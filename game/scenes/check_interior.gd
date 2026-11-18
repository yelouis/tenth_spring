extends Node

# game/scenes/check_interior.gd — Headless Interior Compiler & I1..I6 Checker Scene (Item 57)
# Contract: docs/implementation_plan_dc_trial.md §11.3 C & docs/agent_execution_guide.md §5

const InteriorMap := preload("res://world/interior/interior_map.gd")
const InteriorCheck := preload("res://world/interior/interior_check.gd")

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var target_id := ""
	var target_file := ""

	var i := 0
	while i < user_args.size():
		var arg := str(user_args[i]).strip_edges()
		if arg == "--interior" and i + 1 < user_args.size():
			target_id = str(user_args[i + 1]).strip_edges()
			i += 2
		elif arg.begins_with("--interior="):
			target_id = arg.trim_prefix("--interior=").strip_edges()
			i += 1
		elif arg == "--file" and i + 1 < user_args.size():
			target_file = str(user_args[i + 1]).strip_edges()
			i += 2
		elif arg.begins_with("--file="):
			target_file = arg.trim_prefix("--file=").strip_edges()
			i += 1
		else:
			i += 1

	var paths: Array[String] = []
	if not target_file.is_empty():
		if not FileAccess.file_exists(target_file):
			printerr("[FAIL] interior file not found: %s" % target_file)
			get_tree().quit(2)
			return
		paths.append(target_file)
	elif not target_id.is_empty():
		var resolved := InteriorMap.resolve_interior_path(target_id)
		if resolved.is_empty():
			printerr("[FAIL] unknown interior %s" % target_id)
			get_tree().quit(2)
			return
		paths.append(resolved)
	else:
		paths = InteriorMap.list_dc_interior_paths()
		if paths.is_empty():
			printerr("[FAIL] no DC interior JSON files found in %s" % InteriorMap.DC_INTERIOR_DIR)
			get_tree().quit(2)
			return

	var any_failed := false
	for p in paths:
		var doc := InteriorMap.load_json(p)
		if doc.is_empty():
			print("INTERIOR %s floors=0 stamps=0 art_pending=0 FAIL I1" % p)
			any_failed = true
			continue
		var res := InteriorCheck.compile_and_check(doc)
		print(InteriorCheck.format_summary(res))
		if not bool(res.get("ok", false)):
			any_failed = true
			var rerrs: Dictionary = res.get("rule_errors", {})
			for r_key in ["I1", "I2", "I3", "I4", "I5", "I6"]:
				for msg in (rerrs.get(r_key, []) as Array):
					printerr("[FAIL] %s %s: %s" % [str(res.get("id", p)), r_key, str(msg)])

	get_tree().quit(1 if any_failed else 0)
