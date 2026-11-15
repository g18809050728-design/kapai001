extends "res://tools/run_actor_rig_pilot.gd"

## The normal GameShell route; no pilot flag/root/background is set by this runner.
var character := ""


func _initialize() -> void:
	output = OS.get_environment("CAMPUS_CHARACTER_OUT")
	if output.is_empty():
		output = "res://artifacts/verification/actor-integration-20261115/game-01"
	capture = true
	call_deferred("_start")


func _start() -> void:
	if FileAccess.file_exists(output.path_join("report.json")):
		push_error("Choose fresh CAMPUS_CHARACTER_OUT evidence")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.title = "四角色正式接入验证 · 隔离存档"
	root.size = Vector2i(1280, 800)
	_check(not BattleActorView.pilot_enabled and BattleActorView.pilot_stage_background.is_empty(), "normal default mode, no pilot or background override")
	for id: String in CharacterArt.RIGS:
		character = id
		await _normal_run()
		await _test_room()
	await _legacy_save()
	await _fallbacks()
	_write_report()
	print("CHARACTER_INTEGRATION_RESULT=", JSON.stringify({"checks": report.checks.size(), "failures": report.failures,
		"commands": report.commands.size(), "screens": report.screens.size(), "frames": report.frames.size(), "output": output}))
	quit(0 if report.failures.is_empty() else 1)


func _normal_run() -> void:
	var store := SaveStore.new("user://character-integration-%s-%s-%s" % [character, OS.get_process_id(), Time.get_ticks_usec()])
	var session := GameSession.new(store)
	_configure_session(session)
	shell = helpers.attach_shell(session)
	shell._setup_defaults.default_seed = "32"
	_check(shell.press("menu:new"), character + " normal menu opens setup")
	_check(shell.press("setup:character:" + character), character + " normal tab selects character")
	_check(shell.press("setup:advanced"), character + " opens normal seed configuration")
	var seed_input: LineEdit = helpers._line_edit(shell.page)
	_check(seed_input != null, character + " normal seed field is present")
	if seed_input != null:
		seed_input.text = "32"
		seed_input.text_changed.emit("32")
	_check(shell.press("inspect:close"), character + " closes normal seed configuration")
	await _frames(4)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 640)]:
		for text_scale in [100, 125, 150]:
			root.size = dimensions
			_presentation_settings(session, {"text_scale": text_scale})
			shell._apply_presentation()
			shell.refresh()
			await _frames(5)
			var actor: BattleActorView = shell.page._room_figure
			_check(is_instance_valid(actor.rig) and int(actor.rig.specification.version) == int(CharacterArt.VERSIONS[character]), character + " normal setup version at %s/%s" % [dimensions.x, text_scale])
			_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE and actor.get_global_rect().intersection(shell.get_global_rect()).size == actor.size, character + " setup art fits and does not intercept controls")
			await _save(character + "-setup-%s-%s" % [dimensions.x, text_scale], "normal_setup")
	_check(shell.press("setup:start"), character + " normal start creates run")
	_check(shell._active_seed == "32", character + " uses the recorded production seed 32")
	_check(helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), character + " normal map enters battle")
	await _settle()
	if not shell.page is BattleScreen:
		_check(false, character + " reaches normal battle")
		shell.free()
		return
	await _battle_matrix()
	var stable := helpers.fingerprint(session) as String
	_check(session.save_current().ok, character + " public save succeeds")
	var current_file := store._base_path.path_join("current_run.json")
	var saved_bytes := FileAccess.get_file_as_bytes(current_file)
	var restored := GameSession.new(store)
	_check(restored.continue_run().ok and helpers.fingerprint(restored) == stable, character + " saved battle resumes with exact state revision RNG and event log")
	_check(FileAccess.get_file_as_bytes(current_file) == saved_bytes, character + " continuing does not migrate or rewrite save bytes")
	shell.free()
	shell = helpers.attach_shell(restored)
	_check(shell.press("menu:continue"), character + " normal continue button reopens saved battle")
	await _settle()
	_check(is_instance_valid(_hero()) and int(_hero().rig.specification.version) == int(CharacterArt.VERSIONS[character]), character + " continued battle restores selected version")
	await _save(character + "-continued", "normal_continue")
	control = _clone_session(restored, "character-reference-" + character)
	await _published_commands()
	shell.free()
	control.free()
	await _frames(2)


func _clone_session(source: GameSession, label: String) -> GameSession:
	var result := GameSession.new(SaveStore.new("user://character-%s-%s" % [label, Time.get_ticks_usec()]))
	_configure_session(result)
	result._catalog = source._catalog
	result._run_service = RunService.new(source._catalog)
	result._battle_engine = BattleEngine.new(source._catalog)
	result._state = source._state.copy_for_write()
	return result


