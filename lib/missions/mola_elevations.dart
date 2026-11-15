/// Maximum MOLA MEGDR elevation (meters above the GMM3 Martian areoid) among
/// 128-pixel-per-degree grid cells whose centers lie inside each mission area.
/// See docs/scientific_missions.md for radii, cell counts, and interpolation.
const missionMaximumGridElevationMeters = <String, int>{
  'endeavour': -1772,
  'gale': -2512,
  'columbia-hills': -1932,
  'valles-marineris': -3751,
  'jezero': -2652,
};
