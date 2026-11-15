extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in ["test_ui_semantic_vfx", "test_ui_battle_choice", "test_ui_damage_popup", "test_ui_battle_map_feedback"]:
		var script: Script = load("res://tests/suites/" + path + ".gd")
		if script == null or not script.can_instantiate():
			failures.append("Cannot load " + path)
			continue
		var results: Array[String] = await script.new().run()
		failures.append_array(results)
	print("CHARACTER_CONTACT_CHECKS=", JSON.stringify({"failures": failures}))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
