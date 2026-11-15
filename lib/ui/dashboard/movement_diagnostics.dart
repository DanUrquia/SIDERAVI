import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../../tracking/pedometer_monitor.dart';
import 'dashboard_style.dart';
import 'walking_detection_lab.dart';

/// Opens a local diagnostic overlay while dashboard tracking stays active.
Future<void> showMovementDiagnostics(
  BuildContext context,
  AstronautTracking tracking,
  String mission,
) => showDialog<void>(
  context: context,
  builder: (_) => _MovementDiagnostics(tracking: tracking, mission: mission),
);

class _MovementDiagnostics extends StatefulWidget {
  const _MovementDiagnostics({required this.tracking, required this.mission});

  final AstronautTracking tracking;
  final String mission;

  @override
  State<_MovementDiagnostics> createState() => _MovementDiagnosticsState();
}

class _MovementDiagnosticsState extends State<_MovementDiagnostics> {
  bool _working = false;
  String? _error;

  Future<void> _finish({required bool export}) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (export) {
        await widget.tracking.exportCapture();
      } else {
        await widget.tracking.stopCapture();
      }
    } catch (_) {
      if (mounted) {
        _error = export
            ? 'Could not open the local share sheet.'
            : 'Could not finish capture.';
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final log = tracking.telemetry;
    final pedometer = tracking.pedometer;
    return ListenableBuilder(
      listenable: Listenable.merge([tracking, log, pedometer]),
      builder: (context, _) {
        final capabilities = log.capabilities;
        String capability(String key) => switch (capabilities[key]) {
          true => 'Available',
          false => 'Unavailable',
          _ => 'Awaiting sensor status',
        };
        return AlertDialog(
          title: const Text('Live Movement Diagnostics'),
          scrollable: true,
          content: SizedBox(
            width: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                const Text(
                  'A capture can contain precise Earth coordinates. It stays on '
                  'this iPad until you export it.',
                ),
                if (tracking.requiresRebaseline)
                  const Text(
                    'Position held after a location jump. Rebaseline to assess '
                    'new fixes from this spot.',
                    style: TextStyle(color: DashboardStyle.amber),
                  ),
                Text('${tracking.mode.label} · ${tracking.quality.label}'),
                Text(
                  log.recording
                      ? 'Recording · ${log.count} events'
                      : log.hasEvents
                      ? 'Capture stopped · ${log.count} events'
                      : 'Capture off',
                ),
                if (log.dropped > 0)
                  Text('${log.dropped} older events removed'),
                if (log.lastDecision case final decision?)
                  Text('Last location decision · $decision'),
                if (log.lastPositionSource case final source?)
                  Text('Last position source · $source'),
                Text('Core Motion · ${capability('motion')}'),
                Text('Accelerometer · ${capability('accelerometer')}'),
                Text('Compass · ${capability('compass')}'),
                _PedometerReadout(pedometer),
                if (tracking.mode == TrackingMode.demo)
                  DashboardButton(
                    label: 'ENABLE LIVE SENSORS',
                    icon: Icons.sensors,
                    onPressed: () => tracking.selectMode(TrackingMode.live),
                  ),
                if (_working) const Text('Finishing capture…'),
                if (_error case final error?) Text(error),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DashboardButton(
                      label: log.recording ? 'STOP CAPTURE' : 'START CAPTURE',
                      icon: log.recording
                          ? Icons.stop
                          : Icons.fiber_manual_record,
                      onPressed: _working
                          ? null
                          : log.recording
                          ? () => _finish(export: false)
                          : () => tracking.startCapture(widget.mission),
                    ),
                    DashboardButton(
                      label: 'EXPORT JSON',
                      icon: Icons.ios_share,
                      onPressed: log.hasEvents && !_working
                          ? () => _finish(export: true)
                          : null,
                    ),
                    DashboardButton(
                      label: 'REBASELINE',
                      icon: Icons.my_location,
                      onPressed: tracking.mode == TrackingMode.live
                          ? tracking.rebaseline
                          : null,
                    ),
                  ],
                ),
                const Text(
                  'Rebaseline keeps the Mars position and uses the next '
                  'fresh Earth fix as the new baseline.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => showWalkingDetectionLab(context),
              child: const Text('Walking Detection Lab'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Presents measured physical activity separately from the navigation controls.
class _PedometerReadout extends StatelessWidget {
  const _PedometerReadout(this.monitor);

  final PedometerMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final latest = monitor.latest;
    final capture = monitor.hasCapture;
    final steps = capture ? monitor.captureSteps : latest?.steps;
    final distance = capture ? monitor.captureDistance : latest?.distance;
    final cadence = latest?.cadence;
    final age = monitor.ageSeconds;
    final motion = monitor.recentStepIncrease
        ? 'Steps detected'
        : monitor.state == PedometerState.fresh
        ? 'No recent step increase'
        : 'Awaiting fresh step data';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Text(
          'Pedometer · ${monitor.state.label}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Step counting · ${monitor.stepSupported ? 'Available' : 'Unavailable'}'
          '   •   Distance · ${monitor.distanceSupported ? 'Available' : 'Unavailable'}',
        ),
        Text('Motion authorization · ${monitor.authorization}'),
        Text(
          '${capture ? 'Capture' : 'Live window'} steps · ${steps ?? '—'}'
          '   •   Estimated distance · ${distance == null ? '—' : '${distance.toStringAsFixed(1)} m'}',
        ),
        if (capture && latest != null)
          Text(
            'Latest live window · ${latest.steps} steps'
            '   •   ${latest.distance == null ? '—' : '${latest.distance!.toStringAsFixed(1)} m reported'}',
          ),
        Text(
          'Last sample · ${age == null ? '—' : '$age s ago'}'
          '   •   Cadence · ${cadence == null ? '—' : '${(cadence * 60).round()} steps/min'}',
        ),
        Text('Activity · $motion'),
        if (monitor.error case final failure?)
          Text('Pedometer error · ${failure['domain']} (${failure['code']})'),
        if (monitor.captureQuery case final query?)
          Text(
            query['outcome'] == 'measured'
                ? 'Capture-window query returned a measurement'
                : query['outcome'] == 'error'
                ? 'Capture-window query · ${query['domain']} (${query['code']})'
                : 'Capture-window query · No measurement',
          ),
        const Text(
          'Pedometer measurements are for validation. Map movement uses the location guard.',
        ),
      ],
    );
  }
}
