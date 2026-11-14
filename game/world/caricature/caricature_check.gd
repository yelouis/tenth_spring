class_name CaricatureCheck
extends RefCounted

## game/world/caricature/caricature_check.gd — Playable-Size, Route & City Reachability Measurements (Items 48a, 53)
## Contract: docs/design_neighbourhoods_and_caricature.md §5.3,
##           docs/implementation_plan_dc_trial.md §5.1–§5.2, §10.5

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")

# §5.2 & §10.5 Playable-size contract thresholds (Decisions 58–59)
const MAX_UNREACHED: int = 0
const MAX_TRAPPED: int = 0
const MAX_WALK_HOOD: int = 400
const MAX_WALK_CAMP: int = 120
const MAX_LANDMARK_STEPS_HOOD: int = 260
const MAX_LANDMARK_STEPS_CAMP: int = 120
const MIN_TALL_GRASS_HOOD: float = 0.08
const MAX_TALL_GRASS_HOOD: float = 0.35
const TALL_GRASS_CAMP: float = 0.0
const MIN_TALL_GRASS_ROUTE: float = 0.20
const MAX_TALL_GRASS_ROUTE: float = 0.50
const MIN_SEARCH_DOORS_HOOD: int = 4
const MAX_SEARCH_DOORS_HOOD: int = 48
const MAX_SEARCH_DOORS_CAMP: int = 8
const MAX_SEARCH_DOORS_ROUTE: int = 8
const MIN_LANDMARKS_HOOD: int = 2
const MIN_LANDMARKS_ROUTE: int = 1
const ROUTE_OPENINGS_COUNT: int = 2
const PLAIN_GRASS_WINDOW: int = 12
const ROUTE_ENDS_STEPS_MULT: float = 1.5
const MAX_END_SIGN_STEPS: int = 6

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

static func _in_interior(x: int, y: int, w: int, h: int) -> bool:
	var b := CaricatureMap.BORDER
	return x >= b and x < w - b and y >= b and y < h - b

