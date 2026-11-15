import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_map_config.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../../missions/mission.dart';
import '../../maps/trek_tile_source.dart';
import '../../sensors/sensor_service.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/firebase_presence.dart';
import '../../tracking/mission_presence.dart';
import '../../tracking/tracking_geometry.dart';
import '../mission_theme.dart';
import '../sensors/sensor_test_screen.dart';
import 'dashboard_actions.dart';
import 'dashboard_panels.dart';
import 'dashboard_style.dart';
import 'demo_terrain_map.dart';
import 'movement_diagnostics.dart';
import 'tracking_controls.dart';

/// Hosts one astronaut's interactive offline mission scenario.
class MissionDashboard extends StatefulWidget {
  /// Opens the selected briefing with a fresh local navigation state.
  const MissionDashboard({
    super.key,
    required this.astronaut,
    required this.mission,
    required this.tileSource,
    this.sensors = const IpadSensorService(),
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final TrekTileSource tileSource;
  final SensorService sensors;

  @override
  State<MissionDashboard> createState() => _MissionDashboardState();
}

/// Coordinates the dashboard's local navigation and foreground animation.
class _MissionDashboardState extends State<MissionDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _view = TerrainViewController();
  final _messages = GlobalKey<ScaffoldMessengerState>();
  late final MissionMapConfig _map;
  late final DemoNavigation _navigation;
  late final Astronaut _teammate;
  late final Ticker _movement;
  late final AstronautTracking _tracking;
  late final MissionPresence _presence;
  final _firebase = FirebasePresenceConfig.fromBuild();
  ConnectPresence? _connect;
  bool _showingDiagnostics = false;
  bool _foreground = true;
  Duration _lastFrame = Duration.zero;

  @override
  void initState() {
    super.initState();
    _map = missionMaps[widget.mission.id]!;
    _teammate = DemoCrew.roster.firstWhere(
      (astronaut) => astronaut.id != widget.astronaut.id,
    );
    _movement = createTicker(_tick);
    _navigation = DemoNavigation(_map, startAtBase: true)
      ..addListener(_syncMovement);
    _tracking = AstronautTracking(
      navigation: _navigation,
      coordinates: MissionCoordinates(widget.mission),
      sensors: widget.sensors,
    );
    _presence = MissionPresence(
      key: (
        mission: widget.mission.id,
        session: _firebase?.session ?? 'local',
        astronaut: widget.astronaut.id,
      ),
      pose: () => _tracking.pose,
      restore: _tracking.restore,
    );
    _navigation.addListener(_presence.pulse);
    _presence.addListener(_noteConnection);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_tracking.resume());
  }

  /// Records connection transitions alongside local movement diagnostics.
  void _noteConnection() => _tracking.noteConnection(_presence.status);

  /// Runs the ticker only while a route is actively moving.
  void _syncMovement() {
    if (_navigation.moving && !_movement.isActive) {
      _lastFrame = Duration.zero;
      _movement.start();
    } else if (!_navigation.moving && _movement.isActive) {
      _movement.stop();
    }
  }

  /// Caps time after a long frame so resuming the app cannot teleport a marker.
  void _tick(Duration elapsed) {
    final delta = elapsed - _lastFrame;
    _lastFrame = elapsed;
    const maxFrame = Duration(milliseconds: 100);
    _navigation.advance(delta > maxFrame ? maxFrame : delta);
  }

  /// Reports a rejected point without disrupting an existing route.
  void _selectDestination(Offset point, String label) {
    if (_navigation.sos) return;
    if (!_navigation.select(point, label)) {
      _notify('Choose a destination inside the exploration boundary.');
    }
  }

  /// Places a marker only if the ping picker was confirmed.
  Future<void> _sendPing() async {
    final type = await chooseDemoPing(context);
    if (!mounted || type == null) return;
    _navigation.addPing(type);
    _notify(
      type == DemoPingType.danger
          ? 'Warning marker placed on this iPad.'
          : '${type.label} placed on this iPad.',
      warning: type == DemoPingType.danger,
    );
  }

