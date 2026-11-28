# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Battle state & Slice 1 minimal turn/move runner mirroring
# pokemon-showdown@0.11.11 sim/battle.ts & sim/battle-actions.ts.

const RulesRef := preload("res://battle/rules.gd")
const BattleRandomRef := preload("res://battle/battle_random.gd")
const EventCoreRef := preload("res://battle/event_core.gd")
const ActionQueueRef := preload("res://battle/action_queue.gd")
const DamageRef := preload("res://battle/damage.gd")
const FieldStateRef := preload("res://battle/state/field_state.gd")
const SideStateRef := preload("res://battle/state/side_state.gd")
const BattlerStateRef := preload("res://battle/state/battler_state.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")

var gen: int = 8
var turn: int = 0
var sides: Array = []
var field: RefCounted = null
var queue: RefCounted = null
var rng: RefCounted = null
var event_core: RefCounted = null

var active_pokemon: Object = null
var active_target: Object = null
var active_move: Dictionary = {}
var event: Dictionary = {}
var event_depth: int = 0
var _effect_order: int = 0
var last_move: Dictionary = {}
var last_successful_move_this_turn: int = 0
var ended: bool = false
var winner: int = -1

# Tenth Spring overlay switches (OFF during Showdown parity scenarios)
var field_effects_enabled: bool = false
var place_field_id: String = ""
var in_distortion_field: bool = false

var _species_lookup: Callable = Callable()
var _move_lookup: Callable = Callable()
var _cache_dir: String = AssetDBRef.DEFAULT_CACHE_DIR


func _init(random_source: RefCounted = null, cache_dir: String = AssetDBRef.DEFAULT_CACHE_DIR, custom_species_lookup: Callable = Callable(), custom_move_lookup: Callable = Callable()) -> void:
	_cache_dir = cache_dir
	rng = random_source if random_source != null else BattleRandomRef.create_seeded(1)
	event_core = EventCoreRef.new()
	queue = ActionQueueRef.new()
	field = FieldStateRef.new()
	_species_lookup = custom_species_lookup if custom_species_lookup.is_valid() else Callable(self, "_default_species_lookup")
	_move_lookup = custom_move_lookup if custom_move_lookup.is_valid() else Callable(self, "_default_move_lookup")


func _default_species_lookup(dex: int) -> Dictionary:
	return AssetDBRef.species(dex, "", _cache_dir)


func _default_move_lookup(move_id: int) -> Dictionary:
	return AssetDBRef.move(move_id, _cache_dir)


func setup_sides(side0_specs: Array, side1_specs: Array) -> void:
	sides.clear()
	turn = 0
	ended = false
	winner = -1
	_effect_order = 0
	var s0 := SideStateRef.new()
	var s1 := SideStateRef.new()
	sides = [s0, s1]
	s0.setup(0, self, side0_specs, _species_lookup, _move_lookup)
	s1.setup(1, self, side1_specs, _species_lookup, _move_lookup)


func next_effect_order() -> int:
	_effect_order += 1
	return _effect_order


func suppressing_ability(target: Variant = null) -> bool:
	if active_pokemon == null or active_pokemon == target:
		return false
	if bool(active_move.get("ignore_ability", false)):
		return true
	var aid: int = int(active_pokemon.get("ability_id"))
	if (aid == 104 or aid == 163 or aid == 164) and not bool(active_pokemon.call("ignoring_ability")):
		return true
	return false


func is_ability_active_on_field(target_ability_id: int) -> bool:
	for s in sides:
		for b in s.get("active"):
			if b != null and not bool(b.get("fainted")) and int(b.get("ability_id")) == target_ability_id:
				return true
	return false


func get_place_field_mod_4096(_move_type: String) -> int:
	# Place field modifiers arrive in Slice 13; neutral 4096 in Slice 1.
	return 4096


func parse_choice(side_idx: int, choice_str: String) -> Dictionary:
	var s: Object = sides[side_idx]
	var pkmn: Object = s.call("active_battler")
	var parts := choice_str.strip_edges().split(" ", false)
	if parts.size() >= 2 and parts[0] == "move":
		var slot_1based: int = int(parts[1])
		var moves_arr: Array = pkmn.get("moves")
		var m_slot: Dictionary = moves_arr[clampi(slot_1based - 1, 0, moves_arr.size() - 1)]
		var mid: int = int(m_slot["move_id"])
		var mdata: Dictionary = _move_lookup.call(mid)
		return {
			"choice": "move",
			"pokemon": pkmn,
			"side_idx": side_idx,
			"move_slot": slot_1based - 1,
			"move": mdata,
		}
	return {"choice": "pass", "pokemon": pkmn, "side_idx": side_idx}


