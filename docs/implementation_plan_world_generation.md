# Implementation Plan — World Generation (Phase 3, Slice 1: "Neighborhood Preview")

This document specifies **Slice 1 ("Neighborhood Preview")** of Phase 3 World Generation for Tenth Spring. It provides an exact, build-ready architectural plan with deterministic test cases, formal schemas, memory bounds, and measured speed and memory spike numbers.

Contracts: `docs/design_world_generation.md`, `docs/design_memory_and_resources.md`, `docs/design_privacy_and_location.md`, `docs/design_art_direction.md`.

> **Status (2026-10-19, pass 17).** Slice 1 is built (agent guide Items 3–10) and verified with corrections (`ongoing_general_errors.md` M31). The pass-16 amendments to this plan were lost before reaching `main` (F48), so on the points below **the code is the truth**, not the text further down:
> - downloads go under `user://map_data/`, never `~/.cache`;
> - the demo handshake passes the fingerprint, pairing code, and PC id from `DEMO_READY` — there is no literal `demo_pc` id;
> - only `index-v1.json` is used (it carries the download URLs too);
> - §12 #5's speed numbers were a skim, superseded by §5.3's converter gate;
> - the demo-profile test is `profile_paths_test.gd`, the CI demo import is a step in `sync_e2e.yml`, and per-item tests replaced §10.2's single `slice1_world_gen_test.gd`.
>
> **Pass 17 adds** §5.1a (USA scope, Decision 16), §5.4a (download mechanics, F44/F45), §5.5 (clip conversion and store coverage, F46), §7.1a (screen orientation, F43), and §7.4 (screenshot harness, F47) — agent guide Items 0–3, approved now. **The look itself is replaced by slice 2** (`implementation_plan_world_generation_slice2.md`, approved by Decision 17 = A).

---

## 0. Slice 1 Scope & Non-Goals

Slice 1 builds the PC game's first playable map view: displaying the player's real neighborhood as a 16 m tile overworld with two-state fog (`unknown` and `known`), populated from fully offline regional OpenStreetMap extracts (Decision 13 = C), with an input path for hand-drawn or recorded GPX routes.

### Explicit Non-Goals (Deferred to Later Slices / Phases)
- **No tall grass placement or wild encounters** (Phase 3 Slice 2 & Phase 6).
- **No landuse spawn zones beyond visual tile colour** (Phase 3 Slice 2 & Phase 6).
- **No landmark flagging or legendary creature assignments** (Phase 3 Slice 2).
- **No in-game player avatar movement, walking, or travel charging** (Phase 4).
- **No `cleared` fog state** — Slice 1 renders only `unknown` (black void) and `known` (silhouette / desaturated terrain) (Phase 4).
- **No POI interior generation, searching, or intel ceremony** (Phase 7).

---

## 1. Demo Profile — Total Save Isolation

To let the player preview their real neighborhood without risking or modifying their primary game save:

### 1.1 Command-Line Flag & Paths
- Launching Godot with the user argument `--demo` (read via `OS.get_cmdline_user_args()`) switches the storage and identity paths to disposable demo folders:
  - Database: `user://demo/tenth_spring.db` (plus `-wal`, `-shm`, `.tmp`, `.jsonbak` siblings)
  - Sync Identity: `user://demo/sync_identity/` (identity certificate and private key)
- Normal launch (without `--demo`) continues to use `user://tenth_spring.db` and `user://sync_identity/`.
- The real save path `user://tenth_spring.db` and real identity dir `user://sync_identity/` are **never** opened, created, or queried when `--demo` is passed.

### 1.2 UI Distinction
- When running in demo mode, the map window displays a prominent, high-contrast banner/chip in the top-left corner: `DEMO MODE — user://demo/`.

### 1.3 Validation Test (Godot)
- **Falsification Test (`tests/demo_profile_isolation_test.gd`)**:
  1. Ensure `user://tenth_spring.db` does not exist (or snapshot its mtime/hash).
  2. Launch game engine in demo mode (`--demo`).
  3. Perform migrations, insert synthetic visit records, and close.
  4. Assert `user://demo/tenth_spring.db` exists and contains the synthetic records.
  5. Assert `user://tenth_spring.db` was **never created** or altered.

---

## 2. PC-Only GPX Import Tool (`tools/demo_import.py`)

A standalone tool allowing players to import a GPX trace of their neighborhood directly into the demo profile on PC without requiring a phone companion.

