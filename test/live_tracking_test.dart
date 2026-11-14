import 'dart:async';

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

  test(
    'Uncertainty, outliers, stale and coarse fixes do not move the astronaut',
    () {
      final sensor = LiveMovement()..reset(100);
      expect(sensor.observe(_fix(0, 99), 100), isNull);
      expect(sensor.observe(_fix(0, 101), 120), isNull);
      expect(sensor.observe(_fix(0, 101, accuracy: 51), 102), isNull);
      expect(sensor.observe(_fix(0, 102), 102), isNull); // Baseline.
      expect(sensor.fresh(102), isTrue);
      expect(
        sensor.observe(_fix(.00005, 104), 104),
        isNull,
      ); // 5.6 m, accuracy sum 20 m.
      expect(sensor.observe(_fix(.1, 106), 106), isNull); // Implausible jump.
      expect(
        sensor.observe(_fix(.0003, 112), 112),
        isNull,
      ); // Await confirmation.
      expect(sensor.observe(_fix(.0003, 112), 113), isNull); // Duplicate.
      final step = sensor.observe(_fix(.00031, 114), 114);
      expect(step?.dx, closeTo(34.47, .02));
      expect(step?.dy, closeTo(0, .001));
      expect(sensor.fresh(135), isFalse);
      expect(
        sensor.observe(_fix(.02, 155), 155),
        isNull,
      ); // Rebaseline after interruption.
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
        sensors.locations.addAll([_fix(0, 101), _fix(.00004, 103)]);
        await _tick(tester);
        expect(tracking.quality, PositionQuality.uncertain);
        expect(nav.position, nav.map.base);
        sensors.locations.addAll([_fix(.00030, 108), _fix(.00031, 110)]);
        await _tick(tester);
        expect(tracking.quality, PositionQuality.accepted);
        expect(
          tracking.coordinates.distance(nav.map.base, nav.position),
          closeTo(34.47, .03),
        );
        final position = nav.position;

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
Sample _fix(double longitude, double time, {double accuracy = 10}) => {
  'latitude': 0,
  'longitude': longitude,
  'time': time,
  'accuracy': accuracy,
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

  @override
  Future<void> command(String name, [String? argument]) async =>
      commands.add(name);

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
