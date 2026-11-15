import '../sensors/earth_fix.dart';
import '../sensors/walking/walking_detector.dart';

/// Selects the local rhythm detector only when hardware delivers no new steps.
final class AndroidWalkingFallback {
  static const _hardwareGrace = 5.0;
  static const source = 'androidAcceleration';
  int? _stream;
  WalkingDetector _detector = WalkingDetector();
  final _pending = <double>[];
  bool _hardwareActive = false;
  bool _usingAcceleration = false;
  int _total = 0;

  Map? read(Map? native, double now) {
    if (native == null ||
        native['accelerationFallback'] != true ||
        native['authorization'] != 'authorized') {
      _stream = null;
      return native;
    }
    final stream = native['stream'];
    final start = finiteReading(native, 'started');
    if (stream is! int || start == null) return native;
    if (_stream != stream) {
      _stream = stream;
      _detector = WalkingDetector();
      _pending.clear();
      _hardwareActive = false;
      _usingAcceleration = false;
      _total = 0;
    }
    if (!_usingAcceleration && !_hardwareActive) {
      final samples = (native['samples'] as List? ?? const []).whereType<Map>();
      _hardwareActive = samples.any(
        (sample) => sample['steps'] is int && (sample['steps'] as int) > 0,
      );
      if (_hardwareActive) _pending.clear();
    }
    if (_hardwareActive) return native;

    for (final row
        in (native['accelerationSamples'] as List? ?? const [])
            .whereType<List>()) {
      final time = row.isNotEmpty ? row.first : null;
      if (time is num && time >= start && time <= now + 1) {
        _detector.add(row);
      }
    }
    for (final event in _detector.events) {
      if (event['event'] != 'confirmed') continue;
      final peak = event['peakTime'];
      if (peak is double) _pending.add(peak);
    }
    _detector.events.clear();
    _pending.removeWhere((time) => now - time > 10);
    if (!_usingAcceleration &&
        _pending.isNotEmpty &&
        now - _pending.first >= _hardwareGrace) {
      _usingAcceleration = true;
    }
    if (!_usingAcceleration) return native;
    final samples = [
      for (final time in _pending)
        {
          'start': start,
          'end': time,
          'received': now,
          'steps': ++_total,
          'source': source,
        },
    ];
    _pending.clear();
    return {...native, 'samples': samples, 'source': source};
  }
}
