extends Node

## Unit, Falsifying, and Env-Gated Integration Tests for Phase 2 ROM & Data Pack Importer (Item 45).
## Contract: docs/design_rom_asset_pipeline.md §7 & docs/implementation_plan_rom_importer.md §7.

const NdsFsRef := preload("res://rom/nds_fs.gd")
const NarcArchiveRef := preload("res://rom/narc.gd")
const NitroLzRef := preload("res://rom/lz.gd")
const NitroGfxRef := preload("res://rom/nitro_gfx.gd")
const Gen5CellsRef := preload("res://rom/gen5_cells.gd")
const DataPackImporterRef := preload("res://rom/data_pack.gd")
const FanSpritesImporterRef := preload("res://rom/fan_sprites.gd")
const RomImporterRef := preload("res://rom/importer.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")
const MapFetcherRef := preload("res://world/region_import/map_fetcher.gd")

const TEST_ROOT := "user://test/rom_importer_test"

func _put_u16(buf: PackedByteArray, off: int, val: int) -> void:
	buf[off] = val & 0xFF
	buf[off + 1] = (val >> 8) & 0xFF

func _put_u32(buf: PackedByteArray, off: int, val: int) -> void:
	buf[off] = val & 0xFF
	buf[off + 1] = (val >> 8) & 0xFF
	buf[off + 2] = (val >> 16) & 0xFF
	buf[off + 3] = (val >> 24) & 0xFF

func _put_ascii(buf: PackedByteArray, off: int, s: String) -> void:
	var b := s.to_ascii_buffer()
	for i in range(b.size()):
		buf[off + i] = b[i]

func _build_synthetic_nclr(all_same_color: bool = false) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(72)
	buf.fill(0)
	_put_ascii(buf, 0, "RLCN")
	_put_u32(buf, 8, 72)
	_put_u16(buf, 12, 16)
	_put_u16(buf, 14, 1)
	_put_ascii(buf, 16, "TTLP")
	_put_u32(buf, 20, 56)
	_put_u32(buf, 24, 3)
	_put_u32(buf, 32, 32)
	_put_u32(buf, 36, 16)
	for i in range(16):
		var bgr := 0
		if i > 0:
			if all_same_color:
				bgr = (10 << 10) | (10 << 5) | 10
			else:
				var r5 := (i * 2) & 0x1F
				var g5 := ((16 - i) * 2) & 0x1F
				var b5 := ((i * 5) + 3) & 0x1F
				bgr = (b5 << 10) | (g5 << 5) | r5
		_put_u16(buf, 40 + i * 2, bgr)
	return buf

func _build_synthetic_ncer() -> PackedByteArray:
	# Entry 0 shared 4-OAM cell bank:
	# OAM 0: (-48,-48) 64x64 shape=0 size=3 tile_off=0
	# OAM 1: (+16,-48) 32x64 shape=2 size=3 tile_off=32
	# OAM 2: (-48,+16) 64x32 shape=1 size=3 tile_off=48
	# OAM 3: (+16,+16) 32x32 shape=0 size=2 tile_off=64
	var buf := PackedByteArray()
	buf.resize(80)
	buf.fill(0)
	_put_ascii(buf, 0, "RECN")
	_put_u32(buf, 8, 80)
	_put_u16(buf, 12, 16)
	_put_u16(buf, 14, 1)
	_put_ascii(buf, 16, "KBEC")
	_put_u32(buf, 20, 64)
	_put_u16(buf, 24, 1) # n_banks = 1
	_put_u16(buf, 26, 0) # bank_attr = 0 (8-byte bank entry)
	_put_u32(buf, 28, 24) # bank_table_rel -> offset 48
	_put_u32(buf, 32, 1) # mapping_mode = 1 -> tile_step = 2
	# Bank 0 at offset 48 (8 bytes): n_oam = 4, oam_off = 0
	_put_u16(buf, 48, 4)
	_put_u32(buf, 52, 0)
	# 4 OAMs starting at offset 56 (24 bytes)
	var oam_defs := [
		[-48, 0, 3, -48, 0],
		[-48, 2, 3, 16, 32],
		[16, 1, 3, -48, 48],
		[16, 0, 2, 16, 64],
	]
	for idx in range(4):
		var od: Array = oam_defs[idx]
		var y_u8 := int(od[0]) & 0xFF
		var shape := int(od[1]) & 0x03
		var size := int(od[2]) & 0x03
		var x_u9 := int(od[3]) & 0x1FF
		var toff := int(od[4]) & 0x3FF
		var attr0 := y_u8 | (shape << 14)
		var attr1 := x_u9 | (size << 14)
		var attr2 := toff
		var pos := 56 + idx * 6
		_put_u16(buf, pos, attr0)
		_put_u16(buf, pos + 2, attr1)
		_put_u16(buf, pos + 4, attr2)
	return buf

