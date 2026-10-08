extends Node

# Unit test for PcIdentity certificate generation, loading, and fingerprint calculation
const EXPECTED_FIXTURE_FP: String = "ffbbb32bc02ef1e5bef3a6c1019c786cf02a886df08c2eaea37eadfe406b4f4f"
const TEST_IDENTITY_DIR: String = "user://test/sync_identity/"

func run_test() -> bool:
	# 1. Parity test with fixture test_cert.pem
	var fixture_pem = FileAccess.get_file_as_string("res://tests/fixtures/test_cert.pem")
	var fp = PcIdentity.fingerprint_of_pem(fixture_pem)
	if fp != EXPECTED_FIXTURE_FP:
		push_error("pc_identity_test: test_cert.pem fingerprint mismatch: %s vs %s" % [fp, EXPECTED_FIXTURE_FP])
		return false

	# Clean test directory before run
	_clean_test_dir(TEST_IDENTITY_DIR)

	# 2. First call to load_or_create creates new key, cert, and pc_id
	var identity = PcIdentity.new()
	identity.configure_dir(TEST_IDENTITY_DIR)
	if not identity.load_or_create():
		push_error("pc_identity_test: load_or_create failed on fresh dir")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false

	var initial_fp = identity.fingerprint_hex()
	var initial_id = identity.pc_id
	if initial_fp.length() != 64:
		push_error("pc_identity_test: invalid fingerprint length: " + initial_fp)
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false
	if initial_id.length() != 32:
		push_error("pc_identity_test: invalid pc_id length: " + initial_id)
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false

	# Check that files were written on disk
	if not FileAccess.file_exists(TEST_IDENTITY_DIR + "pc.key"):
		push_error("pc_identity_test: pc.key missing")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false
	if not FileAccess.file_exists(TEST_IDENTITY_DIR + "pc.crt"):
		push_error("pc_identity_test: pc.crt missing")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false
	if not FileAccess.file_exists(TEST_IDENTITY_DIR + "pc_id.txt"):
		push_error("pc_identity_test: pc_id.txt missing")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false

	# 3. Second call loads existing identity and matches fingerprint and pc_id
	var identity2 = PcIdentity.new()
	identity2.configure_dir(TEST_IDENTITY_DIR)
	if not identity2.load_or_create():
		push_error("pc_identity_test: second load_or_create failed")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false

	if identity2.fingerprint_hex() != initial_fp:
		push_error("pc_identity_test: reloaded fingerprint mismatch")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false
	if identity2.pc_id != initial_id:
		push_error("pc_identity_test: reloaded pc_id mismatch")
		_clean_test_dir(TEST_IDENTITY_DIR)
		return false

	_clean_test_dir(TEST_IDENTITY_DIR)
	return true

func _clean_test_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		var da = DirAccess.open(path)
		if da != null:
			for f in da.get_files():
				da.remove(f)
