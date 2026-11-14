import 'package:flutter/foundation.dart';

import 'astronaut.dart';

/// Holds the active astronaut in memory for the current app run.
final class MissionSession extends ChangeNotifier {
  Astronaut? _astronaut;

  /// Identifies the signed-in astronaut, if a mission session is open.
  Astronaut? get astronaut => _astronaut;

  /// Opens a session once and rejects overlapping mission launches.
  bool begin(Astronaut astronaut) {
    if (_astronaut != null) return false;
    _astronaut = astronaut;
    notifyListeners();
    return true;
  }

  /// Clears the astronaut when the user returns to login.
  void end() {
    if (_astronaut == null) return;
    _astronaut = null;
    notifyListeners();
  }
}
