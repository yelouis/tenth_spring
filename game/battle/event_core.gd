# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Event core mirroring pokemon-showdown@0.11.11 sim/battle.ts:
#   runEvent (:758), singleEvent (:571), eachEvent (:465), priorityEvent (:943),
#   findEventHandlers (:1035), speedSort (:429), comparePriority (:404),
#   chainModify (:2318), modify (:2329), suppressingAbility (:365).

const StatsRef := preload("res://creatures/stats.gd")
const BattleRandomRef := preload("res://battle/battle_random.gd")

# Sentinels mirroring Showdown JS undefined / null / '' (sim/battle.ts:272, 912-923).
const NO_CHANGE: String = "__TS_EVENT_NO_CHANGE__"
const NULL: String = "__TS_EVENT_NULL__"
const NOT_FAIL: String = "__TS_EVENT_NOT_FAIL__"
const DEFAULT_ORDER: int = 4294967296
const LEFT_TO_RIGHT_EVENTS: Array[String] = ["Invulnerability", "TryHit", "DamagingHit", "EntryHazard"]
const UNPREFIXED_EVENTS: Array[String] = ["BeforeTurn", "Update", "Weather", "WeatherChange", "TerrainChange"]

var _effects: Dictionary = {}
var last_depth_error: String = ""


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
	var a_ord: int = int(a.get("order", DEFAULT_ORDER))
	var b_ord: int = int(b.get("order", DEFAULT_ORDER))
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


static func compare_redirect_order(a: Dictionary, b: Dictionary) -> int:
	# sim/battle.ts:413-419: priority desc, speed desc, holder ability_state.effect_order asc.
	var a_pri: int = int(a.get("priority", 0))
	var b_pri: int = int(b.get("priority", 0))
	if a_pri != b_pri:
		return -1 if a_pri > b_pri else 1
	var a_spe: int = int(a.get("speed", 0))
	var b_spe: int = int(b.get("speed", 0))
	if a_spe != b_spe:
		return -1 if a_spe > b_spe else 1
	var ah: Variant = a.get("effect_holder", null)
	var bh: Variant = b.get("effect_holder", null)
	if ah is Object and bh is Object and ah.get("ability_state") is Dictionary and bh.get("ability_state") is Dictionary:
		var a_eo: int = int((ah.get("ability_state") as Dictionary).get("effect_order", 0))
		var b_eo: int = int((bh.get("ability_state") as Dictionary).get("effect_order", 0))
		if a_eo != b_eo:
			return -1 if a_eo < b_eo else 1
	return 0


static func compare_left_to_right_order(a: Dictionary, b: Dictionary) -> int:
	# sim/battle.ts:421-426: order asc, priority desc, index asc.
	var a_ord: int = int(a.get("order", DEFAULT_ORDER))
	var b_ord: int = int(b.get("order", DEFAULT_ORDER))
	if a_ord != b_ord:
		return -1 if a_ord < b_ord else 1
	var a_pri: int = int(a.get("priority", 0))
	var b_pri: int = int(b.get("priority", 0))
	if a_pri != b_pri:
		return -1 if a_pri > b_pri else 1
	var a_idx: int = int(a.get("index", 0))
	var b_idx: int = int(b.get("index", 0))
	return (-1 if a_idx < b_idx else 1) if a_idx != b_idx else 0


static func _sort_by_mode(list: Array, mode: int) -> void:
	for i in range(1, list.size()):
		var cur: Variant = list[i]
		var j: int = i - 1
		while j >= 0 and ((compare_redirect_order(list[j], cur) if mode == 1 else compare_left_to_right_order(list[j], cur)) > 0):
			list[j + 1] = list[j]
			j -= 1
		list[j + 1] = cur


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


