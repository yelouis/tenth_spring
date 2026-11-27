#!/usr/bin/env python3
"""
tools/check_no_pokemon_names.py — Local Public-Repo Nintendo Name Guard (Item 89 / F113).

Scans tracked text files (outside docs/) against the player's local data cache
(`user://rom_cache/text/en/{species,moves,abilities,items}.json`) to ensure no
Pokemon species, multi-word/special move, ability, or item names are committed
to the public repository.

If no local data cache is present (e.g. on CI runners), prints
`[NAME GUARD SKIPPED] no data cache` and exits 0.
"""

import argparse
import json
import os
import re
import subprocess
import sys

SCANNED_EXTENSIONS = {".gd", ".py", ".json", ".tscn", ".dart", ".yml", ".cfg", ".md"}
SPECIAL_CHARS = set(" -'’.")


def get_godot_user_dir():
    """Computes Godot user data directory for project name 'Tenth Spring'."""
    app_name = "Tenth Spring"
    if sys.platform.startswith("linux"):
        xdg_data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        return os.path.join(xdg_data, "godot", "app_userdata", app_name)
    if sys.platform == "darwin":
        return os.path.expanduser(f"~/Library/Application Support/Godot/app_userdata/{app_name}")
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA") or os.path.expanduser("~\\AppData\\Roaming")
        return os.path.join(appdata, "Godot", "app_userdata", app_name)
    xdg_data = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    return os.path.join(xdg_data, "godot", "app_userdata", app_name)


def is_special_name(name):
    """Returns True if name contains space, hyphen, apostrophe, period, or non-ASCII letter."""
    for ch in name:
        if ch in SPECIAL_CHARS or ord(ch) > 127:
            return True
    return False


def load_forbidden_names(cache_dir):
    """
    Loads forbidden names from <cache_dir>/text/en/{species,moves,abilities,items}.json.
    Returns (dict[name -> (kind, id_str)], cache_found: bool).
    """
    text_dir = os.path.join(cache_dir, "text", "en")
    species_path = os.path.join(text_dir, "species.json")
    if not os.path.isfile(species_path):
        return {}, False

    names = {}
    with open(species_path, "r", encoding="utf-8") as fh:
        sp_doc = json.load(fh)
    if isinstance(sp_doc, dict):
        for sid, raw_name in sp_doc.items():
            s = str(raw_name).strip()
            if s:
                names[s] = ("species", str(sid))

    for kind in ("moves", "abilities", "items"):
        kpath = os.path.join(text_dir, f"{kind}.json")
        if not os.path.isfile(kpath):
            continue
        with open(kpath, "r", encoding="utf-8") as fh:
            kdoc = json.load(fh)
        if not isinstance(kdoc, dict):
            continue
        kind_sing = "ability" if kind == "abilities" else kind[:-1]
        for kid, raw_name in kdoc.items():
            s = str(raw_name).strip()
            if s and is_special_name(s) and s not in names:
                names[s] = (kind_sing, str(kid))

    return names, True


