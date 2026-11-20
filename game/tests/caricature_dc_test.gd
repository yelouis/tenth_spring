extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "deca3a2fad1aed957838cd4b571d2d7c26e3b52361fe1a6f3b057dae6efa156a",
	"hood:washington-dc:national-mall": "a82a456da467599c576c7913003b178defe5f186454b9fda999c800dcbcf055a",
	"hood:washington-dc:tidal-basin": "cf77afd2c9dd22c7058b58b73cdc5a430368c6db0fd14c1eaea62061d0161fcf",
	"hood:washington-dc:dupont-circle": "e0d11df7b9a164bb24698caffe0e2927acc288ffa035d8a7d01162c9d176c6d0",
	"hood:washington-dc:capitol-hill": "f34dd25c14b6bc38cd4f75cf93147d1bf8ed0d396b8d74f60c196a92911a5ce7",
	"hood:washington-dc:union-station": "a9aa9434065479f887cc4b3516581520f407ff750ac6fea6775862313c7e9420",
	"hood:washington-dc:georgetown": "7a946dacabf23653981061d9e89bfe259ae2062f347d6c9cfffa6720e6f0258f",
	"hood:washington-dc:woodley-park": "982551e323b0734d06c30937ee5fe71e10cfb3636bd9e8e93a8f6d3012f6f887",
	"hood:washington-dc:lincoln-memorial": "b4701a757749ab7148e549a5234251e74ea5279c0934c74b9220f119e9168456",
	"route:washington-dc:monument-grounds#1": "db59aada938685b6deff8e3ab9e177144652b065f14a14f42a60471006032e5b",
	"route:washington-dc:pennsylvania-avenue#1": "6b8447accc891991022878a3cfe2462cf271ceed734516e95391672fee55404e",
	"route:washington-dc:constitution-gardens#1": "b4ba335b4e213465eb9d3f83e3d53b238a73c8a86561e96ffc3dc2f96954507b",
	"route:washington-dc:west-potomac-park#1": "2b5d10d3e8db4f05118ddcdf1555eec11dfd89b0b8dac68c2b1cef110443f77c",
	"route:washington-dc:west-potomac-park#2": "b5a54b6ff464cf4a3e9c56eeb80766b766bbf82febe4528fb51a3d1ab718e7f7",
	"route:washington-dc:upper-senate-park#1": "d28ba90e8f8bceb244787c3f0bd756290902ab1f9f59da0db22d4560b52207cf",
	"route:washington-dc:q-street#1": "3d4a275feb9466df8fcc4313196ba321bcb56fc7471b8a9159519373a67a470d",
	"route:washington-dc:connecticut-avenue#1": "6a32919dbc565797c97c1fa3a377f7b1c28a1ba72b555ef453ae33a0dd76e085",
	"route:washington-dc:massachusetts-avenue#1": "45d4a599755855a0284b5863fb783bbb0f44106d1f3254162769d446bf41a640",
	"route:washington-dc:rock-creek-trail#1": "6d8642be4cc7eaa96a68872906683ece81dbf34b58229314ead0c446d649b809",
	"route:washington-dc:rock-creek-trail#2": "299cfa5aaed15bf6b4c2e9e9b7c81cd641d52ea33d36f1f1cb33a6c1020e3558",
	"route:washington-dc:potomac-riverfront#1": "8fd08ea655e1a6d3f5feda023b1e7b335d0f83e77b2407fbbacd942c5b2ee22f",
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

		if area_id == "camp:washington-dc" or area_id == "hood:washington-dc:georgetown":
			var tc := CaricatureCheck.check_town(compiled, area)
			if not bool(tc.get("ok", false)):
				push_error("caricature_dc_test: %s failed check_town (%s): %s" % [area_id, str(tc.get("failed_rules", [])), str(tc)])
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
