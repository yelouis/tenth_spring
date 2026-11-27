extends Node

## game/tests/resume_validation_test.gd — Item 84 (F109) Resume Tile Validation Test
## Contract: docs/agent_execution_guide.md §4 (Item 84 / F109), Decision 83
## Verifies invalid saved indoor/outdoor tiles recover safely while valid tiles stay untouched.

const MainScript := preload("res://scenes/main.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")

const TEST_DB_PATH: String = "user://test/resume_validation_test.db"
const TEST_TMP_PATH: String = "user://test/resume_validation_test.db.tmp"

func _free_nodes(nodes: Array) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()

func _reset_db() -> void:
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	for hood_id in [
		"hood:washington-dc:national-mall",
		"hood:washington-dc:georgetown",
	]:
		DB.upsert_neighbourhood_state(hood_id, "city:washington-dc", 2, "pick", now)
	DB.set_db_meta("last_place", "city:washington-dc")

func _final_cleanup() -> void:
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _step_walker(walker: PlayerWalker, dir: Vector2i) -> void:
	var f := PlayerWalker.dir_vec_to_facing(dir)
	if walker.facing != f:
		walker.place_at(walker.grid_pos, f, false)
	walker.step_simulation(PlayerWalker.walk_step_duration() + 0.002, dir, false)

func _save_and_reopen(sess: Dictionary) -> void:
	DB.save_player_session(sess)
	DB.close()
	DB.init_db()

