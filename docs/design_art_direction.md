# Art Direction — Cozy Post-Apocalypse Pixel Art

Target look: **Pokémon Diamond/Pearl-era top-down pixel art** — warm, readable, charming — carrying post-collapse content (overgrowth, emptied towns, the dead). The contrast *is* the identity: cozy tiles, quiet dread.

## 1. Technical Spec (locked — every asset must comply)

- **Tile size**: 32×32 px, rendered at integer scales only (no sub-pixel).
- **Character sprites**: 32×48 px, 4 directions × 4-frame walk cycles; zombies same sheet layout (shambler/stalker 32×48, brute 48×64, apex 64×96).
- **Palette**: one master palette ≤ 64 colors, defined in `assets/palette/tenth_spring.gpl` before any asset is made. Day/dusk/night are *shader tints* over the same tiles, never separate tile sets.
- **Autotiles**: 47-blob format for grass/road/water/tree-line transitions; buildings from a 9-slice wall set + roof set per building style.
- **Fog states**: `unknown` = solid #0d1119; `known` = desaturated 40% + dark overlay, silhouette buildings as flat shapes; `cleared` = full palette.
- **Sprite sheets**: uniform grid, no trimming, one atlas per sheet (`assets/sprites/*.png` + engine import), rendered by the PC engine's tile/sprite pipeline (Godot `TileSet` + `AnimatedSprite2D` under Decision 0). All art is PC-side; the companion ships only a small static tile set for its read-only memoir view.

## 1.1 Enemy Sprite Matrix (the biggest content cost)

Enemy variety is *thematic to location* (`design_threats_and_colonies.md` §1.1), so the enemy roster is a **matrix, not a list**:

- **Base grid**: 3 tiers (shambler/stalker/brute) × 8 biomes (residential, downtown, industrial, retail, parkland, waterfront, institutional, wilds) ≈ **24 base skins**, each with 4-direction × 4-frame walk + an attack pose.
- **Plus**: colony apex variants and ~1 hand-authored **landmark boss** per landmark archetype (national park, monument, stadium, …) at 64×96+.
- **Reuse discipline**: a biome variant is a *reskin of a shared tier skeleton* (same rig, same frame timings) — recolor + a few silhouette accents (verdant vines, drowned bloat, industrial debris). Do not author each of the 24 from zero; build one skeleton per tier, then palette/accent per biome. This keeps the matrix tractable.
- **Ship-first subset**: the starter neighborhood biomes come first — `residential`, `retail`, `parkland`, `institutional` (the ones a typical player's early map is made of). `industrial`, `waterfront`, `downtown`, `wilds` and the landmark bosses follow. Gameplay is validated on placeholders regardless (see §2).

## 1.2 Item / Loot Icons (Minecraft-style, looting-based)

The game is loot-driven, so the item icon set is large and its own art track:

- **Icon size**: 16×16 px, single frame, one atlas (`game/assets/items/items.png` + index). Rendered in inventory slots, ground drops, crafting, and the stash — always on a dark ~80 px slot for contrast.
- **Read at a glance**: bold silhouette + a 4–6-color palette per icon from the master palette; outline every icon so it reads on any tile. Rarity is shown by a slot border tint (common → `unique`), never by recoloring the icon.
- **Coverage** — one icon per item, spanning the taxonomy in `design_resources_and_base.md` §2: `weapon` (melee + ranged), `armor` (head/body/shield/limbs), `parts`, `tools`, `wood`, `fabric`, `chemical`, `food`, `water`, `meds`, `fuel`, plus `special` (apex components) and `unique` (named landmark drops, which get a subtle glow accent).
- **Reference set**: a concept sheet of 12 icons (cleaver/pistol/nail bat, hard hat/plate vest/riot shield, scrap/plank/nut, canned food/first-aid/fuel can) establishes the style and the 16×16 grid. The artist/pack matches this look; it doubles as programmer-art placeholders until then.
- **Sourcing**: item icons are the *easiest* art to source or commission in bulk (static, tiny) — a licensed icon pack covers most, with custom work only for `unique`/`special` signature items.

## 2. Sourcing Pipeline (honest constraints)

AI (Claude) **cannot** produce raster pixel sprite sheets, and diffusion models are unreliable for tile-aligned, palette-locked, frame-consistent pixel art. The bigger the roster (see §1.1), the more this pipeline matters:

1. **Phase 0–6 (programmer art)**: flat-color placeholder tiles/enemies generated in code, keyed by tier+biome. All gameplay is validated on placeholders — no art blocks progress.
2. **Base kit**: license a cohesive top-down RPG tileset + a **monster/zombie sprite pack** that already spans several archetypes (itch.io / GameDev Market; verify commercial license terms in writing) matching the 32 px spec. A good pack can cover much of the tier skeletons before any commission.
3. **Custom commissions**: an Aseprite artist for the theme-specific work — the biome reskin matrix (§1.1), colony/hive tiles, overgrowth props, safehouse fortification states, and the hand-authored landmark bosses. Commission brief = this document; prioritize the ship-first biome subset.
4. **AI role**: concepting/mood reference only, plus this spec, POI→tile mapping rules, and palette discipline review. Never final assets.

## 3. Mood Rules

- Overgrowth everywhere: every urban tile set has a vine/moss/grass-crack overlay variant; weathering increases with distance from home (home turf feels kept, frontier feels swallowed).
- The dead read clearly at a glance: **tier = silhouette + base hue** (shambler moss-green, stalker pale bone, brute rust-amber, colony tissue-crimson), **biome = accent layer** (verdant vines, drowned bloat, industrial debris, ward scrubs). A player must read *tier* (how dangerous) before *biome* (flavor) at a glance — never let a biome accent obscure the tier silhouette. Landmark bosses get bespoke silhouettes that still telegraph tier 5.
- UI chrome is diegetic-lite: hand-drawn map markers, journal-style menus, no glossy sci-fi.
- Night is beautiful, not muddy: deep blue tint + warm light pools (lamp radius), never plain darkness.

## 4. Files
* `assets/palette/tenth_spring.gpl` — master palette (source of truth, shared).
* `game/assets/tiles/`, `game/assets/sprites/`, `game/assets/props/`, `game/assets/items/` — atlases (PC).
* `game/render/tile_renderer`, `game/render/day_night_tint` (PC).
* `companion/assets/memoir_tiles/` — minimal static set for the phone's read-only map.
