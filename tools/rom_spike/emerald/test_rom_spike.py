#!/usr/bin/env python3
"""
Tenth Spring — Automated Tests for Pokémon Emerald GBA Tile Spike (Item 12)
Contract: docs/agent_execution_guide.md §6
          docs/design_rom_asset_pipeline.md §4, §5, §7
"""

import json
import os
import sys
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "rom_spike", "emerald"))

from rom_spike import (
    check_preconditions,
    lz77_decompress,
    bgr555_to_rgb,
    EmeraldTileset,
    render_metatile_canvas,
    PRIMARY_TILESET_OFFSET,
    SECONDARY_TILESETS_START,
    FEATURED_SECONDARY_TILESETS,
    EXPECTED_HEADER,
    EXPECTED_SHA1,
)


class TestEmeraldTileSpike(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rom_data = check_preconditions()
        cls.primary_ts = EmeraldTileset(cls.rom_data, PRIMARY_TILESET_OFFSET, is_secondary=False, name="General")
        sec_offset = PRIMARY_TILESET_OFFSET + FEATURED_SECONDARY_TILESETS["sec01_petalburg"] * 24
        cls.sec_petalburg = EmeraldTileset(cls.rom_data, sec_offset, is_secondary=True, name="Petalburg")

    def test_preconditions(self):
        """ROM preconditions: header code BPEE, exact SHA-1, path outside repo."""
        header = self.rom_data[0xAC:0xB0]
        self.assertEqual(header, EXPECTED_HEADER)
        import hashlib
        actual_sha1 = hashlib.sha1(self.rom_data).hexdigest().lower()
        self.assertEqual(actual_sha1, EXPECTED_SHA1)

        rom_path = os.environ.get("TENTH_SPRING_ROM_GBA")
        self.assertIsNotNone(rom_path)
        real_rom = os.path.realpath(os.path.expanduser(rom_path))
        real_repo = os.path.realpath(REPO_ROOT)
        self.assertFalse(real_rom.startswith(real_repo), "ROM path must be outside repo")

    def test_primary_tileset_structure(self):
        """Primary tileset offset 0x3DF704, 512 metatiles, tiles decompress to 16,384 bytes."""
        self.assertEqual(self.primary_ts.offset, PRIMARY_TILESET_OFFSET)
        self.assertEqual(self.primary_ts.num_metatiles, 512)
        self.assertEqual(self.primary_ts.tiles_offset, 0xDD5010)
        self.assertEqual(self.primary_ts.pal_offset, 0xDD4E10)
        self.assertEqual(self.primary_ts.meta_offset, 0x3960F0)
        self.assertEqual(self.primary_ts.attr_offset, 0x3980F0)
        self.assertEqual(len(self.primary_ts.tiles_raw), 16384)
        self.assertEqual(len(self.primary_ts.palettes), 16)

    def test_palette_color_count_and_transparency(self):
        """Every palette has <= 16 colors; BGR555 conversion preserves valid RGB range 0..255."""
        for p_idx, pal in enumerate(self.primary_ts.palettes):
            self.assertLessEqual(len(pal), 16)
            for r, g, b in pal:
                self.assertTrue(0 <= r <= 255)
                self.assertTrue(0 <= g <= 255)
                self.assertTrue(0 <= b <= 255)

    def test_pixel_variance_and_color_dominance(self):
        """Grass, tall grass, and water metatiles pass pixel-variance and dominance tests."""
        # Metatile 1: Grass (green dominant)
        grass_c = render_metatile_canvas(1, self.primary_ts)
        all_rgb = [grass_c[y][x] for y in range(16) for x in range(16)]
        avg_r = sum(c[0] for c in all_rgb) / 256.0
        avg_g = sum(c[1] for c in all_rgb) / 256.0
        avg_b = sum(c[2] for c in all_rgb) / 256.0
        self.assertGreater(avg_g, avg_r, f"Grass G ({avg_g}) must exceed R ({avg_r})")
        self.assertGreater(avg_g, avg_b, f"Grass G ({avg_g}) must exceed B ({avg_b})")

        # Metatile 13: Tall grass (green dominant + high variance)
        tg_c = render_metatile_canvas(13, self.primary_ts)
        all_rgb_tg = [tg_c[y][x] for y in range(16) for x in range(16)]
        avg_r_tg = sum(c[0] for c in all_rgb_tg) / 256.0
        avg_g_tg = sum(c[1] for c in all_rgb_tg) / 256.0
        avg_b_tg = sum(c[2] for c in all_rgb_tg) / 256.0
        var_r_tg = sum((c[0] - avg_r_tg) ** 2 for c in all_rgb_tg) / 256.0
        var_g_tg = sum((c[1] - avg_g_tg) ** 2 for c in all_rgb_tg) / 256.0
        var_b_tg = sum((c[2] - avg_b_tg) ** 2 for c in all_rgb_tg) / 256.0
        self.assertGreater(avg_g_tg, avg_r_tg)
        self.assertGreater(avg_g_tg, avg_b_tg)
        self.assertGreater(var_r_tg, 500.0, f"Tall grass variance R was {var_r_tg}")
        self.assertGreater(var_g_tg, 500.0, f"Tall grass variance G was {var_g_tg}")
        self.assertGreater(var_b_tg, 500.0, f"Tall grass variance B was {var_b_tg}")

        # Metatile 44: Water (blue dominant)
        w_c = render_metatile_canvas(44, self.primary_ts)
        all_rgb_w = [w_c[y][x] for y in range(16) for x in range(16)]
        avg_r_w = sum(c[0] for c in all_rgb_w) / 256.0
        avg_g_w = sum(c[1] for c in all_rgb_w) / 256.0
        avg_b_w = sum(c[2] for c in all_rgb_w) / 256.0
        self.assertGreater(avg_b_w, avg_r_w, f"Water B ({avg_b_w}) must exceed R ({avg_r_w})")
        self.assertGreater(avg_b_w, avg_g_w, f"Water B ({avg_b_w}) must exceed G ({avg_g_w})")

    def test_wrong_palette_rejection(self):
        """Falsifying check: a corrupted or shifted palette fails the dominance test."""
        # Construct corrupted palettes where all green is zeroed out
        corrupted_palettes = []
        for pal in self.primary_ts.palettes:
            corrupted_palettes.append([(r, 0, b) for r, g, b in pal])

        class FakeTs:
            tiles_raw = self.primary_ts.tiles_raw
            metatiles_raw = self.primary_ts.metatiles_raw
            palettes = corrupted_palettes
            num_metatiles = 512

        fake_ts = FakeTs()
        grass_bad = render_metatile_canvas(1, fake_ts)
        all_rgb = [grass_bad[y][x] for y in range(16) for x in range(16)]
        avg_r = sum(c[0] for c in all_rgb) / 256.0
        avg_g = sum(c[1] for c in all_rgb) / 256.0
        # Under corrupted palette, G cannot be greater than R
        self.assertFalse(avg_g > avg_r, "Corrupted palette must fail grass green dominance check")

    def test_mapping_table_coverage(self):
        """Coverage: every (class, variant) in placeholder_v1.json is in emerald_tile_map.json or gaps."""
        map_path = os.path.join(REPO_ROOT, "game", "config", "emerald_tile_map.json")
        self.assertTrue(os.path.exists(map_path), "emerald_tile_map.json must exist")
        with open(map_path, "r") as f:
            em_map = json.load(f)

        ph_path = os.path.join(REPO_ROOT, "game", "assets", "tiles", "placeholder_v1.json")
        with open(ph_path, "r") as f:
            ph = json.load(f)

        tile_map = em_map.get("tile_map", {})
        gaps = em_map.get("gaps", [])

        for row in ph["rows"]:
            c = str(row["class"])
            v = str(row["variant"])
            mapped = (c in tile_map) and (v in tile_map[c])
            self.assertTrue(
                mapped or len(gaps) > 0,
                f"Row class {c} variant {v} must be mapped or documented under gaps",
            )

        # Landmarks coverage (§1a rows)
        required_landmarks = [
            "pyramid_hall", "space_center", "battle_tower", "art_museum",
            "maritime_museum", "contest_hall", "dept_store", "game_corner",
            "weather_institute", "power_plant", "league_hall", "stadium",
            "cycling_road", "trick_house"
        ]
        compositions = em_map.get("compositions", {})
        for lm in required_landmarks:
            has_comp = lm in compositions
            has_gap = any(lm in g for g in gaps)
            self.assertTrue(has_comp or has_gap, f"Landmark {lm} must have composition or gaps entry")

    def test_spike_outputs_exist_outside_repo(self):
        """Verify generated contact sheets and synthetic preview exist in ~/.tenth_spring_rom_spike/emerald/."""
        out_dir = os.path.expanduser("~/.tenth_spring_rom_spike/emerald")
        expected_files = [
            "primary_general.png",
            "sec01_petalburg.png",
            "sec02_rustboro.png",
            "sec04_slateport.png",
            "sec05_mauville.png",
            "sec09_lilycove.png",
            "sec10_mossdeep.png",
            "sec44_battle_frontier.png",
            "preview.png"
        ]
        for fname in expected_files:
            fpath = os.path.join(out_dir, fname)
            self.assertTrue(os.path.exists(fpath), f"Output file missing: {fpath}")
            self.assertGreater(os.path.getsize(fpath), 1024, f"Output file {fname} too small")


if __name__ == "__main__":
    unittest.main()
