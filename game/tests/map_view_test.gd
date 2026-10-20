extends Node

# map_view_test.gd — Scene Tree, Attribution, Demo Badge, LRU & Camera Tests (Item 9)
# Contract: docs/implementation_plan_world_generation.md §7–8 & docs/agent_execution_guide.md §6.7

const MapViewScene := preload("res://world/map_view.tscn")

func run_test() -> bool:
	var map_view = MapViewScene.instantiate()
	add_child(map_view)

	# 1. Scene-Tree Assertions (Item 9)
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

	# Badge shows only in demo mode
	map_view.set_demo_mode(false)
	if demo_badge.visible != false:
		push_error("DemoBadge should be hidden when demo mode is false")
		map_view.queue_free()
		return false

	map_view.set_demo_mode(true)
	if demo_badge.visible != true:
		push_error("DemoBadge should be visible when demo mode is true")
		map_view.queue_free()
		return false

	if demo_badge.text != "DEMO MODE":
		push_error("DemoBadge text mismatch: expected 'DEMO MODE', got '%s'" % demo_badge.text)
		map_view.queue_free()
		return false

	# 2. LRU Cache Assertion (Item 9: with 300 cached cells, LRU holds <= 256)
	var cache = map_view.get_lru_cache()
	cache.clear()
	for i in range(300):
		var coord := Vector2i(i, i)
		cache.put(coord, {"buf": PackedByteArray(), "has_data": true})

	if cache.size() > 256:
		push_error("LRU cache exceeded capacity 256: size is %d" % cache.size())
		map_view.queue_free()
		return false

	if cache.size() != 256:
		push_error("LRU cache expected size 256 after 300 insertions, got %d" % cache.size())
		map_view.queue_free()
		return false

	# Oldest keys (0..43) should have been evicted; newest (44..299) should be present
	for i in range(44):
		if cache.has(Vector2i(i, i)):
			push_error("Key (%d, %d) should have been evicted from LRU" % [i, i])
			map_view.queue_free()
			return false

	for i in range(44, 300):
		if not cache.has(Vector2i(i, i)):
			push_error("Key (%d, %d) should be present in LRU" % [i, i])
			map_view.queue_free()
			return false

	# 3. Camera Initial Focus
	map_view.focus_on_cell(4, 5)
	var cam := map_view.get_node_or_null("MapCamera") as Camera2D
	if cam == null:
		push_error("MapCamera node missing")
		map_view.queue_free()
		return false

	var expected_pos := Vector2((4.0 + 0.5) * 256.0, (-5.0 - 0.5) * 256.0)
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

	# 5. Integration check: synthetic map store + revealed cell initial focus + F9 FRAME_P95_MS
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

	map_view._load_map_stores()
	map_view._focus_initial_cell()

	var expected_focus := Vector2((4.0 + 0.5) * 256.0, (-4.0 - 0.5) * 256.0)
	if (cam.position - expected_focus).length() > 0.01:
		push_error("Initial focus cell mismatch: expected %s, got %s" % [expected_focus, cam.position])
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	map_view.get_lru_cache().clear()
	map_view._rendered_cells.clear()
	map_view._frame_times.clear()
	for frame_idx in range(60):
		map_view._process(0.0)
		cam.position += Vector2(4.0, 2.0)

	var f9_ev := InputEventKey.new()
	f9_ev.pressed = true
	f9_ev.keycode = KEY_F9
	map_view._unhandled_input(f9_ev)

	var p95: float = map_view.get_frame_p95_ms()
	if p95 > 16.6:
		push_error("Frame P95 time exceeded target 16.6ms: %.2f ms" % p95)
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		map_view.queue_free()
		return false

	for store in map_view._map_stores:
		store.close()
	map_view._map_stores.clear()

	# 6. F43 Validation: North-up orientation (a, b, c)
	var test_f43_store_path := "user://test/map_data/f43_test.db"
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		if FileAccess.file_exists(test_f43_store_path + suffix):
			DirAccess.remove_absolute(test_f43_store_path + suffix)

	var MapStoreClass := load("res://world/region_import/map_store.gd")
	var f43_store = MapStoreClass.new(test_f43_store_path)
	if not f43_store.open_store(false):
		push_error("Failed to open f43_test.db")
		_cleanup_f43(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	var ring := PackedVector2Array([Vector2(0, 8), Vector2(16, 8), Vector2(16, 16), Vector2(0, 16)])
	f43_store.insert_poly(0, 0, "water", MapStoreClass.pack_rings([ring]))
	f43_store.close()

	map_view._load_map_stores()

	DB.init_db()
	DB.upsert_map_cell(0, 0, 1, 0)
	DB.upsert_map_cell(0, 1, 1, 0)

	map_view.get_lru_cache().clear()
	map_view._rendered_cells.clear()
	map_view._world_tile_map.clear()
	map_view._fog_overlay.clear()

	map_view._render_cell(0, 0)

	var failed_f43 := false
	# (a) Falsifying: WorldTileMap.get_cell_atlas_coords at screen tile (3, -16 + 2) is (5, 0) (water),
	# and at (3, -16 + 13) it is (1, 0) (terrain).
	var top_half_atlas: Vector2i = map_view._world_tile_map.get_cell_atlas_coords(Vector2i(3, -16 + 2))
	var bottom_half_atlas: Vector2i = map_view._world_tile_map.get_cell_atlas_coords(Vector2i(3, -16 + 13))
	if top_half_atlas != Vector2i(5, 0) or bottom_half_atlas != Vector2i(1, 0):
		push_error("F43 (a) falsified: expected top_half=(5, 0) water, bottom_half=(1, 0) terrain; got top_half=%s, bottom_half=%s" % [top_half_atlas, bottom_half_atlas])
		failed_f43 = true

	# (b) Falsifying: with cells (0, 0) and (0, 1) both revealed, every screen row of (0, 1) is smaller (higher on screen) than every row of (0, 0).
	var rows_0: Array[int] = []
	for c in map_view._world_tile_map.get_used_cells():
		if not rows_0.has(c.y):
			rows_0.append(c.y)

	map_view._render_cell(0, 1)
	var rows_1: Array[int] = []
	for c in map_view._world_tile_map.get_used_cells():
		if not rows_0.has(c.y) and not rows_1.has(c.y):
			rows_1.append(c.y)

	var b_failed := false
	for r1 in rows_1:
		for r0 in rows_0:
			if r1 >= r0:
				push_error("F43 (b) falsified: row %d of cell (0, 1) is not smaller than row %d of cell (0, 0)" % [r1, r0])
				b_failed = true
				failed_f43 = true
				break
		if b_failed:
			break

	# (c) focus_on_cell(0, 1).y < focus_on_cell(0, 0).y
	map_view.focus_on_cell(0, 0)
	var cam_pos_0: Vector2 = cam.position
	map_view.focus_on_cell(0, 1)
	var cam_pos_1: Vector2 = cam.position
	if not (cam_pos_1.y < cam_pos_0.y):
		push_error("F43 (c) falsified: focus_on_cell(0, 1).y (%.2f) >= focus_on_cell(0, 0).y (%.2f)" % [cam_pos_1.y, cam_pos_0.y])
		failed_f43 = true

	if failed_f43:
		_cleanup_f43(map_view, test_db_path, test_store_path, test_f43_store_path)
		return false

	_cleanup_f43(map_view, test_db_path, test_store_path, test_f43_store_path)
	print("PASS: map_view_test (Attribution, DemoBadge, LRU 256 cap, UnmappedChip, Camera, FRAME_P95_MS=%.2fms, F43 North-Up verified)" % p95)
	return true

func _cleanup_f43(map_view, test_db_path: String, test_store_path: String, test_f43_store_path: String) -> void:
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
