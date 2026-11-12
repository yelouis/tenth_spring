extends Node

## game/tests/slice3_encounters_test.gd — World Generation Slice 3 Verification Suite (Item 46)
## Contract: docs/implementation_plan_world_generation_slice3.md §1–§8

const CellClassifier := preload("res://world/cell_classifier.gd")
const DistortionFields := preload("res://world/distortion_fields.gd")
const SpawnDirector := preload("res://encounters/spawn_director.gd")
const EncounterRoller := preload("res://encounters/encounter_roller.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")
const MapViewScene := preload("res://world/map_view.tscn")

const TEST_DB_PATH: String = "user://test/slice3_encounters_test.db"

func _cleanup() -> void:
	for suffix in ["", "-wal", "-shm", ".tmp", ".jsonbak"]:
		var p: String = TEST_DB_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func run_test() -> bool:
	_cleanup()

	if not _test_ghost_share_and_statistical_pools():
		_cleanup()
		return false
	if not _test_region_and_biome_isolation_and_distortion_share():
		_cleanup()
		return false
	if not _test_species_partition_zero_legendary_and_ub_gate():
		_cleanup()
		return false
	if not _test_cell_classifier_and_haunted_tie_breaker():
		_cleanup()
		return false
	if not _test_one_way_ledges_and_atlases():
		_cleanup()
		return false
	if not _test_level_bands_familiarity_porch_and_repel():
		_cleanup()
		return false
	if not _test_distortion_field_cadence_placement_and_hud():
		_cleanup()
		return false
	if not _test_db_migration_4_cell_metadata():
		_cleanup()
		return false

	_cleanup()
	return true

# ---------------------------------------------------------------------------
# 1. Phase 6 Exit-Criteria Statistical Tests & Ghost-Share Formula (§3, §8.1)
# ---------------------------------------------------------------------------
func _test_ghost_share_and_statistical_pools() -> bool:
	var g_res_day: float = SpawnDirector.compute_ghost_share("residential", "day", 0)
	if absf(g_res_day - 0.05) > 1e-4:
		push_error("Expected residential day ghost_share 0.05, got %.4f" % g_res_day)
		return false

	var g_cem_night: float = SpawnDirector.compute_ghost_share("cemetery", "night", 0)
	if absf(g_cem_night - 0.80) > 1e-4:
		push_error("Expected cemetery night ghost_share 0.80 (capped), got %.4f" % g_cem_night)
		return false

	var g_ruins_dusk_s1: float = SpawnDirector.compute_ghost_share("ruins", "dusk", 1)
	if absf(g_ruins_dusk_s1 - 0.775) > 1e-4:
		push_error("Expected ruins dusk stage 1 ghost_share 0.775, got %.4f" % g_ruins_dusk_s1)
		return false

	# 1,000-roll night cemetery statistical test: >= 75% (750/1000) from haunted pool
	var rng_cem := RandomNumberGenerator.new()
	rng_cem.seed = 46001
	var cem_haunted_count: int = 0
	var cem_ctx := {
		"zone": "cemetery",
		"biome": "forest",
		"region": "New England",
		"time_band": "night",
		"haunt_stage": 0,
		"distance_miles": 12.0,
		"in_distortion_field": false,
	}
	for i in 1000:
		var r: Dictionary = SpawnDirector.roll_encounter(cem_ctx, rng_cem)
		var dex: int = int(r.get("dex", 0))
		if dex < 1 or dex > 905:
			push_error("Night cemetery roll %d returned out-of-range dex %d" % [i, dex])
			return false
		if str(r.get("pool", "")) == "haunted":
			cem_haunted_count += 1
	if cem_haunted_count < 750:
		push_error("Night cemetery falsified: expected >= 750/1000 haunted rolls, got %d" % cem_haunted_count)
		return false

	# 1,000-roll day residential statistical test: <= 10% (100/1000) from haunted pool
	var rng_sub := RandomNumberGenerator.new()
	rng_sub.seed = 46002
	var sub_haunted_count: int = 0
	var sub_ctx := {
		"zone": "residential",
		"biome": "plains",
		"region": "South Atlantic",
		"time_band": "day",
		"haunt_stage": 0,
		"distance_miles": 1.0,
		"in_distortion_field": false,
	}
	for i in 1000:
		var r: Dictionary = SpawnDirector.roll_encounter(sub_ctx, rng_sub)
		if str(r.get("pool", "")) == "haunted":
			sub_haunted_count += 1
	if sub_haunted_count > 100:
		push_error("Day residential falsified: expected <= 100/1000 haunted rolls, got %d" % sub_haunted_count)
		return false

	return true

