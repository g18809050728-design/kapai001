class_name NativeActorRig
extends Node2D

## Opt-in feasibility rig. All coordinates/animations are presentation data.
## Loop bones are separate from action bones so hits never restart the loop.
var skeleton: Skeleton2D
var action_player: AnimationPlayer
var loop_player: AnimationPlayer
var bones: Dictionary = {}
var meshes: Array[Polygon2D] = []
var specification: Dictionary = {}
var active_pose := "idle"
var motion_enabled := true
var cue_count := 0
var _paths: Dictionary = {}
var _completion: Tween
var _epoch := 0
var _action_lengths := {"action": 0.92, "hit": 0.68, "guard": 0.86, "enter": 0.8, "depart": 0.8, "phase": 1.0}


func configure(file: String) -> bool:
	if not FileAccess.file_exists(file):
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not decoded is Dictionary or not decoded.has("bones") or not decoded.has("parts"):
		return false
	specification = decoded
	# Keep rear parts above the opaque battlefield; negative part z values are
	# relative to this group and must not disappear behind the room background.
	z_index = 10
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for item: Dictionary in specification.bones:
		var bone := Bone2D.new()
		var id := str(item.id)
		bone.name = id
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(float(item.get("length", 28)))
		var parent_id := str(item.get("parent", ""))
		var parent: Node2D = skeleton if parent_id.is_empty() else bones[parent_id]
		parent.add_child(bone)
		bone.position = _vector(item.position)
		bone.rest = bone.transform
		bones[id] = bone
		_paths[id] = "Skeleton/" + id if parent_id.is_empty() else str(_paths[parent_id]) + "/" + id
	for item: Dictionary in specification.parts:
		if not ResourceLoader.exists(str(item.file)):
			push_error("Missing rig part: " + str(item.file))
			return false
		if item.get("mesh", false):
			_add_mesh(item)
		else:
			var sprite := Sprite2D.new()
			sprite.name = str(item.id)
			sprite.texture = load(str(item.file)) as Texture2D
			sprite.centered = false
			sprite.position = _vector(item.offset)
			sprite.z_index = int(item.z)
			(bones[str(item.bone)] as Bone2D).add_child(sprite)
	loop_player = AnimationPlayer.new()
	loop_player.name = "LoopPlayer"
	add_child(loop_player)
	action_player = AnimationPlayer.new()
	action_player.name = "ActionPlayer"
	add_child(action_player)
	_build_animations()
	set_motion(motion_enabled)
	return true


func _add_mesh(item: Dictionary) -> void:
	var mesh := Polygon2D.new()
	mesh.name = str(item.id)
	mesh.texture = load(str(item.file)) as Texture2D
	mesh.z_index = int(item.z)
	mesh.skeleton = NodePath("../Skeleton")
	var bounds := Rect2(_vector(item.position), _vector(item.size))
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	var weights_top := PackedFloat32Array()
	var weights_base := PackedFloat32Array()
	var cells := 5
	for y in cells + 1:
		for x in cells + 1:
			var fraction := Vector2(float(x) / cells, float(y) / cells)
			vertices.append(bounds.position + bounds.size * fraction)
			uv.append(mesh.texture.get_size() * fraction)
			var weight := 1.0 - smoothstep(0.2, 0.95, fraction.y)
			weights_top.append(weight)
			weights_base.append(1.0 - weight)
	var triangles: Array[PackedInt32Array] = []
	for y in cells:
		for x in cells:
			var a := y * (cells + 1) + x
			triangles.append(PackedInt32Array([a, a + 1, a + cells + 2]))
			triangles.append(PackedInt32Array([a, a + cells + 2, a + cells + 1]))
	mesh.polygon = vertices
	mesh.uv = uv
	mesh.polygons = triangles
	mesh.add_bone(NodePath(str(_paths[str(item.bone)]).trim_prefix("Skeleton/")), weights_top)
	mesh.add_bone(NodePath(str(_paths[str(item.base_bone)]).trim_prefix("Skeleton/")), weights_base)
	add_child(mesh)
	meshes.append(mesh)


