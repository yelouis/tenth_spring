#!/usr/bin/env python3
"""
Tenth Spring — Pokémon Emerald GBA Tile Spike (Item 12)
Contract: docs/agent_execution_guide.md §6
          docs/design_rom_asset_pipeline.md §4, §5
          docs/design_art_direction.md §1a

Extracts, decodes, and validates Pokémon Emerald overworld tilesets directly from
the player's GBA ROM dump.
Strictly zero Nintendo assets committed to repository.
All output images written to ~/.tenth_spring_rom_spike/emerald/.
Pure Python 3 standard library; runs under python3 -I.
"""

import hashlib
import json
import os
import struct
import sys
import zlib

EXPECTED_HEADER = b"BPEE"
EXPECTED_SHA1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"

PRIMARY_TILESET_OFFSET = 0x3DF704
SECONDARY_TILESETS_START = 0x3DF71C
MAP_BANK_TABLE_OFFSET = 0x486578

TILESET_RECORD_SIZE = 24

FEATURED_SECONDARY_TILESETS = {
    "sec01_petalburg": 1,        # 0x3df71c, 144 metatiles (Petalburg, Littleroot, Oldale)
    "sec02_rustboro": 2,         # 0x3df734, 350 metatiles (Stone/brick city, Devon Corp)
    "sec04_slateport": 4,        # 0x3df764, 406 metatiles (Oceanic Museum, Contest Hall, Market)
    "sec05_mauville": 5,         # 0x3df77c, 510 metatiles (Game Corner, Cycling Road, Gym)
    "sec09_lilycove": 9,         # 0x3df7dc, 351 metatiles (Art Museum, Dept Store, Contest Hall)
    "sec10_mossdeep": 10,        # 0x3df7f4, 454 metatiles (Space Center)
    "sec44_battle_frontier": 44  # 0x3dfb24, 510 metatiles (Battle Pyramid, Tower, Dome)
}


def find_repo_root():
    cur = os.path.abspath(__file__)
    for _ in range(5):
        cur = os.path.dirname(cur)
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def check_preconditions():
    rom_path = os.environ.get("TENTH_SPRING_ROM_GBA")
    if not rom_path:
        raise RuntimeError("TENTH_SPRING_ROM_GBA environment variable is not set")
    rom_path = os.path.expanduser(rom_path)
    if not os.path.exists(rom_path):
        raise RuntimeError(f"ROM file does not exist: {rom_path}")

    repo_root = find_repo_root()
    real_rom_path = os.path.realpath(rom_path)
    real_repo_root = os.path.realpath(repo_root)
    if real_rom_path.startswith(real_repo_root):
        raise RuntimeError("ROM file cannot be located inside the repository")

    with open(rom_path, "rb") as f:
        rom_data = f.read()

    if len(rom_data) < 0xC0:
        raise RuntimeError("File too small to be a GBA ROM")

    header_code = rom_data[0xAC:0xB0]
    if header_code != EXPECTED_HEADER:
        raise RuntimeError(f"Header code mismatch: expected {EXPECTED_HEADER.decode()}, got {header_code}")

    actual_sha1 = hashlib.sha1(rom_data).hexdigest().lower()
    if actual_sha1 != EXPECTED_SHA1:
        raise RuntimeError(f"SHA-1 mismatch: expected {EXPECTED_SHA1}, got {actual_sha1}")

    return rom_data


def lz77_decompress(data, offset):
    magic = data[offset]
    if magic != 0x10:
        raise ValueError(f"Expected LZ77 type 0x10 magic byte, got {hex(magic)}")
    decomp_size = data[offset + 1] | (data[offset + 2] << 8) | (data[offset + 3] << 16)
    out = bytearray()
    pos = offset + 4
    data_len = len(data)

    while len(out) < decomp_size and pos < data_len:
        flag = data[pos]
        pos += 1
        for bit in range(7, -1, -1):
            if (flag >> bit) & 1:
                if pos + 1 >= data_len:
                    break
                b1 = data[pos]
                b2 = data[pos + 1]
                pos += 2
                disp = (((b1 & 0x0F) << 8) | b2) + 1
                length = (b1 >> 4) + 3
                for _ in range(length):
                    out.append(out[-disp])
                    if len(out) == decomp_size:
                        break
            else:
                if pos >= data_len:
                    break
                out.append(data[pos])
                pos += 1
                if len(out) == decomp_size:
                    break
            if len(out) == decomp_size:
                break

    return bytes(out)


def bgr555_to_rgb(val):
    r = val & 0x1F
    g = (val >> 5) & 0x1F
    b = (val >> 10) & 0x1F
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2))


