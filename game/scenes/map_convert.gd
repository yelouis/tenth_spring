extends Node

# map_convert.gd — Headless Map Converter Scene Script
# CLI driver for regional OSM PBF conversion.

const RegionConverter := preload("res://world/region_import/region_converter.gd")
const MapFetcher := preload("res://world/region_import/map_fetcher.gd")

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var pbf_path := ""
	var out_dir := "user://map_data"
	var clip_to_save := ""
	var margin_cells := 6
	var print_region_save := ""
	var place_id := ""
	var config_path := ""

	var i := 0
	while i < user_args.size():
		var arg := user_args[i]
		if arg == "--print-region" and i + 1 < user_args.size():
			print_region_save = user_args[i + 1]
			i += 2
		elif arg.begins_with("--print-region="):
			print_region_save = arg.trim_prefix("--print-region=")
			i += 1
		elif arg == "--place" and i + 1 < user_args.size():
			place_id = user_args[i + 1]
			i += 2
		elif arg.begins_with("--place="):
			place_id = arg.trim_prefix("--place=")
			i += 1
		elif arg == "--config" and i + 1 < user_args.size():
			config_path = user_args[i + 1]
			i += 2
		elif arg.begins_with("--config="):
			config_path = arg.trim_prefix("--config=")
			i += 1
		elif arg == "--clip-to-save" and i + 1 < user_args.size():
			clip_to_save = user_args[i + 1]
			i += 2
		elif arg.begins_with("--clip-to-save="):
			clip_to_save = arg.trim_prefix("--clip-to-save=")
			i += 1
		elif arg == "--margin-cells" and i + 1 < user_args.size():
			margin_cells = int(user_args[i + 1])
			i += 2
		elif arg.begins_with("--margin-cells="):
			margin_cells = int(arg.trim_prefix("--margin-cells="))
			i += 1
		elif arg == "--pbf" and i + 1 < user_args.size():
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

	if not print_region_save.is_empty():
		var save_db = ClassDB.instantiate("SQLite")
		save_db.path = print_region_save
		save_db.verbosity_level = 0
		if not save_db.open_db():
			printerr("map_convert: Cannot open save DB for --print-region: %s" % print_region_save)
			get_tree().quit(1)
			return
		save_db.query("PRAGMA query_only = ON;")
		save_db.query("SELECT cell_x, cell_y FROM map_cell WHERE reveal_state > 0;")
		var cell_rows = save_db.query_result
		save_db.close_db()
		var cells: Array[Vector2i] = []
		for r in cell_rows:
			cells.append(Vector2i(int(r["cell_x"]), int(r["cell_y"])))
		var fetcher := MapFetcher.new()
		var reg := fetcher.select_region_for_cells(cells)
		print("region: %s %s %s" % [reg.get("id", ""), reg.get("pbf_url", ""), reg.get("md5_url", "")])
		get_tree().quit(0)
		return

	if pbf_path.is_empty():
		printerr("map_convert: Missing required argument --pbf <file.osm.pbf>")
		get_tree().quit(1)
		return

	if not FileAccess.file_exists(pbf_path):
		printerr("map_convert: PBF file does not exist: %s" % pbf_path)
		get_tree().quit(1)
		return

	var clip_rect: Variant = null
	var coverage_box: Variant = null
	if not clip_to_save.is_empty():
		var save_db = ClassDB.instantiate("SQLite")
		save_db.path = clip_to_save
		save_db.verbosity_level = 0
		if not save_db.open_db():
			printerr("map_convert: Cannot open clip save DB: %s" % clip_to_save)
			get_tree().quit(1)
			return
		save_db.query("PRAGMA query_only = ON;")
		save_db.query("SELECT min(cell_x) AS min_cx, min(cell_y) AS min_cy, max(cell_x) AS max_cx, max(cell_y) AS max_cy FROM map_cell WHERE reveal_state > 0;")
		var bounds_rows = save_db.query_result
		save_db.close_db()
		if bounds_rows.is_empty() or bounds_rows[0].get("min_cx") == null:
			printerr("map_convert: No revealed cells found in save: %s" % clip_to_save)
			get_tree().quit(1)
			return
		var min_cx := int(bounds_rows[0]["min_cx"]) - margin_cells
		var min_cy := int(bounds_rows[0]["min_cy"]) - margin_cells
		var max_cx := int(bounds_rows[0]["max_cx"]) + margin_cells
		var max_cy := int(bounds_rows[0]["max_cy"]) + margin_cells
		var w := max_cx - min_cx + 1
		var h := max_cy - min_cy + 1
		print("clip: %d x %d cells" % [w, h])
		var clip_min_x := float(min_cx) * 256.0
		var clip_max_x := float(max_cx + 1) * 256.0
		var clip_min_y := float(min_cy) * 256.0
		var clip_max_y := float(max_cy + 1) * 256.0
		clip_rect = {"min_x": clip_min_x, "min_y": clip_min_y, "max_x": clip_max_x, "max_y": clip_max_y}
		coverage_box = [min_cx, min_cy, max_cx, max_cy]

	var db_filename: String = ""
	if not place_id.is_empty():
		db_filename = place_id + ".db"
	else:
		var file_base: String = pbf_path.get_file()
		if file_base.ends_with(".osm.pbf"):
			file_base = file_base.trim_suffix(".osm.pbf")
		elif file_base.ends_with(".pbf"):
			file_base = file_base.trim_suffix(".pbf")

		if file_base.ends_with("-latest"):
			file_base = file_base.trim_suffix("-latest")

		db_filename = file_base + ".db"

	var out_db_path: String = out_dir.path_join(db_filename)

	print("=== Tenth Spring Map Converter ===")
	print("Input PBF: ", pbf_path)
	print("Output DB: ", out_db_path)
	if not place_id.is_empty():
		print("Place ID: ", place_id)

	var conv := RegionConverter.new()
	var res := conv.convert(pbf_path, out_db_path, clip_rect, coverage_box, place_id, config_path)

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
