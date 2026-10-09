import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import '../outbox/database.dart';
import 'frame_codec.dart';
import 'pairing.dart';
import 'transport.dart';

sealed class ReportResult {
  const ReportResult();
}

class ReportOk extends ReportResult {
  final int sent;
  final int acked;
  const ReportOk({required this.sent, required this.acked});
}

class ReportUnreachable extends ReportResult {
  const ReportUnreachable();
}

class ReportUnpaired extends ReportResult {
  const ReportUnpaired();
}

class ReportSchemaMismatch extends ReportResult {
  const ReportSchemaMismatch();
}

class ReportProtocolError extends ReportResult {
  final String? message;
  const ReportProtocolError([this.message]);
}

sealed class PairResult {
  const PairResult();
}

class PairOk extends PairResult {
  const PairOk();
}

class PairBadCode extends PairResult {
  const PairBadCode();
}

class PairUnreachable extends PairResult {
  const PairUnreachable();
}

class PairProtocolError extends PairResult {
  final String? message;
  const PairProtocolError([this.message]);
}

/// Link manager establishing pinned TLS connections and scout reports to the PC.
class ScoutLink {
  final PairingStore store;
  final SyncTransport transport;

  ScoutLink({PairingStore? pairingStore, SyncTransport? syncTransport})
      : store = pairingStore ?? PairingStore(),
        transport = syncTransport ?? SyncTransport();

  static String certFingerprintHex(X509Certificate cert) {
    final digest = Sha256().toSync().hashSync(cert.der);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Connects to host:port over TLS with strict pinned self-signed certificate.
  Future<SecureSocket> connectPinned(String host, int port, String fpHex) async {
    var rejectedByPin = false;
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (X509Certificate cert) {
          final actualFp = certFingerprintHex(cert);
          final matches = actualFp.toLowerCase() == fpHex.toLowerCase();
          if (!matches) {
            rejectedByPin = true;
          }
          return matches;
        },
        timeout: const Duration(seconds: 3),
      );

      // Re-check peerCertificate after connect
      final peerCert = socket.peerCertificate;
      if (peerCert == null || certFingerprintHex(peerCert).toLowerCase() != fpHex.toLowerCase()) {
        socket.destroy();
        throw const HandshakeException('Peer certificate fingerprint mismatch on post-connect verification');
      }

      return socket;
    } catch (e) {
      if (rejectedByPin) {
        throw const HandshakeException('Certificate pin mismatch');
      }
      rethrow;
    }
  }

  /// Pairs companion with PC using parsed v2 QR payload.
  Future<PairResult> pair(QrPayloadV2 qr) async {
    final storedPcId = await store.getPcId();
    final storedFp = await store.getFp();
    final storedToken = await store.getDeviceToken();

    // Same PC and cert: update addrs/port only if deviceToken is present
    if (storedPcId != null &&
        storedPcId == qr.pcId &&
        storedFp != null &&
        storedFp.toLowerCase() == qr.fp.toLowerCase() &&
        storedToken != null) {
      await store.updateAddrsAndPort(addrs: qr.addrs, port: qr.port);
      return const PairOk();
    }

    // New pairing: get or create phoneId
    var phoneId = await store.getPhoneId();
    if (phoneId == null || phoneId.isEmpty) {
      final rand = Random.secure();
      final idBytes = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        idBytes[i] = rand.nextInt(256);
      }
      phoneId = idBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    // Create fresh 32-byte deviceToken
    final rand = Random.secure();
    final tokenBytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      tokenBytes[i] = rand.nextInt(256);
    }
    final deviceTokenB64 = base64Encode(tokenBytes);

    SecureSocket? socket;
    String? connectedAddr;

    for (final addr in qr.addrs) {
      try {
        socket = await connectPinned(addr, qr.port, qr.fp);
        connectedAddr = addr;
        break;
      } catch (_) {
        continue;
      }
    }

    if (socket == null || connectedAddr == null) {
      return const PairUnreachable();
    }

    final framed = FramedSocket(socket);

    try {
      final pairFrame = {
        "type": "PAIR",
        "v": 2,
        "phoneId": phoneId,
        "pair": qr.pair,
        "deviceToken": deviceTokenB64,
      };

      await framed.send(pairFrame);
      final resp = await framed.nextFrame();

      if (resp == null) {
        await framed.close();
        return const PairProtocolError('No response from PC');
      }

      final type = resp['type'];
      if (type == 'PAIR_OK') {
        await store.savePairing(
          pcId: qr.pcId,
          fp: qr.fp.toLowerCase(),
          addrs: qr.addrs,
          port: qr.port,
          phoneId: phoneId,
          deviceToken: deviceTokenB64,
        );
        await store.setLastGoodAddr(connectedAddr);
        await framed.close();
        return const PairOk();
      } else if (type == 'ERROR' && resp['code'] == 'bad_pair_code') {
        await framed.close();
        return const PairBadCode();
      } else {
        await framed.close();
        return PairProtocolError(resp['code']?.toString());
      }
    } catch (e) {
      await framed.close();
      return PairProtocolError(e.toString());
    }
  }

  /// Reports pending scout outbox rows to PC.
  Future<ReportResult> report({required AppDatabase db, Map<String, dynamic>? bodyFix}) async {
    final pcId = await store.getPcId();
    final fp = await store.getFp();
    final phoneId = await store.getPhoneId();
    final deviceToken = await store.getDeviceToken();
    final port = await store.getPort();
    final addrs = await store.getAddrs();

    if (pcId == null || fp == null || phoneId == null || deviceToken == null || port == null || addrs == null || addrs.isEmpty) {
      return const ReportUnreachable();
    }

    // Try lastGoodAddr first, then other addrs
    final lastGood = await store.getLastGoodAddr();
    final candidateAddrs = <String>[];
    if (lastGood != null && lastGood.isNotEmpty) {
      candidateAddrs.add(lastGood);
    }
    for (final a in addrs) {
      if (!candidateAddrs.contains(a)) {
        candidateAddrs.add(a);
      }
    }

    SecureSocket? socket;
    String? activeAddr;

    for (final addr in candidateAddrs) {
      try {
        socket = await connectPinned(addr, port, fp);
        activeAddr = addr;
        break;
      } catch (_) {
        continue;
      }
    }

    if (socket == null || activeAddr == null) {
      return const ReportUnreachable();
    }

    final framed = FramedSocket(socket);

    try {
      // 1. Send HELLO
      final helloPayload = transport.buildHelloPayload(phoneId, 1, deviceToken);
      await framed.send(helloPayload);

      final helloResp = await framed.nextFrame();
      if (helloResp == null) {
        await framed.close();
        return const ReportProtocolError('No response to HELLO');
      }

      if (helloResp['type'] == 'ERROR') {
        await framed.close();
        final code = helloResp['code'];
        if (code == 'unpaired') {
          await store.clearDeviceToken();
          return const ReportUnpaired();
        }
        if (code == 'schema_mismatch') return const ReportSchemaMismatch();
        return ReportProtocolError(code?.toString());
      }

      if (helloResp['type'] != 'HELLO_OK') {
        await framed.close();
        return const ReportProtocolError('Expected HELLO_OK');
      }

      // 2. Loop BATCH until outbox is empty
      int totalSent = 0;
      int totalAcked = 0;

      while (true) {
        final pendingRows = await (db.select(db.visitOutbox)
              ..orderBy([(t) => OrderingTerm(expression: t.seq, mode: OrderingMode.asc)])
              ..limit(500))
            .get();

        if (pendingRows.isEmpty) {
          break;
        }

        final batchPayload = transport.buildBatchPayload(pendingRows, bodyFix);
        await framed.send(batchPayload);

        final ackResp = await framed.nextFrame();
        if (ackResp == null) {
          await framed.close();
          return const ReportProtocolError('No response to BATCH');
        }

        if (ackResp['type'] == 'ERROR') {
          await framed.close();
          final code = ackResp['code'];
          if (code == 'unpaired') {
            await store.clearDeviceToken();
            return const ReportUnpaired();
          }
          if (code == 'schema_mismatch') return const ReportSchemaMismatch();
          return ReportProtocolError(code?.toString());
        }

        if (ackResp['type'] != 'ACK') {
          await framed.close();
          return const ReportProtocolError('Expected ACK');
        }

        final ackedSeq = await transport.handleAckResponse(ackResp, db);
        totalSent += pendingRows.length;
        final applied = ackResp['appliedCount'] as int? ?? (ackedSeq > 0 ? pendingRows.length : 0);
        totalAcked += applied;

        // If server acknowledged less than the batch's max seq, break to avoid looping
        if (ackedSeq < pendingRows.last.seq) {
          break;
        }
      }

      await store.setLastGoodAddr(activeAddr);
      await framed.close();
      return ReportOk(sent: totalSent, acked: totalAcked);
    } catch (e) {
      await framed.close();
      return ReportProtocolError(e.toString());
    }
  }
}

