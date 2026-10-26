#!/usr/bin/env python3
"""
Tenth Spring — tests for the Emerald (Game Boy Advance) tile spike and its mapping table
(agent guide Items 12 and 12b)
Contract: docs/agent_execution_guide.md §3
          docs/implementation_plan_rom_tiles.md §3
          docs/design_rom_asset_pipeline.md §4, §5, §7

Two halves. The ROM-free tests (no TENTH_SPRING_ROM_GBA) check the table's structure and prove that
each structural rule can fail; they also run in CI through game/tests/test_runner.py. The ROM-gated
tests need the player's own dump (outside the repo) and are skipped without it, so CI, which never
has a ROM, passes. Run the ROM-gated half under python3 -I, through tools/memguard.py, step
rom_spike_gba.

What the tests prove
- The spike decodes the tilesets correctly (header, structure, palettes, a wrong palette fails).
- Every rule in mapping_checks.py holds for game/config/emerald_tile_map.json, and the ROM's own
  layouts back the choices (the lawn is among the ROM's most used pieces; each pond edge piece sits
  at the neighbour mask the table gives it).
- Each rule FAILS on the pass-22 choices (F60) and on single-entry mutations of the new table, and
  each falsifier names the entry it mutated, so a rule that passes means something.
"""

import copy
import hashlib
import json
import os
import re
import sys
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "rom_spike", "emerald"))

import mapping_checks as mc  # noqa: E402
import rom_spike as rs  # noqa: E402

MAP_PATH = os.path.join(REPO_ROOT, "game", "config", "emerald_tile_map.json")
PLACEHOLDER_JSON = os.path.join(REPO_ROOT, "game", "assets", "tiles", "placeholder_v1.json")
SPIKE_OUT = os.path.expanduser("~/.tenth_spring_rom_spike/emerald")

# The pass-22 choices (F60): numbers only. Every rule must reject them.
PASS22 = {
    "grass_variants": {0: 1, 1: 2, 2: 3, 3: 1},
    "water_interior": 44, "water_edge": 52,
    "tall_grass_edge": 37,
    "grave_and_sign": 33, "sand_and_marsh": 76,
    "rail_and_road": 290, "bridge_road": 288, "one_roof_for_all_colours": 521,
}


def _used_secondary_indices(mapping):
    """Secondary tileset indices named anywhere in the table."""
    keys = set(mapping.get("tilesets", {}))
    for _c, _v, _m, entry in mc.iter_entries(mapping):
        keys.add(entry.get("tileset", "primary"))
    for comp in mapping.get("compositions", {}).values():
        keys.add(comp.get("tileset", "primary"))
    for bld in mapping.get("buildings", {}).values():
        for spec in bld.get("roof_colors", {}).values():
            keys.add(spec.get("tileset", "primary"))
    out = {int(k[3:]) for k in keys if re.match(r"^sec\d\d$", k)}
    out |= set(rs.tileset_indices_of(mapping))
    return tuple(sorted(out))


def named(problems, *needles):
    """The problems that mention every needle."""
    return [p for p in problems if all(n in p for n in needles)]


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


class RomFreeCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(MAP_PATH) as f:
            cls.mapping = json.load(f)
        with open(PLACEHOLDER_JSON) as f:
            cls.placeholder_rows = json.load(f)["rows"]

    def assertNoProblems(self, problems):
        self.assertEqual(problems, [], "\n  " + "\n  ".join(problems))

    def mutated(self):
        return copy.deepcopy(self.mapping)


class TableWithoutRomTests(RomFreeCase):
    """The structural rules of the committed table need no ROM, so they run in CI too: numbers
    and ids only, neutral names, coverage, no unlisted shares, gaps without entries, the derived
    buildings, door and grid structure of the compositions, and primary-range bounds."""

    def test_table_holds_numbers_and_ids_only(self):
        self.assertNoProblems(mc.check_table_shape(self.mapping))

    def test_names_are_neutral_and_tilesets_listed(self):
        self.assertNoProblems(mc.check_neutral_names(self.mapping))

    def test_every_synthesised_tile_is_mapped_or_a_gap(self):
        self.assertNoProblems(mc.check_coverage(self.mapping, self.placeholder_rows))

    def test_no_unlisted_shared_metatiles(self):
        self.assertNoProblems(mc.check_no_unlisted_shared(self.mapping))

    def test_no_entry_for_a_gap(self):
        self.assertNoProblems(mc.check_gaps_have_no_entries(self.mapping))

    def test_compositions_have_a_valid_structure(self):
        self.assertNoProblems(mc.check_compositions(None, self.mapping))

    def test_bounds_without_the_rom(self):
        self.assertNoProblems(mc.check_bounds(None, self.mapping))

    def test_buildings_are_derived_from_the_tile_map(self):
        self.assertNoProblems(mc.check_buildings(self.mapping))

    def test_rejects_a_pass22_style_table(self):
        """A version-1 table with place-named keys, bare-string gaps and a colour string fails."""
        old = {"version": 1, "tilesets": {"alpha_town": 1}, "tile_map": {}, "buildings": {},
               "compositions": {"town_hall": {"w": 1, "h": 1, "tileset": "alpha_town", "door": [], "metatiles": [1]}},
               "gaps": ["snow_terrain"], "color": "#ffffff"}
        self.assertTrue(mc.check_table_shape(old))
        self.assertTrue(mc.check_neutral_names(old))
        self.assertTrue(mc.check_gaps_have_no_entries(old))


