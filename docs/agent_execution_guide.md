# Agent Execution Guide — Design Phase (created July 20)

**You are an engineering agent picking up Tenth Spring — a two-build project: a PC game (Steam) and a thin phone companion app (Android + iOS).** The PC game holds all gameplay; the companion does location capture + sync only. The project is in the **design phase**: the docs are written, no code exists. Read this before starting anything so you build in the intended order and don't violate settled pillars.

## 1. Current baseline (July 20)
- No code, no tests, no CI. `docs/` is complete and is the source of truth.
- The design pillars in `README.md` are **user decisions from the founding brainstorm — do not re-litigate them**. If a pillar seems technically infeasible, STOP and file a Decision block in `docs/ongoing_general_errors.md`; never silently deviate.
- Stack (Decision 0, README): **PC = Godot 4** (Steam), **companion = Flutter**, SQLite saves, OSM Overpass (PC), significant-location-change capture (phone), direct E2E device-to-device sync. This is a *working assumption* — confirm Decision 1 before Phase 1 locks it.
- **Two source trees**: `game/` (PC) and `companion/` (phone). The PC SQLite DB is the canonical world; the phone holds only a visit outbox + pairing state.

## 2. The world as designed — intentional decisions (do NOT "fix" these)
- **Cartography, never cargo**: no real-world event may grant resources — enforced by keeping the location subsystem without write access to inventory tables.
- **Intel, never inventory**: repeat real visits raise `IntelLevel` only.
- **Fast travel = the phone's position at sync time** (not the PC's — a desktop has no GPS); **stranded** away from base; **death drops a recoverable cache**; **map/knowledge always persist**. These interact — see `design_travel_and_time.md` §4–5, `design_companion_and_sync.md` §3, and `design_expeditions_and_survival.md` §4 before touching any of them.
- **The phone is never a place to play.** Any proposal to add raids/inventory/base to the companion violates `design_companion_and_sync.md` §1 — file it, don't build it.
- **The world clock pauses when the app is closed** (except capped colony catch-up). Punishing absence is explicitly rejected.
- **Travel time is simulation-authoritative** (15 mph over real distance); on-screen movement is aesthetic.
- **Tile synthesis is deterministic** per (OSM data, cellSeed) — never cache-as-truth.
- **Privacy contracts** in `design_privacy_and_location.md` §1 bind every system; fuzzing lives in exactly one file on the phone (`companion/lib/capture/fuzz.dart`) — raw coordinates exist nowhere else.
- All tuning constants live in `game/config/tuning` (PC); provisional values are listed in the master plan's Core Configurations.

## 3. If you were spawned to "continue the work"
1. **Check `ongoing_general_errors.md`** for a fresh `### Issue N` / `### Decision N` block with a filled `Your selection:` line — that's your queue.
2. **No queue item** → work the master plan phases **in order** (Phase 0 first: companion capture + scout ledger with its stated exit criterion; Phase 1 stands up the PC project + pairing/sync). Do not jump to gameplay before Phase 0's exit criterion demonstrably passes on a real device.
3. **A design gap** — if a doc under-specifies something you need: make the smallest consistent choice, record it in `ongoing_general_errors.md`, and sync the design doc in the same commit.

## 4. THE LOOP (for every work item)
```
(1) STUDY the item + the design_*.md contract it touches.
(2) IMPLEMENT exactly as specified (specs are decisions, not suggestions).
(3) VALIDATE: PC work → engine build clean + game tests green; companion work →
    flutter analyze 0 errors + flutter test green; anything touching location capture,
    battery, or cross-device sync REQUIRES a real-device check, not just a simulator.
(4) BLOCKED or spec wrong? STOP; file with options; ask the user.
(5) RECORD: move resolved items to Resolved with what-was-solved; sync design docs.
(6) COMMIT: one item = one Conventional Commit, WHY in the body.
```

## 5. Where everything lives
| What | Where |
|---|---|
| Settled pillars + doc map + stack decision | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| System design contracts | `docs/design_*.md` |
| Engineering history + decision queue | `docs/ongoing_general_errors.md` |
| Manual test journeys | `docs/e2e_testing_journeys.md` |
| Doc/commit conventions | mirror Gaslight's `.agents/skills/` (import when repo is initialized) |
