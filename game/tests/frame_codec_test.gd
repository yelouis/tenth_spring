extends Node

# Unit test for FrameCodec encode and FrameReader parsing
func run_test() -> bool:
	# 1. Round trip test
	var msg1 = {"type": "HELLO", "peerId": "test_peer_1", "schemaVersion": 1, "deviceToken": "abc123xyz"}
	var encoded = FrameCodec.encode(msg1)
	var reader1 = FrameCodec.FrameReader.new()
	reader1.feed(encoded)
	var decoded1 = reader1.next_frame()
	if decoded1 == null or typeof(decoded1) != TYPE_DICTIONARY:
		push_error("frame_codec_test: round trip failed to decode dictionary")
		return false
	if decoded1.get("type") != "HELLO" or decoded1.get("peerId") != "test_peer_1":
		push_error("frame_codec_test: round trip field mismatch")
		return false

	# 2. Split across 3 feeds
	var reader2 = FrameCodec.FrameReader.new()
	var part1_len = mini(2, encoded.size())
	var part2_len = mini(5, encoded.size() - part1_len)
	var feed1 = encoded.slice(0, part1_len)
	var feed2 = encoded.slice(part1_len, part1_len + part2_len)
	var feed3 = encoded.slice(part1_len + part2_len)

	reader2.feed(feed1)
	if reader2.next_frame() != null:
		push_error("frame_codec_test: unexpected frame on incomplete feed 1")
		return false
	reader2.feed(feed2)
	if reader2.next_frame() != null:
		push_error("frame_codec_test: unexpected frame on incomplete feed 2")
		return false
	reader2.feed(feed3)
	var decoded2 = reader2.next_frame()
	if decoded2 == null or decoded2.get("type") != "HELLO":
		push_error("frame_codec_test: failed to decode split frame")
		return false

	# 3. Two frames in one feed
	var msg2 = {"type": "ACK", "status": "ack", "lastAppliedSeq": 42}
	var encoded2 = FrameCodec.encode(msg2)
	var combined = PackedByteArray()
	combined.append_array(encoded)
	combined.append_array(encoded2)

	var reader3 = FrameCodec.FrameReader.new()
	reader3.feed(combined)
	var f1 = reader3.next_frame()
	var f2 = reader3.next_frame()
	var f3 = reader3.next_frame()
	if f1 == null or f1.get("type") != "HELLO":
		push_error("frame_codec_test: two-frames feed: frame 1 mismatch")
		return false
	if f2 == null or f2.get("type") != "ACK" or f2.get("lastAppliedSeq") != 42:
		push_error("frame_codec_test: two-frames feed: frame 2 mismatch")
		return false
	if f3 != null:
		push_error("frame_codec_test: two-frames feed: unexpected third frame")
		return false

	# 4. N = 0 -> error
	var zero_header = PackedByteArray([0, 0, 0, 0])
	var reader4 = FrameCodec.FrameReader.new()
	reader4.feed(zero_header)
	var res4 = reader4.next_frame()
	if res4 != null or reader4.error == "":
		push_error("frame_codec_test: N=0 did not trigger error")
		return false

	# 5. N = 1_048_577 -> error
	# 1_048_577 is 0x00100001
	var oversize_header = PackedByteArray([0x00, 0x10, 0x00, 0x01])
	var reader5 = FrameCodec.FrameReader.new()
	reader5.feed(oversize_header)
	var res5 = reader5.next_frame()
	if res5 != null or reader5.error == "":
		push_error("frame_codec_test: N=1048577 did not trigger error")
		return false

	return true
