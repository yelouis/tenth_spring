extends Node

## game/tests/local_origin_test.gd — Item 75 (F88, F89) Local Map Render Origin Falsifiers
## Contract: Decision 81 Item 75 (F88 y-sort depth ties & F89 32-bit float shake)

const MapViewerScene := preload("res://world/map_view.tscn")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const PlayerWalker := preload("res://world/player_walker.gd")

const TEST_DB_PATH := "user://test/local_origin_test.db"
const TEST_TMP_PATH := "user://test/local_origin_test.db.tmp"
const MAX_ALLOWED_ABS_PX := 1000000.0

func _fail(msg: String) -> bool:
	push_error("local_origin_test: " + msg)
	return false

func _cleanup_db() -> void:
	DB.close()
	for suffix in ["", "-wal", "-shm", ".tmp", ".jsonbak"]:
		var abs_p := ProjectSettings.globalize_path(TEST_DB_PATH + suffix)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _check_tree_positions_under_limit(node: Node, violations: Array[String]) -> void:
	if node is CanvasLayer:
		return
	if node is Node2D:
		var p: Vector2 = (node as Node2D).position
		if absf(p.x) > MAX_ALLOWED_ABS_PX or absf(p.y) > MAX_ALLOWED_ABS_PX:
			violations.append("%s pos=%s" % [node.name, str(p)])
	elif node is Control:
		var cp: Vector2 = (node as Control).position
		if absf(cp.x) > MAX_ALLOWED_ABS_PX or absf(cp.y) > MAX_ALLOWED_ABS_PX:
			violations.append("%s pos=%s" % [node.name, str(cp)])
	for ch in node.get_children():
		_check_tree_positions_under_limit(ch, violations)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		return _fail("DB.assert_test_safe failed")
	_cleanup_db()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	DB.set_db_meta("starter_place", "city:washington-dc")
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	NeighbourhoodProgress.set_demo_override_for_tests(1)
	NeighbourhoodProgress.demo_force_open(DB, "hood:washington-dc:national-mall")
	NeighbourhoodProgress.demo_force_open(DB, "hood:washington-dc:dupont-circle")

	var mv = MapViewerScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", false):
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("load_place failed for city:washington-dc")

	var origin_tile: Vector2i = mv.get_render_origin_tile()
	if origin_tile == Vector2i.ZERO:
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("render origin tile for city:washington-dc must be non-zero local origin")

	mv.enable_walk_mode("camp:washington-dc", Vector2i(31, 26), "S")
	mv.set_walk_zoom(2.0)
	var walker: PlayerWalker = mv.get_player_walker()
	walker.live_input_enabled = false
	walker.set_process(false)

	# 0. Process priority ensures live PlayerWalker updates before MapViewer camera follow (zero 1-frame lag)
	if walker.process_priority >= mv.process_priority:
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("PlayerWalker.process_priority (%d) must be < MapViewer.process_priority (%d)" % [walker.process_priority, mv.process_priority])

	# 1. Falsifier (F88): Standing just south of camp lamp, Jude, Mall dex 10, camp bench, and camp cherry tree:
	# render containing cells synchronously and assert EVERY base sprite north of the player sorts strictly behind
	# (not Math::is_equal_approx!) and no node in the drawn tree exceeds 1,000,000 px from zero.
	var f88_spots := [
		["camp_lamp", "camp:washington-dc", Vector2i(31, 26), Vector2i(31, 25)],
		["camp_jude", "camp:washington-dc", Vector2i(29, 27), Vector2i(29, 26)],
		["mall_dex10", "hood:washington-dc:national-mall", Vector2i(61, 37), Vector2i(61, 36)],
		["camp_bench", "camp:washington-dc", Vector2i(28, 23), Vector2i(28, 22)],
		["camp_cherry", "camp:washington-dc", Vector2i(26, 19), Vector2i(26, 18)],
	]
	var base_layer: Node2D = mv.get_node_or_null("StampBaseLayer") as Node2D
	for spot in f88_spots:
		var lbl: String = spot[0]
		var aid: String = spot[1]
		var stand_l: Vector2i = spot[2]
		var obj_l: Vector2i = spot[3]
		mv.place_player_in_area(aid, stand_l, "S", false)
		var comp: Dictionary = mv._caricature_compiled_by_area[aid]
		var obj_g: Vector2i = CaricatureWalkerGrid.local_to_global(comp, obj_l.x, obj_l.y)
		var obj_cell: Vector2i = CaricatureWalkerGrid.global_tile_to_cell(obj_g.x, obj_g.y)
		mv._render_cell(obj_cell.x, obj_cell.y)
		var expected_obj_foot_y: float = float(obj_g.y - origin_tile.y + 1) * 32.0
		var player_y: float = walker.position.y
		if is_equal_approx(expected_obj_foot_y, player_y) or not (expected_obj_foot_y < player_y):
			mv.queue_free()
			NeighbourhoodProgress.set_demo_override_for_tests(-1)
			_cleanup_db()
			return _fail("F88 %s: Godot is_equal_approx y-sort tie or wrong order! obj_y=%.2f player_y=%.2f" % [lbl, expected_obj_foot_y, player_y])
		# Verify at least one base sprite exists for non-Pokemon objects (under --no-rom dex 10 icon is omitted)
		if lbl != "mall_dex10":
			var found_base := false
			var obj_rx: float = float(obj_g.x - origin_tile.x) * 32.0
			for ch in base_layer.get_children():
				if ch is Sprite2D:
					var sp := ch as Sprite2D
					if absf(sp.position.y - expected_obj_foot_y) < 0.5 and absf(sp.position.x - obj_rx) <= 32.5:
						found_base = true
						if is_equal_approx(sp.position.y, player_y) or not (sp.position.y < player_y):
							mv.queue_free()
							NeighbourhoodProgress.set_demo_override_for_tests(-1)
							_cleanup_db()
							return _fail("F88 %s sprite y-sort tie: sp_y=%.2f player_y=%.2f" % [lbl, sp.position.y, player_y])
						break
			if not found_base:
				mv.queue_free()
				NeighbourhoodProgress.set_demo_override_for_tests(-1)
				_cleanup_db()
				return _fail("F88 %s: expected base sprite at render_y=%.1f near x=%.1f" % [lbl, expected_obj_foot_y, obj_rx])

	# Also verify distortion field rect + overview chunks + fog overlay stay < 1,000,000 px from zero
	var camp_comp: Dictionary = mv._caricature_compiled_by_area["camp:washington-dc"]
	var camp_orig: Vector2i = camp_comp["origin"]
	mv.set_active_distortion_field({
		"active": true,
		"min_cell": camp_orig,
		"max_cell": camp_orig + Vector2i(1, 1),
		"chip_text": "Test Distortion",
	})
	mv._update_fog_overlay_rect()
	mv.refresh_time_of_day_and_hud()
	var violations: Array[String] = []
	_check_tree_positions_under_limit(mv, violations)
	if not violations.is_empty():
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("Drawn nodes exceeded 1,000,000 px from zero: %s" % ", ".join(PackedStringArray(violations)))

	# Verify camera cell inverse mapping still returns global DC cell
	mv.place_player_in_area("camp:washington-dc", Vector2i(31, 26), "S", false)
	var exp_camp_g := CaricatureWalkerGrid.local_to_global(camp_comp, 31, 26)
	var exp_camp_cell := CaricatureWalkerGrid.global_tile_to_cell(exp_camp_g.x, exp_camp_g.y)
	var got_cam_cell: Vector2i = mv.get_camera_cell()
	if got_cam_cell != exp_camp_cell:
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("get_camera_cell mismatch: expected %s, got %s" % [str(exp_camp_cell), str(got_cam_cell)])

	# Verify night overlay uniforms use local render tiles so player & lamp distances match global distance
	mv.set_time_of_day_override(1380.0)
	mv.refresh_time_of_day_and_hud()
	var tod_rect: ColorRect = mv.get_node_or_null("TimeOfDayLayer/TimeOfDayRect") as ColorRect
	var tod_mat: ShaderMaterial = tod_rect.material as ShaderMaterial
	var u_cam: Vector2 = tod_mat.get_shader_parameter("cam_center_tiles")
	var u_player: Vector2 = tod_mat.get_shader_parameter("player_world_tiles")
	var u_lamp_cnt: int = int(tod_mat.get_shader_parameter("lamp_count"))
	var u_lamps: Array = tod_mat.get_shader_parameter("lamp_world_tiles")
	if absf(u_cam.x) > 5000.0 or absf(u_player.x) > 5000.0 or u_lamp_cnt < 1:
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("Night shader uniforms not in local origin space: cam=%s player=%s lamps=%d" % [str(u_cam), str(u_player), u_lamp_cnt])
	var lamp_pos_l: Vector2i = camp_comp["lamp"]
	var lamp_g := CaricatureWalkerGrid.local_to_global(camp_comp, lamp_pos_l.x, lamp_pos_l.y)
	var exp_lamp_render := Vector2(float(lamp_g.x - origin_tile.x) + 0.5, float(lamp_g.y - origin_tile.y) - 0.25)
	var matched_lamp := false
	for i in range(u_lamp_cnt):
		if (u_lamps[i] as Vector2).distance_to(exp_lamp_render) < 0.05:
			matched_lamp = true
			break
	if not matched_lamp:
		mv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		_cleanup_db()
		return _fail("Night shader lamp_world_tiles missing camp lamp at render tile %s" % str(exp_lamp_render))

	# 2. Falsifier (F89): Walking 3 tiles (48 frames) & running 3 tiles (24 frames) in all 4 directions at zoom 2:
	# Player on-screen position changes 0 px every frame; fixed map point moves exact 4 px/frame walking, 8 px/frame running.
	var fixed_g := CaricatureWalkerGrid.local_to_global(camp_comp, 31, 29)
	var fixed_render_px := Vector2(float(fixed_g.x - origin_tile.x) * 32.0, float(fixed_g.y - origin_tile.y) * 32.0)
	var vp_half := Vector2(480.0, 320.0)
	var shake_cases := [
		["walk", "E", Vector2i(29, 27), Vector2i(1, 0), false, 48],
		["walk", "W", Vector2i(32, 27), Vector2i(-1, 0), false, 48],
		["walk", "S", Vector2i(34, 26), Vector2i(0, 1), false, 48],
		["walk", "N", Vector2i(34, 29), Vector2i(0, -1), false, 48],
		["run", "E", Vector2i(29, 27), Vector2i(1, 0), true, 24],
		["run", "W", Vector2i(32, 27), Vector2i(-1, 0), true, 24],
		["run", "S", Vector2i(34, 26), Vector2i(0, 1), true, 24],
		["run", "N", Vector2i(34, 29), Vector2i(0, -1), true, 24],
	]
	for sc in shake_cases:
		var mode_s: String = sc[0]
		var dir_s: String = sc[1]
		var start_l: Vector2i = sc[2]
		var dir_v: Vector2i = sc[3]
		var is_run: bool = sc[4]
		var n_frames: int = sc[5]
		mv.place_player_in_area("camp:washington-dc", start_l, dir_s, false)
		var start_g: Vector2i = walker.grid_pos
		var cam0: Vector2 = mv._camera.position
		var xform0 := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, -cam0 * 2.0 + vp_half)
		var prev_p: Vector2 = xform0 * walker.position
		var prev_m: Vector2 = xform0 * fixed_render_px
		var exp_step: float = 8.0 if is_run else 4.0
		var exp_dm := Vector2(-float(dir_v.x) * exp_step, -float(dir_v.y) * exp_step)
		for f in range(n_frames):
			walker.step_simulation(1.0 / 60.0, dir_v, is_run)
			# Camera must ALREADY be updated via visual_position_updated signal without manual copy!
			var cam_cur: Vector2 = mv._camera.position
			var xform := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, -cam_cur * 2.0 + vp_half)
			var cur_p: Vector2 = xform * walker.position
			var cur_m: Vector2 = xform * fixed_render_px
			var dp: Vector2 = cur_p - prev_p
			var dm: Vector2 = cur_m - prev_m
			prev_p = cur_p
			prev_m = cur_m
			if dp.length() > 0.01:
				mv.queue_free()
				NeighbourhoodProgress.set_demo_override_for_tests(-1)
				_cleanup_db()
				return _fail("F89 %s %s frame %d: player shifted %.2f px on screen (expected 0)" % [mode_s, dir_s, f, dp.length()])
			if (dm - exp_dm).length() > 0.01:
				mv.queue_free()
				NeighbourhoodProgress.set_demo_override_for_tests(-1)
				_cleanup_db()
				return _fail("F89 %s %s frame %d: map moved %s (expected %s)" % [mode_s, dir_s, f, str(dm), str(exp_dm)])
		var moved: int = absi(walker.grid_pos.x - start_g.x) + absi(walker.grid_pos.y - start_g.y)
		if moved != 3:
			mv.queue_free()
			NeighbourhoodProgress.set_demo_override_for_tests(-1)
			_cleanup_db()
			return _fail("F89 %s %s moved %d tiles (expected 3)" % [mode_s, dir_s, moved])

	mv.queue_free()
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	_cleanup_db()
	print("local_origin_test checks passed")
	return true
