extends Node

## game/tests/seamless_routes_test.gd — Item 70 Seamless 22-Opening Crossing, walk_route & Route Sign Daylight Tests
## Contract: docs/implementation_plan_travel_and_time.md §(e), §(i), §(n); docs/design_travel_and_time.md §2

const MapViewScene := preload("res://world/map_view.tscn")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const WorldClock := preload("res://world/world_clock.gd")

const TEST_DB_PATH: String = "user://test/seamless_routes_test.db"
const TEST_TMP_PATH: String = "user://test/seamless_routes_test.db.tmp"

func _cleanup(mv: Node = null) -> void:
	if mv != null and is_instance_valid(mv):
		if mv.get_parent() != null:
			mv.get_parent().remove_child(mv)
		mv.free()
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _step_walker_once(walker: Node, dir: Vector2i, running: bool = false) -> void:
	# First align facing if needed, then complete a full step (or trigger bump)
	var need_f := ""
	if dir.y < 0:
		need_f = "N"
	elif dir.y > 0:
		need_f = "S"
	elif dir.x < 0:
		need_f = "W"
	elif dir.x > 0:
		need_f = "E"
	if walker.facing != need_f:
		walker.place_at(walker.grid_pos, need_f, false)
	var dur: float = walker.run_step_duration() if running else walker.walk_step_duration()
	walker.step_simulation(dur + 0.002, dir, running)

