import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_map_config.dart';
import '../../dashboard/mission_checklist.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../../missions/mars_solar_time.dart';
import '../../missions/mission.dart';
import '../../maps/trek_tile_source.dart';
import '../../sensors/sensor_service.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/crew_signals.dart';
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
import 'mobile_navigation.dart';
import 'sos_emergency_dialog.dart';
import 'tracking_controls.dart';
import 'tablet_mission_control.dart';

/// Hosts one astronaut's interactive offline mission scenario.
class MissionDashboard extends StatefulWidget {
  /// Opens the selected briefing with a fresh local navigation state.
  const MissionDashboard({
    super.key,
    required this.astronaut,
    required this.mission,
    required this.tileSource,
    this.sensors = const NativeSensorService(),
    this.clock,
    this.connectPresence,
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final TrekTileSource tileSource;
  final SensorService sensors;
  final DateTime Function()? clock;
  final ConnectPresence? connectPresence;

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
  MissionChecklist? _checklist;
  late final ValueNotifier<MarsSolarCycle> _solarCycle;
  Timer? _solarRefresh;
  MarsCoordinates get _solarLocation =>
      widget.mission.elevation?.location ?? widget.mission.coordinates;
  final _firebase = FirebasePresenceConfig.current;
  static final _shownSos = <SessionKey, String>{};
  CrewSos? _activeSos;
  RescueArrival? _arrival;
  DialogRoute<void>? _sosDialog;
  bool _resolving = false;
  String? _submittedResolution;
  bool _initialized = false;
  bool _showingDiagnostics = false;
  bool _foreground = true;
  Duration _lastFrame = Duration.zero;
  int _announcedArrivals = 0;
  int _revealRescue = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isCompactMission() || _isNativeTablet()) {
      _checklist ??= MissionChecklist(
        '${widget.astronaut.id}/${widget.mission.id}',
      )..load();
    }
    if (_initialized) return;
    _initialized = true;
    _map = missionMaps[widget.mission.id]!;
    _solarCycle = ValueNotifier(_readSolarCycle());
    _startSolarRefresh();
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
      astronautId: widget.astronaut.id,
      missionId: widget.mission.id,
      automaticPhysical: _isCompactMission() || _isNativeTablet(),
      clock: widget.clock ?? DateTime.now,
    );
    _presence = MissionPresence(
      key: (
        mission: widget.mission.id,
        session: _firebase?.session ?? 'field-test-01',
        astronaut: widget.astronaut.id,
      ),
      pose: () => _tracking.pose,
      restore: _tracking.restore,
      clock: widget.clock ?? DateTime.now,
    );
    _navigation.addListener(_presence.pulse);
    _navigation.addListener(_announceArrival);
    _navigation.addListener(_observeRescueStep);
    _presence.addListener(_noteConnection);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_tracking.resume());
    unawaited(_startCrew());
  }

  MarsSolarCycle _readSolarCycle() => MarsSolarCycle.at(
    (widget.clock ?? DateTime.now)(),
    planetocentricLatitude: _solarLocation.latitude,
    eastLongitude: _solarLocation.eastLongitude,
  );

  void _startSolarRefresh() {
    _solarRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      _solarCycle.value = _readSolarCycle();
    });
  }

  bool _isCompactMission() => MediaQuery.sizeOf(context).shortestSide < 600;

  bool _isNativeTablet() =>
      !_isCompactMission() && Theme.of(context).platform == TargetPlatform.iOS;

  /// Records connection transitions alongside local movement diagnostics.
  void _noteConnection() {
    _tracking.noteConnection(_presence.status);
    if (_tracking.automaticPhysical) _updateSos();
  }

  void _updateSos() {
    final incoming = _presence.sos;
    final previous = _activeSos;
    if (incoming == null || incoming.state != SosState.active) {
      if (previous == null) return;
      _activeSos = null;
      _arrival = null;
      _navigation.setRescueWaypoint(null);
      final dialog = _sosDialog;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (dialog != null && dialog.isActive) {
          dialog.navigator?.removeRoute(dialog);
        }
        if (incoming?.id == previous.id) {
          _notify(
            incoming!.state == SosState.resolved
                ? 'Rescue completed by ${incoming.finishedBy}.'
                : 'Crew SOS canceled.',
          );
        }
      });
      return;
    }
    if (incoming.id == previous?.id) return;
    _activeSos = incoming;
    final old = _sosDialog;
    if (previous != null && old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && old.isActive) old.navigator?.removeRoute(old);
      });
    }
    if (incoming.sender == widget.astronaut.id) {
      _arrival = null;
      _navigation.setRescueWaypoint(null);
      return;
    }
    _arrival = RescueArrival(incoming.mars, _tracking.pose.mars);
    _navigation.setRescueWaypoint(_tracking.gridPosition(incoming.mars));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground && _activeSos?.id == incoming.id) {
        _announceSos(incoming);
      }
    });
  }

  void _announceSos(CrewSos event) {
    if (_shownSos[_presence.key] == event.id ||
        _showingDiagnostics ||
        ModalRoute.of(context)?.isActive != true) {
      return;
    }
    _shownSos[_presence.key] = event.id;
    final arrival = _arrival!;
    final senderName = _teammate.id == event.sender
        ? _teammate.fullName
        : event.sender;
    final dialog = DialogRoute<void>(
      context: context,
      barrierColor: SosEmergencyDialog.barrierColor,
      animationStyle: SosEmergencyDialog.animationStyle(context),
      builder: (context) => SosEmergencyDialog.incoming(
        key: const ValueKey('incoming-crew-sos'),
        senderId: event.sender,
        senderName: senderName,
        distance: ListenableBuilder(
          listenable: _navigation,
          builder: (context, _) => Text(
            formatNavigationDistance(
              arrival.distance(_tracking.pose.mars),
              live: true,
            ),
          ),
        ),
        onPrimary: () {
          setState(() => _revealRescue++);
          Navigator.pop(context);
        },
        onSecondary: () => Navigator.pop(context),
      ),
    );
    _sosDialog = dialog;
    unawaited(Navigator.of(context).push(dialog));
  }

  void _observeRescueStep() {
    final event = _activeSos;
    final arrival = _arrival;
    if (event == null || arrival == null) return;
    final captured = _tracking.pose;
    final accepted =
        _navigation.positionSource ==
            NavigationPositionSource.pedestrianDeadReckoning &&
        captured.quality == PositionQuality.accepted;
    if (arrival.moved(captured.mars, accepted: accepted) &&
        !_resolving &&
        _submittedResolution != event.id &&
        _presence.canSendSignals) {
      unawaited(_resolveSos(event, captured));
    }
  }

  Future<void> _resolveSos(CrewSos event, AstronautPose arrival) async {
    _resolving = true;
    try {
      final result = await _presence.finishSos(
        event.id,
        SosState.resolved,
        arrival: arrival,
      );
      if (result == CrewActionResult.sent) _submittedResolution = event.id;
    } finally {
      _resolving = false;
    }
  }

  Future<void> _sendCrewPin() async {
    final target = _navigation.selectedDestination;
    if (target == null || !target.isFinite || !_map.contains(target)) {
      _notify('Select a destination on the map first.');
      return;
    }
    final result = await _presence.sendPin(_map.coordinates.toMars(target));
    if (!mounted) return;
    _notify(switch (result) {
      CrewActionResult.sent => 'Destination shared with Crew.',
      CrewActionResult.offline => 'Connect to Crew to share a PIN.',
      CrewActionResult.busy => 'A Crew update is in progress.',
      _ => 'PIN delivery could not be confirmed.',
    });
  }

  Future<void> _changeSharedSos() async {
    final current = _activeSos;
    if (current != null && current.sender != widget.astronaut.id) {
      _notify('A crew rescue alert is already active.', warning: true);
      return;
    }
    final result = current == null
        ? await _presence.startSos()
        : await _presence.finishSos(current.id, SosState.canceled);
    if (!mounted || result == CrewActionResult.sent) return;
    _notify(switch (result) {
      CrewActionResult.changed => 'Crew SOS changed. Check the current alert.',
      CrewActionResult.offline => 'Connect to Crew to update SOS.',
      CrewActionResult.busy => 'A Crew update is in progress.',
      _ => 'The SOS update could not be confirmed.',
    }, warning: true);
  }

  void _announceArrival() {
    final count = _navigation.liveArrivalCount;
    if (count == _announcedArrivals) return;
    _announcedArrivals = count;
    _notify(
      _navigation.targetsBase
          ? 'You have arrived at Habitat Base.'
          : 'You have arrived at your destination.',
    );
  }

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
  bool _selectDestination(Offset point, String label) {
    if (_navigation.sos || _navigation.rescuing) return false;
    final selected = _navigation.select(point, label);
    if (!selected) {
      _notify('Choose a destination inside the exploration boundary.');
    }
    return selected;
  }

  /// Places a marker only if the ping picker was confirmed.
  Future<void> _sendPing() async {
    final type = await chooseDemoPing(context);
    if (!mounted || type == null) return;
    _placePing(type);
  }

  void _placePing(DemoPingType type, {Offset? at}) {
    if (_navigation.sos) return;
    _navigation.addPing(type, at: at);
    _notify(
      type == DemoPingType.danger
          ? 'Warning marker placed on this device.'
          : '${type.label} placed on this device.',
      warning: type == DemoPingType.danger,
    );
  }

  /// Confirms activation and lets the astronaut cancel directly in the dashboard.
  Future<void> _handleSos() async {
    if (_navigation.sos || await confirmDemoSos(context) == true) {
      if (mounted) _toggleConfirmedSos();
    }
  }

  void _toggleConfirmedSos() {
    if (_navigation.sos) {
      _navigation.cancelSos();
      return;
    }
    _messages.currentState?.hideCurrentSnackBar();
    _view.reset();
    _navigation.activateSos();
  }

  /// Shows short, accessible feedback above the persistent action row.
  void _notify(String message, {bool warning = false}) {
    final messenger = _messages.currentState;
    if (messenger == null) return;
    messenger.clearSnackBars();
    final tablet = _isNativeTablet();
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
        width: tablet ? 380 : null,
        margin: tablet ? null : const EdgeInsets.fromLTRB(18, 0, 18, 94),
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

  /// Starts crew sharing after the local expedition has restored its position.
  Future<void> _startCrew() async {
    final connect = widget.connectPresence ?? _firebase?.connect;
    if (connect == null) return;
    await _tracking.positionReady;
    if (mounted && _foreground) _presence.open(connect);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_foreground) return;
      _foreground = false;
      _solarRefresh?.cancel();
      unawaited(_tracking.suspend());
      _presence.suspend();
    } else if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      _solarCycle.value = _readSolarCycle();
      _startSolarRefresh();
      if (!_showingDiagnostics) unawaited(_tracking.resume());
      unawaited(_startCrew());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _solarRefresh?.cancel();
    _solarCycle.dispose();
    _navigation.removeListener(_presence.pulse);
    _navigation.removeListener(_announceArrival);
    _navigation.removeListener(_observeRescueStep);
    _presence.removeListener(_noteConnection);
    _presence.dispose();
    _checklist?.dispose();
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
    final mobile = _isCompactMission();
    final tablet = _isNativeTablet();
    final sharedDashboard = mobile || tablet;
    final dashboard = ListenableBuilder(
      listenable: Listenable.merge([
        _navigation,
        _tracking,
        _presence,
        if (sharedDashboard) _tracking.pedometer,
      ]),
      builder: (context, _) {
        final shared = _presence.crew[_teammate.id];
        final fresh = shared != null && _presence.isFresh(shared);
        final member =
            sharedDashboard && (!fresh || shared.pose.mode != TrackingMode.live)
            ? null
            : shared;
        final demoPeer =
            !sharedDashboard &&
            member == null &&
            _presence.status == ConnectionStatus.offline &&
            _tracking.mode == TrackingMode.demo;
        final peerPoint = member != null
            ? _tracking.gridPosition(member.pose.mars)
            : demoPeer
            ? _map.teammate
            : null;
        final rightPanel = _DashboardSidebar(
          astronaut: astronaut,
          teammate: _teammate,
          mission: mission,
          navigation: _navigation,
          tracking: _tracking,
          solarCycle: _solarCycle,
          teammateStatus: member != null
              ? fresh
                    ? member.pose.mode.label
                    : 'Last known · offline'
              : demoPeer
              ? 'Simulated teammate'
              : 'Not in session',
          onNavigate: () => _navigation.start(instant: reducedMotion),
          onReturn: () => _navigation.returnToBase(instant: reducedMotion),
          onTeammate: _navigation.sos || peerPoint == null
              ? null
              : () => _selectDestination(peerPoint, _teammate.fullName),
        );
        void movementLog() =>
            showMovementDiagnostics(context, _tracking, mission.id);
        final insets = MediaQuery.viewPaddingOf(context);
        Widget terrain(
          bool showMapHud, [
          VoidCallback? onAstronaut,
          Widget Function(Widget? status, Widget? footer)? layoutHud,
        ]) => DemoTerrainMap(
          navigation: _navigation,
          view: _view,
          mission: mission,
          tileSource: widget.tileSource,
          tracking: _tracking,
          astronautId: astronaut.id,
          teammateId: _teammate.id,
          peerPoint: peerPoint,
          peer: member,
          peerFresh: member != null && fresh,
          sharedPins: sharedDashboard
              ? _presence.pins.map(
                  (id, pin) => MapEntry(id, _tracking.gridPosition(pin.mars)),
                )
              : const {},
          sharedSos: sharedDashboard && _activeSos != null
              ? (
                  sender: _activeSos!.sender,
                  point: _tracking.gridPosition(_activeSos!.mars),
                )
              : null,
          teammateName: _teammate.fullName,
          onSelect: _selectDestination,
          onAstronaut: onAstronaut,
          fullScreen: mobile,
          tabletControls: tablet,
          showMapHud: showMapHud,
          solarCycle: mobile ? _solarCycle : null,
          layoutHud: layoutHud,
          overlayInsets: mobile
              ? EdgeInsets.fromLTRB(
                  insets.left,
                  0,
                  insets.right,
                  MobileNavigation.chromeBottom(context),
                )
              : EdgeInsets.zero,
        );
        if (mobile) {
          return MobileNavigation(
            mapBuilder: terrain,
            solarCycle: _solarCycle,
            view: _view,
            astronaut: astronaut,
            teammate: _teammate,
            mission: mission,
            navigation: _navigation,
            checklist: _checklist!,
            tracking: _tracking,
            presence: _presence,
            member: member,
            peerPoint: peerPoint,
            onBack: () => Navigator.of(context).maybePop(),
            onSelect: _selectDestination,
            onNavigate: () => _navigation.start(instant: reducedMotion),
            onReturn: _navigation.returnToBase,
            onSensorTest: _openDiagnostics,
            onMovementLog: movementLog,
            onPing: () => unawaited(_sendCrewPin()),
            onSos: () => unawaited(_changeSharedSos()),
            revealRescue: _revealRescue,
          );
        }
        if (tablet) {
          return TabletMissionControl(
            map: terrain(true),
            view: _view,
            mission: mission,
            astronaut: astronaut,
            teammate: _teammate,
            navigation: _navigation,
            checklist: _checklist!,
            tracking: _tracking,
            solarCycle: _solarCycle,
            presence: _presence,
            member: member,
            peerPoint: peerPoint,
            revealRescue: _revealRescue,
            onBack: () => Navigator.of(context).maybePop(),
            onSelect: _selectDestination,
            onNavigate: () => _navigation.start(instant: reducedMotion),
            onReturn: _navigation.returnToBase,
            onSensorTest: _openDiagnostics,
            onMovementLog: movementLog,
            onPin: () => unawaited(_sendCrewPin()),
            onSos: () => unawaited(_changeSharedSos()),
          );
        }
        final map = Stack(
          fit: StackFit.expand,
          children: [
            terrain(true),
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
              onMovementLog: movementLog,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  spacing: 14,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: map),
                    SizedBox(
                      width: (constraints.maxWidth * .34).clamp(245.0, 460.0),
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
    );
    return ScaffoldMessenger(
      key: _messages,
      child: Scaffold(
        backgroundColor: DashboardStyle.background,
        resizeToAvoidBottomInset: !mobile,
        body: mobile
            ? dashboard
            : SafeArea(minimum: const EdgeInsets.all(16), child: dashboard),
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
    required this.solarCycle,
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
  final ValueNotifier<MarsSolarCycle> solarCycle;
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
        PlanetaryConditionsPanel(mission: mission, cycle: solarCycle),
        const SizedBox(height: 10),
        AstronautListPanel(
          astronaut: astronaut,
          teammate: teammate,
          teammateStatus: teammateStatus,
          onSelect: onTeammate,
        ),
        const SizedBox(height: 10),
        DashboardPanel(
          title: 'MISSION OBJECTIVES',
          icon: Icons.flag_outlined,
          children: [
            for (final (index, objective) in mission.objectives.indexed)
              Text(
                '${index + 1}. ${objective.label}',
                style: const TextStyle(color: DashboardStyle.muted),
              ),
          ],
        ),
      ],
    ),
  );
}
