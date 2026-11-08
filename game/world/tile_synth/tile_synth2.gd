class_name TileSynth2
extends RefCounted

## TileSynth2 — Walking-scale tile synthesizer for Slice 2 ("Pokemon Look")
## Contract: docs/implementation_plan_world_generation_slice2.md §3, §4

const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")
const MapConstants := preload("res://world/map_constants.gd")

# Tile Vocabulary (§3)
const TILE_VOID := 0
const TILE_GRASS := 1
const TILE_TALL_GRASS := 2
const TILE_TREE := 3
const TILE_WATER := 4
const TILE_SAND := 5
const TILE_MARSH := 6
const TILE_PATH := 7
const TILE_ROAD := 8
const TILE_RAIL := 9
const TILE_BRIDGE := 10
const TILE_PLAZA := 11
const TILE_ROOF := 12
const TILE_WALL := 13
const TILE_DOOR := 14
const TILE_FENCE := 15
const TILE_FLOWERS := 16
const TILE_GRAVE := 17
const TILE_SIGN := 18
const TILE_CROP := 19
const TILE_RUBBLE := 20
const TILE_STAMP := 21

# Stamp flags in mask_id for TILE_STAMP (§14.2.2)
const STAMP_FLAG_SOLID := 1
const STAMP_FLAG_OVERHANG := 2
const STAMP_FLAG_DOOR := 4

# Grid Dimensions
const CELL_TILES := 32
const MARGIN_TILES := 4
const WORK_SIZE := 40 # 32 + 2 * 4
const WORK_CELL_START := 4
const WORK_CELL_END := 36 # exclusive
const OUTPUT_BUFFER_SIZE := 32 * 32 * 3 # 3072 bytes

# Salts (§3, §11.2 step 7, §14.4)
const SALT_TREE_SCATTER := 1
const SALT_FLOWERS := 2
const SALT_GRASS_VARIANT := 3
const SALT_ROAD_CRACKS := 4
const SALT_DOOR_ROOF := 5
const SALT_TREE_VARIANT := 6
const SALT_NOISE_LATTICE := 7
const SALT_FALLBACK_SKIP := 8
const SALT_BUILDING_FATE := 9
const SALT_ROOF_COLLAPSE := 10
const SALT_YARD_LOT_GRASS := 11
const SALT_LOT_TREE := 12
const SALT_PATH_OVERGROWTH := 13
const SALT_PLAZA_WEEDS := 14
const SALT_RUIN_STATE := 15
const SALT_RUIN_COLOURWAY := 16
const SALT_GONE_STATE := 17
const SALT_DECAL_COUNT := 18
const SALT_DECAL_DOORSTEP := 19
const SALT_DECAL_POS := 20
const SALT_BLOCK_DESIGN := 21

