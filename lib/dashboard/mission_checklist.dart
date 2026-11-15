import '../sensors/sensor_service.dart';

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
