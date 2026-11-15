import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/step_navigation.dart';

enum _WalkingReference { mapNorth, destination }

Future<void> confirmWalkingDirection(
  BuildContext context,
  AstronautTracking tracking,
) async {
  final destination = tracking.navigation.target;
  final canAlignToTarget =
      destination != null && destination != tracking.navigation.position;
  final canAlignToNorth = tracking.automaticPhysical;
  if (!canAlignToNorth && !canAlignToTarget) return;
  final label = tracking.navigation.targetLabel ?? 'your destination';
  final alignment = switch ((canAlignToNorth, canAlignToTarget)) {
    (true, true) =>
      'Choose whether to align that direction with local map north or $label.',
    (true, false) => 'Use that direction as local map north.',
    _ => 'Confirm to align that direction with $label.',
  };
  final confirmLabel = switch ((canAlignToNorth, canAlignToTarget)) {
    (true, true) => 'Align to destination',
    (true, false) => 'Use map north',
    _ => 'Calibrate',
  };
  final reference = await showDialog<_WalkingReference>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Calibrate walking direction'),
      content: Text(
        'Tilt the screen up and point the phone’s top edge in the direction you intend to walk. '
        '$alignment Keep the phone aligned as you walk.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (canAlignToNorth && canAlignToTarget)
          TextButton(
            onPressed: () => Navigator.pop(context, _WalkingReference.mapNorth),
            child: const Text('Use map north'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            canAlignToTarget
                ? _WalkingReference.destination
                : _WalkingReference.mapNorth,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (!context.mounted || reference == null) return;
  final calibrated = await tracking.calibrateWalkingDirection(
    reference == _WalkingReference.destination ? destination : null,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          calibrated
              ? 'Walking direction calibrated.'
              : 'Hold the phone with its top edge pointing forward and try again.',
        ),
      ),
    );
  }
}

Future<void> configureStride(
  BuildContext context,
  AstronautTracking tracking,
) async {
  final form = GlobalKey<FormState>();
  var value = tracking.stride;
  final meters = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Stride length'),
      scrollable: true,
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const Text(
              'Divide a measured walking distance by the number of steps. '
              'The starting estimate is 0.70 m per step.',
            ),
            TextFormField(
              initialValue: value.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Meters per step'),
              validator: (text) {
                final entered = double.tryParse(
                  text?.replaceAll(',', '.') ?? '',
                );
                if (entered == null || !StepNavigation.validStride(entered)) {
                  return 'Enter a value from 0.25 to 1.50 m.';
                }
                value = entered;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState?.validate() == true) {
              Navigator.pop(context, value);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (meters == null || !context.mounted) return;
  final saved = await tracking.saveStride(meters);
  if (!saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save the stride length.')),
    );
  }
}
