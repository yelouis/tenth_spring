#!/usr/bin/env python3
"""validate_art.py — checks converted sprites against the catalogue, the target look, and the brief's rules (DRAFT).

    python3 -I tools/art_pipeline/validate_art.py --catalogue docs/art_brief/catalogue.json --work ../tenth_spring_art_work

Reads every <asset>__<image>__<mode>.png in <work>/final (written by convert_art.py) and checks it:
  1. technical rules from catalogue.json: size, clean transparency, colour count, outline, fill, no specks,
     door, light from the upper left, symmetry, a collapsed house's missing roof; and, from what the
     converter measured on the generated image (its .json record): no stray marks, drawn at pixel scale,
     background all the way to every edge, no pale backdrop or frame taken in as part of the object, and
     no clearly different colour dropped by the colour cap;
  2. style fit: its 16 x 16 tiles against the local style reference (numbers measured from the
     human's own ROM by build_style_reference.py, kept outside the repository);
  3. originality: no tile may copy a tile of the reference;
  4. the subject review: what the agent saw in the picture, from <work>/review.json (ART_BRIEF.md section 4).
A sprite is PASS when 1-3 pass and its review confirms the subject, REVIEW when 1-3 pass and the review
is missing or incomplete (the entries to fill in are written to <work>/review_todo.json), FAIL otherwise.

It also checks the run against the brief's rules, from <work>/provenance.json, <work>/raw, and
<work>/review.json: every image recorded and kept, each asset within its rounds and images, every prompt
exactly the catalogue's (or the one an earlier run used) apart from the allowed additions, no image given to
a local model, one model for the run, and no review written from a template.

Writes <work>/checks.json, <work>/checks.csv, <work>/contact_sheet.png (candidates only), and
<work>/review_todo.json. With --context (the human's Mac only, needs TENTH_SPRING_ROM_GBA): also writes,
into <work>/local_only/, each sprite that passes 1-3 beside the reference look. Those pictures contain
ROM pixels: never open them in an online model, upload, attach, or commit them.

Exit codes: 0 every sprite passed; 1 at least one failed or awaits review; 2 a usage error; 3 no style
reference (technical checks still ran; ask the human to run build_style_reference.py); 4 the run broke
one of the brief's rules ("process" in checks.json): stop and report it.
"""

import argparse
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art_lib as al  # noqa: E402

NAME = re.compile(r"^(?P<asset>[a-z0-9_]+)__(?P<stem>.+)__(?P<mode>free|master)\.png$")
LAWN = (120, 200, 80, 255)  # the game's own placeholder grass (assets/palette/tenth_spring.gpl)
PAVING = (216, 192, 144, 255)  # the game's own placeholder path (the same palette): where overlays lie
KEY_NAMES = {"#FF00FF": "magenta", "#00FF00": "green"}
FAMILIES = ("nano_banana", "local", "code")  # "code": drawn by a script in tools/ (draw_overlays.py)
VERDICT_COLOUR = {"PASS": (140, 230, 140, 255), "REVIEW": (240, 210, 100, 255), "FAIL": (240, 120, 120, 255)}


def repeat_checks(img, spec):
    rep = spec.get("repeat")
    out = []
    if not rep:
        return out
    def col(x):
        return [img.rgb(x, y) for y in range(img.h) if img.opaque(x, y)]
    def row(y):
        return [img.rgb(x, y) for x in range(img.w) if img.opaque(x, y)]
    for axis, idx in (("cols", rep.get("cols")), ("rows", rep.get("rows"))):
        if not idx:
            continue
        a, b = min(idx) * al.TILE, (max(idx) + 1) * al.TILE - 1
        line = col if axis == "cols" else row
        inner = [sum(al.redmean(p, q) for p, q in zip(line(i), line(i + 1))) / max(1, len(line(i))) for i in range(a, b)]
        base = max(1.0, sum(inner) / len(inner))
        seam = sum(al.redmean(p, q) for p, q in zip(line(b), line(a))) / max(1, len(line(b)))
        ratio = seam / base
        out.append({"name": "repeatable_%s" % axis, "ok": ratio <= 1.6, "value": round(ratio, 3),
                    "target": "<= 1.6 (wrapping the repeated %s is as smooth as inside them)" % axis, "detail": ""})
    return out