func _build_animations() -> void:
	var loop_library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 3.2
	idle.loop_mode = Animation.LOOP_LINEAR
	var amplitudes: Dictionary = specification.get("idle", {})
	for id in amplitudes:
		_rotation_track(idle, str(id), [0.0, 0.8, 1.6, 2.4, 3.2], [0.0, float(amplitudes[id]), 0.0, -float(amplitudes[id]), 0.0])
	loop_library.add_animation("idle", idle)
	loop_player.add_animation_library("", loop_library)
	var library := AnimationLibrary.new()
	for pose in _action_lengths:
		var animation := Animation.new()
		animation.length = float(_action_lengths[pose])
		var times: Array = [0.0, animation.length * 0.18, animation.length * 0.4, animation.length * 0.65, animation.length]
		var poses: Dictionary = specification.get("poses", {}).get(pose, {})
		for id in poses:
			var peak := float(poses[id])
			_rotation_track(animation, str(id), times, [0.0, -peak * 0.22, peak, peak * 0.48, 0.0])
		library.add_animation(str(pose), animation)
	action_player.add_animation_library("", library)


func _rotation_track(animation: Animation, id: String, times: Array, values: Array) -> void:
	if not _paths.has(id):
		return
	var index := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index, NodePath(str(_paths[id]) + ":rotation"))
	animation.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
	for i in times.size():
		animation.track_insert_key(index, float(times[i]), float(values[i]))


func cue(pose: String, speed: float) -> Tween:
	# A card's work event may follow card_played while the same cast is still
	# playing. Preserve that cast instead of snapping back to its first frame.
	if pose == "action" and active_pose == pose and _completion != null and _completion.is_running():
		return _completion
	finish_action()
	var epoch := _epoch
	cue_count += 1
	active_pose = pose if _action_lengths.has(pose) else "action"
	var duration := float(_action_lengths[active_pose]) / maxf(0.05, speed)
	if motion_enabled:
		action_player.speed_scale = maxf(0.05, speed)
		action_player.play(active_pose)
	_completion = create_tween()
	_completion.tween_interval(duration if motion_enabled else 0.001)
	_completion.tween_callback(func():
		if epoch == _epoch:
			_completion = null
			finish_action()
	)
	return _completion


func finish_action() -> void:
	_epoch += 1
	if is_instance_valid(action_player):
		action_player.stop()
	if _completion != null and _completion.is_valid():
		_completion.kill()
	for id in bones:
		if not str(id).begins_with("loop_"):
			(bones[id] as Bone2D).apply_rest()
	active_pose = "idle"


func set_motion(enabled: bool) -> void:
	motion_enabled = enabled
	if not is_instance_valid(loop_player):
		return
	if enabled:
		if not loop_player.is_playing():
			loop_player.play("idle")
	else:
		finish_action()
		loop_player.stop()
		for id in bones:
			(bones[id] as Bone2D).apply_rest()


func fit(bounds: Vector2) -> void:
	if bounds.x <= 0.0 or bounds.y <= 16.0:
		return
	var canvas := _vector(specification.get("canvas", [1024, 1536]))
	var ground := _vector(specification.get("ground", [512, 1450]))
	var factor := minf(bounds.x / canvas.x, (bounds.y - 16.0) / ground.y)
	scale = Vector2.ONE * factor
	position = Vector2(bounds.x * 0.5, bounds.y - 16.0)


func action_anchor() -> Vector2:
	var id := str(specification.get("action_bone", "torso"))
	var point: Bone2D = bones.get(id)
	return Vector2.ZERO if not is_instance_valid(point) else skeleton.to_local(point.global_position)


func debug_snapshot() -> Dictionary:
	var rotations := {}
	for id in bones:
		rotations[id] = (bones[id] as Bone2D).rotation
	var loop_time := loop_player.current_animation_position if not loop_player.current_animation.is_empty() else 0.0
	return {"pose": active_pose, "cue_count": cue_count, "bone_count": bones.size(), "mesh_count": meshes.size(), "loop_time": loop_time, "rotations": rotations, "motion": motion_enabled, "scale": [scale.x, scale.y], "position": [position.x, position.y]}


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
