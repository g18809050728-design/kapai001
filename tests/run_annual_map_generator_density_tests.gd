extends SceneTree


func _initialize() -> void:
	var suite: RefCounted = load("res://tests/suites/test_annual_map_generator_density.gd").new()
	var failures: Array[String] = suite.run()
	for failure in failures:
		push_error(failure)
	print("ANNUAL_MAP_GENERATOR_DENSITY_SUITE=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)
