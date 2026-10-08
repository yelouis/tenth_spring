extends Node2D

func _ready() -> void:
	DB.init_db()
	SyncServer.start_server()
