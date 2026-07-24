# Agent Execution Guide — Active Build: Foundation Completion (verified 2026-07-22, pass 8)

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
| Companion tests | `cd companion && flutter test` | **17/17 passed** |
| Game static audit | `python3 game/tests/test_runner.py` (from repo root) | **Lint pass; Golden Invariant 1 guard intact** |
| Game runtime tests | `godot --headless` | ⚠️ **NOT EXECUTED — Godot is not installed here.** `db_test.gd`, `idempotent_sync_test.gd`, `sync_ingest_isolation_test.gd` are verified by reading only. Never report a game-side runtime pass without installing Godot. |
| D3 device gate | 8 h background soak on a real phone | ⚠️ **NOT YET RUN — UNBLOCKED NOW.** Decision 5 = **Option A**; F8/F9 have landed, so this is the human's next action. Phase 0 stays open until it passes. |

⚠️ **Read before trusting any status note.** Pass 8 found the tracking doc claiming F4 ("real SQLite") and D4 ("secure transport") were fixed when neither was: storage is JSON, and **no networking code exists on either side**. `flutter test` at 17/17 covers crypto helpers in-process — it is *not* evidence that syncing works. Verify in source; treat green suites as "nothing crashed," never as spec fidelity.

Do not regress these numbers.

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F11 — atomic write for the world file** (game) | **Do this first; it is ~10 lines.** Today a crash mid-save truncates `user://tenth_spring.db` and silently erases every place the player has ever walked — data the design says is unrecoverable. Highest severity per hour of work on the board, and it is correct under *either* outcome of Decision 6. |
| 1 | **F4 + F10 — real SQLite store** (game) | **Unblocked — Decision 6 = Option A (finish SQLite as designed).** Must precede #2: transport writes through the DB layer, so settling the engine first avoids re-plumbing every call. F10 (the false "SQLite/ACID" header comment) is fixed in the same commit. Note this also sets Decision 4's scope — the Godot side now needs a SQLite GDExtension *and* libsodium; vet them together. |
| 2 | **D4 + F12 — the actual transport** (both) | The crypto and payload builders exist; **the transport does not**. Needs the Godot-side listener, mDNS on both ends, and F12's AEAD/nonce decision. Largest item; closes Phase 1. |

| — | **▶ HUMAN: run the D3 device soak** | Decision 5 = Option A, and F8/F9 have landed — **this is unblocked right now** and can run in parallel with items 0–2, since it needs your phone and not the codebase. Blocks closing Phase 0. If <3%/day fails, escalate to D3 Option A (Transistorsoft) before more is built on the capture strategy. |

Deferred (trigger-gated, **do not start**): **F7** — see §6.

## 3. Item 0 — F11: atomic write for the world file

**What this means for the user:** if the game is killed while saving, they lose every place they have ever walked — months of real-life scouting, gone, unrecoverably. This is the worst outcome the product can produce, and it is currently a ~10-line fix away.

### The gap
`game/autoloads/db.gd` `_save_persistent_store()` opens `user://tenth_spring.db` with `FileAccess.WRITE` — which **truncates the file** — and then writes the whole world in one pass. Interrupt it and the file is truncated or invalid; `_load_persistent_store()` then fails its `TYPE_DICTIONARY` check and silently falls through to empty defaults. No backup, no atomic swap.

### Implementation
1. Serialise to `user://tenth_spring.db.tmp`, `flush()`, and close it.
2. Only after a clean close, rename over the original with `DirAccess.rename_absolute()` — rename is atomic on all target platforms, so a reader sees either the old world or the new one, never a torn one.
3. On load, if the primary file is missing or fails to parse, fall back to `.tmp` if it parses; otherwise start empty **and log loudly**. Never treat "unparseable" as "no data" without a signal.
4. Do this regardless of Decision 6 — the same discipline applies to a SQLite file.

### Validation
- **Automated (fails today, proving the fix):** write state, commit, then truncate the file to 0 bytes mid-simulation and reload — assert the previous world is still recoverable rather than silently empty.
- **Automated:** a normal save/reload round-trip preserves `map_cell`, `place_node`, and `visit_log` counts exactly.
- **Manual:** `godot --headless`, kill the process during a large save, relaunch, confirm the map survives.

### Blast radius (same commit)
`game/autoloads/db.gd` (`_save_persistent_store`, `_load_persistent_store`) · `game/tests/db_test.gd` · F11 in `ongoing_general_errors.md`.

---

## 4. Item 1 — F4 + F10: real SQLite store

**Decision 6 = Option A (July 22): finish real SQLite as designed.** The design docs already specify SQLite, so this corrects the code toward the existing contract — **do not amend the design to match the JSON implementation.** Persistence already works; this replaces the *engine* beneath it.

**What this means for the user:** whether their world survives a crash intact, and whether the map can still load quickly once they have scouted a whole city.

