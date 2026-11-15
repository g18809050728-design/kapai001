extends SceneTree

## Separate, playable entry. Normal main.tscn never enables pilot assets.
const DEFAULT_OUT := "res://artifacts/verification/actor-rig-pilot-20261114/render-01"
var shell: GameShell
var control: GameSession
var output := DEFAULT_OUT
var capture := false
var verify := false
var polished := false
var refinement := false
var drawings := false
var anatomy := false
var seams := false
var report := {"checks": [], "failures": [], "commands": [], "screens": [], "frames": []}
var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	verify = "--verify" in OS.get_cmdline_user_args()
	seams = "--seams" in OS.get_cmdline_user_args()
	anatomy = "--anatomy" in OS.get_cmdline_user_args() or seams
	drawings = "--drawings" in OS.get_cmdline_user_args() or anatomy
	refinement = "--refinement" in OS.get_cmdline_user_args() or drawings
	polished = "--polished" in OS.get_cmdline_user_args() or refinement
	if polished:
		BattleActorView.pilot_resource_root = "res://assets/art/actor-rig-polish"
		output = "res://artifacts/verification/actor-rig-polish-20261114/render-01"
	if refinement:
		BattleActorView.pilot_resource_root = "res://assets/art/actor-rig-refinement"
		BattleActorView.pilot_stage_background = "res://assets/art/actor-rig-refinement/classroom-stage.png"
		output = "res://artifacts/verification/actor-rig-refinement-20261115/render-01"
	if drawings:
		BattleActorView.pilot_resource_root = "res://assets/art/actor-rig-drawings"
		output = "res://artifacts/verification/actor-rig-drawings-20261115/render-01"
	if anatomy:
		BattleActorView.pilot_resource_root = "res://assets/art/actor-anatomy"
		output = "res://artifacts/verification/actor-anatomy-20261115/render-01"
	if seams:
		BattleActorView.pilot_resource_root = "res://assets/art/actor-seams"
		output = "res://artifacts/verification/actor-seams-20261115/render-01"
	if not OS.get_environment("CAMPUS_ACTOR_PILOT_OUT").is_empty():
		output = OS.get_environment("CAMPUS_ACTOR_PILOT_OUT")
	call_deferred("_start")


func _start() -> void:
	root.title = ("人物与敌怪动作精修" if polished else "人物与敌怪动作实践") + " · P01 / N01 · 独立存档"
	root.size = Vector2i(1280, 800)
	BattleActorView.pilot_enabled = true
	var session := GameSession.new(SaveStore.new("user://actor-rig-pilot-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	session.update_settings({"autosave": false, "audio": {"muted": true}})
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "32"))
	_check(started.accepted, "production P01 starts in a unique isolated SaveStore")
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
		"save_scope": "unique user://actor-rig-pilot-<pid>-<ticks>", "default_entry_unchanged": true}))
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


func _clone_session(source: GameSession, label: String) -> GameSession:
	var result := GameSession.new(SaveStore.new("user://actor-rig-%s-%d" % [label, Time.get_ticks_usec()]))
	result.update_settings({"autosave": false, "audio": {"muted": true}})
	# A legal production checkpoint, copied in memory for presentation A/B only.
	result._catalog = source._catalog
	result._run_service = RunService.new(source._catalog)
	result._battle_engine = BattleEngine.new(source._catalog)
	result._state = source._state.copy_for_write()
	return result


func _page() -> BattleScreen:
	return shell.page as BattleScreen


func _rigs() -> Array[NativeActorRig]:
	var result: Array[NativeActorRig] = []
	if shell.page is BattleScreen:
		for actor in _page()._actors.values():
			if is_instance_valid(actor.rig):
				result.append(actor.rig)
	return result


func _verify_matrix() -> void:
	var original: String = helpers.fingerprint(shell.session)
	BattleActorView.pilot_enabled = false
	var fallback := BattleActorView.new()
	fallback.configure("P01", "player")
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
					moving = maxf(moving, absf((rig.bones["near_forearm"] if rig.specification.definition_id == "P01" else rig.bones["pencil"]).rotation))
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


