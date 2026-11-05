extends SceneTree

const OUT := "res://artifacts/verification/four-year-20261104/setup-render"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var session := GameSession.new(SaveStore.new("user://setup-capture-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	var shell := GameShell.new()
	shell.session = session
	root.add_child(shell)
	if not shell.press("menu:new"):
		push_error("setup menu did not open")
		quit(1)
		return
	for viewport_size in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = viewport_size
		for i in 4: await process_frame
		var scroll := shell.page._scroll
		for position in ["top", "middle", "bottom"]:
			scroll.scroll_vertical = {"top": 0, "middle": int(scroll.get_v_scroll_bar().max_value / 2), "bottom": int(scroll.get_v_scroll_bar().max_value)}[position]
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var code := root.get_texture().get_image().save_png(OUT.path_join("setup-%d-%s.png" % [viewport_size.x, position]))
			if code != OK:
				push_error("setup screenshot failed")
				quit(1)
				return
	shell.free()
	print("FOUR_YEAR_SETUP_RENDER=passed")
	quit(0)
