#!/usr/bin/env python3
"""
Tenth Spring — validation rules for game/config/emerald_tile_map.json (agent guide Item 12b)
Contract: docs/implementation_plan_rom_tiles.md §3, docs/design_rom_asset_pipeline.md §4

Each check reads the table (metatile numbers only) and the player's own Emerald tilesets, and
returns a list of problem strings; an empty list means the rule holds. The spike's tests run
them on the committed table and, as falsifying cases, on deliberately wrong tables. The
importer repeats the same rules on the player's machine before it accepts a table.

Nothing from the ROM is stored here: only thresholds and numbers.
Pure Python 3 standard library; run under python3 -I.
"""

import colorsys
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rom_spike as rs  # noqa: E402

GRASS_SHARE_MIN = 0.90          # a lawn variant draws >= 90% of its pixels from the base lawn's colours
WATER_INTERIOR_MIN = 0.95       # a mask-15 water piece is >= 95% water-coloured
WATER_SHORE_MIN = 0.25          # a 0-bit side shows >= 25% non-water (shore) pixels in its band
WATER_SIDE_WATER_MIN = 0.90     # a 1-bit side's band is >= 90% water-coloured
TALL_GRASS_VARIANCE_MIN = 500.0 # per-channel variance of a tall-grass piece
ROOF_COLOURWAYS_MIN = 4         # distinct roof hues among variants 0-7
BRIDGE_BEHAVIOURS = (0x2B,)     # the ROM's bridge-over-water behaviour byte
SAND_BEHAVIOURS = (0x21,)       # the ROM's sand behaviour byte
SOIL_BEHAVIOURS = (0xA0,)       # the ROM's plantable-soil behaviour byte (carried only by bare soil patches)
DOOR_BEHAVIOURS = (0x60, 0x69)  # the door bytes the ROM's house, hall and tower doors carry
ROOF_BEHAVIOURS = (0x00,)
WALL_BEHAVIOURS = (0x00, 0x01)
DOOR_PIECE_BEHAVIOURS = (0x69,)
GRASS_STRAY_CLUSTER_MAX = 3     # the largest run of non-lawn pixels in a lawn variant
WATER_COLOUR_CONTAINMENT_MIN = 0.99  # water pixels of an edge piece drawn in the interior's colours
WATER_CENTRE_MIN = 0.90         # the central 8 x 8 of any water piece is water
WATER_CORNER_MIN = 0.90         # each 4 x 4 corner of the mask-15 piece is water
NO_DOOR_COMPOSITIONS = ("elevated_road",)  # a raised road has no door
BUILDING_NAMES = ("house_s", "house_m", "block_l")
MIN_REASON_LENGTH = 12

TILESET_KEY_RE = re.compile(r"^(primary|sec\d{2})$")

GAP_ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
MAX_CLASS = 20
REASON_RE = re.compile(r"^[A-Za-z0-9 .,;:()'/+=<>%&*-]{1,700}$")

# SHA-1 of lowercase words (Emerald town names) that must never appear in a tileset key, composition
# id, gap id, or reason. Only hashes are kept here, so the list itself names nothing (F59).
FORBIDDEN_WORD_HASHES = frozenset([
    "07281436eac0ba2aab506ed7c55832e31b0b8f84",
    "1843f754e35180d7525365f8a92e7b7183451956",
    "2b1eb70c04fe75c9c268a1f6c29373ba0c4df57f",
    "2c14f9cc7d65dbf32dba39b5e79c6d9df993f346",
    "3d7b33ee943923091685dd56effc3b9f9f8b7229",
    "48abf82a23ecc71f9052d96a7e252eb0a586d90f",
    "5117003592ec9a37e2437803a9e6a8cf49e9af6e",
    "65a810ffae64bb5f357352dbf745716be3ad93b7",
    "68c7a8605cc90dc4b87704435ae7253b94492ec9",
    "7caf7adf4b7dc1fe1042e21ad99b487ab1f50fe1",
    "8b7566bf946baf356143798e31e22bd78c30ed05",
    "90ec1af77abffb9c5d7740b41dd78381ec143c23",
    "9c9dc45bfc9e58baf6a385c300453f918509375a",
    "a57bc80ac1e61c5de03f5702ace5010a7fd47979",
    "a5b3382f8fbef09cffcf6751a3ab6060f5cd0dc2",
    "d70eb661a62099c586cbb3008fbec80e372e69ae",
])

# Compositions are named by function, never by the Nintendo place or facility they came from.
COMPOSITION_IDS = (
    "pyramid_hall", "dome_centre", "tall_tower", "museum_hall", "maritime_hall", "theatre_hall",
    "dept_store", "casino_hall", "observatory", "power_station", "grand_hall", "stadium",
    "elevated_road", "maze_house",
)


def iter_entries(mapping):
    """Yields (class, variant, mask_key, entry) for every tile_map entry."""
    for cls_s, by_var in mapping.get("tile_map", {}).items():
        for var_s, by_mask in by_var.items():
            for mask_s, entry in by_mask.items():
                yield int(cls_s), int(var_s), mask_s, entry


def entry_key(entry):
    """(metatile, tileset) as the importer resolves it. A primary-range id (< 512) is a primary
    piece whatever tileset key the entry carries, so a stray key cannot hide a share."""
    if entry["metatile"] < rs.PRIMARY_METATILE_COUNT:
        return (entry["metatile"], "primary")
    return (entry["metatile"], entry.get("tileset", "primary"))


