class_name RomImporter
extends RefCounted

## Phase 2 Production Importer Orchestrator & §7 Validation Suite (Item 45).
## Contract: docs/design_rom_asset_pipeline.md §3, §6–7 & docs/implementation_plan_rom_importer.md §2–4, §6.

const NdsFsRef := preload("res://rom/nds_fs.gd")
const NarcArchiveRef := preload("res://rom/narc.gd")
const NitroLzRef := preload("res://rom/lz.gd")
const NitroGfxRef := preload("res://rom/nitro_gfx.gd")
const Gen5CellsRef := preload("res://rom/gen5_cells.gd")
const DataPackImporterRef := preload("res://rom/data_pack.gd")
const FanSpritesImporterRef := preload("res://rom/fan_sprites.gd")
const GbaRomRef := preload("res://rom/gba_rom.gd")
const TileAtlasBuilderRef := preload("res://rom/tile_atlas_builder.gd")

const DEFAULT_CACHE_DIR := "user://rom_cache"
const IMPORTER_VERSION := 3

const EXPECTED_TYPING_CHECKS := {
	"36": ["fairy"],
	"282": ["psychic", "fairy"],
	"778": ["ghost", "fairy"],
	"887": ["dragon", "ghost"],
	"487": ["ghost", "dragon"],
	"442": ["ghost", "dark"],
	"94": ["ghost", "poison"],
	"609": ["ghost", "fire"],
	"593": ["water", "ghost"],
	"623": ["ground", "ghost"],
}

const ROM_METRIC_SPOT_DEX := [1, 94, 487, 593, 609, 623, 649]

static func _copy_dir_recursive(src_dir: String, dst_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(src_dir):
		return
	if not DirAccess.dir_exists_absolute(dst_dir):
		DirAccess.make_dir_recursive_absolute(dst_dir)
	var da := DirAccess.open(src_dir)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var s_path := src_dir.path_join(entry)
			var d_path := dst_dir.path_join(entry)
			if da.current_is_dir():
				_copy_dir_recursive(s_path, d_path)
			else:
				var bytes := FileAccess.get_file_as_bytes(s_path)
				var fh := FileAccess.open(d_path, FileAccess.WRITE)
				if fh != null:
					fh.store_buffer(bytes)
					fh.close()
		entry = da.get_next()
	da.list_dir_end()

static func _prepare_staging_dir(cache_dir: String) -> String:
	var clean_cache := ProjectSettings.globalize_path(cache_dir.trim_suffix("/"))
	var staging_dir := clean_cache + ".tmp"
	DataPackImporterRef._remove_dir_recursive(staging_dir)
	DirAccess.make_dir_recursive_absolute(staging_dir)
	if DirAccess.dir_exists_absolute(clean_cache) and FileAccess.file_exists(clean_cache.path_join("manifest.json")):
		_copy_dir_recursive(clean_cache, staging_dir)
	return staging_dir

static func _promote_staging_dir(staging_dir: String, cache_dir: String) -> bool:
	var clean_cache := ProjectSettings.globalize_path(cache_dir.trim_suffix("/"))
	var backup_dir := clean_cache + ".old"
	DataPackImporterRef._remove_dir_recursive(backup_dir)
	if DirAccess.dir_exists_absolute(clean_cache):
		if DirAccess.rename_absolute(clean_cache, backup_dir) != OK:
			DataPackImporterRef._remove_dir_recursive(clean_cache)
	var err := DirAccess.rename_absolute(staging_dir, clean_cache)
	if err != OK:
		if DirAccess.dir_exists_absolute(backup_dir):
			DirAccess.rename_absolute(backup_dir, clean_cache)
		return false
	DataPackImporterRef._remove_dir_recursive(backup_dir)
	return true

static func _read_manifest_or_default(dir_path: String) -> Dictionary:
	var mpath := dir_path.path_join("manifest.json")
	if FileAccess.file_exists(mpath):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mpath))
		if parsed is Dictionary:
			return parsed
	return {
		"importerVersion": IMPORTER_VERSION,
		"rom": null,
		"dataPack": null,
		"tiles": null,
	}


