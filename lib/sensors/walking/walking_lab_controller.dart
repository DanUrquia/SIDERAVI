import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';

import '../sensor_service.dart';
import 'walking_capture.dart';

/// Connects one visible Lab panel to the opt-in native buffer and analysis isolate.
final class WalkingLabController extends ChangeNotifier
    with WidgetsBindingObserver {
  WalkingLabController() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _queue(() async {
        device = await _native('walkingSnapshot');
        checking = false;
      }, notify: true),
    );
  }

  WalkingScenario scenario = WalkingScenario.table;
  Map<String, Object?> device = {};
  Map<String, Object?>? reading;
  bool checking = true;
  bool busy = false;
  bool running = false;
  String? error;
  _WalkingWorker? _worker;
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _pollQueued = false;
  bool _foreground = true;
  bool _disposed = false;
  static int _nextId = 0;
  String? _captureId;

  bool get supported =>
      device['motion'] == true &&
      device['accelerometer'] == true &&
      device['gyro'] == true;
  bool get hasReport => !running && reading != null;

  void setScenario(WalkingScenario value) {
    if (!running && !busy) {
      scenario = value;
      notifyListeners();
    }
  }

  Future<void> start() => _action(() async {
    if (running || !_foreground || !supported) return;
    final worker = _worker ??= await _WalkingWorker.start();
    if (_disposed || !_foreground) return;
    final id = '${++_nextId}';
    _captureId = id;
    final batch = await _native('startWalking', id);
    if (batch['active'] != true) {
      _captureId = null;
      device = batch;
      error = 'Device motion could not start.';
      return;
    }
    await worker.request('start', scenario.name);
    reading = null;
    await _ingest(batch);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _poll());
  });

  Future<void> stop() => _action(() async {
    if (running) await _stop('operator');
  });

  Future<void> reset() => _action(() async {
    if (!running) return;
    await _ingest(await _native('walkingSnapshot', _captureId));
    if (running) {
      reading = await _worker!.request('reset') as Map<String, Object?>;
    }
  });

  Future<void> export(int? actualSteps) => _action(() async {
    if (!hasReport) return;
    final json = await _worker!.request('export', actualSteps) as String;
    await sensorDiagnosticsChannel.invokeMethod<void>('exportWalking', json);
  });

  Future<void> _action(Future<void> Function() task) {
    if (busy || _disposed) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    return _queue(task, notify: true).whenComplete(() {
      busy = false;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _queue(Future<void> Function() task, {bool notify = false}) {
    return _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (_) {
        checking = false;
        error = 'Walking Lab could not complete the sensor or export request.';
        if (_captureId != null) await _stop('bridgeError');
      }
      if (!_disposed && notify) notifyListeners();
    });
  }

  void _poll() {
    if (_pollQueued || busy || !running || _disposed) return;
    _pollQueued = true;
    unawaited(
      _queue(() async {
        if (!running) return;
        await _ingest(await _native('walkingSnapshot', _captureId));
        if (running) {
          final full = reading?['full'] == true;
          final elapsed = (reading?['elapsedSeconds'] as num?) ?? 0;
          if (full || elapsed >= WalkingCapture.durationLimit) {
            await _stop(full ? 'sampleLimit' : 'timeLimit');
          }
        }
      }, notify: true).whenComplete(() => _pollQueued = false),
    );
  }

  Future<void> _ingest(Map<String, Object?> batch) async {
    reading = await _worker!.request('batch', batch) as Map<String, Object?>;
    running = batch['active'] == true;
    if (!running) {
      _captureId = null;
      _timer?.cancel();
    }
  }

  Future<void> _stop(String reason) async {
    _timer?.cancel();
    try {
      await _ingest(
        await _native('stopWalking', {'id': _captureId, 'reason': reason}),
      );
    } catch (_) {
      running = false;
      try {
        reading =
            await _worker?.request('finish', reason) as Map<String, Object?>?;
      } catch (_) {
        reading = null;
      }
      error = 'The motion stream stopped with an interrupted capture.';
    }
  }

  static Future<Map<String, Object?>> _native(
    String method, [
    Object? value,
  ]) async =>
      await sensorDiagnosticsChannel
          .invokeMapMethod<String, Object?>(method, value)
          .timeout(const Duration(seconds: 4)) ??
      {};

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground || _disposed) return;
    _timer?.cancel();
    unawaited(
      _queue(() async {
        if (_captureId != null) await _stop('appInactive');
      }, notify: true),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _pending.whenComplete(() async {
        try {
          if (_captureId case final id?) {
            await _native('stopWalking', {'id': id, 'reason': 'labClosed'});
          }
        } catch (_) {
          // The native foreground and time guards still bound collection.
        } finally {
          _worker?.close();
        }
      }),
    );
    super.dispose();
  }
}

/// Only raw batches and small readouts cross isolates. JSON is encoded off the UI isolate.
final class _WalkingWorker {
  _WalkingWorker(this._isolate, this._send);

  final Isolate _isolate;
  final SendPort _send;

  static Future<_WalkingWorker> start() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_analyze, ready.sendPort);
    try {
      final port = await ready.first as SendPort;
      return _WalkingWorker(isolate, port);
    } finally {
      ready.close();
    }
  }

  Future<Object?> request(String action, [Object? value]) async {
    final reply = ReceivePort();
    _send.send([action, value, reply.sendPort]);
    try {
      final result = await reply.first as List;
      if (result[0] == false) throw StateError(result[1] as String);
      return result[1];
    } finally {
      reply.close();
    }
  }

  void close() => _isolate.kill(priority: Isolate.immediate);

  static void _analyze(SendPort ready) {
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    WalkingCapture? capture;
    inbox.listen((message) {
      final [String action, value, SendPort reply] = message as List;
      try {
        Object? result;
        switch (action) {
          case 'start':
            capture = WalkingCapture(
              WalkingScenario.values.byName(value as String),
            );
          case 'batch':
            capture!.ingest(value as Map<String, Object?>);
            result = capture!.summary();
          case 'reset':
            capture!.reset();
            result = capture!.summary();
          case 'finish':
            capture!.finish(value as String);
            result = capture!.summary();
          case 'export':
            result = capture!.encodeReport(value as int?);
          default:
            throw StateError('Unknown walking analysis command.');
        }
        reply.send([true, result]);
      } catch (error) {
        reply.send([false, error.toString()]);
      }
    });
  }
}
