#!/usr/bin/env python3
"""
Tenth Spring — tests for tools/rom_spike/emerald/rom_spike.py and Rule-B emerald_tile_map.json checks.

Two halves:
- ROM-free tests check rs.gap_rules / rs.lookup_entry and verify Rule-B invariants on
  game/config/emerald_tile_map.json (empty buildings/compositions, no classes 12..14,
  object_sprites 25..28 offsets, indoor_kits/indoor_fixtures shape, no private paths).
- ROM-gated tests (requiring TENTH_SPRING_ROM_GBA outside the repo; run via memguard step
  rom_spike_gba) verify ROM preconditions, tileset decoding, palette validation + falsifier,
  metatile rendering, and PNG output.
"""

import hashlib
import json
import os
import re
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys  # noqa: E402

sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "rom_spike", "emerald"))
import rom_spike as rs  # noqa: E402

MAP_PATH = os.path.join(REPO_ROOT, "game", "config", "emerald_tile_map.json")
NEUTRAL_KEY_RE = re.compile(r"^[a-z0-9_]+$")
PRIVATE_TEXT_RE = re.compile(r"/Users/|TENTH_SPRING_ROM_|\.gba\b|\.nds\b")


def check_palettes(tilesets):
    """Validate that every tileset holds 16-colour RGB palettes with channels in 0..255."""
    problems = []
    for key, ts in sorted(tilesets.items()):
        for pidx, pal in enumerate(ts.palettes):
            if len(pal) != 16:
                problems.append(f"{key} palette {pidx} has {len(pal)} colours (expected 16)")
                continue
            for cidx, rgb in enumerate(pal):
                if len(rgb) != 3 or any((not isinstance(ch, int) or ch < 0 or ch > 255) for ch in rgb):
                    problems.append(f"{key} palette {pidx} colour {cidx} out of range: {rgb!r}")
    return problems


class GapRuleTests(unittest.TestCase):
    """Pure functions: no ROM needed."""

    def test_gap_rules_cover_class_variant_and_mask(self):
        mapping = {"gaps": [
            {"id": "whole", "classes": [9], "reason": "r"},
            {"id": "some_masks", "classes": [4], "masks": [5, 10], "reason": "r"},
            {"id": "one_variant", "classes": [7], "variants": [1], "reason": "r"},
            {"id": "bare_text_is_ignored_in_old_tables", "reason": "r"},
            "snow_terrain",
        ]}
        rules = rs.gap_rules(mapping)
        self.assertTrue(rs.in_gap(rules, 9, 0, 3))
        self.assertTrue(rs.in_gap(rules, 4, 0, 5))
        self.assertFalse(rs.in_gap(rules, 4, 0, 6))
        self.assertTrue(rs.in_gap(rules, 7, 1, 15))
        self.assertFalse(rs.in_gap(rules, 7, 0, 15))
        self.assertFalse(rs.in_gap(rules, 1, 0, 0))

    def test_lookup_entry_by_class_variant_mask(self):
        tile_map = {"4": {"0": {"15": {"metatile": 9}}}, "5": {"0": {"0": {"metatile": 8}}}}
        self.assertEqual(rs.lookup_entry(tile_map, 4, 0, 15)["metatile"], 9)
        self.assertIsNone(rs.lookup_entry(tile_map, 4, 0, 14))
        self.assertEqual(rs.lookup_entry(tile_map, 5, 0, 0)["metatile"], 8)


class RuleBTableChecks(unittest.TestCase):
    """ROM-free structural and Rule-B invariants on game/config/emerald_tile_map.json."""

    @classmethod
    def setUpClass(cls):
        with open(MAP_PATH, encoding="utf-8") as f:
            cls.raw_text = f.read()
        cls.mapping = json.loads(cls.raw_text)

    def test_rule_b_keeps_buildings_and_compositions_empty(self):
        self.assertEqual(self.mapping.get("buildings"), {})
        self.assertEqual(self.mapping.get("compositions"), {})
        tmap = self.mapping.get("tile_map", {})
        for forbidden_cls in ("12", "13", "14"):
            self.assertNotIn(forbidden_cls, tmap)

    def test_object_sprites_have_integer_offsets(self):
        objs = self.mapping.get("object_sprites", {})
        for cls_key in ("25", "26", "27", "28"):
            self.assertIn(cls_key, objs)
            spec = objs[cls_key]
            for field in ("frame_offset", "palette_offset", "base_metatile"):
                self.assertIsInstance(spec.get(field), int, f"object_sprites[{cls_key}].{field}")
                self.assertFalse(isinstance(spec.get(field), bool))

    def test_indoor_kits_and_fixtures_are_neutral_and_well_formed(self):
        kits = self.mapping.get("indoor_kits", {})
        self.assertTrue(kits)
        for kit_id, kit_def in kits.items():
            self.assertRegex(kit_id, NEUTRAL_KEY_RE, kit_id)
            for req in ("void", "wall_upper", "wall_lower", "floor", "door_mat_2x1", "stairs_up_3x2", "stairs_down_3x2", "rug_3x3"):
                self.assertIn(req, kit_def, f"{kit_id} missing {req}")

        fixtures = self.mapping.get("indoor_fixtures", {})
        self.assertTrue(fixtures)
        for fx_id, fx_def in fixtures.items():
            self.assertRegex(fx_id, NEUTRAL_KEY_RE, fx_id)
            self.assertIsInstance(fx_def.get("w"), int)
            self.assertIsInstance(fx_def.get("h"), int)
            self.assertIsInstance(fx_def.get("base_rows"), int)
            cells = fx_def.get("cells", [])
            self.assertEqual(len(cells), fx_def["h"], fx_id)
            for row in cells:
                self.assertEqual(len(row), fx_def["w"], fx_id)

    def test_tileset_keys_and_no_private_paths(self):
        self.assertIsNone(PRIVATE_TEXT_RE.search(self.raw_text))
        tsets = self.mapping.get("tilesets", {})
        self.assertEqual(tsets.get("primary"), 0)
        for key, val in tsets.items():
            self.assertIsInstance(val, int)
            if key != "primary":
                self.assertEqual(key, rs.sec_key(val))
        self.assertEqual(set(rs.tileset_indices_of(self.mapping)), {v for k, v in tsets.items() if k != "primary"})


