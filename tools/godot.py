#!/usr/bin/env python3
"""Canonical wrapper for launching Godot 4.3 in Tenth Spring (Item 23 / F57).

Every Python script in tools/ and game/tests/ must launch Godot through this
wrapper instead of calling GODOT_BIN directly.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_DIR = REPO_ROOT / "game"
MEMGUARD = REPO_ROOT / "tools" / "memguard.py"


def _resolve_script_path(raw_path: str) -> Path:
    if raw_path.startswith("res://"):
        return GAME_DIR / raw_path[len("res://") :]
    p = Path(raw_path)
    if not p.is_absolute():
        candidate_cwd = Path.cwd() / p
        if candidate_cwd.exists():
            return candidate_cwd
        candidate_game = GAME_DIR / p
        if candidate_game.exists():
            return candidate_game
    return p


def _extends_scenetree_or_mainloop(script_path: Path) -> bool:
    if not script_path.is_file():
        return False
    try:
        text = script_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        return stripped.startswith("extends SceneTree") or stripped.startswith(
            "extends MainLoop"
        )
    return False


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)

    godot_bin = os.environ.get("GODOT_BIN", "").strip()
    if not godot_bin or not os.path.isfile(godot_bin) or not os.access(godot_bin, os.X_OK):
        print(
            "godot.py: set GODOT_BIN to your Godot 4.3 binary",
            file=sys.stderr,
        )
        return 2

    memguard_step: str | None = None
    windowed = False
    passthrough: list[str] = []

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--memguard-step":
            if i + 1 >= len(args):
                print("godot.py: --memguard-step requires a step name", file=sys.stderr)
                return 2
            memguard_step = args[i + 1]
            i += 2
            continue
        if arg.startswith("--memguard-step="):
            memguard_step = arg.split("=", 1)[1]
            i += 1
            continue
        if arg == "--windowed":
            windowed = True
            i += 1
            continue
        if arg == "--headless":
            # Handled explicitly via `windowed` flag; avoid duplicate --headless.
            i += 1
            continue
        if arg == "--path":
            # Strip caller-supplied --path <dir>; wrapper always passes absolute --path.
            i += 2
            continue
        if arg.startswith("--path="):
            i += 1
            continue
        if arg in ("--script", "-s"):
            if i + 1 >= len(args):
                print(f"godot.py: {arg} requires a script path", file=sys.stderr)
                return 2
            script_arg = args[i + 1]
            resolved = _resolve_script_path(script_arg)
            if not _extends_scenetree_or_mainloop(resolved):
                print(
                    f"godot.py: refusing --script {script_arg}: it doesn't extend SceneTree or MainLoop — run tests with game/tests/test_runner.py --only <name>",
                    file=sys.stderr,
                )
                return 2
            passthrough.extend([arg, script_arg])
            i += 2
            continue
        if arg.startswith("--script="):
            script_arg = arg.split("=", 1)[1]
            resolved = _resolve_script_path(script_arg)
            if not _extends_scenetree_or_mainloop(resolved):
                print(
                    f"godot.py: refusing --script {script_arg}: it doesn't extend SceneTree or MainLoop — run tests with game/tests/test_runner.py --only <name>",
                    file=sys.stderr,
                )
                return 2
            passthrough.append(arg)
            i += 1
            continue

        passthrough.append(arg)
        i += 1

    godot_cmd: list[str] = [godot_bin]
    if not windowed:
        godot_cmd.append("--headless")
    godot_cmd.extend(["--path", str(GAME_DIR)])
    godot_cmd.extend(passthrough)

    if memguard_step and not os.environ.get("TENTH_SPRING_MEMGUARD_HELD"):
        full_cmd = [
            sys.executable,
            "-I",
            str(MEMGUARD),
            "run",
            memguard_step,
            "--",
            *godot_cmd,
        ]
    else:
        full_cmd = godot_cmd

    print(" ".join(full_cmd), flush=True)
    proc = subprocess.run(full_cmd, check=False)
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
