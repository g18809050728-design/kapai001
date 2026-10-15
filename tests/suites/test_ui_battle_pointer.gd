extends RefCounted

var _failures: Array[String] = []
var _shell: GameShell
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	_shell = _helpers.attach_shell(
		GameSession.new(SaveStore.new("user://g7-pointer-%s" % Time.get_ticks_usec()))
	)
	_shell.session.update_settings({"autosave": false})
	_shell.press("menu:new")
	var input := _find_input(_shell.page)
	input.text = "0"
	input.text_changed.emit("0")
	_shell.press("setup:start")
	_shell.press("node:" + str(_shell.session.get_view().run.reachable_node_ids[0]))
	_shell.get_tree().root.size = Vector2i(1280, 800)
	await _frames()
	var original := _fingerprint()
	var card := _card("K14")
	_check(card != null, "seed 0 contains a targeted card")
	if card == null:
		_shell.free()
		return _failures
	var source := _point(card, Vector2(85, 80))
	_mouse_move(source)
	await _frames()
	_check(_battle()._hovered_card == card, "mouse hover raises the physical card")
	_check(_fingerprint() == original, "hover preserves state and RNG")
	# Drag out, then drop back in the hand: no command is submitted.
	_mouse_button(source, true)
	_mouse_move(_stage_point(Vector2(650, 300)), true)
	await _frames()
	_check(_battle()._dragging, "mouse motion beyond threshold begins drag")
	_mouse_move(_stage_point(Vector2(650, 690)), true)
	_mouse_button(_stage_point(Vector2(650, 690)), false)
	await _frames()
	_check(_fingerprint() == original, "dropping back into hand cancels without cost")
	_check(_battle().selection_snapshot().card_id == "", "return drop clears local draft")
	# An empty patch of battlefield is not a legal target for this card.
	await _drag(_card("K14"), Vector2(500, 290))
	_check(_fingerprint() == original, "illegal targeted drop preserves state and RNG")
	# Right click and Esc cancel a live drag, including its ghost.
	for use_escape in [false, true]:
		card = _card("K14")
		_mouse_button(_point(card, Vector2(85, 80)), true)
		_mouse_move(_stage_point(Vector2(500, 290)), true)
		if use_escape:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.pressed = true
			_shell.get_tree().root.push_input(key, true)
		else:
			_mouse_button(_stage_point(Vector2(500, 290)), true, MOUSE_BUTTON_RIGHT)
		_mouse_button(_stage_point(Vector2(500, 290)), false)
		await _frames()
		_check(
			_fingerprint() == original and not _battle()._dragging,
			"pointer cancellation preserves complete state"
		)
	# A legal target drop submits exactly one real play_card command.
	var task_id := str(_shell.session.get_view().battle.tasks[0].task_id)
	var target: Button = _battle()._buttons["task:" + task_id]
	var destination := target.get_global_rect().get_center()
	var revision: int = _shell.session.get_view().revision
	card = _card("K14")
	_mouse_button(_point(card, Vector2(85, 80)), true)
	_mouse_move(destination, true)
	_mouse_button(destination, false)
	await _frames()
	_check(_shell.session.get_view().revision == revision + 1, "target drop publishes one revision")
	_check(_card("K14") == null, "target drop removes the played instance from hand")
	_check(
		_shell.session.get_view().battle.tasks[0].work_remaining < 30,
		"target drop applies real work effect"
	)
	_mouse_button(destination, false)
	_check(
		_shell.session.get_view().revision == revision + 1,
		"duplicate release does not replay the card"
	)
	# A non-targeted card can be dropped into the battlefield.
	revision = _shell.session.get_view().revision
	await _drag(_card("K02"), Vector2(520, 300))
	_check(_shell.session.get_view().revision == revision + 1, "non-targeted drop submits once")
	# A real choice locks mouse card input as well as the button interface.
	_shell.press("card:" + str(_card("K03").card_data.card_id))
	await _frames()
	_check(_battle().is_locked(), "real draw/discard card opens choice overlay")
	var pending := _fingerprint()
	await _drag(_battle()._hand_cards[0], Vector2(520, 300))
	_check(_fingerprint() == pending, "pending choice rejects background card drag")
	# Physical mouse selection of a candidate and confirmation remain reachable.
	var candidate_uid := ""
	for uid in _battle().button_uids():
		if str(uid).begins_with("choice:") and uid != "choice:confirm":
			candidate_uid = str(uid)
			break
	var candidate: BattleCard = _battle()._buttons[candidate_uid]
	var candidate_point := _point(candidate, Vector2(80, 60))
	_mouse_move(candidate_point)
	_mouse_button(candidate_point, true)
	_mouse_button(candidate_point, false)
	await _frames()
	_check(
		_battle().selection_snapshot().choice_selected_ids.size() == 1,
		"physical click selects a choice card"
	)
	_check(_fingerprint() == pending, "candidate selection remains local")
	var confirm: Button = _battle()._buttons["choice:confirm"]
	var confirm_point := confirm.get_global_rect().get_center()
	_mouse_button(confirm_point, true)
	_mouse_button(confirm_point, false)
	await _frames()
	_check(not _battle().is_locked(), "physical confirmation closes pending choice")
	# The entire battle adapts to the supported small window without a page scroll.
	var old_size := _shell.get_tree().root.size
	_shell.get_tree().root.size = Vector2i(960, 640)
	await _frames()
	_check(not _battle().get_child(0) is ScrollContainer, "battle has no whole-page scroll")
	var stage_rect := Rect2(
		_battle()._stage.global_position, Vector2(1280, 800) * _battle()._stage.scale
	)
	_check(
		stage_rect.size.x <= _shell.size.x + 1 and stage_rect.size.y <= _shell.size.y + 1,
		"small-window stage remains inside viewport"
	)
	_shell.get_tree().root.size = old_size
	print(
		"G7_POINTER_EVIDENCE=",
		JSON.stringify(
			{
				"seed": 0,
				"real_input_events": true,
				"target_drop": true,
				"no_target_drop": true,
				"cancel_state_rng": true,
				"pending_lock": true,
				"choice_click": true,
				"failures": _failures
			}
		)
	)
	_shell.free()
	return _failures


func _drag(card: BattleCard, destination: Vector2) -> void:
	if card == null:
		_check(false, "card required for drag exists")
		return
	_mouse_button(_point(card, Vector2(85, 80)), true)
	_mouse_move(_stage_point(destination), true)
	_mouse_button(_stage_point(destination), false)
	await _frames()


func _point(control: Control, local: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local


func _stage_point(local: Vector2) -> Vector2:
	return _point(_battle()._stage, local)


func _mouse_move(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_shell.get_tree().root.push_input(event, true)


func _mouse_button(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	_shell.get_tree().root.push_input(event, true)


func _battle() -> BattleScreen:
	return _shell.page as BattleScreen


func _card(definition_id: String) -> BattleCard:
	for card in _battle()._hand_cards:
		if card.card_data.definition_id == definition_id:
			return card
	return null


func _fingerprint() -> String:
	return _helpers.fingerprint(_shell.session)


func _frames() -> void:
	await _shell.get_tree().process_frame
	await _shell.get_tree().process_frame


func _find_input(node: Node) -> LineEdit:
	if node is LineEdit:
		return node
	for child in node.get_children():
		var found := _find_input(child)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("battle pointer: " + message)
