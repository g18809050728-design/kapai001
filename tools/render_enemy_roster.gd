extends SceneTree


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var output := OS.get_environment("CAMPUS_ENEMY_PROBE_OUT")
	if output.is_empty() or FileAccess.file_exists(output.path_join("probe.json")):
		push_error("Choose fresh CAMPUS_ENEMY_PROBE_OUT")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 1250)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1400, 1250)
	background.color = Color("e6dfd1")
	viewport.add_child(background)
	var records := []
	var selection := OS.get_environment("CAMPUS_ENEMY_IDS").split(",", false)
	if selection.is_empty():
		selection = EnemyArt.ids()
	for id: String in selection:
		var creature := NativeActorRig.new()
		viewport.add_child(creature)
		if not creature.configure(EnemyArt.rig_path(id)):
			push_error("Enemy rig failed: " + id)
			quit(1)
			return
		creature.fit(Vector2(800, 1080))
		creature.position.x = 700
		for item: Array in [["neutral", 0.0], ["action", .4], ["hit", .16], ["guard", .4], ["depart", .55], ["phase", .5], ["enter", .3]]:
			creature.set_motion(false)
			if item[0] != "neutral":
				creature.set_motion(true)
				creature.loop_player.speed_scale = 0.0
				creature.cue(str(item[0]), 1.0)
				creature.action_player.speed_scale = 0.0
				creature.action_player.seek(creature.action_length(str(item[0])) * float(item[1]), true)
				creature._update_feet()
				creature._update_drawings()
				creature._update_expression()
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s-%s.png" % [id, item[0]]
			var code := viewport.get_texture().get_image().save_png(output.path_join(file))
			records.append({"id": id, "version": EnemyArt.version(id), "pose": item[0], "fraction": item[1],
				"file": file, "save_error": code, "state": creature.debug_snapshot()})
			creature.finish_action()
		creature.free()
	viewport.free()
	var report := FileAccess.open(output.path_join("probe.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"engine": Engine.get_version_info(), "scope": "actual graphical renderer, controlled full-body poses; not published gameplay commands", "captures": records}, "\t"))
	report.close()
	print("ENEMY_ROSTER_PROBE=", records.size())
	quit(0)
