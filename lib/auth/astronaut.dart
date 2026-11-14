/// The identity available to the mission interface after prototype sign-in.
final class Astronaut {
  /// Creates an identity with its mission roster ID and display name.
  const Astronaut({required this.id, required this.fullName});

  final String id;
  final String fullName;
}
