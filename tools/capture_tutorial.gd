extends SceneTree

## Captures the first-run tutorial at desktop and compact sizes for visual
## review. Uses isolated storage; it never touches a real save.

var _shell: GameShell
var _output := "res://artifacts/verification/tutorial-20261126/visual"
var _scale := 100


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--scale="):
			_scale = int(argument.trim_prefix("--scale="))
	call_deferred("_run")


func _run() -> void:
	if _scale != 100 and not _output.ends_with(str(_scale)):
		_output += "-" + str(_scale)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	root.size = Vector2i(1280, 800)
	var session := GameSession.new(
		SaveStore.new("user://tutorial-capture-%d" % Time.get_ticks_usec())
	)
	session.update_settings({"autosave": false})
	var preferences: Dictionary = session.get_presentation_settings()
	preferences["text_scale"] = _scale
	session.update_settings({"presentation": preferences})
	_shell = GameShell.new()
	_shell.session = session
	_shell.web_first_play_tutorial = true
	root.add_child(_shell)
	await create_timer(0.5).timeout
	if not _shell.press("menu:new"):
		_fail("menu:new")
		return
	await create_timer(0.2).timeout
	if not _shell.press("setup:start"):
		_fail("setup:start")
		return
	await create_timer(0.6).timeout
	if not _shell.tutorial_visible():
		_fail("first-play intro is not visible")
		return
	await _snap("01-intro-values")
	_shell.press("tutorial:next")
	await create_timer(0.4).timeout
	await _snap("02-intro-map")
	_shell.press("tutorial:next")
	await create_timer(0.3).timeout
	await _snap("03-intro-battle")
	_shell.press("tutorial:next")
	await create_timer(0.3).timeout
	var reachable: Array = _shell.session.get_view().run.reachable_node_ids
	if reachable.is_empty():
		_fail("no reachable node")
		return
	_shell.press("node:" + str(reachable[0]))
	_shell.press("map:enter")
	await create_timer(3.0).timeout
	if not _shell.tutorial_visible():
		_fail("first-battle tutorial is not visible")
		return
	await _snap("04-battle-intent")
	_shell.press("tutorial:next")
	await create_timer(0.4).timeout
	await _snap("05-battle-focus")
	_shell.press("tutorial:next")
	await create_timer(0.4).timeout
	await _snap("06-battle-end-turn")
	root.size = Vector2i(960, 600)
	await create_timer(0.8).timeout
	await _snap("07-battle-end-turn-960")
	root.size = Vector2i(1280, 800)
	await create_timer(0.5).timeout
	_shell.press("tutorial:next")
	await create_timer(0.3).timeout
	await _snap("08-battle-after-tutorial")
	_shell.free()
	print("TUTORIAL_CAPTURE=", _output)
	quit(0)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _output.path_join(name + ".png")
	image.save_png(path)
	print("TUTORIAL_SHOT=", path)


func _fail(where: String) -> void:
	push_error("tutorial capture failed: " + where)
	quit(1)
