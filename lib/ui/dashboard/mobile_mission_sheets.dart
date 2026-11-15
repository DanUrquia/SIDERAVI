import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_map_config.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import '../../tracking/pedometer_monitor.dart';
import '../mission_theme.dart';
import 'dashboard_panels.dart';
import 'dashboard_style.dart';
import 'walking_calibration.dart';

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
  final ValueChanged<String> onChange;
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
          _ObjectiveCard(
            key: ValueKey('objective-${item.id}'),
            objective: item,
            completed: completed.contains(item.id),
            toggle: loading ? null : () => onChange(item.id),
            selectWaypoint: switch (waypoints[item.waypoint]) {
              final Offset point => () => onSelect(point, item.waypoint!),
              null => null,
            },
          ),
      ],
    );
  }
}

/// A tappable completion surface with a separate optional map shortcut.
class _ObjectiveCard extends StatelessWidget {
  const _ObjectiveCard({
    super.key,
    required this.objective,
    required this.completed,
    required this.toggle,
    required this.selectWaypoint,
  });

  final MissionObjective objective;
  final bool completed;
  final VoidCallback? toggle;
  final VoidCallback? selectWaypoint;

  @override
  Widget build(BuildContext context) {
    final status = completed ? 'Completed' : 'Pending';
    final radius = BorderRadius.circular(15);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      enabled: toggle != null,
      toggled: completed,
      label: objective.label,
      value: status,
      hint: completed ? 'Mark pending' : 'Mark completed',
      onTap: toggle,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: DashboardStyle.surface(
          color: completed ? const Color(0xFF145341) : DashboardStyle.panel,
          border: completed ? const Color(0xFF347A63) : DashboardStyle.outline,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            excludeFromSemantics: true,
            borderRadius: radius,
            onTap: toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 12, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      objective.label,
                      style: const TextStyle(
                        color: DashboardStyle.text,
                        fontSize: 15,
                        height: 1.38,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Text(
                      status,
                      style: TextStyle(
                        color: completed
                            ? const Color(0xFFB7F6DD)
                            : DashboardStyle.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (selectWaypoint != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: selectWaypoint,
                        style: TextButton.styleFrom(
                          foregroundColor: completed
                              ? const Color(0xFFD1FBE9)
                              : DashboardStyle.warm,
                        ),
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: Text(objective.waypoint!),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents the local pose, diagnostics, and the Earth clock.
class MobileAstronautContent extends StatelessWidget {
  const MobileAstronautContent({
    super.key,
    required this.astronaut,
    required this.navigation,
    required this.tracking,
    required this.onSensorTest,
    required this.onMovementLog,
  });

  final Astronaut astronaut;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
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
            DashboardReadout(
              label: 'Position status',
              value: tracking.stepStatus,
            ),
            if (tracking.pedometer.state == PedometerState.denied)
              Text(
                Theme.of(context).platform == TargetPlatform.iOS
                    ? 'Allow Motion & Fitness for SIDERA VI in Settings to count steps.'
                    : 'Allow motion access for SIDERA VI in Settings to count steps.',
              ),
            DashboardReadout(
              label: 'Estimated Mars position',
              value: formatMarsPosition(tracking.pose.mars),
            ),
            DashboardReadout(
              label: 'Estimated distance traveled',
              value: '${tracking.distanceTraveled.toStringAsFixed(1)} m',
            ),
            DashboardReadout(
              label: 'To base',
              value: formatNavigationDistance(
                navigation.baseDistanceMeters,
                live: true,
              ),
            ),
            DashboardReadout(
              label: 'Total steps',
              value: tracking.measuredSteps?.toString() ?? '—',
            ),
            DashboardReadout(
              label: 'Applied steps',
              value: tracking.appliedSteps.toString(),
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
        const TegucigalpaClock(),
        DashboardPanel(
          title: 'DEVICE SENSORS',
          icon: Icons.sensors,
          children: [
            DashboardReadout(label: 'Step sensor', value: tracking.stepSource),
            ValueListenableBuilder<double?>(
              valueListenable: tracking.heading,
              builder: (_, _, _) {
                final bearing = tracking.walkingBearing;
                return DashboardReadout(
                  label: 'Walking direction',
                  value: bearing == null
                      ? 'Unavailable'
                      : '${bearing.round() % 360}° relative to map north',
                );
              },
            ),
            const Text(
              'The direction the phone first points sets local map north.',
              style: TextStyle(color: DashboardStyle.muted, fontSize: 12),
            ),
            DashboardReadout(
              label: 'Stride length',
              value: '${tracking.stride.toStringAsFixed(2)} m per step',
            ),
            DashboardButton(
              label: 'CALIBRATE WALKING DIRECTION',
              height: 48,
              icon: Icons.navigation_outlined,
              onPressed: tracking.canCalibrateWalking
                  ? () => confirmWalkingDirection(context, tracking)
                  : null,
            ),
            DashboardButton(
              label: 'SET STRIDE LENGTH',
              height: 48,
              icon: Icons.straighten,
              onPressed: () => configureStride(context, tracking),
            ),
            DashboardButton(
              label: 'SENSOR TEST',
              height: 48,
              icon: Icons.monitor_heart_outlined,
              onPressed: onSensorTest,
            ),
            DashboardButton(
              label: 'MOVEMENT LOG',
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
              label: 'Estimated Mars position',
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
                    : 'Estimated separation',
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
