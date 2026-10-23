# Tenth Spring — Master Implementation Plan

The objective is a **Pokémon game, Diamond/Pearl style, set a generation after a collapse, where the map is the places you have actually been.** Two builds: a **phone companion** (an **Explore Here** button and reports to the PC — no tracking, no gameplay, no Nintendo content; Decision 29) and a **PC game** holding everything else — the overworld generated from the player's real geography, main-series battles and catching, Ghost-heavy encounters, haunted zones that spread, and a home safehouse. Pokémon assets come from a ROM the player supplies (`design_rom_asset_pipeline.md`); the repository never contains them. There is no Steam release (pivot of 2026-10-07).

## Core Configurations
All gameplay constants live in `game/config/tuning.json` so balance passes never touch logic. Provisional values — tune in Phase 10:

- **`walkSpeedMph = 15`** — foot speed against *real* geography (`gameMinutesPerMile = 4`); **`bicycleSpeedMultiplier = 2.0`**.
- **`wallSecondsPerGameMinute = 2.0`** — a full in-game day ≈ 48 wall minutes.
- **`tileMeters = 8`** — 8 **Web-Mercator** metres; cells are 32×32 tiles = 256 WM-m (`design_game_state_and_models.md` §2, `implementation_plan_world_generation_slice2.md` §1). On the ground that is 8·cos(latitude) m per tile — ≈ 5.4 m in Seattle. Gameplay distances are always ground metres.
- **Explore Here** (Decision 29): **`exploreMaxAccuracyMeters = 100`** (a fuzzier reading unlocks nothing) and **`exploreTimeLimitSeconds = 10`**. *Retired with background capture:* `visitRadiusMeters`, `visitDwellSeconds`, `captureDistanceFilterMeters`, `captureIntervalMinutes`, `corridorRevealMeters`, `homeFuzzMeters`.
- **`familiarityTiers = {1: known, 3: familiar, 10: mastered}`**, counted in distinct days with an Explore Here report in the area.
- **`baseAccessMeters = 500`** (PC box reach — the stranded rule).
- **`grassEncounterRate = 0.10`** per step; haunted interiors **0.12**.
- **Ghost share:** `clamp(zoneBase · nightMult + 0.10 · hauntStage, 0, 0.80)`; `nightMult` 3.0 night / 1.5 dusk.
- **`hauntGrowthTickGameDays = 1`** (renamed from `colonyGrowthTickGameDays`); **`bagCacheDecayGameDays = 3`** (renamed from `deathCacheDecayGameDays`); ~~`legendaryRespawnGameDays`~~ (retired 2026-10-20: each legendary gets one decisive battle — `design_famous_places.md` §6).
- **Distortion Fields:** `distortionFieldIntervalGameDays = 3` (2 once 6+ Anchors are held), `distortionFieldDurationGameDays = 1`, `distortionFieldRadiusMiles = 10`, `distortionFieldSizeCells = 5`, `distortionFieldForeignShare = 0.40` (`design_encounters_and_haunted_zones.md` §3a).
- **Named battles — fixed levels, never relative** (Decision 35):
  - Wardens **75** (rematch **90**);
  - city survivors **50** (rematch **80**);
  - **the finale:** the Echo mirrors the party at +5 levels, capped at 100 — and at 100 it's stronger by build: perfect IVs, competitive EVs, natures, abilities, items, and movesets (`design_long_game.md` §4.3).
- **Weariness** (Decision 35): `staminaMax = 100`, `staminaBattleCost = 4`, `staminaFaintCost = 10`, `staminaWearyBelow = 40`, `staminaWaypostBedRestore = 50`.
- **Mega Evolution** (Decision 36): one per battle, with the Walker's Keystone; 47 Mega Stones.
- **`partySize = 6`**; PC box 18 × 30; berry garden 8 plots; **shiny rate 1/8192**.
- **The same map for everyone:** `MAP_SNAPSHOT = 2026-10-01` (the pinned OpenStreetMap snapshot) and `MAP_SEED = 0` (the global map-drawing seed) — `design_famous_places.md` §7.
- **Data locality:** no location trace exists anywhere. The phone keeps only the names of the areas you explored, and the PC keeps the map. Reports go directly device-to-device (E2E). No account, no server.

