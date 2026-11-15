import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/sensors/walking/walking_capture.dart';
import 'package:sidera_vi/sensors/walking/walking_detector.dart';
import 'package:sidera_vi/sensors/walking/walking_lab_controller.dart';
import 'package:sidera_vi/ui/dashboard/walking_detection_lab.dart';

/// Synthetic testing signals. These rows supply no evidence about physical accuracy.
List<double> _syntheticRow(
  double t, {
  double vertical = 0,
  double horizontal = 0,
  double rotation = 0,
  bool alternateOrientation = false,
}) => [
  t,
  horizontal,
  alternateOrientation ? vertical : 0,
  alternateOrientation ? 0 : vertical,
  0,
  alternateOrientation ? -1 : 0,
  alternateOrientation ? 0 : -1,
  rotation,
  0,
  0,
  alternateOrientation ? math.sqrt(.5) : 0,
  0,
  0,
  alternateOrientation ? math.sqrt(.5) : 1,
  .02,
  alternateOrientation ? 4 : 3,
];

List<List<double>> _syntheticGait({
  required List<double> periods,
  double from = 0,
  double rest = .8,
  double rotation = 0,
  bool alternateOrientation = false,
  bool secondPeak = false,
}) => [
  for (var t = 0.0; t < rest; t += .02) _syntheticRow(from + t),
  for (var i = 0; i < periods.length; i++)
    for (var t = 0.0; t < periods[i]; t += .02)
      _syntheticRow(
        from + rest + periods.take(i).fold(0.0, (a, b) => a + b) + t,
        vertical:
            .18 * math.sin(2 * math.pi * t / periods[i]) +
            (secondPeak ? .12 * math.sin(6 * math.pi * t / periods[i]) : 0),
        rotation: rotation,
        alternateOrientation: alternateOrientation,
      ),
  _syntheticRow(from + rest + periods.fold(0, (a, b) => a + b)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Synthetic table and held still traces stay quiet', () {
    for (final drift in [0, .006]) {
      final detector = WalkingDetector();
      for (var i = 0; i < 1500; i++) {
        detector.add(
          _syntheticRow(
            i / 50,
            vertical: drift * math.sin(i),
            horizontal: drift * math.cos(i),
            rotation: drift * .1,
          ),
        );
      }
      expect(detector.motion, WalkingMotion.stationary);
      expect(detector.candidates, 0);
      expect(detector.confirmed, 0);
      expect(detector.summary()['observedHz'], closeTo(50, .001));
    }
  });

  test(
    'Synthetic gait confirms rhythmic peaks once across device orientations',
    () {
      for (final rotated in [false, true]) {
        final detector = WalkingDetector();
        for (final row in _syntheticGait(
          periods: List.filled(10, .54),
          alternateOrientation: rotated,
        )) {
          detector.add(row);
          detector.add(row);
        }
        expect(detector.motion, WalkingMotion.rhythmic);
        expect(detector.confirmed, 10);
        expect(detector.cadence, closeTo(111.1, 2));
        expect(
          detector.events
              .where((e) => e['event'] == 'confirmed')
              .map((e) => e['peakTime'])
              .toSet(),
          hasLength(10),
        );
        expect(
          detector.summary()['rejectedSamples'],
          detector.summary()['samples'],
        );
      }
    },
  );

  test('Synthetic variable cadence remains in the walking interval range', () {
    final detector = WalkingDetector();
    for (final row in _syntheticGait(
      periods: [.54, .54, .53, .5, .48, .50, .54, .57, .59, .58],
    )) {
      detector.add(row);
    }
    expect(detector.confirmed, 10);
    expect(detector.cadence, inInclusiveRange(95, 125));
  });

  test(
    'Synthetic handling controls reject rotation, horizontal swings and brief shaking',
    () {
      final rotation = WalkingDetector();
      for (final row in _syntheticGait(
        periods: List.filled(8, .54),
        rotation: 3,
      )) {
        rotation.add(row);
      }
      expect(rotation.confirmed, 0);
      expect(
        rotation.events.any((e) => e['reason'] == 'abruptHandling'),
        isTrue,
      );

      final handling = WalkingDetector();
      for (var i = 0; i < 500; i++) {
        final t = i / 50;
        final swing = math.sin(4 * math.pi * t);
        handling.add(
          _syntheticRow(t, horizontal: .4 * swing, vertical: .11 * swing),
        );
      }
      expect(handling.confirmed, 0);
      expect(handling.motion, WalkingMotion.irregular);
      expect(
        handling.events.any((e) => e['reason'] == 'horizontalMotion'),
        isTrue,
      );

      final shake = WalkingDetector();
      for (var i = 0; i < 120; i++) {
        final burst = i >= 50 && i < 65;
        shake.add(
          _syntheticRow(
            i / 50,
            vertical: burst ? .9 * math.sin(i) : 0,
            rotation: burst ? 3 : 0,
          ),
        );
      }
      expect(shake.confirmed, 0);
    },
  );

  test(
    'Synthetic double peaks and short irregular bouts do not inflate steps',
    () {
      final detector = WalkingDetector();
      for (final row in _syntheticGait(
        periods: List.filled(8, .72),
        secondPeak: true,
      )) {
        detector.add(row);
      }
      expect(detector.confirmed, lessThanOrEqualTo(8));
      expect(
        detector.events.any(
          (e) => ['tooClose', 'lowProminence'].contains(e['reason']),
        ),
        isTrue,
      );

      final irregular = WalkingDetector();
      for (final row in _syntheticGait(
        periods: [.45, .82, .36, .98, .44, .79, .37, .99],
      )) {
        irregular.add(row);
      }
      expect(irregular.confirmed, 0);
    },
  );

  test('Synthetic gaps, start/stop and reset decisions replay exactly', () {
    final capture = WalkingCapture(WalkingScenario.straight);
    void batch(
      List<List<double>> rows, {
      required double elapsed,
      bool active = true,
    }) {
      capture.ingest({
        'active': active,
        'startUptime': 30,
        'started': 1700000000,
        'elapsed': elapsed,
        'requestedHz': 50,
        'source': 'synthetic',
        'samples': rows,
        if (!active) ...{
          'endUptime': 30 + elapsed,
          'ended': 1700000000 + elapsed,
          'reason': 'operator',
        },
      });
    }

    batch(_syntheticGait(from: 30, periods: List.filled(5, .54)), elapsed: 3.5);
    expect(capture.detector.confirmed, 5);
    capture.reset();
    expect(capture.detector.confirmed, 0);
    batch(
      _syntheticGait(from: 35, periods: List.filled(2, .54)),
      elapsed: 6.88,
    );
    batch(
      _syntheticGait(from: 38, periods: List.filled(2, .54)),
      elapsed: 9.88,
      active: false,
    );
    expect(capture.detector.confirmed, 0);
    expect(capture.detector.summary()['gaps'], 2);
    expect(
      capture.detector.events.any((e) => e['reason'] == 'captureEnded'),
      isTrue,
    );

    final report = jsonDecode(capture.encodeReport(9)) as Map<String, Object?>;
    final replay = replayWalkingReport(report);
    expect(replay.summary(), capture.detector.summary());
    expect(replay.events, report['events']);
    expect(report['actualSteps'], 9);
    expect(report['scenarioLabel'], 'Walking straight');
    expect((report['summary'] as Map)['device']['source'], 'synthetic');
    expect(
      (report['trace'] as List).first,
      hasLength(WalkingCapture.columns.length),
    );
  });

  test('Synthetic periodic vertical hand motion demonstrates ambiguity', () {
    // The same device trajectory can be generated while standing. A sensor-only
    // detector cannot infer the cause of an identical signal.
    final detector = WalkingDetector();
    for (final row in _syntheticGait(periods: List.filled(6, .52))) {
      detector.add(row);
    }
    expect(detector.confirmed, 6);
  });

  test(
    'Lab drains and exports its own stopped capture through the isolate',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? labId;
      String? json;
      const supported = {
        'motion': true,
        'accelerometer': true,
        'gyro': true,
        'source': 'synthetic',
        'model': 'Test iPad',
        'os': 'Test OS',
      };
      messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, (
        call,
      ) async {
        switch (call.method) {
          case 'walkingSnapshot':
            if (call.arguments == null) return supported;
            expect(call.arguments, labId);
            return {...supported, 'active': true, 'elapsed': .2, 'samples': []};
          case 'startWalking':
            labId = call.arguments as String;
            return {
              ...supported,
              'active': true,
              'started': 1700000000,
              'startUptime': 0,
              'elapsed': 0,
              'requestedHz': 50,
              'samples': [],
            };
          case 'stopWalking':
            expect(call.arguments, {'id': labId, 'reason': 'appInactive'});
            return {
              ...supported,
              'active': false,
              'reason': 'appInactive',
              'endUptime': 1.2,
              'ended': 1700000001.2,
              'elapsed': 1.2,
              'samples': [for (var i = 0; i < 60; i++) _syntheticRow(i / 50)],
            };
          case 'exportWalking':
            json = call.arguments as String;
            return null;
          default:
            fail('Unexpected method ${call.method}');
        }
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );

      final lab = WalkingLabController();
      addTearDown(lab.dispose);
      Future<void> waitFor(bool Function() predicate) {
        final ready = Completer<void>();
        void check() {
          if (predicate() && !ready.isCompleted) ready.complete();
        }

        lab.addListener(check);
        check();
        return ready.future
            .timeout(const Duration(seconds: 4))
            .whenComplete(() => lab.removeListener(check));
      }

      await waitFor(() => !lab.checking);
      expect(lab.supported, isTrue);
      lab.setScenario(WalkingScenario.held);
      await lab.start();
      expect(lab.running, isTrue);
      lab.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await waitFor(() => !lab.running);
      expect(lab.reading!['observedHz'], closeTo(50, .001));
      expect(lab.reading!['motion'], 'stationary');
      await lab.export(0);
      final report = jsonDecode(json!) as Map<String, Object?>;
      expect(report['scenario'], 'held');
      expect(report['actualSteps'], 0);
      expect(replayWalkingReport(report).events, report['events']);
    },
  );

  testWidgets(
    'The Lab identifies its separate status and disables capture without sensors',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, (
        MethodCall call,
      ) async {
        expect(call.method, 'walkingSnapshot');
        return {'motion': false, 'accelerometer': false, 'gyro': false};
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showWalkingDetectionLab(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('EXPERIMENTAL — NOT USED FOR NAVIGATION'),
        findsOneWidget,
      );
      expect(find.text('Device motion unavailable'), findsOneWidget);
      final start = find.ancestor(
        of: find.text('START CAPTURE'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
    },
  );
}
