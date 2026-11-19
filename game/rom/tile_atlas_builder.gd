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
const INDOOR_STAMP_TO_OBJECT_CLASS := {
	"110": "28", # int_item_ball -> Emerald item ball
	"114": "27", # int_push_boulder -> Emerald Strength boulder
	"115": "26", # int_smash_rubble -> Emerald Rock Smash rock
}


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

	var indoor_res := _build_indoor_atlas_files(rom, cfg, tiles_dir, tile_px, cfg_text.sha256_text())
	if not bool(indoor_res.get("ok", false)):
		return indoor_res

	return {
		"ok": true,
		"png": out_png,
		"json": out_json,
		"indoor_png": str(indoor_res.get("png", "")),
		"indoor_json": str(indoor_res.get("json", "")),
		"tiles_written": tiles_written,
		"indoor_tiles_written": int(indoor_res.get("written", 0)),
	}


static func _render_indoor_descriptor(desc: Dictionary, indoor_decoded: Dictionary, ctx: String) -> Dictionary:
	var ipri_name := str(desc.get("primary", "pri16"))
	if not indoor_decoded.has(ipri_name):
		return {"ok": false, "error": "Missing indoor primary '%s' for %s" % [ipri_name, ctx]}
	var ipri: Dictionary = indoor_decoded[ipri_name]
	var isec: Variant = null
	if desc.has("tileset") and not str(desc.get("tileset", "")).is_empty():
		var isec_name := str(desc.get("tileset", ""))
		if not indoor_decoded.has(isec_name):
			return {"ok": false, "error": "Missing indoor secondary '%s' for %s" % [isec_name, ctx]}
		isec = indoor_decoded[isec_name]
	var imt := int(desc.get("metatile", 0))
	var ilayer := str(desc.get("layer", "full"))
	var img := Gen3TilesRef.render_metatile_layer1_32(ipri, isec, imt) if ilayer == "l1" else Gen3TilesRef.render_indoor_metatile_32(ipri, isec, imt)
	return {"ok": true, "image": img}


static func _register_indoor_descriptor(
	desc: Dictionary,
	unique_descs: Array,
	key_to_idx: Dictionary,
	cols: int
) -> Array:
	var pri := str(desc.get("primary", "pri16"))
	var ts := str(desc.get("tileset", ""))
	var mt := int(desc.get("metatile", 0))
	var lyr := str(desc.get("layer", "full"))
	var key := "%s|%s|%d|%s" % [pri, ts, mt, lyr]
	var idx: int
	if key_to_idx.has(key):
		idx = int(key_to_idx[key])
	else:
		idx = cols + unique_descs.size()
		key_to_idx[key] = idx
		unique_descs.append({
			"primary": pri,
			"tileset": ts,
			"metatile": mt,
			"layer": lyr,
		})
	return [idx % cols, int(idx / cols)]


