extends Node

# region_import_test.gd — Region Import & Map Store Verification Test
# Contract: docs/implementation_plan_world_generation.md §5.2-§5.3 & docs/agent_execution_guide.md §6.5

const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

const GOLDEN_CANONICAL_HASH: String = "250ac3c91ebbcc72a352e2c99d8d7eaad5d4915dca32449def446ef8acd9571c"
const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const TEST_DB_PATH: String = "user://test/map_data/region_import_test.db"

func run_test() -> bool:
	_cleanup()

	# ---------------------------------------------------------
	# 1. Full Uninterrupted Conversion Test
	# ---------------------------------------------------------
	var conv := RegionConverter.new()
	var res := conv.convert(FIXTURE_PBF, TEST_DB_PATH)

	if not res.get("ok", false):
		push_error("Full conversion failed: %s" % res.get("error", "unknown"))
		_cleanup()
		return false

	var store := MapStore.new(TEST_DB_PATH)
	if not store.open_store(false):
		push_error("Failed to open converted store: %s" % store.last_error)
		_cleanup()
		return false

	# Verify counts
	var poly_count: int = int(store._rows("SELECT count(*) as c FROM features_poly;")[0]["c"])
	var line_count: int = int(store._rows("SELECT count(*) as c FROM features_line;")[0]["c"])
	var node_count: int = int(store._rows("SELECT count(*) as c FROM place_nodes;")[0]["c"])

	if poly_count != 5:
		push_error("Expected 5 features_poly, got %d" % poly_count)
		store.close()
		_cleanup()
		return false

	if line_count != 4:
		push_error("Expected 4 features_line, got %d" % line_count)
		store.close()
		_cleanup()
		return false

	if node_count != 2:
		push_error("Expected 2 place_nodes, got %d" % node_count)
		store.close()
		_cleanup()
		return false

	# Verify kinds
	var poly_kinds := store._rows("SELECT DISTINCT kind FROM features_poly ORDER BY kind;")
	var kinds_list: Array[String] = []
	for r in poly_kinds:
		kinds_list.append(r["kind"])
	if kinds_list != ["building", "park", "water"]:
		push_error("Unexpected polygon kinds: %s" % str(kinds_list))
		store.close()
		_cleanup()
		return false

	# Verify multipolygon lake has 2 rings (outer lake + inner island)
	var lake_rows := store._rows("SELECT geom_rings FROM features_poly WHERE kind = 'water';")
	if lake_rows.is_empty():
		push_error("Water polygon missing")
		store.close()
		_cleanup()
		return false
	var lake_rings := MapStore.unpack_rings(lake_rows[0]["geom_rings"])
	if lake_rings.size() != 2:
		push_error("Expected 2 rings for multipolygon lake (outer + inner), got %d" % lake_rings.size())
		store.close()
		_cleanup()
		return false

	# Verify golden canonical dump hash
	var canonical_hash := store.canonical_dump_sha256()
	if canonical_hash != GOLDEN_CANONICAL_HASH:
		push_error("Golden canonical hash mismatch: expected %s, got %s" % [GOLDEN_CANONICAL_HASH, canonical_hash])
		store.close()
		_cleanup()
		return false

	store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 2. Checkpoint Resume Test: Stop after Pass 1 -> Resume
	# ---------------------------------------------------------
	var conv_pass1 := RegionConverter.new()
	conv_pass1.stop_after_pass = 1
	var res_p1 := conv_pass1.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_p1.get("ok", false) or res_p1.get("stopped_after_pass", 0) != 1:
		push_error("Stop after pass 1 failed: %s" % str(res_p1))
		_cleanup()
		return false

	var conv_resume1 := RegionConverter.new()
	var res_r1 := conv_resume1.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_r1.get("ok", false) or res_r1.get("canonical_hash", "") != GOLDEN_CANONICAL_HASH:
		push_error("Resume after pass 1 failed or hash mismatch: %s" % str(res_r1))
		_cleanup()
		return false

	_cleanup()

	# ---------------------------------------------------------
	# 3. Checkpoint Resume Test: Stop after Pass 2 -> Resume
	# ---------------------------------------------------------
	var conv_pass2 := RegionConverter.new()
	conv_pass2.stop_after_pass = 2
	var res_p2 := conv_pass2.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_p2.get("ok", false) or res_p2.get("stopped_after_pass", 0) != 2:
		push_error("Stop after pass 2 failed: %s" % str(res_p2))
		_cleanup()
		return false

	var conv_resume2 := RegionConverter.new()
	var res_r2 := conv_resume2.convert(FIXTURE_PBF, TEST_DB_PATH)
	if not res_r2.get("ok", false) or res_r2.get("canonical_hash", "") != GOLDEN_CANONICAL_HASH:
		push_error("Resume after pass 2 failed or hash mismatch: %s" % str(res_r2))
		_cleanup()
		return false

	_cleanup()

	# ---------------------------------------------------------
	# 4. Equivalence Test (falsifying): Clip covering full fixture
	# Canonical dump hash MUST be identical to unclipped run.
	# ---------------------------------------------------------
	var full_clip := Rect2(1000.0, 1000.0, 600.0, 600.0)
	var conv_eq := RegionConverter.new()
	var res_eq := conv_eq.convert(FIXTURE_PBF, TEST_DB_PATH, full_clip)
	if not res_eq.get("ok", false):
		push_error("Full clip conversion failed: %s" % res_eq.get("error", "unknown"))
		_cleanup()
		return false

	var eq_store := MapStore.new(TEST_DB_PATH)
	if not eq_store.open_store(false):
		push_error("Failed to open eq store: %s" % eq_store.last_error)
		_cleanup()
		return false

	var eq_hash := eq_store.canonical_dump_sha256()
	if eq_hash != GOLDEN_CANONICAL_HASH:
		push_error("Clip equivalence hash mismatch: expected %s, got %s" % [GOLDEN_CANONICAL_HASH, eq_hash])
		eq_store.close()
		_cleanup()
		return false

	if eq_store.get_state("clip") != "1":
		push_error("Expected clip state '1', got '%s'" % eq_store.get_state("clip"))
		eq_store.close()
		_cleanup()
		return false

	var eq_cov: Variant = eq_store.get_coverage_box()
	if eq_cov == null:
		push_error("Expected non-null coverage box in clipped store")
		eq_store.close()
		_cleanup()
		return false

	eq_store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 5. Partial Clip Test: West half
	# East-only building absent, crossing road present and whole, lake present
	# ---------------------------------------------------------
	var west_clip := Rect2(1000.0, 1000.0, 350.0, 600.0)
	var conv_west := RegionConverter.new()
	var res_west := conv_west.convert(FIXTURE_PBF, TEST_DB_PATH, west_clip)
	if not res_west.get("ok", false):
		push_error("West clip conversion failed: %s" % res_west.get("error", "unknown"))
		_cleanup()
		return false

	var west_store := MapStore.new(TEST_DB_PATH)
	if not west_store.open_store(false):
		push_error("Failed to open west store: %s" % west_store.last_error)
		_cleanup()
		return false

	# East-only building (Maple House in cell (5, 4)) must be absent
	var b2_rows := west_store._rows("SELECT count(*) as c FROM features_poly WHERE cell_x = 5 AND cell_y = 4 AND kind = 'building';")
	if int(b2_rows[0]["c"]) != 0:
		push_error("Partial clip failed: east-only building in cell (5, 4) should be absent")
		west_store.close()
		_cleanup()
		return false

	# West building (City Hall in cell (4, 4)) must be present
	var b1_rows := west_store._rows("SELECT count(*) as c FROM features_poly WHERE cell_x = 4 AND cell_y = 4 AND kind = 'building';")
	if int(b1_rows[0]["c"]) != 1:
		push_error("Partial clip failed: west building in cell (4, 4) should be present")
		west_store.close()
		_cleanup()
		return false

	# Crossing road (Lakeside Trail in cell (5, 5)) has first node inside (x=1296) and rest outside;
	# must be present and whole (all 4 vertices preserved)
	var r4_rows := west_store._rows("SELECT geom_pts FROM features_line WHERE cell_x = 5 AND cell_y = 5 AND kind = 'path';")
	if r4_rows.is_empty():
		push_error("Partial clip failed: crossing road in cell (5, 5) should be present")
		west_store.close()
		_cleanup()
		return false
	var r4_pts := MapStore.unpack_pts(r4_rows[0]["geom_pts"])
	if r4_pts.size() != 4:
		push_error("Partial clip failed: crossing road should be whole (4 pts), got %d" % r4_pts.size())
		west_store.close()
		_cleanup()
		return false

	# Multipolygon lake has outer ring node inside (x=1312) and inner ring outside;
	# lake relation must be kept with both rings
	var lake_rows_w := west_store._rows("SELECT geom_rings FROM features_poly WHERE kind = 'water';")
	if lake_rows_w.is_empty():
		push_error("Partial clip failed: lake should be present when one member way has node inside")
		west_store.close()
		_cleanup()
		return false
	var lake_rings_w := MapStore.unpack_rings(lake_rows_w[0]["geom_rings"])
	if lake_rings_w.size() != 2:
		push_error("Partial clip failed: lake should have both rings (outer + inner), got %d" % lake_rings_w.size())
		west_store.close()
		_cleanup()
		return false

	west_store.close()
	_cleanup()

	# When clip boundary is strictly west of cell 5 (x < 1280), lake has no nodes inside and must be absent
	var strict_west_clip := Rect2(1000.0, 1000.0, 270.0, 600.0)
	var conv_sw := RegionConverter.new()
	var res_sw := conv_sw.convert(FIXTURE_PBF, TEST_DB_PATH, strict_west_clip)
	if not res_sw.get("ok", false):
		push_error("Strict west clip failed: %s" % res_sw.get("error", "unknown"))
		_cleanup()
		return false

	var sw_store := MapStore.new(TEST_DB_PATH)
	if not sw_store.open_store(false):
		push_error("Failed to open strict west store: %s" % sw_store.last_error)
		_cleanup()
		return false

	var sw_lake := sw_store._rows("SELECT count(*) as c FROM features_poly WHERE kind = 'water';")
	if int(sw_lake[0]["c"]) != 0:
		push_error("Strict west clip failed: lake should be absent when no member nodes inside")
		sw_store.close()
		_cleanup()
		return false

	sw_store.close()
	_cleanup()

	# ---------------------------------------------------------
	# 6. Empty Clip Test: Rectangle in empty ocean
	# 0 features, coverage recorded, exits 0
	# ---------------------------------------------------------
	var ocean_clip := Rect2(0.0, 0.0, 100.0, 100.0)
	var conv_ocean := RegionConverter.new()
	var res_ocean := conv_ocean.convert(FIXTURE_PBF, TEST_DB_PATH, ocean_clip)
	if not res_ocean.get("ok", false):
		push_error("Empty ocean clip conversion failed: %s" % res_ocean.get("error", "unknown"))
		_cleanup()
		return false

	var ocean_store := MapStore.new(TEST_DB_PATH)
	if not ocean_store.open_store(false):
		push_error("Failed to open ocean store: %s" % ocean_store.last_error)
		_cleanup()
		return false

	var o_poly: int = int(ocean_store._rows("SELECT count(*) as c FROM features_poly;")[0]["c"])
	var o_line: int = int(ocean_store._rows("SELECT count(*) as c FROM features_line;")[0]["c"])
	var o_node: int = int(ocean_store._rows("SELECT count(*) as c FROM place_nodes;")[0]["c"])
	if o_poly != 0 or o_line != 0 or o_node != 0:
		push_error("Empty ocean clip expected 0 features, got %d poly, %d line, %d nodes" % [o_poly, o_line, o_node])
		ocean_store.close()
		_cleanup()
		return false

	if ocean_store.get_state("clip") != "1":
		push_error("Empty ocean clip expected clip='1', got '%s'" % ocean_store.get_state("clip"))
		ocean_store.close()
		_cleanup()
		return false

	if ocean_store.get_coverage_box() == null:
		push_error("Empty ocean clip expected recorded coverage box, got null")
		ocean_store.close()
		_cleanup()
		return false

	ocean_store.close()
	_cleanup()
	return true

func _cleanup() -> void:
	var base_dir := TEST_DB_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		return
	var siblings = [
		TEST_DB_PATH,
		TEST_DB_PATH + "-wal",
		TEST_DB_PATH + "-shm",
		TEST_DB_PATH + ".nodes.tmp",
		TEST_DB_PATH + ".coords.tmp",
		TEST_DB_PATH + ".rels.tmp"
	]
	for p in siblings:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
