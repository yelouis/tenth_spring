import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Representation of a parsed v2 QR pairing payload.
/// Format: {"v":2,"pcId":"<32 hex>","fp":"<64 hex>","addrs":["192.168.1.20"],"port":7350,"pair":"<32 hex>"}
class QrPayloadV2 {
  final int v;
  final String pcId;
  final String fp;
  final List<String> addrs;
  final int port;
  final String pair;

  QrPayloadV2({
    required this.v,
    required this.pcId,
    required this.fp,
    required this.addrs,
    required this.port,
    required this.pair,
  });

  static final RegExp _hex32Regex = RegExp(r'^[0-9a-fA-F]{32}$');
  static final RegExp _hex64LowerRegex = RegExp(r'^[0-9a-f]{64}$');

  static QrPayloadV2? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      if (json['v'] != 2) return null;

      final pcId = json['pcId'];
      if (pcId is! String || !_hex32Regex.hasMatch(pcId)) return null;

      final fp = json['fp'];
      if (fp is! String || !_hex64LowerRegex.hasMatch(fp)) return null;

      final addrsRaw = json['addrs'];
      if (addrsRaw is! List || addrsRaw.isEmpty || addrsRaw.length > 4) return null;
      final addrs = <String>[];
      for (final a in addrsRaw) {
        if (a is! String || !_isValidIpv4(a)) return null;
        addrs.add(a);
      }

      final port = json['port'];
      if (port is! int || port < 1 || port > 65535) return null;

      final pair = json['pair'];
      if (pair is! String || !_hex32Regex.hasMatch(pair)) return null;

      return QrPayloadV2(
        v: 2,
        pcId: pcId,
        fp: fp,
        addrs: addrs,
        port: port,
        pair: pair,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isValidIpv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final val = int.tryParse(p);
      if (val == null || val < 0 || val > 255) return false;
      if (p != val.toString()) return false;
    }
    return true;
  }
}

/// Secure storage of pairing state over FlutterSecureStorage.
class PairingStore {
  final FlutterSecureStorage _storage;

  static const String keyPcId = 'pairing.pcId';
  static const String keyFp = 'pairing.fp';
  static const String keyAddrs = 'pairing.addrs';
  static const String keyPort = 'pairing.port';
  static const String keyPhoneId = 'pairing.phoneId';
  static const String keyDeviceToken = 'pairing.deviceToken';
  static const String keyLastGoodAddr = 'pairing.lastGoodAddr';

  PairingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> getPcId() => _storage.read(key: keyPcId);
  Future<String?> getFp() => _storage.read(key: keyFp);
  Future<List<String>?> getAddrs() async {
    final raw = await _storage.read(key: keyAddrs);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return null;
  }

  Future<int?> getPort() async {
    final raw = await _storage.read(key: keyPort);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<String?> getPhoneId() => _storage.read(key: keyPhoneId);
  Future<String?> getDeviceToken() => _storage.read(key: keyDeviceToken);
  Future<String?> getLastGoodAddr() => _storage.read(key: keyLastGoodAddr);

  Future<void> savePairing({
    required String pcId,
    required String fp,
    required List<String> addrs,
    required int port,
    required String phoneId,
    required String deviceToken,
  }) async {
    await _storage.write(key: keyPcId, value: pcId);
    await _storage.write(key: keyFp, value: fp);
    await _storage.write(key: keyAddrs, value: jsonEncode(addrs));
    await _storage.write(key: keyPort, value: port.toString());
    await _storage.write(key: keyPhoneId, value: phoneId);
    await _storage.write(key: keyDeviceToken, value: deviceToken);
  }

  Future<void> updateAddrsAndPort({
    required List<String> addrs,
    required int port,
  }) async {
    await _storage.write(key: keyAddrs, value: jsonEncode(addrs));
    await _storage.write(key: keyPort, value: port.toString());
  }

  Future<void> setLastGoodAddr(String addr) async {
    await _storage.write(key: keyLastGoodAddr, value: addr);
  }

  Future<void> clear() async {
    await _storage.delete(key: keyPcId);
    await _storage.delete(key: keyFp);
    await _storage.delete(key: keyAddrs);
    await _storage.delete(key: keyPort);
    await _storage.delete(key: keyPhoneId);
    await _storage.delete(key: keyDeviceToken);
    await _storage.delete(key: keyLastGoodAddr);
  }

  Future<bool> isPaired() async {
    final pcId = await getPcId();
    final fp = await getFp();
    final token = await getDeviceToken();
    return pcId != null && fp != null && token != null;
  }
}
