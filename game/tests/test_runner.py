#!/usr/bin/env python3
import os
import sys

def parse_gdscript(filepath):
	"""Basic syntax & structure validation for GDScript files."""
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
	print(f"Auditing GDScript codebase in {game_dir}...")
	
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
			print(f"[FAIL] {rel_path}:")
			for err in errors:
				print(f"  - {err}")
			total_errors += len(errors)
		else:
			print(f"[OK] {rel_path}")

	# Invariant 1 check: Ensure sync_server.gd does not touch inventory_item
	sync_server_path = os.path.join(game_dir, "autoloads", "sync_server.gd")
	if os.path.exists(sync_server_path):
		with open(sync_server_path, 'r', encoding='utf-8') as f:
			content = f.read()
		forbidden = ["inventory_item", "base_state", "item_id", "qty"]
		for token in forbidden:
			if token in content:
				print(f"[INVARIANT VIOLATION] sync_server.gd contains illegal token '{token}'")
				total_errors += 1

	if total_errors == 0:
		print("\nAll GDScript files clean. Golden Invariant 1 intact.")
		sys.exit(0)
	else:
		print(f"\nFound {total_errors} error(s).")
		sys.exit(1)

if __name__ == '__main__':
	main()
