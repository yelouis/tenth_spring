extends Node

# DB Autoload Singleton for Tenth Spring PC Engine
# Canonical persistence via vendored godot-sqlite v4.4 GDExtension.
# Uses WAL journal mode, synchronous FULL, bound parameters on all queries,
# and one-time legacy JSON import without runtime fallback.

const CURRENT_SCHEMA_VERSION: int = 1
const DEFAULT_DB_PATH: String = "user://tenth_spring.db"
const DEFAULT_DB_TMP_PATH: String = "user://tenth_spring.db.tmp"
const JSON_BAK_PATH: String = "user://tenth_spring.db.jsonbak"

var DB_PATH: String = DEFAULT_DB_PATH
var DB_TMP_PATH: String = DEFAULT_DB_TMP_PATH

var _db: Object = null
var _in_transaction: bool = false
var last_error: String = ""
var _active_bak_path: String = ""

const MIGRATIONS: Array = []

func configure_paths(new_db_path: String, new_tmp_path: String) -> void:
	DB_PATH = new_db_path
	DB_TMP_PATH = new_tmp_path
	if _db != null:
		_db.path = DB_PATH

func assert_test_safe() -> bool:
	if DB_PATH == DEFAULT_DB_PATH or DB_TMP_PATH == DEFAULT_DB_TMP_PATH:
		push_error("FAIL: active save path equals production save file user://tenth_spring.db; test cannot run against production save file")
		return false
	return true

func _ready() -> void:
	pass

func init_db() -> void:
	var legacy_pending = _detect_and_rotate_legacy_store()

	if not ClassDB.can_instantiate("SQLite"):
		print("storage: UNAVAILABLE — SQLite extension missing")
		push_error("storage: UNAVAILABLE — SQLite extension missing")
		_db = null
		return

	var base_dir = DB_PATH.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

	_db = ClassDB.instantiate("SQLite")
	_db.path = DB_PATH
	_db.foreign_keys = true
	_db.verbosity_level = 1
	if not _db.open_db():
		var err_msg = _db.error_message
		print("storage: UNAVAILABLE — cannot open " + DB_PATH + ": " + err_msg)
		push_error("storage: UNAVAILABLE — cannot open " + DB_PATH + ": " + err_msg)
		_db = null
		return

	_q("PRAGMA journal_mode=WAL;")
	_q("PRAGMA synchronous=FULL;")
	print("storage: SQLite extension")

	_run_migrations(MIGRATIONS)

	if legacy_pending or _has_unimported_legacy_bak():
		_run_legacy_import()

func _q(sql: String, params: Array = []) -> bool:
	if _db == null:
		last_error = "SQLite extension not available"
		push_error(last_error)
		return false
	var ok: bool = _db.query_with_bindings(sql, params)
	if not ok:
		last_error = _db.error_message
		push_error("SQLite query failed: " + last_error)
	return ok

func _rows(sql: String, params: Array = []) -> Array:
	if not _q(sql, params):
		return []
	var res = _db.query_result
	return res.duplicate(true) if typeof(res) == TYPE_ARRAY else []

func execute_query(sql: String) -> bool:
	return _q(sql)

func begin_transaction() -> bool:
	if _in_transaction:
		last_error = "Nested transaction not allowed"
		push_error(last_error)
		return false
	var ok = _q("BEGIN IMMEDIATE;")
	if ok:
		_in_transaction = true
	return ok

func commit_transaction() -> bool:
	_in_transaction = false
	return _q("COMMIT;")

func rollback_transaction() -> bool:
	_in_transaction = false
	return _q("ROLLBACK;")

