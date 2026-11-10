class_name NdsFs
extends RefCounted

## Nintendo DS ROM header, FAT, and FNT parser for Pokémon Black/White (Item 45).
## Contract: docs/design_rom_asset_pipeline.md §2, §4–5 & docs/implementation_plan_rom_importer.md §2.

const SUPPORTED_GAME_CODES := {
	"IRBO": "Pokemon Black (USA)",
	"IRAO": "Pokemon White (USA)",
}

const CLEAN_SHA1 := {
	"IRBO": "26ad0b9967aa279c4a266ee6fb952b9cae6bb812",
	"IRAO": "a5be2ef5fd2b621fd3b4fb1cd1fd4bb71f3bf820",
}

const SPRITE_NARC_PATH := "/a/0/0/4"
const SPRITE_NARC_FALLBACK_ID := 246
const ITEM_ICON_NARC_PATH := "/a/0/2/5"
const ITEM_ICON_NARC_FALLBACK_ID := 267

static func validate_rom_path(rom_path: String, allow_test_user_dir: bool = false) -> Dictionary:
	var trimmed := rom_path.strip_edges()
	if trimmed == "":
		return {"ok": false, "error": "ROM path is empty."}
	var abs_path := ProjectSettings.globalize_path(trimmed).simplify_path()
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "error": "ROM file does not exist: %s" % abs_path}
	var game_root := ProjectSettings.globalize_path("res://").trim_suffix("/").simplify_path()
	var repo_root := game_root.get_base_dir().simplify_path()
	if not allow_test_user_dir:
		if abs_path == repo_root or abs_path.begins_with(repo_root + "/") or abs_path == game_root or abs_path.begins_with(game_root + "/"):
			return {"ok": false, "error": "ROM path must not reside inside the repository."}
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return {"ok": false, "error": "Cannot open ROM file."}
	var sz := int(fh.get_length())
	fh.close()
	if sz < 0x200:
		return {"ok": false, "error": "ROM file is too small (< 512 bytes)."}
	return {"ok": true, "path": abs_path, "file_size": sz}

static func compute_file_sha1(abs_path: String) -> String:
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	var rem := int(fh.get_length())
	while rem > 0:
		var chunk_sz := mini(rem, 1048576)
		var buf := fh.get_buffer(chunk_sz)
		if buf.is_empty():
			break
		ctx.update(buf)
		rem -= buf.size()
	fh.close()
	return ctx.finish().hex_encode()

static func read_header(rom_path: String, compute_sha1: bool = true, allow_test_user_dir: bool = false) -> Dictionary:
	var check := validate_rom_path(rom_path, allow_test_user_dir)
	if not bool(check.get("ok", false)):
		return check
	var abs_path: String = str(check["path"])
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return {"ok": false, "error": "Cannot open ROM file."}
	var hdr := fh.get_buffer(0x200)
	var file_size := int(fh.get_length())
	fh.close()
	if hdr.size() < 0x80:
		return {"ok": false, "error": "Truncated NDS header."}
	var title_bytes := PackedByteArray()
	for i in range(12):
		if hdr[i] != 0:
			title_bytes.append(hdr[i])
	var code_bytes := PackedByteArray()
	for i in range(0x0C, 0x10):
		if hdr[i] != 0:
			code_bytes.append(hdr[i])
	var title := title_bytes.get_string_from_ascii()
	var game_code := code_bytes.get_string_from_ascii()
	if not SUPPORTED_GAME_CODES.has(game_code):
		return {
			"ok": false,
			"error": "Unsupported ROM game code '%s': expected Pokémon Black (IRBO) or Pokémon White (IRAO) USA." % game_code,
			"game_code": game_code,
		}
	var fnt_offset := int(hdr.decode_u32(0x40))
	var fnt_size := int(hdr.decode_u32(0x44))
	var fat_offset := int(hdr.decode_u32(0x48))
	var fat_size := int(hdr.decode_u32(0x4C))
	var sha1 := compute_file_sha1(abs_path) if compute_sha1 else ""
	var expected_sha1: String = str(CLEAN_SHA1.get(game_code, ""))
	var is_clean := (sha1 != "" and sha1 == expected_sha1)
	var status := "clean" if is_clean else "modified — sprites only"
	var notice := "" if is_clean else "Modified ROM — only its Pokémon sprites are used"
	return {
		"ok": true,
		"path": abs_path,
		"title": title,
		"game_code": game_code,
		"fnt_offset": fnt_offset,
		"fnt_size": fnt_size,
		"fat_offset": fat_offset,
		"fat_size": fat_size,
		"file_size": file_size,
		"sha1": sha1,
		"expected_clean_sha1": expected_sha1,
		"status": status,
		"notice": notice,
	}

static func read_fat(fh: FileAccess, fat_offset: int, fat_size: int) -> Array[Vector2i]:
	fh.seek(fat_offset)
	var raw := fh.get_buffer(fat_size)
	var count := raw.size() / 8
	var entries: Array[Vector2i] = []
	entries.resize(count)
	for i in range(count):
		var s := int(raw.decode_u32(i * 8))
		var e := int(raw.decode_u32(i * 8 + 4))
		entries[i] = Vector2i(s, e)
	return entries

static func lookup_fnt_path(fh: FileAccess, fnt_offset: int, fnt_size: int, rel_path: String) -> int:
	if fnt_size < 8:
		return -1
	fh.seek(fnt_offset)
	var fnt := fh.get_buffer(fnt_size)
	var parts := rel_path.trim_prefix("/").trim_suffix("/").split("/", false)
	var cur_dir_id := 0xF000
	for p_idx in range(parts.size()):
		var part := parts[p_idx]
		var is_last := (p_idx == parts.size() - 1)
		var dir_index := cur_dir_id & 0x0FFF
		var main_off := dir_index * 8
		if main_off + 8 > fnt.size():
			return -1
		var sub_off := int(fnt.decode_u32(main_off))
		var cur_file_id := int(fnt.decode_u16(main_off + 4))
		var pos := sub_off
		var found := false
		while pos < fnt.size():
			var type_len := int(fnt[pos])
			pos += 1
			if type_len == 0:
				break
			var is_subdir := (type_len & 0x80) != 0
			var name_len := type_len & 0x7F
			if pos + name_len > fnt.size():
				return -1
			var name_str := fnt.slice(pos, pos + name_len).get_string_from_ascii()
			pos += name_len
			if is_subdir:
				if pos + 2 > fnt.size():
					return -1
				var sub_dir_id := int(fnt.decode_u16(pos))
				pos += 2
				if name_str == part and not is_last:
					cur_dir_id = sub_dir_id
					found = true
					break
			else:
				if name_str == part and is_last:
					return cur_file_id
				cur_file_id += 1
		if not found:
			return -1
	return -1

static func resolve_archive_id(fh: FileAccess, header: Dictionary, fat: Array[Vector2i], rel_path: String, fallback_id: int) -> int:
	var fid := lookup_fnt_path(fh, int(header["fnt_offset"]), int(header["fnt_size"]), rel_path)
	if fid >= 0 and fid < fat.size():
		return fid
	if fallback_id >= 0 and fallback_id < fat.size():
		var span := fat[fallback_id]
		if span.y > span.x + 16:
			fh.seek(span.x)
			var magic := fh.get_buffer(4).get_string_from_ascii()
			if magic == "NARC":
				return fallback_id
	return -1
