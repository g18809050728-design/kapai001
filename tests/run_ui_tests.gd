extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in [
		"test_run_content_views",
		"test_ui_shell_pages",
		"test_ui_flow_feedback",
		"test_ui_battle_choice",
		"test_ui_battle_pointer",
		"test_ui_battle_polish"
	]:
		var script: Script = load("res://tests/suites/%s.gd" % path)
		if script == null or not script.can_instantiate():
			failures.append("G7 UI suite failed to load: " + path)
			continue
		var result = await script.new().run()
		failures.append_array(result)
	if failures.is_empty():
		print("G7 UI tests passed")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
