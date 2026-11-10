#!/usr/bin/env python3
"""
Black/White NDS Battle Sprite Spike (Item 10 — Decision 34).

Contract: docs/design_rom_asset_pipeline.md §2, §4–5, §7
          docs/agent_execution_guide.md §9

Reads a player-supplied Pokémon Black (IRBO) or White (IRAO) NDS ROM pointed to by
TENTH_SPRING_ROM_BW (outside the repository), parses the NDS FNT/FAT by offset,
locates the battle sprite NARC (/a/0/0/4) and item icon NARC (/a/0/2/5),
decodes static 96x96 front/back sprites (normal and shiny) one sprite at a time,
verifies all 649 National Dex front sprites against structural and pixel checks,
and writes ~/.tenth_spring_rom_spike/preview.png (2x side-by-side preview of
#94, #200, #355, #487, #609, and #623) and ~/.tenth_spring_rom_spike/bw_report.json.

Embeds zero bytes, names, or tables from any ROM. Pure Python 3 standard library.
"""

import hashlib
import json
import os
import struct
import sys
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = Path.home() / ".tenth_spring_rom_spike"

# No-Intro Nintendo DS (Decrypted) DAT (version 20260101, Dat-o-Matic No-Intro org)
# Known-good SHA-1 digests for clean USA/Europe Black (IRBO) and White (IRAO) dumps:
NO_INTRO_DAT_VERSION = "No-Intro Nintendo - Nintendo DS (Decrypted) (20260101)"
NO_INTRO_DAT_SOURCE = "https://datomatic.no-intro.org (Nintendo - Nintendo DS (Decrypted))"
KNOWN_CLEAN_SHA1 = {
    "IRBO": "26ad0b9967aa279c4a266ee6fb952b9cae6bb812",  # Pokemon - Black Version (USA, Europe) (NDSi Enhanced)
    "IRAO": "a5be2ef5fd2b621fd3b4fb1cd1fd4bb71f3bf820",  # Pokemon - White Version (USA, Europe) (NDSi Enhanced)
}

PREVIEW_DEX_NUMBERS = (94, 200, 355, 487, 609, 623)
CANVAS_SIZE = 96
FILES_PER_SPECIES_ENTRY = 20
NATIONAL_DEX_COUNT = 649


class RomValidationError(ValueError):
    """Raised when a ROM fails header, path isolation, or structural sprite checks."""


def verify_rom_preconditions(rom_path_str: Optional[str] = None) -> Path:
    """Verify TENTH_SPRING_ROM_BW exists and its real path lies outside the repository."""
    raw = rom_path_str if rom_path_str is not None else os.environ.get("TENTH_SPRING_ROM_BW", "")
    if not raw:
        raise RomValidationError("TENTH_SPRING_ROM_BW is not set.")
    rom_path = Path(raw).expanduser().resolve()
    if not rom_path.is_file():
        raise RomValidationError("TENTH_SPRING_ROM_BW does not point to an existing file.")
    repo_real = REPO_ROOT.resolve()
    try:
        rom_path.relative_to(repo_real)
        inside_repo = True
    except ValueError:
        inside_repo = False
    if inside_repo:
        raise RomValidationError("ROM file must reside outside the repository.")
    return rom_path


def read_nds_header_and_sha1(rom_path: Path) -> Dict[str, object]:
    """Read NDS header fields (gameCode at 0x0C, FNT at 0x40, FAT at 0x48) and compute SHA-1 in chunks."""
    sha1 = hashlib.sha1()
    file_size = 0
    with open(rom_path, "rb") as f:
        header = f.read(0x200)
        if len(header) < 0x100:
            raise RomValidationError("File is too small to be a valid NDS ROM.")
        sha1.update(header)
        file_size += len(header)
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            sha1.update(chunk)
            file_size += len(chunk)

    title = header[0x00:0x0C].decode("ascii", errors="replace").rstrip("\x00")
    game_code = header[0x0C:0x10].decode("ascii", errors="replace")
    if game_code not in ("IRBO", "IRAO"):
        raise RomValidationError(
            f"Unsupported NDS game code {game_code!r} at 0x0C (expected 'IRBO' or 'IRAO')."
        )
    fnt_offset, fnt_size, fat_offset, fat_size = struct.unpack_from("<IIII", header, 0x40)
    digest = sha1.hexdigest()
    expected_clean = KNOWN_CLEAN_SHA1.get(game_code)
    is_clean = digest == expected_clean
    status = "clean" if is_clean else "modified — sprites only"
    return {
        "title": title,
        "game_code": game_code,
        "file_size": file_size,
        "sha1": digest,
        "expected_clean_sha1": expected_clean,
        "no_intro_dat_version": NO_INTRO_DAT_VERSION,
        "no_intro_dat_source": NO_INTRO_DAT_SOURCE,
        "is_clean": is_clean,
        "status": status,
        "fnt_offset": fnt_offset,
        "fnt_size": fnt_size,
        "fat_offset": fat_offset,
        "fat_size": fat_size,
    }


