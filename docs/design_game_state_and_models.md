# Game State & Data Models

This document defines the schemas, enums, and persistence rules. **Storage split**: the PC game's SQLite database is the canonical world (all tables below live there); the phone companion holds only a `VisitLog` outbox (rows pending sync) plus pairing state. There is no server. Schema version is stored in `meta` on both devices and every migration is tested against a fixture DB — location history is unrecoverable if a migration eats it. (File paths are engine-neutral pending Decision 1; enums shown in Dart syntax for readability.)

## 1. World Clock (`WorldClock`)

Single-row table driving all simulation.
* File: `game/models/world_clock.dart`
* `gameEpochMinutes` (int): minutes elapsed since world start.
* `lastWallSync` (int): wall epoch ms at last tick, for catch-up on app resume.
* Derived: time-of-day, day count, `isNight` (see `design_travel_and_time.md` §3).
* **Offline rule**: while the app is closed the world clock is *paused* — the simulation only advances during play sessions, except colony growth which ticks on app-open catch-up (max 3 ticks).

## 2. Map Cell (`MapCell`)

The fog atom. A cell is a ~256 m square (16×16 tiles at `tileMeters = 16`).
* `cellX`, `cellY` (int): global grid coordinates (Web-Mercator-derived).
* `revealState` (PlaceRevealState): `unknown | known | cleared` — cells use `known` when corridor/visit-revealed; `cleared` is place-level, mirrored here for region queries.
* `tileBlob` (Uint8List): synthesized tile indices (deterministic; regenerable — cache, not source of truth).
* `biome` (Biome): dominant land-use biome (residential/downtown/industrial/retail/parkland/waterfront/institutional/wilds); selects the enemy variant skins spawned here (`design_threats_and_colonies.md` §1.1). Deterministic from OSM.
* `firstRevealedAt` (int), `worldSeed`-salted `cellSeed` (int).

## 3. Place Node (`PlaceNode`)

A raid-able real-world location.
* File: `game/models/place_node.dart`
* `id` (String): stable hash of OSM id (or synthesized for unmapped ruins).
* `name` (String), `category` (PlaceCategory): see resource table.
* `cellX`, `cellY`, `tileX`, `tileY` (int): position.
* `revealState` (PlaceRevealState).
* `visitCount` (int), `lastRealVisitAt` (int) → derived `intelLevel` (IntelLevel).
* `lootState` (LootState): `untouched | partial | stripped | regrown` — loot regrowth is slow and driven by colony proximity, never by real-world visits.
* `dangerTier` (int 1–5): computed from distance-to-home, urban density, colony proximity (see `design_threats_and_colonies.md`); `landmark` sites are fixed at 5.
* `isLandmark` (bool): famous-place flag (national park, monument, stadium…). When true, `bossState` is populated.
* `bossState` (BossState?): `{bossId, defeated, respawnAtGameDay}` — the fixed, non-spreading landmark apex and its long-cooldown respawn. Null on non-landmark places.

A cell's `Biome` (residential/downtown/industrial/retail/parkland/waterfront/institutional/wilds) lives on `MapCell` (§2) and selects the enemy variant skins spawned in that cell.

## 4. Player Profile & Inventory

* File: `game/models/player_profile.dart`
* `survivorName`, `spriteIndex`.
* `posTileX/Y` (int): current overworld position. On PC session start, overwritten by the synced `bodyFix` relocation (fast travel — `design_travel_and_time.md` §4).
* `hp`, `stamina` (int), `carryCapacity` (int).
* `carried` (List<InventoryItem>): the *only* inventory that travels. `InventoryItem = {itemId, qty, quality}`.
* **Stranded rule**: no code path may read `BaseState.stash` while `distanceToHome > baseAccessMeters` (500 m, tunable; distinct from the `homeFuzzMeters` privacy radius).

## 5. Base State (`BaseState`)

* File: `game/models/base_state.dart`
* `homeCellX/Y` (fuzzed — never raw home coordinates).
* `stash` (List<InventoryItem>): unlimited-slot home storage.
* `fortifications` (Map<FortificationType, int>): walls, barricades, watchpost, workshop, garden levels.
* `vehicles` (List<Vehicle>): `{type, fuelUnits, condition}`.

## 6. Colony State (`ColonyState`)

* File: `game/models/colony_state.dart`
* `id`, `rootPlaceId` (String): the POI the hive rooted in.
* `stage` (int 1–4): nest → hive → warren → dominion.
* `territoryCells` (List<(int,int)>): cells under colony influence.
* `lastGrowthTick` (int, game days), `apexTier` (int): boss power.
* `raidPressure` (double): accumulates with stage + proximity to home; crossing threshold schedules a base-raid event.

## 7. Death Cache (`DeathCache`)

* `id`, `tileX/Y`, `items` (List<InventoryItem>), `droppedAtGameDay` (int).
* Expires after `deathCacheDecayGameDays` (3): items are lost to scavengers. At most one cache exists; dying again merges caches at the newest site.

## 8. Visit Log (`VisitLog`)

Append-only real-world evidence table — the memoir. Rows originate on the phone (already fuzzed to 3 decimals ≈ 110 m), sync one hop to the PC (E2E-encrypted, sequence-numbered — `design_companion_and_sync.md` §3), and are acked off the phone's outbox.
* `seq` (int): sync sequence number. `placeId?`, `lat/lon` (fuzzed), `startedAt`, `dwellSeconds`, `kind` (`visit | corridor`).
* Feeds familiarity, the PC-side "intel ceremony" reveal, and the memoir view. Never leaves the paired pair of devices.
