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
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const WorldClock := preload("res://world/world_clock.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const OutdoorFixtures := preload("res://world/caricature/outdoor_fixtures.gd")
const PeopleSprites := preload("res://world/people_sprites.gd")
const PlayerWalker := preload("res://world/player_walker.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const MapConstants := preload("res://world/map_constants.gd")
const SpawnDirector := preload("res://encounters/spawn_director.gd")
const TimeOfDayShader := preload("res://world/shaders/time_of_day.gdshader")
const InteriorTiles := preload("res://world/interior/interior_tiles.gd")

signal door_entered(interior_id: String, return_info: Dictionary)

const CELL_SIZE_PX := 1024.0
const TILE_SIZE_PX := 32
const CELL_TILES := 32
const PAN_SPEED := 600.0

const MAX_SYNTH_CELLS := 1024
const MAX_STORE_CELLS := 256
const SYNTH_BUDGET_USEC := 8000 # 8 ms budget per frame

const ZOOM_STEPS: Array = [0.0625, 0.25, 0.5, 1.0, 2.0]
const WALK_ZOOM_STEPS: Array = [0.5, 1.0, 2.0]

# Palette colors for overview texture (§5.3)
const MAP_COLORS := {
	0: Color("#2a3242"),  # VOID
	1: Color("#6cb458"),  # GRASS
	2: Color("#448238"),  # TALL_GRASS
	3: Color("#2c602e"),  # TREE
	4: Color("#58a4d4"),  # WATER
	5: Color("#d4bc86"),  # SAND
	6: Color("#587650"),  # MARSH
	7: Color("#c4a474"),  # PATH
	8: Color("#868e96"),  # ROAD
	9: Color("#747c84"),  # RAIL
	10: Color("#ac7c4c"), # BRIDGE
	11: Color("#b2b2aa"), # PLAZA
	13: Color("#e8e0d0"), # WALL
	14: Color("#845a38"), # DOOR
	15: Color("#cca472"), # FENCE
	16: Color("#f85878"), # FLOWERS
	17: Color("#b2b2aa"), # GRAVE
	18: Color("#ac7c4c"), # SIGN
	19: Color("#92d472"), # CROP
	20: Color("#948674"), # RUBBLE
	21: Color("#948674"), # STAMP
	22: Color("#4c8e40"), # LEDGE
	23: Color("#7a5c43"), # CLIFF
	24: Color("#b8b4aa"), # STAIRS
	25: Color("#3f7a34"), # CUT_TREE
	26: Color("#7d6852"), # SMASH_ROCK
	27: Color("#94856a"), # BOULDER
	28: Color("#d14b3a"), # ITEM_BALL
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
var _rendered_reveal_state: Dictionary = {} # Vector2i -> int

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
var _tree_base_known: TileMapLayer = null
var _tree_base_cleared: TileMapLayer = null
var _tree_top_known: TileMapLayer = null
var _tree_top_cleared: TileMapLayer = null
var _fog_layer: ColorRect = null
var _overview_layer: Node2D = null
const FOG_GRID_SIZE: int = 64
var _fog_grid_img: Image = null
var _fog_grid_tex: ImageTexture = null
var _fog_grid_origin: Vector2i = Vector2i(-32, -32)
var _fog_town_rects: Array[Vector4] = []
var _fog_dirty: bool = true
var _fog_state_sig: String = ""
var _stamp_base_layer: Node2D = null
var _stamp_overhang_layer: Node2D = null
var _cell_stamp_sprites: Dictionary = {} # Vector2i -> Array[Sprite2D]
var _stamp_images: Dictionary = {} # stamp_id (int) -> Image
var _stamp_textures: Dictionary = {} # stamp_id (int) -> ImageTexture
var _tiled_stamp_textures: Dictionary = {} # Vector3i(stamp_id, w, h) -> ImageTexture
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
var _board_button: Button = null
var _back_to_camp_button: Button = null
var _waypost_board: Control = null
var _lamp_menu: Control = null
var _dialogue_box: Control = null
var _collected_hidden_keys: Dictionary = {} # "hidden:<area_id>:<lx>:<ly>" -> true
var _person_facing_overrides: Dictionary = {} # Vector2i global -> "N"|"S"|"E"|"W"
var _person_sprites_by_global: Dictionary = {} # Vector2i global -> Array[Dictionary]

const OUTDOOR_BALL_ITEM_POOL: Array[String] = [
	"Potion", "Super Potion", "Poké Ball", "Great Ball",
	"Antidote", "Escape Rope", "Repel", "Revive",
]
var _distortion_field_layer: Node2D = null
var _distortion_field_rect: ColorRect = null
var _distortion_field_chip: Label = null
var _active_distortion_field: Dictionary = {}
var _active_place_id: String = ""
var _render_origin_sc: Vector2i = Vector2i.ZERO # Top-left screen-cell (scx=cx, scy=-cy-1) of loaded place (Item 75 / F88-F89)
var _render_origin_tile: Vector2i = Vector2i.ZERO # _render_origin_sc * 32 in whole tiles
var _active_waypost_cell: Vector2i = Vector2i.ZERO
var _active_waypost_wm: Vector2 = Vector2.ZERO
var _has_active_waypost: bool = false
var _is_caricature_place: bool = false
var _excluded_store_place_id: String = ""
var _forced_caricature_area_id: String = ""
var _forced_caricature_place_id: String = ""
var _caricature_cells: Dictionary = {} # Vector2i -> {compiled: Dictionary, area: Dictionary}
var _caricature_compiled_by_area: Dictionary = {} # area_id -> compiled Dictionary
var _caricature_camp_id: String = ""
var _walk_mode_active: bool = false
var _camera_follows_player: bool = false
var _player_walker: PlayerWalker = null
var _walker_grid: CaricatureWalkerGrid = null
var _current_walk_area_id: String = ""
var _world_clock: WorldClock = WorldClock.new()
var _route_origin_area_id: String = ""
var _active_route_id: String = ""
var _route_time_accum_milli: int = 0
var _route_time_charged_min: int = 0
var _route_idle_seconds: float = 0.0
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_timer: float = 0.0
var _last_toast_text: String = ""
var _banner_panel: PanelContainer = null
var _banner_label: Label = null
var _banner_timer: float = 0.0
var _last_banner_text: String = ""
var _time_of_day_layer: CanvasLayer = null
var _time_of_day_rect: ColorRect = null
var _walk_hud_panel: PanelContainer = null
var _walk_hud_label: Label = null
var _all_lamp_world_tiles: Array[Vector2] = []
var _time_of_day_override_min: float = -1.0
var _cached_neighbourhood_states: Dictionary = {}
var _neighbourhood_states_dirty: bool = true
var _cached_states_db_path: String = ""
var _cached_states_rev: int = -1
var _focused_area_id: String = ""
var _focused_area_tiles: Vector2i = Vector2i.ZERO
var _focused_city_cells: Vector2i = Vector2i.ZERO
var _screenshot_area_id: String = ""
var _force_no_rom: bool = false
var _data_cache_dir: String = AssetDB.DEFAULT_CACHE_DIR
var _has_screenshot_tile: bool = false
var _screenshot_tile: Vector2i = Vector2i(-1, -1)

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
var _screenshot_saved: bool = false:

	set(value):
		_screenshot_saved = value
		if _screenshot_saved and is_inside_tree():
			_arm_steady_timer()
var _screenshot_timed_out: bool = false
## Seconds after launch (engine start) at which the screenshot harness gives up (exit code 3) instead of hanging (Item 25b).
var screenshot_timeout_sec: float = 120.0
var _screenshot_focus: String = "most_visited"
var _focus_mode: String = "most_visited"
var _total_rendered_frames: int = 0
var _steady_timer: SceneTreeTimer = null
var harness_fail_handler: Callable = Callable()


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
	_fog_layer = get_node_or_null("FogLayer") as ColorRect
	_overview_layer = get_node_or_null("OverviewLayer") as Node2D
	if _fog_layer != null:
		_fog_layer.z_index = 35
		_fog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fog_layer.visible = true
		_init_fog_overlay()
	if _overview_layer != null:
		_overview_layer.z_index = 30

	_stamp_base_layer = get_node_or_null("StampBaseLayer") as Node2D
	if _stamp_base_layer == null:
		_stamp_base_layer = Node2D.new()
		_stamp_base_layer.name = "StampBaseLayer"
		_stamp_base_layer.z_index = 1
		_stamp_base_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_stamp_base_layer)
	_stamp_base_layer.y_sort_enabled = true

	_stamp_overhang_layer = get_node_or_null("StampOverhangLayer") as Node2D
	if _stamp_overhang_layer == null:
		_stamp_overhang_layer = Node2D.new()
		_stamp_overhang_layer.name = "StampOverhangLayer"
		_stamp_overhang_layer.z_index = 10
		_stamp_overhang_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_stamp_overhang_layer)
	_stamp_overhang_layer.y_sort_enabled = true

	_tree_base_known = get_node_or_null("TreeBaseKnown") as TileMapLayer
	if _tree_base_known == null:
		_tree_base_known = TileMapLayer.new()
		_tree_base_known.name = "TreeBaseKnown"
		_tree_base_known.z_index = 0
		_tree_base_known.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _world_known != null:
			_tree_base_known.material = _world_known.material
		add_child(_tree_base_known)
		if _world_cleared != null:
			move_child(_tree_base_known, _world_cleared.get_index() + 1)

	_tree_base_cleared = get_node_or_null("TreeBaseCleared") as TileMapLayer
	if _tree_base_cleared == null:
		_tree_base_cleared = TileMapLayer.new()
		_tree_base_cleared.name = "TreeBaseCleared"
		_tree_base_cleared.z_index = 0
		_tree_base_cleared.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_tree_base_cleared)
		if _tree_base_known != null:
			move_child(_tree_base_cleared, _tree_base_known.get_index() + 1)

	_tree_top_known = get_node_or_null("TreeTopKnown") as TileMapLayer
	if _tree_top_known == null:
		_tree_top_known = TileMapLayer.new()
		_tree_top_known.name = "TreeTopKnown"
		_tree_top_known.z_index = 2
		_tree_top_known.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _world_known != null:
			_tree_top_known.material = _world_known.material
		add_child(_tree_top_known)

	_tree_top_cleared = get_node_or_null("TreeTopCleared") as TileMapLayer
	if _tree_top_cleared == null:
		_tree_top_cleared = TileMapLayer.new()
		_tree_top_cleared.name = "TreeTopCleared"
		_tree_top_cleared.z_index = 2
		_tree_top_cleared.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_tree_top_cleared)

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
	_board_button = get_node_or_null("AttributionUI/BoardButton") as Button
	if _board_button != null:
		_board_button.pressed.connect(_on_board_pressed)
	_back_to_camp_button = get_node_or_null("AttributionUI/BackToCampButton") as Button
	if _back_to_camp_button != null:
		_back_to_camp_button.pressed.connect(_on_back_to_camp_pressed)

	_distortion_field_layer = get_node_or_null("DistortionFieldLayer") as Node2D
	if _distortion_field_layer == null:
		_distortion_field_layer = Node2D.new()
		_distortion_field_layer.name = "DistortionFieldLayer"
		_distortion_field_layer.z_index = 15
		add_child(_distortion_field_layer)
	_distortion_field_rect = _distortion_field_layer.get_node_or_null("FieldRect") as ColorRect
	if _distortion_field_rect == null:
		_distortion_field_rect = ColorRect.new()
		_distortion_field_rect.name = "FieldRect"
		_distortion_field_rect.color = Color(0.68, 0.22, 0.85, 0.22)
		_distortion_field_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_distortion_field_rect.visible = false
		_distortion_field_layer.add_child(_distortion_field_rect)

	var attr_ui := get_node_or_null("AttributionUI") as CanvasLayer
	if attr_ui != null:
		if attr_ui.layer < 10:
			attr_ui.layer = 10
		_distortion_field_chip = attr_ui.get_node_or_null("DistortionFieldChip") as Label
		if _distortion_field_chip == null:
			_distortion_field_chip = Label.new()
			_distortion_field_chip.name = "DistortionFieldChip"
			_distortion_field_chip.position = Vector2(16.0, 52.0)
			_distortion_field_chip.visible = false
			attr_ui.add_child(_distortion_field_chip)
		_init_walk_banners(attr_ui)
		_init_walk_hud(attr_ui)
	_init_time_of_day_overlay()

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
	if _tree_base_known != null:
		_tree_base_known.clear()
	if _tree_base_cleared != null:
		_tree_base_cleared.clear()
	if _tree_top_known != null:
		_tree_top_known.clear()
	if _tree_top_cleared != null:
		_tree_top_cleared.clear()
	_fog_dirty = true
	_fog_state_sig = ""
	for cell_k in _cell_stamp_sprites.keys():
		_clear_cell_stamps(cell_k)
	_cell_stamp_sprites.clear()
	for s in _overview_sprites.values():
		if is_instance_valid(s):
			s.queue_free()
	_overview_sprites.clear()
	_overview_chunks.clear()
	_dirty_overview_chunks.clear()
	_rendered_cells.clear()
	_rendered_reveal_state.clear()
	_pending_blit_cells.clear()
	_requested_cells.clear()

func _init_tile_sets() -> void:
	var atlas_data: Variant = null if _force_no_rom else AssetDB.tile_atlas()
	var texture: Texture2D = null
	var json_dict: Dictionary = {}

	if atlas_data != null and atlas_data is Dictionary and atlas_data.has("texture") and atlas_data.has("json"):
		texture = atlas_data["texture"]
		json_dict = atlas_data["json"]
	else:
		for png_res in ["res://assets/tiles/original_v1.png", "res://assets/tiles/placeholder_v1.png"]:
			var abs_p := ProjectSettings.globalize_path(png_res)
			if FileAccess.file_exists(abs_p):
				var bytes := FileAccess.get_file_as_bytes(abs_p)
				if not bytes.is_empty():
					var img := Image.new()
					if img.load_png_from_buffer(bytes) == OK and not img.is_empty():
						texture = ImageTexture.create_from_image(img)
			if texture == null and ResourceLoader.exists(png_res):
				texture = load(png_res) as Texture2D
			if texture != null:
				break

		var json_text := ""
		for json_path in ["res://assets/tiles/original_v1.json", "res://assets/tiles/placeholder_v1.json"]:
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
				break
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
	for fv in _fog_rows.values():
		max_row = maxi(max_row, int(fv))

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
	if _tree_base_known != null:
		_tree_base_known.tile_set = tileset
	if _tree_base_cleared != null:
		_tree_base_cleared.tile_set = tileset
	if _tree_top_known != null:
		_tree_top_known.tile_set = tileset
	if _tree_top_cleared != null:
		_tree_top_cleared.tile_set = tileset

func get_atlas_coords(cls: int, variant: int, mask: int) -> Vector2i:
	if cls == TileSynth2.TILE_STAMP or (cls == TileSynth2.TILE_DOOR and mask > 0):
		cls = TileSynth2.TILE_GRASS
		variant = 0
		mask = 0
	var row := 0
	if _class_any_variant.has(cls):
		row = _class_any_variant[cls]
	elif _class_variant_to_row.has(Vector2i(cls, variant)):
		row = _class_variant_to_row[Vector2i(cls, variant)]
	elif _class_variant_to_row.has(Vector2i(cls, 0)):
		row = _class_variant_to_row[Vector2i(cls, 0)]

	var col := (mask & 7) if cls == TileSynth2.TILE_TREE else (mask if _masked_classes.get(cls, false) else 0)
	return Vector2i(col, row)

## S2 (Decision 76): Draw landmark and prop cells over the map file's own ground tile
## (e.g. plaza under the Capitol) rather than plain grass; leave houses/blocks outside DC untouched.
func get_tile_atlas_coords(tile_buf: PackedByteArray, under_buf: PackedByteArray, idx: int) -> Vector2i:
	var cls: int = tile_buf[idx]
	var v: int = tile_buf[idx + 1]
	var mask: int = tile_buf[idx + 2]
	if (cls == TileSynth2.TILE_STAMP or (cls == TileSynth2.TILE_DOOR and mask > 0)) and under_buf.size() == tile_buf.size():
		var sid: int = v if cls == TileSynth2.TILE_STAMP else mask
		var skind := str(TileSynth2.get_stamp_def(sid).get("kind", ""))
		if skind == "landmark" or skind == "prop":
			return get_atlas_coords(under_buf[idx], under_buf[idx + 1], under_buf[idx + 2])
	return get_atlas_coords(cls, v, mask)

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
					if schema_ver != "5":
						print("map: skipping %s — store schema %s, need 5" % [f, schema_ver])
						store.close()
					else:
						var s_place_id := store.get_state("place_id", "")
						if s_place_id.is_empty() and "district-of-columbia" in f:
							s_place_id = "city:washington-dc"
						if not _excluded_store_place_id.is_empty() and s_place_id == _excluded_store_place_id:
							store.close()
							continue
						_map_stores.append(store)
						store_paths.append(p)
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
		_synth_worker.set_caricature(_caricature_cells)
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

		# 2. Check active Waypost cell
		if not found and _has_active_waypost:
			target_cell = _active_waypost_cell
			found = true

		# 3. Fall back to any revealed map_cell
		if not found:
			var cell_rows = db.query_rows("SELECT cell_x, cell_y FROM map_cell WHERE reveal_state > 0 LIMIT 1;")
			if not cell_rows.is_empty():
				target_cell = Vector2i(int(cell_rows[0]["cell_x"]), int(cell_rows[0]["cell_y"]))
				found = true

	focus_on_cell(target_cell.x, target_cell.y)

func get_render_origin_tile() -> Vector2i:
	return _render_origin_tile

func get_render_origin_screen_cell() -> Vector2i:
	return _render_origin_sc

func _set_render_origin_from_screen_cell(sc: Vector2i) -> void:
	_render_origin_sc = sc
	_render_origin_tile = Vector2i(sc.x * CELL_TILES, sc.y * CELL_TILES)
	if _player_walker != null:
		_player_walker.set_render_origin_tile(_render_origin_tile)

func _global_to_render_tile(gt: Vector2i) -> Vector2i:
	return gt - _render_origin_tile

func _render_px_to_global_tile(rp: Vector2) -> Vector2i:
	return Vector2i(floori(rp.x / float(TILE_SIZE_PX)), floori(rp.y / float(TILE_SIZE_PX))) + _render_origin_tile

func _cell_to_render_px_center(cx: int, cy: int) -> Vector2:
	var scx := cx - _render_origin_sc.x
	var scy := (-cy - 1) - _render_origin_sc.y
	return Vector2((float(scx) + 0.5) * CELL_SIZE_PX, (float(scy) + 0.5) * CELL_SIZE_PX)

