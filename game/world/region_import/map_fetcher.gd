extends RefCounted

# map_fetcher.gd — Offline Regional Map Index, Selection, Download & Verification (Item 1, F44, F45)
# Contract: docs/implementation_plan_world_generation.md §5.1a, §5.4a & docs/agent_execution_guide.md §4
# IMPORTANT: This is the ONLY file in the repository permitted to use HTTPRequest or HTTPClient.

const Grid := preload("res://world/grid.gd")
const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapConstants := preload("res://world/map_constants.gd")

const INDEX_URL := "https://download.geofabrik.de/index-v1.json"
const DEFAULT_MAP_DATA_DIR := "user://map_data"
const US_PREFIX := "https://download.geofabrik.de/north-america/us/"

const UNMAPPED_FALLBACK_TEXT := "Unmapped — no map data installed for this area"
const CONFIRM_BUTTON_TEXT := "Download"
const CANCEL_BUTTON_TEXT := "Not now"
const UPDATE_BUTTON_TEXT := "Update map data"
const BEYOND_MAP_TEXT := "Beyond the map — Tenth Spring covers the USA"

signal install_progress(stage: String, done: int, total: int)
signal install_finished(result: Dictionary)

var map_data_dir: String = DEFAULT_MAP_DATA_DIR
var fake_transport: Variant = null
var _cached_index: Dictionary = {}
var _cell_region_cache: Dictionary = {} # Vector2i -> region Dictionary or null

var cancel_requested: bool = false
var max_buffered_bytes: int = 0
var _install_thread: Thread = null
var _active_converter: RegionConverter = null
var _current_download_total: int = 0
var _current_download_done: int = 0
var _cached_tls_options: TLSOptions = null

func _get_client_tls_options() -> TLSOptions:
	if _cached_tls_options != null:
		return _cached_tls_options
	var ca := OS.get_system_ca_certificates()
	if not ca.is_empty():
		var cert := X509Certificate.new()
		if cert.load_from_string(ca) == OK:
			_cached_tls_options = TLSOptions.client(cert)
			return _cached_tls_options
	_cached_tls_options = TLSOptions.client()
	return _cached_tls_options

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

static func build_pbf_url(path_or_url: String) -> String:
	var s := path_or_url.strip_edges()
	if s.begins_with("http://") or s.begins_with("https://"):
		if s.ends_with("-latest.osm.pbf"):
			return s.trim_suffix("-latest.osm.pbf") + "-" + MapConstants.MAP_SNAPSHOT + ".osm.pbf"
		return s
	var prefix := "https://download.geofabrik.de/"
	var clean := s.trim_prefix("/").trim_suffix(".osm.pbf").trim_suffix("-latest")
	return prefix + clean + "-" + MapConstants.MAP_SNAPSHOT + ".osm.pbf"

static func build_md5_url(pbf_url: String) -> String:
	var s := pbf_url.strip_edges()
	if s.ends_with("-latest.osm.pbf.md5"):
		return s.trim_suffix("-latest.osm.pbf.md5") + "-" + MapConstants.MAP_SNAPSHOT + ".osm.pbf.md5"
	if s.ends_with(".md5"):
		return s
	return s + ".md5"

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

# --- Region Selection (§5.1a USA Scope) ---

func select_region_for_cells(cells: Array) -> Dictionary:
	if cells.is_empty():
		return {}

	var idx: Dictionary = ensure_index_cached(false)
	if idx.is_empty():
		return {}

	var kept_features: Array = _get_kept_us_features(idx)
	if kept_features.is_empty():
		return {"beyond_the_map": true}

	var counts: Dictionary = {} # region_id -> count
	var region_map: Dictionary = {} # region_id -> region_dict
	var beyond_count: int = 0
	var total_valid_cells: int = 0

	for c in cells:
		if not (c is Vector2i):
			continue
		total_valid_cells += 1
		var reg: Variant = null
		if _cell_region_cache.has(c):
			reg = _cell_region_cache[c]
		else:
			var center_ll: Vector2 = Grid.cell_center_latlon(c)
			reg = _find_best_region_in_features(center_ll.x, center_ll.y, kept_features)
			_cell_region_cache[c] = reg

		if reg == null or (reg is Dictionary and (reg as Dictionary).is_empty()):
			beyond_count += 1
		elif reg is Dictionary:
			var rid: String = str(reg.get("id", ""))
			counts[rid] = int(counts.get(rid, 0)) + 1
			region_map[rid] = reg

	if total_valid_cells > 0 and beyond_count == total_valid_cells:
		return {"beyond_the_map": true}

	if counts.is_empty():
		return {"beyond_the_map": true}

	var best_id := ""
	var best_count := -1
	var best_area := INF

	for rid in counts.keys():
		var cnt: int = int(counts[rid])
		var reg: Dictionary = region_map[rid]
		var area: float = float(reg.get("area", INF))

		if cnt > best_count:
			best_id = rid
			best_count = cnt
			best_area = area
		elif cnt == best_count:
			if area < best_area:
				best_id = rid
				best_count = cnt
				best_area = area
			elif is_equal_approx(area, best_area):
				if best_id == "" or rid < best_id:
					best_id = rid
					best_count = cnt
					best_area = area

	return region_map.get(best_id, {})

