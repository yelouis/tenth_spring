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
