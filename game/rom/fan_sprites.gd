class_name FanSpritesImporter
extends RefCounted

## Gen 6–8 (#650–905) and 48 Mega form fan-sprite verifier & 96x96 normalizer (Item 45).
## Contract: docs/design_rom_asset_pipeline.md §2a, §6–7 & docs/implementation_plan_rom_importer.md §3.3.

const MapFetcher := preload("res://world/region_import/map_fetcher.gd")
const DataPackImporterRef := preload("res://rom/data_pack.gd")

const DATA_SOURCES_PATH := "res://config/data_sources.json"
const FAN_SPRITE_MANIFEST_PATH := "res://config/fan_sprite_manifest.json"
const FAN_SPRITE_CREDITS_PATH := "res://config/fan_sprite_credits.json"

const VARIANT_SPECS := [
	{"manifest_key": "front", "upstream_sub": "", "local_sub": "front", "cache_sub": "front"},
	{"manifest_key": "back", "upstream_sub": "back", "local_sub": "back", "cache_sub": "back"},
	{"manifest_key": "shiny", "upstream_sub": "shiny", "local_sub": "shiny", "cache_sub": "front_shiny"},
	{"manifest_key": "back_shiny", "upstream_sub": "back/shiny", "local_sub": "back_shiny", "cache_sub": "back_shiny"},
]

static func validate_sprite_id(sprite_id: int) -> Dictionary:
	if sprite_id < 650:
		return {
			"ok": false,
			"error": "Guardrail violation: fan sprite ID %d < 650 is forbidden (#1-649 come from the player's Black/White ROM)." % sprite_id,
		}
	return {"ok": true}

static func build_fan_sprite_url(raw_base_url: String, upstream_sub: String, sprite_id: int) -> Dictionary:
	var check := validate_sprite_id(sprite_id)
	if not bool(check.get("ok", false)):
		return check
	var base := raw_base_url.trim_suffix("/")
	var url := "%s/%d.png" % [base, sprite_id] if upstream_sub == "" else "%s/%s/%d.png" % [base, upstream_sub, sprite_id]
	return {"ok": true, "url": url}

static func normalize_image_to_96x96(src: Image) -> Image:
	var work := src.duplicate() as Image
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	var w := work.get_width()
	var h := work.get_height()
	if w == 96 and h == 96:
		return work
	var canvas := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var src_x := maxi(0, (w - 96) / 2)
	var src_y := maxi(0, (h - 96) / 2)
	var copy_w := mini(96, w - src_x)
	var copy_h := mini(96, h - src_y)
	var dst_x := maxi(0, (96 - copy_w) / 2)
	var dst_y := maxi(0, (96 - copy_h) / 2)
	canvas.blit_rect(work, Rect2i(src_x, src_y, copy_w, copy_h), Vector2i(dst_x, dst_y))
	return canvas

static func _fetch_sprite_bytes(
	sprite_id: int,
	spec: Dictionary,
	raw_base_url: String,
	local_pack_dir: String,
	fetcher: Variant
) -> Dictionary:
	var check := validate_sprite_id(sprite_id)
	if not bool(check.get("ok", false)):
		return check
	if local_pack_dir != "":
		var sub1 := str(spec["local_sub"])
		var sub2 := str(spec["cache_sub"])
		var p1 := local_pack_dir.path_join("sprites").path_join(sub1).path_join("%d.png" % sprite_id)
		var p2 := local_pack_dir.path_join("sprites").path_join(sub2).path_join("%d.png" % sprite_id)
		var chosen := p1 if FileAccess.file_exists(p1) else (p2 if FileAccess.file_exists(p2) else "")
		if chosen == "":
			return {"ok": false, "error": "Missing local fan sprite %s/%d.png" % [sub1, sprite_id]}
		return {"ok": true, "body": FileAccess.get_file_as_bytes(chosen)}
	var url_res := build_fan_sprite_url(raw_base_url, str(spec["upstream_sub"]), sprite_id)
	if not bool(url_res.get("ok", false)):
		return url_res
	var active_fetcher = fetcher if fetcher != null else MapFetcher.new()
	return active_fetcher.download_https_url(str(url_res["url"]), 4194304)

