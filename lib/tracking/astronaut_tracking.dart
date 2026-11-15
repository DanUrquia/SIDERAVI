import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../dashboard/demo_navigation.dart';
import '../sensors/earth_fix.dart';
import '../sensors/sensor_measurements.dart';
import '../sensors/sensor_service.dart';
import 'android_walking_fallback.dart';
import 'live_movement.dart';
import 'mission_presence.dart';
import 'movement_telemetry.dart';
import 'pedometer_monitor.dart';
import 'step_navigation.dart';
import 'tracking_geometry.dart';

/// Owns local sensor state for one dashboard, independently of the network.
final class AstronautTracking extends ChangeNotifier {
  AstronautTracking({
    required this.navigation,
    required this.coordinates,
    required this.sensors,
    this.clock = DateTime.now,
    this.astronautId,
    this.automaticPhysical = false,
    this.missionId,
  }) {
    if (automaticPhysical) {
      mode = TrackingMode.live;
      quality = PositionQuality.waiting;
      measuredSteps = 0;
      navigation.enableDemoMovement(false);
    }
    _lastPosition = navigation.position;
    _lastRoute = _routeState;
    navigation.addListener(_navigationChanged);
    _localState = Future.wait<void>([
      if (astronautId != null) _loadStride(),
      if (_positionScope != null) _loadPosition(),
    ]);
  }

  final DemoNavigation navigation;
  final MissionCoordinates coordinates;
  final SensorService sensors;
  final DateTime Function() clock;
  final String? astronautId;
  final bool automaticPhysical;
  final String? missionId;
  late final Future<List<void>> _localState;
  final heading = ValueNotifier<double?>(null);
  final telemetry = MovementTelemetry();
  final pedometer = PedometerMonitor();

