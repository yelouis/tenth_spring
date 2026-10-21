extends Node2D

const ProfilePaths := preload("res://scripts/profile_paths.gd")
const ScreenshotConfig := preload("res://scripts/screenshot_config.gd")

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

	if s_cfg.get("is_screenshot", false):
		var map_view = open_map_view()
		if map_view != null and map_view.has_method("setup_screenshot"):
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

	# Item 9 (plan §7.1): Open map view if save holds >= 1 revealed cell, else pairing screen
	var revealed_cells := 0
	if DB.is_open():
		var rows = DB.query_rows("SELECT count(*) as c FROM map_cell WHERE reveal_state > 0;")
		if not rows.is_empty():
			revealed_cells = int(rows[0].get("c", 0))

	if revealed_cells >= 1:
		open_map_view()
	else:
		open_pairing_screen()

func open_map_view() -> Node:
	var canvas_layer = get_node_or_null("CanvasLayer")
	if canvas_layer != null:
		canvas_layer.queue_free()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene != null:
		var map_view = map_view_scene.instantiate()
		add_child(map_view)
		return map_view
	return null

func open_pairing_screen() -> void:
	var pairing_node = get_node_or_null("CanvasLayer/Pairing")
	if pairing_node != null:
		pairing_node.show()
		if pairing_node.has_method("refresh_code"):
			pairing_node.refresh_code()
