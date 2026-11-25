extends Node

## game/tests/time_of_day_test.gd — Item 74 Day/Dusk/Night Shader, Walking HUD & --walk-bench Budget Tests
## Contract: Decision 79 (F79, F81) & Decision 80; docs/implementation_plan_travel_and_time.md §(i), §(k), §(m)

const MapViewerScript := preload("res://world/map_view.gd")
const MapViewerScene := preload("res://world/map_view.tscn")
const InteriorView := preload("res://world/interior/interior_view.gd")
const ScreenshotConfig := preload("res://scripts/screenshot_config.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

func _fail(msg: String) -> bool:
	push_error("time_of_day_test: " + msg)
	return false

func _approx(a: float, b: float, eps: float = 0.015) -> bool:
	return absf(a - b) <= eps

func _cleanup_db(base_path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".tmp", ".jsonbak"]:
		var abs_p := ProjectSettings.globalize_path(base_path + suffix)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)

func run_test() -> bool:
	# 1. Shader resource exists and loads cleanly
	if not ResourceLoader.exists("res://world/shaders/time_of_day.gdshader"):
		return _fail("missing res://world/shaders/time_of_day.gdshader")
	var sh := load("res://world/shaders/time_of_day.gdshader")
	if sh == null or not (sh is Shader):
		return _fail("failed to load time_of_day.gdshader as Shader")

	# 2. Pure CPU formula checks (exact mirror of time_of_day.gdshader)
	# Day (12:00 = 720, 08:00 = 480): 100% untouched (alpha == 0.0)
	var c_day_noon: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 720.0, Vector2(0.0, 0.0), true, [])
	if not _approx(c_day_noon.a, 0.0, 0.001):
		return _fail("day 12:00 must be untouched (alpha=0.0), got %s" % str(c_day_noon))
	var c_day_8am: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 480.0, Vector2(0.0, 0.0), true, [])
	if not _approx(c_day_8am.a, 0.0, 0.001):
		return _fail("day 08:00 must be untouched (alpha=0.0), got %s" % str(c_day_8am))

	# Dawn (06:00 = 360): rgb(245, 195, 165), strength 0.14; 07:00 = 420 midpoint (~0.07)
	var c_dawn: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 360.0, Vector2(0.0, 0.0), true, [])
	if not _approx(c_dawn.a, 0.14) or not _approx(c_dawn.r, 245.0 / 255.0) or not _approx(c_dawn.g, 195.0 / 255.0) or not _approx(c_dawn.b, 165.0 / 255.0):
		return _fail("dawn 06:00 mismatch: got %s" % str(c_dawn))
	var c_dawn_mid: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 420.0, Vector2(0.0, 0.0), true, [])
	if not (c_dawn_mid.a > 0.03 and c_dawn_mid.a < 0.11):
		return _fail("dawn->day 07:00 15-min blend expected ~0.07, got %.3f" % c_dawn_mid.a)

	# Dusk (20:00 = 1200): rgb(220, 145, 120), strength 0.24; 19:00 = 1140 midpoint (~0.12)
	var c_dusk: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 1200.0, Vector2(0.0, 0.0), true, [])
	if not _approx(c_dusk.a, 0.24) or not _approx(c_dusk.r, 220.0 / 255.0) or not _approx(c_dusk.g, 145.0 / 255.0) or not _approx(c_dusk.b, 120.0 / 255.0):
		return _fail("dusk 20:00 mismatch: got %s" % str(c_dusk))
	var c_dusk_mid: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(14.0, 0.0), 1140.0, Vector2(0.0, 0.0), true, [])
	if not (c_dusk_mid.a > 0.05 and c_dusk_mid.a < 0.19):
		return _fail("day->dusk 19:00 15-min blend expected ~0.12, got %.3f" % c_dusk_mid.a)

	# Night (23:00 = 1380 & 02:00 = 120): Emerald 4.5-tile Flash circle (<=4.0 lit, 4.0..5.0 blend, >=5.0 dimmed 62% toward rgb(22,30,62))
	for night_min in [1380.0, 120.0]:
		var c_in: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(3.9, 0.0), night_min, Vector2(0.0, 0.0), true, [])
		var c_edge4: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(4.0, 0.0), night_min, Vector2(0.0, 0.0), true, [])
		var c_mid45: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(4.5, 0.0), night_min, Vector2(0.0, 0.0), true, [])
		var c_out5: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(5.0, 0.0), night_min, Vector2(0.0, 0.0), true, [])
		var c_far: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(12.0, 0.0), night_min, Vector2(0.0, 0.0), true, [])
		if not _approx(c_in.a, 0.0, 0.001) or not _approx(c_edge4.a, 0.0, 0.001):
			return _fail("night <=4.0 tiles must be fully lit, got d=3.9:%s d=4.0:%s" % [str(c_in), str(c_edge4)])
		if not _approx(c_mid45.a, 0.31, 0.02):
			return _fail("night d=4.5 tiles expected midpoint alpha ~0.31, got %.3f" % c_mid45.a)
		if not _approx(c_out5.a, 0.62, 0.005) or not _approx(c_far.a, 0.62, 0.005):
			return _fail("night >=5.0 tiles expected alpha 0.62, got d=5:%s d=12:%s" % [str(c_out5), str(c_far)])
		if not _approx(c_far.r, 22.0 / 255.0) or not _approx(c_far.g, 30.0 / 255.0) or not _approx(c_far.b, 62.0 / 255.0):
			return _fail("night indigo tint expected rgb(22,30,62), got %s" % str(c_far))

	# 3. World-tile radius invariance across zoom 2.0 vs 1.0 (960x640 viewport)
	var cam := Vector2(50.0, 50.0)
	var vp := Vector2(960.0, 640.0)
	var uv_z2_4t := Vector2(0.5 + 4.0 / 15.0, 0.5)
	var uv_z2_5t := Vector2(0.5 + 5.0 / 15.0, 0.5)
	var uv_z1_4t := Vector2(0.5 + 4.0 / 30.0, 0.5)
	var uv_z1_5t := Vector2(0.5 + 5.0 / 30.0, 0.5)
	var wt_z2_4: Vector2 = MapViewerScript.screen_uv_to_world_tile(uv_z2_4t, cam, vp, 2.0)
	var wt_z2_5: Vector2 = MapViewerScript.screen_uv_to_world_tile(uv_z2_5t, cam, vp, 2.0)
	var wt_z1_4: Vector2 = MapViewerScript.screen_uv_to_world_tile(uv_z1_4t, cam, vp, 1.0)
	var wt_z1_5: Vector2 = MapViewerScript.screen_uv_to_world_tile(uv_z1_5t, cam, vp, 1.0)
	if not _approx(wt_z2_4.distance_to(cam), 4.0, 0.01) or not _approx(wt_z1_4.distance_to(cam), 4.0, 0.01):
		return _fail("4.0-tile world mapping mismatch across zoom 2 vs 1: %s / %s" % [str(wt_z2_4), str(wt_z1_4)])
	if not _approx(wt_z2_5.distance_to(cam), 5.0, 0.01) or not _approx(wt_z1_5.distance_to(cam), 5.0, 0.01):
		return _fail("5.0-tile world mapping mismatch across zoom 2 vs 1: %s / %s" % [str(wt_z2_5), str(wt_z1_5)])
	# Same screen UV (uv_z2_4t) is 4.0 tiles (lit) at zoom 2.0, but 8.0 tiles (dimmed 0.62) at zoom 1.0!
	var wt_same_uv_z1: Vector2 = MapViewerScript.screen_uv_to_world_tile(uv_z2_4t, cam, vp, 1.0)
	var c_same_z2: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(wt_z2_4, 1380.0, cam, true, [])
	var c_same_z1: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(wt_same_uv_z1, 1380.0, cam, true, [])
	if not (_approx(c_same_z2.a, 0.0, 0.001) and _approx(c_same_z1.a, 0.62, 0.005)):
		return _fail("Flash circle must scale in world tiles (not fixed screen px): z2=%s z1=%s" % [str(c_same_z2), str(c_same_z1)])

	# 4. Lamp 3.5-tile glow pool at night
	var lamps: Array = [Vector2(10.0, 0.0)]
	var c_at_lamp: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(10.0, 0.0), 1380.0, Vector2(0.0, 0.0), true, lamps)
	var c_past_lamp: Color = MapViewerScript.evaluate_time_of_day_at_world_tile(Vector2(13.6, 0.0), 1380.0, Vector2(0.0, 0.0), true, lamps)
	if not (c_at_lamp.a < 0.30 and c_at_lamp.r > c_past_lamp.r):
		return _fail("lamp glow pool did not brighten/warm tile at lamp: at=%s past=%s" % [str(c_at_lamp), str(c_past_lamp)])
	if not _approx(c_past_lamp.a, 0.62, 0.005):
		return _fail("tile beyond 3.5-tile lamp pool must return to full 0.62 night dim, got %s" % str(c_past_lamp))

	# 5. Live MapViewer HUD & layer order + InteriorView untouched
	var db_path := "user://test/time_of_day_test.db"
	_cleanup_db(db_path)
	DB.configure_paths(db_path, "user://test/time_of_day_test.tmp")
	DB.init_db()
	DB.assert_test_safe()
	DB.set_db_meta("starter_place", "city:washington-dc")
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	NeighbourhoodProgress.set_demo_override_for_tests(1)
	NeighbourhoodProgress.demo_force_open(DB, "hood:washington-dc:georgetown")

	var mv = MapViewerScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", false):
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("load_place failed for DC")

	var tod_layer := mv.get_node_or_null("TimeOfDayLayer") as CanvasLayer
	var attr_ui := mv.get_node_or_null("AttributionUI") as CanvasLayer
	if tod_layer == null or tod_layer.layer != 5:
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("TimeOfDayLayer missing or wrong layer (expected 5)")
	if attr_ui == null or attr_ui.layer <= tod_layer.layer:
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("AttributionUI layer (%d) must be strictly above TimeOfDayLayer (%d)" % [attr_ui.layer if attr_ui != null else -1, tod_layer.layer])

	mv.enable_walk_mode("camp:washington-dc", Vector2i(31, 26), "S")
	mv.get_world_clock().set_minutes(720)
	mv.refresh_time_of_day_and_hud()
	var camp_hud: String = mv.get_walk_hud_text()
	if not ("12:00" in camp_hud and "Day" in camp_hud and "Wilson Building Waypost" in camp_hud):
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("camp walk HUD missing time/band/name: '%s'" % camp_hud)
	if "Wild Lv." in camp_hud:
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("camp walk HUD must omit Wild Lv. (no tall grass in camp): '%s'" % camp_hud)

	mv.place_player_in_area("hood:washington-dc:georgetown", Vector2i(-1, -1), "S", false)
	mv.get_world_clock().set_minutes(1380)
	mv.refresh_time_of_day_and_hud()
	var gt_hud: String = mv.get_walk_hud_text()
	if not ("23:00" in gt_hud and "Night" in gt_hud and "Georgetown" in gt_hud and "Wild Lv. 8–22" in gt_hud):
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("Georgetown night walk HUD mismatch: '%s'" % gt_hud)

	var iv := InteriorView.new()
	add_child(iv)
	iv.load_interior("dc:georgetown-ruins", 0, "user://__no_rom__", true)
	if iv.get_node_or_null("TimeOfDayLayer") != null:
		iv.queue_free()
		NeighbourhoodProgress.set_demo_override_for_tests(-1)
		mv.queue_free()
		DB.close()
		_cleanup_db(db_path)
		return _fail("InteriorView must NOT have outdoor TimeOfDayLayer")
	iv.queue_free()

	mv.queue_free()
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	DB.close()
	_cleanup_db(db_path)

	# 6. Demo-only --walk-bench & --walk-shot refusal + frame budget falsifier (standing constraint 22, §(m))
	var repo_root := ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var r_wb_nodemo: Dictionary = ScreenshotConfig.parse_args(["--walk-bench"], false, repo_root)
	if r_wb_nodemo.get("ok", true) != false or int(r_wb_nodemo.get("exit_code", 0)) != 2 or str(r_wb_nodemo.get("error", "")) != ScreenshotConfig.ERR_WALK_BENCH_NEEDS_DEMO:
		return _fail("--walk-bench without --demo must fail with exit 2: %s" % str(r_wb_nodemo))

	var r_wb_headless: Dictionary = ScreenshotConfig.parse_args(["--demo", "--walk-bench"], true, repo_root)
	if r_wb_headless.get("ok", true) != false or int(r_wb_headless.get("exit_code", 0)) != 2:
		return _fail("--walk-bench headless must fail with exit 2: %s" % str(r_wb_headless))

	var r_wb_ok: Dictionary = ScreenshotConfig.parse_args(["--demo", "--walk-bench", "--zoom=2", "--no-rom"], false, repo_root)
	if not bool(r_wb_ok.get("ok", false)) or not bool(r_wb_ok.get("is_walk_bench", false)) or not _approx(float(r_wb_ok.get("zoom", 0.0)), 2.0, 0.001) or not bool(r_wb_ok.get("no_rom", false)):
		return _fail("valid --demo --walk-bench --zoom=2 --no-rom failed: %s" % str(r_wb_ok))

	var r_ws_nodemo: Dictionary = ScreenshotConfig.parse_args(["--walk-shot=night", "--screenshot=/tmp/out_ws.png"], false, repo_root)
	if r_ws_nodemo.get("ok", true) != false or int(r_ws_nodemo.get("exit_code", 0)) != 2 or str(r_ws_nodemo.get("error", "")) != ScreenshotConfig.ERR_WALK_SHOT_NEEDS_DEMO:
		return _fail("--walk-shot without --demo must fail with exit 2: %s" % str(r_ws_nodemo))

	var r_ws_ok: Dictionary = ScreenshotConfig.parse_args(["--demo", "--walk-shot=night", "--time=1380", "--sprite=1", "--zoom=2", "--screenshot=/tmp/out_ws.png"], false, repo_root)
	if not bool(r_ws_ok.get("ok", false)) or str(r_ws_ok.get("walk_shot", "")) != "night" or int(r_ws_ok.get("time_minutes", -1)) != 1380 or int(r_ws_ok.get("sprite_index", -1)) != 1:
		return _fail("valid --walk-shot config failed: %s" % str(r_ws_ok))

	# Frame budget falsifier: <=16.7 steady & <=33.4 seam/door passes; injected >33.4 or >16.7 FAILS
	var b_pass: Dictionary = ScreenshotConfig.evaluate_walk_bench_budget(16.67, 24.5, 29.0, 18.2)
	if not bool(b_pass.get("ok", false)):
		return _fail("valid bench budget failed unexpectedly: %s" % str(b_pass))
	var b_fail_seam: Dictionary = ScreenshotConfig.evaluate_walk_bench_budget(16.67, 35.1, 20.0, 18.0)
	if bool(b_fail_seam.get("ok", true)):
		return _fail("synthetic seam frame 35.1ms (>33.4ms) must FAIL budget")
	var b_fail_p95: Dictionary = ScreenshotConfig.evaluate_walk_bench_budget(17.5, 20.0, 20.0, 18.0)
	if bool(b_fail_p95.get("ok", true)):
		return _fail("synthetic steady P95 17.5ms (>16.7ms) must FAIL budget")

	print("time_of_day_test checks passed")
	return true
