extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3018af791784d1c0232e2c4ddbd6cbccb8c151ebd6d99dba1f71727c31934a2c",
	"hood:washington-dc:national-mall": "7916428593af35c7c7bd8038d1c08fb48e77f2933fca3172993f665321bb8378",
	"hood:washington-dc:tidal-basin": "c6d11f57f2e8cea922a3694ff466c2a2000b6afce846d2b7d4a4da8b12bbc509",
	"hood:washington-dc:dupont-circle": "8d910fe56972d0013fa2de772a9f9ab1d24c8c843eee8f01cb1ebe9cca57d125",
	"hood:washington-dc:capitol-hill": "2141aaf6f90b096fea85697910f54398e42147b10df5a87e04449124e7470083",
	"hood:washington-dc:union-station": "dff7a43d1eae368608489710619c2cbb507410e7bb854e7ec12078630ac6ef65",
	"hood:washington-dc:georgetown": "0ebd0dbcdfb30209e890fa6296ca129098ef5f0890a8c0d9b03012fcf72e73d7",
	"hood:washington-dc:woodley-park": "482a2f6d92eb77bdcb6ff5ba156494fdfd07854ddd419be22b3c64729632915e",
	"hood:washington-dc:lincoln-memorial": "2fd460e8c78153b055e008f88293196112fd7d0733d992ae1919d1fcb2e614bb",
	"route:washington-dc:monument-grounds#1": "1c23c654fcb8957e2789ad6f836af275627da8e1b5a6024fae51dfd09d9a3bce",
	"route:washington-dc:pennsylvania-avenue#1": "7b93e27b8e58dccced9e021a5f48c16a55a38ef96852cf1387dc6481fc88fa4e",
	"route:washington-dc:constitution-gardens#1": "0acbb2be3add36ce3eaaf708d1d2430dff027fbe1d50fe23d638dbc62f3dbbf6",
	"route:washington-dc:west-potomac-park#1": "6809131517bb497cf4e26f65be1d67e7668ec62741ab6d06d6ba0d6954e8d215",
	"route:washington-dc:west-potomac-park#2": "90ea4f4ec49b5db4c69463d82f1a28b09bfd0f03999aff52d47f256dbc91f23c",
	"route:washington-dc:upper-senate-park#1": "6cc0c445efb4bb49a9ff0c962c5137530d7535172a6ca3272f360bae1e210b64",
	"route:washington-dc:q-street#1": "0d344415b3ccedd7af600a9cb32d9c18bc58238b379c6044c901198d16577c9e",
	"route:washington-dc:connecticut-avenue#1": "46c5d942a6ecf821d3e11e64e5b6ffa1c10e61be0c323817aa435d5fefc6403b",
	"route:washington-dc:massachusetts-avenue#1": "85c2d4647e04407c140f67a3cb22dd62c59b0bf0aee869808dafcbeb515b5e2e",
	"route:washington-dc:rock-creek-trail#1": "fc45ed62ca80bb7458db1057fd741935f5eb98e633e5dd49c327d056fc0f14a1",
	"route:washington-dc:rock-creek-trail#2": "d0a80b63609c7c0a3e3f794cd22bf887e1499bfbbff194d5277442c855c7bb40",
	"route:washington-dc:potomac-riverfront#1": "e5dcde92b81ed271de60e8bd7dd48b7fa31a3ae864e88e55c8c1027dc5f2b39a",
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

	return all_ok