# ---------------------------------------------------------------------------
# 2. Region & Biome Isolation Falsifier + Distortion Field 40% Foreign Share (§8.2)
# ---------------------------------------------------------------------------
func _test_region_and_biome_isolation_and_distortion_share() -> bool:
	var tables: Dictionary = SpawnDirector.get_spawn_tables()
	var zones_dict: Dictionary = tables.get("zones", {})
	if zones_dict.size() != 11:
		push_error("Expected 11 zones in spawn_tables.json, got %d" % zones_dict.size())
		return false

	# Collect all species allowed in (zone="wilds", biome="forest", region="Pacific")
	var allowed_pacific_forest: Dictionary = {}
	for pk in ["regular", "haunted"]:
		var filtered: Array[Dictionary] = SpawnDirector.filter_pool("wilds", pk, "forest", "Pacific")
		if filtered.is_empty():
			push_error("Empty filtered pool for wilds/%s/forest/Pacific" % pk)
			return false
		for entry in filtered:
			var biomes_arr: Array = entry.get("biomes", [])
			var regions_arr: Array = entry.get("regions", [])
			if not (biomes_arr.has("all") or biomes_arr.has("forest")):
				push_error("filter_pool leaked non-forest entry: %s" % str(entry))
				return false
			if not (regions_arr.has("all") or regions_arr.has("Pacific")):
				push_error("filter_pool leaked non-Pacific entry: %s" % str(entry))
				return false
			allowed_pacific_forest[int(entry.get("dex", 0))] = true

	# Roll 1,000 normal encounters in (wilds, forest, Pacific) -> 0 foreign species
	var rng := RandomNumberGenerator.new()
	rng.seed = 46003
	var ctx := {
		"zone": "wilds",
		"biome": "forest",
		"region": "Pacific",
		"time_band": "day",
		"haunt_stage": 0,
		"distance_miles": 5.0,
		"in_distortion_field": false,
	}
	for i in 1000:
		var r: Dictionary = SpawnDirector.roll_encounter(ctx, rng)
		var dex: int = int(r.get("dex", 0))
		if not allowed_pacific_forest.has(dex):
			push_error("Region/biome isolation falsified: dex %d appeared in Pacific forest outside Distortion Field" % dex)
			return false

	# Enable Distortion Field on the same cell -> ~40% from_distortion_field draws and foreign species appear
	ctx["in_distortion_field"] = true
	var field_draws: int = 0
	var foreign_dex_draws: int = 0
	for i in 1000:
		var r: Dictionary = SpawnDirector.roll_encounter(ctx, rng)
		var dex: int = int(r.get("dex", 0))
		if bool(r.get("from_distortion_field", false)):
			field_draws += 1
		if not allowed_pacific_forest.has(dex):
			foreign_dex_draws += 1
	if field_draws < 330 or field_draws > 470:
		push_error("Expected ~40%% (330..470/1000) Distortion Field draws, got %d" % field_draws)
		return false
	if foreign_dex_draws < 50:
		push_error("Expected foreign biome/region species to appear inside Distortion Field, got %d" % foreign_dex_draws)
		return false

	return true

