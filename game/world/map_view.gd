extends Node2D

# map_view.gd — Map View Scene Controller (Slice 2, Renderer v2)
# Contract: docs/implementation_plan_world_generation_slice2.md §6 & docs/agent_execution_guide.md §7.5

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const MapFetcher := preload("res://world/region_import/map_fetcher.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const SynthWorker := preload("res://world/synth_worker.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Grid := preload("res://world/grid.gd")

const CELL_SIZE_PX := 1024.0
const TILE_SIZE_PX := 32
const CELL_TILES := 32
const PAN_SPEED := 600.0

const MAX_SYNTH_CELLS := 1024
const MAX_STORE_CELLS := 256
const SYNTH_BUDGET_USEC := 8000 # 8 ms budget per frame

const ZOOM_STEPS: Array = [0.0625, 0.25, 1.0, 2.0]

# Palette colors for overview texture (§5.3)
const MAP_COLORS := {
	0: Color("#2a3242"),  # VOID
	1: Color("#78c850"),  # GRASS
	2: Color("#4f9a3a"),  # TALL_GRASS
	3: Color("#3a7d3a"),  # TREE
	4: Color("#4a90d8"),  # WATER
	5: Color("#e8d8a0"),  # SAND
	6: Color("#6a9a6a"),  # MARSH
	7: Color("#d8c090"),  # PATH
	8: Color("#8a8a90"),  # ROAD
	9: Color("#6b6b6b"),  # RAIL
	10: Color("#b07840"), # BRIDGE
	11: Color("#b0b0b8"), # PLAZA
	13: Color("#e8e0d0"), # WALL
	14: Color("#7a5028"), # DOOR
	15: Color("#f0f0f0"), # FENCE
	16: Color("#f85878"), # FLOWERS
	17: Color("#a0a0a8"), # GRAVE
	18: Color("#b07840"), # SIGN
	19: Color("#a8c060"), # CROP
	20: Color("#8a7a6a"), # RUBBLE
}

const ROOF_BASE_COLORS := [
	Color("#c0504a"), Color("#3a9a9a"), Color("#5a9a4a"), Color("#8a5ab0"),
	Color("#4a78c8"), Color("#e08a3a"), Color("#b090c8"), Color("#8a8a90")
]

# Generic LRU Cache
class LruCache:
	var capacity: int = 256
	var _map: Dictionary = {}
	var _order: Array[Vector2i] = []

	func _init(cap: int = 256) -> void:
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

	func size() -> int:
		return _order.size()

	func clear() -> void:
		_map.clear()
		_order.clear()

var _synth_cache := LruCache.new(MAX_SYNTH_CELLS)
var _store_cache := LruCache.new(MAX_STORE_CELLS)
var _rendered_cells: Dictionary = {} # Vector2i -> bool

var _synth_worker: SynthWorker = null
var _pending_blit_cells: Array[Vector2i] = []
var _requested_cells: Dictionary = {} # Vector2i -> bool
var _max_blits_observed: int = 0

var _load_start_time_usec: int = 0
var _load_max_frame_ms: float = 0.0
var _load_done: bool = false
var _load_time_ms: float = 0.0
var _steady_frame_times: Array[float] = []
var _steady_frames_count: int = 0
var _unknown_overview_tex: ImageTexture = null

var _camera: Camera2D = null
var _background_layer: ColorRect = null
var _world_known: TileMapLayer = null
var _world_cleared: TileMapLayer = null
var _fog_layer: TileMapLayer = null
var _overview_layer: Node2D = null
var _overview_sprites: Dictionary = {} # chunk_key (Vector2i) -> Sprite2D
var _overview_chunks: Dictionary = {} # chunk_key (Vector2i) -> Dictionary {image: Image, tex: ImageTexture, sprite: Sprite2D}
var _dirty_overview_chunks: Dictionary = {} # chunk_key (Vector2i) -> bool
var _unknown_overview_img: Image = null

var _demo_badge: Label = null
var _attribution_label: Label = null
var _unmapped_chip: PanelContainer = null
var _chip_label: Label = null
var _update_map_button: Button = null
var _download_dialog: ConfirmationDialog = null
var _install_panel: PanelContainer = null
var _install_label: Label = null
var _cancel_button: Button = null
var _sign_tooltip: Label = null
var _return_home_button: Button = null
var _active_place_id: String = ""
var _active_waypost_cell: Vector2i = Vector2i.ZERO
var _active_waypost_wm: Vector2 = Vector2.ZERO
var _has_active_waypost: bool = false

var _map_fetcher = MapFetcher.new()
var _pending_region: Dictionary = {}
var _pending_size_mb: int = 0
var _is_beyond_the_map: bool = false

var _unmapped_poll_timer: float = 0.0
var _last_unmapped_cells: Array[Vector2i] = []
var _unmapped_revealed_cells: Dictionary = {} # Vector2i -> bool
var _lookup_thread: Thread = null
var _lookup_mutex := Mutex.new()
var _pending_lookup_result: Variant = null

var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _current_zoom_step: float = 1.0 # 0.0625, 0.25, 1.0, 2.0
var _preview_cleared: bool = false

var _frame_times: Array[float] = []
var _is_demo: bool = false
var _map_stores: Array[MapStore] = []
var _map_data_dir: String = ""

# Atlas lookup mapping
var _class_variant_to_row: Dictionary = {}
var _class_any_variant: Dictionary = {}
var _masked_classes: Dictionary = {}
var _fog_rows: Dictionary = {}

# Landmarks mapping
var _landmarks_by_cell: Dictionary = {}
var _landmark_names: Dictionary = {}

# Screenshot mode state
var _screenshot_mode: bool = false
var _screenshot_path: String = ""
var _screenshot_zoom: float = 1.0
var _screenshot_target_frames: int = 10
var _screenshot_frames_waited: int = 0
var _screenshot_saved: bool = false
var _screenshot_focus: String = "most_visited"
var _focus_mode: String = "most_visited"
var _total_rendered_frames: int = 0

func _ready() -> void:
	_camera = get_node_or_null("MapCamera") as Camera2D
	if _camera != null:
		_camera.limit_left = -200000000
		_camera.limit_top = -200000000
		_camera.limit_right = 200000000
		_camera.limit_bottom = 200000000

	_background_layer = get_node_or_null("BackgroundLayer") as ColorRect
	_world_known = get_node_or_null("WorldKnown") as TileMapLayer
	_world_cleared = get_node_or_null("WorldCleared") as TileMapLayer
	_fog_layer = get_node_or_null("FogLayer") as TileMapLayer
	_overview_layer = get_node_or_null("OverviewLayer") as Node2D

	_demo_badge = get_node_or_null("AttributionUI/DemoBadge") as Label
	_attribution_label = get_node_or_null("AttributionUI/AttributionLabel") as Label
	_unmapped_chip = get_node_or_null("AttributionUI/UnmappedChip") as PanelContainer
	if _unmapped_chip != null:
		_chip_label = _unmapped_chip.get_node_or_null("ChipLabel") as Label
		_unmapped_chip.gui_input.connect(_on_unmapped_chip_gui_input)
	_update_map_button = get_node_or_null("AttributionUI/UpdateMapButton") as Button
	if _update_map_button != null:
		_update_map_button.pressed.connect(trigger_update_map_data)
	_download_dialog = get_node_or_null("AttributionUI/DownloadDialog") as ConfirmationDialog
	if _download_dialog != null:
		_download_dialog.confirmed.connect(_on_download_dialog_confirmed)
		_download_dialog.canceled.connect(cancel_download_dialog)
	_install_panel = get_node_or_null("AttributionUI/InstallPanel") as PanelContainer
	if _install_panel != null:
		_install_label = _install_panel.get_node_or_null("HBox/InstallLabel") as Label
		_cancel_button = _install_panel.get_node_or_null("HBox/CancelButton") as Button
		if _cancel_button != null:
			_cancel_button.pressed.connect(_on_install_cancel_pressed)
	_sign_tooltip = get_node_or_null("AttributionUI/SignTooltip") as Label
	_return_home_button = get_node_or_null("AttributionUI/ReturnHomeButton") as Button
	if _return_home_button != null:
		_return_home_button.pressed.connect(_on_return_home_pressed)

	set_map_fetcher(_map_fetcher)
	_check_demo_mode()
	_init_tile_sets()
	_load_landmarks()
	_load_start_time_usec = Time.get_ticks_usec()
	_load_map_stores()
	_set_zoom_step(1.0)
	if _focus_mode == "most_buildings":
		_focus_most_buildings()
	elif _focus_mode == "far_buildings":
		_focus_far_buildings()
	elif _focus_mode == "waypost":
		_focus_waypost()
	elif _focus_mode == "landmark":
		_focus_landmark()
	else:
		_focus_initial_cell()

func _load_landmarks() -> void:
	_landmarks_by_cell.clear()
	_landmark_names.clear()
	var places: Array = RevealEngine.load_places()
	for p in places:
		var interiors: Array = p.get("interiors", [])
		for interior in interiors:
			var i_id: String = str(interior.get("id", ""))
			var i_name: String = str(interior.get("name", ""))
			var door: Dictionary = interior.get("door", {})
			var d_lat := float(door.get("lat", 0.0))
			var d_lon := float(door.get("lon", 0.0))
			var wm: Vector2 = Grid.latlon_to_wm(d_lat, d_lon)
			var cell: Vector2i = Grid.wm_to_cell(wm.x, wm.y)
			var lm_dict := {
				"id": i_id,
				"name": i_name,
				"door_wm": wm
			}
			if not _landmarks_by_cell.has(cell):
				_landmarks_by_cell[cell] = []
			_landmarks_by_cell[cell].append(lm_dict)
			_landmark_names[i_name] = true

func _check_demo_mode() -> void:
	var profile = ProfilePaths.resolve_from_cmdline()
	_is_demo = profile.get("is_demo", false)

	var preview_cleared_arg := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			_is_demo = true
		elif arg == "--preview-cleared":
			preview_cleared_arg = true
		elif arg.begins_with("--focus="):
			_focus_mode = arg.trim_prefix("--focus=").strip_edges()
	for arg in OS.get_cmdline_args():
		if arg == "--demo":
			_is_demo = true
		elif arg == "--preview-cleared":
			preview_cleared_arg = true
		elif arg.begins_with("--focus="):
			_focus_mode = arg.trim_prefix("--focus=").strip_edges()

	if preview_cleared_arg:
		if _is_demo:
			_preview_cleared = true
		else:
			print("map: --preview-cleared needs --demo")
			_preview_cleared = false

	_update_demo_badge()

func _update_demo_badge() -> void:
	if _demo_badge != null:
		if _is_demo:
			_demo_badge.visible = true
			if _preview_cleared:
				_demo_badge.text = "DEMO MODE — preview: cleared look"
			else:
				_demo_badge.text = "DEMO MODE"
		else:
			_demo_badge.visible = false

func set_demo_mode(enabled: bool) -> void:
	_is_demo = enabled
	_update_demo_badge()

func set_preview_cleared(enabled: bool) -> void:
	if enabled and not _is_demo:
		print("map: --preview-cleared needs --demo")
		_preview_cleared = false
	else:
		_preview_cleared = enabled
	_update_demo_badge()
	_clear_rendered_layers()
	_update_frustum_culling()

func _clear_rendered_layers() -> void:
	if _world_known != null:
		_world_known.clear()
	if _world_cleared != null:
		_world_cleared.clear()
	if _fog_layer != null:
		_fog_layer.clear()
	for s in _overview_sprites.values():
		if is_instance_valid(s):
			s.queue_free()
	_overview_sprites.clear()
	_overview_chunks.clear()
	_dirty_overview_chunks.clear()
	_rendered_cells.clear()
	_pending_blit_cells.clear()
	_requested_cells.clear()

func _init_tile_sets() -> void:
	var atlas_data: Variant = AssetDB.tile_atlas()
	var texture: Texture2D = null
	var json_dict: Dictionary = {}

	if atlas_data != null and atlas_data is Dictionary and atlas_data.has("texture") and atlas_data.has("json"):
		texture = atlas_data["texture"]
		json_dict = atlas_data["json"]
	else:
		if ResourceLoader.exists("res://assets/tiles/placeholder_v1.png"):
			texture = load("res://assets/tiles/placeholder_v1.png") as Texture2D
		if texture == null:
			var abs_p := ProjectSettings.globalize_path("res://assets/tiles/placeholder_v1.png")
			if FileAccess.file_exists(abs_p):
				var img := Image.load_from_file(abs_p)
				if img != null and not img.is_empty():
					texture = ImageTexture.create_from_image(img)

		var json_path := "res://assets/tiles/placeholder_v1.json"
		var json_text := ""
		if FileAccess.file_exists(json_path):
			var f := FileAccess.open(json_path, FileAccess.READ)
			if f != null:
				json_text = f.get_as_text()
				f.close()
		else:
			var abs_jp := ProjectSettings.globalize_path(json_path)
			if FileAccess.file_exists(abs_jp):
				var f := FileAccess.open(abs_jp, FileAccess.READ)
				if f != null:
					json_text = f.get_as_text()
					f.close()
		if not json_text.is_empty():
			var parsed = JSON.parse_string(json_text)
			if parsed is Dictionary:
				json_dict = parsed

	_class_variant_to_row.clear()
	_class_any_variant.clear()
	_masked_classes.clear()
	_fog_rows = json_dict.get("fog_rows", {
		"solid": 54,
		"d75": 55,
		"d50": 56,
		"d25": 57
	})

	var rows_list: Array = json_dict.get("rows", [])
	var max_row := 57
	for item in rows_list:
		if item is Dictionary:
			var c: int = item.get("class", 0)
			var v: int = item.get("variant", 0)
			var r: int = item.get("row", 0)
			var m: bool = item.get("masked", false)
			_masked_classes[c] = m
			_class_variant_to_row[Vector2i(c, v)] = r
			if item.get("any_variant", false):
				_class_any_variant[c] = r
			if r > max_row:
				max_row = r

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)
	if texture != null:
		for r in range(max_row + 1):
			for c in range(16):
				var coord := Vector2i(c, r)
				if not source.has_tile(coord):
					source.create_tile(coord)
	tileset.add_source(source, 0)

	if _world_known != null:
		_world_known.tile_set = tileset
	if _world_cleared != null:
		_world_cleared.tile_set = tileset
	if _fog_layer != null:
		_fog_layer.tile_set = tileset

