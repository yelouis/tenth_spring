extends RefCounted

# Injected randomness seam with named draws (Decision 85 / §6.6).
# Play uses SeededBattleRandom; parity and unit tests pass PolicyBattleRandom.

const DRAW_ACCURACY: String = "accuracy"
const DRAW_CRIT: String = "crit"
const DRAW_DAMAGE_ROLL: String = "damage_roll"
const DRAW_SECONDARY: String = "secondary"
const DRAW_MULTIHIT: String = "multihit"
const DRAW_SPEED_TIE: String = "speed_tie"
const DRAW_SLEEP_TURNS: String = "sleep_turns"
const DRAW_CONFUSION_TURNS: String = "confusion_turns"
const DRAW_CONFUSION_SELF_HIT: String = "confusion_self_hit"
const DRAW_PARALYSIS: String = "paralysis"
const DRAW_THAW: String = "thaw"
const DRAW_FLINCH: String = "flinch"
const DRAW_QUICK_CLAW: String = "quick_claw"
const DRAW_FOCUS_BAND: String = "focus_band"
const DRAW_ESCAPE: String = "escape"
const DRAW_CATCH_SHAKE: String = "catch_shake"
const DRAW_CRIT_CAPTURE: String = "crit_capture"

var mode: String = "seeded"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var policy: Dictionary = {}
var draw_log: Array[Dictionary] = []
var record_draws: bool = false
var unforced_draws: Array[String] = []


func _record_unforced(draw_name: String) -> void:
	unforced_draws.append(draw_name)
	push_error("BattleRandom: unforced draw %s in policy mode" % draw_name)


static func create_seeded(seed_val: int) -> RefCounted:
	var scr: GDScript = load("res://battle/battle_random.gd") as GDScript
	var inst: RefCounted = scr.new()
	inst.mode = "seeded"
	inst._rng.seed = seed_val
	return inst


static func create_policy(pol: Dictionary) -> RefCounted:
	var scr: GDScript = load("res://battle/battle_random.gd") as GDScript
	var inst: RefCounted = scr.new()
	inst.mode = "policy"
	inst.policy = pol.duplicate(true)
	inst._rng.seed = int(pol.get("seed", 1))
	return inst


func random_int(draw_name: String, min_val: int, max_val: int) -> int:
	var result: int = min_val
	if mode == "policy":
		if draw_name == DRAW_DAMAGE_ROLL and policy.has("damage_roll"):
			result = clampi(int(policy["damage_roll"]), min_val, max_val)
		elif policy.has(draw_name):
			result = clampi(int(policy[draw_name]), min_val, max_val)
		else:
			_record_unforced(draw_name)
			result = _rng.randi_range(min_val, max_val)
	else:
		result = _rng.randi_range(min_val, max_val)
	if record_draws:
		draw_log.append({"draw": draw_name, "kind": "int", "min": min_val, "max": max_val, "val": result})
	return result


func random_chance(draw_name: String, numerator: int, denominator: int) -> bool:
	if denominator <= 0:
		return false
	if numerator >= denominator:
		return true
	if numerator <= 0:
		return false
	var result: bool = false
	if mode == "policy":
		if draw_name == DRAW_ACCURACY and policy.has("accuracy_mode"):
			var am: String = str(policy["accuracy_mode"])
			if am == "always":
				result = true
			elif am == "never":
				result = false
			else:
				_record_unforced(draw_name)
				result = _rng.randi_range(0, denominator - 1) < numerator
		elif draw_name == DRAW_CRIT and policy.has("crit_mode"):
			var cm: String = str(policy["crit_mode"])
			if cm == "always":
				result = true
			elif cm == "never":
				result = false
			else:
				_record_unforced(draw_name)
				result = _rng.randi_range(0, denominator - 1) < numerator
		elif policy.has("all_chances"):
			var ac: String = str(policy["all_chances"])
			result = (ac == "pass" or ac == "always")
		else:
			_record_unforced(draw_name)
			result = _rng.randi_range(0, denominator - 1) < numerator
	else:
		result = _rng.randi_range(0, denominator - 1) < numerator
	if record_draws:
		draw_log.append({"draw": draw_name, "kind": "chance", "num": numerator, "den": denominator, "val": result})
	return result


func damage_roll() -> int:
	return random_int(DRAW_DAMAGE_ROLL, 85, 100)


func shuffle_slice(draw_name: String, list: Array, start_idx: int, end_idx: int) -> void:
	var count: int = end_idx - start_idx
	if count <= 1:
		return
	if mode == "policy" and draw_name == DRAW_SPEED_TIE and policy.has("speed_tie"):
		var tie_pref: int = int(policy["speed_tie"])
		var sub: Array = []
		for i in range(start_idx, end_idx):
			sub.append(list[i])
		sub.sort_custom(func(a, b):
			var sa: int = _extract_side_index(a)
			var sb: int = _extract_side_index(b)
			if tie_pref == 1:
				return sa > sb
			return sa < sb
		)
		for i in range(count):
			list[start_idx + i] = sub[i]
		if record_draws:
			draw_log.append({"draw": draw_name, "kind": "shuffle_policy", "pref": tie_pref, "count": count})
		return
	if mode == "policy":
		_record_unforced(draw_name)

	# Standard Fisher-Yates shuffle matching Showdown sim/prng.ts
	var cur_start: int = start_idx
	while cur_start < end_idx - 1:
		var next_idx: int = _rng.randi_range(cur_start, end_idx - 1)
		if cur_start != next_idx:
			var tmp: Variant = list[cur_start]
			list[cur_start] = list[next_idx]
			list[next_idx] = tmp
		cur_start += 1
	if record_draws:
		draw_log.append({"draw": draw_name, "kind": "shuffle_seeded", "count": count})


static func _extract_side_index(item: Variant) -> int:
	if item is Dictionary:
		if item.has("side_idx"):
			return int(item["side_idx"])
		if item.has("side") and item["side"] is int:
			return int(item["side"])
		var target_obj: Variant = item.get("effect_holder", item.get("pokemon", null))
		if target_obj is Object and target_obj.get("side") != null:
			var s_obj: Variant = target_obj.get("side")
			if s_obj is Object:
				return int(s_obj.get("id"))
	elif item is Object:
		if item.get("side") != null:
			var s2: Variant = item.get("side")
			if s2 is Object:
				return int(s2.get("id"))
		if item.get("id") is int:
			return int(item.get("id"))
	return 0
