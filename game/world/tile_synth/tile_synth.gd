class_name TileSynth
extends RefCounted

const MapStore := preload("res://world/region_import/map_store.gd")

## TileSynth — Deterministic Geometry to Tile Rasterizer (Plan §6)
##
## Converts cell-local vector geometry (polygons, lines) into a 16x16 byte grid
## of tile IDs per 256m cell. Completely deterministic across platforms.

const CELL_TILES := 16
const BUFFER_SIZE := CELL_TILES * CELL_TILES # 256 bytes

# Tile Palette IDs (plan §6.1)
const TILE_VOID := 0       # Flat #0d1119 (unmapped or void)
const TILE_TERRAIN := 1    # Muted green/grey grass/ground
const TILE_ROAD := 2       # Asphalt grey, min 1 tile wide
const TILE_BUILDING := 3   # Structure silhouette, min 2x2 tiles
const TILE_PARK := 4       # Vibrant meadow green vegetation
const TILE_WATER := 5      # Deep navy water

# Exact Palette Colours (plan §6.1, §7.1)
const PALETTE := {
	TILE_VOID: Color("#0d1119"),
	TILE_TERRAIN: Color("#475e46"),
	TILE_ROAD: Color("#5a5d64"),
	TILE_BUILDING: Color("#2e3238"),
	TILE_PARK: Color("#3e7d44"),
	TILE_WATER: Color("#1f385c"),
}

