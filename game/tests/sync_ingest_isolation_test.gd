extends Node

# Golden Invariant 1 Capability Guard Test:
# Cartography, never cargo — sync ingest must NOT write or access inventory_item or base_state.

func run_test() -> bool:
	var file = FileAccess.open("res://autoloads/sync_server.gd", FileAccess.READ)
	if file == null:
		push_error("Failed to open sync_server.gd")
		return false

	var code = file.get_as_text()
	file.close()

	# Static capability audit: code must NOT mention inventory_item or base_state
	var illegal_tokens = ["inventory_item", "base_state", "item_id", "qty", "add_item"]
	for token in illegal_tokens:
		if code.contains(token):
			push_error("GOLDEN INVARIANT 1 VIOLATION: SyncServer contains reference to '%s'" % token)
			return false

	print("PASS: Golden Invariant 1 Sync Ingestion Isolation Guard Test")
	return true