class StructuralRulesRejectWrongTables(RomFreeCase):
    """Falsifying cases for the rules that need no ROM: each mutates ONE thing, and the check must
    name it. A rule that cannot fail would prove nothing."""

    @staticmethod
    def two_classes_on_one_piece(cls_a, cls_b, metatile, listed):
        m = {"tile_map": {str(cls_a): {"0": {"0": {"metatile": metatile}}},
                          str(cls_b): {"0": {"0": {"metatile": metatile}}}}, "shared": []}
        if listed:
            m["shared"] = [{"metatile": metatile, "tileset": "primary", "classes": [cls_a, cls_b], "reason": "test reason"}]
        return m

    def test_shared_rejects_grave_and_sign_on_one_piece(self):
        m = self.two_classes_on_one_piece(17, 18, PASS22["grave_and_sign"], listed=False)
        self.assertTrue(named(mc.check_no_unlisted_shared(m), "metatile 33", "[17, 18]"))

    def test_shared_accepts_a_listed_share(self):
        m = self.two_classes_on_one_piece(17, 18, PASS22["grave_and_sign"], listed=True)
        self.assertEqual(mc.check_no_unlisted_shared(m), [])

    def test_shared_rejects_a_stale_listing(self):
        m = self.two_classes_on_one_piece(17, 18, PASS22["grave_and_sign"], listed=True)
        m["tile_map"]["17"]["0"]["0"]["metatile"] = 34
        m["tile_map"]["18"]["0"]["0"]["metatile"] = 35
        self.assertTrue(named(mc.check_no_unlisted_shared(m), "no two classes use it"))

    def test_shared_rejects_rail_on_a_road_piece(self):
        m = self.two_classes_on_one_piece(8, 9, PASS22["rail_and_road"], listed=False)
        self.assertTrue(named(mc.check_no_unlisted_shared(m), "metatile 290", "[8, 9]"))

    def test_shared_rejects_marsh_on_the_sand_piece(self):
        m = self.two_classes_on_one_piece(5, 6, PASS22["sand_and_marsh"], listed=False)
        self.assertTrue(named(mc.check_no_unlisted_shared(m), "metatile 76", "[5, 6]"))

    def test_shared_ignores_a_stray_tileset_key_on_a_primary_piece(self):
        """A primary-range metatile is a primary piece whatever tileset key it carries."""
        m = {"tile_map": {"17": {"0": {"0": {"metatile": 33}}},
                          "18": {"0": {"0": {"metatile": 33, "tileset": "sec05"}}}}, "shared": []}
        self.assertTrue(named(mc.check_no_unlisted_shared(m), "metatile 33"))

    def test_gaps_reject_an_entry_for_a_gap(self):
        m = self.mutated()
        m["gaps"] = list(m["gaps"]) + [{"id": "probe_gap", "classes": [9], "reason": "a probe gap reason"}]
        m["tile_map"].setdefault("9", {}).setdefault("0", {})["5"] = {"metatile": 1}
        self.assertTrue(named(mc.check_gaps_have_no_entries(m), "class 9 variant 0 mask 5"))

    def test_gaps_reject_a_wildcard_entry_under_a_masked_gap(self):
        m = {"tile_map": {"4": {"0": {"*": {"metatile": 1}}}},
             "gaps": [{"id": "some_masks", "classes": [4], "masks": [5], "reason": "a masked gap reason"}]}
        self.assertTrue(named(mc.check_gaps_have_no_entries(m), "class 4", "mask *"))

    def test_gap_shape_is_checked(self):
        m = {"tile_map": {}, "gaps": [
            {"id": "empty_classes", "classes": [], "reason": "a long enough reason"},
            {"id": "wide_mask", "classes": [4], "masks": [16], "reason": "a long enough reason"},
            {"id": "boolean_class", "classes": [True], "reason": "a long enough reason"},
            {"id": "empty_masks", "classes": [4], "masks": [], "reason": "a long enough reason"},
            {"id": "short_reason", "classes": [4], "reason": "r"},
            {"id": "twice", "classes": [4], "reason": "a long enough reason"},
            {"id": "twice", "classes": [5], "reason": "a long enough reason"},
        ]}
        problems = mc.check_gaps_have_no_entries(m)
        for gap_id in ("empty_classes", "wide_mask", "boolean_class", "empty_masks", "short_reason"):
            self.assertTrue(named(problems, gap_id), "%s must be flagged: %s" % (gap_id, problems))
        self.assertTrue(named(problems, "twice", "used twice"))

    def wrong(self, cls, var, mask, metatile, tileset="primary"):
        m = self.mutated()
        m["tile_map"].setdefault(str(cls), {}).setdefault(str(var), {})[str(mask)] = {"metatile": metatile}
        if tileset != "primary":
            m["tile_map"][str(cls)][str(var)][str(mask)]["tileset"] = tileset
        return m

    def test_bounds_reject_ids_and_keys_that_do_not_exist(self):
        self.assertTrue(named(mc.check_bounds(None, self.wrong(1, 0, 0, 9999)), "9999"))
        self.assertTrue(named(mc.check_bounds(None, self.wrong(1, 0, 0, 700)), "700", "primary"))
        self.assertTrue(named(mc.check_bounds(None, self.wrong(1, 0, 0, -1)), "-1"))
        self.assertTrue(named(mc.check_bounds(None, self.wrong(1, 0, 0, 600, "sec99")), "sec99"))
        self.assertTrue(named(mc.check_bounds(None, self.wrong(1, 0, 0, 600, "sec00")), "sec00"))

    def test_coverage_rejects_a_missing_mask_and_a_missing_sign_variant(self):
        m = self.mutated()
        gaps = rs.gap_rules(m)
        victim = next(k for k in ("15", "10", "9", "8") if not rs.in_gap(gaps, int(k), 0, 7))
        m["tile_map"][victim]["0"].pop("7", None)
        self.assertTrue(named(mc.check_coverage(m, self.placeholder_rows), "class %s variant 0 mask 7" % victim))
        m = self.mutated()
        m["tile_map"]["18"].pop("15")
        self.assertTrue(named(mc.check_coverage(m, self.placeholder_rows), "class 18 variant 15"))

    def test_compositions_reject_structural_errors(self):
        m = self.mutated()
        first = next(iter(m["compositions"]))
        m["compositions"][first]["metatiles"] = m["compositions"][first]["metatiles"][:-1]
        m["compositions"]["town_name"] = copy.deepcopy(m["compositions"][first])
        problems = mc.check_compositions(None, m)
        self.assertTrue(named(problems, first, "metatiles for"))
        self.assertTrue(named(problems, "town_name", "neutral"))
        m = self.mutated()
        del m["compositions"]["stadium"]
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "missing"))
        m = self.mutated()
        m["compositions"]["stadium"]["door"] = [99, 99]
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "outside"))
        m = self.mutated()
        m["compositions"]["stadium"]["door"] = []
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "no door"))
        m = self.mutated()
        m["compositions"]["stadium"]["door"] = [3]
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "door must be"))
        m = self.mutated()
        m["compositions"]["stadium"].update({"w": 0, "h": 0, "metatiles": []})
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "at least 1"))
        m = {"compositions": {"stadium": {"metatiles": [1, 2]}}}
        self.assertTrue(named(mc.check_compositions(None, m), "stadium", "needs integer w and h"))

    def test_the_raised_road_may_have_no_door(self):
        self.assertEqual(self.mapping["compositions"]["elevated_road"]["door"], [])
        self.assertNoProblems(mc.check_compositions(None, self.mapping))

    def test_names_reject_place_keys_and_a_wrong_tileset_block(self):
        m = self.mutated()
        m["tilesets"] = dict(m["tilesets"], alpha_town=5)
        self.assertTrue(named(mc.check_neutral_names(m), "alpha_town"))
        m = self.mutated()
        m["tilesets"]["sec05"] = 9
        self.assertTrue(named(mc.check_neutral_names(m), "sec05", "index"))
        m = self.mutated()
        del m["tilesets"]["sec05"]
        self.assertTrue(named(mc.check_neutral_names(m), "sec05", "not listed"))
        m = self.mutated()
        m["tilesets"]["sec33"] = 33
        self.assertTrue(named(mc.check_neutral_names(m), "sec33", "nothing uses it"))
        m = self.mutated()
        m["tilesets"]["sec99"] = 99
        self.assertTrue(named(mc.check_neutral_names(m), "sec99"))

    def test_forbidden_place_words_are_caught_by_hash(self):
        """The list holds only hashes; a word whose hash is on it fails in any id or reason."""
        word = "zorblax"
        saved = mc.FORBIDDEN_WORD_HASHES
        try:
            mc.FORBIDDEN_WORD_HASHES = saved | {hashlib.sha1(word.encode()).hexdigest()}
            m = self.mutated()
            m["gaps"] = list(m["gaps"]) + [{"id": "probe", "classes": [9], "reason": "a note about the %s district" % word}]
            self.assertTrue(named(mc.check_neutral_names(m), "probe", "forbidden"))
            m = self.mutated()
            m["buildings"]["%s_hall" % word] = m["buildings"].pop("house_s")
            self.assertTrue(named(mc.check_neutral_names(m), "building", "forbidden"))
            self.assertEqual(mc.check_neutral_names(self.mapping), [])
        finally:
            mc.FORBIDDEN_WORD_HASHES = saved

    def test_buildings_must_match_the_tile_map(self):
        m = self.mutated()
        m["buildings"]["house_s"]["roof_colors"]["0"]["metatiles"][0] = 161
        self.assertTrue(named(mc.check_buildings(m), "differs"))

    def test_shape_rejects_wildcards_blobs_and_loose_types(self):
        m = {"version": 2, "tile_map": {"4": {"0": {"*": {"metatile": 1}, "3": {"metatile": 1, "pixels": "00"}}}},
             "gaps": [{"id": "x", "classes": [4], "reason": "<script>#abc"}]}
        problems = mc.check_table_shape(m)
        self.assertTrue(named(problems, "wildcard"))
        self.assertTrue(named(problems, "{metatile, tileset?}"))
        self.assertTrue(named(problems, "plain ASCII"))
        m = self.mutated()
        m["buildings"]["town_hall"] = m["buildings"]["house_s"]
        m["buildings"]["house_m"]["w"] = "wide"
        problems = mc.check_table_shape(m)
        self.assertTrue(named(problems, "town_hall", "is not one of"))
        self.assertTrue(named(problems, "house_m", "w and h are integers"))

    def test_roof_gap_path_requires_a_reason_for_every_unmapped_variant(self):
        """Guide §3 step 4: fewer than four colourways is allowed if the gaps say why."""
        base = {"tile_map": {}, "gaps": []}
        self.assertTrue(mc.check_roof_colourways({"primary": object()}, base))
        base["gaps"] = [{"id": "roof_colourways_missing", "classes": [12], "reason": "the tilesets have none"}]
        self.assertEqual(mc.check_roof_colourways({"primary": object()}, base), [])


class EmeraldRomTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get("TENTH_SPRING_ROM_GBA"):
            raise unittest.SkipTest("[SKIP] TENTH_SPRING_ROM_GBA not set. Emerald ROM tests skipped.")
        cls.rom_data = rs.check_preconditions()
        with open(MAP_PATH) as f:
            cls.mapping = json.load(f)
        with open(PLACEHOLDER_JSON) as f:
            cls.placeholder_rows = json.load(f)["rows"]
        indices = tuple(sorted(set(rs.FEATURED_SECONDARY_INDICES) | set(_used_secondary_indices(cls.mapping))))
        cls.tilesets = rs.load_tilesets(cls.rom_data, indices)
        cls.primary_ts = cls.tilesets["primary"]

    def assertNoProblems(self, problems):
        self.assertEqual(problems, [], "\n  " + "\n  ".join(problems))

    def mutated(self):
        return copy.deepcopy(self.mapping)

    def wrong(self, cls, var, mask, metatile, tileset="primary"):
        m = self.mutated()
        m["tile_map"].setdefault(str(cls), {}).setdefault(str(var), {})[str(mask)] = {"metatile": metatile}
        if tileset != "primary":
            m["tile_map"][str(cls)][str(var)][str(mask)]["tileset"] = tileset
        return m

    def entry_of(self, cls, var, mask):
        e = self.mapping["tile_map"][str(cls)][str(var)][str(mask)]
        return e["metatile"], e.get("tileset", "primary")


