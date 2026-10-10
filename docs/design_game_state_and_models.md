# Game State & Data Models

This document defines the schemas, enums, and persistence rules. **Storage split**: the PC game's SQLite database is the canonical world (all tables below live there); the phone companion holds only a `VisitLog` outbox (rows pending sync) plus pairing state. There is no server. Schema version is stored in `meta` on both devices and every migration is tested against a fixture DB — location history is unrecoverable if a migration eats it. (Enums shown in Dart syntax for readability.) **No table stores Nintendo content** — species, moves, and items are referenced by number; names, stats, and sprites are resolved from the player's ROM cache at runtime (`design_rom_asset_pipeline.md`).

## 0. Storage backends

**The engine is SQLite** (Decision 6 = A), via the vendored `godot-sqlite` v4.4 GDExtension (Decision 7 = B). With the pass-12 SQLite build landed (2026-10-08), the **interim file fallback has been retired**:
- **SQLite only.** Every value is passed as a **bound parameter**, and every getter reads SQL, never memory.
- **Durability:** `PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;`.
- **Missing extension at boot** prints `storage: UNAVAILABLE — SQLite extension missing`, pushes an error, and writes nothing. It never silently degrades.
- **Upsert semantics** (identical to the fallback's — F26):
  - `reveal_state` only ever increases;
  - `first_revealed_at` and `cell_seed` are set once;
  - `place_node.visit_count` accumulates;
  - `sync_peer.last_applied_seq` never decreases.
- **One-time legacy import.** A fallback save is recognised because its first 16 bytes are not `SQLite format 3\0`. It is renamed to `user://tenth_spring.db.jsonbak` (`JSON_BAK_PATH`), imported in one transaction, and kept. It is never deleted. **Any import failure — a failed statement, or a row-count mismatch — rolls back and closes the database for the session** (`storage: UNAVAILABLE — legacy import failed: …`); the backup stays untouched and the next boot retries. An import never runs into a database that already holds `visit_log` or `map_cell` rows (F31). **Order matters (F35):** parse the backup first. If it is unreadable, record `meta('legacy_import', '<file> (unreadable — kept)')` so it is never retried and never blocks a later boot. Only a *readable*, not-yet-imported backup is subject to the rows precondition.

## 1. World Clock (`WorldClock`)

Single-row table driving all simulation.
* File: `game/models/world_clock.dart`
* `gameEpochMinutes` (int): minutes elapsed since world start.
* `lastWallSync` (int): wall epoch ms at last tick, for catch-up on app resume.
* Derived: time-of-day, day count, `isNight` (see `design_travel_and_time.md` §3).
* **Offline rule**: while the app is closed the world clock is *paused* — the simulation only advances during play sessions, except haunting growth, which ticks on app-open catch-up (max 3 ticks).

## 2. Map Cell (`MapCell`)

The fog atom. A cell is a ~256 m square (16×16 tiles at `tileMeters = 16`).
* `cellX`, `cellY` (int): global grid coordinates (Web-Mercator-derived).
* `revealState` (PlaceRevealState): `unknown | known | cleared` — cells use `known` when corridor/visit-revealed; `cleared` is place-level, mirrored here for region queries.
* `tileBlob` (Uint8List): synthesized tile indices (deterministic; regenerable — cache, not source of truth).
* `zone` (SpawnZone): residential / downtown / industrial / retail / parkland / waterfront / institutional / wilds / **cemetery / ruins / hospital**. Selects the spawn pools and base ghost share (`design_encounters_and_haunted_zones.md` §2). Deterministic from OSM.
* `hauntZoneId` (String?): the haunted zone whose territory covers this cell, if any.
* `firstRevealedAt` (int), `worldSeed`-salted `cellSeed` (int).

## 3. Place Node (`PlaceNode`)

An explorable real-world location.
* File: `game/models/place_node.gd`
* `id` (String): stable hash of OSM id (or synthesized for unmapped ruins).
* `name` (String), `category` (PlaceCategory — `design_resources_and_base.md` §1).
* `cellX`, `cellY`, `tileX`, `tileY` (int): position.
* `revealState` (PlaceRevealState).
* `visitCount` (int), `lastRealVisitAt` (int) → derived `intelLevel` (IntelLevel).
* `itemState` (ItemState): `untouched | partial | stripped | regrown` — regrowth is driven by haunting proximity, never by real-world visits.
* `levelTier` (int 0–3): from distance to home (`design_encounters_and_haunted_zones.md` §4).
* `isLandmark` (bool) and `legendaryDex` (int?): the legendary assigned to this landmark, if any.
* `legendaryState` (`{caught, faintedRespawnAtGameDay}`?): null on non-landmark places.

## 4. Player, party, and bag

* File: `game/models/player_profile.gd`
* `trainerName`, `spriteIndex`, `posTileX/Y` — position overwritten on PC session start by the synced `bodyFix` (fast travel — `design_travel_and_time.md` §4).
* `party`: up to 6 `PokemonInstance` ids, in order.
* `bag`: `{pocket, itemIndex, qty}` rows (pockets per `design_resources_and_base.md` §2).
* **Stranded rule:** no code path may read or write `pc_box` for withdrawal or swap while `distanceToHome > baseAccessMeters` (500 m, tunable; distinct from the `homeFuzzMeters` privacy radius). Remote *deposit* of a newly caught Pokémon is always allowed.

## 5. Pokémon instance (`PokemonInstance`)

* File: `game/creatures/pokemon.gd`
* `id`, `dex`, `level`, `exp`, `ivs[6]`, `evs[6]`, `nature`, `ability`, `gender`, `isShiny`.
* `moves`: up to 4 × `{moveId, pp, ppMax}`; `currentHp`; `status`.
* `location`: `party | pc_box`, plus `boxIndex/slot` when boxed.
* `caughtAtCell`, `caughtAtCategory`, `caughtAtGameDay` — the memoir (`design_creatures_and_battles.md` §13). Categories and cells only, never coordinates.

## 6. Home, Pokédex, haunted zones, bag cache

* **Home (`BaseState`)** — `homeCellX/Y` (fuzzed; never raw coordinates), `pcSealed` (bool — stage-4 intrusion, `design_encounters_and_haunted_zones.md` §5.4), garden plots `{plotIndex, berryIndex, plantedAtGameDay}` (max 8).
* **Pokédex** — per dex: `seen`, `caught`, `firstCaughtCell`, `firstCaughtCategory`.
* **Haunted zone (`HauntZone`)** — `id`, `rootPlaceId`, `stage` (0–4), `territoryCells`, `lastGrowthTick`, `bossDex`, `bossDefeated`.
* **Bag cache (`BagCache`)** — `tileX/Y`, `items`, `droppedAtGameDay`. Expires after `bagCacheDecayGameDays = 3`. At most one exists; blacking out again merges into the newest location.

## 8. Visit Log (`VisitLog`)

Append-only real-world evidence table — the memoir. Rows originate on the phone (already fuzzed to 3 decimals ≈ 110 m), sync one hop to the PC (E2E-encrypted, sequence-numbered — `design_companion_and_sync.md` §3), and are acked off the phone's outbox.
* `seq` (int): sync sequence number. `placeId?`, `lat/lon` (fuzzed), `startedAt`, `dwellSeconds`, `kind` (`visit | corridor`).
* Feeds familiarity, the PC-side "intel ceremony" reveal, and the memoir view. Never leaves the paired pair of devices.
