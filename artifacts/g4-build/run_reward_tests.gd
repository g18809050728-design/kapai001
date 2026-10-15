extends SceneTree


func _initialize() -> void:
	var suite = load("res://tests/suites/test_run_transactions.gd").new()
	var failures: Array[String] = suite.run()
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