### The gap
- `db.gd:10-19` — the world is in-memory Dictionaries, serialised with `JSON.stringify` into a file merely *named* `.db`. There is no SQLite anywhere in the repo.
- `db.gd:36-41` — `_run_migrations()` writes a version string; it is not a migration runner. No §B2 DDL exists.
- `db.gd:46-67` — transactions are Dictionary deep-copies, so there is no ACID and no `PRIMARY KEY (peer_id, seq)`; idempotency is enforced by dict-key convention only.
- **F10** — `db.gd:3-5` claims the file "manages canonical **SQLite** database storage… **DDL schemas (§B2)**… **ACID transaction boundaries**." All three are false, and this comment is *why* a previous pass recorded F4 as fixed.

### Implementation
1. **Add a SQLite GDExtension.** Per Decision 4, prefer a maintained binding; wrap it yourself only if none is current. **Vet it alongside the libsodium binding Item 2 needs** — one maintained source covering both is preferable to two dependencies. **Record which you chose on Decision 4** — that is what finally makes Decision 4 "realized."
2. **Open the DB at `user://tenth_spring.db`.** The existing JSON file lives at that exact path, so on first run detect a JSON payload, import it into the new tables, and rename the original to `user://tenth_spring.db.jsonbak`. Do **not** silently delete it — a botched import must be recoverable.
3. **Implement the §B2 DDL exactly:** `meta`, `world_clock`, `map_cell`, `place_node`, `visit_log`, `sync_peer`, `player_profile`, `base_state`, `inventory_item`, `osm_cache`. `visit_log` **must** carry `PRIMARY KEY (peer_id, seq)` — that key *is* the idempotency guarantee, and moving it from dict-key convention into the engine is a main point of this item.
4. **Implement the §B6 migration runner** keyed on `meta.schema_version` — ordered, idempotent, and never destructive to `visit_log` or `map_cell`.
5. **Keep every public method signature unchanged** (`get_map_cell`, `upsert_map_cell`, `get_place_node`, `upsert_place_node`, `is_visit_logged`, `insert_visit_log`, `get_sync_peer`, `update_sync_peer`, `get_base_state`, `set_player_tile`, `get_schema_version`) so no caller churns.
6. **Replace the snapshot transactions with real `BEGIN` / `COMMIT` / `ROLLBACK`**, and delete the Dictionary snapshot fields (`db.gd:22-26`) — leaving both mechanisms in place invites a future agent to "fix" the wrong one.
7. **Rewrite the `db.gd` header comment (F10)** so it describes what the file actually does. Once SQLite is real the current wording finally becomes true — verify line by line rather than assuming.
8. **Keep Item 0's durability discipline:** let SQLite manage its own journal/WAL. Do not hand-roll writes around it or copy the DB file while a transaction is open.

### Validation
- **Automated:** persistence across a full reload; per-table round-trip; a migration fixture that upgrades without losing a single `visit_log` row.
- **Automated:** `idempotent_sync_test.gd` still green — replay ⇒ `appliedCount == 0`; injected failure ⇒ no state persisted.
- **Automated (fails today, proving the engine is real):** inserting a duplicate `(peer_id, seq)` is rejected **by the engine** — a constraint violation — not by application code. Today's dict-key check cannot produce that error.
- **Automated:** grep the shipped `db.gd` for `JSON.stringify` / `JSON.parse_string` and assert **zero** matches — the JSON path must be gone, not merely bypassed.
- **Automated:** the JSON→SQLite import migrates an existing fixture file with **zero `visit_log` rows lost**, and leaves `.jsonbak` in place.
- **Manual:** `godot --headless` executes the runtime tests (`test_runner.py` should stop printing the "Godot not found" note).

### Blast radius (same commit)
`game/autoloads/db.gd` (incl. header comment + snapshot fields `:22-26`) · `game/tests/db_test.gd` · `game/tests/idempotent_sync_test.gd` · Decision 4 (record the binding) · Decision 6 + F4/F10 status in `ongoing_general_errors.md`.

---

## 5. Item 2 — D4 + F12: the actual transport

**What this means for the user:** this is still the missing half of the product. Walking around cannot reach the game until it exists.

### The gap — read this carefully; the tracking doc previously said "fixed"
- **Delivered and genuinely good:** `companion/lib/sync/pairing.dart` (X25519 + HKDF-SHA256, private keys in `FlutterSecureStorage`, correctly never in the DB) and `transport.dart` (AEAD encrypt/decrypt, HELLO/BATCH builders, `handleAckResponse` purging the outbox). Four honest tests including tampered-ciphertext rejection. **Do not rewrite these.**
- **Missing — the transport itself:** `grep -rn "Socket|MDnsClient|multicast_dns|connect(" companion/lib/` returns **nothing**. `game/autoloads/sync_server.gd` has no listener, no mDNS, no crypto, and the game tree has no libsodium binding. Neither device can open a connection.
- **F12** — `transport.dart:7` uses `Chacha20.poly1305Aead()` (96-bit, caller-supplied nonce) where the contract specifies **XChaCha20-Poly1305 `crypto_secretstream`**. No nonce discipline exists in the code; a repeated nonce under one key is a silent, catastrophic AEAD failure.

