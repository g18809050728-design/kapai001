extends SceneTree

func _initialize() -> void:
	var session := GameSession.new()
	var storage: SessionStorageView = session.inspect_saves().data
	print("PLAYER_STORAGE_PROBE=", JSON.stringify({
		"user_data_dir": OS.get_user_data_dir(),
		"has_save": storage.has_save,
		"can_continue": storage.can_continue,
		"has_active_session": storage.has_active_session,
		"error": storage.save_error.to_dictionary() if storage.save_error != null else null
	}))
	session.free()
	quit(0)
