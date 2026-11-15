import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../dashboard/demo_navigation.dart';
import '../../dashboard/mission_map_config.dart';
import '../../maps/mars_projection.dart';
import '../../missions/mission.dart';
import '../../tracking/astronaut_tracking.dart';
import '../../tracking/crew_signals.dart';
import '../../tracking/mission_presence.dart';
import '../../tracking/tracking_geometry.dart';
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
  final ValueChanged<String> onChange;
  final ValueChanged<DemoLandmark> onSelect;
  final String? storageWarning;

  @override
  Widget build(BuildContext context) {
    final objectives = mission.objectives;
    final waypoints = {for (final landmark in landmarks) landmark.id: landmark};
    final assigned = {
      for (final item in objectives)
        if (waypoints.containsKey(item.landmarkId)) item.landmarkId,
    };
    final done = objectives.where((item) => completed.contains(item.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _MissionPanorama(mission: mission),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 9,
            children: [
              Semantics(
                header: true,
                child: Row(
                  spacing: 8,
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 21,
                      color: DashboardStyle.warm,
                    ),
                    Flexible(
                      child: Text(
                        mission.title.toUpperCase(),
                        style: MissionTheme.display(
                          16,
                          tracking: .45,
                        ).copyWith(color: DashboardStyle.warm),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                mission.description,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _MissionFact(
                    icon: Icons.place_outlined,
                    label: assigned.length == 1
                        ? '1 location'
                        : '${assigned.length} locations',
                  ),
                  _MissionFact(
                    icon: Icons.radar_outlined,
                    label: 'Radius · ${mission.radiusLabel}',
                  ),
                  _MissionFact(
                    icon: Icons.terrain_outlined,
                    label:
                        'Base · ${mission.elevation?.label ?? 'Unavailable'}',
                    semanticsLabel: 'Habitat Base MOLA elevation',
                  ),
                ],
              ),
              const SizedBox(height: 1),
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
                style: const TextStyle(
                  color: DashboardStyle.muted,
                  fontSize: 13,
                ),
              ),
              if (storageWarning case final warning?)
                Text(
                  warning,
                  style: const TextStyle(color: DashboardStyle.amber),
                ),
            ],
          ),
        ),
        const Divider(height: 10, color: DashboardStyle.outline),
        Semantics(
          header: true,
          child: Row(
            spacing: 8,
            children: [
              const Icon(
                Icons.my_location,
                size: 19,
                color: DashboardStyle.warm,
              ),
              Flexible(
                child: Text(
                  'SCIENTIFIC OBJECTIVES',
                  style: MissionTheme.display(
                    14,
                    tracking: .6,
                  ).copyWith(color: DashboardStyle.warm),
                ),
              ),
            ],
          ),
        ),
        for (final (index, item) in objectives.indexed)
          _ObjectiveCard(
            key: ValueKey('objective-${item.id}'),
            number: (index + 1).toString().padLeft(2, '0'),
            objective: item,
            completed: completed.contains(item.id),
            toggle: loading ? null : () => onChange(item.id),
            waypoint: waypoints[item.landmarkId],
            onSelect: onSelect,
          ),
      ],
    );
  }
}

class _MissionPanorama extends StatelessWidget {
  const _MissionPanorama({required this.mission});

  final MarsMission mission;

  @override
  Widget build(BuildContext context) {
    final imagery = mission.imagery;
    final image = Image.asset(
      imagery.asset,
      semanticLabel: imagery.caption,
      fit: BoxFit.cover,
      alignment: mission.id == 'endeavour'
          ? const Alignment(.5, 0)
          : Alignment.center,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ColoredBox(
        color: DashboardStyle.panel,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              'Panorama unavailable · ${mission.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DashboardStyle.muted),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        AspectRatio(
          key: const ValueKey('mission-panorama'),
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            // The Opportunity mosaic has unfilled strips along its lower edge.
            child: mission.id == 'endeavour'
                ? Transform.scale(
                    scale: 1.2,
                    alignment: Alignment.topCenter,
                    child: image,
                  )
                : image,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${imagery.instrument} · ${imagery.credit}',
            style: const TextStyle(color: DashboardStyle.muted, fontSize: 10),
          ),
        ),
      ],
    );
  }
}

