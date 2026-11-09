#!/usr/bin/env python3
"""
tools/art_pipeline/recolour_tiles.py — Deterministic CC0 terrain recolourer & atlas builder.
Contract: docs/implementation_plan_original_tiles.md §3, §4, §6 (Decision 53, Item 40).

Builds game/assets/tiles/original_v1.png (512 x 3,136 px, RGBA) and
game/assets/tiles/original_v1.json (94 vocabulary rows + 4 fog rows = 98 rows)
from Kenney's Roguelike/RPG Pack (CC0 1.0 Universal, http://creativecommons.org/publicdomain/zero/1.0/)
recoloured to the 35-colour Tenth Spring Terrain Palette.

Pure Python 3 standard library only; 100% deterministic across platforms.
"""

import argparse
import base64
import hashlib
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_lib as al

ARCHIVE_SHA256 = "8e7d2378f8f794245645f6d7dc7aeeb246791410a7e512293c594b46a5a9524b"
SHEET_SHA256 = "808c8d734480bc949b284f3bcc252e87e1ee53b24178791a6838cce6a319c439"
EMBEDDED_PACK1_B64 = (
    "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"
)


# ---------------------------------------------------------------------------
# Tenth Spring Terrain Palette (35 colours across 10 material groups)
# Every adjacent step within a material has redmean >= 60.1 (> SOFT_STEP = 40),
# and 0 RGB overlaps with the 432 unique RGB colours in the GBA reference set.
# ---------------------------------------------------------------------------

TS_TERRAIN_PALETTE = {
    # Grass (TILE_GRASS)
    "grass_hi":     (146, 212, 114, 255),  # #92d472
    "grass_base":   (108, 180,  88, 255),  # #6cb458
    "grass_shade":  ( 76, 142,  64, 255),  # #4c8e40
    # Tall Grass (TILE_TALL_GRASS)
    "tall_tip":     (146, 212, 114, 255),  # #92d472
    "tall_upper":   (100, 166,  76, 255),  # #64a64c
    "tall_mid":     ( 68, 130,  56, 255),  # #448238
    "tall_deep":    ( 44,  96,  46, 255),  # #2c602e
    # Water (TILE_WATER)
    "water_foam":   (172, 220, 238, 255),  # #acdcee
    "water_base":   ( 88, 164, 212, 255),  # #58a4d4
    "water_deep":   ( 56, 122, 172, 255),  # #387aac
    # Sand (TILE_SAND)
    "sand_hi":      (238, 220, 172, 255),  # #eedcac
    "sand_base":    (212, 188, 134, 255),  # #d4bc86
    "sand_grain":   (180, 148, 100, 255),  # #b49464
    "sand_rim":     (130,  98,  64, 255),  # #826240
    # Marsh (TILE_MARSH)
    "marsh_reed":   (114, 158,  98, 255),  # #729e62
    "marsh_mud":    ( 88, 118,  80, 255),  # #587650
    "marsh_pool":   ( 64, 116, 134, 255),  # #407486
    # Dirt Path (TILE_PATH)
    "path_hi":      (220, 196, 148, 255),  # #dcc494
    "path_base":    (196, 164, 116, 255),  # #c4a474
    "path_pebble":  (156, 124,  84, 255),  # #9c7c54
    "path_rim":     (114,  84,  56, 255),  # #725438
    # Road (TILE_ROAD)
    "road_curb":    (188, 196, 204, 255),  # #bcc4cc
    "road_base":    (134, 142, 150, 255),  # #868e96
    "road_wear":    (102, 110, 118, 255),  # #666e76
    "road_crack":   ( 70,  78,  86, 255),  # #464e56
    # Plaza (TILE_PLAZA)
    "plaza_hi":     (212, 212, 204, 255),  # #d4d4cc
    "plaza_base":   (178, 178, 170, 255),  # #b2b2aa
    "plaza_joint":  (138, 138, 130, 255),  # #8a8a82
    # Wood (TILE_BRIDGE, TILE_FENCE, SIGN)
    "wood_hi":      (204, 164, 114, 255),  # #cca472
    "wood_base":    (172, 124,  76, 255),  # #ac7c4c
    "wood_seam":    (132,  90,  56, 255),  # #845a38
    "wood_shadow":  ( 90,  58,  40, 255),  # #5a3a28
    # Rail (TILE_RAIL)
    "rail_top":     (196, 204, 212, 255),  # #c4ccd4
    "rail_side":    (116, 124, 132, 255),  # #747c84
    "rail_ballast": (148, 134, 116, 255),  # #948674
}

MATERIAL_RAMPS = [
    ("grass", ["grass_hi", "grass_base", "grass_shade"]),
    ("tall_grass", ["tall_tip", "tall_upper", "tall_mid", "tall_deep"]),
    ("water", ["water_foam", "water_base", "water_deep"]),
    ("sand", ["sand_hi", "sand_base", "sand_grain", "sand_rim"]),
    ("marsh", ["marsh_reed", "marsh_mud", "marsh_pool"]),
    ("path", ["path_hi", "path_base", "path_pebble", "path_rim"]),
    ("road", ["road_curb", "road_base", "road_wear", "road_crack"]),
    ("plaza", ["plaza_hi", "plaza_base", "plaza_joint"]),
    ("wood", ["wood_hi", "wood_base", "wood_seam", "wood_shadow"]),
    ("rail", ["rail_top", "rail_side", "rail_ballast"]),
]