def style_image(img, spec):
    """What the style check judges, as the sprite will be seen: an overlay laid over plain paving; a decal too
    sparse to judge on its own (a thin vine) standing on plain lawn; anything else as it is. Judged alone, a sparse
    sprite has no tile opaque enough, so in the fourth re-run only vines drawn on a frame could pass."""
    if spec.get("overlay"):
        ground = PAVING
    elif not al.image_tile_metrics(img, min_opaque=0.3):
        ground = LAWN
    else:
        return img
    out = al.Image(img.w, img.h)
    out.fill(ground)
    out.paste(img, 0, 0)
    return out


def _norm(text):
    return " ".join((text or "").split())


def allowed_prompts(spec, doc, attachments):
    """Every prompt the brief allows for this asset: the catalogue prompt (or the one an earlier run used, if it
    has changed since), then the layout-guide sentence if its guide is attached, then the style-reference sentence
    if other images are attached, then at most one section-5 change (a listed sentence, or one of the asset's own
    sentences repeated)."""
    key_name = KEY_NAMES.get(spec["key_colour"].upper(), "magenta")
    changes = [""]
    for name, change in sorted(doc["prompt_changes"].items()):
        if name == "roofless" and spec.get("max_roof_share") is None:
            continue  # it changes the subject of any other asset
        changes.append(_norm(change["sentence"].format(key_name=key_name)))
    changes += [_norm(s) for _k, s in sorted(spec["repeatable"].items()) if s]
    guide = _norm(doc["guide_sentence"]) if spec["guide"] in attachments else ""
    style = _norm(doc["style_reference_sentence"]) if any(a != spec["guide"] for a in attachments) else ""
    bases = [_norm(spec["prompt"])] + [_norm(p) for p in spec.get("earlier_prompts", [])]
    return {" ".join(p for p in (base, guide, style, ch) if p) for base in bases for ch in changes}


def _plain(text):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).split())


def echoes_catalogue(shows, spec):
    """True when a review's sentence repeats the asset's own 'must read as' phrase word for word (phrases of five
    words or more): that is the catalogue's wording, not a description of the picture."""
    phrase = _plain(spec.get("must_read_as"))
    return len(phrase.split()) >= 5 and phrase in _plain(shows)


def review_template(shows, spec):
    """A review's sentence with the asset's own wording taken out, to compare sentences across assets."""
    text = _plain(shows)
    for own in (spec.get("must_read_as"), spec.get("name"), spec.get("name", "").replace(" (overlay)", "")):
        own = _plain(own)
        if own:
            text = text.replace(own, " ")
    return " ".join(text.split())


