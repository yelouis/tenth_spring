# Implementation Plan — World Generation, Slice 2: "Pokémon Look"

> **Status: APPROVED (2026-10-19).** Decision 17 = A approved this plan as written.
> - **Decision 19 = Emerald:** the map's real art comes from the player's Pokémon Emerald ROM (`design_rom_asset_pipeline.md` §2, §5). §5's code-drawn placeholder atlas is **still built** — it is the no-ROM look and the only atlas tests and agents ever see. The renderer (§6) loads `user://rom_cache/tiles/emerald_v1.png` + `.json` when the Emerald import is valid, and the placeholder otherwise.
> - **Both atlases share §5.2's JSON layout**, so the switch is data, not code.
> - The Emerald importer itself is a separate, ROM-gated item (agent guide Item 12). It may adjust §4.2's template sizes to fit Emerald's building compositions — through a plan amendment the human reviews.
>
> Built in agent guide Items 4–9, after Items 0–3 (slice-1 fixes, clip conversion, and the screenshot harness — `implementation_plan_world_generation.md` §5.1a, §5.4a, §5.5, §7.1a, §7.4).
>
> **Pass 18 (2026-10-20): built, then corrected.** Items 4–9 delivered the plan, but the human's verdict at the Item 9 pause was that the map "should contain buildings" — and on their area only ~13% of buildings were placed (`ongoing_general_errors.md` F51–F53). **§10 amends this plan** (agent guide Items 13–16). Where §10 and an earlier section disagree, §10 wins.

**Goal.** The human's own neighbourhood, from their own route, drawn by the running game as a Pokémon-style map: paths and roads, roofed buildings with south-facing doors and signs bearing real names, tree-bordered parks full of tall grass, shorelines, graveyards behind fences, and rail lines — under the two-state fog. Proven with screenshots the game saves itself.

**Why the current map can't get there.** Slice 1 fills each 16 WM-m square (≈ 13 m on the ground) with one of six flat colours. A real house is about one square, so it becomes a dot; a street becomes a one-square line. A Pokémon map is the opposite: it is *assembled* from walking-scale pieces. This slice halves the square size and replaces "colour each square" with "build the map from pieces, in the real places".

Contracts this plan extends: `design_world_generation.md` §3, `design_art_direction.md` §3, `design_game_state_and_models.md` §2, `design_memory_and_resources.md` §3.3. **Every number, name, and string here is deliberate — implement as written.**

---

## 0. Scope

**In:**
- the tile-scale change (8 WM-m tiles, 32 × 32 per cell);
- map store v2 — new kinds, names, building anchoring, coastline and sea;
- synthesis v2 — terrain, sea, roads, paths, rail, bridges, vegetation, cemeteries, parking, buildings, signs, and decoration;
- an original placeholder tile atlas and palette;
- renderer v2 — atlas, known/cleared layers, fog shimmer and feathered fog edges, and an overview zoom;
- screenshot proof on the human's area.

**Not in (slice 3 or later):**
- the player avatar and walking; encounters; spawn zones and haunting tints;
- ledges and terraces from elevation; biome classification (Decision 18);
- overgrowth by distance from home; interiors; the night tint;
- pre-built stores (Decision 15); final 47-blob autotiles (`design_art_direction.md` §3).

---

## 1. Scale

- **`Grid.TILE_WM = 8.0`** (was 16). A cell stays 256 WM-m, so a cell is **32 × 32 tiles**. `Grid.latlon_to_tile` becomes `floor(x / 8)`, `floor(y / 8)`.
- **On the ground** a tile is 8·cos(latitude) m: ≈ 6.3 m at 38° N, 5.4 m at 48° N, 7.1 m at 26° N.
- **Why 8:**
  - A Pokémon house (4 × 4 tiles since §13; 4 × 3 before) then covers about 25 × 25 m — roughly one suburban lot — so buildings land near their real spots.
  - Streets come out 2–4 tiles wide, like Pokémon paths.
  - Crossing a 5 km town on foot takes about 3.5 minutes of play.
- **Pixels:** 32 × 32 px per tile (`design_art_direction.md` §3). One cell is 1024 × 1024 world pixels.
- **Store units don't change.** Add `MapStore.GEOM_UNIT_WM := 16.0`; the converter divides by it instead of `Grid.TILE_WM`. Synthesis multiplies store coordinates by `GEOM_UNIT_WM / Grid.TILE_WM` (= 2.0) to get tile coordinates. So the slice-1 canonical dump stays valid until §2's schema changes land.
- **Saved tile coordinates change meaning** (`player_profile.pos_tile_*`, `place_node.tile_*`). There is no migration, because no real save exists. **Verify that first:** `user://tenth_spring.db` must be absent on the human's Mac (it was on 2026-10-19). If one exists, STOP and file it.
- **Config:** `tuning.json` `tileMeters` → `8.0`; `config.gd` default → `8.0`.

---

## 2. Map store v2

The store is a regenerable cache. Bump `import_state('schema_version', '2')`. The map view skips any store whose `schema_version` isn't `'2'`, logging `map: skipping <file name> — store schema <v>, need 2`.

Stores are always created fresh, so these are changes to the slice-1 `CREATE TABLE` statements, not `ALTER`s:
```sql
-- features_poly gains two columns:
subkind TEXT NOT NULL DEFAULT '',
name    TEXT NOT NULL DEFAULT ''
-- features_line gains one column:
subkind TEXT NOT NULL DEFAULT ''
-- new table:
CREATE TABLE cell_flags (
  cell_x INTEGER NOT NULL,
  cell_y INTEGER NOT NULL,
  sea    INTEGER NOT NULL,          -- 0 land, 1 sea, 2 coast
  PRIMARY KEY (cell_x, cell_y)
);
-- import_state keys: schema_version = '2'; coverage and clip (slice-1 plan §5.5)
```

### 2.1 Polygon kinds — the first matching row wins

| kind | subkind | OSM tags |
|---|---|---|
| `building` | the `building` value | `building=*` except `building=no`; skipped when it also has `building:part` with any value but `no` (§11.1a). Ways tagged only `building:part=*` are never stored |
| `water` | — | `natural=water`, `water=*`, `waterway=riverbank`, `landuse=reservoir`, `landuse=basin` |
| `wetland` | — | `natural=wetland` |
| `sand` | — | `natural=beach`, `natural=sand` |
| `cemetery` | — | `landuse=cemetery`, `amenity=grave_yard` |
| `park` | the `leisure` or `landuse` value | `leisure=park\|garden\|recreation_ground\|playground\|pitch\|nature_reserve\|dog_park\|golf_course\|common`; `landuse=grass\|village_green\|recreation_ground\|meadow` |
| `forest` | — | `landuse=forest`, `natural=wood` |
| `scrub` | — | `natural=scrub\|heath\|grassland` |
| `farmland` | — | `landuse=farmland\|orchard\|vineyard\|allotments\|farmyard\|greenhouse_horticulture` |
| `parking` | — | `amenity=parking` (closed way or multipolygon) |
| `residential` | — | `landuse=residential` |
| `commercial` | — | `landuse=commercial\|retail` |
| `industrial` | — | `landuse=industrial\|railway\|brownfield\|quarry` |
| *(not stored)* | | anything else |

`name` is the OSM `name` tag (empty if none).

### 2.2 Line kinds

| kind | subkind | Width (tiles) | OSM tags |
|---|---|---|---|
| `road` | the `highway` value | motorway 4, trunk 4, primary 3, secondary 3, tertiary 2, residential / unclassified / living_street / road 2, any `*_link` 2, service 2 (§13; it was 1) | `highway=` one of those |
| `path` | the `highway` value | 2 (§13; it was 1) | `highway=footway\|path\|cycleway\|pedestrian\|track\|steps\|bridleway` |
| `rail` | the `railway` value | 2 | `railway=rail\|light_rail\|narrow_gauge\|tram` |
| `waterway` | the `waterway` value | river 3, canal 2, stream / ditch / drain 2 (§13; it was 1) | `waterway=river\|canal\|stream\|ditch\|drain` |
| `coastline` | — | — | `natural=coastline` |

- **Bridges:** if the way has `bridge=*` (any value except `no`), append `:bridge` to the subkind, e.g. `primary:bridge`.
- **Excluded entirely:**
  - `tunnel=*` (any value except `no`), `covered=yes`, or `layer` < 0 — coastline excepted;
  - `highway=proposed|construction|platform|corridor|elevator|bus_stop|raceway`;
  - `railway=abandoned|disused|subway|proposed|construction`;
  - `area=yes` highways.
- **Clipping must preserve vertex order.** The coastline side test (§2.4) depends on direction.

### 2.3 Anchoring

- **Buildings:** one row each, **unclipped**, stored in the *anchor cell* — the cell containing the centre of the footprint's bounding box. Coordinates are relative to the anchor cell's origin, in store units, and may fall outside `[0, 16)`.
- **Other polygons:** clipped per cell, as in slice 1. `name` goes only on the piece in the cell containing the polygon's bounding-box centre. If that cell has no piece, it goes on the piece with the largest clipped area; ties go to the lowest `(cell_y, cell_x)`.
- **Lines:** clipped per cell, as in slice 1.

### 2.4 Sea flags (coastline)

OpenStreetMap has no sea polygons. The sea is whatever lies to the **right** of a `natural=coastline` way, which always runs with land on its left. After Pass 3, for every cell in the store's coverage rectangle:
1. Bucket every coastline segment by cell.
2. A cell with a coastline segment in itself or any of its 8 neighbours → `sea = 2` (coast).
3. Otherwise search rings of cells outward, r = 1 … 64, until a ring contains coastline segments, and take the segment nearest the cell centre p (point-to-segment distance in WM-m).
   - If the nearest point lies inside the segment a→b: sea when `cross(b − a, p − a) < 0` (p is to the right, with y pointing north).
   - If the nearest point is a vertex v shared by segments u→v and v→w: sea when `cross(w − u, p − v) < 0`.
   - If no ring within 64 has segments → land.
