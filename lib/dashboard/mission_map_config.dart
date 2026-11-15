import 'dart:math' as math;
import 'dart:ui';

import '../missions/mission.dart';
import '../missions/mission_catalog.dart';
import '../tracking/tracking_geometry.dart';

/// Describes a selectable landmark in the normalized demonstration grid.
final class DemoLandmark {
  /// Places a landmark at an east-positive, screen-south-positive coordinate.
  const DemoLandmark(this.id, this.name, this.position);

  final String id;
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
        DemoLandmark(landmark.id, landmark.name, withinArea(landmark.position)),
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

  /// Checks the spherical distance to the established Habitat Base.
  bool contains(Offset point) =>
      coordinates.distance(base, point) <= radiusMeters + 1e-6;
}

/// Maps mission IDs from the briefing catalog to local demo scenarios.
final missionMaps = Map<String, MissionMapConfig>.unmodifiable({
  'jezero': MissionMapConfig(
    mission: marsMissionById['jezero']!,
    asset: 'assets/maps/jezero.jpg',
    credit: 'PIA19303 · NASA/JPL-Caltech/University of Arizona',
    base: Offset(.43, .55),
    start: Offset(.44, .73),
    teammate: Offset(.65, .41),
    layoutRadius: .37,
    landmarks: const [
      DemoLandmark('delta-outcrop', 'Delta outcrop', Offset(.53, .32)),
      DemoLandmark('channel-edge', 'Channel edge', Offset(.24, .50)),
      DemoLandmark('survey-station', 'Survey station', Offset(.67, .59)),
    ],
  ),
  'gale': MissionMapConfig(
    mission: marsMissionById['gale']!,
    asset: 'assets/maps/gale.jpg',
    credit: 'PIA14290 · NASA/JPL-Caltech/ASU',
    base: Offset(.52, .48),
    start: Offset(.30, .55),
    teammate: Offset(.64, .68),
    layoutRadius: .34,
    landmarks: const [
      DemoLandmark('sandstone-bench', 'Sandstone bench', Offset(.41, .26)),
      DemoLandmark('bedding-station', 'Bedding station', Offset(.70, .39)),
      DemoLandmark('lower-overlook', 'Lower overlook', Offset(.48, .73)),
    ],
  ),
  'endeavour': MissionMapConfig(
    mission: marsMissionById['endeavour']!,
    asset: 'assets/maps/endeavour.jpg',
    credit: 'PIA11837 · NASA/JPL-Caltech/MSSS',
    base: Offset(.56, .53),
    start: Offset(.64, .70),
    teammate: Offset(.37, .44),
    layoutRadius: .36,
    landmarks: const [
      DemoLandmark('rim-outcrop', 'Rim outcrop', Offset(.53, .29)),
      DemoLandmark('ripple-field', 'Ripple field', Offset(.33, .60)),
      DemoLandmark('ridge-overlook', 'Ridge overlook', Offset(.79, .50)),
    ],
  ),
  'columbia-hills': MissionMapConfig(
    mission: marsMissionById['columbia-hills']!,
    asset: 'assets/maps/columbia-hills.jpg',
    credit: 'PIA03253 · NASA/JPL-Caltech/MSSS',
    base: Offset(.47, .50),
    start: Offset(.33, .64),
    teammate: Offset(.63, .27),
    layoutRadius: .35,
    landmarks: const [
      DemoLandmark('basalt-station', 'Basalt station', Offset(.25, .43)),
      DemoLandmark('debris-slope', 'Debris slope', Offset(.44, .29)),
      DemoLandmark('hillside-outcrop', 'Hillside outcrop', Offset(.71, .54)),
    ],
  ),
  'valles-marineris': MissionMapConfig(
    mission: marsMissionById['valles-marineris']!,
    asset: 'assets/maps/valles-marineris.jpg',
    credit: 'PIA00422 · NASA/JPL/USGS',
    base: Offset(.51, .52),
    start: Offset(.54, .35),
    teammate: Offset(.72, .64),
    layoutRadius: .38,
    landmarks: const [
      DemoLandmark('western-corridor', 'Western corridor', Offset(.25, .47)),
      DemoLandmark('wall-overlook', 'Wall overlook', Offset(.57, .71)),
      DemoLandmark(
        'orbital-survey-point',
        'Orbital survey point',
        Offset(.77, .39),
      ),
    ],
  ),
});