### 2.1 Interface & Safety Guardrails
```bash
python3 -I tools/memguard.py run demo_import -- python3 -I tools/demo_import.py --gpx <path_to_gpx>
```
- **Repo Isolation Rule**: `demo_import.py` resolves `os.path.realpath(gpx_path)` and **refuses execution** if the file resides inside the Tenth Spring repository tree (enforcing Standing Constraint 5).
- **Port**: Runs a headless Godot receiver instance on dedicated demo port **7352** (preventing conflict with production sync port 7350 or test port 7351).
- **Process Model**:
  1. Starts Godot headless in demo mode loading `res://scenes/demo_import_server.tscn` listening on `127.0.0.1:7352`.
  2. Waits for TLS listener readiness by reading `E2E_READY port 7352` on stdout.
  3. Invokes the companion's real Flutter capture/sync pipeline headlessly:
     ```bash
     cd companion && flutter test test/demo_import_test.dart \
       --dart-define=DEMO_GPX=<path> \
       --dart-define=DEMO_PORT=7352 \
       --dart-define=DEMO_PC_ID=demo_pc
     ```
  4. The Flutter harness replays the GPX through `GpxReplaySource` → `VisitCorridorDetector` → `fuzzPoint` → `visit_outbox` → pinned TLS batch report to Godot.
  5. Godot's `sync_server` applies the batch to `user://demo/tenth_spring.db`.
  6. Godot outputs `DEMO_IMPORT_COMPLETE applied <N> rows`.
  7. `demo_import.py` prints summary to player: `Imported <N> scout points into demo profile.`

### 2.2 Validation
- Test with `companion/test/fixtures/synthetic_hand_drawn.gpx`: asserts exactly expected visit and corridor rows are committed to `user://demo/tenth_spring.db`.

---

## 3. GPX Interpretation Rules for Hand-Drawn Routes

Hand-drawn routes from mapping tools (e.g., GPX editors, Strava, Google My Maps) typically lack timestamps, speed, and dwell times. `GpxReplaySource` applies strict deterministic synthesis rules:

### 3.1 Synthesis Specification
1. **Track Points (`<trkpt>`)**: Treated as **corridor movement**.
2. **Waypoints (`<wpt>`)**: Treated as **visits**, assigned a synthesized dwell duration of exactly **10 minutes** (`dwellSeconds = 600`).
3. **Missing Timestamps (`<time>`)**:
   - The first point begins at synthetic epoch `t0 = 1770000000000` ms (UTC).
   - Each subsequent point calculates distance $d$ (haversine meters) from the prior point.
   - Walking speed is synthesized at exactly **1.4 m/s** (5.04 km/h).
   - $\Delta t = \mathrm{round}(d / 1.4) \times 1000$ ms.
   - Point timestamp = $t_{\mathrm{prev}} + \Delta t$.

### 3.2 Committed Synthetic Fixture
- `companion/test/fixtures/synthetic_hand_drawn.gpx` containing:
  - 1 `<wpt>` (fictional location, e.g., synthetic park center).
  - 20 `<trkpt>` without `<time>` tags outlining a fictional loop.

---

## 4. Corridor Reveal Fix (F37)

### 4.1 The Gap
`game/autoloads/sync_server.gd` `process_batch` previously revealed only the single 256 m cell containing each point. Contract `implementation_plan_foundation.md` §B4.5 mandates that corridor rows reveal every cell within `corridorRevealMeters` (60 m) of the point.

### 4.2 Algorithm
For a corridor point $P = (\mathrm{lat}, \mathrm{lon})$:
1. Compute primary cell $(c_x, c_y) = \mathrm{latlon\_to\_cell}(\mathrm{lat}, \mathrm{lon})$.
2. Bounding offset in meters: $R = 60\text{ m}$.
3. Approximate latitude delta $\Delta\mathrm{lat} = R / 111320.0$.
4. Approximate longitude delta $\Delta\mathrm{lon} = R / (111320.0 \times \cos(\mathrm{lat} \times \pi / 180.0))$.
5. Check the 9 neighbor cells in range $[c_x - 1, c_x + 1] \times [c_y - 1, c_y + 1]$.
6. For each candidate cell, compute the minimum distance from $P$ to the cell's bounding box.
7. If distance $\le R$, call `upsert_map_cell(cx, cy, REVEAL_KNOWN)` and stamp `first_revealed_at`.

