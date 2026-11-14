class_name TileAtlasBuilder
extends RefCounted

## Builds user://rom_cache/tiles/emerald_v1.{png,json} by starting from original_v1.png
## (keeping buildings 12..14 and any unmapped gap classes untouched per Rule B) and
## overwriting mapped landscape/cliff/puzzle cells with 2x-scaled Pokémon Emerald tiles.

const GbaRomRef := preload("res://rom/gba_rom.gd")
const Gen3TilesRef := preload("res://rom/gen3_tiles.gd")

const ORIGINAL_PNG_PATH := "res://assets/tiles/original_v1.png"
const ORIGINAL_JSON_PATH := "res://assets/tiles/original_v1.json"
const DEFAULT_EMERALD_MAP_PATH := "res://config/emerald_tile_map.json"


static func build_emerald_atlas(
	rom: Variant,
	staging_dir: String,
	map_config_path: String = DEFAULT_EMERALD_MAP_PATH
) -> Dictionary:
	if rom == null:
		return {"ok": false, "error": "Null GBA ROM instance."}

	var png_bytes := FileAccess.get_file_as_bytes(ORIGINAL_PNG_PATH)
	if png_bytes.is_empty():
		return {"ok": false, "error": "Missing " + ORIGINAL_PNG_PATH}
	var atlas_img := Image.new()
	var load_err := atlas_img.load_png_from_buffer(png_bytes)
	if load_err != OK or atlas_img.is_empty():
		return {"ok": false, "error": "Failed to decode " + ORIGINAL_PNG_PATH}
	atlas_img.convert(Image.FORMAT_RGBA8)

	var orig_json_text := FileAccess.get_file_as_string(ORIGINAL_JSON_PATH)
	var orig_json_v: Variant = JSON.parse_string(orig_json_text)
	if not (orig_json_v is Dictionary):
		return {"ok": false, "error": "Failed to parse " + ORIGINAL_JSON_PATH}
	var orig_json: Dictionary = orig_json_v

	var cfg_text := FileAccess.get_file_as_string(map_config_path)
	var cfg_v: Variant = JSON.parse_string(cfg_text)
	if not (cfg_v is Dictionary):
		return {"ok": false, "error": "Failed to parse " + map_config_path}
	var cfg: Dictionary = cfg_v

	var tmap: Dictionary = cfg.get("tile_map", {})
	for forbidden_cls in ["12", "13", "14"]:
		if tmap.has(forbidden_cls):
			return {"ok": false, "error": "Rule B violation: class %s must not appear in emerald_tile_map.json." % forbidden_cls}
	if not (cfg.get("buildings", {}) as Dictionary).is_empty() or not (cfg.get("compositions", {}) as Dictionary).is_empty():
		return {"ok": false, "error": "Rule B violation: buildings and compositions must be empty."}

	var tilesets_cfg: Dictionary = cfg.get("tilesets", {})
	var decoded_tilesets: Dictionary = {}
	for ts_name_v in tilesets_cfg.keys():
		var ts_name := str(ts_name_v)
		var ts_index := int(tilesets_cfg[ts_name_v])
		var dec := Gen3TilesRef.decode_tileset_record(rom, ts_index)
		if not bool(dec.get("ok", false)):
			return {"ok": false, "error": "Tileset %s decode failed: %s" % [ts_name, str(dec.get("error", ""))]}
		decoded_tilesets[ts_name] = dec

	if not decoded_tilesets.has("primary"):
		return {"ok": false, "error": "Missing primary tileset in emerald_tile_map.json."}
	var primary_ts: Dictionary = decoded_tilesets["primary"]

	# Map (class, variant) -> {"row": int, "masked": bool}
	var row_lookup: Dictionary = {}
	for r_v in (orig_json.get("rows", []) as Array):
		var r: Dictionary = r_v
		var key := "%d:%d" % [int(r.get("class", -1)), int(r.get("variant", 0))]
		row_lookup[key] = {"row": int(r.get("row", 0)), "masked": bool(r.get("masked", false))}

	var tile_px := int(orig_json.get("tile_px", 32))
	var tiles_written := 0

	# Render landscape metatiles
	for cls_key_v in tmap.keys():
		var cls_key := str(cls_key_v)
		var cls_int := int(cls_key)
		if cls_int in [12, 13, 14]:
			continue
		var variants_dict: Dictionary = tmap[cls_key_v]
		for var_key_v in variants_dict.keys():
			var var_int := int(str(var_key_v))
			var lookup_key := "%d:%d" % [cls_int, var_int]
			if not row_lookup.has(lookup_key):
				continue
			var rinfo: Dictionary = row_lookup[lookup_key]
			var row_idx := int(rinfo["row"])
			var is_masked := bool(rinfo["masked"])
			var masks_dict: Dictionary = variants_dict[var_key_v]
			for mask_key_v in masks_dict.keys():
				var mask_int := int(str(mask_key_v))
				if not is_masked and mask_int != 0:
					continue
				var col_idx := mask_int if is_masked else 0
				var rule: Dictionary = masks_dict[mask_key_v]
				var mt_id := int(rule.get("metatile", 0))
				var ts_name := str(rule.get("tileset", "primary"))
				var secondary: Variant = null if ts_name == "primary" else decoded_tilesets.get(ts_name, null)
				if ts_name != "primary" and not (secondary is Dictionary):
					return {"ok": false, "error": "Missing secondary tileset '%s' for %s" % [ts_name, lookup_key]}
				var cell_img := Gen3TilesRef.render_metatile_32(primary_ts, secondary, mt_id)
				atlas_img.blit_rect(cell_img, Rect2i(0, 0, tile_px, tile_px), Vector2i(col_idx * tile_px, row_idx * tile_px))
				tiles_written += 1

	# Render 16x16 field-move & item-ball object sprites (classes 25..28) composited over grass
	var obj_cfg: Dictionary = cfg.get("object_sprites", {})
	for obj_cls_v in obj_cfg.keys():
		var cls_int := int(str(obj_cls_v))
		var lookup_key := "%d:0" % cls_int
		if not row_lookup.has(lookup_key):
			continue
		var rinfo: Dictionary = row_lookup[lookup_key]
		var row_idx := int(rinfo["row"])
		var spec: Dictionary = obj_cfg[obj_cls_v]
		var base_mt := int(spec.get("base_metatile", 1))
		var frame_off := int(spec.get("frame_offset", 0))
		var pal_off := int(spec.get("palette_offset", 0))
		var obj_img := Gen3TilesRef.render_object_over_metatile_32(rom, primary_ts, base_mt, frame_off, pal_off)
		atlas_img.blit_rect(obj_img, Rect2i(0, 0, tile_px, tile_px), Vector2i(0, row_idx * tile_px))
		tiles_written += 1

	var abs_stage := ProjectSettings.globalize_path(staging_dir.trim_suffix("/"))
	var tiles_dir := abs_stage.path_join("tiles")
	DirAccess.make_dir_recursive_absolute(tiles_dir)

	var out_png := tiles_dir.path_join("emerald_v1.png")
	var out_json := tiles_dir.path_join("emerald_v1.json")
	var save_err := atlas_img.save_png(out_png)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save %s (err=%d)" % [out_png, save_err]}
	var jf := FileAccess.open(out_json, FileAccess.WRITE)
	if jf == null:
		return {"ok": false, "error": "Failed to write " + out_json}
	jf.store_string(orig_json_text)
	jf.close()

	return {
		"ok": true,
		"png": out_png,
		"json": out_json,
		"tiles_written": tiles_written,
	}