func _run_migrations(migrations: Array = MIGRATIONS) -> void:
	if _db == null:
		return

	var meta_rows = _rows("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'meta';")
	if meta_rows.is_empty():
		if not begin_transaction():
			return
		var ddl_statements = [
			"CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
			"CREATE TABLE IF NOT EXISTS world_clock (id INTEGER PRIMARY KEY CHECK (id = 1), game_epoch_minutes INTEGER NOT NULL DEFAULT 0, last_wall_sync INTEGER NOT NULL DEFAULT 0);",
			"CREATE TABLE IF NOT EXISTS map_cell (cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL, reveal_state INTEGER NOT NULL DEFAULT 0, tile_blob BLOB, first_revealed_at INTEGER, cell_seed INTEGER NOT NULL, PRIMARY KEY (cell_x, cell_y));",
			"CREATE TABLE IF NOT EXISTS place_node (id TEXT PRIMARY KEY, name TEXT, category INTEGER NOT NULL, cell_x INTEGER, cell_y INTEGER, tile_x INTEGER, tile_y INTEGER, reveal_state INTEGER NOT NULL DEFAULT 1, visit_count INTEGER NOT NULL DEFAULT 0, last_real_visit_at INTEGER, loot_state INTEGER NOT NULL DEFAULT 0, danger_tier INTEGER NOT NULL DEFAULT 1);",
			"CREATE TABLE IF NOT EXISTS visit_log (seq INTEGER NOT NULL, peer_id TEXT NOT NULL, place_id TEXT, lat REAL, lon REAL, started_at INTEGER, dwell_seconds INTEGER, kind TEXT NOT NULL, PRIMARY KEY (peer_id, seq));",
			"CREATE TABLE IF NOT EXISTS sync_peer (peer_id TEXT PRIMARY KEY, device_token_hash BLOB, last_applied_seq INTEGER NOT NULL DEFAULT 0, last_body_lat REAL, last_body_lon REAL, last_body_ts INTEGER);",
			"CREATE TABLE IF NOT EXISTS player_profile (id INTEGER PRIMARY KEY CHECK (id = 1), trainer_name TEXT, sprite_index INTEGER DEFAULT 0, pos_tile_x INTEGER, pos_tile_y INTEGER);",
			"CREATE TABLE IF NOT EXISTS base_state (id INTEGER PRIMARY KEY CHECK (id = 1), home_cell_x INTEGER, home_cell_y INTEGER);",
			"CREATE TABLE IF NOT EXISTS osm_cache (cell_x INTEGER, cell_y INTEGER, fetched_at INTEGER, payload BLOB, PRIMARY KEY (cell_x, cell_y));",
			"INSERT OR IGNORE INTO world_clock (id, game_epoch_minutes, last_wall_sync) VALUES (1, 0, 0);",
			"INSERT OR IGNORE INTO player_profile (id, trainer_name, sprite_index, pos_tile_x, pos_tile_y) VALUES (1, NULL, 0, 0, 0);",
			"INSERT OR IGNORE INTO base_state (id, home_cell_x, home_cell_y) VALUES (1, 0, 0);",
			"INSERT INTO meta (key, value) VALUES ('schema_version', '1');"
		]
		for stmt in ddl_statements:
			if not _q(stmt):
				var err = last_error
				rollback_transaction()
				print("storage: UNAVAILABLE — migration 1 failed: " + err)
				close()
				return
		commit_transaction()

	var current_version = get_schema_version()
	var sorted_migrations = migrations.duplicate(true)
	sorted_migrations.sort_custom(func(a, b): return a.get("version", 0) < b.get("version", 0))

	for mig in sorted_migrations:
		var v = int(mig.get("version", 0))
		if v > current_version:
			if not begin_transaction():
				return
			var stmts = mig.get("statements", [])
			for stmt in stmts:
				if not _q(stmt):
					var err = last_error
					rollback_transaction()
					print("storage: UNAVAILABLE — migration " + str(v) + " failed: " + err)
					close()
					return
			if not _q("UPDATE meta SET value = ? WHERE key = 'schema_version';", [str(v)]):
				var err = last_error
				rollback_transaction()
				print("storage: UNAVAILABLE — migration " + str(v) + " failed: " + err)
				close()
				return
			commit_transaction()
			current_version = v

func _detect_and_rotate_legacy_store() -> bool:
	_active_bak_path = ""
	if not FileAccess.file_exists(DB_PATH):
		return false
	var fa = FileAccess.open(DB_PATH, FileAccess.READ)
	if fa == null:
		return false
	var header = fa.get_buffer(16)
	fa.close()
	var sqlite_magic = PackedByteArray([0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00])
	if header == sqlite_magic:
		return false

	var base_bak = DB_PATH + ".jsonbak"
	var target_bak = base_bak
	if FileAccess.file_exists(target_bak):
		var idx = 1
		while FileAccess.file_exists(base_bak + "." + str(idx)):
			idx += 1
		target_bak = base_bak + "." + str(idx)

	var err = DirAccess.rename_absolute(DB_PATH, target_bak)
	if err != OK:
		push_error("Failed to rename legacy store to bak: " + target_bak)
		return false

	_active_bak_path = target_bak
	if FileAccess.file_exists(DB_TMP_PATH):
		DirAccess.rename_absolute(DB_TMP_PATH, target_bak + ".tmp")
	return true

