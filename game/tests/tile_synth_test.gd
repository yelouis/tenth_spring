extends Node

# tile_synth_test.gd — Deterministic Tile Synthesis Verification Test
# Contract: docs/implementation_plan_world_generation.md §6 & docs/agent_execution_guide.md §6.6

const TileSynth := preload("res://world/tile_synth/tile_synth.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

const GOLDEN_SYNTH_HASH: String = "ae8769c0bab5fd6f3f5eb6797875a65195b1016ae5c01686cb72cbbc4b323c8e"
const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const TEST_DB_PATH: String = "user://test/map_data/tile_synth_test.db"

func run_test() -> bool:
	_cleanup()

	# 1. Convert synthetic neighborhood fixture to map store
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

	var cells: Array[Vector2i] = [
		Vector2i(4, 4),
		Vector2i(4, 5),
		Vector2i(5, 4),
		Vector2i(5, 5),
	]

	var combined_buffers := PackedByteArray()
	var cell_buffers: Dictionary = {}

	for c in cells:
		var features := {
			"polys": store.get_features_poly(c.x, c.y),
			"lines": store.get_features_line(c.x, c.y),
			"places": store.get_place_nodes(c.x, c.y)
		}
		var buf := TileSynth.synthesize_cell(c.x, c.y, features, 0)
		if buf.size() != 256:
			push_error("Cell (%d, %d) buffer size expected 256, got %d" % [c.x, c.y, buf.size()])
			store.close()
			_cleanup()
			return false
		cell_buffers[c] = buf
		combined_buffers.append_array(buf)

	# 2. Golden Hash Verification across the 4 cells
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(combined_buffers)
	var synth_hash := ctx.finish().hex_encode()

	if synth_hash != GOLDEN_SYNTH_HASH:
		push_error("Tile synth golden hash mismatch: expected %s, got %s" % [GOLDEN_SYNTH_HASH, synth_hash])
		store.close()
		_cleanup()
		return false

	# 3. Individual Cell Content Verification
	# Cell (4, 4): Building 1 (16 tiles), Road 1 (14 tiles), Terrain (226 tiles)
	var counts_4_4 := _count_tiles(cell_buffers[Vector2i(4, 4)])
	if counts_4_4.get(TileSynth.TILE_BUILDING, 0) != 16:
		push_error("Cell (4, 4) expected 16 building tiles, got %d" % counts_4_4.get(TileSynth.TILE_BUILDING, 0))
		store.close()
		_cleanup()
		return false
	if counts_4_4.get(TileSynth.TILE_ROAD, 0) != 14:
		push_error("Cell (4, 4) expected 14 road tiles, got %d" % counts_4_4.get(TileSynth.TILE_ROAD, 0))
		store.close()
		_cleanup()
		return false

	# Cell (5, 4): Building 2 (16 tiles), Park (56 tiles), Road 2 (14 tiles), Terrain (170 tiles)
	var counts_5_4 := _count_tiles(cell_buffers[Vector2i(5, 4)])
	if counts_5_4.get(TileSynth.TILE_BUILDING, 0) != 16:
		push_error("Cell (5, 4) expected 16 building tiles, got %d" % counts_5_4.get(TileSynth.TILE_BUILDING, 0))
		store.close()
		_cleanup()
		return false
	if counts_5_4.get(TileSynth.TILE_PARK, 0) != 56:
		push_error("Cell (5, 4) expected 56 park tiles, got %d" % counts_5_4.get(TileSynth.TILE_PARK, 0))
		store.close()
		_cleanup()
		return false

	# Cell (5, 5): Lake (128 tiles), Island/Terrain (113 tiles), Road 4 (15 tiles)
	var counts_5_5 := _count_tiles(cell_buffers[Vector2i(5, 5)])
	if counts_5_5.get(TileSynth.TILE_WATER, 0) != 128:
		push_error("Cell (5, 5) expected 128 water tiles, got %d" % counts_5_5.get(TileSynth.TILE_WATER, 0))
		store.close()
		_cleanup()
		return false
	if counts_5_5.get(TileSynth.TILE_ROAD, 0) != 15:
		push_error("Cell (5, 5) expected 15 road tiles, got %d" % counts_5_5.get(TileSynth.TILE_ROAD, 0))
		store.close()
		_cleanup()
		return false

	# 4. Minimum 2x2 building footprint test
	# A tiny sub-tile building (1x1m at local (2.5, 2.5)) must expand to >= 4 building tiles (2x2)
	var tiny_building := PackedVector2Array([
		Vector2(2.4, 2.4), Vector2(2.6, 2.4), Vector2(2.6, 2.6), Vector2(2.4, 2.6)
	])
	var tiny_features := {
		"polys": [{"kind": "building", "geom_rings": [tiny_building]}],
		"lines": []
	}
	var tiny_buf := TileSynth.synthesize_cell(0, 0, tiny_features, 0)
	var tiny_counts := _count_tiles(tiny_buf)
	if tiny_counts.get(TileSynth.TILE_BUILDING, 0) < 4:
		push_error("Tiny building failed minimum 2x2 footprint constraint: expected >= 4 tiles, got %d" % tiny_counts.get(TileSynth.TILE_BUILDING, 0))
		store.close()
		_cleanup()
		return false

	# 5. Determinism test
	var repeat_buf := TileSynth.synthesize_cell(4, 4, {
		"polys": store.get_features_poly(4, 4),
		"lines": store.get_features_line(4, 4)
	}, 0)
	if repeat_buf != cell_buffers[Vector2i(4, 4)]:
		push_error("Tile synthesis non-deterministic on identical input")
		store.close()
		_cleanup()
		return false

	# 6. Falsification test: moving a building vertex by 32 WM-m (2 tiles) changes the hash
	var polys_4_4: Array = store.get_features_poly(4, 4)
	var lines_4_4: Array = store.get_features_line(4, 4)
	store.close()
	_cleanup()

	var falsified_polys: Array = []
	for p in polys_4_4:
		var kind: String = p["kind"]
		var rings: Array[PackedVector2Array] = MapStore.unpack_rings(p["geom_rings"])
		if kind == "building" and not rings.is_empty():
			var outer := rings[0]
			# Move vertex 2 by 32 WM-m (2 tiles in cell-local coords: +2.0 in X)
			outer[2] = Vector2(outer[2].x + 2.0, outer[2].y)
			rings[0] = outer
		falsified_polys.append({
			"kind": kind,
			"geom_rings": rings
		})

	var falsified_buf := TileSynth.synthesize_cell(4, 4, {
		"polys": falsified_polys,
		"lines": lines_4_4
	}, 0)

	var falsified_combined := PackedByteArray()
	falsified_combined.append_array(falsified_buf)
	falsified_combined.append_array(cell_buffers[Vector2i(4, 5)])
	falsified_combined.append_array(cell_buffers[Vector2i(5, 4)])
	falsified_combined.append_array(cell_buffers[Vector2i(5, 5)])

	var f_ctx := HashingContext.new()
	f_ctx.start(HashingContext.HASH_SHA256)
	f_ctx.update(falsified_combined)
	var f_hash := f_ctx.finish().hex_encode()

	if f_hash == GOLDEN_SYNTH_HASH:
		push_error("Falsification failed: moving building vertex by 32 WM-m did NOT change the hash!")
		return false

	print("PASS: tile_synth_test (golden hash %s verified, falsification verified)" % GOLDEN_SYNTH_HASH)
	return true

func _count_tiles(buf: PackedByteArray) -> Dictionary:
	var counts := {}
	for b in buf:
		counts[b] = counts.get(b, 0) + 1
	return counts

func _cleanup() -> void:
	if FileAccess.file_exists(TEST_DB_PATH):
		DirAccess.remove_absolute(TEST_DB_PATH)
	if FileAccess.file_exists(TEST_DB_PATH + "-wal"):
		DirAccess.remove_absolute(TEST_DB_PATH + "-wal")
	if FileAccess.file_exists(TEST_DB_PATH + "-shm"):
		DirAccess.remove_absolute(TEST_DB_PATH + "-shm")
