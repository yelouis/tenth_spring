# Ongoing General Errors & Engineering History

## Overview
This document tracks decisions, open findings, and the engineering record for Tenth Spring. The design contracts are the `docs/design_*.md` files.
- **Open decisions** come first, each with its options and a `Your selection:` line.
- **Once answered,** a decision moves to *Resolved Decisions* as a short entry: the answer, the date, and the contracts it changed. The options not chosen are dropped.
- **Findings** are numbered F1, F2, …, and **work records** M1, M2, …. Numbers are never reused.
- **Keep new records short:** what changed, the proof, and what is left. Full logs and measurements go in the commit body.

**Condensed 2026-11-01.** Resolved decisions and work records are summarised here. The full earlier text, with every option, measurement, and log, is in git history: `git show 7290149:docs/ongoing_general_errors.md`.

---

## 🟠 Open Decisions — waiting for you

**No decision is open** (2026-11-01). You answered Art 0, Art D1–D6, the Item 12 plan, F62, and F63 that day; they are Decisions 38–45 below, and F62 and F63 under *Verification Findings*.

### Things only you can do (not decisions)
- **The real-device sync gate (Phase 1's exit).** This is ready now: the five steps in agent guide §2.
- **Explore Here on a real phone (Phase 0's exit),** at Item 28's pause. The nine steps are in agent guide §2.
- **Tier 2 art run** (the 14 monuments and the ruined city block): paste the prompt in `docs/art_brief/ART_BRIEF.md` into Antigravity once it's written (ask Claude). Its sprites come back to you for approval before Item 30 uses them.

---

## 🔎 Verification Findings — open, for the next agent
- **F63 (minor) — a capture can hang after its screenshot is saved,** waiting for steady frames that never arrive (once, with the window not being presented). **You chose B (2026-11-01):** the steady-frame wait gets the same time limit and exits 3 with its own message. **Agent guide Item 25c.** If it keeps happening after that, re-ask the human.
- **F62 (minor) — a `far_buildings` capture spends about 85 s in its focus scan, and the timeout can't see that wait.** **You chose to leave it (2026-11-01):** pass `--timeout 300` for `far_buildings` captures. **If it keeps happening** (a capture fails with exit 3 while nothing is stuck), **re-ask the human** with the other two options: skip the first scan when the harness repeats it after `load_place`, or cache the focus choice for the run.
- **F58 (minor) — a fresh checkout fails the battery until Godot imports the project.** Without `game/.godot/`, `class_name` scripts don't parse. Run `python3 -I tools/godot.py --memguard-step godot_import --import` first, as CI does (README → *Launching Godot*; guide constraint 7). Having the runner do the import itself is deferred (guide §11).
- **F55 — DC's "neighbourhoods" are its 8 political wards.** The rule takes `admin_level` 9 first (`implementation_plan_famous_places.md` §3.1a), so DC has 8 huge neighbourhoods instead of its ~130 real ones, and 2 wards unlock it. Fix: **agent guide Item 26** (the places pack).
- **F49 (minor, deferred) — memguard logs a peak of 0.0 GiB for steps shorter than its 2 s poll** (`POLL_SECONDS`, `tools/memguard.py`). Safe, but the log is misleading (guide §11).
- **F39 — the ROM-import half is open:** the importer needs its memory limit (≤ 512 MiB, `design_memory_and_resources.md`). Scheduled for **agent guide Item 10**. The converter half was resolved in M29.
- **F27(d) (deferred) — mDNS auto-discovery on the LAN.** v1 connects by remembered address plus a QR re-scan (guide §11).
- **F7 — retired by Decision 29.** No home location reaches the PC at all.

---

## ✅ Resolved Decisions
Newest first. Each entry gives the answer and where it lives. The options not chosen are dropped (git history has them).

- **Decision 46 — Tier 2 gets 10 rounds, and art runs share the Mac (2026-11-01; your directive).**
  - **10 rounds:** Tier 2 allows 10 rounds of 4 images per asset, as Tier 1 does (raised from 3).
  - **Sharing the Mac:** an art run may run while another job, from another system, uses the Mac. It never stops that job: it runs alongside when memory allows, and queues otherwise.
  - **How:** `memguard run --parallel` (`design_memory_and_resources.md` §2; M65), and the Tier 2 prompt in `docs/art_brief/ART_BRIEF.md`.
- **Decision 45 — The Emerald tile import plan is approved (2026-11-01; the Item 12 verdict).** `implementation_plan_rom_tiles.md` is approved as written. It is built in Phase 2 with the importer plan from Item 29 (agent guide §11).
- **Decision 44 — Several signature features per park, made by the local image model (2026-11-01; art brief D6, amended by you).**
  - **Several per site** (Old Faithful, Grand Prismatic Spring, and the Lower Falls at Yellowstone, not one view), each at a fixed lat/lon and placed like a set piece.
  - **The art** comes from the local image model (Qwen-Image-2512), through the art brief, under Decision 39.
  - **Next:** a plan section with the feature list (agent guide Item 34). It replaces the art brief's 51 one-per-site views.
- **Decision 43 — Ruined houses are drawn with the house sprites (2026-11-01; art brief D5).**
  - A ruined building gets a house sprite in state A (neglected) or B (broken), chosen by its distance from the Waypost.
  - A gone building gets state C (the collapsed shell), or grass with decals.
  - A `block_l` building gets the repeatable `ruined_block`.
  - **Next:** the amendment to slice-2 §11.2 (agent guide Item 32), then the build (Item 33).
- **Decision 42 — Monument stamps come from approved images (2026-11-01; art brief D4).**
  - The 14 stamps of slice-2 §12.2 become committed PNGs with provenance, instead of being drawn by `tools/gen_landmark_stamps.py`.
  - **The Library of Congress is the 15th stamp:** 22 × 14 tiles, enterable as the Archive of the Stillness.
  - The visitor centres and site structures join the register.
  - **Next:** the amendment to slice-2 §12 (agent guide Item 32), then Item 30.
- **Decision 41 — Outlines are a dark shade of each object's own colour, never near-black (2026-11-01; art brief D3).** This replaces slice-2 §12.2's `#1a1a20` (`design_art_direction.md` §1a, §3).
- **Decision 40 — Each original sprite has its own palette of at most 16 colours, in 15-bit colour (2026-11-01; art brief D2).** This is how Emerald's tiles work. The 64-colour master palette stays for the code-drawn placeholder tiles only (`design_art_direction.md` §3).
- **Decision 39 — AI-made images may be final game art, with conditions (2026-11-01; art brief D1).** Each image must be:
  - validated by the art tools;
  - approved by you;
  - recorded in provenance with its model and licence;
  - credited as AI-assisted in `CREDITS.md`;
  - made by a model whose licence allows it. Qwen-Image-2512 (Apache 2.0) does; Qwen-Image 2.1 (research-only) doesn't.

  Contract: `design_art_direction.md` §5. The procedure is `docs/art_brief/ART_BRIEF.md`.
- **Decision 38 — The Tier 1 art is approved (2026-11-01; art brief "Art 0").** All 26 sprites in `docs/art_brief/tier1_selection.json`: 9 ruined houses, 16 decals, and the Library of Congress. They enter the repo in agent guide Item 31.
- **Art direction for ruins and landmarks (2026-10-26/27, at the Item 25 and Item 12 pauses).** The placeholder told you little. You saw the same views drawn with Emerald tiles and judged that the ruins and landmarks "still don't look right". So: **new original art,** generated locally and validated against the Emerald look (`docs/art_brief/`, a draft). This replaced the overlay-and-art-library path of M60 and M61. You answered its questions on 2026-11-01 (Decisions 38–44).
- **Decision 37 — Accept 43% of ordinary buildings gone (2026-10-23).** The §11.4 "gone" target widened from 20–40% to 20–45%. No code changed (slice-2 §11.4).
- **Decision 36 — Mega Evolution only (2026-10-22).** One Mega per battle, using the Walker's Keystone. There are 47 Mega Stones, each earned through late-game content; Mega Rayquaza needs none, and Wardens' aces can Mega Evolve. No Z-Moves, no Dynamax, no Primal Reversion (`design_creatures_and_battles.md` §16).
- **Decision 35 — The long game: survival plus mastery (2026-10-22).**
  - **Wardens:** every Warden fields a fixed level-75 team with competitive builds and the strongest AI, whatever your levels.
  - **No relative levelling:** no level caps and no level-flattening.
  - **Survival:** fog-swollen bosses, smarter opponents, and weariness on long trips, on top of home-only healing and scarce PP.
  - **The Echo** is at level 100 (the cap), and its edge is the build: perfect IVs, competitive EVs, natures, items, and movesets.
  - **The agent's reading, which stands unless you change it:**
    - city survivors are fixed at level 50;
    - Old Friends rematches are at 80, and Warden rematches at 90;
    - wild levels rise to 65–85 at 2,000 miles or more.
  - **Contract:** `design_long_game.md` §4. The ideas not chosen stay in its §3.
- **Decision 34 — Your ROMs are on your machine (2026-10-22).**
  - The Emerald file is a clean `BPEE` dump.
  - The Black file is a fan-modified `IRBO`, so it's accepted **for the #1–649 sprites only**, after structural checks, and shows "modified ROM — sprites only".
  - The paths are set on your machine in `TENTH_SPRING_ROM_GBA` and `TENTH_SPRING_ROM_BW`, and are never written in the repo.
- **Decision 33 — Las Vegas casinos are back, as the Glow (2026-10-22).**
  - The Glow is a working casino society under the Fremont Street canopy, whose lights are stolen from the desert towns by Necrozma, held in a vault.
  - Its games are skill and logic only, never betting. The Glow Arena runs rotating rules.
  - Casinos are now allowed; memorials to tragedies, active worship, burial grounds, and sacred Native sites stay excluded.
  - **Contracts:** `design_story_and_world.md` §4b and `design_interiors_and_quests.md` §4.1.
- **Decision 32 — Pokémon through Generation 8 (2026-10-22; supersedes Decision 12's Gen 1–5).**
  - **Species:** 905. The 82 legendaries and mythicals wait at 78 famous places, and the 11 Ultra Beasts appear only in Distortion Fields.
  - **Sprites:** #1–649 come from your Black/White ROM. #650–905 are the Smogon Sprite Project's fan sprites (non-profit use, credit required).
  - **Data:** all species' data comes from PokéAPI (BSD 3-Clause, a pinned commit).
  - **Never committed:** the fan sprites and the data are downloaded on the player's machine.
  - **Battles** follow Gen 8 rules, including the Fairy type.
  - **Contracts:** `design_rom_asset_pipeline.md`, `design_creatures_and_battles.md`, `design_famous_places.md` §1.2/§1.4.
- **Decision 31 — Stay with Godot (2026-10-22).** The four crashes were the agent's tools launching Godot wrongly (F57), fixed by the launch wrapper (Item 23). ROM-hack systems (tile behaviours, event scripting, data-driven trainers) are adopted as *designs* to reimplement.
- **Decision 30 — Civilization is gone (2026-10-21; answers Decision 28).**
  - Each ordinary building gets a fixed fate, the same for every player: **standing**, **ruined**, or **gone**. Fates are tidier near the Wayposts, large buildings mostly stand, and **enterable landmarks always stand**.
  - Streets crack and grow over.
  - The 45% placement target is retired, and the §11.4 ruin targets replace it (slice-2 §11, Item 25).
- **Decision 29 — Explore Here: the phone doesn't track you (2026-10-21; supersedes Decisions 3, 5, and 21).**
  - **One reading:** the phone asks for location only while the app is in use, and only on a tap of **Explore Here**. It takes one reading, checks it against a bundled **places pack**, and discards it.
  - **Only area names leave the phone,** never coordinates.
  - **Set home** sends only the nearest famous city's name.
  - **Sessions resume where they ended.**
  - **Contracts:** `design_companion_and_sync.md`, `design_privacy_and_location.md`, and `implementation_plan_explore_here.md`. Built in Items 26–28.
- **Decision 28 — Building-placement target (2026-10-21).** Answered by Decision 30.
- **Decision 27 — Enterable famous buildings and abundant side quests (2026-10-20).**
  - **Interiors:** 71 city interiors and 36 park visitor centres, plus the legendary lairs. Each has at least two purposes.
  - **Puzzles:** Pokémon-style puzzle kinds (34 after pass 20).
  - **Quests:** about 210 side quests, including 9 Truth quests that end in Dr. Ruth Calder's logs.
  - **Ordinary buildings** are searched from the doorway, not entered (the agent's call, which you can override).
  - **Contract:** `design_interiors_and_quests.md`.
- **Decision 26 — Famous parks, Warden gating, and one chance at each legendary (2026-10-20).**
  - **Parks:** visiting anywhere in a park unlocks all of it.
  - **Legendaries:** each one waits behind a challenge that's the same for every player. A finished battle (caught or defeated) ends that chance forever.
  - **Wardens** appear only once all three of their region's cities are unlocked, each at one fixed landmark.
  - **Regions:** each has its own story and three named survivors.
  - **Contracts:** `design_famous_places.md` §1.2, §5, and §6, and `design_story_and_world.md` §4a.
- **Decision 25 — Famous places only; home is a hub; Distort (2026-10-20).**
  - **The map:** 27 famous cities (3 per region) plus the famous parks.
  - **Home** is an off-map hub.
  - **Distort:** from home, free, to the famous city nearest you and to any place you've physically visited. You arrive at its Waypost, and can Distort home only from a Waypost.
  - **Contract:** `design_famous_places.md` §1–§4.
- **Decision 24 — Leave the leaked map-cell value in git history (2026-10-20).** No history rewrite and no force-push. The guide's privacy rule now names cell coordinates.
- **Decision 23 — The same map for everyone: on-PC conversion from one pinned snapshot (2026-10-20; supersedes Decision 15).** There are four rules:
  1. one pinned snapshot per release (`MAP_SNAPSHOT = 2026-10-01`);
  2. each famous place is converted as a fixed unit;
  3. the whole coastline is always kept;
  4. one global map seed (`MAP_SEED = 0`).

  Contract: `design_famous_places.md` §7.
- **Decision 22 — A city reveals after `T` of its neighbourhoods (2026-10-20).** `T = 1` for a single neighbourhood, otherwise `clamp(ceil(0.10 × n), 2, 5)` (`design_famous_places.md` §3.2).
- **Decision 21 — Any movement reveals a neighbourhood (2026-10-20).** Superseded by Decision 29: a tap of Explore Here is the only trigger.
- **Decision 20 — Exclude `landuse=construction` from the map store (2026-10-20)** (slice-2 §2.1).
- **Decision 19 — Real map tiles from the player's Emerald ROM (2026-10-19).**
  - Players also dump Pokémon Emerald (`BPEE`). The repo holds metatile numbers only (`game/config/emerald_tile_map.json`).
  - The code-drawn placeholder atlas stays: it's the no-ROM look, and the only atlas tests see.
  - The IP guard blocks GBA game codes (M36).
  - The mapping was chosen by evidence (M60), and the import plan was approved (Decision 45).
  - **Contracts:** `design_rom_asset_pipeline.md` and `design_art_direction.md` §1.
- **Decision 18 — Completing the game (2026-10-19).**
  - **A new story:** the Stillness, the Distortion, and the Walkers (`design_story_and_world.md`).
  - **Nine Warden trials,** one per Census division, in any order. All nine are required.
  - **The finale is the Echo,** a mirror of your party (its level rules are now Decision 35). Giratina is an ordinary legendary.
  - **Distortion Fields** bring any non-legendary species anywhere, rarely. A full Pokédex needs every legendary caught or defeated.
- **Decision 17 — Real streets, rebuilt from Pokémon pieces (2026-10-19).** The slice-2 plan was approved as written: 8 WM-m tiles, roads and paths, roofed buildings with doors, and tree borders (`implementation_plan_world_generation_slice2.md`).
- **Decision 16 — The USA only (2026-10-19).** The 50 states, DC, Puerto Rico, and the US Virgin Islands. Everywhere else is "beyond the map".
- **Decision 15 — Pre-converted hosted map stores (2026-10-15).** Never built, and superseded by Decision 23.
- **Decision 14 — Build the neighbourhood map preview: the full plan (2026-10-10)** (`implementation_plan_world_generation.md`, Items 3–10).
- **Decision 13 — Fully offline OpenStreetMap data (2026-10-09).**
  - The PC downloads map data and converts it locally, so no request ever names a place you've been.
  - Map files never enter the repo.
  - OSM attribution is always shown.
- **Decision 12 — Gen 1–5 from the start (2026-10-08).** Superseded by Decision 32.
- **Decision 11 — Sync encryption: Godot's built-in TLS with a pinned certificate (2026-10-08).**
  - The pairing QR carries the PC certificate's SHA-256 fingerprint, and the phone trusts nothing else.
  - A 256-bit device token authenticates the phone; the PC stores only the token's hash.
  - This replaces libsodium (Decision 4's crypto half).
  - **Contract:** `design_companion_and_sync.md` §2–3.
- **Decision 10 — Black/White sprites for all 649 (2026-10-09).** Platinum dropped. Amended by Decision 19 (Emerald for tiles) and Decision 32 (fan sprites for #650+).
- **Decision 9 — Base ROM Platinum (2026-10-08).** Superseded by Decisions 10 and 12.
- **Decision 8 — Single-player only for v1 (2026-10-08).** No server and no accounts.
- **Decision 7 — An agent vendors `godot-sqlite` v4.4 (MIT), and CI proves it loads (2026-10-08).** Desktop binaries are committed under `game/addons/godot-sqlite/` with a SHA-256 manifest (M14).
- **Decision 6 — Real SQLite storage (July 22).** Delivered through Decision 7 (M14).
- **Decision 5 — When to run the battery soak (July 22).** Retired by Decision 29.
- **Decision 4 — Crypto and mDNS libraries (July 21).** Superseded: the crypto half by Decision 11, and the mDNS half by F27 (deferred).
- **Decision 3 — Background location capture (July 21).** Retired by Decision 29.
- **Decision 2 — Build the GPX replay harness in Phase 0 (July 21)** (`implementation_plan_foundation.md` §A8).
- **Decision 1 — The stack: Godot 4 on the PC and Flutter on the phone, with LAN-only, end-to-end encrypted sync (July 21).** There's no server in v1.

---

## 🧪 Resolved Issues & Implementation Refinements
One line per work record. Each lists the findings it resolved; the full records are in git history (see *Overview*) and in the commit bodies.

**Phases 0–1: foundation and sync**
- **M1** (July 22) — Phase 0 phone capture built (`implementation_plan_foundation.md` §A). Background capture was later retired by Decision 29.
- **M2** (July 22) — relocation maths, one grid projection, and transactions with rollback (F1, F2, F3, F5, F6).
- **M3** (July 22) — background capture closed out (F8, F9). Retired by Decision 29.
- **M4** (July 22) — SQLite store, the §B2 schema, and the §B6 migrations. The claim was premature; real SQLite arrived in M14 (F4).
- **M5** (July 22) — the first transport and pairing code: primitives only. Replaced by TLS (Decision 11, M15).
- **M6** (July 22) — an atomic write and backup recovery for the world file (F11).
- **M7** (2026-10-07) — the public-repo IP guard (F18).
- **M8** (2026-10-07) — persistence restored with an atomic temp-file swap, and a null query fails loudly (F11, F13).
- **M9** (2026-10-07) — retired zombie config keys, and loaded the Pokémon constants (F17).
- **M10** (2026-10-07) — IP guard bypasses closed (F21).
- **M11** (2026-10-07) — tests can't touch the real save (F22).
- **M12** (2026-10-08) — real headless Godot tests in CI (F25).
- **M13** (2026-10-08) — IP guard: merge, tip-tree, hook check, and the Gen 4–5 prefixes (F24, F28).
- **M14** (2026-10-08) — the real SQLite engine through vendored godot-sqlite v4.4, with bound parameters; the file fallback is retired (F4, F10, F16, F19, F20, F23, F26; Decision 7).
- **M15** (2026-10-08) — pinned-TLS sync, pairing, scout reports, and cross-language loopback sync in CI (F12, F14, F15, F27(a–c); Decisions 4 and 11).
- **M16** (2026-10-09) — fuzzed-fix enforcement, and stale fixes refused (F34).
- **M17** (2026-10-09) — re-pairing after an unpair works (F33).
- **M18** (2026-10-09) — storage failures surface as `ERROR storage`, never as success (F32).
- **M19** (2026-10-09) — a failed legacy import closes the database and protects the backup (F31).
- **M20** (2026-10-09) — a runner-level save snapshot, and an evil-merge test (F29, F30).
- **M21** (2026-10-10) — the developer-tooling memory guard, `tools/memguard.py` (F38; `design_memory_and_resources.md`).
- **M22** (2026-10-10) — legacy import order, and unreadable saves (F35).
- **M23** (2026-10-10) — a fresh one-shot fix for Scout Here (F36).

**Phase 3, slice 1: the map preview**
- **M24** (2026-10-10) — the slice-1 plan, and the PBF speed spike (Item 3). Verified with corrections in pass 16.
- **M25** (2026-10-14) — one Web Mercator grid (F42).
- **M26** (2026-10-14) — SQLite loads on macOS (F40).
- **M27** (2026-10-14) — memory-guard fixes (F41).
- **M28** (2026-10-14) — the 60 m corridor reveal (F37).
- **M29** (2026-10-15) — the region converter, the map store, and the converter gate. Washington took about 61 min against a 30 min limit, which opened Decision 15 (F39, converter half).
- **M30** (2026-10-19) — tile synthesis, the Map View, and the region download: slice 1 complete (Items 8–10).
- **M31** (2026-10-19, pass 17) — slice 1 verified, with corrections (F43–F48 filed; F48 fixed).
- **M32** (2026-10-19) — north is up (F43, Item 0).
- **M33** (2026-10-19) — the USA scope and the download mechanics (Decision 16; F44, F45(a, b, c, e); Item 1).
- **M34** (2026-10-19) — clip conversion, store coverage, and profile isolation (F46, F50; Item 2).
- **M35** (2026-10-19) — the screenshot harness, and honest windowed frame times (F47; Item 3).
- **M36** (2026-10-20) — the IP guard blocks GBA ROMs (Item 11; Decision 19).

**Phase 3, slice 2: Pokémon pieces, famous places, and ruins**
- **M37** (2026-10-20) — scale and Map Store v2 (Item 4).
- **M38**, **M39** (2026-10-20) — synthesis, parts 1 and 2 (Items 5 and 6).
- **M40** (2026-10-20) — the placeholder atlas (Item 7).
- **M41** (2026-10-20) — renderer v2 (Item 8).
- **M42** (2026-10-20) — slice-2 proof screenshots, and camera limits (Item 9).
- **M43** (2026-10-20, pass 18) — Items 0–9 and 11 verified, with corrections (F51–F53 filed).
- **M44** (2026-10-20) — minor ways dropped, and building placement v2 (F51; Item 13).
- **M45** (2026-10-20) — connected rail art (F53; Item 14).
- **M46** (2026-10-20) — synthesis moved to a background worker (F52; Item 15).
- **M47** (2026-10-20) — proof v2 in Washington DC (Item 16).
- **M48** (2026-10-20) — the famous-places list (Item 17). *Its summary misworded the legendaries; the data is right (corrected in M53).*
- **M48** (second record, 2026-10-21) — the same map for everyone, and place-store schema v4 (Decision 23; F45(d); Item 18).
- **M49** (2026-10-21) — Item 19: schema version 2 (`area_reveal`, `distort_list`, the home meta) and `RevealEngine`.
- **M50** (2026-10-21) — Item 20: the home hub screen and the Town Map.
- **M51** (2026-10-21) — Item 22 verified: gold roofs, highlighted doors, and name signs on enterable buildings.
- **M52** (2026-10-21) — Item 21: Washington DC converted from the pinned snapshot into place store v4, and the `user://demo_dc` profile.
- **M53** (2026-10-21, pass 19) — Items 13–22 verified, with corrections (F54–F57 filed).
- **M54** (2026-10-22, pass 20) — design only: Gen 8, the new legendary places, the Glow, more puzzles, and the long game. No free landmark art in this style exists.
- **M55** (2026-10-22) — the Godot launch wrapper and its rules (F57; Item 23).
- **M56** (2026-10-22, pass 21) — Item 23 verified, and Item 24's stop diagnosed (slice-2 §11.1a).
- **M57** (2026-10-22) — enterable landmarks drawn: `building:part` and 3 × 3 matching (F54; Item 24).
- **M58** (2026-10-23, pass 22) — Items 24 and 24a verified (105 place entries, 78 legendaries). Item 25's ruin pass measured inside §11.4 after Decision 37, but its proof was incomplete (F59–F61 filed).
- **M59** (2026-10-23, pass 23) — no item finished; Item 12b in progress.
- **M60** (2026-10-24) — Item 12b: the Emerald mapping chosen by evidence (behaviour bytes, pixel tests, and layout statistics), checked by 16 falsifying rules, with neutral names (F59, F60).
  - **The table:** `emerald_tile_map.json` version 2, with 360 entries.
  - **Gaps that keep the placeholder:**
    - marsh, gravestones, and rail;
    - single pointed trees;
    - fence junctions;
    - the inside of bridge decks wider than 2 tiles;
    - snow and modern props.
- **M61** (2026-10-26) — Item 12c, your review changes: the ploughed crop field (sec07, metatile 657), and five compositions' corner cells set to lawn. Widths and the house went to Item 12d.
- **M62** (2026-10-26) — Item 12d: service roads, paths, streams, and door paths are 2 tiles wide, and `house_s` is 4 × 4.
  - **Measured on DC:** path tiles 14.8%; building tiles 11.7%; gone 43.1%; ruined 29.3%; tall grass 14.2%; landmarks 4/4. All are inside §11.4.
  - **Golden hash:** `69c99343…`.
- **M63** (2026-10-26) — Item 25b (F61, F56).
  - **The cause:** the whole-city view never finished because the worker's 64-request queue forgot cells the view still counted as requested.
  - **The fix:** forgotten cells are requested again, and cells already drawn are skipped.
  - **The harness:** `--timeout` (default 120 s from launch) now ends a stalled capture with exit 3.
  - **Frame times:** all five meet ≤ 16.7 / ≤ 33.4 ms, at zoom 1 and at 1/16.
  - **Filed:** F62 and F63.

**Decisions and art**
- **M64** (2026-11-01, pass 24) — a decision pass; no code changed.
  - This file was condensed, and Decisions 38–45 were recorded.
  - `design_art_direction.md`, the slice-2 §11.2/§12 notes, and the tile plan's status were updated to match.
  - The agent guide's queue is now 25c, 31, 32, 34, 26, 27+28, 33, 30, 10, 29.
  - The battery is green on `7290149`: 22/22 game tests, `sync_e2e` OK, Flutter 37 passed and 2 skipped, and the 84 art-tool tests.
- **M65** (2026-11-01) — the memory guard can run a job alongside others, for Decision 46.
  - **`memguard run --parallel`:**
    - it skips the exclusive lock;
    - it is admitted when memory fits, plus the running steps' unused budgets, which a new ledger records;
    - it yields first: below FLOOR, or on one critical poll.
  - **`--admit-timeout 0`** waits without a limit.
  - **`memguard doctor`** lists the running steps.
  - **A guard that is stopped** (SIGTERM or Ctrl-C) now stops its child too, with exit 130. Before this, the child ran on unwatched in its own session.
  - **Tests:** cases 11–16 are new. Every one was run against the old code and against seven broken variants of the new code; each failure was caught.
  - **Budgets:** `art_qwen_image_2512` is 28.5 GiB, measured as a 28.3 GiB drop in available memory, since GPU memory isn't in RSS; `art_validate` is 3.5 GiB, from its 2.67 GiB peak in the log.
  - **Live check:** ComfyUI started in parallel next to the test suite's guarded steps, and stopped with its guard.
  - **The Tier 2 limit** is now 10 rounds (catalogue, brief, validator test), and the Tier 2 prompt is written.

---

## 📜 Design-Phase Decision Record
The founding choices, kept for their reasons. Items 9–14 belonged to the zombie design that item 15 replaced.

1. **Two fogs.** Real visits reveal; only in-game travel clears. Real life is scouting, and the game is the game.
2. **Intel, never inventory,** from repeat visits.
3. **15 mph travel,** priced in time against real geography.
4. **Fast travel by physical presence, plus the stranded rule.** Reversed by Decision 25 (Distort): your real body now opens the doors.
5. **Drop-and-recover** instead of deletion (now the bag drops on blackout).
6. **A generation after the collapse:** overgrown, emptied, and haunted.
7. **True pixel art.** AI was for concepts only; Art D1 re-asks this for final art.
8. **The name "Tenth Spring"** (cleared July 20, 2026; the formal trademark check is pending).
9. **A PC game with a thin phone companion** (July 20). This still stands, but Steam was dropped by item 15. A second item 9, rejecting a Pokémon game on commercial IP risk (July 21), was reversed by item 15. Its "OpenStreetMap, not Google Maps" still stands.
10. –14. **Superseded by item 15:** biome enemy variants, loot by horde, landmark bosses, special infected, and loot icons.
15. **The Pokémon pivot (2026-10-07).**
    - **The game:** Diamond/Pearl style, Ghost-heavy, with real sprites from the player's own ROM, main-series battles, and catching.
    - **No Steam and no sales.** The repo is public, so it never holds Nintendo material.
    - **Why:** PokeMMO's bring-your-own-ROM model has held up, while Essentials, Uranium, and Prism were taken down.
16. **Post-pivot follow-ups (2026-10-08):** Decisions 7–12.
17. **Memory guards (2026-10-10).** Work is bounded by construction, admitted only when there's room, and watched while it runs (`design_memory_and_resources.md`).
18. **The grid is plain Web Mercator** (EPSG:3857, 256 WM-m cells, `game/world/grid.gd`; F42).
19. **The world is the USA** (Decision 16).
20. **"Looks like Pokémon" is a requirement, not polish** (Decision 17).
21. **A new story replaces the Giratina arc** (Decision 18): the Distortion copies whatever crosses it, and is learning the player.
22. **Real map art from a second cartridge,** Emerald (Decision 19).
23. **Neighbourhoods and cities, not streets** (Decisions 21–22).
24. **Famous places only, plus Distort** (Decisions 25–26).
25. **The same map for everyone** (Decision 23).
26. **Buildings you can enter, and quests that tell the story** (Decision 27).
27. **The phone stops tracking** (Decision 29).
28. **A ruined world, not a census** (Decision 30).
29. **Godot stays** (Decision 31).
30. **Gen 8 and fan sprites,** never committed (Decision 32).
31. **A society that kept the lights on:** the Glow (Decision 33).
