extends RefCounted

# map_fetcher.gd — Offline Regional Map Index, Selection, Download & Verification (Item 10)
# Contract: docs/implementation_plan_world_generation.md §5.1, §5.4 & docs/agent_execution_guide.md §6.8
# IMPORTANT: This is the ONLY file in the repository permitted to use HTTPRequest or HTTPClient.

const Grid := preload("res://world/grid.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")

const INDEX_URL := "https://download.geofabrik.de/index-v1.json"
const DEFAULT_MAP_DATA_DIR := "user://map_data"

const UNMAPPED_FALLBACK_TEXT := "Unmapped — no map data installed for this area"
const CONFIRM_BUTTON_TEXT := "Download"
const CANCEL_BUTTON_TEXT := "Not now"
const UPDATE_BUTTON_TEXT := "Update map data"

var map_data_dir: String = DEFAULT_MAP_DATA_DIR
var fake_transport: Variant = null
var _cached_index: Dictionary = {}

func _init(target_dir: String = DEFAULT_MAP_DATA_DIR, transport: Variant = null) -> void:
	map_data_dir = target_dir.trim_suffix("/")
	fake_transport = transport

static func format_size_mb(size_bytes: int) -> int:
	if size_bytes <= 0:
		return 0
	var mb := int(round(float(size_bytes) / (1024.0 * 1024.0)))
	return maxi(1, mb)

static func format_unmapped_chip_text(region_name: String, size_mb: int) -> String:
	if region_name == "" or size_mb <= 0:
		return UNMAPPED_FALLBACK_TEXT
	return "Unmapped Region — %s (%d MB)" % [region_name, size_mb]

static func format_download_dialog_text(region_name: String, size_mb: int) -> String:
	return "Download offline map for %s (%d MB)?" % [region_name, size_mb]

static func sanitize_region_id(region_id: String) -> String:
	var s := region_id.strip_edges().replace("/", "_").replace("\\", "_").replace(":", "_")
	return s if s != "" else "region"

func get_index_cache_path() -> String:
	return map_data_dir + "/index-v1.json"

func ensure_index_cached(force_refresh: bool = false) -> Dictionary:
	if not force_refresh and not _cached_index.is_empty():
		return _cached_index

	var cache_path := get_index_cache_path()
	if not force_refresh and FileAccess.file_exists(cache_path):
		var raw_text := FileAccess.get_file_as_string(cache_path)
		var parsed: Variant = JSON.parse_string(raw_text)
		if parsed is Dictionary:
			_cached_index = parsed
			return _cached_index

	var body: PackedByteArray = _http_get_bytes(INDEX_URL)
	if body.is_empty():
		return {}

	var text := body.get_string_from_utf8()
	var parsed_net: Variant = JSON.parse_string(text)
	if not (parsed_net is Dictionary):
		return {}

	if not DirAccess.dir_exists_absolute(map_data_dir):
		DirAccess.make_dir_recursive_absolute(map_data_dir)
	var fa := FileAccess.open(cache_path, FileAccess.WRITE)
	if fa != null:
		fa.store_buffer(body)
		fa.close()

	_cached_index = parsed_net
	return _cached_index

func select_region_for_cells(cells: Array) -> Dictionary:
	if cells.is_empty():
		return {}
	# Compute centroid lat/lon of the unmapped revealed cells via Grid
	var sum_lat := 0.0
	var sum_lon := 0.0
	var count := 0
	for c in cells:
		if c is Vector2i:
			var ll: Vector2 = Grid.cell_center_latlon(c)
			sum_lat += ll.x
			sum_lon += ll.y
			count += 1
	if count == 0:
		return {}
	return select_region_for_latlon(sum_lat / float(count), sum_lon / float(count))