func get_atlas_coords(cls: int, variant: int, mask: int) -> Vector2i:
	var row := 0
	if _class_any_variant.has(cls):
		row = _class_any_variant[cls]
	elif _class_variant_to_row.has(Vector2i(cls, variant)):
		row = _class_variant_to_row[Vector2i(cls, variant)]
	elif _class_variant_to_row.has(Vector2i(cls, 0)):
		row = _class_variant_to_row[Vector2i(cls, 0)]

	var col := mask if _masked_classes.get(cls, false) else 0
	return Vector2i(col, row)

func set_map_data_dir(dir_path: String) -> void:
	_map_data_dir = dir_path
	_load_map_stores()
	_synth_cache.clear()
	_store_cache.clear()
	_clear_rendered_layers()
	_update_frustum_culling()

func _load_map_stores() -> void:
	for s in _map_stores:
		s.close()
	_map_stores.clear()
	_store_cache.clear()
	var store_paths: Array[String] = []
	var target_dir := _map_data_dir
	if target_dir.is_empty():
		target_dir = ProfilePaths.get_map_data_dir()
	if not target_dir.ends_with("/"):
		target_dir += "/"
	if DirAccess.dir_exists_absolute(target_dir):
		var files = DirAccess.get_files_at(target_dir)
		for f in files:
			if f.ends_with(".db") and not f.ends_with(".tmp.db"):
				var p: String = target_dir + f
				var store := MapStore.new(p)
				if store.open_store(true):
					var schema_ver := store.get_state("schema_version", "")
					if schema_ver != "4":
						print("map: skipping %s — store schema %s, need 4" % [f, schema_ver])
						store.close()
					else:
						_map_stores.append(store)
						store_paths.append(p)
						var s_place_id := store.get_state("place_id", "")
						if not s_place_id.is_empty() and _active_place_id.is_empty():
							_active_place_id = s_place_id
	_resolve_active_waypost()
	if _synth_worker == null:
		_synth_worker = SynthWorker.new()
		_synth_worker.start(store_paths)
	else:
		_synth_worker.set_store_paths(store_paths)
	if _synth_worker != null:
		_synth_worker.set_landmarks(_landmarks_by_cell)
		_synth_worker.set_waypost_wm(_active_waypost_wm if _has_active_waypost else null)

