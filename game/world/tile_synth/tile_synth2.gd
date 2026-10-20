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
				_:
					variant = 0

			# Mask byte
			var mask := 0
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
		"signs": PackedStringArray()
	}

## Mask family for 4-neighbour connectivity (§3 table)
static func _get_mask_family(cls: int) -> Array:
	match cls:
		TILE_WATER:
			return [TILE_WATER, TILE_BRIDGE]
		TILE_PATH:
			return [TILE_PATH, TILE_ROAD, TILE_BRIDGE, TILE_PLAZA]
		TILE_ROAD:
			return [TILE_ROAD, TILE_BRIDGE]
		TILE_RAIL:
			return [TILE_RAIL]
		TILE_BRIDGE:
			return [TILE_BRIDGE]
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
