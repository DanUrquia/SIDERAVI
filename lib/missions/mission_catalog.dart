import 'mission.dart';

/// Fixed browsing order for the five Phase 2 educational missions.
const marsMissions = [
  MarsMission(
    id: 'jezero',
    title: 'Jezero Crater',
    region: 'Jezero Crater',
    subtitle: 'Perseverance · Ancient river delta',
    description:
        'A river once emptied into a lake here. Its sediment left a fan-shaped delta with layers exposed in the outcrops.',
    objective:
        'Survey the delta margin and log three changes in the exposed sediment layers before returning to base.',
    difficulty: MissionDifficulty.moderate,
    coordinates: MarsCoordinates(18.41, 77.69),
    radiusKm: 1,
    type: 'Delta stratigraphy',
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
  MarsMission(
    id: 'gale',
    title: 'Gale Crater',
    region: 'Lower Mount Sharp, Gale Crater',
    subtitle: 'Curiosity · Lower Mount Sharp',
    description:
        'At Murray Buttes, wind has carved remnants of sandstone into isolated mesas with visible cross-bedding.',
    objective:
        'From a short observation loop, sketch the cross-beds in two buttes and compare the directions they dip.',
    difficulty: MissionDifficulty.easy,
    coordinates: MarsCoordinates(-5.44, 137.70),
    radiusKm: .5,
    elevation: 'Mount Sharp: ~5 km above crater floor',
    type: 'Outcrop observation',
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
    id: 'endeavour',
    title: 'Endeavour Crater',
    region: 'Western rim, Endeavour Crater',
    subtitle: 'Opportunity · Western rim',
    description:
        'Murray Ridge looks across the crater floor. On the western rim, dark sand ripples partly cover rocks thrown out by the impact.',
    objective:
        'Compare rim outcrops with nearby ripples and plan a return route that avoids loose sand.',
    difficulty: MissionDifficulty.challenging,
    coordinates: MarsCoordinates(-2.28, 354.80),
    radiusKm: 1.5,
    elevation: 'Cape Tribulation: ~135 m above surrounding plain',
    type: 'Rim traverse',
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
    id: 'columbia-hills',
    title: 'Columbia Hills',
    region: 'Columbia Hills, Gusev Crater',
    subtitle: 'Spirit · Gusev Crater',
    description:
        'Spirit found rocks altered by water in these hills. Boulders and loose debris cover parts of the slopes below Husband Hill.',
    objective:
        'Plan an ascent around loose debris to compare hillside outcrops with basalt samples from the plains.',
    difficulty: MissionDifficulty.hard,
    coordinates: MarsCoordinates(-14.5478, 175.6255),
    radiusKm: 1.2,
    elevation: 'Husband Hill: ~90 m above the base',
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
        'Deep chasms and branching troughs cross this canyon system. Viking’s orbital imagery shows how the major sections connect.',
    objective:
        'Read the orbital mosaic and identify a survey corridor that avoids steep canyon walls and broken terrain.',
    difficulty: MissionDifficulty.extreme,
    coordinates: MarsCoordinates(-13.74, 300.80),
    radiusKm: 50,
    elevation: 'Canyon depth: up to ~9.3 km',
    type: 'Orbital route planning',
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
];
