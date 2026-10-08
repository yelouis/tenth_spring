class_name PcIdentity
extends RefCounted

# PC Identity management (Decision 11 / §B3)
# Holds RSA-2048 key, self-signed certificate, 32-hex pcId, and certificate DER SHA-256 fingerprint.

const DEFAULT_DIR: String = "user://sync_identity/"

var _dir_path: String = DEFAULT_DIR
var key: CryptoKey = null
var cert: X509Certificate = null
var pc_id: String = ""

func configure_dir(path: String) -> void:
	_dir_path = path if path.ends_with("/") else path + "/"

func get_dir() -> String:
	return _dir_path

func fingerprint_hex() -> String:
	if cert == null:
		return ""
	return fingerprint_of_pem(cert.save_to_string())

static func fingerprint_of_pem(pem: String) -> String:
	var lines = pem.split("\n")
	var b64_clean = ""
	for line in lines:
		var s = line.strip_edges()
		if s.begins_with("-----") or s == "":
			continue
		b64_clean += s
	var der = Marshalls.base64_to_raw(b64_clean)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(der)
	var digest = ctx.finish()
	return digest.hex_encode().to_lower()

func load_or_create() -> bool:
	var key_file = _dir_path + "pc.key"
	var cert_file = _dir_path + "pc.crt"
	var id_file = _dir_path + "pc_id.txt"

	if FileAccess.file_exists(key_file) and FileAccess.file_exists(cert_file) and FileAccess.file_exists(id_file):
		var k = CryptoKey.new()
		var err_k = k.load(key_file)
		if err_k != OK:
			push_error("Failed to load key from " + key_file)
			return false

		var c = X509Certificate.new()
		var err_c = c.load(cert_file)
		if err_c != OK:
			push_error("Failed to load cert from " + cert_file)
			return false

		var id_str = FileAccess.get_file_as_string(id_file).strip_edges()
		if id_str.length() != 32:
			push_error("Invalid pc_id length in " + id_file)
			return false

		key = k
		cert = c
		pc_id = id_str
		return true

	# Create new identity
	var dir_err = DirAccess.make_dir_recursive_absolute(_dir_path)
	if dir_err != OK:
		push_error("Failed to create identity dir: " + _dir_path)
		return false

	var crypto = Crypto.new()
	var new_key = crypto.generate_rsa(2048)
	if new_key == null:
		push_error("Failed to generate RSA 2048 key")
		return false

	var dt = Time.get_datetime_dict_from_system(true)
	var not_before = "%04d%02d%02d%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var not_after = "%04d%02d%02d%02d%02d%02d" % [dt.year + 20, dt.month, dt.day, dt.hour, dt.minute, dt.second]

	var new_cert = crypto.generate_self_signed_certificate(new_key, "CN=tenthspring-pc,O=Tenth Spring,C=US", not_before, not_after)
	if new_cert == null:
		push_error("Failed to generate self-signed certificate")
		return false

	var rand_bytes = crypto.generate_random_bytes(16)
	var new_pc_id = rand_bytes.hex_encode().to_lower()

	var save_k_err = new_key.save(key_file)
	if save_k_err != OK:
		push_error("Failed to save key to " + key_file)
		return false

	var save_c_err = new_cert.save(cert_file)
	if save_c_err != OK:
		push_error("Failed to save cert to " + cert_file)
		return false

	var fa = FileAccess.open(id_file, FileAccess.WRITE)
	if fa == null:
		push_error("Failed to write pc_id to " + id_file)
		return false
	fa.store_string(new_pc_id)
	fa.close()

	key = new_key
	cert = new_cert
	pc_id = new_pc_id
	return true
