extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3018af791784d1c0232e2c4ddbd6cbccb8c151ebd6d99dba1f71727c31934a2c",
	"hood:washington-dc:national-mall": "7f33bf19057748efff21fd09202b914f1feb9338a1d6aca7c42de8c23eef6a97",
	"hood:washington-dc:tidal-basin": "e25feb20f4347402887a3e47ce8e192442af719e52022eef15ae25474300e86f",
	"hood:washington-dc:dupont-circle": "998554c46e52098984367fc6d5190639ff55ebfeca3d2def959663eff3e7751f",
	"hood:washington-dc:capitol-hill": "afc71c2bf3226f93ceaecfd5c691f49ad2b424c3e6f03339a3e1c1c3e3421c49",
	"hood:washington-dc:union-station": "dfb6ea21ad8183020f984324aaec8eaf9eeb3dcfa73ad74703acc978a8b083fc",
	"hood:washington-dc:georgetown": "d20bc780b03b527c8ea25f1dee4472721c0bfef6a7701004b4542cd4b008334f",
	"hood:washington-dc:woodley-park": "2d8f9a96631756ca4010990021ea2e5954c3b30182796e45ac72a5b5fac5923e",
	"hood:washington-dc:lincoln-memorial": "07f1224c2840eb25db06e535d5e27d7437295fa57e168615f1c9c0f4fc4bf9b6",
	"route:washington-dc:monument-grounds#1": "2c34cdf29b5b73a4dbc680aaf557435d9e0f74d35395b6aadc23ac994bee5e0c",
	"route:washington-dc:pennsylvania-avenue#1": "b248654faf04d33ddf415f025b5920ccfb40b7367d3c48c10a6ce84285ef37af",
	"route:washington-dc:constitution-gardens#1": "12d9eded1fcbd95ae7c04ee5b60bb4629b8359b699845d24cfc9de41614a857a",
	"route:washington-dc:west-potomac-park#1": "2c0708f8f4b10f2482d2255f0e1f4e2d883463638d47bcdf287e483b1347e03f",
	"route:washington-dc:west-potomac-park#2": "d92f39d0d00e88512e7eed0c98c1a8e1762488cd7d9988bbe6b6132d6a5af388",
	"route:washington-dc:upper-senate-park#1": "081c41aa223e07c7d954157c3b2ed74e2b7e1acaf22ccc31fec77981d587fbf5",
	"route:washington-dc:q-street#1": "5b6961ec0d919a28c93a4c4323c03a2381781714a0ea17d2ec3f0a4ce6e67935",
	"route:washington-dc:connecticut-avenue#1": "df8ba20a157e52a46e43bb51c51e678efb460072979ddbc7d5c35d69ab727d73",
	"route:washington-dc:massachusetts-avenue#1": "a8acda126d6fd86330b849692a3facacfbab2b974ad774e3ee681dfa1298f4da",
	"route:washington-dc:rock-creek-trail#1": "f08c5186b326ad1364d7533ac6175eaf62269d72e0bb3fa3c42fc6824e6f54e0",
	"route:washington-dc:rock-creek-trail#2": "f8c119054889c4f72676b9c0454e881b95859d0a842c7bead530de219728337a",
	"route:washington-dc:potomac-riverfront#1": "5476d52028c8fd4ff42ab282c4bec3f1ef70c86d49868033760f074170749556",
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
