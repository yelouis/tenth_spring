# Art Direction — Diamond/Pearl, After the Collapse

Target look: **Pokémon Diamond/Pearl-era top-down pixel art** — warm, readable, charming — with a horror undertone: overgrowth, emptied towns, distortion bleeding in at the edges of the known world, and Ghost Pokémon in the dark.

The pivot changes where art comes from. **Pokémon and item art come from the player's Black/White ROM**, and — since Decision 19 (2026-10-19) — **the overworld map tiles come from the player's Emerald ROM**, all at runtime. **Everything else is original art** and lives in the repo, including the placeholder map tiles the game shows until an Emerald ROM is imported.

---

## 1. Where each kind of art comes from

| Art | Source | In repo? |
|---|---|---|
| Pokémon battle sprites #1–649 (front/back, shiny) — 96×96, animated, Black/White style (Decision 10 = B) | Player's Black/White ROM via the importer | **Never** |
| Pokémon battle sprites #650–905 — the **Smogon Sprite Project's** Black/White-style fan sprites (Decision 32) | Downloaded on the player's machine, credited (`design_rom_asset_pipeline.md` §2a) | **Never** (credits only) |
| Item icons | Player's ROM via the importer | **Never** |
| Overworld map tiles (layout generated from OSM) | Player's **Emerald** ROM via the importer (Decision 19) | **Never** |
| Placeholder map tiles — the no-ROM look | Original, code-drawn (`placeholder_v1`) | Yes |
| **Landmark set pieces** — the famous buildings Emerald has no look-alike for (§1a) | Original (code-drawn or commissioned), in the Emerald style | Yes |
| **Modern props Emerald lacks** — cars, traffic lights, street lamps, bus stops | Free, credited libraries (§2a), palette-matched to the Emerald tiles | Yes, with `CREDITS.md` |
| Player overworld sprite, battle UI, menus, fonts | Original | Yes |
| Battle backgrounds per zone | Original | Yes |
| Fog, distortion, night, and lamp effects | Original shaders | Yes |

**Why Emerald for the map.** The DS games (Gen 4–5) draw their overworlds as 3D models, not 2D tilesets, so there is nothing tile-shaped to extract from Black/White. The Game Boy Advance games are the last Pokémon games built from true 2D tiles, and Emerald has the widest range of landscapes among them (desert, beach, forest, mountains). The *layout* is still generated from OpenStreetMap (`implementation_plan_world_generation_slice2.md`); only the pixels come from the ROM, through a committed table of metatile numbers (`design_rom_asset_pipeline.md` §5). Gen 3 tiles are 16 px and render at 2× (32 px), the same integer-scale rule as everything else. The overworld is Gen 3 in look while battles use Black/White sprites; the two never share a screen.

**Battle layout** is built for a 96×96 animated sprite box at integer scale, never stretched.

## 1a. Landmarks — the real world's famous buildings in Pokémon style (2026-10-22)
The human noted that "the art from the ROMs might not be enough for things like the monuments in real life." Emerald draws its own region's towns, not the Statue of Liberty. Each famous interior (`design_interiors_and_quests.md` §4) gets its look from the first source that fits:

1. **An Emerald look-alike,** composed from the player's ROM through the mapping table (numbers only, never pixels — `design_rom_asset_pipeline.md` §5):

   Compositions are named by function, never by the Emerald place or facility they come from (F59). The ids below are the keys of `compositions` in `game/config/emerald_tile_map.json`:

   | Composition id | Emerald building (by function) | Stands in for |
   |---|---|---|
   | `pyramid_hall` | the pyramid-shaped hall | The Pyramid (Memphis) |
   | `dome_centre` | the dome building | Space Center Houston, Kennedy Space Center |
   | `tall_tower` | the tall tower | Empire State Building, Willis Tower, Renaissance Center, Terminal Tower, Freedom Tower, Cathedral of Learning, the STRAT |
   | `museum_hall` | the gallery hall | Philadelphia Museum of Art, Nelson-Atkins, Boston Public Library, Library of Congress |
   | `maritime_hall` | the seaside exhibition hall | Georgia Aquarium, American Museum of Natural History, Field Museum, the natural-science museums |
   | `theatre_hall` | the performance hall | the Fox Theatres, Ryman Auditorium, the Smith Center, Preservation Hall, TCL Chinese Theatre |
   | `dept_store` | the department store | Reading Terminal, Pike Place, French Market, and West Side Market halls |
   | `casino_hall` | the arcade hall | the Glow's casinos on Fremont Street |
   | `observatory` | the research observatory | Griffith Observatory, McDonald Observatory |
   | `power_station` | the power station | Michigan Central Station, the Edison laboratory, the Flats |
   | `grand_hall` | the grand hall | the state capitols (Rhode Island, Texas, Colorado, Arizona) |
   | `stadium` | the dome stadium | Fenway Park, the Astrodome, Churchill Downs |
   | `elevated_road` | the raised roadway | the "L", the Stone Arch Bridge, the Hot Metal Bridge |
   | `maze_house` | the maze house | City Museum (St. Louis) |

