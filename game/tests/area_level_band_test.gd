extends Node

## game/tests/area_level_band_test.gd — Item 68 Real-Anchor Level Bands (§10.8) & Route Cost Helpers
## Contract: docs/implementation_plan_dc_trial.md §10.8; docs/implementation_plan_travel_and_time.md §(i), §(k)

const SpawnDirector := preload("res://encounters/spawn_director.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")

const TEST_NH_PATH: String = "user://test/area_level_band_test_nh.json"

func _cleanup() -> void:
	Neighbourhoods.set_config_path_for_tests("")
	if FileAccess.file_exists(TEST_NH_PATH):
		DirAccess.remove_absolute(TEST_NH_PATH)

func run_test() -> bool:
	_cleanup()

	# 1. All 9 DC areas with starter_place = city:washington-dc
	var dc_area_bands := {
		"camp:washington-dc": Vector2i(2, 10),
		"hood:washington-dc:national-mall": Vector2i(2, 10),
		"hood:washington-dc:tidal-basin": Vector2i(2, 10),
		"hood:washington-dc:lincoln-memorial": Vector2i(2, 10),
		"hood:washington-dc:dupont-circle": Vector2i(2, 10),
		"hood:washington-dc:capitol-hill": Vector2i(2, 10),
		"hood:washington-dc:union-station": Vector2i(2, 10),
		"hood:washington-dc:georgetown": Vector2i(8, 22),
		"hood:washington-dc:woodley-park": Vector2i(8, 22),
	}
	for aid in dc_area_bands.keys():
		var exp_band: Vector2i = dc_area_bands[aid]
		var got_band: Vector2i = SpawnDirector.compute_area_level_band(aid, "city:washington-dc")
		if got_band != exp_band:
			push_error("FAIL: DC starter band for %s expected %s, got %s (dist=%.3f mi)" % [aid, str(exp_band), str(got_band), SpawnDirector.compute_area_distance_miles(aid, "city:washington-dc")])
			_cleanup()
			return false

	# 2. All 10 DC routes (both bare route ID and #1 leg ID) with starter_place = city:washington-dc
	var dc_route_bands := {
		"route:washington-dc:pennsylvania-avenue": Vector2i(2, 10),
		"route:washington-dc:massachusetts-avenue": Vector2i(2, 10),
		"route:washington-dc:monument-grounds": Vector2i(2, 10),
		"route:washington-dc:constitution-gardens": Vector2i(2, 10),
		"route:washington-dc:west-potomac-park": Vector2i(2, 10),
		"route:washington-dc:upper-senate-park": Vector2i(2, 10),
		"route:washington-dc:potomac-riverfront": Vector2i(2, 10),
		"route:washington-dc:q-street": Vector2i(2, 10),
		"route:washington-dc:connecticut-avenue": Vector2i(2, 10),
		"route:washington-dc:rock-creek-trail": Vector2i(8, 22),
	}
	for rid in dc_route_bands.keys():
		var exp_band: Vector2i = dc_route_bands[rid]
		var got_bare: Vector2i = SpawnDirector.compute_area_level_band(rid, "city:washington-dc")
		var got_leg: Vector2i = SpawnDirector.compute_area_level_band(rid + "#1", "city:washington-dc")
		if got_bare != exp_band or got_leg != exp_band:
			push_error("FAIL: DC starter band for %s expected %s, got bare=%s leg=%s" % [rid, str(exp_band), str(got_bare), str(got_leg)])
			_cleanup()
			return false

	# 3. Other starter cities: Philadelphia (30-50), Boston (42-62), Seattle (65-85)
	if SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:philadelphia") != Vector2i(30, 50):
		push_error("FAIL: Philadelphia starter band for national-mall expected (30, 50), got %s" % str(SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:philadelphia")))
		_cleanup()
		return false
	if SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:boston") != Vector2i(42, 62):
		push_error("FAIL: Boston starter band for national-mall expected (42, 62), got %s" % str(SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:boston")))
		_cleanup()
		return false
	if SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:seattle") != Vector2i(65, 85):
		push_error("FAIL: Seattle starter band for national-mall expected (65, 85), got %s" % str(SpawnDirector.compute_area_level_band("hood:washington-dc:national-mall", "city:seattle")))
		_cleanup()
		return false

	# 4. Route walk minutes (foot & bicycle) and waypost_minutes_from_area
	var exp_route_mins := {
		"route:washington-dc:monument-grounds": [3, 2],
		"route:washington-dc:pennsylvania-avenue": [6, 3],
		"route:washington-dc:constitution-gardens": [4, 2],
		"route:washington-dc:west-potomac-park": [4, 2],
		"route:washington-dc:upper-senate-park": [3, 2],
		"route:washington-dc:q-street": [7, 4],
		"route:washington-dc:connecticut-avenue": [6, 3],
		"route:washington-dc:massachusetts-avenue": [9, 5],
		"route:washington-dc:rock-creek-trail": [8, 4],
		"route:washington-dc:potomac-riverfront": [7, 4],
	}
	for rid in exp_route_mins.keys():
		var pair: Array = exp_route_mins[rid]
		var foot_m: int = NeighbourhoodProgress.route_walk_minutes(rid, false)
		var bike_m: int = NeighbourhoodProgress.route_walk_minutes(rid, true)
		var leg_m: int = NeighbourhoodProgress.route_walk_minutes(rid + "#1", false)
		if foot_m != int(pair[0]) or bike_m != int(pair[1]) or leg_m != int(pair[0]):
			push_error("FAIL: route_walk_minutes(%s) expected foot=%d bike=%d, got foot=%d bike=%d leg=%d" % [rid, int(pair[0]), int(pair[1]), foot_m, bike_m, leg_m])
			_cleanup()
			return false

	if NeighbourhoodProgress.trip_minutes("city:washington-dc", "camp:washington-dc", "hood:washington-dc:georgetown", false) != 10:
		push_error("FAIL: Camp->Georgetown foot trip expected 10 min")
		_cleanup()
		return false
	if NeighbourhoodProgress.trip_minutes("city:washington-dc", "camp:washington-dc", "hood:washington-dc:georgetown", true) != 5:
		push_error("FAIL: Camp->Georgetown bike trip expected 5 min")
		_cleanup()
		return false
	if NeighbourhoodProgress.waypost_minutes_from_area("city:washington-dc", "camp:washington-dc") != 0:
		push_error("FAIL: waypost_minutes_from_area(camp) expected 0")
		_cleanup()
		return false
	if NeighbourhoodProgress.waypost_minutes_from_area("city:washington-dc", "hood:washington-dc:georgetown") != 10:
		push_error("FAIL: waypost_minutes_from_area(georgetown) expected 10")
		_cleanup()
		return false
	if NeighbourhoodProgress.waypost_minutes_from_area("city:washington-dc", "route:washington-dc:q-street#1") != 7:
		push_error("FAIL: waypost_minutes_from_area(q-street#1) expected 7, got %d" % NeighbourhoodProgress.waypost_minutes_from_area("city:washington-dc", "route:washington-dc:q-street#1"))
		_cleanup()
		return false

	# 5. FALSIFIER: moving Georgetown's block cell ("at") by +500 cells leaves band UNCHANGED;
	# moving its real "anchor" changes the band! (proving §10.8 real-anchor rule)
	var raw_txt := FileAccess.get_file_as_string(Neighbourhoods.DEFAULT_CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(raw_txt)
	if not (parsed is Dictionary):
		push_error("FAIL: Could not parse neighbourhoods.json for falsifier")
		_cleanup()
		return false
	var doc: Dictionary = parsed

	# Step 5a: shift Georgetown's "at" by +500 cells
	for c in doc["cities"]:
		if str(c.get("place_id", "")) == "city:washington-dc":
			for h in c["neighbourhoods"]:
				if str(h.get("id", "")) == "hood:washington-dc:georgetown":
					h["at"] = [int(h["at"][0]) + 500, int(h["at"][1]) + 500]
	var f1 := FileAccess.open(TEST_NH_PATH, FileAccess.WRITE)
	f1.store_string(JSON.stringify(doc))
	f1.close()
	Neighbourhoods.set_config_path_for_tests(TEST_NH_PATH)
	var band_after_at_shift: Vector2i = SpawnDirector.compute_area_level_band("hood:washington-dc:georgetown", "city:washington-dc")
	if band_after_at_shift != Vector2i(8, 22):
		push_error("FAIL: Shifting block cell 'at' by +500 changed Georgetown's band to %s (expected unchanged (8, 22))!" % str(band_after_at_shift))
		_cleanup()
		return false

	# Step 5b: shift Georgetown's real "anchor" lat by +2.0 deg (~138 mi -> 30-50 band)
	for c in doc["cities"]:
		if str(c.get("place_id", "")) == "city:washington-dc":
			for h in c["neighbourhoods"]:
				if str(h.get("id", "")) == "hood:washington-dc:georgetown":
					h["anchor"]["lat"] = float(h["anchor"]["lat"]) + 2.0
	var f2 := FileAccess.open(TEST_NH_PATH, FileAccess.WRITE)
	f2.store_string(JSON.stringify(doc))
	f2.close()
	Neighbourhoods.set_config_path_for_tests(TEST_NH_PATH)
	var band_after_anchor_shift: Vector2i = SpawnDirector.compute_area_level_band("hood:washington-dc:georgetown", "city:washington-dc")
	if band_after_anchor_shift != Vector2i(30, 50):
		push_error("FAIL: Shifting real 'anchor' by +2.0 deg expected (30, 50), got %s!" % str(band_after_anchor_shift))
		_cleanup()
		return false

	_cleanup()
	return true
