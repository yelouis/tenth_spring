extends Node

## game/tests/screen_scaling_test.gd — Item 85 (F110 / Decision 83) 960x640 Integer Screen Scaling Test
## Contract: docs/agent_execution_guide.md §5 (Item 85 / F110), Decision 83
## Verifies:
##   1. Root viewport visible rect is always 960x640 with viewport/keep/integer stretch & #000000 bars
##   2. At zoom 2.0, camera shows exactly 15x10 tiles (480x320 world px at 32 px/tile)
##   3. LampMenu (8/8 Go buttons), WaypostBoard, DialogueBox, HomeHub, and TownMap match 960x640 rects
##   4. Real mouse click (InputEventMouseButton in window coords through stretch transform) presses
##      a WaypostBoard Go button AND a lit TownMap marker
##   5. Startup window scale formula fits biggest integer multiple of 960x640 (2x = 1920x1280 on 2560x1440)

const MainScript := preload("res://scenes/main.gd")
const MapViewScene := preload("res://world/map_view.tscn")
const WaypostBoardScene := preload("res://scenes/waypost_board.tscn")
const LampMenuScene := preload("res://scenes/lamp_menu.tscn")
const DialogueBoxScene := preload("res://scenes/dialogue_box.tscn")
const HomeHubScene := preload("res://scenes/home_hub.tscn")
const TownMapScene := preload("res://scenes/town_map.tscn")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

const TEST_DB_PATH := "user://test/screen_scaling_test.db"
const TEST_TMP_PATH := "user://test/screen_scaling_test.db.tmp"
const LOGICAL_SIZE := Vector2(960.0, 640.0)

func _free_nodes(nodes: Array) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()

