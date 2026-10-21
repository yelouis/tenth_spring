# Implementation Plan — Neighbourhood & City Unlocking (DRAFT)

> **Status: DRAFT (pass 18, 2026-10-20).** This plan becomes the contract when **Decision 21 = A** and **Decision 22 = A** (`docs/ongoing_general_errors.md`). It is built in agent guide Items 17–19.
> - **Decision 21 = B** (any movement unlocks): §5 rule 1 also applies to corridor rows, and §5 rule 4 is dropped. Everything else holds.
> - **Decision 21 = C** (passing through reveals nothing): corridor rows stop revealing cells, which changes the slice-1 F37 rule — a plan amendment, reviewed first.
> - **Decision 22 = B or C:** replace §5 rule 2's threshold with the constant chosen (2 or 3). Everything else holds.
>
> Every number, name, and string here is deliberate — implement as written.

**What this means for the player.** The human asked that going to a neighbourhood reveal the whole neighbourhood, and that visiting a couple of neighbourhoods in a city reveal the whole city. Today the map reveals only the strip along the streets the phone passed, plus the stops. After this plan:
- **a stop in a neighbourhood** turns that whole neighbourhood `known`;
- **stopping in enough of a city's neighbourhoods** turns the whole city `known`.

The two-fog model is unchanged: *known* is the grey silhouette, and travelling there in-game is still what clears a place (`design_world_generation.md` §1).

---

## 1. Terms

| Term | Meaning |
|---|---|
| **City** | An incorporated US city, town, or village: an OpenStreetMap `boundary=administrative` relation with `admin_level=8`. |
| **Neighbourhood** | A named neighbourhood inside or outside a city (§2.2), or a generated **district** where none is mapped (§2.3). Every covered map cell belongs to exactly one. |
| **Area key** | A stable text id for a city or neighbourhood, identical across map-store rebuilds: `osm:r<id>` for relations, `osm:n<id>` for nodes, `grid:<city key or "none">:<gx>:<gy>` for districts. |
| **Unlocked** | Recorded in the save's `area_reveal` table (§4). Unlocking only ever adds; it is never undone. |

---

## 2. Where areas come from — the map store (schema v4)

### 2.1 Cities
`boundary=administrative` + `admin_level=8` relations, assembled into polygons with the converter's existing multipolygon code. A cell belongs to the city whose polygon contains the **cell centre**; if two cities contain it, the lower relation id wins. A cell in no city has no city ("unincorporated").

### 2.2 Named neighbourhoods
In priority order, for each cell:
1. `boundary=administrative` relations with `admin_level=9` or `10` that contain the cell centre — lower id first.
2. Otherwise, the **nearest** `place=neighbourhood|suburb|quarter` node *in the same city* (or, for unincorporated cells, any such node within 3 km). Distance is measured in WM-m between the cell centre and the node; ties go to the lower node id. This is a cell-level Voronoi split.

Each neighbourhood's name is its OSM `name` (empty if none).

### 2.3 Generated districts
Cells left with no neighbourhood after §2.2 — a city with no mapped neighbourhoods, or rural land — are grouped into **districts of 4 × 4 cells** on the global grid: `gx = floor(cx / 4)`, `gy = floor(cy / 4)`, split by city.
- **Key:** `grid:<city key or "none">:<gx>:<gy>`.
- **Name:** the nearest `place=*` node name within 3 km of the district's centre cell; else the city's name; else empty.

A district is about 1 km on a side.

