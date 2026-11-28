extends Node

# Unit Tests for Slice 1 Event Core & Action Queue (Item 94):
# - handler ordering (order, priority, speed, sub_order, effect_order, seeded tie shuffle)
# - relay-variable rules (NO_CHANGE, false fail/stop, numeric replacement)
# - chainModify & modify at 4096 scale (exact Gen 8 fixed-point rounding)
# - all 5 prefix scopes (on, onAlly, onFoe, onSource, onAny)
# - ability suppression (ignoring_ability, ignoring_item, breakable suppression)
# - ActionQueue Showdown orders + Tenth Spring run/bag/ball orders before switch

const BattleRandomRef := preload("res://battle/battle_random.gd")
const EventCoreRef := preload("res://battle/event_core.gd")
const ActionQueueRef := preload("res://battle/action_queue.gd")
const BattleStateRef := preload("res://battle/state/battle_state.gd")
const DamageRef := preload("res://battle/damage.gd")
const StatsRef := preload("res://creatures/stats.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")


func _make_test_battle(rng: RefCounted = null) -> RefCounted:
	var sp_fn := func(dex: int) -> Dictionary:
		return {
			"dex": dex,
			"base_stats": {"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 120 if dex == 1 else 80},
			"types": ["normal"],
			"weight_hg": 500,
		}
	var mv_fn := func(mid: int) -> Dictionary:
		return {"id": mid, "type": "normal", "damage_class": "physical", "power": 80, "accuracy": 100, "pp": 15, "priority": 0, "meta": {"crit_rate": 0}}
	return BattleStateRef.new(rng, AssetDBRef.DEFAULT_CACHE_DIR, sp_fn, mv_fn)


func run_test() -> bool:
	if not _test_handler_ordering_and_speed_sort():
		return false
	if not _test_relay_variable_rules():
		return false
	if not _test_chain_modify_4096():
		return false
	if not _test_prefix_scopes():
		return false
	if not _test_ability_and_item_suppression():
		return false
	if not _test_action_queue_and_residual_order():
		return false
	if not _test_item96_showdown_rules():
		return false
	return true


func _test_handler_ordering_and_speed_sort() -> bool:
	var rng := BattleRandomRef.create_seeded(42)
	var b := _make_test_battle(rng)
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9001, "item_id": 9101, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9002, "item_id": 0, "moves": [1]}]
	)
	var ev_core: Object = b.event_core
	var log_order: Array[String] = []

	# Register handlers with explicit order, priority, sub_order, and speed ties
	ev_core.register_effect("ability:9001", {
		"id": "ability:9001",
		"callbacks": {"onOrderProbe": func(_ctx): log_order.append("pri_high"); return EventCoreRef.NO_CHANGE},
		"priorities": {"onOrderProbe": 20},
	})
	ev_core.register_effect("item:9101", {
		"id": "item:9101",
		"callbacks": {"onOrderProbe": func(_ctx): log_order.append("pri_low"); return EventCoreRef.NO_CHANGE},
		"priorities": {"onOrderProbe": 5},
	})
	ev_core.register_effect("ability:9002", {
		"id": "ability:9002",
		"callbacks": {"onFoeOrderProbe": func(_ctx): log_order.append("pri_mid"); return EventCoreRef.NO_CHANGE},
		"priorities": {"onFoeOrderProbe": 10},
	})

	var target: Object = b.sides[0].call("active_battler")
	ev_core.run_event(b, "OrderProbe", target)
	if log_order != ["pri_high", "pri_mid", "pri_low"]:
		push_error("battle_event_core_test: priority order mismatch: %s" % str(log_order))
		return false

	# Full 5-key speed_sort check (order asc -> priority desc -> speed desc -> sub_order asc -> effect_order asc)
	var items: Array = [
		{"tag": "ord200_pri0_spe50", "order": 200, "priority": 0, "speed": 50, "sub_order": 0, "effect_order": 1},
		{"tag": "ord100_pri0_spe10", "order": 100, "priority": 0, "speed": 10, "sub_order": 0, "effect_order": 2},
		{"tag": "ord200_pri1_spe10", "order": 200, "priority": 1, "speed": 10, "sub_order": 0, "effect_order": 3},
		{"tag": "ord200_pri0_spe90_sub1", "order": 200, "priority": 0, "speed": 90, "sub_order": 1, "effect_order": 4},
		{"tag": "ord200_pri0_spe90_sub0_eo2", "order": 200, "priority": 0, "speed": 90, "sub_order": 0, "effect_order": 2},
		{"tag": "ord200_pri0_spe90_sub0_eo1", "order": 200, "priority": 0, "speed": 90, "sub_order": 0, "effect_order": 1},
	]
	ev_core.speed_sort(b, items)
	var got_tags: Array[String] = []
	for it in items:
		got_tags.append(str(it["tag"]))
	var exp_tags: Array[String] = [
		"ord100_pri0_spe10",
		"ord200_pri1_spe10",
		"ord200_pri0_spe90_sub0_eo1",
		"ord200_pri0_spe90_sub0_eo2",
		"ord200_pri0_spe90_sub1",
		"ord200_pri0_spe50",
	]
	if got_tags != exp_tags:
		push_error("battle_event_core_test: speed_sort mismatch got=%s exp=%s" % [str(got_tags), str(exp_tags)])
		return false

	# Seeded tie shuffle produces both outcomes across seeds and respects policy speed_tie
	var p0 := BattleRandomRef.create_policy({"speed_tie": 0})
	var p1 := BattleRandomRef.create_policy({"speed_tie": 1})
	var b0 := _make_test_battle(p0)
	var b1 := _make_test_battle(p1)
	var tie0: Array = [
		{"side_idx": 1, "order": 200, "priority": 0, "speed": 100, "sub_order": 0, "effect_order": 0},
		{"side_idx": 0, "order": 200, "priority": 0, "speed": 100, "sub_order": 0, "effect_order": 0},
	]
	var tie1: Array = tie0.duplicate(true)
	b0.event_core.speed_sort(b0, tie0)
	b1.event_core.speed_sort(b1, tie1)
	if int(tie0[0]["side_idx"]) != 0 or int(tie1[0]["side_idx"]) != 1:
		push_error("battle_event_core_test: policy speed_tie failed")
		return false
	return true


