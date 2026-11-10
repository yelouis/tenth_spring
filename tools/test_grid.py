#!/usr/bin/env python3
"""
tools/test_grid.py — Unit tests for tools/grid.py against tools/testdata/grid_vectors.json
Contract: docs/implementation_plan_explore_here.md §1.1
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grid  # noqa: E402


class TestGrid(unittest.TestCase):
    def setUp(self):
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.vectors_path = os.path.join(repo_root, "tools", "testdata", "grid_vectors.json")
        with open(self.vectors_path, "r", encoding="utf-8") as f:
            self.vectors = json.load(f)

    def test_vector_count_and_coverage(self):
        self.assertGreaterEqual(len(self.vectors), 40)
        names = {v["name"] for v in self.vectors}
        self.assertTrue(any("alaska" in n for n in names))
        self.assertTrue(any("hawaii" in n for n in names))
        self.assertTrue(any("puerto_rico" in n for n in names))
        self.assertTrue(any("cell_edge" in n for n in names))
        self.assertTrue(any(v["lon"] < 0 for v in self.vectors))

    def test_all_vectors_match(self):
        for v in self.vectors:
            lat = float(v["lat"])
            lon = float(v["lon"])
            wm_x, wm_y = grid.latlon_to_wm(lat, lon)
            cx, cy = grid.latlon_to_cell(lat, lon)
            self.assertAlmostEqual(
                wm_x, float(v["wm_x"]), places=6, msg=f"wm_x mismatch on {v['name']}"
            )
            self.assertAlmostEqual(
                wm_y, float(v["wm_y"]), places=6, msg=f"wm_y mismatch on {v['name']}"
            )
            self.assertEqual(cx, int(v["cell_x"]), msg=f"cell_x mismatch on {v['name']}")
            self.assertEqual(cy, int(v["cell_y"]), msg=f"cell_y mismatch on {v['name']}")

            # Round-trip wm_to_latlon
            rt_lat, rt_lon = grid.wm_to_latlon(wm_x, wm_y)
            self.assertAlmostEqual(rt_lat, lat, places=6, msg=f"rt_lat mismatch on {v['name']}")
            self.assertAlmostEqual(rt_lon, lon, places=6, msg=f"rt_lon mismatch on {v['name']}")

    def test_ground_distance_and_cell_center(self):
        cx, cy = grid.latlon_to_cell(47.6000, -122.3300)
        lat1, lon1 = grid.cell_center_latlon(cx, cy)
        lat2, lon2 = grid.cell_center_latlon(cx + 1, cy)
        d = grid.ground_distance_m(lat1, lon1, lat2, lon2)
        self.assertAlmostEqual(d, 172.6, delta=1.0)


if __name__ == "__main__":
    unittest.main()
