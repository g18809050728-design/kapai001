extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite = preload("res://tests/suites/test_ui_followup.gd").new()
	var failures: Array[String] = await suite.run()
	await create_timer(.1).timeout
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
