import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_checklist.dart';
import '../../dashboard/terrain_view_controller.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';
import 'mobile_map_controls.dart';
import 'mobile_mission_sheets.dart';

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
    required this.view,
    required this.astronaut,
    required this.teammate,
    required this.mission,
    required this.navigation,
    required this.tracking,
    required this.presence,
    required this.member,
    required this.peerPoint,
    required this.peerFresh,
    required this.onBack,
    required this.onSelect,
    required this.onNavigate,
    required this.onReturn,
    required this.onSensorTest,
    required this.onMovementLog,
    required this.onJoin,
    required this.onPing,
    required this.onSos,
  });

  final Widget Function(bool showMapHud) mapBuilder;
  final TerrainViewController view;
  final Astronaut astronaut;
  final Astronaut teammate;
  final MarsMission mission;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final MissionPresence presence;
  final CrewPresence? member;
  final Offset? peerPoint;
  final bool peerFresh;
  final VoidCallback onBack;
  final void Function(Offset, String) onSelect;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;
  final VoidCallback? onJoin;
  final VoidCallback onPing;
  final VoidCallback onSos;

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
  late final _storage = MissionChecklistStore(
    '${widget.astronaut.id}/${widget.mission.id}',
  );
  Set<String> _completed = {};
  bool _loading = true;
  bool _saving = false;
  bool _confirming = false;
  String? _storageWarning;
  _Sheet? _sheet;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    unawaited(_loadChecklist());
  }

  Future<void> _loadChecklist() async {
    Set<String> completed = {};
    try {
      completed = await _storage.read();
    } on PlatformException {
      _storageWarning = 'Checklist storage unavailable.';
    } on MissingPluginException {
      _storageWarning = 'Checklist lasts for this visit.';
    }
    if (!mounted) return;
    setState(() {
      _completed = completed;
      _loading = false;
    });
  }

  Future<void> _changeObjective(String id) async {
    if (_loading || _saving) return;
    _saving = true;
    setState(() {
      _completed = {..._completed};
      if (!_completed.remove(id)) _completed.add(id);
    });
    try {
      await Future.wait([
        _storage.write(_completed),
        Future<void>.delayed(const Duration(milliseconds: 160)),
      ]);
      if (mounted && _storageWarning != null) {
        setState(() => _storageWarning = null);
      }
    } on PlatformException {
      if (mounted) {
        setState(() {
          _storageWarning = 'Could not save the checklist on this device.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _storageWarning = 'Checklist lasts for this visit.');
      }
    } finally {
      _saving = false;
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return to habitat base?'),
        content: const Text(
          'Start direct guidance to Habitat Base. Keep the phone’s top edge pointed in your walking direction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Return to base'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !widget.navigation.canReturnToBase) {
      return;
    }
    widget.onReturn();
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required String detail,
    required VoidCallback onConfirmed,
  }) async {
    if (_confirming) return;
    _confirming = true;
    try {
      final yes = await confirmMobileAction(
        context,
        title: title,
        message: message,
        detail: detail,
      );
      if (mounted && yes == true) onConfirmed();
    } finally {
      _confirming = false;
    }
  }

  void _ping() => unawaited(
    _confirmAction(
      title: 'Send Location Ping?',
      message: 'Share your current simulated Mars position with your crew?',
      detail: 'This prototype places a location marker on this device.',
      onConfirmed: widget.onPing,
    ),
  );

  void _sos() {
    if (widget.navigation.sos) {
      widget.onSos();
      return;
    }
    unawaited(
      _confirmAction(
        title: 'Activate SOS?',
        message: 'Send an emergency alert to your mission crew?',
        detail:
            'Demo SOS highlights your position and pauses exploration on this device.',
        onConfirmed: widget.onSos,
      ),
    );
  }

  Widget _content(_Sheet sheet) => switch (sheet) {
    _Sheet.missions => MobileMissionsContent(
      mission: widget.mission,
      landmarks: widget.navigation.map.landmarks,
      completed: _completed,
      loading: _loading,
      storageWarning: _storageWarning,
      onChange: _changeObjective,
      onSelect: _select,
    ),
    _Sheet.astronaut => MobileAstronautContent(
      astronaut: widget.astronaut,
      navigation: widget.navigation,
      tracking: widget.tracking,
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
      peerPoint: widget.peerPoint,
      fresh: widget.peerFresh,
      onJoin: widget.onJoin,
      onTeammate: widget.navigation.sos || widget.peerPoint == null
          ? null
          : () => _select(widget.peerPoint!, widget.teammate.fullName),
    ),
  };

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
            widget.mapBuilder(sheet == null),
            Positioned(
              left: insets.left + 12,
              right: insets.right + 12,
              top: insets.top + 9,
              bottom: dockTop + 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 7,
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
                  MobileMapTelemetry(
                    mission: widget.mission,
                    navigation: widget.navigation,
                  ),
                  if (sheet == null)
                    Expanded(
                      child: Align(
                        alignment: const Alignment(1, -.47),
                        child: MobileMapControls(
                          navigation: widget.navigation,
                          onNavigate: widget.onNavigate,
                          onReturn: _returnToBase,
                          onPing: _ping,
                          onSos: _sos,
                          following: widget.tracking.follow,
                          onRecenter: () {
                            final viewport = constraints.biggest;
                            final world = missionWorld(viewport);
                            widget.view.recenter(
                              world.topLeft +
                                  widget.navigation.position * world.width,
                              viewport,
                            );
                          },
                          onFollow: () => widget.tracking.setFollow(
                            !widget.tracking.follow,
                          ),
                        ),
                      ),
                    ),
                ],
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
                          child: _content(sheet),
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
    final status =
        navigation.target == null && !navigation.paused && !navigation.sos
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
                      color: navigation.sos
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
                      presence.status.label,
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
