extends SceneTree


func _initialize() -> void:
	var suite = load("res://tests/suites/test_run_nodes.gd").new()
	var failures: Array[String] = suite.run()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("G4 node, map, event and rest tests passed")
	quit(0 if failures.is_empty() else 1)