func _build_synthetic_ncgr_from_canvas(canvas_indices: PackedByteArray, use_linear_12x12: bool = false) -> PackedByteArray:
	# Packs a 96x96 array of 4-bit palette indices into 144 8x8 tiles (4,608 bytes) + 48-byte NCGR header.
	var buf := PackedByteArray()
	buf.resize(48 + 4608)
	buf.fill(0)
	_put_ascii(buf, 0, "RGCN")
	_put_u32(buf, 8, 4656)
	_put_u16(buf, 12, 16)
	_put_u16(buf, 14, 1)
	_put_ascii(buf, 16, "RAHC")
	_put_u32(buf, 20, 4640)
	_put_u16(buf, 24, 18)
	_put_u16(buf, 26, 8)
	_put_u32(buf, 28, 3) # 4bpp
	_put_u32(buf, 36, 0) # unencrypted
	_put_u32(buf, 40, 4608)

	var oam_quads := [
		[0, 0, 8, 8, 0],
		[64, 0, 4, 8, 64],
		[0, 64, 8, 4, 96],
		[64, 64, 4, 4, 128],
	]
	for t_idx in range(144):
		var tx_px := 0
		var ty_px := 0
		if use_linear_12x12:
			tx_px = (t_idx % 12) * 8
			ty_px = (t_idx / 12) * 8
		else:
			for q in oam_quads:
				var q_start := int(q[4])
				var q_tw := int(q[2])
				var q_th := int(q[3])
				if t_idx >= q_start and t_idx < q_start + q_tw * q_th:
					var rel := t_idx - q_start
					tx_px = int(q[0]) + (rel % q_tw) * 8
					ty_px = int(q[1]) + (rel / q_tw) * 8
					break
		var tile_off := 48 + t_idx * 32
		for py in range(8):
			for px_pair in range(4):
				var x0 := tx_px + px_pair * 2
				var y0 := ty_px + py
				var p0 := int(canvas_indices[y0 * 96 + x0]) & 0x0F
				var p1 := int(canvas_indices[y0 * 96 + x0 + 1]) & 0x0F
				buf[tile_off + py * 4 + px_pair] = p0 | (p1 << 4)
	return buf

func _build_coherent_96x96_indices() -> PackedByteArray:
	var idx := PackedByteArray()
	idx.resize(96 * 96)
	idx.fill(0)
	# Draw a filled creature body spanning (16..80, 16..80) so it crosses both x=63|64 and y=63|64 seams
	for y in range(16, 80):
		for x in range(16, 80):
			var band := 1 + ((x / 8 + y / 8) % 12)
			idx[y * 96 + x] = band
	# Distinct quadrant corner markers inside the body
	idx[20 * 96 + 20] = 13
	idx[20 * 96 + 70] = 14
	idx[70 * 96 + 20] = 15
	idx[70 * 96 + 70] = 12
	return idx

