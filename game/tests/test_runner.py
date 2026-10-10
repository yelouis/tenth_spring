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

def check_vendored_checksums(game_dir):
	"""Recomputes SHA-256 for all vendored files and verifies complete coverage."""
	vendored_dir = os.path.join(game_dir, "addons", "godot-sqlite")
	sha_file = os.path.join(vendored_dir, "VENDORED.sha256")
	if not os.path.exists(sha_file):
		print("\n[VENDORED CHECK FAIL] VENDORED.sha256 missing")
		sys.exit(1)

	import hashlib
	with open(sha_file, "r", encoding="utf-8") as f:
		lines = [l.strip() for l in f if l.strip()]

	expected_hashes = {}
	for line in lines:
		parts = line.split(None, 1)
		if len(parts) == 2:
			expected_hashes[parts[1].strip()] = parts[0]

	for rel_p, exp_hash in expected_hashes.items():
		full_p = os.path.join(vendored_dir, rel_p)
		if not os.path.isfile(full_p):
			print(f"\n[VENDORED CHECK FAIL] Listed file missing: {rel_p}")
			sys.exit(1)
		h = hashlib.sha256()
		with open(full_p, "rb") as bf:
			while chunk := bf.read(65536):
				h.update(chunk)
		act_hash = h.hexdigest()
		if act_hash != exp_hash:
			print(f"\n[VENDORED CHECK FAIL] SHA256 mismatch for {rel_p}: expected {exp_hash}, got {act_hash}")
			sys.exit(1)

	bin_dir = os.path.join(vendored_dir, "bin")
	if os.path.exists(bin_dir):
		for root, _, files in os.walk(bin_dir):
			for file in files:
				file_full = os.path.join(root, file)
				file_rel = os.path.relpath(file_full, vendored_dir)
				if file_rel not in expected_hashes:
					print(f"\n[VENDORED CHECK FAIL] File under bin/ not listed in VENDORED.sha256: {file_rel}")
					sys.exit(1)

def get_godot_user_dir():
	"""Computes Godot user data directory for project name 'Tenth Spring'."""
	app_name = "Tenth Spring"
	if sys.platform.startswith("linux"):
		xdg_data = os.environ.get("XDG_DATA_HOME")
		if not xdg_data:
			xdg_data = os.path.expanduser("~/.local/share")
		return os.path.join(xdg_data, "godot", "app_userdata", app_name)
	elif sys.platform == "darwin":
		return os.path.expanduser(f"~/Library/Application Support/Godot/app_userdata/{app_name}")
	elif sys.platform == "win32":
		appdata = os.environ.get("APPDATA")
		if not appdata:
			appdata = os.path.expanduser("~\\AppData\\Roaming")
		return os.path.join(appdata, "Godot", "app_userdata", app_name)
	else:
		xdg_data = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
		return os.path.join(xdg_data, "godot", "app_userdata", app_name)

PROTECTED_SAVE_FILES = [
	"tenth_spring.db",
	"tenth_spring.db-wal",
	"tenth_spring.db-shm",
	"tenth_spring.db.tmp",
	"tenth_spring.db.jsonbak",
	"sync_identity/pc.key",
	"sync_identity/pc.crt",
	"sync_identity/pc_id.txt",
]

