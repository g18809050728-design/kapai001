extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: GDScript = load("res://tests/suites/test_ui_flow_revision.gd")
	if script == null or not script.can_instantiate():
		push_error("UI flow revision suite cannot load")
		quit(1)
		return
	var failures: Array[String] = await script.new().run()
	await create_timer(.1).timeout
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
