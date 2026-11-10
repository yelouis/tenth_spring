class_name NitroGfx
extends RefCounted

## Nitro NCGR (RGCN/RAHC 4bpp tiles) and NCLR (RLCN/TTLP BGR555 palette) decoders (Item 45).
## Confirmed by tools/rom_spike/bw_sprite_spike.py:265-308.

static func parse_nclr(data: PackedByteArray) -> Array[Color]:
	var pal: Array[Color] = []
	if data.size() < 40 or data.slice(0, 4).get_string_from_ascii() != "RLCN":
		return pal
	if data.slice(16, 20).get_string_from_ascii() != "TTLP":
		return pal
	var pal_offset := 40
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
