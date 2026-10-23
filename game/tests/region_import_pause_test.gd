extends Node

# region_import_pause_test.gd — Memory Watchdog Pause/Resume Parity Test
# Contract: docs/implementation_plan_world_generation.md §9.1 & docs/agent_execution_guide.md §6.5

const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

const GOLDEN_CANONICAL_HASH: String = "fb7d26d6189721ed0b0652e9a69a0a92d0b4e105e904d5a303d8b34544bb368e"
const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const TEST_DB_PATH: String = "user://test/map_data/region_import_pause_test.db"

class MockMemoryWatchdogReader:
	var total_ram: int = 16 * 1024 * 1024 * 1024 # 16 GiB
	var floor_bytes: int = int(16 * 1024 * 1024 * 1024 * 0.10) # 1.6 GiB
	var calls: int = 0
	var drop_at_call: int = 2
	var recover_after_poll: int = 2
	var poll_count: int = 0

	func get_memory_info() -> Dictionary:
		calls += 1
		var avail: int = 8 * 1024 * 1024 * 1024 # Normal 8 GiB
		if calls >= drop_at_call and poll_count < recover_after_poll:
			avail = int(floor_bytes * 0.5) # Drop below floor (0.8 GiB)
			poll_count += 1
		elif poll_count >= recover_after_poll:
			avail = floor_bytes + 1024 * 1024 * 1024 # Recovered to 2.6 GiB (above floor + 512 MiB)
		return {"physical": total_ram, "available": avail}

func run_test() -> bool:
	_cleanup()

	var mock := MockMemoryWatchdogReader.new()
	var conv := RegionConverter.new()
	conv.memory_reader = Callable(mock, "get_memory_info")
	conv.simulated_pause_delay_ms = 10
	conv.required_resume_consecutive_ms = 50 # 50 ms for fast test execution

	var res := conv.convert(FIXTURE_PBF, TEST_DB_PATH)

	if not res.get("ok", false):
		push_error("Pause test conversion failed: %s" % res.get("error", "unknown"))
		_cleanup()
		return false

	if conv.pause_count < 1:
		push_error("Expected at least 1 pause event, got %d" % conv.pause_count)
		_cleanup()
		return false

	if conv.resume_count < 1:
		push_error("Expected at least 1 resume event, got %d" % conv.resume_count)
		_cleanup()
		return false

	var canonical_hash: String = res.get("canonical_hash", "")
	if canonical_hash != GOLDEN_CANONICAL_HASH:
		push_error("Hash mismatch after pause/resume: expected %s, got %s" % [GOLDEN_CANONICAL_HASH, canonical_hash])
		_cleanup()
		return false

	_cleanup()
	return true

func _cleanup() -> void:
	var base_dir := TEST_DB_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		return
	var siblings = [
		TEST_DB_PATH,
		TEST_DB_PATH + "-wal",
		TEST_DB_PATH + "-shm",
		TEST_DB_PATH + ".nodes.tmp",
		TEST_DB_PATH + ".coords.tmp",
		TEST_DB_PATH + ".rels.tmp"
	]
	for p in siblings:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
