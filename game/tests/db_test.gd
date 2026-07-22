extends Node

# DB & Relocation Test Suite for PC Engine

func run_test() -> bool:
	# Schema version check
	var version = DB.get_schema_version()
	if version != 1:
		push_error("FAIL: Expected schema_version 1, got %d" % version)
		return false

	# Test Relocation Manager
	var peer_id = "test_phone_001"
	DB.update_sync_peer(peer_id, 2, 37.776, -122.420, 1700000200)

	var RelocationManager = load("res://scripts/relocation_manager.gd").new()
	var relocation = RelocationManager.calculate_relocation(peer_id)

	if not relocation.has("spawn_tile"):
		push_error("FAIL: Missing spawn_tile in relocation result")
		return false

	print("PASS: DB & Relocation Test Suite")
	return true
