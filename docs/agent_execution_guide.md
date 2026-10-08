# Agent Execution Guide — Active Build: Foundation Completion (real SQLite, TLS sync) + ROM Spike (verified 2026-10-08, pass 12)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The project pivoted on 2026-10-07** to a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been. Pokémon sprites and data come from ROMs **the player supplies**, read on their own machine (the PokeMMO model). All **649 Pokémon of Generations 1–5** are in scope: **Black/White** supplies all data, and **Platinum** optionally supplies Diamond/Pearl-style sprites (Decision 10). There is no Steam release. The capture, sync, and persistence foundation (Phases 0–1) carries over, and most of your queue is finishing it.

**What changed this pass (2026-10-08).** The human answered every decision that blocked the queue:
- **Decision 7 = B:** you vendor the `godot-sqlite` v4.4 extension, and CI proves it loads.
- **Decision 8 = A:** single-player.
- **Decision 9 = A**, amended by **Decision 12:** all 649 Pokémon, with Black/White as the single data source.
- **Decision 11:** sync uses Godot's built-in **TLS with a pinned certificate**. libsodium is gone.

**Items 0–3 are now unblocked.** Item 4 waits only on the human supplying a ROM dump.

**What is approved for build right now:** the queue in §2, in order. **What NOT to touch:**
- §10 — already delivered;
- §11 — accepted equivalents;
- §12 — intentional decisions.

