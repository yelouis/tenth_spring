class_name InteriorCheck
extends RefCounted

## game/world/interior/interior_check.gd — Interior Measurement & Playable Rules I1..I6 (Item 57)
## Contract: docs/implementation_plan_dc_trial.md §11.3 C & docs/agent_execution_guide.md §5

const InteriorTiles := preload("res://world/interior/interior_tiles.gd")
const InteriorMap := preload("res://world/interior/interior_map.gd")

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(-1, 0),
]

static func compile_and_check(doc: Dictionary) -> Dictionary:
	var compiled := InteriorMap.compile(doc)
	return check(compiled)

static func _in_bounds(x: int, y: int, w: int, h: int) -> bool:
	return x >= 0 and x < w and y >= 0 and y < h

static func _mark_solid_footprint(mask: PackedByteArray, w: int, h: int, at: Vector2i, sw: int, sh: int, base_rows: int) -> void:
	for ty in range(sh - base_rows, sh):
		for tx in range(sw):
			var gx := at.x + tx
			var gy := at.y + ty
			if _in_bounds(gx, gy, w, h):
				mask[gy * w + gx] = 1

static func _build_block_mask(floor_dict: Dictionary, open_gates: Dictionary, allow_clearable: bool, include_non_gating: bool) -> PackedByteArray:
	var w: int = int(floor_dict["w"])
	var h: int = int(floor_dict["h"])
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	for st_v in (floor_dict["stamps"] as Array):
		var st: Dictionary = st_v
		var base_rows := int(st.get("base_rows", 0))
		if base_rows <= 0:
			continue
		var gate_id := str(st.get("gate_id", ""))
		var clearable := bool(st.get("clearable", false))
		var is_gating := (not gate_id.is_empty()) or clearable
		if is_gating:
			if not gate_id.is_empty() and open_gates.has(gate_id):
				continue
			if clearable and allow_clearable:
				continue
		else:
			if not include_non_gating:
				continue
		_mark_solid_footprint(mask, w, h, st["at"] as Vector2i, int(st["w"]), int(st["h"]), base_rows)
	if include_non_gating:
		for fx_v in (floor_dict.get("fixtures", []) as Array):
			var fx: Dictionary = fx_v
			var fbase := int(fx.get("base_rows", 0))
			if fbase <= 0:
				continue
			_mark_solid_footprint(mask, w, h, fx["at"] as Vector2i, int(fx["w"]), int(fx["h"]), fbase)
	return mask

static func _is_tile_passable(floor_dict: Dictionary, block_mask: PackedByteArray, x: int, y: int) -> bool:
	var w: int = int(floor_dict["w"])
	var h: int = int(floor_dict["h"])
	if not _in_bounds(x, y, w, h):
		return false
	var idx := y * w + x
	if block_mask[idx] != 0:
		return false
	var tiles: PackedByteArray = floor_dict["tiles"]
	return InteriorTiles.is_walkable(int(tiles[idx]))

static func _slide_destination(floor_dict: Dictionary, block_mask: PackedByteArray, start: Vector2i) -> Vector2i:
	var w: int = int(floor_dict["w"])
	var tiles: PackedByteArray = floor_dict["tiles"]
	var cur := start
	var visited_arrows: Dictionary = {}
	while true:
		var cls := int(tiles[cur.y * w + cur.x])
		if not InteriorTiles.is_gust_arrow(cls):
			return cur
		if visited_arrows.has(cur):
			return cur
		visited_arrows[cur] = true
		var delta := InteriorTiles.gust_delta(cls)
		var nxt := cur + delta
		if not _is_tile_passable(floor_dict, block_mask, nxt.x, nxt.y):
			return cur
		cur = nxt
	return cur

static func _count_walkable_components(floor_dict: Dictionary, block_mask: PackedByteArray) -> int:
	var w: int = int(floor_dict["w"])
	var h: int = int(floor_dict["h"])
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen.fill(0)
	var comps := 0
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if seen[idx] != 0 or not _is_tile_passable(floor_dict, block_mask, x, y):
				continue
			comps += 1
			var q: Array[Vector2i] = [Vector2i(x, y)]
			seen[idx] = 1
			var head := 0
			while head < q.size():
				var p := q[head]
				head += 1
				for d in DIRS:
					var np := p + d
					if _is_tile_passable(floor_dict, block_mask, np.x, np.y):
						var nidx := np.y * w + np.x
						if seen[nidx] == 0:
							seen[nidx] = 1
							q.append(np)
	return comps

