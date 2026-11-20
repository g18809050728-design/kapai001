extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	var suite = load("res://tests/suites/test_ui_text_editor.gd").new()
	var failures: Array[String] = await suite.run()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		var file := FileAccess.open(output + "/failures.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures": failures, "passed": failures.is_empty()}, "\t"))
		file.close()
	for failure in failures:
		push_error(failure)
	print("TEXT_EDITOR_TESTS=", "passed" if failures.is_empty() else "failed")
	quit(0 if failures.is_empty() else 1)
