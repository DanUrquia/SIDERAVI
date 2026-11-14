import 'package:flutter/material.dart';

/// Shared colors, typography, and touch feedback for the mission interface.
abstract final class MissionTheme {
  static const navy = Color(0xFF0B0F1B);
  static const keyFace = Color(0xFF171E2D);
  static const utilityFace = Color(0xFF111726);
  static const outline = Color(0xFF344155);
  static const text = Color(0xFFF8F5F1);
  static const muted = Color(0xFFA1AFC2);
  static const orange = Color(0xFFFF5826);
  static const warmOrange = Color(0xFFFF926B);
  static const ready = Color(0xFF38DCA5);
  static const denied = Color(0xFFFF8482);
  static const black = Color(0xFF040507);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: navy,
    colorScheme: const ColorScheme.dark(
      primary: orange,
      surface: navy,
      onSurface: text,
      error: denied,
    ),
    fontFamily: 'Inter',
  );

  /// Styles high-contrast labels using the bundled cockpit display face.
  static TextStyle display(double size, {double tracking = 0}) => TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: tracking,
    height: 1.1,
  );

  /// Gives the whole button the same focus, pressed, and disabled treatment.
  static ButtonStyle control({
    required Color fill,
    required Color border,
    Color foreground = text,
    double elevation = 3,
    double radius = 16,
  }) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? utilityFace : fill,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? muted : foreground,
    ),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return Colors.black38;
      if (states.contains(WidgetState.focused)) return Colors.white24;
      if (states.contains(WidgetState.hovered)) return Colors.white12;
      return null;
    }),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? outline
            : states.contains(WidgetState.focused)
            ? foreground
            : border,
        width: 2,
      ),
    ),
    elevation: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.disabled)
          ? 0
          : elevation,
    ),
    shadowColor: const WidgetStatePropertyAll(Colors.black87),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