4. Write `cell_flags` rows for every cell in coverage.

Synthesis of a coast cell uses the same rule per tile centre, against the coastline segments of its 3 × 3 neighbourhood; sea cells are all water.

---

## 3. Tile vocabulary — what synthesis outputs

Each cell is **32 × 32 tiles × 3 bytes**: `[class, variant, mask]`. That is 3072 bytes, row-major. **Row 0 is the cell's north edge, and column 0 its west edge** (north-first, unlike slice 1's south-first buffers).

The map view draws buffer row `r` of cell `(cx, cy)` at screen tile row `(−cy − 1)·32 + r` and column `cx·32 + c` — the slice-1 plan's §7.1a rule, with 32 in place of 16 and no row flip.

| id | class | Walkable later? | Variant byte |
|---|---|---|---|
| 0 | `VOID` — outside every store's coverage | — | 0 |
| 1 | `GRASS` | yes | 0–3 texture variant |
| 2 | `TALL_GRASS` | yes (encounters, slice 3) | 0 |
| 3 | `TREE` | no | 0–1 (round or pointed canopy) |
| 4 | `WATER` | no | 0 |
| 5 | `SAND` | yes | 0 |
| 6 | `MARSH` | yes | 0 |
| 7 | `PATH` | yes | 0; 1 overgrown (§11.2) |
| 8 | `ROAD` | yes | 0 normal, 1 cracked |
| 9 | `RAIL` | no | 0 |
| 10 | `BRIDGE` | yes | 0 |
| 11 | `PLAZA` | yes | 0; 1 weeded (§11.2) |
| 12 | `ROOF` | no | roof colour 0–7; + 16 broken (§11.2); 32 landmark (§10.8) |
| 13 | `WALL` | no | roof colour 0–7, + 8 if the tile has a window; + 16 broken (§11.2); 32 or 40 landmark (§10.8) |
| 14 | `DOOR` | yes (interiors, later) | roof colour 0–7; + 16 boarded (§11.2); 32 landmark (§10.8) |
| 15 | `FENCE` | no | 0 |
| 16 | `FLOWERS` | yes | 0 |
| 17 | `GRAVE` | no | 0 |
| 18 | `SIGN` | no | index into the cell's sign list, 0–15 |
| 19 | `CROP` | yes | 0 |
| 20 | `RUBBLE` (§11.2) | no | 0 small pile, 1 large pile |

**Mask byte:** bit 0 = north, bit 1 = east, bit 2 = south, bit 3 = west. A bit is set when that neighbour (in the working grid, so cell edges see their neighbours) belongs to the tile's *family*:

| Class | Family |
|---|---|
| `WATER` | `WATER`, `BRIDGE` |
| `PATH` | `PATH`, `ROAD`, `BRIDGE`, `PLAZA` |
| `ROAD` | `ROAD`, `BRIDGE` |
| `RAIL` | `RAIL` |
| `BRIDGE` | `BRIDGE` |
| `TREE` | `TREE` |
| `TALL_GRASS` | `TALL_GRASS` |
| `ROOF` | `ROOF` |
| `WALL` | `WALL`, `DOOR` |
| `FENCE` | `FENCE` |
| all others | mask = 0 |

**Hashing — portable, never Godot's `hash()`:**
- `fnv1a32(ints)`: start at `h = 2166136261`; for each int, for each of its 4 little-endian bytes (as int32): `h ^= byte; h = (h * 16777619) & 0xFFFFFFFF`.
- `u(gx, gy, salt) = fnv1a32([gx, gy, world_seed, salt]) / 4294967296.0`, over *global* tile coordinates: `gx = cx·32 + c`, `gy = cy·32 + (31 − r)` (northing tile index). Global coordinates make decoration seamless across cells. The demo uses `world_seed = 0`.
- **Salts:** 1 tree scatter · 2 flowers · 3 grass variant · 4 road cracks · 5 house door and roof colour · 6 tree variant · 7 noise lattice · 8 fallback-house skip · 9–14 the ruin pass (§11.2).
- **Value noise** `v(gx, gy)`: lattice spacing 4 tiles; `L(i, j) = fnv1a32([i, j, world_seed, 7]) / 4294967296.0`; `i = floori(gx / 4.0)`, `fx = (posmod(gx, 4) + 0.5) / 4`, and likewise `j`, `fy`; `v` = bilinear interpolation of the four lattice values. Use `floori` and `posmod` everywhere — US longitudes are negative.

---

## 4. Synthesis rules — `game/world/tile_synth/tile_synth2.gd`

`TileSynth2.synthesize_cell(cx, cy, area: Dictionary, world_seed: int) -> Dictionary` returns `{"tiles": PackedByteArray (3072), "signs": PackedStringArray}`.

`area` holds, for each offset `Vector2i(dx, dy)` with dx, dy ∈ {−1, 0, 1}:
- `polys`, `lines`, `places` — the store rows of that cell;
- `covered` — a bool;
- `sea` — 0, 1, or 2.

### 4.0 The working grid
Synthesis paints a **40 × 40 working grid**: the 32 × 32 cell plus a 4-tile margin, filled from the 3 × 3 neighbourhood. It then derives masks and keeps the central 32 × 32. A store point `(x, y)` from the cell at offset `(dx, dy)`, in store units, maps to working-grid floats:
- `col = 4 + 2x + 32·dx`
- `row = 36 − 2y − 32·dy`

A tile `(c, r)` is inside a polygon when its centre `(c + 0.5, r + 0.5)` is inside the outer ring and not inside a hole (even-odd rule). Test only tiles inside the polygon's bounding box.

### 4.1 Layers, in order — later layers overwrite earlier ones unless a rule says otherwise
1. **Base.** `GRASS` on tiles whose source cell is covered; `VOID` on tiles whose source cell isn't.
2. **Sea.** Sea cells → `WATER`. Coast cells → `WATER` on tiles that pass §2.4's side test.
3. **Land cover**, in this order:
   - `farmland` → `CROP` on rows where `gy` is even, `GRASS` on odd rows;
   - `scrub` → `TALL_GRASS`;
   - `forest` → `TREE`;
   - `park` → `GRASS` (detailed in step 6);
   - `cemetery` → `GRASS` (step 7);
   - `sand` → `SAND`; `wetland` → `MARSH`; `parking` → `PLAZA`; `water` → `WATER`.
   - `residential`, `commercial`, and `industrial` paint nothing; they steer steps 5b and 8.
4. **Lines.** Rasterize each segment's centreline as a 4-connected supercover (no diagonal-only steps, so grid movement can follow it). Then paint a square brush of width w: `lo = (w − 1) / 2` (integer division), `hi = w − 1 − lo`, painting `[c − lo, c + hi] × [r − lo, r + hi]` around each centreline tile. In this order:
   - `waterway` → `WATER`;
   - `rail` → `RAIL`;
   - `road` → `ROAD` if w ≥ 3, `PATH` if w ≤ 2;
   - `path` → `PATH`.

   **Crossings:**
   - A road or rail tile that lands on `WATER` becomes `BRIDGE` if the line's subkind ends in `:bridge`.
   - Otherwise, a road overwrites `WATER` that came from a **waterway line** (a culvert), but never polygon or sea `WATER`.
   - Where road and rail cross, the road wins (a level crossing).
5. **Buildings** (§4.2) and **fallback houses** (§4.3), then door paths.
6. **Parks.**
   - Every `GRASS` tile in a park becomes `TALL_GRASS` where `v(gx, gy) > 0.55`.
   - Then the park's *edge tiles* become `TREE` if they are `GRASS` or `TALL_GRASS`. An edge tile is a park tile with a 4-neighbour covered by no park polygon that isn't `WATER`. Path and road tiles stay as they are, so the paths form gaps in the tree border.
   - **Forests:** tiles at least 2 tiles from the forest edge become `TALL_GRASS` where `v > 0.70` (clearings).
7. **Cemeteries.** `GRAVE` on cemetery `GRASS` tiles where `gx mod 2 = 0` and `gy mod 3 = 0` (using `posmod`). `FENCE` on cemetery edge tiles that are `GRASS` or `GRAVE`.
8. **Scatter** on remaining `GRASS` tiles:
   - `TREE` where `u(…, 1) < 0.08` in residential land, or `< 0.05` elsewhere, but only if no 8-neighbour is `PATH`, `ROAD`, `PLAZA`, `DOOR`, `WALL`, `ROOF`, `FENCE`, or `SIGN`;
   - `FLOWERS` where the tile is within 2 tiles (Chebyshev) of a `DOOR` and `u(…, 2) < 0.25`.
9. **Signs** (§4.4).
10. **Variants and masks.**
    - `GRASS` variant = `floor(u(…, 3) · 4)`.
    - `ROAD` variant = 1 where `u(…, 4) < 0.20`.
    - `TREE` variant = 1 where `u(…, 6) < 0.30`.
    - Masks per §3. Then crop to the central 32 × 32.

### 4.2 Buildings

Only buildings **anchored in the centre cell** are placed. Their unclipped footprints map through §4.0.

- **Size.**
  - A = the footprint's outer-ring area in WM-m², i.e. the shoelace area in store units × 256.
  - `(w_t, h_t)` = the footprint's bounding-box size in tiles.
  - Skip footprints with A < 60 (sheds and garages are not drawn).
- **Template:**

| Template | When | Size (cols × rows) | Roof rows | Wall rows | Doors (bottom row, column offsets) |
|---|---|---|---|---|---|
| `house_s` | A < 400 | 4 × 4 (§13; it was 4 × 3) | 2 | 2 | column 1 if `u(col0, row0, 5) < 0.5`, else column 2 |
| `house_m` | 400 ≤ A < 2000, or subkind `apartments` / `dormitory` with A < 2000 | 5 × 4 | 2 | 2 | column 2 |
| `block_l` | A ≥ 2000 | w = clamp(round(w_t), 6, 24), h = clamp(round(h_t), 5, 14) | h − 2 | 2 | columns 2, 10, 18 (those < w − 1) |