def _loaded(tilesets, key):
    return key == "primary" or key in tilesets


def _render(tilesets, entry):
    return rs.render_entry(tilesets, entry["metatile"], entry.get("tileset", "primary"))


def _label(cls, var, mask, entry):
    return "class %s variant %s mask %s (metatile %s, %s)" % (
        cls, var, mask, entry.get("metatile"), entry.get("tileset", "primary"))


def _mean(canvas):
    px = rs.canvas_pixels(canvas)
    n = float(len(px))
    return tuple(sum(p[i] for p in px) / n for i in range(3))


def _variance(canvas):
    px = rs.canvas_pixels(canvas)
    n = float(len(px))
    mean = _mean(canvas)
    return tuple(sum((p[i] - mean[i]) ** 2 for p in px) / n for i in range(3))


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def _largest_cluster(canvas, colours):
    """Size of the largest 8-connected run of pixels whose colour is not in `colours`."""
    pts = {(x, y) for y in range(16) for x in range(16) if canvas[y][x] not in colours}
    seen, best = set(), 0
    for start in sorted(pts):
        if start in seen:
            continue
        stack, size = [start], 0
        seen.add(start)
        while stack:
            x, y = stack.pop()
            size += 1
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in pts and q not in seen:
                        seen.add(q)
                        stack.append(q)
        best = max(best, size)
    return best


def check_grass(tilesets, mapping):
    """Every GRASS variant is plain lawn: ordinary behaviour 0x00, >= 90% of its pixels from the base
    lawn's colours with no compact patch of other colours (a corner wedge of another object), and no
    object painted over it."""
    problems = []
    tile_map = mapping["tile_map"]
    base = rs.lookup_entry(tile_map, 1, 0, 0)
    if base is None:
        return ["GRASS variant 0 has no entry"]
    if not _loaded(tilesets, base.get("tileset", "primary")):
        return ["GRASS variant 0 names an unknown tileset"]
    base_canvas = _render(tilesets, base)
    base_colours = rs.colour_set(base_canvas)
    r, g, b = _mean(base_canvas)
    if not (g > r and g > b):
        problems.append("GRASS base lawn is not green-dominant (mean %.0f/%.0f/%.0f)" % (r, g, b))
    gaps = rs.gap_rules(mapping)
    for var in range(4):
        if rs.in_gap(gaps, 1, var, 0):
            continue
        entry = rs.lookup_entry(tile_map, 1, var, 0)
        if entry is None:
            problems.append("GRASS variant %d has no entry and is not a gap" % var)
            continue
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("GRASS variant %d names an unknown tileset" % var)
            continue
        canvas = _render(tilesets, entry)
        s = rs.colour_share(canvas, base_colours)
        if s < GRASS_SHARE_MIN:
            problems.append("GRASS variant %d (metatile %d) draws only %.0f%% of its pixels from the lawn's colours (needs >= %.0f%%)"
                            % (var, entry["metatile"], s * 100, GRASS_SHARE_MIN * 100))
        cluster = _largest_cluster(canvas, base_colours)
        if cluster > GRASS_STRAY_CLUSTER_MAX:
            problems.append("GRASS variant %d (metatile %d) has a patch of %d non-lawn pixels (at most %d)"
                            % (var, entry["metatile"], cluster, GRASS_STRAY_CLUSTER_MAX))
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh != 0x00:
            problems.append("GRASS variant %d (metatile %d) has behaviour %s, not the ordinary 0x00"
                            % (var, entry["metatile"], None if beh is None else "0x%02X" % beh))
        if not rs.top_layer_blank(tilesets, entry["metatile"], key):
            problems.append("GRASS variant %d (metatile %d) paints an object over the lawn" % (var, entry["metatile"]))
    return problems


def _centre_share(canvas, predicate):
    px = [canvas[y][x] for y in range(4, 12) for x in range(4, 12)]
    return sum(1 for p in px if predicate(p)) / float(len(px))


def _corner_shares(canvas, predicate):
    out = []
    for cy in (0, 12):
        for cx in (0, 12):
            px = [canvas[y][x] for y in range(cy, cy + 4) for x in range(cx, cx + 4)]
            out.append(sum(1 for p in px if predicate(p)) / 16.0)
    return out


