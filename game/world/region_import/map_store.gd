extends RefCounted

# map_store.gd — Regional Map Store SQLite Database Manager
# Contract: docs/implementation_plan_world_generation.md §5.2 & slice-2 plan §2

const GEOM_UNIT_WM: float = 16.0

var db_path: String = ""
var _db: Object = null
var _in_transaction: bool = false
var last_error: String = ""

func _init(path: String = ""):
	db_path = path

func open_store(read_only: bool = false) -> bool:
	if not ClassDB.can_instantiate("SQLite"):
		last_error = "SQLite extension missing"
		push_error(last_error)
		return false

	var base_dir := db_path.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

	_db = ClassDB.instantiate("SQLite")
	_db.path = db_path
	_db.foreign_keys = true
	_db.verbosity_level = 0

	if not _db.open_db():
		last_error = _db.error_message
		push_error("Failed to open map store %s: %s" % [db_path, last_error])
		_db = null
		return false

	if not read_only:
		_q("PRAGMA journal_mode = WAL;")
		_q("PRAGMA synchronous = NORMAL;")
		_init_schema()
	else:
		_q("PRAGMA query_only = ON;")
		_q("PRAGMA cache_size = -32768;") # 32 MiB read cache (plan §9.2)

	return true

func close() -> void:
	if _db != null:
		if _in_transaction:
			rollback()
		_db.close_db()
		_db = null

func _init_schema() -> void:
	_q("""
	CREATE TABLE IF NOT EXISTS features_poly (
		id INTEGER PRIMARY KEY,
		cell_x INTEGER NOT NULL,
		cell_y INTEGER NOT NULL,
		kind TEXT NOT NULL,
		subkind TEXT NOT NULL DEFAULT '',
		name TEXT NOT NULL DEFAULT '',
		geom_rings BLOB NOT NULL
	);
	""")
	_q("CREATE INDEX IF NOT EXISTS idx_poly_cell ON features_poly(cell_x, cell_y);")

	_q("""
	CREATE TABLE IF NOT EXISTS features_line (
		id INTEGER PRIMARY KEY,
		cell_x INTEGER NOT NULL,
		cell_y INTEGER NOT NULL,
		kind TEXT NOT NULL,
		subkind TEXT NOT NULL DEFAULT '',
		geom_pts BLOB NOT NULL
	);
	""")
	_q("CREATE INDEX IF NOT EXISTS idx_line_cell ON features_line(cell_x, cell_y);")

	_q("""
	CREATE TABLE IF NOT EXISTS place_nodes (
		osm_id INTEGER PRIMARY KEY,
		cell_x INTEGER NOT NULL,
		cell_y INTEGER NOT NULL,
		name TEXT,
		category TEXT NOT NULL,
		lat REAL NOT NULL,
		lon REAL NOT NULL
	);
	""")
	_q("CREATE INDEX IF NOT EXISTS idx_place_cell ON place_nodes(cell_x, cell_y);")

	_q("""
	CREATE TABLE IF NOT EXISTS cell_flags (
		cell_x INTEGER NOT NULL,
		cell_y INTEGER NOT NULL,
		sea INTEGER NOT NULL,
		PRIMARY KEY (cell_x, cell_y)
	);
	""")

	_q("""
	CREATE TABLE IF NOT EXISTS import_state (
		key TEXT PRIMARY KEY,
		val TEXT NOT NULL
	);
	""")
	_q("INSERT OR IGNORE INTO import_state (key, val) VALUES ('schema_version', '2');")

func _q(sql: String, params: Array = []) -> bool:
	if _db == null:
		last_error = "Database not open"
		return false
	var ok: bool = _db.query_with_bindings(sql, params)
	if not ok:
		last_error = _db.error_message
	return ok

func _rows(sql: String, params: Array = []) -> Array:
	if not _q(sql, params):
		return []
	var res = _db.query_result
	return res.duplicate(true) if typeof(res) == TYPE_ARRAY else []

func begin_transaction() -> bool:
	if _in_transaction:
		return false
	var ok = _q("BEGIN IMMEDIATE;")
	if ok:
		_in_transaction = true
	return ok

func commit() -> bool:
	if not _in_transaction:
		return false
	var ok = _q("COMMIT;")
	if ok:
		_in_transaction = false
	return ok