func _resolve_active_waypost() -> void:
	if _active_place_id.is_empty():
		return
	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == _active_place_id:
			var wp: Dictionary = p.get("waypost", {})
			var w_lat := float(wp.get("lat", 0.0))
			var w_lon := float(wp.get("lon", 0.0))
			_active_waypost_cell = Grid.latlon_to_cell(w_lat, w_lon)
			_active_waypost_wm = Grid.latlon_to_wm(w_lat, w_lon)
			_has_active_waypost = true
			return

func _get_db() -> Node:
	return get_node_or_null("/root/DB")

func _focus_initial_cell() -> void:
	if _camera == null:
		return

	var target_cell := Vector2i.ZERO
	var found := false

	var db = _get_db()
	if db != null and db.is_open():
		# 1. Check most visited place_node
		var place_rows = db.query_rows("SELECT cell_x, cell_y FROM place_node WHERE cell_x IS NOT NULL ORDER BY visit_count DESC LIMIT 1;")
		if not place_rows.is_empty():
			target_cell = Vector2i(int(place_rows[0]["cell_x"]), int(place_rows[0]["cell_y"]))
			found = true

		# 2. Check base_state home cell
		if not found:
			var base_rows = db.query_rows("SELECT home_cell_x, home_cell_y FROM base_state WHERE home_cell_x != 0 OR home_cell_y != 0 LIMIT 1;")
			if not base_rows.is_empty():
				target_cell = Vector2i(int(base_rows[0]["home_cell_x"]), int(base_rows[0]["home_cell_y"]))
				found = true

		# 3. Fall back to any revealed map_cell
		if not found:
			var cell_rows = db.query_rows("SELECT cell_x, cell_y FROM map_cell WHERE reveal_state > 0 LIMIT 1;")
			if not cell_rows.is_empty():
				target_cell = Vector2i(int(cell_rows[0]["cell_x"]), int(cell_rows[0]["cell_y"]))
				found = true

	focus_on_cell(target_cell.x, target_cell.y)

func focus_on_cell(cx: int, cy: int) -> void:
	if _camera != null:
		_camera.position = Vector2((cx + 0.5) * CELL_SIZE_PX, (-cy - 0.5) * CELL_SIZE_PX)
	_update_return_home_visibility()

func load_place(place_id: String, center_waypost: bool = true) -> bool:
	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == place_id:
			_active_place_id = place_id
			var wp: Dictionary = p.get("waypost", {})
			var w_lat := float(wp.get("lat", 0.0))
			var w_lon := float(wp.get("lon", 0.0))
			_active_waypost_cell = Grid.latlon_to_cell(w_lat, w_lon)
			_active_waypost_wm = Grid.latlon_to_wm(w_lat, w_lon)
			_has_active_waypost = true
			if _synth_worker != null:
				_synth_worker.set_waypost_wm(_active_waypost_wm)
			if center_waypost:
				focus_on_cell(_active_waypost_cell.x, _active_waypost_cell.y)
			_update_return_home_visibility()
			return true
	return false

func get_camera_cell() -> Vector2i:
	if _camera == null:
		return Vector2i.ZERO
	var cx := int(floor(_camera.position.x / CELL_SIZE_PX))
	var cy := int(floor(-_camera.position.y / CELL_SIZE_PX))
	return Vector2i(cx, cy)

func _update_return_home_visibility() -> void:
	if _return_home_button == null:
		return
	if not _has_active_waypost:
		_return_home_button.visible = false
		return
	var cam_cell := get_camera_cell()
	var dist_x: int = abs(cam_cell.x - _active_waypost_cell.x)
	var dist_y: int = abs(cam_cell.y - _active_waypost_cell.y)
	_return_home_button.visible = (dist_x <= 1 and dist_y <= 1)

func _on_return_home_pressed() -> void:
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_home_hub"):
		main_node.open_home_hub()
	elif get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/home_hub.tscn")

func _focus_most_buildings() -> void:
	if _camera == null:
		return
	var db = _get_db()
	if db == null or not db.is_open():
		_focus_initial_cell()
		return

	var cell_rows = db.query_rows("SELECT cell_x, cell_y, reveal_state FROM map_cell WHERE reveal_state > 0;")
	if cell_rows.is_empty():
		_focus_initial_cell()
		return

	var best_cell: Variant = null
	var max_doors: int = -1

	for row in cell_rows:
		var cx := int(row["cell_x"])
		var cy := int(row["cell_y"])
		var cell := Vector2i(cx, cy)
		var reveal_state := int(row["reveal_state"])

		var buf: PackedByteArray
		if _synth_cache.has(cell):
			buf = _synth_cache.get_item(cell).get("buf", PackedByteArray())
		elif _synth_worker != null and _synth_worker.is_running():
			var res: Dictionary = _synth_worker.request_cell_sync(cell, false, reveal_state, _preview_cleared)
			var item := {
				"buf": res["tiles"],
				"signs": res["signs"],
				"has_data": res["has_data"],
				"image": res.get("image", null),
				"thread_id": res.get("thread_id", 0),
				"reveal_state": reveal_state
			}
			_synth_cache.put(cell, item)
			buf = res.get("tiles", PackedByteArray())
		else:
			var area: Dictionary = {}
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					area[Vector2i(dx, dy)] = _get_cell_features(cx + dx, cy + dy)
			var synth_res: Dictionary = TileSynth2.synthesize_cell(cx, cy, area)
			buf = synth_res.get("tiles", PackedByteArray())

		var door_count := 0
		for ty in 32:
			for tx in 32:
				var idx := (ty * 32 + tx) * 3
				if idx < buf.size() and buf[idx] == TileSynth2.TILE_DOOR:
					door_count += 1

		if door_count > max_doors:
			max_doors = door_count
			best_cell = cell
		elif door_count == max_doors:
			# Ties go to the lower (cy, cx)
			if best_cell == null or cy < best_cell.y or (cy == best_cell.y and cx < best_cell.x):
				best_cell = cell

	if best_cell != null:
		focus_on_cell(best_cell.x, best_cell.y)
	else:
		_focus_initial_cell()

