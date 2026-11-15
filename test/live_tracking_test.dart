import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/maps/mars_projection.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/sensors/sensor_measurements.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/firebase_presence.dart';
import 'package:sidera_vi/tracking/live_movement.dart';
import 'package:sidera_vi/tracking/mission_presence.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';
import 'package:sidera_vi/ui/dashboard/demo_terrain_map.dart';

/// Exercises movement and sharing without real coordinates or an external account.
void main() {
  test(
    'Earth east/north meters and Mars angular conversion wrap longitude',
    () {
      final east = earthDisplacement(
        const Offset(179.9999, 0),
        const Offset(-179.9999, 0),
      );
      expect(east.dx, closeTo(22.239, .001));
      expect(east.dy, closeTo(0, .0001));
      final north = earthDisplacement(
        const Offset(20, 0),
        const Offset(20, .001),
      );
      expect(north.dx, closeTo(0, .0001));
      expect(north.dy, closeTo(111.195, .001));

      const start = Offset(179.9999, 20);
      final mars = displaceOnMars(start, east);
      expect(mars.dx, lessThan(0));
      expect(
        surfaceDistance(start, mars, MarsProjection.radiusMeters),
        closeTo(east.distance, .001),
      );
      final movedNorth = displaceOnMars(start, north);
      expect(movedNorth.dx, closeTo(start.dx, .000001));
      expect(movedNorth.dy, greaterThan(start.dy));
    },
  );

  test(
    'Each mission base projects to the same georeferenced pixel as its marker',
    () {
      const viewport = Size(612, 420);
      const side = 420.0;
      for (final mission in marsMissions) {
        final nav = DemoNavigation(missionMaps[mission.id]!, startAtBase: true);
        addTearDown(nav.dispose);
        final coordinates = MissionCoordinates(mission);
        final base = coordinates.toMars(nav.position);
        final scene = MarsScene(
          viewport: viewport,
          latitude: coordinates.center.dy,
          longitude: coordinates.center.dx,
          shortSideDegrees: coordinates.span,
        );
        final overlay =
            viewport.center(Offset.zero) +
            (nav.map.base - const Offset(.5, .5)) * side;
        final projected = scene.toPixel(base);
        expect((overlay - projected).distance, lessThan(.001));
        expect(nav.position, nav.map.base);
        expect(
          (coordinates.toGrid(base) - nav.map.base).distance,
          lessThan(.000001),
        );
      }
    },
  );

  test('Stationary drift and short walks inside uncertainty hold position', () {
    final sensor = LiveMovement()..reset(100);
    expect(
      sensor.observe(_meters(0, 99), 100).reason,
      MovementReason.oldWindow,
    );
    expect(sensor.observe(_meters(0, 101), 120).reason, MovementReason.stale);
    expect(
      sensor.observe(_meters(0, 101, accuracy: 51), 102).reason,
      MovementReason.coarse,
    );
    expect(
      sensor.observe(_meters(0, 102), 102).reason,
      MovementReason.baseline,
    );
    for (final (time, drift) in [
      (107.0, 5.0),
      (111.0, -3.0),
      (117.0, 6.0),
      (126.0, 10.0),
    ]) {
      final decision = sensor.observe(
        _meters(drift, time, walking: true),
        time,
      );
      expect(decision.reason, MovementReason.uncertain);
      expect(decision.step, isNull);
    }
    expect(sensor.fresh(126), isTrue);
    expect(sensor.fresh(142), isFalse);
    expect(
      sensor.observe(_meters(250, 160), 160).reason,
      MovementReason.gapBaseline,
    );
    expect(sensor.requiresRebaseline, isFalse);
  });

  test('Replayed 202 m cluster holds until the operator rebaselines', () {
    final sensor = LiveMovement()..reset(100);
    for (final time in [100.0, 110.0, 120.0, 130.0, 140.0]) {
      expect(sensor.observe(_meters(0, time, accuracy: 30), time).step, isNull);
    }
    final first = sensor.observe(_meters(202, 150, accuracy: 30), 150);
    expect(first.reason, MovementReason.jump);
    expect(first.distance, closeTo(202, .01));
    expect(first.uncertainty, 60);
    expect(first.step, isNull);
    expect(
      sensor.observe(_meters(202, 152, accuracy: 30), 152).reason,
      MovementReason.held,
    );
    expect(sensor.requiresRebaseline, isTrue);
    sensor.reset(170); // Mode toggle or app foreground restart.
    expect(sensor.observe(_meters(202, 171), 171).reason, MovementReason.held);
    sensor.rebaseline(172);
    expect(
      sensor.observe(_meters(202, 171), 172).reason,
      MovementReason.oldWindow,
    );
    expect(
      sensor.observe(_meters(203, 173), 173).reason,
      MovementReason.baseline,
    );
    expect(sensor.requiresRebaseline, isFalse);
  });

  test(
    'A large, optimistic jump cannot pass on speed, course, or another fix',
    () {
      final sensor = LiveMovement()..reset(100);
      sensor.observe(_meters(0, 100, accuracy: 1), 100);
      final decision = sensor.observe(
        _meters(65, 120, accuracy: 1, walking: true),
        120,
      );
      expect(decision.reason, MovementReason.jump);
      expect(decision.step, isNull);
      expect(
        sensor
            .observe(_meters(68, 123, accuracy: 1, walking: true), 123)
            .reason,
        MovementReason.held,
      );
    },
  );

  test('An optimistic correlated cluster lacks progressive evidence', () {
    final sensor = LiveMovement()..reset(100);
    sensor.observe(_meters(0, 100, accuracy: 3), 100);
    expect(
      sensor.observe(_meters(26, 110, accuracy: 3), 110).reason,
      MovementReason.uncorroborated,
    );
    expect(
      sensor
          .observe(_meters(26, 111, accuracy: 3, walking: true, batch: 9), 111)
          .reason,
      MovementReason.pending,
    );
    expect(
      sensor
          .observe(_meters(29, 112, accuracy: 3, walking: true, batch: 9), 112)
          .reason,
      MovementReason.sameCallback,
    );
    for (final time in [114.0, 116.0, 118.0]) {
      final decision = sensor.observe(
        _meters(26, time, accuracy: 3, walking: true),
        time,
      );
      expect(decision.reason, MovementReason.noProgress);
      expect(decision.step, isNull);
    }
    expect(
      sensor.observe({
        ..._meters(35, 119, accuracy: 3, walking: true),
        'simulatedBySoftware': true,
      }, 119).reason,
      MovementReason.simulated,
    );
  });

  test(
    'Consistent fixes beyond uncertainty apply only the supported portion once',
    () {
      final sensor = LiveMovement()..reset(100);
      sensor.observe(_meters(0, 100, accuracy: 4), 100);
      for (final (time, distance) in [(110.0, 12.0), (114.0, 19.0)]) {
        expect(
          sensor
              .observe(
                _meters(distance, time, walking: true, accuracy: 4),
                time,
              )
              .reason,
          MovementReason.pending,
        );
      }
      final last = _meters(26, 118, walking: true, accuracy: 4);
      final result = sensor.observe(last, 118);
      expect(result.reason, MovementReason.accepted);
      expect(result.step?.dx, closeTo(18, .01));
      expect(result.step?.dy, closeTo(0, .001));
      expect(result.distance, closeTo(26, .01));
      expect(result.uncertainty, 8);
      expect(sensor.observe(last, 119).reason, MovementReason.repeated);
      expect(
        sensor.observe(_meters(26, 120, walking: true, accuracy: 4), 120).step,
        isNull,
      );
    },
  );

  testWidgets(
    'Live and demo sources switch without moving position or requesting early permission',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(100000);
      final sensors = _Sensors();
      final mission = marsMissionById['jezero']!;
      final nav = DemoNavigation(missionMaps[mission.id]!, startAtBase: true);
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: MissionCoordinates(mission),
        sensors: sensors,
        clock: () => now,
      );
      try {
        await tracking.resume();
        expect(sensors.commands, ['startMotion']);
        expect(tracking.mode, TrackingMode.demo);
        expect(nav.position, nav.map.base);
        nav.select(nav.map.landmarks.first.position, 'Waypoint');
        nav.start();
        expect(nav.moving, isTrue);

        await tracking.selectMode(TrackingMode.live);
        expect(sensors.commands.last, 'startLocation');
        expect(nav.moving, isFalse);
        expect(nav.guiding, isFalse);
        expect(nav.canNavigate, isTrue);
        nav.start(instant: true);
        expect(nav.guiding, isTrue);
        expect(nav.moving, isFalse);
        expect(nav.position, nav.map.base);
        expect(nav.canNavigate, isFalse);
        sensors.stepWindow = 100;
        sensors.steps.add(_steps(100, 101, 5));
        now = DateTime.fromMillisecondsSinceEpoch(101000);
        sensors.motion.add(_attitude(101, 179));
        sensors.locations.addAll([_meters(0, 100), _meters(22, 101)]);
        await _tick(tester);
        expect(tracking.measuredSteps, 5);
        expect(nav.position, nav.map.base);
        expect(tracking.quality, PositionQuality.waiting);
        expect(await tracking.calibrateWalkingDirection(nav.target!), isTrue);
        expect(sensors.commands.last, 'restartPedometer');
        sensors.stream++;
        sensors.stepWindow = 101.1;
        now = DateTime.fromMillisecondsSinceEpoch(102000);
        sensors.motion.add(_attitude(102, 179));
        sensors.steps.add(_steps(101.1, 102, 10));
        await _tick(tester);
        final position = nav.position;
        expect(tracking.distanceTraveled, closeTo(7, .001));
        expect(tracking.measuredSteps, 15);
        expect(
          nav.positionSource,
          NavigationPositionSource.pedestrianDeadReckoning,
        );
        expect(nav.guiding, isTrue);

        now = DateTime.fromMillisecondsSinceEpoch(103000);
        sensors.motion.add(_attitude(103, -179));
        sensors.steps.addAll([_steps(101.1, 102, 10), _steps(101.1, 103, 10)]);
        sensors.locations.add(_meters(200, 103, walking: true));
        await _tick(tester);
        expect(tracking.walkingBearing, isNotNull);
        expect(nav.position, position);
        expect(tracking.measuredSteps, 15);

        await tracking.selectMode(TrackingMode.demo);
        expect(sensors.commands.last, 'stopLocation');
        expect(nav.position, position);
        expect(nav.canNavigate, isTrue);
        await tracking.suspend();
        await tracking.resume();
        expect(sensors.commands.sublist(sensors.commands.length - 2), [
          'stop',
          'startMotion',
        ]);
        expect(nav.position, position);
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );

  testWidgets(
    'Live navigation uses current measured distance in both directions and returns only beyond 100 m',
    (tester) async {
      final nav = DemoNavigation(missionMaps['jezero']!, startAtBase: true)
        ..enableDemoMovement(false);
      addTearDown(nav.dispose);
      Offset east(double meters) => nav.map.coordinates.toGrid(
        displaceOnMars(
          nav.map.coordinates.toMars(nav.map.base),
          Offset(meters, 0),
        ),
      );
      void advanceTo(double meters) => nav.applyStepPosition(east(meters));

      final arbitrary = east(175.3);
      expect(nav.select(arbitrary, 'Map waypoint'), isTrue);
      expect(nav.target, arbitrary);
      expect(nav.select(east(501), 'Outside mission'), isFalse);
      expect(nav.target, arbitrary);
      expect(nav.remainingMeters, closeTo(175.3, .001));
      expect(nav.canReturnToBase, isFalse);
      nav.returnToBase(instant: true);
      expect(nav.target, arbitrary);
      nav.start(instant: true);
      expect(
        nav.state(positionCertain: false),
        NavigationState.positionUncertain,
      );
      nav.advance(const Duration(minutes: 1));
      expect(nav.position, nav.map.base);
      expect(nav.canNavigate, isFalse);

      advanceTo(100);
      expect(nav.remainingMeters, closeTo(75.3, .001));
      expect(nav.canReturnToBase, isFalse);
      advanceTo(101);
      expect(nav.canReturnToBase, isTrue);
      advanceTo(105);
      final nearer = nav.remainingMeters!;
      advanceTo(102);
      expect(nav.remainingMeters, greaterThan(nearer));
      final beforeReturn = nav.position;
      nav.returnToBase(instant: true);
      nav.advance(const Duration(minutes: 1));
      expect(nav.position, beforeReturn);
      expect(nav.state(), NavigationState.navigatingToBase);
      expect(nav.remainingMeters, closeTo(102, .001));
      expect(nav.canReturnToBase, isFalse);

      advanceTo(113);
      expect(nav.remainingMeters, closeTo(113, .001));
      advanceTo(7);
      final withinBase = nav.position;
      expect(nav.state(), NavigationState.arrivedAtBase);
      expect(nav.position, withinBase);
      expect(nav.routeTarget, isNull);
      expect(nav.liveArrivalCount, 1);
      advanceTo(6);
      expect(nav.liveArrivalCount, 1);
    },
  );

  testWidgets(
    'Calibrated step batches publish the Mars pose and arrive without snapping',
    (tester) async {
      final nav = DemoNavigation(missionMaps['jezero']!, startAtBase: true);
      final sensors = _Sensors();
      var now = DateTime.fromMillisecondsSinceEpoch(100000);
      final coordinates = nav.map.coordinates;
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: coordinates,
        sensors: sensors,
        clock: () => now,
      );
      final connection = _Connection();
      final presence = MissionPresence(
        key: (
          mission: 'jezero',
          session: 'field-test-01',
          astronaut: 'ARES-01',
        ),
        pose: () => tracking.pose,
        restore: tracking.restore,
        clock: () => now,
      );
      nav.addListener(presence.pulse);
      Future<void> read(
        double time,
        double yaw, {
        int? steps,
        double? distance,
      }) async {
        now = DateTime.fromMillisecondsSinceEpoch((time * 1000).round());
        sensors.motion.add(_attitude(time, yaw));
        if (steps != null) {
          sensors.steps.add(
            _steps(sensors.stepWindow, time, steps, distance: distance),
          );
        }
        await _tick(tester);
      }

      try {
        await tracking.resume();
        await tracking.selectMode(TrackingMode.live);
        presence.open((_) async => connection);
        await tester.pump();
        connection.data.add({
          'ARES-01': (pose: _pose(), updated: now, online: true),
        });
        await tester.pump();
        expect(nav.position, nav.map.base);
        final target = coordinates.toGrid(
          displaceOnMars(coordinates.toMars(nav.map.base), const Offset(25, 0)),
        );
        nav.select(target, 'Map waypoint');
        nav.start(instant: true);
        sensors.locationAuthorization = 'Denied';
        sensors.stepWindow = 101.1;
        await read(101, 0);
        expect(nav.remainingMeters, closeTo(25, .001));
        expect(await tracking.calibrateWalkingDirection(target), isTrue);
        await read(102, 0, steps: 10);
        expect(nav.remainingMeters, closeTo(18, .01));
        expect(tracking.distanceTraveled, closeTo(7, .01));
        await read(103, 180, steps: 15);
        expect(nav.remainingMeters, closeTo(21.5, .01));
        expect(tracking.distanceTraveled, closeTo(10.5, .01));
        await read(104, 0, steps: 20, distance: 15);
        expect(nav.remainingMeters, closeTo(18, .01));
        await read(105, 0, steps: 30, distance: 26);
        expect(nav.remainingMeters, closeTo(7, .01));
        expect(tracking.distanceTraveled, closeTo(25, .01));
        final measuredPosition = nav.position;
        expect(connection.writes.last.pose.mars, tracking.pose.mars);
        expect(connection.writes.last.pose.quality, PositionQuality.accepted);
        expect(connection.writes.last.pose.mode, TrackingMode.live);
        expect(
          connection.writes.last.pose.mars,
          isNot(coordinates.toMars(target)),
        );
        expect(nav.state(), NavigationState.arrivedAtDestination);
        expect(nav.target, target);
        expect(nav.routeTarget, isNull);
        expect(nav.guiding, isFalse);
        expect(nav.liveArrivalCount, 1);
        await read(106, 0, steps: 30, distance: 26);
        expect(nav.position, measuredPosition);
        expect(nav.liveArrivalCount, 1);
      } finally {
        nav.removeListener(presence.pulse);
        presence.dispose();
        tracking.dispose();
        nav.dispose();
      }
    },
  );

  testWidgets(
    'Pause, resume, frame changes and motion gaps require fresh calibration',
    (tester) async {
      final nav = DemoNavigation(missionMaps['jezero']!, startAtBase: true);
      final sensors = _Sensors();
      var now = DateTime.fromMillisecondsSinceEpoch(100000);
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: nav.map.coordinates,
        sensors: sensors,
        clock: () => now,
      );
      Future<void> read(
        double time,
        int steps, {
        String frame = 'portrait',
        double? yaw = 0,
      }) async {
        now = DateTime.fromMillisecondsSinceEpoch((time * 1000).round());
        sensors.motion.add(_attitude(time, yaw, frame));
        sensors.steps.add(_steps(sensors.stepWindow, time, steps));
        await _tick(tester);
      }

      try {
        await tracking.resume();
        await tracking.selectMode(TrackingMode.live);
        final coordinates = nav.map.coordinates;
        final target = coordinates.toGrid(
          displaceOnMars(coordinates.toMars(nav.position), const Offset(25, 0)),
        );
        nav.select(target, 'Waypoint');
        nav.start();
        await read(101, 0);
        expect(await tracking.calibrateWalkingDirection(target), isTrue);
        sensors.stream++;
        sensors.stepWindow = 101.1;
        await read(102, 5);
        expect(nav.remainingMeters, closeTo(21.5, .01));
        final measured = nav.position;
        nav.togglePause();
        await read(103, 10);
        expect(nav.state(), NavigationState.paused);
        expect(nav.position, measured);
        nav.togglePause();
        await read(104, 15);
        expect(nav.position, measured);
        expect(await tracking.calibrateWalkingDirection(target), isTrue);
        await tracking.suspend();
        await tracking.resume();
        sensors.stream++;
        sensors.stepWindow = 104.1;
        await read(105, 5);
        expect(nav.position, measured);
        expect(await tracking.calibrateWalkingDirection(target), isTrue);
        sensors.stream++;
        sensors.stepWindow = 105.1;
        await read(106, 3, frame: 'landscape');
        expect(nav.position, measured);
        expect(await tracking.calibrateWalkingDirection(target), isTrue);
        sensors.stream++;
        sensors.stepWindow = 106.1;
        await read(107, 4, frame: 'landscape', yaw: null);
        expect(nav.position, measured);
        await read(111, 5, frame: 'landscape');
        expect(nav.position, measured);
        expect(nav.guiding, isTrue);
        expect(nav.liveArrivalCount, 0);
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );

  testWidgets(
    'Restoration, optional GPS diagnostics, and reconnect preserve provenance',
    (tester) async {
      final nav = DemoNavigation(missionMaps['jezero']!, startAtBase: true);
      final sensors = _Sensors();
      var now = DateTime.fromMillisecondsSinceEpoch(100000);
      final coordinates = MissionCoordinates(marsMissionById['jezero']!);
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: coordinates,
        sensors: sensors,
        clock: () => now,
      );
      try {
        await tracking.resume();
        tracking.startCapture('jezero');
        final restored = coordinates.toMars(nav.map.landmarks.first.position);
        tracking.noteConnection(ConnectionStatus.connected);
        tracking.restore((
          mars: restored,
          heading: null,
          mode: TrackingMode.demo,
          quality: PositionQuality.simulated,
        ));
        final trusted = nav.position;
        expect(
          (coordinates.toMars(trusted) - restored).distance,
          lessThan(.000001),
        );
        expect(nav.positionSource, NavigationPositionSource.firebaseRestore);

        await tracking.selectMode(TrackingMode.live);
        now = DateTime.fromMillisecondsSinceEpoch(107000);
        sensors.locations.addAll([_meters(0, 101), _meters(202, 106)]);
        await _tick(tester);
        expect(tracking.quality, PositionQuality.waiting);
        expect(nav.position, trusted);

        tracking.noteConnection(ConnectionStatus.reconnecting);
        tracking.noteConnection(ConnectionStatus.connected);
        tracking.restore(_pose());
        expect(nav.position, trusted);
        await tracking.suspend();
        await tracking.resume();
        expect(nav.position, trusted);
        tracking.rebaseline();
        now = DateTime.fromMillisecondsSinceEpoch(110000);
        sensors.locations.add(_meters(205, 109));
        await _tick(tester);
        expect(nav.position, trusted);

        await tracking.exportCapture();
        final report = jsonDecode(sensors.exported!) as Map;
        final events = (report['events'] as List).cast<Map>();
        expect(report['schema'], 'sidera-movement-v1');
        expect(tracking.telemetry.recording, isFalse);
        expect(
          events
              .where((item) => item['event'] == 'positionChanged')
              .single['source'],
          'firebaseRestore',
        );
        final fix = events.where((item) => item['decision'] == 'jump').single;
        expect(fix['observedMeters'], closeTo(202, .01));
        expect(fix['appliedMarsMeters'], 0);
        expect(fix['earthFix'], containsPair('callbackBatch', 106));
        expect(fix['baseline'], containsPair('time', 101));
        expect(
          events.where((item) => item['outcome'] == 'alreadyReviewed'),
          hasLength(1),
        );
        expect(
          events.where((item) => item['reason'] == 'operatorRebaseline'),
          hasLength(1),
        );
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );

  testWidgets(
    'Calibration wraps, handles the landscape frame, and expires missing attitude',
    (tester) async {
      final sensors = _Sensors();
      final mission = marsMissionById['jezero']!;
      final nav = DemoNavigation(missionMaps[mission.id]!);
      var time = 100000;
      final tracking = AstronautTracking(
        navigation: nav,
        coordinates: MissionCoordinates(mission),
        sensors: sensors,
        clock: () => DateTime.fromMillisecondsSinceEpoch(time),
      );
      try {
        await tracking.resume();
        Future<void> sample(
          double? yaw, [
          String side = 'right',
          int ms = 100,
        ]) async {
          time += ms;
          sensors.motion.add({'time': time / 1000, 'yaw': yaw, 'frame': side});
          await _tick(tester);
        }

        await sample(179);
        expect(tracking.heading.value, 0);
        await sample(-179);
        expect(tracking.heading.value, 2);
        await sample(-170, 'left');
        expect(tracking.heading.value, 0);
        await sample(-80, 'left');
        expect(tracking.heading.value, 90);
        await tracking.calibrate();
        expect(sensors.commands.last, 'clearMotion');
        await sample(-80, 'left');
        expect(tracking.heading.value, 0);
        await sample(null, 'left', 3000);
        expect(tracking.heading.value, isNull);
      } finally {
        tracking.dispose();
        nav.dispose();
      }
    },
  );

  testWidgets('The arrow animates through the short arc at +/-180 degrees', (
    tester,
  ) async {
    Widget arrow(double degrees) => MaterialApp(
      home: RelativeMarkerArrow(
        heading: degrees,
        child: const Icon(Icons.navigation),
      ),
    );
    await tester.pumpWidget(arrow(179));
    await tester.pumpWidget(arrow(-179));
    final rotation = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(rotation.turns, closeTo(181 / 360, .0001));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Presence scopes missions, throttles heading and reconnects once',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1);
      AstronautPose pose = _pose();
      final connection = _Connection();
      final next = _Connection();
      final scopes = <SessionKey>[];
      final restored = <AstronautPose>[];
      final presence = MissionPresence(
        key: (mission: 'jezero', session: 'field-a', astronaut: 'ARES-01'),
        pose: () => pose,
        restore: restored.add,
        clock: () => now,
      );
      Future<PresenceConnection> connect(SessionKey key) async {
        scopes.add(key);
        return scopes.length == 1 ? connection : next;
      }

      try {
        presence.open(connect);
        presence.open(connect);
        await tester.pump();
        expect(scopes, [
          (mission: 'jezero', session: 'field-a', astronaut: 'ARES-01'),
        ]);
        expect(presence.status, ConnectionStatus.reconnecting);
        final old = _pose(lon: 77.1);
        final peer = (pose: _pose(heading: 15), updated: now, online: true);
        connection.data.add({
          'ARES-01': (pose: old, updated: now, online: false),
          'ARES-02': peer,
        });
        await tester.pump();
        expect(restored, [old]);
        expect(presence.crew.keys, ['ARES-02']);
        expect(presence.isFresh(presence.crew['ARES-02']!), isTrue);
        expect(connection.writes.length, 1);

        pose = _pose(heading: 1);
        now = now.add(const Duration(milliseconds: 250));
        await _tick(tester, ms: 250);
        expect(connection.writes.length, 1);
        pose = _pose(heading: 30);
        presence.pulse();
        await tester.pump();
        expect(connection.writes.length, 2);

        now = now.add(const Duration(seconds: 19));
        await _tick(tester, ms: 250);
        expect(presence.isFresh(peer), isFalse);
        connection.data.addError(StateError('Disconnected'));
        await tester.pump();
        expect(presence.status, ConnectionStatus.reconnecting);
        expect(connection.closed, isTrue);
        await _tick(tester, ms: 1100);
        expect(scopes.length, 2);
        next.data.add({
          'ARES-02': (pose: _pose(heading: 80), updated: now, online: true),
        });
        await tester.pump();
        expect(presence.status, ConnectionStatus.connected);
        expect(presence.crew['ARES-02']?.pose.heading, 80);
        expect(restored, [old]);
        presence.suspend();
        await tester.pump();
        expect(presence.status, ConnectionStatus.offline);
        expect(next.writes.last.online, isFalse);
      } finally {
        presence.dispose();
        await tester.pump();
      }
    },
  );

  test(
    'Firebase stream applies incremental changes and drops malformed roster entries',
    () {
      final tree = <String, Object?>{};
      mergePresenceEvent(tree, {
        'path': '/',
        'data': {
          'ARES-02': {
            'marsLon': 77,
            'marsLat': 18,
            'mode': 'live',
            'quality': 'uncertain',
            'online': true,
            'updated': 123000,
            'relativeHeading': 15,
          },
          'unassigned': {'marsLon': 77},
        },
      }, patch: false);
      expect(decodePresence(tree).keys, ['ARES-02']);
      expect(decodePresence(tree)['ARES-02']?.pose.heading, 15);
      mergePresenceEvent(tree, {
        'path': '/ARES-02',
        'data': {'relativeHeading': -179, 'online': false},
      }, patch: true);
      expect(decodePresence(tree)['ARES-02']?.pose.heading, -179);
      expect(decodePresence(tree)['ARES-02']?.online, false);
      mergePresenceEvent(tree, {
        'path': '/ARES-02',
        'data': null,
      }, patch: false);
      expect(decodePresence(tree), isEmpty);
    },
  );
}

/// A synthetic Earth fix near the equator for predictable eastward movement.
Sample _meters(
  double meters,
  double time, {
  double accuracy = 10,
  bool walking = false,
  int? batch,
}) => {
  'latitude': 0.0,
  'longitude': meters / 111195,
  'time': time,
  'accuracy': accuracy,
  'callbackBatch': batch ?? time.round(),
  if (walking) ...{
    'speed': 1.4,
    'speedAccuracy': .3,
    'course': 90,
    'courseAccuracy': 10,
  },
};

/// Simulated session data only.
AstronautPose _pose({double lon = 77, double heading = 0}) => (
  mars: Offset(lon, 18),
  heading: heading,
  mode: TrackingMode.live,
  quality: PositionQuality.uncertain,
);

Sample _attitude(double time, double? yaw, [String frame = 'portrait']) => {
  'time': time,
  'yaw': yaw,
  'frame': frame,
};

Sample _steps(double start, double end, int total, {double? distance}) => {
  'start': start,
  'end': end,
  'steps': total,
  if (distance != null) 'distance': distance,
};

Future<void> _tick(WidgetTester tester, {int ms = 100}) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

final class _Sensors implements SensorService {
  final commands = <String>[];
  final locations = <Sample>[];
  final motion = <Sample>[];
  final steps = <Sample>[];
  int stream = 1;
  double stepWindow = 100;
  String locationAuthorization = 'Authorized';
  String? exported;

  @override
  Future<void> command(String name, [String? argument]) async {
    commands.add(name);
    if (name == 'exportMovement') exported = argument;
  }

  @override
  Future<Sample> snapshot() async {
    final batch = {
      'authorization': locationAuthorization,
      'services': true,
      'precise': true,
      'locations': locations.toList(growable: false),
      'orientations': motion.toList(growable: false),
      'pedometer': {
        'source': 'coreMotionPedometer',
        'stepCounting': true,
        'authorization': 'authorized',
        'stream': stream,
        'started': stepWindow,
        'samples': steps.toList(growable: false),
      },
    };
    locations.clear();
    motion.clear();
    steps.clear();
    return batch;
  }
}

final class _Connection implements PresenceConnection {
  final data = StreamController<PresenceSnapshot>();
  final writes = <({AstronautPose pose, bool online})>[];
  bool closed = false;

  @override
  Stream<PresenceSnapshot> get snapshots => data.stream;

  @override
  Future<void> publish(AstronautPose pose, {required bool online}) async =>
      writes.add((pose: pose, online: online));

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(data.close());
  }
}
