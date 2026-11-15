import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../dashboard/demo_navigation.dart';
import '../sensors/earth_fix.dart';
import '../sensors/sensor_measurements.dart';
import '../sensors/sensor_service.dart';
import 'live_movement.dart';
import 'mission_presence.dart';
import 'movement_telemetry.dart';
import 'tracking_geometry.dart';

/// Owns local sensor state for one dashboard, independently of the network.
final class AstronautTracking extends ChangeNotifier {
  AstronautTracking({
    required this.navigation,
    required this.coordinates,
    required this.sensors,
    this.clock = DateTime.now,
  }) {
    _lastPosition = navigation.position;
    _lastRoute = _routeState;
    navigation.addListener(_navigationChanged);
  }

  final DemoNavigation navigation;
  final MissionCoordinates coordinates;
  final SensorService sensors;
  final DateTime Function() clock;
  final heading = ValueNotifier<double?>(null);
  final telemetry = MovementTelemetry();

  static const _interval = Duration(milliseconds: 100);
  final _movement = LiveMovement();
  late Offset _lastPosition;
  late ({Offset? target, bool moving, bool paused, bool sos}) _lastRoute;
  ConnectionStatus _connection = ConnectionStatus.offline;
  int _locationEpoch = 0;
  bool _restoreReviewed = false;
  bool _positionChanged = false;
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _reading = false;
  bool _active = false;
  bool _disposed = false;
  bool _paused = false;
  int _epoch = 0;
  double? _reference;
  double? _lastMotionTime;
  double _motionStarted = 0;
  double? _resumeHeading;
  String? _frame;
  bool _confirmed = false;

  TrackingMode mode = TrackingMode.demo;
  PositionQuality quality = PositionQuality.simulated;
  bool follow = false;

  /// Supplies synchronization with the simulated state and no private readings.
  AstronautPose get pose => (
    mars: coordinates.toMars(navigation.position),
    heading: heading.value,
    mode: mode,
    quality: quality,
  );

  /// Restores a previously shared pose once, before the astronaut moves locally.
  void restore(AstronautPose previous) {
    final before = pose.mars;
    final atInitialBase =
        navigation.atBase && !_positionChanged && !navigation.moving;
    final outcome = _restoreReviewed
        ? 'alreadyReviewed'
        : !atInitialBase
        ? 'localPositionInUse'
        : coordinates.distance(
                navigation.position,
                coordinates.toGrid(previous.mars),
              ) <
              .00001
        ? 'alreadyAtSavedPosition'
        : 'applied';
    _restoreReviewed = true;
    telemetry.event(clock(), 'firebaseRestore', {
      'outcome': outcome,
      'before': marsPosition(before),
      'saved': marsPosition(previous.mars),
    });
    if (outcome != 'applied') return;
    _resetEarth('firebaseRestore');
    navigation.setTrackedPosition(
      coordinates.toGrid(previous.mars),
      source: NavigationPositionSource.firebaseRestore,
    );
  }

  bool get requiresRebaseline => _movement.requiresRebaseline;

  /// Allows the next fresh Earth fix to set a baseline without moving the marker.
  void rebaseline() {
    if (mode != TrackingMode.live || _disposed) return;
    _movement.rebaseline(_seconds);
    _resetEarth('operatorRebaseline');
    notifyListeners();
  }

  /// Opens an opt-in timeline for the current mission dashboard.
  void startCapture(String mission) => telemetry.start(clock(), {
    'mission': mission,
    'mode': mode.name,
    'quality': quality.name,
    'connection': _connection.name,
    'position': marsPosition(pose.mars),
    'requiresRebaseline': requiresRebaseline,
  });

  /// Freezes the capture and opens the native local report export.
  Future<void> exportCapture() {
    telemetry.stop(clock());
    return sensors.command('exportMovement', telemetry.export());
  }

  /// Records connectivity transitions without changing either tracking baseline.
  void noteConnection(ConnectionStatus status) {
    if (status == _connection) return;
    telemetry.event(clock(), 'connectionChanged', {
      'from': _connection.name,
      'to': status.name,
      'position': marsPosition(pose.mars),
    });
    _connection = status;
  }

