class_name CaricatureCheck
extends RefCounted

## game/world/caricature/caricature_check.gd — Playable-Size, Route & City Reachability Measurements (Items 48a, 53)
## Contract: docs/design_neighbourhoods_and_caricature.md §5.3,
##           docs/implementation_plan_dc_trial.md §5.1–§5.2, §10.5

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")
const OutdoorFixtures := preload("res://world/caricature/outdoor_fixtures.gd")

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
const EDGE_CLEAR_TILES: int = 5
const LOOSE_FURNITURE_PER_TILES: int = 500
const BOLLARD_WATER_MAX_DIST: int = 3
const MIN_WATER_ANCHOR_SHARE: float = 0.80

const LOOSE_FURNITURE_KINDS: Dictionary = {
	"standin_bench": true,
	"em_bollard": true,
	"em_planter_box": true,
}

const FENCE_FIXTURE_KINDS: Dictionary = {
	"em_iron_fence_h": true,
	"em_iron_fence_v": true,
	"em_white_fence_h": true,
	"em_white_fence_v": true,
	"em_wood_fence_post": true,
}

const FENCE_ANCHOR_FIXTURE_KINDS: Dictionary = {
	"em_statue": true,
	"em_fountain": true,
	"em_lighthouse": true,
	"em_market_stall_blue": true,
	"em_market_stall_peach": true,
	"standin_lock_gate": true,
	"em_rowboat": true,
	"em_sailboat": true,
	"em_bridge_v_rail_w": true,
	"em_bridge_v_rail_e": true,
	"em_bridge_v_pier_w": true,
	"em_bridge_v_pier_e": true,
	"em_bridge_h_rail_n": true,
	"em_bridge_h_girder": true,
	"em_bridge_h_pier": true,
}

const SOLID_ANCHOR_FIXTURE_KINDS: Dictionary = {
	"em_streetlamp": true,
	"em_statue": true,
	"em_fountain": true,
	"em_lighthouse": true,
	"em_iron_fence_h": true,
	"em_iron_fence_v": true,
	"em_white_fence_h": true,
	"em_white_fence_v": true,
	"em_wood_fence_post": true,
	"em_flower_patch": true,
	"standin_lock_gate": true,
	"em_bridge_v_rail_w": true,
	"em_bridge_v_rail_e": true,
	"em_bridge_v_pier_w": true,
	"em_bridge_v_pier_e": true,
	"em_bridge_h_rail_n": true,
	"em_bridge_h_girder": true,
	"em_bridge_h_pier": true,
	"em_market_stall_blue": true,
	"em_market_stall_peach": true,
}

# Rendered TILE_WATER baselines at d9169e9 (Decision 74 rendered-tile water anchor >= 80%)
const DC_WATER_BASELINE: Dictionary = {
	"camp:washington-dc": 38,
	"hood:washington-dc:national-mall": 46,
	"hood:washington-dc:tidal-basin": 3082,
	"hood:washington-dc:dupont-circle": 4,
	"hood:washington-dc:capitol-hill": 98,
	"hood:washington-dc:union-station": 8,
	"hood:washington-dc:georgetown": 1790,
	"hood:washington-dc:woodley-park": 397,
	"hood:washington-dc:lincoln-memorial": 3118,
	"route:washington-dc:monument-grounds#1": 0,
	"route:washington-dc:pennsylvania-avenue#1": 9,
	"route:washington-dc:constitution-gardens#1": 256,
	"route:washington-dc:west-potomac-park#1": 654,
	"route:washington-dc:west-potomac-park#2": 19,
	"route:washington-dc:upper-senate-park#1": 20,
	"route:washington-dc:q-street#1": 196,
	"route:washington-dc:connecticut-avenue#1": 182,
	"route:washington-dc:massachusetts-avenue#1": 0,
	"route:washington-dc:rock-creek-trail#1": 426,
	"route:washington-dc:rock-creek-trail#2": 150,
	"route:washington-dc:potomac-riverfront#1": 1245,
}

const MIN_THINGS_PER_150_ROUTE: float = 0.9
const MAX_SIGN_SHARE_ROUTE: float = 1.0 / 3.0
const MAX_ITEM_SHARE_ROUTE: float = 0.5
const MAX_DOOR_SHARE_ROUTE: float = 1.0 / 3.0
const MAX_OPEN_GROUND_ROUTE: float = 0.13
const MAX_REPEAT_8X8_ROUTE: int = 5

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

static func _is_retired_block_stamp(sname: String) -> bool:
	return (
		sname.begins_with("standing_block_16x14_")
		or sname.begins_with("standing_block_23x14_")
		or sname == "ruined_block_16x14_b"
		or sname == "ruined_block_23x14_b"
	)

static func _is_route_only_large_block(sname: String) -> bool:
	return sname == "ruined_block_16x14_a" or sname == "ruined_block_23x14_a"

static func _stamp_name_for_placed(po: Dictionary) -> String:
	var sid := int(po.get("stamp_id", 0))
	if sid > 0 and TileSynth2.STAMP_TABLE.has(sid):
		return str((TileSynth2.STAMP_TABLE[sid] as Dictionary).get("id", ""))
	return str(po.get("stamp_str", ""))

static func _within_edge_clear_of_opening(x: int, y: int, w: int, h: int, openings: Array) -> bool:
	for op_var in openings:
		if not (op_var is Dictionary):
			continue
		var op: Dictionary = op_var
		var side := str(op.get("side", ""))
		var op_at := int(op.get("at", 0))
		var op_w := int(op.get("width", 0))
		if op_w <= 0:
			continue
		var dx := 9999
		var dy := 9999
		if side == "N":
			dx = maxi(0, maxi(op_at - x, x - (op_at + op_w - 1)))
			dy = y
		elif side == "S":
			dx = maxi(0, maxi(op_at - x, x - (op_at + op_w - 1)))
			dy = (h - 1) - y
		elif side == "W":
			dx = x
			dy = maxi(0, maxi(op_at - y, y - (op_at + op_w - 1)))
		elif side == "E":
			dx = (w - 1) - x
			dy = maxi(0, maxi(op_at - y, y - (op_at + op_w - 1)))
		if maxi(dx, dy) <= EDGE_CLEAR_TILES:
			return true
	return false

static func _violates_edge_clear(x: int, y: int, w: int, h: int, openings: Array) -> bool:
	if x >= EDGE_CLEAR_TILES and x < w - EDGE_CLEAR_TILES and y >= EDGE_CLEAR_TILES and y < h - EDGE_CLEAR_TILES:
		return false
	return not _within_edge_clear_of_opening(x, y, w, h, openings)

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

static func _build_directed_graph(
	w: int,
	h: int,
	cls_buf: PackedByteArray,
	var_buf: PackedByteArray,
	mask_buf: PackedByteArray,
	opening_mask: PackedByteArray,
	walkable_flags: PackedByteArray
) -> Dictionary:
	var fwd_edges: Dictionary = {}
	var rev_edges: Dictionary = {}
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
	return {"fwd": fwd_edges, "rev": rev_edges}

