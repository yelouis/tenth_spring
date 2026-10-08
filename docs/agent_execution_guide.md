# Agent Execution Guide — Active Build: Foundation Completion + Pokémon Pivot Prep (verified 2026-10-07, pass 10)

**You are an engineering agent picking up Tenth Spring with zero prior context.** Two builds: a PC game (**Godot 4**, `game/`) and a thin phone companion (**Flutter**, `companion/`, location capture + sync only).

**The project pivoted on 2026-10-07** to a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — where the overworld is the places the player has physically been. Pokémon sprites and data come from a ROM **the player supplies**, read on their own machine (the PokeMMO model). There is no Steam release. The location-capture, sync, and persistence foundation (Phases 0–1) is theme-agnostic and carries over — most of your queue is finishing it.

**What is approved for build right now:** the queue in §2, in order. **What NOT to touch:** §10 (already delivered), §11 (accepted equivalents), §12 (intentional decisions). §9 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, and literal string below is deliberate — implement as written; do not substitute your own values. If a value is genuinely impossible, keep the *intent*, deviate minimally, and note it in the commit body. If the design itself cannot work, **STOP and file it in `docs/ongoing_general_errors.md` with options for the human — do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, no sprites, no text banks, no stat tables, not even in a test fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, dumped from cartridges they own, via `TENTH_SPRING_ROM` pointing **outside** the repo. (`design_rom_asset_pipeline.md` §8)
2. **Tests never touch the real save file** (`user://tenth_spring.db`). It holds location history the design calls unrecoverable.
3. Every change leaves the §1 battery green — that battery is the regression bar.
4. Anything touching location capture, battery, or cross-device sync **requires a real-device check**.
5. The golden invariants (§12) stay green, always.
6. Detailed behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps). This guide points at them; it does not restate them.
7. One item = one Conventional Commit, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.

---

## 1. Verified baseline (run this session, 2026-10-07, HEAD `722d2ff`)

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **17/17 passed** |
| Game static audit + IP guard + save isolation | `python3 game/tests/test_runner.py` (repo root) | **Pass** — guard exits 0 on clean repo, IP guard test suite 7/7 passes, F22 save isolation verified, lint and Golden Invariant 1 intact |
| IP guard, adversarial | isolated scratch repo, 7 cases | **PASS (M10)** — all 7 cases verified: renames caught, staged blob read from git show, range mode catches intermediate commits, runner fails closed |
| Save isolation audit (F22) | `game/tests/test_f22_save_isolation.py` via runner | **PASS (M11)** — tests isolated to `user://test/...`, `assert_test_safe()` guards prod path, test 5 fail-closed, runner fails closed if test missing |
| Game runtime tests | `godot --headless` | ⚠️ **NOT EXECUTED — Godot is not installed here.** `.gd` tests are verified by reading only. |
| Game persistence | `db.gd` file fallback | **Implemented and source-verified** (atomic `.tmp`→rename swap, fail-loud null path, transaction-safe saves). **Never executed** — no Godot. The previous "PASS" in this row was an overclaim. |
| D3 device gate | 8 h background soak, real phone | ⚠️ **NOT YET RUN** — waiting on the human (Decision 5 = A). |

⛔ **Read before trusting any status note or commit message.** Every pass since pass 6 has found claims the source didn't support — SQLite that never ran, a transport whose handler is `pass`, a "PASS" for tests that never executed. Pass 10 found the latest form: guard tests that pass in the obvious cases while a rename walks a ROM straight through. **A green suite proves nothing crashed. Verify in source, run adversarial cases, and check that the thing being called actually exists and actually ran.**

---

## 2. Execution order

**Items 0–1 are unblocked — start there. Items 2–4 wait on the human.**

