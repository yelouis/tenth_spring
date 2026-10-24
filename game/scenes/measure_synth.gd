extends Node

# measure_synth.gd — Measure Synthesis Statistics on Map Store
# Contract: docs/implementation_plan_world_generation_slice2.md §10.3 & docs/agent_execution_guide.md §2 Item 13

const MapStore := preload("res://world/region_import/map_store.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Grid := preload("res://world/grid.gd")

class LruCache:
	var capacity: int = 512
	var _map: Dictionary = {}
	var _order: Array[Vector2i] = []

	func _init(cap: int = 512) -> void:
		capacity = cap

	func get_item(key: Vector2i):
		if not _map.has(key):
			return null
		_order.erase(key)
		_order.append(key)
		return _map[key]

	func has(key: Vector2i) -> bool:
		return _map.has(key)

	func put(key: Vector2i, val) -> void:
		if _map.has(key):
			_order.erase(key)
		elif _order.size() >= capacity:
			var oldest: Vector2i = _order.pop_front()
			_map.erase(oldest)
		_order.append(key)
		_map[key] = val

var _raw_cache := LruCache.new(512)

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var store_path := ""

	var i := 0
	while i < user_args.size():
		var arg := user_args[i]
		if arg == "--store" and i + 1 < user_args.size():
			store_path = user_args[i + 1]
			i += 2
		elif arg.begins_with("--store="):
			store_path = arg.trim_prefix("--store=")
			i += 1
		else:
			i += 1

	if store_path.is_empty():
		printerr("measure_synth: Missing required argument --store")
		get_tree().quit(1)
		return

	var store := MapStore.new(store_path)
	if not store.open_store(false):
		printerr("measure_synth: Failed to open map store '%s': %s" % [store_path, store.last_error])
		get_tree().quit(1)
		return

	# Resolve place_id, waypost_wm, and landmarks for this store (§11.2, §11.4)
	var place_id: String = store.get_state("place_id", "")
	if place_id.is_empty():
		var fname := store_path.get_file().trim_suffix(".db")
		if fname.begins_with("city:") or fname.begins_with("site:"):
			place_id = fname
		elif "district-of-columbia" in fname:
			place_id = "city:washington-dc"

	var has_waypost := false
	var waypost_wm := Vector2.ZERO
	var landmarks_by_cell: Dictionary = {}
	var expected_landmarks := 0
	var places: Array = RevealEngine.load_places()
	for p in places:
		var p_id := str(p.get("id", ""))
		if p_id == place_id or place_id.is_empty():
			if p_id == place_id and p.has("waypost"):
				var wp: Dictionary = p["waypost"]
				waypost_wm = Grid.latlon_to_wm(float(wp.get("lat", 0.0)), float(wp.get("lon", 0.0)))
				has_waypost = true
			var interiors: Array = p.get("interiors", [])
			for interior in interiors:
				var i_id := str(interior.get("id", ""))
				var i_name := str(interior.get("name", ""))
				var door: Dictionary = interior.get("door", {})
				var wm: Vector2 = Grid.latlon_to_wm(float(door.get("lat", 0.0)), float(door.get("lon", 0.0)))
				var cell: Vector2i = Grid.wm_to_cell(wm.x, wm.y)
				if not landmarks_by_cell.has(cell):
					landmarks_by_cell[cell] = []
				landmarks_by_cell[cell].append({
					"id": i_id,
					"name": i_name,
					"door_wm": wm
				})
				if p_id == place_id:
					expected_landmarks += 1

	# Query candidate cells that contain at least one building polygon
	var building_cells := store._rows(
		"SELECT DISTINCT cell_x, cell_y FROM features_poly WHERE kind = 'building' ORDER BY cell_y, cell_x;"
	)

	var cov_box = store.get_coverage_box()
	var built_up_cells: Array[Vector2i] = []

	for row in building_cells:
		var cx: int = int(row["cell_x"])
		var cy: int = int(row["cell_y"])

		# Built-up cell: covered cell with >= 1 building in store and 3x3 neighbourhood covered
		var is_built_up := true
		if cov_box != null and cov_box is Rect2i:
			var r: Rect2i = cov_box
			var min_cx: int = r.position.x
			var min_cy: int = r.position.y
			var max_cx: int = min_cx + r.size.x - 1
			var max_cy: int = min_cy + r.size.y - 1
			if cx - 1 < min_cx or cx + 1 > max_cx or cy - 1 < min_cy or cy + 1 > max_cy:
				is_built_up = false
		else:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not store.covers_cell(cx + dx, cy + dy):
						is_built_up = false
						break
				if not is_built_up:
					break

		if is_built_up:
			built_up_cells.append(Vector2i(cx, cy))

	var total_candidates: int = 0
	var total_placed: int = 0
	var total_fallback: int = 0
	var total_building_tiles: int = 0
	var total_path_tiles: int = 0
	var total_road_tiles: int = 0
	var total_rubble_tiles: int = 0
	var total_tall_grass_tiles: int = 0
	var total_ordinary_standing: int = 0
	var total_ordinary_ruined: int = 0
	var total_ordinary_gone: int = 0
	var placed_landmark_ids: Dictionary = {}

	for cell in built_up_cells:
		var cx := cell.x
		var cy := cell.y

		var area: Dictionary = {}
		if has_waypost:
			area["waypost_wm"] = waypost_wm
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var offset := Vector2i(dx, dy)
				var nx := cx + dx
				var ny := cy + dy
				var cell_raw := _get_cell_raw(store, nx, ny).duplicate()
				cell_raw["landmarks"] = landmarks_by_cell.get(Vector2i(nx, ny), [])
				area[offset] = cell_raw

		var synth_res := TileSynth2.synthesize_cell(cx, cy, area)
		var stats: Dictionary = synth_res.get("stats", {})
		total_candidates += int(stats.get("building_candidates", 0))
		total_placed += int(stats.get("buildings_placed", 0))
		total_fallback += int(stats.get("fallback_placed", 0))
		total_ordinary_standing += int(stats.get("ordinary_standing", 0))
		total_ordinary_ruined += int(stats.get("ordinary_ruined", 0))
		total_ordinary_gone += int(stats.get("ordinary_gone", 0))
		for lm_id in stats.get("landmark_ids_placed", []):
			placed_landmark_ids[str(lm_id)] = true

		var tiles: PackedByteArray = synth_res.get("tiles", PackedByteArray())
		var t_size := tiles.size()
		for idx in range(0, t_size, 3):
			var cls: int = tiles[idx]
			if cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR:
				total_building_tiles += 1
			elif cls == TileSynth2.TILE_PATH:
				total_path_tiles += 1
			elif cls == TileSynth2.TILE_ROAD:
				total_road_tiles += 1
			elif cls == TileSynth2.TILE_RUBBLE:
				total_rubble_tiles += 1
			elif cls == TileSynth2.TILE_TALL_GRASS:
				total_tall_grass_tiles += 1

	store.close()

	var total_tiles: int = built_up_cells.size() * 1024
	var placement_pct: float = (float(total_placed) / float(total_candidates) * 100.0) if total_candidates > 0 else 0.0
	var building_tile_pct: float = (float(total_building_tiles) / float(total_tiles) * 100.0) if total_tiles > 0 else 0.0
	var path_tile_pct: float = (float(total_path_tiles) / float(total_tiles) * 100.0) if total_tiles > 0 else 0.0
	var road_tile_pct: float = (float(total_road_tiles) / float(total_tiles) * 100.0) if total_tiles > 0 else 0.0
	var rubble_tile_pct: float = (float(total_rubble_tiles) / float(total_tiles) * 100.0) if total_tiles > 0 else 0.0
	var tall_grass_pct: float = (float(total_tall_grass_tiles) / float(total_tiles) * 100.0) if total_tiles > 0 else 0.0

	var total_ordinary: int = total_ordinary_standing + total_ordinary_ruined + total_ordinary_gone
	var standing_pct: float = (float(total_ordinary_standing) / float(total_ordinary) * 100.0) if total_ordinary > 0 else 0.0
	var ruined_pct: float = (float(total_ordinary_ruined) / float(total_ordinary) * 100.0) if total_ordinary > 0 else 0.0
	var gone_pct: float = (float(total_ordinary_gone) / float(total_ordinary) * 100.0) if total_ordinary > 0 else 0.0

	print("MEASURE cells=%d candidates=%d placed=%d placement_pct=%.1f%% building_tile_pct=%.1f%% path_tile_pct=%.1f%% road_tile_pct=%.1f%%" % [
		built_up_cells.size(),
		total_candidates,
		total_placed,
		placement_pct,
		building_tile_pct,
		path_tile_pct,
		road_tile_pct
	])
	print("MEASURE_RUIN standing_pct=%.1f%% ruined_pct=%.1f%% gone_pct=%.1f%% building_tile_pct=%.1f%% rubble_tile_pct=%.1f%% tall_grass_pct=%.1f%% landmarks_standing=%d/%d" % [
		standing_pct,
		ruined_pct,
		gone_pct,
		building_tile_pct,
		rubble_tile_pct,
		tall_grass_pct,
		placed_landmark_ids.size(),
		expected_landmarks
	])

	get_tree().quit(0)

func _get_cell_raw(store: MapStore, cx: int, cy: int) -> Dictionary:
	var key := Vector2i(cx, cy)
	if _raw_cache.has(key):
		return _raw_cache.get_item(key)

	var data := {
		"polys": store.get_features_poly(cx, cy),
		"lines": store.get_features_line(cx, cy),
		"places": store.get_place_nodes(cx, cy),
		"covered": store.covers_cell(cx, cy),
		"sea": store.get_cell_sea(cx, cy)
	}
	_raw_cache.put(key, data)
	return data
