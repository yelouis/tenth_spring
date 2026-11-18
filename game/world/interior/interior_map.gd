class_name InteriorMap
extends RefCounted

## game/world/interior/interior_map.gd — Interior JSON Loader, Registry & Floor Compiler (Item 57)
## Contract: docs/implementation_plan_dc_trial.md §11.3 C & docs/design_neighbourhoods_and_caricature.md §7.7

const InteriorTiles := preload("res://world/interior/interior_tiles.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

const DC_INTERIOR_DIR := "res://data/interiors/washington-dc"
const MIN_WIDTH: int = 12
const MIN_HEIGHT: int = 10

const CAPSTONE_STAMP_IDS: Dictionary = {
	119: true, # int_obs_slit_window
	122: true, # int_radio_console
	127: true, # int_calder_cipher_desk
	130: true, # int_cobalion_dais
	132: true, # int_keystone_pedestal
}

static var _stamp_num_by_id: Dictionary = {}

static func _ensure_stamp_lookup() -> void:
	if _stamp_num_by_id.size() == TileSynth2.STAMP_TABLE.size():
		return
	_stamp_num_by_id.clear()
	for k in TileSynth2.STAMP_TABLE.keys():
		var sdef: Dictionary = TileSynth2.STAMP_TABLE[k]
		var aid := str(sdef.get("id", ""))
		if not aid.is_empty():
			_stamp_num_by_id[aid] = int(k)

static func resolve_stamp_id(raw_stamp: Variant) -> int:
	_ensure_stamp_lookup()
	if typeof(raw_stamp) == TYPE_INT or (typeof(raw_stamp) == TYPE_FLOAT and float(raw_stamp) == floor(float(raw_stamp))):
		var sid := int(raw_stamp)
		if sid >= 1 and sid <= 134 and TileSynth2.STAMP_TABLE.has(sid):
			return sid
		return -1
	if typeof(raw_stamp) == TYPE_STRING:
		var s := str(raw_stamp).strip_edges()
		if s.is_valid_int():
			var sid_s := s.to_int()
			if sid_s >= 1 and sid_s <= 134 and TileSynth2.STAMP_TABLE.has(sid_s):
				return sid_s
			return -1
		return int(_stamp_num_by_id.get(s, -1))
	return -1

static func list_dc_interior_paths() -> Array[String]:
	var files := [
		"washington-monument.json",
		"air-and-space.json",
		"library-of-congress.json",
		"lincoln-memorial.json",
		"georgetown-ruins.json",
		"woodley-vet.json",
	]
	var out: Array[String] = []
	for fn in files:
		var p: String = DC_INTERIOR_DIR + "/" + str(fn)
		if FileAccess.file_exists(p):
			out.append(p)
	return out

static func resolve_interior_path(interior_key: String) -> String:
	var k := interior_key.strip_edges()
	if k.is_empty():
		return ""
	if k.begins_with("res://") or k.begins_with("user://"):
		return k if FileAccess.file_exists(k) else ""
	var slug := k
	if slug.begins_with("dc:"):
		slug = slug.trim_prefix("dc:")
	elif slug.begins_with("washington-dc:"):
		slug = slug.trim_prefix("washington-dc:")
	if slug.ends_with(".json"):
		slug = slug.trim_suffix(".json")
	var direct := DC_INTERIOR_DIR + "/" + slug + ".json"
	if FileAccess.file_exists(direct):
		return direct
	for p in list_dc_interior_paths():
		var doc := load_json(p)
		if str(doc.get("id", "")) == k:
			return p
	return ""

static func load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

static func _is_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return float(v) == floor(float(v))
	return false

static func _parse_vec2i(v: Variant) -> Variant:
	if v is Array and (v as Array).size() == 2:
		var a: Array = v
		if _is_int(a[0]) and _is_int(a[1]):
			return Vector2i(int(a[0]), int(a[1]))
	return null

static func compile(doc: Dictionary) -> Dictionary:
	_ensure_stamp_lookup()
	var rule_errors: Dictionary = {
		"I1": [],
		"I2": [],
		"I3": [],
		"I4": [],
		"I5": [],
		"I6": [],
	}
	var interior_id := str(doc.get("id", "unknown"))
	var area_id := str(doc.get("area_id", ""))
	var title := str(doc.get("title", interior_id))
	var atmosphere := str(doc.get("atmosphere", "normal"))
	var art_pending := 0
	var total_stamps := 0

	var floors_v: Variant = doc.get("floors", null)
	if not (floors_v is Array) or (floors_v as Array).is_empty():
		(rule_errors["I1"] as Array).append("floors must be a non-empty array")
		return {
			"ok": false,
			"id": interior_id,
			"area_id": area_id,
			"title": title,
			"atmosphere": atmosphere,
			"floors": [],
			"floor_by_id": {},
			"total_stamps": 0,
			"art_pending": 0,
			"rule_errors": rule_errors,
		}

	var floors_raw: Array = floors_v
	var compiled_floors: Array[Dictionary] = []
	var floor_by_id: Dictionary = {}

	for f_idx in range(floors_raw.size()):
		var f_v: Variant = floors_raw[f_idx]
		if not (f_v is Dictionary):
			(rule_errors["I1"] as Array).append("floor %d is not a dictionary" % f_idx)
			continue
		var fd: Dictionary = f_v
		var fid := str(fd.get("floor_id", str(f_idx)))
		var label := str(fd.get("label", fid))
		var theme := str(fd.get("theme", "stone"))
		var kit := str(fd.get("kit", "")).strip_edges()
		if not kit.is_empty() and not InteriorTiles.has_kit(kit):
			(rule_errors["I6"] as Array).append("floor %s unknown kit '%s'" % [fid, kit])
		var w_v: Variant = fd.get("width", 0)
		var h_v: Variant = fd.get("height", 0)
		if not _is_int(w_v) or not _is_int(h_v):
			(rule_errors["I1"] as Array).append("floor %s width/height must be integers" % fid)
			continue
		var w := int(w_v)
		var h := int(h_v)
		if w < MIN_WIDTH or h < MIN_HEIGHT:
			(rule_errors["I1"] as Array).append("floor %s size %dx%d < minimum %dx%d" % [fid, w, h, MIN_WIDTH, MIN_HEIGHT])

		var grid_v: Variant = fd.get("grid", null)
		var grid_ok := true
		if not (grid_v is Array) or (grid_v as Array).size() != h:
			(rule_errors["I1"] as Array).append("floor %s grid row count does not match height %d" % [fid, h])
			grid_ok = false
		var tiles := PackedByteArray()
		tiles.resize(maxi(1, w * h))
		tiles.fill(InteriorTiles.TILE_INT_VOID_BLACK)
		var door_mats: Array[Vector2i] = []

		if grid_ok:
			var grid_arr: Array = grid_v
			for y in range(h):
				var row_v: Variant = grid_arr[y]
				if typeof(row_v) != TYPE_STRING or str(row_v).length() != w:
					(rule_errors["I1"] as Array).append("floor %s row %d length != width %d" % [fid, y, w])
					grid_ok = false
					break
				var r_str: String = row_v
				for x in range(w):
					var ch: String = r_str[x]
					if not InteriorTiles.TOKEN_TO_CLASS.has(ch):
						(rule_errors["I2"] as Array).append("floor %s unknown token '%s' at (%d,%d)" % [fid, ch, x, y])
						tiles[y * w + x] = InteriorTiles.TILE_INT_VOID_BLACK
					else:
						var cls: int = int(InteriorTiles.TOKEN_TO_CLASS[ch])
						tiles[y * w + x] = cls
						if cls == InteriorTiles.TILE_INT_DOOR_MAT:
							door_mats.append(Vector2i(x, y))

		if f_idx == 0 and grid_ok and door_mats.is_empty():
			(rule_errors["I2"] as Array).append("ground floor %s has no door_mat ('D')" % fid)

		var stamps_compiled: Array[Dictionary] = []
		var stamps_v: Variant = fd.get("stamps", [])
		if stamps_v is Array:
			for st_v in (stamps_v as Array):
				if not (st_v is Dictionary):
					continue
				var std: Dictionary = st_v
				if str(std.get("art", "")) == "pending":
					art_pending += 1
					(rule_errors["I6"] as Array).append("floor %s stamp has art=pending" % fid)
				var sid := resolve_stamp_id(std.get("stamp", null))
				if sid < 1 or sid > 134:
					(rule_errors["I6"] as Array).append("floor %s invalid stamp '%s' (outside 1..134)" % [fid, str(std.get("stamp", ""))])
					continue
				var at_p: Variant = _parse_vec2i(std.get("at", null))
				if not (at_p is Vector2i):
					(rule_errors["I5"] as Array).append("floor %s stamp %d invalid 'at'" % [fid, sid])
					continue
				var sdef: Dictionary = TileSynth2.get_stamp_def(sid)
				var sw := int(sdef.get("w", 1))
				var sh := int(sdef.get("h", 1))
				var sbase := int(sdef.get("base_rows", sh))
				var gate_id := str(std.get("gate_id", ""))
				var clearable := bool(std.get("clearable", false))
				var capstone := bool(std.get("capstone", CAPSTONE_STAMP_IDS.has(sid)))
				stamps_compiled.append({
					"stamp_id": sid,
					"id": str(sdef.get("id", "")),
					"path": str(sdef.get("path", "")),
					"at": at_p as Vector2i,
					"w": sw,
					"h": sh,
					"base_rows": sbase,
					"gate_id": gate_id,
					"clearable": clearable,
					"capstone": capstone,
				})
				total_stamps += 1

		var stairs_arr: Array[Dictionary] = []
		for sv in (fd.get("stairs", []) as Array):
			if sv is Dictionary:
				var sd: Dictionary = sv
				if str(sd.get("art", "")) == "pending":
					art_pending += 1
					(rule_errors["I6"] as Array).append("floor %s stair has art=pending" % fid)
				stairs_arr.append(sd)

		var warps_arr: Array[Dictionary] = []
		for wv in (fd.get("warps", []) as Array):
			if wv is Dictionary:
				var wd: Dictionary = wv
				if str(wd.get("art", "")) == "pending":
					art_pending += 1
					(rule_errors["I6"] as Array).append("floor %s warp has art=pending" % fid)
				warps_arr.append(wd)

		var switches_arr: Array[Dictionary] = []
		for swv in (fd.get("switches", []) as Array):
			if swv is Dictionary:
				switches_arr.append(swv as Dictionary)

		var npcs_arr: Array[Dictionary] = []
		for nv in (fd.get("npcs", []) as Array):
			if nv is Dictionary:
				var nd: Dictionary = nv
				if str(nd.get("art", "")) == "pending":
					art_pending += 1
					(rule_errors["I6"] as Array).append("floor %s npc has art=pending" % fid)
				npcs_arr.append(nd)

		var items_arr: Array[Dictionary] = []
		for iv in (fd.get("items", []) as Array):
			if iv is Dictionary:
				items_arr.append(iv as Dictionary)

		var signs_arr: Array[Dictionary] = []
		for sgv in (fd.get("signs", []) as Array):
			if sgv is Dictionary:
				signs_arr.append(sgv as Dictionary)

		var fixtures_compiled: Array[Dictionary] = []
		var fixtures_v: Variant = fd.get("fixtures", [])
		if fixtures_v is Array:
			for fx_v in (fixtures_v as Array):
				if not (fx_v is Dictionary):
					continue
				var fxd := fx_v as Dictionary
				if str(fxd.get("art", "")) == "pending":
					art_pending += 1
					(rule_errors["I6"] as Array).append("floor %s fixture has art=pending" % fid)
				var fx_id := str(fxd.get("fixture", "")).strip_edges()
				if fx_id.is_empty() or not InteriorTiles.has_fixture(fx_id):
					(rule_errors["I6"] as Array).append("floor %s invalid fixture '%s'" % [fid, fx_id])
					continue
				var at_fx: Variant = _parse_vec2i(fxd.get("at", null))
				if not (at_fx is Vector2i):
					(rule_errors["I5"] as Array).append("floor %s fixture %s invalid 'at'" % [fid, fx_id])
					continue
				var fdef := InteriorTiles.get_fixture_def(fx_id)
				fixtures_compiled.append({
					"fixture": fx_id,
					"at": at_fx as Vector2i,
					"w": int(fdef.get("w", 1)),
					"h": int(fdef.get("h", 1)),
					"base_rows": int(fdef.get("base_rows", 1)),
					"layer": str(fdef.get("layer", "l1")),
				})

		var cf := {
			"index": f_idx,
			"floor_id": fid,
			"label": label,
			"theme": theme,
			"kit": kit,
			"w": w,
			"h": h,
			"grid_ok": grid_ok,
			"tiles": tiles,
			"door_mats": door_mats,
			"stamps": stamps_compiled,
			"fixtures": fixtures_compiled,
			"stairs": stairs_arr,
			"warps": warps_arr,
			"switches": switches_arr,
			"npcs": npcs_arr,
			"items": items_arr,
			"signs": signs_arr,
		}
		compiled_floors.append(cf)
		floor_by_id[fid] = f_idx

	return {
		"ok": true,
		"id": interior_id,
		"area_id": area_id,
		"title": title,
		"atmosphere": atmosphere,
		"floors": compiled_floors,
		"floor_by_id": floor_by_id,
		"total_stamps": total_stamps,
		"art_pending": art_pending,
		"rule_errors": rule_errors,
	}
