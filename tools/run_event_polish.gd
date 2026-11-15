extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := "res://artifacts/verification/event-polish-20261115/checks-01"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var script = load("res://tests/suites/test_ui_event_polish.gd")
	if script == null or not script.can_instantiate():
		quit(2)
		return
	var suite = script.new()
	suite.capture_directory = output
	var failures: Array[String] = await suite.run()
	for failure in failures:
		push_error(failure)
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)
