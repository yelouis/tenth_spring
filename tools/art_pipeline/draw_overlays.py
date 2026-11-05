#!/usr/bin/env python3
"""draw_overlays.py — draws three Tier 1 decals by code instead of with an image model (DRAFT).

    python3 -I tools/art_pipeline/draw_overlays.py --work ../tenth_spring_art_code

The cracks and grass-tuft overlays are 1-pixel lines and small tufts in a few colours, laid over paving. Image models
drew them as houses, tiles, slabs, rocks, or noisy specks in three runs (ART_BRIEF.md section 0), so the human chose
to draw them by code (2026-10-31). The creeping vine joined them on 2026-11-01: in four prompt designs, the image
model drew it on a panel or as a noisy scribble, because a thin stem with small leaves can't be drawn well at
16 x 16 from a large picture. Each is drawn on the 16-pixel grid in the game's own palette colours
(assets/palette/tenth_spring.gpl), then saved the way an image model's picture would be: enlarged 60 times on
magenta, as <work>/raw/<asset>/candidate_01.png, with a provenance entry (model_family "code"). convert_art.py and
validate_art.py then treat it like any other candidate, and the converter gives back exactly the drawn sprite.
"""

import argparse
import datetime
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art_lib as al  # noqa: E402

# The game's palette (assets/palette/tenth_spring.gpl)
ROAD_CRACK = (90, 90, 96)
PATH_EDGE = (176, 144, 96)
TALL_BLADES = (47, 107, 36)
GRASS_TUFT = (95, 168, 63)
TALL_TIPS = (143, 216, 106)
TREE_OUTLINE = (36, 92, 42)


def _line(points):
    """The pixels of a polyline, 8-connected."""
    out = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            p = (int(round(x0 + (x1 - x0) * i / float(n or 1))), int(round(y0 + (y1 - y0) * i / float(n or 1))))
            if not out or out[-1] != p:
                out.append(p)
    return out


def _cracks():
    """One jagged crack across the tile with a branch that forks again, and a lighter rim under the main line.
    It is one connected piece: a separate second crack would be taken for a stray mark."""
    px = {}
    main = _line([(0, 4), (2, 5), (4, 5), (6, 7), (8, 7), (10, 8), (12, 10), (15, 10)])
    for p in main:
        px[p] = ROAD_CRACK
    for p in _line([(6, 7), (7, 9), (6, 11)]) + _line([(6, 11), (8, 13), (10, 14), (13, 15)]) + _line([(6, 11), (4, 13)]):
        px[p] = ROAD_CRACK
    for x, y in main:  # the far side of the crack catches the light
        if (x, y + 1) not in px and y + 1 < 16:
            px[(x, y + 1)] = PATH_EDGE
    return px


# One grass tuft growing from a short crack, by offset from its foot: lit from the upper left.
_TUFT = ["L.L..",
         "LGLG.",
         "BGGGL",
         ".BGBB",
         "CCCC."]
_TUFT_COLOURS = {"L": TALL_TIPS, "G": GRASS_TUFT, "B": TALL_BLADES, "C": ROAD_CRACK}


def _tufts():
    """Three tufts in a loose triangle, each over a short crack."""
    px = {}
    for cx, foot in ((2, 6), (13, 9), (7, 15)):
        for row, line in enumerate(_TUFT):
            for col, ch in enumerate(line):
                if ch != ".":
                    px[(cx - 2 + col, foot - 4 + row)] = _TUFT_COLOURS[ch]
    return px


# One ivy leaf by offset from its top-left corner: a dark outline, lit from the upper left.
_LEAF = [".OO.",
         "OLGO",
         "OGGO",
         ".OO."]
_LEAF_COLOURS = {"O": TREE_OUTLINE, "L": TALL_TIPS, "G": GRASS_TUFT}


def _creeper():
    """A creeping vine: a wavy dark stem with two leaves above it and two below. It is an outlined decal that the
    converter fits inside a 1-pixel margin, so it spans columns 1-14 and rests on row 14."""
    px = {}
    for p in _line([(1, 10), (3, 9), (5, 10), (7, 10), (9, 9), (11, 10), (14, 9)]):
        px[p] = TREE_OUTLINE
    for lx, ly in ((2, 5), (5, 11), (8, 5), (11, 11)):
        for row, line in enumerate(_LEAF):
            for col, ch in enumerate(line):
                if ch != ".":
                    px[(lx + col, ly + row)] = _LEAF_COLOURS[ch]
    return px


DRAWN = {"decal_cracks": _cracks(), "decal_tufts": _tufts(), "decal_creeper": _creeper()}


def sprite(art):
    img = al.Image(16, 16)
    for (x, y), c in art.items():
        img.set(x, y, c + (255,))
    return img


def raw_picture(art, scale=60, size=1024, key=(255, 0, 255)):
    """The sprite enlarged `scale` times, centred on a `size` square of the key colour, as an image model's
    picture would be. Each drawing fills its asset's box (16 columns for an overlay, 14 inside a 1-pixel margin for
    an outlined decal) and rests on its bottom row, so the converter maps it back pixel for pixel."""
    img = al.Image(size, size)
    img.fill(key + (255,))
    o = (size - 16 * scale) // 2
    for (x, y), c in art.items():
        for dy in range(scale):
            row = (o + y * scale + dy) * size
            for dx in range(scale):
                i = (row + o + x * scale + dx) * 4
                img.px[i:i + 4] = bytes(c + (255,))
    return img


def main():
    ap = argparse.ArgumentParser(description="Draw the cracks, grass-tuft, and creeping-vine decals (see the module docstring).")
    ap.add_argument("--work", required=True, help="the work folder (outside the repository)")
    args = ap.parse_args()
    work = os.path.abspath(args.work)
    if work == al.repo_root() or work.startswith(al.repo_root() + os.sep):
        print("draw_overlays: --work must be outside the repository", file=sys.stderr)
        return 2
    prov_path = os.path.join(work, "provenance.json")
    entries = al.load_json(prov_path) if os.path.exists(prov_path) else []
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for aid, art in sorted(DRAWN.items()):
        d = os.path.join(work, "raw", aid)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "candidate_01.png")
        if os.path.exists(path):
            print("keeping %s (already drawn)" % path)
            continue
        al.write_png(path, raw_picture(art))
        entries.append({"asset": aid, "file": "candidate_01.png", "round": 1, "date": now,
                        "service": "tools/art_pipeline/draw_overlays.py", "model": "draw_overlays.py",
                        "model_family": "code", "licence": "the project's own code", "prompt": None,
                        "prompt_change": None, "attachments": [], "output_format": "png", "image_size": "1024x1024",
                        "visible_watermark": False, "converted_to_png": False, "carried_over": False})
        print("drew %s" % path)
    al.save_json(prov_path, entries)
    return 0


if __name__ == "__main__":
    sys.exit(main())
