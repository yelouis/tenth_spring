extends Node

# Demo Import Server Scene (Item 6 / plan §2)
# Headless Godot receiver listening on dedicated demo port 7352 (or custom port).
# Receives companion scout reports and commits to demo profile.

const ProfilePaths := preload("res://scripts/profile_paths.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

var total_elapsed: float = 0.0
var no_session_elapsed: float = 0.0
var had_sync: bool = false
var finished: bool = false
var total_applied: int = 0
var import_port: int = 7352

func _ready() -> void:
	# 1. Resolve demo profile paths
	var profile = ProfilePaths.resolve_from_cmdline()
	if not profile.ok:
		printerr("Failed to resolve profile paths: " + profile.error)
		get_tree().quit(1)
		return

	if not profile.is_demo:
		# Default to demo profile if not explicitly specified on cmdline
		profile = ProfilePaths.resolve(["--demo"])

	# Ensure demo directories exist
	DirAccess.make_dir_recursive_absolute(profile.identity_dir)

	# Configure DB and Identity for demo profile
	DB.configure_paths(profile.db_path, profile.db_tmp_path)
	DB.init_db()

	var identity = PcIdentity.new()
	identity.configure_dir(profile.identity_dir)
	if not identity.load_or_create():
		printerr("Failed to load or create identity for demo import")
		get_tree().quit(1)
		return
	SyncServer.configure_identity(identity)

	# Configure pairing code
	var now_unix = int(Time.get_unix_time_from_system())
	var pair_code = SyncServer.pairing_codes.new_code(now_unix)

	# Connect signal for sync completion
	SyncServer.sync_completed.connect(_on_sync_completed)

	# Parse port if provided in cmdline (--port <num> or --port=<num>)
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var i = 0
	while i < args.size():
		var arg = str(args[i]).strip_edges()
		if arg == "--port" and i + 1 < args.size():
			import_port = int(args[i + 1])
			i += 1
		elif arg.begins_with("--port="):
			import_port = int(arg.substr(7))
		i += 1

	# Start SyncServer on demo port
	var err = SyncServer.start_server(import_port)
	if err != OK:
		printerr("Failed to start sync server on port %d: %d" % [import_port, err])
		get_tree().quit(1)
		return

	# Readiness line
	var ready_payload = {
		"port": import_port,
		"fp": identity.fingerprint_hex(),
		"pair": pair_code,
		"pcId": identity.pc_id
	}
	print("DEMO_READY " + JSON.stringify(ready_payload))

func _on_sync_completed(_peer_id: String, applied_count: int) -> void:
	had_sync = true
	total_applied += applied_count
	no_session_elapsed = 0.0

func _process(delta: float) -> void:
	total_elapsed += delta
	if total_elapsed >= 120.0:
		print("DEMO_TIMEOUT")
		get_tree().quit(1)
		return

	if had_sync and not finished:
		if SyncServer._current_session != null and SyncServer._current_session.state != SyncServer.ActiveSession.State.CLOSED:
			no_session_elapsed = 0.0
		else:
			no_session_elapsed += delta
			if no_session_elapsed >= 3.0:
				finished = true
				_finish_and_quit()

func _finish_and_quit() -> void:
	if DB.is_open():
		if DB.get_db_meta("home_cell", "").is_empty():
			var place_rows = DB._rows("SELECT cell_x, cell_y FROM place_node WHERE cell_x IS NOT NULL ORDER BY visit_count DESC LIMIT 1;")
			if not place_rows.is_empty():
				var hc = Vector2i(int(place_rows[0]["cell_x"]), int(place_rows[0]["cell_y"]))
				RevealEngine.designate_home(DB, {}, [], hc)
		RevealEngine.apply(DB)
	print("DEMO_IMPORT_COMPLETE applied %d rows" % total_applied)
	DB.close()
	get_tree().quit(0)
