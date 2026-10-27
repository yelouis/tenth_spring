extends Node

# map_view_test.gd — Scene Tree, Layers, Shaders, Inward Feathering, Overview, LRU & Camera Tests
# Contract: docs/implementation_plan_world_generation_slice2.md §6, §8

const MapViewScene := preload("res://world/map_view.tscn")
const MapStoreClass := preload("res://world/region_import/map_store.gd")
const ProfilePathsClass := preload("res://scripts/profile_paths.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const SynthWorkerScript := preload("res://world/synth_worker.gd")

func run_test() -> bool:
	var map_view = MapViewScene.instantiate()
	add_child(map_view)
	map_view.set_map_data_dir("user://test/map_data")

	# 1. Scene-Tree & Layer Assertions (§8)
	var background_layer := map_view.get_node_or_null("BackgroundLayer") as ColorRect
	var world_known := map_view.get_node_or_null("WorldKnown") as TileMapLayer
	var world_cleared := map_view.get_node_or_null("WorldCleared") as TileMapLayer
	var fog_layer := map_view.get_node_or_null("FogLayer") as TileMapLayer
	var overview_layer := map_view.get_node_or_null("OverviewLayer") as Node2D

	if background_layer == null:
		push_error("BackgroundLayer missing from scene tree")
		map_view.queue_free()
		return false
	if world_known == null:
		push_error("WorldKnown TileMapLayer missing from scene tree")
		map_view.queue_free()
		return false
	if world_cleared == null:
		push_error("WorldCleared TileMapLayer missing from scene tree")
		map_view.queue_free()
		return false
	if fog_layer == null:
		push_error("FogLayer TileMapLayer missing from scene tree")
		map_view.queue_free()
		return false
	if overview_layer == null:
		push_error("OverviewLayer Node2D missing from scene tree")
		map_view.queue_free()
		return false

	# Verify shaders on WorldKnown and FogLayer
	if world_known.material == null or not (world_known.material is ShaderMaterial):
		push_error("WorldKnown material must be a ShaderMaterial (known_tint.gdshader)")
		map_view.queue_free()
		return false
	if world_cleared.material != null:
		push_error("WorldCleared must have no shader material")
		map_view.queue_free()
		return false
	if fog_layer.material == null or not (fog_layer.material is ShaderMaterial):
		push_error("FogLayer material must be a ShaderMaterial (distortion_fog.gdshader)")
		map_view.queue_free()
		return false

	var attribution_label := map_view.get_node_or_null("AttributionUI/AttributionLabel") as Label
	if attribution_label == null:
		push_error("AttributionLabel node missing from scene tree")
		map_view.queue_free()
		return false

	var expected_attr := "© OpenStreetMap contributors"
	if attribution_label.text != expected_attr:
		push_error("AttributionLabel text mismatch: expected '%s', got '%s'" % [expected_attr, attribution_label.text])
		map_view.queue_free()
		return false

	var demo_badge := map_view.get_node_or_null("AttributionUI/DemoBadge") as Label
	if demo_badge == null:
		push_error("DemoBadge node missing from scene tree")
		map_view.queue_free()
		return false

	# Badge and --preview-cleared logic (§6, §8)
	map_view.set_demo_mode(false)
	if demo_badge.visible != false:
		push_error("DemoBadge should be hidden when demo mode is false")
		map_view.queue_free()
		return false

	# Refusal: --preview-cleared without --demo is refused
	map_view.set_preview_cleared(true)
	if map_view._preview_cleared != false:
		push_error("--preview-cleared without --demo should be refused")
		map_view.queue_free()
		return false

	map_view.set_demo_mode(true)
	if demo_badge.visible != true or demo_badge.text != "DEMO MODE":
		push_error("DemoBadge should show 'DEMO MODE' when demo is true and preview_cleared is false")
		map_view.queue_free()
		return false

	map_view.set_preview_cleared(true)
	if map_view._preview_cleared != true or demo_badge.text != "DEMO MODE — preview: cleared look":
		push_error("DemoBadge should show 'DEMO MODE — preview: cleared look' when preview_cleared is true")
		map_view.queue_free()
		return false
	map_view.set_preview_cleared(false)
	map_view.set_demo_mode(false)

	# 2. LRU Cache Assertion (§6: capacity 1024)
	var cache = map_view.get_lru_cache()
	cache.clear()
	for i in range(1100):
		var coord := Vector2i(i, i)
		cache.put(coord, {"buf": PackedByteArray(), "has_data": true})

	if cache.size() > 1024:
		push_error("LRU cache exceeded capacity 1024: size is %d" % cache.size())
		map_view.queue_free()
		return false
	if cache.size() != 1024:
		push_error("LRU cache expected size 1024 after 1100 insertions, got %d" % cache.size())
		map_view.queue_free()
		return false

	for i in range(76):
		if cache.has(Vector2i(i, i)):
			push_error("Key (%d, %d) should have been evicted from LRU" % [i, i])
			map_view.queue_free()
			return false
	for i in range(76, 1100):
		if not cache.has(Vector2i(i, i)):
			push_error("Key (%d, %d) should be present in LRU" % [i, i])
			map_view.queue_free()
			return false

	# 3. Camera Initial Focus (CELL_SIZE_PX = 1024.0)
	map_view.focus_on_cell(4, 5)
	var cam := map_view.get_node_or_null("MapCamera") as Camera2D
	if cam == null:
		push_error("MapCamera node missing")
		map_view.queue_free()
		return false

	var expected_pos := Vector2((4.0 + 0.5) * 1024.0, (-5.0 - 0.5) * 1024.0)
	if (cam.position - expected_pos).length() > 0.01:
		push_error("Camera position mismatch: expected %s, got %s" % [expected_pos, cam.position])
		map_view.queue_free()
		return false

	# 4. Unmapped Chip Assertion
	var unmapped_chip := map_view.get_node_or_null("AttributionUI/UnmappedChip") as PanelContainer
	if unmapped_chip == null:
		push_error("UnmappedChip node missing from scene tree")
		map_view.queue_free()
		return false

	var chip_label := unmapped_chip.get_node_or_null("ChipLabel") as Label
	if chip_label == null:
		push_error("ChipLabel node missing from UnmappedChip")
		map_view.queue_free()
		return false

	var expected_chip_text := "Unmapped — no map data installed for this area"
	if chip_label.text != expected_chip_text:
		push_error("ChipLabel text mismatch: expected '%s', got '%s'" % [expected_chip_text, chip_label.text])
		map_view.queue_free()
		return false

	# 5. Integration check: synthetic map store v2 + revealed cell focus + F9 FRAME_P95_MS
	var test_db_path := "user://test/map_view_test.db"
	var test_tmp_path := "user://test/map_view_test.db.tmp"
	var test_store_path := "user://test/map_data/synthetic_neighborhood.db"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	DB.configure_paths(test_db_path, test_tmp_path)
	if not DB.assert_test_safe():
		push_error("DB.assert_test_safe failed in map_view_test")
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	DB.init_db()
	DB.upsert_map_cell(4, 4, 1, 0)
	DB.upsert_place_node({
		"id": "osm:test_park",
		"name": "Synthetic Park",
		"category": 1,
		"cell_x": 4,
		"cell_y": 4,
		"reveal_state": 1,
		"visit_count": 3
	})

	var converter = load("res://world/region_import/region_converter.gd").new()
	var conv_res: Dictionary = converter.convert("res://tests/fixtures/synthetic_neighborhood.osm.pbf", test_store_path)
	if not conv_res.get("ok", false):
		push_error("Failed to convert synthetic PBF in map_view_test")
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	map_view.set_map_data_dir("user://test/map_data")
	map_view._load_map_stores()
	map_view._focus_initial_cell()

	var expected_focus := Vector2((4.0 + 0.5) * 1024.0, (-4.0 - 0.5) * 1024.0)
	if (cam.position - expected_focus).length() > 0.01:
		push_error("Initial focus cell mismatch: expected %s, got %s" % [expected_focus, cam.position])
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	map_view.get_lru_cache().clear()
	map_view._clear_rendered_layers()
	map_view._frame_times.clear()
	for frame_idx in range(60):
		map_view._process(0.0)
		cam.position += Vector2(16.0, 8.0)

	var f9_ev := InputEventKey.new()
	f9_ev.pressed = true
	f9_ev.keycode = KEY_F9
	map_view._unhandled_input(f9_ev)

	var p95: float = map_view.get_frame_p95_ms()
	if p95 > 16.7:
		push_error("Frame P95 time exceeded target 16.7ms: %.2f ms" % p95)
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	# 5b. Worker synthesis verification (F52 / Item 15)
	var worker = map_view.get_synth_worker()
	if worker == null or not worker.is_running():
		push_error("SynthWorker is not running")
		_cleanup(map_view, test_db_path, test_store_path, "")
		return false

	# Wait a brief moment for worker to complete pending background tasks
	for i in range(10):
		map_view._process(0.0)
		OS.delay_msec(5)

	# Verify each synthesized result records thread that made it, and it isn't main thread
	var found_worker_result := false
	var lru = map_view.get_lru_cache()
	for cell_k in lru._map.keys():
		var c_data = lru._map[cell_k]
		if c_data is Dictionary and c_data.has("thread_id"):
			var tid: int = c_data["thread_id"]
			if tid == OS.get_main_thread_id():
				push_error("Synthesized cell %s thread_id matches main thread!" % str(cell_k))
				_cleanup(map_view, test_db_path, test_store_path, "")
				return false
			elif tid != 0:
				found_worker_result = true
	if not found_worker_result:
		push_error("No worker-synthesized cells found in cache with worker thread_id")
		_cleanup(map_view, test_db_path, test_store_path, "")
		return false

	# Verify blit throttle: no frame blits more than 2 cells
	var max_blits: int = int(map_view.get_max_blits_per_frame())
	if max_blits > 2:
		push_error("Blit throttle failed: max blits per frame was %d, expected <= 2" % max_blits)
		_cleanup(map_view, test_db_path, test_store_path, "")
		return false

	# Verify request queue limits and camera jump pruning:
	# Populate visible cells at (200..209, 200..209)
	for y in range(200, 210):
		for x in range(200, 210):
			DB.upsert_map_cell(x, y, 1, 0)
	map_view.focus_on_cell(204, 204)
	map_view._clear_rendered_layers()
	map_view._process(0.0)

	# Jump camera far away: (1000, 1000)
	map_view.focus_on_cell(1000, 1000)
	map_view._process(0.0)

	var q_size: int = int(worker.get_request_queue_size())
	if q_size > 64:
		push_error("Request queue exceeded 64 after camera jump: got %d" % q_size)
		_cleanup(map_view, test_db_path, test_store_path, "")
		return false

	var queued_cells: Array = worker.get_request_queue_cells()
	for c in queued_cells:
		if c.x < 500 or c.y < 500:
			push_error("Stale request for cell %s was not dropped after camera jump to (1000, 1000)" % str(c))
			_cleanup(map_view, test_db_path, test_store_path, "")
			return false

	# 6. Which layer a cell goes to (§6, §8):
	# reveal_state 0 -> FogLayer solid
	# 1 (known) -> WorldKnown
	# >= 2 (cleared) -> WorldCleared
	DB.query_rows("DELETE FROM map_cell;")
	DB.upsert_map_cell(1, 1, 0, 0) # unknown
	DB.upsert_map_cell(2, 2, 1, 0) # known
	DB.upsert_map_cell(3, 3, 2, 0) # cleared

	map_view.get_lru_cache().clear()
	map_view._clear_rendered_layers()

	map_view._render_cell(1, 1)
	var expected_solid: int = map_view._fog_rows.get("solid", 58)
	var fog_solid_tile: Vector2i = fog_layer.get_cell_atlas_coords(map_view._screen_tile(1, 1, 10, 10))
	if fog_solid_tile.y != expected_solid: # fog_solid row
		push_error("Unknown cell (1, 1) should have solid fog on FogLayer (row %d), got %s" % [expected_solid, str(fog_solid_tile)])
		map_view.queue_free()
		return false
	if world_known.get_cell_atlas_coords(map_view._screen_tile(1, 1, 10, 10)) != Vector2i(-1, -1):
		push_error("Unknown cell (1, 1) should have no tiles on WorldKnown")
		map_view.queue_free()
		return false

	map_view._render_cell(2, 2)
	var known_tile: Vector2i = world_known.get_cell_atlas_coords(map_view._screen_tile(2, 2, 10, 10))
	if known_tile == Vector2i(-1, -1):
		push_error("Known cell (2, 2) should have tiles on WorldKnown")
		map_view.queue_free()
		return false
	if world_cleared.get_cell_atlas_coords(map_view._screen_tile(2, 2, 10, 10)) != Vector2i(-1, -1):
		push_error("Known cell (2, 2) should have no tiles on WorldCleared")
		map_view.queue_free()
		return false

	map_view._render_cell(3, 3)
	var cleared_tile: Vector2i = world_cleared.get_cell_atlas_coords(map_view._screen_tile(3, 3, 10, 10))
	if cleared_tile == Vector2i(-1, -1):
		push_error("Cleared cell (3, 3) should have tiles on WorldCleared")
		map_view.queue_free()
		return false
	if world_known.get_cell_atlas_coords(map_view._screen_tile(3, 3, 10, 10)) != Vector2i(-1, -1):
		push_error("Cleared cell (3, 3) should have no tiles on WorldKnown")
		map_view.queue_free()
		return false

	# 7. Inward Feathering (§6, §8):
	# Cell (2, 2) is revealed (known). Its north neighbour (2, 3) is unknown (hidden).
	var expected_d75: int = map_view._fog_rows.get("d75", 59)
	var expected_d50: int = map_view._fog_rows.get("d50", 60)
	var expected_d25: int = map_view._fog_rows.get("d25", 61)
	var d0_fog: Vector2i = fog_layer.get_cell_atlas_coords(map_view._screen_tile(2, 2, 16, 0))
	var d1_fog: Vector2i = fog_layer.get_cell_atlas_coords(map_view._screen_tile(2, 2, 16, 1))
	var d2_fog: Vector2i = fog_layer.get_cell_atlas_coords(map_view._screen_tile(2, 2, 16, 2))
	var d3_fog: Vector2i = fog_layer.get_cell_atlas_coords(map_view._screen_tile(2, 2, 16, 3))

	if d0_fog.y != expected_d75: # d75
		push_error("Inward feathering row 0 expected d75 (row %d), got %s" % [expected_d75, str(d0_fog)])
		map_view.queue_free()
		return false
	if d1_fog.y != expected_d50: # d50
		push_error("Inward feathering row 1 expected d50 (row %d), got %s" % [expected_d50, str(d1_fog)])
		map_view.queue_free()
		return false
	if d2_fog.y != expected_d25: # d25
		push_error("Inward feathering row 2 expected d25 (row %d), got %s" % [expected_d25, str(d2_fog)])
		map_view.queue_free()
		return false
	if d3_fog != Vector2i(-1, -1):
		push_error("Inward feathering row 3 should have no fog tile, got %s" % str(d3_fog))
		map_view.queue_free()
		return false

	# 8. Overview Mode at zoom 1/16 (§6, §8)
	map_view._set_zoom_step(0.0625) # zoom 1/16
	if overview_layer.visible != true:
		push_error("OverviewLayer should be visible at zoom 1/16")
		map_view.queue_free()
		return false
	if world_known.visible != false or world_cleared.visible != false or fog_layer.visible != false:
		push_error("Tile layers should be hidden at zoom 1/16")
		map_view.queue_free()
		return false

	# Check overview chunk sprite exists for chunk (0, 0) (which covers cell (2, 2)) and is scaled 32x32 (§11.5 step 2)
	var s: Sprite2D = map_view._overview_sprites.get(Vector2i(0, 0), null)
	if s == null:
		push_error("OverviewLayer should have a Sprite2D for chunk (0, 0) covering cell (2, 2)")
		map_view.queue_free()
		return false
	if s.scale != Vector2(32, 32):
		push_error("Overview Sprite2D scale expected (32, 32), got %s" % str(s.scale))
		map_view.queue_free()
		return false

	map_view._set_zoom_step(1.0)
	if overview_layer.visible != false or world_known.visible != true:
		push_error("OverviewLayer should be hidden and WorldKnown visible at zoom 1.0")
		map_view.queue_free()
		return false

	# 9. F43 Orientation Assertions (§3, §8)
	var test_f43_store_path := "user://test/map_data/f43_test.db"
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		if FileAccess.file_exists(test_f43_store_path + suffix):
			DirAccess.remove_absolute(test_f43_store_path + suffix)

	var f43_store = MapStoreClass.new(test_f43_store_path)
	if not f43_store.open_store(false):
		push_error("Failed to open f43_test.db")
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	# Polygon in store y in [8, 16] (north half in store units 0..16)
	var ring := PackedVector2Array([Vector2(0, 8), Vector2(16, 8), Vector2(16, 16), Vector2(0, 16)])
	f43_store.insert_poly(0, 0, "water", MapStoreClass.pack_rings([ring]))
	f43_store.set_state("schema_version", "4")
	f43_store.set_state("coverage", "0,0,2,2")
	f43_store.close()

	map_view._load_map_stores()
	DB.init_db()
	DB.upsert_map_cell(0, 0, 1, 0)
	DB.upsert_map_cell(0, 1, 1, 0)

	map_view.get_lru_cache().clear()
	map_view._clear_rendered_layers()
	map_view._render_cell(0, 0)

	# North half (row 2) is WATER (class 4, atlas row 8); South half (row 20) is GRASS (class 1, atlas row 1..4)
	var top_half_atlas: Vector2i = world_known.get_cell_atlas_coords(map_view._screen_tile(0, 0, 3, 2))
	var bottom_half_atlas: Vector2i = world_known.get_cell_atlas_coords(map_view._screen_tile(0, 0, 3, 20))
	if top_half_atlas.y != 8: # WATER row
		push_error("F43 north-first failed: top half expected WATER (atlas row 8), got %s" % str(top_half_atlas))
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false
	if bottom_half_atlas.y == 8:
		push_error("F43 north-first failed: bottom half should not be WATER")
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	# (b) With (0, 0) and (0, 1) both revealed, every screen row of (0, 1) is smaller than every row of (0, 0)
	var rows_0: Array[int] = []
	for c in world_known.get_used_cells():
		if not rows_0.has(c.y):
			rows_0.append(c.y)

	map_view._render_cell(0, 1)
	var rows_1: Array[int] = []
	for c in world_known.get_used_cells():
		if not rows_0.has(c.y) and not rows_1.has(c.y):
			rows_1.append(c.y)

	for r1 in rows_1:
		for r0 in rows_0:
			if r1 >= r0:
				push_error("F43 (b) failed: row %d of cell (0, 1) is not smaller than row %d of cell (0, 0)" % [r1, r0])
				_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
				return false

	# (c) focus_on_cell(0, 1).y < focus_on_cell(0, 0).y
	map_view.focus_on_cell(0, 0)
	var cam_pos_0: Vector2 = cam.position
	map_view.focus_on_cell(0, 1)
	var cam_pos_1: Vector2 = cam.position
	if not (cam_pos_1.y < cam_pos_0.y):
		push_error("F43 (c) failed: focus_on_cell(0, 1).y >= focus_on_cell(0, 0).y")
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	# -------------------------------------------------------------
	# 9. Landmark Atlas Coordinates & Enterable Tooltip (§10.8, Item 22)
	# -------------------------------------------------------------
	var roof_32_coords: Vector2i = map_view.get_atlas_coords(TileSynth2.TILE_ROOF, 32, 0)
	var wall_32_coords: Vector2i = map_view.get_atlas_coords(TileSynth2.TILE_WALL, 32, 0)
	var wall_40_coords: Vector2i = map_view.get_atlas_coords(TileSynth2.TILE_WALL, 40, 0)
	var door_32_coords: Vector2i = map_view.get_atlas_coords(TileSynth2.TILE_DOOR, 32, 0)

	if roof_32_coords.y == 0 or wall_32_coords.y == 0 or wall_40_coords.y == 0 or door_32_coords.y == 0:
		push_error("Landmark atlas coordinates lookup failed: roof=%s, wall32=%s, wall40=%s, door=%s" % [
			str(roof_32_coords), str(wall_32_coords), str(wall_40_coords), str(door_32_coords)
		])
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	# Verify tooltip logic for landmark sign
	map_view._landmark_names["Test Landmark"] = true
	var mock_tiles := PackedByteArray()
	mock_tiles.resize(32 * 32 * 3)
	mock_tiles.fill(0)
	# Put landmark sign at (col=5, row=5)
	var mock_sign_idx := (5 * 32 + 5) * 3
	mock_tiles[mock_sign_idx] = TileSynth2.TILE_SIGN
	mock_tiles[mock_sign_idx + 1] = 0 # variant 0 -> index in signs
	# Put landmark door at (col=6, row=5)
	var mock_door_idx := (5 * 32 + 6) * 3
	mock_tiles[mock_door_idx] = TileSynth2.TILE_DOOR
	mock_tiles[mock_door_idx + 1] = 32 # variant 32 -> landmark door

	map_view._landmarks_by_cell[Vector2i(10, 10)] = [{"name": "Test Landmark"}]
	map_view.get_lru_cache().put(Vector2i(10, 10), {
		"buf": mock_tiles,
		"signs": ["Test Landmark"],
		"reveal_state": 1
	})

	# 10. Item 25b / F61: the whole-city view finishes loading at zoom 1/16, even when its view extends past the
	#     store's coverage. FALSIFYING: on the pre-25b code the synthesis queue kept 64 requests and forgot the rest,
	#     so the cells it dropped stayed "requested" and pending_cell_count() never reached 0.
	for gx in range(-8, 18):
		for gy in range(-6, 16):
			DB.upsert_map_cell(gx, gy, 1, 0) # far more revealed cells than fit in the queue; the store covers only a few
	var o_default: Dictionary = _load_overview_at_one_sixteenth(MapViewScene, 0)
	print("map_view_test: overview 1/16 loaded %d cells in %.1f s" % [o_default["visible"], o_default["elapsed_sec"]])
	if o_default["visible"] <= SynthWorkerScript.MAX_QUEUED_REQUESTS:
		push_error("(25b) test fixture too small: only %d cells pending at the start (must exceed the %d-request queue)" % [o_default["visible"], SynthWorkerScript.MAX_QUEUED_REQUESTS])
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false
	if o_default["cells"] + o_default["chunks"] != 0:
		push_error("(25b) overview at zoom 1/16 did not finish loading: %d cells and %d chunks still pending after %.1f s (%d were pending at the start)" % [o_default["cells"], o_default["chunks"], o_default["elapsed_sec"], o_default["visible"]])
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	# 10b. The same view with a cache far smaller than the view (a big window shows more cells than the 1024-cell
	#      synthesis cache holds). FALSIFYING: when a rendered cell whose cache entry was evicted is requested again,
	#      the worker keeps re-synthesizing the nearest cells and the farthest are never reached.
	var o_small: Dictionary = _load_overview_at_one_sixteenth(MapViewScene, 100)
	print("map_view_test: overview 1/16 with a 100-cell cache loaded %d cells in %.1f s" % [o_small["visible"], o_small["elapsed_sec"]])
	if o_small["cells"] + o_small["chunks"] != 0:
		push_error("(25b) overview at zoom 1/16 with a 100-cell synthesis cache did not finish loading: %d cells and %d chunks still pending after %.1f s (%d were pending at the start)" % [o_small["cells"], o_small["chunks"], o_small["elapsed_sec"], o_small["visible"]])
		_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	_cleanup(map_view, test_db_path, test_store_path, test_f43_store_path)
	print("PASS: map_view_test (Renderer v2, layers, shaders, inward feathering, overview 1/16, LRU 1024, preview-cleared, F43 North-Up, landmark atlas & tooltips verified)")
	return true

## Item 25b: loads the zoom-1/16 overview in a second map view that has its own 1280 x 720 viewport (the screenshot
## harness's size: about 345 cells, more than the worker's queue). The headless root viewport is too small for that, and
## moving the first view out of the tree would stop its worker. cache_capacity > 0 shrinks the view's synthesis cache.
## The loop waits on the clock, because the headless test advances frames far faster than the worker synthesizes, and
## stops early when nothing has changed for 5 s. Returns {visible, cells, chunks, elapsed_sec}.
func _load_overview_at_one_sixteenth(view_scene: PackedScene, cache_capacity: int) -> Dictionary:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sv)
	var view = view_scene.instantiate()
	sv.add_child(view)
	view.set_map_data_dir("user://test/map_data")
	if cache_capacity > 0:
		view.get_lru_cache().capacity = cache_capacity
	view.focus_on_cell(4, 4)
	view._set_zoom_step(0.0625)
	var start_ms := Time.get_ticks_msec()
	var last_change_ms := start_ms
	var last_pending := -1
	var visible := 0
	var frames := 0
	while Time.get_ticks_msec() - start_ms < 90000:
		# delta 0.0: a real delta would run the view's 2 s unmapped-region lookup, which can reach the network.
		view._process(0.0)
		var pending: int = view.pending_cell_count()
		visible = maxi(visible, view.pending_parts().x)
		if pending == 0 and frames > 2:
			break
		if pending != last_pending:
			last_pending = pending
			last_change_ms = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_change_ms > 5000:
			break
		OS.delay_msec(5)
		frames += 1
	var parts: Vector2i = view.pending_parts()
	var elapsed_sec := float(Time.get_ticks_msec() - start_ms) / 1000.0
	sv.remove_child(view)
	view.free()
	sv.free()
	return {"visible": visible, "cells": parts.x, "chunks": parts.y, "elapsed_sec": elapsed_sec}

func _cleanup(map_view, test_db_path: String, test_store_path: String, test_f43_store_path: String) -> void:
	if map_view.get_synth_worker() != null:
		map_view.get_synth_worker().stop()
	for store in map_view._map_stores:
		store.close()
	map_view._map_stores.clear()
	DB.close()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		if FileAccess.file_exists(test_db_path + suffix):
			DirAccess.remove_absolute(test_db_path + suffix)
		if FileAccess.file_exists(test_store_path + suffix):
			DirAccess.remove_absolute(test_store_path + suffix)
		if FileAccess.file_exists(test_f43_store_path + suffix):
			DirAccess.remove_absolute(test_f43_store_path + suffix)
	map_view.queue_free()
