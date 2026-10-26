#!/usr/bin/env python3
"""
Tenth Spring — Emerald (Game Boy Advance) tile spike (agent guide Items 12 and 12b)
Contract: docs/agent_execution_guide.md §3 (Item 12b)
          docs/design_rom_asset_pipeline.md §4, §5, §7
          docs/design_art_direction.md §1a

Reads and decodes the overworld tilesets of the player's own Emerald dump, renders
labelled contact sheets, the mapping table laid out like the importer's atlas
(table_ground.png, table_buildings.png), a sheet of the building compositions, and a
preview of synthetic fixture cells, and offers the evidence helpers (behaviour bytes,
pixel tests, layout statistics) that the mapping builder and the checks use.

Usage (under python3 -I, through tools/memguard.py, step rom_spike_gba):
    rom_spike.py [sheets] [compositions] [preview]     default: all three

Nothing taken from the ROM is stored in this file: only offsets, sizes, and numbers.
Every image is written outside the repository, to ~/.tenth_spring_rom_spike/emerald/.
Pure Python 3 standard library; run it under python3 -I.
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
MAP_BANK_TABLE_OFFSET = 0x486578
TILESET_RECORD_SIZE = 24
TILESET_TABLE_COUNT = 58

PRIMARY_METATILE_COUNT = 512
PRIMARY_PALETTE_COUNT = 6

# Secondary tilesets loaded by default, by index in the tileset array. The sheets and the tests
# load whichever tilesets the mapping table names.
FEATURED_SECONDARY_INDICES = ()

OUT_DIR_DISPLAY = "~/.tenth_spring_rom_spike/emerald"
OUT_DIR = os.path.expanduser(OUT_DIR_DISPLAY)


def sec_key(index):
    """Neutral key of a secondary tileset: its index in the tileset array."""
    return "sec%02d" % index


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
        raise RuntimeError("ROM file does not exist")

    real_rom_path = os.path.realpath(rom_path)
    real_repo_root = os.path.realpath(find_repo_root())
    if real_rom_path.startswith(real_repo_root):
        raise RuntimeError("ROM file cannot be located inside the repository")

    with open(rom_path, "rb") as f:
        rom_data = f.read()

    if len(rom_data) < 0xC0:
        raise RuntimeError("File too small to be a GBA ROM")
    header_code = rom_data[0xAC:0xB0]
    if header_code != EXPECTED_HEADER:
        raise RuntimeError("Header code mismatch: expected %s, got %r" % (EXPECTED_HEADER.decode(), header_code))
    actual_sha1 = hashlib.sha1(rom_data).hexdigest().lower()
    if actual_sha1 != EXPECTED_SHA1:
        raise RuntimeError("SHA-1 mismatch: expected %s, got %s" % (EXPECTED_SHA1, actual_sha1))
    return rom_data


# ---------------------------------------------------------------------------
# Decoding
# ---------------------------------------------------------------------------

def lz77_decompress(data, offset):
    magic = data[offset]
    if magic != 0x10:
        raise ValueError("Expected LZ77 type 0x10 magic byte, got %s" % hex(magic))
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
        is_comp, is_sec, _pad, t_ptr, p_ptr, m_ptr, a_ptr, _cb_ptr = struct.unpack("<BBHIIIII", header)
        self.is_compressed = bool(is_comp)
        self.is_secondary = bool(is_sec)
        self.tiles_offset = t_ptr & 0x1FFFFFF
        self.pal_offset = p_ptr & 0x1FFFFFF
        self.meta_offset = m_ptr & 0x1FFFFFF
        self.attr_offset = a_ptr & 0x1FFFFFF

        if self.is_compressed:
            self.tiles_raw = lz77_decompress(rom_data, self.tiles_offset)
        else:
            self.tiles_raw = rom_data[self.tiles_offset : self.tiles_offset + 16384]

        self.palettes = []
        for p in range(16):
            pal_bytes = rom_data[self.pal_offset + p * 32 : self.pal_offset + (p + 1) * 32]
            self.palettes.append([bgr555_to_rgb(c) for c in struct.unpack("<16H", pal_bytes)])

        # The attribute table follows the metatile table, 2 bytes per metatile.
        if self.attr_offset > self.meta_offset:
            self.num_metatiles = (self.attr_offset - self.meta_offset) // 16
        else:
            self.num_metatiles = PRIMARY_METATILE_COUNT if not self.is_secondary else 350

        self.metatiles_raw = rom_data[self.meta_offset : self.meta_offset + self.num_metatiles * 16]
        self.attributes = struct.unpack(
            "<%dH" % self.num_metatiles,
            rom_data[self.attr_offset : self.attr_offset + self.num_metatiles * 2],
        )

    def behaviour(self, local_index):
        """The behaviour byte: bits 0-7 of the metatile's attribute word."""
        return self.attributes[local_index] & 0xFF


