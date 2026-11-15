extends "res://tools/run_actor_rig_pilot.gd"

## Explicit three-protagonist entry; production main and legacy pilots stay intact.
var character := "P02"
const PARTY_ROOT := "res://assets/art/actor-party"


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
	BattleActorView.pilot_resource_root = PARTY_ROOT
	BattleActorView.pilot_stage_background = "res://assets/art/actor-rig-refinement/classroom-stage.png"
	output = "res://artifacts/verification/actor-party-20261115/" + character.to_lower() + "-render-01"
	if not OS.get_environment("CAMPUS_ACTOR_PILOT_OUT").is_empty():
		output = OS.get_environment("CAMPUS_ACTOR_PILOT_OUT")
	call_deferred("_start")


func _start() -> void:
	root.title = "三位主角动作试玩 · " + character + " · 独立存档"
	root.size = Vector2i(1280, 800)
	BattleActorView.pilot_enabled = true
	var session := GameSession.new(SaveStore.new("user://actor-party-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	session.update_settings({"autosave": false, "audio": {"muted": true}})
	var started := session.start_run(StartRunRequest.new(character, &"normal", "campus_four_year", "32"))
	_check(started.accepted, "selected production protagonist starts in a unique isolated SaveStore")
	if not started.accepted:
		quit(1)
		return
	shell = helpers.attach_shell(session)
	shell.show_screen("")
	_check(helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), "first battle enters through normal map commands")
	await _settle()
	if not shell.page is BattleScreen:
		push_error("Pilot did not reach a battle")
		quit(1)
		return
	print("ACTOR_RIG_PILOT_READY=", JSON.stringify({"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "tasks": shell.page.view.tasks,
		"save_scope": "unique user://actor-party-<pid>-<ticks>", "default_entry_unchanged": true}))
	if not capture and not verify:
		return
	if FileAccess.file_exists(output.path_join("report.json")):
		push_error("Evidence already exists; set CAMPUS_ACTOR_PILOT_OUT to a new directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	control = _clone_session(session, "control")
	if verify:
		await _verify_matrix()
		await _verify_lifecycle()
		if polished:
			await _verify_motion_polish()
		if refinement:
			await _verify_refinement()
		if drawings:
			await _verify_drawings()
		if anatomy:
			await _verify_anatomy()
	if capture:
		await _capture_matrix()
	await _published_commands()
	if verify:
		await _render_reentry()
	_write_report()
	shell.free()
	control.free()
	BattleActorView.pilot_enabled = false
	BattleActorView.pilot_stage_background = ""
	await process_frame
	print("ACTOR_RIG_PILOT_RESULT=", JSON.stringify({"checks": report.checks.size(), "failures": report.failures,
		"commands": report.commands.size(), "screens": report.screens.size(), "frames": report.frames.size(), "output": output}))
	quit(0 if report.failures.is_empty() else 1)


func _verify_matrix() -> void:
	var original: String = helpers.fingerprint(shell.session)
	BattleActorView.pilot_enabled = false
	var fallback := BattleActorView.new()
	fallback.configure(character, "player")
	_check(fallback.rig == null, "default actor has no pilot rig")
	fallback.free()
	BattleActorView.pilot_enabled = true
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for text_scale in [100, 125, 150]:
			root.size = dimensions
			shell.session.update_settings({"presentation": {"text_scale": text_scale, "animation_speed": 1, "reduced_motion": false}})
			shell._apply_presentation()
			shell.refresh()
			await _settle()
			var label := "%d/%d" % [dimensions.x, text_scale]
			_check(_rigs().size() == 2, "both production definitions use a native rig at " + label)
			var page := _page()
			var hud := _geometry(page)
			var actors := {}
			for id in page._actors:
				var actor: BattleActorView = page._actors[id]
				actors[id] = actor.get_instance_id()
				_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "rig never intercepts targeting at " + label)
			for rig in _rigs():
				_check(rig.scale.x > .08 and rig.scale.x < .5, "rig is visibly fitted at positive stage scale at " + label)
				_check(rig.z_index > 4, "rear body parts remain above the opaque room background at " + label)
				_check(rig.skeleton is Skeleton2D and rig.bones.size() >= 10 and rig.meshes.size() >= 1, "real bones and weighted mesh at " + label)
				for mesh in rig.meshes:
					_check(mesh.get_bone_count() >= 2 and mesh.polygon.size() >= 36, "mesh has actual weights and deformation vertices at " + label)
				var clock := rig.loop_player.current_animation_position
				var action := rig.cue("action", page.effect_speed())
				# Observe a short actual interval. A single fixed sample can land
				# on the limb's zero crossing under headless scheduling jitter.
				var moving := 0.0
				for motion_sample in 4:
					await create_timer(.04 if polished else .021).timeout
					moving = maxf(moving, absf((rig.bones["near_forearm"] if rig.bones.has("near_forearm") else rig.bones["pencil"]).rotation))
				_check(moving > .025 and rig.rotation == 0, "body joint moves independently of the root at " + label)
				_check(rig.loop_player.current_animation_position != clock, "idle clock advances during action at " + label)
				var action_count := rig.cue_count
				_check(rig.cue("action", page.effect_speed()) == action and rig.cue_count == action_count, "same ongoing cast coalesces at " + label)
				rig.cue("hit", page.effect_speed())
				await create_timer(.06).timeout
				_check(rig.loop_player.current_animation_position != clock, "hit does not rewind the idle at " + label)
				rig.finish_action()
			_check(hud == _geometry(page), "HUD and target rectangles stay fixed through body actions at " + label)
			shell.refresh()
			await _frames(3)
			for id in actors:
				_check(_page()._actors[id].get_instance_id() == actors[id], "UI rebuild retains actor identity at " + label)
			page = _page()
			var card_id := _work_card()
			if not card_id.is_empty():
				_check(shell.press("card:" + card_id), "work card can be selected at " + label)
				_check(helpers.fingerprint(shell.session) == original, "selection alone never mutates the domain at " + label)
				shell.press("battle:cancel")
			page = _page()
			page.animation_enabled = false
			for rig in _rigs():
				var pose: Dictionary = rig.debug_snapshot().rotations
				await create_timer(.045).timeout
				_check(not rig.loop_player.is_playing() and rig.active_pose == "idle" and pose == rig.debug_snapshot().rotations, "motion off settles and stays still at " + label)
			shell.session.update_settings({"presentation": {"reduced_motion": true}})
			shell._apply_presentation()
			_check(not page.animation_enabled, "shell reduced-motion setting reaches the rig at " + label)
			shell.session.update_settings({"presentation": {"reduced_motion": false}})
			shell._apply_presentation()
			_check(helpers.fingerprint(shell.session) == original, "all visual modes preserve revision/domain/RNG at " + label)
	root.size = Vector2i(1280, 800)
	shell.session.update_settings({"presentation": {"text_scale": 100, "animation_speed": 1, "reduced_motion": false}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	for multiplier in [1.0, 2.0, 3.0]:
		var page := _page()
		page.speed_scale = multiplier
		_check(is_equal_approx(page.effect_speed(), 4.0 * multiplier), "base x4 and user x%s compose" % multiplier)
		var rig := _rigs()[0]
		var before := Time.get_ticks_msec()
		await rig.cue("action", page.effect_speed()).finished
		var elapsed := (Time.get_ticks_msec() - before) / 1000.0
		var expected: float = rig.action_length("action") / (4.0 * multiplier)
		_check(absf(elapsed - expected) < .10, "action completion follows effective speed x%s" % multiplier)
		if not report.has("timings"):
			report.timings = []
		report.timings.append({"user_multiplier": multiplier, "base": 4, "expected": expected, "observed": elapsed})
	_page().speed_scale = 1


func _verify_refinement() -> void:
	var page := _page()
	var fingerprint: String = helpers.fingerprint(shell.session)
	var background := page._stage.get_node("BattleRoomBackground") as TextureRect
	_check(background.texture.resource_path == BattleActorView.pilot_stage_background, "refinement uses the reviewed floor environment only in the opt-in stage")
	var hero: NativeActorRig
	for rig in _rigs():
		if rig.specification.definition_id == character:
			hero = rig
	if not is_instance_valid(hero):
		_check(false, "refinement has a selected protagonist for contact and expression checks")
		return
	var hand_id := (hero.parts.held_hand as Sprite2D).get_instance_id()
	var prop_id := (hero.parts.held_laptop as Sprite2D).get_instance_id()
	_check(hand_id != prop_id, "palm and prop are separate rendered parts")
	var geometry := _geometry(page)
	var max_contact_error := 0.0
	var max_foot_error := 0.0
	var wrist_min := INF
	var wrist_max := -INF
	for pose in ["action", "hit", "guard", "phase", "depart", "enter"]:
		hero.cue(pose, 4.0)
		for sample in 20:
			await create_timer(.025).timeout
			var state := hero.debug_snapshot()
			max_contact_error = maxf(max_contact_error, state.held_contact_error)
			for foot: Dictionary in state.feet:
				max_foot_error = maxf(max_foot_error, float(foot.error))
			wrist_min = minf(wrist_min, float(state.rotations.held_wrist))
			wrist_max = maxf(wrist_max, float(state.rotations.held_wrist))
		hero.finish_action()
	_check(max_contact_error < .05, "held prop contact stays with the palm through all six poses")
	_check(max_foot_error < 1.0, "planted feet remain reachable through action hit guard phase depart and enter")
	_check(wrist_max - wrist_min > .05, "held wrist visibly articulates independently through recoil and recovery")
	_check(geometry == _geometry(page), "held prop and shoulder refinements preserve all HUD and target geometry")
	var seen_blink := false
	var seen_neutral := false
	for sample in 100:
		await create_timer(.033).timeout
		seen_blink = seen_blink or hero.debug_snapshot().face == "blink"
		seen_neutral = seen_neutral or hero.debug_snapshot().face == "neutral"
	_check(seen_blink and seen_neutral, "continuous idle actually renders and releases the blink")
	hero.set_motion(false)
	_check(hero.debug_snapshot().face == "neutral", "reduced motion restores a neutral eye instead of freezing a blink")
	var stopped := hero.debug_snapshot()
	await _frames(5)
	_check(stopped == hero.debug_snapshot(), "reduced motion keeps all new wrist and expression channels completely stable")
	hero.set_motion(true)
	_check(fingerprint == helpers.fingerprint(shell.session), "all refinement checks preserve domain revision and RNG")


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
	_check(hero.specification.version == 7 and hero.bones.size() == 27 and hero.meshes.size() == 6, "party protagonist uses independently registered V5 family geometry")
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
	var hero: NativeActorRig
	for rig in _rigs():
		if str(rig.specification.definition_id) == character:
			hero = rig
	if not is_instance_valid(hero):
		_check(false, "anatomy has a selected protagonist")
		return
	var fingerprint: String = helpers.fingerprint(shell.session)
	var geometry := _geometry(_page())
	hero.set_motion(false)
	var neutral := hero.debug_snapshot()
	var calibration: Array = hero.specification.anatomy.calibration
	var bind_error := 0.0
	for index in neutral.feet.size():
		for key: String in ["hip", "knee"]:
			bind_error = maxf(bind_error, NativeActorRig._vector(neutral.feet[index][key]).distance_to(NativeActorRig._vector(calibration[index][key])))
	_check(bind_error < .05, "neutral IK preserves actual painted hip and knee registration instead of rebending a slanted strip")
	_check(hero.parts.pelvis is Polygon2D and (hero.parts.pelvis as Polygon2D).get_bone_count() == 3 and hero.parts.rear_shoe is Sprite2D and hero.parts.front_shoe is Sprite2D, "continuous pelvis follows both hips with three real weights while both shoes stay rigid")
	var rear_length: float = float(calibration[0].lengths[0]) + float(calibration[0].lengths[1])
	var front_length: float = float(calibration[1].lengths[0]) + float(calibration[1].lengths[1])
	_check(absf(rear_length - front_length) / maxf(rear_length, front_length) < .04, "measured full leg lengths differ by less than four percent")
	var max_length_error := 0.0
	var max_foot_error := 0.0
	var max_shoe_rotation := 0.0
	var max_flexion := 0.0
	var min_signed_flexion := INF
	var min_reach_margin := INF
	var samples: Array = []
	hero.set_motion(true)
	hero.loop_player.speed_scale = 0.0
	hero.loop_player.seek(0, true)
	for pose: String in ["action", "hit", "guard", "phase", "depart", "enter"]:
		hero.cue(pose, 1.0)
		for fraction: float in [0.0, .08, .18, .30, .42, .55, .70, .86, .96, 1.0]:
			hero.action_player.seek(hero.action_length(pose) * fraction, true)
			hero._update_feet()
			var state := hero.debug_snapshot()
			for index in state.feet.size():
				var foot: Dictionary = state.feet[index]
				for segment in 2:
					max_length_error = maxf(max_length_error, absf(float(foot.lengths[segment]) - float(calibration[index].lengths[segment])))
				max_foot_error = maxf(max_foot_error, float(foot.error))
				max_shoe_rotation = maxf(max_shoe_rotation, absf(float(foot.shoe_rotation)))
				max_flexion = maxf(max_flexion, absf(float(foot.knee_flexion)))
				min_signed_flexion = minf(min_signed_flexion, float(foot.knee_flexion) * -float(hero.specification.feet[index].bend))
				min_reach_margin = minf(min_reach_margin, float(foot.reach_margin))
			samples.append({"pose": pose, "fraction": fraction, "feet": state.feet})
		hero.finish_action()
	hero.loop_player.speed_scale = 1.0
	hero.set_motion(true)
	_check(max_length_error < .05, "six poses preserve measured thigh and calf lengths without stretching")
	_check(max_foot_error < .05 and min_reach_margin > .01, "both feet remain reachable without full-extension clamping in every sampled pose")
	_check(max_shoe_rotation < .001, "rigid soles stay level while knees and chest move")
	_check(min_signed_flexion >= -.001 and max_flexion < deg_to_rad(80), "knees retain the authored bend direction without inversion or an extreme folded leg")
	_check(geometry == _geometry(_page()) and fingerprint == helpers.fingerprint(shell.session), "anatomy correction preserves HUD targets domain and RNG")
	report.anatomy_geometry = {"neutral_bind_error": bind_error, "leg_lengths": [rear_length, front_length],
		"max_segment_error": max_length_error, "max_foot_error": max_foot_error, "max_shoe_rotation": max_shoe_rotation,
		"max_knee_radians": max_flexion, "min_signed_knee_radians": min_signed_flexion, "min_reach_margin": min_reach_margin,
		"samples": samples, "scope": "geometry only; anatomy silhouette still requires rendered review"}


func _capture_anatomy() -> void:
	# Large, real engine renders for full-body inspection. They are controlled
	# art previews, kept separate from the live battle and published commands.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 1400)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1200, 1400)
	background.color = Color("e6dfd1")
	viewport.add_child(background)
	var hero := NativeActorRig.new()
	viewport.add_child(hero)
	_check(hero.configure(BattleActorView.pilot_resource_root.path_join(character + "/rig.json")), "large full-body anatomy inspection uses the same live resource")
	hero.fit(Vector2(1000, 1300))
	hero.position.x = 600
	var captures: Array = []
	for item: Array in [["neutral", 0.0], ["action", .42], ["hit", .16], ["guard", .40]]:
		if str(item[0]) == "neutral":
			hero.set_motion(false)
		else:
			hero.set_motion(true)
			hero.loop_player.seek(0, true)
			hero.loop_player.speed_scale = 0.0
			hero.cue(str(item[0]), 1.0)
			hero.action_player.seek(hero.action_length(str(item[0])) * float(item[1]), true)
			# pause() clears current_animation, which the drawing mixer correctly
			# interprets as neutral. Freeze playback without clearing the pose.
			hero.action_player.speed_scale = 0.0
			hero._update_feet()
			hero._update_drawings()
			hero._update_expression()
		await _frames(2)
		await RenderingServer.frame_post_draw
		var file := "anatomy-full-%s.png" % str(item[0])
		viewport.get_texture().get_image().save_png(output.path_join(file))
		var state := hero.debug_snapshot()
		if str(item[0]) != "neutral":
			var expected_head := "head_hit" if str(item[0]) == "hit" else ("head_strike" if character == "P01" else "head_focus")
			_check(state.drawings.head == expected_head, "large full-body capture retains actual local drawing for " + str(item[0]))
			if str(item[0]) == "action":
				_check(state.drawings.near_forearm == "arm_strike", "large strike capture uses actual registered strike forearm")
		captures.append({"file": file, "pose": item[0], "fraction": item[1], "state": state})
		report.screens.append({"file": file, "kind": "controlled_fullbody_anatomy_inspection", "size": [1200, 1400]})
		hero.finish_action()
	for sequence: Array in [["idle", 1.0, 2.4], ["action", 4.0, .8], ["action", 1.0, 2.0], ["hit", 1.0, 1.4], ["guard", 4.0, .7]]:
		await _record_fullbody(viewport, hero, str(sequence[0]), float(sequence[1]), float(sequence[2]))
	viewport.free()
	report.anatomy_captures = captures
	for rig in _rigs():
		rig.set_motion(false)
	await _frames(3)
	await _save("anatomy-reduced-motion-1280", "real_battle_reduced_motion")
	for rig in _rigs():
		rig.set_motion(true)


func _record_fullbody(viewport: SubViewport, hero: NativeActorRig, pose: String, speed: float, seconds: float) -> void:
	hero.set_motion(false)
	hero.loop_player.speed_scale = 1.0
	hero.set_motion(true)
	if pose != "idle":
		hero.cue(pose, speed)
	if not report.has("fullbody_frames"):
		report.fullbody_frames = []
	var sequence := "fullbody-%s-x%d" % [pose, int(speed)]
	var started := Time.get_ticks_msec()
	var ordinal := 0
	while Time.get_ticks_msec() - started < seconds * 1000:
		await RenderingServer.frame_post_draw
		var file := "%s-%03d.jpg" % [sequence, ordinal]
		var code := viewport.get_texture().get_image().save_jpg(output.path_join(file), .92)
		if code != OK:
			_check(false, "full-body continuous frame saves")
		report.fullbody_frames.append({"sequence": sequence, "file": file, "ordinal": ordinal,
			"elapsed_ms": Time.get_ticks_msec() - started, "kind": "controlled_fullbody_motion", "state": hero.debug_snapshot()})
		ordinal += 1
		await create_timer(.03).timeout
	hero.finish_action()


func _render_reentry() -> void:
	_check(shell.session.restart_run(StartRunRequest.new(character, &"normal", "campus_four_year", "32"), true).accepted, "isolated run can restart after rig battle")
	shell.show_screen("")
	_check(helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])), "battle can reenter after result cleanup")
	await _settle()
	_check(_rigs().size() == 2 and _rigs().all(func(r): return r.loop_player.is_playing()), "reentry has two fresh live native rigs")


func _write_report() -> void:
	report.character = character
	report.resource_root = PARTY_ROOT
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