def parse_fnt_paths(fnt: bytes) -> Dict[str, int]:
    """Parse NDS File Name Table (FNT) into a mapping of {'/a/0/0/4': file_id, ...}."""
    paths: Dict[str, int] = {}

    def _walk(dir_id: int, prefix: str) -> None:
        idx = dir_id & 0x0FFF
        if (idx + 1) * 8 > len(fnt):
            return
        sub_off, first_file_id, _ = struct.unpack_from("<IHH", fnt, idx * 8)
        pos = sub_off
        file_id = first_file_id
        while pos < len(fnt):
            length = fnt[pos]
            pos += 1
            if length == 0:
                break
            is_dir = (length & 0x80) != 0
            name_len = length & 0x7F
            name = fnt[pos : pos + name_len].decode("ascii", errors="replace")
            pos += name_len
            full = f"{prefix}/{name}"
            if is_dir:
                sub_id = struct.unpack_from("<H", fnt, pos)[0]
                pos += 2
                _walk(sub_id, full)
            else:
                paths[full] = file_id
                file_id += 1

    _walk(0xF000, "")
    return paths


def read_fat_span(fat: bytes, file_id: int) -> Tuple[int, int]:
    """Return (start_offset, end_offset) for a given FAT file_id."""
    if (file_id + 1) * 8 > len(fat):
        raise RomValidationError(f"FAT index {file_id} out of range.")
    return struct.unpack_from("<II", fat, file_id * 8)


def parse_narc_index(f, narc_start: int, narc_end: int) -> Tuple[int, List[Tuple[int, int]]]:
    """
    Parse a NARC archive header at narc_start without reading its GMIF payload into memory.
    Returns (gmif_data_start, [(entry_rel_start, entry_rel_end), ...]).
    """
    if narc_end - narc_start < 28:
        raise RomValidationError("NARC slice too small.")
    f.seek(narc_start)
    narc_hdr = f.read(16)
    magic, _bom, _ver, _total_size, _hdr_size, _num_chunks = struct.unpack("<4sHHIHH", narc_hdr)
    if magic != b"NARC":
        raise RomValidationError(f"Invalid NARC magic: {magic!r}")
    btaf_hdr = f.read(12)
    btaf_magic, btaf_size, num_files = struct.unpack("<4sII", btaf_hdr)
    if btaf_magic != b"BTAF":
        raise RomValidationError(f"Invalid BTAF magic: {btaf_magic!r}")
    table_bytes = f.read(num_files * 8)
    entries = [struct.unpack_from("<II", table_bytes, i * 8) for i in range(num_files)]

    btnf_pos = narc_start + 16 + btaf_size
    f.seek(btnf_pos)
    btnf_magic, btnf_size = struct.unpack("<4sI", f.read(8))
    if btnf_magic != b"BTNF":
        raise RomValidationError(f"Invalid BTNF magic: {btnf_magic!r}")

    gmif_pos = btnf_pos + btnf_size
    f.seek(gmif_pos)
    gmif_magic, _gmif_size = struct.unpack("<4sI", f.read(8))
    if gmif_magic != b"GMIF":
        raise RomValidationError(f"Invalid GMIF magic: {gmif_magic!r}")
    gmif_data_start = gmif_pos + 8
    return gmif_data_start, entries