static func _build_indoor_atlas_files(
	rom: Variant,
	cfg: Dictionary,
	tiles_dir: String,
	tile_px: int,
	cfg_sha256: String = ""
) -> Dictionary:
	var indoor_ts_cfg: Dictionary = cfg.get("indoor_tilesets", {})
	var indoor_map_cfg: Dictionary = cfg.get("indoor_tile_map", {})
	var indoor_kits_cfg: Dictionary = cfg.get("indoor_kits", {})
	var indoor_fixtures_cfg: Dictionary = cfg.get("indoor_fixtures", {})
	var out_indoor_png := tiles_dir.path_join("emerald_indoor_v1.png")
	var out_indoor_json := tiles_dir.path_join("emerald_indoor_v1.json")
	if indoor_map_cfg.is_empty():
		return {"ok": true, "png": out_indoor_png, "json": out_indoor_json, "written": 0}

	var indoor_decoded: Dictionary = {}
	for its_name_v in indoor_ts_cfg.keys():
		var its_name := str(its_name_v)
		var its_index := int(indoor_ts_cfg[its_name_v])
		var idec := Gen3TilesRef.decode_tileset_record(rom, its_index)
		if not bool(idec.get("ok", false)):
			return {"ok": false, "error": "Indoor tileset %s decode failed: %s" % [its_name, str(idec.get("error", ""))]}
		indoor_decoded[its_name] = idec

	var indoor_cols := 17
	var unique_descs: Array = []
	var key_to_idx: Dictionary = {}

	var kits_meta: Dictionary = {}
	var kit_names := indoor_kits_cfg.keys()
	kit_names.sort()
	for kit_name_v in kit_names:
		var kit_name := str(kit_name_v)
		var kit_spec: Dictionary = indoor_kits_cfg[kit_name_v]
		var kit_out: Dictionary = {}
		var slot_names := kit_spec.keys()
		slot_names.sort()
		for slot_v in slot_names:
			var slot_name := str(slot_v)
			var val: Variant = kit_spec[slot_v]
			if val is Dictionary:
				kit_out[slot_name] = _register_indoor_descriptor(val, unique_descs, key_to_idx, indoor_cols)
			elif val is Array:
				var arr := val as Array
				if not arr.is_empty() and arr[0] is Array:
					var mat_out: Array = []
					for row_v in arr:
						var row_out: Array = []
						for cell_v in (row_v as Array):
							row_out.append(_register_indoor_descriptor(cell_v, unique_descs, key_to_idx, indoor_cols))
						mat_out.append(row_out)
					kit_out[slot_name] = mat_out
				else:
					var row_out2: Array = []
					for cell_v in arr:
						row_out2.append(_register_indoor_descriptor(cell_v, unique_descs, key_to_idx, indoor_cols))
					kit_out[slot_name] = row_out2
		kits_meta[kit_name] = kit_out

	var fixtures_meta: Dictionary = {}
	var fx_names := indoor_fixtures_cfg.keys()
	fx_names.sort()
	for fx_v in fx_names:
		var fx_name := str(fx_v)
		var fx_spec: Dictionary = indoor_fixtures_cfg[fx_v]
		var fpri := str(fx_spec.get("primary", "pri16"))
		var fsec := str(fx_spec.get("tileset", ""))
		var flayer := str(fx_spec.get("layer", "l1"))
		var fcells: Array = fx_spec.get("cells", [])
		var out_cells: Array = []
		for row_v in fcells:
			var out_row: Array = []
			for mt_v in (row_v as Array):
				var desc := {"primary": fpri, "tileset": fsec, "metatile": int(mt_v), "layer": flayer}
				out_row.append(_register_indoor_descriptor(desc, unique_descs, key_to_idx, indoor_cols))
			out_cells.append(out_row)
		fixtures_meta[fx_name] = {
			"w": int(fx_spec.get("w", 1)),
			"h": int(fx_spec.get("h", 1)),
			"base_rows": int(fx_spec.get("base_rows", 1)),
			"underlay": bool(fx_spec.get("underlay", false)),
			"layer": flayer,
			"cells": out_cells,
		}

	var obj_cfg: Dictionary = cfg.get("object_sprites", {})
	var override_descs: Array = []
	var stamp_overrides: Dictionary = {}
	var sid_keys := INDOOR_STAMP_TO_OBJECT_CLASS.keys()
	sid_keys.sort()
	for sid_v in sid_keys:
		var sid_str := str(sid_v)
		var obj_cls_str := str(INDOOR_STAMP_TO_OBJECT_CLASS[sid_str])
		if not obj_cfg.has(obj_cls_str):
			continue
		var atlas_idx := indoor_cols + unique_descs.size() + override_descs.size()
		var spec: Dictionary = obj_cfg[obj_cls_str]
		override_descs.append({
			"col": atlas_idx % indoor_cols,
			"row": int(atlas_idx / indoor_cols),
			"frame_offset": int(spec.get("frame_offset", 0)),
			"palette_offset": int(spec.get("palette_offset", 0)),
		})
		stamp_overrides[sid_str] = [atlas_idx % indoor_cols, int(atlas_idx / indoor_cols)]

	var total_slots := indoor_cols + unique_descs.size() + override_descs.size()
	var total_rows := maxi(1, int((total_slots + indoor_cols - 1) / indoor_cols))
	var indoor_img := Image.create(indoor_cols * tile_px, total_rows * tile_px, false, Image.FORMAT_RGBA8)
	indoor_img.fill(Color(0, 0, 0, 0))

	var indoor_written := 0
	var indoor_rows: Array = []
	for icls in range(indoor_cols):
		var ikey := str(icls)
		if indoor_map_cfg.has(ikey):
			var rres := _render_indoor_descriptor(indoor_map_cfg[ikey], indoor_decoded, "indoor class %d" % icls)
			if not bool(rres.get("ok", false)):
				return rres
			indoor_img.blit_rect(rres["image"], Rect2i(0, 0, tile_px, tile_px), Vector2i(icls * tile_px, 0))
			indoor_written += 1
		indoor_rows.append({"class": icls, "col": icls})

	for u_idx in range(unique_descs.size()):
		var atlas_idx := indoor_cols + u_idx
		var col := atlas_idx % indoor_cols
		var row := int(atlas_idx / indoor_cols)
		var ures := _render_indoor_descriptor(unique_descs[u_idx], indoor_decoded, "indoor slot %d" % atlas_idx)
		if not bool(ures.get("ok", false)):
			return ures
		indoor_img.blit_rect(ures["image"], Rect2i(0, 0, tile_px, tile_px), Vector2i(col * tile_px, row * tile_px))
		indoor_written += 1

	for ov_v in override_descs:
		var ov: Dictionary = ov_v
		var obj_img := Gen3TilesRef.render_object_transparent_32(
			rom,
			int(ov["frame_offset"]),
			int(ov["palette_offset"])
		)
		indoor_img.blit_rect(obj_img, Rect2i(0, 0, tile_px, tile_px), Vector2i(int(ov["col"]) * tile_px, int(ov["row"]) * tile_px))
		indoor_written += 1

	var isave_err := indoor_img.save_png(out_indoor_png)
	if isave_err != OK:
		return {"ok": false, "error": "Failed to save %s (err=%d)" % [out_indoor_png, isave_err]}
	var ijf := FileAccess.open(out_indoor_json, FileAccess.WRITE)
	if ijf == null:
		return {"ok": false, "error": "Failed to write " + out_indoor_json}
	ijf.store_string(JSON.stringify({
		"format": "emerald_indoor_v2",
		"cfg_sha256": cfg_sha256,
		"tile_px": tile_px,
		"cols": indoor_cols,
		"rows": total_rows,
		"count": indoor_cols,
		"columns": indoor_rows,
		"kits": kits_meta,
		"fixtures": fixtures_meta,
		"stamp_overrides": stamp_overrides,
	}, "\t") + "\n")
	ijf.close()
	return {"ok": true, "png": out_indoor_png, "json": out_indoor_json, "written": indoor_written}
