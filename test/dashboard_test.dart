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
import 'package:sidera_vi/tracking/mission_presence.dart';
import 'package:sidera_vi/tracking/astronaut_tracking.dart';
import 'package:sidera_vi/tracking/tracking_geometry.dart';
import 'package:sidera_vi/sensors/sensor_service.dart';
import 'package:sidera_vi/ui/dashboard/demo_terrain_map.dart';
import 'package:sidera_vi/ui/dashboard/mission_dashboard.dart';
import 'package:sidera_vi/ui/mission_theme.dart';

import 'fake_trek_tiles.dart';

/// Exercises native dashboard interactions in a landscape iPad viewport.
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
      const radii = [500, 650, 750, 850, 1000];
      const heights = [-2652, -2606, -1783, -1934, -3874];
      for (final (index, mission) in marsMissions.indexed) {
        expect(mission.objectives, hasLength(3));
        for (final objective in mission.objectives) {
          expect(objective.id, matches(r'^[a-z]+(?:-[a-z]+)*$'));
          expect(ids.add(objective.id), isTrue);
        }
        final map = missionMaps[mission.id]!;
        expect(map.radiusMeters, radii[index]);
        expect(map.radiusMeters, mission.radiusMeters);
        expect(mission.elevation?.meters, heights[index]);
        expect(mission.elevationLabel, '−${heights[index].abs()} m');
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
            closeTo(radii[index], .0001),
          );
          expect(map.contains(point), isTrue);
        }
        for (final offset in [
          Offset(radii[index] + 1.0, 0),
          Offset(0, -radii[index] - 1.0),
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
      final mission = marsMissions.first;
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
    final mission = marsMissions.first;
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
    final openHeight = tester.getSize(surface).height;
    await _tapTooltip(tester, 'Expand or collapse Missions');
    expect(tester.getSize(surface).height, greaterThan(openHeight));
    await _tapTooltip(tester, 'Expand or collapse Missions');
    expect(tester.getSize(surface).height, lessThan(openHeight));

    await _mobileTab(tester, 'astronaut');
    expect(surface, findsOneWidget);
    expect(find.byTooltip('Close Missions'), findsNothing);
    expect(find.text('Total steps'), findsOneWidget);
    await _mobileTab(tester, 'crew');
    expect(surface, findsOneWidget);
    expect(find.byTooltip('Close Astronaut'), findsNothing);
    expect(find.text('Adrian Flores'), findsOneWidget);
    await _mobileTab(tester, 'crew');
    expect(surface, findsNothing);
    expect(map.view.value, pinched);

    await _mobileTab(tester, 'missions');
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(75, 33),
      const Offset(0, 470),
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
    await _tapTooltip(tester, 'Expand or collapse Missions');
    final survey = find.byKey(const ValueKey('objective-ancient-liquid-water'));
    expect(tester.widget<CheckboxListTile>(survey).value, isFalse);
    await tester.tap(survey);
    await tester.pumpAndSettle();
    expect(completed, ['ancient-liquid-water']);
    final sheet = find.byKey(const ValueKey('mobile-mission-sheet'));
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Delta outcrop')),
    );
    await tester.pumpAndSettle();
    expect(map.navigation.targetLabel, 'Delta outcrop');
    expect(sheet, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _launch(tester, size: const Size(390, 844));
    await _mobileTab(tester, 'missions');
    expect(tester.widget<CheckboxListTile>(survey).value, isTrue);
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
          await _tapTooltip(tester, 'Expand or collapse Missions');
          expect(find.text('0 of 3 complete · On this device'), findsOneWidget);
          for (final objective in mission.objectives) {
            final tile = find.byKey(ValueKey('objective-${objective.id}'));
            expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
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

  testWidgets('Compact phone keeps pause, return and crew emergency actions', (
    tester,
  ) async {
    final map = await _launch(tester, size: const Size(320, 568));
    final nav = map.navigation;
    nav.select(nav.map.teammate, 'Survey route');
    nav.start(instant: true);
    await tester.pumpAndSettle();
    await _mobileTab(tester, 'astronaut');
    await _tapTooltip(tester, 'Expand or collapse Astronaut');
    final pause = find.text('PAUSE MISSION');
    await _tapPhoneAction(tester, pause);
    await tester.pumpAndSettle();
    expect(nav.paused, isTrue);
    await tester.tap(find.text('RESUME MISSION'));
    await tester.pumpAndSettle();
    expect(nav.paused, isFalse);

    final returnToBase = find.text('RETURN TO BASE');
    await _tapPhoneAction(tester, returnToBase);
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.teammate);
    expect(find.text('Return to habitat base?'), findsOneWidget);
    await tester.tap(find.text('Return to base'));
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.base);

    await _mobileTab(tester, 'crew');
    await _tapTooltip(tester, 'Expand or collapse Crew');
    final ping = find.text('SEND PING');
    await _tapPhoneAction(tester, ping);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location Ping'));
    await tester.pumpAndSettle();
    expect(nav.pings.single.type, DemoPingType.location);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final sos = find.text('SOS');
    await _tapPhoneAction(tester, sos);
    await tester.pumpAndSettle();
    expect(nav.sos, isFalse);
    await tester.tap(find.text('ACTIVATE DEMO SOS'));
    await tester.pumpAndSettle();
    expect(nav.sos, isTrue);
    expect(nav.paused, isTrue);
    expect(find.text('Demo SOS active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Mounts the dashboard in the existing mission theme.
Future<DemoTerrainMap> _launch(
  WidgetTester tester, {
  Size size = const Size(1366, 1024),
  MarsMission? mission,
  Astronaut astronaut = DemoCrew.dan,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: MissionTheme.dark,
      home: MissionDashboard(
        astronaut: astronaut,
        tileSource: FakeTrekTiles(),
        mission: mission ?? marsMissions.first,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<DemoTerrainMap>(find.byType(DemoTerrainMap));
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

Future<void> _tapPhoneAction(WidgetTester tester, Finder action) async {
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
  await tester.tap(action.hitTestable());
}