  /// Starts Core Motion now and location only if live mode was selected.
  Future<void> resume() {
    if (_active || _disposed) return _pending;
    _active = true;
    _resumeHeading = heading.value;
    _reference = null;
    _lastMotionTime = null;
    _motionStarted = _seconds;
    _resetEarth('foregroundResume');
    final epoch = ++_epoch;
    _timer = Timer.periodic(_interval, (_) => _poll());
    return _queue(() async {
      if (!_current(epoch)) return;
      await sensors.command('startMotion');
      if (_current(epoch) && mode == TrackingMode.live) {
        await sensors.command('startLocation');
      }
    });
  }

  /// Stops both sensors before another foreground route acquires the bridge.
  Future<void> suspend() {
    if (!_active) return _pending;
    _active = false;
    _epoch++;
    _timer?.cancel();
    _resetEarth('foregroundSuspend');
    return _queue(() => sensors.command('stop'));
  }

  /// Changes the movement source without changing the position on the map.
  Future<void> selectMode(TrackingMode next) {
    if (_disposed || mode == next) return _pending;
    final previous = mode;
    mode = next;
    telemetry.event(clock(), 'modeChanged', {
      'from': previous.name,
      'to': next.name,
      'position': marsPosition(pose.mars),
    });
    navigation.enableDemoMovement(next == TrackingMode.demo);
    _resetEarth('modeChanged');
    notifyListeners();
    final epoch = _epoch;
    return _queue(() async {
      if (!_current(epoch) || mode != next) return;
      await sensors.command(
        next == TrackingMode.live ? 'startLocation' : 'stopLocation',
      );
    });
  }

  /// Makes the current screen-top direction the mission reference.
  Future<void> calibrate() {
    final epoch = _epoch;
    return _queue(() async {
      if (!_current(epoch)) return;
      await sensors.command('clearMotion');
      if (!_current(epoch)) return;
      _reference = null;
      _resumeHeading = null;
      heading.value = null;
    });
  }

  /// Enables or disables recentering without changing zoom.
  void setFollow(bool value) {
    if (follow == value) return;
    follow = value;
    notifyListeners();
  }

  /// Reads a single batch at a time and drops callbacks from an old route.
  void _poll() {
    if (_reading || !_active) return;
    _reading = true;
    final epoch = _epoch;
    unawaited(
      _queue(() async {
        try {
          if (!_current(epoch)) return;
          final locationEpoch = _locationEpoch;
          final batch = await sensors.snapshot();
          if (!_current(epoch)) return;
          final now = _seconds;
          telemetry.updateCapabilities(batch);
          _orientation(batch['orientations'] as List? ?? const [], now);
          if (mode == TrackingMode.live && locationEpoch == _locationEpoch) {
            _location(batch, now);
          } else {
            _recordRejected(batch, MovementReason.inactive);
          }
        } finally {
          _reading = false;
        }
      }),
    );
  }

  /// Keeps the last reference through angle wraparound and handles interface flips.
  void _orientation(List samples, double now) {
    for (final sample in samples.whereType<Map>()) {
      final time = finiteReading(sample, 'time');
      final yaw = finiteReading(sample, 'yaw');
      if (time == null ||
          now - time > 2 ||
          time > now + 1 ||
          (_lastMotionTime != null && time <= _lastMotionTime!)) {
        continue;
      }
      final frame = sample['frame'];
      if (frame != _frame) {
        if (_frame != null) {
          _reference = null;
          _resumeHeading = null;
        }
        _frame = frame as String?;
      }
      if (yaw == null) continue;
      _lastMotionTime = time;
      _reference ??= yaw - (_resumeHeading ?? 0);
      _resumeHeading = null;
      heading.value = signedTurn(yaw - _reference!);
    }
    final recent = _lastMotionTime ?? _motionStarted;
    if (now - recent > 2) heading.value = null;
  }

