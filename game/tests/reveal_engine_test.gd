extends Node

# reveal_engine_test.gd — Reveal Engine Verification Test (Item 19)
# Contract: docs/implementation_plan_famous_places.md §4, cases (a)–(g)

const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

const FIXTURE_PBF: String = "res://tests/fixtures/synthetic_neighborhood.osm.pbf"
const FIXTURE_CONFIG: String = "res://tests/fixtures/famous_places_fixture.json"

const TEST_DB_PATH: String = "user://test/tenth_spring_reveal_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_reveal_test.db.tmp"
const TEST_CITY_DB: String = "user://test/map_data/fixture_city_reveal.db"
const TEST_SITE_DB: String = "user://test/map_data/fixture_park_reveal.db"

func _cleanup_path(path: String) -> void:
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		var p: String = path + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _cleanup() -> void:
	_cleanup_path(TEST_DB_PATH)
	_cleanup_path(TEST_TMP_PATH)
	_cleanup_path(TEST_CITY_DB)
	_cleanup_path(TEST_SITE_DB)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup()

	# Convert fixture places for testing
	var conv := RegionConverter.new()
	var res_city := conv.convert(FIXTURE_PBF, TEST_CITY_DB, null, null, "city:fixture-city", FIXTURE_CONFIG)
	if not res_city.get("ok", false):
		push_error("FAIL: Failed to convert fixture city: %s" % res_city.get("error", "unknown"))
		_cleanup()
		return false

	var res_site := conv.convert(FIXTURE_PBF, TEST_SITE_DB, null, null, "site:fixture-park", FIXTURE_CONFIG)
	if not res_site.get("ok", false):
		push_error("FAIL: Failed to convert fixture site: %s" % res_site.get("error", "unknown"))
		_cleanup()
		return false

	var city_store := MapStore.new(TEST_CITY_DB)
	if not city_store.open_store(false):
		push_error("FAIL: Failed to open fixture city store")
		_cleanup()
		return false

	var site_store := MapStore.new(TEST_SITE_DB)
	if not site_store.open_store(false):
		push_error("FAIL: Failed to open fixture site store")
		city_store.close()
		_cleanup()
		return false

	var stores := {
		"city:fixture-city": city_store,
		"site:fixture-park": site_store
	}
	var places := RevealEngine.load_places(FIXTURE_CONFIG)

	DB.init_db()

	# Coordinates from synthetic_neighborhood.osm.pbf
	# Old Town: WM (1152, 1152) -> cell (4, 4)
	var ot_latlon := Grid.wm_to_latlon(Vector2(1152.0, 1152.0))
	# North End: WM (1152, 1920) -> cell (4, 7)
	var ne_latlon := Grid.wm_to_latlon(Vector2(1152.0, 1920.0))
	# Fixture Park: cell (10, 4) -> WM (2688, 1152)
	var park_latlon := Grid.wm_to_latlon(Vector2(2688.0, 1152.0))
	# Point outside both places: WM (5248, 5248) -> cell (20, 20)
	var out_latlon := Grid.wm_to_latlon(Vector2(5248.0, 5248.0))

	# -------------------------------------------------------------
	# (a) Falsifying: 1 corridor row through Old Town -> every Old Town cell known
	# Before RevealEngine, a corridor only revealed 60 m radius (1 cell).
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 1,
		"peer_id": "p1",
		"place_id": null,
		"lat": ot_latlon.x,
		"lon": ot_latlon.y,
		"started_at": 1000,
		"dwell_seconds": 0,
		"kind": "corridor"
	})
	# Simulate raw sync corridor reveal
	DB.upsert_map_cell(4, 4, 1)

	var ot_cells_before: Array = city_store.get_cells_for_area("osm:n9104")
	if ot_cells_before.size() != 12:
		push_error("FAIL: Expected 12 cells for Old Town, got %d" % ot_cells_before.size())
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var count_before := 0
	for c in ot_cells_before:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [c["cell_x"], c["cell_y"]])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			count_before += 1

	if count_before != 1:
		push_error("FAIL: Expected only 1 cell known before RevealEngine, got %d" % count_before)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Run RevealEngine
	var r_a := RevealEngine.apply(DB, stores, places)
	if not r_a.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (a): %s" % str(r_a))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var count_after := 0
	for c in ot_cells_before:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [c["cell_x"], c["cell_y"]])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			count_after += 1

	if count_after != 12:
		push_error("FAIL (a): Expected all 12 Old Town cells known, got %d" % count_after)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var ot_rev := DB.get_area_reveal("osm:n9104")
	if ot_rev.is_empty() or ot_rev["kind"] != "neighbourhood":
		push_error("FAIL (a): Old Town missing from area_reveal or kind mismatch: %s" % str(ot_rev))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var dl_city := DB.get_distort_entry("city:fixture-city")
	if dl_city.is_empty() or dl_city["reason"] != "visited":
		push_error("FAIL (a): city:fixture-city missing from distort_list: %s" % str(dl_city))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Fixture City not yet in area_reveal (T=2, unlocked=1)
	var city_rev := DB.get_area_reveal("city:fixture-city")
	if not city_rev.is_empty():
		push_error("FAIL (a): city:fixture-city should not be in area_reveal yet")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (b) Second row in North End -> n=4, T=2 -> Fixture City unlocked (36 cells known)
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 2,
		"peer_id": "p1",
		"place_id": null,
		"lat": ne_latlon.x,
		"lon": ne_latlon.y,
		"started_at": 2000,
		"dwell_seconds": 0,
		"kind": "corridor"
	})

	var r_b := RevealEngine.apply(DB, stores, places)
	if not r_b.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (b): %s" % str(r_b))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var city_rev_b := DB.get_area_reveal("city:fixture-city")
	if city_rev_b.is_empty() or city_rev_b["kind"] != "city" or int(city_rev_b["unlocked_at"]) != 2000:
		push_error("FAIL (b): Expected city:fixture-city in area_reveal with unlocked_at 2000, got %s" % str(city_rev_b))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var city_cells := city_store._rows("SELECT cell_x, cell_y FROM area_cells;")
	if city_cells.size() != 36:
		push_error("FAIL (b): Expected 36 inside cells for Fixture City, got %d" % city_cells.size())
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var city_known_count := 0
	for c in city_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [c["cell_x"], c["cell_y"]])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			city_known_count += 1

	if city_known_count != 36:
		push_error("FAIL (b): Expected all 36 city cells known, got %d" % city_known_count)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (c) One row anywhere in Fixture Park -> all 16 park cells known, park on distort_list
	# -------------------------------------------------------------
	DB.insert_visit_log({
		"seq": 3,
		"peer_id": "p1",
		"place_id": null,
		"lat": park_latlon.x,
		"lon": park_latlon.y,
		"started_at": 3000,
		"dwell_seconds": 60,
		"kind": "visit"
	})

	var r_c := RevealEngine.apply(DB, stores, places)
	if not r_c.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (c): %s" % str(r_c))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var dl_park := DB.get_distort_entry("site:fixture-park")
	if dl_park.is_empty() or dl_park["reason"] != "visited":
		push_error("FAIL (c): site:fixture-park missing from distort_list: %s" % str(dl_park))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var ar_park := DB.get_area_reveal("site:fixture-park")
	if ar_park.is_empty() or ar_park["kind"] != "site":
		push_error("FAIL (c): site:fixture-park missing from area_reveal: %s" % str(ar_park))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var park_cells := site_store._rows("SELECT cell_x, cell_y FROM area_cells WHERE area_key = 'site:fixture-park';")
	if park_cells.size() != 16:
		push_error("FAIL (c): Expected 16 cells for Fixture Park, got %d" % park_cells.size())
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var park_known_count := 0
	for c in park_cells:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [c["cell_x"], c["cell_y"]])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			park_known_count += 1

	if park_known_count != 16:
		push_error("FAIL (c): Expected all 16 park cells known, got %d" % park_known_count)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (d) Replaying visit_log changes nothing (idempotence)
	# -------------------------------------------------------------
	var ar_before := DB.get_all_area_reveals()
	var dl_before := DB.get_all_distort_entries()
	var total_cells_before := int(DB.query_rows("SELECT count(*) as c FROM map_cell WHERE reveal_state >= 1;")[0]["c"])

	var r_d := RevealEngine.apply(DB, stores, places)
	if not r_d.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (d): %s" % str(r_d))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var ar_after := DB.get_all_area_reveals()
	var dl_after := DB.get_all_distort_entries()
	var total_cells_after := int(DB.query_rows("SELECT count(*) as c FROM map_cell WHERE reveal_state >= 1;")[0]["c"])

	if ar_before.size() != ar_after.size() or dl_before.size() != dl_after.size() or total_cells_before != total_cells_after:
		push_error("FAIL (d): Idempotence violated on replay")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (e) Designating home west of the city -> Fixture City starter (reason 'starter'),
	# and its Waypost neighbourhood is revealed with no visits.
	# -------------------------------------------------------------
	DB.execute_query("DELETE FROM map_cell;")
	DB.execute_query("DELETE FROM area_reveal;")
	DB.execute_query("DELETE FROM distort_list;")
	DB.execute_query("DELETE FROM visit_log;")
	DB.execute_query("DELETE FROM meta WHERE key = 'home_cell';")

	# Designate home at cell (1, 5), west of Fixture City
	var r_e := RevealEngine.designate_home(DB, stores, places, Vector2i(1, 5))
	if not r_e.get("ok", false):
		push_error("FAIL: designate_home failed on (e): %s" % str(r_e))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	if r_e.get("starter_city", "") != "city:fixture-city":
		push_error("FAIL (e): Expected starter city city:fixture-city, got %s" % str(r_e.get("starter_city")))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var dl_starter := DB.get_distort_entry("city:fixture-city")
	if dl_starter.is_empty() or dl_starter["reason"] != "starter":
		push_error("FAIL (e): Expected distort_entry with reason 'starter', got %s" % str(dl_starter))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Waypost of Fixture City is in Old Town (osm:n9104)
	var ar_wp := DB.get_area_reveal("osm:n9104")
	if ar_wp.is_empty() or ar_wp["kind"] != "neighbourhood":
		push_error("FAIL (e): Expected Old Town in area_reveal, got %s" % str(ar_wp))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Old Town cells are revealed with 0 visits in visit_log
	var v_count := int(DB.query_rows("SELECT count(*) as c FROM visit_log;")[0]["c"])
	if v_count != 0:
		push_error("FAIL (e): Expected 0 visit_log rows, got %d" % v_count)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var ot_e_count := 0
	for c in ot_cells_before:
		var rows = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = ? AND cell_y = ?;", [c["cell_x"], c["cell_y"]])
		if not rows.is_empty() and int(rows[0]["reveal_state"]) >= 1:
			ot_e_count += 1

	if ot_e_count != 12:
		push_error("FAIL (e): Expected 12 Old Town cells revealed from starter Waypost, got %d" % ot_e_count)
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (f) A row outside both places -> no area_reveal or distort_list change
	# -------------------------------------------------------------
	var ar_f_pre := DB.get_all_area_reveals()
	var dl_f_pre := DB.get_all_distort_entries()

	DB.insert_visit_log({
		"seq": 10,
		"peer_id": "p1",
		"place_id": null,
		"lat": out_latlon.x,
		"lon": out_latlon.y,
		"started_at": 4000,
		"dwell_seconds": 60,
		"kind": "visit"
	})

	var r_f := RevealEngine.apply(DB, stores, places)
	if not r_f.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (f): %s" % str(r_f))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var ar_f_post := DB.get_all_area_reveals()
	var dl_f_post := DB.get_all_distort_entries()

	if ar_f_pre.size() != ar_f_post.size() or dl_f_pre.size() != dl_f_post.size():
		push_error("FAIL (f): Row outside places modified area_reveal or distort_list")
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# -------------------------------------------------------------
	# (g) cleared stays cleared
	# -------------------------------------------------------------
	DB.upsert_map_cell(4, 4, 2)
	var r_g := RevealEngine.apply(DB, stores, places)
	if not r_g.get("ok", false):
		push_error("FAIL: RevealEngine.apply failed on (g): %s" % str(r_g))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	var cell_4_4 = DB.query_rows("SELECT reveal_state FROM map_cell WHERE cell_x = 4 AND cell_y = 4;")
	if cell_4_4.is_empty() or int(cell_4_4[0]["reveal_state"]) != 2:
		push_error("FAIL (g): Cleared cell (4, 4) state lowered, expected 2, got %s" % str(cell_4_4))
		city_store.close()
		site_store.close()
		_cleanup()
		return false

	# Cleanup
	city_store.close()
	site_store.close()
	_cleanup()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

	print("PASS: reveal_engine_test")
	return true
