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
      final mission = marsMissions.first;
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
        expect(nav.canNavigate, isFalse);
        now = now.add(const Duration(seconds: 10));
        sensors.locations.addAll([_meters(0, 101), _meters(4, 103)]);
        await _tick(tester);
        expect(tracking.quality, PositionQuality.uncertain);
        expect(nav.position, nav.map.base);
        PositionQuality? publishedQuality;
        nav.addListener(() {
          if (nav.positionSource == NavigationPositionSource.coreLocation) {
            publishedQuality = tracking.quality;
          }
        });
        now = now.add(const Duration(seconds: 10));
        sensors.locations.addAll([
          _meters(23, 111, walking: true),
          _meters(28, 115, walking: true),
          _meters(34, 119, walking: true),
        ]);
        await _tick(tester);
        expect(tracking.quality, PositionQuality.accepted);
        expect(
          tracking.coordinates.distance(nav.map.base, nav.position),
          closeTo(14, .03),
        );
        expect(nav.positionSource, NavigationPositionSource.coreLocation);
        expect(publishedQuality, PositionQuality.accepted);
        final position = nav.position;
        sensors.locations.add(_meters(34, 119, walking: true));
        await _tick(tester);
        expect(nav.position, position);

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
    'Restoration, a position hold, and reconnect preserve provenance',
    (tester) async {
      final nav = DemoNavigation(missionMaps['jezero']!, startAtBase: true);
      final sensors = _Sensors();
      var now = DateTime.fromMillisecondsSinceEpoch(100000);
      final coordinates = MissionCoordinates(marsMissions.first);
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
        expect(tracking.requiresRebaseline, isTrue);
        expect(tracking.quality, PositionQuality.uncertain);
        expect(nav.position, trusted);

        tracking.noteConnection(ConnectionStatus.reconnecting);
        tracking.noteConnection(ConnectionStatus.connected);
        tracking.restore(_pose());
        expect(nav.position, trusted);
        await tracking.suspend();
        await tracking.resume();
        expect(tracking.requiresRebaseline, isTrue);
        expect(nav.position, trusted);
        tracking.rebaseline();
        now = DateTime.fromMillisecondsSinceEpoch(110000);
        sensors.locations.add(_meters(205, 109));
        await _tick(tester);
        expect(tracking.requiresRebaseline, isFalse);
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
      final mission = marsMissions.first;
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

Future<void> _tick(WidgetTester tester, {int ms = 100}) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

final class _Sensors implements SensorService {
  final commands = <String>[];
  final locations = <Sample>[];
  final motion = <Sample>[];
  String? exported;

  @override
  Future<void> command(String name, [String? argument]) async {
    commands.add(name);
    if (name == 'exportMovement') exported = argument;
  }

  @override
  Future<Sample> snapshot() async {
    final batch = {
      'authorization': 'Authorized',
      'services': true,
      'precise': true,
      'locations': locations.toList(growable: false),
      'orientations': motion.toList(growable: false),
    };
    locations.clear();
    motion.clear();
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
