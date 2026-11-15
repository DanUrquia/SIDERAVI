import 'dart:convert';

import 'walking_detector.dart';

enum WalkingScenario {
  table('Stationary on a table'),
  held('Held stationary in both hands'),
  straight('Walking straight'),
  turning('Turning while walking'),
  rotation('Rotating while standing still'),
  handMotion('Moving the iPad by hand without walking'),
  shake('Brief shake while standing still'),
  sitStand('Sitting down or standing up');

  const WalkingScenario(this.label);
  final String label;
}

/// Stores the bounded native trace and the exact input boundaries for replay.
final class WalkingCapture {
  WalkingCapture(this.scenario);

  static const sampleLimit = 5400;
  static const durationLimit = 90.0;
  static const schema = 1;
  static const detectorVersion = 1;
  static const columns = [
    'time',
    'ax',
    'ay',
    'az',
    'gx',
    'gy',
    'gz',
    'wx',
    'wy',
    'wz',
    'qx',
    'qy',
    'qz',
    'qw',
    'interval',
    'orientation',
    'filteredG',
  ];

  final WalkingScenario scenario;
  final WalkingDetector detector = WalkingDetector();
  final List<List<Object?>> _trace = [];
  final List<Map<String, Object?>> _boundaries = [];
  final Map<String, Object?> _device = {};
  Map<String, Object?>? _error;
  String? _reason;
  double? _started;
  double? _ended;
  double? _startUptime;
  double? _endUptime;
  double _elapsed = 0;
  num? _requestedHz;
  int _nativeDropped = 0;

  bool get full => _trace.length >= sampleLimit;

  void ingest(Map<String, Object?> native) {
    for (final key in [
      'model',
      'os',
      'source',
      'motion',
      'accelerometer',
      'gyro',
    ]) {
      if (native[key] case final value?) _device[key] = value;
    }
    _started ??= _number(native['started']);
    _startUptime ??= _number(native['startUptime']);
    _elapsed = _number(native['elapsed']) ?? _elapsed;
    _requestedHz = _number(native['requestedHz']) ?? _requestedHz;
    _nativeDropped = (native['nativeDropped'] as int?) ?? _nativeDropped;
    if (native['samples'] case final List samples) {
      for (final row in samples.whereType<List>().take(
        sampleLimit - _trace.length,
      )) {
        if (row.length != columns.length - 1 ||
            row.any((value) => value is! num || !value.isFinite)) {
          continue;
        }
        _trace.add([...row, detector.add(row)]);
      }
    }
    if (native['active'] == false) {
      _ended = _number(native['ended']);
      _endUptime = _number(native['endUptime']);
      if (native['error'] case final Map error) {
        _error = {'domain': error['domain'], 'code': error['code']};
      }
      finish((native['reason'] as String?) ?? 'captureEnded');
    }
  }

  void reset() {
    if (_reason != null) return;
    final at = _sampleClock;
    if (at == null) return;
    _boundaries.add({'action': 'reset', 'beforeRow': _trace.length, 'at': at});
    detector.reset(at);
  }

  void finish(String reason) {
    if (_reason != null) return;
    _reason = reason;
    final at = _endUptime ?? _sampleClock;
    _boundaries.add({'action': 'stop', 'beforeRow': _trace.length, 'at': at});
    detector.finish(at);
  }

  double? get _sampleClock =>
      _startUptime == null ? null : _startUptime! + _elapsed;

  Map<String, Object?> summary() => {
    ...detector.summary(),
    'scenarioLabel': scenario.label,
    'requestedHz': _requestedHz,
    'elapsedSeconds': _elapsed,
    'nativeDropped': _nativeDropped,
    'traceRows': _trace.length,
    'reason': _reason,
    'error': _error,
    'device': _device,
    'full': full,
    'stale':
        _sampleClock != null &&
        _elapsed > 1.5 &&
        (_trace.isEmpty || _sampleClock! - (_trace.last[0] as num) > 1.5),
  };

  String encodeReport(int? actualSteps) => jsonEncode({
    'schema': schema,
    'detectorVersion': detectorVersion,
    'scenario': scenario.name,
    'scenarioLabel': scenario.label,
    'startedUtc': _utc(_started),
    'endedUtc': _utc(_ended),
    'startUptime': _startUptime,
    'endUptime': _endUptime,
    'actualSteps': actualSteps,
    'thresholds': WalkingDetector.thresholds,
    'columns': columns,
    'summary': summary(),
    'boundaries': _boundaries,
    'trace': _trace,
    'events': detector.events,
  });

  static double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static String? _utc(double? seconds) => seconds == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(
          (seconds * 1000000).round(),
          isUtc: true,
        ).toIso8601String();
}

/// Recomputes decisions from exported raw rows and explicit reset/stop boundaries.
WalkingDetector replayWalkingReport(Map<String, Object?> report) {
  if (report['schema'] != WalkingCapture.schema) {
    throw const FormatException('Unsupported walking trace schema.');
  }
  final rows = report['trace'] as List;
  final boundaries = report['boundaries'] as List;
  final detector = WalkingDetector();
  var next = 0;
  for (var i = 0; i <= rows.length; i++) {
    while (next < boundaries.length && boundaries[next]['beforeRow'] == i) {
      final boundary = boundaries[next++] as Map;
      final at = (boundary['at'] as num?)?.toDouble();
      switch (boundary['action']) {
        case 'reset' when at != null:
          detector.reset(at);
        case 'stop' when i == rows.length:
          detector.finish(at);
        default:
          throw const FormatException('Invalid walking report boundary.');
      }
    }
    if (i < rows.length) detector.add(rows[i] as List);
  }
  if (next < boundaries.length) {
    throw const FormatException('Invalid walking report boundary index.');
  }
  return detector;
}
