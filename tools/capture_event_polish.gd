extends SceneTree

var output := "res://artifacts/verification/event-polish-20261115/before"
var fixtures = preload("res://tools/event_polish_fixtures.gd").new()
var captures: Array = []
var full := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		if argument == "--full":
			full = true
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for key in ["V01", "V03", "V04", "V10", "C", "I", "L", "LAB", "T", "ST", "FAMILIAR"]:
		var shell: GameShell = fixtures.room("E" if key.begins_with("V") or key == "FAMILIAR" else key, key if key.begins_with("V") else ("V10" if key == "FAMILIAR" else ""), key == "FAMILIAR")
		if shell == null:
			continue
		for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
			for scale in ([100, 125, 150] if full else [100]):
				await _present(shell, dimensions, scale)
				shell.page._scroll.scroll_vertical = 0
				await _save(shell, "%s-%d-%d" % [key, dimensions.x, scale])
				if key.begins_with("V") and full:
					shell.page._scroll.scroll_vertical = int(shell.page._scroll.get_v_scroll_bar().max_value)
					await _save(shell, "%s-%d-%d-bottom" % [key, dimensions.x, scale])
		shell.free()
	var session := GameSession.new(SaveStore.new("user://event-polish-menu-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	var shell: GameShell = fixtures.helpers.attach_shell(session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in ([100, 125, 150] if full else [100]):
			await _present(shell, dimensions, scale)
			shell.show_screen("settings")
			await _save(shell, "settings-%d-%d" % [dimensions.x, scale])
			shell.show_screen("menu")
			shell.press("menu:test")
			await _save(shell, "test-home-%d-%d" % [dimensions.x, scale])
			shell.show_screen("menu")
	# Public test room entry, isolated by SaveStore/TestStore.
	shell.press("menu:test")
	shell.press("test:start")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in ([100, 125, 150] if full else [100]):
			await _present(shell, dimensions, scale)
			await _save(shell, "test-hud-%d-%d" % [dimensions.x, scale])
	var outcome := session.set_test_outcome(shell._test_context(), "won")
	if not outcome.accepted:
		fixtures.failures.append("Public manual test outcome failed")
	shell.refresh()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in ([100, 125, 150] if full else [100]):
			await _present(shell, dimensions, scale)
			await _save(shell, "test-result-%d-%d" % [dimensions.x, scale])
	shell.free()
	var report := {"captures": captures, "failures": fixtures.failures,
		"scope": "isolated controlled route checkpoints, public room commands, real graphical Godot; not a natural playthrough"}
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("EVENT_POLISH_CAPTURE=", captures.size(), " failures=", fixtures.failures.size())
	for failure in fixtures.failures:
		push_error(failure)
	quit(0 if fixtures.failures.is_empty() else 1)


func _present(shell: GameShell, dimensions: Vector2i, scale: int) -> void:
	root.size = dimensions
	shell.session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await _frames(8)


func _frames(count: int = 5) -> void:
	for frame in count:
		await process_frame


func _save(shell: GameShell, caption: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(output.path_join(caption + ".png"))
	if code != OK:
		fixtures.failures.append("Capture failed: " + caption)
	var event_view: Dictionary = shell.page.view.event if shell.page.view.get("event") is Dictionary else {}
	captures.append({"file": caption + ".png", "size": [root.size.x, root.size.y],
		"screen": str(shell.session.get_view().screen), "event_id": str(event_view.get("definition_id", "")),
		"scale": UiStyle.text_scale, "save_error": code})
