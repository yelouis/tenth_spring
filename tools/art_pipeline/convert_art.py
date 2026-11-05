#!/usr/bin/env python3
"""convert_art.py — turns generated images into native sprites for one catalogue asset (DRAFT).

    python3 -I tools/art_pipeline/convert_art.py --catalogue docs/art_brief/catalogue.json --asset house_s_a --out-dir ../tenth_spring_art_work/final RAW.png [RAW2.png ...]

For each image it writes, in --out-dir (which must be outside the repository):
  <asset>__<image>__free.png      the sprite, at native size (16 pixels per tile), free 15-bit palette
  <asset>__<image>__master.png    the same, snapped to assets/palette/tenth_spring.gpl (with --mode both or master)
  ...__x4.png                     4x nearest-neighbour previews of each
  ...__<colourway>.png            roof colourways for houses (with --variants)
  <asset>__<image>.json           what the conversion did, for validate_art.py and provenance.json

Exit codes: 0 every image converted; 1 at least one image was rejected (the reason is printed);
2 a usage error (unknown asset, an output folder inside the repository).
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art_lib as al  # noqa: E402

EXCLUDE = {
    "landmark": (),
    "house": ("roof1", "roof2", "roof3", "roof4", "roof5", "roof6", "gold roof", "water", "marsh", "flower pink"),
    "nature": ("roof", "gold roof"),
}
ROOF_COLOURWAYS = {"teal": (58, 154, 154), "green": (90, 154, 74), "purple": (138, 90, 176)}


def master_palette(palette_set):
    gpl = al.load_gpl(os.path.join(al.repo_root(), "assets", "palette", "tenth_spring.gpl"))
    out = []
    for rgb, name in gpl:
        if any(name.startswith(prefix) for prefix in EXCLUDE.get(palette_set, ())):
            continue
        out.append(rgb)
    return out


def load_asset(catalogue_path, asset_id):
    cat = al.load_json(catalogue_path)
    for a in cat["assets"]:
        if a["id"] == asset_id:
            return a
    return None


def main():
    ap = argparse.ArgumentParser(description="Convert generated images into native sprites for one catalogue asset.")
    ap.add_argument("--catalogue", required=True, help="path to catalogue.json")
    ap.add_argument("--asset", required=True, help="the asset id in catalogue.json")
    ap.add_argument("--out-dir", required=True, help="output folder, outside the repository")
    ap.add_argument("--mode", choices=("free", "master", "both"), default="both")
    ap.add_argument("--variants", action="store_true", help="also write the roof colourways (houses)")
    ap.add_argument("images", nargs="+")
    args = ap.parse_args()

    spec = load_asset(args.catalogue, args.asset)
    if spec is None:
        print("convert_art: no asset %r in catalogue.json" % args.asset, file=sys.stderr)
        return 2
    out_dir = os.path.abspath(args.out_dir)
    if out_dir == al.repo_root() or out_dir.startswith(al.repo_root() + os.sep):
        print("convert_art: --out-dir must be outside the repository", file=sys.stderr)
        return 2
    w, h = spec["size_px"]
    key = al.hexc(spec["key_colour"])
    modes = ("free", "master") if args.mode == "both" else (args.mode,)
    status = 0
    for path in args.images:
        stem = os.path.splitext(os.path.basename(path))[0]
        base = os.path.join(out_dir, "%s__%s" % (spec["id"], stem))
        record = {"asset": spec["id"], "source": os.path.basename(path), "outputs": {}}
        try:
            raw = al.read_png(path)
            record["source_size"] = [raw.w, raw.h]
            for mode in modes:
                pal = master_palette(spec["palette_set"]) if mode == "master" else None
                sprite, rep = al.convert(raw, w, h, mode=mode, palette=pal, cap=spec["colour_cap"], key=key,
                                         fit=spec["fit"], margin=spec["margin"], outline=spec.get("outline", True))
                out = "%s__%s.png" % (base, mode)
                al.write_png(out, sprite)
                al.write_png("%s__%s__x4.png" % (base, mode), sprite.scaled(4))
                record["outputs"][mode] = {"file": os.path.basename(out), "report": rep}
                if args.variants and spec.get("variants") and mode == "free":
                    roof = (0, spec["roof_rows"] * al.TILE) if spec.get("roof_rows") else None
                    for name, rgb in ROOF_COLOURWAYS.items():
                        v = al.recolour_hue(sprite, 3, rgb, rows=roof)
                        vout = "%s__%s__%s.png" % (base, mode, name)
                        al.write_png(vout, v)
                        record["outputs"]["%s_%s" % (mode, name)] = {"file": os.path.basename(vout), "report": rep}
            print("converted %s -> %s (%s)" % (os.path.basename(path), os.path.basename(base), ", ".join(modes)))
        except al.ConversionError as e:
            record["rejected"] = str(e)
            status = 1
            print("REJECTED %s: %s" % (os.path.basename(path), e))
        except ValueError as e:
            record["rejected"] = str(e)
            status = 1
            print("REJECTED %s: %s" % (os.path.basename(path), e))
        al.save_json(base + ".json", record)
    return status


if __name__ == "__main__":
    sys.exit(main())
