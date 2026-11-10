class_name AssetDB
extends RefCounted

## Runtime Asset Seam over user://rom_cache/ and repo-safe configs (Item 8, Item 45).
## Contract: docs/design_rom_asset_pipeline.md §6, §10 & docs/implementation_plan_rom_importer.md §5.
## No module outside game/rom/ reads user://rom_cache/ directly.

const DEFAULT_CACHE_DIR := "user://rom_cache"
const TYPE_CHART_PATH := "res://config/type_chart.json"
const FAN_SPRITE_CREDITS_PATH := "res://config/fan_sprite_credits.json"
const TEXTURE_LRU_CAPACITY := 64

const KIND_TO_FILE := {
	"species": "species.json",
	"form": "forms.json",
	"forms": "forms.json",
	"move": "moves.json",
	"moves": "moves.json",
	"ability": "abilities.json",
	"abilities": "abilities.json",
	"item": "items.json",
	"items": "items.json",
	"type": "types.json",
	"types": "types.json",
}

# Hardcoded Mega form -> pokemon_id lookup from fan_sprite_credits.json so sprite_front(dex, shiny, "mega")
# works even before data/species.json is loaded.
static var _credits_cache: Dictionary = {}
static var _type_chart_cache: Dictionary = {}
static var _json_cache_by_dir: Dictionary = {}
static var _texture_lru_map: Dictionary = {}
static var _texture_lru_order: Array[String] = []
static var _silhouette_cache: Dictionary = {}
static var _item_placeholder_tex: ImageTexture = null

static func tile_atlas() -> Variant:
	## World map tiles use res://assets/tiles/original_v1.{png,json} (Decision 53).
	return null

static func clear_memory_cache() -> void:
	_json_cache_by_dir.clear()
	_texture_lru_map.clear()
	_texture_lru_order.clear()

static func _norm_dir(cache_dir: String) -> String:
	var s := cache_dir.strip_edges().trim_suffix("/")
	return DEFAULT_CACHE_DIR if s == "" else s

static func _load_cached_json(cache_dir: String, rel_path: String) -> Dictionary:
	var cdir := _norm_dir(cache_dir)
	var key := cdir + "/" + rel_path
	if _json_cache_by_dir.has(key):
		return _json_cache_by_dir[key]
	var full_path := cdir.path_join(rel_path)
	if not FileAccess.file_exists(full_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full_path))
	if parsed is Dictionary:
		_json_cache_by_dir[key] = parsed
		return parsed
	return {}

static func _load_manifest(cache_dir: String) -> Dictionary:
	var cdir := _norm_dir(cache_dir)
	var mpath := cdir.path_join("manifest.json")
	if not FileAccess.file_exists(mpath):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	return parsed if parsed is Dictionary else {}

static func is_rom_ready(cache_dir: String = DEFAULT_CACHE_DIR) -> bool:
	var man := _load_manifest(cache_dir)
	var rom_block: Variant = man.get("rom", null)
	if not (rom_block is Dictionary):
		return false
	return int(rom_block.get("frontSpritesDecoded", 0)) == 649 and int(rom_block.get("backSpritesDecoded", 0)) == 649

static func is_data_ready(cache_dir: String = DEFAULT_CACHE_DIR) -> bool:
	var man := _load_manifest(cache_dir)
	var dp_block: Variant = man.get("dataPack", null)
	if not (dp_block is Dictionary):
		return false
	return int(dp_block.get("speciesCount", 0)) == 905 and int(dp_block.get("moveCount", 0)) == 778

static func rom_status(cache_dir: String = DEFAULT_CACHE_DIR) -> Dictionary:
	var man := _load_manifest(cache_dir)
	var rom_block: Variant = man.get("rom", null)
	if rom_block is Dictionary:
		var out: Dictionary = (rom_block as Dictionary).duplicate(true)
		out["ready"] = is_rom_ready(cache_dir)
		return out
	return {"ready": false, "status": "unimported", "notice": ""}

static func _ensure_credits_loaded() -> Dictionary:
	if not _credits_cache.is_empty():
		return _credits_cache
	if not FileAccess.file_exists(FAN_SPRITE_CREDITS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FAN_SPRITE_CREDITS_PATH))
	if parsed is Dictionary:
		_credits_cache = parsed
	return _credits_cache

