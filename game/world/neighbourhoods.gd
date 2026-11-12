class_name Neighbourhoods
extends RefCounted

## game/world/neighbourhoods.gd — Caricature City & Neighbourhood Roster Loader (Item 47)
## Contract: docs/design_neighbourhoods_and_caricature.md §2–§7, §10;
##           docs/implementation_plan_dc_trial.md §1.3, §3.1

const Grid := preload("res://world/grid.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

const DEFAULT_CONFIG_PATH: String = "res://config/neighbourhoods.json"
const FAMOUS_PLACES_PATHS: Array[String] = [
	"res://config/famous_places.json",
	"res://tests/fixtures/famous_places_fixture.json",
]

static var _config_path: String = DEFAULT_CONFIG_PATH
static var _loaded: bool = false
static var _loaded_path: String = ""
static var _cities_by_id: Dictionary = {} # place_id -> Dictionary
static var _areas_by_place: Dictionary = {} # place_id -> Array[Dictionary]
static var _areas_by_id: Dictionary = {} # area_id -> Dictionary
static var _wayposts_by_place: Dictionary = {} # place_id -> Dictionary {lat, lon, name}

static func set_config_path_for_tests(path: String) -> void:
	var target := DEFAULT_CONFIG_PATH if path.is_empty() else path
	_config_path = target
	_loaded = false
	_loaded_path = ""
	_cities_by_id.clear()
	_areas_by_place.clear()
	_areas_by_id.clear()

static func _ensure_wayposts_loaded() -> void:
	if not _wayposts_by_place.is_empty():
		return
	for p in FAMOUS_PLACES_PATHS:
		if not FileAccess.file_exists(p):
			continue
		var txt := FileAccess.get_file_as_string(p)
		if txt.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(txt)
		var list: Array = []
		if parsed is Array:
			list = parsed
		elif parsed is Dictionary and parsed.has("places") and parsed["places"] is Array:
			list = parsed["places"]
		for item_var in list:
			if not (item_var is Dictionary):
				continue
			var item: Dictionary = item_var
			var pid := str(item.get("id", ""))
			if pid.is_empty() or _wayposts_by_place.has(pid):
				continue
			var wp_var: Variant = item.get("waypost", {})
			if wp_var is Dictionary:
				var wp: Dictionary = wp_var
				_wayposts_by_place[pid] = {
					"name": str(wp.get("name", "")),
					"lat": float(wp.get("lat", 0.0)),
					"lon": float(wp.get("lon", 0.0)),
				}

static func _ensure_loaded() -> void:
	if _loaded and _loaded_path == _config_path:
		return
	_cities_by_id.clear()
	_areas_by_place.clear()
	_areas_by_id.clear()
	_loaded = true
	_loaded_path = _config_path

	if not FileAccess.file_exists(_config_path):
		push_error("Neighbourhoods: roster file not found at %s" % _config_path)
		return
	var txt := FileAccess.get_file_as_string(_config_path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("Neighbourhoods: invalid JSON root in %s" % _config_path)
		return
	var root: Dictionary = parsed
	var cities_var: Variant = root.get("cities", [])
	if not (cities_var is Array):
		return
	var cities_arr: Array = cities_var
	for c_var in cities_arr:
		if not (c_var is Dictionary):
			continue
		var c: Dictionary = (c_var as Dictionary).duplicate(true)
		var pid := str(c.get("place_id", ""))
		if pid.is_empty():
			continue
		_cities_by_id[pid] = c

		var area_list: Array = []
		var camp_var: Variant = c.get("camp", {})
		if camp_var is Dictionary and not (camp_var as Dictionary).is_empty():
			var camp_entry: Dictionary = (camp_var as Dictionary).duplicate(true)
			camp_entry["kind"] = "camp"
			camp_entry["place_id"] = pid
			area_list.append(camp_entry)
			var cid := str(camp_entry.get("id", ""))
			if not cid.is_empty():
				_areas_by_id[cid] = camp_entry

		var hoods_var: Variant = c.get("neighbourhoods", [])
		if hoods_var is Array:
			for h_var in hoods_var:
				if not (h_var is Dictionary):
					continue
				var hood_entry: Dictionary = (h_var as Dictionary).duplicate(true)
				hood_entry["kind"] = "hood"
				hood_entry["place_id"] = pid
				area_list.append(hood_entry)
				var hid := str(hood_entry.get("id", ""))
				if not hid.is_empty():
					_areas_by_id[hid] = hood_entry

		_areas_by_place[pid] = area_list

static func has_city(place_id: String) -> bool:
	_ensure_loaded()
	return _cities_by_id.has(place_id)

static func is_ready(place_id: String) -> bool:
	_ensure_loaded()
	if not _cities_by_id.has(place_id):
		return false
	var c: Dictionary = _cities_by_id[place_id]
	var r: Variant = c.get("ready", false)
	return typeof(r) == TYPE_BOOL and bool(r) == true

static func city(place_id: String) -> Dictionary:
	_ensure_loaded()
	if not _cities_by_id.has(place_id):
		return {}
	return (_cities_by_id[place_id] as Dictionary).duplicate(true)

static func areas_of(place_id: String) -> Array:
	_ensure_loaded()
	if not _areas_by_place.has(place_id):
		return []
	var out: Array = []
	for a in _areas_by_place[place_id]:
		out.append((a as Dictionary).duplicate(true))
	return out

static func area(area_id: String) -> Dictionary:
	_ensure_loaded()
	if not _areas_by_id.has(area_id):
		return {}
	return (_areas_by_id[area_id] as Dictionary).duplicate(true)

static func block_origin(area_dict: Dictionary) -> Vector2i:
	var anchor_var: Variant = area_dict.get("anchor", {})
	var anchor: Dictionary = anchor_var if anchor_var is Dictionary else {}
	var lat := float(anchor.get("lat", 0.0))
	var lon := float(anchor.get("lon", 0.0))
	var cells_var: Variant = area_dict.get("cells", [1, 1])
	var cells_arr: Array = cells_var if cells_var is Array else [1, 1]
	var cols: int = int(cells_arr[0]) if cells_arr.size() >= 1 else 1
	var rows: int = int(cells_arr[1]) if cells_arr.size() >= 2 else 1
	var anchor_cell := Grid.latlon_to_cell(lat, lon)
	var half_x: int = int((cols - 1) / 2)
	var half_y: int = int((rows - 1) / 2)
	return anchor_cell - Vector2i(half_x, half_y)

static func block_cells(area_dict: Dictionary) -> Array[Vector2i]:
	var orig := block_origin(area_dict)
	var cells_var: Variant = area_dict.get("cells", [1, 1])
	var cells_arr: Array = cells_var if cells_var is Array else [1, 1]
	var cols: int = int(cells_arr[0]) if cells_arr.size() >= 1 else 1
	var rows: int = int(cells_arr[1]) if cells_arr.size() >= 2 else 1
	var result: Array[Vector2i] = []
	for dy in range(rows):
		for dx in range(cols):
			result.append(Vector2i(orig.x + dx, orig.y + dy))
	return result

static func distance_m(place_id: String, area_id: String) -> float:
	_ensure_loaded()
	_ensure_wayposts_loaded()
	if not _wayposts_by_place.has(place_id) or not _areas_by_id.has(area_id):
		return 0.0
	var wp: Dictionary = _wayposts_by_place[place_id]
	var a: Dictionary = _areas_by_id[area_id]
	var anchor_var: Variant = a.get("anchor", {})
	var anchor: Dictionary = anchor_var if anchor_var is Dictionary else {}
	return Grid.ground_distance_m(
		float(wp.get("lat", 0.0)),
		float(wp.get("lon", 0.0)),
		float(anchor.get("lat", 0.0)),
		float(anchor.get("lon", 0.0))
	)

static func validate_landmark_stamps(place_id: String = "") -> Dictionary:
	_ensure_loaded()
	var known_stamps := {}
	for sid_key in TileSynth2.STAMP_TABLE.keys():
		var sdef: Dictionary = TileSynth2.STAMP_TABLE[sid_key]
		var sname := str(sdef.get("id", ""))
		if not sname.is_empty():
			known_stamps[sname] = true

	var errors: Array[String] = []
	var target_places: Array = [place_id] if not place_id.is_empty() else _cities_by_id.keys()
	for pid in target_places:
		if not _areas_by_place.has(pid):
			errors.append("unknown place_id '%s'" % str(pid))
			continue
		for a_var in _areas_by_place[pid]:
			var a: Dictionary = a_var
			if str(a.get("kind", "")) != "hood":
				continue
			var lms_var: Variant = a.get("landmarks", [])
			if not (lms_var is Array):
				continue
			for lm_var in lms_var:
				if not (lm_var is Dictionary):
					continue
				var lm: Dictionary = lm_var
				if not lm.has("stamp"):
					continue
				var stamp_str := str(lm.get("stamp", ""))
				var is_pending := str(lm.get("art", "")) == "pending"
				if is_pending:
					if known_stamps.has(stamp_str):
						errors.append("%s landmark '%s' marks existing stamp '%s' as pending" % [str(a.get("id", "")), str(lm.get("name", "")), stamp_str])
				else:
					if not known_stamps.has(stamp_str):
						errors.append("%s landmark '%s' has unknown stamp '%s' without art=pending" % [str(a.get("id", "")), str(lm.get("name", "")), stamp_str])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
	}
