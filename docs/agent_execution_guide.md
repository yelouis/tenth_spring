# Agent Execution Guide — Active Build: Buildings, Rail Art, and Speed for the Pokémon-Look Map (F51–F53), then Famous Places — Same Map for Everyone, Unlocking, Distort, and Enterable-Building Markers (verified 2026-10-20, pass 18; Decisions 21–27 answered the same day)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`) that only captures location and syncs.

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — whose overworld is the places the player has physically been. **The map is made of famous US places only:** 27 cities and 36 parks, monuments, and wonders (Decisions 16, 25, 26 — `docs/design_famous_places.md`). Home is a hub you **Distort** from.
- **Pokémon content** comes from ROMs **the player supplies**, read on their own machine (the PokeMMO model). **Black/White** supplies all data and sprites for the **649 Pokémon of Generations 1–5** (Decision 10 = B). **Emerald** supplies the overworld map tiles (Decision 19).
- **Story:** an original one — the Stillness, the Distortion, nine regional Wardens, and the Echo. `docs/design_story_and_world.md` is the theme contract for everything player-facing.
- **No commerce:** no Steam, no sales.

**Where things stand.**
- **The foundation is built and runs in CI:** background capture, a real SQLite save, pinned-TLS pairing and sync, and the memory guard.
- **The map — slices 1 and 2 — is built.** Pass 18 verified the whole pass-17 queue (Items 0–9 and 11): 20/20 game tests on Linux, macOS, and the human's Mac, and the source matches the plans. On the human's real neighbourhood, the game now draws a north-up, 8 m-tile map of paths, grass, parks, water, rail, and signs, under two-state fog, with a screenshot harness that proves what it draws.
- **The human looked at the slice-2 proof screenshots and said they "don't look like pokemon sprites. It should contain buildings."** They're right, and it's measurable:
  - **F51 — almost no buildings.** On their area, about **13%** of the real buildings are drawn. Sidewalks, parking aisles, and driveways are each drawn as 8 m paths (26.5% of the map is path), and the placement rule refuses to put a building next to any path.
  - **F52 — the overview zoom is slow:** 87 ms per frame against a 16.6 ms target. Synthesis takes ~9 ms a cell and runs on the main thread.
  - **F53 — rail lines look broken:** diagonal track draws as separate boxes.
  - The *art* is the original placeholder by design. **The real Pokémon look arrives with the human's Emerald dump** (Item 12). F51 is what keeps even the placeholder map from looking like a town.
- **The human also redesigned the map — all answered on 2026-10-20** (`ongoing_general_errors.md`, Decisions 21–26):
  - **Unlocking by area:** inside a famous city, any real movement in a neighbourhood reveals it (21 = B), and enough neighbourhoods reveal the city (22 = A, `clamp(ceil(10%), 2, 5)`). Any visit to a famous park reveals all of it.
  - **Famous places only (25):** 27 cities, 3 per region. Home is a hub. You Distort, free, to the famous city nearest home (its Waypost neighbourhood pre-revealed) and to any place you've physically visited. You return home only from a Waypost.
  - **Legendaries and Wardens (26):** 48 legendaries, each at its own themed place behind a challenge, with one decisive battle. Each region's Warden waits at a fixed landmark, once all three of the region's cities are unlocked. Each region gets its own story and survivors (`design_story_and_world.md` §4a).
  - **The same map for everyone (23 = A):** one pinned OpenStreetMap snapshot (2026-10-01), fixed conversion units per place, the whole coastline kept, and one global map seed. Decision 15's hosted stores are dropped.
  - **Your area is no longer a famous place,** so the canonical test city is **Washington DC** — public, a 21 MB file, nothing private.
- **Then, Decision 27 (the human's directive):** as in Pokémon, famous buildings and structures — the New York Subway, Alcatraz, the Seattle Underground, … — can be entered, and **each has a purpose** (a trainer, a Warden, hidden items, a legendary's maze, a puzzle, a quest step). Over 200 Pokémon-style side quests reveal what happened to each region (`docs/design_interiors_and_quests.md`).
  - **Ordinary buildings are searched from the doorway** instead of entered.
  - **This build only marks** the enterable buildings on the map (Item 22). The interiors and quests themselves are Phase 7–8 work (§9).

**What is approved for build right now:**
- **Items 13–16** (§2) — the building fix, the rail art, background synthesis, and a stricter proof that pauses for the human's verdict.
- **Items 17–22** (famous places, plus enterable-building markers) — approved by the human's decisions. **Item 17 pauses** for the human to review the filled-in place list.

**Waiting on the human:** Item 10 waits on a Black/White dump, Item 12 on an Emerald dump.

**What NOT to touch:**
- §11 — already delivered;
- §12 — accepted equivalents;
- §13 — intentional decisions.

§10 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string here and in the docs it points to is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work** — including a §10.3 target that the exact rules miss: **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise or tune silently.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds` or `.gba`, sprites, tiles, palettes, text banks, or stat tables, not even in a fixture or a debug PNG. Never help anyone find a ROM. ROMs come only from the human, through `TENTH_SPRING_ROM_BW` and `TENTH_SPRING_ROM_GBA`, which point **outside** the repo (`design_rom_asset_pipeline.md` §8). Mapping tables may reference ROM data **by number** only.
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Work on a branch per item, get all workflows green, then fast-forward `main`.
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the identity folder `user://sync_identity/`;
   - the human's demo profile `user://demo/`, including `user://demo/map_data/`.

   Tests use `user://test/…`. The DC profiles the agent makes (`user://measure_dc`, `user://demo_dc`) aren't the human's, and may be created and deleted freely.
