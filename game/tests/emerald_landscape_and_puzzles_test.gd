extends Node

# game/tests/emerald_landscape_and_puzzles_test.gd — Stage 1 Falsifiers & Verification (Item 55)
# Verifies terrain classes 23..28, CaricatureCheck dual-graph soft-lock & reachability rules,
# interior metadata on kind buildings, GbaRom / Gen3Tiles unit logic, Rule B compliance,
# and runtime Emerald cache import/fallback.

const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const RomImporter := preload("res://rom/importer.gd")
const AssetDB := preload("res://rom/asset_db.gd")

const FIXTURE_ROSTER := "res://tests/fixtures/neighbourhoods_fixture.json"
const ORIGINAL_JSON := "res://assets/tiles/original_v1.json"
const ORIGINAL_PNG := "res://assets/tiles/original_v1.png"
const EMERALD_MAP_JSON := "res://config/emerald_tile_map.json"
const CACHE_EMPTY := "user://test/emerald_empty"
const CACHE_IMPORT := "user://test/emerald_cache"

func _rm_tree(path: String) -> void:
	var g := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(g):
		return
	var da := DirAccess.open(g)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var sub := g.path_join(name)
			if da.current_is_dir():
				_rm_tree(sub)
			else:
				DirAccess.remove_absolute(sub)
		name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(g)

func _cleanup() -> void:
	Neighbourhoods.set_config_path_for_tests("")
	AssetDB.clear_tile_atlas_cache()
	_rm_tree(CACHE_EMPTY)
	_rm_tree(CACHE_IMPORT)

func _blank_32_grid(fill_char: String) -> Array:
	var grid := []
	for y in range(32):
		var row := []
		for x in range(32):
			if x < 3 or x >= 29 or y < 3 or y >= 29:
				row.append("T")
			else:
				row.append(fill_char)
		grid.append(row)
	return grid

func _make_camp_map(grid: Array, lamp: Array, objects: Array = []) -> Dictionary:
	var rows: Array[String] = []
	for r in grid:
		rows.append("".join(r))
	return {
		"schema": 1,
		"id": "camp:fixture-city",
		"rows": rows,
		"objects": objects,
		"lamp": lamp,
		"signs": [],
	}

func _fail(msg: String) -> bool:
	push_error("emerald_landscape_and_puzzles_test: " + msg)
	_cleanup()
	return false

