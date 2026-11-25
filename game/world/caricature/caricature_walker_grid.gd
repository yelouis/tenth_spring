class_name CaricatureWalkerGrid
extends RefCounted

## game/world/caricature/caricature_walker_grid.gd — Shared Runtime Walkability & Seam Oracle (Items 69–70)
## Shares CaricatureCheck._in_play_bounds, TileSynth2.is_walkable, solid_mask, TileSynth2.can_jump_ledge,
## and CaricatureCheck's 22-link opening seam alignment across all 21 Washington DC maps.
## Contract: docs/implementation_plan_travel_and_time.md §(d), §(e), §(i)

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")

var _place_id: String = ""
var _compiled_by_area: Dictionary = {} # area_id -> compiled Dictionary
var _cells_map: Dictionary = {} # Vector2i cell -> {"compiled": Dictionary, "area": Dictionary}
var _area_meta_by_id: Dictionary = {} # area_id -> area Dictionary
var _reveal_fn: Callable = Callable()
var _opening_masks: Dictionary = {} # area_id -> PackedByteArray
var _street_pokemon_by_area: Dictionary = {} # area_id -> Dictionary(Vector2i local -> Dictionary)
var _doors_by_area: Dictionary = {} # area_id -> Dictionary(Vector2i local -> Dictionary)
var _collected_ball_keys: Dictionary = {} # "ball:<area_id>:<lx>:<ly>" -> true
var _seams_by_step: Dictionary = {} # "gx,gy|dx,dy" -> seam Dictionary
var _seam_list: Array[Dictionary] = [] # 1 representative entry per directed link (44 for DC's 22 links)
var _seam_link_count: int = 0
var _route_ends_steps_cache: Dictionary = {} # route_id -> int

static func local_to_global(compiled: Dictionary, lx: int, ly: int) -> Vector2i:
	var origin: Vector2i = compiled["origin"]
	var rows: int = int(compiled["rows"])
	return Vector2i(origin.x * 32 + lx, (-(origin.y + rows - 1) - 1) * 32 + ly)

static func global_to_local(compiled: Dictionary, gx: int, gy: int) -> Vector2i:
	var origin: Vector2i = compiled["origin"]
	var rows: int = int(compiled["rows"])
	return Vector2i(gx - origin.x * 32, gy - (-(origin.y + rows - 1) - 1) * 32)

static func global_tile_to_cell(gx: int, gy: int) -> Vector2i:
	return Vector2i(floori(float(gx) / 32.0), -floori(float(gy) / 32.0) - 1)

static func ball_item_key(area_id: String, lx: int, ly: int) -> String:
	return "ball:%s:%d:%d" % [area_id, lx, ly]

static func _seam_step_key(gx: int, gy: int, dir: Vector2i) -> String:
	return "%d,%d|%d,%d" % [gx, gy, dir.x, dir.y]

func setup(compiled_by_area: Dictionary, cells_map: Dictionary, reveal_fn: Callable = Callable(), collected_keys: Dictionary = {}, place_id: String = "") -> void:
	_place_id = place_id
	_compiled_by_area = compiled_by_area
	_cells_map = cells_map
	_reveal_fn = reveal_fn
	_collected_ball_keys = collected_keys.duplicate()
	_area_meta_by_id.clear()
	_opening_masks.clear()
	_street_pokemon_by_area.clear()
	_doors_by_area.clear()
	_seams_by_step.clear()
	_seam_list.clear()
	_seam_link_count = 0
	_route_ends_steps_cache.clear()

	for cell_v in _cells_map.keys():
		var entry: Dictionary = _cells_map[cell_v]
		var a_dict: Dictionary = entry.get("area", {}) if entry.get("area") is Dictionary else {}
		var aid_c := str(a_dict.get("id", ""))
		if not aid_c.is_empty():
			_area_meta_by_id[aid_c] = a_dict
			if _place_id.is_empty():
				_place_id = str(a_dict.get("place_id", ""))

	for aid_v in _compiled_by_area.keys():
		var aid := str(aid_v)
		var comp: Dictionary = _compiled_by_area[aid_v]
		var w: int = int(comp.get("w", 0))
		var h: int = int(comp.get("h", 0))
		var openings: Array = comp.get("openings", [])
		_opening_masks[aid] = CaricatureCheck._build_opening_mask(w, h, openings)

		var sp_map := {}
		for sp_v in comp.get("street_pokemon", []):
			if sp_v is Dictionary:
				var sp: Dictionary = sp_v
				sp_map[Vector2i(int(sp["x"]), int(sp["y"]))] = sp
		_street_pokemon_by_area[aid] = sp_map

		var door_map := {}
		for d_v in comp.get("doors", []):
			if d_v is Dictionary:
				var d: Dictionary = d_v
				door_map[Vector2i(int(d["x"]), int(d["y"]))] = d
		_doors_by_area[aid] = door_map

	_build_seam_index()

