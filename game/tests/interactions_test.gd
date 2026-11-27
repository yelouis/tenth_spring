extends Node

## game/tests/interactions_test.gd — Item 73 DialogueBox, Signs, People, Outdoor/Hidden/Indoor Items, Street Pokemon & Hints
## Contract: docs/implementation_plan_travel_and_time.md §(d), §(e), §(h), §(n)

const MainScript := preload("res://scenes/main.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")

const TEST_DB_PATH: String = "user://test/interactions_test.db"
const TEST_TMP_PATH: String = "user://test/interactions_test.db.tmp"
const TEST_NAMES_CACHE_DIR: String = "user://test/interactions_names_cache"
const TEST_NAMES_EMPTY_DIR: String = "user://test/interactions_names_empty"

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
	var names_json := ProjectSettings.globalize_path(TEST_NAMES_CACHE_DIR + "/text/en/species.json")
	if FileAccess.file_exists(names_json):
		DirAccess.remove_absolute(names_json)
	AssetDB.clear_memory_cache()
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

	# 6. Street Pokemon (Item 79 / F97): check real species name from a test names file in user://test
	#    mapping dex 10 -> "Testmon", plus fallback "#010" when data cache has no names file.
	var sp10 := {}
	for sp_v in nm_comp.get("street_pokemon", []):
		if sp_v is Dictionary and int((sp_v as Dictionary).get("dex", 0)) == 10:
			sp10 = sp_v
			break
	if sp10.is_empty():
		push_error("FAIL [F97]: No dex 10 street Pokemon found on National Mall")
		_cleanup([mv, main_node])
		return false
	var sp10_pos := Vector2i(int(sp10["x"]), int(sp10["y"]))
	var sp10_nb := _find_standable_neighbor(grid, "hood:washington-dc:national-mall", sp10_pos)
	var test_en_dir := ProjectSettings.globalize_path(TEST_NAMES_CACHE_DIR + "/text/en")
	DirAccess.make_dir_recursive_absolute(test_en_dir)
	var nf := FileAccess.open(test_en_dir.path_join("species.json"), FileAccess.WRITE)
	if nf == null:
		push_error("FAIL [F97]: Could not write test species.json")
		_cleanup([mv, main_node])
		return false
	nf.store_string("{\"10\": \"Testmon\"}\n")
	nf.close()
	AssetDB.clear_memory_cache()
	mv.set_data_cache_dir(TEST_NAMES_CACHE_DIR)
	mv.place_player_in_area("hood:washington-dc:national-mall", sp10_nb["stand"], sp10_nb["facing"])
	mv.trigger_interact_for_walker()
	if dlg.current_text() != "A wild Testmon watches you quietly.":
		push_error("FAIL [F97]: Street Pokemon line with test names file wrong: expected 'A wild Testmon watches you quietly.', got '%s'" % dlg.current_text())
		_cleanup([mv, main_node])
		return false
	dlg.close()
	# Fallback check when data pack is absent
	mv.set_data_cache_dir(TEST_NAMES_EMPTY_DIR)
	mv.trigger_interact_for_walker()
	if dlg.current_text() != "A wild #010 watches you quietly.":
		push_error("FAIL [F97]: Street Pokemon fallback line wrong: expected 'A wild #010 watches you quietly.', got '%s'" % dlg.current_text())
		_cleanup([mv, main_node])
		return false
	dlg.close()
	mv.set_data_cache_dir(AssetDB.DEFAULT_CACHE_DIR)

	# 7. Water / HM / ordinary-door hint test (Decision 82 / Item 81 / F101 exact strings)
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
					if dlg.current_text() == "The water is deep here. You'd need a way across.":
						found_water_hint = true
					dlg.close()
					break
		if found_water_hint:
			break
	if not found_water_hint:
		push_error("FAIL [F101]: Facing water did not show exact F101 water line")
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

	# 10. Item 81 / F101: All outdoor obstacle & locked-door exact strings across DC
	var dlg2: Control = mv2.get_dialogue_box()
	var grid2: CaricatureWalkerGrid = mv2.get_walker_grid()
	var f101_targets := {
		TileSynth2.TILE_CUT_TREE: "Tangled brush blocks the path. Something sharp could clear it.",
		TileSynth2.TILE_SMASH_ROCK: "A cracked rock blocks the path. A strong blow could break it.",
		TileSynth2.TILE_BOULDER: "A heavy boulder blocks the way. It won't move by hand.",
		TileSynth2.TILE_DOOR: "The door is locked.",
	}
	var f101_seen := {}
	for aid_v in mv2._caricature_compiled_by_area.keys():
		var aid_s := str(aid_v)
		var comp_s: Dictionary = mv2._caricature_compiled_by_area[aid_v]
		var sw_s := int(comp_s["w"])
		var sh_s := int(comp_s["h"])
		var cls_s: PackedByteArray = comp_s["class"]
		for ty_s in range(sh_s):
			for tx_s in range(sw_s):
				var tc: int = cls_s[ty_s * sw_s + tx_s]
				if not f101_targets.has(tc) or f101_seen.has(tc):
					continue
				if tc == TileSynth2.TILE_DOOR:
					var has_int := false
					for dv_s in comp_s.get("doors", []):
						if dv_s is Dictionary and int((dv_s as Dictionary).get("x", -1)) == tx_s and int((dv_s as Dictionary).get("y", -1)) == ty_s and not str((dv_s as Dictionary).get("interior", "")).is_empty():
							has_int = true
							break
					if has_int:
						continue
				var nb_s := _find_standable_neighbor(grid2, aid_s, Vector2i(tx_s, ty_s))
				if nb_s.is_empty():
					continue
				mv2.place_player_in_area(aid_s, nb_s["stand"], nb_s["facing"])
				if not mv2.trigger_interact_for_walker() or dlg2.current_text() != str(f101_targets[tc]):
					push_error("FAIL [F101]: Tile class %d in %s gave '%s', expected '%s'" % [tc, aid_s, dlg2.current_text(), str(f101_targets[tc])])
					_cleanup([mv2, main2])
					return false
				dlg2.close()
				f101_seen[tc] = true
			if f101_seen.size() == f101_targets.size():
				break
		if f101_seen.size() == f101_targets.size():
			break
	if f101_seen.size() != f101_targets.size():
		push_error("FAIL [F101]: Only verified %d/%d obstacle/door classes: %s" % [f101_seen.size(), f101_targets.size(), str(f101_seen.keys())])
		_cleanup([mv2, main2])
		return false

	# 11. Item 81 / F102: All 8 neighbourhood notice boards, 3 indoor rubble, 2 indoor boulders & 6 goal pieces
	var all_dc_hoods := [
		"hood:washington-dc:national-mall",
		"hood:washington-dc:tidal-basin",
		"hood:washington-dc:dupont-circle",
		"hood:washington-dc:capitol-hill",
		"hood:washington-dc:union-station",
		"hood:washington-dc:georgetown",
		"hood:washington-dc:woodley-park",
		"hood:washington-dc:lincoln-memorial",
	]
	for haid in all_dc_hoods:
		var hcomp: Dictionary = mv2._caricature_compiled_by_area[haid]
		var board_hit := false
		for st_v in hcomp.get("stamps", []):
			if st_v is Dictionary:
				var sid_b := int((st_v as Dictionary).get("stamp_id", -1))
				if str(TileSynth2.get_stamp_def(sid_b).get("id", "")) == "waypost_board":
					var al := CaricatureWalkerGrid.global_to_local(hcomp, int((st_v as Dictionary)["anchor_gx"]), int((st_v as Dictionary)["anchor_gy"]))
					var bnb := _find_standable_neighbor(grid2, haid, Vector2i(al.x, al.y + 1))
					if bnb.is_empty():
						bnb = _find_standable_neighbor(grid2, haid, Vector2i(al.x + 1, al.y + 1))
					mv2.place_player_in_area(haid, bnb["stand"], bnb["facing"])
					var hood_d: Dictionary = Neighbourhoods.area(haid)
					var exp_board := "%s notice board — Types: %s · Night: %s · Pays: %s." % [
						str(hood_d.get("name", "")),
						str(NeighbourhoodProgress.ZONE_CARD_TYPES.get(str(hood_d.get("zone", "residential")), "Normal")),
						NeighbourhoodProgress.night_danger(hood_d),
						str((hood_d.get("main_quest", {}) as Dictionary).get("pays", "")),
					]
					if not mv2.trigger_interact_for_walker() or dlg2.current_text() != exp_board:
						push_error("FAIL [F102]: Board in %s gave '%s', expected '%s'" % [haid, dlg2.current_text(), exp_board])
						_cleanup([mv2, main2])
						return false
					dlg2.close()
					board_hit = true
					break
		if not board_hit:
			push_error("FAIL [F102]: No waypost_board found in %s" % haid)
			_cleanup([mv2, main2])
			return false

	# 11b. All 5 indoor rubble/boulders + all 6 capstones (11 indoor stamp targets)
	var indoor_stamp_cases := [
		{"iid": "dc:air-and-space", "fl": 0, "stand": Vector2i(5, 7), "face": "E", "exp": "A cracked rock blocks the path. A strong blow could break it."},
		{"iid": "dc:georgetown-ruins", "fl": 0, "stand": Vector2i(13, 7), "face": "E", "exp": "A cracked rock blocks the path. A strong blow could break it."},
		{"iid": "dc:lincoln-memorial", "fl": 1, "stand": Vector2i(11, 10), "face": "E", "exp": "A cracked rock blocks the path. A strong blow could break it."},
		{"iid": "dc:washington-monument", "fl": 1, "stand": Vector2i(7, 3), "face": "E", "exp": "A heavy boulder blocks the way. It won't move by hand."},
		{"iid": "dc:lincoln-memorial", "fl": 1, "stand": Vector2i(6, 9), "face": "E", "exp": "A heavy boulder blocks the way. It won't move by hand."},
		{"iid": "dc:georgetown-ruins", "fl": 0, "stand": Vector2i(8, 2), "face": "E", "exp": "An old keystone rests on the pedestal. It hums faintly."},
		{"iid": "dc:woodley-vet", "fl": 0, "stand": Vector2i(8, 2), "face": "E", "exp": "An old keystone rests on the pedestal. It hums faintly."},
		{"iid": "dc:air-and-space", "fl": 0, "stand": Vector2i(16, 8), "face": "E", "exp": "The relay console flickers, still waiting for a signal."},
		{"iid": "dc:library-of-congress", "fl": 1, "stand": Vector2i(16, 9), "face": "E", "exp": "Coded notes cover the desk. Someone left mid-sentence."},
		{"iid": "dc:lincoln-memorial", "fl": 1, "stand": Vector2i(5, 2), "face": "E", "exp": "Hoofprints are worn deep into the stone dais."},
		{"iid": "dc:washington-monument", "fl": 2, "stand": Vector2i(8, 2), "face": "N", "exp": "Through the slit, the quiet Mall stretches out below."},
	]
	for ic in indoor_stamp_cases:
		var iv_c := InteriorView.new()
		add_child(iv_c)
		iv_c.load_interior(str(ic["iid"]), int(ic["fl"]), AssetDB.DEFAULT_CACHE_DIR, true)
		iv_c.enable_walking(Vector2i(-1, -1), "N", {}, null, DB)
		var iw_c: PlayerWalker = iv_c.get_player_walker()
		iw_c.live_input_enabled = false
		iw_c.place_at(ic["stand"] as Vector2i, str(ic["face"]), false)
		var ok_ic := iv_c.trigger_interact_for_walker()
		var got_ic: String = str(iv_c.get_dialogue_box().current_text()) if iv_c.get_dialogue_box() != null else ""
		remove_child(iv_c)
		iv_c.free()
		if not ok_ic or got_ic != str(ic["exp"]):
			push_error("FAIL [F102]: Indoor %s fl=%d stand=%s face=%s -> ok=%s got='%s' expected='%s'" % [
				str(ic["iid"]), int(ic["fl"]), str(ic["stand"]), str(ic["face"]), str(ok_ic), got_ic, str(ic["exp"])
			])
			_cleanup([mv2, main2])
			return false

	# 12. Item 81 / F100: ALL 50 DC indoor items show real names (never "Found Item!") and persist item_name in DB
	var picked_indoor := 0
	for ipath in InteriorMap.list_all_dc_interior_paths():
		var idoc := InteriorMap.load_json(ipath)
		var iid_p := str(idoc.get("id", ""))
		var fls_p: Array = idoc.get("floors", []) as Array
		for fi_p in range(fls_p.size()):
			var fl_p: Dictionary = fls_p[fi_p]
			var items_p: Array = fl_p.get("items", []) as Array
			if items_p.is_empty():
				continue
			var iv_p := InteriorView.new()
			add_child(iv_p)
			iv_p.load_interior(iid_p, fi_p, AssetDB.DEFAULT_CACHE_DIR, true)
			iv_p.enable_walking(Vector2i(-1, -1), "N", {}, null, DB)
			var iw_p: PlayerWalker = iv_p.get_player_walker()
			iw_p.live_input_enabled = false
			for it_v in items_p:
				var it_d: Dictionary = it_v
				var it_name := str(it_d.get("name", ""))
				var it_at: Vector2i = InteriorMap._parse_vec2i(it_d.get("at", null))
				if it_name.is_empty() or it_name == "Item":
					push_error("FAIL [F100]: Bad item name '%s' in %s" % [it_name, iid_p])
					remove_child(iv_p)
					iv_p.free()
					_cleanup([mv2, main2])
					return false
				# Skip if already picked up earlier in test (dc:washington-monument Metal Coat at [15,9])
				var ikey_p := InteriorView.indoor_item_key(iid_p, str(fl_p.get("floor_id", str(fi_p))), it_d)
				if not DB.is_item_collected(ikey_p):
					iw_p.place_at(Vector2i(it_at.x, it_at.y + 1), "N", false)
					if not iv_p.trigger_interact_for_walker():
						iw_p.place_at(Vector2i(it_at.x - 1, it_at.y), "E", false)
						iv_p.trigger_interact_for_walker()
					var got_nm: String = str(iv_p.get_dialogue_box().current_text())
					iv_p.get_dialogue_box().close()
					if got_nm != "Found %s!" % it_name:
						push_error("FAIL [F100]: Pickup in %s gave '%s', expected 'Found %s!'" % [iid_p, got_nm, it_name])
						remove_child(iv_p)
						iv_p.free()
						_cleanup([mv2, main2])
						return false
				# Verify DB record carries the real item_name
				var db_rows: Array = DB.get_collected_items_in_area(iid_p)
				var matched_db := false
				for dr_v in db_rows:
					if dr_v is Dictionary and str((dr_v as Dictionary).get("item_key", "")) == ikey_p and str((dr_v as Dictionary).get("item_name", "")) == it_name:
						matched_db = true
						break
				if not matched_db:
					push_error("FAIL [F100]: DB collected_item missing real item_name '%s' for key '%s'" % [it_name, ikey_p])
					remove_child(iv_p)
					iv_p.free()
					_cleanup([mv2, main2])
					return false
				picked_indoor += 1
			remove_child(iv_p)
			iv_p.free()
	if picked_indoor != 50:
		push_error("FAIL [F100]: Expected 50 DC indoor items verified, got %d" % picked_indoor)
		_cleanup([mv2, main2])
		return false

	# 13. Item 82 / F106: Collected ball at National Mall (16, 26) & ALL 136 outdoor balls + 281 signs
	#     must compute their OWN edge mask (no grass edge toward same-paving neighbors) right after pickup
	#     AND after reload, AND adjacent road/path tiles must connect seamlessly to paving balls & signs!
	var nm_comp106: Dictionary = mv2._caricature_compiled_by_area["hood:washington-dc:national-mall"]
	var g16_26 := CaricatureWalkerGrid.local_to_global(nm_comp106, 16, 26)
	var cell16_26 := CaricatureWalkerGrid.global_tile_to_cell(g16_26.x, g16_26.y)
	mv2.place_player_in_area("hood:washington-dc:national-mall", Vector2i(16, 27), "N")
	mv2._render_cell(cell16_26.x, cell16_26.y)
	if not mv2.trigger_interact_for_walker():
		push_error("FAIL [F106]: Could not collect National Mall ball at (16, 26)")
		_cleanup([mv2, main2])
		return false
	mv2.get_dialogue_box().close()
	var exp_road_15: Vector2i = mv2.get_atlas_coords(TileSynth2.TILE_ROAD, 0, 15)
	var rst16_26: Vector2i = mv2._global_to_render_tile(g16_26)
	var got_pickup_coord: Vector2i = mv2._world_cleared.get_cell_atlas_coords(rst16_26)
	if got_pickup_coord != exp_road_15:
		push_error("FAIL [F106]: Right after pickup at (16, 26) expected TILE_ROAD mask=15 (%s), got %s" % [str(exp_road_15), str(got_pickup_coord)])
		_cleanup([mv2, main2])
		return false
	# Reload MapViewer and confirm _blit_cell also draws TILE_ROAD mask=15!
	remove_child(mv2)
	mv2.free()
	main2.free()
	var main3: Node2D = MainScript.new()
	var mv3: Node = main3.distort_to_place("city:washington-dc", true, self)
	mv3.get_player_walker().live_input_enabled = false
	mv3.place_player_in_area("hood:washington-dc:national-mall", Vector2i(16, 27), "N")
	mv3._render_cell(cell16_26.x, cell16_26.y)
	var got_relaunch_coord: Vector2i = mv3._world_cleared.get_cell_atlas_coords(mv3._global_to_render_tile(g16_26))
	if got_relaunch_coord != exp_road_15:
		push_error("FAIL [F106]: After relaunch at (16, 26) expected TILE_ROAD mask=15 (%s), got %s" % [str(exp_road_15), str(got_relaunch_coord)])
		_cleanup([mv3, main3])
		return false

	# Verify ALL 136 outdoor balls (collected) and ALL 281 signs across ALL 21 DC areas!
	var checked_balls_106 := 0
	var checked_signs_106 := 0
	for aid_v106 in mv3._caricature_compiled_by_area.keys():
		var aid106 := str(aid_v106)
		var comp106: Dictionary = mv3._caricature_compiled_by_area[aid_v106]
		var area106: Dictionary = Neighbourhoods.area(aid106)
		var w106 := int(comp106["w"])
		var h106 := int(comp106["h"])
		var cls106: PackedByteArray = comp106["class"]
		var cell_buf_cache: Dictionary = {}
		for ly106 in range(h106):
			for lx106 in range(w106):
				var tcls106: int = cls106[ly106 * w106 + lx106]
				if tcls106 != TileSynth2.TILE_ITEM_BALL and tcls106 != TileSynth2.TILE_SIGN:
					continue
				if tcls106 == TileSynth2.TILE_ITEM_BALL:
					checked_balls_106 += 1
				else:
					checked_signs_106 += 1
				var gpos106 := CaricatureWalkerGrid.local_to_global(comp106, lx106, ly106)
				var cpos106 := CaricatureWalkerGrid.global_tile_to_cell(gpos106.x, gpos106.y)
				if not cell_buf_cache.has(cpos106):
					cell_buf_cache[cpos106] = CaricatureMap.cell_result(comp106, cpos106, area106)["tiles"]
				var tbuf106: PackedByteArray = cell_buf_cache[cpos106]
				var tx106 := posmod(gpos106.x, 32)
				var ty106 := posmod(gpos106.y, 32)
				var res106: Vector2i = mv3._paving_under_tile(cpos106.x, cpos106.y, tx106, ty106, tbuf106)
				if res106.x < 0:
					continue
				var pave_cls := res106.x
				var own_mask := res106.y
				var fam := TileSynth2._get_mask_family(pave_cls)
				var dir_specs := [
					[Vector2i(0, -1), 1, 4],
					[Vector2i(1, 0), 2, 8],
					[Vector2i(0, 1), 4, 1],
					[Vector2i(-1, 0), 8, 2],
				]
				for ds in dir_specs:
					var dv: Vector2i = ds[0]
					var my_bit: int = int(ds[1])
					var nb_bit: int = int(ds[2])
					var nlx := lx106 + dv.x
					var nly := ly106 + dv.y
					if nlx < 0 or nlx >= w106 or nly < 0 or nly >= h106:
						continue
					var n_eff: int = mv3._effective_class_in_compiled(comp106, nlx, nly, true)
					# 1. Own tile must NOT have a grass edge (bit 0) toward a same-family neighbor
					if not fam.is_empty() and (n_eff in fam) and (own_mask & my_bit) == 0:
						push_error("FAIL [F106]: %s (%d,%d) cls=%d pave=%d mask=%d missing bit %d toward neighbor cls=%d" % [
							aid106, lx106, ly106, tcls106, pave_cls, own_mask, my_bit, n_eff
						])
						_cleanup([mv3, main3])
						return false
					# 2. Synthesized cardinal neighbor (ROAD/PATH) must NOT have a grass edge toward this paving ball/sign
					var n_raw: int = cls106[nly * w106 + nlx]
					if n_raw == TileSynth2.TILE_ROAD or n_raw == TileSynth2.TILE_PATH:
						var nfam := TileSynth2._get_mask_family(n_raw)
						if pave_cls in nfam:
							var ngp := CaricatureWalkerGrid.local_to_global(comp106, nlx, nly)
							var ncell := CaricatureWalkerGrid.global_tile_to_cell(ngp.x, ngp.y)
							if not cell_buf_cache.has(ncell):
								cell_buf_cache[ncell] = CaricatureMap.cell_result(comp106, ncell, area106)["tiles"]
							var nbuf: PackedByteArray = cell_buf_cache[ncell]
							var nmask: int = nbuf[(posmod(ngp.y, 32) * 32 + posmod(ngp.x, 32)) * 3 + 2]
							if (nmask & nb_bit) == 0:
								push_error("FAIL [F106]: Neighbor (%d,%d) of %s (%d,%d) has grass edge (mask=%d missing bit %d) toward paving class %d" % [
									nlx, nly, aid106, lx106, ly106, nmask, nb_bit, pave_cls
								])
								_cleanup([mv3, main3])
								return false
	if checked_balls_106 != 136 or checked_signs_106 != 281:
		push_error("FAIL [F106]: Expected 136 balls and 281 signs checked, got %d balls and %d signs" % [checked_balls_106, checked_signs_106])
		_cleanup([mv3, main3])
		return false

	# 14. Item 83 / F108: Every uncollected outdoor ball (136) and sign (281) across all 21 DC areas
	#     must draw its surrounding ground class & mask on the World layer (in both ROM and --no-rom modes),
	#     and draw its sprite on _stamp_base_layer (balls use stamp 110 int_item_ball and disappear on pickup).
	#     Reuse mv3 (zero extra distort_to_place allocations) so godot_selftest stays well under its 0.5 GiB cap.
	for a_open in Neighbourhoods.areas_of("city:washington-dc"):
		var aid_o := str((a_open as Dictionary).get("id", ""))
		if aid_o != "camp:washington-dc":
			DB.upsert_neighbourhood_state(aid_o, "city:washington-dc", 2, "pick", 1)
	for r_open in Neighbourhoods.routes_of("city:washington-dc"):
		DB.upsert_neighbourhood_state(str((r_open as Dictionary).get("id", "")), "city:washington-dc", 2, "route", 1)

	var f108_any_failed := false
	var prev_ov_layer: Node = mv3._overview_layer
	mv3._overview_layer = null
	for mode_no_rom in [false, true]:
		mv3.get_walker_grid()._collected_ball_keys.clear()
		mv3._synth_cache.clear()
		mv3.set_force_no_rom(mode_no_rom)
		var f108_balls_wrong_total := 0
		var f108_balls_wrong_nongrass := 0
		var f108_balls_paving := 0
		var f108_balls_tall_grass := 0
		var f108_balls_other := 0
		var f108_signs_wrong_total := 0
		var f108_signs_tall_grass := 0
		var f108_signs_paving := 0
		var f108_signs_other := 0
		var f108_checked_balls := 0
		var f108_checked_signs := 0
		var f108_rendered_cells: Dictionary = {}

		for aid_v in mv3._caricature_compiled_by_area.keys():
			var aid4 := str(aid_v)
			var comp4: Dictionary = mv3._caricature_compiled_by_area[aid_v]
			var area4: Dictionary = Neighbourhoods.area(aid4)
			var w4 := int(comp4["w"])
			var h4 := int(comp4["h"])
			var cls4: PackedByteArray = comp4["class"]
			for ly4 in range(h4):
				for lx4 in range(w4):
					var tcls4: int = cls4[ly4 * w4 + lx4]
					if tcls4 != TileSynth2.TILE_ITEM_BALL and tcls4 != TileSynth2.TILE_SIGN:
						continue
					var gpos4 := CaricatureWalkerGrid.local_to_global(comp4, lx4, ly4)
					var cpos4 := CaricatureWalkerGrid.global_tile_to_cell(gpos4.x, gpos4.y)
					if not f108_rendered_cells.has(cpos4):
						var cr4: Dictionary = CaricatureMap.cell_result(comp4, cpos4, area4)
						mv3._blit_cell(cpos4.x, cpos4.y, {
							"buf": cr4["tiles"],
							"under_buf": cr4.get("under_tiles", PackedByteArray()),
							"reveal_state": 2,
							"has_data": true,
							"stamps": [],
							"fixtures": [],
							"people": [],
							"street_pokemon": [],
						})
						f108_rendered_cells[cpos4] = true
					var exp_gnd: Vector2i = _expected_ground_under_object(comp4, lx4, ly4)
					var exp_coord: Vector2i = mv3.get_atlas_coords(exp_gnd.x, 0, exp_gnd.y)
					var rst4: Vector2i = mv3._global_to_render_tile(gpos4)
					var got_coord: Vector2i = mv3._world_cleared.get_cell_atlas_coords(rst4)
					if got_coord == Vector2i(-1, -1):
						got_coord = mv3._world_known.get_cell_atlas_coords(rst4)
					if tcls4 == TileSynth2.TILE_ITEM_BALL:
						f108_checked_balls += 1
						if got_coord != exp_coord:
							f108_balls_wrong_total += 1
							if exp_gnd.x != TileSynth2.TILE_GRASS:
								f108_balls_wrong_nongrass += 1
								if TileSynth2.is_paving_class(exp_gnd.x) and exp_gnd.x != TileSynth2.TILE_SAND:
									f108_balls_paving += 1
								elif exp_gnd.x == TileSynth2.TILE_TALL_GRASS:
									f108_balls_tall_grass += 1
								else:
									f108_balls_other += 1
						elif not mv3._ball_sprites_by_global.has(gpos4):
							push_error("FAIL [F108 no_rom=%s]: Missing ball sprite at %s (%d,%d)" % [str(mode_no_rom), aid4, lx4, ly4])
							f108_any_failed = true
					else:
						f108_checked_signs += 1
						if got_coord != exp_coord:
							f108_signs_wrong_total += 1
							if exp_gnd.x == TileSynth2.TILE_TALL_GRASS:
								f108_signs_tall_grass += 1
							elif TileSynth2.is_paving_class(exp_gnd.x):
								f108_signs_paving += 1
							else:
								f108_signs_other += 1
			for c_spr_arr in mv3._cell_stamp_sprites.values():
				for sp_node in (c_spr_arr as Array):
					if is_instance_valid(sp_node):
						if sp_node.get_parent() != null:
							sp_node.get_parent().remove_child(sp_node)
						sp_node.free()
			mv3._cell_stamp_sprites.clear()
			mv3._ball_sprites_by_global.clear()
			mv3._cell_ball_globals.clear()
			if mv3._world_cleared != null:
				mv3._world_cleared.clear()
			if mv3._world_known != null:
				mv3._world_known.clear()
			f108_rendered_cells.clear()

		if f108_checked_balls != 136 or f108_checked_signs != 281:
			push_error("FAIL [F108 no_rom=%s]: Expected 136 balls and 281 signs, got %d balls and %d signs" % [str(mode_no_rom), f108_checked_balls, f108_checked_signs])
			mv3._overview_layer = prev_ov_layer
			_cleanup([mv3, main3])
			return false
		if f108_balls_wrong_total > 0 or f108_signs_wrong_total > 0:
			push_error("FAIL [F108 no_rom=%s]: wrong_balls=%d (non_grass=%d: paving=%d tall_grass=%d other=%d), wrong_signs=%d (tall_grass=%d paving=%d other=%d)" % [
				str(mode_no_rom), f108_balls_wrong_total, f108_balls_wrong_nongrass,
				f108_balls_paving, f108_balls_tall_grass, f108_balls_other,
				f108_signs_wrong_total, f108_signs_tall_grass, f108_signs_paving, f108_signs_other
			])
			f108_any_failed = true
			continue

		# Verify pickup of National Mall (16, 26) removes the ball sprite and keeps TILE_ROAD mask=15 ground
		var nm_c4: Dictionary = mv3._caricature_compiled_by_area["hood:washington-dc:national-mall"]
		var g16: Vector2i = CaricatureWalkerGrid.local_to_global(nm_c4, 16, 26)
		var c16: Vector2i = CaricatureWalkerGrid.global_tile_to_cell(g16.x, g16.y)
		mv3.place_player_in_area("hood:washington-dc:national-mall", Vector2i(16, 27), "N")
		mv3._render_cell(c16.x, c16.y)
		if not mv3._ball_sprites_by_global.has(g16):
			push_error("FAIL [F108 no_rom=%s]: Uncollected ball sprite missing at National Mall (16, 26)" % str(mode_no_rom))
			mv3._overview_layer = prev_ov_layer
			_cleanup([mv3, main3])
			return false
		mv3._erase_collected_ball_visual(g16)
		if mv3._ball_sprites_by_global.has(g16):
			push_error("FAIL [F108 no_rom=%s]: Ball sprite still tracked after pickup at (16, 26)" % str(mode_no_rom))
			mv3._overview_layer = prev_ov_layer
			_cleanup([mv3, main3])
			return false
		var after_pick_coord: Vector2i = mv3._world_cleared.get_cell_atlas_coords(mv3._global_to_render_tile(g16))
		if after_pick_coord != mv3.get_atlas_coords(TileSynth2.TILE_ROAD, 0, 15):
			push_error("FAIL [F108 no_rom=%s]: Ground after pickup at (16, 26) got %s, expected road mask=15" % [str(mode_no_rom), str(after_pick_coord)])
			mv3._overview_layer = prev_ov_layer
			_cleanup([mv3, main3])
			return false

	mv3._overview_layer = prev_ov_layer

	# 15. Item 86 / F111: All 25 DC indoor NPCs have unique spoken lines (across all indoor & outdoor DC people)
	#     and every page fits the 960x640 dialogue box (lines_drawn <= lines_visible).
	var line_sources: Dictionary = {} # line_text -> Array[String]
	var outdoor_people_checked := 0
	for aid_p_v in mv3._caricature_compiled_by_area.keys():
		var aid_p := str(aid_p_v)
		var comp_p: Dictionary = mv3._caricature_compiled_by_area[aid_p_v]
		for person_v in comp_p.get("people", []):
			if not (person_v is Dictionary):
				continue
			var person: Dictionary = person_v
			outdoor_people_checked += 1
			var pname := str(person.get("name", person.get("id", "Person")))
			var plines: Array = person.get("lines", []) if person.get("lines") is Array else []
			for lv in plines:
				var lt := str(lv).strip_edges()
				if lt.is_empty():
					continue
				if not line_sources.has(lt):
					line_sources[lt] = []
				(line_sources[lt] as Array).append("outdoor:%s:%s" % [aid_p, pname])

	var indoor_npcs_checked := 0
	var box_overflow_errors: Array[String] = []
	for ipath_n in InteriorMap.list_all_dc_interior_paths():
		var idoc_n := InteriorMap.load_json(ipath_n)
		var iid_n := str(idoc_n.get("id", ""))
		var fls_n: Array = idoc_n.get("floors", []) as Array
		for fi_n in range(fls_n.size()):
			var fl_n: Dictionary = fls_n[fi_n]
			var npcs_n: Array = fl_n.get("npcs", []) as Array
			if npcs_n.is_empty():
				continue
			var iv_n := InteriorView.new()
			add_child(iv_n)
			iv_n.load_interior(iid_n, fi_n, AssetDB.DEFAULT_CACHE_DIR, true)
			iv_n.enable_walking(Vector2i(-1, -1), "N", {}, null, DB)
			var iw_n: PlayerWalker = iv_n.get_player_walker()
			iw_n.live_input_enabled = false
			for npc_v in npcs_n:
				if not (npc_v is Dictionary):
					continue
				var npc_d: Dictionary = npc_v
				var n_at: Vector2i = InteriorMap._parse_vec2i(npc_d.get("at", null))
				var n_name := str(npc_d.get("name", npc_d.get("id", "NPC")))
				iw_n.place_at(Vector2i(n_at.x, n_at.y + 1), "N", false)
				var interacted := iv_n.trigger_interact_for_walker()
				var dlg_n := iv_n.get_dialogue_box()
				if not interacted or dlg_n == null or not dlg_n.is_open():
					push_error("FAIL [F111]: Could not interact with indoor NPC %s (%s fl=%d)" % [n_name, iid_n, fi_n])
					remove_child(iv_n)
					iv_n.free()
					_cleanup([mv3, main3])
					return false
				indoor_npcs_checked += 1
				var pages: Array = dlg_n.get_all_lines()
				for p_idx in range(pages.size()):
					var ptxt := str(pages[p_idx]).strip_edges()
					if not line_sources.has(ptxt):
						line_sources[ptxt] = []
					(line_sources[ptxt] as Array).append("indoor:%s:%s" % [iid_n, n_name])
					# Verify dialogue box fit at 960x640: lines_drawn <= lines_visible
					var bp := dlg_n.get_node_or_null("BoxPanel") as PanelContainer
					var bl := dlg_n.get_node_or_null("BoxPanel/Margin/VBox/BodyLabel") as Label
					if bp != null and bl != null:
						bp.size = Vector2(720.0, 116.0)
						for _pass in range(2):
							_force_layout_control_tree(bp)
						var drawn := bl.get_line_count()
						var vis := bl.get_visible_line_count()
						if drawn > vis:
							box_overflow_errors.append("%s (%s) page %d: drawn=%d > visible=%d ('%s')" % [
								n_name, iid_n, p_idx, drawn, vis, ptxt
							])
					dlg_n.advance_or_close()
			remove_child(iv_n)
			iv_n.free()

	var dup_errors: Array[String] = []
	for lt_k in line_sources.keys():
		var srcs: Array = line_sources[lt_k]
		if srcs.size() > 1:
			dup_errors.append("x%d '%s' (%s)" % [srcs.size(), str(lt_k), ", ".join(PackedStringArray(srcs))])

	if indoor_npcs_checked != 25 or outdoor_people_checked < 45:
		push_error("FAIL [F111]: Expected 25 indoor NPCs (>=45 outdoor), checked indoor=%d outdoor=%d" % [indoor_npcs_checked, outdoor_people_checked])
		_cleanup([mv3, main3])
		return false
	if not dup_errors.is_empty():
		for de in dup_errors:
			push_error("FAIL [F111]: Duplicate DC person line: " + de)
		_cleanup([mv3, main3])
		return false
	if not box_overflow_errors.is_empty():
		for oe in box_overflow_errors:
			push_error("FAIL [F111]: Dialogue box overflow: " + oe)
		_cleanup([mv3, main3])
		return false

	_cleanup([mv3, main3])
	return not f108_any_failed

