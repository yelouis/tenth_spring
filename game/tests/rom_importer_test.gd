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
	# 1. Consent summary (32 PokéAPI CSVs = 12584275 + 1216 fan sprites = 1387217 -> 13971492 bytes)
	var consent := DataPackImporterRef.get_consent_summary()
	if int(consent.get("total_bytes", 0)) != 13971492:
		push_error("Expected total_bytes == 13971492, got %d" % int(consent.get("total_bytes", 0)))
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

	# 3. 96x96 canvas normalization for 90x97 (dex 796 back) and 94x94 (Mega dex 127 back_shiny)
	for dims in [Vector2i(90, 97), Vector2i(94, 94)]:
		var raw_img := Image.create(dims.x, dims.y, false, Image.FORMAT_RGBA8)
		raw_img.fill(Color8(120, 80, 200, 255))
		var norm_img := FanSpritesImporterRef.normalize_image_to_96x96(raw_img)
		if norm_img.get_width() != 96 or norm_img.get_height() != 96:
			push_error("normalize_image_to_96x96 failed for %s" % str(dims))
			return false

	# 4. SHA-256 / size mismatch falsifier on DataPackImporter (and pinned raw_base_url resolution)
	var sources_doc := DataPackImporterRef.load_json_res(DataPackImporterRef.DATA_SOURCES_PATH)
	var pokeapi_url := DataPackImporterRef.resolve_raw_base_url(sources_doc.get("pokeapi", {}), "csv_path")
	var fan_url := DataPackImporterRef.resolve_raw_base_url(sources_doc.get("fan_sprites", {}), "sprite_path")
	if pokeapi_url != "https://raw.githubusercontent.com/PokeAPI/pokeapi/5cbeb3f3eb55a9b86da52c4869336f9d61fdd6d7/data/v2/csv":
		push_error("Unexpected PokeAPI raw_base_url: %s" % pokeapi_url)
		return false
	if fan_url != "https://raw.githubusercontent.com/PokeAPI/sprites/1b3b7c0a538dd2226ae08d0d2f8955125075bbd4/sprites/pokemon/versions/generation-v/black-white":
		push_error("Unexpected fan sprites raw_base_url: %s" % fan_url)
		return false
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
	if bool(bad_dp.get("ok", false)) or str(bad_dp.get("failed_file", "")) != "ability_names.csv" or str(bad_dp.get("error", "")).begins_with("Failed to fetch"):
		push_error("Expected corrupted ability_names.csv to be rejected on size/SHA-256, got: %s" % str(bad_dp))
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
		push_error("Expected #887 to have non-empty fan sprite credits")
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
		# Item 62: BW /a/0/0/7 box icons + --no-rom / missing cache null behavior
		var pikachu_box := AssetDBRef.pokemon_box_icon(25, e2e_cache, false)
		if pikachu_box == null or pikachu_box.get_width() != 32 or pikachu_box.get_height() != 32:
			push_error("Expected 32x32 BW /a/0/0/7 box icon for #25 after import")
			return false
		if AssetDBRef.pokemon_box_icon(25, e2e_cache, true) != null:
			push_error("Expected AssetDB.pokemon_box_icon with no_rom=true to return null")
			return false
		if AssetDBRef.pokemon_box_icon(0, e2e_cache, false) != null or AssetDBRef.pokemon_box_icon(650, e2e_cache, false) != null:
			push_error("Expected out-of-range AssetDB.pokemon_box_icon to return null")
			return false
		var auto_cache := TEST_ROOT + "/auto_bw_cache"
		var auto_pikachu := AssetDBRef.pokemon_box_icon(25, auto_cache, false)
		DataPackImporterRef._remove_dir_recursive(ProjectSettings.globalize_path(auto_cache))
		if auto_pikachu == null or auto_pikachu.get_width() != 32 or auto_pikachu.get_height() != 32:
			push_error("Expected AssetDB.pokemon_box_icon to auto-import 32x32 icon under user://test when TENTH_SPRING_ROM_BW set")
			return false
	else:
		print("SKIPPED real Black/White ROM import — TENTH_SPRING_ROM_BW not set")
		var empty_bw := TEST_ROOT + "/missing_bw_cache"
		DataPackImporterRef._remove_dir_recursive(ProjectSettings.globalize_path(empty_bw))
		if AssetDBRef.pokemon_box_icon(25, empty_bw, false) != null:
			push_error("Expected AssetDB.pokemon_box_icon without BW ROM to return null")
			return false

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

