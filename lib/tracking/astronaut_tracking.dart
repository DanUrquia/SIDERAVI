import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dashboard/demo_navigation.dart';
import '../sensors/earth_fix.dart';
import '../sensors/sensor_measurements.dart';
import '../sensors/sensor_service.dart';
import 'live_movement.dart';
import 'mission_presence.dart';
import 'tracking_geometry.dart';

/// Owns local sensor state for one dashboard, independently of the network.
final class AstronautTracking extends ChangeNotifier {
  AstronautTracking({
    required this.navigation,
    required this.coordinates,
    required this.sensors,
    this.clock = DateTime.now,
  }) {
    navigation.addListener(_navigationChanged);
  }

  final DemoNavigation navigation;
  final MissionCoordinates coordinates;
  final SensorService sensors;
  final DateTime Function() clock;
  final heading = ValueNotifier<double?>(null);

  static const _interval = Duration(milliseconds: 100);
  final _movement = LiveMovement();
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

  /// Restores a previously shared position if this dashboard is still at base.
  void restore(AstronautPose previous) {
    if (!navigation.atBase || navigation.moving) return;
    navigation.setTrackedPosition(coordinates.toGrid(previous.mars));
  }

  /// Starts Core Motion now and location only if live mode was selected.
  Future<void> resume() {
    if (_active || _disposed) return _pending;
    _active = true;
    _resumeHeading = heading.value;
    _reference = null;
    _lastMotionTime = null;
    _motionStarted = _seconds;
    _resetEarth();
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
    _resetEarth();
    return _queue(() => sensors.command('stop'));
  }

  /// Changes the movement source without changing the position on the map.
  Future<void> selectMode(TrackingMode next) {
    if (_disposed || mode == next) return _pending;
    mode = next;
    navigation.enableDemoMovement(next == TrackingMode.demo);
    _resetEarth();
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
          final batch = await sensors.snapshot();
          if (!_current(epoch)) return;
          final now = _seconds;
          _orientation(batch['orientations'] as List? ?? const [], now);
          if (mode == TrackingMode.live) _location(batch, now);
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
      _setQuality(PositionQuality.paused);
      return;
    }
    if (batch['services'] == false ||
        authorization == 'Denied' ||
        authorization == 'Restricted' ||
        (authorization == 'Authorized' && batch['precise'] != true)) {
      _confirmed = false;
      _movement.reset(now);
      _setQuality(PositionQuality.unavailable);
      return;
    }
    final samples = (batch['locations'] as List? ?? const []).whereType<Map>();
    if (samples.isNotEmpty) {
      _confirmed = false;
      for (final sample in samples) {
        final step = _movement.observe(sample, now);
        if (step == null) continue;
        final displaced = displaceOnMars(pose.mars, step);
        _confirmed = true;
        navigation.setTrackedPosition(coordinates.toGrid(displaced));
      }
    }
    final fresh = _movement.fresh(now);
    _setQuality(
      _confirmed && fresh
          ? PositionQuality.accepted
          : fresh ||
                samples.isNotEmpty ||
                quality == PositionQuality.uncertain ||
                quality == PositionQuality.accepted
          ? PositionQuality.uncertain
          : PositionQuality.waiting,
    );
  }

  void _navigationChanged() {
    if (_paused == navigation.paused) return;
    _paused = navigation.paused;
    _resetEarth();
  }

  void _resetEarth() {
    _confirmed = false;
    _movement.reset(_seconds);
    _setQuality(
      mode == TrackingMode.demo
          ? PositionQuality.simulated
          : _paused
          ? PositionQuality.paused
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
    super.dispose();
  }
}
