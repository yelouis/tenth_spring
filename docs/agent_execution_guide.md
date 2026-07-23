# Agent Execution Guide

**You are an engineering agent building Tenth Spring — a two-build project: a PC game (Steam, Godot) and a thin phone companion app (Android + iOS, Flutter).** The PC game holds all gameplay; the companion does location capture + sync only.

This guide is your front door: it tells you (1) where to find the governing doc for anything, (2) the exact state of the code right now, (3) the prioritized work left, and (4) the loop to work by. **Read it first, every time.** Never write code before reading the doc that governs the thing you're building, and never violate a settled pillar.

Prime directive: **find the governing doc → follow the loop → validate → record.** Specs are decisions, not suggestions.

---

## 0. Orientation (read in this order)
1. `README.md` — the game, the pillars, the confirmed stack.
2. This guide — state of the code + the loop.
3. `docs/master_implementation_plan.md` — phase order + tuning constants.
4. `docs/implementation_plan_foundation.md` — build-ready detail + validation for Phase 0–1 (the current work).
5. The specific `docs/design_*.md` contract for the system you touch.

Two source trees: **`game/`** (Godot/GDScript, canonical SQLite world) and **`companion/`** (Flutter/Dart — a visit outbox + pairing state only).

---

## 1. Current state (verified July 22)

Code now exists. A verification pass established:

**✅ Phase 0 — companion capture: DONE and GREEN.**
`cd companion && flutter test` passes (11/11 green) and `flutter analyze` passes (0 issues). Built and spec-faithful: the `LocationSource` seam, real `OsLocationSource` (via `geolocator`), `VisitCorridorDetector` (dwell/corridor + accuracy filter), `fuzz.dart` (3-dp point / 300 m home cell), the Drift outbox, `GpxReplaySource` + fixtures (`errand_day`, `commute`, `relocation_200mi`), and the scout-ledger UI. The privacy invariant holds — full-precision fixes stay in memory; only fuzzed values are stored.

**🟡 Phase 1 — PC + sync: PARTIAL.**
- `game/autoloads/db.gd` is an in-memory store supporting snapshot transactions (`begin_transaction`, `commit_transaction`, `rollback_transaction`). (F4 SQLite integration is open).
- `game/autoloads/sync_server.gd` applies batches **idempotently** inside atomic snapshot transactions, using unified cell (~256m) and tile (16m) grid projections. Touches **only** map tables (`visit_log`/`map_cell`/`place_node`) — golden invariant 1 holds.
- `game/scripts/relocation_manager.gd` computes survivor spawn tiles and `is_stranded` using unified meters coordinate math, minimal-circle cell reveals for unknown areas, nearest-revealed-tile snapping, and out-of-contact fallback.
- `game/tests/test_runner.py` is updated as a static linter and capability guard, auto-executing headless Godot tests (`godot --headless`) when a Godot engine binary is available in CI/environment.

---

## 2. Where everything lives (find the doc)

| If you need to know… | Read |
|---|---|
| The game, pillars, confirmed stack | `README.md` |
| What to build next; tuning constants | `docs/master_implementation_plan.md` |
| **How to build Phase 0–1, with validation** | `docs/implementation_plan_foundation.md` |
| The rules of one system | `docs/design_<system>.md` |
| Two-fog pipeline / visits→tiles | `docs/design_world_generation.md` |
| Data models / schemas | `docs/design_game_state_and_models.md` |
| Travel, clock, fast-travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync protocol | `docs/design_companion_and_sync.md` |
| Enemies (tiers/specials/attack patterns/combos), colonies, bosses | `docs/design_threats_and_colonies.md` |
| Raids, noise, familiarity, death | `docs/design_expeditions_and_survival.md` |
| POI→resource, loot, fuel, base, item/loot icons | `docs/design_resources_and_base.md` · `docs/design_art_direction.md` |
| Privacy/location contracts (bind everything) | `docs/design_privacy_and_location.md` |
| Open decisions + engineering history + verification findings | `docs/ongoing_general_errors.md` |
| Manual E2E test journeys | `docs/e2e_testing_journeys.md` |

`design_*.md` = contracts (rules); `implementation_plan_*.md` = build steps (how + validation). If they conflict, the contract wins and you file it (§4).

---

## 3. Your task queue — do these in order
The foundation is half-built. Work these top-to-bottom; each is one pass of THE LOOP (§4) with acceptance = the matching validation in `implementation_plan_foundation.md`.

1. **[Finish Phase 0 · resolves D3] Real background capture.** Implement `OsLocationSource` behind `LocationSource` (§A2): iOS `CLVisit` + significant-location-change; Android foreground service + FusedLocationProvider (balanced) + dwell detection. Wire it into `main.dart`. **Accept:** on-device the ledger fills over a normal day at **< 3%/day** battery (§A7, §Phase 0 exit). Record the D3 outcome.
2. **[Phase 1 · SQLite] Replace the `db.gd` stub.** Stand up a real SQLite store (GDExtension per D4 tooling) with the §B2 DDL and the §B6 migration framework; port the existing query methods unchanged in signature. **Accept:** schema round-trip + migration fixture tests pass under Godot headless.
3. **[Phase 1 · resolves D4] Secure transport, both sides.** Build pairing (X25519 + QR via `mobile_scanner`; keys in secure storage — never the DB) and the encrypted channel (mDNS discovery via `multicast_dns` ↔ Godot mDNS; TCP; libsodium `secretstream`). New: `companion/lib/sync/pairing.dart` + `transport.dart` and Godot equivalents. **Verify Dart `cryptography` ↔ the Godot libsodium binding are wire-compatible with shared test vectors.** **Accept:** cross-device sync of a GPX-fixture batch lands the expected PC state; **replay is a no-op; a mid-batch drop resumes to identical state**; Wireshark shows ciphertext only, no coord finer than 3 dp (§B4, device gate).
4. **[Correctness] Fix relocation.** In `relocation_manager.gd`, put home and body into one coordinate frame (home is a fuzzed *cell*, body is lat/lon); implement nearest-revealed-tile snapping, the unknown-area minimal-circle reveal, and the out-of-contact fallback (§B5). **Unify the grid:** `sync_server.latlon_to_cell` (×100 ≈ 1.1 km) and `relocation` (×1000) use different projections — pick one shared cell/tile projection consistent with `tileMeters`/cell size in the models doc.
5. **[Correctness] Transactional batch apply.** Wrap `sync_server.process_batch` in one DB transaction (§B4.4) so a crash mid-batch cannot advance `last_applied_seq` past partially-applied rows.
6. **[Validation infra] Run the `.gd` tests for real.** Wire Godot headless into CI (`godot --headless` test scenes) so `idempotent_sync_test` / `db_test` / `sync_ingest_isolation_test` actually execute. Keep `test_runner.py` as a lint gate only, and label it as such.

