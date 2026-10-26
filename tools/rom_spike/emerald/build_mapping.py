#!/usr/bin/env python3
"""
Tenth Spring — build the Emerald tile mapping table (agent guide Item 12b)
Contract: docs/implementation_plan_rom_tiles.md §3
          docs/design_rom_asset_pipeline.md §4 "Choosing the metatiles"

Writes game/config/emerald_tile_map.json: metatile NUMBERS only, never pixels.

Every choice in mapping_data.py is a rule (class, variants, masks, metatile, tileset) picked by
evidence — behaviour bytes, pixel tests, and the ROM's own map layouts read as statistics only.
This builder expands the rules, derives the building templates from them, and, with the
player's ROM at TENTH_SPRING_ROM_GBA, refuses to write a table that fails mapping_checks.py.

Run under python3 -I, through tools/memguard.py, step rom_spike_gba.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapping_checks as mc  # noqa: E402
import mapping_data as data  # noqa: E402
import rom_spike as rs  # noqa: E402

OUT_PATH = os.path.join(rs.find_repo_root(), "game", "config", "emerald_tile_map.json")
ALL_MASKS = list(range(16))

def expand_rules(rules):
    """Rules (class, variants, masks, metatile, tileset) -> tile_map[class][variant][mask]."""
    tile_map = {}
    for cls, variants, masks, metatile, tileset in rules:
        for var in variants:
            for mask in (ALL_MASKS if masks == "all" else masks):
                by_mask = tile_map.setdefault(str(cls), {}).setdefault(str(var), {})
                if str(mask) in by_mask:
                    raise ValueError("class %d variant %d mask %d is set twice" % (cls, var, mask))
                entry = {"metatile": metatile}
                if tileset != "primary":
                    entry["tileset"] = tileset
                by_mask[str(mask)] = entry
    return tile_map


def build_table():
    tile_map = expand_rules(data.RULES)
    gaps = [dict(g) for g in data.GAPS]
    gap_rules = rs.gap_rules({"gaps": gaps})
    compositions = {}
    for cid in mc.COMPOSITION_IDS:
        comp = dict(data.COMPOSITIONS[cid])
        compositions[cid] = comp
    buildings = mc.derive_buildings(tile_map, gap_rules)
    table = {
        "version": 2,
        "tilesets": {"primary": 0},
        "tile_map": tile_map,
        "shared": [dict(s) for s in data.SHARED],
        "buildings": buildings,
        "compositions": compositions,
        "gaps": gaps,
    }
    for key in sorted(k for k in mc.used_tileset_keys(table) if k != "primary"):
        table["tilesets"][key] = int(key[3:])
    return table


# ---------------------------------------------------------------------------
# Compact, stable JSON: one line per (class, variant) row of masks
# ---------------------------------------------------------------------------

def _inline(obj):
    return json.dumps(obj, separators=(", ", ": "))


def dump_table(table):
    lines = ["{"]
    sections = []

    def section(name, body_lines):
        sections.append(['  "%s": %s' % (name, body_lines[0])] + body_lines[1:])

    section("version", [str(table["version"])])
    section("tilesets", [_inline(table["tilesets"])])

    tm = ["{"]
    classes = sorted(table["tile_map"], key=int)
    for ci, cls in enumerate(classes):
        tm.append('    "%s": {' % cls)
        variants = sorted(table["tile_map"][cls], key=int)
        for vi, var in enumerate(variants):
            by_mask = table["tile_map"][cls][var]
            row = ", ".join('"%s": %s' % (m, _inline(by_mask[m])) for m in sorted(by_mask, key=int))
            tm.append('      "%s": {%s}%s' % (var, row, "," if vi < len(variants) - 1 else ""))
        tm.append("    }%s" % ("," if ci < len(classes) - 1 else ""))
    tm.append("  }")
    section("tile_map", tm)

    section("shared", [_inline(table["shared"])] if table["shared"] else ["[]"])

    bl = ["{"]
    names = list(table["buildings"])
    for ni, name in enumerate(names):
        b = table["buildings"][name]
        bl.append('    "%s": {"w": %d, "h": %d, "door": %s, "roof_colors": {' % (name, b["w"], b["h"], _inline(b["door"])))
        cols = sorted(b["roof_colors"], key=int)
        for i, c in enumerate(cols):
            bl.append('      "%s": %s%s' % (c, _inline(b["roof_colors"][c]), "," if i < len(cols) - 1 else ""))
        bl.append("    }}%s" % ("," if ni < len(names) - 1 else ""))
    bl.append("  }")
    section("buildings", bl)

    cl = ["{"]
    ids = list(table["compositions"])
    for i, cid in enumerate(ids):
        cl.append('    "%s": %s%s' % (cid, _inline(table["compositions"][cid]), "," if i < len(ids) - 1 else ""))
    cl.append("  }")
    section("compositions", cl)

    gl = ["["]
    for i, g in enumerate(table["gaps"]):
        gl.append("    %s%s" % (_inline(g), "," if i < len(table["gaps"]) - 1 else ""))
    gl.append("  ]")
    section("gaps", gl)

    for si, sec in enumerate(sections):
        sec[-1] = sec[-1] + ("," if si < len(sections) - 1 else "")
        lines.extend(sec)
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    table = build_table()
    rom_data = rs.check_preconditions()
    indices = tuple(sorted(set(rs.FEATURED_SECONDARY_INDICES) | set(rs.tileset_indices_of(table))))
    tilesets = rs.load_tilesets(rom_data, indices)
    with open(os.path.join(rs.find_repo_root(), "game", "assets", "tiles", "placeholder_v1.json")) as f:
        placeholder_rows = json.load(f)["rows"]
    results = mc.run_all(tilesets, table, placeholder_rows)
    failed = False
    for name, problems in results.items():
        if problems:
            failed = True
            print("FAIL: check %s (%d problems)" % (name, len(problems)))
            for p in problems[:12]:
                print("  - " + p)
        else:
            print("PASS: check %s" % name)
    if failed:
        print("The table failed its checks and was NOT written.")
        return 1
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    text = dump_table(table)
    json.loads(text)  # the compact writer must still produce valid JSON
    with open(OUT_PATH, "w") as f:
        f.write(text)
    print("PASS: Wrote emerald_tile_map.json (%d rules' worth of entries, %d compositions, %d gap rules)"
          % (sum(len(m) for v in table["tile_map"].values() for m in v.values()), len(table["compositions"]), len(table["gaps"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
