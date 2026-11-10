#!/usr/bin/env python3
"""Gen 8 data pack (PokéAPI CSVs) and Smogon B&W-style fan sprites (#650-905 + 48 Megas) spike (Item 29).

Strictly adheres to docs/design_rom_asset_pipeline.md §2a, §7, §8:
- Python 3 standard library only (plus tools/art_pipeline/art_lib.py for pure-stdlib PNG decode/encode).
- Downloads only from the commits pinned in game/config/data_sources.json into ~/.tenth_spring_data_spike/.
- NEVER requests or stores #1-649 sprites from PokeAPI/sprites.
- Writes repo-safe manifests and artist credits (game/config/data_pack_manifest.json,
  game/config/fan_sprite_manifest.json, game/config/fan_sprite_credits.json) with zero species names.
"""

from __future__ import annotations

import concurrent.futures
import csv
import hashlib
import io
import json
import os
import re
import struct
import sys
import urllib.request
import zlib
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "art_pipeline"))
import art_lib as al  # noqa: E402

DATA_SOURCES_PATH = REPO_ROOT / "game" / "config" / "data_sources.json"
DATA_PACK_MANIFEST_PATH = REPO_ROOT / "game" / "config" / "data_pack_manifest.json"
FAN_SPRITE_MANIFEST_PATH = REPO_ROOT / "game" / "config" / "fan_sprite_manifest.json"
FAN_SPRITE_CREDITS_PATH = REPO_ROOT / "game" / "config" / "fan_sprite_credits.json"

DEFAULT_OUT_DIR = Path.home() / ".tenth_spring_data_spike"

CSV_FILES: Tuple[str, ...] = (
    "ability_names.csv",
    "evolution_chains.csv",
    "evolution_triggers.csv",
    "growth_rates.csv",
    "item_categories.csv",
    "item_names.csv",
    "items.csv",
    "move_damage_classes.csv",
    "move_meta.csv",
    "move_meta_stat_changes.csv",
    "move_names.csv",
    "moves.csv",
    "pokemon.csv",
    "pokemon_abilities.csv",
    "pokemon_evolution.csv",
    "pokemon_form_names.csv",
    "pokemon_forms.csv",
    "pokemon_move_methods.csv",
    "pokemon_moves.csv",
    "pokemon_species.csv",
    "pokemon_species_names.csv",
    "pokemon_stats.csv",
    "pokemon_types.csv",
    "stat_names.csv",
    "stats.csv",
    "type_efficacy.csv",
    "type_names.csv",
    "types.csv",
    "version_groups.csv",
)

SPRITE_VARIANTS: Tuple[Tuple[str, str], ...] = (
    ("front", ""),
    ("back", "back/"),
    ("shiny", "shiny/"),
    ("back_shiny", "back/shiny/"),
)

# Priority order per design_rom_asset_pipeline.md §2a:
# 20 = sword-shield, 24 = legends-arceus, 23 = brilliant-diamond-shining-pearl,
# 19 = lets-go-pikachu-lets-go-eevee, 18 = ultra-sun-ultra-moon
LEARNSET_VG_PRIORITY: Tuple[int, ...] = (20, 24, 23, 19, 18)

PREVIEW_DEX_IDS: Tuple[int, ...] = (
    650,
    700,
    750,
    800,
    850,
    887,
    888,
    889,
    890,
    898,
    905,
    10038,  # Mega #94
)

