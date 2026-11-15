import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/mission_presence.dart';
import 'package:sidera_vi/tracking/pedometer_monitor.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';

void main() {
  test('Reports unsupported, denied, missing and stale readings honestly', () {
    final monitor = PedometerMonitor();
    addTearDown(monitor.dispose);
    void read(Map? data, double now) =>
        monitor.ingest(data, now, active: true, onSample: (_) {});
    read(null, 100);
    expect(monitor.state, PedometerState.unavailable);
    read({'stepCounting': false}, 100);
    expect(monitor.state, PedometerState.unsupported);
    read(_native(1, 100, authorization: 'denied'), 101);
    expect(monitor.state, PedometerState.denied);
    read(_native(1, 100), 102);
    expect(monitor.state, PedometerState.waiting);
    expect(monitor.latest, isNull);
    read(_native(1, 100, readings: [_sample(100, 103, 0)]), 103);
    expect(monitor.state, PedometerState.fresh);
    expect(monitor.latest?.steps, 0);
    expect(monitor.latest?.distance, isNull);
    expect(monitor.recentStepIncrease, isFalse);
    read(_native(1, 100), 112);
    expect(monitor.state, PedometerState.stale);
    expect(monitor.ageSeconds, 9);
    read({
      ..._native(1, 100),
      'error': {'domain': 'CoreMotion', 'code': 2},
    }, 113);
    expect(monitor.state, PedometerState.unavailable);
    expect(monitor.error, containsPair('code', 2));
  });

  test(
    'Deduplicates deferred counts, optional distances and cumulative resets',
    () {
      final monitor = PedometerMonitor()..beginCapture(101);
      addTearDown(monitor.dispose);
      final decisions = <PedometerObservation>[];
      void read(Map data, double now) =>
          monitor.ingest(data, now, active: true, onSample: decisions.add);

      read(_native(1, 100, readings: [_sample(100, 102, 4, distance: 2)]), 102);
      expect(
        monitor.captureSteps,
        isNull,
      ); // This window began before the capture.
      read(
        _native(
          2,
          102,
          readings: [
            _sample(102, 103, 0),
            _sample(102, 105, 6, distance: 3),
            _sample(102, 105, 6, distance: 3),
            _sample(102, 104, 4, distance: 2),
            _sample(102, 107, 10, distance: 5),
          ],
        ),
        107,
      );
      expect(monitor.captureSteps, 10);
      expect(monitor.captureDistance, 5);
      expect(monitor.recentStepIncrease, isTrue);
      expect(
        decisions.where((sample) => sample.decision == 'duplicateOrOutOfOrder'),
        hasLength(2),
      );

      read(
        _native(
          2,
          102,
          readings: [
            _sample(102, 109, 1, distance: .5),
            _sample(102, 112, 3, distance: 1.5),
          ],
        ),
        112,
      );
      expect(decisions[decisions.length - 2].decision, 'cumulativeReset');
      expect(monitor.captureSteps, 12);
      expect(monitor.captureDistance, 6);

      read(_native(3, 113, readings: [_sample(113, 117, 4, distance: 2)]), 117);
      expect(monitor.captureSteps, 16);
      expect(monitor.captureDistance, 8);
      monitor.endCapture();
      read(_native(3, 113, readings: [_sample(113, 119, 7, distance: 3)]), 119);
      expect(monitor.captureSteps, 16);
      expect(monitor.latest?.steps, 7);
    },
  );

  test(
    'Equal-end Core Motion corrections apply only their incremental evidence',
    () {
      final monitor = PedometerMonitor();
      addTearDown(monitor.dispose);
      final readings = <PedometerObservation>[];
      monitor.ingest(
        _native(
          2,
          101,
          readings: [
            _sample(101, 105, 14, distance: 9),
            _sample(101, 105, 24, distance: 16),
            _sample(101, 105, 24, distance: 16),
            _sample(101, 104, 30, distance: 20),
          ],
        ),
        108,
        active: true,
        onSample: readings.add,
      );
      expect(readings.map((sample) => sample.incrementalSteps), [14, 10, 0, 0]);
      expect(readings[1].incrementalDistance, 7);
      expect(monitor.latest?.steps, 24);
    },
  );

  testWidgets(
    'Capture, resume and rebaseline collect steps without changing the pose',
    (tester) async {
      final mission = marsMissions.first;
      final nav = DemoNavigation(missionMaps[mission.id]!, startAtBase: true);
      final sensors = _Sensors();
      var now = 100.0;
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: MissionCoordinates(mission),
        sensors: sensors,
        clock: () => DateTime.fromMillisecondsSinceEpoch((now * 1000).round()),
      );
      Future<void> read(double time, Map payload) async {
        now = time;
        sensors.payload = payload;
        await tester.pump(const Duration(milliseconds: 110));
        await tester.pump();
      }

      try {
        await tracking.resume();
        expect(sensors.commands, ['startMotion']);
        await tracking.selectMode(TrackingMode.live);
        expect(sensors.commands.last, 'startLocation');
        tracking.startCapture(mission.id);
        await read(
          108,
          _native(1, 101, readings: [_sample(101, 108, 9, distance: 5)]),
        );
        expect(sensors.commands, contains('restartPedometer'));
        expect(tracking.pedometer.captureSteps, 9);
        expect(nav.atBase, isTrue);

        tracking.rebaseline();
        tracking.noteConnection(ConnectionStatus.reconnecting);
        tracking.noteConnection(ConnectionStatus.connected);
        await read(
          110,
          _native(1, 101, readings: [_sample(101, 108, 9, distance: 5)]),
        );
        expect(tracking.pedometer.captureSteps, 9);
        expect(
          sensors.commands.where((c) => c == 'restartPedometer'),
          hasLength(1),
        );

        await tracking.suspend();
        expect(sensors.commands.last, 'stop');
        await tracking.resume();
        expect(sensors.commands.last, 'startLocation');
        await read(
          114,
          _native(2, 111, readings: [_sample(111, 114, 3, distance: 2)]),
        );
        expect(tracking.pedometer.captureSteps, 12);
        await tracking.calibrate();
        expect(nav.atBase, isTrue);
        await tracking.selectMode(TrackingMode.demo);
        expect(sensors.commands.last, 'stopLocation');
        await read(
          116,
          _native(2, 111, readings: [_sample(111, 116, 6, distance: 3)]),
        );
        expect(tracking.pedometer.state, PedometerState.idle);
        expect(tracking.pedometer.captureSteps, 12);

        await tracking.exportCapture();
        final report = jsonDecode(sensors.report!) as Map;
        final events = (report['events'] as List).cast<Map>();
        final steps = events.where((e) => e['event'] == 'pedometerSample');
        expect(steps.last['appliedMarsMeters'], 0);
        expect(steps.first, containsPair('estimatedDistanceMeters', 5.0));
        expect(
          events.where((e) => e['event'] == 'headingCalibrated'),
          hasLength(1),
        );
        expect(events.where((e) => e['event'] == 'positionChanged'), isEmpty);
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );
  testWidgets(
    'A failed live stream queries only the opted-in capture and preserves the pose',
    (tester) async {
      final mission = marsMissions.first;
      final nav = DemoNavigation(missionMaps[mission.id]!, startAtBase: true);
      final sensors = _Sensors();
      var now = 100;
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: MissionCoordinates(mission),
        sensors: sensors,
        clock: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
      );
      try {
        await tracking.resume();
        await tracking.selectMode(TrackingMode.live);
        tracking.startCapture(mission.id);
        now = 150;
        sensors.payload = {
          ..._native(2, 101),
          'error': {'domain': 'CMErrorDomain', 'code': 109},
        };
        await tester.pump(const Duration(milliseconds: 110));
        await tester.pump();
        expect(tracking.pedometer.state, PedometerState.unavailable);
        sensors.query = {'outcome': 'measured', 'steps': 29, 'distance': 16.5};
        now = 160;
        final stopping = tracking.stopCapture();
        expect(identical(tracking.stopCapture(), stopping), isTrue);
        await stopping;
        expect(
          sensors.commands.where((name) => name == 'finishPedometerCapture'),
          hasLength(1),
        );
        expect(jsonDecode(sensors.queryArgument!), {
          'start': 100.0,
          'end': 160.0,
        });
        expect(tracking.pedometer.captureSteps, 29);
        expect(tracking.pedometer.captureDistance, 16.5);
        expect(tracking.pedometer.state, PedometerState.unavailable);
        expect(nav.atBase, isTrue);
        await tracking.exportCapture();
        final report = jsonDecode(sensors.report!) as Map;
        final events = (report['events'] as List).cast<Map>();
        expect(
          events
              .where((event) => event['event'] == 'pedometerCaptureQuery')
              .single,
          containsPair('appliedMarsMeters', 0),
        );
        expect(
          events.where((event) => event['event'] == 'positionChanged'),
          isEmpty,
        );
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );
}

Map<String, Object?> _native(
  int stream,
  double started, {
  String authorization = 'authorized',
  List<Map> readings = const [],
}) => {
  'stream': stream,
  'started': started,
  'stepCounting': true,
  'distance': true,
  'cadence': true,
  'authorization': authorization,
  'samples': readings,
};

Map<String, Object?> _sample(
  double start,
  double end,
  int steps, {
  double? distance,
}) => {
  'start': start,
  'end': end,
  'received': end,
  'steps': steps,
  if (distance != null) 'distance': distance,
};

final class _Sensors implements SensorService {
  final commands = <String>[];
  Map? payload;
  String? report;
  Map? query;
  String? queryArgument;

  @override
  Future<void> command(String name, [String? argument]) async {
    commands.add(name);
    if (name == 'exportMovement') report = argument;
    if (name == 'finishPedometerCapture') {
      queryArgument = argument;
      payload = {...?payload, 'captureQuery': query};
    }
  }

  @override
  Future<Map<String, Object?>> snapshot() async => {'pedometer': payload};
}