func select_region_for_latlon(lat: float, lon: float) -> Dictionary:
	var idx: Dictionary = ensure_index_cached(false)
	if idx.is_empty():
		return {}
	var kept_features: Array = _get_kept_us_features(idx)
	var res = _find_best_region_in_features(lat, lon, kept_features)
	if res != null and (res is Dictionary) and not (res as Dictionary).is_empty():
		return res
	return {"beyond_the_map": true}

func _get_kept_us_features(idx: Dictionary) -> Array:
	var out: Array = []
	var features: Variant = idx.get("features", [])
	if not (features is Array):
		return out
	for feat in features:
		if not (feat is Dictionary):
			continue
		var props: Variant = feat.get("properties", {})
		if not (props is Dictionary):
			continue
		var urls: Variant = props.get("urls", {})
		if not (urls is Dictionary):
			continue
		var pbf_url: String = str(urls.get("pbf", ""))
		if pbf_url.begins_with(US_PREFIX):
			out.append(feat)
	return out

func _find_best_region_in_features(lat: float, lon: float, kept_features: Array) -> Variant:
	var best_region: Variant = null
	var best_area := INF
	var best_id := ""

	for feat in kept_features:
		var geom: Variant = feat.get("geometry", {})
		var props: Variant = feat.get("properties", {})
		if not (geom is Dictionary) or not (props is Dictionary):
			continue

		if _geometry_contains_lonlat(geom, lon, lat):
			var area: float = _geometry_area(geom)
			var rid: String = str(props.get("id", ""))
			if area < best_area or (is_equal_approx(area, best_area) and (best_id == "" or rid < best_id)):
				best_area = area
				best_id = rid
				var urls: Dictionary = props.get("urls", {})
				var raw_pbf: String = str(urls.get("pbf", ""))
				var pbf_url: String = build_pbf_url(raw_pbf)
				var md5_url: String = build_md5_url(pbf_url)
				best_region = {
					"id": rid,
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

# --- Threaded Install (§5.4a rules 4–5) ---

func start_install(region: Dictionary) -> void:
	cancel_requested = false
	if _install_thread != null and _install_thread.is_alive():
		return
	if _install_thread != null:
		_install_thread.wait_to_finish()
	_install_thread = Thread.new()
	_install_thread.start(_thread_install_worker.bind(region))

func _thread_install_worker(region: Dictionary) -> void:
	var res := download_and_install_region(region)
	install_finished.emit(res)

func cancel_install() -> void:
	cancel_requested = true
	if _active_converter != null:
		_active_converter.cancel_requested = true

# --- Synchronous Install (Kept for tests & called by thread) ---

func download_and_install_region(region: Dictionary) -> Dictionary:
	var region_id: String = str(region.get("id", ""))
	var pbf_url: String = str(region.get("pbf_url", ""))
	var md5_url: String = str(region.get("md5_url", pbf_url + ".md5"))
	if region_id == "" or pbf_url == "":
		return {"ok": false, "error": "Invalid region specification"}

	if cancel_requested:
		return {"ok": false, "error": "Cancelled"}

	if not DirAccess.dir_exists_absolute(map_data_dir):
		DirAccess.make_dir_recursive_absolute(map_data_dir)

	var safe_id := sanitize_region_id(region_id)
	var part_path := map_data_dir + "/" + safe_id + ".osm.pbf.part"
	var md5_path := map_data_dir + "/" + safe_id + ".osm.pbf.md5"
	var pbf_path := map_data_dir + "/" + safe_id + ".osm.pbf"
	var tmp_db_path := map_data_dir + "/" + safe_id + ".tmp.db"
	var final_db_path := map_data_dir + "/" + safe_id + ".db"

	_remove_if_exists(part_path)
	_remove_if_exists(md5_path)
	_remove_if_exists(pbf_path)

	# 1. Download PBF to .part (streaming)
	var fa_part := FileAccess.open(part_path, FileAccess.WRITE)
	if fa_part == null:
		return {"ok": false, "error": "Cannot open .part file for writing"}

	var head_res := _fetch_http(pbf_url, HTTPClient.METHOD_HEAD, null)
	_current_download_total = int(head_res.get("content_length", 0))
	_current_download_done = 0
	max_buffered_bytes = 0

	install_progress.emit("download", 0, _current_download_total)
	var get_res := _fetch_http(pbf_url, HTTPClient.METHOD_GET, fa_part)
	fa_part.close()

	if not get_res.get("ok", false) or cancel_requested:
		_remove_if_exists(part_path)
		if cancel_requested or get_res.get("error") == "Cancelled":
			return {"ok": false, "error": "Cancelled"}
		return {"ok": false, "error": str(get_res.get("error", "Failed to download PBF"))}

	# 2. Download .md5 file
	install_progress.emit("verify", 0, 1)
	var md5_bytes := _http_get_bytes(md5_url)
	if md5_bytes.is_empty() or cancel_requested:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		if cancel_requested:
			return {"ok": false, "error": "Cancelled"}
		return {"ok": false, "error": "Failed to download MD5"}

	var fa_md5 := FileAccess.open(md5_path, FileAccess.WRITE)
	if fa_md5 != null:
		fa_md5.store_buffer(md5_bytes)
		fa_md5.close()

	if cancel_requested:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {"ok": false, "error": "Cancelled"}

	# 3. Verify MD5; clean up .part and .md5 on mismatch
	var expected_md5 := _parse_expected_md5(md5_bytes.get_string_from_utf8())
	var actual_md5 := _compute_file_md5(part_path)

	if expected_md5 == "" or actual_md5 != expected_md5:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {
			"ok": false,
			"error": "MD5 mismatch: expected %s, got %s" % [expected_md5, actual_md5]
		}
	install_progress.emit("verify", 1, 1)

	# 4. Rename .part -> .osm.pbf
	var ren_err := DirAccess.rename_absolute(part_path, pbf_path)
	if ren_err != OK:
		_remove_if_exists(part_path)
		_remove_if_exists(md5_path)
		return {"ok": false, "error": "Failed to rename .part to .osm.pbf"}

	# 5. Convert .osm.pbf -> .tmp.db
	_remove_db_family(tmp_db_path)
	_active_converter = RegionConverter.new()
	if cancel_requested:
		_active_converter.cancel_requested = true
	_active_converter.progress_updated.connect(func(stage: String, current: int, total: int):
		install_progress.emit(stage, current, total)
	)
	var conv_res: Dictionary = _active_converter.convert(pbf_path, tmp_db_path)
	_active_converter = null

	# 6. Delete downloaded .osm.pbf and .md5 regardless of conversion outcome
	_remove_if_exists(pbf_path)
	_remove_if_exists(md5_path)

	if not conv_res.get("ok", false) or cancel_requested:
		_remove_db_family(tmp_db_path)
		if cancel_requested or conv_res.get("error") == "Cancelled":
			return {"ok": false, "error": "Cancelled"}
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
			var denom := (yj - yi) if absf(yj - yi) > 1e-12 else 1e-12
			var intersect := ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / denom + xi)
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

