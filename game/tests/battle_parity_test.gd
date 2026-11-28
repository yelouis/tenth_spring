extends Node

# Parity Test Runner for Slice 1 (Item 94):
# - Validates battle_parity_gen8/slice1.json header & schema (always, incl. CI)
# - Runs synthetic Slice 1 parity battles end-to-end (always, incl. CI)
# - Executes all 60 pokemon-showdown@0.11.11 parity scenarios against AssetDB
#   v3 cache when present (local Mac), printing `parity slice1 N/N` and ms/turn.

const BattleRandomRef := preload("res://battle/battle_random.gd")
const BattleStateRef := preload("res://battle/state/battle_state.gd")
const AssetDBRef := preload("res://rom/asset_db.gd")

const SLICE1_FIXTURE_PATH: String = "res://tests/fixtures/battle_parity_gen8/slice1.json"


func run_test() -> bool:
	if not _test_synthetic_parity_flow():
		return false
	return run_fixture_path(SLICE1_FIXTURE_PATH)


static func run_fixture_path(fixture_path: String) -> bool:
	if not FileAccess.file_exists(fixture_path):
		push_error("battle_parity_test: missing fixture %s" % fixture_path)
		return false
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not (doc is Dictionary):
		push_error("battle_parity_test: invalid JSON in %s" % fixture_path)
		return false
	if str(doc.get("oracle_package", "")) != "pokemon-showdown" or str(doc.get("oracle_version", "")) != "0.11.11":
		push_error("battle_parity_test: invalid oracle header in %s" % fixture_path)
		return false
	if str(doc.get("generator_sha256", "")).length() != 64:
		push_error("battle_parity_test: invalid generator_sha256 in %s" % fixture_path)
		return false
	var scenarios: Array = doc.get("scenarios", [])
	if scenarios.size() < 50:
		push_error("battle_parity_test: expected >= 50 scenarios, got %d" % scenarios.size())
		return false

	if not AssetDBRef.is_data_ready():
		print("SKIPPED data-pack parity scenarios (%d validated) — no local data cache present" % scenarios.size())
		return true

	var passed: int = 0
	var total_turns: int = 0
	var t0_us: int = Time.get_ticks_usec()

	for sc_var in scenarios:
		var sc: Dictionary = sc_var
		var sc_id: int = int(sc.get("id", 0))
		var sc_tag: String = str(sc.get("tag", ""))
		var pol: Dictionary = sc.get("policy", {})
		var rng := BattleRandomRef.create_policy(pol)
		var battle := BattleStateRef.new(rng)
		var sides_cfg: Array = sc.get("sides", [[], []])
		battle.setup_sides(sides_cfg[0], sides_cfg[1])

		var turns: Array = sc.get("turns", [])
		var expected_turns: Array = sc.get("expected_turns", [])
		if turns.size() < expected_turns.size():
			push_error("battle_parity_test: scenario #%d (%s) turns < expected_turns" % [sc_id, sc_tag])
			return false

		for t_idx in range(expected_turns.size()):
			var ch: Array = turns[t_idx]
			var got_snap: Dictionary = battle.run_turn(str(ch[0]), str(ch[1]))
			total_turns += 1
			var exp_snap: Dictionary = expected_turns[t_idx]
			var diff := _diff_turn_snapshot(got_snap, exp_snap)
			if diff != "":
				push_error("battle_parity_test: scenario #%d (%s) turn %d mismatch: %s" % [sc_id, sc_tag, t_idx + 1, diff])
				return false
		passed += 1

	var elapsed_ms: float = float(Time.get_ticks_usec() - t0_us) / 1000.0
	var ms_per_turn: float = elapsed_ms / float(maxi(1, total_turns))
	print("parity slice1 %d/%d (turns=%d, %.3f ms/turn)" % [passed, scenarios.size(), total_turns, ms_per_turn])
	return passed == scenarios.size()