5. **The human's location never enters the repo — and that includes place names.**
   - Never commit `.gpx` routes, demo saves, map stores, or screenshots of their area.
   - **Never write the name of their town, neighbourhood, or streets, or any coordinates of where they live or walk** — not in docs, code, tests, commit messages, or CI logs.
   - **Map-cell numbers (`cx`, `cy`), tile numbers, and Web-Mercator pixel or metre positions of their area count as coordinates.** Pass 17 leaked one in a doc note (M42); report sizes and counts only (`clip: 38 x 33 cells`).
   - Keep all of it in `~/tenth_spring_private/`. Tests use made-up coordinates near (0.01, 0.01) — open ocean.
6. **Heavy commands go through the memory guard:** `python3 -I tools/memguard.py run <step> -- <command>` (`design_memory_and_resources.md` §2). `test_runner.py`, `sync_e2e.py`, and `demo_import.py` wrap themselves.
   - Never run two heavy commands at once, and never leave one running beyond the session.
   - If a step exits **75** (no room) or **76** (stopped for memory), report it — don't retry in a loop.
   - The Mac is shared with other projects that use tens of GB. **Never** deliberately starve it.
7. **Godot on the human's Mac** is at `/Applications/Godot.app/Contents/MacOS/Godot` (4.3-stable), **not** on `PATH`. Set `GODOT_BIN` to it.
8. **Download nothing** except what an item names:
   - **Items 13, 15, 16, 18, and 21:** the pinned Washington DC snapshot — `https://download.geofabrik.de/north-america/us/district-of-columbia-261001.osm.pbf` and its `.md5` — into a scratch folder outside the repo.
   - **Item 17:** public place-name lookups on `https://nominatim.openstreetmap.org/search`, ≥ 1.1 s apart, with the plan's `User-Agent`. Public names only — never anything about the human.

   Never commit a download. Never fetch `-latest` for game data; use the pinned `-261001` files.
