extends Node

# check_caricature.gd — Headless Caricature Map, Route & City Checker Scene (Items 48b, 53)
# Contract: docs/implementation_plan_dc_trial.md §5.3, §10.5 & docs/agent_execution_guide.md §3–§4

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

	var any_failed := false
	if not target_area_id.is_empty():
		var single_area: Dictionary = Neighbourhoods.area(target_area_id)
		if single_area.is_empty():
			printerr("[FAIL] unknown area %s" % target_area_id)
			Neighbourhoods.set_config_path_for_tests("")
			get_tree().quit(2)
			return
		var _comp_single := {}
		var _m_single := {}
		if not _check_one_area(single_area, show_preview, _comp_single, _m_single):
			any_failed = true
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
				if not (c_var is Dictionary):
					continue
				var c_dict: Dictionary = c_var
				var pid := str(c_dict.get("place_id", ""))
				if pid.is_empty():
					continue
				var has_routes := c_dict.has("routes")
				var compiled_by_id: Dictionary = {}
				var measures_by_id: Dictionary = {}
				var show_each_preview: bool = show_preview and not has_routes
				for a_entry in Neighbourhoods.areas_of(pid):
					if not _check_one_area(a_entry as Dictionary, show_each_preview, compiled_by_id, measures_by_id):
						any_failed = true

				if has_routes:
					for r_var in Neighbourhoods.routes_of(pid):
						var r_dict: Dictionary = r_var
						var r_id := str(r_dict.get("id", ""))
						var rp: Dictionary = CaricatureCheck.check_route(r_dict, compiled_by_id, measures_by_id)
						var rp_ok := bool(rp.get("ok", false))
						var rp_failed: Array = rp.get("failed_rules", [])
						var rp_status := "PASS" if rp_ok else ("FAIL " + ",".join(PackedStringArray(rp_failed)))
						print(
							"CARICATURE_ROUTE %s legs=%d landmarks=%d/%d end_signs=%d/2 %s" % [
								r_id,
								int(rp["legs"]),
								int(rp["landmarks_present"]),
								int(rp["landmarks_listed"]),
								int(rp["end_signs"]),
								rp_status,
							]
						)
						if not rp_ok:
							any_failed = true

					var cp: Dictionary = CaricatureCheck.check_city(pid, compiled_by_id)
					var cp_ok := bool(cp.get("ok", false))
					var cp_failed: Array = cp.get("failed_rules", [])
					var cp_status := "PASS" if cp_ok else ("FAIL " + ",".join(PackedStringArray(cp_failed)))
					var n_hoods := int(cp["neighbourhoods"])
					print(
						"CARICATURE_CITY %s neighbourhoods=%d routes=%d legs=%d openings_aligned=%d/%d connected=%d/%d %s" % [
							pid,
							n_hoods,
							int(cp["routes"]),
							int(cp["legs"]),
							int(cp["openings_aligned"]),
							int(cp["openings_total"]),
							int(cp["connected"]),
							n_hoods,
							cp_status,
						]
					)
					if not cp_ok:
						any_failed = true
					if show_preview:
						_print_city_preview(pid, compiled_by_id)

	Neighbourhoods.set_config_path_for_tests("")
	get_tree().quit(1 if any_failed else 0)

func _check_one_area(area: Dictionary, show_preview: bool, compiled_by_id: Dictionary, measures_by_id: Dictionary) -> bool:
	var area_id := str(area.get("id", ""))
	var is_route := (str(area.get("kind", "")) == "route" or area_id.begins_with("route:"))
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

	compiled_by_id[area_id] = compiled
	var m: Dictionary = CaricatureCheck.measure(compiled, area)
	measures_by_id[area_id] = m
	var w: int = int(compiled["w"])
	var h: int = int(compiled["h"])
	var passed: bool = bool(m.get("ok", false))
	var failed_rules: Array = m.get("failed_rules", [])
	var status_str := "PASS" if passed else ("FAIL " + ",".join(PackedStringArray(failed_rules)))

	if is_route:
		print(
			"CARICATURE %s size=%dx%d walkable=%d unreached=%d trapped=%d ends_steps=%d tall_grass=%.2f search_doors=%d %s" % [
				area_id,
				w,
				h,
				int(m["walkable"]),
				int(m["unreached"]),
				int(m["trapped"]),
				int(m["ends_steps"]),
				float(m["tall_grass_share"]),
				int(m["search_doors"]),
				status_str,
			]
		)
	else:
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