func _find_seam(grid: CaricatureWalkerGrid, from_area_id: String, to_area_id: String) -> Dictionary:
	for s_var in grid.get_all_seams():
		if s_var is Dictionary:
			var s: Dictionary = s_var
			if str(s.get("from_area_id", "")) == from_area_id and str(s.get("to_area_id", "")) == to_area_id:
				return s
	return {}

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in seamless_routes_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	# Prepare DC save: camp ensured, dupont-circle entered (state=2), georgetown open (state=1, route q-street open state=1)
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	DB.upsert_neighbourhood_state("hood:washington-dc:dupont-circle", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:georgetown", "city:washington-dc", 1, "pick", now)
	DB.upsert_neighbourhood_state("route:washington-dc:q-street", "city:washington-dc", 1, "route", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:union-station", "city:washington-dc", 1, "pick", now)
	DB.upsert_neighbourhood_state("route:washington-dc:massachusetts-avenue", "city:washington-dc", 1, "route", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:tidal-basin", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:lincoln-memorial", "city:washington-dc", 1, "pick", now)
	DB.upsert_neighbourhood_state("route:washington-dc:west-potomac-park", "city:washington-dc", 1, "route", now)
	# Note: woodley-park and connecticut-avenue remain LOCKED (state 0 / no row)
	DB.set_world_clock_minutes(600) # 10:00 AM

	var mv := MapViewScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", true):
		push_error("FAIL: MapViewer.load_place failed for city:washington-dc")
		_cleanup(mv)
		return false

	var grid: CaricatureWalkerGrid = mv.get_walker_grid()
	var walker: PlayerWalker = mv.get_player_walker()
	if grid == null or walker == null:
		push_error("FAIL: walker_grid or player_walker missing after load_place")
		_cleanup(mv)
		return false
	walker.live_input_enabled = false

	# 1. Precomputed 22-opening seam index (22 bidirectional links = 44 directed crossings)
	if grid.get_seam_link_count() != 22 or grid.get_seam_count() != 44:
		push_error("FAIL: Expected 22 seam links / 44 directed seams, got links=%d directed=%d" % [
			grid.get_seam_link_count(), grid.get_seam_count()
		])
		_cleanup(mv)
		return false

	# 2. Seamless crossing Dupont Circle -> Q Street #1 -> Georgetown fires walk_route & charges real walk minutes
	if NeighbourhoodProgress.can_go(DB, "hood:washington-dc:georgetown"):
		push_error("FAIL: Georgetown should NOT have can_go=true before walking Q Street")
		_cleanup(mv)
		return false

	var seam_dup_q := _find_seam(grid, "hood:washington-dc:dupont-circle", "route:washington-dc:q-street#1")
	var seam_q_geo := _find_seam(grid, "route:washington-dc:q-street#1", "hood:washington-dc:georgetown")
	if seam_dup_q.is_empty() or seam_q_geo.is_empty():
		push_error("FAIL: Missing Q Street seams in seam index")
		_cleanup(mv)
		return false

	var start_clk := int(mv.get_world_clock().game_epoch_minutes)
	var dup_from_g: Vector2i = seam_dup_q["from_global"]
	var dup_dir: Vector2i = seam_dup_q["dir"]
	var dup_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:dupont-circle"]
	var dup_from_l: Vector2i = CaricatureWalkerGrid.global_to_local(dup_comp, dup_from_g.x, dup_from_g.y)
	mv.place_player_in_area("hood:washington-dc:dupont-circle", dup_from_l, "W")

	# Step across seam onto Q Street #1
	_step_walker_once(walker, dup_dir)
	if mv.get_current_walk_area_id() != "route:washington-dc:q-street#1":
		push_error("FAIL: Expected seamless step onto route:washington-dc:q-street#1, got %s" % mv.get_current_walk_area_id())
		_cleanup(mv)
		return false
	if walker.grid_pos != seam_dup_q["to_global"]:
		push_error("FAIL: Expected walker at seam target %s, got %s" % [str(seam_dup_q["to_global"]), str(walker.grid_pos)])
		_cleanup(mv)
		return false
	var sess_mid: Dictionary = DB.get_player_session()
	if str(sess_mid.get("route_origin_area_id", "")) != "hood:washington-dc:dupont-circle" or str(sess_mid.get("active_route_id", "")) != "route:washington-dc:q-street":
		push_error("FAIL: Expected route_origin/active_route persisted on crossing into Q Street, got %s" % str(sess_mid))
		_cleanup(mv)
		return false
	if int(sess_mid.get("route_time_accum_milli", 0)) <= 0 and int(sess_mid.get("route_time_charged_min", 0)) <= 0:
		push_error("FAIL: Expected fractional route time accrual on route step, got accum=%d charged=%d" % [
			int(sess_mid.get("route_time_accum_milli", 0)), int(sess_mid.get("route_time_charged_min", 0))
		])
		_cleanup(mv)
		return false

	# Verify mid-route fractional accrual ticks WorldClock (+1 min once accum >= 1000 milli-min)
	# Q Street is 7 min over ~162 steps (~43 milli-min/step), so 25 tiles inside q-street#1 ticks >= 1 min
	var p_in_q: Vector2i = walker.grid_pos
	var p_in_q2: Vector2i = p_in_q + dup_dir # 1 tile further west inside q-street#1
	var mid_clk_start := int(mv.get_world_clock().game_epoch_minutes)
	for step_i in range(24):
		var d_step := dup_dir if (step_i % 2 == 0) else -dup_dir
		if (step_i % 2 == 0 and walker.grid_pos == p_in_q) or (step_i % 2 == 1 and walker.grid_pos == p_in_q2):
			_step_walker_once(walker, d_step)
	var mid_clk_after := int(mv.get_world_clock().game_epoch_minutes)
	if mid_clk_after <= mid_clk_start:
		push_error("FAIL: Expected mid-route walking to tick WorldClock via route_time_accum_milli (start=%d after=%d state=%s)" % [
			mid_clk_start, mid_clk_after, str(mv.get_route_crossing_state())
		])
		_cleanup(mv)
		return false

	# Advance to Q Street #1's Georgetown opening while preserving route crossing state, then step into Georgetown
	var q_from_g: Vector2i = seam_q_geo["from_global"]
	var q_dir: Vector2i = seam_q_geo["dir"]
	walker.place_at(q_from_g, "W", false)
	_step_walker_once(walker, q_dir)

	if mv.get_current_walk_area_id() != "hood:washington-dc:georgetown":
		push_error("FAIL: Expected seamless arrival in georgetown, got %s" % mv.get_current_walk_area_id())
		_cleanup(mv)
		return false
	var geo_row: Dictionary = DB.get_neighbourhood_state("hood:washington-dc:georgetown")
	var qs_row: Dictionary = DB.get_neighbourhood_state("route:washington-dc:q-street")
	if int(geo_row.get("state", 0)) != 2 or not NeighbourhoodProgress.can_go(DB, "hood:washington-dc:georgetown"):
		push_error("FAIL: Expected walk_route to enter georgetown & light lamp, row=%s can_go=%s" % [str(geo_row), str(NeighbourhoodProgress.can_go(DB, "hood:washington-dc:georgetown"))])
		_cleanup(mv)
		return false
	if int(qs_row.get("state", 0)) != 2:
		push_error("FAIL: Expected q-street state=2 after walking across, got %s" % str(qs_row))
		_cleanup(mv)
		return false
	var expected_q_min := NeighbourhoodProgress.route_walk_minutes("route:washington-dc:q-street", false)
	var after_clk := int(mv.get_world_clock().game_epoch_minutes)
	if after_clk - start_clk != expected_q_min:
		push_error("FAIL: Expected Q Street crossing to charge exact %d min, got delta=%d (start=%d after=%d)" % [
			expected_q_min, after_clk - start_clk, start_clk, after_clk
		])
		_cleanup(mv)
		return false
	var banner := str(mv.get_last_banner_text())
	if banner != "Arrived in Georgetown — lamp lit for fast travel.":
		push_error("FAIL: Expected exact first-arrival banner, got '%s'" % banner)
		_cleanup(mv)
		return false

	# 3. Falsifier A: Locked-route opening (Dupont Circle -> Connecticut Avenue, locked) refused with fog toast
	var seam_dup_conn := _find_seam(grid, "hood:washington-dc:dupont-circle", "route:washington-dc:connecticut-avenue#1")
	if seam_dup_conn.is_empty():
		push_error("FAIL: Missing Dupont -> Connecticut Ave seam")
		_cleanup(mv)
		return false
	var conn_from_g: Vector2i = seam_dup_conn["from_global"]
	var conn_dir: Vector2i = seam_dup_conn["dir"]
	var conn_from_l: Vector2i = CaricatureWalkerGrid.global_to_local(dup_comp, conn_from_g.x, conn_from_g.y)
	mv.place_player_in_area("hood:washington-dc:dupont-circle", conn_from_l, "N")
	_step_walker_once(walker, conn_dir)
	if walker.grid_pos != conn_from_g or mv.get_current_walk_area_id() != "hood:washington-dc:dupont-circle":
		push_error("FAIL: Locked route crossing should be refused; pos=%s area=%s" % [str(walker.grid_pos), mv.get_current_walk_area_id()])
		_cleanup(mv)
		return false
	var fog_toast := str(mv.get_last_toast_text())
	if fog_toast != "Thick fog blocks the way — open the next neighbourhood at the Waypost board first.":
		push_error("FAIL: Expected locked-fog toast, got '%s'" % fog_toast)
		_cleanup(mv)
		return false

	# 4. Falsifier B: Turn-back guard (Dupont -> Mass Ave -> back into Dupont) must NOT call walk_route
	var seam_dup_mass := _find_seam(grid, "hood:washington-dc:dupont-circle", "route:washington-dc:massachusetts-avenue#1")
	if seam_dup_mass.is_empty():
		push_error("FAIL: Missing Dupont -> Mass Ave seam")
		_cleanup(mv)
		return false
	var mass_from_g: Vector2i = seam_dup_mass["from_global"]
	var mass_dir: Vector2i = seam_dup_mass["dir"]
	var mass_from_l: Vector2i = CaricatureWalkerGrid.global_to_local(dup_comp, mass_from_g.x, mass_from_g.y)
	mv.place_player_in_area("hood:washington-dc:dupont-circle", mass_from_l, "E")
	_step_walker_once(walker, mass_dir)
	if mv.get_current_walk_area_id() != "route:washington-dc:massachusetts-avenue#1":
		push_error("FAIL: Failed to enter Mass Ave #1 for turn-back test")
		_cleanup(mv)
		return false
	# Immediately turn back West into Dupont Circle
	_step_walker_once(walker, -mass_dir)
	if mv.get_current_walk_area_id() != "hood:washington-dc:dupont-circle":
		push_error("FAIL: Failed to turn back into Dupont Circle")
		_cleanup(mv)
		return false
	var us_row: Dictionary = DB.get_neighbourhood_state("hood:washington-dc:union-station")
	var ma_row: Dictionary = DB.get_neighbourhood_state("route:washington-dc:massachusetts-avenue")
	if int(us_row.get("state", 0)) != 1 or NeighbourhoodProgress.can_go(DB, "hood:washington-dc:union-station") or int(ma_row.get("state", 0)) != 1:
		push_error("FAIL: Turn-back incorrectly called walk_route! us=%s ma=%s" % [str(us_row), str(ma_row)])
		_cleanup(mv)
		return false

	# 5. Two-leg route preserves origin across leg #1 -> leg #2 seam (tidal-basin -> west-potomac-park #1 -> #2 -> lincoln-memorial)
	var seam_tb_w1 := _find_seam(grid, "hood:washington-dc:tidal-basin", "route:washington-dc:west-potomac-park#1")
	var seam_w1_w2 := _find_seam(grid, "route:washington-dc:west-potomac-park#1", "route:washington-dc:west-potomac-park#2")
	var seam_w2_lm := _find_seam(grid, "route:washington-dc:west-potomac-park#2", "hood:washington-dc:lincoln-memorial")
	if seam_tb_w1.is_empty() or seam_w1_w2.is_empty() or seam_w2_lm.is_empty():
		push_error("FAIL: Missing 2-leg West Potomac Park seams")
		_cleanup(mv)
		return false
	var tb_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:tidal-basin"]
	var tb_l: Vector2i = CaricatureWalkerGrid.global_to_local(tb_comp, seam_tb_w1["from_global"].x, seam_tb_w1["from_global"].y)
	var clk_before_wpp := int(mv.get_world_clock().game_epoch_minutes)
	mv.place_player_in_area("hood:washington-dc:tidal-basin", tb_l, "W")
	_step_walker_once(walker, seam_tb_w1["dir"])
	walker.place_at(seam_w1_w2["from_global"], "N", false)
	_step_walker_once(walker, seam_w1_w2["dir"])
	if mv.get_current_walk_area_id() != "route:washington-dc:west-potomac-park#2":
		push_error("FAIL: Failed to cross west-potomac-park #1 -> #2")
		_cleanup(mv)
		return false
	var sess_leg2: Dictionary = DB.get_player_session()
	if str(sess_leg2.get("route_origin_area_id", "")) != "hood:washington-dc:tidal-basin":
		push_error("FAIL: Lost route_origin across leg #1 -> #2 seam: %s" % str(sess_leg2))
		_cleanup(mv)
		return false
	walker.place_at(seam_w2_lm["from_global"], "N", false)
	_step_walker_once(walker, seam_w2_lm["dir"])
	var lm_row: Dictionary = DB.get_neighbourhood_state("hood:washington-dc:lincoln-memorial")
	var wpp_expected := NeighbourhoodProgress.route_walk_minutes("route:washington-dc:west-potomac-park", false)
	var clk_after_wpp := int(mv.get_world_clock().game_epoch_minutes)
	if int(lm_row.get("state", 0)) != 2 or clk_after_wpp - clk_before_wpp != wpp_expected:
		push_error("FAIL: 2-leg route arrival failed: lm=%s clk_delta=%d expected=%d" % [str(lm_row), clk_after_wpp - clk_before_wpp, wpp_expected])
		_cleanup(mv)
		return false

	# 6. Route sign daylight tagging for Q Street (7 min) per plan §(e):
	#    10:00 (600) -> green, 18:50 (1130, 10m left) -> amber, 18:56 (1136, 4m left) -> red, 22:00 (1320) -> red
	var q_cost := NeighbourhoodProgress.route_walk_minutes("route:washington-dc:q-street", false)
	if q_cost != 7:
		push_error("FAIL: Expected Q Street cost = 7 min, got %d" % q_cost)
		_cleanup(mv)
		return false
	var sign_cases := [
		[600, "green", "Q Street — 7 min on foot (round trip before dusk)"],
		[1130, "amber", "Q Street — 7 min on foot (one-way before dusk)"],
		[1136, "red", "Q Street — 7 min on foot (night ahead)"],
		[1320, "red", "Q Street — 7 min on foot (night ahead)"],
	]
	for sc in sign_cases:
		var m_day: int = int(sc[0])
		var exp_tag: String = str(sc[1])
		var exp_txt: String = str(sc[2])
		var rem_day := WorldClock.daylight_minutes_left_for_minute(m_day)
		var res: Dictionary = WorldClock.format_route_sign_daylight("Q Street", q_cost, rem_day)
		if str(res.get("tag", "")) != exp_tag or str(res.get("text", "")) != exp_txt:
			push_error("FAIL: Route sign daylight mismatch at min=%d: expected (%s, '%s'), got %s" % [
				m_day, exp_tag, exp_txt, str(res)
			])
			_cleanup(mv)
			return false

	_cleanup(mv)
	return true