func run_test() -> bool:
	_cleanup()
	Neighbourhoods.set_config_path_for_tests(FIXTURE_ROSTER)
	var camp_area := Neighbourhoods.area("camp:fixture-city")
	if camp_area.is_empty():
		return _fail("missing camp:fixture-city fixture area")

	# -------------------------------------------------------------
	# A. ▶ Ledge + Cut soft-lock falsifier:
	# Drop via 'v' ledge into pocket whose ONLY exit is 'k' (Cut tree).
	# Full graph can exit; Base graph cannot -> base_trapped > 0 and P2 MUST fail.
	# -------------------------------------------------------------
	var g_soft := _blank_32_grid(".")
	for y in range(9, 15):
		for x in range(9, 15):
			if x == 9 or x == 14 or y == 9 or y == 14:
				g_soft[y][x] = "^"
			else:
				g_soft[y][x] = "."
	g_soft[9][11] = "v"
	g_soft[14][11] = "k"
	var c_soft := CaricatureMap.compile(camp_area, _make_camp_map(g_soft, [16, 25]))
	if not bool(c_soft.get("ok", false)):
		return _fail("A compile failed (missing new terrain tokens '^'/'k'?): %s" % str(c_soft.get("errors", [])))
	var m_soft := CaricatureCheck.measure(c_soft, camp_area)
	if bool(m_soft.get("ok", true)) or not (m_soft.get("failed_rules", []) as Array).has("P2"):
		return _fail("A expected P2 failure for ledge+Cut soft-lock, got ok=%s rules=%s" % [str(m_soft.get("ok")), str(m_soft.get("failed_rules"))])
	if int(m_soft.get("base_trapped", 0)) <= 0:
		return _fail("A expected base_trapped > 0, got %d" % int(m_soft.get("base_trapped", -1)))
	if int(m_soft.get("trapped", -1)) != 0:
		return _fail("A expected full-graph trapped == 0 (since Cut clears exit), got %d" % int(m_soft.get("trapped", -1)))

	# -------------------------------------------------------------
	# B. ▶ Cliff-walled item ball falsifier: unreached > 0 and fails P1
	# -------------------------------------------------------------
	var g_item := _blank_32_grid(".")
	for y in range(9, 14):
		for x in range(9, 14):
			if x == 9 or x == 13 or y == 9 or y == 13:
				g_item[y][x] = "^"
			else:
				g_item[y][x] = "."
	g_item[11][11] = "!"
	var c_item := CaricatureMap.compile(camp_area, _make_camp_map(g_item, [16, 25]))
	if not bool(c_item.get("ok", false)):
		return _fail("B compile failed (missing '^'/'!'?): %s" % str(c_item.get("errors", [])))
	var m_item := CaricatureCheck.measure(c_item, camp_area)
	if bool(m_item.get("ok", true)) or not (m_item.get("failed_rules", []) as Array).has("P1") or int(m_item.get("unreached", 0)) <= 0:
		return _fail("B expected P1 failure with unreached > 0, got %s" % str(m_item))

	# -------------------------------------------------------------
	# C. Valid Cut + Rock Smash + Strength cliff pockets & ledge-stair loop
	# -------------------------------------------------------------
	var g_ok := _blank_32_grid("T")
	for y in range(8, 27):
		for x in range(8, 26):
			g_ok[y][x] = "."
	# Three 3x3 cliff pockets at top, each gated by k / r / o and holding '!'
	for px_i in range(3):
		var bx := 9 + px_i * 5
		var gate: String = str(["k", "r", "o"][px_i])
		for y in range(9, 13):
			for x in range(bx, bx + 4):
				if x == bx or x == bx + 3 or y == 9 or y == 12:
					g_ok[y][x] = "^"
		g_ok[12][bx + 1] = gate
		g_ok[10][bx + 1] = "!"
	# Elevated cliff plateau with E-W / N-S stairs 's'/'S' and one-way ledge 'v' back down
	for y in range(15, 20):
		for x in range(10, 21):
			if y == 15 or y == 19 or x == 10 or x == 20:
				g_ok[y][x] = "^"
	g_ok[17][10] = "S" # E-W stair entry
	g_ok[15][15] = "s" # N-S stair exit/entry
	g_ok[19][14] = "v" # One-way south ledge return (both base & full graph can exit via 's'/'S')

	var c_ok := CaricatureMap.compile(camp_area, _make_camp_map(g_ok, [16, 25]))
	if not bool(c_ok.get("ok", false)):
		return _fail("C compile failed: %s" % str(c_ok.get("errors", [])))
	var m_ok := CaricatureCheck.measure(c_ok, camp_area)
	if not bool(m_ok.get("ok", false)):
		return _fail("C expected valid puzzle map to pass P1..P10, failed: %s metrics=%s" % [str(m_ok.get("failed_rules")), str(m_ok)])
	if int(m_ok.get("unreached", -1)) != 0 or int(m_ok.get("trapped", -1)) != 0 or int(m_ok.get("base_trapped", -1)) != 0:
		return _fail("C expected 0 unreached/trapped/base_trapped, got %s" % str(m_ok))
	if int(m_ok.get("item_balls", 0)) != 3:
		return _fail("C expected item_balls == 3, got %s" % str(m_ok.get("item_balls", -1)))

	# -------------------------------------------------------------
	# D. kind-based ordinary building retains interior & name on compiled door
	# -------------------------------------------------------------
	var g_kind := _blank_32_grid(".")
	var kind_objs := [{
		"form": "kind",
		"kind": "block_8x7",
		"fate": "standing",
		"at": [10, 10],
		"interior": "dc:woodley-vet",
		"name": "Woodley Vet Clinic",
	}]
	var c_kind := CaricatureMap.compile(camp_area, _make_camp_map(g_kind, [16, 25], kind_objs))
	if not bool(c_kind.get("ok", false)):
		return _fail("D compile failed: %s" % str(c_kind.get("errors", [])))
	var doors_d: Array = c_kind.get("doors", [])
	if doors_d.is_empty() or str(doors_d[0].get("interior", "")) != "dc:woodley-vet" or str(doors_d[0].get("name", "")) != "Woodley Vet Clinic":
		return _fail("D expected door interior='dc:woodley-vet' & name='Woodley Vet Clinic', got %s" % str(doors_d))

	# -------------------------------------------------------------
	# E. Synthetic GBA / Gen3 / Rule B unit tests (no ROM needed)
	# -------------------------------------------------------------
	var gba_script := load("res://rom/gba_rom.gd")
	var gen3_script := load("res://rom/gen3_tiles.gd")
	if gba_script == null or gen3_script == null:
		return _fail("E missing res://rom/gba_rom.gd or res://rom/gen3_tiles.gd")

	# E1: LZ77 type 0x10 decompression: "ABCD" + back-ref copy of 4 bytes at disp=4 => "ABCDABCD" (len=8)
	var lz_bytes := PackedByteArray([0x10, 0x08, 0x00, 0x00, 0x08, 65, 66, 67, 68, 0x10, 0x03])
	var dec_res: Dictionary = gba_script.call("decompress_lz77_bytes", lz_bytes)
	if not bool(dec_res.get("ok", false)) or (dec_res["data"] as PackedByteArray).get_string_from_ascii() != "ABCDABCD":
		return _fail("E1 LZ77 synthetic decode failed: %s" % str(dec_res))
	var bad_lz: Dictionary = gba_script.call("decompress_lz77_bytes", PackedByteArray([0x11, 0x04, 0x00, 0x00, 0x00]))
	if bool(bad_lz.get("ok", true)):
		return _fail("E1 expected non-0x10 header to fail")

	# E2: BGR555 -> RGBA & 4bpp metatile flip/compositing & 2x scaling
	var c_bgr: Color = gen3_script.call("bgr555_to_color", 0x7FE0) # G=31, B=31 -> teal
	if c_bgr.r8 != 0 or c_bgr.g8 != 255 or c_bgr.b8 != 255:
		return _fail("E2 BGR555 conversion mismatch: %s" % str(c_bgr))

	# E3: Rule B check on res://config/emerald_tile_map.json
	if not FileAccess.file_exists(EMERALD_MAP_JSON):
		return _fail("E3 missing " + EMERALD_MAP_JSON)
	var emap_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(EMERALD_MAP_JSON))
	if not (emap_v is Dictionary):
		return _fail("E3 failed to parse " + EMERALD_MAP_JSON)
	var emap: Dictionary = emap_v
	var tmap: Dictionary = emap.get("tile_map", {})
	for forbidden_cls in ["12", "13", "14"]:
		if tmap.has(forbidden_cls):
			return _fail("E3 Rule B violated: building class %s in tile_map" % forbidden_cls)
	if not (emap.get("buildings", {}) as Dictionary).is_empty() or not (emap.get("compositions", {}) as Dictionary).is_empty():
		return _fail("E3 Rule B violated: buildings and compositions must be empty {}")

	# E4: original_v1.json has 104 tile rows and fog_rows ending at row 107 (512x3456)
	var orig_doc_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_JSON))
	if not (orig_doc_v is Dictionary):
		return _fail("E4 failed to parse original_v1.json")
	var orig_doc: Dictionary = orig_doc_v
	if (orig_doc.get("rows", []) as Array).size() != 104 or int((orig_doc.get("fog_rows", {}) as Dictionary).get("d25", 0)) != 107:
		return _fail("E4 expected original_v1.json 104 rows & fog d25==107")

	# -------------------------------------------------------------
	# F. Cache fallback + ROM-gated import verification
	# -------------------------------------------------------------
	if AssetDB.tile_atlas(CACHE_EMPTY) != null:
		return _fail("F expected AssetDB.tile_atlas(empty) == null")

	var rom_env := OS.get_environment("TENTH_SPRING_ROM_GBA").strip_edges()
	if rom_env == "":
		print("[SKIP] emerald_landscape_and_puzzles_test ROM-gated check (TENTH_SPRING_ROM_GBA unset)")
		_cleanup()
		return true

	var imp_res: Dictionary = RomImporter.import_gba_rom(rom_env, CACHE_IMPORT)
	if not bool(imp_res.get("ok", false)):
		return _fail("F import_gba_rom failed: %s" % str(imp_res))

	var atlas_v: Variant = AssetDB.tile_atlas(CACHE_IMPORT)
	if not (atlas_v is Dictionary):
		return _fail("F AssetDB.tile_atlas returned null after valid import")
	var atlas: Dictionary = atlas_v
	var tex: Texture2D = atlas.get("texture", null)
	if tex == null or tex.get_width() != 512 or tex.get_height() != 3456:
		return _fail("F expected 512x3456 Emerald atlas, got %s" % str(tex))

	var em_img: Image = tex.get_image()
	var orig_img := Image.new()
	orig_img.load_png_from_buffer(FileAccess.get_file_as_bytes(ORIGINAL_PNG))
	# Grass row 1 col 0 must differ from original_v1.png
	var grass_diff := 0
	for py in range(32):
		for px in range(32):
			if em_img.get_pixel(px, 32 + py) != orig_img.get_pixel(px, 32 + py):
				grass_diff += 1
	if grass_diff == 0:
		return _fail("F expected Emerald grass tile (row 1, col 0) to differ from original_v1.png")

	# Building Roof (class 12), Wall (class 13), Door (class 14) must remain byte/pixel-identical to original_v1.png
	var orig_rows: Array = (orig_doc_v as Dictionary).get("rows", [])
	var clean_v0_row: Dictionary = {}
	var clean_v1_row: Dictionary = {}
	for r_entry_v in orig_rows:
		var r_entry: Dictionary = r_entry_v
		var r_cls := int(r_entry.get("class", -1))
		var r_var := int(r_entry.get("variant", 0))
		var r_num := int(r_entry.get("row", 0))
		if r_cls in [7, 8, 11]:
			if r_var == 0:
				clean_v0_row[r_cls] = r_num
			elif r_var == 1:
				clean_v1_row[r_cls] = r_num
		if r_cls in [12, 13, 14]:
			var row_y := r_num * 32
			for py in range(32):
				for px in range(512):
					if em_img.get_pixel(px, row_y + py) != orig_img.get_pixel(px, row_y + py):
						return _fail("F Rule B pixel diff on class %d row %d at (%d,%d)" % [r_cls, int(r_entry["row"]), px, py])

	# Decision 71 (Item 62b): worn path/road/plaza (classes 7, 8, 11 at variant 1) must draw identical to variant 0
	for clean_cls in [7, 8, 11]:
		if not clean_v0_row.has(clean_cls) or not clean_v1_row.has(clean_cls):
			return _fail("F missing clean/worn row entry for class %d" % clean_cls)
		var y0 := int(clean_v0_row[clean_cls]) * 32
		var y1 := int(clean_v1_row[clean_cls]) * 32
		for py in range(32):
			for px in range(512):
				if em_img.get_pixel(px, y1 + py) != em_img.get_pixel(px, y0 + py):
					return _fail("F clean-worn-paving violation: class %d variant=1 row %d differs from variant=0 row %d at (%d,%d)" % [clean_cls, int(clean_v1_row[clean_cls]), int(clean_v0_row[clean_cls]), px, py])

	# G. Item 62: OutdoorFixtures and PeopleSprites ROM + procedural fallback resolution
	var OutFix := load("res://world/caricature/outdoor_fixtures.gd")
	var PplSprites := load("res://world/people_sprites.gd")
	var fb_fountain: Dictionary = OutFix.resolve_texture("em_fountain", true, CACHE_EMPTY)
	var rom_fountain: Dictionary = OutFix.resolve_texture("em_fountain", false, CACHE_IMPORT)
	if fb_fountain.get("texture", null) == null or bool(fb_fountain.get("is_rom", true)):
		return _fail("G expected OutdoorFixtures fallback for em_fountain")
	if rom_fountain.get("texture", null) == null or not bool(rom_fountain.get("is_rom", false)):
		return _fail("G expected OutdoorFixtures ROM atlas for em_fountain after GBA import")
	var fb_healer: Texture2D = PplSprites.resolve_texture("healer", "S", "healer", true, CACHE_EMPTY)
	var rom_healer: Texture2D = PplSprites.resolve_texture("healer", "S", "healer", false, CACHE_IMPORT)
	if fb_healer == null or rom_healer == null:
		return _fail("G expected non-null PeopleSprites fallback and ROM textures")
	var fh_img := fb_healer.get_image()
	var rh_img := rom_healer.get_image()
	if fh_img == null or rh_img == null or fh_img.get_data() == rh_img.get_data():
		return _fail("G expected Emerald ROM healer sprite to differ from procedural fallback")

	# Item 62b (Decision 71): bench (2x1 = 64x32) and lock gate (2x3 = 64x96) stand-ins
	var bench_res: Dictionary = OutFix.resolve_texture("standin_bench", false, CACHE_IMPORT)
	var gate_res: Dictionary = OutFix.resolve_texture("standin_lock_gate", false, CACHE_IMPORT)
	var btex: Texture2D = bench_res.get("texture", null)
	var gtex: Texture2D = gate_res.get("texture", null)
	if btex == null or btex.get_width() != 64 or btex.get_height() != 32:
		return _fail("G expected 64x32 texture for 2x1 standin_bench, got %s" % str(btex))
	if gtex == null or gtex.get_width() != 64 or gtex.get_height() != 96:
		return _fail("G expected 64x96 texture for 2x3 standin_lock_gate, got %s" % str(gtex))

	print("[EMERALD HYBRID OK] base_trapped falsifier, cliff/puzzle checks, synthetic GBA, outdoor/people ROM + fallback verified")
	_cleanup()
	return true