func _sync_camera_to_player() -> void:
	if _walk_mode_active and _camera_follows_player and _camera != null and _player_walker != null:
		_camera.position = _player_walker.get_camera_target()

func focus_on_cell(cx: int, cy: int) -> void:
	_focused_area_id = ""
	_focused_area_tiles = Vector2i.ZERO
	_focused_city_cells = Vector2i.ZERO
	_camera_follows_player = false
	if _camera != null:
		_camera.position = _cell_to_render_px_center(cx, cy)
	_update_return_home_visibility()

func set_data_cache_dir(dir_path: String) -> void:
	var s := dir_path.strip_edges()
	_data_cache_dir = AssetDB.DEFAULT_CACHE_DIR if s.is_empty() else s

func set_force_no_rom(enabled: bool) -> void:
	var changed := (_force_no_rom != enabled)
	_force_no_rom = enabled
	if _player_walker != null:
		_player_walker.set_force_no_rom(enabled)
	if changed and is_inside_tree():
		_init_tile_sets()

func is_walk_mode_active() -> bool:
	return _walk_mode_active

func get_player_walker() -> PlayerWalker:
	return _player_walker

func get_walker_grid() -> CaricatureWalkerGrid:
	return _walker_grid

func get_current_walk_area_id() -> String:
	return _current_walk_area_id

func get_world_clock() -> WorldClock:
	return _world_clock

static func format_arrival_banner(place_name: String) -> String:
	return "You are in %s. You have what you carry. The way home is this Waypost." % place_name

static func format_resume_banner(place_id: String, area_id: String, place_name: String) -> String:
	var a_dict: Dictionary = Neighbourhoods.area(area_id)
	var kind := str(a_dict.get("kind", ""))
	if kind == "camp" or area_id.begins_with("camp:"):
		return format_arrival_banner(place_name)
	var display_name := str(a_dict.get("name", area_id))
	if kind == "route" or area_id.begins_with("route:"):
		var rid := str(a_dict.get("route_id", ""))
		if not rid.is_empty():
			var r_dict: Dictionary = Neighbourhoods.route(rid)
			display_name = str(r_dict.get("name", display_name))
	var mins := NeighbourhoodProgress.waypost_minutes_from_area(place_id, area_id, false)
	return "You are in %s. The Waypost is %d min on foot." % [display_name, mins]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _walk_mode_active and not _screenshot_mode:
			_world_clock.save_to_db()
			persist_player_session()

func get_last_toast_text() -> String:
	return _last_toast_text

func get_last_banner_text() -> String:
	return _last_banner_text

func get_route_crossing_state() -> Dictionary:
	return {
		"route_origin_area_id": _route_origin_area_id,
		"active_route_id": _active_route_id,
		"route_time_accum_milli": _route_time_accum_milli,
		"route_time_charged_min": _route_time_charged_min,
	}

func set_route_crossing_state(origin_area_id: String, route_id: String, accum_milli: int = 0, charged_min: int = 0) -> void:
	_route_origin_area_id = origin_area_id
	_active_route_id = route_id
	_route_time_accum_milli = maxi(0, accum_milli)
	_route_time_charged_min = maxi(0, charged_min)
	_route_idle_seconds = 0.0

func _init_walk_banners(attr_ui: Node) -> void:
	if _banner_panel == null:
		_banner_panel = PanelContainer.new()
		_banner_panel.name = "WalkBannerPanel"
		_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner_panel.anchor_left = 0.5
		_banner_panel.anchor_right = 0.5
		_banner_panel.anchor_top = 0.0
		_banner_panel.anchor_bottom = 0.0
		_banner_panel.offset_left = -360.0
		_banner_panel.offset_right = 360.0
		_banner_panel.offset_top = 50.0
		_banner_panel.offset_bottom = 88.0
		var bstyle := StyleBoxFlat.new()
		bstyle.bg_color = Color(0.08, 0.11, 0.17, 0.90)
		bstyle.border_width_left = 1
		bstyle.border_width_top = 1
		bstyle.border_width_right = 1
		bstyle.border_width_bottom = 1
		bstyle.border_color = Color(0.55, 0.72, 0.92, 0.85)
		bstyle.corner_radius_top_left = 6
		bstyle.corner_radius_top_right = 6
		bstyle.corner_radius_bottom_left = 6
		bstyle.corner_radius_bottom_right = 6
		bstyle.content_margin_left = 14.0
		bstyle.content_margin_right = 14.0
		bstyle.content_margin_top = 6.0
		bstyle.content_margin_bottom = 6.0
		_banner_panel.add_theme_stylebox_override("panel", bstyle)
		_banner_label = Label.new()
		_banner_label.name = "WalkBannerLabel"
		_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner_label.add_theme_font_size_override("font_size", 14)
		_banner_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
		_banner_panel.add_child(_banner_label)
		_banner_panel.visible = false
		attr_ui.add_child(_banner_panel)

	if _toast_panel == null:
		_toast_panel = PanelContainer.new()
		_toast_panel.name = "WalkToastPanel"
		_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_panel.anchor_left = 0.5
		_toast_panel.anchor_right = 0.5
		_toast_panel.anchor_top = 1.0
		_toast_panel.anchor_bottom = 1.0
		_toast_panel.offset_left = -310.0
		_toast_panel.offset_right = 310.0
		_toast_panel.offset_top = -62.0
		_toast_panel.offset_bottom = -24.0
		var tstyle := StyleBoxFlat.new()
		tstyle.bg_color = Color(0.10, 0.12, 0.18, 0.90)
		tstyle.border_width_left = 1
		tstyle.border_width_top = 1
		tstyle.border_width_right = 1
		tstyle.border_width_bottom = 1
		tstyle.border_color = Color(0.82, 0.68, 0.36, 0.85)
		tstyle.corner_radius_top_left = 5
		tstyle.corner_radius_top_right = 5
		tstyle.corner_radius_bottom_left = 5
		tstyle.corner_radius_bottom_right = 5
		tstyle.content_margin_left = 12.0
		tstyle.content_margin_right = 12.0
		tstyle.content_margin_top = 5.0
		tstyle.content_margin_bottom = 5.0
		_toast_panel.add_theme_stylebox_override("panel", tstyle)
		_toast_label = Label.new()
		_toast_label.name = "WalkToastLabel"
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.add_theme_font_size_override("font_size", 13)
		_toast_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82, 1.0))
		_toast_panel.add_child(_toast_label)
		_toast_panel.visible = false
		attr_ui.add_child(_toast_panel)

func _init_walk_hud(attr_ui: Node) -> void:
	_walk_hud_panel = attr_ui.get_node_or_null("WalkHudPanel") as PanelContainer
	if _walk_hud_panel == null:
		_walk_hud_panel = PanelContainer.new()
		_walk_hud_panel.name = "WalkHudPanel"
		_walk_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_walk_hud_panel.anchor_left = 0.0
		_walk_hud_panel.anchor_right = 0.0
		_walk_hud_panel.anchor_top = 0.0
		_walk_hud_panel.anchor_bottom = 0.0
		_walk_hud_panel.offset_left = 10.0
		_walk_hud_panel.offset_top = 10.0
		_walk_hud_panel.offset_right = 430.0
		_walk_hud_panel.offset_bottom = 42.0
		var hstyle := StyleBoxFlat.new()
		hstyle.bg_color = Color(0.08, 0.10, 0.16, 0.86)
		hstyle.border_width_left = 1
		hstyle.border_width_top = 1
		hstyle.border_width_right = 1
		hstyle.border_width_bottom = 1
		hstyle.border_color = Color(0.70, 0.76, 0.86, 0.75)
		hstyle.corner_radius_top_left = 5
		hstyle.corner_radius_top_right = 5
		hstyle.corner_radius_bottom_left = 5
		hstyle.corner_radius_bottom_right = 5
		hstyle.content_margin_left = 10.0
		hstyle.content_margin_right = 10.0
		hstyle.content_margin_top = 4.0
		hstyle.content_margin_bottom = 4.0
		_walk_hud_panel.add_theme_stylebox_override("panel", hstyle)
		_walk_hud_label = Label.new()
		_walk_hud_label.name = "WalkHudLabel"
		_walk_hud_label.add_theme_font_size_override("font_size", 13)
		_walk_hud_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99, 1.0))
		_walk_hud_panel.add_child(_walk_hud_label)
		_walk_hud_panel.visible = false
		attr_ui.add_child(_walk_hud_panel)

func _init_time_of_day_overlay() -> void:
	_time_of_day_layer = get_node_or_null("TimeOfDayLayer") as CanvasLayer
	if _time_of_day_layer == null:
		_time_of_day_layer = CanvasLayer.new()
		_time_of_day_layer.name = "TimeOfDayLayer"
		_time_of_day_layer.layer = 5
		add_child(_time_of_day_layer)
	_time_of_day_rect = _time_of_day_layer.get_node_or_null("TimeOfDayRect") as ColorRect
	if _time_of_day_rect == null:
		_time_of_day_rect = ColorRect.new()
		_time_of_day_rect.name = "TimeOfDayRect"
		_time_of_day_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_time_of_day_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_time_of_day_rect.color = Color(1.0, 1.0, 1.0, 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = TimeOfDayShader
		_time_of_day_rect.material = mat
		_time_of_day_rect.visible = false
		_time_of_day_layer.add_child(_time_of_day_rect)

static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0 if x < edge0 else 1.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func screen_uv_to_world_tile(uv: Vector2, cam_center_tiles: Vector2, viewport_size_px: Vector2, zoom_val: float) -> Vector2:
	var z := maxf(zoom_val, 0.0001)
	var view_size_tiles := viewport_size_px / (float(TILE_SIZE_PX) * z)
	return cam_center_tiles + (uv - Vector2(0.5, 0.5)) * view_size_tiles

static func evaluate_time_of_day_at_world_tile(world_tile: Vector2, minute_of_day: float, player_world_tile: Vector2, has_player: bool = true, lamp_world_tiles: Array = []) -> Color:
	var m := fposmod(minute_of_day, 1440.0)
	var t_n_to_dawn := _smoothstep(285.0, 315.0, m)
	var t_dawn_to_day := _smoothstep(405.0, 435.0, m)
	var t_day_to_dusk := _smoothstep(1125.0, 1155.0, m)
	var t_dusk_to_n := _smoothstep(1245.0, 1275.0, m)

	var w_dawn := t_n_to_dawn * (1.0 - t_dawn_to_day)
	var w_dusk := t_day_to_dusk * (1.0 - t_dusk_to_n)
	var w_night := (1.0 - t_n_to_dawn) + t_dusk_to_n

	if w_dawn + w_dusk + w_night <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)

	var dark_factor := 1.0
	if has_player:
		var d_player := world_tile.distance_to(player_world_tile)
		dark_factor = _smoothstep(4.0, 5.0, d_player)

	var lamp_reduction := 0.0
	var lim := mini(16, lamp_world_tiles.size())
	for i in range(lim):
		var l_v = lamp_world_tiles[i]
		if l_v is Vector2:
			var d_lamp := world_tile.distance_to(l_v as Vector2)
			var lit := 1.0 - _smoothstep(1.0, 3.5, d_lamp)
			lamp_reduction = maxf(lamp_reduction, lit)

	var effective_dark := dark_factor * (1.0 - 0.85 * lamp_reduction)
	var a_dawn := w_dawn * 0.14
	var a_dusk := w_dusk * 0.24
	var a_night := w_night * 0.62 * effective_dark
	var a_lamp := w_night * 0.12 * lamp_reduction
	var a_out := clampf(a_dawn + a_dusk + a_night + a_lamp, 0.0, 1.0)
	if a_out <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var r_out := ((245.0 / 255.0) * a_dawn + (220.0 / 255.0) * a_dusk + (22.0 / 255.0) * a_night + (255.0 / 255.0) * a_lamp) / a_out
	var g_out := ((195.0 / 255.0) * a_dawn + (145.0 / 255.0) * a_dusk + (30.0 / 255.0) * a_night + (224.0 / 255.0) * a_lamp) / a_out
	var b_out := ((165.0 / 255.0) * a_dawn + (120.0 / 255.0) * a_dusk + (62.0 / 255.0) * a_night + (150.0 / 255.0) * a_lamp) / a_out
	return Color(r_out, g_out, b_out, a_out)

func set_time_of_day_override(minute: float) -> void:
	_time_of_day_override_min = minute
	refresh_time_of_day_and_hud()

func invalidate_neighbourhood_state_cache() -> void:
	_neighbourhood_states_dirty = true

func _get_cached_neighbourhood_states() -> Dictionary:
	var db = _get_db()
	if db == null or not db.is_open():
		return {}
	var cur_path := str(db.DB_PATH) if ("DB_PATH" in db) else ""
	var cur_rev := int(db.neighbourhood_state_revision) if ("neighbourhood_state_revision" in db) else -1
	if _neighbourhood_states_dirty or cur_path != _cached_states_db_path or cur_rev != _cached_states_rev or _cached_neighbourhood_states.is_empty():
		_cached_neighbourhood_states = {"__loaded__": -1}
		for ns_var in db.get_neighbourhood_states(_active_place_id):
			if ns_var is Dictionary:
				var ns_d: Dictionary = ns_var
				_cached_neighbourhood_states[str(ns_d.get("area_id", ""))] = int(ns_d.get("state", 0))
		_cached_states_db_path = cur_path
		_cached_states_rev = cur_rev
		_neighbourhood_states_dirty = false
	return _cached_neighbourhood_states

func get_walk_hud_text() -> String:
	if _walk_hud_label != null:
		return _walk_hud_label.text
	return ""

func _band_display_name(band: String) -> String:
	match band:
		"dawn":
			return "Dawn"
		"day":
			return "Day"
		"dusk":
			return "Dusk"
		"night":
			return "Night"
		_:
			return band.capitalize()

func refresh_time_of_day_and_hud() -> void:
	var show_tod: bool = _walk_mode_active or _time_of_day_override_min >= 0.0
	if _time_of_day_rect != null:
		_time_of_day_rect.visible = show_tod
		if show_tod and _time_of_day_rect.material is ShaderMaterial:
			var sm := _time_of_day_rect.material as ShaderMaterial
			var cur_min: float = _time_of_day_override_min if _time_of_day_override_min >= 0.0 else float(_world_clock.minute_of_day())
			var vp_px := get_viewport_rect().size
			if vp_px.x <= 1.0 or vp_px.y <= 1.0:
				vp_px = Vector2(960.0, 640.0)
			var z := _camera.zoom.x if (_camera != null and _camera.zoom.x > 0.0001) else 2.0
			var cam_center_t := (_camera.position / float(TILE_SIZE_PX)) if _camera != null else Vector2.ZERO
			var view_size_t := vp_px / (float(TILE_SIZE_PX) * z)
			var has_p := 1.0 if (_walk_mode_active and _player_walker != null) else 0.0
			var p_tile := (_player_walker.get_camera_target() / float(TILE_SIZE_PX)) if (_walk_mode_active and _player_walker != null) else cam_center_t
			sm.set_shader_parameter("minute_of_day", cur_min)
			sm.set_shader_parameter("cam_center_tiles", cam_center_t)
			sm.set_shader_parameter("view_size_tiles", view_size_t)
			sm.set_shader_parameter("player_world_tiles", p_tile)
			sm.set_shader_parameter("has_player", has_p)
			var near_lamps: Array[Vector2] = []
			var origin_tf := Vector2(_render_origin_tile)
			for lt in _all_lamp_world_tiles:
				var lt_render := lt - origin_tf
				if lt_render.distance_to(cam_center_t) <= 48.0 and near_lamps.size() < 16:
					near_lamps.append(lt_render)
			sm.set_shader_parameter("lamp_count", near_lamps.size())
			var padded_lamps: Array[Vector2] = []
			padded_lamps.resize(16)
			for i in range(16):
				padded_lamps[i] = near_lamps[i] if i < near_lamps.size() else Vector2(-999999.0, -999999.0)
			sm.set_shader_parameter("lamp_world_tiles", padded_lamps)

	if _walk_hud_panel != null and _walk_hud_label != null:
		_walk_hud_panel.visible = _walk_mode_active
		if _walk_mode_active:
			var disp_min: int = posmod(int(round(_time_of_day_override_min)) if _time_of_day_override_min >= 0.0 else _world_clock.minute_of_day(), WorldClock.MINUTES_PER_DAY)
			var clock_str := "%02d:%02d" % [int(disp_min / 60), disp_min % 60]
			var band_str := WorldClock.time_band_for_minute(disp_min)
			var area_title := _area_name(_current_walk_area_id)
			var hud_line := "%s · %s · %s" % [clock_str, _band_display_name(band_str), area_title]
			if _area_kind(_current_walk_area_id) != "camp" and not _current_walk_area_id.is_empty():
				var db = _get_db()
				var starter_pid := _active_place_id
				if db != null and db.is_open():
					var sp_meta: String = db.get_db_meta("starter_place", "")
					if not sp_meta.is_empty():
						starter_pid = sp_meta
				var band_vec: Vector2i = SpawnDirector.compute_area_level_band(_current_walk_area_id, starter_pid, false, band_str, 0)
				hud_line += " · Wild Lv. %d–%d" % [band_vec.x, band_vec.y]
			_walk_hud_label.text = hud_line

func show_toast(msg: String, duration: float = 4.0) -> void:
	_last_toast_text = msg
	_toast_timer = maxf(0.5, duration)
	if _toast_label != null:
		_toast_label.text = msg
	if _toast_panel != null:
		_toast_panel.visible = not msg.is_empty()

func show_banner(msg: String, duration: float = 5.0) -> void:
	_last_banner_text = msg
	_banner_timer = maxf(0.5, duration)
	if _banner_label != null:
		_banner_label.text = msg
	if _banner_panel != null:
		_banner_panel.visible = not msg.is_empty()

func _area_meta(area_id: String) -> Dictionary:
	if _walker_grid != null:
		return _walker_grid.area_meta(area_id)
	return Neighbourhoods.area(area_id)

func _area_kind(area_id: String) -> String:
	if area_id.is_empty():
		return ""
	var meta := _area_meta(area_id)
	var k := str(meta.get("kind", ""))
	if not k.is_empty():
		return k
	if area_id.begins_with("camp:"):
		return "camp"
	if area_id.begins_with("route:"):
		return "route"
	return "hood"

func _area_name(area_id: String) -> String:
	var meta := _area_meta(area_id)
	return str(meta.get("name", area_id))

func _area_route_id(area_id: String) -> String:
	var meta := _area_meta(area_id)
	var rid := str(meta.get("route_id", ""))
	if not rid.is_empty():
		return rid
	var hash_idx := area_id.find("#")
	return area_id.substr(0, hash_idx) if hash_idx > 0 else area_id

