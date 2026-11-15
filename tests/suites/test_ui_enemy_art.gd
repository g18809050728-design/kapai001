extends RefCounted

var _failures: Array[String] = []


func run() -> Array[String]:
	var manifest: Dictionary = load("res://data/four_year/manifests/campus_four_year.json").data
	var enabled: Array = manifest.enabled.task
	_check(enabled.size() == int(EnemyArt.INDEX.data.expected_count), "production roster scope matches manifest")
	var textures := {}
	for id: String in EnemyArt.ids():
		_check(id in enabled, id + " is enabled production content")
		var actor := BattleActorView.new()
		actor.configure(id, "task")
		_check(is_instance_valid(actor.rig), id + " resolves by exact definition ID without a pilot")
		if is_instance_valid(actor.rig):
			_check(str(actor.rig.specification.definition_id) == id, id + " retains its own identity")
			_check(int(actor.rig.specification.version) == EnemyArt.version(id), id + " uses the registered version")
			_check(actor.rig.skeleton is Skeleton2D and actor.rig.meshes.size() >= 1, id + " has actual weighted geometry")
			for pose in ["action", "hit", "guard", "enter", "depart", "phase"]:
				_check(actor.rig.action_length(pose) > 0, id + " has " + pose)
			_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, id + " leaves input to stable target controls")
			actor.set_motion(false)
			_check(not actor.rig.loop_player.is_playing(), id + " respects motion off")
		var texture := UiStyle.texture(id)
		_check(texture != null and texture.resource_path == EnemyArt.texture_path(id), id + " generic art bypasses historical aliases")
		if texture != null:
			_check(not textures.has(texture.resource_path), id + " has a distinct texture resource")
			textures[texture.resource_path] = id
		actor.free()
	for entry in [["R3-AC-TASK-A", "task"], ["unknown_enemy", "task"], ["R3-U01", "unit"], ["test_P01", "player"]]:
		var actor := BattleActorView.new()
		actor.configure(entry[0], entry[1])
		_check(not is_instance_valid(actor.rig), entry[0] + " retains the existing fallback")
		actor.free()
	_check(not BattleActorView.pilot_enabled, "normal roster never enables pilot mode")
	return _failures


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append("Enemy art: " + message)
