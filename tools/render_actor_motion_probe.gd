extends SceneTree

## Quick actual renderer inspection before the full battle verification.
func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var output := OS.get_environment("CAMPUS_ACTOR_PILOT_OUT")
	if output.is_empty() or FileAccess.file_exists(output.path_join("probe.json")):
		push_error("Set a fresh CAMPUS_ACTOR_PILOT_OUT for the pose probe")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 1400)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1200, 1400)
	background.color = Color("e6dfd1")
	viewport.add_child(background)
	var records := []
	var samples: Array = [["neutral", 0.0], ["action", .42], ["hit", .16], ["guard", .4], ["depart", .55], ["phase", .5], ["enter", .3]]
	for pose in ["action", "hit", "guard"]:
		for step in range(21):
			samples.append([pose, float(step) / 20.0, step])
	for version in ["actor-proportions", "actor-motion"]:
		var character := "P04"
		var hero := NativeActorRig.new()
		viewport.add_child(hero)
		if not hero.configure("res://assets/art/" + version + "/" + character + "/rig.json"):
			quit(1)
			return
		hero.fit(Vector2(1000, 1300))
		hero.position.x = 600
		for item: Array in samples:
			hero.set_motion(false)
			if item[0] != "neutral":
				hero.set_motion(true)
				hero.loop_player.speed_scale = 0.0
				hero.cue(str(item[0]), 1.0)
				hero.action_player.speed_scale = 0.0
				hero.action_player.seek(hero.action_length(str(item[0])) * float(item[1]), true)
				hero._update_feet()
				hero._update_drawings()
				hero._update_expression()
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s-%s.png" % ["v8" if version == "actor-proportions" else "v11", item[0]]
			if item.size() > 2:
				file = file.trim_suffix(".png") + "-%02d.png" % int(item[2])
			var code := viewport.get_texture().get_image().save_png(output.path_join(file))
			records.append({"version": version, "character": character, "pose": item[0], "fraction": item[1], "file": file, "save_error": code, "state": hero.debug_snapshot(), "landmarks": _landmarks(hero)})
			hero.finish_action()
		hero.free()
	viewport.free()
	var report := FileAccess.open(output.path_join("probe.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"engine": Engine.get_version_info(), "scope": "controlled actual renderer pose inspection; not a gameplay test", "captures": records}, "\t"))
	report.close()
	print("MOTION_POSE_PROBE=", records.size())
	quit(0)


func _landmarks(hero: NativeActorRig) -> Dictionary:
	var result := {}
	for id in ["torso", "loop_chest", "loop_near", "near_forearm", "action_tip", "loop_far", "far_forearm", "held_wrist", "loop_laptop"]:
		var point: Vector2 = hero.skeleton.to_local(hero.bones[id].global_position)
		result[id] = [point.x, point.y]
	return result