def decompress_lz(data: bytes) -> Tuple[bytes, str]:
    """
    Decompress Nintendo DS LZ77 (0x10) or LZ11 (0x11) stream if compressed.
    Note: Raw NARC sub-files whose first 4 bytes are an uncompressed Nitro magic
    ('RGCN', 'RLCN', 'RECN', 'RNAN', 'RCMN', 'RAMN') begin with ASCII 'R' (0x52),
    so they never collide with 0x10 or 0x11.
    """
    if not data:
        return b"", "EMPTY"
    if len(data) >= 4 and data[:4] in (b"RGCN", b"RLCN", b"RECN", b"RNAN", b"RCMN", b"RAMN"):
        return data, "RAW"

    tag = data[0]
    if tag == 0x10 and len(data) >= 4:
        dec_len = data[1] | (data[2] << 8) | (data[3] << 16)
        if dec_len == 0:
            return data, "RAW"
        out = bytearray()
        pos = 4
        while len(out) < dec_len and pos < len(data):
            flags = data[pos]
            pos += 1
            for i in range(8):
                if len(out) >= dec_len or pos >= len(data):
                    break
                if flags & (0x80 >> i):
                    if pos + 1 >= len(data):
                        raise RomValidationError("Truncated LZ10 backreference.")
                    b1, b2 = data[pos], data[pos + 1]
                    pos += 2
                    length = (b1 >> 4) + 3
                    disp = (((b1 & 0x0F) << 8) | b2) + 1
                    if disp > len(out):
                        raise RomValidationError("Invalid LZ10 displacement.")
                    for _ in range(length):
                        out.append(out[-disp])
                else:
                    out.append(data[pos])
                    pos += 1
        return bytes(out[:dec_len]), "LZ10"

    if tag == 0x11 and len(data) >= 4:
        dec_len = data[1] | (data[2] << 8) | (data[3] << 16)
        pos = 4
        if dec_len == 0:
            if len(data) < 8:
                raise RomValidationError("Truncated LZ11 extended length header.")
            dec_len = struct.unpack_from("<I", data, 4)[0]
            pos = 8
        out = bytearray()
        while len(out) < dec_len and pos < len(data):
            flags = data[pos]
            pos += 1
            for i in range(8):
                if len(out) >= dec_len or pos >= len(data):
                    break
                if flags & (0x80 >> i):
                    b1 = data[pos]
                    ind = b1 >> 4
                    if ind == 0:
                        if pos + 2 >= len(data):
                            raise RomValidationError("Truncated LZ11 mode-0 backreference.")
                        b2, b3 = data[pos + 1], data[pos + 2]
                        pos += 3
                        length = ((b1 & 0x0F) << 4) + (b2 >> 4) + 0x11
                        disp = (((b2 & 0x0F) << 8) | b3) + 1
                    elif ind == 1:
                        if pos + 3 >= len(data):
                            raise RomValidationError("Truncated LZ11 mode-1 backreference.")
                        b2, b3, b4 = data[pos + 1], data[pos + 2], data[pos + 3]
                        pos += 4
                        length = (((b1 & 0x0F) << 12) | (b2 << 4) | (b3 >> 4)) + 0x111
                        disp = (((b3 & 0x0F) << 8) | b4) + 1
                    else:
                        if pos + 1 >= len(data):
                            raise RomValidationError("Truncated LZ11 short backreference.")
                        b2 = data[pos + 1]
                        pos += 2
                        length = ind + 1
                        disp = (((b1 & 0x0F) << 8) | b2) + 1
                    if disp > len(out):
                        raise RomValidationError("Invalid LZ11 displacement.")
                    for _ in range(length):
                        out.append(out[-disp])
                else:
                    out.append(data[pos])
                    pos += 1
        return bytes(out[:dec_len]), "LZ11"

    return data, "RAW"


# NDS OAM dimensions in 8x8 tiles indexed by (shape, size):
# shape 0 = Square, shape 1 = Horizontal, shape 2 = Vertical
OAM_TILE_DIMS: Dict[Tuple[int, int], Tuple[int, int]] = {
    (0, 0): (1, 1),
    (0, 1): (2, 2),
    (0, 2): (4, 4),
    (0, 3): (8, 8),
    (1, 0): (2, 1),
    (1, 1): (4, 1),
    (1, 2): (4, 2),
    (1, 3): (8, 4),
    (2, 0): (1, 2),
    (2, 1): (1, 4),
    (2, 2): (2, 4),
    (2, 3): (4, 8),
}


