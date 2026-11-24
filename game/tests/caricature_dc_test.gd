extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3018af791784d1c0232e2c4ddbd6cbccb8c151ebd6d99dba1f71727c31934a2c",
	"hood:washington-dc:national-mall": "f50ff000d9ba5060493b7c3189cf210ead897956ef4b46e54c83495ba2629a71",
	"hood:washington-dc:tidal-basin": "71354ff88aa63c3bd1ad89678e8bd4c339604111dccb453bef0c3db552a2da9f",
	"hood:washington-dc:dupont-circle": "460f11d09e6e7b9b3ab0f503a26ba372e93f311284650ed428323bd2b7ad68df",
	"hood:washington-dc:capitol-hill": "21c67f4a081af6acc66ec94b08e7b189ae13b657fc41113e3104e9b389901c49",
	"hood:washington-dc:union-station": "ece42d932127d304f72b9f88500fe7111b935dbee13ed6c1d48c886b8cb9b0f3",
	"hood:washington-dc:georgetown": "fb94536091300873b88e74efdd60d4c596e6f129d5007512e88af9ca73014dd8",
	"hood:washington-dc:woodley-park": "a8dce8feb3a3476ad4d87bfdaf25a0d1e105b05a94ceaad3e415b3df5c0414f6",
	"hood:washington-dc:lincoln-memorial": "2b7a8d5e7efe535c0d6d8e01090fd9a0ec53ebb18b777e4d56fc912a8be56e0b",
	"route:washington-dc:monument-grounds#1": "d428342df0ed03570485950c5c720d3a5d517c337893a8ed94f31ba5162cafd7",
	"route:washington-dc:pennsylvania-avenue#1": "8ebdca3da74af159dae111b2d3bb9a690ccb11bb0a37a301ff3b99df29bd8199",
	"route:washington-dc:constitution-gardens#1": "6eb7e4ed9689152bf65e22c51b3cabe083242102060a9fa2c899616ad13870ec",
	"route:washington-dc:west-potomac-park#1": "5e4a3d3ea5ff51997050b0dbd891403f7dbae727f1a85f003339a5b9a178d514",
	"route:washington-dc:west-potomac-park#2": "451135160e94debf924b0f2e1e8de757a28d29f24e7d07d30c63f63327e7b604",
	"route:washington-dc:upper-senate-park#1": "4ae04a7899c122b5f2947389290e834c9ff435868b84a7d629a6d48578350527",
	"route:washington-dc:q-street#1": "c3adfbb84233a16483fd1efa9c84d3ec191eef43e69776a23b33388d01958bd5",
	"route:washington-dc:connecticut-avenue#1": "bef5a84f2f767ebd7ad9b388c066d598384bc6a7d986e88c9192c561c0895906",
	"route:washington-dc:massachusetts-avenue#1": "eba52023c6ab3298a96045d2b19086cc598b56c1635d2aa46d3cddcff7dd853f",
	"route:washington-dc:rock-creek-trail#1": "1c30451f2fe158565203221d783cfd85a507737bec1c5aec9ac9ab93f74bde69",
	"route:washington-dc:rock-creek-trail#2": "5ecf36c746d2c7b4bf4637b3bbf77f370ea843d65dcfe62b96d94adedd036ae8",
	"route:washington-dc:potomac-riverfront#1": "95b385e1db835ab6d59899826fd69cc754964bebf0f7da07577ab94ca741c530",
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
