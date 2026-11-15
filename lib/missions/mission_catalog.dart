import 'mission.dart';

/// Browsing order for the five Mars expeditions.
const marsMissions = [
  MarsMission(
    id: 'endeavour',
    title: 'Endeavour Crater',
    region: 'Western rim, Endeavour Crater',
    subtitle: 'Opportunity · Western rim',
    description:
        'Endeavour is an ancient impact crater about 22 kilometers across in Meridiani Planum. It became a major science destination for NASA’s Opportunity rover.',
    objectives: [
      MissionObjective(
        'review-minerals',
        'Review the mineral composition of exposed rocks and geological formations.',
      ),
      MissionObjective(
        'survey-crater-rim',
        'Survey the local crater rim and investigate the crater’s structure and surrounding terrain.',
        waypoint: 'Rim outcrop',
      ),
      MissionObjective(
        'ancient-habitability',
        'Examine soil and rocks for clues to past conditions that could have supported life.',
      ),
    ],
    difficulty: MissionDifficulty.challenging,
    coordinates: MarsCoordinates(-2.28, 354.80),
    radiusMeters: 750,
    elevation: MarsBaseElevation(-1783, MarsCoordinates(-2.295, 354.83)),
    type: 'Mineralogy',
    imagery: MissionImagery(
      asset: 'assets/missions/endeavour.jpg',
      instrument: 'Opportunity Pancam',
      caption: 'Endeavour’s western rim from Murray Ridge',
      credit: 'NASA/JPL-Caltech/Cornell Univ./Arizona State Univ.',
      sourceUrl:
          'https://science.nasa.gov/photojournal/endeavour-crater-rim-from-murray-ridge-on-mars/',
    ),
    geographySourceUrl: 'https://planetarynames.wr.usgs.gov/Feature/14501',
  ),
  MarsMission(
    id: 'gale',
    title: 'Gale Crater',
    region: 'Lower Mount Sharp, Gale Crater',
    subtitle: 'Curiosity · Lower Mount Sharp',
    description:
        'Gale is a roughly 154-kilometer-wide impact basin that formed an estimated 3.5 to 3.8 billion years ago. It is named for Australian astronomer Walter F. Gale.',
    objectives: [
      MissionObjective(
        'compare-cross-beds',
        'Follow a short observation loop. Examine cross-bedding in two buttes and compare the apparent directions in which the layers dip.',
        waypoint: 'Sandstone bench',
      ),
      MissionObjective(
        'past-water-activity',
        'Examine exposed rocks for geological evidence of past water activity.',
      ),
      MissionObjective(
        'layered-mount-sharp',
        'Observe Aeolis Mons (Mount Sharp) from the local survey area and identify features that reveal its layered history.',
        waypoint: 'Lower overlook',
      ),
    ],
    difficulty: MissionDifficulty.easy,
    coordinates: MarsCoordinates(-5.44, 137.70),
    radiusMeters: 650,
    elevation: MarsBaseElevation(-2606, MarsCoordinates(-5.415, 137.725)),
    type: 'Sedimentology',
    imagery: MissionImagery(
      asset: 'assets/missions/gale.jpg',
      instrument: 'Curiosity Mastcam',
      caption: 'Layered sandstone in Murray Buttes',
      credit: 'NASA/JPL-Caltech/MSSS',
      sourceUrl:
          'https://science.nasa.gov/photojournal/farewell-to-murray-buttes-image-2/',
    ),
    geographySourceUrl: 'https://planetarynames.wr.usgs.gov/Feature/Gale',
  ),
  MarsMission(
    id: 'columbia-hills',
    title: 'Columbia Hills',
    region: 'Columbia Hills, Gusev Crater',
    subtitle: 'Spirit · Gusev Crater',
    description:
        'The Columbia Hills lie inside Gusev Crater, about 3 kilometers from NASA’s Spirit rover landing site.',
    objectives: [
      MissionObjective(
        'ascent-and-basalt',
        'Plan a safe ascent around loose debris and compare hillside outcrops with basalt from the surrounding plains.',
        waypoint: 'Basalt station',
      ),
      MissionObjective(
        'compare-five-rock-classes',
        'Compare the geological characteristics of five rock classes identified by Spirit: Clovis, Wishstone, Peace, Watchtower, and Backstay.',
      ),
      MissionObjective(
        'ancient-water-evidence',
        'Look for mineralogical and geological evidence of ancient water activity.',
      ),
    ],
    difficulty: MissionDifficulty.hard,
    coordinates: MarsCoordinates(-14.5478, 175.6255),
    radiusMeters: 850,
    elevation: MarsBaseElevation(-1934, MarsCoordinates(-14.5478, 175.6165)),
    type: 'Hillside geology',
    imagery: MissionImagery(
      asset: 'assets/missions/columbia-hills.jpg',
      instrument: 'Spirit Pancam',
      caption: 'Boulders on the slopes of Columbia Hills',
      credit: 'NASA/JPL/Cornell',
      sourceUrl: 'https://science.nasa.gov/photojournal/hillside-boulders/',
    ),
    geographySourceUrl:
        'https://marsnext.jpl.nasa.gov/documents/LandingSiteWorksheet_ColumbiaHillsGusev_final.pdf',
  ),
  MarsMission(
    id: 'valles-marineris',
    title: 'Valles Marineris',
    region: 'Valles Marineris canyon system',
    subtitle: 'Viking · Orbital reconnaissance',
    description:
        'Valles Marineris is the largest canyon system in the Solar System. It stretches across equatorial Mars east of the Tharsis volcanic province.',
    objectives: [
      MissionObjective(
        'plan-safe-corridor',
        'Read the regional terrain map and identify a route that avoids steep cliffs and hazardous ground.',
        waypoint: 'Western corridor',
      ),
      MissionObjective(
        'erosion-and-collapse',
        'Look for erosion, landslides, and collapse. Consider what the exposed rock layers might reveal about past habitability.',
        waypoint: 'Wall overlook',
      ),
      MissionObjective(
        'water-and-climate',
        'Examine landscape features for clues to ancient surface water and how Mars’s climate and atmosphere changed.',
      ),
    ],
    difficulty: MissionDifficulty.extreme,
    coordinates: MarsCoordinates(-13.74, 300.80),
    radiusMeters: 1000,
    elevation: MarsBaseElevation(-3874, MarsCoordinates(-13.83, 300.845)),
    type: 'Canyon geology',
    imagery: MissionImagery(
      asset: 'assets/missions/valles-marineris.jpg',
      instrument: 'Viking Orbiter 1',
      caption: 'Orbital mosaic of the Valles Marineris hemisphere',
      credit: 'NASA/JPL-Caltech',
      sourceUrl:
          'https://science.nasa.gov/resource/valles-marineris-the-grand-canyon-of-mars/',
    ),
    geographySourceUrl: 'https://planetarynames.wr.usgs.gov/Feature/6288',
  ),
  MarsMission(
    id: 'jezero',
    title: 'Jezero Crater',
    region: 'Jezero Crater',
    subtitle: 'Perseverance · Ancient river delta',
    description:
        'Jezero is an impact crater in the Syrtis Major quadrangle of Mars. Its center is near 18.41° N, 77.69° E.',
    objectives: [
      MissionObjective(
        'ancient-liquid-water',
        'Look for geological evidence that liquid water once existed in Jezero Crater.',
        waypoint: 'Delta outcrop',
      ),
      MissionObjective(
        'potential-biosignatures',
        'Examine exposed rocks for possible signs of ancient microbial life, including fossil-like shapes. Consider nonbiological explanations.',
      ),
      MissionObjective(
        'ancient-channel',
        'Survey the surface for a possible ancient river channel or water-flow path.',
        waypoint: 'Channel edge',
      ),
    ],
    difficulty: MissionDifficulty.moderate,
    coordinates: MarsCoordinates(18.41, 77.69),
    radiusMeters: 500,
    elevation: MarsBaseElevation(-2652, MarsCoordinates(18.386, 77.6564)),
    type: 'Delta geology',
    imagery: MissionImagery(
      asset: 'assets/missions/jezero.jpg',
      instrument: 'Perseverance Mastcam-Z',
      caption: 'Jezero delta from Octavia E. Butler Landing',
      credit: 'NASA/JPL-Caltech/ASU/MSSS',
      sourceUrl:
          'https://science.nasa.gov/photojournal/perseverance-view-of-the-delta-in-jezero-crater/',
    ),
    geographySourceUrl: 'https://planetarynames.wr.usgs.gov/Feature/14300',
  ),
];

/// Keeps map and terrain configuration independent of the carousel order.
final marsMissionById = Map<String, MarsMission>.unmodifiable({
  for (final mission in marsMissions) mission.id: mission,
});