static func import_gba_rom(
	rom_path: String = "",
	cache_dir: String = DEFAULT_CACHE_DIR,
	allow_test_user_dir: bool = false
) -> Dictionary:
	var effective_path := rom_path.strip_edges()
	if effective_path.is_empty():
		effective_path = OS.get_environment("TENTH_SPRING_ROM_GBA").strip_edges()
	var is_test_dir := allow_test_user_dir or cache_dir.strip_edges().begins_with("user://test/")
	var opened := GbaRomRef.open_rom(effective_path, is_test_dir, true)
	if not bool(opened.get("ok", false)):
		return opened
	var rom: Variant = opened["rom"]
	var staging_dir := _prepare_staging_dir(cache_dir)
	var build_res := TileAtlasBuilderRef.build_emerald_atlas(rom, staging_dir)
	rom.close()
	if not bool(build_res.get("ok", false)):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return build_res

	var manifest := _read_manifest_or_default(staging_dir)
	if manifest.get("dataPack", null) == null:
		manifest["importerVersion"] = IMPORTER_VERSION
	manifest["tiles"] = {
		"format": "emerald_v1",
		"gameCode": str(opened.get("game_code", GbaRomRef.EXPECTED_GAME_CODE)),
		"sha1": str(opened.get("sha1", "")),
		"isClean": bool(opened.get("is_clean", false)),
		"tilesWritten": int(build_res.get("tiles_written", 0)),
	}
	var mf := FileAccess.open(staging_dir.path_join("manifest.json"), FileAccess.WRITE)
	if mf == null:
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Cannot write manifest.json in GBA staging dir."}
	mf.store_string(JSON.stringify(manifest, "\t") + "\n")
	mf.close()

	if not _promote_staging_dir(staging_dir, cache_dir):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Failed to promote GBA tile cache directory."}

	var asset_db_script := load("res://rom/asset_db.gd")
	if asset_db_script != null:
		asset_db_script.call("clear_tile_atlas_cache")

	return {
		"ok": true,
		"cache_dir": cache_dir,
		"sha1": str(opened.get("sha1", "")),
		"tiles_written": int(build_res.get("tiles_written", 0)),
	}

