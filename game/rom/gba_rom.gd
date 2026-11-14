class_name GbaRom
extends RefCounted

## Pure GDScript Game Boy Advance ROM reader for Pokémon Emerald USA (BPEE, Item 55).
## Supports header/SHA-1 verification, seeked integer/byte reads, and GBA BIOS Type-10 LZ77.

const NdsFsRef := preload("res://rom/nds_fs.gd")

const EXPECTED_GAME_CODE := "BPEE"
const EXPECTED_SIZE := 16777216
const CLEAN_SHA1 := "f3ae088181bf583e55daf962a92bb46f4f1d07b7"
const ROM_ADDR_BASE := 0x08000000
const MAX_LZ77_OUTPUT := 16777216

var path: String = ""
var game_code: String = ""
var file_size: int = 0
var sha1: String = ""
var is_clean: bool = false
var _fh: FileAccess = null


static func rom_ptr_to_offset(ptr: int) -> int:
	if ptr >= ROM_ADDR_BASE and ptr < ROM_ADDR_BASE + EXPECTED_SIZE:
		return ptr - ROM_ADDR_BASE
	if ptr >= 0 and ptr < EXPECTED_SIZE:
		return ptr
	return -1


static func validate_rom_path(rom_path: String, allow_test_user_dir: bool = false) -> Dictionary:
	var check := NdsFsRef.validate_rom_path(rom_path, allow_test_user_dir)
	if not bool(check.get("ok", false)):
		return check
	var sz := int(check.get("file_size", 0))
	if sz != EXPECTED_SIZE:
		return {
			"ok": false,
			"error": "Unexpected GBA ROM size %d (expected %d bytes for Emerald USA)." % [sz, EXPECTED_SIZE],
		}
	return check


static func open_rom(rom_path: String, allow_test_user_dir: bool = false, require_clean_sha1: bool = true) -> Dictionary:
	var check := validate_rom_path(rom_path, allow_test_user_dir)
	if not bool(check.get("ok", false)):
		return check
	var abs_path := str(check["path"])
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return {"ok": false, "error": "Cannot open GBA ROM file."}
	var hdr := fh.get_buffer(0xC0)
	if hdr.size() < 0xC0:
		fh.close()
		return {"ok": false, "error": "Truncated GBA ROM header."}
	var code := hdr.slice(0xAC, 0xB0).get_string_from_ascii()
	if code != EXPECTED_GAME_CODE:
		fh.close()
		return {
			"ok": false,
			"error": "Unsupported GBA ROM game code '%s' (expected %s)." % [code, EXPECTED_GAME_CODE],
			"game_code": code,
		}
	var computed_sha1 := NdsFsRef.compute_file_sha1(abs_path)
	var clean := (computed_sha1 == CLEAN_SHA1)
	if require_clean_sha1 and not clean:
		fh.close()
		return {
			"ok": false,
			"error": "GBA ROM SHA-1 mismatch (expected clean Pokémon Emerald USA BPEE).",
			"sha1": computed_sha1,
		}
	var inst := new()
	inst.path = abs_path
	inst.game_code = code
	inst.file_size = int(check["file_size"])
	inst.sha1 = computed_sha1
	inst.is_clean = clean
	inst._fh = fh
	return {
		"ok": true,
		"rom": inst,
		"path": abs_path,
		"game_code": code,
		"file_size": inst.file_size,
		"sha1": computed_sha1,
		"is_clean": clean,
	}


func close() -> void:
	if _fh != null:
		_fh.close()
		_fh = null


func read_bytes(offset: int, length: int) -> PackedByteArray:
	if _fh == null or offset < 0 or length <= 0 or offset + length > file_size:
		return PackedByteArray()
	_fh.seek(offset)
	return _fh.get_buffer(length)


func read_u8(offset: int) -> int:
	var buf := read_bytes(offset, 1)
	if buf.size() < 1:
		return -1
	return int(buf[0])


func read_u16(offset: int) -> int:
	var buf := read_bytes(offset, 2)
	if buf.size() < 2:
		return -1
	return int(buf[0]) | (int(buf[1]) << 8)


func read_u32(offset: int) -> int:
	var buf := read_bytes(offset, 4)
	if buf.size() < 4:
		return -1
	return int(buf[0]) | (int(buf[1]) << 8) | (int(buf[2]) << 16) | (int(buf[3]) << 24)


func decompress_lz77(offset: int) -> Dictionary:
	if _fh == null or offset < 0 or offset + 4 > file_size:
		return {"ok": false, "error": "LZ77 offset out of range: %d" % offset}
	var hdr := read_bytes(offset, 4)
	if hdr.size() < 4 or hdr[0] != 0x10:
		return {"ok": false, "error": "Invalid GBA LZ77 header at offset %d" % offset}
	var out_len := int(hdr[1]) | (int(hdr[2]) << 8) | (int(hdr[3]) << 16)
	if out_len <= 0 or out_len > MAX_LZ77_OUTPUT:
		return {"ok": false, "error": "Unreasonable LZ77 output size %d at %d" % [out_len, offset]}
	var max_read := mini(file_size - offset, maxi(out_len * 2 + 64, 131072))
	var chunk := read_bytes(offset, max_read)
	return decompress_lz77_bytes(chunk)


static func decompress_lz77_bytes(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {"ok": false, "error": "Compressed buffer shorter than 4-byte LZ77 header."}
	if data[0] != 0x10:
		return {"ok": false, "error": "Expected LZ77 tag 0x10, got 0x%02x." % int(data[0])}
	var out_len := int(data[1]) | (int(data[2]) << 8) | (int(data[3]) << 16)
	if out_len < 0 or out_len > MAX_LZ77_OUTPUT:
		return {"ok": false, "error": "Invalid LZ77 decompressed size %d." % out_len}
	var out := PackedByteArray()
	out.resize(out_len)
	var in_pos := 4
	var out_pos := 0
	var in_size := data.size()
	while out_pos < out_len:
		if in_pos >= in_size:
			return {"ok": false, "error": "Truncated LZ77 stream (needed %d bytes, got %d)." % [out_len, out_pos]}
		var flags := int(data[in_pos])
		in_pos += 1
		for bit in range(8):
			if out_pos >= out_len:
				break
			if (flags & (0x80 >> bit)) == 0:
				if in_pos >= in_size:
					return {"ok": false, "error": "Truncated LZ77 literal byte."}
				out[out_pos] = data[in_pos]
				in_pos += 1
				out_pos += 1
			else:
				if in_pos + 1 >= in_size:
					return {"ok": false, "error": "Truncated LZ77 back-reference."}
				var b0 := int(data[in_pos])
				var b1 := int(data[in_pos + 1])
				in_pos += 2
				var length := (b0 >> 4) + 3
				var disp := (((b0 & 0x0F) << 8) | b1) + 1
				if disp <= 0 or disp > out_pos:
					return {"ok": false, "error": "Invalid LZ77 back-reference distance %d at out_pos %d." % [disp, out_pos]}
				for _k in range(length):
					if out_pos >= out_len:
						break
					out[out_pos] = out[out_pos - disp]
					out_pos += 1
	return {"ok": true, "data": out}
