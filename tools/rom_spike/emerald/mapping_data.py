"""
Tenth Spring — the chosen Emerald metatile numbers (agent guide Item 12b)
Contract: docs/design_rom_asset_pipeline.md §4 "Choosing the metatiles"

Numbers only: metatile ids and tileset keys, never pixels. Every entry was chosen by evidence
(behaviour bytes, pixel tests, and the ROM's own map layouts counted as statistics) and is
re-checked by mapping_checks.py before build_mapping.py writes the table.

A metatile id below 512 is a primary-tileset piece; 512 and above belongs to the named
secondary tileset ("secNN", NN = its index in the tileset array).

RULES: (class, variants, masks, metatile, tileset)
  masks is "all" (0-15) or a list; an unmasked class uses [0].
  Mask bits (slice-2 plan §3): bit0 = N, bit1 = E, bit2 = S, bit3 = W, set when that neighbour
  belongs to the tile's family. 15 is an interior; a 0 bit is an edge on that side.
"""

P = "primary"

RULES = [
    # --- ground cover -------------------------------------------------------------------
    # VOID: a flat single-colour piece.
    (0, [0], [0], 0, P),
    # GRASS: the base lawn is the ROM's most frequent plain green piece (12,294 uses). Variants
    # 1-3 are the other three arrangements of the same two lawn textures; the ROM has no more.
    (1, [0], [0], 1, P),
    (1, [1], [0], 910, "sec05"),
    (1, [2], [0], 925, "sec10"),
    (1, [3], [0], 830, "sec03"),
    # TALL_GRASS: behaviour 0x02, blank top layer. The ROM has no tall-grass edge art, so the
    # one piece serves every mask.
    (2, [0], "all", 13, P),
    # SAND: the sand-behaviour (0x21) twin of the plain sand ground (pixel-identical to 289).
    (5, [0], [0], 292, P),
    # FLOWERS: the ROM's own flower-on-lawn piece (560 uses).
    (16, [0], [0], 4, P),
    # CROP: the ROM's plantable-soil behaviour (0xA0) is carried only by bare soil patches; 268 is
    # the full-tile soil with a blank top layer, the centre of the ROM's dirt patch on lawn.
    (19, [0], [0], 268, P),

    # --- footpaths and streets ----------------------------------------------------------
    # PATH: the 3 x 3 footpath block (the ROM's route paths). Every ROM path is at least two
    # tiles wide, so the masks of a 1-wide path are gaps.
    (7, [0], [15], 289, P),
    (7, [0], [14], 281, P),
    (7, [0], [11], 297, P),
    (7, [0], [7], 288, P),
    (7, [0], [13], 290, P),
    (7, [0], [6], 280, P),
    (7, [0], [12], 282, P),
    (7, [0], [3], 296, P),
    (7, [0], [9], 298, P),
    # ROAD: the 3 x 3 cobble paving block of one secondary tileset.
    (8, [0], [15], 529, "sec04"),
    (8, [0], [14], 521, "sec04"),
    (8, [0], [11], 537, "sec04"),
    (8, [0], [7], 528, "sec04"),
    (8, [0], [13], 530, "sec04"),
    (8, [0], [6], 520, "sec04"),
    (8, [0], [12], 522, "sec04"),
    (8, [0], [3], 536, "sec04"),
    (8, [0], [9], 538, "sec04"),
    # PLAZA: the plain herringbone paving of the ROM's largest square.
    (11, [0], [0], 699, "sec02"),

    # --- standing objects ---------------------------------------------------------------
    # TREE variant 0: the small round tree is a stack: canopy, interior rows, then trunk base.
    (3, [0], [0, 2, 4, 6, 8, 10, 12, 14], 14, P),
    (3, [0], [1, 3, 9, 11], 22, P),
    (3, [0], [5, 7, 13, 15], 198, P),
    # TREE variant 1: the ROM's only pointed tree is a 2 x 2 block.
    (3, [1], [6], 30, P),
    (3, [1], [12], 31, P),
    (3, [1], [3], 38, P),
    (3, [1], [9], 39, P),
    # FENCE: the left-aligned fence family (no jog where pieces join).
    (15, [0], [0, 2, 8, 10], 329, P),
    (15, [0], [1, 9], 306, P),
    (15, [0], [3], 328, P),
    (15, [0], [4, 12], 313, P),
    (15, [0], [5], 320, P),
    (15, [0], [6], 312, P),
    # SIGN: a signboard on a post, with lawn behind it; one piece serves all 16 indices.
    (18, list(range(16)), [0], 27, P),
    # RUBBLE variant 0: a single boulder on lawn.
    (20, [0], [0], 224, P),
]