func _test_relay_variable_rules() -> bool:
	var b := _make_test_battle(BattleRandomRef.create_seeded(7))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9010, "item_id": 9110, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9011, "item_id": 0, "moves": [1]}]
	)
	var ev_core: Object = b.event_core
	var t: Object = b.sides[0].call("active_battler")

	# 1. Handler returning NO_CHANGE (or void) keeps relay_var; number replaces it
	ev_core.register_effect("ability:9010", {
		"id": "ability:9010",
		"callbacks": {"onRelayNum": func(_ctx): return EventCoreRef.NO_CHANGE},
		"priorities": {"onRelayNum": 20},
	})
	ev_core.register_effect("item:9110", {
		"id": "item:9110",
		"callbacks": {"onRelayNum": func(ctx): return int(ctx["relay_var"]) + 25},
		"priorities": {"onRelayNum": 10},
	})
	var res_num: Variant = ev_core.run_event(b, "RelayNum", t, null, null, 100)
	if int(res_num) != 125:
		push_error("battle_event_core_test: relay numeric replacement failed: %s" % str(res_num))
		return false

	# 2. Handler returning false stops execution immediately and returns false
	var after_false_ran: Array[bool] = [false]
	ev_core.register_effect("ability:9010", {
		"id": "ability:9010",
		"callbacks": {"onRelayStop": func(_ctx): return false},
		"priorities": {"onRelayStop": 20},
	})
	ev_core.register_effect("item:9110", {
		"id": "item:9110",
		"callbacks": {"onRelayStop": func(_ctx): after_false_ran[0] = true; return 999},
		"priorities": {"onRelayStop": 10},
	})
	var res_stop: Variant = ev_core.run_event(b, "RelayStop", t, null, null, 100)
	if not (res_stop is bool and res_stop == false) or after_false_ran[0]:
		push_error("battle_event_core_test: false relay must fail and short-circuit")
		return false
	return true


