class_name CaricatureCheck
extends RefCounted

## game/world/caricature/caricature_check.gd — Playable-Size & Reachability Measurements (Item 48a)
## Contract: docs/design_neighbourhoods_and_caricature.md §5.3,
##           docs/implementation_plan_dc_trial.md §5.1–§5.2

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")

# §5.2 Playable-size contract thresholds (new)
const MAX_UNREACHED: int = 0
const MAX_TRAPPED: int = 0
const MAX_WALK_HOOD: int = 200
const MAX_WALK_CAMP: int = 60
const MAX_LANDMARK_STEPS_HOOD: int = 120
const MAX_LANDMARK_STEPS_CAMP: int = 60
const MIN_TALL_GRASS_HOOD: float = 0.08
const MAX_TALL_GRASS_HOOD: float = 0.35
const TALL_GRASS_CAMP: float = 0.0
const MIN_SEARCH_DOORS_HOOD: int = 4
const MAX_SEARCH_DOORS_HOOD: int = 24
const MAX_SEARCH_DOORS_CAMP: int = 4
const MIN_LANDMARKS_HOOD: int = 2

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

static func _in_interior(x: int, y: int, w: int, h: int) -> bool:
	var b := CaricatureMap.BORDER
	return x >= b and x < w - b and y >= b and y < h - b

static func measure(compiled: Dictionary, area: Dictionary) -> Dictionary:
	var w: int = int(compiled.get("w", 0))
	var h: int = int(compiled.get("h", 0))
	var cls_buf: PackedByteArray = compiled.get("class", PackedByteArray())
	var var_buf: PackedByteArray = compiled.get("variant", PackedByteArray())
	var mask_buf: PackedByteArray = compiled.get("mask", PackedByteArray())
	var arrival: Vector2i = compiled.get("arrival", Vector2i.ZERO)
	var art_pending: int = int(compiled.get("art_pending", 0))

	var total: int = w * h
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(total)
	walkable_flags.fill(0)

	var walkable_count := 0
	for y in range(CaricatureMap.BORDER, h - CaricatureMap.BORDER):
		for x in range(CaricatureMap.BORDER, w - CaricatureMap.BORDER):
			var idx: int = y * w + x
			if TileSynth2.is_walkable(cls_buf[idx], var_buf[idx], mask_buf[idx]):
				walkable_flags[idx] = 1
				walkable_count += 1

	# Build directed movement graph (normal 1-step & 1-step ledge jumps) and reverse graph
	var fwd_edges: Dictionary = {} # int_idx -> PackedInt32Array
	var rev_edges: Dictionary = {} # int_idx -> PackedInt32Array
	for y in range(CaricatureMap.BORDER, h - CaricatureMap.BORDER):
		for x in range(CaricatureMap.BORDER, w - CaricatureMap.BORDER):
			var a_idx: int = y * w + x
			if walkable_flags[a_idx] == 0:
				continue
			var outs := PackedInt32Array()
			for d in DIRS:
				var bx: int = x + d.x
				var by: int = y + d.y
				if not _in_interior(bx, by, w, h):
					continue
				var b_idx: int = by * w + bx
				if walkable_flags[b_idx] == 1:
					outs.append(b_idx)
				elif cls_buf[b_idx] == TileSynth2.TILE_LEDGE:
					var cx: int = x + d.x * 2
					var cy: int = y + d.y * 2
					if _in_interior(cx, cy, w, h):
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

	if _in_interior(arrival.x, arrival.y, w, h):
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
	if _in_interior(arrival.x, arrival.y, w, h):
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

	# Search doors: doors of standing or ruined ordinary buildings whose south tile is reached
	var search_doors := 0
	var doors_arr: Array = compiled.get("doors", [])
	for d_var in doors_arr:
		var d: Dictionary = d_var
		if not bool(d.get("is_ordinary", false)):
			continue
		var sx: int = int(d["x"])
		var sy: int = int(d["y"]) + 1
		if _in_interior(sx, sy, w, h) and dist[sy * w + sx] >= 0:
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
			landmarks_present += 1
			var best_steps := -1
			for po in matching_objs:
				var step_val := _steps_for_drawing_landmark(po, doors_arr, dist, w, h)
				if step_val >= 0 and (best_steps == -1 or step_val < best_steps):
					best_steps = step_val
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
			landmarks_present += 1
			var best_steps := -1
			for sg in matching_signs:
				var sx: int = int(sg["x"])
				var sy: int = int(sg["y"])
				for d in DIRS:
					var nx: int = sx + d.x
					var ny: int = sy + d.y
					if _in_interior(nx, ny, w, h):
						var st: int = dist[ny * w + nx]
						if st >= 0 and (best_steps == -1 or st < best_steps):
							best_steps = st
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

	# Pass/fail rules P1-P7 (§5.2)
	var is_camp := (str(area.get("kind", "")) == "camp" or str(area.get("id", "")).begins_with("camp:"))
	var failed_rules: Array[String] = []

	if unreached_count != MAX_UNREACHED:
		failed_rules.append("P1")
	if trapped_count != MAX_TRAPPED:
		failed_rules.append("P2")

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
	else:
		if tall_grass_share < MIN_TALL_GRASS_HOOD or tall_grass_share > MAX_TALL_GRASS_HOOD:
			failed_rules.append("P5")

	if is_camp:
		if search_doors < 0 or search_doors > MAX_SEARCH_DOORS_CAMP:
			failed_rules.append("P6")
	else:
		if search_doors < MIN_SEARCH_DOORS_HOOD or search_doors > MAX_SEARCH_DOORS_HOOD:
			failed_rules.append("P6")

	var listed_count: int = roster_lms.size()
	if is_camp:
		if landmarks_present != listed_count:
			failed_rules.append("P7")
	else:
		if listed_count < MIN_LANDMARKS_HOOD or landmarks_present != listed_count:
			failed_rules.append("P7")

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
	}

