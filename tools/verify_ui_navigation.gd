extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for name in ["test_ui_map_activation", "test_ui_navigation_revision", "test_ui_battle_layout"]:
		var script: Script = load("res://tests/suites/" + name + ".gd")
		if script == null or not script.can_instantiate():
			failures.append("Cannot load " + name)
			continue
		failures.append_array(await script.new().run())
	await create_timer(.1).timeout
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