def load_allowlist(allow_path):
    """Loads exact allowlisted phrases (one per line, # comments ignored)."""
    phrases = []
    if not allow_path or not os.path.isfile(allow_path):
        return phrases
    with open(allow_path, "r", encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            phrases.append(s)
    phrases.sort(key=len, reverse=True)
    return phrases


def _trie_to_regex(node):
    """Converts a prefix trie dict into a compact, fast regex pattern."""
    end_marker = "" in node
    children = [(ch, sub) for ch, sub in sorted(node.items()) if ch != ""]
    if not children:
        return ""
    alts = []
    single_chars = []
    for ch, sub in children:
        sub_rx = _trie_to_regex(sub)
        if sub_rx == "" and "" in sub and len(sub) == 1:
            single_chars.append(re.escape(ch))
        else:
            alts.append(re.escape(ch) + sub_rx)
    if single_chars:
        if len(single_chars) == 1:
            alts.append(single_chars[0])
        else:
            alts.append("[" + "".join(single_chars) + "]")
    body = alts[0] if len(alts) == 1 else "(?:" + "|".join(alts) + ")"
    if end_marker:
        if body.startswith("(?:") and body.endswith(")"):
            return body + "?"
        return "(?:" + body + ")?"
    return body


def _build_trie_pattern(words):
    root = {}
    for w in words:
        cur = root
        for ch in w:
            cur = cur.setdefault(ch, {})
        cur[""] = None
    return _trie_to_regex(root)


def compile_name_matchers(names_dict):
    """
    Compiles fast Trie-based case-sensitive whole-word regexes grouped by (starts_word, ends_word)
    so names with trailing punctuation/symbols (e.g. periods or gender signs) match cleanly.
    """
    buckets = {
        (True, True): [],
        (True, False): [],
        (False, True): [],
        (False, False): [],
    }
    for name in sorted(names_dict.keys()):
        sw = name[0].isalnum() or name[0] == "_"
        ew = name[-1].isalnum() or name[-1] == "_"
        buckets[(sw, ew)].append(name)

    matchers = []
    for (sw, ew), words in buckets.items():
        if not words:
            continue
        left = r"(?<![A-Za-z0-9_])" if sw else ""
        right = r"(?![A-Za-z0-9_])" if ew else ""
        pattern = left + _build_trie_pattern(words) + right
        matchers.append(re.compile(pattern))
    return matchers


def mask_allowlisted(line, allow_phrases):
    """Replaces allowlisted phrases with spaces of equal length."""
    masked = line
    for phrase in allow_phrases:
        if phrase in masked:
            masked = masked.replace(phrase, " " * len(phrase))
    return masked


def scan_text(rel_path, text, matchers, names_dict, allow_phrases):
    """Scans a file's text line-by-line and returns list of (rel_path, line_no, kind, id_str)."""
    hits = []
    for line_no, raw_line in enumerate(text.splitlines(), 1):
        line = mask_allowlisted(raw_line, allow_phrases)
        found_on_line = []
        for rx in matchers:
            for m in rx.finditer(line):
                matched = m.group(0)
                kind, obj_id = names_dict.get(matched, ("unknown", "?"))
                found_on_line.append((m.start(), kind, obj_id))
        found_on_line.sort(key=lambda x: x[0])
        for _, kind, obj_id in found_on_line:
            hits.append((rel_path, line_no, kind, obj_id))
    return hits


def should_scan_path(rel_path):
    norm = rel_path.replace("\\", "/")
    if norm == "docs" or norm.startswith("docs/"):
        return False
    _, ext = os.path.splitext(norm)
    return ext.lower() in SCANNED_EXTENSIONS


def list_target_files(repo_root, staged=False, rev=None):
    if staged:
        cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=d", "-z"]
    elif rev:
        cmd = ["git", "ls-tree", "-r", "--name-only", "-z", rev]
    else:
        cmd = ["git", "ls-files", "-z"]
    res = subprocess.run(cmd, cwd=repo_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    paths = [p for p in res.stdout.decode("utf-8", errors="surrogateescape").split("\0") if p]
    return [p for p in paths if should_scan_path(p)]


def read_target_text(repo_root, rel_path, staged=False, rev=None):
    if staged:
        res = subprocess.run(
            ["git", "show", f":{rel_path}"],
            cwd=repo_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
        )
        if res.returncode != 0:
            return None
        return res.stdout.decode("utf-8", errors="replace")
    if rev:
        res = subprocess.run(
            ["git", "show", f"{rev}:{rel_path}"],
            cwd=repo_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
        )
        if res.returncode != 0:
            return None
        return res.stdout.decode("utf-8", errors="replace")
    full_path = os.path.join(repo_root, rel_path)
    if not os.path.isfile(full_path):
        return None
    with open(full_path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def run_guard(repo_root, cache_dir, allow_path, staged=False, rev=None):
    names_dict, found = load_forbidden_names(cache_dir)
    if not found:
        return {"status": "skipped", "scanned": 0, "hits": []}
    allow_phrases = load_allowlist(allow_path)
    matchers = compile_name_matchers(names_dict)
    files = list_target_files(repo_root, staged=staged, rev=rev)
    all_hits = []
    scanned = 0
    for rel_path in files:
        txt = read_target_text(repo_root, rel_path, staged=staged, rev=rev)
        if txt is None:
            continue
        scanned += 1
        all_hits.extend(scan_text(rel_path, txt, matchers, names_dict, allow_phrases))
    return {"status": "fail" if all_hits else "ok", "scanned": scanned, "hits": all_hits}


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description="Local guard against committed Pokemon names.")
    parser.add_argument("--staged", action="store_true", help="Scan staged git blobs instead of working tree.")
    parser.add_argument("--rev", default=None, help="Scan tracked files at a specific git revision.")
    parser.add_argument(
        "--cache-dir",
        default=os.path.join(get_godot_user_dir(), "rom_cache"),
        help="Path to local rom_cache directory containing text/en/*.json."
    )
    parser.add_argument(
        "--allowlist",
        default=os.path.join(repo_root, "tools", "name_guard_allow.txt"),
        help="Path to exact-phrase allowlist file."
    )
    parser.add_argument(
        "--repo-root",
        default=repo_root,
        help="Repository root directory (defaults to this script's parent repo)."
    )
    args = parser.parse_args()

    result = run_guard(
        args.repo_root,
        args.cache_dir,
        args.allowlist,
        staged=args.staged,
        rev=args.rev,
    )
    if result["status"] == "skipped":
        print("[NAME GUARD SKIPPED] no data cache")
        sys.exit(0)
    if result["status"] == "ok":
        print(f"[NAME GUARD OK] scanned {result['scanned']} files")
        sys.exit(0)
    for rel_path, line_no, kind, obj_id in result["hits"]:
        print(f"[NAME GUARD FAIL] {rel_path}:{line_no} ({kind} #{obj_id})")
    file_count = len({h[0] for h in result["hits"]})
    print(f"[NAME GUARD FAIL] {len(result['hits'])} hit(s) in {file_count} file(s) (scanned {result['scanned']} files)")
    sys.exit(1)


if __name__ == "__main__":
    main()
