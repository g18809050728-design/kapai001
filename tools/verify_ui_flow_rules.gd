extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in ["test_annual_map_generator_v3", "test_difficulty", "test_adaptive_maps"]:
		var script: GDScript = load("res://tests/suites/%s.gd" % path)
		if script != null and script.can_instantiate():
			failures.append_array(script.new().run())
		else:
			failures.append("Cannot load suite " + path)
	for failure in failures:
		push_error(failure)
	print("UI_FLOW_RULE_FAILURES=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
