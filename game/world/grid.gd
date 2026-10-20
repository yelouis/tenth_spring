extends RefCounted

# Web-Mercator Grid Projection & Ground-Distance Utilities (F42 / EPSG:3857)
# Single canonical coordinate projection for Tenth Spring.
# No class_name is used so the file loads cleanly without godot --import.

const WM_R: float = 6378137.0
const EARTH_MEAN_R: float = 6371008.8
const CELL_WM: float = 256.0
const TILE_WM: float = 8.0
const MAX_LAT: float = 85.05112878

static func latlon_to_wm(lat: float, lon: float) -> Vector2:
	var clamped_lat := clampf(lat, -MAX_LAT, MAX_LAT)
	var x := WM_R * deg_to_rad(lon)
	var y := WM_R * log(tan(PI / 4.0 + deg_to_rad(clamped_lat) / 2.0))
	return Vector2(x, y)

static func wm_to_latlon(p: Vector2) -> Vector2:
	var lat := rad_to_deg(2.0 * atan(exp(p.y / WM_R)) - PI / 2.0)
	var lon := rad_to_deg(p.x / WM_R)
	return Vector2(lat, lon)

static func latlon_to_cell(lat: float, lon: float) -> Vector2i:
	var wm := latlon_to_wm(lat, lon)
	return Vector2i(int(floor(wm.x / CELL_WM)), int(floor(wm.y / CELL_WM)))

static func latlon_to_tile(lat: float, lon: float) -> Vector2i:
	var wm := latlon_to_wm(lat, lon)
	return Vector2i(int(floor(wm.x / TILE_WM)), int(floor(wm.y / TILE_WM)))

static func cell_center_latlon(cell: Vector2i) -> Vector2:
	var cx := (float(cell.x) + 0.5) * CELL_WM
	var cy := (float(cell.y) + 0.5) * CELL_WM
	return wm_to_latlon(Vector2(cx, cy))

static func ground_distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var phi1 := deg_to_rad(lat1)
	var phi2 := deg_to_rad(lat2)
	var delta_phi := deg_to_rad(lat2 - lat1)
	var delta_lambda := deg_to_rad(lon2 - lon1)

	var a := sin(delta_phi / 2.0) * sin(delta_phi / 2.0) + cos(phi1) * cos(phi2) * sin(delta_lambda / 2.0) * sin(delta_lambda / 2.0)
	var c := 2.0 * atan2(sqrt(a), sqrt(maxf(0.0, 1.0 - a)))
	return EARTH_MEAN_R * c

static func cells_within_ground_radius(lat: float, lon: float, radius_m: float = 60.0) -> Array[Vector2i]:
	var primary := latlon_to_cell(lat, lon)
	var wm_p := latlon_to_wm(lat, lon)
	var result: Array[Vector2i] = []

	if radius_m >= 0.0:
		result.append(primary)

	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var cell := Vector2i(primary.x + dx, primary.y + dy)
			var min_x := float(cell.x) * CELL_WM
			var max_x := float(cell.x + 1) * CELL_WM
			var min_y := float(cell.y) * CELL_WM
			var max_y := float(cell.y + 1) * CELL_WM
			var closest_x := clampf(wm_p.x, min_x, max_x)
			var closest_y := clampf(wm_p.y, min_y, max_y)
			var closest_latlon := wm_to_latlon(Vector2(closest_x, closest_y))
			var dist := ground_distance_m(lat, lon, closest_latlon.x, closest_latlon.y)
			if dist <= radius_m:
				result.append(cell)

	return result

