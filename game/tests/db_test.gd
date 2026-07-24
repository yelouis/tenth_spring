extends Node

# DB & Relocation Test Suite for PC Engine
# Verifies schema version, relocation manager calculation, schema round-trip,
# atomic file persistence, and temp backup recovery (F11).

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

	# 5. Atomic temp backup recovery test (F11)
	if FileAccess.file_exists(DB.DB_PATH):
		var main_content = FileAccess.get_file_as_string(DB.DB_PATH)
		var tmp_file = FileAccess.open(DB.DB_TMP_PATH, FileAccess.WRITE)
		if tmp_file != null:
			tmp_file.store_string(main_content)
			tmp_file.close()

		# Truncate main file to simulate crash during write
		var corrupt_file = FileAccess.open(DB.DB_PATH, FileAccess.WRITE)
		if corrupt_file != null:
			corrupt_file.store_string("")
			corrupt_file.close()

		# Reload DB - should recover cleanly from temp backup
		DB.init_db()
		var recovered_cell = DB.get_map_cell(10, 20)
		if recovered_cell.get("reveal_state", 0) != 1:
			push_error("FAIL: Atomic temp backup recovery failed when primary DB was corrupted")
			return false

	print("PASS: DB, Relocation, Persistence & Atomic Recovery (F11) Test Suite")
	return true
