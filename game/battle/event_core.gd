# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Event core mirroring pokemon-showdown@0.11.11 sim/battle.ts:
#   runEvent (:758), singleEvent (:571), eachEvent (:465), priorityEvent (:943),
#   findEventHandlers (:1035), speedSort (:429), comparePriority (:404),
#   chainModify (:2318), modify (:2329), suppressingAbility (:365).

const StatsRef := preload("res://creatures/stats.gd")
const BattleRandomRef := preload("res://battle/battle_random.gd")

# Sentinel meaning "handler did not return a replacement value" (JS undefined).
const NO_CHANGE: String = "__TS_EVENT_NO_CHANGE__"

# Registered effect handler tables keyed by effect_key (e.g., "ability:37", "item:247",
# "move:33", "status:4", "cond_73", "weather:1", "terrain:2").
# Each entry is a Dictionary of callbacks + metadata:
#   {"id": String, "effect_type": String, "breakable": bool,
#    "callbacks": {"onBasePower": Callable, ...},
#    "priorities": {"onBasePower": int, ...},
#    "orders": {"onResidual": int, ...},
#    "sub_orders": {"onResidual": int, ...}}
var _effects: Dictionary = {}


static func chain_mod(prev_mod4096: int, next_mod4096: int) -> int:
	return (prev_mod4096 * next_mod4096 + 2048) >> 12


static func poke_round(value: int, mod4096: int) -> int:
	# Exact Gen 5-8 round half down: sim/battle.ts:2329-2340
	var prod: int = value * mod4096
	return (prod + 2047) / 4096


static func mod_from_fraction(numerator: int, denominator: int = 1) -> int:
	if denominator == 1:
		return numerator
	return (numerator * 4096) / denominator


func register_effect(effect_key: String, effect_def: Dictionary) -> void:
	_effects[effect_key] = effect_def


func get_effect(effect_key: String) -> Dictionary:
	var eff: Variant = _effects.get(effect_key, {})
	return eff if eff is Dictionary else {}


func chain_modify(battle: Object, numerator: int, denominator: int = 1) -> void:
	var ev: Dictionary = battle.get("event")
	var prev_mod: int = int(ev.get("modifier", 4096))
	var next_mod: int = numerator if denominator == 4096 else mod_from_fraction(numerator, denominator)
	ev["modifier"] = chain_mod(prev_mod, next_mod)


func modify_value(value: int, mod4096: int) -> int:
	return poke_round(value, mod4096)


static func compare_priority(a: Dictionary, b: Dictionary) -> int:
	# sim/battle.ts:404-420: order asc, priority desc, fractionalPriority desc,
	# speed desc, subOrder asc, effectOrder asc.
	var a_ord: int = int(a.get("order", 4294967295))
	var b_ord: int = int(b.get("order", 4294967295))
	if a_ord != b_ord:
		return -1 if a_ord < b_ord else 1
	var a_pri: int = int(a.get("priority", 0))
	var b_pri: int = int(b.get("priority", 0))
	if a_pri != b_pri:
		return -1 if a_pri > b_pri else 1
	var a_fpri: float = float(a.get("fractional_priority", 0.0))
	var b_fpri: float = float(b.get("fractional_priority", 0.0))
	if a_fpri != b_fpri:
		return -1 if a_fpri > b_fpri else 1
	var a_spe: int = int(a.get("speed", 0))
	var b_spe: int = int(b.get("speed", 0))
	if a_spe != b_spe:
		return -1 if a_spe > b_spe else 1
	var a_sub: int = int(a.get("sub_order", 0))
	var b_sub: int = int(b.get("sub_order", 0))
	if a_sub != b_sub:
		return -1 if a_sub < b_sub else 1
	var a_eo: int = int(a.get("effect_order", 0))
	var b_eo: int = int(b.get("effect_order", 0))
	if a_eo != b_eo:
		return -1 if a_eo < b_eo else 1
	return 0


