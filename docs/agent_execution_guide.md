# Agent Execution Guide — Active Build: Launch Safety, Landmarks, the Ruined City, the Real Emerald Look, Explore Here, and Generation 8 (verified 2026-10-23, pass 23; Decisions 29–37 answered)

**You are an engineering agent picking up Tenth Spring with zero prior context.** There are two builds:
- a PC game (**Godot 4.3**, `game/`);
- a thin phone companion (**Flutter**, `companion/`). Until Item 27 it still does background location capture; after Item 27 it is just an **Explore Here** button and a report to the PC (Decision 29).

**The game:** a **Pokémon game** — Diamond/Pearl style, Ghost-heavy, set after a collapse — played on a map of **famous US places only**: 27 cities and 60 parks, monuments, and wonders (`docs/design_famous_places.md`). Home is a hub you **Distort** from.
- **Pokémon:** all **905 species of Generations 1–8** (Decision 32), under **Generation 8 battle rules**, with **Mega Evolution** and nothing else (Decision 36).
  - **Sprites:** #1–649 from the player's own Black/White ROM; #650–905 from the **Smogon Sprite Project's** fan sprites.
  - **Data:** from PokéAPI's open data.
  - All of it is read or downloaded **on the player's machine**, never committed (`docs/design_rom_asset_pipeline.md`).
- **Map art:** the player's **Emerald** ROM supplies the tiles (Decision 19). Famous buildings get original set pieces or Emerald look-alikes (`design_art_direction.md` §1a).
- **Story:** an original one — the Stillness, the Distortion, nine Wardens, the Echo, and now the Glow in Las Vegas (Decision 33). `docs/design_story_and_world.md` is the theme contract.
- **Long game** (Decision 35): fixed level-75 Warden teams, and survival (weariness). Built in Phases 5–8, not in this queue.
- **No commerce:** no Steam, no sales.

**Where things stand.**
- **Pass 23 (2026-10-23, M59):** no item finished. **Item 12b is in progress** on `item-12-mapping-fix` — uncommitted, with the spike refactored and labelled contact sheets rendered. **Finish it first, then Item 25b.**
- **Pass 22 (2026-10-23, M58)** — four items landed:
  - **Items 24 and 24a are verified.** All four DC landmarks are drawn; the place list has 105 entries and 78 legendaries.
  - **Item 25 (the ruin pass) is built and measures right,** but its proof is incomplete. **The whole-city view never finishes loading in the screenshot harness (F61),** so its zoom-1/16 frame times (F56) and two screenshots are missing.
  - **Item 12's Emerald spike and plan are delivered,** but its mapping draws the wrong pieces (F60) and uses Nintendo names (F59).
  - **Items 25b and 12b fix those first.**
- **Pass 21 (2026-10-22, M56):** Item 23 verified; Item 24's stop on the Lincoln Memorial was diagnosed and fixed in the plan (slice-2 §11.1a).
- **Pass 19 verified the whole pass-18 queue** (Items 13–22; M53) and found four problems: F54–F57 (`ongoing_general_errors.md`, *Verification Findings*).
  - **F54:** two of DC's four enterable landmarks don't show.
  - **F55:** DC's "neighbourhoods" are its 8 political wards.
  - **F56:** the frame targets were stricter than vsync allows, and the whole-city overview drops frames.
  - **F57:** every Godot crash was the agent's own tools launching Godot wrongly.
- **The human's directives since then:**
  - **Decision 29 — Explore Here:** the phone stops tracking. One tap reads the location once, checks it against a bundled **places pack**, and sends only area names.
  - **Decision 30:** a **ruined, overgrown city** instead of fields of houses.
  - **Decision 32:** Generation 8.
  - **Decision 33:** the Glow — Las Vegas's casino society with a dark secret.
- **Decision 34 — the human has supplied ROMs,** so Items 10 and 12 are unblocked:
  - **Emerald:** a clean `BPEE` dump (SHA-1 `f3ae088181bf583e55daf962a92bb46f4f1d07b7`);
  - **Black:** `IRBO`, but a **fan-modified** ROM, so it's accepted for its sprites only.
  - The human gives you the file paths in chat. **Never write them in the repo.**
- **The pass-20 content** — the 30 new legendary places, the Glow, new puzzles and quests — is in the design docs already. This queue builds the parts that belong to Phases 2–3.

**What is approved for build right now:** Items **12b (in progress), 25b, 30, 26, 27, 28, 10, and 29**, in §2's order.
- **They pause at** Items 12b, 25b, 30, 28, and 29, for the human's verdict.
- **Items 27 and 28 land together** (§2).

**What NOT to touch:**
- §13 — already delivered;
- §14 — accepted equivalents;
- §15 — intentional decisions.

§12 is the phase roadmap — scope, not an approved queue.

**Specs are decisions, not suggestions.** Every number, constant, file name, message shape, and literal string here and in the docs it points to is deliberate. Implement as written; do not substitute your own values.
- **If a value is genuinely impossible:** keep the *intent*, deviate minimally, and note it in the commit body.
- **If the design itself cannot work** — including a numeric target that the exact rules miss: **STOP and file it in `docs/ongoing_general_errors.md` with options for the human. Do not improvise or tune silently.**

**Standing constraints (apply to every item):**
1. **The repository is PUBLIC. Never commit, download, or link to a ROM or anything extracted from one** — no `.nds` or `.gba`, sprites, tiles, palettes, text banks, or stat tables, not even in a fixture or a debug PNG. Never help anyone find a ROM.
   - ROMs come only from the human, through `TENTH_SPRING_ROM_BW` and `TENTH_SPRING_ROM_GBA`, which point **outside** the repo. **Their paths are never written in the repo.**
   - **The same holds for the Smogon fan sprites and PokéAPI's data files** (Decision 32): downloaded outside the repo, never committed. Only SHA-256 manifests and credits (dex numbers and artist names) are committed.
   - Mapping tables reference ROM data **by number** only.
2. **Activate the commit hook in your clone before your first commit:** `git config core.hooksPath .githooks`. The local battery fails without it.
3. **Never force-push `main`.** Work on a branch per item, get all workflows green, then fast-forward `main`.
   - **Then delete the item's branch,** locally (`git branch -d <branch>`) and on GitHub (`git push origin --delete <branch>`). Only `main` stays.
   - `git branch -d` refuses a branch that isn't fully merged. If it does, stop and find out why — never force it with `-D`.
   - *(Added 2026-10-22: 29 merged item branches had piled up because nothing deleted them.)*
4. **Tests never write to the player's real state:**
   - the save `user://tenth_spring.db`, plus its `-wal`, `-shm`, `.tmp`, and `.jsonbak` siblings;
   - the identity folder `user://sync_identity/`;
   - the human's demo profile `user://demo/`, including `user://demo/map_data/`.

   Tests use `user://test/…`. The DC profiles the agent makes (`user://measure_dc`, `user://demo_dc`) aren't the human's, and may be created and deleted freely.
5. **The human's location never enters the repo — and that includes place names.**
   - Never commit demo saves, map stores, point files, or screenshots of their area.
   - **Never write the name of their town, neighbourhood, streets, or starter city, or any coordinates of where they live or walk** — not in docs, code, tests, commit messages, or CI logs.
   - **Map-cell numbers (`cx`, `cy`), tile numbers, and Web-Mercator positions of their area count as coordinates.** Report sizes and counts only.
   - Keep all of it in `~/tenth_spring_private/`. Tests use made-up coordinates near (0.01, 0.01) — open ocean.
6. **Heavy commands go through the memory guard:** `python3 -I tools/memguard.py run <step> -- <command>` (`design_memory_and_resources.md` §2). `test_runner.py`, `sync_e2e.py`, and `demo_import.py` wrap themselves.
   - Never run two heavy commands at once, and never leave one running beyond the session.
   - If a step exits **75** (no room) or **76** (stopped for memory), report it — don't retry in a loop.
   - The Mac is shared with other projects that use tens of GB. **Never** deliberately starve it.
