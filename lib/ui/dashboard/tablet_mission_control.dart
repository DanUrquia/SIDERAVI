import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_checklist.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../../missions/mars_solar_time.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/crew_signals.dart';
import '../../tracking/mission_presence.dart';
import '../mission_action_button.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';
import 'mission_control_dialogs.dart';
import 'mobile_astronaut_content.dart';
import 'mobile_mission_sheets.dart';

/// A tablet workspace with a persistent terrain view and independent panels.
class TabletMissionControl extends StatefulWidget {
  const TabletMissionControl({
    super.key,
    required this.map,
    required this.view,
    required this.mission,
    required this.astronaut,
    required this.teammate,
    required this.navigation,
    required this.checklist,
    required this.tracking,
    required this.solarCycle,
    required this.presence,
    required this.member,
    required this.peerPoint,
    required this.revealRescue,
    required this.onBack,
    required this.onSelect,
    required this.onNavigate,
    required this.onReturn,
    required this.onSensorTest,
    required this.onMovementLog,
    required this.onPin,
    required this.onSos,
  });

  final Widget map;
  final TerrainViewController view;
  final MarsMission mission;
  final Astronaut astronaut;
  final Astronaut teammate;
  final DemoNavigation navigation;
  final MissionChecklist checklist;
  final AstronautTracking tracking;
  final ValueListenable<MarsSolarCycle> solarCycle;
  final MissionPresence presence;
  final CrewPresence? member;
  final Offset? peerPoint;
  final int revealRescue;
  final VoidCallback onBack;
  final bool Function(Offset point, String label) onSelect;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;
  final VoidCallback onPin;
  final VoidCallback onSos;

  @override
  State<TabletMissionControl> createState() => _TabletMissionControlState();
}

enum _TabletPanel {
  missions('Missions', Icons.flag_outlined),
  astronaut('Astronaut', Icons.person_outline),
  crew('Crew', Icons.groups_outlined);

