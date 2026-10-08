extends Node

# DB Test Suite for PC Engine (Real SQLite Engine)
# Verifies ClassDB SQLite existence, schema version 1, sqlite_master 9 tables,
# disk persistence across restart and independent connection, duplicate rejection with UNIQUE,
# upsert semantics (reveal_state MAX, unchanged first_revealed_at, visit_count increment, last_applied_seq MAX),
# SQL injection immunity with bound parameters (quotes, escapes, double float precision),
# transaction rollback persistence isolation, and execute_query failure on closed handle.

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
	DB.init_db()

	# 1. Verify ClassDB SQLite class exists and schema version
	if not ClassDB.class_exists("SQLite"):
		push_error("FAIL: ClassDB SQLite does not exist")
		_cleanup_test_files()
		return false

	var version = DB.get_schema_version()
	if version != 1:
		push_error("FAIL: Expected schema_version 1, got %d" % version)
		_cleanup_test_files()
		return false

	# 2. Verify sqlite_master lists exactly the nine v1 tables
	var master_rows = DB._rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
	var table_names = []
	for r in master_rows:
		table_names.append(r.get("name", ""))
	table_names.sort()
	var expected_tables = ["base_state", "map_cell", "meta", "osm_cache", "place_node", "player_profile", "sync_peer", "visit_log", "world_clock"]
	expected_tables.sort()
	if table_names != expected_tables:
		push_error("FAIL: Tables in sqlite_master do not match expected 9 tables: " + str(table_names))
		_cleanup_test_files()
		return false

	# 3. Disk persistence: write cell -> close -> init -> read; also check with independent SQLite instance
	DB.upsert_map_cell(5, 7, 1, 42)
	DB.close()
	DB.init_db()
	var cell = DB.get_map_cell(5, 7)
	if cell.get("reveal_state", 0) != 1 or cell.get("cell_seed", 0) != 42:
		push_error("FAIL: Map cell not preserved across restart")
		_cleanup_test_files()
		return false

	var db2 = ClassDB.instantiate("SQLite")
	db2.path = TEST_DB_PATH
	if not db2.open_db():
		push_error("FAIL: Could not open second independent SQLite instance on disk")
		_cleanup_test_files()
		return false
	db2.query_with_bindings("SELECT cell_x, cell_y, reveal_state, cell_seed FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [5, 7])
	var db2_rows = db2.query_result
	db2.close_db()
	if db2_rows.is_empty() or db2_rows[0].get("reveal_state", 0) != 1:
		push_error("FAIL: Independent SQLite instance could not find row on disk")
		_cleanup_test_files()
		return false

	# 4. Engine rejects duplicate with UNIQUE constraint error
	var ok1 = DB._db.query_with_bindings("INSERT INTO visit_log (seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?);", [10, "dup_peer", null, 0.0, 0.0, 100, 0, "visit"])
	if not ok1:
		push_error("FAIL: First raw visit_log insert failed")
		_cleanup_test_files()
		return false
	var ok2 = DB._db.query_with_bindings("INSERT INTO visit_log (seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?);", [10, "dup_peer", null, 0.0, 0.0, 100, 0, "visit"])
	if ok2:
		push_error("FAIL: Second raw visit_log insert succeeded unexpectedly on duplicate PK")
		_cleanup_test_files()
		return false
	if not DB._db.error_message.to_upper().contains("UNIQUE"):
		push_error("FAIL: Expected error_message to contain UNIQUE, got: " + DB._db.error_message)
		_cleanup_test_files()
		return false

	# 5. Upsert semantics:
	# 5a. reveal 2 then 1 -> stays 2; first_revealed_at unchanged on second upsert
	DB.upsert_map_cell(20, 30, 2, 100)
	var cell_u1 = DB.get_map_cell(20, 30)
	var first_rev = cell_u1.get("first_revealed_at", 0)
	DB.upsert_map_cell(20, 30, 1, 100)
	var cell_u2 = DB.get_map_cell(20, 30)
	if cell_u2.get("reveal_state", 0) != 2:
		push_error("FAIL: Upsert downgrade! reveal_state did not stay 2")
		_cleanup_test_files()
		return false
	if cell_u2.get("first_revealed_at", 0) != first_rev:
		push_error("FAIL: first_revealed_at changed on second upsert")
		_cleanup_test_files()
		return false

	# 5b. place_node visit_count 1 -> 2
	DB.upsert_place_node({"id": "node_vc", "name": "Store", "visit_count": 1})
	var p1 = DB.get_place_node("node_vc")
	if p1.get("visit_count", 0) != 1:
		push_error("FAIL: Expected initial visit_count 1")
		_cleanup_test_files()
		return false
	DB.upsert_place_node({"id": "node_vc", "name": "Store", "visit_count": 1})
	var p2 = DB.get_place_node("node_vc")
	if p2.get("visit_count", 0) != 2:
		push_error("FAIL: Expected visit_count to add up to 2, got %d" % p2.get("visit_count", 0))
		_cleanup_test_files()
		return false

	# 5c. sync_peer last_applied_seq 5 then 3 -> stays 5
	DB.update_sync_peer("seq_peer", 5, 0.0, 0.0, 100)
	var sp1 = DB.get_sync_peer("seq_peer")
	if sp1.get("last_applied_seq", 0) != 5:
		push_error("FAIL: Expected initial last_applied_seq 5")
		_cleanup_test_files()
		return false
	DB.update_sync_peer("seq_peer", 3, 0.0, 0.0, 100)
	var sp2 = DB.get_sync_peer("seq_peer")
	if sp2.get("last_applied_seq", 0) != 5:
		push_error("FAIL: last_applied_seq went backwards from 5 to 3!")
		_cleanup_test_files()
		return false

	# 6. SQL Injection immunity & precision
	var inj_kind = "visit'); DROP TABLE map_cell;--"
	DB.insert_visit_log({"seq": 50, "peer_id": "inj_peer", "place_id": null, "lat": 0.0, "lon": 0.0, "started_at": 100, "dwell_seconds": 0, "kind": inj_kind})
	var rows_inj = DB._rows("SELECT kind FROM visit_log WHERE peer_id = 'inj_peer' AND seq = 50;")
	if rows_inj.is_empty() or rows_inj[0].get("kind", "") != inj_kind:
		push_error("FAIL: Injection kind was not stored literally")
		_cleanup_test_files()
		return false
	var chk_mc = DB._rows("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'map_cell';")
	if chk_mc.is_empty():
		push_error("FAIL: SQL injection dropped table map_cell!")
		_cleanup_test_files()
		return false

	DB.upsert_place_node({"id": "obrien", "name": "O'Brien's Pub"})
	var ob = DB.get_place_node("obrien")
	if ob.get("name", "") != "O'Brien's Pub":
		push_error("FAIL: O'Brien's Pub name failed to round-trip")
		_cleanup_test_files()
		return false

	DB.insert_visit_log({"seq": 60, "peer_id": "float_peer", "lat": 37.123456789, "lon": -122.123456789, "started_at": 100, "dwell_seconds": 0, "kind": "visit"})
	var rows_flt = DB._rows("SELECT lat, lon FROM visit_log WHERE peer_id = 'float_peer' AND seq = 60;")
	if rows_flt.is_empty():
		push_error("FAIL: float visit_log row missing")
		_cleanup_test_files()
		return false
	var act_lat = float(rows_flt[0].get("lat", 0.0))
	if abs(act_lat - 37.123456789) > 1e-9:
		push_error("FAIL: lat truncation! Expected 37.123456789, got %f" % act_lat)
		_cleanup_test_files()
		return false

	# 7. Rollback: begin -> insert -> rollback -> close/init -> row absent
	DB.begin_transaction()
	DB.insert_visit_log({"seq": 99, "peer_id": "rb_peer", "lat": 0.0, "lon": 0.0, "started_at": 100, "dwell_seconds": 0, "kind": "visit"})
	DB.rollback_transaction()
	DB.close()
	DB.init_db()
	if DB.is_visit_logged("rb_peer", 99):
		push_error("FAIL: Rolled back visit_log row was persisted!")
		_cleanup_test_files()
		return false

	# 8. execute_query after close returns false
	DB.close()
	if DB.execute_query("SELECT 1;"):
		push_error("FAIL: execute_query succeeded after close()")
		_cleanup_test_files()
		return false

	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: db_test")
	return true
