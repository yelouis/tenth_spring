extends Node2D

const ProfilePaths := preload("res://scripts/profile_paths.gd")
const ScreenshotConfig := preload("res://scripts/screenshot_config.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Grid := preload("res://world/grid.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")
const WorldClock := preload("res://world/world_clock.gd")
const PlayerWalker := preload("res://world/player_walker.gd")

var _warm_map_view: Node = null

# Demo-only Item 74 --walk-bench & --walk-shot harness state (standing constraint 22)
var _wb_active: bool = false
var _wb_phase: String = ""
var _wb_mv: Node = null
var _wb_iv: InteriorView = null
var _wb_plan: Dictionary = {}
var _wb_step_idx: int = 0
var _wb_warmup_frames: int = 0
var _wb_zoom: float = 2.0
var _wb_walk_deltas: Array[float] = []
var _wb_seam_max_ms: float = 0.0
var _wb_seam_watch_frames: int = 0
var _wb_door_enter_max_ms: float = 0.0
var _wb_door_exit_max_ms: float = 0.0
var _wb_door_watch_frames: int = 0
var _wb_indoor_steps_north: int = 0
var _wb_indoor_returning: bool = false
var _wb_timeout_sec: float = 120.0
var _wb_elapsed_sec: float = 0.0

var _ws_active: bool = false
var _ws_mv: Node = null
var _ws_iv: InteriorView = null
var _ws_path: String = ""
var _ws_zoom: float = 2.0
var _ws_frames_left: int = 10
var _ws_timeout_sec: float = 120.0
var _ws_elapsed_sec: float = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		for ch in get_children():
			if ch.has_method("persist_player_session"):
				ch.persist_player_session()
			if ch.has_method("get_world_clock"):
				var clk = ch.get_world_clock()
				if clk != null and clk.has_method("save_to_db"):
					clk.save_to_db()

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var is_headless := DisplayServer.get_name() == "headless" or "--headless" in OS.get_cmdline_args()
	var s_cfg: Dictionary = ScreenshotConfig.parse_args(user_args, is_headless)
	if not s_cfg.get("ok", false):
		printerr(s_cfg.get("error", "Invalid arguments"))
		get_tree().quit(s_cfg.get("exit_code", 1))
		return

	var profile: Dictionary = ProfilePaths.resolve_from_cmdline()
	if not profile.get("ok", false):
		push_error("Failed to resolve profile paths: " + str(profile.get("error", "")))
		get_tree().quit(1)
		return

	DB.configure_paths(profile.db_path, profile.db_tmp_path)
	DB.init_db()
	RevealEngine.apply(DB)

	if bool(s_cfg.get("is_walk_bench", false)):
		_start_walk_bench(s_cfg)
		return

	if s_cfg.get("is_screenshot", false) and not str(s_cfg.get("walk_shot", "")).is_empty():
		_start_walk_shot(s_cfg)
		return

	if s_cfg.get("is_screenshot", false):
		var interior_id := str(s_cfg.get("interior", ""))
		if not interior_id.is_empty():
			var use_fallback: bool = bool(s_cfg.get("interior_fallback", false)) or bool(s_cfg.get("no_rom", false))
			var iv := open_interior_view(interior_id, int(s_cfg.get("floor", 0)), use_fallback)
			if iv == null:
				printerr("[FAIL] failed to load interior %s" % interior_id)
				get_tree().quit(1)
				return
			iv.screenshot_timeout_sec = float(s_cfg.get("timeout", 120))
			iv.setup_screenshot(
				str(s_cfg.get("screenshot_path", "")),
				float(s_cfg.get("zoom", 1.0)),
				int(s_cfg.get("frames", 10)),
				str(s_cfg.get("interior_view", "whole"))
			)
			return

		if s_cfg.get("screen", "map") == "town_map":
			var town_map = open_town_map()
			if town_map != null and town_map.has_method("setup_screenshot"):
				town_map.setup_screenshot(
					str(s_cfg.get("screenshot_path", "")),
					int(s_cfg.get("frames", 10))
				)
			return

		if s_cfg.get("screen", "map") == "board":
			var board_place_id := get_resume_place_id()
			if board_place_id.is_empty():
				var starter := DB.get_db_meta("starter_place", "")
				if Neighbourhoods.is_ready(starter):
					board_place_id = starter
				else:
					for de in DB.get_all_distort_entries():
						if de is Dictionary:
							var cand_pid := str((de as Dictionary).get("place_id", ""))
							if Neighbourhoods.is_ready(cand_pid):
								board_place_id = cand_pid
								break
			if board_place_id.is_empty():
				printerr("[FAIL] --screen=board found no ready caricature city in save")
				get_tree().quit(1)
				return
			var map_view_board = open_map_view()
			if map_view_board != null:
				if not map_view_board.load_place(board_place_id, true):
					get_tree().quit(1)
					return
				if map_view_board.has_method("open_board"):
					map_view_board.open_board()
				if map_view_board.has_method("setup_screenshot"):
					map_view_board.screenshot_timeout_sec = float(s_cfg.get("timeout", 120))
					map_view_board.setup_screenshot(
						str(s_cfg.get("screenshot_path", "")),
						float(s_cfg.get("zoom", 1.0)),
						int(s_cfg.get("frames", 10)),
						"waypost"
					)
			return

		if s_cfg.get("screen", "map") == "city":
			var city_place_id := get_resume_place_id()
			if city_place_id.is_empty():
				var starter_c := DB.get_db_meta("starter_place", "")
				if Neighbourhoods.is_ready(starter_c):
					city_place_id = starter_c
				else:
					for de_c in DB.get_all_distort_entries():
						if de_c is Dictionary:
							var cand_c := str((de_c as Dictionary).get("place_id", ""))
							if Neighbourhoods.is_ready(cand_c):
								city_place_id = cand_c
								break
			if city_place_id.is_empty():
				printerr("[FAIL] --screen=city found no ready caricature city in save")
				get_tree().quit(1)
				return
			var map_view_city = open_map_view()
			if map_view_city != null:
				if not map_view_city.load_place(city_place_id, false):
					get_tree().quit(1)
					return
				if map_view_city.has_method("setup_city_screenshot"):
					map_view_city.screenshot_timeout_sec = float(s_cfg.get("timeout", 120))
					map_view_city.setup_city_screenshot(
						str(s_cfg.get("screenshot_path", "")),
						int(s_cfg.get("frames", 10)),
						city_place_id
					)
			return

		var area_id := str(s_cfg.get("area", ""))
		var no_rom := bool(s_cfg.get("no_rom", false))
		var has_tile := bool(s_cfg.get("has_tile", false))
		var tile_pos: Vector2i = s_cfg.get("tile", Vector2i(-1, -1))
		if not area_id.is_empty():
			var area_dict: Dictionary = Neighbourhoods.area(area_id)
			var area_place_id := str(area_dict.get("place_id", ""))
			var force_res := NeighbourhoodProgress.demo_force_open(DB, area_id)
			if not bool(force_res.get("ok", false)):
				printerr("[FAIL] demo_force_open failed for %s: %s" % [area_id, str(force_res.get("error", ""))])
				get_tree().quit(1)
				return
			var map_view_area = open_map_view(no_rom, has_tile, tile_pos)
			if map_view_area != null:
				if map_view_area.has_method("force_caricature_area"):
					map_view_area.force_caricature_area(area_id)
				if not area_place_id.is_empty() and map_view_area.has_method("load_place"):
					if not map_view_area.load_place(area_place_id, false):
						get_tree().quit(1)
						return
				if map_view_area.has_method("setup_screenshot"):
					map_view_area.screenshot_timeout_sec = float(s_cfg.get("timeout", 120))
					map_view_area.setup_screenshot(
						str(s_cfg.get("screenshot_path", "")),
						float(s_cfg.get("zoom", 1.0)),
						int(s_cfg.get("frames", 10)),
						str(s_cfg.get("focus", "area"))
					)
			return

		var resume_place_id := get_resume_place_id()
		var map_view = open_map_view(no_rom)
		if map_view != null:
			if not resume_place_id.is_empty() and map_view.has_method("load_place"):
				map_view.load_place(resume_place_id, false)
			if map_view.has_method("setup_screenshot"):
				map_view.screenshot_timeout_sec = float(s_cfg.get("timeout", 120))
				map_view.setup_screenshot(
					str(s_cfg.get("screenshot_path", "")),
					float(s_cfg.get("zoom", 1.0)),
					int(s_cfg.get("frames", 10)),
					str(s_cfg.get("focus", "most_visited"))
				)
		return

	var identity = PcIdentity.new()
	identity.configure_dir(profile.identity_dir)
	SyncServer.configure_identity(identity)
	SyncServer.start_server()

	# Boot and resume (explore plan §4.4 & Phase 4 §(j)):
	# - if last_place / player_session is active, resume at exact saved tile (or interior) with §5 banner;
	# - otherwise open the home hub.
	var resume_place_id := get_resume_place_id()
	if not resume_place_id.is_empty():
		resume_from_session()
	else:
		open_home_hub()

func _resolve_place_name(place_id: String) -> String:
	for p_var in RevealEngine.load_places():
		if p_var is Dictionary and str((p_var as Dictionary).get("id", "")) == place_id:
			return str((p_var as Dictionary).get("name", place_id))
	return place_id

func distort_to_place(place_id: String, force_no_rom: bool = false, host_override: Node = null) -> Node:
	if not Neighbourhoods.is_ready(place_id):
		return open_map_view_for_place(place_id)
	var host: Node = host_override if host_override != null else self
	if DB.is_open():
		NeighbourhoodProgress.ensure_camp(DB, place_id)
		DB.set_db_meta("last_place", place_id)
	if host == self:
		clear_current_view()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene == null:
		return null
	var map_view = map_view_scene.instantiate()
	if force_no_rom and map_view.has_method("set_force_no_rom"):
		map_view.set_force_no_rom(true)
	host.add_child(map_view)
	if not map_view.load_place(place_id, false):
		return null
	var city_dict: Dictionary = Neighbourhoods.city(place_id)
	var camp_dict: Dictionary = city_dict.get("camp", {}) if city_dict.get("camp") is Dictionary else {}
	var camp_id := str(camp_dict.get("id", ""))
	if map_view.has_method("enable_walk_mode"):
		map_view.enable_walk_mode(camp_id, Vector2i(-1, -1), "S")
	var pname := _resolve_place_name(place_id)
	if map_view.has_method("show_banner"):
		map_view.show_banner(map_view.format_arrival_banner(pname))
	return map_view

func resume_from_session(force_no_rom: bool = false, host_override: Node = null) -> Node:
	var resume_place_id := get_resume_place_id()
	if resume_place_id.is_empty():
		return open_home_hub() if host_override == null else null
	if not Neighbourhoods.is_ready(resume_place_id):
		return open_map_view_for_place(resume_place_id)

	var host: Node = host_override if host_override != null else self
	var sess: Dictionary = DB.get_player_session() if (DB.is_open() and DB.has_method("get_player_session")) else {}
	if host == self:
		clear_current_view()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene == null:
		return null
	var map_view = map_view_scene.instantiate()
	if force_no_rom and map_view.has_method("set_force_no_rom"):
		map_view.set_force_no_rom(true)
	host.add_child(map_view)
	if not map_view.load_place(resume_place_id, false):
		return null

	var pname := _resolve_place_name(resume_place_id)
	var sess_place := str(sess.get("place_id", ""))
	var sess_area := str(sess.get("area_id", ""))
	var has_valid_sess: bool = (sess_place == resume_place_id and not sess_area.is_empty() and bool(map_view._caricature_compiled_by_area.has(sess_area)))
	if has_valid_sess:
		var tx := int(sess.get("tile_x", -1))
		var ty := int(sess.get("tile_y", -1))
		var facing_str := str(sess.get("facing", "S"))
		map_view.enable_walk_mode(sess_area, Vector2i(tx, ty), facing_str)
		if map_view.has_method("set_route_crossing_state"):
			map_view.set_route_crossing_state(
				str(sess.get("route_origin_area_id", "")),
				str(sess.get("active_route_id", "")),
				int(sess.get("route_time_accum_milli", 0)),
				int(sess.get("route_time_charged_min", 0))
			)
		var interior_id := str(sess.get("interior_id", ""))
		if not interior_id.is_empty():
			var ifloor := int(sess.get("interior_floor", 0))
			var ipos := Vector2i(int(sess.get("interior_x", -1)), int(sess.get("interior_y", -1)))
			var ret_info := {
				"place_id": resume_place_id,
				"return_area_id": str(sess.get("return_area_id", sess_area)),
				"return_x": int(sess.get("return_x", tx)),
				"return_y": int(sess.get("return_y", ty)),
			}
			var iv := enter_interior_from_map(map_view, interior_id, ret_info, ifloor, ipos, facing_str, host)
			if iv != null:
				return iv
		map_view.show_banner(map_view.format_resume_banner(resume_place_id, sess_area, pname))
	else:
		var city_dict: Dictionary = Neighbourhoods.city(resume_place_id)
		var camp_dict: Dictionary = city_dict.get("camp", {}) if city_dict.get("camp") is Dictionary else {}
		var camp_id := str(camp_dict.get("id", ""))
		map_view.enable_walk_mode(camp_id, Vector2i(-1, -1), "S")
		map_view.show_banner(map_view.format_arrival_banner(pname))
	return map_view

func get_resume_place_id(custom_stores: Dictionary = {}) -> String:
	if not DB.is_open():
		return ""
	var last_place: String = DB.get_db_meta("last_place", "")
	if last_place.is_empty():
		return ""
	if Neighbourhoods.is_ready(last_place):
		return last_place
	var stores: Dictionary = custom_stores
	if stores.is_empty():
		stores = RevealEngine.load_installed_stores()
	if stores.has(last_place):
		return last_place
	return ""

func clear_current_view() -> void:
	_warm_map_view = null
	for child in get_children():
		if child is CanvasLayer:
			child.queue_free()
		elif child.name.begins_with("MapViewer") or child.name.begins_with("HomeHub") or child.name.begins_with("TownMap") or child.name.begins_with("InteriorView"):
			child.queue_free()

func enter_interior_from_map(map_view: Node, interior_id: String, return_info: Dictionary, floor_index: int = 0, spawn_tile: Vector2i = Vector2i(-1, -1), facing_str: String = "N", host_override: Node = null) -> InteriorView:
	if map_view == null or interior_id.is_empty():
		return null
	var host: Node = host_override if host_override != null else (map_view.get_parent() if map_view.get_parent() != null else self)
	_warm_map_view = map_view
	map_view.visible = false
	if map_view.has_method("set_overlays_visible"):
		map_view.set_overlays_visible(false)
	map_view.process_mode = Node.PROCESS_MODE_DISABLED

	var iv := InteriorView.new()
	iv.name = "InteriorView"
	host.add_child(iv)
	var use_fallback := bool(map_view._force_no_rom) if ("_force_no_rom" in map_view) else false
	if not iv.load_interior(interior_id, floor_index, AssetDB.DEFAULT_CACHE_DIR, use_fallback):
		if iv.get_parent() != null:
			iv.get_parent().remove_child(iv)
		iv.queue_free()
		map_view.visible = true
		if map_view.has_method("set_overlays_visible"):
			map_view.set_overlays_visible(true)
		map_view.process_mode = Node.PROCESS_MODE_INHERIT
		_warm_map_view = null
		return null
	var clk = map_view.get_world_clock() if map_view.has_method("get_world_clock") else null
	iv.enable_walking(spawn_tile, facing_str, return_info, clk, DB)
	iv.exit_requested.connect(func(ret_dict: Dictionary): exit_interior_to_map(iv, ret_dict))
	return iv

func exit_interior_to_map(iv: InteriorView, return_info: Dictionary) -> Node:
	if iv != null and is_instance_valid(iv):
		if iv.get_parent() != null:
			iv.get_parent().remove_child(iv)
		iv.queue_free()
	var mv := _warm_map_view
	_warm_map_view = null
	if mv != null and is_instance_valid(mv):
		if mv.has_method("resume_from_interior"):
			mv.resume_from_interior(return_info)
		else:
			mv.visible = true
			mv.process_mode = Node.PROCESS_MODE_INHERIT
	return mv

func open_interior_view(interior_id: String, floor_index: int = 0, force_fallback: bool = false) -> InteriorView:
	clear_current_view()
	var iv := InteriorView.new()
	iv.name = "InteriorView"
	add_child(iv)
	if not iv.load_interior(interior_id, floor_index, AssetDB.DEFAULT_CACHE_DIR, force_fallback):
		iv.queue_free()
		return null
	return iv

func open_map_view(force_no_rom: bool = false, has_tile: bool = false, tile_pos: Vector2i = Vector2i(-1, -1)) -> Node:
	clear_current_view()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene != null:
		var map_view = map_view_scene.instantiate()
		if map_view.has_method("set_screenshot_options"):
			map_view.set_screenshot_options(force_no_rom, has_tile, tile_pos)
		add_child(map_view)
		return map_view
	return null

func open_map_view_for_place(place_id: String) -> Node:
	if DB.is_open() and not place_id.is_empty():
		DB.set_db_meta("last_place", place_id)
	clear_current_view()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene != null:
		var map_view = map_view_scene.instantiate()
		add_child(map_view)
		if map_view.has_method("load_place"):
			map_view.load_place(place_id)
		return map_view
	return null

func open_home_hub() -> Node:
	clear_current_view()
	var hub_scene = load("res://scenes/home_hub.tscn")
	if hub_scene != null:
		var hub = hub_scene.instantiate()
		add_child(hub)
		if hub.has_method("_sync_to_viewport"):
			hub._sync_to_viewport()
		return hub
	return null

func open_town_map() -> Node:
	clear_current_view()
	var town_map_scene = load("res://scenes/town_map.tscn")
	if town_map_scene != null:
		var tm = town_map_scene.instantiate()
		tm.size = get_viewport_rect().size
		add_child(tm)
		return tm
	return null

func open_pairing_screen() -> void:
	clear_current_view()
	var cl = CanvasLayer.new()
	cl.name = "CanvasLayer"
	add_child(cl)
	var pairing_scene = load("res://scenes/pairing.tscn")
	if pairing_scene != null:
		var pairing_node = pairing_scene.instantiate()
		pairing_node.name = "Pairing"
		cl.add_child(pairing_node)
		if pairing_node.has_method("refresh_code"):
			pairing_node.refresh_code()

func _process(delta: float) -> void:
	if _wb_active:
		_tick_walk_bench(delta)
	elif _ws_active:
		_tick_walk_shot(delta)

func _ensure_dc_demo_areas(areas: Array[String]) -> void:
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	for aid in areas:
		NeighbourhoodProgress.demo_force_open(DB, aid)

func _start_walk_bench(s_cfg: Dictionary) -> void:
	_wb_zoom = float(s_cfg.get("zoom", 2.0))
	_wb_timeout_sec = float(s_cfg.get("timeout", 120))
	_wb_elapsed_sec = 0.0
	var no_rom := bool(s_cfg.get("no_rom", false))
	var t_min := int(s_cfg.get("time_minutes", -1))
	if t_min < 0:
		t_min = 1380 # 23:00 night: stress-test both Option C fog AND night Flash shader
	_ensure_dc_demo_areas(["hood:washington-dc:dupont-circle", "hood:washington-dc:georgetown"])
	var mv = open_map_view(no_rom)
	if mv == null or not mv.load_place("city:washington-dc", false):
		printerr("[FAIL] --walk-bench could not load city:washington-dc")
		get_tree().quit(1)
		return
	mv.enable_walk_mode("hood:washington-dc:dupont-circle", Vector2i(-1, -1), "S")
	mv.set_walk_zoom(_wb_zoom)
	mv.set_time_of_day_override(float(t_min))
	var sp_idx := int(s_cfg.get("sprite_index", -1))
	var walker: PlayerWalker = mv.get_player_walker()
	if walker == null:
		printerr("[FAIL] --walk-bench missing PlayerWalker")
		get_tree().quit(1)
		return
	if sp_idx >= 0:
		walker.set_sprite_index(sp_idx)
	walker.live_input_enabled = false
	walker.set_process(false)

	_wb_plan = mv.find_walk_bench_plan("hood:washington-dc:dupont-circle", "route:washington-dc:q-street#1", 40, 40)
	if not bool(_wb_plan.get("ok", false)):
		printerr("[FAIL] --walk-bench could not build 40+seam+40+door plan: %s" % str(_wb_plan))
		get_tree().quit(1)
		return

	mv.place_player_in_area(str(_wb_plan["start_area"]), _wb_plan["start_local"] as Vector2i, "W", false)
	mv.refresh_time_of_day_and_hud()
	_wb_mv = mv
	_wb_step_idx = 0
	_wb_warmup_frames = 0
	_wb_walk_deltas.clear()
	_wb_seam_max_ms = 0.0
	_wb_seam_watch_frames = 0
	_wb_door_enter_max_ms = 0.0
	_wb_door_exit_max_ms = 0.0
	_wb_door_watch_frames = 0
	_wb_phase = "warmup"
	_wb_active = true

func _tick_walk_bench(delta: float) -> void:
	_wb_elapsed_sec += delta
	if _wb_elapsed_sec > _wb_timeout_sec:
		printerr("[FAIL] --walk-bench timed out in phase %s after %.1fs" % [_wb_phase, _wb_elapsed_sec])
		get_tree().quit(3)
		return
	var frame_ms := delta * 1000.0

	if _wb_phase == "warmup":
		if _wb_mv.pending_cell_count() > 0:
			return
		_wb_warmup_frames += 1
		if _wb_warmup_frames >= 20:
			var vp_px := get_viewport_rect().size
			var scr_scale := DisplayServer.screen_get_scale()
			var log_tile_px := 32.0 * _wb_zoom
			var phys_tile_px := log_tile_px * scr_scale
			var view_w := floori(vp_px.x / log_tile_px)
			var view_h := floori(vp_px.y / log_tile_px)
			print("VIEWPORT_PX: %dx%d" % [int(vp_px.x), int(vp_px.y)])
			print("CONTENT_SCALE_FACTOR: %.2f" % scr_scale)
			print("LOGICAL_TILE_PX: %.1f" % log_tile_px)
			print("PHYSICAL_TILE_PX: %.1f" % phys_tile_px)
			print("VIEW_TILES %dx%d" % [view_w, view_h])
			_wb_phase = "walk_route"
		return

	if _wb_phase == "walk_route":
		var walker: PlayerWalker = _wb_mv.get_player_walker()
		var steps_arr: Array = _wb_plan.get("step_dirs", [])
		var seam_idx := int(_wb_plan.get("seam_step_index", 40))
		_wb_walk_deltas.append(frame_ms)
		if _wb_seam_watch_frames > 0:
			_wb_seam_max_ms = maxf(_wb_seam_max_ms, frame_ms)
			_wb_seam_watch_frames -= 1
		if _wb_step_idx >= steps_arr.size():
			if _wb_seam_watch_frames <= 0:
				_wb_mv.place_player_in_area(str(_wb_plan["door_area"]), _wb_plan["door_step_local"] as Vector2i, "N", false)
				_wb_warmup_frames = 0
				_wb_phase = "door_prep"
			return
		var cur_dir: Vector2i = steps_arr[_wb_step_idx] as Vector2i
		var use_run: bool = (_wb_step_idx >= 20 and _wb_step_idx < seam_idx) or (_wb_step_idx >= seam_idx + 21)
		var prev_pos := walker.grid_pos
		if _wb_step_idx == seam_idx:
			_wb_seam_max_ms = maxf(_wb_seam_max_ms, frame_ms)
		var sim_t0 := Time.get_ticks_usec()
		walker.step_simulation(delta, cur_dir, use_run)
		var sim_ms := float(Time.get_ticks_usec() - sim_t0) / 1000.0
		if walker.grid_pos != prev_pos:
			if _wb_step_idx == seam_idx:
				_wb_seam_max_ms = maxf(_wb_seam_max_ms, maxf(frame_ms, sim_ms))
				_wb_seam_watch_frames = 3
			_wb_step_idx += 1
		return

	if _wb_phase == "door_prep":
		if _wb_mv.pending_cell_count() > 0:
			return
		_wb_warmup_frames += 1
		if _wb_warmup_frames >= 12:
			_wb_phase = "door_enter"
		return

	if _wb_phase == "door_enter":
		var walker: PlayerWalker = _wb_mv.get_player_walker()
		var t0 := Time.get_ticks_usec()
		walker.step_simulation(1.0 / 60.0, Vector2i(0, -1), false)
		var enter_cpu_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_wb_door_enter_max_ms = maxf(_wb_door_enter_max_ms, maxf(frame_ms, enter_cpu_ms))
		_wb_iv = get_node_or_null("InteriorView") as InteriorView
		if _wb_iv == null:
			printerr("[FAIL] --walk-bench door step did not open InteriorView")
			get_tree().quit(1)
			return
		_wb_iv.set_walk_zoom(_wb_zoom)
		var iv_walker: PlayerWalker = _wb_iv.get_player_walker()
		if iv_walker != null:
			iv_walker.live_input_enabled = false
			iv_walker.set_process(false)
		_wb_door_watch_frames = 3
		_wb_indoor_steps_north = 0
		_wb_indoor_returning = false
		_wb_phase = "door_enter_watch"
		return

	if _wb_phase == "door_enter_watch":
		_wb_door_enter_max_ms = maxf(_wb_door_enter_max_ms, frame_ms)
		_wb_door_watch_frames -= 1
		if _wb_door_watch_frames <= 0:
			_wb_phase = "interior_walk"
		return

	if _wb_phase == "interior_walk":
		if _wb_iv == null or not is_instance_valid(_wb_iv):
			_wb_phase = "door_exit_watch"
			_wb_door_watch_frames = 3
			return
		var iv_walker: PlayerWalker = _wb_iv.get_player_walker()
		if not _wb_indoor_returning:
			if _wb_indoor_steps_north >= 2:
				_wb_indoor_returning = true
				return
			var prev_p := iv_walker.grid_pos
			iv_walker.step_simulation(delta, Vector2i(0, -1), false)
			if iv_walker.grid_pos != prev_p:
				_wb_indoor_steps_north += 1
			elif iv_walker.is_bumping():
				_wb_indoor_returning = true
		else:
			if _wb_indoor_steps_north <= 0:
				_wb_phase = "door_exit"
				return
			var prev_p2 := iv_walker.grid_pos
			iv_walker.step_simulation(delta, Vector2i(0, 1), false)
			if iv_walker.grid_pos != prev_p2:
				_wb_indoor_steps_north -= 1
		return

	if _wb_phase == "door_exit":
		if _wb_iv != null and is_instance_valid(_wb_iv):
			var iv_walker: PlayerWalker = _wb_iv.get_player_walker()
			iv_walker.place_at(iv_walker.grid_pos, "S")
			var t0 := Time.get_ticks_usec()
			iv_walker.step_simulation(1.0 / 60.0, Vector2i(0, 1), false)
			var exit_cpu_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			_wb_door_exit_max_ms = maxf(_wb_door_exit_max_ms, maxf(frame_ms, exit_cpu_ms))
		_wb_iv = null
		_wb_door_watch_frames = 4
		_wb_phase = "door_exit_watch"
		return

	if _wb_phase == "door_exit_watch":
		_wb_door_exit_max_ms = maxf(_wb_door_exit_max_ms, frame_ms)
		_wb_door_watch_frames -= 1
		if _wb_door_watch_frames <= 0:
			_finish_walk_bench()
		return

func _finish_walk_bench() -> void:
	_wb_active = false
	var sorted := _wb_walk_deltas.duplicate()
	sorted.sort()
	var walk_p95 := 0.0
	if not sorted.is_empty():
		var idx := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
		walk_p95 = float(sorted[idx])
	var refresh_rate := DisplayServer.screen_get_refresh_rate()
	if refresh_rate <= 0.0:
		refresh_rate = 60.0
	var vsync_ms := 1000.0 / refresh_rate
	print("VSYNC_MS: %.2f" % vsync_ms)
	print("WALK_FRAME_P95_MS: %.2f" % walk_p95)
	print("SEAM_MAX_FRAME_MS: %.2f" % _wb_seam_max_ms)
	print("DOOR_ENTER_MAX_FRAME_MS: %.2f" % _wb_door_enter_max_ms)
	print("DOOR_EXIT_MAX_FRAME_MS: %.2f" % _wb_door_exit_max_ms)
	var eval: Dictionary = ScreenshotConfig.evaluate_walk_bench_budget(walk_p95, _wb_seam_max_ms, _wb_door_enter_max_ms, _wb_door_exit_max_ms)
	if bool(eval.get("ok", false)):
		print("WALK_BENCH_RESULT: PASS")
		get_tree().quit(0)
	else:
		print("WALK_BENCH_RESULT: FAIL %s" % ", ".join(PackedStringArray(eval.get("fails", []))))
		get_tree().quit(1)

func _start_walk_shot(s_cfg: Dictionary) -> void:
	var scenario := str(s_cfg.get("walk_shot", ""))
	_ws_path = str(s_cfg.get("screenshot_path", ""))
	_ws_zoom = float(s_cfg.get("zoom", 2.0))
	_ws_frames_left = maxi(4, int(s_cfg.get("frames", 10)))
	_ws_timeout_sec = float(s_cfg.get("timeout", 120))
	_ws_elapsed_sec = 0.0
	var no_rom := bool(s_cfg.get("no_rom", false))
	var t_min := int(s_cfg.get("time_minutes", -1))
	var sp_idx := int(s_cfg.get("sprite_index", -1))

	_ensure_dc_demo_areas(["hood:washington-dc:dupont-circle", "hood:washington-dc:georgetown", "hood:washington-dc:national-mall"])
	var mv = open_map_view(no_rom)
	if mv == null or not mv.load_place("city:washington-dc", false):
		printerr("[FAIL] --walk-shot could not load city:washington-dc")
		get_tree().quit(1)
		return

	var default_time := 720
	if scenario == "dusk":
		default_time = 1200
	elif scenario == "night":
		default_time = 1380
	if t_min < 0:
		t_min = default_time
	if sp_idx < 0:
		sp_idx = 1 if (scenario == "may_step" or scenario == "may_run") else 0

	mv.enable_walk_mode("camp:washington-dc", Vector2i(31, 26), "S")
	mv.set_walk_zoom(_ws_zoom)
	mv.get_world_clock().set_minutes(t_min)
	mv.get_world_clock().set_running(false)
	mv.set_time_of_day_override(float(t_min))
	var walker: PlayerWalker = mv.get_player_walker()
	walker.set_sprite_index(sp_idx)
	walker.live_input_enabled = false
	walker.set_process(false)

	_ws_mv = mv
	_ws_iv = null

	match scenario:
		"day", "dusk", "night":
			# 5 tiles east of Dupont Circle lamp [64, 73] so both 4.5-tile Flash circle & 3.5-tile lamp pool show at zoom 2 & 1
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(69, 74), "W", false)
		"seam_route":
			# Stepping west across Dupont Circle's W opening onto Q Street #1
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(0, 47), "W", false)
			walker.step_simulation(8.0 / 60.0, Vector2i(-1, 0), false)
		"house_interior":
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(40, 52), "N", false)
			var ret_info := {"place_id": "city:washington-dc", "return_area_id": "hood:washington-dc:dupont-circle", "return_x": 40, "return_y": 52}
			var iv := enter_interior_from_map(mv, "dc:dc-brownstone-w", ret_info)
			if iv == null:
				printerr("[FAIL] --walk-shot=house_interior failed to open dc:dc-brownstone-w")
				get_tree().quit(1)
				return
			iv.set_walk_zoom(_ws_zoom)
			var iv_walker: PlayerWalker = iv.get_player_walker()
			iv_walker.set_sprite_index(sp_idx)
			iv_walker.live_input_enabled = false
			iv_walker.set_process(false)
			iv_walker.step_simulation(1.0 / 60.0, Vector2i(0, -1), false)
			iv_walker.step_simulation(15.0 / 60.0, Vector2i.ZERO, false)
			iv_walker.step_simulation(1.0 / 60.0, Vector2i(0, -1), false)
			iv_walker.step_simulation(15.0 / 60.0, Vector2i.ZERO, false)
			iv.set_walk_zoom(_ws_zoom)
			_ws_iv = iv
		"dialogue_sign":
			mv.place_player_in_area("route:washington-dc:q-street#1", Vector2i(155, 14), "N", false)
			mv.trigger_interact_for_walker()
		"dialogue_person":
			mv.place_player_in_area("camp:washington-dc", Vector2i(30, 26), "W", false)
			mv.trigger_interact_for_walker()
		"brendan_step", "may_step":
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(64, 75), "S", false)
			walker.step_simulation(1.0 / 60.0, Vector2i(0, 1), false)
			walker.step_simulation(3.0 / 60.0, Vector2i.ZERO, false)
		"brendan_run", "may_run":
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(64, 75), "S", false)
			walker.step_simulation(1.0 / 60.0, Vector2i(0, 1), true)
			walker.step_simulation(1.5 / 60.0, Vector2i.ZERO, true)
		"wall_bump":
			mv.place_player_in_area("hood:washington-dc:dupont-circle", Vector2i(41, 52), "N", false)
			walker.step_simulation(1.0 / 60.0, Vector2i(0, -1), false)
			walker.step_simulation(7.0 / 60.0, Vector2i.ZERO, false)
		"ledge_hop":
			mv.place_player_in_area("hood:washington-dc:national-mall", Vector2i(119, 23), "S", false)
			walker.step_simulation(1.0 / 60.0, Vector2i(0, 1), false)
			walker.step_simulation(11.0 / 60.0, Vector2i.ZERO, false)
		"landing_dust":
			mv.place_player_in_area("hood:washington-dc:national-mall", Vector2i(119, 23), "S", false)
			walker.step_simulation(1.0 / 60.0, Vector2i(0, 1), false)
			walker.step_simulation(31.0 / 60.0, Vector2i.ZERO, false)
			walker.step_simulation(8.0 / 60.0, Vector2i.ZERO, false)

	if _ws_iv == null and _ws_mv != null:
		if _ws_mv._camera != null and walker != null:
			_ws_mv._camera.position = walker.get_camera_target()
		_ws_mv.refresh_time_of_day_and_hud()
	_ws_active = true

func _tick_walk_shot(delta: float) -> void:
	_ws_elapsed_sec += delta
	if _ws_elapsed_sec > _ws_timeout_sec:
		printerr("[FAIL] --walk-shot timed out after %.1fs" % _ws_elapsed_sec)
		get_tree().quit(3)
		return
	if _ws_iv == null and _ws_mv != null:
		if _ws_mv.pending_cell_count() > 0:
			return
	_ws_frames_left -= 1
	if _ws_frames_left > 0:
		return
	_ws_active = false
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("[FAIL] --walk-shot viewport image empty")
		get_tree().quit(1)
		return
	var err := img.save_png(_ws_path)
	if err != OK:
		printerr("[FAIL] --walk-shot save_png failed: %d" % err)
		get_tree().quit(1)
		return
	var vp_px := get_viewport_rect().size
	var tile_px := 32.0 * _ws_zoom
	print("SCREENSHOT_SAVED %s" % _ws_path.get_file())
	print("VIEW_TILES %dx%d" % [floori(vp_px.x / tile_px), floori(vp_px.y / tile_px)])
	get_tree().quit(0)