func _build_synthetic_narc(subfiles: Array[PackedByteArray]) -> PackedByteArray:
	var count := subfiles.size()
	var btaf_size := 12 + count * 8
	var btnf_size := 16
	var gmif_payload := PackedByteArray()
	var offsets: Array[Vector2i] = []
	for sf in subfiles:
		var s := gmif_payload.size()
		gmif_payload.append_array(sf)
		var e := gmif_payload.size()
		while (gmif_payload.size() % 4) != 0:
			gmif_payload.append(0xFF)
		offsets.append(Vector2i(s, e))
	var gmif_size := 8 + gmif_payload.size()
	var total_size := 16 + btaf_size + btnf_size + gmif_size

	var buf := PackedByteArray()
	buf.resize(16 + btaf_size + btnf_size + 8)
	buf.fill(0)
	_put_ascii(buf, 0, "NARC")
	_put_u16(buf, 4, 0xFFFE)
	_put_u16(buf, 6, 0x0100)
	_put_u32(buf, 8, total_size)
	_put_u16(buf, 12, 16)
	_put_u16(buf, 14, 3)

	_put_ascii(buf, 16, "BTAF")
	_put_u32(buf, 20, btaf_size)
	_put_u32(buf, 24, count)
	for i in range(count):
		_put_u32(buf, 28 + i * 8, offsets[i].x)
		_put_u32(buf, 28 + i * 8 + 4, offsets[i].y)

	var btnf_pos := 16 + btaf_size
	_put_ascii(buf, btnf_pos, "BTNF")
	_put_u32(buf, btnf_pos + 4, btnf_size)

	var gmif_pos := btnf_pos + btnf_size
	_put_ascii(buf, gmif_pos, "GMIF")
	_put_u32(buf, gmif_pos + 4, gmif_size)
	buf.append_array(gmif_payload)
	return buf

func _test_lz_decompression() -> bool:
	# 1. Raw 16-entry table guard: starts with u32 16 = 0x10 0x00 0x00 0x00 (dec_len == 0)
	var raw_table := PackedByteArray([0x10, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00])
	var raw_res := NitroLzRef.decompress(raw_table)
	if not bool(raw_res.get("ok", false)) or str(raw_res.get("format", "")) != "RAW":
		push_error("Expected dec_len == 0 stream to be treated as RAW")
		return false

	# 2. LZ10 stream: 4 literals 'A','B','C','D' followed by 1 back-ref length=4 disp=4 -> "ABCDABCD"
	# Header: 0x10, dec_len = 8 (0x08, 0x00, 0x00)
	# Flags: 0b00001000 = 0x08 (4 literals, then 1 compressed token)
	# Token: length=4 -> (4-3)=1 in top nibble, disp=4 -> (4-1)=3 -> b0=0x10, b1=0x03
	var lz10_stream := PackedByteArray([
		0x10, 0x08, 0x00, 0x00,
		0x08,
		0x41, 0x42, 0x43, 0x44,
		0x10, 0x03,
	])
	var lz10_res := NitroLzRef.decompress(lz10_stream)
	if not bool(lz10_res.get("ok", false)) or str(lz10_res.get("format", "")) != "LZ10":
		push_error("LZ10 decompression failed")
		return false
	if (lz10_res["data"] as PackedByteArray).get_string_from_ascii() != "ABCDABCD":
		push_error("LZ10 output mismatch")
		return false

	# 3. LZ11 stream: 2 literals 'X','Y' followed by indicator=2 (length = 2+1 = 3), disp=2 -> "XYXYX"
	var lz11_stream := PackedByteArray([
		0x11, 0x05, 0x00, 0x00,
		0x20,
		0x58, 0x59,
		0x20, 0x01,
	])
	var lz11_res := NitroLzRef.decompress(lz11_stream)
	if not bool(lz11_res.get("ok", false)) or str(lz11_res.get("format", "")) != "LZ11":
		push_error("LZ11 decompression failed")
		return false
	if (lz11_res["data"] as PackedByteArray).get_string_from_ascii() != "XYXYX":
		push_error("LZ11 output mismatch")
		return false
	return true

