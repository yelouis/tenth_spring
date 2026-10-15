extends RefCounted

# osm_pbf_reader.gd — Streaming OpenStreetMap PBF Reader (F39)
# Reads PBF files blob by blob, bounding in-flight blocks.
# Reference: docs/design_memory_and_resources.md §3.1 & docs/implementation_plan_world_generation.md §5.2

class ProtoReader:
	var buf: PackedByteArray
	var pos: int = 0
	var size: int = 0

	func _init(b: PackedByteArray):
		buf = b
		pos = 0
		size = b.size()

	func has_more() -> bool:
		return pos < size

	func read_varint() -> int:
		var res: int = 0
		var shift: int = 0
		while pos < size:
			var b: int = buf[pos]
			pos += 1
			res |= (b & 0x7F) << shift
			if (b & 0x80) == 0:
				return res
			shift += 7
			if shift >= 64:
				break
		return res

	func read_sint64() -> int:
		var v := read_varint()
		return (v >> 1) ^ (-(v & 1))

	func skip(n: int) -> void:
		pos = mini(pos + n, size)

	func read_bytes(n: int) -> PackedByteArray:
		var end_p := mini(pos + n, size)
		var res := buf.slice(pos, end_p)
		pos = end_p
		return res

	func read_string(n: int) -> String:
		return read_bytes(n).get_string_from_utf8()


static func read_blob_header_and_data(f: FileAccess) -> Dictionary:
	# Returns { "type": String, "raw_data": PackedByteArray, "offset": int } or empty on EOF/error
	var start_pos := f.get_position()
	var h_len_buf := f.get_buffer(4)
	if h_len_buf.size() < 4:
		return {}

	var h_len := (h_len_buf[0] << 24) | (h_len_buf[1] << 16) | (h_len_buf[2] << 8) | h_len_buf[3]
	if h_len > 65536:
		push_error("BlobHeader exceeds 64 KiB: %d" % h_len)
		return {"error": "BlobHeader too large"}

	var h_buf := f.get_buffer(h_len)
	var hr := ProtoReader.new(h_buf)
	var b_type := ""
	var data_size := 0
	while hr.has_more():
		var tag := hr.read_varint()
		var fn := tag >> 3
		var wt := tag & 0x7
		if fn == 1 and wt == 2:
			var slen := hr.read_varint()
			b_type = hr.read_string(slen)
		elif fn == 3 and wt == 0:
			data_size = hr.read_varint()
		elif wt == 0:
			hr.read_varint()
		elif wt == 2:
			var l := hr.read_varint()
			hr.skip(l)

	if data_size > 33554432:
		push_error("Blob datasize exceeds 32 MiB: %d" % data_size)
		return {"error": "Blob too large"}

	var b_buf := f.get_buffer(data_size)
	var br := ProtoReader.new(b_buf)
	var raw_size := 0
	var zlib_slice := PackedByteArray()
	var raw_slice := PackedByteArray()
	while br.has_more():
		var tag := br.read_varint()
		var fn := tag >> 3
		var wt := tag & 0x7
		if fn == 1 and wt == 2:
			var rlen := br.read_varint()
			raw_slice = br.read_bytes(rlen)
		elif fn == 2 and wt == 0:
			raw_size = br.read_varint()
		elif fn == 3 and wt == 2:
			var zlen := br.read_varint()
			zlib_slice = br.read_bytes(zlen)
		elif wt == 0:
			br.read_varint()
		elif wt == 2:
			var l := br.read_varint()
			br.skip(l)

	var decomp := PackedByteArray()
	if not zlib_slice.is_empty() and raw_size > 0:
		decomp = zlib_slice.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	elif not raw_slice.is_empty():
		decomp = raw_slice

	return {
		"type": b_type,
		"decompressed": decomp,
		"offset": start_pos,
		"next_offset": f.get_position()
	}


static func decode_string_table(pr: ProtoReader, byte_len: int) -> Array[String]:
	var end_p := pr.pos + byte_len
	var table: Array[String] = []
	while pr.pos < end_p:
		var tag := pr.read_varint()
		var fn := tag >> 3
		var wt := tag & 0x7
		if fn == 1 and wt == 2:
			var slen := pr.read_varint()
			table.append(pr.read_string(slen))
		elif wt == 2:
			var l := pr.read_varint()
			pr.skip(l)
		elif wt == 0:
			pr.read_varint()
	return table
