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

var weather_id: int = WEATHER_NONE
var weather_state: Dictionary = {}
var terrain_id: int = TERRAIN_NONE
var terrain_state: Dictionary = {}
# Map of numeric/generic pseudo-weather condition id -> EffectState Dictionary
var pseudo_weather: Dictionary = {}


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