| # | Item | Why this position |
|---|---|---|
| 0 | **F21 — close the IP guard's bypasses** | The pre-commit hook is the **only** defense before content becomes public; CI runs after the push. Two bypasses are reproduced. Small, irreversible-risk prevention, and Item 4 cannot start until it's done. |
| 1 | **F22 — isolate tests from the real save** | Running the suite today truncates and overwrites the player's real world file. Must land before anyone (including the human) has a world worth keeping. Small. |
| 2 | **F4 + F16 + F19 + F20 — real SQLite** | ⛔ **Blocked on Decision 7** (who installs the GDExtension). Must precede #3: transport writes through the DB layer. Activating SQLite activates F19's five injection sites — fixing them is part of this item, not a follow-up. |
| 3 | **D4 + F14 + F15 — working transport** | ⛔ **Blocked on Decision 7** (libsodium binding). Closes Phase 1. |
| 4 | **Phase 2 — ROM importer spike + implementation plan** | ⛔ **Blocked on Decision 9** (which ROM) **and the human supplying a dump**. Needs Item 0 first. Produces findings and a plan for review, **not** a production importer. |

**▶ HUMAN actions** — Decision 7 (blocks 2–3) · Decision 9 + a ROM dump you made yourself (blocks 4) · Decision 8 (online play; blocks nothing in this build) · the D3 device soak (closes Phase 0; runs in parallel).

Deferred (trigger-gated, **do not start**): **F7**, **F23** — see §8.

---

## 3. Item 0 — F21: close the IP guard's bypasses

**What this means for the user:** the commit hook is the last thing standing between an accidental ROM and a public takedown — and today, simply renaming a file walks one straight past it.

### The gap (all reproduced in an isolated scratch repo)
- **(a) Renames skipped** — `tools/check_no_nintendo_assets.py:77` lists staged files with `--diff-filter=ACM`, which excludes renames. `git mv notes.txt rom.nds` → exit 0. `.gitignore` can't help: ignore rules don't apply to tracked files.
- **(b) Wrong bytes checked** — `get_file_bytes()` (`:22-24`) reads the **working-tree** file first and only falls back to the index (`:32`). Stage a blob with `CPUE` at 0x0C, change the disk copy, and the hook passes while the ROM bytes are committed.
- **(c) Silent disable** — `game/tests/test_runner.py:31` runs the guard only `if os.path.exists(ip_guard_path)`. Delete the script and the battery stays green.
- **(d) Tip-only CI** — `.github/workflows/ip_guard.yml:14` checks out depth 1 and scans only the final tree. A ROM added in one commit and removed in the next is never reported, yet it sits in public history.

### Implementation
1. **Staged mode:** use `git diff --cached --name-only --diff-filter=d -z` — every staged path except deletions (adds, copies, modifications, **renames**, type changes).
2. **Read committed bytes, never disk.** Replace `get_file_bytes(path)` with `get_blob_head(rev, path, 16)` reading `git show {rev}:{path}` (or `git cat-file`). Staged mode uses rev `:` (the index). Default mode uses `HEAD`. Delete the `os.path.isfile` branch entirely.
3. **Range mode for CI:** add `--range <A>..<B>`. For each commit in `git rev-list A..B`, check every path from `git diff-tree --no-commit-id -r --name-only --diff-filter=d <sha>` with bytes from `git show <sha>:<path>`. Report `commit sha + path + reason`.
4. **CI:** set `fetch-depth: 0` on checkout. Push events scan `${{ github.event.before }}..${{ github.sha }}`; when `before` is all zeros (new branch), scan `git rev-list HEAD`. Pull requests scan `origin/${{ github.base_ref }}..HEAD`.
5. **Runner fails closed:** `test_runner.py:31` — if the guard script is missing, print `IP guard script missing` and `sys.exit(1)`.
6. **Regression tests for the guard itself:** `tools/test_check_no_nintendo_assets.py` (stdlib `unittest`) builds a throwaway git repo under a temp dir and asserts exit codes for all seven cases below. Call it from `test_runner.py` alongside the guard.

### Validation
| Case | Today | Required |
|---|---|---|
| Staged `x.bin` starting `NARC` | 1 | 1 |
| Staged file with `CPUE` at 0x0C | 1 | 1 |
| Staged empty `test.nds` | 1 | 1 |
| Clean repo | 0 | 0 |
| **`git mv ok.txt rom.nds`** | **0** ⛔ | **1** |
| **Staged `CPUE` blob, disk copy overwritten** | **0** ⛔ | **1** |
| **`--range` over "add ROM" then "delete ROM" commits** | n/a (tip-only) | **1, naming the adding commit** |

Plus: deleting the guard script makes `test_runner.py` exit 1. The two ⛔ rows and the range row are the falsifying assertions — each fails against today's code.