### Implementation
1. **Settle F12 first**, before any wire code: either `Xchacha20.poly1305Aead()` with a documented monotonic nonce scheme, or secretstream on both sides. If you deviate deliberately, write the nonce rule down and record it as an accepted equivalent. There is no sunk cost — the Godot half doesn't exist yet.
2. **Wire-compatibility spike, second.** Prove Dart and the chosen Godot binding interoperate against a committed shared test vector before building on top. Mismatched primitives here cost days.
3. **Godot side (Decision 4's real question):** adopt a libsodium GDExtension, add a TCP listener, and advertise `_tenthspring._tcp` over mDNS. Record which binding you chose on Decision 4 — that is what makes the decision "realized."
4. **Companion side:** resolve the PC via `multicast_dns`, open the socket, and drive the existing `pairing.dart`/`transport.dart` helpers. Provide a manual-IP fallback for networks that block mDNS.
5. **Pairing UX:** PC renders the QR (`{v:1, pcId, pcPubKeyB64, mdnsName}`); phone scans with `mobile_scanner`.
6. Refuse on schema-version mismatch rather than applying across versions. Never hand-roll crypto.

### Validation
- **Automated:** crypto round-trip against the committed vector, **both directions** (Dart→Godot and Godot→Dart).
- **Automated:** loopback integration — run `companion/test/fixtures/errand_day.gpx` through capture → sync and assert the expected `map_cell` / `place_node` / `visit_log` rows land on the PC. *This is the assertion that proves a transport exists; nothing in today's suite can.*
- **Automated — replay is a no-op:** re-send an identical batch; `appliedCount == 0`, zero drift.
- **Automated — mid-batch drop resumes identical:** kill the socket before `ACK`, reconnect, assert the final state equals a clean single run.
- **Manual device gate:** real phone + PC on one Wi-Fi; pair by QR, sync, and confirm via Wireshark that the payload is **ciphertext only** — no plaintext coordinates, nothing finer than 3 decimal places.

### Blast radius (same commit)
`companion/lib/sync/transport.dart` (F12) · new companion socket/mDNS code · `companion/lib/main.dart` · `game/autoloads/sync_server.gd` · `design_companion_and_sync.md` if the protocol deviates · Decision 4 + F12 status.

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
Phase 0 capture pipeline (`LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, scout-ledger UI) · **D3 background capture code** (platform settings, all six Android permissions, iOS usage strings + `UIBackgroundModes`, wired into `main.dart:9`) — *code-complete; device gate pending, Decision 5* · **F1** relocation unit math · **F2** transaction + rollback · **F3** cell/tile grid unification (256 m / 16 m) · **F5** Godot-headless-aware test runner · **F6** `base_access_meters` stranded threshold · **F8** both-platform settings test (`debugDefaultTargetPlatformOverride`) · **F9** Android background-permission flow (`openAppSettings()` + "Background scouting off — tap to enable" banner) · **world-file persistence** (JSON; engine choice is Decision 6) · `simulateFailure` hook removed · **pairing.dart / transport.dart crypto helpers** (X25519, HKDF, AEAD, ACK purge — keep these) · DB accessor cleanup (`get_base_state`, `set_player_tile`) · idempotent sync apply · golden-invariant guards.

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
- [x] **Item 0 (F11)** — atomic temp+rename write; a truncated file no longer silently empties the world.
- [ ] **Item 1 (F4+F10)** — real SQLite (Decision 6 = A): §B2 DDL, §B6 migrations, engine-enforced `PRIMARY KEY (peer_id, seq)`, existing JSON world imported with nothing lost, no `JSON.stringify` left in `db.gd`, header comment true.
- [ ] **Item 2 (D4+F12)** — nonce/AEAD settled; Godot listener + mDNS on both sides; the **loopback GPX sync assertion passes** (the first real proof a transport exists); replay is a no-op; mid-batch drop resumes identical; Wireshark shows ciphertext only.
- [ ] **D3 device soak run** (Decision 5 = Option A) — ledger fills backgrounded at < 3%/day. **Closes Phase 0.**
- [ ] Full §1 battery green, **including Godot headless runtime tests actually executing**.
- [ ] `ongoing_general_errors.md` updated; no status note claims something the source contradicts.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is **Phase 2 (§7)** — which starts by writing `implementation_plan_phase2.md` and pausing for human review, *not* by writing code. Other legitimate triggers: (a) a new item in `ongoing_general_errors.md` with a filled `Your selection:`, (b) the §1 battery regressing on a fresh checkout, (c) the F7 trigger firing, or (d) the human assigning something. Otherwise report that the queue is complete and stop.
