# Agent Execution Guide — Active Build: Foundation Completion + Pokémon Pivot Prep (verified 2026-10-07)

**You are an engineering agent picking up Tenth Spring with zero prior context.** Two builds: a PC game (**Godot 4**, `game/`) and a thin phone companion (**Flutter**, `companion/`, location capture + sync only).

**The project pivoted on 2026-10-07.** It is now a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — where the overworld is the places the player has physically been. Pokémon sprites and data come from a ROM **the player supplies**, read on their own machine (the PokeMMO model). There is no Steam release. The location-capture, sync, and persistence foundation (Phases 0–1) is theme-agnostic and carries over unchanged — **most of your queue is finishing it.**

**What is approved for build right now:** the queue in §2, in order. **What NOT to touch:** §11 (already delivered), §12 (accepted equivalents), §13 (intentional decisions). §10 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, and literal string below is deliberate — implement as written; do not substitute your own values. If a value is genuinely impossible, keep the *intent*, deviate minimally, and note it in the commit body. If the design itself cannot work, **STOP and file it in `docs/ongoing_general_errors.md` with options for the human — do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, no sprites, no text banks, no stat tables, not even in a test fixture or a debug PNG. Never help anyone find a ROM. ROMs are supplied only by the human, from cartridges they own, via the `TENTH_SPRING_ROM` environment variable pointing **outside** the repo. A ROM in public git history stays there until history is rewritten. (`design_rom_asset_pipeline.md` §8)
2. Every change leaves the §1 battery green — that battery is the regression bar.
3. Anything touching location capture, battery, or cross-device sync **requires a real-device check**.
4. The golden invariants (§13) stay green, always.
5. Detailed behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps). This guide points at them; it does not restate them.
6. One item = one Conventional Commit, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.

---

## 1. Verified baseline (run this session, 2026-10-07)

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **17/17 passed** |
| Game static audit | `python3 game/tests/test_runner.py` (repo root) | **Lint pass; Golden Invariant 1 guard intact** |
| Game runtime tests | `godot --headless` | ⚠️ **NOT EXECUTED — Godot is not installed here.** `.gd` tests are verified by reading only. Never report a game-side runtime pass without Godot. |
| Game persistence | manual, Godot | **PASS (M8)** — atomic temp+rename fallback verified in `db.gd` & `db_test.gd`; fails loudly on null handle (F13/F11). |
| Public-repo IP guard | `python3 -I tools/check_no_nintendo_assets.py` | **PASS (M7)** — guard script in `test_runner.py`, pre-commit hook, CI (F18). |
| D3 device gate | 8 h background soak, real phone | ⚠️ **NOT YET RUN** — waiting on the human (Decision 5 = A). |

⛔ **Read before trusting any status note or commit message.** Passes 6–9 found commits claiming SQLite, socket transport, and nonce discipline that delivered none of them. The recurring pattern: plausible code written against infrastructure that does not exist, hidden by a permissive success path — `execute_query()` returns `true` on a null handle (`db.gd:79`), `_handle_incoming_peer()` is `pass` (`sync_server.gd:39-41`), `verify_sync_isolation()` is `return true` (`db.gd:172-173`). **A green suite proves nothing crashed. Verify in source, and check that the thing being called actually exists.**

---

## 2. Execution order

**Items 0–2 are unblocked — start there. Items 3–5 wait on the human.**

| # | Item | Why this position |
|---|---|---|
| 0 | **F18 — public-repo IP guard** | **First, before anything Pokémon-related.** It is the one irreversible mistake on the board: a ROM or ripped sprite in public git history can't be removed by deleting the file, and it is exactly what draws takedowns. ~1 hour. Item 5 cannot start until this exists. |
| 1 | **F13 — stop the silent data loss** | The world is lost on every quit, and `execute_query`'s `return true` guarantees no test notices. Correct under every outcome of Decision 7. |
| 2 | **F17 — retire zombie-era config names** | Tiny. Do it now so no later agent reads `colony` and reintroduces zombie concepts. |
| 3 | **F4 + F16 + F19 + F20 — real SQLite** | ⛔ **Blocked on Decision 7** (who installs the GDExtension). Must precede #4: transport writes through the DB layer. F19 (SQL injection) is mandatory here — this item is what would *activate* it. |
| 4 | **D4 + F14 + F15 — working transport** | ⛔ **Blocked on Decision 7** (libsodium binding). Closes Phase 1. |
| 5 | **Phase 2 — ROM importer: feasibility spike + implementation plan** | ⛔ **Blocked on Decision 9** (which ROM) **and the human supplying a dump** of it. Needs Item 0 first. Produces findings and a plan for human review — **not** a production importer. |