func _is_outdoor_standable(mv: Node, area_id: String, lpos: Vector2i) -> bool:
	var wgrid: CaricatureWalkerGrid = mv.get_walker_grid()
	if wgrid == null or not mv._caricature_compiled_by_area.has(area_id):
		return false
	var comp: Dictionary = mv._caricature_compiled_by_area[area_id]
	var gpos := CaricatureWalkerGrid.local_to_global(comp, lpos.x, lpos.y)
	for offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nbr: Vector2i = gpos + offset
		var ev: Dictionary = wgrid.evaluate_step(nbr.x, nbr.y, gpos - nbr)
		if str(ev.get("action", "")) == "step" and (ev.get("to", Vector2i(-999999, -999999)) as Vector2i) == gpos:
			return true
	return false

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in resume_validation_test")
		return false

	var failures: Array[String] = []

	# (a) Monument 1F (0, 0) [wall] -> moves to 1F door_mats[0], facing N, updates DB, and can walk South out
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 33,
		"tile_y": 53,
		"facing": "W",
		"interior_id": "dc:washington-monument",
		"interior_floor": 0,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": 33,
		"return_y": 53,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_a: Node2D = MainScript.new()
	var iv_a: InteriorView = main_a.resume_from_session(true, self) as InteriorView
	var warm_a: Node = main_a._warm_map_view
	if iv_a == null or iv_a.get_player_walker() == null:
		failures.append("(a) Monument 1F (0,0): resume_from_session returned null")
	else:
		var f0_a: Dictionary = iv_a._compiled["floors"][0]
		var dm_a: Vector2i = (f0_a["door_mats"] as Array)[0] as Vector2i
		var wa: PlayerWalker = iv_a.get_player_walker()
		wa.live_input_enabled = false
		if iv_a.get_floor_index() != 0 or wa.grid_pos != dm_a or wa.facing != "N":
			failures.append("(a) Monument 1F (0,0): expected floor=0 tile=%s facing=N, got floor=%d tile=%s facing=%s" % [
				str(dm_a), iv_a.get_floor_index(), str(wa.grid_pos), wa.facing
			])
		else:
			var s_a: Dictionary = DB.get_player_session()
			if int(s_a.get("interior_x", -1)) != dm_a.x or int(s_a.get("interior_y", -1)) != dm_a.y:
				failures.append("(a) Monument 1F (0,0): DB not updated to door_mat %s, got (%s,%s)" % [
					str(dm_a), str(s_a.get("interior_x")), str(s_a.get("interior_y"))
				])
			# Must be able to step South off the door mat and exit cleanly
			_step_walker(wa, Vector2i(0, 1))
			if warm_a == null or not warm_a.visible:
				failures.append("(a) Monument 1F (0,0): could not walk South out of interior after fix")
	_free_nodes([iv_a, warm_a, main_a])

	# (b) Monument 1F (8, 4), no opened_gate row -> moves to 1F door_mats[0]
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 33,
		"tile_y": 53,
		"facing": "S",
		"interior_id": "dc:washington-monument",
		"interior_floor": 0,
		"interior_x": 8,
		"interior_y": 4,
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": 33,
		"return_y": 53,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_b: Node2D = MainScript.new()
	var iv_b: InteriorView = main_b.resume_from_session(true, self) as InteriorView
	var warm_b: Node = main_b._warm_map_view
	if iv_b == null or iv_b.get_player_walker() == null:
		failures.append("(b) Monument 1F (8,4) closed gate: resume returned null")
	else:
		var dm_b: Vector2i = (iv_b._compiled["floors"][0]["door_mats"] as Array)[0] as Vector2i
		var wb: PlayerWalker = iv_b.get_player_walker()
		if iv_b.get_floor_index() != 0 or wb.grid_pos != dm_b or wb.facing != "N":
			failures.append("(b) Monument 1F (8,4) closed gate: expected door_mat %s facing N, got floor=%d tile=%s facing=%s" % [
				str(dm_b), iv_b.get_floor_index(), str(wb.grid_pos), wb.facing
			])
	_free_nodes([iv_b, warm_b, main_b])

	# (c) Georgetown Ruins (8, 2), no opened_gate row -> moves to 1F door_mats[0]
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:georgetown",
		"tile_x": 40,
		"tile_y": 40,
		"facing": "E",
		"interior_id": "dc:georgetown-ruins",
		"interior_floor": 0,
		"interior_x": 8,
		"interior_y": 2,
		"return_area_id": "hood:washington-dc:georgetown",
		"return_x": 40,
		"return_y": 40,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_c: Node2D = MainScript.new()
	var iv_c: InteriorView = main_c.resume_from_session(true, self) as InteriorView
	var warm_c: Node = main_c._warm_map_view
	if iv_c == null or iv_c.get_player_walker() == null:
		failures.append("(c) Georgetown Ruins (8,2) closed gate: resume returned null")
	else:
		var dm_c: Vector2i = (iv_c._compiled["floors"][0]["door_mats"] as Array)[0] as Vector2i
		var wc: PlayerWalker = iv_c.get_player_walker()
		if iv_c.get_floor_index() != 0 or wc.grid_pos != dm_c or wc.facing != "N":
			failures.append("(c) Georgetown Ruins (8,2) closed gate: expected door_mat %s facing N, got floor=%d tile=%s facing=%s" % [
				str(dm_c), iv_c.get_floor_index(), str(wc.grid_pos), wc.facing
			])
	_free_nodes([iv_c, warm_c, main_c])

	# (d) Georgetown Ruins (8, 2) WITH gate_canal_keystone opened -> stays at (8, 2) facing E
	_reset_db()
	DB.mark_gate_opened("dc:georgetown-ruins", "gate_canal_keystone")
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:georgetown",
		"tile_x": 40,
		"tile_y": 40,
		"facing": "E",
		"interior_id": "dc:georgetown-ruins",
		"interior_floor": 0,
		"interior_x": 8,
		"interior_y": 2,
		"return_area_id": "hood:washington-dc:georgetown",
		"return_x": 40,
		"return_y": 40,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_d: Node2D = MainScript.new()
	var iv_d: InteriorView = main_d.resume_from_session(true, self) as InteriorView
	var warm_d: Node = main_d._warm_map_view
	if iv_d == null or iv_d.get_player_walker() == null:
		failures.append("(d) Georgetown Ruins (8,2) open gate: resume returned null")
	else:
		var wd: PlayerWalker = iv_d.get_player_walker()
		if iv_d.get_floor_index() != 0 or wd.grid_pos != Vector2i(8, 2) or wd.facing != "E":
			failures.append("(d) Georgetown Ruins (8,2) open gate: should stay at (8,2) E, got floor=%d tile=%s facing=%s" % [
				iv_d.get_floor_index(), str(wd.grid_pos), wd.facing
			])
	_free_nodes([iv_d, warm_d, main_d])

	# (e) National Mall (78, 46) [inside lamp post] -> moves to nearest standable neighbour & persists
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 78,
		"tile_y": 46,
		"facing": "S",
		"interior_id": "",
		"interior_floor": 0,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "",
		"return_x": 0,
		"return_y": 0,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_e: Node2D = MainScript.new()
	var mv_e: Node = main_e.resume_from_session(true, self)
	if mv_e == null or mv_e.get_player_walker() == null:
		failures.append("(e) National Mall (78,46): resume returned null")
	else:
		var nm_comp_e: Dictionary = mv_e._caricature_compiled_by_area["hood:washington-dc:national-mall"]
		var we: PlayerWalker = mv_e.get_player_walker()
		var le := CaricatureWalkerGrid.global_to_local(nm_comp_e, we.grid_pos.x, we.grid_pos.y)
		var manhattan_e := absi(le.x - 78) + absi(le.y - 46)
		if le == Vector2i(78, 46) or manhattan_e != 1 or not _is_outdoor_standable(mv_e, "hood:washington-dc:national-mall", le):
			failures.append("(e) National Mall (78,46): expected standable 1-tile neighbour, got local=%s (dist=%d, standable=%s)" % [
				str(le), manhattan_e, str(_is_outdoor_standable(mv_e, "hood:washington-dc:national-mall", le))
			])
		else:
			var s_e: Dictionary = DB.get_player_session()
			if int(s_e.get("tile_x", -1)) != le.x or int(s_e.get("tile_y", -1)) != le.y:
				failures.append("(e) National Mall (78,46): DB not updated to %s, got (%s,%s)" % [
					str(le), str(s_e.get("tile_x")), str(s_e.get("tile_y"))
				])
	_free_nodes([mv_e, main_e])

	# (f) National Mall (78, 47) [standable] -> stays unchanged at (78, 47) facing W
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 78,
		"tile_y": 47,
		"facing": "W",
		"interior_id": "",
		"interior_floor": 0,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "",
		"return_x": 0,
		"return_y": 0,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_f: Node2D = MainScript.new()
	var mv_f: Node = main_f.resume_from_session(true, self)
	if mv_f == null or mv_f.get_player_walker() == null:
		failures.append("(f) National Mall (78,47): resume returned null")
	else:
		var nm_comp_f: Dictionary = mv_f._caricature_compiled_by_area["hood:washington-dc:national-mall"]
		var wf: PlayerWalker = mv_f.get_player_walker()
		var lf := CaricatureWalkerGrid.global_to_local(nm_comp_f, wf.grid_pos.x, wf.grid_pos.y)
		if lf != Vector2i(78, 47) or wf.facing != "W":
			failures.append("(f) National Mall (78,47): should stay at (78,47) W, got %s %s" % [str(lf), wf.facing])
	_free_nodes([mv_f, main_f])

	# (g) Multi-floor invalid indoor save: Monument 2F (0, 0) -> resets cleanly to 1F (floor 0) door_mat & persists
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 33,
		"tile_y": 53,
		"facing": "W",
		"interior_id": "dc:washington-monument",
		"interior_floor": 1,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": 33,
		"return_y": 53,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_g: Node2D = MainScript.new()
	var iv_g: InteriorView = main_g.resume_from_session(true, self) as InteriorView
	var warm_g: Node = main_g._warm_map_view
	if iv_g == null or iv_g.get_player_walker() == null:
		failures.append("(g) Monument 2F (0,0): resume returned null")
	else:
		var dm_g: Vector2i = (iv_g._compiled["floors"][0]["door_mats"] as Array)[0] as Vector2i
		var wg: PlayerWalker = iv_g.get_player_walker()
		wg.live_input_enabled = false
		if iv_g.get_floor_index() != 0 or wg.grid_pos != dm_g or wg.facing != "N":
			failures.append("(g) Monument 2F (0,0): expected floor=0 door_mat=%s facing=N, got floor=%d tile=%s facing=%s" % [
				str(dm_g), iv_g.get_floor_index(), str(wg.grid_pos), wg.facing
			])
		else:
			var s_g: Dictionary = DB.get_player_session()
			if int(s_g.get("interior_floor", -1)) != 0 or int(s_g.get("interior_x", -1)) != dm_g.x or int(s_g.get("interior_y", -1)) != dm_g.y:
				failures.append("(g) Monument 2F (0,0): DB not updated to floor 0 door_mat: %s" % str(s_g))
			_step_walker(wg, Vector2i(0, 1))
			if warm_g == null or not warm_g.visible:
				failures.append("(g) Monument 2F (0,0): could not step South out after resetting to floor 0")
	_free_nodes([iv_g, warm_g, main_g])

	# (h) Outdoor out-of-range fallback (> 8 tiles from any standable tile): National Mall (999, 999) -> arrival
	_reset_db()
	_save_and_reopen({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": 999,
		"tile_y": 999,
		"facing": "N",
		"interior_id": "",
		"interior_floor": 0,
		"interior_x": 0,
		"interior_y": 0,
		"return_area_id": "",
		"return_x": 0,
		"return_y": 0,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	var main_h: Node2D = MainScript.new()
	var mv_h: Node = main_h.resume_from_session(true, self)
	if mv_h == null or mv_h.get_player_walker() == null:
		failures.append("(h) National Mall (999,999): resume returned null")
	else:
		var nm_comp_h: Dictionary = mv_h._caricature_compiled_by_area["hood:washington-dc:national-mall"]
		var exp_arr: Vector2i = nm_comp_h.get("arrival", Vector2i(16, 16))
		var wh: PlayerWalker = mv_h.get_player_walker()
		var lh := CaricatureWalkerGrid.global_to_local(nm_comp_h, wh.grid_pos.x, wh.grid_pos.y)
		if lh != exp_arr:
			failures.append("(h) National Mall (999,999): expected arrival %s, got %s" % [str(exp_arr), str(lh)])
	_free_nodes([mv_h, main_h])

	_final_cleanup()

	if not failures.is_empty():
		for msg in failures:
			push_error("FAIL [F109]: " + msg)
		return false
	return true
