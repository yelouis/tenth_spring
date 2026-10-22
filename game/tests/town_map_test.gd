extends Node

# town_map_test.gd — Town Map, Home Hub & Return Home Verification (Item 20)
# Contract: docs/implementation_plan_famous_places.md §5, docs/agent_execution_guide.md §7.4

const Grid := preload("res://world/grid.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")

const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const FIXTURE_CONFIG: String = "res://tests/fixtures/famous_places_fixture.json"

const TEST_DB_PATH: String = "user://test/tenth_spring_town_map_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_town_map_test.db.tmp"
const TEST_CITY_DB: String = "user://test/map_data/fixture_city_town_map.db"
const TEST_SITE_DB: String = "user://test/map_data/fixture_park_town_map.db"

func _cleanup_path(path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		var p: String = path + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _cleanup() -> void:
	_cleanup_path(TEST_DB_PATH)
	_cleanup_path(TEST_TMP_PATH)
	_cleanup_path(TEST_CITY_DB)
	_cleanup_path(TEST_SITE_DB)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup()

	# Convert fixture stores for testing
	var conv := RegionConverter.new()
	var res_city := conv.convert(FIXTURE_PBF, TEST_CITY_DB, null, null, "city:fixture-city", FIXTURE_CONFIG)
	if not res_city.get("ok", false):
		push_error("FAIL: Failed to convert fixture city: %s" % res_city.get("error", "unknown"))
		_cleanup()
		return false

	var res_site := conv.convert(FIXTURE_PBF, TEST_SITE_DB, null, null, "site:fixture-park", FIXTURE_CONFIG)
	if not res_site.get("ok", false):
		push_error("FAIL: Failed to convert fixture site: %s" % res_site.get("error", "unknown"))
		_cleanup()
		return false

	var city_store := MapStore.new(TEST_CITY_DB)
	city_store.open_store(false)
	var site_store := MapStore.new(TEST_SITE_DB)
	site_store.open_store(false)

	var stores := {
		"city:fixture-city": city_store,
		"site:fixture-park": site_store
	}

	DB.init_db()

	# -------------------------------------------------------------
	# 1. Town Map scene: Locked markers cannot be opened (falsifier)
	# -------------------------------------------------------------
	var town_map_scene = load("res://scenes/town_map.tscn")
	if town_map_scene == null:
		push_error("FAIL: Could not load town_map.tscn")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var tm = town_map_scene.instantiate()
	add_child(tm)
	tm.load_places_from_config(FIXTURE_CONFIG)

	if tm.is_place_lit("city:fixture-city"):
		push_error("FAIL (falsifier): city:fixture-city should be locked initially")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var locked_btn = tm.get_marker("city:fixture-city")
	if locked_btn == null or not locked_btn.disabled:
		push_error("FAIL (falsifier): Locked marker button should be disabled")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var select_locked_ok: bool = tm.select_place("city:fixture-city")
	if select_locked_ok:
		push_error("FAIL (falsifier): Opening locked marker succeeded; must fail")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# 2. Lit marker: Unlocked place can be opened & emits waypost coords
	# -------------------------------------------------------------
	var now := int(Time.get_unix_time_from_system())
	DB.insert_distort_entry("city:fixture-city", now, "visited")
	tm.refresh_markers()

	if not tm.is_place_lit("city:fixture-city"):
		push_error("FAIL: city:fixture-city should be lit after adding to distort_list")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var lit_btn = tm.get_marker("city:fixture-city")
	if lit_btn == null or lit_btn.disabled:
		push_error("FAIL: Lit marker button should be enabled")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var selection := {"id": "", "lat": 0.0, "lon": 0.0}
	tm.place_selected.connect(func(pid: String, lat: float, lon: float):
		selection["id"] = pid
		selection["lat"] = lat
		selection["lon"] = lon
	)

	var select_lit_ok: bool = tm.select_place("city:fixture-city")
	if not select_lit_ok or selection["id"] != "city:fixture-city":
		push_error("FAIL: Selecting lit place failed: ok=%s, id=%s" % [str(select_lit_ok), selection["id"]])
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if not is_equal_approx(selection["lat"], 0.0103486) or not is_equal_approx(selection["lon"], 0.0080489):
		push_error("FAIL: Waypost coordinates mismatch on lit place selection: (%f, %f)" % [selection["lat"], selection["lon"]])
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# 3. Ringed marker: Fully unlocked city has ring; site does not
	# -------------------------------------------------------------
	if tm.is_place_ringed("city:fixture-city"):
		push_error("FAIL: city:fixture-city should not be ringed before area_reveal city entry")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	DB.insert_area_reveal("city:fixture-city", "city", now)
	tm.refresh_markers()

	if not tm.is_place_ringed("city:fixture-city"):
		push_error("FAIL: city:fixture-city should be ringed after area_reveal city entry")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Site on distort_list and area_reveal (sites do not get rings)
	DB.insert_distort_entry("site:fixture-park", now, "visited")
	DB.insert_area_reveal("site:fixture-park", "site", now)
	tm.refresh_markers()

	if not tm.is_place_lit("site:fixture-park"):
		push_error("FAIL: site:fixture-park should be lit")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if tm.is_place_ringed("site:fixture-park"):
		push_error("FAIL: site:fixture-park should NOT be ringed; rings are for cities only")
		tm.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	tm.queue_free()

	# -------------------------------------------------------------
	# 4. Return Home Button in map_view:
	# Visible only when camera is within 1 cell of the Waypost
	# -------------------------------------------------------------
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene == null:
		push_error("FAIL: Could not load map_view.tscn")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var mv = map_view_scene.instantiate()
	add_child(mv)

	# Load fixture city
	var loaded: bool = mv.load_place("city:fixture-city")
	if not loaded:
		push_error("FAIL: map_view.load_place failed for city:fixture-city")
		mv.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Fixture Town Hall Waypost is at cell (3, 4)
	if mv._active_waypost_cell != Vector2i(3, 4):
		push_error("FAIL: Expected waypost cell (3, 4), got %s" % str(mv._active_waypost_cell))
		mv.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# (a) At Waypost cell (3, 4): Return home button MUST be visible
	mv.focus_on_cell(3, 4)
	if not mv._return_home_button.visible:
		push_error("FAIL: Return home button should be visible at Waypost cell (3, 4)")
		mv.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# (b) Within 1 cell (e.g. cell (4, 4) or (3, 5)): Return home button MUST be visible
	mv.focus_on_cell(4, 4)
	if not mv._return_home_button.visible:
		push_error("FAIL: Return home button should be visible within 1 cell at (4, 4)")
		mv.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# (c) Away from Waypost (> 1 cell distance, e.g. cell (7, 4)): Return home button MUST be hidden
	mv.focus_on_cell(7, 4)
	if mv._return_home_button.visible:
		push_error("FAIL: Return home button should be hidden away from Waypost at cell (7, 4)")
		mv.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	mv.queue_free()

	# -------------------------------------------------------------
	# 5. Home Hub Scene:
	# Buttons exist, Rest/PC Box/Garden disabled with tooltips, Distort/Pair enabled
	# -------------------------------------------------------------
	var hub_scene = load("res://scenes/home_hub.tscn")
	if hub_scene == null:
		push_error("FAIL: Could not load home_hub.tscn")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var hub = hub_scene.instantiate()
	add_child(hub)

	if hub.distort_button == null or hub.distort_button.disabled:
		push_error("FAIL: Distort button missing or disabled in home_hub")
		hub.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if hub.rest_button == null or not hub.rest_button.disabled or not hub.rest_button.tooltip_text.contains("Phase 4–7"):
		push_error("FAIL: Rest button should be disabled with Phase 4–7 tooltip")
		hub.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if hub.pc_box_button == null or not hub.pc_box_button.disabled or not hub.pc_box_button.tooltip_text.contains("Phase 4–7"):
		push_error("FAIL: PC Box button should be disabled with Phase 4–7 tooltip")
		hub.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if hub.garden_button == null or not hub.garden_button.disabled or not hub.garden_button.tooltip_text.contains("Phase 4–7"):
		push_error("FAIL: Garden button should be disabled with Phase 4–7 tooltip")
		hub.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if hub.pair_button == null or hub.pair_button.disabled:
		push_error("FAIL: Pair button missing or disabled in home_hub")
		hub.queue_free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	hub.queue_free()

	# -------------------------------------------------------------
	# 6. Boot Routing in main.gd:
	# - with a bodyFix inside a famous place -> open place's map view;
	# - otherwise -> open home hub.
	# -------------------------------------------------------------
	var main_node = load("res://scenes/main.gd").new()

	# Case A: bodyFix inside Fixture City (node 9104 at WM (1152, 1152))
	var ot_ll := Grid.wm_to_latlon(Vector2(1152.0, 1152.0))
	DB.update_sync_peer("test_peer", 1, ot_ll.x, ot_ll.y, now)

	var boot_place_a: String = main_node.get_boot_place_id(stores)
	if boot_place_a != "city:fixture-city":
		push_error("FAIL (boot routing A): Expected city:fixture-city, got '%s'" % boot_place_a)
		main_node.free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Case B: bodyFix outside famous places (e.g. far out point)
	var out_ll := Grid.wm_to_latlon(Vector2(5248.0, 5248.0))
	DB.update_sync_peer("test_peer", 2, out_ll.x, out_ll.y, now + 10)

	var boot_place_b: String = main_node.get_boot_place_id(stores)
	if not boot_place_b.is_empty():
		push_error("FAIL (boot routing B): Expected empty boot_place_id for outside fix, got '%s'" % boot_place_b)
		main_node.free()
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	main_node.free()

	# Cleanup
	city_store.close()
	site_store.close()
	_cleanup()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: town_map_test")
	return true
