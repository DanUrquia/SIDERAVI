import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'mission_map_config.dart';

/// The three local markers available from Send Ping.
enum DemoPingType {
  location('Location Ping'),
  item('Item Ping'),
  danger('Danger Ping');

  const DemoPingType(this.label);

  final String label;
}

/// A demo point annotated by the current astronaut.
final class DemoPing {
  /// Records the selected ping kind at a local grid position.
  const DemoPing(this.type, this.position);

  final DemoPingType type;
  final Offset position;
}

/// Identifies the writer responsible for an actual simulated position change.
enum NavigationPositionSource {
  pedestrianDeadReckoning,
  demoMovement,
  firebaseRestore,
  localPositionRestore,
  expeditionStart,
  localNavigation,
}

enum NavigationState {
  noDestination,
  destinationSelected,
  navigatingToDestination,
  navigatingToBase,
  positionUncertain,
  arrivedAtDestination,
  arrivedAtBase,
  paused,
}

/// Owns route guidance independently of the writer for the mission position.
final class DemoNavigation extends ChangeNotifier {
  /// Initializes at the mission's configured astronaut position.
  DemoNavigation(this.map, {bool startAtBase = false})
    : _position = startAtBase ? map.base : map.start;

  final MissionMapConfig map;
  static const returnThresholdMeters = 100.0;
  static const _arrivalRadius = 8.0;
  final List<DemoPing> _pings = [];
  Offset _position;
  NavigationPositionSource _positionSource =
      NavigationPositionSource.localNavigation;
  Offset? _target;
  Offset? _rescueWaypoint;
  String? _targetLabel;
  double? _heading;
  bool _started = false;
  bool _paused = false;
  bool _sos = false;
  bool _acceptsDemoMovement = true;
  bool _liveArrived = false;
  int _liveArrivalCount = 0;

  Offset get position => _position;
  NavigationPositionSource get positionSource => _positionSource;
  bool get rescuing => _rescueWaypoint != null;
  Offset? get target => _rescueWaypoint ?? _target;
  String? get targetLabel => rescuing ? 'Rescue waypoint' : _targetLabel;
  bool get paused => _paused;
  bool get sos => _sos;
  double? get heading => _heading;
  List<DemoPing> get pings => List.unmodifiable(_pings);
  bool get live => !_acceptsDemoMovement;
  bool get guiding => rescuing || _started;
  bool get moving => _acceptsDemoMovement && _started && !_paused && !_sos;
  bool get arrived =>
      !rescuing &&
      (live ? _liveArrived : _target != null && _position == _target);
  int get liveArrivalCount => _liveArrivalCount;
  bool get targetsBase => !rescuing && _target == map.base;
  Offset? get routeTarget => arrived ? null : target;
  double? get remainingMeters => target == null ? null : distanceTo(target!);
  double get baseDistanceMeters => distanceTo(map.base);
  bool get canNavigate =>
      !rescuing &&
      _target != null &&
      !arrived &&
      !_started &&
      !_paused &&
      !_sos;
  bool get canReturnToBase =>
      !rescuing &&
      !_sos &&
      !(_started && targetsBase) &&
      baseDistanceMeters - returnThresholdMeters > .000001;
  bool get atBase => _position == map.base;

  NavigationState state({bool positionCertain = true}) =>
      switch ((_paused, arrived, _started, _target)) {
        (true, _, _, _) => NavigationState.paused,
        (_, true, _, _) =>
          targetsBase
              ? NavigationState.arrivedAtBase
              : NavigationState.arrivedAtDestination,
        (_, _, _, _) when live && !positionCertain =>
          NavigationState.positionUncertain,
        (_, _, true, _) =>
          targetsBase
              ? NavigationState.navigatingToBase
              : NavigationState.navigatingToDestination,
        (_, _, _, null) => NavigationState.noDestination,
        _ => NavigationState.destinationSelected,
      };

  String get status => statusFor();

  String statusFor({bool positionCertain = true}) => _sos
      ? 'Demo SOS active'
      : switch (state(positionCertain: positionCertain)) {
          NavigationState.noDestination => 'Awaiting destination',
          NavigationState.destinationSelected => 'Destination selected',
          NavigationState.navigatingToDestination => 'Navigating',
          NavigationState.navigatingToBase =>
            live ? 'Navigating to base' : 'Navigating',
          NavigationState.positionUncertain =>
            guiding
                ? 'Position uncertain · Paused'
                : 'Live Sensors · Position uncertain',
          NavigationState.arrivedAtDestination =>
            live ? 'Arrived at destination' : 'Arrived',
          NavigationState.arrivedAtBase =>
            live ? 'Arrived at Habitat Base' : 'Arrived',
          NavigationState.paused => 'Paused',
        };

  /// Calculates the straight-line surface distance on the Mars sphere.
  double distanceTo(Offset point) => map.coordinates.distance(position, point);

  /// Selects a valid destination and stops the previous route.
  bool select(Offset point, String label) {
    if (_sos || rescuing || !point.isFinite || !map.contains(point)) {
      return false;
    }
    _setTarget(point, label);
    notifyListeners();
    return true;
  }

