class_name Gen5Cells
extends RefCounted

## Nitro NCER (RECN/KBEC) OAM cell parser and 96x96 Black/White sprite assembler (Item 45).
## Confirmed by tools/rom_spike/bw_sprite_spike.py:310-396.

const NitroGfxRef := preload("res://rom/nitro_gfx.gd")

const OAM_DIMENSIONS := {
	"0_0": Vector2i(8, 8),
	"0_1": Vector2i(16, 16),
	"0_2": Vector2i(32, 32),
	"0_3": Vector2i(64, 64),
	"1_0": Vector2i(16, 8),
	"1_1": Vector2i(32, 8),
	"1_2": Vector2i(32, 16),
	"1_3": Vector2i(64, 32),
	"2_0": Vector2i(8, 16),
	"2_1": Vector2i(8, 32),
	"2_2": Vector2i(16, 32),
	"2_3": Vector2i(32, 64),
}

static func parse_ncer(data: PackedByteArray) -> Dictionary:
	if data.size() < 48 or data.slice(0, 4).get_string_from_ascii() != "RECN":
		return {"ok": false, "error": "Invalid NCER magic"}
	if data.slice(16, 20).get_string_from_ascii() != "KBEC":
		return {"ok": false, "error": "Invalid KBEC chunk"}
	var n_banks := int(data.decode_u16(24))
	var bank_attr := int(data.decode_u16(26))
	var bank_table_rel := int(data.decode_u32(28))
	var mapping_mode := int(data.decode_u32(32))
	var entry_size := 16 if bank_attr == 1 else 8
	var bank_table_pos := 24 + bank_table_rel
	var oam_data_pos := bank_table_pos + n_banks * entry_size
	var tile_step := 1 << (mapping_mode & 0x03)

	var banks: Array = []
	for i in range(n_banks):
		var b_pos := bank_table_pos + i * entry_size
		if b_pos + 8 > data.size():
			break
		var n_oam := int(data.decode_u16(b_pos))
		var oam_off := int(data.decode_u32(b_pos + 4))
		var pos := oam_data_pos + oam_off
		var oams: Array = []
		for _j in range(n_oam):
			if pos + 6 > data.size():
				break
			var attr0 := int(data.decode_u16(pos))
			var attr1 := int(data.decode_u16(pos + 2))
			var attr2 := int(data.decode_u16(pos + 4))
			pos += 6
			var y := attr0 & 0xFF
			if y >= 128:
				y -= 256
			var shape := (attr0 >> 14) & 0x03
			var x := attr1 & 0x1FF
			if x >= 256:
				x -= 512
			var size := (attr1 >> 14) & 0x03
			var xflip := ((attr1 >> 12) & 1) != 0
			var yflip := ((attr1 >> 13) & 1) != 0
			var tile_off := attr2 & 0x3FF
			var dims: Vector2i = OAM_DIMENSIONS.get("%d_%d" % [shape, size], Vector2i(8, 8))
			oams.append({
				"x": x,
				"y": y,
				"w": dims.x,
				"h": dims.y,
				"tile_offset": tile_off,
				"tile_index": tile_off * tile_step,
				"xflip": xflip,
				"yflip": yflip,
			})
		banks.append(oams)
	return {
		"ok": true,
		"mapping_mode": mapping_mode,
		"tile_step": tile_step,
		"banks": banks,
	}

static func assemble_sprite_image(
	tile_bytes: PackedByteArray,
	palette: Array[Color],
	oams: Array,
	canvas_w: int = 96,
	canvas_h: int = 96
) -> Image:
	var tiles := NitroGfxRef.decode_linear_4bpp_tiles(tile_bytes)
	var num_tiles := tiles.size()
	var img := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := canvas_w / 2
	var cy := canvas_h / 2

	for idx in range(oams.size() - 1, -1, -1):
		var oam: Dictionary = oams[idx]
		var ox := int(oam["x"]) + cx
		var oy := int(oam["y"]) + cy
		var w := int(oam["w"])
		var h := int(oam["h"])
		var t_start := int(oam["tile_index"])
		var xflip := bool(oam["xflip"])
		var yflip := bool(oam["yflip"])
		var tw := w / 8
		var th := h / 8
		for ty in range(th):
			for tx in range(tw):
				var t_idx := t_start + ty * tw + tx
				if t_idx < 0 or t_idx >= num_tiles:
					continue
				var tile := tiles[t_idx]
				var draw_tx := (tw - 1 - tx) if xflip else tx
				var draw_ty := (th - 1 - ty) if yflip else ty
				for py in range(8):
					var src_py := (7 - py) if yflip else py
					var dst_y := oy + draw_ty * 8 + py
					if dst_y < 0 or dst_y >= canvas_h:
						continue
					for px in range(8):
						var src_px := (7 - px) if xflip else px
						var dst_x := ox + draw_tx * 8 + px
						if dst_x < 0 or dst_x >= canvas_w:
							continue
						var pal_idx := int(tile[src_py * 8 + src_px])
						if pal_idx > 0 and pal_idx < palette.size():
							img.set_pixel(dst_x, dst_y, palette[pal_idx])
	return img