func speed_sort(battle: Object, list: Array, draw_name: String = BattleRandomRef.DRAW_SPEED_TIE) -> void:
	var n: int = list.size()
	if n <= 1:
		return
	# Insertion sort by compare_priority (deterministic, preserves ties cleanly before shuffling)
	for i in range(1, n):
		var cur: Variant = list[i]
		var j: int = i - 1
		while j >= 0 and compare_priority(list[j], cur) > 0:
			list[j + 1] = list[j]
			j -= 1
		list[j + 1] = cur

	# Break exact ties via BattleRandom.shuffle_slice (sim/battle.ts:429-460)
	var rng_obj: Variant = battle.get("rng") if battle != null else null
	if rng_obj == null:
		return
	var start: int = 0
	while start < n:
		var end_idx: int = start + 1
		while end_idx < n and compare_priority(list[start], list[end_idx]) == 0:
			end_idx += 1
		if end_idx - start > 1:
			rng_obj.shuffle_slice(draw_name, list, start, end_idx)
		start = end_idx


func single_event(battle: Object, event_id: String, effect: Dictionary, state: Dictionary, target: Variant, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE) -> Variant:
	if effect.is_empty():
		return relay_var
	var callbacks: Dictionary = effect.get("callbacks", {})
	var cb_name: String = "on" + event_id
	if not callbacks.has(cb_name):
		return relay_var
	var cb: Variant = callbacks[cb_name]
	if not (cb is Callable):
		return relay_var

	var parent_event: Dictionary = battle.get("event")
	battle.set("event", {
		"id": event_id,
		"target": target,
		"source": source,
		"effect": source_effect,
		"modifier": 4096,
	})
	battle.set("event_depth", int(battle.get("event_depth")) + 1)

	var ctx := {
		"battle": battle,
		"target": target,
		"source": source,
		"effect": source_effect,
		"state": state,
		"relay_var": relay_var,
		"event_core": self,
	}
	var ret: Variant = (cb as Callable).call(ctx)
	var active_ev: Dictionary = battle.get("event")
	var final_mod: int = int(active_ev.get("modifier", 4096))

	battle.set("event_depth", int(battle.get("event_depth")) - 1)
	battle.set("event", parent_event)

	var out: Variant = relay_var
	if not _is_no_change(ret):
		out = ret
	if final_mod != 4096 and (out is int or out is float):
		out = poke_round(int(out), final_mod)
	return out


func find_event_handlers(battle: Object, target: Variant, event_name: String, source: Variant = null, source_effect: Variant = null) -> Array[Dictionary]:
	var handlers: Array[Dictionary] = []
	var suppress_ability: bool = bool(battle.call("suppressing_ability", target))

	# 1. Target battler's own effects: on<Event>
	if target is Object and target.has_method("get_action_speed"):
		_collect_battler_handlers(battle, handlers, target, "on" + event_name, suppress_ability, false)

		# Side & slot conditions on target's side: on<Event>
		var t_side: Variant = target.get("side")
		if t_side is Object:
			_collect_side_handlers(battle, handlers, t_side, target, "on" + event_name)
			# Ally prefix (in singles, side's active battler itself if onAlly is registered on side/ally)
			_collect_battler_handlers(battle, handlers, target, "onAlly" + event_name, suppress_ability, false)

			# Foe side & foe active battlers: onFoe<Event>
			var foe_side: Variant = t_side.call("foe_side")
			if foe_side is Object:
				_collect_side_handlers(battle, handlers, foe_side, target, "onFoe" + event_name)
				for foe_b in foe_side.get("active"):
					if foe_b != null and not bool(foe_b.get("fainted")):
						_collect_battler_handlers(battle, handlers, foe_b, "onFoe" + event_name, false, false)

		# Source battler: onSource<Event>
		if source is Object and source.has_method("get_action_speed"):
			_collect_battler_handlers(battle, handlers, source, "onSource" + event_name, false, false)

	# 2. Active battlers on both sides: onAny<Event>
	for b_side in battle.get("sides"):
		if b_side is Object:
			for act_b in b_side.get("active"):
				if act_b != null and not bool(act_b.get("fainted")):
					var sup_any: bool = (act_b == target) and suppress_ability
					_collect_battler_handlers(battle, handlers, act_b, "onAny" + event_name, sup_any, false)

	# 3. Field effects (weather, terrain, pseudo-weather): on<Event> and onAny<Event>
	var field_obj: Variant = battle.get("field")
	if field_obj is Object:
		_collect_field_handlers(battle, handlers, field_obj, "on" + event_name)
		_collect_field_handlers(battle, handlers, field_obj, "onAny" + event_name)

	# 4. Source move/effect itself if passed as Dictionary with callbacks (on<Event> on move)
	if source_effect is Dictionary and source_effect.has("callbacks"):
		var cb_name: String = "on" + event_name
		var cbs: Dictionary = source_effect["callbacks"]
		if cbs.has(cb_name) and cbs[cb_name] is Callable:
			handlers.append(_make_handler(
				source_effect,
				cbs[cb_name],
				cb_name,
				target,
				{},
				0,
				0
			))

	speed_sort(battle, handlers)
	return handlers


