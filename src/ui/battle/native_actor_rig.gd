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
var refined := false
var contact_count := 0
var parts: Dictionary = {}
var _neutral_face: Texture2D
var _blink_face: Texture2D
var _face_state := "neutral"
var _drawing_layers: Array[Dictionary] = []
var _drawing_origin: Dictionary = {}
var _drawing_weights: Dictionary = {}
var _drawing_states: Dictionary = {}


func configure(file: String) -> bool:
	if not FileAccess.file_exists(file):
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not decoded is Dictionary or not decoded.has("bones") or not decoded.has("parts"):
		return false
	specification = decoded
	refined = int(specification.get("version", 1)) >= 2
	process_priority = 20
	if refined:
		for pose in specification.get("animations", {}):
			_action_lengths[pose] = float(specification.animations[pose].length)
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
			if item.has("display_size"):
				sprite.scale = _vector(item.display_size) / sprite.texture.get_size()
			sprite.z_index = int(item.z)
			(bones[str(item.bone)] as Bone2D).add_child(sprite)
			parts[str(item.id)] = sprite
	if specification.has("expression"):
		var expression: Dictionary = specification.expression
		_neutral_face = (parts[str(expression.part)] as Sprite2D).texture
		_blink_face = load(str(expression.blink)) as Texture2D
	_configure_drawings()
	loop_player = AnimationPlayer.new()
	loop_player.name = "LoopPlayer"
	add_child(loop_player)
	action_player = AnimationPlayer.new()
	action_player.name = "ActionPlayer"
	add_child(action_player)
	action_player.animation_finished.connect(_on_action_finished)
	_build_animations()
	set_motion(motion_enabled)
	if refined:
		_update_feet()
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
	var weights_foot := PackedFloat32Array()
	var weights_split := PackedFloat32Array()
	var has_foot: bool = item.has("foot_bone")
	var has_split: bool = item.has("split_bone")
	var cells := int(item.get("cells", 5))
	var axis: Array = item.get("weight_axis", [])
	var weight_range: Array = item.get("weight_range", [0.2, 0.95])
	var split_range: Array = item.get("split_range", [0.4, 0.6])
	for y in cells + 1:
		for x in cells + 1:
			var fraction := Vector2(float(x) / cells, float(y) / cells)
			vertices.append(bounds.position + bounds.size * fraction)
			uv.append(mesh.texture.get_size() * fraction)
			var foot_weight := smoothstep(0.78, 0.93, fraction.y) if has_foot else 0.0
			var along := fraction.y
			if axis.size() == 2:
				var start := _vector(axis[0])
				var direction := _vector(axis[1]) - start
				along = (vertices[-1] - start).dot(direction) / maxf(1.0, direction.length_squared())
			var weight := 1.0 - smoothstep(0.24, 0.68, fraction.y) if has_foot else 1.0 - smoothstep(float(weight_range[0]), float(weight_range[1]), along)
			weights_top.append(weight * (1.0 - foot_weight))
			var side := smoothstep(float(split_range[0]), float(split_range[1]), fraction.x) if has_split else 0.0
			weights_base.append((1.0 - weight) * (1.0 - foot_weight) * (1.0 - side))
			weights_split.append((1.0 - weight) * side)
			weights_foot.append(foot_weight)
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
	if has_foot:
		mesh.add_bone(NodePath(str(_paths[str(item.foot_bone)]).trim_prefix("Skeleton/")), weights_foot)
	if has_split:
		mesh.add_bone(NodePath(str(_paths[str(item.split_bone)]).trim_prefix("Skeleton/")), weights_split)
	add_child(mesh)
	meshes.append(mesh)
	parts[str(item.id)] = mesh


func _configure_drawings() -> void:
	for definition: Dictionary in specification.get("drawings", []):
		var node := parts[str(definition.part)] as CanvasItem
		var material := ShaderMaterial.new()
		material.shader = preload("res://src/ui/battle/actor_drawing_mix.gdshader")
		var variants: Array = definition.variants
		for index in 3:
			var texture := load(str(variants[mini(index, variants.size() - 1)].file)) as Texture2D
			material.set_shader_parameter("drawing_" + ["a", "b", "c"][index], texture)
		node.material = material
		_drawing_layers.append({"definition": definition, "material": material})
	_reset_drawings()