# Overview MAP_COLORS matching TS_TERRAIN_PALETTE (docs/implementation_plan_original_tiles.md §6.4)
EXPECTED_MAP_COLORS_HEX = {
    0:  "#2a3242",  # VOID
    1:  "#6cb458",  # GRASS -> grass_base
    2:  "#448238",  # TALL_GRASS -> tall_mid
    3:  "#2c602e",  # TREE -> tall_deep
    4:  "#58a4d4",  # WATER -> water_base
    5:  "#d4bc86",  # SAND -> sand_base
    6:  "#587650",  # MARSH -> marsh_mud
    7:  "#c4a474",  # PATH -> path_base
    8:  "#868e96",  # ROAD -> road_base
    9:  "#747c84",  # RAIL -> rail_side
    10: "#ac7c4c",  # BRIDGE -> wood_base
    11: "#b2b2aa",  # PLAZA -> plaza_base
    13: "#e8e0d0",  # WALL
    14: "#845a38",  # DOOR -> wood_seam
    15: "#cca472",  # FENCE -> wood_hi
    16: "#f85878",  # FLOWERS
    17: "#b2b2aa",  # GRAVE -> plaza_base
    18: "#ac7c4c",  # SIGN -> wood_base
    19: "#92d472",  # CROP -> grass_hi
    20: "#948674",  # RUBBLE -> rail_ballast
    21: "#948674",  # STAMP -> rail_ballast
}

# Exact deterministic mapping from Kenney Roguelike/RPG Pack RGB colours to TS_TERRAIN_PALETTE
PACK1_COLOR_MAP = {
    # Grass
    al.hexc("#8dc435"): TS_TERRAIN_PALETTE["grass_base"],
    al.hexc("#84bb2c"): TS_TERRAIN_PALETTE["grass_shade"],
    # Tall grass & foliage
    al.hexc("#92c939"): TS_TERRAIN_PALETTE["tall_tip"],
    al.hexc("#88bd32"): TS_TERRAIN_PALETTE["tall_upper"],
    al.hexc("#7bad2c"): TS_TERRAIN_PALETTE["tall_mid"],
    al.hexc("#73a228"): TS_TERRAIN_PALETTE["tall_deep"],
    al.hexc("#648c32"): TS_TERRAIN_PALETTE["tall_deep"],
    al.hexc("#639535"): TS_TERRAIN_PALETTE["tall_deep"],
    al.hexc("#79b742"): TS_TERRAIN_PALETTE["tall_mid"],
    al.hexc("#95c866"): TS_TERRAIN_PALETTE["tall_tip"],
    # Water
    al.hexc("#63c5cf"): TS_TERRAIN_PALETTE["water_base"],
    al.hexc("#8ed4db"): TS_TERRAIN_PALETTE["water_foam"],
    # Sand
    al.hexc("#eee6d2"): TS_TERRAIN_PALETTE["sand_hi"],
    al.hexc("#e6dabf"): TS_TERRAIN_PALETTE["sand_base"],
    al.hexc("#d9caa9"): TS_TERRAIN_PALETTE["sand_grain"],
    al.hexc("#c7b081"): TS_TERRAIN_PALETTE["sand_rim"],
    # Path / Shore earth
    al.hexc("#c58f5c"): TS_TERRAIN_PALETTE["path_hi"],
    al.hexc("#b48355"): TS_TERRAIN_PALETTE["path_base"],
    al.hexc("#a07247"): TS_TERRAIN_PALETTE["path_pebble"],
    al.hexc("#8f673f"): TS_TERRAIN_PALETTE["path_rim"],
    al.hexc("#997048"): TS_TERRAIN_PALETTE["wood_seam"],
    # Road
    al.hexc("#b1bebf"): TS_TERRAIN_PALETTE["road_curb"],
    al.hexc("#a8b6b7"): TS_TERRAIN_PALETTE["road_base"],
    al.hexc("#859495"): TS_TERRAIN_PALETTE["road_crack"],
    # Plaza & Stone
    al.hexc("#e3e3e3"): TS_TERRAIN_PALETTE["plaza_hi"],
    al.hexc("#dbdbdb"): TS_TERRAIN_PALETTE["plaza_hi"],
    al.hexc("#cccccc"): TS_TERRAIN_PALETTE["plaza_base"],
    al.hexc("#c2c2c2"): TS_TERRAIN_PALETTE["plaza_hi"],
    al.hexc("#b7b7b7"): TS_TERRAIN_PALETTE["plaza_base"],
    al.hexc("#a9a9a9"): TS_TERRAIN_PALETTE["plaza_joint"],
    al.hexc("#868686"): TS_TERRAIN_PALETTE["road_wear"],
    # Wood (Bridge / Fence / Sign)
    al.hexc("#c8a480"): TS_TERRAIN_PALETTE["wood_hi"],
    al.hexc("#b98b5e"): TS_TERRAIN_PALETTE["wood_base"],
    al.hexc("#a87e54"): TS_TERRAIN_PALETTE["wood_seam"],
    al.hexc("#9c7650"): TS_TERRAIN_PALETTE["wood_shadow"],
    # Rail
    al.hexc("#c5cbd9"): TS_TERRAIN_PALETTE["rail_top"],
    al.hexc("#838790"): TS_TERRAIN_PALETTE["rail_side"],
    # Flower accents
    al.hexc("#f7f7f7"): (248,  88, 120, 255),  # #f85878 flower_pink
    al.hexc("#e2e2e2"): (244, 240, 232, 255),  # #f4f0e8 flower_white
    al.hexc("#ffc90e"): (244, 208,  72, 255),  # #f4d048 flower_yellow
    al.hexc("#959595"): TS_TERRAIN_PALETTE["tall_mid"],
}

