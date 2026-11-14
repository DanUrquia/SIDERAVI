import 'package:flutter/material.dart';

import 'auth/astronaut.dart';
import 'auth/mission_session.dart';
import 'missions/mission.dart';
import 'maps/trek_tile_source.dart';
import 'ui/mission_login.dart';
import 'ui/mission_theme.dart';
import 'ui/mission_welcome.dart';
import 'ui/dashboard/mission_dashboard.dart';
import 'ui/missions/mission_selection.dart';

/// Hosts the mission theme and owns the astronaut session.
class MissionApp extends StatefulWidget {
  /// Creates the SIDERA VI application.
  const MissionApp({super.key, this.tileSource});

  /// Allows an offline tile provider in tests.
  final TrekTileSource? tileSource;

  @override
  State<MissionApp> createState() => _MissionAppState();
}

/// Keeps the session alive across welcome, mission browsing and the dashboard.
class _MissionAppState extends State<MissionApp> {
  final _session = MissionSession();
  late final _tiles = widget.tileSource ?? HttpTrekTileSource();

  /// Opens one authenticated route and clears its session only on logout.
  Future<void> _openMission(BuildContext context, Astronaut astronaut) async {
    if (!_session.begin(astronaut)) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    try {
      await Navigator.of(context).push<void>(
        _fadeRoute(
          duration: reducedMotion
              ? Duration.zero
              : MissionWelcome.loginFadeDuration,
          child: _MissionFlow(
            astronaut: astronaut,
            session: _session,
            tileSource: _tiles,
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
    if (widget.tileSource == null) _tiles.close();
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

/// Fades full-screen routes while leaving their underlying state intact.
Route<void> _fadeRoute({
  required Duration duration,
  required Widget child,
  Duration reverseDuration = Duration.zero,
}) => PageRouteBuilder<void>(
  transitionDuration: duration,
  reverseTransitionDuration: reverseDuration,
  pageBuilder: (context, animation, secondaryAnimation) => child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
        child: child,
      ),
);

/// Replaces welcome with mission selection in the same authenticated route.
class _MissionFlow extends StatefulWidget {
  const _MissionFlow({
    required this.astronaut,
    required this.session,
    required this.tileSource,
  });

  final Astronaut astronaut;
  final MissionSession session;
  final TrekTileSource tileSource;

  @override
  State<_MissionFlow> createState() => _MissionFlowState();
}

/// Keeps mission browsing mounted while the dashboard covers it.
class _MissionFlowState extends State<_MissionFlow> {
  bool _welcomeComplete = false;
  bool _openingDashboard = false;

  /// Swaps out the welcome once its full timeline has completed.
  void _showMissions() {
    if (!ModalRoute.of(context)!.isCurrent) return;
    setState(() => _welcomeComplete = true);
  }

  /// Records the chosen mission and opens its dashboard once.
  Future<void> _startMission(MarsMission mission) async {
    if (_openingDashboard || !ModalRoute.of(context)!.isCurrent) return;
    _openingDashboard = true;
    widget.session.selectMission(mission);
    final duration = _transitionDuration(context);
    try {
      await Navigator.of(context).push<void>(
        _fadeRoute(
          duration: duration,
          reverseDuration: duration,
          child: MissionDashboard(
            astronaut: widget.astronaut,
            mission: mission,
            tileSource: widget.tileSource,
          ),
        ),
      );
    } finally {
      _openingDashboard = false;
    }
  }

  /// Uses a short fade unless the astronaut has enabled Reduce Motion.
  Duration _transitionDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    if (!_welcomeComplete) {
      return MissionWelcome(
        astronaut: widget.astronaut,
        onComplete: _showMissions,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _transitionDuration(context),
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: MissionSelection(
        astronaut: widget.astronaut,
        onBack: () => Navigator.of(context).pop(),
        onStart: _startMission,
      ),
    );
  }
}
