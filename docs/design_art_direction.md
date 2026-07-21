# Art Direction — Cozy Post-Apocalypse Pixel Art

Target look: **Pokémon Diamond/Pearl-era top-down pixel art** — warm, readable, charming — carrying post-collapse content (overgrowth, emptied towns, the dead). The contrast *is* the identity: cozy tiles, quiet dread.

## 1. Technical Spec (locked — every asset must comply)

- **Tile size**: 32×32 px, rendered at integer scales only (no sub-pixel).
- **Character sprites**: 32×48 px, 4 directions × 4-frame walk cycles; zombies same sheet layout (shambler/stalker 32×48, brute 48×64, apex 64×96).
- **Palette**: one master palette ≤ 64 colors, defined in `assets/palette/tenth_spring.gpl` before any asset is made. Day/dusk/night are *shader tints* over the same tiles, never separate tile sets.
- **Autotiles**: 47-blob format for grass/road/water/tree-line transitions; buildings from a 9-slice wall set + roof set per building style.
- **Fog states**: `unknown` = solid #0d1119; `known` = desaturated 40% + dark overlay, silhouette buildings as flat shapes; `cleared` = full palette.
- **Sprite sheets**: uniform grid, no trimming, one atlas per sheet (`assets/sprites/*.png` + engine import), rendered by the PC engine's tile/sprite pipeline (Godot `TileSet` + `AnimatedSprite2D` under Decision 0). All art is PC-side; the companion ships only a small static tile set for its read-only memoir view.

## 2. Sourcing Pipeline (honest constraints)

AI (Claude) **cannot** produce raster pixel sprite sheets, and diffusion models are unreliable for tile-aligned, palette-locked, frame-consistent pixel art. The pipeline is therefore:

1. **Phase 0–6 (programmer art)**: flat-color placeholder tiles generated in code. All gameplay is validated on placeholders.
2. **Base kit**: license a cohesive top-down RPG tileset + character base (itch.io / GameDev Market; verify commercial license terms in writing) that matches the 32 px spec.
3. **Custom commissions**: Aseprite artist for the theme-specific set — zombie tiers, colony/hive tiles, overgrowth props, safehouse fortification states, apex bosses. Commission brief = this document.
4. **AI role**: concepting/mood reference only, plus this spec, POI→tile mapping rules, and palette discipline review. Never final assets.

## 3. Mood Rules

- Overgrowth everywhere: every urban tile set has a vine/moss/grass-crack overlay variant; weathering increases with distance from home (home turf feels kept, frontier feels swallowed).
- The dead read clearly at a glance: tier = silhouette size + hue family (shambler moss-green, stalker pale bone, brute rust-amber, colony tissue-crimson). Color encodes threat, matching the map's danger legibility contract.
- UI chrome is diegetic-lite: hand-drawn map markers, journal-style menus, no glossy sci-fi.
- Night is beautiful, not muddy: deep blue tint + warm light pools (lamp radius), never plain darkness.

## 4. Files
* `assets/palette/tenth_spring.gpl` — master palette (source of truth, shared).
* `game/assets/tiles/`, `game/assets/sprites/`, `game/assets/props/` — atlases (PC).
* `game/render/tile_renderer`, `game/render/day_night_tint` (PC).
* `companion/assets/memoir_tiles/` — minimal static set for the phone's read-only map.
