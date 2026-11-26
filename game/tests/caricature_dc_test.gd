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
	"hood:washington-dc:national-mall": "b7388e6a8f32a94919f541e52a79cdd9fca79a0ee0d05a795d0f07eb3bbf8580",
	"hood:washington-dc:tidal-basin": "085136c41612c20321134430519810c0ab0120ac4666fd90445d36604a6144a3",
	"hood:washington-dc:dupont-circle": "5f42867be9c75fd944a82d87c431d7e75e65f9585c2a5d86754839e3f1110c0b",
	"hood:washington-dc:capitol-hill": "66f76ada41a8fa0590481db6a444866407295d133e13d6655dd2b1d18998ef4f",
	"hood:washington-dc:union-station": "dcea1d8fddb185975131157200fbe7654deae32e25b3b4d58571b18185809e8f",
	"hood:washington-dc:georgetown": "28fb36efc8bb535dd5c3951241fca0560e9893538b089dba4bc5d55a819ec473",
	"hood:washington-dc:woodley-park": "c54d4aeb5e2c5f17371ca4701b9ffaab80ef8766a02789100af9970407c6489f",
	"hood:washington-dc:lincoln-memorial": "3224dc6be17d92b8a6b847e7ec7d7d4c5c6d61621840b54d7a5b62821807d2b8",
	"route:washington-dc:monument-grounds#1": "dd55d4fd416133302bb57c1261f85868103e24f500c2d0e4ba571ec1abe3ed0a",
	"route:washington-dc:pennsylvania-avenue#1": "50ee49371601476c7af70e30f583b265d8e3d3ae789bda0f974ff13487d0933d",
	"route:washington-dc:constitution-gardens#1": "fa5bb154dc1a93786b4e80e4368fccef205e4344ddd9b714cf6a77101e5b9cd6",
	"route:washington-dc:west-potomac-park#1": "a126ad10e8ff8eaff9768517e14838094298ea2987f393a585041686243545f4",
	"route:washington-dc:west-potomac-park#2": "6e7ae7fc769d3d6916cd34c898e22269308cba9190d8bc0d15accd93d4f79121",
	"route:washington-dc:upper-senate-park#1": "0d4567134bbe10afe4408bef5f304855ea5da5b9f2a7248242e30bf50ef94a51",
	"route:washington-dc:q-street#1": "1d513ed7fa6574cd8e907d5d31abd0dc2662ae903ba2ddaf20760c8694c64ccd",
	"route:washington-dc:connecticut-avenue#1": "acb154df2e9b3f4cf66f84d1c600fbde9c1d18d86a687847c2247a92cc67ebc3",
	"route:washington-dc:massachusetts-avenue#1": "89fce6a49f418408c9ed6d30badf76ed752bcdf504e1abfd16cdf4c3ffa268a1",
	"route:washington-dc:rock-creek-trail#1": "8dad2f06f7f9bd1010988f0b14c4f5a91790ec0825745568e8bccbfe344f8913",
	"route:washington-dc:rock-creek-trail#2": "596cf421d80e9f483975e846e40b83c5c58ba0505a931532d9283a190f75b0ac",
	"route:washington-dc:potomac-riverfront#1": "823cf725cf083595eb2165d1a4e2ebe05ea2a35c86d2a46a891bb4073828ebb7",
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