static func _resolve_mega_pokemon_id(dex: int, form: String) -> int:
	if dex >= 10033 and dex <= 10090:
		return dex
	var norm_form := form.strip_edges().to_lower()
	if norm_form == "":
		return 0
	var cred := _ensure_credits_loaded()
	var mega_map: Dictionary = cred.get("mega_form_credits", {})
	for pid_str in mega_map.keys():
		var entry: Dictionary = mega_map[pid_str]
		if int(entry.get("species_dex", 0)) == dex:
			var slot := str(entry.get("mega_slot", "default")).to_lower()
			if norm_form in ["mega", "default"] and slot in ["mega", "default", "x", "mega-x"]:
				return int(pid_str)
			if norm_form in ["mega-x", "x"] and slot in ["mega-x", "x"]:
				return int(pid_str)
			if norm_form in ["mega-y", "y"] and slot in ["mega-y", "y"]:
				return int(pid_str)
	return 0

static func species(dex: int, form: String = "", cache_dir: String = DEFAULT_CACHE_DIR) -> Dictionary:
	var doc := _load_cached_json(cache_dir, "data/species.json")
	if doc.is_empty():
		return {}
	var species_map: Dictionary = doc.get("species", {})
	var mega_map: Dictionary = doc.get("mega_forms", {})
	if dex >= 10033 and mega_map.has(str(dex)):
		var m_entry: Dictionary = mega_map[str(dex)]
		var base_dex := int(m_entry.get("species_dex", 0))
		var base_sp: Dictionary = (species_map.get(str(base_dex), {}) as Dictionary).duplicate(true)
		if base_sp.is_empty():
			return m_entry.duplicate(true)
		base_sp["pokemon_id"] = dex
		base_sp["form"] = str(m_entry.get("form", "mega"))
		base_sp["base_stats"] = (m_entry.get("base_stats", {}) as Dictionary).duplicate(true)
		base_sp["types"] = (m_entry.get("types", []) as Array).duplicate(true)
		base_sp["ability_id"] = int(m_entry.get("ability_id", 0))
		return base_sp

	if not species_map.has(str(dex)):
		return {}
	var out: Dictionary = (species_map[str(dex)] as Dictionary).duplicate(true)
	var norm_form := form.strip_edges().to_lower()
	if norm_form != "":
		var m_list: Array = out.get("mega_forms", [])
		for m_var in m_list:
			if m_var is Dictionary:
				var mf: Dictionary = m_var
				if str(mf.get("form", "")).to_lower() == norm_form:
					out["pokemon_id"] = int(mf.get("pokemon_id", dex))
					out["form"] = norm_form
					out["base_stats"] = (mf.get("base_stats", {}) as Dictionary).duplicate(true)
					out["types"] = (mf.get("types", []) as Array).duplicate(true)
					out["ability_id"] = int(mf.get("ability_id", 0))
					break
	return out

static func learnset(dex: int, cache_dir: String = DEFAULT_CACHE_DIR) -> Array:
	var doc := _load_cached_json(cache_dir, "data/learnsets.json")
	var arr: Variant = doc.get(str(dex), [])
	return (arr as Array).duplicate(true) if arr is Array else []

static func evolutions(dex: int, cache_dir: String = DEFAULT_CACHE_DIR) -> Array:
	var doc := _load_cached_json(cache_dir, "data/evolutions.json")
	var arr: Variant = doc.get(str(dex), [])
	return (arr as Array).duplicate(true) if arr is Array else []