**▶ HUMAN actions** — Decision 7 (blocks 3–4) · Decision 9 + a ROM dump you made yourself (blocks 5) · Decision 8 (online play; blocks nothing in this build) · the D3 device soak (closes Phase 0; runs in parallel with everything).

Deferred (trigger-gated, **do not start**): **F7** — see §9.

---

## 3. Item 0 — F18: public-repo IP guard

**What this means for the user:** one accidental commit of a ROM or a ripped sprite to this public repo is the most likely way the whole project gets taken down — and deleting the file afterwards doesn't undo it.

### The gap
- `.gitignore` (30 lines) has rules for SQLite temp files but **none** for ROMs (`*.nds`, `*.gba`) or Nintendo container formats (`*.narc`, `*.ncgr`, `*.nclr`).
- There is no `tools/` directory, no `.githooks/`, and no `.github/workflows/` — nothing checks what gets committed.

### Implementation
1. Append to `.gitignore` under a `# Nintendo content — never commit (public repo)` header: `*.nds`, `*.gba`, `*.gb`, `*.gbc`, `*.3ds`, `*.cia`, `*.narc`, `*.ncgr`, `*.nclr`, `*.ncer`, `*.nanr`, `*.nscr`, `*.sdat`, `roms/`, `**/rom_cache/`, `**/rom_cache.tmp/`.
2. Create `tools/check_no_nintendo_assets.py` (stdlib only; run with `python3 -I`). Iterate `git ls-files -z`. Fail — exit 1, printing each offending path — when a tracked file: (a) has any extension from step 1; (b) begins with the 4 bytes `NARC`; (c) is ≥ 0x10 bytes and bytes `0x0C–0x0F` equal one of `CPUE`, `ADAE`, `APAE`, `IPKE`, `IPGE` (NDS game codes for Platinum, Diamond, Pearl, HeartGold, SoulSilver); or (d) has `rom_cache` anywhere in its path.
3. Add `.githooks/pre-commit` that runs the script against the staged index, and document `git config core.hooksPath .githooks` in the README's setup notes.
4. Add `.github/workflows/ip_guard.yml` running the script on every push and pull request.
5. Call the script from `game/tests/test_runner.py` `main()` (`:25`) **before** linting, so the §1 battery covers it.

### Validation
- **Automated (fails today, proving the guard exists):** in a scratch branch, create and stage a 16-byte file named `x.bin` whose first four bytes are `NARC` → the script exits 1 naming it. Repeat with a file carrying `CPUE` at offset `0x0C`, and with an empty file named `test.nds` → each fails. Today none of these is caught.
- **Automated:** on the clean repo the script exits 0.
- **Manual:** `git commit` of a staged `.nds` is refused by the hook.

### Blast radius (same commit)
`.gitignore` · new `tools/`, `.githooks/`, `.github/workflows/` · `game/tests/test_runner.py:25` · README setup notes · F18 status.

---

## 4. Item 1 — F13: stop the silent data loss

**What this means for the user:** right now every place they have ever walked is erased when they close the game, with no error shown. Once Pokémon exist, it would erase every Pokémon they caught.

### The gap
1. `db.gd:34` gates the engine on `ClassDB.can_instantiate("SQLite")`. **No SQLite GDExtension exists in this repo**, so this is always false and `_db` stays `null`.
2. `db.gd:76-79` — `execute_query()` **returns `true` when `_db` is null.** Every `CREATE TABLE`, `BEGIN`, `COMMIT`, and `ROLLBACK` reports success while doing nothing.
3. All state lives in Dictionaries (`db.gd:15-24`), and the JSON persistence that previously worked was deleted. `JSON_BAK_PATH` (`db.gd:9`) is a dangling constant.

The §B2 DDL at `db.gd:42-53` is correct — **keep it**; Item 3 activates it.

