import 'dart:convert';
import 'dart:typed_data';

/// 4-byte big-endian length + UTF-8 JSON frame codec.
class FrameCodec {
  static const int maxFrameSize = 1048576;

  static Uint8List encode(Map<String, dynamic> obj) {
    final jsonBytes = utf8.encode(jsonEncode(obj));
    final n = jsonBytes.length;
    final buffer = Uint8List(4 + n);
    final bd = ByteData.sublistView(buffer);
    bd.setUint32(0, n, Endian.big);
    buffer.setRange(4, 4 + n, jsonBytes);
    return buffer;
  }
}

/// Incremental buffering frame reader with validation against bounds and schema.
class FrameReader {
  final List<int> _buffer = [];
  String error = '';

  void feed(List<int> bytes) {
    _buffer.addAll(bytes);
  }

  Map<String, dynamic>? nextFrame() {
    if (error.isNotEmpty) return null;
    if (_buffer.length < 4) return null;

    final bd = ByteData.sublistView(Uint8List.fromList(_buffer.sublist(0, 4)));
    final n = bd.getUint32(0, Endian.big);

    if (n == 0 || n > FrameCodec.maxFrameSize) {
      error = 'Invalid frame length: $n';
      return null;
    }

    if (_buffer.length < 4 + n) {
      return null;
    }

    final payloadBytes = _buffer.sublist(4, 4 + n);
    _buffer.removeRange(0, 4 + n);

    try {
      final jsonStr = utf8.decode(payloadBytes);
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map<String, dynamic>) {
        error = 'Invalid JSON or non-object payload';
        return null;
      }
      if (!parsed.containsKey('type')) {
        error = 'Missing type field in frame';
        return null;
      }
      return parsed;
    } catch (_) {
      error = 'Invalid JSON payload';
      return null;
    }
  }
}
