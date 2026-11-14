/// The identity available to the mission interface after prototype sign-in.
final class Astronaut {
  /// Creates an identity with its mission roster ID and display name.
  const Astronaut({required this.id, required this.fullName});

  final String id;
  final String fullName;

  /// Initials for the mission header avatar, derived from the roster name.
  String get initials => fullName
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .join();
}

/// Demo crew identities shared by authentication and the mission roster.
abstract final class DemoCrew {
  static const dan = Astronaut(id: 'ARES-01', fullName: 'Dan Urquía');
  static const adrian = Astronaut(id: 'ARES-02', fullName: 'Adrian Flores');

  /// The offline demonstration roster, independent of the PIN lookup.
  static const roster = [dan, adrian];
}
