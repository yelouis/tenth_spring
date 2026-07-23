#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess

def parse_gdscript(filepath):
	"""Static syntax & structure linting for GDScript files."""
	with open(filepath, 'r', encoding='utf-8') as f:
		lines = f.readlines()

	errors = []
	for idx, line in enumerate(lines, 1):
		stripped = line.strip()
		if stripped.startswith("func "):
			if not stripped.endswith(":") and not "->" in stripped:
				errors.append(f"Line {idx}: Missing colon in function declaration")
		if "var " in line and "=" in line:
			parts = line.split("=")
			if not parts[0].strip():
				errors.append(f"Line {idx}: Invalid variable declaration")

	return errors

def main():
	game_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	print(f"=== Tenth Spring GDScript Static Lint & Invariant Gate ===")
	print(f"Auditing GDScript codebase in {game_dir}...\n")

	gd_files = []
	for root, _, files in os.walk(game_dir):
		for f in files:
			if f.endswith('.gd'):
				gd_files.append(os.path.join(root, f))

	total_errors = 0
	for gdf in gd_files:
		rel_path = os.path.relpath(gdf, game_dir)
		errors = parse_gdscript(gdf)
		if errors:
			print(f"[LINT FAIL] {rel_path}:")
			for err in errors:
				print(f"  - {err}")
			total_errors += len(errors)
		else:
			print(f"[LINT OK]   {rel_path}")

	# Golden Invariant 1 check: Ensure sync_server.gd does not touch inventory_item
	sync_server_path = os.path.join(game_dir, "autoloads", "sync_server.gd")
	if os.path.exists(sync_server_path):
		with open(sync_server_path, 'r', encoding='utf-8') as f:
			content = f.read()
		forbidden = ["inventory_item", "base_state", "item_id", "qty"]
		for token in forbidden:
			if token in content:
				print(f"\n[GOLDEN INVARIANT VIOLATION] sync_server.gd contains illegal token '{token}'")
				total_errors += 1

	if total_errors > 0:
		print(f"\nStatic lint failed with {total_errors} error(s).")
		sys.exit(1)

	print("\nStatic lint passed. Golden Invariant 1 static capability guard intact.")

	# Check for Godot executable to run runtime GDScript tests
	godot_bin = shutil.which("godot") or shutil.which("godot4")
	if godot_bin:
		print(f"\nFound Godot binary at '{godot_bin}'. Executing runtime test suite under headless mode...")
		test_files = [
			"tests/db_test.gd",
			"tests/idempotent_sync_test.gd",
			"tests/sync_ingest_isolation_test.gd"
		]
		for test_file in test_files:
			test_path = os.path.join(game_dir, test_file)
			cmd = [godot_bin, "--headless", "-s", test_path]
			res = subprocess.run(cmd, cwd=game_dir, capture_output=True, text=True)
			if res.returncode == 0:
				print(f"[RUNTIME OK]   {test_file}")
			else:
				print(f"[RUNTIME FAIL] {test_file}:\n{res.stderr or res.stdout}")
				sys.exit(1)
	else:
		print("\n[NOTE] Godot binary ('godot') not found in PATH. Static lint passed. Runtime GDScript execution requires Godot engine.")

if __name__ == '__main__':
	main()
