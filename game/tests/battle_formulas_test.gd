extends Node

# Unit & Oracle Verification Tests for Slice 1 (Item 94):
# - game/config/battle_rules.json + game/battle/rules.gd
# - game/creatures/stats.gd (HP, stats, 25 natures, stages, action speed)
# - all 324 type-chart cells + dual-type multipliers
# - synthetic accuracy & damage pipeline tests (run everywhere, incl. CI)
# - all 320 @smogon/calc@0.12.0 Gen 8 vectors x 16 rolls (exact match when data cache present)

const RulesRef := preload("res://battle/rules.gd")
const StatsRef := preload("res://creatures/stats.gd")
const BattleRandomRef := preload("res://battle/battle_random.gd")
const EventCoreRef := preload("res://battle/event_core.gd")
const BattleStateRef := preload("res://battle/state/battle_state.gd")
const BattlerStateRef := preload("res://battle/state/battler_state.gd")
const DamageRef := preload("res://battle/damage.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")

const VECTORS_PATH: String = "res://tests/fixtures/battle_damage_vectors_gen8.json"


func run_test() -> bool:
	if not _test_rules_config():
		return false
	if not _test_stats_natures_stages():
		return false
	if not _test_type_chart_324_cells():
		return false
	if not _test_synthetic_damage_and_accuracy():
		return false
	if not _test_calc_vectors_fixture():
		return false
	return true


func _test_rules_config() -> bool:
	RulesRef.clear_cache()
	var rules := RulesRef.load_rules()
	if rules.is_empty():
		push_error("battle_formulas_test: failed to load battle_rules.json")
		return false
	if RulesRef.get_int("B_TYPE_CHART_GEN") != 8:
		push_error("battle_formulas_test: B_TYPE_CHART_GEN != 8")
		return false
	if RulesRef.get_int("B_CRIT_MULTIPLIER_4096") != 6144:
		push_error("battle_formulas_test: B_CRIT_MULTIPLIER_4096 != 6144")
		return false
	var denoms := RulesRef.get_int_array("B_CRIT_CHANCE_DENOMS")
	if denoms != [0, 24, 8, 2, 1]:
		push_error("battle_formulas_test: B_CRIT_CHANCE_DENOMS mismatch: %s" % str(denoms))
		return false
	if RulesRef.get_int("B_BURN_DAMAGE_DIVISOR") != 16:
		push_error("battle_formulas_test: B_BURN_DAMAGE_DIVISOR != 16")
		return false
	if RulesRef.get_int("B_SHINY_DENOM") != 4096 or RulesRef.get_int("B_DUSK_BALL_MULT_4096") != 12288:
		push_error("battle_formulas_test: Gen 8 shiny/ball rule mismatch")
		return false
	if RulesRef.get_bool("B_ZMOVE", true) or RulesRef.get_bool("B_DYNAMAX", true) or RulesRef.get_bool("B_PRIMAL", true):
		push_error("battle_formulas_test: forbidden gimmicks must be false")
		return false
	if not RulesRef.get_bool("B_MEGA_EVOLUTION", false):
		push_error("battle_formulas_test: B_MEGA_EVOLUTION must be true")
		return false
	return true


