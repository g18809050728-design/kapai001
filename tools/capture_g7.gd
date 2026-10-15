extends SceneTree

var _shell: GameShell
var _session: GameSession
var _output: String
var _steps: Array[Dictionary] = []


func _initialize() -> void:
	_output = "res://artifacts/g7-visual-%s" % Time.get_unix_time_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	root.size = Vector2i(1280, 800)
	_session = GameSession.new(SaveStore.new("user://g7-visual-%s" % Time.get_ticks_usec()))
	_shell = GameShell.new()
	_shell.session = _session
	root.add_child(_shell)
	await _save("01-menu")
	if not _shell.press("menu:settings"):
		_fail("menu:settings")
		return
	await _save("02-settings")
	_shell.press("settings:back")
	_shell.press("menu:new")
	await _save("03-setup")
	if not _shell.press("setup:start") or _session.get_view().run_id == null:
		_fail("setup:start")
		return
	await _save("04-map")
	var node_id := str(_session.get_view().run.reachable_node_ids[0])
	if not _shell.press("node:" + node_id) or _session.get_view().battle == null:
		_fail("node:" + node_id)
		return
	await _save("05-battle")
	for card in _session.get_view().battle.hand:
		if card.definition_id == "K03" and not _shell.page.button_disabled("card:" + card.card_id):
			_shell.press("card:" + card.card_id)
			if _session.get_view().pending_choice != null:
				await _save("06-choice")
			break
	root.size = Vector2i(960, 640)
	await _save("07-battle-960")
	var file := FileAccess.open(_output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"screens": _steps, "isolated_storage": true}, "\t"))
	file.close()
	_shell.free()
	print("G7 visual capture passed: " + _output)
	quit(0)


func _save(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := _output.path_join(label + ".png")
	var result := root.get_texture().get_image().save_png(path)
	_steps.append(
		{
			"label": label,
			"path": path,
			"save_error": result,
			"screen": String(_session.get_view().screen),
			"window_size": [root.size.x, root.size.y],
			"run_id": _session.get_view().run_id,
			"revision": _session.get_view().revision
		}
	)
	if result != OK:
		_fail("capture " + label)


func _fail(uid: String) -> void:
	push_error("G7 visual capture failed at " + uid)
	quit(1)