func single_event(battle: Object, event_id: String, effect: Dictionary, state: Dictionary, target: Variant, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE, custom_callback: Callable = Callable()) -> Variant:
	# sim/battle.ts:571-652: depth guard, four suppression checks, no modifier/rounding.
	if int(battle.get("event_depth")) >= 8:
		last_depth_error = "EventCore: event depth over 8: %s" % event_id
		push_error(last_depth_error)
		return false
	var has_relay: bool = not _is_no_change(relay_var)
	var cur_relay: Variant = relay_var if has_relay else true
	if effect.is_empty() or _is_suppressed_single(battle, event_id, effect, target):
		return cur_relay
	var cb: Variant = custom_callback if custom_callback.is_valid() else (effect.get("callbacks", {}) as Dictionary).get("on" + event_id, null)
	if not (cb is Callable) or not (cb as Callable).is_valid():
		return cur_relay

	var parent_event: Dictionary = battle.get("event")
	battle.set("event", {"id": event_id, "target": target, "source": source, "effect": source_effect})
	battle.set("event_depth", int(battle.get("event_depth")) + 1)
	var ret: Variant = (cb as Callable).call({
		"battle": battle, "target": target, "source": source, "effect": source_effect,
		"effect_holder": target, "state": state, "has_relay_var": has_relay,
		"relay_var": cur_relay if has_relay else NO_CHANGE, "event_core": self,
	})
	battle.set("event_depth", int(battle.get("event_depth")) - 1)
	battle.set("event", parent_event)
	return cur_relay if _is_no_change(ret) else ret


func find_event_handlers(battle: Object, target: Variant, event_name: String, source: Variant = null) -> Array[Dictionary]:
	# sim/battle.ts:1035-1095: collects without suppression filtering or sorting.
	var handlers: Array[Dictionary] = []
	var should_bubble_down: bool = _is_side(target)
	var prefixed: bool = not (event_name in UNPREFIXED_EVENTS)
	var cur_target: Variant = target
	if _is_battler(cur_target) and (bool(cur_target.get("is_active")) or (_is_battler(source) and bool(source.get("is_active")))):
		_collect_pokemon(handlers, cur_target, "on" + event_name)
		if prefixed:
			var t_side: Variant = cur_target.get("side")
			if _is_side(t_side):
				for ally in t_side.get("active"):
					if ally != null and not bool(ally.get("fainted")):
						_collect_pokemon(handlers, ally, "onAlly" + event_name)
						_collect_pokemon(handlers, ally, "onAny" + event_name)
				var f_side: Variant = t_side.call("foe_side")
				if _is_side(f_side):
					for foe in f_side.get("active"):
						if foe != null and not bool(foe.get("fainted")):
							_collect_pokemon(handlers, foe, "onFoe" + event_name)
							_collect_pokemon(handlers, foe, "onAny" + event_name)
		cur_target = cur_target.get("side")
	if _is_battler(source) and prefixed:
		_collect_pokemon(handlers, source, "onSource" + event_name)
	if _is_side(cur_target):
		for s in battle.get("sides"):
			if not _is_side(s):
				continue
			if should_bubble_down:
				for act in s.get("active"):
					if act != null and not bool(act.get("fainted")):
						if s == cur_target:
							_collect_pokemon(handlers, act, "on" + event_name)
						elif prefixed:
							_collect_pokemon(handlers, act, "onFoe" + event_name)
						if prefixed:
							_collect_pokemon(handlers, act, "onAny" + event_name)
			if s == cur_target:
				_collect_side(handlers, s, "on" + event_name)
			elif prefixed:
				_collect_side(handlers, s, "onFoe" + event_name)
			if prefixed:
				_collect_side(handlers, s, "onAny" + event_name)
	var fld: Variant = battle.get("field")
	if _is_field(fld):
		_collect_field(handlers, fld, "on" + event_name)
	return handlers