### 4.3 Validation Test (`tests/corridor_reveal_radius_test.gd`)
- Place a synthetic corridor point 10 m from a 256 m cell boundary:
  - Assert **both** adjacent cells are upserted with `reveal_state = 1 (known)`.
- Place a point 100 m from a cell boundary:
  - Assert only the primary containing cell is upserted.

---

## 5. Offline Regional OpenStreetMap Extracts (Decision 13 = C)

### 5.1 Architecture & Privacy Guarantee
- **Zero Coordinate Traffic**: No Overpass API, no bounding-box REST queries, and no remote tile downloads. The game client never transmits or requests coordinates.
- **Regional PBF Source**: Whole-region extracts downloaded directly from Geofabrik:
  - Example: `https://download.geofabrik.de/north-america/us/<state>-latest.osm.pbf`
  - Checksum: `https://download.geofabrik.de/north-america/us/<state>-latest.osm.pbf.md5`
- **Region Index**: Downloaded once:
  - `https://download.geofabrik.de/index-v1-nogeom.json` (metadata & download URLs, ~500 KB)
  - `https://download.geofabrik.de/index-v1.json` (region boundary polygons, ~3.5 MB)
- **Region Selection**:
  1. When unmapped revealed cells exist, find the bounding box of those cells.
  2. Query `index-v1.json` to find the **smallest** enclosing regional polygon (e.g., State/Province).
  3. Prompt the player with confirmation modal showing region name and exact download size:
     `Download offline map for Washington (348 MB)?`
  4. On confirmation, download to `~/.cache/tenth_spring/downloads/<region>.osm.pbf`, verify MD5, and begin conversion.

### 5.1a USA Scope (pass 17 — Decision 16; agent guide Item 1)
- **Index filter.** `map_fetcher.gd` keeps only index features whose `properties.urls.pbf` starts with `https://download.geofabrik.de/north-america/us/` — 55 on 2026-10-19: the 50 states, DC, Puerto Rico, the US Virgin Islands, and California's `norcal` and `socal`. Everything else is ignored, including the whole-country `us` file and the multi-state groupings (`us-west`, `us-pacific`, …), whose URLs sit directly under `north-america/`. The smallest enclosing polygon still wins, so a Californian point resolves to `norcal` or `socal`.
- **Per-cell regions.** For each revealed, visible cell that no store covers (§5.5), find the kept region containing the cell centre (`Grid.cell_center_latlon`); cache the answer per cell for the session. Cells in no kept region are **beyond the map**.
- **Which region the chip offers:** the region containing the most of those cells; ties go to the smaller polygon area, then the lexically smaller `id`.
- **Beyond the map.** Beyond-the-map cells render fog-solid. If every unmapped visible revealed cell is beyond the map, the chip reads exactly `Beyond the map — Tenth Spring covers the USA` and is not clickable. They are never offered for download.
- **Return shape.** `select_region_for_cells(cells)` returns the chosen region dictionary as today, `{"beyond_the_map": true}` when every cell is beyond the map, or `{}` only when the index is unavailable.

### 5.2 Map Store Schema (`user://map_data/<region_id>.db`)
The converted extract lives in its own SQLite database per region, separate from the save:

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Feature polygons (buildings, parks, water, landuse)
CREATE TABLE features_poly (
  id           INTEGER PRIMARY KEY,
  cell_x       INTEGER NOT NULL,
  cell_y       INTEGER NOT NULL,
  kind         TEXT NOT NULL, -- 'building', 'park', 'water', 'residential', etc.
  geom_rings   BLOB NOT NULL  -- packed 16m cell-local coordinate vertices
);
CREATE INDEX idx_poly_cell ON features_poly(cell_x, cell_y);

-- Linear features (highways, roads, paths, waterways)
CREATE TABLE features_line (
  id           INTEGER PRIMARY KEY,
  cell_x       INTEGER NOT NULL,
  cell_y       INTEGER NOT NULL,
  kind         TEXT NOT NULL, -- 'primary', 'secondary', 'residential', 'path', 'waterway'
  geom_pts     BLOB NOT NULL  -- packed 16m cell-local polyline vertices
);
CREATE INDEX idx_line_cell ON features_line(cell_x, cell_y);

-- POI Place nodes
CREATE TABLE place_nodes (
  osm_id       INTEGER PRIMARY KEY,
  cell_x       INTEGER NOT NULL,
  cell_y       INTEGER NOT NULL,
  name         TEXT,
  category     TEXT NOT NULL,
  lat          REAL NOT NULL,
  lon          REAL NOT NULL
);
CREATE INDEX idx_place_cell ON place_nodes(cell_x, cell_y);

