class_name NeighbourhoodProgress
extends RefCounted

## game/world/neighbourhood_progress.gd — Caricature City & Neighbourhood Unlocking Rules (Item 50)
## Contract: docs/design_neighbourhoods_and_caricature.md §2–§4;
##           docs/implementation_plan_dc_trial.md §7.2, §7.4, §7.5

const Grid := preload("res://world/grid.gd")
const CellClassifier := preload("res://world/cell_classifier.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")

const METERS_PER_MILE: float = 1609.344

## Card type summary per spawn zone (new; from design_encounters_and_haunted_zones.md §2, plan §7.5)
const ZONE_CARD_TYPES: Dictionary = {
	"residential": "Normal, Flying",
	"downtown": "Psychic, Steel",
	"industrial": "Poison, Steel, Electric",
	"retail": "Normal",
	"parkland": "Grass, Bug",
	"waterfront": "Water",
	"institutional": "Psychic",
	"wilds": "Varied",
	"cemetery": "Ghost",
	"ruins": "Ghost",
	"hospital": "Ghost",
}

## Night danger thresholds on night ghost share g = min(0.80, ZONE_BASE_GHOST_SHARE[zone] * 3.0) (new; plan §7.5)
const NIGHT_GHOST_CAP: float = 0.80
const NIGHT_GHOST_MULTIPLIER: float = 3.0
const NIGHT_HIGH_THRESHOLD: float = 0.40
const NIGHT_MEDIUM_THRESHOLD: float = 0.20

static var _demo_override_for_tests: int = -1 # -1 = use ProfilePaths.resolve_from_cmdline().is_demo

static func set_demo_override_for_tests(val: int) -> void:
	_demo_override_for_tests = val

static func is_demo_profile() -> bool:
	if _demo_override_for_tests >= 0:
		return _demo_override_for_tests > 0
	var prof: Dictionary = ProfilePaths.resolve_from_cmdline()
	return bool(prof.get("is_demo", false))

static func _get_config() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		return (ml as SceneTree).root.get_node_or_null("/root/Config")
	return null

static func _first_picks() -> int:
	var cfg := _get_config()
	if cfg != null and "first_picks" in cfg:
		return int(cfg.get("first_picks"))
	return 2

static func _finale_requires_finished() -> int:
	var cfg := _get_config()
	if cfg != null and "finale_requires_finished" in cfg:
		return int(cfg.get("finale_requires_finished"))
	return 5

static func _walk_speed_mph() -> float:
	var cfg := _get_config()
	if cfg != null and "walk_speed_mph" in cfg:
		var v := float(cfg.get("walk_speed_mph"))
		if v > 0.0:
			return v
	return 15.0

static func night_danger(area_dict: Dictionary) -> String:
	var haunt_site := str(area_dict.get("haunt_site", ""))
	var zone := str(area_dict.get("zone", "residential"))
	var base_g := float(CellClassifier.ZONE_BASE_GHOST_SHARE.get(zone, 0.05))
	var g := minf(NIGHT_GHOST_CAP, base_g * NIGHT_GHOST_MULTIPLIER)
	if not haunt_site.is_empty() or g > NIGHT_HIGH_THRESHOLD:
		return "high"
	if g >= NIGHT_MEDIUM_THRESHOLD:
		return "medium"
	return "low"

static func trip_minutes(_place_id: String, from_area_id: String, to_area_id: String) -> int:
	var a1: Dictionary = Neighbourhoods.area(from_area_id)
	var a2: Dictionary = Neighbourhoods.area(to_area_id)
	if a1.is_empty() or a2.is_empty():
		return 1
	var anch1: Dictionary = a1.get("anchor", {}) if a1.get("anchor") is Dictionary else {}
	var anch2: Dictionary = a2.get("anchor", {}) if a2.get("anchor") is Dictionary else {}
	var dist_m := Grid.ground_distance_m(
		float(anch1.get("lat", 0.0)),
		float(anch1.get("lon", 0.0)),
		float(anch2.get("lat", 0.0)),
		float(anch2.get("lon", 0.0))
	)
	var miles := dist_m / METERS_PER_MILE
	var game_minutes_per_mile := 60.0 / _walk_speed_mph()
	return maxi(1, int(ceili(miles * game_minutes_per_mile)))

