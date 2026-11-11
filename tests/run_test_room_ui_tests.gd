extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite_script: Script = load("res://tests/suites/test_test_room_ui.gd")
	var failures: Array[String] = []
	if suite_script != null and suite_script.can_instantiate():
		failures.append_array(await suite_script.new().run())
	else:
		failures.append("test room UI suite failed to load")
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("TEST ROOM UI tests passed")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
