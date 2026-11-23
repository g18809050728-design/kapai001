extends RefCounted

var failures: Array[String] = []
var checks := 0
var commands: Array = []
var capture_directory := ""
var fixtures = preload("res://tools/event_polish_fixtures.gd").new()


func run() -> Array[String]:
	_art_routes()
	await _readable_rooms()
	await _free_actions()
	await _paid_events()
	await _disabled_event()
	await _settings_and_test_buttons()
	failures.append_array(fixtures.failures)
	UiStyle.text_scale = 1.0
	var report := {"checks": checks, "failures": failures, "commands": commands,
		"scope": "UI-only narrative/art routing and real public commands from isolated route checkpoints"}
	if not capture_directory.is_empty():
		var file := FileAccess.open(capture_directory.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("EVENT_POLISH_CHECKS=", checks, " failures=", failures.size(), " real_command_pairs=", commands.size())
	return failures


func _art_routes() -> void:
	var narratives: Array[String] = []
	var paths: Array[String] = []
	for key in ["V01", "V03", "V04", "V10", "C", "I", "L", "LAB", "T", "ST", "FAMILIAR"]:
		var event_id: String = key if key.begins_with("V") else ""
		var kind: String = "E" if not event_id.is_empty() else key
		var story := CampusRoomIllustration.details(kind, event_id)
		var copy := CampusRoomIllustration.narrative(kind, event_id)
		_check(copy.length() >= 55 and copy.contains("\n\n"), "substantial two-paragraph introduction " + key)
		_check(not narratives.has(copy), "unique introduction " + key)
		narratives.append(copy)
		_check(not paths.has(str(story.get("art", ""))), "independent artwork path " + key)
		paths.append(str(story.get("art", "")))
		_check(CampusRoomIllustration.background_texture(kind, event_id) != null, "background resolves " + key)
		var illustration := CampusRoomIllustration.new()
		illustration.configure(kind, str(story.get("title", "")), event_id)
		_check(illustration.artwork != null and illustration.story_key == key, "precise art identity " + key)
		_check(illustration.artwork.get_size() == Vector2(1024, 1024), "high resolution is retained " + key)
		illustration.free()
	_check(CampusRoomIllustration._texture("res://assets/art/events/missing.png") == null, "missing image uses safe null fallback")
	_check(CampusRoomIllustration.narrative("E", "UNKNOWN") == CampusRoomIllustration.narrative("E"), "unknown event preserves generic narrative fallback")
	var fallback := CampusRoomIllustration.new()
	fallback.configure("UNKNOWN", "未知情境", "UNKNOWN")
	_check(fallback.artwork != null and fallback.story_key.is_empty(), "unknown art uses existing campus asset")
	fallback.free()


func _readable_rooms() -> void:
	for key in ["V01", "V03", "V04", "V10", "C", "I", "L", "LAB", "T", "ST", "FAMILIAR"]:
		var shell: GameShell = fixtures.room("E" if key.begins_with("V") or key == "FAMILIAR" else key, key if key.begins_with("V") else ("V10" if key == "FAMILIAR" else ""), key == "FAMILIAR")
		if shell == null:
			continue
		var before: String = fixtures.helpers.fingerprint(shell.session)
		for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
			for scale in [100, 125, 150]:
				await _present(shell, dimensions, scale)
				var page := shell.page as UiExperiencePage
				var prefix := "%s/%d/%d " % [key, dimensions.x, scale]
				var illustration := page._room_illustration
				_check(is_instance_valid(illustration) and illustration.story_key == key, prefix + "correct visible image")
				_check(page.get_global_rect().encloses(illustration.get_global_rect()), prefix + "image stays within viewport")
				_check(not illustration.get_global_rect().intersects(page._scroll.get_global_rect()), prefix + "image and text do not overlap")
				var narrative := page.find_child("EventNarrative", true, false) as Label
				var heading := page.find_child("EventTitle", true, false) as Label
				_check(narrative != null and heading != null, prefix + "story title and full introduction exist")
				_check(narrative != null and narrative.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and not narrative.clip_text, prefix + "full introduction wraps without truncation")
				_check(page._scroll.get_h_scroll_bar().max_value <= page._scroll.get_h_scroll_bar().page + 1, prefix + "no horizontal scroll required")
				for uid in page.button_uids():
					var button: Control = page._buttons[uid]
					if not button.has_meta("story_choice"):
						continue
					_check(button.size.y >= 44 and button.size.x >= 44, prefix + "physical action target " + str(uid))
					page._scroll.ensure_control_visible(button)
					await _frames(3)
					_check(page._scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), prefix + "action can be scrolled fully into view " + str(uid))
					var copy := button.find_child("StoryChoiceCopy", true, false) as Control
					_check(copy != null and button.get_global_rect().grow(1).encloses(copy.get_global_rect()), prefix + "action copy fits hit target " + str(uid))
					for label in button.find_children("Choice*", "Label", true, false):
						_check(button.get_global_rect().grow(1).encloses(label.get_global_rect()), prefix + "title/effect readable inside action " + str(uid))
				if key.begins_with("V"):
					var leave: Button = page._buttons["event:option:leave"]
					page._scroll.ensure_control_visible(leave)
					leave.grab_focus()
					await _frames()
					_check(leave.has_focus() and page._scroll.get_global_rect().grow(1).encloses(leave.get_global_rect()), prefix + "last event action reachable by focus")
					_check(leave.get_theme_stylebox("focus") is StyleBoxTexture, prefix + "visible matching focus skin")
				_check(fixtures.helpers.fingerprint(shell.session) == before, prefix + "reading/scaling/scrolling/focus preserve full state/revision/RNG")
		shell.free()