func rollback() -> bool:
	if not _in_transaction:
		return false
	var ok = _q("ROLLBACK;")
	_in_transaction = false
	return ok

# -------------------------------------------------------------
# Binary packing for 16m cell-local coordinates
# -------------------------------------------------------------

static func pack_pts(pts: PackedVector2Array) -> PackedByteArray:
	var spb := StreamPeerBuffer.new()
	spb.big_endian = false
	spb.put_u32(pts.size())
	for p in pts:
		spb.put_float(p.x)
		spb.put_float(p.y)
	return spb.data_array

static func unpack_pts(blob: PackedByteArray) -> PackedVector2Array:
	if blob.size() < 4:
		return PackedVector2Array()
	var spb := StreamPeerBuffer.new()
	spb.big_endian = false
	spb.data_array = blob
	var count := spb.get_u32()
	var res := PackedVector2Array()
	res.resize(count)
	for i in count:
		var x := spb.get_float()
		var y := spb.get_float()
		res[i] = Vector2(x, y)
	return res

static func pack_rings(rings: Array) -> PackedByteArray:
	var spb := StreamPeerBuffer.new()
	spb.big_endian = false
	spb.put_u32(rings.size())
	for ring in rings:
		var pts: PackedVector2Array = ring
		spb.put_u32(pts.size())
		for p in pts:
			spb.put_float(p.x)
			spb.put_float(p.y)
	return spb.data_array

static func unpack_rings(blob: PackedByteArray) -> Array[PackedVector2Array]:
	if blob.size() < 4:
		return []
	var spb := StreamPeerBuffer.new()
	spb.big_endian = false
	spb.data_array = blob
	var num_rings := spb.get_u32()
	var rings: Array[PackedVector2Array] = []
	for r in num_rings:
		var count := spb.get_u32()
		var ring := PackedVector2Array()
		ring.resize(count)
		for i in count:
			var x := spb.get_float()
			var y := spb.get_float()
			ring[i] = Vector2(x, y)
		rings.append(ring)
	return rings

# -------------------------------------------------------------
# Ingestion helpers
# -------------------------------------------------------------

func insert_poly(cell_x: int, cell_y: int, kind: String, geom_rings: PackedByteArray, subkind: String = "", name: String = "") -> bool:
	return _q(
		"INSERT INTO features_poly (cell_x, cell_y, kind, subkind, name, geom_rings) VALUES (?, ?, ?, ?, ?, ?);",
		[cell_x, cell_y, kind, subkind, name, geom_rings]
	)

func insert_line(cell_x: int, cell_y: int, kind: String, geom_pts: PackedByteArray, subkind: String = "") -> bool:
	return _q(
		"INSERT INTO features_line (cell_x, cell_y, kind, subkind, geom_pts) VALUES (?, ?, ?, ?, ?);",
		[cell_x, cell_y, kind, subkind, geom_pts]
	)

func insert_cell_flag(cell_x: int, cell_y: int, sea: int) -> bool:
	return _q(
		"INSERT OR REPLACE INTO cell_flags (cell_x, cell_y, sea) VALUES (?, ?, ?);",
		[cell_x, cell_y, sea]
	)

func get_cell_sea(cell_x: int, cell_y: int, default_val: int = 0) -> int:
	var rows := _rows("SELECT sea FROM cell_flags WHERE cell_x = ? AND cell_y = ? LIMIT 1;", [cell_x, cell_y])
	if rows.is_empty():
		return default_val
	return int(rows[0].get("sea", default_val))

func insert_place(osm_id: int, cell_x: int, cell_y: int, name: String, category: String, lat: float, lon: float) -> bool:
	return _q(
		"INSERT OR REPLACE INTO place_nodes (osm_id, cell_x, cell_y, name, category, lat, lon) VALUES (?, ?, ?, ?, ?, ?, ?);",
		[osm_id, cell_x, cell_y, name, category, lat, lon]
	)

func set_state(key: String, val: String) -> bool:
	return _q(
		"INSERT OR REPLACE INTO import_state (key, val) VALUES (?, ?);",
		[key, val]
	)

func get_state(key: String, default_val: String = "") -> String:
	var rows := _rows("SELECT val FROM import_state WHERE key = ?;", [key])
	if rows.is_empty():
		return default_val
	return str(rows[0].get("val", default_val))

# -------------------------------------------------------------
# Read queries
# -------------------------------------------------------------

