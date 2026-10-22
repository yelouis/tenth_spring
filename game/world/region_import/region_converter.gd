extends RefCounted

# region_converter.gd — Streaming Three-Pass OSM PBF to Map Store Converter (F39)
# Reference: docs/design_memory_and_resources.md §3.1 & docs/implementation_plan_world_generation.md §5.2-§5.3

const OsmPbfReader := preload("res://world/region_import/osm_pbf_reader.gd")
const MapStore := preload("res://world/region_import/map_store.gd")
const Grid := preload("res://world/grid.gd")
const PoiMapping := preload("res://config/poi_mapping.gd")
const MapConstants := preload("res://world/map_constants.gd")

# Injectable memory reader: Callable returning Dictionary with "available" and "physical" in bytes
var memory_reader: Callable = Callable(self, "_default_memory_reader")

# Testing / injection hooks
var simulated_pause_delay_ms: int = 1000
var required_resume_consecutive_ms: int = 10000
var stop_after_pass: int = -1 # If > 0, halts after completing this pass for checkpoint testing
var pause_count: int = 0
var resume_count: int = 0
var cancel_requested: bool = false

# Signals/Events
signal progress_updated(stage: String, current: int, total: int)
signal memory_paused(available: int, floor: int)
signal memory_resumed()

var _last_mem_poll_ms: int = 0
var _cached_mem_info: Dictionary = {}

func _default_memory_reader() -> Dictionary:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_mem_poll_ms < 1000 and not _cached_mem_info.is_empty():
		return _cached_mem_info

	_last_mem_poll_ms = now_ms
	var info := OS.get_memory_info()

	if OS.get_name() == "macOS":
		var phys: int = info.get("physical", 0)
		var avail: int = info.get("available", 0)
		if avail < int(phys * 0.10):
			var out: Array = []
			var res := OS.execute("vm_stat", [], out)
			if res == 0 and out.size() > 0:
				var text: String = out[0]
				var page_size := 16384 if "16384" in text else 4096
				var free_p := 0
				var inact_p := 0
				var spec_p := 0
				var purg_p := 0
				for line in text.split("\n"):
					var l := line.strip_edges()
					if l.begins_with("Pages free:"):
						free_p = l.trim_prefix("Pages free:").trim_suffix(".").strip_edges().to_int()
					elif l.begins_with("Pages inactive:"):
						inact_p = l.trim_prefix("Pages inactive:").trim_suffix(".").strip_edges().to_int()
					elif l.begins_with("Pages speculative:"):
						spec_p = l.trim_prefix("Pages speculative:").trim_suffix(".").strip_edges().to_int()
					elif l.begins_with("Pages purgeable:"):
						purg_p = l.trim_prefix("Pages purgeable:").trim_suffix(".").strip_edges().to_int()
				var real_avail: int = (free_p + inact_p + spec_p + purg_p) * page_size
				if real_avail > 0:
					info["available"] = real_avail

	_cached_mem_info = info
	return info

func _check_memory_pause() -> void:
	var mem_info: Dictionary = memory_reader.call()
	if not mem_info.has("available") or mem_info["available"] < 0:
		return
	var physical: int = mem_info.get("physical", 0)
	var available: int = mem_info.get("available", 0)
	var pause_floor: int = maxi(1024 * 1024 * 1024, int(physical * 0.10))

	if available < pause_floor:
		pause_count += 1
		print("Paused — your computer is low on memory. Map preparation will continue automatically.")
		memory_paused.emit(available, pause_floor)

		var resume_threshold: int = pause_floor + 512 * 1024 * 1024
		var consecutive_ok_ms: int = 0
		while consecutive_ok_ms < required_resume_consecutive_ms:
			OS.delay_msec(simulated_pause_delay_ms)
			var cur_info: Dictionary = memory_reader.call()
			var cur_avail: int = cur_info.get("available", 0)
			if cur_avail >= resume_threshold:
				consecutive_ok_ms += simulated_pause_delay_ms
			else:
				consecutive_ok_ms = 0
		resume_count += 1
		print("Resumed map preparation.")
		memory_resumed.emit()

# -------------------------------------------------------------
# Clipping & Geometry Utilities
# -------------------------------------------------------------

static func clip_polygon_to_box(pts: PackedVector2Array, box_min: Vector2, box_max: Vector2) -> PackedVector2Array:
	var output := pts
	output = _clip_edge(output, 0, box_min.x, true)
	if output.is_empty(): return output
	output = _clip_edge(output, 0, box_max.x, false)
	if output.is_empty(): return output
	output = _clip_edge(output, 1, box_min.y, true)
	if output.is_empty(): return output
	output = _clip_edge(output, 1, box_max.y, false)
	return output