static func import_bw_rom(
	rom_path: String,
	cache_dir: String = DEFAULT_CACHE_DIR,
	allow_test_user_dir: bool = false
) -> Dictionary:
	var hdr := NdsFsRef.read_header(rom_path, true, allow_test_user_dir)
	if not bool(hdr.get("ok", false)):
		return hdr

	var abs_path := str(hdr["path"])
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return {"ok": false, "error": "Cannot open ROM file."}

	var fat := NdsFsRef.read_fat(fh, int(hdr["fat_offset"]), int(hdr["fat_size"]))
	var sprite_fid := NdsFsRef.resolve_archive_id(
		fh, hdr, fat, NdsFsRef.SPRITE_NARC_PATH, NdsFsRef.SPRITE_NARC_FALLBACK_ID
	)
	if sprite_fid < 0:
		fh.close()
		return {"ok": false, "error": "Could not locate /a/0/0/4 sprite NARC in ROM."}

	var sp_span := fat[sprite_fid]
	var sp_narc := NarcArchiveRef.parse(fh, sp_span.x, sp_span.y)
	if sp_narc == null or sp_narc.file_count() < 649 * 20 + 20:
		fh.close()
		return {"ok": false, "error": "Invalid or truncated /a/0/0/4 NARC."}

	var shared_ncer_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, 4))
	if not bool(shared_ncer_lz.get("ok", false)):
		fh.close()
		return {"ok": false, "error": "Failed to decompress shared NCER."}
	var shared_ncer := Gen5CellsRef.parse_ncer(shared_ncer_lz["data"])
	if not bool(shared_ncer.get("ok", false)) or (shared_ncer["banks"] as Array).is_empty():
		fh.close()
		return {"ok": false, "error": "Invalid shared NCER in /a/0/0/4."}
	var shared_oams: Array = shared_ncer["banks"][0]

	var staging_dir := _prepare_staging_dir(cache_dir)
	for sub in ["front", "back", "front_shiny", "back_shiny"]:
		var sdir := staging_dir.path_join("sprites").path_join(sub)
		if not DirAccess.dir_exists_absolute(sdir):
			DirAccess.make_dir_recursive_absolute(sdir)

	var front_decoded := 0
	var back_decoded := 0

	for dex in range(1, 650):
		var base := dex * 20
		var front_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, base + 0))
		var back_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, base + 9))
		var pal_norm_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, base + 18))
		var pal_shiny_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, base + 19))
		if not (bool(front_lz.get("ok", false)) and bool(back_lz.get("ok", false)) and bool(pal_norm_lz.get("ok", false)) and bool(pal_shiny_lz.get("ok", false))):
			fh.close()
			DataPackImporterRef._remove_dir_recursive(staging_dir)
			return {"ok": false, "error": "LZ decompression failed for species #%d" % dex, "failed_dex": dex}

		var front_ncgr := NitroGfxRef.parse_ncgr(front_lz["data"])
		var back_ncgr := NitroGfxRef.parse_ncgr(back_lz["data"])
		var pal_norm := NitroGfxRef.parse_nclr(pal_norm_lz["data"])
		var pal_shiny := NitroGfxRef.parse_nclr(pal_shiny_lz["data"])
		if not bool(front_ncgr.get("ok", false)) or not bool(back_ncgr.get("ok", false)) or pal_norm.size() < 16 or pal_shiny.size() < 16:
			fh.close()
			DataPackImporterRef._remove_dir_recursive(staging_dir)
			return {"ok": false, "error": "NCGR/NCLR parse failed for species #%d" % dex, "failed_dex": dex}

		var front_tiles: PackedByteArray = front_ncgr["tile_bytes"]
		var back_tiles: PackedByteArray = back_ncgr["tile_bytes"]

		var img_f := Gen5CellsRef.assemble_sprite_image(front_tiles, pal_norm, shared_oams, 96, 96)
		var img_b := Gen5CellsRef.assemble_sprite_image(back_tiles, pal_norm, shared_oams, 96, 96)
		var img_fs := Gen5CellsRef.assemble_sprite_image(front_tiles, pal_shiny, shared_oams, 96, 96)
		var img_bs := Gen5CellsRef.assemble_sprite_image(back_tiles, pal_shiny, shared_oams, 96, 96)

		img_f.save_png(staging_dir.path_join("sprites/front/%d.png" % dex))
		img_b.save_png(staging_dir.path_join("sprites/back/%d.png" % dex))
		img_fs.save_png(staging_dir.path_join("sprites/front_shiny/%d.png" % dex))
		img_bs.save_png(staging_dir.path_join("sprites/back_shiny/%d.png" % dex))
		front_decoded += 1
		back_decoded += 1

	# Extract item icons from /a/0/2/5 when present
	var item_icons_decoded := 0
	var item_fid := NdsFsRef.resolve_archive_id(
		fh, hdr, fat, NdsFsRef.ITEM_ICON_NARC_PATH, NdsFsRef.ITEM_ICON_NARC_FALLBACK_ID
	)
	if item_fid >= 0:
		var item_span := fat[item_fid]
		var item_narc := NarcArchiveRef.parse(fh, item_span.x, item_span.y)
		if item_narc != null and item_narc.file_count() >= 4:
			var icon_ncer_lz := NitroLzRef.decompress(item_narc.read_subfile(fh, 1))
			if bool(icon_ncer_lz.get("ok", false)):
				var icon_ncer := Gen5CellsRef.parse_ncer(icon_ncer_lz["data"])
				if bool(icon_ncer.get("ok", false)) and not (icon_ncer["banks"] as Array).is_empty():
					var icon_oams: Array = icon_ncer["banks"][0]
					var icons_dir := staging_dir.path_join("icons/items")
					DirAccess.make_dir_recursive_absolute(icons_dir)
					var pair_count := (item_narc.file_count() - 2) / 2
					for k in range(pair_count):
						var cg_lz := NitroLzRef.decompress(item_narc.read_subfile(fh, 2 + k * 2))
						var cl_lz := NitroLzRef.decompress(item_narc.read_subfile(fh, 3 + k * 2))
						if not bool(cg_lz.get("ok", false)) or not bool(cl_lz.get("ok", false)):
							continue
						var cg := NitroGfxRef.parse_ncgr(cg_lz["data"])
						var cl := NitroGfxRef.parse_nclr(cl_lz["data"])
						if not bool(cg.get("ok", false)) or cl.size() < 16:
							continue
						var icon_img := Gen5CellsRef.assemble_sprite_image(cg["tile_bytes"], cl, icon_oams, 32, 32)
						icon_img.save_png(icons_dir.path_join("%d.png" % k))
						item_icons_decoded += 1

	var box_icons_decoded := 0
	var box_fid := NdsFsRef.resolve_archive_id(
		fh, hdr, fat, NdsFsRef.BOX_ICON_NARC_PATH, NdsFsRef.BOX_ICON_NARC_FALLBACK_ID
	)
	if box_fid >= 0:
		var box_span := fat[box_fid]
		var box_narc := NarcArchiveRef.parse(fh, box_span.x, box_span.y)
		if box_narc != null and box_narc.file_count() > 7 + 649 * 2:
			var box_pal_lz := NitroLzRef.decompress(box_narc.read_subfile(fh, 0))
			var box_palettes := NitroGfxRef.parse_nclr_multi(box_pal_lz["data"], 8) if bool(box_pal_lz.get("ok", false)) else []
			if not box_palettes.is_empty():
				var box_dir := staging_dir.path_join("icons/pokemon_box")
				DirAccess.make_dir_recursive_absolute(box_dir)
				for dex in range(1, 650):
					if _extract_box_icon_to_dir(fh, box_narc, sp_narc, box_palettes, dex, box_dir):
						box_icons_decoded += 1

	fh.close()

	var val_res := validate_rom_staging(staging_dir)
	if not bool(val_res.get("ok", false)):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return val_res

	var manifest := _read_manifest_or_default(staging_dir)
	if manifest.get("dataPack", null) == null:
		manifest["importerVersion"] = IMPORTER_VERSION
	manifest["rom"] = {
		"gameCode": str(hdr["game_code"]),
		"title": str(hdr["title"]),
		"sha1": str(hdr["sha1"]),
		"status": str(hdr["status"]),
		"notice": str(hdr["notice"]),
		"importedAt": Time.get_datetime_string_from_system(true) + "Z",
		"frontSpritesDecoded": front_decoded,
		"backSpritesDecoded": back_decoded,
		"itemIconsDecoded": item_icons_decoded,
	}
	if not DataPackImporterRef._write_json_file(staging_dir.path_join("manifest.json"), manifest):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Failed to write manifest.json"}

	if not _promote_staging_dir(staging_dir, cache_dir):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Failed to promote staging directory"}

	return {
		"ok": true,
		"game_code": str(hdr["game_code"]),
		"sha1": str(hdr["sha1"]),
		"status": str(hdr["status"]),
		"notice": str(hdr["notice"]),
		"front_sprites_decoded": front_decoded,
		"back_sprites_decoded": back_decoded,
		"item_icons_decoded": item_icons_decoded,
	}

