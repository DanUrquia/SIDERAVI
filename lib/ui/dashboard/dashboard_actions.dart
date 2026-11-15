import 'package:flutter/material.dart';

import '../../dashboard/demo_navigation.dart';
import '../mission_theme.dart';
import 'dashboard_style.dart';

/// Exposes the three local exploration actions in a dedicated bottom bar.
class DashboardActions extends StatelessWidget {
  /// Reflects the current paused and demo SOS states.
  const DashboardActions({
    super.key,
    required this.navigation,
    required this.onPause,
    required this.onPing,
    required this.onSos,
  });

  final DemoNavigation navigation;
  final VoidCallback onPause;
  final VoidCallback onPing;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      Expanded(
        child: DashboardButton(
          label: navigation.paused ? 'RESUME EXPLORATION' : 'PAUSE EXPLORATION',
          icon: navigation.paused
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded,
          primary: navigation.paused && !navigation.sos,
          onPressed: navigation.sos ? null : onPause,
        ),
      ),
      Expanded(
        child: DashboardButton(
          label: 'SEND PING',
          icon: Icons.sensors,
          onPressed: navigation.sos ? null : onPing,
        ),
      ),
      Expanded(
        child: DashboardButton(
          label: navigation.sos ? 'CANCEL DEMO SOS' : 'SOS',
          icon: Icons.warning_amber_rounded,
          emergency: true,
          onPressed: onSos,
        ),
      ),
    ],
  );
}

/// Asks for one of the three local ping marker types.
Future<DemoPingType?> chooseDemoPing(BuildContext context) =>
    showDialog<DemoPingType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: DashboardStyle.panel,
        title: const Text('Send demo ping'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              const Text(
                'Place a local marker at your destination or current position.',
              ),
              for (final type in DemoPingType.values)
                DashboardButton(
                  label: type.label,
                  icon: switch (type) {
                    DemoPingType.location => Icons.place_outlined,
                    DemoPingType.item => Icons.inventory_2_outlined,
                    DemoPingType.danger => Icons.warning_amber_rounded,
                  },
                  onPressed: () => Navigator.of(dialogContext).pop(type),
                ),
            ],
          ),
        ),
        scrollable: true,
        actions: [
          DashboardButton(
            label: 'CANCEL',
            icon: Icons.close,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );

/// Requires confirmation before entering the dashboard's demo emergency state.
Future<bool?> confirmDemoSos(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    backgroundColor: DashboardStyle.panel,
    title: const Text('Activate demo SOS?'),
    content: const Text(
      'This highlights your position and pauses exploration on this device.',
    ),
    scrollable: true,
    actions: [
      DashboardButton(
        label: 'CANCEL',
        icon: Icons.close,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
      DashboardButton(
        label: 'ACTIVATE DEMO SOS',
        icon: Icons.warning_amber_rounded,
        emergency: true,
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
    ],
  ),
);

/// Describes the emergency inside the same dashboard layout.
class DemoSosBanner extends StatelessWidget {
  /// Names the active astronaut whose marker is highlighted.
  const DemoSosBanner({super.key, required this.astronautName});

  final String astronautName;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 15),
      decoration: DashboardStyle.surface(
        color: DashboardStyle.emergency,
        border: DashboardStyle.danger,
      ),
      child: Row(
        spacing: 14,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: DashboardStyle.danger,
            size: 27,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  'DEMO SOS ACTIVE',
                  style: MissionTheme.display(17, tracking: .8),
                ),
                Text(
                  '$astronautName’s position is highlighted. Exploration is paused.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
