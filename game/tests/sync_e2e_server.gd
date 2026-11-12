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

	var kind_rows = DB._rows("SELECT kind, count(*) as c FROM visit_log GROUP BY kind ORDER BY kind;")
	var visit_kinds := {}
	for kr in kind_rows:
		visit_kinds[str(kr.get("kind", ""))] = int(kr.get("c", 0))

	var ar_rows = DB.get_all_area_reveals()
	var area_keys: Array[String] = []
	for ar in ar_rows:
		area_keys.append(str(ar.get("area_key", "")))

	var dl_rows = DB.get_all_distort_entries()
	var distort_ids: Array[String] = []
	for dr in dl_rows:
		distort_ids.append(str(dr.get("place_id", "")))

	var ns_ids: Array[String] = []
	var ns_tbl = DB._rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'neighbourhood_state';")
	if not ns_tbl.is_empty():
		var ns_rows = DB._rows("SELECT area_id FROM neighbourhood_state ORDER BY area_id;")
		for nr in ns_rows:
			ns_ids.append(str(nr.get("area_id", "")))

	# Scan every table in sqlite_master and every REAL column for non-NULL values
	var non_null_real_count := 0
	var tables = DB._rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
	for t in tables:
		var t_name := str(t.get("name", ""))
		var cols = DB._rows("PRAGMA table_info(" + t_name + ");")
		for col in cols:
			var col_type := str(col.get("type", "")).to_upper()
			if col_type.contains("REAL"):
				var col_name := str(col.get("name", ""))
				var cnt_rows = DB._rows("SELECT count(*) as c FROM " + t_name + " WHERE " + col_name + " IS NOT NULL;")
				if not cnt_rows.is_empty():
					non_null_real_count += int(cnt_rows[0].get("c", 0))

	var state = {
		"visit_log": v_cnt,
		"visit_log_kinds": visit_kinds,
		"area_reveal": area_keys,
		"distort_list": distort_ids,
		"neighbourhood_state": ns_ids,
		"map_cell": m_cnt,
		"place_node": p_cnt,
		"last_applied_seq": last_seq,
		"non_null_real_count": non_null_real_count
	}
	print("E2E_STATE " + JSON.stringify(state))
	SyncServer.stop_server()
	DB.close()
	get_tree().quit(0)