func persist_player_session() -> void:
	if not _walk_mode_active or _screenshot_mode or _player_walker == null or _current_walk_area_id.is_empty():
		return
	var db = _get_db()
	if db == null or not db.is_open() or not db.has_method("save_player_session"):
		return
	if not _caricature_compiled_by_area.has(_current_walk_area_id):
		return
	var comp: Dictionary = _caricature_compiled_by_area[_current_walk_area_id]
	var lpos := CaricatureWalkerGrid.global_to_local(comp, _player_walker.grid_pos.x, _player_walker.grid_pos.y)
	db.save_player_session({
		"place_id": _active_place_id,
		"area_id": _current_walk_area_id,
		"tile_x": lpos.x,
		"tile_y": lpos.y,
		"facing": _player_walker.facing,
		"interior_id": "",
		"interior_floor": 0,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "",
		"return_x": 0,
		"return_y": 0,
		"route_origin_area_id": _route_origin_area_id,
		"active_route_id": _active_route_id,
		"route_time_accum_milli": _route_time_accum_milli,
		"route_time_charged_min": _route_time_charged_min,
	})

func _rebuild_walker_grid() -> void:
	var collected := {}
	_collected_hidden_keys.clear()
	var db = _get_db()
	if db != null and db.is_open() and db.has_method("get_collected_items_in_area"):
		for aid_v in _caricature_compiled_by_area.keys():
			var aid := str(aid_v)
			for row_v in db.get_collected_items_in_area(aid):
				if row_v is Dictionary:
					var rk := str((row_v as Dictionary).get("kind", ""))
					var rkey := str((row_v as Dictionary).get("item_key", ""))
					if rk == "ball":
						collected[rkey] = true
					elif rk == "hidden":
						_collected_hidden_keys[rkey] = true
	_walker_grid = CaricatureWalkerGrid.new()
	_walker_grid.setup(
		_caricature_compiled_by_area,
		_caricature_cells,
		Callable(self, "_caricature_reveal_state"),
		collected,
		_active_place_id
	)

func enable_walk_mode(area_id: String = "", local_tile: Vector2i = Vector2i(-1, -1), facing_str: String = "S") -> bool:
	if not _is_caricature_place:
		return false
	if _walker_grid == null:
		_rebuild_walker_grid()
	var target_aid := area_id if not area_id.is_empty() else _caricature_camp_id
	if target_aid.is_empty() or not _caricature_compiled_by_area.has(target_aid):
		return false

	if _player_walker == null:
		_player_walker = PlayerWalker.new()
		_player_walker.name = "PlayerWalker"
		_player_walker.set_render_origin_tile(_render_origin_tile)
		_player_walker.set_force_no_rom(_force_no_rom)
		_player_walker.set_step_evaluator(Callable(self, "_evaluate_walker_step"))
		_player_walker.step_completed.connect(_on_walker_step_completed)
		_player_walker.step_blocked.connect(_on_walker_step_blocked)
		_player_walker.door_stepped.connect(_on_walker_door_stepped)
		_player_walker.interact_pressed.connect(_on_walker_interact_pressed)
		_player_walker.visual_position_updated.connect(_sync_camera_to_player)
		if _stamp_base_layer != null:
			_stamp_base_layer.add_child(_player_walker)
		else:
			add_child(_player_walker)
	else:
		_player_walker.set_render_origin_tile(_render_origin_tile)
		if not _player_walker.step_blocked.is_connected(_on_walker_step_blocked):
			_player_walker.step_blocked.connect(_on_walker_step_blocked)
		if not _player_walker.door_stepped.is_connected(_on_walker_door_stepped):
			_player_walker.door_stepped.connect(_on_walker_door_stepped)
		if not _player_walker.interact_pressed.is_connected(_on_walker_interact_pressed):
			_player_walker.interact_pressed.connect(_on_walker_interact_pressed)
		if not _player_walker.visual_position_updated.is_connected(_sync_camera_to_player):
			_player_walker.visual_position_updated.connect(_sync_camera_to_player)

	var db = _get_db()
	var sidx := 0
	if db != null and db.is_open() and db.has_method("get_player_sprite_index"):
		sidx = int(db.get_player_sprite_index())
	_player_walker.set_sprite_index(sidx)
	_player_walker.set_force_no_rom(_force_no_rom)
	_player_walker.visible = true
	_player_walker.input_enabled = true

	_world_clock.load_from_db(db)
	_world_clock.set_running(not _screenshot_mode)

	_walk_mode_active = true
	_camera_follows_player = true
	invalidate_neighbourhood_state_cache()
	# Pre-warm static indoor atlas & TileSet once at walk start so first door entry (incl. --no-rom) stays <= 16.7 ms
	var ibundle: Dictionary = InteriorTiles.resolve_atlas_bundle(AssetDB.DEFAULT_CACHE_DIR, _force_no_rom)
	InteriorTiles.resolve_tileset(ibundle.get("texture", null) as Texture2D, int(ibundle.get("cols", InteriorTiles.CLASS_COUNT)), int(ibundle.get("rows", 1)))
	_set_zoom_step(2.0) # Emerald 15x10 screen at 960x640 (Decision 79 / F81)
	var placed := place_player_in_area(target_aid, local_tile, facing_str)
	refresh_time_of_day_and_hud()
	return placed

func disable_walk_mode() -> void:
	_walk_mode_active = false
	_camera_follows_player = false
	_world_clock.set_running(false)
	if _player_walker != null:
		_player_walker.visible = false
		_player_walker.input_enabled = false
	refresh_time_of_day_and_hud()

func set_walk_zoom(zoom_val: float) -> void:
	_set_zoom_step(zoom_val)
	refresh_time_of_day_and_hud()

func find_walk_bench_plan(hood_area_id: String = "hood:washington-dc:dupont-circle", route_leg_id: String = "route:washington-dc:q-street#1", hood_steps: int = 40, route_steps: int = 40) -> Dictionary:
	if _walker_grid == null or not _caricature_compiled_by_area.has(hood_area_id) or not _caricature_compiled_by_area.has(route_leg_id):
		return {"ok": false, "error": "missing areas"}
	var hood_comp: Dictionary = _caricature_compiled_by_area[hood_area_id]
	var seam_from_g := Vector2i.ZERO
	var found_seam := false
	var seam_dir := Vector2i(-1, 0)
	for op_v in hood_comp.get("openings", []):
		if op_v is Dictionary and str((op_v as Dictionary).get("side", "")) == "W":
			var ot: Array = (op_v as Dictionary).get("outer_tiles", [])
			if not ot.is_empty():
				seam_from_g = ot[int(ot.size() / 2)] as Vector2i
				found_seam = true
				break
	if not found_seam:
		return {"ok": false, "error": "no W opening in hood"}
	var seam_eval: Dictionary = _walker_grid.evaluate_step(seam_from_g.x, seam_from_g.y, seam_dir)
	if str(seam_eval.get("action", "")) != "step" or str(seam_eval.get("to_area", "")) != route_leg_id:
		return {"ok": false, "error": "W opening does not cross to route leg: %s" % str(seam_eval)}
	var seam_to_g: Vector2i = seam_eval.get("to", seam_from_g + seam_dir)

	var dirs_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# BFS inside hood_area_id backward from seam_from_g so every forward step is a clean 1-tile step
	var h_parent: Dictionary = {seam_from_g: Vector2i(0, 0)}
	var h_dist: Dictionary = {seam_from_g: 0}
	var h_queue: Array[Vector2i] = [seam_from_g]
	var h_head := 0
	var start_g := seam_from_g
	var best_h_dist := 0
	while h_head < h_queue.size():
		var cur: Vector2i = h_queue[h_head]
		h_head += 1
		var cd := int(h_dist[cur])
		if cd >= hood_steps:
			start_g = cur
			best_h_dist = cd
			break
		if cd > best_h_dist:
			best_h_dist = cd
			start_g = cur
		for d in dirs_4:
			var prev_cand := cur - d
			if h_dist.has(prev_cand):
				continue
			if _walker_grid.area_at_global(prev_cand.x, prev_cand.y) != hood_area_id:
				continue
			var ev: Dictionary = _walker_grid.evaluate_step(prev_cand.x, prev_cand.y, d)
			if str(ev.get("action", "")) == "step" and (ev.get("to", Vector2i.ZERO) as Vector2i) == cur and str(ev.get("to_area", "")) == hood_area_id:
				h_dist[prev_cand] = cd + 1
				h_parent[prev_cand] = d
				h_queue.append(prev_cand)

	var step_dirs: Array[Vector2i] = []
	var walk_cur := start_g
	while walk_cur != seam_from_g:
		var sd: Vector2i = h_parent[walk_cur]
		step_dirs.append(sd)
		walk_cur += sd
	var seam_step_idx := step_dirs.size()
	step_dirs.append(seam_dir)

	# BFS inside route_leg_id forward from seam_to_g for route_steps tiles
	var r_prev: Dictionary = {seam_to_g: seam_to_g}
	var r_pdir: Dictionary = {}
	var r_dist: Dictionary = {seam_to_g: 0}
	var r_queue: Array[Vector2i] = [seam_to_g]
	var r_head := 0
	var end_g := seam_to_g
	var best_r_dist := 0
	while r_head < r_queue.size():
		var cur_r: Vector2i = r_queue[r_head]
		r_head += 1
		var cdr := int(r_dist[cur_r])
		if cdr >= route_steps:
			end_g = cur_r
			best_r_dist = cdr
			break
		if cdr > best_r_dist:
			best_r_dist = cdr
			end_g = cur_r
		for d in dirs_4:
			var ev_r: Dictionary = _walker_grid.evaluate_step(cur_r.x, cur_r.y, d)
			if str(ev_r.get("action", "")) != "step" or str(ev_r.get("to_area", "")) != route_leg_id:
				continue
			var nxt: Vector2i = ev_r.get("to", cur_r + d)
			if r_dist.has(nxt):
				continue
			r_dist[nxt] = cdr + 1
			r_prev[nxt] = cur_r
			r_pdir[nxt] = d
			r_queue.append(nxt)

	var route_dirs_rev: Array[Vector2i] = []
	var trace_r := end_g
	while trace_r != seam_to_g:
		route_dirs_rev.append(r_pdir[trace_r] as Vector2i)
		trace_r = r_prev[trace_r] as Vector2i
	route_dirs_rev.reverse()
	for rd in route_dirs_rev:
		step_dirs.append(rd)

	# Find an enterable door in hood_area_id
	var door_step_local := Vector2i(-1, -1)
	var door_iid := ""
	for d_v in hood_comp.get("doors", []):
		if d_v is Dictionary:
			var dd: Dictionary = d_v
			var iid := str(dd.get("interior", ""))
			if iid.is_empty():
				continue
			var dl := Vector2i(int(dd.get("x", -1)), int(dd.get("y", -1)) + 1)
			var dg := CaricatureWalkerGrid.local_to_global(hood_comp, dl.x, dl.y)
			var dev: Dictionary = _walker_grid.evaluate_step(dg.x, dg.y, Vector2i(0, -1))
			if str(dev.get("action", "")) == "door":
				door_step_local = dl
				door_iid = iid
				break

	var start_local := CaricatureWalkerGrid.global_to_local(hood_comp, start_g.x, start_g.y)
	return {
		"ok": best_h_dist >= hood_steps and best_r_dist >= route_steps and not door_iid.is_empty(),
		"start_area": hood_area_id,
		"start_local": start_local,
		"step_dirs": step_dirs,
		"seam_step_index": seam_step_idx,
		"hood_steps": best_h_dist,
		"route_steps": best_r_dist,
		"door_area": hood_area_id,
		"door_step_local": door_step_local,
		"door_interior_id": door_iid,
	}

func place_player_in_area(area_id: String, local_tile: Vector2i = Vector2i(-1, -1), facing_str: String = "S", preserve_route_state: bool = false) -> bool:
	if _player_walker == null or not _caricature_compiled_by_area.has(area_id):
		return false
	var comp: Dictionary = _caricature_compiled_by_area[area_id]
	var lpos := local_tile
	if lpos.x < 0 or lpos.y < 0:
		lpos = comp.get("arrival", Vector2i(16, 16))
	var gpos := CaricatureWalkerGrid.local_to_global(comp, lpos.x, lpos.y)
	_current_walk_area_id = area_id
	_focused_area_id = area_id
	if not preserve_route_state:
		_route_origin_area_id = ""
		_active_route_id = ""
		_route_time_accum_milli = 0
		_route_time_charged_min = 0
		_route_idle_seconds = 0.0
	_camera_follows_player = true
	_player_walker.place_at(gpos, facing_str)
	if _camera != null:
		_camera.position = _player_walker.get_camera_target()
	_update_return_home_visibility()
	refresh_time_of_day_and_hud()
	persist_player_session()
	return true

func _evaluate_walker_step(from_tile: Vector2i, dir: Vector2i) -> Dictionary:
	if _walker_grid == null:
		return {"action": "blocked", "reason": "none", "tile": from_tile + dir, "area_id": _current_walk_area_id}
	return _walker_grid.evaluate_step(from_tile.x, from_tile.y, dir)

func _on_walker_step_blocked(_tile: Vector2i, info: Dictionary) -> void:
	if str(info.get("reason", "")) == "fog":
		show_toast("Thick fog blocks the way — open the next neighbourhood at the Waypost board first.")

func _on_walker_door_stepped(door_info: Dictionary) -> void:
	if not _walk_mode_active or _screenshot_mode:
		return
	var d_entry: Dictionary = door_info.get("door", {}) if door_info.get("door") is Dictionary else {}
	var iid := str(d_entry.get("interior", ""))
	if iid.is_empty():
		return
	var aid := str(door_info.get("area_id", _current_walk_area_id))
	var d_local: Vector2i = door_info.get("door_local", Vector2i.ZERO)
	var return_info := {
		"place_id": _active_place_id,
		"return_area_id": aid,
		"return_x": d_local.x,
		"return_y": d_local.y + 1,
		"door_name": str(d_entry.get("name", "")),
	}
	door_entered.emit(iid, return_info)
	var main_node = get_parent()
	if main_node != null and main_node.has_method("enter_interior_from_map"):
		main_node.enter_interior_from_map(self, iid, return_info)

func set_overlays_visible(show: bool) -> void:
	if _time_of_day_layer != null:
		_time_of_day_layer.visible = show
	var attr_ui := get_node_or_null("AttributionUI") as CanvasLayer
	if attr_ui != null:
		attr_ui.visible = show

func resume_from_interior(return_info: Dictionary) -> void:
	visible = true
	set_overlays_visible(true)
	process_mode = Node.PROCESS_MODE_INHERIT
	invalidate_neighbourhood_state_cache()
	var db = _get_db()
	_world_clock.load_from_db(db)
	_world_clock.set_running(not _screenshot_mode)
	var ret_aid := str(return_info.get("return_area_id", _current_walk_area_id))
	var ret_pos := Vector2i(int(return_info.get("return_x", -1)), int(return_info.get("return_y", -1)))
	place_player_in_area(ret_aid, ret_pos, "S", false)
	if _camera != null:
		_camera.make_current()
		_camera.call_deferred("make_current")
		if _player_walker != null:
			_camera.position = _player_walker.get_camera_target()
	_sync_modal_input_lock()

func _accrue_route_step_time(route_id: String, tiles_moved: int) -> void:
	if route_id.is_empty() or _walker_grid == null:
		return
	var route_min := NeighbourhoodProgress.route_walk_minutes(route_id, false)
	var ends_steps := _walker_grid.get_route_total_ends_steps(route_id)
	var per_tile_milli := maxi(1, int(round(float(route_min * 1000) / float(maxi(1, ends_steps)))))
	_route_time_accum_milli += per_tile_milli * maxi(1, tiles_moved)
	while _route_time_accum_milli >= 1000:
		_route_time_accum_milli -= 1000
		_world_clock.advance_minutes(1)
		_route_time_charged_min += 1

func _on_walker_step_completed(tile: Vector2i, info: Dictionary) -> void:
	var from_aid := str(info.get("from_area", _current_walk_area_id))
	var to_aid := str(info.get("to_area", ""))
	if to_aid.is_empty() and _walker_grid != null:
		to_aid = _walker_grid.area_at_global(tile.x, tile.y)
	if to_aid.is_empty():
		to_aid = _current_walk_area_id

	var from_kind := _area_kind(from_aid)
	var to_kind := _area_kind(to_aid)
	var step_tiles := int(info.get("step_tiles", 1))

	if from_kind == "hood" and to_kind == "route":
		# Entered a route from a neighbourhood: start tracking origin & fractional route travel clock
		_route_origin_area_id = from_aid
		_active_route_id = _area_route_id(to_aid)
		_route_time_accum_milli = 0
		_route_time_charged_min = 0
		_route_idle_seconds = 0.0
		_accrue_route_step_time(_active_route_id, step_tiles)
	elif to_kind == "route":
		# Stepping along a route (or seamlessly across leg #1 <-> leg #2): keep origin, accrue fractional travel time
		if _active_route_id.is_empty():
			_active_route_id = _area_route_id(to_aid)
		_route_idle_seconds = 0.0
		_accrue_route_step_time(_active_route_id, step_tiles)
	elif from_kind == "route" and to_kind == "hood":
		var db = _get_db()
		var route_id := _active_route_id if not _active_route_id.is_empty() else _area_route_id(from_aid)
		if not route_id.is_empty() and not _route_origin_area_id.is_empty():
			if to_aid != _route_origin_area_id:
				# Crossed to the far end of the route: flush remaining route travel time & call walk_route
				var req_min := NeighbourhoodProgress.route_walk_minutes(route_id, false)
				if _route_time_charged_min < req_min:
					_world_clock.advance_minutes(req_min - _route_time_charged_min)
				var prev_state := 0
				if db != null and db.is_open():
					var prev_row: Dictionary = db.get_neighbourhood_state(to_aid)
					prev_state = int(prev_row.get("state", 0))
				var wr := NeighbourhoodProgress.walk_route(db, route_id, _route_origin_area_id)
				if bool(wr.get("ok", false)):
					invalidate_neighbourhood_state_cache()
					_fog_dirty = true
					_sync_fog_field()
					_update_frustum_culling()
					var hood_name := _area_name(to_aid)
					if prev_state < 2:
						show_banner("Arrived in %s — lamp lit for fast travel." % hood_name)
					else:
						show_banner(hood_name)
			# Else: player turned back into origin neighbourhood — do NOT call walk_route
		_route_origin_area_id = ""
		_active_route_id = ""
		_route_time_accum_milli = 0
		_route_time_charged_min = 0
		_route_idle_seconds = 0.0

	_current_walk_area_id = to_aid
	_focused_area_id = to_aid
	if _camera_follows_player and _camera != null and _player_walker != null:
		_camera.position = _player_walker.get_camera_target()
	_update_return_home_visibility()
	persist_player_session()

