# Credits

## Original Art

The original game sprites in `game/assets/original/` are AI-assisted:
- **Base models:**
  - Qwen-Image-2512 Q8_0 GGUF (unsloth) under Apache-2.0 (`https://huggingface.co/Qwen/Qwen-Image-2512`).
  - Qwen-Image-Edit-2511 Q8_0 GGUF under Apache-2.0 (`https://huggingface.co/Qwen/Qwen-Image-Edit-2511`), guided by a public-domain interior style-key sheet (`style_key_v1_interiors.png`) assembled solely from **isaiah658**'s *Pixel Pack #2* (`CC0 1.0 Universal`, `https://opengameart.org/content/isaiah658s-pixel-pack-2`).
- **LoRA:** Lightning 8-step LoRA V1.0 under Apache-2.0.
- **Code-drawn decals:** The cracks (`decal_cracks`), grass tufts (`decal_tufts`), and creeping vine (`decal_creeper`) were drawn by the project's own code (`tools/art_pipeline/draw_overlays.py`).
- **Human approval:** The human maintainer approved Tier 1 assets on 2026-11-01 (Decision 38), Tier 2 landmark and initial block assets on 2026-11-04 (Decision 49) and 2026-11-05 (Decision 50), Tier 2 whole ruined city blocks (`ruined_block_8x7_b`, `ruined_block_6x11_a`, `ruined_block_6x11_b`, `ruined_block_9x9_a`, `ruined_block_9x9_b`, `ruined_block_11x13_a`, `ruined_block_11x13_b`, `ruined_block_16x14_a`, `ruined_block_16x14_b`, `ruined_block_23x14_a`, `ruined_block_23x14_b`) on 2026-11-08 (Decision 52), Tier 4 trees, small map objects, standing houses, and standing city blocks (`tree_round`, `tree_conifer`, `obj_flowers`, `obj_sign`, `obj_crop`, `obj_bush`, `standing_house_s_door1`, `standing_house_s_door2`, `standing_house_m`, and `standing_block_{8x7,6x11,9x9,11x13,16x14,23x14}_{a,b}`) on 2026-11-08 (Decision 53), Washington DC trial landmarks and props (`dc_capitol`, `dc_castle`, `dc_air_and_space`, `dc_jefferson`, `dc_union_station`, `dc_healy_hall`, `dc_zoo_gate`, `dc_aviary`, `dc_dupont_fountain`, `tree_cherry`, `waypost_lamp`, `waypost_board`) on 2026-11-14 (Item 51 / DC Trial), and the 25 Tier 5 Washington DC interior props (`int_item_ball`, `int_switch_lever`, `int_metal_gate`, `int_warp_pad`, `int_push_boulder`, `int_smash_rubble`, `int_supply_crate`, `int_elevator_cage`, `int_wind_grate`, `int_obs_slit_window`, `int_suspended_flyer`, `int_space_capsule`, `int_radio_console`, `int_glass_case`, `int_archive_bookshelf`, `int_reading_table_lamp`, `int_octagon_desk`, `int_calder_cipher_desk`, `int_lincoln_statue`, `int_undercroft_pillar`, `int_cobalion_dais`, `int_canal_sluice_wheel`, `int_keystone_pedestal`, `int_vet_kennel_bank`, `int_surgery_table`) on 2026-11-17 (Decision 66 / Item 56). Complete generation and review metadata for each asset is recorded in `game/assets/original/provenance.json`.

## Terrain Tiles (CC0)

The terrain atlas `game/assets/tiles/original_v1.png` is derived from public-domain pixel art:
- **Source pack:** Kenney (`www.kenney.nl`) — *Roguelike/RPG Pack* (`roguelikeSheet_transparent.png`), released under Creative Commons Zero (`CC0 1.0 Universal`, `http://creativecommons.org/publicdomain/zero/1.0/`).
- **Recolouring:** Recoloured to the Tenth Spring Terrain Palette and composed into 4-bit cardinal mask variants by `tools/art_pipeline/recolour_tiles.py`.

## Creature Data & B&W-Style Fan Sprites (First-Run Local Download)

When the player opts in on first run, Tenth Spring downloads open species/move/item data and Generation 6–8 + Mega Evolution Black/White-style fan sprites onto the player's machine (`user://rom_cache/`, never bundled in the repository):
- **PokéAPI (`github.com/PokeAPI/pokeapi`):** Species stats, types, abilities, level-up learnsets, evolutions, moves, items, and names are read from PokéAPI's open CSV database under the **BSD 3-Clause Licence** (*Copyright © Paul Hallett and PokéAPI contributors*; pinned commit recorded in `game/config/data_sources.json`, SHA-256 hashes in `game/config/data_pack_manifest.json`).
- **Smogon Sprite Project (via `github.com/PokeAPI/sprites`):** Custom Generation V (Black/White)-style battle sprites for National Dex **#650–905** and the **48 Mega Evolution forms** (used alongside #1–649 extracted locally from the player's own Black/White ROM) are the work of the **Smogon Sprite Project** community (*"All sprites are free for use as long as the spriter or the project itself is credited"* and *"free for non-profit use"*):
  - **Main project threads:** [Smogon Sprite Project (Gen 8+)](https://www.smogon.com/forums/threads/smogon-sprite-project.3647722/), [Sun/Moon Sprite Project (Gen 7)](https://www.smogon.com/forums/threads/sun-moon-sprite-project.3577711/), and [X/Y Sprite Project (Gen 6 & Mega Evolutions)](https://www.smogon.com/forums/threads/x-y-sprite-project.3486712/).
  - **Public credit sheets:** [Gen 6 & Mega Evolution Credit Sheet](https://docs.google.com/spreadsheets/d/1Gn0UORn-unvcbUeQhQdEBz0ADNcH49BZZqQ1dpXm9eo/edit), [Gen 7 Credit Sheet](https://docs.google.com/spreadsheets/d/1FMcHbSKEWZc7v2Ur4cyJjT_NhO0gqXyU9kDhsOQhlBQ/edit), and [Gen 8 Credit Sheet](https://docs.google.com/spreadsheets/d/1acgzAjh0dnFRQnjZu8kSjS177rKCzpFfEHRLtwuuXRU/edit).
  - **Per-sprite artist credits:** Recorded by National Dex / form ID in `game/config/fan_sprite_credits.json` and displayed in-game on the Credits screen and per Pokédex entry (`game/config/fan_sprite_manifest.json` records each sprite's SHA-256).

## Battle Rules & Gen 8 Data Overrides (MIT)

Tenth Spring's Generation 8 battle-data overrides (`game/config/battle_data_overrides.json`) and battle engine rules are derived from **Pokémon Showdown** (`pokemon-showdown`, MIT Licence):

```text
The MIT License (MIT)

Copyright (c) 2011-2026 Guangcong Luo and other contributors http://pokemonshowdown.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
