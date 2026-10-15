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

func open_pairing_screen() -> void:
	var pairing_node = get_node_or_null("CanvasLayer/Pairing")
	if pairing_node != null:
		pairing_node.show()
		if pairing_node.has_method("refresh_code"):
			pairing_node.refresh_code()