func _test_stats_natures_stages() -> bool:
	# HP formula incl. base_hp == 1 / dex == 292 special rule
	if StatsRef.calc_hp(1, 31, 252, 100, 292) != 1:
		push_error("battle_formulas_test: dex 292 HP must be 1")
		return false
	if StatsRef.calc_hp(100, 31, 252, 100, 0) != 404:
		push_error("battle_formulas_test: base 100 L100 max HP expected 404")
		return false
	if StatsRef.calc_hp(100, 31, 0, 50, 0) != 175:
		push_error("battle_formulas_test: base 100 L50 0-EV HP expected 175")
		return false

	# All 25 natures: 5 neutral (0, 6, 12, 18, 24) and 20 boosting/hindering
	var neutral_count: int = 0
	for nid in range(25):
		var inc_cnt: int = 0
		var dec_cnt: int = 0
		for sk in ["atk", "def", "spe", "spa", "spd"]:
			var m: int = StatsRef.nature_modifier_num(nid, sk)
			if m == 11:
				inc_cnt += 1
			elif m == 9:
				dec_cnt += 1
			elif m != 10:
				push_error("battle_formulas_test: invalid nature mod %d" % m)
				return false
		if inc_cnt == 0 and dec_cnt == 0:
			neutral_count += 1
		elif inc_cnt != 1 or dec_cnt != 1:
			push_error("battle_formulas_test: nature %d unbalanced" % nid)
			return false
	if neutral_count != 5:
		push_error("battle_formulas_test: expected 5 neutral natures, got %d" % neutral_count)
		return false

	# Non-HP stat check (base 130, 31 IV, 252 EV, L50, nature 15 (+spa -atk))
	var spa_boosted: int = StatsRef.calc_stat(130, 31, 252, 50, 15, "spa")
	var atk_hindered: int = StatsRef.calc_stat(130, 31, 0, 50, 15, "atk")
	if spa_boosted != 200 or atk_hindered != 135:
		push_error("battle_formulas_test: stat calc mismatch spa=%d atk=%d" % [spa_boosted, atk_hindered])
		return false

	# Stages -6..+6
	var expected_stages := {
		-6: 25, -5: 28, -4: 33, -3: 40, -2: 50, -1: 66,
		0: 100, 1: 150, 2: 200, 3: 250, 4: 300, 5: 350, 6: 400,
	}
	for s in expected_stages.keys():
		var got: int = StatsRef.apply_stage(100, int(s))
		if got != int(expected_stages[s]):
			push_error("battle_formulas_test: stage %d expected %d got %d" % [int(s), int(expected_stages[s]), got])
			return false

	# Accuracy stages
	if StatsRef.apply_accuracy_stage(80, 1) != 106 or StatsRef.apply_accuracy_stage(80, -1) != 60:
		push_error("battle_formulas_test: accuracy stage truncation mismatch")
		return false

	# Action speed + cond_433 reversed-speed 13-bit wrap
	if StatsRef.calc_action_speed(100, false) != 100:
		push_error("battle_formulas_test: action speed normal mismatch")
		return false
	if StatsRef.calc_action_speed(100, true) != (9900 & 0x1FFF):
		push_error("battle_formulas_test: action speed reversed-speed mismatch")
		return false
	if StatsRef.calc_action_speed(1809, true) != ((10000 - 1809) & 0x1FFF):
		push_error("battle_formulas_test: action speed reversed-speed overflow mismatch")
		return false

	return true


