import 'dart:math' as math;

/// Mars24 local mean solar time (in Mars seconds since local midnight).
///
/// The longitude is positive east and may use either signed or 0–360° form.
/// NASA GISS Mars24 algorithm steps A-2, A-4, A-5, C-2, and C-3.
double marsLocalMeanSolarSeconds(
  DateTime timestamp, {
  required double eastLongitude,
}) {
  final jdTt = _julianDateTt(timestamp);
  final solDate = (jdTt - 2451549.5) / 1.0274912517 + 44796.0 - 0.0009626;
  // Mars24 subtracts west-positive longitude. The mission catalog uses east.
  final localSol = solDate + eastLongitude / 360;
  return (localSol % 1) * Duration.secondsPerDay;
}

/// Formats a local mean Mars clock at the dashboard's minute resolution.
String formatMarsLocalMeanSolarTime(
  DateTime timestamp, {
  required double eastLongitude,
}) => formatMarsSolarHours(
  marsLocalMeanSolarSeconds(timestamp, eastLongitude: eastLongitude) / 3600,
);

/// Formats an hour on the 24-hour Mars clock, at display precision.
String formatMarsSolarHours(double hours) {
  final minutes = ((hours % 24) * 60).floor();
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

double _julianDateTt(DateTime timestamp) {
  final utc = timestamp.toUtc();
  final jdUtc =
      2440587.5 + utc.microsecondsSinceEpoch / Duration.microsecondsPerDay;
  return jdUtc + _ttMinusUtc(utc, jdUtc) / Duration.secondsPerDay;
}

/// The Sun's position and geometric horizon crossings at a fixed Mars site.
///
/// All clock fields use LMST. A Mars hour is one twenty-fourth of a mean sol.
final class MarsSolarCycle {
  MarsSolarCycle._({
    required this.localMeanHours,
    required this.solarLongitude,
    required this.equationOfTimeDegrees,
    required this.elevationDegrees,
    required this.sunriseHours,
    required this.sunsetHours,
    required this.daylightHours,
    required this.isDaylight,
    required this.progress,
  });

  factory MarsSolarCycle.at(
    DateTime timestamp, {
    required double planetocentricLatitude,
    required double eastLongitude,
  }) {
    final localMean =
        marsLocalMeanSolarSeconds(timestamp, eastLongitude: eastLongitude) /
        3600;
    final orbit = _marsOrbit(_julianDateTt(timestamp) - 2451545.0);
    final noon = 12 - orbit.equationOfTime / 15;
    final hourAngleHours = (localMean - noon + 12) % 24 - 12;

    // Convert planetocentric latitude to the IAU planetographic latitude.
    const radiiRatio = 3376.20 / 3396.19;
    final latitude = planetocentricLatitude * _radiansPerDegree;
    final graphic = math.atan2(
      math.sin(latitude),
      radiiRatio * radiiRatio * math.cos(latitude),
    );
    final offset = math.sin(graphic) * math.sin(orbit.declination);
    final amplitude = math.cos(graphic) * math.cos(orbit.declination);
    final sineElevation = offset + amplitude * _cosDegrees(15 * hourAngleHours);
    final elevation = math.asin(sineElevation.clamp(-1, 1)) / _radiansPerDegree;

    // The center crosses a level geometric horizon. Use the current orbital
    // parameters for both crossings, consistent with the instantaneous altitude.
    final continuousNight = offset + amplitude <= 0;
    final continuousDay = !continuousNight && offset - amplitude >= 0;
    final crossesHorizon = !continuousDay && !continuousNight;
    final halfDay = crossesHorizon
        ? math.acos((-offset / amplitude).clamp(-1, 1)) / _radiansPerDegree / 15
        : continuousDay
        ? 12.0
        : 0.0;
    final isDaylight =
        continuousDay ||
        (crossesHorizon && hourAngleHours.abs() <= halfDay + 1e-10);
    return MarsSolarCycle._(
      localMeanHours: localMean,
      solarLongitude: orbit.solarLongitude,
      equationOfTimeDegrees: orbit.equationOfTime,
      elevationDegrees: elevation,
      sunriseHours: crossesHorizon ? (noon - halfDay) % 24 : null,
      sunsetHours: crossesHorizon ? (noon + halfDay) % 24 : null,
      daylightHours: 2 * halfDay,
      isDaylight: isDaylight,
      progress: isDaylight
          ? ((hourAngleHours + halfDay) / (2 * halfDay)).clamp(0, 1).toDouble()
          : null,
    );
  }

  final double localMeanHours;
  final double solarLongitude;
  final double equationOfTimeDegrees;
  final double elevationDegrees;
  final double? sunriseHours;
  final double? sunsetHours;
  final double daylightHours;
  final bool isDaylight;
  final double? progress;

  String get localTime => formatMarsSolarHours(localMeanHours);
  String get sunrise =>
      sunriseHours == null ? '—' : formatMarsSolarHours(sunriseHours!);
  String get sunset =>
      sunsetHours == null ? '—' : formatMarsSolarHours(sunsetHours!);
  String get daylight {
    final minutes = (daylightHours * 60).round();
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }

  String get skyState => sunriseHours == null
      ? (isDaylight ? 'Polar day' : 'Polar night')
      : (isDaylight ? 'Daylight' : 'Night');
}

const _radiansPerDegree = math.pi / 180;
double _sinDegrees(double degrees) => math.sin(degrees * _radiansPerDegree);
double _cosDegrees(double degrees) => math.cos(degrees * _radiansPerDegree);

// NASA GISS Mars24 algorithm, sections B, C-1 and D-1.
({double solarLongitude, double equationOfTime, double declination}) _marsOrbit(
  double days,
) {
  final meanAnomaly = (19.3871 + 0.52402073 * days) % 360;
  final fictitiousMeanSun = (270.3871 + 0.524038496 * days) % 360;
  var perturbation = 0.0;
  for (final (amplitude, period, phase) in _orbitalPerturbers) {
    perturbation += amplitude * _cosDegrees(0.985626 * days / period + phase);
  }
  final equationOfCenter =
      (10.691 + 3e-7 * days) * _sinDegrees(meanAnomaly) +
      .623 * _sinDegrees(2 * meanAnomaly) +
      .050 * _sinDegrees(3 * meanAnomaly) +
      .005 * _sinDegrees(4 * meanAnomaly) +
      .0005 * _sinDegrees(5 * meanAnomaly) +
      perturbation;
  final ls = (fictitiousMeanSun + equationOfCenter) % 360;
  return (
    solarLongitude: ls,
    equationOfTime:
        2.861 * _sinDegrees(2 * ls) -
        .071 * _sinDegrees(4 * ls) +
        .002 * _sinDegrees(6 * ls) -
        equationOfCenter,
    declination:
        math.asin(.42565 * _sinDegrees(ls)) +
        .25 * _radiansPerDegree * _sinDegrees(ls),
  );
}

const _orbitalPerturbers = [
  (.0071, 2.2353, 49.409),
  (.0057, 2.7543, 168.173),
  (.0039, 1.1177, 191.837),
  (.0037, 15.7866, 21.736),
  (.0021, 2.1354, 15.704),
  (.0020, 2.4694, 95.528),
  (.0018, 32.8493, 49.095),
];

// TAI−UTC from the US Naval Observatory, including the 1972 starting offset.
// IERS Bulletin C 72 confirmed that the last row remains valid through 2026.
const _taiUtcChanges = [
  (20170101, 37),
  (20150701, 36),
  (20120701, 35),
  (20090101, 34),
  (20060101, 33),
  (19990101, 32),
  (19970701, 31),
  (19960101, 30),
  (19940701, 29),
  (19930701, 28),
  (19920701, 27),
  (19910101, 26),
  (19900101, 25),
  (19880101, 24),
  (19850701, 23),
  (19830701, 22),
  (19820701, 21),
  (19810701, 20),
  (19800101, 19),
  (19790101, 18),
  (19780101, 17),
  (19770101, 16),
  (19760101, 15),
  (19750101, 14),
  (19740101, 13),
  (19730101, 12),
  (19720701, 11),
  (19720101, 10),
];

double _ttMinusUtc(DateTime utc, double jdUtc) {
  final date = utc.year * 10000 + utc.month * 100 + utc.day;
  for (final (effective, seconds) in _taiUtcChanges) {
    if (date >= effective) return seconds + 32.184;
  }

  // Mars24's pre-1972 polynomial uses centuries since J2000 in UT.
  final centuries = (jdUtc - 2451545.0) / 36525;
  return 64.184 +
      centuries *
          (59 - centuries * (51.2 + centuries * (67.1 + 16.4 * centuries)));
}
