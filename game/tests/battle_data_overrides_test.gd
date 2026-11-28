extends Node

## Tests for AssetDB Gen 8 move overrides (Item 92 / Decision 87).
## Contract: docs/agent_execution_guide.md §3 & §6.5.

const AssetDBRef := preload("res://rom/asset_db.gd")
const DataPackImporterRef := preload("res://rom/data_pack.gd")

const TEST_ROOT := "user://test/battle_data_overrides_test"


func _write_json(abs_path: String, payload: Variant) -> void:
	DataPackImporterRef._write_json_file(abs_path, payload)


func run_test() -> bool:
	var root_abs := ProjectSettings.globalize_path(TEST_ROOT)
	DataPackImporterRef._remove_dir_recursive(root_abs)
	AssetDBRef.clear_memory_cache()

	# 1. Synthetic cache with 3 moves
	var cache_dir := TEST_ROOT + "/cache"
	var cache_abs := ProjectSettings.globalize_path(cache_dir)
	_write_json(cache_abs.path_join("data/moves.json"), {
		"105": {"id": 105, "power": 0, "pp": 5, "accuracy": 0, "priority": 0, "type": "normal", "damage_class": "status"},
		"803": {"id": 803, "power": 55, "pp": 20, "accuracy": 100, "priority": 0, "type": "grass", "damage_class": "physical"},
		"33": {"id": 33, "power": 40, "pp": 35, "accuracy": 100, "priority": 0, "type": "normal", "damage_class": "physical"},
	})

	# 2. Synthetic overrides file with valid overrides + unknown move + unknown field
	var ov_res := TEST_ROOT + "/overrides.json"
	var ov_abs := ProjectSettings.globalize_path(ov_res)
	_write_json(ov_abs, {
		"format": 1,
		"moves": {
			"105": {"pp": 10, "was": {"pp": 5}, "why": "Synthetic PP override"},
			"803": {"power": 70, "not_a_real_field": 999, "was": {"power": 55}, "why": "Synthetic power override"},
			"99999": {"power": 120, "was": {"power": 100}, "why": "Synthetic unknown move"},
		},
	})

	var mv105 := AssetDBRef.move(105, cache_dir, ov_res)
	if int(mv105.get("pp", 0)) != 10:
		push_error("Expected overridden #105 pp=10, got %s" % str(mv105))
		return false
	if mv105.has("was") or mv105.has("why"):
		push_error("Override metadata 'was'/'why' must not be copied onto move #105: %s" % str(mv105))
		return false

	var mv803 := AssetDBRef.move(803, cache_dir, ov_res)
	if int(mv803.get("power", 0)) != 70:
		push_error("Expected overridden #803 power=70, got %s" % str(mv803))
		return false
	if mv803.has("not_a_real_field") or mv803.has("was") or mv803.has("why"):
		push_error("Unknown field or metadata leaked onto move #803: %s" % str(mv803))
		return false

	# Unknown move must remain absent; untouched move #33 must stay unchanged
	if not AssetDBRef.move(99999, cache_dir, ov_res).is_empty():
		push_error("Unknown move #99999 should not be created by overrides")
		return false
	var mv33 := AssetDBRef.move(33, cache_dir, ov_res)
	if int(mv33.get("power", 0)) != 40 or int(mv33.get("pp", 0)) != 35:
		push_error("Untouched move #33 changed unexpectedly: %s" % str(mv33))
		return false

	# Reading with empty overrides_path returns raw un-overridden cache values
	var mv803_raw := AssetDBRef.move(803, cache_dir, "")
	if int(mv803_raw.get("power", 0)) != 55:
		push_error("Expected raw un-overridden #803 power=55, got %s" % str(mv803_raw))
		return false

	# 3. Shipped res://config/battle_data_overrides.json contract check (11 move entries, each with why)
	var shipped := AssetDBRef.battle_data_overrides()
	if int(shipped.get("format", 0)) != 1:
		push_error("Expected shipped battle_data_overrides.json format=1, got %s" % str(shipped.get("format", 0)))
		return false
	var shipped_moves: Variant = shipped.get("moves", {})
	if not (shipped_moves is Dictionary) or (shipped_moves as Dictionary).size() != 11:
		push_error("Expected 11 move entries in shipped battle_data_overrides.json, got %d" % ((shipped_moves as Dictionary).size() if shipped_moves is Dictionary else -1))
		return false
	for mk in (shipped_moves as Dictionary).keys():
		var entry: Variant = (shipped_moves as Dictionary)[mk]
		if not (entry is Dictionary):
			push_error("Malformed override entry for move %s" % str(mk))
			return false
		var why_s := str((entry as Dictionary).get("why", "")).strip_edges()
		if why_s == "":
			push_error("Missing non-empty 'why' on shipped move override %s" % str(mk))
			return false
		if not ((entry as Dictionary).get("was", null) is Dictionary):
			push_error("Missing 'was' dictionary on shipped move override %s" % str(mk))
			return false

	DataPackImporterRef._remove_dir_recursive(root_abs)
	AssetDBRef.clear_memory_cache()
	return true
