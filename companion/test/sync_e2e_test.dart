// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/native.dart';

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
    'E2E cross-language loopback sync (protocol v3)',
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

      // 2. Seed v3 explore & home rows in ExploreOutbox (matching places_pack_v1.json.gz)
      // - home row for city:washington-dc
      // - explore row for Dupont Circle (osm:r2919449) in city:washington-dc
      // - explore row for site:acadia
      await db.insertExploreOutbox(
        kind: 'home',
        placeId: 'city:washington-dc',
        tsUtcMs: 1700000001000,
      );
      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'city:washington-dc',
        areaKey: 'osm:r2919449',
        tsUtcMs: 1700000002000,
      );
      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'site:acadia',
        areaKey: 'site:acadia',
        tsUtcMs: 1700000003000,
      );

      final items = await db.getAllOutboxItems();
      expect(items.length, equals(3));

      final savedRows = List<ExploreOutboxItem>.from(items);
      final maxSeq =
          savedRows.map((r) => r.seq).reduce((a, b) => a > b ? a : b);

      // 3. Print E2E_SENT {"rows":n,"maxSeq":m}
      final sentJson = jsonEncode({'rows': savedRows.length, 'maxSeq': maxSeq});
      print('E2E_SENT $sentJson');

      // 4. report() and expect ReportOk
      final reportResult = await link.report(db: db);
      expect(reportResult, isA<ReportOk>());
      final okResult = reportResult as ReportOk;
      expect(okResult.sent, equals(savedRows.length));
      expect((await db.getAllOutboxItems()).isEmpty, isTrue);

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

      final helloPayload = link.transport.buildHelloPayload(
        phoneId!,
        3,
        deviceToken!,
        packVersion: 1,
      );
      await framed.send(helloPayload);
      final helloResp = await framed.nextFrame();
      expect(helloResp, isNotNull);
      expect(helloResp!['type'], equals('HELLO_OK'));

      final batchPayload = link.transport.buildBatchPayload(savedRows);
      await framed.send(batchPayload);
      final ackResp = await framed.nextFrame();
      expect(ackResp, isNotNull);
      expect(ackResp!['type'], equals('ACK'));
      expect(ackResp['appliedCount'], equals(0));
      await framed.close();

      // 6. Send a BATCH carrying a forbidden `lat` key on a new session -> expect ERROR bad_row
      await Future.delayed(const Duration(milliseconds: 200));
      SecureSocket? badSocket;
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          badSocket = await link.connectPinned('127.0.0.1', port, e2eFp);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }
      expect(badSocket, isNotNull);
      final badFramed = FramedSocket(badSocket!);
      await badFramed.send(helloPayload);
      final badHelloResp = await badFramed.nextFrame();
      expect(badHelloResp, isNotNull);
      expect(badHelloResp!['type'], equals('HELLO_OK'));

      await badFramed.send({
        'type': 'BATCH',
        'rows': [
          {
            'seq': 99,
            'kind': 'explore',
            'placeId': 'city:washington-dc',
            'areaKey': 'osm:r2919449',
            'lat': 38.9096,
            'tsUtcMs': 1700000099000,
          },
        ],
      });
      final badRowResp = await badFramed.nextFrame();
      expect(badRowResp, isNotNull);
      expect(badRowResp!['type'], equals('ERROR'));
      expect(badRowResp['code'], equals('bad_row'));
      print('E2E_BAD_ROW_OK');

      await badFramed.close();
      await db.close();
    },
    skip: e2ePortStr.isEmpty ? 'E2E only — run via tools/sync_e2e.py' : false,
  );
}
