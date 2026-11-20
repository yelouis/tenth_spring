class_name InteriorTiles
extends RefCounted

## game/world/interior/interior_tiles.gd — Indoor Structural Tile Palette (0..16) & Hybrid Atlas Resolver (Item 57)
## Contract: docs/implementation_plan_dc_trial.md §11.3 B & docs/design_neighbourhoods_and_caricature.md §7.7

const AssetDB := preload("res://rom/asset_db.gd")

const TILE_PX: int = 32
const CLASS_COUNT: int = 17

const TILE_INT_VOID_BLACK: int = 0
const TILE_INT_FLOOR_MARBLE: int = 1
const TILE_INT_FLOOR_WOOD: int = 2
const TILE_INT_FLOOR_STONE: int = 3
const TILE_INT_CARPET_RUNNER: int = 4
const TILE_INT_WALL_TOP: int = 5
const TILE_INT_WALL_FACE: int = 6
const TILE_INT_DOOR_MAT: int = 7
const TILE_INT_STAIRS_UP: int = 8
const TILE_INT_STAIRS_DOWN: int = 9
const TILE_INT_PIT_CHASM: int = 10
const TILE_INT_WATER_CHANNEL: int = 11
const TILE_INT_GUST_ARROW_N: int = 12
const TILE_INT_GUST_ARROW_S: int = 13
const TILE_INT_GUST_ARROW_E: int = 14
const TILE_INT_GUST_ARROW_W: int = 15
const TILE_INT_RAILING: int = 16

const INDOOR_TILE_IDS: Dictionary = {
	"void_black": TILE_INT_VOID_BLACK,
	"floor_marble": TILE_INT_FLOOR_MARBLE,
	"floor_wood": TILE_INT_FLOOR_WOOD,
	"floor_stone": TILE_INT_FLOOR_STONE,
	"carpet_runner": TILE_INT_CARPET_RUNNER,
	"wall_top": TILE_INT_WALL_TOP,
	"wall_face": TILE_INT_WALL_FACE,
	"door_mat": TILE_INT_DOOR_MAT,
	"stairs_up": TILE_INT_STAIRS_UP,
	"stairs_down": TILE_INT_STAIRS_DOWN,
	"pit_chasm": TILE_INT_PIT_CHASM,
	"water_channel": TILE_INT_WATER_CHANNEL,
	"gust_arrow_n": TILE_INT_GUST_ARROW_N,
	"gust_arrow_s": TILE_INT_GUST_ARROW_S,
	"gust_arrow_e": TILE_INT_GUST_ARROW_E,
	"gust_arrow_w": TILE_INT_GUST_ARROW_W,
	"railing": TILE_INT_RAILING,
}

# Single-character grid tokens for interior floor rows (North-to-South)
const TOKEN_TO_CLASS: Dictionary = {
	" ": TILE_INT_VOID_BLACK,
	"M": TILE_INT_FLOOR_MARBLE,
	"W": TILE_INT_FLOOR_WOOD,
	".": TILE_INT_FLOOR_STONE,
	"C": TILE_INT_CARPET_RUNNER,
	"R": TILE_INT_CARPET_RUNNER,
	"#": TILE_INT_WALL_TOP,
	"=": TILE_INT_WALL_FACE,
	"D": TILE_INT_DOOR_MAT,
	"U": TILE_INT_STAIRS_UP,
	"d": TILE_INT_STAIRS_DOWN,
	"O": TILE_INT_PIT_CHASM,
	"~": TILE_INT_WATER_CHANNEL,
	"^": TILE_INT_GUST_ARROW_N,
	"v": TILE_INT_GUST_ARROW_S,
	">": TILE_INT_GUST_ARROW_E,
	"<": TILE_INT_GUST_ARROW_W,
	"-": TILE_INT_RAILING,
}

const CLASS_TO_TOKEN: Dictionary = {
	TILE_INT_VOID_BLACK: " ",
	TILE_INT_FLOOR_MARBLE: "M",
	TILE_INT_FLOOR_WOOD: "W",
	TILE_INT_FLOOR_STONE: ".",
	TILE_INT_CARPET_RUNNER: "C",
	TILE_INT_WALL_TOP: "#",
	TILE_INT_WALL_FACE: "=",
	TILE_INT_DOOR_MAT: "D",
	TILE_INT_STAIRS_UP: "U",
	TILE_INT_STAIRS_DOWN: "d",
	TILE_INT_PIT_CHASM: "O",
	TILE_INT_WATER_CHANNEL: "~",
	TILE_INT_GUST_ARROW_N: "^",
	TILE_INT_GUST_ARROW_S: "v",
	TILE_INT_GUST_ARROW_E: ">",
	TILE_INT_GUST_ARROW_W: "<",
	TILE_INT_RAILING: "-",
}

static var _fallback_tex: ImageTexture = null
static var _fallback_bundle_cache: Dictionary = {}
static var _tile_map_cfg_cache: Dictionary = {}
static var _known_kits_cache: Dictionary = {}
static var _known_fixtures_cache: Dictionary = {}

const EMERALD_TILE_MAP_PATH := "res://config/emerald_tile_map.json"

