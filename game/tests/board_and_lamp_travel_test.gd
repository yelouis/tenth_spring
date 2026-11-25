extends Node

## game/tests/board_and_lamp_travel_test.gd — Item 71 Waypost Board & Lamps-Only Fast Travel Tests
## Contract: Decision 79 fix (c); docs/implementation_plan_travel_and_time.md §(f), §(n)

const MapViewScene := preload("res://world/map_view.tscn")
const WaypostBoardScene := preload("res://scenes/waypost_board.tscn")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")

const TEST_DB_PATH: String = "user://test/board_and_lamp_travel_test.db"
const TEST_TMP_PATH: String = "user://test/board_and_lamp_travel_test.db.tmp"

func _cleanup(mv: Node = null) -> void:
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	if mv != null and is_instance_valid(mv):
		if mv.get_parent() != null:
			mv.get_parent().remove_child(mv)
		mv.free()
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _find_button_prefix(root: Node, prefix: String) -> Button:
	for ch in root.get_children():
		if ch is Button and str(ch.name).begins_with(prefix):
			return ch as Button
		var nested := _find_button_prefix(ch, prefix)
		if nested != null:
			return nested
	return null

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in board_and_lamp_travel_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	# Open National Mall (gateway -> can_go=true) & Tidal Basin (state=1, NOT entered yet)
	DB.upsert_neighbourhood_state("hood:washington-dc:national-mall", "city:washington-dc", 1, "first_pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:tidal-basin", "city:washington-dc", 1, "first_pick", now)
	# Also mark Capitol Hill & Georgetown as entered (state=2) for lamp-to-lamp 15-min travel test
	DB.upsert_neighbourhood_state("hood:washington-dc:capitol-hill", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:georgetown", "city:washington-dc", 2, "pick", now)
	DB.set_world_clock_minutes(1131) # 18:51 -> 9 min left until 19:00 dusk

	var mv := MapViewScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", true):
		push_error("FAIL: MapViewer.load_place failed")
		_cleanup(mv)
		return false

	var walker: PlayerWalker = mv.get_player_walker()
	walker.live_input_enabled = false

	# 1. Board daylight colors & demo-only button guard (standing constraint 22)
	NeighbourhoodProgress.set_demo_override_for_tests(0)
	var board: Control = mv.open_board()
	if board == null:
		push_error("FAIL: open_board returned null")
		_cleanup(mv)
		return false
	# At 18:51 (9 min left): national-mall (2 min -> 2*2=4<=9 -> green), capitol-hill (6 min -> 6<=9<12 -> amber), georgetown (10 min -> >9 -> red)
	var nm_info: Dictionary = board.get_row_info("hood:washington-dc:national-mall")
	var ch_info: Dictionary = board.get_row_info("hood:washington-dc:capitol-hill")
	var gt_info: Dictionary = board.get_row_info("hood:washington-dc:georgetown")
	if str(nm_info.get("trip_daylight_tag", "")) != "green" or str(ch_info.get("trip_daylight_tag", "")) != "amber" or str(gt_info.get("trip_daylight_tag", "")) != "red":
		push_error("FAIL: Board row daylight tags wrong at 18:51: nm=%s ch=%s gt=%s" % [
			str(nm_info.get("trip_daylight_tag", "")),
			str(ch_info.get("trip_daylight_tag", "")),
			str(gt_info.get("trip_daylight_tag", "")),
		])
		_cleanup(mv)
		return false
	if _find_button_prefix(board, "DemoWalk_") != null or _find_button_prefix(board, "DemoFinish") != null:
		push_error("FAIL [falsifier]: Demo buttons present in WaypostBoard when non-demo!")
		_cleanup(mv)
		return false

	# 2. Clicking Go on National Mall from Camp -> lands at (78, 47) facing S, charges exact 2 min
	var clk_before_nm := int(mv.get_world_clock().game_epoch_minutes)
	board._on_go_pressed("hood:washington-dc:national-mall")
	var nm_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:national-mall"]
	var nm_local := CaricatureWalkerGrid.global_to_local(nm_comp, walker.grid_pos.x, walker.grid_pos.y)
	if mv.get_current_walk_area_id() != "hood:washington-dc:national-mall" or nm_local != Vector2i(78, 47) or walker.facing != "S":
		push_error("FAIL: Board Go to National Mall landed wrong: area=%s local=%s facing=%s" % [
			mv.get_current_walk_area_id(), str(nm_local), walker.facing
		])
		_cleanup(mv)
		return false
	var clk_after_nm := int(mv.get_world_clock().game_epoch_minutes)
	if clk_after_nm - clk_before_nm != 2:
		push_error("FAIL: Expected Camp -> National Mall = 2 min, got %d" % (clk_after_nm - clk_before_nm))
		_cleanup(mv)
		return false

	# 3. Decision 79 fix (c): NO global "Back to camp" button while walking, and Return Home hidden/refused outside camp
	if mv._back_to_camp_button != null and mv._back_to_camp_button.visible:
		push_error("FAIL [falsifier]: BackToCampButton must be hidden in walk mode (lamps-only fast travel)!")
		_cleanup(mv)
		return false
	if mv._return_home_button != null and mv._return_home_button.visible:
		push_error("FAIL [falsifier]: ReturnHomeButton must be hidden outside camp!")
		_cleanup(mv)
		return false
	if mv.can_return_home() or mv.try_return_home():
		push_error("FAIL [falsifier]: Return home must be refused while standing in National Mall!")
		_cleanup(mv)
		return false

	# 4. At National Mall's lamp: LampMenu lists Camp (2 min) + entered hoods (Capitol Hill, Georgetown), REFUSES unentered Tidal Basin (state=1)
	var lamp_menu: Control = mv.open_lamp_menu()
	if lamp_menu == null:
		push_error("FAIL: open_lamp_menu returned null")
		_cleanup(mv)
		return false
	if not lamp_menu.can_travel_to("camp:washington-dc"):
		push_error("FAIL: National Mall lamp must offer Camp")
		_cleanup(mv)
		return false
	if not lamp_menu.can_travel_to("hood:washington-dc:capitol-hill") or not lamp_menu.can_travel_to("hood:washington-dc:georgetown"):
		push_error("FAIL: National Mall lamp must offer entered neighbourhoods (Capitol Hill, Georgetown)")
		_cleanup(mv)
		return false
	if lamp_menu.can_travel_to("hood:washington-dc:tidal-basin") or lamp_menu.select_destination("hood:washington-dc:tidal-basin"):
		push_error("FAIL [falsifier]: LampMenu allowed unentered (state=1) Tidal Basin!")
		_cleanup(mv)
		return false
	if lamp_menu.can_travel_to("hood:washington-dc:national-mall"):
		push_error("FAIL: LampMenu must not list the current neighbourhood")
		_cleanup(mv)
		return false

	# 5. Travel via lamp: National Mall -> Capitol Hill -> Georgetown (15 min: 3.643 mi * 4 = 14.57 -> 15)
	if not lamp_menu.select_destination("hood:washington-dc:capitol-hill"):
		push_error("FAIL: LampMenu travel to Capitol Hill failed")
		_cleanup(mv)
		return false
	var clk_before_gt := int(mv.get_world_clock().game_epoch_minutes)
	var lamp_ch: Control = mv.open_lamp_menu()
	if not lamp_ch.select_destination("hood:washington-dc:georgetown"):
		push_error("FAIL: LampMenu travel Capitol Hill -> Georgetown failed")
		_cleanup(mv)
		return false
	var clk_after_gt := int(mv.get_world_clock().game_epoch_minutes)
	if clk_after_gt - clk_before_gt != 15:
		push_error("FAIL: Expected Capitol Hill -> Georgetown = 15 min, got %d" % (clk_after_gt - clk_before_gt))
		_cleanup(mv)
		return false
	var gt_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:georgetown"]
	var gt_expected_arr: Vector2i = gt_comp["arrival"]
	var gt_local := CaricatureWalkerGrid.global_to_local(gt_comp, walker.grid_pos.x, walker.grid_pos.y)
	if mv.get_current_walk_area_id() != "hood:washington-dc:georgetown" or gt_local != gt_expected_arr or walker.facing != "S":
		push_error("FAIL: Lamp travel to Georgetown landed at %s (expected %s) facing %s" % [str(gt_local), str(gt_expected_arr), walker.facing])
		_cleanup(mv)
		return false

	# 6. Return to camp via Georgetown lamp -> camp arrival (31, 26), can_return_home becomes true, camp lamp offers Board + Distort Home
	var lamp_gt: Control = mv.open_lamp_menu()
	if not lamp_gt.select_destination("camp:washington-dc"):
		push_error("FAIL: Lamp travel Georgetown -> Camp failed")
		_cleanup(mv)
		return false
	var camp_comp: Dictionary = mv._caricature_compiled_by_area["camp:washington-dc"]
	var camp_local := CaricatureWalkerGrid.global_to_local(camp_comp, walker.grid_pos.x, walker.grid_pos.y)
	if mv.get_current_walk_area_id() != "camp:washington-dc" or camp_local != Vector2i(31, 26) or not mv.can_return_home():
		push_error("FAIL: Expected camp arrival (31, 26) with can_return_home=true, got area=%s local=%s can_home=%s" % [
			mv.get_current_walk_area_id(), str(camp_local), str(mv.can_return_home())
		])
		_cleanup(mv)
		return false
	var camp_lamp: Control = mv.open_lamp_menu()
	var camp_entries: Array = camp_lamp.get_entries()
	var has_board_act := false
	var has_home_act := false
	for e in camp_entries:
		if str(e.get("action", "")) == "board":
			has_board_act = true
		if str(e.get("action", "")) == "distort_home":
			has_home_act = true
	if not has_board_act or not has_home_act:
		push_error("FAIL: Camp lamp menu must offer Board and Distort Home, got %s" % str(camp_entries))
		_cleanup(mv)
		return false

	# 7. Decision 81 (F90): All 9/9 DC Waypost lamps block walking north from arrival (bump!) while still opening LampMenu
	var lamp_areas := [
		"camp:washington-dc",
		"hood:washington-dc:national-mall",
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:dupont-circle",
		"hood:washington-dc:capitol-hill",
		"hood:washington-dc:union-station",
		"hood:washington-dc:georgetown",
		"hood:washington-dc:woodley-park",
		"hood:washington-dc:lincoln-memorial",
	]
	var bumped_count := 0
	for laid in lamp_areas:
		var lcomp: Dictionary = mv._caricature_compiled_by_area[laid]
		var larr: Vector2i = lcomp["arrival"]
		var lpos: Vector2i = lcomp["lamp"]
		mv.place_player_in_area(laid, larr, "N", false)
		var g_before := walker.grid_pos
		if mv.get_walker_grid().is_local_tile_walkable(laid, lpos.x, lpos.y):
			push_error("FAIL [F90]: Lamp post tile %s in %s must be solid" % [str(lpos), laid])
			_cleanup(mv)
			return false
		if not mv.get_walker_grid().is_local_tile_walkable(laid, lpos.x, lpos.y - 1):
			push_error("FAIL [F90]: Lamp lantern row %s in %s must remain walkable behind lamp" % [str(Vector2i(lpos.x, lpos.y - 1)), laid])
			_cleanup(mv)
			return false
		walker.step_simulation(1.0 / 60.0, Vector2i(0, -1), false)
		if walker._state != PlayerWalker.State.BUMPING or walker.grid_pos != g_before:
			push_error("FAIL [F90]: Stepping north from %s arrival %s did not bump (state=%d pos=%s)" % [laid, str(larr), walker._state, str(walker.grid_pos)])
			_cleanup(mv)
			return false
		for _bf in range(32):
			walker.step_simulation(1.0 / 60.0, Vector2i.ZERO, false)
		if walker.grid_pos != g_before:
			push_error("FAIL [F90]: Player moved onto lamp in %s!" % laid)
			_cleanup(mv)
			return false
		# Interacting while facing the solid lamp post still opens the lamp menu
		if mv._lamp_menu != null:
			mv._lamp_menu.visible = false
		if not mv.trigger_interact_for_walker() or mv._lamp_menu == null or not mv._lamp_menu.visible:
			push_error("FAIL [F90]: Facing lamp in %s did not open LampMenu" % laid)
			_cleanup(mv)
			return false
		mv._lamp_menu.visible = false
		mv._sync_modal_input_lock()
		bumped_count += 1
	if bumped_count != 9:
		push_error("FAIL [F90]: Expected 9/9 lamps bumped, got %d" % bumped_count)
		_cleanup(mv)
		return false

	_cleanup(mv)
	return true
