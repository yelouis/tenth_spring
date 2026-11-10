extends Node

# SyncServer Autoload for PC Game (Phase 1 / Decision 11 / §B3-B4)
# TLS transport server, pairing state, frame codec, and dispatch.

const PROTOCOL_VERSION: int = 3
const DEFAULT_PORT: int = 7350

const Grid := preload("res://world/grid.gd")
const PlacesPack := preload("res://world/places_pack.gd")
const RevealEngine := preload("res://world/reveal_engine.gd")

const EXPLORE_ROW_KEYS: Array[String] = ["seq", "kind", "placeId", "areaKey", "tsUtcMs"]
const HOME_ROW_KEYS: Array[String] = ["seq", "kind", "placeId", "tsUtcMs"]

signal sync_completed(peer_id: String, applied_count: int)
signal peer_paired(phone_id: String)

var pairing_codes: PairingCodes = PairingCodes.new()
var _server: TCPServer = TCPServer.new()
var _is_listening: bool = false
var _port: int = DEFAULT_PORT
var _identity: PcIdentity = null
var _current_session: ActiveSession = null

func _ready() -> void:
	pass

func configure_identity(id: PcIdentity) -> void:
	_identity = id

func get_identity() -> PcIdentity:
	if _identity == null:
		_identity = PcIdentity.new()
		_identity.load_or_create()
	return _identity

func get_port() -> int:
	return _port

func start_server(port: int = DEFAULT_PORT) -> Error:
	if _identity == null:
		_identity = PcIdentity.new()
	if _identity.key == null or _identity.cert == null:
		if not _identity.load_or_create():
			print("SyncServer: Failed to load or create PC identity; server will not listen")
			return FAILED
	var err = _server.listen(port, "*")
	if err == OK:
		_is_listening = true
		_port = port
		print("SyncServer listening on port %d" % port)
	else:
		print("SyncServer: Failed to listen on port %d: %d" % [port, err])
	return err

func stop_server() -> void:
	if _current_session != null:
		_current_session.close()
		_current_session = null
	if _is_listening:
		_server.stop()
		_is_listening = false

func _process(delta: float) -> void:
	if not _is_listening:
		return

	if _server.is_connection_available():
		var tcp = _server.take_connection()
		if tcp != null:
			if _current_session != null and _current_session.state != ActiveSession.State.CLOSED:
				# A session is already active; reject second connection immediately
				tcp.disconnect_from_host()
			else:
				var tls = StreamPeerTLS.new()
				var options = TLSOptions.server(_identity.key, _identity.cert)
				var err = tls.accept_stream(tcp, options)
				if err == OK:
					var disp = SessionDispatcher.new(_identity, pairing_codes)
					_current_session = ActiveSession.new(tls, disp)
				else:
					tcp.disconnect_from_host()

	if _current_session != null:
		_current_session.poll(delta)
		if _current_session.state == ActiveSession.State.CLOSED:
			_current_session = null

static func is_fuzzed_coord(v: float) -> bool:
	return absf(v * 1000.0 - roundf(v * 1000.0)) < 1e-6

static func sha256_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()

static func is_valid_phone_id(s: String) -> bool:
	if s.length() != 32:
		return false
	for i in range(32):
		var c = s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true

func create_dispatcher(custom_identity: PcIdentity = null, custom_pairing: PairingCodes = null) -> SessionDispatcher:
	var id = custom_identity if custom_identity != null else get_identity()
	var pc = custom_pairing if custom_pairing != null else pairing_codes
	return SessionDispatcher.new(id, pc)

# Converts fuzzed Lat/Lon coordinate to cell coordinate (256 WM-m cells)
func latlon_to_cell(lat: float, lon: float) -> Vector2i:
	return Grid.latlon_to_cell(lat, lon)

# Converts fuzzed Lat/Lon coordinate to tile coordinate (16 WM-m tiles)
func latlon_to_tile(lat: float, lon: float) -> Vector2i:
	return Grid.latlon_to_tile(lat, lon)

