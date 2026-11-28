extends SceneTree

const Fixtures = preload("res://tests/suites/test_ui_shell_pages.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := GameSession.new(SaveStore.new("user://settings-layout-%s" % Time.get_ticks_usec()))
	var shell := Fixtures.new().attach_shell(session)
	for dimensions in [Vector2i(568, 320), Vector2i(844, 390), Vector2i(1280, 800)]:
		UiStyle.web_touch = dimensions.x < 1000
		root.size = dimensions
		for scale in [100, 125, 150]:
			var preferences := session.get_presentation_settings()
			preferences.text_scale = scale
			_check(session.update_settings({"presentation": preferences}).ok, "sets real preference %d%%" % scale)
			shell._apply_presentation()
			shell.show_screen("settings")
			await _settle()
			var page := shell.page as UiExperiencePage
			await _tap(page._buttons["settings:display"])
			for uid in ["settings:display", "settings:sound", "settings:diagnostics", "settings:back", "settings:apply"]:
				var control := page._buttons[uid] as Control
				_check(control.size.y >= 44 and page.get_global_rect().encloses(control.get_global_rect()), "%s fits %s at %d%%" % [uid, dimensions, scale])
			_check(page._scroll.size.y > 150, "settings keeps a useful reading area")
			var off := page._buttons["settings:speed:0"] as Button
			_check(page._scroll.get_global_rect().grow(1).has_point(off.get_global_rect().position), "animation controls begin inside the scroll region")
			await _tap(page._buttons["settings:sound"])
			var slider := page.find_child("VolumeMaster", true, false) as HSlider
			_check(slider.is_visible_in_tree() and slider.size.x > 105 and slider.size.y >= 44, "volume slider fits and has a usable hit area")
			await _tap(page._buttons["settings:diagnostics"])
			_check(page._buttons["settings:restore_backup"].is_visible_in_tree() and page._buttons["settings:restore_backup"].disabled, "empty backup is visible and cannot be restored")
			_check(page._buttons["settings:save"].disabled, "manual save is unavailable before a run")
			await _tap(page._buttons["settings:back"])
	UiStyle.web_touch = true
	root.size = Vector2i(844,390)
	_check(session.start_run(StartRunRequest.new("P01", &"normal", "campus_four_year", "42")).accepted, "production run started")
	shell.show_screen("settings")
	await _settle()
	var settings := shell.page as UiExperiencePage
	var run_before := Fixtures.new().fingerprint(session)
	await _tap(settings._buttons["settings:sound"])
	var master := settings.find_child("VolumeMaster", true, false) as HSlider
	master.value = 37
	await _tap(settings._buttons["settings:diagnostics"])
	_check(settings._settings_status.text == "尚未应用" and session.get_audio_settings().Master == 100, "audio draft survives a tab switch")
	_check(shell.press("settings:autosave:false") and shell.press("settings:apply"), "settings uses existing save command")
	await _settle()
	_check(session.get_audio_settings().Master == 37 and not session.get_profile().autosave, "mixed draft persists on one apply")
	_check(settings._settings_tab == "save" and settings._settings_status.text.begins_with("已生效"), "apply preserves tab and refreshes state")
	_check(shell.press("settings:save") and str(settings.view.save_status).begins_with("最近手动保存"), "manual save refreshes the save tab")
	_check(settings.view.backup_meta is Dictionary and settings.view.backup_meta.term == 1, "backup metadata includes the real saved term")
	_check(Fixtures.new().fingerprint(session) == run_before, "settings and manual save preserve gameplay and RNG")
	shell.queue_free()
	await _settle()
	print("SETTINGS_LAYOUT=", JSON.stringify({"checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await _settle()


func _settle() -> void:
	for _frame in 4:
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
