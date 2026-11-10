class_name DistortionFields
extends RefCounted

## game/world/distortion_fields.gd — Deterministic Distortion Field Scheduler & Placement (Slice 3, Item 46)
## Contract: docs/implementation_plan_world_generation_slice3.md §5,
##           docs/design_encounters_and_haunted_zones.md §3a

const Grid := preload("res://world/grid.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

const DEFAULT_INTERVAL_DAYS: int = 3
const ESCALATED_INTERVAL_DAYS: int = 2
const DURATION_MINUTES: int = 1440 # 24 game hours = 1 game day
const FIELD_SIZE_CELLS: int = 5 # 5x5 cells (radius 2 around center)
const FIELD_HALF_EXTENT: int = 2
const RADIUS_MILES: float = 10.0
const METERS_PER_MILE: float = 1609.344
const FOREIGN_SHARE: float = 0.40
const ULTRA_BEAST_SHARE: float = 0.02 # 1 in 50 of foreign draws
const SALT_FIELD_PICK: int = 301

static func is_field_day(game_epoch_minutes: int, anchors_held: int = 0) -> bool:
	var interval_days: int = ESCALATED_INTERVAL_DAYS if anchors_held >= 6 else DEFAULT_INTERVAL_DAYS
	var game_day: int = floori(float(maxi(0, game_epoch_minutes)) / float(DURATION_MINUTES))
	return posmod(game_day, interval_days) == 0

static func hours_left_in_field(game_epoch_minutes: int) -> int:
	var min_in_day: int = posmod(maxi(0, game_epoch_minutes), DURATION_MINUTES)
	return maxi(1, ceili(float(DURATION_MINUTES - min_in_day) / 60.0))

static func format_chip_text(hours_left: int) -> String:
	return "Distortion Field — %d h left" % maxi(1, hours_left)

static func is_cell_in_field(cell: Vector2i, field_center: Vector2i) -> bool:
	return absi(cell.x - field_center.x) <= FIELD_HALF_EXTENT and absi(cell.y - field_center.y) <= FIELD_HALF_EXTENT

static func get_field_cells(field_center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-FIELD_HALF_EXTENT, FIELD_HALF_EXTENT + 1):
		for dx in range(-FIELD_HALF_EXTENT, FIELD_HALF_EXTENT + 1):
			out.append(Vector2i(field_center.x + dx, field_center.y + dy))
	return out

static func select_field_center(
	world_seed: int,
	game_epoch_minutes: int,
	player_cell: Vector2i,
	candidate_cells: Array[Vector2i],
	max_radius_miles: float = RADIUS_MILES
) -> Variant:
	if candidate_cells.is_empty():
		return null
	var p_ll: Vector2 = Grid.cell_center_latlon(player_cell)
	var max_dist_m: float = max_radius_miles * METERS_PER_MILE
	var valid: Array[Vector2i] = []
	var seen: Dictionary = {}
	for c in candidate_cells:
		if seen.has(c):
			continue
		seen[c] = true
		var c_ll: Vector2 = Grid.cell_center_latlon(c)
		var d_m: float = Grid.ground_distance_m(p_ll.x, p_ll.y, c_ll.x, c_ll.y)
		if d_m <= max_dist_m + 1e-3:
			valid.append(c)

	if valid.is_empty():
		return null

	valid.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	var game_day: int = floori(float(maxi(0, game_epoch_minutes)) / float(DURATION_MINUTES))
	var h: int = TileSynth2.fnv1a32([world_seed, game_day, SALT_FIELD_PICK])
	var idx: int = posmod(h, valid.size())
	return valid[idx]

static func get_active_field(
	world_seed: int,
	game_epoch_minutes: int,
	current_place_id: String,
	player_cell: Vector2i,
	revealed_grass_cells: Array[Vector2i],
	anchors_held: int = 0
) -> Dictionary:
	if current_place_id.is_empty() or current_place_id == "home":
		return {"active": false}
	if not is_field_day(game_epoch_minutes, anchors_held):
		return {"active": false}

	var center_var: Variant = select_field_center(world_seed, game_epoch_minutes, player_cell, revealed_grass_cells)
	if center_var == null:
		return {"active": false}
	var center: Vector2i = center_var
	var h_left: int = hours_left_in_field(game_epoch_minutes)
	return {
		"active": true,
		"center": center,
		"min_cell": Vector2i(center.x - FIELD_HALF_EXTENT, center.y - FIELD_HALF_EXTENT),
		"max_cell": Vector2i(center.x + FIELD_HALF_EXTENT, center.y + FIELD_HALF_EXTENT),
		"hours_left": h_left,
		"chip_text": format_chip_text(h_left),
		"place_id": current_place_id,
	}
