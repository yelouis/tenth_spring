#!/usr/bin/env python3
"""build_style_reference.py — the local style reference for validate_art.py (tools/art_pipeline/).

Run on the human's Mac only, with TENTH_SPRING_ROM_GBA set. It reads the Emerald ROM through the
Item 12 spike module, measures every metatile Emerald draws outdoors and its building pieces, and
writes NUMBERS ONLY — percentile bands and tile hashes — to
    ~/.tenth_spring_rom_spike/emerald/style_reference.json
plus a calibration report beside it. Both stay outside the repository. Never commit, upload, attach,
or show to an online model anything this script writes.

The calibration answers: does the style check pass real Emerald art, and does it fail the ways
generated art goes wrong (smeared, noisy, smoothly shaded)?
"""

import argparse
import base64
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art_lib as al  # noqa: E402

SPIKE = os.path.join(al.repo_root(), "tools", "rom_spike", "emerald")
sys.path.insert(0, SPIKE)
import rom_spike as rs  # noqa: E402


def canvas_to_image(canvas16_rows):
    """A list of rows of (r, g, b) -> opaque Image."""
    h = len(canvas16_rows)
    w = len(canvas16_rows[0])
    img = al.Image(w, h)
    for y in range(h):
        for x in range(w):
            img.set(x, y, tuple(canvas16_rows[y][x]) + (255,))
    return img


