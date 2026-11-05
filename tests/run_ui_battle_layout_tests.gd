extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: Script = load("res://tests/suites/test_ui_battle_layout.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var failures: Array[String] = await script.new().run()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
