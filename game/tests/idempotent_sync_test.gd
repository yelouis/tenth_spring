extends Node

# Idempotent Sync Ingestion Test
# Verifies that replaying an identical sync batch produces zero state drift or duplicates.

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

	print("PASS: Idempotent Sync Ingestion Test")
	return true