def load_tilesets(rom_data, indices=FEATURED_SECONDARY_INDICES):
    """Returns {"primary": ts, "sec01": ts, ...} for the featured indices."""
    out = {"primary": EmeraldTileset(rom_data, PRIMARY_TILESET_OFFSET, is_secondary=False, name="primary")}
    for idx in indices:
        off = PRIMARY_TILESET_OFFSET + idx * TILESET_RECORD_SIZE
        out[sec_key(idx)] = EmeraldTileset(rom_data, off, is_secondary=True, name=sec_key(idx))
    return out


def decode_8x8_tile_pixels(tiles_data, tile_index, xflip=False, yflip=False):
    byte_offset = tile_index * 32
    if byte_offset + 32 > len(tiles_data):
        return [[0] * 8 for _ in range(8)]
    tile_bytes = tiles_data[byte_offset : byte_offset + 32]
    rows = []
    for r in range(8):
        row_px = []
        for b in tile_bytes[r * 4 : (r + 1) * 4]:
            row_px.append(b & 0x0F)
            row_px.append((b >> 4) & 0x0F)
        if xflip:
            row_px.reverse()
        rows.append(row_px)
    if yflip:
        rows.reverse()
    return rows


def render_metatile_canvas(meta_index, primary_ts, secondary_ts=None):
    """16x16 canvas of (r, g, b) tuples: the bottom layer, then the top layer over it."""
    if meta_index < PRIMARY_METATILE_COUNT:
        ts = primary_ts
        local_idx = meta_index
    else:
        ts = secondary_ts if secondary_ts is not None else primary_ts
        local_idx = meta_index - PRIMARY_METATILE_COUNT

    if local_idx >= ts.num_metatiles:
        return [[(0, 0, 0)] * 16 for _ in range(16)]

    off = local_idx * 16
    words = struct.unpack("<8H", ts.metatiles_raw[off : off + 16])
    canvas = [[(0, 0, 0) for _ in range(16)] for _ in range(16)]

    for layer in (0, 1):
        base = layer * 4
        for sub, (dx, dy) in enumerate([(0, 0), (8, 0), (0, 8), (8, 8)]):
            w = words[base + sub]
            tile_idx = w & 0x3FF
            xflip = bool((w >> 10) & 1)
            yflip = bool((w >> 11) & 1)
            pal_idx = (w >> 12) & 0x0F

            if tile_idx < PRIMARY_METATILE_COUNT:
                tile_src = primary_ts.tiles_raw
                sub_idx = tile_idx
            else:
                tile_src = secondary_ts.tiles_raw if secondary_ts else primary_ts.tiles_raw
                sub_idx = tile_idx - PRIMARY_METATILE_COUNT

            sub_pixels = decode_8x8_tile_pixels(tile_src, sub_idx, xflip, yflip)
            pal_src = secondary_ts.palettes if (secondary_ts and pal_idx >= PRIMARY_PALETTE_COUNT) else primary_ts.palettes
            palette = pal_src[pal_idx]

            for py in range(8):
                for px in range(8):
                    c_idx = sub_pixels[py][px]
                    if layer == 0 or c_idx != 0:
                        canvas[dy + py][dx + px] = palette[c_idx]
    return canvas


def render_entry(tilesets, meta_id, tileset_key="primary"):
    """Renders a global metatile id of the named tileset (None means the primary)."""
    primary = tilesets["primary"]
    secondary = tilesets.get(tileset_key) if tileset_key not in (None, "primary") else None
    return render_metatile_canvas(meta_id, primary, secondary)


def canvas_pixels(canvas_16):
    return [canvas_16[y][x] for y in range(16) for x in range(16)]


def colour_set(canvas_16):
    return set(canvas_pixels(canvas_16))


# ---------------------------------------------------------------------------
# Evidence helpers: behaviour bytes, pixel tests (numbers and colours only)
# ---------------------------------------------------------------------------

# Behaviour bytes (bits 0-7 of the attribute word) the mapping's evidence rules name.
TALL_GRASS_BEHAVIOURS = (0x02, 0x03)
# Standing water only: 0x13 (waterfall) is moving water, a different thing.
WATER_BEHAVIOURS = (0x10, 0x11, 0x12, 0x15, 0x16, 0x17)

