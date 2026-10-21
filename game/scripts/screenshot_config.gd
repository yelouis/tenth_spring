class_name ScreenshotConfig
extends RefCounted

# screenshot_config.gd — Screenshot Harness Argument Parsing and Refusal Rules
# Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6

const ERR_IN_REPO: String = "[FAIL] screenshot path must be outside the repository"
const ERR_UNSUPPORTED_ZOOM: String = "[FAIL] unsupported zoom %s"
const ERR_UNSUPPORTED_FOCUS: String = "[FAIL] unsupported focus %s"
const ERR_HEADLESS: String = "[FAIL] screenshots need a window"

const SUPPORTED_ZOOMS: Array = [0.0625, 0.25, 1, 2, 3]
const SUPPORTED_FOCUSES: Array = ["most_visited", "most_buildings"]

static func parse_args(user_args: Array, is_headless: bool, repo_root_override: String = "") -> Dictionary:
	var screenshot_path := ""
	var zoom_str := ""
	var zoom_val: float = 1.0
	var frames_val := 10
	var focus_str := ""
	var focus_val := "most_visited"
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
		elif arg.begins_with("--focus="):
			focus_str = arg.trim_prefix("--focus=").strip_edges()
		elif arg == "--focus" and i + 1 < user_args.size():
			focus_str = str(user_args[i + 1]).strip_edges()
			i += 1
		i += 1

	if not has_screenshot:
		return {"ok": true, "is_screenshot": false}

	# Refusal 1: Headless refusal (§7.4 rule 2)
	if is_headless:
		return {"ok": false, "error": ERR_HEADLESS, "exit_code": 2}

	# Refusal 2: Unknown zoom (§7.4 rule 2)
	if not zoom_str.is_empty():
		var valid_zoom := false
		if zoom_str.is_valid_float():
			var z_val := zoom_str.to_float()
			for sz in [0.0625, 0.25, 1.0, 2.0, 3.0]:
				if is_equal_approx(z_val, float(sz)):
					zoom_val = z_val
					valid_zoom = true
					break
		if not valid_zoom:
			return {"ok": false, "error": ERR_UNSUPPORTED_ZOOM % zoom_str, "exit_code": 2}

	# Refusal 3: Unsupported focus (§10.6 rule 1)
	if not focus_str.is_empty():
		if focus_str in SUPPORTED_FOCUSES:
			focus_val = focus_str
		else:
			return {"ok": false, "error": ERR_UNSUPPORTED_FOCUS % focus_str, "exit_code": 2}

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
		"focus": focus_val
	}