static func _states_by_area(db, place_id: String) -> Dictionary:
	var out: Dictionary = {}
	if db == null or not db.is_open():
		return out
	var rows: Array = db.get_neighbourhood_states(place_id)
	for r_var in rows:
		if r_var is Dictionary:
			var r: Dictionary = r_var
			var aid := str(r.get("area_id", ""))
			if not aid.is_empty():
				out[aid] = r
	return out

static func _finished_non_finale_count(states_by_id: Dictionary, city_dict: Dictionary) -> int:
	var count := 0
	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if not (hoods_var is Array):
		return 0
	for h_var in hoods_var:
		if not (h_var is Dictionary):
			continue
		var h: Dictionary = h_var
		if str(h.get("role", "")) == "finale":
			continue
		var hid := str(h.get("id", ""))
		if states_by_id.has(hid) and int((states_by_id[hid] as Dictionary).get("state", 0)) >= 3:
			count += 1
	return count

static func _begin_tx(db) -> Dictionary:
	if db == null or not db.is_open():
		return {"ok": false, "owned": false, "error": "db not open"}
	if bool(db.get("_in_transaction")):
		return {"ok": true, "owned": false, "error": ""}
	if not db.begin_transaction():
		return {"ok": false, "owned": false, "error": str(db.last_error)}
	return {"ok": true, "owned": true, "error": ""}

static func _end_tx(db, owned: bool, ok: bool) -> bool:
	if not owned:
		return ok
	if ok:
		return db.commit_transaction()
	db.rollback_transaction()
	return false

static func _reveal_area_cells(db, area_dict: Dictionary, reveal_state: int) -> bool:
	var place_id := str(area_dict.get("place_id", ""))
	var is_camp := str(area_dict.get("kind", "")) == "camp" or str(area_dict.get("id", "")).begins_with("camp:")
	var zone_str := "residential" if is_camp else str(area_dict.get("zone", "residential"))
	var biome_str := CellClassifier.place_baseline_biome(place_id)
	var cells: Array[Vector2i] = Neighbourhoods.block_cells(area_dict)
	for cell in cells:
		var reg_info: Dictionary = CellClassifier.resolve_region_and_place(cell.x, cell.y, place_id)
		var region_str := str(reg_info.get("region", "South Atlantic"))
		db.upsert_map_cell(cell.x, cell.y, reveal_state)
		if not str(db.last_error).is_empty():
			return false
		if not db.upsert_map_cell_metadata(cell.x, cell.y, zone_str, biome_str, region_str, 0):
			return false
	return true

static func ensure_camp(db, place_id: String) -> bool:
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	if city_dict.is_empty():
		return false
	var camp_var: Variant = city_dict.get("camp", {})
	if not (camp_var is Dictionary):
		return false
	var camp_id := str((camp_var as Dictionary).get("id", ""))
	if camp_id.is_empty():
		return false
	var area_dict: Dictionary = Neighbourhoods.area(camp_id)
	if area_dict.is_empty():
		return false

	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return false
	var owned := bool(tx["owned"])

	var existing: Dictionary = db.get_neighbourhood_state(camp_id)
	if existing.is_empty():
		var now := int(Time.get_unix_time_from_system())
		if not db.upsert_neighbourhood_state(camp_id, place_id, 1, "camp", now):
			_end_tx(db, owned, false)
			return false

	if not _reveal_area_cells(db, area_dict, 2):
		_end_tx(db, owned, false)
		return false

	return _end_tx(db, owned, true)

