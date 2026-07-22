import 'dart:async';
import 'fuzz.dart';
import 'location_source.dart';

class DetectedVisit {
  final LatLon fuzzedPoint;
  final int startedAtTsMs;
  final int dwellSeconds;

  const DetectedVisit({
    required this.fuzzedPoint,
    required this.startedAtTsMs,
    required this.dwellSeconds,
  });
}

class DetectedCorridorPoint {
  final LatLon fuzzedPoint;
  final int timestampTsMs;

  const DetectedCorridorPoint({
    required this.fuzzedPoint,
    required this.timestampTsMs,
  });
}

class _Cluster {
  double sumLat;
  double sumLon;
  int count;
  int startTsMs;
  int lastTsMs;
  Fix lastFix;

  _Cluster(Fix firstFix)
      : sumLat = firstFix.lat,
        sumLon = firstFix.lon,
        count = 1,
        startTsMs = firstFix.tsUtcMs,
        lastTsMs = firstFix.tsUtcMs,
        lastFix = firstFix;

  double get centroidLat => sumLat / count;
  double get centroidLon => sumLon / count;
  int get durationSeconds => (lastTsMs - startTsMs) ~/ 1000;

  void add(Fix fix) {
    sumLat += fix.lat;
    sumLon += fix.lon;
    count++;
    lastTsMs = fix.tsUtcMs;
    lastFix = fix;
  }
}

class VisitCorridorDetector {
  final double visitRadiusMeters;
  final int visitDwellSeconds;
  final double maxAccuracyM;
  final double corridorSampleMeters;

  _Cluster? _cluster;
  final _visitController = StreamController<DetectedVisit>.broadcast();
  final _corridorController = StreamController<DetectedCorridorPoint>.broadcast();

  VisitCorridorDetector({
    this.visitRadiusMeters = 75.0,
    this.visitDwellSeconds = 120,
    this.maxAccuracyM = 100.0,
    this.corridorSampleMeters = 25.0,
  });

  Stream<DetectedVisit> get visitStream => _visitController.stream;
  Stream<DetectedCorridorPoint> get corridorStream => _corridorController.stream;

  void processFix(Fix fix) {
    if (fix.accuracyM > maxAccuracyM) {
      return; // Drop noisy fixes
    }

    if (_cluster == null) {
      _cluster = _Cluster(fix);
      return;
    }

    final dist = haversineMeters(
      fix.lat,
      fix.lon,
      _cluster!.centroidLat,
      _cluster!.centroidLon,
    );

    if (dist <= visitRadiusMeters) {
      _cluster!.add(fix);
    } else {
      // Dwell ended or movement detected
      if (_cluster!.durationSeconds >= visitDwellSeconds) {
        final fuzzed = fuzzPoint(_cluster!.centroidLat, _cluster!.centroidLon);
        _visitController.add(DetectedVisit(
          fuzzedPoint: fuzzed,
          startedAtTsMs: _cluster!.startTsMs,
          dwellSeconds: _cluster!.durationSeconds,
        ));
      }

      _resampleAndEmitCorridor(_cluster!.lastFix, fix);
      _cluster = _Cluster(fix);
    }
  }

  void flush() {
    if (_cluster != null && _cluster!.durationSeconds >= visitDwellSeconds) {
      final fuzzed = fuzzPoint(_cluster!.centroidLat, _cluster!.centroidLon);
      _visitController.add(DetectedVisit(
        fuzzedPoint: fuzzed,
        startedAtTsMs: _cluster!.startTsMs,
        dwellSeconds: _cluster!.durationSeconds,
      ));
      _cluster = null;
    }
  }

  void _resampleAndEmitCorridor(Fix startFix, Fix endFix) {
    final dist = haversineMeters(
      startFix.lat,
      startFix.lon,
      endFix.lat,
      endFix.lon,
    );

    if (dist <= 0) return;

    final steps = (dist / corridorSampleMeters).ceil();
    final timeStepMs = (endFix.tsUtcMs - startFix.tsUtcMs) / (steps > 0 ? steps : 1);

    for (int i = 0; i <= steps; i++) {
      final t = steps == 0 ? 0.0 : i / steps;
      final lat = startFix.lat + t * (endFix.lat - startFix.lat);
      final lon = startFix.lon + t * (endFix.lon - startFix.lon);
      final ts = (startFix.tsUtcMs + t * timeStepMs).round();

      final fuzzed = fuzzPoint(lat, lon);
      _corridorController.add(DetectedCorridorPoint(
        fuzzedPoint: fuzzed,
        timestampTsMs: ts,
      ));
    }
  }

  void dispose() {
    _visitController.close();
    _corridorController.close();
  }
}