7. **Godot on the human's Mac** is at `/Applications/Godot.app/Contents/MacOS/Godot` (4.3-stable), **not** on `PATH`. Set `GODOT_BIN` to it.
   - **Launch Godot only through `tools/godot.py`**, never directly (Item 23, delivered).
   - **In a fresh clone or a new git worktree, import first:** `python3 -I tools/godot.py --memguard-step godot_import --import`. Without the import cache, every `class_name` script fails to parse and the battery fails in confusing ways (F58).
   - **Never run a test file with `--script`** — use `test_runner.py --only <test>`.
   - **Turn off any editor feature that starts Godot by itself** (a Godot extension's language server): two of the four crashes came from one (F57).
8. **Download nothing** except what an item names:
   - **Items 25b, 26, and 30:** the pinned Washington DC snapshot, only if the scratch copy is gone — `https://download.geofabrik.de/north-america/us/district-of-columbia-261001.osm.pbf` and its `.md5` — into a scratch folder outside the repo.
   - **Item 26:** Overpass queries at the pinned date, exactly as `implementation_plan_explore_here.md` §1.2 writes them, ≥ 5 s apart.
   - **Item 29:**
     - PokéAPI's CSV files at one pinned commit;
     - the fan sprites #650–905 and the Mega forms' sprites, from `github.com/PokeAPI/sprites` at one pinned commit — **never** its #1–649 files;
     - the Smogon Sprite Project's public credit sheet.

   Never commit a download. Never fetch `-latest` for game data.
9. **Every change leaves the §1 battery and all CI workflows green** — that is the regression bar. **The one sanctioned exception:** `sync_e2e` between Item 27 and Item 28 (§2).
10. **Anything touching the companion's location access or cross-device sync needs a real-device check** before it's declared done (§2, HUMAN actions).
11. **The golden invariants (§15) stay green, always.**
12. **Detailed behaviour lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
13. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
14. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Name the machine (Linux CI, macOS CI, the human's Mac). Game-side claims count as executed only when a run printed the `PASS` lines.
15. **Proof images come only from the game** (or, for ROM spikes, from the spike tool reading the human's ROM). A picture shown to the human as "this is what the game draws" must be saved by the game's screenshot harness from real data, with the exact command in the commit body or your message. Never present a mock-up as the game's output.
16. **Follow the story.** Any player-facing text, name, or content fits `docs/design_story_and_world.md` and its writing rules (§9). Nothing from Nintendo's stories.
17. **Report against the target, honestly.** When an item names a numeric target, state the measured number next to it. A miss is a miss even if other numbers look fine. (Pass 18 reported 16.67 ms as a "PASS" against a 16.6 ms target, and claimed a gold roof that the screenshot didn't show — F54, F56.)

---

## 1. Verified baseline (run 2026-10-23 in this session, pass 23 — `main` at `6330289`)

| Battery | Where | Result |
|---|---|---|
| `cd companion && flutter analyze` | Mac, local | **No issues found** |
| `python3 -I ../tools/memguard.py run flutter_test -- flutter test` (in `companion/`) | Mac, local | **37 passed, 2 skipped** |
| `python3 game/tests/test_runner.py` | Mac, local | **Executed.** **`[ALL GAME TESTS PASS] All 22 expected tests passed`**, `[REAL SAVE CHECK OK]`, static lint OK, `[CHECK FAMOUS PLACES OK] … 27 cities, 60 sites, 18 spots, 78 legendaries, 9 wardens`, placeholder-atlas tests OK |
| `python3 -I tools/sync_e2e.py` | Mac, local | **Executed, green** — `[OK] Cross-language loopback sync succeeded!` |
| `python3 -I tools/rom_spike/emerald/test_rom_spike.py` (with `TENTH_SPRING_ROM_GBA`) | Mac, local | **7/7 OK on `main`** (pass 22). On Item 12b's uncommitted work it fails with `ImportError: cannot import name 'FEATURED_SECONDARY_TILESETS'` — the refactor renamed it, and 12b rewrites these tests |
| CI on `10e2ed8`, `83949c7`, `b5984d6`, `efc64df`, `6330289` | GitHub | **All green** — `game_tests`, IP guard, `sync_e2e` |
| **DC landmarks** — `check_landmarks.py` | Mac | Library of Congress `placed=1 gold_tiles=308` · Air and Space `288` · Washington Monument `20` · **Lincoln Memorial `placed=1 gold_tiles=54`** |
| **DC ruin pass** — `measure_synth.py` | Mac | `placement_pct=32.5%`; `building_tile_pct=11.1%`; `path_tile_pct=12.8%`; `standing 27.3% · ruined 29.7% · gone 42.9%` (target 20–45%, Decision 37); `rubble 1.7%`; `tall_grass 14.0%`; `landmarks_standing=4/4` |
| **Frame times, windowed, DC, zoom 1** (`--focus waypost`) | Mac | `FRAME_P95_MS 16.67` (≤ 16.7 ✅), `LOAD_MAX_FRAME_MS 20.55` (≤ 33.4 ✅), `VSYNC_MS 16.67` |
| **Frame times, zoom 1/16** | Mac | ❌ **Couldn't run** — the capture never finished in 15 minutes (F61) |
| **The human's ROMs** (header read only) | Mac | Emerald `BPEE`, SHA-1 `f3ae0881…07b7` (the clean dump); Black `IRBO`, **modified** |
| Real-device sync gate | phone + PC | ⚠️ **NOT RUN** — human. At Item 28's pause. |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 12b | **Correct the Emerald mapping (F60), with neutral names (F59) → PAUSE** (this is the human's Item 12 review) — **in progress on `item-12-mapping-fix`; keep that work** | **The real Pokémon look.** Item 30's look-alikes come from this mapping. Already started, so it finishes first. |
| 25b | **The whole-city view finishes loading (F61); frame times at zoom 1/16 (F56); the complete proof v3 → PAUSE** | Item 25 can't be judged without its proof, and every later screenshot at overview zoom hangs until this is fixed. Doesn't depend on 12b. |
| 30 | **Landmark set pieces → PAUSE** (slice-2 plan §12) | Needs Item 24's placement and 24a's interiors (both delivered), and 12b's corrected compositions. |
| 26 | **The places pack — F55** (`implementation_plan_explore_here.md` §1–2; famous-places plan §8.2) | Items 27 and 28 both read the pack. |
| 27 | **Companion: Explore Here** (explore plan §3) | Needs 26. **Shares a branch with 28** — see below. |
| 28 | **PC: explore ingest, migration 3, RevealEngine v2, boot, demo, e2e → PAUSE + real-phone check** (explore plan §4–6) | Needs 26 and 27. |
| 10 | **Black/White sprite spike** — sprites only now (Decision 34) | ROM supplied. Its findings feed Item 29's combined importer plan. |
| 29 | **Gen 8 data pack + fan sprites spike, then `implementation_plan_rom_importer.md` → PAUSE** (Decision 32; pipeline §2a) | Needs 10's findings. Phase 2 can't be coded until its plan is approved (THE LOOP, step 2). |

**Items 27 and 28 share one branch and merge to `main` together, as two commits.** The phone switches to protocol v3 in 27 and the PC in 28, so `tools/sync_e2e.py` is red between them. That's expected, and it must be green again at the end of 28. This is the only sanctioned red gate.

**▶ HUMAN actions:**
- **Give the agent your ROM paths in chat,** to set `TENTH_SPRING_ROM_GBA` (Emerald) and `TENTH_SPRING_ROM_BW` (Black). Never put them in the repo.
- **At Item 25's pause:**
  - the ruined-city screenshots (the art is still the placeholder);
  - the new and changed place rows (name → boundary → Waypost).
- **At Item 12's pause:** the Emerald contact sheets, the fixture preview in real Emerald tiles, and the list of what Emerald lacks.
- **At Item 30's pause:** the landmark set pieces in DC.
- **At Item 28's pause — the real-phone check** (explore plan §6), on your phone and PC:
  1. Pair by QR.
  2. **Set home:** the phone names a starting city.
  3. **Explore Here** inside a famous place (the right message), and outside every one ("isn't on Tenth Spring's map").
  4. **Report to PC:** the Town Map lights the place.
  5. **The phone's Settings** show location access as **While Using**, with no "Always".
  6. **Wireshark** (`tcp.port == 7350`): only TLS records.
  7. **On iOS,** the local-network prompt appears on the first report.
  8. **Address change:** renew the PC's DHCP lease → the unreachable message → re-scan → the next report works without re-pairing.
  9. **A second phone** pairs and replaces the first.

  This closes Phases 0 and 1.
- **At Item 29's pause:** the sprite preview and the importer plan.

Deferred (trigger-gated, **do not start**): §11.

---

## 3. Item 12b — Correct the Emerald mapping (F60), with neutral names (F59) → PAUSE (the human's Item 12 review)

**What this means for the user:** the real Pokémon Emerald look — lawns that are plain grass, ponds with shorelines, tall grass that reads as tall grass — instead of a field of stray objects and striped water.

### Where it stands (pass 23)
- **Uncommitted** on `item-12-mapping-fix`. **Keep this work — don't start over:**
  - `tools/rom_spike/emerald/rom_spike.py` has neutral tileset keys (`sec%02d`) and writes **labelled contact sheets** for the primary and 7 secondary tilesets (`~/.tenth_spring_rom_spike/emerald/*_labelled.png`, indices legible).
- **Not yet done:**
  - `test_rom_spike.py` still imports the old `FEATURED_SECONDARY_TILESETS` and fails with `ImportError`;
  - `build_mapping.py` and the corrected `emerald_tile_map.json`;
  - neutral composition ids;
  - the falsifying checks (step 6);
  - the re-rendered preview;
  - the doc updates;
  - the spike's docstring cites the guide's "§4 (Item 12b)" — it's §3 now.

### The gap
The evidence is `~/.tenth_spring_rom_spike/emerald/preview.png` (the fixture cells in Emerald tiles) and `game/config/emerald_tile_map.json`:
- **`GRASS`** variants 1 and 2 → metatiles 2 and 3, which draw a small grey object and red marks across every lawn;
- **`WATER`**: every mask → 44 or 52, which draws as vertical stripes with no shoreline;
- **`TALL_GRASS`** → 13 and 37, and parts of tall-grass areas draw as round bushes;
- **`GRAVE` and `SIGN`** share 33;
- **`MARSH`** reuses the sand tile (76);
- **`RAIL`** → a road tile (290), although `gaps` lists rail;
- **all eight roof colours** → one roof (521);
- **the spike's checks covered only metatiles 1, 13, and 44;**
- **Nintendo place and facility names as identifiers:** the tileset keys (`petalburg` … `battle_frontier`) and the composition ids (`game_corner`, `contest_hall`, `battle_tower`, `trick_house`, …) (F59).

### Implementation
1. **Labelled contact sheets** — ✅ done in the work in progress. Keep them current if the spike changes.
2. **Choose each class's metatiles by evidence, never by guess.** Use any of these, and record the method in `design_rom_asset_pipeline.md` §4:
   - **the metatile attribute table (behaviour byte)** — tall grass only from tall-grass behaviours, water only from water behaviours;
   - **pixel tests** — a plain-grass variant draws ≥ 90% of its pixels from the base grass metatile's colours;
   - **the ROM's own map layouts, read as statistics only:** count which metatiles border the water interior on each side to find shoreline pieces per mask, and likewise for path edges and tree borders. Nothing from a layout is stored except metatile numbers.
3. **No stand-ins that draw a different object.** A class with no honest Emerald piece goes in `gaps` and keeps its placeholder tile: rail, marsh, snow, and graves if the chosen tilesets have none. Different classes never share a metatile unless the table lists the share as intentional.
4. **Roof colours:** map at least four distinct Emerald roof colourways, if the tilesets have them. If not, record the reason in `gaps`.
5. **Neutral names (F59):**
   - tilesets keyed by index (`"sec05"`);
   - compositions named by function (`casino_hall`, `theatre_hall`, `tall_tower`, `maze_house`, `pyramid_hall`, `dome_centre`, `museum_hall`, `maritime_hall`, `grand_hall`, `stadium`, `elevated_road`, `observatory`, `power_station`, `dept_store`);
   - the spike's comments neutral as well;
   - rename `design_art_direction.md` §1a's table to match. Commit messages and docs describe Emerald by function only.
6. **Falsifying checks** in `tools/rom_spike/emerald/test_rom_spike.py` (ROM-gated) — **run them against today's table first; they must fail:**
   - every `GRASS` variant passes the 90% grass-colour test;
   - every `WATER` mask-15 metatile is ≥ 95% water colours, and a mask with a 0 bit shows shore pixels on that side;
   - every `TALL_GRASS` metatile has the tall-grass behaviour;
   - no unlisted shared metatiles;
   - no `tile_map` entry for a class in `gaps`.
7. **Re-render** the preview of the same fixture cells, plus the labelled contact sheets.
8. **Update `docs/implementation_plan_rom_tiles.md` §3** so these checks are also the importer's validation.
9. **Show the preview and the contact sheets to the human. PAUSE** — this is the Item 12 review.

### Validation
- Every new check passes, and failed on the pass-22 table.
- The new preview shows plain lawns, shorelines, and tall grass. Describe what changed, region by region, when you show it.
- `git status` shows only the spike's code, `emerald_tile_map.json`, and doc changes. The guard exits 0.

### Blast radius (same commit)
`game/config/emerald_tile_map.json` · `tools/rom_spike/emerald/*.py` · `docs/design_rom_asset_pipeline.md` §4 · `docs/design_art_direction.md` §1a · `docs/implementation_plan_rom_tiles.md` §3 · `ongoing_general_errors.md` (F60, F59 → Resolved; Decision 19 status).

---

## 4. Item 25b — The whole-city view finishes loading; honest frame times; the complete proof v3 → PAUSE (F61, F56)

**What this means for the user:** the whole-city view of a famous city loads and stays smooth. And they finally see the full set of ruined-city screenshots, with real numbers, to judge the look.

### The gap
- **The capture never finishes at overview zoom.** `python3 -I tools/demo_screenshot.py --out-dir <outside the repo> --demo-dir user://demo_dc --zoom 0.0625 --focus waypost` ran over 15 minutes in pass 22 with no screenshot, and had to be killed. `--zoom 1` finishes in seconds.
  - The implementing agent's own run before the Item 25 commit ended `failed:120` (memguard log, 2026-10-24T00:08Z).
  - The map view saves only once `pending_cell_count() == 0` (`game/world/map_view.gd:1420-1437`, checked at `:1509`). That count includes `_dirty_overview_chunks.size()`.
  - Every overview blit re-marks its chunk dirty (`:1142`), and `_flush_overview_chunks()` drains at most 4 per call (`:1089`).
- **The harness has no timeout,** so a stall hangs forever instead of failing.
- **Item 25 recorded no frame times and no M-record,** and only 3 of its 5 screenshots exist.

### Implementation
1. **Diagnose.** At zoom 1/16, print the two parts of `pending_cell_count()` — unrendered visible cells, and dirty chunks — every 60 frames. Find the part that never reaches zero, fix the cause, and remove the print.
2. **Add a harness timeout.** If no screenshot is saved within **120 s** of launch, print `[FAIL] screenshot harness: <n> cells and <m> chunks still pending after 120 s` and quit with exit code **3**.
3. **New `map_view_test` case.** At zoom 1/16, on a fixture whose view extends past the store's coverage, `pending_cell_count()` reaches 0 within 600 frames. **Run it against the old code first: it must fail.**
4. **Capture all five slice-2 §11.6 screenshots** in `user://demo_dc` — `shot_ruins_z2_far`, `shot_ruins_z1_far`, `shot_ruins_z2_camp`, `shot_z2_landmark`, and `shot_z0.0625_dc` — outside the repo, and tell the human the paths.
5. **Record Item 25** in `ongoing_general_errors.md` (a new M-number):
   - the §11.4 numbers of the §1 baseline;
   - the frame times at zoom 1 **and 1/16** beside 16.7 / 33.4, with `VSYNC_MS`.
6. **Show the five screenshots to the human,** with the placeholder caveat. **PAUSE** for their verdict on the ruined look.

### Validation
- The new test passes, and failed on the old code.
- Zoom 1/16 finishes with `FRAME_P95_MS` ≤ 16.7 and `LOAD_MAX_FRAME_MS` ≤ 33.4. **Report every number beside its target.**
- A deliberately stalled run (for example, a store path that doesn't exist) fails with exit 3 and the message, instead of hanging.
- The full §1 battery, then every workflow.

### Blast radius (same commit)
`map_view.gd` · `map_view_test.gd` · `tools/demo_screenshot.py` (exit 3 handling) · `ongoing_general_errors.md` (F61 and F56 → Resolved) · slice-2 plan §11.5 ("built").

---

## 5. Item 30 — Landmark set pieces → PAUSE

**What this means for the user:** the Statue of Liberty looks like the Statue of Liberty, and the Lincoln Memorial like the Lincoln Memorial — not a gold-roofed box.

### The gap
- Every landmark is drawn as a gilded building template (`tile_synth2.gd`, §10.8 code).
- There is no stamp art, no register, no class 21, and no renderer path for set pieces.

### Implementation
Exactly **slice-2 plan §12**:
- the register `game/config/landmark_art.json`, checked by `check_famous_places.py`;
- `tools/gen_landmark_stamps.py` and the 14 stamps (`stamps_v1.png`/`.json`), with up to 8 new palette colours;
- the placement rule, with fallback to the gilded template;
- class 21 `STAMP`, with the door as `DOOR` 32;
- the renderer drawing class 21 from the stamp atlas, or from Emerald composition rows once Item 12b's corrected mapping and the tile builder exist.
- **The register's first entries:**
  - every §12.2 stamp, on its interior;
  - an Emerald composition for every §1a look-alike in Item 12b's corrected mapping.

### Validation
- **`tile_synth2_test` (u),** including the falsifying case. The stamps regenerate byte-for-byte.
- **The register check** fails on a planted unknown stamp id.
- **Proof:** DC at zoom 2 — the Lincoln Memorial and the Washington Monument — saved by the harness and shown to the human. **PAUSE.**

### Blast radius (same commit)
`tile_synth2.gd` and test (golden hashes) · `map_view.gd` (class 21) · `tools/gen_landmark_stamps.py` and its test · `game/assets/landmarks/` · `assets/palette/tenth_spring.gpl` · `game/config/landmark_art.json` · `check_famous_places.py` · slice-2 plan §12 ("built").

---

## 6. Item 26 — The places pack (F55)

**What this means for the user:** the phone and the game agree, cell for cell, on every neighbourhood and park. And DC's ~130 real neighbourhoods replace its 8 wards, so revealing the city takes real exploring.

### The gap
- **Neighbourhoods are computed inside the converter,** with `admin_level` 9 or 10 accepted (`game/world/region_import/region_converter.gd:964`, `:1572-1574`, assignment at `:1642-1700`). In DC, that makes the 8 wards the neighbourhoods.
- **There is no shared file** the phone could use.

### Implementation
Exactly **`implementation_plan_explore_here.md` §1–§2** and famous-places plan §8.2:
- `tools/grid.py` and `tools/testdata/grid_vectors.json`, with the vectors asserted in Python and GDScript (Dart comes in Item 27);
- `tools/build_places_pack.py`: Overpass at the pinned date, the cache outside the repo, the three neighbourhood rules, failure on overlaps, canonical gzip;
- the pack at `game/data/places_pack_v1.json.gz`, its `.sha256`, and the identical copy in `companion/assets/`;
- `game/data/PLACES_PACK_NOTICE.md`;
- `game/world/places_pack.gd`;
- the converter copying areas from the pack, with store schema `'5'`;
- the fixture pack and v5 `region_import_test`;
- the export filter;
- the battery checks for the pack's hash and place-id set;
- **re-convert DC.**

### Validation
- **`tools/test_build_places_pack.py`:** every case of §1.5, including the falsifying F55 case (a ward over everything plus three points gives **3** areas).
- **`grid_test.gd`** and `tools/test_grid.py` pass on the same vectors.
- **Two builds** from the cache are byte-identical.
- **The pack's place ids** are exactly the 87 places (27 cities and 60 sites). Report its gzipped size against the 4 MiB limit.
- **DC report:** area count, `T`, and the count by rule — names of public DC neighbourhoods are fine. Expect about 130 point-areas and `T = 5`.
- **`region_import_test` v5** passes; the old v4 assertions on wards are gone.

### Blast radius (same commit)
- `region_converter.gd`, with its neighbourhood code removed, and `map_store.gd` (schema 5);
- `map_view.gd` (skips schema < 5);
- `region_import_test.gd` and its fixtures;
- the new tools, tests, and pack files;
- `test_runner.py` (the pack checks);
- famous-places plan §8.2 ("built");
- `ongoing_general_errors.md` (F55 → Resolved).

---

## 7. Item 27 — Companion: Explore Here (shares a branch with Item 28)

**What this means for the user:** the phone stops tracking them. They tap one big button when they're somewhere new, and it tells them on the spot what they've unlocked.

### The gap
- **Background capture is live:**
  - `companion/lib/capture/` — `os_location_source.dart`, `detector.dart`, `fuzz.dart`, `gpx_replay_source.dart`, `location_source.dart`;
  - `companion/ios/Runner/Info.plist:58-64` (`NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes` → `location`);
  - `companion/android/app/src/main/AndroidManifest.xml:36-38` (background and foreground-service location).
- **The outbox stores coordinates:** `companion/lib/outbox/database.dart:10-17` (`VisitOutbox.lat`/`lon`).

### Implementation
Exactly **`implementation_plan_explore_here.md` §3**:
- remove the capture files, their tests and fixtures, the background permissions, and `VisitOutbox` (Drift v2 migration);
- add `lib/explore/` (`grid.dart`, `places_pack.dart`, `explore_service.dart`, `explore_store.dart`) and the three screens;
- use the result-table messages **verbatim**;
- add Set home;
- switch the report to protocol v3;
- show the pack's attribution in Controls.

### Validation
- **Every test of §3.7**, including the falsifying schema reflection: no `RealColumn` anywhere.
- `flutter analyze` is clean, and `flutter test` passes under memguard.
- **`grep -rn "Always\|BACKGROUND_LOCATION\|UIBackgroundModes" companion/ios companion/android`** finds nothing.
- `sync_e2e` is expected red until Item 28 lands on the same branch.

### Blast radius (same commit)
`companion/lib/**`, `companion/test/**`, `companion/pubspec.yaml`, `companion/ios/Runner/Info.plist`, `companion/android/app/src/main/AndroidManifest.xml`, and `companion/assets/` (the pack).

---

## 8. Item 28 — PC: explore ingest, migration 3, RevealEngine v2, boot, demo, e2e → PAUSE + real-phone check

**What this means for the user:** what the phone discovered appears on the PC by the same rules. No coordinate is stored anywhere. And quitting the game never sends them home for free.

### The gap
- **The ingest takes `bodyFix`** and stores body coordinates (`game/autoloads/sync_server.gd:206-213`, `:361-363`).
- **`DB.insert_visit_log`** writes `0.0` for missing coordinates (`game/autoloads/db.gd:462-463`).
- **Boot routes by the body position** (`game/scenes/main.gd:38`, `:58-74`, `get_boot_place_id()`).
- **The reveal engine** projects visit coordinates and designates home from a cell (`game/world/reveal_engine.gd:93` `designate_home`, `:160` `apply`).
- **`tools/demo_import.py`** imports GPX coordinates (`--gpx`).

### Implementation
Exactly **`implementation_plan_explore_here.md` §4**:
- **protocol v3 ingest**, with `pack_mismatch`, `schema_mismatch`, and `bad_row`, and the key whitelists;
- **NULL coordinates;**
- **save migration 3**, with all five steps;
- **RevealEngine v2** reading explore and home rows and the pack's cells;
- **boot and resume** by `meta('last_place')`;
- **`demo_import.py --points`;**
- **the DC demo profile rebuilt** from public points;
- **`sync_e2e.py` v3**, with the zero-REAL check and the `bad_row` probe.

### Validation
- **Every test of §4.6,** including:
  - the falsifying `reveal_engine_test` (a);
  - the v2 → v3 migration test — no coordinates afterwards, and identical unlocks;
  - the `bad_row` cases.
- **`sync_e2e.py` is green again** on the branch, with every table's REAL columns NULL.
- **`sync_ingest_isolation_test`** is green and unchanged.
- **The full battery and every workflow** are green. **Then merge 27 and 28 to `main` together.**
- **PAUSE** for the human's real-phone check (§2).

### Blast radius (same commit)
- `sync_server.gd`, `db.gd` (migration 3, `insert_visit_log`, and `update_sync_peer`), `reveal_engine.gd`, `main.gd`, and `town_map.gd`/its test;
- `demo_import.py` and `demo_import_server.gd`;
- `sync_e2e.py` and `companion/test/sync_e2e_test.dart`;
- `design_game_state_and_models.md` §4, §8, §9, and the foundation plan's §B notes (explore plan §5);
- the tracking doc: Decision 29 built; Phases 0–1 closed once the human's check passes.

---

## 9. Item 10 — Black/White sprite spike (sprites only — Decision 34)

**What this means for the user:** the first real Pokémon on screen — the battle sprites for #1–649, read from their own cartridge's dump.

### The gap
- The Gen 5 sprite rules in `design_rom_asset_pipeline.md` §4 are **verify**: cell assembly, the per-species layout in `a/0/0/4`, and LZ77 vs LZ11.
- **The human's Black ROM is modified,** so a known-good SHA-1 check would reject it. Since Decision 32 the importer needs only its sprites.

### Implementation
1. **Preconditions.** `TENTH_SPRING_ROM_BW` is set, the file exists, and its real path is **not** inside the repo. Its header code is `IRBO` or `IRAO`. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib** under `tools/rom_spike/`, run with `python3 -I` under `memguard run rom_spike` (measure the budget on the first run).
   - Output goes to `~/.tenth_spring_rom_spike/`.
   - Read by FAT offset; decode one sprite at a time.
   - **Embed no bytes, names, or tables from the ROM.**
3. **Header:** record the game code and the SHA-1. Compare it with the No-Intro DAT, recording the DAT version and source. If it doesn't match, it's "modified — sprites only" (Decision 34).
4. **FNT/FAT:** locate `a/0/0/4` and record its real file count (14,285 in a clean Black). A modified ROM may differ; record what you find.
5. **Sprites:**
   - establish the per-species layout and each file type's compression;
   - assemble the **first frame** of the front sprite for #609 and #94 from NCGR + NCER (+ NCLR, normal and shiny) on a 96×96 canvas;
   - record the exact rule;
   - then **decode all 649 front sprites** and count the failures — the structural check that accepts a modified ROM.
6. **Preview for the human:** #94, #200, #355, #487, #609, and #623 side by side at 2× to `~/.tenth_spring_rom_spike/preview.png`. Tell the human the path; **never commit it.**
7. **Update `design_rom_asset_pipeline.md` §4–5:** replace each sprite **verify** with the confirmed rule, citing the reference or experiment.
8. **No plan yet** — Item 29 writes the combined importer plan.

### Validation
- **Falsifies a wrong decode:** each sprite has ≤ 16 colours per palette, and per-pixel variance above a threshold that a deliberately wrong decode (for example, a wrong XOR seed) fails.
- **649 of 649 front sprites decode,** or the failures are listed with dex numbers. A modified ROM is acceptable only at 649 of 649.
- **Nothing leaked:** `git status` shows only `tools/rom_spike/*.py` and doc changes. The guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/` · `docs/design_rom_asset_pipeline.md` §2, §4–5.

---

## 10. Item 29 — Gen 8 data pack and fan sprites spike, then the importer plan → PAUSE

**What this means for the user:** all 905 Pokémon — Galar's included — with real stats, the Fairy type, Mega forms, and the Smogon artists credited.

### The gap
- Nothing yet downloads, verifies, or parses PokéAPI's data or the fan sprites.
- No manifests or credits exist.
- There is no importer plan for Phase 2.

### Implementation
1. **Pin two commits** — `PokeAPI/pokeapi` and `PokeAPI/sprites` — and record them in `game/config/data_sources.json`, with the date and the licence lines (BSD 3-Clause; Smogon's terms, quoted).
2. **Download into `~/.tenth_spring_data_spike/`** (memguard step `data_spike`):
   - **the CSV files** under `data/v2/csv/` that the importer needs — species, forms, stats, types, abilities, level-up moves, moves, evolutions, type efficacy, items, and the English names;
   - **the Black/White-style sprites** — front, back, shiny, and back shiny — for **#650–905 and the 48 Mega forms only;**
   - **the Smogon Sprite Project's credit sheet.**
3. **Verify the data:**
   - 905 species;
   - the Gen 6+ type chart from type efficacy matches `game/config/type_chart.json`'s planned values (`design_creatures_and_battles.md` §3);
   - the four typing checks of pipeline §7;
   - the learnset rule (pipeline §2a) — record the version-group ids;
   - the move count after the Gen 8 / no-Z / no-Max filter.
4. **Coverage:** list every #650–905 and Mega form that has a sprite, and every one pending — the Gen 8 download predates Legends: Arceus.
5. **Write the committed, repo-safe files:**
   - `game/config/data_pack_manifest.json` and `fan_sprite_manifest.json` — SHA-256 per file;
   - `game/config/fan_sprite_credits.json` — dex number (and form) → artists, with **no species names**;
   - **`CREDITS.md`** — the Smogon Sprite Project, PokéAPI, and the credit sheet's link.
6. **Preview for the human:** fan sprites #650, #700, #750, #800, #850, #887, #888, #889, #890, #898, and #905 (or "pending"), plus one Mega form, at 2× to the spike folder. **Never commit it.**
7. **Write `docs/implementation_plan_rom_importer.md`** at foundation depth, covering all of Phase 2:
   - the Black/White sprite import (Item 10's rules), with modified ROMs for sprites only;
   - the data pack, the fan sprites, and the Mega forms;
   - the first-run download with consent, and the size shown;
   - `asset_db`'s API: `species(dex)`, `move(id)`, `sprite_front(dex, shiny, form)`, `name(kind, id)`, `credits(dex)`;
   - the §7 validation suite;
   - bounded memory;
   - the test strategy, with `TENTH_SPRING_ROM_BW` and `TENTH_SPRING_DATA_PACK` set or skipped explicitly.
8. **PAUSE for human review.**

### Validation
- **Every manifest hash** matches its downloaded file. Re-running the spike from the downloads gives identical manifests.
- **No file under `user://`, the spike folders, or the downloads is tracked.** The guard exits 0.
- **A grep of the committed manifests and credits** for any species name in the English-names CSV finds **none** — the falsifying check that no Nintendo names leaked.

### Blast radius (same commit)
`game/config/data_sources.json`, `data_pack_manifest.json`, `fan_sprite_manifest.json`, and `fan_sprite_credits.json` · `CREDITS.md` · `docs/design_rom_asset_pipeline.md` §2a and §7 (confirmed values) · new `docs/implementation_plan_rom_importer.md` · Decision 32 status.

---

## 11. Deferred — trigger-gated, do NOT start
- **The Phase 2 production importer** — the GDScript modules and the first-run download. **Trigger:** the human approves `implementation_plan_rom_importer.md` at Item 29's pause, and `implementation_plan_rom_tiles.md` at Item 12's.
- **Distort gameplay with a walking avatar** — the real Waypost rule, the hub's Rest, PC Box, and Garden, the arrival and resume banners, and weariness's Waypost beds (`design_travel_and_time.md` §4–5; `design_long_game.md` §4.4). **Trigger:** Phase 4.
- **The battle engine with Gen 8 rules, Mega Evolution, weariness, and fixed-level trainers** (`design_creatures_and_battles.md`; `design_long_game.md`). **Trigger:** Phase 5, after Phase 2 lands. Write its plan first.
- **Famous interiors, the 34 puzzle kinds, doorway searching, the quest engine, the Walker's Journal, and the quest roster** (`design_interiors_and_quests.md`; `content_quest_roster.md`). **Trigger:** Phase 7. Write `implementation_plan_interiors_and_quests.md` first, and pause.
- **Legendary lairs and lore requirements, Warden trials at level 75, survivors, the Glow and its vault, the Ultra Beasts in fields, and the Echo** (`design_famous_places.md` §5–§6; `design_story_and_world.md` §4–§5, §4a–§4b). **Trigger:** Phase 8.
- **Modern street props from Kenney's CC0 packs** (`design_art_direction.md` §2a). **Trigger:** the human approves the Emerald look at Item 12's pause and asks for more street detail.
- **Slice 3** — spawn zones, tall-grass encounters, biomes and regions per cell, Distortion Fields, and ledges. **Trigger:** the human approves the ruined look at Item 25's pause. Write `implementation_plan_world_generation_slice3.md` first, and pause.
- **Widening the map beyond famous places.** **Trigger:** a human request. Explore Here records nothing outside famous places, so players will explore new places when they arrive.
- **Moving `MAP_SNAPSHOT` forward,** and with it a new places pack. **Trigger:** a release the human approves.
- **F58 — the runner could import a fresh checkout itself.** When `game/.godot/` is missing, `test_runner.py` could run `tools/godot.py --memguard-step godot_import --import` first. **Trigger:** an agent or CI job stumbles on a fresh clone again. Until then the README and standing constraint 7 tell you to import.
- **F49 — memguard `run` logs a 0.0 peak for short steps.** **Trigger:** the next change to `tools/memguard.py` — take the first sample after 0.2 s, then every `POLL_SECONDS`.
- **mDNS auto-discovery (F27 d).** **Trigger:** the human reports that re-scanning is a real nuisance.
- **A Windows CI job.** **Trigger:** Phase 10 release prep, or the human playing on Windows.
- **Black 2/White 2 and non-USA ROMs; Generation 9.** **Trigger:** a human request.

---

## 12. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Companion — Explore Here · 1 Sync & models · **2 ROM importer + data pack** · 3 World generation (slices 1–2 built; famous places built; ruins, landmarks, and the places pack in this queue; slice 3 later) · 4 Travel & time (incl. Distort) · 5 Creatures & battles (Gen 8) · 6 Encounters & catching · 7 Exploration, interiors & quests · 8 Haunted zones, legendaries, Wardens, the Glow · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward — or any new slice of one — write its `implementation_plan_*.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9.

---

## 13. Already delivered — do NOT rework
- **Pass 21–22 builds, verified in pass 22 (M57, M58):**
  - **Item 24** — landmarks first, the `building:part` rule, 3 × 3 matching, `check_landmarks.py`; all four DC landmarks drawn;
  - **Item 24a** — `famous_places.json` at 105 entries and 78 legendaries, with the extended checker;
  - **Item 25** — the ruin pass, class 20, bit 16, the overgrowth table, `MEASURE_RUIN`, 8 × 8 overview chunks, `VSYNC_MS`, `--focus=far_buildings` (Item 25b finishes its proof);
  - **Item 12** — the Emerald spike, its tests, contact sheets, `implementation_plan_rom_tiles.md`, and the first draft of `emerald_tile_map.json` (Item 12b corrects the mapping).
- **Pass 20 build, verified in pass 21 (M55, M56):** **Item 23** — `tools/godot.py` (headless by default, an absolute `--path`, refusal of non-`SceneTree` scripts, `--memguard-step`), all nine launch sites switched, `test_runner.py --only`, and the no-direct-launch lint.
- **Phase 0 capture pipeline:** the `LocationSource` seam, `VisitCorridorDetector`, `fuzz.dart`, the Drift outbox, `GpxReplaySource`, and the scout-ledger UI. **Item 27 deletes these by design** (Decision 29) — that's not rework.
- **Early fixes:** F1, F2, F3, F5, F6, F8, F9, F11, F13, F17, F18, F21, F22.
- **Pass 12 build (M12–M15):** the Godot test harness + `game_tests` CI; the IP guard; vendored `godot-sqlite` v4.4 + the real SQLite engine; pinned-TLS pairing and sync; the `sync_e2e` CI workflow.
- **Pass 13 fixes (M16–M20):** F34, F33, F32, F31, F29, F30.
- **Pass 15 build (M21–M24):** F38 memguard, F35, F36, the slice-1 plan.
- **Pass 16 build (M25–M30), verified in pass 17 (M31):**
  - F42 — one Web-Mercator grid;
  - F40 — SQLite on macOS;
  - F41 — memguard;
  - slice 1 (replaced by slice 2's synthesis and renderer).
- **Pass 17 build (M32–M42), verified in pass 18 (M43):**
  - Items 0–3: north-up, USA scope, clip conversion, and the screenshot harness;
  - Item 11: the GBA guard;
  - Items 4–9: slice 2.
- **Pass 18 build (M44–M52), verified in pass 19 (M53):**
  - **Item 13:** minor ways dropped, placement v2, and `measure_synth`;
  - **Item 14:** connected rail art;
  - **Item 15:** the synthesis worker thread;
  - **Item 16:** `--focus`, `VISIBLE_DOORS`, and proof v2;
  - **Item 17:** `famous_places.json` and its checker;
  - **Item 18:** `MAP_SNAPSHOT`/`MAP_SEED`, `--place`, the whole coastline, and store v4 with determinism;
  - **Item 19:** migration 2 and the reveal engine;
  - **Item 20:** the hub, the Town Map, and `Return home`;
  - **Item 22:** gilded landmarks and signs;
  - **Item 21:** the DC proof.

  **Items 24, 25, 26, and 28 *change* parts of these by plan** — landmark placement, synthesis, neighbourhood assignment, and the reveal engine. They don't rewrite them.

## 14. Accepted equivalents — do NOT "fix" these back
- **`get_blob_head()` default mode** falls back from `HEAD:path` to the index (`:path`), so staged-but-uncommitted files are still checked.
- **The IP guard's path rule** also blocks any `roms/` path component — broader than the spec; keep it.
- **`test_f22_save_isolation.py`** stays as a fast static pre-check; the proof is the runner-level snapshot.
- **The legacy import uses the same `ON CONFLICT` upserts** as live writes.
- **`SyncServer.configure_identity()` and `create_dispatcher()`** are dependency-injection seams, not test hooks in the production path.
- **The dispatcher accepts an integral float `seq`/`tsUtcMs`** (Godot's JSON parser returns floats).
- **QR codes use ECC level M.**
- **`_fail_legacy_import(reason)`** is shared by statement failures and count mismatches.
- **PAIR rejects malformed frames with `ERROR protocol`** and doesn't consume the code.
- **Memguard case 5 proves itself in-test** (reruns with `allow_rss_check=False`) instead of on a scratch branch.
- **`COMPRESSION_DEFLATE` reads PBF's zlib blobs.**
- **`demo_import.py` re-runs itself under `memguard run demo_import`** when not already guarded.
- **`ProfilePaths` also accepts `--demo-dir <path>` and `--demo-dir=<path>`.**
- **`map_fetcher.gd` uses `HTTPClient` directly,** not `HTTPRequest`.
- **Decision 20 — `landuse=construction` is not stored.**
- **Camera limits of ±200,000,000 px,** so that any US location is reachable.
- **Item 6's commit message lists template sizes `3×3` and `7×6`;** the code uses the plan's `4×3`, `5×4`, and footprint-sized `block_l`. The code is right.
- **Until Items 27 and 28 delete them:** `relocation_manager.gd`'s minimal-circle snap; `nativeVisits()` returning `null`; `_triggerManualScout` clearing SnackBars; and `buildBatchPayload`'s `"bodyFix": ?bodyFix`.

## 15. Intentional decisions — do NOT change
- **No Nintendo content in the repo, ever.**
  - Species, moves, and items are referenced by number. Names, stats, and sprites come from the player's caches through `asset_db` only.
  - The Smogon fan sprites and PokéAPI data are downloaded on the player's machine, never committed. Only manifests and credits are (Decision 32).
  - **The companion never contains Nintendo assets or names.**
- **Roster and rules** (Decisions 32, 36):
  - **905 species, Gen 1–8;**
  - **Gen 8 battle rules** — 18 types with Fairy; Steel no longer resists Ghost or Dark;
  - **Mega Evolution, one per battle** with the Walker's Keystone, and 47 stones. **No Z-Moves, Dynamax, or Primal Reversion;**
  - **sprites:** #1–649 from the player's Black/White ROM, a modified one accepted for sprites only; #650–905 from the Smogon Sprite Project, credited;
  - **data** from PokéAPI.
- **Two cartridges, separate jobs:** Black/White for sprites #1–649; Emerald for the map's tiles, which must be the clean dump. The placeholder atlas is the permanent no-ROM look.
- **The story is `design_story_and_world.md`:**
  - the finale is the Echo — the player's party **perfected**: +5 levels capped at 100, perfect IVs, and competitive EVs, natures, abilities, items, and movesets — the human's own "stronger mirror" — after all nine Anchors;
  - legendaries and mythicals never appear in Distortion Fields; Ultra Beasts appear only there, after Necrozma;
  - the Pokédex is complete only when every legendary is caught or defeated.
- **The long game** (Decision 35): named battles are **fixed, never relative** — Wardens 75, survivors 50, rematches 80 and 90 — plus weariness. No level caps and no level-flattening.
- **Explore Here** (Decision 29):
  - the phone reads the location only on a tap, checks it against the places pack on the phone, and discards it;
  - **only area keys leave the phone;**
  - no background location, ever.
- **Golden invariant 1 — real exploring unlocks access, never cargo or creatures.** The sync ingest writes only `visit_log` (after Item 28; before it, also `map_cell` and `place_node`). When bag, party, PC box, or Pokémon tables are added, extend the forbidden tokens in `sync_ingest_isolation_test.gd` and `test_runner.py` in the same commit.
- **Golden invariant 2 — coordinates are never stored or sent** (Decision 29). After Item 28, every REAL column in the save is NULL, and the PC refuses any row with a coordinate key.
- **The places pack is the single source of areas** (Item 26): the phone's answers, the PC's unlocks, and the stores' `area_cells` all come from one file.
- **The world is the USA, and the map is famous places only:** 27 cities and 60 parks and wonders. Everything else is never drawn and never downloaded.
- **The grid is Web Mercator, implemented once** — `grid.gd`, with `grid.py` and `grid.dart` held to it by shared vectors. On screen, north is up.
- **The human's place names, coordinates, and ROM paths never enter the repo.** Proof images come only from the game or the ROM spike.
- **The demo never touches the real save or identity,** and each profile reads only its own map data.
- **Memory** (`design_memory_and_resources.md`): heavy work is bounded, admitted only when there's room, and watched while it runs. Budgets are measured, never lowered without `--replace`.
- **Map data is fully offline** (Decision 13 = C): whole regional files the player confirms, read locally. **The game itself never queries Overpass or any service naming a place** — Item 26's Overpass use is development-time only, behind the committed pack. `© OpenStreetMap contributors` is always shown. All HTTP lives in `map_fetcher.gd` (plus the Phase 2 data-pack download), and no network call runs on the main thread.
- **Sync security** (Decision 11): TLS with a pinned self-signed certificate plus a device token. One paired phone per PC; re-pairing never deletes history. ACK means success; every failure is an `ERROR` frame with a code.
- **Storage** (Decisions 6–7): SQLite only, bound parameters only. **The v1 DDL is frozen;** every change is a migration. Migration 3's coordinate removal is the one sanctioned rewrite of `visit_log`.
- **Pillar rules:**
  - Distort from home to the starter city and to places explored for real; home only from a Waypost or by blackout;
  - **a session resumes where the last one ended** — the phone never moves you;
  - healing only at home; blackout drops the bag, never Pokémon; the map and Pokédex always persist.
- **The same map for everyone** (Decision 23): `MAP_SNAPSHOT` pinned, fixed conversion units, the whole coastline kept, and `MAP_SEED` global — **including the ruin pass and stamps.**
- **The ruin target** (Decision 37): 20–45% of ordinary buildings gone over a city's built-up cells; DC measures 42.9%.
- **The ruined world** (Decision 30): building fates come from `MAP_SEED` and the distance to the Waypost. **Landmarks always stand; places of worship always stand; hospitals are ruined, never gone.**
- **Anything enterable has a purpose** (Decision 27), and every puzzle has an in-world reason. Ordinary buildings are searched from the doorway. **Casinos may appear, but nothing simulates betting** (Decision 33).
- **Legendaries get one decisive battle,** at their own place behind a challenge. Every lore requirement is "caught or defeated", so no choice can lock a player out. Wardens appear only once their region's three cities are unlocked.
- **Minor ways are never drawn.** Buildings come before footpaths, and roads before buildings. **Landmarks come before every other building** (after Item 24). Synthesis never runs on the main thread.
- **Stack:** Godot 4.3 (PC; Decision 31 = A) + Flutter (companion). No Steam, no monetization.

## 16. Where the contracts live
| Need | Doc |
|---|---|
| Pillars, stack, setup | `README.md` |
| Phase order + tuning constants | `docs/master_implementation_plan.md` |
| Phases 0–1 build steps, v1 DDL, TLS sync (Part A retired) | `docs/implementation_plan_foundation.md` |
| **Explore Here** — the places pack, the companion, the PC's unlocks (Items 26–28) | `docs/implementation_plan_explore_here.md` |
| Slice 1 of world generation | `docs/implementation_plan_world_generation.md` |
| **Slice 2** + §10 (pass 18) + **§11 ruins, landmarks first, frame targets** + **§12 landmark set pieces** | `docs/implementation_plan_world_generation_slice2.md` |
| **What the map contains** — 27 cities, 60 parks, the 78 legendary places and their backstories, Wardens, unlocking, Distort | `docs/design_famous_places.md` |
| Building famous places (Items 17–21) + **§8 pass-19/20 amendments** (Items 24a, 26, 28) | `docs/implementation_plan_famous_places.md` |
| Enterable buildings, the 34 puzzle kinds, the 78 lair challenges, side quests | `docs/design_interiors_and_quests.md` |
| The 110 city quests and 60 park quests | `docs/content_quest_roster.md` |
| The backstory, Calder's nine rules, the regions, **the Glow** | `docs/design_story_and_world.md` |
| **The long game** — fixed levels, weariness, swollen bosses | `docs/design_long_game.md` |
| ROMs, the data pack, fan sprites, formats, legal + repo guardrails | `docs/design_rom_asset_pipeline.md` |
| Stats, types (Gen 8), weariness, Mega Evolution, catching, party | `docs/design_creatures_and_battles.md` |
| Spawn zones, fields, levels, haunted zones, legendaries, Wardens, the Echo | `docs/design_encounters_and_haunted_zones.md` |
| Art sources, landmarks, free libraries and credits, the rip trap | `docs/design_art_direction.md` |
| Explore Here → areas → tiles; tall grass; ruins | `docs/design_world_generation.md` |
| Schemas, storage, the grid | `docs/design_game_state_and_models.md` |
| Travel, clock, Distort, resume, stranded | `docs/design_travel_and_time.md` |
| Companion scope, pairing, protocol | `docs/design_companion_and_sync.md` |
| Privacy | `docs/design_privacy_and_location.md` |
| Memory guards | `docs/design_memory_and_resources.md` |
| Decisions, findings, history | `docs/ongoing_general_errors.md` |
| Manual E2E journeys | `docs/e2e_testing_journeys.md` |

---

## THE LOOP (repeat per item)
```
1 STUDY     Read this item + the design_*.md / implementation_plan_*.md sections it names.
            Specs are decisions.
2 PLAN      Building a phase or slice with no approved implementation_plan_*.md? Write one FIRST
            and PAUSE for human review. (Items 24–30 implement approved plans: slice-2 §11–§12,
            famous-places §8, explore-here §1–§4. Items 10, 12, and 29 are spikes that end in plans.)
3 IMPLEMENT Exactly as written, on a branch. Honor §15 and the standing constraints — above all:
            no Nintendo content or fan sprites in the repo; none of the human's places or ROM paths;
            no test touches the real save, identity, or demo profile; Godot only through
            tools/godot.py; never force-push main.
            LOCAL: one file that a command can check (a port, a data table, boilerplate, unit tests
            for a pure function) may go to the local model — code-gen or unit-test-gen with
            --verify-cmd (and --mutate for tests). Read what it wrote before you commit it.
4 VALIDATE  This item's validation (run the falsifier against the OLD code first), then the full §1
            battery on the Mac with GODOT_BIN, then every workflow on GitHub, Linux and macOS. Report
            each numeric target beside its measured value. Map pictures come only from the harness.
            RED GATE: do not start the next item on a failing one (sole exception: sync_e2e
            between Items 27 and 28 on their shared branch).
            LOCAL: when a run fails, re-run it as test-triage --cmd "<the command>". It prints the
            failure lines verbatim from the whole log plus a checked summary, so you needn't read the
            raw log. Its summary is a lead, not the result.
5 BLOCKED?  Spec wrong, impossible, docs conflict, a target missed with the rules exactly
            implemented, a decision blank, a lookup that finds no boundary, a ROM check that fails →
            STOP. File in ongoing_general_errors.md with options.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design doc whose
            behavior changed — in the same commit.
            LOCAL: doc-sync can draft the M-record and the commit body. Every number in the draft
            must come from your inputs; pass --ran-on to say where the checks ran.
7 COMMIT    One Conventional Commit per item, WHY in the body. Fast-forward main, then delete the
            item's branch locally and on GitHub (standing constraint 3).
            LOCAL: before committing, qa-diff --spec <the item's plan> --spec-section "<its heading>"
            screens the whole change, new files included. Its exact-rule findings are certain; its
            model findings are leads to check, not instructions.
```

**The `LOCAL` steps (the human's Mac only; optional).** They save cloud quota by handing bounded, checkable work to the local model (`qwen3-coder:30b` in Ollama). Use the `local-orchestrator` skill (Claude Code and Antigravity both have it); its script is `~/.gemini/config/plugins/tenth-spring/skills/local-orchestrator/scripts/orchestrate.py`, run from the repo root.
- **Its output is advisory, never evidence.** "Statically checked" and "executed" still come only from the §1 battery, CI, and your own reading (standing constraint 14). Never cite `visual-qa` as proof (standing constraints 15 and 17).
- **It takes the memory-guard lock itself** for each model call (standing constraint 6).
- **Subagents queue; they don't run in parallel.** Every model call takes the same machine-wide lock, whether it comes from a subagent or from Antigravity, and runs alone. A call that waits more than 2 minutes exits 75. So keep the `LOCAL` calls in one agent — yourself or a single subagent — and tell the others not to call the local model.
- **Never let two agents generate the same file.** A second one is refused. Batch `visual-qa` calls: each switch between the code and vision models reloads about 20 GB from the SSD.
- **Exit 3, 4, 75 or 76 means do that step yourself.** Don't retry in a loop. 75 is normal when the Mac is busy.
- **Never pull, delete, or swap models** (standing constraint 8). That is the human's call.

## Definition of Done (this build)
- [x] **HUMAN: Decisions 29–37 answered** (2026-10-21 to 2026-10-23).
- [x] **Item 23 (F57)** — `tools/godot.py`; every launcher switched; `test_runner --only`; the falsifying refusal passes (verified pass 21, M56).
- [x] **Item 24 (F54)** — landmarks first, plus §11.1a; all four DC landmarks `placed=1`, `gold_tiles > 0` (verified pass 22, M58).
- [x] **Item 24a** — `famous_places.json` at 105 entries and 78 legendaries; the checker extended (verified pass 22, M58).
- [x] **Item 25** — the ruin pass built and measured (M58). Its proof is finished in 25b.
- [x] **Item 12** — the Emerald spike, verify markers resolved, the plan written (M58). Its mapping is corrected in 12b.
- [ ] **Item 12b (F60, F59)** — *in progress*; — evidence-based mapping, honest gaps, neutral names, falsifying checks; the new preview and labelled contact sheets **shown; paused** (the human's Item 12 review).
- [ ] **Item 25b (F61, F56)** — the whole-city view loads; the harness times out instead of hanging; frame times at zoom 1 and 1/16 beside their targets; five screenshots **shown; paused.**
- [ ] **Item 30** — the register, 14 stamps, class 21; DC proof **shown; paused.**
- [ ] **Item 26 (F55)** — the places pack built, bundled twice, and hash-checked; DC re-converted with real neighbourhoods; `T` reported.
- [ ] **Item 27** — Explore Here on the companion; no background permission anywhere; no real-number column.
- [ ] **Item 28** — protocol v3, migration 3, RevealEngine v2, resume, explore-point demos; `sync_e2e` green; 27 and 28 merged together; **paused.**
- [ ] **HUMAN: the real-phone check passes** (§2) — **closes Phases 0 and 1.**
- [ ] **Item 10** — sprite rules confirmed; 649/649 decode from the human's ROM; preview shown.
- [ ] **Item 29** — pinned sources, manifests, credits, `CREDITS.md`; coverage listed; preview shown; `implementation_plan_rom_importer.md`; **paused.**
- [ ] The full §1 battery and every CI workflow (Linux and macOS) are green.

**When all of the above are checked, this build's queue is empty. Do NOT invent work.** Legitimate triggers for more:
- a new item in `ongoing_general_errors.md` with a filled `Your selection:`;
- the human's verdict at a pause;
- the §1 battery or any CI workflow regressing;
- a §11 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