func _has_unimported_legacy_bak() -> bool:
	var rows = _rows("SELECT value FROM meta WHERE key = 'legacy_import';")
	if not rows.is_empty():
		return false
	var base_bak = DB_PATH + ".jsonbak"
	return FileAccess.file_exists(base_bak)

func _get_candidate_bak_path() -> String:
	if _active_bak_path != "" and FileAccess.file_exists(_active_bak_path):
		return _active_bak_path
	var base_bak = DB_PATH + ".jsonbak"
	if FileAccess.file_exists(base_bak):
		return base_bak
	return ""

func _run_legacy_import() -> void:
	var rows = _rows("SELECT value FROM meta WHERE key = 'legacy_import';")
	if not rows.is_empty():
		return

	var bak_path = _get_candidate_bak_path()
	if bak_path == "":
		return

	var data = null
	if FileAccess.file_exists(bak_path):
		var text = FileAccess.get_file_as_string(bak_path)
		if text.strip_edges() != "":
			data = JSON.parse_string(text)
	if (data == null or typeof(data) != TYPE_DICTIONARY) and FileAccess.file_exists(bak_path + ".tmp"):
		var tmp_text = FileAccess.get_file_as_string(bak_path + ".tmp")
		if tmp_text.strip_edges() != "":
			data = JSON.parse_string(tmp_text)

	if data == null or typeof(data) != TYPE_DICTIONARY:
		push_warning("Legacy bak was unparseable; skipping legacy import.")
		return

	if not begin_transaction():
		return

	var wc = data.get("world_clock", {})
	if typeof(wc) == TYPE_DICTIONARY and not wc.is_empty():
		_q("UPDATE world_clock SET game_epoch_minutes = ?, last_wall_sync = ? WHERE id = 1;", [
			int(wc.get("game_epoch_minutes", 0)),
			int(wc.get("last_wall_sync", 0))
		])

	var prof = data.get("player_profile", {})
	if typeof(prof) == TYPE_DICTIONARY and not prof.is_empty():
		var t_name = prof.get("survivor_name", prof.get("trainer_name", null))
		_q("UPDATE player_profile SET trainer_name = ?, sprite_index = ?, pos_tile_x = ?, pos_tile_y = ? WHERE id = 1;", [
			t_name,
			int(prof.get("sprite_index", 0)),
			int(prof.get("pos_tile_x", 0)),
			int(prof.get("pos_tile_y", 0))
		])

	var bs = data.get("base_state", {})
	if typeof(bs) == TYPE_DICTIONARY and not bs.is_empty():
		_q("UPDATE base_state SET home_cell_x = ?, home_cell_y = ? WHERE id = 1;", [
			int(bs.get("home_cell_x", 0)),
			int(bs.get("home_cell_y", 0))
		])

	var cells = data.get("map_cell", {})
	if typeof(cells) == TYPE_DICTIONARY:
		for cell_key in cells:
			var c = cells[cell_key]
			var cx = int(c.get("cell_x", 0))
			var cy = int(c.get("cell_y", 0))
			var rev = int(c.get("reveal_state", 0))
			var seed_val = int(c.get("cell_seed", 0))
			var first_rev = int(c.get("first_revealed_at", Time.get_unix_time_from_system()))
			_q("INSERT INTO map_cell (cell_x, cell_y, reveal_state, first_revealed_at, cell_seed) VALUES (?, ?, ?, ?, ?) ON CONFLICT(cell_x, cell_y) DO UPDATE SET reveal_state = MAX(map_cell.reveal_state, excluded.reveal_state);", [
				cx, cy, rev, first_rev, seed_val
			])

	var places = data.get("place_node", {})
	if typeof(places) == TYPE_DICTIONARY:
		for pid in places:
			var p = places[pid]
			_q("INSERT INTO place_node (id, name, category, cell_x, cell_y, reveal_state, visit_count, last_real_visit_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET visit_count = place_node.visit_count + excluded.visit_count, last_real_visit_at = excluded.last_real_visit_at, reveal_state = MAX(place_node.reveal_state, excluded.reveal_state);", [
				str(p.get("id", pid)),
				str(p.get("name", "")),
				int(p.get("category", 1)),
				int(p.get("cell_x", 0)),
				int(p.get("cell_y", 0)),
				int(p.get("reveal_state", 1)),
				int(p.get("visit_count", 1)),
				int(p.get("last_real_visit_at", Time.get_unix_time_from_system()))
			])

	var visits = data.get("visit_log", {})
	if typeof(visits) == TYPE_DICTIONARY:
		for vkey in visits:
			var v = visits[vkey]
			_q("INSERT INTO visit_log (seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?);", [
				int(v.get("seq", 0)),
				str(v.get("peer_id", "")),
				v.get("place_id", null),
				float(v.get("lat", 0.0)),
				float(v.get("lon", 0.0)),
				int(v.get("started_at", 0)),
				int(v.get("dwell_seconds", 0)),
				str(v.get("kind", "visit"))
			])

	var peers = data.get("sync_peer", {})
	if typeof(peers) == TYPE_DICTIONARY:
		for peer_id in peers:
			var sp = peers[peer_id]
			_q("INSERT INTO sync_peer (peer_id, last_applied_seq, last_body_lat, last_body_lon, last_body_ts) VALUES (?, ?, ?, ?, ?) ON CONFLICT(peer_id) DO UPDATE SET last_applied_seq = MAX(sync_peer.last_applied_seq, excluded.last_applied_seq), last_body_lat = excluded.last_body_lat, last_body_lon = excluded.last_body_lon, last_body_ts = excluded.last_body_ts;", [
				str(sp.get("peer_id", peer_id)),
				int(sp.get("last_applied_seq", 0)),
				float(sp.get("last_body_lat", 0.0)),
				float(sp.get("last_body_lon", 0.0)),
				int(sp.get("last_body_ts", 0))
			])

	var inv = data.get("inventory_item", [])
	if typeof(inv) == TYPE_ARRAY and inv.size() > 0:
		print("legacy import: dropped " + str(inv.size()) + " inventory_item entries")

	var bak_filename = bak_path.get_file()
	if not _q("INSERT INTO meta (key, value) VALUES ('legacy_import', ?);", [bak_filename]):
		rollback_transaction()
		print("storage: UNAVAILABLE — legacy import mismatch")
		return

	var cell_count_rows = _rows("SELECT COUNT(*) as c FROM map_cell;")
	var place_count_rows = _rows("SELECT COUNT(*) as c FROM place_node;")
	var visit_count_rows = _rows("SELECT COUNT(*) as c FROM visit_log;")
	var peer_count_rows = _rows("SELECT COUNT(*) as c FROM sync_peer;")

	var exp_cells = cells.size() if typeof(cells) == TYPE_DICTIONARY else 0
	var exp_places = places.size() if typeof(places) == TYPE_DICTIONARY else 0
	var exp_visits = visits.size() if typeof(visits) == TYPE_DICTIONARY else 0
	var exp_peers = peers.size() if typeof(peers) == TYPE_DICTIONARY else 0

	var act_cells = int(cell_count_rows[0].get("c", 0)) if not cell_count_rows.is_empty() else 0
	var act_places = int(place_count_rows[0].get("c", 0)) if not place_count_rows.is_empty() else 0
	var act_visits = int(visit_count_rows[0].get("c", 0)) if not visit_count_rows.is_empty() else 0
	var act_peers = int(peer_count_rows[0].get("c", 0)) if not peer_count_rows.is_empty() else 0

	if act_cells != exp_cells or act_places != exp_places or act_visits != exp_visits or act_peers != exp_peers:
		rollback_transaction()
		print("storage: UNAVAILABLE — legacy import mismatch")
		return

	commit_transaction()

