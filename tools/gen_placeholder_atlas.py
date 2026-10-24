#!/usr/bin/env python3
"""
tools/gen_placeholder_atlas.py — Generates placeholder tileset atlas for Tenth Spring.
Contract: docs/implementation_plan_world_generation_slice2.md §5
Rip-trap rule: Draw every pixel from code. Copy nothing, trace nothing from Nintendo.

Outputs:
  - game/assets/tiles/placeholder_v1.png
  - game/assets/tiles/placeholder_v1.json
  - assets/palette/tenth_spring.gpl
"""

import json
import os
import struct
import sys
import zlib

TILE_SIZE = 32
NUM_COLS = 16
WIDTH = NUM_COLS * TILE_SIZE  # 512 px

# Palette colors (§5.3)
PALETTE = {
    # Grass / vegetation
    "grass": (120, 200, 80, 255),          # #78c850
    "grass_tuft": (95, 168, 63, 255),      # #5fa83f
    "tall_grass": (79, 154, 58, 255),      # #4f9a3a
    "tall_blades": (47, 107, 36, 255),     # #2f6b24
    "tall_tips": (143, 216, 106, 255),     # #8fd86a
    "tree_canopy": (58, 125, 58, 255),     # #3a7d3a
    "tree_outline": (36, 92, 42, 255),     # #245c2a
    "tree_highlight": (90, 160, 90, 255),  # #5aa05a
    "tree_trunk": (107, 74, 43, 255),      # #6b4a2b / sleeper
    # Water
    "water": (74, 144, 216, 255),          # #4a90d8
    "water_waves": (120, 180, 240, 255),   # #78b4f0
    "water_deep": (47, 106, 168, 255),     # #2f6aa8
    "shore": (232, 216, 160, 255),         # #e8d8a0 / sand
    "sand_speckle": (208, 188, 128, 255),  # #d0bc80
    # Marsh
    "marsh": (106, 154, 106, 255),        # #6a9a6a
    "marsh_puddle": (74, 122, 138, 255),   # #4a7a8a
    # Paths & Roads
    "path": (216, 192, 144, 255),          # #d8c090
    "path_pebble": (184, 160, 112, 255),   # #b8a070
    "path_edge": (176, 144, 96, 255),      # #b09060
    "road": (138, 138, 144, 255),          # #8a8a90 / roof 7 base
    "road_speckle": (154, 154, 160, 255),  # #9a9aa0
    "road_curb": (200, 200, 200, 255),     # #c8c8c8
    "road_crack": (90, 90, 96, 255),       # #5a5a60 / roof 7 shade
    # Rail & Bridge
    "rail_ballast": (160, 144, 128, 255),  # #a09080
    "rail": (107, 107, 107, 255),          # #6b6b6b
    "bridge_plank": (176, 120, 64, 255),   # #b07840
    "bridge_rail": (122, 80, 40, 255),     # #7a5028 / door
    # Plaza
    "plaza": (176, 176, 184, 255),         # #b0b0b8
    "plaza_joint": (152, 152, 160, 255),   # #9898a0
    # Roofs 0–7 (base, shade)
    "roof0_base": (192, 80, 74, 255),      # #c0504a
    "roof0_shade": (138, 52, 48, 255),     # #8a3430
    "roof1_base": (58, 154, 154, 255),     # #3a9a9a
    "roof1_shade": (37, 106, 106, 255),    # #256a6a
    "roof2_base": (90, 154, 74, 255),      # #5a9a4a
    "roof2_shade": (58, 106, 48, 255),     # #3a6a30
    "roof3_base": (138, 90, 176, 255),     # #8a5ab0
    "roof3_shade": (90, 58, 122, 255),     # #5a3a7a
    "roof4_base": (74, 120, 200, 255),     # #4a78c8
    "roof4_shade": (48, 80, 138, 255),     # #30508a
    "roof5_base": (224, 138, 58, 255),     # #e08a3a
    "roof5_shade": (160, 90, 32, 255),     # #a05a20
    "roof6_base": (176, 144, 200, 255),    # #b090c8
    "roof6_shade": (122, 96, 144, 255),    # #7a6090
    "roof7_base": (138, 138, 144, 255),    # #8a8a90
    "roof7_shade": (90, 90, 96, 255),      # #5a5a60
    # Wall, Window, Door
    "wall": (232, 224, 208, 255),          # #e8e0d0
    "wall_outline": (168, 152, 128, 255),  # #a89880
    "window": (106, 176, 224, 255),        # #6ab0e0
    "window_frame": (58, 90, 128, 255),    # #3a5a80
    "door_frame": (74, 48, 24, 255),       # #4a3018
    # Details & Accents
    "fence": (240, 240, 240, 255),         # #f0f0f0
    "flower_pink": (248, 88, 120, 255),    # #f85878
    "flower_yellow": (248, 208, 48, 255),  # #f8d030
    "flower_white": (255, 255, 255, 255),  # #ffffff
    "grave": (160, 160, 168, 255),         # #a0a0a8
    "grave_outline": (112, 112, 120, 255), # #707078
    "crop": (168, 192, 96, 255),           # #a8c060
    "crop_furrow": (120, 136, 48, 255),    # #788830
    "void": (42, 50, 66, 255),             # #2a3242
    "fog": (13, 17, 25, 255),              # #0d1119
    "ink_outline": (26, 26, 32, 255),      # #1a1a20
    "gold_roof_base": (216, 168, 56, 255),  # #d8a838
    "gold_roof_shade": (160, 90, 32, 255),  # #a05a20 (shared with roof5_shade to stay <= 64 colours)
    # Ruin pass (§11.2 step 8)
    "rafters": (58, 42, 32, 255),           # #3a2a20
    "planks": (138, 106, 64, 255),          # #8a6a40
    "rubble": (138, 122, 106, 255),         # #8a7a6a
    "rubble_shade": (90, 74, 64, 255),      # #5a4a40
    "transparent": (0, 0, 0, 0),
}

