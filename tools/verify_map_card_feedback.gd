extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in ["test_ui_map_activation", "test_ui_card_categories"]:
		failures.append_array(await load("res://tests/suites/%s.gd" % path).new().run())
	for failure in failures:
		push_error(failure)
	print("MAP_CARD_FEEDBACK=", JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