class TestSpikeFoundations(EmeraldRomTestCase):
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
        """The behaviour byte is bits 0-7 and the layer type bits 12-15; bits 8-11 are unused in
        every tileset the table names (design_rom_asset_pipeline.md §4)."""
        for key, ts in self.tilesets.items():
            stray = [i for i, a in enumerate(ts.attributes) if a & 0x0F00]
            self.assertEqual(stray, [], "%s has attribute bits 8-11 set on metatiles %s" % (key, stray[:5]))

    def test_palette_color_count_and_range(self):
        """Every palette has exactly 16 colours (so a 4-bpp tile cannot use more), each channel in 0..255."""
        self.assertEqual(mc.check_palettes(self.tilesets), [])
        for ts in self.tilesets.values():
            for pal in ts.palettes:
                self.assertEqual(len(pal), 16)

    def test_palette_check_rejects_a_short_palette(self):
        class Short:
            palettes = [[(0, 0, 0)] * 15] + [[(0, 0, 0)] * 16 for _ in range(15)]

        self.assertTrue(named(mc.check_palettes({"primary": Short()}), "primary palette 0"))

    def test_wrong_palette_rejection(self):
        """Falsifying: tilesets whose palettes have the green zeroed out fail the lawn's
        green-dominance check, for whichever tileset holds the base lawn."""
        metatile, key = self.entry_of(1, 0, 0)

        class Corrupted:
            def __init__(self, ts):
                self.tiles_raw = ts.tiles_raw
                self.metatiles_raw = ts.metatiles_raw
                self.num_metatiles = ts.num_metatiles
                self.palettes = [[(r, 0, b) for r, g, b in pal] for pal in ts.palettes]

        corrupted = {k: Corrupted(t) for k, t in self.tilesets.items()}
        good = rs.render_entry(self.tilesets, metatile, key)
        bad = rs.render_entry(corrupted, metatile, key)

        def mean_gr(canvas):
            px = rs.canvas_pixels(canvas)
            return sum(p[1] for p in px) / 256.0, sum(p[0] for p in px) / 256.0

        g, r = mean_gr(good)
        self.assertGreater(g, r, "the real lawn is green-dominant")
        g, r = mean_gr(bad)
        self.assertFalse(g > r, "a corrupted palette must fail the lawn's green-dominance check")