static func _build_opening_mask(w: int, h: int, openings: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	var b := CaricatureMap.BORDER
	for op_var in openings:
		if not (op_var is Dictionary):
			continue
		var op: Dictionary = op_var
		var side := str(op.get("side", ""))
		var op_at := int(op.get("at", 0))
		var op_w := int(op.get("width", 0))
		if side == "N":
			for ty in range(0, mini(b, h)):
				for tx in range(maxi(0, op_at), mini(w, op_at + op_w)):
					mask[ty * w + tx] = 1
		elif side == "S":
			for ty in range(maxi(0, h - b), h):
				for tx in range(maxi(0, op_at), mini(w, op_at + op_w)):
					mask[ty * w + tx] = 1
		elif side == "W":
			for ty in range(maxi(0, op_at), mini(h, op_at + op_w)):
				for tx in range(0, mini(b, w)):
					mask[ty * w + tx] = 1
		elif side == "E":
			for ty in range(maxi(0, op_at), mini(h, op_at + op_w)):
				for tx in range(maxi(0, w - b), w):
					mask[ty * w + tx] = 1
	return mask

static func _in_play_bounds(x: int, y: int, w: int, h: int, opening_mask: PackedByteArray) -> bool:
	if x < 0 or x >= w or y < 0 or y >= h:
		return false
	if _in_interior(x, y, w, h):
		return true
	return opening_mask[y * w + x] == 1

static func _local_outer_of_opening(op: Dictionary, w: int, h: int) -> Array[Vector2i]:
	if op.has("local_outer") and op["local_outer"] is Array:
		var out_existing: Array[Vector2i] = []
		for p in (op["local_outer"] as Array):
			if p is Vector2i:
				out_existing.append(p)
		if not out_existing.is_empty():
			return out_existing
	var out: Array[Vector2i] = []
	var side := str(op.get("side", ""))
	var op_at := int(op.get("at", 0))
	var op_w := int(op.get("width", 0))
	if side == "N":
		for tx in range(op_at, op_at + op_w):
			out.append(Vector2i(tx, 0))
	elif side == "S":
		for tx in range(op_at, op_at + op_w):
			out.append(Vector2i(tx, h - 1))
	elif side == "W":
		for ty in range(op_at, op_at + op_w):
			out.append(Vector2i(0, ty))
	elif side == "E":
		for ty in range(op_at, op_at + op_w):
			out.append(Vector2i(w - 1, ty))
	return out

static func _bfs_from_sources(sources: Array[Vector2i], w: int, h: int, walkable_flags: PackedByteArray, fwd_edges: Dictionary) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[int] = []
	for pt in sources:
		if pt.x >= 0 and pt.x < w and pt.y >= 0 and pt.y < h:
			var idx: int = pt.y * w + pt.x
			if walkable_flags[idx] == 1 and dist[idx] == -1:
				dist[idx] = 0
				queue.append(idx)
	var head := 0
	while head < queue.size():
		var u: int = queue[head]
		head += 1
		var d_u: int = dist[u]
		var outs: PackedInt32Array = fwd_edges.get(u, PackedInt32Array())
		for v in outs:
			if dist[v] == -1:
				dist[v] = d_u + 1
				queue.append(v)
	return dist

static func _has_plain_grass_window(cls_buf: PackedByteArray, w: int, h: int, win: int) -> bool:
	if w < win or h < win:
		return false
	# 2D prefix sum of (cls == TILE_GRASS)
	var stride: int = w + 1
	var psum := PackedInt32Array()
	psum.resize((h + 1) * stride)
	psum.fill(0)
	for y in range(h):
		var row_sum := 0
		var base_cur: int = (y + 1) * stride
		var base_prev: int = y * stride
		var map_base: int = y * w
		for x in range(w):
			if cls_buf[map_base + x] == TileSynth2.TILE_GRASS:
				row_sum += 1
			psum[base_cur + x + 1] = psum[base_prev + x + 1] + row_sum
	var target: int = win * win
	for y0 in range(0, h - win + 1):
		var top_base: int = y0 * stride
		var bot_base: int = (y0 + win) * stride
		for x0 in range(0, w - win + 1):
			var count: int = psum[bot_base + x0 + win] - psum[top_base + x0 + win] - psum[bot_base + x0] + psum[top_base + x0]
			if count == target:
				return true
	return false

static func _uses_route_era_rules(area: Dictionary, is_camp: bool, is_route: bool, openings: Array, w: int, h: int) -> bool:
	if is_route or area.has("at") or not openings.is_empty():
		return true
	if is_camp and (w >= 64 or h >= 64):
		return true
	if not is_camp and (w >= 128 or h >= 128):
		return true
	var pid := str(area.get("place_id", ""))
	if not pid.is_empty():
		var c_dict: Dictionary = Neighbourhoods.city(pid)
		if c_dict.has("routes"):
			return true
	return false

static func measure(compiled: Dictionary, area: Dictionary) -> Dictionary:
	var w: int = int(compiled.get("w", 0))
	var h: int = int(compiled.get("h", 0))
	var cls_buf: PackedByteArray = compiled.get("class", PackedByteArray())
	var var_buf: PackedByteArray = compiled.get("variant", PackedByteArray())
	var mask_buf: PackedByteArray = compiled.get("mask", PackedByteArray())
	var arrival: Vector2i = compiled.get("arrival", Vector2i.ZERO)
	var art_pending: int = int(compiled.get("art_pending", 0))
	var openings_var: Variant = compiled.get("openings", [])
	var openings: Array = openings_var if openings_var is Array else []

	var akind := str(area.get("kind", str(compiled.get("kind", ""))))
	var aid := str(area.get("id", ""))
	var is_camp := (akind == "camp" or aid.begins_with("camp:"))
	var is_route := (akind == "route" or aid.begins_with("route:"))

	var total: int = w * h
	var opening_mask := _build_opening_mask(w, h, openings)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(total)
	walkable_flags.fill(0)

	var walkable_count := 0
	for y in range(h):
		for x in range(w):
			if not _in_play_bounds(x, y, w, h, opening_mask):
				continue
			var idx: int = y * w + x
			if TileSynth2.is_walkable(cls_buf[idx], var_buf[idx], mask_buf[idx]):
				walkable_flags[idx] = 1
				walkable_count += 1

	# Build directed movement graph (normal 1-step & 1-step ledge jumps) and reverse graph
	var fwd_edges: Dictionary = {} # int_idx -> PackedInt32Array
	var rev_edges: Dictionary = {} # int_idx -> PackedInt32Array
	for y in range(h):
		for x in range(w):
			var a_idx: int = y * w + x
			if walkable_flags[a_idx] == 0:
				continue
			var outs := PackedInt32Array()
			for d in DIRS:
				var bx: int = x + d.x
				var by: int = y + d.y
				if not _in_play_bounds(bx, by, w, h, opening_mask):
					continue
				var b_idx: int = by * w + bx
				if walkable_flags[b_idx] == 1:
					outs.append(b_idx)
				elif cls_buf[b_idx] == TileSynth2.TILE_LEDGE:
					var cx: int = x + d.x * 2
					var cy: int = y + d.y * 2
					if _in_play_bounds(cx, cy, w, h, opening_mask):
						var c_idx: int = cy * w + cx
						if TileSynth2.can_jump_ledge(
							TileSynth2.TILE_LEDGE,
							var_buf[b_idx],
							cls_buf[c_idx],
							mask_buf[c_idx],
							d
						):
							outs.append(c_idx)
			fwd_edges[a_idx] = outs
			for dst_idx in outs:
				if not rev_edges.has(dst_idx):
					rev_edges[dst_idx] = PackedInt32Array()
				var r_arr: PackedInt32Array = rev_edges[dst_idx]
				r_arr.append(a_idx)
				rev_edges[dst_idx] = r_arr

	# Forward BFS from arrival
	var dist := PackedInt32Array()
	dist.resize(total)
	dist.fill(-1)

	var reached_count := 0
	var max_walk := 0
	var tall_grass_reached := 0

	if _in_play_bounds(arrival.x, arrival.y, w, h, opening_mask):
		var arr_idx: int = arrival.y * w + arrival.x
		if walkable_flags[arr_idx] == 1:
			dist[arr_idx] = 0
			var queue: Array[int] = [arr_idx]
			var head := 0
			while head < queue.size():
				var u: int = queue[head]
				head += 1
				var d_u: int = dist[u]
				reached_count += 1
				if d_u > max_walk:
					max_walk = d_u
				if cls_buf[u] == TileSynth2.TILE_TALL_GRASS:
					tall_grass_reached += 1
				var outs: PackedInt32Array = fwd_edges.get(u, PackedInt32Array())
				for v in outs:
					if dist[v] == -1:
						dist[v] = d_u + 1
						queue.append(v)

	# Reverse BFS to arrival to find trapped tiles
	var can_return := PackedByteArray()
	can_return.resize(total)
	can_return.fill(0)
	if _in_play_bounds(arrival.x, arrival.y, w, h, opening_mask):
		var arr_idx: int = arrival.y * w + arrival.x
		if walkable_flags[arr_idx] == 1:
			can_return[arr_idx] = 1
			var r_queue: Array[int] = [arr_idx]
			var r_head := 0
			while r_head < r_queue.size():
				var u: int = r_queue[r_head]
				r_head += 1
				var ins: PackedInt32Array = rev_edges.get(u, PackedInt32Array())
				for prev in ins:
					if can_return[prev] == 0:
						can_return[prev] = 1
						r_queue.append(prev)

	var trapped_count := 0
	for i in range(total):
		if dist[i] >= 0 and can_return[i] == 0:
			trapped_count += 1

	var unreached_count: int = walkable_count - reached_count
	var tall_grass_share: float = (float(tall_grass_reached) / float(reached_count)) if reached_count > 0 else 0.0

	# Openings reachability (both ways) & leg ends_steps (§10.5)
	var openings_reached := 0
	for op_var in openings:
		if not (op_var is Dictionary):
			continue
		var loc_outer := _local_outer_of_opening(op_var as Dictionary, w, h)
		if loc_outer.is_empty():
			continue
		var all_ok := true
		for pt in loc_outer:
			var pidx: int = pt.y * w + pt.x
			if dist[pidx] < 0 or can_return[pidx] == 0:
				all_ok = false
				break
		if all_ok:
			openings_reached += 1

	var ends_steps := -1
	if is_route and openings.size() == ROUTE_OPENINGS_COUNT:
		var out0 := _local_outer_of_opening(openings[0] as Dictionary, w, h)
		var out1 := _local_outer_of_opening(openings[1] as Dictionary, w, h)
		var d_from_0 := _bfs_from_sources(out0, w, h, walkable_flags, fwd_edges)
		var d_from_1 := _bfs_from_sources(out1, w, h, walkable_flags, fwd_edges)
		var min_01 := -1
		for pt1 in out1:
			var v01: int = d_from_0[pt1.y * w + pt1.x]
			if v01 >= 0 and (min_01 == -1 or v01 < min_01):
				min_01 = v01
		var min_10 := -1
		for pt0 in out0:
			var v10: int = d_from_1[pt0.y * w + pt0.x]
			if v10 >= 0 and (min_10 == -1 or v10 < min_10):
				min_10 = v10
		if min_01 >= 0 and min_10 >= 0:
			ends_steps = maxi(min_01, min_10)

	# Search doors: doors of standing or ruined ordinary buildings whose south tile is reached
	var search_doors := 0
	var doors_arr: Array = compiled.get("doors", [])
	for d_var in doors_arr:
		var d: Dictionary = d_var
		if not bool(d.get("is_ordinary", false)):
			continue
		var sx: int = int(d["x"])
		var sy: int = int(d["y"]) + 1
		if _in_play_bounds(sx, sy, w, h, opening_mask) and dist[sy * w + sx] >= 0:
			search_doors += 1

	# Landmarks presence and steps
	var placed_objs: Array = compiled.get("placed_objects", [])
	var signs_arr: Array = compiled.get("signs", [])
	var roster_lms_var: Variant = area.get("landmarks", [])
	var roster_lms: Array = roster_lms_var if roster_lms_var is Array else []

	var landmarks_present := 0
	var landmark_steps: Array[int] = []

	for lm_var in roster_lms:
		var lm: Dictionary = lm_var
		if lm.has("stamp"):
			var target_stamp := str(lm.get("stamp", ""))
			var matching_objs: Array[Dictionary] = []
			for po_var in placed_objs:
				var po: Dictionary = po_var
				var form := str(po.get("form", ""))
				if form == "stamp" and str(po.get("stamp_str", "")) == target_stamp:
					matching_objs.append(po)
				elif form == "pending" and str(po.get("pending_id", "")) == target_stamp:
					matching_objs.append(po)
			if matching_objs.is_empty():
				landmark_steps.append(-1)
				continue
			var best_steps := -1
			for po in matching_objs:
				var step_val := _steps_for_drawing_landmark(po, doors_arr, dist, w, h, opening_mask)
				if step_val >= 0 and (best_steps == -1 or step_val < best_steps):
					best_steps = step_val
			if best_steps >= 0:
				landmarks_present += 1
			landmark_steps.append(best_steps)
		else:
			var target_sign := str(lm.get("sign", ""))
			var matching_signs: Array[Dictionary] = []
			for sg_var in signs_arr:
				var sg: Dictionary = sg_var
				if str(sg.get("text", "")) == target_sign:
					matching_signs.append(sg)
			if matching_signs.is_empty():
				landmark_steps.append(-1)
				continue
			var best_steps := -1
			for sg in matching_signs:
				var sx: int = int(sg["x"])
				var sy: int = int(sg["y"])
				for d in DIRS:
					var nx: int = sx + d.x
					var ny: int = sy + d.y
					if _in_play_bounds(nx, ny, w, h, opening_mask):
						var st: int = dist[ny * w + nx]
						if st >= 0 and (best_steps == -1 or st < best_steps):
							best_steps = st
			if best_steps >= 0:
				landmarks_present += 1
			landmark_steps.append(best_steps)

	var landmark_max := 0
	var any_lm_unreachable := false
	for st in landmark_steps:
		if st < 0:
			any_lm_unreachable = true
		elif st > landmark_max:
			landmark_max = st
	if any_lm_unreachable:
		landmark_max = -1

	var has_plain_12 := _has_plain_grass_window(cls_buf, w, h, PLAIN_GRASS_WINDOW)
	var use_route_rules := _uses_route_era_rules(area, is_camp, is_route, openings, w, h)

	# Pass/fail rules P1–P10 (§5.2, §10.5)
	var failed_rules: Array[String] = []

	if unreached_count != MAX_UNREACHED:
		failed_rules.append("P1")
	if trapped_count != MAX_TRAPPED:
		failed_rules.append("P2")

	if not is_route:
		var walk_limit: int = MAX_WALK_CAMP if is_camp else MAX_WALK_HOOD
		if max_walk > walk_limit:
			failed_rules.append("P3")

		var lm_limit: int = MAX_LANDMARK_STEPS_CAMP if is_camp else MAX_LANDMARK_STEPS_HOOD
		var p4_ok := true
		for st in landmark_steps:
			if st < 0 or st > lm_limit:
				p4_ok = false
				break
		if not p4_ok:
			failed_rules.append("P4")

	if is_camp:
		if tall_grass_reached != 0 or tall_grass_share != TALL_GRASS_CAMP:
			failed_rules.append("P5")
	elif is_route:
		if tall_grass_share < MIN_TALL_GRASS_ROUTE or tall_grass_share > MAX_TALL_GRASS_ROUTE:
			failed_rules.append("P5")
	else:
		if tall_grass_share < MIN_TALL_GRASS_HOOD or tall_grass_share > MAX_TALL_GRASS_HOOD:
			failed_rules.append("P5")

	if is_camp:
		if search_doors < 0 or search_doors > MAX_SEARCH_DOORS_CAMP:
			failed_rules.append("P6")
	elif is_route:
		if search_doors < 0 or search_doors > MAX_SEARCH_DOORS_ROUTE:
			failed_rules.append("P6")
	else:
		if search_doors < MIN_SEARCH_DOORS_HOOD or search_doors > MAX_SEARCH_DOORS_HOOD:
			failed_rules.append("P6")

	var listed_count: int = roster_lms.size()
	if not is_route:
		if is_camp:
			if landmarks_present != listed_count:
				failed_rules.append("P7")
		else:
			if listed_count < MIN_LANDMARKS_HOOD or landmarks_present != listed_count:
				failed_rules.append("P7")

	if use_route_rules:
		if is_camp:
			if not openings.is_empty():
				failed_rules.append("P8")
		elif is_route:
			if openings.size() != ROUTE_OPENINGS_COUNT or openings_reached != ROUTE_OPENINGS_COUNT or ends_steps < 0:
				failed_rules.append("P8")
		else:
			if openings.is_empty() or openings_reached != openings.size():
				failed_rules.append("P8")

		if has_plain_12:
			failed_rules.append("P9")

		if is_route:
			var leg_len: int = maxi(w, h)
			if ends_steps < 0 or float(ends_steps) > ROUTE_ENDS_STEPS_MULT * float(leg_len):
				failed_rules.append("P10")

	return {
		"ok": failed_rules.is_empty(),
		"failed_rules": failed_rules,
		"walkable": walkable_count,
		"reached": reached_count,
		"unreached": unreached_count,
		"trapped": trapped_count,
		"max_walk": max_walk,
		"landmark_steps": landmark_steps,
		"landmark_max": landmark_max,
		"tall_grass_share": tall_grass_share,
		"search_doors": search_doors,
		"landmarks_present": landmarks_present,
		"landmarks_listed": listed_count,
		"art_pending": art_pending,
		"openings_reached": openings_reached,
		"openings_total": openings.size(),
		"ends_steps": ends_steps,
		"has_plain_grass_12x12": has_plain_12,
	}

static func _outward_step(side: String) -> Vector2i:
	if side == "N":
		return Vector2i(0, -1)
	if side == "S":
		return Vector2i(0, 1)
	if side == "W":
		return Vector2i(-1, 0)
	if side == "E":
		return Vector2i(1, 0)
	return Vector2i.ZERO

static func _global_tile_rect(compiled: Dictionary) -> Rect2i:
	var orig: Vector2i = compiled.get("origin", Vector2i.ZERO)
	var rows: int = int(compiled.get("rows", 1))
	var w: int = int(compiled.get("w", 0))
	var h: int = int(compiled.get("h", 0))
	var gx0: int = orig.x * 32
	var gy0: int = (-(orig.y + rows - 1) - 1) * 32
	return Rect2i(gx0, gy0, w, h)

static func _opening_faces_compiled(op: Dictionary, target_compiled: Dictionary) -> bool:
	var outer_var: Variant = op.get("outer_tiles", [])
	if not (outer_var is Array) or (outer_var as Array).is_empty():
		return false
	var step := _outward_step(str(op.get("side", "")))
	var rect := _global_tile_rect(target_compiled)
	for pt_var in (outer_var as Array):
		var pt: Vector2i = pt_var
		if not rect.has_point(pt + step):
			return false
	return true

static func _has_route_sign_near_end(leg_compiled: Dictionary, end_op: Dictionary, route_name: String) -> bool:
	var w: int = int(leg_compiled.get("w", 0))
	var h: int = int(leg_compiled.get("h", 0))
	var cls_buf: PackedByteArray = leg_compiled.get("class", PackedByteArray())
	var var_buf: PackedByteArray = leg_compiled.get("variant", PackedByteArray())
	var mask_buf: PackedByteArray = leg_compiled.get("mask", PackedByteArray())
	var openings: Array = leg_compiled.get("openings", [])
	var opening_mask := _build_opening_mask(w, h, openings)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(w * h)
	walkable_flags.fill(0)
	for y in range(h):
		for x in range(w):
			if _in_play_bounds(x, y, w, h, opening_mask):
				var idx: int = y * w + x
				if TileSynth2.is_walkable(cls_buf[idx], var_buf[idx], mask_buf[idx]):
					walkable_flags[idx] = 1
	var fwd_edges: Dictionary = {}
	for y in range(h):
		for x in range(w):
			var a_idx: int = y * w + x
			if walkable_flags[a_idx] == 0:
				continue
			var outs := PackedInt32Array()
			for d in DIRS:
				var bx: int = x + d.x
				var by: int = y + d.y
				if not _in_play_bounds(bx, by, w, h, opening_mask):
					continue
				var b_idx: int = by * w + bx
				if walkable_flags[b_idx] == 1:
					outs.append(b_idx)
				elif cls_buf[b_idx] == TileSynth2.TILE_LEDGE:
					var cx: int = x + d.x * 2
					var cy: int = y + d.y * 2
					if _in_play_bounds(cx, cy, w, h, opening_mask):
						var c_idx: int = cy * w + cx
						if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, var_buf[b_idx], cls_buf[c_idx], mask_buf[c_idx], d):
							outs.append(c_idx)
			fwd_edges[a_idx] = outs

	var sources := _local_outer_of_opening(end_op, w, h)
	var dist := _bfs_from_sources(sources, w, h, walkable_flags, fwd_edges)
	var signs_arr: Array = leg_compiled.get("signs", [])
	for sg_var in signs_arr:
		if not (sg_var is Dictionary):
			continue
		var sg: Dictionary = sg_var
		if str(sg.get("text", "")) != route_name:
			continue
		var sx: int = int(sg["x"])
		var sy: int = int(sg["y"])
		for d in DIRS:
			var nx: int = sx + d.x
			var ny: int = sy + d.y
			if _in_play_bounds(nx, ny, w, h, opening_mask):
				var st: int = dist[ny * w + nx]
				if st >= 0 and st <= MAX_END_SIGN_STEPS:
					return true
	return false

