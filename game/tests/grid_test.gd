extends Node

# Unit test for Web-Mercator Grid Projection & Relocation Math (F42)

const Grid := preload("res://world/grid.gd")
const RelocationManager := preload("res://scripts/relocation_manager.gd")

func run_test() -> bool:
	# (a) Falsifying — north stays north
	var lat := 47.6000
	var lon := -122.3300
	var step_deg := rad_to_deg(100.0 / Grid.EARTH_MEAN_R)
	var initial_cell := Grid.latlon_to_cell(lat, lon)
	for i in range(21):
		var c := Grid.latlon_to_cell(lat, lon)
		if c.x != initial_cell.x:
			push_error("grid_test (a): cell.x changed from %d to %d at step %d" % [initial_cell.x, c.x, i])
			return false
		lat += step_deg

	# (b) Known values
	var wm_origin := Grid.latlon_to_wm(0.0, 0.0)
	if absf(wm_origin.x) > 1e-6 or absf(wm_origin.y) > 1e-6:
		push_error("grid_test (b): latlon_to_wm(0, 0) expected (0, 0) ± 1e-6, got %s" % str(wm_origin))
		return false

	var wm_180 := Grid.latlon_to_wm(0.0, 180.0)
	if absf(wm_180.x - 20037508.0) > 0.001:
		push_error("grid_test (b): latlon_to_wm(0, 180).x expected 20037508.0 ± 0.001 (float32 Vector2), got %f" % wm_180.x)
		return false

	var c_pos := Grid.latlon_to_cell(0.0005, 0.0005)
	if c_pos != Vector2i(0, 0):
		push_error("grid_test (b): latlon_to_cell(0.0005, 0.0005) expected (0, 0), got %s" % str(c_pos))
		return false

	var c_neg := Grid.latlon_to_cell(-0.0005, -0.0005)
	if c_neg != Vector2i(-1, -1):
		push_error("grid_test (b): latlon_to_cell(-0.0005, -0.0005) expected (-1, -1), got %s" % str(c_neg))
		return false

	# (c) Round trip within float32 Vector2 precision (< 1e-5 deg ≈ 1m) for 5 sample points
	var sample_points := [
		Vector2(-33.86, 151.21),
		Vector2(64.15, -21.94),
		Vector2(0.0, 0.0),
		Vector2(47.6, -122.33),
		Vector2(10.0, -10.0)
	]
	for pt in sample_points:
		var wm := Grid.latlon_to_wm(pt.x, pt.y)
		var back := Grid.wm_to_latlon(wm)
		if absf(back.x - pt.x) > 1e-4 or absf(back.y - pt.y) > 1e-4:
			push_error("grid_test (c): round trip mismatch for %s: got %s" % [str(pt), str(back)])
			return false

	# (d) Ground distance
	var d := Grid.ground_distance_m(47.6, -122.33, 47.6 + 300.0 / 111194.93, -122.33)
	if absf(d - 300.0) > 0.5:
		push_error("grid_test (d): ground distance expected 300 ± 0.5, got %f" % d)
		return false

	# (e) Cell ground size at Seattle
	var seattle_cell := Grid.latlon_to_cell(47.6000, -122.3300)
	var c1 := Grid.cell_center_latlon(seattle_cell)
	var c2 := Grid.cell_center_latlon(Vector2i(seattle_cell.x + 1, seattle_cell.y))
	var cell_dist := Grid.ground_distance_m(c1.x, c1.y, c2.x, c2.y)
	if absf(cell_dist - 172.6) > 1.0:
		push_error("grid_test (e): cell ground size expected 172.6 ± 1.0, got %f" % cell_dist)
		return false

	# (f) Falsifying — stranded: body 300m due north of cell centre
	var home_cell := Grid.latlon_to_cell(47.6000, -122.3300)
	var home_center := Grid.cell_center_latlon(home_cell)
	var dlat_300m := rad_to_deg(300.0 / Grid.EARTH_MEAN_R)
	var body_lat := home_center.x + dlat_300m
	var body_lon := home_center.y
	var dist_home := RelocationManager.distance_to_home_m(body_lat, body_lon, home_cell)
	if absf(dist_home - 300.0) > 2.0:
		push_error("grid_test (f): distance_to_home_m expected 300 ± 2, got %f" % dist_home)
		return false
	if dist_home > 500.0:
		push_error("grid_test (f): player should not be stranded at 500m (measured %f)" % dist_home)
		return false

	# (g) Shared cross-language golden vectors (tools/testdata/grid_vectors.json, §1.1)
	var vec_path := ProjectSettings.globalize_path("res://").path_join("../tools/testdata/grid_vectors.json").simplify_path()
	if not FileAccess.file_exists(vec_path):
		push_error("grid_test (g): grid_vectors.json not found at %s" % vec_path)
		return false
	var vec_txt := FileAccess.get_file_as_string(vec_path)
	var vec_arr: Variant = JSON.parse_string(vec_txt)
	if not (vec_arr is Array) or (vec_arr as Array).size() < 40:
		push_error("grid_test (g): expected >= 40 vectors in grid_vectors.json")
		return false
	for item in vec_arr:
		var v: Dictionary = item
		var v_name: String = str(v.get("name", ""))
		var v_lat: float = float(v.get("lat", 0.0))
		var v_lon: float = float(v.get("lon", 0.0))
		var exp_wmx: float = float(v.get("wm_x", 0.0))
		var exp_wmy: float = float(v.get("wm_y", 0.0))
		var exp_cx: int = int(v.get("cell_x", 0))
		var exp_cy: int = int(v.get("cell_y", 0))

		var got_cell := Grid.latlon_to_cell(v_lat, v_lon)
		if got_cell.x != exp_cx or got_cell.y != exp_cy:
			push_error("grid_test (g): cell mismatch on %s: expected (%d, %d), got (%d, %d)" % [
				v_name, exp_cx, exp_cy, got_cell.x, got_cell.y
			])
			return false

		var got_wm := Grid.latlon_to_wm(v_lat, v_lon)
		var tol_x := maxf(1e-3, absf(exp_wmx) * 2e-6)
		var tol_y := maxf(1e-3, absf(exp_wmy) * 2e-6)
		if absf(got_wm.x - exp_wmx) > tol_x or absf(got_wm.y - exp_wmy) > tol_y:
			push_error("grid_test (g): wm mismatch on %s: expected (%f, %f), got (%f, %f)" % [
				v_name, exp_wmx, exp_wmy, got_wm.x, got_wm.y
			])
			return false

	return true
