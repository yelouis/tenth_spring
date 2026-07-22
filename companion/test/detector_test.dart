import 'package:flutter_test/flutter_test.dart';
import 'package:companion/capture/detector.dart';
import 'package:companion/capture/location_source.dart';

void main() {
  group('Visit & Corridor Detector Tests', () {
    test('Dwell under 120s produces no visit', () async {
      final detector = VisitCorridorDetector(
        visitRadiusMeters: 75.0,
        visitDwellSeconds: 120,
      );

      final visits = <DetectedVisit>[];
      detector.visitStream.listen(visits.add);

      final startTs = DateTime.now().millisecondsSinceEpoch;

      // 119s dwell
      detector.processFix(Fix(
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 10.0,
        tsUtcMs: startTs,
      ));

      detector.processFix(Fix(
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 10.0,
        tsUtcMs: startTs + 119000,
      ));

      // Move away
      detector.processFix(Fix(
        lat: 37.7800,
        lon: -122.4194,
        accuracyM: 10.0,
        tsUtcMs: startTs + 130000,
      ));

      detector.flush();
      await Future.delayed(Duration.zero);

      expect(visits, isEmpty);
      detector.dispose();
    });

    test('Dwell of 121s produces a fuzzed visit', () async {
      final detector = VisitCorridorDetector(
        visitRadiusMeters: 75.0,
        visitDwellSeconds: 120,
      );

      final visits = <DetectedVisit>[];
      detector.visitStream.listen(visits.add);

      final startTs = DateTime.now().millisecondsSinceEpoch;

      detector.processFix(Fix(
        lat: 37.774929,
        lon: -122.419416,
        accuracyM: 10.0,
        tsUtcMs: startTs,
      ));

      detector.processFix(Fix(
        lat: 37.774930,
        lon: -122.419415,
        accuracyM: 10.0,
        tsUtcMs: startTs + 121000,
      ));

      // Move away to trigger visit emission
      detector.processFix(Fix(
        lat: 37.785000,
        lon: -122.419416,
        accuracyM: 10.0,
        tsUtcMs: startTs + 130000,
      ));

      detector.flush();
      await Future.delayed(Duration.zero);

      expect(visits.length, equals(1));
      expect(visits.first.fuzzedPoint.lat, equals(37.775));
      expect(visits.first.fuzzedPoint.lon, equals(-122.419));
      expect(visits.first.dwellSeconds, equals(121));

      detector.dispose();
    });

    test('Fixes with accuracy > 100m are dropped', () async {
      final detector = VisitCorridorDetector(maxAccuracyM: 100.0);

      final visits = <DetectedVisit>[];
      detector.visitStream.listen(visits.add);

      final startTs = DateTime.now().millisecondsSinceEpoch;

      // Good fix
      detector.processFix(Fix(
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 10.0,
        tsUtcMs: startTs,
      ));

      // Noisy fix (150m accuracy) - ignored
      detector.processFix(Fix(
        lat: 37.8000,
        lon: -122.5000,
        accuracyM: 150.0,
        tsUtcMs: startTs + 60000,
      ));

      // Good fix back at original location
      detector.processFix(Fix(
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 10.0,
        tsUtcMs: startTs + 130000,
      ));

      detector.flush();
      await Future.delayed(Duration.zero);

      expect(visits.length, equals(1));
      detector.dispose();
    });
  });
}
