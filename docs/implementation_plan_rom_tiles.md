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

Reads `game/config/emerald_tile_map.json`:
1. **Vocabulary Rows:**
   For each row in `game/assets/tiles/placeholder_v1.json` `(class, variant)`:
   - If unmasked: metatile mapped to column 0.
   - If masked: 16 columns corresponding to connectivity masks 0–15.
2. **Modular Buildings:**
   Renders template rows for `house_s`, `house_m`, and `block_l` for roof colors 0–7.
3. **Class 21 Landmark Compositions (slice-2 plan §12.3):**
   Renders look-alike compositions from `emerald_tile_map.json` into dedicated atlas rows for the 14 landmarks defined in `design_art_direction.md` §1a:
   - `pyramid_hall`, `space_center`, `battle_tower`, `art_museum`, `maritime_museum`, `contest_hall`, `dept_store`, `game_corner`, `weather_institute`, `power_plant`, `league_hall`, `stadium`, `cycling_road`, `trick_house`.

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

The builder must fail and reject cache generation if any of these conditions occur:
1. **Schema Coverage:** Every `(class, variant)` from `placeholder_v1.json` has an atlas row or is documented in `gaps`.
2. **Palette Color Count:** Every decoded tile uses $\le 16$ colors from its palette.
3. **Color Dominance & Variance Thresholds:**
   - **Grass (Metatile 1):** Green channel dominant ($G > R$ and $G > B$).
   - **Tall Grass (Metatile 13):** Green channel dominant and pixel variance $\sigma^2 > 500$ on all three channels.
   - **Water (Metatile 44):** Blue channel dominant ($B > R$ and $B > G$).
4. **Metatile Boundary Check:** Rejects mapping table entries referencing metatile index $\ge$ tileset metatile count.

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
