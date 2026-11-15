import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../missions/mission.dart';
import '../../missions/mission_catalog.dart';
import '../cockpit_grid.dart';
import '../mission_theme.dart';
import 'mission_information_panel.dart';
import 'mission_photo_panel.dart';

/// Browses the local Mars catalog during one active astronaut session.
class MissionSelection extends StatefulWidget {
  /// Receives the signed-in astronaut and actions for the current session.
  const MissionSelection({
    super.key,
    required this.astronaut,
    required this.onBack,
    required this.onStart,
  });

  final Astronaut astronaut;
  final VoidCallback onBack;
  final ValueChanged<MarsMission> onStart;

  @override
  State<MissionSelection> createState() => _MissionSelectionState();
}

/// Shares one index and transition across the photograph and mission briefing.
class _MissionSelectionState extends State<MissionSelection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition;
  int _index = 0;
  double _dragDistance = 0;
  bool _imagesWarmed = false;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 210),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imagesWarmed) return;
    _imagesWarmed = true;
    for (final mission in marsMissions) {
      precacheImage(AssetImage(mission.imagery.asset), context);
    }
  }

  /// Uses bounded navigation and ignores additional input during a fade.
  void _move(int step) {
    final next = _index + step;
    if (_transition.isAnimating || next < 0 || next >= marsMissions.length) {
      return;
    }
    setState(() => _index = next);
    if (!MediaQuery.disableAnimationsOf(context)) _transition.forward(from: 0);
  }

  /// Handles both deliberate drags and quick flicks as a single page change.
  void _finishSwipe(DragEndDetails details) {
    final distance = _dragDistance;
    final velocity = details.primaryVelocity ?? 0;
    if (distance.abs() > 42) {
      _move(distance < 0 ? 1 : -1);
    } else if (velocity.abs() > 240) {
      _move(velocity < 0 ? 1 : -1);
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mission = marsMissions[_index];
    final index =
        '${(_index + 1).toString().padLeft(2, '0')} / '
        '${marsMissions.length.toString().padLeft(2, '0')}';
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final photo = MissionPhotoPanel(
      mission: mission,
      index: index,
      onPrevious: _index > 0 ? () => _move(-1) : null,
      onNext: _index < marsMissions.length - 1 ? () => _move(1) : null,
      compact: mobile,
    );
    Widget details({required bool bounded}) => MissionInformationPanel(
      key: ValueKey(mission.id),
      mission: mission,
      index: _index,
      total: marsMissions.length,
      onStart: () {
        if (!_transition.isAnimating) widget.onStart(mission);
      },
      bounded: bounded,
    );
    Widget carousel(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
      onHorizontalDragEnd: _finishSwipe,
      child: FadeTransition(
        opacity: _transition
            .drive(CurveTween(curve: Curves.easeOut))
            .drive(Tween(begin: .68, end: 1)),
        child: child,
      ),
    );
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: .85,
            colors: [Color(0xFF171926), Color(0xFF0B1320)],
          ),
        ),
        child: CustomPaint(
          painter: const CockpitGrid(),
          child: SafeArea(
            minimum: mobile
                ? const EdgeInsets.fromLTRB(16, 8, 16, 8)
                : const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1512),
                child: mobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MobileMissionHeader(
                            astronaut: widget.astronaut,
                            onBack: widget.onBack,
                          ),
                          Expanded(
                            child: carousel(
                              ListView(
                                primary: false,
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 12,
                                ),
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      'Select Mission',
                                      style: MissionTheme.display(22),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    'Choose your next Mars expedition',
                                    style: TextStyle(
                                      color: MissionTheme.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  photo,
                                  const SizedBox(height: 10),
                                  details(bounded: false),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MissionHeader(
                            astronaut: widget.astronaut,
                            onBack: widget.onBack,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1, color: Color(0xFF2B3140)),
                          ),
                          Expanded(
                            child: carousel(
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth < 780) {
                                    return ListView(
                                      primary: false,
                                      children: [
                                        SizedBox(height: 345, child: photo),
                                        const SizedBox(height: 14),
                                        details(bounded: false),
                                      ],
                                    );
                                  }
                                  return Row(
                                    spacing: 22,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(flex: 58, child: photo),
                                      Expanded(
                                        flex: 42,
                                        child: details(bounded: true),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Regional coordinates and published imagery',
                            style: TextStyle(
                              color: MissionTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the back action and the active astronaut in a compact phone toolbar.
class _MobileMissionHeader extends StatelessWidget {
  const _MobileMissionHeader({required this.astronaut, required this.onBack});

  final Astronaut astronaut;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 10,
    children: [
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: onBack,
          icon: const Icon(
            Icons.chevron_left,
            size: 20,
            color: MissionTheme.warmOrange,
          ),
          label: const Text('Back'),
          style:
              MissionTheme.control(
                fill: MissionTheme.utilityFace,
                border: MissionTheme.outline,
                elevation: 0,
                radius: 12,
              ).copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
        ),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: MissionTheme.utilityFace,
              border: Border.all(color: MissionTheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  astronaut.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MissionTheme.display(
                    10,
                    tracking: 1.1,
                  ).copyWith(color: MissionTheme.warmOrange),
                ),
                Text(
                  astronaut.fullName,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: MissionTheme.display(16),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// Aligns navigation, the page title, and the authenticated astronaut.
class _MissionHeader extends StatelessWidget {
  const _MissionHeader({required this.astronaut, required this.onBack});

  final Astronaut astronaut;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        final back = SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onBack,
            icon: const Icon(
              Icons.chevron_left,
              color: MissionTheme.warmOrange,
            ),
            label: const Text('BACK'),
            style: MissionTheme.control(
              fill: MissionTheme.utilityFace,
              border: MissionTheme.outline,
              elevation: 0,
              radius: 12,
            ),
          ),
        );
        final astronautBadge = _AstronautBadge(astronaut: astronaut);
        final title = Semantics(
          header: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MissionTheme.utilityFace,
              border: Border.all(color: const Color(0xFF303748)),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  const Icon(Icons.circle, size: 9, color: MissionTheme.orange),
                  Flexible(
                    child: Text(
                      'SELECT MISSION',
                      style: MissionTheme.display(16, tracking: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final logo = Image.asset(
          'assets/branding/sidera_vi_logo.png',
          width: 111,
          semanticLabel: 'SIDERA VI',
        );
        if (compact) {
          return Column(
            spacing: 10,
            children: [
              Row(
                spacing: 10,
                children: [
                  back,
                  if (constraints.maxWidth >= 440) Flexible(child: logo),
                  const Spacer(),
                  Flexible(flex: 3, child: astronautBadge),
                ],
              ),
              title,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Row(
                spacing: 19,
                children: [
                  back,
                  Flexible(child: logo),
                ],
              ),
            ),
            title,
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: astronautBadge,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Derives the header avatar, exact roster name, and identifier from the session.
class _AstronautBadge extends StatelessWidget {
  const _AstronautBadge({required this.astronaut});

  final Astronaut astronaut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: MissionTheme.utilityFace,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF303748)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Container(
            width: 45,
            height: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MissionTheme.orange, width: 2),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                astronaut.initials,
                style: MissionTheme.display(
                  16,
                ).copyWith(color: MissionTheme.warmOrange),
              ),
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(
                  astronaut.id,
                  style: MissionTheme.display(
                    12,
                    tracking: 1.4,
                  ).copyWith(color: MissionTheme.warmOrange),
                ),
                Text(astronaut.fullName, style: MissionTheme.display(18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