func handle_hello(payload: Dictionary) -> Dictionary:
	var peer_id = payload.get("peerId", "")
	var client_version = int(payload.get("schemaVersion", 0))
	if client_version != PROTOCOL_VERSION:
		return {"status": "error", "code": "schema_mismatch", "message": "Schema version mismatch"}
	if not payload.has("packVersion") or int(payload.get("packVersion", 0)) != PlacesPack.pack_version():
		return {"status": "error", "code": "pack_mismatch", "message": "Pack version mismatch"}
	return {"status": "ok", "peerId": peer_id}

static func _is_valid_int(val: Variant) -> bool:
	if val == null:
		return false
	return typeof(val) == TYPE_INT or (typeof(val) == TYPE_FLOAT and float(val) == round(float(val)))

static func validate_batch_frame(frame: Dictionary) -> String:
	var rows = frame.get("rows", null)
	if rows == null or typeof(rows) != TYPE_ARRAY:
		return "protocol"
	if rows.size() > 500:
		return "protocol"
	if frame.has("bodyFix"):
		return "bad_row"

	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			return "bad_row"
		var kind_v = row.get("kind", null)
		if kind_v == null or typeof(kind_v) != TYPE_STRING:
			return "bad_row"
		var kind: String = str(kind_v)
		var whitelist: Array[String]
		if kind == "explore":
			whitelist = EXPLORE_ROW_KEYS
		elif kind == "home":
			whitelist = HOME_ROW_KEYS
		else:
			return "bad_row"

		for k in row.keys():
			if not whitelist.has(str(k)):
				return "bad_row"
		for req_k in whitelist:
			if not row.has(req_k):
				return "bad_row"

		var seq_v = row.get("seq", null)
		if not _is_valid_int(seq_v) or int(seq_v) < 1:
			return "bad_row"

		var ts_v = row.get("tsUtcMs", null)
		if not _is_valid_int(ts_v) or int(ts_v) <= 0:
			return "bad_row"

		var pid_v = row.get("placeId", null)
		if pid_v == null or typeof(pid_v) != TYPE_STRING or str(pid_v) == "":
			return "bad_row"
		var place_id: String = str(pid_v)
		var p_info: Dictionary = PlacesPack.place_info(place_id)
		if p_info.is_empty():
			return "bad_row"

		if kind == "explore":
			var akey_v = row.get("areaKey", null)
			if akey_v == null or typeof(akey_v) != TYPE_STRING or str(akey_v) == "":
				return "bad_row"
			var area_key: String = str(akey_v)
			var a_info: Dictionary = PlacesPack.area(area_key)
			if a_info.is_empty():
				return "bad_row"
			if str(a_info.get("place_id", "")) != place_id:
				return "bad_row"
			var a_kind: String = str(a_info.get("kind", ""))
			if a_kind != "neighbourhood" and a_kind != "site":
				return "bad_row"
		else:
			if str(p_info.get("kind", "")) != "city":
				return "bad_row"

	return ""

