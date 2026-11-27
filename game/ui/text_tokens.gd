class_name TextTokens
extends RefCounted

## game/ui/text_tokens.gd — Runtime Text Token Resolver (Item 89 / F113)
## Contract: docs/agent_execution_guide.md §4 (Item 89), §13 (no Nintendo names in repo)
##
## Replaces numeric tokens in player-facing text at runtime using AssetDB:
##   {species:<dex>} -> AssetDB.display_name("species", dex), or "Pokémon" when cache absent
##   {item:<id>}     -> AssetDB.display_name("item", id)
##   {move:<id>}     -> AssetDB.display_name("move", id)
##   {ability:<id>}  -> AssetDB.display_name("ability", id)

const AssetDB := preload("res://rom/asset_db.gd")

static var _token_regex: RegEx = null

static func _get_regex() -> RegEx:
	if _token_regex == null:
		_token_regex = RegEx.new()
		_token_regex.compile("\\{(species|item|move|ability):(\\d+)\\}")
	return _token_regex

static func resolve(text: String, cache_dir: String = AssetDB.DEFAULT_CACHE_DIR) -> String:
	if text.is_empty() or not text.contains("{"):
		return text
	var rx := _get_regex()
	var matches := rx.search_all(text)
	if matches.is_empty():
		return text
	var out := ""
	var cursor := 0
	for m in matches:
		var start_idx := m.get_start()
		var end_idx := m.get_end()
		out += text.substr(cursor, start_idx - cursor)
		var kind := m.get_string(1)
		var obj_id := m.get_string(2).to_int()
		var resolved := AssetDB.display_name(kind, obj_id, cache_dir)
		if kind == "species" and resolved.begins_with("#"):
			resolved = "Pokémon"
		out += resolved
		cursor = end_idx
	out += text.substr(cursor)
	return out

static func resolve_lines(lines: Array, cache_dir: String = AssetDB.DEFAULT_CACHE_DIR) -> Array[String]:
	var out: Array[String] = []
	for lv in lines:
		out.append(resolve(str(lv), cache_dir))
	return out