static func _run_multifloor_bfs(floors: Array, floor_by_id: Dictionary, open_gates: Dictionary, allow_clearable: bool) -> Dictionary:
	var block_masks: Array[PackedByteArray] = []
	var link_map: Array[Dictionary] = []
	for f_idx in range(floors.size()):
		var fd: Dictionary = floors[f_idx]
		block_masks.append(_build_block_mask(fd, open_gates, allow_clearable, true))
		var ldict: Dictionary = {}
		for tr_list_key in ["stairs", "warps"]:
			for tr_v in (fd[tr_list_key] as Array):
				var tr: Dictionary = tr_v
				var at_v: Variant = InteriorMap._parse_vec2i(tr.get("at", null))
				var to_v: Variant = InteriorMap._parse_vec2i(tr.get("to", null))
				var to_fid := str(tr.get("to_floor", ""))
				if at_v is Vector2i and to_v is Vector2i and floor_by_id.has(to_fid):
					var tf_idx := int(floor_by_id[to_fid])
					if not ldict.has(at_v):
						ldict[at_v] = []
					(ldict[at_v] as Array).append({"floor": tf_idx, "pos": to_v as Vector2i})
		link_map.append(ldict)

	var reached: Dictionary = {}
	var queue: Array[Dictionary] = []
	if not floors.is_empty():
		var f0: Dictionary = floors[0]
		for dm in (f0["door_mats"] as Array):
			var dmp: Vector2i = dm
			if _is_tile_passable(f0, block_masks[0], dmp.x, dmp.y):
				var k0 := "0:%d:%d" % [dmp.x, dmp.y]
				if not reached.has(k0):
					reached[k0] = true
					queue.append({"f": 0, "p": dmp})

	var head := 0
	while head < queue.size():
		var cur: Dictionary = queue[head]
		head += 1
		var fi: int = int(cur["f"])
		var p: Vector2i = cur["p"]
		var fd: Dictionary = floors[fi]
		var bm: PackedByteArray = block_masks[fi]

		# Orthogonal steps (with gust arrow slide)
		for d in DIRS:
			var np := p + d
			if _is_tile_passable(fd, bm, np.x, np.y):
				var landed := _slide_destination(fd, bm, np)
				var kl := "%d:%d:%d" % [fi, landed.x, landed.y]
				if not reached.has(kl):
					reached[kl] = true
					queue.append({"f": fi, "p": landed})

		# Cross-floor transitions (stairs & warps)
		var ldict_f: Dictionary = link_map[fi]
		if ldict_f.has(p):
			for dest_v in (ldict_f[p] as Array):
				var dest: Dictionary = dest_v
				var tfi := int(dest["floor"])
				var tp: Vector2i = dest["pos"]
				if _is_tile_passable(floors[tfi], block_masks[tfi], tp.x, tp.y):
					var tland := _slide_destination(floors[tfi], block_masks[tfi], tp)
					var kt := "%d:%d:%d" % [tfi, tland.x, tland.y]
					if not reached.has(kt):
						reached[kt] = true
						queue.append({"f": tfi, "p": tland})

	return {"reached": reached, "block_masks": block_masks, "link_map": link_map}

static func _can_interact_point(reached: Dictionary, fi: int, pt: Vector2i) -> bool:
	if reached.has("%d:%d:%d" % [fi, pt.x, pt.y]):
		return true
	for d in DIRS:
		var np := pt + d
		if reached.has("%d:%d:%d" % [fi, np.x, np.y]):
			return true
	return false

static func _can_interact_rect(reached: Dictionary, fi: int, at: Vector2i, w: int, h: int) -> bool:
	for ty in range(h):
		for tx in range(w):
			if _can_interact_point(reached, fi, Vector2i(at.x + tx, at.y + ty)):
				return true
	return false

