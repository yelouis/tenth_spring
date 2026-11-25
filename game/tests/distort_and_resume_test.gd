extends Node

## game/tests/distort_and_resume_test.gd — Item 71 Distort Arrival, Camp-Only Return Home, Exact-Tile Resume & §5 Banners
## Contract: docs/design_travel_and_time.md §5; docs/implementation_plan_travel_and_time.md §(j), §(n)

const MainScript := preload("res://scenes/main.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")

const TEST_DB_PATH: String = "user://test/distort_and_resume_test.db"
const TEST_TMP_PATH: String = "user://test/distort_and_resume_test.db.tmp"

func _cleanup(main_nodes: Array = []) -> void:
	for n in main_nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in distort_and_resume_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	var main1: Node2D = MainScript.new()
	var mv1: Node = main1.distort_to_place("city:washington-dc", true, self)
	if mv1 == null:
		push_error("FAIL: distort_to_place('city:washington-dc') returned null")
		_cleanup([main1])
		return false
	# Ensure walk mode placed player at (31, 26) facing S in camp:washington-dc with exact §5 arrival banner
	var walker1: PlayerWalker = mv1.get_player_walker()
	if walker1 == null:
		push_error("FAIL: PlayerWalker missing after distort_to_place")
		_cleanup([mv1, main1])
		return false
	var camp_comp: Dictionary = mv1._caricature_compiled_by_area["camp:washington-dc"]
	var camp_local := CaricatureWalkerGrid.global_to_local(camp_comp, walker1.grid_pos.x, walker1.grid_pos.y)
	if mv1.get_current_walk_area_id() != "camp:washington-dc" or camp_local != Vector2i(31, 26) or walker1.facing != "S":
		push_error("FAIL: Expected Distort arrival at camp (31, 26) facing S, got area=%s local=%s facing=%s" % [
			mv1.get_current_walk_area_id(), str(camp_local), walker1.facing
		])
		_cleanup([mv1, main1])
		return false
	var arr_banner := str(mv1.get_last_banner_text())
	if arr_banner != "You are in Washington DC. You have what you carry. The way home is this Waypost.":
		push_error("FAIL: Arrival banner mismatch: got '%s'" % arr_banner)
		_cleanup([mv1, main1])
		return false

	# 2. Move player to Georgetown (55, 62) facing W at clock 14:20 (860), persist, close DB & relaunch fresh session
	var now := int(Time.get_unix_time_from_system())
	DB.upsert_neighbourhood_state("hood:washington-dc:georgetown", "city:washington-dc", 2, "pick", now)
	mv1.get_world_clock().set_minutes(860, true) # 14:20
	mv1.place_player_in_area("hood:washington-dc:georgetown", Vector2i(55, 62), "W")

	# Falsifier: try_return_home() while in Georgetown MUST return false and preserve last_place
	if mv1.try_return_home() or DB.get_db_meta("last_place", "") != "city:washington-dc":
		push_error("FAIL [falsifier]: Return home succeeded outside camp or cleared last_place!")
		_cleanup([mv1, main1])
		return false

	# Simulate quit & 10 hours elapsed offline (must NEVER fast-forward!)
	DB.set_world_clock_minutes(860, now - 36000)
	remove_child(mv1)
	mv1.free()
	main1.free()
	DB.close()
	DB.init_db()

	var main2: Node2D = MainScript.new()
	var mv2: Node = main2.resume_from_session(true, self)
	if mv2 == null:
		push_error("FAIL: resume_from_session returned null")
		_cleanup([main2])
		return false
	var walker2: PlayerWalker = mv2.get_player_walker()
	var gt_comp: Dictionary = mv2._caricature_compiled_by_area["hood:washington-dc:georgetown"]
	var gt_local := CaricatureWalkerGrid.global_to_local(gt_comp, walker2.grid_pos.x, walker2.grid_pos.y)
	if mv2.get_current_walk_area_id() != "hood:washington-dc:georgetown" or gt_local != Vector2i(55, 62) or walker2.facing != "W":
		push_error("FAIL: Exact-tile resume mismatch: area=%s local=%s facing=%s" % [
			mv2.get_current_walk_area_id(), str(gt_local), walker2.facing
		])
		_cleanup([mv2, main2])
		return false
	if int(mv2.get_world_clock().game_epoch_minutes) != 860:
		push_error("FAIL: Clock fast-forwarded across quit/resume: expected 860, got %d" % int(mv2.get_world_clock().game_epoch_minutes))
		_cleanup([mv2, main2])
		return false
	var res_banner := str(mv2.get_last_banner_text())
	if res_banner != "You are in Georgetown. The Waypost is 10 min on foot.":
		push_error("FAIL: Resume banner mismatch: expected 'You are in Georgetown. The Waypost is 10 min on foot.', got '%s'" % res_banner)
		_cleanup([mv2, main2])
		return false

	# 3. Return to camp & Distort Home -> clears last_place, clears player_session.place_id, stops clock
	mv2.place_player_in_area("camp:washington-dc", Vector2i(31, 26), "S")
	if not mv2.try_return_home():
		push_error("FAIL: Return home from camp failed")
		_cleanup([mv2, main2])
		return false
	if DB.get_db_meta("last_place", "") != "":
		push_error("FAIL: Return home did not clear last_place")
		_cleanup([mv2, main2])
		return false
	var sess_home: Dictionary = DB.get_player_session()
	if str(sess_home.get("place_id", "")) != "":
		push_error("FAIL: Return home did not clear player_session.place_id: %s" % str(sess_home))
		_cleanup([mv2, main2])
		return false
	if mv2.get_world_clock().is_running():
		push_error("FAIL: WorldClock still running after returning home")
		_cleanup([mv2, main2])
		return false

	# 4. Resuming from an indoor session opens InteriorView at exact saved interior + floor (not camp)
	DB.set_db_meta("last_place", "city:washington-dc")
	DB.save_player_session({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:georgetown",
		"tile_x": 55,
		"tile_y": 62,
		"facing": "N",
		"interior_id": "dc:georgetown-ruins",
		"interior_floor": 0,
		"interior_x": 7,
		"interior_y": 8,
		"return_area_id": "hood:washington-dc:georgetown",
		"return_x": 55,
		"return_y": 62,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	remove_child(mv2)
	mv2.free()
	main2.free()
	DB.close()
	DB.init_db()

	var main3: Node2D = MainScript.new()
	var resumed_indoor: Node = main3.resume_from_session(true, self)
	var warm_mv: Node = main3._warm_map_view
	if resumed_indoor == null or resumed_indoor.name != "InteriorView":
		push_error("FAIL [falsifier]: Indoor session resume did not open InteriorView, got %s" % str(resumed_indoor))
		_cleanup([resumed_indoor, warm_mv, main3])
		return false
	if str(resumed_indoor._compiled.get("id", "")) != "dc:georgetown-ruins":
		push_error("FAIL: Resumed wrong interior: %s" % str(resumed_indoor._compiled.get("id", "")))
		_cleanup([resumed_indoor, warm_mv, main3])
		return false

	_cleanup([resumed_indoor, warm_mv, main3])
	return true
