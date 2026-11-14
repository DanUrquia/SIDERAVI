import 'package:flutter/widgets.dart';

/// Controls the viewport transform shared by the image and all demo markers.
final class TerrainViewController extends TransformationController {
  static const maxZoom = 4.0;

  /// Zooms around the visible center, using the same limits as pinch gestures.
  void zoomBy(double factor, Size viewport) {
    final scale = value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, maxZoom);
    if (next == 1) {
      reset();
      return;
    }
    final center = viewport.center(Offset.zero);
    final scene = toScene(center);
    final x = (center.dx - scene.dx * next).clamp(
      viewport.width * (1 - next),
      0.0,
    );
    final y = (center.dy - scene.dy * next).clamp(
      viewport.height * (1 - next),
      0.0,
    );
    value = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(2, 2, next)
      ..setTranslationRaw(x, y, 0);
  }

  /// Restores the full demo scenario.
  void reset() => value = Matrix4.identity();
}
