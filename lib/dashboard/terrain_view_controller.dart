import 'package:flutter/widgets.dart';

/// The geographic overlay spans the shortest axis on every viewport.
Rect missionWorld(Size viewport) => Rect.fromCenter(
  center: viewport.center(Offset.zero),
  width: viewport.shortestSide,
  height: viewport.shortestSide,
);

/// Controls the viewport transform shared by the image and all demo markers.
final class TerrainViewController extends TransformationController {
  static const maxZoom = 4.0;

  /// Limits free lateral exploration to a neighborhood around the mission view.
  EdgeInsets panMargin(Size viewport) =>
      EdgeInsets.all(viewport.shortestSide * 2);

  /// Zooms around the visible center, using the same limits as pinch gestures.
  void zoomBy(double factor, Size viewport, {double limit = maxZoom}) {
    final scale = value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, limit);
    final center = viewport.center(Offset.zero);
    final scene = toScene(center);
    final margin = panMargin(viewport).left * next;
    final x = (center.dx - scene.dx * next).clamp(
      viewport.width * (1 - next) - margin,
      margin,
    );
    final y = (center.dy - scene.dy * next).clamp(
      viewport.height * (1 - next) - margin,
      margin,
    );
    value = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(2, 2, next)
      ..setTranslationRaw(x, y, 0);
  }

  /// Centers a geographic scene point and preserves the current zoom.
  void recenter(Offset scenePoint, Size viewport) {
    final scale = value.getMaxScaleOnAxis();
    final position = viewport.center(Offset.zero) - scenePoint * scale;
    value = Matrix4.copy(value)..setTranslationRaw(position.dx, position.dy, 0);
  }

  /// Centers a local exploration window without changing the map projection.
  void fitArea(Offset sceneCenter, double scale, Size viewport) {
    final position = viewport.center(Offset.zero) - sceneCenter * scale;
    value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(position.dx, position.dy, 0);
  }

  /// Restores the mission center and initial zoom.
  void reset() => value = Matrix4.identity();
}
