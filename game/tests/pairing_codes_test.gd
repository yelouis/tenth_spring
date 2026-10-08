extends Node

# Unit test for PairingCodes lifecycle, consumption, and address filtering
func run_test() -> bool:
	var pc = PairingCodes.new()
	var t0 = 1000000

	# 1. new_code creates 32-hex string
	var code = pc.new_code(t0)
	if code.length() != 32:
		push_error("pairing_codes_test: code length != 32: " + code)
		return false

	# 2. Wrong code fails
	var wrong_code = "00000000000000000000000000000000"
	if pc.consume(wrong_code, t0 + 10):
		push_error("pairing_codes_test: wrong code was accepted")
		return false

	# 3. Valid code consumes successfully once
	if not pc.consume(code, t0 + 10):
		push_error("pairing_codes_test: valid code was rejected")
		return false

	# 4. Same code consumed a second time fails (one-time use)
	if pc.consume(code, t0 + 15):
		push_error("pairing_codes_test: used code was accepted twice")
		return false

	# 5. Expired code (now + 601s) fails
	var code2 = pc.new_code(t0)
	if pc.consume(code2, t0 + 601):
		push_error("pairing_codes_test: expired code was accepted")
		return false

	# 6. filter_addrs table cases
	var test_addrs = PackedStringArray([
		"127.0.0.1",        # loopback -> drop
		"10.0.1.25",        # private 10/8 -> keep (1)
		"169.254.4.5",      # link-local -> drop
		"172.16.5.10",      # private 172.16/12 -> keep (2)
		"172.32.0.1",       # public -> drop
		"192.168.0.1",      # private 192.168/16 -> keep (3)
		"8.8.8.8",          # public -> drop
		"::1",              # ipv6 -> drop
		"192.168.1.50",     # private -> keep (4)
		"10.10.10.10",      # private -> drop because cap is 4
	])

	var filtered = PairingCodes.filter_addrs(test_addrs)
	if filtered.size() != 4:
		push_error("pairing_codes_test: filtered size != 4: %d" % filtered.size())
		return false

	if filtered[0] != "10.0.1.25" or filtered[1] != "172.16.5.10" or filtered[2] != "192.168.0.1" or filtered[3] != "192.168.1.50":
		push_error("pairing_codes_test: filtered addresses mismatch: " + str(filtered))
		return false

	# 7. QR payload format
	var dummy_identity = {
		"pc_id": "testpcid123456789012345678901234",
		"fingerprint_hex": func(): return "testfp1234567890"
	}
	# RefCounted wrapper for dummy identity if needed, or pass dummy object
	var payload_str = PairingCodes.qr_payload(null, ["192.168.1.1"], 7350, "abcd1234abcd1234")
	var parsed = JSON.parse_string(payload_str)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("pairing_codes_test: failed to parse qr_payload JSON")
		return false
	if parsed.get("v") != 2 or parsed.get("port") != 7350 or parsed.get("pair") != "abcd1234abcd1234":
		push_error("pairing_codes_test: qr_payload fields mismatch")
		return false

	return true
