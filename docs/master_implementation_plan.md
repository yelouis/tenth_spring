# Tenth Spring — Master Implementation Plan

The objective is a **Pokémon game, Diamond/Pearl style, set a generation after a collapse, where the map is the places you have actually been.** Two builds: a **phone companion** (passive location capture + sync — no gameplay, no Nintendo content) and a **PC game** holding everything else — the overworld generated from the player's real geography, main-series battles and catching, Ghost-heavy encounters, haunted zones that spread, and a home safehouse. Pokémon assets come from a ROM the player supplies (`design_rom_asset_pipeline.md`); the repository never contains them. There is no Steam release (pivot of 2026-10-07).

## Core Configurations
All gameplay constants live in `game/config/tuning.json` so balance passes never touch logic. Provisional values — tune in Phase 10:

- **`walkSpeedMph = 15`** — foot speed against *real* geography (`gameMinutesPerMile = 4`); **`bicycleSpeedMultiplier = 2.0`**.
- **`wallSecondsPerGameMinute = 2.0`** — a full in-game day ≈ 48 wall minutes.
- **`tileMeters = 16`**; cells are 16×16 tiles ≈ 256 m.
- **`visitRadiusMeters = 75`**, **`visitDwellSeconds = 120`** — thresholds for a real-world visit.
- **`captureDistanceFilterMeters = 25`**, **`captureIntervalMinutes = 2`**, accuracy **`medium`** — the **battery-budget levers**. Change only with a fresh device measurement.
- **`corridorRevealMeters = 60`**; **`familiarityTiers = {1: known, 3: familiar, 10: mastered}`**.
- **`homeFuzzMeters = 300`** (privacy) and **`baseAccessMeters = 500`** (PC box reach — the stranded rule). Distinct; never conflate them.
- **`grassEncounterRate = 0.10`** per step; haunted interiors **0.12**.
- **Ghost share:** `clamp(zoneBase · nightMult + 0.10 · hauntStage, 0, 0.80)`; `nightMult` 3.0 night / 1.5 dusk.
- **`hauntGrowthTickGameDays = 1`** (renamed from `colonyGrowthTickGameDays`); **`bagCacheDecayGameDays = 3`** (renamed from `deathCacheDecayGameDays`); **`legendaryRespawnGameDays = 30`**.
- **`partySize = 6`**; PC box 18 × 30; berry garden 8 plots; **shiny rate 1/8192**.
- **Data locality:** location traces and map state live only on the player's phone + PC; sync is direct device-to-device (E2E). No account, no server.

## Phase order (dependency order — do not skip ahead)

**Phase 0 — Companion capture & scout ledger** *(code-complete; device gate pending)*
Carrying the phone yields a fuzzed visit/corridor log within budget. **Exit:** ledger fills while backgrounded over ≥ 8 h at < 3%/day on a real device.

**Phase 1 — Pairing, sync & data models** *(partial — the active queue)*
A day of scouting lands as `visit_log` rows + `known` cells on the PC after one LAN sync; persistence survives quit-and-relaunch. **Exit:** real-device sync, replay is a no-op, Wireshark shows ciphertext only.

**Phase 2 — ROM asset importer (BYOR)** *(new; gates every Pokémon-facing phase)*
Import a player-supplied Platinum ROM into `user://rom_cache/`: verify, parse the NDS filesystem, extract and decode sprites, species, moves, learnsets, evolutions, items, icons, and text. Includes the repo guard script. Contract: `design_rom_asset_pipeline.md`. **Exit:** the §7 import validation passes on a real dump, and the guard fails CI if any Nintendo-format file is tracked.

**Phase 3 — World generation**
OSM → deterministic tile overworld: spawn zones (incl. cemetery/ruins/hospital), **tall-grass placement**, landmark flagging with legendary assignment, two-fog rendering, and the intel ceremony. Contract: `design_world_generation.md`. **Exit:** identical tiles from `(cached OSM, cellSeed)` across runs; tall grass appears where the rules say.

**Phase 4 — Travel, time & fast travel** *(partly pre-built — extend, don't rewrite)*
World clock, day/dusk/night bands, travel charged in game-time, bicycle, session-start relocation, stranded rule on the PC box. Contract: `design_travel_and_time.md`. **Exit:** a 12-mile destination reports ~48 min on foot (~24 by bicycle) and charges the clock accordingly.

**Phase 5 — Creatures & battle engine**
Instances, stats, natures, IVs/EVs, the Gen IV type chart, damage, status, v1 move effects and abilities, AI, EXP, growth curves, evolution. Contract: `design_creatures_and_battles.md`. **Exit:** formula unit tests pass (damage, catch, growth totals, type-chart cells); a full wild battle runs headless end to end.

**Phase 6 — Encounters & catching**
Per-step encounter rolls, spawn pools, ghost-share formula, level bands, the catch formula and balls (incl. Dusk Ball), party and PC box, Pokédex. Contract: `design_encounters_and_haunted_zones.md` §1–4. **Exit:** at night in a cemetery ≥ 75% of 1,000 simulated encounters are haunted-pool draws; by day in a suburb ≤ 10%.

**Phase 7 — Exploration & survival**
Site interiors, searching for items by category, haunted interiors, familiarity effects, home-only healing, blacking out and bag recovery, berry garden. Contracts: `design_expeditions_and_survival.md`, `design_resources_and_base.md`. **Exit:** a site can be explored and left; blacking out drops a recoverable bag while Pokémon, map, and PC survive.

**Phase 8 — Haunted zones & legendaries**
Seeding, growth, intrusion and PC sealing, zone bosses and cleansing, real-world-gated events (Spiritomb, Rotom), landmark legendaries, the Giratina arc. Contract: `design_encounters_and_haunted_zones.md` §5–7. **Exit:** an ignored zone grows until it seals the PC; beating its boss cleanses it; a landmark legendary is unique per save.

**Phase 9 — Art & UI pass**
Replace programmer art with original tiles, UI, battle backgrounds, and shaders (distortion tint); ROM sprites render via `asset_db`. Contract: `design_art_direction.md`. **Exit:** no placeholder art in the main zones; every original asset passes the rip-trap check.

**Phase 10 — Privacy hardening, balance & release**
Onboarding (ROM import + pairing), privacy audits, export/erase on both devices, balance pass, battery profiling, release of the asset-free client via GitHub Releases and the IP-free companion to the app stores. Contract: `design_privacy_and_location.md`, `design_rom_asset_pipeline.md` §9. **Exit:** both device gates pass on release builds; a fresh machine with no ROM runs in "no ROM" mode, and importing a valid dump unlocks Pokémon content.

---

## System status
> [!NOTE]
> 2026-10-07: Pokémon pivot. Phases 0–1 carry over unchanged (theme-agnostic). Phases 2–10 are scope only — each needs its own `implementation_plan_<phase>.md`, written and human-reviewed, before coding starts (agent guide, THE LOOP step 2).
