extends Node

var walk_speed_mph: float = 15.0
var wall_seconds_per_game_minute: float = 2.0
var tile_meters: float = 16.0
var visit_radius_meters: float = 75.0
var visit_dwell_seconds: int = 120
var corridor_reveal_meters: float = 60.0
var home_fuzz_meters: float = 300.0
var death_cache_decay_game_days: int = 3
var colony_growth_tick_game_days: int = 1
var familiarity_tiers: Dictionary = {1: "known", 3: "familiar", 10: "mastered"}

func _ready() -> void:
	load_tuning_config("res://config/tuning.json")

func load_tuning_config(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json = JSON.parse_string(text)
	if typeof(json) == TYPE_DICTIONARY:
		walk_speed_mph = json.get("walkSpeedMph", walk_speed_mph)
		wall_seconds_per_game_minute = json.get("wallSecondsPerGameMinute", wall_seconds_per_game_minute)
		tile_meters = json.get("tileMeters", tile_meters)
		visit_radius_meters = json.get("visitRadiusMeters", visit_radius_meters)
		visit_dwell_seconds = json.get("visitDwellSeconds", visit_dwell_seconds)
		corridor_reveal_meters = json.get("corridorRevealMeters", corridor_reveal_meters)
		home_fuzz_meters = json.get("homeFuzzMeters", home_fuzz_meters)
		death_cache_decay_game_days = json.get("deathCacheDecayGameDays", death_cache_decay_game_days)
		colony_growth_tick_game_days = json.get("colonyGrowthTickGameDays", colony_growth_tick_game_days)
		if json.has("familiarityTiers"):
			familiarity_tiers = json["familiarityTiers"]
