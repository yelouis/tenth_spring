class_name CellClassifier
extends RefCounted

## game/world/cell_classifier.gd — Deterministic Cell Zone, Region & Biome Classifier (Slice 3, Item 46)
## Contract: docs/implementation_plan_world_generation_slice3.md §1,
##           docs/design_world_generation.md §3, §5,
##           docs/design_encounters_and_haunted_zones.md §2

const Grid := preload("res://world/grid.gd")
const PlacesPack := preload("res://world/places_pack.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

const REGIONS_CONFIG_PATH: String = "res://config/regions.json"
const FAMOUS_PLACES_CONFIG_PATH: String = "res://config/famous_places.json"

const ZONES: Array[String] = [
	"cemetery",
	"hospital",
	"ruins",
	"waterfront",
	"institutional",
	"retail",
	"downtown",
	"industrial",
	"parkland",
	"residential",
	"wilds",
]

const HAUNTED_ZONES: Array[String] = [
	"cemetery",
	"ruins",
	"hospital",
]

const DIVISIONS: Array[String] = [
	"New England",
	"Middle Atlantic",
	"South Atlantic",
	"East South Central",
	"West South Central",
	"East North Central",
	"West North Central",
	"Mountain",
	"Pacific",
]

const BIOMES: Array[String] = [
	"desert",
	"forest",
	"coast",
	"mountains",
	"wetland",
	"plains",
	"snow",
	"city",
]

const ZONE_BASE_GHOST_SHARE: Dictionary = {
	"cemetery": 0.60,
	"ruins": 0.45,
	"hospital": 0.30,
	"institutional": 0.12,
	"retail": 0.08,
	"downtown": 0.08,
	"parkland": 0.06,
	"wilds": 0.06,
	"waterfront": 0.05,
	"industrial": 0.05,
	"residential": 0.05,
}

static var _regions_cache: Dictionary = {}
static var _places_meta: Dictionary = {} # place_id -> {id, kind, region, lat, lon}

static func _ensure_regions_loaded() -> Dictionary:
	if not _regions_cache.is_empty():
		return _regions_cache
	if FileAccess.file_exists(REGIONS_CONFIG_PATH):
		var txt := FileAccess.get_file_as_string(REGIONS_CONFIG_PATH)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			_regions_cache = parsed
	if _regions_cache.is_empty():
		_regions_cache = {
			"divisions": DIVISIONS,
			"biomes": BIOMES,
			"place_biomes": {},
		}
	if _places_meta.is_empty() and FileAccess.file_exists(FAMOUS_PLACES_CONFIG_PATH):
		var ptxt := FileAccess.get_file_as_string(FAMOUS_PLACES_CONFIG_PATH)
		var pparsed: Variant = JSON.parse_string(ptxt)
		if pparsed is Array:
			for p_var in pparsed:
				if not (p_var is Dictionary):
					continue
				var p: Dictionary = p_var
				var pid: String = str(p.get("id", ""))
				if pid.is_empty():
					continue
				var wp: Dictionary = p.get("waypost", {})
				_places_meta[pid] = {
					"id": pid,
					"kind": str(p.get("kind", "city")),
					"region": str(p.get("region", "South Atlantic")),
					"lat": float(wp.get("lat", 0.0)),
					"lon": float(wp.get("lon", 0.0)),
				}
		_places_meta["city:fixture-city"] = {
			"id": "city:fixture-city",
			"kind": "city",
			"region": "South Atlantic",
			"lat": 0.01,
			"lon": 0.01,
		}
		_places_meta["site:fixture-park"] = {
			"id": "site:fixture-park",
			"kind": "site",
			"region": "South Atlantic",
			"lat": 0.01,
			"lon": 0.01,
		}
	return _regions_cache

static func place_baseline_biome(place_id: String) -> String:
	var cfg := _ensure_regions_loaded()
	var pb: Dictionary = cfg.get("place_biomes", {})
	if pb.has(place_id):
		var b: String = str(pb[place_id])
		if b in BIOMES:
			return b
	return "plains"

static func resolve_region_and_place(cx: int, cy: int, place_id_override: String = "") -> Dictionary:
	_ensure_regions_loaded()
	if not place_id_override.is_empty():
		if _places_meta.has(place_id_override):
			var pm: Dictionary = _places_meta[place_id_override]
			var reg: String = str(pm.get("region", "South Atlantic"))
			if reg.is_empty() or not (reg in DIVISIONS):
				reg = "South Atlantic"
			return {"place_id": place_id_override, "region": reg}
		if PlacesPack._default_instance != null and PlacesPack._default_instance._loaded and PlacesPack.has_place(place_id_override):
			var pinfo := PlacesPack.place_info(place_id_override)
			var reg := str(pinfo.get("region", "South Atlantic"))
			if reg.is_empty() or not (reg in DIVISIONS):
				reg = "South Atlantic"
			return {"place_id": place_id_override, "region": reg}

	if PlacesPack._default_instance != null and PlacesPack._default_instance._loaded:
		var hit: Dictionary = PlacesPack._default_instance.inst_lookup_cell(cx, cy)
		if not hit.is_empty():
			var pid := str(hit.get("place_id", ""))
			if _places_meta.has(pid):
				var reg := str(_places_meta[pid].get("region", "South Atlantic"))
				return {"place_id": pid, "region": reg}
			var pinfo: Dictionary = PlacesPack._default_instance.inst_place_info(pid)
			var reg := str(pinfo.get("region", "South Atlantic"))
			if reg.is_empty() or not (reg in DIVISIONS):
				reg = "South Atlantic"
			return {"place_id": pid, "region": reg}

	var ll: Vector2 = Grid.cell_center_latlon(Vector2i(cx, cy))
	var best_pid: String = ""
	var best_reg: String = "South Atlantic"
	var best_dist: float = INF
	for pid in _places_meta.keys():
		var pm: Dictionary = _places_meta[pid]
		if str(pm.get("kind", "")) != "city":
			continue
		var d: float = Grid.ground_distance_m(ll.x, ll.y, float(pm.get("lat", 0.0)), float(pm.get("lon", 0.0)))
		if d < best_dist:
			best_dist = d
			best_pid = str(pid)
			best_reg = str(pm.get("region", "South Atlantic"))
	if not best_pid.is_empty():
		if best_reg.is_empty() or not (best_reg in DIVISIONS):
			best_reg = "South Atlantic"
		return {"place_id": best_pid, "region": best_reg}

	return {"place_id": "", "region": "South Atlantic"}

static func classify_cell(cx: int, cy: int, area: Dictionary, synth_result: Dictionary = {}, place_id_override: String = "") -> Dictionary:
	var rp := resolve_region_and_place(cx, cy, place_id_override)
	var resolved_pid: String = str(rp.get("place_id", ""))
	var region: String = str(rp.get("region", "South Atlantic"))
	var zone: String = classify_zone(area, synth_result)
	var biome: String = classify_biome(zone, area, synth_result, resolved_pid)
	var ghost_base: float = float(ZONE_BASE_GHOST_SHARE.get(zone, 0.06))
	return {
		"zone": zone,
		"biome": biome,
		"region": region,
		"place_id": resolved_pid,
		"ghost_base": ghost_base,
	}

static func classify_zone(area: Dictionary, synth_result: Dictionary = {}) -> String:
	var center: Dictionary = area.get(Vector2i.ZERO, {})
	var polys: Array = center.get("polys", [])
	var places: Array = center.get("places", [])
	var sea: int = int(center.get("sea", 0))

	var has_cemetery := false
	var has_ruins := false
	var has_hospital := false
	var has_waterfront := (sea == 1 or sea == 2)
	var has_institutional := false
	var has_retail := false
	var has_downtown := false
	var has_industrial := false
	var has_parkland := false
	var has_residential := false

	# 1. Inspect POI place nodes
	for p_var in places:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		var cat: String = str(p.get("category", "")).to_lower()
		var subk: String = str(p.get("subkind", "")).to_lower()
		var pname: String = str(p.get("name", "")).to_lower()

		if cat == "cemetery" or subk in ["cemetery", "grave_yard"] or pname.contains("cemetery") or pname.contains("graveyard"):
			has_cemetery = true
		elif cat == "haunted" or subk in ["ruins", "abandoned", "disused"] or pname.contains("ruin") or pname.contains("abandoned"):
			has_ruins = true
		elif cat == "medical" or subk in ["hospital", "clinic"] or pname.contains("hospital"):
			has_hospital = true
		elif cat in ["civic", "landmark", "education", "institutional"] or subk in ["school", "university", "college", "library", "townhall", "courthouse", "museum"]:
			has_institutional = true
		elif cat in ["bigbox", "grocery", "hardware", "retail", "shop"] or subk in ["supermarket", "mall", "department_store", "hardware", "shop", "retail"]:
			has_retail = true
		elif cat == "park":
			has_parkland = true

	# 2. Inspect polygons
	for poly_var in polys:
		if not (poly_var is Dictionary):
			continue
		var poly: Dictionary = poly_var
		var kind: String = str(poly.get("kind", "")).to_lower()
		var subk: String = str(poly.get("subkind", "")).to_lower()
		var pname: String = str(poly.get("name", "")).to_lower()

		if kind == "cemetery" or subk in ["cemetery", "grave_yard"] or pname.contains("cemetery"):
			has_cemetery = true
		elif kind == "ruins" or subk in ["ruins", "abandoned", "disused"]:
			has_ruins = true
		elif kind == "building":
			if subk in ["hospital", "clinic"] or pname.contains("hospital"):
				has_hospital = true
			elif subk in ["ruins", "abandoned", "disused"]:
				has_ruins = true
			elif subk in ["school", "college", "university", "kindergarten", "public", "civic", "government", "library", "townhall", "courthouse", "museum"]:
				has_institutional = true
			elif subk in ["retail", "supermarket", "shop", "kiosk", "mall"]:
				has_retail = true
			elif subk in ["commercial", "office", "hotel"]:
				has_downtown = true
			elif subk in ["industrial", "warehouse", "manufacture", "factory"]:
				has_industrial = true
			elif subk in ["house", "detached", "residential", "semidetached_house", "bungalow", "terrace", "apartments", "dormitory"]:
				has_residential = true
		elif kind in ["water", "sand"]:
			has_waterfront = true
		elif kind == "retail" or subk == "retail":
			has_retail = true
		elif kind == "commercial" or subk == "commercial":
			has_downtown = true
		elif kind == "industrial" or subk in ["industrial", "railway", "quarry"]:
			has_industrial = true
		elif kind in ["park", "forest", "scrub"]:
			has_parkland = true
		elif kind == "residential":
			has_residential = true

	# 3. Inspect synthesized tiles and stamps if provided
	var tiles: PackedByteArray = synth_result.get("tiles", PackedByteArray())
	var stamps: Array = synth_result.get("stamps", [])

	var water_sand_tiles := 0
	var tree_grass_tiles := 0
	var plaza_building_tiles := 0
	var rail_tiles := 0
	var grave_tiles := 0
	var rubble_tiles := 0

	if tiles.size() == 3072:
		for i in range(0, 3072, 3):
			var cls: int = tiles[i]
			if cls == 4 or cls == 5: # TILE_WATER, TILE_SAND
				water_sand_tiles += 1
			elif cls == 2 or cls == 3: # TILE_TALL_GRASS, TILE_TREE
				tree_grass_tiles += 1
			elif cls in [11, 12, 13, 14, 21]: # PLAZA, ROOF, WALL, DOOR, STAMP
				plaza_building_tiles += 1
			elif cls == 9: # TILE_RAIL
				rail_tiles += 1
			elif cls == 17: # TILE_GRAVE
				grave_tiles += 1
			elif cls == 20: # TILE_RUBBLE
				rubble_tiles += 1

	var house_stamps := 0
	var block_stamps := 0
	var ruined_stamps := 0
	var standing_stamps := 0
	for st_var in stamps:
		if not (st_var is Dictionary):
			continue
		var st: Dictionary = st_var
		var sid: int = int(st.get("stamp_id", 0))
		if (sid >= 15 and sid <= 41) or (sid >= 71 and sid <= 85):
			house_stamps += 1
		elif sid == 42 or (sid >= 60 and sid <= 70) or (sid >= 86 and sid <= 97):
			block_stamps += 1
		if sid >= 15 and sid <= 70:
			ruined_stamps += 1
		elif sid >= 71 and sid <= 97:
			standing_stamps += 1

	if grave_tiles >= 2:
		has_cemetery = true
	if water_sand_tiles >= 160:
		has_waterfront = true
	if block_stamps >= 1 or plaza_building_tiles >= 240:
		has_downtown = true
	if rail_tiles >= 24:
		has_industrial = true
	if house_stamps >= 2:
		has_residential = true
	if (rubble_tiles >= 96 or (ruined_stamps >= 2 and standing_stamps == 0)) and not (has_residential or has_downtown or has_retail or has_industrial or has_institutional):
		has_ruins = true

	# Priority evaluation: Haunted zones (cemetery > ruins > hospital) ALWAYS win ties (§1.1, design_world_generation.md §3)
	if has_cemetery:
		return "cemetery"
	if has_ruins:
		return "ruins"
	if has_hospital:
		return "hospital"
	if has_waterfront:
		return "waterfront"
	if has_institutional:
		return "institutional"
	if has_retail:
		return "retail"
	if has_downtown:
		return "downtown"
	if has_industrial:
		return "industrial"
	if has_parkland:
		return "parkland"
	if has_residential:
		return "residential"
	return "wilds"

static func classify_biome(zone: String, area: Dictionary, synth_result: Dictionary = {}, place_id: String = "") -> String:
	var baseline: String = place_baseline_biome(place_id)
	var center: Dictionary = area.get(Vector2i.ZERO, {})
	var polys: Array = center.get("polys", [])
	var sea: int = int(center.get("sea", 0))

	if sea == 1 or sea == 2:
		return "coast"

	var has_wetland := false
	var has_forest := false
	var has_sand := false
	for poly_var in polys:
		if not (poly_var is Dictionary):
			continue
		var kind: String = str((poly_var as Dictionary).get("kind", "")).to_lower()
		if kind == "wetland":
			has_wetland = true
		elif kind == "forest":
			has_forest = true
		elif kind == "sand":
			has_sand = true

	var tiles: PackedByteArray = synth_result.get("tiles", PackedByteArray())
	var marsh_tiles := 0
	var water_sand_tiles := 0
	var tree_tiles := 0
	if tiles.size() == 3072:
		for i in range(0, 3072, 3):
			var cls: int = tiles[i]
			if cls == 6: # TILE_MARSH
				marsh_tiles += 1
			elif cls == 4 or cls == 5: # TILE_WATER, TILE_SAND
				water_sand_tiles += 1
			elif cls == 3: # TILE_TREE
				tree_tiles += 1

	if has_wetland or marsh_tiles >= 64:
		return "wetland"
	if zone == "waterfront" and (baseline == "coast" or has_sand or water_sand_tiles >= 256):
		return "coast"
	if zone in ["downtown", "retail", "industrial", "institutional", "hospital"]:
		return "city"
	if zone == "residential" and baseline == "city":
		return "city"
	if baseline in ["desert", "snow", "mountains", "wetland", "coast"]:
		return baseline
	if has_forest or tree_tiles >= 256 or (zone == "parkland" and baseline == "city"):
		return "forest"
	if baseline in BIOMES:
		return baseline
	return "plains"
