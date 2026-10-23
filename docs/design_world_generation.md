# World Generation — Explore Here → Areas → Tiles

This document defines the pipeline that turns real-world exploring into the playable overworld: the two-fog state machine, how **Explore Here** unlocks areas, OSM ingestion, and tile synthesis — including the **ruin pass** that makes the cities look emptied (Decision 30).

## 1. The Two-Fog State Machine

Every real-world place passes through exactly three states. This is the game's central contract — no shortcut may ever move a place to `cleared` without in-game travel, and no real-world action may ever grant resources.

```dart
enum PlaceRevealState { unknown, known, cleared }
```

| State | Entered by | Rendered as |
|---|---|---|
| `unknown` | — (default) | Black fog. Not on the map at all. |
| `known` | An **Explore Here** report from the companion (Decision 29): tapped inside a famous city's **neighbourhood**, it reveals that neighbourhood, and enough neighbourhoods reveal the **whole city**; tapped anywhere in a famous park or wonder, it reveals the **whole place** (`design_famous_places.md` §3) | Grey silhouette tiles + "?" chip; name + category shown; no interior. |
| `cleared` | The player **traveling there in-game** and exploring it | Full-color tiles; interior mapped; item state tracked. |

## 2. Explore Here — how real places unlock (Decision 29, 2026-10-21)

> *Supersedes visit and corridor detection.* Item 19 built the per-area reveal on top of background-captured visits and corridors. Decision 29 removes background capture. The unit of real-world evidence is now **one explore event: one tap, one area.**

- **One tap, one area.** Tapping **Explore Here** takes one location reading on the phone and looks it up in the bundled **places pack** (`design_companion_and_sync.md` §1.1). If the reading falls inside a famous place, the result is one explore event naming that place and its area — a neighbourhood key for a city, the site key for a park or wonder. The reading itself is discarded.
- **The PC applies the same rules.** Each event is stored as a `visit_log` row (`kind = 'explore'`, `place_id` = the area key, no coordinates). `RevealEngine` reads area membership **from the places pack**, so the PC and the phone always agree:
  - a neighbourhood reveals all of its cells;
  - `T` neighbourhoods reveal the whole city (Decision 22);
  - a park or wonder reveals all of itself;
  - the place joins the Distort list.
- **Outside every famous place,** Explore Here says so and records nothing.
- **Retired:** visit dwell (75 m / 120 s), corridor reveals (60 m), and GPX visit and track rules. Tests and demos now use **explore points** — a list of public `(lat, lon)` points the demo tool looks up in the places pack, exactly as the phone would (`implementation_plan_explore_here.md` §6).
- **Clock rule:** timestamps are UTC epoch milliseconds. Familiarity (§4) counts **distinct UTC days**, never raw taps.

## 3. OSM Ingestion & Tile Synthesis

