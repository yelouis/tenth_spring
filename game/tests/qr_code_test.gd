extends Node

# Unit test for QrCode parity with Nayuki reference fixtures
const STR_HELLO: String = "HELLO"
const STR_120CHAR: String = "Tenth Spring: A post-collapse world where physical scouting reveals the map. Walk to discover places and creatures! 1234"
const STR_PAYLOAD: String = '{"v":2,"pcId":"0123456789abcdef0123456789abcdef","fp":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","addrs":["192.168.1.20"],"port":7350,"pair":"fedcba9876543210fedcba9876543210"}'

func run_test() -> bool:
	if not _test_fixture(STR_HELLO, "res://tests/fixtures/qr_hello.txt"):
		push_error("qr_code_test: HELLO fixture mismatch")
		return false
	if not _test_fixture(STR_120CHAR, "res://tests/fixtures/qr_120char.txt"):
		push_error("qr_code_test: 120char fixture mismatch")
		return false
	if not _test_fixture(STR_PAYLOAD, "res://tests/fixtures/qr_payload.txt"):
		push_error("qr_code_test: payload fixture mismatch")
		return false

	# Test render_to_texture
	var matrix = QrCode.encode_text(STR_HELLO)
	var tex = QrCode.render_to_texture(matrix, 4)
	if tex == null:
		push_error("qr_code_test: render_to_texture returned null")
		return false
	# HELLO size is 21, quiet zone is 4 on each side -> (21 + 8) * 4 = 116
	if tex.get_width() != 116 or tex.get_height() != 116:
		push_error("qr_code_test: render_to_texture dimensions incorrect: %dx%d" % [tex.get_width(), tex.get_height()])
		return false

	return true

func _test_fixture(input_text: String, fixture_path: String) -> bool:
	var matrix = QrCode.encode_text(input_text)
	if matrix.is_empty():
		return false
	if not FileAccess.file_exists(fixture_path):
		push_error("Fixture file missing: " + fixture_path)
		return false
	var text = FileAccess.get_file_as_string(fixture_path).strip_edges()
	var raw_lines = text.split("\n")
	var lines: Array[String] = []
	for l in raw_lines:
		var line = l.strip_edges()
		if line != "":
			lines.append(line)

	if matrix.size() != lines.size():
		push_error("Matrix row count mismatch: %d vs %d" % [matrix.size(), lines.size()])
		return false

	for y in range(matrix.size()):
		var line = lines[y]
		if matrix[y].size() != line.length():
			push_error("Matrix column count mismatch at row %d" % y)
			return false
		for x in range(matrix[y].size()):
			var expected_dark = (line.substr(x, 1) == "1")
			if matrix[y][x] != expected_dark:
				push_error("Module mismatch at (%d, %d)" % [x, y])
				return false
	return true
