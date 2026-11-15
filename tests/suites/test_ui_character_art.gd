extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	_check(not BattleActorView.pilot_enabled, "normal game does not require a pilot override")
	for id: String in CharacterArt.RIGS:
		await _test_character(id)
	var task := BattleActorView.new()
	task.configure("N01", "task")
	_check(is_instance_valid(task.rig) and int(task.rig.specification.version) == EnemyArt.version("N01"), "normal enemies use their registered art")
	task.free()
	var unknown := BattleActorView.new()
	unknown.configure("test_P01", "player")
	_check(unknown.rig == null, "unknown definitions retain the normal fallback")
	unknown.free()
	return _failures


func _test_character(id: String) -> void:
	var store := SaveStore.new("user://character-default-%s-%s" % [id, Time.get_ticks_usec()])
	var session := GameSession.new(store)
	_configure_session(session)
	var shell := _helpers.attach_shell(session) as GameShell
	shell._setup_defaults.default_seed = "32"
	_check(shell.press("menu:new"), id + " opens normal setup")
	_check(shell.press("setup:character:" + id), id + " selects through normal control")
	_check(shell.press("setup:advanced"), id + " opens seed configuration")
	var seed_input: LineEdit = _helpers._line_edit(shell.page)
	if seed_input != null:
		seed_input.text = "32"
		seed_input.text_changed.emit("32")
	_check(seed_input != null and shell.press("inspect:close"), id + " selects deterministic seed through normal configuration")
	await _frames(shell)
	var setup := shell.page as UiExperiencePage
	_check(is_instance_valid(setup._room_figure.rig) and int(setup._room_figure.rig.specification.version) == int(CharacterArt.VERSIONS[id]), id + " setup uses the selected live rig")
	_check(UiStyle.character_portrait(id).resource_path == CharacterArt.texture_path(id, true), id + " tab uses the matching portrait")
	_check(UiStyle.texture(id).resource_path == CharacterArt.texture_path(id), id + " generic art uses matching neutral figure")
	_presentation_settings(session, {"reduced_motion": true})
	shell._apply_presentation()
	shell.refresh()
	await _frames(shell)
	_check(not shell.page._room_figure.rig.loop_player.is_playing(), id + " setup respects reduced motion")
	_presentation_settings(session, {"reduced_motion": false, "animation_speed": 0})
	shell._apply_presentation()
	shell.refresh()
	await _frames(shell)
	_check(not shell.page._room_figure.rig.loop_player.is_playing(), id + " setup respects animations off")
	_check(shell.press("setup:start"), id + " creates a normal run")
	_check(_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), id + " enters via normal map commands")
	await _frames(shell)
	var page := shell.page as BattleScreen
	var hero := _hero(page)
	_check(is_instance_valid(hero) and is_instance_valid(hero.rig), id + " normal battle has a live rig")
	if is_instance_valid(hero) and is_instance_valid(hero.rig):
		_check(int(hero.rig.specification.version) == int(CharacterArt.VERSIONS[id]), id + " battle preserves selected version")
		_check(not hero.rig.loop_player.is_playing(), id + " battle respects animations off")
		var identity := hero.get_instance_id()
		shell.refresh()
		_check(_hero(page).get_instance_id() == identity, id + " refresh retains actor identity")
	var before := _helpers.fingerprint(session) as String
	_check(session.save_current().ok, id + " saves through public boundary")
	var restored := GameSession.new(store)
	_check(restored.continue_run().ok, id + " existing save continues without migration")
	_check(_helpers.fingerprint(restored) == before, id + " load preserves domain revision events and RNG")
	var resumed := _helpers.attach_shell(restored) as GameShell
	resumed.show_screen("")
	await _frames(resumed)
	_check(resumed.page is BattleScreen and is_instance_valid(_hero(resumed.page)) and int(_hero(resumed.page).rig.specification.version) == int(CharacterArt.VERSIONS[id]), id + " continued battle loads selected art")
	resumed.free()
	shell.free()


func _hero(page: BattleScreen) -> BattleActorView:
	if page != null:
		for actor: BattleActorView in page._actors.values():
			if actor.actor_kind == "player":
				return actor
	return null


func _frames(shell: GameShell) -> void:
	for i in 3:
		await shell.get_tree().process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append("Character art: " + message)


func _configure_session(session: GameSession) -> void:
	var audio := session.get_audio_settings()
	audio.muted = true
	_check(session.update_settings({"autosave": false, "audio": audio}).ok, "isolated settings accepted")


func _presentation_settings(session: GameSession, patch: Dictionary) -> void:
	var preferences := session.get_presentation_settings()
	preferences.merge(patch, true)
	_check(session.update_settings({"presentation": preferences}).ok, "complete presentation settings accepted")
