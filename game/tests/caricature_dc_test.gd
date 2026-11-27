extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3c8869350cc9de22714888ff9c0ed03fdb56bcf5842ec9f1b2935fab5f5ce20a",
	"hood:washington-dc:national-mall": "62b75a38331069034a3d15a4d909c2e8c62abbd19c18a4a1ae9ff76f9dc68c28",
	"hood:washington-dc:tidal-basin": "2a749d96240a7bc8e3554d7922930cba47643894ca97f40a0f9754ca7605b437",
	"hood:washington-dc:dupont-circle": "69100d8f13e126694ab2aa0dee0b1a068301690c40f6977fef8fb93db9c4f74e",
	"hood:washington-dc:capitol-hill": "1c08c409621db10ee17eddba7f7ec369cfc0dccdb32ff63f416bb1512c5907d7",
	"hood:washington-dc:union-station": "e0d995b279e5310da785d1955d10da72b99b9ac8f9fafe2b9c9a8395db5ce0e2",
	"hood:washington-dc:georgetown": "e31d84d67373cb586e54ec7587ff0e7c4c176916646d251fcbc280515091f347",
	"hood:washington-dc:woodley-park": "97e958e0b36d21cf0031c23f8ae3fdfc821feddf65239ed11dee3f2916501800",
	"hood:washington-dc:lincoln-memorial": "96a318bcae9b86f5f1926455847fad75e510fabf281163786e99b74e212749f0",
	"route:washington-dc:monument-grounds#1": "4a9ae765a36a083c6387419b7f7e4f25f3cf6fb555fb98e2ae6c46466bb84a6c",
	"route:washington-dc:pennsylvania-avenue#1": "75b63917fbb5226bbe1a1bcd93c9768a8ab23c155940d333fcddd5de11d137f5",
	"route:washington-dc:constitution-gardens#1": "b78a9d0a0be1b337e5b1399e42600d35d2b56f66085b4e02d23a43d9fe33aa59",
	"route:washington-dc:west-potomac-park#1": "58729ba4c9ccc41df063bf9f9b01208037ee688365dd5461667d02aeb68ca4d5",
	"route:washington-dc:west-potomac-park#2": "55850311a1921509e074efe64dd501c7c5179b8e5c4c189bb8c5c31718278003",
	"route:washington-dc:upper-senate-park#1": "ef61a6347fa782a4cf02d33d2d624ca144e0e36d4182d8d3d0b209bad9ab93a0",
	"route:washington-dc:q-street#1": "6c8d358404e1df45804623b3ded2d5cb3343ea8bc7e08788b0d0d63e1845a576",
	"route:washington-dc:connecticut-avenue#1": "acb154df2e9b3f4cf66f84d1c600fbde9c1d18d86a687847c2247a92cc67ebc3",
	"route:washington-dc:massachusetts-avenue#1": "47597a9b1e8f8b6feb78032d39bbae6e881fdcc31825b9fc08ac20f2d7cdf413",
	"route:washington-dc:rock-creek-trail#1": "7c8f061c836ebc08ed0b43c6f1eceb0b8111dd7cd032c00a64b507c820743dbf",
	"route:washington-dc:rock-creek-trail#2": "596cf421d80e9f483975e846e40b83c5c58ba0505a931532d9283a190f75b0ac",
	"route:washington-dc:potomac-riverfront#1": "e1ae977faba9f7731848c4e4f269ee5d35c72eead6cdba27e8ba024bc30c2e33",
}

func _hash_all_cells(compiled: Dictionary, area: Dictionary, cells: Array[Vector2i]) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for c in cells:
		var cr := CaricatureMap.cell_result(compiled, c, area)
		var t: PackedByteArray = cr["tiles"]
		ctx.update(t)
	return ctx.finish().hex_encode()

