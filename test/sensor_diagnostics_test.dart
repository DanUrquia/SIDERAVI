import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/sensors/sensor_measurements.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/ui/sensors/sensor_test_screen.dart';

final _now = DateTime.utc(2026, 1, 1);
final _epoch = _now.millisecondsSinceEpoch / 1000;

/// Exercises the diagnostic using synthetic Earth fixes and device attitudes.
void main() {
  test('Earth distance uses a great circle across the antimeridian', () {
    expect(earthDistance(0, 0, .001, 0), closeTo(111.195, .01));
    expect(earthDistance(0, 179.999, 0, -179.999), closeTo(222.39, .01));
    expect(earthDistance(8, 15, 8, 15), 0);
  });

  test('Filters invalid, stale, coarse, noisy and out-of-order fixes', () {
    final measurements = SensorMeasurements()..reset(_now);
    measurements.ingest(
      {
        'locations': [
          _fix(0, -20), // Stale.
          _fix(0, -8, accuracy: -1),
          _fix(0, -7, accuracy: 140),
          _fix(0, -6),
          _fix(.00005, -5),
        ],
      },
      _now,
      collecting: true,
    );

    expect(measurements.received, 5);
    expect(measurements.accepted, 1);
    expect(measurements.rejected, 4);
    expect(measurements.latestLocation?['latitude'], .00005);
    expect(measurements.observedDisplacement, closeTo(5.56, .01));
    expect(measurements.uncertainty, 20);
    expect(measurements.displacement, isNull);
    expect(measurements.lastSegment, isNull);
    expect(measurements.path, 0);

    measurements.ingest(
      {
        'locations': [
          _fix(.0003, -4),
          _fix(.0007, -4.5), // Arrived after a newer fix.
          _fix(.0007, -3),
        ],
      },
      _now,
      collecting: true,
    );
    expect(measurements.displacement, closeTo(77.84, .01));
    expect(measurements.lastSegment, closeTo(44.48, .01));
    expect(measurements.path, closeTo(77.84, .01));
    expect(measurements.lastMovementAt, _epoch - 3);
    expect(measurements.filteredLocations, hasLength(3));
    expect(measurements.rawLocations, hasLength(8));
    expect(
      measurements.accepted + measurements.rejected,
      measurements.received,
    );

    measurements.reset(_now);
    expect(measurements.latestLocation, isNull);
    expect(measurements.lastMovementAt, isNull);
    expect(measurements.accepted, 0);
    expect(measurements.drift, 0);
    expect(measurements.rawLocations, isEmpty);
  });

  test(
    'Relative heading wraps, recalibrates and follows interface changes',
    () {
      final measurements = SensorMeasurements();
      void add(double? yaw, {String frame = 'Landscape left'}) {
        measurements.ingest(
          {
            'orientations': [_motion(yaw, _epoch, frame)],
          },
          _now,
          collecting: true,
        );
      }

      add(170);
      expect(measurements.relativeYaw, 0);
      add(-170);
      expect(measurements.relativeYaw, 20);
      add(null);
      expect(measurements.relativeYaw, isNull);
      add(-171);
      expect(measurements.relativeYaw, 19);
      measurements.calibrate();
      expect(measurements.relativeYaw, isNull);
      add(-110);
      expect(measurements.relativeYaw, 0);
      add(-20);
      expect(measurements.relativeYaw, 90);
      add(160, frame: 'Landscape right');
      expect(measurements.relativeYaw, 0);
      expect(measurements.calibrationCount, 3);
    },
  );

  test('Retains bounded local report samples and whole-test counters', () {
    final measurements = SensorMeasurements()..reset(_now);
    const size = SensorMeasurements.maxSamples + 10;
    final batch = {
      'model': 'iPad-test',
      'os': '27.0.1',
      'authorization': 'Authorized',
      'precise': true,
      'locations': List.generate(size, (i) => _fix(0, -1 + i / size)),
      'orientations': List.generate(
        size,
        (i) => _motion(90, _epoch - (size - i) / 10),
      ),
    };
    measurements.ingest(batch, _now, collecting: false);
    expect(measurements.received, 0);
    measurements.ingest(batch, _now, collecting: true);
    final report = jsonDecode(measurements.report(_now)) as Map;
    expect(report['device'], 'iPad-test');
    expect(report['iPadOS'], '27.0.1');
    expect(report['started'], _now.toIso8601String());
    expect(report['ended'], _now.toIso8601String());
    expect(report['capabilities']['authorization'], 'Authorized');
    expect(
      report['rawLocationObservations'],
      hasLength(SensorMeasurements.maxSamples),
    );
    expect(report['filteredLocationObservations'], hasLength(1));
    expect(
      report['relativeOrientationSamples'],
      hasLength(SensorMeasurements.maxSamples),
    );
    expect(report['summary']['received'], size);
    expect(report['summary']['orientationUpdates'], size);
    expect(report['summary']['orientationHzRecent'], closeTo(10, .01));
    expect(report, isNot(contains('astronaut')));
  });

  testWidgets('Permission denial and missing capabilities stay usable', (
    tester,
  ) async {
    final service = _MockSensors({
      'authorization': 'Not determined',
      'services': false,
      'motion': false,
      'gyro': false,
    });
    await _open(tester, service);
    expect(service.commands, isEmpty);
    expect(find.text('Not determined'), findsOneWidget);
    await tester.tap(find.text('START TEST'));
    service.status['authorization'] = 'Denied';
    await _tick(tester);
    expect(service.commands, ['start']);
    expect(find.text('Denied'), findsOneWidget);
    expect(find.text('Unavailable / Unavailable'), findsWidgets);
    expect(find.text('Unavailable · No fresh readings'), findsOneWidget);
    expect(
      find.text('Absolute heading unavailable — relative orientation only'),
      findsOneWidget,
    );

    await tester.tap(find.text('STOP TEST'));
    await _tick(tester);
    expect(service.commands, ['start', 'stop']);
    expect(find.text('Stopped'), findsOneWidget);
    await tester.tap(find.text('EXPORT TEST REPORT'));
    await _tick(tester);
    expect(service.commands.last, 'export');
    expect(jsonDecode(service.exported!)['rawLocationObservations'], isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _tick(tester);
  });

  testWidgets(
    'Displays relative rotation, clears samples and stops in background',
    (tester) async {
      final service = _MockSensors({
        'authorization': 'Authorized',
        'precise': true,
        'services': true,
        'motion': true,
        'gyro': true,
      });
      await _open(tester, service);
      await tester.tap(find.text('START TEST'));
      await _tick(tester);
      final time = DateTime.now().millisecondsSinceEpoch / 1000;
      service.orientations.addAll([_motion(10, time - .1), _motion(100, time)]);
      await _tick(tester);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        .25,
      );
      expect(find.text('90°'), findsOneWidget);

      await tester.tap(find.text('CALIBRATE ORIENTATION'));
      await _tick(tester);
      expect(service.commands.last, 'clearMotion');
      service.orientations.add(_motion(80, time + .1));
      await _tick(tester);
      expect(find.text('0°'), findsOneWidget);

      await tester.tap(find.text('RESET MEASUREMENTS'));
      await _tick(tester);
      expect(service.commands.last, 'reset');
      expect(find.text('0°'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await _tick(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _tick(tester);
      expect(service.commands.last, 'stop');
      expect(find.text('Stopped'), findsOneWidget);

      await tester.tap(find.text('BACK TO DASHBOARD'));
      await tester.pumpAndSettle();
      await _tick(tester);
      expect(find.text('Mock dashboard'), findsOneWidget);
      expect(
        service.commands.where((command) => command == 'stop'),
        hasLength(2),
      );
    },
  );
}

/// Produces a synthetic location without using a real device.
Sample _fix(double latitude, double seconds, {double accuracy = 10}) => {
  'latitude': latitude,
  'longitude': 0,
  'time': _epoch + seconds,
  'accuracy': accuracy,
};

/// Produces a synthetic motion reading in the supplied interface reference.
Sample _motion(double? yaw, double time, [String frame = 'Landscape left']) => {
  'yaw': yaw,
  'time': time,
  'received': time,
  'frame': frame,
  'pitch': 0,
  'roll': 0,
  'rotationRate': 0,
};

/// Opens the tool from a minimal dashboard harness in landscape.
Future<void> _open(WidgetTester tester, SensorService service) async {
  await tester.binding.setSurfaceSize(const Size(1180, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SensorTestScreen(service: service),
            ),
          ),
          child: const Text('Mock dashboard'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mock dashboard'));
  await tester.pumpAndSettle();
  await _tick(tester);
}

/// Advances the foreground polling timer and delivers queued work.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Drains test samples once, matching the platform channel transport.
final class _MockSensors implements SensorService {
  _MockSensors(this.status);

  final Sample status;
  final commands = <String>[];
  final orientations = <Sample>[];
  String? exported;

  @override
  Future<void> command(String name, [String? argument]) async {
    commands.add(name);
    if (name == 'export') exported = argument;
  }

  @override
  Future<Sample> snapshot() async {
    final batch = orientations.toList();
    orientations.clear();
    return {...status, 'orientations': batch};
  }
}
