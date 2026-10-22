extends Node2D

const ProfilePaths := preload("res://scripts/profile_paths.gd")
const ScreenshotConfig := preload("res://scripts/screenshot_config.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Grid := preload("res://world/grid.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

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

	if s_cfg.get("is_screenshot", false):
		if s_cfg.get("screen", "map") == "town_map":
			var town_map = open_town_map()
			if town_map != null and town_map.has_method("setup_screenshot"):
				town_map.setup_screenshot(
					str(s_cfg.get("screenshot_path", "")),
					int(s_cfg.get("frames", 10))
				)
			return

		var boot_place_id := get_boot_place_id()
		var map_view = open_map_view()
		if map_view != null:
			if not boot_place_id.is_empty() and map_view.has_method("load_place"):
				map_view.load_place(boot_place_id, false)
			if map_view.has_method("setup_screenshot"):
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

	# Item 20 boot routing (plan §5):
	# - with a bodyFix inside a famous place, open that place's map view;
	# - otherwise open the home hub;
	# - pairing screen stays reachable from the hub.
	var boot_place_id := get_boot_place_id()
	if not boot_place_id.is_empty():
		open_map_view_for_place(boot_place_id)
	else:
		open_home_hub()

func get_boot_place_id(custom_stores: Dictionary = {}) -> String:
	if not DB.is_open():
		return ""
	var peer_rows = DB._rows("SELECT last_body_lat, last_body_lon FROM sync_peer WHERE last_body_lat IS NOT NULL AND last_body_lon IS NOT NULL ORDER BY last_body_ts DESC LIMIT 1;")
	if peer_rows.is_empty():
		return ""
	var b_lat := float(peer_rows[0].get("last_body_lat", 0.0))
	var b_lon := float(peer_rows[0].get("last_body_lon", 0.0))
	var body_cell := Grid.latlon_to_cell(b_lat, b_lon)

	var stores: Dictionary = custom_stores
	if stores.is_empty():
		stores = RevealEngine.load_installed_stores()

	for pid in stores.keys():
		var s: MapStore = stores[pid]
		if s.covers_cell(body_cell.x, body_cell.y):
			var ca := s.get_cell_area(body_cell.x, body_cell.y)
			if not ca.is_empty():
				return pid
	return ""

func clear_current_view() -> void:
	for child in get_children():
		if child is CanvasLayer:
			child.queue_free()
		elif child.name.begins_with("MapViewer") or child.name.begins_with("HomeHub") or child.name.begins_with("TownMap"):
			child.queue_free()

func open_map_view() -> Node:
	clear_current_view()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene != null:
		var map_view = map_view_scene.instantiate()
		add_child(map_view)
		return map_view
	return null

func open_map_view_for_place(place_id: String) -> Node:
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
