import 'dart:ui';

import '../maps/mars_projection.dart';
import 'tracking_geometry.dart';

typedef CrewPin = ({Offset mars, DateTime updated});

enum SosState { active, canceled, resolved }

typedef CrewSos = ({
  String id,
  String sender,
  Offset mars,
  DateTime started,
  SosState state,
  String? finishedBy,
});

typedef CrewSignals = ({Map<String, CrewPin> pins, CrewSos? sos});

enum CrewActionResult { sent, offline, busy, changed, failed }

const crewPinLifetime = Duration(seconds: 60);

/// Only a new accepted displacement that enters the arrival area can resolve SOS.
final class RescueArrival {
  RescueArrival(this.waypoint, Offset position) : _previous = position {
    _outside = distance(position) > radius;
  }

  static const radius = 5.0;
  final Offset waypoint;
  Offset _previous;
  bool _outside = false;
  bool _reached = false;

  double distance(Offset position) =>
      surfaceDistance(position, waypoint, MarsProjection.radiusMeters);

  bool moved(Offset position, {required bool accepted}) {
    if (position == _previous) return false;
    _previous = position;
    if (!accepted) {
      _outside = false;
      _reached = false;
      return false;
    }
    if (distance(position) > radius) {
      _outside = true;
      _reached = false;
      return false;
    }
    _reached |= _outside;
    return _reached;
  }
}