- **Windows:** `WALL` tiles that aren't doors get the window bit on odd template columns.
- **Placement.**
  - `(cc, rc)` is the centre of the footprint's bounding box in working-grid coordinates. Top-left `col0 = round(cc − w/2)`, `row0 = round(rc − h/2)`.
  - Clamp so the template **and a 1-tile ring around it** stay inside the centre cell: `col0 ∈ [5, 35 − w]`, `row0 ∈ [5, 35 − h]`. Templates never cross a cell edge, so cells stay independent.
- **Order:** descending A, then ascending `row0`, then ascending `col0`.
- **Skip a building** if any template tile, or any tile of its 1-tile ring, is `WATER`, `ROAD`, `PATH`, `RAIL`, `BRIDGE`, `PLAZA`, `ROOF`, `WALL`, `DOOR`, `GRAVE`, or `FENCE`. Exception: `PATH`, `ROAD`, and `PLAZA` are allowed in the ring's south row, because a door may face a path.
- **Roof colour** (also on its `WALL` and `DOOR` tiles):

| Index | Colour | Building subkinds |
|---|---|---|
| 0–3 | red-brown, teal, green, purple | `house`, `detached`, `residential`, `semidetached_house`, `bungalow`, `terrace`, `cabin`, `farm`, `hut`, `apartments`, `dormitory`, and `yes` when the template is `house_s` or `house_m`. Index = `floor(u(col0, row0, 5) · 4)` |
| 4 | blue | `retail`, `commercial`, `supermarket`, `shop`, `kiosk` |
| 5 | orange | `school`, `college`, `university`, `kindergarten`, `public`, `civic`, `government`, `library`, `townhall`, `fire_station`, `police` |
| 6 | lilac | `hospital`, `clinic` |
| 3 | purple | `church`, `chapel`, `cathedral`, `temple`, `mosque`, `synagogue`, `religious` |
| 7 | grey | everything else, including `industrial`, `warehouse`, `office`, `ruins`, and `yes` on a `block_l` |

- **Door paths.** From the tile south of each door, walk south up to 6 tiles. If the walk reaches a `PATH`, `ROAD`, or `PLAZA` tile inside the cell, set the walked tiles to `PATH`. If it hits `WATER`, `RAIL`, a building tile, or the cell edge first, draw no path.

### 4.3 Fallback houses — residential land with no footprints

Many US areas have no building footprints in OpenStreetMap. For each `residential` or `commercial` polygon piece in the centre cell that contains **no** bounding-box centre of a centre-anchored building:
- Candidate `house_s` top-left corners sit on a global lattice: working tiles where `posmod(gx, 7) = 0` and `posmod(gy, 6) = 0`.
- Keep a candidate when the template's centre tile is inside the piece and `u(gx, gy, 8) < 0.70` — the rest stay empty lots, which suits the collapse.
- Apply §4.2's clamp, skip rule, and door paths. Roof index: residential `floor(u(col0, row0, 5) · 4)`, commercial `4`.
- Fallback houses are placed **after** all real buildings.

### 4.4 Signs
- **Sources:** named POIs in the centre cell (`place_nodes` with a non-empty name, positioned through `Grid.latlon_to_wm`), and named polygon pieces in the centre cell (§2.3).
- **Position.**
  - A POI inside a placed template → the `GRASS` tile immediately west of the template's first door.
  - Any other POI → its own tile if it is `GRASS`; else the first `GRASS` tile in rings of radius 1–2, scanning each ring north, east, south, west.
  - A named polygon → scan north from the bottom-centre of its piece's bounding box, up to 4 tiles, for the first `GRASS` tile inside the polygon.
  - No `GRASS` tile → no sign.
- **Spacing:** no two signs within 3 tiles (Chebyshev). Priority: `landmark` > `haunted` > `civic` > `medical` > `park` > any other category, then the lower `osm_id` (for polygons, the lower `(row, col)`). At most 16 signs per cell.
- The sign's variant is its index in the returned `signs` list. **Names are never logged.**

---

## 5. Placeholder art (Decision 19 = A)

### 5.1 Generator
- `tools/gen_placeholder_atlas.py` — Python 3 stdlib only, PNG written with `zlib` + `struct`, run with `python3 -I`. **Deterministic:** a test regenerates it and compares byte-for-byte, like `test_generate_synthetic_pbf.py`.
- **Outputs (committed — original art):** `game/assets/tiles/placeholder_v1.png`, `game/assets/tiles/placeholder_v1.json`, and `assets/palette/tenth_spring.gpl`.
- **Rip-trap rule:** draw every pixel from code. Copy nothing, and trace nothing from any Pokémon tileset or screenshot.

### 5.2 Atlas layout
- 32 × 32 px tiles; 16 columns. **Masked classes** use column = mask (0–15); unmasked classes use column 0.
- One row per `(class, variant)`, listed in the JSON as `{"tile_px": 32, "rows": [{"class": 1, "variant": 0, "row": 0, "masked": false}, …], "fog_rows": {"solid": r, "d75": r, "d50": r, "d25": r}}`.
- **Masked classes:** `WATER`, `PATH`, `ROAD`, `RAIL`, `BRIDGE`, `TREE`, `TALL_GRASS`, `ROOF`, `WALL`, `FENCE`.
- **Rows:** `GRASS` 0–3; `TREE` 0–1; `ROAD` 0–1; `ROOF` 0–7; `WALL` 0–15; `DOOR` 0–7; one row each for the others. `SIGN` has one row marked `"any_variant": true`.
- **Fog rows:** solid `#0d1119`, plus 75%, 50%, and 25% coverage, drawn as a 4 × 4 Bayer pattern in 2-px blocks.

### 5.3 Palette (≤ 64 colours, all in the `.gpl`)

| Role | Hex |
|---|---|
| grass / tuft | `#78c850` / `#5fa83f` |
| tall grass / blades / tips | `#4f9a3a` / `#2f6b24` / `#8fd86a` |
| tree canopy / outline / highlight / trunk | `#3a7d3a` / `#245c2a` / `#5aa05a` / `#6b4a2b` |
| water / waves / deep edge / shore | `#4a90d8` / `#78b4f0` / `#2f6aa8` / `#e8d8a0` |
| sand / speckle | `#e8d8a0` / `#d0bc80` |
| marsh / puddle | `#6a9a6a` / `#4a7a8a` |
| path / pebble / edge | `#d8c090` / `#b8a070` / `#b09060` |
| road / speckle / curb / crack | `#8a8a90` / `#9a9aa0` / `#c8c8c8` / `#5a5a60` |
| rail / sleeper | `#6b6b6b` / `#6b4a2b` |
| bridge plank / rail | `#b07840` / `#7a5028` |
| plaza / joint | `#b0b0b8` / `#9898a0` |
| roof 0–7 (base / shade) | `#c0504a`/`#8a3430`, `#3a9a9a`/`#256a6a`, `#5a9a4a`/`#3a6a30`, `#8a5ab0`/`#5a3a7a`, `#4a78c8`/`#30508a`, `#e08a3a`/`#a05a20`, `#b090c8`/`#7a6090`, `#8a8a90`/`#5a5a60` |
| wall / outline / window / frame | `#e8e0d0` / `#a89880` / `#6ab0e0` / `#3a5a80` |
| door / frame | `#7a5028` / `#4a3018` |
| fence | `#f0f0f0` |
| flowers | `#f85878`, `#f8d030`, `#ffffff` |
| grave / outline | `#a0a0a8` / `#707078` |
| crop / furrow | `#a8c060` / `#788830` |
| void (unmapped) | `#2a3242` |
| fog | `#0d1119` |
| ink outline | `#1a1a20` |

### 5.4 Drawing rules — a starting point; the human judges the result at the Item 9 pause
- **`GRASS`:** base colour plus 6–10 two-pixel tufts at fixed per-variant positions.
- **`TALL_GRASS`:** darker base with three rows of "V" blades and light tips. It must read instantly as different from `GRASS`; this is the most important tile in the game (`design_art_direction.md` §3). Where a mask side is 0, let the blades thin out toward that edge.
- **`TREE`:** grass background; a round canopy (radius 13 px, centre (16, 13)) with a 1-px outline, a highlight arc, and a 4 × 5 px trunk. Variant 1 has a pointed (conifer) canopy. Where N or S mask bits are set, extend the canopy to the tile edge so tree rows read as a wall.
- **`WATER`:** base with wave dashes. On each side whose mask bit is 0, draw a 3-px shore band and a 1-px deep-edge line inside it.
- **`PATH`** and **`ROAD`:** base with speckle; a 2-px darker border (path) or light curb (road) on each side whose mask bit is 0. `ROAD` variant 1 adds two crack lines and a tuft of tall-grass green.
- **`RAIL`:** gravel ground, two rails, and sleepers every 6 px. Run vertically when the N or S bit is set, else horizontally.
- **`BRIDGE`:** planks, with rails on sides whose mask bit is 0.
- **`ROOF`:** the roof colour. A ridge highlight where N = 0, a 3-px eave shadow where S = 0, and a 2-px dark outline where W or E = 0.
- **`WALL`:** wall colour, with an outline where W or E = 0. The window variant adds a 10 × 8 px window with a frame.
- **`DOOR`:** wall background, a 14 × 20 px door with a frame, and a 2-px mat.
- **`FENCE`:** white pickets on grass, horizontal or vertical by mask.
- **`FLOWERS`:** four flowers on grass. **`GRAVE`:** a rounded headstone with an outline. **`SIGN`:** a 20 × 12 px board on a post. **`CROP`:** furrowed rows. **`SAND`**, **`MARSH`**, **`PLAZA`:** base plus texture. **`VOID`:** flat.

