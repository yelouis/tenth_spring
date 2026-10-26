# ROM Asset Pipeline — "Bring Your Own ROM"

This document defines how Tenth Spring gets Pokémon sprites, species data, moves, items, names, and — since Decision 19 (2026-10-19) — its overworld map tiles **without the repository ever containing them**. It is modeled on PokeMMO, which ships no Nintendo files and reads game assets from ROMs the player supplies. Every Pokémon-facing system depends on this pipeline, which is why it is Phase 2 in the master plan.

**Why this model.** The GitHub repo (`yelouis/tenth_spring`) is **public**. Nintendo has historically acted against fan projects that *distributed its assets*:
- **Pokémon Essentials** — taken down August 2018; the kit bundled Nintendo graphics, music, and tilesets.
- **Pokémon Uranium** — 2016.
- **Pokémon Prism** — cease-and-desist four days before its December 2016 release.

PokeMMO distributes no assets and requires players to supply their own ROMs; it has no reported takedown. ROM hacks follow the same principle: they ship as patches against the player's own ROM, never as the ROM itself. BYOR reduces risk substantially, but it does **not** eliminate it — see §8.

**Scope (Decision 32, 2026-10-22): all 905 Pokémon of Generations 1–8.**
- **Sprites:** #1–649 come from the player's Black/White ROM. #650–905 come from the **Smogon Sprite Project**, the community's Black/White-style fan sprites, free for non-profit use with credit (§2a).
- **Data:** all 905 species' data comes from **PokéAPI's open data** (BSD 3-Clause), because no Gen 5 cartridge holds Gen 6–8 data (§2a).
- **All of it lands on the player's machine and never in the repo.** Fan sprites depict Nintendo's characters, so they follow the same rule as ROM content.
- *Superseded:* Decision 12's "Generations 6–9 are out of scope permanently". Gen 9 stays out of scope.

---

## 1. What lives where

