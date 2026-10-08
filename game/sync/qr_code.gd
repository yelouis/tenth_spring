# Ported from Nayuki's QR Code generator (commit 3c6d0b3cefb4e049dc337e82237c9644399716a8)
# https://github.com/nayuki/QR-Code-generator
#
# Copyright (c) Project Nayuki. (MIT License)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# - The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
# - The Software is provided "as is", without warranty of any kind, express or
#   implied, including but not limited to the warranties of merchantability,
#   fitness for a particular purpose and noninfringement. In no event shall the
#   authors or copyright holders be liable for any claim, damages or other
#   liability, whether in an action of contract, tort or otherwise, arising from,
#   out of or in connection with the Software or the use or other dealings in the
#   Software.

class_name QrCode
extends RefCounted

const MIN_VERSION: int = 1
const MAX_VERSION: int = 40

const _PENALTY_N1: int = 3
const _PENALTY_N2: int = 3
const _PENALTY_N3: int = 40
const _PENALTY_N4: int = 10

# ECC Medium codewords per block (index 0 is unused, versions 1 to 40)
const _ECC_CODEWORDS_PER_BLOCK: Array[int] = [
	-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28
]

# Number of error correction blocks for ECC Medium (versions 1 to 40)
const _NUM_ERROR_CORRECTION_BLOCKS: Array[int] = [
	-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49
]

static func encode_text(text: String) -> Array:
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = -1
	for v in range(MIN_VERSION, MAX_VERSION + 1):
		var capacity_bits: int = _get_num_data_codewords(v) * 8
		var num_char_bits: int = 8 if v < 10 else 16
		var used_bits: int = 4 + num_char_bits + data.size() * 8
		if used_bits <= capacity_bits:
			version = v
			break

	if version == -1:
		push_error("QrCode: Text data too long to fit in QR Code")
		return []

	var capacity_bits: int = _get_num_data_codewords(version) * 8
	var num_char_bits: int = 8 if version < 10 else 16

	# Build bit stream: Mode (4 bits: 0100 for Byte mode) + char count + data
	var bit_buffer: Array[int] = []
	_append_bits(bit_buffer, 0x04, 4)
	_append_bits(bit_buffer, data.size(), num_char_bits)
	for b in data:
		_append_bits(bit_buffer, b, 8)

	# Terminator (up to 4 bits of 0)
	var term_bits: int = mini(4, capacity_bits - bit_buffer.size())
	_append_bits(bit_buffer, 0, term_bits)

	# Pad to byte boundary
	var pad_zeros: int = (8 - (bit_buffer.size() % 8)) % 8
	_append_bits(bit_buffer, 0, pad_zeros)

	# Pad alternating bytes 0xEC, 0x11
	var pad_bytes = [0xEC, 0x11]
	var pad_idx = 0
	while bit_buffer.size() < capacity_bits:
		_append_bits(bit_buffer, pad_bytes[pad_idx], 8)
		pad_idx = (pad_idx + 1) % 2

	# Pack bits into data codewords
	var data_codewords = PackedByteArray()
	data_codewords.resize(bit_buffer.size() / 8)
	data_codewords.fill(0)
	for i in range(bit_buffer.size()):
		data_codewords[i >> 3] |= (bit_buffer[i] << (7 - (i & 7)))

	# Symbol setup
	var size: int = version * 4 + 17
	var modules: Array = []
	var is_function: Array = []
	for y in range(size):
		var m_row: Array = []
		var f_row: Array = []
		m_row.resize(size)
		f_row.resize(size)
		m_row.fill(false)
		f_row.fill(false)
		modules.append(m_row)
		is_function.append(f_row)

	# Draw function patterns
	_draw_function_patterns(modules, is_function, version, size)

	# Add ECC and interleave
	var all_codewords: PackedByteArray = _add_ecc_and_interleave(data_codewords, version)

	# Draw codewords
	_draw_codewords(modules, is_function, all_codewords, version, size)

	# Choose best mask by penalty score
	var best_mask: int = 0
	var min_penalty: int = 2147483647
	for mask in range(8):
		_apply_mask(modules, is_function, mask, size)
		_draw_format_bits(modules, is_function, mask, size)
		var penalty: int = _get_penalty_score(modules, size)
		if penalty < min_penalty:
			min_penalty = penalty
			best_mask = mask
		_apply_mask(modules, is_function, mask, size) # Undo mask

	# Apply final best mask
	_apply_mask(modules, is_function, best_mask, size)
	_draw_format_bits(modules, is_function, best_mask, size)

	return modules

