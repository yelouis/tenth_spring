extends Node2D

func _ready() -> void:
	DB.init_db()
	SyncServer.start_server()

func open_pairing_screen() -> void:
	var pairing_node = get_node_or_null("CanvasLayer/Pairing")
	if pairing_node != null:
		pairing_node.show()
		if pairing_node.has_method("refresh_code"):
			pairing_node.refresh_code()