static func _clip_edge(poly: PackedVector2Array, axis: int, edge: float, is_greater: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	var n := poly.size()
	if n < 3: return result
	for i in n:
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var p1_in := (p1[axis] >= edge) if is_greater else (p1[axis] <= edge)
		var p2_in := (p2[axis] >= edge) if is_greater else (p2[axis] <= edge)
		if p1_in and p2_in:
			result.append(p2)
		elif p1_in and not p2_in:
			var denom := p2[axis] - p1[axis]
			var t := (edge - p1[axis]) / denom if absf(denom) > 1e-9 else 0.0
			result.append(p1.lerp(p2, t))
		elif not p1_in and p2_in:
			var denom := p2[axis] - p1[axis]
			var t := (edge - p1[axis]) / denom if absf(denom) > 1e-9 else 0.0
			result.append(p1.lerp(p2, t))
			result.append(p2)
	return result

static func clip_segment_to_box(p1: Vector2, p2: Vector2, box_min: Vector2, box_max: Vector2) -> Array[Vector2]:
	var code := func(p: Vector2) -> int:
		var c := 0
		if p.x < box_min.x: c |= 1
		elif p.x > box_max.x: c |= 2
		if p.y < box_min.y: c |= 4
		elif p.y > box_max.y: c |= 8
		return c

	var c1: int = code.call(p1)
	var c2: int = code.call(p2)
	var a := p1
	var b := p2

	while true:
		if (c1 | c2) == 0:
			return [a, b]
		elif (c1 & c2) != 0:
			return []
		else:
			var c_out := c1 if c1 != 0 else c2
			var p := Vector2.ZERO
			if c_out & 8: # Top
				p.x = a.x + (b.x - a.x) * (box_max.y - a.y) / (b.y - a.y)
				p.y = box_max.y
			elif c_out & 4: # Bottom
				p.x = a.x + (b.x - a.x) * (box_min.y - a.y) / (b.y - a.y)
				p.y = box_min.y
			elif c_out & 2: # Right
				p.y = a.y + (b.y - a.y) * (box_max.x - a.x) / (b.x - a.x)
				p.x = box_max.x
			elif c_out & 1: # Left
				p.y = a.y + (b.y - a.y) * (box_min.x - a.x) / (b.x - a.x)
				p.x = box_min.x

			if c_out == c1:
				a = p
				c1 = code.call(a)
			else:
				b = p
				c2 = code.call(b)
	return []

static func stitch_ways_to_rings(way_segments: Array) -> Array[PackedVector2Array]:
	var closed_rings: Array[PackedVector2Array] = []
	var open_chains: Array[PackedVector2Array] = []

	for seg in way_segments:
		if not (seg is PackedVector2Array):
			continue
		var pts: PackedVector2Array = seg
		if pts.size() < 2:
			continue
		if (pts[0] - pts[pts.size() - 1]).length_squared() < 1e-4 and pts.size() >= 3:
			closed_rings.append(pts)
		else:
			open_chains.append(pts.duplicate())

	while not open_chains.is_empty():
		var chain: PackedVector2Array = open_chains.pop_front()
		var progress := true
		while progress and not open_chains.is_empty():
			progress = false
			if (chain[0] - chain[chain.size() - 1]).length_squared() < 1e-4 and chain.size() >= 3:
				break

			var c_start: Vector2 = chain[0]
			var c_end: Vector2 = chain[chain.size() - 1]

			for i in range(open_chains.size()):
				var next_seg: PackedVector2Array = open_chains[i]
				var n_start: Vector2 = next_seg[0]
				var n_end: Vector2 = next_seg[next_seg.size() - 1]

				if (c_end - n_start).length_squared() < 1e-3:
					for k in range(1, next_seg.size()):
						chain.append(next_seg[k])
					open_chains.remove_at(i)
					progress = true
					break
				elif (c_end - n_end).length_squared() < 1e-3:
					for k in range(next_seg.size() - 2, -1, -1):
						chain.append(next_seg[k])
					open_chains.remove_at(i)
					progress = true
					break
				elif (c_start - n_end).length_squared() < 1e-3:
					var new_chain := PackedVector2Array()
					for k in range(next_seg.size() - 1):
						new_chain.append(next_seg[k])
					new_chain.append_array(chain)
					chain = new_chain
					open_chains.remove_at(i)
					progress = true
					break
				elif (c_start - n_start).length_squared() < 1e-3:
					var new_chain := PackedVector2Array()
					for k in range(next_seg.size() - 1, 0, -1):
						new_chain.append(next_seg[k])
					new_chain.append_array(chain)
					chain = new_chain
					open_chains.remove_at(i)
					progress = true
					break

		if chain.size() >= 3:
			if (chain[0] - chain[chain.size() - 1]).length_squared() >= 1e-4:
				chain.append(chain[0])
			closed_rings.append(chain)

	return closed_rings

static func ring_contains_point(ring: PackedVector2Array, pt: Vector2) -> bool:
	var n := ring.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in range(n):
		var pi := ring[i]
		var pj := ring[j]
		var denom := pj.y - pi.y
		if absf(denom) < 1e-9:
			denom = 1e-9
		if ((pi.y > pt.y) != (pj.y > pt.y)) and (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / denom + pi.x):
			inside = not inside
		j = i
	return inside

static func lookup_place(place_id: String, config_path: String = "") -> Dictionary:
	var paths := []
	if not config_path.is_empty():
		paths.append(config_path)
	paths.append("res://config/famous_places.json")
	paths.append("res://tests/fixtures/famous_places_fixture.json")

	for p in paths:
		if FileAccess.file_exists(p):
			var txt := FileAccess.get_file_as_string(p)
			var parsed: Variant = JSON.parse_string(txt)
			var place_list: Array = []
			if parsed is Array:
				place_list = parsed
			elif parsed is Dictionary and parsed.has("places") and parsed["places"] is Array:
				place_list = parsed["places"]
			for pl in place_list:
				if pl is Dictionary and str(pl.get("id", "")) == place_id:
					return pl
	return {}

static func extract_relation_polygon_from_pbf(pbf_path: String, rel_id: int) -> Dictionary:
	var f := FileAccess.open(pbf_path, FileAccess.READ)
	if not f:
		return {"ok": false, "error": "Cannot open PBF file: " + pbf_path}

	var target_way_ids: Dictionary = {}
	var rel_tags: Dictionary = {}
	var file_len := f.get_length()

	while f.get_position() < file_len:
		var blob := OsmPbfReader.read_blob_header_and_data(f)
		if blob.is_empty():
			break
		if blob.get("type", "") != "OSMData":
			continue
		var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
		if decomp.is_empty():
			continue
		var pr := OsmPbfReader.ProtoReader.new(decomp)
		var string_table: Array[String] = []

		while pr.has_more():
			var tag := pr.read_varint()
			var fn := tag >> 3
			var wt := tag & 0x7
			if fn == 1 and wt == 2:
				var st_len := pr.read_varint()
				string_table = OsmPbfReader.decode_string_table(pr, st_len)
			elif fn == 2 and wt == 2:
				var glen := pr.read_varint()
				var gr_end := pr.pos + glen
				while pr.pos < gr_end:
					var gtag := pr.read_varint()
					var gfn := gtag >> 3
					var gwt := gtag & 0x7
					if gfn == 4 and gwt == 2: # Relation
						var rlen := pr.read_varint()
						var rend := pr.pos + rlen
						var rid := 0
						var r_keys: Array[int] = []
						var r_vals: Array[int] = []
						var r_roles: Array[int] = []
						var r_memids: Array[int] = []
						var r_types: Array[int] = []
						while pr.pos < rend:
							var rtag := pr.read_varint()
							var rfn := rtag >> 3
							var rwt := rtag & 0x7
							if rfn == 1 and rwt == 0:
								rid = pr.read_varint()
							elif rfn == 2 and rwt == 2:
								var kl := pr.read_varint()
								var kend := pr.pos + kl
								while pr.pos < kend:
									r_keys.append(pr.read_varint())
							elif rfn == 3 and rwt == 2:
								var vl := pr.read_varint()
								var vend := pr.pos + vl
								while pr.pos < vend:
									r_vals.append(pr.read_varint())
							elif rfn == 8 and rwt == 2:
								var rl := pr.read_varint()
								var rend_roles := pr.pos + rl
								while pr.pos < rend_roles:
									r_roles.append(pr.read_varint())
							elif rfn == 9 and rwt == 2:
								var ml := pr.read_varint()
								var mend := pr.pos + ml
								var cur_mid := 0
								while pr.pos < mend:
									cur_mid += pr.read_sint64()
									r_memids.append(cur_mid)
							elif rfn == 10 and rwt == 2:
								var tl := pr.read_varint()
								var tend := pr.pos + tl
								while pr.pos < tend:
									r_types.append(pr.read_varint())
							elif rwt == 2:
								pr.skip(pr.read_varint())
							elif rwt == 0:
								pr.read_varint()

						if rid == rel_id:
							for k_i in r_keys.size():
								var k_str := string_table[r_keys[k_i]] if k_i < r_keys.size() and r_keys[k_i] < string_table.size() else ""
								var v_str := string_table[r_vals[k_i]] if k_i < r_vals.size() and r_vals[k_i] < string_table.size() else ""
								rel_tags[k_str] = v_str
							for m_i in r_memids.size():
								var m_type: int = r_types[m_i] if m_i < r_types.size() else 0
								var m_role: String = string_table[r_roles[m_i]] if m_i < r_roles.size() and r_roles[m_i] < string_table.size() else ""
								var m_id: int = r_memids[m_i]
								if m_type == 1: # WAY
									if m_role == "outer" or m_role == "" or m_role == "enclave":
										target_way_ids[m_id] = m_role
							break
					elif gwt == 2:
						pr.skip(pr.read_varint())
					elif gwt == 0:
						pr.read_varint()
			elif wt == 2:
				pr.skip(pr.read_varint())
			elif wt == 0:
				pr.read_varint()
		if not target_way_ids.is_empty():
			break

	if target_way_ids.is_empty():
		f.close()
		return {"ok": false, "error": "Relation %d outer ways not found" % rel_id}

	# 2. Scan ways
	f.seek(0)
	var way_refs: Dictionary = {}
	var needed_node_ids_set: Dictionary = {}
	var found_ways_count := 0

	while f.get_position() < file_len and found_ways_count < target_way_ids.size():
		var blob := OsmPbfReader.read_blob_header_and_data(f)
		if blob.is_empty():
			break
		if blob.get("type", "") != "OSMData":
			continue
		var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
		if decomp.is_empty():
			continue
		var pr := OsmPbfReader.ProtoReader.new(decomp)

		while pr.has_more():
			var tag := pr.read_varint()
			var fn := tag >> 3
			var wt := tag & 0x7
			if fn == 2 and wt == 2:
				var glen := pr.read_varint()
				var gr_end := pr.pos + glen
				while pr.pos < gr_end:
					var gtag := pr.read_varint()
					var gfn := gtag >> 3
					var gwt := gtag & 0x7
					if gfn == 3 and gwt == 2: # Way
						var wlen := pr.read_varint()
						var wend := pr.pos + wlen
						var wid := 0
						var w_refs: Array[int] = []
						while pr.pos < wend:
							var wtag := pr.read_varint()
							var wfn := wtag >> 3
							var wwt := wtag & 0x7
							if wfn == 1 and wwt == 0:
								wid = pr.read_varint()
							elif wfn == 8 and wwt == 2:
								var rl := pr.read_varint()
								var rend := pr.pos + rl
								var cur_ref := 0
								while pr.pos < rend:
									cur_ref += pr.read_sint64()
									w_refs.append(cur_ref)
							elif wwt == 2:
								pr.skip(pr.read_varint())
							elif wwt == 0:
								pr.read_varint()

						if target_way_ids.has(wid):
							way_refs[wid] = w_refs
							for r in w_refs:
								needed_node_ids_set[r] = true
							found_ways_count += 1
					elif gwt == 2:
						pr.skip(pr.read_varint())
					elif gwt == 0:
						pr.read_varint()
			elif wt == 2:
				pr.skip(pr.read_varint())
			elif wt == 0:
				pr.read_varint()

	# 3. Scan dense nodes
	f.seek(0)
	var node_coords: Dictionary = {}
	var found_nodes_count := 0
	var total_needed_nodes := needed_node_ids_set.size()

	while f.get_position() < file_len and found_nodes_count < total_needed_nodes:
		var blob := OsmPbfReader.read_blob_header_and_data(f)
		if blob.is_empty():
			break
		if blob.get("type", "") != "OSMData":
			continue
		var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
		if decomp.is_empty():
			continue
		var pr := OsmPbfReader.ProtoReader.new(decomp)

		while pr.has_more():
			var tag := pr.read_varint()
			var fn := tag >> 3
			var wt := tag & 0x7
			if fn == 2 and wt == 2:
				var glen := pr.read_varint()
				var gr_end := pr.pos + glen
				while pr.pos < gr_end:
					var gtag := pr.read_varint()
					var gfn := gtag >> 3
					var gwt := gtag & 0x7
					if gfn == 2 and gwt == 2: # DenseNodes
						var dlen := pr.read_varint()
						var dend := pr.pos + dlen
						var id_deltas: Array[int] = []
						var lat_deltas: Array[int] = []
						var lon_deltas: Array[int] = []
						while pr.pos < dend:
							var dtag := pr.read_varint()
							var dfn := dtag >> 3
							var dwt := dtag & 0x7
							if dfn == 1 and dwt == 2:
								var l := pr.read_varint()
								var lend := pr.pos + l
								while pr.pos < lend:
									id_deltas.append(pr.read_sint64())
							elif dfn == 8 and dwt == 2:
								var l := pr.read_varint()
								var lend := pr.pos + l
								while pr.pos < lend:
									lat_deltas.append(pr.read_sint64())
							elif dfn == 9 and dwt == 2:
								var l := pr.read_varint()
								var lend := pr.pos + l
								while pr.pos < lend:
									lon_deltas.append(pr.read_sint64())
							elif dwt == 2:
								pr.skip(pr.read_varint())
							elif dwt == 0:
								pr.read_varint()

						var cur_id := 0
						var cur_lat := 0
						var cur_lon := 0
						for di in id_deltas.size():
							cur_id += id_deltas[di]
							cur_lat += lat_deltas[di]
							cur_lon += lon_deltas[di]
							if needed_node_ids_set.has(cur_id):
								var lat_f := float(cur_lat) * 1e-7
								var lon_f := float(cur_lon) * 1e-7
								node_coords[cur_id] = Grid.latlon_to_wm(lat_f, lon_f)
								found_nodes_count += 1
					elif gwt == 2:
						pr.skip(pr.read_varint())
					elif gwt == 0:
						pr.read_varint()
			elif wt == 2:
				pr.skip(pr.read_varint())
			elif wt == 0:
				pr.read_varint()

	f.close()

	var way_segments: Array = []
	for wid in way_refs.keys():
		var refs: Array = way_refs[wid]
		var pts := PackedVector2Array()
		var ok := true
		for r in refs:
			if node_coords.has(r):
				pts.append(node_coords[r])
			else:
				ok = false
				break
		if ok and pts.size() >= 2:
			way_segments.append(pts)

	var rings := stitch_ways_to_rings(way_segments)
	if rings.is_empty():
		return {"ok": false, "error": "Stitching failed to produce closed rings for relation %d" % rel_id}

	var outer_poly := rings[0]
	var max_area := _polygon_area(outer_poly)
	for i in range(1, rings.size()):
		var a := _polygon_area(rings[i])
		if a > max_area:
			max_area = a
			outer_poly = rings[i]

	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in outer_poly:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)

	return {
		"ok": true,
		"polygon": outer_poly,
		"rings": rings,
		"min_wm": Vector2(min_x, min_y),
		"max_wm": Vector2(max_x, max_y),
		"tags": rel_tags
	}

# -------------------------------------------------------------
# Main Conversion Routine
# -------------------------------------------------------------

