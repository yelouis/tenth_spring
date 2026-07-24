import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PairingService {
  final FlutterSecureStorage _storage;
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  PairingService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Parse QR code JSON payload from PC
  Map<String, dynamic>? parseQrCode(String qrData) {
    try {
      final data = jsonDecode(qrData);
      if (data is Map<String, dynamic> &&
          data['v'] == 1 &&
          data.containsKey('pcId') &&
          data.containsKey('pcPubKeyB64')) {
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// Perform X25519 DH + HKDF-SHA256 session key derivation
  Future<List<int>> deriveSessionKey({
    required String phoneId,
    required String pcId,
    required List<int> phonePrivateKeyBytes,
    required List<int> pcPublicKeyBytes,
  }) async {
    final phoneKeyPair = await _x25519.newKeyPairFromSeed(phonePrivateKeyBytes);
    final pcPublicKey = SimplePublicKey(pcPublicKeyBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: phoneKeyPair,
      remotePublicKey: pcPublicKey,
    );

    // HKDF salt = sorted(pcId, phoneId)
    final ids = [pcId, phoneId]..sort();
    final salt = utf8.encode(ids.join(':'));

    final secretKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('tenthspring-sync-v1'),
    );

    return await secretKey.extractBytes();
  }

  /// Saves session key to SecureStorage
  Future<void> storeSessionKey(String pcId, List<int> keyBytes) async {
    await _storage.write(
      key: 'session_key_$pcId',
      value: base64Encode(keyBytes),
    );
  }

  /// Retrieves session key from SecureStorage
  Future<List<int>?> getSessionKey(String pcId) async {
    final b64 = await _storage.read(key: 'session_key_$pcId');
    if (b64 == null) return null;
    return base64Decode(b64);
  }
}
