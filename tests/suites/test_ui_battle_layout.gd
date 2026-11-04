extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()
var _shell: GameShell


func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var old_size := tree.root.size
	_shell = _helpers.attach_shell(GameSession.new(SaveStore.new("user://battle-layout-%d" % Time.get_ticks_usec())))
	_shell.session.update_settings({"autosave": false})
	_check(_shell.session.start_run(StartRunRequest.new("P03", &"normal", "campus_four_year", "42")).accepted, "production P03 battle starts")
	_shell.show_screen("")
	_check(_helpers.enter_node(_shell, str(_shell.session.get_view().run.reachable_node_ids[0])), "enters real battle")
	var original: String = _helpers.fingerprint(_shell.session)
	for dimensions in [Vector2i(1280, 800), Vector2i(960, 600)]:
		for scale in [100, 125, 150]:
			tree.root.size = dimensions
			_shell.session.update_settings({"presentation": {"text_scale": scale, "reduced_motion": true, "animation_speed": 0}})
			_shell._apply_presentation()
			_shell.refresh()
			await _frames()
			var label := "%s / %d%%" % [dimensions, scale]
			for kind in ["deck", "log", "draw", "discard", "exhaust"]:
				var uid: String = "battle:" + kind
				var button: Button = _battle()._buttons[uid]
				_check(button is BattlePileButton, "card-shaped " + uid + " at " + label)
				_check(_battle().get_global_rect().encloses(button.get_global_rect()), "pile is inside viewport: " + uid + " at " + label)
				_mouse_move(button.get_global_rect().get_center())
				await _frames()
				_check(_battle()._hover_panel.visible and _battle()._hover_title.text == button.text and not _battle()._hover_body.text.is_empty(), "real pointer explains " + uid + " at " + label)
				_check(_battle().get_global_rect().encloses(_battle()._hover_panel.get_global_rect()), "purpose popup stays inside viewport at " + label)
				_check(not _battle()._hover_panel.get_global_rect().intersects(button.get_global_rect()), "purpose popup avoids its entry at " + label)
				_check(not _battle()._hover_panel.get_global_rect().intersects(_battle()._hint_label.get_global_rect()), "purpose popup avoids action hint at " + label)
				_check(not _battle()._hover_panel.get_global_rect().intersects(_battle()._buttons["battle:end_turn"].get_global_rect()), "purpose popup avoids end turn at " + label)
				_check(button.tooltip_text.is_empty(), "one hover description per entry")
				if kind == "draw":
					_check(_battle()._hover_body.text.contains("不显示实际抽取顺序"), "draw purpose preserves private order")
				_click(button.get_global_rect().get_center())
				await _frames()
				_check(not _battle()._panel_text.is_empty(), "real click opens " + uid + " at " + label)
				if kind == "draw":
					_check(_battle()._panel_text.begins_with("抽牌堆") and _battle().draw_pile_card_ids().size() == int(_battle().view.zone_counts.draw), "draw inspection shows unordered members")
				_key(KEY_ESCAPE)
				await _frames()
				_check(_battle()._panel_text.is_empty(), "Escape returns to battle")
			var focused: Button = _battle()._buttons["battle:deck"]
			_mouse_move(Vector2(15, dimensions.y * 0.5))
			focused.grab_focus()
			await _frames()
			_check(_battle()._hover_panel.visible and _battle()._hover_title.text == "牌组", "keyboard focus explains pile at " + label)
			focused.release_focus()
			_check(_helpers.fingerprint(_shell.session) == original, "all inspection preserves domain/revision/RNG at " + label)
	# Geometry fixtures alter only the read-only presentation, never the session.
	tree.root.size = Vector2i(1280, 800)
	_shell.session.update_settings({"presentation": {"text_scale": 100, "reduced_motion": true, "animation_speed": 0}})
	_shell._apply_presentation()
	_shell.refresh()
	await _frames()
	var base := _battle().view.duplicate(true)
	for amount in [5, 10]:
		var display := base.duplicate(true)
		display.hand = []
		for i in amount:
			var card: Dictionary = base.hand[i % base.hand.size()].duplicate(true)
			card.card_id = "layout-card-%d" % i
			display.hand.append(card)
		_mouse_move(Vector2(20, 150))
		_battle().render(display)
		await _frames()
		for card in _battle()._hand_cards:
			var bounds := _card_bounds(card, true)
			_check(not bounds.intersects(_battle()._hint_label.get_global_rect()), "%d-card fan and shadow avoid hint" % amount)
			for kind in ["draw", "discard", "exhaust", "end_turn"]:
				_check(not bounds.intersects(_battle()._buttons["battle:" + kind].get_global_rect()), "%d-card fan avoids %s" % [amount, kind])
		for index in amount:
			var card: BattleCard = _battle()._hand_cards[index]
			var home_point: Vector2 = card.get_parent().get_global_transform_with_canvas() * (card.home_position + Vector2(25 if index < amount - 1 else 100, 80))
			_mouse_move(home_point)
			await tree.create_timer(0.3).timeout
			_check(_battle()._hovered_card == card, "hover reaches card %d/%d" % [index + 1, amount])
			_check(not _card_bounds(card, true).intersects(_battle()._hint_label.get_global_rect()), "raised card avoids action hint")
			_check(not _card_bounds(card).intersects(_battle()._buttons["battle:end_turn"].get_global_rect()), "raised card avoids end turn")
			_mouse_move(Vector2(20, 150))
			await tree.create_timer(0.2).timeout
	_check(_helpers.fingerprint(_shell.session) == original, "geometry fixtures leave session untouched")
	for phases in [1, 2]:
		var display := base.duplicate(true)
		var task: Dictionary = display.tasks[0]
		task.phase_count = phases
		task.phase_index = 1
		display.statuses.append({"target_id": task.task_id, "status_id": "weakness", "stacks": 1})
		display.statuses.append({"target_id": task.task_id, "status_id": "feebleness", "stacks": 2})
		display.statuses.append({"target_id": display.player.entity_id, "status_id": "weakness", "stacks": 1})
		_battle().render(display)
		await _frames()
		var status: Label = _battle()._stage.get_node("TaskStatus_" + str(task.task_id).validate_node_name())
		_check(status.text.contains("虚弱") and status.text.contains("乏力"), "both task status names remain visible")
		var title: Label
		for child in _battle()._target_frames["task:" + str(task.task_id)].get_children():
			if child is Label and child.text == UiStyle.label(str(task.definition_id)):
				title = child
		_check(title != null and not status.get_global_rect().intersects(title.get_global_rect()), "status strip avoids task title with %d phases" % phases)
		for card in _battle()._hand_cards:
			_check(not _card_bounds(card, true).intersects(_battle()._buttons["statuses:player"].get_global_rect()), "player statuses avoid hand")
	_shell.free()
	tree.root.size = old_size
	UiStyle.text_scale = 1.0
	print("BATTLE_LAYOUT_CHECKS=", JSON.stringify({"sizes": ["1280x800", "960x600"], "text_scales": [100, 125, 150], "fan_counts": [5, 10], "real_mouse": true, "failures": _failures}))
	return _failures


func _card_bounds(card: BattleCard, shadow: bool = false) -> Rect2:
	var corners := [Vector2.ZERO, Vector2(card.size.x, 0), card.size, Vector2(0, card.size.y)]
	var transform := card.get_global_transform_with_canvas()
	var result := Rect2(transform * corners[0], Vector2.ZERO)
	for point in corners:
		result = result.expand(transform * point)
		if shadow:
			result = result.expand(transform * (point + Vector2(4, 7)))
	return result


func _battle() -> BattleScreen:
	return _shell.page as BattleScreen


func _mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)


func _frames() -> void:
	for i in 6:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
