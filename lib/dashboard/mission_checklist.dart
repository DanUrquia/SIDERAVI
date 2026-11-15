import 'dart:ui';

import '../missions/mission.dart';
import '../sensors/sensor_service.dart';
import 'mission_map_config.dart';

/// One item from the mission briefing and its optional operational waypoint.
typedef MissionObjective = ({
  String id,
  String label,
  String? waypoint,
  Offset? position,
});

List<MissionObjective> missionObjectives(
  MarsMission mission,
  MissionMapConfig map,
) {
  if (mission.id == 'jezero') {
    final outcrop = map.landmarks.firstWhere(
      (landmark) => landmark.name == 'Delta outcrop',
    );
    return [
      (
        id: 'survey-delta-margin',
        label: 'Survey the delta margin',
        waypoint: outcrop.name,
        position: outcrop.position,
      ),
      (
        id: 'log-sediment-layers',
        label: 'Log three changes in the exposed sediment layers',
        waypoint: null,
        position: null,
      ),
      (
        id: 'return-to-base',
        label: 'Return to habitat base',
        waypoint: 'Habitat base',
        position: map.base,
      ),
    ];
  }
  return [
    (
      id: 'briefing-objective',
      label: mission.objective,
      waypoint: null,
      position: null,
    ),
  ];
}

/// Stores only task IDs on the device, scoped to a mission and astronaut.
final class MissionChecklistStore {
  const MissionChecklistStore(this.scope);

  final String scope;

  Future<Set<String>> read() async =>
      (await sensorDiagnosticsChannel.invokeListMethod<String>(
                'readMissionChecklist',
                scope,
              ) ??
              [])
          .toSet();

  Future<void> write(Set<String> completed) =>
      sensorDiagnosticsChannel.invokeMethod<void>('writeMissionChecklist', {
        'scope': scope,
        'completed': completed.toList()..sort(),
      });
}
