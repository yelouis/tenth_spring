extends Node

## game/tests/player_walker_test.gd — Item 69 Walking Character, Emerald Timings & 18-Frame Sprites
## Contract: Decision 79 (F77, F78, F81); docs/implementation_plan_travel_and_time.md §(c)

const PlayerWalker := preload("res://world/player_walker.gd")
const PlayerSprites := preload("res://world/player_sprites.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const MapViewScene := preload("res://world/map_view.tscn")
const HomeHubScene := preload("res://scenes/home_hub.tscn")

const TEST_DB_PATH: String = "user://test/player_walker_test.db"
const TEST_TMP_PATH: String = "user://test/player_walker_test.db.tmp"

func _cleanup() -> void:
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func _count_opaque(img: Image) -> int:
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				n += 1
	return n

func _images_equal(a: Image, b: Image) -> bool:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return false
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in player_walker_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	# 1. Verify tuning.json / Config has exact Emerald frame counts and NO tiles-per-second keys (F78)
	var tuning_txt := FileAccess.get_file_as_string("res://config/tuning.json")
	var tuning_v: Variant = JSON.parse_string(tuning_txt)
	if not (tuning_v is Dictionary):
		push_error("FAIL: Could not parse tuning.json")
		_cleanup()
		return false
	var tuning: Dictionary = tuning_v
	if int(tuning.get("playerWalkFramesPerTile", -1)) != 16 or int(tuning.get("playerRunFramesPerTile", -1)) != 8 or int(tuning.get("playerLedgeHopFrames", -1)) != 32 or int(tuning.get("playerTurnFrames", -1)) != 8:
		push_error("FAIL: tuning.json frame keys mismatch: %s" % str(tuning))
		_cleanup()
		return false
	for bad_k in ["playerWalkTilesPerSec", "playerRunTilesPerSec", "walkTilesPerSec", "runTilesPerSec"]:
		if tuning.has(bad_k):
			push_error("FAIL: tuning.json must not contain tiles-per-second key '%s' (Decision 79)" % bad_k)
			_cleanup()
			return false
	if Config.player_walk_frames_per_tile != 16 or Config.player_run_frames_per_tile != 8 or Config.player_ledge_hop_frames != 32 or Config.player_turn_frames != 8:
		push_error("FAIL: Config frame counts mismatch")
		_cleanup()
		return false

	# 2. Verify exact Emerald walk (16/60s), run (8/60s), ledge hop (32/60s, 24px peak), turn-in-place (8/60s),
	# and alternating L/R feet + exact 8/16 & 5/8 animation phase splits (F77, F78)
	const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
	var walker := PlayerWalker.new()
	add_child(walker)
	walker.set_force_no_rom(true)
	walker.set_step_evaluator(func(from_tile: Vector2i, dir: Vector2i) -> Dictionary:
		var nxt := from_tile + dir
		if nxt == Vector2i(10, 12) and dir == Vector2i(0, 1):
			return {"action": "ledge", "over": nxt, "to": from_tile + dir * 2, "landing_class": TileSynth2.TILE_GRASS}
		if nxt == Vector2i(10, 16) and dir == Vector2i(0, 1):
			return {"action": "ledge", "over": nxt, "to": from_tile + dir * 2, "landing_class": TileSynth2.TILE_TALL_GRASS}
		if nxt == Vector2i(50, 51):
			return {"action": "blocked", "reason": "wall", "tile": nxt}
		return {"action": "step", "to": nxt}
	)
	walker.place_at(Vector2i(10, 10), "S")

	# 2a. Walk step takes 16/60s (0.2667s) — FAILS at 4.0 tps (0.25s)!
	walker.step_simulation(0.05, Vector2i(0, 1), false) # start walking S (already facing S)
	if not walker.is_moving() or walker.current_anim_mode() != "walk" or walker.current_anim_pose() != "step_l":
		push_error("FAIL: First walk step first half expected walk/step_l, got moving=%s mode=%s pose=%s" % [str(walker.is_moving()), walker.current_anim_mode(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.20, Vector2i.ZERO, false) # total 0.25s < 16/60 (0.2667s)
	if not walker.is_moving() or walker.grid_pos != Vector2i(10, 10):
		push_error("FAIL: Walk step finished too early at 0.25s (4.0 tps bug)! pos=%s" % str(walker.grid_pos))
		walker.queue_free()
		_cleanup()
		return false
	if walker.current_anim_pose() != "stand":
		push_error("FAIL: Walk step second half (t >= 0.5) expected stand pose, got %s" % walker.current_anim_pose())
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.02, Vector2i.ZERO, false) # total 0.27s >= 16/60s -> complete
	if walker.is_moving() or walker.grid_pos != Vector2i(10, 11):
		push_error("FAIL: Walk step should have completed at 0.27s -> (10,11), got moving=%s pos=%s" % [str(walker.is_moving()), str(walker.grid_pos)])
		walker.queue_free()
		_cleanup()
		return false

	# 2b. Second walk step alternates to step_r!
	walker.place_at(Vector2i(20, 20), "S", false) # keep foot parity from step 1
	walker.step_simulation(0.05, Vector2i(0, 1), false)
	if walker.current_anim_pose() != "step_r":
		push_error("FAIL: Second walk step expected alternating foot step_r, got %s" % walker.current_anim_pose())
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.25, Vector2i.ZERO, false) # finish step 2

	# 2c. Run step takes 8/60s (0.1333s) — FAILS at 8.0 tps (0.125s)! And uses 5/8 vs 3/8 split!
	walker.place_at(Vector2i(30, 30), "S", true) # reset parity -> step_l first
	walker.step_simulation(0.075, Vector2i(0, 1), true) # t = 0.075 / 0.1333 = 0.5625 < 0.625 (5/8) -> run / step_l
	if not walker.is_moving() or walker.current_anim_mode() != "run" or walker.current_anim_pose() != "step_l":
		push_error("FAIL: Run step at t=0.5625 (<5/8) expected run/step_l, got mode=%s pose=%s" % [walker.current_anim_mode(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.050, Vector2i.ZERO, true) # total 0.125s < 8/60 (0.1333s), t = 0.9375 >= 0.625 -> still moving, run/stand
	if not walker.is_moving() or walker.grid_pos != Vector2i(30, 30):
		push_error("FAIL: Run step finished too early at 0.125s (8.0 tps bug)! pos=%s" % str(walker.grid_pos))
		walker.queue_free()
		_cleanup()
		return false
	if walker.current_anim_mode() != "run" or walker.current_anim_pose() != "stand":
		push_error("FAIL: Run step at t=0.9375 (>=5/8) expected run/stand, got mode=%s pose=%s" % [walker.current_anim_mode(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.015, Vector2i.ZERO, true) # total 0.14s >= 8/60s -> complete
	if walker.is_moving() or walker.grid_pos != Vector2i(30, 31):
		push_error("FAIL: Run step should have completed at 0.14s -> (30,31), got %s" % str(walker.grid_pos))
		walker.queue_free()
		_cleanup()
		return false
	# Second run step alternates to run/step_r
	walker.step_simulation(0.05, Vector2i(0, 1), true)
	if walker.current_anim_mode() != "run" or walker.current_anim_pose() != "step_r":
		push_error("FAIL: Second run step expected run/step_r, got mode=%s pose=%s" % [walker.current_anim_mode(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(0.10, Vector2i.ZERO, true)

	# 2d. Ledge hop (Decision 80 F86c): exact sJumpY_High*2 table (-8 frame 0, -24 frames 10..15, 0 frames 28..31),
	# 8/8/8/8 walking cycle, shadow visible during hop and gone after, dust on grass (NOT on tall grass)!
	walker.place_at(Vector2i(10, 11), "S", true)
	walker.step_simulation(0.0, Vector2i(0, 1), false) # frame 0 of ledge hop
	if not walker.is_moving() or not is_equal_approx(walker.current_hop_offset_px(), -8.0) or not walker.is_shadow_visible() or walker.current_anim_pose() != "step_l":
		push_error("FAIL: Ledge hop frame 0 expected hop=-8, shadow=true, pose=step_l; got hop=%.2f shadow=%s pose=%s" % [walker.current_hop_offset_px(), str(walker.is_shadow_visible()), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	# Advance to frames 10..15 (peak -24.0) and check stand on frames 8..15
	walker.step_simulation(10.0 / 60.0, Vector2i.ZERO, false) # frame 10 -> -24, stand
	if not is_equal_approx(walker.current_hop_offset_px(), -24.0) or walker.current_anim_pose() != "stand":
		push_error("FAIL: Ledge hop frame 10 expected hop=-24, pose=stand; got hop=%.2f pose=%s" % [walker.current_hop_offset_px(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(5.0 / 60.0, Vector2i.ZERO, false) # frame 15 -> still -24
	if not is_equal_approx(walker.current_hop_offset_px(), -24.0):
		push_error("FAIL: Ledge hop frame 15 expected hop=-24, got %.2f" % walker.current_hop_offset_px())
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(3.0 / 60.0, Vector2i.ZERO, false) # frame 18 -> other foot step_r
	if walker.current_anim_pose() != "step_r":
		push_error("FAIL: Ledge hop frame 18 expected other foot step_r, got %s" % walker.current_anim_pose())
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(10.0 / 60.0, Vector2i.ZERO, false) # frame 28 -> hop=0, stand
	if not is_equal_approx(walker.current_hop_offset_px(), 0.0) or walker.current_anim_pose() != "stand":
		push_error("FAIL: Ledge hop frame 28 expected hop=0, pose=stand; got hop=%.2f pose=%s" % [walker.current_hop_offset_px(), walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(3.0 / 60.0, Vector2i.ZERO, false) # frame 31 -> hop=0, still moving
	if not walker.is_moving() or not is_equal_approx(walker.current_hop_offset_px(), 0.0):
		push_error("FAIL: Ledge hop frame 31 expected moving=true, hop=0; got moving=%s hop=%.2f" % [str(walker.is_moving()), walker.current_hop_offset_px()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(2.0 / 60.0, Vector2i.ZERO, false) # landed on GRASS at (10, 13)!
	if walker.is_moving() or walker.grid_pos != Vector2i(10, 13) or walker.is_shadow_visible() or not walker.is_dust_visible():
		push_error("FAIL: Grass landing expected pos=(10,13) shadow=false dust=true; got pos=%s shadow=%s dust=%s" % [str(walker.grid_pos), str(walker.is_shadow_visible()), str(walker.is_dust_visible())])
		walker.queue_free()
		_cleanup()
		return false
	# Advance past 24/60s -> dust disappears
	walker.step_simulation(25.0 / 60.0, Vector2i.ZERO, false)
	if walker.is_dust_visible():
		push_error("FAIL: Landing dust should vanish after 24/60s")
		walker.queue_free()
		_cleanup()
		return false

	# Ledge hop landing on TALL GRASS -> shadow visible during hop, NO dust on landing!
	walker.place_at(Vector2i(10, 15), "S", true)
	walker.step_simulation(33.0 / 60.0, Vector2i(0, 1), false)
	if walker.grid_pos != Vector2i(10, 17) or walker.is_dust_visible():
		push_error("FAIL: Tall-grass landing expected pos=(10,17) and dust=false; got pos=%s dust=%s" % [str(walker.grid_pos), str(walker.is_dust_visible())])
		walker.queue_free()
		_cleanup()
		return false

	# 2e. Turn-in-place (Decision 80 F86b): 4/60s foot frame, then 4/60s stand frame; tap turns without moving, hold steps!
	walker.place_at(Vector2i(15, 15), "S", true)
	walker.step_simulation(2.0 / 60.0, Vector2i(1, 0), false) # tap E -> foot frame during first 4/60s
	if walker.facing != "E" or walker.current_anim_pose() != "step_l" or walker.is_moving():
		push_error("FAIL: Tap-turn at 2/60s expected facing=E pose=step_l moving=false; got facing=%s pose=%s moving=%s" % [walker.facing, walker.current_anim_pose(), str(walker.is_moving())])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(3.0 / 60.0, Vector2i.ZERO, false) # released, now at 5/60s (>= 4/60s) -> stand frame!
	if walker.current_anim_pose() != "stand" or walker.is_moving():
		push_error("FAIL: Tap-turn at 5/60s expected pose=stand moving=false; got pose=%s moving=%s" % [walker.current_anim_pose(), str(walker.is_moving())])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(4.0 / 60.0, Vector2i.ZERO, false) # total 9/60s -> finished turn without moving!
	if walker.is_turning() or walker.is_moving() or walker.grid_pos != Vector2i(15, 15):
		push_error("FAIL: Tap-turn should finish in IDLE on (15,15), got pos=%s" % str(walker.grid_pos))
		walker.queue_free()
		_cleanup()
		return false
	# Now tap W and HOLD past 8/60s -> turns W then steps W
	walker.step_simulation(5.0 / 60.0, Vector2i(-1, 0), false)
	if walker.facing != "W" or walker.is_moving():
		push_error("FAIL: Holding W for 5/60s (<8/60s) should still be turning in place")
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(4.0 / 60.0, Vector2i(-1, 0), false) # total 9/60s > 8/60s -> starts moving W!
	if not walker.is_moving():
		push_error("FAIL: Holding W past 8/60s should have started stepping")
		walker.queue_free()
		_cleanup()
		return false

	# 2f. Wall bump (Decision 80 F86a): 32/60s (16f foot + 16f stand), locks turn/step until 32f finish, alternates feet!
	walker.place_at(Vector2i(50, 50), "S", true)
	walker.step_simulation(8.0 / 60.0, Vector2i(0, 1), false) # blocked by wall at (50,51) -> BUMPING foot frame
	if not walker.is_bumping() or walker.current_anim_pose() != "step_l" or walker.grid_pos != Vector2i(50, 50):
		push_error("FAIL: Bump at 8/60s expected bumping=true pose=step_l pos=(50,50); got bumping=%s pose=%s pos=%s" % [str(walker.is_bumping()), walker.current_anim_pose(), str(walker.grid_pos)])
		walker.queue_free()
		_cleanup()
		return false
	# Trying to turn E mid-bump (at 18/60s) must NOT interrupt the 32-frame bump, and pose switches to stand after 16/60s!
	walker.step_simulation(10.0 / 60.0, Vector2i(1, 0), false) # total 18/60s >= 16/60s
	if not walker.is_bumping() or walker.facing != "S" or walker.current_anim_pose() != "stand":
		push_error("FAIL: Bump at 18/60s expected bumping=true facing=S pose=stand; got bumping=%s facing=%s pose=%s" % [str(walker.is_bumping()), walker.facing, walker.current_anim_pose()])
		walker.queue_free()
		_cleanup()
		return false
	walker.step_simulation(15.0 / 60.0, Vector2i(0, 1), false) # total 33/60s -> finishes bump 1 and starts bump 2 on alternating foot step_r!
	if not walker.is_bumping() or walker.current_anim_pose() != "step_r" or walker.grid_pos != Vector2i(50, 50):
		push_error("FAIL: Consecutive bump 2 expected alternating foot step_r on (50,50); got bumping=%s pose=%s pos=%s" % [str(walker.is_bumping()), walker.current_anim_pose(), str(walker.grid_pos)])
		walker.queue_free()
		_cleanup()
		return false
	walker.queue_free()

	# 3. 18-frame sprites: non-empty 32x64, E == horizontal mirror of W, Brendan != May, ROM != --no-rom
	for sidx in [0, 1]:
		for mode in ["walk", "run"]:
			for pose in ["stand", "step_l", "step_r"]:
				for dir_s in ["S", "N", "W", "E"]:
					var fb_tex := PlayerSprites.resolve_texture(sidx, dir_s, mode, pose, true)
					if fb_tex == null:
						push_error("FAIL: Fallback player texture null for idx=%d %s %s %s" % [sidx, dir_s, mode, pose])
						_cleanup()
						return false
					var fb_img := fb_tex.get_image()
					if fb_img.get_width() != 32 or fb_img.get_height() != 64 or _count_opaque(fb_img) < 100:
						push_error("FAIL: Fallback texture size/opacity invalid for idx=%d %s %s %s" % [sidx, dir_s, mode, pose])
						_cleanup()
						return false
				# E pixel-equals mirrored W (fallback)
				var w_fb := PlayerSprites.resolve_texture(sidx, "W", mode, pose, true).get_image()
				var e_fb := PlayerSprites.resolve_texture(sidx, "E", mode, pose, true).get_image()
				var w_flip := w_fb.duplicate()
				w_flip.flip_x()
				if not _images_equal(w_flip, e_fb):
					push_error("FAIL: Fallback E != mirror(W) for idx=%d %s %s" % [sidx, mode, pose])
					_cleanup()
					return false

	# Brendan != May (fallback)
	var b_fb := PlayerSprites.resolve_texture(0, "S", "walk", "stand", true).get_image()
	var m_fb := PlayerSprites.resolve_texture(1, "S", "walk", "stand", true).get_image()
	if _images_equal(b_fb, m_fb):
		push_error("FAIL: Fallback Brendan and May sprites are identical")
		_cleanup()
		return false

	# If ROM is available (TENTH_SPRING_ROM_GBA or cached), verify ROM 18-frame atlas too!
	var rom_bundle: Variant = AssetDB.player_sprite_atlas()
	if rom_bundle is Dictionary:
		for sidx in [0, 1]:
			for mode in ["walk", "run"]:
				for pose in ["stand", "step_l", "step_r"]:
					var w_rom := PlayerSprites.resolve_texture(sidx, "W", mode, pose, false).get_image()
					var e_rom := PlayerSprites.resolve_texture(sidx, "E", mode, pose, false).get_image()
					if w_rom.get_width() != 32 or w_rom.get_height() != 64 or _count_opaque(w_rom) < 100:
						push_error("FAIL: ROM player texture invalid for idx=%d %s %s" % [sidx, mode, pose])
						_cleanup()
						return false
					var wf := w_rom.duplicate()
					wf.flip_x()
					if not _images_equal(wf, e_rom):
						push_error("FAIL: ROM E != mirror(W) for idx=%d %s %s" % [sidx, mode, pose])
						_cleanup()
						return false
		var b_rom := PlayerSprites.resolve_texture(0, "S", "walk", "stand", false).get_image()
		var m_rom := PlayerSprites.resolve_texture(1, "S", "walk", "stand", false).get_image()
		if _images_equal(b_rom, m_rom):
			push_error("FAIL: ROM Brendan and May sprites are identical")
			_cleanup()
			return false
		if _images_equal(b_rom, b_fb):
			push_error("FAIL: ROM Brendan sprite equals --no-rom fallback")
			_cleanup()
			return false
		var b_run := PlayerSprites.resolve_texture(0, "S", "run", "step_l", false).get_image()
		if _images_equal(b_rom, b_run):
			push_error("FAIL: ROM Brendan walk stand equals run step_l")
			_cleanup()
			return false

	# 3b. Shadow & Landing Dust textures (Decision 80 F86c): non-empty 32x16 in --no-rom and ROM, and ROM != --no-rom
	var sh_fb := PlayerSprites.resolve_shadow_texture(true).get_image()
	if sh_fb.get_width() != 32 or sh_fb.get_height() != 16 or _count_opaque(sh_fb) < 40:
		push_error("FAIL: Fallback shadow texture invalid")
		_cleanup()
		return false
	for df in range(3):
		var df_fb := PlayerSprites.resolve_dust_texture(df, true).get_image()
		if df_fb.get_width() != 32 or df_fb.get_height() != 16 or _count_opaque(df_fb) < 12:
			push_error("FAIL: Fallback dust texture frame %d invalid" % df)
			_cleanup()
			return false
	var fe_bundle: Variant = AssetDB.field_effects_atlas()
	if fe_bundle is Dictionary:
		var sh_rom := PlayerSprites.resolve_shadow_texture(false).get_image()
		if sh_rom.get_width() != 32 or sh_rom.get_height() != 16 or _count_opaque(sh_rom) < 40 or _images_equal(sh_rom, sh_fb):
			push_error("FAIL: ROM shadow texture invalid or identical to --no-rom fallback")
			_cleanup()
			return false
		for df in range(3):
			var df_rom := PlayerSprites.resolve_dust_texture(df, false).get_image()
			var df_fb2 := PlayerSprites.resolve_dust_texture(df, true).get_image()
			if df_rom.get_width() != 32 or df_rom.get_height() != 16 or _count_opaque(df_rom) < 12 or _images_equal(df_rom, df_fb2):
				push_error("FAIL: ROM dust texture frame %d invalid or identical to --no-rom fallback" % df)
				_cleanup()
				return false

	# 4. Home Hub Brendan/May toggle persists in player_profile.sprite_index
	var hub := HomeHubScene.instantiate()
	add_child(hub)
	if DB.get_player_sprite_index() != 0:
		push_error("FAIL: Expected initial sprite_index 0")
		hub.queue_free()
		_cleanup()
		return false
	var next_idx: int = hub.toggle_character_sprite()
	if next_idx != 1 or DB.get_player_sprite_index() != 1:
		push_error("FAIL: HomeHub toggle to May failed: idx=%d db=%d" % [next_idx, DB.get_player_sprite_index()])
		hub.queue_free()
		_cleanup()
		return false
	var back_idx: int = hub.toggle_character_sprite()
	if back_idx != 0 or DB.get_player_sprite_index() != 0:
		push_error("FAIL: HomeHub toggle back to Brendan failed")
		hub.queue_free()
		_cleanup()
		return false
	hub.queue_free()

	# 5. MapViewer walking mode defaults to zoom 2.0 (15x10 tiles at 960x640), camera centered on player,
	# and mouse-wheel steps 2.0 <-> 1.0 <-> 0.5
	var mv := MapViewScene.instantiate()
	mv.set_force_no_rom(true)
	add_child(mv)
	if not mv.load_place("city:washington-dc", true):
		push_error("FAIL: MapViewer.load_place(city:washington-dc) failed")
		mv.queue_free()
		_cleanup()
		return false
	if not mv.is_walk_mode_active():
		push_error("FAIL: Expected walk mode active after loading city:washington-dc")
		mv.queue_free()
		_cleanup()
		return false
	if not is_equal_approx(mv._current_zoom_step, 2.0):
		push_error("FAIL: Expected default walk-mode zoom 2.0 (F81), got %.3f" % mv._current_zoom_step)
		mv.queue_free()
		_cleanup()
		return false
	var pw: PlayerWalker = mv.get_player_walker()
	if pw == null:
		push_error("FAIL: PlayerWalker null in walk mode")
		mv.queue_free()
		_cleanup()
		return false
	mv._process(0.016)
	var cam_err: float = mv._camera.position.distance_to(pw.get_camera_target())
	if cam_err > 1.0:
		push_error("FAIL: Camera not centered on player: err=%.2f cam=%s target=%s" % [cam_err, str(mv._camera.position), str(pw.get_camera_target())])
		mv.queue_free()
		_cleanup()
		return false
	# Wheel down: 2.0 -> 1.0 -> 0.5 -> stays 0.5; wheel up -> 1.0 -> 2.0
	mv._step_zoom(-1)
	if not is_equal_approx(mv._current_zoom_step, 1.0):
		push_error("FAIL: Walk wheel zoom step down from 2.0 expected 1.0, got %.3f" % mv._current_zoom_step)
		mv.queue_free()
		_cleanup()
		return false
	mv._step_zoom(-1)
	if not is_equal_approx(mv._current_zoom_step, 0.5):
		push_error("FAIL: Walk wheel zoom step down from 1.0 expected 0.5, got %.3f" % mv._current_zoom_step)
		mv.queue_free()
		_cleanup()
		return false
	mv._step_zoom(-1)
	if not is_equal_approx(mv._current_zoom_step, 0.5):
		push_error("FAIL: Walk wheel zoom should clamp at 0.5, got %.3f" % mv._current_zoom_step)
		mv.queue_free()
		_cleanup()
		return false
	mv._step_zoom(1)
	mv._step_zoom(1)
	if not is_equal_approx(mv._current_zoom_step, 2.0):
		push_error("FAIL: Walk wheel zoom step back up expected 2.0, got %.3f" % mv._current_zoom_step)
		mv.queue_free()
		_cleanup()
		return false

	mv.queue_free()
	_cleanup()
	return true
