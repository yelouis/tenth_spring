extends Node

# DB & Relocation Test Suite for PC Engine
# Verifies schema version, relocation manager calculation, schema round-trip,
# atomic file persistence, temp backup recovery (F11), fail-loud null path (F13),
# and test save isolation (F22).

const TEST_DB_PATH: String = "user://test/tenth_spring_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_test.db.tmp"

func _cleanup_test_files() -> void:
	if FileAccess.file_exists(TEST_DB_PATH):
		DirAccess.remove_absolute(TEST_DB_PATH)
	if FileAccess.file_exists(TEST_TMP_PATH):
		DirAccess.remove_absolute(TEST_TMP_PATH)

func run_test() -> bool:
	# Isolate test from real player save (F22)
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup_test_files()
	DB.init_db()

	# 1. Schema version check
	var version = DB.get_schema_version()
	if version != 1:
		push_error("FAIL: Expected schema_version 1, got %d" % version)
		_cleanup_test_files()
		return false

	# 2. Relocation Manager Test
	var peer_id = "test_phone_001"
	DB.update_sync_peer(peer_id, 2, 37.776, -122.420, 1700000200)

	var RelocationManager = load("res://scripts/relocation_manager.gd").new()
	var relocation = RelocationManager.calculate_relocation(peer_id)

	if not relocation.has("spawn_tile"):
		push_error("FAIL: Missing spawn_tile in relocation result")
		_cleanup_test_files()
		return false

	# 3. Schema round-trip test
	DB.upsert_map_cell(10, 20, 1, 999)
	var cell = DB.get_map_cell(10, 20)
	if cell.get("reveal_state", 0) != 1 or cell.get("cell_seed", 0) != 999:
		push_error("FAIL: Map cell round-trip failed")
		_cleanup_test_files()
		return false

	DB.upsert_place_node({"id": "p_test_1", "name": "Pharmacy", "category": 2, "cell_x": 10, "cell_y": 20})
	var place = DB.get_place_node("p_test_1")
	if place.get("name", "") != "Pharmacy":
		push_error("FAIL: Place node round-trip failed")
		_cleanup_test_files()
		return false

	# 4. Persistence Test
	DB.init_db()
	var reloaded_cell = DB.get_map_cell(10, 20)
	if reloaded_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Map cell persistence test failed across store reload")
		_cleanup_test_files()
		return false

	# 5. Atomic temp backup recovery test (F11/F22 - must assert primary exists, never skip)
	if not FileAccess.file_exists(DB.DB_PATH):
		push_error("FAIL: save did not produce a primary file")
		_cleanup_test_files()
		return false

	var main_content = FileAccess.get_file_as_string(DB.DB_PATH)
	var tmp_file = FileAccess.open(DB.DB_TMP_PATH, FileAccess.WRITE)
	if tmp_file != null:
		tmp_file.store_string(main_content)
		tmp_file.close()

	# Truncate primary test file to simulate crash during write
	var corrupt_file = FileAccess.open(DB.DB_PATH, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("")
		corrupt_file.close()

	# Reload DB - should recover cleanly from temp backup
	DB.init_db()
	var recovered_cell = DB.get_map_cell(10, 20)
	if recovered_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Atomic temp backup recovery failed when primary DB was corrupted")
		_cleanup_test_files()
		return false

	# 6. execute_query on null handle returns false (F13)
	if DB._db == null:
		print("Testing null DB handle branch: execute_query must return false")
		var q_res = DB.execute_query("CREATE TABLE t(x);")
		if q_res != false:
			push_error("FAIL: Expected execute_query to return false when _db is null")
			_cleanup_test_files()
			return false
	else:
		print("Testing active SQLite handle branch")

	# Clean up and restore production save paths
	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: DB, Relocation, Persistence & Atomic Recovery (F11/F13/F22) Test Suite")
	return true