func run_event(battle: Object, event_id: String, target: Variant = null, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE, on_effect: bool = false, fast_exit: bool = false) -> Variant:
	# sim/battle.ts:758-937
	if int(battle.get("event_depth")) >= 8:
		last_depth_error = "EventCore: event depth over 8: %s" % event_id
		push_error(last_depth_error)
		return false
	var ev_target: Variant = target if target != null else battle
	var eff_source: Variant = source if _is_battler(source) else null
	var handlers: Array[Dictionary] = find_event_handlers(battle, ev_target, event_id, eff_source)
	if on_effect and source_effect is Dictionary:
		var cb_name: String = "on" + event_id
		var cb: Variant = (source_effect.get("callbacks", {}) as Dictionary).get(cb_name, null)
		if cb is Callable:
			handlers.push_front(resolve_priority({"effect": source_effect, "callback": cb, "state": {}, "end": Callable(), "effect_holder": ev_target, "kind": "effect"}, cb_name))
	if event_id in LEFT_TO_RIGHT_EVENTS:
		_sort_by_mode(handlers, 2)
	elif fast_exit:
		_sort_by_mode(handlers, 1)
	else:
		speed_sort(battle, handlers)

	var has_relay: bool = not _is_no_change(relay_var)
	var current_relay: Variant = relay_var if has_relay else true
	var parent_event: Dictionary = battle.get("event")
	# sim/battle.ts:807: one modifier per event, applied once after the loop.
	var cur_event := {"id": event_id, "target": ev_target, "source": source, "effect": source_effect, "modifier": 4096}
	battle.set("event", cur_event)
	battle.set("event_depth", int(battle.get("event_depth")) + 1)

	for h in handlers:
		if _is_suppressed_run(battle, event_id, h["effect"], h["effect_holder"]):
			continue
		var ret: Variant = (h["callback"] as Callable).call({
			"battle": battle, "target": ev_target, "source": source, "effect": source_effect,
			"effect_holder": h["effect_holder"], "state": h["state"], "has_relay_var": has_relay,
			"relay_var": current_relay if has_relay else NO_CHANGE, "event_core": self,
		})
		if not _is_no_change(ret):
			current_relay = ret
			if _is_empty_return(current_relay) or fast_exit:
				break

	battle.set("event_depth", int(battle.get("event_depth")) - 1)
	# sim/battle.ts:929-933: apply single modifier once to whole numbers >= 0.
	if (current_relay is int and current_relay >= 0) or (current_relay is float and current_relay >= 0.0 and current_relay == floor(current_relay)):
		current_relay = poke_round(int(current_relay), int(cur_event.get("modifier", 4096)))
	battle.set("event", parent_event)
	return current_relay


func priority_event(battle: Object, event_id: String, target: Variant = null, source: Variant = null, source_effect: Variant = null, relay_var: Variant = NO_CHANGE, on_effect: bool = false) -> Variant:
	# sim/battle.ts:943-948
	return run_event(battle, event_id, target, source, source_effect, relay_var, on_effect, true)


func each_event(battle: Object, event_id: String, source_effect: Variant = null, relay_var: Variant = NO_CHANGE) -> Array:
	# sim/battle.ts:465-476
	var actives: Array = []
	for s in battle.get("sides"):
		if s is Object:
			for b in s.get("active"):
				if b != null and not bool(b.get("fainted")):
					actives.append({"pokemon": b, "effect_holder": b, "speed": int(b.get("speed")), "order": 0, "priority": 0, "sub_order": 0, "effect_order": 0})
	speed_sort(battle, actives)
	var results: Array = []
	for entry in actives:
		if not bool((entry["pokemon"] as Object).get("fainted")):
			results.append(run_event(battle, event_id, entry["pokemon"], null, source_effect, relay_var))
	if event_id == "Weather" and int(battle.get("gen")) >= 7:
		each_event(battle, "Update")
	return results


func field_event(battle: Object, event_id: String, targets: Array = []) -> void:
	# sim/battle.ts:484-568: Residual / SwitchIn phase with durations, endings, stale checks & faints.
	var cb_name: String = "on" + event_id
	var get_key: String = "duration" if event_id == "Residual" else ""
	var fld: Variant = battle.get("field")
	var handlers: Array[Dictionary] = []
	if _is_field(fld):
		_collect_field(handlers, fld, "onField" + event_id, get_key)
	for s in battle.get("sides"):
		if not _is_side(s):
			continue
		_collect_side(handlers, s, "onSide" + event_id, get_key)
		for active in s.get("active"):
			if active == null:
				continue
			if event_id == "SwitchIn":
				_collect_pokemon(handlers, active, "onAny" + event_id)
			if not targets.is_empty() and not targets.has(active):
				continue
			_collect_pokemon(handlers, active, cb_name, get_key)
			_collect_side(handlers, s, cb_name, "", active)
			if _is_field(fld):
				_collect_field(handlers, fld, cb_name, "", active)
	speed_sort(battle, handlers)
	while not handlers.is_empty():
		var h: Dictionary = handlers.pop_front()
		var holder: Variant = h["effect_holder"]
		var st: Dictionary = h["state"]
		if _is_battler(holder) and bool(holder.get("fainted")) and not bool(st.get("is_slot_condition", false)):
			continue
		var end_cb: Variant = h.get("end", Callable())
		if event_id == "Residual" and end_cb is Callable and (end_cb as Callable).is_valid() and int(st.get("duration", 0)) > 0:
			st["duration"] = int(st["duration"]) - 1
			if int(st["duration"]) == 0:
				(end_cb as Callable).call()
				if bool(battle.get("ended")):
					return
				continue
		if not _is_state_live(h):
			continue
		var h_ev: String = ("Side" + event_id) if _is_side(holder) else (("Field" + event_id) if _is_field(holder) else event_id)
		var cb: Variant = h.get("callback", Callable())
		if cb is Callable and (cb as Callable).is_valid():
			single_event(battle, h_ev, h["effect"], st, holder, null, null, NO_CHANGE, cb)
		battle.call("check_faints")
		if bool(battle.get("ended")):
			return


