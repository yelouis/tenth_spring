# Art Direction — Diamond/Pearl, After the Collapse

Target look: **Pokémon Diamond/Pearl-era top-down pixel art** — warm, readable, charming — with a horror undertone: overgrowth, emptied towns, distortion bleeding in at the edges of the known world, and Ghost Pokémon in the dark.

The pivot changes where art comes from. **Pokémon and item art come from the player's Black/White ROM**, and — since Decision 19 (2026-10-19) — **the overworld map tiles come from the player's Emerald ROM**, all at runtime. **Everything else is original art** and lives in the repo, including the placeholder map tiles the game shows until an Emerald ROM is imported.

---

## 1. Where each kind of art comes from

| Art | Source | In repo? |
|---|---|---|
| Pokémon battle sprites (front/back, shiny) — 96×96, animated, Black/White style, for all 649 (Decision 10 = B) | Player's Black/White ROM via the importer | **Never** |
| Item icons | Player's ROM via the importer | **Never** |
| Overworld map tiles (layout generated from OSM) | Player's **Emerald** ROM via the importer (Decision 19) | **Never** |
| Placeholder map tiles — the no-ROM look | Original, code-drawn (`placeholder_v1`) | Yes |
| Player overworld sprite, battle UI, menus, fonts | Original | Yes |
| Battle backgrounds per zone | Original | Yes |
| Fog, distortion, night, and lamp effects | Original shaders | Yes |

**Why Emerald for the map.** The DS games (Gen 4–5) draw their overworlds as 3D models, not 2D tilesets, so there is nothing tile-shaped to extract from Black/White. The Game Boy Advance games are the last Pokémon games built from true 2D tiles, and Emerald has the widest range of landscapes among them (desert, beach, forest, mountains). The *layout* is still generated from OpenStreetMap (`implementation_plan_world_generation_slice2.md`); only the pixels come from the ROM, through a committed table of metatile numbers (`design_rom_asset_pipeline.md` §5). Gen 3 tiles are 16 px and render at 2× (32 px), the same integer-scale rule as everything else. The overworld is Gen 3 in look while battles use Black/White sprites; the two never share a screen.

**Battle layout** is built for a 96×96 animated sprite box at integer scale, never stretched.

## 2. The rip trap — read before sourcing any tiles

This applies to every piece of art that **isn't** read from the player's ROM at runtime. ROM tiles are never committed, so they never meet this problem; a downloaded tileset would.

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

1. **Programmer art** through Phase 9: the code-drawn placeholder tiles (`placeholder_v1`, slice-2 plan §5) — kept permanently as the no-ROM look. Pokémon render from the Black/White cache, and map tiles from the Emerald cache, as soon as each importer exists.
2. **Map tiles:** the Emerald importer (Decision 19) replaces licensing a base kit for the overworld. Anything Emerald lacks — snow, for example — is drawn as original art in the same style, or filed as a decision.
3. **Commissions:** player sprite, haunted interior tiles, distortion effects, battle backgrounds.
4. **AI:** concepting and mood reference only; never final assets.

## 6. Files
* `assets/palette/tenth_spring.gpl` — master palette.
* `game/assets/tiles/`, `game/assets/ui/`, `game/assets/backgrounds/` — original art.
* `game/render/tile_renderer`, `game/render/day_night_tint`, `game/render/distortion_tint`.
* ROM-derived sprites and icons are read only through `asset_db` from `user://rom_cache/`.
