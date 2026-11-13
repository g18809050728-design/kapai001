extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for suite in ["test_ui_card_categories", "test_ui_flow_feedback"]:
		failures.append_array(await load("res://tests/suites/" + suite + ".gd").new().run())
	if failures.is_empty():
		print("PLAYABLE_PRESENTATION_CHECK=passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
