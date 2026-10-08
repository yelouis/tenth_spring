# ROM Asset Pipeline — "Bring Your Own ROM"

This document defines how Tenth Spring gets Pokémon sprites, species data, moves, items, and names **without the repository ever containing them**. It is modeled on PokeMMO, which ships no Nintendo files and reads game assets from ROMs the player supplies. Every Pokémon-facing system depends on this pipeline, which is why it is Phase 2 in the master plan.

**Why this model.** The GitHub repo (`yelouis/tenth_spring`) is **public**. Nintendo has historically acted against fan projects that *distributed its assets*:
- **Pokémon Essentials** — taken down August 2018; the kit bundled Nintendo graphics, music, and tilesets.
- **Pokémon Uranium** — 2016.
- **Pokémon Prism** — cease-and-desist four days before its December 2016 release.

PokeMMO distributes no assets and requires players to supply their own ROMs; it has no reported takedown. ROM hacks follow the same principle: they ship as patches against the player's own ROM, never as the ROM itself. BYOR reduces risk substantially, but it does **not** eliminate it — see §8.

**Scope (Decision 12, 2026-10-08): all 649 Pokémon of Generations 1–5.** Generations 6–9 are out of scope permanently. Their games are 3DS/Switch titles built from 3D models, not sprites. The sprites found online are rips or fan redraws, and using them would break this document's first rule.

---

## 1. What lives where

| Lives in the repo | Never in the repo |
|---|---|
| Importer and parser code | ROM files (`.nds`, `.gba`, …) |
| Game mechanics: formulas, type chart, our own spawn tables (species referenced by **National Dex number**) | Sprites, palettes, item icons, audio, tilesets extracted from a ROM |
| Original art: overworld tiles, UI, fonts | Nintendo text banks: species/move/item names, Pokédex entries |
| Decoding rules for text (functional code, not text) | Extracted stat tables (base stats, learnsets, move data) |

All extracted content lands in **`user://rom_cache/`** on the player's machine — outside the repo in every build, including editor runs.

## 2. Supported ROMs

Two Nintendo DS games, each **dumped by the player from a cartridge they own**:

| ROM | Game codes (header `0x0C`) | Provides | Required? |
|---|---|---|---|
| **Pokémon Black or White (USA)** | `IRBO` (Black) / `IRAO` (White) — **verify** both against the No-Intro DAT | **All data for all 649 species**: base stats, types, abilities, learnsets, evolutions, moves (559), items, item icons, and all names/text. Battle sprites for #494–649 (and, under Decision 10 = B or C, for #1–493). | **Always** |
| **Pokémon Platinum (USA)** | `CPUE` | Battle sprites for #1–493 in the Diamond/Pearl style | **Only if Decision 10 = A or C** |

**Black and White are interchangeable** for our purposes. Their version differences are wild-encounter tables and exclusive story content, neither of which we read. The importer accepts either and treats them identically.