func force_caricature_area(area_id: String) -> void:
	_forced_caricature_area_id = area_id
	_screenshot_area_id = area_id
	var a_dict: Dictionary = Neighbourhoods.area(area_id)
	_forced_caricature_place_id = str(a_dict.get("place_id", ""))

func set_screenshot_options(no_rom: bool, has_tile: bool = false, tile_pos: Vector2i = Vector2i(-1, -1)) -> void:
	var changed_no_rom := (_force_no_rom != no_rom)
	_force_no_rom = no_rom
	_has_screenshot_tile = has_tile
	_screenshot_tile = tile_pos
	if changed_no_rom and is_inside_tree():
		_init_tile_sets()

func focus_on_area(area_id: String, whole: bool = false) -> void:
	var a_dict: Dictionary = Neighbourhoods.area(area_id)
	if a_dict.is_empty():
		return
	var origin: Vector2i = Neighbourhoods.block_origin(a_dict)
	var cells_arr: Array = a_dict.get("cells", [1, 1])
	var cols: int = int(cells_arr[0]) if cells_arr.size() >= 1 else 1
	var rows: int = int(cells_arr[1]) if cells_arr.size() >= 2 else 1
	_focused_area_id = area_id
	_focused_area_tiles = Vector2i(cols * 32, rows * 32)
	_focused_city_cells = Vector2i.ZERO
	if whole or _screenshot_mode:
		_camera_follows_player = false
	if _camera != null:
		if _has_screenshot_tile:
			var tgx: int = origin.x * 32 + _screenshot_tile.x - _render_origin_tile.x
			var tgy: int = (-(origin.y + rows - 1) - 1) * 32 + _screenshot_tile.y - _render_origin_tile.y
			_camera.position = Vector2((float(tgx) + 0.5) * float(TILE_SIZE_PX), (float(tgy) + 0.5) * float(TILE_SIZE_PX))
		elif whole:
			_camera.position = Vector2(
				(float(origin.x - _render_origin_sc.x) + float(cols) * 0.5) * CELL_SIZE_PX,
				(float(-(origin.y + rows) - _render_origin_sc.y) + float(rows) * 0.5) * CELL_SIZE_PX
			)
		elif _caricature_compiled_by_area.has(area_id):
			var comp: Dictionary = _caricature_compiled_by_area[area_id]
			var arr: Vector2i = comp.get("arrival", Vector2i(16, 16))
			var gx: int = origin.x * 32 + arr.x - _render_origin_tile.x
			var gy: int = (-(origin.y + rows - 1) - 1) * 32 + arr.y - _render_origin_tile.y
			_camera.position = Vector2((float(gx) + 0.5) * float(TILE_SIZE_PX), (float(gy) + 0.5) * float(TILE_SIZE_PX))
		else:
			_camera.position = Vector2(
				(float(origin.x - _render_origin_sc.x) + float(cols) * 0.5) * CELL_SIZE_PX,
				(float(-(origin.y + rows) - _render_origin_sc.y) + float(rows) * 0.5) * CELL_SIZE_PX
			)
	_update_return_home_visibility()

func focus_on_city(place_id: String) -> float:
	var bounds: Rect2i = Neighbourhoods.city_bounds(place_id)
	_focused_area_id = ""
	_focused_area_tiles = Vector2i.ZERO
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_focused_city_cells = Vector2i.ZERO
		return _current_zoom_step
	_focused_city_cells = bounds.size
	var vp_px := get_viewport_rect().size
	var fit_zoom := _current_zoom_step
	if vp_px.x > 0.0 and vp_px.y > 0.0:
		fit_zoom = minf(
			vp_px.x / (float(bounds.size.x) * CELL_SIZE_PX),
			vp_px.y / (float(bounds.size.y) * CELL_SIZE_PX)
		)
	_set_zoom_step(fit_zoom)
	if _camera != null:
		_camera.position = Vector2(
			(float(bounds.position.x - _render_origin_sc.x) + float(bounds.size.x) * 0.5) * CELL_SIZE_PX,
			(float(-(bounds.position.y + bounds.size.y) - _render_origin_sc.y) + float(bounds.size.y) * 0.5) * CELL_SIZE_PX
		)
	_update_return_home_visibility()
	return fit_zoom

func _caricature_reveal_state(cell: Vector2i, states_by_area: Dictionary = {}) -> int:
	if not _caricature_cells.has(cell):
		return 0
	var entry: Dictionary = _caricature_cells[cell]
	var area_dict: Dictionary = entry.get("area", {}) if entry.get("area") is Dictionary else {}
	var aid := str(area_dict.get("id", ""))
	var kind := str(area_dict.get("kind", ""))
	if kind == "camp" or aid.begins_with("camp:"):
		return 2
	var lookup_id := str(area_dict.get("route_id", aid)) if kind == "route" else aid
	if not states_by_area.is_empty():
		if not states_by_area.has(lookup_id):
			return 0
		var st_val := int(states_by_area[lookup_id])
		return 2 if st_val >= 2 else (1 if st_val == 1 else 0)
	var db = _get_db()
	if db != null and db.is_open():
		var ns_row: Dictionary = db.get_neighbourhood_state(lookup_id)
		if not ns_row.is_empty():
			var st_val := int(ns_row.get("state", 0))
			return 2 if st_val >= 2 else (1 if st_val == 1 else 0)
	return 0

func load_place(place_id: String, center_waypost: bool = true) -> bool:
	var use_caricature: bool = Neighbourhoods.is_ready(place_id) or (
		_forced_caricature_place_id == place_id and Neighbourhoods.has_city(place_id)
	)
	if use_caricature:
		_active_place_id = place_id
		var db = _get_db()
		if db != null and db.is_open():
			db.set_db_meta("last_place", place_id)

		var require_all := Neighbourhoods.is_ready(place_id)
		var new_cells: Dictionary = {}
		var new_compiled: Dictionary = {}
		var new_lms_by_cell: Dictionary = {}
		var new_lm_names: Dictionary = {}
		var camp_id := ""
		var camp_origin := Vector2i.ZERO
		var camp_wm := Vector2.ZERO

		for a_var in Neighbourhoods.areas_of(place_id):
			var a: Dictionary = a_var
			var aid := str(a.get("id", ""))
			if str(a.get("kind", "")) == "camp" or aid.begins_with("camp:"):
				camp_id = aid
				camp_origin = Neighbourhoods.block_origin(a)
				var c_anch: Dictionary = a.get("anchor", {})
				camp_wm = Grid.latlon_to_wm(float(c_anch.get("lat", 0.0)), float(c_anch.get("lon", 0.0)))
			var map_path := CaricatureMap.resolve_map_path(str(a.get("map", "")))
			var must_exist := require_all or (aid == _forced_caricature_area_id)
			if not FileAccess.file_exists(map_path):
				if must_exist:
					printerr("[FAIL] caricature %s: missing map" % aid)
					if _screenshot_mode:
						get_tree().quit(1)
					return false
				continue
			var raw_map := CaricatureMap.load_map(map_path)
			if raw_map.is_empty():
				printerr("[FAIL] caricature %s: invalid map json" % aid)
				if _screenshot_mode:
					get_tree().quit(1)
				return false
			var compiled := CaricatureMap.compile(a, raw_map)
			if not bool(compiled.get("ok", false)):
				var errs: Array = compiled.get("errors", [])
				var err_msg := ", ".join(PackedStringArray(errs)) if not errs.is_empty() else "compile error"
				printerr("[FAIL] caricature %s: %s" % [aid, err_msg])
				if _screenshot_mode:
					get_tree().quit(1)
				return false
			new_compiled[aid] = compiled
			var b_orig: Vector2i = compiled["origin"]
			var b_cols: int = int(compiled["cols"])
			var b_rows: int = int(compiled["rows"])
			for dy in range(b_rows):
				for dx in range(b_cols):
					new_cells[Vector2i(b_orig.x + dx, b_orig.y + dy)] = {
						"compiled": compiled,
						"area": a
					}
			var doors_arr: Array = compiled.get("doors", [])
			for d_var in doors_arr:
				var d: Dictionary = d_var
				var iid := str(d.get("interior", ""))
				if iid.is_empty():
					continue
				var d_name := str(d.get("name", ""))
				var dx_t: int = int(d["x"])
				var dy_t: int = int(d["y"])
				var d_cell := Vector2i(b_orig.x + int(dx_t / 32), b_orig.y + b_rows - 1 - int(dy_t / 32))
				var d_st := Vector2i(b_orig.x * 32 + dx_t, (-(b_orig.y + b_rows - 1) - 1) * 32 + dy_t)
				if not new_lms_by_cell.has(d_cell):
					new_lms_by_cell[d_cell] = []
				new_lms_by_cell[d_cell].append({
					"id": iid,
					"name": d_name,
					"door_st": d_st
				})
				if not d_name.is_empty():
					new_lm_names[d_name] = true

		_is_caricature_place = true
		_caricature_cells = new_cells
		_caricature_compiled_by_area = new_compiled
		_caricature_camp_id = camp_id
		# Item 75 (F88, F89): Local render origin at top-left screen-cell of this place so all drawn
		# coordinates stay small (~0..40,000 px), preventing 32-bit float shake and y-sort is_equal_approx ties.
		var has_origin_sc := false
		var min_scx := 0
		var min_scy := 0
		for c_v in new_cells.keys():
			var cc: Vector2i = c_v
			var scx_c := cc.x
			var scy_c := -cc.y - 1
			if not has_origin_sc:
				min_scx = scx_c
				min_scy = scy_c
				has_origin_sc = true
			else:
				min_scx = mini(min_scx, scx_c)
				min_scy = mini(min_scy, scy_c)
		if has_origin_sc:
			_set_render_origin_from_screen_cell(Vector2i(min_scx, min_scy))
		else:
			_set_render_origin_from_screen_cell(Vector2i(camp_origin.x, -camp_origin.y - 1))
		_all_lamp_world_tiles.clear()
		for l_aid in new_compiled.keys():
			var l_comp: Dictionary = new_compiled[l_aid]
			var l_pos: Vector2i = l_comp.get("lamp", Vector2i(-1, -1))
			if l_pos.x >= 0 and l_pos.y >= 0:
				var l_g := CaricatureWalkerGrid.local_to_global(l_comp, l_pos.x, l_pos.y)
				_all_lamp_world_tiles.append(Vector2(float(l_g.x) + 0.5, float(l_g.y) - 0.25))
		invalidate_neighbourhood_state_cache()
		_landmarks_by_cell = new_lms_by_cell
		_landmark_names = new_lm_names
		_active_waypost_cell = camp_origin
		_active_waypost_wm = camp_wm
		_has_active_waypost = true
		if _excluded_store_place_id != place_id:
			_excluded_store_place_id = place_id
			_load_map_stores()
		elif _synth_worker != null:
			_synth_worker.set_landmarks(_landmarks_by_cell)
			_synth_worker.set_caricature(_caricature_cells)
			_synth_worker.set_waypost_wm(_active_waypost_wm)
		# Re-ensure camp waypost cell after _load_map_stores (whose _resolve_active_waypost checks famous_places)
		_active_waypost_cell = camp_origin
		_active_waypost_wm = camp_wm
		_has_active_waypost = true
		_synth_cache.clear()
		_clear_rendered_layers()
		_rebuild_walker_grid()
		if not _screenshot_mode and center_waypost and not camp_id.is_empty():
			enable_walk_mode(camp_id)
		else:
			_set_zoom_step(_current_zoom_step)
			if center_waypost and not camp_id.is_empty():
				focus_on_area(camp_id, false)
		_update_return_home_visibility()
		return true

	if _is_caricature_place:
		disable_walk_mode()
		_is_caricature_place = false
		_excluded_store_place_id = ""
		_caricature_cells.clear()
		_caricature_compiled_by_area.clear()
		_caricature_camp_id = ""
		_load_landmarks()
		_load_map_stores()
		_synth_cache.clear()
		_clear_rendered_layers()
		_set_zoom_step(_current_zoom_step)

	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == place_id:
			_active_place_id = place_id
			var db = _get_db()
			if db != null and db.is_open():
				db.set_db_meta("last_place", place_id)
			var wp: Dictionary = p.get("waypost", {})
			var w_lat := float(wp.get("lat", 0.0))
			var w_lon := float(wp.get("lon", 0.0))
			_active_waypost_cell = Grid.latlon_to_cell(w_lat, w_lon)
			_active_waypost_wm = Grid.latlon_to_wm(w_lat, w_lon)
			_has_active_waypost = true
			_set_render_origin_from_screen_cell(Vector2i(_active_waypost_cell.x, -_active_waypost_cell.y - 1))
			_clear_rendered_layers()
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
	var scx := int(floor(_camera.position.x / CELL_SIZE_PX)) + _render_origin_sc.x
	var scy := int(floor(_camera.position.y / CELL_SIZE_PX)) + _render_origin_sc.y
	return Vector2i(scx, -scy - 1)

func _update_return_home_visibility() -> void:
	if _is_caricature_place:
		var in_camp := false
		if _walk_mode_active:
			in_camp = (_area_kind(_current_walk_area_id) == "camp")
		else:
			var cam_cell := get_camera_cell()
			var cell_entry: Dictionary = _caricature_cells.get(cam_cell, {}) if _caricature_cells.has(cam_cell) else {}
			var cell_area: Dictionary = cell_entry.get("area", {}) if cell_entry.get("area") is Dictionary else {}
			in_camp = (
				str(cell_area.get("kind", "")) == "camp"
				or (_has_active_waypost and (cam_cell == _active_waypost_cell))
			)
		if _return_home_button != null:
			_return_home_button.visible = in_camp and (not _walk_mode_active)
		if _board_button != null:
			_board_button.visible = in_camp and (not _walk_mode_active)
		if _back_to_camp_button != null:
			# Decision 79 fix (c): lamps-only fast travel — hide global Back to camp button while walking
			_back_to_camp_button.visible = (not in_camp) and (not _walk_mode_active)
		return

	if _board_button != null:
		_board_button.visible = false
	if _waypost_board != null:
		_waypost_board.visible = false
	if _lamp_menu != null:
		_lamp_menu.visible = false
	if _back_to_camp_button != null:
		_back_to_camp_button.visible = false
	if _return_home_button == null:
		return
	if not _has_active_waypost:
		_return_home_button.visible = false
		return
	var cam_cell := get_camera_cell()
	var dist_x: int = abs(cam_cell.x - _active_waypost_cell.x)
	var dist_y: int = abs(cam_cell.y - _active_waypost_cell.y)
	_return_home_button.visible = (dist_x <= 1 and dist_y <= 1)

func _sync_modal_input_lock() -> void:
	if _player_walker == null:
		return
	var modal_open := false
	if _waypost_board != null and is_instance_valid(_waypost_board) and _waypost_board.visible:
		modal_open = true
	if _lamp_menu != null and is_instance_valid(_lamp_menu) and _lamp_menu.visible:
		modal_open = true
	if _dialogue_box != null and is_instance_valid(_dialogue_box) and _dialogue_box.visible:
		modal_open = true
	_player_walker.input_enabled = _walk_mode_active and not modal_open

func get_dialogue_box() -> Control:
	if _dialogue_box == null or not is_instance_valid(_dialogue_box):
		var dlg_scene := load("res://scenes/dialogue_box.tscn") as PackedScene
		if dlg_scene == null:
			return null
		_dialogue_box = dlg_scene.instantiate() as Control
		_dialogue_box.name = "DialogueBox"
		var attr_ui := get_node_or_null("AttributionUI")
		if attr_ui != null:
			attr_ui.add_child(_dialogue_box)
		else:
			add_child(_dialogue_box)
		if _dialogue_box.has_signal("closed"):
			_dialogue_box.connect("closed", Callable(self, "_on_modal_overlay_closed"))
	return _dialogue_box

func open_dialogue(lines: Array, speaker: String = "", extra_line: String = "", extra_color: Color = Color.WHITE) -> Control:
	var dlg := get_dialogue_box()
	if dlg == null:
		return null
	if dlg.has_method("open_lines"):
		dlg.open_lines(lines, speaker, extra_line, extra_color)
	_sync_modal_input_lock()
	return dlg

static func opposite_facing(dir_str: String) -> String:
	match dir_str.strip_edges().to_upper():
		"N":
			return "S"
		"S":
			return "N"
		"E":
			return "W"
		"W":
			return "E"
		_:
			return "S"

static func hidden_item_key(area_id: String, lx: int, ly: int) -> String:
	return "hidden:%s:%d:%d" % [area_id, lx, ly]

static func resolve_outdoor_ball_item_name(area_id: String, lx: int, ly: int) -> String:
	var raw := "%s|%d|%d|%d" % [area_id, lx, ly, MapConstants.MAP_SEED]
	var h: int = abs(raw.hash())
	return OUTDOOR_BALL_ITEM_POOL[h % OUTDOOR_BALL_ITEM_POOL.size()]

func trigger_interact_for_walker() -> bool:
	if _player_walker == null or not _walk_mode_active:
		return false
	return _dispatch_walker_interact(_player_walker.facing_tile(), _player_walker.grid_pos, _player_walker.facing)

func open_board() -> Control:
	if not _is_caricature_place or _active_place_id.is_empty():
		return null
	if _lamp_menu != null and is_instance_valid(_lamp_menu):
		_lamp_menu.visible = false
	if _waypost_board == null or not is_instance_valid(_waypost_board):
		var board_scene := load("res://scenes/waypost_board.tscn") as PackedScene
		if board_scene == null:
			return null
		_waypost_board = board_scene.instantiate() as Control
		_waypost_board.name = "WaypostBoard"
		var attr_ui := get_node_or_null("AttributionUI")
		if attr_ui != null:
			attr_ui.add_child(_waypost_board)
		else:
			add_child(_waypost_board)
		if _waypost_board.has_signal("go_requested"):
			_waypost_board.connect("go_requested", Callable(self, "_on_board_go_requested"))
		if _waypost_board.has_signal("state_changed"):
			_waypost_board.connect("state_changed", Callable(self, "_on_board_state_changed"))
		if _waypost_board.has_signal("closed"):
			_waypost_board.connect("closed", Callable(self, "_on_modal_overlay_closed"))
	if _waypost_board.has_method("open_for_place"):
		_waypost_board.open_for_place(_active_place_id, _get_db(), _world_clock)
	_sync_modal_input_lock()
	return _waypost_board