static func first_picks_left(db, place_id: String) -> int:
	if db == null or not db.is_open():
		return 0
	var used := 0
	for r_var in db.get_neighbourhood_states(place_id):
		if r_var is Dictionary and str((r_var as Dictionary).get("opened_by", "")) == "first_pick":
			used += 1
	return maxi(0, _first_picks() - used)

static func picks_left(db, place_id: String) -> int:
	if db == null or not db.is_open():
		return 0
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	if city_dict.is_empty():
		return 0
	var states_by_id := _states_by_area(db, place_id)
	var finished_count := _finished_non_finale_count(states_by_id, city_dict)
	var used_picks := 0
	for r_var in states_by_id.values():
		if r_var is Dictionary and str((r_var as Dictionary).get("opened_by", "")) == "pick":
			used_picks += 1
	return maxi(0, finished_count - used_picks)

static func openable(db, place_id: String) -> Array[String]:
	var out: Array[String] = []
	if db == null or not db.is_open():
		return out
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	if city_dict.is_empty():
		return out
	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if not (hoods_var is Array):
		return out
	var states_by_id := _states_by_area(db, place_id)

	if first_picks_left(db, place_id) > 0:
		for h_var in hoods_var:
			if not (h_var is Dictionary):
				continue
			var h: Dictionary = h_var
			var hid := str(h.get("id", ""))
			if str(h.get("role", "")) == "gateway" and not states_by_id.has(hid):
				out.append(hid)
		return out

	if picks_left(db, place_id) > 0:
		for h_var in hoods_var:
			if not (h_var is Dictionary):
				continue
			var h: Dictionary = h_var
			var hid := str(h.get("id", ""))
			var role := str(h.get("role", ""))
			if states_by_id.has(hid) or role == "finale":
				continue
			if role == "gateway":
				out.append(hid)
			elif role == "inner":
				var borders_var: Variant = h.get("borders", [])
				if borders_var is Array:
					for b_var in borders_var:
						if states_by_id.has(str(b_var)):
							out.append(hid)
							break
		return out

	return out

static func open(db, area_id: String) -> Dictionary:
	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	if area_dict.is_empty() or str(area_dict.get("kind", "")) != "hood":
		return {"ok": false, "error": "not openable"}
	var place_id := str(area_dict.get("place_id", ""))
	var allowed := openable(db, place_id)
	if not (area_id in allowed):
		return {"ok": false, "error": "not openable"}

	var opened_by := "first_pick" if first_picks_left(db, place_id) > 0 else "pick"
	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return {"ok": false, "error": str(tx["error"])}
	var owned := bool(tx["owned"])

	var now := int(Time.get_unix_time_from_system())
	if not db.upsert_neighbourhood_state(area_id, place_id, 1, opened_by, now):
		var err1 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err1}

	if not _reveal_area_cells(db, area_dict, 1):
		var err2 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err2}

	if not _open_ready_routes_in_tx(db, place_id, now):
		var err3 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err3}

	if not _end_tx(db, owned, true):
		return {"ok": false, "error": str(db.last_error)}
	return {"ok": true, "opened_by": opened_by}

static func enter(db, area_id: String) -> bool:
	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	if area_dict.is_empty() or str(area_dict.get("kind", "")) != "hood":
		return false
	if db == null or not db.is_open():
		return false
	var existing: Dictionary = db.get_neighbourhood_state(area_id)
	if existing.is_empty():
		return false

	var place_id := str(area_dict.get("place_id", ""))
	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return false
	var owned := bool(tx["owned"])

	var now := int(Time.get_unix_time_from_system())
	if not db.upsert_neighbourhood_state(area_id, place_id, 2, str(existing.get("opened_by", "pick")), now):
		_end_tx(db, owned, false)
		return false

	if not _reveal_area_cells(db, area_dict, 2):
		_end_tx(db, owned, false)
		return false

	return _end_tx(db, owned, true)

