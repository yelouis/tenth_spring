extends Node

# tile_synth2_test.gd — Synthesis Part 1 Verification Test
# Contract: docs/implementation_plan_world_generation_slice2.md §3, §4, §8

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const TEST_DB_PATH: String = "user://test/map_data/tile_synth2_test.db"

# Stage 1 Golden hash — changes in Item 6 when buildings, doors and signs land
const STAGE1_GOLDEN_HASH: String = "d2d954efe5934433f74867ac43a3fb2eb5fbe160126d3d58a165647fca44d406"

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
	# Stage 1 Golden Hash Verification over cells (4,4), (4,5), (5,4), (5,5)
	# -------------------------------------------------------------
	var area_5_5 := _build_area(store, 5, 5)
	var synth_5_5 := TileSynth2.synthesize_cell(5, 5, area_5_5, 0)

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

	if STAGE1_GOLDEN_HASH.is_empty():
		# Print current hash so we can inspect and record it
		print("STAGE 1 SYNTH GOLDEN HASH: %s" % current_hash)
	elif current_hash != STAGE1_GOLDEN_HASH:
		push_error("Stage 1 golden hash mismatch: expected %s, got %s" % [STAGE1_GOLDEN_HASH, current_hash])
		store.close()
		_cleanup()
		return false

	store.close()
	_cleanup()
	return true

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

func _cleanup() -> void:
	var base_dir := TEST_DB_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		return
	for suffix in ["", "-wal", "-shm", ".tmp", ".nodes.tmp", ".coords.tmp", ".rels.tmp"]:
		var p: String = TEST_DB_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