func open_lamp_menu() -> Control:
	if not _is_caricature_place or _active_place_id.is_empty():
		return null
	var cur_aid := _current_walk_area_id if not _current_walk_area_id.is_empty() else _focused_area_id
	if cur_aid.is_empty() or _area_kind(cur_aid) == "route":
		return null
	if _waypost_board != null and is_instance_valid(_waypost_board):
		_waypost_board.visible = false
	if _lamp_menu == null or not is_instance_valid(_lamp_menu):
		var lamp_scene := load("res://scenes/lamp_menu.tscn") as PackedScene
		if lamp_scene == null:
			return null
		_lamp_menu = lamp_scene.instantiate() as Control
		_lamp_menu.name = "LampMenu"
		var attr_ui := get_node_or_null("AttributionUI")
		if attr_ui != null:
			attr_ui.add_child(_lamp_menu)
		else:
			add_child(_lamp_menu)
		if _lamp_menu.has_signal("travel_requested"):
			_lamp_menu.connect("travel_requested", Callable(self, "_on_lamp_travel_requested"))
		if _lamp_menu.has_signal("board_requested"):
			_lamp_menu.connect("board_requested", Callable(self, "_on_lamp_board_requested"))
		if _lamp_menu.has_signal("distort_home_requested"):
			_lamp_menu.connect("distort_home_requested", Callable(self, "_on_lamp_distort_home_requested"))
		if _lamp_menu.has_signal("closed"):
			_lamp_menu.connect("closed", Callable(self, "_on_modal_overlay_closed"))
	if _lamp_menu.has_method("open_for_area"):
		_lamp_menu.open_for_area(_active_place_id, cur_aid, _get_db(), _world_clock)
	_sync_modal_input_lock()
	return _lamp_menu

func _on_modal_overlay_closed() -> void:
	_sync_modal_input_lock()

func travel_to_area_via_waypost(area_id: String, from_board: bool = false) -> bool:
	if not _caricature_compiled_by_area.has(area_id):
		return false
	var db = _get_db()
	var origin_aid := _current_walk_area_id if not _current_walk_area_id.is_empty() else _caricature_camp_id
	if from_board:
		if not NeighbourhoodProgress.can_go(db, area_id):
			return false
		if _area_kind(area_id) == "hood":
			NeighbourhoodProgress.enter(db, area_id)
	else:
		if area_id != _caricature_camp_id:
			if db == null or not db.is_open():
				return false
			var dest_row: Dictionary = db.get_neighbourhood_state(area_id)
			if dest_row.is_empty() or int(dest_row.get("state", 0)) < 2:
				return false
	var cost := 0
	if origin_aid != area_id and not origin_aid.is_empty():
		cost = NeighbourhoodProgress.trip_minutes(_active_place_id, origin_aid, area_id, false)
		_world_clock.advance_minutes(cost)
	if not place_player_in_area(area_id, Vector2i(-1, -1), "S", false):
		return false
	invalidate_neighbourhood_state_cache()
	_fog_dirty = true
	_sync_fog_field()
	_update_frustum_culling()
	_sync_modal_input_lock()
	if cost > 0:
		show_toast("%s (took %d min)" % [_area_name(area_id), cost])
	return true

func _on_board_go_requested(area_id: String) -> void:
	if _walk_mode_active:
		travel_to_area_via_waypost(area_id, true)
	else:
		focus_on_area(area_id, false)
		_update_frustum_culling()

func _on_lamp_travel_requested(dest_area_id: String, _cost_min: int) -> void:
	if _walk_mode_active:
		travel_to_area_via_waypost(dest_area_id, false)
	else:
		focus_on_area(dest_area_id, false)
		_update_frustum_culling()

func _on_lamp_board_requested() -> void:
	open_board()

func _on_lamp_distort_home_requested() -> void:
	try_return_home()

func _on_board_state_changed(_place_id: String) -> void:
	invalidate_neighbourhood_state_cache()
	_fog_dirty = true
	_sync_fog_field()
	_update_frustum_culling()

func _on_board_pressed() -> void:
	open_board()

func _on_back_to_camp_pressed() -> void:
	if _walk_mode_active:
		return
	if not _caricature_camp_id.is_empty():
		focus_on_area(_caricature_camp_id, false)

func can_return_home() -> bool:
	if _is_caricature_place:
		if _walk_mode_active:
			return _area_kind(_current_walk_area_id) == "camp"
		return _return_home_button != null and _return_home_button.visible
	return _return_home_button != null and _return_home_button.visible

func try_return_home() -> bool:
	if not can_return_home():
		return false
	_world_clock.save_to_db()
	_world_clock.set_running(false)
	var db = _get_db()
	if db != null and db.is_open():
		db.delete_db_meta("last_place")
		if db.has_method("clear_player_session_place"):
			db.clear_player_session_place()
	var main_node = get_parent()
	if main_node != null and main_node.has_method("open_home_hub"):
		main_node.open_home_hub()
	elif get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/home_hub.tscn")
	return true

func _on_return_home_pressed() -> void:
	try_return_home()

func _is_tile_on_waypost_board(area_id: String, local_tile: Vector2i) -> bool:
	if not _caricature_compiled_by_area.has(area_id):
		return false
	var comp: Dictionary = _caricature_compiled_by_area[area_id]
	for st_v in comp.get("stamps", []):
		if not (st_v is Dictionary):
			continue
		var st: Dictionary = st_v
		var sid := int(st.get("stamp_id", -1))
		var def := TileSynth2.get_stamp_def(sid)
		if str(def.get("id", "")) != "waypost_board":
			continue
		var agx := int(st.get("anchor_gx", 0))
		var agy := int(st.get("anchor_gy", 0))
		var sw := int(st.get("w", def.get("w", 2)))
		var sh := int(st.get("h", def.get("h", 2)))
		var anchor_l := CaricatureWalkerGrid.global_to_local(comp, agx, agy)
		if local_tile.x >= anchor_l.x and local_tile.x < anchor_l.x + sw and local_tile.y >= anchor_l.y and local_tile.y < anchor_l.y + sh:
			return true
	return false

func _is_route_end_sign(area_id: String, sign_text: String, local_tile: Vector2i) -> Dictionary:
	if _area_kind(area_id) != "route":
		return {}
	var rid := _area_route_id(area_id)
	var r_dict: Dictionary = Neighbourhoods.route(rid)
	if r_dict.is_empty():
		return {}
	var r_name := str(r_dict.get("name", ""))
	var matched := (not r_name.is_empty() and sign_text.strip_edges() == r_name)
	if not matched and _caricature_compiled_by_area.has(area_id):
		var comp: Dictionary = _caricature_compiled_by_area[area_id]
		for op_v in comp.get("openings", []):
			if op_v is Dictionary:
				for ot_v in (op_v as Dictionary).get("outer_tiles", []):
					if ot_v is Vector2i:
						var ol := CaricatureWalkerGrid.global_to_local(comp, (ot_v as Vector2i).x, (ot_v as Vector2i).y)
						if absi(ol.x - local_tile.x) + absi(ol.y - local_tile.y) <= 6:
							matched = true
							break
			if matched:
				break
	if not matched:
		return {}
	var cost_min := NeighbourhoodProgress.route_walk_minutes(rid, false)
	var rem_day := _world_clock.daylight_minutes_left()
	return WorldClock.format_route_sign_daylight(r_name, cost_min, rem_day)

func _turn_outdoor_person(global_tile: Vector2i, person_dict: Dictionary, new_facing: String) -> void:
	_person_facing_overrides[global_tile] = new_facing
	person_dict["facing"] = new_facing
	if _person_sprites_by_global.has(global_tile):
		var ptex := PeopleSprites.resolve_texture(
			str(person_dict.get("sprite", "")),
			new_facing,
			str(person_dict.get("role", "talk")),
			_force_no_rom
		)
		for entry_v in (_person_sprites_by_global[global_tile] as Array):
			if entry_v is Dictionary:
				var sp = (entry_v as Dictionary).get("sprite", null)
				if sp != null and is_instance_valid(sp):
					(sp as Sprite2D).texture = ptex

func _erase_collected_ball_visual(global_tile: Vector2i) -> void:
	var cell := CaricatureWalkerGrid.global_tile_to_cell(global_tile.x, global_tile.y)
	var tx := posmod(global_tile.x, 32)
	var ty := posmod(global_tile.y, 32)
	var repl_coord := get_atlas_coords(TileSynth2.TILE_GRASS, 0, 0)
	if _synth_cache.has(cell):
		var item: Dictionary = _synth_cache.get_item(cell)
		var buf: PackedByteArray = item.get("buf", PackedByteArray())
		var tidx := (ty * 32 + tx) * 3
		if tidx + 2 < buf.size():
			var nb := _paving_under_tile(cell.x, cell.y, tx, ty, buf)
			if nb.x >= 0:
				repl_coord = get_atlas_coords(nb.x, 0, nb.y)
				buf[tidx] = nb.x
				buf[tidx + 1] = 0
				buf[tidx + 2] = nb.y
			else:
				buf[tidx] = TileSynth2.TILE_GRASS
				buf[tidx + 1] = 0
				buf[tidx + 2] = 0
	var rst := _global_to_render_tile(global_tile)
	if _world_cleared != null and _world_cleared.get_cell_source_id(rst) != -1:
		_world_cleared.set_cell(rst, 0, repl_coord)
	if _world_known != null and _world_known.get_cell_source_id(rst) != -1:
		_world_known.set_cell(rst, 0, repl_coord)

func _try_collect_hidden_item_at(global_tile: Vector2i) -> bool:
	if _walker_grid == null:
		return false
	var aid := _walker_grid.area_at_global(global_tile.x, global_tile.y)
	if aid.is_empty() or not _caricature_compiled_by_area.has(aid):
		return false
	var comp: Dictionary = _caricature_compiled_by_area[aid]
	var lpos := CaricatureWalkerGrid.global_to_local(comp, global_tile.x, global_tile.y)
	for hi_v in comp.get("hidden_items", []):
		if not (hi_v is Dictionary):
			continue
		var hi: Dictionary = hi_v
		if int(hi.get("x", -1)) == lpos.x and int(hi.get("y", -1)) == lpos.y:
			var hkey := hidden_item_key(aid, lpos.x, lpos.y)
			var db = _get_db()
			var already := _collected_hidden_keys.has(hkey)
			if not already and db != null and db.is_open() and db.has_method("is_item_collected"):
				already = bool(db.is_item_collected(hkey))
			if already:
				return false
			_collected_hidden_keys[hkey] = true
			var iname := str(hi.get("item", "Item"))
			var inote := str(hi.get("note", ""))
			if db != null and db.is_open() and db.has_method("mark_item_collected"):
				db.mark_item_collected(hkey, aid, "hidden", iname)
			var msg := ("Found a hidden %s! — %s" % [iname, inote]) if not inote.is_empty() else ("Found a hidden %s!" % iname)
			open_dialogue([msg])
			return true
	return false

func _on_walker_interact_pressed(facing_tile: Vector2i, standing_tile: Vector2i, facing_dir: String) -> void:
	_dispatch_walker_interact(facing_tile, standing_tile, facing_dir)

func _dispatch_walker_interact(facing_tile: Vector2i, standing_tile: Vector2i, facing_dir: String) -> bool:
	if not _walk_mode_active or _walker_grid == null:
		return false
	if _dialogue_box != null and is_instance_valid(_dialogue_box) and _dialogue_box.visible:
		return false
	var aid := _walker_grid.area_at_global(facing_tile.x, facing_tile.y)
	if not aid.is_empty() and _caricature_compiled_by_area.has(aid):
		var comp: Dictionary = _caricature_compiled_by_area[aid]
		var f_local := CaricatureWalkerGrid.global_to_local(comp, facing_tile.x, facing_tile.y)
		var w := int(comp.get("w", 0))
		var h := int(comp.get("h", 0))

		# 1. Waypost Notice Board (Camp opens board; 8 neighbourhood boards read local summary — F102)
		if _area_kind(aid) == "camp" and _is_tile_on_waypost_board(aid, f_local):
			open_board()
			return true
		elif _is_tile_on_waypost_board(aid, f_local):
			var hood: Dictionary = Neighbourhoods.area(aid)
			var hood_name := str(hood.get("name", _area_name(aid)))
			var zone := str(hood.get("zone", "residential"))
			var types_str := str(NeighbourhoodProgress.ZONE_CARD_TYPES.get(zone, "Normal"))
			var night_str := NeighbourhoodProgress.night_danger(hood)
			var mq: Dictionary = hood.get("main_quest", {}) if hood.get("main_quest") is Dictionary else {}
			var pays_str := str(mq.get("pays", ""))
			open_dialogue(["%s notice board — Types: %s · Night: %s · Pays: %s." % [
				hood_name, types_str, night_str, pays_str
			]])
			return true
		# 2. Waypost Lamp (Camp + all 8 neighbourhoods)
		var lamp_pos: Vector2i = comp.get("lamp", Vector2i(-1, -1))
		if lamp_pos.x >= 0 and (f_local == lamp_pos or f_local == Vector2i(lamp_pos.x, lamp_pos.y - 1)):
			open_lamp_menu()
			return true
		# 3. Outdoor Sign (281 signs; route end signs append daylight-colored walk time)
		for sg_v in comp.get("signs", []):
			if sg_v is Dictionary and int((sg_v as Dictionary).get("x", -1)) == f_local.x and int((sg_v as Dictionary).get("y", -1)) == f_local.y:
				var stext := str((sg_v as Dictionary).get("text", ""))
				var route_dl := _is_route_end_sign(aid, stext, f_local)
				if not route_dl.is_empty():
					open_dialogue([stext], "", str(route_dl["text"]), route_dl["color"] as Color)
				else:
					open_dialogue([stext])
				return true
		# 4. Outdoor Person (63 people; turns to face player and pages lines[])
		for pe_v in comp.get("people", []):
			if pe_v is Dictionary and int((pe_v as Dictionary).get("x", -1)) == f_local.x and int((pe_v as Dictionary).get("y", -1)) == f_local.y:
				var pe: Dictionary = pe_v
				_turn_outdoor_person(facing_tile, pe, opposite_facing(facing_dir))
				var plines: Array = pe.get("lines", []) if pe.get("lines") is Array else []
				if plines.is_empty():
					plines = ["Stay safe out past the Waypost."]
				open_dialogue(plines, str(pe.get("name", "Survivor")))
				return true
		# 5. Visible '!' Item Ball (136 balls; persisted in collected_item & removed immediately)
		if f_local.x >= 0 and f_local.x < w and f_local.y >= 0 and f_local.y < h:
			var cls_buf: PackedByteArray = comp["class"]
			var f_cls: int = cls_buf[f_local.y * w + f_local.x]
			if f_cls == TileSynth2.TILE_ITEM_BALL and not _walker_grid.is_ball_collected(aid, f_local.x, f_local.y):
				var bkey := CaricatureWalkerGrid.ball_item_key(aid, f_local.x, f_local.y)
				var bname := resolve_outdoor_ball_item_name(aid, f_local.x, f_local.y)
				var db = _get_db()
				if db != null and db.is_open() and db.has_method("mark_item_collected"):
					db.mark_item_collected(bkey, aid, "ball", bname)
				_walker_grid.mark_ball_collected(aid, f_local.x, f_local.y)
				_erase_collected_ball_visual(facing_tile)
				open_dialogue(["Found %s!" % bname])
				return true
		# 6. Street Pokemon (155 outdoor; 1 line via AssetDB.display_name from PokéAPI data pack)
		for sp_v in comp.get("street_pokemon", []):
			if sp_v is Dictionary and int((sp_v as Dictionary).get("x", -1)) == f_local.x and int((sp_v as Dictionary).get("y", -1)) == f_local.y:
				var dex := int((sp_v as Dictionary).get("dex", 0))
				var sname := AssetDB.display_name("species", dex, _data_cache_dir)
				open_dialogue(["A wild %s watches you quietly." % sname])
				return true
		# 7. Hidden Item at facing tile (219 outdoor)
		if _try_collect_hidden_item_at(facing_tile):
			return true
		# 8. HM / Water / Ordinary Door hints (plan §(d), §(g))
		if f_local.x >= 0 and f_local.x < w and f_local.y >= 0 and f_local.y < h:
			var cls_buf2: PackedByteArray = comp["class"]
			var f_cls2: int = cls_buf2[f_local.y * w + f_local.x]
			if f_cls2 == TileSynth2.TILE_WATER:
				open_dialogue(["The water is deep here. You'd need a way across."])
				return true
			if f_cls2 == TileSynth2.TILE_CUT_TREE:
				open_dialogue(["Tangled brush blocks the path. Something sharp could clear it."])
				return true
			if f_cls2 == TileSynth2.TILE_SMASH_ROCK:
				open_dialogue(["A cracked rock blocks the path. A strong blow could break it."])
				return true
			if f_cls2 == TileSynth2.TILE_BOULDER:
				open_dialogue(["A heavy boulder blocks the way. It won't move by hand."])
				return true
			if f_cls2 == TileSynth2.TILE_DOOR:
				var is_enterable := false
				for d_v in comp.get("doors", []):
					if d_v is Dictionary and int((d_v as Dictionary).get("x", -1)) == f_local.x and int((d_v as Dictionary).get("y", -1)) == f_local.y:
						if not str((d_v as Dictionary).get("interior", "")).is_empty():
							is_enterable = true
						break
				if not is_enterable:
					open_dialogue(["The door is locked."])
					return true

	# 9. Hidden Item at standing tile
	if _try_collect_hidden_item_at(standing_tile):
		return true
	return false

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
				"under_buf": res.get("under_tiles", PackedByteArray()),
				"signs": res["signs"],
				"stamps": res.get("stamps", []),
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
				"under_buf": res.get("under_tiles", PackedByteArray()),
				"signs": res["signs"],
				"stamps": res.get("stamps", []),
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
					if cls == TileSynth2.TILE_DOOR or cls == TileSynth2.TILE_RUBBLE or cls == TileSynth2.TILE_STAMP:
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
	if _is_caricature_place and not _caricature_camp_id.is_empty():
		focus_on_area(_caricature_camp_id, false)
		return
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
	var target_lm_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--landmark="):
			target_lm_id = arg.trim_prefix("--landmark=").strip_edges()
	var places: Array = RevealEngine.load_places()
	for p in places:
		if str(p.get("id", "")) == _active_place_id or _active_place_id.is_empty():
			var interiors: Array = p.get("interiors", [])
			for interior in interiors:
				var i_id: String = str(interior.get("id", ""))
				if not target_lm_id.is_empty() and i_id != target_lm_id:
					continue
				var door: Dictionary = interior.get("door", {})
				var d_lat := float(door.get("lat", 0.0))
				var d_lon := float(door.get("lon", 0.0))
				if target_lm_id.is_empty():
					var cell := Grid.latlon_to_cell(d_lat, d_lon)
					focus_on_cell(cell.x, cell.y)
					return
				var wm := Grid.latlon_to_wm(d_lat, d_lon)
				var door_gx := floori(wm.x / Grid.TILE_WM)
				var door_gy := -floori(wm.y / Grid.TILE_WM) - 1
				var sid := TileSynth2.get_landmark_stamp_id(i_id)
				var def := TileSynth2.get_stamp_def(sid)
				if not def.is_empty():
					var sw := int(def.get("w", 1))
					var sh := int(def.get("h", 1))
					var d_arr = def.get("door", [sw / 2, sh - 1])
					var d_col := int(d_arr[0]) if (d_arr is Array and d_arr.size() >= 2) else (sw / 2)
					var d_row := int(d_arr[1]) if (d_arr is Array and d_arr.size() >= 2) else (sh - 1)
					var center_tx := float(door_gx - d_col) + float(sw) * 0.5
					var visible_h := float(mini(sh, 18)) if _current_zoom_step <= 1.0 else float(mini(sh, 10))
					var center_ty := float(door_gy - d_row + sh) - visible_h * 0.5
					if _camera != null:
						_camera.position = Vector2(
							(center_tx - float(_render_origin_tile.x)) * 32.0,
							(center_ty - float(_render_origin_tile.y)) * 32.0
						)
					_update_return_home_visibility()
					return
				var fb_cell := Grid.latlon_to_cell(d_lat, d_lon)
				focus_on_cell(fb_cell.x, fb_cell.y)
				return
	_focus_initial_cell()

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _walk_mode_active and _player_walker != null:
		if _camera_follows_player and _camera != null:
			_camera.position = _player_walker.get_camera_target()
		if not _screenshot_mode:
			if _area_kind(_current_walk_area_id) == "route":
				if _player_walker.is_moving():
					_route_idle_seconds = 0.0
				else:
					_route_idle_seconds += delta
					if _route_idle_seconds >= 2.0:
						_world_clock.tick(delta)
			else:
				_route_idle_seconds = 0.0
				_world_clock.tick(delta)
	else:
		_handle_keyboard_pan(delta)
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and _banner_panel != null:
			_banner_panel.visible = false
	_update_frustum_culling()
	_drain_worker_results()
	_blit_pending_cells()
	_update_fog_overlay_rect()
	refresh_time_of_day_and_hud()
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
	var st := _render_px_to_global_tile(mouse_world)
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
						for lm_item in cell_lms:
							if lm_item is Dictionary and lm_item.has("door_st") and lm_item["door_st"] == st:
								lm_name = str(lm_item.get("name", lm_name))
								break
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
			if not (_walk_mode_active and _camera_follows_player):
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
		if _camera != null and not (_walk_mode_active and _camera_follows_player):
			_camera.position -= mm.relative / _camera.zoom.x

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_F9:
			print_p95_frame_time()

