extends Node

# Demo Import Server Scene (Items 6, 28 / explore plan §4.5)
# Headless Godot importer for demo explore points (--points <file.json>).
# Looks up each point in PlacesPack and writes v3 explore/home rows with NULL coordinates.

const Grid := preload("res://world/grid.gd")
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

	DirAccess.make_dir_recursive_absolute(profile.identity_dir)

	DB.configure_paths(profile.db_path, profile.db_tmp_path)
	DB.init_db()

	var points_path := ""
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i]).strip_edges()
		if arg == "--points" and i + 1 < args.size():
			points_path = str(args[i + 1]).strip_edges()
			i += 1
		elif arg.begins_with("--points="):
			points_path = arg.substr(9).strip_edges()
		i += 1

	if points_path.is_empty() or not FileAccess.file_exists(points_path):
		printerr("demo_import_server: missing or unreadable --points file: " + points_path)
		DB.close()
		get_tree().quit(1)
		return

	var json_txt := FileAccess.get_file_as_string(points_path)
	var parsed: Variant = JSON.parse_string(json_txt)
	if parsed == null:
		printerr("demo_import_server: invalid JSON in " + points_path)
		DB.close()
		get_tree().quit(1)
		return

	var point_items: Array = []
	var home_dict: Dictionary = {}

	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary:
				if entry.has("home") and entry["home"] is Dictionary:
					home_dict = entry["home"]
				elif entry.has("lat") and entry.has("lon"):
					point_items.append(entry)
	elif parsed is Dictionary:
		if parsed.has("home") and parsed["home"] is Dictionary:
			home_dict = parsed["home"]
		if parsed.has("points") and parsed["points"] is Array:
			for entry in parsed["points"]:
				if entry is Dictionary and entry.has("lat") and entry.has("lon"):
					point_items.append(entry)

	var peer_id := "demo_peer"
	var peer_info := DB.get_sync_peer(peer_id)
	var seq: int = int(peer_info.get("last_applied_seq", 0))
	var ts_base: int = int(Time.get_unix_time_from_system()) * 1000
	var batch_rows: Array = []

	if not home_dict.is_empty() and home_dict.has("lat") and home_dict.has("lon"):
		var h_lat := float(home_dict["lat"])
		var h_lon := float(home_dict["lon"])
		var nearest_city_id: String = PlacesPack.nearest_city(h_lat, h_lon)
		if not nearest_city_id.is_empty():
			seq += 1
			batch_rows.append({
				"seq": seq,
				"kind": "home",
				"placeId": nearest_city_id,
				"tsUtcMs": ts_base + seq
			})

	for pt in point_items:
		var p_lat := float(pt["lat"])
		var p_lon := float(pt["lon"])
		var cell: Vector2i = Grid.latlon_to_cell(p_lat, p_lon)
		var hit: Dictionary = PlacesPack.lookup_cell(cell.x, cell.y)
		if not hit.is_empty():
			var pid: String = str(hit.get("place_id", ""))
			var akey: String = str(hit.get("area_key", ""))
			if not pid.is_empty() and not akey.is_empty():
				seq += 1
				batch_rows.append({
					"seq": seq,
					"kind": "explore",
					"placeId": pid,
					"areaKey": akey,
					"tsUtcMs": ts_base + seq
				})

	var applied_count := 0
	if not batch_rows.is_empty():
		var res := SyncServer.process_batch(peer_id, {"rows": batch_rows})
		if res.get("status") != "ack":
			printerr("demo_import_server: process_batch failed: " + str(res))
			DB.close()
			get_tree().quit(1)
			return
		applied_count = int(res.get("appliedCount", 0))
	else:
		RevealEngine.apply(DB)

	print("DEMO_IMPORT_COMPLETE applied %d rows" % applied_count)
	DB.close()
	get_tree().quit(0)
