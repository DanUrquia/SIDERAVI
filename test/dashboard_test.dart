import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/astronaut.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/dashboard/terrain_view_controller.dart';
import 'package:sidera_vi/missions/mission.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/maps/mars_projection.dart';
import 'package:sidera_vi/maps/mars_trek_layers.dart';

import 'package:sidera_vi/tracking/mission_presence.dart';
import 'package:sidera_vi/tracking/crew_signals.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/ui/dashboard/demo_terrain_map.dart';
import 'package:sidera_vi/ui/dashboard/dashboard_style.dart';
import 'package:sidera_vi/ui/dashboard/dashboard_panels.dart';
import 'package:sidera_vi/ui/dashboard/mission_dashboard.dart';
import 'package:sidera_vi/ui/dashboard/mobile_navigation.dart';
import 'package:sidera_vi/ui/mission_theme.dart';

import 'fake_trek_tiles.dart';

/// Exercises the mission dashboard and its landscape tablet and phone layouts.
void main() {
  test('All five missions have a unique, internally consistent demo map', () {
    expect(
      missionMaps.keys.toSet(),
      marsMissions.map((mission) => mission.id).toSet(),
    );
    expect(
      missionMaps.values.map((scenario) => scenario.asset).toSet(),
      hasLength(5),
    );
    expect(
      missionMaps.values.map((scenario) => scenario.start).toSet(),
      hasLength(5),
    );
    for (final config in missionMaps.values) {
      expect(config.contains(config.start), isTrue);
      expect(config.contains(config.teammate), isTrue);
      expect(config.landmarks, hasLength(3));
      for (final landmark in config.landmarks) {
        expect(config.contains(landmark.position), isTrue);
      }
    }
  });

  test(
    'Scientific catalog and spherical map agree at all five Habitat Bases',
    () {
      final ids = <String>{};
      const expected = {
        'jezero': (500, -2652),
        'gale': (650, -2606),
        'endeavour': (750, -1783),
        'columbia-hills': (850, -1934),
        'valles-marineris': (1000, -3874),
      };
      for (final mission in marsMissions) {
        final (radius, height) = expected[mission.id]!;
        expect(mission.objectives, hasLength(3));
        for (final objective in mission.objectives) {
          expect(objective.id, matches(r'^[a-z]+(?:-[a-z]+)*$'));
          expect(ids.add(objective.id), isTrue);
        }
        final map = missionMaps[mission.id]!;
        expect(map.radiusMeters, radius);
        expect(map.radiusMeters, mission.radiusMeters);
        expect(mission.elevation?.meters, height);
        expect(mission.elevationLabel, '−${height.abs()} m');
        final center = map.coordinates.toMars(map.base);
        expect(
          mission.elevation!.location.latitude,
          closeTo(center.dy, .0000001),
        );
        expect(
          MarsProjection.signedLongitude(
            mission.elevation!.location.eastLongitude,
          ),
          closeTo(center.dx, .0000001),
        );
        for (final point in map.boundary) {
          expect(
            map.coordinates.distance(map.base, point),
            closeTo(radius, .0001),
          );
          expect(map.contains(point), isTrue);
        }
        for (final offset in [
          Offset(radius + 1.0, 0),
          Offset(0, -radius - 1.0),
        ]) {
          expect(
            map.contains(
              map.coordinates.toGrid(displaceOnMars(center, offset)),
            ),
            isFalse,
          );
        }
      }
    },
  );

  test('The local grid measures distance and heading consistently', () {
    final config = missionMaps['jezero']!;
    final nav = DemoNavigation(config);
    addTearDown(nav.dispose);
    expect(nav.select(Offset.zero, 'Outside'), isFalse);
    expect(nav.target, isNull);
    Offset fromStart(Offset meters) => config.coordinates.toGrid(
      displaceOnMars(config.coordinates.toMars(config.start), meters),
    );
    final north = fromStart(const Offset(0, 120));
    expect(nav.select(north, 'North test'), isTrue);
    expect(nav.distanceTo(north), closeTo(120, .001));
    expect(nav.heading, closeTo(0, .001));
    final east = fromStart(const Offset(140, 0));
    expect(nav.select(east, 'East test'), isTrue);
    expect(nav.heading, closeTo(90, .01));
    nav.start(instant: true);
    expect(nav.arrived, isTrue);
    expect(nav.position, east);
  });

  testWidgets('Zoom, pan and reset keep map taps aligned to the demo grid', (
    tester,
  ) async {
    final map = await _launch(tester);
    final viewport = find.byKey(const ValueKey('demo-map-viewport'));
    await _tapTooltip(tester, 'Zoom in');
    expect(map.view.value.getMaxScaleOnAxis(), closeTo(1.4, .001));
    final rect = tester.getRect(viewport);
    await tester.dragFrom(
      rect.center + const Offset(-10, -80),
      const Offset(-130, -20),
    );
    await tester.pumpAndSettle();
    final side = rect.shortestSide;
    final world = Rect.fromCenter(
      center: Offset(rect.width / 2, rect.height / 2),
      width: side,
      height: side,
    );
    await _tapTooltip(tester, 'Zoom out');
    expect(map.view.value.getMaxScaleOnAxis(), closeTo(1, .001));
    await tester.tap(find.text('Fit area · 500 m radius'));
    await tester.pumpAndSettle();
    final config = map.navigation.map;
    final valid = config.coordinates.toGrid(
      displaceOnMars(
        config.coordinates.toMars(config.base),
        const Offset(-290, -270),
      ),
    );
    final scene = world.topLeft + valid * side;
    await tester.tapAt(
      rect.topLeft + MatrixUtils.transformPoint(map.view.value, scene),
    );
    await tester.pumpAndSettle();
    expect(map.navigation.target?.dx, closeTo(valid.dx, .01));
    expect(map.navigation.target?.dy, closeTo(valid.dy, .01));
    await tester.tap(find.text('View region · 500 m radius'));
    await tester.pumpAndSettle();
    expect(map.view.value.isIdentity(), isTrue);

    final first = await tester.startGesture(
      rect.center - const Offset(65, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      rect.center + const Offset(65, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-85, 0));
    await second.moveBy(const Offset(85, 0));
    await first.moveBy(const Offset(-65, 0));
    await second.moveBy(const Offset(65, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(map.view.value.getMaxScaleOnAxis(), greaterThan(1));
    await _tapTooltip(tester, 'Reset view');
    expect(map.view.value.isIdentity(), isTrue);
  });

  testWidgets(
    'Astronaut glyphs, labels and teammate targets stay fixed across zoom',
    (tester) async {
      final mission = marsMissionById['jezero']!;
      final navigation = DemoNavigation(
        missionMaps[mission.id]!,
        startAtBase: true,
      );
      final view = TerrainViewController();
      final tracking = AstronautTracking(
        navigation: navigation,
        coordinates: MissionCoordinates(mission),
        sensors: const NativeSensorService(),
      );
      addTearDown(navigation.dispose);
      addTearDown(view.dispose);
      addTearDown(tracking.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final peer = navigation.map.teammate;
      final teammate = (
        pose: (
          mars: tracking.coordinates.toMars(peer),
          heading: 25.0,
          mode: TrackingMode.live,
          quality: PositionQuality.uncertain,
        ),
        updated: DateTime.utc(2026),
        online: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MissionTheme.dark,
          home: DemoTerrainMap(
            navigation: navigation,
            view: view,
            mission: mission,
            tileSource: FakeTrekTiles(),
            tracking: tracking,
            astronautId: 'ARES-01',
            teammateId: 'ARES-02',
            peer: teammate,
            peerPoint: peer,
            peerFresh: true,
            teammateName: 'Adrian Flores',
            onSelect: (point, label) => navigation.select(point, label),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final local = find.descendant(
        of: find.byKey(const ValueKey('ARES-01')),
        matching: find.byType(RelativeMarkerArrow),
      );
      final remote = find.descendant(
        of: find.byKey(const ValueKey('ARES-02')),
        matching: find.byType(RelativeMarkerArrow),
      );
      final label = find.text('ARES-01 · YOU');
      final sizes = [
        tester.getSize(local),
        tester.getSize(remote),
        tester.getSize(label),
      ];
      final viewport = tester.getRect(
        find.byKey(const ValueKey('demo-map-viewport')),
      );
      final world = Rect.fromCenter(
        center: viewport.size.center(Offset.zero),
        width: viewport.shortestSide,
        height: viewport.shortestSide,
      );
      final focal = world.topLeft + navigation.position * world.width;

      final areaScale = .52 / navigation.map.boundaryBounds.longestSide;
      for (final factor in [
        1.0,
        1.4,
        2.7,
        TerrainViewController.maxZoom,
        1.0,
      ]) {
        final zoom = areaScale * factor;
        final offset = focal * (1 - zoom) + const Offset(-18, 16);
        view.value = Matrix4.identity()
          ..setEntry(0, 0, zoom)
          ..setEntry(1, 1, zoom)
          ..setTranslationRaw(offset.dx, offset.dy, 0);
        await tester.pumpAndSettle();
        for (final (finder, original) in [
          (local, sizes[0]),
          (remote, sizes[1]),
          (label, sizes[2]),
        ]) {
          final rect = tester.getRect(finder);
          expect(rect.width, closeTo(original.width, .001));
          expect(rect.height, closeTo(original.height, .001));
        }
        final anchor =
            viewport.topLeft + MatrixUtils.transformPoint(view.value, focal);
        expect((tester.getCenter(local) - anchor).distance, lessThan(.01));
        final peerAnchor =
            viewport.topLeft +
            MatrixUtils.transformPoint(
              view.value,
              world.topLeft + peer * world.width,
            );
        expect((tester.getCenter(remote) - peerAnchor).distance, lessThan(.01));
        final hit = tester.getRect(
          find.byTooltip('Select Adrian Flores on map'),
        );
        expect(hit.width, closeTo(48, .001));
        expect(hit.height, closeTo(48, .001));
        expect(
          tester
              .widget<AnimatedRotation>(
                find.descendant(
                  of: remote,
                  matching: find.byType(AnimatedRotation),
                ),
              )
              .turns,
          closeTo(25 / 360, .001),
        );
      }
      tracking.heading.value = 80;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: local,
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        closeTo(80 / 360, .001),
      );
      await tester.tap(find.byTooltip('Select Adrian Flores on map'));
      await tester.pumpAndSettle();
      expect(navigation.target, peer);
    },
  );

  testWidgets('A remote astronaut at Habitat base keeps a separate label', (
    tester,
  ) async {
    final mission = marsMissionById['jezero']!;
    final navigation = DemoNavigation(missionMaps[mission.id]!);
    final coordinates = MissionCoordinates(mission);
    final view = TerrainViewController();
    final tracking = AstronautTracking(
      navigation: navigation,
      coordinates: coordinates,
      sensors: const NativeSensorService(),
    );
    addTearDown(navigation.dispose);
    addTearDown(view.dispose);
    addTearDown(tracking.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: MissionTheme.dark,
        home: DemoTerrainMap(
          navigation: navigation,
          view: view,
          mission: mission,
          tileSource: FakeTrekTiles(),
          tracking: tracking,
          astronautId: 'ARES-01',
          teammateId: 'ARES-02',
          teammateName: 'Adrian Flores',
          peerPoint: navigation.map.base,
          peer: (
            pose: (
              mars: coordinates.toMars(navigation.map.base),
              heading: 0.0,
              mode: TrackingMode.demo,
              quality: PositionQuality.simulated,
            ),
            updated: DateTime.utc(2026),
            online: true,
          ),
          peerFresh: true,
          onSelect: (point, label) => navigation.select(point, label),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final zoom in [1.0, 2.0, 4.0]) {
      view.reset();
      view.zoomBy(zoom, const Size(390, 844));
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.text('Habitat base'))
            .overlaps(tester.getRect(find.text('ARES-02'))),
        isFalse,
      );
    }
    view.reset();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select Adrian Flores on map'));
    expect(navigation.target, navigation.map.base);
  });

  testWidgets('Sensor Test returns to the existing Mars scenario', (
    tester,
  ) async {
    const channel = MethodChannel('sidera_vi/sensor_diagnostics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'snapshot' ? <String, Object?>{} : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final map = await _launch(tester);
    await _tapTooltip(tester, 'Select Adrian Flores on map');
    final position = map.navigation.position;
    final target = map.navigation.target;
    await tester.tap(find.text('SENSOR TEST'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Earth location'), findsOneWidget);
    await tester.tap(find.text('BACK TO DASHBOARD'));
    await tester.pumpAndSettle();

    final current = tester.widget<DemoTerrainMap>(find.byType(DemoTerrainMap));
    expect(current.navigation, same(map.navigation));
    expect(current.navigation.position, position);
    expect(current.navigation.target, target);
  });

  testWidgets('Movement Log captures a dashboard session and exports locally', (
    tester,
  ) async {
    const channel = MethodChannel('sidera_vi/sensor_diagnostics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? report;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'exportMovement') report = call.arguments as String;
      if (call.method == 'snapshot') {
        return <String, Object?>{'stepCounting': false};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final map = await _launch(tester);
    expect(map.tracking.telemetry.recording, isFalse);
    await tester.tap(find.text('MOVEMENT LOG'));
    await tester.pumpAndSettle();
    expect(find.text('Live Movement Diagnostics'), findsOneWidget);
    expect(find.textContaining('Step counting · Unavailable'), findsOneWidget);
    expect(find.text('ENABLE LIVE SENSORS'), findsOneWidget);
    await tester.tap(find.text('START CAPTURE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(map.tracking.telemetry.recording, isTrue);
    await tester.tap(find.text('MOVEMENT LOG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ENABLE LIVE SENSORS'));
    await tester.pumpAndSettle();
    expect(map.tracking.mode, TrackingMode.live);
    await tester.tap(find.text('REBASELINE'));
    await tester.pumpAndSettle();
    expect(map.navigation.position, map.navigation.map.base);
    await tester.tap(find.text('EXPORT JSON'));
    await tester.pumpAndSettle();
    expect(report, contains('"event": "modeChanged"'));
    expect(report, contains('"reason": "operatorRebaseline"'));
    expect(map.tracking.telemetry.recording, isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Follow recenters the marker, preserves zoom and releases on pan',
    (tester) async {
      final map = await _launch(tester);
      final marker = find.descendant(
        of: find.byKey(const ValueKey('ARES-01')),
        matching: find.byType(RelativeMarkerArrow),
      );
      final viewport = find.byKey(const ValueKey('demo-map-viewport'));
      final rect = tester.getRect(viewport);
      while (map.view.value.getMaxScaleOnAxis() <
          TerrainViewController.maxZoom) {
        await _tapTooltip(tester, 'Zoom in');
      }
      final zoom = map.view.value.getMaxScaleOnAxis();
      final before = tester.getCenter(marker);
      expect((before - rect.center).distance, greaterThan(5));

      await tester.tap(find.text('FOLLOW ASTRONAUT'));
      await tester.pumpAndSettle();
      expect(map.view.value.getMaxScaleOnAxis(), zoom);
      expect((tester.getCenter(marker) - rect.center).distance, lessThan(1));

      map.navigation.setTrackedPosition(
        map.navigation.map.base + const Offset(.05, -.04),
      );
      await tester.pumpAndSettle();
      expect((tester.getCenter(marker) - rect.center).distance, lessThan(1));
      await tester.dragFrom(
        rect.center + const Offset(20, -70),
        const Offset(-50, -25),
      );
      await tester.pumpAndSettle();
      expect(map.tracking.follow, isFalse);
      expect((tester.getCenter(marker) - rect.center).distance, greaterThan(5));
      await _tapTooltip(tester, 'Reset view');
      expect(map.view.value.isIdentity(), isTrue);
    },
  );

  testWidgets('Selects a teammate and pauses, resumes, then returns to base', (
    tester,
  ) async {
    final map = await _launch(tester);
    final nav = map.navigation;
    await _tapTooltip(tester, 'Select Adrian Flores on map');
    expect(nav.target, nav.map.teammate);
    expect(nav.targetLabel, 'Adrian Flores');
    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(nav.position, isNot(nav.map.start));
    expect(nav.moving, isTrue);

    await tester.tap(find.text('PAUSE EXPLORATION'));
    final paused = nav.position;
    await tester.pump(const Duration(seconds: 1));
    expect(nav.position, paused);
    await tester.tap(find.text('RESUME EXPLORATION'));
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.teammate);
    expect(nav.arrived, isTrue);

    await tester.tap(find.text('RETURN TO BASE'));
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.base);
    expect(nav.targetLabel, 'Habitat base');
  });

  testWidgets('Places all three local ping markers and announces danger', (
    tester,
  ) async {
    final map = await _launch(tester);
    for (final type in DemoPingType.values) {
      await tester.tap(find.text('SEND PING'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(type.label));
      await tester.pumpAndSettle();
      expect(map.navigation.pings.last.type, type);
      expect(map.navigation.pings.last.position, map.navigation.position);
      expect(
        find.byKey(ValueKey((type, map.navigation.position))),
        findsOneWidget,
      );
      if (type == DemoPingType.danger) {
        expect(
          find.text('Warning marker placed on this device.'),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('Confirms and cancels demo SOS without leaving the dashboard', (
    tester,
  ) async {
    final map = await _launch(tester);
    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    expect(map.navigation.sos, isFalse);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(map.navigation.sos, isFalse);
    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACTIVATE DEMO SOS'));
    await tester.pumpAndSettle();
    expect(find.text('DEMO SOS ACTIVE'), findsOneWidget);
    expect(map.navigation.sos, isTrue);
    expect(map.navigation.paused, isTrue);
    await tester.tap(find.text('CANCEL DEMO SOS'));
    await tester.pumpAndSettle();
    expect(find.text('DEMO SOS ACTIVE'), findsNothing);
    expect(find.byType(MissionDashboard), findsOneWidget);
    expect(map.navigation.sos, isFalse);
    expect(map.navigation.paused, isTrue);
  });

  testWidgets('Crew list can be reached and tapped with larger iPad text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final map = await _launch(tester, size: const Size(1024, 768));
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('dashboard-information')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Adrian Flores'),
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Adrian Flores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adrian Flores'));
    await tester.pumpAndSettle();
    expect(map.navigation.targetLabel, 'Adrian Flores');
  });
  testWidgets(
    'Phone applies native-format step batches without a destination',
    (tester) async {
      final motion = _PhoneMotion();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        sensorDiagnosticsChannel,
        motion.handle,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );
      final map = await _launch(
        tester,
        size: const Size(390, 844),
        clock: () => motion.now,
      );
      final tracking = map.tracking;
      final nav = map.navigation;
      final base = nav.map.base;
      final home = tracking.coordinates.toMars(base);
      expect(nav.target, isNull);
      expect(nav.guiding, isFalse);
      expect(nav.position, base);
      expect(tracking.mode, TrackingMode.live);
      expect(tracking.telemetry.recording, isFalse);
      expect(
        motion.calls.map((call) => call.method),
        containsAllInOrder([
          'readMissionPosition',
          'startMotion',
          'startLocation',
        ]),
      );
      expect(
        motion.calls
            .singleWhere((call) => call.method == 'startLocation')
            .arguments,
        'stepsOnly',
      );
      expect(find.text('DEMO MOVEMENT'), findsNothing);
      expect(find.text('LIVE SENSORS'), findsNothing);

      final oldStart = motion.started;
      await motion.poll(tester, 1.2, steps: 5);
      expect(nav.position, base);
      expect(tracking.appliedSteps, 0);

      // The snapshot contains a cumulative batch that crosses the first
      // direction reference. It is consumed without replay from the new window.
      await motion.poll(tester, 2.4, yaw: 42, steps: 8);
      expect(motion.starts, hasLength(2));
      expect(motion.started, greaterThan(oldStart));
      expect(nav.position, base);
      expect(tracking.appliedSteps, 0);
      expect(tracking.walkingBearing, closeTo(0, .001));
      await motion.poll(tester, 2.5, yaw: 42);
      expect(find.text('Exploration active'), findsOneWidget);

      for (var offset = 3; offset <= 12; offset++) {
        await motion.poll(tester, offset.toDouble(), yaw: 42);
      }
      // An unavailable attitude at the end of the batch cannot erase a recent
      // direction. The pedometer delivers the batch several seconds afterward.
      await motion.poll(tester, 12.6);
      await motion.poll(tester, 13.2, yaw: 42);
      await motion.poll(tester, 14.0, yaw: 42);
      await motion.poll(
        tester,
        15.2,
        yaw: 42,
        steps: 24,
        measuredThrough: 12.6,
      );
      expect(nav.target, isNull);
      expect(nav.guiding, isFalse);
      expect(tracking.measuredSteps, 24);
      expect(tracking.appliedSteps, 24);
      expect(tracking.distanceTraveled, closeTo(16.8, .01));
      expect(
        nav.positionSource,
        NavigationPositionSource.pedestrianDeadReckoning,
      );
      expect(tracking.pose.mars.dx, closeTo(home.dx, .000001));
      expect(tracking.pose.mars.dy, greaterThan(home.dy));
      expect(
        motion.calls
            .lastWhere((call) => call.method == 'writeMissionPosition')
            .arguments,
        {
          'scope': 'jezero/ARES-01',
          'mars': [tracking.pose.mars.dx, tracking.pose.mars.dy],
        },
      );
      final walked = nav.position;

      await motion.poll(
        tester,
        15.4,
        yaw: 132,
        steps: 24,
        measuredThrough: 12.6,
      );
      expect(nav.position, walked);
      expect(tracking.appliedSteps, 24);
      expect(tracking.walkingBearing, closeTo(90, .001));

      for (final sheet in ['missions', 'astronaut', 'crew']) {
        await _mobileTab(tester, sheet);
        expect(find.text('DEMO MOVEMENT'), findsNothing);
        expect(find.text('LIVE SENSORS · STEP NAVIGATION'), findsNothing);
        await _mobileTab(tester, sheet);
      }
      expect(motion.starts, hasLength(2));
      expect(motion.calls.where((call) => call.method == 'stop'), isEmpty);
      final east = tracking.coordinates.toGrid(
        displaceOnMars(tracking.pose.mars, const Offset(40, 0)),
      );
      expect(nav.select(east, 'Survey waypoint'), isTrue);
      await tester.pumpAndSettle();
      await motion.poll(tester, 16, yaw: 132, steps: 29);
      expect(nav.guiding, isFalse);
      expect(nav.remainingMeters, closeTo(36.5, .01));
      final atGuidanceStart = nav.position;
      await _tapTooltip(tester, 'Start Navigation');
      expect(nav.position, atGuidanceStart);
      expect(nav.guiding, isTrue);
      expect(motion.starts, hasLength(2));

      final session = await _connectPhoneCrew(tester, map);
      await motion.poll(tester, 17, yaw: 132, steps: 34);
      expect(nav.remainingMeters, closeTo(33, .01));
      expect(tracking.appliedSteps, 34);
      expect(session.writes.last.mars, tracking.pose.mars);
      expect(session.writes.last.quality, PositionQuality.accepted);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Phone restores its pose and stride across fresh step windows', (
    tester,
  ) async {
    final config = missionMaps['jezero']!;
    final saved = displaceOnMars(
      config.coordinates.toMars(config.base),
      const Offset(30, 0),
    );
    final motion = _PhoneMotion(savedPosition: saved, savedStride: .82);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    final map = await _launch(
      tester,
      size: const Size(390, 844),
      clock: () => motion.now,
    );
    expect(map.tracking.pose.mars.dx, closeTo(saved.dx, .0000001));
    expect(map.tracking.pose.mars.dy, closeTo(saved.dy, .0000001));
    expect(map.tracking.stride, .82);
    expect(
      motion.calls
          .singleWhere((call) => call.method == 'readStrideLength')
          .arguments,
      'ARES-01',
    );
    await motion.poll(tester, 1, yaw: 65);
    await motion.poll(tester, 2, yaw: 65, steps: 10);
    expect(map.tracking.appliedSteps, 10);
    final before = map.navigation.position;
    final previousWindow = motion.started;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(motion.calls.last.method, 'stop');
    await motion.poll(tester, 10, yaw: 42);
    expect(map.navigation.position, before);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(motion.started, greaterThan(previousWindow));
    await motion.poll(tester, 11, steps: 40, streamStart: previousWindow);
    expect(map.navigation.position, before);
    await motion.poll(tester, 12, yaw: 42);
    await motion.poll(tester, 13, yaw: 42, steps: 5);
    expect(map.tracking.appliedSteps, 15);
    expect(map.tracking.distanceTraveled, closeTo(12.3, .01));
    expect(
      motion.calls
          .lastWhere((call) => call.method == 'writeMissionPosition')
          .arguments,
      {
        'scope': 'jezero/ARES-01',
        'mars': [map.tracking.pose.mars.dx, map.tracking.pose.mars.dy],
      },
    );
    expect(map.navigation.target, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final astronaut in DemoCrew.roster) {
    testWidgets('${astronaut.id} opens at base and writes only its own steps', (
      tester,
    ) async {
      final motion = _PhoneMotion();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        sensorDiagnosticsChannel,
        motion.handle,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );

      final map = await _launch(
        tester,
        size: const Size(390, 844),
        astronaut: astronaut,
        clock: () => motion.now,
      );
      final nav = map.navigation;
      final tracking = map.tracking;
      final base = tracking.coordinates.toMars(nav.map.base);
      final stale = displaceOnMars(base, const Offset(20, 30));
      final session = await _connectPhoneCrew(
        tester,
        map,
        peerMars: base,
        oldOwnMars: stale,
      );
      final currentMap = tester.widget<DemoTerrainMap>(
        find.byType(DemoTerrainMap),
      );
      expect(currentMap.peerPoint, nav.map.base);
      expect(tracking.pose.mars, base);
      expect(session.key.astronaut, astronaut.id);
      expect(session.writes.single.mars, base);

      await motion.poll(tester, 1, yaw: 42);
      await motion.poll(tester, 2, yaw: 42, steps: 11);
      expect(tracking.appliedSteps, 11);
      expect(
        nav.positionSource,
        NavigationPositionSource.pedestrianDeadReckoning,
      );
      expect(nav.baseDistanceMeters, closeTo(7.7, .01));
      expect(session.writes.last.mars, tracking.pose.mars);
      expect(
        tester
            .widget<DemoTerrainMap>(find.byType(DemoTerrainMap))
            .peer!
            .pose
            .mars,
        base,
      );
      expect(motion.positions.keys, ['jezero/${astronaut.id}']);
      expect(await tracking.startNewExpedition(), isTrue);
      await tester.pumpAndSettle();
      expect(tracking.pose.mars, base);
      expect(motion.positions['jezero/${astronaut.id}'], base);
      expect(session.writes.last.mars, base);
    });
  }

  testWidgets('An iPhone can resume a saved walk or explicitly reset to base', (
    tester,
  ) async {
    final config = missionMaps['jezero']!;
    final base = config.coordinates.toMars(config.base);
    final saved = displaceOnMars(base, const Offset(45, 0));
    final motion = _PhoneMotion(savedPosition: saved);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );

    final map = await _launch(
      tester,
      size: const Size(390, 844),
      platform: TargetPlatform.iOS,
      clock: () => motion.now,
    );
    final session = await _connectPhoneCrew(
      tester,
      map,
      peerMars: base,
      oldOwnMars: displaceOnMars(base, const Offset(80, 0)),
    );
    final nav = map.navigation;
    final tracking = map.tracking;
    expect(tracking.pose.mars, saved);
    expect(session.writes.last.mars, saved);
    await motion.poll(tester, 1, yaw: 42);
    await motion.poll(tester, 2, yaw: 42, steps: 10);
    nav.select(config.landmarks.first.position, 'Survey waypoint');
    nav.togglePause();
    await tester.pumpAndSettle();
    final walked = tracking.pose.mars;
    final beforeReset = motion.started;
    expect(tracking.appliedSteps, 10);

    await _mobileTab(tester, 'astronaut');
    final start = find.text('START NEW EXPEDITION');
    await _tapPhoneAction(tester, start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue expedition'));
    await tester.pumpAndSettle();
    expect(tracking.pose.mars, walked);

    motion.failPositionWrite = true;
    await _tapPhoneAction(tester, start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start at Habitat Base'));
    await tester.pumpAndSettle();
    expect(tracking.pose.mars, walked);
    expect(nav.paused, isTrue);
    expect(session.writes.last.mars, walked);
    expect(
      find.text('Could not save a new expedition. Your position was kept.'),
      findsOneWidget,
    );

    motion.failPositionWrite = false;
    await _tapPhoneAction(tester, start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start at Habitat Base'));
    await tester.pumpAndSettle();
    expect(nav.position, config.base);
    expect(nav.target, isNull);
    expect(nav.paused, isFalse);
    expect(tracking.pose.mars, base);
    expect(tracking.appliedSteps, 0);
    expect(tracking.distanceTraveled, 0);
    expect(session.writes.last.mars, base);
    expect(motion.positions['jezero/ARES-01'], base);

    expect(motion.started, greaterThan(beforeReset));
    await motion.poll(
      tester,
      3,
      yaw: 42,
      steps: 50,
      measuredThrough: 1.9,
      streamStart: beforeReset,
    );
    expect(tracking.pose.mars, base);
    expect(tracking.appliedSteps, 0);
    await motion.poll(tester, 4, yaw: 42, steps: 6);
    expect(tracking.appliedSteps, 6);
    expect(nav.baseDistanceMeters, closeTo(4.2, .01));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reopened = await _launch(tester, size: const Size(390, 844));
    expect(reopened.navigation.baseDistanceMeters, closeTo(4.2, .01));
  });

  testWidgets(
    'Overlapping crew keeps separate chips and zero Mars separation',
    (tester) async {
      final map = await _launch(tester, size: const Size(390, 844));
      final base = map.tracking.pose.mars;
      final session = await _connectPhoneCrew(tester, map, peerMars: base);
      final self = find.byTooltip('ARES-01 · YOU');
      final peer = find.byTooltip('Select Adrian Flores on map');
      final anchor = map.navigation.position;
      final viewport = find.byKey(const ValueKey('demo-map-viewport'));
      final lowScale = map.view.value.getMaxScaleOnAxis();

      void expectCluster() {
        final current = tester.widget<DemoTerrainMap>(
          find.byType(DemoTerrainMap),
        );
        expect(current.peerPoint, anchor);
        expect(current.navigation.position, anchor);
        expect(current.peer!.pose.mars, base);
        final a = tester.getRect(self);
        final b = tester.getRect(peer);
        expect(a.width, closeTo(48, .001));
        expect(b.width, closeTo(48, .001));
        expect(b.center.dx - a.center.dx, closeTo(48, .001));
        expect(b.center.dy, closeTo(a.center.dy, .001));
        expect(
          find.byKey(const ValueKey('marker-collision-tether')),
          findsNothing,
        );
        expect(
          tester
              .getRect(find.text('ARES-01 · YOU'))
              .overlaps(tester.getRect(find.text('ARES-02'))),
          isFalse,
        );
      }

      expectCluster();
      map.view.zoomBy(3, tester.getSize(viewport));
      await tester.pumpAndSettle();
      expect(map.view.value.getMaxScaleOnAxis(), greaterThan(lowScale));
      expectCluster();
      await tester.tap(self);
      await tester.pumpAndSettle();
      expect(find.text('Position status'), findsOneWidget);
      await _tapTooltip(tester, 'Close Astronaut');
      await tester.tap(peer);
      await tester.pumpAndSettle();
      expect(map.navigation.target, anchor);
      expect(map.navigation.targetLabel, 'Adrian Flores');
      final header = find.byKey(const ValueKey('mobile-header-destination'));
      expect(_within(header, 'Adrian Flores'), findsOneWidget);
      expect(_within(header, ' · 0 m'), findsOneWidget);
      expect(find.text('Destination'), findsNothing);
      expectCluster();

      await _mobileTab(tester, 'crew');
      final readout = find.ancestor(
        of: find.text('Estimated separation'),
        matching: find.byType(DashboardReadout),
      );
      expect(tester.widget<DashboardReadout>(readout).value, '0 m');
      expect(find.text('Same position'), findsOneWidget);
      expect(session.writes.last.mars, base);

      for (final (meters, display) in [
        (.4, '0 m'),
        (7.2, '7 m'),
        (19.7, '20 m'),
        (1240.0, '1.24 km'),
      ]) {
        final other = displaceOnMars(base, Offset(meters, 0));
        session.update({map.teammateId: other});
        await tester.pumpAndSettle();
        expect(tester.widget<DashboardReadout>(readout).value, display);
        final current = tester.widget<DemoTerrainMap>(
          find.byType(DemoTerrainMap),
        );
        expect(current.peer!.pose.mars, other);
        expect(current.navigation.position, anchor);
        expect(session.writes.last.mars, base);
      }
      await _tapTooltip(tester, 'Close Crew');
      expect(find.text('Destination'), findsOneWidget);
    },
  );

  testWidgets('Every phone mission opens its own Crew session automatically', (
    tester,
  ) async {
    final motion = _PhoneMotion();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    final visits = <SessionKey>[];
    final connections = <_PhonePresence>[];
    for (final mission in marsMissions) {
      final session = _PhonePresence(DateTime.now);
      connections.add(session);
      final map = await _launch(
        tester,
        size: const Size(390, 844),
        mission: mission,
        connectPresence: (key) async {
          visits.add(key);
          return session;
        },
      );
      expect(visits.last, (
        mission: mission.id,
        session: 'field-test-01',
        astronaut: DemoCrew.dan.id,
      ));
      expect(find.byType(AlertDialog), findsNothing);
      if (mission.id != 'gale') {
        session.update({DemoCrew.adrian.id: map.tracking.pose.mars});
      } else {
        // The previous Endeavour subscription has ended and must not leak here.
        session.update({});
      }
      await tester.pumpAndSettle();
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(
        find.byTooltip('Select Adrian Flores on map'),
        mission.id == 'gale' ? findsNothing : findsOneWidget,
      );
      expect(
        session.writes.single.mars,
        map.tracking.coordinates.toMars(map.navigation.map.base),
      );

      await _mobileTab(tester, 'crew');
      expect(find.text('JOIN CREW'), findsNothing);
      expect(find.text('Crew email'), findsNothing);
      expect(find.text('Crew password'), findsNothing);
      expect(find.text('Steps'), findsNothing);
      if (mission.id == 'gale') {
        final card = find.ancestor(
          of: find.text('ARES-02 · OFFLINE'),
          matching: find.byType(DashboardPanel),
        );
        expect(
          tester
              .widgetList<Text>(
                find.descendant(of: card, matching: find.byType(Text)),
              )
              .map((text) => text.data),
          ['ARES-02 · OFFLINE', 'Adrian Flores'],
        );
      } else {
        expect(find.text('ARES-02 · ONLINE'), findsOneWidget);
        expect(find.text('Estimated separation'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(session.closed, isTrue);
      expect(session.offlineWrites.single.mars, map.tracking.pose.mars);
    }
    expect(visits.map((key) => key.mission), marsMissions.map((m) => m.id));
    expect(connections, hasLength(5));
  });

  testWidgets('Automatic Crew retries enrollment and network loss', (
    tester,
  ) async {
    final motion = _PhoneMotion();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    var attempts = 0;
    final sessions = <_PhonePresence>[];
    final map = await _launch(
      tester,
      size: const Size(390, 844),
      connectPresence: (_) async {
        if (attempts++ == 0) throw const PresenceEnrollmentPending();
        final result = _PhonePresence(DateTime.now);
        sessions.add(result);
        return result;
      },
    );
    await _mobileTab(tester, 'crew');
    expect(find.text('Crew device setup pending.'), findsOneWidget);
    expect(find.text('ARES-02 · OFFLINE'), findsOneWidget);
    final home = map.tracking.pose.mars;
    final walked = displaceOnMars(home, const Offset(12, 0));
    map.navigation.applyStepPosition(map.tracking.coordinates.toGrid(walked));
    await tester.pump(const Duration(seconds: 1));
    sessions.single.update({DemoCrew.adrian.id: home});
    await tester.pumpAndSettle();
    expect(find.text('Crew device setup pending.'), findsNothing);
    expect(find.text('ARES-02 · ONLINE'), findsOneWidget);
    expect(sessions.single.writes.last.mars, map.tracking.pose.mars);

    sessions.single.crew.addError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.text('ARES-02 · OFFLINE'), findsOneWidget);
    expect(find.text('Estimated separation'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    sessions.last.update({DemoCrew.adrian.id: home});
    await tester.pumpAndSettle();
    expect(find.text('ARES-02 · ONLINE'), findsOneWidget);
    expect(find.text('ARES-02 · OFFLINE'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sessions, hasLength(2));
    expect(sessions.last.writes.single.mars, map.tracking.pose.mars);
    expect(map.navigation.baseDistanceMeters, closeTo(12, .001));
  });

  testWidgets('Landscape tablet retains its separate simulation controls', (
    tester,
  ) async {
    final motion = _PhoneMotion();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    final map = await _launch(tester, size: const Size(1024, 768));
    expect(map.tracking.mode, TrackingMode.demo);
    expect(find.text('DEMO MOVEMENT'), findsOneWidget);
    expect(find.text('LIVE SENSORS'), findsOneWidget);
    expect(motion.starts, isEmpty);
    await tester.tap(find.text('LIVE SENSORS'));
    await tester.pumpAndSettle();
    expect(map.tracking.mode, TrackingMode.live);
    expect(motion.starts, hasLength(1));
    expect(
      motion.calls
          .singleWhere((call) => call.method == 'startLocation')
          .arguments,
      isNull,
    );
  });

  testWidgets('Phone sheets share one full-bleed map and preserve its camera', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      sensorDiagnosticsChannel,
      (call) async => call.method == 'readMissionChecklist' ? <String>[] : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    tester.view.viewPadding = const FakeViewPadding(top: 57, bottom: 32);
    addTearDown(tester.view.resetViewPadding);
    const size = Size(390, 844);
    final map = await _launch(tester, size: size);
    await _connectPhoneCrew(tester, map);
    final mapWidget = find.byType(DemoTerrainMap);
    final mapState = tester.state(mapWidget);
    final viewport = find.byKey(const ValueKey('demo-map-viewport'));
    final surface = find.byKey(const ValueKey('mobile-mission-sheet'));
    expect(tester.getRect(viewport), Offset.zero & size);
    expect(find.text('N'), findsNothing);
    expect(surface, findsNothing);
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('mobile-tab-crew'))).dy,
      lessThan(size.height - 32),
    );

    final center = tester.getCenter(viewport);
    final local = find.descendant(
      of: find.byKey(const ValueKey('ARES-01')),
      matching: find.byType(RelativeMarkerArrow),
    );
    final markerSize = tester.getSize(local);
    final first = await tester.startGesture(center - const Offset(32, 0));
    final second = await tester.startGesture(center + const Offset(32, 0));
    await first.moveBy(const Offset(-35, 0));
    await second.moveBy(const Offset(35, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(map.view.value.getMaxScaleOnAxis(), greaterThan(1.1));
    expect(tester.getRect(local).size.width, closeTo(markerSize.width, .001));
    final pinched = Matrix4.copy(map.view.value);

    await _mobileTab(tester, 'missions');
    expect(surface, findsOneWidget);
    _expectExpandedSheet(tester, surface, safeTop: 57);
    final openHeight = tester.getSize(surface).height;
    await _tapTooltip(tester, 'Expand or collapse Missions');
    expect(tester.getSize(surface).height, lessThan(openHeight));
    expect(
      tester.getRect(surface).bottom,
      tester.getRect(find.byKey(const ValueKey('mobile-navigation-dock'))).top,
    );

    await _mobileTab(tester, 'astronaut');
    expect(surface, findsOneWidget);
    expect(find.byTooltip('Close Missions'), findsNothing);
    expect(find.text('Total steps'), findsOneWidget);
    _expectExpandedSheet(tester, surface, safeTop: 57);
    await _tapPhoneAction(tester, find.text('SENSOR TEST'), tap: false);
    await _mobileTab(tester, 'crew');
    expect(surface, findsOneWidget);
    expect(find.byTooltip('Close Astronaut'), findsNothing);
    expect(find.text('Adrian Flores'), findsOneWidget);
    _expectExpandedSheet(tester, surface, safeTop: 57);
    await _tapTooltip(tester, 'Expand or collapse Crew');
    expect(tester.getSize(surface).height, lessThan(openHeight));
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(65, 38),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    _expectExpandedSheet(tester, surface, safeTop: 57);
    await _tapPhoneAction(tester, find.text('TARGET TEAMMATE'), tap: false);
    await _mobileTab(tester, 'crew');
    expect(surface, findsNothing);
    expect(map.view.value, pinched);

    await _mobileTab(tester, 'missions');
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(75, 33),
      Offset(0, openHeight * .94),
    );
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(map.view.value, pinched);
    await _mobileTab(tester, 'astronaut');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(tester.state(mapWidget), same(mapState));
    expect(map.view.value, pinched);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The phone checklist saves to the active astronaut and mission', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var completed = <String>[];
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, (call) async {
      switch (call.method) {
        case 'readMissionChecklist':
          expect(call.arguments, 'ARES-01/jezero');
          return completed;
        case 'writeMissionChecklist':
          final args = call.arguments as Map;
          expect(args['scope'], 'ARES-01/jezero');
          completed = (args['completed'] as List).cast<String>();
        case 'snapshot':
          return <String, Object?>{};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );

    final map = await _launch(tester, size: const Size(390, 844));
    await _mobileTab(tester, 'missions');
    final survey = find.byKey(const ValueKey('objective-ancient-liquid-water'));
    expect(_within(survey, 'Pending'), findsOneWidget);
    expect(_objectiveColor(tester, survey), DashboardStyle.panel);
    expect(find.byType(Checkbox), findsNothing);
    final bounds = tester.getRect(survey);
    final leftEdge = Offset(bounds.left + 8, bounds.top + 20);
    await tester.tapAt(leftEdge);
    await tester.tapAt(leftEdge);
    await tester.pumpAndSettle();
    expect(completed, ['ancient-liquid-water']);
    expect(_within(survey, 'Completed'), findsOneWidget);
    expect(_objectiveColor(tester, survey), const Color(0xFF145341));
    expect(find.text('1 of 3 complete · On this device'), findsOneWidget);
    await tester.tapAt(leftEdge);
    await tester.pumpAndSettle();
    expect(completed, isEmpty);
    expect(_objectiveColor(tester, survey), DashboardStyle.panel);
    expect(find.text('0 of 3 complete · On this device'), findsOneWidget);
    await tester.tapAt(leftEdge);
    await tester.pumpAndSettle();
    await _mobileTab(tester, 'astronaut');
    await _mobileTab(tester, 'missions');
    expect(_within(survey, 'Completed'), findsOneWidget);
    final sheet = find.byKey(const ValueKey('mobile-mission-sheet'));
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Delta outcrop')),
    );
    await tester.pumpAndSettle();
    expect(map.navigation.targetLabel, 'Delta outcrop');
    expect(completed, ['ancient-liquid-water']);
    expect(sheet, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _launch(tester, size: const Size(390, 844));
    await _mobileTab(tester, 'missions');
    expect(_within(survey, 'Completed'), findsOneWidget);
    expect(_objectiveColor(tester, survey), const Color(0xFF145341));
  });

  testWidgets('Solar HUD fits the portrait dock and action rail', (
    tester,
  ) async {
    final mini = find.byKey(const ValueKey('map-solar-cycle'));
    final fit = find.byKey(const ValueKey('map-scale-panel'));
    final rail = find.byKey(const ValueKey('mobile-map-controls'));
    final dock = find.byKey(const ValueKey('mobile-navigation-dock'));
    addTearDown(tester.view.resetViewPadding);
    for (final (size, scale, stacked) in [
      (const Size(393, 852), 1.0, false), // iPhone 16
      (const Size(428, 926), 1.0, false), // iPhone 14 Plus
      (const Size(320, 568), 2.0, false),
      (const Size(300, 640), 1.4, true),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.viewPadding = const FakeViewPadding(top: 20, bottom: 20);
      await _launch(tester, size: size, textScale: scale);
      final left = tester.getRect(mini);
      final right = tester.getRect(fit);
      if (stacked) {
        expect(left.bottom, lessThan(right.top));
      } else {
        expect(left.right, lessThan(right.left));
        expect(left.top, closeTo(right.top, .01));
        expect(left.height, closeTo(right.height, .01));
      }
      expect(right.bottom, lessThan(tester.getRect(dock).top));
      expect(left.overlaps(tester.getRect(rail)), isFalse);
      expect(right.overlaps(tester.getRect(rail)), isFalse);
      expect(
        find.text('Fit area · 500 m radius').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('NASA Mars Trek').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('One clock refreshes the map arc and Astronaut solar detail', (
    tester,
  ) async {
    var timestamp = DateTime.utc(2026, 11, 15, 18);
    await _launch(
      tester,
      size: const Size(393, 852),
      mission: marsMissionById['endeavour'],
      clock: () => timestamp,
    );
    final mini = find.byKey(const ValueKey('map-solar-cycle'));
    expect(find.byKey(const ValueKey('night-arc')), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    expect(_within(mini, '06:27'), findsOneWidget);
    expect(_within(mini, '18:24'), findsOneWidget);
    await _mobileTab(tester, 'astronaut');
    expect(mini, findsNothing);
    expect(find.byKey(const ValueKey('map-scale-panel')), findsNothing);
    expect(find.text('06:27'), findsOneWidget);
    expect(find.text('18:24'), findsOneWidget);
    expect(find.text('05:48'), findsWidgets);

    timestamp = timestamp.add(const Duration(hours: 4));
    await tester.pump(const Duration(minutes: 1));
    expect(find.byKey(const ValueKey('daylight-arc')), findsOneWidget);
    expect(find.text('05:48'), findsNothing);
    expect(find.text('Daylight'), findsOneWidget);
    await _mobileTab(tester, 'astronaut');
    expect(find.byKey(const ValueKey('daylight-arc')), findsOneWidget);
    expect(mini, findsOneWidget);
  });

  testWidgets('Phone tile status has its own space above the compact scale', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      sensorDiagnosticsChannel,
      (call) async => call.method == 'readMissionChecklist' ? <String>[] : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    addTearDown(tester.view.resetViewPadding);
    final status = find.byKey(const ValueKey('map-tile-status'));
    final footer = find.byKey(const ValueKey('map-scale-panel'));
    final fit = find.text('Fit area · 500 m radius');
    final scale = find.textContaining('≈ ');
    final credit = find.text('NASA Mars Trek');
    final retry = find.text('Retry');
    final rail = find.byKey(const ValueKey('mobile-map-controls'));
    final sheet = find.byKey(const ValueKey('mobile-mission-sheet'));
    for (final (size, safeArea, textScale) in [
      (const Size(390, 844), const FakeViewPadding(top: 59, bottom: 34), 1.0),
      (const Size(360, 806), const FakeViewPadding(top: 28, bottom: 38), 1.5),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.viewPadding = safeArea;
      final tiles = FakeTrekTiles();
      await _launch(tester, size: size, tiles: tiles, textScale: textScale);
      final footerRect = tester.getRect(footer);
      final errorRect = tester.getRect(status);
      expect(find.text('Map connection unavailable'), findsOneWidget);
      expect(footerRect.top - errorRect.bottom, closeTo(6, .001));
      expect(errorRect.overlaps(tester.getRect(rail)), isFalse);
      expect(footerRect.overlaps(tester.getRect(rail)), isFalse);
      expect(
        tester.getRect(scale).top - tester.getRect(fit).bottom,
        inInclusiveRange(0, 8),
      );
      expect(
        tester.getRect(credit).top - tester.getRect(scale).bottom,
        inInclusiveRange(0, 6),
      );
      expect(retry.hitTestable(), findsOneWidget);
      final requests = tiles.requested.length;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(tiles.requested.length, greaterThan(requests));
      expect(tester.getRect(footer), footerRect);

      for (final tab in ['missions', 'astronaut', 'crew']) {
        await _mobileTab(tester, tab);
        _expectExpandedSheet(tester, sheet, safeTop: safeArea.top);
        expect(status, findsNothing);
        expect(footer, findsNothing);
      }
      await _mobileTab(tester, 'crew');
      expect(retry.hitTestable(), findsOneWidget);
      expect(tester.getRect(footer), footerRect);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Endeavour opens regionally then follows with a 200 m scale bar',
    (tester) async {
      const size = Size(393, 852);
      final mission = marsMissionById['endeavour']!;
      final map = await _launch(
        tester,
        size: size,
        mission: mission,
        settle: false,
      );
      final nav = map.navigation;
      final view = map.view;
      final world = missionWorld(size);
      final center = size.center(Offset.zero);
      final scene = missionTrekMaps[mission.id]!.scene(mission, size);
      final local = find.descendant(
        of: find.byKey(const ValueKey('ARES-01')),
        matching: find.byType(RelativeMarkerArrow),
      );
      final markerWidth = tester.getRect(local).width;
      expect(view.value, Matrix4.identity());
      expect(map.tracking.follow, isFalse);
      await tester.pump(const Duration(milliseconds: 990));
      expect(view.value, Matrix4.identity());

      Offset walkFromBase(double east, double north) =>
          nav.map.coordinates.toGrid(
            displaceOnMars(
              nav.map.coordinates.toMars(nav.map.base),
              Offset(east, north),
            ),
          );
      final firstPosition = walkFromBase(20, 10);
      nav.applyStepPosition(firstPosition);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 400));
      final intermediateScale = view.value.getMaxScaleOnAxis();
      expect(intermediateScale, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 650));
      expect(map.tracking.follow, isFalse);
      final currentPosition = walkFromBase(35, 15);
      nav.applyStepPosition(currentPosition);
      await tester.pumpAndSettle();

      final scale = view.value.getMaxScaleOnAxis();
      final focus = world.topLeft + currentPosition * world.width;
      final barDistance = scene.groundMetersPerPixel(focus) * 50 / scale;
      expect(barDistance, closeTo(200, .001));
      expect(scale, greaterThan(intermediateScale));
      expect((view.toScene(center) - focus).distance, lessThan(.0001));
      expect(map.tracking.follow, isTrue);
      expect(nav.position, currentPosition);
      expect(tester.getRect(local).width, closeTo(markerWidth, .001));
      expect(find.text('≈ 200 m'), findsOneWidget);
      expect(find.text('Fit area · 750 m radius'), findsOneWidget);
      expect(find.text('Raster resolution limit'), findsNothing);
      expect(find.text('Map connection unavailable'), findsOneWidget);

      final oldTransform = Matrix4.copy(view.value);
      final next = walkFromBase(50, 20);
      nav.applyStepPosition(next);
      await tester.pump(); // Build and queue the follow animation.
      await tester.pump(); // Establish the ticker's first frame.
      await tester.pump(const Duration(milliseconds: 110));
      expect(view.value, isNot(oldTransform));
      expect(tester.getCenter(local), isNot(center));
      await tester.pumpAndSettle();
      expect(view.value.getMaxScaleOnAxis(), closeTo(scale, .001));
      expect((tester.getCenter(local) - center).distance, lessThan(.001));
      expect(nav.position, next);

      final pinchPoint = center - const Offset(45, 35);
      final left = await tester.startGesture(pinchPoint - const Offset(45, 0));
      final right = await tester.startGesture(pinchPoint + const Offset(45, 0));
      await left.moveBy(const Offset(14, 0));
      await right.moveBy(const Offset(-14, 0));
      await tester.pump();
      final anchor = view.toScene(pinchPoint);
      await left.moveBy(const Offset(12, 0));
      await right.moveBy(const Offset(-12, 0));
      await tester.pump();
      // The two pointer moves arrive separately during the same pinch.
      expect(
        (MatrixUtils.transformPoint(view.value, anchor) - pinchPoint).distance,
        lessThan(8),
      );
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
      expect(view.value.getMaxScaleOnAxis(), lessThan(scale));
      final manualScale = view.value.getMaxScaleOnAxis();
      final afterPinch = Matrix4.copy(view.value);
      expect(map.tracking.follow, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(view.value, afterPinch);

      await tester.dragFrom(
        center - const Offset(50, 35),
        const Offset(48, 40),
      );
      await tester.pumpAndSettle();
      expect(map.tracking.follow, isFalse);
      final afterPan = Matrix4.copy(view.value);
      nav.applyStepPosition(walkFromBase(65, 25));
      await tester.pumpAndSettle();
      expect(view.value, afterPan);
      await _tapTooltip(tester, 'Recenter on astronaut');
      expect(view.value.getMaxScaleOnAxis(), closeTo(manualScale, .001));
      expect((tester.getCenter(local) - center).distance, lessThan(.001));
      await _tapTooltip(tester, 'Heading-up');
      expect(map.tracking.follow, isTrue);
      expect(view.headingUp.value, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Opening zoom uses the finest available regional or global raster',
    (tester) async {
      const size = Size(390, 844);
      for (final mission in [
        marsMissionById['gale']!,
        marsMissionById['valles-marineris']!,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final tiles = FakeTrekTiles();
        final map = await _launch(
          tester,
          size: size,
          mission: mission,
          tiles: tiles,
          settle: false,
        );
        final config = missionTrekMaps[mission.id]!;
        final layer = config.detail ?? globalTrekLayer;
        final scene = config.scene(mission, size);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          map.view.value.getMaxScaleOnAxis(),
          closeTo(scene.degreesPerPixel / layer.finestDegreesPerPixel, .001),
        );
        expect(map.tracking.follow, isTrue);
        expect(find.text('Raster resolution limit'), findsNothing);
        expect(find.text('Map connection unavailable'), findsOneWidget);
        final focus = scene.toGeographic(
          map.view.toScene(size.center(Offset.zero)),
        );
        final visible = Rect.fromCenter(
          center: focus,
          width: 1e-7,
          height: 1e-7,
        );
        expect(
          tiles.requested,
          contains(layer.tiles(visible, layer.maxMatrix).single.uri),
        );
        expect(map.navigation.map.radiusMeters, mission.radiusMeters);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Manual pan and pinch cancel pending opening zoom', (
    tester,
  ) async {
    const size = Size(393, 852);
    for (final pinch in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      final map = await _launch(
        tester,
        size: size,
        mission: marsMissionById['endeavour']!,
        settle: false,
      );
      const focal = Offset(140, 420);
      await tester.pump(const Duration(milliseconds: 550));
      if (pinch) {
        await _pinchPhoneMap(tester, focal, 30);
        expect(map.view.value.getMaxScaleOnAxis(), greaterThan(1));
      } else {
        await tester.dragFrom(focal, const Offset(55, 40));
        await tester.pumpAndSettle();
        expect(map.view.value, isNot(Matrix4.identity()));
      }
      final chosen = Matrix4.copy(map.view.value);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(map.view.value, chosen);
      expect(map.tracking.follow, isFalse);
    }
  });

  testWidgets(
    'An opening zoom is interruptible and closing a sheet never restarts it',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        sensorDiagnosticsChannel,
        (call) async =>
            call.method == 'readMissionChecklist' ? <String>[] : null,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );
      const size = Size(393, 852);
      final mission = marsMissionById['endeavour']!;
      final map = await _launch(
        tester,
        size: size,
        mission: mission,
        settle: false,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 320));
      expect(map.view.value.getMaxScaleOnAxis(), greaterThan(1));
      await _pinchPhoneMap(tester, const Offset(155, 425), 25);
      final chosen = Matrix4.copy(map.view.value);
      await tester.pump(const Duration(seconds: 2));
      expect(map.view.value, chosen);
      expect(map.tracking.follow, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      final next = await _launch(
        tester,
        size: size,
        mission: mission,
        settle: false,
      );
      await _mobileTab(tester, 'missions');
      await tester.pump(const Duration(seconds: 2));
      await _mobileTab(tester, 'missions');
      await tester.pump(const Duration(seconds: 2));
      expect(next.view.value, Matrix4.identity());
      expect(next.tracking.follow, isFalse);
      expect(find.byType(DemoTerrainMap), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _launch(tester, size: size, mission: mission, settle: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phone camera toggles heading while preserving map interactions',
    (tester) async {
      const size = Size(390, 844);
      final map = await _launch(
        tester,
        size: size,
        mission: marsMissions.singleWhere((mission) => mission.id == 'jezero'),
      );
      final view = map.view;
      final world = missionWorld(size);
      final local = find.descendant(
        of: find.byKey(const ValueKey('ARES-01')),
        matching: find.byType(RelativeMarkerArrow),
      );
      final glyph = find.descendant(
        of: local,
        matching: find.byIcon(Icons.navigation_rounded),
      );
      final label = find.text('ARES-01 · YOU');
      final viewport = find.byKey(const ValueKey('demo-map-viewport'));
      final center = tester.getCenter(viewport);
      double angle(Finder finder) {
        final matrix = tester
            .renderObject<RenderBox>(finder)
            .getTransformTo(null);
        return math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));
      }

      await tester.tap(find.text('Fit area · 500 m radius'));
      await tester.pumpAndSettle();
      final startZoom = view.value.getMaxScaleOnAxis();
      final markerWidth = tester.getRect(local).width;
      final startPosition = map.navigation.position;
      map.tracking.heading.value = 90;
      await tester.pumpAndSettle();
      expect(view.headingUp.value, isFalse);
      expect(view.rotation, 0);
      expect(angle(glyph), closeTo(math.pi / 2, .001));

      const dragStart = Offset(-45, -75);
      await tester.dragFrom(center + dragStart, const Offset(-25, 37));
      await tester.pumpAndSettle();
      expect((tester.getCenter(local) - center).distance, greaterThan(10));
      await _tapTooltip(tester, 'Recenter on astronaut');
      expect((tester.getCenter(local) - center).distance, lessThan(.01));
      await _tapTooltip(tester, 'Heading-up');
      expect(view.headingUp.value, isTrue);
      expect(map.tracking.follow, isTrue);
      expect(tester.getRect(local).width, closeTo(markerWidth, .001));
      expect(view.rotation, closeTo(-math.pi / 2, .001));
      expect(view.value.getMaxScaleOnAxis(), closeTo(startZoom, .001));
      expect(map.navigation.position, startPosition);
      expect(angle(glyph), closeTo(0, .001));
      expect(angle(label), closeTo(0, .001));

      final coordinate = map.tracking.coordinates.toGrid(
        displaceOnMars(map.tracking.pose.mars, const Offset(170, 145)),
      );
      final target = world.topLeft + coordinate * world.width;
      final screen = MatrixUtils.transformPoint(view.value, target);
      await tester.tapAt(screen);
      await tester.pumpAndSettle();
      expect((map.navigation.target! - coordinate).distance, lessThan(.00001));
      final route = find.byKey(const ValueKey('mission-route-overlay'));
      expect(
        (tester.renderObject<RenderBox>(route).localToGlobal(target) - screen)
            .distance,
        lessThan(.001),
      );
      final flag = find.byIcon(Icons.flag);
      expect((tester.getCenter(flag) - screen).distance, lessThan(.001));
      expect(angle(flag), closeTo(0, .001));

      await _pinchPhoneMap(tester, center, -26);
      final zoom = view.value.getMaxScaleOnAxis();
      expect(zoom, lessThan(startZoom));
      expect(view.rotation, closeTo(-math.pi / 2, .001));

      await tester.dragFrom(center + dragStart, const Offset(36, 38));
      await tester.pumpAndSettle();
      expect((tester.getCenter(local) - center).distance, greaterThan(10));
      expect(map.tracking.follow, isTrue);

      final moved = map.tracking.coordinates.toGrid(
        displaceOnMars(map.tracking.pose.mars, const Offset(13, 17)),
      );
      map.navigation.applyStepPosition(moved);
      await tester.pumpAndSettle();
      expect((tester.getCenter(local) - center).distance, lessThan(.01));
      expect(view.value.getMaxScaleOnAxis(), closeTo(zoom, .001));
      expect(map.navigation.position, moved);

      map.tracking.heading.value = 170;
      await tester.pumpAndSettle();
      map.tracking.heading.value = -175;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(math.cos(view.rotation), lessThan(-.98));
      expect(angle(glyph), closeTo(0, .001));
      await tester.pumpAndSettle();
      expect(view.rotation, closeTo(175 * math.pi / 180, .001));
      final stableView = Matrix4.copy(view.value);
      map.tracking.heading.value = -175.8;
      await tester.pumpAndSettle();
      expect(view.value, stableView);
      map.tracking.heading.value = null;
      await tester.pumpAndSettle();
      expect(view.value, stableView);

      map.tracking.heading.value = 90;
      await tester.pumpAndSettle();
      await _tapTooltip(tester, 'North-up');
      expect(view.headingUp.value, isFalse);
      expect(view.rotation, closeTo(0, .001));
      expect(view.value.getMaxScaleOnAxis(), closeTo(zoom, .001));
      expect(map.navigation.position, moved);
      expect(angle(glyph), closeTo(math.pi / 2, .001));
      expect(angle(label), closeTo(0, .001));
      expect(tester.takeException(), isNull);
    },
  );

  test('Rotated terrain requests tiles covering all four viewport corners', () {
    const size = Size(390, 844);
    const scale = 2.0;
    final view = TerrainViewController();
    addTearDown(view.dispose);
    final center = size.center(Offset.zero);
    view.frame(center, center, scale, angle: math.pi / 4);
    final region = view.visibleScene(size);
    final extent = (size.width + size.height) / (math.sqrt(2) * scale);
    expect(region.width, closeTo(extent, .001));
    expect(region.height, closeTo(extent, .001));
    expect((region.center - center).distance, lessThan(.001));
  });

  testWidgets('Live route paint stays anchored and arrival is announced once', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      sensorDiagnosticsChannel,
      (call) async => call.method == 'snapshot' ? <String, Object?>{} : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    const size = Size(390, 844);
    final map = await _launch(tester, size: size);
    final nav = map.navigation;
    final header = find.byKey(const ValueKey('mobile-mission-header'));
    final headerRect = tester.getRect(header);
    final routeOverlay = find.byKey(const ValueKey('mission-route-overlay'));
    final world = missionWorld(size);
    final start = find.byTooltip('Start Navigation');
    final coordinates = nav.map.coordinates;
    Offset east(double meters) => coordinates.toGrid(
      displaceOnMars(coordinates.toMars(nav.map.base), Offset(meters, 0)),
    );
    expect(map.tracking.mode, TrackingMode.live);
    expect(find.text('LIVE SENSORS'), findsNothing);
    final destination = east(25);
    nav.select(destination, 'Map waypoint');
    await tester.pumpAndSettle();
    expect(find.text('Direct guidance · Terrain unverified'), findsOneWidget);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.base);
    expect(tester.getRect(header), headerRect);
    expect(find.text('Navigating'), findsOneWidget);
    final from = world.topLeft + nav.map.base * world.width;
    final to = world.topLeft + destination * world.width;
    List<List<dynamic>> segments() {
      final canvas = TestRecordingCanvas();
      tester.widget<CustomPaint>(routeOverlay).painter!.paint(canvas, size);
      return [
        for (final call in canvas.invocations.map(
          (record) => record.invocation,
        ))
          if (call.memberName == #drawLine &&
              (call.positionalArguments.last as Paint).color.toARGB32() ==
                  DashboardStyle.warm.toARGB32())
            call.positionalArguments,
      ];
    }

    expect(segments().first.first, from);
    expect(segments().last[1], to);
    await tester.tap(find.text('Fit area · 500 m radius'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(155, 375), const Offset(-30, 55));
    await tester.pumpAndSettle();
    final afterPan = Matrix4.copy(map.view.value);
    expect(segments().first.first, from);
    expect(segments().last[1], to);
    final arrivalPosition = east(20);
    final approaching = east(14);
    nav.applyStepPosition(approaching);
    await tester.pumpAndSettle();
    final current = world.topLeft + approaching * world.width;
    expect(segments().first.first, current);
    expect(segments().last[1], to);
    nav.applyStepPosition(arrivalPosition);
    await tester.pumpAndSettle();
    expect(find.text('You have arrived at your destination.'), findsOneWidget);
    expect(nav.position, arrivalPosition);
    expect(nav.target, destination);
    expect(segments(), isEmpty);
    expect(map.view.value, afterPan);
    expect(tester.getRect(header), headerRect);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    nav.applyStepPosition(east(21));
    await tester.pumpAndSettle();
    expect(find.text('You have arrived at your destination.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gale phone keeps the shared marker clear of the base label', (
    tester,
  ) async {
    final map = await _launch(
      tester,
      size: const Size(390, 844),
      mission: marsMissionById['gale']!,
    );
    await _connectPhoneCrew(tester, map);
    final baseLabel = find.text('Habitat base');
    final peer = find.byTooltip('Select Adrian Flores on map');
    expect(tester.getRect(baseLabel).overlaps(tester.getRect(peer)), isFalse);
    expect(tester.getSize(peer), const Size.square(48));
    await tester.tap(peer);
    await tester.pumpAndSettle();
    expect(map.navigation.target, map.navigation.map.teammate);
  });

  testWidgets(
    'All phone checklists show the catalog objectives and load only their own saved IDs',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final saved = <String, List<String>>{};
      messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, (
        call,
      ) async {
        if (call.method == 'readMissionChecklist') {
          return saved[call.arguments] ?? <String>[];
        }
        if (call.method == 'writeMissionChecklist') {
          final args = call.arguments as Map;
          saved[args['scope'] as String] = (args['completed'] as List)
              .cast<String>();
        }
        if (call.method == 'snapshot') return <String, Object?>{};
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
      );
      for (final astronaut in DemoCrew.roster) {
        for (final mission in marsMissions) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await _launch(
            tester,
            size: const Size(390, 844),
            mission: mission,
            astronaut: astronaut,
          );
          expect(
            find.text('Fit area · ${mission.radiusLabel} radius'),
            findsOneWidget,
          );
          await _mobileTab(tester, 'missions');
          expect(find.text('0 of 3 complete · On this device'), findsOneWidget);
          for (final objective in mission.objectives) {
            final tile = find.byKey(ValueKey('objective-${objective.id}'));
            expect(_within(tile, 'Pending'), findsOneWidget);
            expect(
              find.descendant(of: tile, matching: find.text(objective.label)),
              findsOneWidget,
            );
          }
          if (astronaut == DemoCrew.dan) {
            final tile = find.byKey(
              ValueKey('objective-${mission.objectives.first.id}'),
            );
            await tester.tap(tile);
            await tester.pumpAndSettle();
            expect(saved['${astronaut.id}/${mission.id}'], [
              mission.objectives.first.id,
            ]);
          }
          expect(tester.takeException(), isNull);
        }
      }
      expect(saved.keys, hasLength(5));
    },
  );

  testWidgets(
    'Phone route actions work and offline Crew alerts stay unconfirmed',
    (tester) async {
      final map = await _launch(tester, size: const Size(320, 568));
      final nav = map.navigation;
      final start = find.byKey(const ValueKey('mobile-action-start'));
      expect(tester.widget<IconButton>(start).onPressed, isNull);
      expect(nav.moving, isFalse);
      expect(nav.select(const Offset(0, 0), 'Outside the area'), isFalse);
      expect(nav.select(nav.map.teammate, 'Survey route'), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(nav.guiding, isTrue);
      expect(nav.position, nav.map.base);
      expect(nav.canReturnToBase, isFalse);
      final awayFromTarget = nav.map.teammate.dx >= nav.map.base.dx
          ? -150.0
          : 150.0;
      final walked = nav.map.coordinates.toGrid(
        displaceOnMars(
          nav.map.coordinates.toMars(nav.map.base),
          Offset(awayFromTarget, 0),
        ),
      );
      nav.applyStepPosition(walked);
      await tester.pumpAndSettle();
      expect(nav.canReturnToBase, isTrue);
      await _mobileTab(tester, 'astronaut');
      final pause = find.text('PAUSE MISSION');
      await _tapPhoneAction(tester, pause);
      await tester.pumpAndSettle();
      expect(nav.paused, isTrue);
      await tester.tap(find.text('RESUME MISSION'));
      await tester.pumpAndSettle();
      expect(nav.paused, isFalse);
      await _mobileTab(tester, 'astronaut');

      await _tapTooltip(tester, 'Return to Base');
      expect(nav.position, walked);
      expect(find.text('Return to habitat base?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(nav.position, walked);
      expect(nav.target, nav.map.teammate);
      await _tapTooltip(tester, 'Return to Base');
      await tester.tap(find.text('Return to base'));
      expect(nav.position, walked);
      expect(nav.target, nav.map.base);
      await tester.pumpAndSettle();
      expect(nav.position, walked);
      expect(nav.guiding, isTrue);
      nav.applyStepPosition(nav.map.base);
      await tester.pumpAndSettle();
      expect(nav.position, nav.map.base);
      expect(find.text('You have arrived at Habitat Base.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      nav.select(nav.map.teammate, 'Another destination');
      await tester.pumpAndSettle();
      await _tapTooltip(tester, 'Send PIN');
      expect(find.text('Connect to Crew to share a PIN.'), findsOneWidget);
      expect(find.text('Destination shared with Crew.'), findsNothing);
      expect(nav.pings, isEmpty);
      expect(nav.position, nav.map.base);

      await _tapTooltip(tester, 'SOS');
      expect(find.text('Send SOS to your crew?'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(nav.paused, isFalse);
      expect(find.byKey(const ValueKey('crew-sos-marker')), findsNothing);
      await _tapTooltip(tester, 'SOS');
      await tester.tap(find.text('SEND SOS'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to Crew to update SOS.'), findsOneWidget);
      expect(find.text('SOS ACTIVE'), findsNothing);
      expect(nav.paused, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Connected phone needs an explicit destination to send a PIN', (
    tester,
  ) async {
    final map = await _launch(tester, size: const Size(390, 844));
    final session = await _connectPhoneCrew(tester, map);
    final nav = map.navigation;
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(nav.selectedDestination, isNull);
    expect(nav.select(Offset.zero, 'Outside the mission'), isFalse);
    await _tapTooltip(tester, 'Send PIN');
    expect(find.text('Select a destination on the map first.'), findsOneWidget);
    expect(session.pinWrites, isEmpty);
    expect(session.pinned, isEmpty);
    expect(find.byKey(const ValueKey('crew-pin-ARES-01')), findsNothing);
    expect(nav.position, nav.map.base);
    expect(nav.guiding, isFalse);

    // A route to a crew SOS is distinct from a user-selected destination.
    nav.setRescueWaypoint(nav.map.landmarks.first.position);
    await _tapTooltip(tester, 'Send PIN');
    expect(find.text('Select a destination on the map first.'), findsWidgets);
    expect(session.pinWrites, isEmpty);
    expect(nav.target, nav.map.landmarks.first.position);
  });

  testWidgets('PIN sends the selected coordinates and expires independently', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 15, 18);
    const size = Size(390, 844);
    final map = await _launch(tester, size: size, clock: () => now);
    final session = await _connectPhoneCrew(tester, map);
    final nav = map.navigation;
    session.updateSignals();
    await tester.pumpAndSettle();
    final base = map.tracking.pose.mars;
    final moved = displaceOnMars(base, const Offset(11, 0));
    nav.applyStepPosition(map.tracking.gridPosition(moved));
    final target = nav.map.landmarks.first.position;
    final destination = nav.map.coordinates.toMars(target);
    expect(nav.select(target, 'Survey'), isTrue);
    await tester.pumpAndSettle();
    final presenceWrites = session.writes.length;

    final gate = Completer<void>();
    session.pinGate = gate;
    await _tapTooltip(tester, 'Send PIN');
    expect(session.pinWrites.single, destination);
    expect(session.pinWrites.single, isNot(moved));
    expect(map.tracking.pose.mars, moved);
    expect(nav.target, target);
    expect(nav.guiding, isFalse);
    expect(find.text('Destination shared with Crew.'), findsNothing);
    final pin = find.byKey(const ValueKey('crew-pin-ARES-01'));
    expect(pin, findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Destination shared with Crew.'), findsOneWidget);
    expect(session.writes, hasLength(presenceWrites));
    expect(pin, findsOneWidget);
    final world = missionWorld(size);
    final anchor = MatrixUtils.transformPoint(
      map.view.value,
      world.topLeft + target * world.width,
    );
    expect((tester.getCenter(pin) - anchor).distance, lessThan(.001));
    expect(
      find.descendant(
        of: pin,
        matching: find.byKey(const ValueKey('pin-anchor-tether')),
      ),
      findsOneWidget,
    );

    final other = displaceOnMars(base, const Offset(0, 18));
    session.pinned['ARES-02'] = (mars: other, updated: now);
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(find.text('PIN · ARES-02'), findsOneWidget);
    for (final (id, color) in [
      ('ARES-01', DashboardStyle.cyan),
      ('ARES-02', DashboardStyle.amber),
    ]) {
      final marker = find.byKey(ValueKey('crew-pin-$id'));
      final glyph = find.descendant(
        of: marker,
        matching: find.byIcon(Icons.location_on_rounded),
      );
      expect(tester.widget<Icon>(glyph).color, color);
      expect(tester.widget<Text>(find.text('PIN · $id')).style?.color, color);
    }
    expect(nav.target, target);

    final next = nav.map.landmarks[1].position;
    expect(nav.select(next, 'Second survey'), isTrue);
    now = now.add(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    await _tapTooltip(tester, 'Send PIN');
    expect(session.pinWrites.last, nav.map.coordinates.toMars(next));
    expect(session.pinned['ARES-01']!.mars, session.pinWrites.last);
    expect(session.pinned['ARES-02']!.mars, other);
    expect(pin, findsOneWidget);
    nav.start();
    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('PIN · ARES-02'), findsNothing);
    expect(pin, findsOneWidget);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 250));
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(pin, findsNothing);
    expect(nav.target, next);
    expect(nav.guiding, isTrue);
  });

  testWidgets('Remote PIN keeps its map anchor and selects only on tap', (
    tester,
  ) async {
    const size = Size(390, 844);
    final map = await _launch(tester, size: size, astronaut: DemoCrew.adrian);
    final session = await _connectPhoneCrew(tester, map);
    final navigation = map.navigation;
    final prior = navigation.map.landmarks.first.position;
    expect(navigation.select(prior, 'Existing destination'), isTrue);
    navigation.start();
    final origin = navigation.position;
    final coordinate = displaceOnMars(
      map.tracking.pose.mars,
      const Offset(78, 65),
    );
    final point = map.tracking.gridPosition(coordinate);
    session.pinned['ARES-01'] = (mars: coordinate, updated: session.clock());
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(navigation.target, prior);
    expect(navigation.guiding, isTrue);
    expect(
      tester
          .widget<DemoTerrainMap>(find.byType(DemoTerrainMap))
          .sharedPins['ARES-01'],
      point,
    );

    final pin = find.byKey(const ValueKey('crew-pin-ARES-01'));
    final tap = find.byTooltip('Select PIN from ARES-01');
    final world = missionWorld(size);
    void expectAnchor() {
      final position = MatrixUtils.transformPoint(
        map.view.value,
        world.topLeft + point * world.width,
      );
      expect((tester.getCenter(pin) - position).distance, lessThan(.001));
    }

    expectAnchor();
    await tester.tap(find.text('Fit area · 500 m radius'));
    await tester.pumpAndSettle();
    expectAnchor();
    await tester.dragFrom(const Offset(160, 480), const Offset(22, 16));
    await tester.pumpAndSettle();
    expectAnchor();
    await _tapTooltip(tester, 'Recenter on astronaut');
    expectAnchor();
    map.tracking.heading.value = 65;
    await _tapTooltip(tester, 'Heading-up');
    expect(map.view.rotation, isNot(0));
    expectAnchor();
    expect(tap.hitTestable(), findsOneWidget);
    await tester.tap(tap);
    await tester.pumpAndSettle();
    expect(navigation.target, point);
    expect(navigation.targetLabel, 'PIN · ARES-01');
    expect(navigation.guiding, isFalse);
    expect(navigation.position, origin);
    expect(tap.hitTestable(), findsOneWidget);
    await _tapTooltip(tester, 'North-up');
    expectAnchor();
    expect(map.view.rotation, closeTo(0, 1e-12));
  });

  testWidgets('Sender can cancel shared SOS and keep moving', (tester) async {
    final map = await _launch(tester, size: const Size(390, 844));
    final session = await _connectPhoneCrew(tester, map);
    session.updateSignals();
    await tester.pumpAndSettle();
    final normal = _missionRim(tester);
    final captured = map.tracking.pose.mars;

    final solar = find.byKey(const ValueKey('map-solar-cycle'));
    expect(solar, findsOneWidget);
    await _tapTooltip(tester, 'SOS');
    expect(session.started, 0);
    await tester.tap(find.text('SEND SOS'));
    await tester.pumpAndSettle();
    expect(session.started, 1);
    expect(session.alert!.mars, captured);
    expect(find.text('SOS ACTIVE'), findsOneWidget);
    expect(solar, findsNothing);
    expect(find.text('NASA Mars Trek'), findsOneWidget);
    expect(find.byKey(const ValueKey('incoming-crew-sos')), findsNothing);
    final active = _missionRim(tester);
    expect(active.color, DashboardStyle.danger.toARGB32());
    expect(active.bounds, normal.bounds);
    expect(map.navigation.paused, isFalse);

    final walked = displaceOnMars(captured, const Offset(9, 0));
    map.navigation.applyStepPosition(map.tracking.coordinates.toGrid(walked));
    await tester.pumpAndSettle();
    final updated = tester.widget<DemoTerrainMap>(find.byType(DemoTerrainMap));
    expect(updated.sharedSos!.point, map.tracking.gridPosition(captured));
    expect(map.tracking.pose.mars, walked);
    expect(session.finished, isEmpty);

    await _tapTooltip(tester, 'Cancel SOS');
    expect(session.finished.single, SosState.canceled);
    expect(solar, findsOneWidget);
    expect(find.byKey(const ValueKey('crew-sos-marker')), findsNothing);
    expect(_missionRim(tester), normal);
    expect(find.text('Crew SOS canceled.'), findsOneWidget);
  });

  testWidgets('Receiver gets one SOS modal and resolves by accepted arrival', (
    tester,
  ) async {
    final motion = _PhoneMotion();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    final map = await _launch(
      tester,
      size: const Size(390, 844),
      astronaut: DemoCrew.adrian,
      clock: () => motion.now,
    );
    final session = await _connectPhoneCrew(tester, map);
    final home = map.tracking.pose.mars;
    final rescue = displaceOnMars(home, const Offset(0, 10));
    final prior = map.navigation.map.landmarks.first.position;
    map.navigation.select(prior, 'Survey');
    final normal = _missionRim(tester);
    session.alert = (
      id: 'peer-arrival-test',
      sender: 'ARES-01',
      mars: rescue,
      started: motion.now,
      state: SosState.active,
      finishedBy: null,
    );
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(find.text('SOS — ARES-01 NEEDS HELP'), findsOneWidget);
    expect(
      find.textContaining('Dan Urquía has requested assistance.'),
      findsOneWidget,
    );
    expect(find.textContaining('Estimated distance · 10 m'), findsOneWidget);
    expect(map.navigation.target, map.tracking.gridPosition(rescue));
    expect(map.navigation.guiding, isTrue);
    expect(_missionRim(tester).bounds, normal.bounds);
    expect(_missionRim(tester).color, DashboardStyle.danger.toARGB32());
    await tester.tap(find.text('DISMISS'));
    await tester.pumpAndSettle();
    session.updateSignals();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-crew-sos')), findsNothing);
    expect(find.text('RESCUE · ARES-01'), findsOneWidget);
    expect(find.text('Rescue waypoint'), findsOneWidget);
    expect(session.finished, isEmpty);

    await _tapTooltip(tester, 'Heading-up');
    await motion.poll(tester, 1, yaw: 42);
    await motion.poll(tester, 2, yaw: 42, steps: 4);
    expect(map.navigation.remainingMeters, closeTo(7.2, .01));
    expect(session.finished, isEmpty);
    await motion.poll(tester, 3, yaw: 42, steps: 9);
    expect(map.tracking.appliedSteps, 9);
    expect(session.finished.single, SosState.resolved);
    expect(session.alert!.finishedBy, 'ARES-02');
    expect(map.navigation.target, prior);
    expect(find.byKey(const ValueKey('crew-sos-marker')), findsNothing);
    expect(_missionRim(tester), normal);
    expect(find.text('Rescue completed by ARES-02.'), findsOneWidget);
    session.updateSignals();
    await motion.poll(tester, 4, yaw: 42, steps: 10);
    expect(session.finished, hasLength(1));
    expect(find.byKey(const ValueKey('incoming-crew-sos')), findsNothing);
    await _tapTooltip(tester, 'North-up');
  });

  testWidgets('Rescue survives signal reconnect without reopening the modal', (
    tester,
  ) async {
    final motion = _PhoneMotion();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, motion.handle);
    addTearDown(
      () => messenger.setMockMethodCallHandler(sensorDiagnosticsChannel, null),
    );
    final connections = <_PhonePresence>[];
    CrewSos? serverAlert;
    final map = await _launch(
      tester,
      size: const Size(390, 844),
      astronaut: DemoCrew.adrian,
      clock: () => motion.now,
      connectPresence: (key) async {
        final connection = _PhonePresence(() => motion.now)
          ..key = key
          ..alert = serverAlert;
        connections.add(connection);
        connection.update({});
        connection.updateSignals();
        return connection;
      },
    );
    await _mobileTab(tester, 'crew');
    serverAlert = (
      id: 'test-reconnect-alert',
      sender: 'ARES-01',
      mars: map.tracking.pose.mars,
      started: motion.now,
      state: SosState.active,
      finishedBy: null,
    );
    connections.single
      ..alert = serverAlert
      ..updateSignals();
    await tester.pumpAndSettle();
    await tester.tap(find.text('VIEW WAYPOINT'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close Crew'), findsNothing);
    expect(map.navigation.rescuing, isTrue);
    connections.single.signals.addError(StateError('Connection lost'));
    await tester.pumpAndSettle();
    expect(map.navigation.rescuing, isTrue);
    expect(find.byKey(const ValueKey('crew-sos-marker')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(connections, hasLength(2));
    expect(find.byKey(const ValueKey('incoming-crew-sos')), findsNothing);
    expect(map.navigation.rescuing, isTrue);
    expect(connections.last.finished, isEmpty);
    connections.last
      ..alert = null
      ..updateSignals();
    await tester.pumpAndSettle();
    expect(map.navigation.rescuing, isFalse);
    expect(find.byKey(const ValueKey('crew-sos-marker')), findsNothing);
  });

  testWidgets(
    'Phone chrome fits safe areas with stable header and three readings',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetViewPadding);
      for (final (size, safeArea) in [
        (const Size(390, 844), const FakeViewPadding(top: 59, bottom: 34)),
        (const Size(360, 806), const FakeViewPadding(top: 28, bottom: 38)),
        (const Size(320, 568), const FakeViewPadding(top: 24, bottom: 28)),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.viewPadding = safeArea;
        final map = await _launch(
          tester,
          size: size,
          mission: marsMissionById['gale']!,
        );
        final header = find.byKey(const ValueKey('mobile-mission-header'));
        final readings = find.byKey(const ValueKey('mobile-map-telemetry'));
        final actions = find.byKey(const ValueKey('mobile-map-actions'));
        final circles = find.descendant(
          of: actions,
          matching: find.byType(IconButton),
        );
        final dock = find.byKey(const ValueKey('mobile-tab-crew'));
        final headerRect = tester.getRect(header);
        final readingsRect = tester.getRect(readings);
        expect(headerRect.top, greaterThan(safeArea.top));
        expect(readingsRect.top, greaterThan(headerRect.bottom));
        expect(readingsRect.center.dx, size.width / 2);
        expect(find.text('Destination: —'), findsOneWidget);
        expect(_within(readings, 'MARS TIME'), findsOneWidget);
        expect(_within(readings, 'TEMP'), findsOneWidget);
        expect(_within(readings, 'ELEVATION'), findsOneWidget);
        expect(_within(readings, '−2606 m'), findsOneWidget);
        expect(circles, findsNWidgets(4));
        for (final label in [
          'Start Navigation',
          'Return to Base',
          'Send PIN',
          'SOS',
        ]) {
          expect(find.bySemanticsLabel(label), findsOneWidget);
        }

        Rect? previous;
        for (final button in tester.widgetList<IconButton>(circles)) {
          final style = button.style!;
          expect(style.shape!.resolve({}), isA<CircleBorder>());
          expect(style.backgroundColor!.resolve({}), DashboardStyle.orange);
          expect(style.foregroundColor!.resolve({}), MissionTheme.black);
          final rect = tester.getRect(find.byKey(button.key!));
          expect(rect.width, closeTo(rect.height, .001));
          expect(rect.width, greaterThanOrEqualTo(44));
          if (size.height <= 600) {
            expect(rect.left, greaterThan(previous?.right ?? 12));
            expect(rect.top, greaterThan(readingsRect.bottom));
            expect(find.byKey(button.key!).hitTestable(), findsOneWidget);
          } else {
            expect(rect.right, closeTo(size.width - 12, .001));
            expect(
              rect.top,
              greaterThan(previous?.bottom ?? readingsRect.bottom),
            );
          }
          expect(rect.bottom, lessThan(tester.getTopLeft(dock).dy));
          expect(
            rect.overlaps(tester.getRect(find.byTooltip('Heading-up'))),
            isFalse,
          );
          previous = rect;
        }
        final recenter = find.byTooltip('Recenter on astronaut');
        final follow = find.byTooltip('Heading-up');
        expect(recenter, findsOneWidget);
        expect(follow, findsOneWidget);
        final sosRect = tester.getRect(
          find.byKey(const ValueKey('mobile-action-sos')),
        );
        final recenterRect = tester.getRect(recenter);
        final followRect = tester.getRect(follow);
        if (size.height <= 600) {
          expect(recenterRect.center.dy, closeTo(sosRect.center.dy, .001));
          expect(followRect.center.dy, closeTo(sosRect.center.dy, .001));
          expect(recenterRect.left, greaterThan(sosRect.right));
          expect(followRect.left, greaterThan(recenterRect.right));
          expect(followRect.right, closeTo(size.width - 12, .001));
        } else {
          expect(recenterRect.center.dx, closeTo(sosRect.center.dx, .001));
          expect(followRect.center.dx, closeTo(sosRect.center.dx, .001));
          expect(recenterRect.top, greaterThan(sosRect.bottom));
          expect(followRect.top, greaterThan(recenterRect.bottom));
          expect(
            followRect.top - recenterRect.bottom,
            closeTo(recenterRect.top - sosRect.bottom, .001),
          );
        }
        expect(recenter.hitTestable(), findsOneWidget);
        expect(follow.hitTestable(), findsOneWidget);
        expect(followRect.bottom, lessThan(tester.getTopLeft(dock).dy));
        map.navigation.select(
          map.navigation.map.teammate,
          'A long destination label for the terrain survey',
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(header), headerRect);
        expect(tester.getRect(readings), readingsRect);
        expect(find.text('Destination: —'), findsNothing);
        await _mobileTab(tester, 'astronaut');
        expect(actions, findsNothing);
        expect(recenter, findsNothing);
        expect(follow, findsNothing);
        final sheet = find.byKey(const ValueKey('mobile-mission-sheet'));
        expect(_within(sheet, 'EARTH TIME'), findsOneWidget);
        expect(_within(sheet, 'Tegucigalpa · UTC−6'), findsOneWidget);
        for (final label in [
          'PLANETARY CONDITIONS',
          'MARS TIME',
          'TEMP',
          'ELEVATION',
          'START NAVIGATION',
          'RETURN TO BASE',
        ]) {
          expect(_within(sheet, label), findsNothing);
        }
        await _mobileTab(tester, 'crew');
        for (final label in ['MISSION TOOLS', 'SEND PING', 'SOS']) {
          expect(_within(sheet, label), findsNothing);
        }
        await _tapTooltip(tester, 'Close Crew');
        expect(actions, findsOneWidget);
        expect(tester.getRect(readings), readingsRect);
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    },
  );
}

({Rect bounds, int color}) _missionRim(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('mission-route-overlay'));
  final canvas = TestRecordingCanvas();
  tester
      .widget<CustomPaint>(finder)
      .painter!
      .paint(canvas, tester.getSize(finder));
  final stroke = canvas.invocations
      .map((record) => record.invocation)
      .firstWhere(
        (call) =>
            call.memberName == #drawPath &&
            (call.positionalArguments.last as Paint).style ==
                PaintingStyle.stroke,
      );
  return (
    bounds: (stroke.positionalArguments.first as Path).getBounds(),
    color: (stroke.positionalArguments.last as Paint).color.toARGB32(),
  );
}

/// Mounts the dashboard in the existing mission theme.
Future<DemoTerrainMap> _launch(
  WidgetTester tester, {
  Size size = const Size(1366, 1024),
  MarsMission? mission,
  Astronaut astronaut = DemoCrew.dan,
  FakeTrekTiles? tiles,
  DateTime Function()? clock,
  TargetPlatform? platform,
  ConnectPresence? connectPresence,
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: MissionTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MissionDashboard(
        astronaut: astronaut,
        tileSource: tiles ?? FakeTrekTiles(),
        mission: mission ?? marsMissionById['jezero']!,
        clock: clock,
        connectPresence: connectPresence,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return tester.widget<DemoTerrainMap>(find.byType(DemoTerrainMap));
}

/// Changes the spread around a map focal point while both fingers are down.
Future<void> _pinchPhoneMap(
  WidgetTester tester,
  Offset focal,
  double spread,
) async {
  final first = await tester.startGesture(focal - const Offset(45, 0));
  final second = await tester.startGesture(focal + const Offset(45, 0));
  await first.moveBy(Offset(-spread, 0));
  await second.moveBy(Offset(spread, 0));
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

/// Taps a labeled map control and waits for its view to settle.
Future<void> _tapTooltip(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(label));
  await tester.pumpAndSettle();
}

Future<void> _mobileTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('mobile-tab-$name')));
  await tester.pumpAndSettle();
}

Finder _within(Finder surface, String text) =>
    find.descendant(of: surface, matching: find.text(text));

Color? _objectiveColor(WidgetTester tester, Finder objective) =>
    (tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: objective,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration)
        .color;

void _expectExpandedSheet(
  WidgetTester tester,
  Finder sheet, {
  required double safeTop,
}) {
  final rect = tester.getRect(sheet);
  expect(rect.top, inInclusiveRange(safeTop, safeTop + 10));
  final border =
      tester.widget<Material>(sheet).shape! as RoundedRectangleBorder;
  expect(
    border.borderRadius.resolve(TextDirection.ltr),
    const BorderRadius.vertical(top: Radius.circular(23)),
  );
  final dock = tester.getRect(
    find.byKey(const ValueKey('mobile-navigation-dock')),
  );
  expect(rect.bottom, closeTo(dock.top, .001));
  expect(rect.left, dock.left);
  expect(rect.right, dock.right);
  expect(dock.height, 64);
  expect(
    dock.bottom,
    tester.view.physicalSize.height - tester.view.viewPadding.bottom - 10,
  );
}

Future<void> _tapPhoneAction(
  WidgetTester tester,
  Finder action, {
  bool tap = true,
}) async {
  final surface = find.byKey(const ValueKey('mobile-mission-sheet'));
  for (
    var index = 0;
    index < 12 && action.hitTestable().evaluate().isEmpty;
    index++
  ) {
    final region = tester.getRect(surface);
    await tester.dragFrom(
      Offset(region.center.dx, region.bottom - 30),
      const Offset(0, -110),
    );
    await tester.pumpAndSettle();
  }
  expect(action.hitTestable(), findsOneWidget);
  if (tap) await tester.tap(action.hitTestable());
}

/// Models iOS's bridge contract. The tracking code receives only channel maps.
final class _PhoneMotion {
  _PhoneMotion({this.savedPosition, this.savedStride});

  final Offset? savedPosition;
  final double? savedStride;
  final positions = <String, Offset>{};
  bool failPositionWrite = false;
  final origin = DateTime.utc(2026, 11, 15, 14);
  final calls = <MethodCall>[];
  final starts = <double>[];
  final _attitudes = <Map<String, Object?>>[];
  final _samples = <Map<String, Object?>>[];
  DateTime? _now;

  DateTime get now => _now ?? origin;
  double get started => starts.last;

  double _seconds(DateTime value) =>
      value.microsecondsSinceEpoch / Duration.microsecondsPerSecond;

  double _at(double offset) => _seconds(origin) + offset;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'startLocation':
        starts.add(_seconds(now));
        return null;
      case 'restartPedometer':
        starts.add(double.parse(call.arguments as String));
        return null;
      case 'stop':
        _attitudes.clear();
        _samples.clear();
        return null;
      case 'startMotion':
        _attitudes.clear();
        return null;
      case 'readStrideLength':
        return savedStride;
      case 'readMissionPosition':
        final pose = positions[call.arguments] ?? savedPosition;
        return pose == null ? null : [pose.dx, pose.dy];
      case 'writeMissionPosition':
        if (failPositionWrite) throw PlatformException(code: 'storageError');
        final args = call.arguments as Map;
        final mars = (args['mars'] as List).cast<double>();
        positions[args['scope'] as String] = Offset(mars[0], mars[1]);
        return null;
      case 'readMissionChecklist':
        return <String>[];
      case 'snapshot':
        final readings = <String, Object?>{
          'services': false,
          'authorization': 'Denied',
          'orientations': List.of(_attitudes),
          if (starts.isNotEmpty)
            'pedometer': {
              'source': 'coreMotionPedometer',
              'authorization': 'authorized',
              'stepCounting': true,
              'stream': starts.length,
              'started': started,
              'samples': List.of(_samples),
            },
        };
        _attitudes.clear();
        _samples.clear();
        return readings;
      default:
        return null;
    }
  }

  Future<void> poll(
    WidgetTester tester,
    double offset, {
    double? yaw,
    int? steps,
    double? measuredThrough,
    double? streamStart,
  }) async {
    _now = origin.add(
      Duration(microseconds: (offset * Duration.microsecondsPerSecond).round()),
    );
    _attitudes.add({
      'frame': 'Portrait',
      'time': _seconds(now),
      if (yaw != null) 'yaw': yaw,
    });
    if (steps != null) {
      _samples.add({
        'start': streamStart ?? started,
        'end': _at(measuredThrough ?? offset),
        'received': _seconds(now),
        'steps': steps,
      });
    }
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();
  }
}

Future<_PhonePresence> _connectPhoneCrew(
  WidgetTester tester,
  DemoTerrainMap map, {
  Offset? peerMars,
  Offset? oldOwnMars,
}) async {
  final dashboard = tester.widget<MobileNavigation>(
    find.byType(MobileNavigation),
  );
  final session = _PhonePresence(dashboard.presence.clock);
  dashboard.presence.open((key) async {
    session.key = key;
    return session;
  });
  await tester.pump();
  session.update({
    map.teammateId:
        peerMars ??
        map.tracking.coordinates.toMars(map.navigation.map.teammate),
    if (oldOwnMars != null) map.astronautId: oldOwnMars,
  });
  await tester.pumpAndSettle();
  expect(dashboard.presence.status, ConnectionStatus.connected);
  return session;
}

/// Keeps the existing presence publisher active without a Firebase connection.
final class _PhonePresence implements CrewSignalConnection {
  _PhonePresence(this.clock);

  final DateTime Function() clock;
  late SessionKey key;
  final crew = StreamController<PresenceSnapshot>();
  final signals = StreamController<CrewSignals>();
  final pinned = <String, CrewPin>{};
  final pinWrites = <Offset>[];
  final finished = <SosState>[];
  CrewSos? alert;
  Completer<void>? pinGate;
  int started = 0;
  final writes = <AstronautPose>[];
  final offlineWrites = <AstronautPose>[];
  bool closed = false;

  void update(Map<String, Offset> positions) {
    crew.add({
      for (final entry in positions.entries)
        entry.key: (
          pose: (
            mars: entry.value,
            heading: 12,
            mode: TrackingMode.live,
            quality: PositionQuality.accepted,
          ),
          updated: clock(),
          online: true,
        ),
    });
  }

  @override
  Stream<PresenceSnapshot> get snapshots => crew.stream;

  @override
  Future<void> publish(AstronautPose pose, {required bool online}) async {
    (online ? writes : offlineWrites).add(pose);
  }

  void updateSignals() => signals.add((pins: Map.of(pinned), sos: alert));

  @override
  Stream<CrewSignals> get signalSnapshots => signals.stream;

  @override
  Future<void> sendPin(Offset destination) async {
    pinWrites.add(destination);
    await pinGate?.future;
    pinned[key.astronaut] = (mars: destination, updated: clock());
    updateSignals();
  }

  @override
  Future<bool> startSos(Offset mars) async {
    if (alert?.state == SosState.active) return false;
    started++;
    alert = (
      id: 'sender-alert-$started',
      sender: key.astronaut,
      mars: mars,
      started: clock(),
      state: SosState.active,
      finishedBy: null,
    );
    updateSignals();
    return true;
  }

  @override
  Future<bool> finishSos(String eventId, SosState state) async {
    final previous = alert;
    if (previous == null ||
        previous.id != eventId ||
        previous.state != SosState.active) {
      return false;
    }
    finished.add(state);
    alert = (
      id: previous.id,
      sender: previous.sender,
      mars: previous.mars,
      started: previous.started,
      state: state,
      finishedBy: key.astronaut,
    );
    updateSignals();
    return true;
  }

  @override
  void close() {
    closed = true;
    unawaited(crew.close());
    unawaited(signals.close());
  }
}
