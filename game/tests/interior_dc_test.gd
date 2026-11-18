extends Node

# game/tests/interior_dc_test.gd — Washington DC 6 Interiors (10 Floors) Verification & SHA-256 Pins (Item 57)
# Contract: docs/implementation_plan_dc_trial.md §11.3 D & docs/design_neighbourhoods_and_caricature.md §7.7

const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")
const RomImporter := preload("res://rom/importer.gd")
const AssetDB := preload("res://rom/asset_db.gd")

const CACHE_EMPTY := "user://test/interior_dc_empty"
const CACHE_EMERALD := "user://test/interior_dc_emerald"

const PINNED_SHA256: Dictionary = {
	"res://data/interiors/washington-dc/air-and-space.json": "ebe5629f41b2fb3194fc7cecd05032f3798bcf4300b13c5055871c52bb42e4f6",
	"res://data/interiors/washington-dc/georgetown-ruins.json": "c6f5185db206a980d8c50532affaf20bfb85ad29cfd697b47cc664cc3b48f497",
	"res://data/interiors/washington-dc/library-of-congress.json": "abdb0b3efe9914741d0f06724dbaa6bab281f5d78cd5de8ce2630bc325c88109",
	"res://data/interiors/washington-dc/lincoln-memorial.json": "e2f2ce5d452b529503e8ac40e11069e65d80baafd60cd4847e992fbd01897046",
	"res://data/interiors/washington-dc/washington-monument.json": "086a70d5cdad609e31b24921bc266c9ff1bff07c1d4205a9049267894400a8e1",
	"res://data/interiors/washington-dc/woodley-vet.json": "b962a93fb904f7359676c09b44cfbfa7ee154aa63989ce0c32c29834b8fade4a",
}

const EXPECTED_FLOOR_COUNTS: Dictionary = {
	"dc:washington-monument": 3,
	"dc:air-and-space": 1,
	"dc:library-of-congress": 2,
	"dc:lincoln-memorial": 2,
	"dc:georgetown-ruins": 1,
	"dc:woodley-vet": 1,
}

func _rm_tree(path: String) -> void:
	var g := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(g):
		return
	var da := DirAccess.open(g)
	if da == null:
		return
	da.list_dir_begin()
	var nm := da.get_next()
	while nm != "":
		if nm != "." and nm != "..":
			var sub := g.path_join(nm)
			if da.current_is_dir():
				_rm_tree(sub)
			else:
				DirAccess.remove_absolute(sub)
		nm = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(g)

func _cleanup() -> void:
	AssetDB.clear_tile_atlas_cache()
	_rm_tree(CACHE_EMPTY)
	_rm_tree(CACHE_EMERALD)

func _fail(msg: String) -> bool:
	push_error("interior_dc_test: " + msg)
	_cleanup()
	return false

func run_test() -> bool:
	_cleanup()
	var paths := InteriorMap.list_dc_interior_paths()
	if paths.size() != 6:
		return _fail("Expected 6 DC interior JSON files, found %d" % paths.size())

	var total_floors := 0
	var used_stamp_ids: Dictionary = {}

	for p in paths:
		if not PINNED_SHA256.has(p):
			return _fail("Missing SHA-256 pin for %s" % p)
		var actual_sha := FileAccess.get_sha256(p)
		if actual_sha != str(PINNED_SHA256[p]):
			return _fail("SHA-256 mismatch for %s: expected %s, got %s" % [p, str(PINNED_SHA256[p]), actual_sha])

		var doc := InteriorMap.load_json(p)
		if doc.is_empty():
			return _fail("Failed to parse JSON at %s" % p)
		var res := InteriorCheck.compile_and_check(doc)
		if not bool(res.get("ok", false)):
			return _fail("Interior %s failed I1..I6: %s" % [p, str(res)])
		if int(res.get("art_pending", -1)) != 0:
			return _fail("Interior %s has art_pending != 0" % p)

		var iid := str(res.get("id", ""))
		var fcount := int(res.get("floors", 0))
		if int(EXPECTED_FLOOR_COUNTS.get(iid, -1)) != fcount:
			return _fail("Interior %s expected %d floors, got %d" % [iid, int(EXPECTED_FLOOR_COUNTS.get(iid, -1)), fcount])
		total_floors += fcount

		var comp: Dictionary = res["compiled"]
		var floors: Array = comp.get("floors", [])
		for fi in range(floors.size()):
			var fd: Dictionary = floors[fi]
			for st_v in (fd["stamps"] as Array):
				var sid := int((st_v as Dictionary)["stamp_id"])
				if sid < 110 or sid > 134:
					return _fail("Interior %s floor %d placed stamp %d outside 110..134" % [iid, fi, sid])
				used_stamp_ids[sid] = true

			# Exercise InteriorView fallback draw path on every floor
			var iv := InteriorView.new()
			add_child(iv)
			var ok_fb := iv.load_interior(iid, fi, CACHE_EMPTY, true)
			var src_fb := iv.get_atlas_source_kind()
			var fsz := iv.get_floor_size()
			remove_child(iv)
			iv.free()
			if not ok_fb or src_fb != "fallback" or fsz.x < 12 or fsz.y < 10:
				return _fail("Fallback InteriorView build failed on %s floor %d (ok=%s src=%s size=%s)" % [iid, fi, str(ok_fb), src_fb, str(fsz)])

	if total_floors != 10:
		return _fail("Expected 10 total DC interior floors, got %d" % total_floors)

	# Verify all 25 Tier-5 interior stamps (110..134) are placed across DC's 6 interiors
	for sid in range(110, 135):
		if not used_stamp_ids.has(sid):
			return _fail("Tier-5 interior stamp %d is never placed in any DC interior" % sid)

	# Optional ROM-gated check: when TENTH_SPRING_ROM_GBA is set, verify Emerald indoor atlas path too
	var rom_env := OS.get_environment("TENTH_SPRING_ROM_GBA").strip_edges()
	if not rom_env.is_empty():
		var imp := RomImporter.import_gba_rom(rom_env, CACHE_EMERALD)
		if not bool(imp.get("ok", false)):
			return _fail("ROM-gated import_gba_rom failed: %s" % str(imp))
		var iatlas: Variant = AssetDB.indoor_tile_atlas(CACHE_EMERALD)
		if not (iatlas is Dictionary):
			return _fail("Expected non-null AssetDB.indoor_tile_atlas after GBA import")
		var itex: Texture2D = (iatlas as Dictionary).get("texture", null)
		if itex == null or itex.get_width() != 17 * 32 or itex.get_height() != 32:
			return _fail("Expected 544x32 Emerald indoor texture")
		var iv_em := InteriorView.new()
		add_child(iv_em)
		var ok_em := iv_em.load_interior("dc:washington-monument", 1, CACHE_EMERALD, false)
		var src_em := iv_em.get_atlas_source_kind()
		remove_child(iv_em)
		iv_em.free()
		if not ok_em or src_em != "emerald":
			return _fail("Expected InteriorView to select 'emerald' indoor atlas, got %s" % src_em)

	_cleanup()
	return true