static func render_to_texture(matrix: Array, scale: int = 4) -> ImageTexture:
	var size: int = matrix.size()
	if size == 0:
		return null
	var border: int = 4 # 4-module quiet zone
	var img_size: int = (size + border * 2) * scale
	var img: Image = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)

	for y in range(size):
		for x in range(size):
			if matrix[y][x]:
				var px: int = (x + border) * scale
				var py: int = (y + border) * scale
				for dy in range(scale):
					for dx in range(scale):
						img.set_pixel(px + dx, py + dy, Color.BLACK)

	return ImageTexture.create_from_image(img)

static func _append_bits(bb: Array[int], val: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bb.append((val >> i) & 1)

static func _draw_function_patterns(modules: Array, is_func: Array, version: int, size: int) -> void:
	# Timing patterns
	for i in range(size):
		_set_function_module(modules, is_func, 6, i, i % 2 == 0)
		_set_function_module(modules, is_func, i, 6, i % 2 == 0)

	# 3 Finder patterns
	_draw_finder_pattern(modules, is_func, 3, 3, size)
	_draw_finder_pattern(modules, is_func, size - 4, 3, size)
	_draw_finder_pattern(modules, is_func, 3, size - 4, size)

	# Alignment patterns
	var align_pos = _get_alignment_pattern_positions(version)
	var num_align = align_pos.size()
	for i in range(num_align):
		for j in range(num_align):
			if (i == 0 and j == 0) or (i == 0 and j == num_align - 1) or (i == num_align - 1 and j == 0):
				continue
			_draw_alignment_pattern(modules, is_func, align_pos[i], align_pos[j])

	# Format bits dummy placeholder
	_draw_format_bits(modules, is_func, 0, size)

	# Version bits (version >= 7)
	if version >= 7:
		_draw_version(modules, is_func, version, size)

static func _draw_finder_pattern(modules: Array, is_func: Array, x: int, y: int, size: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var xx: int = x + dx
			var yy: int = y + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				var dist: int = maxi(absi(dx), absi(dy))
				_set_function_module(modules, is_func, xx, yy, dist != 2 and dist != 4)

static func _draw_alignment_pattern(modules: Array, is_func: Array, x: int, y: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var dist: int = maxi(absi(dx), absi(dy))
			_set_function_module(modules, is_func, x + dx, y + dy, dist != 1)

static func _set_function_module(modules: Array, is_func: Array, x: int, y: int, is_dark: bool) -> void:
	modules[y][x] = is_dark
	is_func[y][x] = true

static func _draw_format_bits(modules: Array, is_func: Array, mask: int, size: int) -> void:
	# Format bits for ECC Medium (formatbits = 0)
	var data: int = mask
	var rem: int = data
	for _i in range(10):
		rem = (rem << 1) ^ (((rem >> 9) & 1) * 0x537)
	var bits: int = ((data << 10) | rem) ^ 0x5412

	# First copy
	for i in range(6):
		_set_function_module(modules, is_func, 8, i, (bits >> i) & 1 != 0)
	_set_function_module(modules, is_func, 8, 7, (bits >> 6) & 1 != 0)
	_set_function_module(modules, is_func, 8, 8, (bits >> 7) & 1 != 0)
	_set_function_module(modules, is_func, 7, 8, (bits >> 8) & 1 != 0)
	for i in range(9, 15):
		_set_function_module(modules, is_func, 14 - i, 8, (bits >> i) & 1 != 0)

	# Second copy
	for i in range(8):
		_set_function_module(modules, is_func, size - 1 - i, 8, (bits >> i) & 1 != 0)
	for i in range(8, 15):
		_set_function_module(modules, is_func, 8, size - 15 + i, (bits >> i) & 1 != 0)
	_set_function_module(modules, is_func, 8, size - 8, true)

static func _draw_version(modules: Array, is_func: Array, version: int, size: int) -> void:
	var rem: int = version
	for _i in range(12):
		rem = (rem << 1) ^ (((rem >> 11) & 1) * 0x1F25)
	var bits: int = (version << 12) | rem

	for i in range(18):
		var bit: bool = (bits >> i) & 1 != 0
		var a: int = size - 11 + (i % 3)
		var b: int = i / 3
		_set_function_module(modules, is_func, a, b, bit)
		_set_function_module(modules, is_func, b, a, bit)

static func _add_ecc_and_interleave(data: PackedByteArray, version: int) -> PackedByteArray:
	var num_blocks: int = _NUM_ERROR_CORRECTION_BLOCKS[version]
	var block_ecc_len: int = _ECC_CODEWORDS_PER_BLOCK[version]
	var raw_codewords: int = _get_num_raw_data_modules(version) / 8
	var num_short_blocks: int = num_blocks - (raw_codewords % num_blocks)
	var short_block_len: int = raw_codewords / num_blocks

	var blocks: Array[PackedByteArray] = []
	var rs_div: PackedByteArray = _reed_solomon_compute_divisor(block_ecc_len)
	var k: int = 0
	for i in range(num_blocks):
		var blk_data_len = short_block_len - block_ecc_len + (0 if i < num_short_blocks else 1)
		var dat = data.slice(k, k + blk_data_len)
		k += blk_data_len
		var ecc = _reed_solomon_compute_remainder(dat, rs_div)
		if i < num_short_blocks:
			dat.append(0)
		var full_block = PackedByteArray()
		full_block.append_array(dat)
		full_block.append_array(ecc)
		blocks.append(full_block)

	var result = PackedByteArray()
	result.resize(raw_codewords)
	var out_idx: int = 0
	for i in range(blocks[0].size()):
		for j in range(num_blocks):
			if i != (short_block_len - block_ecc_len) or j >= num_short_blocks:
				result[out_idx] = blocks[j][i]
				out_idx += 1
	return result

static func _draw_codewords(modules: Array, is_func: Array, data: PackedByteArray, version: int, size: int) -> void:
	var bit_index: int = 0
	var total_bits: int = data.size() * 8
	var right: int = size - 1
	while right > 0:
		if right == 6:
			right = 5
		for vert in range(size):
			for j in range(2):
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = (size - 1 - vert) if upward else vert
				if not is_func[y][x] and bit_index < total_bits:
					var bit: bool = (data[bit_index >> 3] >> (7 - (bit_index & 7))) & 1 != 0
					modules[y][x] = bit
					bit_index += 1
		right -= 2

static func _apply_mask(modules: Array, is_func: Array, mask: int, size: int) -> void:
	for y in range(size):
		for x in range(size):
			if not is_func[y][x]:
				var invert: bool = false
				match mask:
					0: invert = ((x + y) % 2) == 0
					1: invert = (y % 2) == 0
					2: invert = (x % 3) == 0
					3: invert = ((x + y) % 3) == 0
					4: invert = ((x / 3 + y / 2) % 2) == 0
					5: invert = ((x * y) % 2 + (x * y) % 3) == 0
					6: invert = (((x * y) % 2 + (x * y) % 3) % 2) == 0
					7: invert = (((x + y) % 2 + (x * y) % 3) % 2) == 0
				if invert:
					modules[y][x] = not modules[y][x]

static func _get_penalty_score(modules: Array, size: int) -> int:
	var result: int = 0

	# Penalty N1 & N3 across rows
	for y in range(size):
		var run_color: bool = false
		var run_x: int = 0
		var history: Array[int] = [0, 0, 0, 0, 0, 0, 0]
		for x in range(size):
			if modules[y][x] == run_color:
				run_x += 1
				if run_x == 5:
					result += _PENALTY_N1
				elif run_x > 5:
					result += 1
			else:
				_history_add(history, run_x, size)
				if not run_color:
					result += _pattern_count(history) * _PENALTY_N3
				run_color = modules[y][x]
				run_x = 1
		if run_color:
			_history_add(history, run_x, size)
			run_x = 0
		run_x += size
		_history_add(history, run_x, size)
		result += _pattern_count(history) * _PENALTY_N3

	# Penalty N1 & N3 across columns
	for x in range(size):
		var run_color: bool = false
		var run_y: int = 0
		var history: Array[int] = [0, 0, 0, 0, 0, 0, 0]
		for y in range(size):
			if modules[y][x] == run_color:
				run_y += 1
				if run_y == 5:
					result += _PENALTY_N1
				elif run_y > 5:
					result += 1
			else:
				_history_add(history, run_y, size)
				if not run_color:
					result += _pattern_count(history) * _PENALTY_N3
				run_color = modules[y][x]
				run_y = 1
		if run_color:
			_history_add(history, run_y, size)
			run_y = 0
		run_y += size
		_history_add(history, run_y, size)
		result += _pattern_count(history) * _PENALTY_N3

	# Penalty N2: 2x2 blocks
	for y in range(size - 1):
		for x in range(size - 1):
			if modules[y][x] == modules[y][x + 1] and modules[y][x] == modules[y + 1][x] and modules[y][x] == modules[y + 1][x + 1]:
				result += _PENALTY_N2

	# Penalty N4: balance of dark/light modules
	var dark: int = 0
	for y in range(size):
		for x in range(size):
			if modules[y][x]:
				dark += 1
	var total: int = size * size
	var k: int = (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += k * _PENALTY_N4

	return result

static func _history_add(history: Array[int], run_len: int, size: int) -> void:
	if history[0] == 0:
		run_len += size
	history.pop_back()
	history.push_front(run_len)

static func _pattern_count(history: Array[int]) -> int:
	var n: int = history[1]
	var core: bool = n > 0 and (history[2] == n and history[4] == n and history[5] == n and history[3] == n * 3)
	var count: int = 0
	if core and history[0] >= n * 4 and history[6] >= n:
		count += 1
	if core and history[6] >= n * 4 and history[0] >= n:
		count += 1
	return count

static func _get_alignment_pattern_positions(version: int) -> Array[int]:
	if version == 1:
		var empty: Array[int] = []
		return empty
	var num_align: int = version / 7 + 2
	var step: int = (version * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	var size: int = version * 4 + 17
	var result: Array[int] = []
	for i in range(num_align - 1):
		result.append(size - 7 - i * step)
	result.append(6)
	result.reverse()
	return result

static func _get_num_raw_data_modules(ver: int) -> int:
	var result: int = (16 * ver + 128) * ver + 64
	if ver >= 2:
		var num_align: int = ver / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if ver >= 7:
			result -= 36
	return result

static func _get_num_data_codewords(ver: int) -> int:
	return _get_num_raw_data_modules(ver) / 8 - _ECC_CODEWORDS_PER_BLOCK[ver] * _NUM_ERROR_CORRECTION_BLOCKS[ver]

static func _reed_solomon_compute_divisor(degree: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root: int = 1
	for _i in range(degree):
		for j in range(degree):
			result[j] = _reed_solomon_multiply(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _reed_solomon_multiply(root, 0x02)
	return result

static func _reed_solomon_compute_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(divisor.size())
	result.fill(0)
	for b in data:
		var factor: int = b ^ result[0]
		for k in range(result.size() - 1):
			result[k] = result[k + 1]
		result[result.size() - 1] = 0
		for i in range(divisor.size()):
			result[i] ^= _reed_solomon_multiply(divisor[i], factor)
	return result

static func _reed_solomon_multiply(x: int, y: int) -> int:
	var z: int = 0
	for i in range(7, -1, -1):
		var high_bit: int = (z >> 7) & 1
		z = ((z << 1) ^ (high_bit * 0x11D)) & 0xFF
		z ^= (((y >> i) & 1) * x)
		z &= 0xFF
	return z
