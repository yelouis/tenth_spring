import 'package:flutter_test/flutter_test.dart';
import 'package:companion/capture/fuzz.dart';

void main() {
  group('Fuzzing & Privacy Tests', () {
    test('fuzzPoint rounds to 3 decimal places', () {
      final rawLat = 37.774929;
      final rawLon = -122.419416;

      final fuzzed = fuzzPoint(rawLat, rawLon);

      expect(fuzzed.lat, equals(37.775));
      expect(fuzzed.lon, equals(-122.419));
    });

    test('fuzzPoint is deterministic and idempotent', () {
      final p1 = fuzzPoint(37.7749, -122.4194);
      final p2 = fuzzPoint(p1.lat, p1.lon);

      expect(p1, equals(p2));
    });

    test('fuzzHome maps raw points within 300m cell to identical cell id', () {
      final homeCell1 = fuzzHome(37.7749, -122.4194);
      final homeCell2 = fuzzHome(37.7751, -122.4192);

      expect(homeCell1, equals(homeCell2));
    });

    test('haversineMeters calculates accurate distance', () {
      // ~111km per degree lat
      final dist = haversineMeters(37.0, -122.0, 38.0, -122.0);
      expect((dist - 111000).abs(), lessThan(2000.0));
    });
  });
}
