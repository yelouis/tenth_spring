extends Node

# Legacy Fallback Import Test Suite
# Verifies that a legacy JSON world file is detected, rotated to .jsonbak,
# imported into real SQLite tables with correct field mapping (survivor_name -> trainer_name),
# verified for byte-for-byte backup preservation (SHA-256), and proven idempotent on subsequent boots.

const TEST_DB_PATH: String = "user://test/tenth_spring_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_test.db.tmp"

func _cleanup_test_files() -> void:
	var to_clean = [
		TEST_DB_PATH,
		TEST_DB_PATH + "-wal",
		TEST_DB_PATH + "-shm",
		TEST_TMP_PATH,
		TEST_DB_PATH + ".jsonbak",
		TEST_DB_PATH + ".jsonbak.tmp",
		TEST_DB_PATH + ".jsonbak.1",
		TEST_DB_PATH + ".jsonbak.2"
	]
	for p in to_clean:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup_test_files()

	var fixture_path = "res://tests/fixtures/legacy_fallback_world.json"
	if not FileAccess.file_exists(fixture_path):
		push_error("FAIL: Fixture missing: " + fixture_path)
		return false

	var fa_in = FileAccess.open(fixture_path, FileAccess.READ)
	var fixture_bytes = fa_in.get_buffer(fa_in.get_length())
	fa_in.close()
	var fixture_hash = FileAccess.get_sha256(fixture_path)

	# Ensure test directory exists and stage fixture at TEST_DB_PATH
	var base_dir = TEST_DB_PATH.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

	var fa_out = FileAccess.open(TEST_DB_PATH, FileAccess.WRITE)
	fa_out.store_buffer(fixture_bytes)
	fa_out.close()

	# 1. First boot: detects legacy JSON, rotates to .jsonbak, runs migrations, and imports
	DB.init_db()

	# Assert counts match fixture
	var cell_count = DB._rows("SELECT COUNT(*) as c FROM map_cell;")[0].get("c", 0)
	var place_count = DB._rows("SELECT COUNT(*) as c FROM place_node;")[0].get("c", 0)
	var visit_count = DB._rows("SELECT COUNT(*) as c FROM visit_log;")[0].get("c", 0)
	var peer_count = DB._rows("SELECT COUNT(*) as c FROM sync_peer;")[0].get("c", 0)

	if cell_count != 3 or place_count != 2 or visit_count != 5 or peer_count != 1:
		push_error("FAIL: Row counts do not match fixture (cells: %d, places: %d, visits: %d, peers: %d)" % [
			cell_count, place_count, visit_count, peer_count
		])
		_cleanup_test_files()
		return false

	# Assert field mappings
	var prof_rows = DB._rows("SELECT trainer_name FROM player_profile WHERE id = 1;")
	if prof_rows.is_empty() or prof_rows[0].get("trainer_name", "") != "Tester":
		push_error("FAIL: trainer_name mapping failed; expected 'Tester'")
		_cleanup_test_files()
		return false

	var ob = DB.get_place_node("place_1")
	if ob.get("name", "") != "O'Brien's Pub":
		push_error("FAIL: Place node O'Brien's Pub import failed")
		_cleanup_test_files()
		return false

	var c21 = DB.get_map_cell(10, 21)
	if c21.get("reveal_state", 0) != 2:
		push_error("FAIL: Map cell (10, 21) reveal_state 2 import failed")
		_cleanup_test_files()
		return false

	# Assert backup file is byte-identical to original fixture
	var bak_path = TEST_DB_PATH + ".jsonbak"
	if not FileAccess.file_exists(bak_path):
		push_error("FAIL: Expected rotated backup file at " + bak_path)
		_cleanup_test_files()
		return false

	var bak_hash = FileAccess.get_sha256(bak_path)
	if bak_hash != fixture_hash:
		push_error("FAIL: Rotated backup hash mismatch! Expected %s, got %s" % [fixture_hash, bak_hash])
		_cleanup_test_files()
		return false

	# 2. Second boot: should NOT re-import or duplicate rows
	DB.init_db()

	var cell_count2 = DB._rows("SELECT COUNT(*) as c FROM map_cell;")[0].get("c", 0)
	var place_count2 = DB._rows("SELECT COUNT(*) as c FROM place_node;")[0].get("c", 0)
	var visit_count2 = DB._rows("SELECT COUNT(*) as c FROM visit_log;")[0].get("c", 0)
	var peer_count2 = DB._rows("SELECT COUNT(*) as c FROM sync_peer;")[0].get("c", 0)

	if cell_count2 != 3 or place_count2 != 2 or visit_count2 != 5 or peer_count2 != 1:
		push_error("FAIL: Second boot duplicated rows!")
		_cleanup_test_files()
		return false

	var leg_rows = DB._rows("SELECT * FROM meta WHERE key = 'legacy_import';")
	if leg_rows.size() != 1:
		push_error("FAIL: Expected exactly 1 legacy_import meta row, got %d" % leg_rows.size())
		_cleanup_test_files()
		return false

	DB.close()
	_cleanup_test_files()

	# 3. Falsifying F31: failed legacy import closes DB, leaves backup intact, no meta row
	var fail_fixture_path = "res://tests/fixtures/legacy_fallback_duplicate_visit.json"
	if not FileAccess.file_exists(fail_fixture_path):
		push_error("FAIL: Duplicate visit fixture missing: " + fail_fixture_path)
		return false

	var fa_fail = FileAccess.open(fail_fixture_path, FileAccess.READ)
	var fail_bytes = fa_fail.get_buffer(fa_fail.get_length())
	fa_fail.close()
	var fail_hash = FileAccess.get_sha256(fail_fixture_path)

	var fa_out_fail = FileAccess.open(TEST_DB_PATH, FileAccess.WRITE)
	fa_out_fail.store_buffer(fail_bytes)
	fa_out_fail.close()

	DB.init_db()

	if DB._db != null:
		push_error("FAIL: DB._db should be null after failed legacy import")
		_cleanup_test_files()
		return false

	if DB.execute_query("SELECT 1;"):
		push_error("FAIL: DB.execute_query should return false when DB is closed")
		_cleanup_test_files()
		return false

	var fail_bak_path = TEST_DB_PATH + ".jsonbak"
	if not FileAccess.file_exists(fail_bak_path):
		push_error("FAIL: Expected rotated backup file at " + fail_bak_path)
		_cleanup_test_files()
		return false

	var fail_bak_hash = FileAccess.get_sha256(fail_bak_path)
	if fail_bak_hash != fail_hash:
		push_error("FAIL: Rotated backup hash mismatch! Expected %s, got %s" % [fail_hash, fail_bak_hash])
		_cleanup_test_files()
		return false

	var ind_db = ClassDB.instantiate("SQLite")
	ind_db.path = TEST_DB_PATH
	if not ind_db.open_db():
		push_error("FAIL: Could not open independent SQLite connection on disk")
		_cleanup_test_files()
		return false
	ind_db.query("SELECT value FROM meta WHERE key = 'legacy_import';")
	var meta_rows = ind_db.query_result
	ind_db.close_db()
	if not meta_rows.is_empty():
		push_error("FAIL: Expected no legacy_import meta row after failed import, got: " + str(meta_rows))
		_cleanup_test_files()
		return false

	DB.close()
	_cleanup_test_files()

	# 4. Precondition check: database with existing map_cell row blocks legacy import and closes DB
	DB.init_db()
	DB.upsert_map_cell(10, 20, 1)
	var pre_cells = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	if pre_cells.is_empty() or pre_cells[0].get("c", 0) != 1:
		push_error("FAIL: Failed to seed map_cell for precondition test")
		DB.close()
		_cleanup_test_files()
		return false
	DB.close()

	# Stage a .jsonbak while DB already has rows and meta has no legacy_import row
	var fa_bak_in = FileAccess.open(fixture_path, FileAccess.READ)
	var bak_bytes = fa_bak_in.get_buffer(fa_bak_in.get_length())
	fa_bak_in.close()

	var fa_bak_out = FileAccess.open(TEST_DB_PATH + ".jsonbak", FileAccess.WRITE)
	fa_bak_out.store_buffer(bak_bytes)
	fa_bak_out.close()

	DB.init_db()

	if DB._db != null:
		push_error("FAIL: DB._db should be null when legacy import is blocked by existing rows")
		_cleanup_test_files()
		return false

	var ind_db2 = ClassDB.instantiate("SQLite")
	ind_db2.path = TEST_DB_PATH
	if not ind_db2.open_db():
		push_error("FAIL: Could not open independent SQLite connection on disk for precondition check")
		_cleanup_test_files()
		return false
	ind_db2.query("SELECT COUNT(*) as c FROM map_cell;")
	var post_cell_count = ind_db2.query_result[0].get("c", 0) if not ind_db2.query_result.is_empty() else 0
	ind_db2.query("SELECT value FROM meta WHERE key = 'legacy_import';")
	var precond_meta_rows = ind_db2.query_result
	ind_db2.close_db()

	if post_cell_count != 1:
		push_error("FAIL: Precondition check failed; map_cell count changed: %d" % post_cell_count)
		_cleanup_test_files()
		return false

	if not precond_meta_rows.is_empty():
		push_error("FAIL: Precondition blocked import but legacy_import meta row exists")
		_cleanup_test_files()
		return false

	DB.close()
	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: db_legacy_import_test")
	return true
