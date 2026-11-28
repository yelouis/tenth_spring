# Translated from Pokémon Showdown (MIT); see CREDITS.md.
extends RefCounted

# Stat, nature, stage, and integer truncation helpers matching
# pokemon-showdown@0.11.11 sim/pokemon.ts:560-649 and sim/dex.ts:391.

const STAT_KEYS: Array[String] = ["hp", "atk", "def", "spa", "spd", "spe"]
# Nature table order: inc = nature_id / 5, dec = nature_id % 5
# 0=atk, 1=def, 2=spe, 3=spa, 4=spd (neutral when inc == dec).
const NATURE_STAT_ORDER: Array[String] = ["atk", "def", "spe", "spa", "spd"]

const STATUS_NONE: int = 0
const STATUS_PAR: int = 1
const STATUS_SLP: int = 2
const STATUS_FRZ: int = 3
const STATUS_BRN: int = 4
const STATUS_PSN: int = 5
const STATUS_TOX: int = 6


static func trunc_int(value: int, bits: int = 0) -> int:
	if bits > 0:
		var mask: int = (1 << bits) - 1
		return value & mask
	return value


static func clamp_int(value: int, min_val: int, max_val: int) -> int:
	if value < min_val:
		return min_val
	if value > max_val:
		return max_val
	return value


static func nature_modifier_num(nature_id: int, stat_key: String) -> int:
	if stat_key == "hp":
		return 10
	var nid: int = clamp_int(nature_id, 0, 24)
	var inc_idx: int = nid / 5
	var dec_idx: int = nid % 5
	if inc_idx == dec_idx:
		return 10
	var s_idx: int = NATURE_STAT_ORDER.find(stat_key)
	if s_idx == inc_idx:
		return 11
	if s_idx == dec_idx:
		return 9
	return 10


static func calc_hp(base_hp: int, iv: int, ev: int, level: int, species_dex: int = 0) -> int:
	if species_dex == 292 or base_hp == 1:
		return 1
	var c_iv: int = clamp_int(iv, 0, 31)
	var c_ev: int = clamp_int(ev, 0, 252)
	var c_lvl: int = clamp_int(level, 1, 100)
	return ((2 * base_hp + c_iv + (c_ev / 4)) * c_lvl) / 100 + c_lvl + 10


static func calc_stat(base_val: int, iv: int, ev: int, level: int, nature_id: int, stat_key: String) -> int:
	var c_iv: int = clamp_int(iv, 0, 31)
	var c_ev: int = clamp_int(ev, 0, 252)
	var c_lvl: int = clamp_int(level, 1, 100)
	var raw: int = ((2 * base_val + c_iv + (c_ev / 4)) * c_lvl) / 100 + 5
	var nat_num: int = nature_modifier_num(nature_id, stat_key)
	return (raw * nat_num) / 10


static func calc_all_stats(
	base_stats: Dictionary,
	ivs: Array,
	evs: Array,
	level: int,
	nature_id: int,
	species_dex: int = 0
) -> Dictionary:
	var out := {}
	out["hp"] = calc_hp(int(base_stats.get("hp", 1)), int(ivs[0]), int(evs[0]), level, species_dex)
	out["atk"] = calc_stat(int(base_stats.get("atk", 1)), int(ivs[1]), int(evs[1]), level, nature_id, "atk")
	out["def"] = calc_stat(int(base_stats.get("def", 1)), int(ivs[2]), int(evs[2]), level, nature_id, "def")
	out["spa"] = calc_stat(int(base_stats.get("spa", 1)), int(ivs[3]), int(evs[3]), level, nature_id, "spa")
	out["spd"] = calc_stat(int(base_stats.get("spd", 1)), int(ivs[4]), int(evs[4]), level, nature_id, "spd")
	out["spe"] = calc_stat(int(base_stats.get("spe", 1)), int(ivs[5]), int(evs[5]), level, nature_id, "spe")
	return out


static func apply_stage(stat_value: int, stage: int) -> int:
	var s: int = clamp_int(stage, -6, 6)
	if s > 0:
		return (stat_value * (2 + s)) / 2
	if s < 0:
		return (stat_value * 2) / (2 - s)
	return stat_value


static func apply_accuracy_stage(accuracy: int, net_stage: int) -> int:
	var s: int = clamp_int(net_stage, -6, 6)
	if s > 0:
		return (accuracy * (3 + s)) / 3
	if s < 0:
		return (accuracy * 3) / (3 - s)
	return accuracy


static func calc_action_speed(modified_spe: int, trick_room_active: bool) -> int:
	var spe: int = trunc_int(modified_spe, 13)
	if trick_room_active:
		spe = trunc_int(10000 - spe, 13)
	return spe