static func check_route(route_dict: Dictionary, compiled_by_id: Dictionary, measures_by_id: Dictionary) -> Dictionary:
	var rid := str(route_dict.get("id", ""))
	var rname := str(route_dict.get("name", ""))
	var ends_var: Variant = route_dict.get("ends", [])
	var ends_arr: Array = ends_var if ends_var is Array else []
	var legs_var: Variant = route_dict.get("legs", [])
	var legs_arr: Array = legs_var if legs_var is Array else []
	var leg_count: int = legs_arr.size()
	var lms_var: Variant = route_dict.get("landmarks", [])
	var lms_arr: Array = lms_var if lms_var is Array else []
	var listed_count: int = lms_arr.size()

	# RP1: every landmark listed on the route is present & reachable on at least one leg
	var landmarks_present := 0
	for lm_idx in range(listed_count):
		var found := false
		for leg_num in range(1, leg_count + 1):
			var leg_id := "%s#%d" % [rid, leg_num]
			if measures_by_id.has(leg_id):
				var m: Dictionary = measures_by_id[leg_id]
				var lm_steps: Array = m.get("landmark_steps", [])
				if lm_idx < lm_steps.size() and int(lm_steps[lm_idx]) >= 0:
					found = true
					break
		if found:
			landmarks_present += 1

	# RP2: a sign with the route's name stands within 6 steps of each of its two ends
	var end_signs := 0
	if ends_arr.size() == 2 and leg_count >= 1:
		var end0_id := str(ends_arr[0])
		var end1_id := str(ends_arr[1])
		var leg_first_id := "%s#1" % rid
		var leg_last_id := "%s#%d" % [rid, leg_count]
		if compiled_by_id.has(leg_first_id) and compiled_by_id.has(end0_id):
			var c_first: Dictionary = compiled_by_id[leg_first_id]
			var c_end0: Dictionary = compiled_by_id[end0_id]
			for op_var in (c_first.get("openings", []) as Array):
				var op: Dictionary = op_var
				if _opening_faces_compiled(op, c_end0):
					if _has_route_sign_near_end(c_first, op, rname):
						end_signs += 1
					break
		if compiled_by_id.has(leg_last_id) and compiled_by_id.has(end1_id):
			var c_last: Dictionary = compiled_by_id[leg_last_id]
			var c_end1: Dictionary = compiled_by_id[end1_id]
			for op_var in (c_last.get("openings", []) as Array):
				var op: Dictionary = op_var
				if _opening_faces_compiled(op, c_end1):
					if _has_route_sign_near_end(c_last, op, rname):
						end_signs += 1
					break

	var failed_rules: Array[String] = []
	if listed_count < MIN_LANDMARKS_ROUTE or landmarks_present != listed_count:
		failed_rules.append("RP1")
	if end_signs != 2:
		failed_rules.append("RP2")

	return {
		"ok": failed_rules.is_empty(),
		"failed_rules": failed_rules,
		"legs": leg_count,
		"landmarks_present": landmarks_present,
		"landmarks_listed": listed_count,
		"end_signs": end_signs,
	}