9. **Every change leaves the §1 battery and all CI workflows green** — that is the regression bar.
10. **Anything touching capture, battery, or cross-device sync requires a real-device check** before Phase 1 is declared closed (§2, HUMAN actions).
11. **The golden invariants (§13) stay green, always.**
12. **Detailed behaviour lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
13. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
14. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Name the machine (Linux CI, macOS CI, the human's Mac). Game-side claims count as executed only when a run printed the `PASS` lines.
15. **Proof images come only from the game.** A picture shown to the human as "this is what the game draws" must be saved by the game's screenshot harness from real data, with the exact command in the commit body or your message. Never present a mock-up as the game's output.
16. **Follow the story.** Any player-facing text, name, or content fits `docs/design_story_and_world.md` and its writing rules (§9). Nothing from Nintendo's stories.
17. **Report against the target, honestly.** When an item names a numeric target (placement %, frame time), state the measured number next to the target. A miss is a miss even if other numbers look fine. M42 recorded an 87 ms frame as "within target"; don't repeat that.

---

## 1. Verified baseline (run 2026-10-20 in this session, HEAD `item-17-famous-places-list`)

| Battery | Where | Result |
|---|---|---|
| `cd companion && flutter analyze` | Mac, local | **No issues found** |
| `python3 -I ../tools/memguard.py run flutter_test -- flutter test` (in `companion/`) | Mac, local | **37 passed, 2 skipped** (`sync_e2e_test`, `demo_import_test` — run only through their tools) |
| `GODOT_BIN=… python3 game/tests/test_runner.py` | Mac, local | **Executed.** IP guard + 17 self-tests, isolation audit, memguard (10), synthetic PBF, demo-screenshot and placeholder-atlas tests, famous-places check & unit tests (3), vendored SHA-256, harness self-test → **20/20 `PASS`**, `[REAL SAVE CHECK OK]`, static lint OK |
| `GODOT_BIN=… python3 -I tools/sync_e2e.py` | Mac, local | **Executed, green.** `E2E_SENT rows 14` → `visit_log 14, last_applied_seq 14, map_cell 3, place_node 1` |
| CI `game_tests` / IP guard / `sync_e2e` | runs `39549576482` / `39549576511` / `39549576467` (Item 16) | **All green** — `game_tests` on Linux and macOS |
| **Famous-places list (M48, Item 17)** | Mac, local | **75 places** (27 cities, 36 sites, 12 spots), 48 legendaries, 9 wardens validated. Falsification tests passed. |
| **Measurement — Washington DC, the canonical test city** (pinned `district-of-columbia-261001`, MD5 verified, converted unclipped in **15.4 s**) | Mac, local | **136,325** building candidates across 3,706 built-up cells → **44,267 placed (32.5%)**. Building tiles: **18.9%** (target ≥ 12%), path tiles: **16.6%** (target ≤ 18%), road tiles: 6.8%. Decision 28 filed on the placement target. |
| **Proof v2 (M47, Item 16)** | Mac, local | `shot_z2_mb_cleared`: **VISIBLE_DOORS 7** (target ≥ 3 ✅); `shot_z1_mb_cleared`: **VISIBLE_DOORS 20** (target ≥ 8 ✅); all `FRAME_P95_MS` **16.67 ms** ✅ |
| **Synthesis speed** (same store, 200 cells, features prefetched) | Mac, local | Dedicated `SynthWorker` off main thread, 256-cell raw-row LRU |
| `FRAME_P95_MS`, windowed (M35, M46) | Mac | zoom 1: **16.67 ms** ✅ (load max frame **24.68 ms** ✅ ≤ 33 ms); **zoom 1/16: 16.67 ms** ✅ (load max frame **27.28 ms** ✅ ≤ 33 ms, down from 86.9 ms ❌) |
| Real-device sync gate | phone + PC | ⚠️ **NOT RUN** — human. Ready now. |
| D3 device soak | 8 h background carry | ⚠️ **NOT RUN** — human (Decision 5 = A). Ready any time. |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 13 | **Buildings: drop minor ways, placement v2, measurement — F51** (slice-2 plan §10.1–10.3, §10.7) | The human's verdict. Everything else in this build is judged on a map that has buildings. |
| 14 | **Connected rail art — F53** (§10.4) | Small, independent art fix. Before the proof, so the screenshots don't show broken rails. |
| 15 | **Synthesis off the main thread — F52** (§10.5) | Touches the same renderer the proof measures. Must land before Item 16's frame-time acceptance. |
| 16 | **Proof v2 in DC → show the human → PAUSE for their verdict** (§10.6) | Needs 13–15. Continue to Item 17 while the human reviews; the look doesn't affect the place list. |
| 17 | **The famous-places list** (`implementation_plan_famous_places.md` §1) → **PAUSE** for the human's review | Everything after builds on the place ids, boundaries, and Wayposts. The human must see the list first. |
| 18 | **The same map for everyone + place stores (schema v4)** (plan §2, §3) | The reveal engine reads place stores and `area_cells`. |
| 19 | **Unlocking: save migration 2 + the reveal engine + the starter city** (plan §4) | Needs Item 18's stores. |
| 20 | **Distort, the Town Map, and the home hub — viewer level** (plan §5) | Needs the Distort list from Item 19. |
| 22 | **Enterable landmarks on the map — gold roof, highlighted door, name sign** (slice-2 plan §10.8; Decision 27) | Needs Item 17's `interiors` and the renderer. Before the proof, so DC's screenshots show them. |
| 21 | **Real-data proof in Washington DC → PAUSE** (plan §6) | Needs 18–20 and 22. |
| 10 | **Phase 2 — ROM spike + importer plan** (Black/White) | ⛔ Waits on the human supplying a Black/White dump. |
| 12 | **Emerald tile spike + tile-importer plan** (Decision 19) | ⛔ Waits on the human supplying an Emerald dump. **This is what makes the map look like real Pokémon.** |

**▶ HUMAN actions:**
- **At Item 17's pause:** review the filled-in famous-places list (names → OSM boundaries → Wayposts), and confirm or swap rows — including which legendary goes where (`design_famous_places.md` §1.2).
- **For the real Pokémon look:** a Pokémon Emerald (USA) dump from your own cartridge (`TENTH_SPRING_ROM_GBA`), kept outside the repo. It unblocks Item 12.
- **For Pokémon themselves:** a Black or White (USA) dump from your own cartridge (`TENTH_SPRING_ROM_BW`). It unblocks Item 10.
- **Real-device sync gate — ready now.** It closes Phase 1. Install the companion on your iPhone (README → *Install the companion on an iPhone*), and start the PC game from `/Applications/Godot.app` with `game/project.godot`.
  1. **Pair and report:** real phone + PC on one Wi-Fi network. Pair by QR — this also proves a real phone can scan the PC's QR. Walk an errand, then *Report to PC*; the rows appear on the PC.
  2. **Wireshark:** filter `tcp.port == 7350`. The capture shows only TLS records, and searching it for the home's 3-decimal latitude finds nothing.
  3. **iOS:** the local-network prompt appears on the first report.
  4. **Address change:** renew the PC's DHCP lease → *Report to PC* shows the unreachable message. Re-scan → the next report succeeds **without** re-pairing.
  5. **Second phone:** pair a second phone → the first phone's next report shows the unpaired message. Re-scanning on the first phone pairs it again.
- **Any time:** the D3 device soak (closes Phase 0).

Deferred (trigger-gated, **do not start**): see §9.

---

## 3. Item 13 — Buildings: drop minor ways, placement v2, and a measurement tool (F51)

**What this means for the user:** famous cities fill with houses, shops, and schools — nearly half of the real buildings drawn as Pokémon-style buildings — instead of a field of tan paths.

**Contract:** `implementation_plan_world_generation_slice2.md` §10.1, §10.2, §10.3, §10.7.

### The gap
- **Minor ways are stored and drawn.** `region_converter.gd:1216-1219` stores every `highway=service` and `highway=footway` way; the tag list at `:555` doesn't keep `footway`, `cycleway`, `service`, or `indoor`, so sidewalks can't even be told apart. In the human's store: 13,724 service pieces and 7,242 footway pieces, against 4,162 residential streets.
- **Paths are drawn before buildings** (`tile_synth2.gd:452`). A building is rejected if any tile of its 1-tile ring is a path (`:51-54`, `:686-710`). There's no nudge, and no side-by-side buildings.
- **No placement statistics, and no way to measure real data** — so an 87%-drop synthesizer passed every test.

### Implementation
1. **Converter:** §10.1's exclusions; keep the four extra tags; store `schema_version = '3'`; the map view's skip message becomes `need 3`.
2. **Synthesis:** §10.2, steps 1–7 exactly — split the line layer (roads before buildings, paths after), the v2 rejection rule, reserved door rows, the 13-offset nudge, the same rules for fallback houses, and `stats`.
3. **`tools/measure_synth.py` and `game/scenes/measure_synth.tscn`/`.gd`**, per §10.3, under memguard step `measure_synth` (measure its budget on the first run). It prints only the `MEASURE …` line.
4. **Fixture v3 and tests (k)–(n)**, per §10.7. Commit the new golden hashes with the reason.
5. **Convert Washington DC** from the pinned snapshot (standing constraint 8; check the MD5): `python3 -I tools/map_convert.py --pbf <district-of-columbia-261001.osm.pbf> --out-dir user://measure_dc`. Keep the file outside the repo until Item 21 is done.
6. **Measure:** `python3 -I tools/measure_synth.py --store user://measure_dc/<file>.db`. Put the line in the commit body, and add an "after Item 13" column to §10.3's table.

### Validation
- **Falsifying:** test (k) fails against the current code — sidewalks and driveways are stored, and at most 1 of the 3 houses is placed. Paste the failure in the commit body.
- **Targets on Washington DC's built-up cells (§10.3):** placement **≥ 45%** (baseline ≈ 9.5%), building tiles **≥ 12%** (3.6%), path tiles **≤ 18%** (30.6%). State each measured value beside its target. **If any target is missed with the rules implemented exactly, STOP** and file a decision with options — don't tune.
- Tests (l), (m), and (n) pass; `region_import_test` passes on fixture v3; the battery and all workflows are green.

### Blast radius (same commit)
`region_converter.gd` · `map_store.gd` (schema `'3'`) · `map_view.gd` (skip message) · `tile_synth2.gd` · `tile_synth2_test.gd` · `region_import_test.gd` and `region_import_pause_test.gd` (hashes) · `tools/generate_synthetic_pbf.py` + its test + `synthetic_neighborhood.osm.pbf` · new `tools/measure_synth.py` and `game/scenes/measure_synth.*` · `memguard_budgets.json` · slice-2 plan §10.3 numbers · F51 → Resolved.

---

## 4. Item 14 — Connected rail art (F53)

**What this means for the user:** rail lines read as continuous track, even on diagonals, instead of a trail of separate boxes.

**Contract:** slice-2 plan §10.4.

### The gap
`tools/gen_placeholder_atlas.py:398-446` draws `RAIL` straight only — vertical if N or S is set, else horizontal — inside a framed tile. A 4-connected stair-step diagonal therefore renders as disconnected pieces.

### Implementation
Redraw `RAIL` as a connector tile, exactly per §10.4. Regenerate `game/assets/tiles/placeholder_v1.png` and its JSON.

### Validation
- **Falsifying — new assertion in `tools/test_gen_placeholder_atlas.py`:** in the `RAIL` tile for mask N + E (`0b0011`), the pixels at the centre of the north edge and the centre of the east edge are rail colour, and the centres of the south and west edges are gravel. The current art fails it.
- Regeneration is still byte-identical, and the JSON coverage test still passes.

### Blast radius (same commit)
`tools/gen_placeholder_atlas.py` · `placeholder_v1.png` / `.json` · `tools/test_gen_placeholder_atlas.py` · F53 → Resolved.

---

## 5. Item 15 — Synthesis off the main thread (F52)

**What this means for the user:** zooming out to see their whole area stays smooth, instead of stuttering at ~11 frames a second.

**Contract:** slice-2 plan §10.5.

### The gap
`map_view.gd` synthesizes on the main thread (`_render_cell`, ~`:696`). The 8 ms budget (`:19`, `:597`) is checked only between cells, and one cell costs ~9.3 ms. Zoom 1/16 measured 86.9 ms per frame (M42).

### Implementation
1. **`game/world/synth_worker.gd`:** one `Thread` with its own read-only `MapStore` connections, opened inside the thread, plus a 256-cell raw-row LRU, a request queue (≤ 64, nearest-first, stale requests dropped), and a mutex-guarded result queue.
2. **`map_view.gd`:**
   - post requests, and each frame blit **≤ 2** finished cells, or create **≤ 8** overview textures at zoom < 1;
   - cells still waiting show solid fog;
   - reveal-state queries stay on the main thread.
3. **Harness:** print `LOAD_TIME_MS`, `LOAD_MAX_FRAME_MS`, and the steady-state `FRAME_P95_MS` (120 frames after `pending_cell_count() == 0`). `tools/demo_screenshot.py` gains `--demo-dir <dir>`, passed through to Godot.
4. **The DC demo profile** — needed for this item's real-data check, and reused by Item 16 (slice-2 plan §10.6 step 0):
   - draw a GPX through public DC landmarks (National Mall, Union Station, Dupont Circle, Capitol Hill), saved outside the repo;
   - `python3 -I tools/demo_import.py --gpx <file> --demo-dir user://demo_dc`;
   - convert DC from the pinned snapshot into `user://demo_dc/map_data/`.

### Validation
- **`map_view_test`:**
  - each synthesized result records the thread that made it, and it isn't the main thread;
  - no frame blits more than 2 cells;
  - after a camera jump, the request queue never exceeds 64, and requests for cells no longer visible are dropped.
- **Falsifying — on the human's Mac, in the DC demo profile:** `tools/demo_screenshot.py --demo-dir user://demo_dc` at zoom 1 and zoom 1/16. Steady-state `FRAME_P95_MS` **≤ 16.6 ms** at both, and `LOAD_MAX_FRAME_MS` **≤ 33 ms**. The old code measured 86.9 ms at 1/16. Report all four numbers beside their targets.
- The battery and all workflows are green.

### Blast radius (same commit)
`map_view.gd` · new `synth_worker.gd` · `map_view_test.gd` · `tools/demo_screenshot.py` (output lines) · `design_memory_and_resources.md` §3.3 (the worker and its caches) · F52 → Resolved.

---

## 6. Item 16 — Proof v2 in Washington DC → show the human → PAUSE

**What this means for the user:** they see a famous city — DC — with buildings, rails, and parks, made by the game at Pokémon zoom, and decide whether the look is right.

**Contract:** slice-2 plan §10.6.

### Implementation
1. **Use the DC demo profile** made in Item 15 (`user://demo_dc`).
2. **Harness:** `--focus=most_visited|most_buildings` and the `VISIBLE_DOORS` line.
3. **Capture the four screenshots** in §10.6's table with `tools/demo_screenshot.py --demo-dir user://demo_dc`, into a folder outside the repo.

### Validation
- **Automated:** `screenshot_args_test` accepts both `--focus` values and refuses anything else with exit 2.
- **Acceptance on the human's Mac:** `VISIBLE_DOORS` **≥ 3** in `shot_z2_mb_cleared.png` and **≥ 8** in `shot_z1_mb_cleared.png`, and every steady-state `FRAME_P95_MS` ≤ 16.6 ms. **Report each number beside its target.**
- **Show the human all four images.** Say plainly that the art is the original placeholder, and that the real Pokémon tiles arrive with their Emerald dump (Item 12).
- **PAUSE** for their verdict on the look, and continue to Item 17 meanwhile.

### Blast radius (same commit)
`game/scripts/screenshot_config.gd` · `map_view.gd` · `tools/demo_screenshot.py` · `screenshot_args_test.gd` · M-entry in `ongoing_general_errors.md` with the numbers.

---

## 7. Famous places (Items 17–22) — approved by Decisions 21–27

**What this means for the user:** the game's world becomes 27 famous cities and 36 famous parks and wonders.
- Home is a hub. From day one they can Distort to the famous city nearest home, its Waypost neighbourhood already revealed.
- Passing through a neighbourhood for real reveals it; enough neighbourhoods reveal the city; a visit to a park reveals all of it.
- Two friends in the same place see the identical map.

**The contracts:** `docs/design_famous_places.md` (the design and the lists) and `docs/implementation_plan_famous_places.md` (the build). Implement their sections exactly; this guide adds only order, proof, and blast radius.

**Rules for every famous-places item:**
- Never name the human's home, town, or starter city anywhere in the repo. The proof uses Washington DC.
- Every reveal only ever adds.
- Golden invariant 1 holds: ingest writes only `map_cell`, `place_node`, and `visit_log`.

### 7.1 Item 17 — The famous-places list → PAUSE (plan §1)
- **Build:**
  - `game/config/famous_places.json` — 75 entries, per `design_famous_places.md` §1–§5 and §9;
  - the Nominatim lookups for boundary relations, Wayposts, Warden landmarks, and **each famous interior's public entrance** (`design_interiors_and_quests.md` §4) — public names only, ≥ 1.1 s apart;
  - `tools/check_famous_places.py` in the battery.
- **Prove:** the checker passes — 27 cities (3 per region); 48 distinct legendaries with no shared place; a boundary and Waypost for every city and site; one Warden per region in one of its cities; ≥ 2 interiors per city and a visitor centre per site, each with ≥ 2 purposes including T, W, L, or Q. **Falsifying:** a copy with two legendaries on one place fails, and so does an interior with only H.
- **PAUSE:** show the human the list (name → relation id → Waypost), and record their confirmations or swaps in `ongoing_general_errors.md`. Continue to Item 18 only after they answer.
- **Blast radius:** the config, the checker, `test_runner.py`.

### 7.2 Item 18 — The same map for everyone, and place stores (plan §2, §3)
- **Build:**
  - `map_constants.gd` (`MAP_SNAPSHOT`, `MAP_SEED`); the pinned dated URLs in the fetcher;
  - `tools/map_convert.py --place <id>` with the fixed unit (boundary bounding box + 2 cells);
  - the whole coastline kept; one store per place, schema v4, with `areas` and `area_cells` (neighbourhoods for cities, one area for sites);
  - fixture v4.
- **The in-game install now converts only famous places** — this closes F45(d).
- **Prove:**
  - **Falsifying — the determinism test** (plan §2.5): two different clips give identical place buffers;
  - fixture v4's expected `areas`/`area_cells`;
  - DC converted with `--place city:washington-dc`, with time, peak RSS, and store size recorded in slice-1 plan §5.3.
- **Blast radius:** `tile_synth2.gd` (seed from `MAP_SEED`), `map_fetcher.gd`, `region_converter.gd`, `map_store.gd`, `map_convert.*`, the generator + its test + the fixtures, `region_import_test.gd`, `map_view.gd` (skip message `need 4`), F45 → Resolved.

### 7.3 Item 19 — Unlocking: migration 2, the reveal engine, the starter city (plan §4)
- **Build:**
  - migration 2 (`area_reveal`, `distort_list`, `meta('home_cell')`);
  - `game/world/reveal_engine.gd` — any movement unlocks a neighbourhood or site (21 = B), the city threshold (22 = A), the Distort list, home designation, and the starter city;
  - the four call sites.
- **Prove:**
  - `reveal_engine_test.gd` (add it to `EXPECTED`), cases (a)–(g). **(a) — a corridor row reveals a whole neighbourhood — is the falsifier.**
  - `db_migration_test` covers v1 → v2. `sync_ingest_isolation_test` stays green, unchanged.
- **Blast radius:** `db.gd`, `sync_server.gd`, `main.gd`, `demo_import_server.gd`, the engine and its test, `EXPECTED`, `design_game_state_and_models.md`, `design_world_generation.md` §1–2.

### 7.4 Item 20 — Distort, the Town Map, and the home hub — viewer level (plan §5)
- **Build:**
  - `home_hub.tscn` and `town_map.tscn` (original art);
  - lit, grey, and ringed markers; loading a place centred on its Waypost;
  - `Return home` only within 1 cell of the Waypost;
  - boot routing: phone inside a famous place → that place; otherwise → the hub.
- **Prove:** the plan §5 scene tests. **Falsifying:** a locked marker can't be opened.
- **Blast radius:** the new scenes and tests, `main.gd`, `map_view.gd`/`.tscn`, `EXPECTED`, `design_travel_and_time.md` §4 (mark it built at viewer level).

### 7.5 Item 22 — Enterable landmarks on the map (slice-2 plan §10.8; Decision 27)
- **Build:**
  - the map view passes each cell's famous interiors to synthesis;
  - landmark buildings get variant bit 32 (a gold roof, gold-framed walls and door);
  - a name sign beside the door, or a sign alone for structures;
  - the four new atlas rows;
  - the tooltip `<name> — can be entered (interiors arrive in a later update)`.
- **Prove:** §10.8's tests. **Falsifying:** the fixture building gets bit 32 only when its interior entry exists. Atlas regeneration stays byte-identical.
- **Blast radius:** `tile_synth2.gd`, `map_view.gd`, `tools/gen_placeholder_atlas.py` + the assets, `tile_synth2_test.gd`, `map_view_test.gd`, the atlas test.

### 7.6 Item 21 — Real-data proof in Washington DC → PAUSE (plan §6)
- **Steps:**
  1. Convert DC with `--place`.
  2. Make a DC demo profile with the agent-drawn public route, and home at a public point outside DC.
  3. Capture the Town Map, DC at zoom 1/16, DC at zoom 1 at the Waypost, and DC at zoom 2 on an enterable landmark (for example the Library of Congress), showing its gold roof and sign.
  4. Report the neighbourhoods unlocked, whether the city threshold was reached, and the Distort list.
  5. Show the human.
- **PAUSE.**
- **Doc changes** (plan §7): `design_privacy_and_location.md`, `master_implementation_plan.md` Phase 3.
- **Blast radius:** those docs; Items 17–21 → Resolved.

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

---

## 8b. Item 12 — Emerald tile spike + tile-importer plan (Decision 19)

**⛔ Waits on the human supplying a Pokémon Emerald (USA) dump from their own cartridge** (`TENTH_SPRING_ROM_GBA`). The renderer's atlas slot already exists — `asset_db.tile_atlas()`, M41. It produces findings, a mapping table, and a plan for review; **it does not build the production importer.**

**What this means for the user:** the moment their map stops looking like placeholder art and starts looking like a real Pokémon game.

### The gap
- Every Emerald format rule in `design_rom_asset_pipeline.md` §4 is still **verify**.
- No mapping exists from the slice-2 tile vocabulary (slice-2 plan §3) to Emerald metatiles.
- The slice-2 building templates (plan §4.2) may not match the building shapes Emerald actually has.

### Implementation
1. **Preconditions.** `TENTH_SPRING_ROM_GBA` is set, the file exists, and its real path is **not** inside the repo. If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib** under `tools/rom_spike/emerald/`, run with `python3 -I` under `memguard run rom_spike_gba` (measure the budget on the first run). Output goes to `~/.tenth_spring_rom_spike/emerald/`, outside the repo. **The code embeds no bytes, images, or tables taken from the ROM** — only offsets, sizes, and metatile numbers.
3. **Header.** Assert `BPEE` at `0xAC`. Compute the SHA-1, compare it with the No-Intro DAT entry, and record the hash and the DAT source in `design_rom_asset_pipeline.md` §2.
4. **Find the tilesets.** Locate the primary tileset and the secondary tilesets through the ROM's own pointer tables. Record every offset, structure size, and how you found it, citing documentation (for example, the community decompilation project's source as a *reference*) — never a downloaded ROM or extracted asset.
5. **Decode** the tile graphics (LZ77 type `0x10`), palettes, metatiles, and attributes. Replace each Emerald **verify** in `design_rom_asset_pipeline.md` §4 with the confirmed rule.
6. **Contact sheets for the human:** the primary tileset's metatiles at 2×, plus the secondary tilesets for 4–6 differently themed towns, saved to the spike folder. Tell the human the paths. **Never commit them.**
7. **Draft `game/config/emerald_tile_map.json`** — numbers only:
   - for every `(class, variant, mask)` the synthesizer emits, the metatile to use;
   - the multi-metatile building compositions for `house_s`, `house_m`, and `block_l`, plus each roof colour;
   - a `gaps` list of anything Emerald lacks (for example snow, or inner corners the 16-mask scheme can't express).
8. **Preview from synthetic data only.** A test helper dumps the four fixture cells' slice-2 buffers to `user://test/fixture_cells.bin`. The spike renders them with the Emerald tiles to `~/.tenth_spring_rom_spike/emerald/preview.png`. Show it to the human; never commit it.
9. **If the templates don't fit** Emerald's buildings, write the smallest amendment to slice-2 plan §4.2 that does, and include it in the review. Don't change the synthesizer yet.
10. **Write `docs/implementation_plan_rom_tiles.md`** at foundation depth. Cover:
    - the GDScript modules (`gba_rom.gd`, `gen3_tiles.gd`, `tile_atlas_builder.gd`);
    - `asset_db.tile_atlas()`;
    - the resumable cache write;
    - `design_rom_asset_pipeline.md` §7's tile checks;
    - the test strategy — ROM tests run only when `TENTH_SPRING_ROM_GBA` is set, and are skipped with an explicit message otherwise.
11. **PAUSE for human review.**

### Validation
- **Decode check:** every decoded tile uses ≤ 16 colours from its palette, and the grass, tall-grass, and water metatiles pass a pixel-variance threshold that a wrong decompression or palette fails.
- **Coverage:** the mapping table covers every `(class, variant)` in the placeholder JSON, or lists it under `gaps`.
- **Nothing leaked:** `git status` shows only `tools/rom_spike/emerald/*.py`, `game/config/emerald_tile_map.json`, and doc changes, and the guard (with Item 11's GBA rule) exits 0.

### Blast radius (same commit)
`tools/rom_spike/emerald/` · `game/config/emerald_tile_map.json` · `docs/design_rom_asset_pipeline.md` §2 and §4 · new `docs/implementation_plan_rom_tiles.md` · the slice-2 plan amendment (if any) · Decision 19 status.

---

---

## 9. Deferred — trigger-gated, do NOT start
- **Distort gameplay with a walking avatar** — the real Waypost rule (you must *walk* to the Waypost to go home), the home hub's Rest, PC Box, and Garden, and the session-start banner (`design_famous_places.md` §2–§4; `design_travel_and_time.md` §4–5). **Trigger:** Phase 4. Item 20 builds only the viewer-level structure.
- **Famous interiors, puzzles, doorway searching, the quest engine, the Walker's Journal, and the quest content** (`design_interiors_and_quests.md`). **Trigger:** Phase 7 — after the avatar (Phase 4) and the battle engine (Phase 5). Write `implementation_plan_interiors_and_quests.md` first, and pause.
- **Legendary challenges and lairs, Warden trials, region survivors, and the Echo** (`design_famous_places.md` §5–§6; `design_interiors_and_quests.md` §4; `design_story_and_world.md` §4–§5, §4a; encounters §7). **Trigger:** Phase 8 — after Phase 7. Not before.
- **Widening the map beyond famous places.** **Trigger:** a human request. The phone and save already keep everything, so nothing is lost meanwhile.
- **Slice 3** — spawn zones, tall-grass encounters, biomes and regions per cell, Distortion Fields, ledges and terraces from USGS elevation, and overgrowth by distance (`design_encounters_and_haunted_zones.md` §2a and §3a). **Trigger:** the human approves the look at Item 16's pause. Write `implementation_plan_world_generation_slice3.md` first, and pause.
- **Moving `MAP_SNAPSHOT` forward.** **Trigger:** a release the human approves. It changes every player's map at once, deliberately.
- **F49 — memguard `run` logs a 0.0 peak for short steps.** **Trigger:** the next change to `tools/memguard.py` — take the first sample after 0.2 s, then every `POLL_SECONDS`.
- **F7 — home-cell grid mismatch.** `companion/lib/capture/fuzz.dart:38-47` snaps home to a **300 m** grid; the game stores home as one cell (`meta('home_cell')`, Item 19). **Trigger:** the onboarding UI for designating home (Phase 10).
- **mDNS auto-discovery (F27 d).** v1 finds the PC by remembered address plus QR re-scan. **Trigger:** the human reports that re-scanning is a real nuisance.
- **A Windows CI job.** The Windows `.dll`s are vendored but have never been loaded. **Trigger:** Phase 10 release prep, or the human playing on Windows.
- **Black 2/White 2 and non-USA ROMs.** **Trigger:** a human request.

---

## 10. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Capture · 1 Sync & models · **2 ROM importer** · 3 World generation (slices 1–2 built and being corrected; famous places next; slice 3 later) · 4 Travel & time (incl. Distort) · 5 Creatures & battles · 6 Encounters & catching · 7 Exploration & survival · 8 Haunted zones, legendaries, Wardens · 9 Art & UI · 10 Privacy, balance & release.

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

  Slice 2 replaced slice-1 synthesis and rendering (Item 8, M41).
- **Pass 17 build (M32–M42), verified in pass 18 (M43):**
  - **Items 0–3:** north-up screen (F43); USA scope, redirects, streaming, threaded install, and the wired chip (Decision 16, F44, F45 a/b/c/e); clip conversion, coverage, F46, and profile-local map data (F50); the screenshot harness (F47).
  - **Item 11:** the IP guard blocks GBA ROM headers.
  - **Items 4–9 — slice 2:** 8 WM-m tiles and store v2; `tile_synth2.gd`; the placeholder atlas; renderer v2 (known/cleared layers, fog shaders and feathering, overview, sign tooltips, `--preview-cleared`, the `asset_db.tile_atlas()` slot); the proof screenshots.

  Items 13–15 *correct* parts of slice 2 by plan (§10) — they don't rewrite it.

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
- **Decision 20 — `landuse=construction` is not stored** (M37). It resolved a contradiction in the slice-2 plan; keep it.
- **Camera limits of ±200,000,000 px** (M42), wider than the plan mentions, so that any US location is reachable.
- **Item 6's commit message lists template sizes `3×3` and `7×6`; the code uses the plan's `4×3`, `5×4`, and footprint-sized `block_l`.** The code is right — don't "fix" it to match the message.

## 13. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever.** Species, moves, and items are referenced by number; names, stats, and sprites come from the player's ROM cache through `asset_db` only. **The companion never contains Nintendo assets or names.**
- **Roster and rules** (Decision 12): **649 species, Gen 1–5, Black/White only** (Decision 10 = B). **Gen IV formulas over Gen V data** — 17 types; Steel resists Ghost and Dark; crit ×2; Dusk Ball ×3.5. No hidden abilities in v1. Gen 6+ permanently out of scope.
- **The story is `design_story_and_world.md`** (Decision 18): the finale is the Echo — a mirror of the player's party at +5 levels — after all nine Warden Anchors. **Giratina is an ordinary legendary.** Legendaries and mythicals never appear in Distortion Fields. The Pokédex is complete only when every legendary is caught or defeated.
- **Two cartridges, separate jobs** (Decisions 10 and 19): Black/White for every Pokémon; Emerald for the map's tiles only. The code-drawn placeholder atlas is the permanent no-ROM look.
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
- **Minor ways are never drawn** (F51, after Item 13): sidewalks, crossings, parking aisles, driveways, and every `highway=service`. Pokémon maps show streets and footpaths.
- **Buildings come before footpaths; roads come before buildings** (slice-2 plan §10.2). Every building keeps its door row walkable.
- **Synthesis never runs on the main thread** (F52, after Item 15). SQLite connections are never shared across threads.
- **The map is famous places only** (Decisions 25–26): 27 cities and 36 parks and wonders, listed in `design_famous_places.md`. Everything else is never drawn — but still recorded and stored.
- **Unlocking only ever adds** (Items 17–21): an unlocked neighbourhood, city, or site stays unlocked; reveal states never decrease. Any real movement counts (21 = B); the city threshold is `clamp(ceil(0.10 × n), 2, 5)` (22 = A).
- **Distort:** from home, only to the starter city and to places physically visited; home only from a Waypost or by blackout (Decision 25).
- **The same map for everyone** (Decision 23): `MAP_SNAPSHOT` pinned per release, fixed conversion units, the whole coastline kept, and `MAP_SEED` global. **Never** let a per-player seed or a `-latest` download touch the map.
- **Legendaries get one decisive battle,** each at its own place behind a challenge; Wardens appear only once their region's three cities are unlocked (Decision 26).
- **Anything enterable has a purpose** (Decision 27): every famous interior carries ≥ 2 purposes, including a trainer, Warden, legendary, or rewarding quest step. Ordinary buildings are searched from the doorway, never entered. All interiors, puzzles, and quests are original.

## 14. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, setup | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Phases 0–1 build steps, v1 DDL, TLS sync protocol, Godot test-harness contract | `docs/implementation_plan_foundation.md` |
| **Slice 1 of world generation** + its pass-17 amendments (§5.1a, §5.4a, §5.5, §7.1a, §7.4) | `docs/implementation_plan_world_generation.md` |
| **Slice 2 — "Pokémon look"** (approved, Decision 17 = A) **+ the pass-18 corrections (§10)** | `docs/implementation_plan_world_generation_slice2.md` |
| **What the map contains** — famous places, unlocking, Distort, the same map for everyone, the 48 legendary places, Warden landmarks | `docs/design_famous_places.md` |
| **Building famous places** (Items 17–21) | `docs/implementation_plan_famous_places.md` |
| **Enterable famous buildings, puzzles, and side quests** (Phase 7–8; markers in Item 22) | `docs/design_interiors_and_quests.md` |
| **The backstory and theme** — the Stillness, the Distortion, Wardens, the Echo, writing rules | `docs/design_story_and_world.md` |
| The Black/White and Emerald ROMs, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types, damage, catching, party, PC, blackout | `docs/design_creatures_and_battles.md` |
| Spawn zones, regions and biomes, Distortion Fields, ghost share, levels, haunted zones, legendaries, Warden trials, the Echo finale | `docs/design_encounters_and_haunted_zones.md` |
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
            FIRST and PAUSE for human review. (Items 13–16 implement the approved slice-2 plan's
            §10; Items 17–22 implement the approved famous-places plan, with a pause at 17.)
3 IMPLEMENT Exactly as written, on a branch. Honor §13 and the standing constraints —
            above all: no Nintendo content; none of the human's places in the repo; no test
            touches the real save, identity, or demo profile; one grid; never force-push main.
4 VALIDATE  This item's validation (run the falsifier against the OLD code first), then the full
            §1 battery on the Mac with GODOT_BIN, then every workflow on GitHub, Linux and macOS.
            Report each numeric target beside its measured value. Map pictures come only from
            the harness.
            RED GATE: do not start the next item on a failing one.
5 BLOCKED?  Spec wrong, impossible, docs conflict, a target missed with the rules implemented
            exactly, a decision blank, or a ROM you don't have → STOP. File in
            ongoing_general_errors.md with options.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design doc
            whose behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body.
```

## Definition of Done (this build)
- [x] **Item 13 (F51)** — minor ways dropped; placement v2; `measure_synth`; fixture v3; DC converted from the pinned snapshot; **on DC's built-up cells: placement ≥ 45%, building tiles ≥ 12%, path tiles ≤ 18%** — or a decision filed.
- [x] **Item 14 (F53)** — connected rail art; the falsifying pixel test passes.
- [x] **Item 15 (F52)** — worker-thread synthesis; steady `FRAME_P95_MS` ≤ 16.6 ms at zoom 1 and 1/16; load frames ≤ 33 ms.
- [x] **Item 16** — the four screenshots, `VISIBLE_DOORS` ≥ 3 (zoom 2) and ≥ 8 (zoom 1), **shown to the human; paused for their verdict.**
- [x] **HUMAN: Decisions 21–26 answered** (2026-10-20).
- [ ] **Item 17** — the famous-places list filled in, the checker in the battery; **the human reviewed it at the pause.**
- [ ] **Item 18** — the determinism test passes; place stores v4; the in-game install converts only famous places (F45 resolved).
- [ ] **Item 19** — the reveal engine (any movement, the scaled threshold, sites, the Distort list, the starter city); migration 2.
- [ ] **Item 20** — the home hub, the Town Map, and `Return home` at the Waypost (viewer level).
- [ ] **Item 22** — enterable landmarks marked on the map (gold roof, door, sign); the falsifying test passes.
- [ ] **Item 21** — the DC proof, including a landmark close-up, **shown to the human; paused.**
- [ ] **HUMAN: real-device sync gate passes** (§2). **Closes Phase 1.**
- [ ] **HUMAN: D3 device soak run.** **Closes Phase 0.**
- [ ] **When a Black/White dump is supplied:** Item 10 — verify markers resolved, `implementation_plan_rom_importer.md` written, preview shown, **paused for review**.
- [ ] **When an Emerald dump is supplied:** Item 12 — Emerald verify markers resolved, `emerald_tile_map.json` drafted, contact sheets and preview shown, `implementation_plan_rom_tiles.md` written, **paused for review**.
- [ ] The full §1 battery and every CI workflow (Linux and macOS) are green.

**When all of the above that apply are checked, this build's queue is empty. Do NOT invent work.** Legitimate triggers for more:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the human's verdict at Item 16's, 17's, or 21's pause;
- a ROM dump supplied (Items 10, 12);
- the §1 battery or any CI workflow regressing;
- a §9 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