func _cleanup_cancel(out_db_path: String, store: Object) -> Dictionary:
	if store != null:
		store.close()
	for p in [out_db_path + ".nodes.tmp", out_db_path + ".rels.tmp", out_db_path + ".coords.tmp", out_db_path + ".nbrs.tmp", out_db_path + ".poly.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for sfx in ["", "-wal", "-shm"]:
		if FileAccess.file_exists(out_db_path + sfx):
			DirAccess.remove_absolute(out_db_path + sfx)
	return {"ok": false, "error": "Cancelled"}

func convert(pbf_path: String, out_db_path: String, clip_rect: Variant = null, coverage_box: Variant = null, place_id: String = "", config_path: String = "") -> Dictionary:
	var t0 := Time.get_ticks_msec()

	if cancel_requested:
		return _cleanup_cancel(out_db_path, null)

	if not FileAccess.file_exists(pbf_path):
		return {"ok": false, "error": "PBF file not found: " + pbf_path}

	var store := MapStore.new(out_db_path)
	if not store.open_store(false):
		return {"ok": false, "error": "Failed to open map store: " + store.last_error}

	var cur_state_pass := store.get_state("pass", "0")
	if cur_state_pass == "completed":
		print("map_convert: Map store is already completely converted.")
		var h := store.canonical_dump_sha256()
		store.close()
		return {
			"ok": true,
			"already_completed": true,
			"canonical_hash": h,
			"time_ms": Time.get_ticks_msec() - t0
		}

	# Check for place-based fixed conversion unit
	var temp_poly_path := out_db_path + ".poly.tmp"
	var place_poly := PackedVector2Array()
	var place_kind := ""
	var place_name := ""

	if not place_id.is_empty():
		var place_info := lookup_place(place_id, config_path)
		if place_info.is_empty():
			store.close()
			return {"ok": false, "error": "Place not found in configuration: " + place_id}
		var boundary_val: Variant = place_info.get("osm_boundary", null)
		var rel_id := 0
		if boundary_val is Dictionary:
			rel_id = int(boundary_val.get("relation_id", 0))
		elif boundary_val is String:
			var s: String = (boundary_val as String).strip_edges()
			if s.begins_with("r"):
				rel_id = int(s.substr(1))
			else:
				rel_id = int(s)
		elif boundary_val is int:
			rel_id = boundary_val
		if rel_id == 0:
			store.close()
			return {"ok": false, "error": "Place %s has no osm_boundary relation id" % place_id}

		place_kind = str(place_info.get("kind", "city"))
		place_name = str(place_info.get("name", ""))

		if FileAccess.file_exists(temp_poly_path):
			var pf := FileAccess.open(temp_poly_path, FileAccess.READ)
			if pf:
				var p_txt := pf.get_as_text()
				var p_parsed: Variant = JSON.parse_string(p_txt)
				if p_parsed is Dictionary:
					place_kind = str(p_parsed.get("kind", place_kind))
					place_name = str(p_parsed.get("name", place_name))
					var pts_arr: Array = p_parsed.get("pts", [])
					place_poly = PackedVector2Array()
					for pt in pts_arr:
						place_poly.append(Vector2(float(pt[0]), float(pt[1])))
				pf.close()

		if place_poly.is_empty():
			var poly_res := extract_relation_polygon_from_pbf(pbf_path, rel_id)
			if not poly_res.get("ok", false):
				store.close()
				return poly_res

			place_poly = poly_res["polygon"]
			var pf := FileAccess.open(temp_poly_path, FileAccess.WRITE)
			if pf:
				var pts_arr: Array = []
				for p in place_poly:
					pts_arr.append([p.x, p.y])
				pf.store_string(JSON.stringify({
					"kind": place_kind,
					"name": place_name,
					"pts": pts_arr
				}))
				pf.close()

		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		for p in place_poly:
			min_x = minf(min_x, p.x)
			min_y = minf(min_y, p.y)
			max_x = maxf(max_x, p.x)
			max_y = maxf(max_y, p.y)

		var p_min_cx := int(floor(min_x / Grid.CELL_WM))
		var p_min_cy := int(floor(min_y / Grid.CELL_WM))
		var p_max_cx := int(floor(max_x / Grid.CELL_WM))
		var p_max_cy := int(floor(max_y / Grid.CELL_WM))

		var c_min_cx := p_min_cx - 2
		var c_min_cy := p_min_cy - 2
		var c_max_cx := p_max_cx + 2
		var c_max_cy := p_max_cy + 2

		var c_min_x := float(c_min_cx) * Grid.CELL_WM
		var c_min_y := float(c_min_cy) * Grid.CELL_WM
		var c_max_x := float(c_max_cx + 1) * Grid.CELL_WM
		var c_max_y := float(c_max_cy + 1) * Grid.CELL_WM

		clip_rect = Rect2(c_min_x, c_min_y, c_max_x - c_min_x, c_max_y - c_min_y)
		coverage_box = [c_min_cx, c_min_cy, c_max_cx, c_max_cy]

	# In-memory indices
	var needed_node_ids := PackedInt64Array()
	var node_lats := PackedInt32Array()
	var node_lons := PackedInt32Array()
	var kept_relations := []
	var relation_way_ids := {}
	var neighbourhood_nodes: Array = []
	var admin_neighbourhood_relations: Array = []

	# Intermediate binary files for checkpoint resume across process restarts
	var temp_nodes_path := out_db_path + ".nodes.tmp"
	var temp_coords_path := out_db_path + ".coords.tmp"
	var temp_rels_path := out_db_path + ".rels.tmp"
	var temp_nbr_nodes_path := out_db_path + ".nbrs.tmp"

	var start_pass := cur_state_pass.to_int()

	# =========================================================
	# PRE-PASS: Collect node IDs inside clip rectangle (if clipping)
	# =========================================================
	var S := PackedInt64Array()
	var is_clipping := (clip_rect != null)
	var clip_min_x := -INF
	var clip_max_x := INF
	var clip_min_y := -INF
	var clip_max_y := INF
	if is_clipping:
		if clip_rect is Rect2:
			clip_min_x = clip_rect.position.x
			clip_max_x = clip_rect.position.x + clip_rect.size.x
			clip_min_y = clip_rect.position.y
			clip_max_y = clip_rect.position.y + clip_rect.size.y
		elif clip_rect is Dictionary:
			clip_min_x = float(clip_rect.get("min_x", -INF))
			clip_max_x = float(clip_rect.get("max_x", INF))
			clip_min_y = float(clip_rect.get("min_y", -INF))
			clip_max_y = float(clip_rect.get("max_y", INF))

		if start_pass < 1:
			print("--- Pre-pass: Streaming dense nodes for clip rectangle ---")
			var f_pre := FileAccess.open(pbf_path, FileAccess.READ)
			if not f_pre:
				store.close()
				return {"ok": false, "error": "Cannot open PBF file for pre-pass"}
			var file_size_pre := f_pre.get_length()
			var s_chunk := PackedInt64Array()
			const S_CHUNK_SIZE := 2000000

			while f_pre.get_position() < file_size_pre:
				if cancel_requested:
					f_pre.close()
					return _cleanup_cancel(out_db_path, store)
				_check_memory_pause()
				var blob := OsmPbfReader.read_blob_header_and_data(f_pre)
				if blob.is_empty():
					break
				if blob.get("type", "") != "OSMData":
					continue

				var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
				if decomp.is_empty():
					continue

				var pr := OsmPbfReader.ProtoReader.new(decomp)
				while pr.has_more():
					var tag := pr.read_varint()
					var fn := tag >> 3
					var wt := tag & 0x7
					if fn == 2 and wt == 2: # PrimitiveGroup
						var glen := pr.read_varint()
						var gr_end := pr.pos + glen
						while pr.pos < gr_end:
							var gtag := pr.read_varint()
							var gfn := gtag >> 3
							var gwt := gtag & 0x7
							if gfn == 2 and gwt == 2: # DenseNodes
								var dlen := pr.read_varint()
								var dend := pr.pos + dlen
								var id_deltas: Array[int] = []
								var lat_deltas: Array[int] = []
								var lon_deltas: Array[int] = []
								while pr.pos < dend:
									var dtag := pr.read_varint()
									var dfn := dtag >> 3
									var dwt := dtag & 0x7
									if dfn == 1 and dwt == 2:
										var l := pr.read_varint()
										var lend := pr.pos + l
										while pr.pos < lend:
											id_deltas.append(pr.read_sint64())
									elif dfn == 8 and dwt == 2:
										var l := pr.read_varint()
										var lend := pr.pos + l
										while pr.pos < lend:
											lat_deltas.append(pr.read_sint64())
									elif dfn == 9 and dwt == 2:
										var l := pr.read_varint()
										var lend := pr.pos + l
										while pr.pos < lend:
											lon_deltas.append(pr.read_sint64())
									elif dwt == 2:
										pr.skip(pr.read_varint())
									elif dwt == 0:
										pr.read_varint()

								var cur_id := 0
								var cur_lat := 0
								var cur_lon := 0
								for di in id_deltas.size():
									cur_id += id_deltas[di]
									cur_lat += lat_deltas[di]
									cur_lon += lon_deltas[di]
									var lat_f := float(cur_lat) * 1e-7
									var lon_f := float(cur_lon) * 1e-7
									var wm: Vector2 = Grid.latlon_to_wm(lat_f, lon_f)
									if wm.x >= clip_min_x and wm.x < clip_max_x and wm.y >= clip_min_y and wm.y < clip_max_y:
										s_chunk.append(cur_id)
										if s_chunk.size() >= S_CHUNK_SIZE:
											s_chunk.sort()
											s_chunk = _dedup_sorted(s_chunk)
											S = _merge_sorted_dedup(S, s_chunk)
											s_chunk = PackedInt64Array()
							elif gwt == 2:
								pr.skip(pr.read_varint())
							elif gwt == 0:
								pr.read_varint()
					elif wt == 2:
						pr.skip(pr.read_varint())
					elif wt == 0:
						pr.read_varint()
			f_pre.close()

			if not s_chunk.is_empty():
				s_chunk.sort()
				s_chunk = _dedup_sorted(s_chunk)
				S = _merge_sorted_dedup(S, s_chunk)
				s_chunk = PackedInt64Array()

			print("Pre-pass finished: %d nodes in clip rectangle" % S.size())

	# =========================================================
	# PASS 1: Scan relations and ways, collect needed node IDs
	# =========================================================
	if start_pass < 1:
		print("--- Pass 1: Scanning relations and ways ---")
		progress_updated.emit("convert", 1, 3)
		var f := FileAccess.open(pbf_path, FileAccess.READ)
		if not f:
			store.close()
			return {"ok": false, "error": "Cannot open PBF file"}

		var file_size := f.get_length()
		var id_chunk := PackedInt64Array()
		const ID_CHUNK_SIZE := 2000000

		var candidate_relations: Array = []
		var candidate_rel_way_ids: Dictionary = {}
		var rel_way_refs: Dictionary = {}
		var rel_ways_in_clip: Dictionary = {}

		# Step 1A: Scan relations first to collect candidate multipolygons and their member way IDs
		while f.get_position() < file_size:
			if cancel_requested:
				f.close()
				return _cleanup_cancel(out_db_path, store)
			_check_memory_pause()
			var blob := OsmPbfReader.read_blob_header_and_data(f)
			if blob.is_empty():
				break
			if blob.get("type", "") != "OSMData":
				continue

			var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
			if decomp.is_empty():
				continue

			var pr := OsmPbfReader.ProtoReader.new(decomp)
			var string_table: Array[String] = []

			while pr.has_more():
				var tag := pr.read_varint()
				var fn := tag >> 3
				var wt := tag & 0x7

				if fn == 1 and wt == 2:
					var st_len := pr.read_varint()
					string_table = OsmPbfReader.decode_string_table(pr, st_len)
				elif fn == 2 and wt == 2:
					var glen := pr.read_varint()
					var gr_end := pr.pos + glen
					while pr.pos < gr_end:
						var gtag := pr.read_varint()
						var gfn := gtag >> 3
						var gwt := gtag & 0x7
						if gfn == 4 and gwt == 2: # Relation
							var rlen := pr.read_varint()
							var rend := pr.pos + rlen
							var rid := 0
							var r_keys: Array[int] = []
							var r_vals: Array[int] = []
							var r_roles: Array[int] = []
							var r_memids: Array[int] = []
							var r_types: Array[int] = []
							while pr.pos < rend:
								var rtag := pr.read_varint()
								var rfn := rtag >> 3
								var rwt := rtag & 0x7
								if rfn == 1 and rwt == 0:
									rid = pr.read_varint()
								elif rfn == 2 and rwt == 2:
									var kl := pr.read_varint()
									var kend := pr.pos + kl
									while pr.pos < kend:
										r_keys.append(pr.read_varint())
								elif rfn == 3 and rwt == 2:
									var vl := pr.read_varint()
									var vend := pr.pos + vl
									while pr.pos < vend:
										r_vals.append(pr.read_varint())
								elif rfn == 8 and rwt == 2:
									var sl := pr.read_varint()
									var send := pr.pos + sl
									while pr.pos < send:
										r_roles.append(pr.read_varint())
								elif rfn == 9 and rwt == 2:
									var ml := pr.read_varint()
									var mend := pr.pos + ml
									var cur_mid := 0
									while pr.pos < mend:
										cur_mid += pr.read_sint64()
										r_memids.append(cur_mid)
								elif rfn == 10 and rwt == 2:
									var tl := pr.read_varint()
									var tend := pr.pos + tl
									while pr.pos < tend:
										r_types.append(pr.read_varint())
								elif rwt == 2:
									pr.skip(pr.read_varint())
								elif rwt == 0:
									pr.read_varint()

							var tags := {}
							for k_i in r_keys.size():
								var k_str := string_table[r_keys[k_i]] if k_i < r_keys.size() and r_keys[k_i] < string_table.size() else ""
								var v_str := string_table[r_vals[k_i]] if k_i < r_vals.size() and r_vals[k_i] < string_table.size() else ""
								tags[k_str] = v_str

							var is_multi: bool = (tags.get("type", "") == "multipolygon")
							var is_boundary: bool = (tags.get("type", "") == "boundary" or tags.has("boundary"))
							var is_admin_sub: bool = (tags.get("boundary", "") == "administrative" and str(tags.get("admin_level", "")) in ["9", "10"])

							if is_multi or is_boundary or is_admin_sub:
								var members := []
								for m_i in r_memids.size():
									var m_type: int = r_types[m_i] if m_i < r_types.size() else 0
									var m_role: String = string_table[r_roles[m_i]] if m_i < r_roles.size() and r_roles[m_i] < string_table.size() else ""
									var m_id: int = r_memids[m_i]
									if m_type == 1: # WAY
										candidate_rel_way_ids[m_id] = true
										members.append({"id": m_id, "role": m_role})
								candidate_relations.append({
									"id": rid,
									"tags": tags,
									"members": members
								})
						elif gwt == 2:
							pr.skip(pr.read_varint())
						elif gwt == 0:
							pr.read_varint()
				elif wt == 2:
					pr.skip(pr.read_varint())
				elif wt == 0:
					pr.read_varint()

		# Step 1B: Rewind and scan ways
		f.seek(0)
		while f.get_position() < file_size:
			if cancel_requested:
				f.close()
				return _cleanup_cancel(out_db_path, store)
			_check_memory_pause()
			var blob := OsmPbfReader.read_blob_header_and_data(f)
			if blob.is_empty():
				break
			if blob.get("type", "") != "OSMData":
				continue

			var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
			if decomp.is_empty():
				continue

			var pr := OsmPbfReader.ProtoReader.new(decomp)
			var string_table: Array[String] = []

			while pr.has_more():
				var tag := pr.read_varint()
				var fn := tag >> 3
				var wt := tag & 0x7

				if fn == 1 and wt == 2:
					var st_len := pr.read_varint()
					string_table = OsmPbfReader.decode_string_table(pr, st_len)
				elif fn == 2 and wt == 2:
					var glen := pr.read_varint()
					var gr_end := pr.pos + glen
					while pr.pos < gr_end:
						var gtag := pr.read_varint()
						var gfn := gtag >> 3
						var gwt := gtag & 0x7
						if gfn == 3 and gwt == 2: # Way
							var wlen := pr.read_varint()
							var wend := pr.pos + wlen
							var wid := 0
							var w_keys: Array[int] = []
							var w_vals: Array[int] = []
							var w_refs: Array[int] = []
							while pr.pos < wend:
								var wtag := pr.read_varint()
								var wfn := wtag >> 3
								var wwt := wtag & 0x7
								if wfn == 1 and wwt == 0:
									wid = pr.read_varint()
								elif wfn == 2 and wwt == 2:
									var kl := pr.read_varint()
									var kend := pr.pos + kl
									while pr.pos < kend:
										w_keys.append(pr.read_varint())
								elif wfn == 3 and wwt == 2:
									var vl := pr.read_varint()
									var vend := pr.pos + vl
									while pr.pos < vend:
										w_vals.append(pr.read_varint())
								elif wfn == 8 and wwt == 2:
									var rl := pr.read_varint()
									var rend := pr.pos + rl
									var cur_ref := 0
									while pr.pos < rend:
										cur_ref += pr.read_sint64()
										w_refs.append(cur_ref)
								elif wwt == 2:
									pr.skip(pr.read_varint())
								elif wwt == 0:
									pr.read_varint()

							var has_standalone_tags := false
							var is_coastline := false
							for k_i in w_keys.size():
								var k_str := string_table[w_keys[k_i]] if k_i < w_keys.size() and w_keys[k_i] < string_table.size() else ""
								var v_str := string_table[w_vals[k_i]] if k_i < w_vals.size() and w_vals[k_i] < string_table.size() else ""
								if k_str == "natural" and v_str == "coastline":
									is_coastline = true
									has_standalone_tags = true
									break
								elif k_str in ["highway", "waterway", "building", "leisure", "natural", "water", "amenity", "railway", "footway", "cycleway", "service", "indoor"]:
									has_standalone_tags = true
									break
								elif k_str == "landuse":
									var v_str2 := string_table[w_vals[k_i]] if k_i < w_vals.size() and w_vals[k_i] < string_table.size() else ""
									if v_str2 in ["grass", "meadow", "village_green", "recreation_ground", "forest", "farmland", "orchard", "vineyard", "allotments", "farmyard", "greenhouse_horticulture", "cemetery", "residential", "industrial", "commercial", "retail", "railway", "brownfield", "quarry", "reservoir", "basin"]:
										has_standalone_tags = true
										break

							var is_candidate_way: bool = candidate_rel_way_ids.has(wid)
							if is_clipping:
								var has_clip_node := false
								for r in w_refs:
									var idx := S.bsearch(r)
									if idx < S.size() and S[idx] == r:
										has_clip_node = true
										break
								if is_candidate_way:
									rel_way_refs[wid] = w_refs
									if has_clip_node:
										rel_ways_in_clip[wid] = true
								if is_coastline or (has_standalone_tags and has_clip_node):
									for r in w_refs:
										id_chunk.append(r)
									if id_chunk.size() >= ID_CHUNK_SIZE:
										id_chunk.sort()
										id_chunk = _dedup_sorted(id_chunk)
										needed_node_ids = _merge_sorted_dedup(needed_node_ids, id_chunk)
										id_chunk = PackedInt64Array()
							else:
								if is_candidate_way:
									rel_way_refs[wid] = w_refs
								if is_candidate_way or has_standalone_tags:
									for r in w_refs:
										id_chunk.append(r)
									if id_chunk.size() >= ID_CHUNK_SIZE:
										id_chunk.sort()
										id_chunk = _dedup_sorted(id_chunk)
										needed_node_ids = _merge_sorted_dedup(needed_node_ids, id_chunk)
										id_chunk = PackedInt64Array()
						elif gwt == 2:
							pr.skip(pr.read_varint())
						elif gwt == 0:
							pr.read_varint()
				elif wt == 2:
					pr.skip(pr.read_varint())
				elif wt == 0:
					pr.read_varint()

		f.close()

		# Resolve candidate relations
		for crel in candidate_relations:
			var keep_rel := false
			if is_clipping:
				for m in crel.members:
					if rel_ways_in_clip.has(m.id):
						keep_rel = true
						break
			else:
				keep_rel = true

			if keep_rel:
				kept_relations.append(crel)
				for m in crel.members:
					relation_way_ids[m.id] = true
					if is_clipping and rel_way_refs.has(m.id):
						for r in rel_way_refs[m.id]:
							id_chunk.append(r)
						if id_chunk.size() >= ID_CHUNK_SIZE:
							id_chunk.sort()
							id_chunk = _dedup_sorted(id_chunk)
							needed_node_ids = _merge_sorted_dedup(needed_node_ids, id_chunk)
							id_chunk = PackedInt64Array()

		# Flush remaining chunk into needed_node_ids
		if not id_chunk.is_empty():
			id_chunk.sort()
			id_chunk = _dedup_sorted(id_chunk)
			needed_node_ids = _merge_sorted_dedup(needed_node_ids, id_chunk)
			id_chunk = PackedInt64Array()
		needed_node_ids = _dedup_sorted(needed_node_ids)

		print("Pass 1 finished: %d needed nodes, %d kept relations" % [needed_node_ids.size(), kept_relations.size()])

		# Save checkpoint state to disk
		var nf := FileAccess.open(temp_nodes_path, FileAccess.WRITE)
		if nf:
			nf.store_64(needed_node_ids.size())
			for nid in needed_node_ids:
				nf.store_64(nid)
			nf.close()

		var rf := FileAccess.open(temp_rels_path, FileAccess.WRITE)
		if rf:
			rf.store_string(JSON.stringify(kept_relations))
			rf.close()

		store.set_state("pass", "1")
		if stop_after_pass == 1:
			store.close()
			return {"ok": true, "stopped_after_pass": 1}

	else:
		# Reload needed_node_ids and relations from temp files
		if FileAccess.file_exists(temp_nodes_path):
			var nf := FileAccess.open(temp_nodes_path, FileAccess.READ)
			if nf:
				var count := nf.get_64()
				needed_node_ids.resize(count)
				for idx in count:
					needed_node_ids[idx] = nf.get_64()
				nf.close()
		if FileAccess.file_exists(temp_rels_path):
			var rf := FileAccess.open(temp_rels_path, FileAccess.READ)
			if rf:
				var parsed = JSON.parse_string(rf.get_as_text())
				if typeof(parsed) == TYPE_ARRAY:
					kept_relations = []
					for r in parsed:
						var norm_members: Array = []
						for m in r.get("members", []):
							var m_id: int = int(m.get("id", 0))
							relation_way_ids[m_id] = true
							norm_members.append({"id": m_id, "role": str(m.get("role", ""))})
						kept_relations.append({
							"id": int(r.get("id", 0)),
							"tags": r.get("tags", {}),
							"members": norm_members
						})
				rf.close()

	# =========================================================
	# PASS 2: Stream DenseNodes, resolve needed coords & POIs
	# =========================================================
	node_lats.resize(needed_node_ids.size())
	node_lons.resize(needed_node_ids.size())

	if start_pass < 2:
		print("--- Pass 2: Streaming dense nodes ---")
		progress_updated.emit("convert", 2, 3)
		var f := FileAccess.open(pbf_path, FileAccess.READ)
		if not f:
			store.close()
			return {"ok": false, "error": "Cannot open PBF file for Pass 2"}

		var file_size := f.get_length()
		var poi_count := 0

		store.begin_transaction()

		while f.get_position() < file_size:
			if cancel_requested:
				store.rollback()
				f.close()
				return _cleanup_cancel(out_db_path, store)
			_check_memory_pause()
			var blob := OsmPbfReader.read_blob_header_and_data(f)
			if blob.is_empty():
				break
			if blob.get("type", "") != "OSMData":
				continue

			var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
			if decomp.is_empty():
				continue

			var pr := OsmPbfReader.ProtoReader.new(decomp)
			var string_table: Array[String] = []

			while pr.has_more():
				var tag := pr.read_varint()
				var fn := tag >> 3
				var wt := tag & 0x7

				if fn == 1 and wt == 2:
					var st_len := pr.read_varint()
					string_table = OsmPbfReader.decode_string_table(pr, st_len)
				elif fn == 2 and wt == 2:
					var glen := pr.read_varint()
					var gr_end := pr.pos + glen
					while pr.pos < gr_end:
						var gtag := pr.read_varint()
						var gfn := gtag >> 3
						var gwt := gtag & 0x7
						if gfn == 2 and gwt == 2: # DenseNodes
							var dlen := pr.read_varint()
							var dend := pr.pos + dlen
							var id_deltas: Array[int] = []
							var lat_deltas: Array[int] = []
							var lon_deltas: Array[int] = []
							var keys_vals: Array[int] = []

							while pr.pos < dend:
								var dtag := pr.read_varint()
								var dfn := dtag >> 3
								var dwt := dtag & 0x7
								if dfn == 1 and dwt == 2:
									var l := pr.read_varint()
									var lend := pr.pos + l
									while pr.pos < lend:
										id_deltas.append(pr.read_sint64())
								elif dfn == 8 and dwt == 2:
									var l := pr.read_varint()
									var lend := pr.pos + l
									while pr.pos < lend:
										lat_deltas.append(pr.read_sint64())
								elif dfn == 9 and dwt == 2:
									var l := pr.read_varint()
									var lend := pr.pos + l
									while pr.pos < lend:
										lon_deltas.append(pr.read_sint64())
								elif dfn == 10 and dwt == 2:
									var l := pr.read_varint()
									var lend := pr.pos + l
									while pr.pos < lend:
										keys_vals.append(pr.read_varint())
								elif dwt == 2:
									pr.skip(pr.read_varint())
								elif dwt == 0:
									pr.read_varint()

							# Unpack dense nodes
							var cur_id := 0
							var cur_lat := 0
							var cur_lon := 0
							var kv_idx := 0
							var total_dense := id_deltas.size()

							for i in total_dense:
								cur_id += id_deltas[i]
								cur_lat += lat_deltas[i]
								cur_lon += lon_deltas[i]

								# Check needed nodes
								var idx := needed_node_ids.bsearch(cur_id)
								if idx < needed_node_ids.size() and needed_node_ids[idx] == cur_id:
									node_lats[idx] = cur_lat
									node_lons[idx] = cur_lon

								# Collect tags for this dense node
								var tags := {}
								while kv_idx < keys_vals.size():
									var k_sid := keys_vals[kv_idx]
									kv_idx += 1
									if k_sid == 0:
										break
									var v_sid := keys_vals[kv_idx] if kv_idx < keys_vals.size() else 0
									kv_idx += 1
									var k_str := string_table[k_sid] if k_sid < string_table.size() else ""
									var v_str := string_table[v_sid] if v_sid < string_table.size() else ""
									tags[k_str] = v_str

								# Check POI category
								if not tags.is_empty():
									var cat := PoiMapping.resolve_category(tags)
									if cat != "":
										var keep_poi := true
										if is_clipping:
											var s_idx := S.bsearch(cur_id)
											keep_poi = (s_idx < S.size() and S[s_idx] == cur_id)
										if keep_poi:
											var lat_f := float(cur_lat) * 1e-7
											var lon_f := float(cur_lon) * 1e-7
											var cell := Grid.latlon_to_cell(lat_f, lon_f)
											var name := str(tags.get("name", ""))
											store.insert_place(cur_id, cell.x, cell.y, name, cat, lat_f, lon_f)
											poi_count += 1

									var place_tag := str(tags.get("place", ""))
									if place_tag in ["neighbourhood", "suburb", "quarter"]:
										var lat_f := float(cur_lat) * 1e-7
										var lon_f := float(cur_lon) * 1e-7
										var name := str(tags.get("name", ""))
										var wm_pt := Grid.latlon_to_wm(lat_f, lon_f)
										neighbourhood_nodes.append({
											"id": cur_id,
											"name": name,
											"lat": lat_f,
											"lon": lon_f,
											"wm": wm_pt,
											"wm_x": wm_pt.x,
											"wm_y": wm_pt.y
										})
						elif gwt == 2:
							pr.skip(pr.read_varint())
						elif gwt == 0:
							pr.read_varint()
				elif wt == 2:
					pr.skip(pr.read_varint())
				elif wt == 0:
					pr.read_varint()

		store.commit()
		f.close()

		# Save coordinates checkpoint
		var cf := FileAccess.open(temp_coords_path, FileAccess.WRITE)
		if cf:
			cf.store_64(node_lats.size())
			for i in node_lats.size():
				cf.store_32(node_lats[i])
				cf.store_32(node_lons[i])
			cf.close()

		var nbf := FileAccess.open(temp_nbr_nodes_path, FileAccess.WRITE)
		if nbf:
			nbf.store_string(JSON.stringify(neighbourhood_nodes))
			nbf.close()

		store.set_state("pass", "2")
		print("Pass 2 finished: resolved coords, %d POIs inserted" % poi_count)

		if stop_after_pass == 2:
			store.close()
			return {"ok": true, "stopped_after_pass": 2}
	else:
		if FileAccess.file_exists(temp_coords_path):
			var cf := FileAccess.open(temp_coords_path, FileAccess.READ)
			if cf:
				var count := cf.get_64()
				node_lats.resize(count)
				node_lons.resize(count)
				for i in count:
					node_lats[i] = cf.get_32()
					node_lons[i] = cf.get_32()
				cf.close()
		if FileAccess.file_exists(temp_nbr_nodes_path):
			var nbf := FileAccess.open(temp_nbr_nodes_path, FileAccess.READ)
			if nbf:
				var parsed_nbrs = JSON.parse_string(nbf.get_as_text())
				if typeof(parsed_nbrs) == TYPE_ARRAY:
					neighbourhood_nodes = []
					for item in parsed_nbrs:
						neighbourhood_nodes.append({
							"id": int(item.get("id", 0)),
							"name": str(item.get("name", "")),
							"lat": float(item.get("lat", 0.0)),
							"lon": float(item.get("lon", 0.0)),
							"wm": Vector2(float(item.get("wm_x", 0.0)), float(item.get("wm_y", 0.0)))
						})
				nbf.close()

	# =========================================================
	# PASS 3: Assemble way geometries, rings & multipolygons
	# =========================================================
	print("--- Pass 3: Assembling geometries and writing map store ---")
	progress_updated.emit("convert", 3, 3)
	var f := FileAccess.open(pbf_path, FileAccess.READ)
	if not f:
		store.close()
		return {"ok": false, "error": "Cannot open PBF file for Pass 3"}

	var file_size := f.get_length()
	var resolved_ways: Dictionary = {} # way_id -> PackedVector2Array (Web-Mercator) for relation members
	var batch_count := 0
	store.begin_transaction()

	while f.get_position() < file_size:
		if cancel_requested:
			store.rollback()
			f.close()
			return _cleanup_cancel(out_db_path, store)
		_check_memory_pause()
		var blob := OsmPbfReader.read_blob_header_and_data(f)
		if blob.is_empty():
			break
		if blob.get("type", "") != "OSMData":
			continue

		var decomp: PackedByteArray = blob.get("decompressed", PackedByteArray())
		if decomp.is_empty():
			continue

		var pr := OsmPbfReader.ProtoReader.new(decomp)
		var string_table: Array[String] = []

		while pr.has_more():
			var tag := pr.read_varint()
			var fn := tag >> 3
			var wt := tag & 0x7

			if fn == 1 and wt == 2:
				var st_len := pr.read_varint()
				string_table = OsmPbfReader.decode_string_table(pr, st_len)
			elif fn == 2 and wt == 2:
				var glen := pr.read_varint()
				var gr_end := pr.pos + glen
				while pr.pos < gr_end:
					var gtag := pr.read_varint()
					var gfn := gtag >> 3
					var gwt := gtag & 0x7
					if gfn == 3 and gwt == 2: # Way
						var wlen := pr.read_varint()
						var wend := pr.pos + wlen
						var wid := 0
						var w_keys: Array[int] = []
						var w_vals: Array[int] = []
						var w_refs: Array[int] = []
						while pr.pos < wend:
							var wtag := pr.read_varint()
							var wfn := wtag >> 3
							var wwt := wtag & 0x7
							if wfn == 1 and wwt == 0:
								wid = pr.read_varint()
							elif wfn == 2 and wwt == 2:
								var kl := pr.read_varint()
								var kend := pr.pos + kl
								while pr.pos < kend:
									w_keys.append(pr.read_varint())
							elif wfn == 3 and wwt == 2:
								var vl := pr.read_varint()
								var vend := pr.pos + vl
								while pr.pos < vend:
									w_vals.append(pr.read_varint())
							elif wfn == 8 and wwt == 2:
								var rl := pr.read_varint()
								var rend := pr.pos + rl
								var cur_ref := 0
								while pr.pos < rend:
									cur_ref += pr.read_sint64()
									w_refs.append(cur_ref)
							elif wwt == 2:
								pr.skip(pr.read_varint())
							elif wwt == 0:
								pr.read_varint()

						var tags := {}
						for k_i in w_keys.size():
							var k_str := string_table[w_keys[k_i]] if w_keys[k_i] < string_table.size() else ""
							var v_str := string_table[w_vals[k_i]] if w_vals[k_i] < string_table.size() else ""
							tags[k_str] = v_str

						# Resolve way vertices in Web-Mercator
						var wm_pts := PackedVector2Array()
						var all_nodes_resolved := true
						for ref in w_refs:
							var idx := needed_node_ids.bsearch(ref)
							if idx < needed_node_ids.size() and needed_node_ids[idx] == ref:
								var lat_f := float(node_lats[idx]) * 1e-7
								var lon_f := float(node_lons[idx]) * 1e-7
								wm_pts.append(Grid.latlon_to_wm(lat_f, lon_f))
							else:
								all_nodes_resolved = false
								break

						if not all_nodes_resolved or wm_pts.is_empty():
							continue

						# If this way belongs to a relation, cache its Web-Mercator geometry
						if relation_way_ids.has(wid):
							resolved_ways[wid] = wm_pts

						# Determine if way is a standalone polygon or line
						var poly_info := classify_polygon(tags)
						var line_info := classify_line(tags)

						if not poly_info.is_empty() and wm_pts.size() >= 3:
							_write_poly_feature(store, poly_info["kind"], [wm_pts], poly_info["subkind"], poly_info["name"])
							batch_count += 1
						elif not line_info.is_empty() and wm_pts.size() >= 2:
							_write_line_feature(store, line_info["kind"], wm_pts, line_info["subkind"])
							batch_count += 1

						if batch_count >= 10000:
							store.commit()
							store.begin_transaction()
							batch_count = 0

					elif gwt == 2:
						pr.skip(pr.read_varint())
					elif gwt == 0:
						pr.read_varint()
			elif wt == 2:
				pr.skip(pr.read_varint())
			elif wt == 0:
				pr.read_varint()

	# Assemble and write kept multipolygon and boundary relations
	for rel in kept_relations:
		var tags: Dictionary = rel.get("tags", {})
		var members: Array = rel.get("members", [])
		var outer_way_pts: Array = []
		var inner_way_pts: Array = []

		for m in members:
			var wid: int = int(m.get("id", 0))
			var role: String = str(m.get("role", ""))
			if resolved_ways.has(wid):
				var w_pts: PackedVector2Array = resolved_ways[wid]
				if role == "inner":
					inner_way_pts.append(w_pts)
				else:
					outer_way_pts.append(w_pts)

		if outer_way_pts.is_empty():
			continue

		var outer_rings := stitch_ways_to_rings(outer_way_pts)
		var inner_rings := stitch_ways_to_rings(inner_way_pts)

		if outer_rings.is_empty():
			continue

		var is_admin_sub: bool = (tags.get("boundary", "") == "administrative" and str(tags.get("admin_level", "")) in ["9", "10"])
		if is_admin_sub:
			admin_neighbourhood_relations.append({
				"id": int(rel.get("id", 0)),
				"name": str(tags.get("name", "")),
				"poly": outer_rings[0]
			})

		var poly_info := classify_polygon(tags)
		if poly_info.is_empty():
			continue

		var all_rings: Array[PackedVector2Array] = []
		all_rings.append_array(outer_rings)
		all_rings.append_array(inner_rings)
		_write_poly_feature(store, poly_info["kind"], all_rings, poly_info["subkind"], poly_info["name"])
		batch_count += 1

	store.commit()
	f.close()

	store.set_state("pass", "completed")

	# Record coverage & clip state (§5.5 rule 5)
	var cov_rect := Rect2i(0, 0, 1, 1)
	if is_clipping:
		store.set_state("clip", "1")
		var c_min_cx := int(floor(clip_min_x / Grid.CELL_WM))
		var c_min_cy := int(floor(clip_min_y / Grid.CELL_WM))
		var c_max_cx := int(ceil(clip_max_x / Grid.CELL_WM)) - 1
		var c_max_cy := int(ceil(clip_max_y / Grid.CELL_WM)) - 1
		if coverage_box != null and coverage_box is Array and coverage_box.size() >= 4:
			c_min_cx = coverage_box[0]
			c_min_cy = coverage_box[1]
			c_max_cx = coverage_box[2]
			c_max_cy = coverage_box[3]
		elif coverage_box != null and coverage_box is Dictionary:
			c_min_cx = coverage_box.get("min_cx", c_min_cx)
			c_min_cy = coverage_box.get("min_cy", c_min_cy)
			c_max_cx = coverage_box.get("max_cx", c_max_cx)
			c_max_cy = coverage_box.get("max_cy", c_max_cy)
		store.set_state("coverage", "%d,%d,%d,%d" % [c_min_cx, c_min_cy, c_max_cx, c_max_cy])
		cov_rect = Rect2i(c_min_cx, c_min_cy, c_max_cx - c_min_cx + 1, c_max_cy - c_min_cy + 1)
	else:
		# Unclipped: bounding box of all written features
		var min_cx := INF
		var min_cy := INF
		var max_cx := -INF
		var max_cy := -INF
		for q in [
			"SELECT min(cell_x) AS min_cx, min(cell_y) AS min_cy, max(cell_x) AS max_cx, max(cell_y) AS max_cy FROM features_poly;",
			"SELECT min(cell_x) AS min_cx, min(cell_y) AS min_cy, max(cell_x) AS max_cx, max(cell_y) AS max_cy FROM features_line;",
			"SELECT min(cell_x) AS min_cx, min(cell_y) AS min_cy, max(cell_x) AS max_cx, max(cell_y) AS max_cy FROM place_nodes;"
		]:
			var r = store._rows(q)
			if not r.is_empty() and r[0]["min_cx"] != null:
				min_cx = minf(min_cx, float(r[0]["min_cx"]))
				min_cy = minf(min_cy, float(r[0]["min_cy"]))
				max_cx = maxf(max_cx, float(r[0]["max_cx"]))
				max_cy = maxf(max_cy, float(r[0]["max_cy"]))
		if min_cx != INF:
			store.set_state("coverage", "%d,%d,%d,%d" % [int(min_cx), int(min_cy), int(max_cx), int(max_cy)])
			cov_rect = Rect2i(int(min_cx), int(min_cy), int(max_cx) - int(min_cx) + 1, int(max_cy) - int(min_cy) + 1)
		else:
			store.set_state("coverage", "0,0,0,0")
			cov_rect = Rect2i(0, 0, 1, 1)
		store.set_state("clip", "0")

	# Populate areas and area_cells (schema v4)
	if not place_id.is_empty() and not place_poly.is_empty():
		var city_neighbourhood_nodes: Array = []
		for nn in neighbourhood_nodes:
			if ring_contains_point(place_poly, nn["wm"]):
				city_neighbourhood_nodes.append(nn)
		city_neighbourhood_nodes.sort_custom(func(a, b): return a["id"] < b["id"])
		admin_neighbourhood_relations.sort_custom(func(a, b): return a["id"] < b["id"])

		var neighbourhood_counts: Dictionary = {}
		var neighbourhood_names: Dictionary = {}
		var assigned_cells: Dictionary = {}
		var total_inside_cells := 0

		var cov_min_cx := cov_rect.position.x
		var cov_min_cy := cov_rect.position.y
		var cov_max_cx := cov_rect.position.x + cov_rect.size.x - 1
		var cov_max_cy := cov_rect.position.y + cov_rect.size.y - 1

		for cy in range(cov_min_cy, cov_max_cy + 1):
			for cx in range(cov_min_cx, cov_max_cx + 1):
				var c_center := Vector2((float(cx) + 0.5) * Grid.CELL_WM, (float(cy) + 0.5) * Grid.CELL_WM)
				if not ring_contains_point(place_poly, c_center):
					continue

				total_inside_cells += 1

				if place_kind == "site":
					assigned_cells[Vector2i(cx, cy)] = place_id
				else: # city
					var assigned_key := ""
					var assigned_name := ""

					# (a) Admin 9 or 10 relation containing it (lower id first)
					for ar in admin_neighbourhood_relations:
						if ring_contains_point(ar["poly"], c_center):
							assigned_key = "osm:r%d" % ar["id"]
							assigned_name = ar["name"]
							break

					# (b) Else nearest neighbourhood node inside city (WM-m distance; ties to lower id)
					if assigned_key == "" and not city_neighbourhood_nodes.is_empty():
						var best_dist_sq := INF
						var best_id := -1
						var best_name := ""
						for nn in city_neighbourhood_nodes:
							var d2: float = (nn["wm"] - c_center).length_squared()
							if d2 < best_dist_sq or (is_equal_approx(d2, best_dist_sq) and (best_id == -1 or nn["id"] < best_id)):
								best_dist_sq = d2
								best_id = nn["id"]
								best_name = nn["name"]
						if best_id != -1:
							assigned_key = "osm:n%d" % best_id
							assigned_name = best_name

					# (c) Else grid fallback: grid:<city_id>:<floor(cx/4)>:<floor(cy/4)>
					if assigned_key == "":
						var gx := floori(float(cx) / 4.0)
						var gy := floori(float(cy) / 4.0)
						assigned_key = "grid:%s:%d:%d" % [place_id, gx, gy]
						assigned_name = ""

					assigned_cells[Vector2i(cx, cy)] = assigned_key
					neighbourhood_counts[assigned_key] = int(neighbourhood_counts.get(assigned_key, 0)) + 1
					neighbourhood_names[assigned_key] = assigned_name

		store.begin_transaction()
		if place_kind == "site":
			store.insert_area(place_id, "site", place_name, total_inside_cells)
			for c in assigned_cells.keys():
				store.insert_area_cell(c.x, c.y, place_id)
		else: # city
			store.insert_area(place_id, "city", place_name, total_inside_cells)
			for a_key in neighbourhood_counts.keys():
				store.insert_area(a_key, "neighbourhood", neighbourhood_names.get(a_key, ""), neighbourhood_counts[a_key])
			for c in assigned_cells.keys():
				store.insert_area_cell(c.x, c.y, assigned_cells[c])
		store.commit()

	store.set_state("schema_version", "4")
	if not place_id.is_empty():
		store.set_state("place_id", place_id)
		store.set_state("snapshot", MapConstants.MAP_SNAPSHOT)

	_compute_and_write_sea_flags(store, cov_rect)

	# Clean up temporary index files
	if FileAccess.file_exists(temp_nodes_path):
		DirAccess.remove_absolute(temp_nodes_path)
	if FileAccess.file_exists(temp_coords_path):
		DirAccess.remove_absolute(temp_coords_path)
	if FileAccess.file_exists(temp_rels_path):
		DirAccess.remove_absolute(temp_rels_path)
	if FileAccess.file_exists(temp_nbr_nodes_path):
		DirAccess.remove_absolute(temp_nbr_nodes_path)
	if FileAccess.file_exists(temp_poly_path):
		DirAccess.remove_absolute(temp_poly_path)

	var h := store.canonical_dump_sha256()
	var elapsed := Time.get_ticks_msec() - t0

	var p_rows: int = int(store._rows("SELECT count(*) as c FROM features_poly;")[0]["c"])
	var l_rows: int = int(store._rows("SELECT count(*) as c FROM features_line;")[0]["c"])
	var n_rows: int = int(store._rows("SELECT count(*) as c FROM place_nodes;")[0]["c"])

	print("Conversion completed in %.2f s: %d poly, %d line, %d place_nodes; canonical SHA-256: %s" % [
		float(elapsed) / 1000.0, p_rows, l_rows, n_rows, h
	])

	store.close()
	return {
		"ok": true,
		"features_poly": p_rows,
		"features_line": l_rows,
		"place_nodes": n_rows,
		"canonical_hash": h,
		"time_ms": elapsed
	}

# -------------------------------------------------------------
# Spatial Assignment & Writing
# -------------------------------------------------------------

static func classify_polygon(tags: Dictionary) -> Dictionary:
	var name: String = str(tags.get("name", ""))

	# 1. building: building=* except building=no; building:part is ignored
	if tags.has("building"):
		if tags.has("building:part"):
			return {}
		var b_val: String = str(tags["building"])
		if b_val != "no":
			return {"kind": "building", "subkind": b_val, "name": name}

	# 2. water: natural=water, water=*, waterway=riverbank, landuse=reservoir, landuse=basin
	var is_water := false
	if tags.get("natural", "") == "water":
		is_water = true
	elif tags.has("water"):
		is_water = true
	elif tags.get("waterway", "") == "riverbank":
		is_water = true
	elif tags.get("landuse", "") in ["reservoir", "basin"]:
		is_water = true
	if is_water:
		return {"kind": "water", "subkind": "", "name": name}

	# 3. wetland: natural=wetland
	if tags.get("natural", "") == "wetland":
		return {"kind": "wetland", "subkind": "", "name": name}

	# 4. sand: natural=beach, natural=sand
	if tags.get("natural", "") in ["beach", "sand"]:
		return {"kind": "sand", "subkind": "", "name": name}

	# 5. cemetery: landuse=cemetery, amenity=grave_yard
	if tags.get("landuse", "") == "cemetery" or tags.get("amenity", "") == "grave_yard":
		return {"kind": "cemetery", "subkind": "", "name": name}

	# 6. park: leisure or landuse
	var leisure_val: String = str(tags.get("leisure", ""))
	if leisure_val in ["park", "garden", "recreation_ground", "playground", "pitch", "nature_reserve", "dog_park", "golf_course", "common"]:
		return {"kind": "park", "subkind": leisure_val, "name": name}
	var lu_val: String = str(tags.get("landuse", ""))
	if lu_val in ["grass", "village_green", "recreation_ground", "meadow"]:
		return {"kind": "park", "subkind": lu_val, "name": name}

	# 7. forest: landuse=forest, natural=wood
	if lu_val == "forest" or tags.get("natural", "") == "wood":
		return {"kind": "forest", "subkind": "", "name": name}

	# 8. scrub: natural=scrub|heath|grassland
	if tags.get("natural", "") in ["scrub", "heath", "grassland"]:
		return {"kind": "scrub", "subkind": "", "name": name}

	# 9. farmland: landuse=farmland|orchard|vineyard|allotments|farmyard|greenhouse_horticulture
	if lu_val in ["farmland", "orchard", "vineyard", "allotments", "farmyard", "greenhouse_horticulture"]:
		return {"kind": "farmland", "subkind": "", "name": name}

	# 10. parking: amenity=parking
	if tags.get("amenity", "") == "parking":
		return {"kind": "parking", "subkind": "", "name": name}

	# 11. residential: landuse=residential
	if lu_val == "residential":
		return {"kind": "residential", "subkind": "", "name": name}

	# 12. commercial: landuse=commercial|retail
	if lu_val in ["commercial", "retail"]:
		return {"kind": "commercial", "subkind": "", "name": name}

	# 13. industrial: landuse=industrial|railway|brownfield|quarry (construction excluded per Decision 20)
	if lu_val in ["industrial", "railway", "brownfield", "quarry"]:
		return {"kind": "industrial", "subkind": "", "name": name}

	return {}

static func classify_line(tags: Dictionary) -> Dictionary:
	var is_coastline: bool = (str(tags.get("natural", "")) == "coastline")
	if is_coastline:
		return {"kind": "coastline", "subkind": ""}

	# Exclusions: tunnel!=no, covered=yes, layer < 0
	if tags.has("tunnel") and str(tags["tunnel"]) != "no":
		return {}
	if str(tags.get("covered", "")) == "yes":
		return {}
	if tags.has("layer"):
		var l_val := str(tags["layer"]).to_int()
		if l_val < 0:
			return {}

	var is_bridge: bool = (tags.has("bridge") and str(tags["bridge"]) != "no")

	# Highway
	if tags.has("highway"):
		if tags.get("area", "") == "yes":
			return {}
		var hw: String = str(tags["highway"])
		if hw in ["proposed", "construction", "platform", "corridor", "elevator", "bus_stop", "raceway"]:
			return {}

		# Section 10.1 exclusions
		if hw == "service":
			return {}
		var fw: String = str(tags.get("footway", ""))
		if fw in ["sidewalk", "crossing", "traffic_island", "access_aisle", "link"]:
			return {}
		if hw == "cycleway":
			var cw: String = str(tags.get("cycleway", ""))
			if cw in ["crossing", "sidewalk"]:
				return {}
		if hw in ["footway", "path", "pedestrian"]:
			if str(tags.get("indoor", "")) == "yes":
				return {}

		var subk := hw
		if is_bridge:
			subk += ":bridge"

		if hw in ["motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street", "road"] or hw.ends_with("_link"):
			return {"kind": "road", "subkind": subk}
		elif hw in ["footway", "path", "cycleway", "pedestrian", "track", "steps", "bridleway"]:
			return {"kind": "path", "subkind": subk}

	# Railway
	if tags.has("railway"):
		var rw: String = str(tags["railway"])
		if rw in ["abandoned", "disused", "subway", "proposed", "construction"]:
			return {}
		var subk := rw
		if is_bridge:
			subk += ":bridge"
		if rw in ["rail", "light_rail", "narrow_gauge", "tram"]:
			return {"kind": "rail", "subkind": subk}

	# Waterway
	if tags.has("waterway"):
		var ww: String = str(tags["waterway"])
		if ww in ["river", "canal", "stream", "ditch", "drain"]:
			return {"kind": "waterway", "subkind": ww}

	return {}

static func _polygon_area(pts: PackedVector2Array) -> float:
	var n := pts.size()
	if n < 3:
		return 0.0
	var a := 0.0
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return absf(a) * 0.5

static func _quantize_wm(v: Vector2) -> Vector2i:
	return Vector2i(int(round(v.x * 100.0)), int(round(v.y * 100.0)))

func _compute_and_write_sea_flags(store: MapStore, cov_box: Rect2i) -> void:
	var coast_rows = store._rows("SELECT cell_x, cell_y, geom_pts FROM features_line WHERE kind = 'coastline';")
	var coast_by_cell: Dictionary = {}
	var all_segments: Array = []
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}

	for row in coast_rows:
		var cx: int = int(row["cell_x"])
		var cy: int = int(row["cell_y"])
		var origin := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
		var pts := MapStore.unpack_pts(row["geom_pts"])
		if pts.size() < 2:
			continue
		for i in range(pts.size() - 1):
			var a := origin + pts[i] * MapStore.GEOM_UNIT_WM
			var b := origin + pts[i + 1] * MapStore.GEOM_UNIT_WM
			if (b - a).length_squared() < 1e-6:
				continue
			var seg = [a, b]
			all_segments.append(seg)
			var cell_key := Vector2i(cx, cy)
			if not coast_by_cell.has(cell_key):
				coast_by_cell[cell_key] = []
			coast_by_cell[cell_key].append(seg)
			incoming[_quantize_wm(b)] = a
			outgoing[_quantize_wm(a)] = b

	store.begin_transaction()
	for cy in range(cov_box.position.y, cov_box.position.y + cov_box.size.y):
		for cx in range(cov_box.position.x, cov_box.position.x + cov_box.size.x):
			# 2. Cell with coastline segment in itself or 8 neighbours -> sea = 2 (coast)
			var is_coast := false
			for ndy in [-1, 0, 1]:
				for ndx in [-1, 0, 1]:
					if coast_by_cell.has(Vector2i(cx + ndx, cy + ndy)):
						is_coast = true
						break
				if is_coast:
					break
			if is_coast:
				store.insert_cell_flag(cx, cy, 2)
				continue

			if all_segments.is_empty():
				store.insert_cell_flag(cx, cy, 0)
				continue

			# 3. Search rings r = 1 ... 64
			var cell_center := Vector2((float(cx) + 0.5) * Grid.CELL_WM, (float(cy) + 0.5) * Grid.CELL_WM)
			var found_ring := -1
			var candidate_segments: Array = []

			for r in range(1, 65):
				var ring_has := false
				for d in range(-r, r + 1):
					for cand in [
						Vector2i(cx + d, cy - r),
						Vector2i(cx + d, cy + r),
						Vector2i(cx - r, cy + d),
						Vector2i(cx + r, cy + d)
					]:
						if coast_by_cell.has(cand):
							ring_has = true
							for s in coast_by_cell[cand]:
								candidate_segments.append(s)
				if ring_has:
					found_ring = r
					break

			if found_ring == -1 or candidate_segments.is_empty():
				store.insert_cell_flag(cx, cy, 0)
				continue

			# Include candidate segments from ring r+1
			var r_next := found_ring + 1
			if r_next <= 64:
				for d in range(-r_next, r_next + 1):
					for cand in [
						Vector2i(cx + d, cy - r_next),
						Vector2i(cx + d, cy + r_next),
						Vector2i(cx - r_next, cy + d),
						Vector2i(cx + r_next, cy + d)
					]:
						if coast_by_cell.has(cand):
							for s in coast_by_cell[cand]:
								candidate_segments.append(s)

			var min_dist_sq := INF
			var nearest_seg = null
			var nearest_t := 0.0

			for seg in candidate_segments:
				var sa: Vector2 = seg[0]
				var sb: Vector2 = seg[1]
				var ab := sb - sa
				var len_sq := ab.length_squared()
				var t := 0.0
				if len_sq > 1e-6:
					t = clampf((cell_center - sa).dot(ab) / len_sq, 0.0, 1.0)
				var proj := sa + ab * t
				var dist_sq := (cell_center - proj).length_squared()
				if dist_sq < min_dist_sq:
					min_dist_sq = dist_sq
					nearest_seg = seg
					nearest_t = t

			if nearest_seg == null:
				store.insert_cell_flag(cx, cy, 0)
				continue

			var na: Vector2 = nearest_seg[0]
			var nb: Vector2 = nearest_seg[1]
			var is_sea := false

			if nearest_t > 1e-4 and nearest_t < 1.0 - 1e-4:
				is_sea = (nb - na).cross(cell_center - na) < 0.0
			else:
				var v := na if nearest_t <= 1e-4 else nb
				var vk := _quantize_wm(v)
				if incoming.has(vk) and outgoing.has(vk):
					var u: Vector2 = incoming[vk]
					var w: Vector2 = outgoing[vk]
					is_sea = (w - u).cross(cell_center - v) < 0.0
				else:
					is_sea = (nb - na).cross(cell_center - na) < 0.0

			var sea_val := 1 if is_sea else 0
			store.insert_cell_flag(cx, cy, sea_val)
	store.commit()