2. **A free, credited library piece** (§2a) — mainly modern props, not landmarks.
3. **An original set piece** — a multi-tile stamp drawn in the Emerald style: 16-colour palettes, a 1-px dark outline, light from the top left. Needed first for the icons nothing else can stand in for:
   - the Statue of Liberty and the Gateway Arch;
   - the Lincoln Memorial and the Washington Monument;
   - the Space Needle, Coit Tower, and the Golden Gate's towers;
   - Boston Light and the Cape Hatteras lighthouse;
   - Alcatraz's cellhouse and Nashville's Parthenon;
   - Independence Hall, Grand Central's facade, and the Neon Museum's signs.

   Code-drawn first, as `placeholder_v1` was; a human pixel artist can replace any of them later.

**The register** (slice-2 plan §12, agent guide Item 30). `game/config/landmark_art.json` maps each interior id to its source: `{"source": "original", "stamp": "<stamp id>"}` or `{"source": "emerald", "composition": "<composition id>"}`. The synthesizer places a set piece on the landmark's footprint in place of the gold-roof template (slice-2 plan §11.1). A landmark with no entry keeps the gold roof.

**Searched and not found** (2026-10-22): free (CC0 or CC-BY) top-down pixel art of US landmarks in a compatible style. That's why original set pieces are the plan.

## 2. The rip trap — read before sourcing any tiles

This applies to every piece of art that **isn't** read from the player's ROM at runtime. ROM tiles are never committed, so they never meet this problem; a downloaded tileset would.

**Many "Diamond/Pearl tilesets" circulating online are rips of Nintendo's art.** Committing one puts Nintendo assets into a public repo — exactly what the BYOR model exists to prevent. Before licensing any tileset: confirm the author drew it, get commercial-use-or-better license terms in writing, and prefer artists with a portfolio of original work. When in doubt, commission.

## 2a. Free libraries — vetted, and how to credit them (2026-10-22)
The human asked for free 2D art libraries "(give credit) … that fits the pokemon theme". What the search found — **check each asset page's licence again at the moment of download**, and record it in `CREDITS.md`:

| Library | Licence | What it offers | Our use |
|---|---|---|---|
| [Kenney — RPG Urban Pack](https://opengameart.org/content/rpg-urban-pack) ([itch.io](https://kenney-assets.itch.io/rpg-urban-kit)) | **CC0** (attribution appreciated, not required) | 480+ urban tiles: roads, buildings, vehicles, details; six walking characters | **Modern props** — cars, signs, traffic lights, street lamps — palette-matched to Emerald |
| [Kenney — Roguelike Modern City](https://opengameart.org/content/roguelike-modern-city-pack) | **CC0** | 1,000+ tiles: roads, parking, buildings | More modern props |
| [tiny16 tileset](https://opengameart.org/content/tiny16-tileset) (FuwanekoGames) | **CC-BY 3.0** | 16×16 pastel town tiles, "somewhat Pokémon inspired" | A fallback for town pieces Emerald lacks |
| Ninja Adventure (Pixel-boy and AAA, itch.io) | **CC0**, per the author's own statement | A large top-down pack of terrain, villages, and props | **Snow and winter tiles**, which Emerald lacks — check its contents first |
| [Tuxemon tileset](https://opengameart.org/content/tuxemon-tileset) (Buch) | CC-BY-SA 3.0 | 16×16 Pokémon-like terrain | **Not used for now:** an unresolved comment says two of its tiles were copied from another artist, and share-alike would bind our derived atlas |
| [Pokémon-inspired 16×16 tiles](https://opengameart.org/content/pokemon-inspired-16x16-tiles) (Red_Voxel) | unclear (CC-BY-SA listed, CC0 claimed) | trees, a mailbox, tall grass | **Not used** until the licence is clear |

**Rules:**
- **The rip trap (§2) applies to every library piece.** Check the author's other work, and refuse anything that looks traced from a Pokémon game.
- **Palette matching is allowed and credited.** Recolouring a CC0 or CC-BY tile to the Emerald look is a modification, so `CREDITS.md` says "recoloured".
- **`CREDITS.md`** (repo root) lists every third-party file with:
  - title, author, licence, and source link;
  - what we changed;
  - where it's used.

  CC-BY and CC-BY-SA pieces also credit in-game, on the Credits screen.
- **Never mix in a library's characters or monsters.** The player sprite is original, and the Pokémon come from the ROM and the fan sprites.

## 3. Technical spec (every original asset must comply)

- **Tiles:** 32×32 px, integer scaling only.
- **Palette:** one master palette ≤ 64 colours (`assets/palette/tenth_spring.gpl`). Day/dusk/night and **haunted-territory distortion** are shader tints over the same tiles, never separate tile sets.
- **Autotiles:** placeholder autotiles use the 16-mask scheme until final art (47-blob format for grass/tall-grass/road/water/tree-line transitions; buildings from a 9-slice wall set + roof set).
- **Tall grass must read instantly** as "encounters happen here" — the single most important tile in the game.
- **Fog states:** `unknown` = solid `#0d1119` with a slow distortion shimmer (the Distortion); `known` = desaturated 40% + dark overlay; `cleared` = full palette.
- ROM sprites render at integer scale over original battle backgrounds; never recolor them.

## 4. Mood rules

- **Cozy tiles, quiet dread.** The overworld stays readable and warm by day. Dread arrives through light and colour: night's deep blue tint with warm lamp pools; haunted territory's distortion tint, which deepens per haunt stage.
- **Overgrowth everywhere.** Tall grass bursts through roads and lots, and half the houses have fallen in or vanished (the ruin pass, Decision 30). Weathering increases with distance from each place's Waypost, so the survivors' camp feels kept and the outskirts feel swallowed.
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