static func _can_return_to_exit(floors: Array, block_masks: Array, link_map: Array, start_fi: int, start_p: Vector2i) -> bool:
	var seen: Dictionary = {}
	var q: Array[Dictionary] = [{"f": start_fi, "p": start_p}]
	seen["%d:%d:%d" % [start_fi, start_p.x, start_p.y]] = true
	var head := 0
	while head < q.size():
		var cur: Dictionary = q[head]
		head += 1
		var fi := int(cur["f"])
		var p: Vector2i = cur["p"]
		var fd: Dictionary = floors[fi]
		if fi == 0:
			var tiles0: PackedByteArray = fd["tiles"]
			if int(tiles0[p.y * int(fd["w"]) + p.x]) == InteriorTiles.TILE_INT_DOOR_MAT:
				return true
		var bm: PackedByteArray = block_masks[fi]
		for d in DIRS:
			var np := p + d
			if _is_tile_passable(fd, bm, np.x, np.y):
				var landed := _slide_destination(fd, bm, np)
				var kl := "%d:%d:%d" % [fi, landed.x, landed.y]
				if not seen.has(kl):
					seen[kl] = true
					q.append({"f": fi, "p": landed})
		var ldict_f: Dictionary = link_map[fi]
		if ldict_f.has(p):
			for dest_v in (ldict_f[p] as Array):
				var dest: Dictionary = dest_v
				var tfi := int(dest["floor"])
				var tp: Vector2i = dest["pos"]
				if _is_tile_passable(floors[tfi], block_masks[tfi], tp.x, tp.y):
					var tland := _slide_destination(floors[tfi], block_masks[tfi], tp)
					var kt := "%d:%d:%d" % [tfi, tland.x, tland.y]
					if not seen.has(kt):
						seen[kt] = true
						q.append({"f": tfi, "p": tland})
	return false

