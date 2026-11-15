import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/demo_navigation.dart';
import '../../missions/mars_solar_time.dart';
import '../../missions/mission.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';

/// Stacks the mission actions and camera controls on the right of the map.
class MobileMapControls extends StatelessWidget {
  const MobileMapControls({
    super.key,
    required this.navigation,
    required this.onNavigate,
    required this.onReturn,
    required this.onPing,
    required this.onSos,
    required this.ownsActiveSos,
    required this.headingUp,
    required this.onRecenter,
    required this.onToggleHeading,
  });

  final DemoNavigation navigation;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onPing;
  final VoidCallback onSos;
  final bool ownsActiveSos;
  final ValueListenable<bool> headingUp;
  final VoidCallback onRecenter;
  final VoidCallback onToggleHeading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      final gap = ((height - 6 * 44) / 5).clamp(3.0, 8.0);
      final diameter = ((height - 5 * gap) / 6).clamp(44.0, 52.0);
      final column = Column(
        key: const ValueKey('mobile-map-controls'),
        mainAxisSize: MainAxisSize.min,
        spacing: gap,
        children: [
          Column(
            key: const ValueKey('mobile-map-actions'),
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: [
              _button(
                'start',
                'Start Navigation',
                Icons.navigation_rounded,
                diameter,
                navigation.canNavigate ? onNavigate : null,
              ),
              _button(
                'return',
                'Return to Base',
                Icons.home_rounded,
                diameter,
                navigation.canReturnToBase ? onReturn : null,
              ),
              _button(
                'ping',
                'Send PIN',
                Icons.location_on_outlined,
                diameter,
                onPing,
              ),
              _button(
                'sos',
                ownsActiveSos ? 'Cancel SOS' : 'SOS',
                Icons.warning_amber_rounded,
                diameter,
                onSos,
              ),
            ],
          ),
          _cameraButton(
            label: 'Recenter on astronaut',
            icon: Icons.my_location,
            size: diameter,
            onPressed: onRecenter,
          ),
          ValueListenableBuilder(
            valueListenable: headingUp,
            builder: (context, active, _) => Semantics(
              button: true,
              label: 'Heading-up map',
              toggled: active,
              onTap: onToggleHeading,
              excludeSemantics: true,
              child: _cameraButton(
                label: active ? 'North-up' : 'Heading-up',
                icon: Icons.navigation_outlined,
                size: diameter,
                onPressed: onToggleHeading,
                selected: active,
              ),
            ),
          ),
        ],
      );
      if (6 * diameter + 5 * gap > height + .01) {
        return SingleChildScrollView(primary: false, child: column);
      }
      return column;
    },
  );

  Widget _button(
    String id,
    String label,
    IconData icon,
    double diameter,
    VoidCallback? action,
  ) => Semantics(
    label: label,
    button: true,
    enabled: action != null,
    onTap: action,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconButton.filled(
        key: ValueKey('mobile-action-$id'),
        onPressed: action,
        style: IconButton.styleFrom(
          alignment: Alignment.center,
          padding: EdgeInsets.zero,
          fixedSize: Size.square(diameter),
          minimumSize: Size.square(diameter),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
          backgroundColor: DashboardStyle.orange,
          foregroundColor: MissionTheme.black,
          disabledBackgroundColor: const Color(0xFFC65D36),
          disabledForegroundColor: const Color(0xFF302420),
          elevation: 3,
          shadowColor: Colors.black87,
        ),
        icon: Icon(icon, size: 23),
      ),
    ),
  );

  Widget _cameraButton({
    required String label,
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
    bool selected = false,
  }) => IconButton.filled(
    tooltip: label,
    isSelected: selected,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      fixedSize: Size.square(size),
      minimumSize: Size.square(size),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: selected ? DashboardStyle.cyan : DashboardStyle.inset,
      foregroundColor: selected ? DashboardStyle.inset : DashboardStyle.cyan,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: DashboardStyle.outline),
      ),
    ),
    icon: Icon(icon, size: 21, semanticLabel: label),
  );
}

/// Fits the three Mars readings into one row below the mission header.
class MobileMapTelemetry extends StatelessWidget {
  const MobileMapTelemetry({
    super.key,
    required this.eastLongitude,
    required this.mission,
    this.clock = DateTime.now,
  });

