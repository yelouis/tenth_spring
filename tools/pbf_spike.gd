extends SceneTree

# tools/pbf_spike.gd — Pure-GDScript streaming OSM PBF reader speed and memory spike
# Implements streaming PBF parser per docs/design_memory_and_resources.md §3.1
# Reads blob by blob with FileAccess, bounding in-flight blocks to at most 4.

class ProtoReader:
	var buf: PackedByteArray
	var pos: int = 0
	var size: int = 0

	func _init(b: PackedByteArray):
		buf = b
		pos = 0
		size = b.size()

	func has_more() -> bool:
		return pos < size

	func read_varint() -> int:
		var res: int = 0
		var shift: int = 0
		while pos < size:
			var b: int = buf[pos]
			pos += 1
			res |= (b & 0x7F) << shift
			if (b & 0x80) == 0:
				return res
			shift += 7
			if shift >= 64:
				break
		return res

	func skip(n: int):
		pos = mini(pos + n, size)


static func _parse_primitive_block(decomp: PackedByteArray) -> Dictionary:
	var pr = ProtoReader.new(decomp)
	var nodes_count = 0
	var ways_count = 0
	var relations_count = 0

	while pr.has_more():
		var tag = pr.read_varint()
		var fn = tag >> 3
		var wt = tag & 0x7
		if fn == 2 and wt == 2: # PrimitiveGroup
			var glen = pr.read_varint()
			var gr_end = pr.pos + glen
			while pr.pos < gr_end:
				var gtag = pr.read_varint()
				var gfn = gtag >> 3
				var gwt = gtag & 0x7
				if gfn == 1 and gwt == 2: # nodes
					nodes_count += 1
					var nl = pr.read_varint()
					pr.skip(nl)
				elif gfn == 2 and gwt == 2: # dense nodes
					var dl = pr.read_varint()
					var dend = pr.pos + dl
					while pr.pos < dend:
						var dtag = pr.read_varint()
						var dfn = dtag >> 3
						var dwt = dtag & 0x7
						if dfn == 1 and dwt == 2: # id packed deltas
							var idlen = pr.read_varint()
							var idend = pr.pos + idlen
							while pr.pos < idend:
								pr.read_varint()
								nodes_count += 1
						elif dwt == 2:
							var l = pr.read_varint()
							pr.skip(l)
						elif dwt == 0:
							pr.read_varint()
				elif gfn == 3 and gwt == 2: # ways
					ways_count += 1
					var wl = pr.read_varint()
					pr.skip(wl)
				elif gfn == 4 and gwt == 2: # relations
					relations_count += 1
					var rl = pr.read_varint()
					pr.skip(rl)
				elif gwt == 2:
					var l = pr.read_varint()
					pr.skip(l)
				elif gwt == 0:
					pr.read_varint()
		elif wt == 2:
			var l = pr.read_varint()
			pr.skip(l)
		elif wt == 0:
			pr.read_varint()

	return {
		"decompressed_size": decomp.size(),
		"nodes": nodes_count,
		"ways": ways_count,
		"relations": relations_count
	}


static func _process_blob_job(job_input: Dictionary) -> Dictionary:
	var zlib_slice: PackedByteArray = job_input["zlib_slice"]
	var raw_size: int = job_input["raw_size"]
	var decomp = zlib_slice.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if decomp.is_empty():
		return {
			"decompressed_size": 0,
			"nodes": 0,
			"ways": 0,
			"relations": 0
		}
	return _parse_primitive_block(decomp)


func _check_memory_pause():
	var mem_info = OS.get_memory_info()
	if not mem_info.has("available") or mem_info["available"] < 0:
		return
	var physical: int = mem_info.get("physical", 0)
	var available: int = mem_info.get("available", 0)
	var pause_floor: int = maxi(1024 * 1024 * 1024, int(physical * 0.10))
	if available < pause_floor:
		print("pbf_spike: Paused — your computer is low on memory (need ", pause_floor / (1024 * 1024), " MiB, have ", available / (1024 * 1024), " MiB)")
		var resume_threshold: int = pause_floor + 512 * 1024 * 1024
		var consecutive_ok_ms: int = 0
		while consecutive_ok_ms < 10000:
			OS.delay_msec(1000)
			var cur_info = OS.get_memory_info()
			var cur_avail: int = cur_info.get("available", 0)
			if cur_avail >= resume_threshold:
				consecutive_ok_ms += 1000
			else:
				consecutive_ok_ms = 0
		print("pbf_spike: Resumed map processing.")


func _worker_wrapper(input_data: Dictionary, task_holder: Dictionary):
	task_holder["out_res"] = _process_blob_job(input_data)


