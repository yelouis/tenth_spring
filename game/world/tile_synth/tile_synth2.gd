class_name TileSynth2
extends RefCounted

## TileSynth2 — Walking-scale tile synthesizer for Slice 2 ("Pokemon Look")
## Contract: docs/implementation_plan_world_generation_slice2.md §3, §4

const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")

# Tile Vocabulary (§3)
const TILE_VOID := 0
const TILE_GRASS := 1
const TILE_TALL_GRASS := 2
const TILE_TREE := 3
const TILE_WATER := 4
const TILE_SAND := 5
const TILE_MARSH := 6
const TILE_PATH := 7
const TILE_ROAD := 8
const TILE_RAIL := 9
const TILE_BRIDGE := 10
const TILE_PLAZA := 11
const TILE_ROOF := 12
const TILE_WALL := 13
const TILE_DOOR := 14
const TILE_FENCE := 15
const TILE_FLOWERS := 16
const TILE_GRAVE := 17
const TILE_SIGN := 18
const TILE_CROP := 19

# Grid Dimensions
const CELL_TILES := 32
const MARGIN_TILES := 4
const WORK_SIZE := 40 # 32 + 2 * 4
const WORK_CELL_START := 4
const WORK_CELL_END := 36 # exclusive
const OUTPUT_BUFFER_SIZE := 32 * 32 * 3 # 3072 bytes

# Salts (§3)
const SALT_TREE_SCATTER := 1
const SALT_FLOWERS := 2
const SALT_GRASS_VARIANT := 3
const SALT_ROAD_CRACKS := 4
const SALT_DOOR_ROOF := 5
const SALT_TREE_VARIANT := 6
const SALT_NOISE_LATTICE := 7
const SALT_FALLBACK_SKIP := 8

# Forbidden building placement tile classes (§4.2)
const FORBIDDEN_BUILDING_TILES: Array[int] = [
	TILE_WATER, TILE_ROAD, TILE_PATH, TILE_RAIL, TILE_BRIDGE,
	TILE_PLAZA, TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_GRAVE, TILE_FENCE, TILE_VOID
]
const FORBIDDEN_SOUTH_RING_TILES: Array[int] = [
	TILE_WATER, TILE_RAIL, TILE_BRIDGE,
	TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_GRAVE, TILE_FENCE, TILE_VOID
]

## Portable FNV-1a 32-bit hash (§3)
static func fnv1a32(ints: Array) -> int:
	var h: int = 2166136261
	for val in ints:
		var uval: int = int(val) & 0xFFFFFFFF
		for i in 4:
			var b: int = (uval >> (i * 8)) & 0xFF
			h = (h ^ b) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
	return h

## Uniform pseudorandom float u in [0, 1) over global tile coords (§3)
static func u_rand(gx: int, gy: int, world_seed: int, salt: int) -> float:
	return float(fnv1a32([gx, gy, world_seed, salt])) / 4294967296.0

