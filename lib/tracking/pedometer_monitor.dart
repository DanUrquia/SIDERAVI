import 'package:flutter/foundation.dart';

import '../sensors/earth_fix.dart';

/// Labels the diagnostic state independently of the simulated Mars position.
enum PedometerState {
  idle('Select Live Sensors'),
  unsupported('Step counting unavailable'),
  denied('Motion permission denied'),
  restricted('Motion permission restricted'),
  waiting('Waiting for pedometer updates'),
  unavailable('Pedometer unavailable'),
  fresh('Fresh pedometer reading'),
  stale('Stale pedometer reading');

  const PedometerState(this.label);
  final String label;
}

/// A timestamped native reading with deduplicated cumulative increments.
typedef PedometerObservation = ({
  double start,
  double intervalStart,
  String? source,
  double end,
  double? received,
  int steps,
  double? distance,
  double? cadence,
  int incrementalSteps,
  double? incrementalDistance,
  String decision,
});

/// Tracks local pedometer measurements without writing simulated movement.
final class PedometerMonitor extends ChangeNotifier {
  static const freshnessSeconds = 8;

  bool stepSupported = false;
  bool distanceSupported = false;
  bool cadenceSupported = false;
  String authorization = 'unknown';
  String? source;
  Map<String, Object?>? error;
  PedometerState state = PedometerState.idle;
  PedometerObservation? latest;
  int? ageSeconds;

  int? _stream;
  double? _streamStart;
  int _previousSteps = 0;
  double? _previousDistance = 0;
  double? _lastStepAt;
  double? _captureStart;

  bool hasCapture = false;
  int? captureSteps;
  double? captureDistance;
  Map<String, Object?>? captureQuery;

  /// A fresh increase shows step detections without inferring a direction.
  bool get recentStepIncrease =>
      state == PedometerState.fresh &&
      _lastStepAt != null &&
      latest != null &&
      latest!.end - _lastStepAt! <= freshnessSeconds;

  /// Starts a capture at an explicit boundary so older cumulative totals cannot leak in.
  void beginCapture(double at) {
    _captureStart = at;
    hasCapture = true;
    captureSteps = null;
    captureDistance = null;
    captureQuery = null;
    notifyListeners();
  }

  /// Preserves the measured totals for review.
  double? endCapture() {
    final start = _captureStart;
    _captureStart = null;
    return start;
  }

  /// Keeps one historical capture result separate from ongoing stream readings.
  void applyCaptureQuery(Map result) {
    captureQuery = <String, Object?>{
      for (final key in [
        'outcome',
        'domain',
        'code',
        'steps',
        'distance',
        'start',
        'end',
      ])
        if (result[key] is String || finiteReading(result, key) != null)
          key: result[key],
    };
    final steps = result['steps'];
    if (result['outcome'] == 'measured' &&
        captureSteps == null &&
        steps is int &&
        steps >= 0) {
      captureSteps = steps;
      captureDistance = _nonnegative(result, 'distance');
    }
    notifyListeners();
  }

