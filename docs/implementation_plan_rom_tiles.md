# Implementation Plan — ROM Overworld Tiles (Emerald GBA)

> **Status: DRAFT / PENDING REVIEW (Item 12 pause).**
> - **Preconditions:** `TENTH_SPRING_ROM_GBA` set, header `BPEE`, SHA-1 `f3ae088181bf583e55daf962a92bb46f4f1d07b7`.
> - **Contract:** `docs/design_rom_asset_pipeline.md` §4, §5, §6, §7; `docs/design_art_direction.md` §1a; `docs/implementation_plan_world_generation_slice2.md` §5, §11, §12.
> - **IP Guard:** The repository is public. Never commit ROM dumps, binary blobs, or extracted graphics. The importer runs strictly on the player's machine at runtime.

---

## 0. Goal & Scope

Deliver runtime overworld map tile extraction from the player's Pokémon Emerald GBA ROM dump to replace placeholder art with genuine Pokémon pixel art.

### In:
- `gba_rom.gd`: Pure GDScript GBA ROM reader with seek-based slicing and LZ77 type `0x10` streaming decompressor.
- `gen3_tiles.gd`: Emerald tileset extractor for primary (`gTileset_General`) and secondary tilesets, BGR555 palette decoding, 16×16 metatile decoding, and 2× integer scale compositing.
- `tile_atlas_builder.gd`: Generates `user://rom_cache/tiles/emerald_v1.png` (32×32 px tiles) and `emerald_v1.json`, matching the layout of `placeholder_v1.json`, plus composition rows for class 21 landmarks.
- `asset_db.tile_atlas()`: Auto-detects valid Emerald cache; returns the Emerald atlas or degrades cleanly to `placeholder_v1`.
- Resumable and idempotent staging in `user://rom_cache.tmp/`.
- Automated tests gated by `TENTH_SPRING_ROM_GBA`.

