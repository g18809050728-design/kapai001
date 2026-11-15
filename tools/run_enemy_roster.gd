extends "res://tools/run_character_integration.gd"

var encounter_records: Array = []
var lifecycle_records: Array = []
var seen_enemies := {}


func _initialize() -> void:
	output = OS.get_environment("CAMPUS_ENEMY_GAME_OUT")
	if output.is_empty():
		output = "res://artifacts/verification/enemy-roster-20261115/game-01"
	capture = true
	call_deferred("_start")


func _start() -> void:
	if FileAccess.file_exists(output.path_join("report.json")):
		push_error("Choose fresh CAMPUS_ENEMY_GAME_OUT evidence")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.title = "敌怪独立形象正式接入验证 · 隔离存档"
	root.size = Vector2i(1280, 800)
	_check(not BattleActorView.pilot_enabled, "normal enemy roster requires no pilot override")
	for id: String in CharacterArt.RIGS:
		character = id
		await _normal_run()
		await _test_room()
	await _legacy_save()
	await _encounters()
	await _enemy_lifecycles()
	await _fallbacks()
	_write_report()
	print("ENEMY_ROSTER_GAME_RESULT=", JSON.stringify({"checks": report.checks.size(), "failures": report.failures,
		"commands": report.commands.size(), "screens": report.screens.size(), "frames": report.frames.size(),
		"enemy_ids": seen_enemies.keys(), "output": output}))
	quit(0 if report.failures.is_empty() else 1)


func _enemy_matrix() -> void:
	var original: String = helpers.fingerprint(shell.session)
	for actor: BattleActorView in _page()._actors.values():
		if actor.actor_kind != "task":
			continue
		_check(is_instance_valid(actor.rig), character + " first encounter has its own enemy rig")
		if not is_instance_valid(actor.rig):
			continue
		_check(str(actor.rig.specification.definition_id) == actor.definition_id, "enemy identity survives normal battle and continue")
		var geometry := _geometry(_page())
		for pose in ["action", "hit", "guard", "enter", "phase", "depart"]:
			actor.cue(pose, _page().effect_speed())
			await create_timer(.025).timeout
			_check(_geometry(_page()) == geometry, "enemy " + pose + " preserves target and HUD rectangles")
			actor.reset_pose()
		var identity := actor.get_instance_id()
		shell.refresh()
		await _frames(3)
		_check(actor.get_instance_id() == identity, "enemy refresh retains live skeleton")
		actor.set_motion(false)
		var stopped: Dictionary = actor.rig.debug_snapshot().rotations
		await create_timer(.06).timeout
		_check(not actor.rig.loop_player.is_playing() and stopped == actor.rig.debug_snapshot().rotations, "enemy disabled motion is still")
		actor.set_motion(true)
		for multiplier in [1.0, 2.0, 3.0]:
			var started := Time.get_ticks_msec()
			await actor.cue("action", 4.0 * multiplier).finished
			var expected: float = actor.rig.action_length("action") / (4.0 * multiplier)
			_check(absf((Time.get_ticks_msec() - started) / 1000.0 - expected) < .12, "enemy respects base x4 / preference x%s" % multiplier)
	_check(helpers.fingerprint(shell.session) == original, "enemy motion probes preserve domain revision RNG and events")
	# Unwind Tween.finished before the parent test frees the containing shell.
	await _frames(2)


func _encounters() -> void:
	root.size = Vector2i(1280, 800)
	var definitions: Array = load("res://data/four_year/definitions/encounters.json").data
	for definition: Dictionary in definitions:
		var id := str(definition.id)
		var session := _sandbox(id)
		if session == null:
			continue
		shell = helpers.attach_shell(session)
		shell.refresh()
		await _frames(4)
		_check(shell.page is BattleScreen, "isolated encounter opens production BattleScreen: " + id)
		if shell.page is BattleScreen:
			var members := _inspect_enemies(id)
			await _save("encounter-" + id, "public_test_room_fixture")
			encounter_records.append({"encounter": id, "members": members, "scope": "public isolated test-room config, not natural campaign progression"})
			for member: Dictionary in session.get_test_view().battle.tasks:
				var task_id := str(member.task_id)
				var task_definition: Dictionary = session.test_service().catalog.get_definition("task", str(member.definition_id)).data
				for phase: Dictionary in task_definition.phases:
					var applied := session.apply_test_patch(shell._test_context(), {"ops": [{"op": "set_task_phase", "task_id": task_id, "phase_key": phase.phase_key}]})
					_check(applied.accepted, "public phase fixture applies: %s/%s" % [member.definition_id, phase.phase_key])
					shell.refresh()
					await _frames(2)
					_inspect_enemies(id + "/" + str(phase.phase_key))
					if task_definition.phases.size() > 1:
						await _save("phase-%s-%s" % [id, phase.phase_key], "public_test_room_phase_fixture")
			if definition.members.size() > 1 or str(definition.kind) == "boss":
				root.size = Vector2i(960, 640)
				await _frames(4)
				_inspect_enemies(id + "/960")
				await _save("encounter-" + id + "-960", "public_test_room_fixture")
				root.size = Vector2i(1280, 800)
		shell.free()
		await _frames(2)
	for id: String in EnemyArt.ids():
		# Summoned/transformed definitions are covered by real rule turns below.
		if id not in ["Q0A_3_1", "Q0E_2", "Q0E_3", "Q0B_1"]:
			_check(seen_enemies.has(id), id + " appears in an enabled encounter")