func _write_poly_feature(store: MapStore, kind: String, rings: Array[PackedVector2Array], subkind: String = "", name: String = "") -> void:
	if rings.is_empty():
		return
	var outer := rings[0]
	if outer.size() < 3:
		return

	# Calculate bounding box of outer ring
	var min_wm := outer[0]
	var max_wm := outer[0]
	for p in outer:
		min_wm.x = minf(min_wm.x, p.x)
		min_wm.y = minf(min_wm.y, p.y)
		max_wm.x = maxf(max_wm.x, p.x)
		max_wm.y = maxf(max_wm.y, p.y)

	var center_wm := (min_wm + max_wm) * 0.5

	# Buildings: unclipped, stored in anchor cell (§2.3)
	if kind == "building":
		var anchor_cx := int(floor(center_wm.x / Grid.CELL_WM))
		var anchor_cy := int(floor(center_wm.y / Grid.CELL_WM))
		var cell_origin := Vector2(float(anchor_cx) * Grid.CELL_WM, float(anchor_cy) * Grid.CELL_WM)
		var local_rings: Array[PackedVector2Array] = []
		for ring in rings:
			var l_ring := PackedVector2Array()
			l_ring.resize(ring.size())
			for i in ring.size():
				l_ring[i] = (ring[i] - cell_origin) / MapStore.GEOM_UNIT_WM
			local_rings.append(l_ring)
		var blob := MapStore.pack_rings(local_rings)
		store.insert_poly(anchor_cx, anchor_cy, kind, blob, subkind, name)
		return

	# Other polygons: clipped per cell (§2.3)
	var c_min_x := int(floor(min_wm.x / Grid.CELL_WM))
	var c_max_x := int(floor(max_wm.x / Grid.CELL_WM))
	var c_min_y := int(floor(min_wm.y / Grid.CELL_WM))
	var c_max_y := int(floor(max_wm.y / Grid.CELL_WM))

	# Fast-path: Polygon completely in single cell
	if c_min_x == c_max_x and c_min_y == c_max_y:
		var cx := c_min_x
		var cy := c_min_y
		var cell_origin := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
		var local_rings: Array[PackedVector2Array] = []
		for ring in rings:
			var l_ring := PackedVector2Array()
			l_ring.resize(ring.size())
			for i in ring.size():
				l_ring[i] = (ring[i] - cell_origin) / MapStore.GEOM_UNIT_WM
			local_rings.append(l_ring)
		var blob := MapStore.pack_rings(local_rings)
		store.insert_poly(cx, cy, kind, blob, subkind, name)
		return

	# Spanning polygon: clip per cell
	var target_cx := int(floor(center_wm.x / Grid.CELL_WM))
	var target_cy := int(floor(center_wm.y / Grid.CELL_WM))

	var pieces := []
	var max_area := -1.0
	var max_piece_idx := -1

	for cy in range(c_min_y, c_max_y + 1):
		for cx in range(c_min_x, c_max_x + 1):
			var box_min := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
			var box_max := Vector2(float(cx + 1) * Grid.CELL_WM, float(cy + 1) * Grid.CELL_WM)
			var cell_local_rings: Array[PackedVector2Array] = []

			for ring in rings:
				var clipped := clip_polygon_to_box(ring, box_min, box_max)
				if clipped.size() >= 3:
					var l_ring := PackedVector2Array()
					l_ring.resize(clipped.size())
					for i in clipped.size():
						l_ring[i] = (clipped[i] - box_min) / MapStore.GEOM_UNIT_WM
					cell_local_rings.append(l_ring)

			if not cell_local_rings.is_empty() and cell_local_rings[0].size() >= 3:
				var blob := MapStore.pack_rings(cell_local_rings)
				var area := _polygon_area(cell_local_rings[0])
				var idx := pieces.size()
				pieces.append({
					"cx": cx,
					"cy": cy,
					"blob": blob,
					"area": area
				})
				if area > max_area:
					max_area = area
					max_piece_idx = idx
				elif absf(area - max_area) < 1e-6 and max_piece_idx >= 0:
					# Ties go to lowest (cell_y, cell_x)
					var prev = pieces[max_piece_idx]
					if cy < prev["cy"] or (cy == prev["cy"] and cx < prev["cx"]):
						max_piece_idx = idx

	if pieces.is_empty():
		return

	var named_piece_idx := -1
	if name != "":
		for i in pieces.size():
			if pieces[i]["cx"] == target_cx and pieces[i]["cy"] == target_cy:
				named_piece_idx = i
				break
		if named_piece_idx == -1:
			named_piece_idx = max_piece_idx

	for i in pieces.size():
		var p = pieces[i]
		var piece_name := name if i == named_piece_idx else ""
		store.insert_poly(p["cx"], p["cy"], kind, p["blob"], subkind, piece_name)

