#!/usr/bin/env python3
"""
tools/test_build_places_pack.py — Unit tests for tools/build_places_pack.py
Contract:
  - docs/implementation_plan_explore_here.md §1.5
  - docs/agent_execution_guide.md §6 (F55 & F67 falsifiers)
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_places_pack as bpp  # noqa: E402
import grid  # noqa: E402


def _wm_box_geom(x0: float, y0: float, x1: float, y1: float):
    pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
    out = []
    for x, y in pts:
        lat, lon = grid.wm_to_latlon(x, y)
        out.append({"lat": round(lat, 7), "lon": round(lon, 7)})
    return out


class TestBuildPlacesPack(unittest.TestCase):
    def setUp(self):
        self.repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.fixture_cache = os.path.join(self.repo_root, "tools", "testdata", "overpass_fixture")
        self.fixture_config = os.path.join(
            self.repo_root, "game", "tests", "fixtures", "famous_places_fixture.json"
        )

    def test_1_falsifying_f55_ward_ignored_three_points(self):
        """
        Falsifying (F55): a city with an admin_level=9 ward covering everything,
        plus three neighbourhood points. The pack has 3 areas, never 1 ward.
        """
        with tempfile.TemporaryDirectory() as tmp:
            cfg = [
                {
                    "id": "city:ward-test",
                    "name": "Ward Test City",
                    "region": "test",
                    "kind": "city",
                    "osm_boundary": "r8001",
                    "waypost": {"name": "City Hall", "lat": 0.01, "lon": 0.01},
                }
            ]
            cfg_path = os.path.join(tmp, "places.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f)

            # 6x6 cells [2..7, 2..7]
            b_geom = _wm_box_geom(512.0, 512.0, 2048.0, 2048.0)
            with open(os.path.join(tmp, "r8001_boundary.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {
                                "type": "relation",
                                "id": 8001,
                                "tags": {
                                    "type": "boundary",
                                    "boundary": "administrative",
                                    "admin_level": "8",
                                    "name": "Ward Test City",
                                },
                                "members": [{"type": "way", "ref": 1, "role": "outer", "geometry": b_geom}],
                            }
                        ]
                    },
                    f,
                )

            # Rule 1 file contains an admin_level=9 ward covering everything
            with open(os.path.join(tmp, "r8001_rule1.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {
                                "type": "relation",
                                "id": 8009,
                                "tags": {
                                    "type": "boundary",
                                    "boundary": "administrative",
                                    "admin_level": "9",
                                    "name": "Ward 1",
                                },
                                "members": [{"type": "way", "ref": 2, "role": "outer", "geometry": b_geom}],
                            }
                        ]
                    },
                    f,
                )

            # Rule 2 file contains 3 neighbourhood points
            p1 = grid.wm_to_latlon(1152.0, 1920.0)
            p2 = grid.wm_to_latlon(1152.0, 1152.0)
            p3 = grid.wm_to_latlon(1920.0, 1152.0)
            with open(os.path.join(tmp, "r8001_rule2.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {"type": "node", "id": 101, "lat": p1[0], "lon": p1[1], "tags": {"place": "neighbourhood", "name": "Alpha"}},
                            {"type": "node", "id": 102, "lat": p2[0], "lon": p2[1], "tags": {"place": "neighbourhood", "name": "Beta"}},
                            {"type": "node", "id": 103, "lat": p3[0], "lon": p3[1], "tags": {"place": "neighbourhood", "name": "Gamma"}},
                        ]
                    },
                    f,
                )

            pack, stats = bpp.build_pack(cfg_path, tmp, offline=True)
            city = pack["places"][0]
            area_keys = [a["key"] for a in city["areas"]]
            self.assertEqual(len(city["areas"]), 3)
            self.assertEqual(area_keys, ["osm:n101", "osm:n102", "osm:n103"])
            self.assertNotIn("osm:r8009", area_keys)
            self.assertEqual(stats["city:ward-test"]["polygon_areas"], 0)
            self.assertEqual(stats["city:ward-test"]["point_areas"], 3)

    def test_2_smaller_polygon_wins_over_larger_admin10(self):
        """
        A place=neighbourhood polygon inside an admin_level=10 polygon:
        the cells inside both go to the smaller one.
        """
        with tempfile.TemporaryDirectory() as tmp:
            cfg = [
                {
                    "id": "city:nested-test",
                    "name": "Nested Test City",
                    "region": "test",
                    "kind": "city",
                    "osm_boundary": "r7001",
                    "waypost": {"name": "City Hall", "lat": 0.01, "lon": 0.01},
                }
            ]
            cfg_path = os.path.join(tmp, "places.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f)

            # 4x4 city: [512..1536] x [512..1536] -> cells 2..5 x 2..5 (16 cells)
            city_geom = _wm_box_geom(512.0, 512.0, 1536.0, 1536.0)
            # admin_level=10 covering all 16 cells (lower OSM id 10, larger area)
            big_admin10 = _wm_box_geom(512.0, 512.0, 1536.0, 1536.0)
            # place=neighbourhood way covering 2x2 cells [512..1024] x [512..1024] (higher OSM id 500, smaller area)
            small_nhood = _wm_box_geom(512.0, 512.0, 1024.0, 1024.0)

            with open(os.path.join(tmp, "r7001_boundary.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {
                                "type": "relation",
                                "id": 7001,
                                "tags": {"boundary": "administrative", "admin_level": "8", "name": "Nested Test City"},
                                "members": [{"type": "way", "ref": 1, "role": "outer", "geometry": city_geom}],
                            }
                        ]
                    },
                    f,
                )

            with open(os.path.join(tmp, "r7001_rule1.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {
                                "type": "relation",
                                "id": 10,
                                "tags": {"boundary": "administrative", "admin_level": "10", "name": "Big Borough"},
                                "members": [{"type": "way", "ref": 2, "role": "outer", "geometry": big_admin10}],
                            },
                            {
                                "type": "way",
                                "id": 500,
                                "tags": {"place": "neighbourhood", "name": "Pocket Green"},
                                "geometry": small_nhood,
                            },
                        ]
                    },
                    f,
                )

            with open(os.path.join(tmp, "r7001_rule2.json"), "w", encoding="utf-8") as f:
                json.dump({"elements": []}, f)

            pack, _ = bpp.build_pack(cfg_path, tmp, offline=True)
            city = pack["places"][0]
            decoded = bpp.decode_rows(city["rows"])
            idx_to_key = {i: a["key"] for i, a in enumerate(city["areas"])}

            # Cells (2,2), (2,3), (3,2), (3,3) must belong to osm:w500 (Pocket Green)
            for cx in (2, 3):
                for cy in (2, 3):
                    self.assertEqual(idx_to_key[decoded[(cx, cy)]], "osm:w500")
            # Remaining 12 cells must belong to osm:r10 (Big Borough)
            for (cx, cy), a_idx in decoded.items():
                if cx not in (2, 3) or cy not in (2, 3):
                    self.assertEqual(idx_to_key[a_idx], "osm:r10")

    def test_3_grid_districts_when_no_polygons_or_points(self):
        """
        Cells beyond every polygon, with no points, form grid:<city id>:<floor(cx/4)>:<floor(cy/4)> districts.
        """
        with tempfile.TemporaryDirectory() as tmp:
            cfg = [
                {
                    "id": "city:grid-city",
                    "name": "Grid City",
                    "region": "test",
                    "kind": "city",
                    "osm_boundary": "r6001",
                    "waypost": {"name": "City Hall", "lat": 0.01, "lon": 0.01},
                }
            ]
            cfg_path = os.path.join(tmp, "places.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f)

            # 6x6 cells [2..7, 2..7] -> spans floor(cx/4) in {0, 1}, floor(cy/4) in {0, 1} -> 4 grid districts
            city_geom = _wm_box_geom(512.0, 512.0, 2048.0, 2048.0)
            with open(os.path.join(tmp, "r6001_boundary.json"), "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "elements": [
                            {
                                "type": "relation",
                                "id": 6001,
                                "tags": {"boundary": "administrative", "admin_level": "8", "name": "Grid City"},
                                "members": [{"type": "way", "ref": 1, "role": "outer", "geometry": city_geom}],
                            }
                        ]
                    },
                    f,
                )
            with open(os.path.join(tmp, "r6001_rule1.json"), "w", encoding="utf-8") as f:
                json.dump({"elements": []}, f)
            with open(os.path.join(tmp, "r6001_rule2.json"), "w", encoding="utf-8") as f:
                json.dump({"elements": []}, f)

            pack, stats = bpp.build_pack(cfg_path, tmp, offline=True)
            city = pack["places"][0]
            keys = [a["key"] for a in city["areas"]]
            self.assertEqual(
                keys,
                [
                    "grid:city:grid-city:0:0",
                    "grid:city:grid-city:0:1",
                    "grid:city:grid-city:1:0",
                    "grid:city:grid-city:1:1",
                ],
            )
            self.assertEqual(stats["city:grid-city"]["grid_areas"], 4)

    def test_4_overlapping_places_fail_with_exit_1_naming_both_ids(self):
        """
        Two overlapping places -> exit 1, naming both ids.
        """
        with tempfile.TemporaryDirectory() as tmp:
            cfg = [
                {
                    "id": "site:alpha-park",
                    "name": "Alpha Park",
                    "region": "test",
                    "kind": "site",
                    "osm_boundary": "r5001",
                    "waypost": {"name": "Alpha VC", "lat": 0.01, "lon": 0.01},
                },
                {
                    "id": "site:beta-park",
                    "name": "Beta Park",
                    "region": "test",
                    "kind": "site",
                    "osm_boundary": "r5002",
                    "waypost": {"name": "Beta VC", "lat": 0.01, "lon": 0.01},
                },
            ]
            cfg_path = os.path.join(tmp, "places.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f)

            geom = _wm_box_geom(512.0, 512.0, 1024.0, 1024.0)
            for rid, rname in [(5001, "Alpha Park"), (5002, "Beta Park")]:
                with open(os.path.join(tmp, f"r{rid}_boundary.json"), "w", encoding="utf-8") as f:
                    json.dump(
                        {
                            "elements": [
                                {
                                    "type": "relation",
                                    "id": rid,
                                    "tags": {"boundary": "national_park", "name": rname},
                                    "members": [{"type": "way", "ref": 1, "role": "outer", "geometry": geom}],
                                }
                            ]
                        },
                        f,
                    )

            out_gz = os.path.join(tmp, "out.json.gz")
            proc = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    os.path.join(self.repo_root, "tools", "build_places_pack.py"),
                    "--config",
                    cfg_path,
                    "--cache-dir",
                    tmp,
                    "--out",
                    out_gz,
                    "--sha256-out",
                    "",
                    "--companion-out",
                    "",
                    "--offline",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 1)
            combined = proc.stdout + proc.stderr
            self.assertIn("site:alpha-park", combined)
            self.assertIn("site:beta-park", combined)

    def test_5_two_runs_byte_identical_and_rows_round_trip(self):
        """
        Two runs from the same cache -> byte-identical output.
        The rows round-trip: decoding gives the exact inside cells.
        """
        with tempfile.TemporaryDirectory() as tmp:
            out1 = os.path.join(tmp, "pack1.json.gz")
            out2 = os.path.join(tmp, "pack2.json.gz")
            for out_path in (out1, out2):
                proc = subprocess.run(
                    [
                        sys.executable,
                        "-I",
                        os.path.join(self.repo_root, "tools", "build_places_pack.py"),
                        "--config",
                        self.fixture_config,
                        "--cache-dir",
                        self.fixture_cache,
                        "--out",
                        out_path,
                        "--sha256-out",
                        "",
                        "--companion-out",
                        "",
                        "--offline",
                    ],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc.returncode, 0, msg=proc.stderr)

            with open(out1, "rb") as f1, open(out2, "rb") as f2:
                b1 = f1.read()
                b2 = f2.read()
            self.assertEqual(b1, b2)

            pack, _ = bpp.build_pack(self.fixture_config, self.fixture_cache, offline=True)
            city = next(p for p in pack["places"] if p["id"] == "city:fixture-city")
            park = next(p for p in pack["places"] if p["id"] == "site:fixture-park")

            city_cells = bpp.decode_rows(city["rows"])
            park_cells = bpp.decode_rows(park["rows"])

            expected_city_cells = {(cx, cy) for cx in range(2, 8) for cy in range(2, 8)}
            expected_park_cells = {(cx, cy) for cx in range(9, 13) for cy in range(3, 7)}
            self.assertEqual(set(city_cells.keys()), expected_city_cells)
            self.assertEqual(set(park_cells.keys()), expected_park_cells)

    def test_6_f67_falsifier_acadia_old_vs_new_boundary(self):
        """
        F67 falsifier (agent guide §6):
        validate_boundary_element fails on the old id of site:acadia (r1257404)
        and passes on the new one (r2176999).
        """
        old_place = {
            "id": "site:acadia",
            "kind": "site",
            "name": "Acadia National Park (ME)",
            "osm_boundary": "r1257404",
        }
        # Old relation r1257404 in OSM is either missing at 261001 or an unrelated route relation
        with self.assertRaises(ValueError):
            bpp.validate_boundary_element(old_place, {"elements": []})
        with self.assertRaises(ValueError):
            bpp.validate_boundary_element(
                old_place,
                {
                    "elements": [
                        {
                            "type": "relation",
                            "id": 1257404,
                            "tags": {"type": "route", "route": "bus", "name": "Line 12"},
                        }
                    ]
                },
            )

        new_place = {
            "id": "site:acadia",
            "kind": "site",
            "name": "Acadia National Park (ME)",
            "osm_boundary": "r2176999",
        }
        el = bpp.validate_boundary_element(
            new_place,
            {
                "elements": [
                    {
                        "type": "relation",
                        "id": 2176999,
                        "tags": {
                            "type": "boundary",
                            "boundary": "protected_area",
                            "name": "Acadia National Park",
                        },
                    }
                ]
            },
        )
        self.assertEqual(el["id"], 2176999)


if __name__ == "__main__":
    unittest.main()