func _init():
	var user_args = OS.get_cmdline_user_args()
	var pbf_path = ""
	var num_threads = 1

	var i = 0
	while i < user_args.size():
		var arg = user_args[i]
		if arg == "--pbf" and i + 1 < user_args.size():
			pbf_path = user_args[i + 1]
			i += 2
		elif arg == "--threads" and i + 1 < user_args.size():
			num_threads = user_args[i + 1].to_int()
			i += 2
		else:
			i += 1

	if pbf_path.is_empty():
		printerr("Usage: godot --headless --script tools/pbf_spike.gd -- --pbf <path> [--threads <1|4>]")
		quit(1)
		return

	if not FileAccess.file_exists(pbf_path):
		printerr("File does not exist: ", pbf_path)
		quit(1)
		return

	# Pre-check available memory >= 2 GiB
	var initial_mem = OS.get_memory_info()
	if initial_mem.has("available") and initial_mem["available"] >= 0:
		if initial_mem["available"] < 2 * 1024 * 1024 * 1024:
			print("pbf_spike: Available memory < 2 GiB at start — pausing...")
			_check_memory_pause()

	var f = FileAccess.open(pbf_path, FileAccess.READ)
	if not f:
		printerr("Cannot open file: ", pbf_path)
		quit(1)
		return

	var file_size = f.get_length()
	var file_size_mb = file_size / (1024.0 * 1024.0)
	print("--- PBF Speed Spike ---")
	print("Input file: ", pbf_path, " (", "%.2f" % file_size_mb, " MB)")
	print("Mode: ", "Multi-threaded (4 in flight)" if num_threads > 1 else "Single-threaded (1 thread)")

	var t0 = Time.get_ticks_msec()
	var total_blobs = 0
	var total_decompressed = 0
	var total_nodes = 0
	var total_ways = 0
	var total_relations = 0

	var active_tasks = []

	while f.get_position() < file_size:
		# Pause check before reading next block
		_check_memory_pause()

		var h_len_buf = f.get_buffer(4)
		if h_len_buf.size() < 4:
			break
		var h_len = (h_len_buf[0] << 24) | (h_len_buf[1] << 16) | (h_len_buf[2] << 8) | h_len_buf[3]
		if h_len > 65536:
			printerr("BlobHeader exceeds 64 KiB: ", h_len)
			quit(1)
			return

		var h_buf = f.get_buffer(h_len)
		var hr = ProtoReader.new(h_buf)
		var b_type = ""
		var data_size = 0
		while hr.has_more():
			var tag = hr.read_varint()
			var fn = tag >> 3
			var wt = tag & 0x7
			if fn == 1 and wt == 2:
				var slen = hr.read_varint()
				b_type = hr.buf.slice(hr.pos, hr.pos + slen).get_string_from_utf8()
				hr.skip(slen)
			elif fn == 3 and wt == 0:
				data_size = hr.read_varint()
			elif wt == 0:
				hr.read_varint()
			elif wt == 2:
				var l = hr.read_varint()
				hr.skip(l)

		if data_size > 33554432:
			printerr("Blob datasize exceeds 32 MiB: ", data_size)
			quit(1)
			return

		var b_buf = f.get_buffer(data_size)
		total_blobs += 1

		if b_type != "OSMData":
			continue

		var br = ProtoReader.new(b_buf)
		var raw_size = 0
		var zlib_slice = PackedByteArray()
		while br.has_more():
			var tag = br.read_varint()
			var fn = tag >> 3
			var wt = tag & 0x7
			if fn == 2 and wt == 0:
				raw_size = br.read_varint()
			elif fn == 3 and wt == 2:
				var zlen = br.read_varint()
				zlib_slice = br.buf.slice(br.pos, br.pos + zlen)
				br.skip(zlen)
			elif wt == 0:
				br.read_varint()
			elif wt == 2:
				var l = br.read_varint()
				br.skip(l)

		if zlib_slice.is_empty() or raw_size <= 0:
			continue

		var job_input = {
			"zlib_slice": zlib_slice,
			"raw_size": raw_size
		}

		if num_threads <= 1:
			var res = _process_blob_job(job_input)
			total_decompressed += res["decompressed_size"]
			total_nodes += res["nodes"]
			total_ways += res["ways"]
			total_relations += res["relations"]
		else:
			# Multi-threaded: maintain at most 4 blocks in flight
			while active_tasks.size() >= 4:
				var oldest = active_tasks.pop_front()
				WorkerThreadPool.wait_for_task_completion(oldest["task_id"])
				var r = oldest["out_res"]
				total_decompressed += r["decompressed_size"]
				total_nodes += r["nodes"]
				total_ways += r["ways"]
				total_relations += r["relations"]

			var task_holder = {"task_id": 0, "out_res": {}}
			var callable = Callable(self, "_worker_wrapper").bind(job_input, task_holder)
			task_holder["task_id"] = WorkerThreadPool.add_task(callable)
			active_tasks.append(task_holder)

	# Flush remaining tasks for multi-threaded mode
	while not active_tasks.is_empty():
		var t = active_tasks.pop_front()
		WorkerThreadPool.wait_for_task_completion(t["task_id"])
		var r = t["out_res"]
		total_decompressed += r["decompressed_size"]
		total_nodes += r["nodes"]
		total_ways += r["ways"]
		total_relations += r["relations"]

	f.close()

	var elapsed_s = (Time.get_ticks_msec() - t0) / 1000.0
	var mb_s = file_size_mb / (elapsed_s if elapsed_s > 0 else 0.001)
	var ca_extrapolated_s = (1200.0 / mb_s) if mb_s > 0 else 0.0
	var ca_extrapolated_min = ca_extrapolated_s / 60.0

	print("--- Results ---")
	print("Blobs processed: ", total_blobs)
	print("Decompressed payload: ", "%.2f" % (total_decompressed / (1024.0 * 1024.0)), " MB")
	print("Entities: Nodes=", total_nodes, " Ways=", total_ways, " Relations=", total_relations)
	print("Elapsed time: ", "%.3f" % elapsed_s, " s")
	print("Throughput: ", "%.2f" % mb_s, " MB/s")
	print("Extrapolated 1.2 GB (California): ", "%.1f" % ca_extrapolated_s, " s (", "%.2f" % ca_extrapolated_min, " min)")

	quit(0)
