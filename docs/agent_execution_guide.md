# Agent Execution Guide — Active Build: Map Fixes and a Real-Data Proof (F43–F47, F50), then Slice 2 "Pokémon Look" once Decisions 17 and 19 Are Answered (verified 2026-10-19, pass 17)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been, **in the USA** (Decision 16).
- **Pokémon content** comes from a ROM **the player supplies**, read on their own machine (the PokeMMO model).
- **Scope:** all **649 Pokémon of Generations 1–5**. **Black/White** supplies all data **and all sprites** (Decision 10 = B).
- **No commerce:** no Steam, no sales.

**Where things stand.**
- **The foundation is built and runs in CI:** background capture, a real SQLite save, pinned-TLS pairing and sync, and the memory guard.
- **Slice 1 of the map — the neighbourhood preview — is built.** Pass 17 verified it: 19/19 game tests on Linux, macOS, and the human's Mac, and the source matches the plan for most of it. But pass 17 also found:
  - **F43** — the map is drawn upside-down: north is at the bottom.
  - **F44** — the "Unmapped" download chip is never wired up in the running game.
  - **F45** — the real download can't work (Geofabrik redirects, and the client doesn't follow redirects). It would also hold the whole file in memory, freeze the window, and convert the entire state on the PC.
  - **F46** — whole neighbourhoods are painted as park.
  - **F47** — the frame-time number came from a headless run, not a rendered frame.
  - **F50** — the map view loads test map stores in every profile.
  - **The image shown to the human as proof was not made by the game.** Their Mac has no demo profile, no map store, and no route file.
- **The human rejected the look.** In their words, the map "looks nothing like a pokemon game map". They want a Pokémon-guidebook look and "a massive map … the only way to true complete the game is to travel", and they narrowed the world to the USA. Three decisions follow, all in `docs/ongoing_general_errors.md`:
  - **Decision 17** — what the walkable map is built from (the important one);
  - **Decision 18** — how travel gates completion (shapes slice 3, not this build);
  - **Decision 19** — where the tile art comes from for now.

  The draft plan for the recommended answers is `docs/implementation_plan_world_generation_slice2.md`.

**What is approved for build right now: Items 0–3** (§2). They fix what is broken in every possible answer to the decisions, and end by showing the human what the game *actually* draws of their area today.

**Items 4–9 (slice 2) are gated.** Start them only when `ongoing_general_errors.md` shows **Decision 17 = A** and Decision 19 answered (§7 has the gate check). Item 10 waits on a ROM.

**What NOT to touch:**
- §11 — already delivered;
- §12 — accepted equivalents;
- §13 — intentional decisions.

§10 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string here and in the docs it points to is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work:** **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds`, sprites, text banks, or stat tables, not even in a fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, through `TENTH_SPRING_ROM_BW`, which points **outside** the repo (`design_rom_asset_pipeline.md` §8).
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Work on a branch, get all workflows green, then fast-forward `main`. Every pass since 14 has done exactly this — keep doing it.
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the identity folder `user://sync_identity/`;
   - the human's demo profile `user://demo/` (including `user://demo/map_data/` after Item 2).

   Tests use `user://test/…`.
5. **The human's location never enters the repo — and that includes place names.**
   - Never commit `.gpx` routes, demo saves, map stores, or screenshots of their area.
   - **Never write the name of their town, neighbourhood, or streets, or any coordinates of where they live or walk** — not in docs, code, tests, commit messages, or CI logs. The repo is public, and a town name says where someone lives.
   - Keep all of it in `~/tenth_spring_private/`, outside the repo. Tests use made-up coordinates near (0.01, 0.01) — open ocean.
6. **Heavy commands go through the memory guard:** `python3 -I tools/memguard.py run <step> -- <command>` (`design_memory_and_resources.md` §2). `test_runner.py`, `sync_e2e.py`, and `demo_import.py` already wrap themselves.
   - Never run two heavy commands at once, and never leave one running beyond the session.
   - If a step exits **75** (no room) or **76** (stopped for memory), report it — don't retry in a loop.
   - The Mac is shared with other projects that use tens of GB. **Never** deliberately starve it to test the guard; use the fake-reader tests.
7. **Godot on the human's Mac** is at `/Applications/Godot.app/Contents/MacOS/Godot` (4.3-stable), **not** on `PATH`. Set `GODOT_BIN` to it; `test_runner.py`, `sync_e2e.py`, and `demo_import.py` honour it.
8. **Download nothing** except what an item names:
   - **Item 1:** nothing in tests (fake transports). The manual check may fetch Geofabrik's `index-v1.json` and send one `HEAD`.
   - **Item 2:** the human's region file — the URL the game's own region choice returns for their demo save — and its `.md5`, into `~/tenth_spring_private/downloads/`.

   Never commit a download.