func _test_room() -> void:
	var session := GameSession.new(SaveStore.new("user://character-room-saves-%s" % Time.get_ticks_usec()))
	_configure_session(session)
	session.test_service().store = TestStore.new("user://character-room-%s" % Time.get_ticks_usec())
	shell = helpers.attach_shell(session)
	_check(shell.press("menu:test"), character + " normal menu opens test room")
	_check(shell.press("test:character:" + character), character + " test room selects character")
	_check(shell.press("test:start"), character + " test room starts normal battle view")
	await _settle()
	_check(is_instance_valid(_hero()) and int(_hero().rig.specification.version) == int(CharacterArt.VERSIONS[character]), character + " test room uses selected production version")
	await _save(character + "-test-room", "normal_test_room")
	shell.submit_action({"type": "test.close", "payload": {}})
	shell.free()
	await _frames(2)


func _hero() -> BattleActorView:
	if is_instance_valid(shell) and shell.page is BattleScreen:
		for actor: BattleActorView in _page()._actors.values():
			if actor.actor_kind == "player":
				return actor
	return null


func _battle_matrix() -> void:
	var original: String = helpers.fingerprint(shell.session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 640)]:
		for text_scale in [100, 125, 150]:
			root.size = dimensions
			_presentation_settings(shell.session, {"text_scale": text_scale, "reduced_motion": false, "animation_speed": 1})
			shell._apply_presentation()
			shell.refresh()
			await _settle()
			var page := _page()
			var hero := _hero()
			_check(is_instance_valid(hero.rig) and int(hero.rig.specification.version) == int(CharacterArt.VERSIONS[character]), character + " production battle version at %s/%s" % [dimensions.x, text_scale])
			_check(_rigs().size() == 1 and hero.rig.bones.size() == 27 and hero.rig.meshes.size() == 6, character + " only protagonist uses selected native skeleton")
			var geometry := _geometry(page)
			var identity := hero.get_instance_id()
			var clock := hero.rig.loop_player.current_animation_position
			hero.cue("action", page.effect_speed())
			await create_timer(.09).timeout
			_check(geometry == _geometry(page), character + " action preserves HUD and target rectangles")
			_check(clock != hero.rig.loop_player.current_animation_position, character + " idle continues under action")
			hero.reset_pose()
			shell.refresh()
			await _frames(3)
			_check(_hero().get_instance_id() == identity, character + " local refresh retains live rig")
			_check(helpers.fingerprint(shell.session) == original, character + " presentation preserves state RNG and revision")
			await _save(character + "-battle-%s-%s" % [dimensions.x, text_scale], "normal_battle")
	root.size = Vector2i(1280, 800)
	_presentation_settings(shell.session, {"text_scale": 100, "reduced_motion": true})
	shell._apply_presentation()
	shell.refresh()
	await _frames(4)
	var frozen: Dictionary = _hero().rig.debug_snapshot().rotations
	await create_timer(.1).timeout
	_check(not _hero().rig.loop_player.is_playing() and frozen == _hero().rig.debug_snapshot().rotations, character + " reduced motion is fully still")
	_presentation_settings(shell.session, {"reduced_motion": false, "animation_speed": 0})
	shell._apply_presentation()
	shell.refresh()
	await _frames(3)
	_check(not _hero().rig.loop_player.is_playing(), character + " animation off also stops selected rig")
	_presentation_settings(shell.session, {"animation_speed": 1})
	shell._apply_presentation()
	shell.refresh()
	await _settle()
	for multiplier in [1.0, 2.0, 3.0]:
		_page().speed_scale = multiplier
		var started := Time.get_ticks_msec()
		var expected: float = _hero().rig.action_length("action") / (4.0 * multiplier)
		await _hero().cue("action", _page().effect_speed()).finished
		_check(absf((Time.get_ticks_msec() - started) / 1000.0 - expected) < .12, character + " action respects base x4 / preference x%s" % multiplier)
	_page().speed_scale = 1
	var actor_id := str(_page().view.player.entity_id)
	var event := {"index": 0, "type": "card_played", "source_id": actor_id, "target_ids": [], "data": {}}
	_page().consume_events([event], "character-dedup", 990)
	_page()._animator.advance(.02)
	var count := _hero().rig.cue_count
	_page().consume_events([event], "character-dedup", 990)
	_page()._animator.advance(.02)
	_check(_hero().rig.cue_count == count, character + " repeated event is presented once")
	_page()._finish_event_presentation()
	var completed: Array = []
	var callback := func(): completed.append(true)
	_page().result_presentation_finished.connect(callback)
	_page().present_result([event], [], "character-terminal", 991)
	_page()._animator.advance(.02)
	_check(_page()._result_pending and completed.is_empty() and _page()._presentation.is_animating(), character + " terminal waits for finite protagonist animation")
	await create_timer(.6).timeout
	_check(completed.size() == 1 and not _page()._result_pending, character + " terminal releases exactly once with live idle")
	_page().result_presentation_finished.disconnect(callback)
	shell.refresh()
	await _settle()
	_check(shell.press("battle:map"), character + " map overlay remains accessible")
	_check(shell.press("battle:close_panel"), character + " overlay returns to hand controls")
	_check(helpers.fingerprint(shell.session) == original, character + " motion and overlay checks remain read-only")
	# Exercise transient restoration through the same production resolver.
	_page()._stage_effects.remember()
	var hero := _hero()
	_page()._actors.erase(actor_id)
	hero.get_parent().remove_child(hero)
	_page()._stage_effects._restore_refined_target(actor_id)
	var transient: BattleActorView = _page()._stage_effects._refined_transients.get(actor_id)
	_check(is_instance_valid(transient) and int(transient.rig.specification.version) == int(CharacterArt.VERSIONS[character]), character + " transient result actor uses production selected version")
	if is_instance_valid(transient):
		transient.free()
	_page()._stage_effects._refined_transients.erase(actor_id)
	_page()._stage.add_child(hero)
	_page()._actors[actor_id] = hero


