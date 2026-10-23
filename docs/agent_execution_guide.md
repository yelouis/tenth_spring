# Agent Execution Guide — Active Build: Launch Safety, Landmarks, the Ruined City, the Real Emerald Look, Explore Here, and Generation 8 (verified 2026-10-22, pass 20; Decisions 29–36 answered)

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

**What is approved for build right now:** Items **23, 24, 24a, 25, 12, 30, 26, 27, 28, 10, and 29**, in §2's order.
- **They pause at** Items 25, 12, 30, 28, and 29, for the human's verdict.
- **Items 27 and 28 land together** (§2).

**What NOT to touch:**
- §16 — already delivered;
- §17 — accepted equivalents;
- §18 — intentional decisions.

§15 is the phase roadmap — scope, not an approved queue.

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
   - **After Item 23, launch Godot only through `tools/godot.py`**, never directly.
   - **Never run a test file with `--script`** — use `test_runner.py --only <test>`.
   - **Turn off any editor feature that starts Godot by itself** (a Godot extension's language server): two of the four crashes came from one (F57).
8. **Download nothing** except what an item names:
   - **Items 24, 25, 26, and 30:** the pinned Washington DC snapshot — `https://download.geofabrik.de/north-america/us/district-of-columbia-261001.osm.pbf` and its `.md5` — into a scratch folder outside the repo.
   - **Item 24a:** public place-name lookups on `https://nominatim.openstreetmap.org/search`, ≥ 1.1 s apart, with the plan's `User-Agent`. Public names only.
   - **Item 26:** Overpass queries at the pinned date, exactly as `implementation_plan_explore_here.md` §1.2 writes them, ≥ 5 s apart.
   - **Item 29:**
     - PokéAPI's CSV files at one pinned commit;
     - the fan sprites #650–905 and the Mega forms' sprites, from `github.com/PokeAPI/sprites` at one pinned commit — **never** its #1–649 files;
     - the Smogon Sprite Project's public credit sheet.

   Never commit a download. Never fetch `-latest` for game data.
9. **Every change leaves the §1 battery and all CI workflows green** — that is the regression bar. **The one sanctioned exception:** `sync_e2e` between Item 27 and Item 28 (§2).
10. **Anything touching the companion's location access or cross-device sync needs a real-device check** before it's declared done (§2, HUMAN actions).
11. **The golden invariants (§18) stay green, always.**
12. **Detailed behaviour lives in `docs/design_*.md` (contracts) and `docs/implementation_plan_*.md` (build steps).** This guide tells you how to build and prove each item; where it quotes a contract, the contract wins.
13. **One item = one Conventional Commit**, WHY in the body. Record the resolution in `ongoing_general_errors.md` as part of the item.
14. **Say what actually ran.** "Source-verified," "statically checked," and "executed" are three different claims. Name the machine (Linux CI, macOS CI, the human's Mac). Game-side claims count as executed only when a run printed the `PASS` lines.
15. **Proof images come only from the game** (or, for ROM spikes, from the spike tool reading the human's ROM). A picture shown to the human as "this is what the game draws" must be saved by the game's screenshot harness from real data, with the exact command in the commit body or your message. Never present a mock-up as the game's output.
16. **Follow the story.** Any player-facing text, name, or content fits `docs/design_story_and_world.md` and its writing rules (§9). Nothing from Nintendo's stories.
17. **Report against the target, honestly.** When an item names a numeric target, state the measured number next to it. A miss is a miss even if other numbers look fine. (Pass 18 reported 16.67 ms as a "PASS" against a 16.6 ms target, and claimed a gold roof that the screenshot didn't show — F54, F56.)

---

## 1. Verified baseline (run 2026-10-22 in this session, HEAD `0f84697` plus doc-only changes)

| Battery | Where | Result |
|---|---|---|
| `cd companion && flutter analyze` | Mac, local | **No issues found** |
| `python3 -I ../tools/memguard.py run flutter_test -- flutter test` (in `companion/`) | Mac, local | **37 passed, 2 skipped** (`sync_e2e_test`, `demo_import_test` — run only through their tools) |
| `GODOT_BIN=… python3 game/tests/test_runner.py` | Mac, local | **Executed.** IP guard and self-tests, isolation audit, memguard, synthetic PBF, demo-screenshot, placeholder-atlas and famous-places tests, vendored SHA-256, harness self-test → **`[ALL GAME TESTS PASS] All 22 expected tests passed`**, `[REAL SAVE CHECK OK]`, static lint OK. *(The `ERROR` lines in its log are its own negative tests — injected legacy-import and migration failures.)* |
| `GODOT_BIN=… python3 -I tools/sync_e2e.py` | Mac, local | **Executed, green.** `E2E_SENT rows 14` → `visit_log 14, last_applied_seq 14, map_cell 3, place_node 1`; `[OK] Cross-language loopback sync succeeded!` |
| CI on `0f84697` | `game_tests` 39726058576, IP guard 39726058569, `sync_e2e` 39726058546 | **All green** — `game_tests` on Linux and macOS |
| **DC placement** (pass 18, Item 13) | Mac | 136,325 candidates → **32.5% placed**; building tiles **18.9%**; path tiles **16.6%** |
| **DC landmarks** (pass 19, read-only check) | Mac | Library of Congress **placed 0 of 2 candidates**; Lincoln Memorial **gold tiles 0**; Air and Space **240**; Washington Monument **10** — F54 |
| **Frame times** (pass 18, Items 15, 21) | Mac, windowed | zoom 1: `FRAME_P95_MS` 16.67; whole-city zoom 1/16: **18.06** and `LOAD_MAX_FRAME_MS` **33.33** — F56 |
| **DC neighbourhoods** (pass 18, Item 18) | Mac | **9 areas** — DC plus Wards 1–8 — so 2 wards unlock the city (F55) |
| **Godot crash reports** (pass 19) | Mac | 4 reports, one stack: `Main::start()` → `OS_MacOS::alert()` → abort. Two from an editor's `language_server`, two from scripts running a test file directly (F57) |
| **The human's ROMs** (pass 20, header read only) | Mac | Emerald `BPEE`, SHA-1 `f3ae0881…07b7` (the clean dump); Black `IRBO`, **modified** (not a retail dump) |
| Real-device sync gate | phone + PC | ⚠️ **NOT RUN** — human. Folded into Item 28's pause. |
| ~~D3 device soak~~ | — | **Retired** with background capture (Decision 29) |

---

## 2. Execution order

| # | Item | Why this position |
|---|---|---|
| 23 | **Launch wrapper + `test_runner --only` — F57** ✅ **DONE** (`tools/godot.py`, `--only`, static lint) | Every later item launches Godot. This stops the crashes first. |
| 24 | **Landmarks first — F54** (slice-2 plan §11.1) | Synthesis change. The ruin pass (25) must never hide a landmark, and DC's proof must show all four. |
| 24a | **The place list, revised:** the pass-19 swaps, the 30 Gen 6–8 places, the Glow's six interiors, and `requires` (`implementation_plan_famous_places.md` §8.1) | Data only. Items 25 and 30 render interiors from this list. The human reviews the new rows at Item 25's pause. |
| 25 | **The ruin pass + frame targets + overview chunks + DC proof v3 → PAUSE** (slice-2 plan §11.2–11.7; F56) | Needs 24. Adds the tile vocabulary that Item 12's mapping table must cover. |
| 12 | **Emerald tile spike + mapping table + tile-importer plan → PAUSE** (Decision 19; ROM supplied) | **This is what makes the map look like real Pokémon.** Its mapping must include Item 25's new tiles, and the look-alike compositions Item 30 needs. |
| 30 | **Landmark set pieces → PAUSE** (slice-2 plan §12) | Needs 24's placement, 24a's interiors, and 12's compositions. |
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

Deferred (trigger-gated, **do not start**): §14.

---

## 3. Item 23 — Launch wrapper and `test_runner --only` (F57)

**What this means for the user:** no more Godot crash pop-ups while the agent works. Every crash so far came from the tools launching Godot the wrong way.

### The gap
- **Every launcher builds its own Godot command,** with a *relative* `--path game` that breaks when the working directory isn't the repo root:
  - `tools/map_convert.py:67-68,108-109`;
  - `tools/measure_synth.py:53-54`;
  - `tools/demo_import.py:96`;
  - `tools/demo_screenshot.py:132`;
  - `tools/sync_e2e.py:39`;
  - `game/tests/test_runner.py:287,308`.
- **Nothing stops a test file being run directly.** `godot --script tests/x.gd` aborts in a window, because the test isn't a `SceneTree` script — that's the `tile_synth2_test` abort in the memguard log (10-21 16:16Z).
- **There is no way to run one test** without running all 22.

### Implementation
1. **New `tools/godot.py`** (Python stdlib, `python3 -I`):
   - **Resolve `GODOT_BIN`.** If it's unset or not executable, print `godot.py: set GODOT_BIN to your Godot 4.3 binary` and exit 2.
   - **Always pass an absolute** `--path <repo root>/game`.
   - **Always pass `--headless`,** unless `--windowed` is given (the screenshot harness passes it).
   - **Refuse `--script <file>`** unless the file's first non-comment, non-blank line is `extends SceneTree` or `extends MainLoop`. Print `godot.py: refusing --script <file>: it doesn't extend SceneTree or MainLoop — run tests with game/tests/test_runner.py --only <name>` and exit 2.
   - **Pass every other argument through** unchanged, print the exact command it runs, and return Godot's exit code.
   - **`--memguard-step <name>`** runs it under `tools/memguard.py run <name>`, for callers that aren't already guarded. Never wrap twice.
2. **Switch all nine launch sites above to `tools/godot.py`.** No other file may contain `"--path", "game"` or call `GODOT_BIN` directly — add that check to the static lint in `test_runner.py`.
3. **`game/tests/test_runner.py --only <test name>`:**
   - passes `--only=<name>` to `res://tests/test_main.tscn`, and the harness runs just that entry of `EXPECTED`;
   - it still runs the real-save check;
   - an unknown name prints `test_runner: no test named <name> (see EXPECTED)` and exits 2.
4. **README → Setup notes:** a short "Launching Godot" paragraph with rule 7 of the standing constraints.

### Validation
- **Falsifying:** `python3 -I tools/godot.py --script res://tests/tile_synth2_test.gd` exits 2 with the refusal message, **and no Godot window or crash report appears**. On the old code, the same direct run aborts.
- `python3 game/tests/test_runner.py --only tile_synth2_test` prints exactly one test `PASS` line plus the real-save check.
- `--only nonexistent` exits 2 with the message.
- The static lint fails on a planted `"--path", "game"` in a scratch copy of a tool.
- The full §1 battery and every workflow are green.

### Blast radius (same commit)
The nine launch sites · `game/tests/test_main.gd` (the `--only` filter) · `README.md` · `ongoing_general_errors.md` (F57 → Resolved).

---

## 4. Item 24 — Landmarks first (F54)

**What this means for the user:** every enterable landmark actually shows on the map, gilded, with its sign — starting with the Library of Congress, which today isn't drawn at all.

### The gap
- **Landmarks go through the ordinary placement rules,** after every larger building has taken its space (`game/world/tile_synth/tile_synth2.gd`, the loop before `:875`). The Library of Congress's two buildings are rejected outright.
- **The door must lie exactly inside the placed template** (`:888-892`), so the Lincoln Memorial — placed, but with its door point just outside — is never gilded.

### Implementation
Exactly **slice-2 plan §11.1**:
- find each landmark's footprint (door inside, else within 2 store units);
- place landmarks **before** the ordinary loop, allowing `PATH` underneath, with 21 nudges and then shrink-to-fit;
- gild at placement time;
- `stats` gains `landmarks_placed` and `landmarks_sign_only`;
- new `tools/check_landmarks.py` with `res://scenes/check_landmarks.tscn`, launched through `tools/godot.py` (memguard step `check_landmarks`).

### Validation
- **`tile_synth2_test` (p)** — the falsifying fixture, the door 2 tiles outside, and the shrink case (§11.7). Run (p) against the old code first: it must fail.
- **Acceptance on DC:** `check_landmarks.py --store <DC store> --place city:washington-dc` prints `placed=1` and `gold_tiles > 0` for all four DC interiors. Report every line.
- `measure_synth` on DC still runs. Report placement and tile percentages beside the pass-18 numbers (they may move slightly).

### Blast radius (same commit)
`tile_synth2.gd` · `tile_synth2_test.gd` and its golden hashes, saying why they changed · `tools/check_landmarks.py` and its scene · slice-2 plan §11.1 ("built") · `ongoing_general_errors.md` (F54 → Resolved).

---

## 5. Item 24a — The place list, revised

**What this means for the user:** the 30 new legendary places of Generations 6–8, the lake trio in their right homes, Las Vegas's Glow, and every lore requirement become real data the game can use.

### The gap
`game/config/famous_places.json` still has:
- 75 entries;
- the old lake-trio placement;
- Theodore Roosevelt NP holding Zapdos;
- Salem Maritime and Russell Cave;
- no Gen 6–8 places;
- no `requires`;
- pass 18's Las Vegas interiors.

### Implementation
Exactly `implementation_plan_famous_places.md` §8.1. The rows are `design_famous_places.md` §1.2 and §9, and the interiors `design_interiors_and_quests.md` §4.1–§4.2.
- **Look up** each new boundary relation (or closed way), Waypost, and interior door with Nominatim — public names only, ≥ 1.1 s apart.
- **The Glow's vault door** is the centre of the Fremont Street canopy.
- **Churchill Downs** gains `L P`.
- **Update `tools/check_famous_places.py`** as §8.1 lists:
  - 105 entries, and 78 distinct legendaries;
  - region counts 7–9;
  - `requires` keys from §9 only, and no circular chain.

### Validation
- The checker passes on the new file.
- **Falsifying unit tests** (`tools/test_check_famous_places.py`):
  - a `requires` naming a non-legendary dex fails;
  - a duplicated legendary fails;
  - a region with 6 legendaries fails;
  - an unknown `requires` key fails.
- **Report** the new and changed rows as a table (name → relation or way id → Waypost name), for the human at Item 25's pause.

### Blast radius (same commit)
`game/config/famous_places.json` · `tools/check_famous_places.py` and its tests · famous-places plan §8.1 ("built").

---

## 6. Item 25 — The ruin pass, honest frame targets, overview chunks, and proof v3 → PAUSE

**What this means for the user:** the cities look emptied — houses fallen in or gone to grass, side streets overgrown, tidy blocks around the survivors' camps — instead of a census of every house. And the whole-city view stops stuttering.

### The gap
- **No building ever ruins or disappears:** every placed building is drawn whole (`tile_synth2.gd`, §4.2 painting).
- **There is no `RUBBLE` class,** no broken variants, and no overgrowth by distance.
- **The whole-city overview** keeps one `Sprite2D` per cell (`game/world/map_view.gd:1022-1030`, `:1044-1052`) — 4,469 for DC — and measured `FRAME_P95_MS` 18.06.
- **The frame target of 16.6 ms** is below the 60 Hz vsync interval (16.67).

### Implementation
Exactly **slice-2 plan §11.2–11.6**:
- the band from the Waypost (`area["waypost_wm"]`, passed by the map view and the worker);
- building fates, fixed fates, and the ruined and gone drawing;
- the overgrowth table;
- salts 9–14;
- class 20 `RUBBLE`, variant bit 16, and `PATH`/`PLAZA` variant 1;
- the atlas rows, regenerated byte-identically;
- `MEASURE_RUIN`;
- the new frame targets and `VSYNC_MS`;
- 8 × 8-cell overview chunks;
- `--focus=far_buildings`;
- the five proof screenshots in `user://demo_dc`.

### Validation
- **`tile_synth2_test` (q)–(t)**, including the falsifying (r) against the old code. The atlas regenerates byte-identically.
- **`measure_synth` on DC:** report every §11.4 measure beside its target, including building tiles 10–16%, gone 20–40%, ruined 20–35%, tall grass ≥ 8%, and landmarks all standing.
  - **A miss means STOP:** file it with the numbers, and don't tune.
- **Frame times on the human's Mac,** in the DC profile:
  - zoom 1 and zoom 1/16;
  - `FRAME_P95_MS` ≤ 16.7 and `LOAD_MAX_FRAME_MS` ≤ 33.4;
  - plus `VSYNC_MS`.
  - Report all of them beside their targets. 1/16 was 18.06 before.
- **Show the five screenshots and Item 24a's rows to the human.** Say plainly that the art is still the placeholder until the Emerald import. **PAUSE.**

### Blast radius (same commit)
- `tile_synth2.gd` and its test, with golden hashes;
- `tools/gen_placeholder_atlas.py`, `placeholder_v1.png`/`.json`, and `assets/palette/tenth_spring.gpl`;
- `map_view.gd`, `synth_worker.gd`, `tools/demo_screenshot.py`, `tools/measure_synth.py`, and `screenshot_args_test.gd`;
- slice-2 plan §11 ("built");
- `ongoing_general_errors.md` (F56 → Resolved; Decision 30 built).

---

## 7. Item 12 — Emerald tile spike, mapping table, and tile-importer plan → PAUSE

**What this means for the user:** the moment the map stops looking like placeholder art and starts looking like a real Pokémon game. It's the change they've asked for since pass 17.

### The gap
- Every Emerald format rule in `design_rom_asset_pipeline.md` §4 is still **verify**.
- No mapping exists from the slice-2 tile vocabulary — now including `RUBBLE`, bit 16, the overgrown variants, and class 21 `STAMP` — to Emerald metatiles.
- No look-alike compositions exist for the landmarks (`design_art_direction.md` §1a).

### Implementation
1. **Preconditions.** `TENTH_SPRING_ROM_GBA` is set, the file exists, and its real path is **not** inside the repo. Its header is `BPEE` and its SHA-1 is `f3ae088181bf583e55daf962a92bb46f4f1d07b7`. If any check fails, STOP and report. **Never download, search for, or link to a ROM.**
2. **Write the spike in Python 3 stdlib** under `tools/rom_spike/emerald/`, run with `python3 -I` under `memguard run rom_spike_gba` (measure the budget on the first run).
   - Output goes to `~/.tenth_spring_rom_spike/emerald/`, outside the repo.
   - **The code embeds no bytes, images, or tables taken from the ROM** — only offsets, sizes, and metatile numbers.
3. **Find the tilesets** through the ROM's own pointer tables: the primary tileset and the secondary tilesets. Record every offset and structure size, and how you found it.
   - Cite documentation, such as the community decompilation project's source *as a reference*.
   - Never use a downloaded ROM or extracted asset.
4. **Decode** the tile graphics (LZ77 type `0x10`), palettes, metatiles, and attributes. Replace each Emerald **verify** in `design_rom_asset_pipeline.md` §4 with the confirmed rule.
5. **Contact sheets for the human:** the primary tileset's metatiles at 2×, plus the secondary tilesets for 4–6 differently themed towns. They include the buildings named in `design_art_direction.md` §1a: the pyramid hall, the space centre, the battle tower, the museums, the contest hall, the department store, the game corner, the weather institute, the power plant, the league hall, the stadium, the cycling road, and the trick house. Saved to the spike folder; tell the human the paths. **Never commit them.**
6. **Draft `game/config/emerald_tile_map.json`** — numbers only:
   - **for every `(class, variant, mask)`** the synthesizer emits — including `RUBBLE` 0–1, the bit-16 broken `ROOF`/`WALL`/`DOOR`, and `PATH`/`PLAZA` variant 1 — the metatile to use;
   - **the building compositions** for `house_s`, `house_m`, and `block_l`, and each roof colour;
   - **`compositions`:** one look-alike per row of `design_art_direction.md` §1a, as `{"<id>": {"w", "h", "metatiles": [...], "door": [col, row]}}`;
   - **`gaps`:** everything Emerald lacks — snow, for example.
7. **Preview from synthetic data only:**
   - a test helper dumps the fixture cells' slice-2 buffers to `user://test/fixture_cells.bin`;
   - the spike renders them in Emerald tiles to `~/.tenth_spring_rom_spike/emerald/preview.png`, including a ruined house, a gone lot, and an overgrown street;
   - show it to the human, and never commit it.
8. **If the templates don't fit** Emerald's buildings, write the smallest amendment to slice-2 plan §4.2 that does, and include it in the review. Don't change the synthesizer yet.
9. **Write `docs/implementation_plan_rom_tiles.md`** at foundation depth. Cover:
   - `gba_rom.gd`, `gen3_tiles.gd`, and `tile_atlas_builder.gd`, which also renders `compositions` into atlas rows for class 21 (slice-2 plan §12.3);
   - `asset_db.tile_atlas()`;
   - the resumable cache write;
   - `design_rom_asset_pipeline.md` §7's tile checks;
   - the test strategy — ROM tests run only when `TENTH_SPRING_ROM_GBA` is set, and are skipped with an explicit message otherwise.
10. **PAUSE for human review.**

### Validation
- **Decode check:** every decoded tile uses ≤ 16 colours from its palette. The grass, tall-grass, and water metatiles pass a pixel-variance threshold that a wrong decompression or palette fails — prove it by running the check against a deliberately wrong palette.
- **Coverage:** the mapping table covers every `(class, variant)` in the placeholder JSON, or lists it under `gaps`. Every §1a row has a composition, or a `gaps` entry.
- **Nothing leaked:** `git status` shows only `tools/rom_spike/emerald/*.py`, `game/config/emerald_tile_map.json`, and doc changes. The guard exits 0.

### Blast radius (same commit)
`tools/rom_spike/emerald/` · `game/config/emerald_tile_map.json` · `docs/design_rom_asset_pipeline.md` §4 · new `docs/implementation_plan_rom_tiles.md` · the slice-2 plan amendment (if any) · Decision 19 status.

---

## 8. Item 30 — Landmark set pieces → PAUSE

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
- the renderer drawing class 21 from the stamp atlas, or from Emerald composition rows once Item 12's builder exists.
- **The register's first entries:**
  - every §12.2 stamp, on its interior;
  - an Emerald composition for every §1a look-alike that Item 12 drafted.

### Validation
- **`tile_synth2_test` (u),** including the falsifying case. The stamps regenerate byte-for-byte.
- **The register check** fails on a planted unknown stamp id.
- **Proof:** DC at zoom 2 — the Lincoln Memorial and the Washington Monument — saved by the harness and shown to the human. **PAUSE.**

### Blast radius (same commit)
`tile_synth2.gd` and test (golden hashes) · `map_view.gd` (class 21) · `tools/gen_landmark_stamps.py` and its test · `game/assets/landmarks/` · `assets/palette/tenth_spring.gpl` · `game/config/landmark_art.json` · `check_famous_places.py` · slice-2 plan §12 ("built").

---

## 9. Item 26 — The places pack (F55)

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

## 10. Item 27 — Companion: Explore Here (shares a branch with Item 28)

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

## 11. Item 28 — PC: explore ingest, migration 3, RevealEngine v2, boot, demo, e2e → PAUSE + real-phone check

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

## 12. Item 10 — Black/White sprite spike (sprites only — Decision 34)

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

## 13. Item 29 — Gen 8 data pack and fan sprites spike, then the importer plan → PAUSE

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

## 14. Deferred — trigger-gated, do NOT start
- **The Phase 2 production importer** — the GDScript modules and the first-run download. **Trigger:** the human approves `implementation_plan_rom_importer.md` at Item 29's pause, and `implementation_plan_rom_tiles.md` at Item 12's.
- **Distort gameplay with a walking avatar** — the real Waypost rule, the hub's Rest, PC Box, and Garden, the arrival and resume banners, and weariness's Waypost beds (`design_travel_and_time.md` §4–5; `design_long_game.md` §4.4). **Trigger:** Phase 4.
- **The battle engine with Gen 8 rules, Mega Evolution, weariness, and fixed-level trainers** (`design_creatures_and_battles.md`; `design_long_game.md`). **Trigger:** Phase 5, after Phase 2 lands. Write its plan first.
- **Famous interiors, the 34 puzzle kinds, doorway searching, the quest engine, the Walker's Journal, and the quest roster** (`design_interiors_and_quests.md`; `content_quest_roster.md`). **Trigger:** Phase 7. Write `implementation_plan_interiors_and_quests.md` first, and pause.
- **Legendary lairs and lore requirements, Warden trials at level 75, survivors, the Glow and its vault, the Ultra Beasts in fields, and the Echo** (`design_famous_places.md` §5–§6; `design_story_and_world.md` §4–§5, §4a–§4b). **Trigger:** Phase 8.
- **Modern street props from Kenney's CC0 packs** (`design_art_direction.md` §2a). **Trigger:** the human approves the Emerald look at Item 12's pause and asks for more street detail.
- **Slice 3** — spawn zones, tall-grass encounters, biomes and regions per cell, Distortion Fields, and ledges. **Trigger:** the human approves the ruined look at Item 25's pause. Write `implementation_plan_world_generation_slice3.md` first, and pause.
- **Widening the map beyond famous places.** **Trigger:** a human request. Explore Here records nothing outside famous places, so players will explore new places when they arrive.
- **Moving `MAP_SNAPSHOT` forward,** and with it a new places pack. **Trigger:** a release the human approves.
- **F49 — memguard `run` logs a 0.0 peak for short steps.** **Trigger:** the next change to `tools/memguard.py` — take the first sample after 0.2 s, then every `POLL_SECONDS`.
- **mDNS auto-discovery (F27 d).** **Trigger:** the human reports that re-scanning is a real nuisance.
- **A Windows CI job.** **Trigger:** Phase 10 release prep, or the human playing on Windows.
- **Black 2/White 2 and non-USA ROMs; Generation 9.** **Trigger:** a human request.

---

## 15. Phase roadmap — scope, not an approved queue

Full list, contracts, and exit criteria: **`docs/master_implementation_plan.md`**. Order:

0 Companion — Explore Here · 1 Sync & models · **2 ROM importer + data pack** · 3 World generation (slices 1–2 built; famous places built; ruins, landmarks, and the places pack in this queue; slice 3 later) · 4 Travel & time (incl. Distort) · 5 Creatures & battles (Gen 8) · 6 Encounters & catching · 7 Exploration, interiors & quests · 8 Haunted zones, legendaries, Wardens, the Glow · 9 Art & UI · 10 Privacy, balance & release.

**Rule:** before coding any phase from 2 onward — or any new slice of one — write its `implementation_plan_*.md` at foundation depth and pause for human review (THE LOOP, step 2). Phase 2 must land before Phases 5–9.

---

## 16. Already delivered — do NOT rework
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

## 17. Accepted equivalents — do NOT "fix" these back
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

## 18. Intentional decisions — do NOT change
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
- **The ruined world** (Decision 30): building fates come from `MAP_SEED` and the distance to the Waypost. **Landmarks always stand; places of worship always stand; hospitals are ruined, never gone.**
- **Anything enterable has a purpose** (Decision 27), and every puzzle has an in-world reason. Ordinary buildings are searched from the doorway. **Casinos may appear, but nothing simulates betting** (Decision 33).
- **Legendaries get one decisive battle,** at their own place behind a challenge. Every lore requirement is "caught or defeated", so no choice can lock a player out. Wardens appear only once their region's three cities are unlocked.
- **Minor ways are never drawn.** Buildings come before footpaths, and roads before buildings. **Landmarks come before every other building** (after Item 24). Synthesis never runs on the main thread.
- **Stack:** Godot 4.3 (PC; Decision 31 = A) + Flutter (companion). No Steam, no monetization.

## 19. Where the contracts live
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
3 IMPLEMENT Exactly as written, on a branch. Honor §18 and the standing constraints — above all:
            no Nintendo content or fan sprites in the repo; none of the human's places or ROM paths;
            no test touches the real save, identity, or demo profile; Godot only through
            tools/godot.py (after Item 23); never force-push main.
4 VALIDATE  This item's validation (run the falsifier against the OLD code first), then the full §1
            battery on the Mac with GODOT_BIN, then every workflow on GitHub, Linux and macOS. Report
            each numeric target beside its measured value. Map pictures come only from the harness.
            RED GATE: do not start the next item on a failing one (sole exception: sync_e2e
            between Items 27 and 28 on their shared branch).
5 BLOCKED?  Spec wrong, impossible, docs conflict, a target missed with the rules exactly
            implemented, a decision blank, a lookup that finds no boundary, a ROM check that fails →
            STOP. File in ongoing_general_errors.md with options.
6 RECORD    Move the item's findings to Resolved with what-was-solved; update any design doc whose
            behavior changed — in the same commit.
7 COMMIT    One Conventional Commit per item, WHY in the body. Fast-forward main, then delete the
            item's branch locally and on GitHub (standing constraint 3).
```

## Definition of Done (this build)
- [x] **HUMAN: Decisions 29–36 answered** (2026-10-21 and 2026-10-22).
- [ ] **Item 23 (F57)** — `tools/godot.py`; every launcher switched; `test_runner --only`; the falsifying refusal passes.
- [ ] **Item 24 (F54)** — landmarks first; all four DC landmarks `placed=1`, `gold_tiles > 0`.
- [ ] **Item 24a** — `famous_places.json` at 105 entries and 78 legendaries; the checker extended; rows reported.
- [ ] **Item 25** — the ruin pass; every §11.4 measure reported beside its target; frame targets met with `VSYNC_MS`; five screenshots **shown; paused.**
- [ ] **Item 12** — Emerald verify markers resolved; `emerald_tile_map.json` with the ruin tiles, compositions, and gaps; contact sheets and preview shown; `implementation_plan_rom_tiles.md`; **paused.**
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
- a §14 trigger firing;
- the human assigning something.

Otherwise report that the queue is complete and stop.
