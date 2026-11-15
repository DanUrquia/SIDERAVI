/// Mars24 local mean solar time (in Mars seconds since local midnight).
///
/// The longitude is positive east and may use either signed or 0–360° form.
/// NASA GISS Mars24 algorithm steps A-2, A-4, A-5, C-2, and C-3.
double marsLocalMeanSolarSeconds(
  DateTime timestamp, {
  required double eastLongitude,
}) {
  final utc = timestamp.toUtc();
  final jdUtc =
      2440587.5 + utc.microsecondsSinceEpoch / Duration.microsecondsPerDay;
  final jdTt = jdUtc + _ttMinusUtc(utc, jdUtc) / Duration.secondsPerDay;
  final solDate = (jdTt - 2451549.5) / 1.0274912517 + 44796.0 - 0.0009626;
  // Mars24 subtracts west-positive longitude. The mission catalog uses east.
  final localSol = solDate + eastLongitude / 360;
  return (localSol % 1) * Duration.secondsPerDay;
}

/// Formats a local mean Mars clock at the dashboard's minute resolution.
String formatMarsLocalMeanSolarTime(
  DateTime timestamp, {
  required double eastLongitude,
}) {
  final minutes =
      marsLocalMeanSolarSeconds(timestamp, eastLongitude: eastLongitude) ~/
      Duration.secondsPerMinute;
  final hour = (minutes ~/ Duration.minutesPerHour).toString().padLeft(2, '0');
  final minute = (minutes % Duration.minutesPerHour).toString().padLeft(2, '0');
  return '$hour:$minute';
}

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
