# ROM Asset Pipeline — "Bring Your Own ROM"

This document defines how Tenth Spring gets Pokémon sprites, species data, moves, items, and names **without the repository ever containing them**. It is modeled on PokeMMO, which ships no Nintendo files and reads game assets from ROMs the player supplies. Every Pokémon-facing system depends on this pipeline, which is why it is Phase 2 in the master plan.

**Why this model.** The GitHub repo (`yelouis/tenth_spring`) is **public**. Nintendo has historically acted against fan projects that *distributed its assets* — the Pokémon Essentials kit (taken down August 2018; it bundled Nintendo graphics, music, and tilesets), Pokémon Uranium (2016), and Pokémon Prism (cease-and-desist four days before its December 2016 release). PokeMMO, which distributes no assets and requires players to supply their own ROMs, has no reported takedown. ROM hacks follow the same principle: they are distributed as patches (`xdelta` for Platinum hacks) applied to the player's own ROM, never as the ROM itself. BYOR reduces risk substantially; it does **not** eliminate it — see §8.

---

## 1. What lives where

| Lives in the repo | Never in the repo |
|---|---|
| Importer and parser code | ROM files (`.nds`, `.gba`, …) |
| Game mechanics: formulas, type chart, our own spawn tables (species referenced by **National Dex number**) | Sprites, palettes, item icons, audio, tilesets extracted from a ROM |
| Original art: overworld tiles, UI, fonts | Nintendo text banks: species/move/item names, Pokédex entries |
| A character-encoding table for decoding Gen 4 text (functional data) | Extracted stat tables (base stats, learnsets, move data) |

All extracted content lands in **`user://rom_cache/`** on the player's machine — outside the repo in every build, including editor runs.

## 2. Supported ROM

- **Target: Pokémon Platinum (USA)**, NDS game code **`CPUE`** at header offset `0x0C`. *(Pending **Decision 9**; Platinum is the recommendation — it is Gen 4 with Diamond/Pearl-style sprites, contains data for all 493 species, includes Giratina and the Distortion World that this setting builds on, and has the most complete community documentation via the pret decompilation `pret/pokeplatinum`.)*
- **The player must dump the ROM from a cartridge they own.** The game, its docs, and any agent working on it **must never download a ROM, link to a ROM site, or help a user find one.** Only users can supply ROMs.
- Verification on import: game code must equal `CPUE`; compute the file's SHA-1 and compare it to the No-Intro known-good hash for Platinum (USA). *(The hash is deliberately not hardcoded here — the importing agent must take it from the No-Intro DAT and record its source, not guess it.)* A ROM that fails either check is rejected with a plain-language message; modified ROMs (hacks) are rejected in v1.

## 3. Import flow (first run, and on demand)

```
1 LOCATE   Player picks the ROM file in a native file dialog. Store only its path.
2 VERIFY   Game code == CPUE; SHA-1 == No-Intro Platinum (USA). Reject otherwise.
3 PARSE    Read the NDS header → file name table (FNT) + file allocation table (FAT).
4 EXTRACT  Pull the archives in §5 by path; unpack each NARC.
5 DECODE   Sprites: decrypt (if needed) → NCGR tiles + NCLR palette → PNG.
           Data: parse fixed-layout records → species/move/item/evolution/learnset tables.
           Text: decrypt message banks → names, Pokédex text.
6 WRITE    user://rom_cache/ (layout §6). Write a manifest last.
7 VALIDATE Spot-check a fixed set of species (§7) before marking the cache valid.
```
- Import is **resumable and idempotent**: write into `user://rom_cache.tmp/`, then rename to `user://rom_cache/` only after the manifest is written. A crash leaves the old cache intact.
- The game **must run (in a degraded "no ROM" mode) before import** — onboarding, the map, and sync work with placeholder silhouettes. Pokémon content unlocks once the cache is valid.
- Importer runs in pure GDScript (`FileAccess.get_buffer`, `PackedByteArray.decode_u16/u32`). **It needs no native extension**, so it is independent of Decision 7.

## 4. Formats (verify each against `pret/pokeplatinum` before relying on it)

- **NDS header:** FNT offset `0x40`, FNT size `0x44`, FAT offset `0x48`, FAT size `0x4C` (u32 little-endian).
- **NARC:** magic `NARC`, followed by `BTAF` (file allocation), `BTNF` (file names), `GMIF` (file images) chunks.
- **NCGR / NCLR:** tile graphics (`RGCN`) and palettes (`RLCN`); 4bpp tiles, BGR555 palette entries.
- **LZ77:** when an extracted file's first byte is `0x10`, decompress (Nintendo LZ77 type 0x10) before parsing.
- **Sprite encryption:** Diamond/Pearl battle-sprite pixel data (the `RAHC`/`CHAR` block) is encrypted with the Gen 4 PRNG (`seed = seed × 0x41C64E6D + 0x6073`, XOR per u16). **The iteration direction and seed source differ between DP and Platinum** — the importer spike's first job is to decode one known species correctly and record the exact rule here.
- **Text banks:** Gen 4 message banks are per-entry encrypted and use a Gen 4 character table, not ASCII/UTF-16. Use pret's `charmap` as the reference for the encoding table.

## 5. What to extract (Platinum paths, confirmed via Project Pokémon's raw database)