SIDE_NAMES = ("N", "E", "S", "W")  # mask bits 0..3, as in slice-2 plan §3
SHORE_BAND_DEPTH = 4  # pixels deep, of a metatile's 16
SHORE_BAND_MARGIN = 4  # skip this many pixels at each end of a side, so corners don't count


def resolve_tileset(tilesets, meta_id, key):
    """(tileset, local index) holding a global metatile id for the named tileset key."""
    primary = tilesets["primary"]
    if meta_id < PRIMARY_METATILE_COUNT:
        return primary, meta_id
    secondary = tilesets.get(key) if key not in (None, "primary") else None
    if secondary is None:
        return None, None
    return secondary, meta_id - PRIMARY_METATILE_COUNT


def metatile_words(tilesets, meta_id, key="primary"):
    ts, local = resolve_tileset(tilesets, meta_id, key)
    if ts is None or local >= ts.num_metatiles:
        return None
    return struct.unpack("<8H", ts.metatiles_raw[local * 16 : local * 16 + 16])


def behaviour_at(tilesets, meta_id, key="primary"):
    """Behaviour byte of a global metatile id, or None when the id is outside the tileset."""
    ts, local = resolve_tileset(tilesets, meta_id, key)
    if ts is None or local >= ts.num_metatiles:
        return None
    return ts.behaviour(local)


def top_layer_blank(tilesets, meta_id, key="primary"):
    """True when the metatile's top layer draws nothing: it is only a ground piece, with no
    object (tree top, sign, roof overhang) painted over it."""
    words = metatile_words(tilesets, meta_id, key)
    if words is None:
        return False
    primary = tilesets["primary"]
    secondary = tilesets.get(key) if key not in (None, "primary") else None
    for w in words[4:8]:
        tile_idx = w & 0x3FF
        if tile_idx < PRIMARY_METATILE_COUNT:
            src, sub = primary.tiles_raw, tile_idx
        else:
            src, sub = (secondary.tiles_raw if secondary else primary.tiles_raw), tile_idx - PRIMARY_METATILE_COUNT
        for row in decode_8x8_tile_pixels(src, sub):
            if any(row):
                return False
    return True


def is_water_pixel(rgb):
    """A pixel counts as water-coloured when blue is its strongest channel."""
    r, g, b = rgb
    return b > r and b > g


def share(canvas_16, predicate):
    """Fraction of a metatile's 256 pixels satisfying predicate(rgb)."""
    px = [canvas_16[y][x] for y in range(16) for x in range(16)]
    return sum(1 for p in px if predicate(p)) / 256.0


def colour_share(canvas_16, colours):
    """Fraction of a metatile's pixels whose colour is in the given set."""
    return share(canvas_16, lambda p: p in colours)


def side_pixels(canvas_16, side, depth=SHORE_BAND_DEPTH, margin=SHORE_BAND_MARGIN):
    """The pixels of the band along one side of a metatile, excluding the corner ends."""
    lo, hi = margin, 16 - margin
    out = []
    for d in range(depth):
        for t in range(lo, hi):
            if side == "N":
                out.append(canvas_16[d][t])
            elif side == "S":
                out.append(canvas_16[15 - d][t])
            elif side == "W":
                out.append(canvas_16[t][d])
            else:
                out.append(canvas_16[t][15 - d])
    return out


def side_water_share(canvas_16, side):
    px = side_pixels(canvas_16, side)
    return sum(1 for p in px if is_water_pixel(p)) / float(len(px))


def scale_2x_rows(canvas_16):
    """A 16x16 canvas of tuples to 32 rows of 96 RGB bytes (2x nearest neighbour)."""
    rows = []
    for y in range(16):
        line = bytearray()
        for x in range(16):
            line.extend(bytes(canvas_16[y][x]) * 2)
        rows.append(bytes(line))
        rows.append(bytes(line))
    return rows


# ---------------------------------------------------------------------------
# Map layouts (statistics only: nothing but metatile numbers is ever used)
# ---------------------------------------------------------------------------

def _is_rom_ptr(value):
    return 0x08000000 <= value < 0x09000000


