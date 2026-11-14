import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/astronaut.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/dashboard/mission_map_config.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
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

  test('The local grid measures distance and heading consistently', () {
    final config = missionMaps['jezero']!;
    final nav = DemoNavigation(config);
    addTearDown(nav.dispose);
    expect(nav.select(Offset.zero, 'Outside'), isFalse);
    expect(nav.target, isNull);
    final north = config.start + const Offset(0, -.1);
    expect(nav.select(north, 'North test'), isTrue);
    expect(nav.distanceTo(north), closeTo(270, .001));
    expect(nav.heading, 0);
    final east = config.start + const Offset(.1, 0);
    expect(nav.select(east, 'East test'), isTrue);
    expect(nav.heading, 90);
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
    final valid = map.navigation.map.base + const Offset(.1, .04);
    final scene = world.topLeft + valid * side;
    await tester.tapAt(
      rect.topLeft + MatrixUtils.transformPoint(map.view.value, scene),
    );
    await tester.pumpAndSettle();
    expect(map.navigation.target?.dx, closeTo(valid.dx, .01));
    expect(map.navigation.target?.dy, closeTo(valid.dy, .01));
    await _tapTooltip(tester, 'Zoom out');
    expect(map.view.value.getMaxScaleOnAxis(), closeTo(1, .001));

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
      await _tapTooltip(tester, 'Zoom in');
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
          find.text('Warning marker placed on this iPad.'),
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
}

/// Mounts the dashboard in the existing mission theme.
Future<DemoTerrainMap> _launch(
  WidgetTester tester, {
  Size size = const Size(1366, 1024),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: MissionTheme.dark,
      home: MissionDashboard(
        astronaut: DemoCrew.dan,
        tileSource: FakeTrekTiles(),
        mission: marsMissions.first,
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