static func check(compiled: Dictionary) -> Dictionary:
	var rule_errors: Dictionary = (compiled.get("rule_errors", {}) as Dictionary).duplicate(true)
	for r_id in ["I1", "I2", "I3", "I4", "I5", "I6"]:
		if not rule_errors.has(r_id):
			rule_errors[r_id] = []

	var floors: Array = compiled.get("floors", [])
	var floor_by_id: Dictionary = compiled.get("floor_by_id", {})
	var has_i1_i2 := not (rule_errors["I1"] as Array).is_empty() or not (rule_errors["I2"] as Array).is_empty()

	# -------------------------------------------------------------
	# I5: Stamp bounds, illegal overlap, & hallway pass lane
	# -------------------------------------------------------------
	if (rule_errors["I1"] as Array).is_empty():
		for f_idx in range(floors.size()):
			var fd: Dictionary = floors[f_idx]
			var fid := str(fd["floor_id"])
			var w := int(fd["w"])
			var h := int(fd["h"])
			var tiles: PackedByteArray = fd["tiles"]
			var solid_occupied := PackedByteArray()
			solid_occupied.resize(w * h)
			solid_occupied.fill(0)

			_validate_placement_list(fd["stamps"] as Array, "stamp", "id", fid, w, h, tiles, solid_occupied, rule_errors)
			_validate_placement_list(fd.get("fixtures", []) as Array, "fixture", "fixture", fid, w, h, tiles, solid_occupied, rule_errors)

			# Hallway pass-lane check: non-gating solid props & fixtures must not increase walkable components
			var empty_gates: Dictionary = {}
			var bm_bare := _build_block_mask(fd, empty_gates, true, false)
			var bm_with_props := _build_block_mask(fd, empty_gates, true, true)
			var comps_bare := _count_walkable_components(fd, bm_bare)
			var comps_props := _count_walkable_components(fd, bm_with_props)
			if comps_props > comps_bare:
				(rule_errors["I5"] as Array).append("floor %s non-gating stamp blocks hallway pass lane (components %d -> %d)" % [fid, comps_bare, comps_props])

			# Also check each non-gating solid prop & fixture has >= 1 walkable pass tile adjacent to its base
			_check_pass_adjacency(fd, fd["stamps"] as Array, "stamp", "id", fid, w, h, bm_with_props, rule_errors)
			_check_pass_adjacency(fd, fd.get("fixtures", []) as Array, "fixture", "fixture", fid, w, h, bm_with_props, rule_errors)

	# -------------------------------------------------------------
	# I3: Valid walkable stair/warp endpoints
	# -------------------------------------------------------------
	if (rule_errors["I1"] as Array).is_empty():
		var open_all_gates: Dictionary = {}
		for fd_g in floors:
			for st_g in ((fd_g as Dictionary)["stamps"] as Array):
				var gid := str((st_g as Dictionary).get("gate_id", ""))
				if not gid.is_empty():
					open_all_gates[gid] = true

		for f_idx in range(floors.size()):
			var fd: Dictionary = floors[f_idx]
			var fid := str(fd["floor_id"])
			var w := int(fd["w"])
			var h := int(fd["h"])
			var tiles: PackedByteArray = fd["tiles"]
			for kind_key in ["stairs", "warps"]:
				for tr_v in (fd[kind_key] as Array):
					var tr: Dictionary = tr_v
					var at_v: Variant = InteriorMap._parse_vec2i(tr.get("at", null))
					var to_v: Variant = InteriorMap._parse_vec2i(tr.get("to", null))
					var to_fid := str(tr.get("to_floor", ""))
					if not (at_v is Vector2i) or not _in_bounds((at_v as Vector2i).x, (at_v as Vector2i).y, w, h):
						(rule_errors["I3"] as Array).append("floor %s %s invalid origin 'at'" % [fid, kind_key])
						continue
					var at_p: Vector2i = at_v
					var src_cls := int(tiles[at_p.y * w + at_p.x])
					if not InteriorTiles.is_walkable(src_cls):
						(rule_errors["I3"] as Array).append("floor %s %s origin %s is non-walkable class %d" % [fid, kind_key, str(at_p), src_cls])
					if not floor_by_id.has(to_fid):
						(rule_errors["I3"] as Array).append("floor %s %s references unknown target floor '%s'" % [fid, kind_key, to_fid])
						continue
					var t_idx := int(floor_by_id[to_fid])
					var t_fd: Dictionary = floors[t_idx]
					var tw := int(t_fd["w"])
					var th := int(t_fd["h"])
					if not (to_v is Vector2i) or not _in_bounds((to_v as Vector2i).x, (to_v as Vector2i).y, tw, th):
						(rule_errors["I3"] as Array).append("floor %s %s target 'to' out of bounds on %s" % [fid, kind_key, to_fid])
						continue
					var to_p: Vector2i = to_v
					var dst_cls := int((t_fd["tiles"] as PackedByteArray)[to_p.y * tw + to_p.x])
					var dst_bm := _build_block_mask(t_fd, open_all_gates, true, true)
					if not InteriorTiles.is_landing_safe(dst_cls) or dst_bm[to_p.y * tw + to_p.x] != 0:
						(rule_errors["I3"] as Array).append("floor %s %s landing %s on %s is blocked or unsafe (class %d)" % [fid, kind_key, str(to_p), to_fid, dst_cls])

	# -------------------------------------------------------------
	# I4: Multi-floor BFS reachability & zero-deadlock check
	# -------------------------------------------------------------
	var trapped_tiles := 0
	if not has_i1_i2 and (rule_errors["I3"] as Array).is_empty():
		# Iterative switch unlock BFS: start with 0 open gates, unlock any switch reachable so far
		var open_gates: Dictionary = {}
		var changed := true
		var bfs_state: Dictionary = {}
		while changed:
			changed = false
			bfs_state = _run_multifloor_bfs(floors, floor_by_id, open_gates, true)
			var rset: Dictionary = bfs_state["reached"]
			for f_idx in range(floors.size()):
				var fd: Dictionary = floors[f_idx]
				for sw_v in (fd["switches"] as Array):
					var sw: Dictionary = sw_v
					var sw_at_v: Variant = InteriorMap._parse_vec2i(sw.get("at", null))
					if sw_at_v is Vector2i and _can_interact_point(rset, f_idx, sw_at_v as Vector2i):
						for gid_v in (sw.get("opens", []) as Array):
							var gid := str(gid_v)
							if not gid.is_empty() and not open_gates.has(gid):
								open_gates[gid] = true
								changed = true

		var reached: Dictionary = bfs_state.get("reached", {})
		var block_masks: Array = bfs_state.get("block_masks", [])
		var link_map: Array = bfs_state.get("link_map", [])

		for f_idx in range(floors.size()):
			var fd: Dictionary = floors[f_idx]
			var fid := str(fd["floor_id"])

			# Every floor must have at least 1 reached tile
			var floor_has_reached := false
			for rk in reached.keys():
				if str(rk).begins_with("%d:" % f_idx):
					floor_has_reached = true
					break
			if not floor_has_reached:
				(rule_errors["I4"] as Array).append("floor %s is unreachable from entrance" % fid)

			# Stairs & warps
			for kind_key in ["stairs", "warps"]:
				for tr_v in (fd[kind_key] as Array):
					var at_v: Variant = InteriorMap._parse_vec2i((tr_v as Dictionary).get("at", null))
					if at_v is Vector2i:
						var p_tr: Vector2i = at_v
						if not reached.has("%d:%d:%d" % [f_idx, p_tr.x, p_tr.y]):
							(rule_errors["I4"] as Array).append("floor %s %s at %s is unreachable" % [fid, kind_key, str(p_tr)])

			# Switches
			for sw_v in (fd["switches"] as Array):
				var sw_at_v: Variant = InteriorMap._parse_vec2i((sw_v as Dictionary).get("at", null))
				if sw_at_v is Vector2i and not _can_interact_point(reached, f_idx, sw_at_v as Vector2i):
					(rule_errors["I4"] as Array).append("floor %s switch '%s' at %s is unreachable" % [fid, str((sw_v as Dictionary).get("id", "")), str(sw_at_v)])

			# NPCs, items, signs
			for list_key in ["npcs", "items", "signs"]:
				for obj_v in (fd[list_key] as Array):
					var obj_at_v: Variant = InteriorMap._parse_vec2i((obj_v as Dictionary).get("at", null))
					if obj_at_v is Vector2i and not _can_interact_point(reached, f_idx, obj_at_v as Vector2i):
						(rule_errors["I4"] as Array).append("floor %s %s at %s is unreachable" % [fid, list_key, str(obj_at_v)])

			# Capstone & item-ball stamps
			for st_v in (fd["stamps"] as Array):
				var st: Dictionary = st_v
				var sid := int(st["stamp_id"])
				if bool(st.get("capstone", false)) or sid == 110:
					if not _can_interact_rect(reached, f_idx, st["at"] as Vector2i, int(st["w"]), int(st["h"])):
						(rule_errors["I4"] as Array).append("floor %s objective stamp %s at %s is unreachable" % [fid, str(st["id"]), str(st["at"])])

		# Deadlock check: every reached tile must be able to return to a ground-floor door_mat
		for rk in reached.keys():
			var parts := str(rk).split(":")
			var rfi := parts[0].to_int()
			var rpx := parts[1].to_int()
			var rpy := parts[2].to_int()
			if not _can_return_to_exit(floors, block_masks, link_map, rfi, Vector2i(rpx, rpy)):
				trapped_tiles += 1
		if trapped_tiles > 0:
			(rule_errors["I4"] as Array).append("%d reachable tile(s) cannot return to entrance door_mat (deadlock)" % trapped_tiles)

	var failed_rules: Array[String] = []
	for r_id in ["I1", "I2", "I3", "I4", "I5", "I6"]:
		if not (rule_errors[r_id] as Array).is_empty():
			failed_rules.append(r_id)

	return {
		"ok": failed_rules.is_empty(),
		"id": str(compiled.get("id", "unknown")),
		"floors": floors.size(),
		"stamps": int(compiled.get("total_stamps", 0)),
		"art_pending": int(compiled.get("art_pending", 0)),
		"trapped": trapped_tiles,
		"failed_rules": failed_rules,
		"rule_errors": rule_errors,
		"compiled": compiled,
	}

