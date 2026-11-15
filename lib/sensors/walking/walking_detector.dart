import 'dart:math' as math;

enum WalkingMotion {
  insufficient('Insufficient evidence'),
  stationary('Stationary'),
  possible('Possible walking'),
  rhythmic('Confirmed rhythmic walking'),
  irregular('Irregular handheld movement');

  const WalkingMotion(this.label);
  final String label;
}

/// A timestamp-based feasibility detector with no location or position inputs.
final class WalkingDetector {
  static const thresholds = {
    'highPassHz': .6,
    'lowPassHz': 4.0,
    'minimumPeakG': .035,
    'minimumProminenceG': .075,
    'energyTimeSeconds': .35,
    'quietAccelerationRmsG': .026,
    'quietRotationRmsRadS': .16,
    'minimumStepSeconds': .32,
    'maximumStepSeconds': 1.10,
    'minimumIntervalRatio': .68,
    'minimumStepsForRhythm': 4,
    'rotationLimitRadS': 2.2,
    'accelerationLimitG': .65,
    'horizontalToVerticalEnergyLimit': 2.25,
    'handlingHoldSeconds': .28,
    'warmupSeconds': .45,
    'quietWindowSeconds': .8,
    'rhythmExpirySeconds': 1.45,
    'gapSeconds': .10,
  };

  final List<Map<String, Object?>> events = [];
  final List<({double time, double peak, double prominence})> _rhythm = [];
  double? _first;
  double? _latest;
  double? _window;
  double? _lastCandidate;
  double? _lastConfirmed;
  double? _handledAt;
  double? _confirmedPeriod;
  double _baseline = 0;
  double _filtered = 0;
  double _trough = 0;
  double _verticalEnergy = 0;
  double _horizontalEnergy = 0;
  double _rotationEnergy = 0;
  bool _rising = false;
  bool _boutConfirmed = false;
  int _sampleCount = 0;
  int _rejectedSamples = 0;
  int _gaps = 0;
  double _maxGap = 0;
  double _acceleration = 0;
  int candidates = 0;
  int confirmed = 0;
  double confidence = 0;
  double? cadence;
  WalkingMotion motion = WalkingMotion.insufficient;

  /// Consumes a native row. The returned band-passed value accompanies the raw trace.
  double? add(List<Object?> row) {
    if (row.length < 16 ||
        row.take(16).any((value) => value is! num || !value.isFinite)) {
      _rejectedSamples++;
      return null;
    }
    final time = (row[0] as num).toDouble();
    final previous = _latest;
    if (time < 0 || (previous != null && time <= previous)) {
      _rejectedSamples++;
      return null;
    }
    final gx = row[4] as num, gy = row[5] as num, gz = row[6] as num;
    final gravity = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gravity < .5 || gravity > 1.5) {
      _rejectedSamples++;
      return null;
    }
    final ax = row[1] as num, ay = row[2] as num, az = row[3] as num;
    final projected = -(ax * gx + ay * gy + az * gz) / gravity;
    final squaredAcceleration = (ax * ax + ay * ay + az * az).toDouble();
    final rx = row[7] as num, ry = row[8] as num, rz = row[9] as num;
    final squaredRotation = (rx * rx + ry * ry + rz * rz).toDouble();
    _acceleration = math.sqrt(squaredAcceleration);

    _first ??= time;
    _latest = time;
    _sampleCount++;
    final elapsed = previous == null ? 0.0 : (time - previous);
    final gap = elapsed > thresholds['gapSeconds']!;
    if (gap) {
      _gaps++;
      _maxGap = math.max(_maxGap, elapsed);
      _event('sampleGap', time, {'seconds': elapsed});
      _clearWindow(time, 'sampleGap');
    }
    if (_window == null) {
      _window = time;
      _baseline = projected;
      return 0;
    }

    final energyWeight =
        1 - math.exp(-elapsed / thresholds['energyTimeSeconds']!);
    _verticalEnergy += energyWeight * (projected * projected - _verticalEnergy);
    _horizontalEnergy +=
        energyWeight *
        (math.max(0, squaredAcceleration - projected * projected) -
            _horizontalEnergy);
    _rotationEnergy += energyWeight * (squaredRotation - _rotationEnergy);

