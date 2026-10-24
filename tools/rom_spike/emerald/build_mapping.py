#!/usr/bin/env python3
"""
Tenth Spring — Build Emerald Tile Mapping Table
Generates game/config/emerald_tile_map.json (numbers only, never pixels).
Covers every (class, variant, mask) from placeholder_v1.json plus look-alike compositions.
"""

import json
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT_PATH = os.path.join(REPO_ROOT, "game", "config", "emerald_tile_map.json")

def build_tile_map():
    tile_map = {}

    # Class 0: VOID
    tile_map["0"] = {"0": {"0": {"metatile": 0}}}

    # Class 1: GRASS (variants 0..3)
    tile_map["1"] = {
        "0": {"0": {"metatile": 1}},
        "1": {"0": {"metatile": 2}},
        "2": {"0": {"metatile": 3}},
        "3": {"0": {"metatile": 1}}
    }

    # Class 2: TALL_GRASS
    tile_map["2"] = {"0": {str(m): {"metatile": 13 if m == 15 else 37} for m in range(16)}}

    # Class 3: TREE (variants 0, 1)
    tile_map["3"] = {
        "0": {str(m): {"metatile": 468} for m in range(16)},
        "1": {str(m): {"metatile": 469} for m in range(16)}
    }

    # Class 4: WATER
    tile_map["4"] = {"0": {str(m): {"metatile": 44 if m == 15 else 52} for m in range(16)}}

    # Class 5: SAND
    tile_map["5"] = {"0": {"0": {"metatile": 76}}}

    # Class 6: MARSH
    tile_map["6"] = {"0": {"0": {"metatile": 76}}}

    # Class 7: PATH (0 normal, 1 overgrown)
    tile_map["7"] = {
        "0": {str(m): {"metatile": 281 if m == 15 else 288} for m in range(16)},
        "1": {str(m): {"metatile": 282 if m == 15 else 289} for m in range(16)}
    }

    # Class 8: ROAD (0 normal, 1 cracked)
    tile_map["8"] = {
        "0": {str(m): {"metatile": 288 if m == 15 else 290} for m in range(16)},
        "1": {str(m): {"metatile": 290 if m == 15 else 297} for m in range(16)}
    }

    # Class 9: RAIL
    tile_map["9"] = {"0": {str(m): {"metatile": 290} for m in range(16)}}

    # Class 10: BRIDGE
    tile_map["10"] = {"0": {str(m): {"metatile": 288} for m in range(16)}}

    # Class 11: PLAZA (0 normal, 1 weeded)
    tile_map["11"] = {
        "0": {"0": {"metatile": 288}},
        "1": {"0": {"metatile": 289}}
    }

    # Class 12: ROOF (standing 0..7, ruined 16..23, landmark 32)
    tile_map["12"] = {}
    for v in range(8):
        tile_map["12"][str(v)] = {str(m): {"metatile": 521} for m in range(16)}
    for v in range(16, 24):
        tile_map["12"][str(v)] = {str(m): {"metatile": 529 if (v % 2 == 0) else 537} for m in range(16)}
    tile_map["12"]["32"] = {str(m): {"metatile": 641} for m in range(16)}

    # Class 13: WALL (standing 0..15, ruined 16..31, landmark 32, 40)
    tile_map["13"] = {}
    for v in range(16):
        is_win = (v & 8) != 0
        tile_map["13"][str(v)] = {str(m): {"metatile": 562 if is_win else 546} for m in range(16)}
    for v in range(16, 32):
        tile_map["13"][str(v)] = {str(m): {"metatile": 570 if (v % 2 == 0) else 568} for m in range(16)}
    tile_map["13"]["32"] = {str(m): {"metatile": 642} for m in range(16)}
    tile_map["13"]["40"] = {str(m): {"metatile": 640} for m in range(16)}

    # Class 14: DOOR (standing 0..7, boarded 16..23, landmark 32)
    tile_map["14"] = {}
    for v in range(8):
        tile_map["14"][str(v)] = {"0": {"metatile": 560}}
    for v in range(16, 24):
        tile_map["14"][str(v)] = {"0": {"metatile": 568}}
    tile_map["14"]["32"] = {"0": {"metatile": 688}}

    # Class 15: FENCE
    tile_map["15"] = {"0": {str(m): {"metatile": 330 if m == 15 else 331} for m in range(16)}}

    # Class 16: FLOWERS
    tile_map["16"] = {"0": {"0": {"metatile": 14}}}

    # Class 17: GRAVE
    tile_map["17"] = {"0": {"0": {"metatile": 33}}}

    # Class 18: SIGN
    tile_map["18"] = {str(v): {"0": {"metatile": 33}} for v in range(16)}

    # Class 19: CROP
    tile_map["19"] = {"0": {"0": {"metatile": 85}}}

    # Class 20: RUBBLE (0 small, 1 large)
    tile_map["20"] = {
        "0": {"0": {"metatile": 116}},
        "1": {"0": {"metatile": 124}}
    }

    return tile_map