  /// Reads one drained native window and updates timing, increments and availability.
  void ingest(
    Map? data,
    double now, {
    required bool active,
    required void Function(PedometerObservation sample) onSample,
  }) {
    final previous = (
      state,
      latest,
      ageSeconds,
      authorization,
      source,
      stepSupported,
      distanceSupported,
      cadenceSupported,
      error,
      captureSteps,
      captureDistance,
    );
    final snapshot = data ?? const {};
    source = snapshot['source'] as String?;
    stepSupported = snapshot['stepCounting'] == true;
    distanceSupported = snapshot['distance'] == true;
    cadenceSupported = snapshot['cadence'] == true;
    authorization = snapshot['authorization']?.toString() ?? 'unknown';
    final nativeError = snapshot['error'];
    if (nativeError case final Map details) {
      final next = {
        'domain': details['domain']?.toString(),
        'code': details['code'],
      };
      if (!mapEquals(error, next)) error = next;
    } else {
      error = null;
    }
    final stream = snapshot['stream'];
    if (stream is int && stream != _stream) {
      _stream = stream;
      _streamStart = finiteReading(snapshot, 'started');
      _previousSteps = 0;
      _previousDistance = 0;
      _lastStepAt = null;
      latest = null;
    }
    if (active &&
        stepSupported &&
        authorization != 'denied' &&
        authorization != 'restricted' &&
        _streamStart != null) {
      for (final raw
          in (snapshot['samples'] as List? ?? const []).whereType<Map>()) {
        final result = _read(raw, now);
        if (result != null) onSample(result);
      }
    }
    ageSeconds = latest == null
        ? null
        : (now - latest!.end).clamp(0, double.infinity).floor();
    state = !active
        ? PedometerState.idle
        : data == null
        ? PedometerState.unavailable
        : !stepSupported
        ? PedometerState.unsupported
        : authorization == 'denied'
        ? PedometerState.denied
        : authorization == 'restricted'
        ? PedometerState.restricted
        : error != null
        ? PedometerState.unavailable
        : ageSeconds == null
        ? PedometerState.waiting
        : now - latest!.end > freshnessSeconds
        ? PedometerState.stale
        : PedometerState.fresh;
    if (previous !=
        (
          state,
          latest,
          ageSeconds,
          authorization,
          source,
          stepSupported,
          distanceSupported,
          cadenceSupported,
          error,
          captureSteps,
          captureDistance,
        )) {
      notifyListeners();
    }
  }

  /// Converts cumulative readings to increments once per increasing end timestamp.
  PedometerObservation? _read(Map raw, double now) {
    final start = finiteReading(raw, 'start');
    final end = finiteReading(raw, 'end');
    final steps = raw['steps'];
    final distance = _nonnegative(raw, 'distance');
    if (start == null || end == null || steps is! int || steps < 0) return null;
    final previousEnd = latest?.end;
    final validWindow =
        start >= _streamStart! - 1 &&
        end >= start &&
        end >= _streamStart! &&
        end <= now + 1;
    final duplicate = previousEnd != null && end <= previousEnd;
    final cumulativeReset = steps < _previousSteps;
    final counted = validWindow && !duplicate && !cumulativeReset;
    final previousDistance = _previousDistance;
    final result = (
      start: start,
      intervalStart: previousEnd ?? _streamStart!,
      source: raw['source'] as String? ?? source,
      end: end,
      received: finiteReading(raw, 'received'),
      steps: steps,
      distance: distance,
      cadence: _nonnegative(raw, 'cadence'),
      incrementalSteps: counted ? steps - _previousSteps : 0,
      incrementalDistance:
          counted &&
              distance != null &&
              previousDistance != null &&
              distance >= previousDistance
          ? distance - previousDistance
          : null,
      decision: !validWindow
          ? 'invalidWindow'
          : duplicate
          ? 'duplicateOrOutOfOrder'
          : cumulativeReset
          ? 'cumulativeReset'
          : 'observed',
    );
    if (!validWindow || duplicate) return result;
    _previousSteps = steps;
    _previousDistance = distance ?? (steps == 0 ? 0 : null);
    latest = result;
    if (result.incrementalSteps > 0) _lastStepAt = end;
    final captureStart = _captureStart;
    // The native API counts from stream-start; its reported start may be rounded.
    if (counted && captureStart != null && _streamStart! >= captureStart) {
      captureSteps = (captureSteps ?? 0) + result.incrementalSteps;
      if (result.incrementalDistance case final meters?) {
        captureDistance = (captureDistance ?? 0) + meters;
      }
    }
    return result;
  }

  double? _nonnegative(Map sample, String key) {
    final value = finiteReading(sample, key);
    return value != null && value >= 0 ? value : null;
  }
}