func _build_seam_index() -> void:
	if _place_id.is_empty():
		return
	var routes: Array = Neighbourhoods.routes_of(_place_id)
	for r_var in routes:
		if not (r_var is Dictionary):
			continue
		var r: Dictionary = r_var
		var rid := str(r.get("id", ""))
		var ends_arr: Array = r.get("ends", []) if r.get("ends") is Array else []
		var rlegs_arr: Array = r.get("legs", []) if r.get("legs") is Array else []
		if ends_arr.size() != 2 or rlegs_arr.is_empty():
			continue
		var chain: Array[String] = [str(ends_arr[0])]
		for li in range(rlegs_arr.size()):
			chain.append("%s#%d" % [rid, li + 1])
		chain.append(str(ends_arr[1]))

		for ci in range(chain.size() - 1):
			var id_a := chain[ci]
			var id_b := chain[ci + 1]
			if not _compiled_by_area.has(id_a) or not _compiled_by_area.has(id_b):
				continue
			var comp_a: Dictionary = _compiled_by_area[id_a]
			var comp_b: Dictionary = _compiled_by_area[id_b]
			var ops_a: Array = comp_a.get("openings", [])
			var ops_b: Array = comp_b.get("openings", [])
			var cands_a: Array[int] = []
			var cands_b: Array[int] = []
			for ia in range(ops_a.size()):
				if CaricatureCheck._opening_faces_compiled(ops_a[ia] as Dictionary, comp_b):
					cands_a.append(ia)
			for ib in range(ops_b.size()):
				if CaricatureCheck._opening_faces_compiled(ops_b[ib] as Dictionary, comp_a):
					cands_b.append(ib)
			if cands_a.size() != 1 or cands_b.size() != 1:
				continue
			var op_a: Dictionary = ops_a[cands_a[0]]
			var op_b: Dictionary = ops_b[cands_b[0]]
			var out_a: Array = op_a.get("outer_tiles", [])
			var out_b: Array = op_b.get("outer_tiles", [])
			if out_a.size() != out_b.size() or out_a.is_empty():
				continue
			var step_a := CaricatureCheck._outward_step(str(op_a.get("side", "")))
			var step_b := -step_a
			var exact_match := true
			for ti in range(out_a.size()):
				var pa: Vector2i = out_a[ti]
				var pb: Vector2i = out_b[ti]
				if pa + step_a != pb:
					exact_match = false
					break
			if not exact_match:
				continue

			_seam_link_count += 1
			var mid_idx: int = int(out_a.size() / 2)
			var rep_ab: Dictionary = {}
			var rep_ba: Dictionary = {}
			for ti in range(out_a.size()):
				var pa: Vector2i = out_a[ti]
				var pb: Vector2i = out_b[ti]
				var seam_ab := {
					"from_area_id": id_a,
					"to_area_id": id_b,
					"route_id": rid,
					"from_global": pa,
					"to_global": pb,
					"dir": step_a,
				}
				var seam_ba := {
					"from_area_id": id_b,
					"to_area_id": id_a,
					"route_id": rid,
					"from_global": pb,
					"to_global": pa,
					"dir": step_b,
				}
				_seams_by_step[_seam_step_key(pa.x, pa.y, step_a)] = seam_ab
				_seams_by_step[_seam_step_key(pb.x, pb.y, step_b)] = seam_ba
				if ti == mid_idx:
					rep_ab = seam_ab
					rep_ba = seam_ba
			if not rep_ab.is_empty():
				_seam_list.append(rep_ab)
				_seam_list.append(rep_ba)
	# Precompute route ends_steps once at city load so stepping onto a route seam never runs BFS on a walking frame
	for r_var2 in routes:
		if r_var2 is Dictionary:
			var rid2 := str((r_var2 as Dictionary).get("id", ""))
			if not rid2.is_empty():
				get_route_total_ends_steps(rid2)