def parse_ncer_cell0(ncer: bytes) -> List[Tuple[int, int, int, int, int]]:
    """
    Parse cell 0 of a Nitro Cell Resource (RECN / KBEC) into a list of OAM rectangles:
    [(canvas_x_px, canvas_y_px, width_tiles, height_tiles, base_tile_index), ...]
    """
    if len(ncer) < 32 or ncer[:4] != b"RECN":
        raise RomValidationError("Invalid NCER magic.")
    cebk_magic, _size, num_cells, bank_attr, cell_off, mapping_mode = struct.unpack_from(
        "<4sIHHII", ncer, 16
    )
    if cebk_magic != b"KBEC" or num_cells < 1:
        raise RomValidationError("Invalid CEBK header in NCER.")
    cell_data_start = 24 + cell_off
    entry_size = 16 if bank_attr == 1 else 8
    n_oam, _cell_attr, oam_ptr = struct.unpack_from("<HHI", ncer, cell_data_start)
    oam_abs = cell_data_start + num_cells * entry_size + oam_ptr
    # mapping_mode gives boundary shift in 32-byte 4bpp tiles: 1 << (mapping_mode & 3)
    tile_step = 1 << (mapping_mode & 0x3)
    rects: List[Tuple[int, int, int, int, int]] = []
    for i in range(n_oam):
        attr0, attr1, attr2 = struct.unpack_from("<HHH", ncer, oam_abs + i * 6)
        y = attr0 & 0xFF
        if y >= 128:
            y -= 256
        shape = (attr0 >> 14) & 0x3
        x = attr1 & 0x1FF
        if x >= 256:
            x -= 512
        size = (attr1 >> 14) & 0x3
        tile_off = (attr2 & 0x3FF) * tile_step
        tw, th = OAM_TILE_DIMS[(shape, size)]
        rects.append((x + 48, y + 48, tw, th, tile_off))
    return rects


def parse_nclr_palette(nclr: bytes) -> List[Tuple[int, int, int]]:
    """Parse 16 BGR555 colour entries from a Nitro Palette Resource (RLCN / TTLP)."""
    if len(nclr) < 72 or nclr[:4] != b"RLCN":
        raise RomValidationError(f"Invalid NCLR palette (len={len(nclr)}).")
    pltt_magic = nclr[16:20]
    if pltt_magic != b"TTLP":
        raise RomValidationError(f"Invalid TTLP chunk magic: {pltt_magic!r}")
    colours: List[Tuple[int, int, int]] = []
    for i in range(16):
        bgr555 = struct.unpack_from("<H", nclr, 40 + i * 2)[0]
        r = ((bgr555 & 0x1F) * 255 + 15) // 31
        g = (((bgr555 >> 5) & 0x1F) * 255 + 15) // 31
        b = (((bgr555 >> 10) & 0x1F) * 255 + 15) // 31
        colours.append((r, g, b))
    return colours


def assemble_sprite_96x96(
    ncgr: bytes,
    oam_rects: List[Tuple[int, int, int, int, int]],
    *,
    wrong_xor_seed: Optional[int] = None,
    linear_tile_order: bool = False,
) -> List[List[int]]:
    """
    Assemble a 96x96 4bpp indexed sprite from a decompressed static NCGR (4,656 bytes)
    and its NCER cell 0 OAM rectangles.
    Optional fault-injection flags (wrong_xor_seed, linear_tile_order) are provided
    for falsifiability testing (§7 / §9 Validation).
    """
    if len(ncgr) < 4656 or ncgr[:4] != b"RGCN":
        raise RomValidationError(f"Invalid static 96x96 NCGR (len={len(ncgr)}).")
    rahc_magic, _csize, h_tiles, w_tiles, fmt, _mapping, _mode, data_size, _off = struct.unpack_from(
        "<4sIHHIIIII", ncgr, 16
    )
    if rahc_magic != b"RAHC" or h_tiles != 12 or w_tiles != 12 or fmt != 3 or data_size != 4608:
        raise RomValidationError(
            f"Unexpected RAHC header: h={h_tiles} w={w_tiles} fmt={fmt} size={data_size}"
        )
    tile_bytes = bytearray(ncgr[48 : 48 + 4608])

    if wrong_xor_seed is not None:
        seed = wrong_xor_seed & 0xFFFF
        for i in range(0, len(tile_bytes), 2):
            word = tile_bytes[i] | (tile_bytes[i + 1] << 8)
            word ^= seed
            tile_bytes[i] = word & 0xFF
            tile_bytes[i + 1] = (word >> 8) & 0xFF
            seed = (seed * 0x41C64E6D + 0x6073) & 0xFFFF

    grid = [[0] * CANVAS_SIZE for _ in range(CANVAS_SIZE)]
    if linear_tile_order:
        for ty in range(12):
            for tx in range(12):
                t_idx = ty * 12 + tx
                for py in range(8):
                    for px in range(8):
                        b = tile_bytes[t_idx * 32 + py * 4 + (px >> 1)]
                        grid[ty * 8 + py][tx * 8 + px] = (b >> 4) if (px & 1) else (b & 0xF)
        return grid

    for ox, oy, tw, th, t_base in oam_rects:
        for ty in range(th):
            for tx in range(tw):
                t_idx = t_base + ty * tw + tx
                for py in range(8):
                    for px in range(8):
                        b = tile_bytes[t_idx * 32 + py * 4 + (px >> 1)]
                        val = (b >> 4) if (px & 1) else (b & 0xF)
                        cy = oy + ty * 8 + py
                        cx = ox + tx * 8 + px
                        if 0 <= cx < CANVAS_SIZE and 0 <= cy < CANVAS_SIZE:
                            grid[cy][cx] = val
    return grid


