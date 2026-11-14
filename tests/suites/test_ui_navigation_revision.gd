extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _captures: Array = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _out := ""


func run() -> Array[String]:
	_out = OS.get_environment("CAMPUS_NAV_CAPTURE_OUT")
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	await _battle_navigation()
	await _map_navigation()
	await _room_navigation()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	var evidence := {"checks": _checks, "failures": _failures, "captures": _captures, "scope": "real navigation on isolated production sessions; no natural playthrough or human visual approval"}
	if not _out.is_empty():
		var file := FileAccess.open(_out + "/checks.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence, "\t"))
	print("UI_NAVIGATION_REVISION=", JSON.stringify(evidence))
	return _failures


func _session() -> GameSession:
	var session := GameSession.new(SaveStore.new("user://navigation-%d" % Time.get_ticks_usec()))
	_check(session.update_settings({"autosave": false, "presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}}).ok, "isolated presentation settings accepted")
	return session


func _present(shell: GameShell, dimensions: Vector2i, scale: int) -> void:
	(Engine.get_main_loop() as SceneTree).root.size = dimensions
	_check(shell.session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}}).ok, "complete presentation preferences accepted")
	shell._apply_presentation()
	shell.refresh()
	await _frames()
	_check(is_equal_approx(UiStyle.text_scale, scale / 100.0), "actual requested text scale applied")


func _battle_navigation() -> void:
	var session := _session()
	_check(session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42")).accepted, "start actual production run")
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	_check(_helpers.enter_node(shell, str(session.get_view().run.reachable_node_ids[0])), "navigate into actual battle")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var battle := shell.page as BattleScreen
			var toolbar := battle._toolbar
			var before := _helpers.fingerprint(session)
			var controls := {}
			for uid in battle._buttons:
				if str(uid).begins_with("card:"):
					controls[uid] = battle._buttons[uid]
			_main_geometry(battle, ["battle:map", "battle:deck", "battle:options", "battle:relics"])
			_check(int(battle._buttons["battle:deck"].get_meta("nav_count")) == battle.view.cards.size(), "deck badge is actual permanent card count")
			await _capture("battle-bar-%d-%d" % [dimensions.x, scale])
			var toggler: Button = battle._buttons["battle:options"]
			toggler.grab_focus()
			_click(toggler.get_global_rect().get_center())
			await _frames()
			_check(toolbar.is_menu_open() and bool(toggler.get_meta("nav_active")), "actual click opens and marks gear")
			_check(battle.get_global_rect().encloses(toolbar._panel.get_global_rect()), "menu panel fits viewport")
			_check(not shell.press("battle:end_turn"), "menu prevents background commands")
			_key(KEY_E)
			_key(KEY_1)
			await _frames()
			_check(_helpers.fingerprint(session) == before, "background hotkeys cannot advance battle through menu")
			var speed := battle.speed_scale
			_check(shell.press("battle:speed"), "speed row is actionable")
			_check(toolbar.is_menu_open() and battle.speed_scale != speed, "speed updates in place without closing menu")
			_check((battle._buttons["battle:speed"].get_node("MenuValue") as Label).text == "×%s" % battle.speed_scale, "speed label shows actual state")
			var animation := battle.animation_enabled
			shell.press("battle:animation")
			_check(battle.animation_enabled != animation and toolbar.is_menu_open(), "animation changes in place")
			var home: Button = battle._buttons["battle:menu"]
			home.grab_focus()
			await _frames()
			_check(toolbar._panel.get_global_rect().encloses(home.get_global_rect()), "keyboard focus scrolls final menu action into view")
			battle._buttons["battle:close_options"].grab_focus()
			(toolbar._menu_column.get_parent() as ScrollContainer).scroll_vertical = 0
			await _frames()
			for uid in controls:
				_check(battle._buttons[uid] == controls[uid], "menu settings retain the exact hand controls")
			await _capture("battle-menu-%d-%d" % [dimensions.x, scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(not toolbar.is_menu_open() and toggler.has_focus() and not bool(toggler.get_meta("nav_active")), "Escape restores exact gear focus and state")
			_check(not battle._buttons["battle:end_turn"].disabled, "closing menu restores prior legal controls")
			_key(KEY_F10)
			await _frames()
			_check(toolbar.is_menu_open(), "F10 opens same menu")
			_click(Vector2(30, dimensions.y * .5))
			await _frames()
			_check(not toolbar.is_menu_open() and _helpers.fingerprint(session) == before, "outside click closes once without reaching battlefield")
			shell.press("battle:options")
			await _frames()
			_key(KEY_L)
			await _frames()
			_check(not battle._toolbar.is_menu_open() and not battle._panel_text.is_empty(), "L opens log from menu")
			_key(KEY_ESCAPE)
			await _frames()
			battle = shell.page as BattleScreen
			_check(battle._panel_text.is_empty(), "Escape closes log")
			_check(_helpers.fingerprint(session) == before, "navigation and presentation preserve all domain state and random streams")
	shell.free()
	await _frames()


func _map_navigation() -> void:
	var session := _session()
	session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42"))
	var shell: GameShell = _helpers.attach_shell(session)
	shell.show_screen("")
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var page := shell.page as UiExperiencePage
			var before := _helpers.fingerprint(session)
			var target := str(session.get_view().run.reachable_node_ids[0])
			page.press("node:" + target)
			var original: Button = page._buttons["node:" + target]
			var generation := page._render_generation
			_check(page._scroll.get_global_rect().encloses(original.get_global_rect()), "reachable selected node fits after viewport and text-scale changes")
			_main_geometry(page, ["inspect:deck", "flow:options", "inspect:relics"])
			_check(not page._buttons.has("flow:map"), "the map page never creates its redundant map button")
			await _capture("map-bar-%d-%d" % [dimensions.x, scale])
			page.press("flow:options")
			await _frames()
			_check(page._toolbar.is_menu_open() and not page.press("map:enter"), "room menu isolates pending map confirmation")
			_check(page.get_global_rect().encloses(page._toolbar._panel.get_global_rect()), "room menu fits actual viewport")
			await _capture("map-menu-%d-%d" % [dimensions.x, scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(page._buttons["node:" + target] == original and page._render_generation == generation and str(page._choices.get("map:node")) == target, "opening and closing the menu preserve selected node and control")
			_check(not page._buttons["map:enter"].disabled, "closing menu restores map confirmation")
			_key(KEY_D)
			await _frames()
			_check(is_instance_valid(page._inspector) and page._inspector.z_index > page._toolbar.z_index, "collection inspector covers and isolates the top navigation")
			_check(bool(page._buttons["inspect:deck"].get_meta("nav_active")), "deck inspection marks the active navigation entry")
			_key(KEY_ESCAPE)
			await _frames()
			_check(not is_instance_valid(page._inspector) and not bool(page._buttons["inspect:deck"].get_meta("nav_active")) and page._buttons["node:" + target] == original, "closing collection restores map controls and clears active state")
			page.press("flow:options")
			_key(KEY_M)
			await _frames()
			_check(not page._toolbar.is_menu_open() and page._map_overview and not is_instance_valid(page._full_map), "map menu M switches existing overview without duplicating the map")
			_check(str(page._choices.get("map:node")) == target and _helpers.fingerprint(session) == before, "overview retains selection and all domain state")
			await _capture("map-overview-%d-%d" % [dimensions.x, scale])
			_key(KEY_M)
			await _frames()
			_check(not page._map_overview and not is_instance_valid(page._full_map) and not page.button_disabled("map:enter"), "map M returns to detail with original confirmation available")
	shell.free()
	await _frames()


func _main_geometry(page: UiPage, uids: Array) -> void:
	for uid in uids:
		var button: Button = page._buttons[uid]
		var rect := button.get_global_rect()
		_check(button.is_visible_in_tree() and page.get_global_rect().encloses(rect), "primary navigation visible and contained: " + uid)
		_check(rect.size.x >= 44 and rect.size.y >= 44, "actual physical click target at least 44 pixels: " + uid)
		for other in uids:
			if uid != other:
				_check(not rect.intersects(page._buttons[other].get_global_rect()), "main hit areas do not overlap")


func _room_navigation() -> void:
	var room_helper = preload("res://tests/suites/test_ui_flow_revision.gd").new()
	var shell: GameShell = room_helper._controlled_room("C")
	_check(shell != null, "controlled campus club fixture loads actual room")
	if shell == null:
		return
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			await _present(shell, dimensions, scale)
			var page := shell.page as UiExperiencePage
			var before := _helpers.fingerprint(shell.session)
			_main_geometry(page, ["flow:map", "inspect:deck", "flow:options", "inspect:relics"])
			_check(is_instance_valid(page._room_illustration) and not page._room_illustration.get_global_rect().intersects(page._scroll.get_global_rect()), "shared navigation retains room artwork and option area")
			await _capture("club-bar-%d-%d" % [dimensions.x, scale])
			page.press("flow:options")
			await _frames()
			_check(page._toolbar.is_menu_open() and page.get_global_rect().encloses(page._toolbar._panel.get_global_rect()), "club menu opens within viewport")
			await _capture("club-menu-%d-%d" % [dimensions.x, scale])
			_key(KEY_ESCAPE)
			await _frames()
			_check(_helpers.fingerprint(shell.session) == before, "room menu is read only")
			var room_generation := page._render_generation
			var option_controls := page._buttons.duplicate()
			_check(page.press("flow:map"), "ordinary rooms retain their full map entry")
			await _frames()
			_check(is_instance_valid(page._full_map), "room map entry opens complete read-only map")
			await _capture("club-map-%d-%d" % [dimensions.x, scale])
			var marker: Button = page._full_map._route.get_children().filter(func(c): return c is Button)[0]
			_click(marker.get_global_rect().get_center())
			_click(marker.get_global_rect().get_center())
			await _frames()
			_check(_helpers.fingerprint(shell.session) == before, "repeated clicks on room full map cannot enter nodes")
			_key(KEY_ESCAPE)
			await _frames()
			_check(page._render_generation == room_generation and not is_instance_valid(page._full_map), "closing room map preserves the room generation")
			for uid in option_controls:
				_check(page._buttons[uid] == option_controls[uid], "room map preserves exact underlying controls")
	shell.free()
	await _frames()


func _capture(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var tree := Engine.get_main_loop() as SceneTree
	var image := tree.root.get_texture().get_image()
	_check(image.save_png(_out + "/" + name + ".png") == OK, "actual render saved: " + name)
	_captures.append(name + ".png")


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)


func _key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)


func _frames() -> void:
	for frame in 10:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