func _step_zoom(direction: int) -> void:
	var steps: Array = WALK_ZOOM_STEPS if _walk_mode_active else ZOOM_STEPS
	var curr_idx := steps.size() - 1
	for i in range(steps.size()):
		if is_equal_approx(_current_zoom_step, float(steps[i])):
			curr_idx = i
			break
	var next_idx: int = clampi(curr_idx + direction, 0, steps.size() - 1)
	_set_zoom_step(float(steps[next_idx]))

func _is_overview_zoom(zoom_val: float = _current_zoom_step) -> bool:
	var min_tile_zoom := 0.25 if _is_caricature_place else 0.5
	return zoom_val < min_tile_zoom - 0.001

func _set_zoom_step(zoom_val: float) -> void:
	var was_overview := (_overview_layer != null and _overview_layer.visible)
	_current_zoom_step = zoom_val
	if _camera != null:
		_camera.zoom = Vector2(zoom_val, zoom_val)

	var show_overview := _is_overview_zoom(_current_zoom_step)
	if was_overview != show_overview:
		_rendered_cells.clear()
		_rendered_reveal_state.clear()
		_pending_blit_cells.clear()
		_requested_cells.clear()
	if _overview_layer != null:
		_overview_layer.visible = show_overview
	if _world_known != null:
		_world_known.visible = not show_overview
	if _world_cleared != null:
		_world_cleared.visible = not show_overview
	if _tree_base_known != null:
		_tree_base_known.visible = not show_overview
	if _tree_base_cleared != null:
		_tree_base_cleared.visible = not show_overview
	if _tree_top_known != null:
		_tree_top_known.visible = not show_overview
	if _tree_top_cleared != null:
		_tree_top_cleared.visible = not show_overview
	if _fog_layer != null:
		_fog_layer.visible = true
	_fog_dirty = true
	if _stamp_base_layer != null:
		_stamp_base_layer.visible = not show_overview
	if _stamp_overhang_layer != null:
		_stamp_overhang_layer.visible = not show_overview

func _update_frustum_culling() -> void:
	if _camera == null:
		return

	var vp_size := get_viewport_rect().size / _camera.zoom.x
	var cam_pos := _camera.position
	var vis_rect := Rect2(cam_pos - vp_size * 0.5, vp_size).grow(CELL_SIZE_PX)

	var min_cx := int(floor(vis_rect.position.x / CELL_SIZE_PX)) + _render_origin_sc.x
	var max_cx := int(floor((vis_rect.position.x + vis_rect.size.x) / CELL_SIZE_PX)) + _render_origin_sc.x
	var top := vis_rect.position.y
	var bottom := vis_rect.position.y + vis_rect.size.y
	var r0 := int(floor(top / CELL_SIZE_PX)) + _render_origin_sc.y
	var r1 := int(floor(bottom / CELL_SIZE_PX)) + _render_origin_sc.y
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1

	var cam_cell_center := Vector2(
		cam_pos.x / CELL_SIZE_PX + float(_render_origin_sc.x),
		-(cam_pos.y / CELL_SIZE_PX + float(_render_origin_sc.y)) - 1.0
	)
	var visible_cell_set: Dictionary = {}
	var has_unmapped_revealed_cell := false
	var new_requests: Array[Dictionary] = []

	var db = _get_db()
	var db_open: bool = (db != null and db.is_open())
	var revealed_cells_in_view: Dictionary = {}
	var caricature_states_by_area: Dictionary = {}
	if db_open:
		if _is_caricature_place:
			caricature_states_by_area = _get_cached_neighbourhood_states()
		else:
			var q_sql := "SELECT cell_x, cell_y, reveal_state FROM map_cell WHERE cell_x >= ? AND cell_x <= ? AND cell_y >= ? AND cell_y <= ? AND reveal_state > 0;"
			var rows: Array = db.query_rows(q_sql, [min_cx, max_cx, min_cy, max_cy])
			for r in rows:
				var r_cell := Vector2i(int(r["cell_x"]), int(r["cell_y"]))
				revealed_cells_in_view[r_cell] = int(r["reveal_state"])

	var is_overview := _is_overview_zoom()
	_sync_fog_field(caricature_states_by_area)

	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			visible_cell_set[cell] = true

			var reveal_state: int = (
				_caricature_reveal_state(cell, caricature_states_by_area)
				if _is_caricature_place
				else int(revealed_cells_in_view.get(cell, 0))
			)

			if _rendered_cells.has(cell) and int(_rendered_reveal_state.get(cell, -1)) != reveal_state:
				_unrender_cell(cx, cy)
				_rendered_cells.erase(cell)
				if _synth_cache.has(cell):
					var c_item: Dictionary = _synth_cache.get_item(cell)
					c_item["reveal_state"] = reveal_state
					c_item["image"] = null
				for nbr in [Vector2i(cx + 1, cy), Vector2i(cx - 1, cy), Vector2i(cx, cy + 1), Vector2i(cx, cy - 1)]:
					if _rendered_cells.has(nbr) and int(_rendered_reveal_state.get(nbr, 0)) > 0 and _synth_cache.has(nbr):
						_rendered_cells.erase(nbr)
						if not _pending_blit_cells.has(nbr):
							_pending_blit_cells.append(nbr)

			if reveal_state == 0:
				if not _rendered_cells.has(cell):
					_render_unknown_cell(cx, cy)
					_rendered_cells[cell] = true
					_rendered_reveal_state[cell] = 0
			else:
				if _synth_cache.has(cell):
					var cached_item: Dictionary = _synth_cache.get_item(cell)
					if int(cached_item.get("reveal_state", 1)) != reveal_state:
						cached_item["reveal_state"] = reveal_state
						cached_item["image"] = null
					if not _rendered_cells.has(cell) and not _pending_blit_cells.has(cell):
						_pending_blit_cells.append(cell)
				elif _rendered_cells.has(cell):
					# Drawn already; its cache entry was evicted (a view can show more cells than the cache holds).
					# Synthesizing it again would only evict a nearer cell and starve the farthest ones (Item 25b).
					pass
				else:
					if not is_overview:
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
		# The worker keeps the nearest SynthWorker.MAX_QUEUED_REQUESTS; the cells it forgot are requested again once there is room (F61).
		var dropped: Array[Vector2i] = _synth_worker.update_requests(new_requests, visible_cell_set)
		for dropped_cell in dropped:
			_requested_cells.erase(dropped_cell)

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
			"under_buf": res.get("under_tiles", PackedByteArray()),
			"signs": res["signs"],
			"stamps": res.get("stamps", []),
			"fixtures": res.get("fixtures", []),
			"people": res.get("people", []),
			"street_pokemon": res.get("street_pokemon", []),
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
	var is_overview := _is_overview_zoom()
	var max_blits := 64 if is_overview else 2

	while not _pending_blit_cells.is_empty() and blits_this_frame < max_blits:
		var cell: Vector2i = _pending_blit_cells.pop_front()
		if not _synth_cache.has(cell):
			continue
		var item: Dictionary = _synth_cache.get_item(cell)
		_blit_cell(cell.x, cell.y, item)
		_rendered_cells[cell] = true
		_rendered_reveal_state[cell] = int(item.get("reveal_state", 1))
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
		chunk_img.fill(Color8(128, 132, 145, 255))
		var chunk_tex := ImageTexture.create_from_image(chunk_img)
		var sprite := Sprite2D.new()
		sprite.centered = false
		# North-up: chunk covers cells cy in [chunk_cy .. chunk_cy + 7], so its top screen edge is at (-chunk_cy - 8) * CELL_SIZE_PX
		sprite.position = Vector2(
			float(chunk_cx - _render_origin_sc.x) * CELL_SIZE_PX,
			float((-chunk_cy - 8) - _render_origin_sc.y) * CELL_SIZE_PX
		)
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

func _effective_class_in_compiled(comp: Dictionary, lx: int, ly: int, resolve_objects: bool = true) -> int:
	var w := int(comp.get("w", 0))
	var h := int(comp.get("h", 0))
	if lx < 0 or lx >= w or ly < 0 or ly >= h:
		return TileSynth2.TILE_VOID
	var cls_buf: PackedByteArray = comp["class"]
	var c: int = cls_buf[ly * w + lx]
	if resolve_objects and (c == TileSynth2.TILE_ITEM_BALL or c == TileSynth2.TILE_SIGN):
		var nc := _effective_class_in_compiled(comp, lx, ly - 1, false)
		var ec := _effective_class_in_compiled(comp, lx + 1, ly, false)
		var sc := _effective_class_in_compiled(comp, lx, ly + 1, false)
		var wc := _effective_class_in_compiled(comp, lx - 1, ly, false)
		var pcls := TileSynth2.resolve_paving_class_from_neighbors(nc, ec, sc, wc)
		return pcls if pcls >= 0 else TileSynth2.TILE_GRASS
	return c

func _paving_under_tile(cx: int, cy: int, tx: int, ty: int, tile_buf: PackedByteArray) -> Vector2i:
	# Decision 82 (Item 82 / F106): Treat the ball or sign tile as the surrounding paving class
	# and compute its OWN 4-bit edge mask with TileSynth2's exact mask family (never copy a neighbor's mask).
	var n_cls := TileSynth2.TILE_VOID
	var e_cls := TileSynth2.TILE_VOID
	var s_cls := TileSynth2.TILE_VOID
	var w_cls := TileSynth2.TILE_VOID
	var used_compiled := false
	if _is_caricature_place and _walker_grid != null:
		var gst := _global_screen_tile(cx, cy, tx, ty)
		var aid := _walker_grid.area_at_global(gst.x, gst.y)
		if not aid.is_empty() and _caricature_compiled_by_area.has(aid):
			var comp: Dictionary = _caricature_compiled_by_area[aid]
			var loc := CaricatureWalkerGrid.global_to_local(comp, gst.x, gst.y)
			n_cls = _effective_class_in_compiled(comp, loc.x, loc.y - 1, true)
			e_cls = _effective_class_in_compiled(comp, loc.x + 1, loc.y, true)
			s_cls = _effective_class_in_compiled(comp, loc.x, loc.y + 1, true)
			w_cls = _effective_class_in_compiled(comp, loc.x - 1, loc.y, true)
			used_compiled = true
	if not used_compiled:
		if ty > 0:
			n_cls = int(tile_buf[((ty - 1) * 32 + tx) * 3])
		if tx < 31:
			e_cls = int(tile_buf[(ty * 32 + (tx + 1)) * 3])
		if ty < 31:
			s_cls = int(tile_buf[((ty + 1) * 32 + tx) * 3])
		if tx > 0:
			w_cls = int(tile_buf[(ty * 32 + (tx - 1)) * 3])
	var pave_cls := TileSynth2.resolve_paving_class_from_neighbors(n_cls, e_cls, s_cls, w_cls)
	if pave_cls < 0:
		return Vector2i(-1, 0)
	var own_mask := TileSynth2.compute_paving_mask_from_neighbors(pave_cls, n_cls, e_cls, s_cls, w_cls)
	return Vector2i(pave_cls, own_mask)

func _sign_pavement_neighbor(tile_buf: PackedByteArray, tx: int, ty: int) -> Vector2i:
	var n_cls := int(tile_buf[((ty - 1) * 32 + tx) * 3]) if ty > 0 else TileSynth2.TILE_VOID
	var e_cls := int(tile_buf[(ty * 32 + (tx + 1)) * 3]) if tx < 31 else TileSynth2.TILE_VOID
	var s_cls := int(tile_buf[((ty + 1) * 32 + tx) * 3]) if ty < 31 else TileSynth2.TILE_VOID
	var w_cls := int(tile_buf[(ty * 32 + (tx - 1)) * 3]) if tx > 0 else TileSynth2.TILE_VOID
	var pave_cls := TileSynth2.resolve_paving_class_from_neighbors(n_cls, e_cls, s_cls, w_cls)
	if pave_cls < 0:
		return Vector2i(-1, 0)
	return Vector2i(pave_cls, TileSynth2.compute_paving_mask_from_neighbors(pave_cls, n_cls, e_cls, s_cls, w_cls))


func _blit_cell(cx: int, cy: int, item: Dictionary) -> void:
	var cell := Vector2i(cx, cy)
	var tile_buf: PackedByteArray = item.get("buf", PackedByteArray())
	var under_buf: PackedByteArray = item.get("under_buf", PackedByteArray())
	var reveal_state: int = item.get("reveal_state", 1)
	var has_map_data: bool = item.get("has_data", false)
	var is_overview := _is_overview_zoom()

	if not is_overview:
		if reveal_state == 0:
			_render_solid_fog(cx, cy)
		else:
			var target_layer: TileMapLayer = _world_cleared if (_preview_cleared or reveal_state >= 2) else _world_known
			var other_layer: TileMapLayer = _world_known if target_layer == _world_cleared else _world_cleared
			var target_tree_base_layer: TileMapLayer = _tree_base_cleared if (_preview_cleared or reveal_state >= 2) else _tree_base_known
			var other_tree_base_layer: TileMapLayer = _tree_base_known if target_tree_base_layer == _tree_base_cleared else _tree_base_cleared
			var target_top_layer: TileMapLayer = _tree_top_cleared if (_preview_cleared or reveal_state >= 2) else _tree_top_known
			var other_top_layer: TileMapLayer = _tree_top_known if target_top_layer == _tree_top_cleared else _tree_top_cleared

			for ty in 32:
				for tx in 32:
					var idx := (ty * 32 + tx) * 3
					var cls: int = tile_buf[idx]
					var st := _screen_tile(cx, cy, tx, ty)
					var gst := _global_screen_tile(cx, cy, tx, ty)
					var base_coord := get_tile_atlas_coords(tile_buf, under_buf, idx)
					if cls == TileSynth2.TILE_ITEM_BALL and _is_caricature_place and _walker_grid != null:
						var b_aid := _walker_grid.area_at_global(gst.x, gst.y)
						if not b_aid.is_empty() and _caricature_compiled_by_area.has(b_aid):
							var b_loc := CaricatureWalkerGrid.global_to_local(_caricature_compiled_by_area[b_aid], gst.x, gst.y)
							if _walker_grid.is_ball_collected(b_aid, b_loc.x, b_loc.y):
								var nb_b := _paving_under_tile(cx, cy, tx, ty, tile_buf)
								base_coord = get_atlas_coords(nb_b.x, 0, nb_b.y) if nb_b.x >= 0 else get_atlas_coords(TileSynth2.TILE_GRASS, 0, 0)
					if not _force_no_rom and cls == TileSynth2.TILE_SIGN:
						var nb := _paving_under_tile(cx, cy, tx, ty, tile_buf)
						if nb.x >= 0:
							base_coord = get_atlas_coords(nb.x, 0, nb.y)
					var top_st := st + Vector2i(0, -1)
					if cls == TileSynth2.TILE_TREE:
						# Decision 81 (Item 77 / F92): Draw map ground on World layer and transparent tree base
						# on TreeBase layer (z=0) + transparent canopy overhang on TreeTop layer (z=2, above sprites).
						var tree_ground := get_atlas_coords(TileSynth2.TILE_GRASS, 0, 0)
						target_layer.set_cell(st, 0, tree_ground)
						other_layer.erase_cell(st)
						if target_tree_base_layer != null:
							target_tree_base_layer.set_cell(st, 0, base_coord)
						if other_tree_base_layer != null:
							other_tree_base_layer.erase_cell(st)
						if target_top_layer != null:
							target_top_layer.set_cell(top_st, 0, Vector2i(base_coord.x + 8, base_coord.y))
						if other_top_layer != null:
							other_top_layer.erase_cell(top_st)
					else:
						target_layer.set_cell(st, 0, base_coord)
						other_layer.erase_cell(st)
						if target_tree_base_layer != null:
							target_tree_base_layer.erase_cell(st)
						if other_tree_base_layer != null:
							other_tree_base_layer.erase_cell(st)
						if target_top_layer != null:
							target_top_layer.erase_cell(top_st)
						if other_top_layer != null:
							other_top_layer.erase_cell(top_st)

			_render_cell_stamps(cx, cy, item)

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
	if not _is_overview_zoom():
		_render_solid_fog(cx, cy)
	if _overview_layer != null:
		_blit_cell_to_overview_chunk(cx, cy, _get_unknown_overview_image())

func _get_unknown_overview_image() -> Image:
	if _unknown_overview_img == null:
		_unknown_overview_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		_unknown_overview_img.fill(Color8(128, 132, 145, 255))
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
				base_col = Color8(128, 132, 145, 255)
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

