import 'package:flutter/material.dart';

import 'sos_emergency_dialog.dart';

Future<bool?> confirmReturnToHabitatBase(
  BuildContext context, {
  bool tablet = false,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Return to habitat base?'),
    content: Text(
      'Start direct guidance to Habitat Base. Keep the '
      '${tablet ? 'iPad' : 'phone'}’s top edge pointed in your walking direction.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Return to base'),
      ),
    ],
  ),
);

Future<bool?> confirmCrewSos(BuildContext context) => showDialog<bool>(
  context: context,
  barrierColor: SosEmergencyDialog.barrierColor,
  animationStyle: SosEmergencyDialog.animationStyle(context),
  builder: (context) => SosEmergencyDialog.confirm(
    key: const ValueKey('confirm-crew-sos'),
    onPrimary: () => Navigator.pop(context, true),
    onSecondary: () => Navigator.pop(context, false),
  ),
);
