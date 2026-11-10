extends RefCounted

# game/world/places_pack.gd — Bundled Places Pack Reader (Item 26)
# Contract: docs/implementation_plan_explore_here.md §2.1

const Grid := preload("res://world/grid.gd")

const DEFAULT_PACK_PATH: String = "res://data/places_pack_v1.json.gz"
const FIXTURE_PACK_PATH: String = "res://tests/fixtures/places_pack_fixture.json.gz"

static var _default_instance: RefCounted = null
static var _active_pack_path: String = DEFAULT_PACK_PATH

var pack_path: String = DEFAULT_PACK_PATH
var _loaded: bool = false
var _version: int = 1
var _snapshot: String = "261001"
var _attribution: String = ""
var _places_by_id: Dictionary = {} # place_id -> Dictionary
var _places_list: Array = []
var _areas_by_key: Dictionary = {} # area_key -> {place_id, kind, name, cell_count}
var _cells_by_area: Dictionary = {} # area_key -> PackedVector2Array

func _init(path: String = "") -> void:
	if not path.is_empty():
		pack_path = path
	else:
		pack_path = _active_pack_path

static func set_active_pack_path(path: String) -> void:
	if _active_pack_path != path:
		_active_pack_path = path
		_default_instance = null

static func reset_active_pack_path() -> void:
	set_active_pack_path(DEFAULT_PACK_PATH)

static func get_default() -> RefCounted:
	if _default_instance == null or _default_instance.pack_path != _active_pack_path:
		var script_res: Script = load("res://world/places_pack.gd")
		_default_instance = script_res.new(_active_pack_path)
		_default_instance.ensure_loaded()
	return _default_instance

static func for_config(config_path: String = "") -> RefCounted:
	var script_res: Script = load("res://world/places_pack.gd")
	if config_path.ends_with("famous_places_fixture.json"):
		var inst = script_res.new(FIXTURE_PACK_PATH)
		inst.ensure_loaded()
		return inst
	return get_default()

static func _read_gzip_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	# Try FileAccess.open_compressed first; standard RFC 1952 .gz files use decompress_dynamic
	var fa := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if fa != null:
		var txt := fa.get_as_text()
		fa.close()
		if not txt.is_empty():
			return txt
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		return ""
	var decomp := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if decomp.is_empty():
		return ""
	return decomp.get_string_from_utf8()

