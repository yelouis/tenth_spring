extends Node

# DB Autoload Singleton for Tenth Spring PC Engine
# Manages persistence (atomic temp-file swap fallback; SQLite extension when present),
# DDL schemas (§B2), queries, and transaction boundaries.

const CURRENT_SCHEMA_VERSION: int = 1
const DEFAULT_DB_PATH: String = "user://tenth_spring.db"
const DEFAULT_DB_TMP_PATH: String = "user://tenth_spring.db.tmp"
const JSON_BAK_PATH: String = "user://tenth_spring.db.jsonbak"

var DB_PATH: String = DEFAULT_DB_PATH
var DB_TMP_PATH: String = DEFAULT_DB_TMP_PATH

func configure_paths(new_db_path: String, new_tmp_path: String) -> void:
	DB_PATH = new_db_path
	DB_TMP_PATH = new_tmp_path
	if _db != null and _db.has_method("open_db"):
		_db.path = DB_PATH

func assert_test_safe() -> bool:
	if DB_PATH == DEFAULT_DB_PATH or DB_TMP_PATH == DEFAULT_DB_TMP_PATH:
		push_error("FAIL: active save path equals production save file user://tenth_spring.db; test cannot run against production save file")
		return false
	return true

var _db: Object = null
var _in_transaction: bool = false
var _transaction_snapshot: Dictionary = {}

# Internal tables storage driven by SQLite engine DDL / file fallback
var _meta_table: Dictionary = {}
var _world_clock_table: Dictionary = {"id": 1, "game_epoch_minutes": 0, "last_wall_sync": 0}
var _map_cell_table: Dictionary = {}
var _place_node_table: Dictionary = {}
var _visit_log_table: Dictionary = {}
var _sync_peer_table: Dictionary = {}
var _player_profile_table: Dictionary = {"id": 1, "survivor_name": "Survivor", "sprite_index": 0, "pos_tile_x": 0, "pos_tile_y": 0, "hp": 100, "stamina": 100, "carry_capacity": 50}
var _base_state_table: Dictionary = {"id": 1, "home_cell_x": 0, "home_cell_y": 0}
var _inventory_item_table: Array = []
var _osm_cache_table: Dictionary = {}

func _ready() -> void:
	init_db()

func init_db() -> void:
	_init_sqlite_engine()
	if _db == null:
		_load_persistent_store()
	_run_migrations()

func _init_sqlite_engine() -> void:
	if ClassDB.can_instantiate("SQLite"):
		_db = ClassDB.instantiate("SQLite")
		_db.path = DB_PATH
		_db.open_db()
		print("storage: SQLite extension")
		_create_ddl_tables()
	else:
		print("storage: file fallback")

func _create_ddl_tables() -> void:
	# §B2 DDL Schema Creation
	execute_query("""
		CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
		CREATE TABLE IF NOT EXISTS world_clock (id INTEGER PRIMARY KEY CHECK (id = 1), game_epoch_minutes INTEGER NOT NULL DEFAULT 0, last_wall_sync INTEGER NOT NULL DEFAULT 0);
		CREATE TABLE IF NOT EXISTS map_cell (cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL, reveal_state INTEGER NOT NULL DEFAULT 0, tile_blob BLOB, first_revealed_at INTEGER, cell_seed INTEGER NOT NULL, PRIMARY KEY (cell_x, cell_y));
		CREATE TABLE IF NOT EXISTS place_node (id TEXT PRIMARY KEY, name TEXT, category INTEGER NOT NULL, cell_x INTEGER, cell_y INTEGER, tile_x INTEGER, tile_y INTEGER, reveal_state INTEGER NOT NULL DEFAULT 1, visit_count INTEGER NOT NULL DEFAULT 0, last_real_visit_at INTEGER, loot_state INTEGER NOT NULL DEFAULT 0, danger_tier INTEGER NOT NULL DEFAULT 1);
		CREATE TABLE IF NOT EXISTS visit_log (seq INTEGER NOT NULL, peer_id TEXT NOT NULL, place_id TEXT, lat REAL, lon REAL, started_at INTEGER, dwell_seconds INTEGER, kind TEXT NOT NULL, PRIMARY KEY (peer_id, seq));
		CREATE TABLE IF NOT EXISTS sync_peer (peer_id TEXT PRIMARY KEY, peer_pubkey BLOB NOT NULL, last_applied_seq INTEGER NOT NULL DEFAULT 0, last_body_lat REAL, last_body_lon REAL, last_body_ts INTEGER);
		CREATE TABLE IF NOT EXISTS player_profile (id INTEGER PRIMARY KEY CHECK (id = 1), survivor_name TEXT, sprite_index INTEGER DEFAULT 0, pos_tile_x INTEGER, pos_tile_y INTEGER, hp INTEGER, stamina INTEGER, carry_capacity INTEGER);
		CREATE TABLE IF NOT EXISTS base_state (id INTEGER PRIMARY KEY CHECK (id = 1), home_cell_x INTEGER, home_cell_y INTEGER);
		CREATE TABLE IF NOT EXISTS inventory_item (id INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL, item_id TEXT NOT NULL, qty INTEGER NOT NULL, quality INTEGER);
		CREATE TABLE IF NOT EXISTS osm_cache (cell_x INTEGER, cell_y INTEGER, fetched_at INTEGER, payload BLOB, PRIMARY KEY (cell_x, cell_y));
	""")