func _test_chain_modify_4096() -> bool:
	# Exact Showdown chain() math: ((prev * next + 2048) >> 12)
	# 1.5x (6144) chained with 1.3x (5325) = ((6144 * 5325 + 2048) >> 12) = 7988
	if EventCoreRef.chain_mod(6144, 5325) != 7988:
		push_error("battle_event_core_test: chain_mod(6144, 5325) expected 7988 got %d" % EventCoreRef.chain_mod(6144, 5325))
		return false
	# 0.5x (2048) chained with 1.5x (6144) = 3072
	if EventCoreRef.chain_mod(2048, 6144) != 3072:
		push_error("battle_event_core_test: chain_mod(2048, 6144) expected 3072")
		return false

	# Live chain_modify inside run_event
	var b := _make_test_battle(BattleRandomRef.create_seeded(9))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9020, "item_id": 9120, "moves": [1]}],
		[{"dex": 2, "level": 50, "moves": [1]}]
	)
	var ev_core: Object = b.event_core
	ev_core.register_effect("ability:9020", {
		"id": "ability:9020",
		"callbacks": {"onBasePower": func(ctx): ctx["event_core"].chain_modify(ctx["battle"], 6144, 4096); return EventCoreRef.NO_CHANGE},
		"priorities": {"onBasePower": 20},
	})
	ev_core.register_effect("item:9120", {
		"id": "item:9120",
		"callbacks": {"onBasePower": func(ctx): ctx["event_core"].chain_modify(ctx["battle"], 4915, 4096); return EventCoreRef.NO_CHANGE},
		"priorities": {"onBasePower": 10},
	})
	var t: Object = b.sides[0].call("active_battler")
	# One modifier per event (sim/battle.ts:807,929): 6144 chained with 4915 = 7373 -> [63, 108, 139, 182]
	var got_vals: Array[int] = []
	for v in [35, 60, 77, 101]:
		got_vals.append(int(ev_core.run_event(b, "BasePower", t, null, null, v)))
	if got_vals != [63, 108, 139, 182]:
		push_error("battle_event_core_test: one-modifier expected [63, 108, 139, 182] got %s" % str(got_vals))
		return false
	return true


func _test_prefix_scopes() -> bool:
	var b := _make_test_battle(BattleRandomRef.create_seeded(11))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9030, "item_id": 9130, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9031, "item_id": 9131, "moves": [1]}]
	)
	var ev_core: Object = b.event_core
	var fired: Array[String] = []

	ev_core.register_effect("ability:9030", {
		"id": "ability:9030",
		"callbacks": {
			"onScopeTest": func(_ctx): fired.append("on"); return EventCoreRef.NO_CHANGE,
			"onAllyScopeTest": func(_ctx): fired.append("onAlly"); return EventCoreRef.NO_CHANGE,
		},
		"priorities": {"onScopeTest": 50, "onAllyScopeTest": 40},
	})
	ev_core.register_effect("ability:9031", {
		"id": "ability:9031",
		"callbacks": {
			"onFoeScopeTest": func(_ctx): fired.append("onFoe"); return EventCoreRef.NO_CHANGE,
			"onSourceScopeTest": func(_ctx): fired.append("onSource"); return EventCoreRef.NO_CHANGE,
		},
		"priorities": {"onFoeScopeTest": 30, "onSourceScopeTest": 20},
	})
	ev_core.register_effect("item:9131", {
		"id": "item:9131",
		"callbacks": {
			"onAnyScopeTest": func(_ctx): fired.append("onAny"); return EventCoreRef.NO_CHANGE,
		},
		"priorities": {"onAnyScopeTest": 10},
	})

	var target: Object = b.sides[0].call("active_battler")
	var source: Object = b.sides[1].call("active_battler")
	ev_core.run_event(b, "ScopeTest", target, source)
	if fired != ["on", "onAlly", "onFoe", "onSource", "onAny"]:
		push_error("battle_event_core_test: prefix scopes mismatch: %s" % str(fired))
		return false
	return true