static func import_data_pack(
	local_pack_dir: String = "",
	fetcher: Variant = null,
	cache_dir: String = DEFAULT_CACHE_DIR
) -> Dictionary:
	var resolved_local := local_pack_dir.strip_edges()
	if resolved_local == "":
		resolved_local = OS.get_environment("TENTH_SPRING_DATA_PACK").strip_edges()
	if resolved_local != "":
		resolved_local = ProjectSettings.globalize_path(resolved_local).simplify_path()

	var staging_dir := _prepare_staging_dir(cache_dir)

	var dp_res := DataPackImporterRef.verify_and_stage_data_pack(staging_dir, resolved_local, fetcher)
	if not bool(dp_res.get("ok", false)):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return dp_res

	var fs_res := FanSpritesImporterRef.verify_and_stage_fan_sprites(staging_dir, resolved_local, fetcher)
	if not bool(fs_res.get("ok", false)):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return fs_res

	var val_res := validate_data_staging(staging_dir)
	if not bool(val_res.get("ok", false)):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return val_res

	var manifest := _read_manifest_or_default(staging_dir)
	manifest["importerVersion"] = IMPORTER_VERSION
	manifest["dataPack"] = {
		"pokeapiCommit": str(dp_res.get("source_commit", "")),
		"spritesCommit": str(fs_res.get("source_commit", "")),
		"importedAt": Time.get_datetime_string_from_system(true) + "Z",
		"speciesCount": int(dp_res.get("species_count", 0)),
		"megaFormCount": int(dp_res.get("mega_form_count", 0)),
		"battleFormCount": int(dp_res.get("battle_form_count", 0)),
		"moveCount": int(dp_res.get("move_count", 0)),
		"tmSpeciesCount": int(dp_res.get("tm_species_count", 0)),
		"machineCount": int(dp_res.get("machine_count", 0)),
		"fanSpritesPresent": int(fs_res.get("target_count", 0)),
		"pendingSpeciesDex": fs_res.get("pending_species_dex", []),
		"pendingMegaPokemonIds": fs_res.get("pending_mega_pokemon_ids", []),
	}
	if not DataPackImporterRef._write_json_file(staging_dir.path_join("manifest.json"), manifest):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Failed to write manifest.json"}

	if not _promote_staging_dir(staging_dir, cache_dir):
		DataPackImporterRef._remove_dir_recursive(staging_dir)
		return {"ok": false, "error": "Failed to promote staging directory"}

	return {
		"ok": true,
		"species_count": int(dp_res.get("species_count", 0)),
		"mega_form_count": int(dp_res.get("mega_form_count", 0)),
		"battle_form_count": int(dp_res.get("battle_form_count", 0)),
		"move_count": int(dp_res.get("move_count", 0)),
		"tm_species_count": int(dp_res.get("tm_species_count", 0)),
		"machine_count": int(dp_res.get("machine_count", 0)),
		"fan_sprites_present": int(fs_res.get("target_count", 0)),
		"normalized_sprites": int(fs_res.get("normalized_count", 0)),
	}