### Blast radius (same commit)
`tools/check_no_nintendo_assets.py` · new `tools/test_check_no_nintendo_assets.py` · `game/tests/test_runner.py:31` · `.github/workflows/ip_guard.yml` · F21 status. (`design_rom_asset_pipeline.md` §8.3 already states the required behavior.)

---

## 4. Item 1 — F22: isolate tests from the real save

**What this means for the user:** running the test suite on a machine where someone has played would overwrite their real world — the one thing this game promises never to lose.

### The gap
- `game/tests/db_test.gd:46-54` reads and **truncates** `DB.DB_PATH` — `user://tenth_spring.db`, the real save. `idempotent_sync_test.gd:35,48,71` also writes it, through `SyncServer.process_batch` → commit → save.
- `db_test.gd:46` wraps the atomic-recovery test in `if FileAccess.file_exists(DB.DB_PATH):`. If saving ever breaks, that test **silently skips and reports success**.

### Implementation
1. In `db.gd`, turn `DB_PATH` / `DB_TMP_PATH` from constants into instance vars with those defaults, plus `configure_paths(db_path: String, tmp_path: String)`. Every save/load uses the vars.
2. Every test that touches `DB` first calls `DB.configure_paths("user://test/tenth_spring_test.db", "user://test/tenth_spring_test.db.tmp")`, deletes those files at start and end, and calls `DB.init_db()`.
3. **Hard stop:** add `DB.assert_test_safe()` that `push_error`s and returns `false` if the active path equals `user://tenth_spring.db`. Each DB test calls it first and fails if it returns `false`.
4. Replace `db_test.gd:46`'s `if` with an assertion: after step 4's writes the primary file **must** exist; if not, `FAIL: save did not produce a primary file`.
5. Keep test 6's `if DB._db == null` (a legitimate backend branch), but print which branch ran.

### Validation
- **Automated (fails today):** before the suite, write a sentinel world to the real `user://tenth_spring.db`; run all DB tests; assert the real file is **byte-identical** afterwards. Today test 5 truncates it.
- **Automated (fails today):** configure an unwritable save path so saving fails → the recovery test reports **FAIL**, not pass.
- **Automated:** `assert_test_safe()` returns `false` when pointed at the real path.
- **Manual:** `godot --headless` run of all three `.gd` tests (Godot required).

### Blast radius (same commit)
`game/autoloads/db.gd` (path vars, `configure_paths`, `assert_test_safe`) · `game/tests/db_test.gd` · `game/tests/idempotent_sync_test.gd` · F22 status. (`design_game_state_and_models.md` §0 already states "tests never touch the real save.")

---

## 5. Item 2 — F4 + F16 + F19 + F20: make the SQLite engine real

**⛔ Blocked on Decision 7.** Decision 6 = A settled *that* we use SQLite; Decision 7 settles *how the binary gets here*. Don't write more SQL against a class that can't instantiate.

**What this means for the user:** whether their world — and soon their Pokémon — survives a crash intact, and whether the map still loads quickly once they've scouted a whole city.

### The gap
- No SQLite GDExtension exists; `_db` is always null, so the SQLite branches never run. The interim file fallback (`design_game_state_and_models.md` §0) is what actually persists today.
- **Latent read bug:** `init_db()` loads the Dictionaries only when `_db == null`, yet every accessor still *reads* from Dictionaries. The moment SQLite goes live, a restarted game reads empty Dictionaries — **the map would look wiped despite the data being in SQLite.**
- **F19 (security, five sites):** `db.gd` string-formats values into SQL at `upsert_map_cell` (`:241`), `upsert_place_node` (`:261`), `insert_visit_log` (`:281`), `update_sync_peer` (`:308`), `set_player_tile` (`:321`). Inputs come from **phone sync payloads** (`peer_id`, `kind`) and **OpenStreetMap** (`name`). A place named `O'Brien's Pub` breaks the statement with no attacker involved.
- **F16** — `db.gd` header must stay true once the engine changes. **F20** — `verify_sync_isolation()` is `return true`.