    final handling =
        squaredRotation > math.pow(thresholds['rotationLimitRadS']!, 2) ||
        _acceleration > thresholds['accelerationLimitG']!;
    if (handling) {
      _handledAt = time;
      _breakRhythm(time, 'abruptHandling');
    } else if (_rhythm.isNotEmpty &&
        time - _rhythm.last.time > thresholds['rhythmExpirySeconds']!) {
      _breakRhythm(time, 'rhythmExpired');
    }
    final recentHandling =
        _handledAt != null &&
        time - _handledAt! < thresholds['handlingHoldSeconds']!;
    final horizontalHandling =
        _horizontalEnergy >
        thresholds['horizontalToVerticalEnergyLimit']! *
            math.max(.0004, _verticalEnergy);
    if (horizontalHandling) _breakRhythm(time, 'horizontalMotion');

    _baseline += _weight('highPassHz', elapsed) * (projected - _baseline);
    final value =
        _filtered +
        _weight('lowPassHz', elapsed) * (projected - _baseline - _filtered);
    final rising = value > _filtered;
    if (value < _filtered) {
      if (_rising &&
          _filtered >= thresholds['minimumPeakG']! &&
          time - _window! >= thresholds['warmupSeconds']!) {
        _peak(
          peakTime: previous!,
          at: time,
          peak: _filtered,
          prominence: _filtered - _trough,
          veto: recentHandling
              ? 'abruptHandling'
              : horizontalHandling
              ? 'horizontalMotion'
              : null,
        );
        _trough = value;
      } else if (value < _trough) {
        _trough = value;
      }
    }
    if (value != _filtered) _rising = rising;
    _filtered = value;
    _classify(time, recentHandling || horizontalHandling);
    return value;
  }

  double _weight(String cutoff, double seconds) =>
      1 - math.exp(-2 * math.pi * thresholds[cutoff]! * seconds);

  void _peak({
    required double peakTime,
    required double at,
    required double peak,
    required double prominence,
    required String? veto,
  }) {
    candidates++;
    final fields = {
      'peakTime': peakTime,
      'peakG': peak,
      'prominenceG': prominence,
    };
    _event('candidate', at, fields);
    final earliest = _lastCandidate;
    final reason =
        veto ??
        (prominence < thresholds['minimumProminenceG']!
            ? 'lowProminence'
            : earliest != null &&
                  peakTime - earliest < thresholds['minimumStepSeconds']!
            ? 'tooClose'
            : null);
    if (reason != null) {
      _event('rejected', at, {...fields, 'reason': reason});
      return;
    }
    _lastCandidate = peakTime;
    final proposed = (time: peakTime, peak: peak, prominence: prominence);
    if (_rhythm.isNotEmpty) {
      final interval = peakTime - _rhythm.last.time;
      final agrees =
          !_boutConfirmed ||
          math.min(interval, _confirmedPeriod!) /
                  math.max(interval, _confirmedPeriod!) >=
              thresholds['minimumIntervalRatio']!;
      if (interval > thresholds['maximumStepSeconds']! || !agrees) {
        _breakRhythm(at, 'inconsistentInterval');
      }
    }
    _rhythm.add(proposed);
    final minimum = thresholds['minimumStepsForRhythm']!.toInt();
    if (_rhythm.length < minimum) return;
    if (_rhythm.length > minimum) _rhythm.removeAt(0);

    var shortest = double.infinity, longest = 0.0, total = 0.0;
    for (var i = 1; i < _rhythm.length; i++) {
      final dt = _rhythm[i].time - _rhythm[i - 1].time;
      shortest = math.min(shortest, dt);
      longest = math.max(longest, dt);
      total += dt;
    }
    final regularity = shortest / longest;
    if (regularity < thresholds['minimumIntervalRatio']!) {
      _breakRhythm(at, 'inconsistentRhythm', keepLatest: true);
      return;
    }
    _confirmedPeriod = total / (_rhythm.length - 1);
    cadence = 60 / _confirmedPeriod!;
    confidence = .55 + .45 * regularity;
    for (final step in _boutConfirmed ? [proposed] : _rhythm) {
      _lastConfirmed = step.time;
      confirmed++;
      _event('confirmed', at, {
        'peakTime': step.time,
        'peakG': step.peak,
        'prominenceG': step.prominence,
        'cadenceSpm': cadence,
        'confidence': confidence,
      });
    }
    _boutConfirmed = true;
  }

  void _breakRhythm(double at, String why, {bool keepLatest = false}) {
    final keep = keepLatest ? _rhythm.last : null;
    if (!_boutConfirmed) {
      for (final step in _rhythm) {
        if (step == keep) continue;
        _event('rejected', at, {
          'peakTime': step.time,
          'peakG': step.peak,
          'prominenceG': step.prominence,
          'reason': why,
        });
      }
    }
    _rhythm.clear();
    if (keep != null) _rhythm.add(keep);
    _boutConfirmed = false;
    _confirmedPeriod = null;
  }

  void _classify(double time, bool handling) {
    final quiet =
        _verticalEnergy + _horizontalEnergy <
            math.pow(thresholds['quietAccelerationRmsG']!, 2) &&
        _rotationEnergy < math.pow(thresholds['quietRotationRmsRadS']!, 2);
    final next = time - _window! < thresholds['warmupSeconds']!
        ? WalkingMotion.insufficient
        : handling
        ? WalkingMotion.irregular
        : _boutConfirmed
        ? WalkingMotion.rhythmic
        : _rhythm.isNotEmpty
        ? WalkingMotion.possible
        : quiet
        ? time - _window! >= thresholds['quietWindowSeconds']!
              ? WalkingMotion.stationary
              : WalkingMotion.insufficient
        : WalkingMotion.irregular;
    if (next != WalkingMotion.rhythmic) {
      cadence = null;
      confidence = next == WalkingMotion.possible ? .12 * _rhythm.length : 0;
    }
    _markMotion(time, next);
  }

  void _markMotion(double at, WalkingMotion next) {
    if (motion == next) return;
    motion = next;
    _event('classification', at, {
      'motion': next.name,
      'confidence': confidence,
      'cadenceSpm': cadence,
    });
  }

  void _clearWindow(double at, String why) {
    _breakRhythm(at, why);
    _window = null;
    _lastCandidate = null;
    _handledAt = null;
    _trough = 0;
    _filtered = 0;
    _rising = false;
    _verticalEnergy = 0;
    _horizontalEnergy = 0;
    _rotationEnergy = 0;
    cadence = null;
    confidence = 0;
    _markMotion(at, WalkingMotion.insufficient);
  }

  void reset(double at) {
    _clearWindow(at, 'counterReset');
    candidates = 0;
    confirmed = 0;
    _lastConfirmed = null;
    _event('counterReset', at);
  }

  /// Finalizes pending peaks without resolving future data beyond the capture edge.
  void finish(double? at) {
    if (at == null) return;
    _breakRhythm(at, 'captureEnded');
  }

  void _event(
    String event,
    double at, [
    Map<String, Object?> fields = const {},
  ]) => events.add({'event': event, 'at': at, ...fields});

  Map<String, Object?> summary() {
    final seconds = _first == null ? 0.0 : _latest! - _first!;
    return {
      'samples': _sampleCount,
      'rejectedSamples': _rejectedSamples,
      'spanSeconds': seconds,
      'observedHz': _sampleCount < 2 || seconds <= 0
          ? null
          : (_sampleCount - 1) / seconds,
      'gaps': _gaps,
      'longestGapSeconds': _maxGap,
      'accelerationG': _sampleCount == 0 ? null : _acceleration,
      'filteredG': _sampleCount == 0 ? null : _filtered,
      'candidates': candidates,
      'confirmed': confirmed,
      'cadenceSpm': cadence,
      'confidence': confidence,
      'motion': motion.name,
      'lastStepAgeSeconds': _lastConfirmed == null
          ? null
          : _latest! - _lastConfirmed!,
      'lastSampleTime': _latest,
    };
  }
}