# 8 standing roof colourways (0..7) + gilded landmark roof (32)
ROOF_RAMPS = {
    0: ((226, 114,  98, 255), (200,  76,  64, 255), (152,  50,  40, 255), ( 88,  32,  28, 255)),  # Red
    1: ((104, 196, 196, 255), ( 64, 156, 156, 255), ( 40, 114, 114, 255), ( 24,  68,  68, 255)),  # Teal
    2: ((120, 196, 120, 255), ( 76, 156,  76, 255), ( 50, 114,  50, 255), ( 28,  68,  28, 255)),  # Green
    3: ((180, 132, 212, 255), (140,  92, 172, 255), (100,  60, 130, 255), ( 60,  34,  80, 255)),  # Purple
    4: ((114, 164, 220, 255), ( 72, 124, 184, 255), ( 46,  86, 136, 255), ( 26,  50,  82, 255)),  # Blue
    5: ((228, 188, 104, 255), (196, 150,  64, 255), (148, 108,  40, 255), ( 88,  62,  22, 255)),  # Ochre
    6: ((164, 176, 188, 255), (124, 136, 148, 255), ( 86,  96, 108, 255), ( 50,  56,  64, 255)),  # Slate
    7: ((220, 146, 104, 255), (184, 108,  66, 255), (136,  74,  42, 255), ( 80,  42,  22, 255)),  # Terracotta
    32: ((242, 210, 100, 255), (216, 168,  56, 255), (160,  90,  32, 255), ( 92,  52,  18, 255)), # Gilded gold
}

WALL_PLASTER = {
    "hi":      (242, 234, 220, 255),  # #f2eadc
    "base":    (232, 224, 208, 255),  # #e8e0d0
    "shade":   (204, 194, 176, 255),  # #ccc2b0
    "outline": (132, 122, 108, 255),  # #847a6c
    "win_gl":  ( 92, 148, 196, 255),  # #5c94c4
    "win_hi":  (164, 212, 240, 255),  # #a4d4f0
    "win_fr":  (114,  84,  56, 255),  # #725438
}

VOID_RGBA = (42, 50, 66, 255)      # #2a3242
FOG_RGBA  = (13, 17, 25, 255)      # #0d1119
BAYER_4X4 = [
    [ 0,  8,  2, 10],
    [12,  4, 14,  6],
    [ 3, 11,  1,  9],
    [15,  7, 13,  5],
]


def load_source_tiles(pack_sheet_path=None):
    """Loads the 16x16 CC0 source tiles either from pack_sheet_path (verifying SHA-256)
    or from the embedded lossless dictionary."""
    raw_dict = json.loads(zlib.decompress(base64.b64decode(EMBEDDED_PACK1_B64)).decode("ascii"))
    embedded_tiles = {
        tuple(int(x) for x in k.split(",")): al.Image(16, 16, bytearray(base64.b64decode(v)))
        for k, v in raw_dict.items()
    }
    if pack_sheet_path is not None:
        with open(pack_sheet_path, "rb") as f:
            sheet_bytes = f.read()
        digest = hashlib.sha256(sheet_bytes).hexdigest()
        if digest != SHEET_SHA256:
            raise ValueError(f"Pack sheet SHA-256 mismatch: expected {SHEET_SHA256}, got {digest}")
        sheet_img = al.read_png(pack_sheet_path)
        extracted = {}
        for c, r in embedded_tiles:
            extracted[(c, r)] = sheet_img.crop(c * 17, r * 17, c * 17 + 16, r * 17 + 16)
        return extracted
    return embedded_tiles


def recolour_rgba(tile, cmap=None, bg_tile=None):
    """Deterministically maps each opaque pixel in a 16x16 al.Image through cmap."""
    if cmap is None:
        cmap = PACK1_COLOR_MAP
    out = bg_tile.copy() if bg_tile is not None else al.Image(tile.w, tile.h)
    cmap_items = sorted(cmap.items(), key=lambda kv: kv[0])
    for y in range(tile.h):
        for x in range(tile.w):
            r, g, b, a = tile.get(x, y)
            if a < 128 or (r, g, b) == (255, 0, 255):
                continue
            rgb = (r, g, b)
            if rgb in cmap:
                out.set(x, y, cmap[rgb])
            else:
                best = min(cmap_items, key=lambda kv: (al.redmean(rgb, kv[0]), kv[0]))[1]
                out.set(x, y, best)
    return out


def compose_quarter_tiles(nw, n, ne, w, c, e, sw, s, se, mask, bg_tile=None):
    """Rule B (§3.1): Composes a 16x16 tile from four 8x8 quadrants (TL, TR, BL, BR)
    of a 3x3 9-slice set according to cardinal neighbour mask (N=1, E=2, S=4, W=8)."""
    n_conn = (mask & 1) != 0
    e_conn = (mask & 2) != 0
    s_conn = (mask & 4) != 0
    w_conn = (mask & 8) != 0

    def pick_src(v_conn, h_conn, corner_t, v_edge_t, h_edge_t, center_t):
        if not v_conn and not h_conn:
            return corner_t
        if not v_conn and h_conn:
            return h_edge_t
        if v_conn and not h_conn:
            return v_edge_t
        return center_t

    tl_src = pick_src(n_conn, w_conn, nw, w, n, c).crop(0, 0, 8, 8)
    tr_src = pick_src(n_conn, e_conn, ne, e, n, c).crop(8, 0, 16, 8)
    bl_src = pick_src(s_conn, w_conn, sw, w, s, c).crop(0, 8, 8, 16)
    br_src = pick_src(s_conn, e_conn, se, e, s, c).crop(8, 8, 16, 16)

    out = bg_tile.copy() if bg_tile is not None else al.Image(16, 16)
    out.paste(tl_src, 0, 0, only_opaque=(bg_tile is not None))
    out.paste(tr_src, 8, 0, only_opaque=(bg_tile is not None))
    out.paste(bl_src, 0, 8, only_opaque=(bg_tile is not None))
    out.paste(br_src, 8, 8, only_opaque=(bg_tile is not None))
    return out