### Implementation
1. **Make the null path fail loudly.** `execute_query()` must `push_error()` naming the missing extension and return `false` when `_db` is null. Required under every option of Decision 7.
2. **Restore persistence now.** Serialise the Dictionary tables to `user://tenth_spring.db.tmp`, `flush()`, close, then `DirAccess.rename_absolute()` over the primary — atomic on all targets, so a reader sees the old world or the new one, never a torn one.
3. **On load:** if the primary is missing or unparseable, fall back to `.tmp` if it parses; otherwise start empty **and `push_warning()` loudly**. Never treat "unparseable" as "no data" silently.
4. **Boot diagnostic:** one `print()` at startup naming the live backend — `"storage: SQLite extension"` or `"storage: file fallback"`.

### Validation
- **Automated (fails today):** with `_db == null`, `execute_query("CREATE TABLE t(x);")` returns **`false`** and emits an error. Today it returns `true`.
- **Automated (fails today):** write a `map_cell`, reload the store, assert the row survives.
- **Automated:** truncate the primary to 0 bytes, reload → the previous world is recovered from `.tmp`, not silently empty.
- **Manual:** `godot --headless`, add data, quit, relaunch → the map survives and the boot line names the backend.

### Blast radius (same commit)
`game/autoloads/db.gd` (`execute_query`, save/load, boot diagnostic, `JSON_BAK_PATH`) · `game/tests/db_test.gd` · F11/F13 status.

---

## 5. Item 2 — F17: retire zombie-era config names

**What this means for the user:** nothing visible — this stops the next agent from reading "colony" and rebuilding zombie mechanics into a Pokémon game.

### The gap
`game/config/tuning.json:10` `deathCacheDecayGameDays` and `:11` `colonyGrowthTickGameDays`; `game/autoloads/config.gd:11-12` and `:36-37` load them as `death_cache_decay_game_days` / `colony_growth_tick_game_days`.

### Implementation
1. Rename the JSON keys to `bagCacheDecayGameDays` and `hauntGrowthTickGameDays`; rename the GDScript vars to `bag_cache_decay_game_days` and `haunt_growth_tick_game_days`. Values unchanged (3 and 1).
2. Add the remaining master-plan constants to `tuning.json` with their documented values: `bicycleSpeedMultiplier` 2.0, `grassEncounterRate` 0.10, `hauntedInteriorEncounterRate` 0.12, `legendaryRespawnGameDays` 30, `partySize` 6. Load them in `config.gd`.

### Validation
- **Automated:** `grep -rniE "colony|death_?cache" game/` returns **nothing**.
- **Automated:** after `Config` loads, `haunt_growth_tick_game_days == 1`, `bag_cache_decay_game_days == 3`, `grass_encounter_rate == 0.10`.

### Blast radius (same commit)
`game/config/tuning.json` · `game/autoloads/config.gd` · F17 status.

---

## 6. Item 3 — F4 + F16 + F19 + F20: make the SQLite engine real

**⛔ Blocked on Decision 7.** Decision 6 = A settled *that* we use SQLite; Decision 7 settles *how the binary gets here*. Do not start by writing more SQL — three passes already did that against a class that cannot instantiate.

**What this means for the user:** whether their world — and soon their Pokémon — survives a crash intact, and whether the map still loads quickly once they've scouted a whole city.

### The gap
- The §B2 DDL (`db.gd:42-53`) never executes because `_db` is always null.
- Every accessor reads and writes Dictionaries (`db.gd:15-24`); `_run_migrations()` (`:55-59`) writes into `_meta_table` alongside SQL — a shadow layer that will diverge once SQLite is real.
- **F16** — the header (`db.gd:3-5`) claims engine-enforced constraints and ACID; both false today.
- **F19 (security)** — `insert_visit_log` (`db.gd:135`) string-formats `peer_id` and `kind` — **network input from the phone** — into SQL. Activating SQLite without fixing this ships SQL injection.
- **F20** — `verify_sync_isolation()` (`db.gd:172-173`) is `return true`.