# Stamp metadata table 1..70 (0 reserved; §14.2.1, §14.3.2, F68 b-c, Item 38)
const STAMP_TABLE: Dictionary = {
	1: {"id": "arch", "kind": "landmark", "path": "landmarks/arch.png", "w": 24, "h": 24, "base_rows": 4, "door": [11, 23], "tiles": ["........++++++++........", ".......++++++++++.......", "......+++++..+++++......", ".....++++......++++.....", ".....+++........+++.....", "....++++.........+++....", "....+++..........+++....", "...++++..........++++...", "...+++............+++...", "...+++............+++...", "...+++............+++...", "..++++............++++..", "..++++............++++..", "..+++..............+++..", "..+++..............+++..", "..+++..............++++.", "..+++..............++++.", ".++++..............++++.", ".++++....++++++....++++.", ".++++....++++++....++++.", "+###+....+####+....+###+", "#####....+####+....#####", "#####....+####+....#####", "+++++....+####+....+++++"]},
	2: {"id": "boston_light", "kind": "landmark", "path": "landmarks/boston_light.png", "w": 2, "h": 5, "base_rows": 1, "door": [1, 4], "tiles": ["++", "++", "++", "++", "##"]},
	3: {"id": "coit", "kind": "landmark", "path": "landmarks/coit.png", "w": 2, "h": 10, "base_rows": 2, "door": [1, 9], "tiles": ["..", "..", "..", "++", "++", "++", "++", "++", "##", "##"]},
	4: {"id": "gg_tower", "kind": "landmark", "path": "landmarks/gg_tower.png", "w": 4, "h": 24, "base_rows": 2, "door": null, "tiles": ["....", "....", "....", "....", "....", "....", "....", "....", "....", "....", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "++++", "####", "#+##"]},
	5: {"id": "grand_central", "kind": "landmark", "path": "landmarks/grand_central.png", "w": 15, "h": 7, "base_rows": 4, "door": [7, 6], "tiles": ["...+++++++++...", ".+++++++++++++.", "+++++++++++++++", "###############", "###############", "###############", "###############"]},
	6: {"id": "hatteras_light", "kind": "landmark", "path": "landmarks/hatteras_light.png", "w": 2, "h": 9, "base_rows": 2, "door": [1, 8], "tiles": ["..", "..", "++", "++", "++", "++", "++", "##", "##"]},
	7: {"id": "independence", "kind": "landmark", "path": "landmarks/independence.png", "w": 7, "h": 9, "base_rows": 4, "door": [3, 8], "tiles": ["...+...", "...+...", "..+++..", "+.+++.+", "+++++++", "#######", "#######", "#######", "#######"]},
	8: {"id": "liberty", "kind": "landmark", "path": "landmarks/liberty.png", "w": 5, "h": 15, "base_rows": 3, "door": [2, 14], "tiles": [".....", ".....", ".....", ".+...", ".+...", ".+++.", ".+++.", ".+++.", ".+++.", ".+++.", ".+++.", ".+++.", "+###+", "#####", "#####"]},
	9: {"id": "library_of_congress", "kind": "landmark", "path": "landmarks/library_of_congress.png", "w": 22, "h": 14, "base_rows": 7, "door": [10, 13], "tiles": ["..........++..........", "..+++++++++++++++++...", ".++++++++++++++++++++.", ".++++++++++++++++++++.", ".++++++++++++++++++++.", ".++++++++++++++++++++.", "+++++++++++++++++++++.", "+####################+", "######################", "######################", "######################", "######################", "######################", "###++++#######+++++###"]},
	10: {"id": "lincoln", "kind": "landmark", "path": "landmarks/lincoln.png", "w": 9, "h": 7, "base_rows": 4, "door": [4, 6], "tiles": [".........", ".+++++++.", "+++++++++", "+#######+", "+#######+", "#########", "#########"]},
	11: {"id": "needle", "kind": "landmark", "path": "landmarks/needle.png", "w": 6, "h": 24, "base_rows": 3, "door": [2, 23], "tiles": ["......", "......", "......", "......", "..++..", "..++..", "..++..", "++++++", "++++++", ".++++.", ".++++.", "..++..", "..++..", "..++..", "..++..", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", "++++++", "######", "######", "+####+"]},
	12: {"id": "neon_signs", "kind": "landmark", "path": "landmarks/neon_signs.png", "w": 6, "h": 3, "base_rows": 1, "door": [3, 2], "tiles": [".+++++", ".+++++", "##+###"]},
	13: {"id": "obelisk", "kind": "landmark", "path": "landmarks/obelisk.png", "w": 6, "h": 24, "base_rows": 3, "door": [2, 23], "tiles": ["......", "......", "......", "......", "......", "..++..", "..++..", ".+++..", ".+++..", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", ".++++.", "######", "######", "######"]},
	14: {"id": "parthenon", "kind": "landmark", "path": "landmarks/parthenon.png", "w": 7, "h": 5, "base_rows": 3, "door": [3, 4], "tiles": [".+++++.", "+++++++", "######+", "######+", "#######"]},
	15: {"id": "house_s_a", "kind": "house", "path": "ruins/house_s_a.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	16: {"id": "house_s_a__teal", "kind": "house", "path": "ruins/house_s_a__teal.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	17: {"id": "house_s_a__green", "kind": "house", "path": "ruins/house_s_a__green.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	18: {"id": "house_s_a__purple", "kind": "house", "path": "ruins/house_s_a__purple.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	19: {"id": "house_s_a_door2", "kind": "house", "path": "ruins/house_s_a_door2.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	20: {"id": "house_s_a_door2__teal", "kind": "house", "path": "ruins/house_s_a_door2__teal.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	21: {"id": "house_s_a_door2__green", "kind": "house", "path": "ruins/house_s_a_door2__green.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	22: {"id": "house_s_a_door2__purple", "kind": "house", "path": "ruins/house_s_a_door2__purple.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	23: {"id": "house_s_b", "kind": "house", "path": "ruins/house_s_b.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	24: {"id": "house_s_b__teal", "kind": "house", "path": "ruins/house_s_b__teal.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	25: {"id": "house_s_b__green", "kind": "house", "path": "ruins/house_s_b__green.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	26: {"id": "house_s_b__purple", "kind": "house", "path": "ruins/house_s_b__purple.png", "w": 4, "h": 4, "base_rows": 4, "door": [1, 3]},
	27: {"id": "house_s_b_door2", "kind": "house", "path": "ruins/house_s_b_door2.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	28: {"id": "house_s_b_door2__teal", "kind": "house", "path": "ruins/house_s_b_door2__teal.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	29: {"id": "house_s_b_door2__green", "kind": "house", "path": "ruins/house_s_b_door2__green.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	30: {"id": "house_s_b_door2__purple", "kind": "house", "path": "ruins/house_s_b_door2__purple.png", "w": 4, "h": 4, "base_rows": 4, "door": [2, 3]},
	31: {"id": "house_m_a", "kind": "house", "path": "ruins/house_m_a.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	32: {"id": "house_m_a__teal", "kind": "house", "path": "ruins/house_m_a__teal.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	33: {"id": "house_m_a__green", "kind": "house", "path": "ruins/house_m_a__green.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	34: {"id": "house_m_a__purple", "kind": "house", "path": "ruins/house_m_a__purple.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	35: {"id": "house_m_b", "kind": "house", "path": "ruins/house_m_b.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	36: {"id": "house_m_b__teal", "kind": "house", "path": "ruins/house_m_b__teal.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	37: {"id": "house_m_b__green", "kind": "house", "path": "ruins/house_m_b__green.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	38: {"id": "house_m_b__purple", "kind": "house", "path": "ruins/house_m_b__purple.png", "w": 5, "h": 4, "base_rows": 4, "door": [2, 3]},
	39: {"id": "house_s_c", "kind": "shell", "path": "ruins/house_s_c.png", "w": 4, "h": 4, "base_rows": 4, "door": null},
	40: {"id": "house_s_c_door2", "kind": "shell", "path": "ruins/house_s_c_door2.png", "w": 4, "h": 4, "base_rows": 4, "door": null},
	41: {"id": "house_m_c", "kind": "shell", "path": "ruins/house_m_c.png", "w": 5, "h": 4, "base_rows": 4, "door": null},
	42: {"id": "ruined_block", "kind": "block", "path": "ruins/ruined_block.png", "w": 8, "h": 7, "base_rows": 7, "door": [3, 6], "door_cols": [3, 4], "tiled": true},
	43: {"id": "decal_rubble", "kind": "decal", "path": "ruins/decal_rubble.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	44: {"id": "decal_rubble_weeds", "kind": "decal", "path": "ruins/decal_rubble_weeds.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	45: {"id": "decal_stones", "kind": "decal", "path": "ruins/decal_stones.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	46: {"id": "decal_beams", "kind": "decal", "path": "ruins/decal_beams.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	47: {"id": "decal_wall_stump", "kind": "decal", "path": "ruins/decal_wall_stump.png", "w": 1, "h": 1, "base_rows": 1, "door": null},
	48: {"id": "decal_wall_corner", "kind": "decal", "path": "ruins/decal_wall_corner.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	49: {"id": "decal_tufts", "kind": "decal", "path": "ruins/decal_tufts.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	50: {"id": "decal_cracks", "kind": "decal", "path": "ruins/decal_cracks.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	51: {"id": "decal_weeds", "kind": "decal", "path": "ruins/decal_weeds.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	52: {"id": "decal_bush", "kind": "decal", "path": "ruins/decal_bush.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	53: {"id": "decal_bramble", "kind": "decal", "path": "ruins/decal_bramble.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	54: {"id": "decal_stump", "kind": "decal", "path": "ruins/decal_stump.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	55: {"id": "decal_creeper", "kind": "decal", "path": "ruins/decal_creeper.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	56: {"id": "decal_sapling", "kind": "decal", "path": "ruins/decal_sapling.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	57: {"id": "decal_boulder", "kind": "decal", "path": "ruins/decal_boulder.png", "w": 1, "h": 1, "base_rows": 1, "door": null},
	58: {"id": "decal_doorstep", "kind": "decal", "path": "ruins/decal_doorstep.png", "w": 1, "h": 1, "base_rows": 0, "door": null},
	59: {"id": "alcatraz", "kind": "landmark", "path": "landmarks/alcatraz.png", "w": 24, "h": 6, "base_rows": 3, "door": [12, 5], "tiles": [".......+.........++++...", "...++++++++++++++++++...", "...++++++++++++++++++...", "...+#################...", "...+#################++.", ".+####################+."]},
	60: {"id": "ruined_block_8x7_b", "kind": "block", "path": "ruins/ruined_block_8x7_b.png", "w": 8, "h": 7, "base_rows": 7, "door": [3, 6], "door_cols": [3, 4]},
	61: {"id": "ruined_block_6x11_a", "kind": "block", "path": "ruins/ruined_block_6x11_a.png", "w": 6, "h": 11, "base_rows": 11, "door": [2, 10], "door_cols": [2, 3]},
	62: {"id": "ruined_block_6x11_b", "kind": "block", "path": "ruins/ruined_block_6x11_b.png", "w": 6, "h": 11, "base_rows": 11, "door": [2, 10], "door_cols": [2, 3]},
	63: {"id": "ruined_block_9x9_a", "kind": "block", "path": "ruins/ruined_block_9x9_a.png", "w": 9, "h": 9, "base_rows": 9, "door": [4, 8], "door_cols": [4]},
	64: {"id": "ruined_block_9x9_b", "kind": "block", "path": "ruins/ruined_block_9x9_b.png", "w": 9, "h": 9, "base_rows": 9, "door": [4, 8], "door_cols": [4]},
	65: {"id": "ruined_block_11x13_a", "kind": "block", "path": "ruins/ruined_block_11x13_a.png", "w": 11, "h": 13, "base_rows": 13, "door": [5, 12], "door_cols": [5]},
	66: {"id": "ruined_block_11x13_b", "kind": "block", "path": "ruins/ruined_block_11x13_b.png", "w": 11, "h": 13, "base_rows": 13, "door": [5, 12], "door_cols": [5]},
	67: {"id": "ruined_block_16x14_a", "kind": "block", "path": "ruins/ruined_block_16x14_a.png", "w": 16, "h": 14, "base_rows": 14, "door": [7, 13], "door_cols": [7, 8]},
	68: {"id": "ruined_block_16x14_b", "kind": "block", "path": "ruins/ruined_block_16x14_b.png", "w": 16, "h": 14, "base_rows": 14, "door": [7, 13], "door_cols": [7, 8]},
	69: {"id": "ruined_block_23x14_a", "kind": "block", "path": "ruins/ruined_block_23x14_a.png", "w": 23, "h": 14, "base_rows": 14, "door": [11, 13], "door_cols": [11]},
	70: {"id": "ruined_block_23x14_b", "kind": "block", "path": "ruins/ruined_block_23x14_b.png", "w": 23, "h": 14, "base_rows": 14, "door": [11, 13], "door_cols": [11]}
}

static var _landmark_art_loaded := false
static var _landmark_art_map: Dictionary = {}
static var _stamp_id_by_asset_name: Dictionary = {}

static func _ensure_landmark_art_loaded() -> void:
	if _landmark_art_loaded:
		return
	_landmark_art_loaded = true
	for sid_key in STAMP_TABLE.keys():
		var sdef: Dictionary = STAMP_TABLE[sid_key]
		var aid: String = str(sdef.get("id", ""))
		if not aid.is_empty():
			_stamp_id_by_asset_name[aid] = int(sid_key)
	var path := "res://config/landmark_art.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var ints = parsed.get("interiors", {})
		if ints is Dictionary:
			for k in ints.keys():
				_landmark_art_map[str(k)] = ints[k]
		var structs = parsed.get("structures", {})
		if structs is Dictionary:
			for k in structs.keys():
				_landmark_art_map[str(k)] = structs[k]

static func get_landmark_stamp_id(lm_id: String) -> int:
	if lm_id.is_empty():
		return -1
	_ensure_landmark_art_loaded()
	var spec = _landmark_art_map.get(lm_id, null)
	if not (spec is Dictionary):
		return -1
	if str(spec.get("source", "")) != "original":
		return -1
	var asset_name: String = str(spec.get("stamp", ""))
	return int(_stamp_id_by_asset_name.get(asset_name, -1))

static func compute_stamp_tiles_from_image(img: Image, w: int, h: int, base_rows: int) -> Array[String]:
	var rows: Array[String] = []
	if img == null or img.get_width() != w * 16 or img.get_height() != h * 16:
		return rows
	for ty in h:
		var is_base: bool = (ty >= h - base_rows)
		var row_str := ""
		for tx in w:
			var opaque := 0
			for py in range(ty * 16, (ty + 1) * 16):
				for px in range(tx * 16, (tx + 1) * 16):
					if img.get_pixel(px, py).a8 > 0:
						opaque += 1
			if opaque == 0:
				row_str += "."
			elif is_base and opaque >= 128:
				row_str += "#"
			else:
				row_str += "+"
		rows.append(row_str)
	return rows

static func get_stamp_def(stamp_id: int) -> Dictionary:
	return STAMP_TABLE.get(stamp_id, {})

## Walkability function home (§14.2.4, Decision 27)
static func is_walkable(cls: int, _variant: int, mask: int) -> bool:
	if cls == TILE_STAMP:
		return (mask & STAMP_FLAG_SOLID) == 0
	if cls == TILE_VOID or cls == TILE_TREE or cls == TILE_WATER or cls == TILE_ROOF or cls == TILE_WALL or cls == TILE_FENCE or cls == TILE_SIGN:
		return false
	return true

static func is_tile_walkable_in_buffer(tiles: PackedByteArray, lx: int, ly: int) -> bool:
	if lx < 0 or lx >= 32 or ly < 0 or ly >= 32:
		return false
	var idx := (ly * 32 + lx) * 3
	return is_walkable(tiles[idx], tiles[idx + 1], tiles[idx + 2])

## Tiling lookup for ruined_block (8x7 source -> WxH footprint, never stacking wall rows above roof rows; §14.1.5)
static func ruined_block_src_tile(x: int, y: int, w: int, h: int) -> Vector2i:
	var ty := 0
	if h <= 5:
		var map_5 := [0, 1, 2, 5, 6]
		ty = map_5[clampi(y, 0, 4)]
	elif h == 6:
		var map_6 := [0, 1, 2, 4, 5, 6]
		ty = map_6[clampi(y, 0, 5)]
	else:
		if y == 0:
			ty = 0
		elif y <= h - 6:
			ty = 1
		elif y == h - 5:
			ty = 2
		else:
			ty = 3 + (y - (h - 4))

	var tx := 0
	if x <= 2:
		tx = maxi(0, x)
	elif x == w - 1:
		tx = 7
	elif w <= 6:
		tx = 3 if x == 3 else 6
	elif w == 7:
		if x == 3:
			tx = 3
		elif x == 4:
			tx = 4
		else:
			tx = 6
	else:
		if x == w - 3:
			tx = 5
		elif x == w - 2:
			tx = 6
		else:
			tx = 3 + ((x - 3) % 2)
	return Vector2i(tx, ty)

# Forbidden building placement tile classes (§4.2, §10.2, §11.1)
const FORBIDDEN_BUILDING_TILES: Array[int] = [
	TILE_WATER, TILE_ROAD, TILE_PATH, TILE_RAIL, TILE_BRIDGE,
	TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_STAMP, TILE_GRAVE, TILE_FENCE, TILE_VOID
]
const FORBIDDEN_LANDMARK_TILES: Array[int] = [
	TILE_WATER, TILE_ROAD, TILE_RAIL, TILE_BRIDGE,
	TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_STAMP, TILE_GRAVE, TILE_FENCE, TILE_VOID
]
const FORBIDDEN_SOUTH_RING_TILES: Array[int] = [
	TILE_WATER, TILE_RAIL, TILE_BRIDGE,
	TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_STAMP, TILE_VOID
]

# Nudge offsets in evaluation order (§10.2 step 4)
const NUDGE_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
	Vector2i(2, 0),
	Vector2i(-2, 0),
	Vector2i(0, 2),
	Vector2i(0, -2)
]

# Landmark nudge offsets (21 total, §11.1 step 2)
const LANDMARK_NUDGE_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
	Vector2i(2, 0),
	Vector2i(-2, 0),
	Vector2i(0, 2),
	Vector2i(0, -2),
	Vector2i(3, 0),
	Vector2i(-3, 0),
	Vector2i(0, 3),
	Vector2i(0, -3),
	Vector2i(4, 0),
	Vector2i(-4, 0),
	Vector2i(0, 4),
	Vector2i(0, -4)
]

## Portable FNV-1a 32-bit hash (§3)
static func fnv1a32(ints: Array) -> int:
	var h: int = 2166136261
	for val in ints:
		var uval: int = int(val) & 0xFFFFFFFF
		for i in 4:
			var b: int = (uval >> (i * 8)) & 0xFF
			h = (h ^ b) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
	return h

## Uniform pseudorandom float u in [0, 1) over global tile coords (§3)
static func u_rand(gx: int, gy: int, world_seed: int, salt: int) -> float:
	return float(fnv1a32([gx, gy, world_seed, salt])) / 4294967296.0

## Value noise v in [0, 1) with 4-tile lattice spacing (§3)
static func value_noise(gx: int, gy: int, world_seed: int) -> float:
	var i: int = floori(float(gx) / 4.0)
	var j: int = floori(float(gy) / 4.0)
	var fx: float = (float(posmod(gx, 4)) + 0.5) / 4.0
	var fy: float = (float(posmod(gy, 4)) + 0.5) / 4.0
	var l00: float = float(fnv1a32([i, j, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l10: float = float(fnv1a32([i + 1, j, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l01: float = float(fnv1a32([i, j + 1, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l11: float = float(fnv1a32([i + 1, j + 1, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	return l00 * (1.0 - fx) * (1.0 - fy) + l10 * fx * (1.0 - fy) + l01 * (1.0 - fx) * fy + l11 * fx * fy

## Quantize Vector2 WM coordinates for stable vertex indexing
static func _quantize_wm(v: Vector2) -> Vector2i:
	return Vector2i(int(round(v.x * 100.0)), int(round(v.y * 100.0)))

## 4-connected supercover line rasterization (§4.1 step 4)
static func supercover_line(c0: int, r0: int, c1: int, r1: int) -> Array[Vector2i]:
	var pts: Array[Vector2i] = []
	var dx: int = absi(c1 - c0)
	var dy: int = absi(r1 - r0)
	var x: int = c0
	var y: int = r0
	var n: int = 1 + dx + dy
	var x_inc: int = 1 if c1 > c0 else (-1 if c1 < c0 else 0)
	var y_inc: int = 1 if r1 > r0 else (-1 if r1 < r0 else 0)
	var error: int = dx - dy
	dx *= 2
	dy *= 2

	for _i in range(n):
		pts.append(Vector2i(x, y))
		if error > 0:
			x += x_inc
			error -= dy
		elif error < 0:
			y += y_inc
			error += dx
		else:
			x += x_inc
			error -= dy
			pts.append(Vector2i(x, y))
			y += y_inc
			error += dx
	return pts

## Point in polygon (even-odd rule)
static func point_in_polygon(px: float, py: float, outer_ring: PackedVector2Array, holes: Array[PackedVector2Array]) -> bool:
	if not _point_in_ring(px, py, outer_ring):
		return false
	for hole in holes:
		if _point_in_ring(px, py, hole):
			return false
	return true

static func _point_in_ring(px: float, py: float, ring: PackedVector2Array) -> bool:
	var n: int = ring.size()
	if n < 3:
		return false
	var inside := false
	for i in n:
		var j := (i + 1) % n
		var p0 := ring[i]
		var p1 := ring[j]
		if ((p0.y > py) != (p1.y > py)) and (px < (p1.x - p0.x) * (py - p0.y) / (p1.y - p0.y) + p0.x):
			inside = not inside
	return inside

## Point in rings (outer ring and hole list)
static func _point_in_rings(pt: Vector2, rings: Array[PackedVector2Array]) -> bool:
	if rings.is_empty():
		return false
	var holes: Array[PackedVector2Array] = []
	for i in range(1, rings.size()):
		holes.append(rings[i])
	return point_in_polygon(pt.x, pt.y, rings[0], holes)

## Shoelace area in polygon coordinate units
static func _shoelace_area(pts: PackedVector2Array) -> float:
	var n: int = pts.size()
	if n < 3:
		return 0.0
	var a := 0.0
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return absf(a) * 0.5

## Category priority for signs (§4.4)
static func _sign_priority(cat: String) -> int:
	match cat:
		"landmark":
			return 6
		"haunted":
			return 5
		"civic":
			return 4
		"medical":
			return 3
		"park":
			return 2
		_:
			return 1

## Determine road width in tiles from subkind (§2.2)
static func get_road_width(subkind: String) -> int:
	var base := subkind.trim_suffix(":bridge")
	match base:
		"motorway", "trunk":
			return 4
		"primary", "secondary":
			return 3
		"tertiary", "residential", "unclassified", "living_street", "road":
			return 2
		"service":
			return 2 # §13: Emerald has no one-tile street
		_:
			if base.ends_with("_link"):
				return 2
			return 2

## Determine waterway width in tiles from subkind (§2.2)
static func get_waterway_width(subkind: String) -> int:
	var base := subkind.trim_suffix(":bridge")
	match base:
		"river":
			return 3
		"canal":
			return 2
		"stream", "ditch", "drain":
			return 2 # §13: Emerald has no one-tile pond or stream
		_:
			return 2

## Check whether building template fits at (col0, row0) (§10.2 steps 2-3, §11.1 step 2)
static func _can_place_template(col0: int, row0: int, w: int, h: int, grid_class: PackedByteArray, reserved_grid: PackedByteArray, allow_path: bool = false) -> bool:
	if col0 < 5 or col0 + w > 35 or row0 < 5 or row0 + h > 35:
		return false
	var forbidden: Array[int] = FORBIDDEN_LANDMARK_TILES if allow_path else FORBIDDEN_BUILDING_TILES
	for tr in h:
		var r: int = row0 + tr
		for tc in w:
			var c: int = col0 + tc
			var idx: int = r * WORK_SIZE + c
			if grid_class[idx] in forbidden or reserved_grid[idx] != 0:
				return false
	var south_r: int = row0 + h
	if south_r >= WORK_SIZE:
		return false
	for tc in w:
		var c: int = col0 + tc
		var idx: int = south_r * WORK_SIZE + c
		if grid_class[idx] in FORBIDDEN_SOUTH_RING_TILES:
			return false
	return true

## Point-to-ring distance in store units (§11.1 step 1)
static func _point_to_ring_dist_su(pt: Vector2, ring: PackedVector2Array) -> float:
	var n: int = ring.size()
	if n == 0:
		return INF
	var min_d_sq := INF
	for i in n:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0
		if len_sq > 1e-8:
			t = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
		var proj := a + ab * t
		var d_sq := (pt - proj).length_squared()
		if d_sq < min_d_sq:
			min_d_sq = d_sq
	return sqrt(min_d_sq)

## Template door column offsets for a given template and width (§4.2)
static func _template_door_cols(t_name: String, w: int, gx0: int, gy0: int, world_seed: int) -> Array[int]:
	var cols: Array[int] = []
	if t_name == "house_s":
		var d_col: int = 1 if u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) < 0.5 else 2
		cols.append(d_col)
	elif t_name == "house_m":
		cols.append(2)
	else:
		for off in [2, 10, 18]:
			if off < w - 1:
				cols.append(off)
	return cols

## Build pure-OSM landmark-local terrain grid in global (C, R) coordinates (§14.3.5 rule 4, F68 a & e)
static func _build_landmark_terrain_grid(pad_c0: int, pad_c1: int, pad_r0: int, pad_r1: int, ncx_lo: int, ncx_hi: int, ncy_lo: int, ncy_hi: int, cx: int, cy: int, area: Dictionary) -> PackedByteArray:
	var gw: int = pad_c1 - pad_c0 + 1
	var gh: int = pad_r1 - pad_r0 + 1
	var total: int = gw * gh
	var local_class := PackedByteArray()
	local_class.resize(total)
	local_class.fill(TILE_VOID)

	var local_cemetery := PackedByteArray()
	local_cemetery.resize(total)
	local_cemetery.fill(0)

	var local_water_way := PackedByteArray()
	local_water_way.resize(total)
	local_water_way.fill(0)

	var local_water_poly_sea := PackedByteArray()
	local_water_poly_sea.resize(total)
	local_water_poly_sea.fill(0)

	# 1. Coverage & Sea (§4.1 steps 1-2)
	var coast_segments: Array = []
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for ncy in range(ncy_lo, ncy_hi + 1):
		for ncx in range(ncx_lo, ncx_hi + 1):
			var off := Vector2i(ncx - cx, ncy - cy)
			var n_data: Dictionary = area.get(off, {})
			var lines: Array = n_data.get("lines", [])
			for line in lines:
				if line.get("kind", "") != "coastline":
					continue
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue
				var origin := Vector2(float(ncx) * Grid.CELL_WM, float(ncy) * Grid.CELL_WM)
				for i in range(pts.size() - 1):
					var a := origin + pts[i] * MapStore.GEOM_UNIT_WM
					var b := origin + pts[i + 1] * MapStore.GEOM_UNIT_WM
					if (b - a).length_squared() < 1e-6:
						continue
					coast_segments.append([a, b])
					incoming[_quantize_wm(b)] = a
					outgoing[_quantize_wm(a)] = b

	for lr in gh:
		var gr: int = pad_r0 + lr
		var owner_cy: int = -floori(float(gr) / 32.0) - 1
		var gy_north: int = -gr - 1
		for lc in gw:
			var gc: int = pad_c0 + lc
			var owner_cx: int = floori(float(gc) / 32.0)
			var off := Vector2i(owner_cx - cx, owner_cy - cy)
			var n_data: Dictionary = area.get(off, {})
			var idx: int = lr * gw + lc
			if not n_data.get("covered", false):
				local_class[idx] = TILE_VOID
				continue
			local_class[idx] = TILE_GRASS
			var sea_val: int = int(n_data.get("sea", 0))
			if sea_val == 1:
				local_class[idx] = TILE_WATER
				local_water_poly_sea[idx] = 1
			elif sea_val == 2 and not coast_segments.is_empty():
				var p_wm := Vector2((float(gc) + 0.5) * Grid.TILE_WM, (float(gy_north) + 0.5) * Grid.TILE_WM)
				var min_dist_sq := INF
				var nearest_seg = null
				var nearest_t := 0.0
				for seg in coast_segments:
					var sa: Vector2 = seg[0]
					var sb: Vector2 = seg[1]
					var ab := sb - sa
					var len_sq := ab.length_squared()
					var t := 0.0
					if len_sq > 1e-6:
						t = clampf((p_wm - sa).dot(ab) / len_sq, 0.0, 1.0)
					var proj := sa + ab * t
					var dist_sq := (p_wm - proj).length_squared()
					if dist_sq < min_dist_sq:
						min_dist_sq = dist_sq
						nearest_seg = seg
						nearest_t = t
				if nearest_seg != null:
					var na: Vector2 = nearest_seg[0]
					var nb: Vector2 = nearest_seg[1]
					var is_sea := false
					if nearest_t > 1e-4 and nearest_t < 1.0 - 1e-4:
						is_sea = (nb - na).cross(p_wm - na) < 0.0
					else:
						var v: Vector2 = na if nearest_t <= 1e-4 else nb
						var vk := _quantize_wm(v)
						if incoming.has(vk) and outgoing.has(vk):
							var u_pt: Vector2 = incoming[vk]
							var w_pt: Vector2 = outgoing[vk]
							is_sea = (w_pt - u_pt).cross(p_wm - v) < 0.0
						else:
							is_sea = (nb - na).cross(p_wm - na) < 0.0
					if is_sea:
						local_class[idx] = TILE_WATER
						local_water_poly_sea[idx] = 1

	# 2. Land Cover Polygons (§4.1 step 3)
	var polys_by_order: Dictionary = {
		"farmland": [], "scrub": [], "forest": [], "park": [], "cemetery": [],
		"sand": [], "wetland": [], "parking": [], "water": []
	}
	for ncy in range(ncy_lo, ncy_hi + 1):
		for ncx in range(ncx_lo, ncx_hi + 1):
			var off := Vector2i(ncx - cx, ncy - cy)
			var polys: Array = area.get(off, {}).get("polys", [])
			var base_c: float = float(ncx * 32 - pad_c0)
			var base_r: float = float((-ncy - 1) * 32 - pad_r0)
			for poly in polys:
				var kind: String = poly.get("kind", "")
				if not polys_by_order.has(kind):
					continue
				var geom = poly.get("geom_rings", null)
				if geom == null:
					continue
				var rings: Array[PackedVector2Array] = []
				if geom is PackedByteArray:
					rings = MapStore.unpack_rings(geom)
				elif geom is Array:
					for r_item in geom:
						if r_item is PackedVector2Array:
							rings.append(r_item)
				if rings.is_empty():
					continue
				var mapped_rings: Array[PackedVector2Array] = []
				for ring in rings:
					var m_ring := PackedVector2Array()
					for pt in ring:
						m_ring.append(Vector2(base_c + 2.0 * pt.x, base_r + 32.0 - 2.0 * pt.y))
					mapped_rings.append(m_ring)
				polys_by_order[kind].append(mapped_rings)

	var order_keys := ["farmland", "scrub", "forest", "park", "cemetery", "sand", "wetland", "parking", "water"]
	for kind in order_keys:
		for rings in polys_by_order[kind]:
			var outer: PackedVector2Array = rings[0]
			var holes: Array[PackedVector2Array] = []
			for h_i in range(1, rings.size()):
				holes.append(rings[h_i])
			var min_c := gw - 1
			var max_c := 0
			var min_r := gh - 1
			var max_r := 0
			for pt in outer:
				min_c = mini(min_c, floori(pt.x))
				max_c = maxi(max_c, ceili(pt.x))
				min_r = mini(min_r, floori(pt.y))
				max_r = maxi(max_r, ceili(pt.y))
			min_c = clampi(min_c, 0, gw - 1)
			max_c = clampi(max_c, 0, gw - 1)
			min_r = clampi(min_r, 0, gh - 1)
			max_r = clampi(max_r, 0, gh - 1)
			for lr in range(min_r, max_r + 1):
				var py := float(lr) + 0.5
				var gy_north: int = -(pad_r0 + lr) - 1
				for lc in range(min_c, max_c + 1):
					var px := float(lc) + 0.5
					if not point_in_polygon(px, py, outer, holes):
						continue
					var idx := lr * gw + lc
					if local_class[idx] == TILE_VOID:
						continue
					match kind:
						"farmland":
							local_class[idx] = TILE_CROP if posmod(gy_north, 2) == 0 else TILE_GRASS
						"scrub":
							local_class[idx] = TILE_TALL_GRASS
						"forest":
							local_class[idx] = TILE_TREE
						"park":
							local_class[idx] = TILE_GRASS
						"cemetery":
							local_class[idx] = TILE_GRASS
							local_cemetery[idx] = 1
						"sand":
							local_class[idx] = TILE_SAND
						"wetland":
							local_class[idx] = TILE_MARSH
						"parking":
							local_class[idx] = TILE_PLAZA
						"water":
							local_class[idx] = TILE_WATER
							local_water_poly_sea[idx] = 1

	# 3. Linear features before buildings (§4.1 step 4a) + path bridges
	var line_groups: Dictionary = {"waterway": [], "rail": [], "road": [], "path": []}
	for ncy in range(ncy_lo, ncy_hi + 1):
		for ncx in range(ncx_lo, ncx_hi + 1):
			var off := Vector2i(ncx - cx, ncy - cy)
			var lines: Array = area.get(off, {}).get("lines", [])
			var base_c: float = float(ncx * 32 - pad_c0)
			var base_r: float = float((-ncy - 1) * 32 - pad_r0)
			for line in lines:
				var kind: String = line.get("kind", "")
				if not line_groups.has(kind):
					continue
				var subkind: String = line.get("subkind", "")
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue
				var mapped_pts := PackedVector2Array()
				for pt in pts:
					mapped_pts.append(Vector2(base_c + 2.0 * pt.x, base_r + 32.0 - 2.0 * pt.y))
				line_groups[kind].append({"subkind": subkind, "pts": mapped_pts})

	for kind in ["waterway", "rail", "road", "path"]:
		for item in line_groups[kind]:
			var subkind: String = item["subkind"]
			var is_bridge: bool = subkind.ends_with(":bridge")
			if kind == "path" and not is_bridge:
				continue
			var pts: PackedVector2Array = item["pts"]
			var width := 2
			var target_class := TILE_PATH
			match kind:
				"waterway":
					width = get_waterway_width(subkind)
					target_class = TILE_WATER
				"rail":
					width = 2
					target_class = TILE_RAIL
				"road":
					width = get_road_width(subkind)
					target_class = TILE_ROAD if width >= 3 else TILE_PATH
				"path":
					width = 2
					target_class = TILE_PATH
			var lo: int = (width - 1) / 2
			var hi: int = width - 1 - lo
			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var supercover := supercover_line(floori(p0.x), floori(p0.y), floori(p1.x), floori(p1.y))
				for center in supercover:
					for br in range(center.y - lo, center.y + hi + 1):
						if br < 0 or br >= gh:
							continue
						for bc in range(center.x - lo, center.x + hi + 1):
							if bc < 0 or bc >= gw:
								continue
							var idx := br * gw + bc
							var cur_cls: int = local_class[idx]
							if cur_cls == TILE_VOID:
								continue
							if kind == "waterway":
								local_class[idx] = TILE_WATER
								local_water_way[idx] = 1
							elif kind == "rail":
								if cur_cls == TILE_WATER or cur_cls == TILE_BRIDGE:
									if is_bridge:
										local_class[idx] = TILE_BRIDGE
								else:
									local_class[idx] = TILE_RAIL
							elif kind == "road":
								if cur_cls == TILE_WATER or cur_cls == TILE_BRIDGE:
									if is_bridge:
										local_class[idx] = TILE_BRIDGE
									elif local_water_way[idx] == 1 and local_water_poly_sea[idx] == 0:
										local_class[idx] = target_class
								else:
									local_class[idx] = target_class
							elif kind == "path" and is_bridge:
								if cur_cls == TILE_WATER or cur_cls == TILE_BRIDGE:
									local_class[idx] = TILE_BRIDGE

	# 4. Cemeteries (§4.1 step 7) -> GRAVE and FENCE
	for lr in gh:
		var gy_north: int = -(pad_r0 + lr) - 1
		for lc in gw:
			var idx := lr * gw + lc
			if local_cemetery[idx] == 1 and local_class[idx] == TILE_GRASS:
				var gc: int = pad_c0 + lc
				if posmod(gc, 2) == 0 and posmod(gy_north, 3) == 0:
					local_class[idx] = TILE_GRAVE

	var cemetery_fences := PackedByteArray()
	cemetery_fences.resize(total)
	cemetery_fences.fill(0)
	var card_offs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for lr in gh:
		for lc in gw:
			var idx := lr * gw + lc
			if local_cemetery[idx] == 1 and (local_class[idx] == TILE_GRASS or local_class[idx] == TILE_GRAVE):
				for noff in card_offs:
					var nc: int = lc + noff.x
					var nr: int = lr + noff.y
					if nc < 0 or nc >= gw or nr < 0 or nr >= gh or local_cemetery[nr * gw + nc] == 0:
						cemetery_fences[idx] = 1
						break
	for idx in total:
		if cemetery_fences[idx] == 1:
			local_class[idx] = TILE_FENCE

	return local_class

## Shared-input cross-cell landmark stamp resolution (§14.3.3, §14.3.5, F68 a & e)
static func _resolve_landmark_stamp(door_wm: Vector2, def: Dictionary, cx: int, cy: int, area: Dictionary) -> Dictionary:
	var sw: int = int(def.get("w", 0))
	var sh: int = int(def.get("h", 0))
	var base_rows: int = int(def.get("base_rows", sh))
	var tiles_map: Array = def.get("tiles", [])
	if sw <= 0 or sh <= 0 or tiles_map.size() != sh:
		return {"placed": false}

	var door_arr = def.get("door", null)
	var has_door: bool = (door_arr is Array and door_arr.size() >= 2)
	var door_col: int = int(door_arr[0]) if has_door else (sw / 2)
	var door_row: int = int(door_arr[1]) if has_door else (sh - 1)

	var door_gx: int = floori(door_wm.x / Grid.TILE_WM)
	var door_gy: int = -floori(door_wm.y / Grid.TILE_WM) - 1

	var c_min: int = door_gx - door_col - 4
	var c_max: int = door_gx - door_col + sw + 3
	var r_min: int = door_gy - door_row + sh - base_rows - 4
	var r_max: int = door_gy - door_row + sh + 4

	var ncx_lo: int = floori(float(c_min) / 32.0)
	var ncx_hi: int = floori(float(c_max) / 32.0)
	var ncy_lo: int = -floori(float(r_max) / 32.0) - 1
	var ncy_hi: int = -floori(float(r_min) / 32.0) - 1

	var pad_c0: int = c_min - 1
	var pad_c1: int = c_max + 1
	var pad_r0: int = r_min - 1
	var pad_r1: int = r_max + 1
	var gw: int = pad_c1 - pad_c0 + 1

	var local_class: PackedByteArray = _build_landmark_terrain_grid(
		pad_c0, pad_c1, pad_r0, pad_r1, ncx_lo, ncx_hi, ncy_lo, ncy_hi, cx, cy, area
	)

	var forbidden_base: Array[int] = [
		TILE_WATER, TILE_ROAD, TILE_RAIL, TILE_BRIDGE, TILE_VOID, TILE_GRAVE, TILE_FENCE
	]
	var forbidden_south: Array[int] = [
		TILE_WATER, TILE_RAIL, TILE_BRIDGE, TILE_VOID
	]

	for nudge in LANDMARK_NUDGE_OFFSETS:
		var agx: int = door_gx - door_col + nudge.x
		var agy: int = door_gy - door_row + nudge.y
		var ok := true
		for ty in range(sh - base_rows, sh):
			var row_str: String = str(tiles_map[ty])
			for tx in sw:
				var is_door_tile: bool = (has_door and tx == door_col and ty == door_row)
				if row_str[tx] == "#" or is_door_tile:
					var lc: int = (agx + tx) - pad_c0
					var lr: int = (agy + ty) - pad_r0
					var cls: int = local_class[lr * gw + lc]
					if cls in forbidden_base:
						ok = false
						break
			if not ok:
				break
		if ok and has_door:
			var sc: int = (agx + door_col) - pad_c0
			var sr: int = (agy + door_row + 1) - pad_r0
			var s_cls: int = local_class[sr * gw + sc]
			if s_cls in forbidden_south:
				ok = false
		if ok:
			return {
				"placed": true,
				"anchor_gx": agx,
				"anchor_gy": agy
			}

	return {"placed": false}

static var _use_legacy_item33_anchor_frame := false

static func _cell_row0(cy: int) -> int:
	return cy * 32 if _use_legacy_item33_anchor_frame else (-cy - 1) * 32

## Synthesize a cell's 32x32 tiles from a 3x3 neighbourhood (§4)
static func synthesize_cell(cx: int, cy: int, area: Dictionary, world_seed: int = MapConstants.MAP_SEED) -> Dictionary:
	var total_tiles: int = WORK_SIZE * WORK_SIZE
	var grid_class := PackedByteArray()
	grid_class.resize(total_tiles)
	grid_class.fill(TILE_VOID)

	var grid_variant := PackedByteArray()
	grid_variant.resize(total_tiles)
	grid_variant.fill(0)

	var grid_mask := PackedByteArray()
	grid_mask.resize(total_tiles)
	grid_mask.fill(0)

	var stamps_list: Array[Dictionary] = []

	var is_park := PackedByteArray()
	is_park.resize(total_tiles)
	is_park.fill(0)

	var is_forest := PackedByteArray()
	is_forest.resize(total_tiles)
	is_forest.fill(0)

	var is_cemetery := PackedByteArray()
	is_cemetery.resize(total_tiles)
	is_cemetery.fill(0)

	var is_residential := PackedByteArray()
	is_residential.resize(total_tiles)
	is_residential.fill(0)

	var water_from_waterway := PackedByteArray()
	water_from_waterway.resize(total_tiles)
	water_from_waterway.fill(0)

	var water_from_poly_or_sea := PackedByteArray()
	water_from_poly_or_sea.resize(total_tiles)
	water_from_poly_or_sea.fill(0)

	# -------------------------------------------------------------
	# 1. Base Layer (§4.1 step 1)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		var dy: int = 1 if r < 4 else (-1 if r >= 36 else 0)
		for c in WORK_SIZE:
			var dx: int = -1 if c < 4 else (1 if c >= 36 else 0)
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var idx: int = r * WORK_SIZE + c
			if n_data.get("covered", false):
				grid_class[idx] = TILE_GRASS
			else:
				grid_class[idx] = TILE_VOID

	# -------------------------------------------------------------
	# 2. Sea & Coast Layer (§4.1 step 2)
	# -------------------------------------------------------------
	var coast_segments: Array = []
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var lines: Array = n_data.get("lines", [])
			for line in lines:
				if line.get("kind", "") != "coastline":
					continue
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue
				var origin := Vector2(float(cx + dx) * Grid.CELL_WM, float(cy + dy) * Grid.CELL_WM)
				for i in range(pts.size() - 1):
					var a := origin + pts[i] * MapStore.GEOM_UNIT_WM
					var b := origin + pts[i + 1] * MapStore.GEOM_UNIT_WM
					if (b - a).length_squared() < 1e-6:
						continue
					coast_segments.append([a, b])
					incoming[_quantize_wm(b)] = a
					outgoing[_quantize_wm(a)] = b

	for r in WORK_SIZE:
		var dy: int = 1 if r < 4 else (-1 if r >= 36 else 0)
		for c in WORK_SIZE:
			var dx: int = -1 if c < 4 else (1 if c >= 36 else 0)
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var sea_val: int = int(n_data.get("sea", 0))
			var idx: int = r * WORK_SIZE + c

			if sea_val == 1:
				grid_class[idx] = TILE_WATER
				water_from_poly_or_sea[idx] = 1
			elif sea_val == 2 and not coast_segments.is_empty():
				var gx: int = cx * 32 + (c - 4)
				var gy: int = cy * 32 + (35 - r)
				var p_wm := Vector2((float(gx) + 0.5) * Grid.TILE_WM, (float(gy) + 0.5) * Grid.TILE_WM)

				var min_dist_sq := INF
				var nearest_seg = null
				var nearest_t := 0.0
				for seg in coast_segments:
					var sa: Vector2 = seg[0]
					var sb: Vector2 = seg[1]
					var ab := sb - sa
					var len_sq := ab.length_squared()
					var t := 0.0
					if len_sq > 1e-6:
						t = clampf((p_wm - sa).dot(ab) / len_sq, 0.0, 1.0)
					var proj := sa + ab * t
					var dist_sq := (p_wm - proj).length_squared()
					if dist_sq < min_dist_sq:
						min_dist_sq = dist_sq
						nearest_seg = seg
						nearest_t = t

				if nearest_seg != null:
					var na: Vector2 = nearest_seg[0]
					var nb: Vector2 = nearest_seg[1]
					var is_sea := false
					if nearest_t > 1e-4 and nearest_t < 1.0 - 1e-4:
						is_sea = (nb - na).cross(p_wm - na) < 0.0
					else:
						var v: Vector2 = na if nearest_t <= 1e-4 else nb
						var vk := _quantize_wm(v)
						if incoming.has(vk) and outgoing.has(vk):
							var u_pt: Vector2 = incoming[vk]
							var w_pt: Vector2 = outgoing[vk]
							is_sea = (w_pt - u_pt).cross(p_wm - v) < 0.0
						else:
							is_sea = (nb - na).cross(p_wm - na) < 0.0
					if is_sea:
						grid_class[idx] = TILE_WATER
						water_from_poly_or_sea[idx] = 1

	# -------------------------------------------------------------
	# 3. Land Cover Polygons (§4.1 step 3)
	# -------------------------------------------------------------
	# Group polygons by land cover type to paint in exact plan order
	var polys_by_order: Dictionary = {
		"farmland": [],
		"scrub": [],
		"forest": [],
		"park": [],
		"cemetery": [],
		"sand": [],
		"wetland": [],
		"parking": [],
		"water": [],
		"residential": []
	}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var polys: Array = n_data.get("polys", [])
			for poly in polys:
				var kind: String = poly.get("kind", "")
				if not polys_by_order.has(kind):
					continue
				var geom = poly.get("geom_rings", null)
				if geom == null:
					continue
				var rings: Array[PackedVector2Array] = []
				if geom is PackedByteArray:
					rings = MapStore.unpack_rings(geom)
				elif geom is Array:
					for r_item in geom:
						if r_item is PackedVector2Array:
							rings.append(r_item)
				if rings.is_empty():
					continue

				# Map vertices to working grid coordinates (§4.0)
				var mapped_rings: Array[PackedVector2Array] = []
				for ring in rings:
					var m_ring := PackedVector2Array()
					for pt in ring:
						var m_col: float = 4.0 + 2.0 * pt.x + 32.0 * float(dx)
						var m_row: float = 36.0 - 2.0 * pt.y - 32.0 * float(dy)
						m_ring.append(Vector2(m_col, m_row))
					mapped_rings.append(m_ring)
				polys_by_order[kind].append(mapped_rings)

	# Paint in exact order
	var order_keys := ["farmland", "scrub", "forest", "park", "cemetery", "sand", "wetland", "parking", "water", "residential"]
	for kind in order_keys:
		var list: Array = polys_by_order[kind]
		for rings in list:
			var outer: PackedVector2Array = rings[0]
			var holes: Array[PackedVector2Array] = []
			for h_i in range(1, rings.size()):
				holes.append(rings[h_i])

			var min_c := 39
			var max_c := 0
			var min_r := 39
			var max_r := 0
			for pt in outer:
				min_c = mini(min_c, floori(pt.x))
				max_c = maxi(max_c, ceili(pt.x))
				min_r = mini(min_r, floori(pt.y))
				max_r = maxi(max_r, ceili(pt.y))

			min_c = clampi(min_c, 0, 39)
			max_c = clampi(max_c, 0, 39)
			min_r = clampi(min_r, 0, 39)
			max_r = clampi(max_r, 0, 39)

			for r in range(min_r, max_r + 1):
				var py := float(r) + 0.5
				for c in range(min_c, max_c + 1):
					var px := float(c) + 0.5
					if not point_in_polygon(px, py, outer, holes):
						continue
					var idx := r * WORK_SIZE + c
					var gx := cx * 32 + (c - 4)
					var gy := cy * 32 + (35 - r)

					match kind:
						"farmland":
							grid_class[idx] = TILE_CROP if posmod(gy, 2) == 0 else TILE_GRASS
						"scrub":
							grid_class[idx] = TILE_TALL_GRASS
						"forest":
							grid_class[idx] = TILE_TREE
							is_forest[idx] = 1
						"park":
							grid_class[idx] = TILE_GRASS
							is_park[idx] = 1
						"cemetery":
							grid_class[idx] = TILE_GRASS
							is_cemetery[idx] = 1
						"sand":
							grid_class[idx] = TILE_SAND
						"wetland":
							grid_class[idx] = TILE_MARSH
						"parking":
							grid_class[idx] = TILE_PLAZA
						"water":
							grid_class[idx] = TILE_WATER
							water_from_poly_or_sea[idx] = 1
						"residential":
							is_residential[idx] = 1

	# -------------------------------------------------------------
	# 4. Lines & Crossings (§4.1 step 4)
	# -------------------------------------------------------------
	var line_groups: Dictionary = {
		"waterway": [],
		"rail": [],
		"road": [],
		"path": []
	}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var lines: Array = n_data.get("lines", [])
			for line in lines:
				var kind: String = line.get("kind", "")
				if not line_groups.has(kind):
					continue
				var subkind: String = line.get("subkind", "")
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue

				var mapped_pts := PackedVector2Array()
				for pt in pts:
					var m_col: float = 4.0 + 2.0 * pt.x + 32.0 * float(dx)
					var m_row: float = 36.0 - 2.0 * pt.y - 32.0 * float(dy)
					mapped_pts.append(Vector2(m_col, m_row))
				line_groups[kind].append({
					"subkind": subkind,
					"pts": mapped_pts
				})

	# 4a. Lines & Crossings (§4.1 step 4, §10.2 step 1)
	# Paint waterways, rail, and roads before buildings
	var line_order_pre := ["waterway", "rail", "road"]
	for kind in line_order_pre:
		var list: Array = line_groups[kind]
		for item in list:
			var subkind: String = item["subkind"]
			var pts: PackedVector2Array = item["pts"]
			var is_bridge: bool = subkind.ends_with(":bridge")

			var width: int = 1
			var target_class: int = TILE_PATH
			match kind:
				"waterway":
					width = get_waterway_width(subkind)
					target_class = TILE_WATER
				"rail":
					width = 2
					target_class = TILE_RAIL
				"road":
					width = get_road_width(subkind)
					target_class = TILE_ROAD if width >= 3 else TILE_PATH

			var lo: int = (width - 1) / 2
			var hi: int = width - 1 - lo

			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var c0: int = floori(p0.x)
				var r0: int = floori(p0.y)
				var c1: int = floori(p1.x)
				var r1: int = floori(p1.y)

				var supercover := supercover_line(c0, r0, c1, r1)
				for center in supercover:
					for br in range(center.y - lo, center.y + hi + 1):
						if br < 0 or br >= WORK_SIZE:
							continue
						for bc in range(center.x - lo, center.x + hi + 1):
							if bc < 0 or bc >= WORK_SIZE:
								continue
							var idx := br * WORK_SIZE + bc
							var current_class: int = grid_class[idx]

							if kind == "waterway":
								grid_class[idx] = TILE_WATER
								water_from_waterway[idx] = 1
							elif kind == "rail":
								if current_class == TILE_WATER or current_class == TILE_BRIDGE:
									if is_bridge:
										grid_class[idx] = TILE_BRIDGE
								else:
									grid_class[idx] = TILE_RAIL
							elif kind == "road":
								if current_class == TILE_WATER or current_class == TILE_BRIDGE:
									if is_bridge:
										grid_class[idx] = TILE_BRIDGE
									elif water_from_waterway[idx] == 1 and water_from_poly_or_sea[idx] == 0:
										# Culvert: overwrites waterway line
										grid_class[idx] = target_class
								else:
									# Road overwrites rail (level crossing) and terrain
									grid_class[idx] = target_class

	# -------------------------------------------------------------
	# 5. Buildings & Fallback Houses (§4.1 step 5, §4.2, §4.3, §10.2)
	# -------------------------------------------------------------
	var placed_buildings: Array[Dictionary] = []
	var all_doors: Array[Vector2i] = []
	var reserved_grid := PackedByteArray()
	reserved_grid.resize(WORK_SIZE * WORK_SIZE)
	reserved_grid.fill(0)
	var buildings_placed_count := 0
	var fallback_placed_count := 0

	# 5a. Real Buildings anchored in the centre cell
	var center_polys: Array = area.get(Vector2i.ZERO, {}).get("polys", [])
	var building_candidates: Array[Dictionary] = []

	for poly in center_polys:
		if poly.get("kind", "") != "building":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				rings.append(PackedVector2Array(r_item))
		if rings.is_empty() or rings[0].size() < 3:
			continue

		var outer_ring: PackedVector2Array = rings[0]
		var A: float = _shoelace_area(outer_ring) * 256.0
		if A < 60.0:
			continue # skip sheds / garages

		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for pt in outer_ring:
			min_x = minf(min_x, pt.x)
			max_x = maxf(max_x, pt.x)
			min_y = minf(min_y, pt.y)
			max_y = maxf(max_y, pt.y)

		var w_t: float = (max_x - min_x) * 2.0
		var h_t: float = (max_y - min_y) * 2.0

		var subk: String = poly.get("subkind", "")
		var w := 4
		var h := 4
		var roof_rows := 2
		var wall_rows := 2
		var template_name := "house_s"

		if A < 400.0:
			w = 4
			h = 4 # §13: 2 roof rows over 2 wall rows, like Emerald's houses
			roof_rows = 2
			wall_rows = 2
			template_name = "house_s"
		elif A < 2000.0 or subk in ["apartments", "dormitory"]:
			w = 5
			h = 4
			roof_rows = 2
			wall_rows = 2
			template_name = "house_m"
		else:
			w = clampi(int(round(w_t)), 6, 24)
			h = clampi(int(round(h_t)), 5, 14)
			roof_rows = h - 2
			wall_rows = 2
			template_name = "block_l"

		var bx_c := (min_x + max_x) * 0.5
		var by_c := (min_y + max_y) * 0.5
		var cc := 4.0 + 2.0 * bx_c
		var rc := 36.0 - 2.0 * by_c
		var col0 := clampi(int(round(cc - float(w) / 2.0)), 5, 35 - w)
		var row0 := clampi(int(round(rc - float(h) / 2.0)), 5, 35 - h)

		var gx0 := cx * 32 + (col0 - 4)
		var gy0 := cy * 32 + (35 - row0)

		var door_cols: Array[int] = []
		if template_name == "house_s":
			var d_col: int = 1 if u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) < 0.5 else 2
			door_cols = [d_col]
		elif template_name == "house_m":
			door_cols = [2]
		else:
			for off in [2, 10, 18]:
				if off < w - 1:
					door_cols.append(off)

		var roof_color := 7
		if subk in ["house", "detached", "residential", "semidetached_house", "bungalow", "terrace", "cabin", "farm", "hut", "apartments", "dormitory"] or (subk == "yes" and template_name in ["house_s", "house_m"]):
			roof_color = floori(u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) * 4.0)
		elif subk in ["retail", "commercial", "supermarket", "shop", "kiosk"]:
			roof_color = 4
		elif subk in ["school", "college", "university", "kindergarten", "public", "civic", "government", "library", "townhall", "fire_station", "police"]:
			roof_color = 5
		elif subk in ["hospital", "clinic"]:
			roof_color = 6
		elif subk in ["church", "chapel", "cathedral", "temple", "mosque", "synagogue", "religious"]:
			roof_color = 3
		else:
			roof_color = 7

		building_candidates.append({
			"area": A,
			"col0": col0,
			"row0": row0,
			"cc": cc,
			"rc": rc,
			"w": w,
			"h": h,
			"roof_rows": roof_rows,
			"door_cols": door_cols,
			"roof_color": roof_color,
			"template": template_name,
			"subkind": subk,
			"bx_c": bx_c,
			"by_c": by_c,
			"rings": rings
		})

	var total_building_candidates: int = building_candidates.size()
	var landmarks_placed_count := 0
	var landmarks_sign_only_count := 0
	var landmark_ids_placed: Array[String] = []
	var landmark_sign_specs: Array[Dictionary] = []

	# -------------------------------------------------------------
	# 5a-0. Landmarks First (§11.1 + §11.1a, Item 24)
	# -------------------------------------------------------------
	# Collect footprints from all 9 cells in offset order (dy, then dx, from -1 to 1),
	# shifted by (16*dx, 16*dy) store units into the centre cell's frame (§11.1a step 2).
	var neigh_footprints: Array[Dictionary] = []
	var used_neigh_footprints: Dictionary = {}
	var used_candidate_indices: Dictionary = {}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var off := Vector2i(dx, dy)
			if off == Vector2i.ZERO:
				for c_idx in building_candidates.size():
					var cand: Dictionary = building_candidates[c_idx]
					neigh_footprints.append({
						"offset": Vector2i.ZERO,
						"center_idx": c_idx,
						"area": float(cand["area"]),
						"outer_ring": cand["rings"][0]
					})
			else:
				var shift_su := Vector2(16.0 * float(dx), 16.0 * float(dy))
				var n_polys: Array = area.get(off, {}).get("polys", [])
				for poly in n_polys:
					if poly.get("kind", "") != "building":
						continue
					var geom = poly.get("geom_rings", null)
					if geom == null:
						continue
					var rings: Array[PackedVector2Array] = []
					if geom is PackedByteArray:
						rings = MapStore.unpack_rings(geom)
					elif geom is Array:
						for r_item in geom:
							rings.append(PackedVector2Array(r_item))
					if rings.is_empty() or rings[0].size() < 3:
						continue
					var outer_ring: PackedVector2Array = rings[0]
					var A_n: float = _shoelace_area(outer_ring) * 256.0
					if A_n < 60.0:
						continue
					var shifted_ring := PackedVector2Array()
					shifted_ring.resize(outer_ring.size())
					for p_i in outer_ring.size():
						shifted_ring[p_i] = outer_ring[p_i] + shift_su
					neigh_footprints.append({
						"offset": off,
						"center_idx": -1,
						"area": A_n,
						"outer_ring": shifted_ring
					})

	# Collect landmarks from all 9 cells in offset order (dy, then dx, from -1 to 1), then list order
	var all_landmarks: Array[Dictionary] = []
	var seen_lm_ids: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var off := Vector2i(dx, dy)
			var cell_lms: Array = area.get(off, {}).get("landmarks", [])
			for lm_item in cell_lms:
				var lm_id: String = str(lm_item.get("id", ""))
				var dedup_key: String = lm_id if not lm_id.is_empty() else str(lm_item.get("name", "")) + ":" + str(lm_item.get("door_wm", Vector2.ZERO))
				if seen_lm_ids.has(dedup_key):
					continue
				seen_lm_ids[dedup_key] = true
				all_landmarks.append({
					"lm": lm_item,
					"door_offset": off
				})

	var cell_origin_wm := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
	var in_landmark_stamp_box := PackedByteArray()
	in_landmark_stamp_box.resize(total_tiles)
	in_landmark_stamp_box.fill(0)

	for entry in all_landmarks:
		var lm: Dictionary = entry["lm"]
		var door_offset: Vector2i = entry["door_offset"]
		var lm_id: String = str(lm.get("id", ""))
		var lm_name: String = str(lm.get("name", ""))
		var door_wm: Vector2 = lm.get("door_wm", Vector2.ZERO)
		var door_su: Vector2 = (door_wm - cell_origin_wm) / MapStore.GEOM_UNIT_WM
		var door_gx: int = int(floor(door_wm.x / Grid.TILE_WM))
		var door_gy: int = int(floor(door_wm.y / Grid.TILE_WM))
		var door_c: int = door_gx - cx * 32 + 4
		var door_r: int = 35 - (door_gy - cy * 32)

		var matched_nf_idx := -1
		# First: candidate whose outer ring contains the door point
		# Ties go to the larger A, then the lower (dy, dx) offset (§11.1a step 2)
		var best_inside_area := -1.0
		var best_inside_off := Vector2i(99, 99)
		for nf_i in neigh_footprints.size():
			if used_neigh_footprints.has(nf_i):
				continue
			var nf: Dictionary = neigh_footprints[nf_i]
			var outer_ring: PackedVector2Array = nf["outer_ring"]
			if _point_in_ring(door_su.x, door_su.y, outer_ring):
				var c_area: float = float(nf["area"])
				var c_off: Vector2i = nf["offset"]
				var better := false
				if c_area > best_inside_area + 1e-5:
					better = true
				elif absf(c_area - best_inside_area) <= 1e-5:
					if c_off.y < best_inside_off.y or (c_off.y == best_inside_off.y and c_off.x < best_inside_off.x):
						better = true
				if better:
					best_inside_area = c_area
					best_inside_off = c_off
					matched_nf_idx = nf_i

		# Else: candidate whose outer ring passes within 2 store units (32 WM-m, 4 tiles) of door point
		# — nearest first, ties to the larger A, then the lower (dy, dx) offset
		if matched_nf_idx == -1:
			var best_dist := INF
			var best_near_area := -1.0
			var best_near_off := Vector2i(99, 99)
			for nf_i in neigh_footprints.size():
				if used_neigh_footprints.has(nf_i):
					continue
				var nf: Dictionary = neigh_footprints[nf_i]
				var outer_ring: PackedVector2Array = nf["outer_ring"]
				var d_su: float = _point_to_ring_dist_su(door_su, outer_ring)
				if d_su <= 2.0 + 1e-5:
					var c_area: float = float(nf["area"])
					var c_off: Vector2i = nf["offset"]
					var better := false
					if d_su < best_dist - 1e-5:
						better = true
					elif absf(d_su - best_dist) <= 1e-5:
						if c_area > best_near_area + 1e-5:
							better = true
						elif absf(c_area - best_near_area) <= 1e-5:
							if c_off.y < best_near_off.y or (c_off.y == best_near_off.y and c_off.x < best_near_off.x):
								better = true
					if better:
						best_dist = d_su
						best_near_area = c_area
						best_near_off = c_off
						matched_nf_idx = nf_i

		# Landmark set-piece placement (§12.3, §14.3, F68 a-f)
		var lm_stamp_id: int = get_landmark_stamp_id(lm_id)
		if lm_stamp_id >= 0:
			var s_def: Dictionary = get_stamp_def(lm_stamp_id)
			var s_res: Dictionary = _resolve_landmark_stamp(door_wm, s_def, cx, cy, area)
			if bool(s_res.get("placed", false)):
				if matched_nf_idx != -1:
					used_neigh_footprints[matched_nf_idx] = true
					var matched_nf_s: Dictionary = neigh_footprints[matched_nf_idx]
					if matched_nf_s["offset"] == Vector2i.ZERO:
						used_candidate_indices[int(matched_nf_s["center_idx"])] = true

				var agx: int = int(s_res["anchor_gx"])
				var agy: int = int(s_res["anchor_gy"])
				var sw: int = int(s_def["w"])
				var sh: int = int(s_def["h"])
				var base_rows: int = int(s_def["base_rows"])
				var tiles_map: Array = s_def["tiles"]
				var door_arr = s_def.get("door", null)
				var has_door: bool = (door_arr is Array and door_arr.size() >= 2)
				var d_col: int = int(door_arr[0]) if has_door else (sw / 2)
				var d_row: int = int(door_arr[1]) if has_door else (sh - 1)
				var door_tile_gx: int = agx + d_col
				var door_tile_gy: int = agy + d_row

				var cell_c0: int = cx * 32
				var cell_r0: int = (-cy - 1) * 32

				# Suppress any ordinary building candidate overlapping the stamp's W x H box or the tile south of its door (§14.3.5 rule 5, F68 e)
				for c_idx in building_candidates.size():
					if used_candidate_indices.has(c_idx):
						continue
					var bc: Dictionary = building_candidates[c_idx]
					var bc_c0: int = cell_c0 + (int(bc["col0"]) - 4)
					var bc_c1: int = bc_c0 + int(bc["w"]) - 1
					var bc_r0: int = cell_r0 + (int(bc["row0"]) - 4)
					var bc_r1: int = bc_r0 + int(bc["h"]) - 1
					if bc_c1 >= agx and bc_c0 < agx + sw and bc_r1 >= agy and bc_r0 < agy + sh:
						used_candidate_indices[c_idx] = true
					elif has_door and door_tile_gx >= bc_c0 and door_tile_gx <= bc_c1 and (door_tile_gy + 1) >= bc_r0 and (door_tile_gy + 1) <= bc_r1:
						used_candidate_indices[c_idx] = true

				for ty in sh:
					var r: int = (agy + ty) - cell_r0 + 4
					if r < 0 or r >= WORK_SIZE:
						continue
					var row_str: String = str(tiles_map[ty])
					for tx in sw:
						var c: int = (agx + tx) - cell_c0 + 4
						if c < 0 or c >= WORK_SIZE:
							continue
						var idx: int = r * WORK_SIZE + c
						reserved_grid[idx] = 1
						in_landmark_stamp_box[idx] = 1
						var ch: String = row_str[tx]
						if has_door and tx == d_col and ty == d_row:
							grid_class[idx] = TILE_DOOR
							grid_variant[idx] = 32
							grid_mask[idx] = lm_stamp_id
							if c >= WORK_CELL_START and c < WORK_CELL_END and r >= WORK_CELL_START and r < WORK_CELL_END:
								all_doors.append(Vector2i(c, r))
						elif ch == "#":
							grid_class[idx] = TILE_STAMP
							grid_variant[idx] = lm_stamp_id
							grid_mask[idx] = STAMP_FLAG_SOLID
						elif ch == "+":
							grid_class[idx] = TILE_STAMP
							grid_variant[idx] = lm_stamp_id
							grid_mask[idx] = 0 if ty >= sh - base_rows else STAMP_FLAG_OVERHANG

				if has_door:
					var sc: int = door_tile_gx - cell_c0 + 4
					var sr: int = (door_tile_gy + 1) - cell_r0 + 4
					if sc >= 0 and sc < WORK_SIZE and sr >= 0 and sr < WORK_SIZE:
						reserved_grid[sr * WORK_SIZE + sc] = 1
						in_landmark_stamp_box[sr * WORK_SIZE + sc] = 1

				if agx + sw > cell_c0 and agx < cell_c0 + 32 and agy + sh > cell_r0 and agy < cell_r0 + 32:
					var out_agy: int = (cy * 32 + (agy - cell_r0)) if _use_legacy_item33_anchor_frame else agy
					stamps_list.append({
						"stamp_id": lm_stamp_id,
						"anchor_gx": agx,
						"anchor_gy": out_agy,
						"w": sw,
						"h": sh
					})

				if has_door and door_tile_gx >= cell_c0 and door_tile_gx < cell_c0 + 32 and door_tile_gy >= cell_r0 and door_tile_gy < cell_r0 + 32 and landmarks_placed_count < 4:
					buildings_placed_count += 1
					landmarks_placed_count += 1
					if not lm_id.is_empty():
						landmark_ids_placed.append(lm_id)
					var lm_door_c_s: int = door_tile_gx - cell_c0 + 4
					var lm_door_r_s: int = door_tile_gy - cell_r0 + 4
					placed_buildings.append({
						"col0": lm_door_c_s,
						"row0": lm_door_r_s,
						"w": 1,
						"h": 1,
						"door_cols": [0],
						"is_landmark": true
					})
					landmark_sign_specs.append({
						"name": lm_name,
						"is_building": true,
						"door_pos": Vector2i(lm_door_c_s, lm_door_r_s)
					})
				continue

		if matched_nf_idx == -1:
			# If no footprint is found anywhere and the door lies in the centre cell, place the sign only (§11.1a step 2)
			if door_offset == Vector2i.ZERO and landmarks_placed_count + landmarks_sign_only_count < 4:
				landmarks_sign_only_count += 1
				landmark_sign_specs.append({
					"name": lm_name,
					"is_building": false,
					"door_pos": Vector2i(door_c, door_r)
				})
			continue

		used_neigh_footprints[matched_nf_idx] = true
		var chosen_nf: Dictionary = neigh_footprints[matched_nf_idx]
		if chosen_nf["offset"] != Vector2i.ZERO:
			# Anchored in another cell: do nothing here — that cell places it (§11.1a step 2)
			continue

		if landmarks_placed_count >= 4:
			continue

		var matched_idx: int = int(chosen_nf["center_idx"])
		var lb: Dictionary = building_candidates[matched_idx]
		var orig_w: int = lb["w"]
		var orig_h: int = lb["h"]
		var orig_t: String = lb["template"]
		var cc: float = lb["cc"]
		var rc: float = lb["rc"]

		# Build shrink sequence (§11.1 step 2):
		# original -> (w-2, h-2) down to 6x5 for block_l -> house_m (5x4) -> house_s (4x4)
		var size_attempts: Array[Dictionary] = []
		size_attempts.append({
			"w": orig_w,
			"h": orig_h,
			"roof_rows": lb["roof_rows"],
			"template": orig_t
		})
		if orig_t == "block_l":
			var cur_w: int = orig_w
			var cur_h: int = orig_h
			while cur_w > 6 or cur_h > 5:
				var next_w: int = maxi(6, cur_w - 2)
				var next_h: int = maxi(5, cur_h - 2)
				if next_w == cur_w and next_h == cur_h:
					break
				cur_w = next_w
				cur_h = next_h
				size_attempts.append({
					"w": cur_w,
					"h": cur_h,
					"roof_rows": cur_h - 2,
					"template": "block_l"
				})
			size_attempts.append({"w": 5, "h": 4, "roof_rows": 2, "template": "house_m"})
			size_attempts.append({"w": 4, "h": 4, "roof_rows": 2, "template": "house_s"})
		elif orig_t == "house_m":
			size_attempts.append({"w": 4, "h": 4, "roof_rows": 2, "template": "house_s"})

		var lm_placed := false
		var chosen_col0 := 0
		var chosen_row0 := 0
		var chosen_w := orig_w
		var chosen_h := orig_h
		var chosen_roof_rows: int = lb["roof_rows"]
		var chosen_t := orig_t

		for attempt in size_attempts:
			var aw: int = attempt["w"]
			var ah: int = attempt["h"]
			var base_col0: int = clampi(int(round(cc - float(aw) / 2.0)), 5, 35 - aw)
			var base_row0: int = clampi(int(round(rc - float(ah) / 2.0)), 5, 35 - ah)
			for nudge in LANDMARK_NUDGE_OFFSETS:
				var test_col: int = clampi(base_col0 + nudge.x, 5, 35 - aw)
				var test_row: int = clampi(base_row0 + nudge.y, 5, 35 - ah)
				if _can_place_template(test_col, test_row, aw, ah, grid_class, reserved_grid, true):
					chosen_col0 = test_col
					chosen_row0 = test_row
					chosen_w = aw
					chosen_h = ah
					chosen_roof_rows = attempt["roof_rows"]
					chosen_t = attempt["template"]
					lm_placed = true
					break
			if lm_placed:
				break

		if not lm_placed:
			landmarks_sign_only_count += 1
			landmark_sign_specs.append({
				"name": lm_name,
				"is_building": false,
				"door_pos": Vector2i(door_c, door_r)
			})
			continue

		# Placed landmark leaves the ordinary candidate list (§11.1 step 2)
		used_candidate_indices[matched_idx] = true
		buildings_placed_count += 1
		landmarks_placed_count += 1
		if not lm_id.is_empty():
			landmark_ids_placed.append(lm_id)

		var gx0_lm: int = cx * 32 + (chosen_col0 - 4)
		var gy0_lm: int = cy * 32 + (35 - chosen_row0)
		var cand_door_cols := _template_door_cols(chosen_t, chosen_w, gx0_lm, gy0_lm, world_seed)
		# Its door is the template door column nearest the real door point's column (§11.1 step 2)
		var best_door_col: int = cand_door_cols[0]
		var best_col_diff: int = absi((chosen_col0 + best_door_col) - door_c)
		for d_off in cand_door_cols:
			var diff: int = absi((chosen_col0 + d_off) - door_c)
			if diff < best_col_diff:
				best_col_diff = diff
				best_door_col = d_off

		# Gild at placement time: ROOF 32, WALL 32 or 40, DOOR 32 (§11.1 step 3)
		for tr in chosen_h:
			var r: int = chosen_row0 + tr
			for tc in chosen_w:
				var c: int = chosen_col0 + tc
				var idx: int = r * WORK_SIZE + c
				if tr < chosen_roof_rows:
					grid_class[idx] = TILE_ROOF
					grid_variant[idx] = 32
				else:
					if tr == chosen_h - 1 and tc == best_door_col:
						grid_class[idx] = TILE_DOOR
						grid_variant[idx] = 32
						all_doors.append(Vector2i(c, r))
					else:
						grid_class[idx] = TILE_WALL
						var has_window: bool = (tc % 2 != 0)
						grid_variant[idx] = 40 if has_window else 32

		for tc in chosen_w:
			var s_idx: int = (chosen_row0 + chosen_h) * WORK_SIZE + (chosen_col0 + tc)
			reserved_grid[s_idx] = 1

		placed_buildings.append({
			"col0": chosen_col0,
			"row0": chosen_row0,
			"w": chosen_w,
			"h": chosen_h,
			"door_cols": [best_door_col],
			"is_landmark": true
		})

		var lm_door_r: int = chosen_row0 + chosen_h - 1
		var lm_door_c: int = chosen_col0 + best_door_col
		landmark_sign_specs.append({
			"name": lm_name,
			"is_building": true,
			"door_pos": Vector2i(lm_door_c, lm_door_r)
		})

	# Remove placed landmarks from ordinary candidate list
	var remaining_candidates: Array[Dictionary] = []
	for c_idx in building_candidates.size():
		if not used_candidate_indices.has(c_idx):
			remaining_candidates.append(building_candidates[c_idx])

	# Order: descending A, then ascending row0, then ascending col0
	remaining_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["area"], b["area"]):
			return a["area"] > b["area"]
		if a["row0"] != b["row0"]:
			return a["row0"] < b["row0"]
		return a["col0"] < b["col0"]
	)

	for b in remaining_candidates:
		var base_col0: int = b["col0"]
		var base_row0: int = b["row0"]
		var w: int = b["w"]
		var h: int = b["h"]

		var placed := false
		var chosen_col0 := base_col0
		var chosen_row0 := base_row0

		for nudge in NUDGE_OFFSETS:
			var test_col: int = clampi(base_col0 + nudge.x, 5, 35 - w)
			var test_row: int = clampi(base_row0 + nudge.y, 5, 35 - h)
			if _can_place_template(test_col, test_row, w, h, grid_class, reserved_grid):
				chosen_col0 = test_col
				chosen_row0 = test_row
				placed = true
				break

		if not placed:
			continue

		buildings_placed_count += 1

		# Paint building
		for tr in h:
			var r: int = chosen_row0 + tr
			for tc in w:
				var c: int = chosen_col0 + tc
				var idx: int = r * WORK_SIZE + c
				if tr < b["roof_rows"]:
					grid_class[idx] = TILE_ROOF
					grid_variant[idx] = b["roof_color"]
				else:
					if tr == h - 1 and tc in b["door_cols"]:
						grid_class[idx] = TILE_DOOR
						grid_variant[idx] = b["roof_color"]
						all_doors.append(Vector2i(c, r))
					else:
						grid_class[idx] = TILE_WALL
						var has_window: bool = (tc % 2 != 0)
						grid_variant[idx] = b["roof_color"] + (8 if has_window else 0)

		# Mark south ring row reserved (§10.2 step 3)
		for tc in w:
			var s_idx: int = (chosen_row0 + h) * WORK_SIZE + (chosen_col0 + tc)
			reserved_grid[s_idx] = 1

		placed_buildings.append({
			"col0": chosen_col0,
			"row0": chosen_row0,
			"w": w,
			"h": h,
			"door_cols": b["door_cols"],
			"template": b["template"],
			"subkind": b["subkind"],
			"is_landmark": false
		})

	# 5b. Fallback Houses (§4.3, §10.2 step 5)
	for poly in center_polys:
		var p_kind: String = poly.get("kind", "")
		if p_kind != "residential" and p_kind != "commercial":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var f_rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			f_rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				f_rings.append(PackedVector2Array(r_item))
		if f_rings.is_empty():
			continue

		var has_real_building := false
		for b in building_candidates:
			if _point_in_rings(Vector2(b["bx_c"], b["by_c"]), f_rings):
				has_real_building = true
				break
		if has_real_building:
			continue

		# Candidate house_s on global lattice: posmod(gx, 7) == 0 and posmod(gy, 6) == 0
		for r in range(4, 36):
			for c in range(4, 36):
				var gx: int = cx * 32 + (c - 4)
				var gy: int = cy * 32 + (35 - r)
				if posmod(gx, 7) == 0 and posmod(gy, 6) == 0:
					var base_col0: int = clampi(c, 5, 31)
					var base_row0: int = clampi(r, 5, 31)
					# Template centre tile in store units (house_s is 4x4 -> col0 + 2, row0 + 2)
					var tc_su := Vector2((float(base_col0 + 2) + 0.5 - 4.0) * 0.5, (36.0 - (float(base_row0 + 2) + 0.5)) * 0.5)
					if not _point_in_rings(tc_su, f_rings):
						continue
					if u_rand(gx, gy, world_seed, SALT_FALLBACK_SKIP) >= 0.70:
						continue

					var f_placed := false
					var chosen_col0 := base_col0
					var chosen_row0 := base_row0

					for nudge in NUDGE_OFFSETS:
						var test_col: int = clampi(base_col0 + nudge.x, 5, 31)
						var test_row: int = clampi(base_row0 + nudge.y, 5, 31)
						if _can_place_template(test_col, test_row, 4, 4, grid_class, reserved_grid):
							chosen_col0 = test_col
							chosen_row0 = test_row
							f_placed = true
							break

					if not f_placed:
						continue

					fallback_placed_count += 1

					var gx0: int = cx * 32 + (chosen_col0 - 4)
					var gy0: int = cy * 32 + (35 - chosen_row0)
					var roof_color: int = 4 if p_kind == "commercial" else floori(u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) * 4.0)
					var door_col: int = 1 if u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) < 0.5 else 2

					for tr in 4:
						var cur_r: int = chosen_row0 + tr
						for tc in 4:
							var cur_c: int = chosen_col0 + tc
							var idx: int = cur_r * WORK_SIZE + cur_c
							if tr < 2:
								grid_class[idx] = TILE_ROOF
								grid_variant[idx] = roof_color
							else:
								if tr == 3 and tc == door_col:
									grid_class[idx] = TILE_DOOR
									grid_variant[idx] = roof_color
									all_doors.append(Vector2i(cur_c, cur_r))
								else:
									grid_class[idx] = TILE_WALL
									var has_window: bool = (tc % 2 != 0)
									grid_variant[idx] = roof_color + (8 if has_window else 0)

					for tc in 4:
						var s_idx: int = (chosen_row0 + 4) * WORK_SIZE + (chosen_col0 + tc)
						reserved_grid[s_idx] = 1

					placed_buildings.append({
						"col0": chosen_col0,
						"row0": chosen_row0,
						"w": 4,
						"h": 4,
						"door_cols": [door_col],
						"template": "house_s",
						"subkind": p_kind,
						"is_landmark": false
					})

	# -------------------------------------------------------------
	# 5d. The Ruin Pass (§11.2, Decision 30, Item 25)
	# -------------------------------------------------------------
	var band := "mid"
	if area.has("waypost_wm") and area["waypost_wm"] is Vector2:
		var wp_wm: Vector2 = area["waypost_wm"]
		var cell_center_ll := Grid.cell_center_latlon(Vector2i(cx, cy))
		var wp_ll := Grid.wm_to_latlon(wp_wm)
		var dist_m: float = Grid.ground_distance_m(cell_center_ll.x, cell_center_ll.y, wp_ll.x, wp_ll.y)
		if dist_m < 600.0:
			band = "camp"
		elif dist_m < 1500.0:
			band = "near"
		elif dist_m < 3000.0:
			band = "mid"
		else:
			band = "far"

	var ordinary_standing := 0
	var ordinary_ruined := 0
	var ordinary_gone := 0
	var surviving_buildings: Array[Dictionary] = []

	for b in placed_buildings:
		if b.get("is_landmark", false):
			surviving_buildings.append(b)
			continue

		var b_col0: int = b["col0"]
		var b_row0: int = b["row0"]
		var b_w: int = b["w"]
		var b_h: int = b["h"]
		var b_t: String = b.get("template", "house_s")
		var b_sub: String = b.get("subkind", "")
		var gx0: int = cx * 32 + (b_col0 - 4)
		var gy0: int = cy * 32 + (35 - b_row0)

		var fate := "standing"
		if b_sub in ["church", "chapel", "cathedral", "temple", "mosque", "synagogue", "religious"]:
			fate = "standing"
		elif b_sub in ["hospital", "clinic"] or b_sub == "ruins":
			fate = "ruined"
		else:
			var s_share := 35.0
			var r_share := 30.0
			if b_t == "block_l":
				match band:
					"camp":
						s_share = 85.0
						r_share = 15.0
					"near":
						s_share = 75.0
						r_share = 20.0
					"mid":
						s_share = 70.0
						r_share = 22.0
					"far":
						s_share = 65.0
						r_share = 25.0
			else:
				match band:
					"camp":
						s_share = 70.0
						r_share = 20.0
					"near":
						s_share = 50.0
						r_share = 30.0
					"mid":
						s_share = 35.0
						r_share = 30.0
					"far":
						s_share = 25.0
						r_share = 30.0

			var f_val: float = u_rand(gx0, gy0, world_seed, SALT_BUILDING_FATE)
			if f_val < s_share / 100.0:
				fate = "standing"
			elif f_val < (s_share + r_share) / 100.0:
				fate = "ruined"
			else:
				fate = "gone"

		b["fate"] = fate
		if fate == "standing":
			ordinary_standing += 1
			surviving_buildings.append(b)
		elif fate == "ruined":
			ordinary_ruined += 1
			surviving_buildings.append(b)
			# Drawing a ruined building with whole-building sprites (§14.1.1, §14.1.2, §14.1.5):
			var c_draw: float = u_rand(gx0, gy0, world_seed, SALT_RUIN_COLOURWAY)
			var roof_col := 0
			if c_draw < 0.40:
				roof_col = 0
			elif c_draw < 0.60:
				roof_col = 1
			elif c_draw < 0.80:
				roof_col = 2
			else:
				roof_col = 3

			if b_t == "block_l":
				# Ruined block_l -> Place whole ruined blocks by size (Item 38, Decision 52, §14.1.5):
				# Consider every chosen whole drawing with w <= W and h <= H, plus Item 33c's cropped section min(W, 8) x min(H, 7).
				# Take the largest area; on a tie, prefer a whole drawing over the section, then the wider one.
				var sec_w: int = mini(b_w, 8)
				var sec_h: int = mini(b_h, 7)
				var best_area: int = sec_w * sec_h
				var best_is_whole := false
				var best_sid_a := 42
				var best_sid_b := 42
				var whole_specs: Array = [
					{"w": 8, "h": 7, "sid_a": 42, "sid_b": 60},
					{"w": 6, "h": 11, "sid_a": 61, "sid_b": 62},
					{"w": 9, "h": 9, "sid_a": 63, "sid_b": 64},
					{"w": 11, "h": 13, "sid_a": 65, "sid_b": 66},
					{"w": 16, "h": 14, "sid_a": 67, "sid_b": 68},
					{"w": 23, "h": 14, "sid_a": 69, "sid_b": 70},
				]
				for ws in whole_specs:
					var ww: int = int(ws["w"])
					var wh: int = int(ws["h"])
					if ww <= b_w and wh <= b_h:
						var w_area: int = ww * wh
						var better := false
						if w_area > best_area:
							better = true
						elif w_area == best_area:
							if not best_is_whole or ww > sec_w:
								better = true
						if better:
							sec_w = ww
							sec_h = wh
							best_area = w_area
							best_is_whole = true
							best_sid_a = int(ws["sid_a"])
							best_sid_b = int(ws["sid_b"])

				var chosen_sid: int = 42
				if best_is_whole:
					var is_design_a: bool = u_rand(gx0, gy0, world_seed, SALT_BLOCK_DESIGN) < 0.50
					chosen_sid = best_sid_a if is_design_a else best_sid_b
				var sec_row0: int = b_row0 + (b_h - sec_h)
				var new_door_cols: Array[int] = []
				if best_is_whole:
					var def_dcols: Array = STAMP_TABLE[chosen_sid].get("door_cols", [])
					for dc_val in def_dcols:
						new_door_cols.append(int(dc_val))
				else:
					new_door_cols = [3]
					if sec_w >= 7:
						new_door_cols.append(4)
				for old_d_col in b["door_cols"]:
					all_doors.erase(Vector2i(b_col0 + old_d_col, b_row0 + b_h - 1))
				for nd_col in new_door_cols:
					var bl_door_pos := Vector2i(b_col0 + nd_col, b_row0 + b_h - 1)
					if not all_doors.has(bl_door_pos):
						all_doors.append(bl_door_pos)
				b["door_cols"] = new_door_cols

				var lot_tiles: Array[Vector2i] = []
				for tr in b_h:
					var r: int = b_row0 + tr
					for tc in b_w:
						var c: int = b_col0 + tc
						var idx: int = r * WORK_SIZE + c
						if tc < sec_w and tr >= b_h - sec_h:
							if tr == b_h - 1 and tc in new_door_cols:
								grid_class[idx] = TILE_DOOR
								grid_variant[idx] = 16 + roof_col
								grid_mask[idx] = chosen_sid
							else:
								grid_class[idx] = TILE_STAMP
								grid_variant[idx] = chosen_sid
								grid_mask[idx] = STAMP_FLAG_SOLID
						else:
							var gx: int = cx * 32 + (c - 4)
							var gy: int = cy * 32 + (35 - r)
							if u_rand(gx, gy, world_seed, SALT_YARD_LOT_GRASS) < 0.60:
								grid_class[idx] = TILE_TALL_GRASS
								grid_variant[idx] = 0
							else:
								grid_class[idx] = TILE_GRASS
								grid_variant[idx] = 0
							grid_mask[idx] = 0
							lot_tiles.append(Vector2i(tc, tr))

				if b_col0 + sec_w > WORK_CELL_START and b_col0 < WORK_CELL_END and sec_row0 + sec_h > WORK_CELL_START and sec_row0 < WORK_CELL_END:
					stamps_list.append({
						"stamp_id": chosen_sid,
						"anchor_gx": cx * 32 + (b_col0 - 4),
						"anchor_gy": _cell_row0(cy) + (sec_row0 - 4),
						"w": sec_w,
						"h": sec_h
					})

				var lot_len: int = lot_tiles.size()
				if lot_len > 0:
					var lot_decal_count: int = mini(lot_len, maxi(2, int(floor(float(lot_len) / 8.0))))
					var taken_lot_k: Dictionary = {}
					for i in lot_decal_count:
						var k: int = int(floor(u_rand(gx0 + i * 7, gy0 + i * 11, world_seed, SALT_DECAL_POS) * float(lot_len)))
						var placed_k := -1
						for _step in lot_len:
							if not taken_lot_k.has(k):
								taken_lot_k[k] = true
								placed_k = k
								break
							k = (k + 1) % lot_len
						if placed_k >= 0:
							var lt: Vector2i = lot_tiles[placed_k]
							var dc: int = b_col0 + lt.x
							var dr: int = b_row0 + lt.y
							var d_idx: int = dr * WORK_SIZE + dc
							var d_sid: int = 43 + int(floor(u_rand(gx0 + i * 13, gy0 + i * 17, world_seed, SALT_DECAL_COUNT) * 15.0))
							var d_mask: int = STAMP_FLAG_SOLID if (d_sid == 47 or d_sid == 57) else 0
							grid_class[d_idx] = TILE_STAMP
							grid_variant[d_idx] = d_sid
							grid_mask[d_idx] = d_mask
							if dc >= WORK_CELL_START and dc < WORK_CELL_END and dr >= WORK_CELL_START and dr < WORK_CELL_END:
								stamps_list.append({
									"stamp_id": d_sid,
									"anchor_gx": cx * 32 + (dc - 4),
									"anchor_gy": _cell_row0(cy) + (dr - 4),
									"w": 1,
									"h": 1
								})
			else:
				var state_b_thresh := 0.75
				match band:
					"camp":
						state_b_thresh = 0.20
					"near":
						state_b_thresh = 0.50
					"mid":
						state_b_thresh = 0.75
					"far":
						state_b_thresh = 0.90
				var is_state_b: bool = u_rand(gx0, gy0, world_seed, SALT_RUIN_STATE) < state_b_thresh
				var d_col: int = int(b["door_cols"][0]) if not b["door_cols"].is_empty() else 1
				var stamp_id := 15
				if b_t == "house_m":
					stamp_id = (35 if is_state_b else 31) + roof_col
					d_col = 2
				else:
					if d_col == 2:
						stamp_id = (27 if is_state_b else 19) + roof_col
					else:
						stamp_id = (23 if is_state_b else 15) + roof_col

				for tr in b_h:
					var r: int = b_row0 + tr
					for tc in b_w:
						var c: int = b_col0 + tc
						var idx: int = r * WORK_SIZE + c
						if tc == d_col and tr == b_h - 1:
							grid_class[idx] = TILE_DOOR
							grid_variant[idx] = 16 + roof_col
							grid_mask[idx] = stamp_id
						else:
							grid_class[idx] = TILE_STAMP
							grid_variant[idx] = stamp_id
							grid_mask[idx] = STAMP_FLAG_SOLID
				if b_col0 + b_w > WORK_CELL_START and b_col0 < WORK_CELL_END and b_row0 + b_h > WORK_CELL_START and b_row0 < WORK_CELL_END:
					stamps_list.append({
						"stamp_id": stamp_id,
						"anchor_gx": cx * 32 + (b_col0 - 4),
						"anchor_gy": _cell_row0(cy) + (b_row0 - 4),
						"w": b_w,
						"h": b_h
					})

			# 3. One RUBBLE (variant 0) on the first GRASS tile of the template's east ring column,
			# else its west ring column, scanning top to bottom
			var rubble_ring_placed := false
			var east_c: int = b_col0 + b_w
			if east_c >= 0 and east_c < WORK_SIZE:
				for r in range(b_row0, b_row0 + b_h):
					if r >= 0 and r < WORK_SIZE:
						var e_idx: int = r * WORK_SIZE + east_c
						if grid_class[e_idx] == TILE_GRASS and in_landmark_stamp_box[e_idx] == 0:
							grid_class[e_idx] = TILE_RUBBLE
							grid_variant[e_idx] = 0
							rubble_ring_placed = true
							break
			if not rubble_ring_placed:
				var west_c: int = b_col0 - 1
				if west_c >= 0 and west_c < WORK_SIZE:
					for r in range(b_row0, b_row0 + b_h):
						if r >= 0 and r < WORK_SIZE:
							var w_idx: int = r * WORK_SIZE + west_c
							if grid_class[w_idx] == TILE_GRASS and in_landmark_stamp_box[w_idx] == 0:
								grid_class[w_idx] = TILE_RUBBLE
								grid_variant[w_idx] = 0
								break

			# 4. GRASS tiles within 1 tile of the template (Chebyshev) become TALL_GRASS where u(gx, gy, 11) < 0.50
			for r in range(b_row0 - 1, b_row0 + b_h + 1):
				if r < 0 or r >= WORK_SIZE:
					continue
				for c in range(b_col0 - 1, b_col0 + b_w + 1):
					if c < 0 or c >= WORK_SIZE:
						continue
					var idx: int = r * WORK_SIZE + c
					if grid_class[idx] == TILE_GRASS:
						var gx: int = cx * 32 + (c - 4)
						var gy: int = cy * 32 + (35 - r)
						if u_rand(gx, gy, world_seed, SALT_YARD_LOT_GRASS) < 0.50:
							grid_class[idx] = TILE_TALL_GRASS
							grid_variant[idx] = 0
		else:
			ordinary_gone += 1
			# Drawing a gone building (§14.1.3, §14.1.4, §14.1.5 rule 4):
			# 1. Remove its doors from all_doors
			for d_col in b["door_cols"]:
				var d_pos := Vector2i(b_col0 + d_col, b_row0 + b_h - 1)
				all_doors.erase(d_pos)

			var state_c_thresh := 0.25
			match band:
				"camp":
					state_c_thresh = 0.60
				"near":
					state_c_thresh = 0.40
				"mid":
					state_c_thresh = 0.25
				"far":
					state_c_thresh = 0.10
			var is_state_c: bool = (b_t != "block_l") and (u_rand(gx0, gy0, world_seed, SALT_GONE_STATE) < state_c_thresh)

			if is_state_c:
				var d_col: int = int(b["door_cols"][0]) if not b["door_cols"].is_empty() else 1
				var stamp_id := 39
				if b_t == "house_m":
					stamp_id = 41
				elif d_col == 2:
					stamp_id = 40
				else:
					stamp_id = 39
				for tr in b_h:
					var r: int = b_row0 + tr
					for tc in b_w:
						var c: int = b_col0 + tc
						var idx: int = r * WORK_SIZE + c
						grid_class[idx] = TILE_STAMP
						grid_variant[idx] = stamp_id
						grid_mask[idx] = STAMP_FLAG_SOLID
				if b_col0 + b_w > WORK_CELL_START and b_col0 < WORK_CELL_END and b_row0 + b_h > WORK_CELL_START and b_row0 < WORK_CELL_END:
					stamps_list.append({
						"stamp_id": stamp_id,
						"anchor_gx": cx * 32 + (b_col0 - 4),
						"anchor_gy": _cell_row0(cy) + (b_row0 - 4),
						"w": b_w,
						"h": b_h
					})
			else:
				# Grass with decals: every template tile becomes GRASS, then TALL_GRASS where u(gx, gy, 11) < 0.60
				for tr in b_h:
					var r: int = b_row0 + tr
					for tc in b_w:
						var c: int = b_col0 + tc
						var idx: int = r * WORK_SIZE + c
						var gx: int = cx * 32 + (c - 4)
						var gy: int = cy * 32 + (35 - r)
						if u_rand(gx, gy, world_seed, SALT_YARD_LOT_GRASS) < 0.60:
							grid_class[idx] = TILE_TALL_GRASS
							grid_variant[idx] = 0
						else:
							grid_class[idx] = TILE_GRASS
							grid_variant[idx] = 0
						grid_mask[idx] = 0

				var base_decal_count: int = 2 if b_t == "block_l" else 1
				var num_decals: int = base_decal_count + int(floor(u_rand(gx0, gy0, world_seed, SALT_DECAL_COUNT) * 3.0))
				var start_i := 0
				var occupied_local: Dictionary = {}
				if u_rand(gx0, gy0, world_seed, SALT_DECAL_DOORSTEP) < 0.50:
					var d_col: int = int(b["door_cols"][0]) if not b["door_cols"].is_empty() else 1
					var ds_c: int = b_col0 + d_col
					var ds_r: int = b_row0 + b_h - 1
					var ds_idx: int = ds_r * WORK_SIZE + ds_c
					grid_class[ds_idx] = TILE_STAMP
					grid_variant[ds_idx] = 58
					grid_mask[ds_idx] = 0
					occupied_local[Vector2i(d_col, b_h - 1)] = true
					if ds_c >= WORK_CELL_START and ds_c < WORK_CELL_END and ds_r >= WORK_CELL_START and ds_r < WORK_CELL_END:
						stamps_list.append({
							"stamp_id": 58,
							"anchor_gx": cx * 32 + (ds_c - 4),
							"anchor_gy": _cell_row0(cy) + (ds_r - 4),
							"w": 1,
							"h": 1
						})
					start_i = 1

				for i in range(start_i, num_decals):
					var lx: int = int(floor(u_rand(gx0 + i * 7, gy0, world_seed, SALT_DECAL_POS) * float(b_w)))
					var ly: int = int(floor(u_rand(gx0, gy0 + i * 11, world_seed, SALT_DECAL_POS) * float(b_h)))
					var d_sid: int = 43 + int(floor(u_rand(gx0 + i * 13, gy0 + i * 17, world_seed, SALT_DECAL_COUNT) * 15.0))
					var placed_decal := false
					for _attempt in b_w:
						if not occupied_local.has(Vector2i(lx, ly)):
							occupied_local[Vector2i(lx, ly)] = true
							placed_decal = true
							break
						lx = (lx + 1) % b_w
					if placed_decal:
						var dc: int = b_col0 + lx
						var dr: int = b_row0 + ly
						var d_idx: int = dr * WORK_SIZE + dc
						var d_mask: int = STAMP_FLAG_SOLID if (d_sid == 47 or d_sid == 57) else 0
						grid_class[d_idx] = TILE_STAMP
						grid_variant[d_idx] = d_sid
						grid_mask[d_idx] = d_mask
						if dc >= WORK_CELL_START and dc < WORK_CELL_END and dr >= WORK_CELL_START and dr < WORK_CELL_END:
							stamps_list.append({
								"stamp_id": d_sid,
								"anchor_gx": cx * 32 + (dc - 4),
								"anchor_gy": _cell_row0(cy) + (dr - 4),
								"w": 1,
								"h": 1
							})

	# Only standing and ruined buildings keep their template for door paths and POI signs (§11.2 step 5)
	placed_buildings = surviving_buildings

	# -------------------------------------------------------------
	# 4b. Paths after buildings (§10.2 step 1)
	# -------------------------------------------------------------
	var path_list: Array = line_groups["path"]
	for item in path_list:
		var subkind: String = item["subkind"]
		var pts: PackedVector2Array = item["pts"]
		var is_bridge: bool = subkind.ends_with(":bridge")
		var width := 2 # §13: footways are two tiles wide
		var target_class := TILE_PATH

		var lo: int = (width - 1) / 2
		var hi: int = width - 1 - lo

		for i in range(pts.size() - 1):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var c0: int = floori(p0.x)
			var r0: int = floori(p0.y)
			var c1: int = floori(p1.x)
			var r1: int = floori(p1.y)

			var supercover := supercover_line(c0, r0, c1, r1)
			for center in supercover:
				for br in range(center.y - lo, center.y + hi + 1):
					if br < 0 or br >= WORK_SIZE:
						continue
					for bc in range(center.x - lo, center.x + hi + 1):
						if bc < 0 or bc >= WORK_SIZE:
							continue
						var idx := br * WORK_SIZE + bc
						var current_class: int = grid_class[idx]

						# A path tile never overwrites ROOF, WALL, DOOR, RUBBLE, or STAMP; it simply skips those tiles.
						if current_class in [TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_RUBBLE, TILE_STAMP]:
							continue

						if current_class == TILE_WATER or current_class == TILE_BRIDGE:
							if is_bridge:
								grid_class[idx] = TILE_BRIDGE
							elif water_from_waterway[idx] == 1 and water_from_poly_or_sea[idx] == 0:
								# Culvert: overwrites waterway line
								grid_class[idx] = target_class
						else:
							grid_class[idx] = target_class

	# Door paths (come after 4b, as before)
	for b in placed_buildings:
		for d_col in b["door_cols"]:
			var door_r: int = b["row0"] + b["h"] - 1
			var door_c: int = b["col0"] + d_col
			var walk_path: Array[Vector2i] = []
			var reached_connector := false
			for step in range(1, 7):
				var wr: int = door_r + step
				var wc: int = door_c
				if wr > 35:
					break
				var idx: int = wr * WORK_SIZE + wc
				var cur_cls: int = grid_class[idx]
				if cur_cls in [TILE_PATH, TILE_ROAD, TILE_PLAZA]:
					reached_connector = true
					break
				if cur_cls in [TILE_WATER, TILE_RAIL, TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_RUBBLE, TILE_STAMP, TILE_FENCE, TILE_BRIDGE, TILE_VOID]:
					break
				walk_path.append(Vector2i(wc, wr))
			if reached_connector:
				for pt in walk_path:
					var p_idx: int = pt.y * WORK_SIZE + pt.x
					grid_class[p_idx] = TILE_PATH
					grid_variant[p_idx] = 0
					# §13: two tiles wide: the tile east of the door column too, where only open ground lies
					if pt.x + 1 < WORK_SIZE:
						var e_idx: int = p_idx + 1
						if grid_class[e_idx] in [TILE_GRASS, TILE_TALL_GRASS, TILE_FLOWERS, TILE_SAND, TILE_MARSH]:
							grid_class[e_idx] = TILE_PATH
							grid_variant[e_idx] = 0

	# -------------------------------------------------------------
	# 6. Parks & Forests (§4.1 step 6)
	# -------------------------------------------------------------
	# 6a. Parks: GRASS -> TALL_GRASS where value_noise > 0.55
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_park[idx] == 1 and grid_class[idx] == TILE_GRASS:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)
				if value_noise(gx, gy, world_seed) > 0.55:
					grid_class[idx] = TILE_TALL_GRASS

	# 6b. Park edge tiles become TREE if GRASS or TALL_GRASS
	var park_trees := PackedByteArray()
	park_trees.resize(total_tiles)
	park_trees.fill(0)

	var cardinal_offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_park[idx] == 1 and (grid_class[idx] == TILE_GRASS or grid_class[idx] == TILE_TALL_GRASS):
				var is_edge := false
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE:
						is_edge = true
						break
					var n_idx: int = nr * WORK_SIZE + nc
					if is_park[n_idx] == 0 and grid_class[n_idx] != TILE_WATER:
						is_edge = true
						break
				if is_edge:
					park_trees[idx] = 1

	for idx in total_tiles:
		if park_trees[idx] == 1 and in_landmark_stamp_box[idx] == 0:
			grid_class[idx] = TILE_TREE

	# 6c. Forests: tiles at least 2 tiles from forest edge become TALL_GRASS where v > 0.70
	var forest_edges := PackedByteArray()
	forest_edges.resize(total_tiles)
	forest_edges.fill(0)

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_forest[idx] == 1:
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE or is_forest[nr * WORK_SIZE + nc] == 0:
						forest_edges[idx] = 1
						break

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_forest[idx] == 1 and grid_class[idx] == TILE_TREE:
				# Must be >= 2 tiles from edge: neither itself nor any of its 8-neighbours is a forest edge
				var near_edge := false
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						var nc: int = c + dc
						var nr: int = r + dr
						if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE:
							near_edge = true
							break
						if forest_edges[nr * WORK_SIZE + nc] == 1:
							near_edge = true
							break
					if near_edge:
						break
				if not near_edge:
					var gx := cx * 32 + (c - 4)
					var gy := cy * 32 + (35 - r)
					if value_noise(gx, gy, world_seed) > 0.70:
						grid_class[idx] = TILE_TALL_GRASS

	# -------------------------------------------------------------
	# 7. Cemeteries (§4.1 step 7)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_cemetery[idx] == 1 and grid_class[idx] == TILE_GRASS and in_landmark_stamp_box[idx] == 0:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)
				if posmod(gx, 2) == 0 and posmod(gy, 3) == 0:
					grid_class[idx] = TILE_GRAVE

	var cemetery_fences := PackedByteArray()
	cemetery_fences.resize(total_tiles)
	cemetery_fences.fill(0)

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_cemetery[idx] == 1 and (grid_class[idx] == TILE_GRASS or grid_class[idx] == TILE_GRAVE):
				var is_edge := false
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE or is_cemetery[nr * WORK_SIZE + nc] == 0:
						is_edge = true
						break
				if is_edge:
					cemetery_fences[idx] = 1

	for idx in total_tiles:
		if cemetery_fences[idx] == 1 and in_landmark_stamp_box[idx] == 0:
			grid_class[idx] = TILE_FENCE

	# -------------------------------------------------------------
	# 6.5. Overgrowth on the ground (§11.2 step 6)
	# -------------------------------------------------------------
	var path_tg_thresh := 2.0 # never in camp
	var path_v1_thresh := 0.10
	var road_v1_thresh := 0.10
	var plaza_v1_thresh := 0.10
	var plaza_tg_thresh := 2.0 # never in camp/near
	var res_tree_thresh := 0.08
	match band:
		"camp":
			path_tg_thresh = 2.0
			path_v1_thresh = 0.10
			road_v1_thresh = 0.10
			plaza_v1_thresh = 0.10
			plaza_tg_thresh = 2.0
			res_tree_thresh = 0.08
		"near":
			path_tg_thresh = 0.80
			path_v1_thresh = 0.25
			road_v1_thresh = 0.20
			plaza_v1_thresh = 0.50
			plaza_tg_thresh = 2.0
			res_tree_thresh = 0.10
		"mid":
			path_tg_thresh = 0.72
			path_v1_thresh = 0.40
			road_v1_thresh = 0.35
			plaza_v1_thresh = 0.50
			plaza_tg_thresh = 0.60
			res_tree_thresh = 0.13
		"far":
			path_tg_thresh = 0.65
			path_v1_thresh = 0.55
			road_v1_thresh = 0.50
			plaza_v1_thresh = 0.50
			plaza_tg_thresh = 0.55
			res_tree_thresh = 0.16

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			var cls: int = grid_class[idx]
			var gx := cx * 32 + (c - 4)
			var gy := cy * 32 + (35 - r)
			if cls == TILE_PATH:
				if path_tg_thresh <= 1.0 and value_noise(gx, gy, world_seed) > path_tg_thresh:
					grid_class[idx] = TILE_TALL_GRASS
					grid_variant[idx] = 0
				elif u_rand(gx, gy, world_seed, SALT_PATH_OVERGROWTH) < path_v1_thresh:
					grid_variant[idx] = 1
			elif cls == TILE_PLAZA:
				if plaza_tg_thresh <= 1.0 and value_noise(gx, gy, world_seed) > plaza_tg_thresh:
					grid_class[idx] = TILE_TALL_GRASS
					grid_variant[idx] = 0
				elif u_rand(gx, gy, world_seed, SALT_PLAZA_WEEDS) < plaza_v1_thresh:
					grid_variant[idx] = 1

	# -------------------------------------------------------------
	# 8. Scatter (§4.1 step 8, §11.2 step 6)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if grid_class[idx] == TILE_GRASS:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)

				# 8b. FLOWERS within 2 tiles (Chebyshev) of a DOOR where u(..., 2) < 0.25
				var near_door := false
				for d in all_doors:
					if maxi(absi(c - d.x), absi(r - d.y)) <= 2:
						near_door = true
						break
				if near_door and u_rand(gx, gy, world_seed, SALT_FLOWERS) < 0.25:
					grid_class[idx] = TILE_FLOWERS
					grid_variant[idx] = 0
					continue

				# 8a. TREE scatter
				var threshold: float = res_tree_thresh if is_residential[idx] == 1 else 0.05
				if in_landmark_stamp_box[idx] == 0 and u_rand(gx, gy, world_seed, SALT_TREE_SCATTER) < threshold:
					# Check 8-neighbourhood for forbidden classes
					var blocked := false
					for dr in range(-1, 2):
						for dc in range(-1, 2):
							if dr == 0 and dc == 0:
								continue
							var nc: int = c + dc
							var nr: int = r + dr
							if nc >= 0 and nc < WORK_SIZE and nr >= 0 and nr < WORK_SIZE:
								var n_cls: int = grid_class[nr * WORK_SIZE + nc]
								if n_cls in [TILE_PATH, TILE_ROAD, TILE_PLAZA, TILE_DOOR, TILE_WALL, TILE_ROOF, TILE_RUBBLE, TILE_STAMP, TILE_FENCE, TILE_SIGN]:
									blocked = true
									break
						if blocked:
							break
					if not blocked:
						grid_class[idx] = TILE_TREE

	# -------------------------------------------------------------
	# 9. Signs (§4.1 step 9, §4.4)
	# -------------------------------------------------------------
	var sign_candidates: Array[Dictionary] = []

	# POI place nodes in centre cell
	var places: Array = area.get(Vector2i.ZERO, {}).get("places", [])
	for place in places:
		var s_name: String = place.get("name", "")
		if s_name.is_empty():
			continue
		var s_cat: String = place.get("category", "")
		var s_osm_id: int = int(place.get("osm_id", 0))
		var lat: float = float(place.get("lat", 0.0))
		var lon: float = float(place.get("lon", 0.0))
		var wm: Vector2 = Grid.latlon_to_wm(lat, lon)
		var cell_origin := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
		var su: Vector2 = (wm - cell_origin) / MapStore.GEOM_UNIT_WM
		var c_tile: int = clampi(int(floor(4.0 + 2.0 * su.x)), 4, 35)
		var r_tile: int = clampi(int(floor(36.0 - 2.0 * su.y)), 4, 35)
		sign_candidates.append({
			"is_poi": true,
			"name": s_name,
			"category": s_cat,
			"priority": _sign_priority(s_cat),
			"osm_id": s_osm_id,
			"grid_pos": Vector2i(c_tile, r_tile)
		})

	# Named polygon pieces in centre cell
	for poly in center_polys:
		var s_name: String = poly.get("name", "")
		if s_name.is_empty() or poly.get("kind", "") == "building":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var p_rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			p_rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				p_rings.append(PackedVector2Array(r_item))
		if p_rings.is_empty() or p_rings[0].size() < 3:
			continue

		var p_min_x := INF
		var p_max_x := -INF
		var p_min_y := INF
		var p_max_y := -INF
		for pt in p_rings[0]:
			p_min_x = minf(p_min_x, pt.x)
			p_max_x = maxf(p_max_x, pt.x)
			p_min_y = minf(p_min_y, pt.y)
			p_max_y = maxf(p_max_y, pt.y)

		var p_kind: String = poly.get("kind", "")
		var s_cat: String = "park" if p_kind == "park" else p_kind
		var bc_col: int = clampi(int(round(4.0 + 2.0 * ((p_min_x + p_max_x) * 0.5))), 4, 35)
		var bot_row: int = clampi(int(round(36.0 - 2.0 * p_min_y)), 4, 35)
		sign_candidates.append({
			"is_poi": false,
			"name": s_name,
			"category": s_cat,
			"priority": _sign_priority(s_cat),
			"osm_id": 0,
			"grid_pos": Vector2i(bc_col, bot_row),
			"rings": p_rings
		})

	# Spacing: landmark > haunted > civic > medical > park > any other category,
	# then lower osm_id (for polygons, lower (row, col))
	sign_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		if a["is_poi"] and b["is_poi"]:
			return a["osm_id"] < b["osm_id"]
		if a["is_poi"] != b["is_poi"]:
			return a["is_poi"]
		if a["grid_pos"].y != b["grid_pos"].y:
			return a["grid_pos"].y < b["grid_pos"].y
		return a["grid_pos"].x < b["grid_pos"].x
	)

	var signs_list: Array[String] = []
	var placed_sign_tiles: Array[Vector2i] = []

	# Landmark signs (§10.8 step 2) placed before ordinary signs
	for lm_sign in landmark_sign_specs:
		if signs_list.size() >= 16:
			break
		var target_pos := Vector2i(-1, -1)
		var p0: Vector2i = lm_sign["door_pos"]

		if lm_sign["is_building"]:
			# Candidate tiles beside the door: south-west, south-east, west, east, south, rings 1..2
			var candidates: Array[Vector2i] = [
				Vector2i(p0.x - 1, p0.y + 1),
				Vector2i(p0.x + 1, p0.y + 1),
				Vector2i(p0.x - 1, p0.y),
				Vector2i(p0.x + 1, p0.y),
				Vector2i(p0.x, p0.y + 1)
			]
			for rad in [1, 2]:
				for off in [Vector2i(0, -rad), Vector2i(rad, 0), Vector2i(0, rad), Vector2i(-rad, 0)]:
					var cand_p: Vector2i = p0 + off
					if not candidates.has(cand_p):
						candidates.append(cand_p)

			for cand_p in candidates:
				if cand_p.x >= 4 and cand_p.x <= 35 and cand_p.y >= 4 and cand_p.y <= 35:
					var cls: int = grid_class[cand_p.y * WORK_SIZE + cand_p.x]
					if cls == TILE_GRASS or cls == TILE_PATH or cls == TILE_TALL_GRASS or cls == TILE_FLOWERS:
						target_pos = cand_p
						break
		else:
			# Structure with no building: first GRASS or PATH tile within 2 tiles of door
			if p0.x >= 4 and p0.x <= 35 and p0.y >= 4 and p0.y <= 35:
				var p0_cls: int = grid_class[p0.y * WORK_SIZE + p0.x]
				if p0_cls == TILE_GRASS or p0_cls == TILE_PATH or p0_cls == TILE_TALL_GRASS or p0_cls == TILE_FLOWERS:
					target_pos = p0
			if target_pos.x == -1:
				for rad in [1, 2]:
					var ring_offsets: Array[Vector2i] = [Vector2i(0, -rad), Vector2i(rad, 0), Vector2i(0, rad), Vector2i(-rad, 0),
						Vector2i(-rad, -rad), Vector2i(rad, -rad), Vector2i(rad, rad), Vector2i(-rad, rad)]
					for off in ring_offsets:
						var cand_p: Vector2i = p0 + off
						if cand_p.x >= 4 and cand_p.x <= 35 and cand_p.y >= 4 and cand_p.y <= 35:
							var cls: int = grid_class[cand_p.y * WORK_SIZE + cand_p.x]
							if cls == TILE_GRASS or cls == TILE_PATH or cls == TILE_TALL_GRASS or cls == TILE_FLOWERS:
								target_pos = cand_p
								break
					if target_pos.x != -1:
						break

		if target_pos.x != -1:
			var too_close := false
			for st in placed_sign_tiles:
				if maxi(absi(target_pos.x - st.x), absi(target_pos.y - st.y)) <= 3:
					too_close = true
					break
			if not too_close:
				var s_idx := signs_list.size()
				grid_class[target_pos.y * WORK_SIZE + target_pos.x] = TILE_SIGN
				grid_variant[target_pos.y * WORK_SIZE + target_pos.x] = s_idx
				placed_sign_tiles.append(target_pos)
				signs_list.append(lm_sign["name"])

	for cand in sign_candidates:
		if signs_list.size() >= 16:
			break
		var target_pos := Vector2i(-1, -1)

		if cand["is_poi"]:
			# Check if inside a placed template
			var p0: Vector2i = cand["grid_pos"]
			var inside_b = null
			for b in placed_buildings:
				if p0.x >= b["col0"] and p0.x < b["col0"] + b["w"] and p0.y >= b["row0"] and p0.y < b["row0"] + b["h"]:
					inside_b = b
					break
			if inside_b != null:
				# West of first door
				var d_col: int = inside_b["door_cols"][0]
				var d_r: int = inside_b["row0"] + inside_b["h"] - 1
				var d_c: int = inside_b["col0"] + d_col
				var west_c := d_c - 1
				if west_c >= 4 and west_c <= 35 and d_r >= 4 and d_r <= 35:
					if grid_class[d_r * WORK_SIZE + west_c] == TILE_GRASS:
						target_pos = Vector2i(west_c, d_r)
			else:
				# Own tile if GRASS, else rings of radius 1-2 scanning N, E, S, W
				if grid_class[p0.y * WORK_SIZE + p0.x] == TILE_GRASS:
					target_pos = p0
				else:
					var found_ring := false
					for rad in [1, 2]:
						var ring_offsets: Array[Vector2i] = [Vector2i(0, -rad), Vector2i(rad, 0), Vector2i(0, rad), Vector2i(-rad, 0)]
						for off: Vector2i in ring_offsets:
							var cand_tp: Vector2i = p0 + off
							if cand_tp.x >= 4 and cand_tp.x <= 35 and cand_tp.y >= 4 and cand_tp.y <= 35:
								if grid_class[cand_tp.y * WORK_SIZE + cand_tp.x] == TILE_GRASS:
									target_pos = cand_tp
									found_ring = true
									break
						if found_ring:
							break
		else:
			# Named polygon: scan north from bottom-centre up to 4 tiles for first GRASS inside polygon
			var bc_col: int = cand["grid_pos"].x
			var bot_row: int = cand["grid_pos"].y
			var p_rings: Array[PackedVector2Array] = cand["rings"]
			for s in range(5):
				var tr := bot_row - s
				var tc := bc_col
				if tc >= 4 and tc <= 35 and tr >= 4 and tr <= 35:
					if grid_class[tr * WORK_SIZE + tc] == TILE_GRASS:
						var pt_su := Vector2((float(tc) + 0.5 - 4.0) * 0.5, (36.0 - (float(tr) + 0.5)) * 0.5)
						if _point_in_rings(pt_su, p_rings):
							target_pos = Vector2i(tc, tr)
							break

		if target_pos.x == -1:
			continue

		# Spacing: no two signs within 3 tiles (Chebyshev)
		var too_close := false
		for st in placed_sign_tiles:
			if maxi(absi(target_pos.x - st.x), absi(target_pos.y - st.y)) <= 3:
				too_close = true
				break
		if too_close:
			continue

		var s_idx := signs_list.size()
		grid_class[target_pos.y * WORK_SIZE + target_pos.x] = TILE_SIGN
		grid_variant[target_pos.y * WORK_SIZE + target_pos.x] = s_idx
		placed_sign_tiles.append(target_pos)
		signs_list.append(cand["name"])

	# -------------------------------------------------------------
	# 10. Variants & Masks (§4.1 step 10)
	# -------------------------------------------------------------
	var output := PackedByteArray()
	output.resize(OUTPUT_BUFFER_SIZE)
	var out_idx := 0

	for r in range(WORK_CELL_START, WORK_CELL_END):
		for c in range(WORK_CELL_START, WORK_CELL_END):
			var idx := r * WORK_SIZE + c
			var cls: int = grid_class[idx]
			var gx: int = cx * 32 + (c - 4)
			var gy: int = cy * 32 + (35 - r)

			# Variant byte
			var variant := 0
			match cls:
				TILE_GRASS:
					variant = floori(u_rand(gx, gy, world_seed, SALT_GRASS_VARIANT) * 4.0)
				TILE_ROAD:
					variant = 1 if u_rand(gx, gy, world_seed, SALT_ROAD_CRACKS) < road_v1_thresh else 0
				TILE_TREE:
					variant = 1 if u_rand(gx, gy, world_seed, SALT_TREE_VARIANT) < 0.30 else 0
				TILE_PATH, TILE_PLAZA, TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_SIGN, TILE_RUBBLE, TILE_STAMP:
					variant = grid_variant[idx]
				_:
					variant = 0

			# Mask byte
			var mask := 0
			if cls == TILE_STAMP or cls == TILE_DOOR:
				mask = grid_mask[idx]
			elif cls == TILE_ROOF:
				var my_color: int = 32 if (grid_variant[idx] & 32) != 0 else (grid_variant[idx] % 8)
				if grid_class[(r - 1) * WORK_SIZE + c] == TILE_ROOF:
					var n_col: int = 32 if (grid_variant[(r - 1) * WORK_SIZE + c] & 32) != 0 else (grid_variant[(r - 1) * WORK_SIZE + c] % 8)
					if n_col == my_color:
						mask |= 1
				if grid_class[r * WORK_SIZE + (c + 1)] == TILE_ROOF:
					var e_col: int = 32 if (grid_variant[r * WORK_SIZE + (c + 1)] & 32) != 0 else (grid_variant[r * WORK_SIZE + (c + 1)] % 8)
					if e_col == my_color:
						mask |= 2
				if grid_class[(r + 1) * WORK_SIZE + c] == TILE_ROOF:
					var s_col: int = 32 if (grid_variant[(r + 1) * WORK_SIZE + c] & 32) != 0 else (grid_variant[(r + 1) * WORK_SIZE + c] % 8)
					if s_col == my_color:
						mask |= 4
				if grid_class[r * WORK_SIZE + (c - 1)] == TILE_ROOF:
					var w_col: int = 32 if (grid_variant[r * WORK_SIZE + (c - 1)] & 32) != 0 else (grid_variant[r * WORK_SIZE + (c - 1)] % 8)
					if w_col == my_color:
						mask |= 8
			elif cls == TILE_WALL:
				var my_color: int = 32 if (grid_variant[idx] & 32) != 0 else (grid_variant[idx] % 8)
				var n_n: int = grid_class[(r - 1) * WORK_SIZE + c]
				if n_n == TILE_WALL or n_n == TILE_DOOR:
					var n_col: int = 32 if (grid_variant[(r - 1) * WORK_SIZE + c] & 32) != 0 else (grid_variant[(r - 1) * WORK_SIZE + c] % 8)
					if n_col == my_color:
						mask |= 1
				var n_e: int = grid_class[r * WORK_SIZE + (c + 1)]
				if n_e == TILE_WALL or n_e == TILE_DOOR:
					var e_col: int = 32 if (grid_variant[r * WORK_SIZE + (c + 1)] & 32) != 0 else (grid_variant[r * WORK_SIZE + (c + 1)] % 8)
					if e_col == my_color:
						mask |= 2
				var n_s: int = grid_class[(r + 1) * WORK_SIZE + c]
				if n_s == TILE_WALL or n_s == TILE_DOOR:
					var s_col: int = 32 if (grid_variant[(r + 1) * WORK_SIZE + c] & 32) != 0 else (grid_variant[(r + 1) * WORK_SIZE + c] % 8)
					if s_col == my_color:
						mask |= 4
				var n_w: int = grid_class[r * WORK_SIZE + (c - 1)]
				if n_w == TILE_WALL or n_w == TILE_DOOR:
					var w_col: int = 32 if (grid_variant[r * WORK_SIZE + (c - 1)] & 32) != 0 else (grid_variant[r * WORK_SIZE + (c - 1)] % 8)
					if w_col == my_color:
						mask |= 8
			else:
				var family: Array = _get_mask_family(cls)
				if not family.is_empty():
					# Bit 0 = North (r - 1, c)
					if grid_class[(r - 1) * WORK_SIZE + c] in family:
						mask |= 1
					# Bit 1 = East (r, c + 1)
					if grid_class[r * WORK_SIZE + (c + 1)] in family:
						mask |= 2
					# Bit 2 = South (r + 1, c)
					if grid_class[(r + 1) * WORK_SIZE + c] in family:
						mask |= 4
					# Bit 3 = West (r, c - 1)
					if grid_class[r * WORK_SIZE + (c - 1)] in family:
						mask |= 8

			output[out_idx] = cls
			output[out_idx + 1] = variant
			output[out_idx + 2] = mask
			out_idx += 3

	stamps_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay: int = int(a["anchor_gy"]) + int(a["h"])
		var by: int = int(b["anchor_gy"]) + int(b["h"])
		if ay != by:
			return ay < by
		if int(a["anchor_gx"]) != int(b["anchor_gx"]):
			return int(a["anchor_gx"]) < int(b["anchor_gx"])
		return int(a["stamp_id"]) < int(b["stamp_id"])
	)

	return {
		"tiles": output,
		"signs": PackedStringArray(signs_list),
		"stamps": stamps_list,
		"stats": {
			"building_candidates": total_building_candidates,
			"buildings_placed": buildings_placed_count,
			"fallback_placed": fallback_placed_count,
			"landmarks_placed": landmarks_placed_count,
			"landmarks_sign_only": landmarks_sign_only_count,
			"landmark_ids_placed": landmark_ids_placed,
			"ordinary_standing": ordinary_standing,
			"ordinary_ruined": ordinary_ruined,
			"ordinary_gone": ordinary_gone
		}
	}

## Mask family for 4-neighbour connectivity (§3 table)
static func _get_mask_family(cls: int) -> Array:
	match cls:
		TILE_WATER:
			return [TILE_WATER, TILE_BRIDGE]
		TILE_PATH:
			return [TILE_PATH, TILE_ROAD, TILE_BRIDGE, TILE_PLAZA, TILE_DOOR]
		TILE_ROAD:
			return [TILE_ROAD, TILE_BRIDGE, TILE_PLAZA]
		TILE_RAIL:
			return [TILE_RAIL, TILE_BRIDGE]
		TILE_BRIDGE:
			return [TILE_BRIDGE, TILE_ROAD, TILE_PATH, TILE_RAIL]
		TILE_TREE:
			return [TILE_TREE]
		TILE_TALL_GRASS:
			return [TILE_TALL_GRASS]
		TILE_ROOF:
			return [TILE_ROOF]
		TILE_WALL:
			return [TILE_WALL, TILE_DOOR]
		TILE_FENCE:
			return [TILE_FENCE]
		_:
			return []
