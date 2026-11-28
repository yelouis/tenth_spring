# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Accuracy step and Gen 8 damage pipeline translated from
# pokemon-showdown@0.11.11 sim/battle-actions.ts:690-750 (hitStepAccuracy),
# :1585-1723 (getDamage), and :1724-1835 (modifyDamage).

const StatsRef := preload("res://creatures/stats.gd")
const BattleRandomRef := preload("res://battle/battle_random.gd")
const EventCoreRef := preload("res://battle/event_core.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")


static func hit_step_accuracy(
	battle: Object,
	attacker: Object,
	defender: Object,
	move: Dictionary
) -> bool:
	var event_core: Object = battle.get("event_core")
	var rng: Object = battle.get("rng")
	var acc: Variant = true
	var raw_acc: int = int(move.get("accuracy", 0))
	var is_ohko: bool = bool(move.get("ohko", false))

	if is_ohko:
		var base_ohko: int = 30
		if str(move.get("ohko_type", "")).to_lower() == "ice" and not bool(attacker.call("has_type", "ice")):
			base_ohko = 20
		var atk_lvl: int = int(attacker.get("level"))
		var def_lvl: int = int(defender.get("level"))
		if atk_lvl < def_lvl:
			return false
		var ohko_type: String = str(move.get("ohko_type", "")).to_lower()
		if ohko_type != "" and bool(defender.call("has_type", ohko_type)):
			return false
		acc = base_ohko + (atk_lvl - def_lvl)
	else:
		acc = true if raw_acc == 0 else raw_acc
		acc = event_core.run_event(battle, "ModifyAccuracy", defender, attacker, move, acc)
		if not (acc is bool):
			var boost: int = 0
			if not bool(move.get("ignore_accuracy", false)):
				var a_boosts: Dictionary = (attacker.get("boosts") as Dictionary).duplicate()
				var mod_a: Variant = event_core.run_event(battle, "ModifyBoost", attacker, null, null, a_boosts)
				if mod_a is Dictionary:
					a_boosts = mod_a
				boost = StatsRef.clamp_int(int(a_boosts.get("accuracy", 0)), -6, 6)
			if not bool(move.get("ignore_evasion", false)):
				var d_boosts: Dictionary = (defender.get("boosts") as Dictionary).duplicate()
				var mod_d: Variant = event_core.run_event(battle, "ModifyBoost", defender, null, null, d_boosts)
				if mod_d is Dictionary:
					d_boosts = mod_d
				boost = StatsRef.clamp_int(boost - int(d_boosts.get("evasion", 0)), -6, 6)
			acc = StatsRef.apply_accuracy_stage(int(acc), boost)

	var mid: int = int(move.get("id", 0))
	var always_hit: bool = bool(move.get("always_hit", false))
	var is_poison_m92: bool = (mid == 92 and bool(attacker.call("has_type", "poison")))
	var is_self_status: bool = (
		str(move.get("target", "")) == "self"
		and str(move.get("damage_class", "")).to_lower() == "status"
	)
	if always_hit or is_poison_m92 or is_self_status:
		acc = true
	else:
		acc = event_core.run_event(battle, "Accuracy", defender, attacker, move, acc)

	if acc is bool:
		return bool(acc)
	return bool(rng.random_chance(BattleRandomRef.DRAW_ACCURACY, int(acc), 100))


static func get_damage(
	battle: Object,
	source: Object,
	target: Object,
	move: Dictionary,
	forced_crit: Variant = null,
	forced_roll: int = -1
) -> Dictionary:
	var event_core: Object = battle.get("event_core")
	var rng: Object = battle.get("rng")

	if not bool(target.call("run_immunity", move)):
		return {"immune": true, "damage": 0, "crit": false, "type_mod": 0}

	var base_power: int = int(move.get("power", 0))
	if base_power <= 0:
		return {"immune": false, "damage": 0, "crit": false, "type_mod": 0}
	base_power = maxi(1, base_power)

	# Crit calculation (sim/battle-actions.ts:1623-1645; Gen 8 1-indexed critRatio)
	var meta: Dictionary = move.get("meta", {})
	var base_crit_ratio: int = 1 + int(meta.get("crit_rate", 0))
	var crit_ratio: int = int(event_core.run_event(battle, "ModifyCritRatio", source, target, move, base_crit_ratio))
	crit_ratio = StatsRef.clamp_int(crit_ratio, 0, 4)
	var crit_mult: Array[int] = [0, 24, 8, 2, 1]

	var is_crit: bool = false
	if forced_crit is bool:
		is_crit = bool(forced_crit)
	elif bool(move.get("will_crit", false)):
		is_crit = true
	elif crit_ratio > 0:
		is_crit = bool(rng.random_chance(BattleRandomRef.DRAW_CRIT, 1, crit_mult[crit_ratio]))

	if is_crit:
		var ch_res: Variant = event_core.run_event(battle, "CriticalHit", target, null, move, true)
		if ch_res is bool and not bool(ch_res):
			is_crit = false

	# BasePower event runs AFTER crit calculation (sim/battle-actions.ts:1648)
	var bp_res: Variant = event_core.run_event(battle, "BasePower", source, target, move, base_power, true)
	if bp_res is bool and not bool(bp_res):
		return {"immune": false, "damage": 0, "crit": is_crit, "type_mod": 0}
	base_power = maxi(1, int(bp_res))

	var level: int = int(source.get("level"))
	var attacker: Object = target if str(move.get("override_offensive_pokemon", "")) == "target" else source
	var defender: Object = source if str(move.get("override_defensive_pokemon", "")) == "source" else target

	var is_phys: bool = str(move.get("damage_class", "physical")).to_lower() == "physical"
	var atk_stat: String = str(move.get("override_offensive_stat", "atk" if is_phys else "spa"))
	var def_stat: String = str(move.get("override_defensive_stat", "def" if is_phys else "spd"))

	var atk_boost: int = int((attacker.get("boosts") as Dictionary).get(atk_stat, 0))
	var def_boost: int = int((defender.get("boosts") as Dictionary).get(def_stat, 0))

	var ignore_neg_off: bool = bool(move.get("ignore_negative_offensive", false)) or is_crit
	var ignore_pos_def: bool = bool(move.get("ignore_positive_defensive", false)) or is_crit
	if bool(move.get("ignore_offensive", false)) or (ignore_neg_off and atk_boost < 0):
		atk_boost = 0
	if bool(move.get("ignore_defensive", false)) or (ignore_pos_def and def_boost > 0):
		def_boost = 0

	var attack: int = int(attacker.call("calculate_stat", atk_stat, atk_boost))
	var defense: int = int(defender.call("calculate_stat", def_stat, def_boost))

	var atk_ev: String = "ModifyAtk" if is_phys else "ModifySpA"
	var def_ev: String = "ModifyDef" if def_stat == "def" else "ModifySpD"
	attack = maxi(1, int(event_core.run_event(battle, atk_ev, source, target, move, attack)))
	defense = maxi(1, int(event_core.run_event(battle, def_ev, target, source, move, defense)))

	# Base damage (sim/battle-actions.ts:1718): tr(tr(tr(tr(2 * L / 5 + 2) * P * A) / D) / 50)
	var base_damage: int = (((((2 * level) / 5 + 2) * base_power * attack) / defense) / 50)
	return modify_damage(battle, base_damage, source, target, move, is_crit, forced_roll)


