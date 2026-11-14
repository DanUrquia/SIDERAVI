import 'dart:ui';

/// Describes a selectable landmark in the normalized demonstration grid.
final class DemoLandmark {
  /// Places a landmark at an east-positive, screen-south-positive coordinate.
  const DemoLandmark(this.name, this.position);

  final String name;
  final Offset position;
}

/// Supplies offline backdrop metadata and the local navigation scenario.
final class MissionMapConfig {
  /// Defines a scenario independent of the published photograph's geometry.
  const MissionMapConfig({
    required this.asset,
    required this.credit,
    required this.base,
    required this.start,
    required this.teammate,
    required this.radius,
    required this.demoMetersPerUnit,
    required this.landmarks,
    required this.marsTime,
    required this.marsTemperature,
  });

  final String asset;
  final String credit;
  final Offset base;
  final Offset start;
  final Offset teammate;
  final double radius;
  final double demoMetersPerUnit;
  final List<DemoLandmark> landmarks;
  final String marsTime;
  final String marsTemperature;

  /// Checks the circular demo boundary around the base.
  bool contains(Offset point) => (point - base).distance <= radius;
}

/// Maps mission IDs from the briefing catalog to local demo scenarios.
const missionMaps = {
  'jezero': MissionMapConfig(
    asset: 'assets/maps/jezero.jpg',
    credit: 'PIA19303 · NASA/JPL-Caltech/University of Arizona',
    base: Offset(.43, .55),
    start: Offset(.44, .73),
    teammate: Offset(.65, .41),
    radius: .37,
    demoMetersPerUnit: 2700,
    landmarks: [
      DemoLandmark('Delta outcrop', Offset(.53, .32)),
      DemoLandmark('Channel edge', Offset(.24, .50)),
      DemoLandmark('Survey station', Offset(.67, .59)),
    ],
    marsTime: '10:28',
    marsTemperature: '−62 °C',
  ),
  'gale': MissionMapConfig(
    asset: 'assets/maps/gale.jpg',
    credit: 'PIA14290 · NASA/JPL-Caltech/ASU',
    base: Offset(.52, .48),
    start: Offset(.30, .55),
    teammate: Offset(.64, .68),
    radius: .34,
    demoMetersPerUnit: 1500,
    landmarks: [
      DemoLandmark('Sandstone bench', Offset(.41, .26)),
      DemoLandmark('Bedding station', Offset(.70, .39)),
      DemoLandmark('Lower overlook', Offset(.48, .73)),
    ],
    marsTime: '12:10',
    marsTemperature: '−45 °C',
  ),
  'endeavour': MissionMapConfig(
    asset: 'assets/maps/endeavour.jpg',
    credit: 'PIA11837 · NASA/JPL-Caltech/MSSS',
    base: Offset(.56, .53),
    start: Offset(.64, .70),
    teammate: Offset(.37, .44),
    radius: .36,
    demoMetersPerUnit: 4200,
    landmarks: [
      DemoLandmark('Rim outcrop', Offset(.53, .29)),
      DemoLandmark('Ripple field', Offset(.33, .60)),
      DemoLandmark('Ridge overlook', Offset(.79, .50)),
    ],
    marsTime: '09:42',
    marsTemperature: '−68 °C',
  ),
  'columbia-hills': MissionMapConfig(
    asset: 'assets/maps/columbia-hills.jpg',
    credit: 'PIA03253 · NASA/JPL-Caltech/MSSS',
    base: Offset(.47, .50),
    start: Offset(.33, .64),
    teammate: Offset(.63, .27),
    radius: .35,
    demoMetersPerUnit: 3400,
    landmarks: [
      DemoLandmark('Basalt station', Offset(.25, .43)),
      DemoLandmark('Debris slope', Offset(.44, .29)),
      DemoLandmark('Hillside outcrop', Offset(.71, .54)),
    ],
    marsTime: '15:06',
    marsTemperature: '−38 °C',
  ),
  'valles-marineris': MissionMapConfig(
    asset: 'assets/maps/valles-marineris.jpg',
    credit: 'PIA00422 · NASA/JPL/USGS',
    base: Offset(.51, .52),
    start: Offset(.54, .35),
    teammate: Offset(.72, .64),
    radius: .38,
    demoMetersPerUnit: 132000,
    landmarks: [
      DemoLandmark('Western corridor', Offset(.25, .47)),
      DemoLandmark('Wall overlook', Offset(.57, .71)),
      DemoLandmark('Orbital survey point', Offset(.77, .39)),
    ],
    marsTime: '08:35',
    marsTemperature: '−76 °C',
  ),
};