static func validate_rom_staging(staging_dir: String) -> Dictionary:
	for dex in range(1, 650):
		for sub in ["front", "back", "front_shiny", "back_shiny"]:
			var p := staging_dir.path_join("sprites/%s/%d.png" % [sub, dex])
			if not FileAccess.file_exists(p):
				return {"ok": false, "error": "Missing ROM sprite %s/%d.png" % [sub, dex], "failed_check": "rom_sprite_exists"}
	for dex in ROM_METRIC_SPOT_DEX:
		for sub in ["front", "front_shiny"]:
			var p := staging_dir.path_join("sprites/%s/%d.png" % [sub, dex])
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
				return {"ok": false, "error": "Cannot load PNG %s" % p, "failed_check": "rom_sprite_load"}
			if img.get_width() != 96 or img.get_height() != 96:
				return {"ok": false, "error": "Sprite %s/%d.png is not 96x96" % [sub, dex], "failed_check": "rom_sprite_dims"}
			var metrics := Gen5CellsRef.compute_sprite_metrics(img)
			var mcheck := Gen5CellsRef.validate_sprite_metrics(metrics)
			if not bool(mcheck.get("ok", false)):
				return {
					"ok": false,
					"error": "Sprite #%d (%s) failed metric check: %s" % [dex, sub, str(mcheck.get("error", ""))],
					"failed_check": "rom_sprite_metrics",
				}
	return {"ok": true}

