extends Node

# Unit & Integration test for ProfilePaths and Demo Profile Isolation
# Contract: docs/implementation_plan_world_generation.md §1 & docs/agent_execution_guide.md §6.1

const ProfilePaths := preload("res://scripts/profile_paths.gd")

func run_test() -> bool:
	# ---------------------------------------------------------
	# 1. Row 1: Default Production (no demo args)
	# ---------------------------------------------------------
	var r1 = ProfilePaths.resolve([])
	if not r1.ok or r1.is_demo != false or r1.error != "":
		push_error("Row 1 failed: expected ok=true, is_demo=false, error='', got: %s" % str(r1))
		return false
	if r1.db_path != "user://tenth_spring.db" or r1.db_tmp_path != "user://tenth_spring.db.tmp" or r1.identity_dir != "user://sync_identity/" or r1.get("map_data_dir", "") != "user://map_data":
		push_error("Row 1 failed: incorrect paths: %s" % str(r1))
		return false

	var r1_extra = ProfilePaths.resolve(["--fullscreen", "--verbose"])
	if not r1_extra.ok or r1_extra.is_demo != false or r1_extra.db_path != "user://tenth_spring.db" or r1_extra.get("map_data_dir", "") != "user://map_data":
		push_error("Row 1 with extra args failed: %s" % str(r1_extra))
		return false

	# ---------------------------------------------------------
	# 2. Row 2: Default Demo (--demo)
	# ---------------------------------------------------------
	var r2 = ProfilePaths.resolve(["--demo"])
	if not r2.ok or r2.is_demo != true or r2.error != "":
		push_error("Row 2 failed: expected ok=true, is_demo=true, error='', got: %s" % str(r2))
		return false
	if r2.db_path != "user://demo/tenth_spring.db" or r2.db_tmp_path != "user://demo/tenth_spring.db.tmp" or r2.identity_dir != "user://demo/sync_identity/" or r2.get("map_data_dir", "") != "user://demo/map_data":
		push_error("Row 2 failed: incorrect paths: %s" % str(r2))
		return false

	# ---------------------------------------------------------
	# 3. Row 3: Custom Demo Dir (--demo-dir <path>)
	# ---------------------------------------------------------
	var r3 = ProfilePaths.resolve(["--demo-dir", "user://test/demo"])
	if not r3.ok or r3.is_demo != true or r3.error != "":
		push_error("Row 3 failed: expected ok=true, is_demo=true, error='', got: %s" % str(r3))
		return false
	if r3.db_path != "user://test/demo/tenth_spring.db" or r3.db_tmp_path != "user://test/demo/tenth_spring.db.tmp" or r3.identity_dir != "user://test/demo/sync_identity/" or r3.get("map_data_dir", "") != "user://test/demo/map_data":
		push_error("Row 3 failed: incorrect paths: %s" % str(r3))
		return false

	var r3_eq = ProfilePaths.resolve(["--demo", "--demo-dir=user://test/demo"])
	if not r3_eq.ok or r3_eq.is_demo != true or r3_eq.db_path != "user://test/demo/tenth_spring.db":
		push_error("Row 3 with --demo-dir=path failed: %s" % str(r3_eq))
		return false

	# ---------------------------------------------------------
	# 4. Row 4: Refusal Row (Falsifying test)
	# ---------------------------------------------------------
	# Must refuse root user:// collision with verbatim error
	var r4_root = ProfilePaths.resolve(["--demo-dir", "user://"])
	if r4_root.ok != false:
		push_error("Row 4 failed: expected ok=false for root user://, got ok=true")
		return false
	if r4_root.error != "demo directory cannot collide with primary save path":
		push_error("Row 4 failed: verbatim error mismatch. Expected 'demo directory cannot collide with primary save path', got '%s'" % r4_root.error)
		return false

	# Must refuse missing argument for --demo-dir with verbatim error
	var r4_missing = ProfilePaths.resolve(["--demo-dir"])
	if r4_missing.ok != false:
		push_error("Row 4 failed: expected ok=false for missing --demo-dir argument, got ok=true")
		return false
	if r4_missing.error != "missing argument for --demo-dir":
		push_error("Row 4 failed: verbatim error mismatch for missing argument. Got '%s'" % r4_missing.error)
		return false

	# Must refuse identity dir collision
	var r4_id = ProfilePaths.resolve(["--demo-dir", "user://sync_identity"])
	if r4_id.ok != false or r4_id.error != "demo directory cannot collide with primary save path":
		push_error("Row 4 failed: collision with sync_identity not refused properly: %s" % str(r4_id))
		return false

	# ---------------------------------------------------------
	# 5. Integration Case (§1.3): Complete Save Isolation
	# ---------------------------------------------------------
	var integ_dir = "user://test/demo_profile_integ"
	var integ_db = integ_dir + "/tenth_spring.db"
	var integ_tmp = integ_dir + "/tenth_spring.db.tmp"
	var integ_id = integ_dir + "/sync_identity/"

	# Cleanup test directory before start
	_cleanup_dir(integ_dir)

	var orig_db_path = DB.DB_PATH
	var orig_tmp_path = DB.DB_TMP_PATH

	var p = ProfilePaths.resolve(["--demo-dir", integ_dir])
	if not p.ok:
		push_error("Integration test: resolve failed: %s" % p.error)
		return false

	DB.configure_paths(p.db_path, p.db_tmp_path)
	var identity = PcIdentity.new()
	identity.configure_dir(p.identity_dir)
	SyncServer.configure_identity(identity)

	DB.init_db()
	if not identity.load_or_create():
		push_error("Integration test: failed to load or create identity in %s" % p.identity_dir)
		DB.close()
		DB.configure_paths(orig_db_path, orig_tmp_path)
		return false

	# Insert synthetic record into demo profile
	var ok_insert = DB.insert_visit_log({
		"peer_id": "test_peer_1",
		"seq": 1,
		"place_id": null,
		"lat": 0.01,
		"lon": 0.01,
		"started_at": 1000,
		"dwell_seconds": 600,
		"kind": "visit"
	})
	if not ok_insert:
		push_error("Integration test: failed to insert synthetic visit into demo db")
		DB.close()
		DB.configure_paths(orig_db_path, orig_tmp_path)
		return false

	DB.close()

	# Assertions: demo DB and cert exist in demo dir
	if not FileAccess.file_exists(integ_db):
		push_error("Integration test: expected demo db at %s, but file does not exist" % integ_db)
		DB.configure_paths(orig_db_path, orig_tmp_path)
		return false

	if not FileAccess.file_exists(integ_id + "pc.crt"):
		push_error("Integration test: expected demo cert at %spc.crt, but file does not exist" % integ_id)
		DB.configure_paths(orig_db_path, orig_tmp_path)
		return false

	# Assertions: real save was NOT created or modified
	if FileAccess.file_exists("user://tenth_spring.db"):
		push_error("Integration test VIOLATION: real save user://tenth_spring.db exists!")
		DB.configure_paths(orig_db_path, orig_tmp_path)
		return false

	# Cleanup test directory and restore paths
	_cleanup_dir(integ_dir)
	DB.configure_paths(orig_db_path, orig_tmp_path)
	SyncServer.configure_identity(null)

	return true

func _cleanup_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var d = DirAccess.open(dir_path)
	if d != null:
		d.list_dir_begin()
		var file_name = d.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_sub = dir_path + "/" + file_name
				if d.current_is_dir():
					_cleanup_dir(full_sub)
				else:
					DirAccess.remove_absolute(full_sub)
			file_name = d.get_next()
		d.list_dir_end()
		DirAccess.remove_absolute(dir_path)
