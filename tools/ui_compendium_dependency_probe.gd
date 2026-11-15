extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script = load("res://tests/suites/test_ui_compendium.gd")
	var suite = script.new()
	var failures = await suite.run()
	suite = null
	script = null
	for _frame in 6:
		await process_frame
	print("DEPENDENCY_PROBE=", failures)
	quit(0 if failures.is_empty() else 1)