### 2.4 Store tables (`schema_version = '4'`)
```sql
CREATE TABLE areas (
  area_key   TEXT PRIMARY KEY,
  kind       TEXT NOT NULL,          -- 'city' | 'neighbourhood'
  name       TEXT NOT NULL DEFAULT '',
  city_key   TEXT,                   -- neighbourhoods only; NULL when unincorporated
  cell_count INTEGER NOT NULL        -- cells of this area inside the store's coverage
);
CREATE TABLE area_cells (
  cell_x     INTEGER NOT NULL,
  cell_y     INTEGER NOT NULL,
  nbhd_key   TEXT NOT NULL,
  city_key   TEXT,
  PRIMARY KEY (cell_x, cell_y)
);
CREATE INDEX idx_area_cells_nbhd ON area_cells(nbhd_key);
CREATE INDEX idx_area_cells_city ON area_cells(city_key);
```
Every cell in the store's coverage rectangle has exactly one `area_cells` row. The map view skips older stores with `map: skipping <file name> — store schema <v>, need 4`.

### 2.5 Converting enough of the map — the clip rectangle grows to whole areas
A city can only be revealed if the store covers all of it. So `--clip-to-save` gains a first stage:
1. **Stage A — boundaries only.** Extend the existing pre-pass so that, in the same read of the file, it also collects:
   - every `admin_level` 8, 9, and 10 boundary relation;
   - the coordinates of their member ways' nodes;
   - every `place=*` node.

   Assemble the polygons and compute each city's bounding box in cells.
2. **The rectangle.** Take the union of:
   - the bounding box of every city containing a revealed cell;
   - for revealed cells in no city, the 3 × 3 districts around them;
   - plus `--margin-cells` (default 2 now; it was 6).

   Print only its size (`clip: <w> x <h> cells`).
3. **Stage B** is today's clip conversion with that rectangle, plus the `areas` and `area_cells` tables computed for every covered cell.

**Re-measure:** run on the human's area under `memguard measure map_convert_clip`, and record time, peak RSS, and store size beside plan §5.3's clip row. Target: ≤ 15 min and ≤ 1 GiB. Report either way — this feeds Decision 23.

---

## 3. Synthetic fixture v4
Made-up names and coordinates only. Add:
- **`Fixture City`** — an `admin_level=8` multipolygon covering 6 × 6 cells;
- **three `place=neighbourhood` nodes inside it:** `North End`, `Old Town`, and `Riverside`;
- **one `admin_level=10` relation** (`Mill District`) covering a 2 × 2 block of the city;
- **rural land** outside the city, 8 × 4 cells, with no place nodes.

**Expected:** every covered cell has one `area_cells` row; the `Mill District` cells take it rather than the nearest node; the rural cells form `grid:none:*` districts. Commit the canonical dump hash.

---

## 4. The save — `area_reveal` (migration 2)
The save's v1 DDL is frozen, so this is the first entry in `db.gd`'s `MIGRATIONS` (`implementation_plan_foundation.md` §B6):
```sql
CREATE TABLE IF NOT EXISTS area_reveal (
  area_key    TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,         -- 'city' | 'neighbourhood'
  unlocked_at INTEGER NOT NULL       -- epoch ms of the visit that unlocked it
);
```
- **`db_migration_test` gains a case:** a v1 save migrates to v2, keeps every row, and gains an empty `area_reveal`.
- **Golden invariant 1 still holds.** The sync ingest still writes only `map_cell`, `place_node`, and `visit_log`. `area_reveal` is written by the reveal engine (§5), never by ingest, and holds no cargo.

---

## 5. The reveal engine — `game/world/reveal_engine.gd`
`RevealEngine.apply(db, stores) -> Dictionary` returns `{"neighbourhoods_unlocked": [...], "cities_unlocked": [...], "cells_revealed": n}`. It is deterministic and idempotent, and it never lowers a reveal state.

1. **Neighbourhoods (Decision 21 = A).** For every `visit_log` row with `kind = 'visit'`:
   - project its stored latitude/longitude through `Grid.latlon_to_cell`, and look the cell up in `area_cells`;
   - if its neighbourhood is not yet in `area_reveal`, insert it with `unlocked_at = started_at`;
   - process visits in `(started_at, peer_id, seq)` order, so `unlocked_at` is the earliest qualifying visit.
