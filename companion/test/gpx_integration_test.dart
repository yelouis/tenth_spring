import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:companion/capture/gpx_replay_source.dart';
import 'package:companion/capture/detector.dart';
import 'package:companion/outbox/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('GPX errand_day fixture produces fuzzed visit & corridor entries in outbox',
      () async {
    final file = File('test/fixtures/errand_day.gpx');
    expect(file.existsSync(), isTrue, reason: 'errand_day.gpx must exist');
    final gpxXml = file.readAsStringSync();

    final gpxSource = GpxReplaySource(gpxXml, instant: true);
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

    // Await all async database insertion futures
    await Future.delayed(const Duration(milliseconds: 200));
    await Future.wait(pendingFutures);

    final items = await db.getAllVisits();
    expect(items.isNotEmpty, isTrue);

    final visits = items.where((i) => i.kind == 'visit').toList();
    expect(visits.length, greaterThanOrEqualTo(1));

    // Privacy verification: all lat/lon in outbox must be fuzzed (<= 3 decimal places)
    for (final item in items) {
      final latStr = item.lat.toString();
      final lonStr = item.lon.toString();
      final latDecimals = latStr.contains('.') ? latStr.split('.')[1].length : 0;
      final lonDecimals = lonStr.contains('.') ? lonStr.split('.')[1].length : 0;
      expect(latDecimals, lessThanOrEqualTo(3));
      expect(lonDecimals, lessThanOrEqualTo(3));
    }
  });
}