func get_features_poly(cell_x: int, cell_y: int) -> Array:
	return _rows(
		"SELECT id, kind, subkind, name, geom_rings FROM features_poly WHERE cell_x = ? AND cell_y = ? ORDER BY id;",
		[cell_x, cell_y]
	)

func get_features_line(cell_x: int, cell_y: int) -> Array:
	return _rows(
		"SELECT id, kind, subkind, geom_pts FROM features_line WHERE cell_x = ? AND cell_y = ? ORDER BY id;",
		[cell_x, cell_y]
	)

func get_place_nodes(cell_x: int, cell_y: int) -> Array:
	return _rows(
		"SELECT osm_id, name, category, lat, lon FROM place_nodes WHERE cell_x = ? AND cell_y = ? ORDER BY osm_id;",
		[cell_x, cell_y]
	)

func get_coverage_box() -> Variant:
	var cov_str := get_state("coverage", "")
	if cov_str.is_empty():
		return null
	var parts := cov_str.split(",")
	if parts.size() < 4:
		return null
	var min_cx := int(parts[0].strip_edges())
	var min_cy := int(parts[1].strip_edges())
	var max_cx := int(parts[2].strip_edges())
	var max_cy := int(parts[3].strip_edges())
	return Rect2i(min_cx, min_cy, max_cx - min_cx + 1, max_cy - min_cy + 1)

func covers_cell(cx: int, cy: int) -> bool:
	var box = get_coverage_box()
	if box != null and box is Rect2i:
		var r: Rect2i = box
		return cx >= r.position.x and cx < r.position.x + r.size.x and cy >= r.position.y and cy < r.position.y + r.size.y
	# Pre-pass-17 fallback: covers only cells with features
	var p_rows := _rows("SELECT 1 FROM features_poly WHERE cell_x = ? AND cell_y = ? LIMIT 1;", [cx, cy])
	if not p_rows.is_empty():
		return true
	var l_rows := _rows("SELECT 1 FROM features_line WHERE cell_x = ? AND cell_y = ? LIMIT 1;", [cx, cy])
	if not l_rows.is_empty():
		return true
	var n_rows := _rows("SELECT 1 FROM place_nodes WHERE cell_x = ? AND cell_y = ? LIMIT 1;", [cx, cy])
	return not n_rows.is_empty()

# -------------------------------------------------------------
# Canonical Dump and Hash for Verification
# -------------------------------------------------------------

func canonical_dump() -> String:
	var lines: Array[String] = []

	var polys := _rows("SELECT cell_x, cell_y, kind, subkind, name, geom_rings FROM features_poly ORDER BY cell_x, cell_y, kind, subkind, name, id;")
	for p in polys:
		var b: PackedByteArray = p["geom_rings"]
		var sk: String = p.get("subkind", "")
		var nm: String = p.get("name", "")
		lines.append("POLY|%d|%d|%s|%s|%s|%s" % [p["cell_x"], p["cell_y"], p["kind"], sk, nm, b.hex_encode()])

	var lines_rows := _rows("SELECT cell_x, cell_y, kind, subkind, geom_pts FROM features_line ORDER BY cell_x, cell_y, kind, subkind, id;")
	for l in lines_rows:
		var b: PackedByteArray = l["geom_pts"]
		var sk: String = l.get("subkind", "")
		lines.append("LINE|%d|%d|%s|%s|%s" % [l["cell_x"], l["cell_y"], l["kind"], sk, b.hex_encode()])

	var places := _rows("SELECT osm_id, cell_x, cell_y, name, category, lat, lon FROM place_nodes ORDER BY cell_x, cell_y, osm_id;")
	for pl in places:
		var n: String = pl.get("name", "")
		lines.append("NODE|%d|%d|%d|%s|%s|%.7f|%.7f" % [
			pl["osm_id"], pl["cell_x"], pl["cell_y"], n, pl["category"], pl["lat"], pl["lon"]
		])

	var flags := _rows("SELECT cell_x, cell_y, sea FROM cell_flags ORDER BY cell_x, cell_y;")
	for f in flags:
		lines.append("FLAG|%d|%d|%d" % [f["cell_x"], f["cell_y"], f["sea"]])

	return "\n".join(lines) + "\n"

func canonical_dump_sha256() -> String:
	var dump_str := canonical_dump()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(dump_str.to_utf8_buffer())
	return ctx.finish().hex_encode()
