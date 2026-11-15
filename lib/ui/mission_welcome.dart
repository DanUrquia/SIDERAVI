import 'package:flutter/material.dart';

import '../auth/astronaut.dart';
import 'mission_theme.dart';

/// Plays the Phase 1 welcome and simulated dashboard initialization.
class MissionWelcome extends StatefulWidget {
  /// Presents the authenticated astronaut and notifies the app after the final stage.
  const MissionWelcome({
    super.key,
    required this.astronaut,
    required this.onComplete,
  });

  /// Time reserved at the start of the sequence for the login fade.
  static const loginFadeDuration = Duration(milliseconds: 800);

  final Astronaut astronaut;
  final VoidCallback onComplete;

  @override
  State<MissionWelcome> createState() => _MissionWelcomeState();
}

/// Drives all four stages from one finite animation timeline.
class _MissionWelcomeState extends State<MissionWelcome>
    with SingleTickerProviderStateMixin {
  static const _nameStarts = 800;
  static const _calibrationStarts = 2200;
  static const _readyStarts = 4500;
  static const _finished = 5500;
  late final AnimationController _timeline;
  bool _finishedSequence = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _finished),
    )..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _timeline.value = 1;
    } else if (_timeline.isDismissed && !_timeline.isAnimating) {
      _timeline.forward();
    }
  }

  /// Advances after the ready message, including when Reduce Motion skips motion.
  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _finishedSequence) return;
    _finishedSequence = true;
    // Reduced motion can complete the timeline during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete();
    });
  }

  /// Converts a time window within the timeline to a smooth 0–1 reveal.
  double _reveal(double elapsed, int start, int end) => Curves.easeInOut
      .transform(((elapsed - start) / (end - start)).clamp(0, 1));

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MissionTheme.black,
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = (constraints.maxHeight / 760).clamp(.65, 1.1);
            return Center(
              child: AnimatedBuilder(
                animation: _timeline,
                builder: (context, child) {
                  final elapsed = _timeline.value * _finished;
                  final name = _reveal(elapsed, _nameStarts, 1650);
                  final loading = _reveal(elapsed, _calibrationStarts, 2750);
                  final progress = _reveal(
                    elapsed,
                    _calibrationStarts,
                    _readyStarts,
                  );
                  final ready = _reveal(elapsed, _readyStarts, 5200);
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _stage(
                          name,
                          Semantics(
                            header: true,
                            label:
                                'Welcome Astronaut ${widget.astronaut.fullName}',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 16 * scale,
                              children: [
                                Text(
                                  'Welcome Astronaut',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: MissionTheme.muted,
                                    fontSize: 19 * scale,
                                    letterSpacing: 3,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    widget.astronaut.fullName,
                                    style: MissionTheme.display(
                                      72 * scale,
                                      tracking: -1.7,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 8 * scale),
                                _accentLine(),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 39 * scale),
                        _stage(
                          loading,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 20 * scale,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Loading and calibrating your dashboard.',
                                  style: TextStyle(
                                    color: MissionTheme.muted,
                                    fontSize: 18 * scale,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 340 * scale,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 3,
                                  borderRadius: BorderRadius.circular(4),
                                  backgroundColor: const Color(0xFF2B211F),
                                  color: MissionTheme.warmOrange,
                                  semanticsLabel:
                                      'Mission dashboard initialization',
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 22 * scale),
                        _stage(
                          ready,
                          Semantics(
                            liveRegion: true,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'MISSION INTERFACE READY',
                                style: MissionTheme.display(
                                  15 * scale,
                                  tracking: 2.6,
                                ).copyWith(color: MissionTheme.warmOrange),
                              ),
                            ),
                          ),
                        ),
                        // Preserve the welcome's original vertical alignment.
                        SizedBox(height: 115 * scale),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Holds layout space until a stage can be shown and announced.
  Widget _stage(double opacity, Widget content) => Opacity(
    opacity: opacity,
    child: Visibility(
      visible: opacity > 0,
      maintainState: true,
      maintainSize: true,
      maintainAnimation: true,
      child: content,
    ),
  );

  /// Anchors the astronaut name with a restrained, warm glow.
  Widget _accentLine() => Container(
    width: 180,
    height: 2,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.transparent, MissionTheme.orange, Colors.transparent],
      ),
      boxShadow: [BoxShadow(color: Color(0x40FF5826), blurRadius: 18)],
    ),
  );
}