# --- HTTP Transport (Redirects <= 5, Streaming, Fake Transport) ---

func _http_get_bytes(url: String) -> PackedByteArray:
	var res := _fetch_http(url, HTTPClient.METHOD_GET, null)
	if res.get("ok", false):
		return res.get("body", PackedByteArray())
	return PackedByteArray()

func _http_head_content_length(url: String) -> int:
	var res := _fetch_http(url, HTTPClient.METHOD_HEAD, null)
	if res.get("ok", false):
		return int(res.get("content_length", 0))
	return 0

func _fetch_http(url: String, method: int, out_file: FileAccess) -> Dictionary:
	var current_url := url
	var redirect_count := 0

	while redirect_count <= 5:
		if fake_transport != null:
			var res := _fake_http_step(current_url, method, out_file)
			if res.has("redirect_to"):
				current_url = res["redirect_to"]
				redirect_count += 1
				continue
			return res

		var parsed := _parse_url(current_url)
		var host: String = str(parsed.get("host", ""))
		var path: String = str(parsed.get("path", "/"))
		var port: int = int(parsed.get("port", 443))
		var use_tls: bool = bool(parsed.get("tls", true))

		if host != "download.geofabrik.de":
			return {"ok": false, "error": "Unexpected redirect to %s" % host}

		var client := HTTPClient.new()
		client.read_chunk_size = 1048576
		var tls_opts: TLSOptions = _get_client_tls_options() if use_tls else null
		var err := client.connect_to_host(host, port, tls_opts)
		if err != OK:
			return {"ok": false, "error": "Cannot connect to %s" % host}

		var start_ms := Time.get_ticks_msec()
		while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
			client.poll()
			OS.delay_msec(10)
			if Time.get_ticks_msec() - start_ms > 15000:
				client.close()
				return {"ok": false, "error": "Connection timeout"}

		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			client.close()
			return {"ok": false, "error": "Connection failed"}

		var headers := PackedStringArray(["User-Agent: TenthSpring/1.0", "Accept: */*"])
		err = client.request(method, path, headers)
		if err != OK:
			client.close()
			return {"ok": false, "error": "Request failed"}

		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			OS.delay_msec(10)
			if Time.get_ticks_msec() - start_ms > 30000:
				client.close()
				return {"ok": false, "error": "Request timeout"}

		var code := client.get_response_code()
		var resp_headers := client.get_response_headers_as_dictionary()
		var content_len := 0
		for k in resp_headers.keys():
			if str(k).to_lower() == "content-length":
				content_len = int(str(resp_headers[k]).strip_edges())

		if code in [301, 302, 303, 307, 308]:
			client.close()
			redirect_count += 1
			var location := ""
			for k in resp_headers.keys():
				if str(k).to_lower() == "location":
					location = str(resp_headers[k]).strip_edges()
					break
			if location == "":
				return {"ok": false, "error": "Redirect without Location"}
			if location.begins_with("/"):
				current_url = "https://download.geofabrik.de" + location
			elif location.begins_with("http://") or location.begins_with("https://"):
				var loc_parsed = _parse_url(location)
				var t_host: String = str(loc_parsed.get("host", ""))
				if t_host != "download.geofabrik.de":
					return {"ok": false, "error": "Unexpected redirect to %s" % t_host}
				current_url = location
			else:
				current_url = "https://download.geofabrik.de/" + location
			continue

		if code < 200 or code >= 300:
			client.close()
			return {"ok": false, "code": code, "error": "HTTP %d" % code}

		if method == HTTPClient.METHOD_HEAD:
			client.close()
			return {"ok": true, "code": code, "headers": resp_headers, "content_length": content_len}

		var body := PackedByteArray()
		if client.has_response() or client.get_status() == HTTPClient.STATUS_BODY:
			var poll_cnt := 0
			while client.get_status() == HTTPClient.STATUS_BODY:
				poll_cnt += 1
				client.poll()
				if cancel_requested:
					client.close()
					return {"ok": false, "error": "Cancelled"}
				var chunk := client.read_response_body_chunk()
				if chunk.size() > 0:
					if chunk.size() > max_buffered_bytes:
						max_buffered_bytes = chunk.size()
					if out_file != null:
						out_file.store_buffer(chunk)
						_current_download_done += chunk.size()
						install_progress.emit("download", _current_download_done, _current_download_total)
					else:
						body.append_array(chunk)
				else:
					OS.delay_msec(5)

		client.close()
		return {"ok": true, "code": code, "headers": resp_headers, "body": body if out_file == null else PackedByteArray()}

	return {"ok": false, "error": "Too many redirects"}

