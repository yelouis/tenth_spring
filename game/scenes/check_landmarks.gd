extends Node

# check_landmarks.gd — Verify landmark placement and gilding on a place store (Item 24 / F54)
# Contract: docs/implementation_plan_world_generation_slice2.md §11.1 & docs/agent_execution_guide.md §4

const MapStore := preload("res://world/region_import/map_store.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")
const Grid := preload("res://world/grid.gd")

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	var store_path := ""
	var place_id := ""

	var i := 0
	while i < user_args.size():
		var arg := user_args[i]
		if arg == "--store" and i + 1 < user_args.size():
			store_path = user_args[i + 1]
			i += 2
		elif arg.begins_with("--store="):
			store_path = arg.trim_prefix("--store=")
			i += 1
		elif arg == "--place" and i + 1 < user_args.size():
			place_id = user_args[i + 1]
			i += 2
		elif arg.begins_with("--place="):
			place_id = arg.trim_prefix("--place=")
			i += 1
		else:
			i += 1

	if store_path.is_empty() or place_id.is_empty():
		printerr("check_landmarks: Missing required arguments --store and --place")
		get_tree().quit(1)
		return

	var places: Array = RevealEngine.load_places()
	var target_place: Dictionary = {}
	for p in places:
		if str(p.get("id", "")) == place_id:
			target_place = p
			break

	if target_place.is_empty():
		printerr("check_landmarks: Place '%s' not found in famous_places.json" % place_id)
		get_tree().quit(1)
		return

	var store := MapStore.new(store_path)
	if not store.open_store(false):
		printerr("check_landmarks: Failed to open map store '%s': %s" % [store_path, store.last_error])
		get_tree().quit(1)
		return

	var interiors: Array = target_place.get("interiors", [])
	# Group interiors by cell in famous_places.json order
	var landmarks_by_cell: Dictionary = {}
	var interior_list: Array[Dictionary] = []

	for interior in interiors:
		var i_id: String = str(interior.get("id", ""))
		var i_name: String = str(interior.get("name", ""))
		var door: Dictionary = interior.get("door", {})
		var d_lat := float(door.get("lat", 0.0))
		var d_lon := float(door.get("lon", 0.0))
		var wm: Vector2 = Grid.latlon_to_wm(d_lat, d_lon)
		var cell: Vector2i = Grid.wm_to_cell(wm.x, wm.y)
		var lm_dict := {
			"id": i_id,
			"name": i_name,
			"door_wm": wm,
			"cell": cell
		}
		if not landmarks_by_cell.has(cell):
			landmarks_by_cell[cell] = []
		landmarks_by_cell[cell].append(lm_dict)
		interior_list.append(lm_dict)

	for lm_item in interior_list:
		var door_cell: Vector2i = lm_item["cell"]
		var lm_id: String = lm_item["id"]
		var lm_name: String = lm_item["name"]
		var placed := 0
		var gold_tiles := 0
		var has_sign := 0

		# Synthesize the door's cell and its 8 neighbours (§11.1a step 3)
		for ny_off in range(-1, 2):
			for nx_off in range(-1, 2):
				var cx: int = door_cell.x + nx_off
				var cy: int = door_cell.y + ny_off

				var area: Dictionary = {}
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var offset := Vector2i(dx, dy)
						var nx := cx + dx
						var ny := cy + dy
						var n_cell := Vector2i(nx, ny)
						area[offset] = {
							"polys": store.get_features_poly(nx, ny),
							"lines": store.get_features_line(nx, ny),
							"places": store.get_place_nodes(nx, ny),
							"covered": store.covers_cell(nx, ny),
							"sea": store.get_cell_sea(nx, ny),
							"landmarks": [lm_item] if n_cell == door_cell else []
						}

				var res := TileSynth2.synthesize_cell(cx, cy, area)
				var stats: Dictionary = res.get("stats", {})
				var ids_placed: Array = stats.get("landmark_ids_placed", [])
				if lm_id in ids_placed:
					placed = 1

				var tiles: PackedByteArray = res.get("tiles", PackedByteArray())
				for idx in range(0, tiles.size(), 3):
					var cls: int = tiles[idx]
					var v: int = tiles[idx + 1]
					if (cls == TileSynth2.TILE_ROOF or cls == TileSynth2.TILE_WALL or cls == TileSynth2.TILE_DOOR) and (v & 32) != 0:
						gold_tiles += 1

				var signs: PackedStringArray = res.get("signs", PackedStringArray())
				for s in signs:
					if s == lm_name:
						has_sign = 1
						break

		print("LANDMARK %s placed=%d gold_tiles=%d sign=%d" % [
			lm_id,
			placed,
			gold_tiles,
			has_sign
		])

	store.close()
	get_tree().quit(0)