func _focus_far_buildings() -> void:
	if _camera == null:
		return
	var db = _get_db()
	if db == null or not db.is_open():
		_focus_initial_cell()
		return

	var cell_rows = db.query_rows("SELECT cell_x, cell_y, reveal_state FROM map_cell WHERE reveal_state > 0;")
	if cell_rows.is_empty():
		_focus_initial_cell()
		return

	var wp_ll := Vector2.ZERO
	var has_wp := _has_active_waypost
	if has_wp:
		wp_ll = Grid.wm_to_latlon(_active_waypost_wm)
	else:
		var places: Array = RevealEngine.load_places()
		for p in places:
			if str(p.get("id", "")) == _active_place_id or _active_place_id.is_empty():
				var wp: Dictionary = p.get("waypost", {})
				wp_ll = Vector2(float(wp.get("lat", 0.0)), float(wp.get("lon", 0.0)))
				_active_waypost_wm = Grid.latlon_to_wm(wp_ll.x, wp_ll.y)
				_active_waypost_cell = Grid.latlon_to_cell(wp_ll.x, wp_ll.y)
				_has_active_waypost = true
				has_wp = true
				if _synth_worker != null:
					_synth_worker.set_waypost_wm(_active_waypost_wm)
				break

	var best_cell: Variant = null
	var max_score: int = -1

	for row in cell_rows:
		var cx := int(row["cell_x"])
		var cy := int(row["cell_y"])
		var cell := Vector2i(cx, cy)
		var reveal_state := int(row["reveal_state"])

		if has_wp:
			var c_ll := Grid.cell_center_latlon(cell)
			var d_m := Grid.ground_distance_m(c_ll.x, c_ll.y, wp_ll.x, wp_ll.y)
			if d_m < 3000.0:
				continue

		var buf: PackedByteArray
		if _synth_cache.has(cell):
			buf = _synth_cache.get_item(cell).get("buf", PackedByteArray())
		elif _synth_worker != null and _synth_worker.is_running():
			var res: Dictionary = _synth_worker.request_cell_sync(cell, false, reveal_state, _preview_cleared)
			var item := {
				"buf": res["tiles"],
				"signs": res["signs"],
				"has_data": res["has_data"],
				"image": res.get("image", null),
				"thread_id": res.get("thread_id", 0),
				"reveal_state": reveal_state
			}
			_synth_cache.put(cell, item)
			buf = res.get("tiles", PackedByteArray())
		else:
			var area: Dictionary = {}
			if _has_active_waypost:
				area["waypost_wm"] = _active_waypost_wm
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					area[Vector2i(dx, dy)] = _get_cell_features(cx + dx, cy + dy)
			var synth_res: Dictionary = TileSynth2.synthesize_cell(cx, cy, area)
			buf = synth_res.get("tiles", PackedByteArray())

		var score := 0
		for ty in 32:
			for tx in 32:
				var idx := (ty * 32 + tx) * 3
				if idx < buf.size():
					var cls: int = buf[idx]
					if cls == TileSynth2.TILE_DOOR or cls == TileSynth2.TILE_RUBBLE:
						score += 1

		if score > max_score:
			max_score = score
			best_cell = cell
		elif score == max_score:
			if best_cell == null or cy < best_cell.y or (cy == best_cell.y and cx < best_cell.x):
				best_cell = cell

	if best_cell != null:
		focus_on_cell(best_cell.x, best_cell.y)
	else:
		_focus_most_buildings()

func _focus_waypost() -> void:
	if _has_active_waypost:
		focus_on_cell(_active_waypost_cell.x, _active_waypost_cell.y)
		return
	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == _active_place_id or _active_place_id.is_empty():
			var wp: Dictionary = p.get("waypost", {})
			var w_lat := float(wp.get("lat", 0.0))
			var w_lon := float(wp.get("lon", 0.0))
			var cell := Grid.latlon_to_cell(w_lat, w_lon)
			focus_on_cell(cell.x, cell.y)
			return
	_focus_initial_cell()

func _focus_landmark() -> void:
	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == _active_place_id or _active_place_id.is_empty():
			var interiors: Array = p.get("interiors", [])
			if not interiors.is_empty():
				var door: Dictionary = interiors[0].get("door", {})
				var d_lat := float(door.get("lat", 0.0))
				var d_lon := float(door.get("lon", 0.0))
				var cell := Grid.latlon_to_cell(d_lat, d_lon)
				focus_on_cell(cell.x, cell.y)
				return
	_focus_initial_cell()

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_handle_keyboard_pan(delta)
	_update_frustum_culling()
	_drain_worker_results()
	_blit_pending_cells()
	_lookup_mutex.lock()
	var lookup_res: Variant = _pending_lookup_result
	_pending_lookup_result = null
	_lookup_mutex.unlock()
	if lookup_res != null and lookup_res is Dictionary:
		_on_region_lookup_done(lookup_res)
	_poll_unmapped_cells(delta)
	_update_sign_tooltip()
	_update_return_home_visibility()
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var sample_ms := delta * 1000.0 if delta > 0.0 else elapsed_ms
	_frame_times.append(sample_ms)
	if _frame_times.size() > 120:
		_frame_times.pop_front()

	if not _load_done:
		_load_max_frame_ms = maxf(_load_max_frame_ms, elapsed_ms)
		if _total_rendered_frames >= 2:
			_load_max_frame_ms = maxf(_load_max_frame_ms, sample_ms)
		if pending_cell_count() == 0:
			_load_done = true
			_load_time_ms = float(Time.get_ticks_usec() - _load_start_time_usec) / 1000.0
			print("LOAD_TIME_MS: %.2f" % _load_time_ms)
			print("LOAD_MAX_FRAME_MS: %.2f" % _load_max_frame_ms)
	else:
		_steady_frame_times.append(sample_ms)
		if _steady_frame_times.size() > 120:
			_steady_frame_times.pop_front()
		_steady_frames_count += 1

func _update_sign_tooltip() -> void:
	if _sign_tooltip == null:
		return

	var mouse_world := get_global_mouse_position()
	var st := Vector2i(floori(mouse_world.x / 32.0), floori(mouse_world.y / 32.0))
	var cx := floori(float(st.x) / 32.0)
	var col := posmod(st.x, 32)
	var cell_row := floori(float(st.y) / 32.0)
	var cy := -cell_row - 1
	var row := posmod(st.y, 32)
	var cell := Vector2i(cx, cy)

	if _synth_cache.has(cell):
		var item = _synth_cache.get_item(cell)
		if item is Dictionary and item.get("reveal_state", 0) > 0:
			var buf: PackedByteArray = item.get("buf", PackedByteArray())
			var signs = item.get("signs", [])
			var t_idx := (row * 32 + col) * 3
			if t_idx + 2 < buf.size():
				var t_class := int(buf[t_idx])
				var t_variant := int(buf[t_idx + 1])
				if t_class == TileSynth2.TILE_SIGN:
					if t_variant >= 0 and t_variant < signs.size():
						var s_name := str(signs[t_variant])
						if _landmark_names.has(s_name):
							_sign_tooltip.text = "%s — can be entered (interiors arrive in a later update)" % s_name
						else:
							_sign_tooltip.text = s_name
						_sign_tooltip.global_position = get_viewport().get_mouse_position() + Vector2(12, 12)
						_sign_tooltip.visible = true
						return
				elif t_class == TileSynth2.TILE_DOOR and (t_variant & 32 != 0 or t_variant == 32):
					var cell_lms: Array = _landmarks_by_cell.get(cell, [])
					var lm_name := "Landmark"
					if not cell_lms.is_empty():
						lm_name = str(cell_lms[0].get("name", "Landmark"))
					_sign_tooltip.text = "%s — can be entered (interiors arrive in a later update)" % lm_name
					_sign_tooltip.global_position = get_viewport().get_mouse_position() + Vector2(12, 12)
					_sign_tooltip.visible = true
					return

	_sign_tooltip.visible = false

func _poll_unmapped_cells(delta: float) -> void:
	_unmapped_poll_timer += delta
	if _unmapped_poll_timer < 2.0:
		return
	_unmapped_poll_timer = 0.0

	var unmapped: Array[Vector2i] = []
	for c in _unmapped_revealed_cells.keys():
		unmapped.append(c)
	unmapped.sort()

	if unmapped.is_empty():
		_last_unmapped_cells.clear()
		return

	if unmapped == _last_unmapped_cells:
		return

	_last_unmapped_cells = unmapped.duplicate()

	if _chip_label != null:
		_chip_label.text = "Unmapped — looking up map data…"
	if _unmapped_chip != null:
		_unmapped_chip.visible = true

	if _map_fetcher == null:
		return

	if _lookup_thread != null and _lookup_thread.is_alive():
		return
	if _lookup_thread != null:
		_lookup_thread.wait_to_finish()
	_lookup_thread = Thread.new()
	_lookup_thread.start(_thread_lookup_worker.bind(unmapped))

