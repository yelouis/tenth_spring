class_name Gen3Tiles
extends RefCounted

## GBA Gen 3 (Pokémon Emerald) tileset, metatile, and 16x16 overworld sprite renderer (Item 55).
## Extracts 4bpp 8x8 tiles, BGR555 palettes, and 2-layer 16x16 metatiles from a clean BPEE ROM
## and scales them 2x nearest-neighbour to 32x32 RGBA8 images for Tenth Spring's landscape atlas.

const GbaRomRef := preload("res://rom/gba_rom.gd")

const PRIMARY_TILESET_OFFSET := 0x3DF704
const TILESET_RECORD_SIZE := 24
const PRIMARY_METATILE_LIMIT := 512
const NUM_PALETTES := 16
const COLORS_PER_PALETTE := 16
const PRIMARY_PALETTE_SLOTS := 6
const METATILE_BYTE_SIZE := 16


static func bgr555_to_color(c16: int) -> Color:
	var r5 := c16 & 0x1F
	var g5 := (c16 >> 5) & 0x1F
	var b5 := (c16 >> 10) & 0x1F
	var r8 := (r5 << 3) | (r5 >> 2)
	var g8 := (g5 << 3) | (g5 >> 2)
	var b8 := (b5 << 3) | (b5 >> 2)
	return Color8(r8, g8, b8, 255)


static func _parse_palettes(raw_pal: PackedByteArray) -> Array:
	var pals: Array = []
	for p_idx in range(NUM_PALETTES):
		var pal: Array[Color] = []
		var base := p_idx * COLORS_PER_PALETTE * 2
		for c_idx in range(COLORS_PER_PALETTE):
			var off := base + c_idx * 2
			if off + 1 < raw_pal.size():
				var c16 := int(raw_pal[off]) | (int(raw_pal[off + 1]) << 8)
				pal.append(bgr555_to_color(c16))
			else:
				pal.append(Color8(0, 0, 0, 255))
		pals.append(pal)
	return pals


static func decode_tileset_record(rom: Variant, index: int) -> Dictionary:
	if rom == null or index < 0:
		return {"ok": false, "error": "Invalid ROM or tileset index."}
	var off := PRIMARY_TILESET_OFFSET + index * TILESET_RECORD_SIZE
	var is_comp: int = rom.read_u8(off)
	var is_sec: int = rom.read_u8(off + 1)
	var tiles_ptr: int = rom.read_u32(off + 4)
	var pal_ptr: int = rom.read_u32(off + 8)
	var mt_ptr: int = rom.read_u32(off + 12)
	var attr_ptr: int = rom.read_u32(off + 16)
	var tiles_off := GbaRomRef.rom_ptr_to_offset(tiles_ptr)
	var pal_off := GbaRomRef.rom_ptr_to_offset(pal_ptr)
	var mt_off := GbaRomRef.rom_ptr_to_offset(mt_ptr)
	var attr_off := GbaRomRef.rom_ptr_to_offset(attr_ptr)
	if tiles_off < 0 or pal_off < 0 or mt_off < 0:
		return {"ok": false, "error": "Invalid pointer in tileset %d at 0x%x." % [index, off]}

	var tiles_bytes := PackedByteArray()
	if is_comp != 0:
		var dec: Dictionary = rom.decompress_lz77(tiles_off)
		if not bool(dec.get("ok", false)):
			return {"ok": false, "error": "LZ77 decode failed for tileset %d: %s" % [index, str(dec.get("error", ""))]}
		tiles_bytes = dec["data"]
	else:
		tiles_bytes = rom.read_bytes(tiles_off, 512 * 32)
		if tiles_bytes.is_empty():
			return {"ok": false, "error": "Uncompressed tile read failed for tileset %d." % index}

	var pal_bytes: PackedByteArray = rom.read_bytes(pal_off, NUM_PALETTES * COLORS_PER_PALETTE * 2)
	if pal_bytes.size() < NUM_PALETTES * COLORS_PER_PALETTE * 2:
		return {"ok": false, "error": "Palette read truncated for tileset %d." % index}

	var mt_len := 8192
	if attr_off > mt_off and attr_off - mt_off <= 16384:
		mt_len = attr_off - mt_off
	var mt_bytes: PackedByteArray = rom.read_bytes(mt_off, mt_len)
	if mt_bytes.size() < METATILE_BYTE_SIZE:
		return {"ok": false, "error": "Metatile table truncated for tileset %d." % index}

	return {
		"ok": true,
		"index": index,
		"is_secondary": is_sec != 0,
		"tiles": tiles_bytes,
		"palettes": _parse_palettes(pal_bytes),
		"metatiles": mt_bytes,
		"num_metatiles": mt_bytes.size() / METATILE_BYTE_SIZE,
	}


static func _combined_palettes(primary: Dictionary, secondary: Variant) -> Array:
	var pri_pals: Array = primary.get("palettes", [])
	var sec_pals: Array = (secondary as Dictionary).get("palettes", pri_pals) if secondary is Dictionary else pri_pals
	var combined: Array = []
	for i in range(NUM_PALETTES):
		if i < PRIMARY_PALETTE_SLOTS and i < pri_pals.size():
			combined.append(pri_pals[i])
		elif i < sec_pals.size():
			combined.append(sec_pals[i])
		elif i < pri_pals.size():
			combined.append(pri_pals[i])
		else:
			combined.append([])
	return combined


