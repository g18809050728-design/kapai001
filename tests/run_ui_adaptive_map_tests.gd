extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script: Script = load("res://tests/suites/test_ui_adaptive_maps.gd")
	if script == null or not script.can_instantiate():
		push_error("adaptive map UI suite failed to load")
		quit(1)
		return
	var failures: Array[String] = await script.new().run()
	for failure in failures:
		push_error(failure)
	print("ADAPTIVE_MAP_UI=", JSON.stringify({"failures": failures, "engine": Engine.get_version_info().string}))
	quit(0 if failures.is_empty() else 1)