  const _TabletPanel(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _TabletMissionControlState extends State<TabletMissionControl> {
  final _viewport = GlobalKey();
  final _storage = PageStorageBucket();
  final _scroll = {
    for (final panel in _TabletPanel.values) panel: ScrollController(),
  };
  _TabletPanel _panel = _TabletPanel.astronaut;
  _TabletPanel _control = _TabletPanel.astronaut;
  bool _confirming = false;

  CrewSos? get _emergency => switch (widget.presence.sos) {
    final sos? when sos.state == SosState.active => sos,
    _ => null,
  };

  bool get _ownsSos => _emergency?.sender == widget.astronaut.id;

  @override
  void didUpdateWidget(TabletMissionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealRescue != widget.revealRescue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.navigation.rescuing) {
          _focus(widget.navigation.target!);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _scroll.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _focus(Offset point) {
    final size = _viewport.currentContext?.size;
    if (size == null || size.isEmpty) return;
    widget.tracking.setFollow(false);
    widget.view.recenterMissionPoint(point, size);
  }

  Future<void> _returnToBase() async {
    final confirmed = await confirmReturnToHabitatBase(context, tablet: true);
    if (mounted && confirmed == true && widget.navigation.canReturnToBase) {
      widget.onReturn();
    }
  }

  Future<void> _confirmSos() async {
    if (_confirming) return;
    if (_emergency != null) {
      if (_ownsSos) widget.onSos();
      return;
    }
    _confirming = true;
    try {
      final confirmed = await confirmCrewSos(context);
      if (mounted && confirmed == true && _emergency == null) widget.onSos();
    } finally {
      _confirming = false;
    }
  }

  Widget _missionContent() => ListenableBuilder(
    listenable: widget.checklist,
    builder: (context, _) => MobileMissionsContent(
      mission: widget.mission,
      landmarks: widget.navigation.map.landmarks,
      completed: widget.checklist.completed,
      loading: widget.checklist.loading,
      storageWarning: widget.checklist.warning,
      onChange: widget.checklist.toggle,
      onSelect: (landmark) {
        if (widget.onSelect(landmark.position, landmark.name)) {
          _focus(landmark.position);
        }
      },
    ),
  );

  Widget _controlContent(_TabletPanel panel) => switch (panel) {
    _TabletPanel.astronaut => MobileAstronautContent(
      astronaut: widget.astronaut,
      mission: widget.mission,
      navigation: widget.navigation,
      tracking: widget.tracking,
      solarCycle: widget.solarCycle,
      onSensorTest: widget.onSensorTest,
      onMovementLog: widget.onMovementLog,
      tablet: true,
      emergencyActive: _emergency != null,
    ),
    _TabletPanel.crew => MobileCrewContent(
      astronaut: widget.astronaut,
      teammate: widget.teammate,
      navigation: widget.navigation,
      tracking: widget.tracking,
      presence: widget.presence,
      member: widget.member,
      tablet: true,
      onTeammate: switch (widget.peerPoint) {
        final point? when _emergency == null => () {
          if (widget.onSelect(point, widget.teammate.fullName)) _focus(point);
        },
        _ => null,
      },
    ),
    _TabletPanel.missions => _missionContent(),
  };

  Widget _scroller(_TabletPanel panel, Widget content) {
    final controller = _scroll[panel]!;
    return Scrollbar(
      controller: controller,
      child: SingleChildScrollView(
        key: PageStorageKey('tablet-${panel.name}-scroll'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
        child: content,
      ),
    );
  }

  Widget _map() => Stack(
    key: _viewport,
    fit: StackFit.expand,
    children: [
      widget.map,
      if (_emergency case final sos?)
        Positioned(
          top: 66,
          left: 10,
          right: 10,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: DashboardStyle.surface(
                  color: DashboardStyle.emergency,
                  border: DashboardStyle.danger,
                  radius: 9,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text(
                    'SOS ACTIVE · ${sos.sender}',
                    style: MissionTheme.display(
                      12,
                    ).copyWith(color: DashboardStyle.text),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _tabBar(
    Iterable<_TabletPanel> panels,
    _TabletPanel active,
    ValueChanged<_TabletPanel> select,
  ) => Wrap(
    spacing: 5,
    runSpacing: 4,
    children: [
      for (final panel in panels)
        ChoiceChip(
          key: ValueKey('tablet-tab-${panel.name}'),
          selected: panel == active,
          showCheckmark: false,
          avatar: Icon(
            panel.icon,
            color: panel == active ? DashboardStyle.warm : DashboardStyle.muted,
            size: 17,
          ),
          label: Text(panel.label),
          labelStyle: TextStyle(
            color: panel == active ? DashboardStyle.cyan : DashboardStyle.text,
          ),
          side: BorderSide(
            color: panel == active
                ? DashboardStyle.cyan.withValues(alpha: .55)
                : DashboardStyle.outline,
          ),
          selectedColor: DashboardStyle.panel,
          backgroundColor: DashboardStyle.inset,
          onSelected: (_) => select(panel),
        ),
    ],
  );

  Widget _panelShell({required Key key, required Widget child}) => Container(
    key: key,
    clipBehavior: Clip.antiAlias,
    decoration: DashboardStyle.surface(color: DashboardStyle.inset, radius: 15),
    child: child,
  );

  Widget _missions() => _panelShell(
    key: const ValueKey('tablet-missions'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(icon: Icons.flag_outlined, title: 'MISSIONS'),
        Expanded(child: _scroller(_TabletPanel.missions, _missionContent())),
      ],
    ),
  );

  Widget _right({required bool wide}) {
    final active = wide ? _control : _panel;
    final operations = _TabletOperations(
      navigation: widget.navigation,
      emergency: _emergency != null,
      ownsSos: _ownsSos,
      onNavigate: widget.onNavigate,
      onReturn: _returnToBase,
      onPin: widget.onPin,
      onSos: _confirmSos,
    );
    return _panelShell(
      key: const ValueKey('tablet-mission-control'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useFooter =
              active != _TabletPanel.missions &&
              constraints.maxHeight >= 505 &&
              MediaQuery.textScalerOf(context).scale(14) < 23;
          final content = _controlContent(active);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                const _SectionTitle(icon: Icons.tune, title: 'MISSION CONTROL'),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 5),
                child: _tabBar(
                  [
                    if (!wide) _TabletPanel.missions,
                    _TabletPanel.astronaut,
                    _TabletPanel.crew,
                  ],
                  active,
                  (panel) => setState(() {
                    _panel = panel;
                    if (panel != _TabletPanel.missions) _control = panel;
                  }),
                ),
              ),
              Expanded(
                child: _scroller(
                  active,
                  useFooter || active == _TabletPanel.missions
                      ? content
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 10,
                          children: [operations, content],
                        ),
                ),
              ),
              if (useFooter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: operations,
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _storage,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final landscape = width > constraints.maxHeight;
        final wide = landscape && width >= 916;
        final map = _map();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            _TabletHeader(
              mission: widget.mission,
              astronaut: widget.astronaut,
              presence: widget.presence,
              onBack: widget.onBack,
            ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        SizedBox(
                          width: (width * .218).clamp(226.0, 305.0),
                          child: _missions(),
                        ),
                        Expanded(child: map),
                        SizedBox(
                          width: (width * .246).clamp(284.0, 348.0),
                          child: _right(wide: true),
                        ),
                      ],
                    )
                  : landscape && width >= 650
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        Expanded(child: map),
                        SizedBox(width: 286, child: _right(wide: false)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        Expanded(flex: 5, child: map),
                        Expanded(flex: 6, child: _right(wide: false)),
                      ],
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
    child: Semantics(
      header: true,
      child: Row(
        spacing: 7,
        children: [
          Icon(icon, size: 19, color: DashboardStyle.warm),
          Expanded(
            child: Text(
              title,
              style: MissionTheme.display(
                13,
                tracking: .8,
              ).copyWith(color: DashboardStyle.warm),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TabletHeader extends StatelessWidget {
  const _TabletHeader({
    required this.mission,
    required this.astronaut,
    required this.presence,
    required this.onBack,
  });

  final MarsMission mission;
  final Astronaut astronaut;
  final MissionPresence presence;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: DashboardStyle.surface(radius: 14),
    child: Row(
      spacing: 10,
      children: [
        IconButton(
          tooltip: 'Back to missions',
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SIDERA VI',
                style: MissionTheme.display(
                  11,
                  tracking: 1.25,
                ).copyWith(color: DashboardStyle.warm),
              ),
              Text(mission.title, style: MissionTheme.display(20)),
            ],
          ),
        ),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: DecoratedBox(
              decoration: DashboardStyle.surface(color: DashboardStyle.inset),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                child: Text(
                  '${astronaut.id} · ${presence.status.mobileLabel}',
                  style: MissionTheme.display(12, tracking: .4).copyWith(
                    color: presence.status == ConnectionStatus.connected
                        ? DashboardStyle.green
                        : DashboardStyle.muted,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TabletOperations extends StatelessWidget {
  const _TabletOperations({
    required this.navigation,
    required this.emergency,
    required this.ownsSos,
    required this.onNavigate,
    required this.onReturn,
    required this.onPin,
    required this.onSos,
  });

  final DemoNavigation navigation;
  final bool emergency;
  final bool ownsSos;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onPin;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('tablet-navigation-actions'),
    decoration: DashboardStyle.surface(radius: 12),
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          navigation.targetLabel ?? 'Select a map destination',
          style: MissionTheme.display(14),
        ),
        Text(
          [
            if (navigation.remainingMeters case final meters?)
              formatNavigationDistance(meters, live: true),
            navigation.status,
          ].join(' · '),
          style: const TextStyle(color: DashboardStyle.muted, fontSize: 12),
        ),
        MissionActionButton(
          key: const ValueKey('tablet-start-navigation'),
          label: 'START NAVIGATION',
          icon: Icons.navigation_outlined,
          onPressed: navigation.canNavigate && !emergency ? onNavigate : null,
          wrapLabel: true,
          minimumHeight: 48,
        ),
        Row(
          spacing: 5,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _operation(
              'Return to Base',
              Icons.home_outlined,
              navigation.canReturnToBase && !emergency ? onReturn : null,
            ),
            _operation('Send PIN', Icons.place_outlined, onPin),
            _operation(
              ownsSos ? 'Cancel SOS' : 'SOS',
              Icons.warning_amber_rounded,
              !emergency || ownsSos ? onSos : null,
              emergency: true,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _operation(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool emergency = false,
  }) => Expanded(
    child: Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          minimumSize: const Size(44, 44),
          foregroundColor: emergency
              ? DashboardStyle.danger
              : DashboardStyle.text,
          backgroundColor: emergency
              ? DashboardStyle.emergency
              : DashboardStyle.inset,
          side: BorderSide(
            color: emergency ? DashboardStyle.danger : DashboardStyle.outline,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Icon(icon, size: 19),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}