func select_region_for_latlon(lat: float, lon: float) -> Dictionary:
	var idx: Dictionary = ensure_index_cached(false)
	if idx.is_empty():
		return {}
	var features: Variant = idx.get("features", [])
	if not (features is Array):
		return {}

	var best_region: Dictionary = {}
	var best_area: float = INF

	for feat in features:
		if not (feat is Dictionary):
			continue
		var props: Variant = feat.get("properties", {})
		var geom: Variant = feat.get("geometry", {})
		if not (props is Dictionary) or not (geom is Dictionary):
			continue
		var urls: Variant = props.get("urls", {})
		if not (urls is Dictionary):
			continue
		var pbf_url: String = str(urls.get("pbf", ""))
		if pbf_url == "":
			continue

		if _geometry_contains_lonlat(geom, lon, lat):
			var area: float = _geometry_area(geom)
			if area < best_area:
				best_area = area
				var md5_url: String = str(urls.get("md5", pbf_url + ".md5"))
				best_region = {
					"id": str(props.get("id", "")),
					"name": str(props.get("name", "")),
					"parent": str(props.get("parent", "")),
					"pbf_url": pbf_url,
					"md5_url": md5_url,
					"area": area
				}

	return best_region

func fetch_region_size_mb(region: Dictionary) -> int:
	if region.is_empty():
		return 0
	if region.has("size_bytes"):
		return format_size_mb(int(region.get("size_bytes", 0)))
	var pbf_url: String = str(region.get("pbf_url", ""))
	if pbf_url == "":
		return 0
	var size_bytes: int = _http_head_content_length(pbf_url)
	return format_size_mb(size_bytes)

func download_and_install_region(region: Dictionary) -> Dictionary:
	var region_id: String = str(region.get("id", ""))
	var pbf_url: String = str(region.get("pbf_url", ""))
	var md5_url: String = str(region.get("md5_url", pbf_url + ".md5"))
	if region_id == "" or pbf_url == "":
		return {"ok": false, "error": "Invalid region specification"}

	if not DirAccess.dir_exists_absolute(map_data_dir):
		DirAccess.make_dir_recursive_absolute(map_data_dir)

	var safe_id := sanitize_region_id(region_id)
	var part_path := map_data_dir + "/" + safe_id + ".osm.pbf.part"
	var md5_path := map_data_dir + "/" + safe_id + ".osm.pbf.md5"
	var pbf_path := map_data_dir + "/" + safe_id + ".osm.pbf"
	var tmp_db_path := map_data_dir + "/" + safe_id + ".tmp.db"
	var final_db_path := map_data_dir + "/" + safe_id + ".db"

	# Clean any stale partial files before starting
	_remove_if_exists(part_path)
	_remove_if_exists(md5_path)
	_remove_if_exists(pbf_path)

	# 1. Download PBF to .part
	var pbf_bytes: PackedByteArray = _http_get_bytes(pbf_url)
	if pbf_bytes.is_empty():
		_remove_if_exists(part_path)
		return {"ok": false, "error": "Failed to download PBF"}

	var fa_part := FileAccess.open(part_path, FileAccess.WRITE)
	if fa_part == null:
		return {"ok": false, "error": "Cannot open .part file for writing"}
	fa_part.store_buffer(pbf_bytes)
	fa_part.close()

	# 2. Download .md5 file
	var md5_bytes: PackedByteArray = _http_get_bytes(md5_url)
	if md5_bytes.is_empty():
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {"ok": false, "error": "Failed to download MD5"}

	var fa_md5 := FileAccess.open(md5_path, FileAccess.WRITE)
	if fa_md5 != null:
		fa_md5.store_buffer(md5_bytes)
		fa_md5.close()

	var expected_md5 := _parse_expected_md5(md5_bytes.get_string_from_utf8())
	var actual_md5 := _compute_file_md5(part_path)

	# 3. Verify MD5; clean up .part and .md5 on mismatch
	if expected_md5 == "" or actual_md5 != expected_md5:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {
			"ok": false,
			"error": "MD5 mismatch: expected %s, got %s" % [expected_md5, actual_md5]
		}

	# 4. Rename .part -> .osm.pbf
	var ren_err := DirAccess.rename_absolute(part_path, pbf_path)
	if ren_err != OK:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {"ok": false, "error": "Failed to rename .part to .osm.pbf"}

	# 5. Convert .osm.pbf -> .tmp.db
	_remove_db_family(tmp_db_path)
	var converter := RegionConverter.new()
	var conv_res: Dictionary = converter.convert(pbf_path, tmp_db_path)

	# 6. Delete downloaded .osm.pbf and .md5 regardless of conversion outcome
	_remove_if_exists(pbf_path)
	_remove_if_exists(md5_path)

	if not conv_res.get("ok", false):
		_remove_db_family(tmp_db_path)
		return {"ok": false, "error": str(conv_res.get("error", "Conversion failed"))}

	# 7. Atomically replace final .db with .tmp.db
	_remove_db_family(final_db_path)
	var db_ren_err := DirAccess.rename_absolute(tmp_db_path, final_db_path)
	if db_ren_err != OK:
		_remove_db_family(tmp_db_path)
		return {"ok": false, "error": "Failed to rename .tmp.db to .db"}

	return {
		"ok": true,
		"db_path": final_db_path,
		"region_id": region_id
	}

