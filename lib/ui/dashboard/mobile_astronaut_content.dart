import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../missions/mars_climate.dart';
import '../../missions/mars_solar_time.dart';
import '../../missions/mission.dart';
import '../../missions/mola_elevations.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/pedometer_monitor.dart';
import '../mission_action_button.dart';
import '../mission_theme.dart';
import 'dashboard_panels.dart';
import 'dashboard_style.dart';
import 'solar_cycle_card.dart';
import 'walking_calibration.dart';

/// Mission control for the astronaut on this device.
class MobileAstronautContent extends StatelessWidget {
  const MobileAstronautContent({
    super.key,
    required this.astronaut,
    required this.mission,
    required this.navigation,
    required this.tracking,
    required this.solarCycle,
    required this.onSensorTest,
    required this.onMovementLog,
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final ValueListenable<MarsSolarCycle> solarCycle;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;

  @override
  Widget build(BuildContext context) {
    final stepState = tracking.pedometer.state;
    final stepSensorUnavailable = _stepSensorUnavailable(stepState);
    final measuredSteps = stepSensorUnavailable ? null : tracking.measuredSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _IdentityHeader(
          astronaut: astronaut,
          mission: mission.title,
          status: tracking.stepStatus,
          statusColor: stepSensorUnavailable
              ? DashboardStyle.muted
              : navigation.paused
              ? DashboardStyle.amber
              : DashboardStyle.cyan,
        ),
        _MissionTelemetry(mission: mission, cycle: solarCycle),
        SolarCycleCard(cycle: solarCycle),
        DashboardPanel(
          title: 'EXPLORATION STATUS',
          icon: Icons.explore_outlined,
          children: [
            _MetricPair(
              first: _Metric(
                label: 'DISTANCE TRAVELED',
                value: '${tracking.distanceTraveled.toStringAsFixed(1)} m',
                note: 'Estimated',
                highlight: true,
              ),
              second: _Metric(
                label: 'TOTAL STEPS',
                value: measuredSteps?.toString() ?? '—',
                note: measuredSteps == null ? stepState.label : 'Measured',
                highlight: true,
              ),
            ),
            DashboardReadout(
              label: 'Estimated Mars position',
              value: formatMarsPosition(tracking.pose.mars),
            ),
            DashboardReadout(
              label: 'Position quality',
              value: tracking.pose.quality.label,
            ),
            DashboardReadout(
              label: 'Distance to Habitat Base',
              value: formatNavigationDistance(
                navigation.baseDistanceMeters,
                live: true,
              ),
            ),
            DashboardReadout(
              label: 'Applied steps',
              value: tracking.appliedSteps.toString(),
            ),
          ],
        ),
        DashboardPanel(
          title: 'MISSION CONTROLS',
          icon: Icons.tune,
          children: [
            MissionActionButton(
              label: navigation.paused ? 'RESUME MISSION' : 'PAUSE MISSION',
              icon: navigation.paused ? Icons.play_arrow : Icons.pause,
              onPressed: navigation.sos ? null : navigation.togglePause,
              wrapLabel: true,
            ),
            if (Theme.of(context).platform == TargetPlatform.iOS)
              MissionActionButton(
                label: 'START NEW EXPEDITION',
                icon: Icons.restart_alt,
                appearance: MissionActionAppearance.secondary,
                onPressed: navigation.sos
                    ? null
                    : () => _confirmNewExpedition(context),
                wrapLabel: true,
              ),
          ],
        ),
        _MarsTopography(mission: mission),
        _DeviceSensors(
          tracking: tracking,
          paused: navigation.paused,
          onSensorTest: onSensorTest,
          onMovementLog: onMovementLog,
        ),
      ],
    );
  }