func _thread_lookup_worker(cells: Array) -> void:
	var res: Dictionary = _map_fetcher.select_region_for_cells(cells)
	_lookup_mutex.lock()
	_pending_lookup_result = res
	_lookup_mutex.unlock()

func _on_region_lookup_done(res: Dictionary) -> void:
	if _lookup_thread != null and not _lookup_thread.is_alive():
		_lookup_thread.wait_to_finish()
		_lookup_thread = null
	configure_unmapped_region_data(res)

func _handle_keyboard_pan(delta: float) -> void:
	if _camera == null:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	if dir != Vector2.ZERO:
		_camera.position += dir.normalized() * (PAN_SPEED * delta / _camera.zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_dragging = true
				_drag_start_pos = mb.position
			else:
				_is_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_step_zoom(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_step_zoom(-1)

	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		if _camera != null:
			_camera.position -= mm.relative / _camera.zoom.x

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_F9:
			print_p95_frame_time()

func _step_zoom(direction: int) -> void:
	var curr_idx := 2
	for i in range(ZOOM_STEPS.size()):
		if is_equal_approx(_current_zoom_step, float(ZOOM_STEPS[i])):
			curr_idx = i
			break
	var next_idx: int = clampi(curr_idx + direction, 0, ZOOM_STEPS.size() - 1)
	_set_zoom_step(float(ZOOM_STEPS[next_idx]))

func _set_zoom_step(zoom_val: float) -> void:
	var was_overview := (_current_zoom_step < 1.0)
	_current_zoom_step = zoom_val
	if _camera != null:
		_camera.zoom = Vector2(zoom_val, zoom_val)

	var show_overview := (_current_zoom_step < 1.0)
	if was_overview != show_overview:
		_rendered_cells.clear()
		_pending_blit_cells.clear()
		_requested_cells.clear()
	if _overview_layer != null:
		_overview_layer.visible = show_overview
	if _world_known != null:
		_world_known.visible = not show_overview
	if _world_cleared != null:
		_world_cleared.visible = not show_overview
	if _fog_layer != null:
		_fog_layer.visible = not show_overview

func _update_frustum_culling() -> void:
	if _camera == null:
		return

	var vp_size := get_viewport_rect().size / _camera.zoom.x
	var cam_pos := _camera.position
	var vis_rect := Rect2(cam_pos - vp_size * 0.5, vp_size).grow(CELL_SIZE_PX)

	var min_cx := int(floor(vis_rect.position.x / CELL_SIZE_PX))
	var max_cx := int(floor((vis_rect.position.x + vis_rect.size.x) / CELL_SIZE_PX))
	var top := vis_rect.position.y
	var bottom := vis_rect.position.y + vis_rect.size.y
	var r0 := int(floor(top / CELL_SIZE_PX))
	var r1 := int(floor(bottom / CELL_SIZE_PX))
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1

	var cam_cell_center := Vector2(cam_pos.x / CELL_SIZE_PX, -cam_pos.y / CELL_SIZE_PX - 1.0)
	var visible_cell_set: Dictionary = {}
	var has_unmapped_revealed_cell := false
	var new_requests: Array[Dictionary] = []

	var db = _get_db()
	var db_open: bool = (db != null and db.is_open())
	var revealed_cells_in_view: Dictionary = {}
	if db_open:
		var q_sql := "SELECT cell_x, cell_y, reveal_state FROM map_cell WHERE cell_x >= ? AND cell_x <= ? AND cell_y >= ? AND cell_y <= ? AND reveal_state > 0;"
		var rows: Array = db.query_rows(q_sql, [min_cx, max_cx, min_cy, max_cy])
		for r in rows:
			var r_cell := Vector2i(int(r["cell_x"]), int(r["cell_y"]))
			revealed_cells_in_view[r_cell] = int(r["reveal_state"])

	var is_overview := (_current_zoom_step < 1.0)

	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			visible_cell_set[cell] = true

			var reveal_state: int = revealed_cells_in_view.get(cell, 0)

			if reveal_state == 0:
				if not _rendered_cells.has(cell):
					_render_unknown_cell(cx, cy)
					_rendered_cells[cell] = true
			else:
				if _synth_cache.has(cell):
					if not _rendered_cells.has(cell) and not _pending_blit_cells.has(cell):
						_pending_blit_cells.append(cell)
				else:
					if not _rendered_cells.has(cell) and not is_overview:
						_render_solid_fog(cx, cy)
					if not _requested_cells.has(cell):
						var dist: float = (Vector2(cx + 0.5, cy + 0.5) - cam_cell_center).length()
						new_requests.append({
							"cell": cell,
							"priority_dist": dist,
							"needs_overview": is_overview,
							"reveal_state": reveal_state,
							"preview_cleared": _preview_cleared
						})
						_requested_cells[cell] = true

	# Post requests to worker
	if _synth_worker != null and _synth_worker.is_running():
		_synth_worker.update_requests(new_requests, visible_cell_set)

	# Clean up _requested_cells for cells no longer visible
	var req_keys := _requested_cells.keys()
	for c in req_keys:
		if not visible_cell_set.has(c):
			_requested_cells.erase(c)

	# Unrender cells that scrolled out of view
	var to_remove: Array[Vector2i] = []
	for cell in _rendered_cells.keys():
		if not visible_cell_set.has(cell):
			_unrender_cell(cell.x, cell.y)
			to_remove.append(cell)
	for cell in to_remove:
		_rendered_cells.erase(cell)

	# Prune _pending_blit_cells for cells no longer visible
	var pruned_blits: Array[Vector2i] = []
	for c in _pending_blit_cells:
		if visible_cell_set.has(c):
			pruned_blits.append(c)
	_pending_blit_cells = pruned_blits

	# Sort pending blits nearest to camera first
	_pending_blit_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (Vector2(a.x + 0.5, a.y + 0.5) - cam_cell_center).length_squared()
		var db_dist := (Vector2(b.x + 0.5, b.y + 0.5) - cam_cell_center).length_squared()
		return da < db_dist
	)

	# Check unmapped chip
	for c in _unmapped_revealed_cells.keys():
		if visible_cell_set.has(c):
			has_unmapped_revealed_cell = true
			break
	if _unmapped_chip != null:
		_unmapped_chip.visible = has_unmapped_revealed_cell

func _drain_worker_results() -> void:
	if _synth_worker == null or not _synth_worker.is_running():
		return
	var results := _synth_worker.pop_results()
	for res in results:
		var cell: Vector2i = res["cell"]
		_synth_cache.put(cell, {
			"buf": res["tiles"],
			"signs": res["signs"],
			"has_data": res["has_data"],
			"image": res.get("image", null),
			"thread_id": res.get("thread_id", 0),
			"reveal_state": res.get("reveal_state", 1)
		})
		_requested_cells.erase(cell)
		if not _rendered_cells.has(cell) and not _pending_blit_cells.has(cell):
			_pending_blit_cells.append(cell)

func _blit_pending_cells() -> void:
	var blits_this_frame := 0
	var is_overview := (_current_zoom_step < 1.0)
	var max_blits := 64 if is_overview else 2

	while not _pending_blit_cells.is_empty() and blits_this_frame < max_blits:
		var cell: Vector2i = _pending_blit_cells.pop_front()
		if not _synth_cache.has(cell):
			continue
		var item: Dictionary = _synth_cache.get_item(cell)
		_blit_cell(cell.x, cell.y, item)
		_rendered_cells[cell] = true
		blits_this_frame += 1

	if not is_overview:
		_max_blits_observed = maxi(_max_blits_observed, blits_this_frame)

	_flush_overview_chunks()

func _flush_overview_chunks() -> void:
	if _dirty_overview_chunks.is_empty():
		return
	var updated := 0
	var keys := _dirty_overview_chunks.keys()
	for chunk_key in keys:
		if updated >= 4:
			break
		_dirty_overview_chunks.erase(chunk_key)
		if _overview_chunks.has(chunk_key):
			var c_data: Dictionary = _overview_chunks[chunk_key]
			var tex: ImageTexture = c_data.get("tex", null)
			var img: Image = c_data.get("image", null)
			if tex != null and img != null:
				tex.update(img)
				updated += 1

func _blit_cell_to_overview_chunk(cx: int, cy: int, cell_img: Image) -> void:
	if _overview_layer == null:
		return
	var chunk_cx: int = floori(float(cx) / 8.0) * 8
	var chunk_cy: int = floori(float(cy) / 8.0) * 8
	var chunk_key := Vector2i(chunk_cx, chunk_cy)

	var c_data: Dictionary
	if _overview_chunks.has(chunk_key):
		c_data = _overview_chunks[chunk_key]
	else:
		var chunk_img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		chunk_img.fill(Color("#0d1119"))
		var chunk_tex := ImageTexture.create_from_image(chunk_img)
		var sprite := Sprite2D.new()
		sprite.centered = false
		# North-up: chunk covers cells cy in [chunk_cy .. chunk_cy + 7], so its top screen edge is at (-chunk_cy - 8) * CELL_SIZE_PX
		sprite.position = Vector2(float(chunk_cx) * CELL_SIZE_PX, float(-chunk_cy - 8) * CELL_SIZE_PX)
		sprite.scale = Vector2(32, 32)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = chunk_tex
		_overview_layer.add_child(sprite)
		c_data = {
			"image": chunk_img,
			"tex": chunk_tex,
			"sprite": sprite
		}
		_overview_chunks[chunk_key] = c_data
		_overview_sprites[chunk_key] = sprite

	var local_cx: int = cx - chunk_cx
	var local_cy: int = cy - chunk_cy
	var dst_x: int = local_cx * 32
	var dst_y: int = (7 - local_cy) * 32
	var chunk_img_ref: Image = c_data["image"]
	chunk_img_ref.blit_rect(cell_img, Rect2i(0, 0, 32, 32), Vector2i(dst_x, dst_y))
	_dirty_overview_chunks[chunk_key] = true

func _blit_cell(cx: int, cy: int, item: Dictionary) -> void:
	var cell := Vector2i(cx, cy)
	var tile_buf: PackedByteArray = item.get("buf", PackedByteArray())
	var reveal_state: int = item.get("reveal_state", 1)
	var has_map_data: bool = item.get("has_data", false)
	var is_overview := (_current_zoom_step < 1.0)

	if not is_overview:
		if reveal_state == 0:
			_render_solid_fog(cx, cy)
		else:
			var target_layer: TileMapLayer = _world_cleared if (_preview_cleared or reveal_state >= 2) else _world_known
			var other_layer: TileMapLayer = _world_known if target_layer == _world_cleared else _world_cleared

			for ty in 32:
				for tx in 32:
					var idx := (ty * 32 + tx) * 3
					var cls: int = tile_buf[idx]
					var v: int = tile_buf[idx + 1]
					var mask: int = tile_buf[idx + 2]
					var st := _screen_tile(cx, cy, tx, ty)
					target_layer.set_cell(st, 0, get_atlas_coords(cls, v, mask))
					other_layer.erase_cell(st)

			# Inward feathering on FogLayer (§6)
			var n_hidden := _is_cell_hidden(cx, cy + 1)
			var e_hidden := _is_cell_hidden(cx + 1, cy)
			var s_hidden := _is_cell_hidden(cx, cy - 1)
			var w_hidden := _is_cell_hidden(cx - 1, cy)

			var fog_d75: int = _fog_rows.get("d75", 55)
			var fog_d50: int = _fog_rows.get("d50", 56)
			var fog_d25: int = _fog_rows.get("d25", 57)

			for ty in 32:
				for tx in 32:
					var st := _screen_tile(cx, cy, tx, ty)
					var min_dist := 999
					if n_hidden:
						min_dist = mini(min_dist, ty)
					if s_hidden:
						min_dist = mini(min_dist, 31 - ty)
					if w_hidden:
						min_dist = mini(min_dist, tx)
					if e_hidden:
						min_dist = mini(min_dist, 31 - tx)

					if min_dist == 0:
						_fog_layer.set_cell(st, 0, Vector2i(0, fog_d75))
					elif min_dist == 1:
						_fog_layer.set_cell(st, 0, Vector2i(0, fog_d50))
					elif min_dist == 2:
						_fog_layer.set_cell(st, 0, Vector2i(0, fog_d25))
					else:
						_fog_layer.erase_cell(st)

	# Overview chunk in OverviewLayer (§11.5 step 2)
	if _overview_layer != null:
		var img: Image = item.get("image", null)
		if img == null:
			img = _build_overview_image(tile_buf, reveal_state)
			item["image"] = img
		_blit_cell_to_overview_chunk(cx, cy, img)

	var is_unmapped := (reveal_state > 0 and not has_map_data)
	if is_unmapped:
		_unmapped_revealed_cells[cell] = true
	else:
		_unmapped_revealed_cells.erase(cell)

func _render_unknown_cell(cx: int, cy: int) -> void:
	if _current_zoom_step >= 1.0:
		_render_solid_fog(cx, cy)
	if _overview_layer != null:
		_blit_cell_to_overview_chunk(cx, cy, _get_unknown_overview_image())

func _get_unknown_overview_image() -> Image:
	if _unknown_overview_img == null:
		_unknown_overview_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		_unknown_overview_img.fill(Color("#0d1119"))
	return _unknown_overview_img

func _get_unknown_overview_texture() -> ImageTexture:
	if _unknown_overview_tex == null:
		_unknown_overview_tex = ImageTexture.create_from_image(_get_unknown_overview_image())
	return _unknown_overview_tex

func _build_overview_image(tile_buf: PackedByteArray, reveal_state: int) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var apply_cpu_tint := (reveal_state == 1 and not _preview_cleared)
	for r in 32:
		for c in 32:
			var idx := (r * 32 + c) * 3
			var cls: int = tile_buf[idx]
			var v: int = tile_buf[idx + 1]
			var base_col: Color
			if reveal_state == 0:
				base_col = Color("#0d1119")
			elif cls == 12: # ROOF
				base_col = ROOF_BASE_COLORS[v % 8]
			else:
				base_col = MAP_COLORS.get(cls, Color("#2a3242"))

			if apply_cpu_tint:
				var g := 0.299 * base_col.r + 0.587 * base_col.g + 0.114 * base_col.b
				base_col = Color(
					(g * 0.4 + base_col.r * 0.6) * 0.82,
					(g * 0.4 + base_col.g * 0.6) * 0.82,
					(g * 0.4 + base_col.b * 0.6) * 0.82,
					1.0
				)
			img.set_pixel(c, r, base_col)
	return img

func _screen_tile(cx: int, cy: int, tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * 32 + tx, (-cy - 1) * 32 + ty)

func _is_cell_hidden(cx: int, cy: int) -> bool:
	var db = _get_db()
	if db != null and db.is_open():
		var rows: Array = db.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [cx, cy])
		if not rows.is_empty():
			return int(rows[0].get("reveal_state", 0)) == 0
	return true # Unknown if not in DB

