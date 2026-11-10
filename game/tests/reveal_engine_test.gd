extends Node

# reveal_engine_test.gd — Reveal Engine v2 Verification Test (Items 19, 28)
# Contract: docs/implementation_plan_explore_here.md §4.3 & §4.6, cases (a)–(g)

const PlacesPack := preload("res://world/places_pack.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

const TEST_DB_PATH: String = "user://test/tenth_spring_reveal_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_reveal_test.db.tmp"

func _cleanup_path(path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		var p: String = path + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _cleanup() -> void:
	DB.close()
	_cleanup_path(TEST_DB_PATH)
	_cleanup_path(TEST_TMP_PATH)
	PlacesPack.reset_active_pack_path()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	PlacesPack.set_active_pack_path(PlacesPack.FIXTURE_PACK_PATH)
	DB.init_db()

	var ot_cells: PackedVector2Array = PlacesPack.cells_of("osm:n9104")
	if ot_cells.size() != 12:
		push_error("FAIL: Expected 12 cells for Old Town in fixture pack, got %d" % ot_cells.size())
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (a) Falsifying: 1 explore row for Old Town (osm:n9104, lat=null, lon=null)
	# -> every Old Town cell is known (v1 needed coordinates).
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 1,
		"peer_id": "p1",
		"place_id": "osm:n9104",
		"lat": null,
		"lon": null,
		"started_at": 1000,
		"dwell_seconds": 0,
		"kind": "explore"
	})

	var r_a := RevealEngine.apply(DB)
	if not r_a.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (a): %s" % str(r_a))
		_cleanup()
		return false

	var count_after := 0
	for pt in ot_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [int(pt.x), int(pt.y)])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			count_after += 1

	if count_after != 12:
		push_error("FAIL (a): Expected all 12 Old Town cells known with NULL coordinates, got %d" % count_after)
		_cleanup()
		return false

	var ot_rev := DB.get_area_reveal("osm:n9104")
	if ot_rev.is_empty() or ot_rev["kind"] != "neighbourhood":
		push_error("FAIL (a): Old Town missing from area_reveal or kind mismatch: %s" % str(ot_rev))
		_cleanup()
		return false

	var dl_city := DB.get_distort_entry("city:fixture-city")
	if dl_city.is_empty() or dl_city["reason"] != "visited":
		push_error("FAIL (a): city:fixture-city missing from distort_list: %s" % str(dl_city))
		_cleanup()
		return false

	# Fixture City not yet in area_reveal (T=2, unlocked=1)
	var city_rev := DB.get_area_reveal("city:fixture-city")
	if not city_rev.is_empty():
		push_error("FAIL (a): city:fixture-city should not be in area_reveal yet")
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (b) Second area in North End (osm:n9103) -> T=2 reached -> Fixture City unlocked (36 cells known)
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 2,
		"peer_id": "p1",
		"place_id": "osm:n9103",
		"lat": null,
		"lon": null,
		"started_at": 2000,
		"dwell_seconds": 0,
		"kind": "explore"
	})

	var r_b := RevealEngine.apply(DB)
	if not r_b.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (b): %s" % str(r_b))
		_cleanup()
		return false

	var city_rev_b := DB.get_area_reveal("city:fixture-city")
	if city_rev_b.is_empty() or city_rev_b["kind"] != "city" or int(city_rev_b["unlocked_at"]) != 2000:
		push_error("FAIL (b): Expected city:fixture-city in area_reveal with unlocked_at 2000, got %s" % str(city_rev_b))
		_cleanup()
		return false

	var city_cells: PackedVector2Array = PlacesPack.cells_of("city:fixture-city")
	if city_cells.size() != 36:
		push_error("FAIL (b): Expected 36 inside cells for Fixture City, got %d" % city_cells.size())
		_cleanup()
		return false

	var city_known_count := 0
	for pt in city_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [int(pt.x), int(pt.y)])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			city_known_count += 1

	if city_known_count != 36:
		push_error("FAIL (b): Expected all 36 city cells known, got %d" % city_known_count)
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (c) A site row (site:fixture-park) -> all 16 park cells known, park on distort_list
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 3,
		"peer_id": "p1",
		"place_id": "site:fixture-park",
		"lat": null,
		"lon": null,
		"started_at": 3000,
		"dwell_seconds": 0,
		"kind": "explore"
	})

	var r_c := RevealEngine.apply(DB)
	if not r_c.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (c): %s" % str(r_c))
		_cleanup()
		return false

	var dl_park := DB.get_distort_entry("site:fixture-park")
	if dl_park.is_empty() or dl_park["reason"] != "visited":
		push_error("FAIL (c): site:fixture-park missing from distort_list: %s" % str(dl_park))
		_cleanup()
		return false

	var ar_park := DB.get_area_reveal("site:fixture-park")
	if ar_park.is_empty() or ar_park["kind"] != "site":
		push_error("FAIL (c): site:fixture-park missing from area_reveal: %s" % str(ar_park))
		_cleanup()
		return false

	var park_cells: PackedVector2Array = PlacesPack.cells_of("site:fixture-park")
	if park_cells.size() != 16:
		push_error("FAIL (c): Expected 16 cells for Fixture Park, got %d" % park_cells.size())
		_cleanup()
		return false

	var park_known_count := 0
	for pt in park_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [int(pt.x), int(pt.y)])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			park_known_count += 1

	if park_known_count != 16:
		push_error("FAIL (c): Expected all 16 park cells known, got %d" % park_known_count)
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (d) Replaying visit_log changes nothing (idempotence)
	# -------------------------------------------------------------
	var ar_before := DB.get_all_area_reveals()
	var dl_before := DB.get_all_distort_entries()
	var total_cells_before := int(DB.query_rows("SELECT count(*) as c FROM map_cell WHERE reveal_state >= 1;")[0]["c"])

	var r_d := RevealEngine.apply(DB)
	if not r_d.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (d): %s" % str(r_d))
		_cleanup()
		return false

	var ar_after := DB.get_all_area_reveals()
	var dl_after := DB.get_all_distort_entries()
	var total_cells_after := int(DB.query_rows("SELECT count(*) as c FROM map_cell WHERE reveal_state >= 1;")[0]["c"])

	if ar_before.size() != ar_after.size() or dl_before.size() != dl_after.size() or total_cells_before != total_cells_after:
		push_error("FAIL (d): Idempotence violated on replay")
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (e) A home row -> starter city on distort_list ('starter'),
	# meta('starter_place') set, and its Waypost neighbourhood revealed.
	# -------------------------------------------------------------
	DB.execute_query("DELETE FROM map_cell;")
	DB.execute_query("DELETE FROM area_reveal;")
	DB.execute_query("DELETE FROM distort_list;")
	DB.execute_query("DELETE FROM visit_log;")
	DB.execute_query("DELETE FROM meta WHERE key = 'starter_place';")

	DB.insert_visit_log({
		"seq": 1,
		"peer_id": "p1",
		"place_id": "city:fixture-city",
		"lat": null,
		"lon": null,
		"started_at": 3500,
		"dwell_seconds": 0,
		"kind": "home"
	})

	var r_e := RevealEngine.apply(DB)
	if not r_e.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (e): %s" % str(r_e))
		_cleanup()
		return false

	if DB.get_db_meta("starter_place", "") != "city:fixture-city":
		push_error("FAIL (e): Expected starter_place meta to be city:fixture-city, got %s" % DB.get_db_meta("starter_place", ""))
		_cleanup()
		return false

	var dl_starter := DB.get_distort_entry("city:fixture-city")
	if dl_starter.is_empty() or dl_starter["reason"] != "starter":
		push_error("FAIL (e): Expected distort_entry with reason 'starter', got %s" % str(dl_starter))
		_cleanup()
		return false

	# Waypost of Fixture City is in Old Town (osm:n9104)
	var ar_wp := DB.get_area_reveal("osm:n9104")
	if ar_wp.is_empty() or ar_wp["kind"] != "neighbourhood":
		push_error("FAIL (e): Expected Old Town in area_reveal from home row, got %s" % str(ar_wp))
		_cleanup()
		return false

	var ot_e_count := 0
	for pt in ot_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [int(pt.x), int(pt.y)])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			ot_e_count += 1

	if ot_e_count != 12:
		push_error("FAIL (e): Expected 12 Old Town cells revealed from starter Waypost, got %d" % ot_e_count)
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (f) An unknown area key is refused at ingest (ERROR bad_row)
	# -------------------------------------------------------------
	var ar_f_pre := DB.get_all_area_reveals()
	var dl_f_pre := DB.get_all_distort_entries()

	var bad_ingest := SyncServer.process_batch("p1", {
		"rows": [
			{
				"seq": 10,
				"kind": "explore",
				"placeId": "city:fixture-city",
				"areaKey": "osm:n9999999",
				"tsUtcMs": 4000
			}
		]
	})
	if bad_ingest.get("status", "") != "error" or bad_ingest.get("code", "") != "bad_row":
		push_error("FAIL (f): Expected bad_row on unknown areaKey at ingest, got %s" % str(bad_ingest))
		_cleanup()
		return false

	var ar_f_post := DB.get_all_area_reveals()
	var dl_f_post := DB.get_all_distort_entries()

	if ar_f_pre.size() != ar_f_post.size() or dl_f_pre.size() != dl_f_post.size():
		push_error("FAIL (f): Refused unknown areaKey modified area_reveal or distort_list")
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (g) cleared stays cleared
	# -------------------------------------------------------------
	DB.upsert_map_cell(4, 4, 2)
	var r_g := RevealEngine.apply(DB)
	if not r_g.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (g): %s" % str(r_g))
		_cleanup()
		return false

	var cell_4_4 = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = 4 AND cell_y = 4;")
	if cell_4_4.is_empty() or int(cell_4_4[0]["reveal_state"]) != 2:
		push_error("FAIL (g): Cleared cell (4, 4) state lowered, expected 2, got %s" % str(cell_4_4))
		_cleanup()
		return false

	_cleanup()
	print("PASS: reveal_engine_test")
	return true