# ---------------------------------------------------------------------------
# 3. 905-Species Partition, Zero-Legendary & Ultra-Beast Gate Falsifiers (§8.3)
# ---------------------------------------------------------------------------
func _test_species_partition_zero_legendary_and_ub_gate() -> bool:
	var tables: Dictionary = SpawnDirector.get_spawn_tables()
	var leg_arr: Array = tables.get("excluded_legendary_mythical_dex", [])
	var ub_arr: Array = tables.get("ultra_beast_pool", [])
	var evo_ub_arr: Array = tables.get("evolution_only_ultra_beasts", [])
	var field_arr: Array = tables.get("non_legendary_field_pool", [])
	var evo_wild_arr: Array = tables.get("evolvable_from_wild_dex", [])

	if leg_arr.size() != 82:
		push_error("Expected 82 excluded legendaries/mythicals, got %d" % leg_arr.size())
		return false
	if ub_arr.size() != 10 or evo_ub_arr.size() != 1:
		push_error("Expected 10 wild UBs + 1 evo UB (#804), got %d + %d" % [ub_arr.size(), evo_ub_arr.size()])
		return false

	var leg_set: Dictionary = {}
	for d in leg_arr:
		leg_set[int(d)] = true
	var ub_set: Dictionary = {}
	for d in ub_arr:
		ub_set[int(d)] = true
	for d in evo_ub_arr:
		ub_set[int(d)] = true

	var all_seen: Dictionary = {}
	for d in leg_arr:
		all_seen[int(d)] = true
	for d in ub_arr:
		if all_seen.has(int(d)):
			push_error("Overlap between legendary and UB dex %d" % int(d))
			return false
		all_seen[int(d)] = true
	for d in evo_ub_arr:
		all_seen[int(d)] = true
	for d in field_arr:
		if leg_set.has(int(d)) or ub_set.has(int(d)):
			push_error("Field pool leaked legendary or UB dex %d" % int(d))
			return false
		all_seen[int(d)] = true
	for d in evo_wild_arr:
		if leg_set.has(int(d)) or ub_set.has(int(d)):
			push_error("Evolvable pool leaked legendary or UB dex %d" % int(d))
			return false
		all_seen[int(d)] = true

	if all_seen.size() != 905:
		push_error("Expected exact 905-species partition (1..905), got %d unique species" % all_seen.size())
		return false

	# Falsifier A: 3,000 Distortion Field rolls with anchors_held=5, necrozma_cleared=true -> 0 legendaries, 0 UBs
	var rng := RandomNumberGenerator.new()
	rng.seed = 46004
	var ctx_pre := {
		"zone": "cemetery",
		"biome": "city",
		"region": "Middle Atlantic",
		"time_band": "night",
		"haunt_stage": 2,
		"distance_miles": 100.0,
		"in_distortion_field": true,
		"anchors_held": 5,
		"necrozma_cleared": true,
	}
	for i in 3000:
		var r: Dictionary = SpawnDirector.roll_encounter(ctx_pre, rng)
		var dex: int = int(r.get("dex", 0))
		if leg_set.has(dex):
			push_error("Zero-legendary falsified: legendary dex %d rolled in Distortion Field" % dex)
			return false
		if ub_set.has(dex) or bool(r.get("is_ultra_beast", false)):
			push_error("UB gate falsified: UB dex %d rolled with anchors_held=5" % dex)
			return false

	# Falsifier B: 3,000 Distortion Field rolls with anchors_held=7, necrozma_cleared=false -> 0 UBs
	var ctx_no_necro := ctx_pre.duplicate()
	ctx_no_necro["anchors_held"] = 7
	ctx_no_necro["necrozma_cleared"] = false
	for i in 3000:
		var r: Dictionary = SpawnDirector.roll_encounter(ctx_no_necro, rng)
		var dex: int = int(r.get("dex", 0))
		if ub_set.has(dex) or bool(r.get("is_ultra_beast", false)):
			push_error("UB gate falsified: UB dex %d rolled with necrozma_cleared=false" % dex)
			return false

	# Falsifier C: 4,000 Distortion Field rolls with anchors_held=7, necrozma_cleared=true -> > 0 UBs, 0 legendaries
	var ctx_post := ctx_pre.duplicate()
	ctx_post["anchors_held"] = 7
	ctx_post["necrozma_cleared"] = true
	var ub_count: int = 0
	for i in 4000:
		var r: Dictionary = SpawnDirector.roll_encounter(ctx_post, rng)
		var dex: int = int(r.get("dex", 0))
		if leg_set.has(dex):
			push_error("Zero-legendary falsified post-Necrozma: legendary dex %d rolled" % dex)
			return false
		if bool(r.get("is_ultra_beast", false)):
			if not ub_set.has(dex):
				push_error("is_ultra_beast=true for non-UB dex %d" % dex)
				return false
			ub_count += 1
	if ub_count <= 0:
		push_error("Expected > 0 Ultra Beast rolls across 4,000 post-Necrozma Distortion Field draws, got 0")
		return false

	return true

