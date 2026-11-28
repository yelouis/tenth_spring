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
	# 60 -> poke_round(60, 6144) = 90 -> poke_round(90, 4915) = 108
	var bp: int = int(ev_core.run_event(b, "BasePower", t, null, null, 60))
	if bp != 108:
		push_error("battle_event_core_test: run_event chain_modify expected 108 got %d" % bp)
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

	# 2. With ability #104 active on attacker, breakable ability is suppressed (only item 1.5x applies -> 150)
	b.active_pokemon = attacker
	var def_suppressed: int = int(ev_core.run_event(b, "ModifyDef", defender, attacker, null, 100))
	b.active_pokemon = null
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
	b.event_core.residual_event(b)
	if res_log != ["first", "second"]:
		push_error("battle_event_core_test: residualOrder mismatch: %s" % str(res_log))
		return false
	return true