func _test_narc_ncgr_ncer_and_falsifiers() -> bool:
	var unit_dir := ProjectSettings.globalize_path(TEST_ROOT + "/narc_unit")
	DataPackImporterRef._remove_dir_recursive(unit_dir)
	DirAccess.make_dir_recursive_absolute(unit_dir)

	var canvas_indices := _build_coherent_96x96_indices()
	var ncer_bytes := _build_synthetic_ncer()
	var nclr_bytes := _build_synthetic_nclr(false)
	var ncgr_bytes := _build_synthetic_ncgr_from_canvas(canvas_indices, false)

	var narc_bytes := _build_synthetic_narc([ncer_bytes, ncgr_bytes, nclr_bytes])
	var narc_path := unit_dir.path_join("test.narc")
	var fh_w := FileAccess.open(narc_path, FileAccess.WRITE)
	fh_w.store_buffer(narc_bytes)
	fh_w.close()

	var fh_r := FileAccess.open(narc_path, FileAccess.READ)
	var arc := NarcArchiveRef.parse(fh_r, 0, narc_bytes.size())
	if arc == null or arc.file_count() != 3:
		fh_r.close()
		push_error("NarcArchive failed to parse synthetic NARC")
		return false

	var ncer := Gen5CellsRef.parse_ncer(arc.read_subfile(fh_r, 0))
	var ncgr := NitroGfxRef.parse_ncgr(arc.read_subfile(fh_r, 1))
	var pal := NitroGfxRef.parse_nclr(arc.read_subfile(fh_r, 2))
	fh_r.close()

	if not bool(ncer.get("ok", false)) or not bool(ncgr.get("ok", false)) or pal.size() != 16:
		push_error("Failed to parse synthetic NCER/NCGR/NCLR")
		return false

	var oams: Array = ncer["banks"][0]
	var img := Gen5CellsRef.assemble_sprite_image(ncgr["tile_bytes"], pal, oams, 96, 96)
	if img.get_width() != 96 or img.get_height() != 96:
		push_error("Assembled image is not 96x96")
		return false

	# Verify exact pixel placement across all 4 OAM quadrants
	if img.get_pixel(20, 20) != pal[13] or img.get_pixel(70, 20) != pal[14] or img.get_pixel(20, 70) != pal[15] or img.get_pixel(70, 70) != pal[12]:
		push_error("4-OAM quadrant pixel placement mismatch")
		return false

	var valid_metrics := Gen5CellsRef.compute_sprite_metrics(img)
	var valid_check := Gen5CellsRef.validate_sprite_metrics(valid_metrics)
	if not bool(valid_check.get("ok", false)):
		push_error("Valid synthetic sprite failed metric validation: %s" % str(valid_check.get("error", "")))
		return false

	# Falsifier A: Zero-variance monochrome palette -> rejected
	var mono_pal := NitroGfxRef.parse_nclr(_build_synthetic_nclr(true))
	var mono_img := Gen5CellsRef.assemble_sprite_image(ncgr["tile_bytes"], mono_pal, oams, 96, 96)
	var mono_check := Gen5CellsRef.validate_sprite_metrics(Gen5CellsRef.compute_sprite_metrics(mono_img))
	if bool(mono_check.get("ok", false)):
		push_error("Falsifier A failed: zero-variance palette was not rejected")
		return false

	# Falsifier B: Wrong XOR seed / scrambled tile bytes -> rejected by neighbor_coherence < 0.65
	var scrambled_tiles := (ncgr["tile_bytes"] as PackedByteArray).duplicate()
	var seed_val := 0x5A3C9E17
	for i in range(scrambled_tiles.size()):
		seed_val = int((seed_val * 1103515245 + 12345) & 0x7FFFFFFF)
		if scrambled_tiles[i] != 0:
			scrambled_tiles[i] = 1 + (seed_val % 15) + ((1 + ((seed_val >> 4) % 15)) << 4)
	var scram_img := Gen5CellsRef.assemble_sprite_image(scrambled_tiles, pal, oams, 96, 96)
	var scram_check := Gen5CellsRef.validate_sprite_metrics(Gen5CellsRef.compute_sprite_metrics(scram_img))
	if bool(scram_check.get("ok", false)):
		push_error("Falsifier B failed: scrambled XOR tile buffer was not rejected")
		return false

	# Falsifier C: Linear 12x12 tile order -> breaks OAM seam at x=63|64 and y=63|64 -> rejected
	var seam_canvas := PackedByteArray()
	seam_canvas.resize(96 * 96)
	seam_canvas.fill(0)
	# Only fill x=0..63, y=16..80 in linear order so when decoded via 4-OAMs the seam is severed
	for t in range(64):
		for b in range(32):
			pass
	var broken_tiles := PackedByteArray()
	broken_tiles.resize(4608)
	broken_tiles.fill(0)
	# Put opaque pixels on x=63 (right edge of OAM 0: tiles 7,15,23,31,39,47,55,63) while leaving OAM 1 (tiles 64..95) transparent
	for row_t in range(8):
		var t_idx := row_t * 8 + 7
		var base := t_idx * 32
		for py in range(8):
			var col_idx := 1 + ((row_t + py) % 14)
			for px_pair in range(4):
				broken_tiles[base + py * 4 + px_pair] = col_idx | (col_idx << 4)
	var broken_seam_img := Gen5CellsRef.assemble_sprite_image(broken_tiles, pal, oams, 96, 96)
	var broken_seam_check := Gen5CellsRef.validate_sprite_metrics(Gen5CellsRef.compute_sprite_metrics(broken_seam_img))
	if bool(broken_seam_check.get("ok", false)):
		push_error("Falsifier C failed: broken OAM seam sprite was not rejected")
		return false

	DataPackImporterRef._remove_dir_recursive(unit_dir)
	return true

