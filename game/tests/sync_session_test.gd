extends Node

# Unit test for SyncServer SessionDispatcher driving frames directly without sockets (protocol v3)
const PlacesPack := preload("res://world/places_pack.gd")

const TEST_DB_PATH: String = "user://test/tenth_spring_sync_session_test.db"
const TEST_DB_TMP_PATH: String = "user://test/tenth_spring_sync_session_test.db.tmp"
const TEST_IDENTITY_DIR: String = "user://test/sync_identity_session_test/"

func run_test() -> bool:
	_cleanup()

	DB.configure_paths(TEST_DB_PATH, TEST_DB_TMP_PATH)
	DB.assert_test_safe()
	PlacesPack.set_active_pack_path(PlacesPack.FIXTURE_PACK_PATH)
	DB.init_db()

	var test_id = PcIdentity.new()
	test_id.configure_dir(TEST_IDENTITY_DIR)
	if not test_id.load_or_create():
		push_error("sync_session_test: failed to create test identity")
		_cleanup()
		return false

	var test_pairing = PairingCodes.new()
	var disp = SyncServer.create_dispatcher(test_id, test_pairing)

	# 1. BATCH before HELLO -> ERROR protocol
	var res1 = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 1, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "osm:n9104", "tsUtcMs": 1000}]
	})
	if res1.get("type") != "ERROR" or res1.get("code") != "protocol":
		push_error("sync_session_test: BATCH before HELLO did not return ERROR protocol: " + str(res1))
		_cleanup()
		return false

	# 2. Pair a test phone
	var phone_alpha = "0123456789abcdef0123456789abcdef"
	var phone_beta = "fedcba9876543210fedcba9876543210"
	var now = int(Time.get_unix_time_from_system())
	var code = test_pairing.new_code(now)
	var crypto = Crypto.new()
	var secret_token_bytes = crypto.generate_random_bytes(32)
	var valid_token_b64 = Marshalls.raw_to_base64(secret_token_bytes)

	var pair_res = disp.handle_frame({
		"type": "PAIR",
		"phoneId": phone_alpha,
		"pair": code,
		"deviceToken": valid_token_b64
	})
	if pair_res.get("type") != "PAIR_OK" or pair_res.get("pcId") != test_id.pc_id:
		push_error("sync_session_test: PAIR failed: " + str(pair_res))
		_cleanup()
		return false

	# 3. Wrong token on HELLO -> ERROR unpaired
	var wrong_token_bytes = crypto.generate_random_bytes(32)
	var wrong_token_b64 = Marshalls.raw_to_base64(wrong_token_bytes)
	var hello_bad = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 3,
		"packVersion": 1,
		"deviceToken": wrong_token_b64
	})
	if hello_bad.get("type") != "ERROR" or hello_bad.get("code") != "unpaired":
		push_error("sync_session_test: wrong token did not return ERROR unpaired: " + str(hello_bad))
		_cleanup()
		return false

	# 4a. Wrong schemaVersion on HELLO -> ERROR schema_mismatch
	var hello_schema_mismatch = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 1,
		"packVersion": 1,
		"deviceToken": valid_token_b64
	})
	if hello_schema_mismatch.get("type") != "ERROR" or hello_schema_mismatch.get("code") != "schema_mismatch":
		push_error("sync_session_test: wrong schemaVersion did not return ERROR schema_mismatch: " + str(hello_schema_mismatch))
		_cleanup()
		return false

	# 4b. Wrong packVersion on HELLO -> ERROR pack_mismatch
	var hello_pack_mismatch = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 3,
		"packVersion": 999,
		"deviceToken": valid_token_b64
	})
	if hello_pack_mismatch.get("type") != "ERROR" or hello_pack_mismatch.get("code") != "pack_mismatch":
		push_error("sync_session_test: wrong packVersion did not return ERROR pack_mismatch: " + str(hello_pack_mismatch))
		_cleanup()
		return false

	# 4c. Valid HELLO -> HELLO_OK
	var hello_ok = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 3,
		"packVersion": 1,
		"deviceToken": valid_token_b64
	})
	if hello_ok.get("type") != "HELLO_OK" or hello_ok.get("pcId") != test_id.pc_id:
		push_error("sync_session_test: valid HELLO failed: " + str(hello_ok))
		_cleanup()
		return false

	# 5. Row validation -> ERROR bad_row, visit_log unchanged:
	# (a) row carrying a `lat` key
	# (b) row with unknown placeId
	# (c) explore row with an areaKey belonging to another place
	# (d) home row with a non-city placeId (site:fixture-park)
	# (e) BATCH carrying a top-level `bodyFix` key
	var count_rows_pre = DB._rows("SELECT COUNT(*) as c FROM visit_log;")
	var pre_count = int(count_rows_pre[0].get("c", 0)) if not count_rows_pre.is_empty() else 0

	var bad_batches = [
		{
			"name": "lat key in row",
			"frame": {
				"type": "BATCH",
				"rows": [{"seq": 1, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "osm:n9104", "lat": 0.01, "tsUtcMs": 1000}]
			}
		},
		{
			"name": "unknown placeId",
			"frame": {
				"type": "BATCH",
				"rows": [{"seq": 1, "kind": "explore", "placeId": "city:atlantis", "areaKey": "osm:n9104", "tsUtcMs": 1000}]
			}
		},
		{
			"name": "areaKey of another place",
			"frame": {
				"type": "BATCH",
				"rows": [{"seq": 1, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "site:fixture-park", "tsUtcMs": 1000}]
			}
		},
		{
			"name": "home row with site placeId",
			"frame": {
				"type": "BATCH",
				"rows": [{"seq": 1, "kind": "home", "placeId": "site:fixture-park", "tsUtcMs": 1000}]
			}
		},
		{
			"name": "bodyFix key on frame",
			"frame": {
				"type": "BATCH",
				"rows": [{"seq": 1, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "osm:n9104", "tsUtcMs": 1000}],
				"bodyFix": {"lat": 0.01, "lon": 0.01, "tsUtcMs": 1000}
			}
		}
	]

	for b in bad_batches:
		var b_res = disp.handle_frame(b["frame"])
		if b_res.get("type") != "ERROR" or b_res.get("code") != "bad_row":
			push_error("sync_session_test: %s did not return ERROR bad_row: %s" % [b["name"], str(b_res)])
			_cleanup()
			return false

	var count_rows_post = DB._rows("SELECT COUNT(*) as c FROM visit_log;")
	var post_count = int(count_rows_post[0].get("c", 0)) if not count_rows_post.is_empty() else 0
	if post_count != pre_count:
		push_error("sync_session_test: visit_log changed after invalid bad_row batches")
		_cleanup()
		return false

	# 6. BATCH frame carrying top-level "peerId": "other" is stored under authenticated peer ("phone_alpha")
	var batch_spoof = disp.handle_frame({
		"type": "BATCH",
		"peerId": "other_attacker",
		"rows": [
			{"seq": 1, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "osm:n9104", "tsUtcMs": 1000},
			{"seq": 2, "kind": "home", "placeId": "city:fixture-city", "tsUtcMs": 2000}
		]
	})
	if batch_spoof.get("type") != "ACK" or int(batch_spoof.get("appliedCount", 0)) != 2:
		push_error("sync_session_test: valid batch failed to ACK: " + str(batch_spoof))
		_cleanup()
		return false

	if not DB.is_visit_logged(phone_alpha, 1) or not DB.is_visit_logged(phone_alpha, 2):
		push_error("sync_session_test: rows were not stored under authenticated peerId")
		_cleanup()
		return false

	if DB.is_visit_logged("other_attacker", 1):
		push_error("sync_session_test: row was stored under spoofed peerId")
		_cleanup()
		return false

	# Verify stored visit_log rows have NULL lat and lon
	var v_check = DB._rows("SELECT lat, lon FROM visit_log WHERE peer_id = ? AND seq = 1;", [phone_alpha])
	if v_check.is_empty() or v_check[0].get("lat") != null or v_check[0].get("lon") != null:
		push_error("sync_session_test: visit_log lat/lon were not NULL: " + str(v_check))
		_cleanup()
		return false

	# 7. Falsifying F33: multi-phone re-pair
	var code_b = test_pairing.new_code(now)
	var token_b_bytes = crypto.generate_random_bytes(32)
	var token_b_b64 = Marshalls.raw_to_base64(token_b_bytes)
	var pair_b = disp.handle_frame({
		"type": "PAIR",
		"phoneId": phone_beta,
		"pair": code_b,
		"deviceToken": token_b_b64
	})
	if pair_b.get("type") != "PAIR_OK":
		push_error("sync_session_test: Phone B PAIR failed: " + str(pair_b))
		_cleanup()
		return false

	# Phone A's HELLO -> ERROR unpaired (PC cleared other tokens)
	var hello_a_unpaired = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 3,
		"packVersion": 1,
		"deviceToken": valid_token_b64
	})
	if hello_a_unpaired.get("type") != "ERROR" or hello_a_unpaired.get("code") != "unpaired":
		push_error("sync_session_test: Phone A HELLO after B paired did not return ERROR unpaired: " + str(hello_a_unpaired))
		_cleanup()
		return false

	# Phone A pairs again with a fresh code -> PAIR_OK
	var code_a2 = test_pairing.new_code(now)
	var token_a2_bytes = crypto.generate_random_bytes(32)
	var token_a2_b64 = Marshalls.raw_to_base64(token_a2_bytes)
	var pair_a2 = disp.handle_frame({
		"type": "PAIR",
		"phoneId": phone_alpha,
		"pair": code_a2,
		"deviceToken": token_a2_b64
	})
	if pair_a2.get("type") != "PAIR_OK":
		push_error("sync_session_test: Phone A re-pair failed: " + str(pair_a2))
		_cleanup()
		return false

	# Phone A's HELLO -> HELLO_OK
	var hello_a2 = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 3,
		"packVersion": 1,
		"deviceToken": token_a2_b64
	})
	if hello_a2.get("type") != "HELLO_OK":
		push_error("sync_session_test: Phone A HELLO after re-pair failed: " + str(hello_a2))
		_cleanup()
		return false

	# Earlier visit_log rows for Phone A are still present
	if not DB.is_visit_logged(phone_alpha, 1):
		push_error("sync_session_test: Phone A earlier visit_log missing after re-pair")
		_cleanup()
		return false

	# 8. Falsifying F32: malformed PAIR (31-byte token) returns ERROR protocol without burning code
	var code_gamma = test_pairing.new_code(now)
	var short_token_bytes = crypto.generate_random_bytes(31)
	var short_token_b64 = Marshalls.raw_to_base64(short_token_bytes)
	var pair_short = disp.handle_frame({
		"type": "PAIR",
		"phoneId": "11111111111111111111111111111111",
		"pair": code_gamma,
		"deviceToken": short_token_b64
	})
	if pair_short.get("type") != "ERROR" or pair_short.get("code") != "protocol":
		push_error("sync_session_test: 31-byte token PAIR did not return ERROR protocol: " + str(pair_short))
		_cleanup()
		return false

	# Same code pairs successfully with 32-byte token (code not burned)
	var valid_gamma_bytes = crypto.generate_random_bytes(32)
	var valid_gamma_b64 = Marshalls.raw_to_base64(valid_gamma_bytes)
	var pair_gamma = disp.handle_frame({
		"type": "PAIR",
		"phoneId": "11111111111111111111111111111111",
		"pair": code_gamma,
		"deviceToken": valid_gamma_b64
	})
	if pair_gamma.get("type") != "PAIR_OK":
		push_error("sync_session_test: code was burned by malformed PAIR: " + str(pair_gamma))
		_cleanup()
		return false

	# PAIR with DB closed -> ERROR storage
	var code_closed = test_pairing.new_code(now)
	DB.close()
	var pair_closed = disp.handle_frame({
		"type": "PAIR",
		"phoneId": "22222222222222222222222222222222",
		"pair": code_closed,
		"deviceToken": valid_gamma_b64
	})
	if pair_closed.get("type") != "ERROR" or pair_closed.get("code") != "storage":
		push_error("sync_session_test: PAIR with DB closed did not return ERROR storage: " + str(pair_closed))
		_cleanup()
		return false

	# Re-open DB
	DB.init_db()

	# Fault injection without production hooks: pair and HELLO, then DB.close(), then dispatch valid BATCH -> ERROR storage
	var code_fault = test_pairing.new_code(now)
	var fault_token_bytes = crypto.generate_random_bytes(32)
	var fault_token_b64 = Marshalls.raw_to_base64(fault_token_bytes)
	var phone_fault = "33333333333333333333333333333333"
	var pair_fault = disp.handle_frame({
		"type": "PAIR",
		"phoneId": phone_fault,
		"pair": code_fault,
		"deviceToken": fault_token_b64
	})
	if pair_fault.get("type") != "PAIR_OK":
		push_error("sync_session_test: PAIR before fault injection failed: " + str(pair_fault))
		_cleanup()
		return false

	var hello_fault = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_fault,
		"schemaVersion": 3,
		"packVersion": 1,
		"deviceToken": fault_token_b64
	})
	if hello_fault.get("type") != "HELLO_OK":
		push_error("sync_session_test: HELLO before fault injection failed: " + str(hello_fault))
		_cleanup()
		return false

	# Close DB to simulate storage failure during BATCH
	DB.close()
	var batch_storage_err = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 100, "kind": "explore", "placeId": "city:fixture-city", "areaKey": "osm:n9104", "tsUtcMs": 100000}]
	})
	if batch_storage_err.get("type") != "ERROR" or batch_storage_err.get("code") != "storage":
		push_error("sync_session_test: BATCH with DB closed did not return ERROR storage: " + str(batch_storage_err))
		_cleanup()
		return false

	# Re-open DB for safe cleanup
	DB.init_db()

	_cleanup()
	return true

func _cleanup() -> void:
	DB.close()
	PlacesPack.reset_active_pack_path()
	var test_dir = TEST_DB_PATH.get_base_dir()
	if DirAccess.dir_exists_absolute(test_dir):
		var da = DirAccess.open(test_dir)
		if da != null:
			for f in da.get_files():
				if f.begins_with("tenth_spring_sync_session_test.db"):
					da.remove(f)
	if DirAccess.dir_exists_absolute(TEST_IDENTITY_DIR):
		var da_id = DirAccess.open(TEST_IDENTITY_DIR)
		if da_id != null:
			for f in da_id.get_files():
				da_id.remove(f)
	DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)
