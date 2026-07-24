import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../outbox/database.dart';

/// Monotonic AEAD Nonce & Encrypted Transport Manager for Tenth Spring.
/// Uses ChaCha20-Poly1305 with a 96-bit (12-byte) monotonic counter nonce scheme.
class SyncTransport {
  final Chacha20 _cipher = Chacha20.poly1305Aead();

  /// Generates a 96-bit monotonic nonce from a 64-bit sequence counter.
  Uint8List generateMonotonicNonce(int counter) {
    final nonce = Uint8List(12);
    final bd = ByteData.sublistView(nonce);
    bd.setUint64(4, counter, Endian.big);
    return nonce;
  }

  /// Encrypts message bytes with AEAD ChaCha20-Poly1305 and a monotonic nonce
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

/// Active Sync Client connecting to PC SyncServer via mDNS / Direct TCP
class SyncClient {
  final MDnsClient _mdnsClient = MDnsClient();

  Future<String?> discoverPcHost({String serviceName = '_tenthspring._tcp.local'}) async {
    try {
      await _mdnsClient.start();
      await for (final PtrResourceRecord ptr in _mdnsClient.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(serviceName))) {
        await for (final SrvResourceRecord srv in _mdnsClient.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          _mdnsClient.stop();
          return '${srv.target}:${srv.port}';
        }
      }
      _mdnsClient.stop();
    } catch (_) {}
    return null;
  }

  Future<Socket> connectToPc(String host, int port) async {
    return await Socket.connect(host, port, timeout: const Duration(seconds: 5));
  }
}