static func finish(db, area_id: String) -> Dictionary:
	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	if area_dict.is_empty() or str(area_dict.get("kind", "")) != "hood":
		return {"ok": false, "error": "unknown neighbourhood", "finale_opened": false, "city_complete": false}
	if db == null or not db.is_open():
		return {"ok": false, "error": "db not open", "finale_opened": false, "city_complete": false}
	var existing: Dictionary = db.get_neighbourhood_state(area_id)
	if existing.is_empty() or int(existing.get("state", 0)) < 2:
		return {"ok": false, "error": "not entered", "finale_opened": false, "city_complete": false}

	var place_id := str(area_dict.get("place_id", ""))
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return {"ok": false, "error": str(tx["error"]), "finale_opened": false, "city_complete": false}
	var owned := bool(tx["owned"])

	var now := int(Time.get_unix_time_from_system())
	if not db.upsert_neighbourhood_state(area_id, place_id, 3, str(existing.get("opened_by", "pick")), now):
		var err1 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err1, "finale_opened": false, "city_complete": false}

	var states_by_id := _states_by_area(db, place_id)
	var finished_non_finale := _finished_non_finale_count(states_by_id, city_dict)

	var finale_id := ""
	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if hoods_var is Array:
		for h_var in hoods_var:
			if h_var is Dictionary and str((h_var as Dictionary).get("role", "")) == "finale":
				finale_id = str((h_var as Dictionary).get("id", ""))
				break

	var finale_opened := false
	if not finale_id.is_empty() and not states_by_id.has(finale_id) and finished_non_finale >= _finale_requires_finished():
		var finale_area: Dictionary = Neighbourhoods.area(finale_id)
		if not db.upsert_neighbourhood_state(finale_id, place_id, 1, "finale", now):
			var err2 := str(db.last_error)
			_end_tx(db, owned, false)
			return {"ok": false, "error": err2, "finale_opened": false, "city_complete": false}
		if not _reveal_area_cells(db, finale_area, 1):
			var err3 := str(db.last_error)
			_end_tx(db, owned, false)
			return {"ok": false, "error": err3, "finale_opened": false, "city_complete": false}
		if not _open_ready_routes_in_tx(db, place_id, now):
			var err4 := str(db.last_error)
			_end_tx(db, owned, false)
			return {"ok": false, "error": err4, "finale_opened": false, "city_complete": false}
		finale_opened = true
		states_by_id = _states_by_area(db, place_id)

	var is_complete := false
	if not finale_id.is_empty() and states_by_id.has(finale_id):
		is_complete = int((states_by_id[finale_id] as Dictionary).get("state", 0)) == 3

	if not _end_tx(db, owned, true):
		return {"ok": false, "error": str(db.last_error), "finale_opened": false, "city_complete": false}
	return {"ok": true, "finale_opened": finale_opened, "city_complete": is_complete}

static func city_complete(db, place_id: String) -> bool:
	if db == null or not db.is_open():
		return false
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	if city_dict.is_empty():
		return false
	var hoods_var: Variant = city_dict.get("neighbourhoods", [])
	if not (hoods_var is Array):
		return false
	for h_var in hoods_var:
		if h_var is Dictionary and str((h_var as Dictionary).get("role", "")) == "finale":
			var fid := str((h_var as Dictionary).get("id", ""))
			var row: Dictionary = db.get_neighbourhood_state(fid)
			return not row.is_empty() and int(row.get("state", 0)) == 3
	return false

static func _reveal_route_cells(db, route_dict: Dictionary, reveal_state: int) -> bool:
	var rid := str(route_dict.get("id", ""))
	var legs_var: Variant = route_dict.get("legs", [])
	if not (legs_var is Array):
		return true
	for idx in range((legs_var as Array).size()):
		var leg_id := "%s#%d" % [rid, idx + 1]
		var leg_area: Dictionary = Neighbourhoods.area(leg_id)
		if leg_area.is_empty():
			continue
		if not _reveal_area_cells(db, leg_area, reveal_state):
			return false
	return true

