import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sensors/sensor_measurements.dart';
import '../../sensors/sensor_service.dart';
import '../../sensors/sensor_test_controller.dart';
import '../dashboard/dashboard_style.dart';

/// Displays Earth sensor feasibility readings without touching the Mars session.
class SensorTestScreen extends StatefulWidget {
  /// Allows an alternate service during tests.
  const SensorTestScreen({
    super.key,
    this.service = const NativeSensorService(),
  });

  final SensorService service;

  @override
  State<SensorTestScreen> createState() => _SensorTestScreenState();
}

/// Limits collection to the diagnostic route and foreground app lifecycle.
class _SensorTestScreenState extends State<SensorTestScreen>
    with WidgetsBindingObserver {
  late final SensorTestController _test;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _test = SensorTestController(widget.service)..observe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_test.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _test.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('SENSOR TEST'),
      leadingWidth: 235,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: DashboardButton(
          label: 'BACK TO DASHBOARD',
          icon: Icons.chevron_left,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    ),
    backgroundColor: DashboardStyle.background,
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: _test,
        builder: (context, _) {
          final m = _test.measurements;
          final data = m.capabilities;
          final now = _test.running ? _test.clock() : m.ended ?? _test.clock();
          final seconds = now.millisecondsSinceEpoch / 1000;
          final fix = m.latestLocation;
          final orientation = m.latestOrientation;
          final fixTime = SensorMeasurements.reading(fix, 'time');
          final orientationTime = SensorMeasurements.reading(
            orientation,
            'time',
          );
          final accuracy = SensorMeasurements.reading(fix, 'accuracy');
          final yaw = orientationTime != null && seconds - orientationTime <= 2
              ? m.relativeYaw
              : null;
          final freshFix =
              fixTime != null &&
              seconds - fixTime <= SensorMeasurements.maxLocationAge;
          final course = SensorMeasurements.reading(fix, 'course');
          final courseAccuracy = SensorMeasurements.reading(
            fix,
            'courseAccuracy',
          );
          final speed = SensorMeasurements.reading(fix, 'speed');
          final speedAccuracy = SensorMeasurements.reading(
            fix,
            'speedAccuracy',
          );
          final showSpeed = freshFix && speed != null && speed >= 0;
          final showCourse =
              showSpeed &&
              speedAccuracy != null &&
              speed > speedAccuracy &&
              course != null &&
              courseAccuracy != null &&
              courseAccuracy <= 30;
          final heading = data['heading'];
          final authorization = data['authorization'];
          final quality = _quality(
            fixFresh: freshFix,
            accuracy: accuracy,
            precise: data['precise'] == true,
            consistentMotion:
                yaw != null &&
                SensorMeasurements.motionIsConsistent(m.orientations),
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _Panel('Earth location', [
                  _Metric(
                    'Latitude',
                    freshFix ? _number(fix?['latitude'], '', 6) : 'Unavailable',
                  ),
                  _Metric(
                    'Longitude',
                    freshFix
                        ? _number(fix?['longitude'], '', 6)
                        : 'Unavailable',
                  ),
                  _Metric('Horizontal accuracy', _number(accuracy, ' m')),
                  _Metric('Last fix (UTC)', _timestamp(fixTime)),
                  _Metric(
                    m.ended != null ? 'Age at stop' : 'Age',
                    _age(seconds, fixTime),
                  ),
                  _Metric(
                    'Authorization',
                    authorization?.toString() ?? 'Unavailable',
                  ),
                  _Metric(
                    'Precise location',
                    authorization == 'Authorized'
                        ? _availability(data['precise'])
                        : 'Unavailable',
                  ),
                  _Metric('Location Services', _availability(data['services'])),
                  _Metric('Received updates', '${m.received}'),
                ]),
                _Panel('Physical movement', [
                  _Metric(
                    'Displacement from start',
                    m.observedDisplacement == null
                        ? 'Unavailable'
                        : m.displacement == null
                        ? 'Inconclusive'
                        : _number(m.displacement, ' m'),
                  ),
                  _Metric(
                    'Observed / uncertainty',
                    '${_number(m.observedDisplacement, ' m')} / ${_number(m.uncertainty, ' m')}',
                  ),
                  _Metric(
                    'Last accepted segment',
                    _number(m.lastSegment, ' m'),
                  ),
                  _Metric(
                    'Latest candidate step',
                    m.observedDisplacement == null
                        ? 'Unavailable'
                        : m.lastStep == null
                        ? 'Inconclusive'
                        : _number(m.lastStep, ' m'),
                  ),
                  _Metric(
                    'Accepted path',
                    m.accepted == 0 ? 'Unavailable' : _number(m.path, ' m'),
                  ),
                  _Metric(
                    'Accepted / rejected',
                    '${m.accepted} / ${m.rejected}',
                  ),
                  _Metric(
                    'Estimated speed',
                    showSpeed ? _number(speed, ' m/s', 1) : 'Unavailable',
                  ),
                  _Metric(
                    'Speed uncertainty',
                    showSpeed
                        ? _number(speedAccuracy, ' m/s', 1)
                        : 'Unavailable',
                  ),
                  _Metric(
                    'Direction of travel',
                    showCourse ? _number(course, '° true') : 'Unavailable',
                  ),
                  _Metric('Last movement (UTC)', _timestamp(m.lastMovementAt)),
                ]),
                _Panel('Device orientation', [
                  Center(child: _HeadingArrow(degrees: yaw)),
                  _Metric('Relative heading', _number(yaw, '°')),
                  _Metric(
                    'Device pitch / roll',
                    '${_number(orientation?['pitch'], '°')} / ${_number(orientation?['roll'], '°')}',
                  ),
                  _Metric(
                    'Angular rotation',
                    _number(orientation?['rotationRate'], '°/s', 1),
                  ),
                  _Metric(
                    'Motion / gyro',
                    '${_availability(data['motion'])} / ${_availability(data['gyro'])}',
                  ),
                  _Metric(
                    'Accelerometer / magnetometer',
                    '${_availability(data['accelerometer'])} / ${_availability(data['magnetometer'])}',
                  ),
                  _Metric('Compass API', _availability(data['compass'])),
                  _Metric(
                    'Reference',
                    data['motion'] == true
                        ? 'Relative screen top · ${orientation?['frame'] ?? 'Awaiting sample'}'
                        : 'Unavailable',
                  ),
                  _Metric(
                    m.ended != null ? 'Age at stop' : 'Age',
                    _age(seconds, orientationTime),
                  ),
                  Text(
                    heading == null
                        ? 'Absolute heading unavailable — relative orientation only'
                        : 'Absolute device heading ${_number(heading, '° true')} · uncertainty ${_number(data['headingAccuracy'], '°')}',
                  ),
                ]),
                _Panel('Sensor quality', [
                  Text(
                    quality,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: DashboardStyle.warm,
                    ),
                  ),
                  _Metric(
                    'Test',
                    _test.running
                        ? 'Collecting'
                        : m.ended != null
                        ? 'Stopped'
                        : 'Ready',
                  ),
                  _Metric(
                    'Location update rate',
                    _number(
                      SensorMeasurements.frequency(m.rawLocations),
                      ' Hz',
                      2,
                    ),
                  ),
                  _Metric(
                    'Motion update rate',
                    _number(
                      SensorMeasurements.frequency(m.orientations),
                      ' Hz',
                      1,
                    ),
                  ),
                  _Metric('Location sample delay', _delay(fix)),
                  _Metric('Motion sample delay', _delay(orientation)),
                  _Metric('Orientation updates', '${m.orientationCount}'),
                  _Metric(
                    'Peak observed displacement',
                    m.accepted == 0
                        ? 'Unavailable'
                        : _number(m.maxObservedDisplacement, ' m'),
                  ),
                  _Metric(
                    'Within-noise drift',
                    m.accepted == 0 ? 'Unavailable' : _number(m.drift, ' m'),
                  ),
                ]),
              ];
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    const Text(
                      'Earth sensor readings stay on this device unless you export a report.',
                    ),
                    if (_test.error case final error?)
                      Text(
                        error,
                        style: const TextStyle(color: DashboardStyle.amber),
                      ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        DashboardButton(
                          label: 'START TEST',
                          icon: Icons.play_arrow,
                          primary: true,
                          onPressed: _test.running || _test.busy
                              ? null
                              : _test.start,
                        ),
                        DashboardButton(
                          label: 'STOP TEST',
                          icon: Icons.stop,
                          onPressed: !_test.running || _test.busy
                              ? null
                              : _test.stop,
                        ),
                        DashboardButton(
                          label: 'CALIBRATE ORIENTATION',
                          icon: Icons.explore_outlined,
                          onPressed: !_test.running || _test.busy
                              ? null
                              : _test.calibrate,
                        ),
                        DashboardButton(
                          label: 'RESET MEASUREMENTS',
                          icon: Icons.refresh,
                          onPressed: _test.busy ? null : _test.reset,
                        ),
                        DashboardButton(
                          label: 'EXPORT TEST REPORT',
                          icon: Icons.ios_share,
                          onPressed:
                              !_test.running && m.ended != null && !_test.busy
                              ? _test.export
                              : null,
                        ),
                      ],
                    ),
                    if (constraints.maxWidth >= 720)
                      for (var i = 0; i < cards.length; i += 2)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Expanded(child: cards[i]),
                            Expanded(child: cards[i + 1]),
                          ],
                        )
                    else
                      ...cards,
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

