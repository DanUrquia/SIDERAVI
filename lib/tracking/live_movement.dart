import 'dart:math' as math;
import 'dart:ui';

import '../sensors/earth_fix.dart';
import 'tracking_geometry.dart';

/// Explains what happened to one Core Location observation.
enum MovementReason {
  invalid('Invalid fix'),
  inactive('Tracking paused or inactive'),
  unavailable('Precise location unavailable'),
  stale('Stale fix'),
  oldWindow('Before this tracking window'),
  repeated('Duplicate or out-of-order fix'),
  simulated('Software-simulated location'),
  coarse('Reported accuracy too coarse'),
  baseline('Earth baseline set'),
  gapBaseline('Earth baseline set after a gap'),
  uncertain('Displacement within uncertainty'),
  jump('Spatial discontinuity · rebaseline required'),
  held('Holding position · rebaseline required'),
  implausible('Displacement exceeds the walking envelope'),
  uncorroborated('Usable walking speed and course required'),
  sameCallback('Waiting for a separate location callback'),
  noProgress('Candidate lacks consistent forward progress'),
  pending('Waiting for more corroborated fixes'),
  accepted('Conservative displacement applied');

  const MovementReason(this.label);
  final String label;
}

/// Contains the evidence used for one movement decision, prior to Mars conversion.
final class MovementDecision {
  const MovementDecision(
    this.reason, {
    this.baseline,
    this.candidate,
    this.distance,
    this.uncertainty,
    this.estimatedSpeed,
    this.step,
  });

  final MovementReason reason;
  final EarthFix? baseline;
  final EarthFix? candidate;
  final double? distance;
  final double? uncertainty;
  final double? estimatedSpeed;
  final Offset? step;
}

/// Tracks foreground Earth observations without moving a disputed Mars position.
final class LiveMovement {
  static const maxAccuracy = 50.0;
  static const maxGap = 30.0;
  static const maxUnvalidatedStep = 40.0;
  static const _maxWalkingSpeed = 3.5;
  static const _requiredCandidates = 3;
  static const _minimumProgress = 2.0;

  EarthFix? _anchor;
  EarthFix? _nearAnchor;
  EarthFix? _candidate;
  EarthFix? _latest;
  num? _candidateCallback;
  int _candidateCount = 0;
  double _started = 0;
  bool _requiresRebaseline = false;

  bool get requiresRebaseline => _requiresRebaseline;

  /// Discards an old Earth window while retaining any discontinuity hold.
  void reset(double started) {
    _started = started;
    _anchor = _nearAnchor = _latest = null;
    _clearCandidates();
  }

  /// Explicitly permits a new Earth baseline at the current simulated position.
  void rebaseline(double started) {
    _requiresRebaseline = false;
    reset(started);
  }

  /// Indicates whether a usable Earth fix is still recent.
  bool fresh(double now) =>
      _latest != null && now - _latest!.time <= EarthFix.maximumAge;

