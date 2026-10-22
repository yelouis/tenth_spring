class_name SynthWorker
extends RefCounted

# synth_worker.gd — Dedicated Background Worker for Map Tile Synthesis (Slice 2, F52)
# Contract: docs/implementation_plan_world_generation_slice2.md §10.5 & docs/agent_execution_guide.md §5

const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")
const MapStore := preload("res://world/region_import/map_store.gd")

# LRU Cache for raw store features (capacity 256)
class LruCache:
	var capacity: int = 256
	var _map: Dictionary = {}
	var _order: Array[Vector2i] = []

	func _init(cap: int = 256) -> void:
		capacity = cap

	func get_item(key: Vector2i):
		if not _map.has(key):
			return null
		_order.erase(key)
		_order.append(key)
		return _map[key]

	func has(key: Vector2i) -> bool:
		return _map.has(key)

	func put(key: Vector2i, val) -> void:
		if _map.has(key):
			_order.erase(key)
		elif _order.size() >= capacity:
			var oldest: Vector2i = _order.pop_front()
			_map.erase(oldest)
		_order.append(key)
		_map[key] = val

	func size() -> int:
		return _order.size()

	func clear() -> void:
		_map.clear()
		_order.clear()

# Thread & synchronization
var _thread: Thread = null
var _mutex: Mutex = null
var _semaphore: Semaphore = null
var _running: bool = false
var _main_thread_id: int = 0
var _worker_thread_id: int = 0

# Worker-owned store connections (never shared across threads)
var _store_paths: Array[String] = []
var _store_paths_changed: bool = false
var _worker_stores: Array[MapStore] = []
var _store_cache: LruCache = null

# Queues
# Request items: Dictionary {cell: Vector2i, priority_dist: float, needs_overview: bool, reveal_state: int, preview_cleared: bool}
var _request_queue: Array[Dictionary] = []
# Result items: Dictionary {cell: Vector2i, tiles: PackedByteArray, signs: Array, has_data: bool, image: Image, thread_id: int, reveal_state: int}
var _result_queue: Array[Dictionary] = []
# Synchronous requests: cell -> Semaphore
var _sync_requests: Dictionary = {}

# Palette colors for overview texture (§5.3 / §6)
const MAP_COLORS := {
	0: Color("#2a3242"),  # VOID
	1: Color("#78c850"),  # GRASS
	2: Color("#4f9a3a"),  # TALL_GRASS
	3: Color("#3a7d3a"),  # TREE
	4: Color("#4a90d8"),  # WATER
	5: Color("#e8d8a0"),  # SAND
	6: Color("#6a9a6a"),  # MARSH
	7: Color("#d8c090"),  # PATH
	8: Color("#8a8a90"),  # ROAD
	9: Color("#6b6b6b"),  # RAIL
	10: Color("#b07840"), # BRIDGE
	11: Color("#b0b0b8"), # PLAZA
	13: Color("#e8e0d0"), # WALL
	14: Color("#7a5028"), # DOOR
	15: Color("#f0f0f0"), # FENCE
	16: Color("#f85878"), # FLOWERS
	17: Color("#a0a0a8"), # GRAVE
	18: Color("#b07840"), # SIGN
	19: Color("#a8c060"), # CROP
}

const ROOF_BASE_COLORS := [
	Color("#c0504a"), Color("#3a9a9a"), Color("#5a9a4a"), Color("#8a5ab0"),
	Color("#4a78c8"), Color("#e08a3a"), Color("#b090c8"), Color("#8a8a90")
]

func _init() -> void:
	_main_thread_id = OS.get_thread_caller_id()
	_mutex = Mutex.new()
	_semaphore = Semaphore.new()

func start(store_paths: Array[String] = []) -> void:
	if _running:
		return
	_store_paths = store_paths.duplicate()
	_store_paths_changed = true
	_running = true
	_thread = Thread.new()
	_thread.start(_worker_loop)

func stop() -> void:
	if not _running:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_semaphore.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

func is_running() -> bool:
	return _running

func set_store_paths(paths: Array[String]) -> void:
	_mutex.lock()
	_store_paths = paths.duplicate()
	_store_paths_changed = true
	_mutex.unlock()
	_semaphore.post()

