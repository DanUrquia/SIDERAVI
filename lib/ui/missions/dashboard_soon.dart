import 'package:flutter/material.dart';

import '../../auth/astronaut.dart';
import '../../missions/mission.dart';
import '../mission_theme.dart';

/// Shows the confirmed mission and astronaut until the dashboard is available.
class DashboardSoon extends StatelessWidget {
  /// Receives the mission and astronaut from the active session.
  const DashboardSoon({
    super.key,
    required this.astronaut,
    required this.mission,
  });

  final Astronaut astronaut;
  final MarsMission mission;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MissionTheme.black,
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 156,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            MissionTheme.orange,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Dashboard soon.',
                      style: MissionTheme.display(60),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Mission: ${mission.title}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 21),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Astronaut: ${astronaut.fullName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MissionTheme.muted,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: 330,
                    height: 70,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: MissionTheme.control(
                        fill: const Color(0xFF251915),
                        border: const Color(0xFFC97958),
                        elevation: 0,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'BACK TO MISSIONS',
                          style: MissionTheme.display(19, tracking: 1.1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
