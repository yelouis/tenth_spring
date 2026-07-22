extends Node

# Relocation Manager for Session-Start Handoff
# Calculates survivor spawn tile from companion bodyFix and determines stranded status.

const METERS_PER_DEGREE: float = 111000.0

var is_stranded: bool = false
var distance_from_home_meters: float = 0.0
var current_spawn_tile: Vector2i = Vector2i.ZERO

func calculate_relocation(peer_id: String) -> Dictionary:
	var peer = DB.get_sync_peer(peer_id)
	var body_lat = float(peer.get("last_body_lat", 0.0))
	var body_lon = float(peer.get("last_body_lon", 0.0))

	var home = DB._base_state_store
	var home_x = float(home.get("home_cell_x", 0))
	var home_y = float(home.get("home_cell_y", 0))

	# Compute coarse distance in meters from home
	var delta_x = (body_lon - home_x) * METERS_PER_DEGREE
	var delta_y = (body_lat - home_y) * METERS_PER_DEGREE
	distance_from_home_meters = sqrt(delta_x * delta_x + delta_y * delta_y)

	var home_fuzz = Config.home_fuzz_meters
	is_stranded = distance_from_home_meters > home_fuzz

	current_spawn_tile = Vector2i(int(floor(body_lon * 1000.0)), int(floor(body_lat * 1000.0)))

	return {
		"spawn_tile": current_spawn_tile,
		"distance_from_home_meters": distance_from_home_meters,
		"is_stranded": is_stranded
	}