func _fake_http_step(url: String, method: int, out_file: FileAccess) -> Dictionary:
	var resp: Dictionary = {}
	if fake_transport is Object and fake_transport.has_method("request"):
		resp = fake_transport.request(url, method)
	elif fake_transport is Dictionary and fake_transport.has("responses") and fake_transport["responses"].has(url):
		var raw = fake_transport["responses"][url]
		if raw is Dictionary:
			resp = raw
	elif fake_transport is Object and "responses" in fake_transport and fake_transport.responses.has(url):
		var raw = fake_transport.responses[url]
		if raw is Dictionary:
			resp = raw

	# Fallbacks for legacy fake_transport shapes
	if resp.is_empty():
		if method == HTTPClient.METHOD_HEAD:
			if fake_transport is Object and fake_transport.has_method("head_size"):
				var sz := int(fake_transport.head_size(url))
				return {"ok": true, "code": 200, "content_length": sz, "headers": {"Content-Length": str(sz)}}
			elif fake_transport is Dictionary:
				var head_map: Variant = fake_transport.get("head_size", {})
				if head_map is Dictionary and head_map.has(url):
					var sz := int(head_map[url])
					return {"ok": true, "code": 200, "content_length": sz, "headers": {"Content-Length": str(sz)}}
			return {"ok": false, "code": 404, "error": "HTTP 404"}
		else:
			var b := PackedByteArray()
			if fake_transport is Object and fake_transport.has_method("get_bytes"):
				b = fake_transport.get_bytes(url)
			elif fake_transport is Dictionary:
				var get_map: Variant = fake_transport.get("get_bytes", {})
				if get_map is Dictionary and get_map.has(url):
					var v: Variant = get_map[url]
					b = v if v is PackedByteArray else str(v).to_utf8_buffer()
			if not b.is_empty():
				if out_file != null:
					if b.size() > max_buffered_bytes:
						max_buffered_bytes = b.size()
					out_file.store_buffer(b)
					_current_download_done += b.size()
					install_progress.emit("download", _current_download_done, _current_download_total)
					return {"ok": true, "code": 200, "headers": {}, "body": PackedByteArray()}
				return {"ok": true, "code": 200, "headers": {}, "body": b}
			return {"ok": false, "code": 404, "error": "HTTP 404"}

	var code: int = int(resp.get("code", 200))
	var headers: Dictionary = resp.get("headers", {})

	if code in [301, 302, 303, 307, 308]:
		var location := ""
		for k in headers.keys():
			if str(k).to_lower() == "location":
				location = str(headers[k]).strip_edges()
				break
		if location == "":
			return {"ok": false, "error": "Redirect without Location"}
		if location.begins_with("/"):
			return {"redirect_to": "https://download.geofabrik.de" + location}
		elif location.begins_with("http://") or location.begins_with("https://"):
			var loc_parsed := _parse_url(location)
			var t_host: String = str(loc_parsed.get("host", ""))
			if t_host != "download.geofabrik.de":
				return {"ok": false, "error": "Unexpected redirect to %s" % t_host}
			return {"redirect_to": location}
		else:
			return {"redirect_to": "https://download.geofabrik.de/" + location}

	if code < 200 or code >= 300:
		return {"ok": false, "code": code, "error": "HTTP %d" % code}

	var content_len := 0
	for k in headers.keys():
		if str(k).to_lower() == "content-length":
			content_len = int(str(headers[k]).strip_edges())

	if method == HTTPClient.METHOD_HEAD:
		return {"ok": true, "code": code, "headers": headers, "content_length": content_len}

	var chunks: Array = resp.get("chunks", [])
	if chunks.is_empty() and resp.has("body"):
		chunks = [resp["body"]]

	var body := PackedByteArray()
	for chunk in chunks:
		if cancel_requested:
			return {"ok": false, "error": "Cancelled"}
		if fake_transport is Object and "chunk_sleep_ms" in fake_transport and int(fake_transport.chunk_sleep_ms) > 0:
			OS.delay_msec(int(fake_transport.chunk_sleep_ms))
		var byte_chunk: PackedByteArray = chunk if chunk is PackedByteArray else str(chunk).to_utf8_buffer()
		if byte_chunk.size() > max_buffered_bytes:
			max_buffered_bytes = byte_chunk.size()
		if fake_transport is Object and "on_chunk" in fake_transport and (fake_transport.on_chunk is Callable) and fake_transport.on_chunk.is_valid():
			fake_transport.on_chunk.call(byte_chunk)
		if out_file != null:
			out_file.store_buffer(byte_chunk)
			_current_download_done += byte_chunk.size()
			install_progress.emit("download", _current_download_done, _current_download_total)
		else:
			body.append_array(byte_chunk)

	return {"ok": true, "code": code, "headers": headers, "body": body if out_file == null else PackedByteArray()}

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
