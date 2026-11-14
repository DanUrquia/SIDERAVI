import 'astronaut.dart';

/// Matches the two bundled demo credentials entirely offline.
final class PrototypeAuth {
  /// Creates the stateless prototype credential service.
  const PrototypeAuth();

  static const _roster = {'0107': DemoCrew.dan, '1412': DemoCrew.adrian};

  /// Returns an astronaut for an exact match, preserving leading zeroes.
  Astronaut? authenticate(String pin) => _roster[pin];
}