func get_seam_link_count() -> int:
	return _seam_link_count

func get_seam_count() -> int:
	return _seam_list.size()

func get_all_seams() -> Array[Dictionary]:
	return _seam_list.duplicate(true)

func get_seam(from_gx: int, from_gy: int, dir: Vector2i) -> Dictionary:
	var k := _seam_step_key(from_gx, from_gy, dir)
	if _seams_by_step.has(k):
		return _seams_by_step[k]
	return {}

func area_meta(area_id: String) -> Dictionary:
	if _area_meta_by_id.has(area_id):
		return _area_meta_by_id[area_id]
	return Neighbourhoods.area(area_id)

func get_route_total_ends_steps(route_id: String) -> int:
	if _route_ends_steps_cache.has(route_id):
		return int(_route_ends_steps_cache[route_id])
	var r_dict: Dictionary = Neighbourhoods.route(route_id)
	if r_dict.is_empty():
		return 64
	var legs_arr: Array = r_dict.get("legs", []) if r_dict.get("legs") is Array else []
	var total := 0
	for li in range(legs_arr.size()):
		var leg_id := "%s#%d" % [route_id, li + 1]
		total += _compute_leg_ends_steps(leg_id)
	total = maxi(1, total)
	_route_ends_steps_cache[route_id] = total
	return total

func _compute_leg_ends_steps(leg_id: String) -> int:
	if not _compiled_by_area.has(leg_id):
		return 64
	var comp: Dictionary = _compiled_by_area[leg_id]
	var w: int = int(comp.get("w", 0))
	var h: int = int(comp.get("h", 0))
	var openings: Array = comp.get("openings", [])
	if openings.size() < 2 or w <= 0 or h <= 0:
		return maxi(w, h)
	var op0: Dictionary = openings[0]
	var op1: Dictionary = openings[1]
	var goals := {}
	for gt in op1.get("outer_tiles", []):
		if gt is Vector2i:
			var gl := global_to_local(comp, (gt as Vector2i).x, (gt as Vector2i).y)
			if gl.x >= 0 and gl.x < w and gl.y >= 0 and gl.y < h:
				goals[gl.y * w + gl.x] = true
	if goals.is_empty():
		return maxi(w, h)

	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	for st in op0.get("outer_tiles", []):
		if st is Vector2i:
			var sl := global_to_local(comp, (st as Vector2i).x, (st as Vector2i).y)
			if sl.x >= 0 and sl.x < w and sl.y >= 0 and sl.y < h and is_local_tile_walkable(leg_id, sl.x, sl.y, true):
				var sidx := sl.y * w + sl.x
				if dist[sidx] < 0:
					dist[sidx] = 0
					queue.append(sl)
	var cls_buf: PackedByteArray = comp["class"]
	var var_buf: PackedByteArray = comp["variant"]
	var mask_buf: PackedByteArray = comp["mask"]
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cidx := cur.y * w + cur.x
		var dcur := dist[cidx]
		if goals.has(cidx):
			return maxi(1, dcur)
		for dv in dirs:
			var nx := cur.x + dv.x
			var ny := cur.y + dv.y
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var nidx := ny * w + nx
			if is_local_tile_walkable(leg_id, nx, ny, true):
				if dist[nidx] < 0:
					dist[nidx] = dcur + 1
					queue.append(Vector2i(nx, ny))
			elif cls_buf[nidx] == TileSynth2.TILE_LEDGE:
				var lx2 := cur.x + dv.x * 2
				var ly2 := cur.y + dv.y * 2
				if lx2 >= 0 and lx2 < w and ly2 >= 0 and ly2 < h and is_local_tile_walkable(leg_id, lx2, ly2, true):
					var lidx2 := ly2 * w + lx2
					if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, var_buf[nidx], cls_buf[lidx2], mask_buf[lidx2], dv):
						if dist[lidx2] < 0:
							dist[lidx2] = dcur + 2
							queue.append(Vector2i(lx2, ly2))
	return maxi(w, h)

