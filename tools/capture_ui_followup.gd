extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = preload("res://tests/suites/test_ui_followup.gd").new()
	suite.capture_enabled = true
	var failures: Array[String] = await suite.run()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
