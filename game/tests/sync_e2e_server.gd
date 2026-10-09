extends Node

# End-to-end sync server scene script (Item 3c / Decision 11)
# Listens on port 7351, prints E2E_READY, waits for sessions, prints E2E_STATE and quits.

var total_elapsed: float = 0.0
var no_session_elapsed: float = 0.0
var had_sync: bool = false
var finished: bool = false

func _ready() -> void:
	# Ensure test directories exist
	DirAccess.make_dir_recursive_absolute("user://test/sync_identity_e2e/")

	# Clean any stale test files
	var dir = DirAccess.open("user://test/")
	if dir != null:
		for f in ["e2e.db", "e2e.db-wal", "e2e.db-shm", "e2e.db.tmp"]:
			if dir.file_exists(f):
				dir.remove(f)
	var id_dir = DirAccess.open("user://test/sync_identity_e2e/")
	if id_dir != null:
		for f in ["pc.key", "pc.crt", "pc_id.txt"]:
			if id_dir.file_exists(f):
				id_dir.remove(f)

	# Configure test DB
	DB.configure_paths("user://test/e2e.db", "user://test/e2e.db.tmp")
	DB.init_db()

	# Configure identity
	var identity = PcIdentity.new()
	identity.configure_dir("user://test/sync_identity_e2e/")
	if not identity.load_or_create():
		printerr("Failed to load or create identity for e2e")
		get_tree().quit(1)
		return
	SyncServer.configure_identity(identity)

	# Configure pairing code
	var now_unix = int(Time.get_unix_time_from_system())
	var pair_code = SyncServer.pairing_codes.new_code(now_unix)

	# Connect signal for sync completion
	SyncServer.sync_completed.connect(_on_sync_completed)

	# Start SyncServer on port 7351
	var err = SyncServer.start_server(7351)
	if err != OK:
		printerr("Failed to start sync server on port 7351: ", err)
		get_tree().quit(1)
		return

	# Ready line
	var ready_payload = {
		"port": 7351,
		"fp": identity.fingerprint_hex(),
		"pair": pair_code,
		"pcId": identity.pc_id
	}
	print("E2E_READY " + JSON.stringify(ready_payload))

func _on_sync_completed(_peer_id: String, _applied_count: int) -> void:
	had_sync = true
	no_session_elapsed = 0.0

func _process(delta: float) -> void:
	total_elapsed += delta
	if total_elapsed >= 120.0:
		print("E2E_TIMEOUT")
		get_tree().quit(1)
		return

	if had_sync and not finished:
		if SyncServer._current_session != null and SyncServer._current_session.state != SyncServer.ActiveSession.State.CLOSED:
			no_session_elapsed = 0.0
		else:
			no_session_elapsed += delta
			if no_session_elapsed >= 5.0:
				finished = true
				_print_state_and_quit()

func _print_state_and_quit() -> void:
	var v_rows = DB._rows("SELECT count(*) as c FROM visit_log;")
	var m_rows = DB._rows("SELECT count(*) as c FROM map_cell;")
	var p_rows = DB._rows("SELECT count(*) as c FROM place_node;")
	var peer_rows = DB._rows("SELECT max(last_applied_seq) as s FROM sync_peer;")

	var v_cnt = int(v_rows[0].get("c", 0)) if not v_rows.is_empty() else 0
	var m_cnt = int(m_rows[0].get("c", 0)) if not m_rows.is_empty() else 0
	var p_cnt = int(p_rows[0].get("c", 0)) if not p_rows.is_empty() else 0
	var last_seq = 0
	if not peer_rows.is_empty() and peer_rows[0].get("s") != null:
		last_seq = int(peer_rows[0].get("s"))

	var state = {
		"visit_log": v_cnt,
		"map_cell": m_cnt,
		"place_node": p_cnt,
		"last_applied_seq": last_seq
	}
	print("E2E_STATE " + JSON.stringify(state))
	SyncServer.stop_server()
	DB.close()
	get_tree().quit(0)