func _verify_lifecycle() -> void:
	var page := _page()
	var task := str(page.view.tasks[0].task_id)
	var event := {"index": 0, "type": "task_transformed", "source_id": task, "target_ids": [task], "data": {}}
	page.consume_events([event], "pilot-dedup", 990)
	page._animator.advance(.02)
	var counts: Array = _rigs().map(func(r): return r.cue_count)
	page.consume_events([event], "pilot-dedup", 990)
	page._animator.advance(.02)
	_check(counts == _rigs().map(func(r): return r.cue_count), "same run/revision/event never replays a rig cue")
	page._finish_event_presentation()
	var completions: Array = []
	var callback := func(): completions.append(true)
	page.result_presentation_finished.connect(callback)
	page.present_result([event], [], "pilot-terminal", 991)
	page._animator.advance(.02)
	_check(page._result_pending and completions.is_empty() and page._presentation.is_animating(), "terminal waits for finite rig action while idle keeps looping")
	await create_timer(.5).timeout
	_check(completions.size() == 1 and not page._result_pending, "terminal completes once without waiting forever for idle")
	page.result_presentation_finished.disconnect(callback)
	page._stage_effects.cue(task, "depart")
	await _frames(2)
	page._finish_event_presentation()
	_check(not page._presentation.is_animating() and _rigs().all(func(r): return r.active_pose == "idle"), "cancel kills registered action tweens and restores rest")
	shell.refresh()
	await _frames(3)
	var before: String = helpers.fingerprint(shell.session)
	_check(shell.press("battle:map"), "full-map entry remains usable with rigs")
	await _frames(3)
	_check(shell.press("battle:close_panel"), "map overlay closes and returns to hand")
	_check(before == helpers.fingerprint(shell.session), "map inspection with rigs remains read-only")


func _geometry(page: BattleScreen) -> Dictionary:
	var result := {}
	for id in page._actors:
		result["actor:" + str(id)] = page._actors[id].get_global_rect()
	for id in page._buttons:
		if str(id).begins_with("task:") or str(id) == "battle:end_turn":
			result[id] = page._buttons[id].get_global_rect()
	for child in page._stage.get_children():
		if child is Label and (str(child.name).begins_with("Task") or child.name == "PlayerVitalityValue"):
			result[str(child.name)] = child.get_global_rect()
	return result


