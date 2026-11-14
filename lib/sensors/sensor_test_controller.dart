import 'dart:async';
import 'package:flutter/foundation.dart';

import 'sensor_measurements.dart';
import 'sensor_service.dart';

/// Owns polling and serializes native commands for a single foreground test.
final class SensorTestController extends ChangeNotifier {
  /// Uses an injectable clock and transport for repeatable lifecycle tests.
  SensorTestController(this.service, {this.clock = DateTime.now});

  final SensorService service;
  final DateTime Function() clock;
  final measurements = SensorMeasurements();
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  bool _reading = false;
  bool busy = false;
  bool running = false;
  String? error;

  /// Begins status polling without requesting permission or collecting data.
  void observe() {
    unawaited(_poll());
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_poll());
    });
  }

  /// Starts a fresh authorized measurement window.
  Future<void> start() => _perform(() async {
    if (running) return;
    measurements.reset(clock());
    await service.command('start');
    running = true;
  });

  /// Stops foreground collection and records the end of the test.
  Future<void> stop() => _perform(() async {
    if (running) measurements.ended = clock();
    running = false;
    await service.command('stop');
  });

  /// Clears samples and calibration while preserving the current run state.
  Future<void> reset() => _perform(() async {
    await service.command('reset');
    measurements.reset(running ? clock() : null);
  });

  /// Uses the next usable heading as relative zero.
  Future<void> calibrate() => _perform(() async {
    await service.command('clearMotion');
    measurements.calibrate();
  });

  /// Presents the locally generated report after the explicit export action.
  Future<void> export() =>
      _perform(() => service.command('export', measurements.report(clock())));

  /// Serializes UI actions with any outstanding native read.
  Future<void> _perform(Future<void> Function() action) {
    if (_disposed) return Future.value();
    busy = true;
    notifyListeners();
    return _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        error = null;
        await action();
      } catch (_) {
        error = 'Sensor operation unavailable on this device.';
      } finally {
        if (!_disposed) {
          busy = false;
          notifyListeners();
        }
      }
    });
  }

  /// Keeps a single read in flight and discards results after disposal.
  Future<void> _poll() {
    if (_disposed || _reading || busy) return Future.value();
    _reading = true;
    return _pending = _pending.then((_) async {
      try {
        if (_disposed) return;
        final batch = await service.snapshot();
        if (!_disposed) {
          measurements.ingest(batch, clock(), collecting: running);
          if (error == 'Sensor readings unavailable.') error = null;
        }
      } catch (_) {
        if (!_disposed) error = 'Sensor readings unavailable.';
      } finally {
        _reading = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(
      _pending.whenComplete(() async {
        try {
          await service.command('stop');
        } catch (_) {
          // A missing bridge has no active sensor session to stop.
        }
      }),
    );
    super.dispose();
  }
}
