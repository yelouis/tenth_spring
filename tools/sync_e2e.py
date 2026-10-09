#!/usr/bin/env python3
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    game_dir = os.path.join(repo_root, "game")
    companion_dir = os.path.join(repo_root, "companion")

    godot_bin = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not godot_bin:
        print("[FAIL] Godot executable not found in PATH or GODOT_BIN")
        sys.exit(1)

    flutter_bin = os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
    if not flutter_bin:
        print("[FAIL] Flutter executable not found in PATH or FLUTTER_BIN")
        sys.exit(1)

    print(f"=== Cross-Language Sync E2E Test ===")
    print(f"Using Godot: {godot_bin}")
    print(f"Using Flutter: {flutter_bin}")

    # 1. Launch Godot E2E server scene
    godot_cmd = [godot_bin, "--headless", "--path", "game", "res://tests/sync_e2e_server.tscn"]
    print(f"Step 1: Starting Godot server: {' '.join(godot_cmd)}")

    godot_proc = subprocess.Popen(
        godot_cmd,
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )

    out_q = queue.Queue()
    all_lines = []

    def enqueue_output(out, q):
        try:
            for line in iter(out.readline, ''):
                q.put(line)
        finally:
            out.close()

    reader_thread = threading.Thread(target=enqueue_output, args=(godot_proc.stdout, out_q), daemon=True)
    reader_thread.start()

    ready_data = None
    start_time = time.time()

    # Wait up to 60s for E2E_READY
    while time.time() - start_time < 60.0:
        if godot_proc.poll() is not None and out_q.empty():
            print(f"[FAIL] Godot process exited prematurely with code {godot_proc.returncode}")
            sys.exit(1)
        try:
            line = out_q.get(timeout=1.0)
            all_lines.append(line)
            stripped = line.strip()
            print(f"[Godot] {stripped}")
            if stripped.startswith("E2E_READY "):
                json_str = stripped[len("E2E_READY "):].strip()
                ready_data = json.loads(json_str)
                break
        except queue.Empty:
            continue

    if not ready_data:
        print("[FAIL] Timeout waiting for E2E_READY from Godot server")
        godot_proc.kill()
        sys.exit(1)

    print(f"Server ready on port {ready_data['port']} with fingerprint {ready_data['fp'][:16]}...")

    # 2. Run Flutter E2E test
    print("Step 2: Running companion E2E test...")
    flutter_cmd = [
        flutter_bin,
        "test",
        "test/sync_e2e_test.dart",
        f"--dart-define=E2E_PORT={ready_data['port']}",
        f"--dart-define=E2E_FP={ready_data['fp']}",
        f"--dart-define=E2E_PAIR={ready_data['pair']}",
        f"--dart-define=E2E_PCID={ready_data['pcId']}",
    ]
    print(f"Running: {' '.join(flutter_cmd)}")

    flutter_res = subprocess.run(
        flutter_cmd,
        cwd=companion_dir,
        capture_output=True,
        text=True
    )

    print(flutter_res.stdout)
    if flutter_res.stderr:
        print(flutter_res.stderr, file=sys.stderr)

    if flutter_res.returncode != 0:
        print(f"[FAIL] Flutter test exited with non-zero code {flutter_res.returncode}")
        godot_proc.kill()
        sys.exit(1)

    sent_data = None
    for line in flutter_res.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("E2E_SENT "):
            sent_data = json.loads(stripped[len("E2E_SENT "):].strip())
            break

    if not sent_data:
        print("[FAIL] Could not find E2E_SENT line in Flutter test output")
        godot_proc.kill()
        sys.exit(1)

    print(f"Flutter sent {sent_data['rows']} rows with maxSeq={sent_data['maxSeq']}")

    # 3. Wait for E2E_STATE from Godot
    print("Step 3: Waiting for Godot E2E_STATE...")
    state_data = None
    wait_state_start = time.time()

    while time.time() - wait_state_start < 30.0:
        try:
            line = out_q.get(timeout=1.0)
            all_lines.append(line)
            stripped = line.strip()
            print(f"[Godot] {stripped}")
            if stripped.startswith("E2E_STATE "):
                state_data = json.loads(stripped[len("E2E_STATE "):].strip())
                break
        except queue.Empty:
            if godot_proc.poll() is not None and out_q.empty():
                break

    godot_proc.wait(timeout=10.0)

    if godot_proc.returncode != 0:
        print(f"[FAIL] Godot server exited with code {godot_proc.returncode}")
        sys.exit(1)

    if not state_data:
        print("[FAIL] Timeout waiting for E2E_STATE from Godot server")
        sys.exit(1)

    # 4. Assert correctness
    print(f"Step 4: Verifying state invariants: {state_data}")
    errors = []
    if state_data.get("visit_log") != sent_data.get("rows"):
        errors.append(f"visit_log ({state_data.get('visit_log')}) != rows ({sent_data.get('rows')})")
    if state_data.get("last_applied_seq") != sent_data.get("maxSeq"):
        errors.append(f"last_applied_seq ({state_data.get('last_applied_seq')}) != maxSeq ({sent_data.get('maxSeq')})")
    if state_data.get("map_cell", 0) < 1:
        errors.append(f"map_cell ({state_data.get('map_cell')}) < 1")

    if errors:
        for err in errors:
            print(f"[FAIL] Invariant error: {err}")
        sys.exit(1)

    print(f"\n[OK] Cross-language loopback sync succeeded! All assertions satisfied.")
    sys.exit(0)

if __name__ == "__main__":
    main()
