extends Node

# Corridor Reveal Radius Test (F37)
# Verifies that corridor rows reveal every 256m cell within corridorRevealMeters (60m),
# while visit rows remain unchanged (only primary cell).
# Contract: docs/implementation_plan_world_generation.md §4 & docs/agent_execution_guide.md §6.3

const Grid := preload("res://world/grid.gd")

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
	# -------------------------------------------------------------
	# 1. Pure Grid Geometry Tests: 2 / 4 / 1 cells
	# -------------------------------------------------------------
	# Cell (4, 4) bounds in Web-Mercator: x in [1024, 1280], y in [1024, 1280]
	# Center point: (1152, 1152) -> > 60m from all 4 boundaries
	var center_latlon := Grid.wm_to_latlon(Vector2(1152.0, 1152.0))
	var c_cells := Grid.cells_within_ground_radius(center_latlon.x, center_latlon.y, 60.0)
	if c_cells.size() != 1 or c_cells[0] != Vector2i(4, 4):
		push_error("FAIL: Expected 1 cell for center point, got %s" % str(c_cells))
		return false

	# 100m from cell boundary (plan §4.3)
	var p_100_latlon := Grid.wm_to_latlon(Vector2(1024.0 + 100.0, 1024.0 + 100.0))
	var c_100 := Grid.cells_within_ground_radius(p_100_latlon.x, p_100_latlon.y, 60.0)
	if c_100.size() != 1 or c_100[0] != Vector2i(4, 4):
		push_error("FAIL: Expected 1 cell for 100m from boundary point, got %s" % str(c_100))
		return false

	# Edge point: 10m from East boundary (x = 1270, y = 1152) -> 2 cells: (4, 4) and (5, 4)
	var edge_latlon := Grid.wm_to_latlon(Vector2(1270.0, 1152.0))
	var e_cells := Grid.cells_within_ground_radius(edge_latlon.x, edge_latlon.y, 60.0)
	if e_cells.size() != 2:
		push_error("FAIL: Expected 2 cells for edge point, got %s" % str(e_cells))
		return false
	if not e_cells.has(Vector2i(4, 4)) or not e_cells.has(Vector2i(5, 4)):
		push_error("FAIL: Expected cells (4, 4) and (5, 4) for edge point, got %s" % str(e_cells))
		return false

	# Corner point: 10m from East and North boundaries (x = 1270, y = 1270) -> 4 cells
	var corner_latlon := Grid.wm_to_latlon(Vector2(1270.0, 1270.0))
	var cr_cells := Grid.cells_within_ground_radius(corner_latlon.x, corner_latlon.y, 60.0)
	if cr_cells.size() != 4:
		push_error("FAIL: Expected 4 cells for corner point, got %s" % str(cr_cells))
		return false
	var expected_4 = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]
	for exp_c in expected_4:
		if not cr_cells.has(exp_c):
			push_error("FAIL: Missing expected cell %s for corner point: %s" % [str(exp_c), str(cr_cells)])
			return false

	# -------------------------------------------------------------
	# 2. Database Ingestion & Falsification Tests via SyncServer
	# -------------------------------------------------------------
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	# Case A: Falsification - Edge-adjacent corridor row writes 2 map_cell rows (was 1), replay changes nothing
	_cleanup_test_files()
	DB.init_db()

	var peer_id := "test_corridor_peer"
	var edge_batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "corridor",
				"lat": edge_latlon.x,
				"lon": edge_latlon.y,
				"startedAt": 1700000000
			}
		]
	}

	var res_edge = SyncServer.process_batch(peer_id, edge_batch)
	if res_edge.get("appliedCount", 0) != 1:
		push_error("FAIL: Expected appliedCount=1 for edge batch, got %s" % str(res_edge))
		_cleanup_test_files()
		return false

	var cell_count_rows = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	var cell_count = int(cell_count_rows[0].get("c", 0))
	if cell_count != 2:
		push_error("FAIL: Falsification check failed: Expected 2 map_cell rows for edge-adjacent corridor, got %d" % cell_count)
		_cleanup_test_files()
		return false

	var c44 = DB.get_map_cell(4, 4)
	var c54 = DB.get_map_cell(5, 4)
	if c44.get("reveal_state", 0) != 1 or c54.get("reveal_state", 0) != 1:
		push_error("FAIL: Expected both cells to have reveal_state=1, got c44=%s c54=%s" % [str(c44), str(c54)])
		_cleanup_test_files()
		return false

	# Replay test: re-running identical batch must change nothing
	var res_replay = SyncServer.process_batch(peer_id, edge_batch)
	if res_replay.get("appliedCount", 0) != 0:
		push_error("FAIL: Idempotency failed: Replay applied %s rows (expected 0)" % str(res_replay.get("appliedCount")))
		_cleanup_test_files()
		return false

	var replay_count_rows = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	var replay_count = int(replay_count_rows[0].get("c", 0))
	if replay_count != 2:
		push_error("FAIL: Replay altered map_cell row count from 2 to %d" % replay_count)
		_cleanup_test_files()
		return false

	# Case B: Corner-adjacent corridor row writes 4 map_cell rows
	_cleanup_test_files()
	DB.init_db()

	var corner_batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "corridor",
				"lat": corner_latlon.x,
				"lon": corner_latlon.y,
				"startedAt": 1700000000
			}
		]
	}

	var res_corner = SyncServer.process_batch(peer_id, corner_batch)
	if res_corner.get("appliedCount", 0) != 1:
		push_error("FAIL: Expected appliedCount=1 for corner batch, got %s" % str(res_corner))
		_cleanup_test_files()
		return false

	var corner_count_rows = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	var corner_count = int(corner_count_rows[0].get("c", 0))
	if corner_count != 4:
		push_error("FAIL: Expected 4 map_cell rows for corner corridor, got %d" % corner_count)
		_cleanup_test_files()
		return false

	for exp_c in expected_4:
		var mc = DB.get_map_cell(exp_c.x, exp_c.y)
		if mc.get("reveal_state", 0) != 1:
			push_error("FAIL: Expected cell %s to have reveal_state=1, got %s" % [str(exp_c), str(mc)])
			_cleanup_test_files()
			return false

	# Case C: Center corridor row writes 1 map_cell row
	_cleanup_test_files()
	DB.init_db()

	var center_batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "corridor",
				"lat": center_latlon.x,
				"lon": center_latlon.y,
				"startedAt": 1700000000
			}
		]
	}

	var res_center = SyncServer.process_batch(peer_id, center_batch)
	if res_center.get("appliedCount", 0) != 1:
		push_error("FAIL: Expected appliedCount=1 for center batch, got %s" % str(res_center))
		_cleanup_test_files()
		return false

	var center_count_rows = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	var center_count = int(center_count_rows[0].get("c", 0))
	if center_count != 1:
		push_error("FAIL: Expected 1 map_cell row for center corridor, got %d" % center_count)
		_cleanup_test_files()
		return false

	# Case D: Visit rows remain unchanged (only primary cell revealed, 1 place node)
	_cleanup_test_files()
	DB.init_db()

	var visit_batch = {
		"rows": [
			{
				"seq": 1,
				"kind": "visit",
				"lat": edge_latlon.x,
				"lon": edge_latlon.y,
				"startedAt": 1700000000,
				"dwellSeconds": 300
			}
		]
	}

	var res_visit = SyncServer.process_batch(peer_id, visit_batch)
	if res_visit.get("appliedCount", 0) != 1:
		push_error("FAIL: Expected appliedCount=1 for visit batch, got %s" % str(res_visit))
		_cleanup_test_files()
		return false

	var visit_cell_count_rows = DB._rows("SELECT COUNT(*) as c FROM map_cell;")
	var visit_cell_count = int(visit_cell_count_rows[0].get("c", 0))
	if visit_cell_count != 1:
		push_error("FAIL: Visit row must reveal only 1 cell, got %d" % visit_cell_count)
		_cleanup_test_files()
		return false

	var place_count_rows = DB._rows("SELECT COUNT(*) as c FROM place_node;")
	var place_count = int(place_count_rows[0].get("c", 0))
	if place_count != 1:
		push_error("FAIL: Expected 1 place_node for visit row, got %d" % place_count)
		_cleanup_test_files()
		return false

	# Clean up and restore default paths
	_cleanup_test_files()
	DB.close()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	return true