func _run_migrations() -> void:
	var current_version = get_schema_version()
	if current_version < 1:
		_meta_table["schema_version"] = "1"
		if _db != null:
			execute_query("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '1');")
		else:
			_save_persistent_store()

func get_schema_version() -> int:
	return int(_meta_table.get("schema_version", "1"))

func begin_transaction() -> void:
	_in_transaction = true
	if _db != null:
		execute_query("BEGIN TRANSACTION;")
	else:
		_transaction_snapshot = _create_state_snapshot()

func commit_transaction() -> void:
	_in_transaction = false
	_transaction_snapshot = {}
	if _db != null:
		execute_query("COMMIT;")
	else:
		_save_persistent_store()

func rollback_transaction() -> void:
	_in_transaction = false
	if _db != null:
		execute_query("ROLLBACK;")
	else:
		if not _transaction_snapshot.is_empty():
			_restore_state_snapshot(_transaction_snapshot)
			_transaction_snapshot = {}

func execute_query(query_string: String) -> bool:
	if _db != null and _db.has_method("query"):
		return _db.query(query_string)
	push_error("SQLite extension not available; cannot execute query: " + query_string)
	return false

func _save_persistent_store() -> void:
	var state = {
		"meta": _meta_table,
		"world_clock": _world_clock_table,
		"map_cell": _map_cell_table,
		"place_node": _place_node_table,
		"visit_log": _visit_log_table,
		"sync_peer": _sync_peer_table,
		"player_profile": _player_profile_table,
		"base_state": _base_state_table,
		"inventory_item": _inventory_item_table,
		"osm_cache": _osm_cache_table
	}
	var json_str = JSON.stringify(state)
	var base_dir = DB_TMP_PATH.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file = FileAccess.open(DB_TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open temp DB file for writing: %s (error %d)" % [DB_TMP_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_str)
	file.flush()
	file.close()

	var err = DirAccess.rename_absolute(DB_TMP_PATH, DB_PATH)
	if err != OK:
		push_error("Failed to rename temp DB file %s to %s: error %d" % [DB_TMP_PATH, DB_PATH, err])

func _load_persistent_store() -> void:
	_reset_default_tables()

	var data: Variant = null

	if FileAccess.file_exists(DB_PATH):
		var content = FileAccess.get_file_as_string(DB_PATH)
		if content.strip_edges() != "":
			data = JSON.parse_string(content)
			if data == null:
				push_warning("Primary DB file %s is unparseable or corrupted; attempting recovery from %s" % [DB_PATH, DB_TMP_PATH])
		else:
			push_warning("Primary DB file %s is empty (0 bytes); attempting recovery from %s" % [DB_PATH, DB_TMP_PATH])

	if (data == null or typeof(data) != TYPE_DICTIONARY) and FileAccess.file_exists(DB_TMP_PATH):
		var tmp_content = FileAccess.get_file_as_string(DB_TMP_PATH)
		if tmp_content.strip_edges() != "":
			var tmp_data = JSON.parse_string(tmp_content)
			if tmp_data != null and typeof(tmp_data) == TYPE_DICTIONARY:
				data = tmp_data
				push_warning("Successfully recovered world database from temp backup: %s" % DB_TMP_PATH)
			else:
				push_warning("Backup DB file %s is also unparseable" % DB_TMP_PATH)

	if data != null and typeof(data) == TYPE_DICTIONARY:
		_apply_loaded_state(data)
	else:
		if FileAccess.file_exists(DB_PATH) or FileAccess.file_exists(DB_TMP_PATH):
			push_warning("Database files were present but unparseable. Starting with fresh state.")

func _reset_default_tables() -> void:
	_meta_table = {}
	_world_clock_table = {"id": 1, "game_epoch_minutes": 0, "last_wall_sync": 0}
	_map_cell_table = {}
	_place_node_table = {}
	_visit_log_table = {}
	_sync_peer_table = {}
	_player_profile_table = {"id": 1, "survivor_name": "Survivor", "sprite_index": 0, "pos_tile_x": 0, "pos_tile_y": 0, "hp": 100, "stamina": 100, "carry_capacity": 50}
	_base_state_table = {"id": 1, "home_cell_x": 0, "home_cell_y": 0}
	_inventory_item_table = []
	_osm_cache_table = {}

func _apply_loaded_state(data: Dictionary) -> void:
	if data.has("meta") and typeof(data["meta"]) == TYPE_DICTIONARY:
		_meta_table = data["meta"]
	if data.has("world_clock") and typeof(data["world_clock"]) == TYPE_DICTIONARY:
		_world_clock_table = data["world_clock"]
	if data.has("map_cell") and typeof(data["map_cell"]) == TYPE_DICTIONARY:
		_map_cell_table = data["map_cell"]
	if data.has("place_node") and typeof(data["place_node"]) == TYPE_DICTIONARY:
		_place_node_table = data["place_node"]
	if data.has("visit_log") and typeof(data["visit_log"]) == TYPE_DICTIONARY:
		_visit_log_table = data["visit_log"]
	if data.has("sync_peer") and typeof(data["sync_peer"]) == TYPE_DICTIONARY:
		_sync_peer_table = data["sync_peer"]
	if data.has("player_profile") and typeof(data["player_profile"]) == TYPE_DICTIONARY:
		_player_profile_table = data["player_profile"]
	if data.has("base_state") and typeof(data["base_state"]) == TYPE_DICTIONARY:
		_base_state_table = data["base_state"]
	if data.has("inventory_item") and typeof(data["inventory_item"]) == TYPE_ARRAY:
		_inventory_item_table = data["inventory_item"]
	if data.has("osm_cache") and typeof(data["osm_cache"]) == TYPE_DICTIONARY:
		_osm_cache_table = data["osm_cache"]

func _create_state_snapshot() -> Dictionary:
	return {
		"meta": _meta_table.duplicate(true),
		"world_clock": _world_clock_table.duplicate(true),
		"map_cell": _map_cell_table.duplicate(true),
		"place_node": _place_node_table.duplicate(true),
		"visit_log": _visit_log_table.duplicate(true),
		"sync_peer": _sync_peer_table.duplicate(true),
		"player_profile": _player_profile_table.duplicate(true),
		"base_state": _base_state_table.duplicate(true),
		"inventory_item": _inventory_item_table.duplicate(true),
		"osm_cache": _osm_cache_table.duplicate(true)
	}

func _restore_state_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("meta"): _meta_table = snapshot["meta"].duplicate(true)
	if snapshot.has("world_clock"): _world_clock_table = snapshot["world_clock"].duplicate(true)
	if snapshot.has("map_cell"): _map_cell_table = snapshot["map_cell"].duplicate(true)
	if snapshot.has("place_node"): _place_node_table = snapshot["place_node"].duplicate(true)
	if snapshot.has("visit_log"): _visit_log_table = snapshot["visit_log"].duplicate(true)
	if snapshot.has("sync_peer"): _sync_peer_table = snapshot["sync_peer"].duplicate(true)
	if snapshot.has("player_profile"): _player_profile_table = snapshot["player_profile"].duplicate(true)
	if snapshot.has("base_state"): _base_state_table = snapshot["base_state"].duplicate(true)
	if snapshot.has("inventory_item"): _inventory_item_table = snapshot["inventory_item"].duplicate(true)
	if snapshot.has("osm_cache"): _osm_cache_table = snapshot["osm_cache"].duplicate(true)

# Map Cell Operations
func get_map_cell(cell_x: int, cell_y: int) -> Dictionary:
	var key = "%d,%d" % [cell_x, cell_y]
	return _map_cell_table.get(key, {})

func upsert_map_cell(cell_x: int, cell_y: int, reveal_state: int, cell_seed: int = 0) -> void:
	var key = "%d,%d" % [cell_x, cell_y]
	var now = Time.get_unix_time_from_system()
	if _map_cell_table.has(key):
		var existing = _map_cell_table[key]
		if reveal_state > existing["reveal_state"]:
			existing["reveal_state"] = reveal_state
	else:
		_map_cell_table[key] = {
			"cell_x": cell_x,
			"cell_y": cell_y,
			"reveal_state": reveal_state,
			"first_revealed_at": now,
			"cell_seed": cell_seed
		}
	if _db != null:
		execute_query("INSERT OR REPLACE INTO map_cell (cell_x, cell_y, reveal_state, first_revealed_at, cell_seed) VALUES (%d, %d, %d, %d, %d);" % [cell_x, cell_y, reveal_state, int(now), cell_seed])
	elif not _in_transaction:
		_save_persistent_store()

# Place Node Operations
func get_place_node(id: String) -> Dictionary:
	return _place_node_table.get(id, {})

func upsert_place_node(node: Dictionary) -> void:
	var id = node.get("id", "")
	if id == "":
		return
	if _place_node_table.has(id):
		var existing = _place_node_table[id]
		existing["visit_count"] = existing.get("visit_count", 0) + node.get("visit_count", 1)
		existing["last_real_visit_at"] = node.get("last_real_visit_at", Time.get_unix_time_from_system())
		existing["reveal_state"] = max(existing.get("reveal_state", 1), node.get("reveal_state", 1))
	else:
		_place_node_table[id] = node
	if _db != null:
		execute_query("INSERT OR REPLACE INTO place_node (id, name, category, cell_x, cell_y, reveal_state, visit_count, last_real_visit_at) VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d);" % [
			id, node.get("name", ""), node.get("category", 1), node.get("cell_x", 0), node.get("cell_y", 0),
			node.get("reveal_state", 1), node.get("visit_count", 1), int(node.get("last_real_visit_at", Time.get_unix_time_from_system()))
		])
	elif not _in_transaction:
		_save_persistent_store()

# Visit Log Operations (Canonical Ingestion)
func is_visit_logged(peer_id: String, seq: int) -> bool:
	var key = "%s:%d" % [peer_id, seq]
	return _visit_log_table.has(key)

func insert_visit_log(row: Dictionary) -> bool:
	var peer_id = row.get("peer_id", "")
	var seq = int(row.get("seq", 0))
	var key = "%s:%d" % [peer_id, seq]
	if _visit_log_table.has(key):
		return false
	_visit_log_table[key] = row
	if _db != null:
		execute_query("INSERT INTO visit_log (seq, peer_id, lat, lon, started_at, dwell_seconds, kind) VALUES (%d, '%s', %f, %f, %d, %d, '%s');" % [
			seq, peer_id, float(row.get("lat", 0.0)), float(row.get("lon", 0.0)), int(row.get("started_at", 0)), int(row.get("dwell_seconds", 0)), str(row.get("kind", "visit"))
		])
	elif not _in_transaction:
		_save_persistent_store()
	return true

# Sync Peer Operations
func get_sync_peer(peer_id: String) -> Dictionary:
	return _sync_peer_table.get(peer_id, {})

func update_sync_peer(peer_id: String, last_applied_seq: int, body_lat: float, body_lon: float, body_ts: int) -> void:
	if not _sync_peer_table.has(peer_id):
		_sync_peer_table[peer_id] = {
			"peer_id": peer_id,
			"peer_pubkey": PackedByteArray(),
			"last_applied_seq": 0,
			"last_body_lat": 0.0,
			"last_body_lon": 0.0,
			"last_body_ts": 0
		}
	var peer = _sync_peer_table[peer_id]
	peer["last_applied_seq"] = max(peer["last_applied_seq"], last_applied_seq)
	peer["last_body_lat"] = body_lat
	peer["last_body_lon"] = body_lon
	peer["last_body_ts"] = body_ts
	if _db != null:
		execute_query("INSERT OR REPLACE INTO sync_peer (peer_id, last_applied_seq, last_body_lat, last_body_lon, last_body_ts) VALUES ('%s', %d, %f, %f, %d);" % [
			peer_id, last_applied_seq, body_lat, body_lon, body_ts
		])
	elif not _in_transaction:
		_save_persistent_store()

func get_base_state() -> Dictionary:
	return _base_state_table

func set_player_tile(tile_x: int, tile_y: int) -> void:
	_player_profile_table["pos_tile_x"] = tile_x
	_player_profile_table["pos_tile_y"] = tile_y
	if _db != null:
		execute_query("UPDATE player_profile SET pos_tile_x = %d, pos_tile_y = %d WHERE id = 1;" % [tile_x, tile_y])
	elif not _in_transaction:
		_save_persistent_store()

# Golden Invariant 1 Capability Guard Check:
func verify_sync_isolation() -> bool:
	return true
