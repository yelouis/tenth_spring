# Agent Execution Guide

**You are an engineering agent building Tenth Spring — a two-build project: a PC game (Steam, Godot) and a thin phone companion app (Android + iOS, Flutter).** The PC game holds all gameplay; the companion does location capture + sync only.

This guide is your front door. Its job is to (1) point you to the right document for whatever you're doing, and (2) hand you the exact loop to work by. **Read this first, every time. Do not write code before you have found and read the doc that governs the thing you're about to build, and never violate a settled pillar.**

Prime directive: **find the governing doc → follow the loop → validate → record.** Specs in these docs are decisions, not suggestions.

---

## 0. Orientation (read in this order on a cold start)
1. `README.md` — what the game is, the settled design pillars, the confirmed stack.
2. This guide — how to find docs and how to work.
3. `docs/master_implementation_plan.md` — the phase order and all tuning constants.
4. `docs/implementation_plan_foundation.md` — build-ready detail + validation for the current work (Phase 0–1).
5. The specific `docs/design_*.md` contract for the system you're touching.

Two source trees: **`game/`** (Godot/GDScript, the PC game, the canonical SQLite world) and **`companion/`** (Flutter/Dart, the phone — a visit outbox + pairing state only).

---

## 1. Where everything lives (find the doc)

| If you need to know… | Read | 
|---|---|
| What the game is, the pillars, the confirmed stack | `README.md` |
| What to build next and in what order; tuning constants | `docs/master_implementation_plan.md` |
| **Exactly how to build the current work, with validation** | `docs/implementation_plan_*.md` (foundation = Phase 0–1) |
| The rules of one system (schemas, algorithms, invariants) | `docs/design_<system>.md` |
| The two-fog pipeline, visits→tiles | `docs/design_world_generation.md` |
| Data models / schemas | `docs/design_game_state_and_models.md` |
| Travel, world clock, fast-travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync protocol | `docs/design_companion_and_sync.md` |
| Zombie tiers, scaling, colonies | `docs/design_threats_and_colonies.md` |
| Raids, noise, familiarity, death | `docs/design_expeditions_and_survival.md` |
| POI→resource, fuel, base, crafting | `docs/design_resources_and_base.md` |
| Pixel-art spec, sprite sourcing | `docs/design_art_direction.md` |
| Privacy/location contracts (bind every system) | `docs/design_privacy_and_location.md` |
| The open decision queue + engineering history | `docs/ongoing_general_errors.md` |
| Manual end-to-end test journeys | `docs/e2e_testing_journeys.md` |

Rule of the doc set: **the `design_*.md` files are the contracts (the *what* and the *rules*); the `implementation_plan_*.md` files are the build steps (the *how* and the *validation*).** If they ever disagree, the design doc wins and you file the conflict (see §3).

---

## 2. Non-negotiables — do NOT re-litigate or "fix" these
These are settled user decisions and architectural invariants. If one seems infeasible, STOP and file a Decision (§3) — never silently deviate.

- **Cartography, never cargo** — no real-world event grants resources. The sync ingest may write only map tables (`map_cell`, `place_node`, `visit_log`) + the transient `bodyFix`; it has no path to inventory. Guarded by a permanent test (`implementation_plan_foundation.md` §B6).
- **Intel, never inventory** — repeat real visits raise `IntelLevel` only.
- **Raw coordinates never persist or transit** — full precision lives only in volatile memory in the capture pipeline; everything stored/sent is fuzzed (`companion/lib/capture/fuzz.dart`, the one place raw coords exist).
- **Fast travel = the phone's position at sync time** (a desktop has no GPS); **stranded** away from base; **death drops a recoverable cache**; **map/knowledge always persist**.
- **The phone is never a place to play** — capture + read-only map + sync only. Any "add gameplay to the companion" idea gets filed, not built.
- **World clock pauses when the game is closed** (except capped colony catch-up). Punishing absence is rejected.
- **Travel time is simulation-authoritative** (15 mph over real distance); on-screen movement is aesthetic.
- **Tile synthesis is deterministic** per `(OSM data, cellSeed)` — the tile cache is regenerable, never the source of truth.
- **Confirmed stack (Decision 1)**: Godot (PC) + Flutter (companion), SQLite both sides, LAN-only E2E sync. Sub-decisions D3/D4 are provisional (start-simple) — see `ongoing_general_errors.md`.
- **Never hand-roll crypto** — standard libsodium underneath, always.

---

## 3. Pick your task
Every session starts one of three ways:

