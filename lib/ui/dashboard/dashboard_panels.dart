import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';

/// Shows the active astronaut, local grid position and current bearing.
class PositionPanel extends StatelessWidget {
  /// Reads the astronaut identity and local exploration state.
  const PositionPanel({
    super.key,
    required this.astronaut,
    required this.navigation,
    required this.tracking,
  });

  final Astronaut astronaut;
  final DemoNavigation navigation;
  final AstronautTracking tracking;

  @override
  Widget build(BuildContext context) => DashboardPanel(
    title: 'YOUR POSITION',
    icon: Icons.my_location,
    children: [
      Text(astronaut.fullName, style: MissionTheme.display(18)),
      DashboardReadout(
        label: 'Simulated Mars',
        value: formatMarsPosition(tracking.pose.mars),
      ),
      ValueListenableBuilder<double?>(
        valueListenable: tracking.heading,
        builder: (context, heading, _) => DashboardReadout(
          label: 'Relative heading',
          value: heading == null ? 'Unavailable' : '${heading.round()}°',
        ),
      ),
      DashboardReadout(
        label: 'Exploration',
        value: navigation.sos
            ? 'Demo SOS'
            : navigation.paused
            ? 'Paused'
            : 'Active',
      ),
    ],
  );
}

/// Formats the simulated geographic position without identifying an Earth fix.
String formatMarsPosition(Offset point) =>
    '${point.dy.abs().toStringAsFixed(4)}° ${point.dy < 0 ? 'S' : 'N'}, '
    '${point.dx.abs().toStringAsFixed(4)}° ${point.dx < 0 ? 'W' : 'E'}';