# ---------------------------------------------------------------------------
# 4. CellClassifier 11 Zones, Haunted Tie-Breaker & 8 Biomes (§8.5)
# ---------------------------------------------------------------------------
func _test_cell_classifier_and_haunted_tie_breaker() -> bool:
	# Haunted tie-breaker: residential + cemetery -> cemetery
	var tie_cem_res := {
		Vector2i.ZERO: {
			"polys": [
				{"kind": "residential", "subkind": "residential"},
				{"kind": "cemetery", "subkind": "cemetery"},
			],
			"lines": [],
			"places": [],
			"sea": 0,
		}
	}
	if CellClassifier.classify_zone(tie_cem_res) != "cemetery":
		push_error("Haunted tie-breaker failed: residential + cemetery did not resolve to cemetery")
		return false

	# Haunted tie-breaker: downtown + ruins -> ruins
	var tie_ruins_dt := {
		Vector2i.ZERO: {
			"polys": [
				{"kind": "commercial", "subkind": "commercial"},
				{"kind": "ruins", "subkind": "ruins"},
			],
			"lines": [],
			"places": [],
			"sea": 0,
		}
	}
	if CellClassifier.classify_zone(tie_ruins_dt) != "ruins":
		push_error("Haunted tie-breaker failed: commercial + ruins did not resolve to ruins")
		return false

	# Haunted tie-breaker: retail + hospital -> hospital
	var tie_hosp_ret := {
		Vector2i.ZERO: {
			"polys": [
				{"kind": "retail", "subkind": "retail"},
				{"kind": "building", "subkind": "hospital"},
			],
			"lines": [],
			"places": [],
			"sea": 0,
		}
	}
	if CellClassifier.classify_zone(tie_hosp_ret) != "hospital":
		push_error("Haunted tie-breaker failed: retail + hospital did not resolve to hospital")
		return false

	# Haunted priority: cemetery + hospital -> cemetery
	var tie_cem_hosp := {
		Vector2i.ZERO: {
			"polys": [
				{"kind": "building", "subkind": "hospital"},
				{"kind": "cemetery", "subkind": "cemetery"},
			],
			"lines": [],
			"places": [],
			"sea": 0,
		}
	}
	if CellClassifier.classify_zone(tie_cem_hosp) != "cemetery":
		push_error("Haunted priority failed: cemetery + hospital did not resolve to cemetery")
		return false

	# Remaining zones: waterfront, institutional, retail, downtown, industrial, parkland, residential, wilds
	var z_cases := [
		{"expected": "waterfront", "area": {Vector2i.ZERO: {"polys": [], "places": [], "sea": 1}}},
		{"expected": "institutional", "area": {Vector2i.ZERO: {"polys": [{"kind": "building", "subkind": "university"}], "places": [], "sea": 0}}},
		{"expected": "retail", "area": {Vector2i.ZERO: {"polys": [{"kind": "retail", "subkind": "supermarket"}], "places": [], "sea": 0}}},
		{"expected": "downtown", "area": {Vector2i.ZERO: {"polys": [{"kind": "commercial", "subkind": "office"}], "places": [], "sea": 0}}},
		{"expected": "industrial", "area": {Vector2i.ZERO: {"polys": [{"kind": "industrial", "subkind": "warehouse"}], "places": [], "sea": 0}}},
		{"expected": "parkland", "area": {Vector2i.ZERO: {"polys": [{"kind": "park", "subkind": "park"}], "places": [], "sea": 0}}},
		{"expected": "residential", "area": {Vector2i.ZERO: {"polys": [{"kind": "residential", "subkind": "residential"}], "places": [], "sea": 0}}},
		{"expected": "wilds", "area": {Vector2i.ZERO: {"polys": [], "places": [], "sea": 0}}},
	]
	for c in z_cases:
		var got_z: String = CellClassifier.classify_zone(c["area"])
		if got_z != c["expected"]:
			push_error("Expected zone '%s', got '%s'" % [c["expected"], got_z])
			return false

	# Verify all 8 biomes via classify_biome
	var empty_area := {Vector2i.ZERO: {"polys": [], "places": [], "sea": 0}}
	if CellClassifier.classify_biome("wilds", empty_area, {}, "city:phoenix") != "desert":
		push_error("Expected desert biome for city:phoenix")
		return false
	if CellClassifier.classify_biome("wilds", empty_area, {}, "city:minneapolis") != "snow":
		push_error("Expected snow biome for city:minneapolis")
		return false
	if CellClassifier.classify_biome("wilds", empty_area, {}, "city:denver") != "mountains":
		push_error("Expected mountains biome for city:denver")
		return false
	if CellClassifier.classify_biome("wilds", empty_area, {}, "site:everglades") != "wetland":
		push_error("Expected wetland biome for site:everglades")
		return false
	if CellClassifier.classify_biome("waterfront", {Vector2i.ZERO: {"polys": [], "places": [], "sea": 2}}, {}, "city:miami") != "coast":
		push_error("Expected coast biome for sea=2 waterfront")
		return false
	if CellClassifier.classify_biome("downtown", empty_area, {}, "city:chicago") != "city":
		push_error("Expected city biome for downtown zone")
		return false
	if CellClassifier.classify_biome("parkland", empty_area, {}, "city:philadelphia") != "forest":
		push_error("Expected forest biome for parkland inside city:philadelphia")
		return false
	if CellClassifier.classify_biome("wilds", empty_area, {}, "city:austin") != "plains":
		push_error("Expected plains biome for wilds in city:austin")
		return false

	# Verify TileSynth2.synthesize_cell outputs zone, biome, region, ghost_base
	var synth_out: Dictionary = TileSynth2.synthesize_cell(4, 4, tie_cem_res, 12345)
	if str(synth_out.get("zone", "")) != "cemetery":
		push_error("TileSynth2.synthesize_cell expected zone 'cemetery', got '%s'" % str(synth_out.get("zone", "")))
		return false
	if not (str(synth_out.get("biome", "")) in CellClassifier.BIOMES):
		push_error("TileSynth2.synthesize_cell returned invalid biome '%s'" % str(synth_out.get("biome", "")))
		return false
	if not (str(synth_out.get("region", "")) in CellClassifier.DIVISIONS):
		push_error("TileSynth2.synthesize_cell returned invalid region '%s'" % str(synth_out.get("region", "")))
		return false

	return true

