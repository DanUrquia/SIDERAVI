import 'package:flutter/material.dart';

import 'mission_theme.dart';

/// A three-column keypad for masked PIN entry without a system keyboard.
class PinKeypad extends StatelessWidget {
  /// Binds the digit keys and edit controls to the current PIN entry.
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onClear,
    required this.onBackspace,
    required this.keyHeight,
    required this.gap,
  });

  final ValueChanged<String>? onDigit;
  final VoidCallback? onClear;
  final VoidCallback? onBackspace;
  final double keyHeight;
  final double gap;

  /// Builds a digit or editing key with the same full-size touch target.
  Widget _key(String label, {VoidCallback? onPressed, bool utility = false}) {
    final content = switch (label) {
      'Backspace' => Icon(Icons.backspace_outlined, size: keyHeight * .34),
      _ => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: MissionTheme.display(
            keyHeight * (utility ? .25 : .39),
            tracking: utility ? 1.2 : 0,
          ),
        ),
      ),
    };
    return FilledButton(
      onPressed: onPressed,
      style: MissionTheme.control(
        fill: utility ? MissionTheme.utilityFace : MissionTheme.keyFace,
        border: MissionTheme.outline,
        foreground: utility ? MissionTheme.muted : MissionTheme.text,
        radius: keyHeight * .18,
      ),
      child: Semantics(label: label, excludeSemantics: true, child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['CLEAR', '0', 'Backspace'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: gap,
      children: [
        for (final row in rows)
          SizedBox(
            height: keyHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: gap,
              children: [
                for (final label in row)
                  Expanded(
                    child: switch (label) {
                      'CLEAR' => _key(label, onPressed: onClear, utility: true),
                      'Backspace' => _key(
                        label,
                        onPressed: onBackspace,
                        utility: true,
                      ),
                      _ => _key(
                        label,
                        onPressed: onDigit == null
                            ? null
                            : () => onDigit!(label),
                      ),
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
