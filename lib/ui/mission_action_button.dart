import 'package:flutter/material.dart';

import 'mission_theme.dart';

enum MissionActionAppearance { launch, emergency, secondary }

/// The full-width action used on the mission briefing and SOS dialogs.
class MissionActionButton extends StatelessWidget {
  const MissionActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.appearance = MissionActionAppearance.launch,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final MissionActionAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final (colors, border, foreground, glow) = switch (appearance) {
      MissionActionAppearance.launch => (
        const [Color(0xFFF36A36), Color(0xFFC7461F)],
        const Color(0xFFD65B2E),
        const Color(0xFF190C09),
        const Color(0x48FF5826),
      ),
      MissionActionAppearance.emergency => (
        const [Color(0xFFFF8581), Color(0xFFF4595D)],
        const Color(0xFFFF928B),
        const Color(0xFF250A10),
        null,
      ),
      MissionActionAppearance.secondary => (
        null,
        MissionTheme.outline,
        MissionTheme.text,
        null,
      ),
    };
    const radius = 14.0;
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled && colors != null
            ? LinearGradient(colors: colors)
            : null,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (enabled && glow != null) BoxShadow(color: glow, blurRadius: 22),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 72,
        child: FilledButton(
          onPressed: onPressed,
          style: MissionTheme.control(
            fill: colors == null
                ? MissionTheme.utilityFace
                : Colors.transparent,
            border: border,
            foreground: foreground,
            elevation: 0,
            radius: radius,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 27),
                Text(label, style: MissionTheme.display(21, tracking: 1.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
