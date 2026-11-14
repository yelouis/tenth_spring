extends Node

# game/tests/caricature_check_test.gd — Playable-Size & Reachability Measurement Tests (Item 48a)
# Contract: docs/implementation_plan_dc_trial.md §5.1–§5.2, §9; docs/agent_execution_guide.md §4

const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")

const FIXTURE_ROSTER := "res://tests/fixtures/neighbourhoods_fixture.json"
const FIXTURE_MAP := "res://tests/fixtures/caricature_fixture_map.json"

func _cleanup() -> void:
	Neighbourhoods.set_config_path_for_tests("")

func _make_camp_map(grid: Array, lamp: Array) -> Dictionary:
	var rows: Array[String] = []
	for r in grid:
		rows.append("".join(r))
	return {
		"schema": 1,
		"id": "camp:fixture-city",
		"rows": rows,
		"objects": [],
		"lamp": lamp,
		"signs": [],
	}

func _blank_32_grid(fill_char: String) -> Array:
	var grid := []
	for y in range(32):
		var row := []
		for x in range(32):
			if x < 3 or x >= 29 or y < 3 or y >= 29:
				row.append("T")
			else:
				row.append(fill_char)
		grid.append(row)
	return grid

func run_test() -> bool:
	Neighbourhoods.set_config_path_for_tests(FIXTURE_ROSTER)
	var hood_area := Neighbourhoods.area("hood:fixture-city:north-end")
	var camp_area := Neighbourhoods.area("camp:fixture-city")
	if hood_area.is_empty() or camp_area.is_empty():
		_cleanup()
		push_error("caricature_check_test: missing fixture roster areas")
		return false

	# -------------------------------------------------------------
	# 1. Fixture 64x64 map passes P1–P7 with unreached=0 and trapped=0
	# -------------------------------------------------------------
	var map_dict := CaricatureMap.load_map(FIXTURE_MAP)
	var compiled := CaricatureMap.compile(hood_area, map_dict)
	if not bool(compiled.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: fixture map compile failed: %s" % str(compiled.get("errors", [])))
		return false

	var m_fix := CaricatureCheck.measure(compiled, hood_area)
	print(
		"[CARICATURE CHECK FIXTURE] ok=%s unreached=%d trapped=%d max_walk=%d landmark_max=%d tall_grass=%.3f search_doors=%d landmarks=%d/%d art_pending=%d" % [
			str(m_fix["ok"]),
			int(m_fix["unreached"]),
			int(m_fix["trapped"]),
			int(m_fix["max_walk"]),
			int(m_fix["landmark_max"]),
			float(m_fix["tall_grass_share"]),
			int(m_fix["search_doors"]),
			int(m_fix["landmarks_present"]),
			int(m_fix["landmarks_listed"]),
			int(m_fix["art_pending"]),
		]
	)
	if not bool(m_fix["ok"]):
		_cleanup()
		push_error("caricature_check_test: fixture map failed rules: %s" % str(m_fix["failed_rules"]))
		return false
	if int(m_fix["unreached"]) != 0 or int(m_fix["trapped"]) != 0:
		_cleanup()
		push_error("caricature_check_test: expected unreached=0 and trapped=0 on fixture")
		return false
	if int(m_fix["search_doors"]) != 5 or int(m_fix["landmarks_present"]) != 3:
		_cleanup()
		push_error("caricature_check_test: expected search_doors=5 and landmarks_present=3, got %d and %d" % [int(m_fix["search_doors"]), int(m_fix["landmarks_present"])])
		return false

	# -------------------------------------------------------------
	# 2. ▶ Walled-off pocket falsifier: unreached > 0 and fails P1
	# -------------------------------------------------------------
	var g_pocket := _blank_32_grid(".")
	# Wall off a 3x3 grass pocket at x=10..12, y=10..12 with a 5x5 ring of trees at x=9..13, y=9..13
	for y in range(9, 14):
		for x in range(9, 14):
			if x == 9 or x == 13 or y == 9 or y == 13:
				g_pocket[y][x] = "T"
			else:
				g_pocket[y][x] = "."
	var c_pocket := CaricatureMap.compile(camp_area, _make_camp_map(g_pocket, [16, 25]))
	if not bool(c_pocket["ok"]):
		_cleanup()
		push_error("caricature_check_test: pocket grid compile failed: %s" % str(c_pocket["errors"]))
		return false
	var m_pocket := CaricatureCheck.measure(c_pocket, camp_area)
	if int(m_pocket["unreached"]) != 9 or not (m_pocket["failed_rules"] as Array).has("P1"):
		_cleanup()
		push_error("caricature_check_test: pocket falsifier expected unreached=9 and P1, got unreached=%d rules=%s" % [int(m_pocket["unreached"]), str(m_pocket["failed_rules"])])
		return false

	# -------------------------------------------------------------
	# 3. ▶ Pit behind one-way ledge falsifier: trapped > 0 and fails P2
	# -------------------------------------------------------------
	var g_pit := _blank_32_grid(".")
	# 3x3 grass pit at x=10..12, y=10..12 surrounded by trees except north wall (11, 9) is 'v' (jump south)
	for y in range(9, 14):
		for x in range(9, 14):
			if x == 9 or x == 13 or y == 9 or y == 13:
				g_pit[y][x] = "T"
			else:
				g_pit[y][x] = "."
	g_pit[9][11] = "v"
	var c_pit := CaricatureMap.compile(camp_area, _make_camp_map(g_pit, [16, 25]))
	if not bool(c_pit["ok"]):
		_cleanup()
		push_error("caricature_check_test: pit grid compile failed: %s" % str(c_pit["errors"]))
		return false
	var m_pit := CaricatureCheck.measure(c_pit, camp_area)
	if int(m_pit["unreached"]) != 0 or int(m_pit["trapped"]) != 9 or not (m_pit["failed_rules"] as Array).has("P2"):
		_cleanup()
		push_error("caricature_check_test: pit falsifier expected unreached=0, trapped=9, P2; got unreached=%d trapped=%d rules=%s" % [int(m_pit["unreached"]), int(m_pit["trapped"]), str(m_pit["failed_rules"])])
		return false

	# -------------------------------------------------------------
	# 4. Known straight corridor gives exact max_walk
	# -------------------------------------------------------------
	var g_corr := _blank_32_grid("T")
	# Lamp at [15, 5], arrival at [15, 6]; 1-wide grass corridor from y=6 down to y=21 (15 steps south)
	g_corr[4][15] = "T"
	g_corr[5][15] = "." # lamp tile must be walkable before lamp sign is placed
	for y in range(6, 22):
		g_corr[y][15] = "."
	var c_corr := CaricatureMap.compile(camp_area, _make_camp_map(g_corr, [15, 5]))
	if not bool(c_corr["ok"]):
		_cleanup()
		push_error("caricature_check_test: corridor grid compile failed: %s" % str(c_corr["errors"]))
		return false
	var m_corr := CaricatureCheck.measure(c_corr, camp_area)
	if int(m_corr["walkable"]) != 16 or int(m_corr["reached"]) != 16 or int(m_corr["unreached"]) != 0 or int(m_corr["trapped"]) != 0 or int(m_corr["max_walk"]) != 15:
		_cleanup()
		push_error("caricature_check_test: corridor expected walkable=16 reached=16 max_walk=15, got %s" % str(m_corr))
		return false

	# -------------------------------------------------------------
	# 5. Item 53 (§10.5, §10.12): Route fixture city — ends_steps, ledge trap, P9, RP1–RP2, C0 & C1
	# -------------------------------------------------------------
	Neighbourhoods.set_config_path_for_tests("res://tests/fixtures/caricature_routes_fixture_roster.json")
	var r_camp_area := Neighbourhoods.area("camp:fixture-city")
	var r_hood_a_area := Neighbourhoods.area("hood:fixture-city:north-end")
	var r_hood_b_area := Neighbourhoods.area("hood:fixture-city:south-harbor")
	var r_leg_area := Neighbourhoods.area("route:fixture-city:harbor-road#1")
	var r_route_dict := Neighbourhoods.route("route:fixture-city:harbor-road")

	var r_camp_map := CaricatureMap.load_map("res://tests/fixtures/caricature_route_camp.json")
	var r_hood_a_map := CaricatureMap.load_map("res://tests/fixtures/caricature_route_hood_a.json")
	var r_hood_b_map := CaricatureMap.load_map("res://tests/fixtures/caricature_route_hood_b.json")
	var r_leg_map := CaricatureMap.load_map("res://tests/fixtures/caricature_route_leg.json")

	var c_rcamp := CaricatureMap.compile(r_camp_area, r_camp_map)
	var c_rhood_a := CaricatureMap.compile(r_hood_a_area, r_hood_a_map)
	var c_rhood_b := CaricatureMap.compile(r_hood_b_area, r_hood_b_map)
	var c_rleg := CaricatureMap.compile(r_leg_area, r_leg_map)
	if not (bool(c_rcamp["ok"]) and bool(c_rhood_a["ok"]) and bool(c_rhood_b["ok"]) and bool(c_rleg["ok"])):
		_cleanup()
		push_error("caricature_check_test: route fixture maps failed to compile")
		return false

	var m_rcamp := CaricatureCheck.measure(c_rcamp, r_camp_area)
	var m_rhood_a := CaricatureCheck.measure(c_rhood_a, r_hood_a_area)
	var m_rhood_b := CaricatureCheck.measure(c_rhood_b, r_hood_b_area)
	var m_rleg := CaricatureCheck.measure(c_rleg, r_leg_area)

	# (a) ▶ ends_steps is exact on known path (63 steps from y=0 to y=63) and all 4 maps pass
	if not bool(m_rcamp["ok"]) or not bool(m_rhood_a["ok"]) or not bool(m_rhood_b["ok"]) or not bool(m_rleg["ok"]):
		_cleanup()
		push_error("caricature_check_test: route fixture measure failed: camp=%s a=%s b=%s leg=%s" % [
			str(m_rcamp["failed_rules"]), str(m_rhood_a["failed_rules"]),
			str(m_rhood_b["failed_rules"]), str(m_rleg["failed_rules"])
		])
		return false
	if int(m_rleg.get("ends_steps", -1)) != 63:
		_cleanup()
		push_error("caricature_check_test: expected exact ends_steps=63 on fixture leg, got %s" % str(m_rleg.get("ends_steps", -1)))
		return false

	# Route check RP1 & RP2 pass on aligned fixture
	var compiled_by_id := {
		"camp:fixture-city": c_rcamp,
		"hood:fixture-city:north-end": c_rhood_a,
		"hood:fixture-city:south-harbor": c_rhood_b,
		"route:fixture-city:harbor-road#1": c_rleg,
	}
	var measures_by_id := {
		"camp:fixture-city": m_rcamp,
		"hood:fixture-city:north-end": m_rhood_a,
		"hood:fixture-city:south-harbor": m_rhood_b,
		"route:fixture-city:harbor-road#1": m_rleg,
	}
	var rp_res := CaricatureCheck.check_route(r_route_dict, compiled_by_id, measures_by_id)
	if not bool(rp_res.get("ok", false)) or int(rp_res.get("landmarks_present", 0)) != 1 or int(rp_res.get("end_signs", 0)) != 2:
		_cleanup()
		push_error("caricature_check_test: expected check_route ok with landmarks=1, end_signs=2; got %s" % str(rp_res))
		return false

	# (b) ▶ Ledge across leg that strands south end gives trapped > 0 and fails P2
	var leg_stranded := r_leg_map.duplicate(true)
	var row27 := str(leg_stranded["rows"][27])
	var ledge_band := row27.substr(0, 6) + "vvvvvvvvvvvvvvvvvvvv" + row27.substr(26)
	leg_stranded["rows"][27] = ledge_band
	var c_leg_stranded := CaricatureMap.compile(r_leg_area, leg_stranded)
	if not bool(c_leg_stranded["ok"]):
		_cleanup()
		push_error("caricature_check_test: stranded leg compile failed: %s" % str(c_leg_stranded["errors"]))
		return false
	var m_leg_stranded := CaricatureCheck.measure(c_leg_stranded, r_leg_area)
	if int(m_leg_stranded["trapped"]) <= 0 or not (m_leg_stranded["failed_rules"] as Array).has("P2"):
		_cleanup()
		push_error("caricature_check_test: ledge stranding south end expected trapped > 0 and P2, got trapped=%d rules=%s" % [
			int(m_leg_stranded["trapped"]), str(m_leg_stranded["failed_rules"])
		])
		return false

	# (c) ▶ A 12x12 plain-grass window fails P9
	var hood_lawn := r_hood_a_map.duplicate(true)
	for ly in range(30, 42):
		var lr := str(hood_lawn["rows"][ly])
		hood_lawn["rows"][ly] = lr.substr(0, 28) + "............" + lr.substr(40)
	var c_hood_lawn := CaricatureMap.compile(r_hood_a_area, hood_lawn)
	if not bool(c_hood_lawn["ok"]):
		_cleanup()
		push_error("caricature_check_test: lawn copy compile failed: %s" % str(c_hood_lawn["errors"]))
		return false
	var m_hood_lawn := CaricatureCheck.measure(c_hood_lawn, r_hood_a_area)
	if bool(m_hood_lawn["ok"]) or not (m_hood_lawn["failed_rules"] as Array).has("P9"):
		_cleanup()
		push_error("caricature_check_test: 12x12 plain-grass window did not fail P9: %s" % str(m_hood_lawn["failed_rules"]))
		return false

	# (d) ▶ Aligned openings pass C0 and C1; moving one opening by 1 tile fails C0 and then C1
	var city_ok := CaricatureCheck.check_city("city:fixture-city", compiled_by_id)
	if not bool(city_ok.get("ok", false)) or int(city_ok.get("openings_aligned", 0)) != 2 or int(city_ok.get("connected", 0)) != 2:
		_cleanup()
		push_error("caricature_check_test: aligned fixture city expected C0/C1 PASS (2/2, 2/2), got %s" % str(city_ok))
		return false

	var hood_shifted := r_hood_a_map.duplicate(true)
	hood_shifted["openings"] = [{"side": "S", "at": 15, "width": 3}]
	for sy in [92, 93, 94, 95]:
		var sr := str(hood_shifted["rows"][sy])
		if sy >= 93:
			hood_shifted["rows"][sy] = sr.substr(0, 14) + "T---" + sr.substr(18)
		else:
			hood_shifted["rows"][sy] = sr.substr(0, 14) + "----" + sr.substr(18)
	var c_hood_shifted := CaricatureMap.compile(r_hood_a_area, hood_shifted)
	if not bool(c_hood_shifted["ok"]):
		_cleanup()
		push_error("caricature_check_test: shifted opening hood compile failed: %s" % str(c_hood_shifted["errors"]))
		return false
	var shifted_compiled := compiled_by_id.duplicate()
	shifted_compiled["hood:fixture-city:north-end"] = c_hood_shifted
	var city_shifted := CaricatureCheck.check_city("city:fixture-city", shifted_compiled)
	var sh_rules: Array = city_shifted.get("failed_rules", [])
	if bool(city_shifted.get("ok", true)) or not sh_rules.has("C0") or not sh_rules.has("C1"):
		_cleanup()
		push_error("caricature_check_test: 1-tile shifted opening expected C0 and C1 failure, got %s" % str(city_shifted))
		return false

	_cleanup()
	return true
