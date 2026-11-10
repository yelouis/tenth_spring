class_name SpawnDirector
extends RefCounted

## game/encounters/spawn_director.gd — Ghost-Share, Distance Level Bands & Wild Spawn Director (Slice 3, Item 46)
## Contract: docs/implementation_plan_world_generation_slice3.md §3, §4, §5,
##           docs/design_encounters_and_haunted_zones.md §2–§4, Decision 32, Decision 35

const Grid := preload("res://world/grid.gd")
const PlacesPack := preload("res://world/places_pack.gd")
const CellClassifier := preload("res://world/cell_classifier.gd")
const DistortionFields := preload("res://world/distortion_fields.gd")

const SPAWN_TABLES_PATH: String = "res://config/spawn_tables.json"
const METERS_PER_MILE: float = 1609.344

const LEVEL_BANDS: Array = [
	{"max_miles": 2.0, "min_lv": 2, "max_lv": 10},
	{"max_miles": 10.0, "min_lv": 8, "max_lv": 22},
	{"max_miles": 50.0, "min_lv": 18, "max_lv": 38},
	{"max_miles": 300.0, "min_lv": 30, "max_lv": 50},
	{"max_miles": 1000.0, "min_lv": 42, "max_lv": 62},
	{"max_miles": 2000.0, "min_lv": 55, "max_lv": 75},
	{"max_miles": INF, "min_lv": 65, "max_lv": 85},
]

static var _tables_cache: Dictionary = {}

static func get_spawn_tables() -> Dictionary:
	if not _tables_cache.is_empty():
		return _tables_cache
	if FileAccess.file_exists(SPAWN_TABLES_PATH):
		var txt := FileAccess.get_file_as_string(SPAWN_TABLES_PATH)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			_tables_cache = parsed
			return _tables_cache
	return {}

static func compute_ghost_share(zone: String, time_band: String, haunt_stage: int = 0) -> float:
	var zone_base: float = float(CellClassifier.ZONE_BASE_GHOST_SHARE.get(zone, 0.06))
	var night_mult: float = 1.0
	if time_band == "night":
		night_mult = 3.0
	elif time_band == "dusk":
		night_mult = 1.5
	return clampf(zone_base * night_mult + 0.10 * float(maxi(0, haunt_stage)), 0.0, 0.80)

static func compute_distance_miles(cell: Vector2i, starter_place_id: String = "") -> float:
	if starter_place_id.is_empty() or not PlacesPack.has_place(starter_place_id):
		return 0.0
	var wp: Dictionary = PlacesPack.waypost(starter_place_id)
	if wp.is_empty():
		return 0.0
	var cell_ll: Vector2 = Grid.cell_center_latlon(cell)
	var dist_m: float = Grid.ground_distance_m(cell_ll.x, cell_ll.y, float(wp.get("lat", 0.0)), float(wp.get("lon", 0.0)))
	return dist_m / METERS_PER_MILE

static func compute_level_band(
	distance_miles: float,
	is_haunted_pool: bool = false,
	time_band: String = "day",
	haunt_stage: int = 0
) -> Vector2i:
	var d: float = maxf(0.0, distance_miles)
	var min_lv: int = 65
	var max_lv: int = 85
	for band in LEVEL_BANDS:
		if d < float(band["max_miles"]):
			min_lv = int(band["min_lv"])
			max_lv = int(band["max_lv"])
			break

	var bonus: int = 0
	if is_haunted_pool and time_band == "night":
		bonus += 2
	if haunt_stage > 0:
		bonus += 2 * maxi(0, haunt_stage)

	return Vector2i(clampi(min_lv + bonus, 1, 100), clampi(max_lv + bonus, 1, 100))

static func filter_pool(zone: String, pool_kind: String, biome: String, region: String) -> Array[Dictionary]:
	var tables := get_spawn_tables()
	var zones_dict: Dictionary = tables.get("zones", {})
	var z_entry: Dictionary = zones_dict.get(zone, zones_dict.get("wilds", {}))
	var raw_pool: Array = z_entry.get(pool_kind, [])
	var out: Array[Dictionary] = []
	for item_var in raw_pool:
		if not (item_var is Dictionary):
			continue
		var item: Dictionary = item_var
		var biomes_arr: Array = item.get("biomes", ["all"])
		var regions_arr: Array = item.get("regions", ["all"])
		var biome_ok: bool = biomes_arr.has("all") or biomes_arr.has(biome)
		var region_ok: bool = regions_arr.has("all") or regions_arr.has(region)
		if biome_ok and region_ok:
			out.append(item)
	return out