static func _steps_for_drawing_landmark(po: Dictionary, doors_arr: Array, dist: PackedInt32Array, w: int, h: int) -> int:
	var form := str(po.get("form", ""))
	var x0: int = int(po["x"])
	var y0: int = int(po["y"])
	var ow: int = int(po["w"])
	var oh: int = int(po["h"])

	if form == "pending":
		if bool(po.get("has_door", false)):
			var dx: int = int(po["door_x"])
			var dy: int = int(po["door_y"]) + 1
			if _in_interior(dx, dy, w, h):
				return dist[dy * w + dx]
			return -1
		return _nearest_box_neighbour_steps(x0, y0, ow, oh, dist, w, h)

	var sid: int = int(po["stamp_id"])
	var s_def: Dictionary = TileSynth2.STAMP_TABLE.get(sid, {})
	var door_v: Variant = s_def.get("door", null)
	if door_v is Array and (door_v as Array).size() == 2:
		var dx: int = x0 + int(door_v[0])
		var dy: int = y0 + int(door_v[1]) + 1
		for d_var in doors_arr:
			var d: Dictionary = d_var
			if int(d.get("stamp_id", -1)) == sid and int(d["x"]) == dx and int(d["y"]) == dy - 1:
				if _in_interior(dx, dy, w, h):
					return dist[dy * w + dx]
		if _in_interior(dx, dy, w, h):
			return dist[dy * w + dx]
		return -1

	return _nearest_box_neighbour_steps(x0, y0, ow, oh, dist, w, h)

static func _nearest_box_neighbour_steps(x0: int, y0: int, ow: int, oh: int, dist: PackedInt32Array, w: int, h: int) -> int:
	var best := -1
	for tx in range(x0, x0 + ow):
		for cy in [y0 - 1, y0 + oh]:
			if _in_interior(tx, cy, w, h):
				var st: int = dist[cy * w + tx]
				if st >= 0 and (best == -1 or st < best):
					best = st
	for ty in range(y0, y0 + oh):
		for cx in [x0 - 1, x0 + ow]:
			if _in_interior(cx, ty, w, h):
				var st: int = dist[ty * w + cx]
				if st >= 0 and (best == -1 or st < best):
					best = st
	return best
