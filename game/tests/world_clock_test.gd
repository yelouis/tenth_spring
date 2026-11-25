extends Node

## game/tests/world_clock_test.gd — Item 67 Master Plan Phase 4 Exit Test & Clock Falsifiers
## Contract: docs/master_implementation_plan.md (Phase 4 Exit: 12 mi = 48 min foot / 24 min bike),
##           docs/design_travel_and_time.md §1–§2, docs/implementation_plan_travel_and_time.md §(i)

const WorldClock := preload("res://world/world_clock.gd")

const TEST_DB_PATH: String = "user://test/world_clock_test.db"
const TEST_TMP_PATH: String = "user://test/world_clock_test.db.tmp"

func _cleanup() -> void:
	DB.close()
	for p in [TEST_DB_PATH, TEST_DB_PATH + "-wal", TEST_DB_PATH + "-shm", TEST_TMP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)

func run_test() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	if not DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe failed in world_clock_test")
		return false
	_cleanup()
	DB.configure_paths(TEST_DB_PATH, TEST_TMP_PATH)
	DB.init_db()

	# 1. Master Plan Phase 4 Exit Test: 12 miles -> 48 min on foot, 24 min by bicycle
	var foot_12 := WorldClock.estimate_trip_minutes(12.0, false)
	var bike_12 := WorldClock.estimate_trip_minutes(12.0, true)
	if foot_12 != 48:
		push_error("FAIL: Expected 12 miles on foot = 48 min, got %d" % foot_12)
		_cleanup()
		return false
	if bike_12 != 24:
		push_error("FAIL: Expected 12 miles by bicycle = 24 min, got %d" % bike_12)
		_cleanup()
		return false

	# 2. Fresh DB starts at 08:00 (480 min) and charging 12 mi on foot advances clock +48 min -> 08:48 (528)
	var clk := WorldClock.new()
	var loaded := clk.load_from_db(DB)
	if loaded != 480 or clk.format_hhmm() != "08:00" or clk.time_band() != "day":
		push_error("FAIL: Fresh clock expected 480 (08:00 day), got %d (%s %s)" % [loaded, clk.format_hhmm(), clk.time_band()])
		_cleanup()
		return false

	var charged := clk.charge_trip_miles(12.0, false)
	if charged != 48 or clk.game_epoch_minutes != 528 or clk.format_hhmm() != "08:48":
		push_error("FAIL: Expected 12-mi charge 48 -> 528 (08:48), got charged=%d mins=%d (%s)" % [charged, clk.game_epoch_minutes, clk.format_hhmm()])
		_cleanup()
		return false

	# 3. Persistence & zero fast-forward across DB close + reopen (even with old last_wall_sync 10h ago!)
	var ten_hours_ago := int(Time.get_unix_time_from_system()) - 36000
	DB.set_world_clock_minutes(528, ten_hours_ago)
	DB.close()
	DB.init_db()
	var clk2 := WorldClock.new()
	var reloaded := clk2.load_from_db(DB)
	if reloaded != 528:
		push_error("FAIL: Expected zero fast-forward on reload (528), got %d" % reloaded)
		_cleanup()
		return false

	# 4. Clock pauses at Home Hub (running = false) and ticks at 2.0 wall s/min when running = true
	clk2.set_running(false)
	var adv_paused := clk2.tick(120.0)
	if adv_paused != 0 or clk2.game_epoch_minutes != 528:
		push_error("FAIL: Clock advanced while paused at Home Hub: adv=%d mins=%d" % [adv_paused, clk2.game_epoch_minutes])
		_cleanup()
		return false

	clk2.set_running(true)
	var adv_half := clk2.tick(1.5)
	if adv_half != 0 or clk2.game_epoch_minutes != 528:
		push_error("FAIL: Clock advanced before 2.0 wall seconds elapsed: adv=%d" % adv_half)
		_cleanup()
		return false
	var adv_full := clk2.tick(0.5)
	if adv_full != 1 or clk2.game_epoch_minutes != 529:
		push_error("FAIL: Expected +1 min after 2.0s total, got adv=%d mins=%d" % [adv_full, clk2.game_epoch_minutes])
		_cleanup()
		return false
	var adv_multi := clk2.tick(10.0)
	if adv_multi != 5 or clk2.game_epoch_minutes != 534:
		push_error("FAIL: Expected +5 min after 10.0s, got adv=%d mins=%d" % [adv_multi, clk2.game_epoch_minutes])
		_cleanup()
		return false

	# 5. Four time bands + daylight_minutes_left + daylight_tag boundaries
	var band_cases := [
		[0, "night", 0],
		[299, "night", 0],
		[300, "dawn", 840],
		[419, "dawn", 721],
		[420, "day", 720],
		[1139, "day", 1],
		[1140, "dusk", 0],
		[1259, "dusk", 0],
		[1260, "night", 0],
		[1439, "night", 0],
	]
	for bc in band_cases:
		var m := int(bc[0])
		var exp_band := str(bc[1])
		var exp_left := int(bc[2])
		if WorldClock.time_band_for_minute(m) != exp_band:
			push_error("FAIL: time_band_for_minute(%d) expected %s, got %s" % [m, exp_band, WorldClock.time_band_for_minute(m)])
			_cleanup()
			return false
		if WorldClock.daylight_minutes_left_for_minute(m) != exp_left:
			push_error("FAIL: daylight_minutes_left_for_minute(%d) expected %d, got %d" % [m, exp_left, WorldClock.daylight_minutes_left_for_minute(m)])
			_cleanup()
			return false

	# Daylight tags (design_travel_and_time.md §2 / plan §(e)):
	# green = round trip before dusk (>= 2*cost), amber = one-way before dusk (>= cost, < 2*cost), red = < cost or dusk/night
	clk2.set_minutes(1050, false) # 17:30 -> 90 min left until 19:00 dusk
	if clk2.daylight_tag(15) != "green" or clk2.daylight_tag(45) != "green" or clk2.daylight_tag(46) != "amber" or clk2.daylight_tag(90) != "amber" or clk2.daylight_tag(91) != "red":
		push_error("FAIL: Daylight tags wrong at 17:30: 15=%s 45=%s 46=%s 90=%s 91=%s" % [
			clk2.daylight_tag(15), clk2.daylight_tag(45), clk2.daylight_tag(46), clk2.daylight_tag(90), clk2.daylight_tag(91)
		])
		_cleanup()
		return false
	clk2.set_minutes(1200, false) # 20:00 dusk
	if clk2.daylight_tag(1) != "red":
		push_error("FAIL: Expected red tag at dusk, got %s" % clk2.daylight_tag(1))
		_cleanup()
		return false

	# 6. Falsifier: mutating live Config.walk_speed_mph changes estimate_trip_minutes (proving live config binding)
	var orig_mph: float = Config.walk_speed_mph
	Config.walk_speed_mph = 10.0
	var slow_12 := WorldClock.estimate_trip_minutes(12.0, false)
	Config.walk_speed_mph = orig_mph
	if slow_12 != 72:
		push_error("FAIL: Live Config falsifier failed: expected 72 min at 10 mph, got %d" % slow_12)
		_cleanup()
		return false

	# 7. Falsifier: DB.assert_test_safe refuses user://walk_dc/ (Decision 79 standing constraint 4)
	DB.close()
	DB.configure_paths("user://walk_dc/tenth_spring.db", "user://walk_dc/tenth_spring.db.tmp")
	if DB.assert_test_safe():
		push_error("FAIL: DB.assert_test_safe allowed user://walk_dc/tenth_spring.db!")
		_cleanup()
		return false

	_cleanup()
	return true
