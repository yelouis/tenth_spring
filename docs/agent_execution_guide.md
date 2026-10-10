# Agent Execution Guide — Active Build: Memory Guard + Two Small Fixes (F35, F36) + Neighborhood-Map Plan + ROM Spike (verified 2026-10-10, pass 15)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been.
- **Pokémon content** comes from ROMs **the player supplies**, read on their own machine (the PokeMMO model).
- **Scope:** all **649 Pokémon of Generations 1–5**. **Black/White** supplies all data **and all sprites** (Decision 10 = B); Platinum is not used.
- **No commerce:** no Steam release, no sales.

**Where things stand.** The foundation — background capture, a real SQLite save, and pinned-TLS pairing and sync — is built, hardened (pass 13's six fixes), and **executed in three CI workflows**. Pass 14 verified every fix in source and CI, and found two small remaining issues:
- an unreadable *old* save can lock the game out after one session (F35);
- *Scout here* can log a cached location instead of a current one (F36).

**First, though, comes a memory guard** (F38): the human asked that the project never run the machine out of memory, given that other programs start and stop and take memory at any time. After those comes the **plan** for the first map slice — a PC-only "neighborhood preview" the human asked for, built on fully offline regional map data — and then the ROM spike, which waits on the human's cartridge dump.

**What is approved for build right now:** the queue in §2, in order. **What NOT to touch:**
- §10 — already delivered;
- §11 — accepted equivalents;
- §12 — intentional decisions.

§9 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string below is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work:** **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, no sprites, no text banks, no stat tables, not even in a test fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, dumped from cartridges they own, through `TENTH_SPRING_ROM_BW`, which points **outside** the repo. (`design_rom_asset_pipeline.md` §8)
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Iterate on a branch and merge or fast-forward once green. Pass 13 found three `sync_e2e` iterations force-pushed over `main`; on a public repo, history rewrites are confusing and they defeat the IP guard's range scan.
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the PC identity folder `user://sync_identity/`.

   Tests use `user://test/…` paths.
5. **The human's own location data never enters the repo:** `.gpx` routes of their neighborhood, demo saves, and anything derived from them. Tests use synthetic, made-up coordinates only.
6. **Heavy commands go through the memory guard** once Item 0 lands — `python3 -I tools/memguard.py run <step> -- <command>` (`design_memory_and_resources.md` §2). Never run two heavy commands at once, never background one beyond the session, and if a step exits 75 (no room) or 76 (stopped for memory), report it — don't retry in a loop.
7. **Download nothing** except what an item names by exact URL. This build names only Item 3's two Geofabrik extracts (plus their `.md5` files and the region index), for the speed spike. Each goes into a scratch directory outside the repo and is never committed. The Godot and Flutter installs in CI are already pinned.
8. **Every change leaves the §1 battery and all three CI workflows green** — that is the regression bar.
9. **Anything touching capture, battery, or cross-device sync requires a real-device check** before Phase 1 is declared closed (§2, HUMAN actions).
10. **The golden invariants (§12) stay green, always.**
11. **Detailed behavior lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
12. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
13. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Game-side and sync claims count as executed only when the CI workflow ran them (`gh run view <id> --log`).

---

## 1. Verified baseline (re-run 2026-10-10, HEAD `9f94699`, pushed — no code changes since pass 14)

| Battery | Command | Result |
|---|---|---|
| Companion lint | `cd companion && flutter analyze` | **No issues found** |
| Companion tests | `cd companion && flutter test` | **32 passed, 1 skipped.** The skip is `sync_e2e_test`, which only runs via `tools/sync_e2e.py`. |
| Local game battery | `python3 game/tests/test_runner.py` (repo root) | **Pass:** hook check, IP guard, guard self-tests (13), F22 static audit, vendored-file SHA-256 check, static lint + F19 SQL rule. Godot runtime tests print `game runtime tests SKIPPED — Godot not installed; CI runs them`. |
| CI `game_tests` | run `37970602659` | **Executed, green.** Harness self-test exits 1; **11/11 expected `PASS` lines**; `[REAL SAVE CHECK OK]` from outside the Godot process. |
| CI `Public-Repo IP Guard` | run `37970602679` | **Green** — range scan, full-tree scan, 13 self-tests |
| CI `sync_e2e` | run `37970602760` | **Executed, green.** Flutter 32 tests. Loopback: `E2E_SENT rows 14` → `E2E_STATE visit_log 14, last_applied_seq 14`; replay `appliedCount 0`. |
| Falsification branch | CI `scratch-falsify-f29` | Boot-time `init_db()` re-added → `[REAL SAVE CHECK FAIL]` (the in-process check alone still said PASS) |
| Real-device sync gate | phone + PC on Wi-Fi | ⚠️ **NOT RUN** — human; **ready now** |
| D3 device soak | 8 h background carry | ⚠️ **NOT RUN** — human (Decision 5 = A) |
| Memory guard | — | ⛔ **NONE** (F38). Heavy commands run unguarded today; Item 0 adds `tools/memguard.py`. |
| 2026-10-09 out-of-memory event | `/Library/Logs/DiagnosticReports/JetsamEvent-2026-10-09-1950*.ips` | **Not caused by Tenth Spring.** Two ~27–29 GB `mflux` image-generation processes and an ~11 GB `llama-server` from another project (`animated_infographics`). No Tenth Spring process was running; its last activity was ~9 h earlier. |

The last pass's six fixes landed as six reviewable commits, each built on a branch, green in all three workflows, and then fast-forwarded to `main`. **Keep working exactly that way.**

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F38 — the memory guard for every heavy command** (tooling) | The human's request (2026-10-10). **Every later item runs heavy commands** — Godot, Flutter, the map-file speed spike, the ROM spike — and from now on they all go through the guard, so it must exist first. |
| 1 | **F35 — an unreadable old save never locks the game out** (PC) | A permanent lockout, however rare, outranks a data-accuracy issue. Isolated to `db.gd` + one test. |
| 2 | **F36 — *Scout here* uses a fresh fix** (phone) | Small; touches the `LocationSource` interface and both implementations. Independent of Item 1. |
| 3 | **Phase 3 slice 1 — "Neighborhood preview": write the plan, then PAUSE** | Chosen by the human (2026-10-09): a PC-only demo of their real neighborhood, built as the first real slice of world generation. Map data is fully offline (Decision 13 = C). Plan only this pass — including a measured speed **and memory** spike for reading regional files, run under the Item 0 guard; building needs plan approval. Independent of the ROM. |
| 4 | **Phase 2 — ROM spike + importer implementation plan** | ⛔ **Waits on the human supplying a Black/White dump.** Produces findings and a plan for review. |

**▶ HUMAN actions (none block Items 0–2):**
- **To try the neighborhood demo later:** install Godot 4.3 on the Mac (README → *Run the PC game*), and make a `.gpx` route of your neighborhood, kept outside the repo. The demo will also download your region's map file once (your state; tens to hundreds of MB), and asks first.
- **Run the real-device sync gate now** — it closes Phase 1. Items 0–2 don't touch the sync protocol. Install the companion on your iPhone first (README → *Install the companion on an iPhone*).
  1. **Pair and report:** real phone + PC on one Wi-Fi network. Pair by QR — this also proves a real phone can scan the PC's QR. Walk an errand, then *Report to PC*; the rows appear on the PC.
  2. **Wireshark:** filter `tcp.port == 7350`. The capture shows only TLS records, and searching it for the home's 3-decimal latitude finds nothing.
  3. **iOS:** the local-network prompt appears on the first report.
  4. **Address change:** renew the PC's DHCP lease → *Report to PC* shows the unreachable message. Re-scan → the next report succeeds **without** re-pairing.
  5. **Second phone:** pair a second phone → the first phone's next report shows the unpaired message. Re-scanning on the first phone pairs it again.
- **Any time:** the D3 device soak (closes Phase 0).
- **To unblock Item 4:** a Black or White (USA) dump from your own cartridge (`TENTH_SPRING_ROM_BW`).

Deferred (trigger-gated, **do not start**): see §8.

---

## 3. Item 0 — F38: the memory guard for every heavy command

**What this means for the user:** their Mac runs other heavy programs — another project's image generator, a ~11–21 GB local AI model server, a browser — that start and stop on their own. Tenth Spring's tests and tools must never be the thing that tips the machine over, and must step aside cleanly when memory disappears instead of getting killed mid-write.

**Contract:** `docs/design_memory_and_resources.md` §1, §2, §4. Every constant, path, exit code, and message there is the spec.

### The gap
- **No guard anywhere.** Heavy commands start with bare `subprocess.run`, without checking free memory, without serializing, and without watching:
  - `game/tests/test_runner.py` launches Godot twice (`test_runner.py` `main()`, the harness self-test and the main suite);
  - `tools/sync_e2e.py` launches Godot and Flutter **at the same time**.
- **The next items are heavier still:** the map-file speed spike (Item 3) and the ROM spike (Item 4).
- **Context:** the 2026-10-09 out-of-memory event on this Mac came from another project's processes (`JetsamEvent-2026-10-09-195051.ips`: two ~27–29 GB `mflux` runs plus an ~11 GB `llama-server`). No Tenth Spring process was involved, but Tenth Spring's runs would have been equally unprotected.

### Implementation
1. **`tools/memguard.py`** (stdlib only; runs under `python3 -I`; importable *and* a CLI). Implement exactly `design_memory_and_resources.md` §1–§2:
   - `read_memory()` on macOS and Linux;
   - constants: `FLOOR` = max(4 GiB, 10% of RAM), 2 s poll, 15 min admission timeout, 10 s stop grace, ×1.5 runaway cap, ×1.25 budget margin;
   - the machine-wide `fcntl.flock` lock at `~/.cache/tenth_spring/locks/heavy.lock` (`TENTH_SPRING_LOCK_DIR` overrides it);
   - admission: wait for room, log every 30 s, exit **75** on timeout with the exact message;
   - the watchdog: child in its own process group (`start_new_session=True`); process-tree RSS from `ps -A -o pid=,ppid=,rss=`; stop on critical pressure ×2, available < `FLOOR/2`, or tree RSS > budget × 1.5; SIGTERM → 10 s → SIGKILL on the **group**; exit **76**;
   - the nested-run bypass via `TENTH_SPRING_MEMGUARD_HELD`;
   - the JSON-lines log at `~/.cache/tenth_spring/memguard.log`;
   - the CLI: `run`, `measure`, `doctor`.

   **The memory reader and the clock must be injectable**, for tests.
2. **`tools/memguard_budgets.json`.** Measure, on the human's Mac, with `memguard measure`: `godot_import`, `godot_selftest`, `godot_tests`, `flutter_test`, and `sync_e2e` (Godot + Flutter together, as **one** step). Record each budget = peak × 1.25, rounded up to 0.5 GiB, with the measured peak, date, and machine. Leave `demo_import`, `pbf_spike`, `rom_spike`, and `flutter_build_ios` at the 8 GiB `UNMEASURED` default until their items measure them.
3. **Wire it in:**
   - **`game/tests/test_runner.py`:** each Godot invocation goes through `memguard` as `godot_selftest` / `godot_tests`; an `import memguard` from `tools/` is fine.
   - **`tools/sync_e2e.py`:** the whole Godot + Flutter run is **one** `sync_e2e` step — the outer process takes the lock, and its children inherit `TENTH_SPRING_MEMGUARD_HELD`.
   - **All three CI workflows** call the same code, so Linux uses `/proc/meminfo`. The workflows run the `memguard doctor` output into the log first.
   - Exit codes **75** and **76** propagate as failures with their messages.
4. **`tools/test_memguard.py`** — the seven cases in `design_memory_and_resources.md` §4, exactly. Case 5 uses **real** memory: a child Python process allocating ~200 MiB in 20 MiB steps under a 50 MiB budget must be stopped as a runaway. Wire it into `test_runner.py` **fail-closed**, the same way as the guard self-tests: a missing file is a failure.
5. **Document the agent rule** in THE LOOP (already in this guide) and in `README.md` setup notes: one line saying heavy commands go through `python3 -I tools/memguard.py run <step> -- <cmd>`.

### Validation
- **Falsifying — runaway:** test case 5 passes, and fails if the RSS check is removed. Prove that on a scratch branch.
- **Falsifying — other programs:** while a guarded `godot_tests` run is in progress, start a separate memory hog that drops available memory below `FLOOR/2` — e.g. `python3 -c "b=bytearray(N); input()"` with N sized from `doctor`'s reading. The guard stops the run with exit 76 and the cause `available below floor`. Then free the hog, rerun, and it passes. Record the transcript in the commit body.
- **Admission:** with a fake reader reporting too little memory, `run` waits, logs the waiting line, and exits 75 after the (test-shortened) timeout.
- **Serialization:** two simultaneous `memguard run sync_e2e …` invocations run one after the other. The log shows the second with `waited_ms > 0`.
- **Doctor:** `memguard doctor` on the Mac reports an available figure within 10 points of `memory_pressure -Q`'s free percentage.
- **All three CI workflows green,** each log showing `memguard` lines for its heavy steps.

### Blast radius (same commit)
New `tools/memguard.py`, `tools/memguard_budgets.json`, `tools/test_memguard.py` · `game/tests/test_runner.py` · `tools/sync_e2e.py` · `.github/workflows/*.yml` · `README.md` (one setup line) · F38 → Resolved.

---

## 4. Item 1 — F35: an unreadable old save never locks the game out

**What this means for the user:** a player upgrading from an old save that turns out to be corrupted plays one session normally — and from then on the game refuses to start, every time, until someone deletes a hidden file by hand.

### The gap
In `game/autoloads/db.gd` `_run_legacy_import`:
- **The checks run in the wrong order.** The "database already has rows" precondition — `print`, `push_error`, `close()` — runs **before** the backup is parsed.
- **An unreadable backup is never marked as handled.** When both `<bak>` and `<bak>.tmp` are unparseable, the function prints `storage: legacy save unreadable — kept at <path>` and returns **without recording anything**, so `_has_unimported_legacy_bak()` stays true.

**Sequence today:**
1. Boot 1: unreadable → skipped; the player syncs, so rows are written.
2. Boot 2 and every boot after: the precondition sees rows → `storage: UNAVAILABLE — legacy import blocked` → the database closes.

**Contract (updated this pass):** `design_game_state_and_models.md` §0, legacy-import bullet, "Order matters (F35)".

### Implementation
1. **Reorder `_run_legacy_import`:**
   1. Return if `meta.legacy_import` exists.
   2. Find the candidate backup.
   3. **Parse** the backup, then its `.tmp`.
   4. If unreadable → step 2.
   5. Otherwise → the rows precondition → the import, unchanged.
2. **When the backup is unreadable:**
   - In one transaction: `INSERT INTO meta (key, value) VALUES ('legacy_import', ?)` with `<bak file name> + " (unreadable — kept)"`.
   - Print exactly `storage: legacy save unreadable — kept at <path>`.
   - Continue booting normally. **Never rename, modify, or delete the backup.**
   - If that meta insert fails, use the existing `_fail_legacy_import(last_error)` path.
3. **Leave untouched:** the readable-import path, the precondition's message, and `_fail_legacy_import`.

### Validation (Godot, `db_legacy_import_test` — add cases; no new test file, so `EXPECTED` doesn't change)
- **Falsifying:**
  1. Write `not json` to the test `DB_PATH` (no `.tmp`).
  2. `init_db()` → `_db != null`, and `meta.legacy_import` ends with `(unreadable — kept)`.
  3. `upsert_map_cell(1, 1, 1)`.
  4. `DB.close()`, then `init_db()` again → `_db != null` (**today it is null — the lockout**), and the map cell is still there.
  5. The backup is byte-identical to `not json`.
- **The precondition still protects real imports:** with a **readable** backup and no `legacy_import` row, a pre-existing `map_cell` row still → `init_db()` closes the database. This is the existing test; keep it passing.
- `game_tests` green with 11 `PASS` lines.

### Blast radius (same commit)
`game/autoloads/db.gd`, `game/tests/db_legacy_import_test.gd` · F35 → Resolved. The contract is already updated.

---

## 5. Item 2 — F36: *Scout here* uses a fresh fix

**What this means for the user:** pressing *Scout here* should mark where they are standing right now — not wherever the phone last happened to record them, which after the app was asleep can be somewhere else entirely.

### The gap
- **A cached fix, stamped as now.** `companion/lib/ui/scout_ledger_screen.dart` `_triggerManualScout` inserts a visit at the cached `_lastFix` with `startedAt: now`.
- **Why the cache can't simply be age-checked:** the capture stream uses a 25 m distance filter (`os_location_source.dart`), so a correct fix can be hours old for someone sitting still. A stale one can also be miles away after the app slept.
- **No way to ask for a fresh fix:** `LocationSource` (`companion/lib/capture/location_source.dart:44-49`) has no one-shot method.
- **Contract (updated this pass):** `design_privacy_and_location.md` §2 ("fresh one-shot fix … never a cached one"); `implementation_plan_foundation.md` §A6.

### Implementation
1. **Interface.** Add `Future<Fix?> currentFix();` to `LocationSource`.
2. **`OsLocationSource.currentFix()`:**
   - `Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 10)))`;
   - map the position to a `Fix`, using the position's own timestamp as `tsUtcMs`;
   - return `null` on any exception (timeout, permission, service off).
3. **`GpxReplaySource.currentFix()`:** return the most recently emitted fix, or `null` if none has been emitted. This is a test/debug source.
4. **`_triggerManualScout`:**
   1. Show `Finding your location…` while waiting.
   2. `final fix = await _locationSource?.currentFix();`
   3. If `null` → a SnackBar with exactly `Couldn't find your location — try again in a moment.`, and return. **No fallback to `_lastFix`.**
   4. Otherwise: `final p = fuzzPoint(fix.lat, fix.lon);` insert the visit at `p.lat`/`p.lon` with `startedAt: fix.tsUtcMs`, and set `_lastFix` from the same fix so the next report's `bodyFix` is current too.
   5. Keep the existing success SnackBar.
5. **Everything else stays as it is:** the `bodyFix` rule (F34), the 25 m / 2 min stream settings, and invariant 2 — `fuzzPoint` stays the only place raw coordinates exist.

### Validation (Dart)
- **Falsifying (widget test with a fake `LocationSource`):**
  - Its stream emits fix A (`37.700, -122.400`, ts 1000), then its `currentFix()` returns fix B (`37.800, -122.500`, ts 9000).
  - Tap *Scout here*. The outbox row is at B's fuzzed coordinates with `startedAt == 9000`.
  - **Today it is at A, stamped with the tap time.**
- **No fallback:** `currentFix()` returning `null` → no outbox row is inserted, and the SnackBar text matches exactly.
- **`GpxReplaySource`:** `currentFix()` is `null` before replay, and the last emitted fix after.
- `flutter analyze` clean; `flutter test` count = 32 + your new tests, reported exactly. `sync_e2e` green.

### Blast radius (same commit)
`companion/lib/capture/location_source.dart`, `os_location_source.dart`, `gpx_replay_source.dart`, `companion/lib/ui/scout_ledger_screen.dart`, `companion/test/` (a new widget test, or an extension to `widget_test.dart`) · F36 → Resolved.

---

## 6. Item 3 — Phase 3, slice 1: "Neighborhood preview" — write the plan, then PAUSE

**The human chose this on 2026-10-09:** a PC-only demo of their real neighborhood, built as the **first real slice of world generation** — not a throwaway — with **fully offline map data (Decision 13 = C)**: the PC downloads a whole regional OpenStreetMap file once and reads every street from it locally, and real movement only un-fogs parts of that preloaded map.

Per THE LOOP step 2, **this item writes `docs/implementation_plan_world_generation.md` (slice 1 only) at the depth of `implementation_plan_foundation.md`, including one measured speed spike, and then PAUSES for human review.** Building it is the next pass, after approval.

**What this means for the user:** for the first time they see their own streets as a game map on the PC — fog everywhere except where they've walked — without needing the phone.

### The gap (what exists today)
- **No map at all.** The PC has no map view, and there is no offline map-data reader: `game/world/` doesn't exist, the only scene is the pairing screen, and there is no OpenStreetMap client.
- **Reveals are narrower than designed.** `game/autoloads/sync_server.gd` `process_batch` reveals only the single 256 m cell containing each point. `implementation_plan_foundation.md` §B4.5 says corridor rows reveal every cell within `corridorRevealMeters` (60 m) of the point (**F37**).
- **No PC-only input path.** Real movement reaches the PC only from the phone. The cross-language test (`tools/sync_e2e.py`) already shows the companion's real capture pipeline can run headless on a computer and report to Godot over pinned TLS — the demo should reuse exactly that.

### What the plan must specify (each is a decision for the plan to pin down exactly — numbers, names, file paths)
1. **Demo profile — never the real save.**
   - Launching with the user arg `--demo` (read via `OS.get_cmdline_user_args()`) makes the game use `user://demo/tenth_spring.db` and identity dir `user://demo/sync_identity/`, and show a visible `DEMO` badge.
   - The real save and identity are never opened in demo mode. Add the demo paths to nothing protected — they're disposable.
   - A test asserts that demo mode never opens `user://tenth_spring.db`.
2. **`tools/demo_import.py --gpx <path>`** (stdlib, `python3 -I`):
   - **Refuses** any GPX path inside the repo (same `realpath` rule as ROMs).
   - Launches Godot headless with a demo-import scene (the `sync_e2e_server` pattern, with demo paths and port **7352**).
   - Runs the companion's **real** pipeline: GPX replay → detector → fuzz → outbox → pinned-TLS report. Use `flutter test test/demo_import_test.dart --dart-define=DEMO_GPX=<path> …`, skipped without the define, like `sync_e2e_test`.
   - **Do not re-implement visit detection in GDScript.**
   - Runs entirely under `memguard run demo_import -- …` (Item 0) as **one** step; Godot and Flutter are children of it.
   - Prints how many rows were applied.
3. **GPX rules for hand-drawn routes,** which usually have no timestamps or dwells:
   - track points = corridor;
   - waypoints (`<wpt>`) = visits, given a synthesized **10-minute** dwell;
   - track points without `<time>` get synthesized walking timestamps at **1.4 m/s**.

   Pin these in the plan and test them with a committed **synthetic** GPX fixture (made-up coordinates — never the human's).
4. **Corridor reveal (F37):** fix `process_batch` to reveal every cell within 60 m of a corridor point, per §B4.5, with a unit test at a cell boundary.
5. **Offline map data (Decision 13 = C)** — the heart of this plan. Contract: `design_world_generation.md` §3, "Map data source".
   - **Source:** Geofabrik regional extracts, for example `https://download.geofabrik.de/north-america/us/<state>-latest.osm.pbf`. Each has an `.md5` beside it (`<file>.md5`); verify the download against it.
   - **Choosing the region:** from `https://download.geofabrik.de/index-v1-nogeom.json` (≈ 0.5 MB), plus boundary geometry from `index-v1.json` (≈ 3.8 MB), pick the **smallest** region containing the revealed cells. Every download needs the **player's confirmation, showing its size**.
   - **No location-bearing requests, ever.** No Overpass and no bounding-box queries. The region index and whole-region files are the only map traffic.
   - **Map store:** convert the extract **once** into a separate SQLite file per region, `user://map_data/<region-id>.db` — **not** the save.
     - Keep only the features slice 1 renders: `highway`, `building`, `landuse`, `leisure`, `natural`, `waterway`, plus the POI tags the place-category table needs.
     - Store simplified geometry keyed by 256 m cell, so drawing a cell is one indexed read.
     - Opened read-only when rendering; deletable and regenerable. The save's frozen `osm_cache` table stays unused.
   - **Speed spike — this decides the converter.** Write a pure-GDScript PBF reader (protobuf varints + `PackedByteArray.decompress` for zlib blobs — verify which `Compression` mode reads PBF's zlib streams) and time it, single- and multi-threaded, on **two named downloads**. **The spike reader must already follow `design_memory_and_resources.md` §3.1:** stream blob by blob, never a dictionary of all nodes, and at most 4 blocks in flight. Every run goes through `memguard run pbf_spike -- …` (Item 0) — **one run at a time**, never single- and multi-threaded side by side. Measure its budget with `memguard measure` on the DC file first.
     - `https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf` (≈ 21 MB);
     - `https://download.geofabrik.de/north-america/us/washington-latest.osm.pbf` (≈ 364 MB).

     Each is downloaded into a scratch directory outside the repo and verified against its `.md5`. Record MB/s, **peak RSS** (from the memguard log), and the extrapolated time for a 1.2 GB state (California). **Decision rule, stated in the plan:**
     - **≤ 30 min and ≤ 1 GiB peak** for the 364 MB file → a GDScript converter on a background thread, with a progress bar, that pauses and resumes on low memory (§3.1);
     - otherwise → **STOP and file a decision** in `ongoing_general_errors.md` with options — e.g. a vendored native converter (the `godot-sqlite` pattern; check licences, and avoid AGPL tools), or a one-time helper tool. Don't pick one yourself.
   - **Outside every installed region:** revealed cells render plain grey with an "unmapped" chip, and the game offers that region's download.
   - **Updates:** an "Update map data" action re-downloads and reconverts a region. Optional for slice 1, but the plan says how.
6. **Tiles:** rasterize at 16 m tiles per `design_world_generation.md` §3:
   - roads ≥ 1 tile wide;
   - buildings as rectangles ≥ 2×2 (doors may wait);
   - parks and forest → grass; water → water; everything else → fill.

   **Deterministic:** a pure function of (OSM payload, cell seed). The tests use a **synthetic** OSM fixture, because real OSM data carries ODbL licence obligations and could be the human's neighborhood.
7. **Rendering:**
   - Godot `TileMapLayer`s with flat-colour programmer art.
   - Fog per `design_art_direction.md`: `unknown` = solid `#0d1119`; `known` = desaturated 40% + dark overlay. `cleared` doesn't exist yet.
   - Camera: pan by drag and WASD, integer zoom steps on the mouse wheel; start centred on the most-visited revealed cell.
   - Render only the cells in view, and state a frame-time target and how it's measured.
8. **Attribution (legal requirement):** the map view always shows `© OpenStreetMap contributors` in a corner (OSM's ODbL licence requires it).
9. **Memory (F39):** the plan specifies the converter exactly to `design_memory_and_resources.md` §3.1 — streaming, ≤ 1 GiB peak, checkpointed, and **pausing when other programs take memory**. That includes the pause test with a fake `get_memory_info`, plus the runtime caps of §3.3 for the map view (≤ 256 decoded cells; paged queries).
10. **CI:** a demo-import run on the synthetic GPX plus a **synthetic `.osm.pbf` fixture** asserts the steps below. Generate the fixture with a committed stdlib script; it uses made-up coordinates, so there is no ODbL data and no real place. No network in CI.
   - rows applied;
   - corridor cells revealed;
   - an identical tile hash across two runs.

   Real Geofabrik downloads happen only in the speed spike and the human's manual demo — never in CI.
11. **Privacy:**
    - Add `*.gpx` and `*.osm.pbf` to `.gitignore`, with exceptions for `companion/test/fixtures/*.gpx` and the synthetic PBF fixture's path.
    - The plan states that the human's route files and demo saves never enter the repo.
    - **No coordinates ever appear in logs** beyond the 3-decimal precision.

### Validation (for this item — the plan, not code)
- `docs/implementation_plan_world_generation.md` exists, covers points 1–11 with exact values and a falsifiable test for each, and lists what slice 1 does **not** do (no tall grass or encounters, no zones beyond tile colour, no landmarks, no player movement or travel, no `cleared` state, no intel ceremony).
- `design_world_generation.md` is updated only where the plan pins down something it left open (e.g. the GPX rules).
- **The speed-spike numbers** — MB/s **and peak RSS**, single- and multi-threaded, both files, on the human's Mac — are in the plan, together with the converter choice the decision rule produced (or the filed decision, if the rule said STOP).
- **No extract, store, or GPX in the repo:** `git status` is clean of `*.osm.pbf`, `map_data/`, and `*.gpx` outside the fixtures.
- **PAUSE:** report to the human — including how big their region's download will be — and wait for approval before writing any slice-1 code.

### Blast radius
New `docs/implementation_plan_world_generation.md` · `docs/design_world_generation.md` (only the pinned-down details) · F37 → linked to the plan · `master_implementation_plan.md` Phase 3 → "slice 1 planned".

---

## 7. Item 4 — Phase 2: ROM spike + importer implementation plan

**⛔ Waits on the human supplying a Pokémon Black or White (USA) dump made from their own cartridge** (`TENTH_SPRING_ROM_BW`). The IP guard fixes it depends on (F24, F28) are delivered. **Produces findings and a plan for review. It does not build the production importer.**

**What this means for the user:** the moment the game can show its first Pokémon, and the evidence the human needs to pick a sprite style. Every Pokémon-facing system depends on it.

### The gap
- No importer exists, so the game can't display a single Pokémon.
- The riskiest unknowns are the **verify** markers in `design_rom_asset_pipeline.md` §4–5:
  - Gen 5 sprite cell assembly and the per-species layout in `a/0/0/4`;
  - LZ77 vs LZ11;
  - Gen 5 record sizes and offsets;
  - the Gen 5 text key schedule and which bank holds which names;
  - and the item-icon archive.

### Implementation
1. **Preconditions.**
   - `TENTH_SPRING_ROM_BW` is set, the file exists, and `os.path.realpath` of it is **not** inside the repo.
   - If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib**, under `tools/rom_spike/`, run with `python3 -I`. The ROM exists only on the human's machine, and Godot isn't installed there; the production importer will be GDScript, so record every rule language-neutrally.
   - **Output** goes to `~/.tenth_spring_rom_spike/` (outside the repo).
   - **PNGs** are written with `zlib` + `struct` — no third-party packages.
   - **Memory:** read archives by FAT offset (seek + read), never the whole ROM into memory, and decode one sprite at a time (`design_memory_and_resources.md` §3.2). Every spike run goes through `memguard run rom_spike -- …` (Item 0); measure its budget on the first run.
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
7. **Preview image for the human:** render the static front sprites of #94, #200, #355, #487, #609, and #623 side by side at 2× integer scale to `~/.tenth_spring_rom_spike/preview.png`, and tell the human the path. **Never commit it.**
8. **Update the design doc.** Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–5 with the confirmed rule, citing the reference you checked or the experiment. Keep the "never in the repo" columns intact.
9. **Write `docs/implementation_plan_rom_importer.md`** at the depth of `implementation_plan_foundation.md`. Cover:
    - the GDScript modules of design §10;
    - each format rule;
    - the per-ROM resumable `rom_cache.tmp` → rename write;
    - the §7 validation suite;
    - the `asset_db` API;
    - the test strategy — ROM tests run only when the env vars are set; in CI they are skipped with an explicit message, never faked.
10. **PAUSE for human review.** No production importer until the plan is approved.

### Validation
- **Counts:** archive file counts match §5, or the table is corrected with evidence.
- **Types:** match design §7 for all six validation species.
- **Falsifies a wrong decode:** each decoded sprite has ≤ 16 distinct colours per palette and per-pixel variance above a threshold that random "static" cannot pass. Show the threshold failing on a deliberately wrong decode — for example, XOR with the wrong seed.
- **Names:** decode to non-empty strings with no unmapped code units.
- **Nothing leaked:** after the spike, `git status` shows only `tools/rom_spike/*.py` and doc changes — no ROM, PNG, or cache — and the guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/` · `docs/design_rom_asset_pipeline.md` §2, §4–5, §7 · new `docs/implementation_plan_rom_importer.md` · Decision 9/12 status.

---

---

---

## 8. Deferred — trigger-gated, do NOT start
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; `game/scripts/relocation_manager.gd:46-47` treats home as a **256 m** cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **mDNS auto-discovery (F27 d).** v1 finds the PC by remembered address plus QR re-scan.
  - Doing this properly needs two things: a PC-side mDNS responder (Godot has none), and native Bonjour/NSD browsing on the phone (the `nsd` package, not raw multicast, which needs Apple's restricted entitlement on iPhones).
  - **Trigger:** the human reports that re-scanning after an address change is a real nuisance in play.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.
- **Session-start relocation (§B5) on game launch.** `relocation_manager.gd` exists, but the main scene doesn't call it yet. **Trigger:** Phase 4 (travel & fast travel). It is not part of Phase 1's exit criterion.

---

## 9. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward, write its `implementation_plan_<phase>.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9, because every Pokémon-facing system reads through `asset_db`.

---

---

## 10. Already delivered — do NOT rework
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI. D3 background-capture code is done; its device soak is pending.
- **Early fixes:** F1, F2, F3, F5, F6, F8, F9, F11, F13, F17, F18, F21, F22.
- **Pass 12 build (M12–M15):**
  - **Test harness and CI:** the scene-based Godot harness and the `game_tests` workflow.
  - **IP guard:** `-m` merge scanning, tip-tree scan, fail-closed errors, and region-agnostic Gen 4–5 prefixes.
  - **Storage:** vendored `godot-sqlite` v4.4 and the real SQLite engine — WAL, bound parameters, MAX-semantics upserts, the nine-table v1 DDL, migrations, and the legacy import.
  - **Sync:** pinned-TLS pairing and sync — `PcIdentity`, `PairingCodes`, `FrameCodec`, `QrCode`, the session state machine, `ScoutLink`, and `PairingStore`.
  - **End-to-end:** the `sync_e2e` CI workflow.
- **Pass 13 fixes (M16–M20):**
  - **F34:** `bodyFix` is only a real, fix-timestamped observation; stale fixes are refused; `update_sync_peer_seq` handles batches without one.
  - **F33:** `unpaired` clears the device token, and re-pairing really re-pairs.
  - **F32:** `ERROR storage`, plus PAIR validation before the code is consumed and a transactional token save.
  - **F31:** every import statement is checked; failures close the database.
  - **F29:** the runner-level save snapshot, with its vacuity guard.
  - **F30:** the evil-merge self-tests.

## 11. Accepted equivalents — do NOT "fix" these back
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so files staged but not yet committed are still checked. Correct.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than spec; keep it.
- **`relocation_manager.gd:63-72`** "nearest-revealed-tile snapping", done as a minimal-circle reveal plus placement — the same guarantee as BFS.
- **`os_location_source.dart:25`** — `nativeVisits()` returns `null`; native visits are an optional hint.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check. The proof is the runner-level save snapshot and the executed `real_save_untouched`.
- **The legacy import uses the same `ON CONFLICT` upserts** as live writes. Equivalent on an empty database.
- **`SyncServer.configure_identity()` and `create_dispatcher()`** are dependency-injection seams for tests. They read no live request data, so they are not test hooks in the production path.
- **The dispatcher accepts an integral float `seq`/`tsUtcMs`**, because Godot's JSON parser returns all numbers as floats.
- **`main.tscn` instances the pairing screen directly** (visible at launch) until the game has a menu (Phase 9).
- **QR codes use ECC level M.**
- **The legacy-import failure path is a helper, `_fail_legacy_import(reason)`, shared by statement failures and count mismatches** — equivalent to the spec's single failure path.
- **`buildBatchPayload` uses Dart's null-aware map element `"bodyFix": ?bodyFix`** to omit the key. Correct.
- **PAIR rejects malformed frames with `ERROR protocol`** rather than `bad_pair_code`, and doesn't consume the code. That is what the spec asked for.

## 12. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever** (standing constraint 1). Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache, through `asset_db` only. **The phone companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12):
  - **649 species, Gen 1–5.** Black/White is the only ROM — all data and all sprites (Decision 10 = B).
  - **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5.
  - No hidden abilities in v1. Gen 6+ is permanently out of scope.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell`, `place_node`, and `visit_log` (+ the body position). **When bag, party, PC box, or Pokémon tables are added, extend the isolation scan's forbidden tokens** in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist, and the PC refuses any coordinate finer than 3 decimals.
- **Memory** (`design_memory_and_resources.md`): heavy work is bounded by construction, admitted only when there's room, and watched while it runs; when memory runs short it is paused or stopped cleanly and resumably, never left for the OS to kill. Budgets are **measured**, not guessed.
- **Map data is fully offline** (Decision 13 = C). It comes from whole regional OpenStreetMap files the player confirms, read locally from a per-region map store. **Never** add Overpass or any request that names a place, cell, or bounding box. `© OpenStreetMap contributors` is always shown.
- **Every location the phone reports is a real observation.** `bodyFix` and *Scout here* use real, fuzzed fixes stamped with the fix's own time — never a default, never a cached fix presented as current (F34, F36).
- **Sync security** (Decision 11):
  - **TLS with a pinned self-signed certificate plus a device token**; the phone uses `withTrustedRoots: false` and a post-connect re-check. **Never hand-roll crypto.**
  - **One paired phone per PC.** Re-pairing never deletes history, and `unpaired` discards the phone's token.
  - **ACK means success.** Every failure is an `ERROR` frame with a code.
- **Storage** (Decisions 6–7):
  - **SQLite only**, with bound parameters only. **The v1 DDL is frozen**; every change is a §B6 migration.
  - **A failed import closes the database for the session.** An **unreadable** old save is marked as handled and never blocks a boot (F35).
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
| The Black/White ROM, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
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
| Memory guards, budgets, pause/resume | `docs/design_memory_and_resources.md` |
| Decisions, findings, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

---

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md / implementation_plan_*.md sections it names.
            Specs are decisions.
2 PLAN      Building a phase with no implementation_plan_*.md at build depth? Write one
            FIRST and PAUSE for human review. Applies to every phase from 2 on.
3 IMPLEMENT Exactly as written, on a branch. Honor §12 and the standing constraints —
            above all: no Nintendo content in the repo; no test touches the real save or
            identity; never force-push main.
4 VALIDATE  This item's validation, then the full §1 battery, then confirm all three CI
            workflows on GitHub (`gh run view <id> --log`). Report what actually ran:
            "source-verified", "statically checked", and "executed" are different claims.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, or you'd need a ROM you don't have →
            STOP. File in ongoing_general_errors.md with options. Do not improvise.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design
            doc whose behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F38)** — `memguard` admits, serializes, and watches every heavy command; the runaway and "other program took the memory" tests stop runs with exit 76; budgets measured for the existing steps; all three CI workflows log `memguard` lines.
- [ ] **Item 1 (F35)** — an unreadable old save is marked as handled; a second boot after playing opens normally; executed in CI.
- [ ] **Item 2 (F36)** — *Scout here* records the fresh fix at its own time and never falls back to the cache; executed in CI.
- [ ] **HUMAN: real-device sync gate passes** (the five steps in §2). **Closes Phase 1.**
- [ ] **HUMAN: D3 device soak run** (Decision 5 = A). **Closes Phase 0.**
- [ ] **Item 3** — `docs/implementation_plan_world_generation.md` (slice 1) is written with measured speed-spike numbers **and peak memory** and the converter choice (or a filed decision), and **paused for review**.
- [ ] **A Black/White dump supplied**, then **Item 4** — the verify markers are resolved, `implementation_plan_rom_importer.md` is written, the preview is shown, and the work is **paused for review**.
- [ ] The full §1 battery and all three CI workflows are green.

**When all of the above are checked: this build's queue is empty. Do NOT invent work.** The next legitimate steps are building slice 1 of the map from its *approved* plan, and the ROM importer from its *approved* plan. Other legitimate triggers:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the §1 battery or any CI workflow regressing;
- a §8 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