func _write_line_feature(store: MapStore, kind: String, wm_pts: PackedVector2Array, subkind: String = "") -> void:
	if wm_pts.size() < 2:
		return

	var min_wm := wm_pts[0]
	var max_wm := wm_pts[0]
	for p in wm_pts:
		min_wm.x = minf(min_wm.x, p.x)
		min_wm.y = minf(min_wm.y, p.y)
		max_wm.x = maxf(max_wm.x, p.x)
		max_wm.y = maxf(max_wm.y, p.y)

	var c_min_x := int(floor(min_wm.x / Grid.CELL_WM))
	var c_max_x := int(floor(max_wm.x / Grid.CELL_WM))
	var c_min_y := int(floor(min_wm.y / Grid.CELL_WM))
	var c_max_y := int(floor(max_wm.y / Grid.CELL_WM))

	# Fast-path: Line completely in single cell
	if c_min_x == c_max_x and c_min_y == c_max_y:
		var cx := c_min_x
		var cy := c_min_y
		var cell_origin := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
		var local_pts := PackedVector2Array()
		local_pts.resize(wm_pts.size())
		for i in wm_pts.size():
			local_pts[i] = (wm_pts[i] - cell_origin) / MapStore.GEOM_UNIT_WM
		var blob := MapStore.pack_pts(local_pts)
		store.insert_line(cx, cy, kind, blob, subkind)
		return

	# Spanning line: clip segments per cell
	for cy in range(c_min_y, c_max_y + 1):
		for cx in range(c_min_x, c_max_x + 1):
			var box_min := Vector2(float(cx) * Grid.CELL_WM, float(cy) * Grid.CELL_WM)
			var box_max := Vector2(float(cx + 1) * Grid.CELL_WM, float(cy + 1) * Grid.CELL_WM)
			var cell_pts := PackedVector2Array()

			for i in range(wm_pts.size() - 1):
				var seg := clip_segment_to_box(wm_pts[i], wm_pts[i + 1], box_min, box_max)
				if seg.size() == 2:
					var p0 := (seg[0] - box_min) / MapStore.GEOM_UNIT_WM
					var p1 := (seg[1] - box_min) / MapStore.GEOM_UNIT_WM
					if cell_pts.is_empty():
						cell_pts.append(p0)
						cell_pts.append(p1)
					else:
						if (cell_pts[cell_pts.size() - 1] - p0).length_squared() > 1e-6:
							cell_pts.append(p0)
						cell_pts.append(p1)

			if cell_pts.size() >= 2:
				var blob := MapStore.pack_pts(cell_pts)
				store.insert_line(cx, cy, kind, blob, subkind)

