import 'dart:convert';
import 'dart:math' as math;

typedef Sample = Map<String, Object?>;

/// Calculates great-circle distance using the mean Earth radius.
double earthDistance(double lat1, double lon1, double lat2, double lon2) {
  const radians = math.pi / 180;
  final lat = (lat2 - lat1) * radians;
  final lon = (lon2 - lon1) * radians;
  final a =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(lat1 * radians) *
          math.cos(lat2 * radians) *
          math.pow(math.sin(lon / 2), 2);
  return 6371008.8 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

/// Wraps a relative angle to the shortest signed turn around the device.
double signedTurn(double degrees) => (degrees + 180) % 360 - 180;

/// Stores bounded raw samples and conservative movement estimates for one test.
final class SensorMeasurements {
  static const maxSamples = 900;
  static const maxLocationAge = 15.0;
  static const maxAccuracy = 100.0;

  Sample capabilities = {};
  final rawLocations = <Sample>[];
  final filteredLocations = <Sample>[];
  final orientations = <Sample>[];
  DateTime? started;
  DateTime? ended;
  Sample? latestLocation;
  Sample? latestOrientation;
  Sample? _origin;
  Sample? _anchor;
  double? _reference;
  String? _frame;
  int received = 0;
  int accepted = 0;
  int rejected = 0;
  int orientationCount = 0;
  int calibrationCount = 0;
  double? relativeYaw;
  double? displacement;
  double? observedDisplacement;
  double? uncertainty;
  double? lastStep;
  double? lastSegment;
  double path = 0;
  double drift = 0;
  double maxObservedDisplacement = 0;
  double? lastMovementAt;

  /// Opens an empty measurement window.
  void reset(DateTime? at) {
    started = at;
    ended = null;
    rawLocations.clear();
    filteredLocations.clear();
    orientations.clear();
    latestLocation = latestOrientation = _origin = _anchor = null;
    _reference = null;
    _frame = null;
    relativeYaw = displacement = observedDisplacement = uncertainty = lastStep =
        lastSegment = lastMovementAt = null;
    received = accepted = rejected = orientationCount = calibrationCount = 0;
    path = drift = maxObservedDisplacement = 0;
  }

  /// Uses the next valid horizontal bearing as the new zero.
  void calibrate() {
    _reference = null;
    relativeYaw = null;
  }

  /// Separates metadata from samples so idle reads cannot record location.
  void ingest(Sample batch, DateTime now, {required bool collecting}) {
    capabilities = {...batch}
      ..remove('locations')
      ..remove('orientations');
    if (!collecting) return;
    final seconds = now.millisecondsSinceEpoch / 1000;
    for (final item in batch['locations'] as List? ?? const []) {
      _location(Map<String, Object?>.from(item as Map), seconds);
    }
    for (final item in batch['orientations'] as List? ?? const []) {
      _orientation(Map<String, Object?>.from(item as Map));
    }
  }

  /// Rejects stale fixes and requires a displacement beyond both uncertainty radii.
  void _location(Sample sample, double now) {
    final previousRaw = rawLocations.lastOrNull;
    final measurementTime = reading(sample, 'time');
    final previousTime = reading(previousRaw, 'time');
    if (measurementTime != null && previousTime != null) {
      sample['interval'] = measurementTime - previousTime;
    }
    received++;
    _append(rawLocations, sample);
    final lat = reading(sample, 'latitude');
    final lon = reading(sample, 'longitude');
    final accuracy = reading(sample, 'accuracy');
    if (lat == null ||
        lat.abs() > 90 ||
        lon == null ||
        lon.abs() > 180 ||
        accuracy == null ||
        accuracy < 0 ||
        measurementTime == null ||
        now - measurementTime > maxLocationAge ||
        measurementTime > now + 1) {
      rejected++;
      sample['decision'] = 'Invalid or stale';
      return;
    }
    final latestTime = reading(latestLocation, 'time');
    if (latestTime != null && measurementTime <= latestTime) {
      rejected++;
      sample['decision'] = 'Out of order or repeated';
      return;
    }
    latestLocation = sample;
    if (accuracy > maxAccuracy) {
      rejected++;
      sample['decision'] = 'Coarse';
      return;
    }
    final origin = _origin ??= sample;
    final anchor = _anchor;
    final fromStart = _distance(origin, sample);
    final startNoise = reading(origin, 'accuracy')! + accuracy;
    final step = anchor == null ? 0.0 : _distance(anchor, sample);
    final stepNoise = anchor == null
        ? 0.0
        : reading(anchor, 'accuracy')! + accuracy;
    sample['fromStartMeters'] = fromStart;
    sample['fromStartUncertaintyMeters'] = startNoise;
    sample['fromPreviousAcceptedMeters'] = anchor == null ? null : step;
    sample['stepUncertaintyMeters'] = anchor == null ? null : stepNoise;
    observedDisplacement = fromStart;
    maxObservedDisplacement = math.max(maxObservedDisplacement, fromStart);
    uncertainty = startNoise;
    displacement = fromStart > startNoise ? fromStart : null;
    lastStep = anchor != null && step > stepNoise ? step : null;
    if (anchor != null && step <= stepNoise) {
      drift = math.max(drift, fromStart);
      rejected++;
      sample['decision'] = 'Within uncertainty';
      return;
    }
    accepted++;
    _anchor = sample;
    if (anchor != null) {
      lastMovementAt = measurementTime;
      lastSegment = step;
      path += step;
    }
    sample['decision'] = anchor == null ? 'Baseline' : 'Above uncertainty';
    _append(filteredLocations, sample);
  }

  /// Calibrates automatically on the first usable sample or interface rotation.
  void _orientation(Sample sample) {
    final currentFrame = sample['frame'] as String?;
    if (currentFrame != _frame) {
      _frame = currentFrame;
      calibrate();
    }
    final yaw = reading(sample, 'yaw');
    if (yaw != null && _reference == null) {
      _reference = yaw;
      calibrationCount++;
    }
    relativeYaw = yaw == null ? null : signedTurn(yaw - _reference!);
    sample['relativeYaw'] = relativeYaw;
    sample['calibration'] = calibrationCount;
    orientationCount++;
    latestOrientation = sample;
    _append(orientations, sample);
  }

  /// Formats the owned measurement window as a shareable, local JSON report.
  String report(DateTime now) => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'device': capabilities['model'],
    'iPadOS': capabilities['os'],
    'started': started?.toUtc().toIso8601String(),
    'ended': (ended ?? now).toUtc().toIso8601String(),
    'capabilities': capabilities,
    'rawLocationObservations': rawLocations,
    'filteredLocationObservations': filteredLocations,
    'relativeOrientationSamples': orientations,
    'summary': {
      'received': received,
      'accepted': accepted,
      'rejected': rejected,
      'acceptedPathMeters': path,
      'observedDisplacementMeters': observedDisplacement,
      'maxObservedDisplacementMeters': maxObservedDisplacement,
      'displacementUncertaintyMeters': uncertainty,
      'maxWithinUncertaintyDisplacementMeters': drift,
      'orientationUpdates': orientationCount,
      'locationHzRecent': frequency(rawLocations),
      'orientationHzRecent': frequency(orientations),
    },
    'limitations': [
      'Earth location fixes may be approximate. Core Location does not identify GNSS usage.',
      'Reported accuracy radii are uncertainty estimates. Accepted path is a coarse sampled estimate.',
      'Relative heading can drift and describes the device, independently of direction of travel.',
      'Each sample list retains at most $maxSamples entries. Counters cover the entire test.',
    ],
  });

  /// Estimates update frequency from the most recent 20 sample timestamps.
  static double? frequency(List<Sample> samples) {
    final intervals = _recentIntervals(samples);
    if (intervals.isEmpty) return null;
    return intervals.length / intervals.reduce((sum, value) => sum + value);
  }

  /// Checks for recent gaps as well as sustained delivery.
  static bool motionIsConsistent(List<Sample> samples) {
    final intervals = _recentIntervals(samples);
    if (intervals.length < 4 || intervals.any((gap) => gap > .5)) return false;
    return intervals.reduce((sum, value) => sum + value) / intervals.length <=
        .2;
  }

  /// Uses positive timestamp intervals within the latest 20 observations.
  static List<double> _recentIntervals(List<Sample> samples) {
    final firstIndex = math.max(0, samples.length - 20);
    final intervals = <double>[];
    for (var i = firstIndex + 1; i < samples.length; i++) {
      final previous = reading(samples[i - 1], 'time');
      final current = reading(samples[i], 'time');
      if (previous != null && current != null && current > previous) {
        intervals.add(current - previous);
      }
    }
    return intervals;
  }

  /// Extracts only finite numeric sensor readings.
  static double? reading(Sample? sample, String key) {
    final value = sample?[key];
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  /// Retains the latest samples under a fixed memory budget.
  void _append(List<Sample> samples, Sample sample) {
    samples.add(sample);
    if (samples.length > maxSamples) samples.removeAt(0);
  }

  /// Measures one geodesic segment between validated fixes.
  double _distance(Sample from, Sample to) => earthDistance(
    reading(from, 'latitude')!,
    reading(from, 'longitude')!,
    reading(to, 'latitude')!,
    reading(to, 'longitude')!,
  );
}
