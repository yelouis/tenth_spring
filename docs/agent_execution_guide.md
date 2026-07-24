# Agent Execution Guide — Active Build: Foundation Completion (verified 2026-07-22, pass 4)

**You are an engineering agent picking up Tenth Spring with zero prior context.** Two builds: a PC game (**Godot 4**, `game/`, canonical world DB) and a thin phone companion (**Flutter**, `companion/`, capture + sync only). The PC holds all gameplay; the phone is never a place to play.

**What is approved for build right now:** the three queued items in §2, in that order. **What NOT to touch:** everything in §8 (already delivered), §9 (accepted equivalents), and §10 (intentional decisions). §7 is the full phase roadmap — it is *scope*, not an approved queue; do not start a phase from it without writing that phase's implementation plan first (see §7's rule).

**Specs are decisions, not suggestions.** Every number, constant, and literal string below is deliberate — implement as written; do not substitute your own values. If a value is genuinely impossible, keep the *intent*, deviate minimally, and note it in the commit body. If the design itself cannot work, **STOP and file it in `docs/ongoing_general_errors.md` with options for the human — do not improvise.**

**Standing constraints (apply to every item):**
- Every change must leave the §1 battery green. That battery is the regression bar.
- Anything touching location capture, battery, or cross-device sync **requires a real-device check**. A simulator or desktop never validates these.
- The two golden invariants (§10) must stay green, always.
- Detailed system behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps). This guide points at them; it does not restate them.
- One item = one Conventional Commit, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item, not afterwards.

---

## 1. Verified baseline (run this session, 2026-07-22)

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **12/12 passed** |
| Game static audit | `python3 game/tests/test_runner.py` (from repo root) | **Lint pass; Golden Invariant 1 guard intact** |
| Game runtime tests | `godot --headless` | ⚠️ **NOT EXECUTED — Godot is not installed here.** `db_test.gd`, `idempotent_sync_test.gd`, `sync_ingest_isolation_test.gd` are verified by reading only. Never report a game-side runtime pass without installing Godot. |
| D3 device gate | 8 h background soak on a real phone | ⚠️ **NOT YET RUN — scheduled.** Decision 5 = **Option A**: run immediately after Item 1 (§3) lands. Phase 0 stays open until it passes. |

Do not regress these numbers.

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 1 | **D3 closeout — F8 + F9** (companion) | Small, and **F9 must land before the device soak**: if Android never actually grants background permission, an 8-hour carry proves nothing and wastes the human's day. F8 is the test that would have caught F9's class of bug. |
| — | **▶ HUMAN: run the D3 device soak** | Decision 5 Option A. Fires the moment Item 1 lands. Blocks closing Phase 0. If the <3%/day target fails, escalate to D3 Option A (Transistorsoft) **before** building further on the capture strategy. |
| 2 | **F4 — real SQLite store** (game) | Must precede #3: building transport against the in-memory stub means re-plumbing every DB call afterwards. Also converts #3's transactions from decorative to real. Its blast radius is already pre-cleared (accessors landed). |
| 3 | **D4 — secure transport** (both) | Depends on #2's real store. Largest item; land it on a stable foundation. Closes Phase 1. |

Deferred (trigger-gated, **do not start**): **F7** — see §6.

---

## 3. Item 1 — D3 closeout (F8 + F9)

**What this means for the user:** on Android the app can look perfectly configured and still never scout in the background — the map silently stops growing, which is the whole product. And the test suite currently can't tell you that.

### The gap
- **F8** — `companion/test/os_location_source_test.dart:15-26` branches on `defaultTargetPlatform`. On a macOS CI host that resolves to `macOS`, so the test takes the Apple branch and the **Android assertions never execute**. The foreground-service config is unverified despite a green suite.
- **F9** — `companion/lib/capture/os_location_source.dart:80-86` escalates to background by calling `Geolocator.requestPermission()` a second time when the grant is `whileInUse`. On **Android 11+ that call does not grant `ACCESS_BACKGROUND_LOCATION`** — the user must be sent to app settings. The manifest is correct, but the runtime grant never arrives, so background capture may never engage.