static func validate_data_staging(staging_dir: String) -> Dictionary:
	var sp_path := staging_dir.path_join("data/species.json")
	var mv_path := staging_dir.path_join("data/moves.json")
	var ls_path := staging_dir.path_join("data/learnsets.json")
	var tm_path := staging_dir.path_join("data/tm_learnsets.json")
	var mach_path := staging_dir.path_join("data/machines.json")
	var bf_path := staging_dir.path_join("data/battle_forms.json")
	var evo_path := staging_dir.path_join("data/evolutions.json")
	var en_sp_path := staging_dir.path_join("text/en/species.json")
	if not (FileAccess.file_exists(sp_path) and FileAccess.file_exists(mv_path) and FileAccess.file_exists(ls_path) and FileAccess.file_exists(tm_path) and FileAccess.file_exists(mach_path) and FileAccess.file_exists(bf_path) and FileAccess.file_exists(evo_path) and FileAccess.file_exists(en_sp_path)):
		return {"ok": false, "error": "Missing compiled data JSON files in staging.", "failed_check": "data_files_exist"}

	var sp_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(sp_path))
	var mv_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(mv_path))
	var ls_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(ls_path))
	var tm_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(tm_path))
	var mach_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(mach_path))
	var bf_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(bf_path))
	var evo_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(evo_path))
	var en_sp_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(en_sp_path))
	if not (sp_doc is Dictionary and mv_doc is Dictionary and ls_doc is Dictionary and tm_doc is Dictionary and mach_doc is Dictionary and bf_doc is Dictionary and evo_doc is Dictionary and en_sp_doc is Dictionary):
		return {"ok": false, "error": "Malformed JSON in staging.", "failed_check": "data_json_parse"}

	var species_map: Dictionary = sp_doc.get("species", {})
	var mega_map: Dictionary = sp_doc.get("mega_forms", {})
	if species_map.size() != 905:
		return {"ok": false, "error": "Expected 905 species, got %d" % species_map.size(), "failed_check": "species_count"}
	if mega_map.size() != 48:
		return {"ok": false, "error": "Expected 48 Mega forms, got %d" % mega_map.size(), "failed_check": "mega_count"}
	if (mv_doc as Dictionary).size() != 778:
		return {"ok": false, "error": "Expected 778 moves, got %d" % (mv_doc as Dictionary).size(), "failed_check": "move_count"}
	if (bf_doc as Dictionary).is_empty():
		return {"ok": false, "error": "Expected non-empty battle_forms.json", "failed_check": "battle_forms_non_empty"}
	if not ((mach_doc as Dictionary).get("by_item", {}) is Dictionary) or ((mach_doc as Dictionary).get("by_item", {}) as Dictionary).is_empty():
		return {"ok": false, "error": "Expected non-empty machines.json by_item", "failed_check": "machines_non_empty"}

	for dex in range(1, 906):
		var sp_entry: Dictionary = species_map.get(str(dex), {})
		if int(sp_entry.get("weight_hg", 0)) <= 0 or int(sp_entry.get("height_dm", 0)) <= 0:
			return {"ok": false, "error": "Missing positive weight_hg/height_dm for species #%d" % dex, "failed_check": "species_weight_height"}
		var ls_arr: Variant = (ls_doc as Dictionary).get(str(dex), [])
		if not (ls_arr is Array) or (ls_arr as Array).is_empty():
			return {"ok": false, "error": "Empty learnset for species #%d" % dex, "failed_check": "learnsets_non_empty"}

	for mid_key in (mv_doc as Dictionary).keys():
		var m_entry: Dictionary = (mv_doc as Dictionary)[mid_key]
		if not (m_entry.get("flags", null) is Array):
			return {"ok": false, "error": "Missing flags array for move #%s" % str(mid_key), "failed_check": "move_flags"}

	var evo_audit := DataPackImporterRef.audit_evolutions(evo_doc as Dictionary)
	if int(evo_audit.get("level_up_rows_without_condition", -1)) != 0 or bool(evo_audit.get("tyrogue_rows_identical", true)):
		return {
			"ok": false,
			"error": "Evolution audit failed: level_up_rows_without_condition=%d tyrogue_rows_identical=%s" % [int(evo_audit.get("level_up_rows_without_condition", -1)), str(evo_audit.get("tyrogue_rows_identical", true))],
			"failed_check": "evolutions_audit",
		}

	# Item 92 (Decision 87): verify the 4 past-value CSVs are pinned in the manifest and rolled back in staging
	var dp_manifest := DataPackImporterRef.load_json_res(DataPackImporterRef.DATA_PACK_MANIFEST_PATH)
	var manifest_files: Dictionary = dp_manifest.get("files", {})
	for past_csv in ["move_changelog.csv", "pokemon_abilities_past.csv", "pokemon_stats_past.csv", "pokemon_types_past.csv"]:
		if not manifest_files.has(past_csv):
			return {"ok": false, "error": "Missing past-value CSV in data_pack_manifest.json: %s" % past_csv, "failed_check": "past_manifest_" + past_csv}
	var mv296: Dictionary = (mv_doc as Dictionary).get("296", {})
	if int(mv296.get("power", 0)) != 70:
		return {"ok": false, "error": "Expected Gen 8 rollback move #296 power=70, got %s" % str(mv296.get("power", 0)), "failed_check": "gen8_move_296"}
	var sp475: Dictionary = species_map.get("475", {})
	var sp475_abils: Array = sp475.get("abilities", [])
	var sp900: Dictionary = species_map.get("900", {})
	var bf10188: Dictionary = (bf_doc as Dictionary).get("10188", {})
	if sp475_abils.size() != 1 or int(sp475_abils[0]) != 80 or int(sp900.get("hidden_ability_id", 0)) != 80 or int((bf10188.get("base_stats", {}) as Dictionary).get("atk", 0)) != 170:
		return {"ok": false, "error": "Gen 8 species/form rollback spot check failed (#475/#900/10188)", "failed_check": "gen8_species_rollback"}

	# 10 §7 typing checks
	for dex_str in EXPECTED_TYPING_CHECKS.keys():
		var expected_types: Array = EXPECTED_TYPING_CHECKS[dex_str]
		var sp_entry: Dictionary = species_map.get(dex_str, {})
		var actual_types: Array = sp_entry.get("types", [])
		if actual_types != expected_types:
			return {
				"ok": false,
				"error": "Typing mismatch for #%s: expected %s, got %s" % [dex_str, str(expected_types), str(actual_types)],
				"failed_check": "typing_check_" + dex_str,
			}

	# English name spot checks (#1, #487, #609, #887, #905)
	for check_dex in ["1", "487", "609", "887", "905"]:
		var nm := str((en_sp_doc as Dictionary).get(check_dex, ""))
		if nm == "" or nm.find("\ufffd") != -1:
			return {"ok": false, "error": "Invalid English name for #%s" % check_dex, "failed_check": "name_check_" + check_dex}

	# Fan sprite existence and 96x96 check for #650-905 and 48 Megas
	var target_ids: Array[int] = []
	for d in range(650, 906):
		target_ids.append(d)
	for pid_str in mega_map.keys():
		target_ids.append(int(pid_str))
	for tid in target_ids:
		for sub in ["front", "back", "front_shiny", "back_shiny"]:
			var p := staging_dir.path_join("sprites/%s/%d.png" % [sub, tid])
			if not FileAccess.file_exists(p):
				return {"ok": false, "error": "Missing fan sprite %s/%d.png" % [sub, tid], "failed_check": "fan_sprite_exists"}

	# Check #887 and normalized #796 (back) dimensions & variance
	for check_pair in [["front", 887], ["back", 796], ["back_shiny", 10041]]:
		var p := staging_dir.path_join("sprites/%s/%d.png" % [check_pair[0], int(check_pair[1])])
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
			return {"ok": false, "error": "Cannot load fan sprite %s" % p, "failed_check": "fan_sprite_load"}
		if img.get_width() != 96 or img.get_height() != 96:
			return {"ok": false, "error": "Fan sprite %s is not 96x96" % p, "failed_check": "fan_sprite_dims"}
		var metrics := Gen5CellsRef.compute_sprite_metrics(img)
		if float(metrics.get("rgb_variance", 0.0)) < 500.0 or int(metrics.get("opaque_px", 0)) < 200:
			return {"ok": false, "error": "Fan sprite %s failed quality gate" % p, "failed_check": "fan_sprite_metrics"}

	return {"ok": true}


