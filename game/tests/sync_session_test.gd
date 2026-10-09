extends Node

# Unit test for SyncServer SessionDispatcher driving frames directly without sockets
const TEST_DB_PATH: String = "user://test/tenth_spring_sync_session_test.db"
const TEST_DB_TMP_PATH: String = "user://test/tenth_spring_sync_session_test.db.tmp"
const TEST_IDENTITY_DIR: String = "user://test/sync_identity_session_test/"

func run_test() -> bool:
	_cleanup()

	DB.configure_paths(TEST_DB_PATH, TEST_DB_TMP_PATH)
	DB.assert_test_safe()
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
		"rows": [{"seq": 1, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 1000, "dwellSeconds": 60}]
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
		"schemaVersion": 1,
		"deviceToken": wrong_token_b64
	})
	if hello_bad.get("type") != "ERROR" or hello_bad.get("code") != "unpaired":
		push_error("sync_session_test: wrong token did not return ERROR unpaired: " + str(hello_bad))
		_cleanup()
		return false

	# 4. Valid HELLO -> HELLO_OK
	var hello_ok = disp.handle_frame({
		"type": "HELLO",
		"peerId": phone_alpha,
		"schemaVersion": 1,
		"deviceToken": valid_token_b64
	})
	if hello_ok.get("type") != "HELLO_OK" or hello_ok.get("pcId") != test_id.pc_id:
		push_error("sync_session_test: valid HELLO failed: " + str(hello_ok))
		_cleanup()
		return false

	# 5. Coordinate with 4 decimals (37.7761) -> ERROR protocol, visit_log unchanged
	var count_rows_pre = DB._rows("SELECT COUNT(*) as c FROM visit_log;")
	var pre_count = int(count_rows_pre[0].get("c", 0)) if not count_rows_pre.is_empty() else 0

	var batch_bad_coord = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 1, "kind": "visit", "lat": 37.7761, "lon": -122.420, "startedAt": 1000, "dwellSeconds": 60}]
	})
	if batch_bad_coord.get("type") != "ERROR" or batch_bad_coord.get("code") != "protocol":
		push_error("sync_session_test: 4-decimal coord did not return ERROR protocol: " + str(batch_bad_coord))
		_cleanup()
		return false

	var count_rows_post = DB._rows("SELECT COUNT(*) as c FROM visit_log;")
	var post_count = int(count_rows_post[0].get("c", 0)) if not count_rows_post.is_empty() else 0
	if post_count != pre_count:
		push_error("sync_session_test: visit_log changed after invalid batch")
		_cleanup()
		return false

	# 6. BATCH frame carrying top-level "peerId": "other" is stored under authenticated peer ("phone_alpha")
	var batch_spoof = disp.handle_frame({
		"type": "BATCH",
		"peerId": "other_attacker",
		"rows": [{"seq": 1, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 1000, "dwellSeconds": 60}],
		"bodyFix": {"lat": 37.776, "lon": -122.420, "tsUtcMs": 1000}
	})
	if batch_spoof.get("type") != "ACK" or int(batch_spoof.get("appliedCount", 0)) != 1:
		push_error("sync_session_test: valid batch failed to ACK: " + str(batch_spoof))
		_cleanup()
		return false

	if not DB.is_visit_logged(phone_alpha, 1):
		push_error("sync_session_test: row was not stored under authenticated peerId")
		_cleanup()
		return false

	if DB.is_visit_logged("other_attacker", 1):
		push_error("sync_session_test: row was stored under spoofed peerId")
		_cleanup()
		return false

	# 7. Falsifying F34: BATCH with bodyFix (ts 2000), then BATCH without bodyFix keeps stored position
	var batch_fix1 = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 2, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 2000, "dwellSeconds": 60}],
		"bodyFix": {"lat": 37.776, "lon": -122.420, "tsUtcMs": 2000}
	})
	if batch_fix1.get("type") != "ACK":
		push_error("sync_session_test: batch_fix1 failed: " + str(batch_fix1))
		_cleanup()
		return false

	var peer_check1 = DB.get_sync_peer(phone_alpha)
	if abs(float(peer_check1.get("last_body_lat", 0.0)) - 37.776) > 1e-6 or abs(float(peer_check1.get("last_body_lon", 0.0)) - (-122.420)) > 1e-6 or int(peer_check1.get("last_body_ts", 0)) != 2000:
		push_error("sync_session_test: peer body fix not saved correctly: " + str(peer_check1))
		_cleanup()
		return false

	# BATCH (seq 3) without bodyFix key
	var batch_no_fix = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 3, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 3000, "dwellSeconds": 60}]
	})
	if batch_no_fix.get("type") != "ACK":
		push_error("sync_session_test: batch_no_fix failed: " + str(batch_no_fix))
		_cleanup()
		return false

	var peer_check2 = DB.get_sync_peer(phone_alpha)
	if int(peer_check2.get("last_applied_seq", 0)) != 3:
		push_error("sync_session_test: last_applied_seq was not updated to 3: " + str(peer_check2))
		_cleanup()
		return false
	if abs(float(peer_check2.get("last_body_lat", 0.0)) - 37.776) > 1e-6 or abs(float(peer_check2.get("last_body_lon", 0.0)) - (-122.420)) > 1e-6 or int(peer_check2.get("last_body_ts", 0)) != 2000:
		push_error("sync_session_test: peer body position corrupted by BATCH without bodyFix: " + str(peer_check2))
		_cleanup()
		return false

	# 8. Falsifying — stale fix: later BATCH with bodyFix tsUtcMs 1000 leaves stored position at ts 2000 values
	var batch_stale = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 4, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 4000, "dwellSeconds": 60}],
		"bodyFix": {"lat": 37.770, "lon": -122.410, "tsUtcMs": 1000}
	})
	if batch_stale.get("type") != "ACK":
		push_error("sync_session_test: batch_stale failed: " + str(batch_stale))
		_cleanup()
		return false

	var peer_check3 = DB.get_sync_peer(phone_alpha)
	if int(peer_check3.get("last_applied_seq", 0)) != 4:
		push_error("sync_session_test: last_applied_seq not updated on stale fix batch: " + str(peer_check3))
		_cleanup()
		return false
	if abs(float(peer_check3.get("last_body_lat", 0.0)) - 37.776) > 1e-6 or abs(float(peer_check3.get("last_body_lon", 0.0)) - (-122.420)) > 1e-6 or int(peer_check3.get("last_body_ts", 0)) != 2000:
		push_error("sync_session_test: stale bodyFix overwrote newer bodyFix: " + str(peer_check3))
		_cleanup()
		return false

	# 9. Protocol validation: 4-decimal coord in bodyFix -> ERROR protocol
	var batch_bad_fix_coord = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 5, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 5000, "dwellSeconds": 60}],
		"bodyFix": {"lat": 37.7761, "lon": -122.420, "tsUtcMs": 5000}
	})
	if batch_bad_fix_coord.get("type") != "ERROR" or batch_bad_fix_coord.get("code") != "protocol":
		push_error("sync_session_test: 4-decimal bodyFix did not return ERROR protocol: " + str(batch_bad_fix_coord))
		_cleanup()
		return false

	# 10. Protocol validation: missing tsUtcMs in bodyFix -> ERROR protocol
	var batch_no_ts = disp.handle_frame({
		"type": "BATCH",
		"rows": [{"seq": 5, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 5000, "dwellSeconds": 60}],
		"bodyFix": {"lat": 37.776, "lon": -122.420}
	})
	if batch_no_ts.get("type") != "ERROR" or batch_no_ts.get("code") != "protocol":
		push_error("sync_session_test: bodyFix without tsUtcMs did not return ERROR protocol: " + str(batch_no_ts))
		_cleanup()
		return false

	# 11. Falsifying F33: multi-phone re-pair
	# Phone A was paired and got HELLO_OK in steps 2 & 4.
	# Phone B pairs with a fresh code.
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
		"schemaVersion": 1,
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
		"schemaVersion": 1,
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

	# 12. Falsifying F32: malformed PAIR (31-byte token) returns ERROR protocol without burning code
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
		"schemaVersion": 1,
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
		"rows": [{"seq": 100, "kind": "visit", "lat": 37.776, "lon": -122.420, "startedAt": 100000, "dwellSeconds": 60}]
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
