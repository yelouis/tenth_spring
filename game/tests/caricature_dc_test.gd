extends Node

# game/tests/caricature_dc_test.gd — Washington DC Caricature Maps & Routes Contract Test (Items 49, 54)
# Contract: docs/implementation_plan_dc_trial.md §2.5, §5, §10.10, §10.12; docs/agent_execution_guide.md §4

const Neighbourhoods := preload("res://world/neighbourhoods.gd")
const CaricatureMap := preload("res://world/caricature/caricature_map.gd")
const CaricatureCheck := preload("res://world/caricature/caricature_check.gd")
const MapConstants := preload("res://world/map_constants.gd")

const PINNED_SHA256: Dictionary = {
	"camp:washington-dc": "3018af791784d1c0232e2c4ddbd6cbccb8c151ebd6d99dba1f71727c31934a2c",
	"hood:washington-dc:national-mall": "1ac3ed472fef6e6b934e1b64dbb7f028a056a6064fe550cfe761d9bfc9adc3c4",
	"hood:washington-dc:tidal-basin": "cac4538a11672b4f92626fb3188b440002174f4285bae3a6e4b11e40f5737348",
	"hood:washington-dc:dupont-circle": "eda6d3fab9c28aa0c9c86f0d24d62015744965fd128263a39a4b4e30333de321",
	"hood:washington-dc:capitol-hill": "b2f756831990dc2d3bad8c126baadac2cc362aa8b65008aacb5c9c18641b9269",
	"hood:washington-dc:union-station": "5029a8f12719a3d62271eae666e600ec718229628cc70d6f2f6181e52063a09d",
	"hood:washington-dc:georgetown": "8e0eda421c3bfc542271062e8f48a34bae808f3a8a03072efae42de8f3d9d7fe",
	"hood:washington-dc:woodley-park": "e3ee02952b21272f879ebb08638d154623fe4ee2cc5040d787a2323ec9ad0a9a",
	"hood:washington-dc:lincoln-memorial": "02e3fc0e9f26368b00f3be058d04b6b34f860f1a95a39f88e8778b2e59fa58bf",
	"route:washington-dc:monument-grounds#1": "d26cce0ab3b811af5bb0f1e7f3d613c1fcf571ab81d27162c6112eb78184bbf4",
	"route:washington-dc:pennsylvania-avenue#1": "9826a7f9021932aa9c7e304c41a5517435b4be477b9d9f3eeaed3273920a1999",
	"route:washington-dc:constitution-gardens#1": "c89bcddb65ccf47f4837a28952bebac128adc8c52f73c28c34a463f0c0e9c26c",
	"route:washington-dc:west-potomac-park#1": "3719402baf5b58359c5808d73f3aebe37c9022502037a60d20091768a4a6e74c",
	"route:washington-dc:west-potomac-park#2": "df1013d3c1cea83772055408ee2cf4e0f13323df63b96dca472a51e9937b715f",
	"route:washington-dc:upper-senate-park#1": "4ae04a7899c122b5f2947389290e834c9ff435868b84a7d629a6d48578350527",
	"route:washington-dc:q-street#1": "cb7b0c42bcca5bcc6e5fc50bf4c85dd76f11737bac4dbba33a28f31955114f01",
	"route:washington-dc:connecticut-avenue#1": "40e50dab7c020653dd6f2679eff6ce983d1b55e6ba5d0d172eafc47b0553e656",
	"route:washington-dc:massachusetts-avenue#1": "758cff9b8ec306b97eee37fb7cc7b7192a75af94000f75997c6ccedbbd3dab5b",
	"route:washington-dc:rock-creek-trail#1": "693c9d699233aa7babc849527f0525f5e889d62a1270406788903abd707e497b",
	"route:washington-dc:rock-creek-trail#2": "2f67594a88d3f327bbde0c986fba97159a4e8fecd02aa6688365d3d3a057982b",
	"route:washington-dc:potomac-riverfront#1": "9de0c59c2f3b1a0d972a693f7276bc352710a75370687136a1ad5e68494e0b36",
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
