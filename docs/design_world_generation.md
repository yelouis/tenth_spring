# World Generation — GPS → Visits → Tiles

This document defines the pipeline that converts real-world movement into the playable overworld: visit detection, the two-fog state machine, OSM ingestion, and tile synthesis.

## 1. The Two-Fog State Machine

Every real-world place passes through exactly three states. This is the game's central contract — no shortcut may ever move a place to `cleared` without in-game travel, and no real-world action may ever grant resources.

```dart
enum PlaceRevealState { unknown, known, cleared }
```

| State | Entered by | Rendered as |
|---|---|---|
| `unknown` | — (default) | Black fog. Not on the map at all. |
| `known` | A detected real-world **visit** (or corridor pass for streets) | Grey silhouette tiles + "?" chip; name + category shown; no interior. |
| `cleared` | The player **traveling there in-game** and exploring it | Full-color tiles; interior mapped; item state tracked. |

## 2. Visit Detection

> **Pending change (pass 18, Decisions 21–22):** the human asked that a visit reveal its whole **neighbourhood**, and that visits to a couple of a city's neighbourhoods reveal the whole **city**. The draft is `implementation_plan_area_unlock.md`. Until it lands, the rules below stand.

A **visit** = the device dwelling within `visitRadiusMeters` (75 m) of a point for ≥ `visitDwellSeconds` (120 s). Driving past does *not* count as visiting a POI — it reveals the road corridor only.

- **Corridor reveal**: any traversed route reveals map cells within `corridorRevealMeters` (60 m) of the trace as `known` terrain (streets, visible building outlines — silhouettes only).
- **GPX rules for imported hand-drawn routes**:
  - Track points (`<trkpt>`) = corridor trace.
  - Waypoints (`<wpt>`) = visits, assigned a synthesized **10-minute** (600 s) dwell.
  - Track points lacking `<time>` receive synthesized walking timestamps at **1.4 m/s** (5.04 km/h) relative to the prior point.
- **Visit log**: every visit appends `(placeId, timestamp, dwellSeconds)`. Repeat visits increment familiarity (see §4).
- **Clock rule**: convert all stored timestamps to UTC epoch; familiarity math uses count + recency, never wall dates.

## 3. OSM Ingestion & Tile Synthesis

