# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Active/party battler state mirroring pokemon-showdown@0.11.11 sim/pokemon.ts.

const StatsRef := preload("res://creatures/stats.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")

var _side_ref: WeakRef = null
var side: Object:
	get:
		return _side_ref.get_ref() if _side_ref != null else null
	set(v):
		_side_ref = weakref(v) if v != null else null
var slot: int = 0
var species_dex: int = 0
var effective_form: String = ""
var pokemon_id: int = 0
var level: int = 50
var max_hp: int = 1
var hp: int = 1
var base_stats: Dictionary = {"hp": 1, "atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}
var ivs: Array[int] = [31, 31, 31, 31, 31, 31]
var evs: Array[int] = [0, 0, 0, 0, 0, 0]
var nature: int = 0
var stored_stats: Dictionary = {"atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}
var speed: int = 0
var boosts: Dictionary = {
	"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "accuracy": 0, "evasion": 0,
}
var types: Array[String] = []
var added_type: String = ""
var status: int = StatsRef.STATUS_NONE
var status_state: Dictionary = {}
var volatiles: Dictionary = {}
var ability_id: int = 0
var base_ability_id: int = 0
var ability_state: Dictionary = {}
var item_id: int = 0
var last_item_id: int = 0
var used_item_this_turn: bool = false
var item_state: Dictionary = {}
var moves: Array[Dictionary] = []
var weight_hg: int = 100
var gender: int = 1
var is_active: bool = false
var fainted: bool = false
var switch_flag: bool = false
var active_turns: int = 0
var move_this_turn: int = 0
var last_move_used: int = 0
var hurt_this_turn: int = 0
var being_called_back: bool = false
var trapped: bool = false
var maybe_trapped: bool = false
var transformed: bool = false
var move_hit_data: Dictionary = {}
var crits_landed_this_battle: int = 0
var damage_taken_without_fainting: int = 0


static func from_spec(
	spec: Dictionary,
	species_data: Dictionary,
	move_lookup: Callable,
	side_ref: Object = null,
	slot_idx: int = 0
) -> RefCounted:
	var scr: GDScript = load("res://battle/state/battler_state.gd") as GDScript
	var b: RefCounted = scr.new()
	b.side = side_ref
	b.slot = slot_idx
	b.species_dex = int(spec.get("dex", species_data.get("dex", 0)))
	b.effective_form = str(spec.get("form", ""))
	b.pokemon_id = int(spec.get("pokemon_id", b.species_dex))
	b.level = int(spec.get("level", 50))
	b.nature = int(spec.get("nature", 0))

	var raw_bs: Dictionary = species_data.get("base_stats", {})
	b.base_stats = {
		"hp": int(raw_bs.get("hp", 50)),
		"atk": int(raw_bs.get("atk", 50)),
		"def": int(raw_bs.get("def", 50)),
		"spa": int(raw_bs.get("spa", 50)),
		"spd": int(raw_bs.get("spd", 50)),
		"spe": int(raw_bs.get("spe", 50)),
	}
	var raw_ivs: Array = spec.get("ivs", [31, 31, 31, 31, 31, 31])
	var raw_evs: Array = spec.get("evs", [0, 0, 0, 0, 0, 0])
	var iv_typed: Array[int] = [int(raw_ivs[0]), int(raw_ivs[1]), int(raw_ivs[2]), int(raw_ivs[3]), int(raw_ivs[4]), int(raw_ivs[5])]
	var ev_typed: Array[int] = [int(raw_evs[0]), int(raw_evs[1]), int(raw_evs[2]), int(raw_evs[3]), int(raw_evs[4]), int(raw_evs[5])]
	b.ivs = iv_typed
	b.evs = ev_typed

	var calc := StatsRef.calc_all_stats(b.base_stats, b.ivs, b.evs, b.level, b.nature, b.species_dex)
	b.max_hp = int(calc["hp"])
	var start_hp: int = int(spec.get("start_hp", 0))
	b.hp = start_hp if (start_hp > 0 and start_hp < b.max_hp) else b.max_hp
	b.stored_stats = {
		"atk": int(calc["atk"]),
		"def": int(calc["def"]),
		"spa": int(calc["spa"]),
		"spd": int(calc["spd"]),
		"spe": int(calc["spe"]),
	}

	b.types.clear()
	for t in species_data.get("types", []):
		b.types.append(str(t).to_lower())
	b.weight_hg = int(species_data.get("weight_hg", 100))
	b.status = int(spec.get("status", StatsRef.STATUS_NONE))
	b.ability_id = int(spec.get("ability_id", 0))
	b.base_ability_id = b.ability_id
	b.item_id = int(spec.get("item_id", 0))
	b.gender = int(spec.get("gender", 1))

	if spec.has("stages") and spec["stages"] is Array:
		var st_arr: Array = spec["stages"]
		var st_keys: Array[String] = ["atk", "def", "spa", "spd", "spe", "accuracy", "evasion"]
		for i in range(mini(st_arr.size(), st_keys.size())):
			b.boosts[st_keys[i]] = StatsRef.clamp_int(int(st_arr[i]), -6, 6)

	b.moves.clear()
	for m_entry in spec.get("moves", []):
		var mid: int = int(m_entry) if (m_entry is int or m_entry is float) else int((m_entry as Dictionary).get("move_id", 0))
		var mdata: Dictionary = move_lookup.call(mid) if move_lookup.is_valid() else {}
		var pp: int = int(mdata.get("pp", 10))
		b.moves.append({
			"move_id": mid,
			"pp": pp,
			"max_pp": pp,
			"disabled": false,
		})
	b.speed = StatsRef.apply_stage(int(b.stored_stats["spe"]), int(b.boosts["spe"]))
	return b


func has_type(type_name: String) -> bool:
	var low := type_name.to_lower()
	if added_type != "" and added_type.to_lower() == low:
		return true
	for t in types:
		if t.to_lower() == low:
			return true
	return false


func get_all_types() -> Array[String]:
	var out: Array[String] = types.duplicate()
	if added_type != "" and not out.has(added_type):
		out.append(added_type)
	return out


func ignoring_ability() -> bool:
	if volatiles.has("cond_380"):
		return true
	if side != null and side.get("battle") != null:
		var battle: Object = side.get("battle")
		if bool(battle.call("is_ability_active_on_field", 256)) and ability_id != 256:
			return true
	return false


func ignoring_item() -> bool:
	if ability_id == 103 and not ignoring_ability():
		return true
	if volatiles.has("cond_373"):
		return true
	if side != null and side.get("battle") != null:
		var battle: Object = side.get("battle")
		var fld: Object = battle.get("field")
		if fld != null and bool(fld.call("is_magic_room_active")):
			return true
	return false


func calculate_stat(stat_name: String, boost: int) -> int:
	var actual_stat: String = stat_name
	if side != null and side.get("battle") != null:
		var fld: Object = (side.get("battle") as Object).get("field")
		if fld != null and bool(fld.call("is_wonder_room_active")):
			if actual_stat == "def":
				actual_stat = "spd"
			elif actual_stat == "spd":
				actual_stat = "def"
	var base_val: int = int(stored_stats.get(actual_stat, 1))
	return StatsRef.apply_stage(base_val, boost)


func get_stat(stat_name: String, unboosted: bool = false, unmodified: bool = false) -> int:
	var boost: int = 0 if unboosted else int(boosts.get(stat_name, 0))
	var val: int = calculate_stat(stat_name, boost)
	if not unmodified and side != null and side.get("battle") != null:
		var battle: Object = side.get("battle")
		var ev_core: Object = battle.get("event_core")
		var ev_map := {"atk": "ModifyAtk", "def": "ModifyDef", "spa": "ModifySpA", "spd": "ModifySpD", "spe": "ModifySpe"}
		if ev_map.has(stat_name):
			val = int(ev_core.run_event(battle, ev_map[stat_name], self, null, null, val))
	return maxi(1, val)


func get_action_speed() -> int:
	var spe: int = get_stat("spe", false, false)
	var tr_active: bool = false
	if side != null and side.get("battle") != null:
		var fld: Object = (side.get("battle") as Object).get("field")
		if fld != null:
			tr_active = bool(fld.call("is_trick_room_active"))
	return StatsRef.calc_action_speed(spe, tr_active)


func update_speed() -> int:
	speed = get_action_speed()
	return speed


func run_immunity(move: Dictionary) -> bool:
	var mtype: String = str(move.get("type", "???")).to_lower()
	if mtype == "???":
		return true
	var eff: float = AssetDBRef.type_effectiveness(mtype, get_all_types())
	return eff > 0.0


func run_effectiveness(move: Dictionary) -> int:
	# Returns integer step sum in [-6..+6]: +1 per 2x type, -1 per 0.5x type (sim/pokemon.ts)
	var mtype: String = str(move.get("type", "???")).to_lower()
	if mtype == "???":
		return 0
	var total_mod: int = 0
	for dt in get_all_types():
		var single: float = AssetDBRef.type_effectiveness(mtype, [dt])
		if single > 1.5:
			total_mod += 1
		elif single > 0.0 and single < 0.75:
			total_mod -= 1
	return total_mod


func clear_boosts() -> void:
	for k in boosts.keys():
		boosts[k] = 0


func apply_damage(amount: int) -> int:
	if fainted or amount <= 0:
		return 0
	var dealt: int = mini(hp, amount)
	hp -= dealt
	hurt_this_turn += dealt
	if hp <= 0:
		hp = 0
		fainted = true
		status = StatsRef.STATUS_NONE
		clear_boosts()
		volatiles.clear()
		if side != null:
			side.set("fainted_this_turn", true)
			side.set("total_fainted", int(side.get("total_fainted")) + 1)
	else:
		damage_taken_without_fainting += dealt
	return dealt


func snapshot() -> Dictionary:
	return {
		"dex": species_dex,
		"hp": hp,
		"max_hp": max_hp,
		"status": status,
		"boosts": boosts.duplicate(),
		"volatiles": volatiles.size(),
		"item_id": item_id,
		"ability_id": ability_id,
		"types": get_all_types(),
		"fainted": fainted,
	}
