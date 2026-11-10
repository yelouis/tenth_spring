extends Node

# Idempotent Sync Ingestion Test & Rollback Verification (protocol v3)
# Verifies that replaying an identical sync batch produces zero state drift or duplicates,
# that an injected batch failure rolls back database state safely,
# and that test runs are strictly isolated from the real user save file (F22).

const PlacesPack := preload("res://world/places_pack.gd")

const TEST_DB_PATH: String = "user://test/tenth_spring_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_test.db.tmp"

func _cleanup_test_files() -> void:
	DB.close()
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
	PlacesPack.reset_active_pack_path()

func run_test() -> bool:
	# Isolate test from real player save (F22)
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup_test_files()
	PlacesPack.set_active_pack_path(PlacesPack.FIXTURE_PACK_PATH)
	DB.init_db()

	var peer_id = "test_phone_001"
	var batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "explore",
				"placeId": "city:fixture-city",
				"areaKey": "osm:n9104",
				"tsUtcMs": 1700000000000
			},
			{
				"seq": 2,
				"kind": "home",
				"placeId": "city:fixture-city",
				"tsUtcMs": 1700000200000
			}
		]
	}

	# First Ingestion
	var result1 = SyncServer.process_batch(peer_id, batch)
	if result1.get("appliedCount", 0) != 2:
		push_error("FAIL: Expected 2 applied rows on first run, got %d" % result1.get("appliedCount", 0))
		_cleanup_test_files()
		return false

	# Verify map cell reveal (Old Town cell (4, 4))
	var map_cell = DB.get_map_cell(4, 4)
	if map_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Expected cell (4, 4) to be revealed (known = 1)")
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

	# Third (Injected Failure) Ingestion - MUST REJECT SAFELY WITHOUT PARTIAL WRITES
	var failing_batch = {
		"rows": [
			{
				"seq": 3,
				"kind": "explore",
				"placeId": "site:fixture-park",
				"areaKey": "site:fixture-park",
				"tsUtcMs": 1700000300000
			},
			{
				"seq": -1, # Injected invalid sequence failure
				"kind": "explore",
				"placeId": "site:fixture-park",
				"areaKey": "site:fixture-park",
				"tsUtcMs": 1700000400000
			}
		]
	}
	var fail_result = SyncServer.process_batch(peer_id, failing_batch)
	if fail_result.get("status", "") != "error":
		push_error("FAIL: Expected error status on injected batch failure")
		_cleanup_test_files()
		return false

	var rolled_back_cell = DB.get_map_cell(10, 4)
	if not rolled_back_cell.is_empty():
		push_error("FAIL: Rollback failed! Uncommitted map cell (10, 4) was persisted")
		_cleanup_test_files()
		return false

	# Clean up and restore production save paths
	_cleanup_test_files()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: Idempotent Sync Ingestion & Rollback Test")
	return true