RULES += [
    # --- water --------------------------------------------------------------------------
    # WATER: the flat light pond blue and the ROM's 3 x 3 pond-shore set (water-family behaviours
    # 0x10 and 0x16). Interior 161 is the ROM's plainest pond piece (675 uses); each edge piece
    # is the one the ROM itself places at that neighbour mask, and every water pixel equals the
    # interior's colour exactly, so seams are invisible. Water one tile wide has no piece.
    (4, [0], [15], 161, P),
    (4, [0], [14], 201, P),   # shore on the north side
    (4, [0], [13], 210, P),   # shore on the east side
    (4, [0], [12], 202, P),   # outer corner, shore north and east
    (4, [0], [11], 217, P),   # shore on the south side
    (4, [0], [9], 218, P),    # outer corner, shore east and south
    (4, [0], [7], 208, P),    # shore on the west side
    (4, [0], [6], 200, P),    # outer corner, shore north and west
    (4, [0], [3], 216, P),    # outer corner, shore south and west
    # BRIDGE: the ROM's only bridge-over-water (behaviour 0x2B, all in one secondary tileset), a
    # plank deck exactly two tiles wide. North-south: left half 846, right half 847, north end
    # 848/849, south end 838/839. East-west: upper half 836 over lower half 844. A deck wider than
    # two tiles has an inside (mask 15) that cannot tell the two orientations apart, so it is a gap.
    (10, [0], [7], 846, "sec02"),
    (10, [0], [13], 847, "sec02"),
    (10, [0], [6], 848, "sec02"),
    (10, [0], [12], 849, "sec02"),
    (10, [0], [3], 838, "sec02"),
    (10, [0], [9], 839, "sec02"),
    (10, [0], [14], 836, "sec02"),
    (10, [0], [11], 844, "sec02"),
]

