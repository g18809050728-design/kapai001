extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = preload("res://tests/suites/test_ui_battle_map_feedback.gd").new()
	suite.capture_enabled = DisplayServer.get_name() != "headless" or "--capture" in OS.get_cmdline_user_args()
	var failures: Array[String] = await suite.run()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