/// Explains quality using recent fixes and motion delivery.
String _quality({
  required bool fixFresh,
  required double? accuracy,
  required bool precise,
  required bool consistentMotion,
}) {
  if (!fixFresh && !consistentMotion) return 'Unavailable · No fresh readings';
  if (fixFresh &&
      precise &&
      accuracy != null &&
      accuracy <= 15 &&
      consistentMotion) {
    return 'Good · Fresh fixes and consistent motion samples';
  }
  if (!fixFresh) {
    return 'Limited · Motion available, Earth fix missing or stale';
  }
  if (!precise || accuracy == null || accuracy > 15) {
    return 'Limited · Earth location is approximate';
  }
  return 'Limited · Relative heading is missing or motion delivery is sparse';
}

/// Formats finite sensor values with a unit.
String _number(Object? value, String suffix, [int decimals = 0]) =>
    value is num && value.isFinite
    ? '${value.toStringAsFixed(decimals)}$suffix'
    : 'Unavailable';

/// Describes whether the API reports a capability.
String _availability(Object? available) =>
    available == true ? 'Available' : 'Unavailable';

/// Displays sample time in UTC, independent of the host time zone.
String _timestamp(double? time) => time == null
    ? 'Unavailable'
    : DateTime.fromMillisecondsSinceEpoch(
        (time * 1000).round(),
        isUtc: true,
      ).toIso8601String();

