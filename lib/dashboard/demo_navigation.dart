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
  coreLocation,
  demoMovement,
  firebaseRestore,
  localNavigation,
}

/// Owns one mission's offline position, route, pings, and demonstration SOS.
final class DemoNavigation extends ChangeNotifier {
  /// Initializes at the mission's configured astronaut position.
  DemoNavigation(this.map, {bool startAtBase = false})
    : _position = startAtBase ? map.base : map.start;

  final MissionMapConfig map;
  final List<DemoPing> _pings = [];
  Offset _position;
  NavigationPositionSource _positionSource =
      NavigationPositionSource.localNavigation;
  Offset? _target;
  String? _targetLabel;
  double? _heading;
  bool _started = false;
  bool _paused = false;
  bool _sos = false;
  bool _acceptsDemoMovement = true;

  Offset get position => _position;
  NavigationPositionSource get positionSource => _positionSource;
  Offset? get target => _target;
  String? get targetLabel => _targetLabel;
  bool get paused => _paused;
  bool get sos => _sos;
  double? get heading => _heading;
  List<DemoPing> get pings => List.unmodifiable(_pings);
  bool get moving => _acceptsDemoMovement && _started && !_paused && !_sos;
  bool get arrived => _target != null && _position == _target;
  bool get canNavigate =>
      _acceptsDemoMovement &&
      _target != null &&
      !arrived &&
      !moving &&
      !_paused &&
      !_sos;
  bool get atBase => _position == map.base;

  /// Describes the current route independently from the exploration status.
  String get status {
    if (_sos) return 'Demo SOS active';
    if (_paused) return 'Paused';
    if (moving) return 'Navigating';
    if (arrived) return 'Arrived';
    return _target == null ? 'Awaiting destination' : 'Destination selected';
  }

  /// Calculates the straight-line surface distance on the Mars sphere.
  double distanceTo(Offset point) => map.coordinates.distance(position, point);

  /// Selects a valid destination and stops the previous route.
  bool select(Offset point, String label) {
    if (_sos || !map.contains(point)) return false;
    _setTarget(point, label);
    notifyListeners();
    return true;
  }

  /// Updates the bearing clockwise from demo north whenever a target changes.
  void _setTarget(Offset point, String label) {
    _started = false;
    _target = point;
    _targetLabel = label;
    final delta = point - position;
    if (delta != Offset.zero) {
      _heading = (math.atan2(delta.dx, -delta.dy) * 180 / math.pi + 360) % 360;
    }
  }

  /// Starts a selected route, snapping to its destination with reduced motion.
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
    notifyListeners();
  }

  /// Updates the shared simulated coordinate without restarting a demo leg.
  void setTrackedPosition(
    Offset point, {
    NavigationPositionSource source = NavigationPositionSource.localNavigation,
  }) {
    if (_position == point) return;
    _updatePosition(point, source);
    _started = false;
    notifyListeners();
  }

  /// Selects base and starts a fresh return route.
  void returnToBase({bool instant = false}) {
    if (_sos) return;
    if (_acceptsDemoMovement) _paused = false;
    _setTarget(map.base, 'Habitat base');
    if (_acceptsDemoMovement) _startRoute(instant);
    notifyListeners();
  }

  /// Applies the motion preference when starting a leg.
  void _startRoute(bool instant) {
    if (instant) {
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
  void addPing(DemoPingType type) {
    if (_sos) return;
    final point = _target ?? position;
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