static func _count_trapped_in_graph(
	total: int,
	arr_idx: int,
	walkable_flags: PackedByteArray,
	graph: Dictionary
) -> int:
	if arr_idx < 0 or arr_idx >= total or walkable_flags[arr_idx] == 0:
		return 0
	var fwd_edges: Dictionary = graph["fwd"]
	var rev_edges: Dictionary = graph["rev"]
	var fwd_seen := PackedByteArray()
	fwd_seen.resize(total)
	fwd_seen.fill(0)
	fwd_seen[arr_idx] = 1
	var fq: Array[int] = [arr_idx]
	var fh := 0
	while fh < fq.size():
		var u: int = fq[fh]
		fh += 1
		for v in (fwd_edges.get(u, PackedInt32Array()) as PackedInt32Array):
			if fwd_seen[v] == 0:
				fwd_seen[v] = 1
				fq.append(v)

	var rev_seen := PackedByteArray()
	rev_seen.resize(total)
	rev_seen.fill(0)
	rev_seen[arr_idx] = 1
	var rq: Array[int] = [arr_idx]
	var rh := 0
	while rh < rq.size():
		var u: int = rq[rh]
		rh += 1
		for prev in (rev_edges.get(u, PackedInt32Array()) as PackedInt32Array):
			if rev_seen[prev] == 0:
				rev_seen[prev] = 1
				rq.append(prev)

	var trapped := 0
	for i in range(total):
		if fwd_seen[i] == 1 and rev_seen[i] == 0:
			trapped += 1
	return trapped

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
	var base_flags := PackedByteArray()
	base_flags.resize(total)
	base_flags.fill(0)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(total)
	walkable_flags.fill(0)

	var walkable_count := 0
	var item_balls := 0
	for y in range(h):
		for x in range(w):
			if not _in_play_bounds(x, y, w, h, opening_mask):
				continue
			var idx: int = y * w + x
			var cls: int = cls_buf[idx]
			if cls == TileSynth2.TILE_ITEM_BALL:
				item_balls += 1
			var solid_mask: PackedByteArray = compiled.get("solid_mask", PackedByteArray())
			var blocked_by_entity: bool = (solid_mask.size() == total and solid_mask[idx] == 1)
			var is_base_w := (not blocked_by_entity) and TileSynth2.is_walkable(cls, var_buf[idx], mask_buf[idx])
			if is_base_w:
				base_flags[idx] = 1
			if is_base_w or ((not blocked_by_entity) and TileSynth2.is_field_clearable(cls)):
				walkable_flags[idx] = 1
				walkable_count += 1

	var arr_idx_global: int = (arrival.y * w + arrival.x) if _in_play_bounds(arrival.x, arrival.y, w, h, opening_mask) else -1
	var base_graph := _build_directed_graph(w, h, cls_buf, var_buf, mask_buf, opening_mask, base_flags)
	var base_trapped_count := _count_trapped_in_graph(total, arr_idx_global, base_flags, base_graph)

	# Build Full movement graph (includes Cut/Rock Smash/Strength clearable obstacles)
	var full_graph := _build_directed_graph(w, h, cls_buf, var_buf, mask_buf, opening_mask, walkable_flags)
	var fwd_edges: Dictionary = full_graph["fwd"]
	var rev_edges: Dictionary = full_graph["rev"]

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
		var base_fwd: Dictionary = base_graph["fwd"]
		var d_from_0 := _bfs_from_sources(out0, w, h, base_flags, base_fwd)
		var d_from_1 := _bfs_from_sources(out1, w, h, base_flags, base_fwd)
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
	if trapped_count != MAX_TRAPPED or base_trapped_count != MAX_TRAPPED:
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

	# P11 (Decision 71/72): Retired large blocks forbidden anywhere; ruined 16x14_a / 23x14_a route-ground only
	var retired_blocks := 0
	var town_rects_m: Array = compiled.get("town", [])
	for po_var in placed_objs:
		var po: Dictionary = po_var
		var sname := _stamp_name_for_placed(po)
		if _is_retired_block_stamp(sname):
			retired_blocks += 1
		elif _is_route_only_large_block(sname) and not town_rects_m.is_empty():
			var ox: int = int(po.get("x", 0))
			var oy: int = int(po.get("y", 0))
			var ow: int = int(po.get("w", 0))
			var oh: int = int(po.get("h", 0))
			var touches_t := false
			for rv in town_rects_m:
				if rv is Array and (rv as Array).size() == 4:
					var ra: Array = rv
					var rx0: int = int(ra[0])
					var ry0: int = int(ra[1])
					var rx1: int = rx0 + int(ra[2])
					var ry1: int = ry0 + int(ra[3])
					if ox < rx1 and (ox + ow) > rx0 and oy < ry1 and (oy + oh) > ry0:
						touches_t = true
						break
			if touches_t:
				retired_blocks += 1
	if retired_blocks > 0:
		failed_rules.append("P11")

	# P12 (Decision 72): Nothing to meet or find within 5 tiles of a map edge unless within 5 tiles of an opening
	var edge_violations := 0
	if w >= 16 and h >= 16:
		for pv in (compiled.get("people", []) as Array):
			var p: Dictionary = pv
			if _violates_edge_clear(int(p["x"]), int(p["y"]), w, h, openings):
				edge_violations += 1
		for kv in (compiled.get("street_pokemon", []) as Array):
			var k: Dictionary = kv
			if _violates_edge_clear(int(k["x"]), int(k["y"]), w, h, openings):
				edge_violations += 1
		for sv in signs_arr:
			var s: Dictionary = sv
			if _violates_edge_clear(int(s["x"]), int(s["y"]), w, h, openings):
				edge_violations += 1
		for hv in (compiled.get("hidden_items", []) as Array):
			var hd: Dictionary = hv
			if _violates_edge_clear(int(hd["x"]), int(hd["y"]), w, h, openings):
				edge_violations += 1
		for y_e in range(h):
			for x_e in range(w):
				if cls_buf[y_e * w + x_e] == TileSynth2.TILE_ITEM_BALL:
					if _violates_edge_clear(x_e, y_e, w, h, openings):
						edge_violations += 1
		for dv in doors_arr:
			var dd: Dictionary = dv
			var is_open_d := not str(dd.get("interior", "")).is_empty()
			var is_ord_d := bool(dd.get("is_ordinary", false))
			if is_open_d or is_ord_d:
				if _violates_edge_clear(int(dd["x"]), int(dd["y"]), w, h, openings):
					edge_violations += 1
	if edge_violations > 0:
		failed_rules.append("P12")

	# P13 (Decision 74): Loose furniture count (<= 1 per 500 map tiles), never alone (8-neighbour solid anchor),
	# bollards within 3 tiles of rendered water; plus rendered-tile water anchor (>= 80% of baseline).
	var anchor_mask := PackedByteArray()
	anchor_mask.resize(total)
	anchor_mask.fill(0)
	var rendered_water := 0
	for i_w in range(total):
		var c_w: int = cls_buf[i_w]
		if c_w == TileSynth2.TILE_WATER:
			rendered_water += 1
			anchor_mask[i_w] = 1
		elif (
			c_w == TileSynth2.TILE_TREE
			or c_w == TileSynth2.TILE_FENCE
			or c_w == TileSynth2.TILE_FLOWERS
			or c_w == TileSynth2.TILE_LEDGE
			or c_w == TileSynth2.TILE_CLIFF
			or c_w == TileSynth2.TILE_ROOF
			or c_w == TileSynth2.TILE_WALL
			or c_w == TileSynth2.TILE_DOOR
			or c_w == TileSynth2.TILE_CUT_TREE
			or c_w == TileSynth2.TILE_SMASH_ROCK
			or c_w == TileSynth2.TILE_BOULDER
		):
			anchor_mask[i_w] = 1
		elif c_w == TileSynth2.TILE_STAMP:
			var s_id_w: int = var_buf[i_w]
			var s_kind_w := str((TileSynth2.STAMP_TABLE.get(s_id_w, {}) as Dictionary).get("kind", ""))
			if s_kind_w != "decal":
				anchor_mask[i_w] = 1

	var fixtures_arr: Array = compiled.get("fixtures", [])
	for fxv in fixtures_arr:
		var fx: Dictionary = fxv
		var fkind := str(fx.get("kind", ""))
		if not SOLID_ANCHOR_FIXTURE_KINDS.has(fkind):
			continue
		var fx0: int = int(fx.get("x", 0))
		var fy0: int = int(fx.get("y", 0))
		var fw: int = int(fx.get("w", 1))
		var fh: int = int(fx.get("h", 1))
		var fbr: int = int(fx.get("base_rows", 1))
		var y_start: int = fy0 + (fh - mini(fh, fbr)) if fbr > 0 else fy0
		for ay in range(maxi(0, y_start), mini(h, fy0 + fh)):
			for ax in range(maxi(0, fx0), mini(w, fx0 + fw)):
				anchor_mask[ay * w + ax] = 1

	var loose_benches := 0
	var loose_bollards := 0
	var loose_planters := 0
	var loose_alone := 0
	var bollard_far := 0
	for fxv in fixtures_arr:
		var fx: Dictionary = fxv
		var fkind := str(fx.get("kind", ""))
		if not LOOSE_FURNITURE_KINDS.has(fkind):
			continue
		if fkind == "standin_bench":
			loose_benches += 1
		elif fkind == "em_bollard":
			loose_bollards += 1
		elif fkind == "em_planter_box":
			loose_planters += 1
		var fx0: int = int(fx.get("x", 0))
		var fy0: int = int(fx.get("y", 0))
		var fw: int = int(fx.get("w", 1))
		var fh: int = int(fx.get("h", 1))
		var touches_anchor := false
		for ty in range(fy0, fy0 + fh):
			for tx in range(fx0, fx0 + fw):
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx: int = tx + dx
						var ny: int = ty + dy
						if nx >= fx0 and nx < fx0 + fw and ny >= fy0 and ny < fy0 + fh:
							continue
						if nx >= 0 and nx < w and ny >= 0 and ny < h and anchor_mask[ny * w + nx] == 1:
							touches_anchor = true
							break
					if touches_anchor:
						break
				if touches_anchor:
					break
			if touches_anchor:
				break
		if not touches_anchor:
			loose_alone += 1
		if fkind == "em_bollard":
			var near_water := false
			for ty in range(fy0, fy0 + fh):
				for tx in range(fx0, fx0 + fw):
					for dy in range(-BOLLARD_WATER_MAX_DIST, BOLLARD_WATER_MAX_DIST + 1):
						var ny: int = ty + dy
						if ny < 0 or ny >= h:
							continue
						var rem: int = BOLLARD_WATER_MAX_DIST - absi(dy)
						for dx in range(-rem, rem + 1):
							var nx: int = tx + dx
							if nx >= 0 and nx < w and cls_buf[ny * w + nx] == TileSynth2.TILE_WATER:
								near_water = true
								break
						if near_water:
							break
					if near_water:
						break
				if near_water:
					break
			if not near_water:
				bollard_far += 1

	var loose_total: int = loose_benches + loose_bollards + loose_planters
	var loose_max: int = int(total / LOOSE_FURNITURE_PER_TILES)

	# P13d (Decision 75): No lone fence runs — every 4-connected run of fence tiles
	# (TILE_FENCE plus iron/white/wood fence fixtures) must touch, in its 8 neighbours,
	# a solid non-fence/non-loose anchor (building/wall/door/roof/solid stamp, tree/cut tree,
	# water/marsh, ledge/cliff, rock/boulder, or solid statue/fountain/stall/bridge/boat/lock-gate).
	var fence_mask := PackedByteArray()
	fence_mask.resize(total)
	fence_mask.fill(0)
	var fence_anchor_mask := PackedByteArray()
	fence_anchor_mask.resize(total)
	fence_anchor_mask.fill(0)
	for i_f in range(total):
		var c_f: int = cls_buf[i_f]
		if c_f == TileSynth2.TILE_FENCE:
			fence_mask[i_f] = 1
		elif (
			c_f == TileSynth2.TILE_TREE
			or c_f == TileSynth2.TILE_WATER
			or c_f == TileSynth2.TILE_MARSH
			or c_f == TileSynth2.TILE_ROOF
			or c_f == TileSynth2.TILE_WALL
			or c_f == TileSynth2.TILE_DOOR
			or c_f == TileSynth2.TILE_LEDGE
			or c_f == TileSynth2.TILE_CLIFF
			or c_f == TileSynth2.TILE_CUT_TREE
			or c_f == TileSynth2.TILE_SMASH_ROCK
			or c_f == TileSynth2.TILE_BOULDER
		):
			fence_anchor_mask[i_f] = 1
		elif c_f == TileSynth2.TILE_STAMP:
			if (mask_buf[i_f] & TileSynth2.STAMP_FLAG_SOLID) != 0:
				fence_anchor_mask[i_f] = 1

	for fxv in fixtures_arr:
		var fx: Dictionary = fxv
		var fkind := str(fx.get("kind", ""))
		var fx0: int = int(fx.get("x", 0))
		var fy0: int = int(fx.get("y", 0))
		var fw: int = int(fx.get("w", 1))
		var fh: int = int(fx.get("h", 1))
		var fbr: int = int(fx.get("base_rows", 1))
		var y_start: int = fy0 + (fh - mini(fh, fbr)) if fbr > 0 else fy0
		if FENCE_FIXTURE_KINDS.has(fkind):
			for ay in range(maxi(0, y_start), mini(h, fy0 + fh)):
				for ax in range(maxi(0, fx0), mini(w, fx0 + fw)):
					fence_mask[ay * w + ax] = 1
		elif FENCE_ANCHOR_FIXTURE_KINDS.has(fkind):
			for ay in range(maxi(0, y_start), mini(h, fy0 + fh)):
				for ax in range(maxi(0, fx0), mini(w, fx0 + fw)):
					fence_anchor_mask[ay * w + ax] = 1

	var fence_visited := PackedByteArray()
	fence_visited.resize(total)
	fence_visited.fill(0)
	var fence_runs := 0
	var lone_fence_runs := 0
	for sy_f in range(h):
		for sx_f in range(w):
			var s_idx: int = sy_f * w + sx_f
			if fence_mask[s_idx] == 0 or fence_visited[s_idx] != 0:
				continue
			fence_runs += 1
			var queue_f: Array[Vector2i] = [Vector2i(sx_f, sy_f)]
			fence_visited[s_idx] = 1
			var qi := 0
			var run_anchored := false
			while qi < queue_f.size():
				var cur: Vector2i = queue_f[qi]
				qi += 1
				if not run_anchored:
					for dy_a in range(-1, 2):
						for dx_a in range(-1, 2):
							if dx_a == 0 and dy_a == 0:
								continue
							var nx_a: int = cur.x + dx_a
							var ny_a: int = cur.y + dy_a
							if nx_a >= 0 and nx_a < w and ny_a >= 0 and ny_a < h and fence_anchor_mask[ny_a * w + nx_a] == 1:
								run_anchored = true
								break
						if run_anchored:
							break
				for d_f in DIRS:
					var nx_f: int = cur.x + d_f.x
					var ny_f: int = cur.y + d_f.y
					if nx_f >= 0 and nx_f < w and ny_f >= 0 and ny_f < h:
						var n_idx: int = ny_f * w + nx_f
						if fence_mask[n_idx] == 1 and fence_visited[n_idx] == 0:
							fence_visited[n_idx] = 1
							queue_f.append(Vector2i(nx_f, ny_f))
			if not run_anchored:
				lone_fence_runs += 1

	if not is_camp:
		if loose_total > loose_max:
			failed_rules.append("P13a")
		if loose_alone > 0:
			failed_rules.append("P13b")
		if bollard_far > 0:
			failed_rules.append("P13c")
		if use_route_rules and lone_fence_runs > 0:
			failed_rules.append("P13d")

	var water_baseline: int = int(DC_WATER_BASELINE.get(aid, -1))
	if water_baseline > 0 and float(rendered_water) + 0.000001 < MIN_WATER_ANCHOR_SHARE * float(water_baseline):
		failed_rules.append("WATER")

	return {
		"ok": failed_rules.is_empty(),
		"failed_rules": failed_rules,
		"walkable": walkable_count,
		"reached": reached_count,
		"unreached": unreached_count,
		"trapped": trapped_count,
		"base_trapped": base_trapped_count,
		"item_balls": item_balls,
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
		"retired_blocks": retired_blocks,
		"edge_violations": edge_violations,
		"loose_benches": loose_benches,
		"loose_bollards": loose_bollards,
		"loose_planters": loose_planters,
		"loose_total": loose_total,
		"loose_max": loose_max,
		"loose_alone": loose_alone,
		"bollard_far": bollard_far,
		"fence_runs": fence_runs,
		"lone_fence_runs": lone_fence_runs,
		"rendered_water": rendered_water,
		"water_baseline": water_baseline,
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


const MIN_THINGS_PER_150_TOWN: float = 4.0
const MIN_THINGS_PER_150_LAND_HOOD: float = 1.85
const MIN_WALK_LAND_PCT_HOOD: float = 0.30
const MAX_TREE_LAND_PCT_HOOD: float = 0.25
const MIN_TOWN_LAND_HOOD: int = 2500
const MAX_TOWN_LAND_HOOD: int = 3500
const MAX_OPEN_GROUND_TOWN: float = 0.05
const MAX_TOWN_SIGNS_CAMP: int = 19
const MAX_TOWN_ITEMS_CAMP: int = 8
const MAX_TOWN_SIGNS_HOOD: int = 13
const MAX_TOWN_ITEMS_HOOD: int = 8

static var _spawn_pool_cache: Dictionary = {}

static func _load_spawn_zones() -> Dictionary:
	if _spawn_pool_cache.has("zones"):
		return _spawn_pool_cache["zones"]
	var zones_out: Dictionary = {}
	var path := "res://config/spawn_tables.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var raw_zones: Dictionary = (parsed as Dictionary).get("zones", {})
			for z_v in raw_zones.keys():
				var z_name := str(z_v).strip_edges().to_lower()
				var zd: Dictionary = raw_zones[z_v]
				var dex_set: Dictionary = {}
				for sub in ["regular", "haunted"]:
					for ev in (zd.get(sub, []) as Array):
						if ev is Dictionary:
							var dex := int((ev as Dictionary).get("dex", 0))
							if dex >= 1 and dex <= 649:
								dex_set[dex] = true
				zones_out[z_name] = dex_set
	_spawn_pool_cache["zones"] = zones_out
	return zones_out

static func _allowed_dex_pools_for_area(area: Dictionary, rend_cls: PackedByteArray) -> Dictionary:
	var all_zones := _load_spawn_zones()
	var area_zones: Dictionary = {}
	var primary_z := str(area.get("zone", "")).strip_edges().to_lower()
	if not primary_z.is_empty():
		area_zones[primary_z] = true
	var haunt_z := str(area.get("haunt_site", "")).strip_edges().to_lower()
	if not haunt_z.is_empty():
		area_zones[haunt_z] = true
	for i in range(rend_cls.size()):
		if rend_cls[i] == TileSynth2.TILE_WATER:
			area_zones["waterfront"] = true
			break
	var all_dex: Dictionary = {}
	var by_zone: Dictionary = {}
	for z_key in area_zones.keys():
		var z_dex: Dictionary = all_zones.get(z_key, {})
		by_zone[z_key] = z_dex
		for dex in z_dex.keys():
			all_dex[dex] = true
	return {"zones": area_zones, "by_zone": by_zone, "all_dex": all_dex}


static func check_town(compiled: Dictionary, area: Dictionary, town_rect_override: Array = []) -> Dictionary:
	var w: int = int(compiled.get("w", 0))
	var h: int = int(compiled.get("h", 0))
	var origin: Vector2i = compiled.get("origin", Vector2i.ZERO)
	var cols: int = int(compiled.get("cols", 1))
	var rows: int = int(compiled.get("rows", 1))
	var total: int = w * h
	var aid := str(area.get("id", ""))
	var akind := str(area.get("kind", str(compiled.get("kind", ""))))
	var is_camp := (akind == "camp" or aid.begins_with("camp:"))
	var is_route := (akind == "route" or aid.begins_with("route:"))
	var is_hood := (not is_camp and not is_route)

	var rects: Array = town_rect_override if not town_rect_override.is_empty() else (compiled.get("town", []) as Array)
	var town_mask := PackedByteArray()
	town_mask.resize(total)
	town_mask.fill(0)
	var town_tile_count := 0
	for rv in rects:
		if rv is Array and (rv as Array).size() >= 4:
			var rx0 := clampi(int(rv[0]), 0, w)
			var ry0 := clampi(int(rv[1]), 0, h)
			var rw := clampi(int(rv[2]), 0, w - rx0)
			var rh := clampi(int(rv[3]), 0, h - ry0)
			for ry in range(ry0, ry0 + rh):
				for rx in range(rx0, rx0 + rw):
					var tidx := ry * w + rx
					if town_mask[tidx] == 0:
						town_mask[tidx] = 1
						town_tile_count += 1

	# Collect rendered buffer slices across all cells for T2, T3, T4
	var rend_cls := PackedByteArray()
	rend_cls.resize(total)
	var rend_var := PackedByteArray()
	rend_var.resize(total)
	var rend_mask := PackedByteArray()
	rend_mask.resize(total)
	var tile_stamp := PackedInt32Array()
	tile_stamp.resize(total)
	tile_stamp.fill(0)
	var tile_fix := PackedInt32Array()
	tile_fix.resize(total)
	tile_fix.fill(0)

	var fix_id_map: Dictionary = {}
	for fxv in (compiled.get("fixtures", []) as Array):
		var fx: Dictionary = fxv
		var fkind := str(fx.get("kind", ""))
		if not fix_id_map.has(fkind):
			fix_id_map[fkind] = fix_id_map.size() + 1
		var fid: int = int(fix_id_map[fkind])
		var fx0: int = int(fx["x"])
		var fy0: int = int(fx["y"])
		for fy in range(fy0, mini(h, fy0 + int(fx["h"]))):
			for fx_x in range(fx0, mini(w, fx0 + int(fx["w"]))):
				tile_fix[fy * w + fx_x] = fid * 1024 + (fy - fy0) * 32 + (fx_x - fx0)

	for pv in (compiled.get("placed_objects", []) as Array):
		var po: Dictionary = pv
		var sid := int(po.get("stamp_id", 0))
		if sid <= 0:
			continue
		var bx0: int = int(po["x"])
		var by0: int = int(po["y"])
		for sy in range(by0, mini(h, by0 + int(po["h"]))):
			for sx in range(bx0, mini(w, bx0 + int(po["w"]))):
				tile_stamp[sy * w + sx] = sid * 1024 + (sy - by0) * 32 + (sx - bx0)

	for r_cell in range(rows):
		var cy: int = origin.y + rows - 1 - r_cell
		for c_cell in range(cols):
			var cx: int = origin.x + c_cell
			var cres := CaricatureMap.cell_result(compiled, Vector2i(cx, cy), area)
			var cbuf: PackedByteArray = cres.get("tiles", PackedByteArray())
			if cbuf.size() < 32 * 32 * 3:
				continue
			for ty in range(32):
				var my: int = r_cell * 32 + ty
				for tx in range(32):
					var mx: int = c_cell * 32 + tx
					var cidx := (ty * 32 + tx) * 3
					var gidx := my * w + mx
					rend_cls[gidx] = cbuf[cidx]
					rend_var[gidx] = cbuf[cidx + 1]
					rend_mask[gidx] = cbuf[cidx + 2]

	# Reachability & walkable flags
	var m_res := measure(compiled, area)
	var openings: Array = compiled.get("openings", [])
	var opening_mask := _build_opening_mask(w, h, openings)
	var solid_mask: PackedByteArray = compiled.get("solid_mask", PackedByteArray())
	var walk_flags := PackedByteArray()
	walk_flags.resize(total)
	walk_flags.fill(0)
	for y in range(h):
		for x in range(w):
			if not _in_play_bounds(x, y, w, h, opening_mask):
				continue
			var i := y * w + x
			var blocked := (solid_mask.size() == total and solid_mask[i] == 1)
			if not blocked and (TileSynth2.is_walkable(rend_cls[i], rend_var[i], rend_mask[i]) or TileSynth2.is_field_clearable(rend_cls[i])):
				walk_flags[i] = 1
	var arrival: Vector2i = compiled.get("arrival", Vector2i.ZERO)
	var graph := _build_directed_graph(w, h, compiled["class"], compiled["variant"], compiled["mask"], opening_mask, walk_flags)
	var dist := _bfs_from_sources([arrival], w, h, walk_flags, graph["fwd"])

	# T1: Interactive things in town
	var things_map: Dictionary = {} # Vector2i -> count
	var doors_arr: Array = compiled.get("doors", [])
	var door_tile_meta: Dictionary = {}
	for dv_meta in doors_arr:
		var dm: Dictionary = dv_meta
		door_tile_meta[Vector2i(int(dm["x"]), int(dm["y"]))] = {
			"stamp_id": int(dm.get("stamp_id", 0)),
			"interior": str(dm.get("interior", "")),
		}
	var total_doorways := 0
	var open_doors_in_town := 0
	var open_house_doors := 0
	var bad_doors := 0
	var door_interior_survivors := 0
	var checked_interiors: Dictionary = {}
	for dv in doors_arr:
		var d: Dictionary = dv
		var dx: int = int(d["x"])
		var dy: int = int(d["y"])
		var sid := int(d.get("stamp_id", 0))
		var iid := str(d.get("interior", ""))
		var pos := Vector2i(dx, dy)
		var left_pos := Vector2i(dx - 1, dy)
		var is_second_half := false
		if door_tile_meta.has(left_pos):
			var lm: Dictionary = door_tile_meta[left_pos]
			if int(lm["stamp_id"]) == sid and str(lm["interior"]) == iid:
				is_second_half = true
		if not is_second_half:
			total_doorways += 1
		if iid.is_empty():
			continue
		var in_town_d := (dx >= 0 and dx < w and dy >= 0 and dy < h and town_mask[dy * w + dx] == 1)
		var ipath := InteriorMap.resolve_interior_path(iid)
		if in_town_d and not is_second_half:
			open_doors_in_town += 1
			if ipath.find("/houses/") != -1:
				open_house_doors += 1
			things_map[pos] = int(things_map.get(pos, 0)) + 1
		if ipath.is_empty():
			bad_doors += 1
			continue
		var idoc := InteriorMap.load_json(ipath)
		var ic := InteriorCheck.compile_and_check(idoc)
		if not bool(ic.get("ok", false)):
			bad_doors += 1
		if not checked_interiors.has(ipath):
			checked_interiors[ipath] = true
			for flv in (idoc.get("floors", []) as Array):
				if flv is Dictionary:
					door_interior_survivors += ((flv as Dictionary).get("npcs", []) as Array).size()
		var d_south_y := dy + 1
		if not _in_play_bounds(dx, d_south_y, w, h, opening_mask) or dist[d_south_y * w + dx] < 0:
			bad_doors += 1

	var people_arr: Array = compiled.get("people", [])
	for pv in people_arr:
		var p: Dictionary = pv
		var ppos := Vector2i(int(p["x"]), int(p["y"]))
		if town_mask[ppos.y * w + ppos.x] == 1:
			things_map[ppos] = int(things_map.get(ppos, 0)) + 1

	var town_signs := 0
	for sv in (compiled.get("signs", []) as Array):
		var s: Dictionary = sv
		var spos := Vector2i(int(s["x"]), int(s["y"]))
		if spos.x >= 0 and spos.x < w and spos.y >= 0 and spos.y < h and town_mask[spos.y * w + spos.x] == 1:
			town_signs += 1
			things_map[spos] = int(things_map.get(spos, 0)) + 1

	var street_pkm: Array = compiled.get("street_pokemon", [])
	for kv in street_pkm:
		var k: Dictionary = kv
		var kpos := Vector2i(int(k["x"]), int(k["y"]))
		if town_mask[kpos.y * w + kpos.x] == 1:
			things_map[kpos] = int(things_map.get(kpos, 0)) + 1

	var hidden_arr: Array = compiled.get("hidden_items", [])
	var hidden_in_town := 0
	var hidden_in_route := 0
	for hv in hidden_arr:
		var h_dict: Dictionary = hv
		var hpos := Vector2i(int(h_dict["x"]), int(h_dict["y"]))
		if hpos.x >= 0 and hpos.x < w and hpos.y >= 0 and hpos.y < h and town_mask[hpos.y * w + hpos.x] == 1:
			hidden_in_town += 1
			things_map[hpos] = int(things_map.get(hpos, 0)) + 1
		else:
			hidden_in_route += 1

	var items_in_town := hidden_in_town
	var items_in_route := 0
	var walk_in_town := 0
	var town_land_tiles := 0
	var town_trees := 0
	var town_tall_grass := 0
	var town_ground_total := 0
	var town_worn_total := 0
	var route_ground_total := 0
	var route_worn_total := 0
	var worn_mask := PackedByteArray()
	worn_mask.resize(total)
	worn_mask.fill(0)
	var route_tiles := 0

	for y in range(h):
		for x in range(w):
			var i := y * w + x
			var cls: int = rend_cls[i]
			var rv: int = rend_var[i]
			var is_paving := (cls == TileSynth2.TILE_PATH or cls == TileSynth2.TILE_PLAZA or cls == TileSynth2.TILE_ROAD)
			if town_mask[i] == 1:
				if cls != TileSynth2.TILE_WATER:
					town_land_tiles += 1
				if cls == TileSynth2.TILE_TREE:
					town_trees += 1
				if walk_flags[i] == 1:
					walk_in_town += 1
				if cls == TileSynth2.TILE_ITEM_BALL:
					items_in_town += 1
					var ipos := Vector2i(x, y)
					things_map[ipos] = int(things_map.get(ipos, 0)) + 1
				if cls == TileSynth2.TILE_TALL_GRASS:
					town_tall_grass += 1
				if is_paving and _in_play_bounds(x, y, w, h, opening_mask):
					town_ground_total += 1
					if rv == 1:
						town_worn_total += 1
						worn_mask[i] = 1
			else:
				if _in_interior(x, y, w, h):
					route_tiles += 1
					if cls == TileSynth2.TILE_ITEM_BALL:
						items_in_route += 1
				if is_paving and _in_play_bounds(x, y, w, h, opening_mask):
					route_ground_total += 1
					if rv == 1:
						route_worn_total += 1
						worn_mask[i] = 1

	# T7: Open ground (walkable in town whose whole 7x7 square in walk_flags is walkable)
	var open_ground_tiles := 0
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if town_mask[i] == 0 or walk_flags[i] == 0:
				continue
			var all_49_walkable := true
			for dy in range(-3, 4):
				var ny := y + dy
				if ny < 0 or ny >= h:
					all_49_walkable = false
					break
				for dx in range(-3, 4):
					var nx := x + dx
					if nx < 0 or nx >= w or walk_flags[ny * w + nx] == 0:
						all_49_walkable = false
						break
				if not all_49_walkable:
					break
			if all_49_walkable:
				open_ground_tiles += 1
	var open_ground_pct: float = 0.0 if walk_in_town == 0 else (float(open_ground_tiles) / float(walk_in_town))

	var total_windows := 0
	var empty_windows := 0
	for wy in range(0, maxi(1, h - 9), 5):
		for wx in range(0, maxi(1, w - 14), 5):
			var tw_walk := 0
			for yy in range(wy, mini(h, wy + 10)):
				for xx in range(wx, mini(w, wx + 15)):
					var ti := yy * w + xx
					if town_mask[ti] == 1 and walk_flags[ti] == 1:
						tw_walk += 1
			if tw_walk < 75:
				continue
			total_windows += 1
			var win_things := 0
			for pt_v in things_map.keys():
				var pt: Vector2i = pt_v
				if pt.x >= wx and pt.x < wx + 15 and pt.y >= wy and pt.y < wy + 10:
					win_things += int(things_map[pt_v])
			if win_things == 0:
				empty_windows += 1

	var things_in_town := 0
	for cnt in things_map.values():
		things_in_town += int(cnt)
	var empty_share: float = 1.0 if total_windows == 0 else (float(empty_windows) / float(total_windows))
	var things_per_150: float = float(things_in_town) / maxf(1.0, float(walk_in_town) / 150.0)
	var things_per_150_land: float = 0.0 if town_land_tiles == 0 else (float(things_in_town) / (float(town_land_tiles) / 150.0))
	var walk_land_pct: float = 0.0 if town_land_tiles == 0 else (float(walk_in_town) / float(town_land_tiles))
	var tree_land_pct: float = 0.0 if town_land_tiles == 0 else (float(town_trees) / float(town_land_tiles))
	var town_wear_pct: float = 0.0 if town_ground_total == 0 else (float(town_worn_total) / float(town_ground_total))
	var route_wear_pct: float = 0.0 if route_ground_total == 0 else (float(route_worn_total) / float(route_ground_total))
	var whole_ground_total: int = town_ground_total + route_ground_total
	var whole_worn_total: int = town_worn_total + route_worn_total
	var wear_pct: float = 0.0 if whole_ground_total == 0 else (float(whole_worn_total) / float(whole_ground_total))

	var wear_touch := 0
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if worn_mask[i] == 0:
				continue
			for nd in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var nx: int = x + nd.x
				var ny: int = y + nd.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and worn_mask[ny * w + nx] == 1:
					wear_touch += 1

	# T4: Repeated non-uniform 8x8 patches inside town (layout key without variant byte; repeat iff distance >= 8 in x or y)
	var patch_seen: Dictionary = {} # key -> Array[Vector2i]
	var repeat_8x8 := 0
	for y0 in range(0, maxi(0, h - 7)):
		for x0 in range(0, maxi(0, w - 7)):
			var all_town := true
			var first_cls := int(rend_cls[y0 * w + x0])
			var uniform := true
			var parts := PackedStringArray()
			parts.resize(64)
			var p_i := 0
			for dy in range(8):
				var row_off := (y0 + dy) * w + x0
				for dx in range(8):
					var gi := row_off + dx
					if town_mask[gi] == 0:
						all_town = false
						break
					var c_here := int(rend_cls[gi])
					var m_here := int(rend_mask[gi])
					var st_here := int(tile_stamp[gi])
					var fx_here := int(tile_fix[gi])
					if c_here != first_cls or st_here != 0 or fx_here != 0:
						uniform = false
					parts[p_i] = "%d:%d:%d:%d" % [c_here, m_here, st_here, fx_here]
					p_i += 1
				if not all_town:
					break
			if not all_town or uniform:
				continue
			var key := ",".join(parts)
			var coords: Array = patch_seen.get(key, [])
			var found_far := false
			for prior_v in coords:
				var prior: Vector2i = prior_v
				if absi(x0 - prior.x) >= 8 or absi(y0 - prior.y) >= 8:
					found_far = true
					break
			if found_far:
				repeat_8x8 += 1
			coords.append(Vector2i(x0, y0))
			patch_seen[key] = coords

	# T6: Sizes & entity counts (generalized by area kind & area's own zone pools)
	var oversized_town_buildings := 0
	for pv in (compiled.get("placed_objects", []) as Array):
		var po: Dictionary = pv
		var ow: int = int(po.get("w", 0))
		var oh: int = int(po.get("h", 0))
		if ow <= 11 and oh <= 13:
			continue
		var sid := int(po.get("stamp_id", 0))
		var s_def: Dictionary = TileSynth2.STAMP_TABLE.get(sid, {})
		var s_kind := str(s_def.get("kind", ""))
		if s_kind == "landmark" or s_kind == "prop" or s_kind == "decal" or s_kind == "field_obj":
			continue
		var bx0: int = int(po.get("x", 0))
		var by0: int = int(po.get("y", 0))
		var touches_town := false
		for by in range(by0, mini(h, by0 + oh)):
			for bx in range(bx0, mini(w, bx0 + ow)):
				if town_mask[by * w + bx] == 1:
					touches_town = true
					break
			if touches_town:
				break
		if touches_town:
			oversized_town_buildings += 1

	var pool_info := _allowed_dex_pools_for_area(area, rend_cls)
	var allowed_zones: Dictionary = pool_info["zones"]
	var by_zone: Dictionary = pool_info["by_zone"]
	var allowed_dex: Dictionary = pool_info["all_dex"]
	var invalid_pokemon := 0
	for kv in street_pkm:
		var k: Dictionary = kv
		var dex := int(k.get("dex", 0))
		var kz := str(k.get("zone", "")).strip_edges().to_lower()
		var bad_p := (dex < 1 or dex > 649)
		if not bad_p and is_hood and not allowed_dex.is_empty():
			if not allowed_dex.has(dex):
				bad_p = true
			elif not kz.is_empty():
				if not allowed_zones.has(kz) or not (by_zone.get(kz, {}) as Dictionary).has(dex):
					bad_p = true
		if bad_p:
			invalid_pokemon += 1

	var total_survivors: int = people_arr.size() + door_interior_survivors
	var route_screens: float = float(route_tiles) / 150.0
	var route_items_per_5_screens: float = 0.0 if route_screens <= 0.0 else (float(items_in_route + hidden_in_route) / (route_screens / 5.0))

	var failed_rules: Array[String] = []
	if total_windows == 0 or empty_share > 0.10 or things_per_150 < MIN_THINGS_PER_150_TOWN:
		failed_rules.append("T1")
	if town_tall_grass > 0:
		failed_rules.append("T2")
	if town_wear_pct > 0.05 or route_wear_pct > 0.05 or wear_pct > 0.05 or wear_touch > 0:
		failed_rules.append("T3")
	if repeat_8x8 > 0:
		failed_rules.append("T4")
	var t5_ok := (bad_doors == 0)
	if is_camp and (open_house_doors < 4 or open_house_doors > 6 or total_doorways > 8):
		t5_ok = false
	elif is_hood and (open_house_doors < 8 or open_house_doors > 12):
		t5_ok = false
	if not t5_ok:
		failed_rules.append("T5")

	var t6_ok := (oversized_town_buildings == 0 and invalid_pokemon == 0)
	if is_camp:
		if people_arr.size() < 10 or people_arr.size() > 16:
			t6_ok = false
		if town_signs > MAX_TOWN_SIGNS_CAMP or items_in_town > MAX_TOWN_ITEMS_CAMP:
			t6_ok = false
	elif is_hood:
		if town_land_tiles < MIN_TOWN_LAND_HOOD or town_land_tiles > MAX_TOWN_LAND_HOOD:
			t6_ok = false
		if total_survivors < 3 or total_survivors > 6:
			t6_ok = false
		if street_pkm.size() < 6 or street_pkm.size() > 12:
			t6_ok = false
		if route_items_per_5_screens < 1.0:
			t6_ok = false
		if town_signs > MAX_TOWN_SIGNS_HOOD or items_in_town > MAX_TOWN_ITEMS_HOOD:
			t6_ok = false
	if not t6_ok:
		failed_rules.append("T6")
	if open_ground_pct > MAX_OPEN_GROUND_TOWN:
		failed_rules.append("T7")
	if is_hood and things_per_150_land < MIN_THINGS_PER_150_LAND_HOOD:
		failed_rules.append("T8")
	if is_hood and walk_land_pct < MIN_WALK_LAND_PCT_HOOD:
		failed_rules.append("T9")
	if is_hood and tree_land_pct > MAX_TREE_LAND_PCT_HOOD:
		failed_rules.append("TREES")

	var town_sign_share: float = 0.0 if things_in_town == 0 else (float(town_signs) / float(things_in_town))
	var town_item_share: float = 0.0 if things_in_town == 0 else (float(items_in_town) / float(things_in_town))

	return {
		"ok": failed_rules.is_empty(),
		"failed_rules": failed_rules,
		"town_tiles": town_tile_count,
		"town_land_tiles": town_land_tiles,
		"walk_in_town": walk_in_town,
		"walk_land_pct": walk_land_pct,
		"town_trees": town_trees,
		"tree_land_pct": tree_land_pct,
		"open_ground_tiles": open_ground_tiles,
		"open_ground_pct": open_ground_pct,
		"windows": total_windows,
		"empty_windows": empty_windows,
		"empty_screens": empty_share,
		"things_in_town": things_in_town,
		"things_per_150": things_per_150,
		"things_per_150_land": things_per_150_land,
		"sign_share": town_sign_share,
		"item_share": town_item_share,
		"town_tall_grass": town_tall_grass,
		"town_wear_pct": town_wear_pct,
		"route_wear_pct": route_wear_pct,
		"wear_pct": wear_pct,
		"wear_touch": wear_touch,
		"repeat_8x8": repeat_8x8,
		"open_doors": open_doors_in_town,
		"open_house_doors": open_house_doors,
		"bad_doors": bad_doors,
		"oversized_buildings": oversized_town_buildings,
		"people": people_arr.size(),
		"survivors": total_survivors,
		"street_pokemon": street_pkm.size(),
		"invalid_pokemon": invalid_pokemon,
		"town_signs": town_signs,
		"town_items": items_in_town,
		"route_items": items_in_route + hidden_in_route,
		"route_items_per_5_screens": route_items_per_5_screens,
	}


static func check_route_ground(compiled: Dictionary, area: Dictionary, town_rect_override: Array = []) -> Dictionary:
	var w: int = int(compiled.get("w", 0))
	var h: int = int(compiled.get("h", 0))
	var origin: Vector2i = compiled.get("origin", Vector2i.ZERO)
	var cols: int = int(compiled.get("cols", 1))
	var rows: int = int(compiled.get("rows", 1))
	var total: int = w * h
	var aid := str(area.get("id", ""))
	var akind := str(area.get("kind", str(compiled.get("kind", ""))))
	var is_camp := (akind == "camp" or aid.begins_with("camp:"))
	if is_camp:
		return {"ok": true, "skipped": true, "failed_rules": []}

	var rects: Array = town_rect_override if not town_rect_override.is_empty() else (compiled.get("town", []) as Array)
	var town_mask := PackedByteArray()
	town_mask.resize(total)
	town_mask.fill(0)
	for rv in rects:
		if rv is Array and (rv as Array).size() == 4:
			var r: Array = rv
			var rx0 := clampi(int(r[0]), 0, w)
			var ry0 := clampi(int(r[1]), 0, h)
			var rx1 := clampi(rx0 + int(r[2]), 0, w)
			var ry1 := clampi(ry0 + int(r[3]), 0, h)
			for yy in range(ry0, ry1):
				for xx in range(rx0, rx1):
					town_mask[yy * w + xx] = 1

	var region := PackedByteArray()
	region.resize(total)
	region.fill(0)
	var b := CaricatureMap.BORDER
	for y in range(b, h - b):
		for x in range(b, w - b):
			if town_mask[y * w + x] == 0:
				region[y * w + x] = 1

	var rend_cls := PackedByteArray()
	var rend_var := PackedByteArray()
	var rend_mask := PackedByteArray()
	rend_cls.resize(total)
	rend_var.resize(total)
	rend_mask.resize(total)
	for r_cell in range(rows):
		var cy: int = origin.y + rows - 1 - r_cell
		for c_cell in range(cols):
			var cx: int = origin.x + c_cell
			var cres := CaricatureMap.cell_result(compiled, Vector2i(cx, cy), area)
			var buf: PackedByteArray = cres.get("tiles", PackedByteArray())
			for ty in range(32):
				var gy := r_cell * 32 + ty
				var row_off := gy * w + c_cell * 32
				for tx in range(32):
					var ci := (ty * 32 + tx) * 3
					rend_cls[row_off + tx] = buf[ci]
					rend_var[row_off + tx] = buf[ci + 1]
					rend_mask[row_off + tx] = buf[ci + 2]

	var solid_mask: PackedByteArray = compiled.get("solid_mask", PackedByteArray())
	var walk_flags := PackedByteArray()
	walk_flags.resize(total)
	walk_flags.fill(0)
	for i in range(total):
		var blocked := (solid_mask.size() == total and solid_mask[i] == 1)
		if not blocked and TileSynth2.is_walkable(rend_cls[i], rend_var[i], rend_mask[i]):
			walk_flags[i] = 1

	var tile_stamp := PackedInt32Array()
	tile_stamp.resize(total)
	tile_stamp.fill(0)
	for pv in (compiled.get("placed_objects", []) as Array):
		var po: Dictionary = pv
		var sid := int(po.get("stamp_id", 0))
		if sid <= 0:
			continue
		var ox := int(po.get("x", 0))
		var oy := int(po.get("y", 0))
		var ow := int(po.get("w", 0))
		var oh := int(po.get("h", 0))
		for sy in range(maxi(0, oy), mini(h, oy + oh)):
			for sx in range(maxi(0, ox), mini(w, ox + ow)):
				tile_stamp[sy * w + sx] = sid * 1024 + (sy - oy) * 32 + (sx - ox)

	var tile_fix := PackedInt32Array()
	tile_fix.resize(total)
	tile_fix.fill(0)
	var fix_id_map: Dictionary = {}
	for fv in (compiled.get("fixtures", []) as Array):
		var f: Dictionary = fv
		var fk := str(f.get("kind", ""))
		if not fix_id_map.has(fk):
			fix_id_map[fk] = fix_id_map.size() + 1
		var fid := int(fix_id_map[fk])
		var fx0 := int(f.get("x", 0))
		var fy0 := int(f.get("y", 0))
		var fw := int(f.get("w", 1))
		var fh := int(f.get("h", 1))
		for fy in range(maxi(0, fy0), mini(h, fy0 + fh)):
			for fx in range(maxi(0, fx0), mini(w, fx0 + fw)):
				tile_fix[fy * w + fx] = fid * 1024 + (fy - fy0) * 32 + (fx - fx0)

	var walk_in_region := 0
	var open_ground_tiles := 0
	var tall_grass_tiles := 0
	var item_balls := 0
	var paving_total := 0
	var paving_worn := 0
	var worn_mask := PackedByteArray()
	worn_mask.resize(total)
	worn_mask.fill(0)

	for y in range(h):
		for x in range(w):
			var gi := y * w + x
			if region[gi] == 0:
				continue
			var cls: int = rend_cls[gi]
			var rv: int = rend_var[gi]
			if cls == TileSynth2.TILE_ITEM_BALL:
				item_balls += 1
			if cls == TileSynth2.TILE_PATH or cls == TileSynth2.TILE_PLAZA or cls == TileSynth2.TILE_ROAD:
				paving_total += 1
				if rv == 1:
					paving_worn += 1
					worn_mask[gi] = 1
			if walk_flags[gi] == 0:
				continue
			walk_in_region += 1
			if cls == TileSynth2.TILE_TALL_GRASS:
				tall_grass_tiles += 1
			var all_49 := true
			for dy in range(-3, 4):
				var ny := y + dy
				if ny < 0 or ny >= h:
					all_49 = false
					break
				for dx in range(-3, 4):
					var nx := x + dx
					if nx < 0 or nx >= w or walk_flags[ny * w + nx] == 0:
						all_49 = false
						break
				if not all_49:
					break
			if all_49:
				open_ground_tiles += 1

	var people_cnt := 0
	for pv in (compiled.get("people", []) as Array):
		var p: Dictionary = pv
		var px := int(p["x"])
		var py := int(p["y"])
		if px >= 0 and px < w and py >= 0 and py < h and region[py * w + px] == 1:
			people_cnt += 1

	var pkm_cnt := 0
	for kv in (compiled.get("street_pokemon", []) as Array):
		var k: Dictionary = kv
		var kx := int(k["x"])
		var ky := int(k["y"])
		if kx >= 0 and kx < w and ky >= 0 and ky < h and region[ky * w + kx] == 1:
			pkm_cnt += 1

	var signs_cnt := 0
	for sv in (compiled.get("signs", []) as Array):
		var s: Dictionary = sv
		var sx := int(s["x"])
		var sy := int(s["y"])
		if sx >= 0 and sx < w and sy >= 0 and sy < h and region[sy * w + sx] == 1:
			signs_cnt += 1

	var hidden_cnt := 0
	for hv in (compiled.get("hidden_items", []) as Array):
		var hd: Dictionary = hv
		var hx := int(hd["x"])
		var hy := int(hd["y"])
		if hx >= 0 and hx < w and hy >= 0 and hy < h and region[hy * w + hx] == 1:
			hidden_cnt += 1

	var open_doors_cnt := 0
	var search_doors_cnt := 0
	var open_door_seen: Dictionary = {}
	for dv in (compiled.get("doors", []) as Array):
		var dd: Dictionary = dv
		var dx := int(dd["x"])
		var dy := int(dd["y"])
		var iid := str(dd.get("interior", ""))
		if not iid.is_empty():
			var dpos := Vector2i(dx, dy)
			var is_second := open_door_seen.has(Vector2i(dx - 1, dy)) and str(open_door_seen[Vector2i(dx - 1, dy)]) == iid
			open_door_seen[dpos] = iid
			if not is_second and dx >= 0 and dx < w and dy >= 0 and dy < h and region[dy * w + dx] == 1:
				open_doors_cnt += 1
		elif bool(dd.get("is_ordinary", false)):
			var sy := dy + 1
			if dx >= 0 and dx < w and sy >= 0 and sy < h and region[sy * w + dx] == 1 and walk_flags[sy * w + dx] == 1:
				search_doors_cnt += 1

	var items_cnt: int = item_balls + hidden_cnt
	var things: int = people_cnt + pkm_cnt + signs_cnt + items_cnt + open_doors_cnt + search_doors_cnt
	var things_per_150: float = 0.0 if walk_in_region == 0 else (float(things) / (float(walk_in_region) / 150.0))
	var sign_share: float = 0.0 if things == 0 else (float(signs_cnt) / float(things))
	var item_share: float = 0.0 if things == 0 else (float(items_cnt) / float(things))
	var door_share: float = 0.0 if things == 0 else (float(open_doors_cnt + search_doors_cnt) / float(things))
	var open_ground_pct: float = 0.0 if walk_in_region == 0 else (float(open_ground_tiles) / float(walk_in_region))
	var tall_grass_share: float = 0.0 if walk_in_region == 0 else (float(tall_grass_tiles) / float(walk_in_region))
	var wear_pct: float = 0.0 if paving_total == 0 else (float(paving_worn) / float(paving_total))

	var wear_touch := 0
	for y in range(h):
		for x in range(w):
			var gi := y * w + x
			if worn_mask[gi] == 0:
				continue
			for nd in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var nx: int = x + nd.x
				var ny: int = y + nd.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and worn_mask[ny * w + nx] == 1:
					wear_touch += 1

	var patch_seen: Dictionary = {}
	var repeat_8x8 := 0
	for y0 in range(0, maxi(0, h - 7)):
		for x0 in range(0, maxi(0, w - 7)):
			var all_reg := true
			var first_cls := int(rend_cls[y0 * w + x0])
			var uniform := true
			var parts := PackedStringArray()
			parts.resize(64)
			var p_i := 0
			for dy in range(8):
				var row_off := (y0 + dy) * w + x0
				for dx in range(8):
					var gi := row_off + dx
					if region[gi] == 0:
						all_reg = false
						break
					var c_here := int(rend_cls[gi])
					var m_here := int(rend_mask[gi])
					var st_here := int(tile_stamp[gi])
					var fx_here := int(tile_fix[gi])
					if c_here != first_cls or st_here != 0 or fx_here != 0:
						uniform = false
					parts[p_i] = "%d:%d:%d:%d" % [c_here, m_here, st_here, fx_here]
					p_i += 1
				if not all_reg:
					break
			if not all_reg or uniform:
				continue
			var key := ",".join(parts)
			var coords: Array = patch_seen.get(key, [])
			var found_far := false
			for prior_v in coords:
				var prior: Vector2i = prior_v
				if absi(x0 - prior.x) >= 8 or absi(y0 - prior.y) >= 8:
					found_far = true
					break
			if found_far:
				repeat_8x8 += 1
			coords.append(Vector2i(x0, y0))
			patch_seen[key] = coords

	var failed_rules: Array[String] = []
	if walk_in_region > 0:
		if things == 0 or things_per_150 < MIN_THINGS_PER_150_ROUTE or sign_share > (MAX_SIGN_SHARE_ROUTE + 0.000001) or item_share > (MAX_ITEM_SHARE_ROUTE + 0.000001) or door_share > (MAX_DOOR_SHARE_ROUTE + 0.000001):
			failed_rules.append("R1")
		if open_ground_pct > MAX_OPEN_GROUND_ROUTE:
			failed_rules.append("R2")
		if repeat_8x8 > MAX_REPEAT_8X8_ROUTE:
			failed_rules.append("R3")
		if wear_pct > 0.05 or wear_touch > 0:
			failed_rules.append("T3")

	return {
		"ok": failed_rules.is_empty(),
		"skipped": false,
		"failed_rules": failed_rules,
		"walk": walk_in_region,
		"open_ground_tiles": open_ground_tiles,
		"open_ground_pct": open_ground_pct,
		"things": things,
		"things_per_150": things_per_150,
		"sign_share": sign_share,
		"item_share": item_share,
		"door_share": door_share,
		"wear_pct": wear_pct,
		"wear_touch": wear_touch,
		"repeat_8x8": repeat_8x8,
		"open_doors": open_doors_cnt,
		"search_doors": search_doors_cnt,
		"people": people_cnt,
		"street_pokemon": pkm_cnt,
		"items": items_cnt,
		"item_balls": item_balls,
		"hidden_items": hidden_cnt,
		"signs": signs_cnt,
		"tall_grass_share": tall_grass_share,
	}