class EmeraldTileset:
    def __init__(self, rom_data, struct_offset, is_secondary=False, name=""):
        self.rom_data = rom_data
        self.offset = struct_offset
        self.name = name

        header = rom_data[struct_offset : struct_offset + TILESET_RECORD_SIZE]
        is_comp, is_sec, pad, t_ptr, p_ptr, m_ptr, a_ptr, cb_ptr = struct.unpack("<BBHIIIII", header)
        self.is_compressed = bool(is_comp)
        self.is_secondary = bool(is_sec)
        self.tiles_offset = t_ptr & 0x1FFFFFF
        self.pal_offset = p_ptr & 0x1FFFFFF
        self.meta_offset = m_ptr & 0x1FFFFFF
        self.attr_offset = a_ptr & 0x1FFFFFF

        # Decode tiles
        if self.is_compressed:
            self.tiles_raw = lz77_decompress(rom_data, self.tiles_offset)
        else:
            # Uncompressed tiles: read up to 512 8x8 tiles (16,384 bytes)
            self.tiles_raw = rom_data[self.tiles_offset : self.tiles_offset + 16384]

        # Decode palettes (16 palettes x 16 colors)
        self.palettes = []
        for p in range(16):
            pal_bytes = rom_data[self.pal_offset + p * 32 : self.pal_offset + (p + 1) * 32]
            colors = [bgr555_to_rgb(c) for c in struct.unpack("<16H", pal_bytes)]
            self.palettes.append(colors)

        # Number of metatiles
        # Attributes immediately follow metatiles in memory
        if self.attr_offset > self.meta_offset:
            self.num_metatiles = (self.attr_offset - self.meta_offset) // 16
        else:
            self.num_metatiles = 512 if not self.is_secondary else 350

        # Read metatiles
        self.metatiles_raw = rom_data[self.meta_offset : self.meta_offset + self.num_metatiles * 16]
        # Read attributes (u16 per metatile)
        self.attributes = struct.unpack(
            f"<{self.num_metatiles}H",
            rom_data[self.attr_offset : self.attr_offset + self.num_metatiles * 2],
        )


def decode_8x8_tile_pixels(tiles_data, tile_index, xflip=False, yflip=False):
    byte_offset = tile_index * 32
    if byte_offset + 32 > len(tiles_data):
        return [[0] * 8 for _ in range(8)]
    tile_bytes = tiles_data[byte_offset : byte_offset + 32]
    rows = []
    for r in range(8):
        row_b = tile_bytes[r * 4 : (r + 1) * 4]
        row_px = []
        for b in row_b:
            row_px.append(b & 0x0F)
            row_px.append((b >> 4) & 0x0F)
        if xflip:
            row_px.reverse()
        rows.append(row_px)
    if yflip:
        rows.reverse()
    return rows


def render_metatile_canvas(meta_index, primary_ts, secondary_ts=None):
    if meta_index < 512:
        ts = primary_ts
        local_idx = meta_index
    else:
        ts = secondary_ts if secondary_ts is not None else primary_ts
        local_idx = meta_index - 512

    if local_idx >= ts.num_metatiles:
        return [[(0, 0, 0)] * 16 for _ in range(16)]

    off = local_idx * 16
    words = struct.unpack("<8H", ts.metatiles_raw[off : off + 16])

    canvas = [[(0, 0, 0) for _ in range(16)] for _ in range(16)]

    # Layer 0 (bottom), Layer 1 (top)
    for layer in (0, 1):
        base = layer * 4
        for sub, (dx, dy) in enumerate([(0, 0), (8, 0), (0, 8), (8, 8)]):
            w = words[base + sub]
            tile_idx = w & 0x3FF
            xflip = bool((w >> 10) & 1)
            yflip = bool((w >> 11) & 1)
            pal_idx = (w >> 12) & 0x0F

            if tile_idx < 512:
                tile_src = primary_ts.tiles_raw
                sub_idx = tile_idx
            else:
                tile_src = secondary_ts.tiles_raw if secondary_ts else primary_ts.tiles_raw
                sub_idx = tile_idx - 512

            sub_pixels = decode_8x8_tile_pixels(tile_src, sub_idx, xflip, yflip)

            pal_src = secondary_ts.palettes if (secondary_ts and pal_idx >= 6) else primary_ts.palettes
            palette = pal_src[pal_idx]

            for py in range(8):
                for px in range(8):
                    c_idx = sub_pixels[py][px]
                    if layer == 0:
                        canvas[dy + py][dx + px] = palette[c_idx]
                    else:
                        if c_idx != 0:
                            canvas[dy + py][dx + px] = palette[c_idx]

    return canvas


