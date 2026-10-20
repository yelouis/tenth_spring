extends Node2D

# map_view.gd — Map View Scene Controller (Plan §7–8, Item 9)
# Contract: docs/implementation_plan_world_generation.md §7–8 & docs/agent_execution_guide.md §6.7

const TileSynth := preload("res://world/tile_synth/tile_synth.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const MapFetcher := preload("res://world/region_import/map_fetcher.gd")
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
var _chip_label: Label = null
var _update_map_button: Button = null
var _download_dialog: ConfirmationDialog = null
var _install_panel: PanelContainer = null
var _install_label: Label = null
var _cancel_button: Button = null

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

	set_map_fetcher(_map_fetcher)
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
		_camera.position = Vector2((cx + 0.5) * CELL_SIZE_PX, (-cy - 0.5) * CELL_SIZE_PX)

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_handle_keyboard_pan(delta)
	_update_frustum_culling()
	_lookup_mutex.lock()
	var lookup_res: Variant = _pending_lookup_result
	_pending_lookup_result = null
	_lookup_mutex.unlock()
	if lookup_res != null and lookup_res is Dictionary:
		_on_region_lookup_done(lookup_res)
	_poll_unmapped_cells(delta)
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var sample_ms := delta * 1000.0 if delta > 0.0 else elapsed_ms
	_frame_times.append(sample_ms)
	if _frame_times.size() > 120:
		_frame_times.pop_front()

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
	var top := vis_rect.position.y
	var bottom := vis_rect.position.y + vis_rect.size.y
	var r0 := int(floor(top / CELL_SIZE_PX))
	var r1 := int(floor(bottom / CELL_SIZE_PX))
	var min_cy := -r1 - 1
	var max_cy := -r0 - 1

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

func _screen_tile(cx: int, cy: int, tx: int, ty: int) -> Vector2i:
	return Vector2i(cx * 16 + tx, (-cy - 1) * 16 + (15 - ty))

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
	for ty in 16:
		for tx in 16:
			var tid: int = tile_buf[ty * 16 + tx]
			_world_tile_map.set_cell(_screen_tile(cx, cy, tx, ty), 0, Vector2i(tid, 0))

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
			_fog_overlay.set_cell(_screen_tile(cx, cy, tx, ty), 0, Vector2i(fog_tile, 0))

	var is_unmapped := (reveal_state > 0 and not has_map_data)
	if is_unmapped:
		_unmapped_revealed_cells[cell] = true
	else:
		_unmapped_revealed_cells.erase(cell)

	return is_unmapped

func _unrender_cell(cx: int, cy: int) -> void:
	_unmapped_revealed_cells.erase(Vector2i(cx, cy))
	for ty in 16:
		for tx in 16:
			var coord := _screen_tile(cx, cy, tx, ty)
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
		lru_cache.clear()
		_rendered_cells.clear()
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
		lru_cache.clear()
		_rendered_cells.clear()
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
		lru_cache.clear()
		_rendered_cells.clear()
		_update_frustum_culling()
	return res

func _exit_tree() -> void:
	if _lookup_thread != null and _lookup_thread.is_alive():
		_lookup_thread.wait_to_finish()
		_lookup_thread = null
	for store in _map_stores:
		store.close()
	_map_stores.clear()