static func _open_ready_routes_in_tx(db, place_id: String, now: int) -> bool:
	var routes: Array = Neighbourhoods.routes_of(place_id)
	if routes.is_empty():
		return true
	var states_by_id := _states_by_area(db, place_id)
	for r_var in routes:
		if not (r_var is Dictionary):
			continue
		var r: Dictionary = r_var
		var rid := str(r.get("id", ""))
		if rid.is_empty() or states_by_id.has(rid):
			continue
		var ends_var: Variant = r.get("ends", [])
		if not (ends_var is Array) or (ends_var as Array).size() != 2:
			continue
		var e0 := str((ends_var as Array)[0])
		var e1 := str((ends_var as Array)[1])
		if states_by_id.has(e0) and states_by_id.has(e1):
			if not db.upsert_neighbourhood_state(rid, place_id, 1, "route", now):
				return false
			if not _reveal_route_cells(db, r, 1):
				return false
			states_by_id[rid] = {"area_id": rid, "state": 1, "opened_by": "route"}
	return true

static func can_go(db, area_id: String) -> bool:
	if db == null or not db.is_open():
		return false
	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	if area_dict.is_empty():
		return false
	var kind := str(area_dict.get("kind", ""))
	if kind == "camp" or area_id.begins_with("camp:"):
		return true
	if kind != "hood":
		return false
	var row: Dictionary = db.get_neighbourhood_state(area_id)
	if row.is_empty():
		return false
	if str(area_dict.get("role", "")) == "gateway":
		return true
	return int(row.get("state", 0)) >= 2

static func walk_from(db, area_id: String) -> Array[String]:
	var out: Array[String] = []
	if db == null or not db.is_open():
		return out
	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	if area_dict.is_empty():
		return out
	var place_id := str(area_dict.get("place_id", ""))
	var states_by_id := _states_by_area(db, place_id)
	for r_var in Neighbourhoods.routes_at(area_id):
		if not (r_var is Dictionary):
			continue
		var r: Dictionary = r_var
		var rid := str(r.get("id", ""))
		if not states_by_id.has(rid) or int((states_by_id[rid] as Dictionary).get("state", 0)) < 1:
			continue
		var ends_var: Variant = r.get("ends", [])
		if not (ends_var is Array) or (ends_var as Array).size() != 2:
			continue
		var e0 := str((ends_var as Array)[0])
		var e1 := str((ends_var as Array)[1])
		var other_id := e1 if e0 == area_id else e0
		if states_by_id.has(other_id) and int((states_by_id[other_id] as Dictionary).get("state", 0)) >= 2:
			out.append(rid)
	return out

