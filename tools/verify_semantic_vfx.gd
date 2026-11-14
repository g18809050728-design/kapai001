extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = await load("res://tests/suites/test_ui_semantic_vfx.gd").new().run()
	await create_timer(.15).timeout
	for failure in failures:
		push_error(failure)
	print("SEMANTIC_VFX_CHECK=", "passed" if failures.is_empty() else "failed")
	quit(0 if failures.is_empty() else 1)
