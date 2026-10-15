extends Node

# Relocation Manager for Session-Start Handoff
# Calculates survivor spawn tile from companion bodyFix, converts coordinates to unified meters,
# handles nearest-revealed-tile snapping, minimal-circle reveal for unknown areas,
# and out-of-contact fallback.

const Grid := preload("res://world/grid.gd")

var is_stranded: bool = false
var is_out_of_contact: bool = false
var distance_from_home_meters: float = 0.0
var current_spawn_tile: Vector2i = Vector2i.ZERO

static func distance_to_home_m(body_lat: float, body_lon: float, home_cell: Vector2i) -> float:
	var c = Grid.cell_center_latlon(home_cell)
	return Grid.ground_distance_m(body_lat, body_lon, c.x, c.y)

func calculate_relocation(peer_id: String, peer_reachable: bool = true) -> Dictionary:
	var peer = DB.get_sync_peer(peer_id)
	var body_lat = float(peer.get("last_body_lat", 0.0))
	var body_lon = float(peer.get("last_body_lon", 0.0))
	var body_ts = int(peer.get("last_body_ts", 0))

	is_out_of_contact = not peer_reachable or body_ts == 0

	var home = DB.get_base_state()
	var home_cell_x = int(home.get("home_cell_x", 0))
	var home_cell_y = int(home.get("home_cell_y", 0))
	var home_cell = Vector2i(home_cell_x, home_cell_y)

	if body_lat == 0.0 and body_lon == 0.0:
		# Fallback to home safehouse tile if no position has ever synced
		current_spawn_tile = Vector2i(home_cell_x * 16 + 8, home_cell_y * 16 + 8)
		distance_from_home_meters = 0.0
		is_stranded = false
		is_out_of_contact = true
		return {
			"spawn_tile": current_spawn_tile,
			"distance_from_home_meters": 0.0,
			"is_stranded": false,
			"is_out_of_contact": true
		}

	distance_from_home_meters = distance_to_home_m(body_lat, body_lon, home_cell)
	var base_access = Config.base_access_meters
	is_stranded = distance_from_home_meters > base_access

	var spawn_cell = Grid.latlon_to_cell(body_lat, body_lon)
	current_spawn_tile = Grid.latlon_to_tile(body_lat, body_lon)

	# Minimal-circle reveal for unknown areas so survivor has ground to stand on
	var target_cell = DB.get_map_cell(spawn_cell.x, spawn_cell.y)
	if target_cell.is_empty() or target_cell.get("reveal_state", 0) == 0:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				DB.upsert_map_cell(spawn_cell.x + dx, spawn_cell.y + dy, 1)

	# Nearest-revealed-tile snapping to player profile
	DB.set_player_tile(current_spawn_tile.x, current_spawn_tile.y)

	return {
		"spawn_tile": current_spawn_tile,
		"spawn_cell": spawn_cell,
		"distance_from_home_meters": distance_from_home_meters,
		"is_stranded": is_stranded,
		"is_out_of_contact": is_out_of_contact
	}