func _write_text_file(path: String, text: String) -> void:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(text)
	fh.close()


func _test_data_pack_v2_synthetic_and_outdated() -> bool:
	var root := ProjectSettings.globalize_path(TEST_ROOT + "/v2_mini")
	DataPackImporterRef._remove_dir_recursive(root)
	var csv_dir := root.path_join("csv")
	var out_dir := root.path_join("staged")
	DirAccess.make_dir_recursive_absolute(csv_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Minimal synthetic CSV fixture covering every Item 90 file & field (zero real names)
	_write_text_file(csv_dir.path_join("types.csv"), "id,identifier\n1,normal\n10,fire\n11,water\n13,electric\n")
	_write_text_file(csv_dir.path_join("pokemon.csv"),
		"id,identifier,species_id,height,weight,base_experience,order,is_default\n"
		+ "1,sp1,1,7,69,64,1,1\n"
		+ "2,sp2,2,10,130,142,2,1\n"
		+ "236,sp236,236,7,210,42,236,1\n"
		+ "106,sp106,106,15,498,159,106,1\n"
		+ "107,sp107,107,14,502,159,107,1\n"
		+ "237,sp237,237,14,480,159,237,1\n"
		+ "458,sp458,458,10,650,69,458,1\n"
		+ "226,sp226,226,21,2200,170,226,1\n"
		+ "10026,sp681-blade,2,17,530,234,999,0\n"
		+ "10033,sp1-mega,1,24,1555,281,998,0\n"
		+ "10195,sp1-gmax,1,240,10000,281,997,0\n"
		+ "10077,sp1-primal,1,98,4300,347,996,0\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_species.csv"),
		"id,identifier,generation_id,evolves_from_species_id,evolution_chain_id,capture_rate,base_happiness,is_baby,growth_rate_id,gender_rate,is_legendary,is_mythical\n"
		+ "1,sp1,1,,1,45,70,0,4,1,0,0\n"
		+ "2,sp2,1,1,1,45,70,0,4,1,0,0\n"
		+ "236,sp236,2,,10,75,70,1,2,0,0,0\n"
		+ "106,sp106,1,236,10,45,70,0,2,0,0,0\n"
		+ "107,sp107,1,236,10,45,70,0,2,0,0,0\n"
		+ "237,sp237,2,236,10,45,70,0,2,0,0,0\n"
		+ "458,sp458,4,,20,25,70,1,1,4,0,0\n"
		+ "226,sp226,2,458,20,25,70,0,1,4,0,0\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_stats.csv"),
		"pokemon_id,stat_id,base_stat,effort\n"
		+ "1,1,45,0\n1,2,49,0\n1,3,49,0\n1,4,65,1\n1,5,65,0\n1,6,45,0\n"
		+ "2,1,60,0\n2,2,50,0\n2,3,140,2\n2,4,50,0\n2,5,140,1\n2,6,60,0\n"
		+ "10026,1,60,0\n10026,2,140,2\n10026,3,50,0\n10026,4,140,1\n10026,5,50,0\n10026,6,60,0\n"
		+ "10033,1,80,0\n10033,2,100,0\n10033,3,123,0\n10033,4,122,2\n10033,5,120,1\n10033,6,80,0\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_types.csv"),
		"pokemon_id,type_id,slot\n"
		+ "1,1,1\n2,10,1\n10026,10,1\n10026,13,2\n10033,1,1\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_abilities.csv"),
		"pokemon_id,ability_id,is_hidden,slot\n"
		+ "1,65,0,1\n1,34,1,3\n10026,176,0,1\n10033,47,0,1\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_forms.csv"),
		"id,identifier,form_identifier,pokemon_id,introduced_in_version_group_id,is_default,is_battle_only,is_mega,form_order,order\n"
		+ "10125,sp2-blade,blade,10026,15,1,1,0,2,2\n"
		+ "10033,sp1-mega,mega,10033,15,1,1,1,2,2\n"
		+ "10364,sp1-gmax,gmax,10195,20,1,1,0,3,3\n"
		+ "10179,sp1-primal,primal,10077,16,1,1,0,4,4\n"
	)
	_write_text_file(csv_dir.path_join("move_flags.csv"), "id,identifier\n1,contact\n8,punch\n9,sound\n")
	_write_text_file(csv_dir.path_join("move_flag_map.csv"), "move_id,move_flag_id\n5,8\n5,1\n33,1\n")
	_write_text_file(csv_dir.path_join("move_meta.csv"), "move_id,meta_category_id,meta_ailment_id,min_hits,max_hits,min_turns,max_turns,drain,healing,crit_rate,ailment_chance,flinch_chance,stat_chance\n5,0,0,,,,,0,0,0,0,0,0\n33,0,0,,,,,0,0,0,0,0,0\n45,2,0,,,,,0,0,0,0,0,0\n")
	_write_text_file(csv_dir.path_join("move_meta_stat_changes.csv"), "move_id,stat_id,change\n45,2,-1\n")
	_write_text_file(csv_dir.path_join("moves.csv"),
		"id,identifier,generation_id,type_id,power,pp,accuracy,priority,target_id,damage_class_id,effect_id,effect_chance\n"
		+ "5,mv5,1,1,80,20,85,0,10,2,1,\n"
		+ "33,mv33,1,1,40,35,100,0,10,2,1,\n"
		+ "45,mv45,1,1,,40,100,0,11,1,19,\n"
	)
	_write_text_file(csv_dir.path_join("pokemon_moves.csv"),
		"pokemon_id,version_group_id,move_id,pokemon_move_method_id,level,order\n"
		+ "1,20,33,1,1,1\n"
		+ "1,20,5,4,0,\n"
		+ "1,18,45,4,0,\n"
		+ "2,18,33,1,1,1\n"
		+ "2,18,45,4,0,\n"
	)
	_write_text_file(csv_dir.path_join("machines.csv"),
		"machine_number,version_group_id,item_id,move_id\n"
		+ "0,20,1288,5\n"
		+ "1,18,305,33\n"
		+ "2,20,306,45\n"
	)
	_write_text_file(csv_dir.path_join("evolution_triggers.csv"), "id,identifier\n1,level-up\n2,trade\n3,use-item\n")
	_write_text_file(csv_dir.path_join("pokemon_evolution.csv"),
		"id,evolved_species_id,evolution_trigger_id,version_group_id,is_default,trigger_item_id,minimum_level,gender_id,location_id,held_item_id,time_of_day,known_move_id,known_move_type_id,minimum_happiness,minimum_beauty,minimum_affection,relative_physical_stats,party_species_id,party_type_id,trade_species_id,needs_overworld_rain,turn_upside_down,needs_multiplayer,near_special_rock,region_id,required_pokemon_form_id,evolved_pokemon_form_id,used_move_id,minimum_move_count,minimum_steps,minimum_damage_taken,nature_bitmask,condition_expression,percentage_chance\n"
		+ "1,2,1,8,1,,,1,10,,,,0,0,170,2,,0,17,0,1,1,0,1,7,0,0,828,20,0,49,0,,0\n"
		+ "2,106,1,3,1,,20,,,,,,,,,,1,,,,0,0,0,0,,,,,,,,,,0\n"
		+ "3,107,1,3,1,,20,,,,,,,,,,-1,,,,0,0,0,0,,,,,,,,,,0\n"
		+ "4,237,1,3,1,,20,,,,,,,,,,0,,,,0,0,0,0,,,,,,,,,,0\n"
		+ "5,226,1,8,1,,,,,,,,,,,,,223,,,0,0,0,0,,,,,,,,,,0\n"
	)
	_write_text_file(csv_dir.path_join("item_categories.csv"), "id,pocket_id,identifier\n37,4,all-machines\n")
	_write_text_file(csv_dir.path_join("items.csv"), "id,identifier,category_id,cost,fling_power\n1288,it1288,37,3000,\n")
	_write_text_file(csv_dir.path_join("pokemon_species_names.csv"), "pokemon_species_id,local_language_id,name\n1,9,SynthOne\n2,9,SynthTwo\n")
	_write_text_file(csv_dir.path_join("pokemon_form_names.csv"), "pokemon_form_id,local_language_id,form_name,pokemon_name\n")
	_write_text_file(csv_dir.path_join("move_names.csv"), "move_id,local_language_id,name\n5,9,SynthMoveFive\n33,9,SynthMoveThirtyThree\n")
	_write_text_file(csv_dir.path_join("ability_names.csv"), "ability_id,local_language_id,name\n")
	_write_text_file(csv_dir.path_join("item_names.csv"), "item_id,local_language_id,name\n")
	_write_text_file(csv_dir.path_join("type_names.csv"), "type_id,local_language_id,name\n1,9,Normal\n")

	var cres := DataPackImporterRef._compile_verified_csvs(csv_dir, out_dir, "synthetic_commit")
	if not bool(cres.get("ok", false)):
		push_error("Synthetic v2 compile failed: %s" % str(cres))
		return false

	AssetDBRef.clear_memory_cache()
	var staged_res := TEST_ROOT + "/v2_mini/staged"
	var sp1 := AssetDBRef.species(1, "", staged_res)
	if int(sp1.get("weight_hg", 0)) != 69 or int(sp1.get("height_dm", 0)) != 7:
		push_error("Expected synthetic #1 weight_hg=69 height_dm=7, got %s" % str(sp1))
		return false
	var mv5 := AssetDBRef.move(5, staged_res)
	if mv5.get("flags", []) != ["contact", "punch"]:
		push_error("Expected move #5 flags ['contact', 'punch'], got %s" % str(mv5.get("flags", [])))
		return false
	var mv45 := AssetDBRef.move(45, staged_res)
	if mv45.get("flags", null) != []:
		push_error("Expected move #45 empty flags array, got %s" % str(mv45.get("flags", null)))
		return false
	# VG priority: #1 has VG 20 machine [5] (overrides VG 18 [45]); #2 falls back to VG 18 [45]
	if AssetDBRef.tm_learnset(1, staged_res) != [5] or AssetDBRef.tm_learnset(2, staged_res) != [45]:
		push_error("TM learnset VG priority mismatch: #1=%s #2=%s" % [str(AssetDBRef.tm_learnset(1, staged_res)), str(AssetDBRef.tm_learnset(2, staged_res))])
		return false
	var mach := AssetDBRef.machines(staged_res)
	var by_item: Dictionary = mach.get("by_item", {})
	if by_item.size() != 2 or int(by_item.get("1288", 0)) != 5 or int(by_item.get("306", 0)) != 45 or by_item.has("305"):
		push_error("Expected VG 20 machines only (1288->5, 306->45), got %s" % str(mach))
		return false
	if AssetDBRef.machine_move_for_item(1288, staged_res) != 5:
		push_error("machine_move_for_item(1288) failed")
		return false
	var bfs := AssetDBRef.battle_forms(staged_res)
	if bfs.size() != 1 or not bfs.has("10026"):
		push_error("Expected exactly 1 non-Mega/Gmax/Primal battle form (10026), got %s" % str(bfs.keys()))
		return false
	var bf := AssetDBRef.battle_form(10026, staged_res)
	if int(bf.get("species_dex", 0)) != 2 or str(bf.get("form_identifier", "")) != "blade" or int(bf.get("weight_hg", 0)) != 530:
		push_error("Unexpected battle_form(10026) payload: %s" % str(bf))
		return false

	# Check all dropped evolution fields preserved
	var ev1 := AssetDBRef.evolutions(1, staged_res)
	if ev1.size() != 1:
		push_error("Expected 1 evolution rule for synthetic #1")
		return false
	var r1: Dictionary = ev1[0]
	if int(r1.get("location_id", 0)) != 10 or int(r1.get("minimum_beauty", 0)) != 170 or int(r1.get("minimum_affection", 0)) != 2 or r1.get("relative_physical_stats", 99) != null or int(r1.get("party_type_id", 0)) != 17 or not bool(r1.get("needs_overworld_rain", false)) or not bool(r1.get("turn_upside_down", false)) or not bool(r1.get("near_special_rock", false)) or int(r1.get("used_move_id", 0)) != 828 or int(r1.get("minimum_move_count", 0)) != 20 or int(r1.get("minimum_damage_taken", 0)) != 49:
		push_error("Dropped evolution fields missing/mismatch on synthetic #1: %s" % str(r1))
		return false
	var ev236 := AssetDBRef.evolutions(236, staged_res)
	var ev458 := AssetDBRef.evolutions(458, staged_res)
	if ev236.size() != 3 or int(ev236[0].get("relative_physical_stats", 99)) != 1 or int(ev236[1].get("relative_physical_stats", 99)) != -1 or int(ev236[2].get("relative_physical_stats", 99)) != 0:
		push_error("Expected #236 relative_physical_stats [1, -1, 0], got %s" % str(ev236))
		return false
	if ev458.size() != 1 or int(ev458[0].get("party_species_id", 0)) != 223:
		push_error("Expected #458 party_species_id=223, got %s" % str(ev458))
		return false

	var evo_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("data/evolutions.json")))
	var audit_ok := DataPackImporterRef.audit_evolutions(evo_doc)
	if int(audit_ok.get("level_up_rows_without_condition", -1)) != 0 or bool(audit_ok.get("tyrogue_rows_identical", true)):
		push_error("Synthetic v2 evolution audit failed: %s" % str(audit_ok))
		return false

	# Falsifier on audit_evolutions: stripped rules trigger both checks
	var broken_evos := {
		"133": [{"to_dex": 470, "trigger": "level-up", "minimum_level": 0, "held_item_id": 0, "minimum_happiness": 0, "known_move_id": 0, "known_move_type_id": 0, "gender_id": 0, "time_of_day": ""}],
		"236": [
			{"to_dex": 106, "trigger": "level-up", "minimum_level": 20},
			{"to_dex": 107, "trigger": "level-up", "minimum_level": 20},
			{"to_dex": 237, "trigger": "level-up", "minimum_level": 20},
		],
	}
	var audit_bad := DataPackImporterRef.audit_evolutions(broken_evos)
	if int(audit_bad.get("level_up_rows_without_condition", 0)) != 1 or not bool(audit_bad.get("tyrogue_rows_identical", false)):
		push_error("Falsifier failed: audit_evolutions did not catch stripped v1 rows: %s" % str(audit_bad))
		return false

	# Outdated v1 cache test: AssetDB reports outdated ("re-run the data import") and never crashes
	var old_v1 := TEST_ROOT + "/v2_mini/old_v1"
	var old_v1_abs := ProjectSettings.globalize_path(old_v1)
	DataPackImporterRef._write_json_file(old_v1_abs.path_join("manifest.json"), {
		"importerVersion": 1,
		"dataPack": {"speciesCount": 905, "moveCount": 778},
	})
	AssetDBRef.clear_memory_cache()
	if not AssetDBRef.is_data_outdated(old_v1) or AssetDBRef.is_data_ready(old_v1):
		push_error("Expected v1 cache to be marked outdated and not ready")
		return false
	var st := AssetDBRef.data_status(old_v1)
	if str(st.get("status", "")) != "outdated" or str(st.get("message", "")).find("re-run the data import") == -1:
		push_error("Unexpected outdated data_status: %s" % str(st))
		return false
	if not AssetDBRef.tm_learnset(1, old_v1).is_empty() or not AssetDBRef.battle_form(10026, old_v1).is_empty() or AssetDBRef.machine_move_for_item(1288, old_v1) != 0:
		push_error("Expected safe empty defaults when reading missing v2 files from old v1 cache")
		return false

	DataPackImporterRef._remove_dir_recursive(root)
	AssetDBRef.clear_memory_cache()
	return true


