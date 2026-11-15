extends SceneTree


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var output := OS.get_environment("CAMPUS_ENEMY_SEQUENCE_OUT")
	if output.is_empty() or FileAccess.file_exists(output.path_join("sequences.json")):
		push_error("Choose fresh CAMPUS_ENEMY_SEQUENCE_OUT")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 1000)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1000, 1000)
	background.color = Color("e6dfd1")
	viewport.add_child(background)
	var records := []
	for id: String in ["N01", "N02", "N03", "N04", "B01", "E04_3", "Q0A_3_1", "FY_B1_TASK", "FY_ROUTE_research_TASK"]:
		if EnemyArt.rig_path(id).is_empty():
			continue
		var creature := NativeActorRig.new()
		viewport.add_child(creature)
		if not creature.configure(EnemyArt.rig_path(id)):
			push_error("Enemy rig failed: " + id)
			quit(1)
			return
		creature.fit(Vector2(650, 900))
		creature.position.x = 500
		for pose: String in ["idle", "action", "hit"]:
			creature.finish_action()
			creature.set_motion(true)
			if pose != "idle":
				creature.cue(pose, 1.0)
			var duration := 1.8 if pose == "idle" else creature.action_length(pose)
			var started := Time.get_ticks_msec()
			var ordinal := 0
			while Time.get_ticks_msec() - started < duration * 1000:
				await RenderingServer.frame_post_draw
				var elapsed := Time.get_ticks_msec() - started
				var file := "%s-%s-%03d.jpg" % [id, pose, ordinal]
				var code := viewport.get_texture().get_image().save_jpg(output.path_join(file), .92)
				records.append({"id": id, "pose": pose, "file": file, "elapsed_ms": elapsed, "save_error": code,
					"state": creature.debug_snapshot()})
				ordinal += 1
				await create_timer(.065).timeout
			await process_frame
		creature.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
	var file := FileAccess.open(output.path_join("sequences.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "actual realtime graphical native-rig sequences; controlled cues, not published gameplay commands",
		"engine": Engine.get_version_info(), "frames": records}, "\t"))
	file.close()
	print("ENEMY_SEQUENCE_FRAMES=", records.size())
	quit(0)
