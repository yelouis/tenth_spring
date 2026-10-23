# Implementation Plan — Famous Places: the Place List, the Same Map for Everyone, Unlocking, and Distort

> **Status: APPROVED by decision (2026-10-20).** The human answered Decisions 21–26: any movement unlocks a neighbourhood, the city threshold scales, a pinned snapshot, only famous places exist, Distort from home with Waypost returns, and Wardens and legendaries at fixed places. This plan builds those choices; the design contract is `design_famous_places.md`. Built in agent guide Items 17–21. **Item 17 ends in a PAUSE:** the human reviews the filled-in place list before anything else is built on it.
>
> *This file was `implementation_plan_area_unlock.md` (a pass-18 draft); it was renamed and rewritten after the human narrowed the scope to famous places.*
>
> **Amended 2026-10-21 (pass 19), §8:** the content revisions to the place list (Item 24), and the neighbourhood rule fix (F55). Since Decision 29 (Explore Here), areas come from the shared **places pack** (Item 26), and unlocking reads explore events, not movement (Item 28) — `implementation_plan_explore_here.md`. §3–§6 below are the record of what Items 18–21 built.
>
> Every number, name, and string here is deliberate — implement as written.

**What this means for the player:**
- The game's world becomes the 27 famous cities and 36 famous parks and wonders.
- Your home is the safehouse hub. From day one you can Distort to the famous city nearest home, arriving at its Waypost neighbourhood, which is already revealed.
- Tapping **Explore Here** in a neighbourhood reveals it; enough neighbourhoods reveal the whole city. Exploring anywhere in a park reveals all of it (Decision 29).
- Two friends standing in the same place see the identical map.

---