class TestSpikeFoundations(unittest.TestCase):
    """ROM-gated spike checks (skipped unless TENTH_SPRING_ROM_GBA is set)."""

    @classmethod
    def setUpClass(cls):
        if not os.environ.get("TENTH_SPRING_ROM_GBA"):
            raise unittest.SkipTest("[SKIP] TENTH_SPRING_ROM_GBA not set. Emerald ROM tests skipped.")
        cls.rom_data = rs.check_preconditions()
        with open(MAP_PATH, encoding="utf-8") as f:
            cls.mapping = json.load(f)
        indices = tuple(sorted(set(rs.FEATURED_SECONDARY_INDICES) | set(rs.tileset_indices_of(cls.mapping))))
        cls.tilesets = rs.load_tilesets(cls.rom_data, indices)
        cls.primary_ts = cls.tilesets["primary"]

    def test_preconditions(self):
        """ROM preconditions: header code BPEE, exact SHA-1, path outside repo."""
        self.assertEqual(self.rom_data[0xAC:0xB0], rs.EXPECTED_HEADER)
        self.assertEqual(hashlib.sha1(self.rom_data).hexdigest().lower(), rs.EXPECTED_SHA1)
        real_rom = os.path.realpath(os.path.expanduser(os.environ["TENTH_SPRING_ROM_GBA"]))
        self.assertFalse(real_rom.startswith(os.path.realpath(REPO_ROOT)), "ROM path must be outside repo")

    def test_primary_tileset_structure(self):
        """Primary tileset offset 0x3DF704, 512 metatiles, tiles decompress to 16,384 bytes."""
        self.assertEqual(self.primary_ts.offset, rs.PRIMARY_TILESET_OFFSET)
        self.assertEqual(self.primary_ts.num_metatiles, 512)
        self.assertEqual(self.primary_ts.tiles_offset, 0xDD5010)
        self.assertEqual(self.primary_ts.pal_offset, 0xDD4E10)
        self.assertEqual(self.primary_ts.meta_offset, 0x3960F0)
        self.assertEqual(self.primary_ts.attr_offset, 0x3980F0)
        self.assertEqual(len(self.primary_ts.tiles_raw), 16384)
        self.assertEqual(len(self.primary_ts.palettes), 16)

    def test_attribute_words_use_only_documented_bits(self):
        """Behaviour byte is bits 0-7 and layer type bits 12-15; bits 8-11 are unused."""
        for key, ts in self.tilesets.items():
            stray = [i for i, a in enumerate(ts.attributes) if a & 0x0F00]
            self.assertEqual(stray, [], f"{key} has attribute bits 8-11 set on metatiles {stray[:5]}")

    def test_palette_color_count_and_range(self):
        """Every palette has 16 RGB colours in 0..255, and a shortened palette fails."""
        self.assertEqual(check_palettes(self.tilesets), [])

        class Short:
            palettes = [[(0, 0, 0)] * 15] + [[(0, 0, 0)] * 16 for _ in range(15)]

        problems = check_palettes({"primary": Short()})
        self.assertTrue(any("primary palette 0" in p for p in problems), problems)

    def test_wrong_palette_rejection(self):
        """Falsifying: zeroing green fails the lawn's green-dominance check."""
        entry = self.mapping["tile_map"]["1"]["0"]["0"]
        metatile = entry["metatile"]
        key = entry.get("tileset", "primary")

        class Corrupted:
            def __init__(self, ts):
                self.tiles_raw = ts.tiles_raw
                self.metatiles_raw = ts.metatiles_raw
                self.num_metatiles = ts.num_metatiles
                self.palettes = [[(r, 0, b) for r, _g, b in pal] for pal in ts.palettes]

        corrupted = {k: Corrupted(t) for k, t in self.tilesets.items()}
        good = rs.render_entry(self.tilesets, metatile, key)
        bad = rs.render_entry(corrupted, metatile, key)

        def mean_gr(canvas):
            px = rs.canvas_pixels(canvas)
            return sum(p[1] for p in px) / 256.0, sum(p[0] for p in px) / 256.0

        g, r = mean_gr(good)
        self.assertGreater(g, r, "real lawn is green-dominant")
        g, r = mean_gr(bad)
        self.assertFalse(g > r, "corrupted palette must fail green-dominance")

    def test_write_png_rows_writes_valid_png(self):
        canvas = rs.render_entry(self.tilesets, self.mapping["tile_map"]["1"]["0"]["0"]["metatile"], "primary")
        rows = [b"".join(bytes(rgb) for rgb in row) for row in canvas]
        with tempfile.TemporaryDirectory() as td:
            out_png = os.path.join(td, "lawn.png")
            rs.write_png_rows(out_png, 16, 16, rows)
            with open(out_png, "rb") as f:
                data = f.read()
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
            self.assertGreater(len(data), 40)


if __name__ == "__main__":
    unittest.main()