  static const _interval = Duration(milliseconds: 100);
  final _movement = LiveMovement();
  final _steps = StepNavigation();
  final _androidWalking = AndroidWalkingFallback();
  late Offset _lastPosition;
  late ({Offset? target, bool moving, NavigationState state, bool sos})
  _lastRoute;
  ConnectionStatus _connection = ConnectionStatus.offline;
  int _locationEpoch = 0;
  bool _restoreReviewed = false;
  bool _positionChanged = false;
  double _demoDistance = 0;
  double _stepDistance = 0;
  double? _lastAppliedStep;
  late String _shownStepStatus = stepStatus;
  int _strideRevision = 0;
  int? measuredSteps;
  int appliedSteps = 0;
  String? lastUnappliedSteps;
  bool hasWalkingCalibration = false;
  Timer? _timer;
  Future<void> _pending = Future.value();
  Future<void>? _finishingCapture;
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
  double? _lastYaw;
  double? _lastValidYawTime;
  double? _requiredStepStart;

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
        (mode == TrackingMode.demo || automaticPhysical) &&
        navigation.atBase &&
        !_positionChanged &&
        !navigation.guiding;
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
      allowLiveRestore: automaticPhysical,
    );
    unawaited(_savePosition());
  }

  String? get _positionScope =>
      automaticPhysical && missionId != null && astronautId != null
      ? '$missionId/$astronautId'
      : null;

  Future<void> _loadPosition() async {
    try {
      final saved = await sensorDiagnosticsChannel.invokeListMethod<double>(
        'readMissionPosition',
        _positionScope,
      );
      if (_disposed || _positionChanged || saved == null || saved.length != 2) {
        return;
      }
      final mars = Offset(saved[0], saved[1]);
      if (!mars.isFinite || mars.dx.abs() > 180 || mars.dy.abs() > 90) return;
      _restoreReviewed = true;
      navigation.setTrackedPosition(
        coordinates.toGrid(mars),
        source: NavigationPositionSource.localPositionRestore,
      );
    } on PlatformException {
      // Mission tracking can proceed with the position already in memory.
    } on MissingPluginException {
      // Local pose storage is optional on bridges that do not provide it.
    }
  }

  Future<void> _savePosition() async {
    final scope = _positionScope;
    if (scope == null) return;
    final mars = pose.mars;
    try {
      await sensorDiagnosticsChannel.invokeMethod<void>(
        'writeMissionPosition',
        {
          'scope': scope,
          'mars': [mars.dx, mars.dy],
        },
      );
    } on PlatformException {
      // Keep the latest estimate in memory.
    } on MissingPluginException {
      // Local pose storage is optional on bridges that do not provide it.
    }
  }

  bool get positionCertain => quality == PositionQuality.accepted;
  double get distanceTraveled =>
      mode == TrackingMode.live ? _stepDistance : _demoDistance;
  double get stride => _steps.stride;
  Map<String, Object?>? get androidWalkingEvidence =>
      _androidWalking.evaluating ? _androidWalking.summary : null;
  String get stepSource => switch (pedometer.source) {
    'coreMotionPedometer' => 'Core Motion pedometer',
    'androidStepCounter' => 'Android step counter',
    'androidStepDetector' => 'Android step detector',
    AndroidWalkingFallback.source => 'Android accelerometer · estimated',
    'coreMotionPedometerQuery' => 'Core Motion pedometer · foreground query',
    _ => 'Awaiting a step reading',
  };
  double get _headingMaxAge => automaticPhysical
      ? StepNavigation.headingHoldoverSeconds
      : StepNavigation.maxHeadingAge;

  double? get walkingBearing =>
      _steps.bearingAt(_seconds, maxAge: _headingMaxAge);

  bool get _stepWindowReady {
    final start = pedometer.streamStart;
    final required = _requiredStepStart;
    return start != null &&
        required != null &&
        start + StepNavigation.timestampTolerance >= required;
  }

  bool get canCalibrateWalking =>
      _active &&
      !_paused &&
      mode == TrackingMode.live &&
      (automaticPhysical ||
          (navigation.target != null &&
              navigation.target != navigation.position));

  String get stepStatus {
    if (_paused) return 'Mission paused';
    switch (pedometer.state) {
      case PedometerState.unsupported:
      case PedometerState.denied:
      case PedometerState.restricted:
      case PedometerState.unavailable:
        return pedometer.state.label;
      default:
        break;
    }
    if (automaticPhysical) {
      if (!_steps.calibrated || walkingBearing == null) {
        return 'Walking direction unavailable';
      }
      if (!_stepWindowReady || pedometer.authorization == 'notDetermined') {
        return 'Starting step tracking';
      }
      if (_lastAppliedStep case final last? when _seconds - last <= 3) {
        return 'Steps detected';
      }
      return 'Exploration active';
    }
    if (!_steps.calibrated) return 'Direction calibration needed';
    if (walkingBearing == null) return 'Waiting for device attitude';
    if (_lastAppliedStep case final last? when _seconds - last <= 3) {
      return 'Walking detected';
    }
    return _lastAppliedStep == null ? 'Ready to walk' : 'Waiting for steps';
  }

  Future<void> _loadStride() async {
    final revision = _strideRevision;
    try {
      final stored = await sensorDiagnosticsChannel.invokeMethod<double>(
        'readStrideLength',
        astronautId,
      );
      if (!_disposed &&
          revision == _strideRevision &&
          stored != null &&
          StepNavigation.validStride(stored)) {
        _steps.stride = stored;
        notifyListeners();
      }
    } on PlatformException {
      // The default stride remains available.
    } on MissingPluginException {
      // The default stride remains available.
    }
  }

  Future<bool> saveStride(double value) async {
    if (!StepNavigation.validStride(value) || _disposed) return false;
    _strideRevision++;
    try {
      if (astronautId != null) {
        await sensorDiagnosticsChannel.invokeMethod<void>('writeStrideLength', {
          'astronaut': astronautId,
          'meters': value,
        });
      }
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
    if (!_disposed) {
      _steps.stride = value;
      notifyListeners();
    }
    return true;
  }

  /// Aligns the screen top to map north or to an explicitly confirmed target.
  Future<bool> calibrateWalkingDirection(Offset? destination) async {
    final now = _seconds;
    final yaw = _lastYaw;
    if (!canCalibrateWalking ||
        (destination == null
            ? !automaticPhysical
            : navigation.target != destination ||
                  destination == navigation.position) ||
        yaw == null ||
        now - (_lastValidYawTime ?? 0) > StepNavigation.maxHeadingAge) {
      return false;
    }
    final bearing = destination == null
        ? 0.0
        : initialBearing(pose.mars, coordinates.toMars(destination));
    await _alignWalkingDirection(
      now,
      yaw,
      bearing,
      reference: destination == null
          ? 'manualLocalNorth'
          : 'confirmedDestination',
    );
    return _steps.calibrated && _active;
  }

  Future<void> _alignWalkingDirection(
    double at,
    double yaw,
    double bearing, {
    required String reference,
  }) {
    _steps.calibrate(at, yaw, bearing);
    final restart = _restartStepWindow(at);
    heading.value = signedTurn(bearing);
    hasWalkingCalibration = true;
    _lastAppliedStep = null;
    telemetry.event(clock(), 'walkingDirectionCalibrated', {
      'bearing': bearing,
      'reference': reference,
    });
    notifyListeners();
    return restart;
  }

  Future<void> _restartStepWindow(double at) {
    if (automaticPhysical) _requiredStepStart = at;
    final epoch = _epoch;
    return _queue(() async {
      if (_current(epoch) &&
          mode == TrackingMode.live &&
          (!automaticPhysical || at == _requiredStepStart)) {
        try {
          await sensors.command(
            'restartPedometer',
            automaticPhysical ? at.toString() : null,
          );
        } catch (_) {
          if (automaticPhysical &&
              _current(epoch) &&
              at == _requiredStepStart) {
            _invalidateWalkingDirection();
            heading.value = null;
          }
          rethrow;
        }
      }
    });
  }

  void _invalidateWalkingDirection() {
    _steps.invalidate();
    _requiredStepStart = null;
    _lastAppliedStep = null;
  }

  /// Resets the Earth location baseline used by the opt-in log.
  void rebaseline() {
    if (mode == TrackingMode.live && !_disposed) {
      _movement.rebaseline(_seconds);
      telemetry.event(clock(), 'earthWindowReset', {
        'reason': 'operatorRebaseline',
      });
    }
  }

  /// Opens an opt-in timeline and fresh pedometer window for this capture.
  void startCapture(String mission) {
    if (_finishingCapture != null) return;
    final at = clock();
    pedometer.beginCapture(at.microsecondsSinceEpoch / 1000000);
    telemetry.start(at, {
      'mission': mission,
      'mode': mode.name,
      'quality': quality.name,
      'connection': _connection.name,
      'position': marsPosition(pose.mars),
    });
    if (mode == TrackingMode.live && !automaticPhysical) {
      final epoch = _epoch;
      unawaited(
        _queue(() async {
          if (_current(epoch) && mode == TrackingMode.live) {
            await sensors.command('restartPedometer');
          }
        }),
      );
    }
  }

  /// Ends recording and checks the current window once if the stream supplied no totals.
  Future<void> stopCapture() =>
      _finishingCapture ??= _finishCapture().whenComplete(() {
        _finishingCapture = null;
      });

  Future<void> _finishCapture() async {
    if (!telemetry.recording) return;
    final start = pedometer.endCapture();
    final stopped = clock();
    if (start != null &&
        _active &&
        mode == TrackingMode.live &&
        pedometer.stepSupported &&
        pedometer.authorization == 'authorized' &&
        pedometer.captureSteps == null) {
      final epoch = _epoch;
      await _queue(() async {
        Map result = {'outcome': 'unavailable'};
        try {
          if (_current(epoch) && mode == TrackingMode.live) {
            await sensors
                .command(
                  'finishPedometerCapture',
                  jsonEncode({
                    'start': start,
                    'end': stopped.microsecondsSinceEpoch / 1000000,
                  }),
                )
                .timeout(const Duration(seconds: 8));
            if (!_current(epoch)) return;
            final locationEpoch = _locationEpoch;
            final batch = await sensors.snapshot();
            if (!_current(epoch)) return;
            final motion = batch['pedometer'];
            final query = motion is Map ? motion['captureQuery'] : null;
            if (query is Map) result = query;
            _ingest(batch, locationEpoch);
          }
        } catch (_) {
          // The live sensor state remains independent of the optional query.
        }
        if (_disposed) return;
        pedometer.applyCaptureQuery(result);
        telemetry.event(clock(), 'pedometerCaptureQuery', {
          ...pedometer.captureQuery!,
          'appliedMarsMeters': 0,
        });
      });
    }
    if (_disposed) return;
    telemetry.event(clock(), 'pedometerCaptureEnded', {
      'steps': pedometer.captureSteps,
      'estimatedDistanceMeters': pedometer.captureDistance,
    });
    telemetry.stop(clock());
  }

  /// Freezes the capture and opens the native local report export.
  Future<void> exportCapture() async {
    await stopCapture();
    if (!_disposed) await sensors.command('exportMovement', telemetry.export());
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

  /// Restarts foreground attitude and, in Live Sensors, native step collection.
  Future<void> resume() {
    if (_active || _disposed) return _pending;
    _active = true;
    _resumeHeading = heading.value;
    _reference = null;
    _lastMotionTime = null;
    _lastYaw = null;
    _lastValidYawTime = null;
    _invalidateWalkingDirection();
    _motionStarted = _seconds;
    _resetEarth('foregroundResume');
    final epoch = ++_epoch;
    _timer = Timer.periodic(_interval, (_) => _poll());
    return _queue(() async {
      if (!_current(epoch)) return;
      await sensors.command('startMotion');
      if (_current(epoch) && mode == TrackingMode.live) {
        await sensors.command(
          'startLocation',
          automaticPhysical ? 'stepsOnly' : null,
        );
      }
    });
  }

  /// Stops both sensors before another foreground route acquires the bridge.
  Future<void> suspend() {
    if (!_active) return _pending;
    _active = false;
    _epoch++;
    _timer?.cancel();
    _invalidateWalkingDirection();
    _resetEarth('foregroundSuspend');
    return _queue(() => sensors.command('stop'));
  }

  /// Changes the movement source without changing the position on the map.
  Future<void> selectMode(TrackingMode next) {
    if (_disposed || automaticPhysical || mode == next) return _pending;
    final previous = mode;
    mode = next;
    _invalidateWalkingDirection();
    if (next == TrackingMode.live) measuredSteps ??= 0;
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
      telemetry.event(clock(), 'headingCalibrated', {
        'previousRelativeDegrees': heading.value,
        'reference': 'screenTopToMapUp',
        'directionSource': 'deviceAttitude',
      });
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
          await _localState;
          if (!_current(epoch)) return;
          final locationEpoch = _locationEpoch;
          final batch = await sensors.snapshot();
          if (!_current(epoch)) return;
          _ingest(batch, locationEpoch);
        } finally {
          _reading = false;
        }
      }),
    );
  }

  /// Applies one current native snapshot without discarding buffered location fixes.
  void _ingest(Map batch, int locationEpoch) {
    final now = _seconds;
    telemetry.updateCapabilities(batch);
    _orientation(batch['orientations'] as List? ?? const [], now);
    final motion = batch['pedometer'];
    final appliedBefore = appliedSteps;
    pedometer.ingest(
      _androidWalking.read(motion is Map ? motion : null, now),
      now,
      active: mode == TrackingMode.live,
      onSample: (sample) {
        // The old stream may still drain during the asynchronous restart.
        // Its cumulative total can overlap the fresh calibrated window.
        if (automaticPhysical && !_stepWindowReady) return;
        measuredSteps = (measuredSteps ?? 0) + sample.incrementalSteps;
        final displacement = _paused || (!automaticPhysical && _lastYaw == null)
            ? null
            : _steps.displacement(sample, headingMaxAge: _headingMaxAge);
        if (displacement != null) {
          appliedSteps += sample.incrementalSteps;
          _lastAppliedStep = now;
          _setQuality(PositionQuality.accepted);
          navigation.applyStepPosition(
            coordinates.toGrid(displaceOnMars(pose.mars, displacement)),
          );
        } else if (sample.incrementalSteps > 0) {
          lastUnappliedSteps = _paused
              ? 'Mission paused'
              : !_steps.calibrated
              ? 'Direction calibration needed'
              : _steps.bearingAt(sample.end, maxAge: _headingMaxAge) == null
              ? 'No matching attitude'
              : 'Batch overlapped calibration';
        }
        telemetry.pedometer(
          clock(),
          sample,
          relativeHeading: heading.value,
          authorization: pedometer.authorization,
          appliedMeters: displacement?.distance ?? 0,
        );
      },
    );
    if (appliedSteps != appliedBefore) unawaited(_savePosition());
    if (mode == TrackingMode.live && locationEpoch == _locationEpoch) {
      _recordLocation(batch, now);
    } else {
      _recordRejected(batch, MovementReason.inactive);
    }
    if (mode == TrackingMode.live) {
      if (_paused) {
        _setQuality(PositionQuality.paused);
      } else if (pedometer.state == PedometerState.denied ||
          pedometer.state == PedometerState.restricted ||
          pedometer.state == PedometerState.unsupported ||
          pedometer.state == PedometerState.unavailable) {
        _setQuality(PositionQuality.unavailable);
      } else if (quality != PositionQuality.accepted) {
        _setQuality(PositionQuality.waiting);
      }
      final status = stepStatus;
      if (status != _shownStepStatus) {
        _shownStepStatus = status;
        notifyListeners();
      }
    }
  }

  /// Keeps the calibrated reference through short attitude interruptions.
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
      if (frame is String && frame != _frame) {
        if (_frame != null) {
          _reference = null;
          _resumeHeading = null;
          _invalidateWalkingDirection();
          _lastYaw = null;
          _lastValidYawTime = null;
        }
        _frame = frame;
      }
      if (!automaticPhysical &&
          _lastValidYawTime != null &&
          time - _lastValidYawTime! > StepNavigation.maxHeadingAge) {
        _invalidateWalkingDirection();
      }
      _lastMotionTime = time;
      if (yaw == null) {
        if (!automaticPhysical) {
          _lastYaw = null;
          heading.value = null;
        }
        continue;
      }
      _lastYaw = yaw;
      _lastValidYawTime = time;
      _reference ??= yaw - (_resumeHeading ?? 0);
      _resumeHeading = null;
      if (automaticPhysical &&
          !_paused &&
          !_steps.calibrated &&
          (finiteReading(sample, 'rotationRate') ?? 0).abs() <= 45) {
        // The current phone-top direction is the local map-north assumption.
        // Use the attitude's timestamp as the exact native counting boundary.
        unawaited(
          _alignWalkingDirection(
            time.clamp(_motionStarted, now),
            yaw,
            0,
            reference: 'initialLocalNorth',
          ),
        );
      }
      _steps.observe(time, yaw);
      final bearing = _steps.bearingAt(time, maxAge: _headingMaxAge);
      heading.value = automaticPhysical
          ? (bearing == null ? null : signedTurn(bearing))
          : (bearing == null
                ? signedTurn(yaw - _reference!)
                : signedTurn(bearing));
    }
    final recent = _lastValidYawTime ?? _motionStarted;
    if (now - recent > _headingMaxAge) heading.value = null;
  }

  /// Preserves Earth location evidence for the opt-in movement log.
  void _recordLocation(Map batch, double now) {
    if (!telemetry.recording) return;
    final samples = (batch['locations'] as List? ?? const []).whereType<Map>();
    for (final sample in samples) {
      telemetry.observation(clock(), sample, _movement.observe(sample, now));
    }
  }

  /// Includes rejected buffered observations in an active local capture.
  void _recordRejected(Map batch, MovementReason reason) {
    if (!telemetry.recording) return;
    for (final sample
        in (batch['locations'] as List? ?? const []).whereType<Map>()) {
      telemetry.observation(clock(), sample, MovementDecision(reason));
    }
  }

  ({Offset? target, bool moving, NavigationState state, bool sos})
  get _routeState => (
    target: navigation.target,
    moving: navigation.moving,
    state: navigation.state(),
    sos: navigation.sos,
  );

  void _navigationChanged() {
    final position = navigation.position;
    if (_lastPosition != position) {
      _positionChanged = true;
      final source = navigation.positionSource;
      final traveled = coordinates.distance(_lastPosition, position);
      if (source == NavigationPositionSource.demoMovement) {
        _demoDistance += traveled;
      } else if (source == NavigationPositionSource.pedestrianDeadReckoning) {
        _stepDistance += traveled;
      }
      telemetry.position(
        clock(),
        navigation.positionSource.name,
        coordinates.toMars(_lastPosition),
        coordinates.toMars(position),
        remainingMeters: navigation.remainingMeters,
        baseDistanceMeters: navigation.baseDistanceMeters,
      );
      _lastPosition = position;
    }
    final route = _routeState;
    if (_lastRoute != route) {
      _lastRoute = route;
      telemetry.event(clock(), 'localNavigation', {
        'moving': route.moving,
        'paused': navigation.paused,
        'sos': route.sos,
        'state': route.state.name,
        'remainingMeters': navigation.remainingMeters,
        'baseDistanceMeters': navigation.baseDistanceMeters,
        'destination': route.target == null
            ? null
            : marsPosition(coordinates.toMars(route.target!)),
      });
    }
    if (_paused == navigation.paused) return;
    _paused = navigation.paused;
    if (automaticPhysical) {
      _lastAppliedStep = null;
      if (!_paused && _steps.calibrated) {
        unawaited(_restartStepWindow(_seconds));
      }
    } else {
      _invalidateWalkingDirection();
    }
    _resetEarth(_paused ? 'explorationPaused' : 'explorationResumed');
  }

  void _resetEarth(String reason) {
    _locationEpoch++;
    _movement.reset(_seconds);
    telemetry.event(clock(), 'earthWindowReset', {
      'reason': reason,
      'position': marsPosition(pose.mars),
    });
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
            if (!automaticPhysical) _invalidateWalkingDirection();
            _resetEarth('sensorError');
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
    pedometer.dispose();
    telemetry.dispose();
    super.dispose();
  }
}
