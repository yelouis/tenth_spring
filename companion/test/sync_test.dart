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
          '"fp":"0123456789abcdef', '"fp":"0123456789ABCDEF');
      expect(QrPayloadV2.tryParse(upperFp), isNull);
    });

    test('rejects 5 addrs', () {
      final fiveAddrs = validJson.replaceAll(
          '["192.168.1.20"]',
          '["192.168.1.20","192.168.1.21","192.168.1.22","192.168.1.23","192.168.1.24"]');
      expect(QrPayloadV2.tryParse(fiveAddrs), isNull);
    });
  });

  group('FrameCodec', () {
    test('frame codec round trip', () {
      final msg = {
        'type': 'HELLO',
        'peerId': 'test_phone',
        'schemaVersion': 1,
        'deviceToken': 'token123'
      };
      final encoded = FrameCodec.encode(msg);
      final reader = FrameReader();
      reader.feed(encoded);
      final decoded = reader.nextFrame();

      expect(decoded, isNotNull);
      expect(decoded!['type'], equals('HELLO'));
      expect(decoded['peerId'], equals('test_phone'));
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
      // 1_048_577 = 0x00100001
      readerOversize.feed([0x00, 0x10, 0x00, 0x01]);
      expect(readerOversize.nextFrame(), isNull);
      expect(readerOversize.error, contains('Invalid frame length'));
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
              'ffbbb32bc02ef1e5bef3a6c1019c786cf02a886df08c2eaea37eadfe406b4f4f'));
    });

    test('pin accept and pin refuse against test-time generated certificate',
        () async {
      // Generate RSA key pair and self-signed certificate at test time
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privKey = keyPair.privateKey as RSAPrivateKey;
      final pubKey = keyPair.publicKey as RSAPublicKey;
      final pemKey = CryptoUtils.encodeRSAPrivateKeyToPem(privKey);
      final dn = {'CN': 'tenthspring-test'};
      final csr = X509Utils.generateRsaCsrPem(dn, privKey, pubKey);
      final certPem =
          X509Utils.generateSelfSignedCertificate(privKey, csr, 365);

      final b64 = certPem
          .split('\n')
          .map((l) => l.trim())
          .where((l) => !l.startsWith('-----') && l.isNotEmpty)
          .join();
      final der = base64Decode(b64);
      final serverFpHex = Sha256()
          .toSync()
          .hashSync(der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(pemKey));

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

      // Pin accept: client pinned to server's fingerprint connects
      final acceptedSocket = await link.connectPinned(
        '127.0.0.1',
        server.port,
        serverFpHex,
      );
      expect(acceptedSocket, isNotNull);
      await acceptedSocket.close();

      await clientDone.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      await Future.delayed(const Duration(milliseconds: 100));

      // Pin refuse: client pinned to different fingerprint fails before any byte is read
      final wrongFpHex = '0' * 64;
      await expectLater(
        () => link.connectPinned('127.0.0.1', server.port, wrongFpHex),
        throwsA(isA<HandshakeException>()),
      );

      await server.close();
    });
  });

  group('PairingStore & ScoutLink Report Loop', () {
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

    test('report() against fake server purges outbox through lastAppliedSeq',
        () async {
      // Generate server cert
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privKey = keyPair.privateKey as RSAPrivateKey;
      final pubKey = keyPair.publicKey as RSAPublicKey;
      final pemKey = CryptoUtils.encodeRSAPrivateKeyToPem(privKey);
      final csr = X509Utils.generateRsaCsrPem({'CN': 'localhost'}, privKey, pubKey);
      final certPem = X509Utils.generateSelfSignedCertificate(privKey, csr, 365);
      final der = base64Decode(certPem
          .split('\n')
          .map((l) => l.trim())
          .where((l) => !l.startsWith('-----') && l.isNotEmpty)
          .join());
      final fpHex = Sha256()
          .toSync()
          .hashSync(der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(pemKey));

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
            await framed.send({
              'type': 'HELLO_OK',
              'pcId': 'pc_fake',
              'lastAppliedSeq': 0,
            });

            final batch = await framed.nextFrame();
            if (batch != null && batch['type'] == 'BATCH') {
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
        fp: fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'test_phone_id',
        deviceToken: 'token_abc',
      );

      // Seed 3 outbox rows
      await db.insertVisit(kind: 'visit', lat: 37.775, lon: -122.419, startedAt: 1000);
      await db.insertVisit(kind: 'corridor', lat: 37.776, lon: -122.420, startedAt: 2000);
      await db.insertVisit(kind: 'visit', lat: 37.777, lon: -122.421, startedAt: 3000);

      expect((await db.getAllVisits()).length, equals(3));

      final result = await link.report(
        db: db,
        bodyFix: {'lat': 37.775, 'lon': -122.419, 'tsUtcMs': 1000},
      );

      expect(result, isA<ReportOk>());
      final ok = result as ReportOk;
      expect(ok.sent, equals(3));

      // Rows up to seq 2 purged, seq 3 remains
      final remaining = await db.getAllVisits();
      expect(remaining.length, equals(1));
      expect(remaining.first.seq, equals(3));

      await server.close();
    });

    test('report() with ERROR unpaired reply returns ReportUnpaired and deletes nothing',
        () async {
      // Generate server cert
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privKey = keyPair.privateKey as RSAPrivateKey;
      final pubKey = keyPair.publicKey as RSAPublicKey;
      final pemKey = CryptoUtils.encodeRSAPrivateKeyToPem(privKey);
      final csr = X509Utils.generateRsaCsrPem({'CN': 'localhost'}, privKey, pubKey);
      final certPem = X509Utils.generateSelfSignedCertificate(privKey, csr, 365);
      final der = base64Decode(certPem
          .split('\n')
          .map((l) => l.trim())
          .where((l) => !l.startsWith('-----') && l.isNotEmpty)
          .join());
      final fpHex = Sha256()
          .toSync()
          .hashSync(der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final serverContext = SecurityContext();
      serverContext.useCertificateChainBytes(utf8.encode(certPem));
      serverContext.usePrivateKeyBytes(utf8.encode(pemKey));

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
            await framed.send({
              'type': 'ERROR',
              'code': 'unpaired',
            });
          }
        }();
      });

      await store.savePairing(
        pcId: 'pc_fake',
        fp: fpHex,
        addrs: ['127.0.0.1'],
        port: server.port,
        phoneId: 'test_phone_id',
        deviceToken: 'wrong_token',
      );

      await db.insertVisit(kind: 'visit', lat: 37.775, lon: -122.419, startedAt: 1000);
      expect((await db.getAllVisits()).length, equals(1));

      final result = await link.report(
        db: db,
        bodyFix: {'lat': 37.775, 'lon': -122.419, 'tsUtcMs': 1000},
      );

      expect(result, isA<ReportUnpaired>());
      // Deletes nothing
      expect((await db.getAllVisits()).length, equals(1));

      await server.close();
    });
  });
}