def check_water(tilesets, mapping):
    """Every mapped WATER mask is a standing-water piece (not a waterfall). Mask 15 is >= 95%
    water-coloured with water in each 4 x 4 corner; every piece has water in its centre and draws its
    water in the interior's own colours (so the shore never sits as a seam beside the lake); for every
    mask (15 included), a 0 bit shows shore pixels on that side and a 1 bit continues the water."""
    problems = []
    tile_map = mapping["tile_map"]
    gaps = rs.gap_rules(mapping)
    interior = rs.lookup_entry(tile_map, 4, 0, 15)
    interior_colours = None
    if interior is not None and _loaded(tilesets, interior.get("tileset", "primary")):
        interior_colours = rs.colour_set(_render(tilesets, interior))
    for mask in range(16):
        if rs.in_gap(gaps, 4, 0, mask):
            continue
        entry = rs.lookup_entry(tile_map, 4, 0, mask)
        if entry is None:
            problems.append("WATER mask %d has no entry and is not a gap" % mask)
            continue
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("WATER mask %d names an unknown tileset" % mask)
            continue
        label = _label(4, 0, mask, entry)
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh not in rs.WATER_BEHAVIOURS:
            problems.append("%s has behaviour %s, not a standing-water behaviour" % (label, None if beh is None else "0x%02X" % beh))
        canvas = _render(tilesets, entry)
        centre = _centre_share(canvas, rs.is_water_pixel)
        if centre < WATER_CENTRE_MIN:
            problems.append("%s has only %.0f%% water in its centre (needs >= %.0f%%)" % (label, centre * 100, WATER_CENTRE_MIN * 100))
        if interior_colours is not None:
            water_px = [p for p in rs.canvas_pixels(canvas) if rs.is_water_pixel(p)]
            if water_px:
                inside = sum(1 for p in water_px if p in interior_colours) / float(len(water_px))
                if inside < WATER_COLOUR_CONTAINMENT_MIN:
                    problems.append("%s draws only %.0f%% of its water in the interior's colours (needs >= %.0f%%)"
                                    % (label, inside * 100, WATER_COLOUR_CONTAINMENT_MIN * 100))
        if mask == 15:
            s = rs.share(canvas, rs.is_water_pixel)
            if s < WATER_INTERIOR_MIN:
                problems.append("%s is only %.0f%% water-coloured (interior needs >= %.0f%%)" % (label, s * 100, WATER_INTERIOR_MIN * 100))
            corners = _corner_shares(canvas, rs.is_water_pixel)
            if min(corners) < WATER_CORNER_MIN:
                problems.append("%s has a corner square only %.0f%% water (interior needs each >= %.0f%%)"
                                % (label, min(corners) * 100, WATER_CORNER_MIN * 100))
        for bit, side in enumerate(rs.SIDE_NAMES):
            ws = rs.side_water_share(canvas, side)
            if (mask >> bit) & 1:
                if ws < WATER_SIDE_WATER_MIN:
                    problems.append("%s: side %s should continue the water but is only %.0f%% water-coloured" % (label, side, ws * 100))
            elif (1.0 - ws) < WATER_SHORE_MIN:
                problems.append("%s: side %s should show a shore but only %.0f%% of its band is non-water" % (label, side, (1.0 - ws) * 100))
    return problems


BRIDGE_NORTH_SOUTH_MASKS = (7, 13, 6, 12, 3, 9)  # the deck's left and right halves and its two ends
BRIDGE_EAST_WEST_MASKS = (14, 11)                # the upper and lower halves of a deck that runs east-west


def check_bridge(tilesets, mapping):
    """Every BRIDGE piece carries the ROM's bridge-over-water behaviour byte, and a deck that runs
    east-west never uses the pieces of one that runs north-south (their planks lie the other way)."""
    problems = []
    pieces = {"ns": set(), "ew": set()}
    for cls, var, mask, entry in iter_entries(mapping):
        if cls != 10:
            continue
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("BRIDGE mask %s names an unknown tileset" % mask)
            continue
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh not in BRIDGE_BEHAVIOURS:
            problems.append("%s has behaviour %s, not the bridge behaviour" % (
                _label(cls, var, mask, entry), None if beh is None else "0x%02X" % beh))
        if str(mask).isdigit():
            if int(mask) in BRIDGE_NORTH_SOUTH_MASKS:
                pieces["ns"].add(entry_key(entry))
            elif int(mask) in BRIDGE_EAST_WEST_MASKS:
                pieces["ew"].add(entry_key(entry))
    if pieces["ns"] & pieces["ew"]:
        problems.append("BRIDGE pieces %s serve both a north-south and an east-west deck"
                        % sorted(m for m, _t in pieces["ns"] & pieces["ew"]))
    return problems


# The building templates the synthesiser places (slice-2 plan §11.1): footprint, roof rows, and the
# door's offset in the bottom row. block_l is drawn at its 6 x 5 minimum.
TEMPLATES = {
    "house_s": {"w": 4, "h": 3, "roof_rows": 2, "door": [1, 2]},
    "house_m": {"w": 5, "h": 4, "roof_rows": 2, "door": [2, 3]},
    "block_l": {"w": 6, "h": 5, "roof_rows": 3, "door": [2, 4]},
}


def derive_building(tile_map, gaps, template, colour):
    """The metatiles of one template in one roof colour, row-major, assembled from the tile_map with
    the synthesiser's own neighbour-mask rules. Returns None when any piece is a gap, and raises when
    the colour mixes two secondary tilesets."""
    w, h, roof_rows = template["w"], template["h"], template["roof_rows"]
    door_x, door_y = template["door"]
    cells, tilesets = [], set()
    for r in range(h):
        for c in range(w):
            if r < roof_rows:
                mask = (1 if r > 0 else 0) | (2 if c < w - 1 else 0) | (4 if r < roof_rows - 1 else 0) | (8 if c > 0 else 0)
                cls, var = 12, colour
            elif (c, r) == (door_x, door_y):
                cls, var, mask = 14, colour, 0
            else:
                mask = (1 if r > roof_rows else 0) | (2 if c < w - 1 else 0) | (4 if r < h - 1 else 0) | (8 if c > 0 else 0)
                cls, var = 13, colour + (8 if c % 2 == 1 else 0)
            if rs.in_gap(gaps, cls, var, mask):
                return None
            entry = rs.lookup_entry(tile_map, cls, var, mask)
            if entry is None:
                return None
            cells.append(entry["metatile"])
            key = entry.get("tileset", "primary")
            if key != "primary" and entry["metatile"] >= rs.PRIMARY_METATILE_COUNT:
                tilesets.add(key)
    if len(tilesets) > 1:
        raise ValueError("building colour %d mixes secondary tilesets %s" % (colour, sorted(tilesets)))
    spec = {"metatiles": cells}
    if tilesets:
        spec["tileset"] = next(iter(tilesets))
    return spec