9. **Every change leaves the §1 battery and all CI workflows green** — that is the regression bar.
10. **Anything touching capture, battery, or cross-device sync requires a real-device check** before Phase 1 is declared closed (§2, HUMAN actions).
11. **The golden invariants (§13) stay green, always.**
12. **Detailed behaviour lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
13. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
14. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Name the machine (Linux CI, macOS CI, the human's Mac). Game-side claims count as executed only when a run printed the `PASS` lines (`gh run view <id> --log`, or your local transcript).
15. **Proof images come only from the game.** A picture shown to the human as "this is what the game draws" must be saved by the game's screenshot harness (Item 3) from real data, with the exact command in the commit body or your message. Never present a mock-up, a hand-made render, or another tool's output as the game's (M31).

---

## 1. Verified baseline (run 2026-10-19 in this session, HEAD `78e6f23`)

| Battery | Where | Result |
|---|---|---|
| `cd companion && flutter analyze` | Mac, local | **No issues found** |
| `python3 -I ../tools/memguard.py run flutter_test -- flutter test` (in `companion/`) | Mac, local | **37 passed, 2 skipped** — `sync_e2e_test` and `demo_import_test`, which run only through their tools |
| `GODOT_BIN=… python3 game/tests/test_runner.py` | Mac, local | **Executed.** Hook check, IP guard + self-tests, F22 audit, memguard tests (10), vendored SHA-256, static lint (F19 SQL rule, F42 projection rule, HTTP isolation rule) → **19/19 `PASS`**, `[REAL SAVE CHECK OK]` |
| `GODOT_BIN=… python3 -I tools/sync_e2e.py` | Mac, local | **Executed, green.** `E2E_SENT rows 14` → `E2E_STATE visit_log 14, last_applied_seq 14, map_cell 3, place_node 1` |
| `python3 -I tools/demo_import.py --gpx <in-repo fixture>` | Mac, local | Exit **2**, before memguard starts (Item 6's falsifier) |
| `python3 -I tools/memguard.py doctor` | Mac, local | 64 GiB; available 37.1 GiB (58%), floor 6.4 GiB, pressure 1; `Cross-check OK` |
| CI `game_tests` | run `39367963628` | **Executed, green — 19/19 on Linux and on macOS**, `[REAL SAVE CHECK OK]` on both |
| CI `Public-Repo IP Guard` | run `39367963620` | **Green** |
| CI `sync_e2e` | run `39367963563` (Linux) | **Executed, green** |
| The map drawn from **real** map data | — | ⚠️ **NEVER RUN.** No demo profile or map store has ever existed on the Mac. Item 3 does it for the first time. |
| The in-game download against Geofabrik | — | ⚠️ **NEVER RUN** — fake transports only. F45(a) shows it would fail. |
| `FRAME_P95_MS` in a windowed run | — | ⚠️ **Never measured** (F47). |
| Real-device sync gate | phone + PC | ⚠️ **NOT RUN** — human. **Ready now.** |
| D3 device soak | 8 h background carry | ⚠️ **NOT RUN** — human (Decision 5 = A). Ready any time. |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 0 | **F43 — north up** | Every later picture depends on it, and it's small. |
| 1 | **USA scope + download mechanics** (Decision 16; F44; F45 a, b, c, e) | Its region choice tells Item 2 which file to fetch; the whole-world index must never be used again. |
| 2 | **Clip conversion, coverage, F46, F50 — and the human's demo save** | Needs Item 1's region choice. Produces the data Item 3 photographs, and its timings feed the Decision 15 re-ask. |
| 3 | **Screenshot harness + the honest baseline** (F47) → show the human | Needs Items 0–2. Ends the ungated work. **If Decisions 17 and 19 are still blank, stop here: the queue is empty.** |
| 4 | ⛔ **Slice 2: scale + map store v2** (plan §1–2) | Gated. Everything in slice 2 reads store v2. |
| 5 | ⛔ **Slice 2: synthesis part 1 — terrain, water, lines, vegetation** (plan §3, §4.0–4.1) | Gated. Needs store v2. |
| 6 | ⛔ **Slice 2: synthesis part 2 — buildings, fallback houses, signs** (plan §4.2–4.4) | Gated. Builds on part 1's grid; building placement checks the tiles part 1 painted. |
| 7 | ⛔ **Slice 2: placeholder atlas** (plan §5) — or map the human's tileset | Gated. Only the renderer needs it. If Decision 19 = B/C and no tileset has arrived, stop before this item. |
| 8 | ⛔ **Slice 2: renderer v2** (plan §6) | Gated. Needs the atlas and both synthesis parts. |
| 9 | ⛔ **Slice 2: proof** (plan §7) → **PAUSE** | Gated. The human judges the look. |
| 10 | **Phase 2 — ROM spike + importer plan** | ⛔ Waits on the human supplying a Black/White dump. |

**▶ HUMAN actions:**
- **Answer Decisions 17, 18, and 19** in `docs/ongoing_general_errors.md` (fill each `Your selection:`). 17 and 19 unblock slice 2.
- **For Items 2–3, a route of your area.** Either make a `.gpx` (outside the repo) and tell the agent its path in chat, or just tell the agent in chat which town or neighbourhood to draw a route through. **Never put either in the repo.**
- **Real-device sync gate — ready now.** It closes Phase 1. Install the companion on your iPhone (README → *Install the companion on an iPhone*), and start the PC game from `/Applications/Godot.app` with `game/project.godot`.
  1. **Pair and report:** real phone + PC on one Wi-Fi network. Pair by QR — this also proves a real phone can scan the PC's QR. Walk an errand, then *Report to PC*; the rows appear on the PC.
  2. **Wireshark:** filter `tcp.port == 7350`. The capture shows only TLS records, and searching it for the home's 3-decimal latitude finds nothing.
  3. **iOS:** the local-network prompt appears on the first report.
  4. **Address change:** renew the PC's DHCP lease → *Report to PC* shows the unreachable message. Re-scan → the next report succeeds **without** re-pairing.
  5. **Second phone:** pair a second phone → the first phone's next report shows the unpaired message. Re-scanning on the first phone pairs it again.
- **Any time:** the D3 device soak (closes Phase 0).
- **To unblock Item 10:** a Black or White (USA) dump from your own cartridge (`TENTH_SPRING_ROM_BW`).

Deferred (trigger-gated, **do not start**): see §9.

---

## 3. Item 0 — F43: north up

**What this means for the user:** today the game would draw their town upside-down — a bay to the north would appear below the town.

**Contract:** `implementation_plan_world_generation.md` §7.1a.

### The gap
Web-Mercator `y` grows north; Godot's screen `y` grows down. `game/world/map_view.gd`:
- `:365` and `:389` place cell `(cx, cy)` at screen row `cy·16`;
- `:369` and `:383` add the buffer row `ty`, which counts from the cell's **south** edge;
- `:225` (`focus_on_cell`) and `:292-293` (culling) use the same unflipped `y`.

### Implementation
1. Add `func _screen_tile(cx: int, cy: int, tx: int, ty: int) -> Vector2i`, returning `Vector2i(cx * 16 + tx, (-cy - 1) * 16 + (15 - ty))`. Use it for both layers in `_render_cell` and `_unrender_cell`.
2. `focus_on_cell`: `Vector2((cx + 0.5) * CELL_SIZE_PX, (-cy - 0.5) * CELL_SIZE_PX)`.
3. Culling: columns unchanged. Compute rows `r0 = floor(top / 256)` and `r1 = floor(bottom / 256)`, and iterate `cy` from `-r1 - 1` to `-r0 - 1`.
4. `design_game_state_and_models.md` §2: add one line — "On screen, y = −northing: cell (cx, cy) is drawn at screen cell row −cy − 1 (`implementation_plan_world_generation.md` §7.1a)."

### Validation — add to `game/tests/map_view_test.gd`
Write a test store into `user://test/map_data/` with one `water` polygon covering store `y ∈ [8, 16]` (the **north** half) of cell (0, 0), and reveal cell (0, 0).
- **(a) Falsifying:** `WorldTileMap.get_cell_atlas_coords` at screen tile `(3, −16 + 2)` (top half) is `(5, 0)` (water), and at `(3, −16 + 13)` (bottom half) it is `(1, 0)` (terrain). The current code gives the reverse.
- **(b) Falsifying:** with cells (0, 0) and (0, 1) both revealed, every screen row of (0, 1) is smaller (higher on screen) than every row of (0, 0).
- **(c)** `focus_on_cell(0, 1).y < focus_on_cell(0, 0).y`.
- **Run (a)–(c) against the old code first** and paste the failures in the commit body. Then 19/19 `PASS` plus the new assertions, on both CI operating systems.

### Blast radius (same commit)
`game/world/map_view.gd` · `game/tests/map_view_test.gd` · one line in `design_game_state_and_models.md` §2 · F43 → Resolved.

---

## 4. Item 1 — USA scope and download mechanics (Decision 16; F44; F45 a, b, c, e)

**What this means for the user:** today, clicking the map's download chip does nothing. If it were wired, it would fail on Geofabrik's first redirect, then freeze the game while holding a several-hundred-MB file in memory. And a trip abroad would offer foreign maps.

**Contract:** `implementation_plan_world_generation.md` §5.1a and §5.4a; `design_world_generation.md` §3 and §5.

### The gap (`game/world/region_import/map_fetcher.gd` unless noted)
- `select_region_for_latlon` (`:95`) chooses from the whole-world index.
- `_real_http_request` (`:388`) follows no redirects and never checks the status code (`:428`).
- `GET` accumulates the whole body in memory (`:441`).
- `download_and_install_region` (`:147`) runs synchronously on the caller's thread — the main thread, from the dialog.
- `configure_unmapped_region` has no caller outside `region_select_test.gd:142`, so `_pending_region` stays empty and `open_download_dialog` (`map_view.gd:443-444`) does nothing.

### Implementation
1. **US filter, per-cell regions, the chip's region choice, beyond the map, and the return shape** — §5.1a exactly.
2. **Redirects (≤ 5, Geofabrik only), status checks, streaming with `read_chunk_size = 1048576` and `max_buffered_bytes`** — §5.4a rules 1–3.
3. **`start_install` / `cancel_install` on a `Thread`**, the progress signals, and `RegionConverter.cancel_requested` — §5.4a rules 4–5. Keep `download_and_install_region` synchronous for tests; the thread calls it.
4. **`AttributionUI/InstallPanel`** with the exact strings in §5.4a rule 6.
5. **Wiring (F44):** every 2.0 s, off the main thread, per §5.4a rule 7.
6. **Extend the fake transport:** each response carries `{code, headers, chunks}` so tests can script redirects, statuses, and chunking.
7. **Leave what gets installed alone** — the whole-region conversion stays (F45(d); Decision 15 re-ask, §9).

### Validation
- **US filter (falsifying):** a fake index where the test point lies inside three features:
  - a US state (URL under `/north-america/us/`);
  - a larger `us-west` grouping (URL `…/north-america/us-west-latest.osm.pbf`);
  - a **smaller** non-US feature (URL under `/north-america/canada/`).

  The new code picks the US state; today's code picks the Canadian one. Also: `norcal` nested inside `us/california` → `norcal`.
- **Beyond the map:** a point only inside the Canadian feature → `{"beyond_the_map": true}`; in a scene, the chip reads exactly `Beyond the map — Tenth Spring covers the USA` and ignores clicks.
- **Redirects (falsifying):**
  - `HEAD …-latest.osm.pbf` → 307 to `…-261018.osm.pbf` → 200 with `Content-Length: 364412180` → the chip reads `(348 MB)`. Today it reads the fallback text.
  - A redirect to `https://example.com/…` → error `Unexpected redirect to example.com`.
  - 404 → error `HTTP 404`, and no `.part` file is left.
- **Streaming (falsifying):** a fake `GET` delivering 40 chunks of 1 MiB. `max_buffered_bytes ≤ 1048576`, and the `.part` file has grown to k MiB when chunk k+1 arrives (probe it from the transport). Today's code holds 40 MiB.
- **Threading:** with a fake transport that sleeps 200 ms per chunk, `start_install` returns in < 50 ms. Progress arrives in order — `download` → `verify` → `convert` → `install_finished`. Cancelling after chunk 3 finishes with `{"ok": false, "error": "Cancelled"}` and leaves no `.part` or `.tmp.db`.
- **Wiring (falsifying, scene test):** a test save with one revealed cell, no store, and a fake fetcher → within 3 s of frames, the chip reads `Unmapped Region — <fake name> (<N> MB)`. Today it stays `Unmapped — no map data installed for this area`.
- The HTTP-isolation lint still passes, and all workflows are green.
- **Manual check — runs in Item 2,** once the human's demo save exists: the chip names their region with its real size (which proves redirects work), and **Not now** downloads nothing. **Don't click Download** — it would convert the whole state (F45(d)).

### Blast radius (same commit)
`map_fetcher.gd` · `region_converter.gd` (cancel flag) · `map_view.gd`/`.tscn` (wiring, `InstallPanel`, beyond-the-map chip) · `region_select_test.gd` · `map_view_test.gd` · F44 → Resolved · F45 → (a), (b), (c), (e) resolved; (d) open · Decision 16 marked "built".

---

## 5. Item 2 — Clip conversion, coverage, F46, F50, and the human's demo save

**What this means for the user:** their own area can be put on the map in minutes instead of over an hour, and empty fields and whole neighbourhoods stop showing up in the wrong colours.

**Contract:** `implementation_plan_world_generation.md` §5.5.

### The gap
- No way to convert part of a region — Washington took ~61 min whole (§5.3).
- "Mapped" today means "the cell has features" (`map_view.gd`, `_render_cell`), so an empty field or open water inside a converted region shows as unmapped grey.
- F46: `tile_synth.gd:75`, `region_converter.gd:772`.
- F50: `map_view.gd:176-177`.

### Implementation
1. **Converter:** the pre-pass and the Pass 1 rule (§5.5 rules 2–4), the coverage keys (rule 5), and the memory-pause watchdog in the pre-pass (rule 9).
2. **Map view:** the coverage semantics (rule 6), and profile-local map data (rule 8 — `ProfilePaths.map_data_dir`).
3. **F46** (rule 7). Report whether the canonical dump hash and the tile golden hash change, old → new.
4. **`tools/map_convert.py`** gains `--clip-to-save <save>`, `--margin-cells <m>` (default 6), and `--print-region <save>`. The last one runs the game's own `map_fetcher.select_region_for_cells` on the save's revealed cells and prints `region: <id> <pbf_url> <md5_url>` — to your local console only.
5. **Build the human's demo save and map** — local only; nothing here is committed:
   1. **Route:** use the human's `.gpx` from the path they give in chat. If they named an area instead, write a GPX with 4–8 `<wpt>` at public landmarks there (stations, town squares, parks, a cemetery) and a `<trk>` joining them along main streets. Save it as `~/tenth_spring_private/demo_route.gpx`. **Never their home.**
   2. `python3 -I tools/demo_import.py --gpx ~/tenth_spring_private/demo_route.gpx` → `Imported <N> scout points into demo profile.`
   3. `python3 -I tools/map_convert.py --print-region user://demo/tenth_spring.db`, then `curl -L` that `.osm.pbf` and its `.md5` into `~/tenth_spring_private/downloads/`, and check the MD5.
   4. `python3 -I tools/memguard.py measure map_convert_clip -- python3 -I tools/map_convert.py --pbf <file> --out-dir user://demo/map_data --clip-to-save user://demo/tenth_spring.db`
   5. Add a row to plan §5.3, "Clip — <W> × <H> cells (the human's area)", with per-pass times, peak RSS, feature counts, and store size. **Don't record the region's name, URL, or file size in the repo.** Target: ≤ 10 min and ≤ 1 GiB. Report the result either way — this is a developer tool, so missing the target is not a STOP; it feeds the Decision 15 re-ask.
   6. **Item 1's manual check:** `"$GODOT_BIN" --path game -- --demo`. Pan to an edge of the clip rectangle, where revealed cells exist outside it if the route runs past it. The chip names the region and its real size, and **Not now** downloads nothing. (If every revealed cell is inside the rectangle, run this check with `--margin-cells 0` on a scratch copy of the store instead.)
   7. Keep the region file until slice 2 is done (Item 4 re-converts it to store v2). Delete it at the end of Item 9 — or now, if slice 2 is not approved.

### Validation
- **Equivalence (falsifying):** clipping the synthetic fixture to a rectangle that covers all of it gives a canonical dump hash **identical** to the unclipped run.
- **Partial clip:** a rectangle covering only the fixture's west half → the east-only building is absent; the road crossing the middle is present and whole; the lake is present exactly when one of its member ways has a node inside.
- **Empty clip:** a rectangle in empty ocean → a store with zero features, its coverage recorded, exit 0.
- **Coverage (falsifying):** a mapped cell with no features renders terrain `(1, 0)`, not unmapped `(6, 0)`; a cell outside every coverage renders `(6, 0)`. Today the first case renders `(6, 0)`.
- **F46 (falsifying):** a `residential` polygon renders `TILE_TERRAIN`, not `TILE_PARK`.
- **F50 (falsifying):** with a store in `user://test/map_data/`, a normal-profile map view loads **zero** stores. Today it loads one.
- Battery and all workflows green.

### Blast radius (same commit)
`region_converter.gd` · `map_store.gd` (if coverage helpers live there) · `game/scenes/map_convert.gd` · `tools/map_convert.py` · `map_view.gd` · `profile_paths.gd` (+ `profile_paths_test.gd`) · `tile_synth.gd` · `region_import_test.gd` · `map_view_test.gd` · `tile_synth_test.gd` (golden, if it changed) · `memguard_budgets.json` (`map_convert_clip`) · plan §5.3 row · F46 and F50 → Resolved.

---

## 6. Item 3 — The screenshot harness, and the honest baseline (F47)

**What this means for the user:** for the first time they see what the game actually draws of their own area — made by the game, not imagined.

**Contract:** `implementation_plan_world_generation.md` §7.4.

### The gap
There is no way to capture the game's view. `FRAME_P95_MS` comes from a headless test (F47). The last "proof" image wasn't game output (M31).

### Implementation
1. `main.gd` screenshot mode: argument parsing and refusals (§7.4 rules 1–2); open the map view without the sync server or the pairing screen (rule 3).
2. `map_view.gd`: `pending_cell_count()`, the frame wait, the PNG save, and the `SCREENSHOT_SAVED` / `FRAME_P95_MS` lines (rule 3).
3. `tools/demo_screenshot.py` (rules 4–5), with memguard step `demo_screenshot` — measure it on its first run.
4. Automated tests: `game/tests/screenshot_args_test.gd` (add it to `EXPECTED`) for the in-repo path, unknown zoom, and `--headless` refusals; and a Python test that the wrapper refuses an in-repo `--out-dir` with exit 2.

### Validation
- **Falsifying:** an in-repo `--screenshot` path exits 2 and opens no window.
- **On the human's Mac — the real capture:** `python3 -I tools/demo_screenshot.py --out-dir ~/tenth_spring_private/screens --zoom 1 --zoom 3` writes two PNGs and prints `SCREENSHOT_SAVED` and a windowed `FRAME_P95_MS`.
  - Put the frame time in the commit body and in plan §7.3; the target is ≤ 16.6 ms. F47 → Resolved.
  - State plainly that CI does not run the capture.
- **Show the human both screenshots,** and say it plainly: *this is slice 1 as built, now north-up, on your real streets — flat squares. Slice 2 is what changes the look; it starts once Decisions 17 and 19 are answered.*
- **Then:** if Decision 17 = A and Decision 19 is answered, continue to Item 4. Otherwise **stop — the queue is empty** (Definition of Done).

### Blast radius (same commit)
`main.gd` · `map_view.gd` · new `tools/demo_screenshot.py` and its test · new `screenshot_args_test.gd` + `EXPECTED` · `memguard_budgets.json` · plan §7.3 numbers · F47 → Resolved.

---

## 7. Slice 2 — "Pokémon look" (Items 4–9) — ⛔ gated

**Gate check — do this before Item 4.** Open `docs/ongoing_general_errors.md`:
- **Decision 17 ≠ A:**
  - **B** → STOP. Write `implementation_plan_world_generation_slice2.md` anew for towns and routes, at the same depth, and pause for review.
  - **C** → STOP. File a short note and end.
  - **Blank** → STOP; the queue is empty.
- **Decision 19 blank** → STOP and ask.
- **Decision 19 = B or C with no tileset supplied yet** → do Items 4–6, then stop before Item 7.

**What this means for the user:** their real streets, drawn the way a Pokémon guidebook draws a town — paths, roofed buildings with doors and name signs, tree-bordered parks full of tall grass, shorelines, graveyards — under the fog of where they haven't been.

**The contract is `docs/implementation_plan_world_generation_slice2.md`.** Implement its sections exactly; this guide adds only order, proof, and blast radius.

**Rules for every slice-2 item:**
- Every lat/lon → cell/tile conversion goes through `grid.gd`.
- Add new Godot tests to `EXPECTED`.
- Tests use the synthetic fixture only.
- Never write the human's place names anywhere in the repo.
- Re-measure memguard budgets for any step that got heavier.

### 7.1 Item 4 — Scale and map store v2 (plan §1, §2, §8 fixture)
- **Build:**
  - `Grid.TILE_WM = 8.0`; `MapStore.GEOM_UNIT_WM`; `tuning.json` and `config.gd` → 8.0;
  - **first check that no real save exists** (plan §1);
  - the kind tables, the bridge suffix, and the exclusions (§2.1–2.2); anchoring (§2.3); sea flags (§2.4); schema v2 and the skip log;
  - fixture v2 via the generator, with the byte-for-byte regeneration test.
- **Prove:**
  - §8's store assertions;
  - the regenerated fixture is byte-identical;
  - **Falsifying:** a coastline-reversed copy of the fixture (from a generator flag `--reverse-coastline`, used only by the test) flips the sea flags.
  - Then re-convert the human's area to v2 with clipping (local only) and report the time.
- **Blast radius:** `grid.gd`, `config.gd`, `tuning.json`, `map_store.gd`, `region_converter.gd`, the generator + its test + the fixture, `region_import_test.gd` (new hash), `design_game_state_and_models.md` §2, `master_implementation_plan.md` (`tileMeters = 8`).

### 7.2 Item 5 — Synthesis part 1 (plan §3, §4.0, §4.1 steps 1–4, 6–8, 10)
- **Build:** `game/world/tile_synth/tile_synth2.gd` — the working grid, FNV-1a hashing, value noise, land cover, sea and coast, lines with crossings, parks, forests, cemeteries, scatter, and masks. No buildings yet.
- **Prove** (`tile_synth2_test.gd`): §8 (c), (e), (f), (g), (h), plus a golden hash for this stage. The golden changes in Item 6 — say so in both commits.
- **Blast radius:** the new module and test, `EXPECTED`.

### 7.3 Item 6 — Synthesis part 2 (plan §4.2–4.4, §4.1 steps 5 and 9)
- **Build:** templates, placement, the skip rule, roof colours, door paths, fallback houses, signs, and flowers.
- **Prove:** §8 (a) — the final golden, identical on the Linux and macOS jobs — and (b), (d), (i), (j).
- **Blast radius:** `tile_synth2.gd`, its test.

### 7.4 Item 7 — Placeholder atlas (plan §5) — or the human's tileset
- **Build:** `tools/gen_placeholder_atlas.py` → `placeholder_v1.png` / `.json` and `tenth_spring.gpl`. If Decision 19 = B or C, map the supplied art onto §3's classes and §5.2's JSON instead, after checking §2 of `design_art_direction.md` (the rip trap) with the human.
- **Prove:** regeneration is byte-identical; the JSON covers every `(class, variant)` the synthesizer can emit. Show the human the atlas PNG — it is original art, committed, and contains no location.
- **Blast radius:** the new tool, its test, the assets, the runner.

### 7.5 Item 8 — Renderer v2 (plan §6)
- **Build:**
  - the atlas TileSet; the `WorldKnown` / `WorldCleared` / `FogLayer` / `OverviewLayer` layers and the two shaders;
  - north-first placement; inward feathering; zoom steps `{1/16, 1/4, 1, 2}` and the overview sprites;
  - the 8 ms synthesis budget; LRUs of 1024 and 256; sign tooltips; `--preview-cleared`;
  - the screenshot harness's zoom list;
  - **delete `tile_synth.gd` and `tile_synth_test.gd`**, and remove `tile_synth_test` from `EXPECTED`.
- **Prove:** §8's `map_view_test` assertions, plus a windowed `FRAME_P95_MS` while panning at zoom 1 and at 1/16 on the human's area — report both against the 16.6 ms target.
- **Blast radius:** `map_view.gd`/`.tscn`, the shaders, the tests, `EXPECTED`, `design_art_direction.md` §3 and §5, `design_world_generation.md` §3, `design_memory_and_resources.md` §3.3.

### 7.6 Item 9 — Proof (plan §7) → PAUSE
- Capture the four screenshots from plan §7 with `tools/demo_screenshot.py` into `~/tenth_spring_private/screens/`, and show them to the human with `FRAME_P95_MS`.
- Delete the region download afterwards.
- **PAUSE.** The human judges the look. Their feedback — and Decision 18 — shape slice 3.

---

## 8. Item 10 — Phase 2: ROM spike + importer implementation plan

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

## 9. Deferred — trigger-gated, do NOT start
- **Decision 15 re-ask (map delivery).** Selected B (pre-converted stores) but never implemented, and its size estimate was wrong (`ongoing_general_errors.md`, Decision 15 status). **Trigger:** Item 2's clip measurement is recorded — the next verification pass re-asks it. **Never build or publish stores before it is answered.**
- **F45(d) — the in-game Download converts the whole state.** **Trigger:** Decision 15 re-answered.
- **F49 — memguard `run` logs a 0.0 peak for short steps.** **Trigger:** the next change to `tools/memguard.py` — take the first sample after 0.2 s, then every `POLL_SECONDS`.
- **Slice 3** — spawn zones, tall-grass encounters, ledges and terraces from USGS elevation, biomes, overgrowth by distance, and Decision 18's content. **Trigger:** the human approves slice 2 at Item 9's pause **and** Decision 18 is answered. Write `implementation_plan_world_generation_slice3.md` first, and pause.
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; the game treats home as one 256 WM-m cell. **Trigger:** the first commit that wires safehouse designation (Phase 3 onboarding).
- **mDNS auto-discovery (F27 d).** v1 finds the PC by remembered address plus QR re-scan. **Trigger:** the human reports that re-scanning is a real nuisance.
- **Session-start relocation (§B5) on game launch.** `relocation_manager.gd` is still not called. **Trigger:** Phase 4.
- **A Windows CI job.** The Windows `.dll`s are vendored but have never been loaded. **Trigger:** Phase 10 release prep, or the human playing on Windows.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.

---

## 10. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation (slice 1 built; slice 2 drafted; slice 3 later) · 4 Travel & time · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones & legendaries · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward — or any new slice of one — write its `implementation_plan_*.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9.

---

## 11. Already delivered — do NOT rework
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource` + fixtures, and the scout-ledger UI. The D3 code is done; its device soak is pending.
- **Early fixes:** F1, F2, F3, F5, F6, F8, F9, F11, F13, F17, F18, F21, F22.
- **Pass 12 build (M12–M15):** the Godot test harness + `game_tests` CI; the IP guard; vendored `godot-sqlite` v4.4 + the real SQLite engine; pinned-TLS pairing and sync; the `sync_e2e` CI workflow.
- **Pass 13 fixes (M16–M20):** F34, F33, F32, F31, F29, F30.
- **Pass 15 build (M21–M24):** F38 memguard, F35, F36, the slice-1 plan.
- **Pass 16 build (M25–M30), verified in pass 17 (M31):**
  - **F42** — one Web-Mercator grid; **F40** — SQLite on macOS + the macOS CI job; **F41** — memguard fixes;
  - **slice 1:** the demo profile, hand-drawn GPX replay, F37 corridor reveal, `demo_import.py`, the converter + map store + gate (Decision 15), slice-1 tile synthesis, the map view, and region selection/download.

  Items 0–2 *fix* the last two — they don't rewrite them. Slice 2 replaces slice-1 synthesis and rendering, by plan.

## 12. Accepted equivalents — do NOT "fix" these back
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so staged-but-uncommitted files are still checked.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than the spec; keep it.
- **`relocation_manager.gd`** "nearest-revealed-tile snapping" is done as a minimal-circle reveal plus placement — the same guarantee as BFS.
- **`os_location_source.dart:25`** — `nativeVisits()` returns `null`; native visits are an optional hint.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check; the proof is the runner-level snapshot.
- **The legacy import uses the same `ON CONFLICT` upserts** as live writes.
- **`SyncServer.configure_identity()` and `create_dispatcher()`** are dependency-injection seams, not test hooks in the production path.
- **The dispatcher accepts an integral float `seq`/`tsUtcMs`** (Godot's JSON parser returns floats).
- **`main.tscn` instances the pairing screen directly;** `main.gd` swaps in the map view when the save has revealed cells.
- **QR codes use ECC level M.**
- **`_fail_legacy_import(reason)`** is shared by statement failures and count mismatches.
- **`buildBatchPayload` uses `"bodyFix": ?bodyFix`** to omit the key.
- **PAIR rejects malformed frames with `ERROR protocol`** and doesn't consume the code.
- **Memguard case 5 proves itself in-test** (reruns with `allow_rss_check=False`) instead of on a scratch branch.
- **`_triggerManualScout` clears existing SnackBars** before each message.
- **`COMPRESSION_DEFLATE` reads PBF's zlib blobs** — Godot's deflate mode accepts zlib-wrapped streams.
- **The slice-1 plan uses `index-v1.json` only** (it carries the download URLs too).
- **`demo_import.py` re-runs itself under `memguard run demo_import`** when not already guarded, rather than requiring the caller to wrap it — the same guarantee as the plan's command line.
- **`ProfilePaths` also accepts `--demo-dir <path>` and `--demo-dir=<path>`** (both imply `--demo`) — a superset of the plan.
- **`map_fetcher.gd` uses `HTTPClient` directly,** not `HTTPRequest` — allowed by the HTTP-isolation rule.

## 13. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever.** Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache through `asset_db` only. **The companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12): **649 species, Gen 1–5, Black/White only** (Decision 10 = B). **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5. No hidden abilities in v1. Gen 6+ permanently out of scope.
- **Golden invariant 1 — real movement unlocks access, never cargo or creatures.** The sync ingest writes only `map_cell`, `place_node`, and `visit_log` (+ the body position). When bag, party, PC box, or Pokémon tables are added, extend the forbidden tokens in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — raw coordinates never persist or transit.** `companion/lib/capture/fuzz.dart` is the only place they exist, and the PC refuses any coordinate finer than 3 decimals.
- **The world is the USA** (Decision 16): regions are filtered by URL prefix (`…/north-america/us/`). Beyond-the-map cells render as fog, are never downloaded, and never count — but the ingest still stores them.
- **The grid is Web Mercator, implemented once** in `game/world/grid.gd` (F42). Gameplay distances are ground metres. **On screen, north is up** (screen y = −northing, F43) — fix orientation in the view, never by changing the grid.
- **The human's place names and coordinates never enter the repo** (standing constraint 5). **Proof images come only from the game** (standing constraint 15).
- **The demo never touches the real save or identity** (plan §1), and each profile reads only its own map data (F50). Tests never touch the human's demo profile.
- **Memory** (`design_memory_and_resources.md`): heavy work is bounded by construction, admitted only when there's room, and watched while it runs. When memory runs short it is paused or stopped cleanly, never left for the OS to kill. Budgets are measured, never lowered by `measure` without `--replace`.
- **Map data is fully offline** (Decision 13 = C): whole regional files the player confirms, read locally. **Never** add Overpass or any request naming a place, cell, or bounding box. `© OpenStreetMap contributors` is always shown. All HTTP lives in `map_fetcher.gd`, and **no network call runs on the main thread** (F45).
- **The converter gate's rule** (Washington ≤ 30 min and ≤ 1 GiB, else STOP and file a decision) decided the converter — not the pass-15 skim.
- **Every location the phone reports is a real observation** — `bodyFix` and *Scout here* use real, fuzzed fixes stamped with the fix's own time (F34, F36).
- **Sync security** (Decision 11): TLS with a pinned self-signed certificate plus a device token; `withTrustedRoots: false` and a post-connect re-check; never hand-roll crypto. One paired phone per PC; re-pairing never deletes history. ACK means success; every failure is an `ERROR` frame with a code.
- **Storage** (Decisions 6–7): SQLite only, bound parameters only. **The v1 DDL is frozen**; every change is a §B6 migration. A failed import closes the database; an unreadable old save is marked as handled (F35). The vendored add-on changes only by documented local patch (F40).
- **Pillar rules:** fast travel = the phone's position at sync time; the PC box is reachable only within `baseAccessMeters` (ground metres); healing only at home; blackout drops the bag, never Pokémon; the map and Pokédex always persist.
- **The phone is never a place to play.** **The world clock pauses when the game is closed** (except capped haunting catch-up). **Tile synthesis is deterministic.**
- **Stack:** Godot 4.3 (PC) + Flutter (companion). No Steam, no monetization.
- **Deliberate values:** the capture settings (accuracy `medium`, 25 m, 2 min) are battery decisions; the `tuning.json` values are balance decisions.

## 14. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, setup | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Phases 0–1 build steps, v1 DDL, TLS sync protocol, Godot test-harness contract | `docs/implementation_plan_foundation.md` |
| **Slice 1 of world generation** + its pass-17 amendments (§5.1a, §5.4a, §5.5, §7.1a, §7.4) | `docs/implementation_plan_world_generation.md` |
| **Slice 2 — "Pokémon look" (draft, gated on Decisions 17 and 19)** | `docs/implementation_plan_world_generation_slice2.md` |
| The Black/White ROM, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types, damage, catching, party, PC, blackout | `docs/design_creatures_and_battles.md` |
| Spawn zones, ghost share, levels, haunted zones, legendaries | `docs/design_encounters_and_haunted_zones.md` |
| Exploring sites, familiarity, healing scarcity | `docs/design_expeditions_and_survival.md` |
| Items by place, bag, home safehouse | `docs/design_resources_and_base.md` |
| Visits → tiles, tall grass, landmarks, **USA scope (§5)** | `docs/design_world_generation.md` |
| Schemas, storage, the Web-Mercator grid (§2) | `docs/design_game_state_and_models.md` |
| Travel, clock, fast travel, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, sync | `docs/design_companion_and_sync.md` |
| Original vs ROM-sourced art, the rip trap | `docs/design_art_direction.md` |
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
            FIRST and PAUSE for human review. (Items 0–3 are approved fixes. Slice 2 is
            approved only by Decision 17 = A.)
3 IMPLEMENT Exactly as written, on a branch. Honor §13 and the standing constraints —
            above all: no Nintendo content; none of the human's places in the repo; no test
            touches the real save, identity, or demo profile; one grid; never force-push main.
4 VALIDATE  This item's validation (run the falsifier against the OLD code first where
            the item says so), then the full §1 battery on the Mac with GODOT_BIN, then
            confirm every workflow on GitHub (`gh run view <id> --log`), Linux and macOS.
            Say what ran, and where. Pictures of the map come only from the harness.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, a gate says STOP, a decision is blank, or
            you'd need a ROM you don't have → STOP. File in ongoing_general_errors.md with
            options.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design
            doc whose behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body.
```

## Definition of Done (this build)
- [ ] **Item 0 (F43)** — north is up; the falsifiers failed on the old code and pass now.
- [ ] **Item 1 (Decision 16, F44, F45 a/b/c/e)** — US-only regions; beyond-the-map chip; redirects, status checks, streaming, threaded install with progress and cancel; the chip wired in the running game.
- [ ] **Item 2 (F46, F50)** — clip conversion with its equivalence falsifier; coverage rendering; profile-local map data; the human's demo save and clipped map built locally; clip timings recorded in plan §5.3; Item 1's manual check done.
- [ ] **Item 3 (F47)** — the harness exists; the honest slice-1 screenshots of the human's area were **shown to them**; windowed `FRAME_P95_MS` recorded.
- [ ] **HUMAN: Decisions 17, 18, and 19 answered.**
- [ ] **If Decision 17 = A:** Items 4–9 delivered with their proofs; the four slice-2 screenshots shown; **paused for the human's verdict.**
- [ ] **HUMAN: real-device sync gate passes** (§2). **Closes Phase 1.**
- [ ] **HUMAN: D3 device soak run.** **Closes Phase 0.**
- [ ] **When a Black/White dump is supplied:** Item 10 — verify markers resolved, `implementation_plan_rom_importer.md` written, preview shown, **paused for review**.
- [ ] The full §1 battery and every CI workflow (Linux and macOS) are green.

**When all of the above that apply are checked — or Item 3 is done and Decision 17 is still blank — this build's queue is empty. Do NOT invent work.** Legitimate triggers for more:
- a filled `Your selection:` on Decision 17, 18, or 19 (or any new item in `ongoing_general_errors.md`);
- the §1 battery or any CI workflow regressing;
- a §9 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
