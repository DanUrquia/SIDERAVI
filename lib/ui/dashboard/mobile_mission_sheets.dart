import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_map_config.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../mission_theme.dart';
import 'dashboard_panels.dart';
import 'dashboard_style.dart';

/// Displays the mission briefing and device-local progress.
class MobileMissionsContent extends StatelessWidget {
  const MobileMissionsContent({
    super.key,
    required this.mission,
    required this.landmarks,
    required this.completed,
    required this.loading,
    required this.onChange,
    required this.onSelect,
    this.storageWarning,
  });

  final MarsMission mission;
  final List<DemoLandmark> landmarks;
  final Set<String> completed;
  final bool loading;
  final void Function(String id, bool completed) onChange;
  final void Function(Offset point, String label) onSelect;
  final String? storageWarning;

  @override
  Widget build(BuildContext context) {
    final objectives = mission.objectives;
    final waypoints = {
      for (final landmark in landmarks) landmark.name: landmark.position,
    };
    final done = objectives.where((item) => completed.contains(item.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        DashboardPanel(
          title: mission.title,
          icon: Icons.flag_outlined,
          children: [
            Text(mission.description),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: loading ? null : done / objectives.length,
              backgroundColor: DashboardStyle.outline,
              color: DashboardStyle.orange,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'Mission progress',
            ),
            Text(
              loading
                  ? 'Loading checklist'
                  : '$done of ${objectives.length} complete · On this device',
              style: const TextStyle(color: DashboardStyle.muted, fontSize: 13),
            ),
            if (storageWarning case final warning?)
              Text(
                warning,
                style: const TextStyle(color: DashboardStyle.amber),
              ),
          ],
        ),
        for (final item in objectives)
          DecoratedBox(
            decoration: DashboardStyle.surface(),
            child: Column(
              children: [
                CheckboxListTile(
                  key: ValueKey('objective-${item.id}'),
                  title: Text(item.label),
                  subtitle: Text(
                    completed.contains(item.id) ? 'Complete' : 'Pending',
                    style: TextStyle(
                      color: completed.contains(item.id)
                          ? DashboardStyle.green
                          : DashboardStyle.muted,
                    ),
                  ),
                  activeColor: DashboardStyle.orange,
                  value: completed.contains(item.id),
                  onChanged: loading
                      ? null
                      : (value) => onChange(item.id, value == true),
                ),
                if (waypoints[item.waypoint] case final position?)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => onSelect(position, item.waypoint!),
                      icon: const Icon(Icons.place_outlined),
                      label: Text(item.waypoint!),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Presents the local pose, mission controls, and reference planetary conditions.
class MobileAstronautContent extends StatelessWidget {
  const MobileAstronautContent({
    super.key,
    required this.astronaut,
    required this.mission,
    required this.navigation,
    required this.tracking,
    required this.onNavigate,
    required this.onReturn,
    required this.onSensorTest,
    required this.onMovementLog,
  });

  final Astronaut astronaut;
  final MarsMission mission;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final VoidCallback onNavigate;
  final VoidCallback onReturn;
  final VoidCallback onSensorTest;
  final VoidCallback onMovementLog;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        DashboardPanel(
          icon: Icons.person_outline,
          title: astronaut.id,
          children: [
            Text(astronaut.fullName, style: MissionTheme.display(22)),
            DashboardReadout(label: 'Mission status', value: navigation.status),
            DashboardReadout(
              label: 'Simulated Mars',
              value: formatMarsPosition(tracking.pose.mars),
            ),
            DashboardReadout(
              label: 'Distance traveled',
              value:
                  '${formatDemoDistance(tracking.distanceTraveled)} · Simulated Mars',
            ),
            DashboardReadout(
              label: 'Total steps',
              value: tracking.measuredSteps == null
                  ? 'Unavailable'
                  : '${tracking.measuredSteps} · Measured this visit',
            ),
            DashboardReadout(
              label: 'Movement source',
              value: tracking.mode.label,
            ),
            DashboardReadout(
              label: 'Position confidence',
              value: tracking.quality.label,
            ),
            const SizedBox(height: 2),
            DashboardButton(
              label: navigation.paused ? 'RESUME MISSION' : 'PAUSE MISSION',
              height: 48,
              icon: navigation.paused ? Icons.play_arrow : Icons.pause,
              onPressed: navigation.sos ? null : navigation.togglePause,
            ),
          ],
        ),
        NavigationPanel(
          navigation: navigation,
          tracking: tracking,
          onNavigate: onNavigate,
          onReturn: onReturn,
        ),
        PlanetaryConditionsPanel(mission: mission, navigation: navigation),
        DashboardPanel(
          title: 'DEVICE SENSORS',
          icon: Icons.sensors,
          children: [
            for (final mode in TrackingMode.values)
              Semantics(
                selected: tracking.mode == mode,
                child: DashboardButton(
                  label: mode.label,
                  height: 48,
                  primary: tracking.mode == mode,
                  icon: mode == TrackingMode.live
                      ? Icons.sensors
                      : Icons.route_outlined,
                  onPressed: () => tracking.selectMode(mode),
                ),
              ),
            DashboardButton(
              label: 'CALIBRATE ARROW',
              height: 48,
              icon: Icons.navigation_outlined,
              onPressed: tracking.calibrate,
            ),
            DashboardButton(
              label: 'SENSOR TEST',
              height: 48,
              icon: Icons.monitor_heart_outlined,
              onPressed: onSensorTest,
            ),
            DashboardButton(
              label:
                  tracking.requiresRebaseline &&
                      tracking.mode == TrackingMode.live
                  ? 'REVIEW POSITION HOLD'
                  : 'MOVEMENT LOG',
              height: 48,
              icon: Icons.receipt_long_outlined,
              onPressed: onMovementLog,
            ),
          ],
        ),
      ],
    );
  }
}

/// Shows only the local astronaut's telemetry and the teammate's shared pose.
class MobileCrewContent extends StatelessWidget {
  const MobileCrewContent({
    super.key,
    required this.astronaut,
    required this.teammate,
    required this.navigation,
    required this.tracking,
    required this.presence,
    required this.member,
    required this.peerPoint,
    required this.fresh,
    required this.onJoin,
    required this.onTeammate,
    required this.onPing,
    required this.onSos,
  });

  final Astronaut astronaut;
  final Astronaut teammate;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final MissionPresence presence;
  final CrewPresence? member;
  final Offset? peerPoint;
  final bool fresh;
  final VoidCallback? onJoin;
  final VoidCallback? onTeammate;
  final VoidCallback onPing;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final current = member;
    final point = peerPoint;
    final peerStatus = fresh
        ? 'In session'
        : current != null
        ? 'Offline · Last known'
        : point == null
        ? 'Not in session'
        : 'Simulated teammate';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        DashboardPanel(
          title: 'SHARED SESSION',
          icon: Icons.link,
          children: [
            DashboardReadout(label: 'Connection', value: presence.status.label),
            if (presence.accessDenied)
              const Text(
                'This account lacks access to the current mission slot.',
              ),
            DashboardButton(
              label: presence.status == ConnectionStatus.offline
                  ? 'JOIN CREW'
                  : 'LEAVE CREW',
              height: 48,
              icon: Icons.group_outlined,
              onPressed: onJoin,
            ),
          ],
        ),
        DashboardPanel(
          title: '${astronaut.id} · YOU',
          icon: Icons.person_outline,
          children: [
            Text(astronaut.fullName, style: MissionTheme.display(18)),
            DashboardReadout(
              label: 'Simulated Mars',
              value: formatMarsPosition(tracking.pose.mars),
            ),
            DashboardReadout(
              label: 'Measured steps',
              value: tracking.measuredSteps?.toString() ?? 'Unavailable',
            ),
          ],
        ),
        DashboardPanel(
          title: '${teammate.id} · $peerStatus',
          icon: Icons.person_outline,
          children: [
            Text(teammate.fullName, style: MissionTheme.display(18)),
            DashboardReadout(
              label: fresh
                  ? 'Shared Mars position'
                  : current == null
                  ? 'Simulated Mars'
                  : 'Last known Mars',
              value: current != null
                  ? formatMarsPosition(current.pose.mars)
                  : point == null
                  ? 'Unavailable'
                  : formatMarsPosition(tracking.coordinates.toMars(point)),
            ),
            const DashboardReadout(label: 'Steps', value: 'Unavailable'),
            if (point != null) ...[
              DashboardReadout(
                label: current != null && !fresh
                    ? 'To last known position'
                    : 'Simulated separation',
                value: formatDemoDistance(
                  tracking.coordinates.distance(navigation.position, point),
                ),
              ),
              DashboardReadout(
                label: 'Relative position',
                value: _relativePosition(point - navigation.position),
              ),
            ],
            if (onTeammate != null)
              DashboardButton(
                label: current != null && !fresh
                    ? 'TARGET LAST KNOWN POSITION'
                    : 'TARGET TEAMMATE',
                height: 48,
                icon: Icons.alt_route,
                onPressed: onTeammate,
              ),
          ],
        ),
        DashboardPanel(
          title: 'MISSION TOOLS',
          icon: Icons.build_outlined,
          children: [
            DashboardButton(
              label: 'SEND PING',
              height: 48,
              icon: Icons.radar,
              onPressed: navigation.sos ? null : onPing,
            ),
            DashboardButton(
              label: navigation.sos ? 'CANCEL SOS' : 'SOS',
              height: 48,
              icon: Icons.sos,
              emergency: true,
              onPressed: onSos,
            ),
          ],
        ),
      ],
    );
  }

  String _relativePosition(Offset delta) {
    if (delta.distance < 1e-6) return 'Same position';
    final northSouth = delta.dy.abs() < 1e-6
        ? ''
        : delta.dy < 0
        ? 'N'
        : 'S';
    final eastWest = delta.dx.abs() < 1e-6
        ? ''
        : delta.dx < 0
        ? 'W'
        : 'E';
    return '$northSouth$eastWest on map';
  }
}
