#!/usr/bin/env python3
"""
Public-Repo IP Guard Check.

Enforces that no Nintendo ROMs, extracted Nintendo assets, or container files
are ever committed to this public repository.
Operates strictly on git committed and staged blob streams (never working-tree disk files).
Supports --staged, --range <A>..<B>, and default (full repo ls-files) modes.
"""

import os
import subprocess
import sys

FORBIDDEN_EXTENSIONS = {
    ".nds", ".gba", ".gb", ".gbc", ".3ds", ".cia",
    ".narc", ".ncgr", ".nclr", ".ncer", ".nanr", ".nscr", ".sdat"
}

FORBIDDEN_GAME_CODE_PREFIXES = {
    b"ADA", b"APA", b"CPU", b"IPK", b"IPG", b"IRB", b"IRA", b"IRE", b"IRD"
}

def get_blob_head(rev, path, num_bytes=16):
    """
    Reads up to num_bytes of the object at {rev}:{path} using git show.
    Never touches working-tree files on disk.
    If rev is ':', reads from git index (:path).
    """
    spec = f":{path}" if rev == ":" else f"{rev}:{path}"
    try:
        res = subprocess.run(
            ["git", "show", spec],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False
        )
        if res.returncode == 0:
            return res.stdout[:num_bytes]
        # In default mode (HEAD), if file is in index but not yet in HEAD, check index
        if rev == "HEAD":
            res2 = subprocess.run(
                ["git", "show", f":{path}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False
            )
            if res2.returncode == 0:
                return res2.stdout[:num_bytes]
    except Exception:
        pass
    return b""

def check_file(path, rev="HEAD"):
    """
    Checks if a file violates IP guard policies at the specified rev.
    Returns error reason string if violation found, else None.
    """
    # (a) Forbidden extension
    _, ext = os.path.splitext(path)
    if ext.lower() in FORBIDDEN_EXTENSIONS:
        return f"forbidden extension '{ext}'"

    # (d) rom_cache anywhere in its path (and roms/ directory)
    normalized = path.replace("\\", "/")
    parts = normalized.split("/")
    if "rom_cache" in normalized or any(p in ("roms", "rom_cache", "rom_cache.tmp") for p in parts):
        return "forbidden path pattern containing rom_cache or roms"

    header = get_blob_head(rev, path, 16)
    if not header:
        return None

    # (b) Begins with 4 bytes 'NARC'
    if len(header) >= 4 and header[:4] == b"NARC":
        return "NARC magic header detected"

    # (c) >= 0x10 bytes and bytes 0x0C-0x0F match one of the forbidden prefixes
    # Match 3-letter prefix for Gen 4-5 titles: ADA (Diamond), APA (Pearl), CPU (Platinum),
    # IPK (HeartGold), IPG (SoulSilver), IRB (Black), IRA (White), IRE (Black 2), IRD (White 2)
    if len(header) >= 0x10 and header[0x0C:0x0F] in FORBIDDEN_GAME_CODE_PREFIXES:
        prefix = header[0x0C:0x0F].decode("ascii", errors="replace")
        code = header[0x0C:0x10].decode("ascii", errors="replace")
        return f"NDS game code prefix '{prefix}' ({code}) detected at offset 0x0C"

    return None

def parse_args():
    use_staged = False
    commit_range = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--staged":
            use_staged = True
        elif args[i] == "--range":
            if i + 1 < len(args):
                commit_range = args[i + 1]
                i += 1
            else:
                print("Error: --range requires an argument", file=sys.stderr)
                sys.exit(1)
        i += 1
    return use_staged, commit_range

def main():
    use_staged, commit_range = parse_args()

    if commit_range:
        if ".." in commit_range:
            parts = commit_range.split("..", 1)
            if not parts[0] or set(parts[0]) == {"0"}:
                rev_cmd = ["git", "rev-list", parts[1]]
            else:
                rev_cmd = ["git", "rev-list", commit_range]
        else:
            rev_cmd = ["git", "rev-list", commit_range]

        try:
            revs_out = subprocess.check_output(rev_cmd, stderr=subprocess.PIPE).decode("utf-8", errors="replace")
        except subprocess.CalledProcessError as e:
            print(f"Error running git rev-list: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
            sys.exit(1)

        commits = [c.strip() for c in revs_out.splitlines() if c.strip()]
        violations = []

        for sha in commits:
            cmd = ["git", "diff-tree", "-m", "--root", "--no-commit-id", "-r", "--name-only", "--diff-filter=d", sha, "-z"]
            try:
                diff_out = subprocess.check_output(cmd, stderr=subprocess.PIPE)
            except subprocess.CalledProcessError as e:
                print(f"Error inspecting commit {sha}: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
                sys.exit(1)
            if not diff_out:
                continue
            paths = list(dict.fromkeys(p for p in diff_out.decode("utf-8", errors="surrogateescape").split("\0") if p))
            for path in paths:
                reason = check_file(path, rev=sha)
                if reason:
                    violations.append((sha, path, reason))

        if violations:
            print("⛔ Public-repo IP guard violation: prohibited Nintendo asset(s) detected in commit range:")
            for sha, path, reason in violations:
                print(f"  - commit {sha[:10]}: {path} ({reason})")
            print("\nNever commit Nintendo assets or ROM files to this public repository.")
            sys.exit(1)

        sys.exit(0)

    if use_staged:
        cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=d", "-z"]
        active_rev = ":"
    else:
        cmd = ["git", "ls-files", "-z"]
        active_rev = "HEAD"

    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running git command: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
        sys.exit(1)

    raw_output = res.stdout
    if not raw_output:
        sys.exit(0)

    files = [f for f in raw_output.decode("utf-8", errors="surrogateescape").split("\0") if f]

    violations = []
    for filepath in files:
        reason = check_file(filepath, rev=active_rev)
        if reason:
            violations.append((filepath, reason))

    if violations:
        print("⛔ Public-repo IP guard violation: prohibited Nintendo asset(s) detected:")
        for path, reason in violations:
            print(f"  - {path}: {reason}")
        print("\nNever commit Nintendo assets or ROM files to this public repository.")
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()