func update_region(region: Dictionary) -> Dictionary:
	return download_and_install_region(region)

static func _parse_expected_md5(md5_text: String) -> String:
	var stripped := md5_text.strip_edges()
	if stripped == "":
		return ""
	var tokens := stripped.split(" ", false)
	if tokens.is_empty():
		return ""
	var first := tokens[0].strip_edges().to_lower()
	if first.length() == 32:
		return first
	return ""

static func _compute_file_md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	while fa.get_position() < fa.get_length():
		var rem := fa.get_length() - fa.get_position()
		var chunk_len := mini(65536, int(rem))
		ctx.update(fa.get_buffer(chunk_len))
	fa.close()
	return ctx.finish().hex_encode().to_lower()

static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func _remove_db_family(db_path: String) -> void:
	for suffix in ["", "-wal", "-shm"]:
		if FileAccess.file_exists(db_path + suffix):
			DirAccess.remove_absolute(db_path + suffix)

# --- Geometry Helpers (GeoJSON Polygon / MultiPolygon in [lon, lat]) ---

static func _geometry_contains_lonlat(geom: Dictionary, lon: float, lat: float) -> bool:
	var gtype: String = str(geom.get("type", ""))
	var coords: Variant = geom.get("coordinates", [])
	if not (coords is Array):
		return false

	if gtype == "Polygon":
		return _polygon_contains_lonlat(coords, lon, lat)
	elif gtype == "MultiPolygon":
		for poly in coords:
			if poly is Array and _polygon_contains_lonlat(poly, lon, lat):
				return true
	return false

static func _polygon_contains_lonlat(rings: Array, lon: float, lat: float) -> bool:
	if rings.is_empty():
		return false
	var outer: Variant = rings[0]
	if not (outer is Array):
		return false
	if not _ring_contains_lonlat(outer, lon, lat):
		return false
	# Check holes if present
	for i in range(1, rings.size()):
		var hole: Variant = rings[i]
		if hole is Array and _ring_contains_lonlat(hole, lon, lat):
			return false
	return true

static func _ring_contains_lonlat(ring: Array, lon: float, lat: float) -> bool:
	var n := ring.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in range(n):
		var pi: Variant = ring[i]
		var pj: Variant = ring[j]
		if pi is Array and pj is Array and pi.size() >= 2 and pj.size() >= 2:
			var xi := float(pi[0])
			var yi := float(pi[1])
			var xj := float(pj[0])
			var yj := float(pj[1])
			var intersect := ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / ((yj - yi) if absf(yj - yi) > 1e-12 else 1e-12) + xi)
			if intersect:
				inside = not inside
		j = i
	return inside

static func _geometry_area(geom: Dictionary) -> float:
	var gtype: String = str(geom.get("type", ""))
	var coords: Variant = geom.get("coordinates", [])
	if not (coords is Array):
		return INF
	var total := 0.0
	if gtype == "Polygon":
		if not coords.is_empty() and coords[0] is Array:
			total += _ring_area(coords[0])
	elif gtype == "MultiPolygon":
		for poly in coords:
			if poly is Array and not poly.is_empty() and poly[0] is Array:
				total += _ring_area(poly[0])
	return total if total > 0.0 else INF

