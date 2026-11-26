extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in [
		"test_ui_battle_status",
		"test_ui_battle_layout",
		"test_ui_battle_pointer",
		"test_ui_experience"
	]:
		if "--capture-only" in OS.get_cmdline_user_args() and path != "test_ui_battle_status":
			continue
		var suite = load("res://tests/suites/" + path + ".gd").new()
		if path == "test_ui_battle_status":
			suite.capture_enabled = not DisplayServer.get_name() == "headless"
		failures.append_array(await suite.run())
	for failure in failures:
		push_error(failure)
	print("BATTLE_STATUS_REGRESSION=", JSON.stringify(failures))
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)