func _reset_drawings() -> void:
	for layer: Dictionary in _drawing_layers:
		var id := str(layer.definition.part)
		_drawing_weights[id] = Vector4(1, 0, 0, 0)
		_drawing_states[id] = "neutral"
		(layer.material as ShaderMaterial).set_shader_parameter("drawing_weights", Vector4(1, 0, 0, 0))
	_drawing_origin.clear()


func _sample_drawing(keys: Array, fraction: float) -> Vector4:
	for index in range(1, keys.size()):
		var right: Array = keys[index]
		if fraction <= float(right[0]):
			var left: Array = keys[index - 1]
			var blend := smoothstep(float(left[0]), float(right[0]), fraction)
			return _drawing_vector(left[1]).lerp(_drawing_vector(right[1]), blend)
	return _drawing_vector(keys[-1][1])


func _update_drawings() -> void:
	var time := action_player.current_animation_position if not action_player.current_animation.is_empty() else 0.0
	var fraction := time / action_length(active_pose)
	var playing := motion_enabled and active_pose != "idle" and not action_player.current_animation.is_empty()
	for layer: Dictionary in _drawing_layers:
		var definition: Dictionary = layer.definition
		var id := str(definition.part)
		var weights := Vector4(1, 0, 0, 0)
		if playing:
			var keys: Array = definition.get("poses", {}).get(active_pose, [])
			if not keys.is_empty():
				weights = _sample_drawing(keys, fraction)
			var blend := smoothstep(0.0, float(specification.get("drawing_blend_seconds", .12)), time)
			var origin: Vector4 = _drawing_origin.get(id, Vector4(1, 0, 0, 0))
			weights = origin.lerp(weights, blend)
		_drawing_weights[id] = weights
		(layer.material as ShaderMaterial).set_shader_parameter("drawing_weights", weights)
		var dominant := 0
		for index in range(1, 4):
			if weights[index] > weights[dominant]:
				dominant = index
		_drawing_states[id] = "neutral" if dominant == 0 else str(definition.variants[dominant - 1].id)


static func _drawing_vector(value: Array) -> Vector4:
	return Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


func _build_animations() -> void:
	if refined:
		_build_refined_animations()
		return
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


func _build_refined_animations() -> void:
	var loop_library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = float(specification.get("idle_length", 6.4))
	idle.loop_mode = Animation.LOOP_LINEAR
	for curve: Dictionary in specification.get("idle_tracks", []):
		_curve_track(idle, curve)
	loop_library.add_animation("idle", idle)
	loop_player.add_animation_library("", loop_library)
	var library := AnimationLibrary.new()
	for pose in specification.animations:
		var definition: Dictionary = specification.animations[pose]
		var animation := Animation.new()
		animation.length = float(definition.length)
		for curve: Dictionary in definition.tracks:
			_curve_track(animation, curve)
		library.add_animation(str(pose), animation)
	action_player.add_animation_library("", library)


func _curve_track(animation: Animation, curve: Dictionary) -> void:
	var id := str(curve.bone)
	if not _paths.has(id):
		return
	var index := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index, NodePath(str(_paths[id]) + ":" + str(curve.property)))
	animation.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
	for key: Array in curve.keys:
		var value: Variant = _vector(key[1]) if key[1] is Array else float(key[1])
		animation.track_insert_key(index, float(key[0]) * animation.length, value)


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
	if refined:
		# Keep the player's last sampled pose alive for native crossfading.
		# Resetting to rest here used to create a visible snap on every hit.
		_epoch += 1
		if _completion != null and _completion.is_valid():
			_completion.kill()
		_completion = null
	else:
		finish_action()
	var epoch := _epoch
	cue_count += 1
	active_pose = pose if _action_lengths.has(pose) else "action"
	_drawing_origin = _drawing_weights.duplicate()
	var duration := float(_action_lengths[active_pose]) / maxf(0.05, speed)
	if motion_enabled:
		action_player.speed_scale = maxf(0.05, speed)
		var blend := float(specification.get("blend_seconds", 0.0)) / maxf(0.05, speed) if refined and action_player.is_playing() else 0.0
		action_player.play(active_pose, blend)
		if refined:
			action_player.advance(0.0)
	_completion = create_tween()
	# The animation's own finished signal is authoritative for v2. A timer
	# created during a long frame can otherwise finish before AnimationPlayer
	# has sampled its recovery. The extra interval is a finite fallback only.
	_completion.tween_interval((duration + .25 if refined else duration) if motion_enabled else 0.001)
	_completion.tween_callback(func():
		if epoch == _epoch:
			_completion = null
			finish_action()
	)
	return _completion