def process_checks(work, doc, catalogue):
    """The run's own rules (ART_BRIEF.md sections 2-5 and 7), from provenance.json and the raw folder."""
    path = os.path.join(work, "provenance.json")
    if not os.path.exists(path):
        return [al._check("provenance_recorded", False, "missing", "provenance.json with one entry per generated image")]
    entries = al.load_json(path)
    if isinstance(entries, dict):
        entries = entries.get("entries", [])
    out = []
    raw_dir = os.path.join(work, "raw")
    on_disk = set()
    if os.path.isdir(raw_dir):
        for asset in sorted(os.listdir(raw_dir)):
            d = os.path.join(raw_dir, asset)
            if os.path.isdir(d):
                on_disk.update((asset, f) for f in os.listdir(d) if f.lower().endswith(".png"))
    listed = {(e.get("asset"), e.get("file")) for e in entries}
    unlisted = sorted(on_disk - listed)
    gone = sorted(p for p in listed - on_disk if p[0] and p[1])
    out.append(al._check("every_image_recorded", not unlisted, len(unlisted), "0 raw images without a provenance entry",
                         "; ".join("%s/%s" % p for p in unlisted[:20])))
    out.append(al._check("every_image_kept", not gone, len(gone),
                         "0 provenance entries whose raw image was deleted or moved (keep failures too)",
                         "; ".join("%s/%s" % p for p in gone[:20])))
    per_asset = {}
    for e in entries:
        if not e.get("carried_over"):
            per_asset.setdefault(e.get("asset"), []).append(e)
    over = []
    for asset, es in sorted(per_asset.items(), key=lambda kv: str(kv[0])):
        spec = catalogue.get(asset)
        if spec is None:
            over.append("%s is not in the catalogue" % asset)
            continue
        lim = doc["limits"][str(spec["tier"])]
        rounds = len({e.get("round") for e in es})
        if len(es) > lim["images"] or rounds > lim["rounds"]:
            over.append("%s: %d images in %d rounds (limit %d in %d)" % (asset, len(es), rounds, lim["images"], lim["rounds"]))
    out.append(al._check("within_limits", not over, len(over), "every asset within its rounds and images (section 4)",
                         "; ".join(over)))
    off_list, local_images, no_licence, families = [], [], [], set()
    for e in entries:
        where = "%s/%s" % (e.get("asset"), e.get("file"))
        spec = catalogue.get(e.get("asset"))
        attachments = e.get("attachments") or []
        new = not e.get("carried_over")  # images carried over from an earlier run were made under its rules
        drawn = e.get("model_family") == "code"  # drawn by a script: there is no prompt
        if new and not drawn and spec is not None and _norm(e.get("prompt")) not in allowed_prompts(spec, doc, attachments):
            off_list.append(where)
        families.add(e.get("model_family"))
        if e.get("model_family") == "local":
            if new and attachments:
                local_images.append(where)
            if not e.get("licence"):
                no_licence.append(where)
    out.append(al._check("prompts_as_catalogued", not off_list, len(off_list),
                         "every prompt is the catalogue's, plus only the additions section 5 allows", "; ".join(off_list[:20])))
    unknown = sorted(str(f) for f in families if f not in FAMILIES)
    out.append(al._check("model_family_recorded", not unknown, ", ".join(unknown) or "ok",
                         "every entry's model_family is nano_banana or local"))
    out.append(al._check("no_images_to_local_models", not local_images, len(local_images),
                         "0 local-model requests with an attached image (they copy it into the art)", "; ".join(local_images[:20])))
    out.append(al._check("local_licence_recorded", not no_licence, len(no_licence),
                         "every local-model entry names the model's licence", "; ".join(no_licence[:20])))
    models = sorted({str(e.get("model")) for e in entries if not e.get("carried_over")})
    out.append(al._check("one_model", len(models) <= 1, "; ".join(models), "one model for the whole run"))
    # In the re-run, a script wrote every review from one template, without looking at a single picture: little
    # houses were reviewed as cracks. One sentence, minus each asset's own wording, shared by three or more assets
    # describes none of them. (One honest sentence for near-identical candidates of one asset is fine.)
    review_path = os.path.join(work, "review.json")
    reviews = al.load_json(review_path) if os.path.exists(review_path) else {}
    shared = {}
    for candidate, r in sorted(reviews.items()):
        spec = catalogue.get(candidate.split("__")[0])
        if spec is None or not isinstance(r, dict):
            continue
        t = review_template(r.get("shows"), spec)
        if t:
            shared.setdefault(t, set()).add(spec["id"])
    templated = sorted((t, sorted(a)) for t, a in shared.items() if len(a) >= 3)
    out.append(al._check("reviews_by_eye", not templated, len(templated),
                         "0 review sentences shared by 3 or more assets (look at each picture and say what it shows)",
                         "; ".join("'%s' for %s" % (t, ", ".join(a[:6])) for t, a in templated[:5])))
    return out


