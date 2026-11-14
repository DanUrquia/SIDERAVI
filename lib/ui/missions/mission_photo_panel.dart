import 'package:flutter/material.dart';

import '../../missions/mission.dart';
import '../mission_theme.dart';

/// Frames genuine Mars imagery with the regional reference and photo credit.
class MissionPhotoPanel extends StatelessWidget {
  /// Receives the current mission and available browser directions.
  const MissionPhotoPanel({
    super.key,
    required this.mission,
    required this.index,
    required this.onPrevious,
    required this.onNext,
  });

  final MarsMission mission;
  final String index;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final imagery = mission.imagery;
    // Keep overlaid captions proportionate to the fixed photograph frame.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4B4948)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                imagery.asset,
                key: ValueKey(imagery.asset),
                semanticLabel: imagery.caption,
                fit: BoxFit.cover,
                alignment: mission.id == 'endeavour'
                    ? const Alignment(.5, 0)
                    : Alignment.center,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .24, .61, .9, 1],
                    colors: [
                      Color(0xB30A111C),
                      Colors.transparent,
                      Color(0x150A111C),
                      Color(0xE00B1320),
                      Color(0xFF0B1320),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      const Flexible(
                        child: _PhotoLabel(
                          label: 'AVAILABLE',
                          status: true,
                          color: MissionTheme.ready,
                        ),
                      ),
                      Flexible(
                        flex: 2,
                        child: _PhotoLabel(
                          label: 'REGION REF\n${mission.coordinates.label}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MissionNavigationControls(
                  onPrevious: onPrevious,
                  onNext: onNext,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 12,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 5,
                          children: [
                            Text(
                              imagery.instrument.toUpperCase(),
                              style: MissionTheme.display(
                                13,
                                tracking: 1.1,
                              ).copyWith(color: MissionTheme.warmOrange),
                            ),
                            Text(
                              imagery.caption,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              imagery.credit,
                              style: const TextStyle(
                                color: MissionTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PhotoLabel(label: index),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Offers large, labeled previous and next controls on the photograph.
class MissionNavigationControls extends StatelessWidget {
  /// Disabled callbacks signal the start and end of the catalog.
  const MissionNavigationControls({
    super.key,
    required this.onPrevious,
    required this.onNext,
  });

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _arrow('Previous mission', Icons.chevron_left, onPrevious),
        _arrow('Next mission', Icons.chevron_right, onNext),
      ],
    );
  }

  /// Gives both arrows an equally large hit area and a muted disabled state.
  Widget _arrow(String label, IconData icon, VoidCallback? onPressed) {
    return Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: 56,
        child: FilledButton(
          onPressed: onPressed,
          style:
              MissionTheme.control(
                fill: const Color(0xF1111726),
                border: MissionTheme.outline,
                radius: 28,
                elevation: 0,
              ).copyWith(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? const Color(0xFF788395)
                      : MissionTheme.text,
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
          child: Icon(icon, size: 31),
        ),
      ),
    );
  }
}

/// Provides stable contrast for status, coordinates and index over photography.
class _PhotoLabel extends StatelessWidget {
  const _PhotoLabel({
    required this.label,
    this.color = MissionTheme.text,
    this.status = false,
  });

  final String label;
  final Color color;
  final bool status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6141B29),
        border: Border.all(color: const Color(0xFF444B56)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (status) Icon(Icons.circle, size: 7, color: color),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: MissionTheme.display(
                  12,
                  tracking: .65,
                ).copyWith(color: color, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
