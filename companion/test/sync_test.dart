import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';

import 'package:companion/outbox/database.dart';
import 'package:companion/sync/frame_codec.dart';
import 'package:companion/sync/pairing.dart';
import 'package:companion/sync/scout_link.dart';
import 'package:companion/sync/transport.dart';

Future<({String certPem, String pemKey, String fpHex})> _generateServerCert() async {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privKey = keyPair.privateKey as RSAPrivateKey;
  final pubKey = keyPair.publicKey as RSAPublicKey;
  final pemKey = CryptoUtils.encodeRSAPrivateKeyToPem(privKey);
  final csr = X509Utils.generateRsaCsrPem({'CN': 'localhost'}, privKey, pubKey);
  final certPem = X509Utils.generateSelfSignedCertificate(privKey, csr, 365);
  final der = base64Decode(
    certPem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', ''),
  );
  final digest = await Sha256().hash(der);
  final fpHex =
      digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return (certPem: certPem, pemKey: pemKey, fpHex: fpHex);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('QR v2 Payload Parsing', () {
    const validJson =
        '{"v":2,"pcId":"0123456789abcdef0123456789abcdef","fp":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","addrs":["192.168.1.20"],"port":7350,"pair":"fedcba9876543210fedcba9876543210"}';

    test('valid v2 payload parses successfully', () {
      final payload = QrPayloadV2.tryParse(validJson);
      expect(payload, isNotNull);
      expect(payload!.v, equals(2));
      expect(payload.pcId, equals('0123456789abcdef0123456789abcdef'));
      expect(payload.port, equals(7350));
      expect(payload.addrs, equals(['192.168.1.20']));
    });

    test('rejects v: 1', () {
      final jsonV1 = validJson.replaceAll('"v":2', '"v":1');
      expect(QrPayloadV2.tryParse(jsonV1), isNull);
    });

    test('rejects uppercase-hex fp', () {
      final upperFp = validJson.replaceAll(
        '"fp":"0123456789abcdef',
        '"fp":"0123456789ABCDEF',
      );
      expect(QrPayloadV2.tryParse(upperFp), isNull);
    });

    test('rejects 5 addrs', () {
      final fiveAddrs = validJson.replaceAll(
        '["192.168.1.20"]',
        '["192.168.1.20","192.168.1.21","192.168.1.22","192.168.1.23","192.168.1.24"]',
      );
      expect(QrPayloadV2.tryParse(fiveAddrs), isNull);
    });
  });

  group('FrameCodec', () {
    test('frame codec round trip', () {
      final msg = {
        'type': 'HELLO',
        'peerId': 'test_phone',
        'schemaVersion': 3,
        'packVersion': 1,
        'deviceToken': 'token123',
      };
      final encoded = FrameCodec.encode(msg);
      final reader = FrameReader();
      reader.feed(encoded);
      final decoded = reader.nextFrame();

      expect(decoded, isNotNull);
      expect(decoded!['type'], equals('HELLO'));
      expect(decoded['peerId'], equals('test_phone'));
      expect(decoded['schemaVersion'], equals(3));
      expect(decoded['packVersion'], equals(1));
      expect(decoded['deviceToken'], equals('token123'));
    });

    test('split delivery across feeds', () {
      final msg = {'type': 'ACK', 'status': 'ack', 'lastAppliedSeq': 10};
      final encoded = FrameCodec.encode(msg);
      final reader = FrameReader();

      reader.feed(encoded.sublist(0, 2));
      expect(reader.nextFrame(), isNull);

      reader.feed(encoded.sublist(2, 6));
      expect(reader.nextFrame(), isNull);

      reader.feed(encoded.sublist(6));
      final decoded = reader.nextFrame();
      expect(decoded, isNotNull);
      expect(decoded!['type'], equals('ACK'));
      expect(decoded['lastAppliedSeq'], equals(10));
    });

    test('oversize header and zero header trigger error', () {
      final readerZero = FrameReader();
      readerZero.feed([0, 0, 0, 0]);
      expect(readerZero.nextFrame(), isNull);
      expect(readerZero.error, contains('Invalid frame length'));

      final readerOversize = FrameReader();
      readerOversize.feed([0x00, 0x10, 0x00, 0x01]);
      expect(readerOversize.nextFrame(), isNull);
      expect(readerOversize.error, contains('Invalid frame length'));
    });
  });

  group('Protocol v3 JSON-key whitelist (§3.6, §3.7)', () {
    test('HELLO and BATCH carry only v3 whitelisted keys and never coordinates or bodyFix',
        () {
      final transport = SyncTransport();
      final hello = transport.buildHelloPayload(
        'peer_abc',
        3,
        'tok_xyz',
        packVersion: 1,
      );
      expect(
        hello.keys.toSet(),
        equals({'type', 'peerId', 'schemaVersion', 'packVersion', 'deviceToken'}),
      );
      expect(hello['schemaVersion'], equals(3));
      expect(hello['packVersion'], equals(1));

      final rows = [
        const ExploreOutboxItem(
          seq: 1,
          kind: 'home',
          placeId: 'city:fixture-city',
          areaKey: null,
          tsUtcMs: 1700000001000,
        ),
        const ExploreOutboxItem(
          seq: 2,
          kind: 'explore',
          placeId: 'city:fixture-city',
          areaKey: 'osm:n9104',
          tsUtcMs: 1700000002000,
        ),
      ];

      final batch = transport.buildBatchPayload(rows);
      expect(batch.keys.toSet(), equals({'type', 'rows'}));
      expect(batch.containsKey('bodyFix'), isFalse);

      final wireRows = batch['rows'] as List<dynamic>;
      expect(wireRows.length, equals(2));

      final rHome = wireRows[0] as Map<String, dynamic>;
      expect(rHome.keys.toSet(), equals({'seq', 'kind', 'placeId', 'tsUtcMs'}));
      expect(rHome.containsKey('areaKey'), isFalse);
      expect(rHome.containsKey('lat'), isFalse);
      expect(rHome.containsKey('lon'), isFalse);

      final rExplore = wireRows[1] as Map<String, dynamic>;
      expect(
        rExplore.keys.toSet(),
        equals({'seq', 'kind', 'placeId', 'areaKey', 'tsUtcMs'}),
      );
      expect(rExplore.containsKey('lat'), isFalse);
      expect(rExplore.containsKey('lon'), isFalse);
    });
  });

  group('Pinned TLS Certificate & Handshake', () {
    test('fingerprint parity: test_cert.pem hashes to expected hex', () {
      final pem = File('test/fixtures/test_cert.pem').readAsStringSync();
      final b64 = pem
          .split('\n')
          .map((l) => l.trim())
          .where((l) => !l.startsWith('-----') && l.isNotEmpty)
          .join();
      final der = base64Decode(b64);
      final digest = Sha256().toSync().hashSync(der);
      final fpHex = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(
        fpHex,
        equals(
          'ffbbb32bc02ef1e5bef3a6c1019c786cf02a886df08c2eaea37eadfe406b4f4f',
        ),
      );
    });

    test('pin accept and pin refuse against test-time generated certificate',
        () async {
      final certInfo = await _generateServerCert();
      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certInfo.certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(certInfo.pemKey));

      final link = ScoutLink();

      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      final clientDone = Completer<void>();
      server.listen(
        (clientSocket) {
          clientSocket.listen(
            (_) {},
            onError: (_) {},
            onDone: () {
              if (!clientDone.isCompleted) clientDone.complete();
            },
          );
        },
        onError: (_) {},
      );

      final acceptedSocket = await link.connectPinned(
        '127.0.0.1',
        server.port,
        certInfo.fpHex,
      );
      expect(acceptedSocket, isNotNull);
      await acceptedSocket.close();

      await clientDone.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final wrongFpHex = '0' * 64;
      await expectLater(
        () => link.connectPinned('127.0.0.1', server.port, wrongFpHex),
        throwsA(isA<HandshakeException>()),
      );

      await server.close();
    });
  });

  group('PairingStore & ScoutLink Report Loop (Protocol v3)', () {
    late AppDatabase db;
    late PairingStore store;
    late ScoutLink link;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = PairingStore();
      link = ScoutLink(pairingStore: store);
    });

    tearDown(() async {
      await db.close();
      await store.clear();
    });

    test('PairingStore saves, reads, and clears correctly', () async {
      await store.savePairing(
        pcId: 'pc_111',
        fp: 'fp_111',
        addrs: ['127.0.0.1'],
        port: 7350,
        phoneId: 'phone_111',
        deviceToken: 'token_111',
      );

      expect(await store.isPaired(), isTrue);
      expect(await store.getPcId(), equals('pc_111'));
      expect(await store.getFp(), equals('fp_111'));
      expect(await store.getAddrs(), equals(['127.0.0.1']));
      expect(await store.getPort(), equals(7350));
      expect(await store.getPhoneId(), equals('phone_111'));
      expect(await store.getDeviceToken(), equals('token_111'));

      await store.clear();
      expect(await store.isPaired(), isFalse);
    });

    test('report() against fake server sends v3 HELLO and BATCH and purges outbox through lastAppliedSeq',
        () async {
      final certInfo = await _generateServerCert();
      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certInfo.certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(certInfo.pemKey));

      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      Map<String, dynamic>? seenHello;
      Map<String, dynamic>? seenBatch;

      server.listen((socket) {
        final framed = FramedSocket(socket);
        () async {
          final hello = await framed.nextFrame();
          if (hello != null && hello['type'] == 'HELLO') {
            seenHello = hello;
            await framed.send({
              'type': 'HELLO_OK',
              'pcId': 'pc_fake',
              'lastAppliedSeq': 0,
            });

            final batch = await framed.nextFrame();
            if (batch != null && batch['type'] == 'BATCH') {
              seenBatch = batch;
              await framed.send({
                'type': 'ACK',
                'status': 'ack',
                'lastAppliedSeq': 2,
                'appliedCount': 2,
              });
            }
          }
        }();
      });

      await store.savePairing(
        pcId: 'pc_fake',
        fp: certInfo.fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'test_phone_id',
        deviceToken: 'token_abc',
      );

      await db.insertExploreOutbox(
        kind: 'home',
        placeId: 'city:fixture-city',
        tsUtcMs: 1000,
      );
      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'city:fixture-city',
        areaKey: 'osm:n9104',
        tsUtcMs: 2000,
      );
      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'site:fixture-park',
        areaKey: 'site:fixture-park',
        tsUtcMs: 3000,
      );

      expect((await db.getAllOutboxItems()).length, equals(3));

      final result = await link.report(db: db);

      expect(result, isA<ReportOk>());
      final ok = result as ReportOk;
      expect(ok.sent, equals(3));

      expect(seenHello, isNotNull);
      expect(seenHello!['schemaVersion'], equals(3));
      expect(seenHello!['packVersion'], equals(1));
      expect(seenBatch, isNotNull);
      expect(seenBatch!.containsKey('bodyFix'), isFalse);

      // Rows up to seq 2 purged, seq 3 remains
      final remaining = await db.getAllOutboxItems();
      expect(remaining.length, equals(1));
      expect(remaining.first.seq, equals(3));

      await server.close();
    });

    test('report() with ERROR pack_mismatch and bad_row returns expected results and exact user messages',
        () async {
      final certInfo = await _generateServerCert();
      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certInfo.certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(certInfo.pemKey));

      String errorToReturn = 'pack_mismatch';
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      server.listen((socket) {
        final framed = FramedSocket(socket);
        () async {
          final hello = await framed.nextFrame();
          if (hello != null && hello['type'] == 'HELLO') {
            if (errorToReturn == 'pack_mismatch') {
              await framed.send({'type': 'ERROR', 'code': 'pack_mismatch'});
            } else {
              await framed.send({
                'type': 'HELLO_OK',
                'pcId': 'pc_fake',
                'lastAppliedSeq': 0,
              });
              final batch = await framed.nextFrame();
              if (batch != null) {
                await framed.send({'type': 'ERROR', 'code': 'bad_row'});
              }
            }
          }
        }();
      });

      await store.savePairing(
        pcId: 'pc_fake',
        fp: certInfo.fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'test_phone_id',
        deviceToken: 'token_abc',
      );

      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'city:fixture-city',
        areaKey: 'osm:n9104',
        tsUtcMs: 1000,
      );

      final resPack = await link.report(db: db);
      expect(resPack, isA<ReportPackMismatch>());
      expect(
        resPack.userMessage,
        equals(
          'Your companion and game have different map versions — update both.',
        ),
      );
      expect((await db.getAllOutboxItems()).length, equals(1));

      errorToReturn = 'bad_row';
      final resBadRow = await link.report(db: db);
      expect(resBadRow, isA<ReportBadRow>());
      expect(
        resBadRow.userMessage,
        equals('Report failed — update both apps.'),
      );
      expect((await db.getAllOutboxItems()).length, equals(1));

      await server.close();
    });

    test('report() with ERROR unpaired reply returns ReportUnpaired and deletes nothing',
        () async {
      final certInfo = await _generateServerCert();
      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certInfo.certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(certInfo.pemKey));

      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      server.listen((socket) {
        final framed = FramedSocket(socket);
        () async {
          final hello = await framed.nextFrame();
          if (hello != null && hello['type'] == 'HELLO') {
            await framed.send({'type': 'ERROR', 'code': 'unpaired'});
          }
        }();
      });

      await store.savePairing(
        pcId: 'pc_fake',
        fp: certInfo.fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'test_phone_id',
        deviceToken: 'wrong_token',
      );

      await db.insertExploreOutbox(
        kind: 'explore',
        placeId: 'city:fixture-city',
        areaKey: 'osm:n9104',
        tsUtcMs: 1000,
      );
      expect((await db.getAllOutboxItems()).length, equals(1));

      final result = await link.report(db: db);

      expect(result, isA<ReportUnpaired>());
      expect((await db.getAllOutboxItems()).length, equals(1));
      expect(await store.getDeviceToken(), isNull);
      expect(await store.getPhoneId(), equals('test_phone_id'));
      expect(await store.getPcId(), equals('pc_fake'));
      expect(await store.getFp(), equals(certInfo.fpHex));

      await server.close();
    });

    test('pair() without stored deviceToken sends real PAIR even if pcId/fp match (F33 falsification)',
        () async {
      final certInfo = await _generateServerCert();
      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certInfo.certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(certInfo.pemKey));

      final server =
          await SecureServerSocket.bind('127.0.0.1', 0, serverContext);
      Map<String, dynamic>? receivedPairFrame;

      server.listen((client) {
        final framed = FramedSocket(client);
        () async {
          final frame = await framed.nextFrame();
          if (frame != null && frame['type'] == 'PAIR') {
            receivedPairFrame = frame;
            await framed.send({'type': 'PAIR_OK', 'pcId': 'pc_fake'});
          }
        }();
      });

      await store.clear();
      await store.savePairing(
        pcId: 'pc_fake',
        fp: certInfo.fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'persisted_phone_id',
        deviceToken: 'old_dead_token',
      );
      await store.clearDeviceToken();

      final qr = QrPayloadV2(
        v: 2,
        pcId: 'pc_fake',
        fp: certInfo.fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        pair: '0123456789abcdef0123456789abcdef',
      );

      final res = await link.pair(qr);

      expect(res, isA<PairOk>());
      expect(receivedPairFrame, isNotNull);
      expect(receivedPairFrame!['type'], equals('PAIR'));
      expect(receivedPairFrame!['phoneId'], equals('persisted_phone_id'));
      expect(await store.getDeviceToken(), isNotNull);
      expect(await store.isPaired(), isTrue);

      await server.close();
    });
  });
}
