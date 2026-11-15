import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import 'dashboard_style.dart';

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
  bool _exporting = false;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      await widget.tracking.exportCapture();
    } catch (_) {
      if (mounted) _error = 'Could not open the local share sheet.';
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final log = tracking.telemetry;
    return ListenableBuilder(
      listenable: Listenable.merge([tracking, log]),
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
                Text('Step counting · ${capability('stepCounting')}'),
                Text('Pedometer distance · ${capability('pedometerDistance')}'),
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
                      onPressed: log.recording
                          ? () => log.stop(tracking.clock())
                          : () => tracking.startCapture(widget.mission),
                    ),
                    DashboardButton(
                      label: 'EXPORT JSON',
                      icon: Icons.ios_share,
                      onPressed: log.hasEvents && !_exporting ? _export : null,
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
