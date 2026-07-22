import 'dart:async';

/// In-memory full-precision GPS fix.
/// CRITICAL PRIVACY GUARD: This full-precision fix lives ONLY in volatile memory
/// inside the capture pipeline. It must NEVER be persisted to disk or transmitted
/// over the network.
class Fix {
  final double lat;
  final double lon;
  final double accuracyM;
  final int tsUtcMs;
  final double? speedMps;

  const Fix({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.tsUtcMs,
    this.speedMps,
  });

  @override
  String toString() =>
      'Fix(lat: $lat, lon: $lon, accuracy: ${accuracyM}m, ts: $tsUtcMs)';
}

/// OS visit event abstraction (e.g. iOS CLVisit hint).
class OsVisit {
  final double lat;
  final double lon;
  final int arrivalTsMs;
  final int departureTsMs;

  const OsVisit({
    required this.lat,
    required this.lon,
    required this.arrivalTsMs,
    required this.departureTsMs,
  });
}

/// Abstract Location Source seam.
/// Both production OsLocationSource and test/debug GpxReplaySource implement this.
abstract class LocationSource {
  Future<void> start();
  Future<void> stop();
  Stream<Fix> fixes();
  Stream<OsVisit>? nativeVisits();
}