### Implementation
1. Rewrite the platform test to drive both branches explicitly with `debugDefaultTargetPlatformOverride`, resetting to `null` in `tearDown`. Assert the full spec, not just presence:
   - **Android:** `foregroundNotificationConfig` non-null · `notificationTitle == 'Tenth Spring'` · `notificationText == 'Scouting your map'` · `enableWakeLock == false` · `intervalDuration == Duration(minutes: 2)` · `distanceFilter == 25` · `accuracy == LocationAccuracy.medium`.
   - **iOS:** `allowBackgroundLocationUpdates == true` · `pauseLocationUpdatesAutomatically == true` · `showBackgroundLocationIndicator == false` · `activityType == ActivityType.other` · same filter/accuracy.
2. Add a real Android background-permission flow: once `whileInUse` is granted, show a short rationale, then call `Geolocator.openAppSettings()`. On app resume, re-check `Geolocator.checkPermission()` and record whether `always` was granted.
3. **Never block the app on this.** If background is refused, degrade to while-in-use + the manual "scout here" path (`design_privacy_and_location.md` §2 — "Always is the enhancement, never the wall").
4. Surface the resulting state in the scout ledger — a one-line banner such as `Background scouting off — tap to enable` — so a user whose grant silently failed can see it rather than wondering why the map stopped growing.
5. Do **not** change accuracy, `distanceFilter`, or `intervalDuration`. Those three are the battery-budget levers (master plan Core Configurations).

### Validation
- **Automated (fails today, proving the fix landed):** with `debugDefaultTargetPlatformOverride = TargetPlatform.android`, assert `buildLocationSettings()` returns `AndroidSettings` with every field above. On a macOS host this branch currently never runs at all.
- **Automated:** the same for the iOS branch.
- **Automated:** `flutter analyze` → 0 issues; `flutter test` → ≥13 passing.
- **Manual (Android 11+ device):** grant only "While using the app". Confirm the rationale appears and routes to settings; after granting "Allow all the time", confirm the ledger gains entries with the app **backgrounded**.

### Blast radius (same commit)
`companion/test/os_location_source_test.dart` · `companion/lib/capture/os_location_source.dart:80-86` · `companion/lib/ui/scout_ledger_screen.dart` (permission banner) · F8/F9 + the D3 status in `ongoing_general_errors.md`.

**On completion:** notify the human that the device soak (Decision 5) is now unblocked.

---

## 4. Item 2 — F4: real SQLite store

**What this means for the user:** today, closing the game erases the entire map they walked. This is the difference between a demo and a save file.

### The gap
- `game/autoloads/db.gd:8-17` — every table is an in-RAM Godot `Dictionary`. Nothing survives a restart.
- `game/autoloads/db.gd:29-30` — `init_db()` only writes a version string; there is no DDL and no migration runner.
- `game/autoloads/db.gd:35-55` — "transactions" deep-copy four dictionaries and restore them on rollback. That is not durability.
- The §B2 DDL and §B6 migration framework in `implementation_plan_foundation.md` are unrealized.

*Already pre-cleared:* `db.gd:130,133` now expose `get_base_state()` / `set_player_tile()`, and `relocation_manager.gd` no longer reaches into private stores — the caller churn this item used to imply is gone.

### Implementation
1. Add a SQLite GDExtension (per Decision 4 tooling: a maintained binding if one exists, else wrap it yourself). **Record which you chose on Decision 4.**
2. Open the DB at `user://tenth_spring.db`. Implement the §B2 DDL exactly — `meta`, `world_clock`, `map_cell`, `place_node`, `visit_log`, `sync_peer`, `player_profile`, `base_state`, `inventory_item`, `osm_cache`. `visit_log` **must** keep `PRIMARY KEY (peer_id, seq)`: that composite key *is* the idempotency guarantee.
3. Implement the §B6 migration runner keyed on `meta.schema_version` — ordered, idempotent, never destructive to `visit_log` or `map_cell`.
4. Port every existing public method with **unchanged signatures** (`get_map_cell`, `upsert_map_cell`, `get_place_node`, `upsert_place_node`, `is_visit_logged`, `insert_visit_log`, `get_sync_peer`, `update_sync_peer`, `get_base_state`, `set_player_tile`, `get_schema_version`).
5. Replace snapshot transactions with real `BEGIN` / `COMMIT` / `ROLLBACK`.
6. Remove the `simulateFailure` test hook from `game/autoloads/sync_server.gd:44,54-56` and drive the rollback test with a real injected DB failure instead — a flag read from live request data does not belong in a production path.

