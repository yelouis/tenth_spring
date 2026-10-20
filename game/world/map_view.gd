extends Node2D

# map_view.gd — Map View Scene Controller (Plan §7–8, Item 9)
# Contract: docs/implementation_plan_world_generation.md §7–8 & docs/agent_execution_guide.md §6.7

const TileSynth := preload("res://world/tile_synth/tile_synth.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")

const CELL_SIZE_PX := 256.0
const TILE_SIZE_PX := 16
const PAN_SPEED := 400.0
const MAX_CACHED_CELLS := 256

# LRU Cache for decoded/synthesized cell buffers (Plan §9.2)
class LruCache:
	var capacity: int = MAX_CACHED_CELLS
	var _map: Dictionary = {}
	var _order: Array[Vector2i] = []

	func _init(cap: int = MAX_CACHED_CELLS) -> void:
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

var lru_cache := LruCache.new(MAX_CACHED_CELLS)
var _rendered_cells: Dictionary = {} # Vector2i -> bool

var _camera: Camera2D = null
var _world_tile_map: TileMapLayer = null
var _fog_overlay: TileMapLayer = null
var _demo_badge: Label = null
var _attribution_label: Label = null
var _unmapped_chip: PanelContainer = null

var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _current_zoom_step: int = 1 # 1, 2, 3

var _frame_times: Array[float] = []
var _is_demo: bool = false
var _map_stores: Array[MapStore] = []

func _ready() -> void:
	_camera = get_node_or_null("MapCamera") as Camera2D
	_world_tile_map = get_node_or_null("WorldTileMap") as TileMapLayer
	_fog_overlay = get_node_or_null("FogOverlayLayer") as TileMapLayer
	_demo_badge = get_node_or_null("AttributionUI/DemoBadge") as Label
	_attribution_label = get_node_or_null("AttributionUI/AttributionLabel") as Label
	_unmapped_chip = get_node_or_null("AttributionUI/UnmappedChip") as PanelContainer

	_check_demo_mode()
	_init_tile_sets()
	_load_map_stores()
	_focus_initial_cell()

func _check_demo_mode() -> void:
	var profile = ProfilePaths.resolve_from_cmdline()
	_is_demo = profile.get("is_demo", false)
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			_is_demo = true
	for arg in OS.get_cmdline_args():
		if arg == "--demo":
			_is_demo = true

	if _demo_badge != null:
		_demo_badge.visible = _is_demo

func set_demo_mode(enabled: bool) -> void:
	_is_demo = enabled
	if _demo_badge != null:
		_demo_badge.visible = enabled