func _capture_matrix() -> void:
	_page()._feedback_text = ""
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		root.size = dimensions
		shell.hide()
		BattleActorView.pilot_enabled = false
		var baseline := helpers.attach_shell(_clone_session(shell.session, "baseline")) as GameShell
		baseline.show_screen("")
		await _frames(5)
		await _save("baseline-%d" % dimensions.x)
		baseline.free()
		BattleActorView.pilot_enabled = true
		shell.show()
		for text_scale in [100, 125, 150]:
			shell.session.update_settings({"presentation": {"text_scale": text_scale}})
			shell._apply_presentation()
			shell.refresh()
			await _settle()
			await _save("battle-%d-%d" % [dimensions.x, text_scale])
			if text_scale == 100:
				for pose in ["action", "hit", "guard", "phase", "depart"]:
					for rig in _rigs():
						rig.cue(pose, 1.0)
					var delay := float({"action": .69, "hit": .20, "guard": .53, "phase": .83, "depart": 1.25}.get(pose, .28)) if polished else .28
					await create_timer(delay).timeout
					await _save("pose-%s-%d" % [pose, dimensions.x], "controlled_pose_preview")
					for rig in _rigs():
						rig.finish_action()
	root.size = Vector2i(1280, 800)
	shell.session.update_settings({"presentation": {"text_scale": 100}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	await _record("idle", 3.3)
	if polished:
		await _capture_motion_review()
	if anatomy:
		await _capture_anatomy()


func _capture_motion_review() -> void:
	for pose in ["action", "hit", "guard", "depart"]:
		for rig in _rigs():
			rig.cue(pose, 4.0)
		await _record("motion-%s-effective4" % pose, .75)
		for rig in _rigs():
			rig.finish_action()
	for pose in ["action", "hit"]:
		for rig in _rigs():
			rig.cue(pose, 1.0)
		await _record("motion-%s-authored1-slow" % pose, 1.95)
		for rig in _rigs():
			rig.finish_action()


func _verify_motion_polish() -> void:
	var fingerprint: String = helpers.fingerprint(shell.session)
	for rig in _rigs():
		var excursion := 0.0
		var foot_error := 0.0
		var rest: Vector2 = rig.bones.torso.position
		var geometry := _geometry(_page())
		var clocks := []
		rig.cue("action", 4.0)
		for sample in 18:
			await create_timer(.025).timeout
			excursion = maxf(excursion, (rig.bones.torso.position as Vector2).distance_to(rest))
			var snapshot := rig.debug_snapshot()
			clocks.append(snapshot.loop_time)
			for foot: Dictionary in snapshot.feet:
				foot_error = maxf(foot_error, float(foot.error))
		_check(excursion > 15.0, "refined body transfers weight instead of only rotating a static torso")
		_check(foot_error < 1.0, "refined planted ankle error remains below one rig unit through full action")
		_check(geometry == _geometry(_page()), "refined weight transfer leaves HUD and targets stationary")
		_check(clocks[0] != clocks[-1], "refined action retains an independent live secondary loop")
		rig.cue("action", 1.0)
		await create_timer(.65).timeout
		var before := rig.debug_snapshot()
		rig.cue("hit", 4.0)
		var immediate := rig.debug_snapshot()
		_check(before.rotations == immediate.rotations and before.body_position == immediate.body_position, "interrupt starts from the actual sampled pose without a rest snap")
		await create_timer(.06).timeout
		_check(rig.active_pose == "hit", "interrupt actually plays the hit instead of ignoring it")
		rig.finish_action()
		rig.set_motion(false)
		var off := rig.debug_snapshot()
		await _frames(4)
		_check(off.rotations == rig.debug_snapshot().rotations and off.body_position == rig.debug_snapshot().body_position, "refined reduced motion settles IK and body completely")
		rig.set_motion(true)
	_check(fingerprint == helpers.fingerprint(shell.session), "motion polish and interruptions do not mutate domain or RNG")


func _verify_refinement() -> void:
	var page := _page()
	var fingerprint: String = helpers.fingerprint(shell.session)
	var background := page._stage.get_node("BattleRoomBackground") as TextureRect
	_check(background.texture.resource_path == BattleActorView.pilot_stage_background, "refinement uses the reviewed floor environment only in the opt-in stage")
	var hero: NativeActorRig
	for rig in _rigs():
		if rig.specification.definition_id == "P01":
			hero = rig
	if not is_instance_valid(hero):
		_check(false, "refinement has a real P01 for contact and expression checks")
		return
	var hand_id := (hero.parts.held_hand as Sprite2D).get_instance_id()
	var prop_id := (hero.parts.held_laptop as Sprite2D).get_instance_id()
	_check(hand_id != prop_id, "palm and laptop are separate rendered parts")
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
	_check(max_contact_error < .05, "held laptop contact stays with the palm through all six poses")
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
	var fingerprint: String = helpers.fingerprint(shell.session)
	var geometry := _geometry(_page())
	for rig in _rigs():
		var hero: bool = str(rig.specification.definition_id) == "P01"
		var expected_version := (6 if seams else 5) if anatomy and hero else 4
		_check(rig.specification.version == expected_version and rig.specification.drawings.size() == (3 if hero else 2), "selected actor uses separate local drawings on the live skeleton")
		for layer: Dictionary in rig.specification.drawings:
			var material := (rig.parts[str(layer.part)] as CanvasItem).material as ShaderMaterial
			_check(material != null and material.shader.resource_path.ends_with("actor_drawing_mix.gdshader"), "registered drawings are bound to the rendered part material")
		var reach_before := rig.action_anchor()
		rig.cue("action", 1.0)
		for fraction in [.18, .42, .74]:
			rig.action_player.seek(rig.action_length("action") * fraction, true)
			rig._update_feet()
			rig._update_drawings()
			rig._update_expression()
			var state := rig.debug_snapshot()
			for values: Array in state.drawing_weights.values():
				var sum := 0.0
				for value in values:
					sum += float(value)
				_check(absf(sum - 1.0) < .0001 and values.min() >= 0.0, "drawing blend retains normalized nonnegative opacity")
			if fraction < .20:
				_check(state.drawings.get("head" if hero else "body") == ("head_turn" if hero else "body_windup"), "anticipation has its own registered turn drawing")
			elif fraction < .5:
				_check(state.drawings.get("head" if hero else "body") == ("head_strike" if hero else "body_strike"), "contact has its own focused drawing")
				var tip := rig.bones.action_tip as Bone2D
				var limb: Bone2D = rig.bones.near_forearm if hero else rig.bones.pencil
				var direction: Vector2 = tip.global_position - limb.global_position
				_check((direction.x > 0 if hero else direction.x < 0) and absf(direction.y / direction.x) < .30, "contact points the actual pen or pencil horizontally toward the opponent")
				if hero:
					var body_factor := float(rig.specification.get("anatomy", {}).get("upper_scale", 1.0))
					_check(rig.action_anchor().x > reach_before.x + 160.0 * body_factor, "hero strike extends the real limb silhouette beyond its resting reach")
					var prop := rig.parts.held_laptop as Sprite2D
					_check(tip.global_position.y < prop.to_global(Vector2(prop.texture.get_width() * .7, prop.texture.get_height() * .12)).y, "hero strike clears the open laptop instead of looking like typing behind it")
			elif hero:
				_check(state.drawings.near_forearm == "arm_follow", "wrist follow-through uses its own drawing before recovery")
		var before := rig.debug_snapshot()
		rig.cue("hit", 4.0)
		_check(before.drawing_weights == rig.debug_snapshot().drawing_weights, "interruption preserves current drawing weights without a neutral flash")
		rig.action_player.seek(rig.action_length("hit") * .18, true)
		rig._update_drawings()
		rig._update_expression()
		_check(rig.debug_snapshot().drawings.get("head" if hero else "body") == ("head_hit" if hero else "body_hit"), "hit reaction actually changes the facial drawing")
		rig.set_motion(false)
		var stopped := rig.debug_snapshot()
		_check(stopped.drawings.values().all(func(value): return value == "neutral"), "reduced motion restores all local drawings to neutral immediately")
		await _frames(4)
		_check(stopped == rig.debug_snapshot(), "reduced motion has no residual drawing or expression progress")
		rig.set_motion(true)
		for pose in ["action", "hit", "guard", "phase", "depart", "enter"]:
			rig.cue(pose, 8.0)
			await create_timer(.52).timeout
			_check(rig.active_pose == "idle" and rig.debug_snapshot().drawings.values().all(func(value): return value == "neutral"), "finite completion releases every drawing for " + pose)
	_check(geometry == _geometry(_page()), "new turn and strike drawings leave HUD and target rectangles fixed")
	_check(fingerprint == helpers.fingerprint(shell.session), "drawing transitions do not change domain revision events or RNG")


func _verify_anatomy() -> void:
	var hero: NativeActorRig
	for rig in _rigs():
		if str(rig.specification.definition_id) == "P01":
			hero = rig
	if not is_instance_valid(hero):
		_check(false, "anatomy has a real P01")
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
	hero.loop_player.pause()
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
	_check(hero.configure(BattleActorView.pilot_resource_root.path_join("P01/rig.json")), "large full-body anatomy inspection uses the same live resource")
	hero.fit(Vector2(1000, 1300))
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
			var expected_head := "head_hit" if str(item[0]) == "hit" else "head_strike"
			_check(state.drawings.head == expected_head, "large full-body capture retains actual local drawing for " + str(item[0]))
			if str(item[0]) == "action":
				_check(state.drawings.near_forearm == "arm_strike" and state.drawings.torso == "torso_strike", "large strike capture uses actual strike forearm and torso drawings")
		captures.append({"file": file, "pose": item[0], "fraction": item[1], "state": state})
		report.screens.append({"file": file, "kind": "controlled_fullbody_anatomy_inspection", "size": [1200, 1400]})
		hero.finish_action()
	viewport.free()
	report.anatomy_captures = captures
	for rig in _rigs():
		rig.set_motion(false)
	await _frames(3)
	await _save("anatomy-reduced-motion-1280", "real_battle_reduced_motion")
	for rig in _rigs():
		rig.set_motion(true)


func _work_card() -> String:
	if not shell.session.get_view().battle is Dictionary:
		return ""
	for card in shell.session.get_view().battle.hand:
		if str(card.definition_id) in ["R3-C-01", "R3-P01-02"]:
			return str(card.card_id)
	return ""


func _published_commands() -> void:
	for step in 16:
		var view := shell.session.get_view()
		if not view.battle is Dictionary:
			break
		var card := _work_card()
		var draft := {"type": "end_turn", "payload": {}}
		if not card.is_empty():
			draft = {"type": "play_card", "payload": {"card_instance_id": card,
				"target_ids": [str(view.battle.tasks[0].task_id)], "replace_unit_id": null}}
			var preview := shell.session.preview_action(ActionDraft.new(&"play_card", draft.payload))
			if not preview.ok or not preview.data.can_submit:
				draft = {"type": "end_turn", "payload": {}}
		var reference := control.submit(CommandContext.new(str(control.get_view().run_id), control.get_view().revision), GameAction.new(StringName(draft.type), draft.payload))
		_check(reference.accepted, "baseline accepts real command %d" % step)
		var cues_before := _cue_counts()
		shell.submit_action(draft)
		var equal: bool = helpers.fingerprint(control) == helpers.fingerprint(shell.session)
		_check(equal, "baseline/pilot domain, RNG, revision and event log equal after real command %d" % step)
		var events: Array = []
		for i in reference.events.size():
			events.append(BattleEventAnimator.new()._event_dictionary(reference.events[i], i))
		report.commands.append({"step": step, "input": draft, "revision": shell.session.get_view().revision,
			"equal": equal, "expected_hash": helpers.fingerprint(control).sha256_text(),
			"actual_hash": helpers.fingerprint(shell.session).sha256_text(), "published_events": events})
		if capture and (step < 3 or not shell.session.get_view().battle is Dictionary):
			await _record("command-%02d" % step, 1.2)
		else:
			await _settle()
		var cues_after := _cue_counts()
		if shell.page is BattleScreen and shell.session.get_view().battle is Dictionary:
			for event: Dictionary in events:
				if event.type == "completion_applied" or event.type == "pressure_applied":
					var data: Dictionary = event.data
					var work: bool = event.type == "completion_applied"
					var loss := int(data.get("work_before" if work else "vitality_before", 0)) - int(data.get("work_after" if work else "vitality_after", 0))
					if loss > 0:
						var target := str(event.target_ids[0])
						_check(int(cues_after.get(target, 0)) > int(cues_before.get(target, 0)), "real damage cues its actual target rig at step %d" % step)
						var source: String = _page()._stage_effects.source_actor(event)
						_check(int(cues_after.get(source, 0)) > int(cues_before.get(source, 0)), "real action cues its actual source rig at step %d" % step)
		report.commands[-1].rig_cues_before = cues_before
		report.commands[-1].rig_cues_after = cues_after
		if not equal or not reference.accepted:
			break
	_check(not shell.session.get_view().battle is Dictionary, "real play/end-turn commands complete the representative battle")
	_check(not shell._waiting_for_battle, "real result transition releases the old rig page")
	if capture:
		await _save("after-real-battle")


func _render_reentry() -> void:
	_check(shell.session.restart_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "32"), true).accepted, "isolated run can restart after rig battle")
	shell.show_screen("")
	_check(helpers.enter_node(shell, str(shell.session.get_view().run.reachable_node_ids[0])), "battle can reenter after result cleanup")
	await _settle()
	_check(_rigs().size() == 2 and _rigs().all(func(r): return r.loop_player.is_playing()), "reentry has two fresh live native rigs")


