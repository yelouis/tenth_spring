extends Node

# Test Harness (Item 0 / F25)
# Discovers res://tests/*_test.gd in alphabetical order, executes each,
# records non-destructive hash check of real save files, and exits with 0 or 1.

func _ready() -> void:
	# 1. Record pre-test state of real save and identity files (F22 real-save check + Item 3a)
	var protected_files = [
		"user://tenth_spring.db",
		"user://tenth_spring.db.tmp",
		"user://sync_identity/pc.key",
		"user://sync_identity/pc.crt",
		"user://sync_identity/pc_id.txt"
	]
	var pre_states = {}
	for p in protected_files:
		var ex = FileAccess.file_exists(p)
		var sha = FileAccess.get_sha256(p) if ex else ""
		pre_states[p] = {"exists": ex, "sha": sha}

	var all_passed = true

	# 2. Discover tests in res://tests/
	var test_files: Array[String] = []
	var raw_files = DirAccess.get_files_at("res://tests/")
	for f in raw_files:
		if f.ends_with("_test.gd"):
			test_files.append(f)
	test_files.sort()

	# 3. Execute each discovered test
	for f in test_files:
		var basename = f.trim_suffix(".gd")
		var s = load("res://tests/" + f)
		if s == null or not s.can_instantiate():
			print("FAIL %s" % basename)
			all_passed = false
			continue

		var t = s.new()
		add_child(t)
		var ok = false
		if t.has_method("run_test"):
			ok = (t.run_test() == true)
		if ok:
			print("PASS %s" % basename)
		else:
			print("FAIL %s" % basename)
			all_passed = false
		t.queue_free()

	# 4. Self-test hook: if TENTH_SPRING_HARNESS_SELFTEST == "1", run harness_selftest.gd
	if OS.get_environment("TENTH_SPRING_HARNESS_SELFTEST") == "1":
		var s = load("res://tests/harness_selftest.gd")
		if s == null or not s.can_instantiate():
			print("FAIL harness_selftest")
			all_passed = false
		else:
			var t = s.new()
			add_child(t)
			var ok = false
			if t.has_method("run_test"):
				ok = (t.run_test() == true)
			if ok:
				print("PASS harness_selftest")
			else:
				print("FAIL harness_selftest")
				all_passed = false
			t.queue_free()

	# 5. Real-save and identity check after all tests
	var save_untouched = true
	for p in protected_files:
		var post_ex = FileAccess.file_exists(p)
		var post_sha = FileAccess.get_sha256(p) if post_ex else ""
		var pre_info = pre_states[p]
		if pre_info["exists"] != post_ex or pre_info["sha"] != post_sha:
			save_untouched = false
			push_error("Protected file modified or created during test: " + p)
			break

	if save_untouched:
		print("PASS real_save_untouched")
	else:
		print("FAIL real_save_untouched")
		all_passed = false

	# 6. Exit with 0 if all passed, else 1
	get_tree().quit(0 if all_passed else 1)