func _cleanup(nodes: Array = []) -> void:
	_free_nodes(nodes)
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _force_layout_tree(n: Node) -> void:
	if n is Container:
		(n as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for ch in n.get_children():
		_force_layout_tree(ch)
	if n is Control:
		(n as Control).update_minimum_size()

func _dispatch_real_mouse_click(vp: Viewport, local_viewport_pos: Vector2) -> void:
	# Convert logical 960x640 viewport position into actual OS window coordinates through the stretch transform
	# (e.g. inside a 1920x1080 or 1152x648 window with letterbox/pillarbox offset) and push real mouse events.
	var win_pos: Vector2 = vp.get_screen_transform() * local_viewport_pos
	var move_ev := InputEventMouseMotion.new()
	move_ev.position = win_pos
	move_ev.global_position = win_pos
	vp.push_input(move_ev, false)

	var down_ev := InputEventMouseButton.new()
	down_ev.button_index = MOUSE_BUTTON_LEFT
	down_ev.pressed = true
	down_ev.position = win_pos
	down_ev.global_position = win_pos
	vp.push_input(down_ev, false)

	var up_ev := InputEventMouseButton.new()
	up_ev.button_index = MOUSE_BUTTON_LEFT
	up_ev.pressed = false
	up_ev.position = win_pos
	up_ev.global_position = win_pos
	vp.push_input(up_ev, false)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL [F110]: DB.assert_test_safe failed")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	var failures: Array[String] = []
	var vp := get_viewport()
	var win := get_window()
	if vp == null or win == null:
		push_error("FAIL [F110]: Missing root viewport or window")
		_cleanup()
		return false

	# 1. Logical viewport size must always be 960x640, with viewport/keep/integer stretch and black bars
	var vis_size: Vector2 = vp.get_visible_rect().size
	var tiles_w := vis_size.x / 64.0
	var tiles_h := vis_size.y / 64.0
	if not vis_size.is_equal_approx(LOGICAL_SIZE):
		failures.append("visible_rect.size=%s (%.2fx%.2f tiles at zoom 2), expected (960, 640) (15x10 tiles)" % [str(vis_size), tiles_w, tiles_h])
	if win.content_scale_mode != Window.CONTENT_SCALE_MODE_VIEWPORT:
		failures.append("content_scale_mode=%d, expected CONTENT_SCALE_MODE_VIEWPORT (%d)" % [win.content_scale_mode, Window.CONTENT_SCALE_MODE_VIEWPORT])
	if win.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_KEEP:
		failures.append("content_scale_aspect=%d, expected CONTENT_SCALE_ASPECT_KEEP (%d)" % [win.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP])
	if win.content_scale_stretch != Window.CONTENT_SCALE_STRETCH_INTEGER:
		failures.append("content_scale_stretch=%d, expected CONTENT_SCALE_STRETCH_INTEGER (%d)" % [win.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_INTEGER])
	if win.content_scale_size != Vector2i(960, 640):
		failures.append("content_scale_size=%s, expected (960, 640)" % str(win.content_scale_size))
	var clear_col: Color = RenderingServer.get_default_clear_color()
	if not clear_col.is_equal_approx(Color(0.0, 0.0, 0.0, 1.0)):
		failures.append("default_clear_color=%s, expected #000000 black bars" % str(clear_col))

	# 2. Startup window-sizing helper checks (Decision 83 + Item 88 / F112)
	var m_inst: Node = MainScript.new()
	if not m_inst.has_method("compute_window_scale_for_rect"):
		failures.append("MainScript missing compute_window_scale_for_rect(usable_rect)")
	else:
		var k_2560: int = int(m_inst.call("compute_window_scale_for_rect", Rect2i(0, 25, 2560, 1415)))
		var k_1080: int = int(m_inst.call("compute_window_scale_for_rect", Rect2i(0, 25, 1920, 1055)))
		var k_4k: int = int(m_inst.call("compute_window_scale_for_rect", Rect2i(0, 25, 3840, 2135)))
		var k_small: int = int(m_inst.call("compute_window_scale_for_rect", Rect2i(0, 0, 800, 600)))
		if k_2560 != 2:
			failures.append("2560x1415 usable rect scale=%d, expected 2 (1920x1280)" % k_2560)
		if k_1080 != 1:
			failures.append("1920x1055 usable rect scale=%d, expected 1 (960x640)" % k_1080)
		if k_4k != 3:
			failures.append("3840x2135 usable rect scale=%d, expected 3 (2880x1920)" % k_4k)
		if k_small != 1:
			failures.append("800x600 usable rect scale=%d, expected 1" % k_small)

	if not m_inst.has_method("startup_window_scale"):
		failures.append("MainScript missing startup_window_scale(start_size, mode, headless, usable, user_args)")
	else:
		var usable_2560 := Rect2i(0, 25, 2560, 1415)
		var win_mode := DisplayServer.WINDOW_MODE_WINDOWED
		var fs_mode := DisplayServer.WINDOW_MODE_FULLSCREEN
		var s_auto: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray()))
		var s_custom: int = int(m_inst.call("startup_window_scale", Vector2i(1152, 648), win_mode, false, usable_2560, PackedStringArray()))
		var s_k1: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray(["--window-scale=1"])))
		var s_k3_clamped: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray(["--window-scale=3"])))
		var s_k0: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray(["--window-scale=0"])))
		var s_k9_bad: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray(["--window-scale=9"])))
		var s_abc_bad: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, false, usable_2560, PackedStringArray(["--window-scale=abc"])))
		var s_headless: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), win_mode, true, usable_2560, PackedStringArray()))
		var s_fullscreen: int = int(m_inst.call("startup_window_scale", Vector2i(960, 640), fs_mode, false, usable_2560, PackedStringArray()))
		if s_auto != 2:
			failures.append("startup_window_scale(960x640, windowed, [])=%d, expected 2" % s_auto)
		if s_custom != 0:
			failures.append("startup_window_scale(1152x648, windowed, [])=%d, expected 0 (keep --resolution)" % s_custom)
		if s_k1 != 1:
			failures.append("startup_window_scale(--window-scale=1)=%d, expected 1" % s_k1)
		if s_k3_clamped != 2:
			failures.append("startup_window_scale(--window-scale=3 on 2560x1415)=%d, expected 2 (clamped)" % s_k3_clamped)
		if s_k0 != 2:
			failures.append("startup_window_scale(--window-scale=0)=%d, expected 2 (auto)" % s_k0)
		if s_k9_bad != -1:
			failures.append("startup_window_scale(--window-scale=9)=%d, expected -1 (rejected)" % s_k9_bad)
		if s_abc_bad != -1:
			failures.append("startup_window_scale(--window-scale=abc)=%d, expected -1 (rejected)" % s_abc_bad)
		if s_headless != 0:
			failures.append("startup_window_scale(headless)=%d, expected 0" % s_headless)
		if s_fullscreen != 0:
			failures.append("startup_window_scale(fullscreen)=%d, expected 0" % s_fullscreen)
		var rect_k1: Rect2i = m_inst.call("compute_centered_window_rect_for_scale", usable_2560, 1)
		if rect_k1.size != Vector2i(960, 640):
			failures.append("compute_centered_window_rect_for_scale(k=1).size=%s, expected (960, 640)" % str(rect_k1.size))
	m_inst.free()

	# Setup DC test state for camera & UI checks
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	var dc_hoods := [
		"hood:washington-dc:national-mall",
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:dupont-circle",
		"hood:washington-dc:capitol-hill",
		"hood:washington-dc:union-station",
		"hood:washington-dc:georgetown",
		"hood:washington-dc:woodley-park",
		"hood:washington-dc:lincoln-memorial",
	]
	for h_id in dc_hoods:
		DB.upsert_neighbourhood_state(h_id, "city:washington-dc", 2, "pick", now)
	DB.insert_distort_entry("city:washington-dc", now, "starter")

	# 3. Camera at zoom 2.0 shows exactly 15x10 tiles (480x320 world px at 32 px/tile)
	var mv = MapViewScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", true) or not mv.enable_walk_mode("hood:washington-dc:national-mall", Vector2i(78, 47), "S"):
		failures.append("Failed to load DC walk mode")
	else:
		var cam: Camera2D = mv._camera
		var cam_zoom: Vector2 = cam.zoom if cam != null else Vector2.ZERO
		var world_vis: Vector2 = vp.get_visible_rect().size / maxf(0.001, cam_zoom.x)
		var cam_tiles: Vector2 = world_vis / 32.0
		if not is_equal_approx(cam_zoom.x, 2.0) or not cam_tiles.is_equal_approx(Vector2(15.0, 10.0)):
			failures.append("Zoom %.2f shows %.2fx%.2f tiles (world %s), expected 15.00x10.00 tiles" % [cam_zoom.x, cam_tiles.x, cam_tiles.y, str(world_vis)])
	_free_nodes([mv])

	# 4. LampMenu 8/8 Go buttons, WaypostBoard, DialogueBox, and HomeHub match 960x640 rects
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)

	var lm: Control = LampMenuScene.instantiate()
	ui_layer.add_child(lm)
	lm.open_for_area("city:washington-dc", "hood:washington-dc:national-mall", DB)
	_force_layout_tree(lm)
	var lm_panel := lm.get_node("CenterPanel") as PanelContainer
	var lm_scroll := lm.get_node("CenterPanel/Margin/RootVBox/Scroll") as ScrollContainer
	var lm_rows := lm.get_node("CenterPanel/Margin/RootVBox/Scroll/RowsVBox") as VBoxContainer
	var exp_lm_rect := Rect2(240.0, 320.0 + lm_panel.offset_top, 480.0, lm_panel.offset_bottom - lm_panel.offset_top)
	if not lm.get_rect().size.is_equal_approx(LOGICAL_SIZE):
		failures.append("LampMenu size=%s, expected (960, 640)" % str(lm.get_rect().size))
	elif not lm_panel.get_rect().position.is_equal_approx(exp_lm_rect.position) or not lm_panel.get_rect().size.is_equal_approx(exp_lm_rect.size):
		failures.append("LampMenu CenterPanel rect=%s, expected %s" % [str(lm_panel.get_rect()), str(exp_lm_rect)])
	var go_cnt := 0
	var srect: Rect2 = lm_scroll.get_global_rect()
	if srect.size.y <= 0.0:
		failures.append("LampMenu ScrollContainer collapsed: rect=%s" % str(srect))
	for r_ch in lm_rows.get_children():
		for b_ch in r_ch.get_children():
			if b_ch is Button and (b_ch as Button).text == "Go":
				go_cnt += 1
				var br := (b_ch as Button).get_global_rect()
				if br.position.y < srect.position.y - 1.0 or br.end.y > srect.end.y + 1.0:
					failures.append("LampMenu Go button %s outside scroll rect (%s vs %s)" % [b_ch.name, str(br), str(srect)])
	if go_cnt != 8:
		failures.append("LampMenu expected 8 Go buttons, found %d" % go_cnt)
	_free_nodes([lm])

	# DialogueBox rect matches 960x640: BoxPanel at x=120..840, y=508..624
	var dlg: Control = DialogueBoxScene.instantiate()
	ui_layer.add_child(dlg)
	dlg.open_lines(["Testing dialogue box rect at 960x640."], "Scout")
	_force_layout_tree(dlg)
	var box_panel := dlg.get_node("BoxPanel") as PanelContainer
	var exp_dlg := Rect2(120.0, 508.0, 720.0, 116.0)
	if not box_panel.get_rect().is_equal_approx(exp_dlg):
		failures.append("DialogueBox BoxPanel rect=%s, expected %s" % [str(box_panel.get_rect()), str(exp_dlg)])
	_free_nodes([dlg])

	# WaypostBoard rect matches 960x640 AND real mouse click presses a Go button!
	var board: Control = WaypostBoardScene.instantiate()
	ui_layer.add_child(board)
	board.open_for_place("city:washington-dc", DB)
	_force_layout_tree(board)
	_force_layout_tree(board)
	var bpanel := board.get_node("BoardPanel") as PanelContainer
	var exp_board := Rect2(20.0, 18.0, 920.0, 604.0)
	if not bpanel.get_rect().is_equal_approx(exp_board):
		failures.append("WaypostBoard BoardPanel rect=%s, expected %s" % [str(bpanel.get_rect()), str(exp_board)])
	var clicked_board_area := {"id": ""}
	board.go_requested.connect(func(aid: String): clicked_board_area["id"] = aid)
	var go_btn := board.find_child("GoButton", true, false) as Button
	if go_btn == null:
		# Find first visible "Go" button inside RowsVBox
		var br_vbox := board.get_node_or_null("BoardPanel/Margin/RootVBox/Scroll/RowsVBox")
		if br_vbox != null:
			for row in br_vbox.get_children():
				for cand in row.find_children("*", "Button", true, false):
					if (cand as Button).text == "Go" and not (cand as Button).disabled:
						go_btn = cand as Button
						break
				if go_btn != null:
					break
	if go_btn == null:
		failures.append("WaypostBoard: no enabled Go button found to click")
	else:
		var go_center: Vector2 = go_btn.get_global_rect().get_center()
		_dispatch_real_mouse_click(vp, go_center)
		if str(clicked_board_area["id"]).is_empty():
			failures.append("WaypostBoard real mouse click at local %s (win %s) did not trigger go_requested" % [
				str(go_center), str(vp.get_screen_transform() * go_center)
			])
	_free_nodes([board, ui_layer])

	# HomeHub under Node2D matches 960x640
	var fake_main := Node2D.new()
	add_child(fake_main)
	var hub: Control = HomeHubScene.instantiate()
	fake_main.add_child(hub)
	if not hub.size.is_equal_approx(LOGICAL_SIZE):
		failures.append("HomeHub size=%s, expected (960, 640)" % str(hub.size))
	_free_nodes([hub])

	# TownMap under Node2D matches 960x640 AND real mouse click presses Washington DC marker!
	var tm: Control = TownMapScene.instantiate()
	fake_main.add_child(tm)
	if not tm.size.is_equal_approx(LOGICAL_SIZE):
		failures.append("TownMap size=%s, expected (960, 640)" % str(tm.size))
	var clicked_place := {"id": ""}
	tm.place_selected.connect(func(pid: String, _lat: float, _lon: float): clicked_place["id"] = pid)
	var dc_marker: Button = tm.get_marker("city:washington-dc")
	if dc_marker == null or dc_marker.disabled:
		failures.append("TownMap DC marker missing or disabled")
	else:
		var m_rect: Rect2 = dc_marker.get_global_rect()
		if m_rect.position.x < 0.0 or m_rect.position.y < 0.0 or m_rect.end.x > 960.0 or m_rect.end.y > 640.0:
			failures.append("TownMap DC marker rect=%s outside 960x640" % str(m_rect))
		var m_center: Vector2 = m_rect.get_center()
		_dispatch_real_mouse_click(vp, m_center)
		if str(clicked_place["id"]) != "city:washington-dc":
			failures.append("TownMap real mouse click at local %s (win %s) did not select city:washington-dc (got '%s')" % [
				str(m_center), str(vp.get_screen_transform() * m_center), str(clicked_place["id"])
			])
	_free_nodes([tm, fake_main])

	_cleanup()

	if not failures.is_empty():
		for msg in failures:
			push_error("FAIL [F110]: " + msg)
		return false
	print("SCREEN_SCALING_OK win=%s visible=%s xform=%s" % [str(win.size), str(vis_size), str(vp.get_screen_transform())])
	return true
