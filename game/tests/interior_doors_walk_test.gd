extends Node

## game/tests/interior_doors_walk_test.gd — Item 72 All 94 DC Doors, Multi-Floor Stairs, Gust Slide, Switch & Indoor Resume Tests
## Contract: Decision 79; docs/implementation_plan_travel_and_time.md §(g), §(m), §(n)

const MainScript := preload("res://scenes/main.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorTiles := preload("res://world/interior/interior_tiles.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")

const TEST_DB_PATH: String = "user://test/interior_doors_walk_test.db"
const TEST_TMP_PATH: String = "user://test/interior_doors_walk_test.db.tmp"

func _cleanup(nodes: Array = []) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
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

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in interior_doors_walk_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	for hood_id in [
		"hood:washington-dc:national-mall",
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:dupont-circle",
		"hood:washington-dc:capitol-hill",
		"hood:washington-dc:union-station",
		"hood:washington-dc:georgetown",
		"hood:washington-dc:woodley-park",
		"hood:washington-dc:lincoln-memorial",
	]:
		DB.upsert_neighbourhood_state(hood_id, "city:washington-dc", 2, "pick", now)

	var main_node: Node2D = MainScript.new()
	var mv: Node = main_node.distort_to_place("city:washington-dc", true, self)
	if mv == null:
		push_error("FAIL: distort_to_place failed")
		_cleanup([main_node])
		return false
	var walker: PlayerWalker = mv.get_player_walker()
	walker.live_input_enabled = false

	# 1. Verify ALL 94 unique enterable DC interiors (and every enterable door tile) compile, enter onto door_mat facing N at zoom 2.0,
	#    keep MapViewer warm (hidden/disabled, never freed!), and exit South back onto exact (door.x, door.y + 1) facing S.
	var unique_interiors := {}
	var ordinary_door_tested := false
	for aid_v in mv._caricature_compiled_by_area.keys():
		var aid := str(aid_v)
		var comp: Dictionary = mv._caricature_compiled_by_area[aid_v]
		for d_v in comp.get("doors", []):
			if not (d_v is Dictionary):
				continue
			var d: Dictionary = d_v
			var iid := str(d.get("interior", ""))
			var dx := int(d.get("x", 0))
			var dy := int(d.get("y", 0))
			if iid.is_empty():
				if not ordinary_door_tested:
					# Falsifier: ordinary door with interior == "" refuses entry and leaves player on doorstep (dx, dy + 1)
					var step_tile := Vector2i(dx, dy + 1)
					if mv.get_walker_grid().is_local_tile_walkable(aid, step_tile.x, step_tile.y):
						mv.place_player_in_area(aid, step_tile, "N")
						var g_before := walker.grid_pos
						_step_walker(walker, Vector2i(0, -1))
						if not mv.visible or walker.grid_pos != g_before or not walker.is_bumping():
							push_error("FAIL [falsifier]: Ordinary door (%s %d,%d) should refuse entry!" % [aid, dx, dy])
							_cleanup([mv, main_node])
							return false
						ordinary_door_tested = true
				continue

			if unique_interiors.has(iid):
				continue
			unique_interiors[iid] = true

			var ipath := InteriorMap.resolve_interior_path(iid)
			if ipath.is_empty():
				push_error("FAIL: Interior path missing for '%s'" % iid)
				_cleanup([mv, main_node])
				return false
			# Enter door by stepping North from (dx, dy + 1)
			mv.place_player_in_area(aid, Vector2i(dx, dy + 1), "N")
			var iv: InteriorView = main_node.enter_interior_from_map(mv, iid, {
				"place_id": "city:washington-dc",
				"return_area_id": aid,
				"return_x": dx,
				"return_y": dy + 1,
			}, 0, Vector2i(-1, -1), "N", self)
			if iv == null or mv.visible or mv.process_mode != Node.PROCESS_MODE_DISABLED:
				push_error("FAIL: Entering '%s' failed or did not keep MapViewer warm/hidden" % iid)
				_cleanup([iv, mv, main_node])
				return false
			var iwalker: PlayerWalker = iv.get_player_walker()
			if iwalker == null or iwalker.facing != "N" or not is_equal_approx(iv._camera.zoom.x, 2.0):
				push_error("FAIL: Interior '%s' spawn/zoom wrong: walker=%s zoom=%.2f" % [
					iid, str(iwalker != null), iv._camera.zoom.x if iv._camera != null else -1.0
				])
				_cleanup([iv, mv, main_node])
				return false
			var f0: Dictionary = iv._compiled["floors"][0]
			var dm_arr: Array = f0.get("door_mats", [])
			if dm_arr.is_empty() or not (iwalker.grid_pos in dm_arr):
				push_error("FAIL: Interior '%s' did not spawn on floor-0 door_mat: pos=%s mats=%s" % [iid, str(iwalker.grid_pos), str(dm_arr)])
				_cleanup([iv, mv, main_node])
				return false

			# Exit by stepping South off floor-0 door_mat
			iwalker.live_input_enabled = false
			_step_walker(iwalker, Vector2i(0, 1))
			if not mv.visible or mv.process_mode != Node.PROCESS_MODE_INHERIT:
				push_error("FAIL: Exiting '%s' did not restore warm MapViewer" % iid)
				_cleanup([iv, mv, main_node])
				return false
			var ret_local := CaricatureWalkerGrid.global_to_local(comp, walker.grid_pos.x, walker.grid_pos.y)
			if mv.get_current_walk_area_id() != aid or ret_local != Vector2i(dx, dy + 1) or walker.facing != "S":
				push_error("FAIL: Exiting '%s' landed wrong: area=%s local=%s (expected %s) facing=%s" % [
					iid, mv.get_current_walk_area_id(), str(ret_local), str(Vector2i(dx, dy + 1)), walker.facing
				])
				_cleanup([mv, main_node])
				return false

	if unique_interiors.size() != 94:
		push_error("FAIL: Expected 94 unique DC interiors tested, got %d" % unique_interiors.size())
		_cleanup([mv, main_node])
		return false
	if not ordinary_door_tested:
		push_error("FAIL: Ordinary door falsifier was never exercised")
		_cleanup([mv, main_node])
		return false

	# 2. Multi-floor stairs, switch gate opening, 8-frame/tile gust slide & 3F warp on dc:washington-monument
	var nm_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:national-mall"]
	var wm_door := Vector2i(33, 52)
	for d_v in nm_comp.get("doors", []):
		if d_v is Dictionary and str((d_v as Dictionary).get("interior", "")) == "dc:washington-monument":
			wm_door = Vector2i(int((d_v as Dictionary)["x"]), int((d_v as Dictionary)["y"]))
			break
	mv.place_player_in_area("hood:washington-dc:national-mall", Vector2i(wm_door.x, wm_door.y + 1), "N")
	var iv_wm: InteriorView = main_node.enter_interior_from_map(mv, "dc:washington-monument", {
		"place_id": "city:washington-dc",
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": wm_door.x,
		"return_y": wm_door.y + 1,
	}, 0, Vector2i(-1, -1), "N", self)
	if iv_wm == null:
		push_error("FAIL: Could not enter dc:washington-monument")
		_cleanup([mv, main_node])
		return false
	var w_wm: PlayerWalker = iv_wm.get_player_walker()
	w_wm.live_input_enabled = false

	# 2a. Switch sw_monument_lift at [3, 7] opens gate_monument_lift at [8, 4]
	if iv_wm.is_tile_passable_for_walker(8, 5):
		push_error("FAIL: gate_monument_lift should block (8, 5) before switch is flipped")
		_cleanup([iv_wm, mv, main_node])
		return false
	w_wm.place_at(Vector2i(3, 8), "N")
	iv_wm.trigger_interact_for_walker()
	if not iv_wm.is_tile_passable_for_walker(8, 5):
		push_error("FAIL: Flipping sw_monument_lift did not open gate_monument_lift!")
		_cleanup([iv_wm, mv, main_node])
		return false

	# 2b. Step onto 1F stair [15, 1] -> transitions to 2F at [15, 2]
	w_wm.place_at(Vector2i(15, 2), "N")
	_step_walker(w_wm, Vector2i(0, -1))
	if iv_wm.get_floor_index() != 1 or iv_wm.get_player_walker().grid_pos != Vector2i(15, 2):
		push_error("FAIL: 1F stair failed: floor=%d pos=%s" % [iv_wm.get_floor_index(), str(iv_wm.get_player_walker().grid_pos)])
		_cleanup([iv_wm, mv, main_node])
		return false

	# 2c. 2F gust arrows >>>> at (3..6, 3): stepping from (2, 3) East onto (3, 3) slides 4 tiles to (7, 3) at exact 8 frames/tile (32/60 s)
	w_wm = iv_wm.get_player_walker()
	w_wm.live_input_enabled = false
	w_wm.place_at(Vector2i(2, 3), "E")
	_step_walker(w_wm, Vector2i(1, 0)) # steps onto (3, 3), which starts forced slide to (7, 3) (4 tiles * 8/60 s = 32/60 s)
	if not w_wm.is_moving():
		push_error("FAIL: Stepping onto gust arrow (3, 3) did not start forced slide!")
		_cleanup([iv_wm, mv, main_node])
		return false
	# Halfway through 4-tile slide (16/60 s) must still be sliding
	w_wm.step_simulation(16.0 / 60.0, Vector2i.ZERO, false)
	if not w_wm.is_moving():
		push_error("FAIL: Gust slide finished too fast (expected 4 * 8/60 s = 32/60 s)")
		_cleanup([iv_wm, mv, main_node])
		return false
	w_wm.step_simulation(16.0 / 60.0 + 0.002, Vector2i.ZERO, false)
	if w_wm.is_moving() or w_wm.grid_pos != Vector2i(7, 3):
		push_error("FAIL: Gust slide did not land at (7, 3), pos=%s moving=%s" % [str(w_wm.grid_pos), str(w_wm.is_moving())])
		_cleanup([iv_wm, mv, main_node])
		return false

	# 2d. Climb 2F stair [2, 1] -> 3F [2, 2], then step onto 3F warp [14, 8] -> 1F [10, 9]
	w_wm.place_at(Vector2i(2, 2), "N")
	_step_walker(w_wm, Vector2i(0, -1))
	if iv_wm.get_floor_index() != 2:
		push_error("FAIL: 2F -> 3F stair failed: floor=%d" % iv_wm.get_floor_index())
		_cleanup([iv_wm, mv, main_node])
		return false
	w_wm = iv_wm.get_player_walker()
	w_wm.live_input_enabled = false
	w_wm.place_at(Vector2i(14, 9), "N")
	_step_walker(w_wm, Vector2i(0, -1))
	if iv_wm.get_floor_index() != 0 or iv_wm.get_player_walker().grid_pos != Vector2i(10, 9):
		push_error("FAIL: 3F warp pad -> 1F [10, 9] failed: floor=%d pos=%s" % [iv_wm.get_floor_index(), str(iv_wm.get_player_walker().grid_pos)])
		_cleanup([iv_wm, mv, main_node])
		return false

	# 3. Indoor quit & resume preserves exact interior floor, tile, AND exterior doorstep on exit!
	var sess_in: Dictionary = DB.get_player_session()
	if str(sess_in.get("interior_id", "")) != "dc:washington-monument" or int(sess_in.get("interior_x", -1)) != 10 or int(sess_in.get("interior_y", -1)) != 9:
		push_error("FAIL: Indoor player_session not persisted cleanly: %s" % str(sess_in))
		_cleanup([iv_wm, mv, main_node])
		return false
	_cleanup([iv_wm, mv, main_node]) # closes DB; wait — re-open without deleting DB!
	# Actually test indoor resume directly without deleting DB:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	DB.upsert_neighbourhood_state("hood:washington-dc:national-mall", "city:washington-dc", 2, "pick", now)
	DB.set_db_meta("last_place", "city:washington-dc")
	DB.save_player_session({
		"place_id": "city:washington-dc",
		"area_id": "hood:washington-dc:national-mall",
		"tile_x": wm_door.x,
		"tile_y": wm_door.y + 1,
		"facing": "W",
		"interior_id": "dc:washington-monument",
		"interior_floor": 1,
		"interior_x": 10,
		"interior_y": 10,
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": wm_door.x,
		"return_y": wm_door.y + 1,
		"route_origin_area_id": "",
		"active_route_id": "",
		"route_time_accum_milli": 0,
		"route_time_charged_min": 0,
	})
	DB.close()
	DB.init_db()

	var main_res: Node2D = MainScript.new()
	var iv_res: InteriorView = main_res.resume_from_session(true, self) as InteriorView
	var warm_mv: Node = main_res._warm_map_view
	if iv_res == null or iv_res.get_floor_index() != 1 or iv_res.get_player_walker() == null or iv_res.get_player_walker().grid_pos != Vector2i(10, 10) or iv_res.get_player_walker().facing != "W":
		push_error("FAIL: Indoor resume did not restore floor=1 tile=(10,10) facing=W")
		_cleanup([iv_res, warm_mv, main_res])
		return false
	# Now move to 1F door_mat and step South -> must exit onto exact exterior doorstep!
	iv_res.switch_floor(0, Vector2i(8, 11), "S")
	var w_res: PlayerWalker = iv_res.get_player_walker()
	w_res.live_input_enabled = false
	_step_walker(w_res, Vector2i(0, 1))
	if warm_mv == null or not warm_mv.visible:
		push_error("FAIL: Exiting after indoor resume did not restore MapViewer")
		_cleanup([iv_res, warm_mv, main_res])
		return false
	var nm_comp2: Dictionary = warm_mv._caricature_compiled_by_area["hood:washington-dc:national-mall"]
	var res_ext_local := CaricatureWalkerGrid.global_to_local(nm_comp2, warm_mv.get_player_walker().grid_pos.x, warm_mv.get_player_walker().grid_pos.y)
	if res_ext_local != Vector2i(wm_door.x, wm_door.y + 1) or warm_mv.get_player_walker().facing != "S":
		push_error("FAIL: Exiting after indoor resume landed at %s (expected %s)" % [str(res_ext_local), str(Vector2i(wm_door.x, wm_door.y + 1))])
		_cleanup([warm_mv, main_res])
		return false

	_cleanup([warm_mv, main_res])
	return true