def scale_2x_rgb(canvas_16):
    out = [[(0, 0, 0) for _ in range(32)] for _ in range(32)]
    for y in range(16):
        for x in range(16):
            c = canvas_16[y][x]
            out[y * 2][x * 2] = c
            out[y * 2][x * 2 + 1] = c
            out[y * 2 + 1][x * 2] = c
            out[y * 2 + 1][x * 2 + 1] = c
    return out


def write_png_file(filepath, width, height, rgb_pixels):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0: none
        for x in range(width):
            r, g, b = rgb_pixels[y][x]
            raw.append(r)
            raw.append(g)
            raw.append(b)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 6)
    png_bytes = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(png_bytes)


def generate_contact_sheet(out_path, primary_ts, secondary_ts=None, cols_per_row=16):
    ts = secondary_ts if secondary_ts else primary_ts
    total_metas = ts.num_metatiles
    start_meta = 512 if secondary_ts else 0

    num_rows = (total_metas + cols_per_row - 1) // cols_per_row
    sheet_w = cols_per_row * 32
    sheet_h = num_rows * 32

    sheet_pixels = [[(15, 18, 25) for _ in range(sheet_w)] for _ in range(sheet_h)]

    for idx in range(total_metas):
        meta_id = start_meta + idx
        canvas_16 = render_metatile_canvas(meta_id, primary_ts, secondary_ts)
        canvas_32 = scale_2x_rgb(canvas_16)

        tile_col = idx % cols_per_row
        tile_row = idx // cols_per_row

        ox = tile_col * 32
        oy = tile_row * 32

        for y in range(32):
            for x in range(32):
                sheet_pixels[oy + y][ox + x] = canvas_32[y][x]

    write_png_file(out_path, sheet_w, sheet_h, sheet_pixels)
    return sheet_w, sheet_h, total_metas


