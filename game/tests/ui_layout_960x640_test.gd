extends Node

## game/tests/ui_layout_960x640_test.gd — Item 78 (Decision 81: F93, F94, F95, F96 + camp buttons)
## Verifies:
##   1. F93: WaypostBoard fits inside 960x640 (non-demo & demo modes, including Open/Go/DemoWalk/DemoFinish)
##   2. F94: HomeHub & RoomArt size to viewport under a Node2D parent (Main) and redraw on resize
##   3. F95: WalkBannerPanel sits cleanly below WalkHudPanel with no overlap
##   4. F96: InteriorView.format_floor_banner_title never repeats the building title across all 94 DC interiors
##   5. Camp buttons: ReturnHomeButton & BoardButton stay hidden everywhere in camp while walking

const WaypostBoardScene := preload("res://scenes/waypost_board.tscn")
const HomeHubScene := preload("res://scenes/home_hub.tscn")
const MapViewScene := preload("res://world/map_view.tscn")
const InteriorViewScript := preload("res://world/interior/interior_view.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

const TEST_DB_PATH := "user://test/ui_layout_960x640_test.db"
const TEST_TMP_PATH := "user://test/ui_layout_960x640_test.db.tmp"

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

func _check_waypost_board_fits_960x640(demo_flag: bool, label: String) -> bool:
	NeighbourhoodProgress.set_demo_override_for_tests(1 if demo_flag else 0)
	var board: Control = WaypostBoardScene.instantiate()
	var holder := Control.new()
	holder.size = Vector2(960.0, 640.0)
	add_child(holder)
	holder.add_child(board)
	board.open_for_place("city:washington-dc", DB)

	var panel := board.get_node_or_null("BoardPanel") as PanelContainer
	if panel == null:
		push_error("FAIL [F93 %s]: BoardPanel missing" % label)
		holder.queue_free()
		return false

	# Available panel width inside 960x640 with offset_left/right
	var avail_w: float = 960.0 - panel.offset_left + panel.offset_right
	var min_w: float = panel.get_combined_minimum_size().x
	if min_w > avail_w + 0.5:
		push_error("FAIL [F93 %s]: BoardPanel combined min width %.1f exceeds available %.1f (960x640 overflow)" % [label, min_w, avail_w])
		holder.queue_free()
		return false

	var rows_vbox := board.get_node_or_null("BoardPanel/Margin/RootVBox/Scroll/RowsVBox") as VBoxContainer
	if rows_vbox == null or rows_vbox.get_child_count() != 8:
		push_error("FAIL [F93 %s]: Expected 8 DC rows, got %d" % [label, rows_vbox.get_child_count() if rows_vbox != null else -1])
		holder.queue_free()
		return false

	for row in rows_vbox.get_children():
		if not (row is PanelContainer):
			continue
		var rmin: float = (row as PanelContainer).get_combined_minimum_size().x
		if rmin > avail_w - 28.0:
			push_error("FAIL [F93 %s]: Row %s combined min width %.1f exceeds inner width %.1f" % [label, row.name, rmin, avail_w - 28.0])
			holder.queue_free()
			return false
		var name_lbl := row.find_child("NameLabel", true, false) as Label
		if name_lbl == null or name_lbl.autowrap_mode == TextServer.AUTOWRAP_OFF:
			push_error("FAIL [F93 %s]: Row %s NameLabel missing word wrap" % [label, row.name])
			holder.queue_free()
			return false
		var card_lbl := row.find_child("CardLabel", true, false) as Label
		if card_lbl == null or card_lbl.autowrap_mode == TextServer.AUTOWRAP_OFF:
			push_error("FAIL [F93 %s]: Row %s CardLabel missing word wrap" % [label, row.name])
			holder.queue_free()
			return false

	var close_btn := board.get_node_or_null("BoardPanel/Margin/RootVBox/Header/CloseButton") as Button
	if close_btn == null or close_btn.text != "Close":
		push_error("FAIL [F93 %s]: CloseButton missing" % label)
		holder.queue_free()
		return false

	holder.queue_free()
	return true

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL [Item 78]: DB.assert_test_safe failed")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	# 1. F93: WaypostBoard fits inside 960x640 in non-demo, demo (with Open/Go/DemoFinish),
	#    and demo with DemoWalk buttons visible (including a hood reachable from multiple routes).
	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	NeighbourhoodProgress.open(DB, "hood:washington-dc:national-mall")
	NeighbourhoodProgress.enter(DB, "hood:washington-dc:national-mall")
	if not _check_waypost_board_fits_960x640(false, "non-demo"):
		_cleanup()
		return false
	if not _check_waypost_board_fits_960x640(true, "demo-open-go-finish"):
		_cleanup()
		return false
	# Open Lincoln Memorial (reachable via routes from Mall + Tidal Basin) to also stress DemoWalk buttons
	NeighbourhoodProgress.open(DB, "hood:washington-dc:tidal-basin")
	NeighbourhoodProgress.enter(DB, "hood:washington-dc:tidal-basin")
	NeighbourhoodProgress.finish(DB, "hood:washington-dc:national-mall")
	NeighbourhoodProgress.open(DB, "hood:washington-dc:lincoln-memorial")
	if not _check_waypost_board_fits_960x640(true, "demo-walk-routes"):
		_cleanup()
		return false
	NeighbourhoodProgress.set_demo_override_for_tests(-1)

	# 2. F94: HomeHub sizes to viewport even when parented to a Node2D (like Main) and resizes RoomArt.
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 640)
	add_child(sv)
	var fake_main := Node2D.new()
	sv.add_child(fake_main)
	var hub: Control = HomeHubScene.instantiate()
	fake_main.add_child(hub)
	var room_art := hub.get_node_or_null("RoomArt") as Control
	if room_art == null:
		push_error("FAIL [F94]: HomeHub RoomArt missing")
		sv.queue_free()
		_cleanup()
		return false
	if not hub.size.is_equal_approx(Vector2(960.0, 640.0)):
		push_error("FAIL [F94]: HomeHub did not size to 960x640 SubViewport under Node2D parent: hub=%s" % str(hub.size))
		sv.queue_free()
		_cleanup()
		return false
	if not room_art.size.is_equal_approx(Vector2(960.0, 640.0)):
		push_error("FAIL [F94]: RoomArt size %s does not match HomeHub 960x640" % str(room_art.size))
		sv.queue_free()
		_cleanup()
		return false
	sv.queue_free()

	# 3. F95 + Camp Buttons: WalkBannerPanel below WalkHudPanel, ReturnHome & Board hidden while walking in camp.
	var mv = MapViewScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", true):
		push_error("FAIL [F95/Camp]: Failed to load DC")
		_cleanup(mv)
		return false
	if not mv.enable_walk_mode("camp:washington-dc", Vector2i(31, 26), "S"):
		push_error("FAIL [F95/Camp]: Failed to enter walk mode in camp")
		_cleanup(mv)
		return false

	var hud_panel := mv.get_node_or_null("AttributionUI/WalkHudPanel") as PanelContainer
	var banner_panel := mv.get_node_or_null("AttributionUI/WalkBannerPanel") as PanelContainer
	if hud_panel == null or banner_panel == null:
		push_error("FAIL [F95]: WalkHudPanel or WalkBannerPanel missing")
		_cleanup(mv)
		return false
	mv.show_banner("You are in Washington DC. You have what you carry. The way home is this Waypost.", 5.0)
	var hud_bottom: float = maxf(hud_panel.offset_bottom, hud_panel.offset_top + hud_panel.get_combined_minimum_size().y)
	if banner_panel.offset_top < hud_bottom:
		push_error("FAIL [F95]: WalkBannerPanel offset_top=%.1f overlaps WalkHudPanel bottom=%.1f" % [banner_panel.offset_top, hud_bottom])
		_cleanup(mv)
		return false

	var ret_btn := mv.get_node_or_null("AttributionUI/ReturnHomeButton") as Button
	var board_btn := mv.get_node_or_null("AttributionUI/BoardButton") as Button
	var back_btn := mv.get_node_or_null("AttributionUI/BackToCampButton") as Button
	for camp_tile in [Vector2i(31, 26), Vector2i(34, 26), Vector2i(20, 26)]:
		mv.enable_walk_mode("camp:washington-dc", camp_tile, "S")
		if (ret_btn != null and ret_btn.visible) or (board_btn != null and board_btn.visible) or (back_btn != null and back_btn.visible):
			push_error("FAIL [Camp buttons]: HUD buttons visible while walking at camp tile %s (ret=%s board=%s back=%s)" % [
				str(camp_tile),
				str(ret_btn.visible if ret_btn != null else false),
				str(board_btn.visible if board_btn != null else false),
				str(back_btn.visible if back_btn != null else false),
			])
			_cleanup(mv)
			return false
	if not mv.can_return_home():
		push_error("FAIL [Camp buttons]: can_return_home() must remain true in camp while walking (for LampMenu)")
		_cleanup(mv)
		return false

	# Non-walk camera inspection mode in camp still exposes the legacy buttons.
	mv.disable_walk_mode()
	mv.focus_on_area("camp:washington-dc", false)
	if ret_btn == null or board_btn == null or not ret_btn.visible or not board_btn.visible:
		push_error("FAIL [Camp buttons]: Non-walk inspection mode in camp should still show ReturnHome/Board")
		_cleanup(mv)
		return false

	# 4. F96: InteriorView banner title never repeats the building title across all 94 DC interiors.
	var shed_fmt: String = InteriorViewScript.format_floor_banner_title("Conservatory Tool Shed", "1F — Conservatory Tool Shed")
	if shed_fmt != "Conservatory Tool Shed — 1F":
		push_error("FAIL [F96]: Expected 'Conservatory Tool Shed — 1F', got '%s'" % shed_fmt)
		_cleanup(mv)
		return false
	var mon_fmt: String = InteriorViewScript.format_floor_banner_title("Washington Monument", "1F — Entry Lobby")
	if mon_fmt != "Washington Monument — 1F — Entry Lobby":
		push_error("FAIL [F96]: Expected 'Washington Monument — 1F — Entry Lobby', got '%s'" % mon_fmt)
		_cleanup(mv)
		return false

	var int_dirs := [
		"res://data/interiors/washington-dc",
		"res://data/interiors/washington-dc/houses",
	]
	var checked_interiors := 0
	var checked_floors := 0
	for int_dir in int_dirs:
		var files := DirAccess.get_files_at(int_dir)
		for fn in files:
			if not fn.ends_with(".json"):
				continue
			var f := FileAccess.open(int_dir + "/" + fn, FileAccess.READ)
			if f == null:
				push_error("FAIL [F96]: Could not open %s/%s" % [int_dir, fn])
				_cleanup(mv)
				return false
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if not (parsed is Dictionary):
				push_error("FAIL [F96]: Invalid JSON in %s/%s" % [int_dir, fn])
				_cleanup(mv)
				return false
			var d: Dictionary = parsed
			var title := str(d.get("title", ""))
			var floors: Variant = d.get("floors", [])
			if not (floors is Array) or title.is_empty():
				push_error("FAIL [F96]: Missing title/floors in %s/%s" % [int_dir, fn])
				_cleanup(mv)
				return false
			checked_interiors += 1
			for fl_v in floors:
				if not (fl_v is Dictionary):
					continue
				var fl_label := str((fl_v as Dictionary).get("label", ""))
				var banner := InteriorViewScript.format_floor_banner_title(title, fl_label)
				if banner.count(title) != 1:
					push_error("FAIL [F96]: Banner '%s' repeats/drops title '%s' in %s" % [banner, title, fn])
					_cleanup(mv)
					return false
				checked_floors += 1

	if checked_interiors != 94 or checked_floors < 98:
		push_error("FAIL [F96]: Expected 94 DC interiors (>=98 floors), checked %d (%d floors)" % [checked_interiors, checked_floors])
		_cleanup(mv)
		return false

	# Live InteriorView instantiation check for Conservatory Tool Shed
	var iv := InteriorViewScript.new()
	add_child(iv)
	if not iv.load_interior("dc:nm-botany-shed", 0):
		push_error("FAIL [F96]: Could not load Conservatory Tool Shed interior")
		iv.queue_free()
		_cleanup(mv)
		return false
	if iv._title_label == null or iv._title_label.text != "Conservatory Tool Shed — 1F":
		push_error("FAIL [F96]: InteriorView title label is '%s', expected 'Conservatory Tool Shed — 1F'" % [
			iv._title_label.text if iv._title_label != null else "<null>"
		])
		iv.queue_free()
		_cleanup(mv)
		return false
	iv.queue_free()

	_cleanup(mv)
	return true
