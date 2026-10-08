extends Node

# Test Harness (Item 0 / F25)
# Discovers res://tests/*_test.gd in alphabetical order, executes each,
# records non-destructive hash check of real save files, and exits with 0 or 1.

func _ready() -> void:
	# 1. Record pre-test state of real save files (F22 real-save check)
	var real_db_path = "user://tenth_spring.db"
	var real_tmp_path = "user://tenth_spring.db.tmp"
	var pre_db_exists = FileAccess.file_exists(real_db_path)
	var pre_db_sha = FileAccess.get_sha256(real_db_path) if pre_db_exists else ""
	var pre_tmp_exists = FileAccess.file_exists(real_tmp_path)
	var pre_tmp_sha = FileAccess.get_sha256(real_tmp_path) if pre_tmp_exists else ""

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

	# 5. Real-save check after all tests
	var post_db_exists = FileAccess.file_exists(real_db_path)
	var post_db_sha = FileAccess.get_sha256(real_db_path) if post_db_exists else ""
	var post_tmp_exists = FileAccess.file_exists(real_tmp_path)
	var post_tmp_sha = FileAccess.get_sha256(real_tmp_path) if post_tmp_exists else ""

	var save_untouched = (pre_db_exists == post_db_exists and pre_db_sha == post_db_sha and
		pre_tmp_exists == post_tmp_exists and pre_tmp_sha == post_tmp_sha)
	if save_untouched:
		print("PASS real_save_untouched")
	else:
		print("FAIL real_save_untouched")
		all_passed = false

	# 6. Exit with 0 if all passed, else 1
	get_tree().quit(0 if all_passed else 1)