func _force_layout_control_tree(n: Node) -> void:
	if n is Container:
		(n as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for ch in n.get_children():
		_force_layout_control_tree(ch)
	if n is Control:
		(n as Control).update_minimum_size()

func _is_f108_ground_class(cls: int) -> bool:
	return cls in [
		TileSynth2.TILE_GRASS,
		TileSynth2.TILE_TALL_GRASS,
		TileSynth2.TILE_SAND,
		TileSynth2.TILE_PATH,
		TileSynth2.TILE_ROAD,
		TileSynth2.TILE_BRIDGE,
		TileSynth2.TILE_PLAZA,
		TileSynth2.TILE_FLOWERS,
		TileSynth2.TILE_CROP,
	]

func _resolve_f108_ground_from_nbs(n_cls: int, e_cls: int, s_cls: int, w_cls: int) -> Vector2i:
	var pcls := TileSynth2.resolve_paving_class_from_neighbors(n_cls, e_cls, s_cls, w_cls)
	if pcls >= 0:
		return Vector2i(pcls, TileSynth2.compute_paving_mask_from_neighbors(pcls, n_cls, e_cls, s_cls, w_cls))
	var nbs := [n_cls, e_cls, s_cls, w_cls]
	var counts: Dictionary = {}
	for nc in nbs:
		if _is_f108_ground_class(nc):
			counts[nc] = int(counts.get(nc, 0)) + 1
	var best_cls := -1
	var best_cnt := 0
	for nc in nbs:
		if _is_f108_ground_class(nc):
			var cnt := int(counts.get(nc, 0))
			if cnt > best_cnt:
				best_cnt = cnt
				best_cls = nc
	if best_cls < 0:
		return Vector2i(TileSynth2.TILE_GRASS, 0)
	return Vector2i(best_cls, TileSynth2.compute_paving_mask_from_neighbors(best_cls, n_cls, e_cls, s_cls, w_cls))

func _f108_effective_cls(comp: Dictionary, lx: int, ly: int, resolve_objects: bool) -> int:
	var w := int(comp["w"])
	var h := int(comp["h"])
	if lx < 0 or lx >= w or ly < 0 or ly >= h:
		return TileSynth2.TILE_VOID
	var cls_buf: PackedByteArray = comp["class"]
	var c: int = cls_buf[ly * w + lx]
	if resolve_objects and (c == TileSynth2.TILE_ITEM_BALL or c == TileSynth2.TILE_SIGN):
		var nc := _f108_effective_cls(comp, lx, ly - 1, false)
		var ec := _f108_effective_cls(comp, lx + 1, ly, false)
		var sc := _f108_effective_cls(comp, lx, ly + 1, false)
		var wc := _f108_effective_cls(comp, lx - 1, ly, false)
		return _resolve_f108_ground_from_nbs(nc, ec, sc, wc).x
	return c

func _expected_ground_under_object(comp: Dictionary, lx: int, ly: int) -> Vector2i:
	var nc := _f108_effective_cls(comp, lx, ly - 1, true)
	var ec := _f108_effective_cls(comp, lx + 1, ly, true)
	var sc := _f108_effective_cls(comp, lx, ly + 1, true)
	var wc := _f108_effective_cls(comp, lx - 1, ly, true)
	return _resolve_f108_ground_from_nbs(nc, ec, sc, wc)