func _free_actions() -> void:
	for entry in [["V01", "return_home"], ["V01", "play_games"], ["V04", "rest"], ["V10", "return_card"], ["V10", "service_desk"], ["V01", "leave"], ["V03", "leave"], ["V04", "leave"], ["V10", "leave"]]:
		var a: GameShell = fixtures.room("E", entry[0])
		var b: GameShell = fixtures.room("E", entry[0])
		b.hide()
		var uid := "event:option:leave" if entry[1] == "leave" else "event:" + str(entry[1])
		var draft := a.page.action_draft(uid)
		var original: Button = a.page._buttons[uid]
		var revision: int = a.session.get_view().revision
		_check(a.press(uid), "native free event button executes " + str(entry))
		var current := b.session.get_view()
		var result := b.session.submit(CommandContext.new(str(current.run_id), current.revision), GameAction.new(StringName(draft.type), _replace_run_ids(draft.payload, str(a.session.get_view().run_id), str(current.run_id))))
		_check(result.accepted, "reference public free command accepts " + str(entry))
		_check(_normalized(a.session) == _normalized(b.session), "button matches reference complete state/RNG " + str(entry))
		_check(a.session.get_view().revision == revision + 1, "free action requires exactly one command " + str(entry))
		var after: String = fixtures.helpers.fingerprint(a.session)
		original.pressed.emit()
		_check(fixtures.helpers.fingerprint(a.session) == after, "repeated old free signal has no second consumption " + str(entry))
		commands.append({"event": entry[0], "option": entry[1], "type": draft.type, "mode": "free button/public command A/B", "equal": _normalized(a.session) == _normalized(b.session)})
		a.free()
		b.free()
		await _frames(1)


func _paid_events() -> void:
	for entry in [["V01", "travel"], ["V03", "consult"], ["V04", "upgrade_work"]]:
		var shell: GameShell = fixtures.room("E", entry[0])
		var reference: GameShell = fixtures.room("E", entry[0])
		reference.hide()
		await _present(shell, Vector2i(960, 600), 150)
		var session := shell.session
		var before: String = fixtures.helpers.fingerprint(session)
		_check(shell.press("event:" + str(entry[1])), "paid/target event opens details " + str(entry))
		await _frames()
		_check(fixtures.helpers.fingerprint(session) == before, "event preselection does not pay " + str(entry))
		_check(shell.press("selection:cancel"), "event details can return " + str(entry))
		_check(fixtures.helpers.fingerprint(session) == before, "cancelling event preserves all state/RNG " + str(entry))
		shell.press("event:" + str(entry[1]))
		if entry[1] in ["travel", "consult"]:
			var picks := shell.page.button_uids().filter(func(uid): return str(uid).begins_with("event:" + str(entry[1]) + ":pick:"))
			_check(not picks.is_empty() and shell.press(picks[0]), "real frozen event candidate can be chosen " + str(entry))
		await _frames()
		_check(fixtures.helpers.fingerprint(session) == before, "event target selection remains read-only " + str(entry))
		var confirm: Button = shell.page._buttons["event:confirm"]
		var cancel: Button = shell.page._buttons["selection:cancel"]
		_check(confirm.global_position.x > cancel.global_position.x, "cancel left / final confirm right " + str(entry))
		_check(shell.page.get_global_rect().encloses(confirm.get_global_rect()) and confirm.size.y >= 44, "fixed final confirm remains reachable " + str(entry))
		_check(not confirm.disabled, "final event action enabled only with complete selection " + str(entry))
		await _capture(str(entry[0]) + "-" + str(entry[1]) + "-confirm-960-150")
		var draft := shell.page.action_draft("event:confirm")
		var context := reference.session.get_view()
		var control := reference.session.submit(CommandContext.new(str(context.run_id), context.revision), GameAction.new(StringName(draft.type), _replace_run_ids(draft.payload, str(session.get_view().run_id), str(context.run_id))))
		var revision: int = session.get_view().revision
		_check(shell.press("event:confirm") and control.accepted, "one final confirmation submits real event " + str(entry))
		_check(session.get_view().revision == revision + 1, "paid/target action consumes one command " + str(entry))
		_check(_normalized(session) == _normalized(reference.session), "confirmed event matches reference state/RNG " + str(entry))
		var after: String = fixtures.helpers.fingerprint(session)
		confirm.pressed.emit()
		_check(fixtures.helpers.fingerprint(session) == after, "old confirmation cannot pay twice " + str(entry))
		commands.append({"event": entry[0], "option": entry[1], "mode": "local selection + one final confirmation/public command A/B", "equal": _normalized(session) == _normalized(reference.session)})
		shell.free()
		reference.free()
		await _frames(1)