func get_main_thread_id() -> int:
	return _main_thread_id

func get_worker_thread_id() -> int:
	return _worker_thread_id

func get_request_queue_size() -> int:
	_mutex.lock()
	var sz := _request_queue.size()
	_mutex.unlock()
	return sz

func get_request_queue_cells() -> Array[Vector2i]:
	_mutex.lock()
	var cells: Array[Vector2i] = []
	for req in _request_queue:
		cells.append(req["cell"])
	_mutex.unlock()
	return cells

func update_requests(new_requests: Array[Dictionary], visible_cell_set: Dictionary) -> void:
	_mutex.lock()
	# 1. Drop requests for cells that left the view (§10.5 rule 2)
	var filtered_queue: Array[Dictionary] = []
	var queued_cells: Dictionary = {}
	for req in _request_queue:
		var c: Vector2i = req["cell"]
		if visible_cell_set.has(c):
			filtered_queue.append(req)
			queued_cells[c] = true
	_request_queue = filtered_queue

	# 2. Add new requests for cells not already queued
	var added_count := 0
	for req in new_requests:
		var c: Vector2i = req["cell"]
		if not queued_cells.has(c) and visible_cell_set.has(c):
			_request_queue.append(req)
			queued_cells[c] = true
			added_count += 1

	# 3. Sort nearest to camera centre first
	_request_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("priority_dist", 0.0)) < float(b.get("priority_dist", 0.0))
	)

	# 4. Enforce queue limit: at most 64 requests queued (§10.5 rule 2)
	if _request_queue.size() > 64:
		_request_queue.resize(64)

	_mutex.unlock()

	if added_count > 0:
		_semaphore.post()

func pop_results() -> Array[Dictionary]:
	_mutex.lock()
	if _result_queue.is_empty():
		_mutex.unlock()
		return []
	var results := _result_queue.duplicate()
	_result_queue.clear()
	_mutex.unlock()
	return results

func request_cell_sync(cell: Vector2i, needs_overview: bool, reveal_state: int, preview_cleared: bool) -> Dictionary:
	var sync_sem := Semaphore.new()
	_mutex.lock()
	_sync_requests[cell] = sync_sem
	var req := {
		"cell": cell,
		"priority_dist": -1.0,
		"needs_overview": needs_overview,
		"reveal_state": reveal_state,
		"preview_cleared": preview_cleared
	}
	for i in range(_request_queue.size() - 1, -1, -1):
		if _request_queue[i]["cell"] == cell:
			_request_queue.remove_at(i)
	_request_queue.push_front(req)
	_mutex.unlock()
	_semaphore.post()

	sync_sem.wait()

	_mutex.lock()
	var found_res: Dictionary = {}
	for i in range(_result_queue.size() - 1, -1, -1):
		if _result_queue[i]["cell"] == cell:
			found_res = _result_queue[i]
			_result_queue.remove_at(i)
			break
	_mutex.unlock()
	return found_res

func _worker_loop() -> void:
	_worker_thread_id = OS.get_thread_caller_id()
	_store_cache = LruCache.new(256)
	_open_worker_stores()

	while true:
		var req: Dictionary = {}
		_mutex.lock()
		if not _running:
			_mutex.unlock()
			break

		if _store_paths_changed:
			_store_paths_changed = false
			_close_worker_stores()
			_open_worker_stores()

		if not _request_queue.is_empty():
			req = _request_queue.pop_front()
		_mutex.unlock()

		if req.is_empty():
			_semaphore.wait()
			continue

		var res: Dictionary = _process_request(req)

		_mutex.lock()
		_result_queue.append(res)
		var cell: Vector2i = req["cell"]
		if _sync_requests.has(cell):
			var sync_sem: Semaphore = _sync_requests[cell]
			_sync_requests.erase(cell)
			sync_sem.post()
		_mutex.unlock()

	_close_worker_stores()

