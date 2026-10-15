extends Node

# map_convert.gd — Headless Map Converter Scene Script
# CLI driver for regional OSM PBF conversion.

const RegionConverter := preload("res://world/region_import/region_converter.gd")

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var pbf_path := ""
	var out_dir := "user://map_data"

	var i := 0
	while i < user_args.size():
		var arg := user_args[i]
		if arg == "--pbf" and i + 1 < user_args.size():
			pbf_path = user_args[i + 1]
			i += 2
		elif arg == "--out-dir" and i + 1 < user_args.size():
			out_dir = user_args[i + 1]
			i += 2
		elif arg.begins_with("--pbf="):
			pbf_path = arg.trim_prefix("--pbf=")
			i += 1
		elif arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=")
			i += 1
		else:
			i += 1

	if pbf_path.is_empty():
		printerr("map_convert: Missing required argument --pbf <file.osm.pbf>")
		get_tree().quit(1)
		return

	if not FileAccess.file_exists(pbf_path):
		printerr("map_convert: PBF file does not exist: %s" % pbf_path)
		get_tree().quit(1)
		return

	var file_base: String = pbf_path.get_file()
	if file_base.ends_with(".osm.pbf"):
		file_base = file_base.trim_suffix(".osm.pbf")
	elif file_base.ends_with(".pbf"):
		file_base = file_base.trim_suffix(".pbf")

	if file_base.ends_with("-latest"):
		file_base = file_base.trim_suffix("-latest")

	var db_filename: String = file_base + ".db"
	var out_db_path: String = out_dir.path_join(db_filename)

	print("=== Tenth Spring Map Converter ===")
	print("Input PBF: ", pbf_path)
	print("Output DB: ", out_db_path)

	var conv := RegionConverter.new()
	var res := conv.convert(pbf_path, out_db_path)

	if not res.get("ok", false):
		printerr("map_convert: Conversion failed: %s" % res.get("error", "unknown"))
		get_tree().quit(1)
		return

	print("MAP_CONVERT_SUCCESS features_poly=%d features_line=%d place_nodes=%d time_ms=%d hash=%s" % [
		res.get("features_poly", 0),
		res.get("features_line", 0),
		res.get("place_nodes", 0),
		res.get("time_ms", 0),
		res.get("canonical_hash", "")
	])

	get_tree().quit(0)