static func compute_sprite_metrics(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var opaque_count := 0
	var distinct := {}
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	var rgb_list: Array[Vector3] = []

	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a8 > 0:
				opaque_count += 1
				var key := (c.r8 << 16) | (c.g8 << 8) | c.b8
				distinct[key] = true
				var v := Vector3(float(c.r8), float(c.g8), float(c.b8))
				rgb_list.append(v)
				sum_r += v.x
				sum_g += v.y
				sum_b += v.z

	if opaque_count == 0:
		return {
			"opaque_px": 0,
			"distinct_opaque_colors": 0,
			"rgb_variance": 0.0,
			"neighbor_coherence": 0.0,
			"seam_continuity": 0.0,
		}

	var mr := sum_r / float(opaque_count)
	var mg := sum_g / float(opaque_count)
	var mb := sum_b / float(opaque_count)
	var var_acc := 0.0
	for v in rgb_list:
		var dr := v.x - mr
		var dg := v.y - mg
		var db := v.z - mb
		var_acc += dr * dr + dg * dg + db * db
	var variance := var_acc / float(opaque_count)

	var same_nb := 0
	var total_nb := w * maxi(0, h - 1)
	var same_opaque_nb := 0
	var total_opaque_nb := 0
	for y in range(h):
		for x in range(w - 1):
			var c := img.get_pixel(x, y)
			var c2 := img.get_pixel(x + 1, y)
			var same_col := (c.a8 == 0 and c2.a8 == 0) or (c.a8 > 0 and c2.a8 > 0 and c.r8 == c2.r8 and c.g8 == c2.g8 and c.b8 == c2.b8)
			if same_col:
				same_nb += 1
			if c.a8 > 0 and c2.a8 > 0:
				total_opaque_nb += 1
				if same_col:
					same_opaque_nb += 1
	var canvas_coherence := float(same_nb) / float(w * maxi(1, w - 1)) if w > 1 else 0.0
	var opaque_coherence := float(same_opaque_nb) / float(total_opaque_nb) if total_opaque_nb > 0 else 0.0
	var coherence := minf(canvas_coherence, opaque_coherence + 0.25)

	var seam_matches := 0
	var seam_total := 0
	if w >= 65 and h >= 65:
		for y in range(h):
			var l := img.get_pixel(63, y)
			var r := img.get_pixel(64, y)
			if l.a8 > 0 or r.a8 > 0:
				seam_total += 1
				if (l.a8 > 0) == (r.a8 > 0):
					seam_matches += 1
		for x in range(w):
			var t := img.get_pixel(x, 63)
			var b := img.get_pixel(x, 64)
			if t.a8 > 0 or b.a8 > 0:
				seam_total += 1
				if (t.a8 > 0) == (b.a8 > 0):
					seam_matches += 1
	var seam_cont := float(seam_matches) / float(seam_total) if seam_total > 0 else 1.0

	return {
		"opaque_px": opaque_count,
		"distinct_opaque_colors": distinct.size(),
		"rgb_variance": variance,
		"neighbor_coherence": coherence,
		"seam_continuity": seam_cont,
	}

static func validate_sprite_metrics(metrics: Dictionary) -> Dictionary:
	var dc := int(metrics.get("distinct_opaque_colors", 0))
	if dc < 1 or dc > 16:
		return {"ok": false, "error": "distinct_opaque_colors=%d outside [1..16]" % dc}
	var op := int(metrics.get("opaque_px", 0))
	if op < 200 or op > 8800:
		return {"ok": false, "error": "opaque_px=%d outside [200..8800]" % op}
	var vr := float(metrics.get("rgb_variance", 0.0))
	if vr < 500.0:
		return {"ok": false, "error": "rgb_variance=%.2f < 500.0" % vr}
	var coh := float(metrics.get("neighbor_coherence", 0.0))
	if coh < 0.65:
		return {"ok": false, "error": "neighbor_coherence=%.4f < 0.65" % coh}
	var seam := float(metrics.get("seam_continuity", 0.0))
	if seam < 0.40:
		return {"ok": false, "error": "seam_continuity=%.4f < 0.40" % seam}
	return {"ok": true}