### Implementation
1. Confirm `ClassDB.can_instantiate("SQLite")` is true in a scratch scene. If not, STOP — the blocker is Decision 7.
2. Open at `DB_PATH`, run the existing DDL, and **verify the tables exist** by querying `sqlite_master`.
3. **Every query uses bound parameters.** No value from any sync payload — or anywhere else — is ever string-formatted into SQL. Rewrite `insert_visit_log` and every other formatted query.
4. Delete the Dictionary tables (`db.gd:15-24`) and route every accessor through SQL, keeping public signatures unchanged.
5. Implement the §B6 migration runner against the real `meta` table — ordered, idempotent, never destructive to `visit_log` or `map_cell`.
6. Import any file-backed world from Item 1's format, then rename it to `.jsonbak`; never delete it.
7. Let SQLite own durability (journal/WAL); remove Item 1's manual temp+rename only once SQLite is genuinely live, saying so in the commit body.
8. Delete `verify_sync_isolation()` (F20) — the static scan is the real guard. Rewrite the `db.gd` header so every clause is true (F16).

### Validation
- **Automated (fails today):** insert a duplicate `(peer_id, seq)` → the **engine** rejects it with a constraint violation.
- **Automated (fails today — proves F19 is closed):** call `insert_visit_log` with `kind = "visit'); DROP TABLE map_cell;--"` → the row stores that literal string and `map_cell` still exists.
- **Automated:** `sqlite_master` lists all ten §B2 tables; `grep -n "Dictionary = {}" game/autoloads/db.gd` finds no state tables; `grep -n "verify_sync_isolation" game/` finds nothing.
- **Automated:** the migration fixture upgrades with zero `visit_log` rows lost; `.jsonbak` is left in place.

### Blast radius (same commit)
`game/autoloads/db.gd` · `game/tests/db_test.gd` · `game/tests/idempotent_sync_test.gd` · Decision 4 + Decision 7 (record the binding) · F4/F16/F19/F20 status.

---

## 7. Item 4 — D4 + F14 + F15: a transport that actually moves bytes

**⛔ Blocked on Decision 7** (libsodium binding).

**What this means for the user:** this is still the missing half of the product — walking around cannot reach the game until it works.

### The gap
- **F14** — `sync_server.gd:39-41`: `_handle_incoming_peer(_stream)` is `pass`; connections are accepted and dropped.
- No mDNS on either side, and no socket code in `companion/lib/` (`grep -rn "Socket|MDnsClient|multicast_dns|connect(" companion/lib/` → nothing).
- **F15** — `transport.dart:14` `generateMonotonicNonce` has zero callers; no counter is persisted; the cipher is ChaCha20, not the spec'd XChaCha20.
- **Keep, don't rewrite:** `pairing.dart` and `transport.dart`'s AEAD + payload builders are correct.

### Implementation
1. **Nonce scheme first (F15):** either `Xchacha20.poly1305Aead()` (192-bit, random-safe), or ChaCha20 with a counter **persisted** beside the session key in `FlutterSecureStorage`, incremented per message, never reset while the key lives. Wire it inside `encryptChunk` so callers cannot supply their own. Record the choice as an accepted equivalent.
2. **Wire-compat spike:** encrypt in Dart, decrypt in Godot, against a committed shared test vector.
3. **Fill in `_handle_incoming_peer` (F14):** read length-prefixed frames, decrypt, dispatch `HELLO` / `BATCH` to `handle_hello` / `process_batch`, write back an encrypted `ACK`. Poll the stream rather than assuming one frame per accept.
4. **Discovery:** advertise `_tenthspring._tcp` from the PC; resolve via `multicast_dns` on the phone; manual-IP fallback.
5. **Companion socket layer** driving the existing helpers; QR pairing (`{v:1, pcId, pcPubKeyB64, mdnsName}`) with `mobile_scanner`.
6. Refuse on schema-version mismatch. Never hand-roll crypto.

### Validation
- **Automated (the first assertion in the project that can prove a transport exists):** run `companion/test/fixtures/errand_day.gpx` through capture → sync and assert the expected `map_cell` / `place_node` / `visit_log` rows land on the PC.
- **Automated:** encrypting the same message twice yields different ciphertext; a persisted counter survives a simulated restart.
- **Automated:** replay ⇒ `appliedCount == 0`; socket dropped before `ACK` ⇒ final state equals a clean run; one flipped ciphertext byte ⇒ rejected.
- **Manual device gate:** real phone + PC on one Wi-Fi; Wireshark shows **ciphertext only**, nothing finer than 3 decimal places.