-- Checkpoint and state metadata
CREATE TABLE import_state (
  key          TEXT PRIMARY KEY,
  val          TEXT NOT NULL
);
```

### 5.3 Converter Gate Results (Measured on Development Machine — Apple Silicon Darwin arm64)

The full three-pass streaming PBF converter (`region_converter.gd` + `map_store.gd`) was measured under `memguard` on macOS Darwin arm64 (Apple Silicon):

| Dataset | File Size | Mode | Elapsed Time | Peak RSS | Feature Counts | Output DB Size | Canonical SHA-256 |
|---|---|---|---|---|---|---|---|
| **District of Columbia** | 20.05 MB | 3-pass streaming | **15.83 s** | **1.693 GiB** | 205,322 poly<br>136,362 line<br>3,002 place | **36 MB** | `5002878b61dee54e1ced3aef08d8d6cc7e7c5a2445d7e174f16c50e0ef2ed07d` |
| **District of Columbia (Item 18 place store v4)** | 20.3 MB (`district-of-columbia-261001.osm.pbf`) | `--place city:washington-dc` (+ 2 cells margin) | **22.77 s** | **1.695 GiB** | 194,126 poly<br>49,600 line<br>2,995 place<br>4,469 area_cells (9 areas: DC + 8 wards) | **32 MB** | `435305696de6f389001323cc7b8d67eea78407015cff5c0fedbbef2363356865` |
| **Washington** | 347.51 MB | 3-pass streaming | **~61 min** (Pass 1: ~1.5m, Pass 2: ~1.5m, Pass 3: ~58m) | **1.30 GiB** during conversion (spiked to 5.2 GiB on unchunked hash) | ~2,500,000 poly<br>~1,500,000 line<br>20,544 place | **1.0 GB** | Incomplete (stopped by memguard during hash) |
| **Clip — 38 × 33 cells (the human's area)** | — | Pre-pass + 3-pass clip | **325.15 s** (~5.4 min) | **0.710 GiB** | 48,715 poly<br>30,482 line<br>451 place | **8.2 MB** | `a066b5fdf2f9debd46bcddab9d9b076d282f3835ba26fd510fbdb0880b9d44af` |

#### Decision Rule Evaluation (Agent Guide Item 7)
- **Gate Rule:** Washington $\le 30\text{ min}$ **and** $\le 1.0\text{ GiB}$ peak RSS.
- **Evaluation:**
  - Total elapsed time was **~61 minutes** (exceeded 30 min threshold).
  - Peak RSS during conversion was **1.30 GiB** (exceeded 1.0 GiB threshold, driven by 753 MB of PackedInt64/PackedInt32 coordinate arrays for 47.2M nodes + Godot runtime and SQLite buffers).
  - Rule triggers: **STOP — commit nothing further, and file a decision with options.**

#### Decision 15: Regional Map Converter Architecture
Given that full-state OSM extraction in pure GDScript exceeds the 30-minute and 1.0 GiB thresholds when scaling to 47+ million nodes, how should regional map ingestion be architected?

- **Option A — Optimized Pure GDScript with Segment Traversal, Deferred Indices, and Disk Node Store**:
  - Replace $O(W \times H)$ bounding-box cell checking in Pass 3 with line segment grid traversal ($O(L)$), eliminating redundant clipping on long spanning highways/rivers.
  - Defer SQLite spatial index creation (`idx_poly_cell`, `idx_line_cell`) until after all rows are bulk inserted.
  - Stream `canonical_dump_sha256` in paginated 5,000-row chunks directly into `HashingContext`.
  - Store node coordinates in a temporary disk file or SQLite cache rather than 750 MB of in-memory arrays to stay strictly $\le 500\text{ MB}$ RSS.
  - *Estimated performance:* ~10–15 min conversion time, $\le 500\text{ MB}$ peak RSS. Pure GDScript remains self-contained with no external binaries or server infrastructure.
- **Option B — Pre-converted Regional Map Stores (CDN / GitHub Releases Distribution)** *(Recommended)*:
  - Pre-convert regional OpenStreetMap extracts into ready-to-use SQLite `.db` stores on a build machine or GitHub Actions runner, and host them as release assets.
  - The client simply downloads the compressed `.db` for their region (e.g. 20–100 MB compressed) directly into `user://map_data/`.
  - Ingestion becomes an instant download with zero client CPU or RAM conversion penalty, completely eliminating client conversion bottlenecks and battery drain on portable devices.
