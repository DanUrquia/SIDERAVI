import 'dart:ui';

import '../sensors/earth_fix.dart';
import 'tracking_geometry.dart';

/// Tracks Earth samples locally, exposing only confirmed east/north steps.
final class LiveMovement {
  static const maxAccuracy = 50.0;
  static const maxGap = 30.0;

  EarthFix? _anchor;
  EarthFix? _candidate;
  EarthFix? _latest;
  double _started = 0;

  /// Rebaselines after interruption without changing the simulated position.
  void reset(double started) {
    _started = started;
    _anchor = _candidate = _latest = null;
  }

  /// Indicates whether a usable fix is still recent.
  bool fresh(double now) =>
      _latest != null && now - _latest!.time <= EarthFix.maximumAge;

  /// Requires two separate, consistent, plausible fixes outside the anchor radius.
  Offset? observe(Map sample, double now) {
    final fix = EarthFix.read(sample, now);
    if (fix == null ||
        fix.accuracy > maxAccuracy ||
        fix.time < _started ||
        (_latest != null && fix.time <= _latest!.time)) {
      return null;
    }
    if (_latest != null && fix.time - _latest!.time > maxGap) {
      _anchor = _candidate = null;
    }
    _latest = fix;
    final anchor = _anchor ??= fix;
    final step = earthDisplacement(anchor.point, fix.point);
    if (!anchor.exceedsUncertainty(fix, step.distance)) {
      _candidate = null;
      return null;
    }
    // Subtract the reported uncertainty for a conservative speed lower bound.
    final minTravel = step.distance - anchor.accuracy - fix.accuracy;
    if (minTravel > (fix.time - anchor.time) * 3.5) {
      _candidate = null;
      return null;
    }
    final candidate = _candidate;
    _candidate = fix;
    if (candidate == null || fix.time - candidate.time < .5) {
      _candidate = candidate ?? fix;
      return null;
    }
    final gap = earthDisplacement(candidate.point, fix.point).distance;
    final candidateStep = earthDisplacement(anchor.point, candidate.point);
    final sameDirection =
        step.dx * candidateStep.dx + step.dy * candidateStep.dy > 0;
    if (fix.time - candidate.time > EarthFix.maximumAge ||
        candidate.exceedsUncertainty(fix, gap) ||
        !sameDirection) {
      return null;
    }
    _anchor = fix;
    _candidate = null;
    return step;
  }
}