func run_test() -> bool:
	Neighbourhoods.set_config_path_for_tests("")
	var areas: Array = Neighbourhoods.areas_of("city:washington-dc")
	if areas.size() != 21:
		push_error("caricature_dc_test: expected 21 blocks for city:washington-dc (camp + 8 neighbourhoods + 12 legs), got %d" % areas.size())
		return false

	var routes: Array = Neighbourhoods.routes_of("city:washington-dc")
	if routes.size() != 10:
		push_error("caricature_dc_test: expected 10 routes for city:washington-dc, got %d" % routes.size())
		return false

	var compiled_by_id: Dictionary = {}
	var measures_by_id: Dictionary = {}
	var all_ok := true
	for a_var in areas:
		var area: Dictionary = a_var
		var area_id := str(area.get("id", ""))
		var map_path := CaricatureMap.resolve_map_path(str(area.get("map", "")))
		if not FileAccess.file_exists(map_path):
			push_error("caricature_dc_test: missing map file for %s at %s" % [area_id, map_path])
			return false

		var map_dict := CaricatureMap.load_map(map_path)
		if map_dict.is_empty():
			push_error("caricature_dc_test: failed to parse map JSON for %s at %s" % [area_id, map_path])
			return false

		var compiled := CaricatureMap.compile(area, map_dict, MapConstants.MAP_SEED)
		if not bool(compiled.get("ok", false)) or not (compiled.get("errors", []) as Array).is_empty():
			push_error("caricature_dc_test: %s compile failed: %s" % [area_id, str(compiled.get("errors", []))])
			return false

		var m := CaricatureCheck.measure(compiled, area)
		if not bool(m.get("ok", false)):
			push_error(
				"caricature_dc_test: %s failed playable-size checks (%s): %s" % [
					area_id,
					str(m.get("failed_rules", [])),
					str(m),
				]
			)
			return false
		if int(m.get("art_pending", 0)) != 0:
			push_error(
				"caricature_dc_test: [falsifier] %s still has art_pending=%d (expected 0 after Item 52)" % [
					area_id,
					int(m.get("art_pending", 0)),
				]
			)
			return false

		compiled_by_id[area_id] = compiled
		measures_by_id[area_id] = m

		var akind := str(area.get("kind", ""))
		var is_camp_a := (akind == "camp" or area_id.begins_with("camp:"))
		var is_route_a := (akind == "route" or area_id.begins_with("route:"))
		if not is_route_a and not bool(compiled.get("has_town_rules", false)):
			push_error("caricature_dc_test: %s is missing town rects" % area_id)
			return false
		if bool(compiled.get("has_town_rules", false)):
			var tc := CaricatureCheck.check_town(compiled, area)
			if not bool(tc.get("ok", false)):
				push_error("caricature_dc_test: %s failed check_town (%s): %s" % [area_id, str(tc.get("failed_rules", [])), str(tc)])
				return false
		if not is_camp_a:
			var rgc := CaricatureCheck.check_route_ground(compiled, area)
			if not bool(rgc.get("ok", false)):
				push_error("caricature_dc_test: %s failed check_route_ground (%s): %s" % [area_id, str(rgc.get("failed_rules", [])), str(rgc)])
				return false

		var cells := Neighbourhoods.block_cells(area)
		var sha1 := _hash_all_cells(compiled, area, cells)
		var compiled2 := CaricatureMap.compile(area, map_dict, MapConstants.MAP_SEED)
		var sha2 := _hash_all_cells(compiled2, area, cells)
		if sha1 != sha2:
			push_error("caricature_dc_test: %s compilation is non-deterministic (%s vs %s)" % [area_id, sha1, sha2])
			return false

		if not PINNED_SHA256.has(area_id):
			push_error("caricature_dc_test: PINNED_SHA256 missing key %s (computed %s)" % [area_id, sha1])
			all_ok = false
			continue

		var expected_sha := str(PINNED_SHA256[area_id])
		if sha1 != expected_sha:
			push_error("caricature_dc_test: %s SHA-256 mismatch: got %s, expected %s" % [area_id, sha1, expected_sha])
			all_ok = false

	for r_var in routes:
		var r_dict: Dictionary = r_var
		var rid := str(r_dict.get("id", ""))
		var rc := CaricatureCheck.check_route(r_dict, compiled_by_id, measures_by_id)
		if not bool(rc.get("ok", false)):
			push_error("caricature_dc_test: route %s failed checks (%s): %s" % [rid, str(rc.get("failed_rules", [])), str(rc)])
			return false

	var cc := CaricatureCheck.check_city("city:washington-dc", compiled_by_id)
	if not bool(cc.get("ok", false)):
		push_error("caricature_dc_test: city:washington-dc failed C0/C1 checks (%s): %s" % [str(cc.get("failed_rules", [])), str(cc)])
		return false
	if int(cc.get("openings_aligned", 0)) != 22 or int(cc.get("openings_total", 0)) != 22 or int(cc.get("connected", 0)) != 8:
		push_error("caricature_dc_test: unexpected city check counts: %s" % str(cc))
		return false

	# Decision 81 (Item 77 / F92): On all 21 DC maps, every 4-connected clump of TILE_TREE tiles
	# has a single kind (no tree tile differs from the tree tile directly above, below, left, or right),
	# and ~30% of clumps are pine/dark (variant == 1). Verify on final synthesized cell buffers!
	var total_tree_clumps := 0
	var pine_tree_clumps := 0
	for a_var in areas:
		var area_t: Dictionary = a_var
		var aid_t := str(area_t.get("id", ""))
		var comp_t: Dictionary = compiled_by_id[aid_t]
		var w_t: int = int(comp_t["w"])
		var h_t: int = int(comp_t["h"])
		var orig_t: Vector2i = comp_t["origin"]
		var rows_t: int = int(comp_t["rows"])
		var synth_cls := PackedByteArray()
		synth_cls.resize(w_t * h_t)
		synth_cls.fill(0)
		var synth_var := PackedByteArray()
		synth_var.resize(w_t * h_t)
		synth_var.fill(0)
		for cell_t in Neighbourhoods.block_cells(area_t):
			var cr_t := CaricatureMap.cell_result(comp_t, cell_t, area_t)
			var tb_t: PackedByteArray = cr_t["tiles"]
			var bx_t: int = (cell_t.x - orig_t.x) * 32
			var by_t: int = (orig_t.y + rows_t - 1 - cell_t.y) * 32
			for ly_t in range(32):
				for lx_t in range(32):
					var ti_t := (ly_t * 32 + lx_t) * 3
					var gi_t := (by_t + ly_t) * w_t + (bx_t + lx_t)
					synth_cls[gi_t] = tb_t[ti_t]
					synth_var[gi_t] = tb_t[ti_t + 1]
		var seen_t := PackedByteArray()
		seen_t.resize(w_t * h_t)
		seen_t.fill(0)
		for y_t in range(h_t):
			for x_t in range(w_t):
				var idx_t := y_t * w_t + x_t
				if synth_cls[idx_t] != TileSynth2.TILE_TREE:
					continue
				var v_t: int = synth_var[idx_t]
				if y_t + 1 < h_t and synth_cls[(y_t + 1) * w_t + x_t] == TileSynth2.TILE_TREE and synth_var[(y_t + 1) * w_t + x_t] != v_t:
					push_error("caricature_dc_test: [F92] %s tree (%d,%d) var=%d differs from south tree (%d,%d) var=%d" % [aid_t, x_t, y_t, v_t, x_t, y_t + 1, synth_var[(y_t + 1) * w_t + x_t]])
					return false
				if x_t + 1 < w_t and synth_cls[idx_t + 1] == TileSynth2.TILE_TREE and synth_var[idx_t + 1] != v_t:
					push_error("caricature_dc_test: [F92] %s tree (%d,%d) var=%d differs from east tree (%d,%d) var=%d" % [aid_t, x_t, y_t, v_t, x_t + 1, y_t, synth_var[idx_t + 1]])
					return false
				if seen_t[idx_t] == 0:
					total_tree_clumps += 1
					if v_t == 1:
						pine_tree_clumps += 1
					var q_t: Array[int] = [idx_t]
					seen_t[idx_t] = 1
					var hq := 0
					while hq < q_t.size():
						var cur := q_t[hq]
						hq += 1
						var cx2 := cur % w_t
						var cy2 := int(cur / w_t)
						for nb_idx in [
							cur - 1 if cx2 > 0 else -1,
							cur + 1 if cx2 + 1 < w_t else -1,
							cur - w_t if cy2 > 0 else -1,
							cur + w_t if cy2 + 1 < h_t else -1,
						]:
							if nb_idx >= 0 and synth_cls[nb_idx] == TileSynth2.TILE_TREE and seen_t[nb_idx] == 0:
								seen_t[nb_idx] = 1
								q_t.append(nb_idx)
	var pine_share := float(pine_tree_clumps) / float(maxi(1, total_tree_clumps))
	print("[TREE CLUMPS DC] total_clumps=%d pine_clumps=%d share=%.3f" % [total_tree_clumps, pine_tree_clumps, pine_share])
	if total_tree_clumps < 50 or pine_share < 0.20 or pine_share > 0.40:
		push_error("caricature_dc_test: [F92] unexpected pine clump share %.3f (%d/%d)" % [pine_share, pine_tree_clumps, total_tree_clumps])
		return false

	return all_ok