static func verify_and_stage_fan_sprites(
	staging_dir: String,
	local_pack_dir: String = "",
	fetcher: Variant = null
) -> Dictionary:
	var sources := DataPackImporterRef.load_json_res(DATA_SOURCES_PATH)
	var manifest := DataPackImporterRef.load_json_res(FAN_SPRITE_MANIFEST_PATH)
	if sources.is_empty() or manifest.is_empty():
		return {"ok": false, "error": "Missing data_sources.json or fan_sprite_manifest.json"}

	var fs_meta: Dictionary = sources.get("fan_sprites", {})
	var raw_base_url := str(fs_meta.get("raw_base_url", ""))
	var files_by_variant: Dictionary = manifest.get("files", {})
	if files_by_variant.is_empty():
		return {"ok": false, "error": "Empty files map in fan_sprite_manifest.json"}

	for spec in VARIANT_SPECS:
		var out_sub := staging_dir.path_join("sprites").path_join(str(spec["cache_sub"]))
		if not DirAccess.dir_exists_absolute(out_sub):
			DirAccess.make_dir_recursive_absolute(out_sub)

	var total_written := 0
	var normalized_count := 0
	var target_ids_seen := {}

	for spec in VARIANT_SPECS:
		var mkey := str(spec["manifest_key"])
		var cache_sub := str(spec["cache_sub"])
		var vmap: Dictionary = files_by_variant.get(mkey, {})
		if vmap.is_empty():
			return {"ok": false, "error": "Missing variant '%s' in fan_sprite_manifest.json" % mkey}
		var id_keys := vmap.keys()
		id_keys.sort_custom(func(a, b): return int(a) < int(b))
		for id_str_var in id_keys:
			var id_str := str(id_str_var)
			var sprite_id := int(id_str)
			var id_check := validate_sprite_id(sprite_id)
			if not bool(id_check.get("ok", false)):
				return id_check
			var expected: Dictionary = vmap[id_str]
			var exp_sha := str(expected.get("sha256", "")).to_lower()
			var exp_size := int(expected.get("size", -1))

			var fetch_res := _fetch_sprite_bytes(sprite_id, spec, raw_base_url, local_pack_dir, fetcher)
			if not bool(fetch_res.get("ok", false)):
				return {
					"ok": false,
					"error": "Failed to fetch %s/%d.png: %s" % [mkey, sprite_id, str(fetch_res.get("error", ""))],
					"failed_file": "%s/%d.png" % [mkey, sprite_id],
				}
			var body: PackedByteArray = fetch_res.get("body", PackedByteArray())
			if body.size() != exp_size:
				return {
					"ok": false,
					"error": "Size mismatch for %s/%d.png: expected %d, got %d" % [mkey, sprite_id, exp_size, body.size()],
					"failed_file": "%s/%d.png" % [mkey, sprite_id],
				}
			var actual_sha := DataPackImporterRef.compute_bytes_sha256(body)
			if actual_sha != exp_sha:
				return {
					"ok": false,
					"error": "SHA-256 mismatch for %s/%d.png: expected %s, got %s" % [mkey, sprite_id, exp_sha, actual_sha],
					"failed_file": "%s/%d.png" % [mkey, sprite_id],
				}

			var img := Image.new()
			var load_err := img.load_png_from_buffer(body)
			if load_err != OK or img.get_width() < 32 or img.get_height() < 32:
				return {
					"ok": false,
					"error": "Invalid PNG for %s/%d.png" % [mkey, sprite_id],
					"failed_file": "%s/%d.png" % [mkey, sprite_id],
				}
			var out_path := staging_dir.path_join("sprites").path_join(cache_sub).path_join("%d.png" % sprite_id)
			if img.get_width() == 96 and img.get_height() == 96:
				var fh := FileAccess.open(out_path, FileAccess.WRITE)
				if fh == null:
					return {"ok": false, "error": "Cannot write %s" % out_path}
				fh.store_buffer(body)
				fh.close()
			else:
				var norm := normalize_image_to_96x96(img)
				if norm.save_png(out_path) != OK:
					return {"ok": false, "error": "Failed to save normalized 96x96 PNG to %s" % out_path}
				normalized_count += 1
			total_written += 1
			target_ids_seen[sprite_id] = true

	return {
		"ok": true,
		"source_commit": str(manifest.get("source_commit", "")),
		"total_files": total_written,
		"target_count": target_ids_seen.size(),
		"normalized_count": normalized_count,
		"pending_species_dex": manifest.get("pending_species_dex", []),
		"pending_mega_pokemon_ids": manifest.get("pending_mega_pokemon_ids", []),
	}