# ---------------------------------------------------------------------------
# 5. One-Way Ledge Traversal, Synthesis & Atlas Verification (§2, §8.6)
# ---------------------------------------------------------------------------
func _test_one_way_ledges_and_atlases() -> bool:
	if TileSynth2.TILE_LEDGE != 22:
		push_error("Expected TileSynth2.TILE_LEDGE == 22, got %d" % TileSynth2.TILE_LEDGE)
		return false
	if TileSynth2.is_walkable(TileSynth2.TILE_LEDGE):
		push_error("TILE_LEDGE must not be directly walkable (requires directional jump)")
		return false

	# Variant 0: south-facing ledge -> only Vector2i(0, 1) allowed when landing tile is walkable
	if not TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 0, TileSynth2.TILE_GRASS, 0, Vector2i(0, 1)):
		push_error("Expected variant 0 ledge to allow south jump Vector2i(0, 1)")
		return false
	if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 0, TileSynth2.TILE_WATER, 0, Vector2i(0, 1)):
		push_error("Variant 0 ledge must block jump when landing tile is unwalkable (TILE_WATER)")
		return false
	for blocked_dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 0, TileSynth2.TILE_GRASS, 0, blocked_dir):
			push_error("Variant 0 ledge must block non-south direction %s" % str(blocked_dir))
			return false

	# Variant 1: east-facing ledge -> only Vector2i(1, 0) allowed
	if not TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 1, TileSynth2.TILE_GRASS, 0, Vector2i(1, 0)):
		push_error("Expected variant 1 ledge to allow east jump Vector2i(1, 0)")
		return false
	if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 1, TileSynth2.TILE_GRASS, 0, Vector2i(-1, 0)):
		push_error("Variant 1 ledge must block west direction")
		return false

	# Variant 2: west-facing ledge -> only Vector2i(-1, 0) allowed
	if not TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 2, TileSynth2.TILE_GRASS, 0, Vector2i(-1, 0)):
		push_error("Expected variant 2 ledge to allow west jump Vector2i(-1, 0)")
		return false
	if TileSynth2.can_jump_ledge(TileSynth2.TILE_LEDGE, 2, TileSynth2.TILE_GRASS, 0, Vector2i(1, 0)):
		push_error("Variant 2 ledge must block east direction")
		return false

	# Synthesize a scrub cell and confirm TILE_LEDGE (22) tiles are placed
	var scrub_ring := PackedVector2Array([
		Vector2(0, 0), Vector2(16, 0), Vector2(16, 16), Vector2(0, 16)
	])
	var scrub_area := {
		Vector2i.ZERO: {
			"polys": [{"kind": "scrub", "geom_rings": MapStore.pack_rings([scrub_ring])}],
			"lines": [],
			"places": [],
			"covered": true,
			"sea": 0,
		}
	}
	var ledge_count: int = 0
	for cx in range(0, 6):
		var res := TileSynth2.synthesize_cell(cx, 0, scrub_area, 42)
		var tiles: PackedByteArray = res["tiles"]
		for i in range(0, 3072, 3):
			if tiles[i] == TileSynth2.TILE_LEDGE:
				ledge_count += 1
	if ledge_count < 3:
		push_error("Expected scrub cells to synthesize >= 3 TILE_LEDGE tiles, got %d" % ledge_count)
		return false

	# Verify both tile atlases include class 22 at rows [94, 95, 96] and 512x3232 dimensions
	for base in ["res://assets/tiles/original_v1", "res://assets/tiles/placeholder_v1"]:
		var json_txt := FileAccess.get_file_as_string(base + ".json")
		var meta: Variant = JSON.parse_string(json_txt)
		if not (meta is Dictionary):
			push_error("Failed to parse %s.json" % base)
			return false
		var rows_arr: Array = (meta as Dictionary).get("rows", [])
		var ledge_rows: Array[int] = []
		for r_entry in rows_arr:
			if r_entry is Dictionary and int((r_entry as Dictionary).get("class", -1)) == 22:
				ledge_rows.append(int((r_entry as Dictionary).get("row", -1)))
		if ledge_rows != [94, 95, 96]:
			push_error("Expected class 22 rows [94, 95, 96] in %s.json, got %s" % [base, str(ledge_rows)])
			return false
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(base + ".png")) != OK:
			push_error("Failed to load %s.png" % base)
			return false
		if img.get_width() != 512 or img.get_height() != 3232:
			push_error("Expected %s.png size 512x3232, got %dx%d" % [base, img.get_width(), img.get_height()])
			return false

	return true

