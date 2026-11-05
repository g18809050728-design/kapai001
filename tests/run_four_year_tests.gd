extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = load("res://tests/suites/test_four_year.gd").new().run()
	failures.append_array(load("res://tests/suites/test_four_year_passives.gd").new().run())
	for failure in failures:
		push_error(failure)
	print("FOUR_YEAR_SUITE=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)