func _on_action_finished(animation: StringName) -> void:
	if refined and str(animation) == active_pose and _completion != null and _completion.is_valid():
		_completion.custom_step(60.0)


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
	_reset_drawings()
	_update_expression()
	if refined and is_inside_tree():
		_update_feet()


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
		if refined and is_inside_tree():
			_update_feet()
	_update_expression()


func fit(bounds: Vector2) -> void:
	if bounds.x <= 0.0 or bounds.y <= 16.0:
		return
	var canvas := _vector(specification.get("canvas", [1024, 1536]))
	var ground := _vector(specification.get("ground", [512, 1450]))
	var offset := float(specification.get("ground_offset", 16.0))
	var factor := minf(bounds.x / canvas.x, (bounds.y - offset) / ground.y)
	scale = Vector2.ONE * factor
	position = Vector2(bounds.x * 0.5, bounds.y - offset)
	queue_redraw()


func _process(_delta: float) -> void:
	if refined and motion_enabled:
		_update_feet()
		_update_drawings()
		_update_expression()


func _update_expression() -> void:
	if not specification.has("expression") or not is_instance_valid(loop_player):
		return
	var closed := false
	var drawing_face := str(_drawing_states.get(str(specification.expression.part), "neutral"))
	if motion_enabled and drawing_face == "neutral" and not loop_player.current_animation.is_empty():
		var clock := loop_player.current_animation_position
		for interval: Array in specification.expression.intervals:
			closed = closed or (clock >= float(interval[0]) and clock < float(interval[1]))
	var sprite: Sprite2D = parts[str(specification.expression.part)]
	var face_texture := _blink_face if closed else _neutral_face
	if sprite.texture != face_texture:
		sprite.texture = face_texture
	_face_state = drawing_face if drawing_face != "neutral" else ("blink" if closed else "neutral")


func _update_feet() -> void:
	# A standing pelvis transfers weight with the torso translation while the
	# chest can bend above it. Opt-in only; legacy rigs keep their original hips.
	for id: String in specification.get("upright_bones", []):
		var upright: Bone2D = bones[id]
		upright.rotation = skeleton.global_rotation - (upright.get_parent() as Node2D).global_rotation
	for foot: Dictionary in specification.get("feet", []):
		var upper: Bone2D = bones[foot.upper]
		var lower: Bone2D = bones[foot.lower]
		var ankle: Bone2D = bones[foot.ankle]
		var parent := upper.get_parent() as Node2D
		var target := parent.to_local(skeleton.to_global(_vector(foot.target)))
		var vector := target - upper.position
		var a := float(foot.lengths[0])
		var b := float(foot.lengths[1])
		var distance := clampf(vector.length(), absf(a - b) + 0.01, a + b - 0.01)
		var bend := float(foot.get("bend", 1.0))
		# New drawings retain their measured hip/knee/ankle coordinates in the
		# bind pose. Subtract those actual axes, rather than bending an already
		# tilted painted leg a second time around an assumed vertical chain.
		var upper_axis := lower.rest.origin.angle() if foot.get("bind_axes", false) else PI * 0.5
		var lower_axis := ankle.rest.origin.angle() if foot.get("bind_axes", false) else PI * 0.5
		upper.rotation = vector.angle() - upper_axis + bend * acos(clampf((a * a + distance * distance - b * b) / (2.0 * a * distance), -1.0, 1.0))
		lower.rotation = -bend * (PI - acos(clampf((a * a + b * b - distance * distance) / (2.0 * a * b), -1.0, 1.0))) + upper_axis - lower_axis
		# Counter-rotate shoes. The body's weight moves; the shoe does not pivot
		# around the hip or skate across the floor with the torso.
		ankle.rotation = skeleton.global_rotation - lower.global_rotation


