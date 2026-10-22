extends RefCounted

# reveal_engine.gd — Famous Places & Neighbourhood Reveal Engine (Item 19)
# Contract: docs/implementation_plan_famous_places.md §4, Decisions 21=B, 22=A, 25, 26

const Grid := preload("res://world/grid.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")

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
				if schema_v == "4":
					var pid: String = s.get_state("place_id", "")
					if pid.is_empty():
						pid = f.trim_suffix(".db")
					stores[pid] = s
				else:
					s.close()
			else:
				s.close()
	return stores

static func _normalize_stores(stores) -> Dictionary:
	var out: Dictionary = {}
	if stores is Dictionary and not stores.is_empty():
		out = stores.duplicate()
	elif stores is Array and not stores.is_empty():
		for s in stores:
			if s != null and s is MapStore:
				var pid: String = s.get_state("place_id", "")
				if pid.is_empty():
					pid = s.db_path.get_file().trim_suffix(".db")
				out[pid] = s
	else:
		out = load_installed_stores()
	return out

static func _normalize_places(places: Array) -> Array:
	if not places.is_empty():
		return places
	return load_places()

static func compute_city_threshold(neighbourhood_count: int) -> int:
	if neighbourhood_count <= 1:
		return 1
	var raw := int(ceili(0.10 * float(neighbourhood_count)))
	return clampi(raw, 2, 5)

static func designate_home(db_inst, stores = {}, places: Array = [], home_cell: Vector2i = Vector2i.ZERO) -> Dictionary:
	if db_inst == null or not db_inst.is_open():
		return {"ok": false, "error": "db not open"}

	var stores_dict: Dictionary = _normalize_stores(stores)
	var places_arr: Array = _normalize_places(places)

	# 1. Store meta('home_cell', '<cx>,<cy>')
	var home_str := "%d,%d" % [home_cell.x, home_cell.y]
	db_inst.set_db_meta("home_cell", home_str)

	# 2. Centre of home cell in WM coordinates -> Lat/Lon
	var home_center_wm := Vector2((float(home_cell.x) + 0.5) * Grid.CELL_WM, (float(home_cell.y) + 0.5) * Grid.CELL_WM)
	var home_ll := Grid.wm_to_latlon(home_center_wm)
	var home_lat: float = home_ll.x
	var home_lon: float = home_ll.y

	# 3. Find starter city: nearest famous city's Waypost by ground_distance_m (ties to lower id)
	var best_dist := INF
	var best_city_id := ""
	var best_wp_lat := 0.0
	var best_wp_lon := 0.0

	for pl in places_arr:
		if str(pl.get("kind", "")) != "city":
			continue
		var cid: String = str(pl.get("id", ""))
		var wp: Dictionary = pl.get("waypost", {})
		var w_lat := float(wp.get("lat", 0.0))
		var w_lon := float(wp.get("lon", 0.0))
		var d: float = Grid.ground_distance_m(home_lat, home_lon, w_lat, w_lon)
		if d < best_dist or (is_equal_approx(d, best_dist) and (best_city_id == "" or cid < best_city_id)):
			best_dist = d
			best_city_id = cid
			best_wp_lat = w_lat
			best_wp_lon = w_lon

	if best_city_id.is_empty():
		return {"ok": false, "error": "No famous cities found in places"}

	var now := int(Time.get_unix_time_from_system())

	# 4. Insert starter city into distort_list with reason 'starter'
	db_inst.insert_distort_entry(best_city_id, now, "starter")

	# 5. Insert the neighbourhood containing its Waypost into area_reveal
	var wp_cell := Grid.latlon_to_cell(best_wp_lat, best_wp_lon)
	var starter_store: MapStore = stores_dict.get(best_city_id, null)
	var wp_area_key := ""
	if starter_store != null:
		var wp_ca: Dictionary = starter_store.get_cell_area(wp_cell.x, wp_cell.y)
		if not wp_ca.is_empty():
			wp_area_key = str(wp_ca.get("area_key", ""))
			var wp_kind: String = str(wp_ca.get("kind", "neighbourhood"))
			db_inst.insert_area_reveal(wp_area_key, wp_kind, now)
			# Reveal all cells of this neighbourhood
			var cells: Array = starter_store.get_cells_for_area(wp_area_key)
			for c in cells:
				db_inst.upsert_map_cell(int(c["cell_x"]), int(c["cell_y"]), 1)

	return {
		"ok": true,
		"home_cell": home_cell,
		"starter_city": best_city_id,
		"waypost_area_key": wp_area_key
	}