  Future<void> _confirmNewExpedition(BuildContext context) async {
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new expedition?'),
        content: const Text(
          'Your position returns to Habitat Base and your route and walking '
          'totals restart. Your teammate and mission checklist stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue expedition'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start at Habitat Base'),
          ),
        ],
      ),
    );
    if (start != true || !context.mounted) return;
    final started = await tracking.startNewExpedition();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'New expedition started at Habitat Base.'
              : 'Could not save a new expedition. Your position was kept.',
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.astronaut,
    required this.mission,
    required this.status,
    required this.statusColor,
  });

  final Astronaut astronaut;
  final String mission;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: DashboardStyle.surface(),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: DashboardStyle.surface(
              color: DashboardStyle.inset,
              border: DashboardStyle.warm.withValues(alpha: .5),
              radius: 12,
            ),
            child: const Icon(
              Icons.person_outline,
              color: DashboardStyle.warm,
              size: 27,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  astronaut.id,
                  style: MissionTheme.display(
                    13,
                    tracking: 1.1,
                  ).copyWith(color: DashboardStyle.cyan),
                ),
                Text(astronaut.fullName, style: MissionTheme.display(27)),
                Text(
                  mission,
                  style: const TextStyle(
                    color: DashboardStyle.muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                _StatusBadge(label: status, color: statusColor),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MissionTelemetry extends StatelessWidget {
  const _MissionTelemetry({required this.mission, required this.cycle});

  final MarsMission mission;
  final ValueListenable<MarsSolarCycle> cycle;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: cycle,
    builder: (_, solar, _) {
      final elevation = mission.elevation;
      final climate = marsClimateCelsius(
        mission.id,
        solar,
        eastLongitude:
            (elevation?.location ?? mission.coordinates).eastLongitude,
      );
      return DashboardPanel(
        title: 'MISSION TELEMETRY',
        icon: Icons.speed,
        children: [
          _MetricPair(
            first: _Metric(
              label: 'MARS TIME',
              value: solar.localTime,
              note: 'LMST · Habitat Base',
              icon: Icons.schedule,
              highlight: true,
            ),
            second: _Metric(
              label: 'TEMPERATURE',
              value: climate == null
                  ? 'Unavailable'
                  : formatMarsClimate(climate),
              note: climate == null ? 'No verified model' : 'Climate estimate',
              icon: Icons.thermostat,
            ),
          ),
          _MetricPair(
            first: _Metric(
              label: 'ELEVATION',
              value: elevation?.label ?? 'Unavailable',
              note: elevation == null
                  ? 'Habitat Base'
                  : 'Habitat Base MOLA · ${MarsBaseElevation.datum}',
              icon: Icons.terrain,
            ),
            second: _Metric(
              label: 'EARTH TIME',
              value: formatTegucigalpaTime(solar.timestamp),
              note: 'Tegucigalpa · UTC−6',
              icon: Icons.public,
            ),
          ),
        ],
      );
    },
  );
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({required this.first, required this.second});

  final _Metric first;
  final _Metric second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 8.0;
      final minimumWidth =
          MediaQuery.textScalerOf(context).scale(12) / 12 * 114;
      if ((constraints.maxWidth - spacing) / 2 < minimumWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: spacing,
          children: [first, second],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: spacing,
          children: [
            Expanded(child: first),
            Expanded(child: second),
          ],
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.note,
    this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String note;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    constraints: const BoxConstraints(minHeight: 98),
    decoration: DashboardStyle.surface(color: DashboardStyle.inset, radius: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            if (icon case final glyph?)
              Icon(glyph, size: 14, color: DashboardStyle.warm),
            Expanded(
              child: Text(
                label,
                style: MissionTheme.display(
                  11,
                  tracking: .35,
                ).copyWith(color: DashboardStyle.muted),
              ),
            ),
          ],
        ),
        Text(
          value,
          style: MissionTheme.display(value == 'Unavailable' ? 14 : 22)
              .copyWith(
                color: highlight ? DashboardStyle.cyan : DashboardStyle.text,
              ),
        ),
        Text(note, style: _noteStyle),
      ],
    ),
  );
}

class _MarsTopography extends StatelessWidget {
  const _MarsTopography({required this.mission});

  final MarsMission mission;

  @override
  Widget build(BuildContext context) {
    final maximum = missionMaximumGridElevationMeters[mission.id];
    return DashboardPanel(
      title: 'MARS TOPOGRAPHY',
      icon: Icons.terrain,
      children: [
        DashboardReadout(label: 'Mission region', value: mission.region),
        DashboardReadout(
          label: 'Habitat Base elevation',
          value: mission.elevation?.label ?? 'Unavailable',
        ),
        DashboardReadout(
          label: 'Maximum gridded elevation',
          value: maximum == null ? 'Unavailable' : formatMarsElevation(maximum),
        ),
        DashboardReadout(
          label: 'Operational radius',
          value: mission.radiusLabel,
        ),
        if (mission.elevation != null || maximum != null) ...[
          const DashboardReadout(
            label: 'Source',
            value: MarsBaseElevation.source,
          ),
          const DashboardReadout(
            label: 'Datum',
            value: MarsBaseElevation.datum,
          ),
          Text(
            '128 cells per degree. The maximum uses grid cell centers within '
            '${mission.radiusLabel} of Habitat Base.',
            style: _noteStyle,
          ),
        ],
      ],
    );
  }
}

