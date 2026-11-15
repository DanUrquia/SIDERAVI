import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mission_theme.dart';

/// Presents the brand once while the existing entry screen mounts underneath.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.child});

  final Widget child;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  static const _logo = AssetImage('assets/branding/sidera_vi_logo.png');
  // NASA/JPL-Caltech's Viking Orbiter 1 mosaic in the Valles Marineris briefing.
  static const _mars = AssetImage('assets/missions/valles-marineris.jpg');
  static const _visibleDuration = Duration(seconds: 4);
  static const _fadeDuration = Duration(milliseconds: 220);

  Timer? _hold;
  bool _preparing = false;
  bool _visible = true;
  bool _fading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preparing) return;
    _preparing = true;
    unawaited(_prepareArtwork());
  }

  Future<void> _prepareArtwork() async {
    await Future.wait([
      precacheImage(_logo, context),
      precacheImage(_mars, context),
    ]);
    if (!mounted) return;

    // Count from the rendered artwork, independently of engine and image startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fade = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _fadeDuration;
      _hold = Timer(_visibleDuration - fade, () {
        if (fade == Duration.zero || MediaQuery.disableAnimationsOf(context)) {
          _dismiss();
        } else {
          setState(() => _fading = true);
        }
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dismiss() {
    if (_visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: _visible,
        child: ExcludeSemantics(
          excluding: _visible,
          child: IgnorePointer(ignoring: _visible, child: widget.child),
        ),
      ),
      if (_visible)
        AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _fadeDuration,
          curve: Curves.easeInOut,
          onEnd: _dismiss,
          child: Material(
            color: MissionTheme.navy,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Image(
                  key: ValueKey('startup-mars'),
                  image: _mars,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .48, .83, 1],
                      colors: [
                        Color(0x290B0F1B),
                        Color(0x540B0F1B),
                        Color(0xA30B0F1B),
                        Color(0xF20B0F1B),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  minimum: const EdgeInsets.symmetric(horizontal: 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Image(
                            key: const ValueKey('startup-logo'),
                            image: _logo,
                            semanticLabel: 'SIDERA VI',
                            fit: BoxFit.contain,
                            width: math.min(
                              math.min(constraints.maxWidth * .90, 650),
                              constraints.maxHeight * 1.35,
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 20),
                            child: Text(
                              'Made with Super Intelligence.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: .9,
                                color: MissionTheme.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