class TestMappingRules(EmeraldRomTestCase):
    """Every rule of mapping_checks.py holds for the committed table."""

    def test_grass_variants_are_plain_lawn(self):
        self.assertNoProblems(mc.check_grass(self.tilesets, self.mapping))

    def test_water_interior_and_shores(self):
        self.assertNoProblems(mc.check_water(self.tilesets, self.mapping))

    def test_tall_grass_pieces(self):
        self.assertNoProblems(mc.check_tall_grass(self.tilesets, self.mapping))

    def test_bridge_pieces(self):
        self.assertNoProblems(mc.check_bridge(self.tilesets, self.mapping))

    def test_sand_and_soil_pieces(self):
        self.assertNoProblems(mc.check_ground_behaviours(self.tilesets, self.mapping))

    def test_palettes(self):
        self.assertNoProblems(mc.check_palettes(self.tilesets))

    def test_no_unlisted_shared_pixels(self):
        """Metatiles that draw identical pixels count as one piece."""
        self.assertNoProblems(mc.check_no_unlisted_shared(self.mapping, self.tilesets))

    def test_metatiles_are_inside_their_tilesets(self):
        self.assertNoProblems(mc.check_bounds(self.tilesets, self.mapping))

    def test_roofs_have_distinct_colourways(self):
        self.assertNoProblems(mc.check_roof_colourways(self.tilesets, self.mapping))

    def test_building_pieces(self):
        self.assertNoProblems(mc.check_building_pieces(self.tilesets, self.mapping))

    def test_compositions_are_valid_and_neutral(self):
        self.assertNoProblems(mc.check_compositions(self.tilesets, self.mapping))

    def test_the_whole_table_passes_every_check(self):
        results = mc.run_all(self.tilesets, self.mapping, self.placeholder_rows)
        failed = {name: problems for name, problems in results.items() if problems}
        self.assertEqual(failed, {})

    def test_layout_evidence_for_the_lawn(self):
        """The base lawn is among the ROM's five most used pieces, by the ROM's own layouts."""
        counts = rs.frequency(list(rs.iter_map_layouts(self.rom_data)))
        base, _key = self.entry_of(1, 0, 0)
        ranked = sorted(counts, key=counts.get, reverse=True)
        self.assertLessEqual(ranked.index(base), 4, "the base lawn is one of the five most used pieces")

    def test_layout_evidence_for_water_edges(self):
        """The ROM itself places each mapped pond edge piece at the neighbour mask the table gives
        it: the piece's most common measured mask in the layouts equals its mask."""
        layouts = list(rs.iter_map_layouts(self.rom_data))
        water = {mid for mid in range(rs.PRIMARY_METATILE_COUNT)
                 if self.primary_ts.behaviour(mid) in rs.WATER_BEHAVIOURS}
        gaps = rs.gap_rules(self.mapping)
        checked = 0
        for mask in range(15):
            entry = rs.lookup_entry(self.mapping["tile_map"], 4, 0, mask)
            if entry is None or rs.in_gap(gaps, 4, 0, mask):
                continue
            piece = entry["metatile"]
            stats = rs.neighbour_stats(layouts, lambda key: key in water, {piece})
            measured = {m: by_piece.get(piece, 0) for m, by_piece in stats.items()}
            if not measured:
                continue
            best = max(measured, key=measured.get)
            share = measured[best] / float(sum(measured.values()))
            self.assertEqual(best, mask, "piece %d is mapped at mask %d but the ROM places it at mask %d" % (piece, mask, best))
            self.assertGreaterEqual(share, 0.6, "piece %d: only %.0f%% of its cells have mask %d" % (piece, share * 100, mask))
            checked += 1
        self.assertGreaterEqual(checked, 6, "the evidence check covered too few water edge pieces")

    def test_spike_outputs_exist_outside_repo(self):
        """The spike's images exist in ~/.tenth_spring_rom_spike/emerald/ (never in the repo)."""
        expected = ["primary_labelled.png", "preview.png", "table_ground.png", "table_buildings.png",
                    "compositions.png"]
        if self.mapping.get("buildings"):
            expected.append("buildings.png")
        expected += ["%s_labelled.png" % rs.sec_key(i) for i in _used_secondary_indices(self.mapping)]
        for name in expected:
            path = os.path.join(SPIKE_OUT, name)
            self.assertTrue(os.path.exists(path), "output missing: %s (run rom_spike.py)" % name)
            self.assertGreater(os.path.getsize(path), 1024, "%s is too small" % name)


