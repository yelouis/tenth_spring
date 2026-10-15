# Agent Execution Guide — Active Build: Grid + macOS + Memory-Guard Fixes (F42, F40, F41), then the Neighborhood Map Preview (Decision 14 = A) (verified 2026-10-10, pass 16)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been.
- **Pokémon content** comes from a ROM **the player supplies**, read on their own machine (the PokeMMO model).
- **Scope:** all **649 Pokémon of Generations 1–5**. **Black/White** supplies all data **and all sprites** (Decision 10 = B).
- **No commerce:** no Steam, no sales.

**Where things stand.** The foundation — background capture, a real SQLite save, pinned-TLS pairing and sync, and the memory guard — is built and executed in three CI workflows. Pass 16 verified the last build's four items:
- **F38** (memory guard), **F35** (unreadable old save), and **F36** (*Scout here* fresh fix) are genuinely fixed.
- **Item 3**, the neighborhood-map plan, was written, but its speed test measured only a skim of the file. The plan has been amended, and **the human approved it on 2026-10-10 — Decision 14 = A**: the full plan, including the in-game map download.

Pass 16 also found three new problems — two of them serious:
- **F42 — the map grid is skewed** 40–58° across the US: north–south streets would render as diagonals, and distances from home come out wrong. It must be fixed before the first real save exists.
- **F40 — on a Mac, the game cannot open its save.** The vendored SQLite add-on's macOS bundle names the wrong executable. The human's PC is a Mac, so their device test would fail. CI is Linux-only and never saw it.
- **F41 — memory-guard rough edges:** a log line that never prints, an unguarded `measure`, and a cross-check that can't pass.

**What is approved for build right now:** Items 0–10 in §2, in order — the three fixes, then the whole map preview (Decision 14 = A). Item 11 waits on a ROM.

**What NOT to touch:**
- §10 — already delivered;
- §11 — accepted equivalents;
- §12 — intentional decisions.

§9 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string here and in the docs it points to is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work:** **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, sprites, text banks, or stat tables, not even in a fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, through `TENTH_SPRING_ROM_BW`, which points **outside** the repo (`design_rom_asset_pipeline.md` §8).
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Work on a branch, get all workflows green, then fast-forward `main`. Pass 15 did exactly this — keep doing it.
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the identity folder `user://sync_identity/`;
   - from Item 3 on, the human's demo profile `user://demo/`.

   Tests use `user://test/…`.
5. **The human's own location data never enters the repo:** `.gpx` routes of their neighborhood, demo saves, map files, and anything derived from them. Tests use made-up coordinates near (0.01, 0.01) — open ocean.
6. **Heavy commands go through the memory guard:** `python3 -I tools/memguard.py run <step> -- <command>` (`design_memory_and_resources.md` §2). `test_runner.py` and `sync_e2e.py` already wrap themselves.
   - Never run two heavy commands at once, and never leave one running beyond the session.
   - If a step exits **75** (no room) or **76** (stopped for memory), report it — don't retry in a loop.
   - The Mac is shared with other projects that use tens of GB. **Never** deliberately starve it to test the guard; use the fake-reader tests.
7. **Godot on the human's Mac** is at `/Applications/Godot.app/Contents/MacOS/Godot` (4.3-stable), **not** on `PATH`. Set `GODOT_BIN` to it — `tools/sync_e2e.py` honours it today, and `test_runner.py` will after Item 1.
8. **Download nothing** except what an item names by exact URL. This build names:
   - **Item 1:** Godot's macOS zip and `SHA512-SUMS.txt` (CI only), plus — optionally — the upstream `godot-sqlite` `bin.zip`;
   - **Item 7:** the two Geofabrik extracts and their `.md5` files.

   Each local download goes into a scratch directory **outside** the repo and is never committed.