func _test_nds_header_and_path_guards() -> bool:
	# 1. Path inside repository must be rejected when allow_test_user_dir == false
	var repo_check := NdsFsRef.validate_rom_path("res://project.godot", false)
	if bool(repo_check.get("ok", false)):
		push_error("Expected ROM path inside res:// to be rejected")
		return false

	# 2. Synthetic NDS header checks in user://test/
	var hdr_dir := ProjectSettings.globalize_path(TEST_ROOT + "/hdr_unit")
	DataPackImporterRef._remove_dir_recursive(hdr_dir)
	DirAccess.make_dir_recursive_absolute(hdr_dir)

	var bad_rom := hdr_dir.path_join("bad_code.nds")
	var buf := PackedByteArray()
	buf.resize(1024)
	buf.fill(0)
	_put_ascii(buf, 0, "POKEMON B2")
	_put_ascii(buf, 0x0C, "IREO") # Black 2 -> unsupported in v1
	var fh := FileAccess.open(bad_rom, FileAccess.WRITE)
	fh.store_buffer(buf)
	fh.close()

	var bad_res := NdsFsRef.read_header(bad_rom, true, true)
	if bool(bad_res.get("ok", false)):
		push_error("Expected IREO game code to be rejected")
		return false

	# 3. Modified IRBO header -> accepted with status == "modified — sprites only"
	_put_ascii(buf, 0, "POKEMON B")
	_put_ascii(buf, 0x0C, "IRBO")
	var mod_rom := hdr_dir.path_join("mod_irbo.nds")
	var fh2 := FileAccess.open(mod_rom, FileAccess.WRITE)
	fh2.store_buffer(buf)
	fh2.close()

	var mod_res := NdsFsRef.read_header(mod_rom, true, true)
	if not bool(mod_res.get("ok", false)):
		push_error("Expected modified IRBO header to be accepted for sprite-only validation")
		return false
	if str(mod_res.get("status", "")) != "modified — sprites only":
		push_error("Expected status == 'modified — sprites only', got %s" % str(mod_res.get("status", "")))
		return false
	if str(mod_res.get("notice", "")) != "Modified ROM — only its Pokémon sprites are used":
		push_error("Unexpected modified ROM notice")
		return false

	DataPackImporterRef._remove_dir_recursive(hdr_dir)
	return true