## 1. The place list — `game/config/famous_places.json` (Item 17)
1. **Write the 75 entries** (27 cities, 36 sites, 12 spots) exactly as `design_famous_places.md` §1–§5 and §9 list them, with each place's `interiors` from `design_interiors_and_quests.md` §4. Ids are slugs (`city:new-york`, `site:grand-canyon`, `spot:alcatraz`).
2. **Look up each city's and site's OSM boundary relation, and each Waypost and Warden landmark position**, with the public OSM search service — **public place names only**, never a location of the human:
   - `https://nominatim.openstreetmap.org/search?q=<public name>&format=json&limit=5`, with a `User-Agent: TenthSpring-dev/<version>` header and **≥ 1.1 s between requests** (Nominatim's usage policy);
   - **cities:** the `boundary=administrative` relation for the city proper;
   - **sites:** the `boundary=national_park` or `protected_area` relation, or the park or state-park relation for wonders;
   - **Wayposts:** a city's city hall (`amenity=townhall`); a site's main visitor centre, else its main entrance.
   - **Interiors:** each famous interior's public entrance (`design_interiors_and_quests.md` §4), stored in the place's `interiors` list with its family and purposes.

   This is development-time research. **Nothing in the game ever queries a search service** (Decision 13).
3. **New `tools/check_famous_places.py`** validates the file:
   - 27 cities, 3 per region;
   - 48 distinct legendary dex numbers across sites and spots, with no place holding two;
   - every city and site has `osm_boundary` and `waypost`;
   - every spot names an existing city;
   - every region has exactly one Warden, located in one of its cities;
   - every city has at least 2 interiors and every site has a visitor-centre interior; every interior has at least two purposes, including T, W, L, or Q (`design_interiors_and_quests.md` §2);
   - coordinates within US bounds.

   It runs in the battery.
4. **PAUSE:** show the human the table (name → relation id → Waypost name), and ask them to confirm or swap rows. Record the answer in `ongoing_general_errors.md`.

---

## 2. The same map for everyone (Item 18)
1. **Constants in a new `game/world/map_constants.gd`:** `MAP_SNAPSHOT := "261001"` (2026-10-01) and `MAP_SEED := 0`.
   - `tile_synth2.gd` takes its seed from `MAP_SEED` — the `world_seed` parameter is removed from the map path.
   - The fetcher builds download URLs as `https://download.geofabrik.de/<geofabrik path>-<MAP_SNAPSHOT>.osm.pbf`, plus `.md5`, never `-latest`.
2. **Fixed conversion units.** `tools/map_convert.py --place <id>` (and the in-game install) converts one place:
   - its boundary relation's polygon → its cell bounding box + **2 cells** of margin;
   - this is the clip rectangle, and it replaces `--clip-to-save` for real use (`--clip-to-save` stays, for tests).
3. **The whole coastline.** During conversion, keep **every** `natural=coastline` way in the region file, whatever the clip, so sea flags never depend on the clip.
4. **One store per place:** `user://map_data/<place id>.db`, with `import_state` keys `place_id`, `snapshot` (= `MAP_SNAPSHOT`), and `schema_version = '4'`.
5. **Determinism test** (new, `region_import_test`):
   - convert the synthetic fixture twice, with two *different* `--clip-to-save` rectangles that both contain the fixture's place;
   - convert it once with `--place`;
   - the two `--place`-equivalent runs give identical canonical hashes, and the `tile_synth2` buffers of every cell inside the place are byte-identical.
   - **Falsifying:** before rules 2–3, the coastline-dependent sea cell differs between the two clips.

---

## 3. Neighbourhoods inside cities — store schema v4 (Item 18)
For **city** places only, during conversion:
1. **Assign each cell centre inside the city boundary a neighbourhood.**
   - **(a)** The `boundary=administrative` relation with `admin_level` 9 or 10 that contains it (lower id first).
   - **(b)** Else the nearest `place=neighbourhood|suburb|quarter` node inside the same city (WM-m distance; ties to the lower id).
   - **(c)** Else the 4 × 4-cell district `grid:<city id>:<floor(cx/4)>:<floor(cy/4)>`.
2. **Cells inside the bounding box but outside the boundary** get no neighbourhood. They are drawn as margin and never revealed.
3. **Tables:**
   ```sql
   CREATE TABLE areas (area_key TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', cell_count INTEGER NOT NULL);
   CREATE TABLE area_cells (cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL, area_key TEXT NOT NULL, PRIMARY KEY (cell_x, cell_y));
   CREATE INDEX idx_area_cells_area ON area_cells(area_key);
   ```
   - **Area keys:** `osm:r<id>`, `osm:n<id>`, `grid:…`, plus one row of kind `'city'` (`area_key` = the place id) and, for sites, one row of kind `'site'` covering all inside cells.
   - **Sites** get `area_cells` for every cell inside their boundary, under the site's key.
4. **The map view skips stores below v4:** `map: skipping <file name> — store schema <v>, need 4`.
5. **Fixture v4** (made-up names and coordinates only):
   - `Fixture City` — an `admin_level=8` relation, 6 × 6 cells;
   - three neighbourhood nodes (`North End`, `Old Town`, `Riverside`);
   - one `admin_level=10` relation (`Mill District`, 2 × 2 cells);
   - `Fixture Park` — a `boundary=national_park` relation, 4 × 4 cells, east of the city.

   Plus a `game/tests/fixtures/famous_places_fixture.json` naming both places. Expected rows are asserted in `region_import_test`.

---

## 4. Unlocking — save migration 2 and the reveal engine (Item 19)
1. **Migration 2** — the first entry in `db.gd`'s `MIGRATIONS`:
   ```sql
   CREATE TABLE IF NOT EXISTS area_reveal (area_key TEXT PRIMARY KEY, kind TEXT NOT NULL, unlocked_at INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS distort_list (place_id TEXT PRIMARY KEY, unlocked_at INTEGER NOT NULL, reason TEXT NOT NULL);  -- 'starter' | 'visited'
   ```
   It also adds `meta('home_cell', '<cx>,<cy>')`, written by the home designation (rule 6).
2. **`game/world/reveal_engine.gd`** — `RevealEngine.apply(db, stores, places)` — runs over every `visit_log` row, **visits and corridors alike** (Decision 21 = B), in `(started_at, peer_id, seq)` order:
   - project the row through `Grid.latlon_to_cell` and look it up in each store's `area_cells`;
   - **neighbourhood:** insert into `area_reveal` if absent;
   - **city or site:** insert into `distort_list` (`reason 'visited'`) if absent;
   - **site:** also insert the site's area into `area_reveal`.
3. **City threshold** (Decision 22 = A): `T = 1` if the city has 1 neighbourhood, else `clamp(ceil(0.10 × n), 2, 5)`. When reached, insert the city's area, with `unlocked_at` = the moment the threshold was crossed.
4. **Reveal cells:** every `area_cells` cell of each area in `area_reveal` → `upsert_map_cell(cx, cy, 1)`. Existing MAX semantics keep `cleared` cells cleared.
5. **Rows inside no famous place** change nothing beyond what ingest already stored.
6. **Home and the starter city:**
   - `RevealEngine.designate_home(db, cell)` stores `meta('home_cell')`;
   - the starter city is the famous city whose Waypost is nearest the home cell's centre (`Grid.ground_distance_m`, ties to the lower id);
   - it goes into `distort_list` with `reason 'starter'`, and **the neighbourhood containing its Waypost** goes into `area_reveal`;
   - for this slice, the demo uses the most-visited place's cell as home; the onboarding UI is Phase 10.
7. **When it runs:**
   - after each committed sync batch, in its own transaction;
   - after any place store is installed;
   - at boot;
   - after a demo import.

   It's idempotent, and it never lowers a reveal.
8. **Golden invariant 1 still holds:** ingest writes only `map_cell`, `place_node`, and `visit_log`. `area_reveal` and `distort_list` are written by the engine, and hold no cargo.

**Tests — new `reveal_engine_test.gd`** (add it to `EXPECTED`), on fixture v4:
- **(a) Falsifying:** one **corridor** row through `Old Town` → every `Old Town` cell is `known`. Today a corridor reveals only 60 m.
- **(b)** A second row, in `North End` → `n = 4`, so `T = 2` → `Fixture City` is unlocked, with all of its inside cells `known`.
- **(c)** One row anywhere in `Fixture Park` → all 16 park cells `known`, and the park is on the Distort list.
- **(d)** Replaying `visit_log` changes nothing.
- **(e)** Designating home west of the city → `Fixture City` is the starter (`reason 'starter'`), and its Waypost neighbourhood is revealed with no visits.
- **(f)** A row outside both places → no `area_reveal` or `distort_list` change.
- **(g)** `cleared` stays `cleared`.
- **Plus:** `db_migration_test` covers v1 → v2, and `sync_ingest_isolation_test` stays green, unchanged.

---

## 5. Distort, the Town Map, and the home hub — viewer level (Item 20)
There's no player avatar yet (Phase 4), so this item builds the *structure* that Phase 4 will drive:
1. **The home hub scene,** `game/scenes/home_hub.tscn`:
   - a simple room screen — placeholder art, original;
   - three disabled buttons, `Rest`, `PC Box`, and `Garden`, marked "coming in Phase 4–7";
   - a **Distort** button that opens the Town Map.
2. **The Town Map,** `game/scenes/town_map.tscn`: an overview of the USA (original drawing — state outlines from public-domain US Census cartographic boundaries are allowed, or plain dots) with one marker per famous place:
   - grey = locked;
   - lit = on the Distort list;
   - a ring = fully unlocked (cities only).

   Clicking a lit marker loads that place's map view, centred on its Waypost.
3. **Leaving a place:** the map view shows a `Return home` button **only while the camera is centred within 1 cell of the place's Waypost** — a viewer-level stand-in for "only from the Waypost". Clicking it returns to the home hub.
4. **Boot:**
   - with a `bodyFix` inside a famous place, open that place's map view;
   - otherwise open the home hub;
   - the pairing screen stays reachable from the hub.
5. **Tests:**
   - a scene test where locked markers can't be clicked and lit ones load the right place;
   - `Return home` hidden away from the Waypost and shown at it;
   - boot routing for both cases.

---

## 6. Real-data proof — Washington DC (Item 21)
Washington DC is a famous city with a small file (21 MB) and nothing private.
1. **Convert it:** `python3 -I tools/map_convert.py --place city:washington-dc` with the pinned snapshot.
2. **Make a DC demo profile** (`--demo-dir user://demo_dc`):
   - import a GPX the agent draws through public DC landmarks (National Mall, Union Station, Dupont Circle), saved outside the repo;
   - designate home at a public point **outside** DC, so DC becomes the starter.
3. **Screenshots with the harness:**
   - the Town Map;
   - DC at zoom 1/16 — revealed neighbourhoods vs fog;
   - DC at zoom 1 at the Waypost.
4. **Report** neighbourhoods unlocked, whether the city threshold was reached, and the Distort list — counts and names of *public DC* areas only.
5. **PAUSE** for the human.

---

## 7. Doc changes when this lands (same commits)
- **`design_world_generation.md`** §1–2: the per-area reveal is built; corridors no longer reveal 60 m strips inside famous places, because the area rule supersedes them.
- **`design_game_state_and_models.md`:** `area_reveal`, `distort_list`, `meta('home_cell')`, store schema v4.
- **`design_privacy_and_location.md`:** reveals are coarser than the fuzzed points. Home never leaves the PC and is used only to pick the starter city.
- **`master_implementation_plan.md`:** Phase 3 scope.

---

## 8. Pass-19 amendments (2026-10-21)

### 8.1 The place list, revised — `game/config/famous_places.json` (Item 24a)
The pass-19 content review changed some rows of `design_famous_places.md` §1.2 and `design_interiors_and_quests.md` §4. Bring the file in line, using §1 step 2's lookup rules (public names only, Nominatim at ≥ 1.1 s between requests, development time only):

| Change | In the file |
|---|---|
| Uxie, Mesprit, Azelf swap places | `site:walden-pond` → `legendary_dex` 480; `site:niagara-falls` → 481; `site:isle-royale` → 482 |
| Zapdos moves to the Everglades | **add** `site:everglades` (South Atlantic, `north-america/us/florida`, Waypost: the Ernest F. Coe Visitor Center, `legendary_dex` 145, a visitor-centre interior); **remove** `site:theodore-roosevelt` |
| Darkrai moves to Katahdin Woods and Waters | **add** `site:katahdin-woods-and-waters` (New England, `north-america/us/maine`, Waypost: the monument's main visitor contact station, else its main entrance; `legendary_dex` 491; a visitor-centre interior); **remove** `site:salem-maritime` |
| Regirock moves to Cathedral Caverns | **add** `site:cathedral-caverns` (East South Central, `north-america/us/alabama`, Waypost: the park's visitor centre; `legendary_dex` 377; a visitor-centre interior and a `cave` lair interior); **remove** `site:russell-cave` |
| Las Vegas interiors (Decision 33) | the **six** rows of `design_interiors_and_quests.md` §4.1: Fremont Street — the Glow; the STRAT tower; the House vault (beneath Fremont Street, door at the canopy's centre); the Neon Museum; the Smith Center; and Springs Preserve, each with its public entrance as `door` |
| **The 30 Generation 6–8 places** (Decision 32) | **add** the 24 sites and 6 spots of `design_famous_places.md` §1.2, with visitor-centre interiors for the sites, and the lair and city interiors of `design_interiors_and_quests.md` §4. Small sites may use `osm_boundary: "w<id>"`. The Churchill Downs interior gains `L P` |
| Lore requirements | **add** `requires` to all 20 legendaries in `design_famous_places.md` §6's table, in §9's object form |

- Use the place ids above if the file uses that slug style; otherwise keep the file's existing style, and say so in the report.
- **`tools/check_famous_places.py` changes:**
  - **105 entries:** 27 cities, 60 sites, and 18 spots;
  - **78 distinct legendary dex numbers,** with no place holding two;
  - `requires`, if present, uses only §9's keys, and every dex it names is a legendary in the file;
  - no `requires` chain is circular;
  - every legendary named in a `requires` is reachable;
  - each of the nine regions holds 7 to 9 legendaries.
- **Report** the new and changed rows (name → relation id → Waypost name) for the human to check at Item 25's pause.

### 8.2 Neighbourhoods come from the places pack (F55) — amends §3 step 1 (Item 26)
- **The bug:** rule (a) took `admin_level` 9 or 10, lower id first. In DC, admin level 9 is the city's 8 political wards, so DC got 8 huge "neighbourhoods", and two of them unlocked the city.
- **The rule now,** computed once by `tools/build_places_pack.py` (`implementation_plan_explore_here.md` §1):
  1. **Polygons:** named `boundary=administrative` areas with `admin_level=10`, and named closed areas tagged `place=neighbourhood|suburb|quarter`, inside the city. A cell takes the **smallest** polygon containing its centre, ties to the lower OSM id. Admin level 9 is never used.
  2. **Points:** each remaining cell takes the nearest named `place=neighbourhood|suburb|quarter` node inside the city that lies in no rule-1 polygon (WM-m distance, ties to the lower id).
  3. **Districts:** cells still unassigned form 4 × 4-cell districts, `grid:<city id>:<floor(cx/4)>:<floor(cy/4)>`.
- **The converter stops computing neighbourhoods.** `--place` copies the place's areas and cells from the bundled pack into the store's `areas` and `area_cells`, so the store, the PC's reveal engine, and the phone all use the same areas. The store schema becomes `'5'` (`import_state('pack_version')` added), and v4 stores are skipped and re-converted.
- **Expected for DC:** no admin-level-10 areas, so rule 2 applies, with roughly 130 named neighbourhood points — and so `T = 5`. Report the counts, never the names of private places (DC's public neighbourhood names are fine).

### 8.3 Unlocking reads explore events (Item 28)
`RevealEngine` v2, save migration 3, the starter city by id, and boot are specified in `implementation_plan_explore_here.md` §4–§5. They replace §4 rules 2 and 6 and §5 step 4 above.