- **Map data source — fully offline (Decision 13 = C):**
  - **Download:** the PC downloads a whole **regional OpenStreetMap extract** (`.osm.pbf`, from Geofabrik) once per region — never per-place or per-area queries. The only thing a download reveals is which region was chosen.
  - **Choosing a region:** the region is picked from Geofabrik's region index by where the player's revealed cells are, and the player confirms each download with its size. **Only US regions count** (Decision 16): index entries whose download URL lies under `https://download.geofabrik.de/north-america/us/` — 55 on 2026-10-19 (the 50 states, DC, Puerto Rico, the US Virgin Islands, and California's `norcal`/`socal` halves). The smallest enclosing one wins.
  - **Map store:** the extract is converted once — streaming, with peak memory ≤ 1 GiB and pausing when the computer runs low (`design_memory_and_resources.md` §3.1) — into a local, spatially indexed **map store** — its own SQLite file per region, separate from the save, regenerable, and deletable.
  - **Rendering:** all tiles are read from that store. Revealed cells outside every installed region render as plain grey "unmapped" until that region is installed.
  - **Attribution:** `© OpenStreetMap contributors` is always visible on the map.
- **POI mapping**: OSM tags → `PlaceCategory` via the table in `design_resources_and_base.md`. Unmapped POIs become generic `ruin` (small mixed items).
- **Spawn-zone derivation**: each cell is assigned a `zone` from its dominant OSM land use — residential / downtown / industrial / retail / parkland / waterfront / institutional / wilds, plus the haunted zones **cemetery** (`landuse=cemetery`, `amenity=grave_yard`), **ruins** (`historic=ruins`, `building=ruins`, `abandoned:*`, `disused:*`), and **hospital** (`amenity=hospital`). Haunted zones win ties. The zone drives spawn pools and base ghost share (`design_encounters_and_haunted_zones.md` §2) and is stored on `map_cell`. Deterministic per cell.
- **Tall grass placement**: tall-grass tiles fill OSM vegetation (park, meadow, grass, scrub, wood edges) and overgrown land (`landuse=brownfield`, vacant lots, abandoned sites). The collapse setting adds overgrowth: road and lot tiles convert to tall grass with probability rising by distance band from home (0%, 10%, 25%, 40%), seeded per cell so it is deterministic. Tall grass is where encounters happen — its placement *is* encounter design.
- **Landmark flagging**: POIs tagged as famous places (e.g. `boundary=national_park`, `leisure=nature_reserve`, `tourism=attraction`, `historic=monument`, `leisure=stadium`) are flagged `isLandmark` and assigned a legendary from their archetype's pool (`design_encounters_and_haunted_zones.md` §7). Assignment is deterministic and independent of player proximity.
- **The grid**: cells and tiles are Web Mercator (`design_game_state_and_models.md` §2, `game/world/grid.gd`), so north is up and street angles are true everywhere. A tile is 8 WM-m, i.e. 8·cos(latitude) m on the ground (`CELL_SIZE_METERS = 256.0`, 32 × 32 tiles per cell).
- **Geometry → tiles**: real geometry is rasterized onto the tile grid at `tileMeters = 8` per tile via `TileSynth2` (`game/world/tile_synth/tile_synth2.gd`, detailed in `implementation_plan_world_generation_slice2.md` §3–§4):
  1. Base terrain (grass or unmapped void) & coastlines.
  2. Polygons rasterized by land cover in strict priority order (farmland, scrub, forest, park, cemetery, sand, wetland, parking, water, residential).
  3. Lines rasterized with width and snapping (waterway, rail, road, path) and bridge crossings.
  4. Building footprints placed with roofs, walls, south-facing doors, and setbacks.
  5. Edge autotiling (16-mask scheme for shorelines, tree borders, paths, roads, roofs, walls).
  6. Props, signs (from POIs and named polygons), and tall grass placement.
- **Determinism**: synthesis is a pure function of `(OSM data, cell seed)`. The same neighborhood always generates the same tiles. Cell seed = hash of cell coordinates + a per-player world seed.
- **Home**: the player designates the safehouse once during onboarding (defaults to most-dwelled location). Its stored coordinates are fuzzed per `design_privacy_and_location.md` before ever touching the map layer.

## 4. Familiarity (Intel, Never Inventory)

Repeat real-world visits raise a place's intel level. Familiarity **never** yields items or Pokémon — it makes the eventual in-game exploration safer (`design_expeditions_and_survival.md` §3).

```dart
enum IntelLevel { known, familiar, mastered }  // 1+, 3+, 10+ visits
```

| Level | Exploration effect |
|---|---|
| `known` | Interior fully dark; standard encounter rate. |
| `familiar` | Room layout and item spots pre-revealed; −25% encounter rate. |
| `mastered` | Full interior pre-mapped incl. item spots; −50% encounter rate; exit route marked. |

## 5. Scope — the USA (Decision 16, 2026-10-19)

The map is the USA: the 50 states, DC, Puerto Rico, and the US Virgin Islands — exactly the regions in §3's filter. Within it the map has no inner boundary: travel anywhere in the USA adds a distant island of `known` cells, stitched into one world map at true geographic offsets. In-game travel between islands is possible but priced honestly by `design_travel_and_time.md` — a 500-mile island is a multi-game-day trek, even by bicycle, or a real-life return trip. Alaska, Hawaii, and Puerto Rico are literal islands.

**Beyond the map.** A revealed cell whose centre lies in no US region is *beyond the map*:
- it renders as fog with the chip `Beyond the map — Tenth Spring covers the USA`;
- it is never offered for download and never counts toward anything (Pokédex, events, familiarity);
- the sync ingest still stores it like any other cell (golden invariants unchanged), so the rule lives entirely in rendering and region choice.

**Why the USA is enough.** A cross-country game is already far larger than any Pokémon region, and US federal map data — USGS elevation and land cover — is public domain, so later slices can add real terrain (ledges, cliffs, terraces) and biomes without licensing trouble. **Regions and biomes (Decision 18).** Every cell also belongs to one of the 9 US Census divisions (DC, Puerto Rico, and the US Virgin Islands count as South Atlantic) and gets a biome. Together they decide which Pokémon can live there, and where each region's Warden and legendaries are found (`design_encounters_and_haunted_zones.md` §2a and §7; `design_story_and_world.md`).

## 6. Files
* `companion/lib/capture/visit_detector.dart` — dwell/corridor detection (phone).
* `game/world/grid.gd` — the one lat/lon ↔ Web-Mercator cell/tile projection and ground-distance helpers (PC). Nothing else projects coordinates.
* `game/world/region_import` — regional extract download, verification, and conversion into the map store (PC).
* `game/world/tile_synth` — deterministic geometry → tile rasterizer (PC).
* `game/world/fog_store` — reveal-state persistence and queries (PC, canonical).
