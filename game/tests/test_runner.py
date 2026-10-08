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
	repo_root = os.path.dirname(game_dir)

	# Runner hook check: unless in CI, verify core.hooksPath is .githooks
	if os.environ.get("CI") != "true":
		try:
			hook_check = subprocess.run(
				["git", "config", "core.hooksPath"],
				cwd=repo_root,
				stdout=subprocess.PIPE,
				stderr=subprocess.PIPE,
				text=True,
				check=False
			)
			hooks_path = hook_check.stdout.strip()
			if hooks_path != ".githooks":
				print(f"\n[HOOK CHECK FAIL] core.hooksPath is '{hooks_path}', expected '.githooks'.")
				print("To activate the pre-commit hook, run:\n  git config core.hooksPath .githooks\n")
				sys.exit(1)
		except Exception as e:
			print(f"\n[HOOK CHECK FAIL] Failed to check git config core.hooksPath: {e}\n")
			sys.exit(1)

	# Public-Repo IP Guard: verify no forbidden Nintendo assets or ROM files are tracked
	ip_guard_path = os.path.join(repo_root, "tools", "check_no_nintendo_assets.py")
	if not os.path.exists(ip_guard_path):
		print("\n[IP GUARD ERROR] IP guard script missing")
		sys.exit(1)

	print("=== Public-Repo IP Guard ===")
	res = subprocess.run([sys.executable, "-I", ip_guard_path], cwd=repo_root)
	if res.returncode != 0:
		print("\n[IP GUARD VIOLATION] Nintendo asset check failed.")
		sys.exit(1)
	print("[IP GUARD OK] No Nintendo assets tracked in repository.\n")

	# Public-Repo IP Guard regression tests
	guard_tests_path = os.path.join(repo_root, "tools", "test_check_no_nintendo_assets.py")
	if not os.path.exists(guard_tests_path):
		print("\n[IP GUARD ERROR] IP guard test suite missing")
		sys.exit(1)

	print("=== Public-Repo IP Guard Test Suite ===")
	test_res = subprocess.run([sys.executable, "-I", guard_tests_path], cwd=repo_root)
	if test_res.returncode != 0:
		print("\n[IP GUARD TEST FAIL] IP guard unit tests failed.")
		sys.exit(1)
	print("[IP GUARD TESTS OK] All IP guard test cases passed.\n")

	# Test Save Isolation check (F22)
	isolation_test_path = os.path.join(game_dir, "tests", "test_f22_save_isolation.py")
	if not os.path.exists(isolation_test_path):
		print("\n[ISOLATION AUDIT ERROR] Test save isolation test suite missing")
		sys.exit(1)
	print("=== Test Save Isolation Audit (F22) ===")
	iso_res = subprocess.run([sys.executable, "-I", isolation_test_path], cwd=game_dir)
	if iso_res.returncode != 0:
		print("\n[ISOLATION AUDIT FAIL] F22 save isolation tests failed.")
		sys.exit(1)
	print("[ISOLATION AUDIT OK] Test save isolation verified.\n")

	EXPECTED = ["db_test", "idempotent_sync_test", "sync_ingest_isolation_test", "real_save_untouched"]

	# Check for Godot executable to run runtime GDScript tests
	godot_bin = shutil.which("godot") or shutil.which("godot4")
	if not godot_bin:
		print("game runtime tests SKIPPED — Godot not installed; CI runs them\n")
	else:
		print(f"=== Game Runtime Test Suite (Headless Godot) ===")
		print(f"Using Godot binary: {godot_bin}")

		# 1. Harness self-test (TENTH_SPRING_HARNESS_SELFTEST=1 must exit 1 and report FAIL harness_selftest)
		print("Running harness self-test...")
		selftest_env = os.environ.copy()
		selftest_env["TENTH_SPRING_HARNESS_SELFTEST"] = "1"
		selftest_res = subprocess.run(
			[godot_bin, "--headless", "--path", "game", "res://tests/test_main.tscn"],
			cwd=repo_root,
			capture_output=True,
			text=True,
			env=selftest_env,
			timeout=300
		)
		selftest_out = (selftest_res.stdout or "") + (selftest_res.stderr or "")
		if selftest_res.returncode != 1 or "FAIL harness_selftest" not in selftest_out:
			print(f"\n[HARNESS SELF-TEST FAILED] Expected exit code 1 with 'FAIL harness_selftest', got exit code {selftest_res.returncode}:\n{selftest_out}")
			sys.exit(1)
		print("[HARNESS SELF-TEST OK] Harness successfully caught injected failure.\n")

		# 2. Main test suite
		print("Running main game test suite...")
		main_res = subprocess.run(
			[godot_bin, "--headless", "--path", "game", "res://tests/test_main.tscn"],
			cwd=repo_root,
			capture_output=True,
			text=True,
			timeout=300
		)
		main_out = (main_res.stdout or "") + (main_res.stderr or "")
		print(main_out)

		if main_res.returncode != 0:
			print(f"[TEST RUNNER FAIL] Godot exited with code {main_res.returncode}")
			sys.exit(1)

		if "SCRIPT ERROR" in main_out:
			print("[TEST RUNNER FAIL] Script error detected in Godot output")
			sys.exit(1)

		lines = main_out.splitlines()
		has_fail = any(line.strip().startswith("FAIL ") for line in lines)
		if has_fail:
			print("[TEST RUNNER FAIL] Test failure detected in output")
			sys.exit(1)

		passed_tests = [line.strip().split()[1] for line in lines if line.strip().startswith("PASS ")]
		if sorted(passed_tests) != sorted(EXPECTED) or len(passed_tests) != len(EXPECTED):
			print(f"[TEST RUNNER FAIL] Passed tests {passed_tests} do not match EXPECTED {EXPECTED}")
			sys.exit(1)

		print(f"[ALL GAME TESTS PASS] All {len(EXPECTED)} expected tests passed.\n")

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

if __name__ == '__main__':
	main()
