extends Node

# game/tests/interior_dc_test.gd — Washington DC 6 Interiors (10 Floors) Verification & SHA-256 Pins (Item 57)
# Contract: docs/implementation_plan_dc_trial.md §11.3 D & docs/design_neighbourhoods_and_caricature.md §7.7

const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")
const InteriorView := preload("res://world/interior/interior_view.gd")
const RomImporter := preload("res://rom/importer.gd")
const AssetDB := preload("res://rom/asset_db.gd")
const GbaRom := preload("res://rom/gba_rom.gd")
const Gen3Tiles := preload("res://rom/gen3_tiles.gd")

const CACHE_EMPTY := "user://test/interior_dc_empty"
const CACHE_EMERALD := "user://test/interior_dc_emerald"

const PINNED_SHA256: Dictionary = {
	"res://data/interiors/washington-dc/air-and-space.json": "3d57937dad12c63f9476c716dea045c6c6ad7600337ccdda6c13832782368ee9",
	"res://data/interiors/washington-dc/georgetown-ruins.json": "501c13ab10f7fd3f2232808f38f1ffa0e01b8d1176a94c5b2846d30e78afe9fb",
	"res://data/interiors/washington-dc/library-of-congress.json": "c38256dbae7061c7fae40e334c4bd0fb605915fdb96eef9f8b5115ca22e29bbc",
	"res://data/interiors/washington-dc/lincoln-memorial.json": "1da6124d38029f3b2ec5593afb7694fef694026af815d146b17d2a8c0059f946",
	"res://data/interiors/washington-dc/washington-monument.json": "4dcae42fdbcadd64c6fbb0305e4198be5bf4ae3981a9599883d1b61943550e20",
	"res://data/interiors/washington-dc/woodley-vet.json": "29e823ce21422026832b1db8e8acb4b68ba1e06dac2bf466e7b3704849fbcb1d",
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

func _load_fallback_stamp_32(rel_path: String) -> Image:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes("res://assets/original/" + rel_path)
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return img

func _decode_expected_rom_obj_32(rom: GbaRom, frame_offset: int, palette_offset: int) -> Image:
	var pal_bytes := rom.read_bytes(palette_offset, 32)
	var frame_bytes := rom.read_bytes(frame_offset, 128)
	if pal_bytes.size() < 32 or frame_bytes.size() < 128:
		return null
	var pal: Array[Color] = []
	for c_idx in range(16):
		var c16 := int(pal_bytes[c_idx * 2]) | (int(pal_bytes[c_idx * 2 + 1]) << 8)
		pal.append(Gen3Tiles.bgr555_to_color(c16))
	var img16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img16.fill(Color(0, 0, 0, 0))
	const QUAD := [Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 8), Vector2i(8, 8)]
	for q in range(4):
		var qpos: Vector2i = QUAD[q]
		var toff := q * 32
		for py in range(8):
			var row_base := toff + py * 4
			for px in range(8):
				var b := int(frame_bytes[row_base + (px >> 1)])
				var c_idx := (b & 0x0F) if (px & 1) == 0 else (b >> 4)
				if c_idx != 0:
					img16.set_pixel(qpos.x + px, qpos.y + py, pal[c_idx])
	img16.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return img16