func _get_cell_features(cell_x: int, cell_y: int) -> Dictionary:
	var key := Vector2i(cell_x, cell_y)
	if _store_cache.has(key):
		return _store_cache.get_item(key)

	var features := {
		"polys": [],
		"lines": [],
		"places": [],
		"landmarks": _landmarks_by_cell.get(key, []),
		"sea": 0,
		"has_data": false,
		"covered": false,
		"is_covered": false
	}
	for store in _map_stores:
		var polys = store.get_features_poly(cell_x, cell_y)
		var lines = store.get_features_line(cell_x, cell_y)
		var places = store.get_place_nodes(cell_x, cell_y)
		if not polys.is_empty() or not lines.is_empty() or not places.is_empty():
			features["polys"].append_array(polys)
			features["lines"].append_array(lines)
			features["places"].append_array(places)
			features["has_data"] = true
		if store.covers_cell(cell_x, cell_y):
			features["covered"] = true
			features["is_covered"] = true
			var sea = store.get_cell_sea(cell_x, cell_y)
			if sea > 0:
				features["sea"] = sea

	_store_cache.put(key, features)
	return features

func _render_cell(cx: int, cy: int, _budget_exceeded: bool = false) -> bool:
	var cell := Vector2i(cx, cy)
	var reveal_state := 0
	var db = _get_db()
	if db != null and db.is_open():
		var rows: Array = db.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [cx, cy])
		if not rows.is_empty():
			reveal_state = int(rows[0].get("reveal_state", 0))

	if reveal_state == 0:
		_render_unknown_cell(cx, cy)
		_rendered_cells[cell] = true
		return false

	var item: Dictionary = {}
	if _synth_cache.has(cell):
		item = _synth_cache.get_item(cell)
	elif _synth_worker != null and _synth_worker.is_running():
		var res: Dictionary = _synth_worker.request_cell_sync(cell, (_current_zoom_step < 1.0), reveal_state, _preview_cleared)
		item = {
			"buf": res["tiles"],
			"signs": res["signs"],
			"has_data": res["has_data"],
			"image": res.get("image", null),
			"thread_id": res.get("thread_id", 0),
			"reveal_state": reveal_state
		}
		_synth_cache.put(cell, item)
	else:
		var area: Dictionary = {}
		if _has_active_waypost:
			area["waypost_wm"] = _active_waypost_wm
		var has_map_data := false
		var is_covered_by_store := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n_cell := Vector2i(cx + dx, cy + dy)
				var n_feat := _get_cell_features(n_cell.x, n_cell.y)
				area[Vector2i(dx, dy)] = n_feat
				if n_feat.get("has_data", false):
					has_map_data = true
				if n_feat.get("is_covered", false):
					is_covered_by_store = true
		var synth_res: Dictionary = TileSynth2.synthesize_cell(cx, cy, area)
		item = {
			"buf": synth_res.get("tiles", PackedByteArray()),
			"signs": synth_res.get("signs", []),
			"has_data": has_map_data or is_covered_by_store,
			"thread_id": OS.get_thread_caller_id(),
			"reveal_state": reveal_state
		}
		_synth_cache.put(cell, item)

	_blit_cell(cx, cy, item)
	_flush_overview_chunks()
	_rendered_cells[cell] = true
	var is_unmapped: bool = (reveal_state > 0 and not item.get("has_data", false))
	return is_unmapped

