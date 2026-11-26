extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var args := OS.get_cmdline_user_args()
	var enemy_captures := "--enemy-debuff-captures" in args
	for path in [
		"test_ui_battle_status",
		"test_ui_battle_layout",
		"test_ui_battle_pointer",
		"test_ui_experience"
	]:
		if ("--capture-only" in args or enemy_captures) and path != "test_ui_battle_status":
			continue
		var suite = load("res://tests/suites/" + path + ".gd").new()
		if path == "test_ui_battle_status" and DisplayServer.get_name() != "headless":
			suite.capture_enabled = not enemy_captures
			suite.capture_enemy_debuffs = enemy_captures
		failures.append_array(await suite.run())
	for failure in failures:
		push_error(failure)
	print("BATTLE_STATUS_REGRESSION=", JSON.stringify(failures))
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)
