import 'package:flutter/material.dart';

import '../../tracking/astronaut_tracking.dart';
import '../../tracking/step_navigation.dart';

Future<void> confirmWalkingDirection(
  BuildContext context,
  AstronautTracking tracking,
) async {
  final destination = tracking.navigation.target;
  if (destination == null) return;
  final label = tracking.navigation.targetLabel;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Calibrate walking direction'),
      content: Text(
        'Tilt the screen up and point the phone’s top edge in the direction you intend to walk. '
        'Confirm to align that direction with ${label ?? 'your destination'}. '
        'Keep the phone aligned as you walk. Calibrate again if you change how you hold it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Calibrate'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return;
  final calibrated = await tracking.calibrateWalkingDirection(destination);
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
