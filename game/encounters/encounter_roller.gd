class_name EncounterRoller
extends RefCounted

## game/encounters/encounter_roller.gd — Per-Step Tall-Grass & Haunted-Interior Encounter Roller (Slice 3, Item 46)
## Contract: docs/implementation_plan_world_generation_slice3.md §6,
##           docs/design_encounters_and_haunted_zones.md §1,
##           docs/design_world_generation.md §4

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const SpawnDirector := preload("res://encounters/spawn_director.gd")

const GRASS_ENCOUNTER_RATE: float = 0.10
const HAUNTED_INTERIOR_ENCOUNTER_RATE: float = 0.12

static func familiarity_tier_from_days(explore_days: int) -> String:
	if explore_days >= 10:
		return "mastered"
	if explore_days >= 3:
		return "familiar"
	if explore_days >= 1:
		return "known"
	return "unknown"

static func familiarity_multiplier(tier: String) -> float:
	match tier:
		"mastered":
			return 0.50
		"familiar":
			return 0.75
		_:
			return 1.00

static func on_player_step(step_ctx: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var repel_steps: int = maxi(0, int(step_ctx.get("repel_steps", 0)))
	var repel_was_active: bool = (repel_steps > 0) or bool(step_ctx.get("repel_active", false))
	var next_repel: int = maxi(0, repel_steps - 1)

	var in_home_porch: bool = bool(step_ctx.get("in_home_porch", false))
	var intrusion_active: bool = bool(step_ctx.get("intrusion_active", false))
	if in_home_porch and not intrusion_active:
		return {
			"triggered": false,
			"repelled": false,
			"effective_rate": 0.0,
			"repel_steps_remaining": next_repel,
		}

	var in_haunted_interior: bool = bool(step_ctx.get("in_haunted_interior", false))
	var tile_class: int = int(step_ctx.get("tile_class", TileSynth2.TILE_GRASS))

	var base_rate: float = 0.0
	if in_haunted_interior:
		base_rate = HAUNTED_INTERIOR_ENCOUNTER_RATE
	elif tile_class == TileSynth2.TILE_TALL_GRASS:
		base_rate = GRASS_ENCOUNTER_RATE
	else:
		return {
			"triggered": false,
			"repelled": false,
			"effective_rate": 0.0,
			"repel_steps_remaining": next_repel,
		}

	var fam_tier: String = str(step_ctx.get("familiarity_tier", ""))
	if fam_tier.is_empty() and step_ctx.has("explore_days"):
		fam_tier = familiarity_tier_from_days(int(step_ctx.get("explore_days", 1)))
	var fam_mult: float = familiarity_multiplier(fam_tier)
	var effective_rate: float = base_rate * fam_mult

	var u_step: float = rng.randf()
	if u_step >= effective_rate:
		return {
			"triggered": false,
			"repelled": false,
			"effective_rate": effective_rate,
			"repel_steps_remaining": next_repel,
		}

	var rolled: Dictionary = SpawnDirector.roll_encounter(step_ctx, rng)
	var lead_party_level: int = int(step_ctx.get("lead_party_level", 1))
	if repel_was_active and int(rolled.get("level", 1)) < lead_party_level:
		return {
			"triggered": false,
			"repelled": true,
			"effective_rate": effective_rate,
			"repel_steps_remaining": next_repel,
			"suppressed_encounter": rolled,
		}

	var result: Dictionary = rolled.duplicate(true)
	result["triggered"] = true
	result["repelled"] = false
	result["effective_rate"] = effective_rate
	result["repel_steps_remaining"] = next_repel
	return result