class _MissionFact extends StatelessWidget {
  const _MissionFact({
    required this.icon,
    required this.label,
    this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: DashboardStyle.surface(radius: 25),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(icon, size: 15, color: DashboardStyle.warm),
          Flexible(
            child: Text(
              label,
              semanticsLabel: semanticsLabel == null
                  ? null
                  : '$semanticsLabel · $label',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The card body toggles the checklist, and the location button selects a target.
class _ObjectiveCard extends StatelessWidget {
  const _ObjectiveCard({
    super.key,
    required this.number,
    required this.objective,
    required this.completed,
    required this.toggle,
    required this.waypoint,
    required this.onSelect,
  });

  final String number;
  final MissionObjective objective;
  final bool completed;
  final VoidCallback? toggle;
  final DemoLandmark? waypoint;
  final ValueChanged<DemoLandmark> onSelect;

  @override
  Widget build(BuildContext context) {
    final status = completed ? 'Completed' : 'Pending';
    final radius = BorderRadius.circular(15);
    final border = completed ? const Color(0xFF347A63) : DashboardStyle.outline;
    final muted = completed ? const Color(0xFFB7F6DD) : DashboardStyle.muted;
    final body = ExcludeSemantics(
      child: Row(
        spacing: 10,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(5),
            decoration: DashboardStyle.surface(
              color: DashboardStyle.inset,
              border: border,
              radius: 28,
            ),
            child: Text(
              number,
              style: MissionTheme.display(13).copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 5,
              children: [
                Text(
                  objective.label,
                  style: const TextStyle(
                    color: DashboardStyle.text,
                    fontSize: 15,
                    height: 1.38,
                  ),
                ),
                Text(status, style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
    final location = switch (waypoint) {
      final point? => OutlinedButton.icon(
        key: ValueKey('objective-location-${objective.id}'),
        onPressed: () => onSelect(point),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          backgroundColor: DashboardStyle.inset,
          foregroundColor: completed
              ? const Color(0xFFD1FBE9)
              : DashboardStyle.warm,
          side: BorderSide(color: border),
        ),
        icon: const Icon(Icons.place_outlined, size: 18),
        label: Text(
          point.name,
          textAlign: TextAlign.start,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      null => Text(
        'Location unavailable',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      enabled: toggle != null,
      toggled: completed,
      label: 'Objective $number. ${objective.label}',
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
          border: border,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            excludeFromSemantics: true,
            borderRadius: radius,
            onTap: toggle,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  if (constraints.maxWidth >= 350 * scale) {
                    return Row(
                      spacing: 10,
                      children: [
                        Expanded(flex: 3, child: body),
                        Flexible(flex: 2, child: location),
                      ],
                    );
                  }
                  return Column(
                    spacing: 7,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      body,
                      Align(alignment: Alignment.centerRight, child: location),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
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
    required this.onTeammate,
    this.onCancelSos,
  });

  final Astronaut astronaut;
  final Astronaut teammate;
  final DemoNavigation navigation;
  final AstronautTracking tracking;
  final MissionPresence presence;
  final CrewPresence? member;
  final VoidCallback? onTeammate;
  final VoidCallback? onCancelSos;

  @override
  Widget build(BuildContext context) {
    final current = member;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        DashboardPanel(
          title: 'SHARED SESSION',
          icon: Icons.link,
          children: [
            DashboardReadout(
              label: 'Connection',
              value: presence.status.mobileLabel,
            ),
            if (presence.sos case final sos? when sos.state == SosState.active)
              Text(
                'SOS ACTIVE · ${sos.sender}',
                style: const TextStyle(
                  color: DashboardStyle.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (onCancelSos != null)
              DashboardButton(
                label: 'CANCEL SOS',
                icon: Icons.warning_amber,
                emergency: true,
                height: 48,
                onPressed: onCancelSos,
              ),
            if (presence.enrollmentPending)
              const Text('Crew device setup pending.'),
            if (presence.accessDenied)
              const Text('Device authorization unavailable.'),
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
          title: '${teammate.id} · ${current == null ? 'OFFLINE' : 'ONLINE'}',
          icon: Icons.person_outline,
          children: [
            Text(teammate.fullName, style: MissionTheme.display(18)),
            if (current != null) ...[
              DashboardReadout(
                label: 'Estimated Mars position',
                value: formatMarsPosition(current.pose.mars),
              ),
              DashboardReadout(
                label: 'Estimated separation',
                value: _separation(current),
              ),
              DashboardReadout(
                label: 'Relative position',
                value: _relativePosition(
                  tracking.gridPosition(current.pose.mars) -
                      navigation.position,
                ),
              ),
              if (onTeammate != null)
                DashboardButton(
                  label: 'TARGET TEAMMATE',
                  height: 48,
                  icon: Icons.alt_route,
                  onPressed: onTeammate,
                ),
            ],
          ],
        ),
      ],
    );
  }

  String _separation(CrewPresence peer) {
    final meters = surfaceDistance(
      tracking.pose.mars,
      peer.pose.mars,
      MarsProjection.radiusMeters,
    );
    return formatNavigationDistance(meters, live: meters < 100);
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