func _test_manifests_guardrails_and_asset_db() -> bool:
	# 1. Consent summary
	var consent := DataPackImporterRef.get_consent_summary()
	if int(consent.get("total_bytes", 0)) != 13926586:
		push_error("Expected total_bytes == 13926586, got %d" % int(consent.get("total_bytes", 0)))
		return false
	if not is_equal_approx(float(consent.get("size_mib", 0.0)), 13.3):
		push_error("Expected size_mib == 13.3")
		return false

	# 2. Fan sprite ID < 650 guardrail
	for forbidden_id in [1, 151, 487, 609, 649]:
		var chk := FanSpritesImporterRef.validate_sprite_id(forbidden_id)
		if bool(chk.get("ok", false)):
			push_error("FanSpritesImporter failed to reject sprite ID %d < 650" % forbidden_id)
			return false
	for allowed_id in [650, 778, 887, 905, 10033, 10090]:
		var chk := FanSpritesImporterRef.validate_sprite_id(allowed_id)
		if not bool(chk.get("ok", false)):
			push_error("FanSpritesImporter rejected valid sprite ID %d" % allowed_id)
			return false

	# 3. 96x96 canvas normalization for 90x97 (Xurkitree back) and 94x94 (Mega Pinsir back_shiny)
	for dims in [Vector2i(90, 97), Vector2i(94, 94)]:
		var raw_img := Image.create(dims.x, dims.y, false, Image.FORMAT_RGBA8)
		raw_img.fill(Color8(120, 80, 200, 255))
		var norm_img := FanSpritesImporterRef.normalize_image_to_96x96(raw_img)
		if norm_img.get_width() != 96 or norm_img.get_height() != 96:
			push_error("normalize_image_to_96x96 failed for %s" % str(dims))
			return false

	# 4. SHA-256 mismatch falsifier on DataPackImporter
	var corrupt_staging := ProjectSettings.globalize_path(TEST_ROOT + "/corrupt_staging")
	DataPackImporterRef._remove_dir_recursive(corrupt_staging)
	var fake_transport := {
		"responses": {
			"https://raw.githubusercontent.com/PokeAPI/pokeapi/5cbeb3f3eb55a9b86da52c4869336f9d61fdd6d7/data/v2/csv/ability_names.csv": {
				"code": 200,
				"body": "corrupted,csv,bytes\n".to_utf8_buffer(),
			}
		}
	}
	var fake_fetcher := MapFetcherRef.new(TEST_ROOT + "/fake_map", fake_transport)
	var bad_dp := DataPackImporterRef.verify_and_stage_data_pack(corrupt_staging, "", fake_fetcher)
	if bool(bad_dp.get("ok", false)) or str(bad_dp.get("failed_file", "")) != "ability_names.csv":
		push_error("Expected corrupted ability_names.csv to be rejected")
		return false

	# 5. AssetDB degraded mode on empty cache
	var empty_cache := TEST_ROOT + "/empty_cache"
	AssetDBRef.clear_memory_cache()
	if AssetDBRef.is_rom_ready(empty_cache) or AssetDBRef.is_data_ready(empty_cache):
		push_error("Expected empty_cache to report not ready")
		return false
	var sil_tex := AssetDBRef.sprite_front(609, false, "", empty_cache)
	if sil_tex == null or sil_tex.get_width() != 96 or sil_tex.get_height() != 96:
		push_error("Expected 96x96 silhouette texture in degraded mode")
		return false
	if not bool(sil_tex.get_meta("is_placeholder", false)) or not bool(sil_tex.get_meta("sprite_pending", false)):
		push_error("Expected silhouette texture metadata is_placeholder=true and sprite_pending=true")
		return false
	if AssetDBRef.display_name("species", 609, empty_cache) != "#609":
		push_error("Expected fallback species name '#609'")
		return false
	var item_tex := AssetDBRef.item_icon(1, empty_cache)
	if item_tex == null or item_tex.get_width() != 24 or item_tex.get_height() != 24:
		push_error("Expected 24x24 item placeholder icon")
		return false

	# 6. Credits lookup
	if not AssetDBRef.credits(609).is_empty():
		push_error("Expected #609 (ROM sprite) to have empty fan sprite credits")
		return false
	if AssetDBRef.credits(887).is_empty():
		push_error("Expected #887 (Dragapult) to have non-empty fan sprite credits")
		return false
	if AssetDBRef.credits(94, "mega").is_empty() or AssetDBRef.credits(6, "mega-x").is_empty():
		push_error("Expected Mega #94 and Mega-X #6 to have non-empty fan sprite credits")
		return false

	# 7. Gen 6+ 18x18 type chart spot checks
	if not is_equal_approx(AssetDBRef.type_effectiveness("fairy", ["dragon", "ghost"]), 2.0):
		push_error("Expected Fairy -> Dragon/Ghost == 2.0")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("dragon", ["ghost", "fairy"]), 0.0):
		push_error("Expected Dragon -> Ghost/Fairy == 0.0")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("ghost", ["ghost", "steel"]), 2.0):
		push_error("Expected Ghost -> Ghost/Steel == 2.0 in Gen 6+")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("dark", ["steel"]), 1.0):
		push_error("Expected Dark -> Steel == 1.0 in Gen 6+")
		return false
	return true

