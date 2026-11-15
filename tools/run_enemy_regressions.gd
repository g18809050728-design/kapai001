extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path: String in ["test_ui_enemy_art", "test_ui_semantic_vfx", "test_ui_battle_map_feedback"]:
		var suite: Script = load("res://tests/suites/" + path + ".gd")
		if suite == null or not suite.can_instantiate():
			failures.append("Enemy regression suite did not load: " + path)
		else:
			failures.append_array(await suite.new().run())
	for failure: String in failures:
		push_error(failure)
	await create_timer(.1).timeout
	print("ENEMY_REGRESSIONS=", JSON.stringify({"failures": failures}))
	quit(0 if failures.is_empty() else 1)