def iter_map_layouts(rom_data):
    """Yields dicts {offset, w, h, grid, primary, secondary} for each distinct layout whose
    tilesets are entries of the tileset array. The grid is a list of rows of metatile ids."""
    known = {PRIMARY_TILESET_OFFSET + i * TILESET_RECORD_SIZE for i in range(TILESET_TABLE_COUNT)}
    seen = set()
    for bank in range(40):
        raw = rom_data[MAP_BANK_TABLE_OFFSET + bank * 4 : MAP_BANK_TABLE_OFFSET + bank * 4 + 4]
        if len(raw) < 4:
            break
        bank_ptr = struct.unpack("<I", raw)[0]
        if not _is_rom_ptr(bank_ptr):
            break
        bank_off = bank_ptr & 0x1FFFFFF
        for m in range(130):
            hdr_ptr = struct.unpack("<I", rom_data[bank_off + m * 4 : bank_off + m * 4 + 4])[0]
            if not _is_rom_ptr(hdr_ptr):
                break
            hdr_off = hdr_ptr & 0x1FFFFFF
            layout_ptr = struct.unpack("<I", rom_data[hdr_off : hdr_off + 4])[0]
            if not _is_rom_ptr(layout_ptr):
                continue
            lo = layout_ptr & 0x1FFFFFF
            if lo in seen:
                continue
            w, h, _border, map_ptr, p_ptr, s_ptr = struct.unpack("<IIIIII", rom_data[lo : lo + 24])
            if not (1 <= w <= 512 and 1 <= h <= 512):
                continue
            if not (_is_rom_ptr(map_ptr) and _is_rom_ptr(p_ptr) and _is_rom_ptr(s_ptr)):
                continue
            p_off, s_off = p_ptr & 0x1FFFFFF, s_ptr & 0x1FFFFFF
            if p_off not in known or s_off not in known:
                continue
            mo = map_ptr & 0x1FFFFFF
            if mo + w * h * 2 > len(rom_data):
                continue
            seen.add(lo)
            words = struct.unpack("<%dH" % (w * h), rom_data[mo : mo + w * h * 2])
            grid = [[words[y * w + x] & 0x3FF for x in range(w)] for y in range(h)]
            yield {
                "offset": lo, "w": w, "h": h, "grid": grid, "primary": p_off, "secondary": s_off,
                "secondary_index": (s_off - PRIMARY_TILESET_OFFSET) // TILESET_RECORD_SIZE,
            }


def gkey(lay, meta_id):
    """A metatile id made unambiguous across layouts: primary ids (< 512) stay plain ints,
    secondary ids become (secondary_index, id)."""
    if meta_id < PRIMARY_METATILE_COUNT:
        return meta_id
    return (lay["secondary_index"], meta_id)


def neighbour_stats(layouts, family_of, wanted):
    """For every cell of a layout that uses the main primary tileset whose gkey is in `wanted`,
    computes the 4-neighbour mask (bit0 N, bit1 E, bit2 S, bit3 W; a bit is set when
    family_of(gkey of that neighbour) is true) and counts the metatile per mask.
    Returns {mask: {gkey: count}}. Statistics only: nothing but metatile numbers is kept."""
    stats = {}
    for lay in layouts:
        if lay["primary"] != PRIMARY_TILESET_OFFSET:
            continue
        grid, w, h = lay["grid"], lay["w"], lay["h"]
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                key = gkey(lay, grid[y][x])
                if key not in wanted:
                    continue
                mask = 0
                if family_of(gkey(lay, grid[y - 1][x])):
                    mask |= 1
                if family_of(gkey(lay, grid[y][x + 1])):
                    mask |= 2
                if family_of(gkey(lay, grid[y + 1][x])):
                    mask |= 4
                if family_of(gkey(lay, grid[y][x - 1])):
                    mask |= 8
                by_key = stats.setdefault(mask, {})
                by_key[key] = by_key.get(key, 0) + 1
    return stats


def neighbour_counts(layouts, wanted):
    """For every cell of a main primary layout whose gkey is in `wanted`, counts which
    metatile sits on each side. Returns {gkey: {"N": {gkey: n}, "E": ..., "S": ..., "W": ...}}."""
    out = {}
    for lay in layouts:
        if lay["primary"] != PRIMARY_TILESET_OFFSET:
            continue
        grid, w, h = lay["grid"], lay["w"], lay["h"]
        for y in range(h):
            for x in range(w):
                key = gkey(lay, grid[y][x])
                if key not in wanted:
                    continue
                sides = out.setdefault(key, {"N": {}, "E": {}, "S": {}, "W": {}})
                for side, (dx, dy) in (("N", (0, -1)), ("E", (1, 0)), ("S", (0, 1)), ("W", (-1, 0))):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        nk = gkey(lay, grid[ny][nx])
                        sides[side][nk] = sides[side].get(nk, 0) + 1
    return out