func process_batch(peer_id: String, batch_data: Dictionary) -> Dictionary:
	var v_err: String = SyncServer.validate_batch_frame(batch_data)
	if v_err != "":
		return {"status": "error", "code": v_err, "message": v_err}

	if not DB.begin_transaction():
		return {"status": "error", "code": "storage", "message": "storage error"}

	var rows: Array = batch_data.get("rows", [])

	var peer_info = DB.get_sync_peer(peer_id)
	var last_applied_seq = int(peer_info.get("last_applied_seq", 0))

	var max_seq = last_applied_seq
	var applied_count = 0

	for row in rows:
		var seq = int(row.get("seq", 0))
		if seq <= last_applied_seq:
			continue # Idempotent skip for already applied rows

		var kind = str(row.get("kind", ""))
		var place_id = str(row.get("placeId", ""))
		var target_id = str(row.get("areaKey", "")) if kind == "explore" else place_id
		var ts_utc_ms = int(row.get("tsUtcMs", 0))

		var log_entry = {
			"peer_id": peer_id,
			"seq": seq,
			"place_id": target_id,
			"lat": null,
			"lon": null,
			"started_at": ts_utc_ms,
			"dwell_seconds": 0,
			"kind": kind
		}

		var inserted = DB.insert_visit_log(log_entry)
		if DB.last_error != "":
			DB.rollback_transaction()
			return {"status": "error", "code": "storage", "message": "storage error"}

		if inserted:
			applied_count += 1
			if seq > max_seq:
				max_seq = seq

	DB.update_sync_peer_seq(peer_id, max_seq)
	if DB.last_error != "":
		DB.rollback_transaction()
		return {"status": "error", "code": "storage", "message": "storage error"}

	if not DB.commit_transaction():
		DB.rollback_transaction()
		return {"status": "error", "code": "storage", "message": "storage error"}

	RevealEngine.apply(DB)

	sync_completed.emit(peer_id, applied_count)

	return {
		"status": "ack",
		"lastAppliedSeq": max_seq,
		"appliedCount": applied_count
	}

# Session Frame Dispatcher
class SessionDispatcher extends RefCounted:
	var identity: PcIdentity
	var pairing_codes: PairingCodes
	var authenticated_peer_id: String = ""

	func _init(id: PcIdentity, pc: PairingCodes) -> void:
		identity = id
		pairing_codes = pc

	func handle_frame(frame: Dictionary) -> Dictionary:
		var type = str(frame.get("type", ""))
		match type:
			"PAIR":
				return _handle_pair(frame)
			"HELLO":
				return _handle_hello(frame)
			"BATCH":
				return _handle_batch(frame)
			_:
				return {"type": "ERROR", "code": "protocol"}

	func _handle_pair(frame: Dictionary) -> Dictionary:
		var phone_id = frame.get("phoneId", null)
		var token_b64 = frame.get("deviceToken", null)
		if phone_id == null or token_b64 == null or typeof(phone_id) != TYPE_STRING or typeof(token_b64) != TYPE_STRING:
			return {"type": "ERROR", "code": "protocol"}

		if not SyncServer.is_valid_phone_id(str(phone_id)):
			return {"type": "ERROR", "code": "protocol"}

		var raw_token = Marshalls.base64_to_raw(str(token_b64))
		if raw_token.size() != 32:
			return {"type": "ERROR", "code": "protocol"}

		var pair_code = str(frame.get("pair", ""))
		var now = int(Time.get_unix_time_from_system())
		if not pairing_codes.consume(pair_code, now):
			return {"type": "ERROR", "code": "bad_pair_code"}

		if not DB.begin_transaction():
			return {"type": "ERROR", "code": "storage"}

		var token_hash = SyncServer.sha256_bytes(raw_token)
		var set_ok = DB.set_peer_token_hash(str(phone_id), token_hash)
		var clear_ok = DB.clear_other_peer_tokens(str(phone_id))
		if not set_ok or not clear_ok or DB.last_error != "":
			DB.rollback_transaction()
			return {"type": "ERROR", "code": "storage"}

		if not DB.commit_transaction():
			DB.rollback_transaction()
			return {"type": "ERROR", "code": "storage"}

		SyncServer.peer_paired.emit(str(phone_id))

		return {
			"type": "PAIR_OK",
			"pcId": identity.pc_id if identity != null else ""
		}

	func _handle_hello(frame: Dictionary) -> Dictionary:
		var peer_id = str(frame.get("peerId", ""))
		var token_b64 = str(frame.get("deviceToken", ""))
		if peer_id == "" or token_b64 == "":
			return {"type": "ERROR", "code": "unpaired"}

		var raw_token = Marshalls.base64_to_raw(token_b64)
		if raw_token.is_empty():
			return {"type": "ERROR", "code": "unpaired"}

		var peer_info = DB.get_sync_peer(peer_id)
		if peer_info.is_empty():
			return {"type": "ERROR", "code": "unpaired"}

		var stored_hash = peer_info.get("device_token_hash", null)
		if stored_hash == null or not (stored_hash is PackedByteArray) or stored_hash.is_empty():
			return {"type": "ERROR", "code": "unpaired"}

		var token_hash = SyncServer.sha256_bytes(raw_token)
		var crypto = Crypto.new()
		if not crypto.constant_time_compare(stored_hash, token_hash):
			return {"type": "ERROR", "code": "unpaired"}

		var client_version = int(frame.get("schemaVersion", 0))
		if client_version != SyncServer.PROTOCOL_VERSION:
			return {"type": "ERROR", "code": "schema_mismatch"}

		if not frame.has("packVersion") or not SyncServer._is_valid_int(frame.get("packVersion", null)) or int(frame.get("packVersion", 0)) != PlacesPack.pack_version():
			return {"type": "ERROR", "code": "pack_mismatch"}

		authenticated_peer_id = peer_id
		var last_applied_seq = int(peer_info.get("last_applied_seq", 0))

		return {
			"type": "HELLO_OK",
			"pcId": identity.pc_id if identity != null else "",
			"lastAppliedSeq": last_applied_seq
		}

	func _handle_batch(frame: Dictionary) -> Dictionary:
		if authenticated_peer_id == "":
			return {"type": "ERROR", "code": "protocol"}

		var v_err: String = SyncServer.validate_batch_frame(frame)
		if v_err != "":
			return {"type": "ERROR", "code": v_err}

		# Apply batch using the authenticated session peer id
		var result = SyncServer.process_batch(authenticated_peer_id, frame)
		if result.get("status") != "ack":
			var err_code: String = str(result.get("code", "storage"))
			return {"type": "ERROR", "code": err_code}
		result["type"] = "ACK"
		return result

