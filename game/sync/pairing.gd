class_name PairingCodes
extends RefCounted

# Pairing codes and QR payload generator (Decision 11 / §B3)

const EXPIRATION_SECONDS: int = 600

var _active_code: String = ""
var _code_created_at: int = 0

func new_code(now_unix: int) -> String:
	var crypto = Crypto.new()
	var bytes = crypto.generate_random_bytes(16)
	_active_code = bytes.hex_encode().to_lower()
	_code_created_at = now_unix
	return _active_code

func get_active_code() -> String:
	return _active_code

func get_code_created_at() -> int:
	return _code_created_at

func consume(code: String, now_unix: int) -> bool:
	if _active_code == "":
		return false
	if now_unix - _code_created_at > EXPIRATION_SECONDS:
		_active_code = ""
		return false
	if code.length() != _active_code.length():
		return false

	var crypto = Crypto.new()
	var trusted = _active_code.to_ascii_buffer()
	var received = code.to_ascii_buffer()
	var is_match = crypto.constant_time_compare(trusted, received)

	if is_match:
		_active_code = ""
		return true
	return false

static func filter_addrs(all: PackedStringArray) -> Array:
	var result: Array = []
	for addr in all:
		if _is_private_ipv4(addr):
			result.append(addr)
			if result.size() == 4:
				break
	return result

static func qr_payload(identity: Variant, addrs: Array, port: int, code: String) -> String:
	var d = {
		"v": 2,
		"pcId": identity.pc_id if identity != null else "",
		"fp": identity.fingerprint_hex() if identity != null else "",
		"addrs": addrs,
		"port": port,
		"pair": code
	}
	return JSON.stringify(d)

static func _is_private_ipv4(addr: String) -> bool:
	var parts = addr.split(".")
	if parts.size() != 4:
		return false
	var octets: Array[int] = []
	for p in parts:
		if not p.is_valid_int():
			return false
		var val = p.to_int()
		if val < 0 or val > 255:
			return false
		if p != str(val):
			return false
		octets.append(val)

	var b0 = octets[0]
	var b1 = octets[1]

	# 10.0.0.0/8
	if b0 == 10:
		return true

	# 172.16.0.0/12
	if b0 == 172 and b1 >= 16 and b1 <= 31:
		return true

	# 192.168.0.0/16
	if b0 == 192 and b1 == 168:
		return true

	return false