# ---------------------------------------------------------------------------
# 6. Level Bands, Familiarity Multipliers, Home Porch & Repel Suppression (§8.7)
# ---------------------------------------------------------------------------
func _test_level_bands_familiarity_porch_and_repel() -> bool:
	var expected_bands := [
		{"miles": 0.5, "band": Vector2i(2, 10)},
		{"miles": 5.0, "band": Vector2i(8, 22)},
		{"miles": 25.0, "band": Vector2i(18, 38)},
		{"miles": 150.0, "band": Vector2i(30, 50)},
		{"miles": 600.0, "band": Vector2i(42, 62)},
		{"miles": 1500.0, "band": Vector2i(55, 75)},
		{"miles": 2500.0, "band": Vector2i(65, 85)},
	]
	for eb in expected_bands:
		var got: Vector2i = SpawnDirector.compute_level_band(float(eb["miles"]), false, "day", 0)
		if got != eb["band"]:
			push_error("Distance %.1f mi expected level band %s, got %s" % [float(eb["miles"]), str(eb["band"]), str(got)])
			return false

	# Night haunted +2 and haunt_stage +2*stage
	var bonus_band: Vector2i = SpawnDirector.compute_level_band(0.5, true, "night", 2)
	if bonus_band != Vector2i(8, 16):
		push_error("Expected night haunted stage-2 band (8, 16), got %s" % str(bonus_band))
		return false

	# Familiarity multipliers
	if EncounterRoller.familiarity_tier_from_days(1) != "known" or absf(EncounterRoller.familiarity_multiplier("known") - 1.00) > 1e-4:
		push_error("Familiarity 'known' multiplier mismatch")
		return false
	if EncounterRoller.familiarity_tier_from_days(5) != "familiar" or absf(EncounterRoller.familiarity_multiplier("familiar") - 0.75) > 1e-4:
		push_error("Familiarity 'familiar' multiplier mismatch")
		return false
	if EncounterRoller.familiarity_tier_from_days(12) != "mastered" or absf(EncounterRoller.familiarity_multiplier("mastered") - 0.50) > 1e-4:
		push_error("Familiarity 'mastered' multiplier mismatch")
		return false

	# Home porch suppression
	var rng := RandomNumberGenerator.new()
	rng.seed = 46006
	var porch_res: Dictionary = EncounterRoller.on_player_step({
		"in_home_porch": true,
		"intrusion_active": false,
		"tile_class": TileSynth2.TILE_TALL_GRASS,
		"repel_steps": 3,
	}, rng)
	if bool(porch_res.get("triggered", false)) or int(porch_res.get("repel_steps_remaining", -1)) != 2:
		push_error("Home porch step should never trigger encounters and should decrement repel_steps")
		return false

	# Repel suppression when rolled.level < lead_party_level (distance 0.5 mi -> lv 2..10, lead_party_level = 30)
	var repelled_count: int = 0
	for i in 200:
		var step_res: Dictionary = EncounterRoller.on_player_step({
			"tile_class": TileSynth2.TILE_TALL_GRASS,
			"explore_days": 1,
			"zone": "wilds",
			"biome": "plains",
			"region": "South Atlantic",
			"distance_miles": 0.5,
			"repel_steps": 10,
			"lead_party_level": 30,
		}, rng)
		if bool(step_res.get("triggered", false)):
			push_error("Repel failed to suppress low-level encounter against Lv 30 lead")
			return false
		if bool(step_res.get("repelled", false)):
			repelled_count += 1
	if repelled_count <= 0:
		push_error("Expected at least 1 repelled encounter across 200 tall-grass steps")
		return false

	return true