# Rule A (§3.1) 16-mask coordinate tables for PATH, ROAD, and RAIL
PATH_MASK_COORDS = {
    0:  (8, 12),
    1:  (5, 11),
    2:  (6, 12),
    3:  (7,  8),
    4:  (6, 11),
    5:  (9,  7),
    6:  (7,  7),
    7:  (7, 10),
    8:  (5, 12),
    9:  (8,  8),
    10: (9,  8),
    11: (8, 11),
    12: (8,  7),
    13: (9, 10),
    14: (8,  9),
    15: (8, 10),
}

ROAD_MASK_COORDS = {m: (cx, cy + 6) for m, (cx, cy) in PATH_MASK_COORDS.items()}

RAIL_MASK_COORDS = {
    0:  (43, 20),
    1:  (41, 22),
    2:  (42, 20),
    3:  (41, 19),
    4:  (42, 22),
    5:  (43, 19),
    6:  (41, 18),
    7:  (45, 20),
    8:  (41, 20),
    9:  (42, 19),
    10: (43, 18),
    11: (47, 19),
    12: (42, 18),
    13: (46, 20),
    14: (45, 18),
    15: (45, 22),
}


def _build_row_specs():
    row_specs = []
    current_row = 0

    def add_row(t_class, variant, masked, any_variant=False):
        nonlocal current_row
        entry = {
            "class": t_class,
            "variant": variant,
            "row": current_row,
            "masked": masked,
        }
        if any_variant:
            entry["any_variant"] = True
        row_specs.append(entry)
        r = current_row
        current_row += 1
        return r

    r_void = add_row(0, 0, False)
    r_grass = [add_row(1, v, False) for v in range(4)]
    r_tall_grass = add_row(2, 0, True)
    r_tree = [add_row(3, v, True) for v in range(2)]
    r_water = add_row(4, 0, True)
    r_sand = add_row(5, 0, False)
    r_marsh = add_row(6, 0, False)
    r_path = add_row(7, 0, True)
    r_road = [add_row(8, v, True) for v in range(2)]
    r_rail = add_row(9, 0, True)
    r_bridge = add_row(10, 0, True)
    r_plaza = add_row(11, 0, False)
    r_roof = [add_row(12, v, True) for v in range(8)]
    r_roof_landmark = add_row(12, 32, True)
    r_wall = [add_row(13, v, True) for v in range(16)]
    r_wall_landmark = add_row(13, 32, True)
    r_wall_landmark_win = add_row(13, 40, True)
    r_door = [add_row(14, v, False) for v in range(8)]
    r_door_landmark = add_row(14, 32, False)
    r_fence = add_row(15, 0, True)
    r_flowers = add_row(16, 0, False)
    r_grave = add_row(17, 0, False)
    r_sign = add_row(18, 0, False, any_variant=True)
    r_crop = add_row(19, 0, False)
    r_path_overgrown = add_row(7, 1, True)
    r_plaza_weeded = add_row(11, 1, False)
    r_roof_broken = [add_row(12, 16 + v, True) for v in range(8)]
    r_wall_broken = [add_row(13, 16 + v, True) for v in range(16)]
    r_door_broken = [add_row(14, 16 + v, False) for v in range(8)]
    r_rubble = [add_row(20, v, False) for v in range(2)]

    fog_rows = {
        "solid": current_row,
        "d75": current_row + 1,
        "d50": current_row + 2,
        "d25": current_row + 3,
    }
    total_rows = current_row + 4
    indices = {
        "void": r_void,
        "grass": r_grass,
        "tall_grass": r_tall_grass,
        "tree": r_tree,
        "water": r_water,
        "sand": r_sand,
        "marsh": r_marsh,
        "path": r_path,
        "road": r_road,
        "rail": r_rail,
        "bridge": r_bridge,
        "plaza": r_plaza,
        "roof": r_roof,
        "roof_landmark": r_roof_landmark,
        "wall": r_wall,
        "wall_landmark": r_wall_landmark,
        "wall_landmark_win": r_wall_landmark_win,
        "door": r_door,
        "door_landmark": r_door_landmark,
        "fence": r_fence,
        "flowers": r_flowers,
        "grave": r_grave,
        "sign": r_sign,
        "crop": r_crop,
        "path_overgrown": r_path_overgrown,
        "plaza_weeded": r_plaza_weeded,
        "roof_broken": r_roof_broken,
        "wall_broken": r_wall_broken,
        "door_broken": r_door_broken,
        "rubble": r_rubble,
        "fog": fog_rows,
        "total_rows": total_rows,
    }
    return row_specs, fog_rows, indices


def _mirror_h(tile):
    out = al.Image(tile.w, tile.h)
    for y in range(tile.h):
        for x in range(tile.w):
            out.set(tile.w - 1 - x, y, tile.get(x, y))
    return out