static func _ensure_cfg_loaded() -> void:
	if not _tile_map_cfg_cache.is_empty():
		return
	if FileAccess.file_exists(EMERALD_TILE_MAP_PATH):
		var f := FileAccess.open(EMERALD_TILE_MAP_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_tile_map_cfg_cache = parsed as Dictionary
				var ks: Variant = _tile_map_cfg_cache.get("indoor_kits", {})
				if ks is Dictionary:
					_known_kits_cache = ks as Dictionary
				var fs: Variant = _tile_map_cfg_cache.get("indoor_fixtures", {})
				if fs is Dictionary:
					_known_fixtures_cache = fs as Dictionary

static func has_kit(kit_id: String) -> bool:
	_ensure_cfg_loaded()
	return _known_kits_cache.has(kit_id)

static func has_fixture(fixture_id: String) -> bool:
	_ensure_cfg_loaded()
	return _known_fixtures_cache.has(fixture_id)

static func get_fixture_def(fixture_id: String) -> Dictionary:
	_ensure_cfg_loaded()
	var d: Variant = _known_fixtures_cache.get(fixture_id, null)
	return d if d is Dictionary else {}

static func known_kit_ids() -> Array[String]:
	_ensure_cfg_loaded()
	var out: Array[String] = []
	for k in _known_kits_cache.keys():
		out.append(str(k))
	out.sort()
	return out

static func known_fixture_ids() -> Array[String]:
	_ensure_cfg_loaded()
	var out: Array[String] = []
	for k in _known_fixtures_cache.keys():
		out.append(str(k))
	out.sort()
	return out

static func is_valid_class(cls: int) -> bool:
	return cls >= 0 and cls < CLASS_COUNT

static func is_walkable(cls: int) -> bool:
	return cls in [
		TILE_INT_FLOOR_MARBLE,
		TILE_INT_FLOOR_WOOD,
		TILE_INT_FLOOR_STONE,
		TILE_INT_CARPET_RUNNER,
		TILE_INT_DOOR_MAT,
		TILE_INT_STAIRS_UP,
		TILE_INT_STAIRS_DOWN,
		TILE_INT_GUST_ARROW_N,
		TILE_INT_GUST_ARROW_S,
		TILE_INT_GUST_ARROW_E,
		TILE_INT_GUST_ARROW_W,
	]

static func is_landing_safe(cls: int) -> bool:
	return cls in [
		TILE_INT_FLOOR_MARBLE,
		TILE_INT_FLOOR_WOOD,
		TILE_INT_FLOOR_STONE,
		TILE_INT_CARPET_RUNNER,
		TILE_INT_DOOR_MAT,
		TILE_INT_STAIRS_UP,
		TILE_INT_STAIRS_DOWN,
	]

static func is_gust_arrow(cls: int) -> bool:
	return cls >= TILE_INT_GUST_ARROW_N and cls <= TILE_INT_GUST_ARROW_W

static func gust_delta(cls: int) -> Vector2i:
	if cls == TILE_INT_GUST_ARROW_N:
		return Vector2i(0, -1)
	if cls == TILE_INT_GUST_ARROW_S:
		return Vector2i(0, 1)
	if cls == TILE_INT_GUST_ARROW_E:
		return Vector2i(1, 0)
	if cls == TILE_INT_GUST_ARROW_W:
		return Vector2i(-1, 0)
	return Vector2i.ZERO

static func resolve_atlas_bundle(cache_dir: String = AssetDB.DEFAULT_CACHE_DIR, force_fallback: bool = false) -> Dictionary:
	if not force_fallback:
		var em_v: Variant = AssetDB.indoor_tile_atlas(cache_dir)
		if em_v is Dictionary:
			var em_dict := em_v as Dictionary
			var em_tex: Texture2D = em_dict.get("texture", null)
			var em_json: Variant = em_dict.get("json", null)
			if em_tex != null and em_json is Dictionary and str((em_json as Dictionary).get("format", "")) == "emerald_indoor_v2":
				var jd := em_json as Dictionary
				return {
					"texture": em_tex,
					"source": "emerald",
					"cols": int(jd.get("cols", CLASS_COUNT)),
					"rows": int(jd.get("rows", 1)),
					"kits": jd.get("kits", {}),
					"fixtures": jd.get("fixtures", {}),
					"stamp_overrides": jd.get("stamp_overrides", {}),
				}
	return build_fallback_bundle()

static func resolve_atlas_texture(cache_dir: String = AssetDB.DEFAULT_CACHE_DIR, force_fallback: bool = false) -> Dictionary:
	var bundle := resolve_atlas_bundle(cache_dir, force_fallback)
	return {"texture": bundle.get("texture", null), "source": str(bundle.get("source", "fallback"))}

static func build_fallback_texture() -> ImageTexture:
	var bundle := build_fallback_bundle()
	return bundle.get("texture", null) as ImageTexture

static func resolve_kit_cells(fd: Dictionary, kit_def: Dictionary) -> Dictionary:
	var w := int(fd.get("w", 0))
	var h := int(fd.get("h", 0))
	var tiles: PackedByteArray = fd.get("tiles", PackedByteArray())
	var base_cells: Array = []
	var overlay_cells: Array = []
	if w <= 0 or h <= 0 or tiles.size() < w * h:
		return {"base": base_cells, "overlay": overlay_cells}

	if kit_def.is_empty():
		for y in range(h):
			for x in range(w):
				var cls := int(tiles[y * w + x])
				if cls >= 0 and cls < CLASS_COUNT:
					base_cells.append({"pos": Vector2i(x, y), "atlas": Vector2i(cls, 0)})
		return {"base": base_cells, "overlay": overlay_cells}

	var grid_coords: Dictionary = {}
	var stair_mask := PackedByteArray()
	stair_mask.resize(w * h)
	stair_mask.fill(0)

	# Pass 1: Stamp 3x2 recessed staircases around U and d
	for y in range(h):
		for x in range(w):
			var cls := int(tiles[y * w + x])
			var slot_name := ""
			if cls == TILE_INT_STAIRS_UP:
				slot_name = "stairs_up_3x2"
			elif cls == TILE_INT_STAIRS_DOWN:
				slot_name = "stairs_down_3x2"
			if slot_name.is_empty():
				continue
			var mat: Variant = kit_def.get(slot_name, [])
			if not (mat is Array) or (mat as Array).size() < 2:
				continue
			var ox := x - 1
			var oy := y - 1
			for sy in range(2):
				var row_arr: Array = (mat as Array)[sy]
				for sx in range(mini(3, row_arr.size())):
					var gx := ox + sx
					var gy := oy + sy
					if gx >= 0 and gx < w and gy >= 0 and gy < h:
						var coords: Array = row_arr[sx]
						grid_coords[Vector2i(gx, gy)] = Vector2i(int(coords[0]), int(coords[1]))
						stair_mask[gy * w + gx] = 1

	# Pass 2: Pair 2x1 door mats horizontally on D runs
	var dmat_arr: Variant = kit_def.get("door_mat_2x1", [])
	for y in range(h):
		var x := 0
		while x < w:
			var p := Vector2i(x, y)
			if not grid_coords.has(p) and int(tiles[y * w + x]) == TILE_INT_DOOR_MAT and dmat_arr is Array and (dmat_arr as Array).size() >= 2:
				var c0: Array = (dmat_arr as Array)[0]
				var c1: Array = (dmat_arr as Array)[1]
				grid_coords[p] = Vector2i(int(c0[0]), int(c0[1]))
				if x + 1 < w and int(tiles[y * w + (x + 1)]) == TILE_INT_DOOR_MAT and not grid_coords.has(Vector2i(x + 1, y)):
					grid_coords[Vector2i(x + 1, y)] = Vector2i(int(c1[0]), int(c1[1]))
					x += 2
					continue
			x += 1

	# Pass 3: Neighbour-aware walls, shadows, floors, puzzles, and 9-slice rug overlay
	var void_c := _atlas_vec(kit_def.get("void", [0, 0]))
	var wu_c := _atlas_vec(kit_def.get("wall_upper", [5, 0]))
	var wl_c := _atlas_vec(kit_def.get("wall_lower", [6, 0]))
	var pw_c := _atlas_vec(kit_def.get("partition_top_w", [5, 0]))
	var ph_c := _atlas_vec(kit_def.get("partition_top_h", [5, 0]))
	var pe_c := _atlas_vec(kit_def.get("partition_top_end_e", [5, 0]))
	var flr_c := _atlas_vec(kit_def.get("floor", [2, 0]))
	var shn_c := _atlas_vec(kit_def.get("floor_shadow_n", [2, 0]))
	var shw_c := _atlas_vec(kit_def.get("floor_shadow_w", [2, 0]))
	var shnw_c := _atlas_vec(kit_def.get("floor_shadow_nw", [2, 0]))
	var rug_mat: Variant = kit_def.get("rug_3x3", [])

	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			if grid_coords.has(p):
				base_cells.append({"pos": p, "atlas": grid_coords[p]})
				continue
			var cls := int(tiles[y * w + x])
			var atlas_v := Vector2i(cls, 0)
			if cls == TILE_INT_VOID_BLACK or cls == TILE_INT_PIT_CHASM:
				atlas_v = void_c
			elif cls == TILE_INT_WALL_TOP:
				var south_cls := int(tiles[(y + 1) * w + x]) if (y + 1 < h) else TILE_INT_VOID_BLACK
				if south_cls == TILE_INT_WALL_FACE or south_cls == TILE_INT_STAIRS_UP or south_cls == TILE_INT_STAIRS_DOWN:
					atlas_v = wu_c
				else:
					var has_w_wall := (x > 0 and int(tiles[y * w + (x - 1)]) == TILE_INT_WALL_TOP)
					var has_e_wall := (x + 1 < w and int(tiles[y * w + (x + 1)]) == TILE_INT_WALL_TOP)
					if not has_w_wall:
						atlas_v = pw_c
					elif not has_e_wall:
						atlas_v = pe_c
					else:
						atlas_v = ph_c
			elif cls == TILE_INT_WALL_FACE:
				atlas_v = wl_c
			elif cls in [TILE_INT_FLOOR_MARBLE, TILE_INT_FLOOR_WOOD, TILE_INT_FLOOR_STONE, TILE_INT_CARPET_RUNNER]:
				var north_cls := int(tiles[(y - 1) * w + x]) if y > 0 else TILE_INT_VOID_BLACK
				var west_cls := int(tiles[y * w + (x - 1)]) if x > 0 else TILE_INT_VOID_BLACK
				var north_stair := (y > 0 and stair_mask[(y - 1) * w + x] != 0)
				var shadow_n := north_stair or (north_cls in [TILE_INT_WALL_TOP, TILE_INT_WALL_FACE, TILE_INT_STAIRS_UP, TILE_INT_STAIRS_DOWN])
				var shadow_w := (x == 0) or (west_cls in [TILE_INT_VOID_BLACK, TILE_INT_WALL_TOP, TILE_INT_WALL_FACE])
				if shadow_n and shadow_w:
					atlas_v = shnw_c
				elif shadow_n:
					atlas_v = shn_c
				elif shadow_w:
					atlas_v = shw_c
				else:
					atlas_v = flr_c
				if cls == TILE_INT_CARPET_RUNNER and rug_mat is Array and (rug_mat as Array).size() >= 3:
					var rw := (x > 0 and int(tiles[y * w + (x - 1)]) == TILE_INT_CARPET_RUNNER)
					var re := (x + 1 < w and int(tiles[y * w + (x + 1)]) == TILE_INT_CARPET_RUNNER)
					var rn := (y > 0 and int(tiles[(y - 1) * w + x]) == TILE_INT_CARPET_RUNNER)
					var rs_b := (y + 1 < h and int(tiles[(y + 1) * w + x]) == TILE_INT_CARPET_RUNNER)
					var rx_i := 0 if not rw else (2 if not re else 1)
					var ry_i := 0 if not rn else (2 if not rs_b else 1)
					var rcell: Array = ((rug_mat as Array)[ry_i] as Array)[rx_i]
					overlay_cells.append({"pos": p, "atlas": Vector2i(int(rcell[0]), int(rcell[1]))})
			base_cells.append({"pos": p, "atlas": atlas_v})
	return {"base": base_cells, "overlay": overlay_cells}

static func _atlas_vec(v: Variant) -> Vector2i:
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int((v as Array)[0]), int((v as Array)[1]))
	return Vector2i.ZERO