/// Reports the age of a recorded fix or device attitude.
String _age(double now, double? time) =>
    time == null ? 'Unavailable' : _number(math.max(0, now - time), ' s', 1);

/// Estimates callback delay from the sample and receipt timestamps.
String _delay(Sample? sample) {
  final time = SensorMeasurements.reading(sample, 'time');
  final received = SensorMeasurements.reading(sample, 'received');
  return received == null || time == null || received < time
      ? 'Unavailable'
      : _number(received - time, ' s', 2);
}

/// Rotates through the shortest arc at the ±180° boundary.
class _HeadingArrow extends StatefulWidget {
  const _HeadingArrow({required this.degrees});
  final double? degrees;

  @override
  State<_HeadingArrow> createState() => _HeadingArrowState();
}

/// Keeps an unwrapped angle for smooth implicit animation.
class _HeadingArrowState extends State<_HeadingArrow> {
  double _angle = 0;

  @override
  void initState() {
    super.initState();
    _angle = widget.degrees ?? 0;
  }

  @override
  void didUpdateWidget(_HeadingArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.degrees;
    if (next != null) _angle += signedTurn(next - _angle);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.degrees == null
        ? 'Relative heading unavailable'
        : 'Relative orientation arrow',
    child: AnimatedRotation(
      turns: _angle / 360,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: Icon(
        Icons.navigation,
        size: 76,
        color: widget.degrees == null
            ? DashboardStyle.muted
            : DashboardStyle.warm,
      ),
    ),
  );
}

/// Groups related measurements in a cockpit panel.
class _Panel extends StatelessWidget {
  const _Panel(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: DashboardStyle.surface(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        ...children,
      ],
    ),
  );
}

/// Keeps labels and sample values readable at increased text size.
class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10,
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: DashboardStyle.muted)),
      ),
      Expanded(child: Text(value, textAlign: TextAlign.end)),
    ],
  );
}
