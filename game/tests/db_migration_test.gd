extends Node

# Migration Runner Test Suite (Items 19, 28 / explore plan §4.2 & §4.6)
# Verifies sequential migration execution (v1 -> v2 -> v3),
# v2 -> v3 coordinate scrubbing & unlock preservation on fixture places,
# idempotent re-run behavior, and atomic rollback on failed migration statements.

const Grid := preload("res://world/grid.gd")
const PlacesPack := preload("res://world/places_pack.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

const TEST_DB_PATH: String = "user://test/tenth_spring_test.db"
const TEST_TMP_PATH: String = "user://test/tenth_spring_test.db.tmp"

func _cleanup_test_files() -> void:
	DB.close()
	var to_clean = [
		TEST_DB_PATH,
		TEST_DB_PATH + "-wal",
		TEST_DB_PATH + "-shm",
		TEST_TMP_PATH,
		TEST_DB_PATH + ".jsonbak",
		TEST_DB_PATH + ".jsonbak.tmp",
		TEST_DB_PATH + ".jsonbak.1",
		TEST_DB_PATH + ".jsonbak.2"
	]
	for p in to_clean:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	PlacesPack.reset_active_pack_path()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed; active path was not isolated")
		return false

	_cleanup_test_files()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	PlacesPack.set_active_pack_path(PlacesPack.FIXTURE_PACK_PATH)
	DB.init_db()

	if DB.get_schema_version() != 5:
		push_error("FAIL: Expected initial schema_version 5 on fresh DB, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false

	# -------------------------------------------------------------
	# 1. Revert to schema version 2 and seed v2 fixture state:
	# - visit row inside Old Town (osm:n9104)
	# - corridor row inside Fixture Park (site:fixture-park)
	# - visit row outside both places
	# - meta('home_cell') = '1,5'
	# - sync_peer with body coordinates
	# - base_state with home_cell_x/y
	# - place_node with visit_count > 0 and last_real_visit_at
	# -------------------------------------------------------------
	DB.execute_query("UPDATE meta SET value = '2' WHERE key = 'schema_version';")
	DB.execute_query("DELETE FROM meta WHERE key = 'starter_place';")
	if DB.get_schema_version() != 2:
		push_error("FAIL: Expected schema_version 2 for v2 -> v3 migration test")
		_cleanup_test_files()
		return false

	var ot_ll := Grid.wm_to_latlon(Vector2(1152.0, 1152.0)) # Old Town cell (4, 4) -> osm:n9104
	var park_ll := Grid.wm_to_latlon(Vector2(2688.0, 1152.0)) # Fixture Park cell (10, 4) -> site:fixture-park
	var out_ll := Grid.wm_to_latlon(Vector2(5248.0, 5248.0)) # Outside cell (20, 20)

	DB.insert_visit_log({
		"seq": 1,
		"peer_id": "mig_peer",
		"place_id": null,
		"lat": ot_ll.x,
		"lon": ot_ll.y,
		"started_at": 1000,
		"dwell_seconds": 60,
		"kind": "visit"
	})
	DB.insert_visit_log({
		"seq": 2,
		"peer_id": "mig_peer",
		"place_id": null,
		"lat": park_ll.x,
		"lon": park_ll.y,
		"started_at": 2000,
		"dwell_seconds": 0,
		"kind": "corridor"
	})
	DB.insert_visit_log({
		"seq": 3,
		"peer_id": "mig_peer",
		"place_id": null,
		"lat": out_ll.x,
		"lon": out_ll.y,
		"started_at": 3000,
		"dwell_seconds": 120,
		"kind": "visit"
	})

	DB.set_db_meta("home_cell", "1,5")
	DB._q("INSERT INTO sync_peer (peer_id, last_applied_seq, last_body_lat, last_body_lon, last_body_ts) VALUES ('mig_peer', 3, ?, ?, 3000);", [ot_ll.x, ot_ll.y])
	DB._q("UPDATE base_state SET home_cell_x = 1, home_cell_y = 5 WHERE id = 1;")
	DB.upsert_place_node({
		"id": "poi_1",
		"name": "Old Bakery",
		"category": 1,
		"cell_x": 4,
		"cell_y": 4,
		"reveal_state": 1,
		"visit_count": 3,
		"last_real_visit_at": 1000
	})

	# Pre-migration v2 unlocks
	DB.insert_area_reveal("osm:n9104", "neighbourhood", 1000)
	DB.insert_area_reveal("site:fixture-park", "site", 2000)
	DB.insert_distort_entry("city:fixture-city", 900, "starter")
	DB.insert_distort_entry("site:fixture-park", 2000, "visited")

	var ar_before := DB.get_all_area_reveals()
	var dl_before := DB.get_all_distort_entries()

	# -------------------------------------------------------------
	# 2. Run migration v2 -> v3 -> v4 -> v5
	# -------------------------------------------------------------
	DB._run_migrations(DB.MIGRATIONS)

	if DB.get_schema_version() != 5:
		push_error("FAIL: Expected schema_version 5 after migration, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false

	# Verify starter_place is set and home_cell is gone
	if DB.get_db_meta("starter_place", "") != "city:fixture-city":
		push_error("FAIL: Expected starter_place = city:fixture-city after migration 3, got '%s'" % DB.get_db_meta("starter_place", ""))
		_cleanup_test_files()
		return false

	var hc_check := DB._rows("SELECT 1 FROM meta WHERE key = 'home_cell';")
	if not hc_check.is_empty():
		push_error("FAIL: home_cell meta row was not deleted by migration 3")
		_cleanup_test_files()
		return false

	# Verify base_state home_cell_x/y are NULL
	var bs := DB.get_base_state()
	if bs.get("home_cell_x") != null or bs.get("home_cell_y") != null:
		push_error("FAIL: base_state home_cell_x/y not NULL after migration 3: %s" % str(bs))
		_cleanup_test_files()
		return false

	# Verify place_node visit_count = 0 and last_real_visit_at = NULL
	var pn := DB.get_place_node("poi_1")
	if int(pn.get("visit_count", -1)) != 0 or pn.get("last_real_visit_at") != null:
		push_error("FAIL: place_node visit trace not cleared by migration 3: %s" % str(pn))
		_cleanup_test_files()
		return false

	# Verify zero non-NULL REAL values across all tables
	var tables := DB._rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
	for t in tables:
		var t_name := str(t.get("name", ""))
		var cols := DB._rows("PRAGMA table_info(" + t_name + ");")
		for col in cols:
			var col_type := str(col.get("type", "")).to_upper()
			if col_type.contains("REAL"):
				var col_name := str(col.get("name", ""))
				var cnt_rows := DB._rows("SELECT count(*) as c FROM " + t_name + " WHERE " + col_name + " IS NOT NULL;")
				var c_val := int(cnt_rows[0].get("c", 0)) if not cnt_rows.is_empty() else 0
				if c_val != 0:
					push_error("FAIL: Non-NULL REAL value remains in %s.%s (%d rows)" % [t_name, col_name, c_val])
					_cleanup_test_files()
					return false

	var peer_after := DB.get_sync_peer("mig_peer")
	if peer_after.get("last_body_ts") != null:
		push_error("FAIL: sync_peer.last_body_ts not NULL after migration 3: %s" % str(peer_after))
		_cleanup_test_files()
		return false

	# Verify visit_log rows were preserved (3 rows) and inside-place rows converted to 'explore'
	var v_rows := DB._rows("SELECT seq, place_id, lat, lon, kind FROM visit_log ORDER BY seq ASC;")
	if v_rows.size() != 3:
		push_error("FAIL: Expected 3 visit_log rows after migration 3, got %d" % v_rows.size())
		_cleanup_test_files()
		return false
	if str(v_rows[0]["kind"]) != "explore" or str(v_rows[0]["place_id"]) != "osm:n9104":
		push_error("FAIL: Row 1 was not migrated to explore osm:n9104: %s" % str(v_rows[0]))
		_cleanup_test_files()
		return false
	if str(v_rows[1]["kind"]) != "explore" or str(v_rows[1]["place_id"]) != "site:fixture-park":
		push_error("FAIL: Row 2 was not migrated to explore site:fixture-park: %s" % str(v_rows[1]))
		_cleanup_test_files()
		return false

	# Verify unlocks are identical before and after migration + RevealEngine.apply
	DB.execute_query("DELETE FROM area_reveal;")
	DB.execute_query("DELETE FROM distort_list;")
	var rev_res := RevealEngine.apply(DB)
	if not rev_res.get("ok", false):
		push_error("FAIL: RevealEngine.apply after migration 3 failed: %s" % str(rev_res))
		_cleanup_test_files()
		return false

	var ar_after := DB.get_all_area_reveals()
	var dl_after := DB.get_all_distort_entries()
	if ar_before.size() != ar_after.size() or dl_before.size() != dl_after.size():
		push_error("FAIL: Unlocks changed across migration 3! before=(%s, %s), after=(%s, %s)" % [str(ar_before), str(dl_before), str(ar_after), str(dl_after)])
		_cleanup_test_files()
		return false
	for i in range(ar_before.size()):
		if str(ar_before[i]["area_key"]) != str(ar_after[i]["area_key"]) or str(ar_before[i]["kind"]) != str(ar_after[i]["kind"]):
			push_error("FAIL: area_reveal mismatch at index %d: %s vs %s" % [i, str(ar_before[i]), str(ar_after[i])])
			_cleanup_test_files()
			return false
	for i in range(dl_before.size()):
		if str(dl_before[i]["place_id"]) != str(dl_after[i]["place_id"]) or str(dl_before[i]["reason"]) != str(dl_after[i]["reason"]):
			push_error("FAIL: distort_list mismatch at index %d: %s vs %s" % [i, str(dl_before[i]), str(dl_after[i])])
			_cleanup_test_files()
			return false

	# -------------------------------------------------------------
	# 2b. Explicit v4 -> v5 migration check (Item 50 / plan §7.1 & §9):
	# Drop neighbourhood_state, set schema_version = '4', seed map_cell + area_reveal + distort_list,
	# run migrations -> version 5, neighbourhood_state exists, every earlier row intact.
	# -------------------------------------------------------------
	DB.execute_query("DROP TABLE IF EXISTS neighbourhood_state;")
	DB.execute_query("UPDATE meta SET value = '4' WHERE key = 'schema_version';")
	DB.upsert_map_cell(4, 4, 2, 777)
	DB.upsert_map_cell_metadata(4, 4, "downtown", "city", "South Atlantic", 0)
	var v4_ar := DB.get_all_area_reveals()
	var v4_dl := DB.get_all_distort_entries()
	var v4_mc := DB.get_map_cell(4, 4)

	DB._run_migrations(DB.MIGRATIONS)
	if DB.get_schema_version() != 5:
		push_error("FAIL: Expected schema_version 5 after v4 -> v5 migration, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false
	var v5_tbl := DB._rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'neighbourhood_state';")
	if v5_tbl.is_empty():
		push_error("FAIL: neighbourhood_state table missing after v4 -> v5 migration")
		_cleanup_test_files()
		return false
	if DB.get_all_area_reveals() != v4_ar or DB.get_all_distort_entries() != v4_dl or DB.get_map_cell(4, 4) != v4_mc:
		push_error("FAIL: Earlier rows altered during v4 -> v5 migration")
		_cleanup_test_files()
		return false

	# Verify upsert_neighbourhood_state monotonic & timestamp invariants (§7.1)
	if not DB.upsert_neighbourhood_state("hood:fixture-city:north-end", "city:fixture-city", 1, "first_pick", 1000):
		push_error("FAIL: initial upsert_neighbourhood_state failed")
		_cleanup_test_files()
		return false
	var ns1 := DB.get_neighbourhood_state("hood:fixture-city:north-end")
	if int(ns1.get("state", 0)) != 1 or int(ns1.get("opened_at", 0)) != 1000 or str(ns1.get("opened_by", "")) != "first_pick" or ns1.get("entered_at") != null or ns1.get("finished_at") != null:
		push_error("FAIL: ns1 mismatch: %s" % str(ns1))
		_cleanup_test_files()
		return false
	# Entering sets entered_at once and preserves opened_at / opened_by
	DB.upsert_neighbourhood_state("hood:fixture-city:north-end", "city:fixture-city", 2, "pick", 2500)
	DB.upsert_neighbourhood_state("hood:fixture-city:north-end", "city:fixture-city", 2, "pick", 2900)
	var ns2 := DB.get_neighbourhood_state("hood:fixture-city:north-end")
	if int(ns2.get("state", 0)) != 2 or int(ns2.get("opened_at", 0)) != 1000 or str(ns2.get("opened_by", "")) != "first_pick" or int(ns2.get("entered_at", 0)) != 2500 or ns2.get("finished_at") != null:
		push_error("FAIL: ns2 mismatch: %s" % str(ns2))
		_cleanup_test_files()
		return false
	# Finishing sets finished_at once, and lowering state to 1 is a no-op on state
	DB.upsert_neighbourhood_state("hood:fixture-city:north-end", "city:fixture-city", 3, "finale", 4000)
	DB.upsert_neighbourhood_state("hood:fixture-city:north-end", "city:fixture-city", 1, "demo", 9999)
	var ns3 := DB.get_neighbourhood_state("hood:fixture-city:north-end")
	if int(ns3.get("state", 0)) != 3 or int(ns3.get("opened_at", 0)) != 1000 or str(ns3.get("opened_by", "")) != "first_pick" or int(ns3.get("entered_at", 0)) != 2500 or int(ns3.get("finished_at", 0)) != 4000:
		push_error("FAIL: ns3 monotonic/timestamp check failed: %s" % str(ns3))
		_cleanup_test_files()
		return false

	# 3. Re-running migration v5 is a no-op (idempotent)
	DB._run_migrations(DB.MIGRATIONS)
	if DB.get_schema_version() != 5 or DB.get_neighbourhood_states("city:fixture-city").size() != 1:
		push_error("FAIL: Expected schema_version to remain 5 with rows intact on idempotent re-run")
		_cleanup_test_files()
		return false

	# 4. Failing migration statement rolls back and leaves version at 5
	var mig_fail = [
		{
			"version": 6,
			"statements": [
				"ALTER TABLE map_cell ADD COLUMN valid_col INTEGER;",
				"SYNTAX ERROR INVALID SQL STATEMENT;"
			]
		}
	]
	DB._run_migrations(mig_fail)
	DB.init_db()

	if DB.get_schema_version() != 5:
		push_error("FAIL: Expected schema_version to remain 5 after failed migration, got %d" % DB.get_schema_version())
		_cleanup_test_files()
		return false

	_cleanup_test_files()
	print("PASS: db_migration_test")
	return true