2. **Cities (Decision 22 = A).** For each city with at least one unlocked neighbourhood:
   - `n` = the number of distinct `nbhd_key`s with that `city_key` in `area_cells`;
   - the threshold is `T = 1` if `n = 1`, else `T = clamp(ceil(0.10 × n), 2, 5)`;
   - when the city's unlocked neighbourhoods reach T, insert the city with `unlocked_at` = the `unlocked_at` of the neighbourhood that reached T.
3. **Reveal cells.** Every `area_cells` cell of an unlocked neighbourhood or city gets `upsert_map_cell(cx, cy, 1)`. The existing MAX semantics keep `cleared` cells cleared.
4. **Corridors are unchanged (Decision 21 = A).** Corridor rows keep revealing the cells within 60 m (F37), and never unlock an area.
5. **No map data yet.** A visit whose cell is in no store's coverage only reveals its own cell, as today. Once a store covering it is installed, the next `apply` unlocks its neighbourhood.
6. **When it runs:**
   - after each committed sync batch — in its own transaction, after the ingest transaction;
   - after any map store is installed or re-converted;
   - once at boot, after `init_db()`;
   - and in `demo_import_server.gd` after `DEMO_IMPORT_COMPLETE`.
7. **Performance.** Process only visits newer than `meta('reveal_engine_seq_<peer>')`, which the engine updates as it goes — except after a store install, when it re-runs over every visit. Target: ≤ 200 ms for 10,000 visits on the human's Mac.

---

## 6. What the player sees
- **Toasts,** shown for 4 s at the top of the map view, one per newly unlocked area, in unlock order. Text, exactly:
  - `Neighbourhood revealed — <name>`
  - `City revealed — <name>`
  - with `an unnamed area` in place of an empty name.
- **City names on the overview:** at zoom < 1, each unlocked city's name is drawn as a label at its centroid cell. Its centroid is the mean of its cell coordinates, rounded.
- **Fog:** unchanged rules, at cell granularity. A newly revealed neighbourhood simply appears as `known` cells.

---

## 7. Validation (Items 17–19)
- **Store** (`region_import_test`): fixture v4's `areas`/`area_cells` as §3 expects, the stable keys, and the canonical hash.
- **Engine** (`reveal_engine_test.gd`, new; add it to `EXPECTED`):
  - **(a) Falsifying:** one visit in `Old Town` → every `Old Town` cell is `known`. Today only the visit's own cell is.
  - **(b)** A corridor row through `Riverside` → `Riverside` is **not** in `area_reveal`; only cells within 60 m are revealed.
  - **(c)** A second visit, in `North End` → `n = 4` (three nodes + `Mill District`), so T = 2 → `Fixture City` unlocks, and all 36 of its cells are `known`.
  - **(d)** Replaying the same `visit_log` changes nothing.
  - **(e)** Visits recorded before any store is installed → after installing the store and running `apply`, the neighbourhoods unlock.
  - **(f)** A rural visit unlocks exactly one 4 × 4 district.
  - **(g)** A `cleared` cell stays `cleared`.
- **Migration** (`db_migration_test`): v1 → v2 adds `area_reveal` and loses nothing.
- **Invariant:** `sync_ingest_isolation_test` stays green, unchanged.
- **Real data** (Item 19): re-convert the human's area with stage A, re-import their route, and capture the overview (zoom 1/16) and a zoom-1 screenshot with the harness. Report how many neighbourhoods and cities unlocked (counts only), and show both to the human.

---

## 8. Doc changes when this lands (same commits)
- **`design_world_generation.md`:** §1's table ("Entered by") and §2 — visits unlock neighbourhoods; enough neighbourhoods unlock cities; corridors reveal 60 m strips.
- **`design_game_state_and_models.md`:** the `area_reveal` table, and store schema v4.
- **`design_privacy_and_location.md`:** reveal is now *coarser* than the phone's fuzzed points. The map shows whole neighbourhoods, which hides where inside them you went.
- **`master_implementation_plan.md`:** Phase 3 scope.
