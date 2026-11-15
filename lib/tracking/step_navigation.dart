import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../sensors/sensor_measurements.dart';
import 'pedometer_monitor.dart';

/// Estimates horizontal displacement from measured steps in a calibrated frame.
final class StepNavigation {
  static const defaultStride = .70;
  static const maxHeadingAge = 2.0;
  static const headingHoldoverSeconds = 6.0;
  static const timestampTolerance = .000001;
  static const _headingHistorySeconds = 45.0;

  final _headings = Queue<({double time, double bearing})>();
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
    if (!calibrated || yaw == null || time < _windowStart) return;
    while (_headings.isNotEmpty &&
        time - _headings.first.time > _headingHistorySeconds) {
      _headings.removeFirst();
    }
    _headings.add((
      time: time,
      bearing: (_referenceBearing! + signedTurn(yaw - _referenceYaw!)) % 360,
    ));
  }

  /// Matches the batch endpoint to the last usable attitude. Short gaps hold
  /// the bearing. The age is measured at the step, independent of delivery.
  double? bearingAt(double time, {double maxAge = headingHoldoverSeconds}) {
    if (_headings.isEmpty || time + timestampTolerance < _windowStart) {
      return null;
    }
    ({double time, double bearing})? matching;
    for (final reading in _headings) {
      if (reading.time > time + timestampTolerance) break;
      matching = reading;
    }
    return matching != null && time - matching.time <= maxAge
        ? matching.bearing
        : null;
  }

  Offset? displacement(
    PedometerObservation sample, {
    double headingMaxAge = headingHoldoverSeconds,
  }) {
    final count = sample.incrementalSteps;
    if (count <= 0 ||
        sample.intervalStart + timestampTolerance < _windowStart) {
      return null;
    }
    final bearing = bearingAt(sample.end, maxAge: headingMaxAge);
    if (bearing == null) return null;
    final native = sample.incrementalDistance;
    final distance = native != null && validStride(native / count)
        ? native
        : count * stride;
    final radians = bearing * math.pi / 180;
    return Offset(distance * math.sin(radians), distance * math.cos(radians));
  }
}