func ensure_loaded() -> bool:
	if _loaded:
		return true
	var path_to_use := pack_path
	if not FileAccess.file_exists(path_to_use) and path_to_use == DEFAULT_PACK_PATH and FileAccess.file_exists(FIXTURE_PACK_PATH):
		path_to_use = FIXTURE_PACK_PATH
	var json_txt := _read_gzip_text(path_to_use)
	if json_txt.is_empty():
		push_error("PlacesPack: failed to read or decompress %s" % path_to_use)
		return false
	var parsed: Variant = JSON.parse_string(json_txt)
	if not (parsed is Dictionary):
		push_error("PlacesPack: invalid JSON root in %s" % path_to_use)
		return false
	var root: Dictionary = parsed
	_version = int(root.get("pack_version", 1))
	_snapshot = str(root.get("snapshot", "261001"))
	_attribution = str(root.get("attribution", ""))
	_places_by_id.clear()
	_places_list.clear()
	_areas_by_key.clear()
	_cells_by_area.clear()

	var places_arr: Array = root.get("places", [])
	for p_var in places_arr:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var
		var pid: String = str(p.get("id", ""))
		var pkind: String = str(p.get("kind", "city"))
		var pname: String = str(p.get("name", ""))
		var areas_arr: Array = p.get("areas", [])
		var rows_arr: Array = p.get("rows", [])

		# Map area index -> key and accumulate cells
		var idx_to_key: Array[String] = []
		var counts_by_key: Dictionary = {}
		for a_var in areas_arr:
			var a: Dictionary = a_var
			var akey: String = str(a.get("key", ""))
			idx_to_key.append(akey)
			counts_by_key[akey] = 0
			_cells_by_area[akey] = PackedVector2Array()

		var all_place_cells := PackedVector2Array()
		var normalized_rows: Array = []

		for r_var in rows_arr:
			var r: Array = r_var
			if r.is_empty():
				continue
			var cy: int = int(r[0])
			var norm_row: Array[int] = [cy]
			var i := 1
			while i + 2 < r.size():
				var cx0: int = int(r[i])
				var run_len: int = int(r[i + 1])
				var a_idx: int = int(r[i + 2])
				norm_row.append(cx0)
				norm_row.append(run_len)
				norm_row.append(a_idx)
				if a_idx >= 0 and a_idx < idx_to_key.size():
					var akey := idx_to_key[a_idx]
					counts_by_key[akey] = int(counts_by_key.get(akey, 0)) + run_len
					var arr: PackedVector2Array = _cells_by_area[akey]
					for dx in range(run_len):
						var pt := Vector2(float(cx0 + dx), float(cy))
						arr.append(pt)
						all_place_cells.append(pt)
					_cells_by_area[akey] = arr
				i += 3
			normalized_rows.append(norm_row)

		var enriched_areas: Array = []
		for a_var in areas_arr:
			var a: Dictionary = a_var
			var akey: String = str(a.get("key", ""))
			var aname: String = str(a.get("name", ""))
			var ccount: int = int(counts_by_key.get(akey, 0))
			var akind := "site" if pkind == "site" else "neighbourhood"
			_areas_by_key[akey] = {
				"area_key": akey,
				"place_id": pid,
				"kind": akind,
				"name": aname,
				"cell_count": ccount
			}
			enriched_areas.append({
				"key": akey,
				"name": aname,
				"kind": akind,
				"cell_count": ccount
			})

		if pkind == "city":
			_areas_by_key[pid] = {
				"area_key": pid,
				"place_id": pid,
				"kind": "city",
				"name": pname,
				"cell_count": all_place_cells.size()
			}
			_cells_by_area[pid] = all_place_cells

		var bbox_raw: Array = p.get("bbox", [0, 0, 0, 0])
		var bbox: Array[int] = [
			int(bbox_raw[0]),
			int(bbox_raw[1]),
			int(bbox_raw[2]),
			int(bbox_raw[3])
		]
		var wp_raw: Dictionary = p.get("waypost", {})
		var wp := {
			"lat": float(wp_raw.get("lat", 0.0)),
			"lon": float(wp_raw.get("lon", 0.0))
		}

		var entry := {
			"id": pid,
			"kind": pkind,
			"name": pname,
			"region": str(p.get("region", "")),
			"waypost": wp,
			"threshold": int(p.get("threshold", 1)),
			"bbox": bbox,
			"areas": enriched_areas,
			"idx_to_key": idx_to_key,
			"rows": normalized_rows,
			"total_cells": all_place_cells.size()
		}
		_places_by_id[pid] = entry
		_places_list.append(entry)

	_loaded = true
	return true

# -------------------------------------------------------------------------
# Instance API
# -------------------------------------------------------------------------

func inst_lookup_cell(cx: int, cy: int) -> Dictionary:
	ensure_loaded()
	for p in _places_list:
		var bbox: Array[int] = p["bbox"]
		if cx < bbox[0] or cx > bbox[2] or cy < bbox[1] or cy > bbox[3]:
			continue
		var rows: Array = p["rows"]
		# Binary search over rows sorted by cy
		var lo := 0
		var hi := rows.size() - 1
		var matched_row: Array = []
		while lo <= hi:
			var mid := (lo + hi) >> 1
			var r: Array = rows[mid]
			var r_cy: int = int(r[0])
			if r_cy == cy:
				matched_row = r
				break
			elif r_cy < cy:
				lo = mid + 1
			else:
				hi = mid - 1
		if matched_row.is_empty():
			continue
		# Binary search over runs in matched_row: [cy, cx0, len, a_idx, ...]
		var num_runs := int((matched_row.size() - 1) / 3)
		var r_lo := 0
		var r_hi := num_runs - 1
		while r_lo <= r_hi:
			var r_mid := (r_lo + r_hi) >> 1
			var base := 1 + r_mid * 3
			var cx0: int = int(matched_row[base])
			var run_len: int = int(matched_row[base + 1])
			var a_idx: int = int(matched_row[base + 2])
			if cx < cx0:
				r_hi = r_mid - 1
			elif cx >= cx0 + run_len:
				r_lo = r_mid + 1
			else:
				var idx_to_key: Array[String] = p["idx_to_key"]
				return {
					"place_id": p["id"],
					"area_key": idx_to_key[a_idx]
				}
	return {}

