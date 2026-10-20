class_name ProfilePaths
extends RefCounted

# ProfilePaths: resolves database and sync identity paths for Tenth Spring.
# Enforces complete isolation between primary save and demo profile.
# Contract: docs/implementation_plan_world_generation.md §1.1

const DEFAULT_DB_PATH: String = "user://tenth_spring.db"
const DEFAULT_DB_TMP_PATH: String = "user://tenth_spring.db.tmp"
const DEFAULT_IDENTITY_DIR: String = "user://sync_identity/"
const DEFAULT_DEMO_DIR: String = "user://demo"
const DEFAULT_MAP_DATA_DIR: String = "user://map_data"

const ERR_COLLIDES_WITH_PRIMARY: String = "demo directory cannot collide with primary save path"
const ERR_MISSING_DEMO_DIR_ARG: String = "missing argument for --demo-dir"

static func resolve_from_cmdline() -> Dictionary:
	var user_args = OS.get_cmdline_user_args()
	if not user_args.is_empty():
		return resolve(user_args)
	return resolve(OS.get_cmdline_args())

static func resolve(args: Array = []) -> Dictionary:
	var is_demo: bool = false
	var custom_demo_dir: String = ""
	var has_custom_demo_dir: bool = false

	var i: int = 0
	while i < args.size():
		var arg: String = str(args[i]).strip_edges()
		if arg == "--demo":
			is_demo = true
		elif arg == "--demo-dir":
			is_demo = true
			has_custom_demo_dir = true
			if i + 1 < args.size():
				custom_demo_dir = str(args[i + 1]).strip_edges()
				i += 1
			else:
				return {
					"ok": false,
					"error": ERR_MISSING_DEMO_DIR_ARG,
					"is_demo": true,
					"db_path": "",
					"db_tmp_path": "",
					"identity_dir": "",
					"map_data_dir": ""
				}
		elif arg.begins_with("--demo-dir="):
			is_demo = true
			has_custom_demo_dir = true
			custom_demo_dir = arg.substr(11).strip_edges()
		i += 1

	if not is_demo:
		return {
			"ok": true,
			"error": "",
			"is_demo": false,
			"db_path": DEFAULT_DB_PATH,
			"db_tmp_path": DEFAULT_DB_TMP_PATH,
			"identity_dir": DEFAULT_IDENTITY_DIR,
			"map_data_dir": DEFAULT_MAP_DATA_DIR
		}

	var demo_dir: String = custom_demo_dir if has_custom_demo_dir else DEFAULT_DEMO_DIR
	while demo_dir.ends_with("/") and demo_dir != "user://" and demo_dir != "/":
		demo_dir = demo_dir.left(demo_dir.length() - 1)

	# Safety check: demo directory must never be root user:// or point to production files
	if demo_dir == "user://" or demo_dir == "user:" or demo_dir == "" or demo_dir == "/":
		return {
			"ok": false,
			"error": ERR_COLLIDES_WITH_PRIMARY,
			"is_demo": true,
			"db_path": "",
			"db_tmp_path": "",
			"identity_dir": "",
			"map_data_dir": ""
		}

	var candidate_db = demo_dir + "/tenth_spring.db"
	var candidate_id = demo_dir + "/sync_identity/"
	if candidate_db == DEFAULT_DB_PATH or candidate_id == DEFAULT_IDENTITY_DIR or demo_dir == "user://sync_identity":
		return {
			"ok": false,
			"error": ERR_COLLIDES_WITH_PRIMARY,
			"is_demo": true,
			"db_path": "",
			"db_tmp_path": "",
			"identity_dir": "",
			"map_data_dir": ""
		}

	return {
		"ok": true,
		"error": "",
		"is_demo": true,
		"db_path": candidate_db,
		"db_tmp_path": candidate_db + ".tmp",
		"identity_dir": candidate_id,
		"map_data_dir": demo_dir + "/map_data"
	}

static func get_map_data_dir() -> String:
	var res := resolve_from_cmdline()
	return str(res.get("map_data_dir", DEFAULT_MAP_DATA_DIR))