- **Option C — Native Converter (C++ GDExtension or Standalone CLI)**:
  - Implement a fast native converter in Rust or C++ (using `libosmpbf`) either as a GDExtension or an external companion CLI.
  - Converts Washington in $< 30\text{ s}$ with $< 200\text{ MB}$ RAM, but adds cross-compilation complexity across Windows, Linux, and macOS.
- **Your selection (2026-10-15): Option B — Pre-converted Regional Map Stores (CDN / GitHub Releases Distribution).** The game client will download pre-built, ready-to-query SQLite `.db` stores for regions; the streaming converter pipeline is maintained for offline pre-generation and deterministic test fixture validation.

### 5.4 Unmapped & Out-of-Region Cells
- If revealed cells fall outside all installed map stores, they render as uniform grey `#2a3242` tiles with a subtle floating chip: `Unmapped Region — Washington (348 MB)`. Clicking the chip prompts download.
- Map updates: An "Update Regional Map" button re-downloads the extract, writes to `user://map_data/<region_id>.tmp.db`, and replaces the database atomically.

### 5.4a Download Mechanics (pass 17 — F44, F45; agent guide Item 1)
1. **Redirects.** Follow at most 5 redirects with status 301, 302, 303, 307, or 308. `Location` may be absolute or start with `/`. Follow only to `https://download.geofabrik.de/`; any other target fails with `Unexpected redirect to <host>`. Geofabrik answers every `-latest` URL with 307 to a dated file (checked 2026-10-19), so this is required for any real download. A `HEAD`'s size is the `Content-Length` of the final 2xx response.
2. **Status.** A final status outside 200–299 fails with `HTTP <code>`, and no body is written.
3. **Streaming.** Set `client.read_chunk_size = 1048576`. A `GET` writes each body chunk straight to `<id>.osm.pbf.part` through an open `FileAccess`; the fetcher never holds more than one chunk. Expose `max_buffered_bytes` (the largest chunk held) for tests.
4. **Off the main thread.** `start_install(region)` runs download → MD5 → rename → convert → atomic replace on a `Thread`, calling the existing synchronous `download_and_install_region` (kept for tests). Progress reaches the scene through `call_deferred`, as signals `install_progress(stage: String, done: int, total: int)` — stage `download` (bytes), `verify`, or `convert` (pass 1–3) — and `install_finished(result: Dictionary)`.
5. **Cancel.** `cancel_install()` sets a flag checked between body chunks and, through a new `RegionConverter.cancel_requested`, before each blob. Cancelling removes `.part`, `.md5`, `.osm.pbf`, and `.tmp.db` (with its `-wal`/`-shm`) and finishes with `{"ok": false, "error": "Cancelled"}`.
6. **Progress panel** (`AttributionUI/InstallPanel`): a label reading exactly `Downloading <Name> — <done> / <total> MB`, then `Checking download…`, then `Preparing map — pass <p> of 3`, and a `Cancel` button. It hides when the install ends. On failure the chip reads `Download failed — <error>. Click to retry.`
7. **Wiring (F44).** Every 2.0 s the map view gathers the revealed, visible cells that no store covers. When that set is non-empty and differs from the last one, it resolves their region off the main thread (§5.1a — the first call may download and parse the index), showing `Unmapped — looking up map data…` meanwhile, then calls `configure_unmapped_region` with the result. No network call ever happens on the main thread.
8. **Unchanged this pass:** what gets installed. The whole-region conversion stays until Decision 15 is re-asked (F45(d)).

### 5.5 Clip Conversion & Store Coverage (pass 17 — F46; agent guide Item 2)
**Why:** converting a whole state took ~61 min for Washington, but the game only needs the area around the places the player has been. Clipping makes converting the human's own area a minutes-long developer step, and its measurements feed the Decision 15 re-ask.