# ---------------------------------------------------------------------------
# 7. Distortion Fields Cadence, 5x5 Placement & MapView HUD Chip (§5)
# ---------------------------------------------------------------------------
func _test_distortion_field_cadence_placement_and_hud() -> bool:
	# Default cadence: every 3 days (day 0=true, day 1=false, day 2=false, day 3=true)
	if not DistortionFields.is_field_day(0 * 1440, 2):
		push_error("Day 0 should be a field day")
		return false
	if DistortionFields.is_field_day(1 * 1440, 2) or DistortionFields.is_field_day(2 * 1440, 2):
		push_error("Days 1 and 2 should not be field days at < 6 Anchors")
		return false
	if not DistortionFields.is_field_day(3 * 1440, 2):
		push_error("Day 3 should be a field day at < 6 Anchors")
		return false
	# Escalated cadence at 6+ Anchors: every 2 days (day 2=true)
	if not DistortionFields.is_field_day(2 * 1440, 6):
		push_error("Day 2 should be a field day at 6+ Anchors")
		return false

	var candidates: Array[Vector2i] = [
		Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 11), Vector2i(14, 12)
	]
	var field_info: Dictionary = DistortionFields.get_active_field(
		999,
		3 * 1440 + 360, # 6 hours into Day 3 -> 18 h left
		"city:fixture-city",
		Vector2i(10, 10),
		candidates,
		0
	)
	if not bool(field_info.get("active", false)):
		push_error("Expected active Distortion Field on Day 3 inside city:fixture-city")
		return false
	if int(field_info.get("hours_left", 0)) != 18:
		push_error("Expected 18 hours left, got %d" % int(field_info.get("hours_left", 0)))
		return false
	if str(field_info.get("chip_text", "")) != "Distortion Field — 18 h left":
		push_error("Unexpected chip_text: '%s'" % str(field_info.get("chip_text", "")))
		return false
	var center: Vector2i = field_info["center"]
	var cells: Array[Vector2i] = DistortionFields.get_field_cells(center)
	if cells.size() != 25:
		push_error("Expected 5x5 = 25 Distortion Field cells, got %d" % cells.size())
		return false

	# Verify MapView HUD chip & overlay integration
	var mv: Node2D = MapViewScene.instantiate()
	add_child(mv)
	mv.set_active_distortion_field(field_info)
	if mv.get_distortion_field_chip_text() != "Distortion Field — 18 h left":
		push_error("MapView HUD chip text mismatch: '%s'" % mv.get_distortion_field_chip_text())
		mv.queue_free()
		return false
	mv.set_active_distortion_field({"active": false})
	if mv.get_distortion_field_chip_text() != "":
		push_error("Expected empty MapView HUD chip text after clearing field")
		mv.queue_free()
		return false
	mv.queue_free()

	return true

