// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';

import 'package:companion/capture/gpx_replay_source.dart';
import 'package:companion/capture/detector.dart';
import 'package:companion/outbox/database.dart';
import 'package:companion/sync/pairing.dart';
import 'package:companion/sync/scout_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  const e2ePortStr = String.fromEnvironment('E2E_PORT');
  const e2eFp = String.fromEnvironment('E2E_FP');
  const e2ePair = String.fromEnvironment('E2E_PAIR');
  const e2ePcId = String.fromEnvironment('E2E_PCID');

  test(
    'E2E cross-language loopback sync',
    () async {
      final port = int.parse(e2ePortStr);
      final db = AppDatabase(NativeDatabase.memory());
      final store = PairingStore();
      await store.clear();
      final link = ScoutLink(pairingStore: store);

      // 1. Pair using the defines
      final qr = QrPayloadV2(
        v: 2,
        pcId: e2ePcId,
        fp: e2eFp,
        addrs: ['127.0.0.1'],
        port: port,
        pair: e2ePair,
      );
      final pairResult = await link.pair(qr);
      expect(pairResult, isA<PairOk>());
      expect(await store.isPaired(), isTrue);

      // 2. Run test/fixtures/errand_day.gpx through capture pipeline into outbox
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

      await Future.delayed(const Duration(milliseconds: 200));
      await Future.wait(pendingFutures);

      final items = await db.getAllVisits();
      expect(items.isNotEmpty, isTrue);

      // Save copy of rows for replay check
      final savedRows = List<VisitOutboxItem>.from(items);
      final maxSeq = savedRows.map((r) => r.seq).reduce((a, b) => a > b ? a : b);

      // 3. Print E2E_SENT {"rows":n,"maxSeq":m}
      final sentJson = jsonEncode({'rows': savedRows.length, 'maxSeq': maxSeq});
      print('E2E_SENT $sentJson');

      // 4. report(), and expect ok
      final reportResult = await link.report(
        db: db,
        bodyFix: {
          'lat': savedRows.last.lat,
          'lon': savedRows.last.lon,
          'tsUtcMs': savedRows.last.startedAt,
        },
      );
      expect(reportResult, isA<ReportOk>());
      final okResult = reportResult as ReportOk;
      expect(okResult.sent, equals(savedRows.length));
      expect((await db.getAllVisits()).isEmpty, isTrue);

      // 5. Re-send the same rows as one raw BATCH on a new session, and expect appliedCount == 0
      await Future.delayed(const Duration(milliseconds: 300));
      SecureSocket? socket;
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          socket = await link.connectPinned('127.0.0.1', port, e2eFp);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }
      expect(socket, isNotNull);
      final framed = FramedSocket(socket!);
      final phoneId = await store.getPhoneId();
      final deviceToken = await store.getDeviceToken();

      final helloPayload = link.transport.buildHelloPayload(phoneId!, 1, deviceToken!);
      await framed.send(helloPayload);
      final helloResp = await framed.nextFrame();
      expect(helloResp, isNotNull);
      expect(helloResp!['type'], equals('HELLO_OK'));

      final batchPayload = link.transport.buildBatchPayload(
        savedRows,
        {
          'lat': savedRows.last.lat,
          'lon': savedRows.last.lon,
          'tsUtcMs': savedRows.last.startedAt,
        },
      );
      await framed.send(batchPayload);
      final ackResp = await framed.nextFrame();
      expect(ackResp, isNotNull);
      expect(ackResp!['type'], equals('ACK'));
      expect(ackResp['appliedCount'], equals(0));

      await framed.close();
      await db.close();
    },
    skip: e2ePortStr.isEmpty ? 'E2E only — run via tools/sync_e2e.py' : false,
  );
}
