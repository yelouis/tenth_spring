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

	_cleanup()
	return true
