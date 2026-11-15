extends "res://tools/run_character_integration.gd"

func _start() -> void:
	await _detail_geometry()
	await super._start()


func _detail_geometry() -> void:
	var rig := NativeActorRig.new()
	root.add_child(rig)
	_check(rig.configure("res://assets/art/actor-lin-polish/P01/rig.json"), "P01 V12 configures high-resolution details")
	rig.fit(Vector2(900, 1200))
	rig.set_motion(false)
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/actor-anatomy/P01/rig.json"))
	for part: Dictionary in rig.specification.parts:
		if part.has("display_size"):
			var sprite: Sprite2D = rig.parts[str(part.id)]
			_check((sprite.texture.get_size() * sprite.scale).distance_to(Vector2(part.display_size[0], part.display_size[1])) < .001,
				"high-resolution pixels retain authored physical dimensions: " + str(part.id))
	var head: Sprite2D = rig.parts.head
	_check(head.texture.get_height() >= 650 and head.scale.x < .4, "Lin head retains large original detail pixels without enlarging anatomy")
	for pose: String in old.animations:
		var current: Dictionary = rig.specification.animations[pose]
		_check(current.length == old.animations[pose].length and current.get("contact_fraction") == old.animations[pose].get("contact_fraction"), "V5 action length and contact retained: " + pose)
		for index in current.tracks.size():
			var track: Dictionary = current.tracks[index]
			if track.property == "rotation":
				_check(track == old.animations[pose].tracks[index], "V5 angular motion retained: %s/%s" % [pose, track.bone])
	for index in 2:
		var old_lengths: Array = old.feet[index].lengths
		var new_lengths: Array = rig.specification.feet[index].lengths
		_check(absf((new_lengths[0] + new_lengths[1]) / (old_lengths[0] + old_lengths[1]) - 1.0) < .06, "accepted V5 leg length retained within six percent: " + str(index))
	var maximum_foot_error := 0.0
	var maximum_contact_error := 0.0
	var finite := true
	var samples := []
	for pose: String in ["action", "hit", "guard", "enter", "depart", "phase"]:
		rig.set_motion(false)
		rig.set_motion(true)
		rig.loop_player.speed_scale = 0.0
		rig.cue(pose, 1.0)
		rig.action_player.speed_scale = 0.0
		for index in 101:
			rig.action_player.seek(rig.action_length(pose) * index / 100.0, true)
			rig._update_feet()
			rig._update_drawings()
			rig._update_expression()
			var snapshot := rig.debug_snapshot()
			maximum_contact_error = maxf(maximum_contact_error, float(snapshot.held_contact_error))
			for foot: Dictionary in snapshot.feet:
				maximum_foot_error = maxf(maximum_foot_error, float(foot.error))
				finite = finite and is_finite(float(foot.error)) and is_finite(float(foot.knee_flexion))
			samples.append({"pose": pose, "fraction": index / 100.0, "state": snapshot})
		rig.finish_action()
	_check(finite and maximum_foot_error < .06, "all 606 motion samples retain planted feet")
	_check(maximum_contact_error < .05, "all 606 samples retain laptop to hand attachment")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output.path_join("lin-geometry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"maximum_foot_error": maximum_foot_error, "maximum_contact_error": maximum_contact_error, "samples": samples}, "\t"))
	file.close()
	rig.free()