func resolve_priority(handler: Dictionary, cb_name: String) -> Dictionary:
	# sim/battle.ts:950-1016
	var eff: Dictionary = handler["effect"]
	var st: Dictionary = handler["state"]
	var holder: Variant = handler["effect_holder"]
	var kind: String = str(handler.get("kind", ""))
	var is_res: bool = cb_name in ["onResidual", "onSideResidual", "onFieldResidual"]
	var orders: Dictionary = eff.get("orders", {})
	var sub_orders: Dictionary = eff.get("sub_orders", {})
	var ord_val: int = int(orders[cb_name]) if orders.has(cb_name) else (int(eff["residual_order"]) if (is_res and eff.has("residual_order")) else DEFAULT_ORDER)
	var sub_val: int = int(sub_orders[cb_name]) if sub_orders.has(cb_name) else (int(eff["residual_sub_order"]) if (is_res and eff.has("residual_sub_order")) else 0)
	if sub_val == 0:
		var et: String = _effect_type(eff)
		if kind == "slot" or bool(st.get("is_slot_condition", false)):
			sub_val = 3
		elif kind == "side":
			sub_val = 4
		elif kind in ["weather", "terrain", "pseudo_weather"] or et in ["Weather", "Terrain"]:
			sub_val = 5
		elif et in ["Condition", "Status"] or kind in ["status", "volatile"]:
			sub_val = 2
		elif et == "Ability" or kind == "ability":
			var ab_num: int = _effect_num(eff)
			sub_val = 6 if (ab_num == 143 or ab_num == 253) else (9 if ab_num == 100 else 7)
		elif et == "Item" or kind == "item":
			sub_val = 8
	var eo_val: int = int(st.get("effect_order", 0)) if (cb_name.ends_with("SwitchIn") or cb_name.ends_with("RedirectTarget")) else 0
	# Slice 3: SwitchIn speedOrder fractional adjustment (sim/battle.ts:1012).
	handler["callback_name"] = cb_name
	handler["order"] = ord_val
	handler["priority"] = int((eff.get("priorities", {}) as Dictionary).get(cb_name, 0))
	handler["fractional_priority"] = float(eff.get("fractional_priority", 0.0))
	handler["speed"] = int(holder.get("speed")) if _is_battler(holder) else 0
	handler["sub_order"] = sub_val
	handler["effect_order"] = eo_val
	return handler


func _collect_entry(handlers: Array[Dictionary], key: String, st: Dictionary, cb_name: String, get_key: String, holder: Variant, owner: Variant, kind: String, end_cb: Callable, slot_idx: int = -1) -> void:
	var eff := get_effect(key)
	var cb: Callable = Callable()
	if not eff.is_empty():
		var cbs: Dictionary = eff.get("callbacks", {})
		if cbs.has(cb_name) and cbs[cb_name] is Callable:
			cb = cbs[cb_name]
		elif _is_battler(holder) and cb_name == "onSwitchIn" and not cbs.has("onAnySwitchIn") and _effect_type(eff) in ["Ability", "Item"] and cbs.has("onStart") and cbs["onStart"] is Callable:
			cb = cbs["onStart"]
	if cb.is_valid() or (get_key != "" and int(st.get(get_key, 0)) > 0):
		handlers.append(resolve_priority({"effect": eff, "effect_key": key, "callback": cb, "state": st, "end": end_cb, "effect_holder": holder, "owner": owner, "kind": kind, "slot_idx": slot_idx}, cb_name))