  /// Updates the bearing clockwise from demo north whenever a target changes.
  void _setTarget(Offset point, String label) {
    _started = false;
    _liveArrived = false;
    _target = point;
    _targetLabel = label;
    final delta = point - position;
    if (delta != Offset.zero) {
      _heading = (math.atan2(delta.dx, -delta.dy) * 180 / math.pi + 360) % 360;
    }
  }

  /// Starts guidance or the explicitly selected demo animation.
  void start({bool instant = false}) {
    if (!canNavigate) return;
    _startRoute(instant);
    notifyListeners();
  }

  /// Cancels an active demo leg when live sensors own the position.
  void enableDemoMovement(bool enabled) {
    if (_acceptsDemoMovement == enabled) return;
    _acceptsDemoMovement = enabled;
    _started = false;
    _liveArrived = false;
    notifyListeners();
  }

  /// Updates the shared simulated coordinate without restarting a demo leg.
  void setTrackedPosition(
    Offset point, {
    NavigationPositionSource source = NavigationPositionSource.localNavigation,
  }) {
    if (live && source == NavigationPositionSource.firebaseRestore) {
      return;
    }
    if (_position == point) return;
    _updatePosition(point, source);
    if (!live) _started = false;
    notifyListeners();
  }

  /// Updates the estimate from one accepted native step interval.
  void applyStepPosition(Offset point) {
    if (!live || paused || sos || point == position) return;
    _updatePosition(point, NavigationPositionSource.pedestrianDeadReckoning);
    if (!rescuing && _started && remainingMeters! <= _arrivalRadius) {
      _liveArrived = true;
      _liveArrivalCount++;
      _started = false;
    }
    notifyListeners();
  }

  /// Starts a new exploration from the mission's shared Habitat Base.
  void startNewExpedition() {
    _updatePosition(map.base, NavigationPositionSource.expeditionStart);
    _target = null;
    _targetLabel = null;
    _heading = null;
    _started = false;
    _paused = false;
    _liveArrived = false;
    notifyListeners();
  }

  /// Gives shared assistance priority over an optional local destination.
  void setRescueWaypoint(Offset? waypoint) {
    if (waypoint == _rescueWaypoint) return;
    _rescueWaypoint = waypoint;
    notifyListeners();
  }

  /// Selects base and starts a fresh return route.
  void returnToBase({bool instant = false}) {
    if (_sos || rescuing || (live && !canReturnToBase)) return;
    if (_acceptsDemoMovement) _paused = false;
    _setTarget(map.base, 'Habitat base');
    _startRoute(instant);
    notifyListeners();
  }

  /// Applies the motion preference when starting a leg.
  void _startRoute(bool instant) {
    if (!live && instant) {
      _updatePosition(_target!, NavigationPositionSource.demoMovement);
    }
    _started = !arrived;
  }

  /// Suspends or resumes exploration without losing the current route.
  void togglePause() {
    if (_sos) return;
    _paused = !_paused;
    notifyListeners();
  }

  /// Advances a linear leg by elapsed time and snaps exactly at arrival.
  void advance(Duration elapsed) {
    if (!moving || elapsed <= Duration.zero) return;
    final target = _target!;
    final delta = target - position;
    final step =
        elapsed.inMicroseconds /
        Duration.microsecondsPerSecond *
        map.demoMetersPerSecond;
    final remaining = distanceTo(target);
    if (remaining <= step) {
      _updatePosition(target, NavigationPositionSource.demoMovement);
      _started = false;
    } else {
      _updatePosition(
        position + delta * (step / remaining),
        NavigationPositionSource.demoMovement,
      );
    }
    notifyListeners();
  }

  void _updatePosition(Offset point, NavigationPositionSource source) {
    _position = point;
    _positionSource = source;
  }

  /// Places a local marker at the destination or the current position.
  void addPing(DemoPingType type, {Offset? at}) {
    if (_sos) return;
    final point = at ?? _target ?? position;
    _pings.removeWhere((ping) => ping.position == point && ping.type == type);
    if (_pings.length == 12) _pings.removeAt(0);
    _pings.add(DemoPing(type, point));
    notifyListeners();
  }

  /// Activates a local emergency state and pauses the current route.
  void activateSos() {
    if (_sos) return;
    _paused = true;
    _sos = true;
    notifyListeners();
  }

  /// Clears the emergency while leaving exploration paused for manual resume.
  void cancelSos() {
    if (!_sos) return;
    _sos = false;
    notifyListeners();
  }
}

/// Rounds navigation readouts to the nearest ten demo meters.
String formatDemoDistance(double meters) {
  final rounded = (meters / 10).round() * 10;
  if (rounded >= 1000) return '${(rounded / 1000).toStringAsFixed(2)} km';
  return '$rounded m';
}

String formatNavigationDistance(double meters, {required bool live}) =>
    live && meters < 1000 ? '${meters.round()} m' : formatDemoDistance(meters);