**Why Black/White is the single data source.** One parser for every species means:
- Gen 1–4 Pokémon keep the Gen 5 moves they can learn in Black/White.
- Only one text decoder is needed (Gen 5 text, not Gen 4's custom character table).
- Every species' data shares one format.

Battle *rules* still follow Generation IV (`design_creatures_and_battles.md`); Gen 5 supplies data, not rules.

**Rules for everyone — the game, its docs, and any agent working on it:**
- **Never download a ROM, link to a ROM site, or help a user find one.** Only users supply ROMs.
- **Verify on import.** The game code must match the table above. The file's SHA-1 must match the No-Intro known-good hash for that title. *(Hashes are deliberately not hardcoded here: the importing agent takes them from the No-Intro DAT and records the source, never a guess.)* A ROM that fails either check is rejected with a plain-language message.
- **v1 rejects** modified ROMs (hacks), non-USA releases, and Black 2/White 2. B2W2's archive layout differs; supporting it is a possible later extension.

## 3. Import flow (first run, and on demand)

Each ROM is imported independently; the cache records which ones are present.

```
1 LOCATE   Player picks a ROM file in a native file dialog. Store only its path.
2 VERIFY   Game code in §2's table; SHA-1 == No-Intro hash for that title. Reject otherwise.
3 PARSE    Read the NDS header → file name table (FNT) + file allocation table (FAT).
4 EXTRACT  Pull that ROM's archives in §5 by path; unpack each NARC.
5 DECODE   Sprites → PNG. Data: fixed-layout records → species/move/item/evolution/learnset tables.
           Text: decrypt message banks → names.
6 WRITE    user://rom_cache/ (layout §6). Write that ROM's manifest entry last.
7 VALIDATE Spot-checks (§7) before marking that ROM's part of the cache valid.
```
- **Resumable and idempotent:** write into `user://rom_cache.tmp/`, then rename to `user://rom_cache/` only after the manifest is written. A crash leaves the old cache intact.
- **The game runs in a degraded "no ROM" mode before import.** Onboarding, the map, and sync work with placeholder silhouettes; Pokémon content unlocks once the required ROMs (§2) are valid. If Decision 10 = A and only Black/White is imported, Gen 1–4 battles still work, showing a silhouette instead of a sprite.
- **Pure GDScript:** the importer uses `FileAccess.get_buffer` and `PackedByteArray.decode_u16/u32`, and needs no native extension.

## 4. Formats (each **verify** must be confirmed by the spike and replaced with the confirmed rule)

**Shared (both ROMs):**
- **NDS header:** FNT offset `0x40`, FNT size `0x44`, FAT offset `0x48`, FAT size `0x4C` (u32 little-endian). Game code at `0x0C`. Black/White are DSi-enhanced; the code is still at `0x0C`.
- **NARC:** magic `NARC`, then three chunks: `BTAF` (file allocation), `BTNF` (file names), `GMIF` (file images).
- **NCGR / NCLR:** tile graphics (`RGCN`) and palettes (`RLCN`); 4bpp tiles; BGR555 palette entries.
- **LZ compression:** if an extracted file's first byte is `0x10` (LZ77) or `0x11` (LZ11), decompress before parsing. Gen 5 archives are known to use LZ11 in places — **verify** which files.

**Platinum — battle sprites (only if Decision 10 = A or C):**
- Pixel data in the `RAHC`/`CHAR` block is encrypted with the Gen 4 PRNG: `seed = seed × 0x41C64E6D + 0x6073`, XOR applied per u16.
- **The iteration direction and seed source differ between Diamond/Pearl and Platinum.** The spike decodes one known species and records the exact rule here, citing `pret/pokeplatinum`.

**Black/White:**
- **Battle sprites** are composed from parts, not stored as one image:
  - an `NCGR` tile sheet;
  - an `NCER` cell bank that says how parts assemble;
  - `NANR`/`NMCR`/`NMAR` animation data;
  - separate normal and shiny `NCLR` palettes.

  A static sprite = cells assembled for the **first frame** of the idle animation, on a 96×96 canvas — **verify**. The per-species file layout inside `a/0/0/4` is also **verify** (14,285 files is not an exact multiple of 649; forms and padding account for the rest).
- **Data records:** personal (base stats etc.), learnset, evolution, and move entries are fixed-layout records. **Verify** each record size and field offset against Project Pokémon's raw database and an open-source editor's source code before relying on them.
- **Text banks:** UTF-16 code units, encrypted per string with a 16-bit key that is advanced after each character — **verify** the exact key schedule and record it here.

**Reference sources** (documentation only — never sources of ROMs):
- `pret/pokeplatinum` (Platinum decompilation).
- Project Pokémon's raw database pages for Black (`projectpokemon.org/rawdb/black/`).

## 5. What to extract

**Black/White** (file counts from Project Pokémon's Black archive list; White must match — **verify**):

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

**Platinum** (only if Decision 10 = A or C):

| Archive | Contents | Cache output |
|---|---|---|
| `/poketool/pokegra/pl_pokegra.narc` (2,964) | Battle sprites + palettes. 2,964 = 494 × 6, consistent with six files per species at index `dex × 6` — **verify** | `sprites_dp/front/{dex}.png`, `back/`, `front_shiny/`, `back_shiny/` for #1–493 |

**Not extracted:** overworld maps and buildings. Our world is generated from OpenStreetMap, and overworld tiles are original art (`design_art_direction.md`).

## 6. Cache layout and versioning

```
user://rom_cache/
  manifest.json   { importerVersion,
                    roms: { bw: {gameCode, sha1, importedAt},
                            pt: {gameCode, sha1, importedAt} | absent },
                    speciesCount, moveCount }
  sprites/  sprites_dp/  icons/  data/  text/en/
```
- **Re-import automatically** if `importerVersion` changes, or if a ROM's `sha1` no longer matches the file the player pointed at.
- **The cache is regenerable, never a source of truth.** Saves store National Dex numbers and instance data, never extracted content. Deleting the cache must never lose player progress.
- **Sprite style is chosen in one place:** `asset_db.sprite_front(dex, shiny)` reads `sprites_dp/` or `sprites/` per Decision 10. No other code knows sprites come from two sources.

## 7. Import validation (the importer is not "done" until these pass)

Spot-check against facts the player's own ROMs must contain. Any failure leaves that part of the cache invalid and reports which check failed.

**Black/White:**
- Species count = **649**; move count = **559**.
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
- **Chandelure's static front sprite** is a real image, not noise. Two checks: ≤ 16 distinct colours per palette, and a pixel-variance threshold that "static" from a wrong decryption or wrong cell assembly cannot pass.

**Platinum** (only if imported): Giratina's (`#487`) front sprite passes the same two image checks.

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
4. **ROM-dependent tests** run **only** when a developer supplies ROMs locally (`TENTH_SPRING_ROM_BW`, and `TENTH_SPRING_ROM_PT` if Platinum is used). Otherwise they are skipped with an explicit message, never faked. CI never has a ROM.
5. **No Nintendo trademarks in branding.** Do not use "Pokémon" or other Nintendo trademarks in the game's title, logo, store pages, or release names. The game is "Tenth Spring."
6. **The phone companion contains no Nintendo assets or names**, ever (`design_companion_and_sync.md` §1). It is a location tracker and must stay store-listable.

## 9. Distribution

- **No commerce of any kind:** no Steam, no sales, no ads, and no donations tied to the game. Any of these makes a takedown far more likely.
- **The asset-free client** is distributed via GitHub Releases from the public repo. Players install it, then import their own ROMs (§3).
- **Honest risk statement:** BYOR keeps Nintendo's assets out of our distribution, which is what separated PokeMMO's survival from Essentials' takedown. It is not immunity: Prism was a patch and still received a cease-and-desist once it became high-profile.
  - Keep the project low-profile.
  - If a takedown notice ever arrives, comply immediately and stop distribution. Do not argue it in public.

## 10. Files
* `game/rom/importer.gd` — orchestrates §3 per ROM; resumable, idempotent.
* `game/rom/nds_fs.gd` — header, FNT/FAT parsing.
* `game/rom/narc.gd`, `game/rom/lz.gd` (LZ77 + LZ11), `game/rom/nitro_gfx.gd` (NCGR/NCLR → `Image`).
* `game/rom/gen5_cells.gd` — NCER cell assembly for Black/White sprites.
* `game/rom/gen4_sprite_crypt.gd` — Platinum sprite decryption (only if Decision 10 = A or C).
* `game/rom/gen5_text.gd` — Black/White text decryption.
* `game/rom/gen5_records.gd` — personal/learnset/evolution/move/item record parsers.
* `game/rom/asset_db.gd` — runtime access API: `species(dex)`, `move(id)`, `sprite_front(dex, shiny)`, `item_icon(id)`, `name(kind, id)`. **The only seam the rest of the game may use.** No system reads the cache directly, so original creatures could be swapped in later without touching gameplay code.
* `tools/check_no_nintendo_assets.py` — the §8.3 guard.
