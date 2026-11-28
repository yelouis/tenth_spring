extends Node

# Demo Import Server Scene (Items 6, 28, 95 / Decision 86)
# Headless Godot importer for demo starter city & opened places:
#   --starter <city id> [--open <place id>,...]
# Writes home/explore rows with NULL coordinates and calls RevealEngine.apply(DB).

const PlacesPack := preload("res://world/places_pack.gd")
const ProfilePaths := preload("res://scripts/profile_paths.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

func _ready() -> void:
	var profile = ProfilePaths.resolve_from_cmdline()
	if not profile.ok:
		printerr("Failed to resolve profile paths: " + str(profile.error))
		get_tree().quit(1)
		return

	if not profile.is_demo:
		profile = ProfilePaths.resolve(["--demo"])

	DB.configure_paths(profile.db_path, profile.db_tmp_path)
	DB.init_db()

	var starter_id := ""
	var open_ids: Array[String] = []
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i]).strip_edges()
		if arg == "--starter" and i + 1 < args.size():
			starter_id = str(args[i + 1]).strip_edges()
			i += 1
		elif arg.begins_with("--starter="):
			starter_id = arg.substr(10).strip_edges()
		elif arg == "--open" and i + 1 < args.size():
			var raw_open := str(args[i + 1]).strip_edges()
			i += 1
			for part in raw_open.split(",", false):
				var pid := part.strip_edges()
				if not pid.is_empty():
					open_ids.append(pid)
		elif arg.begins_with("--open="):
			var raw_open2 := arg.substr(7).strip_edges()
			for part in raw_open2.split(",", false):
				var pid := part.strip_edges()
				if not pid.is_empty():
					open_ids.append(pid)
		i += 1

	if starter_id.is_empty():
		printerr("[FAIL] unknown place id: ")
		DB.close()
		get_tree().quit(2)
		return

	var starter_info: Dictionary = PlacesPack.place_info(starter_id)
	if starter_info.is_empty() or str(starter_info.get("kind", "")) != "city":
		printerr("[FAIL] unknown place id: %s" % starter_id)
		DB.close()
		get_tree().quit(2)
		return

	for pid in open_ids:
		if not PlacesPack.has_place(pid):
			printerr("[FAIL] unknown place id: %s" % pid)
			DB.close()
			get_tree().quit(2)
			return

	var peer_id := "demo_peer"
	var peer_info := DB.get_sync_peer(peer_id)
	var seq: int = int(peer_info.get("last_applied_seq", 0))
	var max_rows := DB.query_rows("SELECT MAX(seq) AS m FROM visit_log WHERE peer_id = ?;", [peer_id])
	if not max_rows.is_empty() and max_rows[0].get("m") != null:
		seq = maxi(seq, int(max_rows[0]["m"]))

	var ts_base: int = int(Time.get_unix_time_from_system()) * 1000
	var applied_count := 0

	if not DB.begin_transaction():
		printerr("demo_import_server: failed to begin transaction: " + DB.last_error)
		DB.close()
		get_tree().quit(1)
		return

	seq += 1
	if DB.insert_visit_log({
		"peer_id": peer_id,
		"seq": seq,
		"place_id": starter_id,
		"lat": null,
		"lon": null,
		"started_at": ts_base + seq,
		"dwell_seconds": 0,
		"kind": "home",
	}):
		applied_count += 1

	for pid in open_ids:
		var areas: Array = PlacesPack.areas_of(pid)
		for a_v in areas:
			if not (a_v is Dictionary):
				continue
			var akey := str((a_v as Dictionary).get("key", "")).strip_edges()
			if akey.is_empty():
				continue
			seq += 1
			if DB.insert_visit_log({
				"peer_id": peer_id,
				"seq": seq,
				"place_id": akey,
				"lat": null,
				"lon": null,
				"started_at": ts_base + seq,
				"dwell_seconds": 0,
				"kind": "explore",
			}):
				applied_count += 1

	DB.update_sync_peer_seq(peer_id, seq)
	DB.commit_transaction()

	var reveal_res := RevealEngine.apply(DB)
	if not bool(reveal_res.get("ok", false)):
		printerr("demo_import_server: RevealEngine.apply failed: " + str(reveal_res))
		DB.close()
		get_tree().quit(1)
		return

	print("DEMO_IMPORT_COMPLETE applied %d rows" % applied_count)
	DB.close()
	get_tree().quit(0)