func run_event(battle: Object, event_id: String, target: Variant = null, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE, on_effect: bool = false, fast_exit: bool = false) -> Variant:
	if int(battle.get("event_depth")) >= 8:
		return false

	var eff_for_find: Variant = source_effect if on_effect else null
	var handlers: Array[Dictionary] = find_event_handlers(battle, target, event_id, source, eff_for_find)

	var parent_event: Dictionary = battle.get("event")
	var cur_event := {
		"id": event_id,
		"target": target,
		"source": source,
		"effect": source_effect,
		"modifier": 4096,
	}
	battle.set("event", cur_event)
	battle.set("event_depth", int(battle.get("event_depth")) + 1)

	var current_relay: Variant = relay_var
	for h in handlers:
		var cb: Callable = h["callback"]
		cur_event["modifier"] = 4096
		var ctx := {
			"battle": battle,
			"target": target,
			"source": source,
			"effect": source_effect,
			"effect_holder": h["effect_holder"],
			"state": h["state"],
			"relay_var": current_relay,
			"event_core": self,
		}
		var ret: Variant = cb.call(ctx)
		if not _is_no_change(ret):
			current_relay = ret
			if (current_relay is bool and current_relay == false) or fast_exit:
				break
		var mod4096: int = int(cur_event.get("modifier", 4096))
		if mod4096 != 4096 and (current_relay is int or current_relay is float):
			current_relay = poke_round(int(current_relay), mod4096)

	battle.set("event_depth", int(battle.get("event_depth")) - 1)
	battle.set("event", parent_event)
	return current_relay


func priority_event(battle: Object, event_id: String, target: Variant = null, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE, on_effect: bool = false) -> Variant:
	return run_event(battle, event_id, target, source, source_effect, relay_var, on_effect, false)


func each_event(battle: Object, event_id: String, source_effect: Variant = null, relay_var: Variant = NO_CHANGE) -> Array:
	var actives: Array = []
	for s in battle.get("sides"):
		if s is Object:
			for b in s.get("active"):
				if b != null and not bool(b.get("fainted")):
					actives.append({
						"pokemon": b,
						"effect_holder": b,
						"speed": int(b.call("get_action_speed")),
						"order": 0,
						"priority": 0,
						"sub_order": 0,
						"effect_order": 0,
					})
	speed_sort(battle, actives)
	var results: Array = []
	for entry in actives:
		var pkmn: Object = entry["pokemon"]
		if bool(pkmn.get("fainted")):
			continue
		results.append(run_event(battle, event_id, pkmn, null, source_effect, relay_var))
	return results


func residual_event(battle: Object) -> void:
	# End-of-turn Residual phase ordered by Showdown residualOrder / speed / residualSubOrder
	var handlers: Array[Dictionary] = []
	var field_obj: Variant = battle.get("field")
	if field_obj is Object:
		_collect_field_handlers(battle, handlers, field_obj, "onResidual", true)
	for s in battle.get("sides"):
		if s is Object:
			_collect_side_handlers(battle, handlers, s, s, "onResidual", true)
			for b in s.get("active"):
				if b != null and not bool(b.get("fainted")):
					_collect_battler_handlers(battle, handlers, b, "onResidual", false, true)
	speed_sort(battle, handlers)
	for h in handlers:
		var holder: Variant = h["effect_holder"]
		if holder is Object and holder.get("fainted") is bool and bool(holder.get("fainted")):
			continue
		var cb: Callable = h["callback"]
		cb.call({
			"battle": battle,
			"target": holder,
			"source": null,
			"effect": h["effect"],
			"effect_holder": holder,
			"state": h["state"],
			"relay_var": NO_CHANGE,
			"event_core": self,
		})


