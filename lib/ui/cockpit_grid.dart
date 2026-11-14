import 'package:flutter/material.dart';

/// Renders the reference cockpit grid with native drawing primitives.
class CockpitGrid extends CustomPainter {
  const CockpitGrid();

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
  bool shouldRepaint(CockpitGrid oldDelegate) => false;
}
