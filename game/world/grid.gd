extends RefCounted

# Web-Mercator Grid Projection & Ground-Distance Utilities (F42 / EPSG:3857)
# Single canonical coordinate projection for Tenth Spring.
# No class_name is used so the file loads cleanly without godot --import.

const WM_R: float = 6378137.0
const EARTH_MEAN_R: float = 6371008.8
const CELL_WM: float = 256.0
const TILE_WM: float = 16.0
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
