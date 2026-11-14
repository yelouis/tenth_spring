extends Node

## game/tests/neighbourhood_progress_test.gd — Item 50 Neighbourhood Progress & Board Rules Suite
## Contract: docs/design_neighbourhoods_and_caricature.md §2.7;
##           docs/implementation_plan_dc_trial.md §7.2, §7.4, §7.5, §9

const Grid := preload("res://world/grid.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

const TEST_DB_PATH: String = "user://test/neighbourhood_progress_test.db"
const TEST_TMP_PATH: String = "user://test/neighbourhood_progress_test.db.tmp"
const TEST_ROUTES_ROSTER_PATH: String = "user://test/progress_routes_fixture.json"
const PLACE_DC: String = "city:washington-dc"
const PLACE_FIX: String = "city:fixture-routes"

func _cleanup() -> void:
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	Neighbourhoods.set_config_path_for_tests("")
	DB.close()
	for suffix in ["", "-wal", "-shm", ".tmp"]:
		var p: String = TEST_DB_PATH + str(suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if FileAccess.file_exists(TEST_TMP_PATH):
		DirAccess.remove_absolute(TEST_TMP_PATH)
	if FileAccess.file_exists(TEST_ROUTES_ROSTER_PATH):
		DirAccess.remove_absolute(TEST_ROUTES_ROSTER_PATH)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _write_routes_fixture_roster() -> bool:
	var dir_abs := ProjectSettings.globalize_path("user://test")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var hoods := [
		{"id": "hood:fixture-routes:gw-1", "name": "Gateway 1", "role": "gateway", "at": [4, 0], "borders": ["hood:fixture-routes:in-1", "hood:fixture-routes:fin"]},
		{"id": "hood:fixture-routes:gw-2", "name": "Gateway 2", "role": "gateway", "at": [10, 0], "borders": ["hood:fixture-routes:in-1", "hood:fixture-routes:in-2"]},
		{"id": "hood:fixture-routes:gw-3", "name": "Gateway 3", "role": "gateway", "at": [16, 0], "borders": ["hood:fixture-routes:in-3"]},
		{"id": "hood:fixture-routes:gw-4", "name": "Gateway 4", "role": "gateway", "at": [22, 0], "borders": []},
		{"id": "hood:fixture-routes:in-1", "name": "Inner 1", "role": "inner", "at": [4, 6], "borders": ["hood:fixture-routes:gw-1", "hood:fixture-routes:gw-2"]},
		{"id": "hood:fixture-routes:in-2", "name": "Inner 2", "role": "inner", "at": [10, 6], "borders": ["hood:fixture-routes:gw-2", "hood:fixture-routes:fin"]},
		{"id": "hood:fixture-routes:in-3", "name": "Inner 3", "role": "inner", "at": [16, 6], "borders": ["hood:fixture-routes:gw-3", "hood:fixture-routes:fin"]},
		{"id": "hood:fixture-routes:fin", "name": "Finale Keep", "role": "finale", "at": [4, 12], "borders": ["hood:fixture-routes:gw-1", "hood:fixture-routes:in-2", "hood:fixture-routes:in-3"]},
	]
	var hood_entries: Array = []
	for h in hoods:
		hood_entries.append({
			"id": h["id"],
			"name": h["name"],
			"anchor": {"lat": 0.01, "lon": 0.01},
			"at": h["at"],
			"cells": [4, 3],
			"role": h["role"],
			"borders": h["borders"],
			"zone": "parkland",
			"ruin": "near",
			"haunt_site": null,
			"map": "fixture-routes/" + str(h["id"]).get_slice(":", 2) + ".json",
			"landmarks": [
				{"id": "lm-a", "name": "Tower A", "kind": "stamp", "art": "pending"},
				{"id": "lm-b", "name": "Lawn B", "kind": "feature", "feature": "park", "sign": "Lawn B"}
			],
			"main_quest": {"id": "quest:fr:" + str(h["id"]).get_slice(":", 2), "title": "Q", "pattern": "keeper", "pays": "items", "summary": "S"}
		})
	var routes := [
		{"id": "route:fixture-routes:r-g1-in1", "name": "Route G1-In1", "ends": ["hood:fixture-routes:gw-1", "hood:fixture-routes:in-1"], "at": [0, 20]},
		{"id": "route:fixture-routes:r-g2-in1", "name": "Route G2-In1", "ends": ["hood:fixture-routes:gw-2", "hood:fixture-routes:in-1"], "at": [4, 20]},
		{"id": "route:fixture-routes:r-g2-in2", "name": "Route G2-In2", "ends": ["hood:fixture-routes:gw-2", "hood:fixture-routes:in-2"], "at": [8, 20]},
		{"id": "route:fixture-routes:r-g3-in3", "name": "Route G3-In3", "ends": ["hood:fixture-routes:gw-3", "hood:fixture-routes:in-3"], "at": [12, 20]},
		{"id": "route:fixture-routes:r-g1-fin", "name": "Route G1-Fin", "ends": ["hood:fixture-routes:gw-1", "hood:fixture-routes:fin"], "at": [0, 24]},
		{"id": "route:fixture-routes:r-in2-fin", "name": "Route In2-Fin", "ends": ["hood:fixture-routes:in-2", "hood:fixture-routes:fin"], "at": [4, 24]},
		{"id": "route:fixture-routes:r-in3-fin", "name": "Route In3-Fin", "ends": ["hood:fixture-routes:in-3", "hood:fixture-routes:fin"], "at": [8, 24]},
	]
	var route_entries: Array = []
	for r in routes:
		route_entries.append({
			"id": r["id"],
			"name": r["name"],
			"ends": r["ends"],
			"zone": "parkland",
			"ruin": "near",
			"calm": false,
			"legs": [{"at": r["at"], "cells": [2, 1], "map": "fixture-routes/routes/" + str(r["id"]).get_slice(":", 2) + ".json"}],
			"landmarks": [{"id": "rlm", "name": " Trail", "kind": "feature", "feature": "park", "sign": "Trail"}]
		})
	var doc := {
		"version": 1,
		"cities": [{
			"place_id": PLACE_FIX,
			"ready": true,
			"camp": {
				"id": "camp:fixture-routes",
				"name": "Fixture Waypost",
				"anchor": {"lat": 0.01, "lon": 0.01},
				"at": [0, 0],
				"cells": [2, 2],
				"ruin": "camp",
				"map": "fixture-routes/camp.json"
			},
			"neighbourhoods": hood_entries,
			"routes": route_entries
		}]
	}
	var fa := FileAccess.open(TEST_ROUTES_ROSTER_PATH, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_string(JSON.stringify(doc))
	fa.close()
	return true

func _reset_tables() -> void:
	DB.execute_query("DELETE FROM neighbourhood_state;")
	DB.execute_query("DELETE FROM map_cell;")

func _find_button_with_text(node: Node, substr: String) -> Button:
	if node is Button and (node as Button).text.contains(substr):
		return node as Button
	for c in node.get_children():
		var hit := _find_button_with_text(c, substr)
		if hit != null:
			return hit
	return null

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed")
		return false

	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()
	Neighbourhoods.set_config_path_for_tests("")
	NeighbourhoodProgress.set_demo_override_for_tests(-1)

	# -------------------------------------------------------------------------
	# 1. Card helpers: ZONE_CARD_TYPES, night_danger, trip_minutes (§7.4, §7.5)
	# -------------------------------------------------------------------------
	var mall_area := Neighbourhoods.area("hood:washington-dc:national-mall")
	var dupont_area := Neighbourhoods.area("hood:washington-dc:dupont-circle")
	var caphill_area := Neighbourhoods.area("hood:washington-dc:capitol-hill")
	var gtown_area := Neighbourhoods.area("hood:washington-dc:georgetown")
	var camp_area := Neighbourhoods.area("camp:washington-dc")

	if NeighbourhoodProgress.night_danger(mall_area) != "low" or NeighbourhoodProgress.night_danger(dupont_area) != "low":
		push_error("FAIL: Expected national-mall and dupont-circle night_danger == 'low'")
		_cleanup()
		return false
	if NeighbourhoodProgress.night_danger(caphill_area) != "medium":
		push_error("FAIL: Expected capitol-hill (institutional, g=0.36) night_danger == 'medium', got '%s'" % NeighbourhoodProgress.night_danger(caphill_area))
		_cleanup()
		return false
	if NeighbourhoodProgress.night_danger(gtown_area) != "high":
		push_error("FAIL: Expected georgetown (Oak Hill Cemetery haunt_site) night_danger == 'high', got '%s'" % NeighbourhoodProgress.night_danger(gtown_area))
		_cleanup()
		return false
	if NeighbourhoodProgress.night_danger({"zone": "ruins", "haunt_site": ""}) != "high":
		push_error("FAIL: Expected ruins zone night_danger == 'high'")
		_cleanup()
		return false

	var c_anch: Dictionary = camp_area["anchor"]
	var m_anch: Dictionary = mall_area["anchor"]
	var expected_miles := Grid.ground_distance_m(
		float(c_anch["lat"]), float(c_anch["lon"]), float(m_anch["lat"]), float(m_anch["lon"])
	) / 1609.344
	var expected_trip := maxi(1, int(ceili(expected_miles * (60.0 / Config.walk_speed_mph))))
	var got_trip := NeighbourhoodProgress.trip_minutes(PLACE_DC, "camp:washington-dc", "hood:washington-dc:national-mall")
	if got_trip != expected_trip:
		push_error("FAIL: trip_minutes mismatch: expected %d, got %d" % [expected_trip, got_trip])
		_cleanup()
		return false

	# -------------------------------------------------------------------------
	# 2. Falsifier: Inner neighbourhood with no opened border is refused (§9)
	# -------------------------------------------------------------------------
	_reset_tables()
	if not NeighbourhoodProgress.ensure_camp(DB, PLACE_DC):
		push_error("FAIL: ensure_camp failed")
		_cleanup()
		return false
	# Open tidal-basin and capitol-hill as the 2 first picks, then finish tidal-basin -> 1 pick
	if not bool(NeighbourhoodProgress.open(DB, "hood:washington-dc:tidal-basin").get("ok", false)):
		push_error("FAIL: open tidal-basin failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.open(DB, "hood:washington-dc:capitol-hill").get("ok", false)):
		push_error("FAIL: open capitol-hill failed")
		_cleanup()
		return false
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:tidal-basin"):
		push_error("FAIL: enter tidal-basin failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.finish(DB, "hood:washington-dc:tidal-basin").get("ok", false)):
		push_error("FAIL: finish tidal-basin failed")
		_cleanup()
		return false

	if NeighbourhoodProgress.picks_left(DB, PLACE_DC) != 1:
		push_error("FAIL: Expected picks_left == 1, got %d" % NeighbourhoodProgress.picks_left(DB, PLACE_DC))
		_cleanup()
		return false
	# Georgetown borders only dupont-circle, woodley-park, lincoln-memorial -> none opened!
	var no_border_openable := NeighbourhoodProgress.openable(DB, PLACE_DC)
	if "hood:washington-dc:georgetown" in no_border_openable or "hood:washington-dc:woodley-park" in no_border_openable:
		push_error("FAIL [falsifier]: Inner neighbourhood without opened border appeared in openable: %s" % str(no_border_openable))
		_cleanup()
		return false
	var refused_inner := NeighbourhoodProgress.open(DB, "hood:washington-dc:georgetown")
	if bool(refused_inner.get("ok", true)) or str(refused_inner.get("error", "")) != "not openable":
		push_error("FAIL [falsifier]: Opening inner neighbourhood with no opened border was not refused: %s" % str(refused_inner))
		_cleanup()
		return false

	# -------------------------------------------------------------------------
	# 3. Full §2.7 Washington DC Walkthrough, Step by Step, + Falsifiers (§9)
	# -------------------------------------------------------------------------
	_reset_tables()

	# Step 1: Day one — arrive at Washington DC camp
	if not NeighbourhoodProgress.ensure_camp(DB, PLACE_DC):
		push_error("FAIL (§2.7 step 1): ensure_camp failed")
		_cleanup()
		return false
	var camp_ns := DB.get_neighbourhood_state("camp:washington-dc")
	if camp_ns.is_empty() or str(camp_ns.get("opened_by", "")) != "camp":
		push_error("FAIL (§2.7 step 1): camp row missing or wrong opened_by: %s" % str(camp_ns))
		_cleanup()
		return false
	var camp_cells := Neighbourhoods.block_cells(camp_area)
	if int(DB.get_map_cell(camp_cells[0].x, camp_cells[0].y).get("reveal_state", 0)) != 2:
		push_error("FAIL (§2.7 step 1): camp cell not cleared")
		_cleanup()
		return false
	if NeighbourhoodProgress.first_picks_left(DB, PLACE_DC) != 2 or NeighbourhoodProgress.picks_left(DB, PLACE_DC) != 0:
		push_error("FAIL (§2.7 step 1): Expected first_picks_left=2, picks_left=0")
		_cleanup()
		return false

	# Step 2: Board offers the 4 gateways; pick National Mall and Dupont Circle; 3rd first pick refused
	var initial_openable := NeighbourhoodProgress.openable(DB, PLACE_DC)
	var expected_gateways: Array[String] = [
		"hood:washington-dc:national-mall",
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:dupont-circle",
		"hood:washington-dc:capitol-hill",
	]
	if initial_openable != expected_gateways:
		push_error("FAIL (§2.7 step 2): Expected 4 gateways %s, got %s" % [str(expected_gateways), str(initial_openable)])
		_cleanup()
		return false

	var r_pick1 := NeighbourhoodProgress.open(DB, "hood:washington-dc:national-mall")
	var r_pick2 := NeighbourhoodProgress.open(DB, "hood:washington-dc:dupont-circle")
	if not bool(r_pick1.get("ok", false)) or str(r_pick1.get("opened_by", "")) != "first_pick":
		push_error("FAIL (§2.7 step 2): First pick 1 failed: %s" % str(r_pick1))
		_cleanup()
		return false
	if not bool(r_pick2.get("ok", false)) or str(r_pick2.get("opened_by", "")) != "first_pick":
		push_error("FAIL (§2.7 step 2): First pick 2 failed: %s" % str(r_pick2))
		_cleanup()
		return false
	if NeighbourhoodProgress.first_picks_left(DB, PLACE_DC) != 0 or not NeighbourhoodProgress.openable(DB, PLACE_DC).is_empty():
		push_error("FAIL (§2.7 step 2): Expected 0 first picks left and empty openable after 2 picks")
		_cleanup()
		return false

	# Verify Mall cells revealed as known (1) with parkland zone metadata
	for mc in Neighbourhoods.block_cells(mall_area):
		var mc_row := DB.get_map_cell(mc.x, mc.y)
		if int(mc_row.get("reveal_state", 0)) != 1 or str(mc_row.get("zone", "")) != "parkland":
			push_error("FAIL (§2.7 step 2): Mall cell %s expected reveal_state=1 zone=parkland, got %s" % [str(mc), str(mc_row)])
			_cleanup()
			return false

	# Falsifier: A third first pick is refused
	var r_pick3 := NeighbourhoodProgress.open(DB, "hood:washington-dc:tidal-basin")
	if bool(r_pick3.get("ok", true)) or str(r_pick3.get("error", "")) != "not openable":
		push_error("FAIL [falsifier]: Third first pick was not refused: %s" % str(r_pick3))
		_cleanup()
		return false

	# Falsifier: finish before enter (state == 1 < 2) is refused
	var premature_fin := NeighbourhoodProgress.finish(DB, "hood:washington-dc:national-mall")
	if bool(premature_fin.get("ok", true)):
		push_error("FAIL: finish before enter (state=1) must be refused")
		_cleanup()
		return false

	# Step 3: Enter & finish National Mall -> 1 pick; offers Tidal Basin, Capitol Hill, Union Station, Georgetown, Woodley Park; open Georgetown
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:national-mall"):
		push_error("FAIL (§2.7 step 3): enter national-mall failed")
		_cleanup()
		return false
	for mc2 in Neighbourhoods.block_cells(mall_area):
		if int(DB.get_map_cell(mc2.x, mc2.y).get("reveal_state", 0)) != 2:
			push_error("FAIL (§2.7 step 3): Mall cell %s not raised to cleared (2) on enter" % str(mc2))
			_cleanup()
			return false

	var fin_mall := NeighbourhoodProgress.finish(DB, "hood:washington-dc:national-mall")
	if not bool(fin_mall.get("ok", false)) or bool(fin_mall.get("finale_opened", true)) or bool(fin_mall.get("city_complete", true)):
		push_error("FAIL (§2.7 step 3): finish national-mall unexpected result: %s" % str(fin_mall))
		_cleanup()
		return false
	if NeighbourhoodProgress.picks_left(DB, PLACE_DC) != 1:
		push_error("FAIL (§2.7 step 3): Expected picks_left == 1 after finishing Mall")
		_cleanup()
		return false

	var step3_openable := NeighbourhoodProgress.openable(DB, PLACE_DC)
	var expected_step3: Array[String] = [
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:capitol-hill",
		"hood:washington-dc:union-station",
		"hood:washington-dc:georgetown",
		"hood:washington-dc:woodley-park",
	]
	if step3_openable != expected_step3:
		push_error("FAIL (§2.7 step 3): Expected openable %s, got %s" % [str(expected_step3), str(step3_openable)])
		_cleanup()
		return false
	if "hood:washington-dc:lincoln-memorial" in step3_openable:
		push_error("FAIL [falsifier]: Finale appeared in openable!")
		_cleanup()
		return false

	var r_gtown := NeighbourhoodProgress.open(DB, "hood:washington-dc:georgetown")
	if not bool(r_gtown.get("ok", false)) or str(r_gtown.get("opened_by", "")) != "pick":
		push_error("FAIL (§2.7 step 3): Opening georgetown failed: %s" % str(r_gtown))
		_cleanup()
		return false
	if NeighbourhoodProgress.picks_left(DB, PLACE_DC) != 0:
		push_error("FAIL (§2.7 step 3): Expected picks_left == 0 after spending pick on Georgetown")
		_cleanup()
		return false

	# Step 4: Reach F = 4 finished non-finale neighbourhoods -> finale STILL locked & refused; at F = 5 -> finale opens by itself!
	# Finish dupont-circle (F=2 -> open woodley-park), georgetown (F=3 -> open tidal-basin), woodley-park (F=4)
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:dupont-circle") or not bool(NeighbourhoodProgress.finish(DB, "hood:washington-dc:dupont-circle").get("ok", false)):
		push_error("FAIL (§2.7 step 4): finish dupont-circle failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.open(DB, "hood:washington-dc:woodley-park").get("ok", false)):
		push_error("FAIL (§2.7 step 4): open woodley-park failed")
		_cleanup()
		return false
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:georgetown") or not bool(NeighbourhoodProgress.finish(DB, "hood:washington-dc:georgetown").get("ok", false)):
		push_error("FAIL (§2.7 step 4): finish georgetown failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.open(DB, "hood:washington-dc:tidal-basin").get("ok", false)):
		push_error("FAIL (§2.7 step 4): open tidal-basin failed")
		_cleanup()
		return false
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:woodley-park"):
		push_error("FAIL (§2.7 step 4): enter woodley-park failed")
		_cleanup()
		return false
	var fin_fourth := NeighbourhoodProgress.finish(DB, "hood:washington-dc:woodley-park")
	if not bool(fin_fourth.get("ok", false)) or bool(fin_fourth.get("finale_opened", true)):
		push_error("FAIL [falsifier]: At F=4, finale must NOT open yet: %s" % str(fin_fourth))
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("hood:washington-dc:lincoln-memorial").is_empty():
		push_error("FAIL [falsifier]: Lincoln Memorial has a row at F=4!")
		_cleanup()
		return false
	# Even with picks_left == 1 at F=4, opening finale with a pick MUST be refused
	var refuse_finale_at_4 := NeighbourhoodProgress.open(DB, "hood:washington-dc:lincoln-memorial")
	if bool(refuse_finale_at_4.get("ok", true)) or str(refuse_finale_at_4.get("error", "")) != "not openable":
		push_error("FAIL [falsifier]: Finale was not refused at F=4: %s" % str(refuse_finale_at_4))
		_cleanup()
		return false

	# Finish 5th neighbourhood (tidal-basin, F=5) -> Lincoln Memorial opens automatically!
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:tidal-basin"):
		push_error("FAIL (§2.7 step 4): enter tidal-basin failed")
		_cleanup()
		return false
	var fin_fifth := NeighbourhoodProgress.finish(DB, "hood:washington-dc:tidal-basin")
	if not bool(fin_fifth.get("ok", false)) or not bool(fin_fifth.get("finale_opened", false)) or bool(fin_fifth.get("city_complete", true)):
		push_error("FAIL (§2.7 step 4): At F=5, expected finale_opened=true, city_complete=false, got %s" % str(fin_fifth))
		_cleanup()
		return false
	var lincoln_ns := DB.get_neighbourhood_state("hood:washington-dc:lincoln-memorial")
	if lincoln_ns.is_empty() or int(lincoln_ns.get("state", 0)) != 1 or str(lincoln_ns.get("opened_by", "")) != "finale":
		push_error("FAIL (§2.7 step 4): Lincoln Memorial row mismatch after F=5 auto-open: %s" % str(lincoln_ns))
		_cleanup()
		return false
	var lincoln_area := Neighbourhoods.area("hood:washington-dc:lincoln-memorial")
	for lc in Neighbourhoods.block_cells(lincoln_area):
		if int(DB.get_map_cell(lc.x, lc.y).get("reveal_state", 0)) != 1:
			push_error("FAIL (§2.7 step 4): Lincoln Memorial cell %s not revealed as known (1)" % str(lc))
			_cleanup()
			return false
	if NeighbourhoodProgress.city_complete(DB, PLACE_DC):
		push_error("FAIL (§2.7 step 4): City should not be complete before Lincoln Memorial is finished")
		_cleanup()
		return false

	# Step 5: Enter and finish Lincoln Memorial -> Washington DC is complete (with 2 neighbourhoods skipped)
	if not NeighbourhoodProgress.enter(DB, "hood:washington-dc:lincoln-memorial"):
		push_error("FAIL (§2.7 step 5): enter lincoln-memorial failed")
		_cleanup()
		return false
	var fin_finale := NeighbourhoodProgress.finish(DB, "hood:washington-dc:lincoln-memorial")
	if not bool(fin_finale.get("ok", false)) or not bool(fin_finale.get("city_complete", false)):
		push_error("FAIL (§2.7 step 5): Finishing Lincoln Memorial should complete city, got %s" % str(fin_finale))
		_cleanup()
		return false
	if not NeighbourhoodProgress.city_complete(DB, PLACE_DC):
		push_error("FAIL (§2.7 step 5): city_complete returned false after Lincoln Memorial finished")
		_cleanup()
		return false

	# -------------------------------------------------------------------------
	# 4. Demo-only controls (Standing Constraint 22, §7.2, §7.5, §9)
	# -------------------------------------------------------------------------
	# Test runs without --demo -> is_demo_profile() is false
	if NeighbourhoodProgress.is_demo_profile():
		push_error("FAIL: Expected headless test runner to run outside demo profile")
		_cleanup()
		return false
	var demo_refused := NeighbourhoodProgress.demo_force_open(DB, "hood:washington-dc:capitol-hill")
	if bool(demo_refused.get("ok", true)) or str(demo_refused.get("error", "")) != "demo only":
		push_error("FAIL [falsifier]: demo_force_open outside demo profile must refuse with 'demo only', got %s" % str(demo_refused))
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("hood:washington-dc:capitol-hill").is_empty():
		push_error("FAIL [falsifier]: Refused demo_force_open wrote a row!")
		_cleanup()
		return false

	# Board check: Open capitol-hill with an earned pick and enter it (state=2); outside demo profile,
	# 'Mark main quest done (demo)' MUST be absent!
	if not bool(NeighbourhoodProgress.open(DB, "hood:washington-dc:capitol-hill").get("ok", false)) or not NeighbourhoodProgress.enter(DB, "hood:washington-dc:capitol-hill"):
		push_error("FAIL: Could not open & enter capitol-hill for board check")
		_cleanup()
		return false

	var board_scene := load("res://scenes/waypost_board.tscn") as PackedScene
	if board_scene == null:
		push_error("FAIL: Could not load res://scenes/waypost_board.tscn")
		_cleanup()
		return false
	var board := board_scene.instantiate()
	add_child(board)
	board.open_for_place(PLACE_DC, DB)

	var ch_info_non_demo: Dictionary = board.get_row_info("hood:washington-dc:capitol-hill")
	if bool(ch_info_non_demo.get("has_demo_finish", true)) or _find_button_with_text(board, "Mark main quest done") != null:
		push_error("FAIL [falsifier]: WaypostBoard showed 'Mark main quest done (demo)' outside a demo profile!")
		board.queue_free()
		_cleanup()
		return false

	# Inside demo profile (simulated via override), state=2 shows 'Mark main quest done (demo)'
	NeighbourhoodProgress.set_demo_override_for_tests(1)
	board.refresh()
	var ch_info_demo: Dictionary = board.get_row_info("hood:washington-dc:capitol-hill")
	var demo_btn := _find_button_with_text(board, "Mark main quest done (demo)")
	if not bool(ch_info_demo.get("has_demo_finish", false)) or demo_btn == null:
		push_error("FAIL: WaypostBoard did not show 'Mark main quest done (demo)' in demo profile for entered neighbourhood")
		board.queue_free()
		_cleanup()
		return false
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	board.queue_free()

	# -------------------------------------------------------------------------
	# 5. Atomic transaction rollback: A failed write leaves no row (§7.2, §9)
	# -------------------------------------------------------------------------
	_reset_tables()
	NeighbourhoodProgress.ensure_camp(DB, PLACE_DC)
	DB.execute_query("DELETE FROM map_cell;")
	DB.execute_query("CREATE TEMP TRIGGER fail_ns_map_cell BEFORE INSERT ON map_cell BEGIN SELECT RAISE(ABORT, 'simulated map_cell failure'); END;")
	var failed_open := NeighbourhoodProgress.open(DB, "hood:washington-dc:national-mall")
	DB.execute_query("DROP TRIGGER IF EXISTS fail_ns_map_cell;")
	if bool(failed_open.get("ok", true)):
		push_error("FAIL: Expected open() to fail when map_cell trigger aborted")
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("hood:washington-dc:national-mall").is_empty():
		push_error("FAIL: Failed open() left a partial row in neighbourhood_state instead of rolling back!")
		_cleanup()
		return false
	if DB._in_transaction:
		push_error("FAIL: DB remained _in_transaction after rollback")
		_cleanup()
		return false

	# Transition check for Item 53: while a city has no routes, any opened neighbourhood has can_go == true
	if Neighbourhoods.routes_of(PLACE_DC).is_empty():
		_reset_tables()
		NeighbourhoodProgress.ensure_camp(DB, PLACE_DC)
		NeighbourhoodProgress.open(DB, "hood:washington-dc:national-mall")
		NeighbourhoodProgress.open(DB, "hood:washington-dc:dupont-circle")
		NeighbourhoodProgress.enter(DB, "hood:washington-dc:dupont-circle")
		NeighbourhoodProgress.finish(DB, "hood:washington-dc:dupont-circle")
		NeighbourhoodProgress.open(DB, "hood:washington-dc:georgetown")
		if not NeighbourhoodProgress.can_go(DB, "hood:washington-dc:georgetown"):
			push_error("FAIL: Non-routes city must allow can_go on opened inner neighbourhood during Item 53")
			_cleanup()
			return false

	# -------------------------------------------------------------------------
	# 6. Item 53 Routes & Board Falsifiers on Fixture City (§10.6, §10.7, §10.12)
	# -------------------------------------------------------------------------
	if not _write_routes_fixture_roster():
		push_error("FAIL: Could not write progress_routes_fixture.json")
		_cleanup()
		return false
	Neighbourhoods.set_config_path_for_tests(TEST_ROUTES_ROSTER_PATH)
	_reset_tables()

	if not NeighbourhoodProgress.ensure_camp(DB, PLACE_FIX):
		push_error("FAIL (53): ensure_camp failed on fixture-routes")
		_cleanup()
		return false
	if not NeighbourhoodProgress.can_go(DB, "camp:fixture-routes"):
		push_error("FAIL (53): can_go must be true for camp")
		_cleanup()
		return false

	# Open 2 gateways (gw-1, gw-2); inner in-1 is NOT open yet -> routes touching in-1 MUST NOT open!
	if not bool(NeighbourhoodProgress.open(DB, "hood:fixture-routes:gw-1").get("ok", false)):
		push_error("FAIL (53): open gw-1 failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.open(DB, "hood:fixture-routes:gw-2").get("ok", false)):
		push_error("FAIL (53): open gw-2 failed")
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("route:fixture-routes:r-g1-in1").is_empty() or not DB.get_neighbourhood_state("route:fixture-routes:r-g2-in1").is_empty():
		push_error("FAIL (53) [falsifier]: Route opened when only one of its ends was open!")
		_cleanup()
		return false
	if not NeighbourhoodProgress.can_go(DB, "hood:fixture-routes:gw-1") or NeighbourhoodProgress.can_go(DB, "hood:fixture-routes:gw-3"):
		push_error("FAIL (53): can_go must be true for opened gateway gw-1 and false for closed gw-3")
		_cleanup()
		return false

	# Enter & finish gw-1 (state=3), leaving gw-2 unentered (state=1), then open inner in-1 (state=1)
	if not NeighbourhoodProgress.enter(DB, "hood:fixture-routes:gw-1") or not bool(NeighbourhoodProgress.finish(DB, "hood:fixture-routes:gw-1").get("ok", false)):
		push_error("FAIL (53): enter/finish gw-1 failed")
		_cleanup()
		return false
	if not bool(NeighbourhoodProgress.open(DB, "hood:fixture-routes:in-1").get("ok", false)):
		push_error("FAIL (53): open in-1 failed")
		_cleanup()
		return false

	# Both r-g1-in1 and r-g2-in1 now have both ends open -> both open (state=1, opened_by="route"), leg cells known (1)
	var rg1 := DB.get_neighbourhood_state("route:fixture-routes:r-g1-in1")
	var rg2 := DB.get_neighbourhood_state("route:fixture-routes:r-g2-in1")
	if rg1.is_empty() or int(rg1.get("state", 0)) != 1 or str(rg1.get("opened_by", "")) != "route":
		push_error("FAIL (53): Expected r-g1-in1 open (state=1, route), got %s" % str(rg1))
		_cleanup()
		return false
	if rg2.is_empty() or int(rg2.get("state", 0)) != 1 or str(rg2.get("opened_by", "")) != "route":
		push_error("FAIL (53): Expected r-g2-in1 open (state=1, route), got %s" % str(rg2))
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("route:fixture-routes:r-g2-in2").is_empty():
		push_error("FAIL (53) [falsifier]: r-g2-in2 opened even though in-2 is still closed!")
		_cleanup()
		return false
	for lc in Neighbourhoods.block_cells(Neighbourhoods.area("route:fixture-routes:r-g1-in1#1")):
		if int(DB.get_map_cell(lc.x, lc.y).get("reveal_state", 0)) != 1:
			push_error("FAIL (53): Opened route leg cell %s not revealed known (1)" % str(lc))
			_cleanup()
			return false

	# Falsifier: can_go is FALSE for opened inner neighbourhood in-1 until a route is walked into it!
	if NeighbourhoodProgress.can_go(DB, "hood:fixture-routes:in-1"):
		push_error("FAIL (53) [falsifier]: can_go returned true for opened inner neighbourhood before walking a route!")
		_cleanup()
		return false

	# walk_from(in-1) lists only r-g1-in1 (gw-1 is state 3 >= 2; gw-2 is state 1 < 2)
	var wf_in1: Array[String] = NeighbourhoodProgress.walk_from(DB, "hood:fixture-routes:in-1")
	if wf_in1 != ["route:fixture-routes:r-g1-in1"]:
		push_error("FAIL (53): Expected walk_from(in-1) == ['route:fixture-routes:r-g1-in1'], got %s" % str(wf_in1))
		_cleanup()
		return false

	# Falsifier: walk_route refused when from_area_id is not entered (gw-2 is state=1 < 2)
	var bad_walk := NeighbourhoodProgress.walk_route(DB, "route:fixture-routes:r-g2-in1", "hood:fixture-routes:gw-2")
	if bool(bad_walk.get("ok", true)):
		push_error("FAIL (53) [falsifier]: walk_route succeeded from unentered end gw-2: %s" % str(bad_walk))
		_cleanup()
		return false

	# Board checks on Walk there row & demo-only Walk button (standing constraint 22, §10.7, §10.12)
	var r_board := board_scene.instantiate()
	add_child(r_board)
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	r_board.open_for_place(PLACE_FIX, DB)
	var in1_info_prod: Dictionary = r_board.get_row_info("hood:fixture-routes:in-1")
	if str(in1_info_prod.get("state_text", "")) != "Walk there" or bool(in1_info_prod.get("has_go", true)):
		push_error("FAIL (53): Expected 'Walk there' with no Go on in-1, got %s" % str(in1_info_prod))
		r_board.queue_free()
		_cleanup()
		return false
	var card_prod := str(in1_info_prod.get("card_text", ""))
	if not card_prod.contains("Walk: Route G1-In1 from Gateway 1") or not card_prod.contains("Walk: Route G2-In1 from Gateway 2 (go there first)"):
		push_error("FAIL (53): Expected route walk hints on card, got: %s" % card_prod)
		r_board.queue_free()
		_cleanup()
		return false
	if _find_button_with_text(r_board, "Walk ") != null:
		push_error("FAIL (53) [falsifier]: Board showed 'Walk (demo)' button outside a demo profile!")
		r_board.queue_free()
		_cleanup()
		return false

	NeighbourhoodProgress.set_demo_override_for_tests(1)
	r_board.refresh()
	var walk_demo_btn := _find_button_with_text(r_board, "Walk Route G1-In1 (demo)")
	var unentered_walk_btn := _find_button_with_text(r_board, "Walk Route G2-In1 (demo)")
	if walk_demo_btn == null or unentered_walk_btn != null:
		push_error("FAIL (53): Expected 'Walk Route G1-In1 (demo)' present and unentered 'Walk Route G2-In1 (demo)' absent in demo mode")
		r_board.queue_free()
		_cleanup()
		return false
	NeighbourhoodProgress.set_demo_override_for_tests(-1)
	r_board.queue_free()

	# Walk r-g1-in1 from gw-1 -> raises route & in-1 to state=2 (cleared), and can_go(in-1) becomes true!
	var ok_walk := NeighbourhoodProgress.walk_route(DB, "route:fixture-routes:r-g1-in1", "hood:fixture-routes:gw-1")
	if not bool(ok_walk.get("ok", false)) or str(ok_walk.get("arrived_at", "")) != "hood:fixture-routes:in-1":
		push_error("FAIL (53): walk_route failed: %s" % str(ok_walk))
		_cleanup()
		return false
	if int(DB.get_neighbourhood_state("route:fixture-routes:r-g1-in1").get("state", 0)) != 2:
		push_error("FAIL (53): walk_route did not raise route to state 2")
		_cleanup()
		return false
	if int(DB.get_neighbourhood_state("hood:fixture-routes:in-1").get("state", 0)) != 2 or not NeighbourhoodProgress.can_go(DB, "hood:fixture-routes:in-1"):
		push_error("FAIL (53): walk_route did not enter in-1 / unlock can_go")
		_cleanup()
		return false
	for lc2 in Neighbourhoods.block_cells(Neighbourhoods.area("route:fixture-routes:r-g1-in1#1")):
		if int(DB.get_map_cell(lc2.x, lc2.y).get("reveal_state", 0)) != 2:
			push_error("FAIL (53): Walked route leg cell %s not cleared (2)" % str(lc2))
			_cleanup()
			return false

	# Finish up to F=5 (gw-1 already finished; finish in-1, gw-2, in-2, gw-3; keep in-3 unopened) -> finale & its open-end routes open!
	NeighbourhoodProgress.finish(DB, "hood:fixture-routes:in-1") # F=2 -> 1 pick -> open in-2
	NeighbourhoodProgress.enter(DB, "hood:fixture-routes:gw-2")
	NeighbourhoodProgress.open(DB, "hood:fixture-routes:in-2")
	NeighbourhoodProgress.walk_route(DB, "route:fixture-routes:r-g2-in2", "hood:fixture-routes:gw-2")
	NeighbourhoodProgress.finish(DB, "hood:fixture-routes:gw-2") # F=3 -> 1 pick -> open gw-3
	NeighbourhoodProgress.open(DB, "hood:fixture-routes:gw-3")
	NeighbourhoodProgress.finish(DB, "hood:fixture-routes:in-2") # F=4
	NeighbourhoodProgress.enter(DB, "hood:fixture-routes:gw-3")
	var fin5 := NeighbourhoodProgress.finish(DB, "hood:fixture-routes:gw-3") # F=5 -> finale opens!
	if not bool(fin5.get("finale_opened", false)):
		push_error("FAIL (53): Expected finale_opened=true at F=5, got %s" % str(fin5))
		_cleanup()
		return false
	if DB.get_neighbourhood_state("route:fixture-routes:r-g1-fin").is_empty() or DB.get_neighbourhood_state("route:fixture-routes:r-in2-fin").is_empty():
		push_error("FAIL (53): Finale's routes to opened neighbours did not open when finish opened the finale!")
		_cleanup()
		return false
	if not DB.get_neighbourhood_state("route:fixture-routes:r-in3-fin").is_empty():
		push_error("FAIL (53): Finale route to unopened in-3 should remain closed!")
		_cleanup()
		return false
	if NeighbourhoodProgress.can_go(DB, "hood:fixture-routes:fin"):
		push_error("FAIL (53): Finale must also require walking a route the first time (can_go == false at state 1)")
		_cleanup()
		return false

	_cleanup()
	print("PASS: neighbourhood_progress_test")
	return true