def evaluate_sprite_quality(
    grid: List[List[int]], palette: List[Tuple[int, int, int]]
) -> Dict[str, object]:
    """
    Validate a decoded 96x96 sprite against §7 and §9 structural and falsifying checks:
    1. Distinct palette indices used <= 16 (and >= 2).
    2. Opaque pixel count in [300, 6500] (falsifies full-canvas XOR noise where ~8640 px are opaque).
    3. Per-pixel RGB variance across opaque pixels >= 500.0 (falsifies blank or single-colour decodes).
    4. Horizontal neighbour coherence >= 0.65 (falsifies wrong XOR seed static noise, ~0.0625).
    5. Tile-row seam continuity >= 0.40 (falsifies linear 12x12 tile ordering without NCER OAM layout).
    """
    used_indices = set()
    opaque_rgb: List[Tuple[int, int, int]] = []
    for y in range(CANVAS_SIZE):
        for x in range(CANVAS_SIZE):
            idx = grid[y][x]
            used_indices.add(idx)
            if idx != 0:
                opaque_rgb.append(palette[idx])

    distinct_colours = len(used_indices)
    opaque_count = len(opaque_rgb)
    if opaque_count > 0:
        mr = sum(c[0] for c in opaque_rgb) / opaque_count
        mg = sum(c[1] for c in opaque_rgb) / opaque_count
        mb = sum(c[2] for c in opaque_rgb) / opaque_count
        rgb_variance = (
            sum((c[0] - mr) ** 2 + (c[1] - mg) ** 2 + (c[2] - mb) ** 2 for c in opaque_rgb)
            / opaque_count
        )
    else:
        rgb_variance = 0.0

    same_pairs = 0
    total_pairs = CANVAS_SIZE * (CANVAS_SIZE - 1)
    for y in range(CANVAS_SIZE):
        row = grid[y]
        for x in range(CANVAS_SIZE - 1):
            if row[x] == row[x + 1]:
                same_pairs += 1
    coherence = same_pairs / total_pairs

    seam_matches = 0
    seam_total = 0
    for ty in range(1, 11):
        y = ty * 8
        for x in range(CANVAS_SIZE):
            a = grid[y - 1][x] != 0
            b = grid[y][x] != 0
            if a or b:
                seam_total += 1
                if a == b:
                    seam_matches += 1
    seam_continuity = seam_matches / max(1, seam_total)

    ok = (
        2 <= distinct_colours <= 16
        and len(palette) <= 16
        and 300 <= opaque_count <= 6500
        and rgb_variance >= 500.0
        and coherence >= 0.65
        and seam_continuity >= 0.40
    )
    return {
        "ok": ok,
        "distinct_colours": distinct_colours,
        "palette_len": len(palette),
        "opaque_pixels": opaque_count,
        "rgb_variance": round(rgb_variance, 2),
        "coherence": round(coherence, 4),
        "seam_continuity": round(seam_continuity, 4),
    }


def write_rgba_png(path: Path, width: int, height: int, rgba_rows: List[bytes]) -> None:
    """Write an RGBA PNG using pure Python stdlib (zlib + struct)."""
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)  # Filter type 0 (None)
        raw.extend(row)

    def _chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png_bytes = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", idat) + _chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes)