class TestRulesRejectWrongTables(EmeraldRomTestCase):
    """Falsifying cases for the rules that read the ROM. Each mutates ONE entry of the committed
    table, with a real piece chosen so that only the named sub-rule can catch it."""

    # --- lawn ---------------------------------------------------------------------------
    def test_grass_rejects_the_pass22_variants(self):
        for var, mid in PASS22["grass_variants"].items():
            if mid == PASS22["grass_variants"][0]:
                continue
            problems = mc.check_grass(self.tilesets, self.wrong(1, var, 0, mid))
            self.assertTrue(named(problems, "variant %d" % var, "metatile %d" % mid),
                            "pass-22 lawn variant %d (metatile %d) must be named: %s" % (var, mid, problems))

    def test_grass_rejects_an_object_painted_over_the_lawn(self):
        """Piece 462 is 91% lawn colours, so only the top-layer rule isolates it."""
        problems = mc.check_grass(self.tilesets, self.wrong(1, 1, 0, 462))
        self.assertTrue(named(problems, "variant 1", "paints an object"), problems)

    def test_grass_rejects_a_corner_wedge_of_another_object(self):
        """Pieces 259, 261, and 275 are 91-92% lawn colours with a blank top layer; the compact patch rule catches them."""
        for piece in (259, 261, 275):
            problems = mc.check_grass(self.tilesets, self.wrong(1, 1, 0, piece))
            self.assertTrue(named(problems, "variant 1", "patch of"), "piece %d: %s" % (piece, problems))

    def test_grass_rejects_a_green_piece_with_another_behaviour(self):
        """Piece 21 (long grass) is green and blank-topped but is not plain lawn."""
        problems = mc.check_grass(self.tilesets, self.wrong(1, 1, 0, 21))
        self.assertTrue(named(problems, "variant 1", "behaviour"), problems)

    # --- water --------------------------------------------------------------------------
    def test_water_rejects_an_edge_piece_as_interior(self):
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, PASS22["water_interior"]))
        self.assertTrue(named(problems, "mask 15", "metatile %d" % PASS22["water_interior"]), problems)

    def test_water_rejects_plain_water_where_a_shore_is_needed(self):
        interior, ikey = self.entry_of(4, 0, 15)
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 14, interior, ikey))
        self.assertTrue(named(problems, "mask 14 ", "side N", "should show a shore"), problems)

    def test_water_rejects_a_shore_piece_in_the_interior_slot(self):
        """Mask 15's slot holding a one-shore piece: its shore side must fail 'continue the water'."""
        mid, key = self.entry_of(4, 0, 14)
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, mid, key))
        self.assertTrue(named(problems, "mask 15 ", "side N", "should continue"), problems)

    def test_water_rejects_the_wrong_side(self):
        """Mask 14's piece (shore north) placed in mask 13's slot (shore east) must fail both ways."""
        mid, key = self.entry_of(4, 0, 14)
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 13, mid, key))
        self.assertTrue(named(problems, "mask 13 ", "side E", "should show a shore"), problems)
        self.assertTrue(named(problems, "mask 13 ", "side N", "should continue"), problems)

    def test_water_rejects_a_waterfall_a_sea_piece_and_a_non_water_piece(self):
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, 76))  # waterfall behaviour
        self.assertTrue(named(problems, "mask 15", "standing-water"), problems)
        # The sea's colour is not the pond's: with a sea interior, every pond edge draws its water in other colours.
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, 368))
        self.assertTrue(named(problems, "metatile 201", "interior's colours"), problems)
        lawn, lkey = self.entry_of(1, 0, 0)
        problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, lawn, lkey))
        self.assertTrue(named(problems, "mask 15", "standing-water"), problems)

    # --- tall grass, sand, bridge -------------------------------------------------------
    def test_tall_grass_rejects_the_bush_piece(self):
        problems = mc.check_tall_grass(self.tilesets, self.wrong(2, 0, 3, PASS22["tall_grass_edge"]))
        self.assertTrue(named(problems, "metatile %d" % PASS22["tall_grass_edge"], "object"), problems)

    def test_tall_grass_rejects_a_lawn_piece(self):
        lawn, lkey = self.entry_of(1, 0, 0)
        problems = mc.check_tall_grass(self.tilesets, self.wrong(2, 0, 3, lawn, lkey))
        self.assertTrue(named(problems, "mask 3", "behaviour"), problems)

    def test_tall_grass_rejects_a_wrong_decode_or_palette(self):
        """Tilesets with the green zeroed fail green-dominance; flattened tile data fails variance."""

        class Altered:
            def __init__(self, ts, palettes=None, tiles=None):
                self.tiles_raw = tiles if tiles is not None else ts.tiles_raw
                self.metatiles_raw = ts.metatiles_raw
                self.num_metatiles = ts.num_metatiles
                self.palettes = palettes if palettes is not None else ts.palettes
                self.attributes = ts.attributes
                self.behaviour = ts.behaviour

        no_green = {k: Altered(t, palettes=[[(r, 0, b) for r, g, b in pal] for pal in t.palettes]) for k, t in self.tilesets.items()}
        flat = {k: Altered(t, tiles=bytes(len(t.tiles_raw))) for k, t in self.tilesets.items()}
        self.assertTrue(named(mc.check_tall_grass(no_green, self.mapping), "green-dominant"))
        self.assertTrue(named(mc.check_tall_grass(flat, self.mapping), "variance"))

    def test_sand_and_crop_reject_a_piece_without_their_behaviour(self):
        lawn, lkey = self.entry_of(1, 0, 0)
        self.assertTrue(named(mc.check_ground_behaviours(self.tilesets, self.wrong(5, 0, 0, lawn, lkey)), "class 5", "sand behaviour"))
        self.assertTrue(named(mc.check_ground_behaviours(self.tilesets, self.wrong(19, 0, 0, lawn, lkey)), "class 19", "crop behaviour"))

    def test_bridge_rejects_a_road_or_lawn_piece(self):
        lawn, lkey = self.entry_of(1, 0, 0)
        self.assertTrue(named(mc.check_bridge(self.tilesets, self.wrong(10, 0, 7, lawn, lkey)), "mask 7", "bridge behaviour"))
        self.assertTrue(named(mc.check_bridge(self.tilesets, self.wrong(10, 0, 7, PASS22["bridge_road"])), "mask 7"))

    def test_bridge_rejects_one_piece_for_both_orientations(self):
        mid, key = self.entry_of(10, 0, 7)  # a north-south deck piece
        problems = mc.check_bridge(self.tilesets, self.wrong(10, 0, 14, mid, key))  # in an east-west slot
        self.assertTrue(named(problems, "north-south and an east-west"), problems)

    # --- shared pieces and pixels -------------------------------------------------------
    def test_shared_rejects_pixel_identical_twins_under_two_numbers(self):
        """Footpath interior 289 and sand 292 draw the same pixels: without a listing it is a share."""
        m = self.mutated()
        m["shared"] = []
        problems = mc.check_no_unlisted_shared(m, self.tilesets)
        self.assertTrue(named(problems, "[5, 7]", "identical pixels"), problems)
        self.assertEqual(mc.check_no_unlisted_shared(self.mapping, self.tilesets), [])

    # --- bounds -------------------------------------------------------------------------
    def test_bounds_reject_an_id_past_a_secondary(self):
        key = next(k for k in self.tilesets if k != "primary")
        past = rs.PRIMARY_METATILE_COUNT + self.tilesets[key].num_metatiles
        self.assertTrue(named(mc.check_bounds(self.tilesets, self.wrong(1, 0, 0, past, key)), str(past), "past the end"))

    def test_bounds_reject_a_piece_that_references_a_missing_tile(self):
        """A few metatiles reference tiles past their tileset's tile data and would render blank."""
        for key in sorted(k for k in self.tilesets if k != "primary"):
            for local in range(self.tilesets[key].num_metatiles):
                mid = rs.PRIMARY_METATILE_COUNT + local
                if not mc._tile_exists(self.tilesets, mid, key):
                    problems = mc.check_bounds(self.tilesets, self.wrong(1, 0, 0, mid, key))
                    self.assertTrue(named(problems, str(mid), "past the end of the tile data"), problems)
                    return
        self.skipTest("every metatile of the loaded tilesets has its tiles")

    # --- buildings and compositions -----------------------------------------------------
    def test_roofs_reject_one_roof_for_every_colour(self):
        m = self.mutated()
        for var in range(8):
            for mask in range(16):
                m["tile_map"].setdefault("12", {}).setdefault(str(var), {})[str(mask)] = {"metatile": PASS22["one_roof_for_all_colours"]}
        m["gaps"] = [g for g in m["gaps"] if not (isinstance(g, dict) and 12 in g.get("classes", []))]
        self.assertTrue(named(mc.check_roof_colourways(self.tilesets, m), "distinct roof colourways"))

    def test_building_pieces_reject_a_non_roof_piece_and_a_copied_variant(self):
        problems = mc.check_building_pieces(self.tilesets, self.wrong(12, 0, 15, 44))  # a water piece as a roof
        self.assertTrue(named(problems, "class 12 variant 0 mask 15", "ROOF behaviour"), problems)
        problems = mc.check_building_pieces(self.tilesets, self.wrong(14, 0, 0, 44))  # a water piece as a door
        self.assertTrue(named(problems, "class 14", "DOOR behaviour"), problems)
        m = self.mutated()
        m["tile_map"]["12"]["4"] = copy.deepcopy(m["tile_map"]["12"]["0"])
        self.assertTrue(named(mc.check_building_pieces(self.tilesets, m), "ROOF variants 0 and 4", "same pieces"))

    def test_compositions_reject_a_door_that_is_not_a_door(self):
        for cid, comp in sorted(self.mapping["compositions"].items()):
            if not comp.get("door"):
                continue
            x, y = comp["door"]
            m = self.mutated()
            lawn, _k = self.entry_of(1, 0, 0)
            m["compositions"][cid]["metatiles"][y * comp["w"] + x] = lawn
            self.assertTrue(named(mc.check_compositions(self.tilesets, m), cid, "not a door"))
            m["compositions"][cid]["metatiles"][y * comp["w"] + x] = 36  # an arrow warp (0x65), not a door
            m["compositions"][cid]["tileset"] = "primary" if all(v < 512 for v in m["compositions"][cid]["metatiles"]) else comp["tileset"]
            self.assertTrue(named(mc.check_compositions(self.tilesets, m), cid, "not a door"))
            return


