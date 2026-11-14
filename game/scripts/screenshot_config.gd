class_name ScreenshotConfig
extends RefCounted

# screenshot_config.gd — Screenshot Harness Argument Parsing and Refusal Rules
# Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6

const Neighbourhoods := preload("res://world/neighbourhoods.gd")

const ERR_IN_REPO: String = "[FAIL] screenshot path must be outside the repository"
const ERR_UNSUPPORTED_ZOOM: String = "[FAIL] unsupported zoom %s"
const ERR_UNSUPPORTED_FOCUS: String = "[FAIL] unsupported focus %s"
const ERR_UNSUPPORTED_SCREEN: String = "[FAIL] unsupported screen %s"
const ERR_HEADLESS: String = "[FAIL] screenshots need a window"
const ERR_AREA_NEEDS_DEMO: String = "[FAIL] --area needs --demo"
const ERR_UNKNOWN_AREA: String = "[FAIL] unknown area %s"
const ERR_CITY_NEEDS_DEMO: String = "[FAIL] --screen=city needs --demo"

const SUPPORTED_ZOOMS: Array = [0.0625, 0.25, 0.5, 1, 2, 3]
const SUPPORTED_FOCUSES: Array = ["most_visited", "most_buildings", "far_buildings", "waypost", "landmark", "area"]
const SUPPORTED_SCREENS: Array = ["map", "town_map", "board", "city"]

static func parse_args(user_args: Array, is_headless: bool, repo_root_override: String = "") -> Dictionary:
	var screenshot_path := ""
	var zoom_str := ""
	var zoom_val: float = 1.0
	var frames_val := 10
	var timeout_val := 120
	var focus_str := ""
	var focus_val := "most_visited"
	var screen_str := ""
	var screen_val := "map"
	var area_str := ""
	var has_area := false
	var has_demo := false
	var has_screenshot := false

	var repo_root := repo_root_override
	if repo_root.is_empty():
		var res_path := ProjectSettings.globalize_path("res://").simplify_path()
		repo_root = res_path.get_base_dir()
	repo_root = repo_root.simplify_path()

	var i := 0
	while i < user_args.size():
		var arg := str(user_args[i]).strip_edges()
		if arg.begins_with("--screenshot="):
			has_screenshot = true
			screenshot_path = arg.trim_prefix("--screenshot=").strip_edges()
		elif arg == "--screenshot" and i + 1 < user_args.size():
			has_screenshot = true
			screenshot_path = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg.begins_with("--zoom="):
			zoom_str = arg.trim_prefix("--zoom=").strip_edges()
		elif arg == "--zoom" and i + 1 < user_args.size():
			zoom_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg.begins_with("--frames="):
			var f_str := arg.trim_prefix("--frames=").strip_edges()
			if f_str.is_valid_int() and f_str.to_int() > 0:
				frames_val = f_str.to_int()
		elif arg == "--frames" and i + 1 < user_args.size():
			var f_str := str(user_args[i + 1]).strip_edges()
			if f_str.is_valid_int() and f_str.to_int() > 0:
				frames_val = f_str.to_int()
			i += 1
		elif arg.begins_with("--timeout="):
			var t_str := arg.trim_prefix("--timeout=").strip_edges()
			if t_str.is_valid_int() and t_str.to_int() > 0:
				timeout_val = t_str.to_int()
		elif arg.begins_with("--focus="):
			focus_str = arg.trim_prefix("--focus=").strip_edges()
		elif arg == "--focus" and i + 1 < user_args.size():
			focus_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg.begins_with("--screen="):
			screen_str = arg.trim_prefix("--screen=").strip_edges()
		elif arg == "--screen" and i + 1 < user_args.size():
			screen_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--town-map":
			screen_str = "town_map"
		elif arg == "--demo" or arg.begins_with("--demo-dir="):
			has_demo = true
		elif arg == "--demo-dir" and i + 1 < user_args.size():
			has_demo = true
			i += 1
		elif arg.begins_with("--area="):
			has_area = true
			area_str = arg.trim_prefix("--area=").strip_edges()
		elif arg == "--area" and i + 1 < user_args.size():
			has_area = true
			area_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--area":
			has_area = true
			area_str = ""
		i += 1

	# Refusal 0: --area and --screen=city are demo-only (standing constraint 22, §4.3, §10.12)
	if has_area:
		if not has_demo:
			return {"ok": false, "error": ERR_AREA_NEEDS_DEMO, "exit_code": 2}
		if area_str.is_empty() or Neighbourhoods.area(area_str).is_empty():
			return {"ok": false, "error": ERR_UNKNOWN_AREA % area_str, "exit_code": 2}
	if screen_str == "city" and not has_demo:
		return {"ok": false, "error": ERR_CITY_NEEDS_DEMO, "exit_code": 2}

	if not has_screenshot:
		return {"ok": true, "is_screenshot": false, "area": area_str}

	# Refusal 1: Headless refusal (§7.4 rule 2)
	if is_headless:
		return {"ok": false, "error": ERR_HEADLESS, "exit_code": 2}

	# Refusal 2: Unknown zoom (§7.4 rule 2)
	if not zoom_str.is_empty():
		var valid_zoom := false
		if zoom_str.is_valid_float():
			var z_val := zoom_str.to_float()
			for sz in [0.0625, 0.25, 0.5, 1.0, 2.0, 3.0]:
				if is_equal_approx(z_val, float(sz)):
					zoom_val = z_val
					valid_zoom = true
					break
		if not valid_zoom:
			return {"ok": false, "error": ERR_UNSUPPORTED_ZOOM % zoom_str, "exit_code": 2}

	# Refusal 3: Unsupported focus (§10.6 rule 1, §4.3)
	if not focus_str.is_empty():
		if focus_str == "area" and not has_area:
			return {"ok": false, "error": ERR_UNSUPPORTED_FOCUS % focus_str, "exit_code": 2}
		elif focus_str in SUPPORTED_FOCUSES:
			focus_val = focus_str
		else:
			return {"ok": false, "error": ERR_UNSUPPORTED_FOCUS % focus_str, "exit_code": 2}
	if has_area:
		focus_val = "area"

	# Refusal 3b: Unsupported screen
	if not screen_str.is_empty():
		if screen_str in SUPPORTED_SCREENS:
			screen_val = screen_str
		else:
			return {"ok": false, "error": ERR_UNSUPPORTED_SCREEN % screen_str, "exit_code": 2}

	# Refusal 4: In-repo path (§7.4 rule 2)
	if screenshot_path.is_empty() or not screenshot_path.ends_with(".png"):
		return {"ok": false, "error": ERR_IN_REPO, "exit_code": 2}

	var abs_path := screenshot_path
	if abs_path.begins_with("res://"):
		return {"ok": false, "error": ERR_IN_REPO, "exit_code": 2}
	elif not abs_path.begins_with("/"):
		var pwd := OS.get_environment("PWD")
		if not pwd.is_empty():
			abs_path = pwd.path_join(abs_path)

	abs_path = abs_path.simplify_path()

	if abs_path == repo_root or abs_path.begins_with(repo_root + "/"):
		return {"ok": false, "error": ERR_IN_REPO, "exit_code": 2}

	return {
		"ok": true,
		"is_screenshot": true,
		"screenshot_path": abs_path,
		"zoom": zoom_val,
		"frames": frames_val,
		"timeout": timeout_val,
		"focus": focus_val,
		"screen": screen_val,
		"area": area_str
	}
