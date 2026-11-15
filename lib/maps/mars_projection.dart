import 'dart:math' as math;
import 'dart:ui';

/// North-up Mars 2000 equidistant cylindrical coordinates in angular degrees.
abstract final class MarsProjection {
  static const radiusMeters = 3396190.0;
  static const globalExtent = Rect.fromLTRB(-180, -90, 180, 90);

  /// Normalizes any east-positive longitude to the interval [−180°, 180°).
  static double signedLongitude(double east) => (east + 180) % 360 - 180;

  /// Normalizes a longitude to the interval [0°, 360°).
  static double eastLongitude(double longitude) => longitude % 360;

  /// Returns horizontal ground scale on the Mars 2000 sphere at a latitude.
  static double metersPerLongitudeDegree(double latitude) =>
      radiusMeters * math.pi / 180 * math.cos(latitude * math.pi / 180);
}

/// Maps the mission's initial scene into the tile grid's angular coordinates.
///
/// Geographic rectangles use west, south, east, north. Scene rectangles use
/// pixel coordinates with y increasing downward. Unwrapped longitudes keep
/// adjacent tiles continuous at the antimeridian.
final class MarsScene {
  /// Fits the configured initial angular span to the viewport's short side.
  MarsScene({
    required this.viewport,
    required double latitude,
    required double longitude,
    required double shortSideDegrees,
  }) : center = Offset(MarsProjection.signedLongitude(longitude), latitude),
       degreesPerPixel = shortSideDegrees / viewport.shortestSide;

  final Size viewport;
  final Offset center;
  final double degreesPerPixel;

  /// Converts a scene pixel to unwrapped longitude and planetocentric latitude.
  Offset toGeographic(Offset pixel) {
    final delta = (pixel - viewport.center(Offset.zero)) * degreesPerPixel;
    return center + Offset(delta.dx, -delta.dy);
  }

  /// Converts longitude and latitude into north-up scene pixels.
  Offset toPixel(Offset geographic) {
    final delta = (geographic - center) / degreesPerPixel;
    return viewport.center(Offset.zero) + Offset(delta.dx, -delta.dy);
  }

  /// Returns the horizontal ground scale at a scene point before camera zoom.
  double groundMetersPerPixel(Offset pixel) =>
      MarsProjection.metersPerLongitudeDegree(toGeographic(pixel).dy) *
      degreesPerPixel;

  /// Returns the longitude and latitude bounds of a scene rectangle.
  Rect geographicBounds(Rect pixels) => Rect.fromPoints(
    toGeographic(pixels.topLeft),
    toGeographic(pixels.bottomRight),
  );

  /// Projects a tile or geographic coverage rectangle into scene space.
  Rect pixelBounds(Rect geographic) => Rect.fromPoints(
    toPixel(geographic.topLeft),
    toPixel(geographic.bottomRight),
  );
}
