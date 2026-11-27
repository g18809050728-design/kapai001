extends RefCounted

var _failures: Array[String] = []
var _shell: GameShell
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	# This suite owns its session and pointer geometry; do not inherit a prior suite's
	# accessibility scale or reduced-motion state.
	UiStyle.text_scale = 1.0
	UiStyle.reduced_motion = false
	_shell = _helpers.attach_shell(
		GameSession.new(SaveStore.new("user://g7-pointer-%s" % Time.get_ticks_usec()))
	)
	_shell.session.update_settings({"autosave": false})
	_check(_shell.session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "0")).accepted, "historical pointer fixture starts through the session API")
	_shell.show_screen("")
	_helpers.enter_node(_shell, str(_shell.session.get_view().run.reachable_node_ids[0]))
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
	_check(not _battle()._hover_panel.visible, "brief card hover does not open an introduction")
	await _shell.get_tree().create_timer(.75).timeout
	_check(_battle()._hovered_card == card, "mouse hover raises the physical card")
	_check(_fingerprint() == original, "hover preserves state and RNG")
	_check(
		(
			_battle()._hover_panel.visible
			and not _battle()._hover_title.text.is_empty()
			and not _battle()._hover_rich_body.get_parsed_text().is_empty()
		),
		"hover popup is visible with title and body"
	)
	_check(not _battle()._hover_panel.get_global_rect().intersects(card.get_global_rect()), "side explanation avoids covering its source card")
	if _battle()._hover_panel.visible:
		_check(_battle()._hover_panel.mouse_filter == Control.MOUSE_FILTER_STOP and _battle()._hover_scroll.mouse_filter == Control.MOUSE_FILTER_STOP, "unfixed introduction owns pointer input for its glossary dropdown")
		var hover_toggle := _battle()._glossary_toggle.get_global_rect().get_center()
		_mouse_move(hover_toggle)
		await _frames()
		_check(
			_battle()._hover_panel.visible and _battle()._pinned_card_detail.is_empty(),
			"hover introduction stays open while the pointer crosses to the glossary toggle"
		)
		_mouse_button(hover_toggle, true)
		_mouse_button(hover_toggle, false)
		await _frames()
		_check(_battle()._glossary_box.visible, "hovering alone can expand the glossary dropdown")
		_mouse_button(hover_toggle, true)
		_mouse_button(hover_toggle, false)
		await _frames()
		_check(not _battle()._glossary_box.visible, "hovering glossary dropdown closes with the same arrow")
		_mouse_move(Vector2(8, 8))
		await _frames()
		_check(not _battle()._hover_panel.visible, "leaving the side panel hides the unfixed introduction")
	_mouse_move(source)
	await _frames()
	_check(card.tooltip_text == "", "card native tooltip is suppressed")
	card.disabled = true
	card.set_meta("disabled_reason", "专注不足：需要 2，当前 1")
	var unavailable_point := _point(card, Vector2(85, 80))
	_mouse_button(unavailable_point, true)
	_mouse_button(unavailable_point, false)
	await _frames()
	_check(_battle().display_snapshot().panel.is_empty(), "clicking a disabled card does not open its introduction")
	_check(_battle()._feedback_text.contains("专注不足"), "disabled card click shows the exact reason")
	_check(_fingerprint() == original and _battle().selection_snapshot().card_id.is_empty(), "disabled click preserves state, RNG and selection")
	var hand_index := 0
	for index in _battle().view.hand.size():
		if str(_battle().view.hand[index].card_id) == str(card.card_data.card_id):
			hand_index = index
			break
	_key(KEY_1 + hand_index)
	await _frames()
	_check(_battle().display_snapshot().panel.is_empty(), "numeric activation of a disabled card does not open its introduction")
	_check(_battle()._feedback_text.contains("专注不足") and _fingerprint() == original, "numeric activation shows the reason without changing state")
	card.disabled = false
	card.set_meta("disabled_reason", "")
	var detail_before := _fingerprint()
	_key(KEY_I)
	await _frames()
	var detail_panel: String = _battle()._hover_rich_body.get_parsed_text()
	_check(_battle()._hover_rich_body.visible and not _battle()._hover_body.visible, "card detail uses the rich body without the summary label")
	_check(detail_panel.contains("专注"), "I opens card detail with cost text")
	_check(not detail_panel.contains("打出后按顺序结算："), "battle detail omits the removed ordered-resolution heading")
	_check(not _battle()._pinned_card_detail.is_empty() and not _battle()._glossary_body.get_parsed_text().is_empty(), "fixed card explanation exposes a separate glossary section")
	_check(_battle()._glossary_toggle.visible and _battle()._glossary_toggle.text.contains("名词解释"), "fixed card explanation shows the glossary dropdown toggle")
	_check(not _battle()._glossary_box.visible, "glossary dropdown starts collapsed")
	_check(not detail_panel.contains("名词解释："), "effect text no longer mixes in the glossary")
	_check(_battle()._hover_highlight_terms.has("专注"), "card detail resolves the displayed glossary terms for highlighting")
	_check(
		_battle()._hover_highlight_segments.any(func(segment): return bool(segment.get("highlighted", false))),
		"card detail builds highlighted keyword segments"
	)
	_check(
		_battle()._glossary_highlight_segments.any(func(segment): return bool(segment.get("highlighted", false))),
		"glossary builds highlighted term-name segments"
	)
	var toggle_point := _battle()._glossary_toggle.get_global_rect().get_center()
	_mouse_move(toggle_point)
	_mouse_button(toggle_point, true)
	_mouse_button(toggle_point, false)
	await _frames()
	_check(_battle()._glossary_box.visible and _battle()._glossary_body.get_parsed_text().contains("专注"), "clicking the arrow expands the glossary dropdown")
	_check(_battle()._hover_rich_body.get_parsed_text() == detail_panel, "expanding the glossary does not rewrite the effect text")
	_mouse_button(toggle_point, true)
	_mouse_button(toggle_point, false)
	await _frames()
	_check(not _battle()._glossary_box.visible, "clicking the arrow again collapses the glossary dropdown")
	_check(_battle().display_snapshot().panel.is_empty(), "fixed card explanation stays beside the card")
	_check(_fingerprint() == detail_before, "card detail preserves state and RNG")
	_key(KEY_ESCAPE)
	await _frames()
	_check(_battle()._pinned_card_detail.is_empty() and not _battle()._hover_panel.visible, "Esc closes fixed card detail")
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
	_mouse_move(destination)
	await _frames()
	_check(
		(
			_battle()._hover_panel.visible
			and _battle()._hover_meta.text.contains("阶段")
			and _battle()._hover_meta.text.contains("剩余")
		),
		"task hover popup shows phase and remaining work"
	)
	var task_before := _fingerprint()
	_key(KEY_I)
	await _frames()
	var task_panel: String = _battle().display_snapshot().panel
	_check(task_panel.contains("未完成量"), "I opens task detail with remaining work")
	_check(not _battle()._detail_terms.is_empty(), "task detail exposes status terms")
	_check(_fingerprint() == task_before, "task detail preserves state and RNG")
	_key(KEY_ESCAPE)
	await _frames()
	_check(_battle().display_snapshot().panel == "", "Esc closes task detail")
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
	# Small windows retain the same battlefield and fan as the full-size game UI.
	var old_size := _shell.get_tree().root.size
	_shell.get_tree().root.size = Vector2i(960, 640)
	await _frames()
	_check(not _battle()._compact_layout and _battle()._stage.scale == Vector2(.75,.75), "small battle retains the scaled battlefield composition")
	_check(not _battle()._hand_cards.is_empty() and _battle()._hand_cards[0].home_rotation < 0, "small battle retains a curved hand fan")
	var stage_rect := _battle()._stage.get_global_rect()
	_check(
		stage_rect.size.x <= _shell.size.x + 1 and stage_rect.size.y <= _shell.size.y + 1,
		"small-window stage remains inside viewport"
	)
	_check(Rect2(Vector2.ZERO, Vector2(960, 640)).encloses(_battle()._buttons["battle:end_turn"].get_global_rect()), "end turn remains fixed and visible")
	var compact_id := str(_battle().view.hand[0].card_id) if not _battle().view.hand.is_empty() else ""
	var compact_card: Button = _battle()._buttons.get("card:" + compact_id)
	if compact_card != null:
		compact_card.disabled = true
		compact_card.set_meta("disabled_reason", "专注不足：需要 3，当前 0")
		var compact_index := 0
		for index in _battle().view.hand.size():
			if str(_battle().view.hand[index].card_id) == compact_id:
				compact_index = index
				break
		_key(KEY_1 + compact_index)
		await _frames()
		_check(_battle().display_snapshot().panel.is_empty(), "compact numeric activation does not inspect a disabled card")
		_check(_battle()._feedback_text.contains("专注不足"), "compact numeric activation shows the disabled reason")
		compact_card.disabled = false
		compact_card.set_meta("disabled_reason", "")
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


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
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