static func apply(db_inst = null, stores = {}, places: Array = []) -> Dictionary:
	if db_inst == null:
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree and main_loop.root != null:
			db_inst = main_loop.root.get_node_or_null("/root/DB")
	if db_inst == null or not db_inst.is_open():
		return {"ok": false, "error": "db not open"}

	var stores_dict: Dictionary = _normalize_stores(stores)
	var places_arr: Array = _normalize_places(places)

	# Cache areas info per store
	var store_areas := {} # store -> { area_key -> {kind, name, cell_count} }
	var city_nbr_counts := {} # city_id -> int (total neighbourhoods n)
	for pid in stores_dict.keys():
		var s: MapStore = stores_dict[pid]
		var a_list := s.get_areas()
		var a_map := {}
		var nbr_c := 0
		for a in a_list:
			a_map[a["area_key"]] = a
			if a["kind"] == "neighbourhood":
				nbr_c += 1
		store_areas[pid] = a_map
		city_nbr_counts[pid] = nbr_c

	# Begin transaction for atomic apply
	if not db_inst.begin_transaction():
		return {"ok": false, "error": "Failed to begin transaction: " + db_inst.last_error}

	# Check home starter designation if home_cell set
	var home_str: String = db_inst.get_db_meta("home_cell", "")
	if not home_str.is_empty():
		var parts := home_str.split(",")
		if parts.size() >= 2:
			var hc := Vector2i(int(parts[0]), int(parts[1]))
			designate_home(db_inst, stores_dict, places_arr, hc)

	# Load current area_reveal and distort_list
	var current_reveals := {}
	for r in db_inst.get_all_area_reveals():
		current_reveals[r["area_key"]] = r

	var current_distort := {}
	for d in db_inst.get_all_distort_entries():
		current_distort[d["place_id"]] = d

	# Track unlocked neighbourhoods per city
	var city_unlocked_nbrs := {}
	for a_key in current_reveals.keys():
		for pid in stores_dict.keys():
			var a_map: Dictionary = store_areas.get(pid, {})
			if a_map.has(a_key) and a_map[a_key]["kind"] == "neighbourhood":
				if not city_unlocked_nbrs.has(pid):
					city_unlocked_nbrs[pid] = {}
				city_unlocked_nbrs[pid][a_key] = true

	# Read all visit_log rows in (started_at, peer_id, seq) order
	var visit_rows: Array = db_inst._rows("SELECT seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind FROM visit_log ORDER BY started_at ASC, peer_id ASC, seq ASC;")

	for row in visit_rows:
		var r_lat: float = float(row.get("lat", 0.0))
		var r_lon: float = float(row.get("lon", 0.0))
		var r_ts: int = int(row.get("started_at", 0))
		var cell := Grid.latlon_to_cell(r_lat, r_lon)

		for pid in stores_dict.keys():
			var s: MapStore = stores_dict[pid]
			if not s.covers_cell(cell.x, cell.y):
				continue
			var ca: Dictionary = s.get_cell_area(cell.x, cell.y)
			if ca.is_empty():
				continue

			var area_key: String = str(ca.get("area_key", ""))
			var a_kind: String = str(ca.get("kind", ""))

			if a_kind == "neighbourhood":
				if not current_reveals.has(area_key):
					db_inst.insert_area_reveal(area_key, "neighbourhood", r_ts)
					current_reveals[area_key] = {"area_key": area_key, "kind": "neighbourhood", "unlocked_at": r_ts}

				if not city_unlocked_nbrs.has(pid):
					city_unlocked_nbrs[pid] = {}
				city_unlocked_nbrs[pid][area_key] = true

				# City goes on distort_list when any neighbourhood is visited
				if not current_distort.has(pid):
					db_inst.insert_distort_entry(pid, r_ts, "visited")
					current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}

				# City threshold (Rule 3)
				var total_nbrs: int = int(city_nbr_counts.get(pid, 0))
				var T := compute_city_threshold(total_nbrs)
				if city_unlocked_nbrs[pid].size() >= T:
					if not current_reveals.has(pid):
						db_inst.insert_area_reveal(pid, "city", r_ts)
						current_reveals[pid] = {"area_key": pid, "kind": "city", "unlocked_at": r_ts}

			elif a_kind == "city":
				if not current_distort.has(pid):
					db_inst.insert_distort_entry(pid, r_ts, "visited")
					current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}
				if not current_reveals.has(pid):
					db_inst.insert_area_reveal(pid, "city", r_ts)
					current_reveals[pid] = {"area_key": pid, "kind": "city", "unlocked_at": r_ts}

			elif a_kind == "site":
				if not current_distort.has(pid):
					db_inst.insert_distort_entry(pid, r_ts, "visited")
					current_distort[pid] = {"place_id": pid, "unlocked_at": r_ts, "reason": "visited"}
				if not current_reveals.has(pid):
					db_inst.insert_area_reveal(pid, "site", r_ts)
					current_reveals[pid] = {"area_key": pid, "kind": "site", "unlocked_at": r_ts}

	# Reveal cells for all active reveals (Rule 4)
	# Every area_cells cell of each area in area_reveal -> upsert_map_cell(cx, cy, 1)
	var all_reveals: Array = db_inst.get_all_area_reveals()
	for a_row in all_reveals:
		var a_key: String = str(a_row.get("area_key", ""))
		var a_kind: String = str(a_row.get("kind", ""))
		for pid in stores_dict.keys():
			var s: MapStore = stores_dict[pid]
			var a_map: Dictionary = store_areas.get(pid, {})
			if a_kind == "city" and a_key == pid:
				var c_cells: Array = s._rows("SELECT cell_x, cell_y FROM area_cells;")
				for c in c_cells:
					db_inst.upsert_map_cell(int(c["cell_x"]), int(c["cell_y"]), 1)
			elif a_map.has(a_key):
				var c_cells: Array = s.get_cells_for_area(a_key)
				for c in c_cells:
					db_inst.upsert_map_cell(int(c["cell_x"]), int(c["cell_y"]), 1)

	db_inst.commit_transaction()

	return {
		"ok": true,
		"revealed_areas": db_inst.get_all_area_reveals(),
		"distort_places": db_inst.get_all_distort_entries()
	}
