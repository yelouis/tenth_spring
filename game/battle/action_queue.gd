# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Action queue mirroring pokemon-showdown@0.11.11 sim/battle-queue.ts:143-370,
# with Tenth Spring's non-Showdown actions (run, bag, ball) placed at fixed
# orders before switch (103) per Plan §3.4.

const EventCoreRef := preload("res://battle/event_core.gd")

const ORDERS: Dictionary = {
	"team": 1,
	"start": 2,
	"instaswitch": 3,
	"beforeTurn": 4,
	"beforeTurnMove": 5,
	# Tenth Spring in-game-only actions (fixed orders before switch)
	"run": 10,
	"bag": 20,
	"ball": 20,
	# Showdown standard battle orders (sim/battle-queue.ts:174-195)
	"runSwitch": 101,
	"switch": 103,
	"megaEvo": 104,
	"priorityChargeMove": 107,
	"shift": 200,
	"move": 200,
	"residual": 300,
}

var list: Array[Dictionary] = []


func clear() -> void:
	list.clear()


func size() -> int:
	return list.size()


func is_empty() -> bool:
	return list.is_empty()


func shift() -> Dictionary:
	if list.is_empty():
		return {}
	return list.pop_front()


func resolve_action(battle: Object, action: Dictionary) -> Dictionary:
	var out: Dictionary = action.duplicate(true)
	var choice: String = str(out.get("choice", "move"))
	out["choice"] = choice
	if not out.has("order"):
		out["order"] = int(ORDERS.get(choice, 200))
	if not out.has("priority"):
		if choice == "move" and out.has("move") and out["move"] is Dictionary:
			out["priority"] = int((out["move"] as Dictionary).get("priority", 0))
		else:
			out["priority"] = 0
	if not out.has("fractional_priority"):
		out["fractional_priority"] = 0.0
	if not out.has("sub_order"):
		out["sub_order"] = 0
	if not out.has("effect_order"):
		# Queued move/switch actions do not carry distinct effectOrder (sim/battle-queue.ts);
		# exact speed ties must fall through to speedSort's tie shuffle.
		out["effect_order"] = 0
	var pkmn: Variant = out.get("pokemon", null)
	if not out.has("speed"):
		if pkmn is Object and pkmn.has_method("get_action_speed"):
			out["speed"] = int(pkmn.call("get_action_speed"))
		else:
			out["speed"] = 0
	if pkmn is Object and not out.has("side_idx"):
		var s_obj: Variant = pkmn.get("side")
		if s_obj is Object:
			out["side_idx"] = int(s_obj.get("id"))
	return out


func add_choice(battle: Object, event_core: Object, action: Dictionary) -> void:
	var resolved := resolve_action(battle, action)
	list.append(resolved)
	event_core.speed_sort(battle, list)


func add_choices(battle: Object, event_core: Object, actions: Array) -> void:
	for a in actions:
		if a is Dictionary:
			list.append(resolve_action(battle, a))
	event_core.speed_sort(battle, list)


func prioritize_action(battle: Object, event_core: Object, target_action: Dictionary) -> void:
	for a in list:
		if a == target_action:
			a["order"] = 3
			break
	event_core.speed_sort(battle, list)