ROOF_COLORS = [
    {"base": PALETTE["roof0_base"], "shade": PALETTE["roof0_shade"]},
    {"base": PALETTE["roof1_base"], "shade": PALETTE["roof1_shade"]},
    {"base": PALETTE["roof2_base"], "shade": PALETTE["roof2_shade"]},
    {"base": PALETTE["roof3_base"], "shade": PALETTE["roof3_shade"]},
    {"base": PALETTE["roof4_base"], "shade": PALETTE["roof4_shade"]},
    {"base": PALETTE["roof5_base"], "shade": PALETTE["roof5_shade"]},
    {"base": PALETTE["roof6_base"], "shade": PALETTE["roof6_shade"]},
    {"base": PALETTE["roof7_base"], "shade": PALETTE["roof7_shade"]},
]

BAYER_4X4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

def make_gpl_content() -> str:
    lines = [
        "GIMP Palette",
        "Name: Tenth Spring",
        "Columns: 8",
        "#",
    ]
    # Filter distinct solid colors
    seen = set()
    for name, c in PALETTE.items():
        if name == "transparent":
            continue
        rgb = (c[0], c[1], c[2])
        if rgb in seen:
            continue
        seen.add(rgb)
        label = name.replace("_", " ")
        lines.append(f"{rgb[0]:3d} {rgb[1]:3d} {rgb[2]:3d}\t{label}")
    return "\n".join(lines) + "\n"

