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
	# waypost_lamp (1x2, mask 2 overhang / mask 0 walkable) occupies (15, 4) and (15, 5), plus y=6..21 -> 18 walkable tiles
	var m_corr := CaricatureCheck.measure(c_corr, camp_area)
	if int(m_corr["walkable"]) != 18 or int(m_corr["reached"]) != 18 or int(m_corr["unreached"]) != 0 or int(m_corr["trapped"]) != 0 or int(m_corr["max_walk"]) != 15:
		_cleanup()
		push_error("caricature_check_test: corridor expected walkable=18 reached=18 max_walk=15, got %s" % str(m_corr))
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

	# -------------------------------------------------------------
	# 7. Item 62b (Decision 71): check_town T1-T7 tests & falsifiers
	# -------------------------------------------------------------
	var tg_base := _blank_32_grid(".")
	for tx in range(3, 29):
		tg_base[15][tx] = "-" if tx in [4, 7, 13, 19, 25] else "#"
		tg_base[16][tx] = "*" if tx in [6, 17, 27] else "#"
	tg_base[14][11] = "*"
	tg_base[17][22] = "-"
	# Asymmetric obstacle scatter so open 7x7 <= 5% and 0 non-uniform 8x8 repeats
	var obs_pts := [
		Vector2i(9, 6), Vector2i(14, 5), Vector2i(20, 6), Vector2i(25, 9),
		Vector2i(8, 11), Vector2i(13, 10), Vector2i(19, 11), Vector2i(24, 13),
		Vector2i(5, 14), Vector2i(10, 14), Vector2i(20, 14), Vector2i(26, 17),
		Vector2i(9, 19), Vector2i(15, 19), Vector2i(21, 19), Vector2i(13, 23),
		Vector2i(18, 22), Vector2i(10, 26), Vector2i(17, 27), Vector2i(27, 21),
		Vector2i(4, 12), Vector2i(27, 11), Vector2i(11, 3), Vector2i(18, 3),
		Vector2i(12, 28), Vector2i(20, 28), Vector2i(3, 19), Vector2i(28, 19),
		Vector2i(3, 9), Vector2i(3, 26), Vector2i(28, 7), Vector2i(6, 20),
	]
	for pi in range(obs_pts.size()):
		var op: Vector2i = obs_pts[pi]
		tg_base[op.y][op.x] = "T" if (pi % 3 != 0) else ("*" if pi % 2 == 0 else "F")
	var t_signs := [
		{"at": [9, 7], "text": "nw"}, {"at": [18, 8], "text": "ne"},
		{"at": [8, 17], "text": "sw"}, {"at": [18, 18], "text": "se"},
		{"at": [13, 13], "text": "c"}, {"at": [24, 12], "text": "e"},
		{"at": [14, 24], "text": "s"}, {"at": [23, 19], "text": "es"},
	]
	var t_people: Array = []
	var ppl_pts := [
		Vector2i(7, 9), Vector2i(12, 7), Vector2i(17, 6), Vector2i(21, 8),
		Vector2i(6, 18), Vector2i(11, 20), Vector2i(16, 14), Vector2i(21, 13),
		Vector2i(19, 25), Vector2i(25, 18),
	]
	for idx_p in range(ppl_pts.size()):
		t_people.append({
			"id": "p_%d" % idx_p,
			"name": "Resident %d" % idx_p,
			"at": [ppl_pts[idx_p].x, ppl_pts[idx_p].y],
			"sprite": "town_woman",
			"role": "talk",
		})
	var t_map := {
		"schema": 1,
		"id": "camp:fixture-city",
		"town": [[0, 0, 32, 32]],
		"rows": [],
		"objects": [
			{"stamp": "standing_house_s_door1", "at": [4, 4], "interior": "dc:camp-family-west"},
			{"stamp": "standing_house_s_door2", "at": [22, 4], "interior": "dc:camp-family-north"},
			{"stamp": "standing_house_m", "at": [4, 22], "interior": "dc:camp-infirmary"},
			{"stamp": "standing_block_8x7_a", "at": [20, 21], "interior": "dc:camp-supply-cottage"},
		],
		"fixtures": [{"kind": "em_fountain", "at": [14, 20]}],
		"people": t_people,
		"street_pokemon": [],
		"signs": t_signs,
		"hidden_items": [{"at": [6, 10], "item": "Potion", "note": "n"}],
		"lamp": [14, 14],
	}
	for r in tg_base:
		(t_map["rows"] as Array).append("".join(r))
	var c_tok := CaricatureMap.compile(camp_area, t_map)
	if not bool(c_tok.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: town baseline compile failed: %s" % str(c_tok.get("errors", [])))
		return false
	var res_tok := CaricatureCheck.check_town(c_tok, camp_area)
	if not bool(res_tok.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: expected synthetic town T1-T7 PASS, got %s" % str(res_tok))
		return false

	# T1 falsifier (4.0 floor): reduce people/signs/items so things_per_150 sits between 1.0 and 4.0 -> MUST FAIL T1
	var t_low_density := t_map.duplicate(true)
	t_low_density["signs"] = []
	t_low_density["hidden_items"] = []
	t_low_density["people"] = t_people.slice(0, 6)
	var c_low := CaricatureMap.compile(camp_area, t_low_density)
	var res_t1 := CaricatureCheck.check_town(c_low, camp_area)
	if bool(res_t1.get("ok", true)) or not (res_t1["failed_rules"] as Array).has("T1") or float(res_t1.get("things_per_150", 0.0)) < 1.0:
		_cleanup()
		push_error("caricature_check_test: expected T1 failure when 1.0 <= things_per_150 < 4.0, got %s" % str(res_t1))
		return false

	# T7 falsifier (open ground > 5%): open 32x32 blank lawn town -> MUST FAIL T7
	var t_open := {
		"schema": 1,
		"id": "camp:fixture-city",
		"town": [[0, 0, 32, 32]],
		"rows": [],
		"objects": [],
		"fixtures": [],
		"people": [],
		"street_pokemon": [],
		"signs": [{"at": [14, 16], "text": "c"}],
		"lamp": [14, 14],
	}
	for r in _blank_32_grid("."):
		(t_open["rows"] as Array).append("".join(r))
	var res_t7 := CaricatureCheck.check_town(CaricatureMap.compile(camp_area, t_open), camp_area)
	if bool(res_t7.get("ok", true)) or not (res_t7["failed_rules"] as Array).has("T7") or float(res_t7.get("open_ground_pct", 0.0)) <= 0.05:
		_cleanup()
		push_error("caricature_check_test: expected T7 failure on open lawn town, got %s" % str(res_t7))
		return false

	# T2 falsifier: tall grass inside town -> must FAIL T2
	var t_grass := t_map.duplicate(true)
	t_grass["rows"][10] = str(t_grass["rows"][10]).substr(0, 11) + "," + str(t_grass["rows"][10]).substr(12)
	var res_t2 := CaricatureCheck.check_town(CaricatureMap.compile(camp_area, t_grass), camp_area)
	if bool(res_t2.get("ok", true)) or not (res_t2["failed_rules"] as Array).has("T2"):
		_cleanup()
		push_error("caricature_check_test: expected T2 failure for tall grass in town, got %s" % str(res_t2))
		return false

	# T3 falsifier (whole map incl. route ground): 0% town wear + >5% route wear -> must FAIL T3
	var g_wear := _blank_32_grid(".")
	for wy in range(22, 29):
		for tx in range(3, 29):
			g_wear[wy][tx] = "#"
	var t_wear := {
		"schema": 1,
		"id": "camp:fixture-city",
		"rows": [],
		"objects": [],
		"fixtures": [],
		"people": [],
		"street_pokemon": [],
		"signs": [{"at": [10, 10], "text": "c"}],
		"lamp": [14, 14],
	}
	for r in g_wear:
		(t_wear["rows"] as Array).append("".join(r))
	var res_t3 := CaricatureCheck.check_town(CaricatureMap.compile(camp_area, t_wear), camp_area, [[4, 4, 16, 16]])
	if bool(res_t3.get("ok", true)) or not (res_t3["failed_rules"] as Array).has("T3") or float(res_t3.get("town_wear_pct", 1.0)) != 0.0 or float(res_t3.get("route_wear_pct", 0.0)) <= 0.05:
		_cleanup()
		push_error("caricature_check_test: expected T3 failure from route-ground wear alone, got %s" % str(res_t3))
		return false

	# T4 falsifier (layout-only key, distance >= 8): identical non-uniform 8x8 lawn+path/building 12 tiles apart fails T4 even across random grass shading; <8 tiles overlapping alone does not
	var t_rep := {
		"schema": 1,
		"id": "camp:fixture-city",
		"town": [[0, 0, 32, 32]],
		"rows": [],
		"objects": [
			{"stamp": "standing_block_9x9_a", "at": [4, 4]},
			{"stamp": "standing_block_9x9_a", "at": [18, 18]},
		],
		"fixtures": [],
		"people": [],
		"street_pokemon": [],
		"signs": [{"at": [27, 4], "text": "ne"}],
		"lamp": [4, 25],
	}
	for r in _blank_32_grid("."):
		(t_rep["rows"] as Array).append("".join(r))
	var res_t4 := CaricatureCheck.check_town(CaricatureMap.compile(camp_area, t_rep), camp_area)
	if bool(res_t4.get("ok", true)) or not (res_t4["failed_rules"] as Array).has("T4"):
		_cleanup()
		push_error("caricature_check_test: expected T4 failure for repeated 8x8 patch >=8 tiles apart, got %s" % str(res_t4))
		return false

	# T5 falsifier: missing interior on open door fails T5 + double-door dedup counts 1
	var t_bad_door := t_map.duplicate(true)
	(t_bad_door["objects"] as Array).append({"stamp": "standing_block_8x7_a", "at": [10, 5], "interior": "dc:camp-nonexistent-house"})
	var c_bad_door := CaricatureMap.compile(camp_area, t_bad_door)
	if not bool(c_bad_door.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: t_bad_door compile failed: %s" % str(c_bad_door.get("errors", [])))
		return false
	var res_t5 := CaricatureCheck.check_town(c_bad_door, camp_area)
	if bool(res_t5.get("ok", true)) or not (res_t5["failed_rules"] as Array).has("T5") or int(res_t5.get("open_doors", 0)) != 5 or int(res_t5.get("bad_doors", 0)) != 2:
		_cleanup()
		push_error("caricature_check_test: expected T5 fail + double-door dedup open_doors==5, got %s" % str(res_t5))
		return false

	# T6 falsifier: 16x14 block in town + invalid street_pokemon dex -> fails T6
	var t_t6 := {
		"schema": 1,
		"id": "camp:fixture-city",
		"town": [[0, 0, 32, 32]],
		"rows": [],
		"objects": [{"stamp": "ruined_block_16x14_a", "at": [5, 5]}],
		"fixtures": [],
		"people": [],
		"street_pokemon": [{"dex": 999, "at": [24, 24]}],
		"signs": [],
		"lamp": [25, 25],
	}
	for r in _blank_32_grid("."):
		(t_t6["rows"] as Array).append("".join(r))
	var res_t6 := CaricatureCheck.check_town(CaricatureMap.compile(camp_area, t_t6), camp_area)
	if bool(res_t6.get("ok", true)) or not (res_t6["failed_rules"] as Array).has("T6") or int(res_t6.get("oversized_buildings", 0)) != 1 or int(res_t6.get("invalid_pokemon", 0)) != 1:
		_cleanup()
		push_error("caricature_check_test: expected T6 fail (oversized=1, invalid_pkm=1), got %s" % str(res_t6))
		return false

	# Decision 71 falsifiers on test copies of DC maps (sign cap, item cap, non-camp/non-Georgetown town & zone pool)
	Neighbourhoods.set_config_path_for_tests("")
	var dc_camp_area := Neighbourhoods.area("camp:washington-dc")
	var dc_camp_map := CaricatureMap.load_map("res://data/caricature/washington-dc/camp.json")
	var dc_gt_area := Neighbourhoods.area("hood:washington-dc:georgetown")
	var dc_gt_map := CaricatureMap.load_map("res://data/caricature/washington-dc/georgetown.json")
	var dc_dupont_area := Neighbourhoods.area("hood:washington-dc:dupont-circle")
	var dc_dupont_map := CaricatureMap.load_map("res://data/caricature/washington-dc/dupont-circle.json")

	var camp_extra_sign := _copy_with_extra_town_thing(dc_camp_area, dc_camp_map, true, 19)
	if not bool(camp_extra_sign.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: camp_extra_sign setup failed: %s" % str(camp_extra_sign))
		return false
	var res_camp_sign := CaricatureCheck.check_town(camp_extra_sign["compiled"], dc_camp_area)
	if bool(res_camp_sign.get("ok", true)) or not (res_camp_sign["failed_rules"] as Array).has("T6") or int(res_camp_sign.get("town_signs", 0)) <= 19:
		_cleanup()
		push_error("caricature_check_test: expected camp +1 sign to fail T6 (>19), got %s" % str(res_camp_sign))
		return false

	var camp_extra_item := _copy_with_extra_town_thing(dc_camp_area, dc_camp_map, false, 8)
	var res_camp_item := CaricatureCheck.check_town(camp_extra_item["compiled"], dc_camp_area)
	if bool(res_camp_item.get("ok", true)) or not (res_camp_item["failed_rules"] as Array).has("T6") or int(res_camp_item.get("town_items", 0)) <= 8:
		_cleanup()
		push_error("caricature_check_test: expected camp +1 item to fail T6 (>8), got %s" % str(res_camp_item))
		return false

	var gt_extra_sign := _copy_with_extra_town_thing(dc_gt_area, dc_gt_map, true, 13)
	var res_gt_sign := CaricatureCheck.check_town(gt_extra_sign["compiled"], dc_gt_area)
	if bool(res_gt_sign.get("ok", true)) or not (res_gt_sign["failed_rules"] as Array).has("T6") or int(res_gt_sign.get("town_signs", 0)) <= 13:
		_cleanup()
		push_error("caricature_check_test: expected georgetown >13 signs to fail T6, got %s" % str(res_gt_sign))
		return false

	var gt_extra_item := _copy_with_extra_town_thing(dc_gt_area, dc_gt_map, false, 8)
	var res_gt_item := CaricatureCheck.check_town(gt_extra_item["compiled"], dc_gt_area)
	if bool(res_gt_item.get("ok", true)) or not (res_gt_item["failed_rules"] as Array).has("T6") or int(res_gt_item.get("town_items", 0)) <= 8:
		_cleanup()
		push_error("caricature_check_test: expected georgetown +1 item to fail T6 (>8), got %s" % str(res_gt_item))
		return false

	# Non-camp / non-Georgetown neighbourhood with a town part runs check_town AND enforces its own zone pool
	var dup_with_town := dc_dupont_map.duplicate(true)
	dup_with_town["town"] = [[24, 24, 80, 80]]
	dup_with_town["people"] = []
	dup_with_town["signs"] = []
	dup_with_town["hidden_items"] = []
	dup_with_town["street_pokemon"] = [{"dex": 562, "at": [64, 60], "zone": "ruins"}] # Yamask: ruins only, invalid for Dupont (residential/waterfront)
	var c_dup_town := CaricatureMap.compile(dc_dupont_area, dup_with_town)
	if not bool(c_dup_town.get("ok", false)) or not bool(c_dup_town.get("has_town_rules", false)):
		_cleanup()
		push_error("caricature_check_test: dup_with_town compile failed: %s" % str(c_dup_town.get("errors", [])))
		return false
	var res_dup := CaricatureCheck.check_town(c_dup_town, dc_dupont_area)
	if bool(res_dup.get("ok", true)) or not (res_dup["failed_rules"] as Array).has("T1") or not (res_dup["failed_rules"] as Array).has("T6") or int(res_dup.get("invalid_pokemon", 0)) != 1:
		_cleanup()
		push_error("caricature_check_test: expected non-camp/non-GT town check + zone-pool rejection (invalid_pokemon==1), got %s" % str(res_dup))
		return false

	# Item 63a falsifier: P11 retired blocks (standing_block_16x14_a anywhere; ruined_block_23x14_b; ruined_block_16x14_a inside town)
	var ret_map := dc_camp_map.duplicate(true)
	var ret_rows: Array = ret_map["rows"]
	var clear_line := "TTT" + ".".repeat(58) + "TTT"
	for ry in range(6, 56):
		ret_rows[ry] = clear_line
	ret_map["rows"] = ret_rows
	ret_map["lamp"] = [50, 50]
	ret_map["objects"] = [{"stamp": "standing_block_16x14_a", "at": [10, 10]}]
	ret_map["fixtures"] = []
	ret_map["people"] = []
	ret_map["signs"] = []
	ret_map["hidden_items"] = []
	var c_ret := CaricatureMap.compile(dc_camp_area, ret_map)
	if not bool(c_ret.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: ret_map compile failed: %s" % str(c_ret.get("errors", [])))
		return false
	var m_ret := CaricatureCheck.measure(c_ret, dc_camp_area)
	if not (m_ret["failed_rules"] as Array).has("P11") or int(m_ret.get("retired_blocks", 0)) < 1:
		_cleanup()
		push_error("caricature_check_test: expected standing_block_16x14_a to fail P11, got %s" % str(m_ret))
		return false

	var ret_ruin_b := ret_map.duplicate(true)
	ret_ruin_b["objects"] = [{"stamp": "ruined_block_23x14_b", "at": [10, 10]}]
	var c_ret_b := CaricatureMap.compile(dc_camp_area, ret_ruin_b)
	if not bool(c_ret_b.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: ret_ruin_b compile failed: %s" % str(c_ret_b.get("errors", [])))
		return false
	var m_ret_b := CaricatureCheck.measure(c_ret_b, dc_camp_area)
	if not (m_ret_b["failed_rules"] as Array).has("P11"):
		_cleanup()
		push_error("caricature_check_test: expected ruined_block_23x14_b to fail P11, got %s" % str(m_ret_b))
		return false

	var ret_town_a := ret_map.duplicate(true)
	ret_town_a["objects"] = [{"stamp": "ruined_block_16x14_a", "at": [10, 10]}]
	var c_ret_ta := CaricatureMap.compile(dc_camp_area, ret_town_a)
	if not bool(c_ret_ta.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: ret_town_a compile failed: %s" % str(c_ret_ta.get("errors", [])))
		return false
	var m_ret_ta := CaricatureCheck.measure(c_ret_ta, dc_camp_area)
	if not (m_ret_ta["failed_rules"] as Array).has("P11"):
		_cleanup()
		push_error("caricature_check_test: expected ruined_block_16x14_a touching town to fail P11, got %s" % str(m_ret_ta))
		return false

	# Item 63a falsifier: P12 5-tile edge clearance (item 2 tiles from edge fails P12; item 4 tiles from edge fails P12)
	var c_camp_ok := CaricatureMap.compile(dc_camp_area, dc_camp_map)
	var edge_2_compiled := c_camp_ok.duplicate(true)
	var e2_hidden: Array = (edge_2_compiled.get("hidden_items", []) as Array).duplicate(true)
	e2_hidden.append({"x": 20, "y": 2, "item": "Potion", "note": "2 tiles from north edge"})
	edge_2_compiled["hidden_items"] = e2_hidden
	var m_edge_2 := CaricatureCheck.measure(edge_2_compiled, dc_camp_area)
	if not (m_edge_2["failed_rules"] as Array).has("P12") or int(m_edge_2.get("edge_violations", 0)) < 1:
		_cleanup()
		push_error("caricature_check_test: expected item 2 tiles from map edge to fail P12, got %s" % str(m_edge_2))
		return false

	var edge_bad_ball := dc_camp_map.duplicate(true)
	var eb_rows: Array = edge_bad_ball["rows"]
	var row4: String = str(eb_rows[4])
	eb_rows[4] = row4.substr(0, 20) + "!" + row4.substr(21)
	edge_bad_ball["rows"] = eb_rows
	var c_edge_ball := CaricatureMap.compile(dc_camp_area, edge_bad_ball)
	if not bool(c_edge_ball.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: edge_bad_ball compile failed: %s" % str(c_edge_ball.get("errors", [])))
		return false
	var m_edge_ball := CaricatureCheck.measure(c_edge_ball, dc_camp_area)
	if not (m_edge_ball["failed_rules"] as Array).has("P12"):
		_cleanup()
		push_error("caricature_check_test: expected item ball 4 tiles from map edge to fail P12, got %s" % str(m_edge_ball))
		return false

	# Item 63a falsifier: check_route_ground R1 (density, sign_share > 1/3, item_share > 1/2), R2 (>13% open), R3 (>5 repeats)
	var rg_area := Neighbourhoods.area("route:washington-dc:monument-grounds#1")
	var rg_rows: Array = []
	for ry in range(64):
		if ry < 3 or ry >= 61:
			rg_rows.append("T".repeat(14) + "----" + "T".repeat(14))
		else:
			rg_rows.append("TTT" + ".".repeat(26) + "TTT")
	var rg_map := {
		"schema": 1,
		"id": "route:washington-dc:monument-grounds#1",
		"lamp": null,
		"rows": rg_rows,
		"objects": [],
		"signs": [{"at": [15, 4], "text": "North end sign"}, {"at": [15, 59], "text": "South end sign"}],
		"hidden_items": [{"at": [12, 20], "item": "Potion", "note": "x"}, {"at": [16, 30], "item": "Repel", "note": "y"}],
		"openings": [{"side": "N", "at": 14, "width": 4}, {"side": "S", "at": 14, "width": 4}],
	}
	var c_rg := CaricatureMap.compile(rg_area, rg_map)
	if not bool(c_rg.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: rg_map compile failed: %s" % str(c_rg.get("errors", [])))
		return false
	var m_rg := CaricatureCheck.measure(c_rg, rg_area)
	if (m_rg["failed_rules"] as Array).has("P12"):
		_cleanup()
		push_error("caricature_check_test: signs within 5 tiles of N/S openings should pass P12, got %s" % str(m_rg))
		return false
	var res_rg := CaricatureCheck.check_route_ground(c_rg, rg_area)
	if bool(res_rg.get("ok", true)) or not (res_rg["failed_rules"] as Array).has("R1") or not (res_rg["failed_rules"] as Array).has("R2"):
		_cleanup()
		push_error("caricature_check_test: expected open sparse route to fail R1 and R2, got %s" % str(res_rg))
		return false

	# Decision 73 falsifiers: compact town size (2500..3500 land), T8 (>=1.85/150 land), T9 (>=30% walk), TREES (<=25%), R1 door_share (<=1/3), camp unchanged
	var res_camp_d73 := CaricatureCheck.check_town(c_camp_ok, dc_camp_area)
	if not bool(res_camp_d73.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: camp:washington-dc must stay PASS under Decision 73, got %s" % str(res_camp_d73))
		return false

	# Synthetic wooded neighbourhood town: 3000 land tiles, >25% trees, <30% walkable, <1.85/150 land -> fails T8, T9, TREES
	var d73_map := dc_dupont_map.duplicate(true)
	var d73_rows: Array = (d73_map["rows"] as Array).duplicate()
	for ry in range(20, 70):
		var old_r: String = str(d73_rows[ry])
		# Keep outer border (0..2 and 125..127) untouched for openings; inside [20, 20, 60, 50]: 45 T (75% trees) + 15 . (25% walk)
		d73_rows[ry] = old_r.substr(0, 3) + ".".repeat(17) + "T".repeat(45) + ".".repeat(15) + ".".repeat(45) + old_r.substr(125)
	d73_map["rows"] = d73_rows
	d73_map["town"] = [[20, 20, 60, 50]]
	d73_map["objects"] = []
	d73_map["fixtures"] = []
	d73_map["people"] = []
	d73_map["street_pokemon"] = []
	d73_map["signs"] = [{"at": [70, 30], "text": "s1"}]
	d73_map["hidden_items"] = []
	d73_map["lamp"] = [70, 40]
	var c_d73 := CaricatureMap.compile(dc_dupont_area, d73_map)
	if not bool(c_d73.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: d73_map compile failed: %s" % str(c_d73.get("errors", [])))
		return false
	var res_d73 := CaricatureCheck.check_town(c_d73, dc_dupont_area)
	var f_d73: Array = res_d73["failed_rules"]
	if not f_d73.has("T8") or not f_d73.has("T9") or not f_d73.has("TREES"):
		_cleanup()
		push_error("caricature_check_test: expected wooded sparse 3000-land town to fail T8, T9, TREES, got %s" % str(res_d73))
		return false

	# Town land size bounds: <2500 fails T6, >3500 fails T6
	var res_small_t := CaricatureCheck.check_town(c_d73, dc_dupont_area, [[20, 20, 40, 50]])
	if not (res_small_t["failed_rules"] as Array).has("T6") or int(res_small_t.get("town_land_tiles", 0)) != 2000:
		_cleanup()
		push_error("caricature_check_test: expected 2000-land town to fail T6, got %s" % str(res_small_t))
		return false
	var res_big_t := CaricatureCheck.check_town(c_d73, dc_dupont_area, [[20, 20, 80, 50]])
	if not (res_big_t["failed_rules"] as Array).has("T6") or int(res_big_t.get("town_land_tiles", 0)) != 4000:
		_cleanup()
		push_error("caricature_check_test: expected 4000-land town to fail T6, got %s" % str(res_big_t))
		return false

	# R1 door_share falsifier: route with 4 search doors + 4 other things -> door_share=0.50 (>1/3) -> fails R1
	var rg_door_map := rg_map.duplicate(true)
	rg_door_map["objects"] = [
		{"stamp": "house_s_a", "at": [6, 12]},
		{"stamp": "house_s_b", "at": [18, 12]},
		{"stamp": "house_s_a", "at": [6, 26]},
		{"stamp": "house_s_b", "at": [18, 26]},
	]
	rg_door_map["people"] = [{"id": "t_p", "name": "Scout", "at": [14, 20], "facing": "S", "sprite": "hiker", "role": "talk", "lines": ["Hi."]}]
	rg_door_map["street_pokemon"] = [{"dex": 16, "at": [15, 22], "zone": "parkland"}]
	var c_rg_door := CaricatureMap.compile(rg_area, rg_door_map)
	if not bool(c_rg_door.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: rg_door_map compile failed: %s" % str(c_rg_door.get("errors", [])))
		return false
	var res_rg_door := CaricatureCheck.check_route_ground(c_rg_door, rg_area)
	if float(res_rg_door.get("door_share", 0.0)) <= 0.34 or not (res_rg_door["failed_rules"] as Array).has("R1"):
		_cleanup()
		push_error("caricature_check_test: expected route with door_share > 1/3 to fail R1, got %s" % str(res_rg_door))
		return false

	# Decision 74 falsifiers: P13a (<= 1 loose piece per 500 tiles), P13b (never alone), P13c (bollards <= 3 tiles from rendered water), WATER (rendered water >= 80% baseline)
	var m_camp_d74 := CaricatureCheck.measure(c_camp_ok, dc_camp_area)
	if not bool(m_camp_d74.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: camp:washington-dc must stay PASS under Decision 74, got %s" % str(m_camp_d74))
		return false

	# P13a falsifier: 5 anchored benches on a 32x64 route (limit = 4) fails P13a only
	var p13a_map := rg_map.duplicate(true)
	var p13a_rows: Array = (p13a_map["rows"] as Array).duplicate()
	p13a_rows[10] = "TTT" + "F".repeat(26) + "TTT"
	p13a_map["rows"] = p13a_rows
	p13a_map["fixtures"] = [
		{"kind": "standin_bench", "at": [4, 11]},
		{"kind": "standin_bench", "at": [8, 11]},
		{"kind": "standin_bench", "at": [12, 11]},
		{"kind": "standin_bench", "at": [16, 11]},
		{"kind": "standin_bench", "at": [20, 11]},
	]
	var c_p13a := CaricatureMap.compile(rg_area, p13a_map)
	if not bool(c_p13a.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: p13a_map compile failed: %s" % str(c_p13a.get("errors", [])))
		return false
	var m_p13a := CaricatureCheck.measure(c_p13a, rg_area)
	var f_p13a: Array = m_p13a["failed_rules"]
	if not f_p13a.has("P13a") or f_p13a.has("P13b") or f_p13a.has("P13c") or int(m_p13a.get("loose_total", 0)) != 5 or int(m_p13a.get("loose_max", 0)) != 4:
		_cleanup()
		push_error("caricature_check_test: expected 5 anchored benches on 32x64 to fail P13a only, got %s" % str(m_p13a))
		return false

	# P13b falsifier: 1 lone bench in open grass fails P13b (even though count <= 4)
	var p13b_map := rg_map.duplicate(true)
	p13b_map["fixtures"] = [{"kind": "standin_bench", "at": [14, 25]}]
	var c_p13b := CaricatureMap.compile(rg_area, p13b_map)
	if not bool(c_p13b.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: p13b_map compile failed: %s" % str(c_p13b.get("errors", [])))
		return false
	var m_p13b := CaricatureCheck.measure(c_p13b, rg_area)
	var f_p13b: Array = m_p13b["failed_rules"]
	if not f_p13b.has("P13b") or f_p13b.has("P13a") or int(m_p13b.get("loose_alone", 0)) != 1:
		_cleanup()
		push_error("caricature_check_test: expected 1 lone bench to fail P13b only, got %s" % str(m_p13b))
		return false

	# P13c falsifier: 1 bollard touching a fence but > 3 tiles from water fails P13c; a bollard within 3 tiles of water passes P13c
	var p13c_map := p13a_map.duplicate(true)
	p13c_map["fixtures"] = [{"kind": "em_bollard", "at": [10, 11]}]
	var c_p13c := CaricatureMap.compile(rg_area, p13c_map)
	var m_p13c := CaricatureCheck.measure(c_p13c, rg_area)
	var f_p13c: Array = m_p13c["failed_rules"]
	if not f_p13c.has("P13c") or f_p13c.has("P13a") or f_p13c.has("P13b") or int(m_p13c.get("bollard_far", 0)) != 1:
		_cleanup()
		push_error("caricature_check_test: expected inland fence-adjacent bollard to fail P13c only, got %s" % str(m_p13c))
		return false

	var p13c_ok_map := p13c_map.duplicate(true)
	var p13c_rows: Array = (p13c_ok_map["rows"] as Array).duplicate()
	p13c_rows[13] = str(p13c_rows[13]).substr(0, 9) + "~~~" + str(p13c_rows[13]).substr(12)
	p13c_rows[14] = str(p13c_rows[14]).substr(0, 9) + "~~~" + str(p13c_rows[14]).substr(12)
	p13c_ok_map["rows"] = p13c_rows
	var c_p13c_ok := CaricatureMap.compile(rg_area, p13c_ok_map)
	var m_p13c_ok := CaricatureCheck.measure(c_p13c_ok, rg_area)
	if (m_p13c_ok["failed_rules"] as Array).has("P13c") or int(m_p13c_ok.get("bollard_far", 1)) != 0:
		_cleanup()
		push_error("caricature_check_test: expected bollard 2 tiles from rendered water to pass P13c, got %s" % str(m_p13c_ok))
		return false

	# Rendered-tile WATER anchor falsifier: building stamp covering >20% of rendered water fails WATER even though '~' stays in raw rows
	var dc_nm_area := Neighbourhoods.area("hood:washington-dc:national-mall")
	var water_map := {
		"schema": 1,
		"id": "hood:washington-dc:national-mall",
		"rows": [],
		"openings": [],
		"objects": [{"stamp": "standing_block_8x7_a", "at": [10, 10]}],
		"fixtures": [],
		"people": [],
		"street_pokemon": [],
		"signs": [],
		"hidden_items": [],
		"lamp": [40, 40],
	}
	for ry in range(128):
		if ry < 3 or ry >= 125:
			(water_map["rows"] as Array).append("T".repeat(160))
		elif ry >= 12 and ry < 14:
			# 46 raw '~' tiles (x=10..32, 2 rows = 46), of which 16 are covered by standing_block_8x7_a at (10,10)..(17,16) -> 30/46 (65%) rendered!
			(water_map["rows"] as Array).append("TTT" + ".".repeat(7) + "~".repeat(23) + ".".repeat(124) + "TTT")
		else:
			(water_map["rows"] as Array).append("TTT" + ".".repeat(154) + "TTT")
	var c_water := CaricatureMap.compile(dc_nm_area, water_map)
	if not bool(c_water.get("ok", false)):
		_cleanup()
		push_error("caricature_check_test: water_map compile failed: %s" % str(c_water.get("errors", [])))
		return false
	var m_water := CaricatureCheck.measure(c_water, dc_nm_area)
	if not (m_water["failed_rules"] as Array).has("WATER") or int(m_water.get("rendered_water", 0)) != 30 or int(m_water.get("water_baseline", 0)) != 46:
		_cleanup()
		push_error("caricature_check_test: expected building over pond (30/46 rendered water) to fail WATER, got %s" % str(m_water))
		return false

	_cleanup()
	return true


func _copy_with_extra_town_thing(area: Dictionary, base_map: Dictionary, add_sign: bool, min_target: int) -> Dictionary:
	var m := base_map.duplicate(true)
	var c0 := CaricatureMap.compile(area, m)
	if not bool(c0.get("ok", false)):
		return {"ok": false, "error": str(c0.get("errors", []))}
	var w := int(c0["w"])
	var h := int(c0["h"])
	var town_mask: PackedByteArray = c0["town_mask"]
	var cls_buf: PackedByteArray = c0["class"]
	var var_buf: PackedByteArray = c0["variant"]
	var mask_buf: PackedByteArray = c0["mask"]
	var used: Dictionary = {}
	for s in (m.get("signs", []) as Array):
		used[Vector2i(int(s["at"][0]), int(s["at"][1]))] = true
	for hi in (m.get("hidden_items", []) as Array):
		used[Vector2i(int(hi["at"][0]), int(hi["at"][1]))] = true
	var cur_count := 0
	if add_sign:
		for s in (m.get("signs", []) as Array):
			var sx := int(s["at"][0])
			var sy := int(s["at"][1])
			if sx >= 0 and sx < w and sy >= 0 and sy < h and town_mask[sy * w + sx] == 1:
				cur_count += 1
	else:
		for y in range(h):
			for x in range(w):
				if town_mask[y * w + x] == 1 and cls_buf[y * w + x] == 28:
					cur_count += 1
		for hi in (m.get("hidden_items", []) as Array):
			var hx := int(hi["at"][0])
			var hy := int(hi["at"][1])
			if hx >= 0 and hx < w and hy >= 0 and hy < h and town_mask[hy * w + hx] == 1:
				cur_count += 1
	var needed := maxi(1, min_target + 1 - cur_count)
	var added := 0
	for y in range(4, h - 4):
		if added >= needed:
			break
		for x in range(4, w - 4):
			var idx := y * w + x
			if town_mask[idx] == 0:
				continue
			var pos := Vector2i(x, y)
			if used.has(pos):
				continue
			if cls_buf[idx] == 1 and var_buf[idx] == 0 and mask_buf[idx] == 0:
				used[pos] = true
				if add_sign:
					(m["signs"] as Array).append({"at": [x, y], "text": "extra"})
				else:
					var h_arr: Array = m.get("hidden_items", [])
					h_arr.append({"at": [x, y], "item": "Potion", "note": "extra"})
					m["hidden_items"] = h_arr
				added += 1
				if added >= needed:
					break
	var c1 := CaricatureMap.compile(area, m)
	return {"ok": bool(c1.get("ok", false)), "compiled": c1}