static func move(id: int, cache_dir: String = DEFAULT_CACHE_DIR) -> Dictionary:
	var doc := _load_cached_json(cache_dir, "data/moves.json")
	var entry: Variant = doc.get(str(id), {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

static func item(id: int, cache_dir: String = DEFAULT_CACHE_DIR) -> Dictionary:
	var doc := _load_cached_json(cache_dir, "data/items.json")
	var entry: Variant = doc.get(str(id), {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

static func _load_or_cache_texture(png_path: String) -> Texture2D:
	if _texture_lru_map.has(png_path):
		_texture_lru_order.erase(png_path)
		_texture_lru_order.append(png_path)
		return _texture_lru_map[png_path]
	if not FileAccess.file_exists(png_path):
		return null
	var bytes := FileAccess.get_file_as_bytes(png_path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("is_placeholder", false)
	tex.set_meta("sprite_pending", false)
	_texture_lru_map[png_path] = tex
	_texture_lru_order.append(png_path)
	while _texture_lru_order.size() > TEXTURE_LRU_CAPACITY:
		var evict_key: String = _texture_lru_order.pop_front()
		_texture_lru_map.erase(evict_key)
	return tex

static func _get_silhouette_texture(target_id: int) -> Texture2D:
	var bucket := posmod(target_id, 8)
	if _silhouette_cache.has(bucket):
		return _silhouette_cache[bucket]
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill_col := Color8(38 + bucket * 2, 44 + bucket * 2, 58 + bucket * 2, 235)
	var rim_col := Color8(84, 96, 122, 255)
	for y in range(18, 82):
		var dy := float(y - 50) / 30.0
		var half_w := int(sqrt(maxf(0.0, 1.0 - dy * dy)) * 24.0)
		for x in range(48 - half_w, 48 + half_w + 1):
			if x == 48 - half_w or x == 48 + half_w:
				img.set_pixel(x, y, rim_col)
			else:
				img.set_pixel(x, y, fill_col)
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("is_placeholder", true)
	tex.set_meta("sprite_pending", true)
	_silhouette_cache[bucket] = tex
	return tex

static func _resolve_sprite_target_id(dex: int, form: String) -> int:
	var mega_pid := _resolve_mega_pokemon_id(dex, form)
	if mega_pid > 0:
		return mega_pid
	return dex

static func sprite_front(
	dex: int,
	shiny: bool = false,
	form: String = "",
	cache_dir: String = DEFAULT_CACHE_DIR
) -> Texture2D:
	var target_id := _resolve_sprite_target_id(dex, form)
	var sub := "front_shiny" if shiny else "front"
	var cdir := _norm_dir(cache_dir)
	var p := cdir.path_join("sprites/%s/%d.png" % [sub, target_id])
	var tex := _load_or_cache_texture(p)
	if tex != null:
		return tex
	return _get_silhouette_texture(target_id)

static func sprite_back(
	dex: int,
	shiny: bool = false,
	form: String = "",
	cache_dir: String = DEFAULT_CACHE_DIR
) -> Texture2D:
	var target_id := _resolve_sprite_target_id(dex, form)
	var sub := "back_shiny" if shiny else "back"
	var cdir := _norm_dir(cache_dir)
	var p := cdir.path_join("sprites/%s/%d.png" % [sub, target_id])
	var tex := _load_or_cache_texture(p)
	if tex != null:
		return tex
	return _get_silhouette_texture(target_id)

static func item_icon(id: int, cache_dir: String = DEFAULT_CACHE_DIR) -> Texture2D:
	var cdir := _norm_dir(cache_dir)
	var p := cdir.path_join("icons/items/%d.png" % id)
	var tex := _load_or_cache_texture(p)
	if tex != null:
		return tex
	if _item_placeholder_tex == null:
		var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in range(4, 20):
			for x in range(4, 20):
				var border := (x == 4 or x == 19 or y == 4 or y == 19)
				img.set_pixel(x, y, Color8(48, 56, 72, 255) if border else Color8(186, 152, 98, 255))
		_item_placeholder_tex = ImageTexture.create_from_image(img)
		_item_placeholder_tex.set_meta("is_placeholder", true)
	return _item_placeholder_tex

static func name(kind: String, id: int, cache_dir: String = DEFAULT_CACHE_DIR) -> String:
	return display_name(kind, id, cache_dir)

static func display_name(kind: String, id: int, cache_dir: String = DEFAULT_CACHE_DIR) -> String:
	var k := kind.strip_edges().to_lower()
	var fname: String = str(KIND_TO_FILE.get(k, ""))
	if fname != "":
		var doc := _load_cached_json(cache_dir, "text/en/" + fname)
		var val := str(doc.get(str(id), ""))
		if val != "":
			return val
	if k == "species":
		return "#%03d" % id
	return "%s #%d" % [k.capitalize(), id]

static func credits(dex: int, form: String = "") -> Array[String]:
	var cred := _ensure_credits_loaded()
	var out: Array[String] = []
	var mega_pid := _resolve_mega_pokemon_id(dex, form)
	if mega_pid > 0:
		var mega_map: Dictionary = cred.get("mega_form_credits", {})
		var m_entry: Dictionary = mega_map.get(str(mega_pid), {})
		var artists: Array = m_entry.get("artists", [])
		for a in artists:
			out.append(str(a))
		return out
	if dex >= 650 and dex <= 905:
		var sp_map: Dictionary = cred.get("species_credits", {})
		var artists: Array = sp_map.get(str(dex), [])
		for a in artists:
			out.append(str(a))
	return out

static func type_chart() -> Dictionary:
	if not _type_chart_cache.is_empty():
		return _type_chart_cache
	if not FileAccess.file_exists(TYPE_CHART_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TYPE_CHART_PATH))
	if parsed is Dictionary:
		_type_chart_cache = parsed
	return _type_chart_cache

static func type_effectiveness(attack_type: String, defend_types: Array) -> float:
	var chart_doc := type_chart()
	var matrix: Dictionary = chart_doc.get("effectiveness", chart_doc.get("chart", {}))
	var atk_row: Dictionary = matrix.get(attack_type.strip_edges().to_lower(), {})
	var mult := 1.0
	for dt in defend_types:
		var def_key := str(dt).strip_edges().to_lower()
		if atk_row.has(def_key):
			mult *= float(atk_row[def_key])
	return mult