func _tile_char(compiled: Dictionary, x: int, y: int) -> String:
	var w: int = int(compiled["w"])
	var cls_buf: PackedByteArray = compiled["class"]
	var var_buf: PackedByteArray = compiled["variant"]
	var mask_buf: PackedByteArray = compiled["mask"]
	var lamp: Vector2i = compiled["lamp"]
	var arrival: Vector2i = compiled["arrival"]
	if x == lamp.x and y == lamp.y:
		return "L"
	if x == arrival.x and y == arrival.y:
		return "a"
	var idx: int = y * w + x
	var cls: int = cls_buf[idx]
	var v: int = var_buf[idx]
	var mask: int = mask_buf[idx]
	if cls == TileSynth2.TILE_STAMP:
		return "o" if TileSynth2.is_walkable(cls, v, mask) else "@"
	if cls == TileSynth2.TILE_LEDGE:
		if v == 0:
			return "v"
		if v == 1:
			return ">"
		return "<"
	if CLASS_TO_CHAR.has(cls):
		return str(CLASS_TO_CHAR[cls])
	return "?"

func _print_preview(compiled: Dictionary) -> void:
	var w: int = int(compiled["w"])
	var h: int = int(compiled["h"])
	for y in range(h):
		var chars := PackedStringArray()
		chars.resize(w)
		for x in range(w):
			chars[x] = _tile_char(compiled, x, y)
		print("PREVIEW:" + "".join(chars))

func _print_city_preview(place_id: String, compiled_by_id: Dictionary) -> void:
	var blocks: Array = []
	var first := true
	var min_gx := 0
	var min_gy := 0
	var max_gx := 0
	var max_gy := 0

	for a_var in Neighbourhoods.areas_of(place_id):
		var a: Dictionary = a_var
		var aid := str(a.get("id", ""))
		if not compiled_by_id.has(aid):
			continue
		var comp: Dictionary = compiled_by_id[aid]
		if not bool(comp.get("ok", false)):
			continue
		var orig: Vector2i = comp["origin"]
		var rows: int = int(comp["rows"])
		var w: int = int(comp["w"])
		var h: int = int(comp["h"])
		var gx0: int = orig.x * 32
		var gy0: int = (-(orig.y + rows - 1) - 1) * 32
		blocks.append({"comp": comp, "gx0": gx0, "gy0": gy0, "w": w, "h": h})
		if first:
			min_gx = gx0
			min_gy = gy0
			max_gx = gx0 + w
			max_gy = gy0 + h
			first = false
		else:
			min_gx = mini(min_gx, gx0)
			min_gy = mini(min_gy, gy0)
			max_gx = maxi(max_gx, gx0 + w)
			max_gy = maxi(max_gy, gy0 + h)

	if first:
		return
	var gw: int = max_gx - min_gx
	var gh: int = max_gy - min_gy
	var rows_buf: Array = []
	for _ry in range(gh):
		var line := PackedStringArray()
		line.resize(gw)
		line.fill(" ")
		rows_buf.append(line)

	for b in blocks:
		var comp: Dictionary = b["comp"]
		var dx0: int = int(b["gx0"]) - min_gx
		var dy0: int = int(b["gy0"]) - min_gy
		var bw: int = int(b["w"])
		var bh: int = int(b["h"])
		for y in range(bh):
			var row_arr: PackedStringArray = rows_buf[dy0 + y]
			for x in range(bw):
				row_arr[dx0 + x] = _tile_char(comp, x, y)
			rows_buf[dy0 + y] = row_arr

	for ry in range(gh):
		print("PREVIEW:" + "".join(rows_buf[ry] as PackedStringArray))