static func _ring_area(ring: Array) -> float:
	var n := ring.size()
	if n < 3:
		return 0.0
	var accum := 0.0
	var j := n - 1
	for i in range(n):
		var pi: Variant = ring[i]
		var pj: Variant = ring[j]
		if pi is Array and pj is Array and pi.size() >= 2 and pj.size() >= 2:
			accum += (float(pj[0]) + float(pi[0])) * (float(pj[1]) - float(pi[1]))
		j = i
	return absf(accum) * 0.5

# --- HTTP Transport (Injectable Fake + Real HTTPClient) ---

func _http_get_bytes(url: String) -> PackedByteArray:
	if fake_transport != null:
		if fake_transport is Object and fake_transport.has_method("get_bytes"):
			return fake_transport.get_bytes(url)
		elif fake_transport is Dictionary:
			var get_map: Variant = fake_transport.get("get_bytes", {})
			if get_map is Dictionary and get_map.has(url):
				var v: Variant = get_map[url]
				if v is PackedByteArray:
					return v
				elif v is String:
					return (v as String).to_utf8_buffer()
		return PackedByteArray()

	return _real_http_request(url, HTTPClient.METHOD_GET).get("body", PackedByteArray())

func _http_head_content_length(url: String) -> int:
	if fake_transport != null:
		if fake_transport is Object and fake_transport.has_method("head_size"):
			return int(fake_transport.head_size(url))
		elif fake_transport is Dictionary:
			var head_map: Variant = fake_transport.get("head_size", {})
			if head_map is Dictionary and head_map.has(url):
				return int(head_map[url])
		return 0

	var res: Dictionary = _real_http_request(url, HTTPClient.METHOD_HEAD)
	return int(res.get("content_length", 0))

func _real_http_request(url: String, method: int) -> Dictionary:
	var parsed := _parse_url(url)
	var host: String = str(parsed.get("host", ""))
	var path: String = str(parsed.get("path", "/"))
	var port: int = int(parsed.get("port", 443))
	var use_tls: bool = bool(parsed.get("tls", true))
	if host == "":
		return {"ok": false}

	var client := HTTPClient.new()
	var tls_opts: TLSOptions = TLSOptions.client() if use_tls else null
	var err := client.connect_to_host(host, port, tls_opts)
	if err != OK:
		return {"ok": false}

	var start_ms := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		OS.delay_msec(10)
		if Time.get_ticks_msec() - start_ms > 15000:
			client.close()
			return {"ok": false}

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return {"ok": false}

	var headers := PackedStringArray(["User-Agent: TenthSpring/1.0", "Accept: */*"])
	err = client.request(method, path, headers)
	if err != OK:
		client.close()
		return {"ok": false}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(10)
		if Time.get_ticks_msec() - start_ms > 30000:
			client.close()
			return {"ok": false}

	var code := client.get_response_code()
	var resp_headers := client.get_response_headers_as_dictionary()
	var content_len := 0
	for k in resp_headers.keys():
		if str(k).to_lower() == "content-length":
			content_len = int(str(resp_headers[k]).strip_edges())

	var body := PackedByteArray()
	if method == HTTPClient.METHOD_GET and client.has_response():
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				body.append_array(chunk)
			else:
				OS.delay_msec(5)

	client.close()
	return {
		"ok": code >= 200 and code < 400,
		"code": code,
		"content_length": content_len,
		"body": body
	}

static func _parse_url(url: String) -> Dictionary:
	var tls := true
	var rest := url
	if rest.begins_with("https://"):
		tls = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		tls = false
		rest = rest.substr(7)
	var slash_idx := rest.find("/")
	var host := rest if slash_idx == -1 else rest.substr(0, slash_idx)
	var path := "/" if slash_idx == -1 else rest.substr(slash_idx)
	var port := 443 if tls else 80
	var colon_idx := host.find(":")
	if colon_idx != -1:
		port = int(host.substr(colon_idx + 1))
		host = host.substr(0, colon_idx)
	return {"host": host, "port": port, "path": path, "tls": tls}
