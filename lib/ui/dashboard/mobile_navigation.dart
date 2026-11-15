import 'dart:async';

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
import '../mission_theme.dart';
import 'dashboard_style.dart';
import 'mobile_map_controls.dart';
import 'mobile_astronaut_content.dart';
import 'mobile_mission_sheets.dart';
import 'mission_control_dialogs.dart';

enum _Sheet {
  missions('Missions', Icons.flag_outlined),
  astronaut('Astronaut', Icons.person_outline),
  crew('Crew', Icons.groups_outlined);

  const _Sheet(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Composes three non-modal sheets over the dashboard's single persistent map.
class MobileNavigation extends StatefulWidget {
  const MobileNavigation({
    super.key,
    required this.mapBuilder,
    required this.solarCycle,
    required this.view,
    required this.astronaut,
    required this.teammate,
    required this.mission,
    required this.navigation,
    required this.checklist,
    required this.tracking,
    required this.presence,
    required this.member,
    required this.peerPoint,
    required this.onBack,
    required this.onSelect,
    required this.onNavigate,
    required this.onReturn,
    required this.onSensorTest,
    required this.onMovementLog,
    required this.onPing,
    required this.onSos,
    this.revealRescue = 0,
  });

  final Widget Function(
    bool showMapHud,
    VoidCallback onAstronaut,
    Widget Function(Widget? status, Widget? footer) layoutHud,
  )
  mapBuilder;
  final ValueListenable<MarsSolarCycle> solarCycle;
  final TerrainViewController view;
  final Astronaut astronaut;
  final Astronaut teammate;
  final MarsMission mission;
  final DemoNavigation navigation;
  final MissionChecklist checklist;
  final AstronautTracking tracking;
  final MissionPresence presence;
  final CrewPresence? member;
  final Offset? peerPoint;
  final VoidCallback onBack;
  final bool Function(Offset, String) onSelect;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;
  final VoidCallback onPing;
  final VoidCallback onSos;
  final int revealRescue;

  static const barHeight = 64.0;
  static const barMargin = 10.0;

  static double chromeBottom(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + barHeight + barMargin;

  @override
  State<MobileNavigation> createState() => _MobileNavigationState();
}

class _MobileNavigationState extends State<MobileNavigation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  final _scrollPositions = PageStorageBucket();
  bool _confirming = false;
  _Sheet? _sheet;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(MobileNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealRescue != oldWidget.revealRescue) unawaited(_close());
  }

  void _open(_Sheet next) {
    if (_sheet == next && !_closing) {
      _close();
      return;
    }
    setState(() {
      _sheet = next;
      _closing = false;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 1;
    } else {
      _slide.forward();
    }
  }

  Future<void> _close() async {
    if (_sheet == null || _closing) return;
    _closing = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 0;
    } else {
      await _slide.reverse();
    }
    if (!mounted || !_closing) return;
    setState(() {
      _sheet = null;
      _closing = false;
    });
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _select(Offset point, String label) {
    widget.onSelect(point, label);
    unawaited(_close());
  }

  Future<void> _returnToBase() async {
    final confirmed = await confirmReturnToHabitatBase(context);
    if (!mounted || confirmed != true || !widget.navigation.canReturnToBase) {
      return;
    }
    widget.onReturn();
  }

  Future<void> _sos() async {
    if (_confirming) return;
    if (widget.presence.sos?.state == SosState.active) {
      widget.onSos();
      return;
    }
    _confirming = true;
    try {
      final confirmed = await confirmCrewSos(context);
      if (mounted && confirmed == true) widget.onSos();
    } finally {
      _confirming = false;
    }
  }

  Widget _content(_Sheet sheet, Size viewport) => switch (sheet) {
    _Sheet.missions => ListenableBuilder(
      listenable: widget.checklist,
      builder: (context, _) => MobileMissionsContent(
        mission: widget.mission,
        landmarks: widget.navigation.map.landmarks,
        completed: widget.checklist.completed,
        loading: widget.checklist.loading,
        storageWarning: widget.checklist.warning,
        onChange: widget.checklist.toggle,
        onSelect: (landmark) {
          if (!widget.onSelect(landmark.position, landmark.name)) return;
          widget.tracking.setFollow(false);
          widget.view.recenterMissionPoint(landmark.position, viewport);
          unawaited(_close());
        },
      ),
    ),
    _Sheet.astronaut => MobileAstronautContent(
      astronaut: widget.astronaut,
      mission: widget.mission,
      navigation: widget.navigation,
      tracking: widget.tracking,
      solarCycle: widget.solarCycle,
      onSensorTest: widget.onSensorTest,
      onMovementLog: widget.onMovementLog,
    ),
    _Sheet.crew => MobileCrewContent(
      astronaut: widget.astronaut,
      teammate: widget.teammate,
      navigation: widget.navigation,
      tracking: widget.tracking,
      presence: widget.presence,
      member: widget.member,
      onCancelSos:
          widget.presence.sos?.state == SosState.active &&
              widget.presence.sos?.sender == widget.astronaut.id
          ? widget.onSos
          : null,
      onTeammate:
          widget.navigation.sos ||
              widget.navigation.rescuing ||
              widget.peerPoint == null
          ? null
          : () => _select(widget.peerPoint!, widget.teammate.fullName),
    ),
  };

  Widget _mapChrome(
    EdgeInsets insets,
    Size viewport,
    _Sheet? sheet,
    Widget? status,
    Widget? footer,
  ) => Positioned(
    left: insets.left + 12,
    right: insets.right + 12,
    top: insets.top + 9,
    bottom:
        insets.bottom +
        MobileNavigation.barHeight +
        MobileNavigation.barMargin +
        11,
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: viewport.width < 355 ? 1.3 : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          _MissionHeader(
            key: const ValueKey('mobile-mission-header'),
            astronaut: widget.astronaut,
            mission: widget.mission,
            navigation: widget.navigation,
            tracking: widget.tracking,
            presence: widget.presence,
            onBack: () => sheet == null ? widget.onBack() : _close(),
          ),
          MobileMapTelemetry(mission: widget.mission, cycle: widget.solarCycle),
          if (sheet == null)
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) {
                  final horizontal = MobileMapControls.usesHorizontalRow(size);
                  return Stack(
                    children: [
                      if (status != null)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: horizontal ? 0 : 68,
                            ),
                            child: status,
                          ),
                        ),
                      Align(
                        alignment: Alignment(1, horizontal ? -1 : -.35),
                        child: MobileMapControls(
                          navigation: widget.navigation,
                          onNavigate: widget.onNavigate,
                          onReturn: _returnToBase,
                          onPing: widget.onPing,
                          onSos: () => unawaited(_sos()),
                          ownsActiveSos:
                              widget.presence.sos?.state == SosState.active &&
                              widget.presence.sos?.sender ==
                                  widget.astronaut.id,
                          headingUp: widget.view.headingUp,
                          onRecenter: () => widget.view.recenterMissionPoint(
                            widget.navigation.position,
                            viewport,
                          ),
                          onToggleHeading: () => widget.view.headingUp.value =
                              !widget.view.headingUp.value,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (footer != null) footer,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final dockBottom = insets.bottom + MobileNavigation.barMargin;
    final dockTop = MobileNavigation.chromeBottom(context);
    final sheet = _sheet;
    return PopScope(
      canPop: sheet == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && sheet != null) _close();
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            widget.mapBuilder(
              sheet == null,
              () => _open(_Sheet.astronaut),
              (status, footer) => _mapChrome(
                insets,
                constraints.biggest,
                sheet,
                status,
                footer,
              ),
            ),
            if (sheet != null)
              Positioned(
                top: insets.top + 8,
                bottom: dockTop,
                left: insets.left + MobileNavigation.barMargin,
                right: insets.right + MobileNavigation.barMargin,
                child: ClipRect(
                  child: SlideTransition(
                    position: _slide.drive(
                      Tween(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).chain(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: PageStorage(
                        bucket: _scrollPositions,
                        child: _MissionSheet(
                          key: ValueKey(sheet),
                          sheet: sheet,
                          onClose: _close,
                          child: _content(sheet, constraints.biggest),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: insets.left + MobileNavigation.barMargin,
              right: insets.right + MobileNavigation.barMargin,
              bottom: dockBottom,
              child: _SheetNavigation(selected: sheet, onTap: _open),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionHeader extends StatelessWidget {
  const _MissionHeader({
    super.key,
    required this.astronaut,
    required this.mission,
    required this.navigation,
    required this.tracking,
    required this.presence,
    required this.onBack,
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final MissionPresence presence;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final connected = switch (presence.status) {
      ConnectionStatus.offline => DashboardStyle.muted,
      ConnectionStatus.connected => DashboardStyle.green,
      ConnectionStatus.reconnecting => DashboardStyle.amber,
    };
    final sos = presence.sos;
    final emergency = sos?.state == SosState.active;
    final status = emergency
        ? (sos!.sender == astronaut.id
              ? 'SOS ACTIVE'
              : 'RESCUE · ${sos.sender}')
        : navigation.target == null && !navigation.paused
        ? tracking.stepStatus
        : navigation.status;
    final remaining = navigation.remainingMeters;
    final steps = tracking.measuredSteps;
    final style = Theme.of(context).textTheme;
    final destinationStyle = style.bodySmall ?? const TextStyle(fontSize: 12);
    final showTarget = remaining != null && !navigation.sos;
    final strut = StrutStyle.fromTextStyle(
      destinationStyle,
      forceStrutHeight: true,
    );
    return DecoratedBox(
      decoration: DashboardStyle.surface(
        color: const Color(0xF20B1320),
        radius: 20,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 7, 10, 7),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to missions',
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  Text(
                    'SIDERA VI',
                    style: MissionTheme.display(
                      11,
                      tracking: 1.4,
                    ).copyWith(color: DashboardStyle.warm),
                  ),
                  Text(
                    mission.title,
                    style: MissionTheme.display(19),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    status,
                    style: style.bodySmall?.copyWith(
                      color: emergency
                          ? DashboardStyle.danger
                          : DashboardStyle.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Row(
                    key: const ValueKey('mobile-header-destination'),
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(
                          showTarget
                              ? navigation.targetLabel!
                              : 'Destination: —',
                          style: destinationStyle.copyWith(
                            color: showTarget
                                ? DashboardStyle.cyan
                                : DashboardStyle.muted,
                          ),
                          strutStyle: strut,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (showTarget)
                        Flexible(
                          flex: 2,
                          child: Text(
                            ' · ${formatNavigationDistance(remaining, live: true)}'
                            '${navigation.guiding ? ' left' : ''}',
                            style: destinationStyle.copyWith(
                              color: DashboardStyle.cyan,
                            ),
                            strutStyle: strut,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(
                  astronaut.id,
                  style: MissionTheme.display(
                    12,
                    tracking: .8,
                  ).copyWith(color: DashboardStyle.cyan),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    Icon(Icons.circle, size: 6, color: connected),
                    Text(
                      presence.status.mobileLabel,
                      style: style.labelSmall?.copyWith(color: connected),
                    ),
                  ],
                ),
                Text(
                  '${steps ?? '—'} ${steps == 1 ? 'step' : 'steps'}',
                  key: const ValueKey('mobile-detected-steps'),
                  style: MissionTheme.display(
                    9,
                    tracking: .35,
                  ).copyWith(color: DashboardStyle.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetNavigation extends StatelessWidget {
  const _SheetNavigation({required this.selected, required this.onTap});

  final _Sheet? selected;
  final ValueChanged<_Sheet> onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('mobile-navigation-dock'),
    color: DashboardStyle.inset,
    elevation: selected == null ? 14 : 0,
    shadowColor: Colors.black,
    shape: selected == null
        ? const StadiumBorder(side: BorderSide(color: DashboardStyle.outline))
        : const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            side: BorderSide(color: DashboardStyle.outline),
          ),
    child: SizedBox(
      height: MobileNavigation.barHeight,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (final sheet in _Sheet.values)
              Expanded(
                child: Semantics(
                  selected: selected == sheet,
                  child: TextButton(
                    key: ValueKey('mobile-tab-${sheet.name}'),
                    onPressed: () => onTap(sheet),
                    style: TextButton.styleFrom(
                      foregroundColor: selected == sheet
                          ? DashboardStyle.inset
                          : DashboardStyle.text,
                      backgroundColor: selected == sheet
                          ? DashboardStyle.orange
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        spacing: 5,
                        children: [
                          Icon(sheet.icon, size: 20),
                          Text(sheet.label, style: MissionTheme.display(14)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _MissionSheet extends StatefulWidget {
  const _MissionSheet({
    super.key,
    required this.sheet,
    required this.child,
    required this.onClose,
  });

  final _Sheet sheet;
  final Widget child;
  final VoidCallback onClose;

  @override
  State<_MissionSheet> createState() => _MissionSheetState();
}

class _MissionSheetState extends State<_MissionSheet> {
  static const _minimum = .12;
  static const _peek = .28;
  static const _medium = .48;
  static const _expanded = 1.0;
  final _extent = DraggableScrollableController();

  @override
  void dispose() {
    _extent.dispose();
    super.dispose();
  }

  void _changeExtent() {
    if (!_extent.isAttached) return;
    final target = _extent.size > _medium + .03 ? _peek : _expanded;
    if (MediaQuery.disableAnimationsOf(context)) {
      _extent.jumpTo(target);
    } else {
      unawaited(
        _extent.animateTo(
          target,
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<DraggableScrollableNotification>(
        onNotification: (event) {
          if (event.extent <= _minimum + .001) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onClose();
            });
          }
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _extent,
          expand: false,
          snap: true,
          snapSizes: const [_peek, _medium],
          minChildSize: _minimum,
          initialChildSize: _expanded,
          maxChildSize: _expanded,
          builder: (context, scroll) => Material(
            key: const ValueKey('mobile-mission-sheet'),
            color: DashboardStyle.inset,
            clipBehavior: Clip.antiAlias,
            elevation: 12,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
              side: BorderSide(color: DashboardStyle.outline),
            ),
            child: CustomScrollView(
              key: PageStorageKey(widget.sheet.name),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  automaticallyImplyLeading: false,
                  primary: false,
                  pinned: true,
                  toolbarHeight: 62,
                  titleSpacing: 15,
                  backgroundColor: DashboardStyle.inset,
                  surfaceTintColor: Colors.transparent,
                  title: Text(
                    widget.sheet.label,
                    style: MissionTheme.display(20),
                  ),
                  flexibleSpace: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: DashboardStyle.muted.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Expand or collapse ${widget.sheet.label}',
                      onPressed: _changeExtent,
                      icon: const Icon(Icons.unfold_more_rounded),
                    ),
                    IconButton(
                      tooltip: 'Close ${widget.sheet.label}',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 5),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  sliver: SliverToBoxAdapter(child: widget.child),
                ),
              ],
            ),
          ),
        ),
      );
}
