extends SceneTree


func _initialize() -> void:
	if not FileAccess.file_exists("res://src/run/annual_map_generator.gd"):
		push_error("AnnualMapGenerator is not implemented")
		quit(1)
		return
	var suite: RefCounted = load("res://tests/suites/test_annual_map_generator.gd").new()
	var failures: Array[String] = (
		suite.run_placement_checks() if OS.get_cmdline_user_args().has("--placement-only") else suite.run()
	)
	for failure in failures:
		push_error(failure)
	print("ANNUAL_MAP_GENERATOR_SUITE=" + ("passed" if failures.is_empty() else "failed"))
	quit(0 if failures.is_empty() else 1)