def main():
    data = {
        "version": 1,
        "tilesets": {
            "primary": 0,
            "petalburg": 1,
            "rustboro": 2,
            "slateport": 4,
            "mauville": 5,
            "lilycove": 9,
            "mossdeep": 10,
            "battle_frontier": 44
        },
        "tile_map": build_tile_map(),
        "buildings": {
            "house_s": {
                "w": 4,
                "h": 3,
                "door": [1, 2],
                "roof_colors": {
                    "0": {"metatiles": [8, 9, 9, 10, 16, 17, 17, 18, 24, 11, 25, 26]},
                    "1": {"metatiles": [520, 521, 521, 522, 528, 529, 529, 530, 546, 560, 562, 545]},
                    "2": {"metatiles": [524, 525, 525, 526, 532, 533, 533, 534, 542, 577, 527, 543]},
                    "3": {"metatiles": [8, 9, 9, 10, 16, 17, 17, 18, 24, 11, 25, 26]},
                    "4": {"metatiles": [520, 521, 521, 522, 528, 529, 529, 530, 546, 560, 562, 545]},
                    "5": {"metatiles": [524, 525, 525, 526, 532, 533, 533, 534, 542, 577, 527, 543]},
                    "6": {"metatiles": [8, 9, 9, 10, 16, 17, 17, 18, 24, 11, 25, 26]},
                    "7": {"metatiles": [520, 521, 521, 522, 528, 529, 529, 530, 546, 560, 562, 545]}
                }
            },
            "house_m": {
                "w": 5,
                "h": 4,
                "door": [2, 3],
                "roof_colors": {
                    "0": {"metatiles": [8, 9, 9, 9, 10, 16, 17, 17, 17, 18, 24, 25, 11, 25, 26, 32, 33, 19, 33, 34]},
                    "1": {"metatiles": [520, 521, 521, 521, 522, 528, 529, 529, 529, 530, 546, 562, 560, 562, 545, 554, 570, 568, 570, 553]},
                    "2": {"metatiles": [524, 525, 525, 525, 526, 532, 533, 533, 533, 534, 542, 527, 577, 527, 543, 550, 535, 585, 535, 551]},
                    "3": {"metatiles": [8, 9, 9, 9, 10, 16, 17, 17, 17, 18, 24, 25, 11, 25, 26, 32, 33, 19, 33, 34]},
                    "4": {"metatiles": [520, 521, 521, 521, 522, 528, 529, 529, 529, 530, 546, 562, 560, 562, 545, 554, 570, 568, 570, 553]},
                    "5": {"metatiles": [524, 525, 525, 525, 526, 532, 533, 533, 533, 534, 542, 527, 577, 527, 543, 550, 535, 585, 535, 551]},
                    "6": {"metatiles": [8, 9, 9, 9, 10, 16, 17, 17, 17, 18, 24, 25, 11, 25, 26, 32, 33, 19, 33, 34]},
                    "7": {"metatiles": [520, 521, 521, 521, 522, 528, 529, 529, 529, 530, 546, 562, 560, 562, 545, 554, 570, 568, 570, 553]}
                }
            },
            "block_l": {
                "w": 6,
                "h": 5,
                "door": [2, 4],
                "roof_colors": {
                    "0": {"metatiles": [8, 9, 9, 9, 9, 10, 16, 17, 17, 17, 17, 18, 16, 17, 17, 17, 17, 18, 24, 25, 11, 25, 25, 26, 32, 33, 19, 33, 33, 34]},
                    "1": {"metatiles": [520, 521, 521, 521, 521, 522, 528, 529, 529, 529, 529, 530, 536, 537, 537, 537, 537, 538, 546, 562, 560, 562, 562, 545, 554, 570, 568, 570, 570, 553]},
                    "2": {"metatiles": [524, 525, 525, 525, 525, 526, 532, 533, 533, 533, 533, 534, 532, 533, 533, 533, 533, 534, 542, 527, 577, 527, 527, 543, 550, 535, 585, 535, 535, 551]},
                    "3": {"metatiles": [8, 9, 9, 9, 9, 10, 16, 17, 17, 17, 17, 18, 16, 17, 17, 17, 17, 18, 24, 25, 11, 25, 25, 26, 32, 33, 19, 33, 33, 34]},
                    "4": {"metatiles": [520, 521, 521, 521, 521, 522, 528, 529, 529, 529, 529, 530, 536, 537, 537, 537, 537, 538, 546, 562, 560, 562, 562, 545, 554, 570, 568, 570, 570, 553]},
                    "5": {"metatiles": [524, 525, 525, 525, 525, 526, 532, 533, 533, 533, 533, 534, 532, 533, 533, 533, 533, 534, 542, 527, 577, 527, 527, 543, 550, 535, 585, 535, 535, 551]},
                    "6": {"metatiles": [8, 9, 9, 9, 9, 10, 16, 17, 17, 17, 17, 18, 16, 17, 17, 17, 17, 18, 24, 25, 11, 25, 25, 26, 32, 33, 19, 33, 33, 34]},
                    "7": {"metatiles": [520, 521, 521, 521, 521, 522, 528, 529, 529, 529, 529, 530, 536, 537, 537, 537, 537, 538, 546, 562, 560, 562, 562, 545, 554, 570, 568, 570, 570, 553]}
                }
            }
        },
        "compositions": {
            "pyramid_hall": {
                "w": 10,
                "h": 8,
                "tileset": "battle_frontier",
                "door": [5, 7],
                "metatiles": [
                    641, 641, 681, 681, 681, 681, 681, 681, 642, 534,
                    641, 641, 641, 681, 681, 681, 681, 681, 642, 534,
                    641, 641, 641, 641, 637, 636, 636, 636, 636, 524,
                    641, 641, 641, 641, 654, 531, 531, 531, 531, 547,
                    641, 681, 681, 681, 654, 531, 518, 539, 539, 519,
                    638, 681, 681, 681, 645, 644, 540, 534, 534, 538,
                    653, 681, 681, 681, 681, 642, 534, 534, 534, 534,
                    547, 636, 636, 636, 547, 524, 534, 534, 522, 546
                ]
            },
            "space_center": {
                "w": 9,
                "h": 8,
                "tileset": "mossdeep",
                "door": [4, 7],
                "metatiles": [
                    928, 929, 930, 931, 932, 933, 934, 935, 814,
                    936, 937, 938, 939, 940, 941, 942, 943, 822,
                    944, 945, 946, 947, 948, 949, 950, 951, 859,
                    952, 953, 953, 954, 733, 955, 956, 956, 957,
                    960, 961, 961, 962, 733, 963, 964, 964, 965,
                    730, 731, 731, 732, 733, 734, 735, 735, 711,
                    738, 739, 739, 740, 741, 742, 743, 743, 719,
                    746, 747, 747, 748, 749, 750, 751, 751, 727
                ]
            },
            "battle_tower": {
                "w": 6,
                "h": 8,
                "tileset": "battle_frontier",
                "door": [3, 7],
                "metatiles": [
                    518, 539, 539, 519, 531, 531,
                    540, 534, 534, 538, 644, 644,
                    534, 688, 534, 534, 640, 681,
                    534, 534, 534, 534, 640, 681,
                    524, 534, 534, 522, 636, 636,
                    547, 523, 523, 546, 531, 531,
                    531, 531, 531, 531, 531, 531,
                    531, 531, 531, 531, 531, 531
                ]
            },
            "art_museum": {
                "w": 6,
                "h": 6,
                "tileset": "lilycove",
                "door": [2, 5],
                "metatiles": [
                    650, 651, 651, 651, 651, 652,
                    608, 609, 610, 610, 610, 634,
                    616, 617, 618, 632, 617, 633,
                    624, 625, 626, 640, 625, 641,
                    517, 513, 514, 515, 516, 517,
                    525, 521, 522, 523, 524, 525
                ]
            },
            "maritime_museum": {
                "w": 7,
                "h": 6,
                "tileset": "slateport",
                "door": [3, 5],
                "metatiles": [
                    661, 662, 662, 662, 662, 662, 663,
                    669, 670, 670, 670, 670, 670, 671,
                    669, 670, 670, 670, 670, 670, 671,
                    677, 678, 678, 678, 678, 678, 679,
                    685, 616, 701, 702, 703, 617, 687,
                    693, 694, 709, 710, 727, 694, 695
                ]
            },
            "contest_hall": {
                "w": 7,
                "h": 7,
                "tileset": "slateport",
                "door": [2, 6],
                "metatiles": [
                    656, 659, 657, 657, 657, 657, 659,
                    664, 667, 665, 665, 665, 665, 667,
                    768, 769, 769, 769, 769, 769, 769,
                    768, 769, 769, 769, 769, 769, 769,
                    672, 673, 673, 673, 683, 673, 683,
                    680, 681, 684, 681, 681, 681, 681,
                    688, 689, 692, 689, 689, 689, 689
                ]
            },
            "dept_store": {
                "w": 4,
                "h": 5,
                "tileset": "lilycove",
                "door": [2, 4],
                "metatiles": [
                    619, 620, 621, 622,
                    80, 81, 82, 83,
                    88, 89, 90, 91,
                    96, 97, 98, 99,
                    554, 555, 556, 555
                ]
            },
            "game_corner": {
                "w": 4,
                "h": 4,
                "tileset": "mauville",
                "door": [1, 3],
                "metatiles": [
                    72, 73, 74, 75,
                    80, 81, 82, 83,
                    88, 89, 90, 91,
                    96, 97, 98, 99
                ]
            },
            "weather_institute": {
                "w": 4,
                "h": 4,
                "tileset": "primary",
                "door": [1, 3],
                "metatiles": [
                    8, 9, 9, 10,
                    16, 17, 17, 18,
                    24, 25, 11, 26,
                    32, 33, 19, 34
                ]
            },
            "power_plant": {
                "w": 6,
                "h": 4,
                "tileset": "mauville",
                "door": [3, 3],
                "metatiles": [
                    740, 751, 691, 692, 693, 746,
                    748, 759, 699, 700, 701, 747,
                    751, 751, 744, 743, 745, 806,
                    759, 759, 750, 742, 742, 750
                ]
            },
            "league_hall": {
                "w": 9,
                "h": 6,
                "tileset": "primary",
                "door": [4, 5],
                "metatiles": [
                    513, 514, 514, 514, 514, 514, 514, 514, 552,
                    529, 530, 530, 530, 530, 530, 530, 530, 568,
                    513, 514, 514, 514, 514, 514, 514, 514, 552,
                    521, 522, 523, 524, 525, 526, 527, 522, 560,
                    529, 530, 531, 532, 533, 534, 535, 530, 568,
                    544, 575, 547, 548, 549, 550, 551, 575, 575
                ]
            },
            "stadium": {
                "w": 11,
                "h": 10,
                "tileset": "battle_frontier",
                "door": [5, 9],
                "metatiles": [
                    641, 641, 641, 641, 641, 649, 649, 641, 641, 681, 681,
                    641, 641, 641, 641, 642, 534, 534, 640, 681, 681, 681,
                    641, 641, 641, 641, 642, 534, 534, 640, 681, 641, 641,
                    641, 641, 641, 641, 641, 633, 633, 681, 641, 641, 641,
                    638, 641, 641, 641, 641, 641, 641, 641, 641, 641, 641,
                    653, 641, 641, 641, 641, 641, 641, 641, 641, 641, 641,
                    653, 641, 641, 641, 641, 641, 641, 641, 641, 641, 641,
                    653, 641, 641, 641, 641, 641, 641, 641, 641, 641, 641,
                    546, 638, 641, 641, 641, 641, 681, 641, 641, 641, 641,
                    546, 636, 636, 636, 636, 636, 636, 636, 636, 546, 531
                ]
            },
            "cycling_road": {
                "w": 4,
                "h": 4,
                "tileset": "mauville",
                "door": [2, 3],
                "metatiles": [
                    40, 41, 41, 43,
                    48, 49, 50, 51,
                    56, 57, 58, 59,
                    96, 65, 66, 67
                ]
            },
            "trick_house": {
                "w": 5,
                "h": 4,
                "tileset": "slateport",
                "door": [2, 3],
                "metatiles": [
                    704, 705, 705, 705, 706,
                    712, 713, 713, 713, 714,
                    728, 721, 723, 721, 730,
                    717, 19, 731, 19, 718
                ]
            }
        },
        "gaps": [
            "snow_terrain",
            "high_speed_rail",
            "modern_asphalt_highways",
            "skyscraper_modern_glass_facades",
            "modern_streetlights_and_traffic_signals",
            "modern_automobiles_and_buses"
        ]
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w") as f:
        json.dump(data, f, indent=2)
    print(f"PASS: Wrote emerald_tile_map.json ({len(data['compositions'])} compositions)")

if __name__ == "__main__":
    main()