static func modify_damage(
	battle: Object,
	base_damage: int,
	source: Object,
	target: Object,
	move: Dictionary,
	is_crit: bool,
	forced_roll: int = -1
) -> Dictionary:
	var event_core: Object = battle.get("event_core")
	var rng: Object = battle.get("rng")
	var move_type: String = str(move.get("type", "???")).to_lower()
	var dmg: int = base_damage + 2

	# Ability #185 2nd hit runs before weather (sim/battle-actions.ts:1737-1741)
	if str(move.get("multihit_type", "")) == "parentalbond" and int(move.get("hit", 1)) > 1:
		dmg = EventCoreRef.poke_round(dmg, 1024)

	# Weather modifier (sim/battle-actions.ts:1745)
	dmg = int(event_core.priority_event(battle, "WeatherModifyDamage", source, target, move, dmg))

	# Critical hit: Gen 6-8 1.5x (sim/battle-actions.ts:1751)
	if is_crit:
		dmg = (dmg * 3) / 2

	# Random roll 85..100 (sim/battle-actions.ts:1755)
	var roll: int = forced_roll if (forced_roll >= 85 and forced_roll <= 100) else int(rng.damage_roll())
	dmg = (dmg * roll) / 100

	# STAB (sim/battle-actions.ts:1761-1790)
	if move_type != "???":
		var is_stab: bool = bool(move.get("force_stab", false)) or bool(source.call("has_type", move_type))
		var stab4096: int = 6144 if is_stab else 4096
		stab4096 = int(event_core.run_event(battle, "ModifySTAB", source, target, move, stab4096))
		dmg = EventCoreRef.poke_round(dmg, stab4096)

	# Type effectiveness (sim/battle-actions.ts:1793-1806)
	var type_mod: int = StatsRef.clamp_int(int(target.call("run_effectiveness", move)), -6, 6)
	if type_mod > 0:
		for _i in range(type_mod):
			dmg *= 2
	elif type_mod < 0:
		for _i in range(-type_mod):
			dmg = dmg / 2

	# Burn physical halving (sim/battle-actions.ts:1810-1814; bypassed by ability #62 and move #263)
	var is_phys: bool = str(move.get("damage_class", "physical")).to_lower() == "physical"
	if int(source.get("status")) == StatsRef.STATUS_BRN and is_phys:
		if int(source.get("ability_id")) != 62 and int(move.get("id", 0)) != 263:
			dmg = EventCoreRef.poke_round(dmg, 2048)

	# Final modifiers (sim/battle-actions.ts:1820)
	dmg = int(event_core.run_event(battle, "ModifyDamage", source, target, move, dmg))

	# Floor clamp to 1 unless immune, then 16-bit truncation (sim/battle-actions.ts:1833-1841)
	if dmg == 0:
		dmg = 1
	dmg = StatsRef.trunc_int(dmg, 16)

	# Tenth Spring Place Field Effect overlay (OFF during all Showdown parity runs)
	if bool(battle.get("field_effects_enabled")):
		var fmod: int = int(battle.call("get_place_field_mod_4096", move_type))
		if fmod != 4096:
			dmg = maxi(1, EventCoreRef.poke_round(dmg, fmod))

	return {"immune": false, "damage": dmg, "crit": is_crit, "type_mod": type_mod}


static func calc_all_16_rolls(
	battle: Object,
	source: Object,
	target: Object,
	move: Dictionary,
	is_crit: bool = false
) -> Array[int]:
	var out: Array[int] = []
	for roll in range(85, 101):
		var res := get_damage(battle, source, target, move, is_crit, roll)
		out.append(int(res["damage"]))
	return out