func get_synth_worker() -> SynthWorker:
	return _synth_worker

func get_max_blits_per_frame() -> int:
	return _max_blits_observed

func reset_max_blits_observed() -> void:
	_max_blits_observed = 0

func get_steady_frame_p95_ms() -> float:
	if _steady_frame_times.is_empty():
		return get_frame_p95_ms()
	var sorted := _steady_frame_times.duplicate()
	sorted.sort()
	var idx := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return sorted[idx]

func _render_solid_fog(cx: int, cy: int) -> void:
	var solid_fog_row: int = _fog_rows.get("solid", 54)
	for ty in 32:
		for tx in 32:
			var st := _screen_tile(cx, cy, tx, ty)
			if _fog_layer != null:
				_fog_layer.set_cell(st, 0, Vector2i(0, solid_fog_row))
			if _world_known != null:
				_world_known.erase_cell(st)
			if _world_cleared != null:
				_world_cleared.erase_cell(st)

func _unrender_cell(cx: int, cy: int) -> void:
	var cell := Vector2i(cx, cy)
	_unmapped_revealed_cells.erase(cell)
	for ty in 32:
		for tx in 32:
			var coord := _screen_tile(cx, cy, tx, ty)
			if _world_known != null:
				_world_known.erase_cell(coord)
			if _world_cleared != null:
				_world_cleared.erase_cell(coord)
			if _fog_layer != null:
				_fog_layer.erase_cell(coord)

func get_lru_cache() -> LruCache:
	return _synth_cache

func get_frame_p95_ms() -> float:
	if _frame_times.is_empty():
		return 0.0
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var idx := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return sorted[idx]

func print_p95_frame_time() -> float:
	var p95 := get_frame_p95_ms()
	print("FRAME_P95_MS: %.2f" % p95)
	return p95

func pending_cell_count() -> int:
	if _camera == null:
		return 0
	var vp_size := get_viewport_rect().size / _camera.zoom.x
	var cam_pos := _camera.position
	var vis_rect := Rect2(cam_pos - vp_size * 0.5, vp_size).grow(CELL_SIZE_PX)

	var min_cx := int(floor(vis_rect.position.x / CELL_SIZE_PX))
	var max_cx := int(floor((vis_rect.position.x + vis_rect.size.x) / CELL_SIZE_PX))
	var r0 := int(floor(vis_rect.position.y / CELL_SIZE_PX))
	var r1 := int(floor((vis_rect.position.y + vis_rect.size.y) / CELL_SIZE_PX))
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1
	var pending := _dirty_overview_chunks.size()
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _rendered_cells.has(cell):
				pending += 1
	return pending

func count_visible_doors() -> int:
	if _camera == null:
		return 0
	var vp_size: Vector2 = get_viewport_rect().size / _camera.zoom.x
	var cam_pos: Vector2 = _camera.position
	var view_rect := Rect2(cam_pos - vp_size * 0.5, vp_size)

	var min_cx := int(floor(view_rect.position.x / CELL_SIZE_PX))
	var max_cx := int(floor((view_rect.position.x + view_rect.size.x) / CELL_SIZE_PX))
	var r0 := int(floor(view_rect.position.y / CELL_SIZE_PX))
	var r1 := int(floor((view_rect.position.y + view_rect.size.y) / CELL_SIZE_PX))
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1

	var visible_doors := 0
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _synth_cache.has(cell):
				continue
			var item: Dictionary = _synth_cache.get_item(cell)
			var buf: PackedByteArray = item.get("buf", PackedByteArray())
			if buf.is_empty():
				continue
			for ty in 32:
				for tx in 32:
					var idx := (ty * 32 + tx) * 3
					if idx < buf.size() and buf[idx] == TileSynth2.TILE_DOOR:
						var st := _screen_tile(cx, cy, tx, ty)
						var tile_rect := Rect2(float(st.x) * 32.0, float(st.y) * 32.0, 32.0, 32.0)
						if view_rect.intersects(tile_rect):
							visible_doors += 1
	return visible_doors

