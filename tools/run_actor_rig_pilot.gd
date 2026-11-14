extends SceneTree

## Separate, playable entry. Normal main.tscn never enables pilot assets.
const DEFAULT_OUT := "res://artifacts/verification/actor-rig-pilot-20261114/render-01"
var shell: GameShell
var control: GameSession
var output := DEFAULT_OUT
var capture := false
var verify := false
var report := {"checks": [], "failures": [], "commands": [], "screens": [], "frames": []}
var helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	verify = "--verify" in OS.get_cmdline_user_args()
	if not OS.get_environment("CAMPUS_ACTOR_PILOT_OUT").is_empty():
		output = OS.get_environment("CAMPUS_ACTOR_PILOT_OUT")
	call_deferred("_start")


func _start() -> void:
	root.title = "人物与敌怪动作实践 · P01 / N01 · 独立存档"
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
	if capture:
		await _capture_matrix()
	await _published_commands()
	if verify:
		await _render_reentry()
	_write_report()
	shell.free()
	control.free()
	BattleActorView.pilot_enabled = false
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
				_check(rig.skeleton is Skeleton2D and rig.bones.size() >= 10 and rig.meshes.size() == 1, "real bones and weighted mesh at " + label)
				for mesh in rig.meshes:
					_check(mesh.get_bone_count() == 2 and mesh.polygon.size() == 36, "mesh has two actual weight sets and 36 vertices at " + label)
				var clock := rig.loop_player.current_animation_position
				var action := rig.cue("action", page.effect_speed())
				await create_timer(.085).timeout
				var moving := absf((rig.bones["near_forearm"] if rig.specification.definition_id == "P01" else rig.bones["pencil"]).rotation)
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
		var expected: float = .92 / (4.0 * multiplier)
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
					await create_timer(.28).timeout
					await _save("pose-%s-%d" % [pose, dimensions.x], "controlled_pose_preview")
					for rig in _rigs():
						rig.finish_action()
	root.size = Vector2i(1280, 800)
	shell.session.update_settings({"presentation": {"text_scale": 100}})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	await _record("idle", 3.3)


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
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