static func _blit_4bpp_tile(
	img: Image,
	tile_bytes: PackedByteArray,
	tile_offset: int,
	pal: Array,
	dst_x: int,
	dst_y: int,
	hflip: bool,
	vflip: bool,
	transparent_zero: bool
) -> void:
	if tile_offset < 0 or tile_offset + 32 > tile_bytes.size() or pal.size() < 16:
		return
	for py in range(8):
		var sy := (7 - py) if vflip else py
		var row_base := tile_offset + sy * 4
		for px in range(8):
			var sx := (7 - px) if hflip else px
			var b := int(tile_bytes[row_base + (sx >> 1)])
			var c_idx := (b & 0x0F) if (sx & 1) == 0 else (b >> 4)
			if transparent_zero and c_idx == 0:
				continue
			img.set_pixel(dst_x + px, dst_y + py, pal[c_idx])


static func _render_metatile_subrange_16(
	primary: Dictionary,
	secondary: Variant,
	metatile_id: int,
	initial_color: Color,
	start_sub: int,
	end_sub: int
) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(initial_color)
	var pals := _combined_palettes(primary, secondary)
	var pri_tiles: PackedByteArray = primary.get("tiles", PackedByteArray())
	var sec_tiles: PackedByteArray = (secondary as Dictionary).get("tiles", PackedByteArray()) if secondary is Dictionary else PackedByteArray()

	var mt_bytes: PackedByteArray
	var mt_local_id: int
	if metatile_id < PRIMARY_METATILE_LIMIT:
		mt_bytes = primary.get("metatiles", PackedByteArray())
		mt_local_id = metatile_id
	elif secondary is Dictionary:
		mt_bytes = (secondary as Dictionary).get("metatiles", PackedByteArray())
		mt_local_id = metatile_id - PRIMARY_METATILE_LIMIT
	else:
		return img

	var mt_base := mt_local_id * METATILE_BYTE_SIZE
	if mt_local_id < 0 or mt_base + METATILE_BYTE_SIZE > mt_bytes.size():
		return img

	const SUB_XY := [
		Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 8), Vector2i(8, 8),
		Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 8), Vector2i(8, 8),
	]
	for sub in range(start_sub, end_sub):
		var off := mt_base + sub * 2
		var entry := int(mt_bytes[off]) | (int(mt_bytes[off + 1]) << 8)
		var tile_idx := entry & 0x3FF
		var hflip := ((entry >> 10) & 1) != 0
		var vflip := ((entry >> 11) & 1) != 0
		var pal_idx := (entry >> 12) & 0x0F
		var pal: Array = pals[pal_idx] if pal_idx < pals.size() else []
		var src_bytes: PackedByteArray
		var src_off: int
		if tile_idx < PRIMARY_METATILE_LIMIT:
			src_bytes = pri_tiles
			src_off = tile_idx * 32
		else:
			src_bytes = sec_tiles
			src_off = (tile_idx - PRIMARY_METATILE_LIMIT) * 32
		var pos: Vector2i = SUB_XY[sub]
		_blit_4bpp_tile(img, src_bytes, src_off, pal, pos.x, pos.y, hflip, vflip, true)
	return img


static func render_metatile_16(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	var pals := _combined_palettes(primary, secondary)
	var backdrop := Color8(0, 0, 0, 255)
	if not pals.is_empty() and (pals[0] as Array).size() > 0:
		backdrop = pals[0][0]
	# Fill with global BG palette 0 colour 0 so colour-0 pixels in Layer 0 palettes stay transparent to backdrop.
	return _render_metatile_subrange_16(primary, secondary, metatile_id, backdrop, 0, 8)


static func render_indoor_metatile_16(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	# Indoor rooms always composite over pure black backdrop (#000000), ignoring pals[0][0].
	return _render_metatile_subrange_16(primary, secondary, metatile_id, Color8(0, 0, 0, 255), 0, 8)


static func render_metatile_layer1_16(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	# Layer-1-only extraction over transparent background for rugs, wall art, and furniture overlays.
	return _render_metatile_subrange_16(primary, secondary, metatile_id, Color(0, 0, 0, 0), 4, 8)


static func scale_2x_nearest(img16: Image) -> Image:
	var w := img16.get_width()
	var h := img16.get_height()
	var out := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c := img16.get_pixel(x, y)
			var dx := x * 2
			var dy := y * 2
			out.set_pixel(dx, dy, c)
			out.set_pixel(dx + 1, dy, c)
			out.set_pixel(dx, dy + 1, c)
			out.set_pixel(dx + 1, dy + 1, c)
	return out


static func render_metatile_32(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	return scale_2x_nearest(render_metatile_16(primary, secondary, metatile_id))


static func render_indoor_metatile_32(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	return scale_2x_nearest(render_indoor_metatile_16(primary, secondary, metatile_id))


static func render_metatile_layer1_32(primary: Dictionary, secondary: Variant, metatile_id: int) -> Image:
	return scale_2x_nearest(render_metatile_layer1_16(primary, secondary, metatile_id))


static func render_object_over_metatile_32(
	rom: Variant,
	primary: Dictionary,
	base_metatile: int,
	frame_offset: int,
	palette_offset: int
) -> Image:
	var img16 := render_metatile_16(primary, null, base_metatile)
	if rom == null:
		return scale_2x_nearest(img16)
	var pal_bytes: PackedByteArray = rom.read_bytes(palette_offset, 32)
	var frame_bytes: PackedByteArray = rom.read_bytes(frame_offset, 128)
	if pal_bytes.size() < 32 or frame_bytes.size() < 128:
		return scale_2x_nearest(img16)
	var pal: Array[Color] = []
	for c_idx in range(16):
		var c16 := int(pal_bytes[c_idx * 2]) | (int(pal_bytes[c_idx * 2 + 1]) << 8)
		pal.append(bgr555_to_color(c16))
	const QUAD := [Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 8), Vector2i(8, 8)]
	for q in range(4):
		var pos: Vector2i = QUAD[q]
		_blit_4bpp_tile(img16, frame_bytes, q * 32, pal, pos.x, pos.y, false, false, true)
	return scale_2x_nearest(img16)
