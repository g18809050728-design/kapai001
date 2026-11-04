extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()

func run() -> Array[String]:
	await _test_setup()
	var runner = load("res://tests/suites/test_four_year.gd").new()
	_failures.append_array(runner.run())
	for kind in ["relic", "relic_full", "grand", "direction", "destination", "service"]:
		if not runner._checkpoints.has(kind):
			_check(false, "campaign fixture exists: " + kind)
			continue
		var store := SaveStore.new("user://four-year-ui-%s-%s" % [kind, Time.get_ticks_usec()])
		var session := GameSession.new(store)
		session.update_settings({"autosave": false})
		session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
		session._state.run = runner._checkpoints[kind].copy_for_write()
		session._state.random_snapshot = runner._rng.duplicate(true)
		var shell := _helpers.attach_shell(session) as GameShell
		shell.show_screen("")
		await _frames(shell)
		_check(shell.page is UiFlowPage and shell.page.screen == "campaign", "campaign UI route: " + kind)
		var before := _helpers.fingerprint(session) as String
		var offer: Dictionary = session.get_view().run.campaign_offer
		var saved := session.save_current()
		_check(saved.ok, "frozen offer saves via public session: " + kind)
		var restored := GameSession.new(store)
		var continued := restored.continue_run()
		_check(continued.ok, "frozen offer resumes: " + kind)
		if continued.ok:
			_check(restored.get_view().run.campaign_offer == offer, "resume preserves exact displayed offer: " + kind)
		restored.free()
		_check(_helpers.fingerprint(session) == before, "render/save/inspection preserve state/RNG")
		if kind == "relic_full":
			var id: String = offer.candidates[0]
			shell.press("campaign:claim:" + id)
			_check(shell.press("campaign:convert:" + id), "full relic conversion is reachable")
		elif kind in ["relic", "grand", "service"]:
			_check(shell.press("campaign:skip"), "skip advances campaign choice: " + kind)
		else:
			_check(shell.press("campaign:" + ("theory" if kind == "direction" else "job")), "year start choice submits")
		_check(shell.press("campaign:confirm"), "campaign final confirmation submits")
		_check(session.get_view().run.campaign.pending.get("offer_id", "") != offer.offer_id, "choice is resolved once: " + kind)
		await shell.get_tree().create_timer(0.08).timeout
		shell.free()
	await _test_summary_layout()
	await _test_audio_persistence()
	return _failures

func _test_setup() -> void:
	for character_id in ["P01", "P02", "P03", "P04"]:
		var session := GameSession.new(SaveStore.new("user://setup-only-four-year-%s-%s" % [character_id, Time.get_ticks_usec()]))
		session.update_settings({"autosave": false})
		var legacy_run_id := ""
		if character_id == "P02":
			var legacy := session.start_run(StartRunRequest.new("P02", &"normal", "campus_v3", "42"))
			_check(legacy.accepted, "historical save compatibility remains available")
			legacy_run_id = str(session.get_view().run_id)
		var shell := _helpers.attach_shell(session) as GameShell
		_check(shell.press("menu:new"), "new-game menu opens setup")
		await _frames(shell)
		for uid in shell.page.button_uids():
			_check(not str(uid).begins_with("setup:manifest:"), "setup never offers a version selector")
		var descriptions := ""
		for label in shell.page.find_children("*", "Label", true, false):
			descriptions += label.text + "\n"
		_check(descriptions.contains("被动"), "setup initially focuses one character")
		if shell.page._character == "P01":
			_check(descriptions.contains("当前尚无放弃取回选择"), "P01 implementation gap is visible")
		_check(shell.press("setup:character:" + character_id), "character selects: " + character_id)
		shell.press("setup:advanced")
		_check(shell.press("setup:seed_random"), "seed refresh keeps the setup selection")
		_check(shell.press("setup:start"), "setup starts: " + character_id)
		if not legacy_run_id.is_empty():
			_check(str(session.get_view().run_id) == legacy_run_id, "restart confirmation preserves the old run")
			_check(shell.press("setup:restart_confirm"), "historical run confirms replacement")
		var view := session.get_view()
		_check(view.screen == &"map" and view.run.manifest_id == "campus_four_year", "new/replacement run uses only four-year content")
		_check(view.run.character_id == character_id, "setup preserves selected character")
		await shell.get_tree().create_timer(0.08).timeout
		shell.free()

func _test_summary_layout() -> void:
	var session := GameSession.new(SaveStore.new("user://summary-layout-%s" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	session.start_run(StartRunRequest.new("P04", &"normal", "campus_four_year", "42"))
	var shell := _helpers.attach_shell(session) as GameShell
	shell.show_screen("")
	_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0]))
	var page := shell.page as BattleScreen
	var fixture := page.view.duplicate(true)
	fixture.units = [{"unit_id": "layout-probe", "definition_id": "R3-U01", "vitality": 3, "cooperation": 2}]
	var before: String = _helpers.fingerprint(session)
	page.render(fixture)
	var summary := page._stage.get_node("V3Summary") as Control
	var unit: Control = page._target_frames["unit:layout-probe"]
	_check(not summary.get_rect().intersects(unit.get_rect()), "v3 summary never covers partner controls")
	_check(_helpers.fingerprint(session) == before, "layout fixture is read-only")
	await shell.get_tree().create_timer(0.08).timeout
	shell.free()

func _test_audio_persistence() -> void:
	var store := SaveStore.new("user://audio-persist-%s" % Time.get_ticks_usec())
	var session := GameSession.new(store)
	var values := {"Master": 35, "Music": 20, "Ambience": 10, "SFX": 45, "UI": 55, "muted": true}
	_check(session.update_settings({"audio": values}).ok, "five bus settings persist")
	session.free()
	var restored := GameSession.new(store)
	_check(restored.get_audio_settings() == values, "all volumes and mute restore after restart")
	_check(not restored.update_settings({"audio": {"Master": 101}}).ok, "invalid audio patch rejected")
	var detached := AudioManager.new()
	_check(not detached.play_sfx("card_play") and not detached.play_ui("ui_click"), "detached audio never starts playback")
	detached.free()
	var audio := AudioManager.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(audio)
	audio.apply_settings(values)
	_check(audio.is_muted() and is_equal_approx(audio.get_bus_volume("SFX"), 0.45), "saved audio settings applied")
	audio.set_muted(false)
	audio._last_played.clear()
	audio._last_group.clear()
	_check(audio.play_sfx("card_play"), "first sound starts")
	_check(not audio.play_sfx("card_play"), "same sound is suppressed within 180ms")
	_check(not audio.event_sfx("unit_summoned").is_empty(), "partner has event sound")
	await audio.get_tree().create_timer(0.08).timeout
	audio.free()
	restored.free()

func _frames(shell: GameShell) -> void:
	for i in 3:
		await shell.get_tree().process_frame

func _check(value: bool, message: String) -> void:
	if not value: _failures.append("four-year UI: " + message)