func _disabled_event() -> void:
	for entry in [["V04", "upgrade_work", 1, "资源不足"], ["V03", "drop", 40, "没有符合条件的目标"]]:
		var shell: GameShell = fixtures.room("E", entry[0])
		# Resource and target availability continue to come from the real domain.
		# Current four-year cards have rarity=basic but no tag="basic", so drop
		# is correctly unavailable under the existing tag-filter rule.
		shell.session._state.run.vitality = entry[2]
		shell.refresh()
		await _present(shell, Vector2i(960, 600), 150)
		var before: String = fixtures.helpers.fingerprint(shell.session)
		var uid := "event:" + str(entry[1])
		var button: Button = shell.page._buttons[uid]
		_check(button.disabled and not shell.press(uid), "domain-unavailable action is disabled " + uid)
		_check(button.text.contains(entry[3]) and button.tooltip_text.contains(entry[3]), "blocking reason remains visible and available on hover " + uid)
		_check(fixtures.helpers.fingerprint(shell.session) == before, "disabled action has no effects " + uid)
		shell.page._scroll.ensure_control_visible(button)
		await _capture(str(entry[0]) + "-disabled-960-150")
		shell.free()


func _settings_and_test_buttons() -> void:
	var session := GameSession.new(SaveStore.new("user://event-polish-buttons-%d" % Time.get_ticks_usec()))
	session.update_settings({"autosave": false})
	var shell: GameShell = fixtures.helpers.attach_shell(session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			shell.show_screen("settings")
			await _frames()
			_check(shell.page._buttons["settings:text:" + str(scale)].get_meta("skin_role") == "selected", "settings selection shares cut skin at %d/%d" % [dimensions.x, scale])
			for uid in ["settings:apply", "settings:back", "settings:diagnostics"]:
				var button: Button = shell.page._buttons[uid]
				_check(button.size.y >= 44 and shell.page.get_global_rect().encloses(button.get_global_rect()), "settings control fits physical viewport " + uid)
			shell.show_screen("menu")
			shell.press("menu:test")
			await _frames()
			for uid in ["test:start", "test:back"]:
				var button: Button = shell.page._buttons[uid]
				_check(button.size.y >= 44 and shell.page.get_global_rect().encloses(button.get_global_rect()), "test home fixed action reachable " + uid)
			_check(shell.page._buttons["test:start"].global_position.x > shell.page._buttons["test:back"].global_position.x, "test start remains right of return")
			shell.show_screen("menu")
	shell.press("menu:test")
	_check(shell.press("test:start") and session.has_test_room(), "styled test entry starts the public isolated test context")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var hud := shell._test_hud
			for uid in hud.button_uids():
				var button: Button = hud._buttons[uid]
				_check(button.size.y >= 44 and button.size.x >= 44 and hud.get_global_rect().encloses(button.get_global_rect()), "test HUD visible physical hit target " + str(uid))
	_check(session.get_test_view().run.screen == "map", "public test entry opens the campus map")
	# Result styling remains covered with a legacy standalone fixture.
	session.close_test_room()
	_check(session.start_test_room({"character_id": "P01", "encounter_id": "N01", "seed": "42"}).accepted,
		"legacy fixture starts for result styling")
	_check(session.set_test_outcome(shell._test_context(), "won").accepted, "legacy manual result opens result page")
	shell.refresh()
	_check(shell.page is TestRoomPage and shell.page.screen == "test_room_result", "legacy result page is present")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			for uid in shell.page.button_uids():
				if not str(uid).begins_with("test:result:"):
					continue
				var button: Button = shell.page._buttons[uid]
				_check(button.size.y >= 44 and shell.page.get_global_rect().encloses(button.get_global_rect()), "all test result actions fit " + str(uid))
	shell.free()


func _normalized(session: GameSession) -> String:
	return fixtures.helpers.fingerprint(session).replace(str(session.get_view().run_id), "RUN")


func _replace_run_ids(payload: Dictionary, old: String, fresh: String) -> Dictionary:
	return JSON.parse_string(JSON.stringify(payload).replace(old, fresh))


func _present(shell: GameShell, dimensions: Vector2i, scale: int) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = dimensions
	shell.session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await _frames(8)


func _frames(count: int = 5) -> void:
	for frame in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _capture(caption: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var tree := Engine.get_main_loop() as SceneTree
	_check(tree.root.get_texture().get_image().save_png(capture_directory.path_join(caption + ".png")) == OK, "save actual interaction frame " + caption)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