  /// Applies only approved Earth steps to the simulated Mars pose.
  void _location(Map batch, double now) {
    final authorization = batch['authorization'];
    if (_paused) {
      _recordRejected(batch, MovementReason.inactive);
      _setQuality(PositionQuality.paused);
      return;
    }
    if (batch['services'] == false ||
        authorization == 'Denied' ||
        authorization == 'Restricted' ||
        (authorization == 'Authorized' && batch['precise'] != true)) {
      if (quality != PositionQuality.unavailable) {
        _resetEarth('locationUnavailable');
      }
      _recordRejected(batch, MovementReason.unavailable);
      _setQuality(PositionQuality.unavailable);
      return;
    }
    final samples = (batch['locations'] as List? ?? const []).whereType<Map>();
    final wasHeld = requiresRebaseline;
    if (samples.isNotEmpty) {
      _confirmed = false;
      for (final sample in samples) {
        final decision = _movement.observe(sample, now);
        telemetry.observation(clock(), sample, decision);
        final step = decision.step;
        if (step == null) continue;
        final displaced = displaceOnMars(pose.mars, step);
        _confirmed = true;
        // Publish the new pose with the matching quality in the same update.
        _setQuality(PositionQuality.accepted);
        navigation.setTrackedPosition(
          coordinates.toGrid(displaced),
          source: NavigationPositionSource.coreLocation,
        );
      }
    }
    final fresh = _movement.fresh(now);
    _setQuality(
      requiresRebaseline
          ? PositionQuality.uncertain
          : _confirmed && fresh
          ? PositionQuality.accepted
          : fresh ||
                samples.isNotEmpty ||
                quality == PositionQuality.uncertain ||
                quality == PositionQuality.accepted
          ? PositionQuality.uncertain
          : PositionQuality.waiting,
    );
    if (wasHeld != requiresRebaseline && !_disposed) notifyListeners();
  }

  /// Includes rejected buffered observations in an active local capture.
  void _recordRejected(Map batch, MovementReason reason) {
    if (!telemetry.recording) return;
    for (final sample
        in (batch['locations'] as List? ?? const []).whereType<Map>()) {
      telemetry.observation(clock(), sample, MovementDecision(reason));
    }
  }

  ({Offset? target, bool moving, bool paused, bool sos}) get _routeState => (
    target: navigation.target,
    moving: navigation.moving,
    paused: navigation.paused,
    sos: navigation.sos,
  );

  void _navigationChanged() {
    final position = navigation.position;
    if (_lastPosition != position) {
      _positionChanged = true;
      telemetry.position(
        clock(),
        navigation.positionSource.name,
        coordinates.toMars(_lastPosition),
        coordinates.toMars(position),
      );
      _lastPosition = position;
    }
    final route = _routeState;
    if (_lastRoute != route) {
      _lastRoute = route;
      telemetry.event(clock(), 'localNavigation', {
        'moving': route.moving,
        'paused': route.paused,
        'sos': route.sos,
        'destination': route.target == null
            ? null
            : marsPosition(coordinates.toMars(route.target!)),
      });
    }
    if (_paused == navigation.paused) return;
    _paused = navigation.paused;
    _resetEarth(_paused ? 'explorationPaused' : 'explorationResumed');
  }

  void _resetEarth(String reason) {
    _locationEpoch++;
    _confirmed = false;
    _movement.reset(_seconds);
    telemetry.event(clock(), 'earthWindowReset', {
      'reason': reason,
      'holdsPosition': requiresRebaseline,
      'position': marsPosition(pose.mars),
    });
    _setQuality(
      mode == TrackingMode.demo
          ? PositionQuality.simulated
          : _paused
          ? PositionQuality.paused
          : requiresRebaseline
          ? PositionQuality.uncertain
          : PositionQuality.waiting,
    );
  }

  void _setQuality(PositionQuality value) {
    if (quality == value) return;
    quality = value;
    if (!_disposed) notifyListeners();
  }

  double get _seconds => clock().microsecondsSinceEpoch / 1000000;

  bool _current(int epoch) => _active && !_disposed && epoch == _epoch;

  /// Keeps all sensor commands and snapshot reads ordered across lifecycle changes.
  Future<void> _queue(Future<void> Function() operation) =>
      _pending = _pending.then((_) async {
        try {
          await operation();
        } catch (_) {
          if (_active && !_disposed && mode == TrackingMode.live) {
            _setQuality(PositionQuality.unavailable);
          }
        }
      });

  @override
  void dispose() {
    _disposed = true;
    navigation.removeListener(_navigationChanged);
    unawaited(suspend());
    heading.dispose();
    telemetry.dispose();
    super.dispose();
  }
}
