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

static func resolve_atlas_texture(cache_dir: String = AssetDB.DEFAULT_CACHE_DIR, force_fallback: bool = false) -> Dictionary:
	if not force_fallback:
		var em_v: Variant = AssetDB.indoor_tile_atlas(cache_dir)
		if em_v is Dictionary:
			var em_tex: Texture2D = (em_v as Dictionary).get("texture", null)
			if em_tex != null:
				return {"texture": em_tex, "source": "emerald"}
	return {"texture": build_fallback_texture(), "source": "fallback"}

static func build_fallback_texture() -> ImageTexture:
	if _fallback_tex != null:
		return _fallback_tex
	var strip16 := Image.create(CLASS_COUNT * 16, 16, false, Image.FORMAT_RGBA8)
	strip16.fill(Color8(12, 14, 20, 255))

	# 0: void_black
	_fill_tile16(strip16, TILE_INT_VOID_BLACK, Color8(12, 14, 20, 255))

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

	# 10: pit_chasm — dark chasm opening inside jagged stone rim
	_fill_tile16(strip16, TILE_INT_PIT_CHASM, Color8(136, 142, 154, 255))
	for y in range(2, 14):
		for x in range(2, 14):
			if (x + y > 4) and (x + (15 - y) > 4) and ((15 - x) + y > 4) and ((15 - x) + (15 - y) > 4):
				_px16(strip16, TILE_INT_PIT_CHASM, x, y, Color8(36, 40, 54, 255))

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

	var strip32 := Image.create(CLASS_COUNT * TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(CLASS_COUNT * 16):
			var c := strip16.get_pixel(x, y)
			var dx := x * 2
			var dy := y * 2
			strip32.set_pixel(dx, dy, c)
			strip32.set_pixel(dx + 1, dy, c)
			strip32.set_pixel(dx, dy + 1, c)
			strip32.set_pixel(dx + 1, dy + 1, c)
	_fallback_tex = ImageTexture.create_from_image(strip32)
	return _fallback_tex

static func _fill_tile16(img: Image, cls: int, col: Color) -> void:
	var x0 := cls * 16
	for y in range(16):
		for x in range(16):
			img.set_pixel(x0 + x, y, col)

static func _px16(img: Image, cls: int, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < 16 and y >= 0 and y < 16:
		img.set_pixel(cls * 16 + x, y, col)

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