static func _dedup_sorted(arr: PackedInt64Array) -> PackedInt64Array:
	var n := arr.size()
	if n <= 1:
		return arr
	var out := PackedInt64Array()
	out.resize(n)
	var write_idx := 1
	var prev: int = arr[0]
	out[0] = prev
	for i in range(1, n):
		var v: int = arr[i]
		if v != prev:
			out[write_idx] = v
			prev = v
			write_idx += 1
	out.resize(write_idx)
	return out

static func _merge_sorted_dedup(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var na := a.size()
	var nb := b.size()
	if na == 0:
		return b
	if nb == 0:
		return a

	var out := PackedInt64Array()
	out.resize(na + nb)
	var i := 0
	var j := 0
	var k := 0
	var prev: int = -9223372036854775808
	var has_prev := false

	while i < na and j < nb:
		var va: int = a[i]
		var vb: int = b[j]
		var v: int
		if va < vb:
			v = va
			i += 1
		elif vb < va:
			v = vb
			j += 1
		else:
			v = va
			i += 1
			j += 1
		if not has_prev or v != prev:
			out[k] = v
			prev = v
			k += 1
			has_prev = true

	while i < na:
		var v: int = a[i]
		i += 1
		if not has_prev or v != prev:
			out[k] = v
			prev = v
			k += 1
			has_prev = true

	while j < nb:
		var v: int = b[j]
		j += 1
		if not has_prev or v != prev:
			out[k] = v
			prev = v
			k += 1
			has_prev = true

	out.resize(k)
	return out
