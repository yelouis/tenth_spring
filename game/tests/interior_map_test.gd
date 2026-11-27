extends Node

# game/tests/interior_map_test.gd — Synthetic Fixture & I1..I6 Negative Falsifier Suite (Item 57)
# Contract: docs/implementation_plan_dc_trial.md §11.3 C–D & docs/agent_execution_guide.md §5

const InteriorTiles := preload("res://world/interior/interior_tiles.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")

const FIXTURE_PATH := "res://tests/fixtures/interior_fixture.json"

func _fail(msg: String) -> bool:
	push_error("interior_map_test: " + msg)
	return false

func _load_fixture() -> Dictionary:
	var txt := FileAccess.get_file_as_string(FIXTURE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}

func run_test() -> bool:
	var base_doc := _load_fixture()
	if base_doc.is_empty():
		return _fail("Failed to load " + FIXTURE_PATH)

	# Verify indoor tile palette 0..16 & multi-row fallback bundle (Item 61)
	if InteriorTiles.INDOOR_TILE_IDS.size() != 17:
		return _fail("Expected 17 indoor tile IDs, got %d" % InteriorTiles.INDOOR_TILE_IDS.size())
	var fb_bundle := InteriorTiles.build_fallback_bundle()
	var fb_tex: ImageTexture = fb_bundle.get("texture", null) as ImageTexture
	if fb_tex == null or fb_tex.get_width() != 17 * 32 or fb_tex.get_height() < 64 or (fb_tex.get_height() % 32) != 0:
		return _fail("Expected 544x(>=64, mult 32) fallback indoor texture, got %s" % str(fb_tex.get_size() if fb_tex != null else Vector2i.ZERO))
	var fb_img := fb_tex.get_image()
	if fb_img == null or fb_img.get_pixel(0, 0) != Color8(0, 0, 0, 255):
		return _fail("Expected class 0 void pixel (0,0) to be pure #000000, got %s" % str(fb_img.get_pixel(0, 0) if fb_img != null else Color()))

	# ------------------------------------------------------------------
	# 1. ▶ Negative Falsifiers FIRST (broken in-memory copies of fixture)
	# ------------------------------------------------------------------

	# Falsifier I1a: jagged grid row length
	var bad_i1 := base_doc.duplicate(true)
	(bad_i1["floors"][0]["grid"] as Array)[3] = "#..short..#"
	var res_i1 := InteriorCheck.compile_and_check(bad_i1)
	print("FALSIFIER_I1: " + InteriorCheck.format_summary(res_i1))
	if bool(res_i1.get("ok", true)) or not (res_i1.get("failed_rules", []) as Array).has("I1"):
		return _fail("I1 falsifier (jagged grid) should fail I1, got: %s" % str(res_i1))

	# Falsifier I1b: undersized room (< 12x10)
	var bad_i1_small := base_doc.duplicate(true)
	bad_i1_small["floors"][0]["width"] = 10
	bad_i1_small["floors"][0]["height"] = 8
	var small_rows: Array = []
	for _r in range(8):
		small_rows.append("##########")
	bad_i1_small["floors"][0]["grid"] = small_rows
	var res_i1b := InteriorCheck.compile_and_check(bad_i1_small)
	if bool(res_i1b.get("ok", true)) or not (res_i1b.get("failed_rules", []) as Array).has("I1"):
		return _fail("I1b falsifier (undersized <12x10) should fail I1, got: %s" % str(res_i1b))

	# Falsifier I2a: unknown grid character '?'
	var bad_i2 := base_doc.duplicate(true)
	(bad_i2["floors"][0]["grid"] as Array)[5] = "#.....?......#"
	var res_i2 := InteriorCheck.compile_and_check(bad_i2)
	print("FALSIFIER_I2: " + InteriorCheck.format_summary(res_i2))
	if bool(res_i2.get("ok", true)) or not (res_i2.get("failed_rules", []) as Array).has("I2"):
		return _fail("I2 falsifier (unknown token '?') should fail I2, got: %s" % str(res_i2))

	# Falsifier I2b: missing door_mat on ground floor
	var bad_i2_nodoor := base_doc.duplicate(true)
	(bad_i2_nodoor["floors"][0]["grid"] as Array)[9] = "#............#"
	(bad_i2_nodoor["floors"][0]["grid"] as Array)[10] = "#............#"
	var res_i2b := InteriorCheck.compile_and_check(bad_i2_nodoor)
	if bool(res_i2b.get("ok", true)) or not (res_i2b.get("failed_rules", []) as Array).has("I2"):
		return _fail("I2b falsifier (missing ground door_mat) should fail I2, got: %s" % str(res_i2b))

	# Falsifier I3: stair lands on non-walkable wall_top (0, 0) or missing floor
	var bad_i3 := base_doc.duplicate(true)
	bad_i3["floors"][0]["stairs"][0]["to"] = [0, 0]
	var res_i3 := InteriorCheck.compile_and_check(bad_i3)
	print("FALSIFIER_I3: " + InteriorCheck.format_summary(res_i3))
	if bool(res_i3.get("ok", true)) or not (res_i3.get("failed_rules", []) as Array).has("I3"):
		return _fail("I3 falsifier (stair landing on wall_top) should fail I3, got: %s" % str(res_i3))

	# Falsifier I4a: capstone sealed behind impassable pit_chasm ring
	var bad_i4 := base_doc.duplicate(true)
	(bad_i4["floors"][1]["grid"] as Array)[5] = "#OOOOOOOOOOOO#"
	var res_i4 := InteriorCheck.compile_and_check(bad_i4)
	print("FALSIFIER_I4: " + InteriorCheck.format_summary(res_i4))
	if bool(res_i4.get("ok", true)) or not (res_i4.get("failed_rules", []) as Array).has("I4"):
		return _fail("I4 falsifier (unreachable capstone behind pit chasm) should fail I4, got: %s" % str(res_i4))

	# Falsifier I4b: switch locked behind the very gate it opens (deadlock)
	var bad_i4_lock := base_doc.duplicate(true)
	bad_i4_lock["floors"][0]["switches"] = []
	bad_i4_lock["floors"][1]["switches"] = [{"id": "sw_vault", "at": [8, 7], "opens": ["gate_2f"]}]
	var res_i4b := InteriorCheck.compile_and_check(bad_i4_lock)
	if bool(res_i4b.get("ok", true)) or not (res_i4b.get("failed_rules", []) as Array).has("I4"):
		return _fail("I4b falsifier (switch locked behind its own gate) should fail I4, got: %s" % str(res_i4b))

	# Falsifier I5a: stamp overlaps wall_top
	var bad_i5_wall := base_doc.duplicate(true)
	(bad_i5_wall["floors"][0]["stamps"] as Array).append({"stamp": "int_supply_crate", "at": [0, 0]})
	var res_i5a := InteriorCheck.compile_and_check(bad_i5_wall)
	if bool(res_i5a.get("ok", true)) or not (res_i5a.get("failed_rules", []) as Array).has("I5"):
		return _fail("I5a falsifier (stamp overlapping wall_top) should fail I5, got: %s" % str(res_i5a))

	# Falsifier I5b: non-gating stamp blocks sole hallway pass lane
	var bad_i5_hall := base_doc.duplicate(true)
	(bad_i5_hall["floors"][1]["grid"] as Array)[4] = "######WW######"
	bad_i5_hall["floors"][1]["stamps"] = [
		{"stamp": "int_supply_crate", "at": [6, 3]},
		{"stamp": "int_radio_console", "at": [3, 6], "capstone": true},
	]
	var res_i5b := InteriorCheck.compile_and_check(bad_i5_hall)
	print("FALSIFIER_I5: " + InteriorCheck.format_summary(res_i5b))
	if bool(res_i5b.get("ok", true)) or not (res_i5b.get("failed_rules", []) as Array).has("I5"):
		return _fail("I5b falsifier (non-gating crate blocking 2-wide hallway) should fail I5, got: %s" % str(res_i5b))

	# Falsifier I6a: art_pending > 0
	var bad_i6 := base_doc.duplicate(true)
	(bad_i6["floors"][0]["stamps"] as Array).append({"stamp": "int_item_ball", "at": [4, 7], "art": "pending"})
	var res_i6 := InteriorCheck.compile_and_check(bad_i6)
	print("FALSIFIER_I6: " + InteriorCheck.format_summary(res_i6))
	if bool(res_i6.get("ok", true)) or not (res_i6.get("failed_rules", []) as Array).has("I6") or int(res_i6.get("art_pending", 0)) != 1:
		return _fail("I6 falsifier (art=pending) should fail I6 with art_pending=1, got: %s" % str(res_i6))

	# Falsifier I6b: stamp ID outside 1..134
	var bad_i6_id := base_doc.duplicate(true)
	(bad_i6_id["floors"][0]["stamps"] as Array).append({"stamp": 999, "at": [4, 7]})
	var res_i6b := InteriorCheck.compile_and_check(bad_i6_id)
	if bool(res_i6b.get("ok", true)) or not (res_i6b.get("failed_rules", []) as Array).has("I6"):
		return _fail("I6b falsifier (stamp=999) should fail I6, got: %s" % str(res_i6b))

	# Falsifier I6c: unknown kit id
	var bad_i6_kit := base_doc.duplicate(true)
	bad_i6_kit["floors"][0]["kit"] = "nonexistent_kit"
	var res_i6c := InteriorCheck.compile_and_check(bad_i6_kit)
	if bool(res_i6c.get("ok", true)) or not (res_i6c.get("failed_rules", []) as Array).has("I6"):
		return _fail("I6c falsifier (unknown kit) should fail I6, got: %s" % str(res_i6c))

	# Falsifier I6d: unknown fixture id
	var bad_i6_fx := base_doc.duplicate(true)
	bad_i6_fx["floors"][0]["fixtures"] = [{"fixture": "nonexistent_fx", "at": [3, 3]}]
	var res_i6d := InteriorCheck.compile_and_check(bad_i6_fx)
	if bool(res_i6d.get("ok", true)) or not (res_i6d.get("failed_rules", []) as Array).has("I6"):
		return _fail("I6d falsifier (unknown fixture) should fail I6, got: %s" % str(res_i6d))

	# Falsifier I5c: solid Emerald fixture blocking sole 2-wide hallway pass lane
	var bad_i5_fx := base_doc.duplicate(true)
	(bad_i5_fx["floors"][1]["grid"] as Array)[4] = "######WW######"
	bad_i5_fx["floors"][1]["stamps"] = [
		{"stamp": "int_radio_console", "at": [3, 6], "capstone": true},
	]
	bad_i5_fx["floors"][1]["fixtures"] = [
		{"fixture": "em_bookshelf_2x2", "at": [6, 3]},
	]
	var res_i5c := InteriorCheck.compile_and_check(bad_i5_fx)
	if bool(res_i5c.get("ok", true)) or not (res_i5c.get("failed_rules", []) as Array).has("I5"):
		return _fail("I5c falsifier (solid em_bookshelf_2x2 blocking 2-wide hallway) should fail I5, got: %s" % str(res_i5c))

	# Item 61 positive mount check: base_rows=0 wall painting on '#'/'=' passes I5, and gallery_wood kit emits expected layered cells
	var kit_doc := base_doc.duplicate(true)
	kit_doc["floors"][0]["kit"] = "gallery_wood"
	kit_doc["floors"][0]["grid"] = [
		"##############",
		"==========U===",
		"WWWWWWWWWWWWWW",
		"WWWWRRRRWWWWWW",
		"WWWWRRRRWWWWWW",
		"WWWWRRRRWWWWWW",
		"WWWWWWWWWWWWWW",
		"WWWWWWWWWWWWWW",
		"WWWWWWWWWWWWWW",
		"WWWWWWWWWWWWWW",
		"WWWWWWWWWWWWWW",
		"WWWWWWDDWWWWWW",
	]
	kit_doc["floors"][0]["stairs"] = [{"at": [10, 1], "to_floor": "2F", "to": [6, 3], "dir": "up"}]
	kit_doc["floors"][0]["stamps"] = [{"stamp": "int_item_ball", "at": [12, 9]}]
	kit_doc["floors"][0]["fixtures"] = [
		{"fixture": "em_painting_gold_2x2", "at": [2, 0]},
	]
	var res_kit := InteriorCheck.compile_and_check(kit_doc)
	if not bool(res_kit.get("ok", false)):
		return _fail("Item 61 wall-mounted fixture + gallery_wood kit test failed: %s" % str(res_kit))
	var kit_fd: Dictionary = (res_kit["compiled"] as Dictionary)["floors"][0]
	var gw_def: Dictionary = (fb_bundle["kits"] as Dictionary)["gallery_wood"]
	var resolved_kit := InteriorTiles.resolve_kit_cells(kit_fd, gw_def)
	var base_map: Dictionary = {}
	for bc in (resolved_kit["base"] as Array):
		var bcd := bc as Dictionary
		base_map[bcd["pos"] as Vector2i] = bcd["atlas"] as Vector2i
	if base_map[Vector2i(1, 0)] == base_map[Vector2i(1, 1)]:
		return _fail("gallery_wood wall_upper and wall_lower should use distinct atlas cells")
	if base_map[Vector2i(1, 2)] == base_map[Vector2i(1, 3)]:
		return _fail("gallery_wood floor_shadow_n at y=2 and open floor at y=3 should use distinct atlas cells")
	if (resolved_kit["overlay"] as Array).size() != 12:
		return _fail("Expected 12 9-slice rug overlay cells for 4x3 rug, got %d" % (resolved_kit["overlay"] as Array).size())

	# ------------------------------------------------------------------
	# 2. ▶ Valid Fixture Compilation & I1..I7 PASS
	# ------------------------------------------------------------------
	var res_ok := InteriorCheck.compile_and_check(base_doc)
	print("VALID_FIXTURE: " + InteriorCheck.format_summary(res_ok))
	if not bool(res_ok.get("ok", false)):
		return _fail("Valid fixture failed I1..I7: %s" % str(res_ok))
	if int(res_ok.get("floors", 0)) != 2 or int(res_ok.get("stamps", 0)) != 6 or int(res_ok.get("art_pending", -1)) != 0:
		return _fail("Unexpected valid fixture counts: %s" % str(res_ok))

	# ------------------------------------------------------------------
	# 3. ▶ Item 80 / F99 Live-Rules I7 Falsifiers (synthetic + 5c6b2f2 74-tile check)
	# ------------------------------------------------------------------
	# Falsifier I7a: one-way gust drops into pocket whose only return goes through clearable rubble.
	# Under I4 (allow_clearable=true), rubble is ignored; under I7 (live rules, rubble stays solid),
	# the pocket is live-reachable and trapped before relaunch!
	var bad_i7 := base_doc.duplicate(true)
	bad_i7["floors"][0]["grid"] = [
		"##############",
		"==========U===",
		"#............#",
		"#..#####.....#",
		"#..#...#.....#",
		"#..>...#.....#",
		"#..#.###.....#",
		"#..#.#.......#",
		"#............#",
		"#......DD....#",
		"#......DD....#",
		"##############",
	]
	bad_i7["floors"][0]["stamps"] = [
		{"stamp": "int_smash_rubble", "at": [4, 6], "clearable": true},
		{"stamp": "int_item_ball", "at": [11, 8]},
	]
	var res_i7a := InteriorCheck.compile_and_check(bad_i7)
	print("FALSIFIER_I7: " + InteriorCheck.format_summary(res_i7a))
	if bool(res_i7a.get("ok", true)) or not (res_i7a.get("failed_rules", []) as Array).has("I7") or int(res_i7a.get("live_trapped_before", 0)) <= 0:
		return _fail("I7a falsifier (one-way gust behind solid rubble) should fail I7 with live_trapped_before > 0, got: %s" % str(res_i7a))
	if (res_i7a.get("failed_rules", []) as Array).has("I4"):
		return _fail("I7a falsifier should pass I4 (rubble treated clearable) while failing I7, got: %s" % str(res_i7a))

	# Falsifier I7b: without gate persistence (5c6b2f2 behavior), exact 74 tiles trap the player
	# across DC's 94 interiors (Monument 12, Lincoln 26, Georgetown Ruins 18, Woodley Vet 18);
	# with gate persistence (Item 80), 0 tiles trap before or after relaunch.
	var expected_5c6b2f2 := {
		"dc:washington-monument": 12,
		"dc:lincoln-memorial": 26,
		"dc:georgetown-ruins": 18,
		"dc:woodley-vet": 18,
	}
	var total_nonpersist := 0
	var dc_paths := InteriorMap.list_all_dc_interior_paths()
	if dc_paths.size() != 94:
		return _fail("Expected 94 DC interior paths for I7 check, got %d" % dc_paths.size())
	for dp in dc_paths:
		var ddoc := InteriorMap.load_json(dp)
		var dcomp := InteriorMap.compile(ddoc)
		var did := str(dcomp.get("id", ""))
		var r_old := InteriorCheck.check_live_return(dcomp, false)
		var r_new := InteriorCheck.check_live_return(dcomp, true)
		var exp_n := int(expected_5c6b2f2.get(did, 0))
		if int(r_old.get("trapped_after", -1)) != exp_n or int(r_old.get("trapped_before", -1)) != 0:
			return _fail("I7b (5c6b2f2 non-persist) mismatch on %s: expected 0/%d, got %d/%d" % [
				did, exp_n, int(r_old.get("trapped_before", -1)), int(r_old.get("trapped_after", -1))
			])
		total_nonpersist += int(r_old.get("trapped_after", 0))
		if int(r_new.get("trapped_before", -1)) != 0 or int(r_new.get("trapped_after", -1)) != 0:
			return _fail("I7b (Item 80 persist) failed on %s: got %d/%d" % [
				did, int(r_new.get("trapped_before", -1)), int(r_new.get("trapped_after", -1))
			])
	if total_nonpersist != 74:
		return _fail("I7b expected exact 74 trapped tiles under 5c6b2f2 non-persist rules, got %d" % total_nonpersist)

	# ------------------------------------------------------------------
	# 4. ▶ Item 81 / F100 Rule I8 Falsifiers (every indoor item has non-empty "name")
	# ------------------------------------------------------------------
	var bad_i8_key := base_doc.duplicate(true)
	bad_i8_key["floors"][0]["items"] = [{"at": [11, 8], "item": "Full Heal"}]
	var res_i8a := InteriorCheck.compile_and_check(bad_i8_key)
	print("FALSIFIER_I8a: " + InteriorCheck.format_summary(res_i8a))
	if bool(res_i8a.get("ok", true)) or not (res_i8a.get("failed_rules", []) as Array).has("I8"):
		return _fail("I8a falsifier (item key instead of name) should fail I8, got: %s" % str(res_i8a))

	var bad_i8_empty := base_doc.duplicate(true)
	bad_i8_empty["floors"][0]["items"] = [{"at": [11, 8], "name": "   "}]
	var res_i8b := InteriorCheck.compile_and_check(bad_i8_empty)
	if bool(res_i8b.get("ok", true)) or not (res_i8b.get("failed_rules", []) as Array).has("I8"):
		return _fail("I8b falsifier (blank name) should fail I8, got: %s" % str(res_i8b))

	var total_dc_indoor_items := 0
	for dp8 in dc_paths:
		var ddoc8 := InteriorMap.load_json(dp8)
		var r8 := InteriorCheck.compile_and_check(ddoc8)
		if not bool(r8.get("ok", false)):
			return _fail("I8 failed on DC interior %s: %s" % [dp8, str(r8)])
		for fl8 in (ddoc8.get("floors", []) as Array):
			for it8 in ((fl8 as Dictionary).get("items", []) as Array):
				total_dc_indoor_items += 1
				var nm8 := str((it8 as Dictionary).get("name", "")).strip_edges()
				if nm8.is_empty():
					return _fail("DC interior %s has item with empty name: %s" % [dp8, str(it8)])
	if total_dc_indoor_items != 50:
		return _fail("Expected 50 DC indoor items checked by I8, got %d" % total_dc_indoor_items)

	# ------------------------------------------------------------------
	# 5. ▶ Item 86 / F111 Rule I9 Falsifiers (every indoor person has non-empty "text" array)
	# ------------------------------------------------------------------
	var bad_i9_missing := base_doc.duplicate(true)
	(bad_i9_missing["floors"][0]["npcs"][0] as Dictionary).erase("text")
	var res_i9a := InteriorCheck.compile_and_check(bad_i9_missing)
	print("FALSIFIER_I9a: " + InteriorCheck.format_summary(res_i9a))
	if bool(res_i9a.get("ok", true)) or not (res_i9a.get("failed_rules", []) as Array).has("I9"):
		return _fail("I9a falsifier (missing text) should fail I9, got: %s" % str(res_i9a))

	var bad_i9_blank := base_doc.duplicate(true)
	bad_i9_blank["floors"][0]["npcs"][0]["text"] = ["   "]
	var res_i9b := InteriorCheck.compile_and_check(bad_i9_blank)
	if bool(res_i9b.get("ok", true)) or not (res_i9b.get("failed_rules", []) as Array).has("I9"):
		return _fail("I9b falsifier (blank text entry) should fail I9, got: %s" % str(res_i9b))

	var total_dc_indoor_npcs := 0
	for dp9 in dc_paths:
		var ddoc9 := InteriorMap.load_json(dp9)
		for fl9 in (ddoc9.get("floors", []) as Array):
			for npc9 in ((fl9 as Dictionary).get("npcs", []) as Array):
				total_dc_indoor_npcs += 1
				var tv9: Variant = (npc9 as Dictionary).get("text", null)
				if not (tv9 is Array) or (tv9 as Array).is_empty():
					return _fail("DC interior %s has NPC without text: %s" % [dp9, str(npc9)])
	if total_dc_indoor_npcs != 25:
		return _fail("Expected 25 DC indoor NPCs checked by I9, got %d" % total_dc_indoor_npcs)

	return true
