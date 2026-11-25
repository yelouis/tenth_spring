extends Node

## game/tests/interactions_test.gd — Item 73 DialogueBox, Signs, People, Outdoor/Hidden/Indoor Items, Street Pokemon & Hints
## Contract: docs/implementation_plan_travel_and_time.md §(d), §(e), §(h), §(n)

const MainScript := preload("res://scenes/main.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")

const TEST_DB_PATH: String = "user://test/interactions_test.db"
const TEST_TMP_PATH: String = "user://test/interactions_test.db.tmp"

func _cleanup(nodes: Array = []) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _find_standable_neighbor(grid: CaricatureWalkerGrid, area_id: String, target: Vector2i) -> Dictionary:
	var checks := [
		[Vector2i(0, 1), "N"],
		[Vector2i(0, -1), "S"],
		[Vector2i(-1, 0), "E"],
		[Vector2i(1, 0), "W"],
	]
	for ch in checks:
		var d: Vector2i = ch[0]
		var stand := target + d
		if grid.is_local_tile_walkable(area_id, stand.x, stand.y):
			return {"stand": stand, "facing": str(ch[1])}
	return {}

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in interactions_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	NeighbourhoodProgress.ensure_camp(DB, "city:washington-dc")
	var now := int(Time.get_unix_time_from_system())
	DB.upsert_neighbourhood_state("hood:washington-dc:national-mall", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:dupont-circle", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("hood:washington-dc:georgetown", "city:washington-dc", 2, "pick", now)
	DB.upsert_neighbourhood_state("route:washington-dc:q-street", "city:washington-dc", 2, "route", now)
	DB.set_world_clock_minutes(1130) # 18:50 -> 10 min left (Q Street 7 min -> amber!)

	var main_node: Node2D = MainScript.new()
	var mv: Node = main_node.distort_to_place("city:washington-dc", true, self)
	if mv == null:
		push_error("FAIL: distort_to_place failed")
		_cleanup([main_node])
		return false
	var walker: PlayerWalker = mv.get_player_walker()
	walker.live_input_enabled = false
	var grid: CaricatureWalkerGrid = mv.get_walker_grid()

	# 1. Outdoor sign in camp returns exact text & pauses walker while open
	var camp_comp: Dictionary = mv._caricature_compiled_by_area["camp:washington-dc"]
	var camp_signs: Array = camp_comp.get("signs", [])
	var sg0: Dictionary = camp_signs[0]
	var sg0_pos := Vector2i(int(sg0["x"]), int(sg0["y"]))
	var sg0_nb := _find_standable_neighbor(grid, "camp:washington-dc", sg0_pos)
	if sg0_nb.is_empty():
		push_error("FAIL: No standable neighbor for camp sign %s" % str(sg0_pos))
		_cleanup([mv, main_node])
		return false
	mv.place_player_in_area("camp:washington-dc", sg0_nb["stand"], sg0_nb["facing"])
	if not mv.trigger_interact_for_walker():
		push_error("FAIL: Sign interact returned false")
		_cleanup([mv, main_node])
		return false
	var dlg: Control = mv.get_dialogue_box()
	if not dlg.is_open() or dlg.current_text() != str(sg0["text"]) or walker.input_enabled:
		push_error("FAIL: Sign dialogue wrong: open=%s text='%s' expected='%s' input_enabled=%s" % [
			str(dlg.is_open()), dlg.current_text(), str(sg0["text"]), str(walker.input_enabled)
		])
		_cleanup([mv, main_node])
		return false
	dlg.advance_or_close()
	if dlg.is_open() or not walker.input_enabled:
		push_error("FAIL: DialogueBox did not close or restore walker input")
		_cleanup([mv, main_node])
		return false

	# 2. Route sign on Q Street at 18:50 (10 min left) appends exact amber daylight walk-time line
	var q_comp: Dictionary = mv._caricature_compiled_by_area["route:washington-dc:q-street#1"]
	var q_sign := {}
	for qs_v in q_comp.get("signs", []):
		if qs_v is Dictionary and str((qs_v as Dictionary).get("text", "")) == "Q Street":
			q_sign = qs_v
			break
	if q_sign.is_empty():
		push_error("FAIL: Could not find Q Street end sign")
		_cleanup([mv, main_node])
		return false
	var qs_nb := _find_standable_neighbor(grid, "route:washington-dc:q-street#1", Vector2i(int(q_sign["x"]), int(q_sign["y"])))
	mv.place_player_in_area("route:washington-dc:q-street#1", qs_nb["stand"], qs_nb["facing"])
	mv.trigger_interact_for_walker()
	if dlg.current_text() != "Q Street" or dlg.current_extra_text() != "Q Street — 7 min on foot (one-way before dusk)":
		push_error("FAIL: Route sign daylight line wrong: text='%s' extra='%s'" % [dlg.current_text(), dlg.current_extra_text()])
		_cleanup([mv, main_node])
		return false
	dlg.close()

	# 3. Outdoor person turns to face player and pages lines[] in order
	var pe0: Dictionary = (camp_comp.get("people", []) as Array)[0]
	var pe0_pos := Vector2i(int(pe0["x"]), int(pe0["y"]))
	var pe0_nb := _find_standable_neighbor(grid, "camp:washington-dc", pe0_pos)
	mv.place_player_in_area("camp:washington-dc", pe0_nb["stand"], pe0_nb["facing"])
	mv.trigger_interact_for_walker()
	var exp_lines: Array = pe0.get("lines", [])
	if dlg.current_speaker() != str(pe0["name"]) or dlg.current_text() != str(exp_lines[0]):
		push_error("FAIL: Person dialogue wrong: speaker='%s' text='%s'" % [dlg.current_speaker(), dlg.current_text()])
		_cleanup([mv, main_node])
		return false
	if str(pe0.get("facing", "")) != mv.opposite_facing(str(pe0_nb["facing"])):
		push_error("FAIL: Outdoor person did not turn to face player: got '%s'" % str(pe0.get("facing", "")))
		_cleanup([mv, main_node])
		return false
	if exp_lines.size() > 1:
		dlg.advance_or_close()
		if dlg.current_text() != str(exp_lines[1]):
			push_error("FAIL: Person second dialogue page wrong: got '%s'" % dlg.current_text())
			_cleanup([mv, main_node])
			return false
	dlg.close()

	# 3b. Decision 81 (F91): Eli (camp_runner_eli) stands off the Waypost board at (36, 26); talking to him shows his own lines
	var eli_dict := {}
	for pe_v in camp_comp.get("people", []):
		if pe_v is Dictionary and str((pe_v as Dictionary).get("id", "")) == "camp_runner_eli":
			eli_dict = pe_v
			break
	if eli_dict.is_empty() or Vector2i(int(eli_dict["x"]), int(eli_dict["y"])) != Vector2i(36, 26):
		push_error("FAIL [F91]: Expected camp_runner_eli at (36, 26), got %s" % str(eli_dict))
		_cleanup([mv, main_node])
		return false
	var eli_nb := _find_standable_neighbor(grid, "camp:washington-dc", Vector2i(36, 26))
	if eli_nb.is_empty():
		push_error("FAIL [F91]: No standable neighbor next to Eli at (36, 26)")
		_cleanup([mv, main_node])
		return false
	mv.place_player_in_area("camp:washington-dc", eli_nb["stand"], eli_nb["facing"])
	if not mv.trigger_interact_for_walker():
		push_error("FAIL [F91]: Talking to Eli returned false")
		_cleanup([mv, main_node])
		return false
	if mv._waypost_board != null and mv._waypost_board.visible:
		push_error("FAIL [F91]: Talking to Eli opened WaypostBoard instead of his dialogue!")
		_cleanup([mv, main_node])
		return false
	if not dlg.is_open() or dlg.current_speaker() != "Eli" or dlg.current_text() != "Ran the Q Street footpath this morning. Overgrown past the bend, watch the grass.":
		push_error("FAIL [F91]: Eli dialogue wrong: speaker='%s' text='%s'" % [dlg.current_speaker(), dlg.current_text()])
		_cleanup([mv, main_node])
		return false
	dlg.close()

	# 4. Outdoor hidden item (including newly moved F82 camp Super Potion at [53, 16]!) collected once & persisted
	mv.place_player_in_area("camp:washington-dc", Vector2i(53, 16), "N")
	if not mv.trigger_interact_for_walker():
		push_error("FAIL: Hidden Super Potion at camp (53, 16) could not be collected while standing on it")
		_cleanup([mv, main_node])
		return false
	if not dlg.current_text().contains("Found a hidden Super Potion!") or not dlg.current_text().contains("northeast pine nook"):
		push_error("FAIL: Hidden item dialogue wrong: '%s'" % dlg.current_text())
		_cleanup([mv, main_node])
		return false
	dlg.close()
	# Falsifier: second interact on same hidden item must NOT collect again!
	if mv.trigger_interact_for_walker():
		push_error("FAIL [falsifier]: Hidden item was repeatable on second interact!")
		_cleanup([mv, main_node])
		return false

	# 5. Visible '!' item ball collected once, immediately becomes walkable, persists gone across reload!
	var nm_comp: Dictionary = mv._caricature_compiled_by_area["hood:washington-dc:national-mall"]
	var ball_pos := Vector2i(-1, -1)
	var nm_w := int(nm_comp["w"])
	var nm_h := int(nm_comp["h"])
	var nm_cls: PackedByteArray = nm_comp["class"]
	for by in range(nm_h):
		for bx in range(nm_w):
			if nm_cls[by * nm_w + bx] == TileSynth2.TILE_ITEM_BALL:
				var bnb := _find_standable_neighbor(grid, "hood:washington-dc:national-mall", Vector2i(bx, by))
				if not bnb.is_empty():
					ball_pos = Vector2i(bx, by)
					break
		if ball_pos.x >= 0:
			break
	if ball_pos.x < 0:
		push_error("FAIL: No reachable item ball found on National Mall")
		_cleanup([mv, main_node])
		return false
	var ball_nb := _find_standable_neighbor(grid, "hood:washington-dc:national-mall", ball_pos)
	mv.place_player_in_area("hood:washington-dc:national-mall", ball_nb["stand"], ball_nb["facing"])
	if grid.is_local_tile_walkable("hood:washington-dc:national-mall", ball_pos.x, ball_pos.y):
		push_error("FAIL: Uncollected item ball should block walking before pickup")
		_cleanup([mv, main_node])
		return false
	if not mv.trigger_interact_for_walker() or not dlg.current_text().begins_with("Found "):
		push_error("FAIL: Visible item ball pickup failed: '%s'" % dlg.current_text())
		_cleanup([mv, main_node])
		return false
	dlg.close()
	if not grid.is_local_tile_walkable("hood:washington-dc:national-mall", ball_pos.x, ball_pos.y):
		push_error("FAIL: Collected item ball did not become walkable immediately")
		_cleanup([mv, main_node])
		return false
	var ball_key := CaricatureWalkerGrid.ball_item_key("hood:washington-dc:national-mall", ball_pos.x, ball_pos.y)
	if not DB.is_item_collected(ball_key):
		push_error("FAIL: Collected item ball not persisted in collected_item")
		_cleanup([mv, main_node])
		return false
	# Second interact must NOT pick it up again!
	if mv.trigger_interact_for_walker():
		push_error("FAIL [falsifier]: Visible item ball was repeatable!")
		_cleanup([mv, main_node])
		return false

	# 6. Street Pokemon returns 1 line containing AssetDB.display_name("species", dex)
	var sp0: Dictionary = (nm_comp.get("street_pokemon", []) as Array)[0]
	var sp0_pos := Vector2i(int(sp0["x"]), int(sp0["y"]))
	var sp0_dex := int(sp0["dex"])
	var sp0_nb := _find_standable_neighbor(grid, "hood:washington-dc:national-mall", sp0_pos)
	mv.place_player_in_area("hood:washington-dc:national-mall", sp0_nb["stand"], sp0_nb["facing"])
	mv.trigger_interact_for_walker()
	var exp_sp_name := AssetDB.display_name("species", sp0_dex, "user://__no_rom__")
	if dlg.current_text() != ("A wild %s watches you quietly." % exp_sp_name):
		push_error("FAIL: Street Pokemon line wrong: expected 'A wild %s watches you quietly.', got '%s'" % [exp_sp_name, dlg.current_text()])
		_cleanup([mv, main_node])
		return false
	dlg.close()

	# 7. Water / HM / ordinary-door hint test (camp has water pond & ordinary door)
	var found_water_hint := false
	var c_w := int(camp_comp["w"])
	var c_h := int(camp_comp["h"])
	var c_cls: PackedByteArray = camp_comp["class"]
	for wy in range(c_h):
		for wx in range(c_w):
			if c_cls[wy * c_w + wx] == TileSynth2.TILE_WATER:
				var wnb := _find_standable_neighbor(grid, "camp:washington-dc", Vector2i(wx, wy))
				if not wnb.is_empty():
					mv.place_player_in_area("camp:washington-dc", wnb["stand"], wnb["facing"])
					mv.trigger_interact_for_walker()
					if dlg.current_text().contains("River Oar"):
						found_water_hint = true
					dlg.close()
					break
		if found_water_hint:
			break
	if not found_water_hint:
		push_error("FAIL: Facing water did not show River Oar hint")
		_cleanup([mv, main_node])
		return false

	# 8. Indoor sign, NPC (turns toward player), and indoor item pickup (persisted & non-repeatable across reload)
	var iv: InteriorView = main_node.enter_interior_from_map(mv, "dc:washington-monument", {
		"place_id": "city:washington-dc",
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": 33,
		"return_y": 53,
	}, 0, Vector2i(-1, -1), "N", self)
	var iw: PlayerWalker = iv.get_player_walker()
	iw.live_input_enabled = false
	# Indoor sign at [13, 3]
	iw.place_at(Vector2i(13, 4), "N")
	iv.trigger_interact_for_walker()
	var idlg: Control = iv.get_dialogue_box()
	if not idlg.current_text().contains("Memorial Dedication Stone"):
		push_error("FAIL: Indoor sign text mismatch: '%s'" % idlg.current_text())
		_cleanup([iv, mv, main_node])
		return false
	idlg.close()
	# Indoor NPC Shaft Watchman at [5, 8]
	iw.place_at(Vector2i(5, 9), "N")
	iv.trigger_interact_for_walker()
	if idlg.current_speaker() != "Shaft Watchman" or idlg.current_text().is_empty():
		push_error("FAIL: Indoor NPC dialogue mismatch: speaker='%s' text='%s'" % [idlg.current_speaker(), idlg.current_text()])
		_cleanup([iv, mv, main_node])
		return false
	idlg.close()
	# Indoor item Metal Coat at [15, 9]
	iw.place_at(Vector2i(15, 10), "N")
	if not iv.trigger_interact_for_walker() or idlg.current_text() != "Found Metal Coat!":
		push_error("FAIL: Indoor item pickup failed: '%s'" % idlg.current_text())
		_cleanup([iv, mv, main_node])
		return false
	idlg.close()
	if iv.trigger_interact_for_walker():
		push_error("FAIL [falsifier]: Indoor item pickup was repeatable!")
		_cleanup([iv, mv, main_node])
		return false
	if not iv.is_tile_passable_for_walker(15, 9):
		push_error("FAIL: Collected indoor item tile did not become passable")
		_cleanup([iv, mv, main_node])
		return false

	# 9. Reload persistence check: fresh MapViewer sees collected ball & hidden item still gone!
	main_node.exit_interior_to_map(iv, {
		"place_id": "city:washington-dc",
		"return_area_id": "hood:washington-dc:national-mall",
		"return_x": 33,
		"return_y": 53,
	})
	remove_child(mv)
	mv.free()
	main_node.free()
	DB.close()
	DB.init_db()
	var main2: Node2D = MainScript.new()
	var mv2: Node = main2.resume_from_session(true, self)
	if not mv2.get_walker_grid().is_ball_collected("hood:washington-dc:national-mall", ball_pos.x, ball_pos.y):
		push_error("FAIL [falsifier]: Collected visible item ball reappeared after reload!")
		_cleanup([mv2, main2])
		return false
	mv2.place_player_in_area("camp:washington-dc", Vector2i(53, 16), "N")
	if mv2.trigger_interact_for_walker():
		push_error("FAIL [falsifier]: Collected hidden item reappeared after reload!")
		_cleanup([mv2, main2])
		return false

	_cleanup([mv2, main2])
	return true
