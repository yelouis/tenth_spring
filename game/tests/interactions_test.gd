extends Node

## game/tests/interactions_test.gd — Item 73 DialogueBox, Signs, People, Outdoor/Hidden/Indoor Items, Street Pokemon & Hints
## Contract: docs/implementation_plan_travel_and_time.md §(d), §(e), §(h), §(n)

const MainScript := preload("res://scenes/main.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const NeighbourhoodProgress := preload("res://world/neighbourhood_progress.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
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
		iv_c.enable_walking(ic["stand"] as Vector2i, str(ic["face"]), {}, null, DB)
		iv_c.get_player_walker().live_input_enabled = false
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

	_cleanup([mv2, main2])
	return true