static func check_city(place_id: String, compiled_by_id: Dictionary) -> Dictionary:
	var all_areas: Array = Neighbourhoods.areas_of(place_id)
	var routes: Array = Neighbourhoods.routes_of(place_id)

	var hoods: Array[Dictionary] = []
	var legs: Array[Dictionary] = []
	for a_var in all_areas:
		if not (a_var is Dictionary):
			continue
		var a: Dictionary = a_var
		var k := str(a.get("kind", ""))
		if k == "hood":
			hoods.append(a)
		elif k == "route":
			legs.append(a)

	# Track every opening across every compiled block in the city
	var matched_opening_keys: Dictionary = {}
	var total_city_openings := 0
	for a_var in all_areas:
		if not (a_var is Dictionary):
			continue
		var aid := str((a_var as Dictionary).get("id", ""))
		if not compiled_by_id.has(aid):
			continue
		var comp: Dictionary = compiled_by_id[aid]
		if not bool(comp.get("ok", false)):
			continue
		var ops: Array = comp.get("openings", [])
		total_city_openings += ops.size()

	# C0: check every link in every route's chain
	var total_links := 0
	var openings_aligned := 0
	var aligned_links: Array[Dictionary] = []

	for r_var in routes:
		if not (r_var is Dictionary):
			continue
		var r: Dictionary = r_var
		var rid := str(r.get("id", ""))
		var ends_var: Variant = r.get("ends", [])
		var ends_arr: Array = ends_var if ends_var is Array else []
		var rlegs_var: Variant = r.get("legs", [])
		var rlegs_arr: Array = rlegs_var if rlegs_var is Array else []
		if ends_arr.size() != 2 or rlegs_arr.is_empty():
			continue
		var chain: Array[String] = [str(ends_arr[0])]
		for li in range(rlegs_arr.size()):
			chain.append("%s#%d" % [rid, li + 1])
		chain.append(str(ends_arr[1]))

		for ci in range(chain.size() - 1):
			total_links += 1
			var id_a := chain[ci]
			var id_b := chain[ci + 1]
			if not compiled_by_id.has(id_a) or not compiled_by_id.has(id_b):
				continue
			var comp_a: Dictionary = compiled_by_id[id_a]
			var comp_b: Dictionary = compiled_by_id[id_b]
			if not bool(comp_a.get("ok", false)) or not bool(comp_b.get("ok", false)):
				continue

			var ops_a: Array = comp_a.get("openings", [])
			var ops_b: Array = comp_b.get("openings", [])
			var cands_a: Array[int] = []
			var cands_b: Array[int] = []
			for ia in range(ops_a.size()):
				if _opening_faces_compiled(ops_a[ia] as Dictionary, comp_b):
					cands_a.append(ia)
			for ib in range(ops_b.size()):
				if _opening_faces_compiled(ops_b[ib] as Dictionary, comp_a):
					cands_b.append(ib)

			if cands_a.size() != 1 or cands_b.size() != 1:
				continue
			var ia_sel: int = cands_a[0]
			var ib_sel: int = cands_b[0]
			var key_a := "%s|%d" % [id_a, ia_sel]
			var key_b := "%s|%d" % [id_b, ib_sel]
			if matched_opening_keys.has(key_a) or matched_opening_keys.has(key_b):
				continue

			var op_a: Dictionary = ops_a[ia_sel]
			var op_b: Dictionary = ops_b[ib_sel]
			var out_a: Array = op_a.get("outer_tiles", [])
			var out_b: Array = op_b.get("outer_tiles", [])
			if out_a.size() != out_b.size() or out_a.is_empty():
				continue
			var step_a := _outward_step(str(op_a.get("side", "")))
			var exact_match := true
			for ti in range(out_a.size()):
				var pa: Vector2i = out_a[ti]
				var pb: Vector2i = out_b[ti]
				if pa + step_a != pb:
					exact_match = false
					break
			if exact_match:
				openings_aligned += 1
				matched_opening_keys[key_a] = true
				matched_opening_keys[key_b] = true
				aligned_links.append({
					"id_a": id_a,
					"op_a": op_a,
					"id_b": id_b,
					"op_b": op_b,
				})

	var unmatched_openings: int = total_city_openings - matched_opening_keys.size()
	var c0_ok: bool = (openings_aligned == total_links and unmatched_openings == 0)

	# C1: Join every neighbourhood and leg into one directed tile graph, crossing ONLY on aligned links
	var play_blocks: Array[Dictionary] = []
	for h_entry in hoods:
		play_blocks.append(h_entry)
	for l_entry in legs:
		play_blocks.append(l_entry)

	var block_offset: Dictionary = {}
	var total_tiles := 0
	for pb in play_blocks:
		var bid := str(pb.get("id", ""))
		if not compiled_by_id.has(bid):
			continue
		var comp: Dictionary = compiled_by_id[bid]
		if not bool(comp.get("ok", false)):
			continue
		block_offset[bid] = total_tiles
		total_tiles += int(comp["w"]) * int(comp["h"])

	var g_walkable := PackedByteArray()
	g_walkable.resize(total_tiles)
	g_walkable.fill(0)
	var g_fwd: Dictionary = {}
	var g_rev: Dictionary = {}

	for pb in play_blocks:
		var bid := str(pb.get("id", ""))
		if not block_offset.has(bid):
			continue
		var base: int = block_offset[bid]
		var comp: Dictionary = compiled_by_id[bid]
		var w: int = int(comp["w"])
		var h: int = int(comp["h"])
		var cls_buf: PackedByteArray = comp["class"]
		var var_buf: PackedByteArray = comp["variant"]
		var mask_buf: PackedByteArray = comp["mask"]
		var op_mask := _build_opening_mask(w, h, comp.get("openings", []))

		for y in range(h):
			for x in range(w):
				if _in_play_bounds(x, y, w, h, op_mask):
					var idx: int = y * w + x
					if TileSynth2.is_walkable(cls_buf[idx], var_buf[idx], mask_buf[idx]):
						g_walkable[base + idx] = 1

		for y in range(h):
			for x in range(w):
				var l_idx: int = y * w + x
				var u: int = base + l_idx
				if g_walkable[u] == 0:
					continue
				var outs := PackedInt32Array()
				for d in DIRS:
					var bx: int = x + d.x
					var by: int = y + d.y
					if not _in_play_bounds(bx, by, w, h, op_mask):
						continue
					var b_idx: int = by * w + bx
					if g_walkable[base + b_idx] == 1:
						outs.append(base + b_idx)
					elif cls_buf[b_idx] == TileSynth2.TILE_LEDGE:
						var cx: int = x + d.x * 2
						var cy: int = y + d.y * 2
						if _in_play_bounds(cx, cy, w, h, op_mask):
							var c_idx: int = cy * w + cx
							if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, var_buf[b_idx], cls_buf[c_idx], mask_buf[c_idx], d):
								outs.append(base + c_idx)
				g_fwd[u] = outs
				for dst in outs:
					if not g_rev.has(dst):
						g_rev[dst] = PackedInt32Array()
					var r_arr: PackedInt32Array = g_rev[dst]
					r_arr.append(u)
					g_rev[dst] = r_arr

	# Add bidirectional seam edges across aligned openings only
	for link in aligned_links:
		var id_a := str(link["id_a"])
		var id_b := str(link["id_b"])
		if not block_offset.has(id_a) or not block_offset.has(id_b):
			continue
		var base_a: int = block_offset[id_a]
		var base_b: int = block_offset[id_b]
		var comp_a: Dictionary = compiled_by_id[id_a]
		var comp_b: Dictionary = compiled_by_id[id_b]
		var wa: int = int(comp_a["w"])
		var ha: int = int(comp_a["h"])
		var wb: int = int(comp_b["w"])
		var hb: int = int(comp_b["h"])
		var loc_a := _local_outer_of_opening(link["op_a"] as Dictionary, wa, ha)
		var loc_b := _local_outer_of_opening(link["op_b"] as Dictionary, wb, hb)
		for ti in range(mini(loc_a.size(), loc_b.size())):
			var pa: Vector2i = loc_a[ti]
			var pb: Vector2i = loc_b[ti]
			var ua: int = base_a + pa.y * wa + pa.x
			var ub: int = base_b + pb.y * wb + pb.x
			if g_walkable[ua] == 1 and g_walkable[ub] == 1:
				var outs_a: PackedInt32Array = g_fwd.get(ua, PackedInt32Array())
				outs_a.append(ub)
				g_fwd[ua] = outs_a
				var outs_b: PackedInt32Array = g_fwd.get(ub, PackedInt32Array())
				outs_b.append(ua)
				g_fwd[ub] = outs_b

				var revs_b: PackedInt32Array = g_rev.get(ub, PackedInt32Array())
				revs_b.append(ua)
				g_rev[ub] = revs_b
				var revs_a: PackedInt32Array = g_rev.get(ua, PackedInt32Array())
				revs_a.append(ub)
				g_rev[ua] = revs_a

	# Strong connectivity check across all neighbourhoods' arrival tiles
	var hood_arrivals: Array[int] = []
	for h_entry in hoods:
		var hid := str(h_entry.get("id", ""))
		if not block_offset.has(hid):
			hood_arrivals.append(-1)
			continue
		var comp_h: Dictionary = compiled_by_id[hid]
		var wh: int = int(comp_h["w"])
		var arr_pt: Vector2i = comp_h.get("arrival", Vector2i.ZERO)
		var arr_u: int = int(block_offset[hid]) + arr_pt.y * wh + arr_pt.x
		hood_arrivals.append(arr_u if (arr_u >= 0 and arr_u < total_tiles and g_walkable[arr_u] == 1) else -1)

	var connected := 0
	if not hood_arrivals.is_empty() and hood_arrivals[0] >= 0:
		var root_u: int = hood_arrivals[0]
		var fwd_seen := PackedByteArray()
		fwd_seen.resize(total_tiles)
		fwd_seen.fill(0)
		fwd_seen[root_u] = 1
		var fq: Array[int] = [root_u]
		var fh := 0
		while fh < fq.size():
			var u: int = fq[fh]
			fh += 1
			var outs: PackedInt32Array = g_fwd.get(u, PackedInt32Array())
			for v in outs:
				if fwd_seen[v] == 0:
					fwd_seen[v] = 1
					fq.append(v)

		var rev_seen := PackedByteArray()
		rev_seen.resize(total_tiles)
		rev_seen.fill(0)
		rev_seen[root_u] = 1
		var rq: Array[int] = [root_u]
		var rh := 0
		while rh < rq.size():
			var u: int = rq[rh]
			rh += 1
			var ins: PackedInt32Array = g_rev.get(u, PackedInt32Array())
			for prev in ins:
				if rev_seen[prev] == 0:
					rev_seen[prev] = 1
					rq.append(prev)

		for hu in hood_arrivals:
			if hu >= 0 and fwd_seen[hu] == 1 and rev_seen[hu] == 1:
				connected += 1

	var c1_ok: bool = (hoods.size() > 0 and connected == hoods.size())
	var failed_rules: Array[String] = []
	if not c0_ok:
		failed_rules.append("C0")
	if not c1_ok:
		failed_rules.append("C1")

	return {
		"ok": failed_rules.is_empty(),
		"failed_rules": failed_rules,
		"neighbourhoods": hoods.size(),
		"routes": routes.size(),
		"legs": legs.size(),
		"openings_aligned": openings_aligned,
		"openings_total": total_links,
		"unmatched_openings": unmatched_openings,
		"connected": connected,
	}