/// Helper managing framed socket reads and writes with buffering.
class FramedSocket {
  final Socket socket;
  final List<Map<String, dynamic>> _incoming = [];
  Completer<Map<String, dynamic>?>? _pendingRead;
  final FrameReader _reader = FrameReader();
  late final StreamSubscription _sub;

  FramedSocket(this.socket) {
    _sub = socket.listen(
      (data) {
        _reader.feed(data);
        while (true) {
          final frame = _reader.nextFrame();
          if (frame == null) break;
          if (_pendingRead != null && !_pendingRead!.isCompleted) {
            _pendingRead!.complete(frame);
            _pendingRead = null;
          } else {
            _incoming.add(frame);
          }
        }
      },
      onError: (_) {
        if (_pendingRead != null && !_pendingRead!.isCompleted) {
          _pendingRead!.complete(null);
          _pendingRead = null;
        }
      },
      onDone: () {
        if (_pendingRead != null && !_pendingRead!.isCompleted) {
          _pendingRead!.complete(null);
          _pendingRead = null;
        }
      },
    );
  }

  Future<void> send(Map<String, dynamic> frame) async {
    socket.add(FrameCodec.encode(frame));
    await socket.flush();
  }

  Future<Map<String, dynamic>?> nextFrame({Duration timeout = const Duration(seconds: 10)}) async {
    if (_incoming.isNotEmpty) {
      return _incoming.removeAt(0);
    }
    _pendingRead = Completer<Map<String, dynamic>?>();
    try {
      return await _pendingRead!.future.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await socket.close();
  }
}