§9 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string below is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work:** **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, no sprites, no text banks, no stat tables, not even in a test fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, dumped from cartridges they own, through `TENTH_SPRING_ROM_BW` (and optionally `TENTH_SPRING_ROM_PT`). Both point **outside** the repo. (`design_rom_asset_pipeline.md` §8)
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. It is the only defense before content becomes public.
3. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`/`-shm`/`.jsonbak` siblings;
   - the PC identity folder `user://sync_identity/`.

   Both hold things the design calls unrecoverable (location history; the phone's pairing).
4. **The only things you may download** are the exact files this guide names, by exact URL:
   - the Godot 4.3 engine (Item 0);
   - `godot-sqlite` v4.4 (Item 2);
   - Nayuki's QR Code generator source (Item 3).

   Each comes with an integrity check. Put downloads in a new, empty scratch directory outside the repo. Nothing Nintendo, ever.
5. **Every change leaves the §1 battery green** — that battery is the regression bar.
6. **Anything touching location capture, battery, or cross-device sync requires a real-device check** before it is called done.
7. **The golden invariants (§12) stay green, always.**
8. **Detailed behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
9. **One item = one Conventional Commit**, WHY in the body. Exceptions are stated per item: Item 2 is two commits pushed together; Item 3 is three. Record the resolution in `ongoing_general_errors.md` as part of the item.
10. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Game-side claims count as executed only when the `game_tests` CI workflow ran them (`gh run view <id> --log`).

---

## 1. Verified baseline (run this session, 2026-10-08, HEAD `51674cb`, pushed)

No code has changed since pass 11. This pass resolved decisions, updated the design contracts, and re-verified the facts this guide depends on: the `godot-sqlite` v4.4 release and API, the Godot 4.3 TLS/`Crypto`/`--import` APIs, and Godot's `SHA512-SUMS.txt` release asset.

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **17/17 passed** |
| Game static audit + IP guard + guard self-tests + isolation audit | `python3 game/tests/test_runner.py` (repo root) | **Pass** — guard exits 0; guard self-tests pass; isolation audit passes (static string checks only) |
| CI on GitHub | `gh run list --repo yelouis/tenth_spring` | **"Public-Repo IP Guard" green** on the last two pushes. It is the only workflow. |
| Game runtime tests | Godot (CI) | **PASS (M12)** — executed in headless Godot 4.3 in CI with exact `EXPECTED` match (`db_test`, `idempotent_sync_test`, `sync_ingest_isolation_test`, `real_save_untouched`), harness self-test exits 1 on failure |
| Game persistence (file fallback) | `db.gd` | Implemented, source-verified, and **executed** in CI |
| Test save isolation (F22) | `db.gd` + `.gd` tests | Implemented, source-verified, and **executed** in CI (`real_save_untouched` PASS) |
| D3 device gate | 8 h background soak, real phone | ⚠️ **NOT YET RUN** — waiting on the human (Decision 5 = A). |

⛔ **Read before trusting any status note or commit message.** Every pass since pass 6 has found claims the source didn't support. Three commits claimed SQLite with no extension present. One claimed a "socket transport listener" whose handler is `pass`. The harness that was supposed to prove all of it has never run. **A green suite proves nothing crashed; an unexecuted suite proves nothing at all.**

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F25 — make the game tests actually run (harness + CI Godot)** | **Everything else is validated through it.** Item 2's proof that the extension loads, Item 3's server tests, and F22's real-save check all need executed Godot. Needs nothing from the human. |
| 1 | **F24 + F28 — close the IP guard's remaining gaps** | Small, and the downside is a public takedown. It must land **before** any ROM reaches a working copy (Item 4). |
| 2 | **D7 + F4/F16/F19/F20/F23/F26 — vendor `godot-sqlite`, make the engine real, retire the fallback** | Needs Item 0: CI is the only place the binary can be proven to load. Must precede Item 3, which needs the `device_token_hash` column, bound parameters, and `last_error`. |
| 3 | **D11 + F14 + F27(a–c) — TLS transport and pairing; retire F12/F15** | Needs Item 2. Three commits: PC side → companion side → cross-language end-to-end CI. **Closes Phase 1** once the human runs the device gate. |
| 4 | **Phase 2 — ROM spike + importer implementation plan** | Needs Item 1, plus ⛔ **a Black/White dump from the human** (Platinum optional). Produces findings, a plan, and a sprite comparison for Decision 10 — **not** a production importer. |

**▶ HUMAN actions:**
- Supply a Black or White (USA) dump made from your own cartridge (unblocks Item 4); add Platinum if you want Decision 10's comparison image.
- Decision 10 — sprite style; best decided after Item 4's comparison.
- The D3 device soak — closes Phase 0; can run in parallel any time.
- The Item 3 real-device gate — closes Phase 1.

Deferred (trigger-gated, **do not start**): **F7** and **mDNS discovery** — see §8.

---

## 3. Item 0 — F25: make the game tests actually run

**What this means for the user:** today nobody can know whether saving, syncing, or the test-isolation protection actually work — the tests that would prove it have never run once. This item turns "should work" into "does work."

### The gap
- **The runner can't run the tests.** `game/tests/test_runner.py:116` runs each test as `godot --headless -s <path>`. Godot's docs say *"The script must inherit from `SceneTree` or `MainLoop`."* `db_test.gd`, `idempotent_sync_test.gd`, and `sync_ingest_isolation_test.gd` all `extends Node`, and nothing calls their `run_test()`.
- **No Godot anywhere.** Godot is not installed locally, and no CI workflow installs it. GitHub Actions already runs on every push, so CI is where to fix that.

### Implementation
1. **Test scene.** Create `game/tests/test_main.gd` (`extends Node`) and `game/tests/test_main.tscn` (a single root `Node` with that script). In `_ready()`:
   1. **Discover tests:** `DirAccess.get_files_at("res://tests/")`, keep names ending in `_test.gd`, and sort them.
   2. **For each test:**
      - `var s = load("res://tests/" + f)`. If `s == null` or `not s.can_instantiate()`, print `FAIL <basename>` and continue.
      - Otherwise `var t = s.new()`, `add_child(t)`, `var ok = t.run_test()`.
      - Print exactly `PASS <basename>` if `ok == true`, else `FAIL <basename>`. `<basename>` is the file name without `.gd` — e.g. `PASS db_test`. A runtime error aborts the call, returns non-`true`, and counts as FAIL.
      - `t.queue_free()`.
   3. **Self-test hook:** if `OS.get_environment("TENTH_SPRING_HARNESS_SELFTEST") == "1"`, also run `res://tests/harness_selftest.gd`, whose `run_test()` returns `false`. Its name doesn't end in `_test.gd`, so discovery never picks it up.
   4. **Finish** with `get_tree().quit(0 if every test passed else 1)`.

   Running a normal scene loads the autoloads (`DB`, `Config`, `SyncServer`) as the game does.
2. **Real-save check (F22's falsifying test — non-destructive).** Do this in `test_main.gd`, **before** any test runs:
   - For each of `user://tenth_spring.db` and `user://tenth_spring.db.tmp`, record whether it exists, and its `FileAccess.get_sha256()` if it does.
   - After all tests, assert every file is in exactly the same state: same hash, still absent, or still present.
   - Print `PASS real_save_untouched` or `FAIL real_save_untouched`.
   - **Never write to the real save, not even a sentinel** — on a developer's machine that file is their actual world.
3. **Runner.** Replace the per-file `-s` loop in `test_runner.py` with one call:

   `godot --headless --path game res://tests/test_main.tscn`

   Use a **300 s** timeout. Keep the expected list in **one** constant:

   `EXPECTED = ["db_test", "idempotent_sync_test", "sync_ingest_isolation_test", "real_save_untouched"]`

   The run is green **only if all** hold:
   - exit code 0;
   - the set of `PASS` names **equals** `EXPECTED` exactly — a missing name fails, and so does an unexpected one, so a new test file must be added to `EXPECTED` deliberately;
   - no `FAIL` line;
   - no line containing `SCRIPT ERROR`.

   A crash before tests run, or an empty run, is a failure.
4. **Harness self-test.** The runner also invokes the scene with `TENTH_SPRING_HARNESS_SELFTEST=1`, and requires exit code **1** and a `FAIL harness_selftest` line. This proves the harness can fail.
5. **Local behavior.** If no `godot`/`godot4` binary is on `PATH`, the runner prints exactly `game runtime tests SKIPPED — Godot not installed; CI runs them` and continues with the static portion. **This is the only permitted skip, and it must say so in those words.**
6. **CI.** Add `.github/workflows/game_tests.yml`, triggered on `push` and `pull_request`, `ubuntu-latest`:
   ```
   curl -fsSLO https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
   curl -fsSLO https://github.com/godotengine/godot/releases/download/4.3-stable/SHA512-SUMS.txt
   grep " Godot_v4.3-stable_linux.x86_64.zip$" SHA512-SUMS.txt | sha512sum -c -
   unzip -q Godot_v4.3-stable_linux.x86_64.zip
   sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
   godot --headless --path game --import
   python3 game/tests/test_runner.py
   ```
   - `--import` is verified for 4.3: it starts the editor, imports resources, and quits.
   - The import pass is required: it generates `game/.godot/` (gitignored), including the extension list Item 2 depends on.
   - Godot is MIT-licensed and these are the official release files. This has nothing to do with ROMs.
7. **Project file hygiene (same commit).** `game/project.godot`'s `config/description` still describes the zombie game; replace it with the README's first sentence. `run/main_scene` points at `res://scenes/main.tscn`, which doesn't exist. Running a specific scene doesn't need it, so **leave it unless the import pass errors** — Item 2 creates that scene.

### Validation
- **Falsifying — the harness can fail:** with `TENTH_SPRING_HARNESS_SELFTEST=1`, the scene exits 1 and prints `FAIL harness_selftest`.
- **First execution ever:** the `game_tests` workflow is green on GitHub, and its log shows exactly the four `PASS` lines in `EXPECTED`. Confirm with `gh run view <id> --log`; never report success from local reasoning.
- **Catches a real regression:** on a scratch branch, make `execute_query()` return `true` on a null handle (re-introducing F13). The workflow must go red on `db_test`. Delete the branch afterwards — never merge it.
- **Catches a stray test:** on the same scratch branch, add an empty `zz_test.gd` whose `run_test()` returns `true`. The runner must fail it as an unexpected `PASS`.

### Blast radius (same commit)
- **New:** `game/tests/test_main.gd`, `game/tests/test_main.tscn`, `game/tests/harness_selftest.gd`, `.github/workflows/game_tests.yml`.
- **Changed:** `game/tests/test_runner.py` (the Godot section) and `game/project.godot` (description).
- **Kept:** `game/tests/test_f22_save_isolation.py` stays as a static pre-check; it is no longer proof.
- **Docs:** F25 and F22 status. The harness contract is in `implementation_plan_foundation.md`'s validation summary.

---

## 4. Item 1 — F24 + F28: close the IP guard's remaining gaps

**What this means for the user:** a ROM that arrives through a merge from a clone without the hook — or simply a European cartridge dump — would currently pass every check and become public. A small fix with an irreversible downside.

### The gap (F24 reproduced in an isolated scratch repo)
- **(a) Merge commits are invisible to range mode.** `tools/check_no_nintendo_assets.py:126` runs `git diff-tree --root --no-commit-id -r --name-only --diff-filter=d <sha>`. Without `-m`, merges report nothing, so a file added during conflict resolution exits 0 under `--range M^1..M`.
- **(b) No tip-tree scan in CI.** `.github/workflows/ip_guard.yml` runs only range mode, so (a)'s file passes CI even though it sits in the pushed tree.
- **(c) Hook activation is unenforced.** The hook protects only clones that ran `git config core.hooksPath .githooks`, and nothing checks it.
- **(d) Silent skip.** The range loop at `:129` does `except subprocess.CalledProcessError: continue`.
- **(e) Force-push false red.** When `github.event.before` isn't fetchable, `git rev-list` errors and CI fails with no real violation.
- **F28 — USA-only fingerprints.** `:20-21` matches exact codes `CPUE`, `ADAE`, `APAE`, `IPKE`, `IPGE`. A European (`CPUP`) or Japanese (`CPUJ`) Platinum dump passes, and Black/White (`IRBO`, `IRAO`) — now a required ROM — isn't listed at all.

### Implementation
1. Add `-m` to the range-mode `diff-tree` call, so merges diff against each parent; de-duplicate paths per commit.
2. Replace `continue` in the range loop with an error message naming the commit, then `sys.exit(1)`.
3. **F28.** Replace `FORBIDDEN_GAME_CODES` with `FORBIDDEN_GAME_CODE_PREFIXES = {b"ADA", b"APA", b"CPU", b"IPK", b"IPG", b"IRB", b"IRA", b"IRE", b"IRD"}`. The check becomes: file ≥ `0x10` bytes and `header[0x0C:0x0F]` in that set. Update the comment at `:78` to list the titles. (`design_rom_asset_pipeline.md` §8.3 has the table.)
4. **Workflow.**
   - After the range scan, add a second step: `python3 -I tools/check_no_nintendo_assets.py` (default mode: the full `HEAD` tree).
   - Before the range scan: if `git cat-file -e "$BEFORE^{commit}"` fails (or `BEFORE` is all zeros), scan `--range HEAD` (full history) instead.
5. **Runner hook check.** In `test_runner.py`, unless `os.environ.get("CI") == "true"`, fail when `git config core.hooksPath` isn't `.githooks`, and print the exact fix: `git config core.hooksPath .githooks`.
6. **New guard self-tests** in `tools/test_check_no_nintendo_assets.py`, each in a throwaway repo:
   - a merge that introduces a `CPUE`-headed file → `--range` exits 1;
   - an unknown SHA in the range → exits 1;
   - `CPUP`-, `CPUJ`-, `IRBO`-, and `IRAO`-headed blobs named `x.bin` → each exits 1;
   - a 16-byte file with `CPX` at `0x0C` → exits 0, proving the check is a prefix, not "anything".

### Validation
- **Falsifying:** a range containing only a merge that introduces a `CPUE`-headed file exits **1** (today: 0).
- **Falsifying:** a staged `x.bin` with `IRBO` at `0x0C` exits **1** (today: 0).
- **Falsifying:** with `core.hooksPath` unset and `CI` unset, `test_runner.py` exits 1 and prints the fix command (today: passes).
- The workflow log shows both a range scan and a full-tree scan, all guard self-tests pass, and the existing adversarial cases still behave.

### Blast radius (same commit)
- `tools/check_no_nintendo_assets.py` (`:20-21`, `:78`, `:126-131`) and `tools/test_check_no_nintendo_assets.py`.
- `.github/workflows/ip_guard.yml` and `game/tests/test_runner.py`.
- F24 and F28 status.

---

## 5. Item 2 — Vendor `godot-sqlite`, make the engine real, retire the fallback

Covers Decision 7 = B and findings F4, F16, F19, F20, F23, and F26.

**What this means for the user:** whether their world — and soon their Pokémon — survives a crash intact, and whether the map still loads quickly once they've scouted a whole city. Done wrong, the **first launch on SQLite would make their map look wiped** (F26).

**Two commits, pushed together** — never push commit A to `main` alone. The moment the extension exists, today's `db.gd` switches into its broken SQL branch (F26).

### The gap
- **No extension.** `game/addons/` doesn't exist, so `_db` is always null and the interim JSON fallback is what persists today (`design_game_state_and_models.md` §0).
- **F19 — SQL injection.** `db.gd` string-formats values into SQL at `:259`, `:279`, `:299`, `:326`, and `:339`. The values come from phone sync payloads and OpenStreetMap, so a place named `O'Brien's Pub` breaks the statement.
- **F26 — the SQL branch has different semantics from the Dictionary branch:**
  - `INSERT OR REPLACE` downgrades `reveal_state` and resets `first_revealed_at` (`:259`);
  - it replaces `visit_count` instead of adding to it (`:279`);
  - it lets `last_applied_seq` go **backwards** (`:326`);
  - `sync_peer.peer_pubkey BLOB NOT NULL` (`:70`) makes every sync-peer insert fail;
  - `%f` truncates coordinates;
  - every getter reads Dictionaries that SQL mode never loads.
- **F23** — zombie-era columns in the v1 DDL. **F16** — the header comment must be true. **F20** — `verify_sync_isolation()` (`:344`) is `return true`.
- **Boot writes.** `DB._ready()` calls `init_db()` (`:43-44`). With SQLite, that would **create** `user://tenth_spring.db` during every test run and fail `real_save_untouched`.

### Implementation — commit A: `chore(vendor): add godot-sqlite v4.4 GDExtension (Decision 7)`
1. **Download twice, by two routes, into a new empty scratch directory outside the repo:**
   - `gh release download v4.4 --repo 2shady4u/godot-sqlite --pattern bin.zip`
   - `curl -fL -o bin2.zip https://github.com/2shady4u/godot-sqlite/releases/download/v4.4/bin.zip`

   Both must be **65,986,325 bytes** (the size GitHub reported on 2026-10-08) and have identical SHA-256 hashes. GitHub publishes no digest for this 2024 release, so this is trust-on-first-use: the two routes and the size are the check. **Any mismatch → STOP and report.**
2. **Unzip into its own empty directory.** Treat the contents as untrusted data: run nothing from inside it.
3. **Copy into `game/addons/godot-sqlite/` only:**
   - `gdsqlite.gdextension`, plus `plugin.cfg` and `godot-sqlite.gd` if present;
   - from `bin/`, exactly the **six desktop entries** the `.gdextension` names:
     - `libgdsqlite.macos.template_debug.framework`, `libgdsqlite.macos.template_release.framework`
     - `libgdsqlite.windows.template_debug.x86_64.dll`, `libgdsqlite.windows.template_release.x86_64.dll`
     - `libgdsqlite.linux.template_debug.x86_64.so`, `libgdsqlite.linux.template_release.x86_64.so`
   - **Do not** copy the Android, iOS, or web binaries.
   - Add the licence from the source repo at the tag:

     `gh api "repos/2shady4u/godot-sqlite/contents/LICENSE.md?ref=v4.4" --jq .content | base64 -d > game/addons/godot-sqlite/LICENSE.md` (MIT).
4. **Keep `gdsqlite.gdextension` unmodified** (`compatibility_minimum = "4.3"`, `entry_symbol = "sqlite_library_init"`). If, and only if, the import pass errors because the mobile/web entries point at missing files, delete only those lines, and record the exact edit in `VENDORED.md`.
5. **Size gate:** no single committed file may exceed **50 MB** (GitHub warns at 50 MB and rejects at 100 MB). Otherwise STOP and file it.
6. **Write the vendoring record:**
   - `game/addons/godot-sqlite/VENDORED.md`: source URL, tag `v4.4`, date, the `bin.zip` SHA-256, the platforms kept and dropped, the licence, and "Godot v4.3-stable / SQLite 3.46.1 per the release notes".
   - `game/addons/godot-sqlite/VENDORED.sha256`: `shasum -a 256` lines for **every** committed file under `game/addons/godot-sqlite/` (recursively, framework contents included), except `VENDORED.sha256` itself.
7. **`.gitattributes`:** add `game/addons/godot-sqlite/bin/** binary`.
8. **`test_runner.py`:** recompute every hash in `VENDORED.sha256`. Fail on any mismatch, any listed file missing, or any file under `game/addons/godot-sqlite/bin/` that isn't listed.
9. **Run the IP guard** over the new files — it must exit 0.
10. **Scratch-branch proof before writing any SQL:** push commit A alone to a scratch branch and read the `game_tests` log.
    - It **must contain** `storage: SQLite extension`. Tests may fail on that branch; only the boot line matters here.
    - If the line is absent, the binary didn't load. STOP and report what the log says. Do not write engine code against a class that can't instantiate.
    - Delete the scratch branch.

### Implementation — commit B: `feat(db): real SQLite engine with bound parameters; retire file fallback (F4 F16 F19 F20 F23 F26)`
1. **Boot moves out of the autoloads.**
   - `DB._ready()` and `SyncServer._ready()` do **nothing**.
   - Create `game/scenes/main.tscn` (root `Node2D`) with `game/scenes/main.gd`, whose `_ready()` calls `DB.init_db()` then `SyncServer.start_server()`. This also gives `run/main_scene` a real file.
   - Tests call `DB.configure_paths(...)` then `DB.init_db()` themselves, so a test run never opens the real save.
2. **v1 DDL — corrected in place, once (F23, Decision 11).** This is safe only because no SQLite file has ever been created by any build. Replace the DDL in `db.gd` with exactly `implementation_plan_foundation.md` §B2's **nine** tables:
   - `meta`, `world_clock`, `map_cell`, `place_node`, `visit_log`;
   - `sync_peer`, with `device_token_hash BLOB` (nullable; no `peer_pubkey`);
   - `player_profile`, with `trainer_name` and **no** `hp`/`stamina`/`carry_capacity`;
   - `base_state`, `osm_cache`.

   **No `inventory_item`.** Seed the single-row tables with `INSERT OR IGNORE`:
   - `world_clock` → `(1, 0, 0)`;
   - `player_profile` → `(id 1, trainer_name NULL, sprite_index 0, pos 0,0)`;
   - `base_state` → `(1, 0, 0)`.
3. **`init_db()` sequence:**
   1. **Legacy check (step 9)** — before opening anything.
   2. If `not ClassDB.can_instantiate("SQLite")`:
      - print `storage: UNAVAILABLE — SQLite extension missing`;
      - `push_error` the same text;
      - leave `_db = null` and return. Nothing writes.
   3. Open: `_db = ClassDB.instantiate("SQLite")`; `_db.path = DB_PATH`; `_db.foreign_keys = true`; `_db.verbosity_level = 1`.
      - If `_db.open_db()` is false: print `storage: UNAVAILABLE — cannot open <path>: <error_message>`, set `_db = null`, and return.
   4. Run `PRAGMA journal_mode=WAL;` and `PRAGMA synchronous=FULL;`.
   5. Print `storage: SQLite extension`.
   6. Run migrations (step 8).
   7. Run the legacy import (step 9) if one is pending.
4. **Two private helpers carry every statement.** No value is ever formatted into SQL text — **not one `%` or `+` building SQL in this file.**
   - **`_q(sql: String, params: Array = []) -> bool`:**
     - `_db == null` → `push_error` and return `false`;
     - otherwise `var ok = _db.query_with_bindings(sql, params)`;
     - if not ok, set `last_error = _db.error_message` and `push_error`.
   - **`_rows(sql, params) -> Array`:** `_q(...)`, then return `_db.query_result` (by value) or `[]`.
   - **Public `execute_query(sql) -> bool`** stays, as `_q(sql)`. **Public `last_error: String`** is cleared at the start of each public write.
5. **Transactions:** `begin_transaction()` → `_q("BEGIN IMMEDIATE;")`; `commit_transaction()` → `_q("COMMIT;")`; `rollback_transaction()` → `_q("ROLLBACK;")`. Track `_in_transaction`. A nested `begin` pushes an error and returns `false`.
6. **Accessors — keep every public signature.** These statements preserve the Dictionary semantics exactly (F26):
   ```
   get_map_cell      SELECT cell_x, cell_y, reveal_state, first_revealed_at, cell_seed FROM map_cell WHERE cell_x = ? AND cell_y = ?
   upsert_map_cell   INSERT INTO map_cell (cell_x, cell_y, reveal_state, first_revealed_at, cell_seed) VALUES (?, ?, ?, ?, ?)
                       ON CONFLICT(cell_x, cell_y) DO UPDATE SET reveal_state = MAX(map_cell.reveal_state, excluded.reveal_state)
   get_place_node    SELECT * FROM place_node WHERE id = ?
   upsert_place_node INSERT INTO place_node (id, name, category, cell_x, cell_y, reveal_state, visit_count, last_real_visit_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                       ON CONFLICT(id) DO UPDATE SET visit_count = place_node.visit_count + excluded.visit_count,
                         last_real_visit_at = excluded.last_real_visit_at,
                         reveal_state = MAX(place_node.reveal_state, excluded.reveal_state)
                     (defaults as today: category 1, reveal_state 1, visit_count 1, last_real_visit_at = now)
   is_visit_logged   SELECT 1 FROM visit_log WHERE peer_id = ? AND seq = ?
   insert_visit_log  if is_visit_logged → return false (duplicate; last_error stays "")
                     else INSERT INTO visit_log (seq, peer_id, place_id, lat, lon, started_at, dwell_seconds, kind)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?) → true on success; false with last_error set on failure
   get_sync_peer     SELECT * FROM sync_peer WHERE peer_id = ?
   update_sync_peer  INSERT INTO sync_peer (peer_id, last_applied_seq, last_body_lat, last_body_lon, last_body_ts)
                       VALUES (?, ?, ?, ?, ?)
                       ON CONFLICT(peer_id) DO UPDATE SET last_applied_seq = MAX(sync_peer.last_applied_seq, excluded.last_applied_seq),
                         last_body_lat = excluded.last_body_lat, last_body_lon = excluded.last_body_lon,
                         last_body_ts = excluded.last_body_ts           -- never touches device_token_hash
   get_base_state    SELECT * FROM base_state WHERE id = 1
   set_player_tile   UPDATE player_profile SET pos_tile_x = ?, pos_tile_y = ? WHERE id = 1
   get_schema_version  int(SELECT value FROM meta WHERE key = 'schema_version'), or 0 if absent
   ```
   Add **`close()`** (`_db.close_db()`, `_db = null`) so tests can simulate a restart.
7. **`sync_server.gd` `process_batch`.** After each `DB.insert_visit_log` / `upsert_*` / `update_sync_peer` call, if `DB.last_error != ""`, call `DB.rollback_transaction()` and return `{"status": "error", "message": "storage error"}`. A duplicate returns `false` with an empty `last_error`, and is skipped exactly as today.
8. **Migration runner** — `_run_migrations(migrations: Array = MIGRATIONS)`, where `const MIGRATIONS: Array = []` holds entries `{version: int, statements: Array[String]}`.
   - **Fresh DB** (no `meta` row): inside one transaction, run the v1 DDL and seeds, then `INSERT INTO meta VALUES ('schema_version', '1')`.
   - **Upgrades:** for each migration with `version > current`, in ascending order: `BEGIN IMMEDIATE`; run each statement; `UPDATE meta SET value = ? WHERE key = 'schema_version'`; `COMMIT`.
   - **Any failure:** `ROLLBACK`, print `storage: UNAVAILABLE — migration <n> failed: <error>`, and close.
   - Production passes the constant; tests pass their own list. **There is no test flag in production code.**
9. **One-time legacy import** (the fallback saved JSON at the **same path** SQLite wants):
   - **Detect.** Before opening, if `DB_PATH` exists and its first 16 bytes are not `SQLite format 3\0`:
     - rename it to `JSON_BAK_PATH` — if that exists, use the first free `<JSON_BAK_PATH>.1`, `.2`, …;
     - rename any `DB_TMP_PATH` to `<that bak path>.tmp`;
     - mark the import pending.

     Derive test-mode bak paths from the configured `DB_PATH` (`DB_PATH + ".jsonbak"`), so tests never touch the real one.
   - **Import.** After migrations, if a bak exists **and** `meta` has no `legacy_import` row:
     1. Parse the bak; if it is empty or unparseable, parse `<bak>.tmp` — the same recovery order as today's `_load_persistent_store` (`db.gd:148-176`).
     2. In **one** transaction, insert every row with the step 6 statements. Coerce every number with `int()`/`float()` — JSON parses numbers as floats.
     3. Map fields: `survivor_name` → `trainer_name`. Drop `hp`/`stamina`/`carry_capacity` and `sync_peer.peer_pubkey`. `inventory_item` must be empty — log its count, and drop it.
     4. Write `meta('legacy_import', <bak file name>)`, then commit.
     5. **Verify** row counts equal the JSON's per table; otherwise roll back and print `storage: UNAVAILABLE — legacy import mismatch`.
   - **Never delete or modify a bak file.**
10. **Delete:**
    - all `_*_table` Dictionaries;
    - `_save_persistent_store`, `_load_persistent_store`, `_reset_default_tables`, `_apply_loaded_state`;
    - the snapshot functions;
    - `verify_sync_isolation()` (F20).

    Keep `configure_paths()` (the tmp path now names the legacy `.tmp`) and `assert_test_safe()`.
11. **Rewrite the `db.gd` header** so every clause is true (F16): SQLite via the vendored extension; bound parameters only; WAL; one-time legacy import; no fallback.
12. **Fixture.** Before deleting the fallback, hand-write `game/tests/fixtures/legacy_fallback_world.json` in **exactly** `_save_persistent_store()`'s shape (`db.gd:119-146`).
    - **Top-level keys:** `meta`, `world_clock`, `map_cell` (keyed `"x,y"`), `place_node` (keyed by id), `visit_log` (keyed `"peer:seq"`), `sync_peer` (keyed by peer id, with `peer_pubkey`), `player_profile` (with `survivor_name`, `hp`, `stamina`, `carry_capacity`), `base_state`, `inventory_item` (`[]`), `osm_cache`.
    - **Content:**
      - 3 map cells, one with `reveal_state` 2;
      - 2 places, one named `O'Brien's Pub`;
      - visit_log seq 1–5 for `test_phone_001`, with `last_applied_seq` 5;
      - `survivor_name` `"Tester"`;
      - synthetic coordinates already used in tests (e.g. `37.776, -122.420`).
13. **Tests.** Every test cleans `DB_PATH` plus `-wal`, `-shm`, `.jsonbak*`, and `.tmp` under `user://test/` before and after, then restores default paths.
    - **`db_test.gd` (rewrite).** Assert:
      - the boot line;
      - `ClassDB.class_exists("SQLite")`;
      - `get_schema_version() == 1`;
      - `sqlite_master` lists exactly the nine tables;
      - write a cell → `DB.close()` → `DB.init_db()` → `get_map_cell` returns it. **Also** open a second, independent `SQLite` instance on the test path and `SELECT` the row — this proves it is on disk, not in memory.
      - The engine rejects a duplicate: two raw `DB._db.query_with_bindings("INSERT INTO visit_log …", [...])` calls — the second returns `false`, and `error_message` contains `UNIQUE`. Tests may touch `DB._db`; production code may not.
      - Upsert semantics: reveal 2 then 1 → stays 2; `first_revealed_at` unchanged on the second upsert; `visit_count` 1 → 2; `last_applied_seq` 5 then 3 → stays 5.
      - Injection: `kind = "visit'); DROP TABLE map_cell;--"` is stored literally and `map_cell` still exists; `name = "O'Brien's Pub"` round-trips exactly; lat `37.123456789` round-trips within `1e-9`.
      - Rollback: begin → insert → rollback → `close()`/`init_db()` → the row is absent.
      - `execute_query` after `close()` returns `false`.
    - **`db_migration_test.gd` (new):**
      - `_run_migrations([{version: 2, statements: ["ALTER TABLE map_cell ADD COLUMN t INTEGER;"]}])` → version 2, and `visit_log` rows unchanged;
      - running it again is a no-op;
      - a failing statement leaves the version at 2.
    - **`db_legacy_import_test.gd` (new):**
      - copy the fixture to the test `DB_PATH` → `init_db()` → per-table counts match the fixture;
      - `trainer_name == "Tester"`;
      - the bak is byte-identical to the fixture (SHA-256);
      - `init_db()` again → no duplicate rows, and `legacy_import` is still one row.
    - **`idempotent_sync_test.gd`** — keep its assertions; they now run on SQLite. Add: after the batch, `DB.close()`/`DB.init_db()`, then replay → `appliedCount == 0`.
    - **`test_runner.py` `EXPECTED`** gains `db_migration_test` and `db_legacy_import_test`.
    - **Static rule (the runner):** fail if `game/autoloads/db.gd` contains a line holding both a SQL keyword (`INSERT`, `UPDATE`, `DELETE`, `SELECT`, `CREATE`) and `%` or `" +`. This keeps F19 closed.

### Validation (executed in the `game_tests` workflow)
- **Falsifying — reads come from disk:** the independent-connection `SELECT` finds the row after a restart. Today's code would fail it.
- **Falsifying — F26:** reveal 2-then-1 stays 2; `last_applied_seq` never decreases; `sync_peer` inserts succeed.
- **Proves F19 closed:** the injection and `O'Brien's Pub` cases pass, and the static rule passes.
- **Proves the legacy import:** counts match, the bak is preserved byte-for-byte, and the import is idempotent.
- **Proves boot isolation:** `real_save_untouched` passes on a fresh CI runner, where the save did not exist before the run.
- **Integrity:** the `VENDORED.sha256` check passes, and the CI log shows `storage: SQLite extension`.
- **Manual (local, if you have Godot):** run the game twice; the second boot reads the first boot's map.

### Blast radius (same push)
- **Vendored:** `game/addons/godot-sqlite/**` and `.gitattributes`.
- **Code:** `game/autoloads/db.gd`, `game/autoloads/sync_server.gd` (`_ready`, `process_batch`), and new `game/scenes/main.tscn` + `main.gd`.
- **Tests:** `game/tests/db_test.gd`, `idempotent_sync_test.gd`, two new tests, the fixture, `test_runner.py`, and `test_f22_save_isolation.py` (if its strings change).
- **Docs:** `design_game_state_and_models.md` §0 is already written for this end state — change "Until agent-guide Item 2 lands" to past tense.
- **Tracking:** resolve F4, F10, F16, F19, F20, F23, F26, D6, and D7 in `ongoing_general_errors.md`.

---

## 6. Item 3 — TLS transport and pairing: the phone and PC actually talk

Covers Decision 11 and findings F14, F27(a–c), F12, and F15.

**What this means for the user:** the missing half of the product. Until this works, walking around can't reach the game at all.

**Three commits, each green on its own:** 3a PC side → 3b companion side → 3c cross-language end-to-end CI. Contracts: `design_companion_and_sync.md` §2–3 and `implementation_plan_foundation.md` §B3–B4, where the message shapes, frame limits, and timeouts are defined.

### The gap
- **F14:** `sync_server.gd:39-41` — `_handle_incoming_peer(_stream)` is `pass`; connections are accepted and dropped.
- **Dead, superseded crypto (F12/F15):** `companion/lib/sync/transport.dart` has an unwired `encryptChunk`/`decryptChunk` and `generateMonotonicNonce`, with no callers. Its `SyncClient` (`:90-112`) is uncalled and **plaintext**. `pairing.dart` derives X25519/HKDF keys that Decision 11 retires.
- **F27(a–c):**
  - `multicast_dns` fails on real iPhones;
  - no `NSLocalNetworkUsageDescription` in `Info.plist`;
  - no `android.permission.INTERNET` in the main `AndroidManifest.xml`, so release builds can't connect.
- **No QR on the PC.** Godot has no QR generator.

### 3a — PC side: `feat(sync): TLS listener, pairing codes, frame codec, QR (F14, Decision 11)`
1. **`game/sync/pc_identity.gd`** (`class_name PcIdentity`, `RefCounted`):
   - **Path:** `configure_dir(path)` (default `user://sync_identity/`; tests use `user://test/sync_identity/`).
   - **`load_or_create() -> bool`:** creates the key, certificate, and `pcId` exactly per §B3 steps 1–4 if missing, otherwise loads them.
   - **Accessors:** `key`, `cert`, `pc_id`, `fingerprint_hex()`.
   - **`static func fingerprint_of_pem(pem: String) -> String`** (per §B3 step 5).
2. **`game/sync/pairing.gd`** (`class_name PairingCodes`):
   - **`new_code(now_unix: int) -> String`:** 16 random bytes, hex, replacing any active code.
   - **`consume(code: String, now_unix: int) -> bool`:** `Crypto.constant_time_compare` against the active code; false if older than **600 s**; clears the code on success.
   - **`static func filter_addrs(all: PackedStringArray) -> Array`:** private IPv4 only, no loopback or `169.254/16`, at most 4, in input order.
   - **`qr_payload(identity, addrs, port, code) -> String`:** compact JSON with keys in the order `v, pcId, fp, addrs, port, pair`.
3. **`game/sync/frame_codec.gd`:**
   - **`static func encode(obj: Dictionary) -> PackedByteArray`:** 4-byte big-endian length, then UTF-8 JSON.
   - **`class FrameReader`** with `feed(bytes)`, `next_frame()` (returns `Dictionary` or `null` when incomplete), and `error: String`. **Errors:**
     - `N == 0` or `N > 1_048_576`;
     - invalid JSON;
     - a non-object;
     - a missing `type`.
4. **`game/sync/qr_code.gd`:** a GDScript port of Nayuki's QR Code generator (MIT).
   - Source: `https://github.com/nayuki/QR-Code-generator`; record the commit SHA you ported from in the file header, with the MIT notice.
   - Byte mode, ECC level **M**, automatic version, mask chosen by the reference penalty rules.
   - `encode_text(s) -> Array[Array[bool]]`, and a helper to render the matrix to an `ImageTexture` at integer scale with a 4-module quiet zone.
   - **Fixtures:** generate the expected matrices **once**, with Nayuki's reference **Python** implementation at the same commit (run from a scratch directory, never vendored), for three fixed strings — `"HELLO"`, a 120-character string, and a sample v2 payload. Commit them as `game/tests/fixtures/qr_*.txt` (rows of `0`/`1`).
5. **`sync_server.gd` — replace the scaffold with one session state machine.** Polled in `_process`; no threads.
   - **Accept.** If no session is active, wrap the connection: `StreamPeerTLS.new().accept_stream(tcp, TLSOptions.server(identity.key, identity.cert))`. If a session is already active, `take_connection()` and immediately `disconnect_from_host()` it.
   - **Handshake.** Poll until `STATUS_CONNECTED`. More than **10 s** or `STATUS_ERROR` → close.
   - **Read.** Read whatever `get_available_bytes()` reports into the `FrameReader`, then handle every complete frame. No complete frame for **30 s** → close.
   - **`PAIR`** (any state):
     - `PairingCodes.consume(pair)` must succeed, else `ERROR bad_pair_code` and close.
     - On success, `DB.set_peer_token_hash(phoneId, sha256(base64_decode(deviceToken)))` and `DB.clear_other_peer_tokens(phoneId)` (two new bound-parameter accessors), then reply `PAIR_OK`.
   - **`HELLO`:**
     - Load `device_token_hash` for `peerId`. If it is null or doesn't `constant_time_compare`-equal SHA-256 of the presented token → `ERROR unpaired`, close.
     - A schema mismatch (existing `handle_hello`) → `ERROR schema_mismatch`, close.
     - Otherwise remember `peerId` **as the session's identity** and reply `HELLO_OK {pcId, lastAppliedSeq}`.
   - **`BATCH`** — only after `HELLO_OK`, else `ERROR protocol` and close.
     - **Validate before applying anything:**
       - ≤ **500** rows;
       - each `seq` an integer ≥ 1;
       - `kind` in `{"visit", "corridor"}`;
       - lat in [-90, 90] and lon in [-180, 180];
       - **every coordinate already at ≤ 3 decimals** — `abs(v * 1000 - round(v * 1000)) < 1e-6`. This is golden invariant 2, enforced at the PC boundary.
     - Any violation → `ERROR protocol`, close, and **nothing applied**.
     - Then `process_batch(<session peerId>, frame)`. **The peer id comes from the authenticated session, never from the payload.** Reply with its result plus `"type": "ACK"`.
   - Any other `type` → `ERROR protocol`, close.
   - `start_server(port = 7350)` loads the identity first; if that fails, print the error and don't listen. It listens on `"*"`.
6. **Tests (Godot; add each to `EXPECTED`):**
   - **`frame_codec_test`:** round trip; a frame split across 3 feeds; 2 frames in one feed; `N = 0` → error; `N = 1_048_577` → error.
   - **`pairing_codes_test`:** valid code → true once, then false; wrong code → false; code at `now + 601` → false; the `filter_addrs` table cases.
   - **`pc_identity_test`:**
     - The fingerprint of `game/tests/fixtures/test_cert.pem` equals the hex you computed with `openssl x509 -in test_cert.pem -outform der | shasum -a 256`. Commit the certificate **only** — generate it with `openssl req -x509 -newkey rsa:2048 -nodes -keyout <scratch>/k.pem -out test_cert.pem -days 7300 -subj "/CN=tenthspring-test"`, and leave the key in scratch.
     - `load_or_create` in the test dir creates the files, and a second call loads the same fingerprint.
   - **`qr_code_test`:** the three matrices equal the fixtures bit for bit.
   - **`sync_session_test`** — drive the dispatcher with frames directly; no sockets:
     - `BATCH` before `HELLO` → `ERROR protocol`;
     - wrong token → `ERROR unpaired`;
     - a coordinate `37.7761` → `ERROR protocol`, with `visit_log` unchanged;
     - a `BATCH` frame carrying a top-level `"peerId": "other"` is still stored under the session's peer — the payload's field is ignored.
   - **Extend `real_save_untouched`** to also hash `user://sync_identity/pc.key`, `pc.crt`, and `pc_id.txt`.
7. **PC pairing screen** — minimal, original UI in `game/scenes/pairing.tscn`, opened from the main scene:
   - title `Recruit your scout`;
   - the QR, re-generated with a fresh code each time the screen opens;
   - a countdown `Code expires in m:ss`;
   - on `PAIR_OK`, the text `Scout recruited.`

### 3b — companion side: `feat(companion): pinned-TLS scout reports; remove superseded crypto (Decision 11, F12, F15, F27)`
1. **Delete:**
   - from `transport.dart`: `encryptChunk`, `decryptChunk`, `generateMonotonicNonce`, and `SyncClient`;
   - from `pairing.dart`: `deriveSessionKey`, `storeSessionKey`, `getSessionKey`;
   - from `pubspec.yaml`: the `multicast_dns` dependency.

   Keep `buildHelloPayload`, `buildBatchPayload`, and `handleAckResponse`, updating HELLO to carry `deviceToken`.
2. **`companion/lib/sync/pairing.dart`:**
   - **`QrPayloadV2.tryParse(String)`** rejects anything not matching §B3 exactly:
     - `v == 2`;
     - `pcId` is 32 hex chars and `fp` is 64 lowercase hex chars;
     - `addrs` has 1–4 dotted-quad IPv4 entries;
     - `port` is 1–65535 and `pair` is 32 hex chars.
   - **`PairingStore`** over `flutter_secure_storage` holds `pairing.pcId`, `pairing.fp`, `pairing.addrs` (JSON), `pairing.port`, `pairing.phoneId`, `pairing.deviceToken` (base64), and `pairing.lastGoodAddr`. Nothing goes in Drift.
3. **`companion/lib/sync/frame_codec.dart`:** the same codec and limits as 3a.
4. **`companion/lib/sync/scout_link.dart`:**
   - **`connectPinned(host, port, fpHex)`** — `SecureSocket.connect(host, port, context: SecurityContext(withTrustedRoots: false), onBadCertificate: (c) => _hex(sha256(c.der)) == fpHex, timeout: Duration(seconds: 3))`.
     - Afterwards, re-check `socket.peerCertificate`; on mismatch, `destroy()` and throw.
     - SHA-256 comes from the existing `cryptography` package (`Sha256().hash`).
   - **`pair(QrPayloadV2)`:**
     - same `pcId` + `fp` as stored → update `addrs`/`port` only;
     - otherwise create the `phoneId` (if absent) and a new `deviceToken` (`Random.secure()`, 32 bytes), send `PAIR`, and store everything only on `PAIR_OK`.
   - **`report({required AppDatabase db, required Map bodyFix})`:**
     1. Try `lastGoodAddr`, then each `addrs` entry.
     2. Send `HELLO` and expect `HELLO_OK`.
     3. Loop: up to **500** pending outbox rows → `BATCH` → `ACK` → `handleAckResponse`, until the outbox is empty.
     4. Store `lastGoodAddr` and close.

     **Returns** a typed result:
     - `ok(sent, acked)`;
     - `unreachable`;
     - `unpaired`;
     - `schemaMismatch`;
     - `protocolError`.
5. **Platform permissions (F27 b–c):**
   - `Info.plist`: `NSLocalNetworkUsageDescription` = `Tenth Spring delivers your scouting reports to your PC over this Wi-Fi.`
   - `AndroidManifest.xml` (main): `<uses-permission android:name="android.permission.INTERNET"/>`.
6. **UI** — scout vocabulary only, per `design_companion_and_sync.md` §4:
   - **Ledger screen:** add a `Report to PC` button, and a `Last report: <relative time>` line.
   - **Pairing:** a `Pair with your PC` entry opens a `mobile_scanner` view.
   - **Unreachable:** `Can't reach your PC — open the scout report on your PC and re-scan its code.`
   - **Unpaired:** `This phone isn't paired with that PC anymore — scan its code to pair again.`
7. **Tests** (Dart; the new total must be **≥ 22**, and report the exact number):
   - **Removed:** the two AEAD tests.
   - **Added:**
     - QR v2 valid parse; rejects `v: 1`, an uppercase-hex `fp`, and 5 `addrs`;
     - frame codec round trip, split delivery, and an oversize header;
     - **pin accept / pin refuse:** start a local `SecureServerSocket` with a key and certificate **generated at test time** by the dev dependency `basic_utils` (pin the current version from pub.dev in `pubspec.yaml`; commit no private keys). The client pinned to it connects; pinned to a different fingerprint, it fails before any byte is read;
     - fingerprint parity: `companion/test/fixtures/test_cert.pem` (the same file as 3a's) hashes to the same hex;
     - `report()` against a fake Dart frame server purges the outbox through `lastAppliedSeq`; an `ERROR unpaired` reply returns `unpaired` and deletes nothing.

     Use `FlutterSecureStorage.setMockInitialValues({})` in tests.

### 3c — end-to-end: `test(sync): cross-language loopback sync in CI`
1. **`game/tests/sync_e2e_server.tscn` + `.gd`** — not a `_test.gd`, so the harness never runs it:
   - **Setup:** test DB path `user://test/e2e.db`, identity dir `user://test/sync_identity_e2e/`, port **7351**, and a pairing code.
   - **Ready line:** print one line, `E2E_READY {"port":7351,"fp":"<hex>","pair":"<hex>","pcId":"<hex>"}`.
   - **Finish:** once a session has completed and **5 s** pass with no session, print `E2E_STATE {"visit_log":n,"map_cell":n,"place_node":n,"last_applied_seq":n}` and quit 0.
   - **Hard timeout: 120 s** → print `E2E_TIMEOUT` and quit 1.
2. **`companion/test/sync_e2e_test.dart`:**
   - **Skip unless the defines are set:** if `E2E_PORT` isn't defined via `--dart-define`, skip with reason `E2E only — run via tools/sync_e2e.py`.
   - **Otherwise:**
     1. Pair using the defines.
     2. Run `test/fixtures/errand_day.gpx` through the real capture pipeline into the outbox (reuse `gpx_integration_test`'s setup).
     3. Print `E2E_SENT {"rows":n,"maxSeq":m}`.
     4. `report()`, and expect `ok`.
     5. Re-send the same rows as one raw `BATCH` on a new session, and expect `appliedCount == 0`.
3. **`tools/sync_e2e.py`** (stdlib, `python3 -I`):
   1. Launch the Godot server scene and wait up to 60 s for `E2E_READY`.
   2. Run `flutter test test/sync_e2e_test.dart --dart-define=E2E_PORT=… --dart-define=E2E_FP=… --dart-define=E2E_PAIR=… --dart-define=E2E_PCID=…` in `companion/`.
   3. Wait for `E2E_STATE`.
   4. **Assert:**
      - flutter exit 0;
      - `visit_log == rows`;
      - `last_applied_seq == maxSeq`;
      - `map_cell ≥ 1`.
   5. Exit non-zero on any failure, printing the step that failed.
4. **`.github/workflows/sync_e2e.yml`** (push and PR):
   - Install Godot exactly as Item 0 does.
   - Install Flutter with `subosito/flutter-action@v2`, pinned to the exact version `flutter --version` reports locally. Record it in the workflow.
   - Run `flutter pub get`, `flutter analyze`, and `flutter test` (this is also the companion battery's first time in CI), then `python3 tools/sync_e2e.py`.

### Validation
- **The first assertion that can prove a transport exists:** `sync_e2e` is green on GitHub, and its log shows `E2E_STATE` with `visit_log` equal to `E2E_SENT.rows`. Confirm with `gh run view`.
- **Falsifying — pinning:** the pin-refuse test fails if `withTrustedRoots: false` or the post-connect re-check is removed. Try removing the re-check on a scratch branch; the test must still fail on the `onBadCertificate` path.
- **Falsifying — authentication:** the wrong-token and `BATCH`-before-`HELLO` cases return `ERROR` and apply nothing.
- **Falsifying — invariant 2 at the boundary:** a 4-decimal coordinate is refused.
- **Retired crypto:**
  - `grep -rn "encryptChunk\|generateMonotonicNonce\|deriveSessionKey\|multicast_dns" companion/` → nothing;
  - `grep -n "pass$" game/autoloads/sync_server.gd` → nothing.
- **Battery:** all game tests are in `EXPECTED` and pass, and `real_save_untouched` (now including the identity files) passes.
- **Manual device gate (closes Phase 1; the human runs it with you):**
  1. Put a real phone and the PC on one Wi-Fi network. Pair by QR, walk an errand, then `Report to PC`. The rows appear on the PC.
  2. In Wireshark on the PC, filter `tcp.port == 7350`. The capture shows only TLS records. Searching the capture for the home's 3-decimal latitude string finds nothing.
  3. On iOS, the local-network prompt appears on the first report.
  4. Change the PC's address (renew its DHCP lease) → `report` returns `unreachable`. Re-scan → the next report succeeds **without** re-pairing.

### Blast radius
- **3a:** `game/autoloads/sync_server.gd`, `game/autoloads/db.gd` (two token accessors), new `game/sync/*.gd`, `game/scenes/pairing.tscn`, Godot tests and fixtures, `test_runner.py` `EXPECTED`.
- **3b:** `companion/lib/sync/*`, `companion/lib/ui/scout_ledger_screen.dart`, a new pairing screen, `companion/lib/main.dart`, `pubspec.yaml`, `Info.plist`, `AndroidManifest.xml`, and `companion/test/*`.
- **3c:** the e2e scene, the Dart e2e test, `tools/sync_e2e.py`, and `.github/workflows/sync_e2e.yml`.
- **Tracking:** resolve F12, F14, F15, F27(a–c), D4, and D11's consequences in `ongoing_general_errors.md`. Mark Phase 1 closed in `master_implementation_plan.md` only after the device gate.

---

## 7. Item 4 — Phase 2: ROM spike + importer implementation plan

**⛔ Waits on the human supplying a Pokémon Black or White (USA) dump made from their own cartridge** (`TENTH_SPRING_ROM_BW`). A Platinum (USA) dump (`TENTH_SPRING_ROM_PT`) is optional; it enables the Decision 10 comparison. Requires Item 1 first. **Produces findings, a plan, and a comparison image for review. It does not build the production importer.**

**What this means for the user:** the moment the game can show its first Pokémon, and the evidence the human needs to pick a sprite style. Every Pokémon-facing system depends on it.

### The gap
- No importer exists, so the game can't display a single Pokémon.
- The riskiest unknowns are the **verify** markers in `design_rom_asset_pipeline.md` §4–5:
  - Gen 5 sprite cell assembly and the per-species layout in `a/0/0/4`;
  - LZ77 vs LZ11;
  - Gen 5 record sizes and offsets;
  - the Gen 5 text key schedule and which bank holds which names;
  - the item-icon archive;
  - and, for Platinum, the sprite decryption rule.

### Implementation
1. **Preconditions.**
   - `TENTH_SPRING_ROM_BW` is set, the file exists, and `os.path.realpath` of it is **not** inside the repo. Same for `TENTH_SPRING_ROM_PT` if set.
   - If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib**, under `tools/rom_spike/`, run with `python3 -I`. The ROM exists only on the human's machine, and Godot isn't installed there; the production importer will be GDScript, so record every rule language-neutrally.
   - **Output** goes to `~/.tenth_spring_rom_spike/` (outside the repo).
   - **PNGs** are written with `zlib` + `struct` — no third-party packages.
   - **The code must embed no bytes, names, or tables taken from a ROM.** Types are compared as numeric ids (Normal 0 … Ghost 7 … Fire 9, Water 10 … Dragon 15, Dark 16).
3. **Header.** Assert the game code against `design_rom_asset_pipeline.md` §2. Compute the SHA-1 and compare it with the No-Intro DAT entry for that title. Record the hash **and the DAT version/source** in the design doc; never guess a hash.
4. **Parse FNT/FAT.** Locate every §5 archive and record actual file counts. Expected for Black: `a/0/1/6` 669, `a/0/1/8` 668, `a/0/1/9` 668, `a/0/2/1` 560, `a/0/2/4` 627, `a/0/0/2` 288, `a/0/0/4` 14,285.
5. **Black/White data.**
   - Decode the personal records for #94, #442, #487, #593, #609, and #623. Record the record size and the field offsets you confirmed.
   - Count species 1–649 and moves (expect 559).
   - Find the text banks holding species, move, item, and ability names; decode #1, #487, and #609.
   - Locate the item-icon archive.
6. **Black/White sprites.**
   - Establish the per-species file layout in `a/0/0/4`, and the compression of each file type.
   - Assemble the **first frame** of the front sprite for **#609 Chandelure** and **#94 Gengar** from NCGR + NCER (+ NCLR, normal and shiny), on a 96×96 canvas.
   - Record the exact assembly rule.
7. **Platinum sprites** (only if `TENTH_SPRING_ROM_PT` is set): decode the front sprites for **#487 Giratina** and **#94 Gengar**, and record the exact decryption rule — seed source and iteration direction — citing `pret/pokeplatinum`.
8. **Comparison image for Decision 10** (only if both ROMs are present):
   - Render #94, #200, #355, and #487 side by side: Platinum style, then Black/White style, at 2× integer scale.
   - Save it to `~/.tenth_spring_rom_spike/decision10_comparison.png`.
   - Tell the human the path. **Never commit it.**
9. **Update the design doc.** Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–5 with the confirmed rule, citing the reference you checked or the experiment. Keep the "never in the repo" columns intact.
10. **Write `docs/implementation_plan_rom_importer.md`** at the depth of `implementation_plan_foundation.md`. Cover:
    - the GDScript modules of design §10;
    - each format rule;
    - the per-ROM resumable `rom_cache.tmp` → rename write;
    - the §7 validation suite;
    - the `asset_db` API, including the Decision 10 switch;
    - the test strategy — ROM tests run only when the env vars are set; in CI they are skipped with an explicit message, never faked.
11. **PAUSE for human review**, and Decision 10. No production importer until the plan is approved.

### Validation
- **Counts:** archive file counts match §5, or the table is corrected with evidence.
- **Types:** match design §7 for all six validation species.
- **Falsifies a wrong decode:** each decoded sprite has ≤ 16 distinct colours per palette and per-pixel variance above a threshold that random "static" cannot pass. Show the threshold failing on a deliberately wrong decode — for example, XOR with the wrong seed.
- **Names:** decode to non-empty strings with no unmapped code units.
- **Nothing leaked:** after the spike, `git status` shows only `tools/rom_spike/*.py` and doc changes — no ROM, PNG, or cache — and the guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/` · `docs/design_rom_asset_pipeline.md` §2, §4–5, §7 · new `docs/implementation_plan_rom_importer.md` · Decision 10 (add the comparison path to its block) · Decision 9/12 status.

---

## 8. Deferred — trigger-gated, do NOT start
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats home as a **256 m** cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **mDNS auto-discovery (F27 a/d).** v1 finds the PC by remembered address plus QR re-scan.
  - Doing this properly needs two things: a PC-side mDNS responder (Godot has none), and native Bonjour/NSD browsing on the phone (the `nsd` package, not raw multicast, which needs Apple's restricted entitlement on iPhones).
  - **Trigger:** the human reports that re-scanning after an address change is a real nuisance in play.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.

---

## 9. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward, write its `implementation_plan_<phase>.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9, because every Pokémon-facing system reads through `asset_db`.

---

## 10. Already delivered — do NOT rework
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI.
- **D3 background capture code** — the device gate is still pending.
- **Relocation and sync foundations:**
  - F1 relocation unit math;
  - F2 transaction + rollback;
  - F3 cell/tile grid (256 m / 16 m);
  - F5 test runner;
  - F6 `base_access_meters`.
- **F8** both-platform settings test; **F9** Android background-permission flow + banner.
- **Sync logic and schema:** the payload builders and `handleAckResponse`, DB accessor signatures, idempotent sync apply, and the §B2 DDL design.
- **IP guard:**
  - **F18** guard core;
  - **F21** fixes — renames included (`--diff-filter=d`); bytes read from the index or commit, never the disk; `--range` mode; full-history CI; fail-closed runner; guard self-tests.
- **Persistence fixes:**
  - **F13** fail-loud `execute_query`;
  - **F11** atomic `.tmp` → rename swap and recovery (retired by Item 2 by design, not reworked);
  - **F17** pivot config;
  - **F22 code** — `configure_paths`, `assert_test_safe`, and isolated test paths.
- **Pass 12 decisions and contracts:**
  - the TLS protocol in `implementation_plan_foundation.md` §B3–B4;
  - the corrected v1 DDL in §B2;
  - the two-ROM pipeline in `design_rom_asset_pipeline.md`;
  - Gen 5 additions to the creature and encounter docs.

## 11. Accepted equivalents — do NOT "fix" these back
- **`db.gd` fallback gating** — `if _db != null: execute_query(...)` / `elif not _in_transaction: _save_persistent_store()`. Correct for the fallback's lifetime; Item 2 removes the fallback, not because this was wrong.
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so files staged but not yet committed are still checked. Correct.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than spec; keep it.
- **`relocation_manager.gd:63-72`** "nearest-revealed-tile snapping", done as a minimal-circle reveal plus placement — the same guarantee as BFS.
- **`os_location_source.dart:25`** — `nativeVisits()` returns `null`; native visits are an optional hint.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check, but it is **not** evidence that isolation works. Only Item 0's executed harness is.

## 12. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever** (standing constraint 1). Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache, through `asset_db` only. **The phone companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12):
  - **649 species, Gen 1–5.** Black/White is the single data source; Platinum supplies only sprites, and only if Decision 10 says so.
  - **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5; Gen IV catch and EXP formulas.
  - No hidden abilities in v1. Gen 6+ is permanently out of scope.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell`, `place_node`, and `visit_log` (+ transient `bodyFix`). **When bag, party, PC box, or Pokémon tables are added, extend the isolation scan's forbidden tokens** in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist, and the PC refuses any coordinate finer than 3 decimals (Item 3).
- **Sync security** (Decision 11):
  - **TLS with a pinned self-signed certificate plus a device token.** Do not reintroduce libsodium or an app-level AEAD layer.
  - The phone uses `withTrustedRoots: false`.
  - **Never hand-roll crypto.**
  - **One paired phone per PC**; re-pairing never deletes history.
- **Storage** (Decisions 6–7): **SQLite only after Item 2** — no second persistence path. Bound parameters only. **The v1 DDL is frozen after Item 2**; every later change is a §B6 migration.
- **Pillar rules:**
  - Fast travel = the phone's position at sync time.
  - **Stranded:** the PC box is reachable only within `baseAccessMeters`.
  - **Healing only at home.** **Blackout drops the bag, never Pokémon.**
  - The map and Pokédex always persist.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot 4.3 (PC) + Flutter (companion). No Steam, no monetization. Discovery by address; mDNS deferred (§8).
- **Deliberate values:** the capture settings (accuracy `medium`, 25 m, 2 min) are battery decisions, and the `tuning.json` values are balance decisions.

## 13. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, distribution | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Build steps for Phases 0–1, the v1 DDL, the TLS sync protocol, the **Godot test harness contract** | `docs/implementation_plan_foundation.md` |
| ROMs (Black/White + optional Platinum), formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
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
1 STUDY     Read this item + the design_*.md / implementation_plan_*.md sections it names.
            Specs are decisions.
2 PLAN      Building a phase with no implementation_plan_*.md at build depth? Write one
            FIRST and PAUSE for human review. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written. Honor §12 and the standing constraints — above all: no
            Nintendo content in the repo; no test touches the real save or identity;
            download only what this guide names.
4 VALIDATE  This item's validation, then the full §1 battery, then confirm every CI
            workflow on GitHub (`gh run view <id> --log`). Report what actually ran:
            "source-verified", "statically checked", and "executed" are different claims.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, a download fails its check, or you'd
            need a ROM you don't have → STOP. File in ongoing_general_errors.md with
            options. Do not improvise.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design
            doc whose behavior changed — in the same commit (or the item's last commit).
7 COMMIT    One Conventional Commit per item (Item 2: two, pushed together; Item 3:
            three), WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F25)** — `game_tests` green on GitHub with exactly the `EXPECTED` `PASS` lines; the harness self-test exits 1; a re-introduced F13 and a stray test both turn CI red.
- [ ] **Item 1 (F24 + F28)** — a merge-introduced file is caught; CI runs range **and** tree scans; an unset `core.hooksPath` fails the local battery; git errors fail closed; `CPUP`/`IRBO` headers are caught.
- [ ] **Item 2** — the CI log shows `storage: SQLite extension`; reads come from disk after a restart; F26 semantics hold; the injection, `O'Brien's Pub`, legacy-import, and migration tests pass; the fallback is gone; `real_save_untouched` passes on a fresh runner — all **executed** in CI.
- [ ] **Item 3** — `sync_e2e` green, with `visit_log == rows sent`; pinning, authentication, and the 3-decimal boundary tests pass; the superseded crypto is gone; companion tests run in CI; **the device gate passes (closes Phase 1).**
- [ ] **D3 device soak run** (Decision 5 = A). **Closes Phase 0.**
- [ ] **A Black/White dump supplied**, then **Item 4** — the verify markers are resolved, `implementation_plan_rom_importer.md` is written, the comparison is shown (if Platinum was supplied), and the work is **paused for review and Decision 10**.
- [ ] The full §1 battery is green, with game tests **executed** in CI.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate step is building the ROM importer from the *approved* plan, then Phase 3. Other legitimate triggers:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the §1 battery or any CI workflow regressing;
- a §8 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