def frequency(layouts):
    """How often each gkey occurs over all main primary layouts: {gkey: count}."""
    counts = {}
    for lay in layouts:
        if lay["primary"] != PRIMARY_TILESET_OFFSET:
            continue
        for row in lay["grid"]:
            for mid in row:
                key = gkey(lay, mid)
                counts[key] = counts.get(key, 0) + 1
    return counts


# ---------------------------------------------------------------------------
# PNG reading and writing (stdlib only)
# ---------------------------------------------------------------------------

def _chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png_rows(filepath, width, height, rows):
    """rows: a list of `height` byte strings, each 3 * width RGB bytes."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rows[y])
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + _chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(png)


def read_png_rgba(path):
    """Reads an 8-bit RGBA non-interlaced PNG. Returns (w, h, rows) with rows of RGBA bytes."""
    with open(path, "rb") as f:
        data = f.read()
    pos = 8
    idat = b""
    w = h = 0
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos : pos + 4])
        tag = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, bit_depth, colour_type, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
            if bit_depth != 8 or colour_type != 6 or interlace != 0:
                raise ValueError("expected an 8-bit RGBA non-interlaced PNG")
        elif tag == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    bpp = 4
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    p = 0
    for _y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1 : p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, rows


# ---------------------------------------------------------------------------
# Labelled contact sheets (original 3x5 pixel digits)
# ---------------------------------------------------------------------------

_DIGITS = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "001", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
}
LABEL_H = 12
CELL_W = 32
CELL_H = 32 + LABEL_H


def draw_number(canvas_rows, x0, y0, number, colour=(255, 255, 255), scale=2):
    text = str(number)
    cx = x0
    for ch in text:
        glyph = _DIGITS[ch]
        for gy in range(5):
            for gx in range(3):
                if glyph[gy][gx] == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            px = cx + gx * scale + sx
                            py = y0 + gy * scale + sy
                            canvas_rows[py][px * 3 : px * 3 + 3] = bytes(colour)
        cx += 4 * scale


def number_width(number, scale=2):
    return len(str(number)) * 4 * scale - scale


def _blit32(canvas_rows, ox, oy, rows32):
    for y in range(32):
        canvas_rows[oy + y][ox * 3 : (ox + 32) * 3] = rows32[y]


def generate_labelled_sheet(out_path, tilesets, key, first=None, last=None, cols=16):
    """A contact sheet of metatiles with each one's global id drawn under it.
    key is "primary" or a secondary key; secondary ids start at 512."""
    primary = tilesets["primary"]
    ts = tilesets[key]
    base = 0 if key == "primary" else PRIMARY_METATILE_COUNT
    lo = 0 if first is None else first
    hi = ts.num_metatiles if last is None else min(last, ts.num_metatiles)
    count = hi - lo
    rows_n = (count + cols - 1) // cols
    width, height = cols * CELL_W, rows_n * CELL_H
    canvas = [bytearray(bytes((15, 18, 25)) * width) for _ in range(height)]
    secondary = None if key == "primary" else ts
    for i in range(count):
        local = lo + i
        meta_id = base + local
        rows32 = scale_2x_rows(render_metatile_canvas(meta_id, primary, secondary))
        ox, oy = (i % cols) * CELL_W, (i // cols) * CELL_H
        _blit32(canvas, ox, oy, rows32)
        w = number_width(meta_id)
        draw_number(canvas, ox + (CELL_W - w) // 2, oy + 32 + 1, meta_id)
    write_png_rows(out_path, width, height, canvas)
    return width, height, count


# ---------------------------------------------------------------------------
# Preview of synthetic fixture cells
# ---------------------------------------------------------------------------

def find_fixture_cells_bin():
    candidates = [
        os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Tenth Spring/test/fixture_cells.bin"),
        os.path.expanduser("~/.local/share/godot/app_userdata/Tenth Spring/test/fixture_cells.bin"),
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


class PlaceholderAtlas:
    """The code-drawn placeholder atlas the game keeps for every class listed in `gaps`."""

    def __init__(self):
        root = os.path.join(find_repo_root(), "game", "assets", "tiles")
        with open(os.path.join(root, "placeholder_v1.json")) as f:
            meta = json.load(f)
        self.rows = {}
        self.masked = {}
        for r in meta["rows"]:
            self.rows[(r["class"], r["variant"])] = (r["row"], r["masked"])
            self.masked[r["class"]] = r["masked"]
        _w, _h, self.pixels = read_png_rgba(os.path.join(root, "placeholder_v1.png"))

    def tile_rows32(self, cls, var, mask):
        key = (cls, var)
        if key not in self.rows:
            key = (cls, 0)
        if key not in self.rows:
            return None
        row, masked = self.rows[key]
        col = mask if masked else 0
        out = []
        for y in range(32):
            line = self.pixels[row * 32 + y]
            seg = line[col * 32 * 4 : (col + 1) * 32 * 4]
            rgb = bytearray()
            for i in range(0, len(seg), 4):
                rgb.extend(seg[i : i + 3])
            out.append(bytes(rgb))
        return out


def lookup_entry(tile_map, cls, var, mask):
    """tile_map[class][variant][mask] -> entry. The mask key "*" matches any mask."""
    by_var = tile_map.get(str(cls))
    if by_var is None:
        return None
    by_mask = by_var.get(str(var))
    if by_mask is None:
        return None
    if str(mask) in by_mask:
        return by_mask[str(mask)]
    return by_mask.get("*")


def load_mapping():
    path = os.path.join(find_repo_root(), "game", "config", "emerald_tile_map.json")
    with open(path) as f:
        return json.load(f)


def tileset_indices_of(mapping):
    """Secondary tileset indices the mapping's `tilesets` block names."""
    return tuple(sorted(i for k, i in mapping.get("tilesets", {}).items() if k != "primary"))