- **Map data source — fully offline (Decision 13 = C):**
  - **Download:** the PC downloads a whole **regional OpenStreetMap extract** (`.osm.pbf`, from Geofabrik) once per region — never per-place or per-area queries. The only thing a download reveals is which region was chosen.
  - **Choosing a region:** the region is picked from Geofabrik's region index by where the player's revealed cells are, and the player confirms each download with its size. **Only US regions count** (Decision 16): index entries whose download URL lies under `https://download.geofabrik.de/north-america/us/` — 55 on 2026-10-19 (the 50 states, DC, Puerto Rico, the US Virgin Islands, and California's `norcal`/`socal` halves). The smallest enclosing one wins.
  - **Map store:** the extract is converted once — streaming, with peak memory ≤ 1 GiB and pausing when the computer runs low (`design_memory_and_resources.md` §3.1) — into a local, spatially indexed **map store** — its own SQLite file per region, separate from the save, regenerable, and deletable.
  - **Rendering:** all tiles are read from that store. Revealed cells outside every installed region render as plain grey "unmapped" until that region is installed.
  - **Attribution:** `© OpenStreetMap contributors` is always visible on the map.
- **POI mapping**: OSM tags → `PlaceCategory` via the table in `design_resources_and_base.md`. Unmapped POIs become generic `ruin` (small mixed items).
- **Spawn-zone derivation**: each cell is assigned a `zone` from its dominant OSM land use — residential / downtown / industrial / retail / parkland / waterfront / institutional / wilds, plus the haunted zones **cemetery** (`landuse=cemetery`, `amenity=grave_yard`), **ruins** (`historic=ruins`, `building=ruins`, `abandoned:*`, `disused:*`), and **hospital** (`amenity=hospital`). Haunted zones win ties. The zone drives spawn pools and base ghost share (`design_encounters_and_haunted_zones.md` §2) and is stored on `map_cell`. Deterministic per cell.
- **Tall grass placement**: tall-grass tiles fill OSM vegetation (park, meadow, grass, scrub, wood edges) and overgrown land (`landuse=brownfield`, vacant lots, abandoned sites). **The ruin pass** (Decision 30, `implementation_plan_world_generation_slice2.md` §11) adds the collapse: lots where houses fell, grass breaking through side streets, and parking lots gone to seed. It grows wilder with distance from the place's **Waypost**, the camp survivors keep tidy. It is seeded by `MAP_SEED`, so it's the same for everyone. Tall grass is where encounters happen — its placement *is* encounter design.
- **Landmarks**: the enterable famous buildings are listed in `game/config/famous_places.json` (`design_interiors_and_quests.md` §4). On the map they get a gold roof, a highlighted door, and a name sign, and they **always stand**, whatever the ruin pass does around them. Each legendary has its own fixed place (`design_famous_places.md` §1.2) — nothing is assigned at runtime.
- **The grid**: cells and tiles are Web Mercator (`design_game_state_and_models.md` §2, `game/world/grid.gd`), so north is up and street angles are true everywhere. A tile is 8 WM-m, i.e. 8·cos(latitude) m on the ground (`CELL_SIZE_METERS = 256.0`, 32 × 32 tiles per cell).
- **Geometry → tiles**: real geometry is rasterized onto the tile grid at `tileMeters = 8` per tile via `TileSynth2` (`game/world/tile_synth/tile_synth2.gd`, detailed in `implementation_plan_world_generation_slice2.md` §3–§4):
  1. Base terrain (grass or unmapped void) & coastlines.
  2. Polygons rasterized by land cover in strict priority order (farmland, scrub, forest, park, cemetery, sand, wetland, parking, water, residential).
  3. Lines rasterized with width and snapping (waterway, rail, road, path) and bridge crossings.
  4. Building footprints placed with roofs, walls, south-facing doors, and setbacks — landmarks first (F54).
  4a. **The ruin pass:** each ordinary building's fate — standing, ruined, or gone — and the overgrowth around it (Decision 30).
  5. Edge autotiling (16-mask scheme for shorelines, tree borders, paths, roads, roofs, walls).
  6. Props, signs (from POIs and named polygons), and tall grass placement.
- **Determinism**: synthesis is a pure function of `(OSM data, cell coordinates, MAP_SEED)`. The same place always generates the same tiles, **for every player** — `MAP_SEED` is one global constant, and OSM data is one pinned snapshot per release (`design_famous_places.md` §7). Per-player seeds drive gameplay only (encounters, hauntings).
- **Home** is not on the map: it's the safehouse hub (`design_famous_places.md` §2). The companion's **Set home** picks the famous city nearest home *on the phone* and reports only that city's id (`design_companion_and_sync.md` §1). No home location reaches the PC.

## 4. Familiarity (Intel, Never Inventory)

Repeat real-world exploring raises an area's intel level: each **distinct UTC day** with an Explore Here report in that area counts once, so tapping again the same day adds nothing. Familiarity **never** yields items or Pokémon — it makes the eventual in-game exploration safer (`design_expeditions_and_survival.md` §3).

```dart
enum IntelLevel { known, familiar, mastered }  // 1+, 3+, 10+ explore days
```

| Level | Exploration effect |
|---|---|
| `known` | Interior fully dark; standard encounter rate. |
| `familiar` | Room layout and item spots pre-revealed; −25% encounter rate. |
| `mastered` | Full interior pre-mapped incl. item spots; −50% encounter rate; exit route marked. |

## 5. Scope — famous places in the USA (Decisions 16 and 25)

**The map is made only of famous places** (2026-10-20, narrowing Decision 16's "the whole USA"): **27 famous cities** (3 per Census region) and **60 famous parks, monuments, and wonders**, each hosting one legendary. The lists, the unlocking rules, Distort travel, and the same-map-for-everyone rules are in `design_famous_places.md`.
- **Everything else in the USA is off the map for now.** It's never drawn and never downloaded. An Explore Here tap there records nothing. If the scope widens later, players explore the new places then.
- **Outside the USA** stays *beyond the map* (Decision 16).
- **Each place is an island,** and you reach it by Distorting from home (`design_travel_and_time.md` §4). In-game walking happens inside places.
- **Regions and biomes (Decision 18).** Every cell belongs to one of the 9 US Census divisions (DC, Puerto Rico, and the US Virgin Islands count as South Atlantic) and gets a biome. Together they decide which Pokémon can live there (`design_encounters_and_haunted_zones.md` §2a).
- **The same map for everyone.** Map data comes from one pinned OpenStreetMap snapshot per game release, places are converted as fixed units, and drawing uses one global seed (`design_famous_places.md` §7). The per-player world seed in §3's "Determinism" applies to gameplay, never to tiles.

## 6. Files
* `companion/lib/explore/places_pack.dart` — the places-pack lookup (phone); `game/world/places_pack.gd` — the same lookup and area membership (PC).
* `tools/build_places_pack.py` — builds the pack from the pinned snapshot (development time only).
* `game/world/grid.gd` — the one lat/lon ↔ Web-Mercator cell/tile projection and ground-distance helpers (PC). Nothing else projects coordinates.
* `game/world/region_import` — regional extract download, verification, and conversion into the map store (PC).
* `game/world/tile_synth` — deterministic geometry → tile rasterizer (PC).
* `game/world/fog_store` — reveal-state persistence and queries (PC, canonical).