| Lives in the repo | Never in the repo |
|---|---|
| Importer and parser code | ROM files (`.nds`, `.gba`, …) |
| Game mechanics: formulas, type chart, our own spawn tables (species referenced by **National Dex number**) | Sprites, palettes, item icons, audio, tilesets extracted from a ROM |
| SHA-256 manifests and per-sprite **credits** for the downloaded content (`game/config/fan_sprite_manifest.json`, `fan_sprite_credits.json`, `data_pack_manifest.json`) — hashes and artist names only | **Fan sprites** (#650–905) and the **data pack** (PokéAPI's CSV files, which include species, move, and item names) |
| Original art: UI, fonts, the placeholder map tiles (the no-ROM look) | Nintendo text banks: species/move/item names, Pokédex entries |
| Tile **mapping tables** that reference ROM metatiles by number (`game/config/emerald_tile_map.json`) | Tile graphics, palettes, and metatile data extracted from a ROM |
| Decoding rules for text (functional code, not text) | Extracted stat tables (base stats, learnsets, move data) |

All extracted content lands in **`user://rom_cache/`** on the player's machine — outside the repo in every build, including editor runs.

## 2. Supported ROMs

**Two cartridges, each dumped by the player from a cartridge they own.**
- **Pokémon:** Decision 10 = B (2026-10-09) — Black/White sprites for all 649, so Platinum is not used.
- **Map art:** Decision 19 = Emerald (2026-10-19) — the human chose real Pokémon art for the overworld. The DS games draw their towns as 3D models; the Game Boy Advance games are the last built from true 2D tiles. Of those, Emerald has the widest range of landscapes.

| ROM | Game code | Provides | Required? |
|---|---|---|---|
| **Pokémon Black or White (USA)** | `IRBO` (Black) / `IRAO` (White) at header `0x0C` | **Battle sprites** (animated, 96×96) for **#1–649**, and item icons for Gen 5 items. *Since Decision 32 its data and text are no longer read* — they come from the data pack (§2a). | For the #1–649 sprites. Without it, those species show original silhouettes. |
| **Pokémon Emerald (USA)** | `BPEE` at header `0xAC`. Known clean SHA-1 `f3ae088181bf583e55daf962a92bb46f4f1d07b7` — the dump the community's Emerald decompilation rebuilds byte-for-byte; confirmed against the human's file on 2026-10-22 | **Overworld map art:** tileset graphics, palettes, and metatile definitions and behaviours, turned into the map's tile atlas (§5) | **For the Pokémon-style map.** Without it, the map uses the original placeholder tiles (the no-ROM look) |

**Black and White are interchangeable** for our purposes. Their version differences are wild-encounter tables and exclusive story content, neither of which we read. The importer accepts either and treats them identically.

**Why the data moved to PokéAPI (Decision 32).** No Gen 5 cartridge contains Gen 6–8 species, moves, or the Fairy type. One data source for all 905 species keeps every species in one format under one ruleset, Generation 8 (`design_creatures_and_battles.md`). *(This replaces "Black/White is the single data source".)*

**Rules for everyone — the game, its docs, and any agent working on it:**
- **Never download a ROM, link to a ROM site, or help a user find one.** Only users supply ROMs.
- **Verify on import.** The game code must match the table above.
  - **Emerald must be the clean dump** (the SHA-1 above): the tile mapping table depends on exact offsets.
  - **Black/White:** a known-good SHA-1 (recorded from the No-Intro DAT, with its source) imports normally. **A modified Black or White ROM is accepted for sprites only** (Decision 34): the importer records its SHA-1, shows `Modified ROM — only its Pokémon sprites are used`, and accepts it only if the sprite archive passes every sprite check in §7.
  - A ROM that fails is rejected with a plain-language message.
- **v1 rejects** non-USA releases and Black 2/White 2. B2W2's archive layout differs; supporting it is a possible later extension.

### 2a. Generations 6–8 — the data pack and the fan sprites (Decision 32)
**Both are downloaded by the game on the player's machine,** with the player's consent and the download size shown first. Both are pinned to exact versions, verified against committed SHA-256 manifests, and stored in `user://rom_cache/`. They are never committed, and CI never downloads them.

| Content | Source (pinned) | Licence / terms | Lands in |
|---|---|---|---|
| **Data for all 905 species:** stats, types, abilities, level-up learnsets, evolutions, moves, items, and names | **PokéAPI** — the CSV files under `data/v2/csv/` of `github.com/PokeAPI/pokeapi`, at one commit recorded in `game/config/data_sources.json` | BSD 3-Clause (© Paul Hallett and PokéAPI contributors) | `data/*.json`, `text/en/*.json` |
| **Battle sprites #650–905:** front, back, shiny front, shiny back | **The Smogon Sprite Project's** Black/White-style sprites, as served by `github.com/PokeAPI/sprites` (folder `sprites/pokemon/versions/generation-v/black-white/` — the spike confirms the exact paths). PokéAPI serves them with Smogon's permission, and states that the sprites above #650 are not official. Pinned to one commit. | "Free for use as long as the spriter or the project itself is credited", and "free for non-profit use" (the Smogon Sprite Project thread) | `sprites/front/{dex}.png` and the other sprite folders, beside the ROM's |

**Rules for both:**
- **Pinned and verified.** `game/config/data_sources.json` records each repository and commit. `data_pack_manifest.json` and `fan_sprite_manifest.json` hold the SHA-256 of every file. A file that fails its hash is refused, and the import reports which.
- **Only #650–905 are taken from the sprite repository.** Its lower numbers are Nintendo's own sprites, so the importer never requests them — #1–649 come only from the player's ROM.
- **Learnsets follow the latest game:** a species' level-up moves come from Sword/Shield if it appears there, else the newest earlier game that has it — Legends: Arceus for #899–905, then Brilliant Diamond/Shining Pearl, Let's Go, and Ultra Sun/Ultra Moon. The spike records the exact version-group ids.
- **Moves:** those introduced by Gen 8 or earlier, excluding Z-Moves and Max Moves (Decision 36 = Mega Evolution only).
- **Mega forms** (Decision 36): the data pack also imports the 48 Mega forms' stats, types, and abilities. Their Black/White-style sprites come from the same pinned sprite repository where they exist (Smogon's X/Y Sprite Project drew them), else they're listed as pending.
- **Gaps:** a species with no Black/White-style fan sprite yet (the project's Gen 8 download predates Legends: Arceus) shows an original silhouette with a "sprite pending" flag, and the import report lists its dex number. Never substitute another style.
- **Credits are required.** `game/config/fan_sprite_credits.json` maps each dex number to its spriter(s), from the project's credit sheet — artist names only, never species names. The game's Credits screen and `CREDITS.md` show them with "Smogon Sprite Project", and the Pokédex shows each sprite's artist.

**Sources** (checked 2026-10-22):
- [Smogon Sprite Project — Gen 8 thread](https://www.smogon.com/forums/threads/smogon-sprite-project.3647722/) (the terms quoted above)
- [X/Y Sprite Project — Gen 6](https://www.smogon.com/forums/threads/x-y-sprite-project.3486712/)
- [PokéAPI sprites](https://github.com/PokeAPI/sprites) ("the sprites with IDs greater than 650 are thus not official"; thanks Smogon "for allowing us to use and serve their custom B&W-style sprites")
- [PokéAPI licence](https://raw.githubusercontent.com/PokeAPI/pokeapi/master/LICENSE.md) (BSD 3-Clause)

## 3. Import flow (first run, and on demand)

The Black/White ROM and the Emerald ROM are imported separately (§2), each with its own verify step and its own part of the cache; either can be present without the other.

```
0 FETCH    (once, with consent) Download the data pack and the #650–905 fan sprites (§2a); verify every
           file against its SHA-256 manifest.
1 LOCATE   Player picks a ROM file in a native file dialog. Store only its path.
2 VERIFY   Game code in §2's table. Emerald: the clean SHA-1. Black/White: a known-good SHA-1, or
           "modified — sprites only" (§2).
3 PARSE    Read the NDS header → file name table (FNT) + file allocation table (FAT).
4 EXTRACT  Pull that ROM's archives in §5 by path; unpack each NARC.
5 DECODE   Sprites → PNG (#1–649 from the ROM). Data and names: the data pack's CSV files → species, move,
           item, evolution, and learnset tables (§2a). The ROM's own data and text are not read.
6 WRITE    user://rom_cache/ (layout §6). Write the manifest last.
7 VALIDATE Spot-checks (§7) before marking the cache valid.
```
- **Resumable and idempotent:** write into `user://rom_cache.tmp/`, then rename to `user://rom_cache/` only after the manifest is written. A crash leaves the old cache intact.
- **The game runs in a degraded "no ROM" mode before import.** Onboarding, the map, and sync work with placeholder silhouettes and the placeholder map tiles. Pokémon content unlocks once the Black/White import (§2) is valid; the Pokémon-style map art, once the Emerald import is valid.
- **Pure GDScript:** the importer uses `FileAccess.get_buffer` and `PackedByteArray.decode_u16/u32`, and needs no native extension.
- **Bounded memory:** archives are read by FAT offset (seek + `get_buffer`), never the whole ROM, with sprites decoded one at a time — peak ≤ 512 MiB, pausing when the computer runs low (`design_memory_and_resources.md` §3.2).

## 4. Formats (each **verify** must be confirmed by the spike and replaced with the confirmed rule)

**Shared (both ROMs):**
- **NDS header:** FNT offset `0x40`, FNT size `0x44`, FAT offset `0x48`, FAT size `0x4C` (u32 little-endian). Game code at `0x0C`. Black/White are DSi-enhanced; the code is still at `0x0C`.
- **NARC:** magic `NARC`, then three chunks: `BTAF` (file allocation), `BTNF` (file names), `GMIF` (file images).
- **NCGR / NCLR:** tile graphics (`RGCN`) and palettes (`RLCN`); 4bpp tiles; BGR555 palette entries.
- **LZ compression:** if an extracted file's first byte is `0x10` (LZ77) or `0x11` (LZ11), decompress before parsing. Gen 5 archives are known to use LZ11 in places — **verify** which files.

**Black/White:**
- **Battle sprites** are composed from parts, not stored as one image:
  - an `NCGR` tile sheet;
  - an `NCER` cell bank that says how parts assemble;
  - `NANR`/`NMCR`/`NMAR` animation data;
  - separate normal and shiny `NCLR` palettes.

  A static sprite = cells assembled for the **first frame** of the idle animation, on a 96×96 canvas — **verify**. The per-species file layout inside `a/0/0/4` is also **verify** (14,285 files is not an exact multiple of 649; forms and padding account for the rest).
- **Data records:** personal (base stats etc.), learnset, evolution, and move entries are fixed-layout records. **Verify** each record size and field offset against Project Pokémon's raw database and an open-source editor's source code before relying on them.
- **Text banks:** UTF-16 code units, encrypted per string with a 16-bit key that is advanced after each character — **verify** the exact key schedule and record it here.

**Emerald (Game Boy Advance)** — confirmed by Emerald tile spike (Item 12):
- **GBA header:** 12-byte title at `0xA0` (`POKEMON EMER`), 4-byte game code at `0xAC` (`BPEE`). SHA-1: `f3ae088181bf583e55daf962a92bb46f4f1d07b7`. Data located through ROM pointer tables; map bank pointer table at `0x486578`.
- **Tileset struct (`struct Tileset`):** 24 bytes (`0x18`) at `0x3DF704` (Primary `gTileset_General`) and array of 57 secondary tilesets contiguous from `0x3DF71C` to `0x3DFC5C`:
  - `isCompressed` (u8) at `+0x00`: 1 if LZ77 type `0x10`, 0 if raw 4bpp.
  - `isSecondary` (u8) at `+0x01`: 0 for primary, 1 for secondary.
  - `padding` (u16) at `+0x02`.
  - `tiles` (u32 pointer) at `+0x04`: GBA pointer (`0x08xxxxxx` -> ROM offset `0xxxxxxx`). Primary `tiles` at `0xDD5010` decompresses to 16,384 bytes (512 8×8 4bpp tiles).
  - `palettes` (u32 pointer) at `+0x08`: 512 bytes (16 BGR555 palettes × 16 colors). Primary `palettes` at `0xDD4E10`. Secondary palettes mirror palettes 0–5 and provide area colors in palettes 6–12.
  - `metatiles` (u32 pointer) at `+0x0C`: Primary at `0x3960F0` (512 metatiles × 16 bytes = 8,192 bytes). Secondary metatiles start at local index 0 (global 512).
  - `attributes` (u32 pointer) at `+0x10`: Primary at `0x3980F0` (512 u16 entries = 1,024 bytes). **Bits 0–7 are the behaviour byte, bits 12–15 the layer type, and bits 8–11 are unused** — confirmed by the spike's test over every tileset the table names (Item 12b; the Item 12 text said "lower 9 bits").
  - `callback` (u32 pointer) at `+0x14`: animation function pointer (e.g. `0x080A0B21`).
- **Metatile layout:** each 16×16 metatile has 8 u16 entries (4 bottom layer, 4 top layer: TL, TR, BL, BR). Each u16: bits 0–9 tile index (0..511 from primary tiles, 512..1023 from secondary tiles), bit 10 xflip, bit 11 yflip, bits 12–15 palette index (0..15).
- **Rendering:** bottom layer 4 tiles drawn first, then top layer 4 tiles composited on top (palette color 0 transparent). Rendered at 2× integer scale (32×32 px) for the Tenth Spring overworld.

**Choosing the metatiles (Item 12b, F60).** Every entry of `game/config/emerald_tile_map.json` is chosen by evidence, never by guess; pass 22 guessed, and drew signs on every lawn, striped water, bushes for tall grass, and one roof for all eight colours. The spike (`tools/rom_spike/emerald/`) offers three kinds of evidence, and the table records only metatile numbers:
- **Behaviour bytes** (bits 0–7 of the attribute word). Tall grass only from `0x02`/`0x03`; standing water only from `0x10`–`0x12` and `0x15`–`0x17` (not the waterfall `0x13`); a bridge deck from `0x2B`; a door piece from `0x60` or `0x69`; sand from `0x21`; cropland from the plantable-soil byte `0xA0`; a plain lawn, roof, or wall from `0x00` (`0x01` for a few walls).
- **Pixel tests**, on the 16 × 16 render: a plain lawn variant draws ≥ 90% of its pixels from the base lawn's colours with no patch of other colours larger than 3 pixels; a water interior is ≥ 95% water-coloured (blue is the strongest channel), and every water piece draws its water in the interior's colours; along a side whose mask bit is 0 the 4-px band (the middle 8 px of that side) is ≥ 25% non-water (a shore), and along a 1-bit side ≥ 90% water; the lawn and tall grass have a **blank top layer** (an object painted over the ground — a tree top, a sign — makes it a different thing); tall grass has per-channel variance > 500.
- **The ROM's own map layouts, read as statistics only.** The spike counts, for each piece, which pieces sit on each side of it and how often it occurs; that finds the edge and corner pieces per mask, the ROM's plain choice for a ground class (the most frequent piece), and how trees, fences and paths join. **Nothing from a layout is stored except metatile numbers, a few aggregate use counts quoted in code comments, and the 14 compositions** — rectangles of metatile numbers lifted from the layouts (with the door's position inside the rectangle) — and no map, event, text, or placement. This reading never leaves the player's machine or the spike. The tests re-measure two of the choices from the layouts: the base lawn is among the ROM's five most used pieces, and each pond edge piece sits at the neighbour mask the table gives it.

The rules that keep the table honest (checked by `tools/rom_spike/emerald/mapping_checks.py`, listed in `implementation_plan_rom_tiles.md` §3):
- **No stand-ins.** A class (or a variant, or some masks of it) with no honest Emerald piece goes into `gaps`, with a reason, and the game keeps its code-drawn placeholder tile there. Two classes never share a metatile unless `shared` lists the share as intentional. Where Emerald draws one thing for two classes — its footpath ground and its plain sand are identical pixels — the table lists the share in `shared`; a twin under a second number counts as the same piece.
- **Tilesets by index.** An entry from a secondary tileset names it by index (`"sec05"`), never by name; the `tilesets` block lists exactly the tilesets the table uses. `secNN` is the tileset record at `0x3DF704 + 24 * NN`: the primary is index 0 and `sec01` is the first secondary (the array runs to `sec57`).
- **Compositions by function** (`design_art_direction.md` §1a), lifted from the ROM's own layouts as rectangles of metatile numbers.

**Table schema (version 2)** — written by `tools/rom_spike/emerald/build_mapping.py`, which refuses to write a table that fails its checks:

| Key | Contents |
|---|---|
| `version` | `2` |
| `tilesets` | `{"primary": 0, "secNN": NN, …}` — exactly the tilesets the entries, buildings and compositions use |
| `tile_map` | `class → variant → mask → {"metatile": N}` or `{"metatile": N, "tileset": "secNN"}`; every mask is an explicit number 0–15 (no wildcard); an unmasked class uses mask `"0"` |
| `shared` | `[{"metatile", "tileset", "classes", "reason"}]` — intentional shares only |
| `buildings` | `house_s`, `house_m`, `block_l`: `{"w", "h", "door": [x, y], "roof_colors": {"0": {"metatiles": […], "tileset"?}, …}}` — derived from `tile_map` with the synthesiser's own neighbour-mask rules, so it can never disagree with it |
| `compositions` | the 14 function ids → `{"w", "h", "tileset", "door": [x, y] or [], "metatiles": [row-major ids]}` |
| `gaps` | `[{"id", "classes", "variants"?, "masks"?, "reason"}]` — leaving out `variants` or `masks` means all of them |

**Reference sources** (documentation only — never sources of ROMs):
- Project Pokémon's raw database pages for Black (`projectpokemon.org/rawdb/black/`).

## 5. What to extract

**Black/White** (file counts from Project Pokémon's Black archive list; White must match — **verify**). *Since Decision 32, only the sprite archive `/a/0/0/4` and the item icons are read. The data and text rows below are kept as the record of the format, and are not imported.*

| Archive | Contents | Cache output |
|---|---|---|
| `/a/0/1/6` (669) | Personal data: base stats, types, catch rate, base EXP, EV yield, growth rate, abilities, gender ratio. Entries 1–649 = species; the rest are forms | `data/species.json` |
| `/a/0/1/8` (668) | Level-up learnsets | `data/learnsets.json` |
| `/a/0/1/9` (668) | Evolution methods | `data/evolutions.json` |
| `/a/0/2/1` (560) | Moves: type, category, power, accuracy, PP, priority, effect | `data/moves.json` |
| `/a/0/2/4` (627) | Item parameters — **verify** contents | `data/items.json` |
| `/a/0/0/2` (288) | System text banks: species, move, item, and ability names — **verify** which bank holds each | `text/en/*.json` |
| `/a/0/0/4` (14,285) | Battle sprites, cells, animations, palettes | `sprites/front/{dex}.png`, `back/`, `front_shiny/`, `back_shiny/` |
| *item icons — archive to be located by the spike* | Item icons + palettes. **Do not guess the path**; record it here once found | `icons/items/{item_id}.png` |

**Emerald** (Decision 19):

| Data | Cache output |
|---|---|
| The primary tileset and the secondary tilesets the mapping table names — graphics, palettes, metatiles, attributes | `tiles/emerald_v1.png` — a 32 × 32 px atlas in the layout of `implementation_plan_world_generation_slice2.md` §5.2 — and `tiles/emerald_v1.json` |

- **The bridge is a committed mapping table**, `game/config/emerald_tile_map.json` (schema in §4). It maps each `(class, variant, mask)` of the slice-2 tile vocabulary (slice-2 plan §3) to metatile numbers, derives the three building templates in eight roof colours, holds the 14 landmark look-alike `compositions`, and lists as `gaps` what Emerald has no honest piece for.
- **Not in the tile vocabulary at all, so not in the table:** snow terrain, high-speed rail, modern asphalt highways, glass skyscraper facades, street lamps and traffic signals, and cars and buses. These are the "modern props Emerald lacks" of `design_art_direction.md` §1 and §2a.
- **Numbers only — never pixels.** The table is written by the Emerald tile spike, from the player's own ROM, and reviewed by the human.
- **Not extracted:** Emerald's maps, events, text, sprites, music, or Pokémon data. The world is generated from OpenStreetMap; Pokémon sprites come from Black/White and the fan sprites, and Pokémon data from the data pack (§2a).

## 6. Cache layout and versioning

```
user://rom_cache/
  manifest.json   { importerVersion,
                    rom: {gameCode, sha1, importedAt},
                    speciesCount, moveCount,
                    tiles: {gameCode, sha1, importedAt, atlas: "tiles/emerald_v1.png"} | null }
  sprites/  icons/  data/  text/en/  tiles/
```
- **Re-import automatically** if `importerVersion` changes, or if a ROM's `sha1` no longer matches the file the player pointed at.
- **The cache is regenerable, never a source of truth.** Saves store National Dex numbers and instance data, never extracted content. Deleting the cache must never lose player progress.
- **Sprites are reached in one place:** `asset_db.sprite_front(dex, shiny)`. No other code reads `sprites/` directly.

## 7. Import validation (the importer is not "done" until these pass)

Spot-check against facts the player's own ROMs must contain. Any failure leaves that part of the cache invalid and reports which check failed.

**Black/White:**
- Species count = **905**, from the data pack. The move count is whatever §2a's rule yields; the spike records it.
- **Gen 6+ typing**, primary then secondary:

  | Dex | Species | Types |
  |---|---|---|
  | `#36` | Clefable | Fairy |
  | `#282` | Gardevoir | Psychic / Fairy |
  | `#778` | Mimikyu | Ghost / Fairy |
  | `#887` | Dragapult | Dragon / Ghost |
- **Every #1–649 sprite decodes** from the ROM, and **every #650–905 sprite** is present or listed as pending (§2a).
- Types, primary then secondary:

  | Dex | Species | Types |
  |---|---|---|
  | `#487` | Giratina | Ghost / Dragon |
  | `#442` | Spiritomb | Ghost / Dark |
  | `#94` | Gengar | Ghost / Poison |
  | `#609` | Chandelure | Ghost / Fire |
  | `#593` | Jellicent | Water / Ghost |
  | `#623` | Golurk | Ground / Ghost |
- Names for #487, #609, and #1 decode to non-empty strings with no unmapped characters.
- **Emerald tiles:**
  - the table passes every rule of `implementation_plan_rom_tiles.md` §3 — coverage of every `(class, variant, mask)` the synthesiser can emit (or a `gaps` rule), the lawn, water, and tall-grass pixel and behaviour tests, no unlisted shared metatile, no entry for a gap, metatile bounds, at least four roof colourways, and neutral names;
  - every atlas tile uses ≤ 16 colours per source palette (guaranteed by 4-bpp decoding; the spike's test asserts 16 entries per palette);
  - the importer refuses a mapping table entry that points past the end of a tileset's metatile table.
- **Chandelure's static front sprite** is a real image, not noise. Two checks: ≤ 16 distinct colours per palette, and a pixel-variance threshold that "static" from a wrong decryption or wrong cell assembly cannot pass.
- **Dragapult's fan sprite** (#887) loads and passes the same variance check.


## 8. Legal and repository guardrails (non-negotiable)

1. **Nothing from §1's right-hand column is ever committed** — not in a test fixture, not a debug PNG, not "temporarily." A ROM in public git history stays there until the history is rewritten.
2. **`.gitignore` blocks** ROM and Nintendo-format extensions (`*.nds`, `*.gba`, `*.gb`, `*.gbc`, `*.narc`, `*.ncgr`, `*.nclr`, `*.ncer`) and any local cache directory.
3. **A repository check** (`tools/check_no_nintendo_assets.py`) runs in CI and as a pre-commit hook. It fails if any tracked file:
   - has a forbidden extension;
   - begins with the `NARC` magic; or
   - carries an NDS game code at offset `0x0C` whose **first three letters** belong to any Gen 4–5 Pokémon title, in any region:

     | Prefix | Title |
     |---|---|
     | `ADA` | Diamond |
     | `APA` | Pearl |
     | `CPU` | Platinum |
     | `IPK` | HeartGold |
     | `IPG` | SoulSilver |
     | `IRB` | Black |
     | `IRA` | White |
     | `IRE` | Black 2 |
     | `IRD` | White 2 |

     The fourth letter is the region, so matching the prefix catches every regional dump.
   - carries a **GBA game code at offset `0xAC`** whose first three letters belong to a Gen 3 Pokémon title (Decision 19 brings a GBA ROM into the developer's hands):

     | Prefix | Title |
     |---|---|
     | `AXV` | Ruby |
     | `AXP` | Sapphire |
     | `BPR` | FireRed |
     | `BPG` | LeafGreen |
     | `BPE` | Emerald |

     So the guard reads at least the first `0xB0` bytes of each blob.

   Because the pre-commit hook is the **only** defense before content becomes public, it must also:
   - check **every staged path except deletions**, renames and copies included (`--diff-filter=d`);
   - read bytes from **what will be committed** — the index (`git cat-file`/`git show :path`) — never the working tree;
   - and the battery must **fail, not skip**, if the guard script is missing.

   **CI** checks out full history and adds these layers:
   - **Every commit in the pushed range** is scanned, not only the final tree. A file added then removed is still in public history and must be reported.
   - **Merge commits are scanned against each parent** (`git diff-tree -m`), because a file added while resolving a conflict exists only in the merge.
   - **The full tip tree is scanned too**, so nothing in the pushed result can escape a gap in the range logic.
   - **Any git error during a scan fails the run** rather than skipping a commit.
   - **If the pre-push SHA is unknown** (e.g. after a force-push), the scan falls back to full history.

   The hook is local, so a clone without it has no pre-publication defense. The local battery therefore **fails if `core.hooksPath` is not `.githooks`**. It skips that check only when `CI=true`, where the range and tree scans apply instead.
4. **ROM-dependent tests** run **only** when a developer supplies ROMs locally (`TENTH_SPRING_ROM_BW`, `TENTH_SPRING_ROM_GBA`). Otherwise they are skipped with an explicit message, never faked. CI never has a ROM.
   - **The same holds for the data pack and fan sprites** (`TENTH_SPRING_DATA_PACK` points at a local download).
   - **Paths to a developer's ROMs are never written in the repo** — only the environment variable names.
   - **No test fixture may contain a fan sprite or a data-pack file.**
5. **No Nintendo trademarks in branding.** Do not use "Pokémon" or other Nintendo trademarks in the game's title, logo, store pages, or release names. The game is "Tenth Spring."
6. **The phone companion contains no Nintendo assets or names**, ever (`design_companion_and_sync.md` §1). It is a location tracker and must stay store-listable.

## 9. Distribution

- **No commerce of any kind:** no Steam, no sales, no ads, and no donations tied to the game. Any of these makes a takedown far more likely.
- **The asset-free client** is distributed via GitHub Releases from the public repo. Players install it, then import their own ROMs (§3). On first run it offers to download the data pack and the fan sprites (§2a), showing the size and the credits.
- **Honest risk statement:** BYOR keeps Nintendo's assets out of our distribution, which is what separated PokeMMO's survival from Essentials' takedown. It is not immunity: Prism was a patch and still received a cease-and-desist once it became high-profile.
  - Keep the project low-profile.
  - If a takedown notice ever arrives, comply immediately and stop distribution. Do not argue it in public.

## 10. Files
* `game/rom/importer.gd` — orchestrates §3; resumable, idempotent.
* `game/rom/nds_fs.gd` — header, FNT/FAT parsing.
* `game/rom/narc.gd`, `game/rom/lz.gd` (LZ77 + LZ11), `game/rom/nitro_gfx.gd` (NCGR/NCLR → `Image`).
* `game/rom/gen5_cells.gd` — NCER cell assembly for Black/White sprites.
* `game/rom/gen5_text.gd` — Black/White text decryption.
* `game/rom/gen5_records.gd` — personal/learnset/evolution/move/item record parsers.
* `game/rom/asset_db.gd` — runtime access API: `species(dex)`, `move(id)`, `sprite_front(dex, shiny)`, `item_icon(id)`, `name(kind, id)`. **The only seam the rest of the game may use.** No system reads the cache directly, so original creatures could be swapped in later without touching gameplay code.
* `game/rom/gba_rom.gd` — GBA header and pointer reads (Emerald).
* `game/rom/gen3_tiles.gd` — Gen 3 tileset, palette, metatile, and attribute decoding.
* `game/rom/tile_atlas_builder.gd` — builds `tiles/emerald_v1.png` and `.json` from `game/config/emerald_tile_map.json`.
* `tools/check_no_nintendo_assets.py` — the §8.3 guard.
* `game/rom/data_pack.gd` — downloads, verifies, and parses the PokéAPI CSV files (§2a).
* `game/rom/fan_sprites.gd` — downloads and verifies the #650–905 sprites; writes them beside the ROM's.
* `game/config/data_sources.json`, `data_pack_manifest.json`, `fan_sprite_manifest.json`, `fan_sprite_credits.json` — pins, hashes, and credits (repo-safe).
