class_name ScreenshotConfig
extends RefCounted

# screenshot_config.gd — Screenshot Harness Argument Parsing and Refusal Rules
# Contract: docs/implementation_plan_world_generation.md §7.4 & docs/agent_execution_guide.md §6

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")

const ERR_IN_REPO: String = "[FAIL] screenshot path must be outside the repository"
const ERR_UNSUPPORTED_ZOOM: String = "[FAIL] unsupported zoom %s"
const ERR_UNSUPPORTED_FOCUS: String = "[FAIL] unsupported focus %s"
const ERR_UNSUPPORTED_SCREEN: String = "[FAIL] unsupported screen %s"
const ERR_HEADLESS: String = "[FAIL] screenshots need a window"
const ERR_AREA_NEEDS_DEMO: String = "[FAIL] --area needs --demo"
const ERR_UNKNOWN_AREA: String = "[FAIL] unknown area %s"
const ERR_CITY_NEEDS_DEMO: String = "[FAIL] --screen=city needs --demo"
const ERR_INTERIOR_NEEDS_DEMO: String = "[FAIL] --interior needs --demo"
const ERR_FLOOR_NEEDS_INTERIOR: String = "[FAIL] --floor needs --interior"
const ERR_UNKNOWN_INTERIOR: String = "[FAIL] unknown interior %s"
const ERR_UNKNOWN_FLOOR: String = "[FAIL] unknown floor %s"
const ERR_UNSUPPORTED_INTERIOR_VIEW: String = "[FAIL] unsupported interior-view %s"
const ERR_INTERIOR_VIEW_NEEDS_INTERIOR: String = "[FAIL] --interior-view needs --interior"
const ERR_INTERIOR_FALLBACK_NEEDS_INTERIOR: String = "[FAIL] --interior-fallback needs --interior"
const ERR_TILE_NEEDS_AREA: String = "[FAIL] --tile needs --area"
const ERR_INVALID_TILE: String = "[FAIL] invalid --tile %s"
const ERR_WALK_BENCH_NEEDS_DEMO: String = "[FAIL] --walk-bench needs --demo"
const ERR_WALK_SHOT_NEEDS_DEMO: String = "[FAIL] --walk-shot needs --demo"
const ERR_UNSUPPORTED_WALK_SHOT: String = "[FAIL] unsupported walk-shot %s"

const SUPPORTED_ZOOMS: Array = [0.0625, 0.25, 0.5, 1, 2, 3]
const SUPPORTED_FOCUSES: Array = ["most_visited", "most_buildings", "far_buildings", "waypost", "landmark", "area"]
const SUPPORTED_SCREENS: Array = ["map", "town_map", "board", "city"]
const SUPPORTED_INTERIOR_VIEWS: Array = ["whole", "compare", "door"]
const SUPPORTED_WALK_SHOTS: Array = [
	"day", "dusk", "night", "seam_route", "house_interior",
	"dialogue_sign", "dialogue_person",
	"brendan_step", "brendan_run", "may_step", "may_run",
	"wall_bump", "ledge_hop", "landing_dust"
]
const WALK_BENCH_MAX_P95_MS: float = 16.7
const WALK_BENCH_MAX_TRANSITION_MS: float = 33.4