def find_fixture_cells_bin():
    candidates = [
        os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Tenth Spring/test/fixture_cells.bin"),
        os.path.expanduser("~/.local/share/godot/app_userdata/Tenth Spring/test/fixture_cells.bin"),
        os.path.join(find_repo_root(), "game", "tests", "testdata", "fixture_cells.bin"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def generate_synthetic_preview(out_path, primary_ts, sec_petalburg):
    bin_path = find_fixture_cells_bin()
    if not bin_path or not os.path.exists(bin_path):
        raise RuntimeError(f"Fixture cells dump not found. Checked: {bin_path}")

    with open(bin_path, "rb") as f:
        data = f.read()

    if len(data) < 12288:
        raise RuntimeError(f"fixture_cells.bin is incomplete: expected 12288 bytes, got {len(data)}")

    # 4 cells: (4, 4), (4, 5), (5, 4), (5, 5)
    # Each cell is 32x32 tiles, row-major (row 0 is North edge).
    # 2x2 grid of cells on screen:
    # Top-Left: (4, 5)
    # Top-Right: (5, 5)
    # Bottom-Left: (4, 4)
    # Bottom-Right: (5, 4)
    cell_4_4 = data[0:3072]
    cell_4_5 = data[3072:6144]
    cell_5_4 = data[6144:9216]
    cell_5_5 = data[9216:12288]

    cells_grid = [
        [cell_4_5, cell_5_5],  # top row (cy = 5)
        [cell_4_4, cell_5_4],  # bottom row (cy = 4)
    ]

    total_tiles_w = 64
    total_tiles_h = 64
    img_w = total_tiles_w * 32
    img_h = total_tiles_h * 32

    preview_pixels = [[(0, 0, 0) for _ in range(img_w)] for _ in range(img_h)]

    # Load mapping from emerald_tile_map.json if available, or default vocabulary
    map_config_path = os.path.join(find_repo_root(), "game", "config", "emerald_tile_map.json")
    mapping = None
    if os.path.exists(map_config_path):
        with open(map_config_path, "r") as mf:
            mapping = json.load(mf)

    # Pre-render cache for metatiles used
    rendered_cache = {}

    def get_metatile_canvas_32(m_id):
        if m_id not in rendered_cache:
            c16 = render_metatile_canvas(m_id, primary_ts, sec_petalburg)
            rendered_cache[m_id] = scale_2x_rgb(c16)
        return rendered_cache[m_id]

    def map_tile_to_metatile(cls, var, msk):
        if mapping and "tile_map" in mapping:
            s_cls = str(cls)
            s_var = str(var)
            s_msk = str(msk)
            tm = mapping["tile_map"]
            if s_cls in tm:
                v_map = tm[s_cls]
                if s_var in v_map:
                    m_map = v_map[s_var]
                    if s_msk in m_map:
                        return m_map[s_msk]["metatile"]
                    elif "0" in m_map:
                        return m_map["0"]["metatile"]
                elif "0" in v_map:
                    m_map = v_map["0"]
                    if s_msk in m_map:
                        return m_map[s_msk]["metatile"]
                    elif "0" in m_map:
                        return m_map["0"]["metatile"]

        # Default fallback mappings
        if cls == 1:  # GRASS
            return [1, 2, 3, 1][var % 4]
        elif cls == 2:  # TALL_GRASS
            return 13
        elif cls == 3:  # TREE
            return 468
        elif cls == 4:  # WATER
            return 44
        elif cls == 5:  # SAND
            return 76
        elif cls == 6:  # MARSH
            return 76
        elif cls == 7:  # PATH
            return 281 if var == 0 else 282  # overgrown
        elif cls == 8:  # ROAD
            return 288 if var == 0 else 290  # cracked
        elif cls == 9:  # RAIL
            return 290
        elif cls == 10:  # BRIDGE
            return 288
        elif cls == 11:  # PLAZA
            return 288 if var == 0 else 289
        elif cls == 12:  # ROOF
            if var >= 16:  # ruined roof
                return 529 if var % 2 == 0 else 537
            return 521  # standing roof
        elif cls == 13:  # WALL
            if var >= 16:  # ruined wall
                return 570 if var % 2 == 0 else 568
            return 562 if (var & 8) else 546  # window vs plain
        elif cls == 14:  # DOOR
            return 568 if var >= 16 else 560
        elif cls == 15:  # FENCE
            return 330
        elif cls == 16:  # FLOWERS
            return 14
        elif cls == 17:  # GRAVE
            return 33
        elif cls == 18:  # SIGN
            return 33
        elif cls == 19:  # CROP
            return 85
        elif cls == 20:  # RUBBLE
            return 116 if var == 0 else 124
        return 1

    for cell_row_idx in range(2):
        for cell_col_idx in range(2):
            cell_buf = cells_grid[cell_row_idx][cell_col_idx]
            for r in range(32):
                for c in range(32):
                    tile_idx = (r * 32 + c) * 3
                    cls = cell_buf[tile_idx]
                    var = cell_buf[tile_idx + 1]
                    msk = cell_buf[tile_idx + 2]

                    meta_id = map_tile_to_metatile(cls, var, msk)
                    canvas_32 = get_metatile_canvas_32(meta_id)

                    gx = (cell_col_idx * 32 + c) * 32
                    gy = (cell_row_idx * 32 + r) * 32

                    for py in range(32):
                        for px in range(32):
                            preview_pixels[gy + py][gx + px] = canvas_32[py][px]

    write_png_file(out_path, img_w, img_h, preview_pixels)
    return img_w, img_h


def run_spike():
    print("=== Tenth Spring — Pokémon Emerald Tile Spike (Item 12) ===")
    rom_data = check_preconditions()
    print("PASS: ROM preconditions verified (Header=BPEE, SHA-1 verified, path outside repo)")

    primary_ts = EmeraldTileset(rom_data, PRIMARY_TILESET_OFFSET, is_secondary=False, name="General")
    print(f"PASS: Primary tileset decoded ({primary_ts.num_metatiles} metatiles, tiles offset {hex(primary_ts.tiles_offset)})")

    out_dir = os.path.expanduser("~/.tenth_spring_rom_spike/emerald")
    os.makedirs(out_dir, exist_ok=True)

    # 1. Primary contact sheet
    p_path = os.path.join(out_dir, "primary_general.png")
    pw, ph, p_count = generate_contact_sheet(p_path, primary_ts)
    print(f"PASS: Contact sheet saved: primary_general.png ({pw}x{ph}, {p_count} metatiles)")

    # 2. Secondary contact sheets
    loaded_secondaries = {}
    for name, sec_idx in FEATURED_SECONDARY_TILESETS.items():
        sec_offset = PRIMARY_TILESET_OFFSET + sec_idx * TILESET_RECORD_SIZE
        sec_ts = EmeraldTileset(rom_data, sec_offset, is_secondary=True, name=name)
        loaded_secondaries[name] = sec_ts
        s_path = os.path.join(out_dir, f"{name}.png")
        sw, sh, s_count = generate_contact_sheet(s_path, primary_ts, sec_ts)
        print(f"PASS: Contact sheet saved: {name}.png ({sw}x{sh}, {s_count} metatiles)")

    # 3. Synthetic preview
    prev_path = os.path.join(out_dir, "preview.png")
    pw, ph = generate_synthetic_preview(prev_path, primary_ts, loaded_secondaries["sec01_petalburg"])
    print(f"PASS: Synthetic preview saved: preview.png ({pw}x{ph})")

    print("\nAll outputs written outside repository to:")
    print(f"  {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(run_spike())