def gap_rules(mapping):
    """Reads the `gaps` block into rules (classes, variants or None, masks or None). A gap names
    classes and, optionally, the variants and masks it covers; leaving one out means all of them."""
    rules = []
    for gap in mapping.get("gaps", []):
        if not isinstance(gap, dict) or not gap.get("classes"):  # a pass-22 table lists bare strings
            continue
        rules.append((
            set(gap["classes"]),
            set(gap["variants"]) if "variants" in gap else None,
            set(gap["masks"]) if "masks" in gap else None,
        ))
    return rules


def in_gap(rules, cls, var, mask):
    """True when (class, variant, mask) is listed as something Emerald lacks."""
    for classes, variants, masks in rules:
        if cls in classes and (variants is None or var in variants) and (masks is None or mask in masks):
            return True
    return False


def generate_synthetic_preview(out_path, tilesets, mapping=None):
    bin_path = find_fixture_cells_bin()
    if not bin_path:
        raise RuntimeError("Fixture cells dump not found (run test_runner.py --only tile_synth2_test first)")
    with open(bin_path, "rb") as f:
        data = f.read()
    if len(data) < 12288:
        raise RuntimeError("fixture_cells.bin is incomplete: expected 12288 bytes, got %d" % len(data))

    cell_4_4, cell_4_5, cell_5_4, cell_5_5 = (data[i * 3072 : (i + 1) * 3072] for i in range(4))
    cells_grid = [[cell_4_5, cell_5_5], [cell_4_4, cell_5_4]]

    mapping = mapping or load_mapping()
    gaps = gap_rules(mapping)
    placeholder = PlaceholderAtlas()
    cache = {}

    def tile_rows(cls, var, mask):
        is_gap = in_gap(gaps, cls, var, mask)
        entry = None if is_gap else lookup_entry(mapping["tile_map"], cls, var, mask)
        if entry is None:
            kind = "gap" if is_gap else "unmapped"
            return placeholder.tile_rows32(cls, var, mask), kind
        key = (entry["metatile"], entry.get("tileset", "primary"))
        if key not in cache:
            cache[key] = scale_2x_rows(render_entry(tilesets, key[0], key[1]))
        return cache[key], "emerald"

    side = 64
    width = height = side * 32
    canvas = [bytearray(width * 3) for _ in range(height)]
    used = {"emerald": 0, "gap": 0, "unmapped": 0}
    for cr in range(2):
        for cc in range(2):
            buf = cells_grid[cr][cc]
            for r in range(32):
                for c in range(32):
                    i = (r * 32 + c) * 3
                    rows32, kind = tile_rows(buf[i], buf[i + 1], buf[i + 2])
                    used[kind] += 1
                    if rows32 is None:
                        continue
                    ox, oy = (cc * 32 + c) * 32, (cr * 32 + r) * 32
                    _blit32(canvas, ox, oy, rows32)
    write_png_rows(out_path, width, height, canvas)
    return width, height, used