---

## 6. Renderer v2 — `game/world/map_view.gd`

- **TileSet:** one atlas source, tile size 32 — `user://rom_cache/tiles/emerald_v1.png` when `asset_db` reports a valid Emerald import, else `res://assets/tiles/placeholder_v1.png`. Both come with a §5.2 JSON. Atlas coordinates are `(mask if masked else 0, row(class, variant))`. The map view reads the ROM atlas only through `asset_db` (`asset_db.tile_atlas()` returns the texture and JSON, or `null`).
- **Layers, bottom to top:**
  - `BackgroundLayer` (`#0d1119`);
  - `WorldKnown` — a TileMapLayer with `res://world/shaders/known_tint.gdshader`;
  - `WorldCleared` — a TileMapLayer with no shader;
  - `FogLayer` — a TileMapLayer with `res://world/shaders/distortion_fog.gdshader`;
  - `OverviewLayer` — a Node2D;
  - `AttributionUI`.
- **Shaders:**
  ```glsl
  // known_tint.gdshader — known = 40% desaturated and dimmed (design_art_direction.md §3)
  shader_type canvas_item;
  void fragment() {
      vec4 c = texture(TEXTURE, UV) * COLOR;
      float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
      COLOR = vec4(mix(vec3(g), c.rgb, 0.6) * 0.82, c.a);
  }
  // distortion_fog.gdshader — the Distortion's slow shimmer
  shader_type canvas_item;
  void fragment() {
      vec4 c = texture(TEXTURE, UV) * COLOR;
      float s = sin(TIME * 0.6 + FRAGCOORD.y * 0.05) * 0.5 + 0.5;
      COLOR = vec4(c.rgb * (0.96 + 0.08 * s), c.a);
  }
  ```
- **Which layer a cell goes to:**
  - `reveal_state` 0 → `FogLayer`, solid;
  - 1 (known) → `WorldKnown`;
  - ≥ 2 (cleared) → `WorldCleared`;
  - beyond the map (slice-1 plan §5.1a) → `FogLayer`, solid.
- **`--preview-cleared`** (demo only): all revealed cells go to `WorldCleared`, and the badge reads exactly `DEMO MODE — preview: cleared look`. Without `--demo`, the flag is ignored and the game logs `map: --preview-cleared needs --demo`. This exists so the human can judge the art at full colour; it never changes the save.
- **Feathered fog — inward, so nothing hidden leaks.** In a revealed cell, a tile that is 0, 1, or 2 tiles from an edge shared with an unknown or beyond-the-map 4-neighbour cell also gets a `FogLayer` dither tile: 75%, 50%, or 25% respectively. Corner tiles take the denser value.
- **Zoom steps:** `{1/16, 1/4, 1, 2}`, default 1.
  - Below 1, hide the tile layers and show `OverviewLayer`: one `Sprite2D` per visible cell, with a 32 × 32 `ImageTexture` (one texel per tile), nearest filtering, and scale 32.
  - Texel colour = the class's *map colour* (§5.3 base colours; roofs use their roof base colour). Known cells get the `known_tint` formula applied on the CPU; unknown and beyond-the-map cells are `#0d1119`.
- **Budget:** in each frame, stop starting new cell syntheses once 8 ms of that frame has gone to synthesis and blitting. Pending cells show solid fog.
- **Caches:**
  - an LRU of synthesized cells, capacity **1024** (3 KB of tiles plus a 4 KB overview texture each, ≈ 7 MiB);
  - an LRU of raw store rows per cell, capacity **256**.
- **Sign tooltip:** hovering a `SIGN` tile shows its name in a label offset (12, 12) px from the cursor. Clicking does nothing.
- **Frame time:** `FRAME_P95_MS` is measured in windowed runs only — on F9, and by the screenshot harness.
- **Retire slice 1's renderer:** delete `tile_synth.gd` and `tile_synth_test.gd` in the same commit that switches the view to `TileSynth2` (Item 8), and remove `tile_synth_test` from `EXPECTED`.

---

## 7. Proof (agent guide Item 9)

Use the screenshot harness (slice-1 plan §7.4, with zoom steps extended to `0.0625`, `0.25`, `1`, `2`) on the human's demo profile — their route, and their region converted with clipping — and save outside the repo:
1. `shot_z2.png` — zoom 2 at the default focus (the most-visited place), known look;
2. `shot_z2_cleared.png` — the same with `--preview-cleared`;
3. `shot_z1_cleared.png` — zoom 1, `--preview-cleared`;
4. `shot_z0.0625.png` — overview, known look.

Show all four to the human with `FRAME_P95_MS`, then **PAUSE** for their verdict on the look.

---

## 8. Validation

- **`map_store_v2` assertions** (extend `region_import_test.gd`):
  - the v2 columns and the `cell_flags` table exist;
  - one fixture feature per row of §2.1 and §2.2 lands with the right kind and subkind;
  - the tunnel way and the `landuse=construction` polygon are absent;
  - the straddling building is stored once, in its anchor cell, unclipped;
  - the new canonical dump hash is committed.
- **`tile_synth2_test.gd`** (new, added to `EXPECTED`):
  - **(a) Golden:** SHA-256 over the fixture cells' 3072-byte buffers plus their sign lists, committed, and identical on the Linux and macOS jobs.
  - **(b) Falsifier — geometry matters:** moving one building vertex by 32 WM-m changes the hash.
  - **(c) Falsifier — north-first:** a water polygon covering only the north half of a cell → rows 0–15 are `WATER`, rows 16–31 are not.
  - **(d) Falsifier — one building, once:** the straddling building yields exactly one door group across the two cells.
  - **(e) Falsifier — coastline side:** a copy of the fixture with the coastline reversed flips which cells are sea.
  - **(f)** The tunnel produces no `ROAD` or `PATH` tiles.
  - **(g) Seamless:** for a road crossing the boundary between cell A and its east neighbour B, A's column 31 and B's column 0 are `ROAD` or `PATH` on the same rows, with matching masks.
  - **(h)** A culvert keeps the road continuous; a `:bridge` road over the river produces `BRIDGE`.
  - **(i)** The residential polygon with no footprints gets ≥ 1 fallback house.
  - **(j)** The named POI produces exactly one sign with its name.
- **`test_gen_placeholder_atlas.py`** (in the runner): regenerating is byte-identical, and the JSON has a row for every `(class, variant)` the synthesizer can emit.
- **`map_view_test` extended:**
  - the layers exist;
  - known cells go to `WorldKnown`, cleared to `WorldCleared`, unknown to `FogLayer`;
  - orientation per §3;
  - inward feathering puts dither tiles only inside revealed cells;
  - the overview shows sprites at zoom 1/16 and hides the tile layers;
  - the cell LRU stays ≤ 1024;
  - `--preview-cleared` without `--demo` is refused.
- **Fixture v2** (`tools/generate_synthetic_pbf.py`; made-up names and coordinates near (0.01, 0.01) only). Add:
  - an oriented coastline (land to the west);
  - a railway crossing a road;
  - a named cemetery polygon;
  - a forest; a parking lot;
  - a stream crossing a road without a bridge tag; a river crossed by a `bridge=yes` road;
  - a building straddling a cell boundary;
  - a `tunnel=yes` road;
  - a residential polygon with no buildings;
  - a named library POI inside a building;
  - a `landuse=construction` polygon.

---

## 9. Doc changes that land with this slice — in the same commits
- **`design_world_generation.md` §3, "Geometry → tiles":** replace steps 1–4 with a summary of §3–§4 and a pointer here; tiles are 8 WM-m.
- **`design_game_state_and_models.md` §2:** 32 × 32 tiles of 8 WM-m; `tile = floor(x / 8)`; buffers north-first; screen y = −northing.
- **`master_implementation_plan.md`, Core Configurations:** `tileMeters = 8`.
- **`design_art_direction.md`:** §3 — placeholder autotiles use the 16-mask scheme until final art (47-blob); §5 step 1 names `placeholder_v1`.
- **`design_memory_and_resources.md` §3.3:** map-view caches are 1024 synthesized cells and 256 raw-row cells.

---

## 10. Pass-18 amendments (2026-10-20) — agent guide Items 13–16

**What the human saw:** close-ups of their area with no buildings at all — tan path tiles, parking, grass, and broken rail pieces. **What was measured:** of 29,319 drawable building footprints in the area, about 13% were placed; path tiles covered 26.5% of the map (F51). §10.1–10.3 fix that; §10.4–10.6 fix the rail art, the speed, and the proof.

### 10.1 Minor ways are not drawn (F51 a) — amends §2.2
Pokémon maps show streets and footpaths, never sidewalks, parking aisles, or driveways. The converter stores **no** line for a way that matches any of these:
- `highway=service`, whatever its `service=*` value;
- any `highway=*` carrying `footway=sidewalk|crossing|traffic_island|access_aisle|link`;
- `highway=cycleway` carrying `cycleway=crossing|sidewalk`;
- `highway=footway|path|pedestrian` with `area=yes` (already excluded) or with `indoor=yes`.

The converter must therefore keep the `footway`, `cycleway`, `service`, and `indoor` tags when it reads highway ways (extend the tag list at `region_converter.gd:555` as needed).

- **Bump the store to `schema_version = '3'`.** The map view skips older stores with `map: skipping <file name> — store schema <v>, need 3`. Stores are regenerable; the human's demo store is re-converted in Item 13.
- **Keep:** footways, paths, cycleways, tracks, steps, and pedestrian streets that match none of the rules above — park trails and real footpaths.

### 10.2 Building placement v2 (F51 b) — amends §4.1 step 4 and §4.2
1. **Split the line layer.**
   - Step **4a** draws waterways, rail, and **roads** (the `road` kind) before buildings.
   - Step **4b** draws the `path` kind **after** buildings (§4.2–4.3). A path tile never overwrites `ROOF`, `WALL`, or `DOOR`; it simply skips those tiles.
   - Door paths come after 4b, as before.