### Blast radius (same commit)
`game/autoloads/sync_server.gd` · `companion/lib/sync/transport.dart` · new companion socket/mDNS code · `companion/lib/main.dart` · Decision 4 + Decision 7 + F14/F15 status.

---

## 8. Item 5 — Phase 2: ROM importer feasibility spike + implementation plan

**⛔ Blocked on Decision 9 (which ROM) and on the human supplying a dump they made from their own cartridge.** Requires Item 0 (the IP guard) first. **This item produces findings and a plan for human review — it does not build the production importer.**

**What this means for the user:** this is the moment the game can show its first Pokémon. Everything Pokémon-facing — battles, encounters, the Pokédex — depends on it.

### The gap
- No `game/rom/` exists; the game cannot display a single Pokémon.
- The riskiest unknowns, marked **verify** in `design_rom_asset_pipeline.md` §4: Platinum's sprite-decryption direction and seed source (they differ from Diamond/Pearl), the six-files-per-species indexing in `pl_pokegra.narc`, and Gen 4 text-bank decoding.

### Implementation
1. **Precondition:** `TENTH_SPRING_ROM` is set and points **outside** the repo. If it is unset, STOP and report — never download, search for, or link to a ROM.
2. Write spike code under `game/rom/spike/`. **All spike output goes to `user://rom_cache_spike/`** — never into the repo. Run Item 0's guard before every commit.
3. Read the NDS header; assert game code `CPUE` (or the code chosen in Decision 9). Parse FNT/FAT; locate each archive in the design doc's §5 table by path; record the actual file counts.
4. Decode **Giratina (#487)**'s front sprite end to end into a PNG; determine the exact decryption rule and record it.
5. Decode the species-name entries for #487, #442, and #94 from `/msgdata/pl_msg.narc`.
6. Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–§5 with what you confirmed, citing the `pret/pokeplatinum` file or experiment that confirmed it.
7. Write `docs/implementation_plan_rom_importer.md` to the depth of `implementation_plan_foundation.md`: module responsibilities, data layouts, the resumable tmp→rename cache write, the §7 validation suite, and test strategy (ROM tests run only when `TENTH_SPRING_ROM` is set; skipped, never faked, in CI).
8. **PAUSE for human review.** Do not build the production importer until the plan is approved.

### Validation
- **Automated:** archive file counts match the design table — 2964 / 508 / 508 / 508 / 471 / 446 / 711 / 724 — or the table is corrected with evidence.
- **Automated (falsifies a wrong decryption):** the decoded Giratina PNG's per-pixel colour variance exceeds a threshold that random "static" cannot pass and has ≤ 16 distinct colours (4bpp). A wrong rule produces noise.
- **Automated:** the three decoded names are non-empty and decode cleanly through the character table.
- **Manual:** `git status` after the spike shows no ROM, cache, or PNG; `tools/check_no_nintendo_assets.py` exits 0.

### Blast radius (same commit)
`game/rom/spike/` · `docs/design_rom_asset_pipeline.md` §4–5 · new `docs/implementation_plan_rom_importer.md` · Decision 9 status.

---

## 9. Deferred — trigger-gated, do NOT start

**F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats home as a **256 m** cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding). Nothing writes `base_state.home_cell_*` today. Reconcile then.

---

## 10. Phase roadmap — scope, not an approved queue

Full phase list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order: 0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward, write its `implementation_plan_<phase>.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before 5–9: every Pokémon-facing system reads through `asset_db`.

---

## 11. Already delivered — do NOT rework
Phase 0 capture pipeline (`LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, scout-ledger UI) · D3 background capture **code** (platform settings, permissions, `main.dart:9`) — device gate pending · F1 relocation unit math · F2 transaction + rollback path · F3 cell/tile grid unification (256 m / 16 m) · F5 Godot-headless-aware test runner · F6 `base_access_meters` stranded threshold · F8 both-platform settings test · F9 Android background-permission flow + banner · `simulateFailure` hook removed · **`pairing.dart` / `transport.dart` crypto helpers** · DB accessors (`get_base_state`, `set_player_tile`) · idempotent sync apply · the §B2 DDL text (`db.gd:42-53`) · golden-invariant static guards.

