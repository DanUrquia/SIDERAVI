import 'package:flutter/services.dart';

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

  static const _channel = MethodChannel('sidera_vi/sensor_diagnostics');

  @override
  Future<void> command(String name, [String? argument]) =>
      _channel.invokeMethod<void>(name, argument);

  @override
  Future<Map<String, Object?>> snapshot() async =>
      await _channel.invokeMapMethod<String, Object?>('snapshot') ?? {};
}
