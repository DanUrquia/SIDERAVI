import 'package:flutter/material.dart';

import '../mission_theme.dart';

/// Dashboard colors and touch controls shared by the map, panels and dialogs.
abstract final class DashboardStyle {
  static const background = Color(0xFF0B1422);
  static const panel = Color(0xFF111B2B);
  static const inset = Color(0xFF0B1320);
  static const outline = Color(0xFF2C3A50);
  static const text = Color(0xFFF5EFE7);
  static const muted = Color(0xFFB0BED1);
  static const orange = Color(0xFFFF632E);
  static const warm = Color(0xFFFFA06D);
  static const cyan = Color(0xFF8DDFFF);
  static const green = Color(0xFF4CDFAB);
  static const danger = Color(0xFFFF6B69);
  static const emergency = Color(0xFF552026);
  static const amber = Color(0xFFFFD280);

  /// Creates the bordered surfaces used for dashboard cards and overlays.
  static BoxDecoration surface({
    Color color = panel,
    Color border = outline,
    double radius = 15,
  }) => BoxDecoration(
    color: color,
    border: Border.all(color: border),
    borderRadius: BorderRadius.circular(radius),
  );
}

/// Keeps dashboard buttons readable and large across landscape layouts.
class DashboardButton extends StatelessWidget {
  /// Builds a control with an optional primary or emergency treatment.
  const DashboardButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.emergency = false,
    this.height = 64,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool emergency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fill = emergency
        ? DashboardStyle.emergency
        : primary
        ? DashboardStyle.orange
        : DashboardStyle.panel;
    final border = emergency
        ? DashboardStyle.danger
        : primary
        ? DashboardStyle.warm
        : DashboardStyle.outline;
    final foreground = primary && !emergency
        ? const Color(0xFF1E100A)
        : DashboardStyle.text;
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: MissionTheme.control(
          fill: fill,
          border: border,
          foreground: foreground,
          elevation: 0,
          radius: 12,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 9,
            children: [
              Icon(icon, size: 23),
              Text(label, style: MissionTheme.display(15, tracking: .65)),
            ],
          ),
        ),
      ),
    );
  }
}