func _init_tile_sets() -> void:
	# 1. World TileSet: 6 palette tiles + 1 unmapped tile
	var world_ts := TileSet.new()
	world_ts.tile_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)

	var world_img := Image.create(TILE_SIZE_PX * 7, TILE_SIZE_PX, false, Image.FORMAT_RGBA8)
	var world_colors = [
		TileSynth.PALETTE[TileSynth.TILE_VOID],     # 0: Void #0d1119
		TileSynth.PALETTE[TileSynth.TILE_TERRAIN],  # 1: Terrain #475e46
		TileSynth.PALETTE[TileSynth.TILE_ROAD],     # 2: Road #5a5d64
		TileSynth.PALETTE[TileSynth.TILE_BUILDING], # 3: Building #2e3238
		TileSynth.PALETTE[TileSynth.TILE_PARK],     # 4: Park #3e7d44
		TileSynth.PALETTE[TileSynth.TILE_WATER],    # 5: Water #1f385c
		Color("#2a3242")                           # 6: Unmapped grey
	]
	for i in 7:
		world_img.fill_rect(Rect2i(i * TILE_SIZE_PX, 0, TILE_SIZE_PX, TILE_SIZE_PX), world_colors[i])
	var world_tex := ImageTexture.create_from_image(world_img)

	var world_source := TileSetAtlasSource.new()
	world_source.texture = world_tex
	world_source.texture_region_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)
	for i in 7:
		world_source.create_tile(Vector2i(i, 0))
	world_ts.add_source(world_source, 0)
	if _world_tile_map != null:
		_world_tile_map.tile_set = world_ts

	# 2. Fog TileSet:
	# Fog 0: Solid #0d1119 (unknown)
	# Fog 1: Dark overlay #141923 at 0.55 opacity (known)
	# Fog 2: Fully transparent (familiar/mastered)
	var fog_ts := TileSet.new()
	fog_ts.tile_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)

	var fog_img := Image.create(TILE_SIZE_PX * 3, TILE_SIZE_PX, false, Image.FORMAT_RGBA8)
	var fog_colors = [
		Color("#0d1119"),                          # 0: Unknown fog (solid)
		Color(0.078, 0.098, 0.137, 0.55),          # 1: Known fog (dark overlay #141923 at 0.55 opacity)
		Color(0.0, 0.0, 0.0, 0.0)                  # 2: Cleared fog (transparent)
	]
	for i in 3:
		fog_img.fill_rect(Rect2i(i * TILE_SIZE_PX, 0, TILE_SIZE_PX, TILE_SIZE_PX), fog_colors[i])
	var fog_tex := ImageTexture.create_from_image(fog_img)

	var fog_source := TileSetAtlasSource.new()
	fog_source.texture = fog_tex
	fog_source.texture_region_size = Vector2i(TILE_SIZE_PX, TILE_SIZE_PX)
	for i in 3:
		fog_source.create_tile(Vector2i(i, 0))
	fog_ts.add_source(fog_source, 0)
	if _fog_overlay != null:
		_fog_overlay.tile_set = fog_ts

