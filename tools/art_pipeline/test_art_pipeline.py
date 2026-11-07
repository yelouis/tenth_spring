#!/usr/bin/env python3
"""test_art_pipeline.py — repository-safe tests for the art pipeline (tools/art_pipeline/).

50 tests covering PNG reading/writing, conversion, generation problem checks,
technical checks, style metrics, and originality checks.
Zero dependency on docs/ or catalogue.json.
"""

import os
import random
import struct
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art_lib as al  # noqa: E402
import recolour_tiles as rt  # noqa: E402
import validate_art as va  # noqa: E402

MAGENTA = (255, 0, 255, 255)

ROOF = [(232, 128, 104), (200, 80, 72), (152, 56, 56)]
WALL = [(248, 240, 224), (216, 200, 176)]
OUTLINE_ROOF, OUTLINE_WALL = (112, 48, 48), (104, 88, 80)
WINDOW, DOOR = (104, 176, 224), (96, 64, 40)


def synthetic_house(w=64, h=64, outline=None):
    """A crisp, original pixel-art house: flat tones, light from the upper left, tinted outline."""
    img = al.Image(w, h)
    roof_h = h // 2
    for y in range(h):
        for x in range(w):
            if y < roof_h:
                band = (y // 4) % 2
                c = ROOF[0] if (x + y) < (w // 2) and band == 0 else (ROOF[1] if y < roof_h - 4 else ROOF[2])
            else:
                c = WALL[0] if y < h - 6 else WALL[1]
            img.set(x, y, c + (255,))
    for wx in (6, w - 18):
        for y in range(roof_h + 6, roof_h + 16):
            for x in range(wx, wx + 10):
                img.set(x, y, WINDOW + (255,))
    for y in range(h - 16, h):
        for x in range(16, 32):
            img.set(x, y, DOOR + (255,))
    for x in range(w):
        for y in (0, h - 1):
            img.set(x, y, (outline or (OUTLINE_ROOF if y == 0 else OUTLINE_WALL)) + (255,))
    for y in range(h):
        for x in (0, w - 1):
            img.set(x, y, (outline or (OUTLINE_ROOF if y < roof_h else OUTLINE_WALL)) + (255,))
    return img


def ai_like(sprite, k=12, margin=48, noise=3, seed=1, soften=True):
    """What a generator returns at best: the sprite drawn large, soft block borders, faint noise,
    on a flat magenta background."""
    big = sprite.scaled(k)
    if soften:
        for y in range(big.h):
            for x in range(1, big.w):
                if x % k == 0:
                    a, b = big.get(x - 1, y), big.get(x, y)
                    m = tuple((a[i] + b[i]) // 2 for i in range(3)) + (255,)
                    big.set(x - 1, y, m)
                    big.set(x, y, m)
    rnd = random.Random(seed)
    out = al.Image(big.w + 2 * margin, big.h + 2 * margin)
    out.fill(MAGENTA)
    for y in range(big.h):
        for x in range(big.w):
            c = big.get(x, y)
            if c[3] < 128:
                continue
            out.set(x + margin, y + margin, tuple(max(0, min(255, c[i] + rnd.randint(-noise, noise))) for i in range(3)) + (255,))
    return out


def blur(img, r):
    out = img.copy()
    for y in range(img.h):
        for x in range(img.w):
            acc = [0, 0, 0]
            n = 0
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < img.w and 0 <= yy < img.h:
                        c = img.get(xx, yy)
                        for i in range(3):
                            acc[i] += c[i]
                        n += 1
            out.set(x, y, tuple(a // n for a in acc) + (255,))
    return out


def write_filtered_rgb_png(path, rows_rgb, filter_types):
    """A PNG writer that uses the given filter per row, so the reader's unfiltering is tested."""
    h, w = len(rows_rgb), len(rows_rgb[0])
    bpp, raw, prev = 3, bytearray(), bytearray(w * 3)
    for y, row in enumerate(rows_rgb):
        line = bytearray(v for px in row for v in px)
        ft = filter_types[y % len(filter_types)]
        out = bytearray(len(line))
        for i in range(len(line)):
            left = line[i - bpp] if i >= bpp else 0
            up = prev[i]
            ul = prev[i - bpp] if i >= bpp else 0
            pred = {0: 0, 1: left, 2: up, 3: (left + up) >> 1, 4: al._paeth(left, up, ul)}[ft]
            out[i] = (line[i] - pred) & 255
        raw.append(ft)
        raw.extend(out)
        prev = line
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(al.PNG_SIG + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


class PngTests(unittest.TestCase):
    def test_rgba_round_trip(self):
        img = synthetic_house()
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.png")
            al.write_png(p, img)
            self.assertEqual(al.read_png(p).px, img.px)

    def test_every_filter_type_decodes(self):
        rnd = random.Random(7)
        rows = [[(rnd.randint(0, 255), rnd.randint(0, 255), rnd.randint(0, 255)) for _ in range(13)] for _ in range(10)]
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f.png")
            write_filtered_rgb_png(p, rows, [0, 1, 2, 3, 4])
            img = al.read_png(p)
            for y in range(10):
                for x in range(13):
                    self.assertEqual(img.get(x, y), rows[y][x] + (255,))

    def test_non_png_is_refused_with_advice(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "x.jpg")
            with open(p, "wb") as f:
                f.write(b"\xff\xd8\xff\xe0 not a png")
            with self.assertRaisesRegex(ValueError, "sips"):
                al.read_png(p)


class ConvertTests(unittest.TestCase):
    def test_recovers_clean_pixel_art(self):
        house = synthetic_house()
        sprite, rep = al.convert(ai_like(house), 64, 64, mode="free")
        close = sum(1 for y in range(64) for x in range(64) if al.redmean(sprite.rgb(x, y), house.rgb(x, y)) <= 30)
        self.assertGreaterEqual(close / 4096.0, 0.95)
        self.assertGreaterEqual(rep["block_purity"], 0.9)

    def test_deterministic(self):
        raw = ai_like(synthetic_house())
        a, _ = al.convert(raw, 64, 64, mode="free")
        b, _ = al.convert(raw, 64, 64, mode="free")
        self.assertEqual(a.px, b.px)

    def test_rejects_wrong_proportions(self):
        with self.assertRaisesRegex(al.ConversionError, "proportions"):
            al.convert(ai_like(synthetic_house()), 96, 64, mode="free")

    def test_rejects_an_empty_picture(self):
        raw = al.Image(200, 200)
        raw.fill(MAGENTA)
        with self.assertRaisesRegex(al.ConversionError, "no foreground"):
            al.convert(raw, 64, 64)

    def test_flags_a_stray_mark_instead_of_cropping_it(self):
        raw = ai_like(synthetic_house(), margin=200)
        for y in range(raw.h - 40, raw.h - 10):
            for x in range(raw.w - 60, raw.w - 10):
                raw.set(x, y, (200, 200, 200, 255))
        sprite, rep = al.convert(raw, 64, 64)
        self.assertTrue(rep["strays"])
        checks = {c["name"]: c for c in al.technical_checks(sprite, spec(), rep)}
        self.assertFalse(checks["no_stray_content"]["ok"])

    def test_flags_a_mark_close_to_the_object(self):
        raw = ai_like(synthetic_house(), margin=200)
        for y in range(raw.h - 190, raw.h - 160):
            for x in range(raw.w - 190, raw.w - 150):
                raw.set(x, y, (220, 220, 220, 255))
        _sprite, rep = al.convert(raw, 64, 64)
        self.assertTrue(rep["strays"])

    def test_scattered_decal_pieces_are_kept_together(self):
        raw = al.Image(400, 400)
        raw.fill(MAGENTA)
        for (x0, y0) in ((120, 260), (200, 280), (260, 250)):
            for y in range(y0, y0 + 40):
                for x in range(x0, x0 + 40):
                    raw.set(x, y, (138, 122, 106, 255))
        _sprite, rep = al.convert(raw, 16, 16, fit="contain", margin=1)
        self.assertEqual(rep["strays"], [])

    def test_output_is_clean(self):
        sprite, _ = al.convert(ai_like(synthetic_house()), 64, 64, cap=12)
        alphas = {sprite.px[i] for i in range(3, len(sprite.px), 4)}
        self.assertTrue(alphas <= {0, 255})
        self.assertLessEqual(len(al._colour_counts(sprite)), 12)

    def test_free_mode_lifts_near_black(self):
        house = synthetic_house(outline=(8, 8, 12))
        sprite, rep = al.convert(ai_like(house), 64, 64, mode="free")
        self.assertGreater(rep["darks_lifted"], 0)
        self.assertGreaterEqual(min(al.hsv(c)[2] for c in al._colour_counts(sprite)), 0.25)

    def test_master_mode_uses_only_the_palette(self):
        pal = [(192, 80, 74), (138, 52, 48), (232, 224, 208), (168, 152, 128), (106, 176, 224), (74, 48, 24), al.INK]
        sprite, _ = al.convert(ai_like(synthetic_house()), 64, 64, mode="master", palette=pal)
        self.assertTrue(set(al._colour_counts(sprite)) <= set(pal))

    def test_close_colours_are_merged(self):
        img = al.Image(4, 1)
        for x, c in enumerate([(100, 100, 100), (104, 100, 100), (200, 50, 50), (200, 50, 50)]):
            img.set(x, 0, c + (255,))
        self.assertEqual(al.merge_close_colours(img, 40), 1)
        self.assertEqual(len(al._colour_counts(img)), 2)

    def test_detail_finer_than_the_grid_shows_as_low_purity(self):
        rnd = random.Random(9)
        busy = al.Image(48, 48)
        for y in range(48):
            for x in range(48):
                busy.set(x, y, rnd.choice([(200, 80, 72), (248, 240, 224), (104, 176, 224), (96, 64, 40)]) + (255,))
        sprite, rep = al.convert(ai_like(busy, k=4, soften=False), 16, 16, mode="free")
        self.assertLess(rep["block_purity"], 0.75)
        checks = {c["name"]: c for c in al.technical_checks(sprite, spec(size_px=[16, 16], size_tiles=[1, 1], door=None, min_fill=0.0), rep)}
        self.assertFalse(checks["drawn_at_pixel_scale"]["ok"])


def spec(**kw):
    s = {"size_px": [64, 64], "size_tiles": [4, 4], "colour_cap": 16, "key_colour": "#FF00FF", "outline": True,
         "min_fill": 0.9, "door": [1, 3], "door_dark_share": 0.3, "light_check": True, "symmetric": False}
    s.update(kw)
    return s


def synthetic_bush(n=12):
    """A small round bush with a dark outline and a highlight on its upper left."""
    img = al.Image(n, n)
    c = (n - 1) / 2.0
    for y in range(n):
        for x in range(n):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if d <= c + 0.3:
                col = (40, 88, 48) if d > c - 0.9 else ((120, 200, 96) if x + y < n - 3 else (72, 144, 64))
                img.set(x, y, col + (255,))
    return img


def framed(sprite, k=20, panel=(246, 242, 228), line=(80, 104, 176)):
    """The sprite drawn on a pale panel with a blue box line inside a magenta picture: a copied layout guide."""
    raw = al.Image(400, 400)
    raw.fill(MAGENTA)
    for y in range(24, 376):
        for x in range(24, 376):
            edge = min(x - 24, y - 24, 375 - x, 375 - y) < 4
            raw.set(x, y, (line if edge else panel) + (255,))
    big = sprite.scaled(k)
    raw.paste(big, (400 - big.w) // 2, 376 - 40 - big.h)
    return raw


def checks_by_name(sprite, sp, rep=None):
    return {c["name"]: c for c in al.technical_checks(sprite, sp, rep)}


class GenerationProblemTests(unittest.TestCase):
    """The ways the first local-model run went wrong (2026-10-27), each made by hand here."""

    def test_clean_decal_passes_the_background_and_edge_checks(self):
        sprite, rep = al.convert(ai_like(synthetic_bush(), k=20, margin=120), 16, 16, fit="contain", margin=1)
        c = checks_by_name(sprite, spec(size_px=[16, 16], size_tiles=[1, 1], door=None, min_fill=0.0), rep)
        self.assertTrue(c["background_clear"]["ok"], c["background_clear"])
        self.assertTrue(c["edge_not_pale"]["ok"], c["edge_not_pale"])
        self.assertTrue(c["colours_kept"]["ok"], c["colours_kept"])

    def test_copied_layout_panel_fails_the_edge_check(self):
        sprite, rep = al.convert(framed(synthetic_bush()), 16, 16, fit="contain", margin=1)
        c = checks_by_name(sprite, spec(size_px=[16, 16], size_tiles=[1, 1], door=None, min_fill=0.0), rep)
        self.assertFalse(c["edge_not_pale"]["ok"], c["edge_not_pale"])

    def test_painted_field_to_the_edge_fails_the_background_check(self):
        raw = ai_like(synthetic_house())
        for y in range(raw.h):
            for x in range(raw.w):
                if al.is_key(raw.get(x, y), (255, 0, 255)):
                    raw.set(x, y, (240, 214, 210, 255))
        sprite, rep = al.convert(raw, 64, 64)
        self.assertFalse(checks_by_name(sprite, spec(), rep)["background_clear"]["ok"])

    def test_object_cut_off_at_the_edge_fails_the_background_check(self):
        raw = ai_like(synthetic_house(), margin=48)
        cut = raw.crop(48, 0, raw.w, raw.h)  # the house now touches the left edge of the picture
        sprite, rep = al.convert(cut, 64, 64, aspect_tolerance=0.5)
        self.assertEqual(rep["subject_margin"], 0.0)
        self.assertFalse(checks_by_name(sprite, spec(), rep)["background_clear"]["ok"])

    def test_an_object_reaching_the_edge_fails_even_when_the_edge_is_mostly_background(self):
        raw = ai_like(synthetic_house(), margin=48)
        for y in range(0, 48):
            for x in range(raw.w // 2 - 3, raw.w // 2 + 3):
                raw.set(x, y, OUTLINE_ROOF + (255,))  # a thin mast up to the top of the picture
        sprite, rep = al.convert(raw, 64, 64)
        self.assertGreaterEqual(rep["border_background"], 0.95)
        self.assertFalse(checks_by_name(sprite, spec(), rep)["background_clear"]["ok"])

    def test_transparent_background_counts_as_background(self):
        raw = ai_like(synthetic_house())
        rnd = random.Random(4)
        for y in range(raw.h):
            for x in range(raw.w):
                if al.is_key(raw.get(x, y), (255, 0, 255)):
                    raw.set(x, y, (rnd.randint(0, 80), rnd.randint(0, 80), rnd.randint(0, 80), rnd.randint(0, 60)))
        sprite, rep = al.convert(raw, 64, 64)
        c = checks_by_name(sprite, spec(), rep)
        self.assertTrue(c["background_clear"]["ok"], c["background_clear"])
        self.assertEqual([n for n, v in c.items() if not v["ok"]], [])

    def test_a_shadow_drawn_on_the_magenta_is_background(self):
        # The third re-run's Library carried a dark magenta drop shadow (#52085A, 6% of the sprite) along its
        # edges: the model drew it on the background, and the converter kept it as part of the building.
        raw = ai_like(synthetic_house())
        k = raw.w // 64
        house_right, house_bottom = 56 * k, 60 * k
        for y in range(raw.h):
            for x in range(raw.w):
                in_shadow = (house_right <= x < house_right + 5 * k and 6 * k <= y < house_bottom + 3 * k) or \
                            (8 * k <= x < house_right + 5 * k and house_bottom <= y < house_bottom + 3 * k)
                if in_shadow and al.redmean(raw.get(x, y), (255, 0, 255)) < 110:  # on the background only
                    raw.set(x, y, (82, 8, 90, 255))
        for c in ((82, 8, 90), (120, 20, 130), (60, 4, 64)):
            self.assertTrue(al.is_key_shade(c, (255, 0, 255)), c)
        # purples and pinks a building or a flower may really use are not shades of the key
        for c in ((176, 136, 216), (90, 58, 122), (200, 80, 72), (16, 33, 74), (232, 128, 104), (160, 40, 120)):
            self.assertFalse(al.is_key_shade(c, (255, 0, 255)), c)
        self.assertTrue(al.is_key_shade((10, 90, 12), (0, 255, 0)))
        self.assertFalse(al.is_key_shade((58, 106, 48), (0, 255, 0)))
        sprite, rep = al.convert(raw, 64, 64)
        purple = sum(1 for y in range(64) for x in range(64)
                     if sprite.opaque(x, y) and al.hsv(sprite.rgb(x, y))[1] > 0.6 and 270 <= al.hsv(sprite.rgb(x, y))[0] * 360 <= 330)
        self.assertEqual(purple, 0)
        self.assertGreater(rep["shadow_removed"], 0)
        self.assertEqual([n for n, v in checks_by_name(sprite, spec(), rep).items() if not v["ok"]], [])

    def test_a_dark_shade_inside_the_object_is_kept(self):
        # A broken house's roof hole may be shaded in dark purple: enclosed by the house, it is not a shadow.
        raw = ai_like(synthetic_house())
        k = raw.w // 64
        for y in range(8 * k, 16 * k):
            for x in range(20 * k, 32 * k):
                raw.set(x, y, (60, 4, 64, 255))
        out, changed = al.shadows_to_background(raw, (255, 0, 255))
        self.assertEqual(changed, 0)
        sprite, rep = al.convert(raw, 64, 64)
        self.assertTrue(all(sprite.opaque(x, y) for y in range(9, 15) for x in range(21, 31)))

    def test_a_small_clearly_different_accent_survives_the_colour_cap(self):
        img = al.Image(64, 64)
        for y in range(64):
            for x in range(64):
                img.set(x, y, (80 + 4 * (y // 2),) * 3 + (255,))  # 32 near-identical greys
        for y in range(10, 14):
            for x in range(30, 35):
                img.set(x, y, (216, 176, 64, 255))  # 20 pixels of gold
        before = al._colour_counts(img)
        al.reduce_colours(img, 8)
        self.assertLessEqual(len(al._colour_counts(img)), 8)
        self.assertIn((216, 176, 64), al._colour_counts(img))
        self.assertEqual(al.lost_colours(before, img), [])

    def test_a_dropped_colour_is_reported(self):
        img = al.Image(40, 40)
        img.fill((150, 150, 150, 255))
        before = {(150, 150, 150): 1500, (216, 176, 64): 100}
        lost = al.lost_colours(before, img)
        self.assertEqual([c["colour"] for c in lost], ["#D8B040"])
        rep = {"strays": [], "block_purity": 1.0, "border_background": 1.0, "subject_margin": 0.1,
               "pale_edge_share": 0.0, "lost_colours": lost}
        self.assertFalse(checks_by_name(synthetic_house(), spec(), rep)["colours_kept"]["ok"])

    def test_a_roof_on_a_collapsed_house_fails(self):
        self.assertFalse(checks_by_name(synthetic_house(), spec(max_roof_share=0.12))["roof_gone"]["ok"])
        ruin = al.Image(64, 64)
        for y in range(64):
            for x in range(64):
                wall = x < 6 or x > 57 or y < 6 or y > 50
                ruin.set(x, y, ((150, 146, 140) if wall else (88, 152, 72)) + (255,))
        self.assertTrue(checks_by_name(ruin, spec(max_roof_share=0.12))["roof_gone"]["ok"])

    def test_records_from_before_these_checks_fail(self):
        rep = {"strays": [], "block_purity": 1.0}
        c = checks_by_name(synthetic_house(), spec(), rep)
        for name in ("background_clear", "edge_not_pale", "colours_kept"):
            self.assertFalse(c[name]["ok"], name)


class TechnicalCheckTests(unittest.TestCase):
    def checks(self, img, **kw):
        return {c["name"]: c for c in al.technical_checks(img, spec(**kw))}

    def test_a_dark_shade_of_the_key_left_in_a_sprite_fails(self):
        img = synthetic_house()
        for x in range(10, 50):
            img.set(x, 63, (82, 8, 90, 255))
        self.assertFalse(self.checks(img)["no_key_colour"]["ok"])

    def test_the_pixel_scale_limit_comes_from_the_asset(self):
        report = {"block_purity": 0.70, "border_background": 1.0, "subject_margin": 0.05, "pale_edge_share": 0.0,
                  "lost_colours": [], "strays": []}
        img = synthetic_house()
        strict = {c["name"]: c for c in al.technical_checks(img, spec(), report)}
        loose = {c["name"]: c for c in al.technical_checks(img, spec(min_purity=0.65), report)}
        self.assertFalse(strict["drawn_at_pixel_scale"]["ok"])
        self.assertTrue(loose["drawn_at_pixel_scale"]["ok"])

    def test_good_house_passes(self):
        c = self.checks(synthetic_house())
        failed = [n for n, v in c.items() if not v["ok"]]
        self.assertEqual(failed, [])

    def test_semi_transparent_pixel_fails(self):
        img = synthetic_house()
        img.set(5, 5, (200, 80, 72, 100))
        self.assertFalse(self.checks(img)["binary_alpha"]["ok"])

    def test_too_many_colours_fails(self):
        img = synthetic_house()
        for i in range(20):
            img.set(10 + i, 40, (10 * i, 120, 200, 255))
        self.assertFalse(self.checks(img)["colours"]["ok"])

    def test_leftover_magenta_fails(self):
        img = synthetic_house()
        img.set(30, 20, (250, 10, 245, 255))
        self.assertFalse(self.checks(img)["no_key_colour"]["ok"])

    def test_light_outline_fails(self):
        self.assertFalse(self.checks(synthetic_house(outline=(250, 250, 250)))["outline"]["ok"])

    def test_light_from_the_wrong_side_fails(self):
        img = al.Image(64, 64)
        for y in range(64):
            for x in range(64):
                img.set(x, y, ((152, 56, 56) if x + y < 64 else (232, 128, 104)) + (255,))
        self.assertFalse(self.checks(img, door=None)["light_from_top_left"]["ok"])

    def test_missing_door_fails(self):
        img = synthetic_house()
        for y in range(48, 64):
            for x in range(16, 32):
                img.set(x, y, WALL[0] + (255,))
        self.assertFalse(self.checks(img)["door"]["ok"])

    def test_speck_fails(self):
        img = al.Image(64, 64)
        img.paste(synthetic_house(32, 32), 0, 0)
        img.set(60, 60, (100, 100, 100, 255))
        self.assertFalse(self.checks(img, min_fill=0.0, door=None)["no_specks"]["ok"])

    def test_asymmetric_silhouette_fails_when_symmetry_is_required(self):
        img = synthetic_house()
        for y in range(0, 40):
            for x in range(40, 64):
                img.set(x, y, (0, 0, 0, 0))
        self.assertFalse(self.checks(img, symmetric=True, min_fill=0.0)["symmetric_silhouette"]["ok"])


def crisp_tiles(n=150, seed=3):
    """Flat-colour tiles with clearly different tones, plus tiles cut from crisp houses in several
    colourways: a stand-in for a reference look."""
    rows = []
    for roof in ([(232, 128, 104), (200, 80, 72), (152, 56, 56)], [(120, 200, 200), (58, 154, 154), (37, 106, 106)],
                 [(150, 200, 120), (90, 154, 74), (58, 106, 48)], [(176, 136, 216), (138, 90, 176), (90, 58, 122)],
                 [(248, 176, 104), (224, 138, 58), (160, 90, 32)], [(240, 112, 96), (208, 72, 64), (144, 48, 48)]):
        ROOF[:] = roof
        rows.extend(al.image_tile_metrics(synthetic_house()))
    ROOF[:] = [(232, 128, 104), (200, 80, 72), (152, 56, 56)]
    rnd = random.Random(seed)
    palette = [(88, 152, 72), (120, 200, 96), (168, 224, 128), (200, 168, 112), (152, 120, 80), (224, 224, 208), (112, 112, 128), (96, 136, 200)]
    for _ in range(n):
        img = al.Image(16, 16)
        base = rnd.choice(palette)
        img.fill(base + (255,))
        for _k in range(rnd.randint(1, 4)):
            c = rnd.choice(palette)
            x0, y0 = rnd.randint(0, 12), rnd.randint(0, 12)
            for y in range(y0, min(16, y0 + rnd.randint(2, 6))):
                for x in range(x0, min(16, x0 + rnd.randint(2, 6))):
                    img.set(x, y, c + (255,))
        rows.append(al.tile_metrics(img.rgb, img.opaque, 0, 0))
    return al.summarise(rows)


class StyleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ref = crisp_tiles()

    def test_crisp_art_passes(self):
        self.assertTrue(al.style_fit(synthetic_house(), self.ref)["ok"])

    def test_blurred_art_fails(self):
        r = al.style_fit(blur(synthetic_house(), 2), self.ref)
        self.assertFalse(r["ok"])
        self.assertIn("soft_step_ratio", [m["name"] for m in r["metrics"] if not m["ok"]])

    def test_noisy_art_fails(self):
        rnd = random.Random(5)
        img = synthetic_house()
        for y in range(64):
            for x in range(64):
                c = img.get(x, y)
                img.set(x, y, tuple(max(0, min(255, c[i] + rnd.randint(-30, 30))) for i in range(3)) + (255,))
        self.assertFalse(al.style_fit(img, self.ref)["ok"])

    def test_near_black_outline_fails(self):
        r = al.style_fit(synthetic_house(outline=(26, 26, 32)), self.ref)
        self.assertFalse(r["ok"])
        self.assertIn("dark_share", [m["name"] for m in r["metrics"] if not m["ok"]])

    def _ref_without(self, *names):
        """The reference with these metrics' bands moved where the crisp house cannot reach."""
        ref = {k: (dict(v) if isinstance(v, dict) else v) for k, v in self.ref.items()}
        for n in names:
            ref[n] = {q: 5.0 for q in ("1", "2.5", "5", "25", "50", "75", "95", "97.5", "99")}
        return ref

    def test_brightness_alone_never_uses_up_the_allowance(self):
        # Every house the image models drew, the ones that look right included, sits below the reference
        # brightness band: brightness is reported as a warning but does not count as the one unusual measure.
        r = al.style_fit(synthetic_house(), self._ref_without("val_mean", "mean_run"))
        self.assertTrue(r["ok"])
        self.assertIn("val_mean", [m["name"] for m in r["metrics"] if not m["ok"]])
        self.assertFalse(al.style_fit(synthetic_house(), self._ref_without("val_spread", "mean_run"))["ok"])
        self.assertFalse(al.style_fit(synthetic_house(), self._ref_without("val_mean", "val_spread", "mean_run"))["ok"])


class OriginalityTests(unittest.TestCase):
    def setUp(self):
        self.tile = al.Image(16, 16)
        rnd = random.Random(11)
        cols = [(200, 80, 72), (232, 128, 104), (152, 56, 56), (248, 240, 224), (104, 176, 224)]
        for y in range(16):
            for x in range(16):
                self.tile.set(x, y, rnd.choice(cols) + (255,))
        h = al.tile_hashes(self.tile.rgb, self.tile.opaque, 0, 0)
        self.ref_hashes, self.ref_patterns = [(h[0], h[2])], [h[1]]

    def test_copied_tile_is_caught(self):
        img = synthetic_house()
        img.paste(self.tile, 16, 16)
        self.assertTrue(al.originality(img, self.ref_hashes, self.ref_patterns))

    def test_recoloured_copy_is_caught(self):
        img = synthetic_house()
        swap = {}
        for y in range(16):
            for x in range(16):
                c = self.tile.rgb(x, y)
                swap.setdefault(c, (c[2], c[0], c[1]))
                img.set(16 + x, 16 + y, swap[c] + (255,))
        self.assertTrue(al.originality(img, self.ref_hashes, self.ref_patterns))

    def test_slightly_altered_copy_is_caught(self):
        img = synthetic_house()
        img.paste(self.tile, 16, 16)
        for x, y in ((3, 3), (9, 12), (14, 1)):
            c = img.rgb(16 + x, 16 + y)
            img.set(16 + x, 16 + y, (min(255, c[0] + 6), c[1], c[2], 255))
        self.assertTrue(al.originality(img, self.ref_hashes, []))

    def test_simple_shared_patterns_are_not_called_copies(self):
        stripes = al.Image(16, 16)
        for y in range(16):
            for x in range(16):
                stripes.set(x, y, ((200, 80, 72) if (y // 4) % 2 else (232, 128, 104)) + (255,))
        h = al.tile_hashes(stripes.rgb, stripes.opaque, 0, 0)
        self.assertIsNone(h)
        img = synthetic_house()
        img.paste(stripes, 16, 0)
        self.assertEqual(al.originality(img, self.ref_hashes, self.ref_patterns), [])

    def test_mostly_flat_tiles_are_not_called_copies(self):
        flat = al.Image(16, 16)
        flat.fill((200, 200, 190, 255))
        rnd = random.Random(2)
        for _ in range(40):
            flat.set(rnd.randint(0, 15), rnd.randint(0, 15), rnd.choice([(90, 90, 80), (150, 150, 140), (240, 240, 230), (120, 160, 90)]) + (255,))
        self.assertIsNone(al.tile_hashes(flat.rgb, flat.opaque, 0, 0))

    def test_a_small_corner_watermark_is_flagged(self):
        raw = ai_like(synthetic_house(), margin=150)
        cx, cy = raw.w - 30, raw.h - 30
        for y in range(raw.h):
            for x in range(raw.w):
                if (x - cx) ** 2 + (y - cy) ** 2 < 120:
                    raw.set(x, y, (240, 240, 240, 255))
        _sprite, rep = al.convert(raw, 64, 64)
        self.assertTrue(rep["strays"])

    def test_original_art_is_not_flagged(self):
        self.assertEqual(al.originality(synthetic_house(), self.ref_hashes, self.ref_patterns), [])


class RecolourTilesTests(unittest.TestCase):
    def test_recolour_rgba_maps_palette_and_binary_alpha(self):
        src_img = al.Image(2, 2)
        src_img.set(0, 0, (141, 196, 53, 255))
        src_img.set(1, 0, (132, 187, 44, 255))
        src_img.set(0, 1, (255, 0, 255, 255))
        src_img.set(1, 1, (141, 196, 53, 64))
        out = rt.recolour_rgba(src_img)
        self.assertEqual(out.get(0, 0), rt.TS_TERRAIN_PALETTE["grass_base"])
        self.assertEqual(out.get(1, 0), rt.TS_TERRAIN_PALETTE["grass_shade"])
        self.assertEqual(out.get(0, 1), (0, 0, 0, 0))
        self.assertEqual(out.get(1, 1), (0, 0, 0, 0))

    def test_compose_quarter_tiles_produces_16_distinct_masks(self):
        patch = []
        for idx, col in enumerate([
            (200, 50, 50, 255),
            (50, 200, 50, 255),
            (50, 50, 200, 255),
            (200, 200, 50, 255),
            (200, 50, 200, 255),
            (50, 200, 200, 255),
            (150, 100, 50, 255),
            (50, 150, 100, 255),
            (100, 50, 150, 255),
        ]):
            im = al.Image(16, 16)
            im.fill(col)
            im.set(idx % 8, idx // 8, (255, 255, 255, 255))
            patch.append(im)
        seen = set()
        for mask in range(16):
            tile = rt.compose_quarter_tiles(*patch, mask)
            self.assertEqual((tile.w, tile.h), (16, 16))
            seen.add(bytes(tile.px))
        self.assertEqual(len(seen), 16)


if __name__ == "__main__":
    unittest.main()