static func evaluate_walk_bench_budget(walk_p95_ms: float, seam_max_ms: float, door_enter_max_ms: float, door_exit_max_ms: float) -> Dictionary:
	var fails: Array[String] = []
	if walk_p95_ms > WALK_BENCH_MAX_P95_MS:
		fails.append("WALK_FRAME_P95_MS=%.2f>%.1f" % [walk_p95_ms, WALK_BENCH_MAX_P95_MS])
	if seam_max_ms > WALK_BENCH_MAX_TRANSITION_MS:
		fails.append("SEAM_MAX_FRAME_MS=%.2f>%.1f" % [seam_max_ms, WALK_BENCH_MAX_TRANSITION_MS])
	if door_enter_max_ms > WALK_BENCH_MAX_TRANSITION_MS:
		fails.append("DOOR_ENTER_MAX_FRAME_MS=%.2f>%.1f" % [door_enter_max_ms, WALK_BENCH_MAX_TRANSITION_MS])
	if door_exit_max_ms > WALK_BENCH_MAX_TRANSITION_MS:
		fails.append("DOOR_EXIT_MAX_FRAME_MS=%.2f>%.1f" % [door_exit_max_ms, WALK_BENCH_MAX_TRANSITION_MS])
	return {"ok": fails.is_empty(), "fails": fails}

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
	var interior_str := ""
	var has_interior := false
	var floor_str := ""
	var has_floor := false
	var floor_val := 0
	var interior_view_str := ""
	var has_interior_view := false
	var interior_view_val := "whole"
	var interior_fallback := false
	var no_rom := false
	var tile_str := ""
	var has_tile := false
	var tile_val := Vector2i(-1, -1)
	var has_demo := false
	var has_screenshot := false
	var is_walk_bench := false
	var walk_shot_str := ""
	var has_walk_shot := false
	var time_minutes_val := -1
	var sprite_index_val := -1

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
		elif arg.begins_with("--interior="):
			has_interior = true
			interior_str = arg.trim_prefix("--interior=").strip_edges()
		elif arg == "--interior" and i + 1 < user_args.size():
			has_interior = true
			interior_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--interior":
			has_interior = true
			interior_str = ""
		elif arg.begins_with("--floor="):
			has_floor = true
			floor_str = arg.trim_prefix("--floor=").strip_edges()
		elif arg == "--floor" and i + 1 < user_args.size():
			has_floor = true
			floor_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--floor":
			has_floor = true
			floor_str = ""
		elif arg.begins_with("--interior-view="):
			has_interior_view = true
			interior_view_str = arg.trim_prefix("--interior-view=").strip_edges()
		elif arg == "--interior-view" and i + 1 < user_args.size():
			has_interior_view = true
			interior_view_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--interior-view":
			has_interior_view = true
			interior_view_str = ""
		elif arg == "--interior-fallback":
			interior_fallback = true
		elif arg == "--no-rom":
			no_rom = true
		elif arg.begins_with("--tile="):
			has_tile = true
			tile_str = arg.trim_prefix("--tile=").strip_edges()
		elif arg == "--tile" and i + 1 < user_args.size():
			has_tile = true
			tile_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--tile":
			has_tile = true
			tile_str = ""
		elif arg == "--walk-bench":
			is_walk_bench = true
		elif arg.begins_with("--walk-shot="):
			has_walk_shot = true
			walk_shot_str = arg.trim_prefix("--walk-shot=").strip_edges()
		elif arg == "--walk-shot" and i + 1 < user_args.size():
			has_walk_shot = true
			walk_shot_str = str(user_args[i + 1]).strip_edges()
			i += 1
		elif arg == "--walk-shot":
			has_walk_shot = true
			walk_shot_str = ""
		elif arg.begins_with("--time="):
			var tm_s := arg.trim_prefix("--time=").strip_edges()
			if tm_s.is_valid_int():
				time_minutes_val = tm_s.to_int()
		elif arg == "--time" and i + 1 < user_args.size():
			var tm_s := str(user_args[i + 1]).strip_edges()
			if tm_s.is_valid_int():
				time_minutes_val = tm_s.to_int()
			i += 1
		elif arg.begins_with("--sprite="):
			var sp_s := arg.trim_prefix("--sprite=").strip_edges()
			if sp_s.is_valid_int():
				sprite_index_val = clampi(sp_s.to_int(), 0, 1)
		elif arg == "--sprite" and i + 1 < user_args.size():
			var sp_s := str(user_args[i + 1]).strip_edges()
			if sp_s.is_valid_int():
				sprite_index_val = clampi(sp_s.to_int(), 0, 1)
			i += 1
		i += 1

	# Refusal 0: --area, --screen=city, and --interior are demo-only (standing constraint 22, §4.3, §10.12, §11.3 D)
	if has_area:
		if not has_demo:
			return {"ok": false, "error": ERR_AREA_NEEDS_DEMO, "exit_code": 2}
		if area_str.is_empty() or Neighbourhoods.area(area_str).is_empty():
			return {"ok": false, "error": ERR_UNKNOWN_AREA % area_str, "exit_code": 2}
	if has_tile:
		if not has_area:
			return {"ok": false, "error": ERR_TILE_NEEDS_AREA, "exit_code": 2}
		var tparts := tile_str.split(",")
		if tparts.size() != 2 or not tparts[0].strip_edges().is_valid_int() or not tparts[1].strip_edges().is_valid_int():
			return {"ok": false, "error": ERR_INVALID_TILE % tile_str, "exit_code": 2}
		tile_val = Vector2i(tparts[0].strip_edges().to_int(), tparts[1].strip_edges().to_int())
		if tile_val.x < 0 or tile_val.y < 0:
			return {"ok": false, "error": ERR_INVALID_TILE % tile_str, "exit_code": 2}
	if screen_str == "city" and not has_demo:
		return {"ok": false, "error": ERR_CITY_NEEDS_DEMO, "exit_code": 2}
	if has_floor and not has_interior:
		return {"ok": false, "error": ERR_FLOOR_NEEDS_INTERIOR, "exit_code": 2}
	if has_interior_view and not has_interior:
		return {"ok": false, "error": ERR_INTERIOR_VIEW_NEEDS_INTERIOR, "exit_code": 2}
	if interior_fallback and not has_interior:
		return {"ok": false, "error": ERR_INTERIOR_FALLBACK_NEEDS_INTERIOR, "exit_code": 2}
	if has_interior_view:
		if not (interior_view_str in SUPPORTED_INTERIOR_VIEWS):
			return {"ok": false, "error": ERR_UNSUPPORTED_INTERIOR_VIEW % interior_view_str, "exit_code": 2}
		interior_view_val = interior_view_str
	if has_interior:
		if not has_demo:
			return {"ok": false, "error": ERR_INTERIOR_NEEDS_DEMO, "exit_code": 2}
		var ipath := InteriorMap.resolve_interior_path(interior_str)
		if interior_str.is_empty() or ipath.is_empty():
			return {"ok": false, "error": ERR_UNKNOWN_INTERIOR % interior_str, "exit_code": 2}
		var idoc := InteriorMap.load_json(ipath)
		var ifloors: Array = idoc.get("floors", []) if idoc.get("floors", []) is Array else []
		if has_floor:
			if not floor_str.is_valid_int():
				return {"ok": false, "error": ERR_UNKNOWN_FLOOR % floor_str, "exit_code": 2}
			floor_val = floor_str.to_int()
		if floor_val < 0 or floor_val >= ifloors.size():
			return {"ok": false, "error": ERR_UNKNOWN_FLOOR % (floor_str if has_floor else str(floor_val)), "exit_code": 2}

	if is_walk_bench:
		if not has_demo:
			return {"ok": false, "error": ERR_WALK_BENCH_NEEDS_DEMO, "exit_code": 2}
		if is_headless:
			return {"ok": false, "error": ERR_HEADLESS, "exit_code": 2}
		var bench_zoom := 2.0
		if not zoom_str.is_empty():
			var valid_bz := false
			if zoom_str.is_valid_float():
				var bz_val := zoom_str.to_float()
				for sz in [0.5, 1.0, 2.0]:
					if is_equal_approx(bz_val, float(sz)):
						bench_zoom = bz_val
						valid_bz = true
						break
			if not valid_bz:
				return {"ok": false, "error": ERR_UNSUPPORTED_ZOOM % zoom_str, "exit_code": 2}
		return {
			"ok": true,
			"is_screenshot": false,
			"is_walk_bench": true,
			"zoom": bench_zoom,
			"timeout": timeout_val,
			"no_rom": no_rom,
			"time_minutes": time_minutes_val,
			"sprite_index": sprite_index_val,
		}

	if has_walk_shot:
		if not has_demo:
			return {"ok": false, "error": ERR_WALK_SHOT_NEEDS_DEMO, "exit_code": 2}
		if walk_shot_str.is_empty() or not (walk_shot_str in SUPPORTED_WALK_SHOTS):
			return {"ok": false, "error": ERR_UNSUPPORTED_WALK_SHOT % walk_shot_str, "exit_code": 2}

	if not has_screenshot:
		return {"ok": true, "is_screenshot": false, "is_walk_bench": false, "walk_shot": walk_shot_str, "time_minutes": time_minutes_val, "sprite_index": sprite_index_val, "area": area_str, "interior": interior_str, "floor": floor_val, "interior_view": interior_view_val, "interior_fallback": interior_fallback, "no_rom": no_rom, "has_tile": has_tile, "tile": tile_val}

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
		"is_walk_bench": false,
		"walk_shot": walk_shot_str,
		"time_minutes": time_minutes_val,
		"sprite_index": sprite_index_val,
		"screenshot_path": abs_path,
		"zoom": zoom_val,
		"frames": frames_val,
		"timeout": timeout_val,
		"focus": focus_val,
		"screen": screen_val,
		"area": area_str,
		"interior": interior_str,
		"floor": floor_val,
		"interior_view": interior_view_val,
		"interior_fallback": interior_fallback,
		"no_rom": no_rom,
		"has_tile": has_tile,
		"tile": tile_val,
	}