## Synthesize a 16x16 tile buffer for a cell from regional map store features.
## Output is a 256-byte PackedByteArray representing row-major [y * 16 + x] tile IDs.
static func synthesize_cell(cell_x: int, cell_y: int, features: Dictionary, world_seed: int = 0) -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.resize(BUFFER_SIZE)

	# Base pass (plan §6.2): Fill entire 16x16 buffer with Terrain Fill (Tile 1)
	buffer.fill(TILE_TERRAIN)

	# Extract features
	var polys: Array = features.get("polys", features.get("features_poly", []))
	var lines: Array = features.get("lines", features.get("features_line", []))

	# Polygon pass (plan §6.2):
	# 1. Rasterize water bodies (Tile 5)
	# 2. Rasterize parks/leisure (Tile 4)
	# 3. Rasterize building footprints (Tile 3, min 2x2 tiles)
	var water_polys: Array = []
	var park_polys: Array = []
	var building_polys: Array = []

	for p in polys:
		var kind: String = ""
		var geom = null
		if p is Dictionary:
			kind = str(p.get("kind", ""))
			geom = p.get("geom_rings", null)
		if geom == null:
			continue

		var rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r in geom:
				if r is PackedVector2Array:
					rings.append(r)

		if rings.is_empty():
			continue

		if kind == "water":
			water_polys.append(rings)
		elif kind in ["park", "garden", "playground", "pitch", "nature_reserve", "cemetery"]:
			park_polys.append(rings)
		elif kind == "building":
			building_polys.append(rings)

	# 1. Rasterize water bodies
	for rings in water_polys:
		_rasterize_polygon(buffer, rings, TILE_WATER)

	# 2. Rasterize parks / vegetation
	for rings in park_polys:
		_rasterize_polygon(buffer, rings, TILE_PARK)

	# 3. Rasterize buildings with minimum 2x2 footprint
	for rings in building_polys:
		_rasterize_building(buffer, rings)

	# Line pass (plan §6.2):
	# Rasterize highways and paths (Tile 2), drawing lines with Bresenham's algorithm at width >= 1 tile
	for l in lines:
		var geom = null
		if l is Dictionary:
			geom = l.get("geom_pts", null)
		if geom == null:
			continue

		var pts := PackedVector2Array()
		if geom is PackedByteArray:
			pts = MapStore.unpack_pts(geom)
		elif geom is PackedVector2Array:
			pts = geom
		elif geom is Array:
			pts = PackedVector2Array(geom)

		if pts.size() < 2:
			continue

		for i in range(pts.size() - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var x0 := clampi(int(floor(p0.x)), 0, CELL_TILES - 1)
			var y0 := clampi(int(floor(p0.y)), 0, CELL_TILES - 1)
			var x1 := clampi(int(floor(p1.x)), 0, CELL_TILES - 1)
			var y1 := clampi(int(floor(p1.y)), 0, CELL_TILES - 1)
			_draw_line_bresenham(buffer, x0, y0, x1, y1, TILE_ROAD)

	return buffer

static func _rasterize_polygon(buffer: PackedByteArray, rings: Array[PackedVector2Array], tile_id: int) -> void:
	if rings.is_empty() or rings[0].size() < 3:
		return
	var outer := rings[0]
	var holes := rings.slice(1)

	for y in CELL_TILES:
		for x in CELL_TILES:
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.is_point_in_polygon(pt, outer):
				var in_hole := false
				for h in holes:
					if Geometry2D.is_point_in_polygon(pt, h):
						in_hole = true
						break
				if not in_hole:
					buffer[y * CELL_TILES + x] = tile_id

static func _rasterize_building(buffer: PackedByteArray, rings: Array[PackedVector2Array]) -> void:
	if rings.is_empty() or rings[0].size() < 3:
		return
	var outer := rings[0]
	var holes := rings.slice(1)

	var covered_tiles: Array[Vector2i] = []
	for y in CELL_TILES:
		for x in CELL_TILES:
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.is_point_in_polygon(pt, outer):
				var in_hole := false
				for h in holes:
					if Geometry2D.is_point_in_polygon(pt, h):
						in_hole = true
						break
				if not in_hole:
					covered_tiles.append(Vector2i(x, y))

	# Minimum 2x2 tiles constraint (plan §6.1, §6.2)
	if covered_tiles.is_empty():
		var min_p := outer[0]
		var max_p := outer[0]
		for p in outer:
			min_p.x = minf(min_p.x, p.x)
			min_p.y = minf(min_p.y, p.y)
			max_p.x = maxf(max_p.x, p.x)
			max_p.y = maxf(max_p.y, p.y)
		var mid := (min_p + max_p) * 0.5
		var cx := clampi(int(floor(mid.x)), 0, CELL_TILES - 2)
		var cy := clampi(int(floor(mid.y)), 0, CELL_TILES - 2)
		for dy in 2:
			for dx in 2:
				buffer[(cy + dy) * CELL_TILES + (cx + dx)] = TILE_BUILDING
	else:
		var min_x := covered_tiles[0].x
		var max_x := covered_tiles[0].x
		var min_y := covered_tiles[0].y
		var max_y := covered_tiles[0].y
		for t in covered_tiles:
			min_x = mini(min_x, t.x)
			max_x = maxi(max_x, t.x)
			min_y = mini(min_y, t.y)
			max_y = maxi(max_y, t.y)

		var need_expand := false
		if max_x - min_x < 1:
			need_expand = true
			if max_x < CELL_TILES - 1:
				max_x += 1
			else:
				min_x -= 1
		if max_y - min_y < 1:
			need_expand = true
			if max_y < CELL_TILES - 1:
				max_y += 1
			else:
				min_y -= 1

		if need_expand:
			for y in range(min_y, max_y + 1):
				for x in range(min_x, max_x + 1):
					buffer[y * CELL_TILES + x] = TILE_BUILDING
		else:
			for t in covered_tiles:
				buffer[t.y * CELL_TILES + t.x] = TILE_BUILDING

static func _draw_line_bresenham(buffer: PackedByteArray, x0: int, y0: int, x1: int, y1: int, tile_id: int) -> void:
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy

	while true:
		if x0 >= 0 and x0 < CELL_TILES and y0 >= 0 and y0 < CELL_TILES:
			buffer[y0 * CELL_TILES + x0] = tile_id
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