static func format_summary(res: Dictionary) -> String:
	var id_str := str(res.get("id", "unknown"))
	var n_floors := int(res.get("floors", 0))
	var n_stamps := int(res.get("stamps", 0))
	var n_pending := int(res.get("art_pending", 0))
	var ok := bool(res.get("ok", false))
	var failed: Array = res.get("failed_rules", [])
	var status := "PASS" if ok else ("FAIL " + ",".join(PackedStringArray(failed)))
	return "INTERIOR %s floors=%d stamps=%d art_pending=%d %s" % [id_str, n_floors, n_stamps, n_pending, status]

static func _validate_placement_list(
	items: Array,
	kind_label: String,
	name_key: String,
	fid: String,
	w: int,
	h: int,
	tiles: PackedByteArray,
	solid_occupied: PackedByteArray,
	rule_errors: Dictionary
) -> void:
	for item_v in items:
		var item: Dictionary = item_v
		var at: Vector2i = item["at"]
		var sw := int(item["w"])
		var sh := int(item["h"])
		var sbase := int(item["base_rows"])
		var sname := str(item.get(name_key, ""))

		if at.x < 0 or at.y < 0 or at.x + sw > w or at.y + sh > h:
			(rule_errors["I5"] as Array).append("floor %s %s %s at %s exceeds %dx%d bounds" % [fid, kind_label, sname, str(at), w, h])
			continue

		for ty in range(sh):
			var is_base := (sbase > 0 and ty >= sh - sbase)
			for tx in range(sw):
				var gx := at.x + tx
				var gy := at.y + ty
				var cls := int(tiles[gy * w + gx])
				if cls == InteriorTiles.TILE_INT_VOID_BLACK or cls == InteriorTiles.TILE_INT_DOOR_MAT:
					(rule_errors["I5"] as Array).append("floor %s %s %s overlaps illegal tile class %d at (%d,%d)" % [fid, kind_label, sname, cls, gx, gy])
				if is_base:
					if not InteriorTiles.is_walkable(cls) or cls == InteriorTiles.TILE_INT_STAIRS_UP or cls == InteriorTiles.TILE_INT_STAIRS_DOWN:
						(rule_errors["I5"] as Array).append("floor %s %s %s solid base overlaps non-floor class %d at (%d,%d)" % [fid, kind_label, sname, cls, gx, gy])
					if solid_occupied[gy * w + gx] != 0:
						(rule_errors["I5"] as Array).append("floor %s %s %s solid base overlaps another solid prop at (%d,%d)" % [fid, kind_label, sname, gx, gy])
					solid_occupied[gy * w + gx] = 1
				elif cls == InteriorTiles.TILE_INT_STAIRS_UP or cls == InteriorTiles.TILE_INT_STAIRS_DOWN:
					(rule_errors["I5"] as Array).append("floor %s %s %s overhang overlaps stair tile %d at (%d,%d)" % [fid, kind_label, sname, cls, gx, gy])

static func _check_pass_adjacency(
	fd: Dictionary,
	items: Array,
	kind_label: String,
	name_key: String,
	fid: String,
	w: int,
	h: int,
	bm_with_props: PackedByteArray,
	rule_errors: Dictionary
) -> void:
	for item_v in items:
		var item: Dictionary = item_v
		var sbase := int(item.get("base_rows", 0))
		if sbase <= 0 or not str(item.get("gate_id", "")).is_empty() or bool(item.get("clearable", false)):
			continue
		var at: Vector2i = item["at"]
		var sw := int(item["w"])
		var sh := int(item["h"])
		if at.x < 0 or at.y < 0 or at.x + sw > w or at.y + sh > h:
			continue
		var adj_walk := 0
		for ty in range(sh - sbase, sh):
			for tx in range(sw):
				for d in DIRS:
					var np := Vector2i(at.x + tx, at.y + ty) + d
					if _is_tile_passable(fd, bm_with_props, np.x, np.y):
						adj_walk += 1
		if adj_walk == 0:
			(rule_errors["I5"] as Array).append("floor %s %s %s leaves 0 walkable pass tiles beside base" % [fid, kind_label, str(item.get(name_key, ""))])