| Archive | Contents | Cache output |
|---|---|---|
| `/poketool/pokegra/pl_pokegra.narc` (2,964 files) | Battle sprites + palettes — 2,964 = 494 × 6, consistent with six files per species (index = `dex × 6`; **verify**) | `sprites/front/{dex}.png`, `back/`, `front_shiny/`, `back_shiny/` |
| `/poketool/personal/pl_personal.narc` (508) | Base stats, types, catch rate, base EXP, growth rate, abilities, gender ratio | `data/species.json` |
| `/poketool/personal/wotbl.narc` (508) | Level-up learnsets | `data/learnsets.json` |
| `/poketool/personal/evo.narc` (508) | Evolution methods | `data/evolutions.json` |
| `/poketool/waza/pl_waza_tbl.narc` (471) | Move power, type, accuracy, PP, category (physical/special/status), effect id | `data/moves.json` |
| `/itemtool/itemdata/pl_item_data.narc` (446) | Item parameters | `data/items.json` |
| `/itemtool/itemdata/item_icon.narc` (711) | Item icons + palettes | `icons/items/{item_id}.png` |
| `/msgdata/pl_msg.narc` (724) | Text banks: species, move, item, ability names; Pokédex entries | `text/en/*.json` |

**Not extracted:** overworld maps and buildings. Gen 4 overworlds are 3D models (NSBMD), not 2D tilesets, and our world is generated from OpenStreetMap anyway. Overworld tiles stay original art (`design_art_direction.md`).

## 6. Cache layout and versioning

```
user://rom_cache/
  manifest.json      { importerVersion, romGameCode, romSha1, importedAt, speciesCount }
  sprites/  icons/  data/  text/en/
```
- If `importerVersion` or `romSha1` doesn't match the running game, re-import automatically.
- The cache is **regenerable, never a source of truth** — saves store National Dex numbers and instance data, never extracted content. Deleting the cache must never lose player progress.

## 7. Import validation (the importer is not "done" until these pass)

Spot-check against facts the player's own ROM must contain: species count = 493 (+ forms); `#487` (Giratina) is dual Ghost/Dragon; `#442` (Spiritomb) is Ghost/Dark; `#94` (Gengar) is Ghost/Poison; one known sprite decodes to a non-noise image (pixel-variance threshold, so "static" from a wrong decryption fails). Any failure leaves the cache invalid and reports which check failed.

## 8. Legal and repository guardrails (non-negotiable)

1. **Nothing from §1's right-hand column is ever committed** — not in a test fixture, not a debug PNG, not "temporarily." A ROM in public git history stays there until the history is rewritten.
2. `.gitignore` blocks ROM and Nintendo-format extensions (`*.nds`, `*.gba`, `*.gb`, `*.gbc`, `*.narc`, `*.ncgr`, `*.nclr`, `*.ncer`) and any local cache directory.
3. A repository check (`tools/check_no_nintendo_assets.py`, run in CI and as a pre-commit hook) fails if any tracked file has a forbidden extension, begins with the `NARC` magic, or carries an NDS header game code (`CPUE`, `ADAE`, `APAE`, `IPKE`, `IPGE`) at offset `0x0C`. Because the pre-commit hook is the **only** defense before content becomes public, it must also:
   - check **every staged path except deletions**, renames and copies included (`--diff-filter=d`);
   - read bytes from **what will be committed** — the index (`git cat-file`/`git show :path`) — never the working tree;
   - and the battery must **fail, not skip**, if the guard script is missing.
   CI checks out full history and scans **every commit in the pushed range**, not only the final tree — a file added then removed is still in public history and must be reported.
4. Tests that need Pokémon data run **only** when a developer supplies a ROM locally (env var `TENTH_SPRING_ROM`); otherwise they are skipped, not faked. CI never has a ROM.
5. **Do not use "Pokémon" or other Nintendo trademarks in the game's title, logo, store pages, or release names.** The game is "Tenth Spring."
6. The **phone companion contains no Nintendo assets or names**, ever (`design_companion_and_sync.md` §1). It is a location tracker and must stay store-listable.

## 9. Distribution

- No Steam, no sales, no ads, no donations tied to the game — any of these makes a takedown far more likely.
- The **asset-free client** is distributed via GitHub Releases from the public repo. Players install it, then import their own ROM (§3).
- **Honest risk statement:** BYOR keeps Nintendo's assets out of our distribution, which is what separated PokeMMO's survival from Essentials' takedown. It is not immunity — Prism was a patch and still received a cease-and-desist once it became high-profile. Keep the project low-profile. If a takedown notice ever arrives, comply immediately and stop distribution; do not argue it in public.

## 10. Files
* `game/rom/importer.gd` — orchestrates §3; resumable, idempotent.
* `game/rom/nds_fs.gd` — header, FNT/FAT parsing.
* `game/rom/narc.gd`, `game/rom/lz77.gd`, `game/rom/nitro_gfx.gd` (NCGR/NCLR → `Image`), `game/rom/gen4_text.gd`.
* `game/rom/asset_db.gd` — runtime access API: `species(dex)`, `move(id)`, `sprite_front(dex, shiny)`, `item_icon(id)`, `name(kind, id)`. **The only seam the rest of the game may use** — no system reads the cache directly, so original creatures could be swapped in later without touching gameplay code.
* `tools/check_no_nintendo_assets.py` — the §8.3 guard.