func _open_worker_stores() -> void:
	if _store_cache != null:
		_store_cache.clear()
	for p in _store_paths:
		var store := MapStore.new(p)
		if store.open_store(true):
			var schema_ver := store.get_state("schema_version", "")
			if schema_ver == "4":
				_worker_stores.append(store)
			else:
				store.close()

func _close_worker_stores() -> void:
	for s in _worker_stores:
		s.close()
	_worker_stores.clear()
	if _store_cache != null:
		_store_cache.clear()

func _get_cell_features(cell_x: int, cell_y: int) -> Dictionary:
	var key := Vector2i(cell_x, cell_y)
	if _store_cache != null and _store_cache.has(key):
		return _store_cache.get_item(key)

	var features := {
		"polys": [],
		"lines": [],
		"places": [],
		"sea": 0,
		"has_data": false,
		"covered": false,
		"is_covered": false
	}
	for store in _worker_stores:
		var polys = store.get_features_poly(cell_x, cell_y)
		var lines = store.get_features_line(cell_x, cell_y)
		var places = store.get_place_nodes(cell_x, cell_y)
		if not polys.is_empty() or not lines.is_empty() or not places.is_empty():
			features["polys"].append_array(polys)
			features["lines"].append_array(lines)
			features["places"].append_array(places)
			features["has_data"] = true
		if store.covers_cell(cell_x, cell_y):
			features["covered"] = true
			features["is_covered"] = true
			var sea = store.get_cell_sea(cell_x, cell_y)
			if sea > 0:
				features["sea"] = sea

	if _store_cache != null:
		_store_cache.put(key, features)
	return features

func _process_request(req: Dictionary) -> Dictionary:
	var cell: Vector2i = req["cell"]
	var cx: int = cell.x
	var cy: int = cell.y
	var needs_overview: bool = req.get("needs_overview", false)
	var reveal_state: int = req.get("reveal_state", 1)
	var preview_cleared: bool = req.get("preview_cleared", false)

	var caller_id := OS.get_thread_caller_id()

	# Assemble 3x3 neighbourhood area for TileSynth2
	var area: Dictionary = {}
	var has_map_data := false
	var is_covered_by_store := false

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n_cell := Vector2i(cx + dx, cy + dy)
			var n_feat := _get_cell_features(n_cell.x, n_cell.y)
			area[Vector2i(dx, dy)] = n_feat
			if n_feat.get("has_data", false):
				has_map_data = true
			if n_feat.get("is_covered", false):
				is_covered_by_store = true

	var tile_buf: PackedByteArray
	var signs_list: Array = []

	if has_map_data or is_covered_by_store:
		var synth_res: Dictionary = TileSynth2.synthesize_cell(cx, cy, area)
		tile_buf = synth_res.get("tiles", PackedByteArray())
		signs_list = synth_res.get("signs", [])
		has_map_data = true
	else:
		tile_buf = PackedByteArray()
		tile_buf.resize(32 * 32 * 3)
		tile_buf.fill(0)

	var overview_image: Image = null
	if needs_overview:
		overview_image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var apply_cpu_tint := (reveal_state == 1 and not preview_cleared)
		for r in 32:
			for c in 32:
				var idx := (r * 32 + c) * 3
				var cls: int = tile_buf[idx]
				var v: int = tile_buf[idx + 1]
				var base_col: Color
				if reveal_state == 0:
					base_col = Color("#0d1119")
				elif cls == 12: # ROOF
					base_col = ROOF_BASE_COLORS[v % 8]
				else:
					base_col = MAP_COLORS.get(cls, Color("#2a3242"))

				if apply_cpu_tint:
					var g := 0.299 * base_col.r + 0.587 * base_col.g + 0.114 * base_col.b
					base_col = Color(
						(g * 0.4 + base_col.r * 0.6) * 0.82,
						(g * 0.4 + base_col.g * 0.6) * 0.82,
						(g * 0.4 + base_col.b * 0.6) * 0.82,
						1.0
					)
				overview_image.set_pixel(c, r, base_col)

	return {
		"cell": cell,
		"tiles": tile_buf,
		"signs": signs_list,
		"has_data": has_map_data,
		"image": overview_image,
		"thread_id": caller_id,
		"reveal_state": reveal_state
	}