static func _extract_box_icon_to_dir(
	fh: FileAccess,
	box_narc: Variant,
	sp_narc: Variant,
	box_palettes: Array,
	dex: int,
	box_dir: String
) -> bool:
	var icon_idx := 7 + dex * 2
	if icon_idx < 0 or icon_idx >= box_narc.file_count():
		return false
	var icon_lz := NitroLzRef.decompress(box_narc.read_subfile(fh, icon_idx))
	if not bool(icon_lz.get("ok", false)):
		return false
	var front_pal: Array = []
	var pal_idx := dex * 20 + 18
	if sp_narc != null and pal_idx < sp_narc.file_count():
		var pal_lz := NitroLzRef.decompress(sp_narc.read_subfile(fh, pal_idx))
		if bool(pal_lz.get("ok", false)):
			front_pal = NitroGfxRef.parse_nclr(pal_lz["data"])
	var img := NitroGfxRef.decode_box_icon_32(icon_lz["data"], box_palettes, front_pal)
	if img == null or img.is_empty():
		return false
	return img.save_png(box_dir.path_join("%d.png" % dex)) == OK


static func import_bw_pokemon_icons(
	rom_path: String,
	dex_ids: Array,
	cache_dir: String = DEFAULT_CACHE_DIR,
	allow_test_user_dir: bool = false
) -> Dictionary:
	var hdr := NdsFsRef.read_header(rom_path, true, allow_test_user_dir)
	if not bool(hdr.get("ok", false)):
		return hdr
	var abs_path := str(hdr["path"])
	var fh := FileAccess.open(abs_path, FileAccess.READ)
	if fh == null:
		return {"ok": false, "error": "Cannot open BW ROM file."}
	var fat := NdsFsRef.read_fat(fh, int(hdr["fat_offset"]), int(hdr["fat_size"]))
	var sprite_fid := NdsFsRef.resolve_archive_id(fh, hdr, fat, NdsFsRef.SPRITE_NARC_PATH, NdsFsRef.SPRITE_NARC_FALLBACK_ID)
	var box_fid := NdsFsRef.resolve_archive_id(fh, hdr, fat, NdsFsRef.BOX_ICON_NARC_PATH, NdsFsRef.BOX_ICON_NARC_FALLBACK_ID)
	if box_fid < 0:
		fh.close()
		return {"ok": false, "error": "Could not locate /a/0/0/7 box icon NARC in ROM."}
	var sp_narc: Variant = NarcArchiveRef.parse(fh, fat[sprite_fid].x, fat[sprite_fid].y) if sprite_fid >= 0 else null
	var box_narc := NarcArchiveRef.parse(fh, fat[box_fid].x, fat[box_fid].y)
	if box_narc == null or box_narc.file_count() < 10:
		fh.close()
		return {"ok": false, "error": "Invalid /a/0/0/7 box icon NARC."}
	var box_pal_lz := NitroLzRef.decompress(box_narc.read_subfile(fh, 0))
	var box_palettes := NitroGfxRef.parse_nclr_multi(box_pal_lz["data"], 8) if bool(box_pal_lz.get("ok", false)) else []
	if box_palettes.is_empty():
		fh.close()
		return {"ok": false, "error": "Failed to parse /a/0/0/7 palette."}

	var box_dir := ProjectSettings.globalize_path(cache_dir.trim_suffix("/")).path_join("icons/pokemon_box")
	DirAccess.make_dir_recursive_absolute(box_dir)
	var written := 0
	for dv in dex_ids:
		var dex := int(dv)
		if dex < 1 or dex > 649:
			continue
		if _extract_box_icon_to_dir(fh, box_narc, sp_narc, box_palettes, dex, box_dir):
			written += 1
	fh.close()
	return {"ok": true, "written": written, "cache_dir": cache_dir}
