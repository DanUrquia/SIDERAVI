import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../maps/mars_projection.dart';
import '../maps/mars_trek_layers.dart';

/// The geographic overlay spans the shortest axis on every viewport.
Rect missionWorld(Size viewport) => Rect.fromCenter(
  center: viewport.center(Offset.zero),
  width: viewport.shortestSide,
  height: viewport.shortestSide,
);

/// Controls the viewport transform shared by the terrain and map overlays.
final class TerrainViewController extends TransformationController {
  static const maxZoom = 4.0;

  final headingUp = ValueNotifier(false);

  double get rotation => math.atan2(value.entry(1, 0), value.entry(0, 0));

  /// The north-up scene rectangle covering all four visible screen corners.
  Rect visibleScene(Size viewport) => MatrixUtils.transformRect(
    Matrix4.inverted(value),
    Offset.zero & viewport,
  );

  /// Matches the finest raster to the tile renderer's logical map pixels.
  static double rasterZoomLimit(MarsScene scene, TrekLayer layer) =>
      (scene.degreesPerPixel / layer.finestDegreesPerPixel).clamp(
        1.0,
        double.infinity,
      );

  /// Converts a horizontal Mars ground span to a continuous camera scale.
  static double zoomForGroundWidth(
    MarsScene scene,
    Offset focus,
    double usableWidth,
    double groundWidth,
  ) => scene.groundMetersPerPixel(focus) * usableWidth / groundWidth;

  /// Places a scene anchor at a screen point with a uniform zoom and rotation.
  void frame(
    Offset scenePoint,
    Offset screenPoint,
    double scale, {
    double? angle,
  }) {
    final matrix = Matrix4.rotationZ(angle ?? rotation)
      ..scaleByDouble(scale, scale, scale, 1);
    final position =
        screenPoint - MatrixUtils.transformPoint(matrix, scenePoint);
    value = matrix..setTranslationRaw(position.dx, position.dy, 0);
  }

  /// Limits free lateral exploration to a neighborhood around the mission view.
  EdgeInsets panMargin(Size viewport) =>
      EdgeInsets.all(viewport.shortestSide * 2);

  /// Zooms around the visible center, using the same limits as pinch gestures.
  void zoomBy(double factor, Size viewport, {double limit = maxZoom}) {
    final scale = value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, limit);
    final center = viewport.center(Offset.zero);
    final scene = toScene(center);
    final boundary = panMargin(viewport).inflateRect(Offset.zero & viewport);
    final extent = visibleScene(viewport).size * (scale / next / 2);
    final focus = Offset(
      scene.dx.clamp(
        boundary.left + extent.width,
        boundary.right - extent.width,
      ),
      scene.dy.clamp(
        boundary.top + extent.height,
        boundary.bottom - extent.height,
      ),
    );
    frame(focus, center, next);
  }

  /// Centers a geographic scene point, preserving zoom and orientation.
  void recenter(Offset scenePoint, Size viewport) => frame(
    scenePoint,
    viewport.center(Offset.zero),
    value.getMaxScaleOnAxis(),
  );

  /// Centers a local exploration window without changing the map projection.
  void fitArea(Offset sceneCenter, double scale, Size viewport) =>
      frame(sceneCenter, viewport.center(Offset.zero), scale);

  /// Restores the mission center and initial zoom.
  void reset() => value = Matrix4.identity();

  @override
  void dispose() {
    headingUp.dispose();
    super.dispose();
  }
}