## 12. Accepted equivalents — do NOT "fix" these back
- `relocation_manager.gd:63-72` implements "nearest-revealed-tile snapping" as a minimal-circle reveal around the spawn cell, then placement at the computed tile. Same guarantee — the player always stands on revealed ground.
- `os_location_source.dart:25` — `nativeVisits()` returns `null`; native visit events are an optional hint and custom clustering covers them.
- `game/tests/test_runner.py` is a static lint + capability guard, not the sync test gate.

## 13. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever** (standing constraint 1). Species, moves, and items are referenced by number in repo data; names, stats, and sprites come from the player's ROM cache through `asset_db` only. The **phone companion never contains Nintendo assets or names**.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell` / `place_node` / `visit_log` (+ transient `bodyFix`). **When bag, party, PC box, or Pokémon tables are added, extend the isolation scan's forbidden tokens in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.**
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist.
- **Fast travel = the phone's position at sync time.** **Stranded:** the PC box is reachable only within `baseAccessMeters`. **Healing only at home. Blackout drops the bag, never Pokémon.** The map and Pokédex always persist.
- **Mechanics are Generation IV** (17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5) — `design_creatures_and_battles.md`.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot (PC) + Flutter (companion), SQLite (Decision 6 = A), LAN-only E2E sync. **Never hand-roll crypto.** No Steam, no monetization.
- Capture settings (accuracy `medium`, 25 m, 2 min) and `tuning.json` values are deliberate battery/balance decisions.

## 14. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, distribution | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Build steps for Phases 0–1 | `docs/implementation_plan_foundation.md` |
| ROM import, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types, damage, catching, party, PC, blackout | `docs/design_creatures_and_battles.md` |
| Spawn zones, ghost share, levels, haunted zones, legendaries | `docs/design_encounters_and_haunted_zones.md` |
| Exploring sites, familiarity, healing scarcity | `docs/design_expeditions_and_survival.md` |
| Items by place, bag, home safehouse | `docs/design_resources_and_base.md` |
| Visits → tiles, tall grass, landmarks | `docs/design_world_generation.md` |
| Schemas | `docs/design_game_state_and_models.md` |
| Travel, clock, fast travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync | `docs/design_companion_and_sync.md` |
| Original vs. ROM-sourced art | `docs/design_art_direction.md` |
| Privacy | `docs/design_privacy_and_location.md` |
| Decisions, findings, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md contract it names. Specs are decisions.
2 PLAN      Building a phase with no implementation_plan_*.md at build depth? Write one
            FIRST and PAUSE for human review before coding. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written. Honor §13 and the standing constraints — above all, no
            Nintendo content in the repo.
4 VALIDATE  This item's validation, then the full §1 battery (including the IP guard).
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, or you'd need a ROM you don't have →
            STOP. File in ongoing_general_errors.md with options. Do not improvise.
6 RECORD    Move the item to Resolved with what-was-solved; update any design doc whose
            behavior changed — in this same commit.
7 COMMIT    One item = one Conventional Commit, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F18)** — `.gitignore` rules, guard script, pre-commit hook, and CI workflow in place; a staged `NARC`/`CPUE`/`.nds` file is rejected.
- [x] **Item 1 (F13)** — `execute_query` fails loudly on a null handle; persistence restored with atomic temp+rename; boot line names the backend.
- [x] **Item 2 (F17)** — no `colony` / `death_cache` names remain in `game/`; pivot constants loaded.
- [ ] **Decision 7 answered**, then **Item 3** — extension verified present, DDL executes, bound parameters everywhere (injection test passes), Dictionary shadow and `verify_sync_isolation` deleted, header true.
- [ ] **Item 4** — nonce wired and persisted; listener reads real frames; mDNS both sides; loopback GPX sync passes; replay is a no-op; Wireshark shows ciphertext only. **Closes Phase 1.**
- [ ] **D3 device soak run** (Decision 5 = A). **Closes Phase 0.**
- [ ] **Decision 9 answered and a ROM supplied**, then **Item 5** — verify markers resolved, `implementation_plan_rom_importer.md` written, **paused for review**.
- [ ] Full §1 battery green, including Godot headless tests actually executing.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is building the ROM importer from the *approved* plan, then Phase 3. Other legitimate triggers: (a) a new item in `ongoing_general_errors.md` with a filled `Your selection:`, (b) the §1 battery regressing on a fresh checkout, (c) the F7 trigger firing, or (d) the human assigning something. Otherwise report that the queue is complete and stop.