func _test_local_cache_v2_integrity() -> bool:
	var evo_path := ProjectSettings.globalize_path("user://rom_cache/data/evolutions.json")
	if not FileAccess.file_exists(evo_path):
		print("SKIPPED local user://rom_cache v2 audit — no local data cache present")
		return true
	var evo_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(evo_path))
	if not (evo_doc is Dictionary):
		push_error("Malformed user://rom_cache/data/evolutions.json")
		return false
	var audit := DataPackImporterRef.audit_evolutions(evo_doc as Dictionary)
	var no_cond := int(audit.get("level_up_rows_without_condition", -1))
	var tyr_ident := bool(audit.get("tyrogue_rows_identical", true))
	print("LOCAL_CACHE_AUDIT level_up_rows_without_condition=%d tyrogue_rows_identical=%s" % [no_cond, str(tyr_ident)])
	if no_cond != 0 or tyr_ident:
		push_error("Local data cache failed v2 evolution check: level_up_rows_without_condition=%d tyrogue_rows_identical=%s" % [no_cond, str(tyr_ident)])
		return false
	AssetDBRef.clear_memory_cache()
	var st := AssetDBRef.data_status("user://rom_cache")
	if not bool(st.get("ready", false)) or bool(st.get("outdated", true)):
		push_error("Local user://rom_cache is outdated or incomplete: %s" % str(st))
		return false
	var tyr_rules := AssetDBRef.evolutions(236, "user://rom_cache")
	var rels: Array = []
	for r in tyr_rules:
		var rv: Variant = r.get("relative_physical_stats", null)
		rels.append(int(rv) if rv != null else null)
	if tyr_rules.size() != 3 or not (rels.has(1) and rels.has(-1) and rels.has(0)):
		push_error("Expected #236 relative_physical_stats {1, -1, 0}, got %s" % str(rels))
		return false
	var man_rules := AssetDBRef.evolutions(458, "user://rom_cache")
	if man_rules.is_empty() or int(man_rules[0].get("party_species_id", 0)) != 223:
		push_error("Expected #458 party_species_id=223, got %s" % str(man_rules))
		return false
	var tm_count := 0
	for dex in range(1, 906):
		var sp := AssetDBRef.species(dex, "", "user://rom_cache")
		if int(sp.get("weight_hg", 0)) <= 0 or int(sp.get("height_dm", 0)) <= 0:
			push_error("Species #%d missing positive weight_hg/height_dm" % dex)
			return false
		if not AssetDBRef.tm_learnset(dex, "user://rom_cache").is_empty():
			tm_count += 1
	var mach := AssetDBRef.machines("user://rom_cache")
	var bfs := AssetDBRef.battle_forms("user://rom_cache")
	var mv_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("user://rom_cache/data/moves.json")))
	var flags_present := 0
	var contact_count := 0
	for mk in mv_doc.keys():
		var fl: Variant = (mv_doc[mk] as Dictionary).get("flags", null)
		if fl is Array:
			flags_present += 1
			if (fl as Array).has("contact"):
				contact_count += 1
	if flags_present != 778 or contact_count <= 0 or (mach.get("by_item", {}) as Dictionary).is_empty() or bfs.is_empty() or tm_count <= 0:
		push_error("Local v2 data metrics invalid: flags=%d/778 contact=%d machines=%d battle_forms=%d tm_species=%d" % [flags_present, contact_count, (mach.get("by_item", {}) as Dictionary).size(), bfs.size(), tm_count])
		return false
	print("LOCAL_CACHE_V2_OK tm_species=%d/905 machines_vg20=%d moves_flags=%d/778 contact=%d battle_forms=%d" % [tm_count, (mach.get("by_item", {}) as Dictionary).size(), flags_present, contact_count, bfs.size()])
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
	if not _test_data_pack_v2_synthetic_and_outdated():
		return false
	if not _test_local_cache_v2_integrity():
		return false
	if not _test_env_gated_real_imports():
		return false
	return true
