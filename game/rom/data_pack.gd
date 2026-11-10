class_name DataPackImporter
extends RefCounted

## Gen 1–8 PokéAPI CSV downloader, SHA-256 verifier, and JSON compiler (Item 45).
## Contract: docs/design_rom_asset_pipeline.md §2a, §3, §6–7 & docs/implementation_plan_rom_importer.md §3.

const MapFetcher := preload("res://world/region_import/map_fetcher.gd")

const DATA_SOURCES_PATH := "res://config/data_sources.json"
const DATA_PACK_MANIFEST_PATH := "res://config/data_pack_manifest.json"
const FAN_SPRITE_MANIFEST_PATH := "res://config/fan_sprite_manifest.json"

const LEARNSET_VG_PRIORITY := [20, 24, 23, 19, 18]

const STAT_KEY_BY_ID := {
	1: "hp",
	2: "atk",
	3: "def",
	4: "spa",
	5: "spd",
	6: "spe",
}

const DAMAGE_CLASS_BY_ID := {
	1: "status",
	2: "physical",
	3: "special",
}

static func load_json_res(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		return {}
	var raw := FileAccess.get_file_as_string(res_path)
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

static func get_consent_summary() -> Dictionary:
	var sources := load_json_res(DATA_SOURCES_PATH)
	var dp_man := load_json_res(DATA_PACK_MANIFEST_PATH)
	var fs_man := load_json_res(FAN_SPRITE_MANIFEST_PATH)
	var csv_bytes := int(dp_man.get("total_bytes", 0))
	var spr_bytes := int(fs_man.get("total_bytes", 0))
	var total_bytes := csv_bytes + spr_bytes
	var size_mib := snappedf(float(total_bytes) / (1024.0 * 1024.0), 0.1)
	var dp_info: Dictionary = sources.get("data_pack", {})
	var fs_info: Dictionary = sources.get("fan_sprites", {})
	return {
		"csv_bytes": csv_bytes,
		"sprite_bytes": spr_bytes,
		"total_bytes": total_bytes,
		"size_mib": size_mib,
		"title": "Download Creature Data & Fan Sprites (%.1f MiB)" % size_mib,
		"confirm_button": "Download (%.1f MiB)" % size_mib,
		"cancel_button": "Not now (use placeholders)",
		"pokeapi_commit": str(dp_info.get("commit", "")),
		"pokeapi_license": str(dp_info.get("license", "")),
		"pokeapi_attribution": str(dp_info.get("attribution", "")),
		"sprites_commit": str(fs_info.get("commit", "")),
		"fan_sprites_license": str(fs_info.get("license", "")),
		"fan_sprites_attribution": str(fs_info.get("attribution", "")),
	}

static func compute_bytes_sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish().hex_encode().to_lower()

static func _fetch_csv_bytes(
	fname: String,
	raw_base_url: String,
	local_pack_dir: String,
	fetcher: Variant
) -> Dictionary:
	if local_pack_dir != "":
		var candidate := local_pack_dir.path_join("csv").path_join(fname)
		if not FileAccess.file_exists(candidate):
			candidate = local_pack_dir.path_join(fname)
		if not FileAccess.file_exists(candidate):
			return {"ok": false, "error": "Missing local CSV file: %s" % fname}
		var b := FileAccess.get_file_as_bytes(candidate)
		return {"ok": true, "body": b}
	var active_fetcher = fetcher if fetcher != null else MapFetcher.new()
	var url := raw_base_url.trim_suffix("/") + "/" + fname
	return active_fetcher.download_https_url(url, 16777216)

static func _read_csv_dicts(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return rows
	if fh.eof_reached():
		fh.close()
		return rows
	var raw_hdr := fh.get_csv_line()
	var headers: Array[String] = []
	for h in raw_hdr:
		headers.append(h.strip_edges())
	var ncols := headers.size()
	while not fh.eof_reached():
		var line := fh.get_csv_line()
		if line.is_empty() or (line.size() == 1 and line[0].strip_edges() == ""):
			continue
		var d := {}
		var limit := mini(ncols, line.size())
		for i in range(limit):
			d[headers[i]] = line[i].trim_suffix("\r")
		rows.append(d)
	fh.close()
	return rows

static func _write_json_file(path: String, payload: Variant) -> bool:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		return false
	fh.store_string(JSON.stringify(payload) + "\n")
	fh.close()
	return true

static func _remove_dir_recursive(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var da := DirAccess.open(dir_path)
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full := dir_path.path_join(entry)
				if da.current_is_dir():
					_remove_dir_recursive(full)
				else:
					DirAccess.remove_absolute(full)
			entry = da.get_next()
		da.list_dir_end()
	DirAccess.remove_absolute(dir_path)

static func verify_and_stage_data_pack(
	staging_dir: String,
	local_pack_dir: String = "",
	fetcher: Variant = null
) -> Dictionary:
	var sources := load_json_res(DATA_SOURCES_PATH)
	var manifest := load_json_res(DATA_PACK_MANIFEST_PATH)
	if sources.is_empty() or manifest.is_empty():
		return {"ok": false, "error": "Missing data_sources.json or data_pack_manifest.json"}

	var dp_meta: Dictionary = sources.get("data_pack", {})
	var raw_base_url := str(dp_meta.get("raw_base_url", ""))
	var files_manifest: Dictionary = manifest.get("files", {})
	if files_manifest.is_empty():
		return {"ok": false, "error": "Empty files map in data_pack_manifest.json"}

	var tmp_csv_dir := staging_dir.path_join("_tmp_csv")
	_remove_dir_recursive(tmp_csv_dir)
	DirAccess.make_dir_recursive_absolute(tmp_csv_dir)

	var fnames := files_manifest.keys()
	fnames.sort()
	for fname_var in fnames:
		var fname := str(fname_var)
		var expected: Dictionary = files_manifest[fname]
		var exp_sha := str(expected.get("sha256", "")).to_lower()
		var exp_size := int(expected.get("size", -1))

		var res := _fetch_csv_bytes(fname, raw_base_url, local_pack_dir, fetcher)
		if not bool(res.get("ok", false)):
			_remove_dir_recursive(tmp_csv_dir)
			return {
				"ok": false,
				"error": "Failed to fetch %s: %s" % [fname, str(res.get("error", "download error"))],
				"failed_file": fname,
			}
		var body: PackedByteArray = res.get("body", PackedByteArray())
		if body.size() != exp_size:
			_remove_dir_recursive(tmp_csv_dir)
			return {
				"ok": false,
				"error": "Size mismatch for %s: expected %d, got %d" % [fname, exp_size, body.size()],
				"failed_file": fname,
			}
		var actual_sha := compute_bytes_sha256(body)
		if actual_sha != exp_sha:
			_remove_dir_recursive(tmp_csv_dir)
			return {
				"ok": false,
				"error": "SHA-256 mismatch for %s: expected %s, got %s" % [fname, exp_sha, actual_sha],
				"failed_file": fname,
			}
		var out_csv := FileAccess.open(tmp_csv_dir.path_join(fname), FileAccess.WRITE)
		if out_csv == null:
			_remove_dir_recursive(tmp_csv_dir)
			return {"ok": false, "error": "Cannot write temporary CSV %s" % fname}
		out_csv.store_buffer(body)
		out_csv.close()

	var compile_res := _compile_verified_csvs(tmp_csv_dir, staging_dir, str(manifest.get("source_commit", "")))
	_remove_dir_recursive(tmp_csv_dir)
	return compile_res

static func _compile_verified_csvs(csv_dir: String, staging_dir: String, source_commit: String) -> Dictionary:
	# 1. Types (id 1..18)
	var types_by_id := {}
	for r in _read_csv_dicts(csv_dir.path_join("types.csv")):
		var tid := int(r.get("id", "0"))
		if tid >= 1 and tid <= 18:
			types_by_id[tid] = str(r.get("identifier", ""))

	# 2. Pokemon stats & effort yields (pokemon_id -> {stats, ev_yield})
	var stats_by_pid := {}
	var ev_by_pid := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_stats.csv")):
		var pid := int(r.get("pokemon_id", "0"))
		var sid := int(r.get("stat_id", "0"))
		if not STAT_KEY_BY_ID.has(sid):
			continue
		var skey: String = STAT_KEY_BY_ID[sid]
		if not stats_by_pid.has(pid):
			stats_by_pid[pid] = {"hp": 1, "atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}
			ev_by_pid[pid] = {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
		stats_by_pid[pid][skey] = int(r.get("base_stat", "1"))
		ev_by_pid[pid][skey] = int(r.get("effort", "0"))

	# 3. Pokemon types (pokemon_id -> Array of [slot, type_identifier])
	var raw_types_by_pid := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_types.csv")):
		var pid := int(r.get("pokemon_id", "0"))
		var tid := int(r.get("type_id", "0"))
		var slot := int(r.get("slot", "1"))
		if types_by_id.has(tid):
			if not raw_types_by_pid.has(pid):
				raw_types_by_pid[pid] = []
			raw_types_by_pid[pid].append([slot, types_by_id[tid]])

	var types_by_pid := {}
	for pid in raw_types_by_pid.keys():
		var pairs: Array = raw_types_by_pid[pid]
		pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var tlist: Array[String] = []
		for p in pairs:
			tlist.append(str(p[1]))
		types_by_pid[pid] = tlist

	# 4. Pokemon abilities (pokemon_id -> {abilities: Array[int], hidden_ability_id: int})
	var raw_abil_by_pid := {}
	var hidden_abil_by_pid := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_abilities.csv")):
		var pid := int(r.get("pokemon_id", "0"))
		var aid := int(r.get("ability_id", "0"))
		var is_hidden := int(r.get("is_hidden", "0"))
		var slot := int(r.get("slot", "1"))
		if is_hidden == 1:
			hidden_abil_by_pid[pid] = aid
		else:
			if not raw_abil_by_pid.has(pid):
				raw_abil_by_pid[pid] = []
			raw_abil_by_pid[pid].append([slot, aid])

	var abil_by_pid := {}
	for pid in raw_abil_by_pid.keys():
		var pairs: Array = raw_abil_by_pid[pid]
		pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var alist: Array[int] = []
		for p in pairs:
			alist.append(int(p[1]))
		abil_by_pid[pid] = alist

	# 5. Pokemon table (id -> species_id, base_experience, height, weight)
	var pokemon_by_id := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon.csv")):
		var pid := int(r.get("id", "0"))
		pokemon_by_id[pid] = {
			"species_id": int(r.get("species_id", "0")),
			"base_exp": int(r.get("base_experience", "0")),
			"height": int(r.get("height", "0")),
			"weight": int(r.get("weight", "0")),
		}

	# 6. Mega forms (is_mega == 1 and introduced_in_version_group_id in {15, 16})
	var mega_forms_by_dex := {}
	var mega_forms_by_pid := {}
	var mega_form_count := 0
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_forms.csv")):
		if int(r.get("is_mega", "0")) != 1:
			continue
		var vg := int(r.get("introduced_in_version_group_id", "0"))
		if vg != 15 and vg != 16:
			continue
		var pid := int(r.get("pokemon_id", "0"))
		var form_id := int(r.get("id", "0"))
		var form_ident := str(r.get("form_identifier", "mega"))
		var pinfo: Dictionary = pokemon_by_id.get(pid, {})
		var dex := int(pinfo.get("species_id", 0))
		if dex < 1 or dex > 905:
			continue
		var m_abils: Array = abil_by_pid.get(pid, [])
		var m_ability_id := int(m_abils[0]) if not m_abils.is_empty() else 0
		var m_entry := {
			"form_id": form_id,
			"pokemon_id": pid,
			"species_dex": dex,
			"form": form_ident,
			"identifier": str(r.get("identifier", "")),
			"base_stats": stats_by_pid.get(pid, {}),
			"types": types_by_pid.get(pid, []),
			"ability_id": m_ability_id,
		}
		if not mega_forms_by_dex.has(dex):
			mega_forms_by_dex[dex] = []
		mega_forms_by_dex[dex].append(m_entry)
		mega_forms_by_pid[str(pid)] = m_entry
		mega_form_count += 1

	# 7. Species 1..905
	var species_out := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_species.csv")):
		var dex := int(r.get("id", "0"))
		var gen := int(r.get("generation_id", "0"))
		if dex < 1 or dex > 905 or gen < 1 or gen > 8:
			continue
		var pinfo: Dictionary = pokemon_by_id.get(dex, {})
		var ev_from_str := str(r.get("evolves_from_species_id", ""))
		var ev_from := int(ev_from_str) if ev_from_str != "" else 0
		species_out[str(dex)] = {
			"dex": dex,
			"generation_id": gen,
			"base_stats": stats_by_pid.get(dex, {}),
			"types": types_by_pid.get(dex, []),
			"abilities": abil_by_pid.get(dex, []),
			"hidden_ability_id": int(hidden_abil_by_pid.get(dex, 0)),
			"catch_rate": int(r.get("capture_rate", "45")),
			"base_exp": int(pinfo.get("base_exp", 0)),
			"ev_yield": ev_by_pid.get(dex, {}),
			"growth_rate_id": int(r.get("growth_rate_id", "2")),
			"gender_rate": int(r.get("gender_rate", "4")),
			"base_happiness": int(r.get("base_happiness", "70")),
			"evolves_from_dex": ev_from,
			"evolution_chain_id": int(r.get("evolution_chain_id", "0")),
			"is_baby": int(r.get("is_baby", "0")) == 1,
			"is_legendary": int(r.get("is_legendary", "0")) == 1,
			"is_mythical": int(r.get("is_mythical", "0")) == 1,
			"mega_forms": mega_forms_by_dex.get(dex, []),
		}

	# 8. Moves (Gen 1..8, id < 10000, exclude Gen 7 pp==1 Z-Moves and Gen 8 max-* Moves -> 778 moves)
	var move_meta_by_id := {}
	for r in _read_csv_dicts(csv_dir.path_join("move_meta.csv")):
		var mid := int(r.get("move_id", "0"))
		move_meta_by_id[mid] = {
			"meta_category_id": int(r.get("meta_category_id", "0")),
			"meta_ailment_id": int(r.get("meta_ailment_id", "0")),
			"min_hits": int(r.get("min_hits", "0")) if str(r.get("min_hits", "")) != "" else 0,
			"max_hits": int(r.get("max_hits", "0")) if str(r.get("max_hits", "")) != "" else 0,
			"min_turns": int(r.get("min_turns", "0")) if str(r.get("min_turns", "")) != "" else 0,
			"max_turns": int(r.get("max_turns", "0")) if str(r.get("max_turns", "")) != "" else 0,
			"drain": int(r.get("drain", "0")),
			"healing": int(r.get("healing", "0")),
			"crit_rate": int(r.get("crit_rate", "0")),
			"ailment_chance": int(r.get("ailment_chance", "0")),
			"flinch_chance": int(r.get("flinch_chance", "0")),
			"stat_chance": int(r.get("stat_chance", "0")),
		}

	var move_stat_changes := {}
	for r in _read_csv_dicts(csv_dir.path_join("move_meta_stat_changes.csv")):
		var mid := int(r.get("move_id", "0"))
		var sid := int(r.get("stat_id", "0"))
		var chg := int(r.get("change", "0"))
		if not move_stat_changes.has(mid):
			move_stat_changes[mid] = []
		move_stat_changes[mid].append({"stat_id": sid, "change": chg})

	var moves_out := {}
	var valid_move_ids := {}
	for r in _read_csv_dicts(csv_dir.path_join("moves.csv")):
		var mid := int(r.get("id", "0"))
		var gen_str := str(r.get("generation_id", ""))
		if gen_str == "" or mid <= 0 or mid >= 10000:
			continue
		var gen := int(gen_str)
		if gen < 1 or gen > 8:
			continue
		var pp_str := str(r.get("pp", ""))
		var pp := int(pp_str) if pp_str != "" else 0
		var ident := str(r.get("identifier", ""))
		if gen == 7 and pp == 1:
			continue
		if gen == 8 and ident.begins_with("max-"):
			continue
		var tid := int(r.get("type_id", "1"))
		if not types_by_id.has(tid):
			continue
		var dcid := int(r.get("damage_class_id", "1"))
		var power_str := str(r.get("power", ""))
		var acc_str := str(r.get("accuracy", ""))
		var eff_chance_str := str(r.get("effect_chance", ""))
		valid_move_ids[mid] = true
		moves_out[str(mid)] = {
			"id": mid,
			"generation_id": gen,
			"type": str(types_by_id[tid]),
			"damage_class": str(DAMAGE_CLASS_BY_ID.get(dcid, "status")),
			"power": int(power_str) if power_str != "" else 0,
			"pp": pp,
			"accuracy": int(acc_str) if acc_str != "" else 0,
			"priority": int(r.get("priority", "0")),
			"target_id": int(r.get("target_id", "10")),
			"effect_id": int(r.get("effect_id", "0")),
			"effect_chance": int(eff_chance_str) if eff_chance_str != "" else 0,
			"meta": move_meta_by_id.get(mid, {}),
			"stat_changes": move_stat_changes.get(mid, []),
		}

	# 9. Stream pokemon_moves.csv for level-up learnsets across priority [20, 24, 23, 19, 18]
	var allowed_vgs := {20: true, 24: true, 23: true, 19: true, 18: true}
	var per_dex_vg_moves := {}
	var pm_fh := FileAccess.open(csv_dir.path_join("pokemon_moves.csv"), FileAccess.READ)
	if pm_fh == null:
		return {"ok": false, "error": "Cannot open pokemon_moves.csv"}
	if not pm_fh.eof_reached():
		pm_fh.get_csv_line() # skip header
	while not pm_fh.eof_reached():
		var row := pm_fh.get_csv_line()
		if row.size() < 5:
			continue
		if row[3] != "1":
			continue
		var vg := int(row[1])
		if not allowed_vgs.has(vg):
			continue
		var pid := int(row[0])
		if pid < 1 or pid > 905:
			continue
		var mid := int(row[2])
		if not valid_move_ids.has(mid):
			continue
		var lvl := int(row[4])
		var ord := int(row[5]) if (row.size() > 5 and row[5] != "") else 0
		if not per_dex_vg_moves.has(pid):
			per_dex_vg_moves[pid] = {}
		var vg_map: Dictionary = per_dex_vg_moves[pid]
		if not vg_map.has(vg):
			vg_map[vg] = []
		vg_map[vg].append([lvl, ord, mid])
	pm_fh.close()

	var learnsets_out := {}
	for dex in range(1, 906):
		var vg_map: Dictionary = per_dex_vg_moves.get(dex, {})
		var chosen_list: Array = []
		for vg in LEARNSET_VG_PRIORITY:
			if vg_map.has(vg):
				chosen_list = vg_map[vg]
				break
		chosen_list.sort_custom(func(a, b):
			if int(a[0]) != int(b[0]):
				return int(a[0]) < int(b[0])
			if int(a[1]) != int(b[1]):
				return int(a[1]) < int(b[1])
			return int(a[2]) < int(b[2])
		)
		var formatted: Array = []
		var seen := {}
		for item in chosen_list:
			var key := "%d_%d" % [int(item[0]), int(item[2])]
			if seen.has(key):
				continue
			seen[key] = true
			formatted.append({"level": int(item[0]), "move_id": int(item[2])})
		learnsets_out[str(dex)] = formatted

	# 10. Evolutions
	var trigger_by_id := {}
	for r in _read_csv_dicts(csv_dir.path_join("evolution_triggers.csv")):
		trigger_by_id[int(r.get("id", "0"))] = str(r.get("identifier", "level-up"))

	var evolutions_out := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_evolution.csv")):
		var evolved_dex := int(r.get("evolved_species_id", "0"))
		if evolved_dex < 1 or evolved_dex > 905 or not species_out.has(str(evolved_dex)):
			continue
		var sp_entry: Dictionary = species_out[str(evolved_dex)]
		var from_dex := int(sp_entry.get("evolves_from_dex", 0))
		if from_dex < 1 or from_dex > 905:
			continue
		var trig_id := int(r.get("evolution_trigger_id", "1"))
		var min_lvl_str := str(r.get("minimum_level", ""))
		var trig_item_str := str(r.get("trigger_item_id", ""))
		var held_item_str := str(r.get("held_item_id", ""))
		var min_hap_str := str(r.get("minimum_happiness", ""))
		var known_move_str := str(r.get("known_move_id", ""))
		var known_type_str := str(r.get("known_move_type_id", ""))
		var gender_str := str(r.get("gender_id", ""))
		var tod := str(r.get("time_of_day", ""))
		var evo_rule := {
			"to_dex": evolved_dex,
			"trigger": str(trigger_by_id.get(trig_id, "level-up")),
			"minimum_level": int(min_lvl_str) if min_lvl_str != "" else 0,
			"trigger_item_id": int(trig_item_str) if trig_item_str != "" else 0,
			"held_item_id": int(held_item_str) if held_item_str != "" else 0,
			"minimum_happiness": int(min_hap_str) if min_hap_str != "" else 0,
			"known_move_id": int(known_move_str) if known_move_str != "" else 0,
			"known_move_type_id": int(known_type_str) if known_type_str != "" else 0,
			"gender_id": int(gender_str) if gender_str != "" else 0,
			"time_of_day": tod,
		}
		var from_key := str(from_dex)
		if not evolutions_out.has(from_key):
			evolutions_out[from_key] = []
		evolutions_out[from_key].append(evo_rule)

	# 11. Items
	var cat_by_id := {}
	for r in _read_csv_dicts(csv_dir.path_join("item_categories.csv")):
		cat_by_id[int(r.get("id", "0"))] = {
			"pocket_id": int(r.get("pocket_id", "0")),
			"identifier": str(r.get("identifier", "")),
		}
	var items_out := {}
	for r in _read_csv_dicts(csv_dir.path_join("items.csv")):
		var iid := int(r.get("id", "0"))
		if iid <= 0:
			continue
		var cid := int(r.get("category_id", "0"))
		var cinfo: Dictionary = cat_by_id.get(cid, {})
		var fp_str := str(r.get("fling_power", ""))
		items_out[str(iid)] = {
			"id": iid,
			"category_id": cid,
			"pocket_id": int(cinfo.get("pocket_id", 0)),
			"category": str(cinfo.get("identifier", "")),
			"cost": int(r.get("cost", "0")),
			"fling_power": int(fp_str) if fp_str != "" else 0,
		}

	# 12. English Names (local_language_id == 9)
	var en_species := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_species_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var sid := int(r.get("pokemon_species_id", "0"))
			if sid >= 1 and sid <= 905:
				en_species[str(sid)] = str(r.get("name", ""))

	var en_forms := {}
	for r in _read_csv_dicts(csv_dir.path_join("pokemon_form_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var fid := int(r.get("pokemon_form_id", "0"))
			var pname := str(r.get("pokemon_name", ""))
			var fname := str(r.get("form_name", ""))
			en_forms[str(fid)] = pname if pname != "" else fname

	var en_moves := {}
	for r in _read_csv_dicts(csv_dir.path_join("move_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var mid := int(r.get("move_id", "0"))
			if valid_move_ids.has(mid):
				en_moves[str(mid)] = str(r.get("name", ""))

	var en_abilities := {}
	for r in _read_csv_dicts(csv_dir.path_join("ability_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var aid := int(r.get("ability_id", "0"))
			if aid > 0 and aid < 10000:
				en_abilities[str(aid)] = str(r.get("name", ""))

	var en_items := {}
	for r in _read_csv_dicts(csv_dir.path_join("item_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var iid := int(r.get("item_id", "0"))
			if iid > 0:
				en_items[str(iid)] = str(r.get("name", ""))

	var en_types := {}
	for r in _read_csv_dicts(csv_dir.path_join("type_names.csv")):
		if str(r.get("local_language_id", "")) == "9":
			var tid := int(r.get("type_id", "0"))
			if tid >= 1 and tid <= 18:
				en_types[str(tid)] = str(r.get("name", ""))

	var species_doc := {
		"species": species_out,
		"mega_forms": mega_forms_by_pid,
	}
	var data_dir := staging_dir.path_join("data")
	var text_dir := staging_dir.path_join("text").path_join("en")
	if not _write_json_file(data_dir.path_join("species.json"), species_doc):
		return {"ok": false, "error": "Failed to write data/species.json"}
	if not _write_json_file(data_dir.path_join("learnsets.json"), learnsets_out):
		return {"ok": false, "error": "Failed to write data/learnsets.json"}
	if not _write_json_file(data_dir.path_join("moves.json"), moves_out):
		return {"ok": false, "error": "Failed to write data/moves.json"}
	if not _write_json_file(data_dir.path_join("evolutions.json"), evolutions_out):
		return {"ok": false, "error": "Failed to write data/evolutions.json"}
	if not _write_json_file(data_dir.path_join("items.json"), items_out):
		return {"ok": false, "error": "Failed to write data/items.json"}

	if not _write_json_file(text_dir.path_join("species.json"), en_species):
		return {"ok": false, "error": "Failed to write text/en/species.json"}
	if not _write_json_file(text_dir.path_join("forms.json"), en_forms):
		return {"ok": false, "error": "Failed to write text/en/forms.json"}
	if not _write_json_file(text_dir.path_join("moves.json"), en_moves):
		return {"ok": false, "error": "Failed to write text/en/moves.json"}
	if not _write_json_file(text_dir.path_join("abilities.json"), en_abilities):
		return {"ok": false, "error": "Failed to write text/en/abilities.json"}
	if not _write_json_file(text_dir.path_join("items.json"), en_items):
		return {"ok": false, "error": "Failed to write text/en/items.json"}
	if not _write_json_file(text_dir.path_join("types.json"), en_types):
		return {"ok": false, "error": "Failed to write text/en/types.json"}

	return {
		"ok": true,
		"source_commit": source_commit,
		"species_count": species_out.size(),
		"mega_form_count": mega_form_count,
		"move_count": moves_out.size(),
	}
