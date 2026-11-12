extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps Contract Test (Item 49)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §9; docs/agent_execution_guide.md §6

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "ebe2621998f4f09a8f8c2ca84f4b082028629a67ba255d413d3ff22c2685f9fe",
	"hood:washington-dc:national-mall": "7f211c1f6ebb75f2453d5b49184562fc0e3ed2792f4dfdaa59804838c781e1e5",
	"hood:washington-dc:tidal-basin": "c342635eb42dfb86a189a87def5ad924ac233ef2dfa8032964bc711cbe7f68bf",
	"hood:washington-dc:dupont-circle": "dc799476e781e39abc1d0d5c09ba47f1bc53cef385c2298efa0b36195a50bc38",
	"hood:washington-dc:capitol-hill": "b57a9fafdab8df9541739b707b2e778edbb03efb66442396d0fc9d76c47d880c",
	"hood:washington-dc:union-station": "3960928359aba69e15c904439fe61fe1c870107bf9dd0ce7586d363a92d0e072",
	"hood:washington-dc:georgetown": "542538f16e127d651457db3ed1fcd9ad624b54fc253e001c76f4fcee37e7339b",
	"hood:washington-dc:woodley-park": "20e6d25350d8f90c8f4f9652dcf58440c63067fe15434db44cca30a7e23ff5ac",
	"hood:washington-dc:lincoln-memorial": "2d19037e3c83ec82ada955e30355022c89511ea56e040ab7db26c65c38a92a49",
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
	if areas.size() != 9:
		push_error("caricature_dc_test: expected 9 areas for city:washington-dc, got %d" % areas.size())
		return false

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

	return all_ok