func mark_ball_collected(area_id: String, lx: int, ly: int) -> void:
	_collected_ball_keys[ball_item_key(area_id, lx, ly)] = true

func is_ball_collected(area_id: String, lx: int, ly: int) -> bool:
	return _collected_ball_keys.has(ball_item_key(area_id, lx, ly))

func area_at_global(gx: int, gy: int) -> String:
	var cell := global_tile_to_cell(gx, gy)
	if not _cells_map.has(cell):
		return ""
	var entry: Dictionary = _cells_map[cell]
	var a: Dictionary = entry.get("area", {})
	return str(a.get("id", ""))

func is_global_tile_revealed(gx: int, gy: int) -> bool:
	var cell := global_tile_to_cell(gx, gy)
	if not _cells_map.has(cell):
		return false
	if _reveal_fn.is_valid():
		return int(_reveal_fn.call(cell)) > 0
	return true

func is_local_tile_walkable(area_id: String, lx: int, ly: int, treat_hm_as_passable: bool = false) -> bool:
	if not _compiled_by_area.has(area_id):
		return false
	var comp: Dictionary = _compiled_by_area[area_id]
	var w: int = int(comp.get("w", 0))
	var h: int = int(comp.get("h", 0))
	var opening_mask: PackedByteArray = _opening_masks.get(area_id, PackedByteArray())
	if not CaricatureCheck._in_play_bounds(lx, ly, w, h, opening_mask):
		return false
	var idx := ly * w + lx
	var solid_mask: PackedByteArray = comp.get("solid_mask", PackedByteArray())
	if solid_mask.size() == w * h and solid_mask[idx] == 1:
		return false
	var sp_map: Dictionary = _street_pokemon_by_area.get(area_id, {})
	if sp_map.has(Vector2i(lx, ly)):
		return false
	var cls_buf: PackedByteArray = comp["class"]
	var var_buf: PackedByteArray = comp["variant"]
	var mask_buf: PackedByteArray = comp["mask"]
	var cls: int = cls_buf[idx]
	if cls == TileSynth2.TILE_ITEM_BALL:
		return is_ball_collected(area_id, lx, ly)
	if treat_hm_as_passable and TileSynth2.is_field_clearable(cls):
		return true
	return TileSynth2.is_walkable(cls, var_buf[idx], mask_buf[idx])

