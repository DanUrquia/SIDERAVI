import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/firebase_presence.dart';
import '../../tracking/mission_presence.dart';
import 'dashboard_style.dart';
import 'walking_calibration.dart';

/// Adds movement, calibration, map follow and connection controls to the dashboard.
class TrackingControls extends StatelessWidget {
  const TrackingControls({
    super.key,
    required this.tracking,
    required this.presence,
    required this.onJoin,
    required this.onMovementLog,
  });

  final AstronautTracking tracking;
  final MissionPresence presence;
  final VoidCallback? onJoin;
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
      if (onJoin != null)
        DashboardButton(
          label: presence.status == ConnectionStatus.offline
              ? 'JOIN CREW'
              : 'LEAVE CREW',
          height: 46,
          icon: Icons.group_outlined,
          onPressed: onJoin,
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
        const Text('Account does not have access to this mission slot.'),
    ],
  );
}

/// Prompts for the Firebase account assigned to the current astronaut.
Future<ConnectPresence?> showCrewSignIn(
  BuildContext context,
  FirebasePresenceConfig config,
  SessionKey slot,
) => showDialog<ConnectPresence>(
  context: context,
  builder: (_) => _CrewSignIn(config: config, slot: slot),
);

/// Keeps account credentials out of the demo roster and build settings.
class _CrewSignIn extends StatefulWidget {
  const _CrewSignIn({required this.config, required this.slot});
  final FirebasePresenceConfig config;
  final SessionKey slot;

  @override
  State<_CrewSignIn> createState() => _CrewSignInState();
}

class _CrewSignInState extends State<_CrewSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Sign-in releases entered credentials when the dialog closes.
  Future<void> _submit() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your assigned crew account credentials.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final connect = await widget.config.signIn(
        widget.slot,
        _email.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop(connect);
    } catch (error) {
      if (mounted) {
        _password.clear();
        setState(() {
          _busy = false;
          _error = error is PresenceAccessDenied
              ? 'This account cannot join as ${widget.slot.astronaut}. Check your crew assignment.'
              : 'Crew sign-in failed. Check your account and connection.';
        });
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Join shared mission as ${widget.slot.astronaut}'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Crew email'),
          ),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Crew password'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error case final error?) Text(error),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('Connect'),
      ),
    ],
  );
}