9. **Every change leaves the §1 battery and all CI workflows green** — that is the regression bar.
10. **Anything touching capture, battery, or cross-device sync requires a real-device check** before Phase 1 is declared closed (§2, HUMAN actions).
11. **The golden invariants (§12) stay green, always.**
12. **Detailed behaviour lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
13. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
14. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Name the machine (Linux CI, macOS CI, the human's Mac). Game-side claims count as executed only when a run printed the `PASS` lines (`gh run view <id> --log`, or your local transcript).

---

## 1. Verified baseline (run 2026-10-10 in this session, HEAD `49e7470`, pushed)

| Battery | Where | Result |
|---|---|---|
| `cd companion && flutter analyze` | Mac, local | **No issues found** |
| `python3 -I ../tools/memguard.py run flutter_test -- flutter test` (in `companion/`) | Mac, local | **35 passed, 1 skipped** (`sync_e2e_test`, which only runs via `tools/sync_e2e.py`). Peak 0.914 GiB. |
| `python3 game/tests/test_runner.py`, Godot not on PATH | Mac, local | **Pass:** hook check, IP guard, guard self-tests (13), F22 audit (5), memguard tests (7), vendored SHA-256, static lint + F19 SQL rule. Game runtime tests print `SKIPPED — Godot not installed`. |
| Same, with Godot 4.3 on PATH | Mac, local | ⛔ **Exit 1 — F40.** Harness self-test OK; `GDExtension dynamic library not found: …libgdsqlite.macos.template_debug.framework` → **5 of 11 FAIL** (`db_legacy_import_test`, `db_migration_test`, `db_test`, `idempotent_sync_test`, `sync_session_test`); 6 PASS. |
| Same, scratch copy of `game/` with both framework `Info.plist`s corrected | Mac, local | **11/11 PASS**, 17× `storage: SQLite extension`. This proves Item 1's fix. |
| `tools/sync_e2e.py`, scratch repo copy with the same correction | Mac, local | **Executed, green.** `E2E_SENT rows 14` → `E2E_STATE visit_log 14, last_applied_seq 14, map_cell 2`; replay assertion passed. Peak 1.114 GiB. |
| CI `game_tests` | run `38073007971` (Linux) | **Executed, green.** Harness self-test exits 1; **11/11 `PASS`**; `[REAL SAVE CHECK OK]`; memguard doctor + 7 memguard tests in the log. |
| CI `Public-Repo IP Guard` | run `38073008131` | **Green** — range scan, tree scan, 13 self-tests |
| CI `sync_e2e` | run `38073007998` (Linux) | **Executed, green.** Flutter **35 passed, 1 skipped**; loopback 14 → 14; replay `appliedCount 0` asserted. |
| `python3 -I tools/memguard.py doctor` | Mac, local | 64 GiB; available 21.8 GiB (34%), floor 6.4 GiB, pressure 1. **Warns** that `memory_pressure -Q` says 62% — F41(c); the contract now explains why. |
| Memguard waiting line | Mac, fake-clock probe | ⛔ **Never printed** in 100 s of simulated waiting; exited 75 correctly — F41(a). |
| Real-device sync gate | phone + PC | ⚠️ **NOT RUN** — human. **Blocked until Items 0 and 1 land** (F40 makes the Mac unable to store anything). |
| D3 device soak | 8 h background carry | ⚠️ **NOT RUN** — human (Decision 5 = A). Ready any time. |
| Memguard "other program" hog test | — | **Deliberately not run** on the shared Mac; Item 2 adds a fake-reader test instead. |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F42 — one Web-Mercator grid** (`game/world/grid.gd`) | **Must land before the first real save exists.** The human's device test creates it, and a save made on the skewed grid would need a migration. Every map item (3–10) projects through this file. |
| 1 | **F40 — SQLite loads on macOS** + a macOS CI job + `GODOT_BIN` | It blocks the human's device test and every local Mac run of the game. Tiny, and the fix is already proven. It goes *after* Item 0 so the Mac can't create a real save on the skewed grid in between. |
| 2 | **F41 — memory-guard fixes**, then re-measure Godot budgets on the Mac | Item 7's converter gate depends on a correct `measure`. Re-measuring needs Godot working on the Mac (Item 1). |
| 3 | **Slice 1: demo profile** (plan §1) | Approved (Decision 14 = A); starts once Items 0–2 are on `main`. Everything later writes to the demo profile. |
| 4 | **Slice 1: hand-drawn GPX replay** (plan §3) | Phone-side only; the demo import (Item 6) depends on it. |
| 5 | **Slice 1: corridor reveal — F37** (plan §4) | Uses Item 0's grid; changes the ingest that Item 6 drives. |
| 6 | **Slice 1: `demo_import.py`** (plan §2) | Needs Items 3–5. After it, the demo save holds the human's route. |
| 7 | **Slice 1: converter + map store + converter gate — F39** (plan §5.2–5.3, §9, §10.1) | The riskiest piece. Its gate can STOP the slice, so it comes before any rendering work. |
| 8 | **Slice 1: tile synthesis** (plan §6) | Reads Item 7's map store. |
| 9 | **Slice 1: map view** (plan §7–8) | Needs Items 7–8. No pause — continue to Item 10. |
| 10 | **Slice 1: region choice + download** (plan §5.1, §5.4) → **PAUSE** | Hooks into Item 9's unmapped chip, so it comes last. Ends slice 1: pause for the human to try it. |
| 11 | **Phase 2 — ROM spike + importer plan** | ⛔ Waits on the human supplying a Black/White dump. |

**▶ HUMAN actions:**
- **Run the real-device sync gate once Items 0 and 1 are on `main`** — not before. It closes Phase 1. Install the companion on your iPhone first (README → *Install the companion on an iPhone*), and start the PC game from `/Applications/Godot.app` with `game/project.godot`.
  1. **Pair and report:** real phone + PC on one Wi-Fi network. Pair by QR — this also proves a real phone can scan the PC's QR. Walk an errand, then *Report to PC*; the rows appear on the PC.
  2. **Wireshark:** filter `tcp.port == 7350`. The capture shows only TLS records, and searching it for the home's 3-decimal latitude finds nothing.
  3. **iOS:** the local-network prompt appears on the first report.
  4. **Address change:** renew the PC's DHCP lease → *Report to PC* shows the unreachable message. Re-scan → the next report succeeds **without** re-pairing.
  5. **Second phone:** pair a second phone → the first phone's next report shows the unpaired message. Re-scanning on the first phone pairs it again.
- **Any time:** the D3 device soak (closes Phase 0).
- **For the map preview later:** make a `.gpx` route of your neighborhood and keep it **outside** the repo.
- **To unblock Item 11:** a Black or White (USA) dump from your own cartridge (`TENTH_SPRING_ROM_BW`).

Deferred (trigger-gated, **do not start**): see §8.

---

## 3. Item 0 — F42: one Web-Mercator grid

**What this means for the user:** today the map grid leans sideways — in Seattle by 58°. Once the map is drawn, every north–south street would appear as a diagonal. The game would also think someone 300 m from home is 560 m away, and strand them on their own street.

**Contract:** `design_game_state_and_models.md` §2 (rewritten this pass). Decision record item 18 says why plain Web Mercator.

### The gap
- **Two private copies of the wrong projection:**
  - `game/autoloads/sync_server.gd:9-10` (`CELL_METERS`, `METERS_PER_DEGREE = 111000.0`) and `:109-122` (`latlon_to_cell`, `latlon_to_tile`);
  - `game/scripts/relocation_manager.gd:8-10` and `:43-57`.

  Both use `x = lon·111000·cos(lat)`, `y = lat·111000` — a sinusoidal projection centred on Greenwich.
- **Measured** with the code's own formula:

  | Place | Walking 256 m due north | Shear | A phone 300 m due north of home measures |
  |---|---|---|---|
  | Seattle (47.6, −122.33) | cell `(-35767, 20639)` → `(-35765, 20640)` | **57.6°** | **560 m** |
  | Washington DC | — | **40.2°** | 393 m |
- **No real save exists yet** (none on the human's Mac), so the grid can still change without a migration.

### Implementation
1. **New `game/world/grid.gd`** (`extends RefCounted`, static functions only). Callers load it with `const Grid := preload("res://world/grid.gd")` — **do not rely on `class_name`**, because the local runner doesn't run `--import`. Constants:
   - `WM_R := 6378137.0`
   - `EARTH_MEAN_R := 6371008.8`
   - `CELL_WM := 256.0`
   - `TILE_WM := 16.0`
   - `MAX_LAT := 85.05112878`

   Functions:
   - `latlon_to_wm(lat: float, lon: float) -> Vector2` — `x = WM_R·deg_to_rad(lon)`, `y = WM_R·log(tan(PI/4 + deg_to_rad(clampf(lat, -MAX_LAT, MAX_LAT))/2))`.
   - `wm_to_latlon(p: Vector2) -> Vector2` — returns `(lat, lon)`: `lat = rad_to_deg(2·atan(exp(p.y/WM_R)) − PI/2)`, `lon = rad_to_deg(p.x/WM_R)`.
   - `latlon_to_cell(lat, lon) -> Vector2i` — `floor(x/CELL_WM)`, `floor(y/CELL_WM)`.
   - `latlon_to_tile(lat, lon) -> Vector2i` — `floor(x/TILE_WM)`, `floor(y/TILE_WM)`.
   - `cell_center_latlon(cell: Vector2i) -> Vector2` — `wm_to_latlon(((cell.x + 0.5)·256, (cell.y + 0.5)·256))`.
   - `ground_distance_m(lat1, lon1, lat2, lon2) -> float` — haversine with `EARTH_MEAN_R`.
2. **`sync_server.gd`:**
   - delete `CELL_METERS` and `METERS_PER_DEGREE` (and `TILE_METERS` if nothing else uses it);
   - `latlon_to_cell` and `latlon_to_tile` become one-line delegates to `Grid`, keeping their names so callers don't change.
3. **`relocation_manager.gd`:**
   - delete its three constants;
   - get the spawn cell and tile from `Grid`;
   - add `static func distance_to_home_m(body_lat: float, body_lon: float, home_cell: Vector2i) -> float`, returning `Grid.ground_distance_m(body_lat, body_lon, c.x, c.y)` with `c = Grid.cell_center_latlon(home_cell)`;
   - `is_stranded` uses it.

   The file stays unwired (§8) — only its maths changes.
4. **Static guard in `game/tests/test_runner.py`'s lint section:** fail with `[LINT FAIL] <file>: private projection constant — use res://world/grid.gd (F42)` if `111000`, `111320`, or `METERS_PER_DEGREE` appears in any `.gd` file other than `game/world/grid.gd`.
5. **Recompute hard-coded expectations.** Grep `game/tests/` for cell coordinates computed from latitude/longitude and recompute them through `Grid`. `tools/sync_e2e.py` only asserts `map_cell ≥ 1`. Report whether `E2E_STATE map_cell` changes from 2.

### Validation — new `game/tests/grid_test.gd` (add `"grid_test"` to `EXPECTED`, making 12)
- **(a) Falsifying — north stays north.**
  - From (47.6000, −122.3300), step 20 times by 100 ground-metres due north (`lat += 100 / (EARTH_MEAN_R·PI/180)`).
  - All 21 points have the **same** `latlon_to_cell(...).x`.
  - The old formula moves x by 2 within the first 256 m.
- **(b) Known values:**
  - `latlon_to_wm(0, 0)` = (0, 0) ± 1e-6;
  - `latlon_to_wm(0, 180).x` = 20037508.342789244 ± 0.001;
  - `latlon_to_cell(0.0005, 0.0005)` = (0, 0);
  - `latlon_to_cell(-0.0005, -0.0005)` = (−1, −1).
- **(c) Round trip:** `wm_to_latlon(latlon_to_wm(p))` is within 1e-9° for 5 sample points, including (−33.86, 151.21) and (64.15, −21.94).
- **(d) Ground distance:** `ground_distance_m(47.6, −122.33, 47.6 + 300/111194.93, −122.33)` = 300 ± 0.5.
- **(e) Cell ground size:** the ground distance between the centres of cells (x, y) and (x+1, y) at Seattle = 172.6 ± 1.0 m.
- **(f) Falsifying — stranded:** take home = the cell containing (47.6000, −122.3300) and a body 300 m due north of that cell's centre. `distance_to_home_m` = 300 ± 2, so the player is **not** stranded at 500 m. Today's code gives 560.
- **Prove the falsifiers bite.** On a scratch branch, point `Grid.latlon_to_cell` and the distance back at the old formula → CI shows `FAIL grid_test`. Put the run id in the commit body, then delete the branch.
- The full battery and all workflows are green; `game_tests` shows **12** `PASS` lines.

### Blast radius (same commit)
New `game/world/grid.gd`, `game/tests/grid_test.gd` · `game/autoloads/sync_server.gd` · `game/scripts/relocation_manager.gd` · `game/tests/test_runner.py` (`EXPECTED` + lint rule) · any recomputed test expectations · F42 → Resolved. The design docs were already updated in pass 16.

---

## 4. Item 1 — F40: SQLite loads on macOS

**What this means for the user:** on their Mac — the PC they'll actually play on — the game can't open or write its save today. Every sync would answer "storage error." This item makes the Mac work, and adds a macOS CI run so it can't silently break again.

### The gap
- **Mismatched names:** `game/addons/godot-sqlite/bin/libgdsqlite.macos.template_debug.framework/Resources/Info.plist` has `CFBundleExecutable = libgdsqlite.template_debug`, but the binary in the bundle is `libmacos.libgdsqlite.template_debug`. The `template_release` framework has the same mismatch.
- **Why that fails:** Godot 4.3 resolves a `.framework` through `CFBundleExecutable` → `GDExtension dynamic library not found` → `storage: UNAVAILABLE — SQLite extension missing` (§1).
- **Proven fix:** correcting both plists → 11/11 game tests and `sync_e2e` pass on the Mac (§1).
- **Why it went unseen:** CI runs only `ubuntu-latest`; `test_runner.py` finds Godot only via `PATH`.

### Implementation
1. **Edit only the plists** — not the binaries:
   ```bash
   cd game/addons/godot-sqlite/bin
   /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable libmacos.libgdsqlite.template_debug" libgdsqlite.macos.template_debug.framework/Resources/Info.plist
   /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable libmacos.libgdsqlite.template_release" libgdsqlite.macos.template_release.framework/Resources/Info.plist
   ```
2. **Update `VENDORED.sha256`** for the two plists only; the binary hashes don't change.
3. **Add `## Local patch (2026-10-10, F40)` to `VENDORED.md`:** what changed, why (the line above), and the two commands.
   - **Optional provenance check:** download `https://github.com/2shady4u/godot-sqlite/releases/download/v4.4/bin.zip` into a scratch dir outside the repo, confirm its SHA-256 equals the one in `VENDORED.md`, and check whether upstream's plist carries the same mismatch. Record the answer: "upstream packaging" or "vendoring error."
4. **`game/tests/test_runner.py`:** `godot_bin = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")` — the same rule as `tools/sync_e2e.py`.
5. **`README.md` → *Setup notes*:** add one line — on a Mac, `export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` before running the battery.
6. **`.github/workflows/game_tests.yml`:** add a macOS job (`runs-on: macos-14`) beside the Linux one, doing the same steps:
   - download `https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_macos.universal.zip`;
   - verify it against the same release's `SHA512-SUMS.txt`, exactly as the Linux job verifies its binary;
   - unzip, and set `GODOT_BIN=$PWD/Godot.app/Contents/MacOS/Godot`;
   - run `memguard doctor`, the guarded `--import`, then `python3 game/tests/test_runner.py`.

### Validation
- **Falsifying:** on a scratch branch with the plists reverted, the **macOS** job fails (`FAIL db_test`), while the Linux job stays green. Record both run ids, then delete the branch.
- **On the fix branch:** both jobs show `storage: SQLite extension`, **12/12** `PASS` (Item 0 landed first), and `[REAL SAVE CHECK OK]`.
- **Locally on the Mac:** with `GODOT_BIN` set, `python3 game/tests/test_runner.py` executes the game tests — 12/12 and `[REAL SAVE CHECK OK]` — and `python3 -I tools/sync_e2e.py` is green. Paste both summaries in the commit body.
- The vendored SHA-256 check passes.

### Blast radius (same commit)
Two `Info.plist` files · `VENDORED.sha256` · `VENDORED.md` · `game/tests/test_runner.py` · `.github/workflows/game_tests.yml` · `README.md` (one line) · F40 → Resolved · §1 of this guide (local game tests now **executed** on the Mac).

---

## 5. Item 2 — F41: memory-guard fixes

**What this means for the user:** when their Mac is busy, the guard should *say* it is waiting rather than sit silent for 15 minutes. Measuring a heavy step must itself be guarded. And the guard's self-check shouldn't cry wolf on every run.

**Contract:** `design_memory_and_resources.md` §1 (cross-check), §2 (`measure`, budgets), and §4 cases 8–10. All were updated in pass 16.

### The gap (`tools/memguard.py`)
- **(a) The waiting line never prints.** `run_guarded` sets `last_log_time = wait_start` (absolute epoch seconds) and then tests `elapsed - last_log_time >= 30.0` with a *relative* `elapsed`. The test is never true in real use. A fake-clock probe started at the real epoch waited 100 s and printed nothing.
- **(b) `measure` is unguarded.** `measure_step` has no admission, no watchdog, and no log line, and it overwrites a budget even when the new peak is lower.
- **(c) The cross-check can't pass.** `cmd_doctor` warns whenever the readings differ by > 10 points. On a busy Mac they always do (34% vs 62%), because the kernel counts compressible memory as free.
- **(d) No floor-stop test.** Nothing tests the watchdog's "available below floor" cause — the "other program took the memory" case.
- **(e) Linux-only budgets.** The `godot_*` and `sync_e2e` budgets were measured only on Linux CI.

### Implementation
1. **(a)** Track the last logged *elapsed* value, starting at 0. Print `memguard: waiting for memory for <step>: need <X> GiB, have <Y> GiB` each time elapsed crosses 30 s, 60 s, ….
2. **(b)** Rebuild `measure_step` per §2:
   - the same lock and admission as `run`;
   - 0.2 s sampling;
   - the same stop rules, with the runaway cap at 2× the current budget (16 GiB if unmeasured);
   - log outcome `measured` (or `stopped:<cause>`);
   - **raise-only**, unless `--replace` is given — print the "kept existing budget" line exactly as §2 words it.
3. **(c)** In `cmd_doctor`, make the check one-directional, using the exact strings in §1.
4. **(d)** Add §4 cases 8, 9, and 10 to `tools/test_memguard.py`. Case 9's fake clock **starts near 1.7e9**, which is what exposes (a).
5. **(e)** After 1–4, with `GODOT_BIN` set (Item 1), run `memguard measure` on the Mac for `godot_import`, `godot_selftest`, `godot_tests`, and `sync_e2e` (`python3 -I tools/sync_e2e.py`), **one at a time**. Budgets rise only if the Mac's peak needs it. Put the four Mac peaks in the commit body.

### Validation
- **Falsifying:** cases 9 and 10 **fail against the current `memguard.py`** — run them before applying 1–2 and paste the failures in the commit body. They then pass.
- Case 8 exits 76 with outcome `stopped:available below floor`.
- `memguard doctor` on the Mac prints the `Cross-check OK: …` line.
- `test_runner.py` reports **10** memguard cases; all workflows are green.

### Blast radius (same commit)
`tools/memguard.py` · `tools/test_memguard.py` · `tools/memguard_budgets.json` · F41 → Resolved.

---

## 6. Slice 1 — the neighborhood map preview (Items 3–10)

**Approved by the human on 2026-10-10 — Decision 14 = A:** the full amended plan, including the in-game region choice and download (Item 10). Start Item 3 once Items 0–2 are on `main`.

**What this means for the user:** for the first time they see their own streets as a game map on the PC — fog everywhere except where they've walked — without needing the phone.

**The contract is `docs/implementation_plan_world_generation.md` (amended pass 16).** Each item below names its plan sections. Implement those sections exactly; this guide adds only order, proof, and blast radius.

**Rules for every slice-1 item:**
- Add each new Godot test file to `EXPECTED` in `test_runner.py`, and keep all three workflows green **on Linux and macOS**.
- Every lat/lon → cell/tile conversion goes through `res://world/grid.gd` (Item 0). The lint rule enforces it.
- Tests use `user://test/…` and the synthetic fixtures near (0.01, 0.01). Never the human's route, demo profile, or map files.
- Heavy runs go through memguard. Measure each new step (`demo_import`, `map_convert`) with `memguard measure` the first time it runs.
- Don't name any source directory `demo` or `map_data` — `.gitignore` would silently drop it (plan §11). Run `git check-ignore -v` on new paths.

### 6.1 Item 3 — Demo profile (plan §1)
**The gap:** `game/scenes/main.gd:3-5` always opens the real save and identity, and there is no `--demo`.
- **Build:**
  - `game/scripts/profile_paths.gd` exactly as the plan's §1.1 table;
  - `main.gd` resolves the profile first, applies `DB.configure_paths` and `PcIdentity.configure_dir`, then calls `init_db()` and `start_server()`.
  - The `DEMO MODE` badge arrives with the map view (Item 9).
- **Prove:** `profile_paths_test` covers all four table rows plus the integration case (§1.3). **Falsifying:** the refusal row returns `ok = false` and the error string verbatim. The runner-level `[REAL SAVE CHECK OK]` holds.
- **Blast radius:** `main.gd`, the new script and test, `EXPECTED`.

### 6.2 Item 4 — Hand-drawn GPX replay (plan §3)
**The gap:** `companion/lib/capture/gpx_replay_source.dart:57` stamps untimed points with `DateTime.now()`, and `<wpt>` is ignored. A hand-drawn route therefore produces no visits and a corridor squeezed into milliseconds.
- **Build:** rules 1–5 of plan §3.1; the fixture `companion/test/fixtures/synthetic_hand_drawn.gpx` (§3.2).
- **Prove:** `companion/test/gpx_hand_drawn_test.dart` — 1 visit ≥ 600 s, the committed corridor count, strictly increasing times starting at `t0`. **Falsifying:** adding one `<time>` switches to recorded mode → 0 visits. The existing `gpx_integration_test.dart` (recorded fixtures) stays green, unchanged.
- **Blast radius:** `gpx_replay_source.dart`, the fixture, the new test. `flutter test` count = 35 + new tests, reported exactly.

### 6.3 Item 5 — Corridor reveal, F37 (plan §4)
**The gap:** `game/autoloads/sync_server.gd:181-182` upserts one cell per row.
- **Build:**
  - add `Grid.cells_within_ground_radius` (plan §4.2) to `grid.gd`;
  - in `process_batch`, corridor rows upsert every returned cell; visit rows are unchanged.
- **Prove:** `corridor_reveal_radius_test` — 2 / 4 / 1 cells. **Falsifying:** a batch with one edge-adjacent corridor row writes **2** `map_cell` rows (today 1), and its replay changes nothing. `sync_ingest_isolation_test` (golden invariant 1) stays green. Report `sync_e2e`'s new `map_cell` count.
- **Blast radius:** `grid.gd`, `sync_server.gd`, the new test, any exact `map_cell` counts in existing tests · F37 → Resolved.

### 6.4 Item 6 — `demo_import.py` (plan §2)
**The gap:** real movement reaches the PC only from a phone.
- **Build:** `tools/demo_import.py`; `game/scenes/demo_import_server.tscn` + `.gd` (based on `game/tests/sync_e2e_server.gd`, port 7352, `DEMO_READY` / `DEMO_IMPORT_COMPLETE`); `companion/test/demo_import_test.dart`; a new step in `.github/workflows/sync_e2e.yml` (plan §10.2).
- **Prove:**
  - **Falsifying:** an in-repo `--gpx` exits 2 and starts nothing (no memguard log line).
  - In CI, the copied fixture imports with `applied == DEMO_SENT`.
  - Locally on the Mac, the same run with `--demo-dir user://test/demo` passes. Measure the `demo_import` budget.
- **Blast radius:** the new tool, scene, and test, `sync_e2e.yml`, `memguard_budgets.json`.

### 6.5 Item 7 — Converter, map store, and the converter gate — F39 (plan §5.2–5.3, §9, §10.1)
**The gap:** no map data exists on the PC; the pass-15 spike measured only a skim (plan §5.3).
- **Build:**
  - `tools/generate_synthetic_pbf.py` + `game/tests/fixtures/synthetic_neighborhood.osm.pbf` (deterministic);
  - `game/world/region_import/` — three passes, checkpointing, an injectable `memory_reader`, pause/resume;
  - the map-store schema and encoding (§5.2);
  - `tools/map_convert.py` + `game/scenes/map_convert.tscn`;
  - `map_convert` in `memguard_budgets.json` as `UNMEASURED`.
- **Prove:**
  - `region_import_test` — the golden canonical-dump hash, kinds and counts including the multipolygon lake, checkpoint resume;
  - `region_import_pause_test` — pause → resume → identical dump;
  - the test that regenerates the synthetic PBF byte-for-byte.
- **The converter gate (part of this item's validation):**
  1. Download `https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf` and `https://download.geofabrik.de/north-america/us/washington-latest.osm.pbf` (and each `.md5`) into a scratch dir outside the repo. Verify the MD5s.
  2. Run `python3 -I tools/memguard.py measure map_convert -- python3 -I tools/map_convert.py --pbf <file> --out-dir user://test/map_data` — DC first, then Washington, **one at a time**.
  3. Write per-pass and total time, peak RSS, feature counts, and store size into plan §5.3.
  4. **Rule:** Washington ≤ 30 min **and** ≤ 1 GiB → GDScript stays. Otherwise **STOP**: commit nothing further, and file a decision with options (plan §5.3).
  5. Delete the downloads and the test stores afterwards.
- **Blast radius:** everything above, `EXPECTED`, plan §5.3 numbers · F39 → Resolved (the converter half).

### 6.6 Item 8 — Tile synthesis (plan §6)
- **Build:** `game/world/tile_synth/tile_synth.gd` (`synthesize_cell`), with the exact IDs, colours, order, and widths.
- **Prove:** `tile_synth_test` — the committed golden SHA-256 for the fixture's 4 cells, **identical on the Linux and macOS jobs**. **Falsifying:** moving a building vertex by 32 WM-m changes the hash.
- **Blast radius:** the new module and test, `EXPECTED`.

### 6.7 Item 9 — The map view (plan §7–8)
- **Build:**
  - `game/world/map_view.tscn` per the scene tree in plan §7.1;
  - fog shader, camera rules, culling + LRU 256, read-only paged store queries;
  - the attribution label and the `DEMO MODE` badge;
  - the unmapped fill `#2a3242` with a chip. Until Item 10 lands, the chip reads exactly `Unmapped — no map data installed for this area`; Item 10 replaces it with plan §5.4's text and download;
  - `main.gd` opens the map view when the save holds ≥ 1 revealed cell, and otherwise the pairing screen, as today.
- **Prove:**
  - **Scene-tree assertion test:** the attribution node exists with the exact text; the badge shows only in demo mode; with 300 cached cells, the LRU holds ≤ 256.
  - **On the human's Mac:** after a demo import of the synthetic route plus a `map_convert` of the synthetic PBF into `user://test/…`, the view opens on the right cell, and **F9** prints `FRAME_P95_MS` — report it; target ≤ 16.6.
- **No pause here** — continue straight to Item 10.
- **Blast radius:** the new scene, scripts, and test, `main.gd`, `EXPECTED`.

### 6.8 Item 10 — Region choice and download (plan §5.1, §5.4) → PAUSE
- **Build:**
  - `game/world/region_import/map_fetcher.gd` (the **only** file allowed to use `HTTPRequest`/`HTTPClient`);
  - the index cache, region rule, `HEAD` size, exact dialog text, `.part` → MD5 → rename → convert → delete;
  - the chip text from plan §5.4;
  - `Update map data`.
- **Prove:**
  - `region_select_test` — nested choice and the MD5-mismatch clean-up, using the fake fetcher;
  - the grep test (no HTTP outside `map_fetcher.gd`);
  - CI makes no network calls.
- **Manually on the Mac:** with a scratch demo profile, the dialog shows a real region's size; **Not now** downloads nothing.
- **PAUSE — slice 1 is complete.** Give the human the exact steps, then wait for their feedback:
  1. `python3 -I tools/demo_import.py --gpx <path to your route, outside the repo>`;
  2. `/Applications/Godot.app/Contents/MacOS/Godot --path game -- --demo`;
  3. the map opens with your route's cells in plain grey and a chip naming your region and its download size — click the chip, then **Download**;
  4. once conversion finishes, your streets appear, fogged except along your route.

  Also report the converter-gate numbers (Item 7) and `FRAME_P95_MS` (Item 9).
- **Blast radius:** the new files and test, the map view's chip, `EXPECTED`.

---

## 7. Item 11 — Phase 2: ROM spike + importer implementation plan

**⛔ Waits on the human supplying a Pokémon Black or White (USA) dump made from their own cartridge** (`TENTH_SPRING_ROM_BW`). It produces findings and a plan for review; **it does not build the production importer.**

**What this means for the user:** the moment the game can show its first Pokémon. Every Pokémon-facing system depends on it.

### The gap
- No importer exists, so the game can't display a single Pokémon.
- The riskiest unknowns are the **verify** markers in `design_rom_asset_pipeline.md` §4–5:
  - Gen 5 sprite cell assembly and the per-species layout in `a/0/0/4`;
  - LZ77 vs LZ11;
  - Gen 5 record sizes and offsets;
  - the Gen 5 text key schedule, and which bank holds which names;
  - the item-icon archive.

### Implementation
1. **Preconditions.** `TENTH_SPRING_ROM_BW` is set, the file exists, and its `os.path.realpath` is **not** inside the repo. If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib** under `tools/rom_spike/`, run with `python3 -I`. The production importer will be GDScript, so record every rule language-neutrally.
   - **Output** goes to `~/.tenth_spring_rom_spike/`, outside the repo.
   - **PNGs** are written with `zlib` + `struct`.
   - **Memory:** read archives by FAT offset (seek + read), never the whole ROM; decode one sprite at a time (`design_memory_and_resources.md` §3.2). Every run goes through `memguard run rom_spike -- …`; measure its budget on the first run.
   - **The code embeds no bytes, names, or tables taken from a ROM.** Types are compared as numeric ids (Normal 0 … Ghost 7 … Fire 9, Water 10 … Dragon 15, Dark 16).
3. **Header.** Assert the game code against `design_rom_asset_pipeline.md` §2. Compute the SHA-1, compare it with the No-Intro DAT entry, and record the hash **and the DAT version/source** in the design doc. Never guess a hash.
4. **FNT/FAT.** Locate every §5 archive and record the actual file counts. Expected for Black: `a/0/1/6` 669, `a/0/1/8` 668, `a/0/1/9` 668, `a/0/2/1` 560, `a/0/2/4` 627, `a/0/0/2` 288, `a/0/0/4` 14,285.
5. **Data.**
   - Decode the personal records for #94, #442, #487, #593, #609, and #623, and record the record size and the field offsets you confirmed.
   - Count species 1–649 and moves (expect 559).
   - Find the species, move, item, and ability name banks, and decode #1, #487, and #609.
   - Locate the item-icon archive.
6. **Sprites.**
   - Establish the per-species layout in `a/0/0/4` and each file type's compression.
   - Assemble the **first frame** of the front sprite for **#609** and **#94** from NCGR + NCER (+ NCLR, normal and shiny) on a 96×96 canvas.
   - Record the exact assembly rule.
7. **Preview for the human:** render the static front sprites of #94, #200, #355, #487, #609, and #623 side by side at 2× to `~/.tenth_spring_rom_spike/preview.png`, and tell the human the path. **Never commit it.**
8. **Update the design doc.** Replace every **verify** marker in `design_rom_asset_pipeline.md` §4–5 with the confirmed rule, citing the reference or experiment.
9. **Write `docs/implementation_plan_rom_importer.md`** at the depth of `implementation_plan_foundation.md`. Cover:
   - the GDScript modules of design §10;
   - each format rule;
   - the resumable `rom_cache.tmp` → rename write;
   - the §7 validation suite;
   - the `asset_db` API;
   - the test strategy — ROM tests run only when the env var is set, and are skipped with an explicit message otherwise.
10. **PAUSE for human review.**

### Validation
- **Counts:** archive counts match §5, or the table is corrected with evidence.
- **Types:** match design §7 for all six species.
- **Falsifies a wrong decode:** each sprite has ≤ 16 colours per palette, and per-pixel variance above a threshold that a deliberately wrong decode (e.g. the wrong XOR seed) fails.
- **Names:** decode to non-empty strings with no unmapped code units.
- **Nothing leaked:** `git status` shows only `tools/rom_spike/*.py` and doc changes, and the guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/` · `docs/design_rom_asset_pipeline.md` §2, §4–5, §7 · new `docs/implementation_plan_rom_importer.md` · Decision 9/12 status.

---

## 8. Deferred — trigger-gated, do NOT start
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; the game treats home as one grid cell (256 WM-m after Item 0). **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **mDNS auto-discovery (F27 d).** v1 finds the PC by remembered address plus QR re-scan. Doing it properly needs a PC-side responder (Godot has none) and native Bonjour/NSD browsing on the phone. **Trigger:** the human reports that re-scanning is a real nuisance.
- **Session-start relocation (§B5) on game launch.** `relocation_manager.gd` uses the new grid after Item 0 but is still not called. **Trigger:** Phase 4.
- **A Windows CI job.** The Windows `.dll`s are vendored but have never been loaded. **Trigger:** Phase 10 release prep, or the human playing on Windows.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.
- **Slice-1 non-goals** (plan §0) — tall grass, zones, landmarks, avatar, `cleared`, multipolygon holes, POI drawing. **Trigger:** an approved slice-2 plan.

---

## 9. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward — or any new slice of one — write its `implementation_plan_*.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9.

---

## 10. Already delivered — do NOT rework
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI. The D3 code is done; its device soak is pending.
- **Early fixes:** F1, F2, F3, F5, F6, F8, F9, F11, F13, F17, F18, F21, F22.
- **Pass 12 build (M12–M15):** the Godot test harness + `game_tests` CI; the IP guard (merge, tip-tree, and region-agnostic prefixes); vendored `godot-sqlite` v4.4 + the real SQLite engine; pinned-TLS pairing and sync; the `sync_e2e` CI workflow.
- **Pass 13 fixes (M16–M20):** F34 real `bodyFix`; F33 re-pair; F32 `ERROR storage`; F31 legacy-import failure closes the database; F29 runner-level save snapshot; F30 evil-merge self-tests.
- **Pass 15 build (M21–M24):**
  - **F38:** `tools/memguard.py`, its budgets, 7 tests, and its wiring into the runner, `sync_e2e.py`, and all workflows. F41 refines it; don't rewrite it.
  - **F35:** an unreadable old save is marked as handled.
  - **F36:** *Scout here* uses `currentFix()`.
  - **The slice-1 plan:** amended in pass 16; the amended plan is the contract.

## 11. Accepted equivalents — do NOT "fix" these back
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so staged-but-uncommitted files are still checked.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than the spec; keep it.
- **`relocation_manager.gd`** "nearest-revealed-tile snapping" is done as a minimal-circle reveal plus placement — the same guarantee as BFS.
- **`os_location_source.dart:25`** — `nativeVisits()` returns `null`; native visits are an optional hint.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check; the proof is the runner-level snapshot.
- **The legacy import uses the same `ON CONFLICT` upserts** as live writes.
- **`SyncServer.configure_identity()` and `create_dispatcher()`** are dependency-injection seams, not test hooks in the production path.
- **The dispatcher accepts an integral float `seq`/`tsUtcMs`** (Godot's JSON parser returns floats).
- **`main.tscn` instances the pairing screen directly** until the map view exists (Item 9) and a menu exists (Phase 9).
- **QR codes use ECC level M.**
- **`_fail_legacy_import(reason)`** is shared by statement failures and count mismatches.
- **`buildBatchPayload` uses `"bodyFix": ?bodyFix`** to omit the key.
- **PAIR rejects malformed frames with `ERROR protocol`** and doesn't consume the code.
- **Memguard case 5 proves itself in-test:** it reruns with `allow_rss_check=False` and expects exit 0, instead of a scratch branch. That is an equivalent falsification.
- **`_triggerManualScout` clears existing SnackBars** before each message.
- **`COMPRESSION_DEFLATE` reads PBF's zlib blobs** — Godot's deflate mode accepts zlib-wrapped streams (the spike's node counts confirm it).
- **The slice-1 plan uses `index-v1.json` only** (it carries the download URLs too); `index-v1-nogeom.json` isn't needed.

## 12. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever.** Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache through `asset_db` only. **The companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12): **649 species, Gen 1–5, Black/White only** (Decision 10 = B). **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5. No hidden abilities in v1. Gen 6+ permanently out of scope.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell`, `place_node`, and `visit_log` (+ the body position). When bag, party, PC box, or Pokémon tables are added, extend the forbidden tokens in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist, and the PC refuses any coordinate finer than 3 decimals.
- **The grid is Web Mercator, implemented once** in `game/world/grid.gd` (F42). Cells are 256 WM-m, and gameplay distances are ground metres. Never add another projection formula — the lint rule enforces it.
- **The demo never touches the real save or identity** (plan §1). Tests never touch the human's demo profile.
- **Memory** (`design_memory_and_resources.md`): heavy work is bounded by construction, admitted only when there's room, and watched while it runs. When memory runs short it is paused or stopped cleanly, never left for the OS to kill. Budgets are measured, never lowered by `measure` without `--replace`.
- **Map data is fully offline** (Decision 13 = C): whole regional files the player confirms, read locally. **Never** add Overpass or any request naming a place, cell, or bounding box. `© OpenStreetMap contributors` is always shown. All HTTP lives in `map_fetcher.gd`.
- **The converter gate's rule** (Washington ≤ 30 min and ≤ 1 GiB, else STOP and file a decision) decides the converter — not the pass-15 skim.
- **Every location the phone reports is a real observation** — `bodyFix` and *Scout here* use real, fuzzed fixes stamped with the fix's own time (F34, F36).
- **Sync security** (Decision 11): TLS with a pinned self-signed certificate plus a device token; `withTrustedRoots: false` and a post-connect re-check; never hand-roll crypto. One paired phone per PC; re-pairing never deletes history. ACK means success; every failure is an `ERROR` frame with a code.
- **Storage** (Decisions 6–7): SQLite only, bound parameters only. **The v1 DDL is frozen**; every change is a §B6 migration. A failed import closes the database; an unreadable old save is marked as handled (F35). The vendored add-on changes only by documented local patch (F40).
- **Pillar rules:** fast travel = the phone's position at sync time; the PC box is reachable only within `baseAccessMeters` (ground metres); healing only at home; blackout drops the bag, never Pokémon; the map and Pokédex always persist.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot 4.3 (PC) + Flutter (companion). No Steam, no monetization.
- **Deliberate values:** the capture settings (accuracy `medium`, 25 m, 2 min) are battery decisions; the `tuning.json` values are balance decisions.

## 13. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, setup | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Phases 0–1 build steps, v1 DDL, TLS sync protocol, Godot test-harness contract | `docs/implementation_plan_foundation.md` |
| **Slice 1 of world generation (the map preview)** | `docs/implementation_plan_world_generation.md` |
| The Black/White ROM, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types, damage, catching, party, PC, blackout | `docs/design_creatures_and_battles.md` |
| Spawn zones, ghost share, levels, haunted zones, legendaries | `docs/design_encounters_and_haunted_zones.md` |
| Exploring sites, familiarity, healing scarcity | `docs/design_expeditions_and_survival.md` |
| Items by place, bag, home safehouse | `docs/design_resources_and_base.md` |
| Visits → tiles, tall grass, landmarks, the grid's role | `docs/design_world_generation.md` |
| Schemas, storage, **the Web-Mercator grid (§2)** | `docs/design_game_state_and_models.md` |
| Travel, clock, fast travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync | `docs/design_companion_and_sync.md` |
| Original vs ROM-sourced art | `docs/design_art_direction.md` |
| Privacy | `docs/design_privacy_and_location.md` |
| Memory guards, budgets, pause/resume | `docs/design_memory_and_resources.md` |
| Decisions, findings, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md / implementation_plan_*.md sections it names.
            Specs are decisions.
2 PLAN      Building a phase or slice with no approved implementation_plan_*.md? Write one
            FIRST and PAUSE for human review. (Slice 1 is approved: Decision 14 = A.)
3 IMPLEMENT Exactly as written, on a branch. Honor §12 and the standing constraints —
            above all: no Nintendo content; no test touches the real save, identity, or
            demo profile; one grid (grid.gd); never force-push main.
4 VALIDATE  This item's validation (run the falsifier against the OLD code first where
            the item says so), then the full §1 battery — on the Mac with GODOT_BIN once
            Item 1 lands — then confirm every workflow on GitHub (`gh run view <id> --log`),
            Linux and macOS. Say what ran, and where.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, a gate's rule says STOP, or you'd need a
            ROM you don't have → STOP. File in ongoing_general_errors.md with options.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design
            doc whose behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 0 (F42)** — one Web-Mercator grid; `grid_test` falsifiers proven on a scratch branch; the lint rule forbids private projections; 12/12 in CI.
- [ ] **Item 1 (F40)** — SQLite loads on macOS; the macOS CI job is green (and red with the plists reverted); the local Mac battery **executes** the game tests.
- [ ] **Item 2 (F41)** — the waiting line prints; `measure` is guarded and raise-only; the doctor check is one-directional; 10 memguard cases; Mac budgets measured.
- [x] **HUMAN: Decision 14 answered — A** (2026-10-10): build the full map preview.
- [ ] **HUMAN: real-device sync gate passes** (§2, after Items 0–1). **Closes Phase 1.**
- [ ] **HUMAN: D3 device soak run.** **Closes Phase 0.**
- [ ] **Slice 1:** Items 3–10 are delivered with their proofs; the converter gate passed (or a decision was filed and the slice STOPPED); the human was told how to try it; **paused for feedback**.
- [ ] **When a Black/White dump is supplied:** Item 11 — verify markers resolved, `implementation_plan_rom_importer.md` written, preview shown, **paused for review**.
- [ ] The full §1 battery and every CI workflow (Linux and macOS) are green.

**When all of the above that apply are checked: this build's queue is empty. Do NOT invent work.** Legitimate triggers for more:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the §1 battery or any CI workflow regressing;
- a §8 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
