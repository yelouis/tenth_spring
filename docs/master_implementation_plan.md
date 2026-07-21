# Tenth Spring v1.0 — Master Implementation Plan

The objective is to implement the core Tenth Spring loop across two builds: a **phone companion app** (passive location capture + sync — no gameplay) and the **PC game for Steam** holding everything else — the pixel-art overworld generated from the player's real geography, the survival layer where all resources are earned by physically-slow expeditions, the living threat ecology (zombie tiers + colonies), and the safehouse economy — all under the two-fog / cartography-never-cargo pillars in `README.md`.

## Core Configurations
All gameplay constants live in one PC-side config file (`game/config/tuning`) so balance passes never touch logic. Provisional values — tune in Phase 8:

- **`walkSpeedMph = 15`** — survivor foot speed measured against *real* geography. Derived: `gameMinutesPerMile = 4`.
- **`wallSecondsPerGameMinute = 2.0`** — world-clock dilation. A full in-game day ≈ 48 wall minutes.
- **`tileMeters = 16`** — one overworld tile ≈ 16 m of real ground (see `design_world_generation.md`).
- **`visitRadiusMeters = 75`**, **`visitDwellSeconds = 120`** — thresholds for a real-world "visit" that reveals a place.
- **`corridorRevealMeters = 60`** — width of map revealed along traveled routes.
- **`familiarityTiers = {1: known, 3: familiar, 10: mastered}`** — real-visit counts → intel level.
- **`homeFuzzMeters = 300`** — safehouse coordinates snapped/offset for privacy.
- **`deathCacheDecayGameDays = 3`** — how long a dropped death cache persists before scavengers claim it.
- **`colonyGrowthTickGameDays = 1`** — colony expansion cadence.
- **Data locality**: all location traces and map state live on the player's phone + PC only; sync is direct device-to-device (E2E). No account, no server, no cloud relay in v1.0.

## Phase 0: Companion Capture & Scout Ledger (phone)
**Goal:** Prove the passive pipeline — phone movement becomes a visit log — before any game exists.
- **Background Geolocation**
  - Integrate significant-location-change + geofence strategy (battery budget: <3%/day; see `design_privacy_and_location.md`).
  - Implement visit detection (`visitRadiusMeters` + `visitDwellSeconds`) and corridor traces; fuzzing at source.
- **Scout Ledger**
  - Persist the visit outbox in Drift; render the ledger (names + counts only) and a debug polygon map behind a dev flag.
- **Exit criterion:** carry the phone for a normal day → open the companion → see the day's detected visits listed, at <3%/day battery attribution.

## Phase 1: Pairing, Sync & Data Models (phone ↔ PC)
**Goal:** Stand up the PC project, the canonical schemas, and the bridge between devices.
- **PC skeleton** — engine project (per Decision 1), SQLite store, every schema in `design_game_state_and_models.md` with serialization round-trip tests.
- **Pairing + Sync** — QR pairing, mDNS discovery, E2E-encrypted resumable batches, `bodyFix`, ack/outbox flow per `design_companion_and_sync.md`.
- Migration framework on both devices from day one (schema version column) — location history is unrecoverable if a migration eats it.
- **Exit criterion:** a day of real scouting on the phone appears as `VisitLog` rows + fog cells in the PC database after one LAN sync; replayed batches are no-ops.

## Phase 2: World Generation (PC)
**Goal:** Turn real geography into the tile overworld.
- **OSM Ingestion** — Overpass queries for POIs + street/park/water geometry inside revealed cells; cache responses locally.
- **Intel Ceremony** — the sync-time reveal moment: fog peels, place chips stamp in, the day's route draws itself (this is the game's loot-box beat; phone shows names only).
- **POI → Place mapping** — apply the category table in `design_resources_and_base.md` (grocery→food, pharmacy→meds, hardware→parts, gas→fuel, home→safehouse).
- **Tile Synthesis** — deterministic real-geometry → tile-grid conversion (`tileMeters`), D/P-style autotiling (grass/road/water/tree/building edges).
- **Two-Fog Rendering** — Unknown (black), Known (grey silhouette + "?" chip), Cleared (full color).

## Phase 3: Travel, Time & Fast Travel
**Goal:** Make distance expensive and the real body the only teleporter.
- World clock with `wallSecondsPerGameMinute`; day/night tint + danger multiplier.
- Route travel consuming game-time at `walkSpeedMph` over real distance; destination picker shows travel-time ("Elm St. pharmacy — 38 min on foot").
- Session-start relocation: spawn survivor at the synced `bodyFix` position, with the "scout out of contact" fallback (the *stranded* rule applies — carried inventory only).

## Phase 4: Expeditions & Loot
**Goal:** The moment-to-moment raid loop (see `design_expeditions_and_survival.md`).
- Site maps (interiors) generated per PlaceNode; scavenge/noise/extract loop; loot tables by POI category.
- Familiarity effects: mastered places start with interior pre-mapped and reduced ambush rolls.
- Death: drop `DeathCache` at the death site; map/knowledge persist; recovery runs.

## Phase 5: Threats & Colonies
**Goal:** A world that pushes back (see `design_threats_and_colonies.md`).
- Shambler / Stalker / Brute tiers; power scaling by distance-from-home, urban density, and night.
- Colony lifecycle: seed in dense POIs → grow on `colonyGrowthTickGameDays` → spill into cleared cells → raid the safehouse.
- Colony assault dungeons: apex zombie, region pacification reward.

## Phase 6: Base & Resource Economy
**Goal:** Give all that loot somewhere to matter.
- Safehouse stash, fortification upgrades, crafting recipes, vehicle + fuel system (fuel = reach).
- Base-defense encounter triggered by colony raids.

## Phase 7: Art Pass
**Goal:** Replace programmer art with the licensed/commissioned pixel set per `design_art_direction.md` spec (32 px tiles, locked palette, 4-direction walk cycles).

## Phase 8: Privacy Hardening, Balance & Release
**Goal:** Ship-ready on both storefronts.
- Permission onboarding + pairing flow polish, home fuzzing audit, sync-encryption audit, data-export/delete controls on both devices.
- Balance pass over every tuning constant; battery profiling; Steam page + companion app store listings (companion is free; the game is the product).

---

## System Status
> [!NOTE]
> Design phase — nothing implemented. Every phase above is open. First engineering session starts at Phase 0.
