import 'package:flutter_test/flutter_test.dart';
import 'package:sidera_vi/tracking/pedometer_monitor.dart';
import 'package:sidera_vi/tracking/step_navigation.dart';

PedometerObservation _steps({
  required double start,
  required double end,
  required int count,
  double? distance,
}) => (
  start: start,
  intervalStart: start,
  end: end,
  received: end + 5,
  steps: count,
  distance: distance,
  cadence: null,
  incrementalSteps: count,
  incrementalDistance: distance,
  decision: 'observed',
  source: 'coreMotionPedometer',
);

void main() {
  test('A delayed batch uses the calibrated heading at its endpoint', () {
    final navigation = StepNavigation()
      ..calibrate(100, 179, 359)
      ..observe(101, -179)
      ..observe(102, -89)
      ..observe(106, -89);
    expect(navigation.bearingAt(101), closeTo(1, .0001));
    expect(navigation.bearingAt(106), closeTo(91, .0001));
    final first = navigation.displacement(
      _steps(start: 100, end: 101, count: 10),
    )!;
    expect(first.distance, closeTo(7, .0001));
    expect(first.dy, greaterThan(6.99));
    final turned = navigation.displacement(
      _steps(start: 101, end: 102, count: 5),
    )!;
    expect(turned.dx, greaterThan(3.49));
    expect(navigation.bearingAt(105), isNull);
  });

  test(
    'A batch crossing calibration or missing a valid heading cannot move',
    () {
      final navigation = StepNavigation();
      final oldBatch = _steps(start: 98, end: 101, count: 5);
      expect(navigation.displacement(oldBatch), isNull);
      navigation
        ..calibrate(100, 0, 45)
        ..observe(101, null);
      expect(navigation.displacement(oldBatch), isNull);
      expect(
        navigation.displacement(_steps(start: 100, end: 101, count: 3)),
        isNull,
      );
      navigation.observe(102, 0);
      expect(
        navigation.displacement(_steps(start: 101, end: 102, count: 0)),
        isNull,
      );
      expect(
        navigation.displacement(_steps(start: 101, end: 106, count: 3)),
        isNull,
      );
      navigation.invalidate();
      expect(
        navigation.displacement(_steps(start: 101, end: 102, count: 3)),
        isNull,
      );
    },
  );

  test('A plausible native interval replaces the saved stride estimate', () {
    final navigation = StepNavigation()
      ..stride = .8
      ..calibrate(100, 0, 90);
    final estimated = navigation.displacement(
      _steps(start: 100, end: 101, count: 5),
    )!;
    final native = navigation.displacement(
      _steps(start: 100, end: 101, count: 5, distance: 3),
    )!;
    final implausible = navigation.displacement(
      _steps(start: 100, end: 101, count: 5, distance: 30),
    )!;
    expect(estimated.dx, closeTo(4, .0001));
    expect(native.dx, closeTo(3, .0001));
    expect(implausible.dx, closeTo(4, .0001));
  });
}
