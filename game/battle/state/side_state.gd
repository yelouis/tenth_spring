# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Battle side state mirroring pokemon-showdown@0.11.11 sim/side.ts.

const BattlerStateRef := preload("res://battle/state/battler_state.gd")

var id: int = 0
var _battle_ref: WeakRef = null
var battle: Object:
	get:
		return _battle_ref.get_ref() if _battle_ref != null else null
	set(v):
		_battle_ref = weakref(v) if v != null else null
var pokemon: Array = []
var active: Array = []
var side_conditions: Dictionary = {}
var slot_conditions: Array[Dictionary] = [{}]
var fainted_last_turn: bool = false
var fainted_this_turn: bool = false
var total_fainted: int = 0
var mega_used: bool = false


func setup(side_id: int, battle_ref: Object, team_specs: Array, species_lookup: Callable, move_lookup: Callable) -> void:
	id = side_id
	battle = battle_ref
	pokemon.clear()
	active.clear()
	side_conditions.clear()
	slot_conditions = [{}]
	fainted_last_turn = false
	fainted_this_turn = false
	total_fainted = 0
	mega_used = false
	for i in range(team_specs.size()):
		var spec: Dictionary = team_specs[i]
		var dex: int = int(spec.get("dex", 0))
		var sp_data: Dictionary = species_lookup.call(dex)
		var b := BattlerStateRef.from_spec(spec, sp_data, move_lookup, self, i)
		pokemon.append(b)
	if not pokemon.is_empty():
		var lead: Object = pokemon[0]
		lead.set("is_active", true)
		active.append(lead)


func foe_side() -> Object:
	if battle == null:
		return null
	var sides: Array = battle.get("sides")
	if sides.size() < 2:
		return null
	return sides[1 - id]


func active_battler() -> Object:
	if active.is_empty():
		return null
	return active[0]


func has_living_pokemon() -> bool:
	for p in pokemon:
		if not bool(p.get("fainted")):
			return true
	return false


func snapshot() -> Dictionary:
	var act: Object = active_battler()
	return {
		"active": act.call("snapshot") if act != null else {},
		"fainted_count": total_fainted,
		"side_conditions": side_conditions.size(),
	}
