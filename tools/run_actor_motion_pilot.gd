extends "res://tools/run_actor_party_pilot.gd"

## Version 11: P04 motion and shoulder skinning correction; historical resources stay reproducible.
const MOTION_ROOT := "res://assets/art/actor-motion"

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	verify = "--verify" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			character = argument.trim_prefix("--character=")
	if not character in ["P01", "P02", "P03", "P04"]:
		push_error("Unknown protagonist: " + character)
		quit(1)
		return
	polished = true
	refinement = true
	drawings = true
	anatomy = true
	BattleActorView.pilot_resource_root = MOTION_ROOT
	BattleActorView.pilot_stage_background = "res://assets/art/actor-rig-refinement/classroom-stage.png"
	output = "res://artifacts/verification/actor-motion-20261115/" + character.to_lower() + "-render-01"
	if not OS.get_environment("CAMPUS_ACTOR_PILOT_OUT").is_empty():
		output = OS.get_environment("CAMPUS_ACTOR_PILOT_OUT")
	call_deferred("_start")


func _verify_drawings() -> void:
	if character == "P01":
		await super._verify_drawings()
		return
	var fingerprint: String = helpers.fingerprint(shell.session)
	var geometry := _geometry(_page())
	var hero: NativeActorRig
	for rig in _rigs():
		if str(rig.specification.definition_id) == character:
			hero = rig
	_check(is_instance_valid(hero), "selected protagonist has a native rendered rig")
	if not is_instance_valid(hero):
		return
	_check(hero.specification.version == (11 if character == "P04" else 10 if character == "P03" else 8) and hero.bones.size() == 27 and hero.meshes.size() == 6, "selected protagonist retains registered V5 family geometry with the corrected posture")
	_check(hero.specification.drawings.size() == 3, "head neck and forearm each have local drawing channels")
	for layer: Dictionary in hero.specification.drawings:
		var material := (hero.parts[str(layer.part)] as CanvasItem).material as ShaderMaterial
		_check(material != null and material.shader.resource_path.ends_with("actor_drawing_mix.gdshader"), "drawing textures are bound to the live rendered material")
	hero.set_motion(false)
	hero.set_motion(true)
	hero.loop_player.speed_scale = 0.0
	var reach_before := hero.action_anchor()
	hero.cue("action", 1.0)
	hero.action_player.speed_scale = 0.0
	hero.action_player.seek(hero.action_length("action") * .42, true)
	hero._update_feet()
	hero._update_drawings()
	hero._update_expression()
	var state := hero.debug_snapshot()
	_check(state.drawings.head == "head_focus" and state.drawings.near_forearm == "arm_strike", "contact renders focused face and extended forearm together")
	_check(hero.action_anchor().x > reach_before.x + 60.0, "authored gesture moves the real pen hand toward the opposing task")
	for values: Array in state.drawing_weights.values():
		var sum := 0.0
		for value in values:
			sum += float(value)
		_check(absf(sum - 1.0) < .0001 and values.min() >= 0.0, "drawing blend retains normalized nonnegative opacity")
	hero.cue("hit", 4.0)
	_check(state.drawing_weights == hero.debug_snapshot().drawing_weights, "interruption retains the sampled drawing without a neutral flash")
	hero.action_player.speed_scale = 0.0
	hero.action_player.seek(hero.action_length("hit") * .18, true)
	hero._update_drawings()
	hero._update_expression()
	_check(hero.debug_snapshot().drawings.head == "head_hit", "hit reaction uses its actual facial drawing")
	hero.set_motion(false)
	var stopped := hero.debug_snapshot()
	_check(stopped.drawings.values().all(func(value): return value == "neutral"), "reduced motion restores every local drawing to neutral")
	await _frames(4)
	_check(stopped == hero.debug_snapshot(), "reduced motion keeps all drawing and expression channels still")
	hero.loop_player.speed_scale = 1.0
	hero.set_motion(true)
	for pose in ["action", "hit", "guard", "phase", "depart", "enter"]:
		hero.cue(pose, 8.0)
		await create_timer(.52).timeout
		_check(hero.active_pose == "idle" and hero.debug_snapshot().drawings.values().all(func(value): return value == "neutral"), "finite completion releases all drawing channels for " + pose)
	_check(geometry == _geometry(_page()) and fingerprint == helpers.fingerprint(shell.session), "local drawings preserve target geometry domain revision events and RNG")



func _write_report() -> void:
	report.character = character
	report.resource_root = MOTION_ROOT
	report.production_seed = "32"
	report.engine = Engine.get_version_info()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.scope = "Isolated representative pilot. Controlled poses are labeled separately from actual published commands. Capture readback is not a realtime performance benchmark."
	report.polished = polished
	report.refinement = refinement
	report.drawings = drawings
	report.anatomy = anatomy
	report.seams = seams
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()



