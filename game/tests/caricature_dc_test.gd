extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "fab50dc3781d26cd7fa211b59aef1e2490ccae9ed43fa33c393d16750af5e5e2",
	"hood:washington-dc:national-mall": "626fbbe37bfd121fbfc5629472f192fe9dac2b5793f3434335bb81cef99357da",
	"hood:washington-dc:tidal-basin": "9235d1bf2e5029560e14d8887ec6d7f00219a1185a8870ab9e3cbf045dcad081",
	"hood:washington-dc:dupont-circle": "406883d476d2c724d5a69d745b00a2b9671d799c75ef42d918a27ba7e7236c7f",
	"hood:washington-dc:capitol-hill": "0d2c1942e7446c6f0395760701918f0c2bdfbf2ba83cd8e11d32c28b93fd178a",
	"hood:washington-dc:union-station": "6a5ded4ec5ecf0a0753a8e4d07a15cbf5e32d8f52d39933f81bb38e4791a77b3",
	"hood:washington-dc:georgetown": "8a9064649e564c1992401e0fbff21f4b3dedd2c05d1ccbfb30892fd163102682",
	"hood:washington-dc:woodley-park": "b31ed27af2480026cdc89c99d7ac64bd25556ca73dfa1818d8a456d9deab65cc",
	"hood:washington-dc:lincoln-memorial": "1fa99ad67c18467eadd52f89b23a6a98149580dc5dc1594ed396845e4a8b20c3",
	"route:washington-dc:monument-grounds#1": "43cd7ff129e4d89710e1644baa8e1cb11089579434c3f1abb09d1fcbece02f09",
	"route:washington-dc:pennsylvania-avenue#1": "fee11d5afa554e2e0814b40e9b94ec328a60642b2c617c318dd09745f2d6eb5d",
	"route:washington-dc:constitution-gardens#1": "e4cd3188bb45a90f50841ccb8acf23b3014a682a07fe307c57f26fabe1fe5b0c",
	"route:washington-dc:west-potomac-park#1": "5c410d7efc2b3c78ea10d6471490e66c37dab688e07241ae38b113fcc3336406",
	"route:washington-dc:west-potomac-park#2": "936bf0e05ee4113e3d4995704300f3c6c81ed24ebaa77cecf6713bdab485fbac",
	"route:washington-dc:upper-senate-park#1": "25d59c9ccd002289232052e8a39b51abbebc22c8480de63739ad9b12181fb5a0",
	"route:washington-dc:q-street#1": "245ef256c5d83ec154f8478f63a27ec599c472caa1c494524e5b8e32cf4eb4cf",
	"route:washington-dc:connecticut-avenue#1": "719302f85fb35e9d6f893e33a95bbae8eec30cf476d5dfc70092959df016b214",
	"route:washington-dc:massachusetts-avenue#1": "fd6899b1ffd30e215106b2167e0f71caeac229049f8a34e3312a53f24ff92796",
	"route:washington-dc:rock-creek-trail#1": "a8b9de24bba33879acbe8a8af706352a0d6218d8264fad049673dfebb75a49e7",
	"route:washington-dc:rock-creek-trail#2": "f0f6dd55dc2f53703872f18d26693d2f46b5bae7e08f1a194a22f88e89d80f37",
	"route:washington-dc:potomac-riverfront#1": "83b215e5b71e31bd8a2e86aab21912283b10deaa828792f2db8a8f765f563620",
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

		compiled_by_id[area_id] = compiled
		measures_by_id[area_id] = m

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
