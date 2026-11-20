class_name PeopleSprites
extends RefCounted

## Resolves shared 16x32 (scaled 2x -> 32x64 px) overworld and indoor person sprites
## from Emerald's cached emerald_people_v1 atlas, with a no-ROM code-drawn fallback
## originally migrated from InteriorView (Item 62).

const AssetDB := preload("res://rom/asset_db.gd")

const ROLE_TO_SPRITE := {
	"scholar": "scientist",
	"archivist": "scientist",
	"warden": "gentleman",
	"healer": "healer",
	"trader": "shopkeeper",
	"shopkeeper": "shopkeeper",
	"guard": "ranger",
	"ranger": "ranger",
	"kid": "child_boy",
	"child": "child_boy",
	"lamplighter": "lamplighter",
	"sailor": "sailor",
	"lockkeeper": "hiker",
	"gardener": "town_woman",
	"elder": "elder_woman",
}

const COAT_BY_KEY := {
	"healer": Color8(224, 128, 148, 255),
	"shopkeeper": Color8(66, 126, 192, 255),
	"elder_man": Color8(144, 118, 86, 255),
	"elder_woman": Color8(168, 126, 158, 255),
	"town_man": Color8(72, 116, 168, 255),
	"town_woman": Color8(186, 98, 108, 255),
	"young_man": Color8(78, 152, 92, 255),
	"young_woman": Color8(208, 126, 92, 255),
	"child_boy": Color8(88, 146, 206, 255),
	"child_girl": Color8(216, 138, 174, 255),
	"ranger": Color8(64, 134, 86, 255),
	"scientist": Color8(198, 204, 214, 255),
	"sailor": Color8(66, 108, 176, 255),
	"gentleman": Color8(88, 72, 142, 255),
	"hiker": Color8(146, 92, 58, 255),
	"lamplighter": Color8(184, 144, 72, 255),
}

static var _rom_tex_cache: Dictionary = {}
static var _atlas_img_cache: Dictionary = {}
static var _fallback_cache: Dictionary = {}


static func clear_cache() -> void:
	_rom_tex_cache.clear()
	_atlas_img_cache.clear()
	_fallback_cache.clear()


static func resolve_sprite_key(sprite_key: String, role: String = "") -> String:
	var clean := sprite_key.strip_edges().to_lower()
	if not clean.is_empty():
		return clean
	var r := role.strip_edges().to_lower()
	if ROLE_TO_SPRITE.has(r):
		return str(ROLE_TO_SPRITE[r])
	return "town_woman"


static func normalize_facing(facing: String) -> String:
	var f := facing.strip_edges().to_upper()
	if f in ["S", "N", "W", "E"]:
		return f
	return "S"


static func resolve_texture(
	sprite_key: String,
	facing: String = "S",
	role: String = "",
	force_fallback: bool = false,
	cache_dir: String = AssetDB.DEFAULT_CACHE_DIR
) -> Texture2D:
	var key := resolve_sprite_key(sprite_key, role)
	var dir := normalize_facing(facing)

	if not force_fallback:
		var bundle: Variant = AssetDB.people_sprite_atlas(cache_dir)
		if bundle is Dictionary:
			var bdict: Dictionary = bundle
			var tex: Texture2D = bdict.get("texture", null)
			var info: Dictionary = bdict.get("json", {})
			var ppl_map: Dictionary = info.get("people", {})
			var target_key := key if ppl_map.has(key) else ("town_woman" if ppl_map.has("town_woman") else "")
			if tex != null and not target_key.is_empty():
				var entry: Dictionary = ppl_map[target_key]
				var rect_arr: Array = entry.get(dir, entry.get("S", []))
				if rect_arr.size() >= 4:
					var rid_id := tex.get_rid().get_id()
					var ckey := "%s|%s|%s|%d" % [cache_dir, target_key, dir, rid_id]
					if _rom_tex_cache.has(ckey):
						return _rom_tex_cache[ckey]
					var atlas_img: Image = _atlas_img_cache.get(rid_id, null)
					if atlas_img == null:
						atlas_img = tex.get_image()
						if atlas_img != null and not atlas_img.is_empty():
							_atlas_img_cache[rid_id] = atlas_img
					if atlas_img != null and not atlas_img.is_empty():
						var reg := Rect2i(int(rect_arr[0]), int(rect_arr[1]), int(rect_arr[2]), int(rect_arr[3]))
						var sub_tex := ImageTexture.create_from_image(atlas_img.get_region(reg))
						_rom_tex_cache[ckey] = sub_tex
						return sub_tex

	return _build_fallback_texture(key, dir)


static func _build_fallback_texture(key: String, facing: String) -> Texture2D:
	var ckey := "%s|%s" % [key, facing]
	if _fallback_cache.has(ckey):
		return _fallback_cache[ckey]

	# 16x32 native base scaled 2x nearest to 32x64 (matches Emerald OW sprite footprint)
	var img16 := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	img16.fill(Color(0, 0, 0, 0))
	var coat: Color = COAT_BY_KEY.get(key, Color8(66, 108, 176, 255))
	var outline := Color8(36, 40, 54, 255)
	var skin := Color8(238, 202, 168, 255)
	var hair := Color8(72, 56, 46, 255)
	if key == "elder_man" or key == "elder_woman":
		hair = Color8(204, 208, 214, 255)

	# Head rows 7..16
	for y in range(7, 17):
		for x in range(4, 12):
			var edge := (x == 4 or x == 11 or y == 7 or y == 16)
			if edge:
				img16.set_pixel(x, y, outline)
			elif y <= 10 or facing == "N":
				img16.set_pixel(x, y, hair)
			else:
				img16.set_pixel(x, y, skin)

	if facing == "S":
		img16.set_pixel(6, 13, outline)
		img16.set_pixel(9, 13, outline)
	elif facing == "W":
		img16.set_pixel(6, 13, outline)
	elif facing == "E":
		img16.set_pixel(9, 13, outline)

	# Torso rows 17..26
	for y in range(17, 27):
		for x in range(3, 13):
			var edge := (x == 3 or x == 12 or y == 17 or y == 26)
			img16.set_pixel(x, y, outline if edge else coat)

	# Legs rows 27..30
	for y in range(27, 31):
		for x in [5, 6, 9, 10]:
			img16.set_pixel(x, y, outline)

	var out := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(16):
			var c := img16.get_pixel(x, y)
			var dx := x * 2
			var dy := y * 2
			out.set_pixel(dx, dy, c)
			out.set_pixel(dx + 1, dy, c)
			out.set_pixel(dx, dy + 1, c)
			out.set_pixel(dx + 1, dy + 1, c)
	var tex := ImageTexture.create_from_image(out)
	_fallback_cache[ckey] = tex
	return tex
