extends "res://tools/run_actor_party_pilot.gd"

## Version 9 P03 posture correction; production and historical pilots stay reproducible.
const POSTURE_ROOT := "res://assets/art/actor-posture"

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
	BattleActorView.pilot_resource_root = POSTURE_ROOT
	BattleActorView.pilot_stage_background = "res://assets/art/actor-rig-refinement/classroom-stage.png"
	output = "res://artifacts/verification/actor-posture-20261115/" + character.to_lower() + "-render-01"
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
	_check(hero.specification.version == (9 if character == "P03" else 8) and hero.bones.size() == 27 and hero.meshes.size() == 6, "selected protagonist retains registered V5 family geometry with the corrected posture")
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



func _verify_anatomy() -> void:
	await super._verify_anatomy()
	if character == "P01":
		return
	for hero in _rigs():
		if str(hero.specification.definition_id) != character:
			continue
		var correction: Dictionary = hero.specification.proportions
		_check(hero.specification.version == (9 if character == "P03" else 8) and is_equal_approx(float(correction.vertical_leg_scale), .78), "the previously selected 22 percent leg shortening is preserved")
		_check(bool(correction.shoes_rigid), "shoe artwork retains rigid dimensions after proportion retargeting")
		_check(bool(correction.head_neck_repaint) == (character == "P03"), "the corrected continuous head/neck source is scoped to Shen Jianzhang")
		report.proportions = correction
		if character == "P03":
			await _verify_upright_head(hero)


func _write_report() -> void:
	report.character = character
	report.resource_root = POSTURE_ROOT
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


func _verify_upright_head(hero: NativeActorRig) -> void:
	hero.set_motion(false)
	var old_file := FileAccess.open("res://assets/art/actor-proportions/P03/rig.json", FileAccess.READ)
	var old: Dictionary = JSON.parse_string(old_file.get_as_text())
	old_file.close()
	var previous_head := Vector2.ZERO
	for bone: Dictionary in old.bones:
		if bone.id == "head":
			previous_head = NativeActorRig._vector(bone.position)
	var current_head: Vector2 = hero.bones.head.position
	_check(current_head.x < previous_head.x - 8.0 and current_head.y < previous_head.y - 4.0, "actual neutral head joint retracts and rises relative to the shoulder")
	_check(hero.specification.posture.base_version == 8 and hero.specification.proportions.vertical_leg_scale == old.proportions.vertical_leg_scale, "posture correction preserves the selected lower-body proportions")
	var old_parts := {}
	for part: Dictionary in old.parts:
		old_parts[str(part.id)] = part
	var unchanged := true
	for part: Dictionary in hero.specification.parts:
		if part.id not in ["head", "neck_overlap"]:
			unchanged = unchanged and part == old_parts[str(part.id)]
	_check(unchanged, "torso sleeves props pelvis legs and shoes keep their exact V8 registration")
	_check(hero.parts.neck_overlap.get_parent() == hero.bones.loop_chest, "neck root remains attached to the chest while the head moves")
	var neutral_offset: Vector2 = hero.bones.head.position
	var samples := []
	for pose in ["action", "hit", "guard", "phase", "depart", "enter"]:
		hero.set_motion(true)
		hero.loop_player.speed_scale = 0.0
		hero.cue(pose, 1.0)
		hero.action_player.speed_scale = 0.0
		hero.action_player.seek(hero.action_length(pose) * .42, true)
		hero._update_feet()
		hero._update_drawings()
		samples.append({"pose": pose, "head_rotation": hero.bones.head.rotation, "head_position": [hero.bones.head.position.x, hero.bones.head.position.y]})
		hero.finish_action()
		hero.set_motion(false)
		_check(hero.bones.head.position.distance_to(neutral_offset) < .001 and absf(hero.bones.head.rotation) < .0001, "completion returns to the corrected upright neutral for " + pose)
	hero.action_player.speed_scale = 1.0
	hero.loop_player.speed_scale = 1.0
	hero.set_motion(true)
	report.posture = {"registration": hero.specification.posture, "neutral_head_position": [neutral_offset.x, neutral_offset.y], "pose_samples": samples}