func _collect_pokemon(handlers: Array[Dictionary], pkmn: Object, cb_name: String, get_key: String = "") -> void:
	# sim/battle.ts:1097-1156
	if int(pkmn.get("status")) > 0:
		_collect_entry(handlers, "status:%d" % int(pkmn.get("status")), pkmn.get("status_state"), cb_name, get_key, pkmn, pkmn, "status", Callable(pkmn, "clear_status"))
	for vk in (pkmn.get("volatiles") as Dictionary).keys():
		_collect_entry(handlers, str(vk), (pkmn.get("volatiles") as Dictionary)[vk], cb_name, get_key, pkmn, pkmn, "volatile", Callable(pkmn, "remove_volatile").bind(str(vk)))
	if int(pkmn.get("ability_id")) > 0:
		_collect_entry(handlers, "ability:%d" % int(pkmn.get("ability_id")), pkmn.get("ability_state"), cb_name, get_key, pkmn, pkmn, "ability", Callable(pkmn, "clear_ability"))
	if int(pkmn.get("item_id")) > 0:
		_collect_entry(handlers, "item:%d" % int(pkmn.get("item_id")), pkmn.get("item_state"), cb_name, get_key, pkmn, pkmn, "item", Callable(pkmn, "clear_item"))
	var p_side: Variant = pkmn.get("side")
	if _is_side(p_side):
		var sidx: int = int(pkmn.get("slot"))
		var slist: Array = p_side.get("slot_conditions")
		if sidx >= 0 and sidx < slist.size():
			for sk in (slist[sidx] as Dictionary).keys():
				_collect_entry(handlers, str(sk), (slist[sidx] as Dictionary)[sk], cb_name, get_key, pkmn, p_side, "slot", Callable(p_side, "remove_slot_condition").bind(sidx, str(sk)), sidx)


func _collect_side(handlers: Array[Dictionary], s: Object, cb_name: String, get_key: String = "", custom_holder: Variant = null) -> void:
	for ck in (s.get("side_conditions") as Dictionary).keys():
		_collect_entry(handlers, str(ck), (s.get("side_conditions") as Dictionary)[ck], cb_name, get_key, custom_holder if custom_holder != null else s, s, "side", Callable() if custom_holder != null else Callable(s, "remove_side_condition").bind(str(ck)))


func _collect_field(handlers: Array[Dictionary], fld: Object, cb_name: String, get_key: String = "", custom_holder: Variant = null) -> void:
	var h: Variant = custom_holder if custom_holder != null else fld
	for pk in (fld.get("pseudo_weather") as Dictionary).keys():
		_collect_entry(handlers, str(pk), (fld.get("pseudo_weather") as Dictionary)[pk], cb_name, get_key, h, fld, "pseudo_weather", Callable() if custom_holder != null else Callable(fld, "remove_pseudo_weather").bind(str(pk)))
	if int(fld.get("weather_id")) > 0:
		_collect_entry(handlers, "weather:%d" % int(fld.get("weather_id")), fld.get("weather_state"), cb_name, get_key, h, fld, "weather", Callable() if custom_holder != null else Callable(fld, "clear_weather"))
	if int(fld.get("terrain_id")) > 0:
		_collect_entry(handlers, "terrain:%d" % int(fld.get("terrain_id")), fld.get("terrain_state"), cb_name, get_key, h, fld, "terrain", Callable() if custom_holder != null else Callable(fld, "clear_terrain"))


static func _is_suppressed_single(battle: Object, event_id: String, eff: Dictionary, target: Variant) -> bool:
	# sim/battle.ts:598-622
	var et: String = _effect_type(eff)
	if et == "Status" and _is_battler(target) and str(eff.get("id", "")) != ("status:%d" % int(target.get("status"))):
		return true
	if event_id == "SwitchIn" and et == "Ability" and bool(eff.get("breakable", false)) and bool(battle.call("suppressing_ability", target)):
		return true
	if event_id not in ["Start", "TakeItem", "SetAbility"] and et == "Item" and _is_battler(target) and bool(target.call("ignoring_item")):
		return true
	if event_id != "End" and et == "Ability" and _is_battler(target) and bool(target.call("ignoring_ability")):
		return true
	var fld: Variant = battle.get("field")
	return et == "Weather" and event_id not in ["FieldStart", "FieldResidual", "FieldEnd"] and _is_field(fld) and bool(fld.call("suppressing_weather"))


