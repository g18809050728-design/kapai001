extends SceneTree


func _initialize() -> void:
	var suite_script: Script = load("res://tests/suites/test_test_room_core.gd")
	var failures: Array[String] = []
	if suite_script != null and suite_script.can_instantiate():
		failures.append_array(suite_script.new().run())
	else:
		failures.append("test room core suite failed to load")
	if failures.is_empty():
		print("TEST ROOM core tests passed")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
