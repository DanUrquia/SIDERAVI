import 'package:flutter/services.dart';

const sensorDiagnosticsChannel = MethodChannel('sidera_vi/sensor_diagnostics');

/// Transport for foreground diagnostic commands and sensor batches.
abstract interface class SensorService {
  /// Sends one command to the local sensor bridge.
  Future<void> command(String name, [String? argument]);

  /// Reads capabilities and drains the current native sample batch.
  Future<Map<String, Object?>> snapshot();
}

/// Talks directly to Core Location and Core Motion through the Runner.
final class IpadSensorService implements SensorService {
  /// Creates the channel client without starting either sensor.
  const IpadSensorService();

  @override
  Future<void> command(String name, [String? argument]) =>
      sensorDiagnosticsChannel.invokeMethod<void>(name, argument);

  @override
  Future<Map<String, Object?>> snapshot() async =>
      await sensorDiagnosticsChannel.invokeMapMethod<String, Object?>(
        'snapshot',
      ) ??
      {};
}
