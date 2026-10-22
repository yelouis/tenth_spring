extends Control

# town_map_canvas.gd — Procedural cartographic canvas for Town Map

func _draw() -> void:
	var w := size.x
	var h := size.y
	var map_rect := Rect2(60, 70, w - 120, h - 140)

	# 1. Ocean Background
	draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.11, 0.16))

	# 2. Map border
	draw_rect(map_rect, Color(0.12, 0.15, 0.22))
	draw_rect(map_rect, Color(0.25, 0.35, 0.45, 0.5), false, 2.0)

	# 3. Coordinate Grid lines
	var grid_color := Color(0.20, 0.28, 0.38, 0.3)
	for i in range(1, 6):
		var gx := map_rect.position.x + map_rect.size.x * (float(i) / 6.0)
		draw_line(Vector2(gx, map_rect.position.y), Vector2(gx, map_rect.position.y + map_rect.size.y), grid_color, 1.0)
	for j in range(1, 5):
		var gy := map_rect.position.y + map_rect.size.y * (float(j) / 5.0)
		draw_line(Vector2(map_rect.position.x, gy), Vector2(map_rect.position.x + map_rect.size.x, gy), grid_color, 1.0)

	# 4. Stylized Contiguous USA Land Silhouette (Original simplified polygon)
	# Approximating US boundary in normalized rect coordinates (0..1)
	var us_shape := PackedVector2Array([
		Vector2(0.05, 0.08), # NW Washington State (Olympic Pen)
		Vector2(0.04, 0.28), # Oregon coast
		Vector2(0.08, 0.55), # California coast
		Vector2(0.14, 0.72), # SoCal
		Vector2(0.20, 0.72), # Arizona border
		Vector2(0.35, 0.78), # New Mexico / Texas border
		Vector2(0.42, 0.92), # Texas South (Rio Grande mouth)
		Vector2(0.48, 0.85), # Texas Gulf coast
		Vector2(0.60, 0.84), # Louisiana Gulf coast
		Vector2(0.72, 0.82), # Florida Panhandle
		Vector2(0.82, 0.95), # South Florida (Key West)
		Vector2(0.84, 0.80), # Florida Atlantic coast
		Vector2(0.80, 0.65), # Georgia / Carolinas coast
		Vector2(0.86, 0.48), # Chesapeake / Delmarva
		Vector2(0.90, 0.38), # New Jersey / New York coast
		Vector2(0.96, 0.22), # Maine East coast
		Vector2(0.92, 0.12), # Maine North
		Vector2(0.82, 0.20), # St Lawrence border
		Vector2(0.74, 0.22), # Lake Ontario
		Vector2(0.68, 0.24), # Lake Erie
		Vector2(0.64, 0.16), # Lake Huron / Michigan
		Vector2(0.56, 0.15), # Lake Superior / Minnesota NW Angle
		Vector2(0.40, 0.12), # North Dakota 49th parallel
		Vector2(0.20, 0.10), # Montana 49th parallel
		Vector2(0.05, 0.08)  # Return to NW Washington
	])

	var land_points := PackedVector2Array()
	for p in us_shape:
		land_points.append(Vector2(
			map_rect.position.x + p.x * map_rect.size.x,
			map_rect.position.y + p.y * map_rect.size.y
		))

	# Draw land fill & coastline outline
	draw_colored_polygon(land_points, Color(0.16, 0.22, 0.26))
	draw_polyline(land_points, Color(0.35, 0.50, 0.60, 0.8), 2.5)

	# Great lakes interior accents
	draw_circle(Vector2(map_rect.position.x + 0.60 * map_rect.size.x, map_rect.position.y + 0.18 * map_rect.size.y), 14.0, Color(0.08, 0.11, 0.16))
	draw_circle(Vector2(map_rect.position.x + 0.66 * map_rect.size.x, map_rect.position.y + 0.22 * map_rect.size.y), 10.0, Color(0.08, 0.11, 0.16))
