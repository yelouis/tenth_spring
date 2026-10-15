import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:companion/capture/gpx_replay_source.dart';
import 'package:companion/capture/detector.dart';
import 'package:companion/capture/location_source.dart';
import 'package:companion/outbox/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('Hand-drawn GPX replay produces 1 visit >= 600s, strictly increasing times starting at t0, and deterministic corridors', () async {
    final file = File('test/fixtures/synthetic_hand_drawn.gpx');
    expect(file.existsSync(), isTrue, reason: 'synthetic_hand_drawn.gpx must exist');
    final gpxXml = file.readAsStringSync();

    final gpxSource = GpxReplaySource(gpxXml, instant: true);
    final detector = VisitCorridorDetector(
      visitRadiusMeters: 75.0,
      visitDwellSeconds: 120,
    );

    final emittedFixes = <Fix>[];
    gpxSource.fixes().listen((fix) {
      emittedFixes.add(fix);
      detector.processFix(fix);
    });

    final pendingFutures = <Future>[];

    detector.visitStream.listen((visit) {
      final f = db.insertVisit(
        kind: 'visit',
        lat: visit.fuzzedPoint.lat,
        lon: visit.fuzzedPoint.lon,
        startedAt: visit.startedAtTsMs,
        dwellSeconds: visit.dwellSeconds,
      );
      pendingFutures.add(f);
    });

    detector.corridorStream.listen((corridor) {
      final f = db.insertVisit(
        kind: 'corridor',
        lat: corridor.fuzzedPoint.lat,
        lon: corridor.fuzzedPoint.lon,
        startedAt: corridor.timestampTsMs,
      );
      pendingFutures.add(f);
    });

    await gpxSource.start();
    detector.flush();

    await Future.delayed(const Duration(milliseconds: 200));
    await Future.wait(pendingFutures);

    // 1. Verify fix timestamps: start at t0 = 1770000000000, strictly increasing
    expect(emittedFixes.isNotEmpty, isTrue);
    expect(emittedFixes.first.tsUtcMs, equals(1770000000000));
    for (int i = 0; i < emittedFixes.length - 1; i++) {
      expect(
        emittedFixes[i + 1].tsUtcMs,
        greaterThan(emittedFixes[i].tsUtcMs),
        reason: 'Fix timestamps must be strictly increasing at index $i',
      );
    }

    final items = await db.getAllVisits();
    expect(items.isNotEmpty, isTrue);

    // 2. Exactly 1 visit with dwell duration >= 600 s
    final visits = items.where((i) => i.kind == 'visit').toList();
    expect(visits.length, equals(1));
    expect(visits.first.dwellSeconds, greaterThanOrEqualTo(600));

    // 3. Corridor count matches deterministic expectation
    final corridors = items.where((i) => i.kind == 'corridor').toList();
    // 20 track points around a loop plus initial movement from wpt
    expect(corridors.length, greaterThan(0));
    expect(corridors.length, equals(38));

    // 4. Privacy: all lat/lon must be fuzzed (<= 3 decimal places)
    for (final item in items) {
      final latStr = item.lat.toString();
      final lonStr = item.lon.toString();
      final latDecimals = latStr.contains('.') ? latStr.split('.')[1].length : 0;
      final lonDecimals = lonStr.contains('.') ? lonStr.split('.')[1].length : 0;
      expect(latDecimals, lessThanOrEqualTo(3));
      expect(lonDecimals, lessThanOrEqualTo(3));
    }
  });

  test('Falsification: adding one <time> tag switches to recorded mode, producing 0 visits', () async {
    final file = File('test/fixtures/synthetic_hand_drawn.gpx');
    expect(file.existsSync(), isTrue);
    final gpxXml = file.readAsStringSync();

    // Inject a single <time> tag into one of the trackpoints
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final modifiedXml = gpxXml.replaceFirst(
      '<trkpt lat="0.01100" lon="0.01000"/>',
      '<trkpt lat="0.01100" lon="0.01000"><time>$nowIso</time></trkpt>',
    );
    expect(modifiedXml, contains('<time>'));

    final gpxSource = GpxReplaySource(modifiedXml, instant: true);
    final detector = VisitCorridorDetector(
      visitRadiusMeters: 75.0,
      visitDwellSeconds: 120,
    );

    final pendingFutures = <Future>[];

    detector.visitStream.listen((visit) {
      final f = db.insertVisit(
        kind: 'visit',
        lat: visit.fuzzedPoint.lat,
        lon: visit.fuzzedPoint.lon,
        startedAt: visit.startedAtTsMs,
        dwellSeconds: visit.dwellSeconds,
      );
      pendingFutures.add(f);
    });

    detector.corridorStream.listen((corridor) {
      final f = db.insertVisit(
        kind: 'corridor',
        lat: corridor.fuzzedPoint.lat,
        lon: corridor.fuzzedPoint.lon,
        startedAt: corridor.timestampTsMs,
      );
      pendingFutures.add(f);
    });

    gpxSource.fixes().listen((fix) {
      detector.processFix(fix);
    });

    await gpxSource.start();
    detector.flush();

    await Future.delayed(const Duration(milliseconds: 200));
    await Future.wait(pendingFutures);

    final items = await db.getAllVisits();
    final visits = items.where((i) => i.kind == 'visit').toList();
    // Switched to recorded mode without 10-minute synthesis -> 0 visits
    expect(visits.length, equals(0));
  });
}