class AtlasBuilder:
    def __init__(self, num_rows: int):
        self.num_rows = num_rows
        self.height = num_rows * TILE_SIZE
        self.buffer = bytearray(WIDTH * self.height * 4)

    def set_pixel(self, col: int, row: int, x: int, y: int, color: tuple):
        if not (0 <= x < TILE_SIZE and 0 <= y < TILE_SIZE):
            return
        px = col * TILE_SIZE + x
        py = row * TILE_SIZE + y
        idx = (py * WIDTH + px) * 4
        self.buffer[idx:idx + 4] = bytes(color)

    def get_pixel(self, col: int, row: int, x: int, y: int) -> tuple:
        if not (0 <= x < TILE_SIZE and 0 <= y < TILE_SIZE):
            return (0, 0, 0, 0)
        px = col * TILE_SIZE + x
        py = row * TILE_SIZE + y
        idx = (py * WIDTH + px) * 4
        return tuple(self.buffer[idx:idx + 4])

    def fill_tile(self, col: int, row: int, color: tuple):
        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                self.set_pixel(col, row, x, y, color)

    def draw_void(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["void"])

    def draw_grass(self, row: int, col: int, variant: int):
        self.fill_tile(col, row, PALETTE["grass"])
        tuft_color = PALETTE["grass_tuft"]
        tufts = {
            0: [(4, 6), (12, 18), (20, 8), (26, 22), (8, 25), (18, 28), (24, 14)],
            1: [(6, 10), (14, 5), (22, 12), (5, 20), (16, 24), (25, 26), (10, 15), (28, 4)],
            2: [(8, 8), (18, 6), (24, 18), (6, 24), (14, 16), (26, 10), (12, 28), (22, 26), (4, 14)],
            3: [(10, 12), (20, 16), (6, 6), (16, 22), (24, 28), (14, 26)],
        }.get(variant, [])
        for tx, ty in tufts:
            self.set_pixel(col, row, tx, ty, tuft_color)
            self.set_pixel(col, row, tx + 1, ty, tuft_color)

    def draw_tall_grass(self, row: int, col: int, mask: int):
        self.fill_tile(col, row, PALETTE["tall_grass"])
        blade_color = PALETTE["tall_blades"]
        tip_color = PALETTE["tall_tips"]
        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        # Draw rows of V blades with tips
        for row_idx, by in enumerate([5, 13, 21]):
            if not n_conn and by < 8:
                continue
            if not s_conn and by > 18:
                continue
            for bx in range(2, 29, 5):
                if not w_conn and bx < 6:
                    continue
                if not e_conn and bx > 24:
                    continue
                # Offset every second row
                ox = 2 if row_idx % 2 == 1 else 0
                x = bx + ox
                if x + 2 >= TILE_SIZE:
                    continue
                # V-blade pattern
                self.set_pixel(col, row, x, by, tip_color)
                self.set_pixel(col, row, x + 2, by, tip_color)
                self.set_pixel(col, row, x, by + 1, blade_color)
                self.set_pixel(col, row, x + 1, by + 2, blade_color)
                self.set_pixel(col, row, x + 2, by + 1, blade_color)

    def draw_tree(self, row: int, col: int, variant: int, mask: int):
        self.fill_tile(col, row, PALETTE["grass"])
        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        if variant == 0:
            # Round canopy: centre (16, 13), radius 13
            # Trunk: 4 x 5 px at bottom
            for ty in range(25, 30):
                for tx in range(14, 18):
                    self.set_pixel(col, row, tx, ty, PALETTE["tree_trunk"])

            for y in range(TILE_SIZE):
                for x in range(TILE_SIZE):
                    dx = x - 16
                    dy = y - 13
                    dist_sq = dx * dx + dy * dy
                    is_canopy = (dist_sq <= 13 * 13)
                    # Extend canopy if neighbours connected
                    if n_conn and y < 13 and abs(dx) <= 12:
                        is_canopy = True
                    if s_conn and y >= 13 and y <= 31 and abs(dx) <= 12:
                        is_canopy = True
                    if w_conn and x < 16 and abs(dy) <= 12:
                        is_canopy = True
                    if e_conn and x >= 16 and abs(dy) <= 12:
                        is_canopy = True

                    if is_canopy:
                        # Outline check
                        is_outline = False
                        if not n_conn and y <= 1:
                            is_outline = True
                        elif not s_conn and y >= 25 and not (w_conn or e_conn):
                            is_outline = True
                        elif not w_conn and x <= 4:
                            is_outline = True
                        elif not e_conn and x >= 27:
                            is_outline = True
                        elif dist_sq >= 12 * 12:
                            is_outline = True

                        if is_outline:
                            self.set_pixel(col, row, x, y, PALETTE["tree_outline"])
                        elif dx < -2 and dy < -2 and dist_sq <= 10 * 10:
                            # Highlight arc
                            self.set_pixel(col, row, x, y, PALETTE["tree_highlight"])
                        else:
                            self.set_pixel(col, row, x, y, PALETTE["tree_canopy"])
        else:
            # Variant 1: Conifer (pointed) tree
            # Trunk at bottom
            for ty in range(26, 31):
                for tx in range(14, 18):
                    self.set_pixel(col, row, tx, ty, PALETTE["tree_trunk"])

            for y in range(TILE_SIZE):
                for x in range(TILE_SIZE):
                    is_conifer = False
                    # Three stepped tiers
                    if 4 <= y <= 10 and abs(x - 16) <= (y - 3):
                        is_conifer = True
                    elif 11 <= y <= 18 and abs(x - 16) <= (y - 9) + 2:
                        is_conifer = True
                    elif 19 <= y <= 25 and abs(x - 16) <= (y - 17) + 5:
                        is_conifer = True

                    if n_conn and y < 10 and abs(x - 16) <= 8:
                        is_conifer = True
                    if s_conn and y >= 20 and abs(x - 16) <= 10:
                        is_conifer = True
                    if w_conn and x < 16 and 10 <= y <= 25:
                        is_conifer = True
                    if e_conn and x >= 16 and 10 <= y <= 25:
                        is_conifer = True

                    if is_conifer:
                        if x < 14 and y < 20:
                            self.set_pixel(col, row, x, y, PALETTE["tree_highlight"])
                        elif x > 18 or y == 25:
                            self.set_pixel(col, row, x, y, PALETTE["tree_outline"])
                        else:
                            self.set_pixel(col, row, x, y, PALETTE["tree_canopy"])

    def draw_water(self, row: int, col: int, mask: int):
        self.fill_tile(col, row, PALETTE["water"])
        # Wave dashes
        waves = [(4, 8), (18, 12), (8, 20), (20, 24)]
        for wx, wy in waves:
            for i in range(4):
                self.set_pixel(col, row, wx + i, wy, PALETTE["water_waves"])

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        # Shore (3-px) and deep edge (1-px) on unconnected sides
        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                is_shore = False
                is_deep = False
                if not n_conn:
                    if y < 3:
                        is_shore = True
                    elif y == 3:
                        is_deep = True
                if not s_conn:
                    if y >= 29:
                        is_shore = True
                    elif y == 28:
                        is_deep = True
                if not w_conn:
                    if x < 3:
                        is_shore = True
                    elif x == 3:
                        is_deep = True
                if not e_conn:
                    if x >= 29:
                        is_shore = True
                    elif x == 28:
                        is_deep = True

                if is_shore:
                    self.set_pixel(col, row, x, y, PALETTE["shore"])
                elif is_deep:
                    self.set_pixel(col, row, x, y, PALETTE["water_deep"])

    def draw_sand(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["shore"])
        speckles = [(5, 7), (14, 12), (22, 5), (9, 21), (25, 18), (17, 27), (3, 29), (28, 26)]
        for sx, sy in speckles:
            self.set_pixel(col, row, sx, sy, PALETTE["sand_speckle"])

    def draw_marsh(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["marsh"])
        # Puddles
        for py in range(7, 11):
            for px in range(6, 14):
                self.set_pixel(col, row, px, py, PALETTE["marsh_puddle"])
        for py in range(19, 23):
            for px in range(17, 26):
                self.set_pixel(col, row, px, py, PALETTE["marsh_puddle"])
        # Reeds
        for rx, ry in [(4, 12), (15, 10), (15, 23), (27, 21)]:
            self.set_pixel(col, row, rx, ry, PALETTE["tall_blades"])
            self.set_pixel(col, row, rx, ry - 1, PALETTE["tall_tips"])

    def draw_path(self, row: int, col: int, variant: int, mask: int):
        self.fill_tile(col, row, PALETTE["path"])
        speckles = [(6, 8), (18, 14), (10, 22), (24, 26), (14, 4), (26, 8)]
        for sx, sy in speckles:
            self.set_pixel(col, row, sx, sy, PALETTE["path_pebble"])

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0
        edge_color = PALETTE["path_edge"]

        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                if (not n_conn and y < 2) or (not s_conn and y >= 30) or \
                   (not w_conn and x < 2) or (not e_conn and x >= 30):
                    self.set_pixel(col, row, x, y, edge_color)

        if variant == 1:
            # Overgrown path: grass tufts pushing through (§11.2 step 8)
            tufts = [(7, 7), (15, 11), (22, 16), (9, 20), (19, 25), (25, 10)]
            for tx, ty in tufts:
                self.set_pixel(col, row, tx, ty, PALETTE["grass"])
                self.set_pixel(col, row, tx + 1, ty, PALETTE["grass"])
                self.set_pixel(col, row, tx, ty - 1, PALETTE["tall_tips"])
                self.set_pixel(col, row, tx + 1, ty + 1, PALETTE["tall_blades"])

    def draw_road(self, row: int, col: int, variant: int, mask: int):
        self.fill_tile(col, row, PALETTE["road"])
        speckles = [(7, 9), (21, 7), (11, 23), (25, 21), (15, 15)]
        for sx, sy in speckles:
            self.set_pixel(col, row, sx, sy, PALETTE["road_speckle"])

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0
        curb_color = PALETTE["road_curb"]

        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                if (not n_conn and y < 2) or (not s_conn and y >= 30) or \
                   (not w_conn and x < 2) or (not e_conn and x >= 30):
                    self.set_pixel(col, row, x, y, curb_color)

        if variant == 1:
            # Crack lines and green tuft
            cracks = [(10, 12), (11, 13), (12, 14), (13, 14), (14, 15),
                      (18, 20), (19, 21), (20, 21), (21, 22)]
            for cx, cy in cracks:
                self.set_pixel(col, row, cx, cy, PALETTE["road_crack"])
            # Green tuft
            self.set_pixel(col, row, 13, 13, PALETTE["tall_grass"])
            self.set_pixel(col, row, 13, 12, PALETTE["tall_tips"])

    def draw_rail(self, row: int, col: int, mask: int):
        ballast = PALETTE["rail_ballast"]
        rail_col = PALETTE["rail"]
        sleeper_col = PALETTE["tree_trunk"]

        # 1. Full-tile gravel bed (#a09080), with no frame (§10.4)
        self.fill_tile(col, row, ballast)

        # 2. Connection flags (Bit 0 = N (1), Bit 1 = E (2), Bit 2 = S (4), Bit 3 = W (8))
        n = (mask & 1) != 0
        e = (mask & 2) != 0
        s = (mask & 4) != 0
        w = (mask & 8) != 0

        # With no bits set, it runs east–west (§10.4)
        if not (n or e or s or w):
            e = True
            w = True
        else:
            set_count = (1 if n else 0) + (1 if e else 0) + (1 if s else 0) + (1 if w else 0)
            if set_count == 1:
                # With exactly one bit set, track also runs to opposite edge (straight end piece)
                if n: s = True
                elif s: n = True
                elif e: w = True
                elif w: e = True

        # 3. Sleepers (drawn first, across rails every 6 px)
        # Vertical arms: sleepers across x in [9, 23]
        if n:
            for sy in (3, 4, 9, 10):
                for sx in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
        if s:
            for sy in (21, 22, 27, 28):
                for sx in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
        # Horizontal arms: sleepers across y in [9, 23]
        if w:
            for sx in (3, 4, 9, 10):
                for sy in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
        if e:
            for sx in (21, 22, 27, 28):
                for sy in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)

        # Center sleepers
        if n and s and not (e or w):
            for sy in (15, 16):
                for sx in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
        elif e and w and not (n or s):
            for sx in (15, 16):
                for sy in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
        elif n and e and not (s or w):
            for d in range(-6, 7):
                cx, cy = 16 + d, 16 - d
                self.set_pixel(col, row, cx, cy, sleeper_col)
                self.set_pixel(col, row, cx + 1, cy, sleeper_col)
        elif s and e and not (n or w):
            for d in range(-6, 7):
                cx, cy = 16 + d, 16 + d
                self.set_pixel(col, row, cx, cy, sleeper_col)
                self.set_pixel(col, row, cx + 1, cy, sleeper_col)
        elif s and w and not (n or e):
            for d in range(-6, 7):
                cx, cy = 16 + d, 16 - d
                self.set_pixel(col, row, cx, cy, sleeper_col)
                self.set_pixel(col, row, cx + 1, cy, sleeper_col)
        elif n and w and not (s or e):
            for d in range(-6, 7):
                cx, cy = 16 + d, 16 + d
                self.set_pixel(col, row, cx, cy, sleeper_col)
                self.set_pixel(col, row, cx + 1, cy, sleeper_col)
        elif (n or s) and (e or w):
            for sy in (15, 16):
                for sx in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)
            for sx in (15, 16):
                for sy in range(9, 24):
                    self.set_pixel(col, row, sx, sy, sleeper_col)

        # 4. Rails (two rails 6 px apart, meeting at centre)
        if n and e and not (s or w):
            # L-bend N + E
            for y in range(0, 14):
                self.set_pixel(col, row, 19, y, rail_col)
            for x in range(19, 32):
                self.set_pixel(col, row, x, 13, rail_col)
            for y in range(0, 20):
                self.set_pixel(col, row, 13, y, rail_col)
            for x in range(13, 32):
                self.set_pixel(col, row, x, 19, rail_col)
        elif s and e and not (n or w):
            # L-bend S + E
            for y in range(13, 32):
                self.set_pixel(col, row, 13, y, rail_col)
            for x in range(13, 32):
                self.set_pixel(col, row, x, 13, rail_col)
            for y in range(19, 32):
                self.set_pixel(col, row, 19, y, rail_col)
            for x in range(19, 32):
                self.set_pixel(col, row, x, 19, rail_col)
        elif s and w and not (n or e):
            # L-bend S + W
            for y in range(13, 32):
                self.set_pixel(col, row, 19, y, rail_col)
            for x in range(0, 20):
                self.set_pixel(col, row, x, 13, rail_col)
            for y in range(19, 32):
                self.set_pixel(col, row, 13, y, rail_col)
            for x in range(0, 14):
                self.set_pixel(col, row, x, 19, rail_col)
        elif n and w and not (s or e):
            # L-bend N + W
            for y in range(0, 14):
                self.set_pixel(col, row, 13, y, rail_col)
            for x in range(0, 14):
                self.set_pixel(col, row, x, 13, rail_col)
            for y in range(0, 20):
                self.set_pixel(col, row, 19, y, rail_col)
            for x in range(0, 20):
                self.set_pixel(col, row, x, 19, rail_col)
        else:
            # Straight tracks or T/4-way junctions
            if n:
                for y in range(0, 16):
                    self.set_pixel(col, row, 13, y, rail_col)
                    self.set_pixel(col, row, 19, y, rail_col)
            if s:
                for y in range(16, 32):
                    self.set_pixel(col, row, 13, y, rail_col)
                    self.set_pixel(col, row, 19, y, rail_col)
            if w:
                for x in range(0, 16):
                    self.set_pixel(col, row, x, 13, rail_col)
                    self.set_pixel(col, row, x, 19, rail_col)
            if e:
                for x in range(16, 32):
                    self.set_pixel(col, row, x, 13, rail_col)
                    self.set_pixel(col, row, x, 19, rail_col)

    def draw_bridge(self, row: int, col: int, mask: int):
        self.fill_tile(col, row, PALETTE["bridge_plank"])
        # Plank seams every 4 px
        for y in range(TILE_SIZE):
            if y % 4 == 0:
                for x in range(TILE_SIZE):
                    self.set_pixel(col, row, x, y, PALETTE["bridge_rail"])

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0
        rail_color = PALETTE["bridge_rail"]

        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                if (not n_conn and y < 3) or (not s_conn and y >= 29) or \
                   (not w_conn and x < 3) or (not e_conn and x >= 29):
                    self.set_pixel(col, row, x, y, rail_color)

    def draw_plaza(self, row: int, col: int, variant: int = 0):
        self.fill_tile(col, row, PALETTE["plaza"])
        joint_color = PALETTE["plaza_joint"]
        for y in range(TILE_SIZE):
            for x in range(TILE_SIZE):
                if x % 8 == 0 or y % 8 == 0:
                    self.set_pixel(col, row, x, y, joint_color)
        if variant == 1:
            # Cracked lot with weeds (§11.2 step 8)
            cracks = [(6, 6), (7, 7), (8, 7), (9, 8), (19, 15), (20, 16), (21, 16), (22, 17)]
            for cx, cy in cracks:
                self.set_pixel(col, row, cx, cy, PALETTE["road_crack"])
            weeds = [(8, 8), (16, 16), (24, 8), (8, 24), (20, 17)]
            for wx, wy in weeds:
                self.set_pixel(col, row, wx, wy, PALETTE["tall_grass"])
                self.set_pixel(col, row, wx + 1, wy, PALETTE["tall_blades"])
                self.set_pixel(col, row, wx, wy - 1, PALETTE["tall_tips"])

    def draw_roof(self, row: int, col: int, variant: int, mask: int):
        is_broken = (variant & 16) != 0 and variant != 32
        if variant == 32:
            colors = {"base": PALETTE["gold_roof_base"], "shade": PALETTE["gold_roof_shade"]}
        else:
            colors = ROOF_COLORS[variant % 8]
        self.fill_tile(col, row, colors["base"])
        # Subtle shingle lines
        for y in range(TILE_SIZE):
            if y % 4 == 0:
                for x in range(TILE_SIZE):
                    self.set_pixel(col, row, x, y, colors["shade"])

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        # Ridge highlight where N = 0
        if not n_conn:
            for y in range(2):
                for x in range(TILE_SIZE):
                    self.set_pixel(col, row, x, y, PALETTE["fence"])

        # 3-px eave shadow where S = 0
        if not s_conn:
            for y in range(29, 32):
                for x in range(TILE_SIZE):
                    self.set_pixel(col, row, x, y, colors["shade"])

        # 2-px dark outline where W = 0 or E = 0
        if not w_conn:
            for y in range(TILE_SIZE):
                self.set_pixel(col, row, 0, y, PALETTE["ink_outline"])
                self.set_pixel(col, row, 1, y, PALETTE["ink_outline"])
        if not e_conn:
            for y in range(TILE_SIZE):
                self.set_pixel(col, row, 30, y, PALETTE["ink_outline"])
                self.set_pixel(col, row, 31, y, PALETTE["ink_outline"])

        if is_broken:
            # Dark holes showing rafters (#3a2a20) (§11.2 step 8)
            for hy in range(8, 17):
                for hx in range(9, 20):
                    if (hx - 14) * (hx - 14) + (hy - 12) * (hy - 12) <= 22:
                        if hx % 3 == 0:
                            self.set_pixel(col, row, hx, hy, PALETTE["rafters"])
                        else:
                            self.set_pixel(col, row, hx, hy, PALETTE["ink_outline"])
            for hy in range(20, 26):
                for hx in range(18, 25):
                    if hy % 2 == 0:
                        self.set_pixel(col, row, hx, hy, PALETTE["rafters"])
                    else:
                        self.set_pixel(col, row, hx, hy, PALETTE["ink_outline"])

    def draw_wall(self, row: int, col: int, variant: int, mask: int):
        self.fill_tile(col, row, PALETTE["wall"])
        roof_idx = variant % 8
        is_gold = (variant in (32, 40))
        is_broken = (variant & 16) != 0 and not is_gold
        has_window = (variant == 40) or (not is_gold and ((variant & 8) != 0))

        # Base / foundation trim in roof color (or gold)
        trim_color = PALETTE["gold_roof_base"] if is_gold else ROOF_COLORS[roof_idx]["base"]
        for y in range(30, 32):
            for x in range(TILE_SIZE):
                self.set_pixel(col, row, x, y, trim_color)

        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        outline_color = PALETTE["gold_roof_base"] if is_gold else PALETTE["wall_outline"]

        # Outline where W or E = 0
        if not w_conn:
            for y in range(TILE_SIZE):
                self.set_pixel(col, row, 0, y, outline_color)
                self.set_pixel(col, row, 1, y, outline_color)
        if not e_conn:
            for y in range(TILE_SIZE):
                self.set_pixel(col, row, 30, y, outline_color)
                self.set_pixel(col, row, 31, y, outline_color)

        if not n_conn:
            for x in range(TILE_SIZE):
                self.set_pixel(col, row, x, 0, outline_color)

        if is_broken:
            # Cracked walls (§11.2 step 8)
            cracks = [(5, 6), (6, 7), (6, 8), (7, 9), (7, 10), (24, 18), (25, 19), (25, 20), (26, 21)]
            for cx, cy in cracks:
                self.set_pixel(col, row, cx, cy, PALETTE["rubble_shade"])

        if has_window:
            # 10 x 8 px window centered: x in 11..20, y in 10..17
            for wy in range(10, 18):
                for wx in range(11, 21):
                    # Frame border
                    if wx in (11, 20) or wy in (10, 17) or wx == 15 or wy == 13:
                        self.set_pixel(col, row, wx, wy, PALETTE["window_frame"])
                    else:
                        self.set_pixel(col, row, wx, wy, PALETTE["ink_outline"] if is_broken else PALETTE["window"])
            if is_broken:
                # Boarded with planks (#8a6a40) (§11.2 step 8)
                for py in (11, 12, 15, 16):
                    for px in range(10, 22):
                        self.set_pixel(col, row, px, py, PALETTE["planks"])

    def draw_door(self, row: int, col: int, variant: int):
        self.fill_tile(col, row, PALETTE["wall"])
        is_gold = (variant == 32)
        is_broken = (variant & 16) != 0 and not is_gold
        frame_color = PALETTE["gold_roof_base"] if is_gold else PALETTE["door_frame"]
        # 14 x 20 px door: x in 9..22, y in 10..29
        for dy in range(10, 30):
            for dx in range(9, 23):
                if dx in (9, 22) or dy in (10, 29):
                    self.set_pixel(col, row, dx, dy, frame_color)
                else:
                    self.set_pixel(col, row, dx, dy, PALETTE["bridge_rail"])
        # Handle at (20, 20)
        self.set_pixel(col, row, 20, 20, PALETTE["path"])
        if is_broken:
            # Boarded door with planks (#8a6a40) (§11.2 step 8)
            for py in (13, 14, 19, 20, 25, 26):
                for px in range(8, 24):
                    self.set_pixel(col, row, px, py, PALETTE["planks"])
        # 2-px mat at bottom x in 8..23, y in 30..31
        mat_color = PALETTE["gold_roof_base"] if is_gold else ROOF_COLORS[variant % 8]["base"]
        for my in range(30, 32):
            for mx in range(8, 24):
                self.set_pixel(col, row, mx, my, mat_color)

    def draw_fence(self, row: int, col: int, mask: int):
        self.fill_tile(col, row, PALETTE["grass"])
        n_conn = (mask & 1) != 0
        e_conn = (mask & 2) != 0
        s_conn = (mask & 4) != 0
        w_conn = (mask & 8) != 0

        # Post in centre
        for py in range(10, 26):
            for px in range(14, 18):
                self.set_pixel(col, row, px, py, PALETTE["fence"])

        if n_conn or s_conn:
            # Vertical rails
            for py in range(TILE_SIZE):
                for px in range(14, 18):
                    self.set_pixel(col, row, px, py, PALETTE["fence"])
        if w_conn or e_conn:
            # Horizontal rails
            for py in (14, 21):
                for px in range(TILE_SIZE):
                    self.set_pixel(col, row, px, py, PALETTE["fence"])

    def draw_flowers(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["grass"])
        spots = [
            (7, 8, PALETTE["flower_pink"], PALETTE["flower_yellow"]),
            (21, 9, PALETTE["flower_yellow"], PALETTE["flower_white"]),
            (9, 21, PALETTE["flower_white"], PALETTE["flower_yellow"]),
            (22, 22, PALETTE["flower_pink"], PALETTE["flower_white"]),
        ]
        for fx, fy, petal_col, center_col in spots:
            # Stem
            self.set_pixel(col, row, fx, fy + 2, PALETTE["tall_grass"])
            # Petals
            for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                self.set_pixel(col, row, fx + ox, fy + oy, petal_col)
            # Center
            self.set_pixel(col, row, fx, fy, center_col)

    def draw_grave(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["grass"])
        # Pedestal
        for y in range(25, 28):
            for x in range(8, 24):
                self.set_pixel(col, row, x, y, PALETTE["grave_outline"])
        # Headstone arch: x in 10..21, y in 9..24
        for y in range(9, 25):
            for x in range(10, 22):
                if y == 9 and (x in (10, 21)):
                    continue
                is_edge = (x in (10, 21)) or (y == 9)
                color = PALETTE["grave_outline"] if is_edge else PALETTE["grave"]
                self.set_pixel(col, row, x, y, color)
        # Small cross engraving
        for y in range(12, 18):
            self.set_pixel(col, row, 15, y, PALETTE["grave_outline"])
            self.set_pixel(col, row, 16, y, PALETTE["grave_outline"])
        for x in range(13, 19):
            self.set_pixel(col, row, x, 14, PALETTE["grave_outline"])

    def draw_sign(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["grass"])
        # Wooden post
        for y in range(19, 28):
            for x in range(14, 18):
                self.set_pixel(col, row, x, y, PALETTE["tree_trunk"])
        # 20 x 12 px board: x in 6..25, y in 8..19
        for y in range(8, 20):
            for x in range(6, 26):
                if x in (6, 25) or y in (8, 19):
                    self.set_pixel(col, row, x, y, PALETTE["bridge_rail"])
                else:
                    self.set_pixel(col, row, x, y, PALETTE["bridge_plank"])
        # Sign text hint lines
        for x in range(9, 23):
            self.set_pixel(col, row, x, 12, PALETTE["door_frame"])
            self.set_pixel(col, row, x, 15, PALETTE["door_frame"])

    def draw_crop(self, row: int, col: int):
        self.fill_tile(col, row, PALETTE["crop_furrow"])
        for y in [4, 5, 12, 13, 20, 21, 28, 29]:
            for x in range(TILE_SIZE):
                self.set_pixel(col, row, x, y, PALETTE["crop"])
        # Plant highlights
        for y in [4, 12, 20, 28]:
            for x in range(2, TILE_SIZE, 4):
                self.set_pixel(col, row, x, y, PALETTE["tall_tips"])

    def draw_rubble(self, row: int, col: int, variant: int):
        self.fill_tile(col, row, PALETTE["grass"])
        # Broken masonry with grass tufts (§11.2 step 8)
        stones = [
            (7, 15, 7, 5),
            (15, 13, 8, 6),
            (10, 20, 9, 5),
            (19, 19, 6, 5),
        ]
        if variant == 1:
            # Larger pile for gone building lot centre
            stones.extend([
                (5, 11, 6, 5),
                (12, 9, 8, 5),
                (21, 12, 6, 5),
                (6, 22, 7, 5),
            ])
        for sx, sy, sw, sh in stones:
            for y in range(sy, sy + sh):
                for x in range(sx, sx + sw):
                    is_edge = (x == sx or x == sx + sw - 1 or y == sy or y == sy + sh - 1)
                    self.set_pixel(col, row, x, y, PALETTE["rubble_shade"] if is_edge else PALETTE["rubble"])
        tufts = [(6, 14), (17, 12), (9, 25), (23, 23)] if variant == 0 else [(4, 15), (14, 8), (25, 17), (11, 26), (22, 24)]
        for tx, ty in tufts:
            self.set_pixel(col, row, tx, ty, PALETTE["tall_grass"])
            self.set_pixel(col, row, tx + 1, ty, PALETTE["tall_blades"])
            self.set_pixel(col, row, tx, ty - 1, PALETTE["tall_tips"])

    def draw_fog(self, row: int, coverage_pct: int):
        # Draw across all columns
        threshold_map = {
            100: 16,  # solid
            75: 12,   # 12 / 16
            50: 8,    # 8 / 16
            25: 4,    # 4 / 16
        }
        thresh = threshold_map[coverage_pct]
        for col in range(NUM_COLS):
            for y in range(TILE_SIZE):
                by = (y // 2) % 4
                for x in range(TILE_SIZE):
                    bx = (x // 2) % 4
                    val = BAYER_4X4[by][bx]
                    if val < thresh:
                        self.set_pixel(col, row, x, y, PALETTE["fog"])
                    else:
                        self.set_pixel(col, row, x, y, PALETTE["transparent"])

    def to_png_bytes(self) -> bytes:
        # Build PNG stream with zlib + struct
        raw_scanlines = bytearray()
        stride = WIDTH * 4
        for y in range(self.height):
            raw_scanlines.append(0)  # filter type 0 (None)
            row_start = y * stride
            raw_scanlines.extend(self.buffer[row_start:row_start + stride])

        compressed = zlib.compress(bytes(raw_scanlines), level=9)

        def make_chunk(chunk_type: bytes, data: bytes) -> bytes:
            length = struct.pack(">I", len(data))
            crc = struct.pack(">I", zlib.crc32(chunk_type + data) & 0xffffffff)
            return length + chunk_type + data + crc

        png_header = b"\x89PNG\r\n\x1a\n"
        ihdr_data = struct.pack(">IIBBBBB", WIDTH, self.height, 8, 6, 0, 0, 0)
        ihdr_chunk = make_chunk(b"IHDR", ihdr_data)
        idat_chunk = make_chunk(b"IDAT", compressed)
        iend_chunk = make_chunk(b"IEND", b"")

        return png_header + ihdr_chunk + idat_chunk + iend_chunk

def build_atlas():
    """Builds AtlasBuilder, json_data dict, and gpl string."""
    # Define row allocations
    row_specs = []
    current_row = 0

    def add_row(t_class: int, variant: int, masked: bool, any_variant: bool = False):
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
        row = current_row
        current_row += 1
        return row

    # Row allocations (§5.2)
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
    # Ruin pass rows (§11.2 step 8)
    r_path_overgrown = add_row(7, 1, True)
    r_plaza_weeded = add_row(11, 1, False)
    r_roof_broken = [add_row(12, 16 + v, True) for v in range(8)]
    r_wall_broken = [add_row(13, 16 + v, True) for v in range(16)]
    r_door_broken = [add_row(14, 16 + v, False) for v in range(8)]
    r_rubble = [add_row(20, v, False) for v in range(2)]

    # Fog rows (§5.2)
    fog_solid = current_row; current_row += 1
    fog_d75 = current_row; current_row += 1
    fog_d50 = current_row; current_row += 1
    fog_d25 = current_row; current_row += 1

    total_rows = current_row
    builder = AtlasBuilder(total_rows)

    # Render VOID
    builder.draw_void(r_void, 0)

    # Render GRASS variants
    for v in range(4):
        builder.draw_grass(r_grass[v], 0, v)

    # Render TALL_GRASS
    for mask in range(NUM_COLS):
        builder.draw_tall_grass(r_tall_grass, mask, mask)

    # Render TREE variants
    for v in range(2):
        for mask in range(NUM_COLS):
            builder.draw_tree(r_tree[v], mask, v, mask)

    # Render WATER
    for mask in range(NUM_COLS):
        builder.draw_water(r_water, mask, mask)

    # Render SAND
    builder.draw_sand(r_sand, 0)

    # Render MARSH
    builder.draw_marsh(r_marsh, 0)

    # Render PATH
    for mask in range(NUM_COLS):
        builder.draw_path(r_path, mask, 0, mask)
    for mask in range(NUM_COLS):
        builder.draw_path(r_path_overgrown, mask, 1, mask)

    # Render ROAD variants
    for v in range(2):
        for mask in range(NUM_COLS):
            builder.draw_road(r_road[v], mask, v, mask)

    # Render RAIL
    for mask in range(NUM_COLS):
        builder.draw_rail(r_rail, mask, mask)

    # Render BRIDGE
    for mask in range(NUM_COLS):
        builder.draw_bridge(r_bridge, mask, mask)

    # Render PLAZA
    builder.draw_plaza(r_plaza, 0, 0)
    builder.draw_plaza(r_plaza_weeded, 0, 1)

    # Render ROOF variants
    for v in range(8):
        for mask in range(NUM_COLS):
            builder.draw_roof(r_roof[v], mask, v, mask)
    for v in range(8):
        for mask in range(NUM_COLS):
            builder.draw_roof(r_roof_broken[v], mask, 16 + v, mask)
    for mask in range(NUM_COLS):
        builder.draw_roof(r_roof_landmark, mask, 32, mask)

    # Render WALL variants
    for v in range(16):
        for mask in range(NUM_COLS):
            builder.draw_wall(r_wall[v], mask, v, mask)
    for v in range(16):
        for mask in range(NUM_COLS):
            builder.draw_wall(r_wall_broken[v], mask, 16 + v, mask)
    for mask in range(NUM_COLS):
        builder.draw_wall(r_wall_landmark, mask, 32, mask)
    for mask in range(NUM_COLS):
        builder.draw_wall(r_wall_landmark_win, mask, 40, mask)

    # Render DOOR variants
    for v in range(8):
        builder.draw_door(r_door[v], 0, v)
    for v in range(8):
        builder.draw_door(r_door_broken[v], 0, 16 + v)
    builder.draw_door(r_door_landmark, 0, 32)

    # Render FENCE
    for mask in range(NUM_COLS):
        builder.draw_fence(r_fence, mask, mask)

    # Render FLOWERS
    builder.draw_flowers(r_flowers, 0)

    # Render GRAVE
    builder.draw_grave(r_grave, 0)

    # Render SIGN
    builder.draw_sign(r_sign, 0)

    # Render CROP
    builder.draw_crop(r_crop, 0)

    # Render RUBBLE
    for v in range(2):
        builder.draw_rubble(r_rubble[v], 0, v)

    # Render FOG rows
    builder.draw_fog(fog_solid, 100)
    builder.draw_fog(fog_d75, 75)
    builder.draw_fog(fog_d50, 50)
    builder.draw_fog(fog_d25, 25)

    json_data = {
        "tile_px": TILE_SIZE,
        "rows": row_specs,
        "fog_rows": {
            "solid": fog_solid,
            "d75": fog_d75,
            "d50": fog_d50,
            "d25": fog_d25,
        },
    }
    return builder, json_data, make_gpl_content()

def generate_atlas_assets():
    """Generates placeholder_v1.png, placeholder_v1.json, and tenth_spring.gpl."""
    builder, json_data, gpl_str = build_atlas()
    png_bytes = builder.to_png_bytes()
    json_bytes = json.dumps(json_data, indent=2).encode("utf-8") + b"\n"
    gpl_bytes = gpl_str.encode("utf-8")
    return png_bytes, json_bytes, gpl_bytes

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    png_path = os.path.join(repo_root, "game", "assets", "tiles", "placeholder_v1.png")
    json_path = os.path.join(repo_root, "game", "assets", "tiles", "placeholder_v1.json")
    gpl_path = os.path.join(repo_root, "assets", "palette", "tenth_spring.gpl")

    os.makedirs(os.path.dirname(png_path), exist_ok=True)
    os.makedirs(os.path.dirname(gpl_path), exist_ok=True)

    png_bytes, json_bytes, gpl_bytes = generate_atlas_assets()

    with open(png_path, "wb") as f:
        f.write(png_bytes)
    with open(json_path, "wb") as f:
        f.write(json_bytes)
    with open(gpl_path, "wb") as f:
        f.write(gpl_bytes)

    print(f"Generated {png_path} ({len(png_bytes)} bytes)")
    print(f"Generated {json_path} ({len(json_bytes)} bytes)")
    print(f"Generated {gpl_path} ({len(gpl_bytes)} bytes)")

if __name__ == "__main__":
    main()
