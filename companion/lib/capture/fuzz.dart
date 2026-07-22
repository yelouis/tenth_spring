import 'dart:math';

/// Representation of a coarse 2D coordinate.
class LatLon {
  final double lat;
  final double lon;

  const LatLon(this.lat, this.lon);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLon &&
          runtimeType == other.runtimeType &&
          (lat - other.lat).abs() < 1e-6 &&
          (lon - other.lon).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(
        (lat * 1000).round(),
        (lon * 1000).round(),
      );

  @override
  String toString() => 'LatLon($lat, $lon)';
}

/// Fuzzes a raw coordinate point to 3 decimal places (~110m precision).
/// This is the ONLY boundary where raw coordinates are converted before storage/sync.
LatLon fuzzPoint(double rawLat, double rawLon) {
  final fLat = double.parse(rawLat.toStringAsFixed(3));
  final fLon = double.parse(rawLon.toStringAsFixed(3));
  return LatLon(fLat, fLon);
}

/// Home location fuzzing: snaps raw coordinate to a coarse 300m grid cell ID.
/// Raw home location is NEVER persisted.
String fuzzHome(double rawLat, double rawLon, {double homeFuzzMeters = 300.0}) {
  // Approximate conversion: 1 deg lat ~ 111,000m
  final deltaLatDeg = homeFuzzMeters / 111000.0;
  final deltaLonDeg = homeFuzzMeters / (111000.0 * cos(rawLat * pi / 180.0));

  final cellY = (rawLat / deltaLatDeg).floor();
  final cellX = (rawLon / deltaLonDeg).floor();

  return 'home_cell_${cellX}_$cellY';
}

/// Simple Haversine distance in meters between two points.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0; // Earth radius in meters
  final dLat = (lat2 - lat1) * pi / 180.0;
  final dLon = (lon2 - lon1) * pi / 180.0;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180.0) *
          cos(lat2 * pi / 180.0) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}