2. **What may lie under a template:** `GRASS`, `TALL_GRASS`, `TREE`, `CROP`, `SAND`, `MARSH`, `FLOWERS`, and **`PLAZA`** (parking beside a shop becomes building).
   - A template is rejected if any of its tiles is `WATER`, `ROAD`, `PATH` (at this stage only road-drawn paths exist), `RAIL`, `BRIDGE`, `VOID`, `GRAVE`, `FENCE`, `ROOF`, `WALL`, `DOOR`, or a **reserved** tile.
3. **Drop the all-round ring.** Only the template's **south ring row** — the row just below the template, its door's way out — is checked. It must not be `WATER`, `RAIL`, `BRIDGE`, `VOID`, `ROOF`, `WALL`, or `DOOR`.
   - When a building is placed, its south ring row is marked **reserved**, so no later template can cover it.
   - **The effect:** buildings may stand side by side east–west, with no gap. North–south they always keep a one-tile walkway, because each building's door row stays clear.
4. **Nudge before giving up.** If the snapped position is rejected, try these `(column, row)` offsets in order and take the first that passes, still clamped to `[5, 35 − w]` × `[5, 35 − h]`: `(0,0) (1,0) (−1,0) (0,1) (0,−1) (1,1) (−1,1) (1,−1) (−1,−1) (2,0) (−2,0) (0,2) (0,−2)`.
5. **The same rules apply to fallback houses** (§4.3), which are still placed after all real buildings.
6. **Statistics.** `synthesize_cell` also returns `"stats": {"building_candidates": n, "buildings_placed": m}`. Candidates are centre-anchored footprints with A ≥ 60; fallback houses are counted separately as `"fallback_placed"`.
7. **Template sizes are unchanged** (`house_s` 4 × 3, `house_m` 5 × 4, footprint-sized `block_l`) — *amended by §13: `house_s` is 4 × 4.*

### 10.3 Targets — measured on Washington DC
*Changed 2026-10-20:* the human's own area is no longer a famous place (Decision 25). The canonical measurement city is **Washington DC** — a famous city, a 21 MB file, public, and nothing private to keep out of the repo.

**The store:** `python3 -I tools/map_convert.py --pbf <district-of-columbia-261001.osm.pbf> --out-dir user://measure_dc`. That's the pinned snapshot (`design_famous_places.md` §7) — download it and its `.md5` from `https://download.geofabrik.de/north-america/us/district-of-columbia-261001.osm.pbf`.

**New tool:** `tools/measure_synth.py --store <user:// path to a map store>`.
- It runs Godot headless with `res://scenes/measure_synth.tscn` under memguard step `measure_synth` (measure the budget on its first run).
- It synthesizes every **built-up cell** — a covered cell whose own store rows include at least one building, and whose 3 × 3 neighbourhood is covered.
- It prints one line, with counts and percentages only:
  `MEASURE cells=<n> candidates=<n> placed=<n> placement_pct=<x> building_tile_pct=<x> path_tile_pct=<x> road_tile_pct=<x>`

