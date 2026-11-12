extends Node

# check_caricature.gd — Headless Caricature Map Compiler & Playable-Size Checker Scene (Item 48b)
# Contract: docs/implementation_plan_dc_trial.md §5.3 & docs/agent_execution_guide.md §5

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")

const CLASS_TO_CHAR: Dictionary = {
	TileSynth2.TILE_GRASS: ".",
	TileSynth2.TILE_TALL_GRASS: ",",
	TileSynth2.TILE_TREE: "T",
	TileSynth2.TILE_WATER: "~",
	TileSynth2.TILE_SAND: ":",
	TileSynth2.TILE_MARSH: "%",
	TileSynth2.TILE_PATH: "-",
	TileSynth2.TILE_ROAD: "=",
	TileSynth2.TILE_RAIL: "R",
	TileSynth2.TILE_BRIDGE: "B",
	TileSynth2.TILE_PLAZA: "#",
	TileSynth2.TILE_ROOF: "@",
	TileSynth2.TILE_WALL: "@",
	TileSynth2.TILE_DOOR: "D",
	TileSynth2.TILE_FENCE: "F",
	TileSynth2.TILE_FLOWERS: "*",
	TileSynth2.TILE_GRAVE: "+",
	TileSynth2.TILE_SIGN: "S",
	TileSynth2.TILE_CROP: "c",
	TileSynth2.TILE_RUBBLE: "x",
}

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var roster_path := Neighbourhoods.DEFAULT_CONFIG_PATH
	var target_area_id := ""
	var show_preview := false

	var i := 0
	while i < user_args.size():
		var arg := str(user_args[i]).strip_edges()
		if arg == "--preview":
			show_preview = true
			i += 1
		elif arg == "--area" and i + 1 < user_args.size():
			target_area_id = str(user_args[i + 1]).strip_edges()
			i += 2
		elif arg.begins_with("--area="):
			target_area_id = arg.trim_prefix("--area=").strip_edges()
			i += 1
		elif arg == "--roster" and i + 1 < user_args.size():
			roster_path = str(user_args[i + 1]).strip_edges()
			i += 2
		elif arg.begins_with("--roster="):
			roster_path = arg.trim_prefix("--roster=").strip_edges()
			i += 1
		else:
			i += 1

	if not FileAccess.file_exists(roster_path):
		printerr("[FAIL] roster file not found: %s" % roster_path)
		get_tree().quit(2)
		return

	Neighbourhoods.set_config_path_for_tests(roster_path)

	var areas_to_check: Array = []
	if not target_area_id.is_empty():
		var single_area: Dictionary = Neighbourhoods.area(target_area_id)
		if single_area.is_empty():
			printerr("[FAIL] unknown area %s" % target_area_id)
			Neighbourhoods.set_config_path_for_tests("")
			get_tree().quit(2)
			return
		areas_to_check.append(single_area)
	else:
		var raw_txt := FileAccess.get_file_as_string(roster_path)
		var parsed: Variant = JSON.parse_string(raw_txt)
		if not (parsed is Dictionary):
			printerr("[FAIL] invalid roster JSON: %s" % roster_path)
			Neighbourhoods.set_config_path_for_tests("")
			get_tree().quit(2)
			return
		var root: Dictionary = parsed
		var cities_var: Variant = root.get("cities", [])
		if cities_var is Array:
			for c_var in cities_var:
				if c_var is Dictionary:
					var pid := str((c_var as Dictionary).get("place_id", ""))
					if not pid.is_empty():
						for a_entry in Neighbourhoods.areas_of(pid):
							areas_to_check.append(a_entry)

	var any_failed := false
	for a_var in areas_to_check:
		var area: Dictionary = a_var
		if not _check_one_area(area, show_preview):
			any_failed = true

	Neighbourhoods.set_config_path_for_tests("")
	get_tree().quit(1 if any_failed else 0)

func _check_one_area(area: Dictionary, show_preview: bool) -> bool:
	var area_id := str(area.get("id", ""))
	var map_path := CaricatureMap.resolve_map_path(str(area.get("map", "")))
	if not FileAccess.file_exists(map_path):
		print("CARICATURE %s FAIL missing map" % area_id)
		return false

	var txt := FileAccess.get_file_as_string(map_path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		print("CARICATURE %s FAIL invalid map json" % area_id)
		return false

	var compiled: Dictionary = CaricatureMap.compile(area, parsed)
	if not bool(compiled.get("ok", false)):
		var errs: Array = compiled.get("errors", [])
		var err_str := ", ".join(PackedStringArray(errs)) if not errs.is_empty() else "compile error"
		print("CARICATURE %s FAIL %s" % [area_id, err_str])
		return false

	var m: Dictionary = CaricatureCheck.measure(compiled, area)
	var w: int = int(compiled["w"])
	var h: int = int(compiled["h"])
	var passed: bool = bool(m.get("ok", false))
	var failed_rules: Array = m.get("failed_rules", [])
	var status_str := "PASS" if passed else ("FAIL " + ",".join(PackedStringArray(failed_rules)))

	print(
		"CARICATURE %s size=%dx%d walkable=%d unreached=%d trapped=%d max_walk=%d landmark_max=%d tall_grass=%.2f search_doors=%d landmarks=%d/%d art_pending=%d %s" % [
			area_id,
			w,
			h,
			int(m["walkable"]),
			int(m["unreached"]),
			int(m["trapped"]),
			int(m["max_walk"]),
			int(m["landmark_max"]),
			float(m["tall_grass_share"]),
			int(m["search_doors"]),
			int(m["landmarks_present"]),
			int(m["landmarks_listed"]),
			int(m["art_pending"]),
			status_str,
		]
	)

	if show_preview:
		_print_preview(compiled)

	return passed

func _print_preview(compiled: Dictionary) -> void:
	var w: int = int(compiled["w"])
	var h: int = int(compiled["h"])
	var cls_buf: PackedByteArray = compiled["class"]
	var var_buf: PackedByteArray = compiled["variant"]
	var mask_buf: PackedByteArray = compiled["mask"]
	var lamp: Vector2i = compiled["lamp"]
	var arrival: Vector2i = compiled["arrival"]

	for y in range(h):
		var chars := PackedStringArray()
		chars.resize(w)
		for x in range(w):
			if x == lamp.x and y == lamp.y:
				chars[x] = "L"
				continue
			if x == arrival.x and y == arrival.y:
				chars[x] = "a"
				continue
			var idx: int = y * w + x
			var cls: int = cls_buf[idx]
			var v: int = var_buf[idx]
			var mask: int = mask_buf[idx]
			if cls == TileSynth2.TILE_STAMP:
				chars[x] = "o" if TileSynth2.is_walkable(cls, v, mask) else "@"
			elif cls == TileSynth2.TILE_LEDGE:
				if v == 0:
					chars[x] = "v"
				elif v == 1:
					chars[x] = ">"
				else:
					chars[x] = "<"
			elif CLASS_TO_CHAR.has(cls):
				chars[x] = str(CLASS_TO_CHAR[cls])
			else:
				chars[x] = "?"
		print("PREVIEW:" + "".join(chars))
