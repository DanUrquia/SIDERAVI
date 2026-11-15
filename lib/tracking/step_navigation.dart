import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../sensors/sensor_measurements.dart';
import 'pedometer_monitor.dart';

/// Estimates horizontal displacement from measured steps in a calibrated frame.
final class StepNavigation {
  static const defaultStride = .70;
  static const maxHeadingAge = 2.0;
  static const _headingHistorySeconds = 45.0;

  final _headings = Queue<({double time, double? bearing})>();
  double stride = defaultStride;
  double? _referenceYaw;
  double? _referenceBearing;
  double _windowStart = double.infinity;

  bool get calibrated => _referenceYaw != null;

  static bool validStride(double value) =>
      value.isFinite && value >= .25 && value <= 1.5;

  void calibrate(double time, double yaw, double bearing) {
    _referenceYaw = yaw;
    _referenceBearing = bearing;
    _windowStart = time;
    _headings.clear();
    observe(time, yaw);
  }

  void invalidate() {
    _referenceYaw = null;
    _referenceBearing = null;
    _headings.clear();
  }

  void observe(double time, double? yaw) {
    if (!calibrated || time < _windowStart) return;
    while (_headings.isNotEmpty &&
        time - _headings.first.time > _headingHistorySeconds) {
      _headings.removeFirst();
    }
    _headings.add((
      time: time,
      bearing: yaw == null
          ? null
          : (_referenceBearing! + signedTurn(yaw - _referenceYaw!)) % 360,
    ));
  }

  /// Uses the last calibrated heading at the sensor interval's endpoint.
  /// Batches without individual step times share that heading.
  double? bearingAt(double time) {
    if (_headings.isEmpty || time < _windowStart) return null;
    if (time >= _headings.last.time) {
      final last = _headings.last;
      return time - last.time <= maxHeadingAge ? last.bearing : null;
    }
    ({double time, double? bearing})? matching;
    for (final reading in _headings) {
      if (reading.time > time) break;
      matching = reading;
    }
    return matching != null && time - matching.time <= maxHeadingAge
        ? matching.bearing
        : null;
  }

  Offset? displacement(PedometerObservation sample) {
    final count = sample.incrementalSteps;
    if (count <= 0 || sample.intervalStart < _windowStart) return null;
    final bearing = bearingAt(sample.end);
    if (bearing == null) return null;
    final native = sample.incrementalDistance;
    final distance = native != null && validStride(native / count)
        ? native
        : count * stride;
    final radians = bearing * math.pi / 180;
    return Offset(distance * math.sin(radians), distance * math.cos(radians));
  }
}
