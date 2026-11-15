import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../mission_action_button.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';

/// The composition shared by the outgoing confirmation and incoming SOS.
class SosEmergencyDialog extends StatelessWidget {
  const SosEmergencyDialog.confirm({
    super.key,
    required this.onPrimary,
    required this.onSecondary,
  }) : senderId = null,
       senderName = null,
       distance = null;

  const SosEmergencyDialog.incoming({
    super.key,
    required String this.senderId,
    required String this.senderName,
    required Widget this.distance,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String? senderId;
  final String? senderName;
  final Widget? distance;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  static const barrierColor = Color(0xD9000000);

  static AnimationStyle? animationStyle(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null;

  @override
  Widget build(BuildContext context) {
    final incoming = senderId != null;
    const coral = Color(0xFFFFA29F);
    return Dialog(
      semanticsRole: SemanticsRole.alertDialog,
      backgroundColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(maxWidth: 430),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      insetAnimationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 100),
      child: Semantics(
        namesRoute: true,
        explicitChildNodes: true,
        label: incoming
            ? 'Emergency distress signal'
            : 'Emergency SOS confirmation',
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: incoming
                  ? const [Color(0xFF591C29), Color(0xFF2B151F)]
                  : const [Color(0xFF281820), Color(0xFF111827)],
            ),
            border: Border.all(
              color: incoming ? DashboardStyle.danger : const Color(0xFF9C555B),
              width: incoming ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _Siren(emphasized: incoming)),
                        Text(
                          incoming
                              ? 'ACTIVE DISTRESS SIGNAL'
                              : 'EMERGENCY BROADCAST',
                          style: MissionTheme.display(
                            12,
                            tracking: 1.6,
                          ).copyWith(color: coral),
                          textAlign: TextAlign.center,
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            incoming ? '$senderId NEEDS HELP' : 'SEND SOS?',
                            style: MissionTheme.display(
                              incoming ? 34 : 32,
                            ).copyWith(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Text(
                          incoming
                              ? '$senderName has requested immediate assistance.'
                              : 'Your crew will receive an emergency alert with your estimated Mars position.',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: MissionTheme.text,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (distance case final readout?) ...[
                          DecoratedBox(
                            decoration: DashboardStyle.surface(
                              color: const Color(0xFF2A111A),
                              border: const Color(0xFFAB4B55),
                              radius: 14,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                spacing: 6,
                                children: [
                                  Text(
                                    'ESTIMATED DISTANCE',
                                    style: MissionTheme.display(
                                      12,
                                      tracking: 1.25,
                                    ).copyWith(color: coral),
                                    textAlign: TextAlign.center,
                                  ),
                                  DefaultTextStyle(
                                    style: MissionTheme.display(
                                      38,
                                    ).copyWith(color: Colors.white),
                                    textAlign: TextAlign.center,
                                    child: readout,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Text(
                            'Rescue waypoint activated',
                            style: TextStyle(
                              color: MissionTheme.text,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                MissionActionButton(
                  label: incoming ? 'VIEW WAYPOINT' : 'SEND SOS',
                  icon: incoming
                      ? Icons.navigation_rounded
                      : Icons.campaign_rounded,
                  onPressed: onPrimary,
                  appearance: MissionActionAppearance.emergency,
                ),
                const SizedBox(height: 10),
                MissionActionButton(
                  label: incoming ? 'DISMISS' : 'CANCEL',
                  icon: Icons.close_rounded,
                  onPressed: onSecondary,
                  appearance: MissionActionAppearance.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Siren extends StatelessWidget {
  const _Siren({required this.emphasized});

  final bool emphasized;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Emergency siren',
    child: Container(
      width: emphasized ? 92 : 70,
      height: emphasized ? 92 : 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x30FF6B69),
        border: Border.all(color: const Color(0x75FF6B69)),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size.square(emphasized ? 54 : 40),
        painter: const _SirenIcon(),
      ),
    ),
  );
}

class _SirenIcon extends CustomPainter {
  const _SirenIcon();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    final outline = Paint()
      ..color = const Color(0xFFFFA09C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final lamp = Path()
      ..moveTo(9, 23)
      ..lineTo(10, 16)
      ..cubicTo(11, 10, 21, 10, 22, 16)
      ..lineTo(23, 23);
    canvas.drawPath(lamp, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(6, 23, 26, 27),
        const Radius.circular(1.5),
      ),
      outline,
    );
    canvas.drawLine(const Offset(16, 4), const Offset(16, 7), outline);
    canvas.drawLine(const Offset(6, 8), const Offset(8, 10), outline);
    canvas.drawLine(const Offset(24, 10), const Offset(26, 8), outline);
    canvas.drawLine(const Offset(3, 16), const Offset(6, 16), outline);
    canvas.drawLine(const Offset(26, 16), const Offset(29, 16), outline);
  }

  @override
  bool shouldRepaint(_SirenIcon oldDelegate) => false;
}
