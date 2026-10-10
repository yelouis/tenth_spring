# Implementation Plan — World Generation (Phase 3, Slice 1: "Neighborhood Preview")

This document specifies **Slice 1 ("Neighborhood Preview")** of Phase 3 World Generation for Tenth Spring. It provides an exact, build-ready architectural plan with deterministic test cases, formal schemas, memory bounds, and measured speed and memory spike numbers.

Contracts: `docs/design_world_generation.md`, `docs/design_memory_and_resources.md`, `docs/design_privacy_and_location.md`, `docs/design_art_direction.md`.

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

### 5.3 Speed & Memory Spike Results (Measured on Development Machine)
The pure-GDScript streaming PBF reader prototype (`tools/pbf_spike.gd`) was executed under `memguard` on macOS Darwin arm64 (Apple Silicon) across single-threaded and multi-threaded (4 in flight) configurations:

| Dataset | File Size | Mode | Elapsed Time | Throughput | Peak RSS | Extrapolated 1.2 GB CA |
|---|---|---|---|---|---|---|
| **District of Columbia** | 20.05 MB | Single-threaded (1 thread) | **0.526 s** | 38.12 MB/s | **0.359 GiB** | 31.5 s (0.52 min) |
| **District of Columbia** | 20.05 MB | Multi-threaded (4 in flight) | **0.389 s** | 51.54 MB/s | **0.360 GiB** | 23.3 s (0.39 min) |
| **Washington** | 347.51 MB | Single-threaded (1 thread) | **11.698 s** | 29.71 MB/s | **0.334 GiB** | 40.4 s (0.67 min) |
| **Washington** | 347.51 MB | Multi-threaded (4 in flight) | **9.869 s** | 35.21 MB/s | **0.126 GiB** | 34.1 s (0.57 min) |

#### Decision Rule Evaluation
- Threshold: $\le 30\text{ min}$ and $\le 1.0\text{ GiB}$ peak RSS for the 348 MB file.
- Actual: **9.869 seconds** and **0.126 GiB peak RSS**.
- Extrapolated California (1.2 GB extract): **~34 seconds**.
- **Converter Selection**: **Pure-GDScript converter running on a background `WorkerThreadPool`**, with a streaming progress bar and memory-pause watchdog. No native C++ extension or external converter tool is needed.

### 5.4 Unmapped & Out-of-Region Cells
- If revealed cells fall outside all installed map stores, they render as uniform grey `#2a3242` tiles with a subtle floating chip: `Unmapped Region — Washington (348 MB)`. Clicking the chip prompts download.
- Map updates: An "Update Regional Map" button re-downloads the extract, writes to `user://map_data/<region_id>.tmp.db`, and replaces the database atomically.

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

### 7.2 Camera Controls
- **WASD / Arrow Keys**: Smooth pan.
- **Mouse Drag**: Middle or Left click-and-drag panning.
- **Mouse Wheel**: Integer zoom steps ($1\times, 2\times, 3\times$).
- **Initial Focus**: Camera automatically centers on the player's most dwelled/visited revealed cell at boot.

### 7.3 Performance Budget & Frustum Culling
- Target: Solid **60 FPS** on desktop hardware ($\le 16.6\text{ ms}$ frame time).
- Frustum Culling: Only cells overlapping the camera's viewport plus a 1-cell margin are active in the `TileMapLayer`. Cells scrolling out of view are unrendered.

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