static func _diff_turn_snapshot(got: Dictionary, exp: Dictionary) -> String:
	if bool(got.get("ended", false)) != bool(exp.get("ended", false)):
		return "ended got=%s exp=%s" % [str(got.get("ended")), str(exp.get("ended"))]
	if int(got.get("winner", -1)) != int(exp.get("winner", -1)):
		return "winner got=%d exp=%d" % [int(got.get("winner", -1)), int(exp.get("winner", -1))]

	var g_acts: Array = got.get("action_order", [])
	var e_acts: Array = exp.get("action_order", [])
	if g_acts.size() != e_acts.size():
		return "action_order len got=%d exp=%d (got=%s exp=%s)" % [g_acts.size(), e_acts.size(), str(g_acts), str(e_acts)]
	for i in range(g_acts.size()):
		var ga: Dictionary = g_acts[i]
		var ea: Dictionary = e_acts[i]
		if int(ga.get("side", -1)) != int(ea.get("side", -1)) \
			or int(ga.get("move_id", -1)) != int(ea.get("move_id", -1)) \
			or bool(ga.get("hit", false)) != bool(ea.get("hit", false)) \
			or bool(ga.get("crit", false)) != bool(ea.get("crit", false)) \
			or bool(ga.get("immune", false)) != bool(ea.get("immune", false)):
			return "action[%d] got=%s exp=%s" % [i, str(ga), str(ea)]

	var g_sides: Array = got.get("sides", [])
	var e_sides: Array = exp.get("sides", [])
	for s in range(2):
		var gs: Dictionary = g_sides[s]
		var es: Dictionary = e_sides[s]
		if int(gs.get("fainted_count", 0)) != int(es.get("fainted_count", 0)):
			return "side%d fainted_count got=%d exp=%d" % [s, int(gs.get("fainted_count", 0)), int(es.get("fainted_count", 0))]
		var gb: Dictionary = gs.get("active", {})
		var eb: Dictionary = es.get("active", {})
		for k in ["dex", "hp", "max_hp", "status", "volatiles", "item_id", "ability_id"]:
			if int(gb.get(k, -1)) != int(eb.get(k, -1)):
				return "side%d.%s got=%d exp=%d" % [s, k, int(gb.get(k, -1)), int(eb.get(k, -1))]
		if bool(gb.get("fainted", false)) != bool(eb.get("fainted", false)):
			return "side%d.fainted got=%s exp=%s" % [s, str(gb.get("fainted")), str(eb.get("fainted"))]
		var g_boosts: Dictionary = gb.get("boosts", {})
		var e_boosts: Dictionary = eb.get("boosts", {})
		for bk in ["atk", "def", "spa", "spd", "spe", "accuracy", "evasion"]:
			if int(g_boosts.get(bk, 0)) != int(e_boosts.get(bk, 0)):
				return "side%d.boosts.%s got=%d exp=%d" % [s, bk, int(g_boosts.get(bk, 0)), int(e_boosts.get(bk, 0))]
		var g_types: Array = gb.get("types", [])
		var e_types: Array = eb.get("types", [])
		if g_types.size() != e_types.size():
			return "side%d.types got=%s exp=%s" % [s, str(g_types), str(e_types)]
		for ti in range(g_types.size()):
			if str(g_types[ti]) != str(e_types[ti]):
				return "side%d.types[%d] got=%s exp=%s" % [s, ti, str(g_types[ti]), str(e_types[ti])]

	var gf: Dictionary = got.get("field", {})
	var ef: Dictionary = exp.get("field", {})
	for fk in ["weather_id", "weather_turns", "terrain_id", "terrain_turns", "pseudo_weather_count"]:
		if int(gf.get(fk, 0)) != int(ef.get(fk, 0)):
			return "field.%s got=%d exp=%d" % [fk, int(gf.get(fk, 0)), int(ef.get(fk, 0))]
	return ""


func _test_synthetic_parity_flow() -> bool:
	# Self-contained synthetic end-to-end turn flow (runs on CI without PokéAPI data cache)
	var sp_fn := func(dex: int) -> Dictionary:
		if dex == 9901:
			return {"dex": 9901, "base_stats": {"hp": 80, "atk": 120, "def": 80, "spa": 60, "spd": 80, "spe": 100}, "types": ["fighting"], "weight_hg": 500}
		return {"dex": 9902, "base_stats": {"hp": 80, "atk": 90, "def": 80, "spa": 90, "spd": 80, "spe": 100}, "types": ["normal"], "weight_hg": 500}
	var mv_fn := func(mid: int) -> Dictionary:
		if mid == 9501:
			return {"id": 9501, "type": "fighting", "damage_class": "physical", "power": 80, "accuracy": 100, "pp": 15, "priority": 0, "meta": {"crit_rate": 0}}
		return {"id": 9502, "type": "normal", "damage_class": "physical", "power": 40, "accuracy": 100, "pp": 30, "priority": 1, "meta": {"crit_rate": 0}}

	# Side 1 uses +1 priority move first despite tied speed, then Side 0 counters with 2x STAB Fighting
	var rng := BattleRandomRef.create_policy({"accuracy_mode": "always", "crit_mode": "never", "damage_roll": 100, "speed_tie": 0})
	var b := BattleStateRef.new(rng, AssetDBRef.DEFAULT_CACHE_DIR, sp_fn, mv_fn)
	b.setup_sides(
		[{"dex": 9901, "level": 50, "moves": [9501]}],
		[{"dex": 9902, "level": 50, "moves": [9502]}]
	)
	var snap := b.run_turn("move 1", "move 1")
	var acts: Array = snap["action_order"]
	if acts.size() != 2 or int(acts[0]["side"]) != 1 or int(acts[1]["side"]) != 0:
		push_error("battle_parity_test: synthetic priority order failed: %s" % str(acts))
		return false
	if int(snap["sides"][1]["active"]["hp"]) >= int(snap["sides"][1]["active"]["max_hp"]):
		push_error("battle_parity_test: synthetic damage not applied")
		return false
	return true
