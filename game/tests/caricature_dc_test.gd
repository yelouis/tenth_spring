extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3018af791784d1c0232e2c4ddbd6cbccb8c151ebd6d99dba1f71727c31934a2c",
	"hood:washington-dc:national-mall": "9a6daf74e24e959d95e6ea010e5296aee64ca41424f5af54f519c03ebbe9fcea",
	"hood:washington-dc:tidal-basin": "a70341078d156dd8cec91cd09862f15cb931532eb179774450c7e3ad592c37ed",
	"hood:washington-dc:dupont-circle": "a1b60c10c45aa3064341471968ae5a87c14f2c4fa62e2bddc58af662574a133e",
	"hood:washington-dc:capitol-hill": "4a4be5b7fe0be519fe46c7939dcda6978c4522f77aed844a99ed1edf02e1c2f1",
	"hood:washington-dc:union-station": "b7406c0e5191058a418bac20a95455690b2c2742cc8e645f8af2b58e47e20e83",
	"hood:washington-dc:georgetown": "cfb6ce878ca7127da7df4cd590d067e9c87f900b6138d5c2c6f7ee90033161c4",
	"hood:washington-dc:woodley-park": "bc6cc7498b1ca959f81689f46210c0a573c46b1cdc27c312cd3b32db4e0a2e6c",
	"hood:washington-dc:lincoln-memorial": "58657fc17dea7036f1d6f48dd1cc0f0ef2723f7240e9fecdbe163d6d531fa0f0",
	"route:washington-dc:monument-grounds#1": "b4a91b943cc7c688191a696954d48233f8f8e85b1926f940157393e898bae950",
	"route:washington-dc:pennsylvania-avenue#1": "1945c9a88fb3bd35ab1a6fa392d7954cebe26d55eb49c14f0aea25a4e2d1240a",
	"route:washington-dc:constitution-gardens#1": "0d8977616eee4a656b0c7a74712d5606098b10a2f9231516091023bcb67affe8",
	"route:washington-dc:west-potomac-park#1": "ad0cefa228ab40f02c4141b535eabd6b486b1c491e1b2fa8eb17efbae1de1727",
	"route:washington-dc:west-potomac-park#2": "27b40650468456778e8e630cc269fd13c0ffce300f25c5ec66a3d9b8dd7cc342",
	"route:washington-dc:upper-senate-park#1": "a425c2977359dac42aaefe3f3996d8cab1e79c913a4ae6ae5eb3a3d7e756b0b1",
	"route:washington-dc:q-street#1": "87ce0defacdf0bd5e5743a2926310c9024553b73e956a0ecbd2c6ef9016190be",
	"route:washington-dc:connecticut-avenue#1": "a4087862f624146a9f72f5eb4f92d9c6c26949c9ac1547f824dd5272783a6535",
	"route:washington-dc:massachusetts-avenue#1": "4d3d3f0022a42d70c1b2bc1629fc91e407fd20aa0457c4e3adb9d2f5a22f6e66",
	"route:washington-dc:rock-creek-trail#1": "486f9a777aeb4c62df9f3962dc193e689acb03c75d4a7dbe041c9bc538206a6e",
	"route:washington-dc:rock-creek-trail#2": "f9148c57f7c1c63baa1c5437bf0e858e4624f7180f5fd899cadaf3bda285edf2",
	"route:washington-dc:potomac-riverfront#1": "40773d44a1aa0ef1c95aa29ba4a1690b4d81d42774cc720dd3be55f11b8116ec",
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
