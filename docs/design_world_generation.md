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

A **visit** = the device dwelling within `visitRadiusMeters` (75 m) of a point for ≥ `visitDwellSeconds` (120 s). Driving past does *not* count as visiting a POI — it reveals the road corridor only.

- **Corridor reveal**: any traversed route reveals map cells within `corridorRevealMeters` (60 m) of the trace as `known` terrain (streets, visible building outlines — silhouettes only).
- **Visit log**: every visit appends `(placeId, timestamp, dwellSeconds)`. Repeat visits increment familiarity (see §4).
- **Clock rule**: convert all stored timestamps to UTC epoch; familiarity math uses count + recency, never wall dates.

## 3. OSM Ingestion & Tile Synthesis

- **Map data source — fully offline (Decision 13 = C):**
  - **Download:** the PC downloads a whole **regional OpenStreetMap extract** (`.osm.pbf`, from Geofabrik) once per region — never per-place or per-area queries. The only thing a download reveals is which region was chosen.
  - **Choosing a region:** the region is picked from Geofabrik's region index by where the player's revealed cells are, and the player confirms each download with its size.
  - **Map store:** the extract is converted once — streaming, with peak memory ≤ 1 GiB and pausing when the computer runs low (`design_memory_and_resources.md` §3.1) — into a local, spatially indexed **map store** — its own SQLite file per region, separate from the save, regenerable, and deletable.
  - **Rendering:** all tiles are read from that store. Revealed cells outside every installed region render as plain grey "unmapped" until that region is installed.
  - **Attribution:** `© OpenStreetMap contributors` is always visible on the map.
- **POI mapping**: OSM tags → `PlaceCategory` via the table in `design_resources_and_base.md`. Unmapped POIs become generic `ruin` (small mixed items).
- **Spawn-zone derivation**: each cell is assigned a `zone` from its dominant OSM land use — residential / downtown / industrial / retail / parkland / waterfront / institutional / wilds, plus the haunted zones **cemetery** (`landuse=cemetery`, `amenity=grave_yard`), **ruins** (`historic=ruins`, `building=ruins`, `abandoned:*`, `disused:*`), and **hospital** (`amenity=hospital`). Haunted zones win ties. The zone drives spawn pools and base ghost share (`design_encounters_and_haunted_zones.md` §2) and is stored on `map_cell`. Deterministic per cell.
- **Tall grass placement**: tall-grass tiles fill OSM vegetation (park, meadow, grass, scrub, wood edges) and overgrown land (`landuse=brownfield`, vacant lots, abandoned sites). The collapse setting adds overgrowth: road and lot tiles convert to tall grass with probability rising by distance band from home (0%, 10%, 25%, 40%), seeded per cell so it is deterministic. Tall grass is where encounters happen — its placement *is* encounter design.
- **Landmark flagging**: POIs tagged as famous places (e.g. `boundary=national_park`, `leisure=nature_reserve`, `tourism=attraction`, `historic=monument`, `leisure=stadium`) are flagged `isLandmark` and assigned a legendary from their archetype's pool (`design_encounters_and_haunted_zones.md` §7). Assignment is deterministic and independent of player proximity.
- **Geometry → tiles**: real geometry is rasterized onto the tile grid at `tileMeters = 16` per tile, then cleaned:
  1. Streets → road tiles (min width 1 tile), snapped to 4/8-directional runs.
  2. Buildings → rectangularized footprints (min 2×2 tiles) with a door tile facing the nearest road.
  3. Parks/forest → grass + tree-line autotiles; water bodies → water autotiles.
  4. Everything else → wilderness fill (grass with density noise; "overgrown" ruin props seeded by building-age heuristics).
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

## 5. Global Scope (The Archipelago)

The map has no boundary. Travel anywhere real adds a distant island of `known` cells. Islands are stitched into one world map at true geographic offsets — in-game travel between them is possible but priced honestly by `design_travel_and_time.md` (a 500-mile island is a multi-game-day trek, even by bicycle, or a real-life return trip).

## 6. Files
* `companion/lib/capture/visit_detector.dart` — dwell/corridor detection (phone).
* `game/world/region_import` — regional extract download, verification, and conversion into the map store (PC).
* `game/world/tile_synth` — deterministic geometry → tile rasterizer (PC).
* `game/world/fog_store` — reveal-state persistence and queries (PC, canonical).
