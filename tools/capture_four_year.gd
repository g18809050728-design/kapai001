extends SceneTree

const OUT := "res://artifacts/verification/four-year-20261104/visual-final"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	var runner = load("res://tests/suites/test_four_year.gd").new()
	var failures: Array[String] = runner.run()
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	var session := GameSession.new(SaveStore.new("user://four-year-capture-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	shell.show_screen("")
	await _save("map-1280")
	shell.press("node:" + str(session.get_view().run.reachable_node_ids[0]))
	await _save("battle-1280")
	root.size = Vector2i(960, 600)
	await _save("battle-960")
	root.size = Vector2i(1280, 800)
	session._state.battle = null
	for kind in ["relic", "relic_full", "grand", "direction", "destination", "service", "summary"]:
		session._state.run = runner._checkpoints[kind].copy_for_write()
		session._state.random_snapshot = runner._rng.duplicate(true)
		shell.show_screen("")
		await _save(kind + "-1280")
		if kind in ["relic_full", "grand"]:
			root.size = Vector2i(960, 600)
			await _save(kind + "-960")
			root.size = Vector2i(1280, 800)
	shell.show_screen("settings")
	await _save("settings-1280")
	shell.free()
	print("FOUR_YEAR_VISUAL_CAPTURE=passed")
	quit(0)

func _save(label: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var code := image.save_png(OUT.path_join(label + ".png"))
	if code != OK:
		push_error("capture failed: " + label)
		quit(1)
