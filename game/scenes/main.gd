extends Node2D

const ProfilePaths := preload("res://scripts/profile_paths.gd")

func _ready() -> void:
	var profile = ProfilePaths.resolve_from_cmdline()
	if not profile.ok:
		push_error("Failed to resolve profile paths: " + profile.error)
		get_tree().quit(1)
		return

	DB.configure_paths(profile.db_path, profile.db_tmp_path)
	var identity = PcIdentity.new()
	identity.configure_dir(profile.identity_dir)
	SyncServer.configure_identity(identity)

	DB.init_db()
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

func open_map_view() -> void:
	var pairing_node = get_node_or_null("CanvasLayer/Pairing")
	if pairing_node != null:
		pairing_node.hide()
	var map_view_scene = load("res://world/map_view.tscn")
	if map_view_scene != null:
		var map_view = map_view_scene.instantiate()
		add_child(map_view)

func open_pairing_screen() -> void:
	var pairing_node = get_node_or_null("CanvasLayer/Pairing")
	if pairing_node != null:
		pairing_node.show()
		if pairing_node.has_method("refresh_code"):
			pairing_node.refresh_code()