class _DeviceSensors extends StatelessWidget {
  const _DeviceSensors({
    required this.tracking,
    required this.paused,
    required this.onSensorTest,
    required this.onMovementLog,
  });

  final AstronautTracking tracking;
  final bool paused;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;

  @override
  Widget build(BuildContext context) {
    final state = tracking.pedometer.state;
    final (status, color) = switch (state) {
      _ when _stepSensorUnavailable(state) => (
        'UNAVAILABLE',
        DashboardStyle.muted,
      ),
      _ when paused => ('PAUSED', DashboardStyle.amber),
      PedometerState.fresh => ('ACTIVE', DashboardStyle.cyan),
      PedometerState.stale => ('STALE', DashboardStyle.amber),
      _ => ('WAITING', DashboardStyle.muted),
    };
    return DashboardPanel(
      title: 'DEVICE SENSORS',
      icon: Icons.sensors,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _StatusBadge(label: status, color: color),
        ),
        DashboardReadout(label: 'Step counting', value: state.label),
        DashboardReadout(label: 'Step sensor', value: tracking.stepSource),
        ValueListenableBuilder<double?>(
          valueListenable: tracking.heading,
          builder: (_, heading, _) {
            final bearing = tracking.walkingBearing;
            return Column(
              spacing: 8,
              children: [
                DashboardReadout(
                  label: 'Device heading',
                  value: paused
                      ? 'PAUSED'
                      : heading == null
                      ? 'UNAVAILABLE'
                      : 'AVAILABLE',
                ),
                DashboardReadout(
                  label: 'Direction calibration',
                  value: tracking.hasWalkingCalibration
                      ? 'Calibrated'
                      : 'Awaiting calibration',
                ),
                DashboardReadout(
                  label: 'Walking direction',
                  value: bearing == null
                      ? 'Unavailable'
                      : '${bearing.round() % 360}° relative to map north',
                ),
              ],
            );
          },
        ),
        const Text(
          'The direction the phone first points sets local map north.',
          style: _noteStyle,
        ),
        DashboardReadout(
          label: 'Stride length',
          value: '${tracking.stride.toStringAsFixed(2)} m per step',
        ),
        if (state == PedometerState.denied)
          Text(
            Theme.of(context).platform == TargetPlatform.iOS
                ? 'Allow Motion & Fitness for SIDERA VI in Settings to count steps.'
                : 'Allow motion access for SIDERA VI in Settings to count steps.',
            style: _noteStyle,
          ),
        const SizedBox(height: 2),
        MissionActionButton(
          label: 'CALIBRATE WALKING DIRECTION',
          icon: Icons.navigation_outlined,
          onPressed: tracking.canCalibrateWalking
              ? () => confirmWalkingDirection(context, tracking)
              : null,
          appearance: MissionActionAppearance.secondary,
          wrapLabel: true,
        ),
        MissionActionButton(
          label: 'SET STRIDE LENGTH',
          icon: Icons.straighten,
          onPressed: () => configureStride(context, tracking),
          appearance: MissionActionAppearance.secondary,
          wrapLabel: true,
        ),
        MissionActionButton(
          label: 'SENSOR TEST',
          icon: Icons.monitor_heart_outlined,
          onPressed: onSensorTest,
          appearance: MissionActionAppearance.secondary,
          wrapLabel: true,
        ),
        MissionActionButton(
          label: 'MOVEMENT LOG',
          icon: Icons.receipt_long_outlined,
          onPressed: onMovementLog,
          appearance: MissionActionAppearance.secondary,
          wrapLabel: true,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: DashboardStyle.surface(
      color: DashboardStyle.inset,
      border: color.withValues(alpha: .32),
      radius: 10,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(Icons.circle, color: color, size: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

const _noteStyle = TextStyle(color: DashboardStyle.muted, fontSize: 12);

bool _stepSensorUnavailable(PedometerState state) => switch (state) {
  PedometerState.unsupported ||
  PedometerState.denied ||
  PedometerState.restricted ||
  PedometerState.unavailable => true,
  _ => false,
};
