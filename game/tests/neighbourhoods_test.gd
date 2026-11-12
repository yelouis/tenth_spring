extends Node

# game/tests/neighbourhoods_test.gd — Roster Loader, Block Arithmetic & Stamp Check Tests (Item 47)
# Contract: docs/implementation_plan_dc_trial.md §1.3, §3.1, §9; docs/agent_execution_guide.md §3

const Neighbourhoods := preload("res://world/neighbourhoods.gd")

const FIXTURE_PATH := "res://tests/fixtures/neighbourhoods_fixture.json"

func _cleanup() -> void:
	Neighbourhoods.set_config_path_for_tests("")

func run_test() -> bool:
	# 1. Tuning constants (§1.5)
	if Config.neighbourhoods_per_city != 8:
		push_error("neighbourhoods_test: expected Config.neighbourhoods_per_city == 8, got %d" % Config.neighbourhoods_per_city)
		return false
	if Config.gateway_count != 4:
		push_error("neighbourhoods_test: expected Config.gateway_count == 4, got %d" % Config.gateway_count)
		return false
	if Config.first_picks != 2:
		push_error("neighbourhoods_test: expected Config.first_picks == 2, got %d" % Config.first_picks)
		return false
	if Config.finale_requires_finished != 5:
		push_error("neighbourhoods_test: expected Config.finale_requires_finished == 5, got %d" % Config.finale_requires_finished)
		return false

	# 2. Canonical Washington DC roster & §3.1 block origins relative to camp cell
	Neighbourhoods.set_config_path_for_tests("")
	if not Neighbourhoods.has_city("city:washington-dc"):
		push_error("neighbourhoods_test: canonical roster missing city:washington-dc")
		return false
	if Neighbourhoods.has_city("city:seattle"):
		push_error("neighbourhoods_test: canonical roster unexpectedly has city:seattle")
		return false
	if Neighbourhoods.is_ready("city:seattle"):
		push_error("neighbourhoods_test: non-roster city reported is_ready == true")
		return false

	var dc_areas := Neighbourhoods.areas_of("city:washington-dc")
	if dc_areas.size() != 9:
		push_error("neighbourhoods_test: expected 9 areas for Washington DC (camp + 8), got %d" % dc_areas.size())
		return false
	if str(dc_areas[0].get("id", "")) != "camp:washington-dc" or str(dc_areas[0].get("kind", "")) != "camp":
		push_error("neighbourhoods_test: first area must be camp:washington-dc with kind='camp'")
		return false

	var camp_area := Neighbourhoods.area("camp:washington-dc")
	var camp_origin := Neighbourhoods.block_origin(camp_area)
	var expected_rel := {
		"hood:washington-dc:national-mall": Vector2i(-3, -3),
		"hood:washington-dc:tidal-basin": Vector2i(-3, -7),
		"hood:washington-dc:capitol-hill": Vector2i(9, -3),
		"hood:washington-dc:dupont-circle": Vector2i(-5, 8),
		"hood:washington-dc:union-station": Vector2i(11, 1),
		"hood:washington-dc:georgetown": Vector2i(-18, 7),
		"hood:washington-dc:woodley-park": Vector2i(-8, 19),
		"hood:washington-dc:lincoln-memorial": Vector2i(-9, -3),
	}
	for hid in expected_rel.keys():
		var h_area := Neighbourhoods.area(hid)
		if h_area.is_empty():
			push_error("neighbourhoods_test: missing area %s" % hid)
			return false
		if str(h_area.get("kind", "")) != "hood":
			push_error("neighbourhoods_test: expected kind='hood' on %s" % hid)
			return false
		var rel := Neighbourhoods.block_origin(h_area) - camp_origin
		if rel != expected_rel[hid]:
			push_error("neighbourhoods_test: %s relative block origin expected %s, got %s" % [hid, str(expected_rel[hid]), str(rel)])
			return false

	# Ground distance check on DC gateways vs inner
	var d_mall := Neighbourhoods.distance_m("city:washington-dc", "hood:washington-dc:national-mall")
	var d_capitol := Neighbourhoods.distance_m("city:washington-dc", "hood:washington-dc:capitol-hill")
	var d_union := Neighbourhoods.distance_m("city:washington-dc", "hood:washington-dc:union-station")
	if not (d_mall > 650.0 and d_mall < 750.0 and d_capitol < d_union):
		push_error("neighbourhoods_test: unexpected DC distances mall=%f capitol=%f union=%f" % [d_mall, d_capitol, d_union])
		return false

	# Every landmark stamp in canonical roster is in STAMP_TABLE or marked art=pending
	var dc_stamp_check := Neighbourhoods.validate_landmark_stamps()
	if not bool(dc_stamp_check.get("ok", false)):
		push_error("neighbourhoods_test: canonical landmark stamp check failed: %s" % str(dc_stamp_check.get("errors", [])))
		return false

	# 3. Fixture roster block arithmetic worked by hand (§3.1, §9)
	Neighbourhoods.set_config_path_for_tests(FIXTURE_PATH)
	if not Neighbourhoods.has_city("city:fixture-city"):
		_cleanup()
		push_error("neighbourhoods_test: fixture missing city:fixture-city")
		return false
	if Neighbourhoods.is_ready("city:fixture-city") != false:
		_cleanup()
		push_error("neighbourhoods_test: fixture city ready should be false")
		return false

	var fix_camp := Neighbourhoods.area("camp:fixture-city")
	if Neighbourhoods.block_origin(fix_camp) != Vector2i(3, 4):
		_cleanup()
		push_error("neighbourhoods_test: fixture camp origin expected (3, 4), got %s" % str(Neighbourhoods.block_origin(fix_camp)))
		return false
	if Neighbourhoods.block_cells(fix_camp) != [Vector2i(3, 4)]:
		_cleanup()
		push_error("neighbourhoods_test: fixture camp cells mismatch")
		return false

	var fix_north := Neighbourhoods.area("hood:fixture-city:north-end")
	if Neighbourhoods.block_origin(fix_north) != Vector2i(6, 6):
		_cleanup()
		push_error("neighbourhoods_test: fixture north-end origin expected (6, 6), got %s" % str(Neighbourhoods.block_origin(fix_north)))
		return false
	var expected_north_cells: Array[Vector2i] = [
		Vector2i(6, 6),
		Vector2i(7, 6),
		Vector2i(6, 7),
		Vector2i(7, 7),
	]
	if Neighbourhoods.block_cells(fix_north) != expected_north_cells:
		_cleanup()
		push_error("neighbourhoods_test: fixture north-end block_cells expected %s, got %s" % [str(expected_north_cells), str(Neighbourhoods.block_cells(fix_north))])
		return false

	var fix_stamp_check := Neighbourhoods.validate_landmark_stamps()
	if not bool(fix_stamp_check.get("ok", false)):
		_cleanup()
		push_error("neighbourhoods_test: fixture landmark stamp check failed: %s" % str(fix_stamp_check.get("errors", [])))
		return false

	# 4. Falsifier: a landmark whose stamp is neither in STAMP_TABLE nor marked art="pending" fails
	DirAccess.make_dir_recursive_absolute("user://test")
	var bad_path := "user://test/neighbourhoods_bad_stamp.json"
	var raw_fixture := FileAccess.get_file_as_string(FIXTURE_PATH)
	var mutated: Dictionary = JSON.parse_string(raw_fixture)
	mutated["cities"][0]["ready"] = true
	mutated["cities"][0]["neighbourhoods"][1]["landmarks"][0] = {
		"name": "Broken Stamp Landmark",
		"stamp": "nonexistent_stamp_xyz"
	}
	var out_f := FileAccess.open(bad_path, FileAccess.WRITE)
	out_f.store_string(JSON.stringify(mutated))
	out_f.close()

	Neighbourhoods.set_config_path_for_tests(bad_path)
	if Neighbourhoods.is_ready("city:fixture-city") != true:
		_cleanup()
		DirAccess.remove_absolute(bad_path)
		push_error("neighbourhoods_test: ready=true copy did not report is_ready == true")
		return false
	var bad_check := Neighbourhoods.validate_landmark_stamps()
	_cleanup()
	DirAccess.remove_absolute(bad_path)

	if bool(bad_check.get("ok", true)):
		push_error("neighbourhoods_test falsifier failed: unknown stamp without art=pending was accepted")
		return false

	return true