1. **A queued item** — open `docs/ongoing_general_errors.md`. A `### Bug N` (with a repro) or a `### Decision N` with a filled **`Your selection:`** line is your assignment. Take the top unresolved one → run the **loop** (§4).
2. **No queue** — work `docs/master_implementation_plan.md` **in phase order**. The current front is Phase 0 (companion capture) then Phase 1 (PC + pairing/sync). Do not jump ahead of the foundation exit criteria.
3. **A design gap** (a doc under-specifies what you need) — make the smallest choice consistent with the pillars, record it as a Decision in `ongoing_general_errors.md`, sync the affected design doc in the same commit, then continue.

If at any point a spec is wrong, a pillar is blocked, or two docs conflict: **STOP, file it in `ongoing_general_errors.md` with options, and ask the user.** Do not guess past a contradiction.

---

## 4. THE LOOP
Every unit of work is the same skeleton — **Orient → Plan → Implement → Validate → Record → Commit** — with two tracks that differ only at Plan and Validate.

### Track A — implement a feature / phase
```
A1 ORIENT   Read the governing design_<system>.md + the phase in the master plan.
A2 PLAN     Ensure a detailed implementation_plan_*.md covers this work.
            If none exists (a phase past the foundation), WRITE one FIRST — algorithms,
            data shapes, file responsibilities, and per-component validation, to the depth
            of implementation_plan_foundation.md — and PAUSE for user review before coding.
A3 BUILD    Implement exactly to that plan. Honor every §2 non-negotiable.
A4 VALIDATE Run the plan's per-component checks + the §5 standard. RED GATE: if any
            check fails, fix before proceeding — do not stack new work on unvalidated work.
A5 RECORD   Sync any changed design/plan docs; log any in-scope choice in ongoing_general_errors.md.
A6 COMMIT   One item = one Conventional Commit; the WHY goes in the body.
```

### Track B — resolve a bug
```
B1 ORIENT   Find (or file, in bug-documentation format) the issue in ongoing_general_errors.md.
            Identify which design contract it violates — that defines "correct".
B2 REPRODUCE Write a FAILING automated test that captures the bug (or a documented manual
            repro for device-only issues). No fix begins without a red test/repro.
B3 FIX      Fix to the design contract — never paper over a symptom. If the contract itself
            is wrong, STOP and file a Decision instead of coding around it.
B4 VALIDATE The new test goes green + full suite green (§5) + existing regression guards intact.
B5 RECORD   Move the issue to Resolved with: root cause, what-was-solved, and a regression warning.
B6 COMMIT   One fix = one Conventional Commit; the WHY goes in the body.
```

---

## 5. Validation standard — what "green" means
Nothing is "done" until it passes the checks its plan names, plus these globally:

- **PC (`game/`)**: engine build clean; unit/integration tests green (GUT or the chosen Godot test runner). Determinism tests for tile synthesis and idempotent-sync tests must pass.
- **Companion (`companion/`)**: `flutter analyze` → 0 errors; `flutter test` green.
- **Cross-device**: the GPX-fixture sync test (companion → PC over loopback) produces the expected PC state; **replaying the same batch is a no-op**; a mid-batch drop resumes to identical state.
- **Golden-invariant guards** (must stay green forever): the sync-ingest isolation test (no inventory write path) and the fuzz-only-persists test.
- **Two manual DEVICE GATES** — required pre-merge for any change touching capture, battery, or the sync channel; not run in CI:
  1. Real-device battery attribution **< 3%/day** with background capture on.
  2. Wireshark on the phone↔PC sync shows **ciphertext only** — no coordinate finer than 3 decimals on the wire.
- **CI** runs everything except the two device gates.

Anything touching location capture, battery, or cross-device sync **requires a real-device check** — a simulator never validates these.

---

## 6. Recording & commit conventions
- **Decisions & bugs** live in `docs/ongoing_general_errors.md`: Decisions carry options + a `Your selection:` line; bugs use the bug-documentation format and, once fixed, move to Resolved with root cause + regression warning.
- **Design/plan docs are living** — when your change alters behavior, update the governing `design_*.md` / `implementation_plan_*.md` in the *same* commit as the code. Docs must never lag the code.
- **Commits**: one item = one Conventional Commit (`feat:`, `fix:`, `docs:`…), the WHY in the body. Branch for changes; commit/push only when the user asks.
- **Doc/commit skill conventions**: mirror Gaslight's `.agents/skills/` (import them when that tooling is set up).
