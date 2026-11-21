extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _out := ""


func run() -> Array[String]:
	_out = OS.get_environment("CAMPUS_REFERENCE_CAPTURE_OUT")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	await _map_and_menu()
	await _battle_and_relics()
	await _reward_and_legacy()
	await _test_room_details()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	var evidence := {"checks": _checks, "failures": _failures, "captures": _captures, "scope": "isolated production sessions; relic ownership is controlled fixture data, not naturally acquired; no human aesthetic acceptance"}
	if not _out.is_empty():
		var file := FileAccess.open(_out + "/checks.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence, "\t"))
	print("UI_MENU_RELIC_REVISION=", JSON.stringify(evidence))
	return _failures


func _session() -> GameSession:
	var session := GameSession.new(SaveStore.new("user://menu-relic-%d" % Time.get_ticks_usec()))
	_check(session.update_settings({"autosave": false, "presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}}).ok, "isolated preferences accepted")
	_check(session.start_run(StartRunRequest.new("P03", &"hard", "campus_four_year", "42")).accepted, "production campaign starts")
	return session


func _equip(session: GameSession) -> void:
	# Explicit controlled ownership with a gap and shuffled storage order.
	# Production make_view supplies all definitions/effects and slot identities.
	var run: RunState = session._state.run
	var first := run.next_instance_seq
	var bookmark := run.next_instance_id("relic")
	var second := run.next_instance_seq
	var guide := run.next_instance_id("relic")
	run.relics.assign([
		{"relic_id": bookmark, "definition_id": "RX-C04", "slot": 2, "acquired_order": first},
		{"relic_id": guide, "definition_id": "RX-C01", "slot": 0, "acquired_order": second}])


func _present(shell: GameShell, dimensions: Vector2i, scale: int) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = dimensions
	shell.session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
	shell._apply_presentation()
	shell.refresh()
	await _frames()


func _map_and_menu() -> void:
	var session := _session()
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	await _frames()
	shell.press("inspect:relics")
	await _frames()
	_check(_text(shell.page._reference).contains("尚未携带饰品"), "no invented starting equipment")
	_key(KEY_ESCAPE)
	await _frames()
	_equip(session)
	shell.refresh()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var page := shell.page as UiExperiencePage
			var target := str(session.get_view().run.reachable_node_ids[0])
			page.press("node:" + target)
			var original: Button = page._buttons["node:" + target]
			var fingerprint := _helpers.fingerprint(session)
			var generation := page._render_generation
			_click(page._buttons["flow:options"].get_global_rect().get_center())
			await _frames()
			_check(page._toolbar.is_menu_open(), "physical map menu click opens")
			_check(_text(page._toolbar).contains("挑战难度"), "menu displays actual selected difficulty")
			_check(page.button_reason("map:save").contains("可保存"), "legal save has correct explanation")
			for uid in ["flow:log", "flow:help", "flow:info", "flow:settings", "map:save", "map:menu"]:
				_check(page._buttons.has(uid) and not page.button_disabled(uid), "implemented legal menu action " + uid)
			await _capture("map-menu-%d-%d" % [dimensions.x, scale])
			await _menu_click(page, "flow:help")
			_check(is_instance_valid(page._reference) and page._reference.section == "rules", "map menu rule caption receives pointer instead of underlying preview")
			_key(KEY_ESCAPE)
			await _frames()
			await _menu_click(page, "flow:info")
			_check(is_instance_valid(page._reference) and page._reference.section == "info", "map menu info caption opens real adventure information")
			_key(KEY_ESCAPE)
			await _frames()
			await _menu_click(page, "flow:log")
			_check(is_instance_valid(page._reference) and page._reference.section == "log", "map menu record caption receives pointer")
			_key(KEY_ESCAPE)
			await _frames()
			_click(page._buttons["flow:options"].get_global_rect().get_center())
			await _frames()
			_key(KEY_L)
			await _frames()
			_check(is_instance_valid(page._reference) and page._reference.section == "log", "map menu L opens actual log")
			_check(not page.press("map:enter"), "log blocks background map confirmation")
			_check(page.get_global_rect().encloses(page._reference._close.get_global_rect()), "reference close fits viewport")
			page._reference._search.text = "absent:result"
			page._reference._search.text_changed.emit("absent:result")
			_check(_text(page._reference).contains("没有匹配记录"), "search empty result explained")
			page._reference._search.text = ""
			page._reference._search.text_changed.emit("")
			_click(page._reference._tabs.rules.get_global_rect().get_center())
			await _frames()
			_check(page._reference.section == "rules" and _text(page._reference).contains("胜负与资源"), "rule tab opens structured help")
			await _capture("map-rules-%d-%d" % [dimensions.x, scale])
			_key(KEY_E)
			_key(KEY_1)
			_key(KEY_ESCAPE)
			await _frames()
			_check(not is_instance_valid(page._reference) and not is_instance_valid(page._inspector), "Esc closes reference immediately")
			_check(page._buttons["node:" + target] == original and generation == page._render_generation, "reference retains exact map controls and layout generation")
			_check(str(page._choices.get("map:node", "")) == target and not page.button_disabled("map:enter"), "selection and legal confirmation restored")
			var slot: Button = page._buttons["toolbar:relic:2"]
			_check(slot.get_global_rect().size.x >= 44 and slot.get_global_rect().size.y >= 44, "relic slot has physical 44 pixel target")
			slot.grab_focus()
			_click(slot.get_global_rect().get_center())
			await _frames()
			_check(page._reference.selected_relic == str(session.get_view().run.relics[0].relic_id) and _text(page._reference).contains("第 3、5 回合"), "physical slot opens the corresponding real relic effect")
			_check(page._reference.data.relics == page.view.relics, "reference uses exact public relic data")
			await _capture("map-relics-%d-%d" % [dimensions.x, scale])
			_click(page._reference._tabs.info.get_global_rect().get_center())
			await _frames()
			_check(_text(page._reference).contains("挑战") and _text(page._reference).contains("2 / 3"), "info contains real difficulty and occupied slots")
			_key(KEY_ESCAPE)
			await _frames()
			_check(slot.has_focus() and not slot.disabled, "closing restores exact equipment focus and enabled state")
			_check(_helpers.fingerprint(session) == fingerprint, "all browsing preserves domain, all RNG, log and revision")
			await _menu_click(page, "map:save")
			_check(shell._ui_feedback.visible and shell._ui_feedback.size.y <= 96, "successful save stays a compact top message at every size and scale")
			_check(page.get_global_rect().encloses(shell._ui_feedback.get_global_rect()), "save message stays inside the viewport")
			_check(page._buttons["node:" + target] == original and _helpers.fingerprint(session) == fingerprint, "saving from visible menu preserves selection controls and game state")
	# Settings and save are actual GameShell actions, not visual-only callbacks.
	var fingerprint := _helpers.fingerprint(session)
	await _menu_click(shell.page, "flow:settings")
	await _frames()
	_check((shell.page as UiExperiencePage).screen == "settings", "menu opens actual settings route")
	shell.press("settings:back")
	await _frames()
	_check((shell.page as UiExperiencePage).screen == "map", "settings returns to original map")
	var target := str(session.get_view().run.reachable_node_ids[0])
	shell.page.press("node:" + target)
	var node_button: Button = shell.page._buttons["node:" + target]
	await _menu_click(shell.page, "map:save")
	if shell.last_error != null:
		print("MENU_SAVE_DIAGNOSTIC=", JSON.stringify(shell.last_error.to_dictionary()))
	_check(session.inspect_saves().data.has_save, "menu writes isolated complete save")
	_check(shell.notice.contains("保存"), "save outcome visibly reported")
	_check(shell._ui_feedback.visible and shell._ui_feedback.text == shell.notice, "successful save is actually visible on screen")
	_check(shell.page._buttons["node:" + target] == node_button, "save retains exact map controls")
	_check(_helpers.fingerprint(session) == fingerprint, "save preserves game state")
	await _capture("map-save-feedback-960-150")
	await _menu_click(shell.page, "map:menu")
	await _frames()
	_check((shell.page as UiExperiencePage).screen == "menu", "menu home navigates to actual home")
	shell.press("menu:continue")
	await _frames()
	_check((shell.page as UiExperiencePage).screen == "map" and _helpers.fingerprint(session) == fingerprint, "continue returns to preserved adventure")
	shell.free()
	await _frames()


func _battle_and_relics() -> void:
	var session := _session()
	_equip(session)
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	_check(_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), "enter production battle")
	# One real end-turn command produces actual pressure/resource/DDL records.
	_check(shell.press("battle:end_turn"), "real end turn creates actual event data")
	await _frames()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var page := shell.page as BattleScreen
			var fingerprint := _helpers.fingerprint(session)
			var hand := page._hand_cards.duplicate()
			await _capture("battle-focus-%d-%d" % [dimensions.x, scale])
			page.press("battle:relics")
			await _frames()
			_check(page._reference.section == "relics" and _text(page._reference).contains(UiStyle.label("RX-C01")), "battle relic button displays actual equipment instead of deck")
			_check(_text(page._reference).contains("获得 4 放松"), "battle shows actual relic effect")
			await _capture("battle-relics-%d-%d" % [dimensions.x, scale])
			_key(KEY_ESCAPE)
			await _frames()
			await _menu_click(page, "battle:rules")
			_check(is_instance_valid(page._reference) and page._reference.section == "rules", "battle menu rule caption receives pointer")
			_key(KEY_ESCAPE)
			await _frames()
			await _menu_click(page, "battle:log")
			_check(page._reference.section == "log" and page._reference.data.event_log == session.get_view().event_log, "battle record is exact session event log")
			_check(_text(page._reference).contains("DDL") and _text(page._reference).contains("→"), "log exposes actual target and before/after")
			await _capture("battle-log-%d-%d" % [dimensions.x, scale])
			page._reference._search.text = "DDL"
			page._reference._search.text_changed.emit("DDL")
			_check(_text(page._reference._log_list).contains("DDL"), "search returns actual DDL events")
			_click(page._reference.find_child("ClearLogSearch", true, false).get_global_rect().get_center())
			await _frames()
			var keys := _event_keys(page._reference)
			_check(page._reference._search.text.is_empty() and not keys.is_empty(), "clear button restores the recorded event list")
			_click(page._reference.find_child("LogOrder", true, false).get_global_rect().get_center())
			await _frames()
			keys.reverse()
			_check(_event_keys(page._reference) == keys, "record ordering reverses the exact real event sequence")
			_click(page._reference.find_child("LogFilter", true, false).get_global_rect().get_center())
			await _frames()
			_check(_event_keys(page._reference).size() == session.get_view().event_log.size(), "all-events filter displays every actual event including the entered room")
			_click(page._reference.find_child("LogFilter", true, false).get_global_rect().get_center())
			await _frames()
			_check(_event_keys(page._reference) == keys, "battle filter returns to the same ordered battle records")
			_check(not page.press("battle:end_turn"), "reference disables battle command")
			_key(KEY_E)
			_key(KEY_1)
			_key(KEY_ESCAPE)
			await _frames()
			_check(page._panel_text.is_empty() and not page.button_disabled("battle:end_turn"), "close restores actual battle gates")
			_check(page._hand_cards == hand, "reference does not rebuild any hand control")
			_check(_helpers.fingerprint(session) == fingerprint, "battle browsing preserves full state and RNG")
	shell.free()
	await _frames()


func _reward_and_legacy() -> void:
	var catalog := ContentDB.new("res://data/four_year")
	_check(catalog.load(RelicPilot.ROSTER).ok, "relic reward catalog loads")
	var service := RunService.new(catalog)
	var created := service.create(StartRunRequest.new("P03", &"normal", RelicPilot.ROSTER, "42"))
	var run: RunState = created.data.state
	run.relics.assign([
		{"relic_id": "guide", "definition_id": "RX-C01", "slot": 0},
		{"relic_id": "card", "definition_id": "RX-C02", "slot": 1},
		{"relic_id": "bookmark", "definition_id": "RX-C04", "slot": 2}])
	run.pending_reward = RewardOffer.new({"offer_id": "controlled-relic-reward", "source_node_id": "controlled", "items": [{"item_id": "relic", "kind": "relic", "status": "pending", "candidates": ["RX-C03", "RX-C05", "RX-C06"], "skippable": true}]})
	var page := UiExperiencePage.new()
	page.screen = "reward"
	page.theme = UiStyle.make_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	var before := run.to_dictionary()
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			(Engine.get_main_loop() as SceneTree).root.size = dimensions
			UiStyle.text_scale = scale / 100.0
			page.size = dimensions
			page.render(service.make_view(run))
			page.press("reward:relic:pick:RX-C03")
			await _frames()
			_check(_text(page).contains("将失去的旧效果") or _text(page).contains("失去的旧效果"), "replacement describes lost effects before confirm")
			_check(page.find_children("*", "TextureRect", true, false).size() >= 6, "reward and replacement share actual relic images")
			await _capture("relic-replacement-%d-%d" % [dimensions.x, scale])
			page._scroll.scroll_vertical = 100000
			await _frames()
			await _capture("relic-replacement-slots-%d-%d" % [dimensions.x, scale])
	page.free()
	_check(run.to_dictionary() == before, "reward inspection and replacement preselection do not mutate run")
	catalog = ContentDB.new()
	_check(catalog.load("campus_mvp").ok, "legacy relic catalog loads")
	service = RunService.new(catalog)
	created = service.create(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	page = UiExperiencePage.new()
	page.screen = "map"
	page.theme = UiStyle.make_theme()
	(Engine.get_main_loop() as SceneTree).root.add_child(page)
	page.size = Vector2(960, 600)
	page.render(service.make_view(created.data.state))
	page.press("inspect:relics")
	await _frames()
	_check(page._reference.data.relic_slots == 6, "legacy capacity remains six actual slots")
	_check(_text(page._reference).contains("每回合限"), "legacy full relic limits remain inspectable")
	page.free()
	await _frames()


func _test_room_details() -> void:
	var session := _session()
	var opened := session.start_test_room({"character_id": "P03", "encounter_id": "N01", "seed": "42", "relics": ["RX-C01"]})
	_check(opened.accepted, "independent test battle starts with selected equipment")
	if not opened.accepted:
		print("REFERENCE_TEST_ROOM_DIAGNOSTIC=", opened.error.to_dictionary())
		return
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	await _frames()
	_check(shell.page is BattleScreen, "test room uses same equipment display")
	_check(shell.page.button_disabled("battle:save"), "test room cannot save the underlying formal adventure through menu")
	_check(shell.page.view.relics[0].detail.id == "RX-C01", "test room publishes actual read-only relic definition")
	shell.press("battle:relics")
	await _frames()
	_check(_text(shell.page._reference).contains("获得 4 放松"), "test room relic full effect is inspectable")
	shell.free()
	await _frames()


func _text(node: Node) -> String:
	var lines: Array[String] = []
	for child in node.find_children("*", "Label", true, false):
		lines.append(child.text)
	return "\n".join(lines)


func _event_keys(reference: UiReferenceOverlay) -> Array[String]:
	var keys: Array[String] = []
	for row in reference._log_list.get_children():
		if row.has_meta("event_key"):
			keys.append(str(row.get_meta("event_key")))
	return keys


func _capture(name: String) -> void:
	if _out.is_empty(): return
	await (Engine.get_main_loop() as SceneTree).process_frame
	await RenderingServer.frame_post_draw
	var path := _out + "/" + name + ".png"
	var bitmap := (Engine.get_main_loop() as SceneTree).root.get_texture().get_image()
	_check(bitmap.save_png(path) == OK, "capture saved " + name)
	_captures.append(path)


func _click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)


func _menu_click(page: UiPage, uid: String) -> void:
	var toolbar: UiRunToolbar = page.get("_toolbar")
	if not toolbar.is_menu_open():
		_click(page._buttons["battle:options" if page is BattleScreen else "flow:options"].get_global_rect().get_center())
		await _frames()
	_check(toolbar.is_menu_open(), "pointer opens menu for " + uid)
	var button: Button = page._buttons[uid]
	var scroll := toolbar._menu_column.get_parent() as ScrollContainer
	scroll.ensure_control_visible(button)
	await _frames()
	var point := (button.get_node("MenuCaption") as Label).get_global_rect().get_center()
	_check(toolbar._panel.get_global_rect().has_point(point), "menu caption is visible for " + uid)
	_click(point)
	await _frames()


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)


func _frames() -> void:
	for frame in 8:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok: _failures.append(message)
