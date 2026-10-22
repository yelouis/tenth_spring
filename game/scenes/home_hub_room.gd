extends Control

# home_hub_room.gd — Procedural original pixel/vector safehouse room art

func _draw() -> void:
	var w := size.x
	var h := size.y

	# 1. Upper Wall (warm muted lavender-taupe wallpaper)
	var wall_h := h * 0.55
	draw_rect(Rect2(0, 0, w, wall_h), Color(0.22, 0.20, 0.25))

	# Wallpaper subtle vertical stripes
	var stripe_w := 24.0
	var x := 0.0
	while x < w:
		draw_rect(Rect2(x, 0, 1.0, wall_h), Color(0.18, 0.16, 0.22, 0.6))
		x += stripe_w

	# Baseboard / Wainscoting
	draw_rect(Rect2(0, wall_h - 16.0, w, 16.0), Color(0.15, 0.12, 0.10))
	draw_rect(Rect2(0, wall_h - 18.0, w, 2.0), Color(0.28, 0.24, 0.20))

	# 2. Wooden Floor (warm planked floor)
	var floor_h := h - wall_h
	draw_rect(Rect2(0, wall_h, w, floor_h), Color(0.28, 0.18, 0.12))

	var plank_h := 32.0
	var y := wall_h
	var row := 0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.18, 0.10, 0.06), 2.0)
		# Staggered vertical plank joints
		var offset := 80.0 if (row % 2 == 1) else 0.0
		var jx := offset
		while jx < w:
			draw_line(Vector2(jx, y), Vector2(jx, y + plank_h), Color(0.18, 0.10, 0.06, 0.7), 1.5)
			jx += 160.0
		y += plank_h
		row += 1

	# 3. Window on Upper Wall (Left side)
	var win_rect := Rect2(60, 40, 140, 180)
	draw_rect(win_rect.grow(8), Color(0.15, 0.12, 0.10)) # Outer frame
	draw_rect(win_rect, Color(0.08, 0.10, 0.18)) # Night sky
	# Stars / outside distortion particles
	draw_circle(Vector2(90, 80), 2.0, Color(0.9, 0.9, 0.6, 0.8))
	draw_circle(Vector2(140, 60), 2.5, Color(0.6, 0.8, 1.0, 0.9))
	draw_circle(Vector2(170, 120), 1.5, Color(0.9, 0.9, 0.9, 0.7))
	# Window crossbars
	draw_line(Vector2(win_rect.position.x + win_rect.size.x * 0.5, win_rect.position.y), Vector2(win_rect.position.x + win_rect.size.x * 0.5, win_rect.position.y + win_rect.size.y), Color(0.25, 0.20, 0.16), 4.0)
	draw_line(Vector2(win_rect.position.x, win_rect.position.y + win_rect.size.y * 0.5), Vector2(win_rect.position.x + win_rect.size.x, win_rect.position.y + win_rect.size.y * 0.5), Color(0.25, 0.20, 0.16), 4.0)

	# 4. Cozy Bed (Far Left, Resting)
	var bed_rect := Rect2(40, wall_h - 40, 180, 140)
	# Headboard
	draw_rect(Rect2(40, wall_h - 80, 180, 40), Color(0.20, 0.14, 0.10))
	# Mattress & Blanket
	draw_rect(bed_rect, Color(0.35, 0.45, 0.55)) # Blue quilt
	draw_rect(Rect2(50, wall_h - 35, 70, 30), Color(0.85, 0.85, 0.80)) # Pillow
	# Blanket fold
	draw_rect(Rect2(40, wall_h + 10, 180, 20), Color(0.28, 0.38, 0.48))

	# 5. Desk & PC Terminal (Middle-Left)
	var desk_rect := Rect2(260, wall_h - 30, 160, 110)
	draw_rect(desk_rect, Color(0.22, 0.16, 0.12)) # Wood desk top
	# Desk legs
	draw_rect(Rect2(270, wall_h + 80, 12, 60), Color(0.16, 0.12, 0.08))
	draw_rect(Rect2(398, wall_h + 80, 12, 60), Color(0.16, 0.12, 0.08))
	# PC Monitor
	draw_rect(Rect2(310, wall_h - 90, 60, 50), Color(0.12, 0.12, 0.14)) # Monitor frame
	draw_rect(Rect2(314, wall_h - 86, 52, 42), Color(0.10, 0.35, 0.30)) # Green CRT screen
	draw_rect(Rect2(334, wall_h - 40, 12, 10), Color(0.18, 0.18, 0.20)) # Stand

	# 6. Distortion Rift / Portal Alcove (Center Right)
	var rift_center := Vector2(w * 0.55, wall_h - 30)
	# Glowing aura
	draw_circle(rift_center, 65.0, Color(0.35, 0.15, 0.50, 0.3))
	draw_circle(rift_center, 45.0, Color(0.20, 0.60, 0.70, 0.4))
	draw_circle(rift_center, 25.0, Color(0.80, 0.95, 1.00, 0.7))
	# Frame arch around the rift
	var arch_points := PackedVector2Array([
		Vector2(rift_center.x - 55, wall_h + 40),
		Vector2(rift_center.x - 55, wall_h - 90),
		Vector2(rift_center.x, wall_h - 130),
		Vector2(rift_center.x + 55, wall_h - 90),
		Vector2(rift_center.x + 55, wall_h + 40)
	])
	draw_polyline(arch_points, Color(0.4, 0.3, 0.2), 6.0)

	# 7. Safehouse Rug
	var rug_center := Vector2(w * 0.5, h * 0.8)
	draw_circle(rug_center, 90.0, Color(0.40, 0.22, 0.22, 0.8))
	draw_circle(rug_center, 75.0, Color(0.50, 0.28, 0.28, 0.9))