func _test_type_chart_324_cells() -> bool:
	var doc := AssetDBRef.type_chart()
	var types_arr: Array = doc.get("types", [])
	var matrix: Dictionary = doc.get("effectiveness", {})
	if types_arr.size() != 18:
		push_error("battle_formulas_test: expected 18 types, got %d" % types_arr.size())
		return false
	var cell_count: int = 0
	for atk_t in types_arr:
		var atk_s := str(atk_t)
		if not matrix.has(atk_s):
			push_error("battle_formulas_test: missing attack type row %s" % atk_s)
			return false
		var row: Dictionary = matrix[atk_s]
		for def_t in types_arr:
			var def_s := str(def_t)
			if not row.has(def_s):
				push_error("battle_formulas_test: missing cell %s -> %s" % [atk_s, def_s])
				return false
			var v: float = float(row[def_s])
			if not (is_equal_approx(v, 0.0) or is_equal_approx(v, 0.5) or is_equal_approx(v, 1.0) or is_equal_approx(v, 2.0)):
				push_error("battle_formulas_test: invalid cell value %s -> %s = %s" % [atk_s, def_s, str(v)])
				return false
			if not is_equal_approx(AssetDBRef.type_effectiveness(atk_s, [def_s]), v):
				push_error("battle_formulas_test: AssetDB.type_effectiveness mismatch on %s -> %s" % [atk_s, def_s])
				return false
			cell_count += 1
	if cell_count != 324:
		push_error("battle_formulas_test: expected 324 cells, checked %d" % cell_count)
		return false

	# Gen 6-8 specific assertions
	if not is_equal_approx(AssetDBRef.type_effectiveness("ghost", ["steel"]), 1.0):
		push_error("battle_formulas_test: Ghost vs Steel must be 1.0 in Gen 8")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("dark", ["steel"]), 1.0):
		push_error("battle_formulas_test: Dark vs Steel must be 1.0 in Gen 8")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("fairy", ["dragon", "dark"]), 4.0):
		push_error("battle_formulas_test: Fairy vs Dragon/Dark must be 4.0")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("dragon", ["fairy"]), 0.0):
		push_error("battle_formulas_test: Dragon vs Fairy must be 0.0")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("normal", ["ghost"]), 0.0):
		push_error("battle_formulas_test: Normal vs Ghost must be 0.0")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("grass", ["fire", "flying"]), 0.25):
		push_error("battle_formulas_test: Grass vs Fire/Flying must be 0.25")
		return false
	if not is_equal_approx(AssetDBRef.type_effectiveness("water", ["water"]), 0.5):
		push_error("battle_formulas_test: Water vs Water must be 0.5")
		return false
	return true