# ---------------------------------------------------------------------------
# 8. Save Schema Migration 4 Metadata Persistence (§7)
# ---------------------------------------------------------------------------
func _test_db_migration_4_cell_metadata() -> bool:
	DB.configure_paths(TEST_DB_PATH, TEST_DB_PATH + ".tmp")
	if not DB.assert_test_safe():
		push_error("DB.assert_test_safe failed in slice3_encounters_test")
		return false
	DB.init_db()
	if DB.get_schema_version() != DB.CURRENT_SCHEMA_VERSION or DB.get_schema_version() < 4:
		push_error("Expected schema version %d (>= 4), got %d" % [DB.CURRENT_SCHEMA_VERSION, DB.get_schema_version()])
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		return false

	if not DB.upsert_map_cell_metadata(42, 99, "cemetery", "forest", "New England", 2):
		push_error("upsert_map_cell_metadata failed")
		DB.close()
		DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
		return false

	var row: Dictionary = DB.get_map_cell(42, 99)
	DB.close()
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
	if str(row.get("zone", "")) != "cemetery":
		push_error("Expected persisted zone 'cemetery', got '%s'" % str(row.get("zone", "")))
		return false
	if str(row.get("biome", "")) != "forest":
		push_error("Expected persisted biome 'forest', got '%s'" % str(row.get("biome", "")))
		return false
	if str(row.get("region", "")) != "New England":
		push_error("Expected persisted region 'New England', got '%s'" % str(row.get("region", "")))
		return false
	if int(row.get("haunt_stage", -1)) != 2:
		push_error("Expected persisted haunt_stage 2, got %d" % int(row.get("haunt_stage", -1)))
		return false

	return true
