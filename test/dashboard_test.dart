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
import 'package:sidera_vi/ui/dashboard/dashboard_style.dart';
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

  testWidgets('Phone camera controls recenter and follow from the same rail', (
    tester,
  ) async {
    final map = await _launch(tester, size: const Size(390, 844));
    final view = map.view;
    final local = find.descendant(
      of: find.byKey(const ValueKey('ARES-01')),
      matching: find.byType(RelativeMarkerArrow),
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('demo-map-viewport')),
    );
    await tester.tap(find.text('Fit area · 500 m radius'));
    await tester.pumpAndSettle();
    final zoom = view.value.getMaxScaleOnAxis();
    await tester.dragFrom(center - const Offset(40, 65), const Offset(-25, 37));
    await tester.pumpAndSettle();
    expect((tester.getCenter(local) - center).distance, greaterThan(10));
    await _tapTooltip(tester, 'Recenter on astronaut');
    expect((tester.getCenter(local) - center).distance, lessThan(.01));
    expect(view.value.getMaxScaleOnAxis(), closeTo(zoom, .001));
    await _tapTooltip(tester, 'Follow astronaut');
    expect(map.tracking.follow, isTrue);
    map.navigation.setTrackedPosition(
      map.navigation.map.landmarks.first.position,
    );
    await tester.pumpAndSettle();
    expect((tester.getCenter(local) - center).distance, lessThan(.01));
    expect(tester.takeException(), isNull);
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
    await map.tracking.selectMode(TrackingMode.live);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('mobile-movement-source')))
          .data,
      'LIVE SENSORS',
    );
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
      mission: marsMissions[1],
    );
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

  testWidgets('Phone actions validate routes and confirm local ping and SOS', (
    tester,
  ) async {
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
    expect(nav.position, nav.map.teammate);
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
    expect(nav.position, nav.map.teammate);
    expect(find.text('Return to habitat base?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.teammate);
    expect(nav.target, nav.map.teammate);
    await _tapTooltip(tester, 'Return to Base');
    await tester.tap(find.text('Return to base'));
    expect(nav.position, nav.map.teammate);
    expect(nav.target, nav.map.base);
    await tester.pumpAndSettle();
    expect(nav.position, nav.map.base);

    nav.select(nav.map.teammate, 'Another destination');
    await tester.pumpAndSettle();
    await _tapTooltip(tester, 'Send Ping');
    expect(find.text('Send Location Ping?'), findsOneWidget);
    expect(
      find.text('Share your current simulated Mars position with your crew?'),
      findsOneWidget,
    );
    final no = find.text('NO');
    final yes = find.text('YES');
    expect(nav.pings, isEmpty);
    await tester.tap(no);
    await tester.pumpAndSettle();
    expect(nav.pings, isEmpty);
    await _tapTooltip(tester, 'Send Ping');
    var notifications = 0;
    nav.addListener(() => notifications++);
    final noButton = find.ancestor(of: no, matching: find.byType(FilledButton));
    final yesButton = find.ancestor(
      of: yes,
      matching: find.byType(FilledButton),
    );
    expect(tester.getSize(noButton), tester.getSize(yesButton));
    expect(tester.getTopLeft(noButton).dy, tester.getTopLeft(yesButton).dy);
    expect(
      tester.getCenter(noButton).dx,
      lessThan(tester.getCenter(yesButton).dx),
    );
    await tester.tap(yes);
    await tester.tap(yes, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(notifications, 1);
    expect(nav.pings.single.type, DemoPingType.location);
    expect(nav.pings.single.position, nav.position);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await _tapTooltip(tester, 'SOS');
    expect(find.text('Activate SOS?'), findsOneWidget);
    expect(
      find.text('Send an emergency alert to your mission crew?'),
      findsOneWidget,
    );
    expect(nav.sos, isFalse);
    await tester.tap(no);
    await tester.pumpAndSettle();
    expect(nav.sos, isFalse);
    await _tapTooltip(tester, 'SOS');
    await tester.tap(yes);
    await tester.tap(yes, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(notifications, 2);
    expect(nav.sos, isTrue);
    expect(nav.paused, isTrue);
    expect(find.text('Demo SOS active'), findsOneWidget);
    await _tapTooltip(tester, 'Cancel demo SOS');
    expect(nav.sos, isFalse);
    expect(tester.takeException(), isNull);
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
        final map = await _launch(tester, size: size, mission: marsMissions[1]);
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
          'Send Ping',
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
          expect(rect.right, closeTo(size.width - 12, .001));
          expect(
            rect.top,
            greaterThan(previous?.bottom ?? readingsRect.bottom),
          );
          expect(rect.bottom, lessThan(tester.getTopLeft(dock).dy));
          expect(
            rect.overlaps(tester.getRect(find.byTooltip('Follow astronaut'))),
            isFalse,
          );
          previous = rect;
        }
        final recenter = find.byTooltip('Recenter on astronaut');
        final follow = find.byTooltip('Follow astronaut');
        expect(recenter, findsOneWidget);
        expect(follow, findsOneWidget);
        final sosRect = tester.getRect(
          find.byKey(const ValueKey('mobile-action-sos')),
        );
        final recenterRect = tester.getRect(recenter);
        final followRect = tester.getRect(follow);
        expect(recenterRect.center.dx, closeTo(sosRect.center.dx, .001));
        expect(followRect.center.dx, closeTo(sosRect.center.dx, .001));
        expect(recenterRect.top, greaterThan(sosRect.bottom));
        expect(followRect.top, greaterThan(recenterRect.bottom));
        expect(
          followRect.top - recenterRect.bottom,
          closeTo(recenterRect.top - sosRect.bottom, .001),
        );
        if (size.height > 600) {
          expect(recenter.hitTestable(), findsOneWidget);
          expect(follow.hitTestable(), findsOneWidget);
          expect(followRect.bottom, lessThan(tester.getTopLeft(dock).dy));
        }
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

/// Mounts the dashboard in the existing mission theme.
Future<DemoTerrainMap> _launch(
  WidgetTester tester, {
  Size size = const Size(1366, 1024),
  MarsMission? mission,
  Astronaut astronaut = DemoCrew.dan,
  FakeTrekTiles? tiles,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: MissionTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MissionDashboard(
        astronaut: astronaut,
        tileSource: tiles ?? FakeTrekTiles(),
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