  /// Evaluates one fix using spatial continuity and corroborating Core Location data.
  MovementDecision observe(Map sample, double now) {
    final fix = EarthFix.read(sample, now);
    final time = finiteReading(sample, 'time');
    final last = _latest;
    if (fix == null) {
      return _decision(
        time != null && now - time > EarthFix.maximumAge
            ? MovementReason.stale
            : MovementReason.invalid,
      );
    }
    if (fix.time < _started) return _decision(MovementReason.oldWindow);
    if (last != null && fix.time <= last.time) {
      return _decision(MovementReason.repeated);
    }
    if (sample['simulatedBySoftware'] == true) {
      _clearCandidates();
      return _decision(MovementReason.simulated);
    }
    if (fix.accuracy > maxAccuracy) {
      _clearCandidates();
      return _decision(MovementReason.coarse);
    }
    if (_requiresRebaseline) return _decision(MovementReason.held);

    final gap = last != null && fix.time - last.time > maxGap;
    if (_anchor == null || gap) {
      _anchor = _nearAnchor = _latest = fix;
      _clearCandidates();
      return _decision(
        gap ? MovementReason.gapBaseline : MovementReason.baseline,
      );
    }

    final anchor = _anchor!;
    _latest = fix;
    final displacement = earthDisplacement(anchor.point, fix.point);
    final distance = displacement.distance;
    final uncertainty = anchor.accuracy + fix.accuracy;
    final estimatedSpeed = distance / (fix.time - anchor.time);
    MovementDecision decision(MovementReason reason, [Offset? step]) =>
        _decision(
          reason,
          distance: distance,
          uncertainty: uncertainty,
          estimatedSpeed: estimatedSpeed,
          step: step,
        );

    final successiveJump =
        last != null &&
        earthDisplacement(last.point, fix.point).distance >
            math.max(maxUnvalidatedStep, last.accuracy + fix.accuracy);
    if (successiveJump ||
        distance > math.max(maxUnvalidatedStep, uncertainty)) {
      final result = decision(MovementReason.jump);
      _requiresRebaseline = true;
      _clearCandidates();
      return result;
    }

    if (distance <= uncertainty) {
      _nearAnchor = fix;
      final result = decision(MovementReason.uncertain);
      _clearCandidates();
      return result;
    }

    final near = _nearAnchor!;
    final fromRecent = earthDisplacement(near.point, fix.point);
    if (fromRecent.distance - near.accuracy - fix.accuracy >
        (fix.time - near.time) * _maxWalkingSpeed) {
      final result = decision(MovementReason.implausible);
      _clearCandidates();
      return result;
    }

    if (!_corroborated(sample, displacement)) {
      final result = decision(MovementReason.uncorroborated);
      _clearCandidates();
      return result;
    }

    // Core Location can deliver several cached observations in one callback.
    final callback = finiteReading(sample, 'callbackBatch');
    final candidate = _candidate;
    if (candidate != null &&
        (fix.time - candidate.time < .5 ||
            (callback != null && callback == _candidateCallback))) {
      return decision(MovementReason.sameCallback);
    }
    if (candidate != null) {
      final progression = earthDisplacement(candidate.point, fix.point);
      final previousDistance = earthDisplacement(
        anchor.point,
        candidate.point,
      ).distance;
      final consistent =
          fix.time - candidate.time <= EarthFix.maximumAge &&
          distance >= previousDistance + _minimumProgress &&
          progression.distance >= _minimumProgress &&
          _corroborated(sample, progression);
      if (!consistent) {
        final result = decision(MovementReason.noProgress);
        _seedCandidate(fix, callback);
        return result;
      }
    }

    _candidateCount++;
    if (_candidateCount < _requiredCandidates) {
      final result = decision(MovementReason.pending);
      _candidate = fix;
      _candidateCallback = callback;
      return result;
    }

    // Use only the portion beyond the estimated uncertainty, at 1:1 scale.
    final step = displacement * ((distance - uncertainty) / distance);
    final result = decision(MovementReason.accepted, step);
    _anchor = _nearAnchor = fix;
    _clearCandidates();
    return result;
  }

  /// Requires credible walking speed and a course consistent with the displacement.
  bool _corroborated(Map sample, Offset direction) {
    final speed = finiteReading(sample, 'speed');
    final speedAccuracy = finiteReading(sample, 'speedAccuracy');
    final course = finiteReading(sample, 'course');
    final courseAccuracy = finiteReading(sample, 'courseAccuracy');
    if (speed == null ||
        speedAccuracy == null ||
        course == null ||
        courseAccuracy == null ||
        speedAccuracy < 0 ||
        speedAccuracy > 1 ||
        speed > _maxWalkingSpeed ||
        speed - speedAccuracy < .35 ||
        course < 0 ||
        course >= 360 ||
        courseAccuracy < 0 ||
        courseAccuracy > 35) {
      return false;
    }
    final bearing = math.atan2(direction.dx, direction.dy) * 180 / math.pi;
    final difference = ((course - bearing + 180) % 360 - 180).abs();
    return difference <= 45;
  }

  void _seedCandidate(EarthFix fix, num? callback) {
    _candidate = fix;
    _candidateCallback = callback;
    _candidateCount = 1;
  }

  void _clearCandidates() {
    _candidate = null;
    _candidateCallback = null;
    _candidateCount = 0;
  }

  MovementDecision _decision(
    MovementReason reason, {
    double? distance,
    double? uncertainty,
    double? estimatedSpeed,
    Offset? step,
  }) => MovementDecision(
    reason,
    baseline: _anchor,
    candidate: _candidate,
    distance: distance,
    uncertainty: uncertainty,
    estimatedSpeed: estimatedSpeed,
    step: step,
  );
}
