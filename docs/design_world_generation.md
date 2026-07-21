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
| `cleared` | The survivor **traveling there in-game** and completing a raid | Full-color tiles; interior mapped; loot state tracked. |

## 2. Visit Detection

A **visit** = the device dwelling within `visitRadiusMeters` (75 m) of a point for ≥ `visitDwellSeconds` (120 s). Driving past does *not* count as visiting a POI — it reveals the road corridor only.

- **Corridor reveal**: any traversed route reveals map cells within `corridorRevealMeters` (60 m) of the trace as `known` terrain (streets, visible building outlines — silhouettes only).
- **Visit log**: every visit appends `(placeId, timestamp, dwellSeconds)`. Repeat visits increment familiarity (see §4).
- **Clock rule**: convert all stored timestamps to UTC epoch; familiarity math uses count + recency, never wall dates.

## 3. OSM Ingestion & Tile Synthesis

- **Query scope**: Overpass API queried lazily — only for map cells that have become `known`, never speculatively. Responses cached on-device (`osm_cache` table) with a 90-day TTL.
- **POI mapping**: OSM tags → `PlaceCategory` via the table in `design_resources_and_base.md`. Unmapped POIs become generic `ruin` (small mixed loot).
- **Geometry → tiles**: real geometry is rasterized onto the tile grid at `tileMeters = 16` per tile, then cleaned:
  1. Streets → road tiles (min width 1 tile), snapped to 4/8-directional runs.
  2. Buildings → rectangularized footprints (min 2×2 tiles) with a door tile facing the nearest road.
  3. Parks/forest → grass + tree-line autotiles; water bodies → water autotiles.
  4. Everything else → wilderness fill (grass with density noise; "overgrown" ruin props seeded by building-age heuristics).
- **Determinism**: synthesis is a pure function of `(OSM data, cell seed)`. The same neighborhood always generates the same tiles. Cell seed = hash of cell coordinates + a per-player world seed.
- **Home**: the player designates the safehouse once during onboarding (defaults to most-dwelled location). Its stored coordinates are fuzzed per `design_privacy_and_location.md` before ever touching the map layer.

## 4. Familiarity (Intel, Never Inventory)

Repeat real-world visits raise a place's intel level. Familiarity **never** yields resources — it de-risks the eventual raid.

```dart
enum IntelLevel { known, familiar, mastered }  // 1+, 3+, 10+ visits
```

| Level | Raid effect |
|---|---|
| `known` | Interior fully dark; standard ambush rolls. |
| `familiar` | Room layout pre-revealed; exits marked; −25% ambush chance. |
| `mastered` | Full interior pre-mapped incl. loot spots; −50% ambush chance; guaranteed known escape route. |

## 5. Global Scope (The Archipelago)

The map has no boundary. Travel anywhere real adds a distant island of `known` cells. Islands are stitched into one world map at true geographic offsets — in-game travel between them is possible but priced honestly by `design_travel_and_time.md` (a 500-mile island is a multi-game-day expedition with fuel logistics, or a real-life return trip).

## 6. Files
* `companion/lib/capture/visit_detector.dart` — dwell/corridor detection (phone).
* `game/world/osm_ingest` — Overpass client + cache (PC).
* `game/world/tile_synth` — deterministic geometry → tile rasterizer (PC).
* `game/world/fog_store` — reveal-state persistence and queries (PC, canonical).
