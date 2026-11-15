extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode := str(arguments[0]) if not arguments.is_empty() else "test-full"
	if arguments.size() > 1:
		OS.set_environment("CAMPUS_COMPENDIUM_CAPTURE_OUT", arguments[1])
	var exit_code := 0
	var session := GameSession.new(SaveStore.new("user://compendium-lifecycle-%s" % Time.get_ticks_usec()))
	if mode == "capture":
		var capture = load("res://tools/capture_compendium.gd").new()
		exit_code = await capture.run(self)
		capture = null
		session.free()
	elif mode.begins_with("test-") or mode.contains("+"):
		var suite = load("res://tests/suites/test_ui_compendium.gd").new()
		suite._catalog = ContentDB.new("res://data/four_year")
		suite._catalog.load("campus_four_year")
		match mode:
			"test-full":
				var failures = await suite.run()
				print("FULL=", failures)
				session.free()
			"test-size":
				var old_size := root.size
				await suite._browse(session)
				root.size = old_size
				suite._restore_style()
			"data+browse", "data+pending", "browse+failure":
				if mode.begins_with("data+"):
					suite._check_catalogue(session.get_compendium().data)
				if mode == "data+browse" or mode == "browse+failure":
					await suite._browse(session)
				else:
					session.free()
				if mode.ends_with("+pending"):
					await suite._legacy_and_pending()
				if mode.ends_with("+failure"):
					await suite._failure_screen()
			"test-data":
				suite._check_catalogue(session.get_compendium().data)
				session.free()
			"test-browse":
				await suite._browse(session)
			"test-pending":
				await suite._legacy_and_pending()
				session.free()
			"test-failure":
				await suite._failure_screen()
				session.free()
			"test-pointer":
				await suite._pointer_and_keyboard()
				session.free()
		for failure in suite._failures:
			push_error(failure)
			exit_code = 1
		suite = null
	elif mode == "catalogue":
		var result := session.get_compendium()
		print("CATALOGUE=", result.ok)
		session.free()
	elif mode == "style":
		var picture := UiStyle.texture("R3-C-01")
		print("STYLE=", picture != null)
		session.free()
	else:
		var shell := GameShell.new()
		shell.session = session
		root.add_child(shell)
		if mode == "ui":
			shell.press("menu:compendium")
		for _frame in 6:
			await process_frame
		shell.free()
	for _frame in 6:
		await process_frame
	quit(exit_code)