func _images_equal(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true

func _count_transparent_pixels(img: Image) -> int:
	if img == null:
		return 0
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a8 == 0:
				n += 1
	return n

func _fail(msg: String) -> bool:
	push_error("interior_dc_test: " + msg)
	_cleanup()
	return false

func _check_rendered_pit_cells(cache_dir: String, force_fallback: bool) -> String:
	const PIT_CASES := [
		{"iid": "dc:library-of-congress", "floor": 1, "cells": [Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5)]},
		{"iid": "dc:washington-monument", "floor": 1, "cells": [Vector2i(5, 6), Vector2i(12, 6)]},
		{"iid": "dc:washington-monument", "floor": 2, "cells": [Vector2i(8, 5), Vector2i(9, 5)]},
	]
	var black := Color8(0, 0, 0, 255)
	var mode_tag := "fallback" if force_fallback else "emerald"
	for pc in PIT_CASES:
		var iid := str(pc["iid"])
		var fl := int(pc["floor"])
		var iv := InteriorView.new()
		add_child(iv)
		var ok := iv.load_interior(iid, fl, cache_dir, force_fallback)
		if not ok:
			remove_child(iv)
			iv.free()
			return "Rendered pit check load failed for %s floor %d (%s)" % [iid, fl, mode_tag]
		for cell_v in (pc["cells"] as Array):
			var cell := cell_v as Vector2i
			var img := iv.render_view_cell_32(cell)
			for py in range(img.get_height()):
				for px in range(img.get_width()):
					var col := img.get_pixel(px, py)
					if col != black:
						remove_child(iv)
						iv.free()
						return "Rendered pit check failed (%s) on %s floor %d cell %s at px (%d,%d): got RGB(%d,%d,%d) expected #000000" % [
							mode_tag, iid, fl, str(cell), px, py, col.r8, col.g8, col.b8
						]
		remove_child(iv)
		iv.free()
	return ""

func _check_rendered_haunted_surround(cache_dir: String, force_fallback: bool) -> String:
	const HAUNTED_CASES := [
		{"iid": "dc:georgetown-ruins", "floor": 0, "sample_cell": Vector2i(8, 7)},
		{"iid": "dc:woodley-vet", "floor": 0, "sample_cell": Vector2i(7, 7)},
	]
	var black := Color8(0, 0, 0, 255)
	var mode_tag := "fallback" if force_fallback else "emerald"
	for hc in HAUNTED_CASES:
		var iid := str(hc["iid"])
		var fl := int(hc["floor"])
		var iv := InteriorView.new()
		add_child(iv)
		var ok := iv.load_interior(iid, fl, cache_dir, force_fallback)
		if not ok:
			remove_child(iv)
			iv.free()
			return "Rendered haunted check load failed for %s (%s)" % [iid, mode_tag]
		var fsz := iv.get_floor_size()
		var ww := float(fsz.x * InteriorView.TILE_PX)
		var wh := float(fsz.y * InteriorView.TILE_PX)
		var void_pts: Array[Vector2] = [
			Vector2(-16.0, -16.0),
			Vector2(ww + 16.0, -16.0),
			Vector2(-16.0, wh + 16.0),
			Vector2(ww + 16.0, wh + 16.0),
		]
		for pt in void_pts:
			var got := iv.sample_rendered_pixel_at_world(pt)
			if got != black:
				remove_child(iv)
				iv.free()
				return "Rendered haunted surround check failed (%s) on %s at world %s: got RGB(%d,%d,%d) expected #000000" % [
					mode_tag, iid, str(pt), got.r8, got.g8, got.b8
				]
		var sc := hc["sample_cell"] as Vector2i
		var room_pt := Vector2(float(sc.x * InteriorView.TILE_PX) + 16.0, float(sc.y * InteriorView.TILE_PX) + 16.0)
		var untinted := iv.get_untinted_base_pixel_at_world(room_pt)
		var tinted := iv.sample_rendered_pixel_at_world(room_pt)
		remove_child(iv)
		iv.free()
		if tinted == untinted:
			return "Rendered haunted room tint check failed (%s) on %s: interior pixel %s was not tinted (got %s)" % [
				mode_tag, iid, str(room_pt), str(tinted)
			]
	return ""