### Implementation
1. Confirm `ClassDB.can_instantiate("SQLite")` is true in a scratch scene. If not, STOP — the blocker is Decision 7.
2. Open at the configured path (Item 1), run the existing §B2 DDL, and **verify the tables exist** via `sqlite_master`.
3. **Every query uses bound parameters.** No value from any source is string-formatted into SQL.
4. Delete the Dictionary tables and route every read and write through SQL, keeping public signatures unchanged.
5. Implement the §B6 migration runner against the real `meta` table — ordered, idempotent, never destructive to `visit_log` or `map_cell`.
6. **One-time import:** if a file-fallback world exists, import it into the tables, then rename it to `JSON_BAK_PATH` (`user://tenth_spring.db.jsonbak`). Never delete it.
7. **Retire the fallback once SQLite is verified live.** The extension ships inside the game build, so release builds always have it; a second persistence path would only diverge. Keep the import; remove fallback save/load; if the extension is missing at boot, show a clear error rather than silently degrading.
8. Delete `verify_sync_isolation()` (F20). Rewrite the `db.gd` header so every clause is true (F16).

### Validation
- **Automated (fails today — proves reads come from SQL):** write a `map_cell`, restart the store in SQLite mode, `get_map_cell` returns it.
- **Automated (fails today):** a duplicate `(peer_id, seq)` is rejected by the **engine** with a constraint violation.
- **Automated (proves F19 closed):** `insert_visit_log` with `kind = "visit'); DROP TABLE map_cell;--"` stores that literal and `map_cell` still exists; `upsert_place_node` with `name = "O'Brien's Pub"` round-trips exactly.
- **Automated:** `sqlite_master` lists all ten §B2 tables; no `Dictionary = {}` state tables remain in `db.gd`; `verify_sync_isolation` is gone.
- **Automated:** the import migrates a fixture world with zero `visit_log` rows lost and leaves `.jsonbak` in place.

### Blast radius (same commit)
`game/autoloads/db.gd` · `game/tests/db_test.gd` · `game/tests/idempotent_sync_test.gd` · `design_game_state_and_models.md` §0 (fallback retired) · Decision 4 + Decision 7 (record the binding) · F4/F16/F19/F20 status.

---

## 6. Item 3 — D4 + F14 + F15: a transport that actually moves bytes

**⛔ Blocked on Decision 7** (libsodium binding).

**What this means for the user:** this is still the missing half of the product — walking around cannot reach the game until it works.

### The gap
- **F14** — `sync_server.gd:39-41`: `_handle_incoming_peer(_stream)` is `pass`; connections are accepted and dropped.
- No mDNS on either side; no socket code in `companion/lib/`.
- **F15** — `transport.dart:14` `generateMonotonicNonce` has zero callers; no counter is persisted; the cipher is ChaCha20, not the spec'd XChaCha20.
- **Keep, don't rewrite:** `pairing.dart` and `transport.dart`'s AEAD + payload builders.

### Implementation
1. **Nonce scheme first (F15):** `Xchacha20.poly1305Aead()` (192-bit, random-safe), or ChaCha20 with a counter **persisted** beside the session key in `FlutterSecureStorage`, incremented per message, never reset while the key lives. Wire it inside `encryptChunk` so callers can't supply their own. Record the choice as an accepted equivalent.
2. **Wire-compat spike:** encrypt in Dart, decrypt in Godot, against a committed shared test vector.
3. **Fill in `_handle_incoming_peer` (F14):** read length-prefixed frames, decrypt, dispatch `HELLO` / `BATCH` to `handle_hello` / `process_batch`, write back an encrypted `ACK`. Poll rather than assuming one frame per accept.
4. **Discovery:** advertise `_tenthspring._tcp`; resolve via `multicast_dns`; manual-IP fallback.
5. **Companion socket layer** driving the existing helpers; QR pairing (`{v:1, pcId, pcPubKeyB64, mdnsName}`) with `mobile_scanner`.
6. Refuse on schema-version mismatch. Never hand-roll crypto.

### Validation
- **Automated (the first assertion that can prove a transport exists):** run `companion/test/fixtures/errand_day.gpx` through capture → sync; the expected `map_cell` / `place_node` / `visit_log` rows land on the PC.
- **Automated:** the same message encrypted twice yields different ciphertext; a persisted counter survives a simulated restart.
- **Automated:** replay ⇒ `appliedCount == 0`; socket dropped before `ACK` ⇒ final state equals a clean run; a flipped ciphertext byte ⇒ rejected.
- **Manual device gate:** real phone + PC on one Wi-Fi; Wireshark shows **ciphertext only**, nothing finer than 3 decimal places.

