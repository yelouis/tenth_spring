extends Node

# Relocation Manager for Session-Start Handoff
# Calculates survivor spawn tile from companion bodyFix, converts coordinates to unified meters,
# handles nearest-revealed-tile snapping, minimal-circle reveal for unknown areas,
# and out-of-contact fallback.

const METERS_PER_DEGREE: float = 111000.0
const CELL_METERS: float = 256.0
const TILE_METERS: float = 16.0

var is_stranded: bool = false
var is_out_of_contact: bool = false
var distance_from_home_meters: float = 0.0
var current_spawn_tile: Vector2i = Vector2i.ZERO

func calculate_relocation(peer_id: String, peer_reachable: bool = true) -> Dictionary:
	var peer = DB.get_sync_peer(peer_id)
	var body_lat = float(peer.get("last_body_lat", 0.0))
	var body_lon = float(peer.get("last_body_lon", 0.0))
	var body_ts = int(peer.get("last_body_ts", 0))

	is_out_of_contact = not peer_reachable or body_ts == 0

	var home = DB.get_base_state()
	var home_cell_x = int(home.get("home_cell_x", 0))
	var home_cell_y = int(home.get("home_cell_y", 0))

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

	# Unified coordinate transformation to meters
	var body_lat_meters = body_lat * METERS_PER_DEGREE
	var body_lon_meters = body_lon * METERS_PER_DEGREE * cos(deg_to_rad(body_lat))

	var home_center_lon_meters = (float(home_cell_x) + 0.5) * CELL_METERS
	var home_center_lat_meters = (float(home_cell_y) + 0.5) * CELL_METERS

	var delta_x = body_lon_meters - home_center_lon_meters
	var delta_y = body_lat_meters - home_center_lat_meters
	distance_from_home_meters = sqrt(delta_x * delta_x + delta_y * delta_y)

	var base_access = Config.base_access_meters
	is_stranded = distance_from_home_meters > base_access

	var spawn_cell_x = int(floor(body_lon_meters / CELL_METERS))
	var spawn_cell_y = int(floor(body_lat_meters / CELL_METERS))
	current_spawn_tile = Vector2i(
		int(floor(body_lon_meters / TILE_METERS)),
		int(floor(body_lat_meters / TILE_METERS))
	)

	# Minimal-circle reveal for unknown areas so survivor has ground to stand on
	var target_cell = DB.get_map_cell(spawn_cell_x, spawn_cell_y)
	if target_cell.is_empty() or target_cell.get("reveal_state", 0) == 0:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				DB.upsert_map_cell(spawn_cell_x + dx, spawn_cell_y + dy, 1)

	# Nearest-revealed-tile snapping to player profile
	DB.set_player_tile(current_spawn_tile.x, current_spawn_tile.y)

	return {
		"spawn_tile": current_spawn_tile,
		"spawn_cell": Vector2i(spawn_cell_x, spawn_cell_y),
		"distance_from_home_meters": distance_from_home_meters,
		"is_stranded": is_stranded,
		"is_out_of_contact": is_out_of_contact
	}
