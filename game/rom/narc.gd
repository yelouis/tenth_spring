class_name NarcArchive
extends RefCounted

## Nitro Archive (NARC / BTAF / BTNF / GMIF) slice reader (Item 45).
## Reads individual sub-files by offset via FileAccess.get_buffer without loading the whole ROM.

var base_offset: int = 0
var gmif_data_offset: int = 0
var entries: Array[Vector2i] = []

static func parse(fh: FileAccess, narc_start: int, narc_end: int) -> NarcArchive:
	if narc_end <= narc_start + 28:
		return null
	fh.seek(narc_start)
	var hdr := fh.get_buffer(28)
	if hdr.size() < 28 or hdr.slice(0, 4).get_string_from_ascii() != "NARC":
		return null
	if hdr.slice(16, 20).get_string_from_ascii() != "BTAF":
		return null
	var btaf_size := int(hdr.decode_u32(20))
	var file_count := int(hdr.decode_u32(24))
	fh.seek(narc_start + 28)
	var btaf_table := fh.get_buffer(file_count * 8)
	if btaf_table.size() < file_count * 8:
		return null
	var btnf_pos := 16 + btaf_size
	fh.seek(narc_start + btnf_pos)
	var btnf_hdr := fh.get_buffer(8)
	if btnf_hdr.size() < 8 or btnf_hdr.slice(0, 4).get_string_from_ascii() != "BTNF":
		return null
	var btnf_size := int(btnf_hdr.decode_u32(4))
	var gmif_pos := btnf_pos + btnf_size
	fh.seek(narc_start + gmif_pos)
	var gmif_hdr := fh.get_buffer(8)
	if gmif_hdr.size() < 8 or gmif_hdr.slice(0, 4).get_string_from_ascii() != "GMIF":
		return null

	var arc := NarcArchive.new()
	arc.base_offset = narc_start
	arc.gmif_data_offset = gmif_pos + 8
	arc.entries.resize(file_count)
	for i in range(file_count):
		var s := int(btaf_table.decode_u32(i * 8))
		var e := int(btaf_table.decode_u32(i * 8 + 4))
		arc.entries[i] = Vector2i(s, e)
	return arc

func file_count() -> int:
	return entries.size()

func read_subfile(fh: FileAccess, index: int) -> PackedByteArray:
	if index < 0 or index >= entries.size():
		return PackedByteArray()
	var span := entries[index]
	var length := span.y - span.x
	if length <= 0:
		return PackedByteArray()
	fh.seek(base_offset + gmif_data_offset + span.x)
	return fh.get_buffer(length)