def generate_original_atlas(pack_sheet_path=None):
    """Generates (png_bytes, json_bytes, recoloured_16x16_samples) for original_v1.{png,json}."""
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    src = load_source_tiles(pack_sheet_path)
    row_specs, fog_rows, idx = _build_row_specs()
    atlas = al.Image(16 * 32, idx["total_rows"] * 32)

    def put_16(col, row, tile16):
        atlas.paste(tile16.scaled(2), col * 32, row * 32, only_opaque=False)

    # Row 0: VOID
    void_16 = al.Image(16, 16)
    void_16.fill(VOID_RGBA)
    put_16(0, idx["void"], void_16)

    # Rows 1..4: GRASS 0..3
    grass0 = recolour_rgba(src[(5, 0)])
    grass1 = recolour_rgba(src[(5, 1)])
    grass2 = grass0.copy()
    for gx, gy in [(3, 4), (4, 3), (11, 11), (12, 10)]:
        grass2.set(gx, gy, TS_TERRAIN_PALETTE["grass_hi"])
    grass3 = _mirror_h(grass1)
    for gx, gy in [(5, 12), (6, 11), (12, 4), (13, 3)]:
        grass3.set(gx, gy, TS_TERRAIN_PALETTE["grass_hi"])
    for v, gt in enumerate([grass0, grass1, grass2, grass3]):
        put_16(0, idx["grass"][v], gt)

    # Row 5: TALL_GRASS 0 (0..15 based on (3, 16) lush tall grass over grass0, feathering unconnected edges)
    tg_center = recolour_rgba(src[(3, 16)], bg_tile=grass0)
    for mask in range(16):
        tg_m = tg_center.copy()
        if not (mask & 1):  # North unconnected: feather top row to grass0 with tall_upper tufts
            for x in range(16):
                tg_m.set(x, 0, grass0.get(x, 0) if x % 3 != 1 else TS_TERRAIN_PALETTE["tall_upper"])
        if not (mask & 4):  # South unconnected: feather bottom row to grass0
            for x in range(16):
                tg_m.set(x, 15, grass0.get(x, 15) if x % 3 != 2 else TS_TERRAIN_PALETTE["tall_upper"])
        if not (mask & 8):  # West unconnected: feather left col to grass0
            for y in range(16):
                tg_m.set(0, y, grass0.get(0, y) if y % 3 != 1 else TS_TERRAIN_PALETTE["tall_upper"])
        if not (mask & 2):  # East unconnected: feather right col to grass0
            for y in range(16):
                tg_m.set(15, y, grass0.get(15, y) if y % 3 != 2 else TS_TERRAIN_PALETTE["tall_upper"])
        put_16(mask, idx["tall_grass"], tg_m)

    # Rows 6..7: TREE 0 (round) and TREE 1 (conifer) — 2-block-tall (16x32 px) Tier 4 sprites (§3.2, §6.3)
    # Columns 0..7 store the bottom 16x16 half (trunk + lower crown) composited over grass0;
    # columns 8..15 store the top 16x16 half (upper crown with transparent background) for the canopy overhang layer.
    terrain_dir = os.path.join(repo_root, "game", "assets", "original", "terrain")
    tree_round_img = al.read_png(os.path.join(terrain_dir, "tree_round.png"))
    tree_conifer_img = al.read_png(os.path.join(terrain_dir, "tree_conifer.png"))
    for v, tree_img in enumerate([tree_round_img, tree_conifer_img]):
        top_16 = tree_img.crop(0, 0, 16, 16)
        bot_16 = tree_img.crop(0, 16, 16, 32)
        for m in range(8):
            # Bottom half (cols 0..7): composited over grass0 (100% opaque)
            b_m = grass0.copy()
            b_m.paste(bot_16, 0, 0, only_opaque=True)
            b_m.set(6, 3, TS_TERRAIN_PALETTE["tall_tip"] if (m & 1) else TS_TERRAIN_PALETTE["tall_mid"])
            b_m.set(7, 3, TS_TERRAIN_PALETTE["tall_tip"] if (m & 2) else TS_TERRAIN_PALETTE["tall_deep"])
            b_m.set(8, 3, TS_TERRAIN_PALETTE["tall_upper"] if (m & 4) else TS_TERRAIN_PALETTE["tall_mid"])
            put_16(m, idx["tree"][v], b_m)

            # Top half (cols 8..15): transparent background around upper crown
            t_m = top_16.copy()
            t_m.set(6, 10, TS_TERRAIN_PALETTE["tall_tip"] if (m & 1) else TS_TERRAIN_PALETTE["tall_mid"])
            t_m.set(7, 10, TS_TERRAIN_PALETTE["tall_tip"] if (m & 2) else TS_TERRAIN_PALETTE["tall_deep"])
            t_m.set(8, 10, TS_TERRAIN_PALETTE["tall_upper"] if (m & 4) else TS_TERRAIN_PALETTE["tall_mid"])
            put_16(8 + m, idx["tree"][v], t_m)

    # Row 8: WATER 0 (0..15 via Rule B from (2..4, 0..2) and center (0, 0))
    w_nw = recolour_rgba(src[(2, 0)])
    w_n  = recolour_rgba(src[(3, 0)])
    w_ne = recolour_rgba(src[(4, 0)])
    w_w  = recolour_rgba(src[(2, 1)])
    w_c  = recolour_rgba(src[(0, 0)])
    w_e  = recolour_rgba(src[(4, 1)])
    w_sw = recolour_rgba(src[(2, 2)])
    w_s  = recolour_rgba(src[(3, 2)])
    w_se = recolour_rgba(src[(4, 2)])
    for mask in range(16):
        w_m = compose_quarter_tiles(w_nw, w_n, w_ne, w_w, w_c, w_e, w_sw, w_s, w_se, mask)
        put_16(mask, idx["water"], w_m)

    # Row 9: SAND 0
    sand0 = recolour_rgba(src[(8, 0)])
    put_16(0, idx["sand"], sand0)

    # Row 10: MARSH 0 (bog moss (5,1) + brackish water pools + reed tufts (22,10))
    marsh_cmap = {
        al.hexc("#8dc435"): TS_TERRAIN_PALETTE["marsh_reed"],
        al.hexc("#84bb2c"): TS_TERRAIN_PALETTE["marsh_mud"],
    }
    marsh0 = recolour_rgba(src[(5, 1)], cmap=marsh_cmap)
    for py in range(4, 8):
        for px_i in range(3, 9):
            if (px_i + py) % 5 != 0:
                marsh0.set(px_i, py, TS_TERRAIN_PALETTE["marsh_pool"])
    for py in range(10, 14):
        for px_i in range(8, 14):
            if (px_i + py) % 5 != 0:
                marsh0.set(px_i, py, TS_TERRAIN_PALETTE["marsh_pool"])
    reeds = recolour_rgba(src[(22, 10)])
    marsh0.paste(reeds, 0, 0, only_opaque=True)
    put_16(0, idx["marsh"], marsh0)

    # Row 11 (PATH 0) and Row 58 (PATH 1 overgrown)
    tuft_fg = recolour_rgba(src[(22, 10)])
    for mask in range(16):
        p_coord = PATH_MASK_COORDS[mask]
        p_clean = recolour_rgba(src[p_coord], bg_tile=grass0)
        put_16(mask, idx["path"], p_clean)
        p_over = p_clean.copy()
        for ty in range(4, 15):
            for tx in range(4, 12):
                c = tuft_fg.get(tx, ty)
                if c[3] >= 128 and (tx + ty) % 2 == 0:
                    p_over.set(tx, ty - 2, TS_TERRAIN_PALETTE["grass_base"])
        put_16(mask, idx["path_overgrown"], p_over)

    #Rows 12..13: ROAD 0 (clean) and ROAD 1 (cracked)
    crack_src = src[(16, 19)]
    for mask in range(16):
        r_coord = ROAD_MASK_COORDS[mask]
        r_clean = recolour_rgba(src[r_coord], bg_tile=grass0)
        put_16(mask, idx["road"][0], r_clean)
        r_crack = r_clean.copy()
        for cy in range(3, 13):
            for cx in range(3, 13):
                if crack_src.rgb(cx, cy) == al.hexc("#908570"):
                    r_crack.set(cx, cy, TS_TERRAIN_PALETTE["road_crack"])
        put_16(mask, idx["road"][1], r_crack)

    # Row 14: RAIL 0 (0..15 via Rule A over grass0)
    for mask in range(16):
        rl_coord = RAIL_MASK_COORDS[mask]
        rl_tile = recolour_rgba(src[rl_coord], bg_tile=grass0)
        # Ensure mask 5/6/7/13/14/15/0 are pairwise distinct at their connected edges
        if mask & 1:
            rl_tile.set(5, 0, TS_TERRAIN_PALETTE["rail_top"])
            rl_tile.set(10, 0, TS_TERRAIN_PALETTE["rail_top"])
        if mask & 2:
            rl_tile.set(15, 5, TS_TERRAIN_PALETTE["rail_top"])
            rl_tile.set(15, 10, TS_TERRAIN_PALETTE["rail_top"])
        if mask & 4:
            rl_tile.set(5, 15, TS_TERRAIN_PALETTE["rail_top"])
            rl_tile.set(10, 15, TS_TERRAIN_PALETTE["rail_top"])
        if mask & 8:
            rl_tile.set(0, 5, TS_TERRAIN_PALETTE["rail_top"])
            rl_tile.set(0, 10, TS_TERRAIN_PALETTE["rail_top"])
        put_16(mask, idx["rail"], rl_tile)

    # Row 15: BRIDGE 0 (0..15 wooden planks over WATER (0,0) with side rails on non-connected edges)
    bridge_h = recolour_rgba(src[(6, 4)], bg_tile=w_c)
    bridge_v = recolour_rgba(src[(5, 4)], bg_tile=w_c)
    for mask in range(16):
        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0
        base_b = bridge_v.copy() if (n_conn or s_conn) and not (e_conn or w_conn) else bridge_h.copy()
        if not n_conn:
            for x in range(16):
                base_b.set(x, 0, TS_TERRAIN_PALETTE["wood_shadow"])
                base_b.set(x, 1, TS_TERRAIN_PALETTE["wood_hi"])
        if not s_conn:
            for x in range(16):
                base_b.set(x, 14, TS_TERRAIN_PALETTE["wood_hi"])
                base_b.set(x, 15, TS_TERRAIN_PALETTE["wood_shadow"])
        if not w_conn:
            for y in range(16):
                base_b.set(0, y, TS_TERRAIN_PALETTE["wood_shadow"])
                base_b.set(1, y, TS_TERRAIN_PALETTE["wood_hi"])
        if not e_conn:
            for y in range(16):
                base_b.set(14, y, TS_TERRAIN_PALETTE["wood_hi"])
                base_b.set(15, y, TS_TERRAIN_PALETTE["wood_shadow"])
        put_16(mask, idx["bridge"], base_b)

    # Row 16 (PLAZA 0) and Row 59 (PLAZA 1 weeded)
    plaza0 = recolour_rgba(src[(6, 2)])
    for i in range(16):
        plaza0.set(i, 0, TS_TERRAIN_PALETTE["plaza_joint"])
        plaza0.set(0, i, TS_TERRAIN_PALETTE["plaza_joint"])
        plaza0.set(i, 8, TS_TERRAIN_PALETTE["plaza_joint"])
        plaza0.set(8, i, TS_TERRAIN_PALETTE["plaza_joint"])
    put_16(0, idx["plaza"], plaza0)

    plaza1 = recolour_rgba(src[(9, 1)])
    for i in range(16):
        plaza1.set(i, 0, TS_TERRAIN_PALETTE["plaza_joint"])
        plaza1.set(0, i, TS_TERRAIN_PALETTE["plaza_joint"])
    for wx, wy in [(3, 4), (4, 4), (11, 12), (12, 12), (8, 8)]:
        plaza1.set(wx, wy, TS_TERRAIN_PALETTE["grass_base"])
        plaza1.set(wx, wy - 1, TS_TERRAIN_PALETTE["grass_hi"])
    put_16(0, idx["plaza_weeded"], plaza1)

    # Rows 17..24 (ROOF 0..7) and Row 25 (ROOF 32 gilded)
    all_roof_variants = [(v, idx["roof"][v]) for v in range(8)] + [(32, idx["roof_landmark"])]
    for v, r_idx in all_roof_variants:
        hi, base, shade, outl = ROOF_RAMPS[v]
        rcmap = {
            al.hexc("#D27134"): hi,
            al.hexc("#B65E26"): base,
            al.hexc("#914A1E"): shade,
        }
        r_base = recolour_rgba(src[(14, 26)], cmap=rcmap)
        for y in range(16):
            for x in range(16):
                if y % 4 == 3:
                    r_base.set(x, y, shade)
                elif y % 4 == 0 and (x + (y // 4) * 3) % 6 == 0:
                    r_base.set(x, y, hi)
        for mask in range(16):
            rm = r_base.copy()
            if not (mask & 1):
                for x in range(16):
                    rm.set(x, 0, outl)
                    rm.set(x, 1, hi)
            if not (mask & 4):
                for x in range(16):
                    rm.set(x, 14, shade)
                    rm.set(x, 15, outl)
            if not (mask & 8):
                for y in range(16):
                    rm.set(0, y, outl)
            if not (mask & 2):
                for y in range(16):
                    rm.set(15, y, outl)
            put_16(mask, r_idx, rm)

    # Rows 26..41 (WALL 0..15) and Rows 42..43 (WALL 32, 40 gilded)
    wall_cmap = {
        al.hexc("#ECE2CD"): WALL_PLASTER["hi"],
        al.hexc("#E6DABF"): WALL_PLASTER["hi"],
        al.hexc("#D9CFB9"): WALL_PLASTER["base"],
        al.hexc("#D9CAA9"): WALL_PLASTER["base"],
        al.hexc("#CDC0A4"): WALL_PLASTER["base"],
        al.hexc("#C4B79B"): WALL_PLASTER["shade"],
        al.hexc("#B4A78C"): WALL_PLASTER["shade"],
        al.hexc("#908570"): WALL_PLASTER["outline"],
    }
    win_cmap = {
        al.hexc("#404040"): WALL_PLASTER["win_gl"],
        al.hexc("#999999"): WALL_PLASTER["win_hi"],
        al.hexc("#C2C2C2"): WALL_PLASTER["win_fr"],
        al.hexc("#DFDFDF"): WALL_PLASTER["hi"],
        al.hexc("#8F673F"): WALL_PLASTER["win_fr"],
        al.hexc("#B98B5E"): TS_TERRAIN_PALETTE["wood_base"],
        al.hexc("#C8A480"): TS_TERRAIN_PALETTE["wood_hi"],
    }
    wall_base_16 = recolour_rgba(src[(15, 16)], cmap=wall_cmap)
    win_fg_16 = recolour_rgba(src[(41, 1)], cmap=win_cmap)
    all_wall_variants = [(v, idx["wall"][v]) for v in range(16)] + [
        (32, idx["wall_landmark"]),
        (40, idx["wall_landmark_win"]),
    ]
    for v, r_idx in all_wall_variants:
        is_gold = v in (32, 40)
        has_win = (v == 40) or (not is_gold and (v & 8) != 0)
        trim_col = ROOF_RAMPS[32 if is_gold else (v % 8)][1]
        outl_col = ROOF_RAMPS[32][2] if is_gold else WALL_PLASTER["outline"]
        wb = wall_base_16.copy()
        if has_win:
            for wy in range(3, 13):
                for wx in range(4, 12):
                    c = win_fg_16.get(wx, wy)
                    if c[3] >= 128:
                        wb.set(wx, wy, c)
        for x in range(16):
            wb.set(x, 15, trim_col)
        for mask in range(16):
            wm = wb.copy()
            if not (mask & 1):
                for x in range(16):
                    wm.set(x, 0, outl_col)
            if not (mask & 4):
                for x in range(16):
                    wm.set(x, 14, trim_col)
            if not (mask & 8):
                for y in range(16):
                    wm.set(0, y, outl_col)
            if not (mask & 2):
                for y in range(16):
                    wm.set(15, y, outl_col)
            put_16(mask, r_idx, wm)

    # Rows 44..51 (DOOR 0..7) and Row 52 (DOOR 32 gilded)
    door_fg = recolour_rgba(src[(32, 0)])
    gilded_door_fg = recolour_rgba(src[(35, 0)], cmap=win_cmap)
    all_door_variants = [(v, idx["door"][v]) for v in range(8)] + [(32, idx["door_landmark"])]
    for v, r_idx in all_door_variants:
        is_gold = (v == 32)
        dt = wall_base_16.copy()
        dt.paste(gilded_door_fg if is_gold else door_fg, 0, 0, only_opaque=True)
        mat_col = ROOF_RAMPS[32 if is_gold else (v % 8)][1]
        for x in range(4, 12):
            dt.set(x, 15, mat_col)
        put_16(0, r_idx, dt)

    # Row 53: FENCE 0 (0..15 wooden fence over grass0)
    fence_post = recolour_rgba(src[(52, 23)])
    fence_h    = recolour_rgba(src[(46, 23)])
    for mask in range(16):
        fm = grass0.copy()
        fm.paste(fence_post, 0, 0, only_opaque=True)
        if mask & 8:
            for y in range(4, 14):
                for x in range(0, 8):
                    c = fence_h.get(x, y)
                    if c[3] >= 128:
                        fm.set(x, y, c)
        if mask & 2:
            for y in range(4, 14):
                for x in range(8, 16):
                    c = fence_h.get(x, y)
                    if c[3] >= 128:
                        fm.set(x, y, c)
        if mask & 1:
            for y in range(0, 8):
                fm.set(7, y, TS_TERRAIN_PALETTE["wood_hi"])
                fm.set(8, y, TS_TERRAIN_PALETTE["wood_seam"])
        if mask & 4:
            for y in range(8, 16):
                fm.set(7, y, TS_TERRAIN_PALETTE["wood_hi"])
                fm.set(8, y, TS_TERRAIN_PALETTE["wood_seam"])
        put_16(mask, idx["fence"], fm)

    # Row 54: FLOWERS 0 (Tier 4 obj_flowers.png over grass0)
    flowers0 = grass0.copy()
    flowers0.paste(al.read_png(os.path.join(terrain_dir, "obj_flowers.png")), 0, 0, only_opaque=True)
    put_16(0, idx["flowers"], flowers0)

    # Row 55: GRAVE 0 (pack headstone (51, 9) over grass0, §3.2)
    grave0 = recolour_rgba(src[(51, 9)], bg_tile=grass0)
    put_16(0, idx["grave"], grave0)

    # Row 56: SIGN 0 (Tier 4 obj_sign.png over grass0)
    sign0 = grass0.copy()
    sign0.paste(al.read_png(os.path.join(terrain_dir, "obj_sign.png")), 0, 0, only_opaque=True)
    put_16(0, idx["sign"], sign0)

    # Row 57: CROP 0 (Tier 4 obj_crop.png over path_pebble soil base)
    crop0 = al.Image(16, 16)
    crop0.fill(TS_TERRAIN_PALETTE["path_pebble"])
    crop0.paste(al.read_png(os.path.join(terrain_dir, "obj_crop.png")), 0, 0, only_opaque=True)
    put_16(0, idx["crop"], crop0)

    # Rows 60..91 & Row 93: Retired broken building rows + RUBBLE v=1 copied from placeholder_v1.png
    placeholder_png = os.path.join(repo_root, "game", "assets", "tiles", "placeholder_v1.png")
    if os.path.isfile(placeholder_png):
        ph_img = al.read_png(placeholder_png)
        retired_rows = idx["roof_broken"] + idx["wall_broken"] + idx["door_broken"] + [idx["rubble"][1]]
        for r_idx in retired_rows:
            row_strip = ph_img.crop(0, r_idx * 32, 512, (r_idx + 1) * 32)
            atlas.paste(row_strip, 0, r_idx * 32, only_opaque=False)

    # Row 92: RUBBLE 0 (committed original decal_rubble.png over grass0)
    decal_rubble_path = os.path.join(repo_root, "game", "assets", "original", "ruins", "decal_rubble.png")
    rubble0 = grass0.copy()
    if os.path.isfile(decal_rubble_path):
        dr_img = al.read_png(decal_rubble_path)
        rubble0.paste(dr_img, 0, 0, only_opaque=True)
    put_16(0, idx["rubble"][0], rubble0)

    # Rows 94..97: fog_rows (solid, d75, d50, d25 across all 16 columns)
    for key, thresh in [("solid", 16), ("d75", 12), ("d50", 8), ("d25", 4)]:
        f_row = fog_rows[key]
        for col in range(16):
            for y in range(32):
                by = (y // 2) % 4
                for x in range(32):
                    bx = (x // 2) % 4
                    if BAYER_4X4[by][bx] < thresh:
                        atlas.set(col * 32 + x, f_row * 32 + y, FOG_RGBA)

    # Encode PNG bytes deterministically (filter 0, zlib level 9)
    def make_chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(atlas.h):
        raw.append(0)
        raw.extend(atlas.px[y * atlas.w * 4:(y + 1) * atlas.w * 4])
    png_bytes = (
        al.PNG_SIG
        + make_chunk(b"IHDR", struct.pack(">IIBBBBB", atlas.w, atlas.h, 8, 6, 0, 0, 0))
        + make_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + make_chunk(b"IEND", b"")
    )

    json_data = {
        "tile_px": 32,
        "rows": row_specs,
        "fog_rows": fog_rows,
    }
    json_bytes = (json.dumps(json_data, indent=2) + "\n").encode("utf-8")

    # Collect the 20 core 16x16 terrain samples for style-reference verification
    terrain_samples = [
        grass0,
        grass1,
        tg_center,
        w_c,
        w_n,
        w_nw,
        w_w,
        w_sw,
        w_s,
        sand0,
        recolour_rgba(src[(8, 11)], bg_tile=grass0),
        recolour_rgba(src[(9,  7)], bg_tile=grass0),
        recolour_rgba(src[(9,  8)], bg_tile=grass0),
        recolour_rgba(src[(8, 16)], bg_tile=grass0),
        recolour_rgba(src[(9, 14)], bg_tile=grass0),
        plaza0,
        plaza1,
        bridge_h,
        recolour_rgba(src[(43, 18)], bg_tile=grass0),
        recolour_rgba(src[(48, 23)], bg_tile=grass0),
    ]
    return png_bytes, json_bytes, terrain_samples


def main():
    parser = argparse.ArgumentParser(description="Build game/assets/tiles/original_v1.{png,json}")
    parser.add_argument("--pack-sheet", default=None, help="Optional path to roguelikeSheet_transparent.png")
    parser.add_argument("--out-png", default=None, help="Output PNG path")
    parser.add_argument("--out-json", default=None, help="Output JSON path")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_png = args.out_png or os.path.join(repo_root, "game", "assets", "tiles", "original_v1.png")
    out_json = args.out_json or os.path.join(repo_root, "game", "assets", "tiles", "original_v1.json")

    png_bytes, json_bytes, _ = generate_original_atlas(args.pack_sheet)
    os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
    with open(out_png, "wb") as f:
        f.write(png_bytes)
    with open(out_json, "wb") as f:
        f.write(json_bytes)
    print(f"Wrote {out_png} ({len(png_bytes)} bytes) and {out_json} ({len(json_bytes)} bytes)")


if __name__ == "__main__":
    main()
