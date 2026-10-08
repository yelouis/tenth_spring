#!/usr/bin/env python3
"""
Public-Repo IP Guard Check.

Enforces that no Nintendo ROMs, extracted Nintendo assets, or container files
are ever committed to this public repository.
"""

import os
import subprocess
import sys

FORBIDDEN_EXTENSIONS = {
    ".nds", ".gba", ".gb", ".gbc", ".3ds", ".cia",
    ".narc", ".ncgr", ".nclr", ".ncer", ".nanr", ".nscr", ".sdat"
}

FORBIDDEN_GAME_CODES = {
    b"CPUE", b"ADAE", b"APAE", b"IPKE", b"IPGE"
}

def get_file_bytes(path, num_bytes=16):
    """Safely retrieves the first num_bytes of a file from disk or the git index."""
    if os.path.isfile(path):
        try:
            with open(path, "rb") as f:
                return f.read(num_bytes)
        except Exception:
            pass
    try:
        res = subprocess.run(
            ["git", "show", f":{path}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False
        )
        if res.returncode == 0:
            return res.stdout[:num_bytes]
    except Exception:
        pass
    return b""

def check_file(path):
    """
    Checks if a file violates IP guard policies.
    Returns error reason string if violation found, else None.
    """
    # (a) Forbidden extension
    _, ext = os.path.splitext(path)
    if ext.lower() in FORBIDDEN_EXTENSIONS:
        return f"forbidden extension '{ext}'"

    # (d) rom_cache anywhere in its path
    normalized = path.replace("\\", "/")
    parts = normalized.split("/")
    if "rom_cache" in normalized or any(p in ("roms", "rom_cache", "rom_cache.tmp") for p in parts):
        return "forbidden path pattern containing rom_cache or roms"

    header = get_file_bytes(path, 16)
    if not header:
        return None

    # (b) Begins with 4 bytes 'NARC'
    if len(header) >= 4 and header[:4] == b"NARC":
        return "NARC magic header detected"

    # (c) >= 0x10 bytes and bytes 0x0C-0x0F equal one of CPUE, ADAE, APAE, IPKE, IPGE
    if len(header) >= 0x10 and header[0x0C:0x10] in FORBIDDEN_GAME_CODES:
        code = header[0x0C:0x10].decode("ascii", errors="replace")
        return f"NDS game code '{code}' detected at offset 0x0C"

    return None

def main():
    use_staged = "--staged" in sys.argv
    if use_staged:
        cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM", "-z"]
    else:
        cmd = ["git", "ls-files", "-z"]

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
        reason = check_file(filepath)
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