func _test_env_gated_real_imports() -> bool:
	var e2e_cache := TEST_ROOT + "/e2e_cache"
	DataPackImporterRef._remove_dir_recursive(ProjectSettings.globalize_path(e2e_cache))
	AssetDBRef.clear_memory_cache()

	var bw_rom := OS.get_environment("TENTH_SPRING_ROM_BW").strip_edges()
	if bw_rom != "" and FileAccess.file_exists(bw_rom):
		var rom_res := RomImporterRef.import_bw_rom(bw_rom, e2e_cache, false)
		if not bool(rom_res.get("ok", false)):
			push_error("Real Black/White ROM import failed: %s" % str(rom_res.get("error", "")))
			return false
		if int(rom_res.get("front_sprites_decoded", 0)) != 649 or int(rom_res.get("back_sprites_decoded", 0)) != 649:
			push_error("Expected 649/649 front and back sprites from real ROM")
			return false
		AssetDBRef.clear_memory_cache()
		if not AssetDBRef.is_rom_ready(e2e_cache):
			push_error("AssetDB.is_rom_ready returned false after real ROM import")
			return false
		var chand_tex := AssetDBRef.sprite_front(609, false, "", e2e_cache)
		if chand_tex == null or bool(chand_tex.get_meta("is_placeholder", true)):
			push_error("Expected real decoded texture for #609 after ROM import")
			return false
	else:
		print("SKIPPED real Black/White ROM import — TENTH_SPRING_ROM_BW not set")

	var dp_dir := OS.get_environment("TENTH_SPRING_DATA_PACK").strip_edges()
	if dp_dir != "" and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dp_dir)):
		var dp_res := RomImporterRef.import_data_pack(dp_dir, null, e2e_cache)
		if not bool(dp_res.get("ok", false)):
			push_error("Real data pack import failed: %s" % str(dp_res.get("error", "")))
			return false
		if int(dp_res.get("species_count", 0)) != 905 or int(dp_res.get("mega_form_count", 0)) != 48 or int(dp_res.get("move_count", 0)) != 778:
			push_error("Unexpected counts from real data pack import: %s" % str(dp_res))
			return false
		AssetDBRef.clear_memory_cache()
		if not AssetDBRef.is_data_ready(e2e_cache):
			push_error("AssetDB.is_data_ready returned false after real data pack import")
			return false
		var dragapult := AssetDBRef.species(887, "", e2e_cache)
		if dragapult.get("types", []) != ["dragon", "ghost"]:
			push_error("Expected #887 types == ['dragon', 'ghost']")
			return false
		var mega_gengar := AssetDBRef.species(94, "mega", e2e_cache)
		var mg_stats: Dictionary = mega_gengar.get("base_stats", {})
		if int(mg_stats.get("spa", 0)) != 170:
			push_error("Expected Mega #94 SpA == 170, got %d" % int(mg_stats.get("spa", 0)))
			return false
		var drag_tex := AssetDBRef.sprite_front(887, false, "", e2e_cache)
		if drag_tex == null or bool(drag_tex.get_meta("is_placeholder", true)):
			push_error("Expected real fan sprite texture for #887")
			return false
	else:
		print("SKIPPED real data pack import — TENTH_SPRING_DATA_PACK not set")

	DataPackImporterRef._remove_dir_recursive(ProjectSettings.globalize_path(e2e_cache))
	AssetDBRef.clear_memory_cache()
	return true

func run_test() -> bool:
	if not _test_lz_decompression():
		return false
	if not _test_narc_ncgr_ncer_and_falsifiers():
		return false
	if not _test_nds_header_and_path_guards():
		return false
	if not _test_manifests_guardrails_and_asset_db():
		return false
	if not _test_env_gated_real_imports():
		return false
	return true