RULES += [
    # --- buildings ----------------------------------------------------------------------
    # Emerald draws a house as two roof rows over two wall rows (door in the bottom row); the
    # synthesiser's larger houses match it, and the 4 x 3 house (one wall row) uses the
    # bottom-row pieces. Pieces were paired by how the ROM's own layouts place them.
    # ROOF: eight honest colourways (0 red tile, 1 brown shingle, 2 green bamboo, 3 purple lattice, 4 blue slate, 5 orange corrugated, 6 pink striped, 7 grey stone) and the gold flat roof for the gilded landmark look (32). Roofs are two rows (ridge row, then eave row); the middle row of a taller roof repeats the eave row (only grey has its own).
    (12, [0], [3, 7], 16, P),
    (12, [0], [6], 8, P),
    (12, [0], [9, 13], 18, P),
    (12, [0], [11, 15], 17, P),
    (12, [0], [12], 10, P),
    (12, [0], [14], 9, P),
    (12, [1], [3, 7], 628, "sec01"),
    (12, [1], [6], 620, "sec01"),
    (12, [1], [9, 13], 630, "sec01"),
    (12, [1], [11, 15], 629, "sec01"),
    (12, [1], [12], 622, "sec01"),
    (12, [1], [14], 621, "sec01"),
    (12, [2], [3, 7], 912, "sec05"),
    (12, [2], [6], 904, "sec05"),
    (12, [2], [9, 13], 914, "sec05"),
    (12, [2], [11, 15], 913, "sec05"),
    (12, [2], [12], 906, "sec05"),
    (12, [2], [14], 905, "sec05"),
    (12, [3], [3, 7], 712, "sec04"),
    (12, [3], [6], 704, "sec04"),
    (12, [3], [9, 13], 714, "sec04"),
    (12, [3], [11, 15], 713, "sec04"),
    (12, [3], [12], 706, "sec04"),
    (12, [3], [14], 705, "sec04"),
    (12, [4], [3, 7], 531, "sec03"),
    (12, [4], [6], 523, "sec03"),
    (12, [4], [9, 13], 533, "sec03"),
    (12, [4], [11, 15], 532, "sec03"),
    (12, [4], [12], 525, "sec03"),
    (12, [4], [14], 524, "sec03"),
    (12, [5], [3, 7], 645, "sec07"),
    (12, [5], [6], 802, "sec07"),
    (12, [5], [9, 13], 647, "sec07"),
    (12, [5], [11, 15], 646, "sec07"),
    (12, [5], [12], 804, "sec07"),
    (12, [5], [14], 803, "sec07"),
    (12, [6], [3, 7], 651, "sec05"),
    (12, [6], [6], 643, "sec05"),
    (12, [6], [9, 13], 653, "sec05"),
    (12, [6], [11, 15], 652, "sec05"),
    (12, [6], [12], 645, "sec05"),
    (12, [6], [14], 644, "sec05"),
    (12, [7], [3], 556, "sec02"),
    (12, [7], [6], 548, "sec02"),
    (12, [7], [7], 566, "sec02"),
    (12, [7], [9], 558, "sec02"),
    (12, [7], [11], 557, "sec02"),
    (12, [7], [12], 550, "sec02"),
    (12, [7], [13], 567, "sec02"),
    (12, [7], [14], 549, "sec02"),
    (12, [7], [15], 574, "sec02"),
    (12, [32], [3, 7], 434, P),
    (12, [32], [6], 426, P),
    (12, [32], [9, 13], 436, P),
    (12, [32], [11, 15], 435, P),
    (12, [32], [12], 428, P),
    (12, [32], [14], 427, P),
    # WALL: variant = colour (0-7), + 8 for a window. Emerald posts never carry a window, so window variants share the post pieces. Where a colourway has no window-less wall piece (1, 2, 5, 32) the door-top or window-bottom piece stands in as the plain wall, as it does in the ROM's own houses. 32 and 40 are the gilded landmark look.
    (13, [0], [14], 12, P),
    (13, [0, 3], [10, 11], 20, P),
    (13, [0, 3, 8, 11], [2, 3], 32, P),
    (13, [0, 3, 8, 11], [8, 9], 34, P),
    (13, [0, 8], [6], 24, P),
    (13, [0, 8], [12], 26, P),
    (13, [1, 9, 32, 40], [2, 3], 644, "sec01"),
    (13, [1, 9, 32, 40], [6], 636, "sec01"),
    (13, [1, 9, 32, 40], [8, 9], 646, "sec01"),
    (13, [1, 9, 32, 40], [10, 11], 655, "sec01"),
    (13, [1, 9, 32, 40], [12], 638, "sec01"),
    (13, [1, 32], [14], 639, "sec01"),
    (13, [2], [14], 921, "sec05"),
    (13, [2, 10], [2, 3], 928, "sec05"),
    (13, [2, 10], [6], 920, "sec05"),
    (13, [2, 10], [8, 9], 916, "sec05"),
    (13, [2, 10], [10, 11], 915, "sec05"),
    (13, [2, 10], [12], 908, "sec05"),
    (13, [3], [14], 715, "sec04"),
    (13, [3, 11], [6], 720, "sec04"),
    (13, [3, 11], [12], 722, "sec04"),
    (13, [4], [10, 11], 551, "sec03"),
    (13, [4], [14], 543, "sec03"),
    (13, [4, 12], [2, 3], 534, "sec03"),
    (13, [4, 12], [6], 526, "sec03"),
    (13, [4, 12], [8, 9], 535, "sec03"),
    (13, [4, 12], [12], 527, "sec03"),
    (13, [5], [14], 669, "sec07"),
    (13, [5, 13], [2, 3], 661, "sec07"),
    (13, [5, 13], [6], 653, "sec07"),
    (13, [5, 13], [8, 9], 663, "sec07"),
    (13, [5, 13], [10, 11], 678, "sec07"),
    (13, [5, 13], [12], 655, "sec07"),
    (13, [6], [10, 11], 668, "sec05"),
    (13, [6], [14], 660, "sec05"),
    (13, [6, 14], [2, 3], 667, "sec05"),
    (13, [6, 14], [6], 659, "sec05"),
    (13, [6, 14], [8, 9], 669, "sec05"),
    (13, [6, 14], [12], 661, "sec05"),
    (13, [7], [10], 541, "sec02"),
    (13, [7], [14], 533, "sec02"),
    (13, [7, 15], [2, 3], 540, "sec02"),
    (13, [7, 15], [6], 532, "sec02"),
    (13, [7, 15], [8, 9], 542, "sec02"),
    (13, [7, 15], [11], 541, "sec02"),
    (13, [7, 15], [12], 534, "sec02"),
    (13, [8], [14], 11, P),
    (13, [8, 11], [10, 11], 19, P),
    (13, [9, 40], [14], 637, "sec01"),
    (13, [10], [14], 907, "sec05"),
    (13, [11], [14], 721, "sec04"),
    (13, [12], [10, 11], 550, "sec03"),
    (13, [12], [14], 542, "sec03"),
    (13, [13], [14], 670, "sec07"),
    (13, [14], [10, 11], 631, "sec05"),
    (13, [14], [14], 623, "sec05"),
    (13, [15], [10, 14], 578, "sec02"),
    # DOOR: the door piece of each colourway's wall set; 32 is the gilded landmark look.
    (14, [0], [0], 33, P),
    (14, [1, 32], [0], 647, "sec01"),
    (14, [2], [0], 929, "sec05"),
    (14, [3], [0], 732, "sec04"),
    (14, [4], [0], 549, "sec03"),
    (14, [5], [0], 677, "sec07"),
    (14, [6], [0], 684, "sec05"),
    (14, [7], [0], 543, "sec02"),
]

