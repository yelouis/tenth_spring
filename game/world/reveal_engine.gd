extends RefCounted

# reveal_engine.gd — Famous Places & Neighbourhood Reveal Engine v2 (Items 19, 28)
# Contract: docs/implementation_plan_explore_here.md §4.3

const Grid := preload("res://world/grid.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const PlacesPack := preload("res://world/places_pack.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

static func load_places(config_path: String = "") -> Array:
	if not config_path.is_empty():
		if FileAccess.file_exists(config_path):
			var txt := FileAccess.get_file_as_string(config_path)
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Array:
				return parsed
			elif parsed is Dictionary and parsed.has("places") and parsed["places"] is Array:
				return parsed["places"]
		return []

	var out: Array = []
	var seen_ids := {}
	for p in ["res://config/famous_places.json", "res://tests/fixtures/famous_places_fixture.json"]:
		if FileAccess.file_exists(p):
			var txt := FileAccess.get_file_as_string(p)
			var parsed: Variant = JSON.parse_string(txt)
			var list: Array = []
			if parsed is Array:
				list = parsed
			elif parsed is Dictionary and parsed.has("places") and parsed["places"] is Array:
				list = parsed["places"]
			for item in list:
				var i_id: String = str(item.get("id", ""))
				if not seen_ids.has(i_id):
					seen_ids[i_id] = true
					out.append(item)
	return out

static func load_installed_stores(map_data_dir: String = "") -> Dictionary:
	var stores: Dictionary = {}
	var dir_path := map_data_dir
	if dir_path.is_empty():
		var profile := ProfilePaths.resolve_from_cmdline()
		dir_path = str(profile.get("map_data_dir", "user://map_data"))

	if not DirAccess.dir_exists_absolute(dir_path):
		return stores

	var files := DirAccess.get_files_at(dir_path)
	for f in files:
		if f.ends_with(".db") and not f.ends_with(".tmp.db"):
			var store_path := dir_path + "/" + f
			var s := MapStore.new(store_path)
			if s.open_store(false):
				var schema_v: String = s.get_state("schema_version", "")
				if schema_v == "5":
					var pid: String = s.get_state("place_id", "")
					if pid.is_empty():
						pid = f.trim_suffix(".db")
					stores[pid] = s
				else:
					s.close()
			else:
				s.close()
	return stores

static func compute_city_threshold(neighbourhood_count: int) -> int:
	if neighbourhood_count <= 1:
		return 1
	var raw := int(ceili(0.10 * float(neighbourhood_count)))
	return clampi(raw, 2, 5)

static func _reveal_starter_waypost(
	db_inst,
	pack: RefCounted,
	city_id: String,
	ts: int,
	current_reveals: Dictionary,
	current_distort: Dictionary,
	city_unlocked_nbrs: Dictionary
) -> bool:
	if not current_distort.has(city_id):
		if not db_inst.insert_distort_entry(city_id, ts, "starter"):
			return false
		current_distort[city_id] = {"place_id": city_id, "unlocked_at": ts, "reason": "starter"}

	if Neighbourhoods.is_ready(city_id):
		return NeighbourhoodProgress.ensure_camp(db_inst, city_id)

	var wp: Dictionary = pack.inst_waypost(city_id)
	if not wp.is_empty():
		var wp_cell: Vector2i = Grid.latlon_to_cell(float(wp.get("lat", 0.0)), float(wp.get("lon", 0.0)))
		var wp_hit: Dictionary = pack.inst_lookup_cell(wp_cell.x, wp_cell.y)
		var wp_area_key: String = str(wp_hit.get("area_key", ""))
		if not wp_area_key.is_empty() and str(wp_hit.get("place_id", "")) == city_id:
			if not current_reveals.has(wp_area_key):
				db_inst.insert_area_reveal(wp_area_key, "neighbourhood", ts)
				current_reveals[wp_area_key] = {"area_key": wp_area_key, "kind": "neighbourhood", "unlocked_at": ts}
			if not city_unlocked_nbrs.has(city_id):
				city_unlocked_nbrs[city_id] = {}
			city_unlocked_nbrs[city_id][wp_area_key] = true
			var T_home: int = pack.inst_threshold(city_id)
			if city_unlocked_nbrs[city_id].size() >= T_home and not current_reveals.has(city_id):
				db_inst.insert_area_reveal(city_id, "city", ts)
				current_reveals[city_id] = {"area_key": city_id, "kind": "city", "unlocked_at": ts}
	return true

static func apply(db_inst = null, _stores = {}, _places: Array = []) -> Dictionary:
	if db_inst == null:
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree and main_loop.root != null:
			db_inst = main_loop.root.get_node_or_null("/root/DB")
	if db_inst == null or not db_inst.is_open():
		return {"ok": false, "error": "db not open"}

	var pack: RefCounted = PlacesPack.get_default()

	if not db_inst.begin_transaction():
		return {"ok": false, "error": "Failed to begin transaction: " + db_inst.last_error}

	var current_reveals := {}
	for r in db_inst.get_all_area_reveals():
		current_reveals[r["area_key"]] = r

	var current_distort := {}
	for d in db_inst.get_all_distort_entries():
		current_distort[d["place_id"]] = d

	var city_unlocked_nbrs := {}
	for a_key in current_reveals.keys():
		var a_info: Dictionary = pack.inst_area(str(a_key))
		if not a_info.is_empty() and str(a_info.get("kind", "")) == "neighbourhood":
			var pid: String = str(a_info.get("place_id", ""))
			if not city_unlocked_nbrs.has(pid):
				city_unlocked_nbrs[pid] = {}
			city_unlocked_nbrs[pid][str(a_key)] = true

	var existing_starter: String = db_inst.get_db_meta("starter_place", "")
	if not existing_starter.is_empty() and pack.inst_has_place(existing_starter):
		var now_ts := int(Time.get_unix_time_from_system())
		if not _reveal_starter_waypost(
			db_inst, pack, existing_starter, now_ts,
			current_reveals, current_distort, city_unlocked_nbrs
		):
			db_inst.rollback_transaction()
			return {"ok": false, "error": "Failed to reveal starter waypost: " + db_inst.last_error}

	var visit_rows: Array = db_inst._rows("SELECT seq, peer_id, place_id, started_at, kind FROM visit_log WHERE kind IN ('explore', 'home') ORDER BY started_at ASC, peer_id ASC, seq ASC;")

	for row in visit_rows:
		var r_kind: String = str(row.get("kind", ""))
		var r_target: String = str(row.get("place_id", ""))
		var r_ts: int = int(row.get("started_at", 0))
		if r_target.is_empty():
			continue

		if r_kind == "explore":
			var a_info: Dictionary = pack.inst_area(r_target)
			if a_info.is_empty():
				continue
			var a_kind: String = str(a_info.get("kind", ""))
			var pid: String = str(a_info.get("place_id", ""))

			if a_kind == "neighbourhood":
				if Neighbourhoods.is_ready(pid):
					if not current_distort.has(pid):
						if not db_inst.insert_distort_entry(pid, r_ts, "visited"):
							db_inst.rollback_transaction()
							return {"ok": false, "error": "Failed to insert distort entry: " + db_inst.last_error}
						current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}
					if not NeighbourhoodProgress.ensure_camp(db_inst, pid):
						db_inst.rollback_transaction()
						return {"ok": false, "error": "Failed to ensure camp: " + db_inst.last_error}
				else:
					if not current_reveals.has(r_target):
						db_inst.insert_area_reveal(r_target, "neighbourhood", r_ts)
						current_reveals[r_target] = {"area_key": r_target, "kind": "neighbourhood", "unlocked_at": r_ts}

					if not city_unlocked_nbrs.has(pid):
						city_unlocked_nbrs[pid] = {}
					city_unlocked_nbrs[pid][r_target] = true

					if not current_distort.has(pid):
						db_inst.insert_distort_entry(pid, r_ts, "visited")
						current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}

					var T: int = pack.inst_threshold(pid)
					if city_unlocked_nbrs[pid].size() >= T and not current_reveals.has(pid):
						db_inst.insert_area_reveal(pid, "city", r_ts)
						current_reveals[pid] = {"area_key": pid, "kind": "city", "unlocked_at": r_ts}

			elif a_kind == "site":
				if not current_reveals.has(r_target):
					db_inst.insert_area_reveal(r_target, "site", r_ts)
					current_reveals[r_target] = {"area_key": r_target, "kind": "site", "unlocked_at": r_ts}
				if not current_distort.has(pid):
					db_inst.insert_distort_entry(pid, r_ts, "visited")
					current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}

		elif r_kind == "home":
			var p_info: Dictionary = pack.inst_place_info(r_target)
			if p_info.is_empty() or str(p_info.get("kind", "")) != "city":
				continue
			if not _reveal_starter_waypost(
				db_inst, pack, r_target, r_ts,
				current_reveals, current_distort, city_unlocked_nbrs
			):
				db_inst.rollback_transaction()
				return {"ok": false, "error": "Failed to reveal home starter: " + db_inst.last_error}
			db_inst.set_db_meta("starter_place", r_target)

	var all_reveals: Array = db_inst.get_all_area_reveals()
	for a_row in all_reveals:
		var a_key: String = str(a_row.get("area_key", ""))
		var a_chk_info: Dictionary = pack.inst_area(a_key)
		var a_chk_pid: String = str(a_chk_info.get("place_id", "")) if not a_chk_info.is_empty() else a_key
		if Neighbourhoods.is_ready(a_chk_pid):
			continue
		var cells: PackedVector2Array = pack.inst_cells_of(a_key)
		for pt in cells:
			db_inst.upsert_map_cell(int(pt.x), int(pt.y), 1)

	db_inst.commit_transaction()

	return {
		"ok": true,
		"revealed_areas": db_inst.get_all_area_reveals(),
		"distort_places": db_inst.get_all_distort_entries()
	}