## Phase order (dependency order — do not skip ahead)

**Phase 0 — Companion: Explore Here** *(rebuilt by Decision 29, 2026-10-21 — agent guide Items 26–27; the background-capture build and its battery soak are retired)*
One tap of Explore Here, checked against the bundled places pack, tells the player what they unlocked and queues one explore event; nothing else is ever recorded. `implementation_plan_explore_here.md`. **Exit:** on a real phone, Explore Here gives the right answer inside and outside a famous place, the app holds only "While Using" location access, and neither device stores a coordinate.

**Phase 1 — Pairing, sync & data models** *(built, hardened & CI-verified — pass-13 fixes F29–F34 landed; only the human's real-device sync gate remains — ready now that F42 (grid) and F40 (macOS SQLite) have landed; see the agent guide §2)*
A report of explored areas lands as `visit_log` rows + `known` cells on the PC after one LAN report (protocol v3 since Decision 29 — Item 28); persistence survives quit-and-relaunch. **Status:** All code delivered across Item 2 (real SQLite persistence, WAL, bound parameters) and Item 3a–c (pinned TLS listener, QR generator, pairing tokens, frame codec, scout reports, and cross-language loopback sync in CI). Verified in CI (`sync_e2e`, `game_tests`, `Public-Repo IP Guard`). **Exit:** real-device sync over pinned TLS (Decision 11), replay is a no-op, Wireshark shows only TLS records (pending human testing on physical phone + PC).

**Phase 2 — ROM asset importer (BYOR)** *(new; gates every Pokémon-facing phase)*
Import a player-supplied Pokémon Black or White ROM (the #1–649 battle sprites; Decision 10 = B), plus — on the player's machine — the data pack for all 905 Gen 1–8 species (PokéAPI) and the Smogon Sprite Project's fan sprites for #650–905 (Decision 32) — and, for the map's tiles, a Pokémon Emerald ROM (Decision 19) — into `user://rom_cache/`: verify, parse the NDS filesystem, extract and decode sprites, species, moves, learnsets, evolutions, items, icons, and text. Includes the repo guard script. Contract: `design_rom_asset_pipeline.md`. **Exit:** the §7 import validation passes on a real dump, and the guard fails CI if any Nintendo-format file is tracked.

**Phase 3 — World generation** *(slices 1 and 2 **built** (pass 17); corrections (Items 13–16) and famous-places architecture (Items 17–22, 21) **fully built and verified**. The map is famous places only (Decisions 25–26): 27 cities and 36 parks and wonders, unlocked per neighbourhood, city, and park, with Distort from a home hub and the same map for everyone — `implementation_plan_famous_places.md`, real-data proof in DC verified. Real map tiles come from the player's Emerald ROM (Decision 19).)*
Offline OSM extracts from one pinned snapshot (Decisions 13, 23), converted per famous place (Decision 25) → deterministic tile overworld assembled from walking-scale Pokémon pieces: spawn zones (incl. cemetery/ruins/hospital), **tall-grass placement**, the **ruin pass** (Decision 30 — fewer houses, broken homes, overgrown streets; slice-2 plan §11), gilded enterable landmarks, two-fog rendering, and the intel ceremony. Areas come from the shared places pack (Item 26). Contract: `design_world_generation.md`. **Exit:** identical tiles from `(cached OSM, cellSeed)` across runs; tall grass appears where the rules say.

**Phase 4 — Travel, time & fast travel** *(partly pre-built — extend, don't rewrite)*
World clock, day/dusk/night bands, travel charged in game-time, bicycle, resuming where the last session ended, **Distort travel between home and famous places, the home hub, and Waypost returns** (`design_famous_places.md` §2–§4), stranded rule on the PC box. Contract: `design_travel_and_time.md`. **Exit:** a 12-mile destination reports ~48 min on foot (~24 by bicycle) and charges the clock accordingly.

**Phase 5 — Creatures & battle engine**
*Generation 8 rules (Decision 32): the Fairy type and the Gen 6+ chart. The long-game rules wait on Decision 35 (`design_long_game.md`), and the gimmicks on Decision 36.*
Instances, stats, natures, IVs/EVs, the type chart, damage, status, v1 move effects and abilities, AI, EXP, growth curves, evolution. Contract: `design_creatures_and_battles.md`. **Exit:** formula unit tests pass (damage, catch, growth totals, type-chart cells); a full wild battle runs headless end to end.

**Phase 6 — Encounters & catching**
Per-step encounter rolls, spawn pools with biome and region rules (Decision 18), Distortion Fields, ghost-share formula, level bands, the catch formula and balls (incl. Dusk Ball), party and PC box, Pokédex and its completion rule. Contract: `design_encounters_and_haunted_zones.md` §1–4 and §7.2. **Exit:** at night in a cemetery ≥ 75% of 1,000 simulated encounters are haunted-pool draws; by day in a suburb ≤ 10%; a region-only species never appears outside its region except inside a Distortion Field; no legendary or mythical ever comes from a field.

**Phase 7 — Exploration, interiors & side quests**
Famous interiors (each with a purpose) and haunted interiors; the Pokémon-style puzzle kinds; doorway searching for ordinary buildings; the side-quest engine, the Walker's Journal, and the quest content (Truth quests, key-item quests, city and park quests, the Lost Postcards); familiarity effects, home-only healing, blacking out and bag recovery, the berry garden. Contracts: `design_interiors_and_quests.md`, `design_expeditions_and_survival.md`, `design_resources_and_base.md`. **Exit:** a famous interior can be entered and cleared via its puzzles; a Truth quest runs end to end and adds its Calder log; blacking out drops a recoverable bag while Pokémon, map, and PC survive.

**Phase 8 — Haunted zones & legendaries**
Seeding, growth, intrusion and PC sealing, zone bosses and cleansing, real-world-gated events (Spiritomb, Rotom), the 82 legendaries and mythicals at their 78 famous places behind challenges (one decisive battle each), the nine Warden trials (gated on unlocking each region's three cities), the regions' survivor trainers, and the Echo finale (Decisions 18, 26; `design_famous_places.md`, `design_story_and_world.md`). Contracts: `design_encounters_and_haunted_zones.md` §5–7, `design_famous_places.md` §5–6, `design_interiors_and_quests.md` (lairs inside buildings). **Exit:** an ignored zone grows until it seals the PC; beating its boss cleanses it; a landmark legendary is unique per save.

**Phase 9 — Art & UI pass**
Replace programmer art with original tiles, UI, battle backgrounds, and shaders (distortion tint); ROM sprites render via `asset_db`. Contract: `design_art_direction.md`. **Exit:** no placeholder art in the main zones; every original asset passes the rip-trap check.

**Phase 10 — Privacy hardening, balance & release**
Onboarding (ROM import + pairing), privacy audits, export/erase on both devices, balance pass, release of the asset-free client via GitHub Releases and the IP-free companion to the app stores. Contract: `design_privacy_and_location.md`, `design_rom_asset_pipeline.md` §9. **Exit:** both device gates pass on release builds; a fresh machine with no ROM runs in "no ROM" mode, and importing a valid dump unlocks Pokémon content.

---

## System status
> [!NOTE]
> 2026-10-07: Pokémon pivot. Phases 0–1 carry over unchanged (theme-agnostic). Phases 2–10 are scope only — each needs its own `implementation_plan_<phase>.md`, written and human-reviewed, before coding starts (agent guide, THE LOOP step 2).