If none of the above is your assignment, or a new item appears in `ongoing_general_errors.md` with a filled `Your selection:`, take that first.

---

## 4. THE LOOP
Every unit of work is **Orient → Plan → Implement → Validate → Record → Commit**, with two tracks that differ only at Plan and Validate.

### Track A — implement a feature / phase
```
A1 ORIENT   Read the governing design_<system>.md + the relevant implementation_plan_*.md.
A2 PLAN     If the work has no implementation_plan_*.md at build depth, WRITE one first
            (algorithms, data shapes, file responsibilities, per-component validation) and
            PAUSE for user review before coding.
A3 BUILD    Implement exactly to the plan. Honor every §5 non-negotiable.
A4 VALIDATE Run the plan's checks + §6 standard. RED GATE: fix failures before new work.
A5 RECORD   Sync changed design/plan docs; log in-scope choices in ongoing_general_errors.md.
A6 COMMIT   One item = one Conventional Commit; WHY in the body.
```

### Track B — resolve a bug / verification finding
```
B1 ORIENT   Find/file the issue in ongoing_general_errors.md; name the contract it violates.
B2 REPRODUCE Write a FAILING test (or a documented manual repro for device-only issues).
B3 FIX      Fix to the contract — never paper over a symptom. Contract wrong? STOP, file a Decision.
B4 VALIDATE New test green + full suite green (§6) + regression guards intact.
B5 RECORD   Move the issue to Resolved with root cause + what-was-solved + a regression warning.
B6 COMMIT   One fix = one Conventional Commit; WHY in the body.
```

When blocked, a spec is wrong, or docs conflict: **STOP, file it in `ongoing_general_errors.md` with options, ask the user.** Never guess past a contradiction. If a choice is the user's to make, file it as a Decision with options and a `Your selection:` line.

---

## 5. Non-negotiables — do NOT re-litigate or "fix" these
- **Cartography, never cargo** — sync ingest writes only `map_cell`/`place_node`/`visit_log` (+ transient `bodyFix`); no inventory path. Guarded permanently (§B6 / the isolation tests).
- **Intel, never inventory** — repeat real visits raise `IntelLevel` only.
- **Raw coordinates never persist or transit** — full precision lives only in volatile capture memory; everything stored/sent is fuzzed (`companion/lib/capture/fuzz.dart`, the one place raw coords exist).
- **Fast travel = the phone's position at sync time** (a desktop has no GPS); **stranded** away from base; **death drops a recoverable cache**; **map/knowledge always persist**.
- **The phone is never a place to play** — capture + read-only map + sync only.
- **World clock pauses when the game is closed** (except capped colony catch-up).
- **Travel time is simulation-authoritative** (15 mph over real distance); on-screen movement is aesthetic.
- **Tile synthesis is deterministic** per `(OSM data, cellSeed)` — the tile cache is regenerable, never source of truth.
- **Confirmed stack (Decision 1)**: Godot (PC) + Flutter (companion), SQLite both sides, LAN-only E2E sync.
- **Never hand-roll crypto** — standard libsodium underneath, always.

---

## 6. Validation standard — what "green" means
Nothing is done until it passes its plan's checks, plus these:
- **Companion (`companion/`)**: `flutter analyze` → 0 errors; `flutter test` green. *(Currently green.)*
- **PC (`game/`)**: **Godot headless** test scenes green — the `.gd` tests must actually run (item 6). `test_runner.py` is a static lint gate, not the sync gate.
- **Cross-device**: GPX-fixture sync (companion → PC) yields expected PC state; **replay = no-op**; mid-batch drop resumes identical.
- **Golden-invariant guards** (green forever): sync-ingest isolation (no inventory writes) and fuzz-only-persists.
- **Two manual DEVICE GATES** (pre-merge for anything touching capture, battery, or sync; not in CI): battery **< 3%/day**; Wireshark shows **ciphertext only**, no coord finer than 3 dp.

Anything touching location capture, battery, or cross-device sync **requires a real-device check** — a simulator/desktop never validates these.

---

## 7. Recording & commit conventions
- **Decisions & bugs** live in `ongoing_general_errors.md`: Decisions carry options + a `Your selection:` line; bugs use the bug-documentation format and, once fixed, move to Resolved with root cause + regression warning.
- **Docs are living** — update the governing `design_*.md` / `implementation_plan_*.md` in the *same* commit as behavior-changing code. Docs must never lag code.
- **Commits**: one item = one Conventional Commit (`feat:`/`fix:`/`docs:`…), WHY in the body. Branch for changes; commit/push only when the user asks.