func inst_area(area_key: String) -> Dictionary:
	ensure_loaded()
	if _areas_by_key.has(area_key):
		return _areas_by_key[area_key].duplicate()
	return {}

func inst_cells_of(area_key: String) -> PackedVector2Array:
	ensure_loaded()
	if _cells_by_area.has(area_key):
		return _cells_by_area[area_key]
	return PackedVector2Array()

func inst_areas_of(place_id: String) -> Array:
	ensure_loaded()
	if _places_by_id.has(place_id):
		return _places_by_id[place_id]["areas"].duplicate(true)
	return []

func inst_threshold(place_id: String) -> int:
	ensure_loaded()
	if _places_by_id.has(place_id):
		return int(_places_by_id[place_id]["threshold"])
	return 1

func inst_waypost(place_id: String) -> Dictionary:
	ensure_loaded()
	if _places_by_id.has(place_id):
		return _places_by_id[place_id]["waypost"].duplicate()
	return {}

func inst_bbox_of(place_id: String) -> Array:
	ensure_loaded()
	if _places_by_id.has(place_id):
		return _places_by_id[place_id]["bbox"].duplicate()
	return []

func inst_place_info(place_id: String) -> Dictionary:
	ensure_loaded()
	if _places_by_id.has(place_id):
		var p: Dictionary = _places_by_id[place_id]
		return {
			"id": p["id"],
			"kind": p["kind"],
			"name": p["name"],
			"region": p["region"],
			"waypost": p["waypost"].duplicate(),
			"threshold": p["threshold"],
			"bbox": p["bbox"].duplicate(),
			"total_cells": p["total_cells"]
		}
	return {}

func inst_has_place(place_id: String) -> bool:
	ensure_loaded()
	return _places_by_id.has(place_id)

func inst_pack_version() -> int:
	ensure_loaded()
	return _version

func inst_nearest_city(lat: float, lon: float) -> String:
	ensure_loaded()
	var best_id := ""
	var best_dist := INF
	for p in _places_list:
		if p["kind"] != "city":
			continue
		var wp: Dictionary = p["waypost"]
		var d := Grid.ground_distance_m(lat, lon, float(wp["lat"]), float(wp["lon"]))
		var pid: String = p["id"]
		if d < best_dist - 1e-6 or (absf(d - best_dist) <= 1e-6 and (best_id == "" or pid < best_id)):
			best_dist = d
			best_id = pid
	return best_id

# -------------------------------------------------------------------------
# Static API (§2.1)
# -------------------------------------------------------------------------

static func lookup_cell(cx: int, cy: int) -> Dictionary:
	return get_default().inst_lookup_cell(cx, cy)

static func area(area_key: String) -> Dictionary:
	return get_default().inst_area(area_key)

static func cells_of(area_key: String) -> PackedVector2Array:
	return get_default().inst_cells_of(area_key)

static func areas_of(place_id: String) -> Array:
	return get_default().inst_areas_of(place_id)

static func threshold(place_id: String) -> int:
	return get_default().inst_threshold(place_id)

static func waypost(place_id: String) -> Dictionary:
	return get_default().inst_waypost(place_id)

static func bbox_of(place_id: String) -> Array:
	return get_default().inst_bbox_of(place_id)

static func place_info(place_id: String) -> Dictionary:
	return get_default().inst_place_info(place_id)

static func has_place(place_id: String) -> bool:
	return get_default().inst_has_place(place_id)

static func pack_version() -> int:
	return get_default().inst_pack_version()

static func nearest_city(lat: float, lon: float) -> String:
	return get_default().inst_nearest_city(lat, lon)
