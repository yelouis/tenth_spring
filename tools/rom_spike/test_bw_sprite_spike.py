#!/usr/bin/env python3
"""
Unit and falsifiability tests for tools/rom_spike/bw_sprite_spike.py (Item 10).
"""

import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.rom_spike.bw_sprite_spike import (
    CANVAS_SIZE,
    REPO_ROOT,
    RomValidationError,
    assemble_sprite_96x96,
    decompress_lz,
    evaluate_sprite_quality,
    parse_ncer_cell0,
    parse_nclr_palette,
    run_spike,
    verify_rom_preconditions,
)


def _make_synthetic_ncer_cell0() -> bytes:
    """Construct a valid synthetic 115-byte Entry 0 NCER (RECN / KBEC) with the 4-OAM 96x96 layout."""
    # Generic 16-byte Nitro header
    hdr = struct.pack("<4sHHIHH", b"RECN", 0xFEFF, 0x0100, 115, 16, 1)
    # CEBK header at offset 16: magic='KBEC', size=99, num_cells=1, bank_attr=0, cell_off=24, mapping_mode=1
    cebk = struct.pack("<4sIHHII", b"KBEC", 99, 1, 0, 24, 1) + b"\x00" * 12
    # Cell 0 at offset 40 (24 + cell_off=24): n_oam=4, cell_attr=0, oam_ptr=0
    cell0 = struct.pack("<HHI", 4, 0, 0)
    # 4 OAMs (each 6 bytes: attr0, attr1, attr2):
    # OAM 0: x=-48 (512-48=464), y=-48 (256-48=208), shape=0, size=3, tile=0
    # OAM 1: x=16, y=-48 (208), shape=2, size=3, tile=32
    # OAM 2: x=-48 (464), y=16, shape=1, size=3, tile=48
    # OAM 3: x=16, y=16, shape=0, size=2, tile=64
    oams = b"".join(
        [
            struct.pack("<HHH", 208 | (0 << 14), 464 | (3 << 14), 0),
            struct.pack("<HHH", 208 | (2 << 14), 16 | (3 << 14), 32),
            struct.pack("<HHH", 16 | (1 << 14), 464 | (3 << 14), 48),
            struct.pack("<HHH", 16 | (0 << 14), 16 | (2 << 14), 64),
        ]
    )
    return hdr + cebk + cell0 + oams


def _make_synthetic_nclr() -> bytes:
    """Construct a valid 72-byte NCLR (RLCN / TTLP) with 16 distinct 15-bit colours."""
    hdr = struct.pack("<4sHHIHH", b"RLCN", 0xFEFF, 0x0100, 72, 16, 1)
    ttlp = struct.pack("<4sIIIHH", b"TTLP", 56, 3, 0, 32, 0) + b"\x00" * 4
    # 16 BGR555 colours with high RGB variance
    rgb_list = [
        (0, 0, 0),
        (31, 4, 4),
        (4, 31, 4),
        (4, 4, 31),
        (31, 31, 4),
        (31, 4, 31),
        (4, 31, 31),
        (28, 28, 28),
        (16, 8, 24),
        (24, 16, 8),
        (8, 24, 16),
        (20, 4, 12),
        (12, 20, 4),
        (4, 12, 20),
        (26, 20, 10),
        (10, 10, 10),
    ]
    pal_bytes = b"".join(
        struct.pack("<H", (r & 0x1F) | ((g & 0x1F) << 5) | ((b & 0x1F) << 10))
        for r, g, b in rgb_list
    )
    return hdr + ttlp + pal_bytes


def _make_synthetic_ncgr(oam_rects) -> bytes:
    """
    Construct a 4,656-byte static 96x96 NCGR (RGCN / RAHC) containing a coherent
    multi-region silhouette (spanning the 64x64, 32x64, 64x32, and 32x32 OAM blocks).
    """
    grid = [[0] * CANVAS_SIZE for _ in range(CANVAS_SIZE)]
    for y in range(20, 78):
        for x in range(22, 76):
            if (x - 48) ** 2 + (y - 48) ** 2 <= 26 ** 2:
                if y < 38:
                    grid[y][x] = 1 if x < 48 else 2
                elif y < 58:
                    grid[y][x] = 3 if x < 48 else 4
                else:
                    grid[y][x] = 5 if x < 48 else 6

    raw_tiles = bytearray(4608)
    for ox, oy, tw, th, t_base in oam_rects:
        for ty in range(th):
            for tx in range(tw):
                t_idx = t_base + ty * tw + tx
                for py in range(8):
                    for px in range(0, 8, 2):
                        p0 = grid[oy + ty * 8 + py][ox + tx * 8 + px] & 0xF
                        p1 = grid[oy + ty * 8 + py][ox + tx * 8 + px + 1] & 0xF
                        raw_tiles[t_idx * 32 + py * 4 + (px >> 1)] = p0 | (p1 << 4)

    hdr = struct.pack("<4sHHIHH", b"RGCN", 0xFEFF, 0x0100, 4656, 16, 1)
    rahc = struct.pack("<4sIHHIIIII", b"RAHC", 4640, 12, 12, 3, 0, 0, 4608, 24)
    return hdr + rahc + bytes(raw_tiles)