## Value noise v in [0, 1) with 4-tile lattice spacing (§3)
static func value_noise(gx: int, gy: int, world_seed: int) -> float:
	var i: int = floori(float(gx) / 4.0)
	var j: int = floori(float(gy) / 4.0)
	var fx: float = (float(posmod(gx, 4)) + 0.5) / 4.0
	var fy: float = (float(posmod(gy, 4)) + 0.5) / 4.0
	var l00: float = float(fnv1a32([i, j, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l10: float = float(fnv1a32([i + 1, j, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l01: float = float(fnv1a32([i, j + 1, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	var l11: float = float(fnv1a32([i + 1, j + 1, world_seed, SALT_NOISE_LATTICE])) / 4294967296.0
	return l00 * (1.0 - fx) * (1.0 - fy) + l10 * fx * (1.0 - fy) + l01 * (1.0 - fx) * fy + l11 * fx * fy

## Quantize Vector2 WM coordinates for stable vertex indexing
static func _quantize_wm(v: Vector2) -> Vector2i:
	return Vector2i(int(round(v.x * 100.0)), int(round(v.y * 100.0)))

## 4-connected supercover line rasterization (§4.1 step 4)
static func supercover_line(c0: int, r0: int, c1: int, r1: int) -> Array[Vector2i]:
	var pts: Array[Vector2i] = []
	var dx: int = absi(c1 - c0)
	var dy: int = absi(r1 - r0)
	var x: int = c0
	var y: int = r0
	var n: int = 1 + dx + dy
	var x_inc: int = 1 if c1 > c0 else (-1 if c1 < c0 else 0)
	var y_inc: int = 1 if r1 > r0 else (-1 if r1 < r0 else 0)
	var error: int = dx - dy
	dx *= 2
	dy *= 2

	for _i in range(n):
		pts.append(Vector2i(x, y))
		if error > 0:
			x += x_inc
			error -= dy
		elif error < 0:
			y += y_inc
			error += dx
		else:
			x += x_inc
			error -= dy
			pts.append(Vector2i(x, y))
			y += y_inc
			error += dx
	return pts

## Point in polygon (even-odd rule)
static func point_in_polygon(px: float, py: float, outer_ring: PackedVector2Array, holes: Array[PackedVector2Array]) -> bool:
	if not _point_in_ring(px, py, outer_ring):
		return false
	for hole in holes:
		if _point_in_ring(px, py, hole):
			return false
	return true

static func _point_in_ring(px: float, py: float, ring: PackedVector2Array) -> bool:
	var n: int = ring.size()
	if n < 3:
		return false
	var inside := false
	for i in n:
		var j := (i + 1) % n
		var p0 := ring[i]
		var p1 := ring[j]
		if ((p0.y > py) != (p1.y > py)) and (px < (p1.x - p0.x) * (py - p0.y) / (p1.y - p0.y) + p0.x):
			inside = not inside
	return inside

## Point in rings (outer ring and hole list)
static func _point_in_rings(pt: Vector2, rings: Array[PackedVector2Array]) -> bool:
	if rings.is_empty():
		return false
	var holes: Array[PackedVector2Array] = []
	for i in range(1, rings.size()):
		holes.append(rings[i])
	return point_in_polygon(pt.x, pt.y, rings[0], holes)

## Shoelace area in polygon coordinate units
static func _shoelace_area(pts: PackedVector2Array) -> float:
	var n: int = pts.size()
	if n < 3:
		return 0.0
	var a := 0.0
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return absf(a) * 0.5

## Category priority for signs (§4.4)
static func _sign_priority(cat: String) -> int:
	match cat:
		"landmark":
			return 6
		"haunted":
			return 5
		"civic":
			return 4
		"medical":
			return 3
		"park":
			return 2
		_:
			return 1

## Determine road width in tiles from subkind (§2.2)
static func get_road_width(subkind: String) -> int:
	var base := subkind.trim_suffix(":bridge")
	match base:
		"motorway", "trunk":
			return 4
		"primary", "secondary":
			return 3
		"tertiary", "residential", "unclassified", "living_street", "road":
			return 2
		"service":
			return 1
		_:
			if base.ends_with("_link"):
				return 2
			return 2

## Determine waterway width in tiles from subkind (§2.2)
static func get_waterway_width(subkind: String) -> int:
	var base := subkind.trim_suffix(":bridge")
	match base:
		"river":
			return 3
		"canal":
			return 2
		"stream", "ditch", "drain":
			return 1
		_:
			return 1

## Synthesize a cell's 32x32 tiles from a 3x3 neighbourhood (§4)
static func synthesize_cell(cx: int, cy: int, area: Dictionary, world_seed: int = 0) -> Dictionary:
	var total_tiles: int = WORK_SIZE * WORK_SIZE
	var grid_class := PackedByteArray()
	grid_class.resize(total_tiles)
	grid_class.fill(TILE_VOID)

	var grid_variant := PackedByteArray()
	grid_variant.resize(total_tiles)
	grid_variant.fill(0)

	var is_park := PackedByteArray()
	is_park.resize(total_tiles)
	is_park.fill(0)

	var is_forest := PackedByteArray()
	is_forest.resize(total_tiles)
	is_forest.fill(0)

	var is_cemetery := PackedByteArray()
	is_cemetery.resize(total_tiles)
	is_cemetery.fill(0)

	var is_residential := PackedByteArray()
	is_residential.resize(total_tiles)
	is_residential.fill(0)

	var water_from_waterway := PackedByteArray()
	water_from_waterway.resize(total_tiles)
	water_from_waterway.fill(0)

	var water_from_poly_or_sea := PackedByteArray()
	water_from_poly_or_sea.resize(total_tiles)
	water_from_poly_or_sea.fill(0)

	# -------------------------------------------------------------
	# 1. Base Layer (§4.1 step 1)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		var dy: int = 1 if r < 4 else (-1 if r >= 36 else 0)
		for c in WORK_SIZE:
			var dx: int = -1 if c < 4 else (1 if c >= 36 else 0)
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var idx: int = r * WORK_SIZE + c
			if n_data.get("covered", false):
				grid_class[idx] = TILE_GRASS
			else:
				grid_class[idx] = TILE_VOID

	# -------------------------------------------------------------
	# 2. Sea & Coast Layer (§4.1 step 2)
	# -------------------------------------------------------------
	var coast_segments: Array = []
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var lines: Array = n_data.get("lines", [])
			for line in lines:
				if line.get("kind", "") != "coastline":
					continue
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue
				var origin := Vector2(float(cx + dx) * Grid.CELL_WM, float(cy + dy) * Grid.CELL_WM)
				for i in range(pts.size() - 1):
					var a := origin + pts[i] * MapStore.GEOM_UNIT_WM
					var b := origin + pts[i + 1] * MapStore.GEOM_UNIT_WM
					if (b - a).length_squared() < 1e-6:
						continue
					coast_segments.append([a, b])
					incoming[_quantize_wm(b)] = a
					outgoing[_quantize_wm(a)] = b

	for r in WORK_SIZE:
		var dy: int = 1 if r < 4 else (-1 if r >= 36 else 0)
		for c in WORK_SIZE:
			var dx: int = -1 if c < 4 else (1 if c >= 36 else 0)
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var sea_val: int = int(n_data.get("sea", 0))
			var idx: int = r * WORK_SIZE + c

			if sea_val == 1:
				grid_class[idx] = TILE_WATER
				water_from_poly_or_sea[idx] = 1
			elif sea_val == 2 and not coast_segments.is_empty():
				var gx: int = cx * 32 + (c - 4)
				var gy: int = cy * 32 + (35 - r)
				var p_wm := Vector2((float(gx) + 0.5) * Grid.TILE_WM, (float(gy) + 0.5) * Grid.TILE_WM)

				var min_dist_sq := INF
				var nearest_seg = null
				var nearest_t := 0.0
				for seg in coast_segments:
					var sa: Vector2 = seg[0]
					var sb: Vector2 = seg[1]
					var ab := sb - sa
					var len_sq := ab.length_squared()
					var t := 0.0
					if len_sq > 1e-6:
						t = clampf((p_wm - sa).dot(ab) / len_sq, 0.0, 1.0)
					var proj := sa + ab * t
					var dist_sq := (p_wm - proj).length_squared()
					if dist_sq < min_dist_sq:
						min_dist_sq = dist_sq
						nearest_seg = seg
						nearest_t = t

				if nearest_seg != null:
					var na: Vector2 = nearest_seg[0]
					var nb: Vector2 = nearest_seg[1]
					var is_sea := false
					if nearest_t > 1e-4 and nearest_t < 1.0 - 1e-4:
						is_sea = (nb - na).cross(p_wm - na) < 0.0
					else:
						var v: Vector2 = na if nearest_t <= 1e-4 else nb
						var vk := _quantize_wm(v)
						if incoming.has(vk) and outgoing.has(vk):
							var u_pt: Vector2 = incoming[vk]
							var w_pt: Vector2 = outgoing[vk]
							is_sea = (w_pt - u_pt).cross(p_wm - v) < 0.0
						else:
							is_sea = (nb - na).cross(p_wm - na) < 0.0
					if is_sea:
						grid_class[idx] = TILE_WATER
						water_from_poly_or_sea[idx] = 1

	# -------------------------------------------------------------
	# 3. Land Cover Polygons (§4.1 step 3)
	# -------------------------------------------------------------
	# Group polygons by land cover type to paint in exact plan order
	var polys_by_order: Dictionary = {
		"farmland": [],
		"scrub": [],
		"forest": [],
		"park": [],
		"cemetery": [],
		"sand": [],
		"wetland": [],
		"parking": [],
		"water": [],
		"residential": []
	}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var polys: Array = n_data.get("polys", [])
			for poly in polys:
				var kind: String = poly.get("kind", "")
				if not polys_by_order.has(kind):
					continue
				var geom = poly.get("geom_rings", null)
				if geom == null:
					continue
				var rings: Array[PackedVector2Array] = []
				if geom is PackedByteArray:
					rings = MapStore.unpack_rings(geom)
				elif geom is Array:
					for r_item in geom:
						if r_item is PackedVector2Array:
							rings.append(r_item)
				if rings.is_empty():
					continue

				# Map vertices to working grid coordinates (§4.0)
				var mapped_rings: Array[PackedVector2Array] = []
				for ring in rings:
					var m_ring := PackedVector2Array()
					for pt in ring:
						var m_col: float = 4.0 + 2.0 * pt.x + 32.0 * float(dx)
						var m_row: float = 36.0 - 2.0 * pt.y - 32.0 * float(dy)
						m_ring.append(Vector2(m_col, m_row))
					mapped_rings.append(m_ring)
				polys_by_order[kind].append(mapped_rings)

	# Paint in exact order
	var order_keys := ["farmland", "scrub", "forest", "park", "cemetery", "sand", "wetland", "parking", "water", "residential"]
	for kind in order_keys:
		var list: Array = polys_by_order[kind]
		for rings in list:
			var outer: PackedVector2Array = rings[0]
			var holes: Array[PackedVector2Array] = []
			for h_i in range(1, rings.size()):
				holes.append(rings[h_i])

			var min_c := 39
			var max_c := 0
			var min_r := 39
			var max_r := 0
			for pt in outer:
				min_c = mini(min_c, floori(pt.x))
				max_c = maxi(max_c, ceili(pt.x))
				min_r = mini(min_r, floori(pt.y))
				max_r = maxi(max_r, ceili(pt.y))

			min_c = clampi(min_c, 0, 39)
			max_c = clampi(max_c, 0, 39)
			min_r = clampi(min_r, 0, 39)
			max_r = clampi(max_r, 0, 39)

			for r in range(min_r, max_r + 1):
				var py := float(r) + 0.5
				for c in range(min_c, max_c + 1):
					var px := float(c) + 0.5
					if not point_in_polygon(px, py, outer, holes):
						continue
					var idx := r * WORK_SIZE + c
					var gx := cx * 32 + (c - 4)
					var gy := cy * 32 + (35 - r)

					match kind:
						"farmland":
							grid_class[idx] = TILE_CROP if posmod(gy, 2) == 0 else TILE_GRASS
						"scrub":
							grid_class[idx] = TILE_TALL_GRASS
						"forest":
							grid_class[idx] = TILE_TREE
							is_forest[idx] = 1
						"park":
							grid_class[idx] = TILE_GRASS
							is_park[idx] = 1
						"cemetery":
							grid_class[idx] = TILE_GRASS
							is_cemetery[idx] = 1
						"sand":
							grid_class[idx] = TILE_SAND
						"wetland":
							grid_class[idx] = TILE_MARSH
						"parking":
							grid_class[idx] = TILE_PLAZA
						"water":
							grid_class[idx] = TILE_WATER
							water_from_poly_or_sea[idx] = 1
						"residential":
							is_residential[idx] = 1

	# -------------------------------------------------------------
	# 4. Lines & Crossings (§4.1 step 4)
	# -------------------------------------------------------------
	var line_groups: Dictionary = {
		"waterway": [],
		"rail": [],
		"road": [],
		"path": []
	}

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_data: Dictionary = area.get(Vector2i(dx, dy), {})
			var lines: Array = n_data.get("lines", [])
			for line in lines:
				var kind: String = line.get("kind", "")
				if not line_groups.has(kind):
					continue
				var subkind: String = line.get("subkind", "")
				var geom = line.get("geom_pts", null)
				if geom == null:
					continue
				var pts: PackedVector2Array = MapStore.unpack_pts(geom) if geom is PackedByteArray else PackedVector2Array(geom)
				if pts.size() < 2:
					continue

				var mapped_pts := PackedVector2Array()
				for pt in pts:
					var m_col: float = 4.0 + 2.0 * pt.x + 32.0 * float(dx)
					var m_row: float = 36.0 - 2.0 * pt.y - 32.0 * float(dy)
					mapped_pts.append(Vector2(m_col, m_row))
				line_groups[kind].append({
					"subkind": subkind,
					"pts": mapped_pts
				})

	# Paint lines in order: waterway, rail, road, path
	var line_order := ["waterway", "rail", "road", "path"]
	for kind in line_order:
		var list: Array = line_groups[kind]
		for item in list:
			var subkind: String = item["subkind"]
			var pts: PackedVector2Array = item["pts"]
			var is_bridge: bool = subkind.ends_with(":bridge")

			var width: int = 1
			var target_class: int = TILE_PATH
			match kind:
				"waterway":
					width = get_waterway_width(subkind)
					target_class = TILE_WATER
				"rail":
					width = 2
					target_class = TILE_RAIL
				"road":
					width = get_road_width(subkind)
					target_class = TILE_ROAD if width >= 3 else TILE_PATH
				"path":
					width = 1
					target_class = TILE_PATH

			var lo: int = (width - 1) / 2
			var hi: int = width - 1 - lo

			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var c0: int = floori(p0.x)
				var r0: int = floori(p0.y)
				var c1: int = floori(p1.x)
				var r1: int = floori(p1.y)

				var supercover := supercover_line(c0, r0, c1, r1)
				for center in supercover:
					for br in range(center.y - lo, center.y + hi + 1):
						if br < 0 or br >= WORK_SIZE:
							continue
						for bc in range(center.x - lo, center.x + hi + 1):
							if bc < 0 or bc >= WORK_SIZE:
								continue
							var idx := br * WORK_SIZE + bc
							var current_class: int = grid_class[idx]

							if kind == "waterway":
								grid_class[idx] = TILE_WATER
								water_from_waterway[idx] = 1
							elif kind == "rail":
								if current_class == TILE_WATER or current_class == TILE_BRIDGE:
									if is_bridge:
										grid_class[idx] = TILE_BRIDGE
								else:
									grid_class[idx] = TILE_RAIL
							elif kind in ["road", "path"]:
								if current_class == TILE_WATER or current_class == TILE_BRIDGE:
									if is_bridge:
										grid_class[idx] = TILE_BRIDGE
									elif water_from_waterway[idx] == 1 and water_from_poly_or_sea[idx] == 0:
										# Culvert: overwrites waterway line
										grid_class[idx] = target_class
								else:
									# Road overwrites rail (level crossing) and terrain
									grid_class[idx] = target_class

	# -------------------------------------------------------------
	# 5. Buildings & Fallback Houses (§4.1 step 5, §4.2, §4.3)
	# -------------------------------------------------------------
	var placed_buildings: Array[Dictionary] = []
	var all_doors: Array[Vector2i] = []

	# 5a. Real Buildings anchored in the centre cell
	var center_polys: Array = area.get(Vector2i.ZERO, {}).get("polys", [])
	var building_candidates: Array[Dictionary] = []

	for poly in center_polys:
		if poly.get("kind", "") != "building":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				rings.append(PackedVector2Array(r_item))
		if rings.is_empty() or rings[0].size() < 3:
			continue

		var outer_ring: PackedVector2Array = rings[0]
		var A: float = _shoelace_area(outer_ring) * 256.0
		if A < 60.0:
			continue # skip sheds / garages

		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for pt in outer_ring:
			min_x = minf(min_x, pt.x)
			max_x = maxf(max_x, pt.x)
			min_y = minf(min_y, pt.y)
			max_y = maxf(max_y, pt.y)

		var w_t: float = (max_x - min_x) * 2.0
		var h_t: float = (max_y - min_y) * 2.0

		var subk: String = poly.get("subkind", "")
		var w := 4
		var h := 3
		var roof_rows := 2
		var wall_rows := 1
		var template_name := "house_s"

		if A < 400.0:
			w = 4
			h = 3
			roof_rows = 2
			wall_rows = 1
			template_name = "house_s"
		elif A < 2000.0 or subk in ["apartments", "dormitory"]:
			w = 5
			h = 4
			roof_rows = 2
			wall_rows = 2
			template_name = "house_m"
		else:
			w = clampi(int(round(w_t)), 6, 24)
			h = clampi(int(round(h_t)), 5, 14)
			roof_rows = h - 2
			wall_rows = 2
			template_name = "block_l"

		var bx_c := (min_x + max_x) * 0.5
		var by_c := (min_y + max_y) * 0.5
		var cc := 4.0 + 2.0 * bx_c
		var rc := 36.0 - 2.0 * by_c
		var col0 := clampi(int(round(cc - float(w) / 2.0)), 5, 35 - w)
		var row0 := clampi(int(round(rc - float(h) / 2.0)), 5, 35 - h)

		var gx0 := cx * 32 + (col0 - 4)
		var gy0 := cy * 32 + (35 - row0)

		var door_cols: Array[int] = []
		if template_name == "house_s":
			var d_col: int = 1 if u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) < 0.5 else 2
			door_cols = [d_col]
		elif template_name == "house_m":
			door_cols = [2]
		else:
			for off in [2, 10, 18]:
				if off < w - 1:
					door_cols.append(off)

		var roof_color := 7
		if subk in ["house", "detached", "residential", "semidetached_house", "bungalow", "terrace", "cabin", "farm", "hut", "apartments", "dormitory"] or (subk == "yes" and template_name in ["house_s", "house_m"]):
			roof_color = floori(u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) * 4.0)
		elif subk in ["retail", "commercial", "supermarket", "shop", "kiosk"]:
			roof_color = 4
		elif subk in ["school", "college", "university", "kindergarten", "public", "civic", "government", "library", "townhall", "fire_station", "police"]:
			roof_color = 5
		elif subk in ["hospital", "clinic"]:
			roof_color = 6
		elif subk in ["church", "chapel", "cathedral", "temple", "mosque", "synagogue", "religious"]:
			roof_color = 3
		else:
			roof_color = 7

		building_candidates.append({
			"area": A,
			"col0": col0,
			"row0": row0,
			"w": w,
			"h": h,
			"roof_rows": roof_rows,
			"door_cols": door_cols,
			"roof_color": roof_color,
			"template": template_name,
			"subkind": subk,
			"bx_c": bx_c,
			"by_c": by_c,
			"rings": rings
		})

	# Order: descending A, then ascending row0, then ascending col0
	building_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["area"], b["area"]):
			return a["area"] > b["area"]
		if a["row0"] != b["row0"]:
			return a["row0"] < b["row0"]
		return a["col0"] < b["col0"]
	)

	for b in building_candidates:
		var col0: int = b["col0"]
		var row0: int = b["row0"]
		var w: int = b["w"]
		var h: int = b["h"]

		var skip := false
		for r in range(row0 - 1, row0 + h + 1):
			for c in range(col0 - 1, col0 + w + 1):
				if r < 0 or r >= WORK_SIZE or c < 0 or c >= WORK_SIZE:
					skip = true
					break
				var idx: int = r * WORK_SIZE + c
				var cur_cls: int = grid_class[idx]
				var in_template: bool = (r >= row0 and r < row0 + h and c >= col0 and c < col0 + w)
				if in_template:
					if cur_cls in FORBIDDEN_BUILDING_TILES:
						skip = true
						break
				else:
					if r == row0 + h:
						if cur_cls in FORBIDDEN_SOUTH_RING_TILES:
							skip = true
							break
					else:
						if cur_cls in FORBIDDEN_BUILDING_TILES:
							skip = true
							break
			if skip:
				break

		if skip:
			continue

		# Paint building
		for tr in h:
			var r: int = row0 + tr
			for tc in w:
				var c: int = col0 + tc
				var idx: int = r * WORK_SIZE + c
				if tr < b["roof_rows"]:
					grid_class[idx] = TILE_ROOF
					grid_variant[idx] = b["roof_color"]
				else:
					if tr == h - 1 and tc in b["door_cols"]:
						grid_class[idx] = TILE_DOOR
						grid_variant[idx] = b["roof_color"]
						all_doors.append(Vector2i(c, r))
					else:
						grid_class[idx] = TILE_WALL
						var has_window: bool = (tc % 2 != 0)
						grid_variant[idx] = b["roof_color"] + (8 if has_window else 0)

		# Door paths
		for d_col in b["door_cols"]:
			var door_r: int = row0 + h - 1
			var door_c: int = col0 + d_col
			var walk_path: Array[Vector2i] = []
			var reached_connector := false
			for step in range(1, 7):
				var wr: int = door_r + step
				var wc: int = door_c
				if wr > 35:
					break
				var idx: int = wr * WORK_SIZE + wc
				var cur_cls: int = grid_class[idx]
				if cur_cls in [TILE_PATH, TILE_ROAD, TILE_PLAZA]:
					reached_connector = true
					break
				if cur_cls in [TILE_WATER, TILE_RAIL, TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_FENCE, TILE_BRIDGE, TILE_VOID]:
					break
				walk_path.append(Vector2i(wc, wr))
			if reached_connector:
				for pt in walk_path:
					var p_idx: int = pt.y * WORK_SIZE + pt.x
					grid_class[p_idx] = TILE_PATH
					grid_variant[p_idx] = 0

		placed_buildings.append(b)

	# 5b. Fallback Houses (§4.3)
	for poly in center_polys:
		var p_kind: String = poly.get("kind", "")
		if p_kind != "residential" and p_kind != "commercial":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var f_rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			f_rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				f_rings.append(PackedVector2Array(r_item))
		if f_rings.is_empty():
			continue

		var has_real_building := false
		for b in building_candidates:
			if _point_in_rings(Vector2(b["bx_c"], b["by_c"]), f_rings):
				has_real_building = true
				break
		if has_real_building:
			continue

		# Candidate house_s on global lattice: posmod(gx, 7) == 0 and posmod(gy, 6) == 0
		for r in range(4, 36):
			for c in range(4, 36):
				var gx: int = cx * 32 + (c - 4)
				var gy: int = cy * 32 + (35 - r)
				if posmod(gx, 7) == 0 and posmod(gy, 6) == 0:
					var col0: int = clampi(c, 5, 31)
					var row0: int = clampi(r, 5, 32)
					# Template centre tile in store units (house_s is 4x3 -> col0 + 2, row0 + 1)
					var tc_su := Vector2((float(col0 + 2) + 0.5 - 4.0) * 0.5, (36.0 - (float(row0 + 1) + 0.5)) * 0.5)
					if not _point_in_rings(tc_su, f_rings):
						continue
					if u_rand(gx, gy, world_seed, SALT_FALLBACK_SKIP) >= 0.70:
						continue

					# Skip check
					var skip := false
					for br in range(row0 - 1, row0 + 4):
						for bc in range(col0 - 1, col0 + 5):
							if br < 0 or br >= WORK_SIZE or bc < 0 or bc >= WORK_SIZE:
								skip = true
								break
							var idx: int = br * WORK_SIZE + bc
							var cur_cls: int = grid_class[idx]
							var in_temp: bool = (br >= row0 and br < row0 + 3 and bc >= col0 and bc < col0 + 4)
							if in_temp:
								if cur_cls in FORBIDDEN_BUILDING_TILES:
									skip = true
									break
							else:
								if br == row0 + 3:
									if cur_cls in FORBIDDEN_SOUTH_RING_TILES:
										skip = true
										break
								else:
									if cur_cls in FORBIDDEN_BUILDING_TILES:
										skip = true
										break
						if skip:
							break
					if skip:
						continue

					var gx0: int = cx * 32 + (col0 - 4)
					var gy0: int = cy * 32 + (35 - row0)
					var roof_color: int = 4 if p_kind == "commercial" else floori(u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) * 4.0)
					var door_col: int = 1 if u_rand(gx0, gy0, world_seed, SALT_DOOR_ROOF) < 0.5 else 2

					for tr in 3:
						var cur_r: int = row0 + tr
						for tc in 4:
							var cur_c: int = col0 + tc
							var idx: int = cur_r * WORK_SIZE + cur_c
							if tr < 2:
								grid_class[idx] = TILE_ROOF
								grid_variant[idx] = roof_color
							else:
								if tc == door_col:
									grid_class[idx] = TILE_DOOR
									grid_variant[idx] = roof_color
									all_doors.append(Vector2i(cur_c, cur_r))
								else:
									grid_class[idx] = TILE_WALL
									var has_window: bool = (tc % 2 != 0)
									grid_variant[idx] = roof_color + (8 if has_window else 0)

					# Door path
					var door_r: int = row0 + 2
					var door_c: int = col0 + door_col
					var walk_path: Array[Vector2i] = []
					var reached_connector := false
					for step in range(1, 7):
						var wr: int = door_r + step
						var wc: int = door_c
						if wr > 35:
							break
						var idx: int = wr * WORK_SIZE + wc
						var cur_cls: int = grid_class[idx]
						if cur_cls in [TILE_PATH, TILE_ROAD, TILE_PLAZA]:
							reached_connector = true
							break
						if cur_cls in [TILE_WATER, TILE_RAIL, TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_FENCE, TILE_BRIDGE, TILE_VOID]:
							break
						walk_path.append(Vector2i(wc, wr))
					if reached_connector:
						for pt in walk_path:
							var p_idx: int = pt.y * WORK_SIZE + pt.x
							grid_class[p_idx] = TILE_PATH
							grid_variant[p_idx] = 0

					placed_buildings.append({
						"col0": col0,
						"row0": row0,
						"w": 4,
						"h": 3,
						"door_cols": [door_col]
					})

	# -------------------------------------------------------------
	# 6. Parks & Forests (§4.1 step 6)
	# -------------------------------------------------------------
	# 6a. Parks: GRASS -> TALL_GRASS where value_noise > 0.55
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_park[idx] == 1 and grid_class[idx] == TILE_GRASS:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)
				if value_noise(gx, gy, world_seed) > 0.55:
					grid_class[idx] = TILE_TALL_GRASS

	# 6b. Park edge tiles become TREE if GRASS or TALL_GRASS
	var park_trees := PackedByteArray()
	park_trees.resize(total_tiles)
	park_trees.fill(0)

	var cardinal_offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_park[idx] == 1 and (grid_class[idx] == TILE_GRASS or grid_class[idx] == TILE_TALL_GRASS):
				var is_edge := false
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE:
						is_edge = true
						break
					var n_idx: int = nr * WORK_SIZE + nc
					if is_park[n_idx] == 0 and grid_class[n_idx] != TILE_WATER:
						is_edge = true
						break
				if is_edge:
					park_trees[idx] = 1

	for idx in total_tiles:
		if park_trees[idx] == 1:
			grid_class[idx] = TILE_TREE

	# 6c. Forests: tiles at least 2 tiles from forest edge become TALL_GRASS where v > 0.70
	var forest_edges := PackedByteArray()
	forest_edges.resize(total_tiles)
	forest_edges.fill(0)

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_forest[idx] == 1:
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE or is_forest[nr * WORK_SIZE + nc] == 0:
						forest_edges[idx] = 1
						break

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_forest[idx] == 1 and grid_class[idx] == TILE_TREE:
				# Must be >= 2 tiles from edge: neither itself nor any of its 8-neighbours is a forest edge
				var near_edge := false
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						var nc: int = c + dc
						var nr: int = r + dr
						if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE:
							near_edge = true
							break
						if forest_edges[nr * WORK_SIZE + nc] == 1:
							near_edge = true
							break
					if near_edge:
						break
				if not near_edge:
					var gx := cx * 32 + (c - 4)
					var gy := cy * 32 + (35 - r)
					if value_noise(gx, gy, world_seed) > 0.70:
						grid_class[idx] = TILE_TALL_GRASS

	# -------------------------------------------------------------
	# 7. Cemeteries (§4.1 step 7)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_cemetery[idx] == 1 and grid_class[idx] == TILE_GRASS:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)
				if posmod(gx, 2) == 0 and posmod(gy, 3) == 0:
					grid_class[idx] = TILE_GRAVE

	var cemetery_fences := PackedByteArray()
	cemetery_fences.resize(total_tiles)
	cemetery_fences.fill(0)

	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if is_cemetery[idx] == 1 and (grid_class[idx] == TILE_GRASS or grid_class[idx] == TILE_GRAVE):
				var is_edge := false
				for n_offset in cardinal_offsets:
					var nc: int = c + n_offset.x
					var nr: int = r + n_offset.y
					if nc < 0 or nc >= WORK_SIZE or nr < 0 or nr >= WORK_SIZE or is_cemetery[nr * WORK_SIZE + nc] == 0:
						is_edge = true
						break
				if is_edge:
					cemetery_fences[idx] = 1

	for idx in total_tiles:
		if cemetery_fences[idx] == 1:
			grid_class[idx] = TILE_FENCE

	# -------------------------------------------------------------
	# 8. Scatter (§4.1 step 8)
	# -------------------------------------------------------------
	for r in WORK_SIZE:
		for c in WORK_SIZE:
			var idx := r * WORK_SIZE + c
			if grid_class[idx] == TILE_GRASS:
				var gx := cx * 32 + (c - 4)
				var gy := cy * 32 + (35 - r)

				# 8b. FLOWERS within 2 tiles (Chebyshev) of a DOOR where u(..., 2) < 0.25
				var near_door := false
				for d in all_doors:
					if maxi(absi(c - d.x), absi(r - d.y)) <= 2:
						near_door = true
						break
				if near_door and u_rand(gx, gy, world_seed, SALT_FLOWERS) < 0.25:
					grid_class[idx] = TILE_FLOWERS
					grid_variant[idx] = 0
					continue

				# 8a. TREE scatter
				var threshold: float = 0.08 if is_residential[idx] == 1 else 0.05
				if u_rand(gx, gy, world_seed, SALT_TREE_SCATTER) < threshold:
					# Check 8-neighbourhood for forbidden classes
					var blocked := false
					for dr in range(-1, 2):
						for dc in range(-1, 2):
							if dr == 0 and dc == 0:
								continue
							var nc: int = c + dc
							var nr: int = r + dr
							if nc >= 0 and nc < WORK_SIZE and nr >= 0 and nr < WORK_SIZE:
								var n_cls: int = grid_class[nr * WORK_SIZE + nc]
								if n_cls in [TILE_PATH, TILE_ROAD, TILE_PLAZA, TILE_DOOR, TILE_WALL, TILE_ROOF, TILE_FENCE, TILE_SIGN]:
									blocked = true
									break
						if blocked:
							break
					if not blocked:
						grid_class[idx] = TILE_TREE

	# -------------------------------------------------------------
	# 9. Signs (§4.1 step 9, §4.4)
	# -------------------------------------------------------------
	var sign_candidates: Array[Dictionary] = []

	# POI place nodes in centre cell
	var places: Array = area.get(Vector2i.ZERO, {}).get("places", [])
	for place in places:
		var s_name: String = place.get("name", "")
		if s_name.is_empty():
			continue
		var s_cat: String = place.get("category", "")
		var s_osm_id: int = int(place.get("osm_id", 0))
		var lat: float = float(place.get("lat", 0.0))
		var lon: float = float(place.get("lon", 0.0))
		var wm: Vector2 = Grid.latlon_to_wm(lat, lon)
		var cell_origin := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
		var su: Vector2 = (wm - cell_origin) / MapStore.GEOM_UNIT_WM
		var c_tile: int = clampi(int(floor(4.0 + 2.0 * su.x)), 4, 35)
		var r_tile: int = clampi(int(floor(36.0 - 2.0 * su.y)), 4, 35)
		sign_candidates.append({
			"is_poi": true,
			"name": s_name,
			"category": s_cat,
			"priority": _sign_priority(s_cat),
			"osm_id": s_osm_id,
			"grid_pos": Vector2i(c_tile, r_tile)
		})

	# Named polygon pieces in centre cell
	for poly in center_polys:
		var s_name: String = poly.get("name", "")
		if s_name.is_empty() or poly.get("kind", "") == "building":
			continue
		var geom = poly.get("geom_rings", null)
		if geom == null:
			continue
		var p_rings: Array[PackedVector2Array] = []
		if geom is PackedByteArray:
			p_rings = MapStore.unpack_rings(geom)
		elif geom is Array:
			for r_item in geom:
				p_rings.append(PackedVector2Array(r_item))
		if p_rings.is_empty() or p_rings[0].size() < 3:
			continue

		var p_min_x := INF
		var p_max_x := -INF
		var p_min_y := INF
		var p_max_y := -INF
		for pt in p_rings[0]:
			p_min_x = minf(p_min_x, pt.x)
			p_max_x = maxf(p_max_x, pt.x)
			p_min_y = minf(p_min_y, pt.y)
			p_max_y = maxf(p_max_y, pt.y)

		var p_kind: String = poly.get("kind", "")
		var s_cat: String = "park" if p_kind == "park" else p_kind
		var bc_col: int = clampi(int(round(4.0 + 2.0 * ((p_min_x + p_max_x) * 0.5))), 4, 35)
		var bot_row: int = clampi(int(round(36.0 - 2.0 * p_min_y)), 4, 35)
		sign_candidates.append({
			"is_poi": false,
			"name": s_name,
			"category": s_cat,
			"priority": _sign_priority(s_cat),
			"osm_id": 0,
			"grid_pos": Vector2i(bc_col, bot_row),
			"rings": p_rings
		})

	# Spacing: landmark > haunted > civic > medical > park > any other category,
	# then lower osm_id (for polygons, lower (row, col))
	sign_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		if a["is_poi"] and b["is_poi"]:
			return a["osm_id"] < b["osm_id"]
		if a["is_poi"] != b["is_poi"]:
			return a["is_poi"]
		if a["grid_pos"].y != b["grid_pos"].y:
			return a["grid_pos"].y < b["grid_pos"].y
		return a["grid_pos"].x < b["grid_pos"].x
	)

	var signs_list: Array[String] = []
	var placed_sign_tiles: Array[Vector2i] = []

	for cand in sign_candidates:
		if signs_list.size() >= 16:
			break
		var target_pos := Vector2i(-1, -1)

		if cand["is_poi"]:
			# Check if inside a placed template
			var p0: Vector2i = cand["grid_pos"]
			var inside_b = null
			for b in placed_buildings:
				if p0.x >= b["col0"] and p0.x < b["col0"] + b["w"] and p0.y >= b["row0"] and p0.y < b["row0"] + b["h"]:
					inside_b = b
					break
			if inside_b != null:
				# West of first door
				var d_col: int = inside_b["door_cols"][0]
				var d_r: int = inside_b["row0"] + inside_b["h"] - 1
				var d_c: int = inside_b["col0"] + d_col
				var west_c := d_c - 1
				if west_c >= 4 and west_c <= 35 and d_r >= 4 and d_r <= 35:
					if grid_class[d_r * WORK_SIZE + west_c] == TILE_GRASS:
						target_pos = Vector2i(west_c, d_r)
			else:
				# Own tile if GRASS, else rings of radius 1-2 scanning N, E, S, W
				if grid_class[p0.y * WORK_SIZE + p0.x] == TILE_GRASS:
					target_pos = p0
				else:
					var found_ring := false
					for rad in [1, 2]:
						var ring_offsets: Array[Vector2i] = [Vector2i(0, -rad), Vector2i(rad, 0), Vector2i(0, rad), Vector2i(-rad, 0)]
						for off: Vector2i in ring_offsets:
							var cand_tp: Vector2i = p0 + off
							if cand_tp.x >= 4 and cand_tp.x <= 35 and cand_tp.y >= 4 and cand_tp.y <= 35:
								if grid_class[cand_tp.y * WORK_SIZE + cand_tp.x] == TILE_GRASS:
									target_pos = cand_tp
									found_ring = true
									break
						if found_ring:
							break
		else:
			# Named polygon: scan north from bottom-centre up to 4 tiles for first GRASS inside polygon
			var bc_col: int = cand["grid_pos"].x
			var bot_row: int = cand["grid_pos"].y
			var p_rings: Array[PackedVector2Array] = cand["rings"]
			for s in range(5):
				var tr := bot_row - s
				var tc := bc_col
				if tc >= 4 and tc <= 35 and tr >= 4 and tr <= 35:
					if grid_class[tr * WORK_SIZE + tc] == TILE_GRASS:
						var pt_su := Vector2((float(tc) + 0.5 - 4.0) * 0.5, (36.0 - (float(tr) + 0.5)) * 0.5)
						if _point_in_rings(pt_su, p_rings):
							target_pos = Vector2i(tc, tr)
							break

		if target_pos.x == -1:
			continue

		# Spacing: no two signs within 3 tiles (Chebyshev)
		var too_close := false
		for st in placed_sign_tiles:
			if maxi(absi(target_pos.x - st.x), absi(target_pos.y - st.y)) <= 3:
				too_close = true
				break
		if too_close:
			continue

		var s_idx := signs_list.size()
		grid_class[target_pos.y * WORK_SIZE + target_pos.x] = TILE_SIGN
		grid_variant[target_pos.y * WORK_SIZE + target_pos.x] = s_idx
		placed_sign_tiles.append(target_pos)
		signs_list.append(cand["name"])

	# -------------------------------------------------------------
	# 10. Variants & Masks (§4.1 step 10)
	# -------------------------------------------------------------
	var output := PackedByteArray()
	output.resize(OUTPUT_BUFFER_SIZE)
	var out_idx := 0

	for r in range(WORK_CELL_START, WORK_CELL_END):
		for c in range(WORK_CELL_START, WORK_CELL_END):
			var idx := r * WORK_SIZE + c
			var cls: int = grid_class[idx]
			var gx: int = cx * 32 + (c - 4)
			var gy: int = cy * 32 + (35 - r)

			# Variant byte
			var variant := 0
			match cls:
				TILE_GRASS:
					variant = floori(u_rand(gx, gy, world_seed, SALT_GRASS_VARIANT) * 4.0)
				TILE_ROAD:
					variant = 1 if u_rand(gx, gy, world_seed, SALT_ROAD_CRACKS) < 0.20 else 0
				TILE_TREE:
					variant = 1 if u_rand(gx, gy, world_seed, SALT_TREE_VARIANT) < 0.30 else 0
				TILE_ROOF, TILE_WALL, TILE_DOOR, TILE_SIGN:
					variant = grid_variant[idx]
				_:
					variant = 0

			# Mask byte
			var mask := 0
			if cls == TILE_ROOF:
				var my_color: int = grid_variant[idx]
				if grid_class[(r - 1) * WORK_SIZE + c] == TILE_ROOF and grid_variant[(r - 1) * WORK_SIZE + c] == my_color:
					mask |= 1
				if grid_class[r * WORK_SIZE + (c + 1)] == TILE_ROOF and grid_variant[r * WORK_SIZE + (c + 1)] == my_color:
					mask |= 2
				if grid_class[(r + 1) * WORK_SIZE + c] == TILE_ROOF and grid_variant[(r + 1) * WORK_SIZE + c] == my_color:
					mask |= 4
				if grid_class[r * WORK_SIZE + (c - 1)] == TILE_ROOF and grid_variant[r * WORK_SIZE + (c - 1)] == my_color:
					mask |= 8
			elif cls == TILE_WALL:
				var my_color: int = grid_variant[idx] % 8
				var n_n: int = grid_class[(r - 1) * WORK_SIZE + c]
				if (n_n == TILE_WALL or n_n == TILE_DOOR) and (grid_variant[(r - 1) * WORK_SIZE + c] % 8 == my_color):
					mask |= 1
				var n_e: int = grid_class[r * WORK_SIZE + (c + 1)]
				if (n_e == TILE_WALL or n_e == TILE_DOOR) and (grid_variant[r * WORK_SIZE + (c + 1)] % 8 == my_color):
					mask |= 2
				var n_s: int = grid_class[(r + 1) * WORK_SIZE + c]
				if (n_s == TILE_WALL or n_s == TILE_DOOR) and (grid_variant[(r + 1) * WORK_SIZE + c] % 8 == my_color):
					mask |= 4
				var n_w: int = grid_class[r * WORK_SIZE + (c - 1)]
				if (n_w == TILE_WALL or n_w == TILE_DOOR) and (grid_variant[r * WORK_SIZE + (c - 1)] % 8 == my_color):
					mask |= 8
			else:
				var family: Array = _get_mask_family(cls)
				if not family.is_empty():
					# Bit 0 = North (r - 1, c)
					if grid_class[(r - 1) * WORK_SIZE + c] in family:
						mask |= 1
					# Bit 1 = East (r, c + 1)
					if grid_class[r * WORK_SIZE + (c + 1)] in family:
						mask |= 2
					# Bit 2 = South (r + 1, c)
					if grid_class[(r + 1) * WORK_SIZE + c] in family:
						mask |= 4
					# Bit 3 = West (r, c - 1)
					if grid_class[r * WORK_SIZE + (c - 1)] in family:
						mask |= 8

			output[out_idx] = cls
			output[out_idx + 1] = variant
			output[out_idx + 2] = mask
			out_idx += 3

	return {
		"tiles": output,
		"signs": PackedStringArray(signs_list)
	}

## Mask family for 4-neighbour connectivity (§3 table)
static func _get_mask_family(cls: int) -> Array:
	match cls:
		TILE_WATER:
			return [TILE_WATER, TILE_BRIDGE]
		TILE_PATH:
			return [TILE_PATH, TILE_ROAD, TILE_BRIDGE, TILE_PLAZA, TILE_DOOR]
		TILE_ROAD:
			return [TILE_ROAD, TILE_BRIDGE, TILE_PLAZA]
		TILE_RAIL:
			return [TILE_RAIL, TILE_BRIDGE]
		TILE_BRIDGE:
			return [TILE_BRIDGE, TILE_ROAD, TILE_PATH, TILE_RAIL]
		TILE_TREE:
			return [TILE_TREE]
		TILE_TALL_GRASS:
			return [TILE_TALL_GRASS]
		TILE_ROOF:
			return [TILE_ROOF]
		TILE_WALL:
			return [TILE_WALL, TILE_DOOR]
		TILE_FENCE:
			return [TILE_FENCE]
		_:
			return []
