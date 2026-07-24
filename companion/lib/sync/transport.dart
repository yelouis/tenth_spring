import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../outbox/database.dart';

class SyncTransport {
  final Chacha20 _cipher = Chacha20.poly1305Aead();

  /// Encrypts message bytes with AEAD ChaCha20-Poly1305
  Future<Uint8List> encryptChunk(List<int> plaintext, List<int> sessionKeyBytes, Uint8List nonce) async {
    final secretKey = SecretKey(sessionKeyBytes);
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    return Uint8List.fromList(secretBox.concatenation(nonce: false, mac: true));
  }

  /// Decrypts AEAD ChaCha20-Poly1305 chunk
  Future<List<int>> decryptChunk(Uint8List encryptedData, List<int> sessionKeyBytes, Uint8List nonce) async {
    final secretKey = SecretKey(sessionKeyBytes);
    final secretBox = SecretBox.fromConcatenation(
      encryptedData,
      nonceLength: 0,
      macLength: 16,
    );
    
    // Create SecretBox with explicit nonce
    final fullSecretBox = SecretBox(
      secretBox.cipherText,
      nonce: nonce,
      mac: secretBox.mac,
    );

    return await _cipher.decrypt(
      fullSecretBox,
      secretKey: secretKey,
    );
  }

  /// Builds HELLO payload
  Map<String, dynamic> buildHelloPayload(String peerId, int schemaVersion) {
    return {
      "peerId": peerId,
      "schemaVersion": schemaVersion,
    };
  }

  /// Builds BATCH payload from un-synced outbox items
  Map<String, dynamic> buildBatchPayload(List<VisitOutboxItem> rows, Map<String, dynamic> bodyFix) {
    final rowList = rows.map((r) => {
      "seq": r.seq,
      "kind": r.kind,
      "lat": r.lat,
      "lon": r.lon,
      "startedAt": r.startedAt,
      "dwellSeconds": r.dwellSeconds,
    }).toList();

    return {
      "rows": rowList,
      "bodyFix": bodyFix,
    };
  }

  /// Handles ACK response and purges applied outbox items
  Future<int> handleAckResponse(Map<String, dynamic> ackPayload, AppDatabase db) async {
    if (ackPayload['status'] == 'ack') {
      final lastAppliedSeq = ackPayload['lastAppliedSeq'] as int;
      await db.deleteSyncedUpTo(lastAppliedSeq);
      return lastAppliedSeq;
    }
    return 0;
  }
}