**Baseline on 2026-10-20** — pass-17 code, the pinned DC snapshot, converted unclipped in 16.7 s:
- **136,325** building candidates;
- placement ≈ **9.5%** (by door count; exact `stats` don't exist yet);
- over the 3,706 built-up cells: building tiles **3.6%**, path tiles **30.6%**, road tiles 4.1%;
- the DC store holds 71,814 footway and 25,817 service pieces, against 11,766 residential streets.

**Targets after Item 13:**

| Measure | Target | Baseline | After Item 13 |
|---|---|---|---|
| Placement (`placed / candidates`) | **≥ 45%** | ≈ 9.5% | **32.5%** (44,267 / 136,325) |
| Building tiles (`ROOF + WALL + DOOR`) | **≥ 12%** of built-up tiles | 3.6% | **18.9%** |
| Path tiles | **≤ 18%** of built-up tiles | 30.6% | **16.6%** |

If the rules above, implemented exactly, miss a target, **do not tune them silently.** Report the measured numbers, then STOP and file a decision with options — for example, a 3 × 3 small house, or allowing buildings over minor paths.

### 10.4 Connected rail art (F53) — amends §5.4
Rail becomes a connector tile, like a pipe:
- a full-tile gravel bed (`#a09080`), with **no frame**;
- for each mask bit that is set, track runs from the tile centre to that edge: two rails 6 px apart, with sleepers every 6 px across them;
- with exactly one bit set, the track also runs to the opposite edge (a straight end piece); with no bits set, it runs east–west;
- two adjacent bits (for example N + E) meet at the centre as an L.

A stair-stepped diagonal now reads as one continuous zig-zag line. Regenerate `placeholder_v1.png` and its JSON, keeping the byte-for-byte regeneration test.

### 10.5 Synthesis off the main thread (F52) — amends §6 "Budget"
1. **One worker thread.** A single `Thread` (the synthesis worker) owns its **own** read-only `MapStore` connections, opened inside the worker. SQLite handles are never shared across threads. It also keeps its own raw-row LRU (256 cells).
2. **Requests.** The main thread posts requests for visible cells that aren't synthesized yet, nearest to the camera centre first. At most 64 are queued; requests for cells that left the view are dropped.
3. **Work on the worker.** The worker runs `TileSynth2.synthesize_cell` and, at zoom < 1, also builds the overview `Image` (texel colours as §6). It returns `{cell, tiles, signs, image}` through a mutex-guarded queue.
4. **Main thread per frame:** take finished results; blit **at most 2 cells** into the TileMapLayers, or create at most 8 overview `ImageTexture`s at zoom < 1. Cells still waiting show solid fog, as now. Reveal-state queries stay on the main thread (the save's `DB` autoload).
5. **Targets:**
   - steady-state `FRAME_P95_MS` **≤ 16.6 ms** at zoom 1 **and** at zoom 1/16, measured over 120 frames after `pending_cell_count() == 0`;
   - while loading, no single frame over **33 ms**.

   The screenshot harness prints `LOAD_TIME_MS`, `LOAD_MAX_FRAME_MS`, and the steady-state `FRAME_P95_MS`.

### 10.6 Proof v2 — amends §7
0. **Where:** a DC demo profile (`--demo-dir user://demo_dc`) holding a route the agent draws through public DC landmarks (National Mall, Union Station, Dupont Circle, Capitol Hill), saved outside the repo, with DC's store converted from the pinned snapshot into `user://demo_dc/map_data/`. Public places only, so DC may be named in commits.
1. **New harness flag:** `--focus=most_visited|most_buildings` (default `most_visited`). `most_buildings` focuses on the revealed cell with the most `DOOR` tiles; ties go to the lower `(cy, cx)`.
2. **The harness also prints `VISIBLE_DOORS <n>`** — door tiles inside the captured view.
3. **Screenshots** (saved outside the repo):

   | File | Zoom | Focus | Look |
   |---|---|---|---|
   | `shot_z2_mv_cleared.png` | 2 | `most_visited` | `--preview-cleared` |
   | `shot_z2_mb_cleared.png` | 2 | `most_buildings` | `--preview-cleared` |
   | `shot_z1_mb_cleared.png` | 1 | `most_buildings` | `--preview-cleared` |
   | `shot_z0.0625.png` | 1/16 | — | known look |

4. **Acceptance:** `shot_z2_mb_cleared` shows **≥ 3** doors and `shot_z1_mb_cleared` shows **≥ 8**, by `VISIBLE_DOORS`. Every steady-state `FRAME_P95_MS` is ≤ 16.6 ms.
5. **Show all four to the human,** saying plainly that the art is still the placeholder until the Emerald import (agent guide Item 12). **PAUSE** for their verdict.

### 10.7 Fixture and test additions
**Fixture v3** (`tools/generate_synthetic_pbf.py`; made-up names and coordinates only) adds:
- **a residential street with three houses** (footprints 12 × 14 WM-m, centres 18 WM-m apart) along its north side;
- **`footway=sidewalk` ways** along both sides of that street, and a `highway=service` + `service=driveway` way to each house;
- **a shop building** whose footprint overlaps an `amenity=parking` polygon.

**New `tile_synth2_test` assertions:**
- **(k) Falsifying:** the sidewalks and driveways are absent from the store. At least 2 of the 3 houses are placed — the pass-17 rules place at most 1.
- **(l)** The shop is placed over the parking.
- **(m)** Every placed building's south ring row is clear of buildings.
- **(n)** `stats` matches a hand count for the fixture cells.

Commit the new golden hashes, and say in the commit why they changed.

### 10.8 Enterable landmarks on the map (Decision 27) — agent guide Item 22
Famous interiors (`design_interiors_and_quests.md` §4) must be recognisable on the map before they can be entered (interiors are built in Phase 7).
1. **Input.** For each cell, the map view passes the famous interiors whose `door` (from `game/config/famous_places.json`) lies in the 3 × 3 neighbourhood: `area[offset]["landmarks"] = [{"id", "name", "door_wm": Vector2}]`. It is projected once with `Grid.latlon_to_wm`.
2. **Synthesis.** After §4.2's placement:
   - a placed building whose template contains the landmark's door tile becomes a **landmark**: its `ROOF`, `WALL`, and `DOOR` tiles get variant bit **32** (`ROOF` 32 + colour is ignored and drawn gold; `WALL` 32 or 40 with a window; `DOOR` 32);
   - a `SIGN` carrying the landmark's name goes beside the door, with priority above every §4.4 category;
   - if no placed building contains the door — a bridge, an arch, an outdoor structure — place only the sign, on the first `GRASS` or `PATH` tile within 2 tiles of the door;
   - at most 4 landmarks per cell.
3. **Atlas** (§5): add rows for `(ROOF, 32)` (gold `#d8a838` / shade `#a07820`), `(WALL, 32)`, `(WALL, 40)`, and `(DOOR, 32)` (the door framed in gold). Regenerate byte-identically.
4. **Tooltip.** Hovering a landmark's sign or door shows `<name> — can be entered (interiors arrive in a later update)`.
5. **Tests.** Fixture v4 gains one `famous_places_fixture.json` interior whose door sits on a fixture building.
   - **Falsifying:** with the entry, that building's roof tiles carry bit 32 and a sign has its name; without it, they don't.
   - A landmark whose door misses every building yields a sign only.
   - The atlas JSON covers the new rows.


---

## 11. Pass-19 amendments (2026-10-21) — landmarks that always show, a ruined world, and honest frame targets — agent guide Items 24–25

**What the human asked for** (Decision 30): "lets take some creative liberties like removing some houses so we don't literally have to walk through fields of homes. We should play into the theme of civilization being gone. Maybe show broken homes or overgrown grass, etc."

**What was measured in pass 19:**
- **F54:** two of DC's four landmarks don't show — the Library of Congress isn't drawn at all, and the Lincoln Memorial isn't gilded.
- **F56:** the whole-city overview drops frames (`FRAME_P95_MS` 18.06), and the 16.6 ms target was below vsync's own 16.67.

§11.1 fixes F54. §11.2–11.4 are the ruin pass. §11.5 fixes F56. §11.6–11.7 are the proof and the tests.

### 11.1 Landmarks first (F54) — amends §4.2 and §10.8 — Item 24 (built)
1. **Find each landmark's footprint before anything is placed.** For each landmark in the centre cell (at most 4, in `famous_places.json` order), take:
   - the centre-anchored building candidate (§4.2, A ≥ 60) whose outer ring contains the door point;
   - else the candidate whose outer ring passes within **2 store units** (32 WM-m, 4 tiles) of the door point — nearest first, ties to the larger A, using point-to-segment distance on the unclipped footprint;
   - else none. The landmark is then an outdoor structure and gets a sign only (§10.8 step 2, unchanged).
2. **Place landmark footprints first,** before the descending-area loop:
   - **What may lie under the template:** §10.2 step 2's list, **plus `PATH`**. At this stage, `PATH` comes only from minor roads (w ≤ 2) and is drawn again around the building by door paths.
   - **Still rejected:** `WATER`, `ROAD`, `RAIL`, `BRIDGE`, `VOID`, `GRAVE`, `FENCE`, another building's tiles, and reserved tiles. The south-ring check (§10.2 step 3) is unchanged.
   - **Nudges:** §10.2's 13 offsets, then `(3,0) (−3,0) (0,3) (0,−3) (4,0) (−4,0) (0,4) (0,−4)` — 21 in all.
   - **Shrink to fit:** if every nudge fails, retry all 21 with `w − 2` and `h − 2` (a `block_l` stops at 6 × 5), then as `house_m` (5 × 4), then as `house_s` (4 × 4, §13).
   - **Its door** is the template door column nearest the real door point's column.
   - A placed landmark leaves the ordinary candidate list.
3. **Gild it at placement time:** `ROOF` 32, `WALL` 32 or 40, `DOOR` 32 — the door-inside-template test is gone. Its sign goes beside its door, as §10.8 says.
4. **Statistics:** `stats` gains `"landmarks_placed"` and `"landmarks_sign_only"`.
5. **New `tools/check_landmarks.py --store <a place store> --place <place id>`.**
   - It runs Godot headless (`res://scenes/check_landmarks.tscn`) under memguard step `check_landmarks`.
   - It prints one line per interior of the place: `LANDMARK <interior id> placed=<0|1> gold_tiles=<n> sign=<0|1>`. Interior ids are public slugs.
   - **Acceptance on DC:** the Library of Congress, the Air and Space Museum, the Washington Monument, and the Lincoln Memorial each print `placed=1` and `gold_tiles > 0`.
   - **Baseline** (pass 19, read-only): the Library of Congress `placed=0`; the Lincoln Memorial `gold_tiles=0`.

### 11.1a Pass-21 amendments — a building the converter dropped, and a door across a cell edge (F54 follow-up, Item 24 — built)
Item 24 built §11.1 exactly. Three of DC's four landmarks then passed, but the Lincoln Memorial still printed `placed=0`. Pass 21 confirmed two causes, both gaps in this plan rather than in the code.

**1. The converter drops real buildings tagged `building:part=no`** — amends §2.1.
- The Lincoln Memorial's outline in OpenStreetMap (way 398769543) is tagged `building=yes` *and* `building:part=no` — "this is the whole building, not a part".
- `region_converter.gd:1768-1769` drops any way that has the `building:part` key, whatever its value, so the memorial never reached the store. The cells around it hold only a park polygon and four small outbuildings.
- **The rule now:** a way with `building=*` (not `no`) is a building **unless** it also carries `building:part` with a value other than `no`. A way with only `building:part=*` is never stored, as before.

**2. A landmark whose door and building fall in different cells is never matched** — amends §11.1 step 1.
- The memorial's footprint straddles a cell edge. Its bounding-box centre, and so its anchor cell (§2.3), is one cell south of the cell that holds its door point.
- §11.1 looked only at landmarks whose door lies in the centre cell, and only at buildings anchored there, so neither cell could match the pair.
- **The rule now — every cell sees the whole 3 × 3 neighbourhood:**
  - **Landmarks considered:** those whose door lies anywhere in the nine cells — `area[offset]["landmarks"]` for every offset, which the map view already passes (§10.8 step 1).
  - **Footprints considered:** buildings anchored in **any** of the nine cells. Those from offset `(dx, dy)` are shifted by `(16·dx, 16·dy)` store units into the centre cell's frame, and they're tested by §11.1 step 1's rules: door inside the outer ring, else the nearest within 2 store units.
  - **Ties** go to the larger A, then the lower `(dy, dx)` offset.
  - **Then each cell acts only on what it owns:**
    - if the chosen footprint is anchored in the **centre** cell, place and gild it here (§11.1 steps 2–3), with its sign beside its door;
    - if it's anchored in **another** cell, do nothing here — that cell places it;
    - if **no** footprint is found and the door lies in the centre cell, place the sign only, as before.

  Every cell evaluates the same choice from the same data, so each landmark is drawn exactly once.
- **The 4-per-cell cap** counts landmarks *placed* in the cell, taken in offset order (`dy`, then `dx`, from −1 to 1), then in list order.

**3. Report which landmarks were placed.**
- `stats` gains `"landmark_ids_placed"`, the interior ids placed in this cell.
- `tools/check_landmarks.py` synthesizes the door's cell **and its 8 neighbours**. It prints `placed=1` if any of them placed the landmark, and sums `gold_tiles` over all nine.

**Rejected:**
- **A wider search radius** (the implementor's option B) would gild a nearby cabin as "the Lincoln Memorial".
- **Moving the door** (option C) points at the same cabin.
- Both would draw the wrong building.

**Tests:**
- **`region_import_test` — falsifying:** a fixture way tagged `building=yes` + `building:part=no` is stored; one tagged only `building:part=yes` is not; one with `building=yes` + `building:part=yes` is not.
- **`tile_synth2_test` (p.4) — falsifying:** a fixture landmark whose footprint straddles a cell edge, door in the north cell and anchor in the south cell.
  - The south cell gilds it and gets its sign.
  - The north cell places **no** sign-only fallback.
  - Both cells report it exactly once between them, in `landmark_ids_placed`.
- **Re-convert DC** (`user://measure_dc` and `user://demo_dc`) from the pinned snapshot. There's no schema bump here; Item 26's bump to `'5'` re-converts every store anyway.
- **Acceptance:** all four DC interiors print `placed=1` and `gold_tiles > 0`. Report `measure_synth`'s numbers beside pass 18's — a few more buildings will now be stored.

### 11.2 The ruin pass (Decision 30) — Item 25
A new step **5d** runs after landmarks and fallback houses and before door paths. Step **6.5** runs after parks and cemeteries and before scatter. Both are pure functions of the cell, its 3 × 3 neighbourhood, the place's Waypost, and `MAP_SEED`, so every player sees the same ruins.

1. **Input.** `area["waypost_wm"]: Vector2` is the loaded place's Waypost, projected once with `Grid.latlon_to_wm`. The map view and the synthesis worker pass it, and a store with no place (tests, legacy clips) passes none.
2. **Band.** `d` = the ground distance from the centre cell's centre to the Waypost (`Grid.ground_distance_m`). It's one value per cell, so every building in a cell shares a band:

   | Band | `d` | |
   |---|---|---|
   | `camp` | < 600 m | where the survivors live — kept tidy |
   | `near` | 600 m – 1.5 km | |
   | `mid` | 1.5 – 3 km | also used when there is no Waypost |
   | `far` | ≥ 3 km | |

3. **Each ordinary building's fate.**
   - Every placed real building and fallback house gets `f = u(gx0, gy0, 9)`, where `(gx0, gy0)` is its template's top-left global tile. Landmarks are never ruined.
   - With the band's `standing / ruined / gone` shares as `s / r / g` (percent, below), the fate is **standing** if `f < s/100`, **ruined** if `f < (s + r)/100`, and **gone** otherwise.

   | Template | `camp` | `near` | `mid` | `far` |
   |---|---|---|---|---|
   | `house_s`, `house_m`, fallback houses | 70 / 20 / 10 | 50 / 30 / 20 | 35 / 30 / 35 | 25 / 30 / 45 |
   | `block_l` | 85 / 15 / 0 | 75 / 20 / 5 | 70 / 22 / 8 | 65 / 25 / 10 |

   - **Fixed fates:**
     - places of worship (`church`, `chapel`, `cathedral`, `temple`, `mosque`, `synagogue`, `religious`) always **stand**, out of respect (`design_interiors_and_quests.md` content rules);
     - `hospital` and `clinic` are always **ruined**, never gone, because they root haunted zones and their doors must stay;
     - subkind `ruins` is always **ruined**.
4. **Drawing a ruined building:**
   - every `ROOF`, `WALL`, and `DOOR` tile of its template gets variant bit **16** — a holed roof, boarded windows, a boarded door;
   - roof tiles where `u(gx, gy, 10) < 0.25` become `RUBBLE` (variant 0): the roof has fallen in there;
   - one `RUBBLE` (variant 0) on the first `GRASS` tile of the template's east ring column, else its west ring column, scanning top to bottom;
   - `GRASS` tiles within 1 tile of the template (Chebyshev) become `TALL_GRASS` where `u(gx, gy, 11) < 0.50`;
   - its door path is still drawn.
5. **Drawing a gone building:**
   - every template tile becomes `GRASS`, then `TALL_GRASS` where `u(gx, gy, 11) < 0.60`;
   - one `RUBBLE` (variant 1) on the template's centre tile, and a `TREE` on its top-left tile where `u(gx0, gy0, 12) < 0.50`;
   - no door path, and its door leaves `all_doors`, so no flowers grow by it and no sign anchors to it — a POI sign there falls back to §4.4's "any other POI" rule;
   - its south ring row stays reserved, so the rest of the layout doesn't move.
6. **Overgrowth on the ground** (step 6.5):

   | Rule | `camp` | `near` | `mid` | `far` |
   |---|---|---|---|---|
   | `PATH` → `TALL_GRASS` where `v(gx, gy) >` | never | 0.80 | 0.72 | 0.65 |
   | other `PATH` → variant 1 (overgrown) where `u(…, 13) <` | 0.10 | 0.25 | 0.40 | 0.55 |
   | `ROAD` → variant 1 (cracked) where `u(…, 4) <` — replaces §4.1 step 10's flat 0.20 | 0.10 | 0.20 | 0.35 | 0.50 |
   | `PLAZA` → variant 1 (weeded) where `u(…, 14) <` | 0.10 | 0.50 | 0.50 | 0.50 |
   | `PLAZA` → `TALL_GRASS` where `v >` | never | never | 0.60 | 0.55 |
   | tree scatter in residential land — replaces §4.1 step 8's 0.08 | 0.08 | 0.10 | 0.13 | 0.16 |

   - `PATH` here includes minor roads (w ≤ 2), which is where "grass pushing through side streets" belongs.
   - `TALL_GRASS` stays walkable, so no route is cut.
   - Major roads (`ROAD`, w ≥ 3) only crack.
7. **Salts:** 9 building fate · 10 roof collapse · 11 yard and lot grass · 12 lot tree · 13 path overgrowth · 14 plaza weeds.
8. **Placeholder art** (§5), regenerated byte-identically:
   - rows `(ROOF, 16–23)`, masked: the roof colour with dark holes showing rafters;
   - `(WALL, 16–31)`: cracked walls, the window variants boarded with planks;
   - `(DOOR, 16–23)`: a boarded door;
   - `RUBBLE` 0–1: broken masonry with grass tufts;
   - `(PATH, 1)`, masked: path with grass through it;
   - `(PLAZA, 1)`: a cracked lot with weeds.

   The palette adds rafters `#3a2a20`, planks `#8a6a40`, and rubble `#8a7a6a` / `#5a4a40`, staying at 64 colours or fewer. The rip-trap rule is unchanged.

### 11.3 How the ruins read — the rules behind the numbers
- **A ruin, not a wasteland.** Even in the `far` band, a quarter of the houses stand and a third are only ruined, so streets stay readable as streets.
- **Tidier near the Wayposts.** The `camp` band is where survivors live, so the player's first steps out of a Waypost are through kept streets.
- **Big buildings outlast houses.** Offices, schools, and stations mostly stand, so downtowns keep their shape.
- **Landmarks always stand** — they're the story.

### 11.4 Targets — the emptied town, measured on DC
`tools/measure_synth.py` prints a second line:
`MEASURE_RUIN standing_pct=<x> ruined_pct=<x> gone_pct=<x> building_tile_pct=<x> rubble_tile_pct=<x> tall_grass_pct=<x> landmarks_standing=<n>/<n>`

| Measure (over DC's built-up cells) | Target | Pass 18 |
|---|---|---|
| Building tiles (`ROOF + WALL + DOOR`, standing and ruined) | **10–16%** of built-up tiles | 18.9% |
| Ordinary buildings **gone** | **20–45%** of those placed (Decision 37 = A) | 0% |
| Ordinary buildings **ruined** | **20–35%** | 0% |
| `TALL_GRASS` tiles | **≥ 8%** of built-up tiles | not measured |
| Landmarks standing | **all** | — |
| Path tiles | **≤ 18%** (unchanged) | 16.6% |

The placement target of §10.3 (45%) is retired (Decision 28, answered by Decision 30). **If the rules above, implemented exactly, miss a target, do not tune them silently:** report the numbers, then STOP and file a decision.

### 11.5 Frame-time targets and the overview (F56) — amends §10.5 — Item 25
1. **Targets:**
   - steady-state `FRAME_P95_MS` **≤ 16.7 ms**, which means no dropped frame at 60 Hz vsync (16.67 passes);
   - `LOAD_MAX_FRAME_MS` **≤ 33.4 ms**, at most one dropped frame.

   The harness also prints `VSYNC_MS <x>`, the display interval it measured against.
2. **Overview chunks.**
   - At zoom < 1, cell overviews are composed into **8 × 8-cell chunks**: one 256 × 256 `Image` and one `Sprite2D` per chunk, with its origin at `(floori(cx / 8.0)·8, floori(cy / 8.0)·8)`. They replace one sprite per cell.
   - The main thread `blit_rect`s each finished 32 × 32 cell overview into its chunk's `Image`, and calls `ImageTexture.update()` for at most **4 chunks per frame**.
3. **Acceptance in the DC demo profile:** at zoom 1/16 (the whole city), `FRAME_P95_MS` ≤ 16.7 (pass 18: 18.06) and `LOAD_MAX_FRAME_MS` ≤ 33.4 (pass 18: 33.33). Zoom 1 still passes both.

### 11.6 Proof v3 — Item 25
- **New harness focus:** `--focus=far_buildings` — the revealed cell with the most `DOOR` + `RUBBLE` tiles among cells in the `far` band; ties go to the lower `(cy, cx)`.
- **Screenshots** in the DC demo profile (cleared preview), saved outside the repo:

  | File | Zoom | Focus |
  |---|---|---|
  | `shot_ruins_z2_far.png` | 2 | `far_buildings` |
  | `shot_ruins_z1_far.png` | 1 | `far_buildings` |
  | `shot_ruins_z2_camp.png` | 2 | `waypost` |
  | `shot_z2_landmark.png` | 2 | `landmark` (the Library of Congress, now gilded) |
  | `shot_z0.0625_dc.png` | 1/16 | — |

- **Show all five to the human,** with the §11.4 numbers and the frame times beside their targets. Say plainly that the art is still the placeholder until the Emerald import (Item 12). **PAUSE** for their verdict.

### 11.7 Tests
- **`tile_synth2_test` (p) — landmarks first:**
  - **falsifying:** a fixture landmark boxed in by minor-road `PATH` tiles is placed and gilded, where the pass-18 rules reject it;
  - a landmark whose door point lies 2 tiles outside its footprint is still gilded;
  - a footprint too big for its gap is placed shrunk.
- **(q) Ruin fates:** fixture cells at known distances from a fixture Waypost give each building the fate a hand-computed table predicts. That includes a church that stands in the `far` band and a hospital that is ruined, never gone.
- **(r) Falsifying:** before the ruin pass, no tile is `RUBBLE` and no `ROOF`/`WALL`/`DOOR` variant has bit 16.
- **(s)** No landmark tile ever carries bit 16.
- **(t) Determinism:** the same cell twice gives identical bytes. Moving the Waypost changes only fates and overgrowth — never placement.
- **Atlas:** the JSON covers the new rows, and regeneration is byte-identical.
- Commit the new golden hashes, and say in the commit why they changed.

---

## 12. Landmark set pieces (2026-10-22) — agent guide Item 30
**Why:** the human noted that the ROM's art "might not be enough for things like the monuments in real life". A gold roof says *this is enterable*; it doesn't say *Statue of Liberty*. This section gives the famous buildings their own look: original set pieces, or Emerald look-alikes (`design_art_direction.md` §1a).

### 12.1 The register — `game/config/landmark_art.json`
- **One entry per interior id that gets a set piece:**
  - `{"source": "original", "stamp": "<stamp id>"}`; or
  - `{"source": "emerald", "composition": "<composition id>"}`, naming an entry in `emerald_tile_map.json`'s `compositions` (Item 12).
- **An interior with no entry keeps the gold-roof template** (§10.8).
- **`tools/check_famous_places.py` also checks the register:** every key is an interior id in `famous_places.json`, and every stamp or composition it names exists.

### 12.2 Original stamps — `tools/gen_landmark_stamps.py`
- **Built like `gen_placeholder_atlas.py`:** Python stdlib, deterministic, run with `python3 -I`, and regenerated byte-for-byte by a test.
- **Outputs (committed, original art):**
  - `game/assets/landmarks/stamps_v1.png` — each stamp drawn on a grid of 16 × 16-pixel tiles and saved at 2×, so a tile is 32 × 32 px, like Emerald's tiles on screen;
  - `game/assets/landmarks/stamps_v1.json` — `{"stamps": {"<id>": {"index": n, "w": tiles, "h": tiles, "door": [col, row], "origin": [x, y]}}}`.
- **Drawing rules:**
  - at most 16 colours per stamp, from `tenth_spring.gpl`, which may grow by up to 8 colours for stone, marble, copper green, and steel, staying at 64 or fewer;
  - a 1-px ink outline (`#1a1a20`) around the silhouette;
  - light from the top left — highlights on the top and left edges, shade on the bottom and right;
  - each stamp must read as its landmark at zoom 1.
  - **The rip trap applies** (`design_art_direction.md` §2): draw from code, trace nothing.
- **The 14 stamps** — sizes are tile footprints, width × height:

  | id | Landmark | Size |
  |---|---|---|
  | `liberty` | Statue of Liberty, on its pedestal | 3 × 6 |
  | `arch` | Gateway Arch | 9 × 7 |
  | `lincoln` | Lincoln Memorial | 7 × 4 |
  | `obelisk` | Washington Monument | 2 × 7 |
  | `needle` | Space Needle | 3 × 8 |
  | `coit` | Coit Tower | 2 × 5 |
  | `gg_tower` | a Golden Gate tower (the bridge deck is ordinary bridge tiles) | 2 × 7 |
  | `boston_light` | Boston Light | 2 × 5 |
  | `hatteras_light` | Cape Hatteras lighthouse, with its spiral stripe | 2 × 6 |
  | `alcatraz` | Alcatraz cellhouse | 8 × 4 |
  | `parthenon` | the Parthenon, Nashville | 7 × 4 |
  | `independence` | Independence Hall and its clock tower | 7 × 5 |
  | `grand_central` | Grand Central's facade | 9 × 4 |
  | `neon_signs` | a cluster of the Neon Museum's signs | 6 × 3 |

### 12.3 Placing a set piece — amends §11.1 step 3
1. **After a landmark's footprint is placed** (§11.1), if the register has an entry for it, try to put the set piece there instead.
   - The set piece's rectangle is anchored with its door column on the placed template's door column, and its bottom row on the template's bottom row.
   - It must pass §11.1's landmark rule: no `WATER`, `ROAD`, `RAIL`, `BRIDGE`, `VOID`, `GRAVE`, `FENCE`, another building's tile, or a reserved tile.
   - Try the same 21 nudges. If none fits, keep the gilded template.
2. **New tile class 21, `STAMP`:**
   - the variant byte is the stamp index — 0–127 for original stamps, 128–255 for Emerald compositions;
   - the mask byte is the tile's index inside the stamp, row-major (0–255);
   - it is **not walkable**, except the stamp's `door` tile, which is written as `DOOR` with variant 32, so doors stay doors.
3. **The sign** goes beside the door, as §10.8.
4. **Emerald compositions** need the Emerald import.
   - The tile-atlas builder (Item 12's plan) renders each composition into extra atlas rows at import time, on the player's machine.
   - Until the import exists, an `emerald` entry falls back to the gilded template.
5. **The renderer** draws class 21 from the stamp atlas (indices 0–127) or from the Emerald composition rows (128–255), through `asset_db.tile_atlas()`.

### 12.4 Tests and proof
- **`tile_synth2_test` (u):**
  - **falsifying:** a fixture landmark with a register entry is drawn as its stamp, where today it gets a gold roof;
  - a stamp that doesn't fit falls back to the gilded template;
  - the stamp's door tile is `DOOR` 32.
- **The stamps** regenerate byte-for-byte.
- **Proof:** in the DC demo profile at zoom 2, `--focus=landmark` on the Lincoln Memorial and on the Washington Monument. Saved outside the repo and shown to the human with the placeholder caveat. **PAUSE.**


---

## 13. Two-tile minimum widths and the 4 × 4 house (2026-10-26) — agent guide Item 12d (**built**, approved by the human 2026-10-26)

**Why.** At the Item 12 pause the human saw that Emerald has no piece for a one-tile-wide pond, footpath, street, or bridge (every Emerald one is at least two tiles wide), and that its houses have two wall rows where `house_s` has one. They answered **"Widen to 2 tiles"** and **"Houses 4 tall"**. Both change the world generator, so they follow THE LOOP: this plan first, then the human's approval, then code. The human approved it, and Item 12d built it.

### 13.1 What changes, exactly

| # | Where | Today | Becomes |
|---|---|---|---|
| 1 | §2.2 line widths and `get_road_width` | `service` 1 | `service` **2** |
| 2 | §2.2 and §4.1 step 4b (`path` lines: footway, path, cycleway, pedestrian, track, steps, bridleway) | width 1 | width **2** |
| 3 | §2.2 and `get_waterway_width` | `stream`, `ditch`, `drain` 1 (and any other value 1) | **2** (`canal` 2 and `river` 3 are unchanged) |
| 4 | §4.2 template table, the fallback house's lattice (§4.3), §10.2 item 7 ("template sizes are unchanged"), and the §11.1 shrink sequence | `house_s` 4 × 3, 2 roof rows, 1 wall row, door in column 1 or 2 of the bottom row | `house_s` **4 × 4**, 2 roof rows, **2 wall rows**, the door in the bottom row (row 3), column 1 or 2 by the same hash; windows on odd columns of both wall rows |
| 5 | `tools/rom_spike/emerald/mapping_checks.py` `TEMPLATES`, `design_art_direction.md` | `house_s` 4 × 3, door `[1, 2]` | 4 × 4, door `[1, 3]`; the derived `buildings` block is rebuilt |
| 6 | §10.2 step 8 door paths (`walk_path` from a door to the nearest connector) — **added while building; the plan had missed them** | one tile wide, in the door's column | **two tiles wide**: the door's column and the tile east of it, where only open ground (`GRASS`, `TALL_GRASS`, `FLOWERS`, `SAND`, `MARSH`) lies |

- **Brush.** The painting formula is unchanged (`lo = (w − 1) / 2`, `hi = w − 1 − lo`), so a width-2 brush covers the centreline tile and the one to its east and south.
- **Class.** A width-2 road is `PATH`, as before (`ROAD` needs w ≥ 3); a 2-wide `service` road therefore becomes `PATH`, as `tertiary` and `residential` already are.
- **Footprints.** `house_s`'s 4 × 4 still fits the fallback lattice (7 columns × 6 rows) with its reserved row below it; the shrink sequence ends `block_l` → `house_m` 5 × 4 → `house_s` 4 × 4. The `A < 400` size rule and the colour, door, and window hashes are unchanged.
- **Unchanged:** `river` 3, `canal` 2, `rail` 2, primary and secondary 3, motorway and trunk 4, every other kind, `MAP_SEED`, and the salts. The ruin pass's rules and shares are unchanged.

### 13.2 What it should fix, and what it leaves

- **Fixes:** the one-tile masks (0, 1, 2, 4, 5, 8, 10) of `WATER`, `PATH`, and `ROAD`, and the one-tile `BRIDGE` masks, can no longer occur on a streamed line. The 4 × 4 house gets Emerald's real two-wall-row art (a door lintel above the door, full-height windows).
- **Leaves (known limits, to be reported, not hidden):**
  - **Bridge decks wider than two tiles** (primary and secondary roads, 3 wide; motorway and trunk, 4): the ROM's plank deck is exactly two wide, so the extra columns have no honest piece and show the placeholder. *Option for the human later:* cap every bridge deck at two tiles.
  - **A path or road that ends, turns, or crosses** can still produce a cell with one neighbour at a tile-grid or clip edge; those cells show the placeholder, and the counts are reported.
  - **Ruined and overgrown art** still has no Emerald piece; that is the art-library question and not part of this item.

### 13.3 Targets — measure, report, and STOP if the exact rules miss

`tools/measure_synth.py` and `MEASURE_RUIN` run on DC before and after; every §11.4 target is reported beside its measured value (pass 22 in brackets):

| Measure | Target | Pass 22 | Expected effect |
|---|---|---|---|
| Path tiles | ≤ 18% | 12.8% | **rises**: footways and service roads double in width; this is the target most at risk |
| Building tiles (`ROOF + WALL + DOOR`) | 10–16% | 11.1% | rises a little: `house_s` grows by a third |
| Ordinary buildings gone | 20–45% | 42.9% | shifts slightly with placement; must stay inside |
| Ordinary buildings ruined | 20–35% | 29.7% | same |
| `TALL_GRASS` tiles | ≥ 8% | 14.0% | falls a little (paths and roads take more room) |
| Landmarks standing | all | 4/4 | unchanged |

**If an exact implementation of §13.1 misses a target, do not tune it silently:** report the numbers, STOP, and file a decision with these options — (a) raise the path ceiling to the measured figure plus a margin; (b) widen water and roads but keep footways at 1 (the one-tile footpath masks stay placeholders); (c) widen footways to 2 only near buildings.

### 13.4 Tests and proof

- **`tile_synth2_test` — falsifying:** a fixture with a service road, a footway, and a stream, each drawn one tile wide by today's code, comes out two tiles wide under §13.1 (run it against the old code first: it must fail); and a fixture house of template `house_s` has 2 roof rows, 2 wall rows, one `DOOR` in the bottom row, and windows on odd columns of both wall rows.
- **Golden hashes** of `tile_synth2_test` and every renderer test that hashes cells change: commit the new ones and say in the commit body why they changed. The synthetic PBF fixture is unchanged.
- **Emerald table:** `TEMPLATES` and the derived `buildings` block follow the 4 × 4 house; the ROM-free table tests still pass; the preview is re-rendered and shown to the human.
- **Proof:** DC at zoom 2 around a footway, a service road, a stream, and a small house, saved by the screenshot harness; the placeholder caveat stays until the Emerald import.

### 13.5 Where it goes in the queue

**Item 12d, before Item 25b.** Item 25b records the §11.4 numbers and the five ruined-city screenshots; running it first would mean doing it twice. Blast radius: `tile_synth2.gd` and its test, `design_world_generation.md` only where it quotes a width or the house size, this plan (§2.2, §4.2, §10.2, §11.1, and "built" status here), `tools/rom_spike/emerald/` (`TEMPLATES`), `design_art_direction.md`, and `ongoing_general_errors.md`.