1. **Interface.** `tools/map_convert.py --pbf <file> --out-dir <user://…> --clip-to-save <user:// path of a save> [--margin-cells 6]`. The Godot side opens that save **read-only**, reads `map_cell` rows with `reveal_state > 0`, and computes the inclusive cell rectangle `R = [min_cx − m, max_cx + m] × [min_cy − m, max_cy + m]` (m = margin, default 6). The clip rectangle in Web-Mercator metres is `[R.min_cx·256, (R.max_cx + 1)·256) × [R.min_cy·256, (R.max_cy + 1)·256)`. No latitude, longitude, or place name ever appears on the command line or in a log; the tool prints only counts, timings, and the rectangle's size, e.g. `clip: 41 x 37 cells`.
2. **Pre-pass** (only when clipping). Stream the dense nodes once; collect the ids of nodes inside the clip rectangle into a sorted, de-duplicated `PackedInt64Array` S, using Pass 1's chunked merge.
3. **Pass 1.** Keep a way only if at least one of its refs is in S. Keep a multipolygon relation only if at least one member way is kept — and then keep **all** its member ways, adding their refs to the needed set. If Pass 1 sees relations before ways, record member way ids and decide once both are known.
4. **Passes 2–3** run unchanged on the reduced sets. A way partly inside the rectangle is written whole and clipped per cell as usual.
5. **Coverage.** Every store records `import_state('coverage', '<min_cx>,<min_cy>,<max_cx>,<max_cy>')` — R for a clipped conversion, or the cell bounding box of all written features for an unclipped one — and `import_state('clip', '1' or '0')`.
6. **Coverage rendering.** A cell is *mapped* when it lies inside some store's coverage rectangle. A mapped cell with no features renders as plain terrain, not unmapped grey. A store without a `coverage` key (pre-pass-17) covers only cells that have features — the old rule.
7. **F46.** The converter stops storing unknown land uses as `park`: `landuse=grass|meadow|village_green|recreation_ground` → `park`; `residential`, `industrial`, `commercial`, `retail`, and `cemetery` keep their names; any other land use is not stored. `tile_synth.gd` paints only `park`, `garden`, `playground`, `pitch`, `nature_reserve`, and `cemetery` with the park colour — `residential`, `industrial`, `commercial`, and `retail` are left as terrain.
8. **Each profile reads only its own map data (F50).** `ProfilePaths` gains `map_data_dir`: `user://map_data` for the normal profile, `<demo dir>/map_data` for the demo (so a clipped store of the human's area stays in the demo profile). The map view loads stores only from that folder; tests set `user://test/map_data` explicitly through a setter. The shared search of `user://test/map_data/` is removed.
9. **Memory.** The pre-pass set and the reduced Pass 1 set stay within the converter's 1 GiB design (`design_memory_and_resources.md` §3.1); the memory-pause watchdog runs in the pre-pass too.

---

## 6. Tile Synthesis Specification (16 m Tiles)

Each 256 m `map_cell` consists of a $16 \times 16$ tile grid ($256 / 16 = 16$).

### 6.1 Tile Palette & Types
1. **Empty / Void**: Tile ID 0 (flat `#0d1119`).
2. **Terrain Fill (Grass / Ground)**: Tile ID 1 (muted green/grey).
3. **Road / Street**: Tile ID 2 (asphalt grey, minimum 1 tile wide).
4. **Building Footprint**: Tile ID 3 (structure silhouette, minimum $2 \times 2$ tiles).
5. **Park / Vegetation**: Tile ID 4 (vibrant meadow green).
6. **Water**: Tile ID 5 (deep navy water).

### 6.2 Deterministic Rasterization
`TileSynth.synthesize_cell(cell_x, cell_y, features, world_seed) -> PackedByteArray`:
- Input: Filtered geometry for $(c_x, c_y)$ from the regional map store, plus `cell_seed = hash(cell_x, cell_y, world_seed)`.
- Base pass: Fill entire $16 \times 16$ buffer with Terrain Fill (Tile 1).
- Polygon pass: Rasterize water bodies (Tile 5), then parks/leisure (Tile 4), then building footprints (Tile 3).
- Line pass: Rasterize highways and paths (Tile 2), drawing lines with Bresenham's algorithm at width $\ge 1$ tile.
- Determinism guarantee: Exactly identical tile buffers are generated given the same input features and seed.

---

## 7. Rendering, Fog & Camera Controls

### 7.1 Scene Hierarchy
```
MapViewer (Node2D)
├── BackgroundLayer (ColorRect, #0d1119)
├── WorldTileMap (TileMapLayer)
│   └── 16x16 tiles rendered with flat programmer art
├── FogOverlayLayer (TileMapLayer or CanvasItem shader)
│   ├── Unknown fog: Solid #0d1119 obscuring unvisited cells
│   └── Known fog: 40% desaturation + dark overlay (#141923 at 0.55 opacity)
├── MapCamera (Camera2D)
└── AttributionUI (CanvasLayer)
    ├── AttributionLabel ("© OpenStreetMap contributors")
    └── DemoBadge ("DEMO MODE")
```

### 7.1a Screen Orientation (pass 17 — F43; agent guide Item 0)
Godot's screen `y` grows downward; Web-Mercator `y` grows north. So:
- cell `(cx, cy)` occupies screen tile rows `(−cy − 1)·16` to `(−cy − 1)·16 + 15`; columns `cx·16` to `cx·16 + 15`, unchanged;
- slice-1 tile buffers count rows from the cell's **south** edge, so buffer row `ty` is drawn at screen row `(−cy − 1)·16 + (15 − ty)`;
- the camera focus for a cell is `x = (cx + 0.5)·256`, `y = (−cy − 0.5)·256` pixels;
- culling turns a screen row band `[y0, y1]` back into cells with `cy ∈ [−floor(y1 / 256) − 1, −floor(y0 / 256) − 1]`.

Slice 2's buffers are north-first and drop the `15 − ty` flip (slice-2 plan §3).

### 7.2 Camera Controls
- **WASD / Arrow Keys**: Smooth pan.
- **Mouse Drag**: Middle or Left click-and-drag panning.
- **Mouse Wheel**: Integer zoom steps ($1\times, 2\times, 3\times$).
- **Initial Focus**: Camera automatically centers on the player's most dwelled/visited revealed cell at boot.

### 7.3 Performance Budget & Frustum Culling
- Target: Solid **60 FPS** on desktop hardware ($\le 16.6\text{ ms}$ frame time).
- Frustum Culling: Only cells overlapping the camera's viewport plus a 1-cell margin are active in the `TileMapLayer`. Cells scrolling out of view are unrendered.
- **Measured Performance (Item 3, 2026-10-19)**: Measured on Darwin arm64 under rendered windowed harness (Vulkan Forward+, 1280×720, 120+ frames):
  - Zoom 1: `FRAME_P95_MS: 8.46 ms` ($\le 16.6\text{ ms}$ target met).
  - Zoom 3: `FRAME_P95_MS: 9.26 ms` ($\le 16.6\text{ ms}$ target met).
  - Memory: Peak RSS 0.264 GiB (budget 0.5 GiB, `demo_screenshot`).

### 7.4 Screenshot Harness (pass 17 — F47; agent guide Item 3)
**Why:** the only acceptable proof of what the map looks like is an image the game itself saved from real data (M31's process finding).
1. **User args** (after `--`): `--screenshot=<absolute path ending in .png>`, plus optional `--zoom=<one of the view's zoom steps>` (slice 1: `1`, `2`, `3`; default `1`) and `--frames=<n>` (default 10).
2. **Refusals**, each exiting 2 before any window opens:
   - the path's real path is inside the repository → `[FAIL] screenshot path must be outside the repository`;
   - an unknown zoom → `[FAIL] unsupported zoom <z>`;
   - `--headless` → `[FAIL] screenshots need a window`.
3. **Run.** In screenshot mode `main.gd` resolves the profile, opens the save, and opens the map view; it does **not** start the sync server or show the pairing screen. The map view waits until no visible cell is pending, renders `--frames` more frames, then saves `get_viewport().get_texture().get_image()` as PNG. It prints `SCREENSHOT_SAVED <file name only>`, then `FRAME_P95_MS: <x>` over the frames rendered since the map opened (at least 120 — keep rendering until there are), then quits with 0.
4. **Window.** The wrapper passes `--resolution 1280x720`. The saved PNG is 1280×720, or exactly 2560×1440 on a HiDPI screen; report which.
5. **Wrapper.** `tools/demo_screenshot.py --out-dir <directory outside the repo> [--zoom <z> ...]` runs Godot with `--demo` under memguard step `demo_screenshot` (measured the first time), refuses an in-repo `--out-dir` with exit 2, and names files `shot_z<zoom>.png`. It honours `GODOT_BIN`.
6. **Where it runs.** CI can't open a window, so the automated test covers argument parsing and the refusals only. The actual capture runs on the human's Mac, and the agent says so.

---

## 8. Legal Attribution Requirement

The OpenStreetMap ODbL license mandates clear attribution whenever map data or derived geometry is displayed:
- A persistent label is rendered on the screen corner:
  `© OpenStreetMap contributors`
- Styled with dark background padding and legible contrast.

---

## 9. Memory Protections & Low-Memory Watchdog (F39)

Following `docs/design_memory_and_resources.md` §3.1 and §3.3:

### 9.1 Converter Streaming Constraints
- **Blob Streaming**: Read via `FileAccess.get_buffer()`. Rejects headers > 64 KiB or blobs > 32 MiB.
- **Bounded In-Flight Work**: At most **4** blocks in flight concurrently.
- **No Global Node Dictionary**: Way geometry resolution uses sorted node ID arrays (`PackedInt64Array`) and binary search.
- **Memory-Pause Watchdog**:
  - Before each blob, query `OS.get_memory_info()`.
  - Pause if available memory $< \max(1.0\text{ GiB}, 10\% \text{ physical RAM})$.
  - Resume only when available memory $\ge \text{floor} + 512\text{ MiB}$ for 10 consecutive seconds.
  - UI displays: `Paused — your computer is low on memory. Map preparation will continue automatically.`

### 9.2 Map View Runtime Cap
- In-memory tile cache retains at most **256** decoded cells in an LRU eviction cache ($\le 64\text{ KiB}$ per cell $\implies \le 16\text{ MiB}$ tile data).
- SQLite map stores are opened read-only with `PRAGMA cache_size = -32768` (32 MiB).

---

## 10. Automated CI Test Pipeline (Zero Network Calls)

All slice-1 functionality is verified in CI without internet access:

### 10.1 Synthetic Fixture Generation
- `tools/generate_synthetic_pbf.py` (committed Python stdlib script) generates `game/tests/fixtures/synthetic_neighborhood.osm.pbf`:
  - Contains synthetic, made-up coordinates only (no ODbL data, no real neighborhood).
  - Contains 1 park polygon, 4 road ways, 3 building footprints, and 2 POIs.

### 10.2 CI Test Suite (`tests/slice1_world_gen_test.gd`)
1. **Demo Import Execution**: Runs synthetic GPX through demo import pipeline. Asserts visit and corridor rows applied.
2. **Corridor Cell Reveal**: Asserts cells within 60 m of corridor trace are marked `known`.
3. **Map Store Ingestion**: Converts `synthetic_neighborhood.osm.pbf` into `user://test/map_data/synthetic.db`.
4. **Tile Rasterization Parity**: Synthesizes tiles for cell $(10, 10)$ twice; asserts `hash(tiles_run_1) == hash(tiles_run_2)`.
5. **Memory Pause Test**: Simulates low-memory pause condition with mock memory reader; asserts converter pauses cleanly and resumes.

---

## 11. Privacy Guarantees

1. `.gitignore` ignores `*.gpx` and `*.osm.pbf` across the repository, excepting only committed synthetic fixtures (`companion/test/fixtures/*.gpx`, `game/tests/fixtures/*.gpx`, `game/tests/fixtures/*.osm.pbf`).
2. The player's real home coordinates and neighborhood GPX routes live strictly outside the repository tree.
3. All log statements format coordinates with at most 3 decimal places (~110 m). Full-precision floats are strictly forbidden from logs.

---

## 12. Verification & Acceptance Checklist

| # | Item | Validation Method |
|---|---|---|
| 1 | Demo profile isolation | `tests/demo_profile_isolation_test.gd`: Real save untouched when running `--demo`. |
| 2 | `demo_import.py` safety | Rejects GPX files inside repo; successfully imports external synthetic GPX on port 7352. |
| 3 | GPX synthesis rules | Unit test: waypoints yield 10-minute visits; untimed trackpoints synthesized at 1.4 m/s. |
| 4 | Corridor 60 m radius (F37) | Unit test: points within 60 m of boundary reveal both cells. |
| 5 | Streaming PBF converter | Measured under `memguard run pbf_spike`: DC (0.39 s, 0.36 GiB), WA (9.87 s, 0.13 GiB). |
| 6 | 16 m tile rasterization | Unit test: identical tile byte array produced across multiple runs. |
| 7 | Rendering & fog | Visual / headless test: `unknown` cells masked by black void, `known` cells desaturated. |
| 8 | ODbL attribution | UI assertion: `© OpenStreetMap contributors` present in scene tree. |
| 9 | Memory pause watchdog | Unit test: simulated low memory pauses worker pool; resumes on recovery. |
| 10 | CI execution | `test_runner.py` executes full suite without network calls. |
| 11 | Privacy git guard | `git status` verifies no `.osm.pbf` or `.gpx` tracked outside test fixtures. |