func _test_synthetic_damage_and_accuracy() -> bool:
	# Pure synthetic stats (no PokéAPI data needed; runs on CI and Mac)
	# Verify poke_round round-half-down at exact .5 boundary: 3 * 6144 = 18432 -> 4.5 -> 4 (NOT 5!)
	if EventCoreRef.poke_round(3, 6144) != 4:
		push_error("battle_formulas_test: poke_round(3, 6144) must round half down to 4")
		return false
	if EventCoreRef.poke_round(1, 2048) != 0:
		push_error("battle_formulas_test: poke_round(1, 2048) must round half down to 0")
		return false
	if EventCoreRef.poke_round(10, 4915) != 12:
		push_error("battle_formulas_test: poke_round(10, 4915) expected 12")
		return false

	var synth_sp := func(dex: int) -> Dictionary:
		return {
			"dex": dex,
			"base_stats": {"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100},
			"types": ["ghost"] if dex == 9991 else ["normal"],
			"weight_hg": 500,
		}
	var synth_mv := func(mid: int) -> Dictionary:
		if mid == 9001:
			return {"id": 9001, "type": "ghost", "damage_class": "special", "power": 80, "accuracy": 100, "pp": 15, "priority": 0, "meta": {"crit_rate": 0}}
		if mid == 9002:
			return {"id": 9002, "type": "normal", "damage_class": "physical", "power": 80, "accuracy": 0, "pp": 20, "priority": 0, "meta": {"crit_rate": 0}}
		return {"id": mid, "type": "fighting", "damage_class": "physical", "power": 80, "accuracy": 80, "pp": 15, "priority": 0, "meta": {"crit_rate": 0}}

	var rng := BattleRandomRef.create_policy({"accuracy_mode": "never", "crit_mode": "never", "damage_roll": 100})
	var b := BattleStateRef.new(rng, AssetDBRef.DEFAULT_CACHE_DIR, synth_sp, synth_mv)
	b.setup_sides(
		[{"dex": 9991, "level": 50, "moves": [9001, 9002]}],
		[{"dex": 9992, "level": 50, "moves": [9003]}]
	)
	var u: Object = b.sides[0].call("active_battler")
	var t: Object = b.sides[1].call("active_battler")

	# Ghost -> Normal is immune (0 damage, never clamped to 1)
	var imm := DamageRef.get_damage(b, u, t, synth_mv.call(9001), false, 100)
	if not bool(imm["immune"]) or int(imm["damage"]) != 0:
		push_error("battle_formulas_test: synthetic immunity failed: %s" % str(imm))
		return false

	# Never-miss (accuracy=0) hits even when accuracy_mode=="never"
	if not DamageRef.hit_step_accuracy(b, u, t, synth_mv.call(9002)):
		push_error("battle_formulas_test: accuracy=0 move must hit even under never mode")
		return false
	# 80-accuracy move misses under accuracy_mode=="never"
	if DamageRef.hit_step_accuracy(b, t, u, synth_mv.call(9003)):
		push_error("battle_formulas_test: accuracy=80 move must miss under never mode")
		return false
	return true


func _test_calc_vectors_fixture() -> bool:
	if not FileAccess.file_exists(VECTORS_PATH):
		push_error("battle_formulas_test: missing fixture %s" % VECTORS_PATH)
		return false
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))
	if not (doc is Dictionary):
		push_error("battle_formulas_test: invalid JSON in %s" % VECTORS_PATH)
		return false
	if str(doc.get("oracle_package", "")) != "@smogon/calc" or str(doc.get("oracle_version", "")) != "0.12.0":
		push_error("battle_formulas_test: invalid oracle header in vectors fixture")
		return false
	var sha := str(doc.get("generator_sha256", ""))
	if sha.length() != 64:
		push_error("battle_formulas_test: invalid generator_sha256 in vectors fixture")
		return false
	var vectors: Array = doc.get("vectors", [])
	if vectors.size() < 300:
		push_error("battle_formulas_test: expected >= 300 vectors, got %d" % vectors.size())
		return false
	for v_var in vectors:
		var v: Dictionary = v_var
		if (v.get("rolls", []) as Array).size() != 16:
			push_error("battle_formulas_test: vector #%d does not have 16 rolls" % int(v.get("id", 0)))
			return false

	# Run every vector against AssetDB v3 cache when present (local Mac); skip cleanly on CI without data pack
	if not AssetDBRef.is_data_ready():
		print("SKIPPED data-pack calc vectors (%d validated) — no local data cache present" % vectors.size())
		return true

	var matched: int = 0
	var rng := BattleRandomRef.create_policy({"accuracy_mode": "always", "crit_mode": "never", "damage_roll": 100})
	var battle := BattleStateRef.new(rng)
	for v_var in vectors:
		var v: Dictionary = v_var
		var a_spec: Dictionary = v["attacker"]
		var d_spec: Dictionary = v["defender"]
		var mid: int = int(v["move_id"])
		var is_crit: bool = bool(v.get("is_crit", false))
		var expected_raw: Array = v["rolls"]

		var a_sp := AssetDBRef.species(int(a_spec["dex"]))
		var d_sp := AssetDBRef.species(int(d_spec["dex"]))
		var m_data := AssetDBRef.move(mid)
		if a_sp.is_empty() or d_sp.is_empty() or m_data.is_empty():
			push_error("battle_formulas_test: missing AssetDB data for vector #%d" % int(v["id"]))
			return false

		battle.setup_sides([a_spec], [d_spec])
		var src: Object = battle.sides[0].call("active_battler")
		var tgt: Object = battle.sides[1].call("active_battler")
		var got_rolls: Array[int] = DamageRef.calc_all_16_rolls(battle, src, tgt, m_data, is_crit)
		for i in range(16):
			var exp_val: int = int(expected_raw[i])
			if got_rolls[i] != exp_val:
				push_error("battle_formulas_test: vector #%d (%s) roll[%d] mismatch: got=%d expected=%d (all got=%s expected=%s)" % [
					int(v["id"]), str(v.get("category", "")), i, got_rolls[i], exp_val, str(got_rolls), str(expected_raw)
				])
				return false
		matched += 1

	print("vectors %d/%d x 16 rolls" % [matched, vectors.size()])
	return matched == vectors.size()