func _settle() -> void:
	for frame in 250:
		if not shell.page is BattleScreen or (_page()._animator.pending_count() == 0 and _page()._animator._remaining <= 0.0 and not _page()._presentation.is_animating() and not shell._waiting_for_battle):
			break
		await create_timer(.025).timeout
	await _frames(3)
	if shell._waiting_for_battle and shell.page is BattleScreen:
		var page := _page()
		var tweens: Array = []
		for tween in page._presentation._tweens:
			tweens.append({"valid": tween.is_valid(), "running": tween.is_running() if tween.is_valid() else false,
				"elapsed": tween.get_total_elapsed_time() if tween.is_valid() else 0})
		print("PILOT_BARRIER_DIAGNOSTIC=", JSON.stringify({"pending_events": page._animator.pending_count(),
			"result_pending": page._result_pending, "events_done": page._result_events_done,
			"page_processing": page.is_processing(), "tweens": tweens}))


func _cue_counts() -> Dictionary:
	var result := {}
	if shell.page is BattleScreen:
		for id in _page()._actors:
			var actor: BattleActorView = _page()._actors[id]
			if is_instance_valid(actor.rig):
				result[id] = actor.rig.cue_count
	return result


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _save(name_: String, kind: String = "real_battle_ui") -> void:
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(output.path_join(name_ + ".png"))
	_check(code == OK, "render saved: " + name_)
	report.screens.append({"name": name_, "kind": kind, "viewport": [root.size.x, root.size.y], "save_error": code})


func _record(sequence: String, seconds: float) -> void:
	var started := Time.get_ticks_msec()
	var ordinal := 0
	while Time.get_ticks_msec() - started < seconds * 1000:
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var file := "%s-%03d.jpg" % [sequence, ordinal]
		var crop := Rect2i(45, 160, 1190, 390)
		frame.get_region(crop).save_jpg(output.path_join(file), .9)
		var rigs: Array = []
		for rig in _rigs():
			rigs.append(rig.debug_snapshot())
		report.frames.append({"sequence": sequence, "ordinal": ordinal, "file": file,
			"elapsed_ms": Time.get_ticks_msec() - started, "crop": [45,160,1190,390], "rigs": rigs})
		ordinal += 1
		await create_timer(.03).timeout
	await _settle()


func _check(ok: bool, message: String) -> void:
	report.checks.append({"ok": ok, "message": message})
	if not ok:
		report.failures.append(message)
		push_error("ACTOR_RIG_PILOT: " + message)


func _write_report() -> void:
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
