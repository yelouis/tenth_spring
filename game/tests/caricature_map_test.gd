extends Node

# game/tests/caricature_map_test.gd — Caricature Map Compiler & Cell Output Tests (Item 48a)
# Contract: docs/implementation_plan_dc_trial.md §2, §3, §9; docs/agent_execution_guide.md §4

const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const MapConstants := preload("res://world/map_constants.gd")

const FIXTURE_ROSTER := "res://tests/fixtures/neighbourhoods_fixture.json"
const FIXTURE_MAP := "res://tests/fixtures/caricature_fixture_map.json"

# Pinned SHA-256 across the four compiled 32x32 cell tile buffers of caricature_fixture_map.json
const PINNED_FIXTURE_SHA256 := "8c3c1fa344b7a42a1901461bf3a367e175b82f4ed186e19efd527356794cc66a"

func _cleanup() -> void:
	Neighbourhoods.set_config_path_for_tests("")

func _tile_bytes_in_cell(cell_tiles: PackedByteArray, tx: int, ty: int) -> Array[int]:
	var base := (ty * 32 + tx) * 3
	return [int(cell_tiles[base]), int(cell_tiles[base + 1]), int(cell_tiles[base + 2])]

func _has_error_prefix(errors: Array, prefix: String) -> bool:
	for e in errors:
		if str(e).begins_with(prefix):
			return true
	return false

func _hash_all_cells(compiled: Dictionary, area: Dictionary, cells: Array[Vector2i]) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for c in cells:
		var cr := CaricatureMap.cell_result(compiled, c, area)
		var t: PackedByteArray = cr["tiles"]
		ctx.update(t)
	return ctx.finish().hex_encode()

