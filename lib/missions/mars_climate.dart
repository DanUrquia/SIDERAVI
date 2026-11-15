import 'macda_climate_data.dart';
import 'mars_solar_time.dart';

const marsClimateSource = 'MACDA v2.0 · Mars Year 33';
const marsClimateDatasetDoi = '10.5285/cd037a9ea387438fabf4d674dbe53088';

/// Offline near-surface air temperature derived from MACDA v2.0.
///
/// Interpolates periodically between 15° seasonal bins and two-hourly Mars
/// prime-meridian times. The source tables already interpolate to Habitat Base
/// on the model's lowest pressure level. See docs/scientific_missions.md.
double? marsClimateCelsius(
  String missionId,
  MarsSolarCycle cycle, {
  required double eastLongitude,
}) => macdaClimateCelsius(
  missionId,
  solarLongitude: cycle.solarLongitude,
  primeMeridianHours: cycle.localMeanHours - eastLongitude / 15,
);

double? macdaClimateCelsius(
  String missionId, {
  required double solarLongitude,
  required double primeMeridianHours,
}) {
  final table = macdaClimateData[missionId];
  if (table == null ||
      !solarLongitude.isFinite ||
      !primeMeridianHours.isFinite) {
    return null;
  }
  final season = (solarLongitude % 360) / 15;
  final time = (primeMeridianHours % 24) / 2;
  final row = season.floor();
  final column = time.floor();
  final nextRow = (row + 1) % table.length;
  final nextColumn = (column + 1) % table[row].length;
  final seasonWeight = season - row;
  final timeWeight = time - column;
  double interpolateTime(List<int> samples) =>
      samples[column] + timeWeight * (samples[nextColumn] - samples[column]);
  final before = interpolateTime(table[row]);
  final after = interpolateTime(table[nextRow]);
  return (before + seasonWeight * (after - before)) / 10 - 273.15;
}

String formatMarsClimate(double? celsius) {
  if (celsius == null) return 'Unavailable';
  final degrees = celsius.round();
  return '${degrees < 0 ? '−' : ''}${degrees.abs()} °C';
}