  /// Confirms activation and lets the astronaut cancel directly in the dashboard.
  Future<void> _handleSos() async {
    if (_navigation.sos) {
      _navigation.cancelSos();
      return;
    }
    final confirmed = await confirmDemoSos(context);
    if (mounted && confirmed == true) {
      _messages.currentState?.hideCurrentSnackBar();
      _view.reset();
      _navigation.activateSos();
    }
  }

  /// Shows short, accessible feedback above the persistent action row.
  void _notify(String message, {bool warning = false}) {
    final messenger = _messages.currentState;
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: warning ? DashboardStyle.amber : DashboardStyle.text,
          ),
        ),
        backgroundColor: DashboardStyle.inset,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 94),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Hands the native bridge to Sensor Test until its route is closed.
  Future<void> _openDiagnostics() async {
    if (_showingDiagnostics) return;
    _showingDiagnostics = true;
    await _tracking.suspend();
    if (!mounted) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => SensorTestScreen(service: widget.sensors),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    if (!mounted) return;
    _showingDiagnostics = false;
    if (_foreground) unawaited(_tracking.resume());
  }

  /// Authenticates sharing independently of the offline astronaut PIN.
  Future<void> _joinCrew() async {
    final setup = _firebase;
    if (setup == null) return;
    if (_presence.status != ConnectionStatus.offline) {
      _connect = null;
      _presence.suspend();
      return;
    }
    final connect = await showCrewSignIn(context, setup, _presence.key);
    if (!mounted || connect == null) return;
    _connect = connect;
    if (_foreground) _presence.open(connect);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_foreground) return;
      _foreground = false;
      unawaited(_tracking.suspend());
      _presence.suspend();
    } else if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      if (!_showingDiagnostics) unawaited(_tracking.resume());
      if (_connect case final connect?) _presence.open(connect);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigation.removeListener(_presence.pulse);
    _presence.removeListener(_noteConnection);
    _presence.dispose();
    _tracking.dispose();
    _navigation.dispose();
    _movement.dispose();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final astronaut = widget.astronaut;
    final mission = widget.mission;
    return ScaffoldMessenger(
      key: _messages,
      child: Scaffold(
        backgroundColor: DashboardStyle.background,
        body: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: Listenable.merge([_navigation, _tracking, _presence]),
            builder: (context, _) {
              final member = _presence.crew[_teammate.id];
              final fresh = member != null && _presence.isFresh(member);
              final demoPeer =
                  member == null &&
                  _presence.status == ConnectionStatus.offline &&
                  _tracking.mode == TrackingMode.demo;
              final peerPoint = member != null
                  ? _tracking.coordinates.toGrid(member.pose.mars)
                  : demoPeer
                  ? _map.teammate
                  : null;
              final rightPanel = _DashboardSidebar(
                astronaut: astronaut,
                teammate: _teammate,
                mission: mission,
                navigation: _navigation,
                tracking: _tracking,
                teammateStatus: member != null
                    ? fresh
                          ? member.pose.mode.label
                          : 'Last known · offline'
                    : demoPeer
                    ? 'Simulated teammate'
                    : 'Not in session',
                onNavigate: () => _navigation.start(instant: reducedMotion),
                onReturn: () =>
                    _navigation.returnToBase(instant: reducedMotion),
                onTeammate: _navigation.sos || peerPoint == null
                    ? null
                    : () => _selectDestination(peerPoint, _teammate.fullName),
              );
              final map = Stack(
                fit: StackFit.expand,
                children: [
                  DemoTerrainMap(
                    navigation: _navigation,
                    view: _view,
                    mission: mission,
                    tileSource: widget.tileSource,
                    tracking: _tracking,
                    astronautId: astronaut.id,
                    teammateId: _teammate.id,
                    peerPoint: peerPoint,
                    peer: member,
                    peerFresh: fresh,
                    teammateName: _teammate.fullName,
                    onSelect: _selectDestination,
                  ),
                  if (_navigation.sos)
                    Positioned(
                      top: 63,
                      left: 14,
                      right: 14,
                      child: DemoSosBanner(astronautName: astronaut.fullName),
                    ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 13,
                children: [
                  _DashboardHeader(
                    astronaut: astronaut,
                    mission: mission,
                    navigation: _navigation,
                    onBack: () => Navigator.of(context).maybePop(),
                    onDiagnostics: _openDiagnostics,
                  ),
                  TrackingControls(
                    tracking: _tracking,
                    presence: _presence,
                    onJoin: _firebase == null ? null : _joinCrew,
                    onMovementLog: () =>
                        showMovementDiagnostics(context, _tracking, mission.id),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        spacing: 14,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: map),
                          SizedBox(
                            width: (constraints.maxWidth * .34).clamp(
                              245.0,
                              460.0,
                            ),
                            child: rightPanel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  DashboardActions(
                    navigation: _navigation,
                    onPause: _navigation.togglePause,
                    onPing: _sendPing,
                    onSos: _handleSos,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Pairs the active mission and astronaut with an always-visible exit.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.astronaut,
    required this.mission,
    required this.navigation,
    required this.onBack,
    required this.onDiagnostics,
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final DemoNavigation navigation;
  final VoidCallback onBack;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final (label, color) = navigation.sos
        ? ('DEMO SOS', DashboardStyle.danger)
        : navigation.paused
        ? ('PAUSED', DashboardStyle.amber)
        : ('EXPLORING', DashboardStyle.green);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final missionLabel = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Text(
              'MISSION DASHBOARD',
              style: MissionTheme.display(
                11,
                tracking: 1.5,
              ).copyWith(color: DashboardStyle.warm),
            ),
            Text(mission.title, style: MissionTheme.display(24)),
            if (mission.region != mission.title)
              Text(
                mission.region,
                style: const TextStyle(
                  fontSize: 12,
                  color: DashboardStyle.muted,
                ),
              ),
          ],
        );
        return Row(
          spacing: compact ? 10 : 18,
          children: [
            DashboardButton(
              label: 'BACK TO MISSIONS',
              icon: Icons.chevron_left,
              height: 56,
              onPressed: onBack,
            ),
            if (!compact)
              Image.asset(
                'assets/branding/sidera_vi_logo.png',
                width: 124,
                semanticLabel: 'SIDERA VI',
              ),
            Expanded(child: missionLabel),
            Flexible(
              child: DashboardButton(
                label: 'SENSOR TEST',
                icon: Icons.sensors,
                height: 52,
                onPressed: onDiagnostics,
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: DashboardStyle.surface(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          '${astronaut.fullName} — ${astronaut.id}',
                          key: const ValueKey('dashboard-identity'),
                          style: MissionTheme.display(15),
                        ),
                        Text(
                          label,
                          style: MissionTheme.display(
                            11,
                            tracking: .5,
                          ).copyWith(color: color),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keeps essential route controls first in a dedicated, scrollable column.
class _DashboardSidebar extends StatelessWidget {
  const _DashboardSidebar({
    required this.astronaut,
    required this.teammate,
    required this.mission,
    required this.navigation,
    required this.tracking,
    required this.teammateStatus,
    required this.onNavigate,
    required this.onReturn,
    required this.onTeammate,
  });

  final Astronaut astronaut;
  final Astronaut teammate;
  final MarsMission mission;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final String teammateStatus;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback? onTeammate;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: ListView(
      key: const ValueKey('dashboard-information'),
      padding: const EdgeInsets.only(right: 6),
      children: [
        NavigationPanel(
          navigation: navigation,
          tracking: tracking,
          onNavigate: onNavigate,
          onReturn: onReturn,
        ),
        const SizedBox(height: 10),
        PositionPanel(
          astronaut: astronaut,
          navigation: navigation,
          tracking: tracking,
        ),
        const SizedBox(height: 10),
        PlanetaryConditionsPanel(mission: mission, navigation: navigation),
        const SizedBox(height: 10),
        AstronautListPanel(
          astronaut: astronaut,
          teammate: teammate,
          teammateStatus: teammateStatus,
          onSelect: onTeammate,
        ),
        const SizedBox(height: 10),
        DashboardPanel(
          title: 'MISSION OBJECTIVE',
          icon: Icons.flag_outlined,
          children: [
            Text(
              mission.objective,
              style: const TextStyle(color: DashboardStyle.muted),
            ),
          ],
        ),
      ],
    ),
  );
}