func run_test() -> bool:
	Neighbourhoods.set_config_path_for_tests(FIXTURE_ROSTER)
	var area := Neighbourhoods.area("hood:fixture-city:north-end")
	if area.is_empty():
		_cleanup()
		push_error("caricature_map_test: missing hood:fixture-city:north-end in fixture roster")
		return false

	var map_dict := CaricatureMap.load_map(FIXTURE_MAP)
	if map_dict.is_empty():
		_cleanup()
		push_error("caricature_map_test: failed to load %s" % FIXTURE_MAP)
		return false

	var seed_val: int = MapConstants.MAP_SEED
	var compiled := CaricatureMap.compile(area, map_dict, seed_val)
	if not bool(compiled.get("ok", false)):
		_cleanup()
		push_error("caricature_map_test: fixture compile failed: %s" % str(compiled.get("errors", [])))
		return false

	if compiled["origin"] != Vector2i(6, 6) or int(compiled["w"]) != 64 or int(compiled["h"]) != 64:
		_cleanup()
		push_error("caricature_map_test: unexpected origin/dimensions %s %dx%d" % [str(compiled["origin"]), int(compiled["w"]), int(compiled["h"])])
		return false

	# Four cells of north-end: top half y=0..31 -> cy=7; bottom half y=32..63 -> cy=6
	var cr_6_7 := CaricatureMap.cell_result(compiled, Vector2i(6, 7), area)
	var cr_7_7 := CaricatureMap.cell_result(compiled, Vector2i(7, 7), area)
	var cr_6_6 := CaricatureMap.cell_result(compiled, Vector2i(6, 6), area)
	var cr_7_6 := CaricatureMap.cell_result(compiled, Vector2i(7, 6), area)

	# -------------------------------------------------------------
	# 1. Every terrain character of §2.2 compiles to its class (and ledge variant)
	# Showcase strip sits in cell (6, 6) at map y=40 (cell ty = 8)
	# -------------------------------------------------------------
	var showcase_checks := [
		[6, TileSynth2.TILE_GRASS, -1],
		[7, TileSynth2.TILE_TALL_GRASS, 0],
		[8, TileSynth2.TILE_TREE, -1],
		[9, TileSynth2.TILE_WATER, 0],
		[10, TileSynth2.TILE_SAND, 0],
		[11, TileSynth2.TILE_MARSH, 0],
		[12, TileSynth2.TILE_PATH, -1],
		[13, TileSynth2.TILE_ROAD, -1],
		[14, TileSynth2.TILE_RAIL, 0],
		[15, TileSynth2.TILE_BRIDGE, 0],
		[16, TileSynth2.TILE_PLAZA, -1],
		[17, TileSynth2.TILE_FENCE, 0],
		[18, TileSynth2.TILE_FLOWERS, 0],
		[19, TileSynth2.TILE_GRAVE, 0],
		[20, TileSynth2.TILE_CROP, 0],
		[21, TileSynth2.TILE_RUBBLE, 0],
		[22, TileSynth2.TILE_LEDGE, 0],
		[24, TileSynth2.TILE_LEDGE, 1],
		[26, TileSynth2.TILE_LEDGE, 2],
	]
	for sc in showcase_checks:
		var mx: int = sc[0]
		var exp_cls: int = sc[1]
		var exp_var: int = sc[2]
		var tb := _tile_bytes_in_cell(cr_6_6["tiles"], mx, 40 - 32)
		if tb[0] != exp_cls:
			_cleanup()
			push_error("caricature_map_test: terrain at (%d, 40) expected class %d, got %d" % [mx, exp_cls, tb[0]])
			return false
		if exp_var >= 0 and tb[1] != exp_var:
			_cleanup()
			push_error("caricature_map_test: terrain at (%d, 40) expected variant %d, got %d" % [mx, exp_var, tb[1]])
			return false

	# -------------------------------------------------------------
	# 2. Exact 3-byte encodings & stamps entries (§3.3–§3.5)
	# -------------------------------------------------------------
	# (a) Landmark: parthenon (stamp 14) at [29, 10], w=7, h=5, base_rows=3, door=[3, 4]
	# [29, 10] is "." -> stays underlying GRASS in cell (6, 7) at tx=29, ty=10
	var parth_dot := _tile_bytes_in_cell(cr_6_7["tiles"], 29, 10)
	var exp_grass_v := floori(TileSynth2.u_rand(6 * 32 + 29, 7 * 32 + (31 - 10), seed_val, TileSynth2.SALT_GRASS_VARIANT) * 4.0)
	if parth_dot != [TileSynth2.TILE_GRASS, exp_grass_v, 0]:
		_cleanup()
		push_error("caricature_map_test: parthenon '.' tile expected %s, got %s" % [str([TileSynth2.TILE_GRASS, exp_grass_v, 0]), str(parth_dot)])
		return false
	# [30, 10] is "+" in overhang (ty=0 < 5-3) -> [TILE_STAMP, 14, STAMP_FLAG_OVERHANG]
	var parth_over := _tile_bytes_in_cell(cr_6_7["tiles"], 30, 10)
	if parth_over != [TileSynth2.TILE_STAMP, 14, TileSynth2.STAMP_FLAG_OVERHANG]:
		_cleanup()
		push_error("caricature_map_test: parthenon overhang '+' expected [21, 14, 2], got %s" % str(parth_over))
		return false
	# [29, 12] is "#" -> [TILE_STAMP, 14, STAMP_FLAG_SOLID]
	var parth_solid := _tile_bytes_in_cell(cr_6_7["tiles"], 29, 12)
	if parth_solid != [TileSynth2.TILE_STAMP, 14, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: parthenon solid '#' expected [21, 14, 1], got %s" % str(parth_solid))
		return false
	# [35, 12] (in cell (7, 7) at tx=3, ty=12) is "+" in base_rows (ty=2 >= 5-3) -> [TILE_STAMP, 14, 0]
	var parth_base_walk := _tile_bytes_in_cell(cr_7_7["tiles"], 35 - 32, 12)
	if parth_base_walk != [TileSynth2.TILE_STAMP, 14, 0]:
		_cleanup()
		push_error("caricature_map_test: parthenon base '+' expected [21, 14, 0], got %s" % str(parth_base_walk))
		return false
	# [32, 14] (in cell (7, 7) at tx=0, ty=14) is door -> [TILE_DOOR, 32, 14]
	var parth_door := _tile_bytes_in_cell(cr_7_7["tiles"], 32 - 32, 14)
	if parth_door != [TileSynth2.TILE_DOOR, 32, 14]:
		_cleanup()
		push_error("caricature_map_test: parthenon door expected [14, 32, 14], got %s" % str(parth_door))
		return false
	if cr_7_7["stats"]["landmark_ids_placed"] != ["fixture-city:town-hall"]:
		_cleanup()
		push_error("caricature_map_test: expected fixture-city:town-hall in cell (7,7) landmark_ids_placed, got %s" % str(cr_7_7["stats"]["landmark_ids_placed"]))
		return false

	# ▶ Cross-cell seam falsifier: parthenon [29, 10] (x=29..35) crosses seam between (6, 7) and (7, 7)
	var exp_parth_stamp := {
		"stamp_id": 14,
		"anchor_gx": 6 * 32 + 29,
		"anchor_gy": (-7 - 1) * 32 + 10,
		"w": 7,
		"h": 5,
	}
	if not (cr_6_7["stamps"] as Array).has(exp_parth_stamp):
		_cleanup()
		push_error("caricature_map_test: seam stamp missing from anchor cell (6, 7): %s" % str(cr_6_7["stamps"]))
		return false
	if not (cr_7_7["stamps"] as Array).has(exp_parth_stamp):
		_cleanup()
		push_error("caricature_map_test: SEAM FALSIFIER: stamp crossing seam into cell (7, 7) missing from (7, 7) stamps (got %s, expected %s)" % [str(cr_7_7["stamps"]), str(exp_parth_stamp)])
		return false

	# (b) Stand-in: fixture_pending_tower at [8, 10], size [5, 5], door_col 2
	var pend_roof_nw := _tile_bytes_in_cell(cr_6_7["tiles"], 8, 10)
	if pend_roof_nw != [TileSynth2.TILE_ROOF, 32, 6]:
		_cleanup()
		push_error("caricature_map_test: stand-in NW roof expected [12, 32, 6], got %s" % str(pend_roof_nw))
		return false
	var pend_roof_mid := _tile_bytes_in_cell(cr_6_7["tiles"], 9, 11)
	if pend_roof_mid != [TileSynth2.TILE_ROOF, 32, 15]:
		_cleanup()
		push_error("caricature_map_test: stand-in mid roof expected [12, 32, 15], got %s" % str(pend_roof_mid))
		return false
	var pend_wall_even := _tile_bytes_in_cell(cr_6_7["tiles"], 8, 13)
	if pend_wall_even != [TileSynth2.TILE_WALL, 32, 6]:
		_cleanup()
		push_error("caricature_map_test: stand-in even wall expected [13, 32, 6], got %s" % str(pend_wall_even))
		return false
	var pend_wall_odd := _tile_bytes_in_cell(cr_6_7["tiles"], 9, 13)
	if pend_wall_odd != [TileSynth2.TILE_WALL, 40, 14]:
		_cleanup()
		push_error("caricature_map_test: stand-in odd wall expected [13, 40, 14], got %s" % str(pend_wall_odd))
		return false
	var pend_door := _tile_bytes_in_cell(cr_6_7["tiles"], 10, 14)
	if pend_door != [TileSynth2.TILE_DOOR, 32, 0]:
		_cleanup()
		push_error("caricature_map_test: stand-in door expected [14, 32, 0], got %s" % str(pend_door))
		return false
	if int(compiled["art_pending"]) != 1:
		_cleanup()
		push_error("caricature_map_test: expected art_pending == 1, got %d" % int(compiled["art_pending"]))
		return false
	var pend_sign := _tile_bytes_in_cell(cr_6_7["tiles"], 7, 15)
	if pend_sign != [TileSynth2.TILE_SIGN, 0, 0] or cr_6_7["signs"] != PackedStringArray(["Fixture Pending Tower"]):
		_cleanup()
		push_error("caricature_map_test: stand-in SW sign mismatch: bytes=%s signs=%s" % [str(pend_sign), str(cr_6_7["signs"])])
		return false

	# (c) Standing house_s at [42, 10] (in cell (7, 7) at tx=10, ty=10)
	var hs_gx := 6 * 32 + 42
	var hs_gy := 7 * 32 + (31 - 10)
	var hs_dcol := 1 if TileSynth2.u_rand(hs_gx, hs_gy, seed_val, TileSynth2.SALT_DOOR_ROOF) < 0.5 else 2
	var hs_col5 := clampi(floori(TileSynth2.u_rand(hs_gx, hs_gy, seed_val, TileSynth2.SALT_RUIN_COLOURWAY) * 5.0), 0, 4)
	var hs_sid := (71 if hs_dcol == 1 else 76) + hs_col5
	var hs_body := _tile_bytes_in_cell(cr_7_7["tiles"], 42 - 32, 10)
	var hs_door := _tile_bytes_in_cell(cr_7_7["tiles"], (42 + hs_dcol) - 32, 13)
	if hs_body != [TileSynth2.TILE_STAMP, hs_sid, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: standing house_s body expected %s, got %s" % [str([TileSynth2.TILE_STAMP, hs_sid, 1]), str(hs_body)])
		return false
	if hs_door != [TileSynth2.TILE_DOOR, hs_col5, hs_sid]:
		_cleanup()
		push_error("caricature_map_test: standing house_s door expected %s, got %s" % [str([TileSynth2.TILE_DOOR, hs_col5, hs_sid]), str(hs_door)])
		return false
	var exp_hs_stamp := {"stamp_id": hs_sid, "anchor_gx": hs_gx, "anchor_gy": -246, "w": 4, "h": 4}
	if not (cr_7_7["stamps"] as Array).has(exp_hs_stamp):
		_cleanup()
		push_error("caricature_map_test: standing house_s stamp entry missing from (7, 7)")
		return false

	# (d) Ruined house_s at [48, 10] (in cell (7, 7) at tx=16, ty=10; ruin_level="near" -> state_b < 0.50)
	var hr_gx := 6 * 32 + 48
	var hr_gy := 7 * 32 + (31 - 10)
	var hr_dcol := 1 if TileSynth2.u_rand(hr_gx, hr_gy, seed_val, TileSynth2.SALT_DOOR_ROOF) < 0.5 else 2
	var hr_cdraw := TileSynth2.u_rand(hr_gx, hr_gy, seed_val, TileSynth2.SALT_RUIN_COLOURWAY)
	var hr_col := 0 if hr_cdraw < 0.40 else (1 if hr_cdraw < 0.60 else (2 if hr_cdraw < 0.80 else 3))
	var hr_is_b := TileSynth2.u_rand(hr_gx, hr_gy, seed_val, TileSynth2.SALT_RUIN_STATE) < 0.50
	var hr_sid := ((23 if hr_is_b else 15) if hr_dcol == 1 else (27 if hr_is_b else 19)) + hr_col
	var hr_body := _tile_bytes_in_cell(cr_7_7["tiles"], 48 - 32, 10)
	var hr_door := _tile_bytes_in_cell(cr_7_7["tiles"], (48 + hr_dcol) - 32, 13)
	if hr_body != [TileSynth2.TILE_STAMP, hr_sid, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: ruined house_s body expected %s, got %s" % [str([TileSynth2.TILE_STAMP, hr_sid, 1]), str(hr_body)])
		return false
	if hr_door != [TileSynth2.TILE_DOOR, 16 + hr_col, hr_sid]:
		_cleanup()
		push_error("caricature_map_test: ruined house_s door expected %s, got %s" % [str([TileSynth2.TILE_DOOR, 16 + hr_col, hr_sid]), str(hr_door)])
		return false

	# (e) Gone house_m at [54, 10] -> shell stamp 41, no door
	var hg_body := _tile_bytes_in_cell(cr_7_7["tiles"], 54 - 32, 10)
	var hg_nodoor := _tile_bytes_in_cell(cr_7_7["tiles"], (54 + 2) - 32, 13)
	if hg_body != [TileSynth2.TILE_STAMP, 41, TileSynth2.STAMP_FLAG_SOLID] or hg_nodoor != [TileSynth2.TILE_STAMP, 41, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: gone house_m shell expected [21, 41, 1] everywhere, got %s / %s" % [str(hg_body), str(hg_nodoor)])
		return false

	# (f) Ruined block_8x7 at [49, 18] -> stamp 42 or 60, two doors at cols 3 and 4
	var blk_gx := 6 * 32 + 49
	var blk_gy := 7 * 32 + (31 - 18)
	var blk_des_a := TileSynth2.u_rand(blk_gx, blk_gy, seed_val, TileSynth2.SALT_BLOCK_DESIGN) < 0.50
	var blk_sid := 42 if blk_des_a else 60
	var blk_cdraw := TileSynth2.u_rand(blk_gx, blk_gy, seed_val, TileSynth2.SALT_RUIN_COLOURWAY)
	var blk_col := 0 if blk_cdraw < 0.40 else (1 if blk_cdraw < 0.60 else (2 if blk_cdraw < 0.80 else 3))
	var blk_body := _tile_bytes_in_cell(cr_7_7["tiles"], 49 - 32, 18)
	var blk_d1 := _tile_bytes_in_cell(cr_7_7["tiles"], (49 + 3) - 32, 24)
	var blk_d2 := _tile_bytes_in_cell(cr_7_7["tiles"], (49 + 4) - 32, 24)
	if blk_body != [TileSynth2.TILE_STAMP, blk_sid, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: ruined block_8x7 body mismatch: %s" % str(blk_body))
		return false
	if blk_d1 != [TileSynth2.TILE_DOOR, 16 + blk_col, blk_sid] or blk_d2 != [TileSynth2.TILE_DOOR, 16 + blk_col, blk_sid]:
		_cleanup()
		push_error("caricature_map_test: ruined block_8x7 doors mismatch: %s / %s" % [str(blk_d1), str(blk_d2)])
		return false

	# (g) Decals: decal_boulder (57, solid) at [22, 18]; decal_rubble (43) + decal_weeds (51) overlapping at [24, 18]
	var dec_solid := _tile_bytes_in_cell(cr_6_7["tiles"], 22, 18)
	var dec_walk := _tile_bytes_in_cell(cr_6_7["tiles"], 24, 18)
	if dec_solid != [TileSynth2.TILE_STAMP, 57, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: decal_boulder expected [21, 57, 1], got %s" % str(dec_solid))
		return false
	if dec_walk != [TileSynth2.TILE_STAMP, 51, 0]:
		_cleanup()
		push_error("caricature_map_test: overlapping walkable decal expected [21, 51, 0], got %s" % str(dec_walk))
		return false

	# -------------------------------------------------------------
	# 3. Sign variant indexes its own cell's list (§3.7)
	# -------------------------------------------------------------
	# Cell (6, 6): lamp [30, 52] -> index 0 ("Waypost lamp"); [13, 43] -> index 1 ("Fixture Pond")
	var lamp_bytes := _tile_bytes_in_cell(cr_6_6["tiles"], 30, 52 - 32)
	var pond_sign_bytes := _tile_bytes_in_cell(cr_6_6["tiles"], 13, 43 - 32)
	if lamp_bytes != [TileSynth2.TILE_SIGN, 0, 0] or pond_sign_bytes != [TileSynth2.TILE_SIGN, 1, 0]:
		_cleanup()
		push_error("caricature_map_test: cell (6,6) sign bytes mismatch: lamp=%s pond=%s" % [str(lamp_bytes), str(pond_sign_bytes)])
		return false
	if cr_6_6["signs"] != PackedStringArray(["Waypost lamp", "Fixture Pond"]):
		_cleanup()
		push_error("caricature_map_test: cell (6,6) signs list mismatch: %s" % str(cr_6_6["signs"]))
		return false
	# Cell (7, 6): [35, 43] -> index 0 ("East Trail")
	var east_sign_bytes := _tile_bytes_in_cell(cr_7_6["tiles"], 35 - 32, 43 - 32)
	if east_sign_bytes != [TileSynth2.TILE_SIGN, 0, 0] or cr_7_6["signs"] != PackedStringArray(["East Trail"]):
		_cleanup()
		push_error("caricature_map_test: cell (7,6) sign mismatch: bytes=%s signs=%s" % [str(east_sign_bytes), str(cr_7_6["signs"])])
		return false

	# -------------------------------------------------------------
	# 4. ▶ Falsifiers M1–M8: each broken rule in a scratch copy reports its own id
	# -------------------------------------------------------------
	# M1: bad character in rows
	var m1 := map_dict.duplicate(true)
	var r10 := str(m1["rows"][10])
	m1["rows"][10] = "?" + r10.substr(1)
	var res_m1 := CaricatureMap.compile(area, m1, seed_val)
	if bool(res_m1["ok"]) or not _has_error_prefix(res_m1["errors"], "M1:"):
		_cleanup()
		push_error("caricature_map_test: M1 falsifier did not report M1: %s" % str(res_m1["errors"]))
		return false

	# M2: walkable grass on border (x=1, y=10)
	var m2 := map_dict.duplicate(true)
	var r_m2 := str(m2["rows"][10])
	m2["rows"][10] = r_m2.substr(0, 1) + "." + r_m2.substr(2)
	var res_m2 := CaricatureMap.compile(area, m2, seed_val)
	if bool(res_m2["ok"]) or not _has_error_prefix(res_m2["errors"], "M2:"):
		_cleanup()
		push_error("caricature_map_test: M2 falsifier did not report M2: %s" % str(res_m2["errors"]))
		return false

	# M3: object touching border (at=[2, 10])
	var m3 := map_dict.duplicate(true)
	m3["objects"].append({"kind": "house_s", "at": [2, 10], "fate": "standing"})
	var res_m3 := CaricatureMap.compile(area, m3, seed_val)
	if bool(res_m3["ok"]) or not _has_error_prefix(res_m3["errors"], "M3:"):
		_cleanup()
		push_error("caricature_map_test: M3 falsifier did not report M3: %s" % str(res_m3["errors"]))
		return false

	# M4: overlapping non-decal objects
	var m4 := map_dict.duplicate(true)
	m4["objects"].append({"kind": "house_s", "at": [43, 11], "fate": "standing"})
	var res_m4 := CaricatureMap.compile(area, m4, seed_val)
	if bool(res_m4["ok"]) or not _has_error_prefix(res_m4["errors"], "M4:"):
		_cleanup()
		push_error("caricature_map_test: M4 falsifier did not report M4: %s" % str(res_m4["errors"]))
		return false

	# M5: tile south of lamp is water '~'
	var m5 := map_dict.duplicate(true)
	var r_m5 := str(m5["rows"][53])
	m5["rows"][53] = r_m5.substr(0, 30) + "~" + r_m5.substr(31)
	var res_m5 := CaricatureMap.compile(area, m5, seed_val)
	if bool(res_m5["ok"]) or not _has_error_prefix(res_m5["errors"], "M5:"):
		_cleanup()
		push_error("caricature_map_test: M5 falsifier did not report M5: %s" % str(res_m5["errors"]))
		return false

	# M6: sign placed on non-walkable water tile (8, 43)
	var m6 := map_dict.duplicate(true)
	m6["signs"].append({"at": [8, 43], "text": "Sunken Sign"})
	var res_m6 := CaricatureMap.compile(area, m6, seed_val)
	if bool(res_m6["ok"]) or not _has_error_prefix(res_m6["errors"], "M6:"):
		_cleanup()
		push_error("caricature_map_test: M6 falsifier did not report M6: %s" % str(res_m6["errors"]))
		return false

	# M7: pending id that is already in STAMP_TABLE ("obelisk")
	var m7 := map_dict.duplicate(true)
	m7["objects"].append({"pending": "obelisk", "size": [6, 6], "door_col": 2, "name": "Already Exists", "at": [6, 30]})
	var res_m7 := CaricatureMap.compile(area, m7, seed_val)
	if bool(res_m7["ok"]) or not _has_error_prefix(res_m7["errors"], "M7:"):
		_cleanup()
		push_error("caricature_map_test: M7 falsifier did not report M7: %s" % str(res_m7["errors"]))
		return false

	# M8: tree directly south of parthenon door at (32, 15)
	var m8 := map_dict.duplicate(true)
	var r_m8 := str(m8["rows"][15])
	m8["rows"][15] = r_m8.substr(0, 32) + "T" + r_m8.substr(33)
	var res_m8 := CaricatureMap.compile(area, m8, seed_val)
	if bool(res_m8["ok"]) or not _has_error_prefix(res_m8["errors"], "M8:"):
		_cleanup()
		push_error("caricature_map_test: M8 falsifier did not report M8: %s" % str(res_m8["errors"]))
		return false

	# -------------------------------------------------------------
	# 5. Same input -> identical bytes, and pinned SHA-256 (§3.9, §9)
	# -------------------------------------------------------------
	var cells_ordered: Array[Vector2i] = [
		Vector2i(6, 6),
		Vector2i(7, 6),
		Vector2i(6, 7),
		Vector2i(7, 7),
	]
	var compiled_2 := CaricatureMap.compile(area, map_dict, seed_val)
	var sha_1 := _hash_all_cells(compiled, area, cells_ordered)
	var sha_2 := _hash_all_cells(compiled_2, area, cells_ordered)
	if sha_1 != sha_2:
		_cleanup()
		push_error("caricature_map_test: non-deterministic output: %s vs %s" % [sha_1, sha_2])
		return false

	print("[CARICATURE MAP FIXTURE SHA256] %s" % sha_1)
	if sha_1 != PINNED_FIXTURE_SHA256:
		_cleanup()
		push_error("caricature_map_test: fixture SHA-256 %s != pinned %s" % [sha_1, PINNED_FIXTURE_SHA256])
		return false

	# Verify block fate="gone" becomes ruined (never shell) per §3.5 step 1
	var m_blk_gone := map_dict.duplicate(true)
	for o in m_blk_gone["objects"]:
		if o.get("kind", "") == "block_8x7":
			o["fate"] = "gone"
	var comp_blk_gone := CaricatureMap.compile(area, m_blk_gone, seed_val)
	if not bool(comp_blk_gone["ok"]):
		_cleanup()
		push_error("caricature_map_test: block fate=gone failed compile: %s" % str(comp_blk_gone["errors"]))
		return false
	var cr_blk_gone := CaricatureMap.cell_result(comp_blk_gone, Vector2i(7, 7), area)
	if _tile_bytes_in_cell(cr_blk_gone["tiles"], 49 - 32, 18) != [TileSynth2.TILE_STAMP, blk_sid, TileSynth2.STAMP_FLAG_SOLID]:
		_cleanup()
		push_error("caricature_map_test: block fate=gone did not compile as ruined block")
		return false

	_cleanup()
	return true
