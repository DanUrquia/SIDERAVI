import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/auth/mission_session.dart';
import 'package:sidera_vi/auth/prototype_auth.dart';
import 'package:sidera_vi/mission_app.dart';
import 'package:sidera_vi/ui/mission_login.dart';

/// Exercises the Phase 1 flow through the same controls as the iPad.
void main() {
  for (final (pin, name) in [
    ('0107', 'Dan Urquía'),
    ('1412', 'Adrian Flowers'),
  ]) {
    testWidgets('Recognizes $name and completes the mission welcome', (
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
      await tester.pumpAndSettle();
      expect(find.text('MISSION INTERFACE READY'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );

      await tester.tap(find.text('RETURN TO LOGIN'));
      await tester.pumpAndSettle();
      expect(find.text('ENTER MISSION PIN'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );
      expect(_submitButton(tester).onPressed, isNull);

      await _enterDigits(tester, pin);
      await tester.tap(find.text('ENTER MISSION'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Welcome Astronaut $name'), findsOneWidget);
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
    expect(
      find.bySemanticsLabel('Welcome Astronaut Dan Urquía'),
      findsOneWidget,
    );
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
    expect(find.text('MISSION INTERFACE READY'), findsOneWidget);
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
    expect(find.text('RETURN TO LOGIN').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Stores exactly one authenticated identity until session end', () {
    const auth = PrototypeAuth();
    expect(auth.authenticate('107'), isNull);
    expect(auth.authenticate('01070'), isNull);
    final dan = auth.authenticate('0107')!;
    final adrian = auth.authenticate('1412')!;
    expect(dan.id, 'ARES-01');
    expect(adrian.id, 'ARES-02');

    final session = MissionSession();
    addTearDown(session.dispose);
    expect(session.begin(dan), isTrue);
    expect(session.begin(adrian), isFalse);
    expect(session.astronaut, same(dan));
    session.end();
    expect(session.astronaut, isNull);
    expect(session.begin(adrian), isTrue);
  });
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
  await tester.pumpWidget(const MissionApp());
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