def derive_buildings(tile_map, gaps):
    out = {}
    for name, template in TEMPLATES.items():
        colours = {}
        for colour in range(8):
            spec = derive_building(tile_map, gaps, template, colour)
            if spec is not None:
                colours[str(colour)] = spec
        if colours:
            out[name] = {"w": template["w"], "h": template["h"], "door": template["door"], "roof_colors": colours}
    return out


def check_buildings(mapping):
    """The `buildings` block is exactly what the tile_map implies (it is derived data and may never
    disagree with it). No ROM needed."""
    try:
        derived = derive_buildings(mapping.get("tile_map", {}), rs.gap_rules(mapping))
    except ValueError as err:
        return ["buildings cannot be derived: %s" % err]
    if mapping.get("buildings", {}) != derived:
        return ["the `buildings` block differs from the buildings derived from `tile_map`; rebuild the table"]
    return []


def check_building_pieces(tilesets, mapping):
    """ROOF, WALL, and DOOR pieces carry the behaviours the ROM gives its house pieces, and each roof
    colour variant 0-7 is a piece set of its own (no variant is a copy of another)."""
    problems = []
    allowed = {12: ROOF_BEHAVIOURS, 13: WALL_BEHAVIOURS, 14: DOOR_PIECE_BEHAVIOURS}
    names = {12: "ROOF", 13: "WALL", 14: "DOOR"}
    roof_sets = {}
    for cls, var, mask, entry in iter_entries(mapping):
        if cls not in allowed:
            continue
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("%s names an unknown tileset" % _label(cls, var, mask, entry))
            continue
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh not in allowed[cls]:
            problems.append("%s has behaviour %s, not a %s behaviour" % (
                _label(cls, var, mask, entry), None if beh is None else "0x%02X" % beh, names[cls]))
        if cls == 12 and var < 8:
            roof_sets.setdefault(var, set()).add(entry_key(entry))
    seen = {}
    for var, pieces in sorted(roof_sets.items()):
        frozen = frozenset(pieces)
        if frozen in seen:
            problems.append("ROOF variants %d and %d use the same pieces" % (seen[frozen], var))
        seen[frozen] = var
    return problems


def check_palettes(tilesets):
    """Every palette of every loaded tileset has exactly 16 colours in range, so a 4-bpp tile
    cannot use more than 16 colours from it."""
    problems = []
    for key, ts in sorted(tilesets.items()):
        if len(ts.palettes) != 16:
            problems.append("%s has %d palettes, not 16" % (key, len(ts.palettes)))
        for index, pal in enumerate(ts.palettes):
            if len(pal) != 16 or not all(0 <= c <= 255 for colour in pal for c in colour):
                problems.append("%s palette %d is not 16 in-range colours" % (key, index))
    return problems


def check_ground_behaviours(tilesets, mapping):
    """The SAND piece carries the ROM's sand behaviour byte, and the CROP piece its plantable-soil byte."""
    problems = []
    wanted = {5: ("SAND", SAND_BEHAVIOURS), 19: ("CROP", SOIL_BEHAVIOURS)}
    for cls, var, mask, entry in iter_entries(mapping):
        if cls not in wanted:
            continue
        name, allowed = wanted[cls]
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("%s names an unknown tileset" % name)
            continue
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh not in allowed:
            problems.append("%s has behaviour %s, not the %s behaviour" % (
                _label(cls, var, mask, entry), None if beh is None else "0x%02X" % beh, name.lower()))
    return problems


def check_tall_grass(tilesets, mapping):
    """Every TALL_GRASS piece has a tall-grass behaviour, paints no object over the grass, is
    green-dominant, and has per-channel variance > 500 (a wrong decode or palette cannot pass)."""
    problems = []
    gaps = rs.gap_rules(mapping)
    seen = set()
    for cls, var, mask, entry in iter_entries(mapping):
        if cls != 2:
            continue
        key = entry.get("tileset", "primary")
        if not _loaded(tilesets, key):
            problems.append("TALL_GRASS mask %s names an unknown tileset" % mask)
            continue
        k = entry_key(entry)
        if k in seen:
            continue
        seen.add(k)
        label = _label(cls, var, mask, entry)
        beh = rs.behaviour_at(tilesets, entry["metatile"], key)
        if beh not in rs.TALL_GRASS_BEHAVIOURS:
            problems.append("%s has behaviour %s, not a tall-grass behaviour" % (label, None if beh is None else "0x%02X" % beh))
        if not rs.top_layer_blank(tilesets, entry["metatile"], key):
            problems.append("%s paints an object over the grass" % label)
        canvas = _render(tilesets, entry)
        r, g, b = _mean(canvas)
        if not (g > r and g > b):
            problems.append("%s is not green-dominant" % label)
        for name, v in zip("RGB", _variance(canvas)):
            if v <= TALL_GRASS_VARIANCE_MIN:
                problems.append("%s has %s variance %.0f (needs > %.0f)" % (label, name, v, TALL_GRASS_VARIANCE_MIN))
    for mask in range(16):
        if not rs.in_gap(gaps, 2, 0, mask) and rs.lookup_entry(mapping["tile_map"], 2, 0, mask) is None:
            problems.append("TALL_GRASS mask %d has no entry and is not a gap" % mask)
    return problems