SHARED = [
    # Emerald draws its footpath ground and its plain sand identically: 289 is the footpath
    # interior and 292 its sand-behaviour twin, so SAND and the PATH interior share one look.
    {"metatile": 289, "tileset": "primary", "classes": [5, 7],
     "reason": "Emerald draws its footpath ground and its plain sand identically; 289 is the footpath interior and 292 is its sand-behaviour twin."},
]

GAPS = [
    {"id": "marsh_wet_ground", "classes": [6],
     "reason": "The ROM has no marsh art: its one wetland is plain pale lawn dotted with ponds, and the puddle and shallow-water pieces are water edges or pale lawn, so every candidate would be a stand-in."},
    {"id": "rail_track", "classes": [9],
     "reason": "No railway track piece exists; the nearest look-alikes are fences, bridge decks and girders, none a track. A road piece is not a stand-in."},
    {"id": "path_overgrown", "classes": [7], "variants": [1],
     "reason": "No path piece shows weeds on its surface; the lawn rim on edge pieces is a border, not weeds."},
    {"id": "path_one_wide", "classes": [7], "masks": [0, 1, 2, 4, 5, 8, 10],
     "reason": "Every ROM path is at least two tiles wide, so there is no end, isolated or one-wide piece."},
    {"id": "road_cracked", "classes": [8], "variants": [1],
     "reason": "No cracked or broken paving piece exists in any paving family."},
    {"id": "road_one_wide", "classes": [8], "masks": [0, 1, 2, 4, 5, 8, 10],
     "reason": "Every ROM street lane is at least two tiles wide, so there is no end, isolated or one-wide piece."},
    {"id": "plaza_weeded", "classes": [11], "variants": [1],
     "reason": "No paving piece shows weeds or grass tufts across its surface."},
    {"id": "gravestone", "classes": [17],
     "reason": "No headstone or grave marker piece was found on plain ground in any tileset."},
    {"id": "pointed_tree_other_cells", "classes": [3], "variants": [1], "masks": [0, 1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 15],
     "reason": "The ROM's only pointed tree is a 2 x 2 block: there is no single-cell, row, column or grove piece, and a round canopy would be a stand-in."},
    {"id": "fence_junctions", "classes": [15], "masks": [7, 11, 13, 14, 15],
     "reason": "No fence T-junction or crossing piece exists."},
    {"id": "water_one_tile_channel", "classes": [4], "masks": [5, 10],
     "reason": "Water one tile wide with land on both sides: every pond edge piece shows a shore on one side or on two adjacent sides, none on two opposite sides."},
    {"id": "water_dead_end_tip", "classes": [4], "masks": [1, 2, 4, 8],
     "reason": "Water with a single water neighbour (a channel end or peninsula tip, shore on three sides): the pond shore set has no three-sided end piece, and the sea-coloured beach pieces would be a stand-in."},
    {"id": "water_single_cell_pool", "classes": [4], "masks": [0],
     "reason": "An isolated one-tile pool: no pond-coloured piece draws a shore on all four sides."},
    {"id": "bridge_not_two_wide", "classes": [10], "masks": [0, 1, 2, 4, 5, 8, 10, 15],
     "reason": "The ROM's plank bridge is a deck exactly two tiles wide built of paired pieces: there is no plank piece for a one-tile deck or a single cell, and the inside of a wider deck (mask 15) cannot tell a north-south deck from an east-west one."},
    {"id": "roof_ruined", "classes": [12], "variants": list(range(16, 24)),
     "reason": "No crumbling, collapsed or damaged roof art exists in the tilesets that hold houses; intact pieces would misrepresent a ruin, so the placeholder stays."},
    {"id": "wall_ruined", "classes": [13], "variants": list(range(16, 32)),
     "reason": "No broken, cracked or half-fallen wall art exists in the tilesets that hold houses; the placeholder stays."},
    {"id": "door_boarded", "classes": [14], "variants": list(range(16, 24)),
     "reason": "No boarded or broken door piece exists; every door piece is intact, so the placeholder stays."},
    {"id": "roof_masks_never_emitted", "classes": [12], "masks": [0, 1, 2, 4, 5, 8, 10],
     "reason": "The synthesiser's rectangular roofs (at least 4 x 3) never produce these neighbour masks; if one ever appears the placeholder is drawn."},
    {"id": "wall_masks_never_emitted", "classes": [13], "masks": [0, 1, 4, 5, 7, 13, 15],
     "reason": "The synthesiser's walls (one row, or two rows under the roof) never produce these neighbour masks; if one ever appears the placeholder is drawn."},
    {"id": "rubble_large_pile", "classes": [20], "variants": [1],
     "reason": "The only large rock pile sits on a cave floor, not on lawn, so it would read as a patch; the placeholder stays."},
]

