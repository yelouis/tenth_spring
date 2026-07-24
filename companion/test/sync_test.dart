import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion/sync/pairing.dart';
import 'package:companion/sync/transport.dart';
import 'package:companion/outbox/database.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase db;
  late SyncTransport transport;
  late PairingService pairing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    transport = SyncTransport();
    pairing = PairingService();
  });

  tearDown(() async {
    await db.close();
  });

  test('QR code parsing succeeds for valid payload format', () {
    const qrData = '{"v":1,"pcId":"pc_001","pcPubKeyB64":"c29tZWtleQ==","mdnsName":"pc.local"}';
    final parsed = pairing.parseQrCode(qrData);

    expect(parsed, isNotNull);
    expect(parsed!['pcId'], equals('pc_001'));
    expect(parsed['pcPubKeyB64'], equals('c29tZWtleQ=='));
  });

  test('AEAD ChaCha20-Poly1305 encryption & decryption round-trip succeeds', () async {
    final sessionKey = List<int>.generate(32, (i) => i + 1);
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));
    final plaintext = Uint8List.fromList('HELLO TENTH SPRING SYNC'.codeUnits);

    final encrypted = await transport.encryptChunk(plaintext, sessionKey, nonce);
    expect(encrypted, isNotNull);
    expect(encrypted.length, greaterThan(plaintext.length));

    final decrypted = await transport.decryptChunk(encrypted, sessionKey, nonce);
    expect(String.fromCharCodes(decrypted), equals('HELLO TENTH SPRING SYNC'));
  });

  test('Tampered ciphertext is rejected by AEAD decryption', () async {
    final sessionKey = List<int>.generate(32, (i) => i + 1);
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));
    final plaintext = Uint8List.fromList('SECRET DATA'.codeUnits);

    final encrypted = await transport.encryptChunk(plaintext, sessionKey, nonce);
    
    // Corrupt the first ciphertext byte
    encrypted[0] = encrypted[0] ^ 0xFF;

    expect(() async => await transport.decryptChunk(encrypted, sessionKey, nonce), throwsA(anything));
  });

  test('ACK response purges applied outbox items from database up to lastAppliedSeq', () async {
    await db.insertVisit(kind: 'visit', lat: 37.775, lon: -122.419, startedAt: 1000);
    await db.insertVisit(kind: 'corridor', lat: 37.776, lon: -122.420, startedAt: 2000);

    var visits = await db.getAllVisits();
    expect(visits.length, equals(2));

    final ackPayload = {
      'status': 'ack',
      'lastAppliedSeq': 1,
      'appliedCount': 1,
    };

    final ackedSeq = await transport.handleAckResponse(ackPayload, db);
    expect(ackedSeq, equals(1));

    visits = await db.getAllVisits();
    expect(visits.length, equals(1));
    expect(visits.first.seq, equals(2));
  });
}