EXPECTED_TYPING_CHECKS: Dict[int, List[str]] = {
    36: ["fairy"],
    282: ["psychic", "fairy"],
    778: ["ghost", "fairy"],
    887: ["dragon", "ghost"],
    487: ["ghost", "dragon"],
    442: ["ghost", "dark"],
    94: ["ghost", "poison"],
    609: ["ghost", "fire"],
    593: ["water", "ghost"],
    623: ["ground", "ghost"],
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def ensure_outside_repo(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    repo_resolved = REPO_ROOT.resolve()
    try:
        resolved.relative_to(repo_resolved)
        raise ValueError(f"Output directory must not live inside the repository: {resolved}")
    except ValueError as exc:
        if "must not live inside" in str(exc):
            raise
    return resolved


def fetch_bytes(url: str, dest: Path) -> bytes:
    if dest.is_file() and dest.stat().st_size > 0:
        return dest.read_bytes()
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "TenthSpring-DataSpike/1.0"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = resp.read()
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(dest)
    return data


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def validate_fan_sprite_id(sprite_id: int) -> None:
    """Hard guardrail: never request or accept #1-649 from PokeAPI/sprites."""
    if sprite_id < 650:
        raise ValueError(
            f"Refusing sprite_id={sprite_id}: National Dex #1-649 must come from TENTH_SPRING_ROM_BW, never PokeAPI/sprites"
        )
    if not (650 <= sprite_id <= 905 or 10033 <= sprite_id <= 10090):
        raise ValueError(f"Out-of-scope fan sprite id: {sprite_id}")


def read_png_any_depth(path: Path) -> al.Image:
    """Read any non-interlaced PNG (including 1/2/4/8-bit indexed ctype=3) into an al.Image."""
    data = path.read_bytes()
    if data[:8] != al.PNG_SIG:
        raise ValueError(f"{path} is not a PNG")
    pos, idat, plte, trns, ihdr = 8, [], b"", b"", None
    while pos + 8 <= len(data):
        (ln,) = struct.unpack(">I", data[pos : pos + 4])
        tag, body = data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            plte = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat.append(body)
        elif tag == b"IEND":
            break
    if ihdr is None:
        raise ValueError(f"{path}: no IHDR")
    w, h, depth, ctype, _c, _f, interlace = ihdr
    if ctype == 3 and depth == 8 or ctype != 3:
        return al.read_png(str(path))
    # Sub-byte indexed palette (depth 1, 2, or 4)
    stride = (w * depth + 7) // 8
    raw = zlib.decompress(b"".join(idat))
    img = al.Image(w, h)
    prev = bytearray(stride)
    p = 0
    out = img.px
    mask = (1 << depth) - 1
    ppb = 8 // depth
    for y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1 : p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(1, stride):
                line[i] = (line[i] + line[i - 1]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - 1] if i >= 1 else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                left = line[i - 1] if i >= 1 else 0
                upleft = prev[i - 1] if i >= 1 else 0
                line[i] = (line[i] + al._paeth(left, prev[i], upleft)) & 255
        prev = line
        d = y * w * 4
        for x in range(w):
            byte_val = line[x // ppb]
            shift = 8 - depth * ((x % ppb) + 1)
            k = (byte_val >> shift) & mask
            r, g, b = plte[k * 3 : k * 3 + 3]
            a = trns[k] if trns and k < len(trns) else 255
            out[d + x * 4 : d + x * 4 + 4] = bytes((r, g, b, a))
    return img


def compute_rgba_metrics(img: al.Image) -> Dict[str, Any]:
    opaque: List[Tuple[int, int, int]] = []
    colors: Set[Tuple[int, int, int]] = set()
    px = img.px
    for i in range(0, len(px), 4):
        a = px[i + 3]
        if a > 0:
            rgb = (px[i], px[i + 1], px[i + 2])
            opaque.append(rgb)
            colors.add(rgb)
    n = len(opaque)
    if n == 0:
        return {"opaque_px": 0, "distinct_colors": 0, "rgb_variance": 0.0}
    mr = sum(p[0] for p in opaque) / n
    mg = sum(p[1] for p in opaque) / n
    mb = sum(p[2] for p in opaque) / n
    var = sum((p[0] - mr) ** 2 + (p[1] - mg) ** 2 + (p[2] - mb) ** 2 for p in opaque) / n
    return {
        "opaque_px": n,
        "distinct_colors": len(colors),
        "rgb_variance": round(var, 2),
    }


def sanitize_artist_credit(raw: str, species_names_lower: Set[str]) -> str:
    """Preserve artist credit while abbreviating any token that matches a Pokémon species name."""
    cleaned = " ".join(raw.strip().split())
    # Explicit known artist handle replacements where a handle contains a species name
    cleaned = re.sub(r"(?i)\bEspeon\s+Scientist\b", "E. Scientist", cleaned)
    cleaned = re.sub(r"(?i)\bRadicalCharizard\b", "RadicalC.", cleaned)
    cleaned = re.sub(r"(?i)\bBasic\s+Vanillite\b", "Basic V.", cleaned)
    # Check against all species names (case-insensitive substring for names >= 3 chars)
    lowered = cleaned.lower()
    for sname in species_names_lower:
        if len(sname) >= 3 and sname in lowered:
            pattern = re.compile(re.escape(sname), re.IGNORECASE)
            cleaned = pattern.sub(sname[0].upper() + ".", cleaned)
            lowered = cleaned.lower()
    return cleaned


def parse_smogon_credits(
    credit_csv_paths: Dict[str, Path],
    mega_forms: Sequence[Dict[str, Any]],
    species_names_lower: Set[str],
) -> Tuple[Dict[str, List[str]], Dict[str, Dict[str, Any]]]:
    """Parse Smogon Sprite Project Gen 6/7/8 CSV sheets into repo-safe dex/form -> artists maps."""
    dex_credits: Dict[str, List[str]] = {}
    mega_rows_in_sheet: List[str] = []

    for key in ("gen6_and_megas", "gen7", "gen8"):
        path = credit_csv_paths[key]
        with path.open("r", encoding="utf-8", errors="replace", newline="") as f:
            rows = list(csv.reader(f))
        section = "main"
        for row in rows:
            if not row:
                continue
            col0 = row[0].strip()
            col1 = row[1].strip() if len(row) > 1 else ""
            spriter = row[6].strip() if len(row) > 6 else ""

            if col0 in ("Primal Reversion", "Mega Evolution", "Other Forms", "Galarian Forms", "Hisuan Forms", "Gigantamax"):
                section = col0
                continue

            if section == "main" and col0.isdigit():
                dex = int(col0)
                if 650 <= dex <= 905 and str(dex) not in dex_credits and spriter:
                    sanitized = sanitize_artist_credit(spriter, species_names_lower)
                    artists = [a.strip() for a in sanitized.split(",") if a.strip()]
                    dex_credits[str(dex)] = artists
            elif section == "Mega Evolution" and col0.isdigit():
                # Skip Kangaskhan-baby sub-row so the 48 Mega rows align with the 48 Gen 6 Megas
                if "baby" in col1.lower():
                    continue
                mega_rows_in_sheet.append(spriter)

    # Map the 48 Mega forms (sorted in sheet order by base species_id, with Charizard X/Y and Mewtwo X/Y)
    mega_sorted_sheet_order = sorted(
        mega_forms,
        key=lambda m: (m["species_id"], m["pokemon_id"]),
    )
    if len(mega_rows_in_sheet) != len(mega_sorted_sheet_order):
        raise ValueError(
            f"Expected 48 Mega Evolution rows in Gen 6 credit sheet, got {len(mega_rows_in_sheet)}"
        )

    mega_credits: Dict[str, Dict[str, Any]] = {}
    for form_info, raw_spriter in zip(mega_sorted_sheet_order, mega_rows_in_sheet):
        sanitized = sanitize_artist_credit(raw_spriter, species_names_lower)
        artists = [a.strip() for a in sanitized.split(",") if a.strip()]
        mega_credits[str(form_info["pokemon_id"])] = {
            "species_dex": form_info["species_id"],
            "mega_slot": form_info["mega_slot"],
            "artists": artists,
        }

    return dex_credits, mega_credits


def verify_no_species_names_in_files(
    paths: Sequence[Path],
    english_species_names: Sequence[str],
) -> List[Tuple[str, str]]:
    """Falsifying check: grep committed manifests and credits for any English species name."""
    leaks: List[Tuple[str, str]] = []
    # Check both exact case-insensitive word matches and exact species name substrings (>= 4 chars)
    patterns: List[Tuple[str, re.Pattern[str]]] = []
    for name in english_species_names:
        clean = name.strip()
        if not clean:
            continue
        # Match whole word or identifier token (including hyphen/underscore/quote boundaries)
        pat = re.compile(r"(?<![A-Za-z])" + re.escape(clean) + r"(?![A-Za-z])", re.IGNORECASE)
        patterns.append((clean, pat))

    for p in paths:
        text = p.read_text(encoding="utf-8")
        for sname, pat in patterns:
            if pat.search(text):
                leaks.append((p.name, sname))
    return leaks


def render_preview_sheet(
    sprite_dir: Path,
    preview_ids: Sequence[int],
    dest_path: Path,
) -> None:
    """Render 2x preview grid (row 0 = normal front, row 1 = shiny front) for preview_ids."""
    cell_w = 192
    cell_h = 192
    pad = 8
    cols = len(preview_ids)
    rows = 2
    total_w = cols * cell_w + (cols + 1) * pad
    total_h = rows * cell_h + (rows + 1) * pad
    canvas = al.Image(total_w, total_h)
    canvas.fill((28, 32, 38, 255))

    for col_idx, sid in enumerate(preview_ids):
        for row_idx, variant in enumerate(("front", "shiny")):
            png_path = sprite_dir / variant / f"{sid}.png"
            img = read_png_any_depth(png_path)
            simg = img.scaled(2)
            x0 = pad + col_idx * (cell_w + pad) + max(0, (cell_w - simg.w) // 2)
            y0 = pad + row_idx * (cell_h + pad) + max(0, (cell_h - simg.h) // 2)
            canvas.paste(simg, x0, y0, only_opaque=True)

    dest_path.parent.mkdir(parents=True, exist_ok=True)
    al.write_png(str(dest_path), canvas)


def run_spike(out_dir: Optional[Path] = None) -> Dict[str, Any]:
    target_dir = ensure_outside_repo(
        out_dir or Path(os.environ.get("TENTH_SPRING_DATA_PACK", str(DEFAULT_OUT_DIR)))
    )
    csv_dir = target_dir / "csv"
    sprite_dir = target_dir / "sprites"
    credits_dir = target_dir / "credits"
    csv_dir.mkdir(parents=True, exist_ok=True)
    sprite_dir.mkdir(parents=True, exist_ok=True)
    credits_dir.mkdir(parents=True, exist_ok=True)

    sources = json.loads(DATA_SOURCES_PATH.read_text(encoding="utf-8"))
    api_commit = sources["pokeapi"]["commit"]
    spr_commit = sources["fan_sprites"]["commit"]

    # 1. Download CSV files concurrently
    csv_tasks: List[Tuple[str, str, Path]] = []
    for fname in CSV_FILES:
        url = f"https://raw.githubusercontent.com/PokeAPI/pokeapi/{api_commit}/data/v2/csv/{fname}"
        csv_tasks.append((fname, url, csv_dir / fname))

    csv_manifest_entries: Dict[str, Dict[str, Any]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        future_map = {
            pool.submit(fetch_bytes, url, dest): (fname, dest)
            for fname, url, dest in csv_tasks
        }
        for fut in concurrent.futures.as_completed(future_map):
            fname, dest = future_map[fut]
            data = fut.result()
            csv_manifest_entries[fname] = {
                "size": len(data),
                "sha256": sha256_bytes(data),
            }

    # 2. Download Smogon Sprite Project credit sheets
    credit_csv_paths: Dict[str, Path] = {}
    for k, url in sources["fan_sprites"]["credit_sheets"].items():
        cpath = credits_dir / f"{k}.csv"
        fetch_bytes(url, cpath)
        credit_csv_paths[k] = cpath

    # 3. Parse CSVs to identify 905 species and 48 Gen 6 Mega forms
    species_rows = read_csv_rows(csv_dir / "pokemon_species.csv")
    gen1_8_species = [
        r for r in species_rows if int(r["id"]) <= 905 and int(r["generation_id"]) <= 8
    ]
    if len(gen1_8_species) != 905:
        raise ValueError(f"Expected 905 Gen 1-8 species, got {len(gen1_8_species)}")

    pokemon_by_id = {int(r["id"]): r for r in read_csv_rows(csv_dir / "pokemon.csv")}
    form_rows = read_csv_rows(csv_dir / "pokemon_forms.csv")
    mega_forms: List[Dict[str, Any]] = []
    for f in form_rows:
        if f["is_mega"] == "1" and int(f["introduced_in_version_group_id"]) in (15, 16):
            pid = int(f["pokemon_id"])
            p = pokemon_by_id[pid]
            ident = f["identifier"]
            slot = "x" if ident.endswith("-mega-x") else ("y" if ident.endswith("-mega-y") else "default")
            mega_forms.append(
                {
                    "form_id": int(f["id"]),
                    "pokemon_id": pid,
                    "species_id": int(p["species_id"]),
                    "introduced_in_version_group_id": int(f["introduced_in_version_group_id"]),
                    "mega_slot": slot,
                }
            )
    mega_forms.sort(key=lambda m: m["pokemon_id"])
    if len(mega_forms) != 48:
        raise ValueError(f"Expected 48 Gen 6 Mega forms, got {len(mega_forms)}")

    # 4. Download #650-905 and 48 Mega sprites ONLY (never #1-649)
    sprite_ids: List[int] = list(range(650, 906)) + [m["pokemon_id"] for m in mega_forms]
    for sid in sprite_ids:
        validate_fan_sprite_id(sid)

    sprite_tasks: List[Tuple[str, int, str, Path]] = []
    for sid in sprite_ids:
        for variant_name, sub_prefix in SPRITE_VARIANTS:
            rel_repo_path = f"{sub_prefix}{sid}.png"
            url = (
                f"https://raw.githubusercontent.com/PokeAPI/sprites/{spr_commit}/"
                f"sprites/pokemon/versions/generation-v/black-white/{rel_repo_path}"
            )
            dest = sprite_dir / variant_name / f"{sid}.png"
            sprite_tasks.append((variant_name, sid, url, dest))

    sprite_manifest_files: Dict[str, Dict[str, Dict[str, Any]]] = {
        v[0]: {} for v in SPRITE_VARIANTS
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        s_futures = {
            pool.submit(fetch_bytes, url, dest): (vname, sid, dest)
            for vname, sid, url, dest in sprite_tasks
        }
        for fut in concurrent.futures.as_completed(s_futures):
            vname, sid, dest = s_futures[fut]
            data = fut.result()
            sprite_manifest_files[vname][str(sid)] = {
                "size": len(data),
                "sha256": sha256_bytes(data),
            }

    # Verify every downloaded sprite is a valid pixel-art PNG with variance >= 500
    min_sprite_var = float("inf")
    non_96x96_dimensions: Dict[str, List[int]] = {}
    dragapult_metrics: Dict[str, Any] = {}
    for vname, _ in SPRITE_VARIANTS:
        for sid in sprite_ids:
            p = sprite_dir / vname / f"{sid}.png"
            img = read_png_any_depth(p)
            if not (32 <= img.w <= 128 and 32 <= img.h <= 128):
                raise ValueError(f"Sprite {vname}/{sid}.png has out-of-range dimensions {img.w}x{img.h}")
            if (img.w, img.h) != (96, 96):
                non_96x96_dimensions[f"{vname}/{sid}.png"] = [img.w, img.h]
            m = compute_rgba_metrics(img)
            if m["opaque_px"] < 100 or m["rgb_variance"] < 500.0:
                raise ValueError(f"Sprite {vname}/{sid}.png failed quality check: {m}")
            if vname == "front":
                min_sprite_var = min(min_sprite_var, m["rgb_variance"])
                if sid == 887:
                    dragapult_metrics = m

    # 5. Verify Gen 6+ 18x18 type chart and §7 typing checks
    types_by_id = {
        int(r["id"]): r["identifier"]
        for r in read_csv_rows(csv_dir / "types.csv")
        if int(r["id"]) <= 18
    }
    if len(types_by_id) != 18 or types_by_id.get(18) != "fairy":
        raise ValueError(f"Expected 18 Gen 6+ types with 18=fairy, got {types_by_id}")

    efficacy_matrix: Dict[str, Dict[str, float]] = {
        t_atk: {t_def: 1.0 for t_def in types_by_id.values()}
        for t_atk in types_by_id.values()
    }
    for row in read_csv_rows(csv_dir / "type_efficacy.csv"):
        atk_id = int(row["damage_type_id"])
        def_id = int(row["target_type_id"])
        if atk_id in types_by_id and def_id in types_by_id:
            efficacy_matrix[types_by_id[atk_id]][types_by_id[def_id]] = int(row["damage_factor"]) / 100.0

    # Assert design_creatures_and_battles.md §3 specifics
    assert efficacy_matrix["fairy"]["dragon"] == 2.0
    assert efficacy_matrix["fairy"]["fighting"] == 2.0
    assert efficacy_matrix["fairy"]["dark"] == 2.0
    assert efficacy_matrix["fairy"]["fire"] == 0.5
    assert efficacy_matrix["fairy"]["poison"] == 0.5
    assert efficacy_matrix["fairy"]["steel"] == 0.5
    assert efficacy_matrix["dragon"]["fairy"] == 0.0
    assert efficacy_matrix["ghost"]["normal"] == 0.0
    assert efficacy_matrix["normal"]["ghost"] == 0.0
    assert efficacy_matrix["fighting"]["ghost"] == 0.0
    assert efficacy_matrix["ghost"]["ghost"] == 2.0
    assert efficacy_matrix["ghost"]["psychic"] == 2.0
    assert efficacy_matrix["ghost"]["dark"] == 0.5
    assert efficacy_matrix["ghost"]["steel"] == 1.0
    assert efficacy_matrix["dark"]["steel"] == 1.0

    # Check §7 species typing checks
    poke_types: Dict[int, List[Tuple[int, str]]] = {}
    for row in read_csv_rows(csv_dir / "pokemon_types.csv"):
        pid = int(row["pokemon_id"])
        tid = int(row["type_id"])
        slot = int(row["slot"])
        if tid in types_by_id:
            poke_types.setdefault(pid, []).append((slot, types_by_id[tid]))

    verified_typings: Dict[str, List[str]] = {}
    for dex, expected in EXPECTED_TYPING_CHECKS.items():
        actual = [t for _, t in sorted(poke_types.get(dex, []))]
        if actual != expected:
            raise ValueError(f"Dex #{dex} typing mismatch: expected {expected}, got {actual}")
        verified_typings[str(dex)] = actual

    # 6. Verify English species names (without leaking them into repo files)
    all_en_species_names: Dict[int, str] = {}
    for row in read_csv_rows(csv_dir / "pokemon_species_names.csv"):
        if row["local_language_id"] == "9":
            all_en_species_names[int(row["pokemon_species_id"])] = row["name"]
    for check_dex in (1, 487, 609, 887, 905):
        nm = all_en_species_names.get(check_dex, "")
        if not nm or "\ufffd" in nm:
            raise ValueError(f"Invalid English name for #{check_dex}")

    # 7. Verify level-up learnsets across all 905 species
    levelup_pairs: Set[Tuple[int, int]] = set()
    for row in read_csv_rows(csv_dir / "pokemon_moves.csv"):
        if row["pokemon_move_method_id"] == "1":
            pid = int(row["pokemon_id"])
            vg = int(row["version_group_id"])
            if 1 <= pid <= 905:
                levelup_pairs.add((pid, vg))

    vg_hist: Counter[int] = Counter()
    for dex in range(1, 906):
        chosen_vg: Optional[int] = None
        for vg in LEARNSET_VG_PRIORITY:
            if (dex, vg) in levelup_pairs:
                chosen_vg = vg
                break
        if chosen_vg is None:
            raise ValueError(f"Species #{dex} has no level-up learnset in {LEARNSET_VG_PRIORITY}")
        vg_hist[chosen_vg] += 1

    # 8. Verify Gen 8 / no-Z / no-Max move filter
    move_rows = read_csv_rows(csv_dir / "moves.csv")
    gen1_8_moves = [
        m for m in move_rows if m["generation_id"] and int(m["generation_id"]) <= 8 and int(m["id"]) < 10000
    ]
    z_moves = [
        m for m in gen1_8_moves if int(m["generation_id"]) == 7 and int(m["pp"] or 0) == 1
    ]
    max_moves = [
        m for m in gen1_8_moves if int(m["generation_id"]) == 8 and m["identifier"].startswith("max-")
    ]
    z_ids = {int(m["id"]) for m in z_moves}
    max_ids = {int(m["id"]) for m in max_moves}
    kept_moves = [m for m in gen1_8_moves if int(m["id"]) not in z_ids and int(m["id"]) not in max_ids]

    # 9. Parse Smogon credits and write repo-safe manifests & credits
    species_names_lower = {n.lower() for n in all_en_species_names.values()}
    dex_credits, mega_credits = parse_smogon_credits(
        credit_csv_paths, mega_forms, species_names_lower
    )
    if len(dex_credits) != 256:
        raise ValueError(f"Expected credits for all 256 #650-905 species, got {len(dex_credits)}")
    if len(mega_credits) != 48:
        raise ValueError(f"Expected credits for all 48 Mega forms, got {len(mega_credits)}")

    sorted_csv_manifest = {
        "version": 1,
        "source_commit": api_commit,
        "total_bytes": sum(v["size"] for v in csv_manifest_entries.values()),
        "files": {k: csv_manifest_entries[k] for k in sorted(csv_manifest_entries)},
    }
    DATA_PACK_MANIFEST_PATH.write_text(
        json.dumps(sorted_csv_manifest, indent=2) + "\n", encoding="utf-8"
    )

    sorted_sprite_files = {
        vname: {str(k): sprite_manifest_files[vname][str(k)] for k in sprite_ids}
        for vname, _ in SPRITE_VARIANTS
    }
    total_sprite_bytes = sum(
        entry["size"]
        for vmap in sorted_sprite_files.values()
        for entry in vmap.values()
    )
    fan_sprite_manifest = {
        "version": 1,
        "source_commit": spr_commit,
        "species_range": [650, 905],
        "mega_pokemon_ids": [m["pokemon_id"] for m in mega_forms],
        "pending_species_dex": [],
        "pending_mega_pokemon_ids": [],
        "total_files": len(sprite_ids) * len(SPRITE_VARIANTS),
        "total_bytes": total_sprite_bytes,
        "files": sorted_sprite_files,
    }
    FAN_SPRITE_MANIFEST_PATH.write_text(
        json.dumps(fan_sprite_manifest, indent=2) + "\n", encoding="utf-8"
    )

    fan_sprite_credits_doc = {
        "version": 1,
        "project": "Smogon Sprite Project",
        "terms": "Free for non-profit use as long as the spriter or the project itself is credited.",
        "threads": sources["fan_sprites"]["threads"],
        "species_credits": {str(d): dex_credits[str(d)] for d in range(650, 906)},
        "mega_form_credits": {str(m["pokemon_id"]): mega_credits[str(m["pokemon_id"])] for m in mega_forms},
    }
    FAN_SPRITE_CREDITS_PATH.write_text(
        json.dumps(fan_sprite_credits_doc, indent=2) + "\n", encoding="utf-8"
    )

    # 10. Falsifying check: verify zero English species names leaked into committed files
    committed_paths = (
        DATA_SOURCES_PATH,
        DATA_PACK_MANIFEST_PATH,
        FAN_SPRITE_MANIFEST_PATH,
        FAN_SPRITE_CREDITS_PATH,
    )
    leaks = verify_no_species_names_in_files(
        committed_paths, list(all_en_species_names.values())
    )
    if leaks:
        raise ValueError(f"Species name leak detected in committed files: {leaks[:10]}")

    # 11. Render 2x preview sheet to ~/.tenth_spring_data_spike/preview.png
    preview_path = target_dir / "preview.png"
    render_preview_sheet(sprite_dir, PREVIEW_DEX_IDS, preview_path)

    report = {
        "pokeapi_commit": api_commit,
        "sprites_commit": spr_commit,
        "species_count": len(gen1_8_species),
        "mega_form_count": len(mega_forms),
        "csv_file_count": len(sorted_csv_manifest["files"]),
        "csv_total_bytes": sorted_csv_manifest["total_bytes"],
        "sprite_file_count": fan_sprite_manifest["total_files"],
        "sprite_total_bytes": fan_sprite_manifest["total_bytes"],
        "pending_species_dex": [],
        "pending_mega_pokemon_ids": [],
        "non_96x96_sprites": non_96x96_dimensions,
        "min_front_sprite_variance": min_sprite_var,
        "dragapult_887_metrics": dragapult_metrics,
        "learnset_version_group_priority": list(LEARNSET_VG_PRIORITY),
        "learnset_version_group_counts": {str(k): vg_hist[k] for k in LEARNSET_VG_PRIORITY},
        "moves": {
            "gen1_8_total": len(gen1_8_moves),
            "excluded_z_moves": len(z_moves),
            "excluded_max_moves": len(max_moves),
            "kept_move_count": len(kept_moves),
        },
        "verified_typings_dex": verified_typings,
        "species_name_leaks_in_committed_configs": len(leaks),
        "preview_path": str(preview_path),
    }
    (target_dir / "data_report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report


def main() -> int:
    report = run_spike()
    print(
        f"[DATA SPIKE OK] species={report['species_count']} megas={report['mega_form_count']} "
        f"moves={report['moves']['kept_move_count']} (from {report['moves']['gen1_8_total']}, "
        f"-{report['moves']['excluded_z_moves']} Z, -{report['moves']['excluded_max_moves']} Max) "
        f"sprites={report['sprite_file_count']} pending=0 leaks={report['species_name_leaks_in_committed_configs']} "
        f"preview={report['preview_path']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
