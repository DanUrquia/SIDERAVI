import 'package:flutter/material.dart';

import 'auth/astronaut.dart';
import 'auth/mission_session.dart';
import 'ui/mission_login.dart';
import 'ui/mission_theme.dart';
import 'ui/mission_welcome.dart';

/// Hosts the mission theme and owns the astronaut session.
class MissionApp extends StatefulWidget {
  /// Creates the SIDERA VI application.
  const MissionApp({super.key});

  @override
  State<MissionApp> createState() => _MissionAppState();
}

/// Coordinates the single login-to-welcome navigation and session lifetime.
class _MissionAppState extends State<MissionApp> {
  final _session = MissionSession();

  /// Closes the session when the welcome route is dismissed.
  Future<void> _openMission(BuildContext context, Astronaut astronaut) async {
    if (!_session.begin(astronaut)) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: reducedMotion
              ? Duration.zero
              : MissionWelcome.loginFadeDuration,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              MissionWelcome(
                key: ValueKey(astronaut.id),
                astronaut: astronaut,
                onReturn: () => Navigator.of(context).pop(),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
                child: child,
              ),
        ),
      );
    } finally {
      if (mounted) _session.end();
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIDERA VI',
      debugShowCheckedModeBanner: false,
      theme: MissionTheme.dark,
      home: Builder(
        builder: (context) => MissionLogin(
          onAuthenticated: (astronaut) => _openMission(context, astronaut),
        ),
      ),
    );
  }
}