func _sandbox(encounter: String) -> GameSession:
	var session := GameSession.new(SaveStore.new("user://enemy-roster-saves-%s" % Time.get_ticks_usec()))
	_configure_session(session)
	session.test_service().store = TestStore.new("user://enemy-roster-tests-%s" % Time.get_ticks_usec())
	var started := session.start_test_room({"character_id": "P01", "encounter_id": encounter, "seed": "32"})
	_check(started.accepted, "public test-room config accepts " + encounter)
	if not started.accepted:
		session.free()
		return null
	return session


func _inspect_enemies(label_: String) -> Array:
	var members: Array = []
	for actor: BattleActorView in _page()._actors.values():
		if actor.actor_kind != "task":
			continue
		var expected := EnemyArt.rig_path(actor.definition_id)
		var ready := not expected.is_empty()
		_check(is_instance_valid(actor.rig) == ready, label_ + ": exact enemy route " + actor.definition_id)
		if ready and is_instance_valid(actor.rig):
			_check(str(actor.rig.specification.definition_id) == actor.definition_id, label_ + ": native skeleton retains enemy identity")
			_check(int(actor.rig.specification.version) == EnemyArt.version(actor.definition_id), label_ + ": selected enemy version")
			seen_enemies[actor.definition_id] = true
			_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, label_ + ": enemy art leaves target input accessible")
		members.append({"id": actor.definition_id, "phase": actor.phase_index, "new_art": ready,
			"rig": actor.rig.debug_snapshot() if is_instance_valid(actor.rig) else {}})
	return members


func _enemy_lifecycles() -> void:
	for case_: Array in [["Q0E", 1, ["Q0E_2", "Q0E_3"]], ["Q0A", 3, ["Q0A_3_1"]], ["Q0B", 3, ["Q0B_1"]]]:
		var session := _sandbox(str(case_[0]))
		if session == null:
			continue
		shell = helpers.attach_shell(session)
		shell.refresh()
		await _frames(3)
		# Extra health is an explicit sandbox setup; turns still use published rules.
		var setup_ops: Array = [
			{"op": "set_player_field", "field": "max_vitality", "value": 999},
			{"op": "set_player_field", "field": "vitality", "value": 999}]
		# These encounters initially include the add-ons. Remove them explicitly
		# so observing a new task proves that a rule actually summoned it.
		for task: Dictionary in session.get_test_view().battle.tasks:
			if str(task.definition_id) in case_[2]:
				setup_ops.append({"op": "remove_task", "task_id": task.task_id})
		var health := session.apply_test_patch(shell._test_context(), {"ops": setup_ops})
		_check(health.accepted, "isolated health fixture accepted for " + str(case_[0]))
		var lifecycle_events: Array = []
		for turn in int(case_[1]):
			var acted := session.submit_test_action(shell._test_context(), {"type": "end_turn", "payload": {}})
			_check(acted.accepted, "real sandbox end_turn accepted: %s/%s" % [case_[0], turn])
			shell.refresh()
			await _frames(3)
			var members := _inspect_enemies("lifecycle-" + str(case_[0]))
			lifecycle_events.append_array(acted.events.map(func(event): return str(event.type)))
			lifecycle_records.append({"encounter": case_[0], "turn": turn, "members": members, "events": acted.events.map(func(event): return str(event.type))})
		var live_ids: Array = session.get_test_view().battle.tasks.map(func(task): return str(task.definition_id))
		for id: String in case_[2]:
			_check(id in live_ids, "real rule turn summons/transforms " + id)
		_check(("task_transformed" if case_[0] == "Q0B" else "task_summoned") in lifecycle_events, "actual lifecycle event published for " + str(case_[0]))
		await _save("lifecycle-" + str(case_[0]), "real_sandbox_turn_after_controlled_setup")
		for actor: BattleActorView in _page()._actors.values():
			if actor.actor_kind == "task" and is_instance_valid(actor.rig):
				_page()._stage_effects.remember()
				var entity_id := ""
				for key in _page()._actors:
					if _page()._actors[key] == actor:
						entity_id = str(key)
				_page()._actors.erase(entity_id)
				actor.get_parent().remove_child(actor)
				_page()._stage_effects._restore_refined_target(entity_id)
				var transient: BattleActorView = _page()._stage_effects._refined_transients.get(entity_id)
				_check(is_instance_valid(transient) and transient.definition_id == actor.definition_id and is_instance_valid(transient.rig), "departed enemy restores exact production art " + actor.definition_id)
				if is_instance_valid(transient):
					transient.free()
				_page()._stage_effects._refined_transients.erase(entity_id)
				_page()._stage.add_child(actor)
				_page()._actors[entity_id] = actor
				break
		shell.free()
		await _frames(2)
	await _real_phase_change()
	for id: String in EnemyArt.ids():
		_check(seen_enemies.has(id), id + " is covered by actual production battle rendering")