static func _weighted_pick(entries: Array[Dictionary], u: float) -> int:
	if entries.is_empty():
		return 1
	var total_weight: int = 0
	for e in entries:
		total_weight += maxi(1, int(e.get("weight", 1)))
	var target: float = clampf(u, 0.0, 0.999999) * float(total_weight)
	var acc: float = 0.0
	for e in entries:
		acc += float(maxi(1, int(e.get("weight", 1))))
		if target < acc:
			return int(e.get("dex", 1))
	return int(entries[entries.size() - 1].get("dex", 1))

static func roll_encounter(ctx: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var zone: String = str(ctx.get("zone", "wilds"))
	var biome: String = str(ctx.get("biome", "plains"))
	var region: String = str(ctx.get("region", "South Atlantic"))
	var time_band: String = str(ctx.get("time_band", "day"))
	var haunt_stage: int = int(ctx.get("haunt_stage", 0))
	var in_distortion_field: bool = bool(ctx.get("in_distortion_field", false))
	var anchors_held: int = int(ctx.get("anchors_held", 0))
	var necrozma_cleared: bool = bool(ctx.get("necrozma_cleared", false))

	var distance_miles: float = 0.0
	if ctx.has("distance_miles"):
		distance_miles = float(ctx.get("distance_miles", 0.0))
	elif ctx.has("cell"):
		var cell: Vector2i = ctx["cell"]
		var starter_pid: String = str(ctx.get("starter_place_id", ""))
		distance_miles = compute_distance_miles(cell, starter_pid)

	var ghost_share: float = compute_ghost_share(zone, time_band, haunt_stage)
	var tables := get_spawn_tables()

	# 1. Check Distortion Field 40% foreign draw
	if in_distortion_field:
		var u_field: float = rng.randf()
		if u_field < DistortionFields.FOREIGN_SHARE:
			var u_ub: float = rng.randf()
			var u_pick: float = rng.randf()
			var u_lv: float = rng.randf()
			if anchors_held >= 6 and necrozma_cleared and u_ub < DistortionFields.ULTRA_BEAST_SHARE:
				var ub_pool: Array = tables.get("ultra_beast_pool", [793])
				var ub_idx: int = clampi(floori(u_pick * float(ub_pool.size())), 0, ub_pool.size() - 1)
				var ub_dex: int = int(ub_pool[ub_idx])
				var ub_band: Vector2i = compute_level_band(distance_miles, false, time_band, haunt_stage)
				var ub_lv: int = ub_band.x + floori(u_lv * float(ub_band.y - ub_band.x + 1))
				return {
					"dex": ub_dex,
					"level": clampi(ub_lv, ub_band.x, ub_band.y),
					"level_band": ub_band,
					"pool": "ultra_beast",
					"ghost_share": ghost_share,
					"from_distortion_field": true,
					"is_ultra_beast": true,
				}
			else:
				var field_pool: Array = tables.get("non_legendary_field_pool", [1])
				var f_idx: int = clampi(floori(u_pick * float(field_pool.size())), 0, field_pool.size() - 1)
				var f_dex: int = int(field_pool[f_idx])
				var f_band: Vector2i = compute_level_band(distance_miles, false, time_band, haunt_stage)
				var f_lv: int = f_band.x + floori(u_lv * float(f_band.y - f_band.x + 1))
				return {
					"dex": f_dex,
					"level": clampi(f_lv, f_band.x, f_band.y),
					"level_band": f_band,
					"pool": "field",
					"ghost_share": ghost_share,
					"from_distortion_field": true,
					"is_ultra_beast": false,
				}

	# 2. Standard cell encounter roll (regular vs haunted pool by ghost_share)
	var u_pool: float = rng.randf()
	var is_haunted: bool = (u_pool < ghost_share)
	var pool_kind: String = "haunted" if is_haunted else "regular"
	var candidates: Array[Dictionary] = filter_pool(zone, pool_kind, biome, region)
	if candidates.is_empty():
		candidates = filter_pool("wilds", pool_kind, "plains", "South Atlantic")
	var u_species: float = rng.randf()
	var u_level: float = rng.randf()
	var chosen_dex: int = _weighted_pick(candidates, u_species)
	var band: Vector2i = compute_level_band(distance_miles, is_haunted, time_band, haunt_stage)
	var level: int = band.x + floori(u_level * float(band.y - band.x + 1))

	return {
		"dex": chosen_dex,
		"level": clampi(level, band.x, band.y),
		"level_band": band,
		"pool": pool_kind,
		"ghost_share": ghost_share,
		"from_distortion_field": false,
		"is_ultra_beast": false,
	}