func _test_ability_and_item_suppression() -> bool:
	var b := _make_test_battle(BattleRandomRef.create_seeded(13))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 104, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9040, "item_id": 9140, "moves": [1]}]
	)
	var ev_core: Object = b.event_core
	ev_core.register_effect("ability:9040", {
		"id": "ability:9040",
		"breakable": true,
		"callbacks": {"onModifyDef": func(ctx): ctx["event_core"].chain_modify(ctx["battle"], 8192, 4096); return EventCoreRef.NO_CHANGE},
	})
	ev_core.register_effect("item:9140", {
		"id": "item:9140",
		"callbacks": {"onModifyDef": func(ctx): ctx["event_core"].chain_modify(ctx["battle"], 6144, 4096); return EventCoreRef.NO_CHANGE},
	})

	var attacker: Object = b.sides[0].call("active_battler")
	var defender: Object = b.sides[1].call("active_battler")

	# 1. Without attacker active_pokemon set, both breakable ability (2x) and item (1.5x) apply -> 100 * 2 * 1.5 = 300
	var def_normal: int = int(ev_core.run_event(b, "ModifyDef", defender, attacker, null, 100))
	if def_normal != 300:
		push_error("battle_event_core_test: unsuppressed def expected 300 got %d" % def_normal)
		return false

	# 2. With active_move.ignore_ability on attacker, breakable ability is suppressed (only item 1.5x -> 150)
	b.active_pokemon = attacker
	b.active_move = {"id": 1, "ignore_ability": true}
	var def_suppressed: int = int(ev_core.run_event(b, "ModifyDef", defender, attacker, b.active_move, 100))
	b.active_pokemon = null
	b.active_move = {}
	if def_suppressed != 150:
		push_error("battle_event_core_test: breakable suppression expected 150 got %d" % def_suppressed)
		return false

	# 3. Volatile cond_380 suppresses defender's ability; field cond_478 suppresses defender's item -> 100
	defender.volatiles["cond_380"] = {}
	b.field.pseudo_weather["cond_478"] = {"duration": 5}
	var def_both_ignored: int = int(ev_core.run_event(b, "ModifyDef", defender, attacker, null, 100))
	if def_both_ignored != 100:
		push_error("battle_event_core_test: ignoring_ability + ignoring_item expected 100 got %d" % def_both_ignored)
		return false
	return true


func _test_action_queue_and_residual_order() -> bool:
	var b := _make_test_battle(BattleRandomRef.create_seeded(17))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9050, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9051, "moves": [1]}]
	)
	var q: Object = b.queue
	q.clear()
	q.add_choices(b, b.event_core, [
		{"choice": "residual"},
		{"choice": "move", "priority": 0, "speed": 120},
		{"choice": "move", "priority": 1, "speed": 50},
		{"choice": "megaEvo", "speed": 100},
		{"choice": "switch", "speed": 100},
		{"choice": "bag", "speed": 100},
		{"choice": "run", "speed": 100},
	])
	var choices_out: Array[String] = []
	while not q.is_empty():
		var a: Dictionary = q.shift()
		choices_out.append("%s:%d" % [str(a["choice"]), int(a["priority"])])
	var expected_out: Array[String] = [
		"run:0", "bag:0", "switch:0", "megaEvo:0", "move:1", "move:0", "residual:0"
	]
	if choices_out != expected_out:
		push_error("battle_event_core_test: ActionQueue order mismatch got=%s exp=%s" % [str(choices_out), str(expected_out)])
		return false

	# Residual order & subOrder
	var res_log: Array[String] = []
	b.event_core.register_effect("ability:9050", {
		"id": "ability:9050",
		"residual_order": 10,
		"residual_sub_order": 2,
		"callbacks": {"onResidual": func(_ctx): res_log.append("second")},
	})
	b.event_core.register_effect("ability:9051", {
		"id": "ability:9051",
		"residual_order": 5,
		"residual_sub_order": 0,
		"callbacks": {"onResidual": func(_ctx): res_log.append("first")},
	})
	b.event_core.field_event(b, "Residual")
	if res_log != ["first", "second"]:
		push_error("battle_event_core_test: residualOrder mismatch: %s" % str(res_log))
		return false
	return true