func _published_commands() -> void:
	for step in 20:
		var view := shell.session.get_view()
		if not view.battle is Dictionary:
			break
		var draft := {"type": "end_turn", "payload": {}}
		for card: Dictionary in view.battle.hand:
			if str(card.definition_id) in ["R3-C-01", "R3-P01-02"]:
				var payload := {"card_instance_id": str(card.card_id), "target_ids": [str(view.battle.tasks[0].task_id)], "replace_unit_id": null}
				var preview := shell.session.preview_action(ActionDraft.new(&"play_card", payload))
				if preview.ok and preview.data.can_submit:
					draft = {"type": "play_card", "payload": payload}
					break
		var baseline := control.submit(CommandContext.new(str(control.get_view().run_id), control.get_view().revision), GameAction.new(StringName(draft.type), draft.payload))
		var before := _hero().rig.cue_count
		shell.submit_action(draft)
		var equal: bool = helpers.fingerprint(control) == helpers.fingerprint(shell.session)
		_check(baseline.accepted and equal, character + " command %s preserves exact domain RNG revision and events" % step)
		var events: Array = []
		for index in baseline.events.size():
			events.append(BattleEventAnimator.new()._event_dictionary(baseline.events[index], index))
		report.commands.append({"character": character, "step": step, "input": draft, "equal": equal,
			"accepted": baseline.accepted, "expected_hash": helpers.fingerprint(control).sha256_text(), "actual_hash": helpers.fingerprint(shell.session).sha256_text(), "events": events})
		if not equal:
			report.commands[-1].expected_state = JSON.parse_string(helpers.fingerprint(control))
			report.commands[-1].actual_state = JSON.parse_string(helpers.fingerprint(shell.session))
		if step < 3:
			await _record(character + "-command-%s" % step, .8)
		else:
			await _settle()
		if is_instance_valid(_hero()) and str(draft.type) == "play_card":
			_check(_hero().rig.cue_count > before, character + " actual played card cues protagonist")
		if not baseline.accepted or not equal:
			break
	_check(not shell.session.get_view().battle is Dictionary and not shell._waiting_for_battle, character + " real battle completes and result animation releases")
	await _save(character + "-after-real-battle", "normal_result")


func _legacy_save() -> void:
	var store := SaveStore.new("user://character-legacy-%s" % Time.get_ticks_usec())
	var session := GameSession.new(store)
	_configure_session(session)
	_check(session.start_run(StartRunRequest.new("P03", &"normal", "campus_v3", "32")).accepted, "historical campus_v3 starts through existing compatibility")
	_check(session.save_current().ok, "historical schema saves without an art field")
	var before: String = helpers.fingerprint(session)
	var restored := GameSession.new(store)
	_check(restored.continue_run().ok and helpers.fingerprint(restored) == before, "historical manifest and domain survive continue without migration")
	session.free()
	shell = helpers.attach_shell(restored)
	shell.show_screen("")
	_check(helpers.enter_node(shell, str(restored.get_view().run.reachable_node_ids[0])), "historical continued run enters battle")
	await _settle()
	_check(is_instance_valid(_hero()) and int(_hero().rig.specification.version) == 10, "historical P03 ID loads selected V10 in normal battle")
	await _save("legacy-P03", "legacy_continue")
	shell.free()


func _fallbacks() -> void:
	for entry in [["N01", "task"], ["R3-U01", "unit"], ["test_P01", "player"]]:
		var actor := BattleActorView.new()
		actor.configure(entry[0], entry[1])
		_check(not is_instance_valid(actor.rig), "non-selected actor retains existing art: " + entry[0])
		actor.free()
	_check(not BattleActorView.pilot_enabled and BattleActorView.pilot_stage_background.is_empty(), "normal route never enabled a pilot override")


func _write_report() -> void:
	report.engine = Engine.get_version_info()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.scope = "Normal GameShell menu/setup/map/battle/continue, four selected rigs; isolated stores only. No pilot override. Controlled lifecycle probes are separate from recorded published commands."
	report.versions = CharacterArt.VERSIONS
	report.production_seed = "32"
	report.pilot_enabled = BattleActorView.pilot_enabled
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _configure_session(session: GameSession) -> void:
	var audio := session.get_audio_settings()
	audio.muted = true
	_check(session.update_settings({"autosave": false, "audio": audio}).ok, "isolated settings accepted")


func _presentation_settings(session: GameSession, patch: Dictionary) -> void:
	var preferences := session.get_presentation_settings()
	preferences.merge(patch, true)
	_check(session.update_settings({"presentation": preferences}).ok, "complete presentation settings accepted")
