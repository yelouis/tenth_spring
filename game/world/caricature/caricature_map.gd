class_name CaricatureMap
extends RefCounted

## game/world/caricature/caricature_map.gd — Caricature Map Compiler & Cell Formatter (Item 48a)
## Contract: docs/design_neighbourhoods_and_caricature.md §5,
##           docs/implementation_plan_dc_trial.md §2, §3

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const MapConstants := preload("res://world/map_constants.gd")
const CellClassifier := preload("res://world/cell_classifier.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")

const BORDER: int = 3

const TERRAIN_MAP: Dictionary = {
	".": {"cls": TileSynth2.TILE_GRASS, "var": 0},
	",": {"cls": TileSynth2.TILE_TALL_GRASS, "var": 0},
	"T": {"cls": TileSynth2.TILE_TREE, "var": 0},
	"~": {"cls": TileSynth2.TILE_WATER, "var": 0},
	":": {"cls": TileSynth2.TILE_SAND, "var": 0},
	"%": {"cls": TileSynth2.TILE_MARSH, "var": 0},
	"-": {"cls": TileSynth2.TILE_PATH, "var": 0},
	"=": {"cls": TileSynth2.TILE_ROAD, "var": 0},
	"R": {"cls": TileSynth2.TILE_RAIL, "var": 0},
	"B": {"cls": TileSynth2.TILE_BRIDGE, "var": 0},
	"#": {"cls": TileSynth2.TILE_PLAZA, "var": 0},
	"F": {"cls": TileSynth2.TILE_FENCE, "var": 0},
	"*": {"cls": TileSynth2.TILE_FLOWERS, "var": 0},
	"+": {"cls": TileSynth2.TILE_GRAVE, "var": 0},
	"c": {"cls": TileSynth2.TILE_CROP, "var": 0},
	"x": {"cls": TileSynth2.TILE_RUBBLE, "var": 0},
	"v": {"cls": TileSynth2.TILE_LEDGE, "var": 0},
	">": {"cls": TileSynth2.TILE_LEDGE, "var": 1},
	"<": {"cls": TileSynth2.TILE_LEDGE, "var": 2},
}

const BORDER_CHARS: Dictionary = {
	"T": true,
	"~": true,
	"F": true,
}

const ORDINARY_KINDS: Dictionary = {
	"house_s": {"w": 4, "h": 4},
	"house_m": {"w": 5, "h": 4},
	"block_8x7": {"w": 8, "h": 7, "standing_a": 86, "standing_b": 87, "ruined_a": 42, "ruined_b": 60},
	"block_6x11": {"w": 6, "h": 11, "standing_a": 88, "standing_b": 89, "ruined_a": 61, "ruined_b": 62},
	"block_9x9": {"w": 9, "h": 9, "standing_a": 90, "standing_b": 91, "ruined_a": 63, "ruined_b": 64},
	"block_11x13": {"w": 11, "h": 13, "standing_a": 92, "standing_b": 93, "ruined_a": 65, "ruined_b": 66},
	"block_16x14": {"w": 16, "h": 14, "standing_a": 94, "standing_b": 95, "ruined_a": 67, "ruined_b": 68},
	"block_23x14": {"w": 23, "h": 14, "standing_a": 96, "standing_b": 97, "ruined_a": 69, "ruined_b": 70},
}

const VALID_FATES: Dictionary = {
	"auto": true,
	"standing": true,
	"ruined": true,
	"gone": true,
}

static var _stamp_num_by_id: Dictionary = {}

static func _ensure_stamp_cache() -> void:
	# Rebuild whenever STAMP_TABLE size differs so Item 52 additions are picked up automatically
	if _stamp_num_by_id.size() == TileSynth2.STAMP_TABLE.size():
		return
	_stamp_num_by_id.clear()
	for k in TileSynth2.STAMP_TABLE.keys():
		var sdef: Dictionary = TileSynth2.STAMP_TABLE[k]
		var sid_str := str(sdef.get("id", ""))
		if not sid_str.is_empty():
			_stamp_num_by_id[sid_str] = int(k)

static func resolve_map_path(map_field: String) -> String:
	if map_field.begins_with("res://") or map_field.begins_with("user://"):
		return map_field
	return "res://data/caricature/" + map_field

