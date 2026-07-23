extends Node

# Idempotent Sync Ingestion Test & Rollback Verification
# Verifies that replaying an identical sync batch produces zero state drift or duplicates,
# and that a mid-batch failure rolls back database state safely.

func run_test() -> bool:
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
		return false

	# Verify map cell reveal
	var cell = SyncServer.latlon_to_cell(37.775, -122.419)
	var map_cell = DB.get_map_cell(cell.x, cell.y)
	if map_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Expected cell to be revealed (known = 1)")
		return false

	# Second (Replayed) Ingestion - MUST BE A NO-OP
	var result2 = SyncServer.process_batch(peer_id, batch)
	if result2.get("appliedCount", 0) != 0:
		push_error("FAIL: Idempotency failed! Replayed batch applied %d rows (expected 0)" % result2.get("appliedCount", 0))
		return false

	# Third (Failed) Ingestion - MUST ROLL BACK SAFELY
	var failing_batch = {
		"rows": [
			{
				"seq": 3,
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
		},
		"simulateFailure": true
	}
	var fail_result = SyncServer.process_batch(peer_id, failing_batch)
	if fail_result.get("status", "") != "error":
		push_error("FAIL: Expected error status on simulated batch failure")
		return false

	var unrevealed_cell = SyncServer.latlon_to_cell(37.880, -122.500)
	var rolled_back_cell = DB.get_map_cell(unrevealed_cell.x, unrevealed_cell.y)
	if not rolled_back_cell.is_empty():
		push_error("FAIL: Rollback failed! Uncommitted map cell was persisted")
		return false

	print("PASS: Idempotent Sync Ingestion & Rollback Test")
	return true