func _verify_anatomy() -> void:
	await super._verify_anatomy()
	if character != "P04":
		return
	var hero: NativeActorRig
	for rig in _rigs():
		if str(rig.specification.definition_id) == character:
			hero = rig
	if not is_instance_valid(hero):
		return
	var geometry := _geometry(_page())
	var fingerprint: String = helpers.fingerprint(shell.session)
	var samples := []
	var max_shoulder := 0.0
	var max_elbow := 0.0
	var max_arm_speed := 0.0
	var max_board := 0.0
	var max_knee_action := 0.0
	var max_drop := 0.0
	var min_support := INF
	var max_contact := 0.0
	hero.set_motion(false)
	var rest_position: Vector2 = hero.bones.torso.position
	hero.set_motion(true)
	hero.loop_player.speed_scale = 0.0
	hero.loop_player.seek(0, true)
	for pose in ["action", "hit", "guard", "enter", "depart", "phase"]:
		hero.cue(pose, 1.0)
		hero.action_player.speed_scale = 0.0
		var previous := Vector2.ZERO
		for i in range(101):
			var fraction := float(i) / 100.0
			hero.action_player.seek(hero.action_length(pose) * fraction, true)
			hero._update_feet()
			hero._update_drawings()
			var state := hero.debug_snapshot()
			var arm := Vector2(hero.bones.near_upper.rotation, hero.bones.near_forearm.rotation)
			max_shoulder = maxf(max_shoulder, absf(arm.x))
			max_elbow = maxf(max_elbow, absf(arm.y))
			if i > 0:
				max_arm_speed = maxf(max_arm_speed, (arm - previous).length() / (hero.action_length(pose) / 100.0))
			previous = arm
			max_board = maxf(max_board, absf(hero.bones.loop_laptop.global_rotation - hero.skeleton.global_rotation))
			max_drop = maxf(max_drop, hero.bones.torso.position.y - rest_position.y)
			max_contact = maxf(max_contact, state.held_contact_error)
			if pose == "action":
				for foot: Dictionary in state.feet:
					max_knee_action = maxf(max_knee_action, absf(float(foot.knee_flexion)))
			var hips: Vector2 = hero.skeleton.to_local(hero.bones.torso.global_position)
			var chest: Vector2 = hero.skeleton.to_local(hero.bones.loop_chest.global_position)
			var head: Vector2 = hero.skeleton.to_local(hero.bones.head.global_position)
			var proxy_x: float = .5 * hips.x + .35 * chest.x + .15 * head.x
			var left: float = float(hero.specification.feet[0].target[0]) - 20.0
			var right: float = float(hero.specification.feet[1].target[0]) + 20.0
			min_support = minf(min_support, minf(proxy_x - left, right - proxy_x))
			samples.append({"pose": pose, "fraction": fraction, "arm": [arm.x, arm.y],
				"proxy_x": proxy_x, "body_position": state.body_position, "feet": state.feet,
				"board_rotation": hero.bones.loop_laptop.global_rotation - hero.skeleton.global_rotation})
		hero.finish_action()
	var sleeve := hero.parts.near_upper as Polygon2D
	var cap_weights := sleeve.get_bone_weights(0)
	_check(cap_weights[0] > .99 and sleeve.get_bone_path(0).get_concatenated_names().ends_with("loop_chest"), "sleeve cap has real chest weights so rotating the humerus does not lift the shoulder tip")
	_check(max_shoulder < deg_to_rad(20) and max_elbow < deg_to_rad(62), "six motions keep shoulder and elbow excursions within the authored small gesture envelope")
	_check(max_arm_speed < 5.0, "continuous joint samples avoid an abrupt shoulder elbow whip at authored speed")
	_check(max_drop < 5.5 and max_knee_action < deg_to_rad(20), "forward gesture keeps a supported upright pelvis instead of a synchronized deep knee bend")
	_check(min_support > 10.0, "torso head pelvis projection proxy stays within the planted shoe support interval")
	_check(max_board < deg_to_rad(6) and max_contact < .05, "held board remains stable and follows the supporting hand throughout all six motions")
	_check(geometry == _geometry(_page()) and fingerprint == helpers.fingerprint(shell.session), "motion chain correction preserves hit geometry and published game state")
	hero.action_player.speed_scale = 1.0
	hero.loop_player.speed_scale = 1.0
	hero.set_motion(true)
	report.motion_chain = {"samples": samples, "max_shoulder_radians": max_shoulder,
		"max_elbow_radians": max_elbow, "max_arm_radians_per_second": max_arm_speed,
		"max_board_radians": max_board, "max_action_knee_radians": max_knee_action,
		"max_pelvis_drop": max_drop, "min_support_proxy_margin": min_support,
		"scope": "2D authored joint and support proxy constraints; visual judgment is separate"}
