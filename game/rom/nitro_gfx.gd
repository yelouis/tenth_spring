class_name NitroGfx
extends RefCounted

## Nitro NCGR (RGCN/RAHC 4bpp tiles) and NCLR (RLCN/TTLP BGR555 palette) decoders (Item 45).
## Confirmed by tools/rom_spike/bw_sprite_spike.py:265-308.

static func _decode_bgr555_16(data: PackedByteArray, pal_offset: int) -> Array[Color]:
	var pal: Array[Color] = []
	var count := mini(16, (data.size() - pal_offset) / 2)
	pal.resize(16)
	for i in range(16):
		if i < count:
			var v := int(data.decode_u16(pal_offset + i * 2))
			var r8 := ((v & 0x1F) * 255 + 15) / 31
			var g8 := (((v >> 5) & 0x1F) * 255 + 15) / 31
			var b8 := (((v >> 10) & 0x1F) * 255 + 15) / 31
			var a8 := 0 if i == 0 else 255
			pal[i] = Color8(r8, g8, b8, a8)
		else:
			pal[i] = Color8(0, 0, 0, 0)
	return pal


static func parse_nclr(data: PackedByteArray) -> Array[Color]:
	var pal: Array[Color] = []
	if data.size() < 40 or data.slice(0, 4).get_string_from_ascii() != "RLCN":
		return pal
	if data.slice(16, 20).get_string_from_ascii() != "TTLP":
		return pal
	return _decode_bgr555_16(data, 40)


static func parse_nclr_multi(data: PackedByteArray, max_palettes: int = 8) -> Array:
	var pals: Array = []
	if data.size() < 40 or data.slice(0, 4).get_string_from_ascii() != "RLCN":
		return pals
	if data.slice(16, 20).get_string_from_ascii() != "TTLP":
		return pals
	var pal_count := mini(max_palettes, maxi(0, (data.size() - 40) / 32))
	for p in range(pal_count):
		pals.append(_decode_bgr555_16(data, 40 + p * 32))
	return pals


static func decode_box_icon_32(
	ncgr_bytes: PackedByteArray,
	icon_palettes: Array,
	front_pal: Array = []
) -> Image:
	var parsed := parse_ncgr(ncgr_bytes)
	if not bool(parsed.get("ok", false)) or icon_palettes.is_empty():
		return null
	var tile_bytes: PackedByteArray = parsed.get("tile_bytes", PackedByteArray())
	if tile_bytes.size() < 512:
		return null

	var tiles := decode_linear_4bpp_tiles(tile_bytes.slice(0, 512))
	if tiles.size() < 16:
		return null

	var best_pal_idx := 0
	if front_pal.size() >= 16:
		var cand_limit := mini(3, icon_palettes.size())
		var best_score := 1e18
		for pi in range(cand_limit):
			var ipal: Array = icon_palettes[pi]
			var score := 0.0
			for t in range(16):
				var px_indices: PackedByteArray = tiles[t]
				for idx in px_indices:
					if idx == 0:
						continue
					var c: Color = ipal[idx]
					var min_d := 1e18
					for fi in range(1, 16):
						var fc: Color = front_pal[fi]
						var dr := float(c.r8 - fc.r8)
						var dg := float(c.g8 - fc.g8)
						var db := float(c.b8 - fc.b8)
						var d := dr * dr + dg * dg + db * db
						if d < min_d:
							min_d = d
					score += min_d
			if score < best_score:
				best_score = score
				best_pal_idx = pi

	var chosen_pal: Array = icon_palettes[best_pal_idx]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for ty in range(4):
		for tx in range(4):
			var px_arr: PackedByteArray = tiles[ty * 4 + tx]
			for ry in range(8):
				for rx in range(8):
					var ci := int(px_arr[ry * 8 + rx])
					if ci != 0 and ci < chosen_pal.size():
						img.set_pixel(tx * 8 + rx, ty * 8 + ry, chosen_pal[ci])
	return img

static func parse_ncgr(data: PackedByteArray) -> Dictionary:
	if data.size() < 48 or data.slice(0, 4).get_string_from_ascii() != "RGCN":
		return {"ok": false, "error": "Invalid NCGR magic"}
	if data.slice(16, 20).get_string_from_ascii() != "RAHC":
		return {"ok": false, "error": "Invalid RAHC chunk"}
	var height_tiles := int(data.decode_u16(24))
	var width_tiles := int(data.decode_u16(26))
	var bit_depth := int(data.decode_u32(28))
	var mapping := int(data.decode_u32(32))
	var flags := int(data.decode_u32(36))
	var data_size := int(data.decode_u32(40))
	var tile_bytes := data.slice(48, mini(data.size(), 48 + data_size))
	return {
		"ok": true,
		"width_tiles": width_tiles,
		"height_tiles": height_tiles,
		"bit_depth": bit_depth,
		"mapping": mapping,
		"flags": flags,
		"data_size": data_size,
		"tile_bytes": tile_bytes,
		"num_tiles": tile_bytes.size() / 32,
	}

static func decode_linear_4bpp_tiles(tile_bytes: PackedByteArray) -> Array[PackedByteArray]:
	var num_tiles := tile_bytes.size() / 32
	var tiles: Array[PackedByteArray] = []
	tiles.resize(num_tiles)
	for t in range(num_tiles):
		var base := t * 32
		var pixels := PackedByteArray()
		pixels.resize(64)
		for i in range(32):
			var b := int(tile_bytes[base + i])
			pixels[i * 2] = b & 0x0F
			pixels[i * 2 + 1] = (b >> 4) & 0x0F
		tiles[t] = pixels
	return tiles
