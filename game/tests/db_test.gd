extends Node

# DB & Relocation Test Suite for PC Engine
# Verifies schema version, relocation manager calculation, schema round-trip,
# and persistence across store reload.

func run_test() -> bool:
	# 1. Schema version check
	var version = DB.get_schema_version()
	if version != 1:
		push_error("FAIL: Expected schema_version 1, got %d" % version)
		return false

	# 2. Relocation Manager Test
	var peer_id = "test_phone_001"
	DB.update_sync_peer(peer_id, 2, 37.776, -122.420, 1700000200)

	var RelocationManager = load("res://scripts/relocation_manager.gd").new()
	var relocation = RelocationManager.calculate_relocation(peer_id)

	if not relocation.has("spawn_tile"):
		push_error("FAIL: Missing spawn_tile in relocation result")
		return false

	# 3. Schema round-trip test
	DB.upsert_map_cell(10, 20, 1, 999)
	var cell = DB.get_map_cell(10, 20)
	if cell.get("reveal_state", 0) != 1 or cell.get("cell_seed", 0) != 999:
		push_error("FAIL: Map cell round-trip failed")
		return false

	DB.upsert_place_node({"id": "p_test_1", "name": "Pharmacy", "category": 2, "cell_x": 10, "cell_y": 20})
	var place = DB.get_place_node("p_test_1")
	if place.get("name", "") != "Pharmacy":
		push_error("FAIL: Place node round-trip failed")
		return false

	# 4. Persistence Test
	DB.init_db()
	var reloaded_cell = DB.get_map_cell(10, 20)
	if reloaded_cell.get("reveal_state", 0) != 1:
		push_error("FAIL: Map cell persistence test failed across store reload")
		return false

	print("PASS: DB, Relocation & Persistence Test Suite")
	return true
