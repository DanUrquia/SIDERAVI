/// SIDERA VI's educational difficulty scale for the simulated objectives.
enum MissionDifficulty {
  easy,
  moderate,
  challenging,
  hard,
  extreme;

  /// Human-readable label for the mission briefing.
  String get label => name[0].toUpperCase() + name.substring(1);
}

/// A planetocentric reference point with an east-positive longitude.
final class MarsCoordinates {
  /// Creates a reference using latitude and longitude in decimal degrees.
  const MarsCoordinates(this.latitude, this.eastLongitude);

  final double latitude;
  final double eastLongitude;

  /// Rounds the regional reference for the briefing display.
  String get label =>
      '${latitude.abs().toStringAsFixed(2)}° ${latitude < 0 ? 'S' : 'N'}'
      '  ·  ${eastLongitude.toStringAsFixed(2)}° E';
}

/// An attributed rover photograph or orbital mosaic bundled with the app.
final class MissionImagery {
  /// Records the original NASA release alongside the display asset.
  const MissionImagery({
    required this.asset,
    required this.instrument,
    required this.caption,
    required this.credit,
    required this.sourceUrl,
  });

  final String asset;
  final String instrument;
  final String caption;
  final String credit;
  final String sourceUrl;
}

/// A local briefing for a simulated expedition in a real Martian region.
final class MarsMission {
  /// Combines the simulation parameters with sourced geographic context.
  const MarsMission({
    required this.id,
    required this.title,
    required this.region,
    required this.subtitle,
    required this.description,
    required this.objective,
    required this.difficulty,
    required this.coordinates,
    required this.radiusKm,
    required this.type,
    required this.imagery,
    required this.geographySourceUrl,
    this.elevation,
  });

  final String id;
  final String title;
  final String region;
  final String subtitle;
  final String description;
  final String objective;
  final MissionDifficulty difficulty;
  final MarsCoordinates coordinates;
  final double radiusKm;
  final String type;
  final MissionImagery imagery;
  final String geographySourceUrl;
  final String? elevation;
}
