import 'package:flutter/material.dart';

import '../../missions/mission.dart';
import '../mission_theme.dart';

/// Displays the current mission's briefing and keeps Start Mission reachable.
class MissionInformationPanel extends StatelessWidget {
  /// Receives the same mission and catalog index shown on the photo panel.
  const MissionInformationPanel({
    super.key,
    required this.mission,
    required this.index,
    required this.total,
    required this.onStart,
    required this.bounded,
  });

  final MarsMission mission;
  final int index;
  final int total;
  final VoidCallback onStart;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final briefing = _briefing();
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C3446), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (bounded)
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.only(bottom: 6),
                child: briefing,
              ),
            )
          else
            briefing,
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF303748)),
          const SizedBox(height: 12),
          Row(
            spacing: 9,
            children: [
              for (var dot = 0; dot < total; dot++)
                Icon(
                  Icons.circle,
                  size: dot == index ? 10 : 7,
                  color: dot == index
                      ? MissionTheme.orange
                      : MissionTheme.outline,
                ),
              Flexible(
                child: Text(
                  'MISSION ${index + 1} OF $total',
                  style: MissionTheme.display(
                    12,
                    tracking: .9,
                  ).copyWith(color: MissionTheme.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _StartMissionButton(onStart: onStart),
        ],
      ),
    );
  }

  /// Lays out the mission description, objective and four briefing facts.
  Widget _briefing() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 15,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            mission.subtitle.toUpperCase(),
            style: MissionTheme.display(
              13,
              tracking: 1.7,
            ).copyWith(color: MissionTheme.warmOrange),
          ),
          Semantics(
            header: true,
            child: Text(
              mission.title,
              style: MissionTheme.display(35, tracking: -.7),
            ),
          ),
        ],
      ),
      _BriefingCard(
        child: Text(
          mission.description,
          style: const TextStyle(
            color: MissionTheme.muted,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ),
      _BriefingCard(
        color: const Color(0xFF171F32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              spacing: 8,
              children: [
                const Icon(
                  Icons.gps_fixed,
                  size: 17,
                  color: MissionTheme.warmOrange,
                ),
                Flexible(
                  child: Text(
                    'MISSION OBJECTIVE',
                    style: MissionTheme.display(13, tracking: 1.15),
                  ),
                ),
              ],
            ),
            Text(
              mission.objective,
              style: const TextStyle(
                color: MissionTheme.muted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final facts = [
            _MissionFact(
              label: 'SIMULATED DIFFICULTY',
              child: DifficultyDisplay(difficulty: mission.difficulty),
            ),
            _MissionFact(
              label: 'SIMULATED RADIUS',
              child: Text('${mission.radiusKm.toStringAsFixed(1)} km'),
            ),
            _MissionFact(
              label: 'ELEVATION / RELIEF',
              child: Text(mission.elevation ?? 'Elevation data pending'),
            ),
            _MissionFact(label: 'MISSION TYPE', child: Text(mission.type)),
          ];
          if (constraints.maxWidth < 250) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: facts,
            );
          }
          return Column(
            spacing: 10,
            children: [
              for (var slot = 0; slot < facts.length; slot += 2)
                IntrinsicHeight(
                  child: Row(
                    spacing: 10,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: facts[slot]),
                      Expanded(child: facts[slot + 1]),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// Names the simulated difficulty using a text label and a matching color.
class DifficultyDisplay extends StatelessWidget {
  /// Displays a level from the SIDERA VI simulated difficulty scale.
  const DifficultyDisplay({super.key, required this.difficulty});

  final MissionDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      MissionDifficulty.easy => MissionTheme.ready,
      MissionDifficulty.moderate => const Color(0xFFF9C862),
      MissionDifficulty.challenging => MissionTheme.warmOrange,
      MissionDifficulty.hard => MissionTheme.denied,
      MissionDifficulty.extreme => const Color(0xFFF2A9E4),
    };
    return Row(
      spacing: 7,
      children: [
        Icon(Icons.circle, size: 7, color: color),
        Flexible(
          child: Text(difficulty.label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

/// Displays one labeled value in the briefing facts grid.
class _MissionFact extends StatelessWidget {
  const _MissionFact({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => _BriefingCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        Text(
          label,
          style: MissionTheme.display(
            11,
            tracking: 1,
          ).copyWith(color: MissionTheme.muted),
        ),
        DefaultTextStyle(
          style: MissionTheme.display(
            15,
          ).copyWith(height: 1.2, color: MissionTheme.text),
          child: child,
        ),
      ],
    ),
  );
}

/// Shares the inset briefing panel treatment across descriptive content.
class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.child,
    this.color = const Color(0xFF0E1522),
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: const Color(0xFF293143)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

/// Presents the primary mission action with the orange cockpit treatment.
class _StartMissionButton extends StatelessWidget {
  const _StartMissionButton({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF36A36), Color(0xFFC7461F)],
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x48FF5826), blurRadius: 22)],
    ),
    child: SizedBox(
      height: 72,
      child: FilledButton(
        onPressed: onStart,
        style: MissionTheme.control(
          fill: Colors.transparent,
          border: const Color(0xFFD65B2E),
          foreground: const Color(0xFF190C09),
          elevation: 0,
          radius: 14,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            spacing: 12,
            children: [
              const Icon(Icons.arrow_forward, size: 27),
              Text(
                'START MISSION',
                style: MissionTheme.display(21, tracking: 1.1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
