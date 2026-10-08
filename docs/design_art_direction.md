# Art Direction — Diamond/Pearl, After the Collapse

Target look: **Pokémon Diamond/Pearl-era top-down pixel art** — warm, readable, charming — with a horror undertone: overgrowth, emptied towns, distortion bleeding in at the edges of the known world, and Ghost Pokémon in the dark.

The pivot changes where art comes from. **Pokémon and item art come from the player's own ROM** at runtime. **Everything else is original art** and lives in the repo.

---

## 1. Where each kind of art comes from

| Art | Source | In repo? |
|---|---|---|
| Pokémon battle sprites (front/back, shiny) — 96×96 animated (Black/White) or 80×80 still (Platinum, #1–493 only); which style is used is **Decision 10** | Player's ROMs via the importer | **Never** |
| Item icons | Player's ROM via the importer | **Never** |
| Overworld tiles (generated from OSM) | Original | Yes |
| Player overworld sprite, battle UI, menus, fonts | Original | Yes |
| Battle backgrounds per zone | Original | Yes |
| Fog, distortion, night, and lamp effects | Original shaders | Yes |

Gen 4 overworlds are 3D models, not 2D tilesets, so there is nothing usable to extract for the overworld — and our world is generated from OpenStreetMap anyway. Overworld tiles stay original.

**Battle layout must fit both sprite sizes.** Platforms and HP boxes are laid out for a 96×96 sprite box. 80×80 sprites are centred bottom-aligned in that box at the same integer scale, never stretched, so either Decision 10 outcome renders correctly.

## 2. The rip trap — read before sourcing any tiles

**Many "Diamond/Pearl tilesets" circulating online are rips of Nintendo's art.** Committing one puts Nintendo assets into a public repo — exactly what the BYOR model exists to prevent. Before licensing any tileset: confirm the author drew it, get commercial-use-or-better license terms in writing, and prefer artists with a portfolio of original work. When in doubt, commission.

## 3. Technical spec (every original asset must comply)

- **Tiles:** 32×32 px, integer scaling only.
- **Palette:** one master palette ≤ 64 colours (`assets/palette/tenth_spring.gpl`). Day/dusk/night and **haunted-territory distortion** are shader tints over the same tiles, never separate tile sets.
- **Autotiles:** 47-blob format for grass/tall-grass/road/water/tree-line transitions; buildings from a 9-slice wall set + roof set.
- **Tall grass must read instantly** as "encounters happen here" — the single most important tile in the game.
- **Fog states:** `unknown` = solid `#0d1119` with a slow distortion shimmer (the Distortion); `known` = desaturated 40% + dark overlay; `cleared` = full palette.
- ROM sprites render at integer scale over original battle backgrounds; never recolor them.

## 4. Mood rules

- **Cozy tiles, quiet dread.** The overworld stays readable and warm by day. Dread arrives through light and colour: night's deep blue tint with warm lamp pools; haunted territory's distortion tint, which deepens per haunt stage.
- **Overgrowth everywhere.** Tall grass bursts through roads and lots; weathering increases with distance from home, so home turf feels kept and the frontier feels swallowed.
- Ghost encounters get a brief fog-in transition instead of the standard battle swirl.
- UI is diegetic-lite: a journal-style Pokédex, hand-drawn map markers, no glossy sci-fi.

## 5. Sourcing pipeline (original art only)

1. **Programmer art** through Phase 9: flat-colour placeholder tiles; Pokémon render from the ROM cache as soon as the importer exists.
2. **Base kit:** license a genuinely original top-down tileset in D/P style (§2's checks).
3. **Commissions:** player sprite, haunted interior tiles, distortion effects, battle backgrounds.
4. **AI:** concepting and mood reference only; never final assets.

## 6. Files
* `assets/palette/tenth_spring.gpl` — master palette.
* `game/assets/tiles/`, `game/assets/ui/`, `game/assets/backgrounds/` — original art.
* `game/render/tile_renderer`, `game/render/day_night_tint`, `game/render/distortion_tint`.
* ROM-derived sprites and icons are read only through `asset_db` from `user://rom_cache/`.