  final double eastLongitude;
  final MarsMission mission;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      key: const ValueKey('mobile-map-telemetry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Expanded(
          child: _MarsTimeCard(eastLongitude: eastLongitude, clock: clock),
        ),
        const Expanded(
          child: _TelemetryCard(
            label: 'TEMP',
            value: 'Unavailable',
            note: 'No local reading',
            detail: 'Mars temperature at Habitat Base',
          ),
        ),
        Expanded(
          child: _TelemetryCard(
            label: 'ELEVATION',
            value: mission.elevation == null
                ? 'Unavailable'
                : mission.elevationLabel,
            note: mission.elevation == null ? 'Base point' : 'MOLA estimate',
            detail: mission.elevation == null
                ? 'Habitat Base elevation unavailable'
                : 'Habitat Base elevation, MOLA grid estimate relative to the GMM3 Martian areoid',
          ),
        ),
      ],
    ),
  );
}

class _MarsTimeCard extends StatefulWidget {
  const _MarsTimeCard({required this.eastLongitude, required this.clock});

  final double eastLongitude;
  final DateTime Function() clock;

  @override
  State<_MarsTimeCard> createState() => _MarsTimeCardState();
}

class _MarsTimeCardState extends State<_MarsTimeCard> {
  late final Timer _timer;
  late String _value;

  String _readTime() => formatMarsLocalMeanSolarTime(
    widget.clock(),
    eastLongitude: widget.eastLongitude,
  );

  @override
  void initState() {
    super.initState();
    _value = _readTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final value = _readTime();
      if (value != _value) setState(() => _value = value);
    });
  }

  @override
  void didUpdateWidget(covariant _MarsTimeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.eastLongitude != oldWidget.eastLongitude ||
        widget.clock != oldWidget.clock) {
      _value = _readTime();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _TelemetryCard(
    label: 'MARS TIME',
    value: _value,
    note: 'LMST at Base',
    detail: 'Mars local mean solar time at Habitat Base',
  );
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.label,
    required this.value,
    required this.note,
    required this.detail,
  });

  final String label;
  final String value;
  final String note;
  final String detail;

  @override
  Widget build(BuildContext context) => Semantics(
    label: detail,
    value: value,
    excludeSemantics: true,
    child: Container(
      decoration: DashboardStyle.surface(
        color: const Color(0xEA0B1320),
        radius: 11,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          _line(
            label,
            MissionTheme.display(
              10,
              tracking: .55,
            ).copyWith(color: DashboardStyle.muted),
          ),
          _line(value, MissionTheme.display(17)),
          _line(
            note,
            const TextStyle(fontSize: 10, color: DashboardStyle.muted),
          ),
        ],
      ),
    ),
  );

  Widget _line(String text, TextStyle style) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, style: style, maxLines: 1),
  );
}

/// Presents a single explicit decision for the local phone actions.
Future<bool?> confirmMobileAction(
  BuildContext context, {
  required String title,
  required String message,
  required String detail,
}) {
  var answered = false;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      void answer(bool yes) {
        if (answered) return;
        answered = true;
        Navigator.of(context).pop(yes);
      }

      Widget button(bool yes) => SizedBox(
        height: 51,
        child: FilledButton(
          autofocus: !yes,
          style: MissionTheme.control(
            fill: yes ? MissionTheme.orange : DashboardStyle.inset,
            border: yes ? DashboardStyle.warm : DashboardStyle.outline,
            foreground: yes ? MissionTheme.black : DashboardStyle.text,
            elevation: 0,
            radius: 12,
          ),
          onPressed: () => answer(yes),
          child: Text(yes ? 'YES' : 'NO', style: MissionTheme.display(16)),
        ),
      );

      return AlertDialog(
        backgroundColor: DashboardStyle.panel,
        scrollable: true,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(message),
            Text(detail, style: const TextStyle(color: DashboardStyle.muted)),
            const SizedBox(height: 2),
            if (MediaQuery.sizeOf(context).width >= 286)
              Row(
                spacing: 10,
                children: [
                  Expanded(child: button(false)),
                  Expanded(child: button(true)),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [button(false), button(true)],
              ),
          ],
        ),
      );
    },
  );
}