static func _steps_for_drawing_landmark(po: Dictionary, doors_arr: Array, dist: PackedInt32Array, w: int, h: int, opening_mask: PackedByteArray) -> int:
	var form := str(po.get("form", ""))
	var x0: int = int(po["x"])
	var y0: int = int(po["y"])
	var ow: int = int(po["w"])
	var oh: int = int(po["h"])

	if form == "pending":
		if bool(po.get("has_door", false)):
			var dx: int = int(po["door_x"])
			var dy: int = int(po["door_y"]) + 1
			if _in_play_bounds(dx, dy, w, h, opening_mask):
				return dist[dy * w + dx]
			return -1
		return _nearest_box_neighbour_steps(x0, y0, ow, oh, dist, w, h, opening_mask)

	var sid: int = int(po["stamp_id"])
	var s_def: Dictionary = TileSynth2.STAMP_TABLE.get(sid, {})
	var door_v: Variant = s_def.get("door", null)
	if door_v is Array and (door_v as Array).size() == 2:
		var dx: int = x0 + int(door_v[0])
		var dy: int = y0 + int(door_v[1]) + 1
		for d_var in doors_arr:
			var d: Dictionary = d_var
			if int(d.get("stamp_id", -1)) == sid and int(d["x"]) == dx and int(d["y"]) == dy - 1:
				if _in_play_bounds(dx, dy, w, h, opening_mask):
					return dist[dy * w + dx]
		if _in_play_bounds(dx, dy, w, h, opening_mask):
			return dist[dy * w + dx]
		return -1

	return _nearest_box_neighbour_steps(x0, y0, ow, oh, dist, w, h, opening_mask)

static func _nearest_box_neighbour_steps(x0: int, y0: int, ow: int, oh: int, dist: PackedInt32Array, w: int, h: int, opening_mask: PackedByteArray) -> int:
	var best := -1
	for tx in range(x0, x0 + ow):
		for cy in [y0 - 1, y0 + oh]:
			if _in_play_bounds(tx, cy, w, h, opening_mask):
				var st: int = dist[cy * w + tx]
				if st >= 0 and (best == -1 or st < best):
					best = st
	for ty in range(y0, y0 + oh):
		for cx in [x0 - 1, x0 + ow]:
			if _in_play_bounds(cx, ty, w, h, opening_mask):
				var st: int = dist[ty * w + cx]
				if st >= 0 and (best == -1 or st < best):
					best = st
	return best
