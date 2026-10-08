extends Node

# Idempotent Sync Ingestion Test & Rollback Verification
# Verifies that replaying an identical sync batch produces zero state drift or duplicates,
# that an injected batch failure rolls back database state safely,
# and that test runs are strictly isolated from the real user save file (F22).

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
	# Isolate test from real player save (F22)
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup_test_files()
	DB.init_db()

	var peer_id = "test_phone_001"
	var batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "visit",
				"lat": 37.775,
				"lon": -122.419,
				"startedAt": 1700000000,
				"dwellSeconds": 180
			},
			{
				"seq": 2,
				"kind": "corridor",
				"lat": 37.776,
				"lon": -122.420,
				"startedAt": 1700000200
			}
		],
		"bodyFix": {
			"lat": 37.776,
			"lon": -122.420,
			"tsUtcMs": 1700000200
		}
	}

	# First Ingestion
	var result1 = SyncServer.process_batch(peer_id, batch)
	if result1.get("appliedCount", 0) != 2:
		push_error("FAIL: Expected 2 applied rows on first run, got %d" % result1.get("appliedCount", 0))
		_cleanup_test_files()
		return false

	# Verify map cell reveal
	var cell = SyncServer.latlon_to_cell(37.775, -122.419)
	var map_cell = DB.get_map_cell(cell.x, cell.y)
	if map_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Expected cell to be revealed (known = 1)")
		_cleanup_test_files()
		return false

	# Restart simulation: close DB and re-init to ensure persisted state on disk
	DB.close()
	DB.init_db()

	# Second (Replayed) Ingestion - MUST BE A NO-OP
	var result2 = SyncServer.process_batch(peer_id, batch)
	if result2.get("appliedCount", 0) != 0:
		push_error("FAIL: Idempotency failed! Replayed batch applied %d rows (expected 0)" % result2.get("appliedCount", 0))
		_cleanup_test_files()
		return false

	# Third (Injected Failure) Ingestion - MUST ROLL BACK SAFELY
	var failing_batch = {
		"rows": [
			{
				"seq": -1, # Injected invalid sequence failure
				"kind": "visit",
				"lat": 37.880,
				"lon": -122.500,
				"startedAt": 1700000300,
				"dwellSeconds": 180
			}
		],
		"bodyFix": {
			"lat": 37.880,
			"lon": -122.500,
			"tsUtcMs": 1700000300
		}
	}
	var fail_result = SyncServer.process_batch(peer_id, failing_batch)
	if fail_result.get("status", "") != "error":
		push_error("FAIL: Expected error status on injected batch failure")
		_cleanup_test_files()
		return false

	var unrevealed_cell = SyncServer.latlon_to_cell(37.880, -122.500)
	var rolled_back_cell = DB.get_map_cell(unrevealed_cell.x, unrevealed_cell.y)
	if not rolled_back_cell.is_empty():
		push_error("FAIL: Rollback failed! Uncommitted map cell was persisted")
		_cleanup_test_files()
		return false

	# Clean up and restore production save paths
	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: Idempotent Sync Ingestion & Rollback Test")
	return true