def render_rect(ts, metatiles, w, h, key):
    rows = [[None] * (w * 16) for _ in range(h * 16)]
    for i, mid in enumerate(metatiles):
        c = rs.render_entry(ts, mid, key)
        ox, oy = (i % w) * 16, (i // w) * 16
        for y in range(16):
            for x in range(16):
                rows[oy + y][ox + x] = c[y][x]
    return canvas_to_image(rows)


def box_blur(img, r):
    """Separable box blur of the RGB channels (alpha untouched)."""
    w, h = img.w, img.h
    src = img.px
    tmp = bytearray(src)
    for y in range(h):
        for ch in range(3):
            acc = 0
            win = []
            row = [src[(y * w + x) * 4 + ch] for x in range(w)]
            pref = [0]
            for v in row:
                pref.append(pref[-1] + v)
            for x in range(w):
                a, b = max(0, x - r), min(w, x + r + 1)
                tmp[(y * w + x) * 4 + ch] = (pref[b] - pref[a]) // (b - a)
    out = bytearray(tmp)
    for x in range(w):
        for ch in range(3):
            col = [tmp[(y * w + x) * 4 + ch] for y in range(h)]
            pref = [0]
            for v in col:
                pref.append(pref[-1] + v)
            for y in range(h):
                a, b = max(0, y - r), min(h, y + r + 1)
                out[(y * w + x) * 4 + ch] = (pref[b] - pref[a]) // (b - a)
    return al.Image(w, h, out)


def on_key(img, k, margin_px):
    """Upscales `img` by k and places it on a magenta canvas with a margin, like a generation."""
    big = img.scaled(k)
    canvas = al.Image(big.w + 2 * margin_px, big.h + 2 * margin_px)
    canvas.fill((255, 0, 255, 255))
    canvas.paste(big, margin_px, margin_px, only_opaque=False)
    return canvas


def on_panel(img, k, margin_px, panel=(246, 242, 228, 255), line=(80, 104, 176, 255)):
    """Like `on_key`, but the art sits on a pale panel with a blue box line, as when a model copies the
    layout guide into the picture. The panel keeps the art's proportions."""
    big = img.scaled(k)
    px, py = max(4, big.w // 10), max(4, big.h // 10)
    canvas = al.Image(big.w + 2 * (px + margin_px), big.h + 2 * (py + margin_px))
    canvas.fill((255, 0, 255, 255))
    for y in range(margin_px, canvas.h - margin_px):
        for x in range(margin_px, canvas.w - margin_px):
            edge = min(x - margin_px, y - margin_px, canvas.w - margin_px - 1 - x, canvas.h - margin_px - 1 - y) < 3
            canvas.set(x, y, line if edge else panel)
    canvas.paste(big, margin_px + px, margin_px + py, only_opaque=False)
    return canvas


def add_noise(img, amp, seed, region=None):
    rnd = random.Random(seed)
    out = img.copy()
    for y in range(img.h):
        for x in range(img.w):
            if region and not (region[0] <= x < region[2] and region[1] <= y < region[3]):
                continue
            c = img.get(x, y)
            out.set(x, y, tuple(max(0, min(255, c[i] + rnd.randint(-amp, amp))) for i in range(3)) + (c[3],))
    return out


def smooth_shade(img):
    """Replaces flat fills with a smooth top-to-bottom light gradient (many near-identical tones)."""
    out = img.copy()
    for y in range(img.h):
        f = 1.18 - 0.36 * (y / float(max(1, img.h - 1)))
        for x in range(img.w):
            c = img.get(x, y)
            out.set(x, y, tuple(max(0, min(255, int(c[i] * f + (x % 7)))) for i in range(3)) + (c[3],))
    return out


def blend_borders(big, k):
    """Softens every k-pixel block border by averaging across it (mild anti-aliasing)."""
    out = big.copy()
    for y in range(big.h):
        for x in range(1, big.w):
            if x % k == 0:
                a, b = big.get(x - 1, y), big.get(x, y)
                m = tuple((a[i] + b[i]) // 2 for i in range(3)) + (255,)
                out.set(x - 1, y, m)
                out.set(x, y, m)
    for x in range(big.w):
        for y in range(1, big.h):
            if y % k == 0:
                a, b = out.get(x, y - 1), out.get(x, y)
                m = tuple((a[i] + b[i]) // 2 for i in range(3)) + (255,)
                out.set(x, y - 1, m)
                out.set(x, y, m)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=al.DEFAULT_REFERENCE, help="where to write the reference (outside the repo)")
    ap.add_argument("--min-uses", type=int, default=3, help="a metatile counts as outdoor art when outdoor maps use it this often")
    ap.add_argument("--controls", type=int, default=12, help="how many building sprites to degrade for the negative controls")
    args = ap.parse_args()
    out_path = os.path.abspath(os.path.expanduser(args.out))
    if out_path.startswith(al.repo_root() + os.sep):
        sys.exit("refusing to write inside the repository: %s" % out_path)

    rom = rs.check_preconditions()
    layouts = list(rs.iter_map_layouts(rom))
    freq = rs.frequency(layouts)
    secondaries = sorted({k[0] for k in freq if isinstance(k, tuple)})
    ts = rs.load_tilesets(rom, tuple(secondaries))

    terrain_rows, hashes, patterns = [], set(), set()
    n_terrain = 0
    for gk, n in sorted(freq.items(), key=lambda kv: str(kv[0])):
        if n < args.min_uses:
            continue
        if isinstance(gk, tuple):
            sec, mid = gk
            canvas = rs.render_entry(ts, mid, rs.sec_key(sec))
        else:
            canvas = rs.render_entry(ts, gk, "primary")
        img = canvas_to_image(canvas)
        m = al.tile_metrics(img.rgb, img.opaque, 0, 0)
        if m is None:
            continue
        terrain_rows.append(m)
        n_terrain += 1
        for getter in ((img.rgb, img.opaque), al.flip_h(img.rgb, img.opaque, 0, 0)):
            hv = al.tile_hashes(getter[0], getter[1], 0, 0)
            if hv:
                hashes.add((hv[0], base64.b64encode(hv[2]).decode("ascii")))
                patterns.add(hv[1])

    mapping = rs.load_mapping()
    sprites = []
    for name, b in sorted(mapping["buildings"].items()):
        for colour, entry in sorted(b["roof_colors"].items()):
            sprites.append(("%s_%s" % (name, colour), render_rect(ts, entry["metatiles"], b["w"], b["h"], entry.get("tileset", "primary"))))
    for name, c in sorted(mapping["compositions"].items()):
        sprites.append((name, render_rect(ts, c["metatiles"], c["w"], c["h"], c.get("tileset", "primary"))))
    structure_rows = []
    for _name, img in sprites:
        structure_rows.extend(al.image_tile_metrics(img))
        for ty in range(img.h // 16):
            for tx in range(img.w // 16):
                hv = al.tile_hashes(img.rgb, img.opaque, tx * 16, ty * 16)
                if hv:
                    hashes.add((hv[0], base64.b64encode(hv[2]).decode("ascii")))
                    patterns.add(hv[1])

    groups = {
        "terrain": al.summarise(terrain_rows),
        "structures": al.summarise(structure_rows),
        "all": al.summarise(terrain_rows + structure_rows),
    }

    # --- calibration ---
    lines = ["Style reference calibration (local only; never commit)", ""]
    lines.append("Outdoor metatiles measured: %d; building/composition sprites: %d (%d tiles)"
                 % (n_terrain, len(sprites), len(structure_rows)))
    lines.append("")
    lines.append("Bands (2.5th to 97.5th percentile), group 'all':")
    for m in al.METRICS:
        b = groups["all"][m]
        lines.append("  %-20s %8.3f .. %8.3f   median %8.3f" % (m, b["2.5"], b["97.5"], b["50"]))

    even = [r for i, r in enumerate(terrain_rows + structure_rows) if i % 2 == 0]
    odd = [r for i, r in enumerate(terrain_rows + structure_rows) if i % 2 == 1]
    half = al.summarise(even)
    lines.append("")
    lines.append("Held-out tiles (bands from even-numbered tiles, tested on odd-numbered ones):")
    all_inside = 0
    for m in al.METRICS:
        lo, hi = half[m]["2.5"], half[m]["97.5"]
        inside = sum(1 for r in odd if lo <= r[m] <= hi) / float(len(odd))
        lines.append("  %-20s %.3f of held-out tiles inside" % (m, inside))
    for r in odd:
        if all(half[m]["2.5"] <= r[m] <= half[m]["97.5"] for m in al.HARD_METRICS):
            all_inside += 1
    lines.append("  all hard metrics inside: %.3f" % (all_inside / float(len(odd))))

    lines.append("")
    lines.append("Emerald building sprites, style check against group 'structures' (in-sample):")
    pos_ok = 0
    distances = []
    for name, img in sprites:
        r = al.style_fit(img, groups["structures"])
        pos_ok += r["ok"]
        distances.append(r["style_distance"])
        ld, _ = al.light_direction(img)
        failed = ",".join(m["name"] for m in r["metrics"] if not m["ok"])
        lines.append("  %-14s %s  distance %.2f  light %.2f  %s" % (name, "PASS" if r["ok"] else "fail", r["style_distance"], ld, failed))
    lines.append("  passed: %d of %d" % (pos_ok, len(sprites)))
    pale = sorted(al.pale_edge_share(img) for _name, img in sprites)
    lines.append("  pale share of the edge (the edge_not_pale check fails above 0.40): median %.2f, highest %.2f, above 0.40: %d of %d"
                 % (pale[len(pale) // 2], pale[-1], sum(1 for p in pale if p > 0.40), len(pale)))

    lines.append("")
    lines.append("Controls. Should PASS: Emerald art that went through the converter cleanly, slightly smeared, or")
    lines.append("on a drifting grid. Should FAIL: noise, detail finer than the grid, a pale panel copied around the")
    lines.append("art, a painted field to the picture's edge, near-black outlines, oversaturated colour, murky")
    lines.append("darkness. (Each Emerald sprite stands in for a generated image.) Converted controls must also pass")
    lines.append("the converter's own measurements: background_clear, edge_not_pale, colours_kept.")
    small = [s2 for s2 in sprites if s2[1].w <= 96 and s2[1].h <= 96][: args.controls]
    tally = {}
    report_checks = ("background_clear", "edge_not_pale", "colours_kept")

    def judge(vname, expect, name, sprite, rep=None):
        fit = al.style_fit(sprite, groups["structures"])
        purity = rep["block_purity"] if rep else 1.0
        measured = []
        if rep is not None:
            spec = {"size_px": [sprite.w, sprite.h], "outline": False, "light_check": False}
            measured = [c["name"] for c in al.technical_checks(sprite, spec, rep) if c["name"] in report_checks and not c["ok"]]
        ok = fit["ok"] and purity >= 0.75 and not measured
        failed = ",".join([m["name"] for m in fit["metrics"] if not m["ok"]] + measured)
        t = tally.setdefault((expect, vname), [0, 0])
        t[0] += ok
        t[1] += 1
        lines.append("  %-14s %-34s %-5s purity %.2f distance %.2f %s" % (name, vname, "PASS" if ok else "fail", purity, fit["style_distance"], failed))

    for name, img in small:
        k = 12
        clean = on_key(img, k, 48)
        inner = (48, 48, clean.w - 48, clean.h - 48)
        field = clean.copy()
        for y in range(field.h):
            for x in range(field.w):
                if al.is_key(field.get(x, y), (255, 0, 255)):
                    field.set(x, y, (240, 214, 210, 255))
        raws = [
            ("pass", "clean", add_noise(blend_borders(clean, k), 3, 1, inner)),
            ("pass", "slightly smeared (blur r=4)", box_blur(clean, 4)),
            ("pass", "drifting grid (x11.3)", None),
            ("fail", "noisy (+/-28)", add_noise(clean, 28, 2, inner)),
            ("fail", "detail finer than the grid", None),
            ("fail", "on a copied pale panel", on_panel(img, k, 48)),
            ("fail", "painted field to the edge", field),
        ]
        for expect, vname, raw in raws:
            try:
                if vname.startswith("drifting"):
                    big = al.Image(int(img.w * 11.3), int(img.h * 11.3))
                    for y in range(big.h):
                        for x in range(big.w):
                            big.set(x, y, img.get(min(img.w - 1, int(x / 11.3)), min(img.h - 1, int(y / 11.3))))
                    raw = al.Image(big.w + 96, big.h + 96)
                    raw.fill((255, 0, 255, 255))
                    raw.paste(big, 48, 48, only_opaque=False)
                    sprite, rep = al.convert(raw, img.w, img.h, mode="free")
                elif vname.startswith("detail"):
                    raw = on_key(img, 4, 16)
                    sprite, rep = al.convert(raw, max(16, img.w // 3), max(16, img.h // 3), mode="free")
                else:
                    sprite, rep = al.convert(raw, img.w, img.h, mode="free")
                judge(vname, expect, name, sprite, rep)
            except al.ConversionError as e:
                t = tally.setdefault((expect, vname), [0, 0])
                t[1] += 1
                lines.append("  %-14s %-34s rejected: %s" % (name, vname, e))
        ink = img.copy()
        for x in range(img.w):
            ink.set(x, 0, al.INK + (255,))
            ink.set(x, img.h - 1, al.INK + (255,))
        for y in range(img.h):
            ink.set(0, y, al.INK + (255,))
            ink.set(img.w - 1, y, al.INK + (255,))
        judge("near-black 1-px outline", "fail", name, ink)
        sat = img.copy()
        dark = img.copy()
        for y in range(img.h):
            for x in range(img.w):
                h_, s_, v_ = al.hsv(img.rgb(x, y))
                r, g, b = al.colorsys.hsv_to_rgb(h_, min(1.0, s_ * 1.8 + 0.25), min(1.0, v_ * 1.05))
                sat.set(x, y, (int(r * 255), int(g * 255), int(b * 255), 255))
                r, g, b = al.colorsys.hsv_to_rgb(h_, s_, v_ * 0.5)
                dark.set(x, y, (int(r * 255), int(g * 255), int(b * 255), 255))
        judge("oversaturated", "fail", name, sat)
        judge("murky (half brightness)", "fail", name, dark)

    lines.append("")
    for (expect, vname), (ok, n) in sorted(tally.items()):
        right = ok if expect == "pass" else n - ok
        lines.append("  should %-4s %-34s right %d of %d" % (expect, vname, right, n))

    # The repo's own code-drawn placeholder house, for comparison (original art, not Emerald)
    try:
        ph = rs.PlaceholderAtlas()
        tm = mapping.get("tile_map", {})
        layout = [[(12, 0, 6), (12, 0, 14), (12, 0, 14), (12, 0, 12)], [(12, 0, 3), (12, 0, 11), (12, 0, 11), (12, 0, 9)],
                  [(13, 1, 6), (13, 0, 14), (13, 1, 14), (13, 0, 12)], [(13, 1, 3), (14, 0, 0), (13, 1, 11), (13, 0, 9)]]
        house = al.Image(64, 64)
        for ty, row in enumerate(layout):
            for tx, (cls, var, mask) in enumerate(row):
                rows32 = ph.tile_rows32(cls, var, mask)
                for y in range(16):
                    for x in range(16):
                        r, g, b = rows32[y * 2][x * 2 * 3:x * 2 * 3 + 3]
                        house.set(tx * 16 + x, ty * 16 + y, (r, g, b, 255))
        fit = al.style_fit(house, groups["structures"])
        failed = ",".join(m["name"] for m in fit["metrics"] if not m["ok"])
        lines.append("")
        lines.append("  the game's code-drawn placeholder house: %s, distance %.2f %s"
                     % ("PASS" if fit["ok"] else "fail", fit["style_distance"], failed))
    except Exception as e:  # informative only
        lines.append("  (placeholder comparison skipped: %s)" % e)

    # --- originality: real reference sprites must be caught; original art must not be ---
    ref_tiles = [(h, base64.b64decode(r)) for h, r in sorted(hashes)]
    caught = 0
    for name, img in sprites:
        if al.originality(img, ref_tiles, patterns):
            caught += 1
    lines.append("")
    lines.append("Originality: reference sprites submitted as if new, caught as copies: %d of %d" % (caught, len(sprites)))
    touched = 0
    for name, img in sprites:
        t = img.copy()
        for y in range(0, t.h, 7):
            for x in range(0, t.w, 11):
                c = t.get(x, y)
                t.set(x, y, (min(255, c[0] + 8), c[1], max(0, c[2] - 8), 255))
        if al.originality(t, ref_tiles, patterns):
            touched += 1
    lines.append("Originality: the same sprites with scattered touch-ups, still caught: %d of %d" % (touched, len(sprites)))
    try:
        ph_hits = al.originality(house, ref_tiles, patterns)
        lines.append("Originality: the game's own code-drawn placeholder house flagged: %s" % ("yes" if ph_hits else "no"))
    except NameError:
        pass

    ref = {
        "version": 1,
        "about": "Numbers measured from the human's Emerald ROM on their machine. Local only: never commit, upload, or attach.",
        "groups": groups,
        "tiles": [[h, r] for h, r in sorted(hashes)],
        "patterns": sorted(patterns),
        "soft_step": al.SOFT_STEP,
        "calibration": {"structures_distance_max": max(distances), "structures_distance_median": sorted(distances)[len(distances) // 2]},
    }
    al.save_json(out_path, ref)
    report_path = os.path.join(os.path.dirname(out_path), "style_calibration.txt")
    with open(report_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote the reference and the calibration report outside the repository (%s)" % os.path.dirname(rs.OUT_DIR_DISPLAY + "/x"))


if __name__ == "__main__":
    main()