func run_turn(choice_s0: String, choice_s1: String) -> Dictionary:
	# Minimal Slice 1 turn execution path:
	# resolve choices -> ActionQueue speedSort -> execute move actions
	# (accuracy -> damage -> HP loss -> faint check) -> Residual -> end-of-turn snapshot.
	turn += 1
	last_successful_move_this_turn = 0
	for s in sides:
		s.set("fainted_last_turn", bool(s.get("fainted_this_turn")))
		s.set("fainted_this_turn", false)
		var b: Object = s.call("active_battler")
		if b != null:
			b.set("hurt_this_turn", 0)
			b.set("move_this_turn", 0)
			b.call("update_speed")

	queue.clear()
	var a0 := parse_choice(0, choice_s0)
	var a1 := parse_choice(1, choice_s1)
	queue.add_choices(self, event_core, [a0, a1])

	var action_order: Array[Dictionary] = []
	while not queue.is_empty():
		if ended:
			break
		var act: Dictionary = queue.shift()
		if str(act.get("choice", "")) == "move":
			var rec := _execute_slice1_move(act)
			if not rec.is_empty():
				action_order.append(rec)
			_check_win()

	if not ended:
		event_core.residual_event(self)
		_check_win()

	return {
		"turn": turn,
		"action_order": action_order,
		"sides": [sides[0].call("snapshot"), sides[1].call("snapshot")],
		"field": field.call("snapshot"),
		"ended": ended,
		"winner": winner,
	}


func _execute_slice1_move(act: Dictionary) -> Dictionary:
	var user: Object = act.get("pokemon", null)
	if user == null or bool(user.get("fainted")):
		return {}
	var u_side: Object = user.get("side")
	var foe_s: Object = u_side.call("foe_side")
	var target: Object = foe_s.call("active_battler")
	if target == null or bool(target.get("fainted")):
		return {}

	var move: Dictionary = (act.get("move", {}) as Dictionary).duplicate(true)
	var mid: int = int(move.get("id", 0))
	var m_slot: int = int(act.get("move_slot", 0))
	var user_moves: Array = user.get("moves")
	if m_slot >= 0 and m_slot < user_moves.size():
		var slot_dict: Dictionary = user_moves[m_slot]
		slot_dict["pp"] = maxi(0, int(slot_dict["pp"]) - 1)

	active_pokemon = user
	active_target = target
	active_move = move
	user.set("move_this_turn", mid)
	user.set("last_move_used", mid)

	var rec := {
		"side": int(u_side.get("id")),
		"kind": "move",
		"move_id": mid,
		"hit": true,
		"crit": false,
		"immune": false,
	}

	# 1. Type immunity runs before accuracy in Showdown (sim/battle-actions.ts tryMoveHit -> hitStepTypeImmunity)
	if not bool(target.call("run_immunity", move)):
		rec["immune"] = true
		active_pokemon = null
		active_target = null
		active_move = {}
		return rec

	# 2. Accuracy check
	var hit_ok: bool = DamageRef.hit_step_accuracy(self, user, target, move)
	if not hit_ok:
		rec["hit"] = false
		active_pokemon = null
		active_target = null
		active_move = {}
		return rec

	# 3. Damage calculation & HP deduction
	var dmg_res: Dictionary = DamageRef.get_damage(self, user, target, move)
	rec["immune"] = bool(dmg_res["immune"])
	rec["crit"] = bool(dmg_res["crit"])
	if not rec["immune"]:
		var dealt: int = int(target.call("apply_damage", int(dmg_res["damage"])))
		if dealt > 0 and rec["crit"]:
			user.set("crits_landed_this_battle", int(user.get("crits_landed_this_battle")) + 1)
		last_move = move
		last_successful_move_this_turn = mid

	active_pokemon = null
	active_target = null
	active_move = {}
	return rec


func _check_win() -> void:
	var s0_alive: bool = bool(sides[0].call("has_living_pokemon"))
	var s1_alive: bool = bool(sides[1].call("has_living_pokemon"))
	if not s0_alive and not s1_alive:
		ended = true
		winner = -1
	elif not s1_alive:
		ended = true
		winner = 0
	elif not s0_alive:
		ended = true
		winner = 1
