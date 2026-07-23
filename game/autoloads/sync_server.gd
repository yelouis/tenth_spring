extends Node

# SyncServer Autoload for PC Game
# Listens for encrypted companion sync batches, handles HELLO/BATCH/ACK,
# and applies visit/corridor logs idempotently to the canonical DB inside one transaction.

const PROTOCOL_VERSION: int = 1
const TILE_METERS: float = 16.0
const CELL_METERS: float = 256.0 # 16x16 tiles at 16m
const METERS_PER_DEGREE: float = 111000.0

signal sync_completed(peer_id: String, applied_count: int)

# Converts fuzzed Lat/Lon coordinate to cell coordinate (~256m cells)
func latlon_to_cell(lat: float, lon: float) -> Vector2i:
	var lat_meters = lat * METERS_PER_DEGREE
	var lon_meters = lon * METERS_PER_DEGREE * cos(deg_to_rad(lat))
	var cell_x = int(floor(lon_meters / CELL_METERS))
	var cell_y = int(floor(lat_meters / CELL_METERS))
	return Vector2i(cell_x, cell_y)

# Converts fuzzed Lat/Lon coordinate to tile coordinate (16m tiles)
func latlon_to_tile(lat: float, lon: float) -> Vector2i:
	var lat_meters = lat * METERS_PER_DEGREE
	var lon_meters = lon * METERS_PER_DEGREE * cos(deg_to_rad(lat))
	var tile_x = int(floor(lon_meters / TILE_METERS))
	var tile_y = int(floor(lat_meters / TILE_METERS))
	return Vector2i(tile_x, tile_y)

func handle_hello(payload: Dictionary) -> Dictionary:
	var peer_id = payload.get("peerId", "")
	var client_version = int(payload.get("schemaVersion", 0))

	if client_version != PROTOCOL_VERSION:
		return {"status": "error", "message": "Schema version mismatch"}

	return {"status": "ok", "peerId": peer_id}

func process_batch(peer_id: String, batch_data: Dictionary) -> Dictionary:
	DB.begin_transaction()

	var rows = batch_data.get("rows", [])
	var body_fix = batch_data.get("bodyFix", {})

	var peer_info = DB.get_sync_peer(peer_id)
	var last_applied_seq = int(peer_info.get("last_applied_seq", 0))

	var max_seq = last_applied_seq
	var applied_count = 0

	for row in rows:
		var seq = int(row.get("seq", 0))
		if seq <= last_applied_seq:
			continue # Idempotent skip for already applied rows

		var kind = str(row.get("kind", "visit"))
		var lat = float(row.get("lat", 0.0))
		var lon = float(row.get("lon", 0.0))
		var started_at = int(row.get("startedAt", 0))
		var dwell_seconds = int(row.get("dwellSeconds", 0))

		var log_entry = {
			"peer_id": peer_id,
			"seq": seq,
			"kind": kind,
			"lat": lat,
			"lon": lon,
			"started_at": started_at,
			"dwell_seconds": dwell_seconds
		}

		var inserted = DB.insert_visit_log(log_entry)
		if inserted:
			applied_count += 1
			if seq > max_seq:
				max_seq = seq

			# Reveal map cell(s)
			var cell = latlon_to_cell(lat, lon)
			DB.upsert_map_cell(cell.x, cell.y, 1) # 1 = Known

			if kind == "visit":
				var place_id = "place_%d_%d" % [cell.x, cell.y]
				DB.upsert_place_node({
					"id": place_id,
					"name": "Scouted Location",
					"category": 1,
					"cell_x": cell.x,
					"cell_y": cell.y,
					"reveal_state": 1,
					"visit_count": 1,
					"last_real_visit_at": started_at
				})

	# Save last body position for relocation
	var body_lat = float(body_fix.get("lat", 0.0))
	var body_lon = float(body_fix.get("lon", 0.0))
	var body_ts = int(body_fix.get("tsUtcMs", 0))

	DB.update_sync_peer(peer_id, max_seq, body_lat, body_lon, body_ts)
	DB.commit_transaction()

	sync_completed.emit(peer_id, applied_count)

	return {
		"status": "ack",
		"lastAppliedSeq": max_seq,
		"appliedCount": applied_count
	}
