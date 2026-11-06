extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var followup = preload("res://tests/suites/test_ui_followup.gd").new()
	followup.capture_enabled = DisplayServer.get_name() != "headless"
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		await followup._battle_and_map(str(dimensions.x))
	var layout = preload("res://tests/suites/test_ui_battle_card_inspection.gd").new()
	layout.capture_enabled = followup.capture_enabled
	var failures: Array[String] = await layout.run()
	failures.append_array(followup._failures)
	var captures: Array = followup._captures + layout._captures
	if followup.capture_enabled:
		var file := FileAccess.open(followup.OUT.path_join("capture.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(captures, "\t"))
	print("BATTLE_CARD_INPUT=", JSON.stringify({"failures": failures, "captures": captures.size(), "scope": "real pointer, 5/10-card fan, two sizes, 100/150% text, delayed full details and I toggle; isolated state"}))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