### Not in:
- Extracting maps, scripts, encounters, or Pokémon battle sprites from Emerald (battle sprites #1–649 come from Black/White).

---

## 1. Architecture

```
game/rom/
  gba_rom.gd             # Low-level ROM reader, header validation, LZ77 decompressor
  gen3_tiles.gd          # Tileset struct, 4bpp tile decode, metatiles & attributes
  tile_atlas_builder.gd  # Atlas generation & landmark compositions builder
```

### 1.1 `gba_rom.gd` — GBA ROM Reader

Pure GDScript, seeking and reading only necessary records to bound memory usage (peak < 64 MiB).

```gdscript
class_name GBARom
extends RefCounted

const EXPECTED_GAME_CODE := "BPEE"
const EXPECTED_SHA1 := "f3ae088181bf583e55daf962a92bb46f4f1d07b7"

var _file: FileAccess
var _file_size: int = 0
var _rom_path: String = ""

func open(path: String) -> Error
func close() -> void
func validate_header() -> bool
func compute_sha1() -> String
func read_u8(offset: int) -> int
func read_u16(offset: int) -> int
func read_u32(offset: int) -> int
func read_bytes(offset: int, length: int) -> PackedByteArray
func decompress_lz77(offset: int) -> PackedByteArray
```

#### LZ77 Decompressor Contract (Type `0x10`):
- Byte 0: `0x10`
- Bytes 1–3: 24-bit little-endian uncompressed length.
- Flag byte: 8 bits (MSB to LSB).
  - Bit 0: Literal byte copied directly to output.
  - Bit 1: 2-byte token `[b1, b2]`. `disp = (((b1 & 0x0F) << 8) | b2) + 1`, `length = (b1 >> 4) + 3`. Copy `length` bytes from `output[pos - disp]`.

---

### 1.2 `gen3_tiles.gd` — Emerald Tileset Extractor

Confirmed ROM offsets:
- Primary tileset `gTileset_General` pointer: `0x3DF704`
- Secondary tilesets table: contiguous array starting at `0x3DF71C` (24 bytes per record)
- Record layout (`struct Tileset`):
  - `+0x00`: `is_compressed` (u8)
  - `+0x01`: `is_secondary` (u8)
  - `+0x02`: `padding` (u16)
  - `+0x04`: `tiles_ptr` (u32, e.g. `0x08DD5010`)
  - `+0x08`: `pal_ptr` (u32, e.g. `0x08DD4E10`)
  - `+0x0C`: `meta_ptr` (u32, e.g. `0x083960F0`)
  - `+0x10`: `attr_ptr` (u32, e.g. `0x083980F0`)
  - `+0x14`: `callback_ptr` (u32)

#### Metatile Decoding (16×16 pixels):
- Consists of 8 `u16` tile references (16 bytes):
  - Words 0–3: Bottom layer (TL, TR, BL, BR)
  - Words 4–7: Top layer (TL, TR, BL, BR)
- Each word:
  - Bits 0–9: Tile index (0–511: primary tiles; 512–1023: secondary tiles).
  - Bit 10: Horizontal flip (`xflip`).
  - Bit 11: Vertical flip (`yflip`).
  - Bits 12–15: Palette index (0–15).
- Compositing:
  1. Bottom layer rendered first.
  2. Top layer composited over bottom (palette color index 0 is transparent).
  3. Scaled 2× nearest-neighbor to produce 32×32 overworld tile.

---

### 1.3 `tile_atlas_builder.gd` — Atlas Builder

Reads `game/config/emerald_tile_map.json` (schema: `design_rom_asset_pipeline.md` §4):
1. **Vocabulary Rows:**
   For each row in `game/assets/tiles/placeholder_v1.json` `(class, variant)`:
   - If unmasked: metatile mapped to column 0.
   - If masked: 16 columns corresponding to connectivity masks 0–15.
2. **Modular Buildings:**
   Renders template rows for `house_s`, `house_m`, and `block_l` for roof colors 0–7.
3. **Class 21 Landmark Compositions (slice-2 plan §12.3):**
   Renders look-alike compositions from `emerald_tile_map.json` into dedicated atlas rows for the 14 landmarks defined in `design_art_direction.md` §1a. They are named by function, never by the Emerald place or facility they come from (F59):
   - `pyramid_hall`, `dome_centre`, `tall_tower`, `museum_hall`, `maritime_hall`, `theatre_hall`, `dept_store`, `casino_hall`, `observatory`, `power_station`, `grand_hall`, `stadium`, `elevated_road`, `maze_house`.
4. **Gaps keep the placeholder.** Every `(class, variant, mask)` the table lists under `gaps` gets its row or column copied from `placeholder_v1`, so the atlas always has a tile for everything the synthesiser can emit. Tilesets are keyed by index (`primary`, `sec05`, …), never by name.

---

### 1.4 `asset_db.gd` Integration

```gdscript
func tile_atlas() -> Dictionary:
    if _cached_emerald_atlas != null and _cached_emerald_atlas.is_valid():
        return _cached_emerald_atlas
    if _can_load_emerald_cache():
        var loaded := _load_emerald_cache()
        if loaded.is_valid():
            _cached_emerald_atlas = loaded
            return _cached_emerald_atlas
    return _placeholder_atlas
```

---

## 2. Resumable Staging & Atomic Cache Write

To ensure robust crash recovery:
1. Target cache directory: `user://rom_cache/tiles/`.
2. All tiles and atlas files written to temporary directory: `user://rom_cache.tmp/tiles/`.
3. Validation pass (§3) executes against `user://rom_cache.tmp/tiles/`.
4. If validation passes:
   - Atomic rename `user://rom_cache.tmp/tiles/` -> `user://rom_cache/tiles/`.
   - Update `user://rom_cache/manifest.json` with `tiles` metadata:
     ```json
     {
       "gameCode": "BPEE",
       "sha1": "f3ae088181bf583e55daf962a92bb46f4f1d07b7",
       "importedAt": 1729718400,
       "atlas": "tiles/emerald_v1.png",
       "importerVersion": 1
     }
     ```
5. If validation fails or process is interrupted, `user://rom_cache.tmp/` is discarded; existing valid cache is left untouched.

---

## 3. Spot-Checks & Validation (`design_rom_asset_pipeline.md` §7)

The builder must fail and reject cache generation if any of these conditions occur. The spike implements these rules as `tools/rom_spike/emerald/mapping_checks.py` (one function per rule, run together by `run_all`), and its tests run them on the committed table (Item 12b); the importer repeats them on the player's machine. Thresholds are fixed numbers, not tuning knobs:

1. **Schema coverage.** Every `(class, variant, mask)` the synthesiser can emit (`placeholder_v1.json`: 16 masks for a masked class, mask 0 otherwise, 16 `SIGN` variants) has an entry or is covered by a `gaps` rule (classes, with optional variants and masks).
2. **Palettes.** Every palette of every tileset has exactly 16 colours, each channel 0–255, so a 4-bpp tile cannot use more than 16 colours from it (`check_palettes`).
3. **Lawn.** The base lawn (`GRASS` variant 0) is green-dominant ($G > R$ and $G > B$). Every `GRASS` variant has the ordinary behaviour `0x00` and a blank top layer, draws $\ge 90\%$ of its pixels from the base lawn's colours, and has no compact patch of other colours larger than 3 pixels (a corner of another object).
4. **Water.** Every mapped `WATER` piece has a standing-water behaviour byte (`0x10`, `0x11`, `0x12`, `0x15`, `0x16`, `0x17`; not the waterfall `0x13`) and is $\ge 90\%$ water in its central 8 × 8. Every water pixel is drawn in a colour the mask-15 piece uses ($\ge 99\%$), so a shore never sits as a seam beside the lake. The mask-15 piece is $\ge 95\%$ water-coloured (blue is the strongest channel) with each 4 × 4 corner $\ge 90\%$ water. For every mask, 15 included, the band along a side (4 px deep, the middle 8 px of the side) is $\ge 25\%$ non-water where the mask bit is 0 (a shore) and $\ge 90\%$ water where it is 1.
5. **Tall grass, sand, and bridge.** Every `TALL_GRASS` piece has a tall-grass behaviour (`0x02` or `0x03`), a blank top layer (no tree or bush painted over it), a green-dominant mean colour, and per-channel variance $> 500$ (a wrong decompression or palette cannot pass). The `SAND` piece has the sand behaviour `0x21`. The `CROP` piece is a field: a blank top layer and at most 10% of the lawn's colours. Every `BRIDGE` piece has the bridge-over-water behaviour `0x2B`, and the pieces of a north-south deck (masks 7, 13, 6, 12, 3, 9) are never the pieces of an east-west deck (masks 14, 11).
6. **No stand-ins.** Two classes never share a metatile unless `shared` lists that share as intentional. With the ROM, metatiles that draw identical pixels count as one piece, so a twin under a second number is still a share (footpath ground and plain sand are the one such share). A primary-range id (below 512) is a primary piece whatever tileset key its entry carries. A `shared` entry whose classes do not match the pieces' real users is itself an error.
7. **Gaps are gaps.** No `tile_map` entry exists for anything `gaps` lists. Each gap has a unique snake_case `id`, a `reason` of at least 12 characters, a non-empty list of class numbers 0–20, and, when given, a non-empty list of masks 0–15 and of variants 0–63.
8. **Metatile boundary.** Rejects an entry whose metatile index is negative, is $\ge 512$ in the primary tileset, or is $\ge 512 +$ the named secondary's metatile count; whose tileset key is not `primary` or `secNN` with NN from 1 to 57; or that references a tile past the end of its tileset's tile data. `secNN` is the tileset record at `0x3DF704 + 24 * NN`, so the primary is index 0 and `sec01` is the first secondary.
9. **Roof colourways.** At least four distinct hues among `ROOF` variants 0–7. A variant's hue is the 30° hue bucket of its most common pixel colour (ignoring pixels whose brightest channel is below 90) across all its mapped masks; a colour with saturation below 0.2 or value below 0.25 falls in one shared "grey" bucket, which counts as a hue. If the tilesets honestly have fewer than four, each mapped variant must be a colourway of its own, and every other variant 0–7 must be covered by a `gaps` rule with a reason (guide §3 step 4).
10. **Building pieces and templates.** `ROOF` pieces have behaviour `0x00`, `WALL` pieces `0x00` or `0x01`, and `DOOR` pieces `0x69`; no two roof variants use the same set of pieces. The `buildings` block equals what `tile_map` implies (the synthesiser's own neighbour-mask rules over the three templates), so the two can never disagree.
11. **Compositions.** The 14 neutral ids exist; each has integer $w, h \ge 1$ with $w \times h$ metatiles, and every one but the raised road (`elevated_road`) has a door inside the grid, on a piece with a door behaviour (`0x60` or `0x69`).
12. **Neutral names and table shape.** Tileset keys are `primary` or `secNN`, and the `tilesets` block lists exactly the tilesets the table uses, each at its own index. Composition ids are the 14 function names, building names the three templates. No id or reason contains a forbidden place word (the checker keeps only SHA-1 hashes of those words, so it names nothing). The table holds numbers, ids, and short plain-ASCII reasons only: the version-2 schema of `design_rom_asset_pipeline.md` §4, explicit masks 0–15 (no wildcard), integer fields typed as integers, no extra fields. Rules 1, 6, 7, 8 (without tile data), 10 (`buildings`), 11 (structure), and 12 need no ROM, so they run in CI too (`test_rom_spike.py`, run by `game/tests/test_runner.py`).

**Each rule is also tested against a wrong table.** The falsifying tests cover the pass-22 choices (a sign object as lawn, an edge piece as water interior, a tree-over-grass piece as tall grass, one piece for grave and sign, one roof for all colours, a bridge made of a road piece) and a real piece chosen so that only the named sub-rule can catch it (a lawn with a painted-over object, a corner wedge, a waterfall, a sea piece, a shore on the wrong side, a door that is not a door, and so on). Where no real piece isolates a threshold, a crafted canvas does. Each test names the mutated entry, and a mutation run that loosens any numeric threshold, or widens any behaviour set, must fail at least one test: a rule that cannot fail proves nothing.

---

## 4. Test Strategy

1. **Gated Execution:**
   - All tests requiring ROM access inspect `OS.get_environment("TENTH_SPRING_ROM_GBA")`.
   - If not set: skip with message: `"[SKIP] TENTH_SPRING_ROM_GBA not set. Emerald ROM tests skipped."`
   - CI environment never has ROMs and must cleanly pass all checks without failures.
2. **Automated Unit Tests (`test_gen3_tiles.gd`):**
   - Header & SHA-1 verification.
   - LZ77 decompression byte accuracy.
   - Palette decoding & color conversion.
   - Metatile rendering & variance verification.
   - Falsifying wrong-palette test.
   - Atlas layout verification vs `placeholder_v1.json`.
