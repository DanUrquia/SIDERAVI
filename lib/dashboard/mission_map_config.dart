import 'dart:math' as math;
import 'dart:ui';

import '../missions/mission.dart';
import '../missions/mission_catalog.dart';
import '../tracking/tracking_geometry.dart';

/// Describes a selectable landmark in the normalized demonstration grid.
final class DemoLandmark {
  /// Places a landmark at an east-positive, screen-south-positive coordinate.
  const DemoLandmark(this.name, this.position);

  final String name;
  final Offset position;
}

/// Supplies offline backdrop metadata and the local navigation scenario.
final class MissionMapConfig {
  MissionMapConfig({
    required MarsMission mission,
    required this.asset,
    required this.credit,
    required this.base,
    required Offset start,
    required Offset teammate,
    required double layoutRadius,
    required List<DemoLandmark> landmarks,
    required this.marsTime,
    required this.marsTemperature,
  }) : radiusMeters = mission.radiusMeters,
       coordinates = MissionCoordinates(mission),
       demoMetersPerSecond = .13 * mission.radiusMeters / layoutRadius {
    final center = coordinates.toMars(base);
    Offset place(Offset point) =>
        coordinates.toGrid(displaceOnMars(center, point));

    // Retain the original bearings and fractional spacing of the simulated
    // waypoints inside the new spherical boundary.
    Offset withinArea(Offset point) {
      final delta = point - base;
      return place(Offset(delta.dx, -delta.dy) * (radiusMeters / layoutRadius));
    }

    this.start = withinArea(start);
    this.teammate = withinArea(teammate);
    this.landmarks = List.unmodifiable([
      for (final landmark in landmarks)
        DemoLandmark(landmark.name, withinArea(landmark.position)),
    ]);
    boundary = List.unmodifiable([
      for (var i = 0; i < 72; i++)
        place(
          Offset(math.sin(i * math.pi / 36), math.cos(i * math.pi / 36)) *
              radiusMeters.toDouble(),
        ),
    ]);
    boundaryBounds = Rect.fromLTRB(
      boundary.map((point) => point.dx).reduce(math.min),
      boundary.map((point) => point.dy).reduce(math.min),
      boundary.map((point) => point.dx).reduce(math.max),
      boundary.map((point) => point.dy).reduce(math.max),
    );
  }

  final String asset;
  final String credit;
  final Offset base;
  late final Offset start;
  late final Offset teammate;
  late final List<DemoLandmark> landmarks;
  final int radiusMeters;
  final MissionCoordinates coordinates;
  final double demoMetersPerSecond;
  late final List<Offset> boundary;
  late final Rect boundaryBounds;
  final String marsTime;
  final String marsTemperature;

  /// Checks the spherical distance to the established Habitat Base.
  bool contains(Offset point) =>
      coordinates.distance(base, point) <= radiusMeters + 1e-6;
}

/// Maps mission IDs from the briefing catalog to local demo scenarios.
final missionMaps = Map<String, MissionMapConfig>.unmodifiable({
  'jezero': MissionMapConfig(
    mission: marsMissions[0],
    asset: 'assets/maps/jezero.jpg',
    credit: 'PIA19303 · NASA/JPL-Caltech/University of Arizona',
    base: Offset(.43, .55),
    start: Offset(.44, .73),
    teammate: Offset(.65, .41),
    layoutRadius: .37,
    landmarks: const [
      DemoLandmark('Delta outcrop', Offset(.53, .32)),
      DemoLandmark('Channel edge', Offset(.24, .50)),
      DemoLandmark('Survey station', Offset(.67, .59)),
    ],
    marsTime: '10:28',
    marsTemperature: '−62 °C',
  ),
  'gale': MissionMapConfig(
    mission: marsMissions[1],
    asset: 'assets/maps/gale.jpg',
    credit: 'PIA14290 · NASA/JPL-Caltech/ASU',
    base: Offset(.52, .48),
    start: Offset(.30, .55),
    teammate: Offset(.64, .68),
    layoutRadius: .34,
    landmarks: const [
      DemoLandmark('Sandstone bench', Offset(.41, .26)),
      DemoLandmark('Bedding station', Offset(.70, .39)),
      DemoLandmark('Lower overlook', Offset(.48, .73)),
    ],
    marsTime: '12:10',
    marsTemperature: '−45 °C',
  ),
  'endeavour': MissionMapConfig(
    mission: marsMissions[2],
    asset: 'assets/maps/endeavour.jpg',
    credit: 'PIA11837 · NASA/JPL-Caltech/MSSS',
    base: Offset(.56, .53),
    start: Offset(.64, .70),
    teammate: Offset(.37, .44),
    layoutRadius: .36,
    landmarks: const [
      DemoLandmark('Rim outcrop', Offset(.53, .29)),
      DemoLandmark('Ripple field', Offset(.33, .60)),
      DemoLandmark('Ridge overlook', Offset(.79, .50)),
    ],
    marsTime: '09:42',
    marsTemperature: '−68 °C',
  ),
  'columbia-hills': MissionMapConfig(
    mission: marsMissions[3],
    asset: 'assets/maps/columbia-hills.jpg',
    credit: 'PIA03253 · NASA/JPL-Caltech/MSSS',
    base: Offset(.47, .50),
    start: Offset(.33, .64),
    teammate: Offset(.63, .27),
    layoutRadius: .35,
    landmarks: const [
      DemoLandmark('Basalt station', Offset(.25, .43)),
      DemoLandmark('Debris slope', Offset(.44, .29)),
      DemoLandmark('Hillside outcrop', Offset(.71, .54)),
    ],
    marsTime: '15:06',
    marsTemperature: '−38 °C',
  ),
  'valles-marineris': MissionMapConfig(
    mission: marsMissions[4],
    asset: 'assets/maps/valles-marineris.jpg',
    credit: 'PIA00422 · NASA/JPL/USGS',
    base: Offset(.51, .52),
    start: Offset(.54, .35),
    teammate: Offset(.72, .64),
    layoutRadius: .38,
    landmarks: const [
      DemoLandmark('Western corridor', Offset(.25, .47)),
      DemoLandmark('Wall overlook', Offset(.57, .71)),
      DemoLandmark('Orbital survey point', Offset(.77, .39)),
    ],
    marsTime: '08:35',
    marsTemperature: '−76 °C',
  ),
});