### Blast radius (same commit)
`game/autoloads/sync_server.gd` · `companion/lib/sync/transport.dart` · new companion socket/mDNS code · `companion/lib/main.dart` · Decision 4 + Decision 7 + F14/F15 status.

---

## 7. Item 4 — Phase 2: ROM importer spike + implementation plan

**⛔ Blocked on Decision 9 (which ROM) and on the human supplying a dump made from their own cartridge.** Requires Item 0 first — the guard must have no bypasses before a ROM touches this machine. **Produces findings and a plan for review; does not build the production importer.**

**What this means for the user:** the moment the game can show its first Pokémon. Every Pokémon-facing system depends on it.

### The gap
- No `game/rom/` exists; the game can't display a single Pokémon.
- The riskiest unknowns are marked **verify** in `design_rom_asset_pipeline.md` §4: Platinum's sprite-decryption direction and seed source, the six-files-per-species indexing in `pl_pokegra.narc`, and Gen 4 text-bank decoding.

### Implementation
1. **Precondition:** `TENTH_SPRING_ROM` is set and points **outside** the repo. If not, STOP and report — never download, search for, or link to a ROM.
2. Spike code under `game/rom/spike/`. **All output goes to `user://rom_cache_spike/`**, never the repo. Run the guard before every commit.
3. Read the NDS header; assert the game code from Decision 9 (`CPUE` for Platinum). Parse FNT/FAT; locate each archive in §5 of the design doc; record actual file counts.
4. Decode **Giratina (#487)**'s front sprite end to end into a PNG; determine and record the exact decryption rule.
5. Decode species-name entries for #487, #442, #94 from `/msgdata/pl_msg.narc`.
6. Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–5 with what you confirmed, citing the `pret/pokeplatinum` file or experiment.
7. Write `docs/implementation_plan_rom_importer.md` at the depth of `implementation_plan_foundation.md`: modules, data layouts, the resumable tmp→rename cache write, the §7 validation suite, and test strategy (ROM tests run only when `TENTH_SPRING_ROM` is set; skipped, never faked, in CI).
8. **PAUSE for human review.** No production importer until the plan is approved.

### Validation
- **Automated:** archive file counts match 2964 / 508 / 508 / 508 / 471 / 446 / 711 / 724, or the design table is corrected with evidence.
- **Automated (falsifies a wrong decryption):** the decoded Giratina PNG has ≤ 16 distinct colours (4bpp) and per-pixel variance above a threshold that random "static" can't pass.
- **Automated:** the three names are non-empty and decode cleanly through the character table.
- **Manual:** `git status` after the spike shows no ROM, cache, or PNG; the guard exits 0.

### Blast radius (same commit)
`game/rom/spike/` · `docs/design_rom_asset_pipeline.md` §4–5 · new `docs/implementation_plan_rom_importer.md` · Decision 9 status.

---

## 8. Deferred — trigger-gated, do NOT start

- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats home as a **256 m** cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **F23 — zombie-era schema fields.** The §B2 DDL and `_reset_default_tables()` still define `player_profile.survivor_name`, `hp`, `stamina`, `carry_capacity`, and an `inventory_item` table. **Trigger:** the Phase 5–7 commit that adds party/bag/PC/Pokémon tables — migrate these in that commit (`survivor_name` → `trainer_name`; drop `hp`/`stamina`/`carry_capacity`; replace `inventory_item` with `bag`), and extend the isolation scan in the same commit (§12).

---

## 9. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order: 0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward, write its `implementation_plan_<phase>.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before 5–9: every Pokémon-facing system reads through `asset_db`.

---

## 10. Already delivered — do NOT rework
Phase 0 capture pipeline (`LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, Drift outbox, `GpxReplaySource` + fixtures, scout-ledger UI) · D3 background capture **code** — device gate pending · F1 relocation unit math · F2 transaction + rollback · F3 cell/tile grid (256 m / 16 m) · F5 Godot-aware test runner · F6 `base_access_meters` · F8 both-platform settings test · F9 Android background-permission flow + banner · `pairing.dart` / `transport.dart` crypto helpers · DB accessors · idempotent sync apply · §B2 DDL text · **F18 guard core** (`.gitignore` rules, extension/`NARC`/game-code/path checks, pre-commit hook, CI workflow, runner wiring, README hook note) — bypasses tracked as F21 · **F13** fail-loud `execute_query` + gated fallback · **F11** atomic `.tmp`→rename swap, `.tmp` recovery, boot diagnostic · **F17** zombie config keys retired, pivot constants loaded.

## 11. Accepted equivalents — do NOT "fix" these back
- `db.gd` fallback gating — `if _db != null: execute_query(...)` / `elif not _in_transaction: _save_persistent_store()`. Stronger than the spec, which only said "fail loudly": fallback mode stays silent and transactions stay atomic on disk.
- The IP guard's path rule also blocks any `roms/` path component — broader than spec; keep it.
- `JSON_BAK_PATH` (`db.gd:10`) is unused on purpose — reserved for Item 2's one-time import.
- `relocation_manager.gd:63-72` "nearest-revealed-tile snapping" as a minimal-circle reveal plus placement — same guarantee as BFS.
- `os_location_source.dart:25` — `nativeVisits()` returns `null`; native visits are an optional hint.
- `game/tests/test_runner.py` is a static lint + capability guard, not the sync test gate.

## 12. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever** (standing constraint 1). Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache through `asset_db` only. The **phone companion never contains Nintendo assets or names**.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell` / `place_node` / `visit_log` (+ transient `bodyFix`). **When bag, party, PC box, or Pokémon tables are added, extend the isolation scan's forbidden tokens in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.**
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist.
- **Fast travel = the phone's position at sync time.** **Stranded:** the PC box is reachable only within `baseAccessMeters`. **Healing only at home. Blackout drops the bag, never Pokémon.** The map and Pokédex always persist.
- **Gen IV mechanics** (17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5) — `design_creatures_and_battles.md`.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot (PC) + Flutter (companion), SQLite (Decision 6 = A), LAN-only E2E sync. **Never hand-roll crypto.** No Steam, no monetization.
- Capture settings (accuracy `medium`, 25 m, 2 min) and `tuning.json` values are deliberate battery/balance decisions.

## 13. Where the contracts live
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
| Schemas + storage backends | `docs/design_game_state_and_models.md` |
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
            FIRST and PAUSE for human review. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written. Honor §12 and the standing constraints — above all, no
            Nintendo content in the repo and no tests touching the real save.
4 VALIDATE  This item's validation, then the full §1 battery. Report only what actually
            ran: "source-verified" and "executed" are different claims.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, or you'd need a ROM you don't have →
            STOP. File in ongoing_general_errors.md with options. Do not improvise.
6 RECORD    Move the item to Resolved with what-was-solved; update any design doc whose
            behavior changed — in this same commit.
7 COMMIT    One item = one Conventional Commit, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F21)** — all seven guard cases give the required exit codes, including rename and index-vs-disk; CI scans every pushed commit; a missing guard fails the battery.
- [x] **Item 1 (F22)** — the real save is byte-identical after the full suite; a failed save makes the recovery test fail, not skip.
- [ ] **Decision 7 answered**, then **Item 2** — reads come from SQL after restart; engine rejects duplicate `(peer_id, seq)`; injection and `O'Brien's Pub` tests pass; fallback retired; header true.
- [ ] **Item 3** — nonce wired and persisted; listener reads real frames; mDNS both sides; loopback GPX sync passes; Wireshark shows ciphertext only. **Closes Phase 1.**
- [ ] **D3 device soak run** (Decision 5 = A). **Closes Phase 0.**
- [ ] **Decision 9 answered and a ROM supplied**, then **Item 4** — verify markers resolved, `implementation_plan_rom_importer.md` written, **paused for review**.
- [ ] Full §1 battery green, including Godot headless tests **actually executing**.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is building the ROM importer from the *approved* plan, then Phase 3. Other legitimate triggers: (a) a new item in `ongoing_general_errors.md` with a filled `Your selection:`, (b) the §1 battery regressing on a fresh checkout, (c) the F7 or F23 trigger firing, or (d) the human assigning something. Otherwise report that the queue is complete and stop.
