extends Node

## game/tests/walkability_parity_test.gd — Item 69 Exact Walkability Parity Across All 21 DC Maps
## Contract: docs/implementation_plan_travel_and_time.md §(d)

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const CaricatureWalkerGrid := preload("res://world/caricature/caricature_walker_grid.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

func run_test() -> bool:
	var areas: Array = Neighbourhoods.areas_of("city:washington-dc")
	if areas.size() != 21:
		push_error("FAIL: Expected 21 DC areas, got %d" % areas.size())
		return false

	var compiled_by_area: Dictionary = {}
	var cells_map: Dictionary = {}
	for a_var in areas:
		var a: Dictionary = a_var
		var aid := str(a.get("id", ""))
		var map_path := CaricatureMap.resolve_map_path(str(a.get("map", "")))
		var raw := CaricatureMap.load_map(map_path)
		var comp := CaricatureMap.compile(a, raw)
		if not bool(comp.get("ok", false)):
			push_error("FAIL: Failed to compile DC area %s" % aid)
			return false
		compiled_by_area[aid] = comp
		var orig: Vector2i = comp["origin"]
		var cols: int = int(comp["cols"])
		var rows: int = int(comp["rows"])
		for dy in range(rows):
			for dx in range(cols):
				cells_map[Vector2i(orig.x + dx, orig.y + dy)] = {"compiled": comp, "area": a}

	var grid := CaricatureWalkerGrid.new()
	grid.setup(compiled_by_area, cells_map)

	var total_openings_checked := 0
	var unique_interiors_checked: Dictionary = {}
	var total_door_tiles_checked := 0
	var total_lamps_checked := 0

	var tested_water := false
	var tested_cliff := false
	var tested_cut := false
	var tested_smash := false
	var tested_boulder := false
	var tested_ledge_s := false
	var tested_ledge_w := false

	const DIRS: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
	]

	for a_var in areas:
		var a: Dictionary = a_var
		var aid := str(a.get("id", ""))
		var comp: Dictionary = compiled_by_area[aid]
		var w: int = int(comp["w"])
		var h: int = int(comp["h"])
		var total: int = w * h
		var cls_buf: PackedByteArray = comp["class"]
		var var_buf: PackedByteArray = comp["variant"]
		var arrival: Vector2i = comp["arrival"]

		# 1. Live BFS using CaricatureWalkerGrid.evaluate_step (same-area edges, street_pokemon + '!' solid, k/r/o blocked)
		var fwd: Dictionary = {}
		var rev: Dictionary = {}
		var arr_idx := arrival.y * w + arrival.x
		var visited := PackedByteArray()
		visited.resize(total)
		visited.fill(0)
		if not grid.is_local_tile_walkable(aid, arrival.x, arrival.y):
			push_error("FAIL: Arrival tile %s in %s is not walkable!" % [str(arrival), aid])
			return false
		visited[arr_idx] = 1
		var q: Array[int] = [arr_idx]
		var qh := 0
		while qh < q.size():
			var u := q[qh]
			qh += 1
			var ux := u % w
			var uy := int(u / w)
			var ug := CaricatureWalkerGrid.local_to_global(comp, ux, uy)
			var outs := PackedInt32Array()
			for d in DIRS:
				var res := grid.evaluate_step(ug.x, ug.y, d)
				var act := str(res.get("action", ""))
				if act == "step" or act == "ledge":
					if str(res.get("to_area", "")) == aid:
						var dest_g: Vector2i = res["to"]
						var dest_l := CaricatureWalkerGrid.global_to_local(comp, dest_g.x, dest_g.y)
						var v := dest_l.y * w + dest_l.x
						outs.append(v)
						if not rev.has(v):
							rev[v] = PackedInt32Array()
						var ra: PackedInt32Array = rev[v]
						ra.append(u)
						rev[v] = ra
						if visited[v] == 0:
							visited[v] = 1
							q.append(v)
						# Verify ledge falsifiers on real DC ledges
						if act == "ledge":
							var over_g: Vector2i = res["over"]
							var over_l := CaricatureWalkerGrid.global_to_local(comp, over_g.x, over_g.y)
							var lv: int = var_buf[over_l.y * w + over_l.x]
							if lv == 0 and d == Vector2i(0, 1) and not tested_ledge_s:
								# Walking N from landing tile into 'v' ledge must be refused!
								var wrong := grid.evaluate_step(dest_g.x, dest_g.y, Vector2i(0, -1))
								if str(wrong.get("action", "")) != "blocked" or str(wrong.get("reason", "")) != "ledge_wrong_dir":
									push_error("FAIL: Walking N into 'v' ledge was not refused: %s" % str(wrong))
									return false
								tested_ledge_s = true
							elif lv == 2 and d == Vector2i(-1, 0) and not tested_ledge_w:
								# Walking E from landing tile into '<' ledge (Woodley Park) must be refused!
								var wrong_w := grid.evaluate_step(dest_g.x, dest_g.y, Vector2i(1, 0))
								if str(wrong_w.get("action", "")) != "blocked" or str(wrong_w.get("reason", "")) != "ledge_wrong_dir":
									push_error("FAIL: Walking E into '<' ledge was not refused: %s" % str(wrong_w))
									return false
								tested_ledge_w = true
				elif act == "blocked":
					var rsn := str(res.get("reason", ""))
					if rsn == "water":
						tested_water = true
					elif rsn == "cliff":
						tested_cliff = true
					elif rsn == "cut":
						tested_cut = true
					elif rsn == "rock_smash":
						tested_smash = true
					elif rsn == "boulder":
						tested_boulder = true
			fwd[u] = outs

		# Reverse BFS to arrival: verify 0 trapped tiles!
		var can_ret := PackedByteArray()
		can_ret.resize(total)
		can_ret.fill(0)
		can_ret[arr_idx] = 1
		var rq: Array[int] = [arr_idx]
		var rqh := 0
		while rqh < rq.size():
			var u := rq[rqh]
			rqh += 1
			for p_idx in (rev.get(u, PackedInt32Array()) as PackedInt32Array):
				if can_ret[p_idx] == 0:
					can_ret[p_idx] = 1
					rq.append(p_idx)
		var trapped := 0
		for i in range(total):
			if visited[i] == 1 and can_ret[i] == 0:
				trapped += 1
		if trapped != 0:
			push_error("FAIL: %s has %d trapped tiles under CaricatureWalkerGrid!" % [aid, trapped])
			return false

		# Compare against non-HM base reachability with all '!' balls collected (Decision 80 F84):
		# Verify 0 non-HM walkable tiles are cut off once balls are collected, while all doors/openings/lamps
		# above were verified reachable BEFORE collecting any ball!
		var all_balls_collected: Dictionary = {}
		for y_b in range(h):
			for x_b in range(w):
				if cls_buf[y_b * w + x_b] == TileSynth2.TILE_ITEM_BALL:
					all_balls_collected[CaricatureWalkerGrid.ball_item_key(aid, x_b, y_b)] = true
		var grid_post_balls := CaricatureWalkerGrid.new()
		grid_post_balls.setup(compiled_by_area, cells_map, Callable(), all_balls_collected)
		var visited_post := PackedByteArray()
		visited_post.resize(total)
		visited_post.fill(0)
		visited_post[arr_idx] = 1
		var qp: Array[int] = [arr_idx]
		var qph := 0
		while qph < qp.size():
			var up := qp[qph]
			qph += 1
			var upg := CaricatureWalkerGrid.local_to_global(comp, up % w, int(up / w))
			for dp in DIRS:
				var rp := grid_post_balls.evaluate_step(upg.x, upg.y, dp)
				var ap := str(rp.get("action", ""))
				if (ap == "step" or ap == "ledge") and str(rp.get("to_area", "")) == aid:
					var dg: Vector2i = rp["to"]
					var dl := CaricatureWalkerGrid.global_to_local(comp, dg.x, dg.y)
					var vp := dl.y * w + dl.x
					if visited_post[vp] == 0:
						visited_post[vp] = 1
						qp.append(vp)

		var opening_mask := CaricatureCheck._build_opening_mask(w, h, comp.get("openings", []))
		var base_flags := PackedByteArray()
		base_flags.resize(total)
		base_flags.fill(0)
		var solid_mask: PackedByteArray = comp.get("solid_mask", PackedByteArray())
		for y in range(h):
			for x in range(w):
				if not CaricatureCheck._in_play_bounds(x, y, w, h, opening_mask):
					continue
				var idx := y * w + x
				if (solid_mask.size() == total and solid_mask[idx] == 1):
					continue
				if TileSynth2.is_walkable(cls_buf[idx], comp["variant"][idx], comp["mask"][idx]):
					base_flags[idx] = 1
		var base_graph := CaricatureCheck._build_directed_graph(w, h, cls_buf, comp["variant"], comp["mask"], opening_mask, base_flags)
		var base_dist := CaricatureCheck._bfs_from_sources([arrival], w, h, base_flags, base_graph["fwd"])
		var sp_set := {}
		for sp in comp.get("street_pokemon", []):
			sp_set[Vector2i(int(sp["x"]), int(sp["y"]))] = true
		var cut_off_pts: Array[Vector2i] = []
		for y in range(h):
			for x in range(w):
				var idx := y * w + x
				var tcls: int = cls_buf[idx]
				if tcls == TileSynth2.TILE_DOOR:
					continue
				if base_dist[idx] >= 0 and not sp_set.has(Vector2i(x, y)) and visited_post[idx] == 0:
					cut_off_pts.append(Vector2i(x, y))
		if not cut_off_pts.is_empty():
			push_error("FAIL: %s has %d non-HM walkable tiles cut off (sample=%s)" % [aid, cut_off_pts.size(), str(cut_off_pts.slice(0, 15))])
			return false

		# Check all openings reachable
		for op in comp.get("openings", []):
			var out_pts := CaricatureCheck._local_outer_of_opening(op, w, h)
			for pt in out_pts:
				if visited[pt.y * w + pt.x] == 0:
					push_error("FAIL: Opening tile %s in %s not reachable!" % [str(pt), aid])
					return false
			total_openings_checked += 1

		# Check all enterable interior doorsteps reachable AND stepping N triggers action="door"
		for d_entry in comp.get("doors", []):
			var iid := str(d_entry.get("interior", ""))
			if iid.is_empty():
				continue
			var dx := int(d_entry["x"])
			var dy := int(d_entry["y"])
			var step_y := dy + 1
			if visited[step_y * w + dx] == 0:
				push_error("FAIL: Interior doorstep (%d,%d) for %s in %s not reachable!" % [dx, step_y, iid, aid])
				return false
			var step_g := CaricatureWalkerGrid.local_to_global(comp, dx, step_y)
			var door_res := grid.evaluate_step(step_g.x, step_g.y, Vector2i(0, -1))
			if str(door_res.get("action", "")) != "door" or str((door_res.get("door", {}) as Dictionary).get("interior", "")) != iid:
				push_error("FAIL: Stepping N into %s door did not trigger door action: %s" % [iid, str(door_res)])
				return false
			unique_interiors_checked[iid] = true
			total_door_tiles_checked += 1

		# Check lamp arrival (camp + 8 neighbourhoods)
		var akind := str(a.get("kind", ""))
		if akind == "camp" or akind == "hood":
			if visited[arr_idx] == 0:
				push_error("FAIL: Lamp arrival not reachable in %s" % aid)
				return false
			total_lamps_checked += 1

	# Verify expected DC counts and all blocker falsifiers fired
	if total_openings_checked != 44: # 22 aligned links * 2 ends = 44 map openings
		push_error("FAIL: Expected 44 map openings across DC, checked %d" % total_openings_checked)
		return false
	if unique_interiors_checked.size() != 94 or total_door_tiles_checked != 119:
		push_error("FAIL: Expected 94 unique DC interiors (119 door tiles), checked %d interiors (%d door tiles)" % [unique_interiors_checked.size(), total_door_tiles_checked])
		return false
	if total_lamps_checked != 9:
		push_error("FAIL: Expected 9 lamp arrivals across DC, checked %d" % total_lamps_checked)
		return false
	if not (tested_water and tested_cliff and tested_cut and tested_smash and tested_boulder and tested_ledge_s and tested_ledge_w):
		push_error("FAIL: Missing blocker/ledge test coverage: water=%s cliff=%s cut=%s smash=%s boulder=%s ledgeS=%s ledgeW=%s" % [
			str(tested_water), str(tested_cliff), str(tested_cut), str(tested_smash), str(tested_boulder), str(tested_ledge_s), str(tested_ledge_w)
		])
		return false

	# Locked-route fog falsifier: stepping from Dupont Circle west opening into a fogged (reveal=0) q-street#1 cell is refused!
	var fog_grid := CaricatureWalkerGrid.new()
	fog_grid.setup(compiled_by_area, cells_map, func(cell: Vector2i) -> int:
		var entry: Dictionary = cells_map.get(cell, {})
		if entry.is_empty():
			return 0
		var ea: Dictionary = entry.get("area", {})
		return 2 if str(ea.get("id", "")) == "hood:washington-dc:dupont-circle" else 0
	)
	var dup_comp: Dictionary = compiled_by_area["hood:washington-dc:dupont-circle"]
	var dup_w_op: Dictionary = {}
	for op in dup_comp.get("openings", []):
		if str(op.get("side", "")) == "W":
			dup_w_op = op
			break
	var w_pts := CaricatureCheck._local_outer_of_opening(dup_w_op, int(dup_comp["w"]), int(dup_comp["h"]))
	var dup_edge_g := CaricatureWalkerGrid.local_to_global(dup_comp, w_pts[0].x, w_pts[0].y)
	var fog_res := fog_grid.evaluate_step(dup_edge_g.x, dup_edge_g.y, Vector2i(-1, 0))
	if str(fog_res.get("action", "")) != "blocked" or str(fog_res.get("reason", "")) != "fog":
		push_error("FAIL: Stepping into locked-route fog expected blocked/fog, got %s" % str(fog_res))
		return false

	return true