### Validation
- **Automated — persistence (fails against today's in-memory store, proving the change):** write a `map_cell`, close the DB, reopen it, assert the row survives.
- **Automated:** schema round-trip — insert one row per table, read back identical.
- **Automated:** migration fixture — open a v0 fixture DB, run migrations, assert `schema_version == 1` and **zero `visit_log` rows lost**.
- **Automated:** `idempotent_sync_test.gd` still passes under real transactions (replay ⇒ `appliedCount == 0`; injected failure ⇒ no state persisted).
- **Manual:** run `godot --headless` once and confirm `test_runner.py` reports **executed** runtime tests instead of the "Godot not found" note.

### Blast radius (same commit)
`game/autoloads/sync_server.gd:44,54-56` · `game/tests/db_test.gd` · `game/tests/idempotent_sync_test.gd`.

---

## 5. Item 3 — D4: secure transport, both sides

**What this means for the user:** this is the moment the two halves become one product. Until it exists, walking around never reaches the game.

### The gap
- **No `companion/lib/sync/` directory exists** — no pairing, no transport, no mDNS client.
- `game/autoloads/sync_server.gd` is a pure in-process function; `process_batch()` is only ever called directly by tests. No TCP listener, no mDNS advertisement, no encryption anywhere.
- Dependencies are installed but unused: `multicast_dns`, `cryptography`, `mobile_scanner`, `flutter_secure_storage`.
- `design_companion_and_sync.md` §2–3 is unimplemented, and the "exactly one E2E-encrypted hop" privacy contract is untested.

### Implementation
1. **Wire-compatibility spike FIRST.** Prove Dart `cryptography` and the chosen Godot libsodium binding agree — encrypt on one side, decrypt on the other, against a committed shared test vector. Mismatched primitives here cost days.
2. **Pairing** (`companion/lib/sync/pairing.dart` + Godot equivalent): PC generates an X25519 keypair and renders a QR encoding `{v:1, pcId, pcPubKeyB64, mdnsName}`; phone scans with `mobile_scanner` and generates its own. Both derive the session key via `HKDF-SHA256(salt = sorted(pcId, phoneId), info = "tenthspring-sync-v1")`. Private keys go to `flutter_secure_storage` / OS keychain — **never** the DB.
3. **Discovery:** PC advertises `_tenthspring._tcp`; phone resolves via `multicast_dns`. Provide a manual-IP fallback for networks that block mDNS.
4. **Channel:** TCP + libsodium `crypto_secretstream` (XChaCha20-Poly1305). One authenticated chunk per message; reject on any auth-tag failure.
5. **Messages** exactly per `implementation_plan_foundation.md` §B4.3 — `HELLO {peerId, schemaVersion}`, `BATCH {rows[], bodyFix}`, `ACK {lastAppliedSeq}`. Refuse on schema-version mismatch rather than applying across versions.
6. **Companion outbox:** on `ACK`, delete rows with `seq <= lastAppliedSeq`; on failure keep them — the PC's `(peer_id, seq)` key makes re-send safe.
7. Never hand-roll crypto. Standard libsodium primitives only.

### Validation
- **Automated:** crypto round-trip against the committed vector, **both directions**.
- **Automated:** loopback integration — run `companion/test/fixtures/errand_day.gpx` through capture → sync, assert the expected `map_cell` / `place_node` / `visit_log` rows on the PC.
- **Automated — replay is a no-op:** re-send an identical batch; assert `appliedCount == 0` and zero state drift.
- **Automated — mid-batch drop resumes identical:** kill the socket before `ACK`, reconnect, assert final state equals a clean single run.
- **Automated:** flip one ciphertext byte; assert rejection, not silent acceptance.
- **Manual device gate (required):** real phone + PC on one Wi-Fi; pair by QR and sync. Capture with Wireshark and assert **ciphertext only** — no plaintext coordinates, nothing finer than 3 decimal places on the wire.

### Blast radius (same commit)
`companion/lib/main.dart` · `companion/lib/outbox/database.dart` (ack/delete + pairing table) · `game/autoloads/sync_server.gd` · `design_companion_and_sync.md` if the protocol deviates · Decision 4 status.

---

## 6. Deferred — trigger-gated, do NOT start

**F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` `fuzzHome()` snaps to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats the home cell as a **256 m** `CELL_METERS` cell.
**Trigger:** the first commit that wires safehouse designation — which lands in **Phase 2** (§7). Nothing writes `base_state.home_cell_*` today; it is hardcoded to `0` at `game/autoloads/db.gd:15`. Reconcile then; touching it earlier is speculative.

---

## 7. Phase roadmap (0–8) — scope, not an approved queue

**Rule before building any phase from 2 onward:** write that phase's `implementation_plan_<phase>.md` to the depth of `implementation_plan_foundation.md` — algorithms, data shapes, file responsibilities, per-component validation — and **pause for human review before coding** (THE LOOP, step A2). This roadmap deliberately carries no `file:line` gaps, because that code does not exist yet; inventing precise steps for unwritten systems produces confident nonsense. Phase order is dependency order — do not skip ahead.

**Phase 0 — Companion capture & scout ledger** · *code-complete; gate pending*
Goal: carrying the phone yields a correct, fuzzed visit/corridor log within the battery budget. Contracts: `design_privacy_and_location.md`, `implementation_plan_foundation.md` §A.
Delivered: `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, `OsLocationSource` platform settings, scout ledger.
**Exit gate:** ledger fills while backgrounded over ≥8 h at **< 3%/day** on a real device. Not yet run — §3 then the Decision 5 soak closes this.

**Phase 1 — Pairing, sync & data models** · *partial — this is the active queue*
Goal: a day of real scouting lands as `visit_log` rows + `known` cells on the PC after one LAN sync. Contracts: `design_companion_and_sync.md`, `design_game_state_and_models.md`, `implementation_plan_foundation.md` §B.
Delivered: schemas (in-memory), idempotent apply, transaction + rollback, relocation, grid unification. Outstanding: **F4** (§4), **D4** (§5).
**Exit gate:** real-device sync lands the expected rows; replay is a no-op; a mid-batch drop resumes identically; Wireshark shows ciphertext only.

**Phase 2 — World generation** · *not started*
Goal: turn revealed real geography into the deterministic tile overworld. Contracts: `design_world_generation.md`, `design_resources_and_base.md` §1.
Deliverables: lazy Overpass ingestion (only for `known` cells, 90-day cache); OSM tags → `PlaceCategory` including `landmark`; **biome derivation** (8 biomes) and `isLandmark` flagging; deterministic geometry→tile rasterisation at `tileMeters = 16` with D/P-style autotiling; two-fog rendering (unknown black · known grey silhouette + "?" chip · cleared full colour); the **intel ceremony** — the sync-time reveal beat where fog peels, place chips stamp in, and the day's route draws itself.
**Exit gate:** the same cell regenerates identical tiles from `(cached OSM, cellSeed)` across two runs — determinism is a contract, not an optimisation — and a fresh sync plays the ceremony.
⚠️ **F7's trigger fires here** (safehouse designation lands in onboarding).

**Phase 3 — Travel, time & fast travel** · *partially pre-built*
Goal: make distance expensive and the phone the only teleporter. Contract: `design_travel_and_time.md`.
Deliverables: world clock at `wallSecondsPerGameMinute = 2.0`; day/night bands with danger multiplier and shrinking light radius; route travel charging `realMiles × 4` game-minutes; destination chips speaking **travel-time** against a daylight budget; terrain speed factors; encounter rolls per game-minute with the 3-minute "porch" exemption.
Already exists — **extend, do not rewrite:** session-start relocation from `bodyFix`, out-of-contact fallback, stranded gating on `baseAccessMeters`.
**Exit gate:** a 12-mile real destination reports ~48 min on foot and charges the clock accordingly; stash reads are refused beyond `baseAccessMeters`.

**Phase 4 — Expeditions & loot** · *not started*
Goal: the moment-to-moment raid loop. Contracts: `design_expeditions_and_survival.md`, `design_resources_and_base.md` §1–2.
Deliverables: deterministic site interiors per `(category, size, cellSeed)`; the loop APPROACH → ENTER → SCAVENGE → COMPLICATE → EXTRACT; the noise model (walk 1 … gunshot 10) driving alert stages quiet → stirred → hunted; familiarity cash-out (known / familiar / mastered ⇒ −0 / −25 / −50 % ambush, pre-mapped interiors); carry capacity that forces choices; loot by category × `dangerTier` × **horde difficulty**; death ⇒ `DeathCache` at the death tile, 3-game-day decay, single-cache merge, recovery run.
**Exit gate:** a raid completes and extracts; a death drops a recoverable cache while map, intel, and cleared states survive intact.

**Phase 5 — Threats & colonies** · *not started*
Goal: a world that pushes back. Contract: `design_threats_and_colonies.md`.
Deliverables: 3 common tiers plus the **6 special archetypes** (spitter, howler, grabber, charger, bloater, sentinel) on the modular `AttackPattern` system; **biome variant** skin + trait selection (the 3 × 8 matrix); pack composition and the named combinations (Howler + crowd, Grabber + Spitter, Charger + Bloater…); the three scaling axes (distance, density, night) with biome explicitly *not* a fourth; colony lifecycle seed → grow → spill → `raidPressure` → base raid, apex assault, pacification reward; **landmark bosses** (tier 5, fixed, non-spreading, 30-game-day respawn, `unique` drops).
**Exit gate:** spawn tables demonstrably read from biome/danger/night; an ignored colony grows and raids the safehouse; a landmark apex drops a `unique`.

**Phase 6 — Base & resource economy** · *not started*
Goal: give the loot somewhere to matter. Contract: `design_resources_and_base.md` §3–5.
Deliverables: stash (stranded-gated), fortifications (walls, barricades, watchpost, workshop, garden — levels 0–3), crafting recipes, vehicles + fuel (`fuel = reach`; bicycle ×2 silent, car ×6 at 1 fuel/3 mi, truck ×5 at 1 fuel/2 mi with extra capacity), base-defence waves resolving against placed fortifications.
**Exit gate:** loot converts into base progression, and a colony raid damages only fortification levels — never the stash or the map.

**Phase 7 — Art pass** · *not started*
Goal: replace programmer art. Contract: `design_art_direction.md`.
Deliverables: 32×32 tiles and a ≤64-colour master palette (`assets/palette/tenth_spring.gpl`) with day/dusk/night as **shader tints over the same tiles**, never separate sets; 47-blob autotiles; the enemy matrix built as **one skeleton per tier, reskinned per biome** (ship-first: residential, retail, parkland, institutional); landmark boss sprites; **16×16 item icons** across the taxonomy, rarity carried by the slot border with `unique` getting a glow.
**Exit gate:** no placeholder art remains in the ship-first biomes, and the palette reads correctly under all three tints.

**Phase 8 — Privacy hardening, balance & release** · *not started*
Goal: ship-ready on both storefronts. Contracts: `design_privacy_and_location.md` §4, master plan Phase 8.
Deliverables: permission + pairing onboarding polish, home-fuzz audit, sync-encryption audit, export ("my map" → GeoJSON) and erase on both devices, a balance pass over every `tuning.json` constant, battery profiling, Steam page + companion store listings.
**Exit gate:** both device gates pass on **release** builds; export produces valid GeoJSON; erase returns both apps to a first-launch state with no residual rows.

---

## 8. Already delivered — do NOT rework
Phase 0 capture pipeline (`LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, scout-ledger UI) · **D3 background capture code** (platform settings, all six Android permissions, iOS usage strings + `UIBackgroundModes`, wired into `main.dart:9`) — *code-complete; device gate pending, Decision 5* · **F1** relocation unit math · **F2** transaction + rollback · **F3** cell/tile grid unification (256 m / 16 m) · **F5** Godot-headless-aware test runner · **F6** `base_access_meters` stranded threshold · DB accessor cleanup (`get_base_state`, `set_player_tile`) · idempotent sync apply · golden-invariant guards.

## 9. Accepted equivalents — do NOT "fix" these back
- `game/scripts/relocation_manager.gd:63-72` implements "nearest-revealed-tile snapping" as *minimal-circle reveal around the spawn cell, then place at the computed tile*, rather than a BFS search. Same guarantee — the survivor always stands on revealed ground. **Accepted.**
- `os_location_source.dart:25` — `nativeVisits()` returns `null` on all platforms. `geolocator` does not expose iOS `CLVisit`, and the design treats native visit events as an *optional corroborating hint* (`implementation_plan_foundation.md` §A2). Custom clustering covers it. **Accepted** — wiring CLVisit would need a bespoke platform channel and isn't justified.
- `game/tests/test_runner.py` is a **static lint + capability guard**, deliberately not the sync test gate, and should not be extended into one.

## 10. Intentional decisions — do NOT change
- **Cartography, never cargo** *(golden invariant 1)* — sync ingest writes only `map_cell` / `place_node` / `visit_log` (+ transient `bodyFix`). No inventory path, ever. Guarded by `sync_ingest_isolation_test.gd`.
- **Raw coordinates never persist or transit** *(golden invariant 2)* — full precision exists only in volatile capture memory; everything stored or sent is fuzzed. `companion/lib/capture/fuzz.dart` is the only place raw coordinates appear.
- **Intel, never inventory** — repeat real visits raise `IntelLevel` only.
- **Fast travel = the phone's position at sync time**; **stranded** away from base; **death drops a recoverable cache**; **map/knowledge always persist**.
- **The phone is never a place to play** — capture + read-only map + sync only.
- **World clock pauses when the game is closed** (except capped colony catch-up).
- **Travel time is simulation-authoritative** (15 mph over real distance); on-screen movement is aesthetic.
- **Tile synthesis is deterministic** per `(OSM data, cellSeed)`; the tile cache is regenerable, never source of truth.
- **Stack (Decision 1):** Godot (PC) + Flutter (companion), SQLite both sides, **LAN-only** E2E sync. **Never hand-roll crypto.**
- Capture settings (accuracy `medium`, 25 m filter, 2-min interval) and `game/config/tuning.json` values are deliberate balance/battery decisions.

## 11. Where the contracts live (don't duplicate them here)
| Need | Doc |
|---|---|
| Pillars, stack | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Build steps + validation for Phase 0–1 | `docs/implementation_plan_foundation.md` |
| Two-fog pipeline, visits→tiles | `docs/design_world_generation.md` |
| Schemas / models | `docs/design_game_state_and_models.md` |
| Travel, clock, fast-travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync protocol | `docs/design_companion_and_sync.md` |
| Enemies, colonies, landmark bosses | `docs/design_threats_and_colonies.md` |
| Raids, noise, familiarity, death | `docs/design_expeditions_and_survival.md` |
| Loot/POI economy · art & item icons | `docs/design_resources_and_base.md` · `docs/design_art_direction.md` |
| Privacy/location contracts | `docs/design_privacy_and_location.md` |
| Decisions, issues, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md contract it names. Specs are decisions.
2 PLAN      Building a phase with no implementation_plan_*.md at build depth? Write one
            FIRST (algorithms, data shapes, file responsibilities, per-item validation)
            and PAUSE for human review before coding. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written. Honor §10 invariants and the standing constraints.
4 VALIDATE  Run this item's validation, then the full §1 battery.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, or docs conflict → STOP. File in
            ongoing_general_errors.md with options for the human. Do not improvise.
6 RECORD    Move the item to Resolved with what-was-solved; update any design doc
            whose described behavior changed — in this same commit.
7 COMMIT    One item = one Conventional Commit, WHY in the body.
```

## Definition of Done (this build — closes Phases 0 and 1)
- [x] **Item 1** — both platform branches asserted with explicit overrides; Android background-permission flow routes to settings and degrades gracefully; ledger shows background state.
- [ ] **D3 device soak run** (Decision 5, Option A) — ledger fills backgrounded at < 3%/day. **Closes Phase 0.**
- [ ] **Item 2** — SQLite store with §B2 DDL + §B6 migrations; persistence survives a restart; `simulateFailure` hook removed.
- [ ] **Item 3** — QR pairing + mDNS + encrypted TCP both sides; replay is a no-op; mid-batch drop resumes identical; Wireshark shows ciphertext only. **Closes Phase 1.**
- [ ] Full §1 battery green, **including Godot headless runtime tests actually executing**.
- [ ] `ongoing_general_errors.md` updated; no open finding describes already-fixed code.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is **Phase 2 (§7)** — and it starts by writing `implementation_plan_phase2.md` and pausing for human review, *not* by writing code. Other legitimate triggers: (a) a new item in `ongoing_general_errors.md` with a filled `Your selection:`, (b) the §1 battery regressing on a fresh checkout, (c) the F7 trigger firing, or (d) the human assigning something. Otherwise report that the queue is complete and stop.