func _collect_battler_handlers(_battle: Object, handlers: Array[Dictionary], battler: Object, cb_name: String, suppress_breakable_ability: bool, is_residual: bool) -> void:
	# Uses cached battler.speed (matching sim/battle.ts:1045; never calls getActionSpeed recursively)
	var spd: int = int(battler.get("speed"))
	# 1. Major status
	var st_id: int = int(battler.get("status"))
	if st_id > 0:
		var st_eff := get_effect("status:%d" % st_id)
		_maybe_append(handlers, st_eff, cb_name, battler, battler.get("status_state"), spd, is_residual)

	# 2. Volatiles
	var vols: Dictionary = battler.get("volatiles")
	for vkey in vols.keys():
		var v_eff := get_effect(str(vkey))
		_maybe_append(handlers, v_eff, cb_name, battler, vols[vkey], spd, is_residual)

	# 3. Ability (respecting ignoring_ability and ability #104 breakable suppression)
	var ab_id: int = int(battler.get("ability_id"))
	if ab_id > 0 and not bool(battler.call("ignoring_ability")):
		var ab_eff := get_effect("ability:%d" % ab_id)
		if not (suppress_breakable_ability and bool(ab_eff.get("breakable", false))):
			_maybe_append(handlers, ab_eff, cb_name, battler, battler.get("ability_state"), spd, is_residual)

	# 4. Held item (respecting ignoring_item)
	var it_id: int = int(battler.get("item_id"))
	if it_id > 0 and not bool(battler.call("ignoring_item")):
		var it_eff := get_effect("item:%d" % it_id)
		_maybe_append(handlers, it_eff, cb_name, battler, battler.get("item_state"), spd, is_residual)


func _collect_side_handlers(_battle: Object, handlers: Array[Dictionary], side_obj: Object, holder: Variant, cb_name: String, is_residual: bool = false) -> void:
	var scs: Dictionary = side_obj.get("side_conditions")
	for ckey in scs.keys():
		var eff := get_effect(str(ckey))
		_maybe_append(handlers, eff, cb_name, holder, scs[ckey], 0, is_residual)


func _collect_field_handlers(_battle: Object, handlers: Array[Dictionary], field_obj: Object, cb_name: String, is_residual: bool = false) -> void:
	var wid: int = int(field_obj.get("weather_id"))
	if wid > 0:
		_maybe_append(handlers, get_effect("weather:%d" % wid), cb_name, field_obj, field_obj.get("weather_state"), 0, is_residual)
	var tid: int = int(field_obj.get("terrain_id"))
	if tid > 0:
		_maybe_append(handlers, get_effect("terrain:%d" % tid), cb_name, field_obj, field_obj.get("terrain_state"), 0, is_residual)
	var pws: Dictionary = field_obj.get("pseudo_weather")
	for pkey in pws.keys():
		_maybe_append(handlers, get_effect(str(pkey)), cb_name, field_obj, pws[pkey], 0, is_residual)


func _maybe_append(handlers: Array[Dictionary], effect: Dictionary, cb_name: String, holder: Variant, state: Dictionary, speed: int, is_residual: bool) -> void:
	if effect.is_empty():
		return
	var cbs: Dictionary = effect.get("callbacks", {})
	if not cbs.has(cb_name):
		return
	var cb: Variant = cbs[cb_name]
	if not (cb is Callable):
		return
	handlers.append(_make_handler(effect, cb, cb_name, holder, state, speed, int(state.get("effect_order", 0)), is_residual))


static func _make_handler(
	effect: Dictionary,
	cb: Callable,
	cb_name: String,
	holder: Variant,
	state: Dictionary,
	speed: int,
	effect_order: int,
	is_residual: bool = false
) -> Dictionary:
	var priorities: Dictionary = effect.get("priorities", {})
	var orders: Dictionary = effect.get("orders", {})
	var sub_orders: Dictionary = effect.get("sub_orders", {})
	var ord_val: int = 4294967295
	if is_residual and effect.has("residual_order"):
		ord_val = int(effect["residual_order"])
	elif orders.has(cb_name):
		ord_val = int(orders[cb_name])
	var sub_val: int = 0
	if is_residual and effect.has("residual_sub_order"):
		sub_val = int(effect["residual_sub_order"])
	elif sub_orders.has(cb_name):
		sub_val = int(sub_orders[cb_name])
	return {
		"effect": effect,
		"callback": cb,
		"callback_name": cb_name,
		"effect_holder": holder,
		"state": state,
		"order": ord_val,
		"priority": int(priorities.get(cb_name, 0)),
		"fractional_priority": float(effect.get("fractional_priority", 0.0)),
		"speed": speed,
		"sub_order": sub_val,
		"effect_order": effect_order,
	}


static func _is_no_change(v: Variant) -> bool:
	return (v == null) or (v is String and v == NO_CHANGE)