func _real_phase_change() -> void:
	var session := _sandbox("B01")
	if session == null:
		return
	shell = helpers.attach_shell(session)
	shell.refresh()
	await _frames(3)
	var old: Dictionary = session.get_test_view().battle.tasks[0].duplicate(true)
	var setup := session.apply_test_patch(shell._test_context(), {"ops": [
		{"op": "set_task_field", "task_id": old.task_id, "field": "work_remaining", "value": 1},
		{"op": "set_task_field", "task_id": old.task_id, "field": "shield", "value": 0},
		{"op": "clear_zone", "zone": "hand"},
		{"op": "add_card", "definition_id": "R3-C-01", "zone": "hand", "count": 1}]})
	_check(setup.accepted, "explicit low-work phase fixture accepted")
	var hand: Array = session.get_test_view().battle.hand
	if hand.is_empty():
		_check(false, "phase fixture has an actual work card")
	else:
		var acted := session.submit_test_action(shell._test_context(), {"type": "play_card", "payload": {
			"card_instance_id": hand[0].card_id, "target_ids": [old.task_id], "replace_unit_id": null}})
		_check(acted.accepted, "real published work card advances phase")
		shell.refresh()
		await _frames(4)
		var next: Dictionary = session.get_test_view().battle.tasks[0]
		_check(str(next.phase_key) != str(old.phase_key), "real phase key changes through battle rules")
		_check("task_advanced" in acted.events.map(func(event): return str(event.type)), "phase advance publishes a real event")
		var members := _inspect_enemies("real-phase-B01")
		lifecycle_records.append({"encounter": "B01", "scope": "real sandbox card after explicit 1-work setup",
			"old_task": old, "next_task": next, "members": members, "events": acted.events.map(func(event): return str(event.type))})
		await _save("lifecycle-B01-phase", "real_sandbox_card_after_controlled_setup")
	shell.free()
	await _frames(2)


func _fallbacks() -> void:
	for entry in [["R3-AC-TASK-A", "task"], ["unknown_enemy", "task"], ["R3-U01", "unit"], ["test_P01", "player"]]:
		var actor := BattleActorView.new()
		actor.configure(entry[0], entry[1])
		_check(not is_instance_valid(actor.rig), "historical or unknown actor retains fallback: " + entry[0])
		actor.free()
	_check(not BattleActorView.pilot_enabled, "production and sandbox routes never set a pilot override")


func _write_report() -> void:
	report.engine = Engine.get_version_info()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.scope = "Normal menu/setup/map/battle/save/continue with real published commands and domain A/B; all enabled encounters via public isolated sandbox config; explicit phase/lifecycle fixtures are labeled separately. No natural four-year completion claim."
	report.versions = CharacterArt.VERSIONS
	report.production_seed = "32"
	report.pilot_enabled = BattleActorView.pilot_enabled
	report.enemy_roster = EnemyArt.INDEX.data
	report.seen_enemies = seen_enemies.keys()
	report.encounters = encounter_records
	report.enemy_lifecycles = lifecycle_records
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


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
			_check(_rigs().size() == 1 + page.view.tasks.size() and hero.rig.bones.size() == 27 and hero.rig.meshes.size() == 6, character + " protagonist and all enemy definitions use their registered skeletons")
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
	_check(_rigs().all(func(rig): return not rig.loop_player.is_playing()), character + " reduced motion stops enemy and protagonist loops")
	_presentation_settings(shell.session, {"reduced_motion": false, "animation_speed": 0})
	shell._apply_presentation()
	shell.refresh()
	await _frames(3)
	_check(not _hero().rig.loop_player.is_playing(), character + " animation off also stops selected rig")
	_check(_rigs().all(func(rig): return not rig.loop_player.is_playing()), character + " animation off also stops every enemy loop")
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
	await _enemy_matrix()


