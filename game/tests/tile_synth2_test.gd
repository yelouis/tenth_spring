extends Node

# tile_synth2_test.gd — Synthesis Part 1 Verification Test
# Contract: docs/implementation_plan_world_generation_slice2.md §3, §4, §8

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")

const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const TEST_DB_PATH: String = "user://test/map_data/tile_synth2_test.db"

# Final Golden hash (§8 a, §10.7, §14.5.3) — proven identical on Linux and macOS CI
const GOLDEN_HASH: String = "c626aaf164311a0fcfa9c3c0366844c75b5ce560de4eb62065bea43e92aa7b76"

func run_test() -> bool:
	_cleanup()

	var conv := RegionConverter.new()
	var res := conv.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res.get("ok", false):
		push_error("Map convert failed: %s" % res.get("error", "unknown"))
		_cleanup()
		return false

	var store := MapStore.new(TEST_DB_PATH)
	if not store.open_store(false):
		push_error("Failed to open store: %s" % store.last_error)
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (c) Falsifier — north-first orientation (§8 c)
	# Water polygon covering north half of a cell (v in [8, 16])
	# Rows 0-15 must be WATER, rows 16-31 must NOT be WATER.
	# -------------------------------------------------------------
	var north_water_ring := PackedVector2Array([
		Vector2(0, 8), Vector2(16, 8), Vector2(16, 16), Vector2(0, 16)
	])
	var north_area := {
		Vector2i.ZERO: {
			"polys": [{"kind": "water", "geom_rings": MapStore.pack_rings([north_water_ring])}],
			"lines": [],
			"places": [],
			"covered": true,
			"sea": 0
		}
	}
	var north_res := TileSynth2.synthesize_cell(0, 0, north_area, 0)
	var north_tiles: PackedByteArray = north_res["tiles"]
	if north_tiles.size() != TileSynth2.OUTPUT_BUFFER_SIZE:
		push_error("(c) Expected buffer size %d, got %d" % [TileSynth2.OUTPUT_BUFFER_SIZE, north_tiles.size()])
		store.close()
		_cleanup()
		return false

	var c_passed := true
	for r in 32:
		for c in 32:
			var cls: int = north_tiles[(r * 32 + c) * 3]
			if r < 16:
				if cls != TileSynth2.TILE_WATER:
					push_error("(c) North-first falsified: row %d col %d expected WATER, got %d" % [r, c, cls])
					c_passed = false
					break
			else:
				if cls == TileSynth2.TILE_WATER:
					push_error("(c) North-first falsified: row %d col %d expected non-WATER, got WATER" % [r, c])
					c_passed = false
					break
		if not c_passed:
			break
	if not c_passed:
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (f) Tunnel produces no ROAD or PATH tiles (§8 f)
	# Hidden Tunnel was in Cell (4, 4) at v=14 (local row 4 in 32x32: 32 - 14*2 = 4)
	# -------------------------------------------------------------
	var area_4_4 := _build_area(store, 4, 4)
	var synth_4_4 := TileSynth2.synthesize_cell(4, 4, area_4_4, 0)
	var tiles_4_4: PackedByteArray = synth_4_4["tiles"]

	# Tunnel was at u in [2, 6], v=14. In 32x32 grid: col in [4, 12], row = 36 - 28 - 4 = 4.
	for c in range(4, 13):
		var cls: int = tiles_4_4[(4 * 32 + c) * 3]
		if cls == TileSynth2.TILE_ROAD or cls == TileSynth2.TILE_PATH:
			push_error("(f) Tunnel produced road/path tile at row 4, col %d: class %d" % [c, cls])
			store.close()
			_cleanup()
			return false

	# -------------------------------------------------------------
	# (g) Seamless road boundary (§8 g)
	# Road crossing boundary between cell A (0,0) and east neighbour B (1,0).
	# A's col 31 and B's col 0 must be ROAD/PATH on same rows with matching masks.
	# -------------------------------------------------------------
	var crossing_road_pts := PackedVector2Array([Vector2(0, 8), Vector2(16, 8)])
	var crossing_line := {
		"kind": "road",
		"subkind": "primary",
		"geom_pts": MapStore.pack_pts(crossing_road_pts)
	}

	var seamless_area_a := {
		Vector2i.ZERO: {
			"polys": [],
			"lines": [crossing_line],
			"places": [],
			"covered": true,
			"sea": 0
		},
		Vector2i(1, 0): {
			"polys": [],
			"lines": [crossing_line],
			"places": [],
			"covered": true,
			"sea": 0
		}
	}
	var seamless_area_b := {
		Vector2i.ZERO: {
			"polys": [],
			"lines": [crossing_line],
			"places": [],
			"covered": true,
			"sea": 0
		},
		Vector2i(-1, 0): {
			"polys": [],
			"lines": [crossing_line],
			"places": [],
			"covered": true,
			"sea": 0
		}
	}

	var synth_a := TileSynth2.synthesize_cell(0, 0, seamless_area_a, 0)
	var synth_b := TileSynth2.synthesize_cell(1, 0, seamless_area_b, 0)
	var tiles_a: PackedByteArray = synth_a["tiles"]
	var tiles_b: PackedByteArray = synth_b["tiles"]

	var found_road := false
	for r in 32:
		var a_idx := (r * 32 + 31) * 3
		var b_idx := (r * 32 + 0) * 3
		var a_cls: int = tiles_a[a_idx]
		var b_cls: int = tiles_b[b_idx]
		var a_mask: int = tiles_a[a_idx + 2]
		var b_mask: int = tiles_b[b_idx + 2]

		var a_is_road := (a_cls == TileSynth2.TILE_ROAD or a_cls == TileSynth2.TILE_PATH)
		var b_is_road := (b_cls == TileSynth2.TILE_ROAD or b_cls == TileSynth2.TILE_PATH)

		if a_is_road or b_is_road:
			found_road = true
			if a_cls != b_cls:
				push_error("(g) Road class mismatch at row %d: Cell A col 31 is %d, Cell B col 0 is %d" % [r, a_cls, b_cls])
				store.close()
				_cleanup()
				return false
			# A's east bit (bit 1 = 2) must be set, and B's west bit (bit 3 = 8) must be set
			if (a_mask & 2) == 0:
				push_error("(g) Road seamless mismatch: Cell A col 31 missing east mask bit at row %d" % r)
				store.close()
				_cleanup()
				return false
			if (b_mask & 8) == 0:
				push_error("(g) Road seamless mismatch: Cell B col 0 missing west mask bit at row %d" % r)
				store.close()
				_cleanup()
				return false
	if not found_road:
		push_error("(g) No road tiles found crossing boundary between cell A and B")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (h) Culvert and Bridge (§8 h)
	# 1. Culvert: Stream crosses Quiet Lane in cell (4, 5) without bridge tag -> road stays continuous.
	# 2. Bridge: River crossed by bridge=yes road in cell (5, 4) -> produces BRIDGE tiles.
	# -------------------------------------------------------------
	# 1. Check bridge in cell (5, 4)
	var area_5_4 := _build_area(store, 5, 4)
	var synth_5_4 := TileSynth2.synthesize_cell(5, 4, area_5_4, 0)
	var tiles_5_4: PackedByteArray = synth_5_4["tiles"]

	var found_bridge := false
	for r in 32:
		for c in 32:
			if tiles_5_4[(r * 32 + c) * 3] == TileSynth2.TILE_BRIDGE:
				found_bridge = true
				break
		if found_bridge:
			break
	if not found_bridge:
		push_error("(h) Bridge road over river failed to produce BRIDGE tiles in cell (5, 4)")
		store.close()
		_cleanup()
		return false

	# 2. Check culvert in cell (4, 5)
	var area_4_5 := _build_area(store, 4, 5)
	var synth_4_5 := TileSynth2.synthesize_cell(4, 5, area_4_5, 0)
	var tiles_4_5: PackedByteArray = synth_4_5["tiles"]

	# Quiet Lane is at v=2.0 (row = 36 - 4 - 4 = 28 in 32x32: 32 - 4 = 28).
	# Stream is at u=8.0 (col = 16 in 32x32).
	# At the crossing (col 16, row 28), it must be ROAD or PATH, not WATER!
	var crossing_cls: int = tiles_4_5[(28 * 32 + 16) * 3]
	if crossing_cls != TileSynth2.TILE_ROAD and crossing_cls != TileSynth2.TILE_PATH:
		push_error("(h) Culvert failed: crossing tile at row 28, col 16 is class %d (expected ROAD/PATH)" % crossing_cls)
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (e) Falsifier — coastline side (§8 e)
	# -------------------------------------------------------------
	# Normal coastline in cell (5, 4): runs south to north at u=15.0.
	# East side (col 31) is water/sea, West side (col 20) is land.
	var normal_east_cls: int = tiles_5_4[(8 * 32 + 31) * 3]
	var normal_west_cls: int = tiles_5_4[(8 * 32 + 20) * 3]
	if normal_east_cls != TileSynth2.TILE_WATER:
		push_error("(e) Normal orientation: col 31 expected WATER, got %d" % normal_east_cls)
		store.close()
		_cleanup()
		return false
	if normal_west_cls == TileSynth2.TILE_WATER:
		push_error("(e) Normal orientation: col 20 expected land, got WATER")
		store.close()
		_cleanup()
		return false

	# Reversed coastline: reverse points of coastline in area
	var rev_area_5_4: Dictionary = {}
	for k in area_5_4:
		var n_orig: Dictionary = area_5_4[k]
		var new_lines: Array = []
		for l in n_orig.get("lines", []):
			if l.get("kind") == "coastline":
				var pts := MapStore.unpack_pts(l["geom_pts"])
				pts.reverse()
				new_lines.append({
					"kind": "coastline",
					"subkind": l.get("subkind", ""),
					"geom_pts": MapStore.pack_pts(pts)
				})
			else:
				new_lines.append(l)
		rev_area_5_4[k] = {
			"polys": n_orig.get("polys", []),
			"lines": new_lines,
			"places": n_orig.get("places", []),
			"covered": n_orig.get("covered", true),
			"sea": n_orig.get("sea", 0)
		}

	var rev_synth := TileSynth2.synthesize_cell(5, 4, rev_area_5_4, 0)
	var rev_tiles: PackedByteArray = rev_synth["tiles"]
	var rev_east_cls: int = rev_tiles[(8 * 32 + 31) * 3]
	var rev_west_cls: int = rev_tiles[(8 * 32 + 20) * 3]

	if rev_east_cls == TileSynth2.TILE_WATER:
		push_error("(e) Reversed orientation: col 31 should be land, got WATER")
		store.close()
		_cleanup()
		return false
	if rev_west_cls != TileSynth2.TILE_WATER:
		push_error("(e) Reversed orientation: col 20 should be WATER, got %d" % rev_west_cls)
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (b) Falsifier — geometry matters (§8 b)
	# Moving one building vertex by 32 WM-m changes the hash
	# -------------------------------------------------------------
	var mod_area_5_4 := _build_area(store, 5, 4)
	var found_b := false
	for p in mod_area_5_4[Vector2i.ZERO]["polys"]:
		if p.get("kind") == "building" and p.get("name") == "Boundary Market":
			var rings := MapStore.unpack_rings(p["geom_rings"])
			# Move vertex 1 by 32 WM-m = 2.0 store units
			rings[0][1].x += 2.0
			p["geom_rings"] = MapStore.pack_rings(rings)
			found_b = true
			break
	if not found_b:
		push_error("(b) Could not find building in cell (5, 4) to test geometry falsifier")
		store.close()
		_cleanup()
		return false

	var mod_synth_5_4 := TileSynth2.synthesize_cell(5, 4, mod_area_5_4, 0)
	if mod_synth_5_4["tiles"] == tiles_5_4:
		push_error("(b) Falsifier failed: moving building vertex by 32 WM-m did not change tile buffer")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (d) Falsifier — one building, once (§8 d)
	# Straddling building yields exactly one door group across the two cells
	# -------------------------------------------------------------
	var area_5_5 := _build_area(store, 5, 5)
	var synth_5_5 := TileSynth2.synthesize_cell(5, 5, area_5_5, 0)

	# In cell (5, 4), Building 4 (straddling) is anchored at col0=5, row0=9 in working grid (size 5x4),
	# yielding its door at col 7, row 12 in working grid (local 32x32: col 3, row 8).
	var straddle_doors_5_4 := 0
	if tiles_5_4[(8 * 32 + 3) * 3] == TileSynth2.TILE_DOOR:
		straddle_doors_5_4 += 1

	# In cell (4, 4), at corresponding west edge (col 31, row 8), it must NOT be a door
	var straddle_doors_4_4 := 0
	if tiles_4_4[(8 * 32 + 31) * 3] == TileSynth2.TILE_DOOR:
		straddle_doors_4_4 += 1

	var total_straddle_doors := straddle_doors_5_4 + straddle_doors_4_4
	if total_straddle_doors != 1:
		push_error("(d) Straddling building yielded %d door groups across cells (expected 1)" % total_straddle_doors)
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (i) Fallback houses (§8 i)
	# The residential polygon with no footprints in Cell (4, 4) gets >= 1 fallback house
	# -------------------------------------------------------------
	# Way 121 in cell (4, 4) is at u in [1, 5], v in [9, 12] -> cols 2..10, rows 8..14
	var fallback_building_tiles := 0
	for r in range(8, 15):
		for c in range(2, 11):
			var cls: int = tiles_4_4[(r * 32 + c) * 3]
			if cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_DOOR or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_RUBBLE or cls == TileSynth2.TILE_STAMP:
				fallback_building_tiles += 1
	if fallback_building_tiles == 0 or int(synth_4_4.get("stats", {}).get("fallback_placed", 0)) < 1:
		push_error("(i) Residential polygon with no footprints produced 0 fallback houses in cell (4, 4)")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (j) Named POI produces exactly one sign with its name (§8 j)
	# -------------------------------------------------------------
	var found_cafe_sign := false
	var cafe_sign_idx := -1
	for s_i in synth_5_4["signs"].size():
		if synth_5_4["signs"][s_i] == "Parkside Cafe":
			found_cafe_sign = true
			cafe_sign_idx = s_i
			break
	if not found_cafe_sign:
		push_error("(j) 'Parkside Cafe' not found in synth_5_4 signs list: %s" % str(synth_5_4["signs"]))
		store.close()
		_cleanup()
		return false

	var cafe_sign_tile_count := 0
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			if tiles_5_4[idx] == TileSynth2.TILE_SIGN and tiles_5_4[idx + 1] == cafe_sign_idx:
				cafe_sign_tile_count += 1
	if cafe_sign_tile_count != 1:
		push_error("(j) 'Parkside Cafe' produced %d sign tiles (expected 1)" % cafe_sign_tile_count)
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (k) Falsifying — minor ways dropped & houses placed (§10.7 k)
	# -------------------------------------------------------------
	var minor_ways := store._rows("SELECT 1 FROM features_line WHERE subkind LIKE '%sidewalk%' OR subkind LIKE '%driveway%' LIMIT 1;")
	if not minor_ways.is_empty():
		push_error("(k) Falsifying: sidewalks or driveways are stored in features_line (expected absent)")
		store.close()
		_cleanup()
		return false

	var three_houses_doors := 0
	tiles_4_5 = synth_4_5["tiles"]
	for r in range(14, 22):
		for c in range(17, 27):
			var idx: int = (r * 32 + c) * 3
			if tiles_4_5[idx] == TileSynth2.TILE_DOOR:
				three_houses_doors += 1
	# Placement is read from the generator's own count: the ruin pass (§11.2) can turn a placed house into
	# rubble, so a standing DOOR is a poor proxy for "placed" (§13 moved a house's row, and with it its fate).
	var placed_houses: int = int(synth_4_5.get("stats", {}).get("buildings_placed", 0))
	if three_houses_doors < 2 and placed_houses < 2:
		push_error("(k) Falsifying: expected at least 2 of 3 houses placed, got %d (doors) and %d (stats)" % [three_houses_doors, int(synth_4_5.get("stats", {}).get("buildings_placed", 0))])
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (l) Shop is placed over parking (§10.7 l)
	# -------------------------------------------------------------
	var shop_roof_tiles := 0
	var parking_plaza_tiles := 0
	for r in range(22, 31):
		for c in range(19, 29):
			var idx: int = (r * 32 + c) * 3
			var cls: int = tiles_4_4[idx]
			if cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_DOOR or cls == TileSynth2.TILE_RUBBLE or cls == TileSynth2.TILE_STAMP:
				shop_roof_tiles += 1
			elif cls == TileSynth2.TILE_PLAZA:
				parking_plaza_tiles += 1
	if shop_roof_tiles == 0:
		push_error("(l) Shop building not placed over parking in cell (4, 4)")
		store.close()
		_cleanup()
		return false
	if parking_plaza_tiles == 0:
		push_error("(l) Expected parking plaza tiles around shop in cell (4, 4)")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (m) Every placed building's south ring row is clear (§10.7 m)
	# -------------------------------------------------------------
	for res_c in [synth_4_4, synth_4_5, synth_5_4, synth_5_5]:
		var c_tiles: PackedByteArray = res_c["tiles"]
		for r in 32:
			for c in 32:
				var idx: int = (r * 32 + c) * 3
				if c_tiles[idx] == TileSynth2.TILE_DOOR:
					if r + 1 < 32:
						var south_idx: int = ((r + 1) * 32 + c) * 3
						var s_cls: int = c_tiles[south_idx]
						if s_cls in [TileSynth2.TILE_ROOF, TileSynth2.TILE_WALL, TileSynth2.TILE_DOOR]:
							push_error("(m) Placed building at r=%d c=%d has building tile in south ring row" % [r, c])
							store.close()
							_cleanup()
							return false

	# -------------------------------------------------------------
	# (n) Stats matches hand count for fixture cells (§10.7 n)
	# -------------------------------------------------------------
	var s_4_4: Dictionary = synth_4_4.get("stats", {})
	if s_4_4.get("building_candidates") != 2 or s_4_4.get("buildings_placed") != 2 or s_4_4.get("fallback_placed") != 1:
		push_error("(n) Stats mismatch in cell (4, 4): %s" % str(s_4_4))
		store.close()
		_cleanup()
		return false

	var s_4_5: Dictionary = synth_4_5.get("stats", {})
	if s_4_5.get("building_candidates") != 4 or s_4_5.get("buildings_placed") != 3 or s_4_5.get("fallback_placed") != 0:
		push_error("(n) Stats mismatch in cell (4, 5): %s" % str(s_4_5))
		store.close()
		_cleanup()
		return false

	var s_5_4: Dictionary = synth_5_4.get("stats", {})
	if s_5_4.get("building_candidates") != 2 or s_5_4.get("buildings_placed") != 2 or s_5_4.get("fallback_placed") != 0:
		push_error("(n) Stats mismatch in cell (5, 4): %s" % str(s_5_4))
		store.close()
		_cleanup()
		return false

	var s_5_5: Dictionary = synth_5_5.get("stats", {})
	if s_5_5.get("building_candidates") != 0 or s_5_5.get("buildings_placed") != 0 or s_5_5.get("fallback_placed") != 0:
		push_error("(n) Stats mismatch in cell (5, 5): %s" % str(s_5_5))
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (o) Landmark buildings and outdoor structures (§10.8, Item 22)
	# -------------------------------------------------------------
	# Falsifying test:
	# Without landmark entry, cell (4, 4) Building 1 roof tiles carry NO bit 32,
	# and signs list has no "Fixture Town Hall".
	var town_hall_wm: Vector2 = Grid.latlon_to_wm(0.0099174007, 0.0099174007)
	var without_lm_has_bit32 := false
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			var cls: int = tiles_4_4[idx]
			var v: int = tiles_4_4[idx + 1]
			if cls == TileSynth2.TILE_ROOF and (v == 32 or (v & 32) != 0):
				without_lm_has_bit32 = true
	var without_lm_has_sign := false
	for s in synth_4_4.get("signs", []):
		if s == "Fixture Town Hall":
			without_lm_has_sign = true

	if without_lm_has_bit32 or without_lm_has_sign:
		push_error("(o) [falsifier] Building 1 carried landmark bit 32 or sign before landmark was passed in area")
		store.close()
		_cleanup()
		return false

	# With landmark entry:
	var area_4_4_lm := _build_area(store, 4, 4)
	area_4_4_lm[Vector2i.ZERO]["landmarks"] = [{
		"id": "fixture-city:town-hall",
		"name": "Fixture Town Hall",
		"door_wm": town_hall_wm
	}]
	var synth_4_4_lm := TileSynth2.synthesize_cell(4, 4, area_4_4_lm, 0)
	var tiles_4_4_lm: PackedByteArray = synth_4_4_lm["tiles"]

	var with_lm_roof_32_count := 0
	var with_lm_door_32_count := 0
	var with_lm_wall_landmark_count := 0
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			var cls: int = tiles_4_4_lm[idx]
			var v: int = tiles_4_4_lm[idx + 1]
			if cls == TileSynth2.TILE_ROOF and v == 32:
				with_lm_roof_32_count += 1
			elif cls == TileSynth2.TILE_DOOR and v == 32:
				with_lm_door_32_count += 1
			elif cls == TileSynth2.TILE_WALL and (v == 32 or v == 40):
				with_lm_wall_landmark_count += 1

	if with_lm_roof_32_count == 0:
		push_error("(o) Landmark building in cell (4, 4) produced 0 ROOF 32 tiles")
		store.close()
		_cleanup()
		return false
	if with_lm_door_32_count != 1:
		push_error("(o) Landmark building in cell (4, 4) expected 1 DOOR 32 tile, got %d" % with_lm_door_32_count)
		store.close()
		_cleanup()
		return false
	if with_lm_wall_landmark_count == 0:
		push_error("(o) Landmark building in cell (4, 4) produced 0 WALL 32/40 tiles")
		store.close()
		_cleanup()
		return false

	var th_sign_idx := -1
	for s_i in synth_4_4_lm["signs"].size():
		if synth_4_4_lm["signs"][s_i] == "Fixture Town Hall":
			th_sign_idx = s_i
			break
	if th_sign_idx == -1:
		push_error("(o) 'Fixture Town Hall' sign missing from landmark synth signs: %s" % str(synth_4_4_lm["signs"]))
		store.close()
		_cleanup()
		return false

	var th_sign_tile_count := 0
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			if tiles_4_4_lm[idx] == TileSynth2.TILE_SIGN and tiles_4_4_lm[idx + 1] == th_sign_idx:
				th_sign_tile_count += 1
	if th_sign_tile_count != 1:
		push_error("(o) 'Fixture Town Hall' sign tile count expected 1, got %d" % th_sign_tile_count)
		store.close()
		_cleanup()
		return false

	# Landmark missing every building (outdoor structure):
	# Door placed on grass of cell (5, 5) (u=1, v=1) where there are 0 buildings
	var area_5_5_lm := _build_area(store, 5, 5)
	var outdoor_wm := Vector2(5.0 * Grid.CELL_WM + 1.0 * Grid.TILE_WM, 5.0 * Grid.CELL_WM + 1.0 * Grid.TILE_WM)
	area_5_5_lm[Vector2i.ZERO]["landmarks"] = [{
		"id": "fixture-park:scenic-lookout",
		"name": "Scenic Lookout",
		"door_wm": outdoor_wm
	}]
	var synth_5_5_lm := TileSynth2.synthesize_cell(5, 5, area_5_5_lm, 0)
	var tiles_5_5_lm: PackedByteArray = synth_5_5_lm["tiles"]

	var outdoor_roof_32 := 0
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			if tiles_5_5_lm[idx] == TileSynth2.TILE_ROOF and tiles_5_5_lm[idx + 1] == 32:
				outdoor_roof_32 += 1
	if outdoor_roof_32 != 0:
		push_error("(o) Outdoor landmark without building produced unexpected ROOF 32 tiles: %d" % outdoor_roof_32)
		store.close()
		_cleanup()
		return false

	var lookout_sign_idx := -1
	for s_i in synth_5_5_lm["signs"].size():
		if synth_5_5_lm["signs"][s_i] == "Scenic Lookout":
			lookout_sign_idx = s_i
			break
	if lookout_sign_idx == -1:
		push_error("(o) 'Scenic Lookout' sign missing from signs list")
		store.close()
		_cleanup()
		return false

	var lookout_sign_tiles := 0
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			if tiles_5_5_lm[idx] == TileSynth2.TILE_SIGN and tiles_5_5_lm[idx + 1] == lookout_sign_idx:
				lookout_sign_tiles += 1
	if lookout_sign_tiles != 1:
		push_error("(o) 'Scenic Lookout' sign tile count expected 1, got %d" % lookout_sign_tiles)
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (p) Landmarks first (§11.1, §11.7, Item 24)
	# -------------------------------------------------------------
	# 1. Falsifying: a fixture landmark boxed in by minor-road PATH tiles is placed and gilded,
	#    where the pass-18 rules reject it.
	var p1_area := _build_empty_area()
	var p1_ring := PackedVector2Array([
		Vector2(6.0, 6.0), Vector2(8.0, 6.0), Vector2(8.0, 8.0), Vector2(6.0, 8.0)
	]) # 32x32 WM-m -> A = 1024 -> house_m (5x4)
	p1_area[Vector2i.ZERO]["polys"] = [{
		"kind": "building",
		"subkind": "civic",
		"name": "Boxed Library",
		"geom_rings": [p1_ring]
	}]
	# Box in with minor-road (width <= 2 -> PATH) lines across the footprint so all 13 pass-18 nudges hit PATH
	var p1_lines: Array = []
	for y_su in [4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]:
		p1_lines.append({
			"kind": "road",
			"subkind": "residential",
			"geom_pts": PackedVector2Array([Vector2(3.0, float(y_su)), Vector2(11.0, float(y_su))])
		})
	p1_area[Vector2i.ZERO]["lines"] = p1_lines
	var p1_door_wm := Vector2(4.0 * Grid.CELL_WM + 7.0 * MapStore.GEOM_UNIT_WM, 4.0 * Grid.CELL_WM + 7.0 * MapStore.GEOM_UNIT_WM)
	p1_area[Vector2i.ZERO]["landmarks"] = [{
		"id": "fixture:boxed-library",
		"name": "Boxed Library",
		"door_wm": p1_door_wm
	}]
	var p1_res := TileSynth2.synthesize_cell(4, 4, p1_area, 0)
	var p1_tiles: PackedByteArray = p1_res["tiles"]
	var p1_gold := 0
	for i in range(0, p1_tiles.size(), 3):
		var cls: int = p1_tiles[i]
		var v: int = p1_tiles[i + 1]
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
			p1_gold += 1
	if p1_gold == 0 or int(p1_res.get("stats", {}).get("landmarks_placed", 0)) != 1:
		push_error("(p.1) [falsifier] Landmark boxed in by minor-road PATH tiles was rejected (gold=%d, stats=%s)" % [p1_gold, str(p1_res.get("stats", {}))])
		store.close()
		_cleanup()
		return false

	# 2. A landmark whose door point lies 2 tiles (1 store unit) outside its footprint is still gilded.
	var p2_area := _build_empty_area()
	p2_area[Vector2i.ZERO]["polys"] = [{
		"kind": "building",
		"subkind": "civic",
		"name": "Memorial Hall",
		"geom_rings": [p1_ring]
	}]
	# Door at y = 5.0 store units (1 store unit = 2 tiles south of outer ring y=6..8)
	var p2_door_wm := Vector2(4.0 * Grid.CELL_WM + 7.0 * MapStore.GEOM_UNIT_WM, 4.0 * Grid.CELL_WM + 5.0 * MapStore.GEOM_UNIT_WM)
	p2_area[Vector2i.ZERO]["landmarks"] = [{
		"id": "fixture:memorial-hall",
		"name": "Memorial Hall",
		"door_wm": p2_door_wm
	}]
	var p2_res := TileSynth2.synthesize_cell(4, 4, p2_area, 0)
	var p2_tiles: PackedByteArray = p2_res["tiles"]
	var p2_gold := 0
	for i in range(0, p2_tiles.size(), 3):
		var cls: int = p2_tiles[i]
		var v: int = p2_tiles[i + 1]
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
			p2_gold += 1
	if p2_gold == 0 or int(p2_res.get("stats", {}).get("landmarks_placed", 0)) != 1:
		push_error("(p.2) Landmark with door 2 tiles outside footprint was not gilded (gold=%d)" % p2_gold)
		store.close()
		_cleanup()
		return false

	# 3. A footprint too big for its gap is placed shrunk.
	var p3_area := _build_empty_area()
	# Large footprint: 6..12 x 6..11 store units -> w_t=12, h_t=10 (block_l 12x10)
	var p3_ring := PackedVector2Array([
		Vector2(5.0, 5.0), Vector2(11.0, 5.0), Vector2(11.0, 10.0), Vector2(5.0, 10.0)
	])
	p3_area[Vector2i.ZERO]["polys"] = [{
		"kind": "building",
		"subkind": "civic",
		"name": "Shrunk Museum",
		"geom_rings": [p3_ring]
	}]
	# Flank with primary roads (ROAD, w=3) leaving only an ~8-tile wide gap around x=8 store units (col=20),
	# so 12x10 fails all 21 nudges, but shrinking fits inside the gap.
	p3_area[Vector2i.ZERO]["lines"] = [
		{
			"kind": "road",
			"subkind": "primary",
			"geom_pts": PackedVector2Array([Vector2(5.0, 1.0), Vector2(5.0, 15.0)])
		},
		{
			"kind": "road",
			"subkind": "primary",
			"geom_pts": PackedVector2Array([Vector2(11.0, 1.0), Vector2(11.0, 15.0)])
		}
	]
	var p3_door_wm := Vector2(4.0 * Grid.CELL_WM + 8.0 * MapStore.GEOM_UNIT_WM, 4.0 * Grid.CELL_WM + 7.5 * MapStore.GEOM_UNIT_WM)
	p3_area[Vector2i.ZERO]["landmarks"] = [{
		"id": "fixture:shrunk-museum",
		"name": "Shrunk Museum",
		"door_wm": p3_door_wm
	}]
	var p3_res := TileSynth2.synthesize_cell(4, 4, p3_area, 0)
	var p3_tiles: PackedByteArray = p3_res["tiles"]
	var p3_gold := 0
	for i in range(0, p3_tiles.size(), 3):
		var cls: int = p3_tiles[i]
		var v: int = p3_tiles[i + 1]
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
			p3_gold += 1
	if p3_gold == 0 or p3_gold >= 120 or int(p3_res.get("stats", {}).get("landmarks_placed", 0)) != 1:
		push_error("(p.3) Shrunk landmark failed to place or did not shrink (gold=%d)" % p3_gold)
		store.close()
		_cleanup()
		return false

	# 4. Falsifying (§11.1a): a fixture landmark whose footprint straddles a cell edge,
	#    door in the north cell (4, 5) and anchor in the south cell (4, 4).
	#    - The south cell gilds it and gets its sign.
	#    - The north cell places NO sign-only fallback.
	#    - Both cells report it exactly once between them, in landmark_ids_placed.
	var p4_ring_south_frame := PackedVector2Array([
		Vector2(6.0, 12.0), Vector2(10.0, 12.0), Vector2(10.0, 17.5), Vector2(6.0, 17.5)
	]) # bbox center y = 14.75 in south cell (4, 4) -> anchored in (4, 4); extends 1.5 su into north cell (4, 5)
	var p4_poly := {
		"kind": "building",
		"subkind": "yes",
		"name": "Straddling Memorial",
		"geom_rings": [p4_ring_south_frame]
	}
	# Door at y = 1.0 store unit inside north cell (4, 5) -> y = 17.0 in south cell frame (inside outer ring 12..17.5)
	var p4_door_wm := Vector2(4.0 * Grid.CELL_WM + 8.0 * MapStore.GEOM_UNIT_WM, 5.0 * Grid.CELL_WM + 1.0 * MapStore.GEOM_UNIT_WM)
	var p4_lm := {
		"id": "fixture:straddling-memorial",
		"name": "Straddling Memorial",
		"door_wm": p4_door_wm
	}

	# Synthesize south cell (4, 4): poly in ZERO, landmark door in north neighbour (0, 1)
	var p4_south_area := _build_empty_area()
	p4_south_area[Vector2i.ZERO]["polys"] = [p4_poly]
	p4_south_area[Vector2i(0, 1)]["landmarks"] = [p4_lm]
	var p4_south_res := TileSynth2.synthesize_cell(4, 4, p4_south_area, 0)
	var p4_south_tiles: PackedByteArray = p4_south_res["tiles"]
	var p4_south_gold := 0
	for i in range(0, p4_south_tiles.size(), 3):
		var cls: int = p4_south_tiles[i]
		var v: int = p4_south_tiles[i + 1]
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
			p4_south_gold += 1
	var p4_south_has_sign := false
	for s in p4_south_res.get("signs", []):
		if s == "Straddling Memorial":
			p4_south_has_sign = true

	# Synthesize north cell (4, 5): poly in south neighbour (0, -1), landmark door in ZERO
	var p4_north_area := _build_empty_area()
	p4_north_area[Vector2i(0, -1)]["polys"] = [p4_poly]
	p4_north_area[Vector2i.ZERO]["landmarks"] = [p4_lm]
	var p4_north_res := TileSynth2.synthesize_cell(4, 5, p4_north_area, 0)
	var p4_north_has_sign := false
	for s in p4_north_res.get("signs", []):
		if s == "Straddling Memorial":
			p4_north_has_sign = true

	var p4_south_ids: Array = p4_south_res.get("stats", {}).get("landmark_ids_placed", [])
	var p4_north_ids: Array = p4_north_res.get("stats", {}).get("landmark_ids_placed", [])
	var p4_north_sign_only: int = int(p4_north_res.get("stats", {}).get("landmarks_sign_only", 0))

	if p4_south_gold == 0 or not p4_south_has_sign:
		push_error("(p.4) [falsifier] South anchor cell failed to gild straddling landmark or place its sign (gold=%d, has_sign=%s)" % [p4_south_gold, str(p4_south_has_sign)])
		store.close()
		_cleanup()
		return false
	if p4_north_has_sign or p4_north_sign_only != 0:
		push_error("(p.4) [falsifier] North door cell placed unexpected sign-only fallback (has_sign=%s, sign_only=%d)" % [str(p4_north_has_sign), p4_north_sign_only])
		store.close()
		_cleanup()
		return false
	if p4_south_ids != ["fixture:straddling-memorial"] or not p4_north_ids.is_empty():
		push_error("(p.4) [falsifier] Expected landmark_ids_placed once in south cell only, got south=%s north=%s" % [str(p4_south_ids), str(p4_north_ids)])
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (q)-(t) Ruin Pass, Fixed Fates, RUBBLE, Stamps & Determinism (§11.2, §14.1, §14.5.2)
	# -------------------------------------------------------------
	# (r) Falsifying: verify that in a cell with multiple houses in the far band,
	# at least one tile is RUBBLE (class 20, side ring), ruined/gone houses emit class 21 (TILE_STAMP)
	# and entries in res["stamps"], and NO tile carries legacy ROOF/WALL variant bit 16.
	var r_area := _build_empty_area()
	var r_polys: Array = []
	for h_i in 6:
		var bx: float = 1.0 + float(h_i % 3) * 5.0
		var by: float = 2.0 + float(h_i / 3) * 6.0
		var h_ring := PackedVector2Array([
			Vector2(bx, by), Vector2(bx + 2.0, by), Vector2(bx + 2.0, by + 1.5), Vector2(bx, by + 1.5)
		])
		r_polys.append({"kind": "building", "subkind": "house", "geom_rings": [h_ring], "name": ""})
	r_area[Vector2i.ZERO]["polys"] = r_polys
	# Put Waypost 5 km away (far band >= 3 km)
	r_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256))
	var r_res := TileSynth2.synthesize_cell(4, 4, r_area, 0)
	var r_tiles: PackedByteArray = r_res["tiles"]
	var r_rubble_count := 0
	var r_stamp_tile_count := 0
	var r_legacy_roof_wall_bit16 := 0
	for i in range(0, r_tiles.size(), 3):
		var cls: int = r_tiles[i]
		var v: int = r_tiles[i + 1]
		if cls == 20: # TILE_RUBBLE
			r_rubble_count += 1
		elif cls == 21: # TILE_STAMP
			r_stamp_tile_count += 1
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL) and (v & 16) != 0:
			r_legacy_roof_wall_bit16 += 1
	var r_stamps: Array = r_res.get("stamps", [])
	if r_rubble_count == 0 or r_stamp_tile_count == 0 or r_stamps.is_empty() or r_legacy_roof_wall_bit16 != 0:
		push_error("(r) [falsifier] Expected RUBBLE ring tiles, TILE_STAMP (21) tiles, non-empty stamps list, and 0 legacy ROOF/WALL bit-16 tiles; got rubble=%d stamp_tiles=%d stamps=%d legacy_bit16=%d" % [
			r_rubble_count, r_stamp_tile_count, r_stamps.size(), r_legacy_roof_wall_bit16
		])
		store.close()
		_cleanup()
		return false

	# (q) Ruin fates: church stands in far band, hospital is ruined (never gone), ruins subkind is ruined,
	# and ordinary houses follow hand-computed u(gx0, gy0, 9) against band thresholds.
	var q_area := _build_empty_area()
	var church_ring := PackedVector2Array([
		Vector2(1.0, 12.0), Vector2(3.0, 12.0), Vector2(3.0, 13.5), Vector2(1.0, 13.5)
	])
	var hosp_ring := PackedVector2Array([
		Vector2(6.0, 12.0), Vector2(8.0, 12.0), Vector2(8.0, 13.5), Vector2(6.0, 13.5)
	])
	var ruins_ring := PackedVector2Array([
		Vector2(11.0, 12.0), Vector2(13.0, 12.0), Vector2(13.0, 13.5), Vector2(11.0, 13.5)
	])
	q_area[Vector2i.ZERO]["polys"] = [
		{"kind": "building", "subkind": "church", "geom_rings": [church_ring], "name": "St. Mary"},
		{"kind": "building", "subkind": "hospital", "geom_rings": [hosp_ring], "name": "Old Clinic"},
		{"kind": "building", "subkind": "ruins", "geom_rings": [ruins_ring], "name": "Old Ruins"}
	]
	q_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256)) # far band
	var q_res := TileSynth2.synthesize_cell(4, 4, q_area, 0)
	var q_stats: Dictionary = q_res.get("stats", {})
	if int(q_stats.get("ordinary_standing", 0)) != 1 or int(q_stats.get("ordinary_ruined", 0)) != 2 or int(q_stats.get("ordinary_gone", 0)) != 0:
		push_error("(q) Fixed fates mismatch: expected 1 standing (church), 2 ruined (hospital+ruins), 0 gone; got %s" % str(q_stats))
		store.close()
		_cleanup()
		return false

	# (s) No landmark tile ever carries bit 16
	var s_area := _build_empty_area()
	var s_ring := PackedVector2Array([
		Vector2(4.0, 4.0), Vector2(12.0, 4.0), Vector2(12.0, 10.0), Vector2(4.0, 10.0)
	])
	s_area[Vector2i.ZERO]["polys"] = [{"kind": "building", "subkind": "public", "geom_rings": [s_ring], "name": "Grand Hall"}]
	var s_door_wm := Vector2(float(4 * 256) + 8.0 * 16.0, float(4 * 256) + 4.5 * 16.0)
	s_area[Vector2i.ZERO]["landmarks"] = [{"id": "fixture:grand-hall", "name": "Grand Hall", "door_wm": s_door_wm}]
	s_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256))
	var s_res := TileSynth2.synthesize_cell(4, 4, s_area, 0)
	var s_tiles: PackedByteArray = s_res["tiles"]
	for i in range(0, s_tiles.size(), 3):
		var cls: int = s_tiles[i]
		var v: int = s_tiles[i + 1]
		if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
			if (v & 16) != 0:
				push_error("(s) Landmark tile carried bit 16: cls=%d v=%d" % [cls, v])
				store.close()
				_cleanup()
				return false

	# (t) Determinism: same cell twice gives identical bytes; moving Waypost changes only fates and overgrowth — never placement
	var t_res_a := TileSynth2.synthesize_cell(4, 4, r_area, 0)
	var t_res_b := TileSynth2.synthesize_cell(4, 4, r_area, 0)
	if t_res_a["tiles"] != t_res_b["tiles"]:
		push_error("(t) Determinism failed: identical inputs produced different tile buffers")
		store.close()
		_cleanup()
		return false
	var r_area_camp := r_area.duplicate(true)
	r_area_camp["waypost_wm"] = Vector2(float(4 * 256) + 100.0, float(4 * 256) + 100.0) # camp band
	var t_res_camp := TileSynth2.synthesize_cell(4, 4, r_area_camp, 0)
	if t_res_a["stats"]["buildings_placed"] != t_res_camp["stats"]["buildings_placed"] or t_res_a["stats"]["building_candidates"] != t_res_camp["stats"]["building_candidates"]:
		push_error("(t) Moving Waypost changed building placement counts!")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# -------------------------------------------------------------
	# (u) Two-tile minimum widths and the 4 x 4 house (§13, Item 12d)
	# A service road, a footway, a stream, and a door path were one tile wide; now none is, and a small
	# house has two roof rows and two wall rows. FALSIFYING: this fails on the pre-§13 code.
	# Store units are 2 tiles: cell col = 2x, cell row = 32 - 2y (north-first).
	# -------------------------------------------------------------
	var u_area := _build_empty_area()
	u_area[Vector2i.ZERO]["lines"] = [
		{"kind": "road", "subkind": "service", "geom_pts": PackedVector2Array([Vector2(1.0, 3.5), Vector2(15.0, 3.5)])},
		{"kind": "path", "subkind": "footway", "geom_pts": PackedVector2Array([Vector2(4.0, 12.0), Vector2(15.0, 12.0)])},
		{"kind": "waterway", "subkind": "stream", "geom_pts": PackedVector2Array([Vector2(2.0, 9.5), Vector2(2.0, 15.5)])},
	]
	u_area[Vector2i.ZERO]["polys"] = [{
		"kind": "building",
		"subkind": "house",
		"name": "",
		"geom_rings": [PackedVector2Array([Vector2(6.0, 6.0), Vector2(7.0, 6.0), Vector2(7.0, 7.0), Vector2(6.0, 7.0)])] # 16x16 m: house_s
	}]
	var u_tiles: PackedByteArray = TileSynth2.synthesize_cell(4, 4, u_area, 0)["tiles"]
	# Overgrowth (§11.2) turns some path tiles into tall grass, so measure the best column along each line.
	var service_w := _thickness(u_tiles, 20, 30, 19, 31, false, [TileSynth2.TILE_PATH, TileSynth2.TILE_ROAD])
	var footway_w := _thickness(u_tiles, 20, 30, 0, 14, false, [TileSynth2.TILE_PATH, TileSynth2.TILE_ROAD])
	var stream_w := _thickness(u_tiles, 2, 12, 0, 7, true, [TileSynth2.TILE_WATER])
	if service_w < 2 or footway_w < 2 or stream_w < 2:
		push_error("(u) Widths: service %d, footway %d, stream %d tiles (each must be >= 2)" % [service_w, footway_w, stream_w])
		store.close()
		_cleanup()
		return false

	var u_roof_rows := {}
	var u_wall_rows := {}
	var u_door := Vector2i(-1, -1)
	var u_doors := 0
	for r in 32:
		for c in 32:
			var cls: int = u_tiles[(r * 32 + c) * 3]
			if cls == TileSynth2.TILE_ROOF:
				u_roof_rows[r] = true
			elif cls == TileSynth2.TILE_WALL:
				u_wall_rows[r] = true
			elif cls == TileSynth2.TILE_DOOR:
				u_doors += 1
				u_door = Vector2i(c, r)
	# The door sits in the bottom wall row, so with two wall rows the wall rows above it hold only WALL tiles
	# and the door row itself holds the DOOR: 2 roof rows, 1 WALL-only row, and the door row.
	if u_doors != 1 or u_roof_rows.size() != 2 or u_wall_rows.size() != 2:
		push_error("(u) House: %d door(s), %d roof row(s), %d WALL row(s) (expected 1, 2, and 2: the door row also holds WALL tiles beside the door)" % [u_doors, u_roof_rows.size(), u_wall_rows.size()])
		store.close()
		_cleanup()
		return false
	# The door path below the door is two tiles wide where it exists.
	var below: int = (u_door.y + 1) * 32 + u_door.x
	if u_tiles[below * 3] == TileSynth2.TILE_PATH and u_tiles[(below + 1) * 3] != TileSynth2.TILE_PATH:
		push_error("(u) Door path below the door is one tile wide")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (v) Item 33 (§14.1, §14.2, §14.4, §14.5.2): Ruined house sprites, door column reuse,
	#     State C vs decals (independent SALT_DECAL_DOORSTEP = 19), walkability, and ruined_block non-stacking.
	#     FALSIFYING: fails on pre-Item 33 code.
	# -------------------------------------------------------------
	var ts_inst := TileSynth2.new()
	if not ts_inst.has_method("is_walkable") or not ts_inst.has_method("is_tile_walkable_in_buffer") or not ts_inst.has_method("ruined_block_src_tile"):
		push_error("(v) [falsifier] TileSynth2 is missing is_walkable / is_tile_walkable_in_buffer / ruined_block_src_tile")
		store.close()
		_cleanup()
		return false

	# 1. Ruined house_s (4x4, subkind "ruins"), ruined house_m (5x4, subkind "ruins"), and ruined block_l (10x9, subkind "hospital")
	var v_area := _build_empty_area()
	# house_s at store units (2..3, 12..13) -> 16x16m (256 m^2 < 500) -> house_s (4x4)
	var v_hs_ring := PackedVector2Array([
		Vector2(2.0, 12.0), Vector2(3.0, 12.0), Vector2(3.0, 13.0), Vector2(2.0, 13.0)
	])
	# house_m at store units (2..4, 2..3.5) -> 32x24m (768 m^2 in 500..1500) -> house_m (5x4)
	var v_hm_ring := PackedVector2Array([
		Vector2(2.0, 2.0), Vector2(4.0, 2.0), Vector2(4.0, 3.5), Vector2(2.0, 3.5)
	])
	# block_l at store units (6..11, 5..9.5) -> w_t = 10, h_t = 9 -> block_l (10x9)
	var v_bl_ring := PackedVector2Array([
		Vector2(6.0, 5.0), Vector2(11.0, 5.0), Vector2(11.0, 9.5), Vector2(6.0, 9.5)
	])
	v_area[Vector2i.ZERO]["polys"] = [
		{"kind": "building", "subkind": "ruins", "geom_rings": [v_hs_ring], "name": ""},
		{"kind": "building", "subkind": "ruins", "geom_rings": [v_hm_ring], "name": ""},
		{"kind": "building", "subkind": "hospital", "geom_rings": [v_bl_ring], "name": "Ruined Wing"}
	]
	v_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256)) # far band
	var v_res := TileSynth2.synthesize_cell(4, 4, v_area, 0)
	var v_tiles: PackedByteArray = v_res["tiles"]
	var v_stamps: Array = v_res.get("stamps", [])
	if v_stamps.size() < 3:
		push_error("(v.1) [falsifier] Expected >= 3 stamp entries (ruined house_s + ruined house_m + ruined block_l SW section + lot decals), got %d: %s" % [v_stamps.size(), str(v_stamps)])
		store.close()
		_cleanup()
		return false

	var found_hs_stamp := false
	var found_hm_stamp := false
	var found_bl_stamp := false
	for st in v_stamps:
		var sid: int = int(st.get("stamp_id", -1))
		var sw: int = int(st.get("w", 0))
		var sh: int = int(st.get("h", 0))
		var agx: int = int(st.get("anchor_gx", 0))
		var agy: int = int(st.get("anchor_gy", 0))
		var lx0: int = agx - 4 * 32
		var ly0: int = agy - 4 * 32
		if sid >= 15 and sid <= 30 and sw == 4 and sh == 4:
			found_hs_stamp = true
			# Check SALT_DOOR_ROOF = 5 reuse: gx0 = agx, gy0 = 4 * 32 + (31 - ly0)
			var hs_gx0: int = agx
			var hs_gy0: int = 4 * 32 + (31 - ly0)
			var expected_d_col: int = 1 if TileSynth2.u_rand(hs_gx0, hs_gy0, 0, TileSynth2.SALT_DOOR_ROOF) < 0.5 else 2
			var stamp_is_door2: bool = (sid >= 19 and sid <= 22) or (sid >= 27 and sid <= 30)
			if (expected_d_col == 2) != stamp_is_door2:
				push_error("(v.1) Ruined house_s stamp_id %d did not reuse SALT_DOOR_ROOF door_col=%d" % [sid, expected_d_col])
				store.close()
				_cleanup()
				return false
			# Verify door tile is walkable TILE_DOOR (14, mask=sid) and other 15 tiles are solid TILE_STAMP (21, variant=sid, mask=1)
			for ty in 4:
				for tx in 4:
					var t_idx: int = ((ly0 + ty) * 32 + (lx0 + tx)) * 3
					var t_cls: int = v_tiles[t_idx]
					var t_var: int = v_tiles[t_idx + 1]
					var t_msk: int = v_tiles[t_idx + 2]
					if tx == expected_d_col and ty == 3:
						if t_cls != TileSynth2.TILE_DOOR or t_msk != sid or not bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined house_s door tile mismatch at (%d,%d): cls=%d var=%d mask=%d" % [tx, ty, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
					else:
						if t_cls != 21 or t_var != sid or t_msk != 1 or bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined house_s body tile mismatch at (%d,%d): cls=%d var=%d mask=%d" % [tx, ty, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
		elif sid >= 31 and sid <= 38 and sw == 5 and sh == 4:
			found_hm_stamp = true
			for ty in 4:
				for tx in 5:
					var t_idx: int = ((ly0 + ty) * 32 + (lx0 + tx)) * 3
					var t_cls: int = v_tiles[t_idx]
					var t_var: int = v_tiles[t_idx + 1]
					var t_msk: int = v_tiles[t_idx + 2]
					if tx == 2 and ty == 3:
						if t_cls != TileSynth2.TILE_DOOR or t_msk != sid or not bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined house_m door tile mismatch at (2,3): cls=%d var=%d mask=%d" % [t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
					else:
						if t_cls != 21 or t_var != sid or t_msk != 1 or bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined house_m body tile mismatch at (%d,%d): cls=%d var=%d mask=%d" % [tx, ty, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
		elif sid == 42 and sw == 8 and sh == 7:
			found_bl_stamp = true
			for ty in 7:
				for tx in 8:
					var t_idx: int = ((ly0 + ty) * 32 + (lx0 + tx)) * 3
					var t_cls: int = v_tiles[t_idx]
					var t_var: int = v_tiles[t_idx + 1]
					var t_msk: int = v_tiles[t_idx + 2]
					if (tx == 3 or tx == 4) and ty == 6:
						if t_cls != TileSynth2.TILE_DOOR or t_msk != 42 or not bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined block_l door tile mismatch at (%d,6): cls=%d var=%d mask=%d" % [tx, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
					else:
						if t_cls != 21 or t_var != 42 or t_msk != 1 or bool(ts_inst.call("is_tile_walkable_in_buffer", v_tiles, lx0 + tx, ly0 + ty)):
							push_error("(v.1) Ruined block_l body tile mismatch at (%d,%d): cls=%d var=%d mask=%d" % [tx, ty, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false

	if not found_hs_stamp or not found_hm_stamp or not found_bl_stamp:
		push_error("(v.1) Missing ruined house_s (%s), house_m (%s), or 10x9 block_l (%s) in stamps: %s" % [str(found_hs_stamp), str(found_hm_stamp), str(found_bl_stamp), str(v_stamps)])
		store.close()
		_cleanup()
		return false

	# 2. Verify ruined_block_src_tile(x, y, 10, 9) non-stacking vertical mapping and east-edge horizontal mapping
	var expected_ty_9 := [0, 1, 1, 1, 2, 3, 4, 5, 6]
	var expected_tx_10 := [0, 1, 2, 3, 4, 3, 4, 5, 6, 7]
	for y in 9:
		for x in 10:
			var src_t: Vector2i = ts_inst.call("ruined_block_src_tile", x, y, 10, 9)
			if src_t.x != expected_tx_10[x] or src_t.y != expected_ty_9[y]:
				push_error("(v.2) ruined_block_src_tile(%d, %d, 10, 9) expected (%d, %d), got %s" % [x, y, expected_tx_10[x], expected_ty_9[y], str(src_t)])
				store.close()
				_cleanup()
				return false

	# 3. Verify walkability of decals (47 decal_wall_stump & 57 decal_boulder are solid; others 43..58 are walkable)
	if bool(ts_inst.call("is_walkable", 21, 47, 1)) != false or bool(ts_inst.call("is_walkable", 21, 57, 1)) != false:
		push_error("(v.3) Solid decals (47, 57) must return is_walkable == false")
		store.close()
		_cleanup()
		return false
	if bool(ts_inst.call("is_walkable", 21, 43, 0)) != true or bool(ts_inst.call("is_walkable", 21, 58, 0)) != true:
		push_error("(v.3) Walkable decals (43, 58) must return is_walkable == true")
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (w) Item 33b (F70 a, §14.1.3, §14.1.4): Gone-building path — State C shells (39..41),
	#     decal lots (43..58), and independent SALT_DECAL_DOORSTEP = 19 across >= 64 footprints.
	#     FALSIFYING: fails if doorstep uses salt 18 instead of 19 or if State C is switched off.
	# -------------------------------------------------------------
	var w_cells := [11, 13, 15, 20, 23, 30, 32, 43]
	var w_cy := 10
	var w_total_footprints := 0
	var w_state_c_lots := 0
	var w_decal_lots := 0
	var w_doorstep_only_lots := 0
	var w_multi_no_doorstep_lots := 0

	for w_cx in w_cells:
		var w_area := _build_empty_area()
		var w_polys: Array = []
		var w_lot_specs: Array = []
		for grid_r in 3:
			for grid_c in 3:
				var col0_t: int = 6 + grid_c * 9
				var row0_t: int = 6 + grid_r * 9
				var is_hm: bool = ((grid_r + grid_c + w_cx) % 2 == 1)
				var bw: int = 5 if is_hm else 4
				var bh: int = 4
				var cc_f: float = float(col0_t) + float(bw) / 2.0
				var rc_f: float = float(row0_t) + float(bh) / 2.0
				var bx_c: float = (cc_f - 4.0) / 2.0
				var by_c: float = (36.0 - rc_f) / 2.0
				var half_x: float = 1.0 if is_hm else 0.5
				var half_y: float = 0.75 if is_hm else 0.5
				var ring := PackedVector2Array([
					Vector2(bx_c - half_x, by_c - half_y),
					Vector2(bx_c + half_x, by_c - half_y),
					Vector2(bx_c + half_x, by_c + half_y),
					Vector2(bx_c - half_x, by_c + half_y)
				])
				w_polys.append({"kind": "building", "subkind": "house", "geom_rings": [ring], "name": ""})
				w_lot_specs.append({
					"col0": col0_t,
					"row0": row0_t,
					"w": bw,
					"h": bh,
					"is_hm": is_hm
				})
				w_total_footprints += 1
		w_area[Vector2i.ZERO]["polys"] = w_polys
		w_area["waypost_wm"] = Vector2(float(w_cx * 256) + 5000.0, float(w_cy * 256)) # far band (>= 3 km)
		var w_res := TileSynth2.synthesize_cell(w_cx, w_cy, w_area, 0)
		var w_tiles: PackedByteArray = w_res["tiles"]
		var w_stamps: Array = w_res.get("stamps", [])

		for spec in w_lot_specs:
			var col0: int = spec["col0"]
			var row0: int = spec["row0"]
			var bw: int = spec["w"]
			var bh: int = spec["h"]
			var is_hm: bool = spec["is_hm"]
			var lx0: int = col0 - 4
			var ly0: int = row0 - 4
			var gx0: int = w_cx * 32 + lx0
			var gy0: int = w_cy * 32 + (35 - row0)
			var gy0_top: int = w_cy * 32 + ly0
			var d_col: int = 2 if is_hm else (1 if TileSynth2.u_rand(gx0, gy0, 0, TileSynth2.SALT_DOOR_ROOF) < 0.5 else 2)

			var f_val: float = TileSynth2.u_rand(gx0, gy0, 0, TileSynth2.SALT_BUILDING_FATE)
			if f_val < 0.55:
				continue # standing or ruined in far band

			var is_sc: bool = TileSynth2.u_rand(gx0, gy0, 0, TileSynth2.SALT_GONE_STATE) < 0.10
			if is_sc:
				w_state_c_lots += 1
				var expected_sc_id: int = 41 if is_hm else (40 if d_col == 2 else 39)
				for ty in bh:
					for tx in bw:
						var t_idx: int = ((ly0 + ty) * 32 + (lx0 + tx)) * 3
						var t_cls: int = w_tiles[t_idx]
						var t_var: int = w_tiles[t_idx + 1]
						var t_msk: int = w_tiles[t_idx + 2]
						if t_cls == TileSynth2.TILE_DOOR:
							push_error("(w) State C lot at (%d,%d) contained unexpected TILE_DOOR" % [gx0, gy0])
							store.close()
							_cleanup()
							return false
						if t_cls != 21 or t_var != expected_sc_id or t_msk != 1:
							push_error("(w) State C lot tile (%d,%d) expected (21,%d,1), got (%d,%d,%d)" % [tx, ty, expected_sc_id, t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
				var matched_sc_stamps := 0
				for st in w_stamps:
					if int(st.get("stamp_id", -1)) == expected_sc_id and int(st.get("anchor_gx", -999)) == gx0 and int(st.get("anchor_gy", -999)) == gy0_top and int(st.get("w", 0)) == bw and int(st.get("h", 0)) == bh:
						matched_sc_stamps += 1
				if matched_sc_stamps != 1:
					push_error("(w) State C lot at (%d,%d) expected 1 stamp entry (%d, %d, %d, %d, %d), got %d" % [gx0, gy0, expected_sc_id, gx0, gy0_top, bw, bh, matched_sc_stamps])
					store.close()
					_cleanup()
					return false
			else:
				w_decal_lots += 1
				var num_decals: int = 1 + int(floor(TileSynth2.u_rand(gx0, gy0, 0, TileSynth2.SALT_DECAL_COUNT) * 3.0))
				var has_doorstep: bool = TileSynth2.u_rand(gx0, gy0, 0, TileSynth2.SALT_DECAL_DOORSTEP) < 0.50
				if has_doorstep and num_decals == 1:
					w_doorstep_only_lots += 1
				if not has_doorstep and num_decals >= 2:
					w_multi_no_doorstep_lots += 1

				# Compute expected decals after collision skips (§14.1.4)
				var expected_occupied: Dictionary = {}
				if has_doorstep:
					expected_occupied[Vector2i(d_col, bh - 1)] = 58
				var start_i: int = 1 if has_doorstep else 0
				for i in range(start_i, num_decals):
					var dlx: int = int(floor(TileSynth2.u_rand(gx0 + i * 7, gy0, 0, TileSynth2.SALT_DECAL_POS) * float(bw)))
					var dly: int = int(floor(TileSynth2.u_rand(gx0, gy0 + i * 11, 0, TileSynth2.SALT_DECAL_POS) * float(bh)))
					var d_sid: int = 43 + int(floor(TileSynth2.u_rand(gx0 + i * 13, gy0 + i * 17, 0, TileSynth2.SALT_DECAL_COUNT) * 15.0))
					for _att in bw:
						if not expected_occupied.has(Vector2i(dlx, dly)):
							expected_occupied[Vector2i(dlx, dly)] = d_sid
							break
						dlx = (dlx + 1) % bw

				var actual_decal_tiles := 0
				for ty in bh:
					for tx in bw:
						var t_idx: int = ((ly0 + ty) * 32 + (lx0 + tx)) * 3
						var t_cls: int = w_tiles[t_idx]
						var t_var: int = w_tiles[t_idx + 1]
						var t_msk: int = w_tiles[t_idx + 2]
						if t_cls == TileSynth2.TILE_DOOR:
							push_error("(w) Decal lot at (%d,%d) contained unexpected TILE_DOOR" % [gx0, gy0])
							store.close()
							_cleanup()
							return false
						var is_ds_tile: bool = (tx == d_col and ty == bh - 1 and t_cls == 21 and t_var == 58 and t_msk == 0)
						if tx == d_col and ty == bh - 1 and has_doorstep != is_ds_tile:
							push_error("(w) Decal lot at (%d,%d) doorstep mismatch at (%d,%d): expected has_doorstep=%s, got (%d,%d,%d)" % [gx0, gy0, tx, ty, str(has_doorstep), t_cls, t_var, t_msk])
							store.close()
							_cleanup()
							return false
						if t_cls == 21:
							actual_decal_tiles += 1
							if not (tx == d_col and ty == bh - 1 and has_doorstep):
								var exp_msk: int = 1 if (t_var == 47 or t_var == 57) else 0
								if t_var < 43 or t_var > 57 or t_msk != exp_msk:
									push_error("(w) Decal tile at (%d,%d) invalid variant/mask: (%d,%d,%d)" % [tx, ty, t_cls, t_var, t_msk])
									store.close()
									_cleanup()
									return false
						else:
							var t_gx: int = w_cx * 32 + (lx0 + tx)
							var t_gy: int = w_cy * 32 + (31 - (ly0 + ty))
							var exp_cls: int = TileSynth2.TILE_TALL_GRASS if TileSynth2.u_rand(t_gx, t_gy, 0, TileSynth2.SALT_YARD_LOT_GRASS) < 0.60 else TileSynth2.TILE_GRASS
							if t_cls != exp_cls:
								push_error("(w) Decal lot ground tile at (%d,%d) expected cls=%d, got %d" % [tx, ty, exp_cls, t_cls])
								store.close()
								_cleanup()
								return false
				if actual_decal_tiles != expected_occupied.size():
					push_error("(w) Decal lot at (%d,%d) expected %d decal tiles, got %d" % [gx0, gy0, expected_occupied.size(), actual_decal_tiles])
					store.close()
					_cleanup()
					return false

	if w_total_footprints < 64 or w_state_c_lots < 3 or w_decal_lots < 3 or w_doorstep_only_lots < 1 or w_multi_no_doorstep_lots < 1:
		push_error("(w) Gone-path fixture coverage insufficient: footprints=%d state_c=%d decal_lots=%d doorstep_only=%d multi_no_doorstep=%d" % [
			w_total_footprints, w_state_c_lots, w_decal_lots, w_doorstep_only_lots, w_multi_no_doorstep_lots
		])
		store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (x) Item 33c (Decision 52, F69 a-b, §14.1.5): Big ruined blocks — Option B ("one section stands,
	#     the rest is rubble") and doors at the drawing's doorway columns 3 and 4.
	#     FALSIFYING: on Item 33's code, a 16x14 ruined block_l has 223 STAMP 42 tiles and a door in col 2.
	# -------------------------------------------------------------
	var x_area := _build_empty_area()
	# 1. 16x14 block_l at store units (2..10, 5..12) -> w_t=16, h_t=14 -> col0=8, row0=12 (lx0=4, ly0=8)
	var x_ring_16_14 := PackedVector2Array([
		Vector2(2.0, 5.0), Vector2(10.0, 5.0), Vector2(10.0, 12.0), Vector2(2.0, 12.0)
	])
	x_area[Vector2i.ZERO]["polys"] = [
		{"kind": "building", "subkind": "hospital", "geom_rings": [x_ring_16_14], "name": "Ruined Complex"}
	]
	x_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256))
	var x_res := TileSynth2.synthesize_cell(4, 4, x_area, 0)
	var x_tiles: PackedByteArray = x_res["tiles"]
	var x_stamps: Array = x_res.get("stamps", [])

	var x_lx0 := 4
	var x_ly0 := 8
	var x_stamp42_count := 0
	var x_door_cols_found: Array[int] = []
	var x_lot_decal_count := 0
	for ty in 14:
		for tx in 16:
			var t_idx: int = ((x_ly0 + ty) * 32 + (x_lx0 + tx)) * 3
			var t_cls: int = x_tiles[t_idx]
			var t_var: int = x_tiles[t_idx + 1]
			var t_msk: int = x_tiles[t_idx + 2]
			var in_sw_sec: bool = (tx < 8 and ty >= 7)
			if ty == 13 and t_cls == TileSynth2.TILE_DOOR and t_msk == 42:
				x_door_cols_found.append(tx)
			elif t_cls == 21 and t_var == 42 and t_msk == 1:
				x_stamp42_count += 1
			elif not in_sw_sec and t_cls == 21:
				if t_var < 43 or t_var > 57:
					push_error("(x) [falsifier] Ruined 16x14 block_l lot had unexpected decal variant %d at (%d,%d)" % [t_var, tx, ty])
					store.close()
					_cleanup()
					return false
				var exp_d_msk: int = 1 if (t_var == 47 or t_var == 57) else 0
				if t_msk != exp_d_msk:
					push_error("(x) [falsifier] Ruined 16x14 block_l decal %d had wrong mask %d at (%d,%d)" % [t_var, t_msk, tx, ty])
					store.close()
					_cleanup()
					return false
				x_lot_decal_count += 1

	if x_stamp42_count != 54 or x_door_cols_found != [3, 4] or x_lot_decal_count != 21 or x_stamps.size() != 22:
		push_error("(x) [falsifier] Ruined 16x14 block_l expected 54 STAMP-42 tiles, doors=[3, 4], 21 lot decals, and 22 stamps; got stamp42=%d doors=%s decals=%d stamps=%d" % [
			x_stamp42_count, str(x_door_cols_found), x_lot_decal_count, x_stamps.size()
		])
		store.close()
		_cleanup()
		return false

	var def_42: Dictionary = TileSynth2.get_stamp_def(42)
	if def_42.get("door", []) != [3, 6] or def_42.get("door_cols", []) != [3, 4]:
		push_error("(x) [falsifier] STAMP_TABLE[42] expected door=[3, 6] and door_cols=[3, 4], got %s" % str(def_42))
		store.close()
		_cleanup()
		return false

	# 2. A 6x5 ruined block_l keeps today's crop (W'=6, H'=5, L=0), with its one door in column 3
	var x65_area := _build_empty_area()
	# 3.0 x 2.5 store units -> 48x40 m = 1920 m^2; to force block_l (A >= 2000), use subkind "hospital" with 3.2 x 2.5 su = 2048 m^2 -> round(6.4)=6, round(5.0)=5
	var x_ring_6_5 := PackedVector2Array([
		Vector2(4.0, 6.0), Vector2(7.2, 6.0), Vector2(7.2, 8.5), Vector2(4.0, 8.5)
	])
	x65_area[Vector2i.ZERO]["polys"] = [
		{"kind": "building", "subkind": "hospital", "geom_rings": [x_ring_6_5], "name": "Small Clinic"}
	]
	x65_area["waypost_wm"] = Vector2(float(4 * 256) + 5000.0, float(4 * 256))
	var x65_res := TileSynth2.synthesize_cell(4, 4, x65_area, 0)
	var x65_tiles: PackedByteArray = x65_res["tiles"]
	var x65_stamps: Array = x65_res.get("stamps", [])
	if x65_stamps.size() != 1 or int(x65_stamps[0].get("w", 0)) != 6 or int(x65_stamps[0].get("h", 0)) != 5:
		push_error("(x.2) Ruined 6x5 block_l expected 1 stamp of 6x5, got %s" % str(x65_stamps))
		store.close()
		_cleanup()
		return false
	var x65_lx0: int = int(x65_stamps[0]["anchor_gx"]) - 4 * 32
	var x65_ly0: int = int(x65_stamps[0]["anchor_gy"]) - 4 * 32
	var x65_doors: Array[int] = []
	var x65_stamp42 := 0
	for ty in 5:
		for tx in 6:
			var t_idx: int = ((x65_ly0 + ty) * 32 + (x65_lx0 + tx)) * 3
			var t_cls: int = x65_tiles[t_idx]
			var t_var: int = x65_tiles[t_idx + 1]
			var t_msk: int = x65_tiles[t_idx + 2]
			if ty == 4 and tx == 3 and t_cls == TileSynth2.TILE_DOOR and t_msk == 42:
				x65_doors.append(tx)
			elif t_cls == 21 and t_var == 42 and t_msk == 1:
				x65_stamp42 += 1
	if x65_stamp42 != 29 or x65_doors != [3]:
		push_error("(x.2) Ruined 6x5 block_l expected 29 STAMP-42 tiles and door=[3], got stamp42=%d doors=%s" % [x65_stamp42, str(x65_doors)])
		store.close()
		_cleanup()
		return false



	# (a) Final Golden Hash Verification over cells (4,4), (4,5), (5,4), (5,5)
	# -------------------------------------------------------------
	var all_cells = [
		Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4), Vector2i(5, 5)
	]
	var cell_results = {
		Vector2i(4, 4): synth_4_4,
		Vector2i(4, 5): synth_4_5,
		Vector2i(5, 4): synth_5_4,
		Vector2i(5, 5): synth_5_5,
	}

	var combined := PackedByteArray()
	for c in all_cells:
		var res_c: Dictionary = cell_results[c]
		combined.append_array(res_c["tiles"])
		var signs: PackedStringArray = res_c["signs"]
		for s in signs:
			combined.append_array(s.to_utf8_buffer())

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(combined)
	var current_hash := ctx.finish().hex_encode()

	# Item 12 helper: dump fixture cells slice-2 buffers to user://test/fixture_cells.bin
	var dump_f := FileAccess.open("user://test/fixture_cells.bin", FileAccess.WRITE)
	if dump_f != null:
		for c in all_cells:
			var res_c: Dictionary = cell_results[c]
			dump_f.store_buffer(res_c["tiles"])
		dump_f.close()

	if GOLDEN_HASH.is_empty():
		print("FINAL SYNTH GOLDEN HASH: %s" % current_hash)
	elif current_hash != GOLDEN_HASH:
		push_error("Golden hash mismatch: expected %s, got %s" % [GOLDEN_HASH, current_hash])
		store.close()
		_cleanup()
		return false

	store.close()
	_cleanup()
	return true

## The thickness of a line: the best (longest) run of tiles of the given classes across it, over all the
## positions along it. For a horizontal line (across_rows false): positions are columns along_lo..along_hi,
## and the run scans rows scan_lo..scan_hi. For a vertical line (across_rows true): positions are rows
## along_lo..along_hi and the run scans columns scan_lo..scan_hi.
func _thickness(tiles: PackedByteArray, along_lo: int, along_hi: int, scan_lo: int, scan_hi: int, across_rows: bool, classes: Array) -> int:
	var best := 0
	for pos in range(along_lo, along_hi + 1):
		var run := 0
		for i in range(scan_lo, scan_hi + 1):
			var idx: int = (pos * 32 + i) if across_rows else (i * 32 + pos)
			if (tiles[idx * 3] as int) in classes:
				run += 1
				best = maxi(best, run)
			else:
				run = 0
	return best

func _build_area(store: MapStore, cx: int, cy: int) -> Dictionary:
	var area: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var offset := Vector2i(dx, dy)
			var nx := cx + dx
			var ny := cy + dy
			area[offset] = {
				"polys": store.get_features_poly(nx, ny),
				"lines": store.get_features_line(nx, ny),
				"places": store.get_place_nodes(nx, ny),
				"covered": store.covers_cell(nx, ny),
				"sea": store.get_cell_sea(nx, ny)
			}
	return area

func _build_empty_area() -> Dictionary:
	var area: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			area[Vector2i(dx, dy)] = {
				"polys": [],
				"lines": [],
				"places": [],
				"covered": true,
				"sea": 0
			}
	return area

func _cleanup() -> void:
	var base_dir := TEST_DB_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		return
	for suffix in ["", "-wal", "-shm", ".tmp", ".nodes.tmp", ".coords.tmp", ".rels.tmp"]:
		var p: String = TEST_DB_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