func evaluate_step(from_gx: int, from_gy: int, dir: Vector2i) -> Dictionary:
	if dir == Vector2i.ZERO:
		return {"action": "blocked", "reason": "none", "tile": Vector2i(from_gx, from_gy), "area_id": area_at_global(from_gx, from_gy)}

	var from_aid := area_at_global(from_gx, from_gy)
	var seam: Dictionary = get_seam(from_gx, from_gy, dir)
	var tx := from_gx + dir.x
	var ty := from_gy + dir.y
	var to_cell := global_tile_to_cell(tx, ty)

	# 1. Revealed / fog check
	if not _cells_map.has(to_cell):
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": "", "seam": seam}
	if _reveal_fn.is_valid() and int(_reveal_fn.call(to_cell)) <= 0:
		var locked_area := area_at_global(tx, ty)
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": locked_area, "seam": seam}

	var to_aid := area_at_global(tx, ty)
	if to_aid.is_empty() or not _compiled_by_area.has(to_aid):
		return {"action": "blocked", "reason": "fog", "tile": Vector2i(tx, ty), "area_id": "", "seam": seam}

	# Crossing between distinct areas is permitted only through a precomputed aligned opening seam
	if not from_aid.is_empty() and to_aid != from_aid and seam.is_empty() and not _seam_list.is_empty():
		return {"action": "blocked", "reason": "wall", "tile": Vector2i(tx, ty), "area_id": to_aid}

	var comp: Dictionary = _compiled_by_area[to_aid]
	var w: int = int(comp["w"])
	var h: int = int(comp["h"])
	var opening_mask: PackedByteArray = _opening_masks.get(to_aid, PackedByteArray())
	var local_t := global_to_local(comp, tx, ty)
	var lx := local_t.x
	var ly := local_t.y

	if not CaricatureCheck._in_play_bounds(lx, ly, w, h, opening_mask):
		return {"action": "blocked", "reason": "wall", "tile": Vector2i(tx, ty), "area_id": to_aid}

	var idx := ly * w + lx
	var cls_buf: PackedByteArray = comp["class"]
	var var_buf: PackedByteArray = comp["variant"]
	var mask_buf: PackedByteArray = comp["mask"]
	var cls: int = cls_buf[idx]

	# 2. Door entry check when stepping North onto a TILE_DOOR
	if cls == TileSynth2.TILE_DOOR:
		var door_map: Dictionary = _doors_by_area.get(to_aid, {})
		var d_entry: Dictionary = door_map.get(Vector2i(lx, ly), {})
		var iid := str(d_entry.get("interior", ""))
		if dir == Vector2i(0, -1) and not iid.is_empty():
			return {
				"action": "door",
				"door": d_entry,
				"door_tile": Vector2i(tx, ty),
				"door_local": Vector2i(lx, ly),
				"area_id": to_aid,
			}
		return {"action": "blocked", "reason": "door_locked", "tile": Vector2i(tx, ty), "area_id": to_aid}

	# 3. Ledge one-way 2-tile hop check
	if cls == TileSynth2.TILE_LEDGE:
		var land_gx := from_gx + dir.x * 2
		var land_gy := from_gy + dir.y * 2
		var land_aid := area_at_global(land_gx, land_gy)
		if land_aid == to_aid and is_global_tile_revealed(land_gx, land_gy):
			var land_l := global_to_local(comp, land_gx, land_gy)
			if is_local_tile_walkable(to_aid, land_l.x, land_l.y):
				var land_idx := land_l.y * w + land_l.x
				var land_cls: int = cls_buf[land_idx]
				var land_mask: int = mask_buf[land_idx]
				if land_cls == TileSynth2.TILE_ITEM_BALL and is_ball_collected(to_aid, land_l.x, land_l.y):
					land_cls = TileSynth2.TILE_GRASS
					land_mask = 0
				if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, var_buf[idx], land_cls, land_mask, dir):
					return {
						"action": "ledge",
						"over": Vector2i(tx, ty),
						"to": Vector2i(land_gx, land_gy),
						"from_area": from_aid,
						"to_area": land_aid,
						"crossed_seam": (from_aid != land_aid),
						"landing_class": cls_buf[land_idx],
						"step_tiles": 2,
					}
		return {"action": "blocked", "reason": "ledge_wrong_dir", "tile": Vector2i(tx, ty), "area_id": to_aid}

	# 4. Standard walkability check
	if is_local_tile_walkable(to_aid, lx, ly):
		return {
			"action": "step",
			"to": Vector2i(tx, ty),
			"from_area": from_aid,
			"to_area": to_aid,
			"crossed_seam": (from_aid != to_aid),
			"seam": seam,
			"route_id": str(seam.get("route_id", "")),
			"step_tiles": 1,
		}

	# 5. Classify exact block reason for interact / bump feedback
	var reason := "wall"
	var solid_mask: PackedByteArray = comp.get("solid_mask", PackedByteArray())
	var sp_map: Dictionary = _street_pokemon_by_area.get(to_aid, {})
	if (solid_mask.size() == w * h and solid_mask[idx] == 1) or sp_map.has(Vector2i(lx, ly)):
		reason = "entity"
	elif cls == TileSynth2.TILE_WATER:
		reason = "water"
	elif cls == TileSynth2.TILE_CLIFF:
		reason = "cliff"
	elif cls == TileSynth2.TILE_CUT_TREE:
		reason = "cut"
	elif cls == TileSynth2.TILE_SMASH_ROCK:
		reason = "rock_smash"
	elif cls == TileSynth2.TILE_BOULDER:
		reason = "boulder"
	elif cls == TileSynth2.TILE_ITEM_BALL:
		reason = "item_ball"
	elif cls == TileSynth2.TILE_SIGN:
		reason = "sign"
	return {"action": "blocked", "reason": reason, "tile": Vector2i(tx, ty), "area_id": to_aid}