func setup_screenshot(path: String, zoom_step: float, frames: int, focus: String = "most_visited") -> void:
	_screenshot_mode = true
	_screenshot_path = path
	_screenshot_zoom = zoom_step
	_screenshot_target_frames = frames
	_screenshot_focus = focus
	_focus_mode = focus
	_set_zoom_step(zoom_step)
	if _focus_mode == "most_buildings":
		_focus_most_buildings()
	elif _focus_mode == "far_buildings":
		_focus_far_buildings()
	elif _focus_mode == "waypost":
		_focus_waypost()
	elif _focus_mode == "landmark":
		_focus_landmark()
	else:
		_focus_initial_cell()
	_pending_blit_cells.clear()
	_requested_cells.clear()
	_load_start_time_usec = Time.get_ticks_usec()
	_load_max_frame_ms = 0.0
	_load_done = false
	_steady_frames_count = 0
	_steady_frame_times.clear()
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func _on_frame_post_draw() -> void:
	if not _screenshot_mode:
		return
	_total_rendered_frames += 1

	if not _screenshot_saved:
		if pending_cell_count() > 0:
			return
		_screenshot_frames_waited += 1
		if _screenshot_frames_waited >= _screenshot_target_frames:
			var img: Image = get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				var err := img.save_png(_screenshot_path)
				if err != OK:
					printerr("[FAIL] Failed to save screenshot to %s: %d" % [_screenshot_path, err])
					get_tree().quit(1)
					return
				print("SCREENSHOT_SAVED %s" % _screenshot_path.get_file())
				var visible_doors := count_visible_doors()
				print("VISIBLE_DOORS %d" % visible_doors)
				_screenshot_saved = true
			else:
				printerr("[FAIL] Viewport texture returned empty image")
				get_tree().quit(1)
				return

	if _screenshot_saved and _steady_frames_count >= 120:
		var p95 := get_steady_frame_p95_ms()
		var refresh_rate := DisplayServer.screen_get_refresh_rate()
		if refresh_rate <= 0.0:
			refresh_rate = 60.0
		var vsync_ms := 1000.0 / refresh_rate
		print("VSYNC_MS: %.2f" % vsync_ms)
		print("FRAME_P95_MS: %.2f" % p95)
		get_tree().quit(0)

func set_map_fetcher(fetcher) -> void:
	if _map_fetcher != null and _map_fetcher is Object:
		if _map_fetcher.is_connected("install_progress", Callable(self, "_on_install_progress")):
			_map_fetcher.disconnect("install_progress", Callable(self, "_on_install_progress"))
		if _map_fetcher.is_connected("install_finished", Callable(self, "_on_install_finished")):
			_map_fetcher.disconnect("install_finished", Callable(self, "_on_install_finished"))
	_map_fetcher = fetcher
	if _map_fetcher != null and _map_fetcher is Object:
		if _map_fetcher.has_signal("install_progress") and not _map_fetcher.is_connected("install_progress", Callable(self, "_on_install_progress")):
			_map_fetcher.connect("install_progress", Callable(self, "_on_install_progress"), Object.CONNECT_DEFERRED)
		if _map_fetcher.has_signal("install_finished") and not _map_fetcher.is_connected("install_finished", Callable(self, "_on_install_finished")):
			_map_fetcher.connect("install_finished", Callable(self, "_on_install_finished"), Object.CONNECT_DEFERRED)

func configure_unmapped_region(cells: Array) -> Dictionary:
	if _map_fetcher == null:
		return {}
	var res: Dictionary = _map_fetcher.select_region_for_cells(cells)
	return configure_unmapped_region_data(res)

func configure_unmapped_region_data(reg_data: Dictionary) -> Dictionary:
	_pending_region = reg_data
	if reg_data.get("beyond_the_map", false):
		_is_beyond_the_map = true
		_pending_size_mb = 0
		if _chip_label != null:
			_chip_label.text = "Beyond the map — Tenth Spring covers the USA"
		if _unmapped_chip != null:
			_unmapped_chip.visible = true
		return reg_data

	_is_beyond_the_map = false
	if reg_data.is_empty():
		_pending_size_mb = 0
		if _chip_label != null:
			_chip_label.text = MapFetcher.UNMAPPED_FALLBACK_TEXT
		return {}

	var r_name: String = str(reg_data.get("name", ""))
	_pending_size_mb = _map_fetcher.fetch_region_size_mb(reg_data)
	if _chip_label != null:
		_chip_label.text = MapFetcher.format_unmapped_chip_text(r_name, _pending_size_mb)
	if _download_dialog != null:
		_download_dialog.dialog_text = MapFetcher.format_download_dialog_text(r_name, _pending_size_mb)
		_download_dialog.ok_button_text = MapFetcher.CONFIRM_BUTTON_TEXT
		_download_dialog.cancel_button_text = MapFetcher.CANCEL_BUTTON_TEXT
	if _unmapped_chip != null:
		_unmapped_chip.visible = true
	return _pending_region

func _on_unmapped_chip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_beyond_the_map:
				return
			open_download_dialog()

func open_download_dialog() -> void:
	if _is_beyond_the_map:
		return
	if _download_dialog != null and not _pending_region.is_empty():
		_download_dialog.popup_centered()

func cancel_download_dialog() -> void:
	if _download_dialog != null:
		_download_dialog.hide()

func _on_download_dialog_confirmed() -> void:
	if _download_dialog != null:
		_download_dialog.hide()
	if _map_fetcher != null and not _pending_region.is_empty():
		if _install_panel != null:
			_install_panel.visible = true
		if _install_label != null:
			_install_label.text = "Downloading %s — 0 / %d MB" % [_pending_region.get("name", ""), _pending_size_mb]
		_map_fetcher.start_install(_pending_region)

func confirm_download_dialog() -> Dictionary:
	if _download_dialog != null:
		_download_dialog.hide()
	if _map_fetcher == null or _pending_region.is_empty():
		return {"ok": false, "error": "No pending region"}
	var res: Dictionary = _map_fetcher.download_and_install_region(_pending_region)
	if res.get("ok", false):
		_load_map_stores()
		_synth_cache.clear()
		_store_cache.clear()
		_clear_rendered_layers()
		_update_frustum_culling()
		if _update_map_button != null:
			_update_map_button.visible = true
	return res

func _on_install_progress(stage: String, done: int, total: int) -> void:
	if _install_panel != null:
		_install_panel.visible = true
	if _install_label == null:
		return
	if stage == "download":
		var done_mb := int(round(float(done) / (1024.0 * 1024.0)))
		var total_mb := int(round(float(total) / (1024.0 * 1024.0)))
		_install_label.text = "Downloading %s — %d / %d MB" % [_pending_region.get("name", ""), done_mb, total_mb]
	elif stage == "verify":
		_install_label.text = "Checking download…"
	elif stage == "convert":
		_install_label.text = "Preparing map — pass %d of 3" % done

func _on_install_finished(result: Dictionary) -> void:
	if _install_panel != null:
		_install_panel.visible = false
	if result.get("ok", false):
		_load_map_stores()
		var db_inst = _get_db()
		if db_inst != null:
			RevealEngine.apply(db_inst, _map_stores)
		_synth_cache.clear()
		_store_cache.clear()
		_clear_rendered_layers()
		_update_frustum_culling()
		if _unmapped_chip != null:
			_unmapped_chip.visible = false
		if _update_map_button != null:
			_update_map_button.visible = true
		_pending_region = {}
	else:
		var err := str(result.get("error", "Download failed"))
		if _unmapped_chip != null:
			_unmapped_chip.visible = true
		if _chip_label != null:
			_chip_label.text = "Download failed — %s. Click to retry." % err

func _on_install_cancel_pressed() -> void:
	if _map_fetcher != null and _map_fetcher.has_method("cancel_install"):
		_map_fetcher.cancel_install()

func trigger_update_map_data() -> Dictionary:
	if _map_fetcher == null or _pending_region.is_empty():
		return {"ok": false, "error": "No region configured for update"}
	var res: Dictionary = _map_fetcher.update_region(_pending_region)
	if res.get("ok", false):
		_load_map_stores()
		_synth_cache.clear()
		_store_cache.clear()
		_clear_rendered_layers()
		_update_frustum_culling()
	return res

func _exit_tree() -> void:
	if _synth_worker != null:
		_synth_worker.stop()
		_synth_worker = null
	if _lookup_thread != null and _lookup_thread.is_alive():
		_lookup_thread.wait_to_finish()
		_lookup_thread = null
	for store in _map_stores:
		store.close()
	_map_stores.clear()
