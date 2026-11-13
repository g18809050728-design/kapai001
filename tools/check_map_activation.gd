extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = await load("res://tests/suites/test_ui_map_activation.gd").new().run()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