func run_test() -> bool:
	_cleanup()
	var paths := InteriorMap.list_dc_interior_paths()
	if paths.size() != 6:
		return _fail("Expected 6 DC interior JSON files, found %d" % paths.size())

	var total_floors := 0
	var used_stamp_ids: Dictionary = {}
	var stamp_counts: Dictionary = {110: 0, 114: 0, 115: 0}

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
				if sid < 110 or sid > 137:
					return _fail("Interior %s floor %d placed stamp %d outside 110..137" % [iid, fi, sid])
				used_stamp_ids[sid] = true
				if stamp_counts.has(sid):
					stamp_counts[sid] = int(stamp_counts[sid]) + 1

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

	if int(stamp_counts[110]) != 11 or int(stamp_counts[114]) != 2 or int(stamp_counts[115]) != 3:
		return _fail("Expected ROM-object counts {110:11, 114:2, 115:3}, got %s" % str(stamp_counts))

	# Verify all 28 Tier-5 interior stamps (110..137) are placed across DC's 6 interiors
	for sid in range(110, 138):
		if not used_stamp_ids.has(sid):
			return _fail("Tier-5 interior stamp %d is never placed in any DC interior" % sid)

	# Without-ROM fallback check: 110 (item ball), 114 (boulder), 115 (Rock Smash rock) draw original stamps
	const OBJ_CASES := [
		{"iid": "dc:library-of-congress", "floor": 0, "sid": 110, "obj_cls": "28", "rel": "interiors/int_item_ball.png"},
		{"iid": "dc:washington-monument", "floor": 1, "sid": 114, "obj_cls": "27", "rel": "interiors/int_push_boulder.png"},
		{"iid": "dc:air-and-space", "floor": 0, "sid": 115, "obj_cls": "26", "rel": "interiors/int_smash_rubble.png"},
	]
	for oc in OBJ_CASES:
		var iv_no_rom := InteriorView.new()
		add_child(iv_no_rom)
		var ok_nr := iv_no_rom.load_interior(str(oc["iid"]), int(oc["floor"]), CACHE_EMPTY, true)
		var fb_rendered := iv_no_rom.extract_rendered_stamp_image_32(int(oc["sid"]))
		remove_child(iv_no_rom)
		iv_no_rom.free()
		var expected_fb := _load_fallback_stamp_32(str(oc["rel"]))
		if not ok_nr or not _images_equal(fb_rendered, expected_fb):
			return _fail("Fallback check failed for stamp %d (%s): rendered != fallback PNG" % [int(oc["sid"]), str(oc["iid"])])

	var fb_pit_err := _check_rendered_pit_cells(CACHE_EMPTY, true)
	if not fb_pit_err.is_empty():
		return _fail(fb_pit_err)
	var fb_haunt_err := _check_rendered_haunted_surround(CACHE_EMPTY, true)
	if not fb_haunt_err.is_empty():
		return _fail(fb_haunt_err)

	# Optional ROM-gated check: when TENTH_SPRING_ROM_GBA is set, verify Emerald indoor atlas + ROM object overrides
	var rom_env := OS.get_environment("TENTH_SPRING_ROM_GBA").strip_edges()
	if not rom_env.is_empty():
		var imp := RomImporter.import_gba_rom(rom_env, CACHE_EMERALD)
		if not bool(imp.get("ok", false)):
			return _fail("ROM-gated import_gba_rom failed: %s" % str(imp))
		var iatlas: Variant = AssetDB.indoor_tile_atlas(CACHE_EMERALD)
		if not (iatlas is Dictionary):
			return _fail("Expected non-null AssetDB.indoor_tile_atlas after GBA import")
		var ijson: Dictionary = (iatlas as Dictionary).get("json", {})
		if str(ijson.get("format", "")) != "emerald_indoor_v2":
			return _fail("Expected format 'emerald_indoor_v2', got '%s'" % str(ijson.get("format", "")))
		var itex: Texture2D = (iatlas as Dictionary).get("texture", null)
		if itex == null or itex.get_width() != 17 * 32 or itex.get_height() < 64 or (itex.get_height() % 32) != 0:
			return _fail("Expected 544x(>=64, mult 32) Emerald indoor texture, got %s" % str(itex.get_size() if itex != null else Vector2i.ZERO))
		var iimg := itex.get_image()
		if iimg == null or iimg.get_pixel(0, 0) != Color8(0, 0, 0, 255):
			return _fail("Expected class 0 Emerald void pixel (0,0) to be pure #000000")

		var cfg_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/emerald_tile_map.json"))
		var obj_cfg: Dictionary = (cfg_parsed as Dictionary).get("object_sprites", {}) if cfg_parsed is Dictionary else {}
		var rom_open := GbaRom.open_rom(rom_env, false, true)
		if not bool(rom_open.get("ok", false)):
			return _fail("ROM-gated open_rom failed: %s" % str(rom_open))
		var rom_inst: GbaRom = rom_open["rom"]
		for oc in OBJ_CASES:
			var sid := int(oc["sid"])
			var spec: Dictionary = obj_cfg.get(str(oc["obj_cls"]), {})
			var exp_rom_32 := _decode_expected_rom_obj_32(rom_inst, int(spec.get("frame_offset", 0)), int(spec.get("palette_offset", 0)))
			var exp_fb_32 := _load_fallback_stamp_32(str(oc["rel"]))
			if exp_rom_32 == null or _count_transparent_pixels(exp_rom_32) == 0:
				rom_inst.close()
				return _fail("Expected decoded ROM sprite %d to have transparent background pixels" % sid)
			var iv_obj := InteriorView.new()
			add_child(iv_obj)
			var ok_obj := iv_obj.load_interior(str(oc["iid"]), int(oc["floor"]), CACHE_EMERALD, false)
			var em_rendered := iv_obj.extract_rendered_stamp_image_32(sid)
			remove_child(iv_obj)
			iv_obj.free()
			if not ok_obj or not _images_equal(em_rendered, exp_rom_32):
				rom_inst.close()
				return _fail("ROM object check failed for stamp %d (%s): rendered does not match transparent 2x ROM sprite" % [sid, str(oc["iid"])])
			if _images_equal(em_rendered, exp_fb_32):
				rom_inst.close()
				return _fail("ROM object check failed for stamp %d (%s): rendered still equals fallback stamp" % [sid, str(oc["iid"])])
		rom_inst.close()

		var iv_em := InteriorView.new()
		add_child(iv_em)
		var ok_em := iv_em.load_interior("dc:library-of-congress", 0, CACHE_EMERALD, false)
		var src_em := iv_em.get_atlas_source_kind()
		var loc_sz := iv_em.get_floor_size()
		remove_child(iv_em)
		iv_em.free()
		if not ok_em or src_em != "emerald":
			return _fail("Expected InteriorView to select 'emerald' indoor atlas, got %s" % src_em)
		if loc_sz.x > 21 or loc_sz.y > 14:
			return _fail("Expected Library of Congress 1F <= 21x14 Emerald reference size, got %s" % str(loc_sz))
		var em_pit_err := _check_rendered_pit_cells(CACHE_EMERALD, false)
		if not em_pit_err.is_empty():
			return _fail(em_pit_err)
		var em_haunt_err := _check_rendered_haunted_surround(CACHE_EMERALD, false)
		if not em_haunt_err.is_empty():
			return _fail(em_haunt_err)

	# Item 62: Verify 6 famous interiors vs all 22 DC interiors (6 famous + 16 small houses)
	var famous_paths := InteriorMap.list_dc_interior_paths()
	if famous_paths.size() != 6:
		return _fail("Expected list_dc_interior_paths() == 6, got %d" % famous_paths.size())
	var all_dc_paths := InteriorMap.list_all_dc_interior_paths()
	if all_dc_paths.size() != 22:
		return _fail("Expected list_all_dc_interior_paths() == 22, got %d" % all_dc_paths.size())
	for dp in all_dc_paths:
		var doc := InteriorMap.load_json(dp)
		if doc.is_empty():
			return _fail("Failed to load DC interior %s" % dp)
		var chk := InteriorCheck.compile_and_check(doc)
		if not bool(chk.get("ok", false)):
			return _fail("DC interior %s failed check_interior: %s" % [dp, str(chk)])

	_cleanup()
	return true