# ---------------------------------------------------------------------------
# Table sheets: the mapping laid out like the importer's atlas (class, variant) x mask
# ---------------------------------------------------------------------------

LABEL_COL_W = 64


def _placeholder_rows_for(placeholder, cls, var, mask):
    rows = placeholder.tile_rows32(cls, var, mask)
    if rows is None:
        return [bytes((42, 50, 66)) * 32 for _ in range(32)]
    return rows


def generate_table_sheet(out_path, tilesets, mapping, classes):
    """One row per (class, variant) of `classes`, 16 mask columns. Gap and unmapped cells show
    the placeholder tile. A label column on the left gives class and variant numbers."""
    placeholder = PlaceholderAtlas()
    gaps = gap_rules(mapping)
    cache = {}
    rows_spec = []
    for cls in classes:
        by_var = mapping["tile_map"].get(str(cls), {})
        variants = sorted(int(v) for v in by_var)
        if not variants:
            variants = sorted({v for (c, v) in placeholder.rows if c == cls}) or [0]
        for var in variants:
            rows_spec.append((cls, var))
    width = LABEL_COL_W + 16 * CELL_W
    height = len(rows_spec) * 32
    canvas = [bytearray(bytes((15, 18, 25)) * width) for _ in range(height)]
    for ri, (cls, var) in enumerate(rows_spec):
        oy = ri * 32
        draw_number(canvas, 2, oy + 4, cls, colour=(255, 220, 120))
        draw_number(canvas, 2, oy + 18, var, colour=(180, 220, 255))
        masked = placeholder.masked.get(cls, False)
        for mask in range(16 if masked else 1):
            if in_gap(gaps, cls, var, mask):
                rows32 = _placeholder_rows_for(placeholder, cls, var, mask)
            else:
                entry = lookup_entry(mapping["tile_map"], cls, var, mask)
                if entry is None:
                    rows32 = _placeholder_rows_for(placeholder, cls, var, mask)
                else:
                    key = (entry["metatile"], entry.get("tileset", "primary"))
                    if key not in cache:
                        cache[key] = scale_2x_rows(render_entry(tilesets, key[0], key[1]))
                    rows32 = cache[key]
            _blit32(canvas, LABEL_COL_W + mask * CELL_W, oy, rows32)
    write_png_rows(out_path, width, height, canvas)
    return width, height, len(rows_spec)


# ---------------------------------------------------------------------------
# Composition and building sheets
# ---------------------------------------------------------------------------