func _global_screen_tile(cx: int, cy: int, tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * 32 + tx, (-cy - 1) * 32 + ty)

func _screen_tile(cx: int, cy: int, tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * 32 + tx - _render_origin_tile.x, (-cy - 1) * 32 + ty - _render_origin_tile.y)

func _is_cell_hidden(cx: int, cy: int) -> bool:
	if _is_caricature_place:
		return _caricature_reveal_state(Vector2i(cx, cy)) == 0
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
	if _is_caricature_place:
		reveal_state = _caricature_reveal_state(cell)
	else:
		var db = _get_db()
		if db != null and db.is_open():
			var rows: Array = db.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [cx, cy])
			if not rows.is_empty():
				reveal_state = int(rows[0].get("reveal_state", 0))

	if reveal_state == 0:
		_render_unknown_cell(cx, cy)
		_rendered_cells[cell] = true
		_fog_dirty = true
		_sync_fog_field()
		return false

	var item: Dictionary = {}
	if _synth_cache.has(cell):
		item = _synth_cache.get_item(cell)
	elif _synth_worker != null and _synth_worker.is_running():
		var res: Dictionary = _synth_worker.request_cell_sync(cell, _is_overview_zoom(), reveal_state, _preview_cleared)
		item = {
			"buf": res["tiles"],
			"under_buf": res.get("under_tiles", PackedByteArray()),
			"signs": res["signs"],
			"stamps": res.get("stamps", []),
			"fixtures": res.get("fixtures", []),
			"people": res.get("people", []),
			"street_pokemon": res.get("street_pokemon", []),
			"has_data": res["has_data"],
			"image": res.get("image", null),
			"thread_id": res.get("thread_id", 0),
			"reveal_state": reveal_state
		}
		_synth_cache.put(cell, item)
	elif _is_caricature_place and _caricature_cells.has(cell):
		var c_entry: Dictionary = _caricature_cells[cell]
		var c_res: Dictionary = CaricatureMap.cell_result(
			c_entry.get("compiled", {}),
			cell,
			c_entry.get("area", {})
		)
		item = {
			"buf": c_res.get("tiles", PackedByteArray()),
			"under_buf": c_res.get("under_tiles", PackedByteArray()),
			"signs": c_res.get("signs", []),
			"stamps": c_res.get("stamps", []),
			"fixtures": c_res.get("fixtures", []),
			"people": c_res.get("people", []),
			"street_pokemon": c_res.get("street_pokemon", []),
			"has_data": true,
			"thread_id": OS.get_thread_caller_id(),
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
			"stamps": synth_res.get("stamps", []),
			"has_data": has_map_data or is_covered_by_store,
			"thread_id": OS.get_thread_caller_id(),
			"reveal_state": reveal_state
		}
		_synth_cache.put(cell, item)

	_blit_cell(cx, cy, item)
	_flush_overview_chunks()
	_rendered_cells[cell] = true
	_fog_dirty = true
	_sync_fog_field()
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
	_clear_cell_stamps(Vector2i(cx, cy))
	_fog_dirty = true
	for ty in 32:
		for tx in 32:
			var st := _screen_tile(cx, cy, tx, ty)
			var top_st := st + Vector2i(0, -1)
			if _world_known != null:
				_world_known.erase_cell(st)
			if _world_cleared != null:
				_world_cleared.erase_cell(st)
			if _tree_base_known != null:
				_tree_base_known.erase_cell(st)
			if _tree_base_cleared != null:
				_tree_base_cleared.erase_cell(st)
			if _tree_top_known != null:
				_tree_top_known.erase_cell(top_st)
			if _tree_top_cleared != null:
				_tree_top_cleared.erase_cell(top_st)

func _unrender_cell(cx: int, cy: int) -> void:
	var cell := Vector2i(cx, cy)
	_rendered_reveal_state.erase(cell)
	_unmapped_revealed_cells.erase(cell)
	_clear_cell_stamps(cell)
	_fog_dirty = true
	for ty in 32:
		for tx in 32:
			var coord := _screen_tile(cx, cy, tx, ty)
			var top_coord := coord + Vector2i(0, -1)
			if _world_known != null:
				_world_known.erase_cell(coord)
			if _world_cleared != null:
				_world_cleared.erase_cell(coord)
			if _tree_base_known != null:
				_tree_base_known.erase_cell(coord)
			if _tree_base_cleared != null:
				_tree_base_cleared.erase_cell(coord)
			if _tree_top_known != null:
				_tree_top_known.erase_cell(top_coord)
			if _tree_top_cleared != null:
				_tree_top_cleared.erase_cell(top_coord)

func _init_fog_overlay() -> void:
	_fog_grid_img = Image.create(FOG_GRID_SIZE, FOG_GRID_SIZE, false, Image.FORMAT_RGBA8)
	_fog_grid_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fog_grid_tex = ImageTexture.create_from_image(_fog_grid_img)
	_fog_dirty = true
	_fog_state_sig = ""
	if _fog_layer != null and _fog_layer.material is ShaderMaterial:
		var sm := _fog_layer.material as ShaderMaterial
		sm.set_shader_parameter("cell_reveal_tex", _fog_grid_tex)
		sm.set_shader_parameter("cell_grid_origin", Vector2(_fog_grid_origin))
		sm.set_shader_parameter("cell_grid_size", Vector2(FOG_GRID_SIZE, FOG_GRID_SIZE))
		sm.set_shader_parameter("town_rect_count", 0)
		sm.set_shader_parameter("time_override", -1.0)
	_update_fog_overlay_rect()

func _update_fog_overlay_rect() -> void:
	if _fog_layer == null:
		return
	var vp_px := get_viewport_rect().size
	if vp_px.x <= 1.0 or vp_px.y <= 1.0:
		vp_px = Vector2(1280.0, 720.0)
	var z := _camera.zoom.x if (_camera != null and _camera.zoom.x > 0.0001) else 1.0
	var half_w := (vp_px.x / z) * 0.5 + float(TILE_SIZE_PX) * 6.0
	var half_h := (vp_px.y / z) * 0.5 + float(TILE_SIZE_PX) * 6.0
	var cpos := _camera.position if _camera != null else Vector2.ZERO
	var top_left := cpos - Vector2(half_w, half_h)
	var sz := Vector2(half_w * 2.0, half_h * 2.0)
	_fog_layer.position = top_left
	_fog_layer.size = sz
	if _background_layer != null:
		_background_layer.position = top_left
		_background_layer.size = sz
	if _fog_layer.material is ShaderMaterial:
		var sm := _fog_layer.material as ShaderMaterial
		sm.set_shader_parameter("rect_origin_tiles", top_left / float(TILE_SIZE_PX))
		sm.set_shader_parameter("rect_size_tiles", sz / float(TILE_SIZE_PX))
		sm.set_shader_parameter("zoom_scale", z)

func _sync_fog_field(caricature_states_by_area: Dictionary = {}) -> void:
	if _fog_grid_img == null or _fog_grid_tex == null:
		_init_fog_overlay()
	var cam_st := (_camera.position / float(TILE_SIZE_PX)) if _camera != null else Vector2.ZERO
	var cam_sc := Vector2i(floori(cam_st.x / 32.0), floori(cam_st.y / 32.0)) + _render_origin_sc
	var half_g := int(FOG_GRID_SIZE / 2)
	if _fog_dirty or absi(cam_sc.x - (_fog_grid_origin.x + half_g)) > 16 or absi(cam_sc.y - (_fog_grid_origin.y + half_g)) > 16:
		_fog_grid_origin = Vector2i(cam_sc.x - half_g, cam_sc.y - half_g)
		_fog_dirty = true

	var db = _get_db()
	var db_open: bool = (db != null and db.is_open())
	var states_map: Dictionary = caricature_states_by_area
	if _is_caricature_place and states_map.is_empty() and db_open:
		states_map = _get_cached_neighbourhood_states()

	var sig_parts := PackedStringArray()
	sig_parts.append("%d,%d,%d" % [_fog_grid_origin.x, _fog_grid_origin.y, 1 if _is_caricature_place else 0])
	var non_cari_cells: Array[Vector2i] = []
	if _is_caricature_place:
		var skeys := states_map.keys()
		skeys.sort()
		for k in skeys:
			if str(k) != "__loaded__":
				sig_parts.append("%s=%d" % [str(k), int(states_map[k])])
		sig_parts.append("areas=%d" % _caricature_compiled_by_area.size())
	else:
		if db_open:
			var cx0: int = _fog_grid_origin.x
			var cx1: int = cx0 + FOG_GRID_SIZE - 1
			var cy_max: int = -_fog_grid_origin.y - 1
			var cy_min: int = -(_fog_grid_origin.y + FOG_GRID_SIZE - 1) - 1
			var rows_q: Array = db.query_rows(
				"SELECT cell_x, cell_y FROM map_cell WHERE cell_x >= ? AND cell_x <= ? AND cell_y >= ? AND cell_y <= ? AND reveal_state > 0 ORDER BY cell_x, cell_y;",
				[cx0, cx1, cy_min, cy_max]
			)
			for r in rows_q:
				var c_v := Vector2i(int(r["cell_x"]), int(r["cell_y"]))
				non_cari_cells.append(c_v)
				sig_parts.append("%d:%d" % [c_v.x, c_v.y])

	var sig := "|".join(sig_parts)
	if not _fog_dirty and sig == _fog_state_sig:
		return

	_fog_grid_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fog_town_rects.clear()
	if _is_caricature_place:
		for cell_v in _caricature_cells.keys():
			var cell: Vector2i = cell_v
			var scx: int = cell.x
			var scy: int = -cell.y - 1
			var u: int = scx - _fog_grid_origin.x
			var v: int = scy - _fog_grid_origin.y
			if u >= 0 and u < FOG_GRID_SIZE and v >= 0 and v < FOG_GRID_SIZE:
				if _caricature_reveal_state(cell, states_map) > 0:
					var cell_entry: Dictionary = _caricature_cells[cell]
					var cell_area: Dictionary = cell_entry.get("area", {}) if cell_entry.get("area") is Dictionary else {}
					var cell_kind := str(cell_area.get("kind", ""))
					var cell_aid := str(cell_area.get("id", ""))
					var allow_mist := 0.0 if (cell_kind == "camp" or cell_aid.begins_with("camp:")) else 1.0
					_fog_grid_img.set_pixel(u, v, Color(1.0, allow_mist, 0.0, 1.0))
		for aid_v in _caricature_compiled_by_area.keys():
			var comp: Dictionary = _caricature_compiled_by_area[aid_v]
			var t_rects: Array = comp.get("town", [])
			if t_rects.is_empty():
				continue
			var orig: Vector2i = comp.get("origin", Vector2i.ZERO)
			var rows_c: int = int(comp.get("rows", 1))
			if _caricature_reveal_state(orig, states_map) <= 0:
				continue
			var gx0: int = orig.x * 32
			var gy0: int = (-(orig.y + rows_c - 1) - 1) * 32
			for rv in t_rects:
				if rv is Array and (rv as Array).size() >= 4 and _fog_town_rects.size() < 32:
					var ra: Array = rv
					_fog_town_rects.append(Vector4(
						float(gx0 + int(ra[0])),
						float(gy0 + int(ra[1])),
						float(gx0 + int(ra[0]) + int(ra[2])),
						float(gy0 + int(ra[1]) + int(ra[3]))
					))
	else:
		for c_v in non_cari_cells:
			var scx: int = c_v.x
			var scy: int = -c_v.y - 1
			var u: int = scx - _fog_grid_origin.x
			var v: int = scy - _fog_grid_origin.y
			if u >= 0 and u < FOG_GRID_SIZE and v >= 0 and v < FOG_GRID_SIZE:
				_fog_grid_img.set_pixel(u, v, Color(1.0, 0.0, 0.0, 1.0))

	_fog_grid_tex.update(_fog_grid_img)
	if _fog_layer != null and _fog_layer.material is ShaderMaterial:
		var sm := _fog_layer.material as ShaderMaterial
		sm.set_shader_parameter("cell_reveal_tex", _fog_grid_tex)
		sm.set_shader_parameter("cell_grid_origin", Vector2(_fog_grid_origin - _render_origin_sc))
		sm.set_shader_parameter("cell_grid_size", Vector2(FOG_GRID_SIZE, FOG_GRID_SIZE))
		sm.set_shader_parameter("town_rect_count", _fog_town_rects.size())
		var origin_t4 := Vector4(float(_render_origin_tile.x), float(_render_origin_tile.y), float(_render_origin_tile.x), float(_render_origin_tile.y))
		var padded: Array[Vector4] = []
		padded.resize(32)
		for i in range(32):
			padded[i] = (_fog_town_rects[i] - origin_t4) if i < _fog_town_rects.size() else Vector4.ZERO
		sm.set_shader_parameter("town_rects", padded)
	_fog_dirty = false
	_fog_state_sig = sig
	_update_fog_overlay_rect()

static func _fog_hash21(p: Vector2) -> float:
	var x := fposmod(p.x * 0.1031, 1.0)
	var y := fposmod(p.y * 0.1031, 1.0)
	var z := fposmod(p.x * 0.1031, 1.0)
	var d := x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33)
	return fposmod((x + d + y + d) * (z + d), 1.0)

static func _fog_vnoise(p: Vector2, seed_val: float) -> float:
	var ix: float = floorf(p.x)
	var iy: float = floorf(p.y)
	var fx: float = p.x - ix
	var fy: float = p.y - iy
	var ux: float = fx * fx * (3.0 - 2.0 * fx)
	var uy: float = fy * fy * (3.0 - 2.0 * fy)
	var off := Vector2(seed_val, seed_val * 1.37)
	var a := _fog_hash21(Vector2(ix, iy) + off)
	var b := _fog_hash21(Vector2(ix + 1.0, iy) + off)
	var c := _fog_hash21(Vector2(ix, iy + 1.0) + off)
	var d := _fog_hash21(Vector2(ix + 1.0, iy + 1.0) + off)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)

static func _fog_fbm3(p: Vector2, cell_sz: Vector2, seed_val: float) -> float:
	var q := Vector2(p.x / cell_sz.x, p.y / cell_sz.y)
	var v := (
		1.0 * _fog_vnoise(q, seed_val)
		+ 0.5 * _fog_vnoise(q * 2.0, seed_val + 3.1)
		+ 0.25 * _fog_vnoise(q * 4.0, seed_val + 6.7)
	) / 1.75
	return clampf((v - 0.25) / 0.5, 0.0, 1.0)

func _sample_fog_cell(scx: int, scy: int) -> Color:
	if _fog_grid_img == null:
		return Color(0.0, 0.0, 0.0, 1.0)
	var u := scx - _fog_grid_origin.x
	var v := scy - _fog_grid_origin.y
	if u < 0 or v < 0 or u >= FOG_GRID_SIZE or v >= FOG_GRID_SIZE:
		return Color(0.0, 0.0, 0.0, 1.0)
	return _fog_grid_img.get_pixel(u, v)

func evaluate_fog_at_tile(st: Vector2, time_sec: float = 0.0) -> Dictionary:
	_sync_fog_field()
	var drift := Vector2(-time_sec / 3.0, 0.0)
	var n := _fog_fbm3(st + drift, Vector2(6.0, 2.2), 11.0)
	var n2 := _fog_fbm3(st + drift, Vector2(10.0, 4.0), 18.0)
	var scx := floori(st.x / 32.0)
	var scy := floori(st.y / 32.0)
	var loc := Vector2(st.x - float(scx * 32), st.y - float(scy * 32))
	var here := _sample_fog_cell(scx, scy)
	var bank := Color(92.0 / 255.0, 96.0 / 255.0, 110.0 / 255.0, 1.0).lerp(
		Color(168.0 / 255.0, 172.0 / 255.0, 184.0 / 255.0, 1.0), n2
	)
	if here.r < 0.5:
		return {
			"outside": true,
			"d_edge": -1.0,
			"d_town": 100.0,
			"a_edge": 1.0,
			"a_mist": 0.0,
			"alpha": 1.0,
			"color": bank,
		}
	var d_edge := 100.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if _sample_fog_cell(scx + dx, scy + dy).r < 0.5:
				var ex := loc.x if dx < 0 else ((32.0 - loc.x) if dx > 0 else 0.0)
				var ey := loc.y if dy < 0 else ((32.0 - loc.y) if dy > 0 else 0.0)
				d_edge = minf(d_edge, Vector2(ex, ey).length())
	var t_edge := clampf(d_edge / 9.0, 0.0, 1.0)
	var sm_edge := t_edge * t_edge * (3.0 - 2.0 * t_edge)
	var a_edge := pow(1.0 - sm_edge, 1.4) * lerpf(0.55, 1.0, n)
	var t_rim := clampf(d_edge / 1.5, 0.0, 1.0)
	var sm_rim := t_rim * t_rim * (3.0 - 2.0 * t_rim)
	a_edge = maxf(a_edge, 1.0 - sm_rim)
	var d_town := 100.0
	var a_mist := 0.0
	if here.g > 0.5:
		for r in _fog_town_rects:
			var dx_t := maxf(maxf(r.x - st.x, st.x - r.z), 0.0)
			var dy_t := maxf(maxf(r.y - st.y, st.y - r.w), 0.0)
			d_town = minf(d_town, Vector2(dx_t, dy_t).length())
		var t_town := clampf(d_town / 5.0, 0.0, 1.0)
		var sm_town := t_town * t_town * (3.0 - 2.0 * t_town)
		a_mist = 0.34 * lerpf(0.30, 1.0, n) * sm_town
	var alpha := 1.0 - (1.0 - a_edge) * (1.0 - a_mist)
	var t_col := clampf(d_edge / 2.5, 0.0, 1.0)
	var sm_col := t_col * t_col * (3.0 - 2.0 * t_col)
	var fog_col := bank.lerp(Color(206.0 / 255.0, 210.0 / 255.0, 220.0 / 255.0, 1.0), sm_col)
	fog_col.a = alpha
	return {
		"outside": false,
		"d_edge": d_edge,
		"d_town": d_town,
		"a_edge": a_edge,
		"a_mist": a_mist,
		"alpha": alpha,
		"color": fog_col,
	}

func _clear_cell_stamps(cell: Vector2i) -> void:
	if not _cell_stamp_sprites.has(cell):
		return
	var sprites: Array = _cell_stamp_sprites[cell]
	for s in sprites:
		if is_instance_valid(s):
			s.queue_free()
	_cell_stamp_sprites.erase(cell)

