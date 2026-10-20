extends Node

# region_select_test.gd — Region Selection, Nested Polygon Rule, Dialog/Chip Text, MD5 Clean-up & HTTP Isolation Test (Item 10)
# Contract: docs/implementation_plan_world_generation.md §5.1, §5.4 & docs/agent_execution_guide.md §6.8

const MapFetcher := preload("res://world/region_import/map_fetcher.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const MapViewScene := preload("res://world/map_view.tscn")

class FakeTransport extends RefCounted:
	var get_responses: Dictionary = {}
	var head_responses: Dictionary = {}
	var get_call_counts: Dictionary = {}
	var head_call_counts: Dictionary = {}

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

	var pbf_url := "https://download.geofabrik.de/synthetic-state-latest.osm.pbf"
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
					"id": "synthetic-country",
					"parent": "synthetic-continent",
					"name": "Synthetic Country",
					"urls": {"pbf": "https://download.geofabrik.de/synthetic-country-latest.osm.pbf"}
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
					"parent": "synthetic-country",
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

	# 2. MapView UI integration: Chip text, Dialog text, and 'Not now' cancellation
	var map_view = MapViewScene.instantiate()
	add_child(map_view)
	map_view.set_map_fetcher(fetcher)

	var reg_info: Dictionary = map_view.configure_unmapped_region([Vector2i(4, 4)])
	if str(reg_info.get("name", "")) != "Synthetic State":
		push_error("MapView configure_unmapped_region returned wrong region")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var chip_label := map_view.get_node_or_null("AttributionUI/UnmappedChip/ChipLabel") as Label
	var expected_chip := "Unmapped Region — Synthetic State (348 MB)"
	if chip_label == null or chip_label.text != expected_chip:
		push_error("ChipLabel text mismatch: expected '%s', got '%s'" % [expected_chip, chip_label.text if chip_label else "null"])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var dialog := map_view.get_node_or_null("AttributionUI/DownloadDialog") as ConfirmationDialog
	var expected_dialog := "Download offline map for Synthetic State (348 MB)?"
	if dialog == null or dialog.dialog_text != expected_dialog:
		push_error("DownloadDialog text mismatch: expected '%s', got '%s'" % [expected_dialog, dialog.dialog_text if dialog else "null"])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	if dialog.ok_button_text != "Download" or dialog.cancel_button_text != "Not now":
		push_error("DownloadDialog button labels mismatch: got '%s' / '%s'" % [dialog.ok_button_text, dialog.cancel_button_text])
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 'Not now' downloads nothing
	map_view.open_download_dialog()
	map_view.cancel_download_dialog()
	if int(transport.get_call_counts.get(pbf_url, 0)) != 0:
		push_error("'Not now' should not download PBF")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 3. Falsifying test: MD5 mismatch cleans up .part and .md5 and installs nothing
	transport.get_responses[md5_url] = "00000000000000000000000000000000  synthetic-state-latest.osm.pbf\n"
	var bad_res: Dictionary = map_view.confirm_download_dialog()
	if bad_res.get("ok", false):
		push_error("Expected MD5 mismatch to fail download_and_install_region")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	for leftover in ["synthetic-state.osm.pbf.part", "synthetic-state.osm.pbf.md5", "synthetic-state.osm.pbf", "synthetic-state.db"]:
		if FileAccess.file_exists(test_dir + "/" + leftover):
			push_error("Leftover file '%s' was not cleaned up after MD5 mismatch" % leftover)
			map_view.queue_free()
			_cleanup_dir(test_dir)
			return false

	# 4. Valid MD5: .part -> MD5 verify -> rename -> convert -> delete temp files -> atomic .db
	transport.get_responses[md5_url] = real_md5 + "  synthetic-state-latest.osm.pbf\n"
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

	# Verify converted store contents
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

	# 5. Update map data button & flow
	var update_btn := map_view.get_node_or_null("AttributionUI/UpdateMapButton") as Button
	if update_btn == null or update_btn.text != "Update map data":
		push_error("UpdateMapButton missing or wrong label")
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	var upd_res: Dictionary = map_view.trigger_update_map_data()
	if not upd_res.get("ok", false):
		push_error("trigger_update_map_data failed: " + str(upd_res.get("error", "")))
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	# 6. Static grep check: no HTTP outside res://world/region_import/map_fetcher.gd
	if not _verify_no_http_outside_map_fetcher("res://"):
		map_view.queue_free()
		_cleanup_dir(test_dir)
		return false

	for s in map_view._map_stores:
		s.close()
	map_view._map_stores.clear()
	map_view.queue_free()
	_cleanup_dir(test_dir)
	print("PASS: region_select_test (nested polygon choice, index cache, HEAD size, dialog/chip text, MD5 mismatch clean-up, Update map data, HTTP isolation verified)")
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
	var files := DirAccess.get_files_at(dir_path)
	for f in files:
		var p: String = dir_path + "/" + f
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(dir_path)