def _blit_grid(canvas, ox, oy, tilesets, metatiles, w, tileset_key):
    for i, mid in enumerate(metatiles):
        rows32 = scale_2x_rows(render_entry(tilesets, mid, tileset_key))
        _blit32(canvas, ox + (i % w) * 32, oy + (i // w) * 32, rows32)


def generate_composition_sheet(out_path, tilesets, mapping):
    """Every composition, drawn at 2x and numbered 1..n in the table's order, in rows of up to
    four. Returns (width, height, ordered ids)."""
    comps = mapping.get("compositions", {})
    ids = list(comps.keys())
    gap = 8
    cols = 4
    placed = []
    x = y = row_h = 0
    width = 0
    for cid in ids:
        c = comps[cid]
        cw, ch = c["w"] * 32, c["h"] * 32 + 14
        if x and x + cw > 1100:
            x = 0
            y += row_h + gap
            row_h = 0
        placed.append((cid, x, y))
        x += cw + gap
        row_h = max(row_h, ch)
        width = max(width, x)
    height = y + row_h + gap
    canvas = [bytearray(bytes((15, 18, 25)) * width) for _ in range(height)]
    for n, (cid, ox, oy) in enumerate(placed, start=1):
        c = comps[cid]
        _blit_grid(canvas, ox, oy + 14, tilesets, c["metatiles"], c["w"], c.get("tileset", "primary"))
        draw_number(canvas, ox + 2, oy + 2, n, colour=(255, 220, 120))
    write_png_rows(out_path, width, height, canvas)
    return width, height, ids


def generate_building_sheet(out_path, tilesets, mapping):
    """Each building template in each roof colour: one block per template, one column per colour."""
    blds = mapping.get("buildings", {})
    colour_ids = sorted({int(k) for b in blds.values() for k in b.get("roof_colors", {})})
    if not blds or not colour_ids:
        return 0, 0, 0
    gap = 8
    col_w = max(b["w"] for b in blds.values()) * 32 + gap
    row_hs = [b["h"] * 32 + 14 + gap for b in blds.values()]
    width = len(colour_ids) * col_w
    height = sum(row_hs)
    canvas = [bytearray(bytes((15, 18, 25)) * width) for _ in range(height)]
    oy = 0
    for (name, b), rh in zip(blds.items(), row_hs):
        for ci, cid in enumerate(colour_ids):
            spec = b.get("roof_colors", {}).get(str(cid))
            if spec is None:
                continue
            ox = ci * col_w
            _blit_grid(canvas, ox, oy + 14, tilesets, spec["metatiles"], b["w"], spec.get("tileset", "primary"))
            draw_number(canvas, ox + 2, oy + 2, cid, colour=(255, 220, 120))
        oy += rh
    write_png_rows(out_path, width, height, canvas)
    return width, height, len(blds)


def run_spike(steps=("sheets", "compositions", "preview")):
    print("=== Tenth Spring — Emerald tile spike (Items 12 and 12b) ===")
    rom_data = check_preconditions()
    print("PASS: ROM preconditions verified (header code, SHA-1, path outside the repo)")

    mapping = load_mapping()
    indices = tuple(sorted(set(FEATURED_SECONDARY_INDICES) | set(tileset_indices_of(mapping))))
    tilesets = load_tilesets(rom_data, indices)
    primary = tilesets["primary"]
    print("PASS: Primary tileset decoded (%d metatiles, tiles offset %s)" % (primary.num_metatiles, hex(primary.tiles_offset)))

    os.makedirs(OUT_DIR, exist_ok=True)
    # A full run removes every image this spike owns, so stale sheets from an earlier mapping
    # never sit beside the new ones (pass 22 left files named after places). A partial run
    # only overwrites what its steps write.
    if all(step in steps for step in ("sheets", "compositions", "preview")):
        for name in os.listdir(OUT_DIR):
            if name.endswith(".png"):
                os.remove(os.path.join(OUT_DIR, name))
    if "sheets" in steps:
        w, h, n = generate_labelled_sheet(os.path.join(OUT_DIR, "primary_labelled.png"), tilesets, "primary")
        print("PASS: Labelled contact sheet saved: primary_labelled.png (%dx%d, %d metatiles)" % (w, h, n))
        for idx in indices:
            key = sec_key(idx)
            w, h, n = generate_labelled_sheet(os.path.join(OUT_DIR, "%s_labelled.png" % key), tilesets, key)
            print("PASS: Labelled contact sheet saved: %s_labelled.png (%dx%d, %d metatiles)" % (key, w, h, n))

    if "compositions" in steps:
        ground = [c for c in range(0, 12)] + [c for c in range(15, 21)]
        w, h, n = generate_table_sheet(os.path.join(OUT_DIR, "table_ground.png"), tilesets, mapping, ground)
        print("PASS: Table sheet saved: table_ground.png (%dx%d, %d rows of class x variant, 16 mask columns)" % (w, h, n))
        w, h, n = generate_table_sheet(os.path.join(OUT_DIR, "table_buildings.png"), tilesets, mapping, [12, 13, 14])
        print("PASS: Table sheet saved: table_buildings.png (%dx%d, %d rows of class x variant, 16 mask columns)" % (w, h, n))
        w, h, ids = generate_composition_sheet(os.path.join(OUT_DIR, "compositions.png"), tilesets, mapping)
        print("PASS: Composition sheet saved: compositions.png (%dx%d); order: %s" % (w, h, ", ".join(ids)))
        w, h, n = generate_building_sheet(os.path.join(OUT_DIR, "buildings.png"), tilesets, mapping)
        if n:
            print("PASS: Building sheet saved: buildings.png (%dx%d, %d templates x roof colours)" % (w, h, n))
        else:
            print("SKIP: no building template has a complete roof set in the table, so no buildings.png")

    if "preview" in steps:
        w, h, used = generate_synthetic_preview(os.path.join(OUT_DIR, "preview.png"), tilesets, mapping)
        print("PASS: Synthetic preview saved: preview.png (%dx%d; %d Emerald tiles, %d placeholder tiles for gaps, %d unmapped)"
              % (w, h, used["emerald"], used["gap"], used["unmapped"]))
    print("\nAll outputs written outside the repository to:\n  %s" % OUT_DIR_DISPLAY)
    return 0


if __name__ == "__main__":
    sys.exit(run_spike(tuple(sys.argv[1:]) or ("sheets", "compositions", "preview")))
