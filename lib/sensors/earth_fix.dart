import 'dart:ui';

/// A finite, recent Core Location fix, shared by the diagnostic and live modes.
final class EarthFix {
  const EarthFix(this.point, this.accuracy, this.time);

  static const maximumAge = 15.0;

  final Offset point;
  final double accuracy;
  final double time;

  /// Rejects invalid coordinates, accuracy, and timestamps before use.
  static EarthFix? read(Map sample, double now) {
    final lat = finiteReading(sample, 'latitude');
    final lon = finiteReading(sample, 'longitude');
    final accuracy = finiteReading(sample, 'accuracy');
    final time = finiteReading(sample, 'time');
    if (lat == null ||
        lat.abs() > 90 ||
        lon == null ||
        lon.abs() > 180 ||
        accuracy == null ||
        accuracy < 0 ||
        time == null ||
        now - time > maximumAge ||
        time > now + 1) {
      return null;
    }
    return EarthFix(Offset(lon, lat), accuracy, time);
  }

  /// Requires the estimated uncertainty circles to be disjoint.
  bool exceedsUncertainty(EarthFix other, double meters) =>
      meters > accuracy + other.accuracy;
}

/// Extracts a finite numeric value from a platform channel sample.
double? finiteReading(Map? sample, String key) {
  final value = sample?[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}
