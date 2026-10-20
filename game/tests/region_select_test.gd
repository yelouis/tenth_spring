extends Node

# region_select_test.gd — Region Selection, USA Scope, Redirects, Streaming, Threading & Wiring Test (Item 1, F44, F45)
# Contract: docs/implementation_plan_world_generation.md §5.1a, §5.4a & docs/agent_execution_guide.md §4

const MapFetcher := preload("res://world/region_import/map_fetcher.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const MapViewScene := preload("res://world/map_view.tscn")
const Grid := preload("res://world/grid.gd")

class FakeTransport extends RefCounted:
	var responses: Dictionary = {} # url -> Dictionary {code, headers, chunks}
	var get_responses: Dictionary = {}
	var head_responses: Dictionary = {}
	var get_call_counts: Dictionary = {}
	var head_call_counts: Dictionary = {}
	var chunk_sleep_ms: int = 0
	var on_chunk: Callable = Callable()

	func request(url: String, method: int) -> Dictionary:
		if method == 1: # METHOD_HEAD
			head_call_counts[url] = int(head_call_counts.get(url, 0)) + 1
		else:
			get_call_counts[url] = int(get_call_counts.get(url, 0)) + 1

		if responses.has(url):
			return responses[url]
		return {}

	func get_bytes(url: String) -> PackedByteArray:
		get_call_counts[url] = int(get_call_counts.get(url, 0)) + 1
		if not get_responses.has(url):
			return PackedByteArray()
		var val: Variant = get_responses[url]
		if val is PackedByteArray:
			return val
		elif val is String:
			return (val as String).to_utf8_buffer()
		return PackedByteArray()

	func head_size(url: String) -> int:
		head_call_counts[url] = int(head_call_counts.get(url, 0)) + 1
		return int(head_responses.get(url, 0))

func run_test() -> bool:
	var test_dir := "user://test/region_select_map_data"
	_cleanup_dir(test_dir)

	var pbf_bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/synthetic_neighborhood.osm.pbf")
	if pbf_bytes.is_empty():
		push_error("Failed to read synthetic_neighborhood.osm.pbf fixture")
		return false

	var md5_ctx := HashingContext.new()
	md5_ctx.start(HashingContext.HASH_MD5)
	md5_ctx.update(pbf_bytes)
	var real_md5 := md5_ctx.finish().hex_encode().to_lower()

	var pbf_url := "https://download.geofabrik.de/north-america/us/synthetic-state-latest.osm.pbf"
	var md5_url := pbf_url + ".md5"

	# Build nested GeoJSON index around (0.01, 0.01) -> Cell (4, 4) center is ~(0.0103, 0.0103)
	var index_dict := {
		"type": "FeatureCollection",
		"features": [
			{
				"type": "Feature",
				"properties": {
					"id": "synthetic-continent",
					"name": "Synthetic Continent",
					"urls": {"pbf": "https://download.geofabrik.de/synthetic-continent-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [-1.0, -1.0]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "us-west",
					"name": "US West",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/us-west-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5], [-0.5, -0.5]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "synthetic-state",
					"parent": "us-west",
					"name": "Synthetic State",
					"urls": {"pbf": pbf_url}
				},
				"geometry": {
					"type": "MultiPolygon",
					"coordinates": [[[[0.0, 0.0], [0.05, 0.0], [0.05, 0.05], [0.0, 0.05], [0.0, 0.0]]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "disjoint-island",
					"name": "Disjoint Island",
					"urls": {"pbf": "https://download.geofabrik.de/disjoint-island-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[10.0, 10.0], [10.001, 10.0], [10.001, 10.001], [10.0, 10.001], [10.0, 10.0]]]
				}
			}
		]
	}

	var transport := FakeTransport.new()
	transport.get_responses[MapFetcher.INDEX_URL] = JSON.stringify(index_dict)
	transport.head_responses[pbf_url] = 364904448 # 348 MB
	transport.get_responses[pbf_url] = pbf_bytes

	var fetcher := MapFetcher.new(test_dir, transport)

	# 1. Nested region selection & index cache verification
	var selected: Dictionary = fetcher.select_region_for_cells([Vector2i(4, 4), Vector2i(5, 5)])
	if str(selected.get("id", "")) != "synthetic-state":
		push_error("Nested region selection failed: expected 'synthetic-state', got '%s'" % str(selected.get("id", "")))
		_cleanup_dir(test_dir)
		return false

	if not FileAccess.file_exists(fetcher.get_index_cache_path()):
		push_error("Index cache file was not written to " + fetcher.get_index_cache_path())
		_cleanup_dir(test_dir)
		return false

	# Second fetcher on same dir should read cached index-v1.json from disk without network call
	var fetcher2 := MapFetcher.new(test_dir, transport)
	var prev_idx_calls := int(transport.get_call_counts.get(MapFetcher.INDEX_URL, 0))
	var selected2: Dictionary = fetcher2.select_region_for_cells([Vector2i(4, 4)])
	if str(selected2.get("id", "")) != "synthetic-state":
		push_error("Cached index region selection failed")
		_cleanup_dir(test_dir)
		return false
	if int(transport.get_call_counts.get(MapFetcher.INDEX_URL, 0)) != prev_idx_calls:
		push_error("Expected cached index-v1.json to avoid extra HTTP GET")
		_cleanup_dir(test_dir)
		return false

	# 2. US Filter Validation:
	# Test point lies inside us-state, us-west grouping, and smaller canada-feat.
	# US filter picks us-state (ignoring smaller canada-feat and broader us-west).
	var us_filter_index := {
		"type": "FeatureCollection",
		"features": [
			{
				"type": "Feature",
				"properties": {
					"id": "us-west",
					"name": "US West",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/us-west-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [-1.0, -1.0]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "us-state",
					"name": "US State",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/us/test-state-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-0.02, -0.02], [0.1, -0.02], [0.1, 0.1], [-0.02, 0.1], [-0.02, -0.02]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "canada-feat",
					"name": "Canada Feature",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/canada/test-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[-0.05, -0.05], [0.05, -0.05], [0.05, 0.05], [-0.05, 0.05], [-0.05, -0.05]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "california",
					"name": "California",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/us/california-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[1.0, 1.0], [2.0, 1.0], [2.0, 2.0], [1.0, 2.0], [1.0, 1.0]]]
				}
			},
			{
				"type": "Feature",
				"properties": {
					"id": "norcal",
					"name": "Northern California",
					"urls": {"pbf": "https://download.geofabrik.de/north-america/us/california/norcal-latest.osm.pbf"}
				},
				"geometry": {
					"type": "Polygon",
					"coordinates": [[[1.2, 1.2], [1.8, 1.2], [1.8, 1.8], [1.2, 1.8], [1.2, 1.2]]]
				}
			}
		]
	}
	var filter_transport := FakeTransport.new()
	filter_transport.get_responses[MapFetcher.INDEX_URL] = JSON.stringify(us_filter_index)
	var filter_fetcher := MapFetcher.new(test_dir + "/filter", filter_transport)
	var filter_selected := filter_fetcher.select_region_for_cells([Vector2i(4, 4)])
	if str(filter_selected.get("id", "")) != "us-state":
		push_error("US filter test failed: expected 'us-state', got '%s'" % str(filter_selected.get("id", "")))
		_cleanup_dir(test_dir)
		return false

	var norcal_selected := filter_fetcher.select_region_for_latlon(1.5, 1.5)
	if str(norcal_selected.get("id", "")) != "norcal":
		push_error("Nested norcal selection failed: expected 'norcal', got '%s'" % str(norcal_selected.get("id", "")))
		_cleanup_dir(test_dir)
		return false

	# 3. Beyond the Map Validation:
	# A point only inside canadian feature returns {"beyond_the_map": true}
	var beyond_point := filter_fetcher.select_region_for_latlon(-0.04, -0.04) # Canada only
	if not beyond_point.get("beyond_the_map", false):
		push_error("Beyond the map point check failed: expected beyond_the_map=true, got %s" % str(beyond_point))
		_cleanup_dir(test_dir)
		return false

	# For cells:
	var beyond_cell := Grid.latlon_to_cell(-0.04, -0.04)
	var beyond_res := filter_fetcher.select_region_for_cells([beyond_cell])
	if not beyond_res.get("beyond_the_map", false):
		push_error("Beyond the map check failed: expected beyond_the_map=true, got %s" % str(beyond_res))
		_cleanup_dir(test_dir)
		return false

	var map_view = MapViewScene.instantiate()
	add_child(map_view)
	map_view.set_map_fetcher(filter_fetcher)
	map_view.configure_unmapped_region([beyond_cell])

	var chip_label := map_view.get_node_or_null("AttributionUI/UnmappedChip/ChipLabel") as Label
	var expected_beyond := "Beyond the map — Tenth Spring covers the USA"
	if chip_label == null or chip_label.text != expected_beyond:
		push_error("Beyond the map chip text mismatch: expected '%s', got '%s'" % [expected_beyond, chip_label.text if chip_label else "null"])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# Click on chip is ignored when beyond the map
	var click_ev := InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	map_view._on_unmapped_chip_gui_input(click_ev)
	var dialog := map_view.get_node_or_null("AttributionUI/DownloadDialog") as ConfirmationDialog
	if dialog != null and dialog.visible:
		push_error("DownloadDialog should not open on beyond the map click")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 4. Redirects & Error Handling Validation:
	# 4a. HEAD ...-latest -> 307 to ...-dated -> 200 with Content-Length 364412180 -> chip reads (348 MB)
	var redir_transport := FakeTransport.new()
	var redir_latest := "https://download.geofabrik.de/north-america/us/redir-latest.osm.pbf"
	var redir_dated := "https://download.geofabrik.de/north-america/us/redir-261018.osm.pbf"
	redir_transport.responses[redir_latest] = {
		"code": 307,
		"headers": {"Location": "/north-america/us/redir-261018.osm.pbf"}
	}
	redir_transport.responses[redir_dated] = {
		"code": 200,
		"headers": {"Content-Length": "364412180"}
	}
	var redir_fetcher := MapFetcher.new(test_dir + "/redir", redir_transport)
	var redir_size := redir_fetcher.fetch_region_size_mb({"pbf_url": redir_latest})
	if redir_size != 348:
		push_error("Redirect HEAD size mismatch: expected 348 MB, got %d MB" % redir_size)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	map_view.set_map_fetcher(redir_fetcher)
	map_view.configure_unmapped_region_data({"name": "Redirect State", "pbf_url": redir_latest})
	var expected_redir_chip := "Unmapped Region — Redirect State (348 MB)"
	if chip_label == null or chip_label.text != expected_redir_chip:
		push_error("Redirect chip text mismatch: expected '%s', got '%s'" % [expected_redir_chip, chip_label.text if chip_label else "null"])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 4b. Redirect to example.com -> error Unexpected redirect to example.com
	var foreign_redir_url := "https://download.geofabrik.de/north-america/us/foreign-latest.osm.pbf"
	redir_transport.responses[foreign_redir_url] = {
		"code": 302,
		"headers": {"Location": "https://example.com/other.osm.pbf"}
	}
	var foreign_res := redir_fetcher.download_and_install_region({"id": "foreign", "pbf_url": foreign_redir_url})
	if foreign_res.get("ok", false) or str(foreign_res.get("error", "")) != "Unexpected redirect to example.com":
		push_error("Foreign redirect error mismatch: got %s" % str(foreign_res))
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 4c. 404 -> error HTTP 404 and no .part file left
	var missing_url := "https://download.geofabrik.de/north-america/us/missing-latest.osm.pbf"
	redir_transport.responses[missing_url] = {
		"code": 404,
		"headers": {}
	}
	var not_found_res := redir_fetcher.download_and_install_region({"id": "missing", "pbf_url": missing_url})
	if not_found_res.get("ok", false) or str(not_found_res.get("error", "")) != "HTTP 404":
		push_error("404 error mismatch: expected 'HTTP 404', got '%s'" % str(not_found_res.get("error", "")))
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false
	if FileAccess.file_exists(test_dir + "/redir/missing.osm.pbf.part"):
		push_error(".part file was not cleaned up after 404")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 5. Streaming Validation:
	# Deliver 40 chunks of 1 MiB. max_buffered_bytes <= 1048576, and file grows to k MiB when chunk k+1 arrives.
	var stream_transport := FakeTransport.new()
	var stream_pbf_url := "https://download.geofabrik.de/north-america/us/stream-latest.osm.pbf"
	var one_mb := PackedByteArray()
	one_mb.resize(1048576)
	one_mb.fill(42)

	var stream_chunks: Array = []
	for i in 40:
		stream_chunks.append(one_mb)

	stream_transport.responses[stream_pbf_url] = {
		"code": 200,
		"headers": {"Content-Length": str(40 * 1048576)},
		"chunks": stream_chunks
	}
	var stream_part_path := test_dir + "/stream/stream.osm.pbf.part"
	var stream_state := {
		"chunks_seen": 0,
		"growth_verified": true
	}

	stream_transport.on_chunk = func(chunk: PackedByteArray):
		var seen: int = int(stream_state["chunks_seen"])
		if seen > 0:
			var expected_len := seen * 1048576
			if FileAccess.file_exists(stream_part_path):
				var fa := FileAccess.open(stream_part_path, FileAccess.READ)
				if fa != null:
					var cur_len := fa.get_length()
					fa.close()
					if cur_len != expected_len:
						stream_state["growth_verified"] = false
		stream_state["chunks_seen"] = seen + 1

	var stream_fetcher := MapFetcher.new(test_dir + "/stream", stream_transport)
	# md5 response is empty so it stops after download phase
	stream_transport.get_responses[stream_pbf_url + ".md5"] = ""
	var stream_res := stream_fetcher.download_and_install_region({"id": "stream", "pbf_url": stream_pbf_url})
	if stream_fetcher.max_buffered_bytes > 1048576:
		push_error("max_buffered_bytes exceeded 1 MiB: %d" % stream_fetcher.max_buffered_bytes)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false
	if not bool(stream_state["growth_verified"]) or int(stream_state["chunks_seen"]) != 40:
		push_error("Streaming file growth verification failed: seen=%d, verified=%s" % [int(stream_state["chunks_seen"]), str(stream_state["growth_verified"])])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 6. Threading & Cancellation Validation:
	# fake transport sleeps 200ms per chunk, start_install returns in < 50ms.
	# cancel after chunk 3 finishes with {"ok": false, "error": "Cancelled"} and leaves no .part or .tmp.db.
	var thread_transport := FakeTransport.new()
	thread_transport.chunk_sleep_ms = 200
	var thread_chunks: Array = []
	for i in 10:
		thread_chunks.append(one_mb)
	var thread_pbf_url := "https://download.geofabrik.de/north-america/us/thread-latest.osm.pbf"
	thread_transport.responses[thread_pbf_url] = {
		"code": 200,
		"headers": {"Content-Length": str(10 * 1048576)},
		"chunks": thread_chunks
	}
	var thread_fetcher := MapFetcher.new(test_dir + "/thread", thread_transport)
	var thread_stages: Array[String] = []
	var thread_state := {
		"finished": false,
		"result": {}
	}

	thread_fetcher.install_progress.connect(func(stage: String, done: int, total: int):
		thread_stages.append(stage)
		if stage == "download":
			var chunk_idx := done / 1048576
			if chunk_idx == 3:
				thread_fetcher.cancel_install()
	)
	thread_fetcher.install_finished.connect(func(res: Dictionary):
		thread_state["result"] = res
		thread_state["finished"] = true
	)

	var t0_install := Time.get_ticks_msec()
	thread_fetcher.start_install({"id": "thread", "pbf_url": thread_pbf_url})
	var t_elapsed := Time.get_ticks_msec() - t0_install
	if t_elapsed >= 50:
		push_error("start_install took >= 50ms (%d ms); did not return asynchronously" % t_elapsed)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var wait_start := Time.get_ticks_msec()
	while not bool(thread_state["finished"]) and Time.get_ticks_msec() - wait_start < 4000:
		OS.delay_msec(20)

	if not bool(thread_state["finished"]):
		push_error("Timed out waiting for install_finished after cancel")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var finished_result: Dictionary = thread_state["result"]

	if finished_result.get("ok", true) != false or str(finished_result.get("error", "")) != "Cancelled":
		push_error("Expected cancellation result {'ok': false, 'error': 'Cancelled'}, got %s" % str(finished_result))
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	for stray in ["thread.osm.pbf.part", "thread.osm.pbf.md5", "thread.osm.pbf", "thread.tmp.db"]:
		if FileAccess.file_exists(test_dir + "/thread/" + stray):
			push_error("Stray file '%s' left after cancellation" % stray)
			map_view.queue_free()
			_cleanup_dir(test_dir)
			return false

	# 7. Wiring Validation (F44):
	# A test save with one revealed cell, no store, and a fake fetcher -> within 3s of frames,
	# the chip reads Unmapped Region — <fake name> (<N> MB).
	var test_db_path := "user://test/wiring_test.db"
	var test_tmp_path := "user://test/wiring_test.db.tmp"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
	DB.configure_paths(test_db_path, test_tmp_path)
	DB.init_db()
	DB.upsert_map_cell(4, 4, 1, 0) # Revealed cell (4, 4)

	var wiring_transport := FakeTransport.new()
	wiring_transport.get_responses[MapFetcher.INDEX_URL] = JSON.stringify(index_dict)
	wiring_transport.head_responses[pbf_url] = 364904448
	var wiring_fetcher := MapFetcher.new(test_dir + "/wiring", wiring_transport)

	var wiring_view = MapViewScene.instantiate()
	add_child(wiring_view)
	wiring_view.set_map_fetcher(wiring_fetcher)
	wiring_view.focus_on_cell(4, 4)

	# Simulate 3 seconds of frames (60 frames * 0.05s)
	for f in 60:
		wiring_view._process(0.05)

	# Give worker thread brief moment to complete lookup
	var poll_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - poll_start < 1000:
		OS.delay_msec(10)
		wiring_view._process(0.01)
		var chip := wiring_view.get_node_or_null("AttributionUI/UnmappedChip/ChipLabel") as Label
		if chip != null and chip.text == "Unmapped Region — Synthetic State (348 MB)":
			break

	var w_label := wiring_view.get_node_or_null("AttributionUI/UnmappedChip/ChipLabel") as Label
	var expected_wiring_chip := "Unmapped Region — Synthetic State (348 MB)"
	if w_label == null or w_label.text != expected_wiring_chip:
		push_error("Wiring test (F44) failed: expected chip '%s', got '%s'" % [expected_wiring_chip, w_label.text if w_label else "null"])
		wiring_view.queue_free()
		map_view.queue_free()
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		_cleanup_dir(test_dir)
		return false

	wiring_view.queue_free()
	DB.close()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
	for sfx in ["", "-wal", "-shm", ".tmp"]:
		if FileAccess.file_exists(test_db_path + sfx):
			DirAccess.remove_absolute(test_db_path + sfx)

	# 8. Valid MD5 Install & Clean-up (preserving existing integration test flow)
	transport.get_responses[md5_url] = real_md5 + "  synthetic-state-latest.osm.pbf\n"
	map_view.set_map_fetcher(fetcher)
	map_view.configure_unmapped_region([Vector2i(4, 4)])
	var good_res: Dictionary = map_view.confirm_download_dialog()
	if not good_res.get("ok", false):
		push_error("Valid download_and_install_region failed: " + str(good_res.get("error", "")))
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var db_path := test_dir + "/synthetic-state.db"
	if not FileAccess.file_exists(db_path):
		push_error("Installed map store DB missing at " + db_path)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	for temp_file in ["synthetic-state.osm.pbf.part", "synthetic-state.osm.pbf.md5", "synthetic-state.osm.pbf", "synthetic-state.tmp.db"]:
		if FileAccess.file_exists(test_dir + "/" + temp_file):
			push_error("Temporary file '%s' should have been deleted after conversion" % temp_file)
			map_view.queue_free()
			_cleanup_dir(test_dir)
			return false

	var store := MapStore.new(db_path)
	if not store.open_store(true):
		push_error("Failed to open converted store at " + db_path)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false
	var polys := store.get_features_poly(4, 4)
	store.close()
	if polys.is_empty():
		push_error("Converted store at %s had no features in cell (4, 4)" % db_path)
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 9. Static grep check: no HTTP outside res://world/region_import/map_fetcher.gd
	if not _verify_no_http_outside_map_fetcher("res://"):
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	for s in map_view._map_stores:
		store.close()
	map_view._map_stores.clear()
	map_view.queue_free()
	_cleanup_dir(test_dir)
	print("PASS: region_select_test (US filter, Beyond the map, Redirects, Streaming, Threading & Wiring verified)")
	return true

func _verify_no_http_outside_map_fetcher(dir_path: String) -> bool:
	var tok_req := "HTTP" + "Request"
	var tok_cli := "HTTP" + "Client"
	var allowed := "res://world/region_import/map_fetcher.gd"

	var files := _list_gd_files(dir_path)
	for f in files:
		if f == allowed:
			continue
		var content := FileAccess.get_file_as_string(f)
		if content.contains(tok_req) or content.contains(tok_cli):
			push_error("Forbidden HTTP class usage found in %s (only %s may use HTTP)" % [f, allowed])
			return false
	return true

func _list_gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := dir_path.trim_suffix("/") + "/" + entry
			if da.current_is_dir():
				out.append_array(_list_gd_files(full))
			elif entry.ends_with(".gd"):
				out.append(full)
		entry = da.get_next()
	da.list_dir_end()
	return out

func _cleanup_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var da := DirAccess.open(dir_path)
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := dir_path.trim_suffix("/") + "/" + entry
				if da.current_is_dir():
					_cleanup_dir(full)
				elif FileAccess.file_exists(full):
					DirAccess.remove_absolute(full)
			entry = da.get_next()
		da.list_dir_end()
	DirAccess.remove_absolute(dir_path)