static func _is_suppressed_run(battle: Object, event_id: String, eff: Dictionary, holder: Variant) -> bool:
	# sim/battle.ts:832-895
	var et: String = _effect_type(eff)
	if et == "Status" and _is_battler(holder) and str(eff.get("id", "")) != ("status:%d" % int(holder.get("status"))):
		return true
	if et == "Ability" and bool(eff.get("breakable", false)) and bool(battle.call("suppressing_ability", holder)):
		return true
	if event_id not in ["Start", "SwitchIn", "TakeItem"] and et == "Item" and _is_battler(holder) and bool(holder.call("ignoring_item")):
		return true
	if event_id != "End" and et == "Ability" and _is_battler(holder) and bool(holder.call("ignoring_ability")):
		return true
	var fld: Variant = battle.get("field")
	return (et == "Weather" or event_id == "Weather") and event_id not in ["Residual", "End"] and _is_field(fld) and bool(fld.call("suppressing_weather"))


static func _is_state_live(h: Dictionary) -> bool:
	# sim/battle.ts:526-556: identity check via is_same().
	var k: String = str(h.get("kind", ""))
	var o: Variant = h.get("owner", null)
	var st: Dictionary = h["state"]
	var ek: String = str(h.get("effect_key", ""))
	if not (o is Object):
		return true
	if k == "status":
		return int(o.get("status")) > 0 and is_same(o.get("status_state"), st)
	if k == "volatile":
		return (o.get("volatiles") as Dictionary).has(ek) and is_same((o.get("volatiles") as Dictionary)[ek], st)
	if k == "ability":
		return int(o.get("ability_id")) > 0 and is_same(o.get("ability_state"), st)
	if k == "item":
		return int(o.get("item_id")) > 0 and is_same(o.get("item_state"), st)
	if k == "slot":
		var idx: int = int(h.get("slot_idx", 0))
		var sl: Array = o.get("slot_conditions")
		return idx >= 0 and idx < sl.size() and (sl[idx] as Dictionary).has(ek) and is_same((sl[idx] as Dictionary)[ek], st)
	if k == "side":
		return (o.get("side_conditions") as Dictionary).has(ek) and is_same((o.get("side_conditions") as Dictionary)[ek], st)
	if k == "weather":
		return int(o.get("weather_id")) > 0 and is_same(o.get("weather_state"), st)
	if k == "terrain":
		return int(o.get("terrain_id")) > 0 and is_same(o.get("terrain_state"), st)
	if k == "pseudo_weather":
		return (o.get("pseudo_weather") as Dictionary).has(ek) and is_same((o.get("pseudo_weather") as Dictionary)[ek], st)
	return true


static func _is_battler(obj: Variant) -> bool:
	return obj is Object and obj.has_method("get_action_speed")


static func _is_side(obj: Variant) -> bool:
	return obj is Object and obj.has_method("foe_side")


static func _is_field(obj: Variant) -> bool:
	return obj is Object and obj.has_method("has_pseudo_weather")


static func _effect_type(eff: Dictionary) -> String:
	var explicit: String = str(eff.get("effect_type", ""))
	if explicit != "":
		return explicit
	var eid: String = str(eff.get("id", ""))
	for pair in [["ability:", "Ability"], ["item:", "Item"], ["status:", "Status"], ["weather:", "Weather"], ["terrain:", "Terrain"], ["move:", "Move"]]:
		if eid.begins_with(pair[0]):
			return pair[1]
	return "Condition"


static func _effect_num(eff: Dictionary) -> int:
	var eid: String = str(eff.get("id", ""))
	var c: int = eid.find(":")
	return int(eid.substr(c + 1)) if c >= 0 else int(eff.get("num", 0))


static func _is_no_change(v: Variant) -> bool:
	return (v == null) or (v is String and v == NO_CHANGE)


static func _is_empty_return(v: Variant) -> bool:
	return (v is bool and not v) or (v is int and v == 0) or (v is float and v == 0.0) or (v is String and (v == "" or v == NULL or v == NOT_FAIL))