func _load_stamp_image(sid: int, def: Dictionary) -> Image:
	if _stamp_images.has(sid):
		return _stamp_images[sid]
	var rel_path: String = str(def.get("path", ""))
	if rel_path.is_empty():
		return null
	var res_path := "res://assets/original/" + rel_path
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img: Image = null
	if FileAccess.file_exists(abs_path):
		img = Image.load_from_file(abs_path)
	if (img == null or img.is_empty()) and ResourceLoader.exists(res_path):
		var loaded = load(res_path)
		if loaded is Texture2D:
			img = (loaded as Texture2D).get_image()
		elif loaded is Image:
			img = loaded
	if img != null and not img.is_empty():
		_stamp_images[sid] = img
		return img
	return null

func _get_stamp_texture(sid: int, sw: int, sh: int, def: Dictionary) -> Texture2D:
	if bool(def.get("tiled", false)):
		var t_key := Vector3i(sid, sw, sh)
		if _tiled_stamp_textures.has(t_key):
			return _tiled_stamp_textures[t_key]
		var src_img := _load_stamp_image(sid, def)
		if src_img == null:
			return null
		var out_img := Image.create(sw * 16, sh * 16, false, src_img.get_format())
		for y in sh:
			for x in sw:
				var src_t: Vector2i = TileSynth2.ruined_block_src_tile(x, y, sw, sh)
				out_img.blit_rect(src_img, Rect2i(src_t.x * 16, src_t.y * 16, 16, 16), Vector2i(x * 16, y * 16))
		var t_tex := ImageTexture.create_from_image(out_img)
		_tiled_stamp_textures[t_key] = t_tex
		return t_tex

	if _stamp_textures.has(sid):
		return _stamp_textures[sid]
	var img := _load_stamp_image(sid, def)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_stamp_textures[sid] = tex
	return tex

func _add_sliced_sprite_to_layers(cx: int, cell_r0: int, agx: int, agy: int, sw: int, sh: int, split_ty: int, tex: Texture2D, tex_tile_px: int, sprite_scale: float, known_mat: Material, created: Array[Sprite2D]) -> void:
	if tex == null or sw <= 0 or sh <= 0:
		return
	var tx0: int = maxi(0, cx * 32 - agx)
	var tx1: int = mini(sw, (cx + 1) * 32 - agx)
	var ty0: int = maxi(0, cell_r0 - agy)
	var ty1: int = mini(sh, cell_r0 + 32 - agy)
	if tx0 >= tx1 or ty0 >= ty1:
		return

	if ty0 < split_ty and _stamp_overhang_layer != null:
		var o_ty0: int = ty0
		var o_ty1: int = mini(ty1, split_ty)
		var o_sp := Sprite2D.new()
		o_sp.centered = false
		o_sp.texture = tex
		o_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		o_sp.region_enabled = true
		o_sp.region_rect = Rect2(float(tx0 * tex_tile_px), float(o_ty0 * tex_tile_px), float((tx1 - tx0) * tex_tile_px), float((o_ty1 - o_ty0) * tex_tile_px))
		o_sp.scale = Vector2(sprite_scale, sprite_scale)
		o_sp.position = Vector2(
			float((agx + tx0 - _render_origin_tile.x) * 32),
			float((agy + sh - _render_origin_tile.y) * 32)
		)
		o_sp.offset = Vector2(0.0, float((o_ty0 - sh) * tex_tile_px))
		o_sp.material = known_mat
		_stamp_overhang_layer.add_child(o_sp)
		created.append(o_sp)

	if ty1 > split_ty:
		var b_ty0: int = maxi(ty0, split_ty)
		var b_ty1: int = ty1
		var b_sp := Sprite2D.new()
		b_sp.centered = false
		b_sp.texture = tex
		b_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b_sp.region_enabled = true
		b_sp.region_rect = Rect2(float(tx0 * tex_tile_px), float(b_ty0 * tex_tile_px), float((tx1 - tx0) * tex_tile_px), float((b_ty1 - b_ty0) * tex_tile_px))
		b_sp.scale = Vector2(sprite_scale, sprite_scale)
		b_sp.position = Vector2(
			float((agx + tx0 - _render_origin_tile.x) * 32),
			float((agy + sh - _render_origin_tile.y) * 32)
		)
		b_sp.offset = Vector2(0.0, float((b_ty0 - sh) * tex_tile_px))
		b_sp.material = known_mat
		_stamp_base_layer.add_child(b_sp)
		created.append(b_sp)


func _render_cell_stamps(cx: int, cy: int, item: Dictionary) -> void:
	var cell := Vector2i(cx, cy)
	_clear_cell_stamps(cell)
	if _stamp_base_layer == null:
		return
	var stamps: Array = item.get("stamps", [])
	var fixtures: Array = item.get("fixtures", [])
	var people: Array = item.get("people", [])
	var street_pokemon: Array = item.get("street_pokemon", [])
	var tile_buf: PackedByteArray = item.get("buf", PackedByteArray())
	if stamps.is_empty() and fixtures.is_empty() and people.is_empty() and street_pokemon.is_empty() and (_force_no_rom or tile_buf.is_empty()):
		return
	var reveal_state: int = int(item.get("reveal_state", 1))
	if reveal_state <= 0:
		return
	var is_known_look: bool = (reveal_state == 1 and not _preview_cleared)
	var known_mat: Material = _world_known.material if (is_known_look and _world_known != null) else null
	var created: Array[Sprite2D] = []
	var cell_r0: int = (-cy - 1) * 32

	var sorted_stamps: Array = stamps.duplicate()
	sorted_stamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay: int = int(a.get("anchor_gy", 0)) + int(a.get("h", 0))
		var by: int = int(b.get("anchor_gy", 0)) + int(b.get("h", 0))
		if ay != by:
			return ay < by
		var ax: int = int(a.get("anchor_gx", 0))
		var bx: int = int(b.get("anchor_gx", 0))
		if ax != bx:
			return ax < bx
		return int(a.get("stamp_id", 0)) < int(b.get("stamp_id", 0))
	)

	for st in sorted_stamps:
		var sid: int = int(st.get("stamp_id", -1))
		var agx: int = int(st.get("anchor_gx", 0))
		var agy: int = int(st.get("anchor_gy", 0))
		var sw: int = int(st.get("w", 0))
		var sh: int = int(st.get("h", 0))
		if sid <= 0 or sw <= 0 or sh <= 0:
			continue
		var def: Dictionary = TileSynth2.get_stamp_def(sid)
		if def.is_empty():
			continue
		var tex: Texture2D = _get_stamp_texture(sid, sw, sh, def)
		var base_rows: int = sh if bool(def.get("tiled", false)) else int(def.get("base_rows", sh))
		var s_kind := str(def.get("kind", ""))
		var split_ty: int = (sh - base_rows) if ((s_kind == "landmark" or s_kind == "prop") and base_rows > 0 and sh > base_rows) else 0
		_add_sliced_sprite_to_layers(cx, cell_r0, agx, agy, sw, sh, split_ty, tex, 16, 2.0, known_mat, created)

	# Outdoor town fixtures (32 px/tile -> scale 1.0)
	for fv in fixtures:
		var f: Dictionary = fv
		var fkind := str(f.get("kind", ""))
		var resolved := OutdoorFixtures.resolve_texture(fkind, _force_no_rom)
		var ftex: Texture2D = resolved.get("texture", null)
		var fw: int = int(f.get("w", resolved.get("tile_w", 1)))
		var fh: int = int(f.get("h", resolved.get("tile_h", 1)))
		var fbr: int = mini(fh, maxi(0, int(f.get("base_rows", resolved.get("base_rows", 1)))))
		var split_ty: int = (fh - fbr) if (fbr > 0 and fh > fbr) else 0
		_add_sliced_sprite_to_layers(cx, cell_r0, int(f.get("anchor_gx", 0)), int(f.get("anchor_gy", 0)), fw, fh, split_ty, ftex, 32, 1.0, known_mat, created)

	# Outdoor overworld people (1x2 tiles = 32x64 -> overhang top half + feet base half)
	for pv in people:
		var p: Dictionary = pv
		var pgx := int(p.get("anchor_gx", 0))
		var pgy := int(p.get("anchor_gy", 0))
		var p_foot := Vector2i(pgx, pgy + 1)
		var p_face := str(_person_facing_overrides.get(p_foot, str(p.get("facing", "S"))))
		var ptex := PeopleSprites.resolve_texture(str(p.get("sprite", "")), p_face, str(p.get("role", "talk")), _force_no_rom)
		var before_cnt := created.size()
		_add_sliced_sprite_to_layers(cx, cell_r0, pgx, pgy, 1, 2, 1, ptex, 32, 1.0, known_mat, created)
		if not _person_sprites_by_global.has(p_foot):
			_person_sprites_by_global[p_foot] = []
		for ci in range(before_cnt, created.size()):
			(_person_sprites_by_global[p_foot] as Array).append({"sprite": created[ci], "person": p})

	# BW /a/0/0/7 street Pokemon box icons at full 2x2 tiles (32x32 icon scaled 2x -> 64x64 px,
	# 1 icon px per Emerald px), standing on their tile and depth-sorted with people; omitted under --no-rom
	for kv in street_pokemon:
		var k: Dictionary = kv
		var pkm_tex := AssetDB.pokemon_box_icon(int(k.get("dex", 0)), AssetDB.DEFAULT_CACHE_DIR, _force_no_rom)
		if pkm_tex == null:
			continue
		var agx := int(k.get("anchor_gx", 0))
		var agy := int(k.get("anchor_gy", 0))
		var base_pos := Vector2(
			float((agx - _render_origin_tile.x) * 32 - 16),
			float((agy - _render_origin_tile.y + 1) * 32)
		)
		if _stamp_overhang_layer != null:
			var o_sp := Sprite2D.new()
			o_sp.centered = false
			o_sp.texture = pkm_tex
			o_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			o_sp.region_enabled = true
			o_sp.region_rect = Rect2(0.0, 0.0, 32.0, 16.0)
			o_sp.scale = Vector2(2.0, 2.0)
			o_sp.position = base_pos
			o_sp.offset = Vector2(0.0, -32.0)
			o_sp.material = known_mat
			_stamp_overhang_layer.add_child(o_sp)
			created.append(o_sp)
		var b_sp := Sprite2D.new()
		b_sp.centered = false
		b_sp.texture = pkm_tex
		b_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b_sp.region_enabled = true
		b_sp.region_rect = Rect2(0.0, 16.0, 32.0, 16.0)
		b_sp.scale = Vector2(2.0, 2.0)
		b_sp.position = base_pos
		b_sp.offset = Vector2(0.0, -16.0)
		b_sp.material = known_mat
		_stamp_base_layer.add_child(b_sp)
		created.append(b_sp)

	# Signs standing on paved/path/road/sand tiles draw transparent wood_sign over the pavement
	if not _force_no_rom and tile_buf.size() >= 32 * 32 * 3:
		var sign_res: Variant = null
		var sign_tex: Texture2D = null
		for ty in 32:
			for tx in 32:
				var tidx := (ty * 32 + tx) * 3
				if int(tile_buf[tidx]) == TileSynth2.TILE_SIGN:
					var nb := _paving_under_tile(cx, cy, tx, ty, tile_buf)
					if nb.x >= 0:
						if sign_res == null:
							sign_res = OutdoorFixtures.resolve_texture("em_wood_sign", false)
							sign_tex = (sign_res as Dictionary).get("texture", null)
						if sign_tex != null:
							var ssp := Sprite2D.new()
							ssp.centered = false
							ssp.texture = sign_tex
							ssp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
							ssp.scale = Vector2(1.0, 1.0)
							ssp.position = Vector2(
								float((cx * 32 + tx - _render_origin_tile.x) * 32),
								float((cell_r0 + ty - _render_origin_tile.y) * 32)
							)
							ssp.material = known_mat
							_stamp_base_layer.add_child(ssp)
							created.append(ssp)

	if not created.is_empty():
		_cell_stamp_sprites[cell] = created

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
	var parts := pending_parts()
	return parts.x + parts.y

## The two parts of the pending count: x = visible cells not yet rendered, y = overview chunks whose
## texture still needs an update. The screenshot harness saves only when both are 0 (§4 of Item 25b).
func pending_parts() -> Vector2i:
	if _camera == null:
		return Vector2i.ZERO
	var vp_size := get_viewport_rect().size / _camera.zoom.x
	var cam_pos := _camera.position
	var vis_rect := Rect2(cam_pos - vp_size * 0.5, vp_size).grow(CELL_SIZE_PX)

	var min_cx := int(floor(vis_rect.position.x / CELL_SIZE_PX)) + _render_origin_sc.x
	var max_cx := int(floor((vis_rect.position.x + vis_rect.size.x) / CELL_SIZE_PX)) + _render_origin_sc.x
	var r0 := int(floor(vis_rect.position.y / CELL_SIZE_PX)) + _render_origin_sc.y
	var r1 := int(floor((vis_rect.position.y + vis_rect.size.y) / CELL_SIZE_PX)) + _render_origin_sc.y
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1
	var pending_cells := 0
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			if not _rendered_cells.has(cell):
				pending_cells += 1
	return Vector2i(pending_cells, _dirty_overview_chunks.size())

func count_visible_doors() -> int:
	if _camera == null:
		return 0
	var vp_size: Vector2 = get_viewport_rect().size / _camera.zoom.x
	var cam_pos: Vector2 = _camera.position
	var view_rect := Rect2(cam_pos - vp_size * 0.5, vp_size)

	var min_cx := int(floor(view_rect.position.x / CELL_SIZE_PX)) + _render_origin_sc.x
	var max_cx := int(floor((view_rect.position.x + view_rect.size.x) / CELL_SIZE_PX)) + _render_origin_sc.x
	var r0 := int(floor(view_rect.position.y / CELL_SIZE_PX)) + _render_origin_sc.y
	var r1 := int(floor((view_rect.position.y + view_rect.size.y) / CELL_SIZE_PX)) + _render_origin_sc.y
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

func setup_city_screenshot(path: String, frames: int, place_id: String) -> void:
	_screenshot_mode = true
	disable_walk_mode()
	_screenshot_path = path
	_screenshot_target_frames = frames
	_screenshot_focus = "city"
	_focus_mode = "city"
	_screenshot_zoom = focus_on_city(place_id)
	_pending_blit_cells.clear()
	_requested_cells.clear()
	_load_start_time_usec = Time.get_ticks_usec()
	_load_max_frame_ms = 0.0
	_load_done = false
	_steady_frames_count = 0
	_steady_frame_times.clear()
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func setup_screenshot(path: String, zoom_step: float, frames: int, focus: String = "most_visited") -> void:
	_screenshot_mode = true
	disable_walk_mode()
	_screenshot_path = path
	_screenshot_zoom = zoom_step
	_screenshot_target_frames = frames
	_screenshot_focus = focus
	_focus_mode = focus
	_set_zoom_step(zoom_step)
	if _focus_mode == "area":
		focus_on_area(_screenshot_area_id, zoom_step <= 0.5 + 0.001)
	elif _focus_mode == "most_buildings":
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

	if not _screenshot_saved and not _screenshot_timed_out:
		var parts := pending_parts()
		if parts.x + parts.y > 0:
			# Seconds since the engine started, so the limit counts the focus scans before the capture begins too.
			var waited_sec := float(Time.get_ticks_usec()) / 1000000.0
			if waited_sec >= screenshot_timeout_sec:
				_screenshot_timed_out = true
				_harness_fail("[FAIL] screenshot harness: %d cells and %d chunks still pending after %d s" % [parts.x, parts.y, int(screenshot_timeout_sec)])
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
				var vp_px := get_viewport_rect().size
				var zoomed_tile_x := float(TILE_SIZE_PX) * (_camera.zoom.x if _camera != null else 1.0)
				var zoomed_tile_y := float(TILE_SIZE_PX) * (_camera.zoom.y if _camera != null else 1.0)
				var view_w := floori(vp_px.x / zoomed_tile_x) if zoomed_tile_x > 0.0 else 0
				var view_h := floori(vp_px.y / zoomed_tile_y) if zoomed_tile_y > 0.0 else 0
				print("VIEW_TILES %dx%d" % [view_w, view_h])
				if _focused_city_cells != Vector2i.ZERO:
					print("CITY_CELLS %dx%d" % [_focused_city_cells.x, _focused_city_cells.y])
				if not _focused_area_id.is_empty():
					print("AREA_TILES %dx%d" % [_focused_area_tiles.x, _focused_area_tiles.y])
				var visible_doors := count_visible_doors()
				print("VISIBLE_DOORS %d" % visible_doors)
				_screenshot_saved = true
				_arm_steady_timer()
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

func _arm_steady_timer() -> void:
	if _steady_timer != null or not is_inside_tree():
		return
	_steady_timer = get_tree().create_timer(screenshot_timeout_sec, true, false, true)
	_steady_timer.timeout.connect(_on_steady_frames_timeout)

func _on_steady_frames_timeout() -> void:
	if _steady_frames_count < 120:
		_harness_fail("[FAIL] screenshot harness: %d of 120 steady frames after %d s" % [_steady_frames_count, int(screenshot_timeout_sec)])

func _harness_fail(message: String) -> void:
	printerr(message)
	if harness_fail_handler.is_valid():
		harness_fail_handler.call(message)
	else:
		get_tree().quit(3)


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

func set_active_distortion_field(field_info: Dictionary) -> void:
	_active_distortion_field = field_info.duplicate(true)
	if not bool(field_info.get("active", false)):
		if _distortion_field_rect != null:
			_distortion_field_rect.visible = false
		if _distortion_field_chip != null:
			_distortion_field_chip.visible = false
			_distortion_field_chip.text = ""
		return

	var min_cell: Vector2i = field_info.get("min_cell", Vector2i.ZERO)
	var max_cell: Vector2i = field_info.get("max_cell", Vector2i.ZERO)
	var width_cells: int = maxi(1, max_cell.x - min_cell.x + 1)
	var height_cells: int = maxi(1, max_cell.y - min_cell.y + 1)
	if _distortion_field_rect != null:
		# Screen Y grows south, so northmost cell max_cell.y has top Y = (-max_cell.y - 1) * CELL_SIZE_PX
		_distortion_field_rect.position = Vector2(
			float(min_cell.x - _render_origin_sc.x) * CELL_SIZE_PX,
			float((-max_cell.y - 1) - _render_origin_sc.y) * CELL_SIZE_PX
		)
		_distortion_field_rect.size = Vector2(
			float(width_cells) * CELL_SIZE_PX,
			float(height_cells) * CELL_SIZE_PX
		)
		_distortion_field_rect.visible = true
	if _distortion_field_chip != null:
		_distortion_field_chip.text = str(field_info.get("chip_text", ""))
		_distortion_field_chip.visible = not _distortion_field_chip.text.is_empty()

func get_distortion_field_chip_text() -> String:
	if _distortion_field_chip != null and _distortion_field_chip.visible:
		return _distortion_field_chip.text
	return ""

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
