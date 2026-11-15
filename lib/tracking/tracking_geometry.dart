import 'dart:math' as math;
import 'dart:ui';

import '../maps/mars_projection.dart';
import '../maps/mars_trek_layers.dart';
import '../missions/mission.dart';

/// Maps the existing square operational overlay to Mars Trek angular coordinates.
final class MissionCoordinates {
  MissionCoordinates(MarsMission mission)
    : center = Offset(
        MarsProjection.signedLongitude(mission.coordinates.eastLongitude),
        mission.coordinates.latitude,
      ),
      span = missionTrekMaps[mission.id]!.shortSideDegrees;

  final Offset center;
  final double span;

  /// Converts a normalized overlay point to signed longitude and latitude.
  Offset toMars(Offset point) => Offset(
    MarsProjection.signedLongitude(center.dx + (point.dx - .5) * span),
    center.dy - (point.dy - .5) * span,
  );

  /// Chooses the wrapped longitude nearest the existing mission viewport.
  Offset toGrid(Offset mars) => Offset(
    .5 + MarsProjection.signedLongitude(mars.dx - center.dx) / span,
    .5 - (mars.dy - center.dy) / span,
  );

  /// Measures a route readout on the Mars sphere.
  double distance(Offset a, Offset b) =>
      surfaceDistance(toMars(a), toMars(b), MarsProjection.radiusMeters);
}

const _radians = math.pi / 180;

/// Measures the spherical arc between east-positive longitude/latitude points.
double surfaceDistance(Offset from, Offset to, double radius) {
  final lat = (to.dy - from.dy) * _radians;
  final lon = (to.dx - from.dx) * _radians;
  final a =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(from.dy * _radians) *
          math.cos(to.dy * _radians) *
          math.pow(math.sin(lon / 2), 2);
  return radius * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

/// Returns the initial bearing clockwise from north on a sphere.
double initialBearing(Offset from, Offset to) {
  final lat1 = from.dy * _radians;
  final lat2 = to.dy * _radians;
  final lon = MarsProjection.signedLongitude(to.dx - from.dx) * _radians;
  return (math.atan2(
            math.sin(lon) * math.cos(lat2),
            math.cos(lat1) * math.sin(lat2) -
                math.sin(lat1) * math.cos(lat2) * math.cos(lon),
          ) /
          _radians) %
      360;
}

/// Returns east/north displacement from a spherical Earth arc and initial bearing.
Offset earthDisplacement(Offset from, Offset to) {
  const earthRadius = 6371008.8;
  final bearing = initialBearing(from, to) * _radians;
  final distance = surfaceDistance(from, to, earthRadius);
  return Offset(distance * math.sin(bearing), distance * math.cos(bearing));
}

/// Applies east/north meters at 1:1 scale using the Mars 2000 sphere.
Offset displaceOnMars(Offset from, Offset eastNorthMeters) {
  if (eastNorthMeters == Offset.zero) return from;
  final arc = eastNorthMeters.distance / MarsProjection.radiusMeters;
  final bearing = math.atan2(eastNorthMeters.dx, eastNorthMeters.dy);
  final lat = from.dy * _radians;
  final nextLat = math.asin(
    (math.sin(lat) * math.cos(arc) +
            math.cos(lat) * math.sin(arc) * math.cos(bearing))
        .clamp(-1, 1),
  );
  final lonChange = math.atan2(
    math.sin(bearing) * math.sin(arc) * math.cos(lat),
    math.cos(arc) - math.sin(lat) * math.sin(nextLat),
  );
  return Offset(
    MarsProjection.signedLongitude(from.dx + lonChange / _radians),
    nextLat / _radians,
  );
}