def review_state(reviews, candidate, spec):
    """('ok' | 'wrong' | 'missing', detail) for one candidate picture, from review.json."""
    items = spec.get("review") or {"must_show": [], "must_not_show": []}
    r = reviews.get(candidate)
    if not isinstance(r, dict):
        return "missing", "no entry in review.json"
    if len(_norm(r.get("shows")).split()) < 5:
        return "missing", "'shows' needs a sentence saying what the picture shows"
    if echoes_catalogue(r.get("shows"), spec):
        return "missing", "'shows' repeats the catalogue's 'must read as' words: say what you see, in your own words"
    shown, not_shown = r.get("must_show") or {}, r.get("must_not_show") or {}
    unanswered = ([i for i in items["must_show"] if not isinstance(shown.get(i), bool)]
                  + [i for i in items["must_not_show"] if not isinstance(not_shown.get(i), bool)])
    if unanswered:
        return "missing", "unanswered: " + "; ".join(unanswered)
    wrong = (["does not show %s" % i for i in items["must_show"] if not shown[i]]
             + ["shows %s" % i for i in items["must_not_show"] if not_shown[i]])
    return ("wrong", "; ".join(wrong)) if wrong else ("ok", _norm(r.get("shows")))


def context_sheet(sprite, spec, out_path):
    """The sprite on reference lawn beside a reference house (ROM pixels: local only)."""
    sys.path.insert(0, os.path.join(al.repo_root(), "tools", "rom_spike", "emerald"))
    import rom_spike as rs
    rom = rs.check_preconditions()
    mapping = rs.load_mapping()
    ts = rs.load_tilesets(rom, rs.tileset_indices_of(mapping))
    tm = mapping["tile_map"]
    def piece(cls, var, mask):
        e = rs.lookup_entry(tm, cls, var, mask)
        if e is None:
            return None
        c = rs.render_entry(ts, e["metatile"], e.get("tileset", "primary"))
        img = al.Image(16, 16)
        for y in range(16):
            for x in range(16):
                img.set(x, y, tuple(c[y][x]) + (255,))
        return img
    house = mapping["buildings"]["house_s"]["roof_colors"]["0"]
    hw, hh = mapping["buildings"]["house_s"]["w"], mapping["buildings"]["house_s"]["h"]
    sw, sh = spec["size_tiles"]
    W, H = hw + 2 + sw + 3, max(hh, sh) + 3
    scene = al.Image(W * 16, H * 16)
    lawn = piece(1, 0, 15) or piece(1, 0, 0)
    path = piece(7, 0, 10) or piece(7, 0, 15)
    for ty in range(H):
        for tx in range(W):
            tile = path if ty == H - 2 and path else lawn
            scene.paste(tile, tx * 16, ty * 16, only_opaque=False)
    hy = H - 2 - hh
    for i, mid in enumerate(house["metatiles"]):
        c = rs.render_entry(ts, mid, house.get("tileset", "primary"))
        for y in range(16):
            for x in range(16):
                scene.set(1 * 16 + (i % hw) * 16 + x, hy * 16 + (i // hw) * 16 + y, tuple(c[y][x]) + (255,))
    scene.paste(sprite, (hw + 2) * 16, (H - 2 - sh) * 16)
    al.write_png(out_path, scene.scaled(3))


def contact_sheet(results, final_dir, out_path):
    tiles = []
    for r in results:
        img = al.read_png(os.path.join(final_dir, r["file"]))
        k = max(1, min(4, 256 // max(img.w, img.h)))
        tiles.append((r, img.scaled(k)))
    if not tiles:
        return
    cell_w = max(max(t.w for _, t in tiles), al.text_width("x" * 30, 1)) + 16
    cell_h = max(t.h for _, t in tiles) + 40
    cols = max(1, min(6, 1600 // cell_w))
    rows = (len(tiles) + cols - 1) // cols
    sheet = al.Image(cols * cell_w, rows * cell_h)
    sheet.fill((40, 44, 52, 255))
    for i, (r, t) in enumerate(tiles):
        ox, oy = (i % cols) * cell_w, (i // cols) * cell_h
        for y in range(oy + 4, oy + 8 + t.h + 4):
            for x in range(ox + 4, ox + 12 + t.w):
                if 0 <= x < sheet.w and 0 <= y < sheet.h:
                    sheet.set(x, y, LAWN)
        sheet.paste(t, ox + 8, oy + 8)
        al.draw_text(sheet, ox + 4, oy + t.h + 16, ("%s %s" % (r["asset"], r["mode"]))[:30], (230, 230, 230, 255), 1)
        al.draw_text(sheet, ox + 4, oy + t.h + 24, ("%s d%s" % (r["verdict"].lower(), r.get("style_distance", "-")))[:30],
                     VERDICT_COLOUR[r["verdict"]], 1)
        al.draw_text(sheet, ox + 4, oy + t.h + 32, r["stem"][:30], (180, 180, 190, 255), 1)
    al.write_png(out_path, sheet)


def validate_paths(paths, catalogue, ref, ref_tiles, filter_asset=None):
    files = []
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isdir(p):
            for root, _, fnames in os.walk(p):
                for f in sorted(fnames):
                    if f.lower().endswith(".png") and not f.endswith("__x4.png") and f != "contact_sheet.png":
                        files.append(os.path.join(root, f))
        elif os.path.isfile(p):
            files.append(p)
    if not files:
        print("validate_art: no PNG files found in paths", file=sys.stderr)
        return 2
    results = []
    for fpath in files:
        fname = os.path.basename(fpath)
        stem = os.path.splitext(fname)[0]
        asset_id = stem if stem in catalogue else stem.split("__")[0]
        if filter_asset and asset_id != filter_asset:
            continue
        spec = catalogue.get(asset_id)
        if spec is None:
            print("skipping %s: unknown asset %r" % (fname, asset_id))
            continue
        img = al.read_png(fpath)
        checks = al.technical_checks(img, spec, report=None) + repeat_checks(img, spec)
        r = {"asset": spec["id"], "file": fname, "technical": checks, "warnings": []}
        ok = all(c["ok"] for c in checks)
        if ref is not None:
            fit = al.style_fit(style_image(img, spec), ref["groups"][spec["ref_group"]])
            r["style"] = fit
            r["style_distance"] = fit.get("style_distance")
            for mm in fit["metrics"]:
                if not mm["ok"] and not mm["hard"]:
                    r["warnings"].append("style: %s is unusual (median %s, reference band %s)" % (mm["name"], mm["median"], mm["band"]))
            cal = ref.get("calibration", {})
            limit = cal.get("structures_distance_max")
            if limit and fit.get("style_distance") is not None and fit["style_distance"] > limit:
                r["warnings"].append("style: overall much plainer or busier than reference (distance %.2f; max %.2f)" % (fit["style_distance"], limit))
            hits = al.originality(img, ref_tiles, ref["patterns"])
            r["originality_hits"] = hits
            ok = ok and fit["ok"] and not hits
        failed = [c["name"] for c in checks if not c["ok"]]
        if ref is not None:
            failed += ["style:%s" % mm["name"] for mm in r["style"]["metrics"] if not mm["ok"] and mm["hard"]]
            if not r["style"]["ok"] and not any(f.startswith("style:") for f in failed):
                failed.append("style:too many unusual metrics")
            if r.get("originality_hits"):
                failed.append("originality")
        r["verdict"] = "PASS" if ok else "FAIL"
        results.append(r)
        print("%-6s %-60s %s%s" % (r["verdict"], fname, ", ".join(failed) or "ok",
                                   ("  [warnings: %d]" % len(r["warnings"])) if r["warnings"] else ""))
    n_pass = sum(1 for r in results if r["verdict"] == "PASS")
    print("\n%d of %d sprites passed." % (n_pass, len(results)))
    if ref is None:
        print("No style reference found: style and originality were NOT checked.")
        return 3
    return 0 if n_pass == len(results) else 1


def main():
    ap = argparse.ArgumentParser(description="Validate converted sprites (see the module docstring).")
    ap.add_argument("--catalogue", required=True, help="path to catalogue.json")
    ap.add_argument("--work", help="the work folder (outside the repository); reads <work>/final")
    ap.add_argument("--reference", default=al.DEFAULT_REFERENCE, help="the local style reference")
    ap.add_argument("--context", action="store_true", help="also write local-only pictures beside the reference look")
    ap.add_argument("--asset", help="only this asset")
    ap.add_argument("paths", nargs="*", help="optional file or directory paths of sprites to validate")
    args = ap.parse_args()

    if not args.work and not args.paths:
        print("validate_art: either --work or positional paths must be provided", file=sys.stderr)
        return 2

    doc = al.load_json(args.catalogue)
    catalogue = {a["id"]: a for a in doc["assets"]}
    ref = al.load_json(os.path.expanduser(args.reference)) if os.path.exists(os.path.expanduser(args.reference)) else None
    ref_tiles = []
    if ref is not None:
        import base64
        ref_tiles = [(h, base64.b64decode(r)) for h, r in ref.get("tiles", [])]

    if not args.work:
        return validate_paths(args.paths, catalogue, ref, ref_tiles, args.asset)

    work = os.path.abspath(args.work)
    if work == al.repo_root() or work.startswith(al.repo_root() + os.sep):
        print("validate_art: --work must be outside the repository", file=sys.stderr)
        return 2
    final_dir = os.path.join(work, "final")
    if not os.path.isdir(final_dir):
        print("validate_art: no folder %s (run convert_art.py first)" % final_dir, file=sys.stderr)
        return 2
    review_path = os.path.join(work, "review.json")
    reviews = al.load_json(review_path) if os.path.exists(review_path) else {}

    results, todo = [], {}
    for fname in sorted(os.listdir(final_dir)):
        m = NAME.match(fname)
        if not m or (args.asset and m.group("asset") != args.asset):
            continue
        spec = catalogue.get(m.group("asset"))
        if spec is None:
            print("skipping %s: unknown asset" % fname)
            continue
        img = al.read_png(os.path.join(final_dir, fname))
        candidate = "%s__%s" % (m.group("asset"), m.group("stem"))
        rec_path = os.path.join(final_dir, candidate + ".json")
        report = None
        if os.path.exists(rec_path):
            report = al.load_json(rec_path).get("outputs", {}).get(m.group("mode"), {}).get("report")
        checks = al.technical_checks(img, spec, report) + repeat_checks(img, spec)
        if report is None:
            checks.append(al._check("conversion_record", False, "missing", "the converter's record %s.json" % candidate))
        r = {"asset": spec["id"], "file": fname, "stem": m.group("stem"), "mode": m.group("mode"),
             "candidate": candidate, "technical": checks, "warnings": []}
        ok = all(c["ok"] for c in checks)
        if ref is not None:
            fit = al.style_fit(style_image(img, spec), ref["groups"][spec["ref_group"]])
            r["style"] = fit
            r["style_distance"] = fit.get("style_distance")
            for mm in fit["metrics"]:
                if not mm["ok"] and not mm["hard"]:
                    r["warnings"].append("style: %s is unusual (median %s, reference band %s)" % (mm["name"], mm["median"], mm["band"]))
            cal = ref.get("calibration", {})
            limit = cal.get("structures_distance_max")
            if limit and fit.get("style_distance") is not None and fit["style_distance"] > limit:
                r["warnings"].append("style: overall much plainer or busier than the reference buildings (distance %.2f; "
                                     "reference buildings reach %.2f): look at it beside the reference before accepting it"
                                     % (fit["style_distance"], limit))
            hits = al.originality(img, ref_tiles, ref["patterns"])
            r["originality_hits"] = hits
            ok = ok and fit["ok"] and not hits
        failed = [c["name"] for c in checks if not c["ok"]]
        if ref is not None:
            failed += ["style:%s" % mm["name"] for mm in r["style"]["metrics"] if not mm["ok"] and mm["hard"]]
            if not r["style"]["ok"] and not any(f.startswith("style:") for f in failed):
                failed.append("style:too many unusual metrics")
            if r["originality_hits"]:
                failed.append("originality")
        state, detail = review_state(reviews, candidate, spec)
        r["review"] = {"state": state, "detail": detail}
        if not ok:
            r["verdict"] = "FAIL"
        elif state == "wrong":
            r["verdict"] = "FAIL"
            failed.append("review: " + detail)
        elif state == "missing":
            r["verdict"] = "REVIEW"
            items = spec.get("review") or {"must_show": [], "must_not_show": []}
            entry = todo.setdefault(candidate, {
                "look_at": [], "shows": "", "must_show": {i: None for i in items["must_show"]},
                "must_not_show": {i: None for i in items["must_not_show"]}})
            entry["look_at"].append(fname.replace(".png", "__x4.png"))
        else:
            r["verdict"] = "PASS"
        results.append(r)
        print("%-6s %-60s %s%s" % (r["verdict"], fname, ", ".join(failed) or ("awaits review: " + detail if state == "missing" else ""),
                                   ("  [warnings: %d]" % len(r["warnings"])) if r["warnings"] else ""))
        if args.context and ok:
            out = os.path.join(work, "local_only", "context__" + fname)
            try:
                context_sheet(img, spec, out)
            except Exception as e:  # the ROM is optional
                print("  (no context picture: %s)" % e)

    process = process_checks(work, doc, catalogue)
    al.save_json(os.path.join(work, "checks.json"), {"results": results, "process": process, "style_reference": bool(ref)})
    al.save_json(os.path.join(work, "review_todo.json"), todo)
    names = [c["name"] for r in results for c in r["technical"]]
    cols = sorted(set(names), key=names.index)
    with open(os.path.join(work, "checks.csv"), "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["asset", "file", "mode", "verdict"] + ["%s (value | target)" % c for c in cols] +
                    ["style ok", "style distance", "style misses", "originality hits", "review", "warnings"])
        for r in results:
            by = {c["name"]: c for c in r["technical"]}
            row = [r["asset"], r["file"], r["mode"], r["verdict"]]
            for c in cols:
                row.append("%s%s | %s" % ("" if by.get(c, {}).get("ok", True) else "FAIL ", by[c]["value"], by[c]["target"]) if c in by else "")
            st = r.get("style")
            row += [st["ok"] if st else "not checked", r.get("style_distance", ""),
                    ";".join("%s=%s (band %s)" % (mm["name"], mm["median"], mm["band"]) for mm in st["metrics"] if not mm["ok"]) if st else "",
                    len(r.get("originality_hits", [])), "%s: %s" % (r["review"]["state"], r["review"]["detail"]), " | ".join(r["warnings"])]
            wr.writerow(row)
    contact_sheet(results, final_dir, os.path.join(work, "contact_sheet.png"))
    n_pass = sum(1 for r in results if r["verdict"] == "PASS")
    n_review = sum(1 for r in results if r["verdict"] == "REVIEW")
    assets = sorted({r["asset"] for r in results})
    passing = sorted({r["asset"] for r in results if r["verdict"] == "PASS"})
    print("\n%d of %d sprites passed, %d await review (fill in review_todo.json and add it to review.json); "
          "%d of %d assets have a passing sprite." % (n_pass, len(results), n_review, len(passing), len(assets)))
    print("Wrote checks.json, checks.csv, contact_sheet.png, and review_todo.json in the work folder.")
    broken = [c for c in process if not c["ok"]]
    print("\nThe run's rules: %s" % ("all kept" if not broken else "%d broken" % len(broken)))
    for c in broken:
        print("  BROKEN %-26s %s (%s)%s" % (c["name"], c["value"], c["target"], (": " + c["detail"]) if c["detail"] else ""))
    if ref is None:
        print("No style reference found: style and originality were NOT checked. Ask the human to run build_style_reference.py.")
        return 3
    if broken:
        print("Stop and report these to the human (ART_BRIEF.md section 4).")
        return 4
    return 0 if n_pass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