func _test_item96_showdown_rules() -> bool:
	# 1. Empty returns (NULL, NOT_FAIL, 0, false) stop; void preserves; priority_event fast-exits
	var b := _make_test_battle(BattleRandomRef.create_seeded(21))
	b.setup_sides(
		[{"dex": 1, "level": 50, "ability_id": 9201, "item_id": 9301, "moves": [1]}, {"dex": 1, "level": 50, "ability_id": 9209, "moves": [1]}],
		[{"dex": 2, "level": 50, "ability_id": 9202, "moves": [1]}]
	)
	var ec: Object = b.event_core
	var t0: Object = b.sides[0].call("active_battler")
	var t1: Object = b.sides[1].call("active_battler")
	for idx in range(4):
		var sv: Variant = [EventCoreRef.NULL, EventCoreRef.NOT_FAIL, 0, false][idx]
		var ran2: Array[bool] = [false]
		ec.register_effect("ability:9201", {"id": "ability:9201", "callbacks": {"onS%d" % idx: func(_c): return sv}, "priorities": {"onS%d" % idx: 20}})
		ec.register_effect("item:9301", {"id": "item:9301", "callbacks": {"onS%d" % idx: func(_c): ran2[0] = true; return 5}, "priorities": {"onS%d" % idx: 10}})
		if ec.run_event(b, "S%d" % idx, t0, null, null, 100) != sv or ran2[0]:
			push_error("battle_event_core_test: empty stop failed idx=%d" % idx)
			return false
	ec.register_effect("ability:9201", {"id": "ability:9201", "callbacks": {"onVoid": func(_c): pass, "onPrio": func(_c): return 42}, "priorities": {"onVoid": 20, "onPrio": 20}})
	ec.register_effect("item:9301", {"id": "item:9301", "callbacks": {"onVoid": func(c): return int(c["relay_var"]) + 7, "onPrio": func(_c): return 99}, "priorities": {"onVoid": 10, "onPrio": 10}})
	if int(ec.run_event(b, "Void", t0, null, null, 10)) != 17 or int(ec.priority_event(b, "Prio", t0, null, null, 10)) != 42:
		push_error("battle_event_core_test: void/priority_event failed")
		return false

	# 2. Per-handler ignore_ability on onSourceModifyDamage + Gen 8 attacker self-keep (:366)
	ec.register_effect("ability:9201", {"id": "ability:9201", "breakable": true, "callbacks": {"onModifyDamage": func(c): c["event_core"].chain_modify(c["battle"], 6144, 4096)}})
	ec.register_effect("ability:9202", {"id": "ability:9202", "breakable": true, "callbacks": {"onSourceModifyDamage": func(c): c["event_core"].chain_modify(c["battle"], 2048, 4096)}})
	ec.register_effect("ability:9203", {"id": "ability:9203", "breakable": false, "callbacks": {"onSourceModifyDamage": func(c): c["event_core"].chain_modify(c["battle"], 2048, 4096)}})
	b.active_pokemon = t0
	b.active_move = {"id": 1, "ignore_ability": true}
	var mb1: int = int(ec.run_event(b, "ModifyDamage", t0, t1, b.active_move, 100))
	t1.ability_id = 9203
	var mb2: int = int(ec.run_event(b, "ModifyDamage", t0, t1, b.active_move, 100))
	b.active_pokemon = null
	b.active_move = {}
	if mb1 != 150 or mb2 != 75:
		push_error("battle_event_core_test: ignore_ability onSourceModifyDamage expected 150/75 got %d/%d" % [mb1, mb2])
		return false
	# single_event skips ignored ability & never rounds; ability #76 suppresses weather
	t0.volatiles["cond_380"] = {}
	var se_ran: Array[bool] = [false]
	var se_v: Variant = ec.single_event(b, "Probe", {"id": "ability:9201", "callbacks": {"onProbe": func(_c): se_ran[0] = true; return 50}}, t0.ability_state, t0, null, null, 100)
	t0.volatiles.clear()
	ec.register_effect("weather:1", {"id": "weather:1", "callbacks": {"onWCheck": func(_c): return 5}})
	b.field.weather_id = 1
	t1.ability_id = 76
	var w_sup: Variant = ec.run_event(b, "WCheck", t0, null, null, 10)
	b.field.weather_id = 0
	t1.ability_id = 9203
	if int(se_v) != 100 or se_ran[0] or int(w_sup) != 10:
		push_error("battle_event_core_test: single_event/weather suppression failed")
		return false

	# 3. Ability before item (20/20 runs, 0 speed_tie draws) + special sub_orders (#143/#253 -> 6, #100 -> 9)
	for s in range(1, 21):
		var rng := BattleRandomRef.create_seeded(s)
		rng.record_draws = true
		var bt := _make_test_battle(rng)
		bt.setup_sides([{"dex": 1, "level": 50, "ability_id": 9204, "item_id": 9304, "moves": [1]}], [{"dex": 2, "level": 50, "moves": [1]}])
		var seq: Array[String] = []
		bt.event_core.register_effect("ability:9204", {"id": "ability:9204", "callbacks": {"onTie": func(_c): seq.append("ab")}})
		bt.event_core.register_effect("item:9304", {"id": "item:9304", "callbacks": {"onTie": func(_c): seq.append("it")}})
		bt.event_core.run_event(bt, "Tie", bt.sides[0].call("active_battler"))
		if seq != ["ab", "it"] or rng.draw_log.any(func(d): return str(d.get("draw", "")) == BattleRandomRef.DRAW_SPEED_TIE):
			push_error("battle_event_core_test: ability-before-item failed seed %d" % s)
			return false
	if int(ec.resolve_priority({"effect": {"id": "ability:143"}, "state": {}, "effect_holder": null, "kind": "ability"}, "onHit")["sub_order"]) != 6 \
		or int(ec.resolve_priority({"effect": {"id": "ability:100"}, "state": {}, "effect_holder": null, "kind": "ability"}, "onHit")["sub_order"]) != 9:
		push_error("battle_event_core_test: default sub_order mismatch")
		return false

	# 4. Collection: side onAny, slot condition, unprefixed Update, inactive battler
	var hits: Array[String] = []
	ec.register_effect("sc_any", {"id": "sc_any", "callbacks": {"onAnyCol": func(_c): hits.append("side_any")}})
	ec.register_effect("slot_c", {"id": "slot_c", "callbacks": {"onCol": func(_c): hits.append("slot")}})
	ec.register_effect("ability:9201", {"id": "ability:9201", "callbacks": {"onAnyUpdate": func(_c): hits.append("bad_upd")}})
	ec.register_effect("ability:9209", {"id": "ability:9209", "callbacks": {"onInact": func(_c): hits.append("bad_inact")}})
	b.sides[1].side_conditions["sc_any"] = {"id": "sc_any"}
	b.sides[0].add_slot_condition(0, "slot_c")
	ec.run_event(b, "Col", t0)
	ec.run_event(b, "Update", t0)
	ec.run_event(b, "Inact", b.sides[0].pokemon[1])
	if hits != ["slot", "side_any"]:
		push_error("battle_event_core_test: collection mismatch: %s" % str(hits))
		return false

	# 5. Residual: duration-2 field end once, removed effect skipped, fainted battler gets no later handler
	var rlog: Array[String] = []
	var ends: Array[int] = [0]
	ec.register_effect("pw_d2", {"id": "pw_d2", "residual_order": 1, "callbacks": {"onFieldEnd": func(_c): ends[0] += 1}})
	ec.register_effect("ability:9201", {"id": "ability:9201", "residual_order": 2, "callbacks": {"onResidual": func(c): c["effect_holder"].volatiles.erase("v_stale")}})
	ec.register_effect("v_stale", {"id": "v_stale", "residual_order": 3, "callbacks": {"onResidual": func(_c): rlog.append("bad_stale")}})
	ec.register_effect("ability:9203", {"id": "ability:9203", "residual_order": 4, "callbacks": {"onResidual": func(c): c["effect_holder"].apply_damage(9999)}})
	ec.register_effect("v_after", {"id": "v_after", "residual_order": 5, "callbacks": {"onResidual": func(_c): rlog.append("bad_faint")}})
	b.field.pseudo_weather["pw_d2"] = {"id": "pw_d2", "duration": 2}
	t0.volatiles["v_stale"] = {"id": "v_stale"}
	t1.ability_id = 0
	ec.field_event(b, "Residual")
	if ends[0] != 0 or not rlog.is_empty() or not b.field.pseudo_weather.has("pw_d2"):
		push_error("battle_event_core_test: residual phase 1 failed")
		return false
	t1.ability_id = 9203
	t1.volatiles["v_after"] = {"id": "v_after"}
	ec.field_event(b, "Residual")
	if ends[0] != 1 or b.field.pseudo_weather.has("pw_d2") or not rlog.is_empty() or not b.ended:
		push_error("battle_event_core_test: residual phase 2 failed")
		return false

	# 6. Depth > 8 logs error and returns false
	var bd := _make_test_battle(BattleRandomRef.create_seeded(23))
	bd.setup_sides([{"dex": 1, "level": 50, "ability_id": 9210, "moves": [1]}], [{"dex": 2, "level": 50, "moves": [1]}])
	bd.event_core.register_effect("ability:9210", {"id": "ability:9210", "callbacks": {"onRec": func(c): return c["event_core"].run_event(c["battle"], "Rec", c["target"])}})
	var dret: Variant = bd.event_core.run_event(bd, "Rec", bd.sides[0].call("active_battler"))
	if not (dret is bool and dret == false) or bd.event_core.last_depth_error != "EventCore: event depth over 8: Rec":
		push_error("battle_event_core_test: depth guard failed")
		return false

	# 7. damage.gd: cond_380 on burned #62 halves physical damage (74 -> 37), #185 hit 2 (18), defense==0 (4)
	var bdm := _make_test_battle(BattleRandomRef.create_policy({"accuracy_mode": "always", "crit_mode": "never", "damage_roll": 100, "speed_tie": 0}))
	bdm.setup_sides([{"dex": 1, "level": 50, "ability_id": 62, "status": StatsRef.STATUS_BRN, "moves": [1]}], [{"dex": 2, "level": 50, "moves": [1]}])
	var da: Object = bdm.sides[0].call("active_battler")
	var dd: Object = bdm.sides[1].call("active_battler")
	var mv := {"id": 1, "type": "fighting", "damage_class": "physical", "power": 80, "accuracy": 100, "meta": {"crit_rate": 0}}
	var d1: int = int(DamageRef.get_damage(bdm, da, dd, mv, false, 100)["damage"])
	da.volatiles["cond_380"] = {}
	var d2: int = int(DamageRef.get_damage(bdm, da, dd, mv, false, 100)["damage"])
	da.volatiles.clear()
	da.status = StatsRef.STATUS_NONE
	var mv2 := mv.duplicate(true)
	mv2["multihit_ability_id"] = 185
	mv2["hit"] = 2
	var d3: int = int(DamageRef.get_damage(bdm, da, dd, mv2, false, 100)["damage"])
	bdm.event_core.register_effect("ability:9211", {"id": "ability:9211", "callbacks": {"onModifyDef": func(_c): return 0}})
	dd.ability_id = 9211
	var d4: int = int(DamageRef.get_damage(bdm, da, dd, mv, false, 100)["damage"])
	if d1 != 74 or d2 != 37 or d3 != 18 or d4 != 4:
		push_error("battle_event_core_test: damage fixes expected 74/37/18/4 got %d/%d/%d/%d" % [d1, d2, d3, d4])
		return false
	return true