/// Shows the route status and actions for destination or base travel.
class NavigationPanel extends StatelessWidget {
  /// Receives route readouts and actions owned by the dashboard.
  const NavigationPanel({
    super.key,
    required this.navigation,
    required this.tracking,
    required this.onNavigate,
    required this.onReturn,
  });

  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final target = navigation.target;
    final live = tracking.mode == TrackingMode.live;
    String distance(Offset point) =>
        formatDemoDistance(navigation.distanceTo(point));
    final start = DashboardButton(
      label: 'START NAVIGATION',
      icon: Icons.navigation_outlined,
      primary: true,
      onPressed: navigation.canNavigate ? onNavigate : null,
    );
    final base = DashboardButton(
      label: 'RETURN TO BASE',
      icon: Icons.home_outlined,
      onPressed: navigation.sos || navigation.atBase ? null : onReturn,
    );
    return DashboardPanel(
      title: 'NAVIGATION',
      icon: Icons.alt_route,
      children: [
        DashboardReadout(
          label: 'Destination',
          value: navigation.targetLabel ?? 'Tap the map',
        ),
        DashboardReadout(
          label: 'To destination',
          value: target == null ? '—' : distance(target),
        ),
        DashboardReadout(
          label: 'To base',
          value: distance(navigation.map.base),
        ),
        Text(
          live && !navigation.paused
              ? tracking.quality.label
              : navigation.status,
          style: const TextStyle(
            color: DashboardStyle.warm,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 350 ||
                MediaQuery.textScalerOf(context).scale(15) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [start, base],
              );
            }
            return Row(
              spacing: 8,
              children: [
                Expanded(flex: 11, child: start),
                Expanded(flex: 10, child: base),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Pairs three reference conditions with the current Tegucigalpa clock.
class PlanetaryConditionsPanel extends StatelessWidget {
  /// Shows the sourced base-point elevation when available.
  const PlanetaryConditionsPanel({
    super.key,
    required this.mission,
    required this.navigation,
  });

  final MarsMission mission;
  final DemoNavigation navigation;

  @override
  Widget build(BuildContext context) => DashboardPanel(
    title: 'PLANETARY CONDITIONS',
    icon: Icons.public,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 7,
        children: [
          Expanded(
            child: _Condition(
              label: 'MARS LOCAL SOLAR TIME',
              value: navigation.map.marsTime,
              note: 'Demo reference',
            ),
          ),
          const Expanded(child: TegucigalpaClock()),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 7,
        children: [
          Expanded(
            child: _Condition(
              label: 'MARS TEMPERATURE',
              value: navigation.map.marsTemperature,
              note: 'Illustrative',
            ),
          ),
          Expanded(
            child: _Condition(
              label: 'ELEVATION / RELIEF',
              value: mission.elevationLabel,
              note: mission.elevation == null ? null : 'MOLA base estimate',
            ),
          ),
        ],
      ),
    ],
  );
}

/// Shows both demo identities and makes the teammate a selectable destination.
class AstronautListPanel extends StatelessWidget {
  /// Distinguishes the current astronaut from the simulated teammate.
  const AstronautListPanel({
    super.key,
    required this.astronaut,
    required this.teammate,
    required this.teammateStatus,
    required this.onSelect,
  });

  final Astronaut astronaut;
  final Astronaut teammate;
  final String teammateStatus;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => DashboardPanel(
    title: 'ASTRONAUTS',
    icon: Icons.people_outline,
    children: [
      _CrewRow(
        astronaut: astronaut,
        status: 'You',
        color: DashboardStyle.green,
      ),
      _CrewRow(
        astronaut: teammate,
        status: teammateStatus,
        color: DashboardStyle.cyan,
        onTap: onSelect,
      ),
    ],
  );
}

/// Gives each secondary information group a consistent surface and heading.
class DashboardPanel extends StatelessWidget {
  /// Places the panel's content under an accessible section title.
  const DashboardPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: DashboardStyle.surface(),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Semantics(
            header: true,
            child: Row(
              spacing: 8,
              children: [
                Icon(icon, size: 19, color: DashboardStyle.warm),
                Flexible(
                  child: Text(
                    title,
                    style: MissionTheme.display(
                      14,
                      tracking: .8,
                    ).copyWith(color: DashboardStyle.muted),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

/// Pairs a short metric label and a wrap-capable value.
class DashboardReadout extends StatelessWidget {
  const DashboardReadout({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10,
    children: [
      Expanded(
        flex: 4,
        child: Text(
          label,
          style: const TextStyle(color: DashboardStyle.muted, fontSize: 13),
        ),
      ),
      Expanded(
        flex: 6,
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(
            color: DashboardStyle.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

/// Displays a planetary condition with its measurement context.
class _Condition extends StatelessWidget {
  const _Condition({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 88),
    decoration: DashboardStyle.surface(color: DashboardStyle.inset, radius: 10),
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Text(
          label,
          style: MissionTheme.display(
            11,
            tracking: .4,
          ).copyWith(color: DashboardStyle.muted),
        ),
        Text(value, style: MissionTheme.display(value.length > 14 ? 14 : 20)),
        if (note case final detail?)
          Text(
            detail,
            style: const TextStyle(fontSize: 11, color: DashboardStyle.muted),
          ),
      ],
    ),
  );
}

/// Reads the device clock in fixed UTC−6 with no network dependency.
class TegucigalpaClock extends StatefulWidget {
  const TegucigalpaClock({super.key});

  @override
  State<TegucigalpaClock> createState() => _TegucigalpaClockState();
}

/// Updates just the Earth-time tile during a long mission.
class _TegucigalpaClockState extends State<TegucigalpaClock> {
  DateTime _now = DateTime.now().toUtc();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = DateTime.now().toUtc();
      if (current.minute != _now.minute || current.hour != _now.hour) {
        setState(() => _now = current);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = _now.subtract(const Duration(hours: 6));
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return _Condition(
      label: 'EARTH TIME',
      value: time,
      note: 'Tegucigalpa · UTC−6',
    );
  }
}

/// Presents a full-width crew row with a glove-sized hit target.
class _CrewRow extends StatelessWidget {
  const _CrewRow({
    required this.astronaut,
    required this.status,
    required this.color,
    this.onTap,
  });

  final Astronaut astronaut;
  final String status;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.all(9),
      child: Row(
        spacing: 9,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: .15),
            foregroundColor: color,
            child: Text(astronaut.initials, style: MissionTheme.display(12)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(astronaut.fullName, style: MissionTheme.display(15)),
                Text(
                  '${astronaut.id} · $status',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: color),
        ],
      ),
    );
    return Material(
      color: DashboardStyle.inset,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: .35)),
      ),
      child: onTap == null
          ? row
          : Semantics(
              label: 'Target ${astronaut.fullName}',
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: row,
              ),
            ),
    );
  }
}