class _Canvases:
    """Context manager: renders chosen metatiles as crafted canvases, so one sub-rule can be tested
    in isolation (no real piece is both over a threshold for one rule and clean for every other)."""

    def __init__(self, overrides):
        self.overrides = overrides

    def __enter__(self):
        self.real = mc._render
        overrides, real = self.overrides, self.real

        def render(tilesets, entry):
            canvas = overrides.get(mc.entry_key(entry))
            return canvas if canvas is not None else real(tilesets, entry)

        mc._render = render
        return self

    def __exit__(self, *exc):
        mc._render = self.real
        return False


class TestThresholdsInIsolation(EmeraldRomTestCase):
    """Each numeric threshold, tested alone with a crafted canvas for an otherwise valid piece."""

    def unused_piece(self, predicate):
        used = {mc.entry_key(e) for _c, _v, _m, e in mc.iter_entries(self.mapping)}
        for mid in range(rs.PRIMARY_METATILE_COUNT):
            if (mid, "primary") not in used and predicate(mid):
                return mid
        self.fail("no unused primary piece matches")

    def water_piece(self):
        return self.unused_piece(lambda mid: self.primary_ts.behaviour(mid) in rs.WATER_BEHAVIOURS
                                 and rs.top_layer_blank(self.tilesets, mid, "primary"))

    def canvas_of(self, cls, var, mask):
        mid, key = self.entry_of(cls, var, mask)
        return [list(row) for row in rs.render_entry(self.tilesets, mid, key)]

    NON_WATER = (200, 120, 40)

    def test_grass_share_rule_alone(self):
        """A lawn with 20% isolated speckles: no compact patch, ordinary behaviour, blank top."""
        piece = self.unused_piece(lambda mid: self.primary_ts.behaviour(mid) == 0
                                  and rs.top_layer_blank(self.tilesets, mid, "primary"))
        canvas = self.canvas_of(1, 0, 0)
        for y in range(16):
            for x in range(16):
                if (x + 2 * y) % 5 == 0:
                    canvas[y][x] = (1, 2, 3)
        with _Canvases({(piece, "primary"): canvas}):
            problems = mc.check_grass(self.tilesets, self.wrong(1, 1, 0, piece))
        self.assertTrue(named(problems, "variant 1", "of its pixels from the lawn's colours"), problems)
        self.assertFalse(named(problems, "patch of"), problems)

    def test_water_interior_share_rule_alone(self):
        """22 stray pixels, few enough in each region to pass the side, corner, and centre rules, but 91% in all."""
        piece = self.water_piece()
        canvas = self.canvas_of(4, 0, 15)
        for x in (5, 6, 7):
            canvas[0][x] = canvas[15][x] = self.NON_WATER   # 3 per band, each side
        for y in (5, 6, 7):
            canvas[y][0] = canvas[y][15] = self.NON_WATER
        for cy, cx in ((0, 0), (0, 15), (15, 0), (15, 15)):
            canvas[cy][cx] = self.NON_WATER                  # 1 per corner square
        for y, x in ((5, 5), (5, 8), (6, 6), (8, 5), (9, 9), (10, 6)):
            canvas[y][x] = self.NON_WATER                    # 6 in the centre
        with _Canvases({(piece, "primary"): canvas}):
            problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, piece))
        self.assertTrue(named(problems, "mask 15", "water-coloured (interior needs"), problems)
        self.assertFalse(named(problems, "side"), problems)
        self.assertFalse(named(problems, "corner square"), problems)
        self.assertFalse(named(problems, "centre"), problems)

    def test_water_corner_rule_alone(self):
        piece = self.water_piece()
        canvas = self.canvas_of(4, 0, 15)
        for y in range(0, 4):
            for x in range(0, 2):
                canvas[y][x] = self.NON_WATER                # half of one 4x4 corner square
        with _Canvases({(piece, "primary"): canvas}):
            problems = mc.check_water(self.tilesets, self.wrong(4, 0, 15, piece))
        self.assertTrue(named(problems, "mask 15", "corner square"), problems)
        self.assertFalse(named(problems, "centre"), problems)

    def test_water_centre_rule_alone(self):
        piece = self.water_piece()
        canvas = self.canvas_of(4, 0, 14)
        for y in range(6, 10):
            for x in range(6, 10):
                canvas[y][x] = self.NON_WATER                # a 4x4 blob in the middle (25% of the centre)
        with _Canvases({(piece, "primary"): canvas}):
            problems = mc.check_water(self.tilesets, self.wrong(4, 0, 14, piece))
        self.assertTrue(named(problems, "mask 14", "in its centre"), problems)

    def test_water_shore_rule_alone(self):
        """A hairline shore (4 of the 32 pixels of the north band) is not a shore."""
        piece = self.water_piece()
        interior = self.canvas_of(4, 0, 15)
        for x in range(4, 8):
            interior[0][x] = self.NON_WATER
        with _Canvases({(piece, "primary"): interior}):
            problems = mc.check_water(self.tilesets, self.wrong(4, 0, 14, piece))
        self.assertTrue(named(problems, "mask 14", "side N", "should show a shore"), problems)

    def test_water_containment_rule_alone(self):
        """Water pixels in a colour the interior does not use (a darker water) leave a seam."""
        piece = self.water_piece()
        canvas = self.canvas_of(4, 0, 14)
        for y in range(6, 8):
            for x in range(6, 12):
                canvas[y][x] = (10, 20, 200)                  # still blue-dominant, but not the pond's blue
        with _Canvases({(piece, "primary"): canvas}):
            problems = mc.check_water(self.tilesets, self.wrong(4, 0, 14, piece))
        self.assertTrue(named(problems, "mask 14", "interior's colours"), problems)

    def test_wall_rejects_a_non_wall_piece(self):
        self.assertTrue(named(mc.check_building_pieces(self.tilesets, self.wrong(13, 0, 14, 44)), "class 13", "WALL behaviour"))


if __name__ == "__main__":
    unittest.main()
