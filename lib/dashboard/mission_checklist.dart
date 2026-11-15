import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Holds a single astronaut's device-local checklist across dashboard layouts.
final class MissionChecklist extends ChangeNotifier {
  MissionChecklist(String scope) : _storage = MissionChecklistStore(scope);

  final MissionChecklistStore _storage;
  Set<String> completed = {};
  bool loading = true;
  String? warning;
  bool _saving = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      completed = await _storage.read();
    } on PlatformException {
      warning = 'Checklist storage unavailable.';
    } on MissingPluginException {
      warning = 'Checklist lasts for this visit.';
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(String id) async {
    if (loading || _saving || _disposed) return;
    _saving = true;
    completed = {...completed};
    if (!completed.remove(id)) completed.add(id);
    notifyListeners();
    final previousWarning = warning;
    try {
      await Future.wait([
        _storage.write(completed),
        Future<void>.delayed(const Duration(milliseconds: 160)),
      ]);
      warning = null;
    } on PlatformException {
      warning = 'Could not save the checklist on this device.';
    } on MissingPluginException {
      warning = 'Checklist lasts for this visit.';
    } finally {
      _saving = false;
    }
    if (!_disposed && warning != previousWarning) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
