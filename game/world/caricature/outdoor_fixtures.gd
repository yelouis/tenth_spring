class_name OutdoorFixtures
extends RefCounted

## Resolves outdoor town fixtures from Emerald ROM atlas (emerald_outdoor_fx_v1)
## with crisp 32 px/tile procedural pixel-art fallbacks for no-ROM runs (Item 62).

const AssetDB := preload("res://rom/asset_db.gd")
const TILE_PX: int = 32
const CFG_PATH := "res://config/emerald_tile_map.json"

static var _cfg_fx_cache: Dictionary = {}
static var _cfg_loaded: bool = false
static var _proc_tex_cache: Dictionary = {}
static var _rom_tex_cache: Dictionary = {}
static var _atlas_img_cache: Dictionary = {}


static func clear_cache() -> void:
	_proc_tex_cache.clear()
	_rom_tex_cache.clear()
	_atlas_img_cache.clear()
	_cfg_fx_cache.clear()
	_cfg_loaded = false


static func _ensure_cfg_loaded() -> void:
	if _cfg_loaded:
		return
	_cfg_loaded = true
	if not FileAccess.file_exists(CFG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	if parsed is Dictionary:
		var fx: Variant = (parsed as Dictionary).get("outdoor_fixtures", {})
		if fx is Dictionary:
			_cfg_fx_cache = fx


static func fixture_meta(kind: String) -> Dictionary:
	_ensure_cfg_loaded()
	if kind == "standin_bench":
		return {"w": 2, "h": 1, "base_rows": 1}
	if kind == "standin_lock_gate":
		return {"w": 2, "h": 3, "base_rows": 3}
	if _cfg_fx_cache.has(kind):
		var spec: Dictionary = _cfg_fx_cache[kind]
		return {
			"w": maxi(1, int(spec.get("w", 1))),
			"h": maxi(1, int(spec.get("h", 1))),
			"base_rows": maxi(0, int(spec.get("base_rows", 1))),
		}
	return {"w": 1, "h": 1, "base_rows": 1}


static func resolve_texture(
	kind: String,
	force_fallback: bool = false,
	cache_dir: String = AssetDB.DEFAULT_CACHE_DIR
) -> Dictionary:
	var meta := fixture_meta(kind)
	var tw := int(meta["w"])
	var th := int(meta["h"])
	var base_rows := int(meta["base_rows"])

	if not force_fallback:
		var bundle: Variant = AssetDB.outdoor_fixture_atlas(cache_dir)
		if bundle is Dictionary:
			var bdict: Dictionary = bundle
			var tex: Texture2D = bdict.get("texture", null)
			var info: Dictionary = bdict.get("json", {})
			var fx_map: Dictionary = info.get("fixtures", {})
			if tex != null and fx_map.has(kind):
				var rid_id := tex.get_rid().get_id()
				var cache_key := "%s|%s|%d" % [cache_dir, kind, rid_id]
				var sub_tex: Texture2D = _rom_tex_cache.get(cache_key, null)
				if sub_tex == null:
					var atlas_img: Image = _atlas_img_cache.get(rid_id, null)
					if atlas_img == null:
						atlas_img = tex.get_image()
						if atlas_img != null and not atlas_img.is_empty():
							_atlas_img_cache[rid_id] = atlas_img
					if atlas_img != null and not atlas_img.is_empty():
						var rect_d: Dictionary = fx_map[kind]
						var reg := Rect2i(
							int(rect_d.get("x", 0)),
							int(rect_d.get("y", 0)),
							int(rect_d.get("w", tw * TILE_PX)),
							int(rect_d.get("h", th * TILE_PX))
						)
						sub_tex = ImageTexture.create_from_image(atlas_img.get_region(reg))
						_rom_tex_cache[cache_key] = sub_tex
				if sub_tex != null:
					return {
						"texture": sub_tex,
						"tile_w": tw,
						"tile_h": th,
						"base_rows": int((fx_map[kind] as Dictionary).get("base_rows", base_rows)),
						"is_rom": true,
					}

	var ptex := _get_procedural_texture(kind, tw, th)
	return {
		"texture": ptex,
		"tile_w": tw,
		"tile_h": th,
		"base_rows": base_rows,
		"is_rom": false,
	}


static func _get_procedural_texture(kind: String, tw: int, th: int) -> Texture2D:
	if _proc_tex_cache.has(kind):
		return _proc_tex_cache[kind]
	# Draw on 16x16 per tile grid, then scale 2x nearest to match 32 px/tile ROM crispness
	var gw := tw * 16
	var gh := th * 16
	var img := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color8(36, 40, 52, 255)

	match kind:
		"em_streetlamp":
			_box(img, 5, 2, 6, 8, outline, Color8(248, 224, 132, 255))
			_fill_rect(img, 6, 2, 4, 2, Color8(62, 68, 86, 255))
			_box(img, 6, 10, 4, 19, outline, Color8(76, 84, 102, 255))
			_box(img, 5, 27, 6, 4, outline, Color8(60, 66, 82, 255))
		"em_fountain":
			_box(img, 4, 8, 40, 34, outline, Color8(184, 192, 204, 255))
			_box(img, 9, 13, 30, 22, Color8(98, 126, 152, 255), Color8(116, 178, 224, 255))
			_box(img, 20, 6, 8, 18, outline, Color8(208, 214, 224, 255))
			_fill_rect(img, 21, 3, 6, 4, Color8(178, 228, 248, 255))
		"em_statue":
			_box(img, 4, 4, 8, 14, outline, Color8(224, 226, 232, 255))
			_box(img, 2, 18, 12, 12, outline, Color8(174, 178, 188, 255))
		"em_lighthouse":
			_box(img, 6, 4, 20, 14, outline, Color8(248, 226, 138, 255))
			_box(img, 4, 18, 24, 42, outline, Color8(228, 232, 238, 255))
			_fill_rect(img, 8, 30, 16, 6, Color8(72, 118, 168, 255))
		"em_flower_patch":
			for fx in [3, 10]:
				for fy in [3, 10]:
					_fill_rect(img, fx - 1, fy - 1, 4, 4, Color8(56, 124, 62, 255))
					_fill_rect(img, fx, fy, 2, 2, Color8(232, 96, 104, 255) if fx == 3 else Color8(244, 214, 96, 255))
		"em_planter_box", "em_planter_tall":
			_box(img, 1, 2, gw - 2, gh - 4, outline, Color8(168, 114, 68, 255))
			_fill_rect(img, 3, 3, gw - 6, gh - 8, Color8(62, 128, 64, 255))
			for y in range(4, gh - 7, 5):
				for x in range(4, gw - 5, 5):
					_fill_rect(img, x, y, 2, 2, Color8(232, 98, 110, 255) if ((x + y) % 2 == 0) else Color8(246, 214, 98, 255))
		"em_flower_pots":
			_box(img, 2, 4, 12, 10, outline, Color8(204, 208, 216, 255))
			_fill_rect(img, 3, 2, 10, 6, Color8(60, 126, 66, 255))
			_fill_rect(img, 5, 3, 2, 2, Color8(236, 102, 84, 255))
			_fill_rect(img, 9, 4, 2, 2, Color8(246, 210, 88, 255))
		"em_wood_sign", "em_notice_board":
			var board := Color8(178, 126, 78, 255) if kind == "em_wood_sign" else Color8(152, 134, 118, 255)
			_fill_rect(img, 7, 10, 2, 5, outline)
			_box(img, 2, 2, 12, 9, outline, board)
			_fill_rect(img, 4, 4, 8, 2, Color8(238, 228, 206, 255))
			_fill_rect(img, 4, 7, 6, 2, Color8(224, 212, 188, 255))
		"em_iron_fence_h", "em_iron_fence_v", "em_white_fence_h", "em_white_fence_v", "em_wood_fence_post":
			var col := Color8(72, 78, 96, 255)
			if kind.begins_with("em_white"):
				col = Color8(218, 224, 232, 255)
			elif kind.begins_with("em_wood"):
				col = Color8(158, 108, 66, 255)
			if kind.ends_with("_v"):
				_box(img, 6, 0, 4, 16, outline, col)
			elif kind == "em_wood_fence_post":
				_box(img, 4, 3, 8, 12, outline, col)
			else:
				_box(img, 0, 4, 16, 8, outline, col)
				_fill_rect(img, 3, 2, 3, 12, col)
				_fill_rect(img, 10, 2, 3, 12, col)
		"em_market_stall_blue", "em_market_stall_peach":
			var tarp := Color8(92, 138, 212, 255) if kind.ends_with("blue") else Color8(224, 154, 106, 255)
			_box(img, 2, 2, gw - 4, 20, outline, tarp)
			for x in range(4, gw - 4, 6):
				_fill_rect(img, x, 3, 3, 18, tarp.lightened(0.22))
			_box(img, 4, 22, 4, 8, outline, Color8(138, 92, 56, 255))
			_box(img, gw - 8, 22, 4, 8, outline, Color8(138, 92, 56, 255))
		"em_crate_wood", "em_crate_green", "em_crate_stack":
			var ccol := Color8(102, 146, 98, 255) if kind == "em_crate_green" else Color8(184, 140, 88, 255)
			_box(img, 2, 3, 12, 12, outline, ccol)
			_fill_rect(img, 3, 7, 10, 2, outline)
			if th >= 2:
				_box(img, 2, 17, 12, 13, outline, ccol.darkened(0.1))
				_fill_rect(img, 3, 22, 10, 2, outline)
		"em_goods_tray", "em_goods_urn", "em_goods_basket", "em_goods_fruit":
			var gcol := Color8(136, 126, 104, 255)
			if kind == "em_goods_basket":
				gcol = Color8(66, 172, 132, 255)
			elif kind == "em_goods_fruit":
				gcol = Color8(218, 92, 54, 255)
			elif kind == "em_goods_tray":
				gcol = Color8(216, 210, 178, 255)
			_box(img, 3, 3, 10, 10, outline, gcol)
		"em_bollard":
			_box(img, 4, 3, 8, 11, outline, Color8(186, 194, 206, 255))
		"em_rowboat":
			_box(img, 3, 4, 42, 24, outline, Color8(168, 132, 92, 255))
			_fill_rect(img, 6, 8, 36, 16, Color8(122, 94, 66, 255))
			_fill_rect(img, 18, 6, 4, 20, Color8(186, 152, 108, 255))
			_fill_rect(img, 30, 6, 4, 20, Color8(186, 152, 108, 255))
		"em_sailboat":
			_box(img, 4, 24, 40, 18, outline, Color8(214, 208, 192, 255))
			_box(img, 14, 4, 18, 22, outline, Color8(236, 240, 248, 255))
			_fill_rect(img, 18, 6, 8, 16, Color8(124, 184, 216, 255))
		"standin_bench":
			# 2x1 tiles (32x16 -> 64x32 px) straight-on wood & wrought-iron park bench
			_box(img, 2, 2, 28, 6, outline, Color8(168, 114, 68, 255))
			_fill_rect(img, 4, 4, 24, 1, Color8(198, 144, 90, 255))
			_box(img, 1, 7, 30, 5, outline, Color8(146, 94, 54, 255))
			_box(img, 2, 6, 3, 9, outline, Color8(62, 68, 84, 255))
			_box(img, 27, 6, 3, 9, outline, Color8(62, 68, 84, 255))
		"standin_lock_gate":
			# 2x3 tiles (32x48 -> 64x96 px) heavy timber & iron miter lock gates across 3-tile canal
			_box(img, 0, 1, 32, 7, outline, Color8(134, 142, 154, 255)) # balance beam walk top
			_box(img, 1, 8, 15, 36, outline, Color8(122, 82, 48, 255)) # west timber leaf
			_box(img, 16, 8, 15, 36, outline, Color8(112, 74, 42, 255)) # east timber leaf
			for gy in [14, 24, 34]:
				_fill_rect(img, 2, gy, 28, 3, outline)
				_fill_rect(img, 3, gy + 1, 26, 1, Color8(136, 146, 160, 255))
			for px in [5, 10, 21, 26]:
				_fill_rect(img, px, 9, 1, 34, Color8(88, 56, 32, 255))
			_fill_rect(img, 2, 44, 28, 3, Color8(176, 224, 244, 255)) # water sill foam
		_:
			_box(img, 3, 3, gw - 6, gh - 6, outline, Color8(164, 168, 180, 255))

	var out := Image.create(gw * 2, gh * 2, false, Image.FORMAT_RGBA8)
	for y in range(gh):
		for x in range(gw):
			var c := img.get_pixel(x, y)
			var dx := x * 2
			var dy := y * 2
			out.set_pixel(dx, dy, c)
			out.set_pixel(dx + 1, dy, c)
			out.set_pixel(dx, dy + 1, c)
			out.set_pixel(dx + 1, dy + 1, c)
	var tex := ImageTexture.create_from_image(out)
	_proc_tex_cache[kind] = tex
	return tex


static func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(maxi(0, y0), mini(img.get_height(), y0 + h)):
		for x in range(maxi(0, x0), mini(img.get_width(), x0 + w)):
			img.set_pixel(x, y, col)


static func _box(img: Image, x0: int, y0: int, w: int, h: int, border: Color, fill: Color) -> void:
	for y in range(maxi(0, y0), mini(img.get_height(), y0 + h)):
		for x in range(maxi(0, x0), mini(img.get_width(), x0 + w)):
			var is_edge := (x == x0 or x == x0 + w - 1 or y == y0 or y == y0 + h - 1)
			img.set_pixel(x, y, border if is_edge else fill)
