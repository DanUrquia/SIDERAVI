import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/mission_session.dart';
import 'package:sidera_vi/auth/prototype_auth.dart';
import 'package:sidera_vi/dashboard/demo_navigation.dart';
import 'package:sidera_vi/mission_app.dart';
import 'package:sidera_vi/missions/mission.dart';
import 'package:sidera_vi/missions/mission_catalog.dart';
import 'package:sidera_vi/ui/mission_login.dart';
import 'package:sidera_vi/ui/dashboard/trek_tile_view.dart';
import 'package:sidera_vi/ui/dashboard/demo_terrain_map.dart';
import 'package:sidera_vi/ui/dashboard/mission_dashboard.dart';
import 'package:sidera_vi/ui/missions/mission_photo_panel.dart';

import 'fake_trek_tiles.dart';

/// Exercises the Phase 1 flow through the same controls as the iPad.
void main() {
  for (final (pin, name, id, initials) in [
    ('0107', 'Dan Urquía', 'ARES-01', 'DU'),
    ('1412', 'Adrian Flores', 'ARES-02', 'AF'),
  ]) {
    testWidgets('Recognizes $name and opens Mission Selection after welcome', (
      tester,
    ) async {
      await _openLogin(tester);
      await _enterDigits(tester, pin);
      await _enterDigits(tester, '9');

      expect(find.byType(MissionLogin), findsOneWidget);
      expect(_submitButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('ENTER MISSION'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('ENTER MISSION PIN').hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('Welcome Astronaut $name'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.bySemanticsLabel('Welcome Astronaut $name'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Simulated dashboard initialization')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 1300));
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, inExclusiveRange(0, 1));
      expect(
        find.text('Loading and calibrating your dashboard.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('MISSION INTERFACE READY'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('MISSION INTERFACE READY'), findsOneWidget);
      expect(find.text('SELECT MISSION'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );

      await tester.pumpAndSettle();
      expect(find.text('SELECT MISSION'), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(find.text(id), findsOneWidget);
      expect(find.text(initials), findsOneWidget);
      expect(find.text('Jezero Crater'), findsOneWidget);
      expect(find.bySemanticsLabel('Welcome Astronaut $name'), findsNothing);

      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();
      expect(find.text('ENTER MISSION PIN'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );
      expect(_submitButton(tester).onPressed, isNull);

      await _signIn(tester, pin);
      expect(find.text(name), findsOneWidget);
    });
  }

  testWidgets('Keeps PIN entry masked and supports backspace and clear', (
    tester,
  ) async {
    await _openLogin(tester);
    expect(find.byType(EditableText), findsNothing);
    await _enterDigits(tester, '010');
    expect(find.bySemanticsLabel('3 of 4 PIN digits entered'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
    await _enterDigits(tester, '7');
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(find.bySemanticsLabel('3 of 4 PIN digits entered'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
    await tester.tap(find.text('CLEAR'));
    await tester.pump();
    expect(find.bySemanticsLabel('0 of 4 PIN digits entered'), findsOneWidget);
  });

  testWidgets('Rejects invalid PINs and resets for the next attempt', (
    tester,
  ) async {
    await _openLogin(tester);
    await _enterDigits(tester, '9999');
    await tester.tap(find.text('ENTER MISSION'));
    await tester.pump();
    expect(find.text('ACCESS DENIED — INVALID PIN'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 4 PIN digits entered'), findsOneWidget);
    expect(find.byType(MissionLogin), findsOneWidget);

    await _enterDigits(tester, '9999');
    await tester.tap(find.text('ENTER MISSION'));
    await tester.pump();
    await _enterDigits(tester, '0107');
    expect(find.text('ACCESS DENIED — INVALID PIN'), findsNothing);
    await tester.tap(find.text('ENTER MISSION'));
    await tester.pumpAndSettle();
    expect(find.text('Dan Urquía'), findsOneWidget);
  });

  testWidgets('Reduced motion makes the completion state available at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _openLogin(tester, size: const Size(1024, 480));
    await _enterDigits(tester, '1412');
    await tester.tap(find.text('ENTER MISSION'));
    await tester.pump();
    await tester.pump();
    expect(find.text('SELECT MISSION'), findsOneWidget);
    expect(find.text('Adrian Flores'), findsOneWidget);
    expect(find.text('START MISSION').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fits the iPad viewport with increased text size', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _openLogin(tester, size: const Size(1024, 768));
    expect(tester.takeException(), isNull);
    final key = find.widgetWithText(FilledButton, '1');
    final submit = find.widgetWithText(FilledButton, 'ENTER MISSION');
    expect(tester.getSize(key).height, greaterThan(60));
    expect(tester.getSize(key).height, tester.getSize(submit).height);
    await _enterDigits(tester, '1412');
    await tester.tap(find.text('ENTER MISSION'));
    await tester.pumpAndSettle();
    expect(find.text('START MISSION').hitTestable(), findsOneWidget);
  });

  test('Stores exactly one authenticated identity until session end', () {
    const auth = PrototypeAuth();
    expect(auth.authenticate('107'), isNull);
    expect(auth.authenticate('01070'), isNull);
    final dan = auth.authenticate('0107')!;
    final adrian = auth.authenticate('1412')!;
    expect(dan.id, 'ARES-01');
    expect(adrian.id, 'ARES-02');
    expect(adrian.fullName, 'Adrian Flores');

    final session = MissionSession();
    addTearDown(session.dispose);
    expect(session.begin(dan), isTrue);
    expect(session.begin(adrian), isFalse);
    expect(session.astronaut, same(dan));
    session.selectMission(marsMissions.last);
    expect(session.mission, same(marsMissions.last));
    session.end();
    expect(session.astronaut, isNull);
    expect(session.mission, isNull);
    session.selectMission(marsMissions.first);
    expect(session.mission, isNull);
    expect(session.begin(adrian), isTrue);
  });

  test('The catalog has five distinct missions, images, and difficulties', () {
    expect(marsMissions.map((mission) => mission.id).toSet(), hasLength(5));
    expect(
      marsMissions.map((mission) => mission.imagery.asset).toSet(),
      hasLength(5),
    );
    expect(
      marsMissions.map((mission) => mission.difficulty).toSet(),
      MissionDifficulty.values.toSet(),
    );
  });

  testWidgets(
    'Arrows and swipes update image and briefing together within the catalog',
    (tester) async {
      await _openLogin(tester);
      await _signIn(tester, '0107');
      final previous = find.byTooltip('Previous mission');
      final next = find.byTooltip('Next mission');
      final photo = find.byType(MissionPhotoPanel);
      _expectMission(0);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      _expectMission(0);

      await tester.tap(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      _expectMission(1);

      await tester.fling(photo, const Offset(-240, 0), 600);
      await tester.pumpAndSettle();
      _expectMission(2);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      _expectMission(1);
      for (var index = 2; index < 5; index++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
        _expectMission(index);
      }
      await tester.tap(next);
      await tester.pumpAndSettle();
      _expectMission(4);
      await tester.fling(photo, const Offset(-240, 0), 600);
      await tester.pumpAndSettle();
      _expectMission(4);
      await tester.fling(photo, const Offset(240, 0), 600);
      await tester.pumpAndSettle();
      _expectMission(3);
    },
  );

  testWidgets('Every briefing can start its mission', (tester) async {
    await _openLogin(tester);
    await _signIn(tester, '1412');
    for (final mission in marsMissions) {
      await tester.tap(find.text('START MISSION'));
      await tester.pumpAndSettle();
      final dashboard = tester.widget<MissionDashboard>(
        find.byType(MissionDashboard),
      );
      expect(dashboard.mission, same(mission));
      final terrain = tester.widget<TrekTileView>(find.byType(TrekTileView));
      expect(terrain.scene.center.dy, mission.coordinates.latitude);
      expect(
        terrain.scene.center.dx,
        closeTo((mission.coordinates.eastLongitude + 180) % 360 - 180, .000001),
      );
      expect(
        find.textContaining('Map imagery: NASA Mars Trek'),
        findsOneWidget,
      );
      final demo = tester
          .widget<DemoTerrainMap>(find.byType(DemoTerrainMap))
          .navigation;
      expect(demo.position, demo.map.base);
      expect(demo.target, isNull);
      expect(demo.pings, isEmpty);
      await tester.tap(find.text('BACK TO MISSIONS'));
      await tester.pumpAndSettle();
      expect(find.text(mission.title), findsOneWidget);
      if (mission != marsMissions.last) {
        await tester.tap(find.byTooltip('Next mission'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets(
    'The dashboard preserves selection and logout resets it for another astronaut',
    (tester) async {
      await _openLogin(tester);
      await _signIn(tester, '0107');
      await tester.tap(find.byTooltip('Next mission'));
      await tester.pumpAndSettle();
      _expectMission(1);

      await tester.tap(find.text('START MISSION'));
      await tester.pumpAndSettle();
      expect(find.text('Gale Crater'), findsOneWidget);
      expect(find.text('Dan Urquía — ARES-01'), findsOneWidget);
      final firstMap = tester.widget<DemoTerrainMap>(
        find.byType(DemoTerrainMap),
      );
      firstMap.navigation.addPing(DemoPingType.item);
      await tester.pump();

      await tester.tap(find.text('BACK TO MISSIONS'));
      await tester.pumpAndSettle();
      _expectMission(1);
      expect(find.text('Dan Urquía'), findsOneWidget);
      expect(find.text('Welcome Astronaut'), findsNothing);

      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();
      await _signIn(tester, '1412');
      _expectMission(0);
      expect(find.text('Adrian Flores'), findsOneWidget);
      expect(find.text('ARES-02'), findsOneWidget);
      expect(find.text('Dan Urquía'), findsNothing);

      await tester.tap(find.text('START MISSION'));
      await tester.pumpAndSettle();
      expect(find.text('Adrian Flores — ARES-02'), findsOneWidget);
      expect(find.text('Jezero Crater'), findsOneWidget);
      final secondMap = tester.widget<DemoTerrainMap>(
        find.byType(DemoTerrainMap),
      );
      expect(secondMap.navigation.pings, isEmpty);
      expect(secondMap.navigation.position, secondMap.navigation.map.base);
    },
  );
}

/// Signs in through the keypad and lets the mission selector appear.
Future<void> _signIn(WidgetTester tester, String pin) async {
  await _enterDigits(tester, pin);
  await tester.tap(find.text('ENTER MISSION'));
  await tester.pumpAndSettle();
}

/// Verifies the selected mission's index, briefing, and attributed photo.
void _expectMission(int index) {
  final mission = marsMissions[index];
  expect(find.text(mission.title), findsOneWidget);
  expect(find.text(mission.objective), findsOneWidget);
  expect(find.text(mission.imagery.credit), findsOneWidget);
  expect(find.byKey(ValueKey(mission.imagery.asset)), findsOneWidget);
  expect(find.text('0${index + 1} / 05'), findsOneWidget);
}

/// Opens the app using an iPad-size logical viewport.
Future<void> _openLogin(
  WidgetTester tester, {
  Size size = const Size(1366, 1024),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MissionApp(tileSource: FakeTrekTiles()));
}

/// Enters digits solely through the on-screen keypad.
Future<void> _enterDigits(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

/// Looks up the submit control to validate its enabled state.
FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'ENTER MISSION'),
);
