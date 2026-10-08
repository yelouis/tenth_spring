extends Node

# Migration Runner Test Suite
# Verifies sequential migration execution, version tracking in meta table,
# idempotent re-run behavior, and atomic rollback on failed migration statements.

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

	# Seed a visit_log row to verify it remains unchanged across migrations
	DB.insert_visit_log({
		"seq": 1,
		"peer_id": "mig_peer",
		"place_id": null,
		"lat": 37.776,
		"lon": -122.420,
		"started_at": 1000,
		"dwell_seconds": 60,
		"kind": "visit"
	})

	# 1. Run migration version 2
	var mig_v2 = [
		{
			"version": 2,
			"statements": ["ALTER TABLE map_cell ADD COLUMN t INTEGER;"]
		}
	]
	DB._run_migrations(mig_v2)

	if DB.get_schema_version() != 2:
		push_error("FAIL: Expected schema_version 2 after migration, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false

	# Assert visit_log rows unchanged
	var v_rows = DB._rows("SELECT * FROM visit_log WHERE peer_id = 'mig_peer' AND seq = 1;")
	if v_rows.is_empty():
		push_error("FAIL: visit_log row lost after migration to version 2")
		_cleanup_test_files()
		return false

	# 2. Re-running migration v2 is a no-op
	DB._run_migrations(mig_v2)
	if DB.get_schema_version() != 2:
		push_error("FAIL: Expected schema_version to remain 2 on idempotent re-run")
		_cleanup_test_files()
		return false

	# 3. Failing migration statement rolls back and leaves version at 2
	var mig_fail = [
		{
			"version": 3,
			"statements": [
				"ALTER TABLE map_cell ADD COLUMN valid_col INTEGER;",
				"SYNTAX ERROR INVALID SQL STATEMENT;"
			]
		}
	]
	DB._run_migrations(mig_fail)
	# Reopen DB to verify disk state after failed migration closed handle
	DB.init_db()

	if DB.get_schema_version() != 2:
		push_error("FAIL: Expected schema_version to remain 2 after failed migration, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false

	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: db_migration_test")
	return true