func seconds_to_contact() -> float:
	if not refined or not motion_enabled or active_pose != "action" or action_player.current_animation.is_empty():
		return 0.0
	var authored := float(_action_lengths.action) * float(specification.get("contact_fraction", 0.4))
	return maxf(0.0, authored - action_player.current_animation_position) / maxf(0.05, action_player.speed_scale)


func action_length(pose: String) -> float:
	return float(_action_lengths.get(pose, _action_lengths.action))


func _draw() -> void:
	if not refined:
		return
	for contact: Array in specification.get("cast_shadows", []):
		draw_set_transform(Vector2(float(contact[0]), float(contact[1])), 0.08, Vector2(1.0, float(contact[3]) / float(contact[2])))
		for ring in range(12, 0, -1):
			draw_circle(Vector2.ZERO, float(contact[2]) * float(ring) / 12.0, Color(0.06, 0.065, 0.07, 0.012), true, -1, true)
	for contact: Array in specification.get("contact_shadows", []):
		draw_set_transform(Vector2(float(contact[0]), float(contact[1])), 0.0, Vector2(1.0, float(contact[3]) / float(contact[2])))
		for ring in range(10, 0, -1):
			draw_circle(Vector2.ZERO, float(contact[2]) * float(ring) / 10.0, Color(0.07, 0.06, 0.05, 0.022), true, -1, true)
	draw_set_transform(Vector2.ZERO)


func action_anchor() -> Vector2:
	var id := str(specification.get("action_bone", "torso"))
	var point: Bone2D = bones.get(id)
	return Vector2.ZERO if not is_instance_valid(point) else skeleton.to_local(point.global_position)


func debug_snapshot() -> Dictionary:
	var rotations := {}
	for id in bones:
		rotations[id] = (bones[id] as Bone2D).rotation
	var loop_time := loop_player.current_animation_position if not loop_player.current_animation.is_empty() else 0.0
	var feet := []
	for foot: Dictionary in specification.get("feet", []):
		var ankle: Bone2D = bones[foot.ankle]
		var point := skeleton.to_local(ankle.global_position)
		var item := {"ankle": foot.ankle, "point": [point.x, point.y], "target": foot.target, "error": point.distance_to(_vector(foot.target))}
		if foot.get("bind_axes", false):
			var hip := skeleton.to_local((bones[foot.upper] as Bone2D).global_position)
			var knee := skeleton.to_local((bones[foot.lower] as Bone2D).global_position)
			item.merge({"hip": [hip.x, hip.y], "knee": [knee.x, knee.y],
				"lengths": [hip.distance_to(knee), knee.distance_to(point)],
				"knee_flexion": (knee - hip).angle_to(point - knee),
				"shoe_rotation": ankle.global_rotation - skeleton.global_rotation,
				"reach_margin": float(foot.lengths[0]) + float(foot.lengths[1]) - hip.distance_to(_vector(foot.target))})
		feet.append(item)
	var body: Bone2D = bones.get("torso")
	var action_time := action_player.current_animation_position if not action_player.current_animation.is_empty() else 0.0
	var held_contact_error := 0.0
	if specification.has("held_contact"):
		var contact: Dictionary = specification.held_contact
		var hand := bones[str(contact.hand)] as Bone2D
		var prop := bones[str(contact.prop)] as Bone2D
		held_contact_error = skeleton.to_local(hand.to_global(_vector(contact.point))).distance_to(skeleton.to_local(prop.global_position))
	var drawing_values := {}
	for id in _drawing_weights:
		var weights: Vector4 = _drawing_weights[id]
		drawing_values[id] = [weights.x, weights.y, weights.z, weights.w]
	return {"pose": active_pose, "cue_count": cue_count, "bone_count": bones.size(), "mesh_count": meshes.size(), "loop_time": loop_time, "rotations": rotations, "motion": motion_enabled, "scale": [scale.x, scale.y], "position": [position.x, position.y], "refined": refined, "feet": feet, "body_position": [body.position.x, body.position.y], "body_scale": [body.scale.x, body.scale.y], "action_time": action_time, "action_speed": action_player.speed_scale, "face": _face_state, "held_contact_error": held_contact_error, "drawings": _drawing_states.duplicate(), "drawing_weights": drawing_values}


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
