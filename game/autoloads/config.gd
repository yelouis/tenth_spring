extends Node

var walk_speed_mph: float = 15.0
var bicycle_speed_multiplier: float = 2.0
var wall_seconds_per_game_minute: float = 2.0
var tile_meters: float = 8.0
var visit_radius_meters: float = 75.0
var visit_dwell_seconds: int = 120
var corridor_reveal_meters: float = 60.0
var home_fuzz_meters: float = 300.0
var base_access_meters: float = 500.0
var grass_encounter_rate: float = 0.10
var haunted_interior_encounter_rate: float = 0.12
var legendary_respawn_game_days: int = 30
var party_size: int = 6
var bag_cache_decay_game_days: int = 3
var haunt_growth_tick_game_days: int = 1
var distortion_field_interval_game_days: int = 3
var distortion_field_interval_escalated_game_days: int = 2
var distortion_field_duration_game_days: int = 1
var distortion_field_radius_miles: float = 10.0
var distortion_field_size_cells: int = 5
var distortion_field_foreign_share: float = 0.40
var ultra_beast_field_share: float = 0.02
var neighbourhoods_per_city: int = 8
var gateway_count: int = 4
var first_picks: int = 2
var finale_requires_finished: int = 5
var familiarity_tiers: Dictionary = {1: "known", 3: "familiar", 10: "mastered"}
var level_bands_by_miles: Array = [
	{"maxMiles": 2.0, "minLevel": 2, "maxLevel": 10},
	{"maxMiles": 10.0, "minLevel": 8, "maxLevel": 22},
	{"maxMiles": 50.0, "minLevel": 18, "maxLevel": 38},
	{"maxMiles": 300.0, "minLevel": 30, "maxLevel": 50},
	{"maxMiles": 1000.0, "minLevel": 42, "maxLevel": 62},
	{"maxMiles": 2000.0, "minLevel": 55, "maxLevel": 75},
	{"maxMiles": 999999.0, "minLevel": 65, "maxLevel": 85}
]

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
		bicycle_speed_multiplier = json.get("bicycleSpeedMultiplier", bicycle_speed_multiplier)
		wall_seconds_per_game_minute = json.get("wallSecondsPerGameMinute", wall_seconds_per_game_minute)
		tile_meters = json.get("tileMeters", tile_meters)
		visit_radius_meters = json.get("visitRadiusMeters", visit_radius_meters)
		visit_dwell_seconds = json.get("visitDwellSeconds", visit_dwell_seconds)
		corridor_reveal_meters = json.get("corridorRevealMeters", corridor_reveal_meters)
		home_fuzz_meters = json.get("homeFuzzMeters", home_fuzz_meters)
		base_access_meters = json.get("baseAccessMeters", base_access_meters)
		grass_encounter_rate = json.get("grassEncounterRate", grass_encounter_rate)
		haunted_interior_encounter_rate = json.get("hauntedInteriorEncounterRate", haunted_interior_encounter_rate)
		legendary_respawn_game_days = json.get("legendaryRespawnGameDays", legendary_respawn_game_days)
		party_size = json.get("partySize", party_size)
		bag_cache_decay_game_days = json.get("bagCacheDecayGameDays", bag_cache_decay_game_days)
		haunt_growth_tick_game_days = json.get("hauntGrowthTickGameDays", haunt_growth_tick_game_days)
		distortion_field_interval_game_days = int(json.get("distortionFieldIntervalGameDays", distortion_field_interval_game_days))
		distortion_field_interval_escalated_game_days = int(json.get("distortionFieldIntervalEscalatedGameDays", distortion_field_interval_escalated_game_days))
		distortion_field_duration_game_days = int(json.get("distortionFieldDurationGameDays", distortion_field_duration_game_days))
		distortion_field_radius_miles = float(json.get("distortionFieldRadiusMiles", distortion_field_radius_miles))
		distortion_field_size_cells = int(json.get("distortionFieldSizeCells", distortion_field_size_cells))
		distortion_field_foreign_share = float(json.get("distortionFieldForeignShare", distortion_field_foreign_share))
		ultra_beast_field_share = float(json.get("ultraBeastFieldShare", ultra_beast_field_share))
		neighbourhoods_per_city = int(json.get("neighbourhoodsPerCity", neighbourhoods_per_city))
		gateway_count = int(json.get("gatewayCount", gateway_count))
		first_picks = int(json.get("firstPicks", first_picks))
		finale_requires_finished = int(json.get("finaleRequiresFinished", finale_requires_finished))
		if json.has("familiarityTiers"):
			familiarity_tiers = json["familiarityTiers"]
		if json.has("levelBandsByMiles") and json["levelBandsByMiles"] is Array:
			level_bands_by_miles = json["levelBandsByMiles"]
