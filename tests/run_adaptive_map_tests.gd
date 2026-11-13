extends SceneTree

func _initialize() -> void:
	var suite: Script = load("res://tests/suites/test_adaptive_maps.gd")
	if suite == null or not suite.can_instantiate():
		push_error("adaptive map suite did not compile")
		quit(1)
		return
	var failures: Array[String] = suite.new().run()
	for failure in failures:
		push_error(failure)
	print("ADAPTIVE_MAP_SUITE=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)