def snapshot_protected_files(user_dir):
	import hashlib
	snapshot = {}
	for rel_file in PROTECTED_SAVE_FILES:
		full_path = os.path.join(user_dir, *rel_file.split("/"))
		if os.path.isfile(full_path):
			h = hashlib.sha256()
			with open(full_path, "rb") as f:
				while chunk := f.read(65536):
					h.update(chunk)
			snapshot[rel_file] = h.hexdigest()
		else:
			snapshot[rel_file] = None
	return snapshot

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

	# Developer Tooling Memory Guard Test Suite (F38)
	memguard_tests_path = os.path.join(repo_root, "tools", "test_memguard.py")
	if not os.path.exists(memguard_tests_path):
		print("\n[MEMGUARD ERROR] Memguard test suite missing")
		sys.exit(1)
	print("=== Memguard Test Suite (F38) ===")
	mem_res = subprocess.run([sys.executable, "-I", memguard_tests_path], cwd=repo_root)
	if mem_res.returncode != 0:
		print("\n[MEMGUARD TEST FAIL] Memguard unit tests failed.")
		sys.exit(1)
	print("[MEMGUARD TESTS OK] All memguard test cases passed.\n")

	# Vendored GDExtension Integrity Check (Decision 7)
	print("=== Vendored GDExtension Integrity Check ===")
	check_vendored_checksums(game_dir)
	print("[VENDORED EXTENSION OK] All vendored files match VENDORED.sha256 exactly.\n")

	EXPECTED = [
		"db_legacy_import_test",
		"db_migration_test",
		"db_test",
		"frame_codec_test",
		"idempotent_sync_test",
		"pairing_codes_test",
		"pc_identity_test",
		"qr_code_test",
		"real_save_untouched",
		"sync_ingest_isolation_test",
		"sync_session_test"
	]

	# Check for Godot executable to run runtime GDScript tests
	godot_bin = shutil.which("godot") or shutil.which("godot4")
	if not godot_bin:
		print("game runtime tests SKIPPED — Godot not installed; CI runs them\n")
	else:
		print(f"=== Game Runtime Test Suite (Headless Godot) ===")
		print(f"Using Godot binary: {godot_bin}")

		# F29 Runner-level snapshot: snapshot protected save files before first Godot invocation
		user_dir = get_godot_user_dir()
		pre_snap = snapshot_protected_files(user_dir)

		memguard_script = os.path.join(repo_root, "tools", "memguard.py")

		# 1. Harness self-test (TENTH_SPRING_HARNESS_SELFTEST=1 must exit 1 and report FAIL harness_selftest)
		print("Running harness self-test...")
		selftest_env = os.environ.copy()
		selftest_env["TENTH_SPRING_HARNESS_SELFTEST"] = "1"
		selftest_cmd = [godot_bin, "--headless", "--path", "game", "res://tests/test_main.tscn"]
		selftest_guarded = [sys.executable, "-I", memguard_script, "run", "godot_selftest", "--"] + selftest_cmd
		selftest_res = subprocess.run(
			selftest_guarded,
			cwd=repo_root,
			capture_output=True,
			text=True,
			env=selftest_env,
			timeout=300
		)
		if selftest_res.returncode in (75, 76):
			print(selftest_res.stderr or selftest_res.stdout)
			sys.exit(selftest_res.returncode)
		selftest_out = (selftest_res.stdout or "") + (selftest_res.stderr or "")
		if selftest_res.returncode != 1 or "FAIL harness_selftest" not in selftest_out:
			print(f"\n[HARNESS SELF-TEST FAILED] Expected exit code 1 with 'FAIL harness_selftest', got exit code {selftest_res.returncode}:\n{selftest_out}")
			sys.exit(1)
		print("[HARNESS SELF-TEST OK] Harness successfully caught injected failure.\n")

		# 2. Main test suite
		print("Running main game test suite...")
		main_cmd = [godot_bin, "--headless", "--path", "game", "res://tests/test_main.tscn"]
		main_guarded = [sys.executable, "-I", memguard_script, "run", "godot_tests", "--"] + main_cmd
		main_res = subprocess.run(
			main_guarded,
			cwd=repo_root,
			capture_output=True,
			text=True,
			timeout=300
		)
		if main_res.returncode in (75, 76):
			print(main_res.stderr or main_res.stdout)
			sys.exit(main_res.returncode)
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

		# F29 Vacuity guard: after the run, assert <user dir>/test/ exists
		test_dir = os.path.join(user_dir, "test")
		if not os.path.isdir(test_dir):
			print(f"\n[REAL SAVE CHECK FAIL] computed Godot user dir is wrong: {user_dir}")
			sys.exit(1)

		# F29 Snapshot comparison: compare after the main run
		post_snap = snapshot_protected_files(user_dir)
		is_ci = os.environ.get("CI") == "true"
		for rel_file in PROTECTED_SAVE_FILES:
			pre_hash = pre_snap.get(rel_file)
			post_hash = post_snap.get(rel_file)
			if pre_hash != post_hash:
				print(f"\n[REAL SAVE CHECK FAIL] {rel_file} changed during the test run")
				sys.exit(1)
			if is_ci and post_hash is not None:
				print(f"\n[REAL SAVE CHECK FAIL] {rel_file} exists after the test run in CI")
				sys.exit(1)

		print(f"[REAL SAVE CHECK OK] Godot user dir verified: {user_dir} (test/ exists, protected files untouched)\n")

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

	# F19 Static Rule: Ensure db.gd has no lines combining SQL keywords and string formatting/concatenation
	db_gd_path = os.path.join(game_dir, "autoloads", "db.gd")
	if os.path.exists(db_gd_path):
		with open(db_gd_path, 'r', encoding='utf-8') as f:
			db_lines = f.readlines()
		sql_keywords = ["INSERT", "UPDATE", "DELETE", "SELECT", "CREATE"]
		for idx, line in enumerate(db_lines, 1):
			has_kw = any(kw in line for kw in sql_keywords)
			has_interp = ("%" in line) or ('" +' in line) or ('"+"' in line)
			if has_kw and has_interp:
				print(f"\n[F19 SQL INJECTION HAZARD] Line {idx} in db.gd contains SQL keyword and string formatting/concatenation:")
				print(f"  {line.strip()}")
				total_errors += 1

	if total_errors > 0:
		print(f"\nStatic lint failed with {total_errors} error(s).")
		sys.exit(1)

	print("\nStatic lint passed. Golden Invariant 1 static capability guard intact.")

if __name__ == '__main__':
	main()
