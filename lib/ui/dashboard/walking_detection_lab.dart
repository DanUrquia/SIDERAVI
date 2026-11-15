import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sensors/walking/walking_capture.dart';
import '../../sensors/walking/walking_detector.dart';
import '../../sensors/walking/walking_lab_controller.dart';
import 'dashboard_style.dart';

/// Opens the diagnostic-only walking section from Movement Log.
Future<void> showWalkingDetectionLab(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _WalkingDetectionLab(),
);

class _WalkingDetectionLab extends StatefulWidget {
  const _WalkingDetectionLab();

  @override
  State<_WalkingDetectionLab> createState() => _WalkingDetectionLabState();
}

class _WalkingDetectionLabState extends State<_WalkingDetectionLab> {
  late final _lab = WalkingLabController();
  final _actual = TextEditingController();

  @override
  void dispose() {
    _actual.dispose();
    _lab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lab,
    builder: (context, _) {
      final data = _lab.reading ?? const {};
      final samples = data['samples'] as int? ?? 0;
      final stale = data['stale'] == true;
      final status = _lab.checking
          ? 'Checking device motion'
          : !_lab.supported
          ? 'Device motion unavailable'
          : _lab.running
          ? stale
                ? 'No fresh motion samples'
                : samples > 0
                ? 'Recording device motion'
                : 'Waiting for motion samples'
          : _lab.hasReport
          ? 'Capture ended · ${_endLabel(data['reason'])}'
          : 'Device motion available';
      String format(String field, int precision, String units) =>
          data[field] is num
          ? '${(data[field] as num).toStringAsFixed(precision)} $units'
          : '—';
      final classification = WalkingMotion.values.byName(
        stale
            ? WalkingMotion.insufficient.name
            : data['motion'] as String? ?? WalkingMotion.insufficient.name,
      );
      final confidence = stale ? 0.0 : (data['confidence'] as num? ?? 0) * 100;
      return AlertDialog(
        title: const Text('Walking Detection Lab'),
        scrollable: true,
        content: SizedBox(
          width: 660,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              const Text(
                'EXPERIMENTAL — NOT USED FOR NAVIGATION',
                style: TextStyle(
                  color: DashboardStyle.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(status, style: Theme.of(context).textTheme.titleMedium),
              DropdownButtonFormField<WalkingScenario>(
                initialValue: _lab.scenario,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _lab.hasReport
                      ? 'Next test scenario'
                      : 'Test scenario',
                ),
                onChanged: _lab.busy || _lab.running
                    ? null
                    : (value) {
                        if (value != null) _lab.setScenario(value);
                      },
                items: [
                  for (final scenario in WalkingScenario.values)
                    DropdownMenuItem(
                      value: scenario,
                      child: Text(scenario.label),
                    ),
                ],
              ),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  _Metric('Actual rate', format('observedHz', 1, 'Hz')),
                  _Metric('Samples', '$samples'),
                  _Metric('Capture duration', format('elapsedSeconds', 1, 's')),
                  _Metric(
                    'Native drops / gaps',
                    '${data['nativeDropped'] ?? 0} / ${data['gaps'] ?? 0}',
                  ),
                  _Metric('Acceleration', format('accelerationG', 3, 'g')),
                  _Metric('Filtered vertical', format('filteredG', 3, 'g')),
                  _Metric('Candidate steps', '${data['candidates'] ?? 0}'),
                  _Metric('Confirmed steps', '${data['confirmed'] ?? 0}'),
                  _Metric(
                    'Cadence',
                    stale ? '—' : format('cadenceSpm', 0, 'steps/min'),
                  ),
                  _Metric('Walking confidence', '${confidence.round()}%'),
                  _Metric(
                    'Last confirmed step',
                    format('lastStepAgeSeconds', 1, 's ago'),
                  ),
                  _Metric(
                    'Peak / prominence',
                    '${WalkingDetector.thresholds['minimumPeakG']} / '
                        '${WalkingDetector.thresholds['minimumProminenceG']} g',
                  ),
                ],
              ),
              Text('Motion · ${classification.label}'),
              if (data['error'] case final Map failure)
                Text('Core Motion · ${failure['domain']} (${failure['code']})'),
              if (_lab.error case final error?) Text(error),
              if (_lab.hasReport) ...[
                Text('Recorded scenario · ${data['scenarioLabel']}'),
                TextField(
                  controller: _actual,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Manually counted steps (optional)',
                    counterText: '',
                  ),
                ),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DashboardButton(
                    label: _lab.running ? 'STOP CAPTURE' : 'START CAPTURE',
                    icon: _lab.running ? Icons.stop : Icons.fiber_manual_record,
                    onPressed: _lab.busy || !_lab.supported
                        ? null
                        : _lab.running
                        ? _lab.stop
                        : () {
                            _actual.clear();
                            _lab.start();
                          },
                  ),
                  DashboardButton(
                    label: 'RESET COUNTER',
                    icon: Icons.restart_alt,
                    onPressed: _lab.running && !_lab.busy ? _lab.reset : null,
                  ),
                  DashboardButton(
                    label: 'EXPORT JSON',
                    icon: Icons.ios_share,
                    onPressed: _lab.hasReport && !_lab.busy
                        ? () => _lab.export(int.tryParse(_actual.text))
                        : null,
                  ),
                ],
              ),
              const Text(
                'Each capture lasts up to 90 seconds. Export it before closing the Lab.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  String _endLabel(Object? reason) => switch (reason) {
    'operator' => 'Stopped',
    'timeLimit' || 'sampleLimit' => 'Capture limit reached',
    'appInactive' || 'motionStopped' => 'App interrupted',
    'coreMotionError' ||
    'bridgeError' ||
    'captureUnavailable' => 'Sensor interrupted',
    _ => 'Stopped',
  };
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
