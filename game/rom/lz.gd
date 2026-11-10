class_name NitroLz
extends RefCounted

## Pure-GDScript Nitro LZ10 (0x10) and LZ11 (0x11) decompressor (Item 45).
## Confirmed by tools/rom_spike/bw_sprite_spike.py:194-262.

const RAW_MAGICS := {
	"RGCN": true,
	"RLCN": true,
	"RECN": true,
	"RNAN": true,
	"RCMN": true,
	"RAMN": true,
}

static func decompress(data: PackedByteArray) -> Dictionary:
	var n := data.size()
	if n < 4:
		return {"ok": true, "format": "RAW", "data": data}
	var magic := data.slice(0, 4).get_string_from_ascii()
	if RAW_MAGICS.has(magic):
		return {"ok": true, "format": "RAW", "data": data}
	var tag := int(data[0])
	if tag != 0x10 and tag != 0x11:
		return {"ok": true, "format": "RAW", "data": data}
	var dec_len := int(data[1]) | (int(data[2]) << 8) | (int(data[3]) << 16)
	var src := 4
	if tag == 0x11 and dec_len == 0:
		if n < 8:
			return {"ok": false, "error": "Truncated LZ11 extended header"}
		dec_len = int(data.decode_u32(4))
		src = 8
	# Guard: a 16-entry raw part-offset table starts with u32 16 (0x10 0x00 0x00 0x00 -> dec_len == 0).
	if dec_len == 0:
		return {"ok": true, "format": "RAW", "data": data}
	if dec_len < 0 or dec_len > 4 * 1024 * 1024:
		return {"ok": false, "error": "Unreasonable LZ decompressed length: %d" % dec_len}

	var out := PackedByteArray()
	out.resize(dec_len)
	var dst := 0

	if tag == 0x10:
		while dst < dec_len and src < n:
			var flags := int(data[src])
			src += 1
			for bit in range(8):
				if dst >= dec_len or src >= n:
					break
				if (flags & (0x80 >> bit)) == 0:
					out[dst] = data[src]
					dst += 1
					src += 1
				else:
					if src + 1 >= n:
						return {"ok": false, "error": "Truncated LZ10 back-reference"}
					var b0 := int(data[src])
					var b1 := int(data[src + 1])
					src += 2
					var length := (b0 >> 4) + 3
					var disp := (((b0 & 0x0F) << 8) | b1) + 1
					if disp > dst:
						return {"ok": false, "error": "LZ10 displacement %d > output pos %d" % [disp, dst]}
					for _k in range(length):
						if dst >= dec_len:
							break
						out[dst] = out[dst - disp]
						dst += 1
		return {"ok": true, "format": "LZ10", "data": out}

	while dst < dec_len and src < n:
		var flags := int(data[src])
		src += 1
		for bit in range(8):
			if dst >= dec_len or src >= n:
				break
			if (flags & (0x80 >> bit)) == 0:
				out[dst] = data[src]
				dst += 1
				src += 1
			else:
				var b0 := int(data[src])
				src += 1
				var indicator := b0 >> 4
				var length := 0
				var disp := 0
				if indicator == 0:
					if src + 1 >= n:
						return {"ok": false, "error": "Truncated LZ11 mode-0 reference"}
					var b1 := int(data[src])
					var b2 := int(data[src + 1])
					src += 2
					length = (((b0 & 0x0F) << 4) | (b1 >> 4)) + 0x11
					disp = (((b1 & 0x0F) << 8) | b2) + 1
				elif indicator == 1:
					if src + 2 >= n:
						return {"ok": false, "error": "Truncated LZ11 mode-1 reference"}
					var b1 := int(data[src])
					var b2 := int(data[src + 1])
					var b3 := int(data[src + 2])
					src += 3
					length = (((b0 & 0x0F) << 12) | (b1 << 4) | (b2 >> 4)) + 0x111
					disp = (((b2 & 0x0F) << 8) | b3) + 1
				else:
					if src >= n:
						return {"ok": false, "error": "Truncated LZ11 short reference"}
					var b1 := int(data[src])
					src += 1
					length = indicator + 1
					disp = (((b0 & 0x0F) << 8) | b1) + 1
				if disp > dst:
					return {"ok": false, "error": "LZ11 displacement %d > output pos %d" % [disp, dst]}
				for _k in range(length):
					if dst >= dec_len:
						break
					out[dst] = out[dst - disp]
					dst += 1
	return {"ok": true, "format": "LZ11", "data": out}