func get_map_cell(cell_x: int, cell_y: int) -> Dictionary:
	var rows = _rows("SELECT cell_x, cell_y, reveal_state, first_revealed_at, cell_seed FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [cell_x, cell_y])
	return rows[0] if not rows.is_empty() else {}

func upsert_map_cell(cell_x: int, cell_y: int, reveal_state: int, cell_seed: int = 0) -> void:
	last_error = ""
	var now = int(Time.get_unix_time_from_system())
	_q("INSERT INTO map_cell (cell_x, cell_y, reveal_state, first_revealed_at, cell_seed) VALUES (?, ?, ?, ?, ?) ON CONFLICT(cell_x, cell_y) DO UPDATE SET reveal_state = MAX(map_cell.reveal_state, excluded.reveal_state);", [
		cell_x, cell_y, reveal_state, now, cell_seed
	])

func get_place_node(id: String) -> Dictionary:
	var rows = _rows("SELECT * FROM place_node WHERE id = ?;", [id])
	return rows[0] if not rows.is_empty() else {}

func upsert_place_node(node: Dictionary) -> void:
	last_error = ""
	var id = str(node.get("id", ""))
	if id == "":
		return
	var name = str(node.get("name", ""))
	var category = int(node.get("category", 1))
	var cell_x = int(node.get("cell_x", 0))
	var cell_y = int(node.get("cell_y", 0))
	var reveal_state = int(node.get("reveal_state", 1))
	var visit_count = int(node.get("visit_count", 1))
	var last_real_visit_at = int(node.get("last_real_visit_at", Time.get_unix_time_from_system()))
	_q("INSERT INTO place_node (id, name, category, cell_x, cell_y, reveal_state, visit_count, last_real_visit_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET visit_count = place_node.visit_count + excluded.visit_count, last_real_visit_at = excluded.last_real_visit_at, reveal_state = MAX(place_node.reveal_state, excluded.reveal_state);", [
		id, name, category, cell_x, cell_y, reveal_state, visit_count, last_real_visit_at
	])

func is_visit_logged(peer_id: String, seq: int) -> bool:
	var rows = _rows("SELECT 1 FROM visit_log WHERE peer_id = ? AND seq = ?;", [peer_id, seq])
	return not rows.is_empty()

func insert_visit_log(row: Dictionary) -> bool:
	last_error = ""
	var peer_id = str(row.get("peer_id", ""))
	var seq = int(row.get("seq", 0))
	if is_visit_logged(peer_id, seq):
		return false
	var place_id = row.get("place_id", null)
	var lat = float(row.get("lat", 0.0))
	var lon = float(row.get("lon", 0.0))
	var started_at = int(row.get("started_at", 0))
	var dwell_seconds = int(row.get("dwell_seconds", 0))
	var kind = str(row.get("kind", "visit"))
	return _q("INSERT INTO visit_log (seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?);", [
		seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind
	])

func get_sync_peer(peer_id: String) -> Dictionary:
	var rows = _rows("SELECT * FROM sync_peer WHERE peer_id = ?;", [peer_id])
	return rows[0] if not rows.is_empty() else {}

func update_sync_peer(peer_id: String, last_applied_seq: int, body_lat: float, body_lon: float, body_ts: int) -> void:
	last_error = ""
	_q("INSERT INTO sync_peer (peer_id, last_applied_seq, last_body_lat, last_body_lon, last_body_ts) VALUES (?, ?, ?, ?, ?) ON CONFLICT(peer_id) DO UPDATE SET last_applied_seq = MAX(sync_peer.last_applied_seq, excluded.last_applied_seq), last_body_lat = excluded.last_body_lat, last_body_lon = excluded.last_body_lon, last_body_ts = excluded.last_body_ts;", [
		peer_id, last_applied_seq, body_lat, body_lon, body_ts
	])

func get_base_state() -> Dictionary:
	var rows = _rows("SELECT * FROM base_state WHERE id = 1;")
	return rows[0] if not rows.is_empty() else {}

func set_player_tile(tile_x: int, tile_y: int) -> void:
	last_error = ""
	_q("UPDATE player_profile SET pos_tile_x = ?, pos_tile_y = ? WHERE id = 1;", [tile_x, tile_y])

func get_schema_version() -> int:
	if _db == null:
		return 0
	var rows = _rows("SELECT value FROM meta WHERE key = 'schema_version';")
	if rows.is_empty():
		return 0
	return int(rows[0].get("value", 0))

func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null
	_in_transaction = false
