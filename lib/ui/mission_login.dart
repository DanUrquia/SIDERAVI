import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/astronaut.dart';
import '../auth/prototype_auth.dart';
import 'mission_theme.dart';
import 'pin_keypad.dart';

/// Gathers a mission PIN and hands the authenticated astronaut to the app.
class MissionLogin extends StatefulWidget {
  /// Creates an empty login with a callback for a successful submission.
  const MissionLogin({super.key, required this.onAuthenticated});

  final Future<void> Function(Astronaut) onAuthenticated;

  @override
  State<MissionLogin> createState() => _MissionLoginState();
}

/// Keeps the entered digits transient and drives the invalid-PIN feedback.
class _MissionLoginState extends State<MissionLogin>
    with SingleTickerProviderStateMixin {
  static const _auth = PrototypeAuth();
  late final AnimationController _failure;
  String _pin = '';
  bool _invalid = false;
  bool _launching = false;

  bool get _canSubmit => _pin.length == 4 && !_invalid && !_launching;

  @override
  void initState() {
    super.initState();
    _failure = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..addStatusListener(_finishFeedback);
  }

  /// Wipes the rejected entry when its brief animation finishes.
  void _finishFeedback(AnimationStatus status) {
    if (status == AnimationStatus.completed) setState(() => _pin = '');
  }

  /// Starts a fresh entry immediately if a previous attempt was rejected.
  void _appendDigit(String digit) {
    if (_launching || (!_invalid && _pin.length == 4)) return;
    if (_invalid) {
      _failure.reset();
    }
    setState(() {
      _pin = _invalid ? digit : _pin + digit;
      _invalid = false;
    });
  }

  /// Clears all PIN input and any denial feedback.
  void _clearPin() {
    _failure.reset();
    setState(() {
      _pin = '';
      _invalid = false;
    });
  }

  /// Deletes the last digit or dismisses a rejected attempt.
  void _deleteDigit() {
    if (_invalid) {
      _clearPin();
    } else if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  /// Authenticates only on explicit submission and clears a successful PIN.
  Future<void> _submit() async {
    if (!_canSubmit) return;
    final astronaut = _auth.authenticate(_pin);
    if (astronaut == null) {
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      setState(() {
        _invalid = true;
        if (reducedMotion) _pin = '';
      });
      if (!reducedMotion) _failure.forward(from: 0);
      return;
    }

    setState(() {
      _pin = '';
      _launching = true;
    });
    try {
      await widget.onAuthenticated(astronaut);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  void dispose() {
    _failure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.76),
            radius: .57,
            colors: [Color(0xFF261923), MissionTheme.navy],
          ),
        ),
        child: CustomPaint(
          painter: const _CockpitGrid(),
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the wider footprint to preserve tap height on short iPads.
                final sideBySide =
                    constraints.maxHeight < 570 && constraints.maxWidth >= 560;
                final scale = sideBySide
                    ? (constraints.maxHeight / 520).clamp(.62, .95)
                    : (constraints.maxHeight / 865).clamp(.62, 1.05);
                final heading = _LoginHeading(scale: scale);
                final pinStatus = _PinStatus(
                  count: _pin.length,
                  invalid: _invalid,
                  scale: scale,
                  failure: _failure,
                );
                final controls = _controls(scale);
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sideBySide ? 1000 : 620,
                    ),
                    child: sideBySide
                        ? Row(
                            spacing: 25,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 24 * scale,
                                  children: [heading, pinStatus],
                                ),
                              ),
                              Expanded(child: controls),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              heading,
                              SizedBox(height: 37 * scale),
                              pinStatus,
                              SizedBox(height: 20 * scale),
                              controls,
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Groups the keypad and explicit submit action at the same width.
  Widget _controls(double scale) {
    final keyHeight = 84 * scale;
    final canEdit = !_launching && (_pin.isNotEmpty || _invalid);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18 * scale,
      children: [
        PinKeypad(
          onDigit: _launching ? null : _appendDigit,
          onClear: canEdit ? _clearPin : null,
          onBackspace: canEdit ? _deleteDigit : null,
          keyHeight: keyHeight,
          gap: 14 * scale,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(keyHeight * .18),
            boxShadow: [
              if (_canSubmit)
                BoxShadow(
                  color: MissionTheme.ready.withValues(alpha: .23),
                  blurRadius: 27,
                ),
            ],
          ),
          child: SizedBox(
            height: keyHeight,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: MissionTheme.control(
                fill: const Color(0xFF087553),
                border: MissionTheme.ready,
                radius: keyHeight * .18,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'ENTER MISSION',
                  style: MissionTheme.display(25 * scale, tracking: 1.6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays the official wordmark with its transparent padding outside the frame.
class _LoginHeading extends StatelessWidget {
  const _LoginHeading({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 436 * scale,
          height: 79 * scale,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return ClipRect(
                child: OverflowBox(
                  maxWidth: width,
                  maxHeight: width / 3,
                  child: Image.asset(
                    'assets/branding/sidera_vi_logo.png',
                    width: width,
                    height: width / 3,
                    semanticLabel: 'SIDERA VI — Martian Space Exploration',
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 31 * scale),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'ENTER MISSION PIN',
            style: MissionTheme.display(33 * scale, tracking: -.6),
          ),
        ),
        SizedBox(height: 8 * scale),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Enter your 4-digit access code.',
            style: TextStyle(
              color: MissionTheme.muted,
              fontSize: 18 * scale,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows PIN length and denial feedback without exposing entered digits.
class _PinStatus extends StatelessWidget {
  const _PinStatus({
    required this.count,
    required this.invalid,
    required this.scale,
    required this.failure,
  });

  final int count;
  final bool invalid;
  final double scale;
  final Animation<double> failure;

  @override
  Widget build(BuildContext context) {
    final color = invalid ? MissionTheme.denied : MissionTheme.orange;
    final status = invalid
        ? 'ACCESS DENIED — INVALID PIN'
        : count == 4
        ? 'PIN READY'
        : '';
    final diameter = 28 * scale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 10 * scale,
      children: [
        Semantics(
          label: '$count of 4 PIN digits entered',
          child: AnimatedBuilder(
            animation: failure,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 24 * scale,
              children: [
                for (var slot = 0; slot < 4; slot++)
                  _dot(diameter, color, slot < count),
              ],
            ),
            builder: (context, child) {
              // One damped movement signals denial and ends at the center.
              final t = failure.value;
              final shift = 9 * math.sin(t * math.pi * 4) * (1 - t);
              return Transform.translate(
                offset: Offset(shift, 0),
                child: child,
              );
            },
          ),
        ),
        SizedBox(
          height: 22 * scale,
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                status,
                style: MissionTheme.display(16 * scale, tracking: 1.2).copyWith(
                  color: invalid ? MissionTheme.denied : MissionTheme.ready,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Paints an empty ring or a glowing masked digit.
  Widget _dot(double diameter, Color color, bool filled) {
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color.withValues(alpha: .15) : MissionTheme.utilityFace,
        border: Border.all(
          color: filled ? color : MissionTheme.outline,
          width: 2,
        ),
      ),
      child: filled
          ? Container(
              width: diameter * .46,
              height: diameter * .46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: .56), blurRadius: 8),
                ],
              ),
            )
          : null,
    );
  }
}

/// Renders the reference cockpit grid with native drawing primitives.
class _CockpitGrid extends CustomPainter {
  const _CockpitGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x07FFFFFF)
      ..strokeWidth = 1;
    for (var x = size.width / 2 % 40; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_CockpitGrid oldDelegate) => false;
}