static func _reg_fb_slot(slot_specs: Array, kind: String, key: String, args: Dictionary) -> Array:
	var idx := CLASS_COUNT + slot_specs.size()
	slot_specs.append({"idx": idx, "kind": kind, "key": key, "args": args})
	return [idx % CLASS_COUNT, int(idx / CLASS_COUNT)]

static func build_fallback_bundle() -> Dictionary:
	if not _fallback_bundle_cache.is_empty():
		return _fallback_bundle_cache
	_ensure_cfg_loaded()

	var slot_specs: Array = []
	var kits_meta: Dictionary = {}

	var r_rug: Array = []
	for ry in range(3):
		var row_r: Array = []
		for rx in range(3):
			row_r.append(_reg_fb_slot(slot_specs, "rug", "shared", {"rx": rx, "ry": ry}))
		r_rug.append(row_r)

	var kit_names := known_kit_ids()
	for kit_name in kit_names:
		var pal := _fallback_kit_palette(kit_name)
		var stairs_up := [
			[_reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 0, "sy": 0, "up": true, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 1, "sy": 0, "up": true, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 2, "sy": 0, "up": true, "pal": pal})],
			[_reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 0, "sy": 1, "up": true, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 1, "sy": 1, "up": true, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 2, "sy": 1, "up": true, "pal": pal})],
		]
		var stairs_dn := [
			[_reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 0, "sy": 0, "up": false, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 1, "sy": 0, "up": false, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 2, "sy": 0, "up": false, "pal": pal})],
			[_reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 0, "sy": 1, "up": false, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 1, "sy": 1, "up": false, "pal": pal}), _reg_fb_slot(slot_specs, "stair", kit_name, {"sx": 2, "sy": 1, "up": false, "pal": pal})],
		]
		kits_meta[kit_name] = {
			"void": [0, 0],
			"wall_upper": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "wall_upper", "pal": pal}),
			"wall_lower": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "wall_lower", "pal": pal}),
			"partition_top_w": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "partition_top_w", "pal": pal}),
			"partition_top_h": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "partition_top_h", "pal": pal}),
			"partition_top_end_e": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "partition_top_end_e", "pal": pal}),
			"floor": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "floor", "pal": pal}),
			"floor_shadow_n": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "floor_shadow_n", "pal": pal}),
			"floor_shadow_w": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "floor_shadow_w", "pal": pal}),
			"floor_shadow_nw": _reg_fb_slot(slot_specs, "kit_surface", kit_name, {"slot": "floor_shadow_nw", "pal": pal}),
			"door_mat_2x1": [_reg_fb_slot(slot_specs, "mat", kit_name, {"side": 0, "pal": pal}), _reg_fb_slot(slot_specs, "mat", kit_name, {"side": 1, "pal": pal})],
			"stairs_up_3x2": stairs_up,
			"stairs_down_3x2": stairs_dn,
			"rug_3x3": r_rug,
		}

	var fixtures_meta: Dictionary = {}
	for fx_id in known_fixture_ids():
		var fspec := get_fixture_def(fx_id)
		var fw := int(fspec.get("w", 1))
		var fh := int(fspec.get("h", 1))
		var fbase := int(fspec.get("base_rows", 1))
		var funder := bool(fspec.get("underlay", false))
		var flayer := str(fspec.get("layer", "l1"))
		var out_cells: Array = []
		for cy in range(fh):
			var row_c: Array = []
			for cx in range(fw):
				row_c.append(_reg_fb_slot(slot_specs, "fixture", fx_id, {"fx": fx_id, "cx": cx, "cy": cy, "w": fw, "h": fh}))
			out_cells.append(row_c)
		fixtures_meta[fx_id] = {"w": fw, "h": fh, "base_rows": fbase, "underlay": funder, "layer": flayer, "cells": out_cells}

	var total_slots := CLASS_COUNT + slot_specs.size()
	var total_rows := maxi(1, int((total_slots + CLASS_COUNT - 1) / CLASS_COUNT))
	var strip16 := Image.create(CLASS_COUNT * 16, total_rows * 16, false, Image.FORMAT_RGBA8)
	strip16.fill(Color(0, 0, 0, 0))

	# 0: void_black (#000000)
	_fill_tile16(strip16, TILE_INT_VOID_BLACK, Color8(0, 0, 0, 255))

	# 1: floor_marble — crisp pale museum marble with bevel & mortar grid
	_fill_tile16(strip16, TILE_INT_FLOOR_MARBLE, Color8(216, 220, 226, 255))
	for i in range(16):
		_px16(strip16, TILE_INT_FLOOR_MARBLE, i, 0, Color8(232, 236, 240, 255))
		_px16(strip16, TILE_INT_FLOOR_MARBLE, 0, i, Color8(232, 236, 240, 255))
		_px16(strip16, TILE_INT_FLOOR_MARBLE, i, 7, Color8(182, 188, 198, 255))
		_px16(strip16, TILE_INT_FLOOR_MARBLE, 7, i, Color8(182, 188, 198, 255))
		_px16(strip16, TILE_INT_FLOOR_MARBLE, i, 15, Color8(174, 180, 192, 255))
		_px16(strip16, TILE_INT_FLOOR_MARBLE, 15, i, Color8(174, 180, 192, 255))

	# 2: floor_wood — warm oak planks
	_fill_tile16(strip16, TILE_INT_FLOOR_WOOD, Color8(196, 152, 102, 255))
	for ry in [0, 4, 8, 12]:
		for rx in range(16):
			_px16(strip16, TILE_INT_FLOOR_WOOD, rx, ry, Color8(154, 112, 68, 255))
			if ry + 1 < 16:
				_px16(strip16, TILE_INT_FLOOR_WOOD, rx, ry + 1, Color8(210, 168, 118, 255))
	for j in [[5, 1, 3], [12, 5, 7], [3, 9, 11], [10, 13, 15]]:
		for vy in range(int(j[1]), int(j[2]) + 1):
			_px16(strip16, TILE_INT_FLOOR_WOOD, int(j[0]), vy, Color8(154, 112, 68, 255))

	# 3: floor_stone — slate chamber pavers
	_fill_tile16(strip16, TILE_INT_FLOOR_STONE, Color8(152, 158, 168, 255))
	for i in range(16):
		_px16(strip16, TILE_INT_FLOOR_STONE, i, 0, Color8(170, 176, 186, 255))
		_px16(strip16, TILE_INT_FLOOR_STONE, 0, i, Color8(170, 176, 186, 255))
		_px16(strip16, TILE_INT_FLOOR_STONE, i, 8, Color8(122, 128, 138, 255))
		_px16(strip16, TILE_INT_FLOOR_STONE, 8, i, Color8(122, 128, 138, 255))
		_px16(strip16, TILE_INT_FLOOR_STONE, i, 15, Color8(116, 122, 132, 255))
		_px16(strip16, TILE_INT_FLOOR_STONE, 15, i, Color8(116, 122, 132, 255))

	# 4: carpet_runner — royal blue woven runner
	_fill_tile16(strip16, TILE_INT_CARPET_RUNNER, Color8(88, 128, 188, 255))
	for y in range(0, 16, 2):
		for x in range(0, 16, 2):
			_px16(strip16, TILE_INT_CARPET_RUNNER, x, y, Color8(102, 142, 202, 255))

	# 5: wall_top — dark slate wall cap with bevel
	_fill_tile16(strip16, TILE_INT_WALL_TOP, Color8(72, 78, 94, 255))
	for x in range(16):
		_px16(strip16, TILE_INT_WALL_TOP, x, 0, Color8(104, 112, 128, 255))
		_px16(strip16, TILE_INT_WALL_TOP, x, 1, Color8(122, 130, 146, 255))
		_px16(strip16, TILE_INT_WALL_TOP, x, 14, Color8(52, 56, 70, 255))
		_px16(strip16, TILE_INT_WALL_TOP, x, 15, Color8(40, 44, 56, 255))

	# 6: wall_face — stone wainscot wall face with baseboard
	_fill_tile16(strip16, TILE_INT_WALL_FACE, Color8(194, 198, 206, 255))
	for x in range(16):
		_px16(strip16, TILE_INT_WALL_FACE, x, 0, Color8(136, 142, 154, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 1, Color8(224, 228, 234, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 11, Color8(154, 160, 170, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 12, Color8(232, 234, 238, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 13, Color8(232, 234, 238, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 14, Color8(92, 98, 112, 255))
		_px16(strip16, TILE_INT_WALL_FACE, x, 15, Color8(64, 70, 84, 255))
	for wy in range(2, 11):
		_px16(strip16, TILE_INT_WALL_FACE, 7, wy, Color8(168, 174, 184, 255))

	# 7: door_mat — crimson welcome mat with cream border
	_fill_tile16(strip16, TILE_INT_DOOR_MAT, Color8(198, 92, 92, 255))
	for i in range(16):
		_px16(strip16, TILE_INT_DOOR_MAT, i, 0, Color8(72, 56, 62, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, i, 15, Color8(72, 56, 62, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, 0, i, Color8(72, 56, 62, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, 15, i, Color8(72, 56, 62, 255))
	for i in range(1, 15):
		_px16(strip16, TILE_INT_DOOR_MAT, i, 1, Color8(236, 226, 214, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, i, 14, Color8(236, 226, 214, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, 1, i, Color8(236, 226, 214, 255))
		_px16(strip16, TILE_INT_DOOR_MAT, 14, i, Color8(236, 226, 214, 255))

	# 8: stairs_up — bright ascending stone treads
	_fill_tile16(strip16, TILE_INT_STAIRS_UP, Color8(122, 130, 144, 255))
	for sy in [2, 6, 10, 14]:
		for sx in range(2, 14):
			_px16(strip16, TILE_INT_STAIRS_UP, sx, sy, Color8(230, 234, 240, 255))
			_px16(strip16, TILE_INT_STAIRS_UP, sx, sy + 1, Color8(82, 88, 102, 255))
	for sy in range(16):
		_px16(strip16, TILE_INT_STAIRS_UP, 1, sy, Color8(64, 70, 84, 255))
		_px16(strip16, TILE_INT_STAIRS_UP, 14, sy, Color8(64, 70, 84, 255))

	# 9: stairs_down — recessed stairwell descending
	_fill_tile16(strip16, TILE_INT_STAIRS_DOWN, Color8(58, 64, 82, 255))
	for sy in [3, 7, 11]:
		for sx in range(2, 14):
			_px16(strip16, TILE_INT_STAIRS_DOWN, sx, sy, Color8(112, 120, 138, 255))
	for i in range(16):
		_px16(strip16, TILE_INT_STAIRS_DOWN, i, 0, Color8(152, 158, 170, 255))
		_px16(strip16, TILE_INT_STAIRS_DOWN, 0, i, Color8(152, 158, 170, 255))
		_px16(strip16, TILE_INT_STAIRS_DOWN, 15, i, Color8(152, 158, 170, 255))

	# 10: pit_chasm — pure black drop opening inside wooden/marble railing
	_fill_tile16(strip16, TILE_INT_PIT_CHASM, Color8(0, 0, 0, 255))

	# 11: water_channel — indoor canal water with ripple
	_fill_tile16(strip16, TILE_INT_WATER_CHANNEL, Color8(74, 126, 208, 255))
	for r in [[3, 4], [4, 4], [5, 5], [10, 10], [11, 10], [12, 11]]:
		_px16(strip16, TILE_INT_WATER_CHANNEL, int(r[0]), int(r[1]), Color8(138, 184, 242, 255))

	# 12..15: gust_arrow_n/s/e/w — framed directional current tiles
	_draw_arrow_tile16(strip16, TILE_INT_GUST_ARROW_N, Vector2i(0, -1))
	_draw_arrow_tile16(strip16, TILE_INT_GUST_ARROW_S, Vector2i(0, 1))
	_draw_arrow_tile16(strip16, TILE_INT_GUST_ARROW_E, Vector2i(1, 0))
	_draw_arrow_tile16(strip16, TILE_INT_GUST_ARROW_W, Vector2i(-1, 0))

	# 16: railing — wood-and-iron indoor balustrade over stone
	_fill_tile16(strip16, TILE_INT_RAILING, Color8(186, 190, 198, 255))
	for x in range(16):
		_px16(strip16, TILE_INT_RAILING, x, 3, Color8(72, 52, 38, 255))
		_px16(strip16, TILE_INT_RAILING, x, 4, Color8(178, 126, 78, 255))
		_px16(strip16, TILE_INT_RAILING, x, 5, Color8(144, 96, 56, 255))
		_px16(strip16, TILE_INT_RAILING, x, 12, Color8(64, 68, 80, 255))
	for post_x in [2, 7, 13]:
		for py in range(6, 13):
			_px16(strip16, TILE_INT_RAILING, post_x, py, Color8(64, 68, 80, 255))
			_px16(strip16, TILE_INT_RAILING, post_x + 1, py, Color8(96, 102, 116, 255))

	for spec_v in slot_specs:
		var sp := spec_v as Dictionary
		var idx := int(sp["idx"])
		var kind := str(sp["kind"])
		var key := str(sp["key"])
		var args: Dictionary = sp["args"]
		var col_i := idx % CLASS_COUNT
		var row_i := int(idx / CLASS_COUNT)
		var ox := col_i * 16
		var oy := row_i * 16
		if kind == "kit_surface":
			_draw_kit_surface16(strip16, ox, oy, str(args["slot"]), args["pal"] as Dictionary)
		elif kind == "rug":
			_draw_rug16(strip16, ox, oy, int(args["rx"]), int(args["ry"]))
		elif kind == "stair":
			_draw_stair16(strip16, ox, oy, int(args["sx"]), int(args["sy"]), bool(args["up"]), args["pal"] as Dictionary)
		elif kind == "mat":
			_draw_mat16(strip16, ox, oy, int(args["side"]), args["pal"] as Dictionary)
		elif kind == "fixture":
			_draw_fixture16(strip16, ox, oy, key, int(args["cx"]), int(args["cy"]))

	var atlas_w16 := CLASS_COUNT * 16
	var atlas_h16 := total_rows * 16
	var strip32 := Image.create(atlas_w16 * 2, atlas_h16 * 2, false, Image.FORMAT_RGBA8)
	for y in range(atlas_h16):
		for x in range(atlas_w16):
			var c := strip16.get_pixel(x, y)
			var dx := x * 2
			var dy := y * 2
			strip32.set_pixel(dx, dy, c)
			strip32.set_pixel(dx + 1, dy, c)
			strip32.set_pixel(dx, dy + 1, c)
			strip32.set_pixel(dx + 1, dy + 1, c)
	_fallback_tex = ImageTexture.create_from_image(strip32)
	_fallback_bundle_cache = {
		"texture": _fallback_tex,
		"source": "fallback",
		"cols": CLASS_COUNT,
		"rows": total_rows,
		"count": CLASS_COUNT,
		"columns": [],
		"kits": kits_meta,
		"fixtures": fixtures_meta,
		"stamp_overrides": {},
	}
	return _fallback_bundle_cache

static func _fill_tile16(img: Image, cls: int, col: Color) -> void:
	_fill_rect16(img, cls * 16, 0, 0, 0, 16, 16, col)

static func _px16(img: Image, cls: int, x: int, y: int, col: Color) -> void:
	_cpx(img, cls * 16, 0, x, y, col)

static func _cpx(img: Image, ox: int, oy: int, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < 16 and y >= 0 and y < 16:
		img.set_pixel(ox + x, oy + y, col)

static func _fill_rect16(img: Image, ox: int, oy: int, rx: int, ry: int, rw: int, rh: int, col: Color) -> void:
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			_cpx(img, ox, oy, x, y, col)

static func _fallback_kit_palette(kit_name: String) -> Dictionary:
	const PALS := {
		"gallery_wood": {"wu": [244, 236, 184], "wl": [214, 176, 132], "fa": [228, 204, 132], "fb": [198, 172, 102], "sn": [170, 144, 80], "mat": [238, 148, 142], "trim": [216, 206, 152]},
		"museum_tile": {"wu": [222, 206, 126], "wl": [172, 184, 224], "fa": [166, 214, 198], "fb": [146, 196, 180], "sn": [96, 166, 166], "mat": [244, 162, 140], "trim": [88, 106, 184]},
		"space_tech": {"wu": [204, 214, 226], "wl": [164, 178, 198], "fa": [196, 204, 214], "fb": [178, 186, 198], "sn": [138, 148, 164], "mat": [212, 108, 108], "trim": [122, 134, 154]},
		"hall_marble": {"wu": [232, 228, 204], "wl": [196, 192, 172], "fa": [210, 214, 222], "fb": [190, 194, 204], "sn": [156, 160, 172], "mat": [222, 118, 118], "trim": [142, 146, 158]},
		"clinic_clean": {"wu": [244, 240, 222], "wl": [238, 170, 106], "fa": [248, 244, 198], "fb": [232, 226, 174], "sn": [206, 194, 144], "mat": [224, 128, 72], "trim": [182, 148, 114]},
		"stone_shrine": {"wu": [148, 162, 182], "wl": [116, 130, 152], "fa": [168, 164, 148], "fb": [150, 146, 132], "sn": [118, 114, 102], "mat": [198, 104, 104], "trim": [88, 98, 116]},
		"abandoned_wood": {"wu": [174, 162, 112], "wl": [138, 126, 92], "fa": [184, 136, 92], "fb": [162, 116, 76], "sn": [132, 110, 68], "mat": [212, 172, 132], "trim": [96, 86, 62]},
		"cottage_wood": {"wu": [242, 232, 184], "wl": [208, 184, 132], "fa": [216, 178, 112], "fb": [192, 156, 96], "sn": [158, 126, 76], "mat": [232, 134, 118], "trim": [182, 148, 98]},
		"cottage_rowhouse": {"wu": [234, 238, 244], "wl": [204, 212, 224], "fa": [224, 198, 144], "fb": [204, 178, 126], "sn": [166, 144, 102], "mat": [108, 148, 214], "trim": [156, 168, 188]},
	}
	return PALS.get(kit_name, PALS["gallery_wood"]) as Dictionary

static func _col(rgb: Array, mul: float = 1.0) -> Color:
	return Color8(
		clampi(int(round(float(rgb[0]) * mul)), 0, 255),
		clampi(int(round(float(rgb[1]) * mul)), 0, 255),
		clampi(int(round(float(rgb[2]) * mul)), 0, 255),
		255
	)

static func _draw_kit_surface16(img: Image, ox: int, oy: int, slot: String, pal: Dictionary) -> void:
	if slot == "wall_upper":
		_fill_rect16(img, ox, oy, 0, 0, 16, 16, _col(pal["wu"]))
		_fill_rect16(img, ox, oy, 0, 0, 16, 1, Color8(68, 64, 62, 255))
		_fill_rect16(img, ox, oy, 0, 1, 16, 2, Color8(248, 248, 242, 255))
		_fill_rect16(img, ox, oy, 0, 14, 16, 2, _col(pal["trim"]))
		return
	if slot == "wall_lower":
		_fill_rect16(img, ox, oy, 0, 0, 16, 16, _col(pal["wl"]))
		_fill_rect16(img, ox, oy, 0, 0, 16, 1, _col(pal["wu"], 0.85))
		_fill_rect16(img, ox, oy, 0, 3, 16, 1, _col(pal["trim"]))
		_fill_rect16(img, ox, oy, 0, 13, 16, 2, _col(pal["wl"], 0.85))
		_fill_rect16(img, ox, oy, 0, 15, 16, 1, Color8(68, 62, 56, 255))
		return
	if slot.begins_with("partition_top"):
		_fill_rect16(img, ox, oy, 0, 0, 16, 16, _col(pal["wu"]))
		_fill_rect16(img, ox, oy, 0, 0, 16, 2, Color8(64, 60, 58, 255))
		_fill_rect16(img, ox, oy, 0, 2, 16, 12, Color8(244, 244, 236, 255))
		_fill_rect16(img, ox, oy, 0, 14, 16, 2, Color8(168, 164, 148, 255))
		if slot == "partition_top_w":
			_fill_rect16(img, ox, oy, 0, 0, 2, 16, Color8(64, 60, 58, 255))
		elif slot == "partition_top_end_e":
			_fill_rect16(img, ox, oy, 14, 0, 2, 16, Color8(64, 60, 58, 255))
		return

	# Floor and shadows (diamond parquet look)
	var fa := _col(pal["fa"])
	var fb := _col(pal["fb"])
	var sn := _col(pal["sn"])
	for y in range(16):
		for x in range(16):
			var d := absi((x % 8) - 3) + absi((y % 8) - 3)
			var base_c := fb if d == 3 else fa
			var is_sn := (slot == "floor_shadow_n" or slot == "floor_shadow_nw") and y < 4
			var is_sw := (slot == "floor_shadow_w" or slot == "floor_shadow_nw") and x < 3
			if is_sn or is_sw:
				base_c = sn
			_cpx(img, ox, oy, x, y, base_c)

static func _draw_rug16(img: Image, ox: int, oy: int, rx: int, ry: int) -> void:
	var cream := Color8(248, 232, 184, 255)
	var trim := Color8(224, 192, 134, 255)
	var edge := Color8(120, 86, 56, 255)
	var x0 := 2 if rx == 0 else 0
	var x1 := 14 if rx == 2 else 16
	var y0 := 2 if ry == 0 else 0
	var y1 := 14 if ry == 2 else 16
	_fill_rect16(img, ox, oy, x0, y0, x1 - x0, y1 - y0, cream)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var on_l := (rx == 0 and x == x0)
			var on_r := (rx == 2 and x == x1 - 1)
			var on_t := (ry == 0 and y == y0)
			var on_b := (ry == 2 and y == y1 - 1)
			var in_l := (rx == 0 and (x == x0 + 1 or x == x0 + 2))
			var in_r := (rx == 2 and (x == x1 - 2 or x == x1 - 3))
			var in_t := (ry == 0 and (y == y0 + 1 or y == y0 + 2))
			var in_b := (ry == 2 and (y == y1 - 2 or y == y1 - 3))
			if on_l or on_r or on_t or on_b:
				_cpx(img, ox, oy, x, y, edge)
			elif in_l or in_r or in_t or in_b:
				_cpx(img, ox, oy, x, y, trim)

static func _draw_stair16(img: Image, ox: int, oy: int, sx: int, sy: int, up: bool, pal: Dictionary) -> void:
	_draw_kit_surface16(img, ox, oy, "wall_upper" if sy == 0 else "wall_lower", pal)
	var frame := Color8(224, 212, 178, 255)
	var dark := Color8(62, 66, 82, 255)
	var step_hi := Color8(210, 152, 108, 255) if up else Color8(126, 134, 152, 255)
	var step_lo := Color8(136, 92, 64, 255) if up else Color8(78, 84, 102, 255)
	if sx == 0:
		_fill_rect16(img, ox, oy, 11, 0 if sy == 1 else 2, 5, 16 if sy == 1 else 14, frame)
		_fill_rect16(img, ox, oy, 10, 0 if sy == 1 else 2, 1, 16 if sy == 1 else 14, dark)
	elif sx == 2:
		_fill_rect16(img, ox, oy, 0, 0 if sy == 1 else 2, 5, 16 if sy == 1 else 14, frame)
		_fill_rect16(img, ox, oy, 5, 0 if sy == 1 else 2, 1, 16 if sy == 1 else 14, dark)
	else:
		_fill_rect16(img, ox, oy, 0, 2 if sy == 0 else 0, 16, 14 if sy == 0 else 16, dark)
		if sy == 1 or not up:
			for row_s in range(0, 16, 4):
				_fill_rect16(img, ox, oy, 0, row_s, 16, 2, step_hi)
				_fill_rect16(img, ox, oy, 0, row_s + 2, 16, 2, step_lo)

static func _draw_mat16(img: Image, ox: int, oy: int, side: int, pal: Dictionary) -> void:
	_draw_kit_surface16(img, ox, oy, "floor", pal)
	var mc := _col(pal["mat"])
	var ml := Color8(248, 232, 224, 255)
	var outline := Color8(120, 72, 72, 255)
	var x0 := 1 if side == 0 else 0
	var x1 := 16 if side == 0 else 15
	_fill_rect16(img, ox, oy, x0, 2, x1 - x0, 12, outline)
	_fill_rect16(img, ox, oy, x0 + (1 if side == 0 else 0), 3, x1 - x0 - 1, 10, mc)
	for y in range(4, 12):
		for x in range(x0 + 1, x1 - 1):
			if ((x + y) % 2) == 0:
				_cpx(img, ox, oy, x, y, ml)

static func _draw_fixture16(img: Image, ox: int, oy: int, fx_id: String, cx: int, cy: int) -> void:
	var dark := Color8(48, 48, 56, 255)
	var wood := Color8(178, 124, 72, 255)
	var cream := Color8(240, 234, 206, 255)
	var green := Color8(72, 164, 78, 255)
	var green_hi := Color8(134, 214, 108, 255)
	if fx_id == "em_wall_pilaster_1x2":
		_fill_rect16(img, ox, oy, 0, 0, 16, 16, Color8(246, 238, 198, 255))
		_fill_rect16(img, ox, oy, 4, 0, 8, 16, Color8(252, 248, 228, 255))
		_fill_rect16(img, ox, oy, 3, 0, 1, 16, Color8(146, 134, 108, 255))
		_fill_rect16(img, ox, oy, 12, 0, 1, 16, Color8(146, 134, 108, 255))
	elif fx_id.begins_with("em_painting"):
		var fcol := Color8(196, 146, 56, 255)
		var art := Color8(88, 148, 216, 255) if fx_id == "em_painting_meadow_2x2" else Color8(214, 136, 68, 255)
		if fx_id.ends_with("1x1"):
			_fill_rect16(img, ox, oy, 3, 4, 10, 9, dark)
			_fill_rect16(img, ox, oy, 4, 5, 8, 7, fcol)
			_fill_rect16(img, ox, oy, 5, 6, 6, 5, art)
		elif cy == 0:
			_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 8, 15, 8, fcol)
			_fill_rect16(img, ox, oy, 3 if cx == 0 else 0, 10, 13, 6, art)
		else:
			_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 0, 15, 6, fcol)
			_fill_rect16(img, ox, oy, 3 if cx == 0 else 0, 0, 13, 4, art)
	elif fx_id.begins_with("em_wall_window"):
		_fill_rect16(img, ox, oy, 1, 5, 14, 9, cream)
		_fill_rect16(img, ox, oy, 2, 6, 12, 7, Color8(122, 192, 244, 255))
		_fill_rect16(img, ox, oy, 3, 7, 4, 3, Color8(224, 246, 255, 255))
	elif fx_id == "em_wall_map_2x1":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 6, 15, 8, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 7, 14, 6, Color8(124, 198, 136, 255))
		_fill_rect16(img, ox, oy, 5, 8, 4, 3, Color8(216, 198, 118, 255))
	elif fx_id == "em_wall_clock_1x1":
		_fill_rect16(img, ox, oy, 4, 5, 8, 8, Color8(152, 162, 186, 255))
		_fill_rect16(img, ox, oy, 5, 6, 6, 6, cream)
		_fill_rect16(img, ox, oy, 7, 7, 1, 3, dark)
		_fill_rect16(img, ox, oy, 8, 9, 2, 1, Color8(192, 64, 64, 255))
	elif fx_id == "em_wall_notice_1x1":
		_fill_rect16(img, ox, oy, 4, 5, 8, 8, dark)
		_fill_rect16(img, ox, oy, 5, 6, 6, 6, cream)
		_fill_rect16(img, ox, oy, 6, 8, 4, 1, Color8(120, 130, 148, 255))
	elif fx_id.begins_with("em_chair"):
		var seat := Color8(88, 178, 96, 255) if fx_id == "em_chair_green_1x1" else Color8(216, 128, 98, 255)
		_fill_rect16(img, ox, oy, 4, 4, 8, 9, dark)
		_fill_rect16(img, ox, oy, 5, 5, 6, 7, seat)
		if fx_id == "em_chair_e_1x1":
			_fill_rect16(img, ox, oy, 3, 2, 2, 11, dark)
			_fill_rect16(img, ox, oy, 4, 3, 2, 9, Color8(168, 92, 68, 255))
		elif fx_id == "em_chair_w_1x1":
			_fill_rect16(img, ox, oy, 11, 2, 2, 11, dark)
			_fill_rect16(img, ox, oy, 10, 3, 2, 9, Color8(168, 92, 68, 255))
	elif fx_id == "em_stool_1x1":
		_fill_rect16(img, ox, oy, 4, 5, 8, 7, dark)
		_fill_rect16(img, ox, oy, 5, 6, 6, 5, Color8(208, 76, 76, 255))
	elif fx_id == "em_bookshelf_2x2":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 14, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 11, Color8(214, 218, 224, 255) if cy == 0 else wood)
		for bx in range(3, 14, 3):
			_fill_rect16(img, ox, oy, bx, 6 if cy == 0 else 2, 2, 6, Color8(192, 82, 82, 255) if (bx % 2 == 1) else Color8(72, 136, 198, 255))
	elif fx_id == "em_pc_desk_2x2":
		if cy == 0:
			_fill_rect16(img, ox, oy, 2, 4, 12, 12, Color8(224, 198, 108, 255))
			_fill_rect16(img, ox, oy, 4, 1, 8, 8, Color8(92, 98, 112, 255))
			if cx == 1:
				_fill_rect16(img, ox, oy, 5, 2, 6, 5, Color8(136, 178, 206, 255))
		else:
			_fill_rect16(img, ox, oy, 2, 0, 12, 8, Color8(178, 134, 72, 255))
	elif fx_id.begins_with("em_potted"):
		if cy == 0:
			_fill_rect16(img, ox, oy, 3, 5, 10, 11, green)
			_fill_rect16(img, ox, oy, 5, 6, 6, 6, green_hi)
		else:
			_fill_rect16(img, ox, oy, 4, 0, 8, 6, green)
			_fill_rect16(img, ox, oy, 4, 6, 8, 8, Color8(186, 188, 196, 255))
			_fill_rect16(img, ox, oy, 5, 7, 6, 6, Color8(138, 142, 152, 255))
	elif fx_id == "em_wood_table_2x2" or fx_id == "em_sofa_2x2":
		var body_c := Color8(216, 186, 128, 255) if fx_id == "em_wood_table_2x2" else cream
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 13, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 11, body_c)
	elif fx_id == "em_cot_cabinet_2x2":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 14 if cy == 1 else 16, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 12 if cy == 1 else 16, Color8(186, 136, 84, 255))
		_fill_rect16(img, ox, oy, 3 if cx == 0 else 1, 5 if cy == 0 else 3, 11, 8, Color8(138, 178, 208, 255) if cy == 0 else Color8(146, 102, 58, 255))
	elif fx_id == "em_cot_kitchen_2x2":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 14 if cy == 1 else 16, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 12 if cy == 1 else 16, Color8(214, 210, 198, 255))
		if cy == 1:
			_fill_rect16(img, ox, oy, 3 if cx == 0 else 2, 4, 10, 6, Color8(136, 156, 176, 255) if cx == 1 else Color8(88, 92, 104, 255))
	elif fx_id == "em_cot_bed_1x2":
		_fill_rect16(img, ox, oy, 2, 2 if cy == 0 else 0, 12, 14, dark)
		_fill_rect16(img, ox, oy, 3, 3 if cy == 0 else 0, 10, 12, Color8(232, 234, 240, 255) if cy == 0 else Color8(102, 154, 212, 255))
		if cy == 0:
			_fill_rect16(img, ox, oy, 4, 5, 8, 5, Color8(244, 246, 250, 255))
	elif fx_id == "em_trash_can_1x1":
		_fill_rect16(img, ox, oy, 4, 3, 8, 11, Color8(132, 138, 150, 255))
		_fill_rect16(img, ox, oy, 5, 4, 6, 2, Color8(194, 200, 212, 255))
	elif fx_id == "em_medicine_shelf_2x3" or fx_id == "em_medicine_cabinet_2x2":
		var is_tall := (fx_id == "em_medicine_shelf_2x3")
		var max_cy := 2 if is_tall else 1
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 14 if cy == max_cy else 16, Color8(72, 78, 92, 255))
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 12 if cy == max_cy else 16, Color8(186, 194, 206, 255))
		if cy < max_cy:
			_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 13, 13, 2, Color8(116, 124, 138, 255))
			for bx in range(3, 13, 4):
				_fill_rect16(img, ox, oy, bx, 5, 3, 7, Color8(216, 86, 86, 255) if (bx + cy) % 2 == 0 else Color8(82, 168, 224, 255))
				_fill_rect16(img, ox, oy, bx + 1, 4, 1, 1, cream)
		else:
			_fill_rect16(img, ox, oy, 3 if cx == 0 else 1, 2, 11, 10, Color8(146, 154, 168, 255))
			_fill_rect16(img, ox, oy, 4 if cx == 0 else 2, 6, 2, 2, dark)
	elif fx_id.begins_with("em_display_dais"):
		var max_cy := 3 if fx_id == "em_display_dais_5x4" else 2
		var max_cx := 4 if fx_id == "em_display_dais_5x4" else 5
		var x0 := 2 if cx == 0 else 0
		var x1 := 14 if cx == max_cx else 16
		var y0 := 3 if cy == 0 else 0
		var y1 := 14 if cy == max_cy else 16
		_fill_rect16(img, ox, oy, x0, y0, x1 - x0, y1 - y0, Color8(192, 188, 174, 255))
		if cy == max_cy:
			_fill_rect16(img, ox, oy, x0, 10, x1 - x0, 4, Color8(134, 128, 114, 255))
			_fill_rect16(img, ox, oy, x0, 14, x1 - x0, 1, dark)
		if cy == 0:
			_fill_rect16(img, ox, oy, x0, y0, x1 - x0, 2, Color8(228, 224, 210, 255))
	elif fx_id == "em_space_window_1x2":
		_draw_kit_surface16(img, ox, oy, "wall_upper" if cy == 0 else "wall_lower", _fallback_kit_palette("space_tech"))
		_fill_rect16(img, ox, oy, 0, 5 if cy == 0 else 0, 16, 11 if cy == 0 else 8, dark)
		_fill_rect16(img, ox, oy, 0, 6 if cy == 0 else 0, 16, 10 if cy == 0 else 6, Color8(108, 178, 236, 255))
		if cy == 0:
			_fill_rect16(img, ox, oy, 3, 8, 5, 3, Color8(210, 240, 255, 255))
	elif fx_id == "em_space_console_2x2" or fx_id == "em_space_drawer_1x2":
		_draw_kit_surface16(img, ox, oy, "wall_upper" if cy == 0 else "wall_lower", _fallback_kit_palette("space_tech"))
		if cy == 1:
			_fill_rect16(img, ox, oy, 1, 2, 14, 12, Color8(118, 130, 152, 255))
			_fill_rect16(img, ox, oy, 3, 4, 4, 3, Color8(88, 210, 156, 255))
			_fill_rect16(img, ox, oy, 9, 4, 4, 3, Color8(224, 146, 86, 255))
	elif fx_id == "em_rocket_table_2x2":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 13, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 11, Color8(176, 186, 202, 255))
		_fill_rect16(img, ox, oy, 3 if cx == 0 else 1, 4 if cy == 0 else 2, 10, 8, Color8(82, 144, 218, 255))
		_fill_rect16(img, ox, oy, 5 if cx == 0 else 3, 6 if cy == 0 else 4, 6, 3, cream)
	elif fx_id == "em_space_desk_2x2":
		_fill_rect16(img, ox, oy, 1 if cx == 0 else 0, 2 if cy == 0 else 0, 15, 13, dark)
		_fill_rect16(img, ox, oy, 2 if cx == 0 else 0, 3 if cy == 0 else 0, 13, 11, Color8(168, 178, 194, 255))
		if cy == 0:
			_fill_rect16(img, ox, oy, 4, 2, 8, 7, dark)
			_fill_rect16(img, ox, oy, 5, 3, 6, 5, Color8(110, 214, 168, 255))

static func _draw_arrow_tile16(img: Image, cls: int, dir: Vector2i) -> void:
	_fill_tile16(img, cls, Color8(224, 232, 244, 255))
	for i in range(16):
		_px16(img, cls, i, 0, Color8(92, 104, 126, 255))
		_px16(img, cls, i, 15, Color8(92, 104, 126, 255))
		_px16(img, cls, 0, i, Color8(92, 104, 126, 255))
		_px16(img, cls, 15, i, Color8(92, 104, 126, 255))
	var arrow_col := Color8(46, 112, 218, 255)
	for u in range(-4, 5):
		for v in range(-4, 5):
			var hit := false
			if v <= 0 and absi(u) <= (v + 4):
				hit = true
			elif v > 0 and absi(u) <= 2 and (v == 1 or v == 3):
				hit = true
			if hit:
				var rx := 8 + u
				var ry := 8 + v
				if dir == Vector2i(0, 1):
					rx = 8 - u
					ry = 7 - v
				elif dir == Vector2i(1, 0):
					rx = 7 - v
					ry = 8 + u
				elif dir == Vector2i(-1, 0):
					rx = 8 + v
					ry = 8 - u
				_px16(img, cls, rx, ry, arrow_col)
