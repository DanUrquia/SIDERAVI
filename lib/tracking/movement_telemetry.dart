import 'dart:collection';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../sensors/earth_fix.dart';
import 'live_movement.dart';

/// Records an opt-in, bounded diagnostic timeline in memory on the current iPad.
final class MovementTelemetry extends ChangeNotifier {
  static const maxEvents = 6000;

  final _events = Queue<Map<String, Object?>>();
  Map<String, Object?> _capabilities = {};
  DateTime? _started;
  DateTime? _stopped;
  int _dropped = 0;
  String? lastDecision;
  String? lastPositionSource;

  bool get recording => _started != null && _stopped == null;
  bool get hasEvents => _started != null;
  int get count => _events.length;
  int get dropped => _dropped;
  Map<String, Object?> get capabilities => Map.unmodifiable(_capabilities);

  /// Opens a fresh local capture with the current dashboard context.
  void start(DateTime time, Map<String, Object?> context) {
    _events.clear();
    _dropped = 0;
    _started = time;
    _stopped = null;
    lastDecision = lastPositionSource = null;
    event(time, 'captureStarted', context);
  }

  /// Ends the current capture while leaving tracking and sharing active.
  void stop(DateTime time) {
    if (!recording) return;
    _append(time, 'captureStopped', {});
    _stopped = time;
    notifyListeners();
  }

  /// Stores runtime availability without querying motion history.
  void updateCapabilities(Map batch) {
    final next = <String, Object?>{
      for (final key in [
        'model',
        'os',
        'authorization',
        'precise',
        'services',
        'motion',
        'gyro',
        'accelerometer',
        'magnetometer',
        'compass',
        'stepCounting',
        'pedometerDistance',
        'pedometerAuthorization',
      ])
        if (batch.containsKey(key)) key: batch[key],
    };
    if (mapEquals(next, _capabilities)) return;
    _capabilities = next;
    notifyListeners();
  }

  /// Records raw, finite location fields and the evidence behind their decision.
  void observation(DateTime time, Map sample, MovementDecision decision) {
    if (!recording) return;
    lastDecision = decision.reason.label;
    event(time, 'locationFix', {
      'earthFix': {
        for (final key in [
          'latitude',
          'longitude',
          'accuracy',
          'time',
          'received',
          'callbackBatch',
          'speed',
          'speedAccuracy',
          'course',
          'courseAccuracy',
          'simulatedBySoftware',
          'producedByAccessory',
        ])
          if (sample[key] is bool || finiteReading(sample, key) != null)
            key: sample[key],
      },
      'baseline': _earthFix(decision.baseline),
      'candidate': _earthFix(decision.candidate),
      'observedMeters': decision.distance,
      'combinedUncertaintyMeters': decision.uncertainty,
      'estimatedMetersPerSecond': decision.estimatedSpeed,
      'appliedMarsMeters': decision.step?.distance ?? 0,
      'decision': decision.reason.name,
    });
  }

  /// Records each local pose change with its specific writer.
  void position(DateTime time, String source, Offset before, Offset after) {
    if (!recording) return;
    lastPositionSource = source;
    event(time, 'positionChanged', {
      'source': source,
      'before': marsPosition(before),
      'after': marsPosition(after),
    });
  }

  /// Adds a mode, reset, restoration, connection or local navigation event.
  void event(DateTime time, String type, Map<String, Object?> fields) {
    if (!recording) return;
    _append(time, type, fields);
    notifyListeners();
  }

  void _append(DateTime time, String type, Map<String, Object?> fields) {
    if (_events.length == maxEvents) {
      _events.removeFirst();
      _dropped++;
    }
    _events.add({
      'at': time.toUtc().toIso8601String(),
      'event': type,
      ...fields,
    });
  }

  /// Produces a local-only JSON snapshot for the system share sheet.
  String export() => JsonEncoder.withIndent('  ').convert({
    'schema': 'sidera-movement-v1',
    'started': _started?.toUtc().toIso8601String(),
    'stopped': _stopped?.toUtc().toIso8601String(),
    'capabilities': _capabilities,
    'droppedEvents': _dropped,
    'events': _events.toList(),
  });
}

/// Labels a coordinate as simulated Mars data rather than an Earth fix.
Map<String, double> marsPosition(Offset point) => {
  'marsLat': point.dy,
  'marsLon': point.dx,
};

Map<String, double>? _earthFix(EarthFix? fix) => fix == null
    ? null
    : {
        'latitude': fix.point.dy,
        'longitude': fix.point.dx,
        'time': fix.time,
        'accuracy': fix.accuracy,
      };
