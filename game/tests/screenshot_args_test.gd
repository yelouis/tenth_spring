extends Node

# screenshot_args_test.gd — Screenshot Mode Argument Parsing & Refusal Verification (Item 3)
# Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6

const ScreenshotConfig := preload("res://scripts/screenshot_config.gd")

func run_test() -> bool:
	var repo_root := ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()

	# 1. Refusal 1: Headless refusal (§7.4 rule 2)
	# "--headless" with a valid outside-repo path must exit 2 with "[FAIL] screenshots need a window"
	var r_headless: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/test.png"], true, repo_root)
	if r_headless.get("ok", true) != false:
		push_error("Headless test failed: expected ok=false, got true")
		return false
	if r_headless.get("exit_code", 0) != 2:
		push_error("Headless test failed: expected exit_code=2, got %d" % r_headless.get("exit_code", 0))
		return false
	if r_headless.get("error", "") != "[FAIL] screenshots need a window":
		push_error("Headless test failed: unexpected error '%s'" % r_headless.get("error", ""))
		return false

	# 2. Refusal 2: Unknown zoom (§7.4 rule 2)
	# Unknown zoom must exit 2 with "[FAIL] unsupported zoom <z>"
	var r_zoom_0: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/test.png", "--zoom=0"], false, repo_root)
	if r_zoom_0.get("ok", true) != false or r_zoom_0.get("exit_code", 0) != 2 or r_zoom_0.get("error", "") != "[FAIL] unsupported zoom 0":
		push_error("Unknown zoom 0 test failed: %s" % str(r_zoom_0))
		return false

	var r_zoom_4: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/test.png", "--zoom=4"], false, repo_root)
	if r_zoom_4.get("ok", true) != false or r_zoom_4.get("exit_code", 0) != 2 or r_zoom_4.get("error", "") != "[FAIL] unsupported zoom 4":
		push_error("Unknown zoom 4 test failed: %s" % str(r_zoom_4))
		return false

	var r_zoom_xyz: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/test.png", "--zoom=xyz"], false, repo_root)
	if r_zoom_xyz.get("ok", true) != false or r_zoom_xyz.get("exit_code", 0) != 2 or r_zoom_xyz.get("error", "") != "[FAIL] unsupported zoom xyz":
		push_error("Unknown zoom xyz test failed: %s" % str(r_zoom_xyz))
		return false

	# 3. Refusal 3: In-repo path (§7.4 rule 2)
	# Absolute path inside repo must exit 2 with "[FAIL] screenshot path must be outside the repository"
	var in_repo_abs := repo_root.path_join("shot.png")
	var r_in_repo: Dictionary = ScreenshotConfig.parse_args(["--screenshot=" + in_repo_abs], false, repo_root)
	if r_in_repo.get("ok", true) != false or r_in_repo.get("exit_code", 0) != 2 or r_in_repo.get("error", "") != "[FAIL] screenshot path must be outside the repository":
		push_error("In-repo absolute path test failed: %s" % str(r_in_repo))
		return false

	# res:// path inside repo
	var r_res: Dictionary = ScreenshotConfig.parse_args(["--screenshot=res://shot.png"], false, repo_root)
	if r_res.get("ok", true) != false or r_res.get("exit_code", 0) != 2 or r_res.get("error", "") != "[FAIL] screenshot path must be outside the repository":
		push_error("In-repo res:// path test failed: %s" % str(r_res))
		return false

	# Subdirectory inside repo
	var in_repo_sub := repo_root.path_join("game/tests/fixtures/shot.png")
	var r_in_sub: Dictionary = ScreenshotConfig.parse_args(["--screenshot=" + in_repo_sub], false, repo_root)
	if r_in_sub.get("ok", true) != false or r_in_sub.get("exit_code", 0) != 2 or r_in_sub.get("error", "") != "[FAIL] screenshot path must be outside the repository":
		push_error("In-repo subpath test failed: %s" % str(r_in_sub))
		return false

	# Non-.png extension
	var r_txt: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/shot.txt"], false, repo_root)
	if r_txt.get("ok", true) != false or r_txt.get("exit_code", 0) != 2 or r_txt.get("error", "") != "[FAIL] screenshot path must be outside the repository":
		push_error("Non-.png extension test failed: %s" % str(r_txt))
		return false

	# 4. Refusal 4: Unsupported focus (§10.6 rule 1)
	var r_focus_bad: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--focus=invalid"], false, repo_root)
	if r_focus_bad.get("ok", true) != false or r_focus_bad.get("exit_code", 0) != 2 or r_focus_bad.get("error", "") != "[FAIL] unsupported focus invalid":
		push_error("Unsupported focus test failed: %s" % str(r_focus_bad))
		return false

	var r_focus_random: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--focus=center"], false, repo_root)
	if r_focus_random.get("ok", true) != false or r_focus_random.get("exit_code", 0) != 2 or r_focus_random.get("error", "") != "[FAIL] unsupported focus center":
		push_error("Unsupported focus test failed: %s" % str(r_focus_random))
		return false

	# 4b. Refusal 5: Unsupported screen
	var r_screen_bad: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--screen=invalid"], false, repo_root)
	if r_screen_bad.get("ok", true) != false or r_screen_bad.get("exit_code", 0) != 2 or r_screen_bad.get("error", "") != "[FAIL] unsupported screen invalid":
		push_error("Unsupported screen test failed: %s" % str(r_screen_bad))
		return false

	# 5. Valid Arguments & Defaults
	var r_valid: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--zoom=2", "--frames=15", "--focus=most_buildings"], false, repo_root)
	if not r_valid.get("ok", false) or not r_valid.get("is_screenshot", false):
		push_error("Valid config test failed: %s" % str(r_valid))
		return false
	if r_valid.get("screenshot_path", "") != "/tmp/out_test.png" or r_valid.get("zoom", 0) != 2 or r_valid.get("frames", 0) != 15 or r_valid.get("focus", "") != "most_buildings":
		push_error("Valid config values mismatch: %s" % str(r_valid))
		return false

	var r_mv: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--focus=most_visited"], false, repo_root)
	if not r_mv.get("ok", false) or r_mv.get("focus", "") != "most_visited":
		push_error("most_visited config test failed: %s" % str(r_mv))
		return false

	var r_waypost: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--focus=waypost"], false, repo_root)
	if not r_waypost.get("ok", false) or r_waypost.get("focus", "") != "waypost":
		push_error("waypost config test failed: %s" % str(r_waypost))
		return false

	var r_landmark: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--focus=landmark"], false, repo_root)
	if not r_landmark.get("ok", false) or r_landmark.get("focus", "") != "landmark":
		push_error("landmark config test failed: %s" % str(r_landmark))
		return false

	var r_town_map: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png", "--screen=town_map"], false, repo_root)
	if not r_town_map.get("ok", false) or r_town_map.get("screen", "") != "town_map":
		push_error("town_map config test failed: %s" % str(r_town_map))
		return false

	# Default zoom=1, frames=10, focus=most_visited
	var r_default: Dictionary = ScreenshotConfig.parse_args(["--screenshot=/tmp/out_test.png"], false, repo_root)
	if not r_default.get("ok", false) or r_default.get("zoom", 0) != 1 or r_default.get("frames", 0) != 10 or r_default.get("focus", "") != "most_visited":
		push_error("Default config values mismatch: %s" % str(r_default))
		return false

	# Non-screenshot execution
	var r_none: Dictionary = ScreenshotConfig.parse_args(["--demo"], false, repo_root)
	if not r_none.get("ok", false) or r_none.get("is_screenshot", true) != false:
		push_error("Non-screenshot test failed: %s" % str(r_none))
		return false

	print("screenshot_args_test checks passed")
	return true
