#!/usr/bin/env python3
"""
tools/test_gen_placeholder_atlas.py — Unit tests for placeholder tileset atlas generator.
Contract: docs/implementation_plan_world_generation_slice2.md §5, §8
"""

import hashlib
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_placeholder_atlas import generate_atlas_assets

class TestGenPlaceholderAtlas(unittest.TestCase):
    def setUp(self):
        self.repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.png_path = os.path.join(self.repo_root, "game", "assets", "tiles", "placeholder_v1.png")
        self.json_path = os.path.join(self.repo_root, "game", "assets", "tiles", "placeholder_v1.json")
        self.gpl_path = os.path.join(self.repo_root, "assets", "palette", "tenth_spring.gpl")

    def test_byte_for_byte_reproducibility(self):
        """Assert regenerating atlas matches committed files byte-for-byte."""
        self.assertTrue(os.path.isfile(self.png_path), f"Missing {self.png_path}")
        self.assertTrue(os.path.isfile(self.json_path), f"Missing {self.json_path}")
        self.assertTrue(os.path.isfile(self.gpl_path), f"Missing {self.gpl_path}")

        png_bytes, json_bytes, gpl_bytes = generate_atlas_assets()

        with open(self.png_path, "rb") as f:
            disk_png = f.read()
        with open(self.json_path, "rb") as f:
            disk_json = f.read()
        with open(self.gpl_path, "rb") as f:
            disk_gpl = f.read()

        self.assertEqual(len(png_bytes), len(disk_png), "PNG size mismatch")
        self.assertEqual(hashlib.sha256(png_bytes).hexdigest(), hashlib.sha256(disk_png).hexdigest())

        self.assertEqual(len(json_bytes), len(disk_json), "JSON size mismatch")
        self.assertEqual(hashlib.sha256(json_bytes).hexdigest(), hashlib.sha256(disk_json).hexdigest())

        self.assertEqual(len(gpl_bytes), len(disk_gpl), "GPL size mismatch")
        self.assertEqual(hashlib.sha256(gpl_bytes).hexdigest(), hashlib.sha256(disk_gpl).hexdigest())

    def test_determinism_multiple_runs(self):
        """Assert repeated generation calls yield identical outputs."""
        p1, j1, g1 = generate_atlas_assets()
        p2, j2, g2 = generate_atlas_assets()
        self.assertEqual(p1, p2)
        self.assertEqual(j1, j2)
        self.assertEqual(g1, g2)

    def test_json_coverage_all_synthesizer_pairs(self):
        """Assert JSON covers every (class, variant) pair emitted by tile_synth2.gd."""
        with open(self.json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data.get("tile_px"), 32)
        self.assertIn("rows", data)
        self.assertIn("fog_rows", data)

        # Check fog rows
        fog = data["fog_rows"]
        for key in ["solid", "d75", "d50", "d25"]:
            self.assertIn(key, fog)
            self.assertIsInstance(fog[key], int)

        # Build map of (class, variant) -> entry
        row_entries = data["rows"]
        class_variant_map = {}
        any_variant_classes = set()

        for entry in row_entries:
            c = entry["class"]
            v = entry["variant"]
            if entry.get("any_variant", False):
                any_variant_classes.add(c)
            class_variant_map[(c, v)] = entry

        # Expected classes and variants emitted by tile_synth2.gd:
        expected_pairs = []
        expected_pairs.append((0, 0))  # VOID
        for v in range(4): expected_pairs.append((1, v))  # GRASS 0..3
        expected_pairs.append((2, 0))  # TALL_GRASS
        for v in range(2): expected_pairs.append((3, v))  # TREE 0..1
        expected_pairs.append((4, 0))  # WATER
        expected_pairs.append((5, 0))  # SAND
        expected_pairs.append((6, 0))  # MARSH
        expected_pairs.append((7, 0))  # PATH
        for v in range(2): expected_pairs.append((8, v))  # ROAD 0..1
        expected_pairs.append((9, 0))  # RAIL
        expected_pairs.append((10, 0))  # BRIDGE
        expected_pairs.append((11, 0))  # PLAZA
        for v in range(8): expected_pairs.append((12, v))  # ROOF 0..7
        for v in range(16): expected_pairs.append((13, v))  # WALL 0..15
        for v in range(8): expected_pairs.append((14, v))  # DOOR 0..7
        expected_pairs.append((15, 0))  # FENCE
        expected_pairs.append((16, 0))  # FLOWERS
        expected_pairs.append((17, 0))  # GRAVE
        for v in range(16): expected_pairs.append((18, v))  # SIGN 0..15
        expected_pairs.append((19, 0))  # CROP

        for c, v in expected_pairs:
            if c in any_variant_classes:
                # Covered by any_variant row
                continue
            self.assertIn((c, v), class_variant_map, f"Missing (class={c}, variant={v}) in JSON rows")

        # Masked classes verification
        masked_classes = {2, 3, 4, 7, 8, 9, 10, 12, 13, 15}
        for entry in row_entries:
            c = entry["class"]
            expected_masked = (c in masked_classes)
            self.assertEqual(entry["masked"], expected_masked, f"Class {c} masked flag mismatch")

    def test_palette_file(self):
        """Assert tenth_spring.gpl has <= 64 colours and standard GIMP palette header."""
        with open(self.gpl_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f.readlines()]

        self.assertEqual(lines[0], "GIMP Palette")
        self.assertEqual(lines[1], "Name: Tenth Spring")
        self.assertEqual(lines[2], "Columns: 8")
        self.assertEqual(lines[3], "#")

        color_lines = lines[4:]
        self.assertGreater(len(color_lines), 0)
        self.assertLessEqual(len(color_lines), 64, f"Palette has {len(color_lines)} colors, exceeding max of 64")

        for line in color_lines:
            parts = line.split(None, 3)
            self.assertGreaterEqual(len(parts), 3)
            r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
            self.assertTrue(0 <= r <= 255)
            self.assertTrue(0 <= g <= 255)
            self.assertTrue(0 <= b <= 255)

if __name__ == "__main__":
    unittest.main()