# Look-alike buildings lifted from the ROM's own outdoor layouts as rectangles of metatile
# numbers (row-major, w x h), named by function. door is [x, y] of the door piece, or [] for none.
# Block corners can hold scenery cells (trees, a sign, shore); the ids are the layout's own.
COMPOSITIONS = {
    "pyramid_hall": {
        "w": 15, "h": 11, "tileset": "sec15", "door": [7, 9],
        "metatiles": [
        289, 289, 289, 289, 289, 614, 615, 581, 579, 580, 289, 289, 289, 289, 289,
        289, 289, 289, 614, 583, 591, 623, 607, 587, 590, 582, 580, 289, 289, 289,
        804, 614, 583, 591, 591, 630, 595, 595, 595, 596, 590, 590, 582, 580, 800,
        621, 591, 591, 591, 599, 638, 603, 603, 603, 604, 598, 590, 590, 590, 589,
        802, 591, 591, 591, 623, 607, 607, 607, 607, 607, 587, 590, 590, 590, 597,
        802, 591, 591, 630, 595, 595, 595, 595, 595, 595, 595, 596, 590, 590, 597,
        802, 591, 599, 803, 603, 603, 805, 806, 807, 603, 603, 604, 598, 590, 597,
        802, 591, 833, 834, 834, 834, 785, 810, 811, 834, 834, 834, 824, 590, 597,
        802, 630, 828, 812, 813, 813, 814, 815, 816, 813, 813, 817, 829, 596, 597,
        637, 606, 830, 818, 819, 819, 820, 832, 822, 819, 819, 823, 831, 622, 605,
        997, 297, 297, 297, 289, 289, 825, 826, 827, 289, 289, 3, 289, 289, 999,
        ],
    },
    "dome_centre": {
        "w": 9, "h": 8, "tileset": "sec10", "door": [4, 7],
        "metatiles": [
        928, 929, 930, 931, 932, 933, 934, 935, 814,
        936, 937, 938, 939, 940, 941, 942, 943, 822,
        944, 945, 946, 947, 948, 949, 950, 951, 859,
        952, 953, 953, 954, 733, 955, 956, 956, 957,
        960, 961, 961, 962, 733, 963, 964, 964, 965,
        730, 731, 731, 732, 733, 734, 735, 735, 711,
        738, 739, 739, 740, 741, 742, 743, 743, 719,
        746, 747, 747, 748, 749, 750, 751, 751, 727,
        ],
    },
    "tall_tower": {
        "w": 17, "h": 16, "tileset": "sec15", "door": [8, 14],
        "metatiles": [
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 737, 738, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 737, 738, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 737, 738, 695,
        728, 745, 746, 723, 724, 725, 726, 760, 761, 762, 763, 764, 765, 766, 745, 746, 695,
        728, 737, 738, 731, 732, 733, 734, 768, 769, 770, 771, 772, 773, 774, 737, 738, 695,
        736, 737, 738, 739, 740, 741, 742, 776, 801, 778, 779, 780, 781, 782, 737, 738, 703,
        744, 745, 746, 747, 748, 749, 750, 784, 809, 786, 787, 788, 789, 790, 745, 746, 711,
        752, 753, 754, 755, 513, 513, 727, 792, 793, 794, 795, 513, 513, 798, 753, 754, 719,
        ],
    },
    "museum_hall": {
        "w": 10, "h": 7, "tileset": "sec09", "door": [4, 5],
        "metatiles": [
        487, 1, 650, 651, 651, 651, 651, 652, 486, 485,
        2, 2, 608, 609, 610, 610, 610, 634, 2, 2,
        520, 611, 616, 617, 618, 632, 617, 633, 611, 519,
        541, 542, 624, 625, 626, 640, 625, 641, 542, 543,
        512, 517, 517, 513, 514, 515, 516, 517, 517, 518,
        549, 550, 525, 521, 522, 523, 524, 525, 526, 527,
        535, 533, 533, 529, 530, 531, 532, 533, 533, 534,
        ],
    },
    "maritime_hall": {
        "w": 6, "h": 6, "tileset": "sec04", "door": [2, 4],
        "metatiles": [
        776, 777, 778, 778, 779, 780,
        784, 785, 786, 763, 787, 788,
        792, 793, 794, 771, 795, 796,
        800, 801, 802, 802, 803, 804,
        808, 809, 810, 810, 811, 812,
        816, 817, 818, 818, 819, 820,
        ],
    },
    "theatre_hall": {
        "w": 7, "h": 7, "tileset": "sec09", "door": [3, 6],
        "metatiles": [
        704, 705, 705, 705, 705, 705, 706,
        712, 713, 713, 713, 713, 713, 714,
        712, 713, 713, 713, 713, 713, 714,
        712, 713, 713, 713, 713, 713, 714,
        720, 721, 721, 721, 721, 721, 722,
        728, 729, 730, 467, 731, 729, 732,
        736, 737, 738, 475, 739, 737, 740,
        ],
    },
    "dept_store": {
        "w": 9, "h": 7, "tileset": "sec09", "door": [4, 6],
        "metatiles": [
        768, 749, 750, 769, 763, 769, 749, 750, 770,
        768, 769, 769, 769, 769, 769, 769, 769, 770,
        768, 749, 750, 769, 763, 769, 749, 750, 770,
        768, 769, 769, 769, 769, 769, 769, 769, 770,
        768, 749, 750, 757, 758, 759, 749, 750, 770,
        766, 764, 783, 771, 772, 773, 782, 764, 767,
        774, 765, 727, 779, 780, 781, 726, 765, 775,
        ],
    },
    "casino_hall": {
        "w": 7, "h": 4, "tileset": "sec05", "door": [3, 3],
        "metatiles": [
        728, 729, 729, 729, 729, 729, 732,
        736, 737, 737, 737, 737, 737, 740,
        744, 731, 745, 746, 747, 731, 748,
        721, 739, 722, 723, 730, 739, 738,
        ],
    },
    "observatory": {
        "w": 11, "h": 8, "tileset": "sec08", "door": [5, 6],
        "metatiles": [
        145, 729, 730, 672, 673, 674, 672, 673, 676, 677, 124,
        736, 737, 738, 739, 680, 680, 680, 683, 684, 685, 686,
        744, 745, 746, 747, 680, 680, 680, 691, 692, 693, 694,
        752, 753, 754, 688, 689, 690, 688, 689, 700, 701, 702,
        760, 761, 762, 696, 697, 698, 696, 697, 708, 709, 710,
        768, 769, 770, 704, 705, 706, 704, 705, 716, 717, 718,
        199, 777, 778, 712, 713, 714, 712, 713, 724, 725, 726,
        199, 199, 1, 720, 721, 722, 720, 721, 3, 1, 1,
        ],
    },
    "power_station": {
        "w": 15, "h": 9, "tileset": "sec14", "door": [7, 8],
        "metatiles": [
        393, 393, 393, 393, 408, 787, 788, 789, 790, 791, 410, 393, 393, 393, 385,
        368, 563, 792, 793, 794, 795, 796, 797, 798, 799, 560, 561, 792, 743, 410,
        570, 571, 800, 801, 802, 803, 804, 805, 806, 807, 568, 569, 800, 751, 732,
        578, 579, 808, 809, 810, 811, 812, 813, 814, 815, 576, 577, 808, 759, 740,
        586, 587, 816, 817, 818, 819, 820, 821, 822, 823, 584, 585, 816, 767, 748,
        594, 659, 824, 825, 826, 827, 828, 829, 830, 831, 580, 581, 824, 582, 593,
        602, 667, 832, 833, 834, 835, 836, 837, 838, 839, 588, 589, 832, 590, 601,
        610, 675, 840, 841, 842, 843, 844, 603, 846, 847, 596, 597, 840, 598, 609,
        93, 683, 848, 849, 850, 851, 852, 611, 854, 855, 604, 605, 848, 606, 95,
        ],
    },
    "grand_hall": {
        "w": 11, "h": 8, "tileset": "sec11", "door": [5, 5],
        "metatiles": [
        520, 513, 514, 514, 514, 514, 514, 514, 514, 552, 561,
        578, 529, 530, 530, 530, 530, 530, 530, 530, 568, 579,
        512, 513, 514, 514, 514, 514, 514, 514, 514, 552, 553,
        520, 521, 522, 523, 524, 525, 526, 527, 522, 560, 561,
        528, 529, 530, 531, 532, 533, 534, 535, 530, 568, 569,
        536, 537, 538, 539, 540, 541, 542, 543, 538, 576, 577,
        1, 544, 575, 547, 548, 549, 550, 551, 575, 575, 546,
        1, 571, 544, 515, 516, 517, 518, 519, 575, 575, 546,
        ],
    },
    "stadium": {
        "w": 13, "h": 14, "tileset": "sec14", "door": [6, 13],
        "metatiles": [
        617, 627, 626, 627, 626, 627, 633, 627, 626, 627, 626, 627, 626,
        616, 619, 1, 1, 634, 635, 636, 637, 638, 1, 1, 1, 618,
        626, 627, 640, 641, 690, 691, 692, 693, 694, 647, 738, 1, 626,
        1, 737, 648, 649, 690, 691, 692, 693, 694, 655, 746, 747, 1,
        744, 745, 656, 657, 690, 691, 692, 693, 694, 663, 754, 755, 756,
        752, 753, 664, 665, 690, 691, 692, 693, 694, 671, 762, 763, 764,
        760, 761, 672, 673, 690, 691, 692, 693, 694, 679, 770, 771, 772,
        768, 769, 680, 681, 690, 691, 692, 693, 694, 687, 778, 779, 780,
        776, 777, 688, 689, 690, 691, 692, 693, 694, 695, 644, 645, 646,
        741, 742, 696, 697, 698, 699, 700, 701, 702, 703, 652, 653, 654,
        749, 750, 704, 705, 706, 707, 708, 709, 710, 711, 660, 661, 662,
        757, 758, 712, 713, 714, 715, 716, 717, 718, 719, 668, 669, 670,
        765, 766, 720, 721, 722, 723, 642, 725, 726, 727, 676, 677, 678,
        328, 774, 728, 729, 730, 731, 650, 733, 734, 735, 684, 685, 330,
        ],
    },
    "elevated_road": {
        "w": 7, "h": 7, "tileset": "sec05", "door": [],
        "metatiles": [
        754, 754, 754, 754, 754, 754, 754,
        762, 762, 762, 762, 762, 762, 762,
        770, 770, 770, 770, 770, 770, 770,
        778, 778, 778, 778, 778, 778, 778,
        786, 786, 786, 781, 786, 786, 786,
        369, 369, 369, 789, 369, 369, 369,
        369, 369, 369, 797, 369, 369, 369,
        ],
    },
    "maze_house": {
        "w": 5, "h": 6, "tileset": "sec05", "door": [2, 5],
        "metatiles": [
        369, 643, 644, 645, 369,
        643, 651, 652, 653, 645,
        651, 651, 652, 653, 653,
        651, 628, 626, 629, 653,
        672, 675, 676, 675, 674,
        680, 683, 684, 683, 682,
        ],
    },
}