func _load_map_stores() -> void:
	for s in _map_stores:
		s.close()
	_map_stores.clear()
	var search_dirs = [
		"user://map_data/",
		"user://test/map_data/"
	]
	for d in search_dirs:
		if DirAccess.dir_exists_absolute(d):
			var files = DirAccess.get_files_at(d)
			for f in files:
				if f.ends_with(".db") and not f.ends_with(".tmp.db"):
					var p: String = d + f
					var store := MapStore.new(p)
					if store.open_store(true):
						_map_stores.append(store)

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
		_camera.position = Vector2(float(cx) * CELL_SIZE_PX + CELL_SIZE_PX * 0.5, float(cy) * CELL_SIZE_PX + CELL_SIZE_PX * 0.5)

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_handle_keyboard_pan(delta)
	_update_frustum_culling()
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var sample_ms := delta * 1000.0 if delta > 0.0 else elapsed_ms
	_frame_times.append(sample_ms)
	if _frame_times.size() > 120:
		_frame_times.pop_front()

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
			_set_zoom_step(_current_zoom_step + 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom_step(_current_zoom_step - 1)

	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		if _camera != null:
			_camera.position -= mm.relative / _camera.zoom.x

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_F9:
			print_p95_frame_time()

func _set_zoom_step(step: int) -> void:
	_current_zoom_step = clampi(step, 1, 3)
	if _camera != null:
		_camera.zoom = Vector2(_current_zoom_step, _current_zoom_step)

func _update_frustum_culling() -> void:
	if _camera == null or _world_tile_map == null or _fog_overlay == null:
		return

	var vp_size := get_viewport_rect().size / _camera.zoom.x
	var cam_pos := _camera.position
	var vis_rect := Rect2(cam_pos - vp_size * 0.5, vp_size).grow(CELL_SIZE_PX)

	var min_cx := int(floor(vis_rect.position.x / CELL_SIZE_PX))
	var max_cx := int(floor((vis_rect.position.x + vis_rect.size.x) / CELL_SIZE_PX))
	var min_cy := int(floor(vis_rect.position.y / CELL_SIZE_PX))
	var max_cy := int(floor((vis_rect.position.y + vis_rect.size.y) / CELL_SIZE_PX))

	var visible_cell_set: Dictionary = {}
	var has_unmapped_revealed_cell := false

	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell := Vector2i(cx, cy)
			visible_cell_set[cell] = true

			if not _rendered_cells.has(cell):
				var is_unmapped := _render_cell(cx, cy)
				if is_unmapped:
					has_unmapped_revealed_cell = true
				_rendered_cells[cell] = true

	# Unrender cells that scrolled out of view (Plan §7.3)
	var to_remove: Array[Vector2i] = []
	for cell in _rendered_cells.keys():
		if not visible_cell_set.has(cell):
			_unrender_cell(cell.x, cell.y)
			to_remove.append(cell)
	for cell in to_remove:
		_rendered_cells.erase(cell)

	if _unmapped_chip != null:
		_unmapped_chip.visible = has_unmapped_revealed_cell

func _render_cell(cx: int, cy: int) -> bool:
	var cell := Vector2i(cx, cy)

	# 1. Determine reveal state from DB
	var reveal_state := 0 # unknown
	var db = _get_db()
	if db != null and db.is_open():
		var rows: Array = db.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [cx, cy])
		if not rows.is_empty():
			reveal_state = int(rows[0].get("reveal_state", 0))

	# 2. Get or synthesize tile buffer
	var tile_buf: PackedByteArray = PackedByteArray()
	var has_map_data := false

	if lru_cache.has(cell):
		var item = lru_cache.get_item(cell)
		if item is Dictionary:
			tile_buf = item.get("buf", PackedByteArray())
			has_map_data = item.get("has_data", false)
	else:
		# Search installed map stores
		var features := {"polys": [], "lines": [], "places": []}
		for store in _map_stores:
			var polys = store.get_features_poly(cx, cy)
			var lines = store.get_features_line(cx, cy)
			var places = store.get_place_nodes(cx, cy)
			if not polys.is_empty() or not lines.is_empty() or not places.is_empty():
				features["polys"].append_array(polys)
				features["lines"].append_array(lines)
				features["places"].append_array(places)
				has_map_data = true

		if has_map_data:
			tile_buf = TileSynth.synthesize_cell(cx, cy, features, 0)
		else:
			# Unmapped fill: 16x16 of tile 6
			tile_buf.resize(256)
			tile_buf.fill(6) # Tile 6: Unmapped grey

		lru_cache.put(cell, {"buf": tile_buf, "has_data": has_map_data})

	# 3. Blit to WorldTileMap
	var base_tx := cx * 16
	var base_ty := cy * 16
	for ty in 16:
		for tx in 16:
			var tid: int = tile_buf[ty * 16 + tx]
			_world_tile_map.set_cell(Vector2i(base_tx + tx, base_ty + ty), 0, Vector2i(tid, 0))

	# 4. Blit to FogOverlayLayer
	# Fog state: 0 (unknown), 1 (known), 2 (cleared)
	var fog_tile := 0
	if reveal_state == 0:
		fog_tile = 0 # Unknown solid
	elif reveal_state == 1:
		fog_tile = 1 # Known dark overlay
	else:
		fog_tile = 2 # Cleared transparent

	for ty in 16:
		for tx in 16:
			_fog_overlay.set_cell(Vector2i(base_tx + tx, base_ty + ty), 0, Vector2i(fog_tile, 0))

	return (reveal_state > 0 and not has_map_data)

func _unrender_cell(cx: int, cy: int) -> void:
	var base_tx := cx * 16
	var base_ty := cy * 16
	for ty in 16:
		for tx in 16:
			var coord := Vector2i(base_tx + tx, base_ty + ty)
			_world_tile_map.erase_cell(coord)
			_fog_overlay.erase_cell(coord)

func get_lru_cache() -> LruCache:
	return lru_cache

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

func _exit_tree() -> void:
	for store in _map_stores:
		store.close()
	_map_stores.clear()
