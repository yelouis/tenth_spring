# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Battle field state mirroring pokemon-showdown@0.11.11 sim/field.ts.

const WEATHER_NONE: int = 0
const WEATHER_RAIN: int = 1
const WEATHER_SUN: int = 2
const WEATHER_SAND: int = 3
const WEATHER_HAIL: int = 4
const WEATHER_DELTA_STREAM: int = 5

const TERRAIN_NONE: int = 0
const TERRAIN_ELECTRIC: int = 1
const TERRAIN_GRASSY: int = 2
const TERRAIN_MISTY: int = 3
const TERRAIN_PSYCHIC: int = 4

var _battle_ref: WeakRef = null
var battle: Object:
	get:
		return _battle_ref.get_ref() if _battle_ref != null else null
	set(v):
		_battle_ref = weakref(v) if v != null else null
var weather_id: int = WEATHER_NONE
var weather_state: Dictionary = {}
var terrain_id: int = TERRAIN_NONE
var terrain_state: Dictionary = {}
# Map of numeric/generic pseudo-weather condition id -> EffectState Dictionary
var pseudo_weather: Dictionary = {}


func suppressing_weather() -> bool:
	# sim/field.ts:106-116: active non-fainted battler with ability #13 or #76
	if battle == null:
		return false
	for s in battle.get("sides"):
		for p in s.get("active"):
			if p != null and not bool(p.get("fainted")) and (bool(p.call("has_ability", 13)) or bool(p.call("has_ability", 76))) and not bool((p.get("ability_state") as Dictionary).get("ending", false)):
				return true
	return false


func clear_weather() -> bool:
	if weather_id == WEATHER_NONE:
		return false
	if battle != null:
		battle.get("event_core").single_event(battle, "FieldEnd", battle.get("event_core").get_effect("weather:%d" % weather_id), weather_state, self)
	weather_id = WEATHER_NONE
	weather_state = {}
	return true


func clear_terrain() -> bool:
	if terrain_id == TERRAIN_NONE:
		return false
	if battle != null:
		battle.get("event_core").single_event(battle, "FieldEnd", battle.get("event_core").get_effect("terrain:%d" % terrain_id), terrain_state, self)
	terrain_id = TERRAIN_NONE
	terrain_state = {}
	return true


func remove_pseudo_weather(cond_id: String) -> bool:
	if not pseudo_weather.has(cond_id):
		return false
	if battle != null:
		battle.get("event_core").single_event(battle, "FieldEnd", battle.get("event_core").get_effect(cond_id), pseudo_weather[cond_id], self)
	pseudo_weather.erase(cond_id)
	return true


func has_pseudo_weather(cond_id: String) -> bool:
	return pseudo_weather.has(cond_id)


func is_trick_room_active() -> bool:
	return pseudo_weather.has("cond_433")


func is_wonder_room_active() -> bool:
	return pseudo_weather.has("cond_472")


func is_magic_room_active() -> bool:
	return pseudo_weather.has("cond_478")


func snapshot() -> Dictionary:
	return {
		"weather_id": weather_id,
		"weather_turns": int(weather_state.get("duration", 0)),
		"terrain_id": terrain_id,
		"terrain_turns": int(terrain_state.get("duration", 0)),
		"pseudo_weather_count": pseudo_weather.size(),
	}