static func walk_route(db, route_id: String, from_area_id: String) -> Dictionary:
	if db == null or not db.is_open():
		return {"ok": false, "error": "db not open", "arrived_at": ""}
	var route_dict: Dictionary = Neighbourhoods.route(route_id)
	if route_dict.is_empty():
		return {"ok": false, "error": "unknown route", "arrived_at": ""}
	var route_row: Dictionary = db.get_neighbourhood_state(route_id)
	if route_row.is_empty() or int(route_row.get("state", 0)) < 1:
		return {"ok": false, "error": "route not open", "arrived_at": ""}
	var ends_var: Variant = route_dict.get("ends", [])
	if not (ends_var is Array) or (ends_var as Array).size() != 2:
		return {"ok": false, "error": "invalid route ends", "arrived_at": ""}
	var e0 := str((ends_var as Array)[0])
	var e1 := str((ends_var as Array)[1])
	if from_area_id != e0 and from_area_id != e1:
		return {"ok": false, "error": "not an end of route", "arrived_at": ""}
	var from_row: Dictionary = db.get_neighbourhood_state(from_area_id)
	if from_row.is_empty() or int(from_row.get("state", 0)) < 2:
		return {"ok": false, "error": "origin not entered", "arrived_at": ""}
	var other_id := e1 if from_area_id == e0 else e0
	var other_row: Dictionary = db.get_neighbourhood_state(other_id)
	if other_row.is_empty():
		return {"ok": false, "error": "destination not open", "arrived_at": ""}
	var other_area: Dictionary = Neighbourhoods.area(other_id)
	if other_area.is_empty():
		return {"ok": false, "error": "unknown destination", "arrived_at": ""}

	var place_id := str(route_dict.get("place_id", str(other_area.get("place_id", ""))))
	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return {"ok": false, "error": str(tx["error"]), "arrived_at": ""}
	var owned := bool(tx["owned"])
	var now := int(Time.get_unix_time_from_system())

	if not db.upsert_neighbourhood_state(route_id, place_id, maxi(2, int(route_row.get("state", 1))), str(route_row.get("opened_by", "route")), now):
		var err1 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err1, "arrived_at": ""}
	if not _reveal_route_cells(db, route_dict, 2):
		var err2 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err2, "arrived_at": ""}
	if not db.upsert_neighbourhood_state(other_id, place_id, maxi(2, int(other_row.get("state", 1))), str(other_row.get("opened_by", "pick")), now):
		var err3 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err3, "arrived_at": ""}
	if not _reveal_area_cells(db, other_area, 2):
		var err4 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err4, "arrived_at": ""}

	if not _end_tx(db, owned, true):
		return {"ok": false, "error": str(db.last_error), "arrived_at": ""}
	return {"ok": true, "arrived_at": other_id}

static func demo_force_open(db, area_id: String) -> Dictionary:
	if not is_demo_profile():
		return {"ok": false, "error": "demo only"}
	if db == null or not db.is_open():
		return {"ok": false, "error": "db not open"}

	var area_dict: Dictionary = Neighbourhoods.area(area_id)
	var direct_route: Dictionary = Neighbourhoods.route(area_id) if area_dict.is_empty() else {}
	if area_dict.is_empty() and direct_route.is_empty():
		return {"ok": false, "error": "unknown area"}

	var tx := _begin_tx(db)
	if not bool(tx["ok"]):
		return {"ok": false, "error": str(tx["error"])}
	var owned := bool(tx["owned"])
	var now := int(Time.get_unix_time_from_system())

	if not direct_route.is_empty() or str(area_dict.get("kind", "")) == "route":
		var route_id := str(direct_route.get("id", "")) if not direct_route.is_empty() else str(area_dict.get("route_id", area_id))
		var r_dict: Dictionary = direct_route if not direct_route.is_empty() else Neighbourhoods.route(route_id)
		var r_place_id := str(r_dict.get("place_id", str(area_dict.get("place_id", ""))))
		if not db.upsert_neighbourhood_state(route_id, r_place_id, 2, "demo", now):
			var r_err1 := str(db.last_error)
			_end_tx(db, owned, false)
			return {"ok": false, "error": r_err1}
		if not _reveal_route_cells(db, r_dict, 2):
			var r_err2 := str(db.last_error)
			_end_tx(db, owned, false)
			return {"ok": false, "error": r_err2}
		if not _end_tx(db, owned, true):
			return {"ok": false, "error": str(db.last_error)}
		return {"ok": true}

	var place_id := str(area_dict.get("place_id", ""))
	var is_camp := str(area_dict.get("kind", "")) == "camp" or area_id.begins_with("camp:")
	var opened_by := "camp" if is_camp else "demo"
	var target_state := 1 if is_camp else 2

	if not db.upsert_neighbourhood_state(area_id, place_id, target_state, opened_by, now):
		var err1 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err1}

	if not _reveal_area_cells(db, area_dict, 2):
		var err2 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err2}

	if not is_camp and not _open_ready_routes_in_tx(db, place_id, now):
		var err3 := str(db.last_error)
		_end_tx(db, owned, false)
		return {"ok": false, "error": err3}

	if not _end_tx(db, owned, true):
		return {"ok": false, "error": str(db.last_error)}
	return {"ok": true}
