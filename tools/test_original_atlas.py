#!/usr/bin/env python3
"""
tools/test_original_atlas.py — Unit tests for original_v1.{png,json} and recolour_tiles.py.
Contract: docs/implementation_plan_original_tiles.md §4.3, §6.1, §6.4, §7 (Decision 53, Item 40).
"""

import hashlib
import json
import os
import re
import sys
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "art_pipeline"))
import art_lib as al
from recolour_tiles import (
    EXPECTED_MAP_COLORS_HEX,
    MATERIAL_RAMPS,
    TS_TERRAIN_PALETTE,
    compose_quarter_tiles,
    generate_original_atlas,
    recolour_rgba,
)


class TestOriginalAtlas(unittest.TestCase):
    def setUp(self):
        self.repo_root = REPO_ROOT
        self.png_path = os.path.join(self.repo_root, "game", "assets", "tiles", "original_v1.png")
        self.json_path = os.path.join(self.repo_root, "game", "assets", "tiles", "original_v1.json")
        self.ph_json_path = os.path.join(self.repo_root, "game", "assets", "tiles", "placeholder_v1.json")

    def test_byte_for_byte_reproducibility_and_determinism(self):
        """Assert original_v1.{png,json} exist and match generate_original_atlas() byte-for-byte across runs."""
        self.assertTrue(os.path.isfile(self.png_path), f"Missing {self.png_path}")
        self.assertTrue(os.path.isfile(self.json_path), f"Missing {self.json_path}")

        png1, json1, _ = generate_original_atlas()
        png2, json2, _ = generate_original_atlas()
        self.assertEqual(png1, png2, "generate_original_atlas() PNG output is not deterministic")
        self.assertEqual(json1, json2, "generate_original_atlas() JSON output is not deterministic")

        with open(self.png_path, "rb") as f:
            disk_png = f.read()
        with open(self.json_path, "rb") as f:
            disk_json = f.read()

        self.assertEqual(hashlib.sha256(png1).hexdigest(), hashlib.sha256(disk_png).hexdigest(), "PNG SHA-256 mismatch")
        self.assertEqual(hashlib.sha256(json1).hexdigest(), hashlib.sha256(disk_json).hexdigest(), "JSON SHA-256 mismatch")

    def test_schema_matches_placeholder_v1_and_all_masks_distinct(self):
        """Assert original_v1.json has the exact 94-row + 4-fog-row schema of placeholder_v1.json
        and all active masked terrain rows have 16 pairwise-distinct 32x32 tiles."""
        self.assertTrue(os.path.isfile(self.png_path), f"Missing {self.png_path}")
        self.assertTrue(os.path.isfile(self.json_path), f"Missing {self.json_path}")

        with open(self.json_path, "r", encoding="utf-8") as f:
            orig_data = json.load(f)
        with open(self.ph_json_path, "r", encoding="utf-8") as f:
            ph_data = json.load(f)

        self.assertEqual(orig_data, ph_data, "original_v1.json schema must match placeholder_v1.json")

        atlas_img = al.read_png(self.png_path)
        self.assertEqual((atlas_img.w, atlas_img.h), (512, 3136))

        active_rows = set(range(0, 17)) | {25, 42, 43, 52, 53, 54, 55, 56, 57, 58, 59, 92}
        for entry in orig_data["rows"]:
            r_idx = entry["row"]
            masked = entry["masked"]
            if r_idx in active_rows:
                t0 = atlas_img.crop(0, r_idx * 32, 32, (r_idx + 1) * 32)
                self.assertEqual(t0.opaque_count(), 1024, f"Row {r_idx} col 0 must be fully opaque")
            if masked and r_idx in active_rows:
                seen_hashes = set()
                for m in range(16):
                    tm = atlas_img.crop(m * 32, r_idx * 32, (m + 1) * 32, (r_idx + 1) * 32)
                    if r_idx in (6, 7) and m >= 8:
                        self.assertGreater(tm.opaque_count(), 0, f"Tree row {r_idx} top-crown col {m} must have opaque foliage")
                        self.assertLess(tm.opaque_count(), 1024, f"Tree row {r_idx} top-crown col {m} must have transparent overhang corners")
                    else:
                        self.assertEqual(tm.opaque_count(), 1024, f"Masked row {r_idx} col {m} must be fully opaque")
                    h = hashlib.sha256(bytes(tm.px)).hexdigest()
                    seen_hashes.add(h)
                self.assertEqual(len(seen_hashes), 16, f"Masked row {r_idx} must have 16 pairwise-distinct mask tiles, got {len(seen_hashes)}")
            elif not masked:
                for m in range(1, 16):
                    tm = atlas_img.crop(m * 32, r_idx * 32, (m + 1) * 32, (r_idx + 1) * 32)
                    self.assertEqual(tm.opaque_count(), 0, f"Unmasked row {r_idx} col {m} must be transparent")

    def test_palette_steps_and_style_reference_bounds(self):
        """Assert every material ramp step has redmean >= 40 and recoloured terrain samples pass style bounds."""
        for mat_name, keys in MATERIAL_RAMPS:
            for i in range(len(keys) - 1):
                c1 = TS_TERRAIN_PALETTE[keys[i]][:3]
                c2 = TS_TERRAIN_PALETTE[keys[i + 1]][:3]
                dist = al.redmean(c1, c2)
                self.assertGreaterEqual(dist, 40.0, f"{mat_name} step {keys[i]}->{keys[i+1]} redmean={dist:.1f} < 40.0")

        _, _, samples = generate_original_atlas()
        metrics = []
        for s in samples:
            m = al.tile_metrics(lambda x, y, im=s: im.rgb(x, y), lambda x, y, im=s: im.opaque(x, y), 0, 0)
            self.assertIsNotNone(m)
            metrics.append(m)
        soft_step = sum(m["soft_step_ratio"] for m in metrics) / len(metrics)
        dark_share = sum(m["dark_share"] for m in metrics) / len(metrics)
        val_mean = sum(m["val_mean"] for m in metrics) / len(metrics)
        sat_mean = sum(m["sat_mean"] for m in metrics) / len(metrics)
        self.assertLessEqual(soft_step, 0.1421, f"soft_step_ratio {soft_step:.4f} > 0.1421")
        self.assertLessEqual(dark_share, 0.0273, f"dark_share {dark_share:.4f} > 0.0273")
        self.assertTrue(0.3934 <= val_mean <= 0.9330, f"val_mean {val_mean:.4f} outside [0.3934, 0.9330]")
        self.assertTrue(0.0375 <= sat_mean <= 0.9341, f"sat_mean {sat_mean:.4f} outside [0.0375, 0.9341]")

    def test_map_view_and_synth_worker_and_credits(self):
        """Assert map_view.gd loads original_v1, MAP_COLORS match TS_TERRAIN_PALETTE in both files, and CREDITS.md credits Kenney."""
        mv_path = os.path.join(self.repo_root, "game", "world", "map_view.gd")
        sw_path = os.path.join(self.repo_root, "game", "world", "synth_worker.gd")
        cr_path = os.path.join(self.repo_root, "CREDITS.md")

        with open(mv_path, "r", encoding="utf-8") as f:
            mv_text = f.read()
        with open(sw_path, "r", encoding="utf-8") as f:
            sw_text = f.read()
        with open(cr_path, "r", encoding="utf-8") as f:
            cr_text = f.read()

        self.assertIn("res://assets/tiles/original_v1.png", mv_text, "map_view.gd does not load original_v1.png")
        self.assertIn("res://assets/tiles/original_v1.json", mv_text, "map_view.gd does not load original_v1.json")

        for label, text in [("map_view.gd", mv_text), ("synth_worker.gd", sw_text)]:
            for cls_id, hex_col in EXPECTED_MAP_COLORS_HEX.items():
                pattern = rf"\b{cls_id}\s*:\s*Color(?:\.html)?\(\"{re.escape(hex_col)}\"\)"
                self.assertRegex(text, pattern, f"{label} MAP_COLORS[{cls_id}] does not match {hex_col}")

        self.assertIn("Kenney", cr_text, "CREDITS.md must credit Kenney for the CC0 Roguelike/RPG Pack")
        self.assertIn("CC0", cr_text, "CREDITS.md must name CC0")

    def test_tier4_terrain_sprites_and_tree_canopy_layers(self):
        """Assert Tier 4 16x32 trees and 16x16 small objects exist in game/assets/original/terrain/ and map_view.gd has TreeTopKnown/Cleared."""
        terrain_dir = os.path.join(self.repo_root, "game", "assets", "original", "terrain")
        for tree_name in ("tree_round.png", "tree_conifer.png"):
            p = os.path.join(terrain_dir, tree_name)
            self.assertTrue(os.path.isfile(p), f"Missing {p}")
            im = al.read_png(p)
            self.assertEqual((im.w, im.h), (16, 32), f"{tree_name} must be 16x32 px (1x2 tiles)")

        for obj_name in ("obj_flowers.png", "obj_sign.png", "obj_crop.png", "obj_bush.png"):
            p = os.path.join(terrain_dir, obj_name)
            self.assertTrue(os.path.isfile(p), f"Missing {p}")
            im = al.read_png(p)
            self.assertEqual((im.w, im.h), (16, 16), f"{obj_name} must be 16x16 px (1x1 tile)")

        mv_path = os.path.join(self.repo_root, "game", "world", "map_view.gd")
        with open(mv_path, "r", encoding="utf-8") as f:
            mv_text = f.read()
        self.assertIn("TreeTopKnown", mv_text)
        self.assertIn("TreeTopCleared", mv_text)


if __name__ == "__main__":
    unittest.main()