def render_scaled_sprite_rgba(
    grid: List[List[int]], palette: List[Tuple[int, int, int]], scale: int = 2
) -> List[List[Tuple[int, int, int, int]]]:
    """Render a 96x96 indexed grid + 16-colour palette into an RGBA pixel matrix at `scale`x."""
    out_h = CANVAS_SIZE * scale
    out_w = CANVAS_SIZE * scale
    canvas: List[List[Tuple[int, int, int, int]]] = [
        [(0, 0, 0, 0)] * out_w for _ in range(out_h)
    ]
    for y in range(CANVAS_SIZE):
        for x in range(CANVAS_SIZE):
            idx = grid[y][x]
            if idx != 0:
                r, g, b = palette[idx]
                px = (r, g, b, 255)
                for dy in range(scale):
                    for dx in range(scale):
                        canvas[y * scale + dy][x * scale + dx] = px
    return canvas


def run_spike(rom_path_str: Optional[str] = None, out_dir: Path = DEFAULT_OUT_DIR) -> Dict[str, object]:
    """Execute the full Item 10 Black/White sprite spike."""
    rom_path = verify_rom_preconditions(rom_path_str)
    hdr_info = read_nds_header_and_sha1(rom_path)

    with open(rom_path, "rb") as f:
        f.seek(int(hdr_info["fnt_offset"]))
        fnt = f.read(int(hdr_info["fnt_size"]))
        f.seek(int(hdr_info["fat_offset"]))
        fat = f.read(int(hdr_info["fat_size"]))

        fnt_paths = parse_fnt_paths(fnt)
        if "/a/0/0/4" not in fnt_paths:
            raise RomValidationError("Missing /a/0/0/4 battle sprite archive in FNT.")
        sprite_fid = fnt_paths["/a/0/0/4"]
        s_start, s_end = read_fat_span(fat, sprite_fid)
        gmif_start, entries = parse_narc_index(f, s_start, s_end)

        item_icon_info: Dict[str, object] = {}
        if "/a/0/2/5" in fnt_paths:
            item_fid = fnt_paths["/a/0/2/5"]
            i_start, i_end = read_fat_span(fat, item_fid)
            _i_gmif, i_entries = parse_narc_index(f, i_start, i_end)
            item_icon_info = {
                "archive_path": "/a/0/2/5",
                "file_id": item_fid,
                "num_files": len(i_entries),
            }

        def _read_entry(idx: int) -> Tuple[bytes, str]:
            es, ee = entries[idx]
            f.seek(gmif_start + es)
            raw = f.read(ee - es)
            return decompress_lz(raw)

        # Shared static 96x96 cell bank is at Entry 0 file 4
        ncer0_bytes, ncer0_comp = _read_entry(4)
        oam_rects = parse_ncer_cell0(ncer0_bytes)

        # Inspect per-species 20-file layout on #609 (Chandelure) and #94 (Gengar)
        layout_samples: Dict[str, List[Dict[str, object]]] = {}
        for sample_dex in (94, 609):
            base = sample_dex * FILES_PER_SPECIES_ENTRY
            slots: List[Dict[str, object]] = []
            for sub in range(FILES_PER_SPECIES_ENTRY):
                dec, comp = _read_entry(base + sub)
                magic4 = dec[:4].decode("ascii", errors="replace") if len(dec) >= 4 else ""
                slots.append(
                    {
                        "slot": sub,
                        "compression": comp,
                        "decompressed_bytes": len(dec),
                        "magic": magic4 if magic4.isprintable() else "BIN",
                    }
                )
            layout_samples[str(sample_dex)] = slots

        # Decode all 649 front sprites one at a time and verify quality
        decoded_ok = 0
        failures: List[Dict[str, object]] = []
        female_variant_count = 0
        preview_sprites: List[Tuple[int, List[List[int]], List[Tuple[int, int, int]], List[Tuple[int, int, int]]]] = []
        highlight_metrics: Dict[str, Dict[str, object]] = {}

        for dex in range(1, NATIONAL_DEX_COUNT + 1):
            base = dex * FILES_PER_SPECIES_ENTRY
            try:
                ncgr_front, _ = _read_entry(base + 0)
                es_f, ee_f = entries[base + 1]
                if ee_f > es_f:
                    female_variant_count += 1
                nclr_norm, _ = _read_entry(base + 18)
                nclr_shiny, _ = _read_entry(base + 19)
                pal_norm = parse_nclr_palette(nclr_norm)
                pal_shiny = parse_nclr_palette(nclr_shiny)
                grid = assemble_sprite_96x96(ncgr_front, oam_rects)
                metrics = evaluate_sprite_quality(grid, pal_norm)
                if metrics["ok"]:
                    decoded_ok += 1
                else:
                    failures.append({"dex": dex, "reason": "quality_check_failed", "metrics": metrics})
                if dex in (94, 609):
                    highlight_metrics[str(dex)] = metrics
                if dex in PREVIEW_DEX_NUMBERS:
                    preview_sprites.append((dex, grid, pal_norm, pal_shiny))
            except Exception as exc:
                failures.append({"dex": dex, "reason": str(exc)})

    # Render 2x side-by-side preview of #94, #200, #355, #487, #609, and #623
    # Row 0: Normal front sprites at 2x (192x192 each)
    # Row 1: Shiny front sprites at 2x (192x192 each)
    scale = 2
    cell_px = CANVAS_SIZE * scale  # 192
    pad = 8
    cols = len(preview_sprites)
    sheet_w = cols * cell_px + (cols + 1) * pad
    sheet_h = 2 * cell_px + 3 * pad
    bg = (28, 32, 38, 255)
    sheet: List[List[Tuple[int, int, int, int]]] = [
        [bg] * sheet_w for _ in range(sheet_h)
    ]

    for col_idx, (_dex, grid, pal_norm, pal_shiny) in enumerate(preview_sprites):
        x0 = pad + col_idx * (cell_px + pad)
        for row_idx, pal in enumerate((pal_norm, pal_shiny)):
            y0 = pad + row_idx * (cell_px + pad)
            scaled = render_scaled_sprite_rgba(grid, pal, scale=scale)
            for y in range(cell_px):
                for x in range(cell_px):
                    px = scaled[y][x]
                    if px[3] > 0:
                        sheet[y0 + y][x0 + x] = px

    rgba_rows = [
        bytes(channel for px in row for channel in px)
        for row in sheet
    ]
    preview_path = out_dir / "preview.png"
    write_rgba_png(preview_path, sheet_w, sheet_h, rgba_rows)

    report = {
        "header": hdr_info,
        "sprite_archive": {
            "path": "/a/0/0/4",
            "file_id": sprite_fid,
            "num_files": len(entries),
            "files_per_species_entry": FILES_PER_SPECIES_ENTRY,
            "species_entries_total": len(entries) // FILES_PER_SPECIES_ENTRY,
            "tail_files": len(entries) % FILES_PER_SPECIES_ENTRY,
            "female_dimorphic_species_count": female_variant_count,
            "shared_static_ncer_entry": 4,
            "shared_static_ncer_compression": ncer0_comp,
            "shared_static_oam_rects": oam_rects,
        },
        "item_icon_archive": item_icon_info,
        "layout_samples": layout_samples,
        "highlight_metrics": highlight_metrics,
        "decode_summary": {
            "total_species": NATIONAL_DEX_COUNT,
            "decoded_ok": decoded_ok,
            "failure_count": len(failures),
            "failures": failures,
            "accepted_for_sprites": decoded_ok == NATIONAL_DEX_COUNT and len(failures) == 0,
        },
        "preview_path": str(preview_path),
        "preview_dex_numbers": list(PREVIEW_DEX_NUMBERS),
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / "bw_report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    try:
        report = run_spike()
    except RomValidationError as exc:
        print(f"[BW SPIKE ERROR] {exc}", file=sys.stderr)
        return 2
    hdr = report["header"]
    arc = report["sprite_archive"]
    dec = report["decode_summary"]
    print(
        f"[BW SPIKE OK] game_code={hdr['game_code']} status={hdr['status']!r} "
        f"sha1={hdr['sha1']} /a/0/0/4={arc['num_files']} files "
        f"decoded={dec['decoded_ok']}/{dec['total_species']} failures={dec['failure_count']} "
        f"preview={report['preview_path']}"
    )
    return 0 if dec["accepted_for_sprites"] else 1


if __name__ == "__main__":
    sys.exit(main())
