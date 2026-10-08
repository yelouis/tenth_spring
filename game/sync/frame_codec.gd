class_name FrameCodec
extends RefCounted

const MAX_FRAME_SIZE: int = 1_048_576

static func encode(obj: Dictionary) -> PackedByteArray:
	var json_str = JSON.stringify(obj)
	var json_bytes = json_str.to_utf8_buffer()
	var n = json_bytes.size()
	var result = PackedByteArray([
		(n >> 24) & 0xFF,
		(n >> 16) & 0xFF,
		(n >> 8) & 0xFF,
		n & 0xFF
	])
	result.append_array(json_bytes)
	return result

class FrameReader extends RefCounted:
	var _buffer: PackedByteArray = PackedByteArray()
	var error: String = ""

	func feed(bytes: PackedByteArray) -> void:
		_buffer.append_array(bytes)

	func next_frame() -> Variant:
		if error != "":
			return null
		if _buffer.size() < 4:
			return null

		var n: int = (_buffer[0] << 24) | (_buffer[1] << 16) | (_buffer[2] << 8) | _buffer[3]
		if n == 0 or n > FrameCodec.MAX_FRAME_SIZE:
			error = "Invalid frame length: %d" % n
			return null

		if _buffer.size() < 4 + n:
			return null

		var payload_bytes = _buffer.slice(4, 4 + n)
		_buffer = _buffer.slice(4 + n)

		var json_str = payload_bytes.get_string_from_utf8()
		var parsed = JSON.parse_string(json_str)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			error = "Invalid JSON or non-object payload"
			return null

		if not parsed.has("type"):
			error = "Missing type field in frame"
			return null

		return parsed
