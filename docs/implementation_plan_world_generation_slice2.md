# Implementation Plan — World Generation, Slice 2: "Pokémon Look"

> **Status: APPROVED (2026-10-19).** Decision 17 = A approved this plan as written.
> - **Decision 19 = Emerald:** the map's real art comes from the player's Pokémon Emerald ROM (`design_rom_asset_pipeline.md` §2, §5). §5's code-drawn placeholder atlas is **still built** — it is the no-ROM look and the only atlas tests and agents ever see. The renderer (§6) loads `user://rom_cache/tiles/emerald_v1.png` + `.json` when the Emerald import is valid, and the placeholder otherwise.
> - **Both atlases share §5.2's JSON layout**, so the switch is data, not code.
> - The Emerald importer itself is a separate, ROM-gated item (agent guide Item 12). It may adjust §4.2's template sizes to fit Emerald's building compositions — through a plan amendment the human reviews.
>
> Built in agent guide Items 4–9, after Items 0–3 (slice-1 fixes, clip conversion, and the screenshot harness — `implementation_plan_world_generation.md` §5.1a, §5.4a, §5.5, §7.1a, §7.4).

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
  - A Pokémon house (4 × 3 tiles) then covers about 25 × 19 m — roughly one suburban lot — so buildings land near their real spots.
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
| `building` | the `building` value | `building=*` except `building=no`; `building:part` is ignored |
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
| `road` | the `highway` value | motorway 4, trunk 4, primary 3, secondary 3, tertiary 2, residential / unclassified / living_street / road 2, any `*_link` 2, service 1 | `highway=` one of those |
| `path` | the `highway` value | 1 | `highway=footway\|path\|cycleway\|pedestrian\|track\|steps\|bridleway` |
| `rail` | the `railway` value | 2 | `railway=rail\|light_rail\|narrow_gauge\|tram` |
| `waterway` | the `waterway` value | river 3, canal 2, stream / ditch / drain 1 | `waterway=river\|canal\|stream\|ditch\|drain` |
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
| 7 | `PATH` | yes | 0 |
| 8 | `ROAD` | yes | 0 normal, 1 cracked |
| 9 | `RAIL` | no | 0 |
| 10 | `BRIDGE` | yes | 0 |
| 11 | `PLAZA` | yes | 0 |
| 12 | `ROOF` | no | roof colour 0–7 |
| 13 | `WALL` | no | roof colour 0–7, + 8 if the tile has a window |
| 14 | `DOOR` | yes (interiors, later) | roof colour 0–7 |
| 15 | `FENCE` | no | 0 |
| 16 | `FLOWERS` | yes | 0 |
| 17 | `GRAVE` | no | 0 |
| 18 | `SIGN` | no | index into the cell's sign list, 0–15 |
| 19 | `CROP` | yes | 0 |

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
- **Salts:** 1 tree scatter · 2 flowers · 3 grass variant · 4 road cracks · 5 house door and roof colour · 6 tree variant · 7 noise lattice · 8 fallback-house skip.
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
| `house_s` | A < 400 | 4 × 3 | 2 | 1 | column 1 if `u(col0, row0, 5) < 0.5`, else column 2 |
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
