import 'package:flutter/foundation.dart';

import '../missions/mission.dart';
import 'astronaut.dart';

/// Holds the active astronaut and mission in memory for the current app run.
final class MissionSession extends ChangeNotifier {
  Astronaut? _astronaut;
  MarsMission? _mission;

  /// Identifies the signed-in astronaut, if a mission session is open.
  Astronaut? get astronaut => _astronaut;

  /// The mission confirmed by the current astronaut.
  MarsMission? get mission => _mission;

  /// Records a confirmed mission only while an astronaut is signed in.
  void selectMission(MarsMission mission) {
    if (_astronaut == null || _mission == mission) return;
    _mission = mission;
    notifyListeners();
  }

  /// Opens a session once and rejects overlapping mission launches.
  bool begin(Astronaut astronaut) {
    if (_astronaut != null) return false;
    _astronaut = astronaut;
    notifyListeners();
    return true;
  }

  /// Clears the astronaut and mission when the user returns to login.
  void end() {
    if (_astronaut == null) return;
    _astronaut = null;
    _mission = null;
    notifyListeners();
  }
}