def check_no_unlisted_shared(mapping, tilesets=None):
    """Two classes never share a metatile unless the table's `shared` list names the share. With
    tilesets, metatiles that draw identical pixels count as one piece (a twin under a second
    number is still a share)."""
    problems = []
    classes_by_key = {}
    for cls, _var, _mask, entry in iter_entries(mapping):
        classes_by_key.setdefault(entry_key(entry), set()).add(cls)
    group_of = {}
    if tilesets is not None:
        first_with_pixels = {}
        for key in sorted(classes_by_key, key=lambda k: (k[1], k[0])):
            if not _loaded(tilesets, key[1]):
                group_of[key] = key
                continue
            pixels = tuple(rs.canvas_pixels(rs.render_entry(tilesets, key[0], key[1])))
            group_of[key] = first_with_pixels.setdefault(pixels, key)
    else:
        group_of = {key: key for key in classes_by_key}
    classes_by_group, members = {}, {}
    for key, classes in classes_by_key.items():
        classes_by_group.setdefault(group_of[key], set()).update(classes)
        members.setdefault(group_of[key], set()).add(key)
    listed = {}
    for item in mapping.get("shared", []):
        listed[entry_key(item)] = set(item["classes"])
    for group, classes in sorted(classes_by_group.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        if len(classes) > 1 and not any(listed.get(k) == classes for k in members[group]):
            twins = sorted(members[group])
            problems.append("metatile %d (%s) is shared by classes %s without being listed as intentional%s"
                            % (group[0], group[1], sorted(classes),
                               "" if len(twins) == 1 else " (identical pixels in metatiles %s)" % [m for m, _t in twins]))
    for key, classes in listed.items():
        group = group_of.get(key)
        if tilesets is None:
            # Without the ROM twins cannot be seen: a listing is stale only if none of its classes uses the number.
            stale = not (classes & classes_by_key.get(key, set()))
        else:
            stale = group is None or len(classes_by_group.get(group, ())) < 2 or classes_by_group[group] != classes
        if stale:
            problems.append("`shared` lists metatile %d (%s) for classes %s but no two classes use it" % (key[0], key[1], sorted(classes)))
    return problems


def check_gaps_have_no_entries(mapping):
    """No tile_map entry exists for anything the `gaps` block lists; each gap is well formed: a unique
    snake_case id, a reason, non-empty lists of real class numbers, masks 0-15 and variants 0-63."""
    problems = []
    gaps = rs.gap_rules(mapping)
    for cls, var, mask, _entry in iter_entries(mapping):
        masks = range(16) if mask == "*" else [int(mask)]
        if any(rs.in_gap(gaps, cls, var, m) for m in masks):
            problems.append("class %d variant %d mask %s has an entry although `gaps` lists it" % (cls, var, mask))
    seen_ids = set()

    def ints(values, low, high):
        return isinstance(values, list) and values and all(type(v) is int and low <= v <= high for v in values)

    for gap in mapping.get("gaps", []):
        if not isinstance(gap, dict):
            problems.append("gap %r is not an object with id, classes and reason" % (gap,))
            continue
        gid = gap.get("id", "")
        if not isinstance(gid, str) or not GAP_ID_RE.match(gid):
            problems.append("gap id %r is not a snake_case name" % (gid,))
        elif gid in seen_ids:
            problems.append("gap id %s is used twice" % gid)
        seen_ids.add(gid)
        reason = gap.get("reason")
        if not isinstance(reason, str) or len(reason) < MIN_REASON_LENGTH:
            problems.append("gap %s needs a reason of at least %d characters" % (gid, MIN_REASON_LENGTH))
        if not ints(gap.get("classes"), 0, MAX_CLASS):
            problems.append("gap %s needs a non-empty `classes` list of class numbers 0-%d" % (gid, MAX_CLASS))
        if "masks" in gap and not ints(gap["masks"], 0, 15):
            problems.append("gap %s needs a non-empty `masks` list within 0-15 (or no `masks`)" % gid)
        if "variants" in gap and not ints(gap["variants"], 0, 63):
            problems.append("gap %s needs a non-empty `variants` list within 0-63 (or no `variants`)" % gid)
    return problems


def _tile_exists(tilesets, metatile, key):
    """True when every tile a metatile references exists in the tile data of its tileset (a tile past
    the end would render blank)."""
    words = rs.metatile_words(tilesets, metatile, key)
    if words is None:
        return False
    primary_tiles = len(tilesets["primary"].tiles_raw) // 32
    secondary = tilesets.get(key) if key != "primary" else None
    for w in words:
        tile = w & 0x3FF
        if tile < rs.PRIMARY_METATILE_COUNT:
            if tile >= primary_tiles:
                return False
        elif secondary is None or (tile - rs.PRIMARY_METATILE_COUNT) >= len(secondary.tiles_raw) // 32:
            return False
    return True


def check_bounds(tilesets, mapping):
    """Every metatile number is inside its tileset, and every tile it references exists (the importer
    refuses entries past the end). Tileset keys are `primary` or `secNN` with NN in 1 to 57. With
    tilesets=None the secondary tilesets' sizes are not checked (no ROM needed)."""
    problems = []

    def check(label, metatile, key):
        if not isinstance(key, str) or not TILESET_KEY_RE.match(key):
            problems.append("%s: tileset key %r is not primary or secNN" % (label, key))
            return
        if key != "primary" and not (1 <= int(key[3:]) < rs.TILESET_TABLE_COUNT):
            problems.append("%s: tileset key %s is outside the 57 secondary tilesets" % (label, key))
            return
        if type(metatile) is not int or metatile < 0:
            problems.append("%s: metatile %r is not a non-negative integer" % (label, metatile))
        elif metatile < rs.PRIMARY_METATILE_COUNT:
            if tilesets is not None and not _tile_exists(tilesets, metatile, "primary"):
                problems.append("%s: metatile %d references a tile past the end of the tile data" % (label, metatile))
        elif key == "primary":
            problems.append("%s: metatile %d is past the primary tileset's 512" % (label, metatile))
        elif tilesets is None:
            return
        elif not _loaded(tilesets, key):
            problems.append("%s: tileset %s was not loaded" % (label, key))
        elif metatile - rs.PRIMARY_METATILE_COUNT >= tilesets[key].num_metatiles:
            problems.append("%s: metatile %d is past the end of %s" % (label, metatile, key))
        elif not _tile_exists(tilesets, metatile, key):
            problems.append("%s: metatile %d references a tile past the end of the tile data" % (label, metatile))

    for cls, var, mask, entry in iter_entries(mapping):
        check(_label(cls, var, mask, entry), entry["metatile"], entry.get("tileset", "primary"))
    for cid, comp in mapping.get("compositions", {}).items():
        for mid in comp.get("metatiles", []):
            check("composition %s" % cid, mid, comp.get("tileset", "primary"))
    for name, bld in mapping.get("buildings", {}).items():
        for colour, spec in bld.get("roof_colors", {}).items():
            for mid in spec.get("metatiles", []):
                check("building %s colour %s" % (name, colour), mid, spec.get("tileset", "primary"))
    return problems


def check_coverage(mapping, placeholder_rows):
    """Every (class, variant, mask) the synthesiser can emit has an entry or is a listed gap.
    placeholder_rows is placeholder_v1.json's `rows`."""
    problems = []
    gaps = rs.gap_rules(mapping)
    needed = {}
    for row in placeholder_rows:
        cls, var = row["class"], row["variant"]
        if row.get("any_variant"):
            variants = range(16)
        else:
            variants = [var]
        for v in variants:
            needed.setdefault((cls, v), row["masked"])
    for (cls, var), masked in sorted(needed.items()):
        for mask in (range(16) if masked else [0]):
            if rs.in_gap(gaps, cls, var, mask):
                continue
            if rs.lookup_entry(mapping["tile_map"], cls, var, mask) is None:
                problems.append("class %d variant %d mask %d has no entry and is not a gap" % (cls, var, mask))
    return problems


def _hue_bucket(rgb):
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if s < 0.2 or v < 0.25:
        return "grey"
    return "h%02d" % int(h * 360 // 30)


def roof_colourways(tilesets, mapping):
    """Returns {variant: hue bucket of the roof's most common non-outline colour} for variants 0-7."""
    out = {}
    gaps = rs.gap_rules(mapping)
    for var in range(8):
        counts = {}
        for mask in range(16):
            if rs.in_gap(gaps, 12, var, mask):
                continue
            entry = rs.lookup_entry(mapping["tile_map"], 12, var, mask)
            if entry is None or not _loaded(tilesets, entry.get("tileset", "primary")):
                continue
            for p in rs.canvas_pixels(_render(tilesets, entry)):
                if max(p) >= 90:
                    counts[p] = counts.get(p, 0) + 1
        if counts:
            out[var] = _hue_bucket(max(counts, key=counts.get))
    return out


def check_roof_colourways(tilesets, mapping):
    """At least four distinct roof colourways among ROOF variants 0-7 (pass 22 mapped all eight to one).
    If the tilesets honestly have fewer, each mapped variant must be a colourway of its own and
    every other variant 0-7 must be covered by a `gaps` rule with a reason (guide §3 step 4:
    "if not, record the reason in gaps")."""
    ways = roof_colourways(tilesets, mapping)
    distinct = sorted(set(ways.values()))
    if len(distinct) >= ROOF_COLOURWAYS_MIN:
        return []
    gaps = rs.gap_rules(mapping)
    detail = ", ".join("%d:%s" % kv for kv in sorted(ways.items()))
    unexplained = [v for v in range(8) if v not in ways and not all(rs.in_gap(gaps, 12, v, m) for m in range(16))]
    if unexplained:
        return ["only %d distinct roof colourways among variants 0-7 (%s) and variants %s are neither mapped nor listed in gaps; needs >= %d"
                % (len(distinct), detail, unexplained, ROOF_COLOURWAYS_MIN)]
    if len(distinct) < len(ways):
        return ["only %d distinct roof colourways among variants 0-7 (%s); variants that repeat a colourway must be gaps, and the table needs >= %d colourways unless the tilesets have fewer"
                % (len(distinct), detail, ROOF_COLOURWAYS_MIN)]
    return []


def check_compositions(tilesets, mapping):
    """Compositions are rectangles of valid metatiles with a door inside them, named by function; every
    building has a door on a door piece, except the raised road. With tilesets=None only the
    structure is checked (no ROM needed)."""
    problems = []
    comps = mapping.get("compositions", {})
    for cid in COMPOSITION_IDS:
        if cid not in comps:
            problems.append("composition %s is missing" % cid)
    for cid, comp in comps.items():
        if cid not in COMPOSITION_IDS:
            problems.append("composition id %r is not one of the neutral function names" % cid)
        w, h, metatiles = comp.get("w"), comp.get("h"), comp.get("metatiles")
        if not (type(w) is int and type(h) is int and w >= 1 and h >= 1 and isinstance(metatiles, list)):
            problems.append("composition %s needs integer w and h of at least 1 and a metatiles list" % cid)
            continue
        if len(metatiles) != w * h:
            problems.append("composition %s has %d metatiles for %dx%d" % (cid, len(metatiles), w, h))
            continue
        door = comp.get("door", [])
        if not door:
            if cid not in NO_DOOR_COMPOSITIONS:
                problems.append("composition %s has no door" % cid)
            continue
        if not (isinstance(door, list) and len(door) == 2 and all(type(v) is int for v in door)):
            problems.append("composition %s: door must be [x, y]" % cid)
            continue
        x, y = door
        if not (0 <= x < w and 0 <= y < h):
            problems.append("composition %s: door %s is outside the %dx%d grid" % (cid, door, w, h))
        elif tilesets is not None:
            mid = metatiles[y * w + x]
            key = comp.get("tileset", "primary")
            if _loaded(tilesets, key):
                beh = rs.behaviour_at(tilesets, mid, key)
                if beh not in DOOR_BEHAVIOURS:
                    problems.append("composition %s: the door piece (metatile %d) has behaviour %s, not a door" % (
                        cid, mid, None if beh is None else "0x%02X" % beh))
    return problems


def used_tileset_keys(mapping):
    """Every tileset key the table's entries, buildings and compositions use."""
    keys = {"primary"}
    for _c, _v, _m, entry in iter_entries(mapping):
        if entry["metatile"] >= rs.PRIMARY_METATILE_COUNT:
            keys.add(entry.get("tileset", "primary"))
    for comp in mapping.get("compositions", {}).values():
        if any(m >= rs.PRIMARY_METATILE_COUNT for m in comp.get("metatiles", [])):
            keys.add(comp.get("tileset", "primary"))
    for bld in mapping.get("buildings", {}).values():
        for spec in bld.get("roof_colors", {}).values():
            if any(m >= rs.PRIMARY_METATILE_COUNT for m in spec.get("metatiles", [])):
                keys.add(spec.get("tileset", "primary"))
    return keys


def check_neutral_names(mapping):
    """Tilesets are keyed by index and compositions named by function (F59); the `tilesets` block
    lists exactly the tilesets the table uses, each key mapped to its own index."""
    problems = []
    block = mapping.get("tilesets", {})
    for key, index in block.items():
        if not TILESET_KEY_RE.match(key):
            problems.append("tileset key %r is not primary or secNN" % key)
        elif key != "primary" and not (1 <= int(key[3:]) < rs.TILESET_TABLE_COUNT):
            problems.append("tileset key %s is outside the 57 secondary tilesets (sec01 to sec57)" % key)
        elif index != (0 if key == "primary" else int(key[3:])):
            problems.append("tileset %s is listed with index %r" % (key, index))
    used = used_tileset_keys(mapping)
    for key in sorted(used - set(block)):
        problems.append("tileset %s is used but not listed in `tilesets`" % key)
    for key in sorted(set(block) - used - {"primary"}):
        problems.append("tileset %s is listed in `tilesets` but nothing uses it" % key)
    for cid in mapping.get("compositions", {}):
        if cid not in COMPOSITION_IDS:
            problems.append("composition id %r is not one of the neutral function names" % cid)
    for where, text in _naming_strings(mapping):
        for word in re.findall(r"[a-z0-9]+", text.lower()):
            if hashlib.sha1(word.encode()).hexdigest() in FORBIDDEN_WORD_HASHES:
                problems.append("%s contains a forbidden place name" % where)
    return problems


def _naming_strings(mapping):
    """Every string of the table that names or describes something: keys, ids, reasons."""
    for key in mapping.get("tilesets", {}):
        yield "tileset key %r" % key, key
    for cid in mapping.get("compositions", {}):
        yield "composition id %r" % cid, cid
    for name in mapping.get("buildings", {}):
        yield "building %r" % name, str(name)
    for gap in mapping.get("gaps", []):
        if isinstance(gap, dict):
            yield "gap %s id" % gap.get("id"), str(gap.get("id", ""))
            yield "gap %s reason" % gap.get("id"), str(gap.get("reason", ""))
    for item in mapping.get("shared", []):
        yield "shared metatile %s reason" % item.get("metatile"), str(item.get("reason", ""))


def check_table_shape(mapping):
    """The table holds numbers, ids and short plain-ASCII reasons only: nothing that could carry a
    colour, a pixel blob, or ROM text. No ROM needed."""
    problems = []
    allowed_top = {"version", "tilesets", "tile_map", "shared", "buildings", "compositions", "gaps"}
    for key in mapping:
        if key not in allowed_top:
            problems.append("unexpected top-level key %r" % key)
    if mapping.get("version") != 2:
        problems.append("version must be 2")

    def is_int(v):
        return type(v) is int

    for cls_s, by_var in mapping.get("tile_map", {}).items():
        if not (cls_s.isdigit() and int(cls_s) <= MAX_CLASS):
            problems.append("tile_map class key %r is not a class number 0-%d" % (cls_s, MAX_CLASS))
            continue
        for var_s, by_mask in by_var.items():
            if not var_s.isdigit():
                problems.append("class %s variant key %r is not a number" % (cls_s, var_s))
                continue
            for mask_s, entry in by_mask.items():
                where = "class %s variant %s mask %r" % (cls_s, var_s, mask_s)
                if not (mask_s.isdigit() and 0 <= int(mask_s) <= 15):
                    problems.append("%s: masks are explicit numbers 0-15 (no wildcard)" % where)
                if not isinstance(entry, dict) or set(entry) - {"metatile", "tileset"} or not is_int(entry.get("metatile")):
                    problems.append("%s: an entry is {metatile, tileset?} with an integer metatile" % where)
                elif "tileset" in entry and not TILESET_KEY_RE.match(str(entry["tileset"])):
                    problems.append("%s: bad tileset key %r" % (where, entry["tileset"]))
    for cid, comp in mapping.get("compositions", {}).items():
        if set(comp) - {"w", "h", "tileset", "door", "metatiles"}:
            problems.append("composition %s has unexpected fields" % cid)
        if not (is_int(comp.get("w")) and is_int(comp.get("h"))):
            problems.append("composition %s: w and h are integers" % cid)
        if not all(is_int(m) and m >= 0 for m in comp.get("metatiles", [])):
            problems.append("composition %s: metatiles must be non-negative integers" % cid)
        door = comp.get("door", [])
        if not (isinstance(door, list) and len(door) in (0, 2) and all(is_int(d) for d in door)):
            problems.append("composition %s: door is [] or [x, y]" % cid)
    for name, bld in mapping.get("buildings", {}).items():
        if name not in BUILDING_NAMES:
            problems.append("building %r is not one of %s" % (name, ", ".join(BUILDING_NAMES)))
        if set(bld) - {"w", "h", "door", "roof_colors"}:
            problems.append("building %s has unexpected fields" % name)
        door = bld.get("door")
        if not (is_int(bld.get("w")) and is_int(bld.get("h")) and isinstance(door, list) and len(door) == 2 and all(is_int(d) for d in door)):
            problems.append("building %s: w and h are integers and door is [x, y]" % name)
        for colour, spec in bld.get("roof_colors", {}).items():
            if not (colour.isdigit() and int(colour) < 8):
                problems.append("building %s: roof colour key %r is not 0-7" % (name, colour))
            if set(spec) - {"metatiles", "tileset"} or not all(is_int(m) and m >= 0 for m in spec.get("metatiles", [])):
                problems.append("building %s colour %s: metatile numbers only" % (name, colour))
    for item in mapping.get("shared", []):
        if set(item) - {"metatile", "tileset", "classes", "reason"} or not is_int(item.get("metatile")):
            problems.append("shared entry %r: {metatile, tileset, classes, reason} only" % (item,))
        elif not REASON_RE.match(str(item.get("reason", ""))):
            problems.append("shared entry for metatile %s: reason must be short plain ASCII text" % item["metatile"])
    for gap in mapping.get("gaps", []):
        if isinstance(gap, dict):
            if set(gap) - {"id", "classes", "variants", "masks", "reason"}:
                problems.append("gap %s has unexpected fields" % gap.get("id"))
            if not REASON_RE.match(str(gap.get("reason", ""))):
                problems.append("gap %s: reason must be short plain ASCII text" % gap.get("id"))
    return problems


def run_all(tilesets, mapping, placeholder_rows):
    """Every check, by name. Returns {name: [problems]}."""
    return {
        "grass": check_grass(tilesets, mapping),
        "water": check_water(tilesets, mapping),
        "tall_grass": check_tall_grass(tilesets, mapping),
        "bridge": check_bridge(tilesets, mapping),
        "shared": check_no_unlisted_shared(mapping, tilesets),
        "palettes": check_palettes(tilesets),
        "ground_behaviours": check_ground_behaviours(tilesets, mapping),
        "gaps": check_gaps_have_no_entries(mapping),
        "bounds": check_bounds(tilesets, mapping),
        "coverage": check_coverage(mapping, placeholder_rows),
        "roof_colourways": check_roof_colourways(tilesets, mapping),
        "compositions": check_compositions(tilesets, mapping),
        "buildings": check_buildings(mapping),
        "building_pieces": check_building_pieces(tilesets, mapping),
        "names": check_neutral_names(mapping),
        "shape": check_table_shape(mapping),
    }
