extends RefCounted

const RULES_PATH: String = "res://config/battle_rules.json"

static var _cache: Dictionary = {}


static func load_rules(path: String = RULES_PATH) -> Dictionary:
	if path == RULES_PATH and not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(path):
		push_error("BattleRules: missing config file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("BattleRules: invalid JSON in %s" % path)
		return {}
	if path == RULES_PATH:
		_cache = parsed
	return parsed


static func clear_cache() -> void:
	_cache.clear()


static func get_int(key: String, default_val: int = 0) -> int:
	return int(load_rules().get(key, default_val))


static func get_bool(key: String, default_val: bool = false) -> bool:
	return bool(load_rules().get(key, default_val))


static func get_string(key: String, default_val: String = "") -> String:
	return str(load_rules().get(key, default_val))


static func get_int_array(key: String) -> Array[int]:
	var raw: Variant = load_rules().get(key, [])
	var out: Array[int] = []
	if raw is Array:
		for v in raw:
			out.append(int(v))
	return out
