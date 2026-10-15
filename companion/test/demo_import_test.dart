// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';

import 'package:companion/capture/gpx_replay_source.dart';
import 'package:companion/capture/detector.dart';
import 'package:companion/capture/location_source.dart';
import 'package:companion/outbox/database.dart';
import 'package:companion/sync/pairing.dart';
import 'package:companion/sync/scout_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  const demoGpxPath = String.fromEnvironment('DEMO_GPX');
  const demoPortStr = String.fromEnvironment('DEMO_PORT', defaultValue: '7352');
  const demoFp = String.fromEnvironment('DEMO_FP');
  const demoPair = String.fromEnvironment('DEMO_PAIR');
  const demoPcId = String.fromEnvironment('DEMO_PC_ID');

  test(
    'Demo GPX Import Harness',
    () async {
      final port = int.parse(demoPortStr);
      final db = AppDatabase(NativeDatabase.memory());
      final store = PairingStore();
      await store.clear();
      final link = ScoutLink(pairingStore: store);

      // 1. Pair with Godot demo import server
      final qr = QrPayloadV2(
        v: 2,
        pcId: demoPcId,
        fp: demoFp,
        addrs: ['127.0.0.1'],
        port: port,
        pair: demoPair,
      );
      final pairResult = await link.pair(qr);
      expect(pairResult, isA<PairOk>());
      expect(await store.isPaired(), isTrue);

      // 2. Load and replay GPX file
      expect(demoGpxPath.isNotEmpty, isTrue, reason: 'DEMO_GPX must be provided');
      final file = File(demoGpxPath);
      expect(file.existsSync(), isTrue, reason: 'GPX file at $demoGpxPath must exist');
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

      Fix? lastFix;
      gpxSource.fixes().listen((fix) {
        lastFix = fix;
        detector.processFix(fix);
      });

      await gpxSource.start();
      detector.flush();

      await Future.delayed(const Duration(milliseconds: 200));
      await Future.wait(pendingFutures);

      final items = await db.getAllVisits();
      expect(items.isNotEmpty, isTrue);

      final maxSeq = items.map((r) => r.seq).reduce((a, b) => a > b ? a : b);
      print('DEMO_SENT {"rows":${items.length},"maxSeq":$maxSeq}');

      // 3. Send report batch to Godot
      Map<String, dynamic>? bodyFix;
      if (lastFix != null) {
        bodyFix = {
          'lat': double.parse(lastFix!.lat.toStringAsFixed(3)),
          'lon': double.parse(lastFix!.lon.toStringAsFixed(3)),
          'tsUtcMs': lastFix!.tsUtcMs,
        };
      }

      final reportResult = await link.report(
        db: db,
        bodyFix: bodyFix,
      );
      expect(reportResult, isA<ReportOk>());
      final ok = reportResult as ReportOk;
      expect(ok.sent, equals(items.length));

      await db.close();
    },
    skip: demoGpxPath.isEmpty ? 'Demo import only — run via tools/demo_import.py' : false,
  );
}