static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CaricatureMap: map file not found at %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_error("CaricatureMap: empty or unreadable map file at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("CaricatureMap: invalid JSON root at %s" % path)
		return {}
	return parsed

static func _is_integral(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return float(v) == floor(float(v))
	return false

static func _cell_of_tile(origin: Vector2i, rows: int, x: int, y: int) -> Vector2i:
	return Vector2i(origin.x + int(x / 32), origin.y + rows - 1 - int(y / 32))

static func _global_col(origin: Vector2i, x: int) -> int:
	return origin.x * 32 + x

static func _screen_row(origin: Vector2i, rows: int, y: int) -> int:
	return (-(origin.y + rows - 1) - 1) * 32 + y

static func _seed_gy(origin: Vector2i, rows: int, y: int) -> int:
	var cy: int = origin.y + rows - 1 - int(y / 32)
	var ty: int = y % 32
	return cy * 32 + (31 - ty)

static func _fail_result(errors: Array[String], origin: Vector2i, cols: int, rows: int) -> Dictionary:
	return {
		"ok": false,
		"errors": errors,
		"w": cols * 32,
		"h": rows * 32,
		"origin": origin,
		"cols": cols,
		"rows": rows,
		"class": PackedByteArray(),
		"variant": PackedByteArray(),
		"mask": PackedByteArray(),
		"stamps": [],
		"signs": [],
		"doors": [],
		"placed_objects": [],
		"lamp": Vector2i.ZERO,
		"arrival": Vector2i.ZERO,
		"art_pending": 0,
	}

static func compile(area: Dictionary, map: Dictionary, world_seed: int = MapConstants.MAP_SEED) -> Dictionary:
	_ensure_stamp_cache()
	var errors: Array[String] = []

	var cells_var: Variant = area.get("cells", [1, 1])
	var cells_arr: Array = cells_var if cells_var is Array else [1, 1]
	var cols: int = int(cells_arr[0]) if cells_arr.size() >= 1 else 1
	var rows: int = int(cells_arr[1]) if cells_arr.size() >= 2 else 1
	var w: int = cols * 32
	var h: int = rows * 32
	var origin: Vector2i = Neighbourhoods.block_origin(area)
	var ruin_level: String = str(area.get("ruin_level", "near"))

	# Build lookup of roster landmarks by stamp id
	var roster_lm_by_stamp: Dictionary = {}
	var lms_var: Variant = area.get("landmarks", [])
	if lms_var is Array:
		for lm_var in lms_var:
			if lm_var is Dictionary:
				var lm: Dictionary = lm_var
				if lm.has("stamp"):
					roster_lm_by_stamp[str(lm.get("stamp", ""))] = lm

	# -------------------------------------------------------------
	# Step 1: Pre-tile structural checks (M1, M7, M3/M5 bounds, M2 row chars)
	# -------------------------------------------------------------
	if map.is_empty():
		errors.append("M1: map dictionary is empty")
		return _fail_result(errors, origin, cols, rows)

	var schema_v: Variant = map.get("schema", null)
	if not _is_integral(schema_v) or int(schema_v) != 1:
		errors.append("M1: schema must be 1")

	var map_id_v: Variant = map.get("id", null)
	if typeof(map_id_v) != TYPE_STRING:
		errors.append("M1: id must be a string")
	else:
		var map_id := str(map_id_v)
		if Neighbourhoods.area(map_id).is_empty() or (area.has("id") and map_id != str(area.get("id", ""))):
			errors.append("M1: id '%s' is not in the roster or does not match area" % map_id)

	var rows_v: Variant = map.get("rows", null)
	if not (rows_v is Array) or (rows_v as Array).size() != h:
		errors.append("M1: rows must have exactly %d strings" % h)
	else:
		var rows_arr: Array = rows_v
		for y in range(h):
			var r_v: Variant = rows_arr[y]
			if typeof(r_v) != TYPE_STRING or str(r_v).length() != w:
				errors.append("M1: row %d must be a string of length %d" % [y, w])
				break
			var r_str: String = r_v
			for x in range(w):
				var ch: String = r_str[x]
				if not TERRAIN_MAP.has(ch):
					errors.append("M1: invalid terrain character '%s' at (%d, %d)" % [ch, x, y])
					break
			if not errors.is_empty():
				break

	if not errors.is_empty():
		return _fail_result(errors, origin, cols, rows)

	# M2 check on border characters
	var map_rows: Array = map["rows"]
	for y in range(h):
		var r_str: String = map_rows[y]
		for x in range(w):
			if x < BORDER or x >= w - BORDER or y < BORDER or y >= h - BORDER:
				var ch: String = r_str[x]
				if not BORDER_CHARS.has(ch):
					errors.append("M2: border tile (%d, %d) has '%s', expected T, ~, or F" % [x, y, ch])
					break
		if not errors.is_empty():
			break

	# M5 bounds check on lamp
	var lamp_v: Variant = map.get("lamp", null)
	var lamp_pos := Vector2i.ZERO
	if not (lamp_v is Array) or (lamp_v as Array).size() != 2 or not _is_integral(lamp_v[0]) or not _is_integral(lamp_v[1]):
		errors.append("M5: lamp must be [x, y] integers")
	else:
		lamp_pos = Vector2i(int(lamp_v[0]), int(lamp_v[1]))
		var lamp_top_y: int = lamp_pos.y - 1
		var arr_y: int = lamp_pos.y + 1
		if lamp_pos.x < BORDER or lamp_pos.x >= w - BORDER or lamp_top_y < BORDER or arr_y >= h - BORDER:
			errors.append("M5: lamp (%d, %d) two tiles and south arrival tile must lie inside BORDER=%d" % [lamp_pos.x, lamp_pos.y, BORDER])

	# Parse & check objects (M7 + M3 + M4 object-object & object-lamp overlap)
	var objs_v: Variant = map.get("objects", [])
	var parsed_objs: Array[Dictionary] = []
	if not (objs_v is Array):
		errors.append("M7: objects must be an array")
	else:
		for obj_idx in range((objs_v as Array).size()):
			var ov: Variant = objs_v[obj_idx]
			if not (ov is Dictionary):
				errors.append("M7: object %d must be a dictionary" % obj_idx)
				continue
			var o: Dictionary = ov
			var at_v: Variant = o.get("at", null)
			if not (at_v is Array) or (at_v as Array).size() != 2 or not _is_integral(at_v[0]) or not _is_integral(at_v[1]):
				errors.append("M3: object %d missing valid 'at' [x, y]" % obj_idx)
				continue
			var x0 := int(at_v[0])
			var y0 := int(at_v[1])

			var has_stamp := o.has("stamp")
			var has_pending := o.has("pending")
			var has_kind := o.has("kind")
			var mode_count := (1 if has_stamp else 0) + (1 if has_pending else 0) + (1 if has_kind else 0)
			if mode_count != 1:
				errors.append("M7: object %d must specify exactly one of stamp, pending, or kind" % obj_idx)
				continue

			var ow := 0
			var oh := 0
			var is_decal := false
			var rec: Dictionary = {"x": x0, "y": y0, "raw": o}

			if has_stamp:
				var s_id := str(o.get("stamp", ""))
				if not _stamp_num_by_id.has(s_id):
					errors.append("M7: unknown stamp '%s' in STAMP_TABLE" % s_id)
					continue
				var s_num: int = _stamp_num_by_id[s_id]
				var s_def: Dictionary = TileSynth2.STAMP_TABLE[s_num]
				ow = int(s_def.get("w", 1))
				oh = int(s_def.get("h", 1))
				is_decal = (str(s_def.get("kind", "")) == "decal")
				rec["form"] = "stamp"
				rec["stamp_str"] = s_id
				rec["stamp_num"] = s_num
			elif has_pending:
				var p_id := str(o.get("pending", ""))
				if p_id.is_empty() or _stamp_num_by_id.has(p_id):
					errors.append("M7: pending id '%s' is empty or already exists in STAMP_TABLE" % p_id)
					continue
				var sz_v: Variant = o.get("size", null)
				if not (sz_v is Array) or (sz_v as Array).size() != 2 or not _is_integral(sz_v[0]) or not _is_integral(sz_v[1]):
					errors.append("M7: pending '%s' missing valid size [w, h]" % p_id)
					continue
				ow = int(sz_v[0])
				oh = int(sz_v[1])
				if ow < 1 or oh < 3:
					errors.append("M7: pending '%s' size [%d, %d] must have w >= 1 and h >= 3" % [p_id, ow, oh])
					continue
				var dc_v: Variant = o.get("door_col", null)
				var d_col: Variant = null
				if dc_v != null:
					if not _is_integral(dc_v) or int(dc_v) < 0 or int(dc_v) >= ow:
						errors.append("M7: pending '%s' invalid door_col %s" % [p_id, str(dc_v)])
						continue
					d_col = int(dc_v)
				rec["form"] = "pending"
				rec["pending_id"] = p_id
				rec["door_col"] = d_col
				rec["name"] = str(o.get("name", ""))
			else:
				var k_str := str(o.get("kind", ""))
				if not ORDINARY_KINDS.has(k_str):
					errors.append("M7: invalid ordinary building kind '%s'" % k_str)
					continue
				var fate_str := str(o.get("fate", "auto"))
				if not VALID_FATES.has(fate_str):
					errors.append("M7: invalid building fate '%s'" % fate_str)
					continue
				var k_spec: Dictionary = ORDINARY_KINDS[k_str]
				ow = int(k_spec["w"])
				oh = int(k_spec["h"])
				rec["form"] = "kind"
				rec["kind"] = k_str
				rec["fate"] = fate_str

			rec["w"] = ow
			rec["h"] = oh
			rec["is_decal"] = is_decal

			if x0 < BORDER or y0 < BORDER or x0 + ow > w - BORDER or y0 + oh > h - BORDER:
				errors.append("M3: object at (%d, %d) size %dx%d violates BORDER=%d" % [x0, y0, ow, oh, BORDER])
				continue

			parsed_objs.append(rec)

	# Validate signs structure
	var signs_v: Variant = map.get("signs", [])
	var explicit_signs: Array[Dictionary] = []
	if not (signs_v is Array):
		errors.append("M6: signs must be an array")
	else:
		for s_idx in range((signs_v as Array).size()):
			var sv: Variant = signs_v[s_idx]
			if not (sv is Dictionary):
				errors.append("M6: sign %d must be a dictionary" % s_idx)
				continue
			var s_dict: Dictionary = sv
			var sat_v: Variant = s_dict.get("at", null)
			if not (sat_v is Array) or (sat_v as Array).size() != 2 or not _is_integral(sat_v[0]) or not _is_integral(sat_v[1]):
				errors.append("M6: sign %d missing valid 'at' [x, y]" % s_idx)
				continue
			var sx := int(sat_v[0])
			var sy := int(sat_v[1])
			if sx < 0 or sx >= w or sy < 0 or sy >= h:
				errors.append("M6: sign (%d, %d) out of map bounds" % [sx, sy])
				continue
			explicit_signs.append({"x": sx, "y": sy, "text": str(s_dict.get("text", ""))})

	if not errors.is_empty():
		return _fail_result(errors, origin, cols, rows)

	# Check M4 overlaps among objects, lamp's two tiles, and explicit signs
	var lamp_tiles: Array[Vector2i] = [Vector2i(lamp_pos.x, lamp_pos.y - 1), lamp_pos]
	for i in range(parsed_objs.size()):
		var a: Dictionary = parsed_objs[i]
		var ax0: int = a["x"]
		var ay0: int = a["y"]
		var aw: int = a["w"]
		var ah: int = a["h"]

		for lt in lamp_tiles:
			if lt.x >= ax0 and lt.x < ax0 + aw and lt.y >= ay0 and lt.y < ay0 + ah:
				errors.append("M4: object at (%d, %d) covers lamp tile (%d, %d)" % [ax0, ay0, lt.x, lt.y])
		for es in explicit_signs:
			var sx: int = es["x"]
			var sy: int = es["y"]
			if sx >= ax0 and sx < ax0 + aw and sy >= ay0 and sy < ay0 + ah:
				errors.append("M4: object at (%d, %d) covers sign at (%d, %d)" % [ax0, ay0, sx, sy])
		for j in range(i + 1, parsed_objs.size()):
			var b: Dictionary = parsed_objs[j]
			if bool(a["is_decal"]) and bool(b["is_decal"]):
				continue
			var bx0: int = b["x"]
			var by0: int = b["y"]
			var bw: int = b["w"]
			var bh: int = b["h"]
			if ax0 < bx0 + bw and bx0 < ax0 + aw and ay0 < by0 + bh and by0 < ay0 + ah:
				errors.append("M4: objects at (%d, %d) and (%d, %d) overlap" % [ax0, ay0, bx0, by0])

	if not errors.is_empty():
		return _fail_result(errors, origin, cols, rows)

	# -------------------------------------------------------------
	# Step 2: Terrain
	# -------------------------------------------------------------
	var total: int = w * h
	var cls_buf := PackedByteArray()
	cls_buf.resize(total)
	cls_buf.fill(TileSynth2.TILE_VOID)

	var var_buf := PackedByteArray()
	var_buf.resize(total)
	var_buf.fill(0)

	var mask_buf := PackedByteArray()
	mask_buf.resize(total)
	mask_buf.fill(0)

	for y in range(h):
		var r_str: String = map_rows[y]
		for x in range(w):
			var ch: String = r_str[x]
			var spec: Dictionary = TERRAIN_MAP[ch]
			var idx: int = y * w + x
			cls_buf[idx] = int(spec["cls"])
			var_buf[idx] = int(spec["var"])

	# -------------------------------------------------------------
	# Step 3: Ground wear by ruin_level (§3.2 step 3)
	# -------------------------------------------------------------
	var path_thresh := 0.25
	var plaza_thresh := 0.50
	match ruin_level:
		"camp":
			path_thresh = 0.10
			plaza_thresh = 0.10
		"near":
			path_thresh = 0.25
			plaza_thresh = 0.50
		"mid":
			path_thresh = 0.40
			plaza_thresh = 0.50
		"far":
			path_thresh = 0.55
			plaza_thresh = 0.50

	for y in range(h):
		var gy: int = _seed_gy(origin, rows, y)
		for x in range(w):
			var idx: int = y * w + x
			var t_cls: int = cls_buf[idx]
			if t_cls == TileSynth2.TILE_PATH:
				var gx: int = _global_col(origin, x)
				if TileSynth2.u_rand(gx, gy, world_seed, TileSynth2.SALT_PATH_OVERGROWTH) < path_thresh:
					var_buf[idx] = 1
			elif t_cls == TileSynth2.TILE_PLAZA:
				var gx: int = _global_col(origin, x)
				if TileSynth2.u_rand(gx, gy, world_seed, TileSynth2.SALT_PLAZA_WEEDS) < plaza_thresh:
					var_buf[idx] = 1

	# -------------------------------------------------------------
	# Step 4: Objects in file order (§3.3, §3.4, §3.5)
	# -------------------------------------------------------------
	var stamps_out: Array[Dictionary] = []
	var doors_out: Array[Dictionary] = []
	var placed_objects: Array[Dictionary] = []
	var pending_sign_jobs: Array[Dictionary] = []
	var art_pending := 0

	for obj in parsed_objs:
		var form := str(obj["form"])
		var x0: int = obj["x"]
		var y0: int = obj["y"]
		var ow: int = obj["w"]
		var oh: int = obj["h"]

		if form == "stamp":
			var s_num: int = obj["stamp_num"]
			var s_str := str(obj["stamp_str"])
			var s_def: Dictionary = TileSynth2.STAMP_TABLE[s_num]
			var s_kind := str(s_def.get("kind", ""))
			var lm_meta: Dictionary = roster_lm_by_stamp.get(s_str, {})
			var lm_interior := str(lm_meta.get("interior", ""))
			var lm_name := str(lm_meta.get("name", ""))
			_write_stamp(
				s_num, s_def, x0, y0, origin, rows,
				0, false, false, lm_interior, lm_name,
				cls_buf, var_buf, mask_buf, w, stamps_out, doors_out
			)
			placed_objects.append({
				"form": "stamp",
				"stamp_str": s_str,
				"stamp_id": s_num,
				"kind": s_kind,
				"x": x0,
				"y": y0,
				"w": ow,
				"h": oh,
			})
		elif form == "pending":
			var p_id := str(obj["pending_id"])
			var d_col: Variant = obj["door_col"]
			var p_name := str(obj["name"])
			var lm_meta: Dictionary = roster_lm_by_stamp.get(p_id, {})
			var lm_interior := str(lm_meta.get("interior", ""))
			var roof_rows: int = oh - 2
			for ty in range(oh):
				for tx in range(ow):
					var idx: int = (y0 + ty) * w + (x0 + tx)
					if ty < roof_rows:
						cls_buf[idx] = TileSynth2.TILE_ROOF
						var_buf[idx] = 32
						mask_buf[idx] = 0
					elif ty == oh - 1 and d_col != null and tx == int(d_col):
						cls_buf[idx] = TileSynth2.TILE_DOOR
						var_buf[idx] = 32
						mask_buf[idx] = 0
					else:
						cls_buf[idx] = TileSynth2.TILE_WALL
						var_buf[idx] = 40 if (tx % 2 != 0) else 32
						mask_buf[idx] = 0
			art_pending += 1
			var door_x := -1
			var door_y := -1
			if d_col != null:
				door_x = x0 + int(d_col)
				door_y = y0 + oh - 1
				doors_out.append({
					"x": door_x,
					"y": door_y,
					"stamp_id": 0,
					"pending_id": p_id,
					"interior": lm_interior,
					"name": p_name,
					"is_ordinary": false,
				})
			placed_objects.append({
				"form": "pending",
				"pending_id": p_id,
				"x": x0,
				"y": y0,
				"w": ow,
				"h": oh,
				"has_door": d_col != null,
				"door_x": door_x,
				"door_y": door_y,
			})
			pending_sign_jobs.append({
				"x0": x0,
				"y0": y0,
				"w": ow,
				"h": oh,
				"text": p_name,
			})
		elif form == "kind":
			var k_str := str(obj["kind"])
			var fate := str(obj["fate"])
			var gx0: int = _global_col(origin, x0)
			var gy0: int = _seed_gy(origin, rows, y0)
			var is_block := k_str.begins_with("block_")

			if fate == "auto":
				var s_share := 50.0
				var r_share := 30.0
				if is_block:
					match ruin_level:
						"camp":
							s_share = 85.0
							r_share = 15.0
						"near":
							s_share = 75.0
							r_share = 20.0
						"mid":
							s_share = 70.0
							r_share = 22.0
						"far":
							s_share = 65.0
							r_share = 25.0
				else:
					match ruin_level:
						"camp":
							s_share = 70.0
							r_share = 20.0
						"near":
							s_share = 50.0
							r_share = 30.0
						"mid":
							s_share = 35.0
							r_share = 30.0
						"far":
							s_share = 25.0
							r_share = 30.0
				var f_val: float = TileSynth2.u_rand(gx0, gy0, world_seed, TileSynth2.SALT_BUILDING_FATE)
				if f_val < s_share / 100.0:
					fate = "standing"
				elif f_val < (s_share + r_share) / 100.0:
					fate = "ruined"
				else:
					fate = "gone"

			if is_block and fate == "gone":
				fate = "ruined"

			var d_col_house := 2
			if k_str == "house_s":
				d_col_house = 1 if TileSynth2.u_rand(gx0, gy0, world_seed, TileSynth2.SALT_DOOR_ROOF) < 0.5 else 2

			var c_draw: float = TileSynth2.u_rand(gx0, gy0, world_seed, TileSynth2.SALT_RUIN_COLOURWAY)
			var colour_ruin := 0
			if c_draw < 0.40:
				colour_ruin = 0
			elif c_draw < 0.60:
				colour_ruin = 1
			elif c_draw < 0.80:
				colour_ruin = 2
			else:
				colour_ruin = 3
			var colour_stand: int = clampi(floori(c_draw * 5.0), 0, 4)

			var chosen_sid := 71
			var door_color := 0
			var is_ruined_flag := false
			var is_ordinary_searchable := true

			if is_block:
				var k_spec: Dictionary = ORDINARY_KINDS[k_str]
				var design_a: bool = TileSynth2.u_rand(gx0, gy0, world_seed, TileSynth2.SALT_BLOCK_DESIGN) < 0.50
				if fate == "standing":
					chosen_sid = int(k_spec["standing_a"]) if design_a else int(k_spec["standing_b"])
					door_color = colour_stand
				else:
					chosen_sid = int(k_spec["ruined_a"]) if design_a else int(k_spec["ruined_b"])
					door_color = colour_ruin
					is_ruined_flag = true
			else:
				if fate == "standing":
					if k_str == "house_m":
						chosen_sid = 81 + colour_stand
					else:
						chosen_sid = (71 if d_col_house == 1 else 76) + colour_stand
					door_color = colour_stand
				elif fate == "ruined":
					var state_b_t := 0.50
					match ruin_level:
						"camp":
							state_b_t = 0.20
						"near":
							state_b_t = 0.50
						"mid":
							state_b_t = 0.75
						"far":
							state_b_t = 0.90
					var is_b: bool = TileSynth2.u_rand(gx0, gy0, world_seed, TileSynth2.SALT_RUIN_STATE) < state_b_t
					if k_str == "house_m":
						chosen_sid = (35 if is_b else 31) + colour_ruin
					elif d_col_house == 1:
						chosen_sid = (23 if is_b else 15) + colour_ruin
					else:
						chosen_sid = (27 if is_b else 19) + colour_ruin
					door_color = colour_ruin
					is_ruined_flag = true
				else:
					is_ordinary_searchable = false
					if k_str == "house_m":
						chosen_sid = 41
					elif d_col_house == 1:
						chosen_sid = 39
					else:
						chosen_sid = 40

			var s_def: Dictionary = TileSynth2.STAMP_TABLE[chosen_sid]
			_write_stamp(
				chosen_sid, s_def, x0, y0, origin, rows,
				door_color, is_ruined_flag, is_ordinary_searchable, "", "",
				cls_buf, var_buf, mask_buf, w, stamps_out, doors_out
			)
			placed_objects.append({
				"form": "kind",
				"kind": k_str,
				"fate": fate,
				"stamp_id": chosen_sid,
				"x": x0,
				"y": y0,
				"w": ow,
				"h": oh,
			})

	# -------------------------------------------------------------
	# Step 5: The lamp (§3.6) and signs (§3.7)
	# -------------------------------------------------------------
	var cell_sign_lists: Dictionary = {} # Vector2i -> Array[String]
	var signs_out: Array[Dictionary] = []
	var placed_sign_coords: Dictionary = {} # Vector2i -> true
	var arrival_pos := Vector2i(lamp_pos.x, lamp_pos.y + 1)

	if _stamp_num_by_id.has("waypost_lamp"):
		var lamp_sid: int = _stamp_num_by_id["waypost_lamp"]
		var lamp_def: Dictionary = TileSynth2.STAMP_TABLE[lamp_sid]
		_write_stamp(
			lamp_sid, lamp_def, lamp_pos.x, lamp_pos.y - 1, origin, rows,
			0, false, false, "", "",
			cls_buf, var_buf, mask_buf, w, stamps_out, doors_out
		)
	else:
		# Until waypost_lamp exists (Item 52), lamp tile is class SIGN with text "Waypost lamp"
		var l_idx: int = lamp_pos.y * w + lamp_pos.x
		if not TileSynth2.is_walkable(cls_buf[l_idx], var_buf[l_idx], mask_buf[l_idx]):
			errors.append("M5: lamp tile (%d, %d) is not walkable terrain" % [lamp_pos.x, lamp_pos.y])
		else:
			_append_sign_at(
				lamp_pos.x, lamp_pos.y, "Waypost lamp", false,
				origin, rows, w, cls_buf, var_buf, mask_buf,
				cell_sign_lists, signs_out, placed_sign_coords
			)

	# Explicit signs in file order
	for es in explicit_signs:
		var sx: int = es["x"]
		var sy: int = es["y"]
		var stext := str(es["text"])
		var spos := Vector2i(sx, sy)
		if spos == Vector2i(lamp_pos.x, lamp_pos.y - 1) or spos == lamp_pos:
			errors.append("M4: sign at (%d, %d) covers lamp tile" % [sx, sy])
			continue
		if placed_sign_coords.has(spos):
			errors.append("M6: duplicate sign at (%d, %d)" % [sx, sy])
			continue
		var s_idx: int = sy * w + sx
		if sx < BORDER or sx >= w - BORDER or sy < BORDER or sy >= h - BORDER or not TileSynth2.is_walkable(cls_buf[s_idx], var_buf[s_idx], mask_buf[s_idx]):
			errors.append("M6: sign at (%d, %d) is not on walkable terrain" % [sx, sy])
			continue
		_append_sign_at(
			sx, sy, stext, true,
			origin, rows, w, cls_buf, var_buf, mask_buf,
			cell_sign_lists, signs_out, placed_sign_coords
		)

	# Stand-in signs (§3.4): (x0 - 1, y0 + h) if walkable terrain, else (x0 + w, y0 + h), else M6 error
	for pjob in pending_sign_jobs:
		var px0: int = pjob["x0"]
		var py0: int = pjob["y0"]
		var pw: int = pjob["w"]
		var ph: int = pjob["h"]
		var ptext := str(pjob["text"])
		var cands: Array[Vector2i] = [
			Vector2i(px0 - 1, py0 + ph),
			Vector2i(px0 + pw, py0 + ph),
		]
		var chosen := Vector2i(-1, -1)
		for cand in cands:
			if cand.x < BORDER or cand.x >= w - BORDER or cand.y < BORDER or cand.y >= h - BORDER:
				continue
			if cand == Vector2i(lamp_pos.x, lamp_pos.y - 1) or cand == lamp_pos or cand == arrival_pos:
				continue
			if placed_sign_coords.has(cand):
				continue
			var covered_by_obj := false
			for po_chk in parsed_objs:
				var ox: int = po_chk["x"]
				var oy: int = po_chk["y"]
				var ow2: int = po_chk["w"]
				var oh2: int = po_chk["h"]
				if cand.x >= ox and cand.x < ox + ow2 and cand.y >= oy and cand.y < oy + oh2:
					covered_by_obj = true
					break
			if covered_by_obj:
				continue
			var c_idx: int = cand.y * w + cand.x
			if TileSynth2.is_walkable(cls_buf[c_idx], var_buf[c_idx], mask_buf[c_idx]):
				chosen = cand
				break
		if chosen.x < 0:
			errors.append("M6: stand-in '%s' at (%d, %d) has neither SW nor SE sign tile walkable" % [ptext, px0, py0])
		else:
			_append_sign_at(
				chosen.x, chosen.y, ptext, false,
				origin, rows, w, cls_buf, var_buf, mask_buf,
				cell_sign_lists, signs_out, placed_sign_coords
			)

	# -------------------------------------------------------------
	# Step 6: Post-grid checks (M2, M5 arrival walkability, M8 door south walkability)
	# -------------------------------------------------------------
	for y in range(h):
		for x in range(w):
			if x < BORDER or x >= w - BORDER or y < BORDER or y >= h - BORDER:
				var b_cls: int = cls_buf[y * w + x]
				if b_cls != TileSynth2.TILE_TREE and b_cls != TileSynth2.TILE_WATER and b_cls != TileSynth2.TILE_FENCE:
					errors.append("M2: finished border tile (%d, %d) is class %d" % [x, y, b_cls])
					break
		if not errors.is_empty():
			break

	var arr_idx: int = arrival_pos.y * w + arrival_pos.x
	if not TileSynth2.is_walkable(cls_buf[arr_idx], var_buf[arr_idx], mask_buf[arr_idx]):
		errors.append("M5: tile south of lamp (%d, %d) is not walkable" % [arrival_pos.x, arrival_pos.y])

	for d in doors_out:
		var dx: int = d["x"]
		var dy: int = d["y"]
		var sy: int = dy + 1
		if sy < BORDER or sy >= h - BORDER:
			errors.append("M8: tile south of door (%d, %d) is outside interior bounds" % [dx, dy])
		else:
			var s_idx: int = sy * w + dx
			if not TileSynth2.is_walkable(cls_buf[s_idx], var_buf[s_idx], mask_buf[s_idx]):
				errors.append("M8: tile south of door (%d, %d) is not walkable" % [dx, dy])

	if not errors.is_empty():
		return _fail_result(errors, origin, cols, rows)

	return {
		"ok": true,
		"errors": errors,
		"w": w,
		"h": h,
		"origin": origin,
		"cols": cols,
		"rows": rows,
		"class": cls_buf,
		"variant": var_buf,
		"mask": mask_buf,
		"stamps": stamps_out,
		"signs": signs_out,
		"cell_signs": cell_sign_lists,
		"doors": doors_out,
		"placed_objects": placed_objects,
		"lamp": lamp_pos,
		"arrival": arrival_pos,
		"art_pending": art_pending,
		"world_seed": world_seed,
	}

static func _append_sign_at(
	sx: int,
	sy: int,
	text: String,
	is_feature_candidate: bool,
	origin: Vector2i,
	rows: int,
	w: int,
	cls_buf: PackedByteArray,
	var_buf: PackedByteArray,
	mask_buf: PackedByteArray,
	cell_sign_lists: Dictionary,
	signs_out: Array[Dictionary],
	placed_sign_coords: Dictionary
) -> void:
	var cell := _cell_of_tile(origin, rows, sx, sy)
	if not cell_sign_lists.has(cell):
		cell_sign_lists[cell] = []
	var arr: Array = cell_sign_lists[cell]
	var s_variant: int = arr.size()
	arr.append(text)
	var idx: int = sy * w + sx
	cls_buf[idx] = TileSynth2.TILE_SIGN
	var_buf[idx] = s_variant
	mask_buf[idx] = 0
	placed_sign_coords[Vector2i(sx, sy)] = true
	signs_out.append({
		"x": sx,
		"y": sy,
		"cell": cell,
		"index": s_variant,
		"text": text,
		"is_explicit": is_feature_candidate,
	})

static func _write_stamp(
	stamp_num: int,
	s_def: Dictionary,
	x0: int,
	y0: int,
	origin: Vector2i,
	rows: int,
	door_color: int,
	is_ruined: bool,
	is_ordinary_searchable: bool,
	lm_interior: String,
	lm_name: String,
	cls_buf: PackedByteArray,
	var_buf: PackedByteArray,
	mask_buf: PackedByteArray,
	map_w: int,
	stamps_out: Array[Dictionary],
	doors_out: Array[Dictionary]
) -> void:
	var sw: int = int(s_def.get("w", 1))
	var sh: int = int(s_def.get("h", 1))
	var base_rows: int = int(s_def.get("base_rows", sh))
	var s_kind := str(s_def.get("kind", ""))

	if s_kind == "landmark" or s_kind == "prop":
		var tiles_arr: Array = s_def.get("tiles", [])
		var door_v: Variant = s_def.get("door", null)
		var has_door: bool = (door_v is Array and (door_v as Array).size() == 2)
		var d_col: int = int(door_v[0]) if has_door else -1
		var d_row: int = int(door_v[1]) if has_door else -1
		for ty in range(sh):
			var r_str: String = str(tiles_arr[ty]) if ty < tiles_arr.size() else ""
			for tx in range(sw):
				var idx: int = (y0 + ty) * map_w + (x0 + tx)
				var ch: String = r_str[tx] if tx < r_str.length() else "."
				if has_door and tx == d_col and ty == d_row:
					cls_buf[idx] = TileSynth2.TILE_DOOR
					var_buf[idx] = 32
					mask_buf[idx] = stamp_num
					doors_out.append({
						"x": x0 + tx,
						"y": y0 + ty,
						"stamp_id": stamp_num,
						"interior": lm_interior,
						"name": lm_name,
						"is_ordinary": false,
					})
				elif ch == "#":
					cls_buf[idx] = TileSynth2.TILE_STAMP
					var_buf[idx] = stamp_num
					mask_buf[idx] = TileSynth2.STAMP_FLAG_SOLID
				elif ch == "+":
					cls_buf[idx] = TileSynth2.TILE_STAMP
					var_buf[idx] = stamp_num
					mask_buf[idx] = 0 if ty >= sh - base_rows else TileSynth2.STAMP_FLAG_OVERHANG
				# "." leaves terrain drawn underneath untouched
	elif s_kind == "decal":
		var d_mask: int = TileSynth2.STAMP_FLAG_SOLID if (stamp_num == 47 or stamp_num == 57) else 0
		for ty in range(sh):
			for tx in range(sw):
				var idx: int = (y0 + ty) * map_w + (x0 + tx)
				cls_buf[idx] = TileSynth2.TILE_STAMP
				var_buf[idx] = stamp_num
				mask_buf[idx] = d_mask
	else:
		# house, shell, block
		var door_cols: Array[int] = []
		if s_kind != "shell":
			if s_def.has("door_cols") and s_def["door_cols"] is Array:
				for dc in s_def["door_cols"]:
					door_cols.append(int(dc))
			elif s_def.get("door", null) is Array:
				door_cols.append(int(s_def["door"][0]))
		var d_var: int = (16 + door_color) if is_ruined else door_color
		for ty in range(sh):
			for tx in range(sw):
				var idx: int = (y0 + ty) * map_w + (x0 + tx)
				if ty == sh - 1 and tx in door_cols:
					cls_buf[idx] = TileSynth2.TILE_DOOR
					var_buf[idx] = d_var
					mask_buf[idx] = stamp_num
					doors_out.append({
						"x": x0 + tx,
						"y": y0 + ty,
						"stamp_id": stamp_num,
						"interior": "",
						"name": "",
						"is_ordinary": is_ordinary_searchable,
					})
				else:
					cls_buf[idx] = TileSynth2.TILE_STAMP
					var_buf[idx] = stamp_num
					mask_buf[idx] = TileSynth2.STAMP_FLAG_SOLID

	stamps_out.append({
		"stamp_id": stamp_num,
		"anchor_gx": _global_col(origin, x0),
		"anchor_gy": _screen_row(origin, rows, y0),
		"w": sw,
		"h": sh,
	})

static func cell_result(compiled: Dictionary, cell: Vector2i, area: Dictionary) -> Dictionary:
	var w: int = int(compiled["w"])
	var h: int = int(compiled["h"])
	var origin: Vector2i = compiled["origin"]
	var rows: int = int(compiled["rows"])
	var world_seed: int = int(compiled.get("world_seed", MapConstants.MAP_SEED))
	var cls_src: PackedByteArray = compiled["class"]
	var var_src: PackedByteArray = compiled["variant"]
	var mask_src: PackedByteArray = compiled["mask"]

	var base_x: int = (cell.x - origin.x) * 32
	var base_y: int = (origin.y + rows - 1 - cell.y) * 32

	var total_work: int = TileSynth2.WORK_SIZE * TileSynth2.WORK_SIZE
	var grid_class := PackedByteArray()
	grid_class.resize(total_work)
	grid_class.fill(TileSynth2.TILE_VOID)

	var grid_variant := PackedByteArray()
	grid_variant.resize(total_work)
	grid_variant.fill(0)

	var grid_mask := PackedByteArray()
	grid_mask.resize(total_work)
	grid_mask.fill(0)

	for r in range(TileSynth2.WORK_SIZE):
		var my: int = base_y + (r - 4)
		if my < 0 or my >= h:
			continue
		for c in range(TileSynth2.WORK_SIZE):
			var mx: int = base_x + (c - 4)
			if mx < 0 or mx >= w:
				continue
			var src_idx: int = my * w + mx
			var dst_idx: int = r * TileSynth2.WORK_SIZE + c
			grid_class[dst_idx] = cls_src[src_idx]
			grid_variant[dst_idx] = var_src[src_idx]
			grid_mask[dst_idx] = mask_src[src_idx]

	var ruin_level := str(area.get("ruin_level", "near"))
	var road_v1_thresh := 0.20
	match ruin_level:
		"camp":
			road_v1_thresh = 0.10
		"near":
			road_v1_thresh = 0.20
		"mid":
			road_v1_thresh = 0.35
		"far":
			road_v1_thresh = 0.50

	var output := TileSynth2.finalize_cell_output(
		cell.x, cell.y, grid_class, grid_variant, grid_mask, world_seed, road_v1_thresh
	)

	# Gather every compiled stamp whose box touches this cell (§3.8 step 4, tile_synth2.gd:1664)
	var cell_stamps: Array[Dictionary] = []
	var all_stamps: Array = compiled.get("stamps", [])
	var cell_c0: int = cell.x * 32
	var cell_r0: int = (-cell.y - 1) * 32
	for s_var in all_stamps:
		var s: Dictionary = s_var
		var agx: int = int(s["anchor_gx"])
		var agy: int = int(s["anchor_gy"])
		var sw: int = int(s["w"])
		var sh: int = int(s["h"])
		if agx + sw > cell_c0 and agx < cell_c0 + 32 and agy + sh > cell_r0 and agy < cell_r0 + 32:
			cell_stamps.append({
				"stamp_id": int(s["stamp_id"]),
				"anchor_gx": agx,
				"anchor_gy": agy,
				"w": sw,
				"h": sh,
			})

	cell_stamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay: int = int(a["anchor_gy"]) + int(a["h"])
		var by: int = int(b["anchor_gy"]) + int(b["h"])
		if ay != by:
			return ay < by
		if int(a["anchor_gx"]) != int(b["anchor_gx"]):
			return int(a["anchor_gx"]) < int(b["anchor_gx"])
		return int(a["stamp_id"]) < int(b["stamp_id"])
	)

	var cell_signs_map: Dictionary = compiled.get("cell_signs", {})
	var signs_arr: Array = cell_signs_map.get(cell, [])

	var place_id := str(area.get("place_id", ""))
	var is_camp := (str(area.get("kind", "")) == "camp" or str(area.get("id", "")).begins_with("camp:"))
	var zone_str := "residential" if is_camp else str(area.get("zone", "residential"))
	var ghost_base := 0.0 if is_camp else float(CellClassifier.ZONE_BASE_GHOST_SHARE.get(zone_str, 0.05))
	var reg_info := CellClassifier.resolve_region_and_place(cell.x, cell.y, place_id)
	var region_str := str(reg_info.get("region", "South Atlantic"))
	var biome_str := CellClassifier.place_baseline_biome(place_id)

	var lm_ids_in_cell: Array = []
	var doors_arr: Array = compiled.get("doors", [])
	for d_var in doors_arr:
		var d: Dictionary = d_var
		var iid := str(d.get("interior", ""))
		if iid.is_empty():
			continue
		var d_cell := _cell_of_tile(origin, rows, int(d["x"]), int(d["y"]))
		if d_cell == cell and not lm_ids_in_cell.has(iid):
			lm_ids_in_cell.append(iid)

	return {
		"tiles": output,
		"signs": PackedStringArray(signs_arr),
		"stamps": cell_stamps,
		"zone": zone_str,
		"biome": biome_str,
		"region": region_str,
		"ghost_base": ghost_base,
		"stats": {
			"building_candidates": 0,
			"buildings_placed": 0,
			"fallback_placed": 0,
			"landmarks_placed": 0,
			"landmarks_sign_only": 0,
			"landmark_ids_placed": lm_ids_in_cell,
			"ordinary_standing": 0,
			"ordinary_ruined": 0,
			"ordinary_gone": 0,
		},
	}
