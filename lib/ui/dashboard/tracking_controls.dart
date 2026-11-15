import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/mission_presence.dart';
import 'dashboard_style.dart';
import 'walking_calibration.dart';

/// Adds movement, calibration, map follow and connection controls to the dashboard.
class TrackingControls extends StatelessWidget {
  const TrackingControls({
    super.key,
    required this.tracking,
    required this.presence,
    required this.onMovementLog,
  });

  final AstronautTracking tracking;
  final MissionPresence presence;
  final VoidCallback onMovementLog;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final mode in TrackingMode.values)
        Semantics(
          selected: tracking.mode == mode,
          child: DashboardButton(
            label: mode.label,
            height: 46,
            icon: mode == TrackingMode.live ? Icons.sensors : Icons.route,
            primary: tracking.mode == mode,
            onPressed: () => tracking.selectMode(mode),
          ),
        ),
      DashboardButton(
        label: tracking.navigation.live
            ? 'CALIBRATE WALKING DIRECTION'
            : 'CALIBRATE',
        height: 46,
        icon: Icons.explore_outlined,
        onPressed: !tracking.navigation.live
            ? tracking.calibrate
            : tracking.canCalibrateWalking
            ? () => confirmWalkingDirection(context, tracking)
            : null,
      ),
      Semantics(
        selected: tracking.follow,
        child: DashboardButton(
          label: 'FOLLOW ASTRONAUT',
          height: 46,
          icon: tracking.follow ? Icons.gps_fixed : Icons.gps_not_fixed,
          primary: tracking.follow,
          onPressed: () => tracking.setFollow(!tracking.follow),
        ),
      ),
      Text(
        presence.status.label,
        style: TextStyle(
          color: presence.status == ConnectionStatus.connected
              ? DashboardStyle.green
              : DashboardStyle.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      DashboardButton(
        label: 'MOVEMENT LOG',
        height: 46,
        icon: Icons.receipt_long_outlined,
        onPressed: onMovementLog,
      ),
      if (presence.accessDenied)
        const Text('Device authorization unavailable.'),
    ],
  );
}