class BwSpriteSpikeTests(unittest.TestCase):
    def test_preconditions_reject_missing_and_inside_repo_paths(self) -> None:
        with self.assertRaises(RomValidationError):
            verify_rom_preconditions("")
        inside_file = REPO_ROOT / "README.md"
        with self.assertRaises(RomValidationError):
            verify_rom_preconditions(str(inside_file))

    def test_lz11_decompression_roundtrip(self) -> None:
        # Uncompressed magic pass-through
        raw_rgcn = b"RGCN" + b"\x00" * 20
        dec, mode = decompress_lz(raw_rgcn)
        self.assertEqual(mode, "RAW")
        self.assertEqual(dec, raw_rgcn)

        # Simple LZ11 stream: 16 bytes ('ABCD' repeated 4 times)
        # Header: 0x11, len=16 (0x10, 0x00, 0x00)
        # Flag byte: 0b00001000 (4 literals 'A','B','C','D', then 1 backreference length=12 disp=4)
        # Mode >=2 backreference: ind = length - 1 = 11 (0xB), disp - 1 = 3 -> b1 = 0xB0, b2 = 0x03
        lz11_stream = bytes([0x11, 16, 0, 0, 0x08, ord("A"), ord("B"), ord("C"), ord("D"), 0xB0, 0x03])
        dec11, mode11 = decompress_lz(lz11_stream)
        self.assertEqual(mode11, "LZ11")
        self.assertEqual(dec11, b"ABCD" * 4)

    def test_falsifiers_reject_wrong_xor_seed_blank_palette_and_linear_tiles(self) -> None:
        ncer = _make_synthetic_ncer_cell0()
        oams = parse_ncer_cell0(ncer)
        self.assertEqual(
            oams,
            [(0, 0, 8, 8, 0), (64, 0, 4, 8, 64), (0, 64, 8, 4, 96), (64, 64, 4, 4, 128)],
        )
        nclr = _make_synthetic_nclr()
        pal = parse_nclr_palette(nclr)
        self.assertEqual(len(pal), 16)

        ncgr = _make_synthetic_ncgr(oams)

        # 1. Clean decode passes all checks
        clean_grid = assemble_sprite_96x96(ncgr, oams)
        clean_metrics = evaluate_sprite_quality(clean_grid, pal)
        self.assertTrue(clean_metrics["ok"], f"Clean sprite should pass: {clean_metrics}")

        # 2. Falsifier A: Wrong XOR seed (produces static noise -> fails coherence & opaque pixel bounds)
        xor_grid = assemble_sprite_96x96(ncgr, oams, wrong_xor_seed=0x5A3C)
        xor_metrics = evaluate_sprite_quality(xor_grid, pal)
        self.assertFalse(xor_metrics["ok"], f"Wrong XOR seed must fail quality check: {xor_metrics}")
        self.assertLess(xor_metrics["coherence"], 0.65)

        # 3. Falsifier B: Flat/corrupt single-colour palette (variance = 0 -> fails rgb_variance >= 500)
        flat_pal = [(120, 120, 120)] * 16
        flat_metrics = evaluate_sprite_quality(clean_grid, flat_pal)
        self.assertFalse(flat_metrics["ok"], f"Zero-variance palette must fail: {flat_metrics}")
        self.assertEqual(flat_metrics["rgb_variance"], 0.0)

        # 4. Falsifier C: Linear 12x12 tile order instead of NCER 4-OAM cell bank (breaks tile seam continuity)
        linear_grid = assemble_sprite_96x96(ncgr, oams, linear_tile_order=True)
        linear_metrics = evaluate_sprite_quality(linear_grid, pal)
        self.assertLess(
            linear_metrics["seam_continuity"],
            clean_metrics["seam_continuity"],
            "Linear tile order must degrade seam continuity across OAM boundaries.",
        )

    def test_real_rom_decode_all_649_when_env_set(self) -> None:
        rom_env = os.environ.get("TENTH_SPRING_ROM_BW", "")
        if not rom_env:
            self.skipTest("TENTH_SPRING_ROM_BW not set; skipping real ROM 649-sprite verification.")
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            report = run_spike(rom_env, out_dir=out_dir)
            self.assertIn(report["header"]["game_code"], ("IRBO", "IRAO"))
            self.assertEqual(report["sprite_archive"]["num_files"], 14285)
            self.assertEqual(report["decode_summary"]["decoded_ok"], 649)
            self.assertEqual(report["decode_summary"]["failure_count"], 0)
            self.assertTrue(report["decode_summary"]["accepted_for_sprites"])
            self.assertTrue((out_dir / "preview.png").is_file())

            # Also verify that injecting a wrong XOR seed on real #609 Chandelure fails
            rom_path = verify_rom_preconditions(rom_env)
            with open(rom_path, "rb") as f:
                f.seek(int(report["header"]["fat_offset"]))
                fat = f.read(int(report["header"]["fat_size"]))
                s_start, s_end = struct.unpack_from(
                    "<II", fat, int(report["sprite_archive"]["file_id"]) * 8
                )
                from tools.rom_spike.bw_sprite_spike import parse_narc_index
                gmif_start, entries = parse_narc_index(f, s_start, s_end)
                es4, ee4 = entries[4]
                f.seek(gmif_start + es4)
                ncer0, _ = decompress_lz(f.read(ee4 - es4))
                oams = parse_ncer_cell0(ncer0)

                base609 = 609 * 20
                es0, ee0 = entries[base609 + 0]
                f.seek(gmif_start + es0)
                ncgr609, _ = decompress_lz(f.read(ee0 - es0))
                es18, ee18 = entries[base609 + 18]
                f.seek(gmif_start + es18)
                nclr609, _ = decompress_lz(f.read(ee18 - es18))
                pal609 = parse_nclr_palette(nclr609)

                bad_xor_609 = evaluate_sprite_quality(
                    assemble_sprite_96x96(ncgr609, oams, wrong_xor_seed=0x1357), pal609
                )
                self.assertFalse(bad_xor_609["ok"])
                bad_linear_609 = evaluate_sprite_quality(
                    assemble_sprite_96x96(ncgr609, oams, linear_tile_order=True), pal609
                )
                self.assertFalse(bad_linear_609["ok"])


if __name__ == "__main__":
    unittest.main()
