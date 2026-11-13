extends SceneTree

func _initialize() -> void:
	var catalog := ContentDB.new("res://data/four_year")
	var result := catalog.load("campus_four_year")
	if not result.ok:
		push_error(str(result.error.to_dictionary()))
		quit(1)
		return
	var info := catalog.get_info()
	print("FOUR_YEAR_CONTENT_BASELINE=" + JSON.stringify({"id": info.id, "version": info.content_version, "hash": info.content_hash, "enabled": info.enabled}))
	quit()
