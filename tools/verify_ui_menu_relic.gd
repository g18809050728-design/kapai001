extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = await preload("res://tests/suites/test_ui_menu_relic_revision.gd").new().run()
	await create_timer(.1).timeout
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