# Active TLS Network Session
class ActiveSession extends RefCounted:
	enum State { HANDSHAKING, READING, CLOSED }
	var state: State = State.HANDSHAKING
	var tls: StreamPeerTLS
	var dispatcher: SessionDispatcher
	var frame_reader: FrameCodec.FrameReader = FrameCodec.FrameReader.new()
	var handshake_time: float = 0.0
	var idle_time: float = 0.0

	func _init(t: StreamPeerTLS, disp: SessionDispatcher) -> void:
		tls = t
		dispatcher = disp

	func poll(delta: float) -> void:
		if state == State.CLOSED:
			return

		tls.poll()
		var status = tls.get_status()

		if state == State.HANDSHAKING:
			if status == StreamPeerTLS.STATUS_CONNECTED:
				state = State.READING
				idle_time = 0.0
			elif status == StreamPeerTLS.STATUS_ERROR or status == StreamPeerTLS.STATUS_DISCONNECTED:
				close()
			else:
				handshake_time += delta
				if handshake_time > 10.0:
					close()

		elif state == State.READING:
			if status != StreamPeerTLS.STATUS_CONNECTED:
				close()
				return

			var available = tls.get_available_bytes()
			if available > 0:
				var chunk = tls.get_data(available)
				if chunk[0] == OK and chunk[1].size() > 0:
					idle_time = 0.0
					frame_reader.feed(chunk[1])
					if frame_reader.error != "":
						_send_error_and_close("protocol")
						return
					while true:
						var frame = frame_reader.next_frame()
						if frame_reader.error != "":
							_send_error_and_close("protocol")
							return
						if frame == null:
							break
						idle_time = 0.0
						var reply = dispatcher.handle_frame(frame)
						var reply_bytes = FrameCodec.encode(reply)
						tls.put_data(reply_bytes)
						if reply.get("type") == "ERROR":
							close()
							return
			else:
				idle_time += delta
				if idle_time > 30.0:
					close()

	func _send_error_and_close(code: String) -> void:
		var reply = {"type": "ERROR", "code": code}
		var reply_bytes = FrameCodec.encode(reply)
		tls.put_data(reply_bytes)
		close()

	func close() -> void:
		if state != State.CLOSED:
			state = State.CLOSED
			tls.disconnect_from_stream()
