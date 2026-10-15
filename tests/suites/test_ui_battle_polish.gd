extends RefCounted

var _failures: Array[String] = []
var _shell: GameShell
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	_shell = _helpers.attach_shell(
		GameSession.new(SaveStore.new("user://g7-battle-polish-%s" % Time.get_ticks_usec()))
	)
	_shell.session.update_settings({"autosave": false})
	_shell.press("menu:new")
	var seed := _find_input(_shell.page)
	seed.text = "0"
	seed.text_changed.emit("0")
	_shell.press("setup:start")
	_shell.press("node:" + str(_shell.session.get_view().run.reachable_node_ids[0]))
	var viewport := _shell.get_tree().root
	var original_size := viewport.size
	viewport.size = Vector2i(1280, 800)
	await _frames()
	var before := _fingerprint()
	_check(_shell.press("battle:deck"), "full deck is reachable during battle")
	var panel: String = _battle().display_snapshot().panel
	_check(
		panel.contains("本局牌组") and panel.contains("完成量 6") and panel.contains("专注 1"),
		"full deck includes actual card cost and effect"
	)
	_check(
		panel.contains("携带饰品") and panel.contains("作业牌完成量 +1") and panel.contains("每回合限 1 次"),
		"full deck includes actual carried relic effect and limit"
	)
	_check(_fingerprint() == before, "opening full deck preserves complete state and RNG")
	_check(_battle().draw_pile_card_ids().is_empty(), "full deck does not reveal draw order")
	_key(KEY_ESCAPE)
	await _frames()
	_check(_battle().display_snapshot().panel == "", "Esc closes full deck")
	var index := _card_index("K14")
	_check(index >= 0, "seed 0 has a targeted card for real keyboard input")
	if index < 0:
		viewport.size = original_size
		_shell.free()
		return _failures
	_key(KEY_1 + index, true)
	_check(_battle().selection_snapshot().card_id == "", "key echo does not select or use cards")
	_key(KEY_1 + index)
	await _frames()
	_check(
		_battle().selection_snapshot().card_id != "" and _fingerprint() == before,
		"physical number key locally selects targeted card without paying cost"
	)
	_check(
		(
			_battle()._hint_label.text.contains("剩余专注")
			and _battle()._hint_label.text.contains("已选")
			and _battle()._hint_label.text.contains("高亮目标")
		),
		"selected card hint includes remaining focus and next target action"
	)
	_key(KEY_ESCAPE)
	await _frames()
	_check(
		_battle().selection_snapshot().card_id == "" and _fingerprint() == before,
		"keyboard cancellation preserves complete state and RNG"
	)
	_key(KEY_1 + index)
	var revision: int = _shell.session.get_view().revision
	var task_id := str(_shell.session.get_view().battle.tasks[0].task_id)
	_check(_shell.press("task:" + task_id), "keyboard-selected card submits through real target")
	_check(
		_shell.session.get_view().revision == revision + 1, "selected card publishes one command"
	)
	before = _fingerprint()
	_check(_shell.press("battle:discard"), "discard is reachable after real play")
	panel = _battle().display_snapshot().panel
	_check(
		panel.contains("弃牌堆 · 1 张") and panel.contains("专注 1") and panel.contains("完成量 5"),
		"discard displays public card cost and full effect"
	)
	_check(_fingerprint() == before, "discard inspection preserves complete state and RNG")
	_key(KEY_ESCAPE)
	# Reuse the actual public card view as an isolated exhaust display fixture.
	var display := _battle().view.duplicate(true)
	display.zones_public.exhaust = display.zones_public.discard.duplicate(true)
	_battle().render(display)
	_check(_shell.press("battle:exhaust"), "exhaust viewer is reachable")
	panel = _battle().display_snapshot().panel
	_check(
		panel.contains("消耗堆 · 1 张") and panel.contains("专注 1") and panel.contains("完成量 5"),
		"exhaust displays public card cost and full effect"
	)
	_check(_fingerprint() == before, "exhaust inspection preserves complete state and RNG")
	_key(KEY_ESCAPE)
	_shell.refresh()
	for window_size in [Vector2i(1280, 800), Vector2i(960, 640)]:
		viewport.size = window_size
		await _frames()
		var deck: Button = _battle()._buttons["battle:deck"]
		var rules: Button = _battle()._buttons["battle:rules"]
		_check(
			not deck.get_global_rect().intersects(rules.get_global_rect()),
			"deck and rules controls remain distinct at %s" % window_size
		)
		_check(
			Rect2(Vector2.ZERO, viewport.size).encloses(deck.get_global_rect()),
			"deck control stays in viewport at %s" % window_size
		)
	index = _card_index("K03")
	_check(index >= 0, "draw/discard card remains available for keyboard play")
	if index >= 0:
		revision = _shell.session.get_view().revision
		_key(KEY_1 + index)
		await _frames()
		_check(
			_battle().is_locked() and _shell.session.get_view().revision == revision + 1,
			"physical number key uses an untargeted card through normal submission"
		)
		before = _fingerprint()
		_check(not _shell.press("battle:deck"), "pending effect locks full deck control")
		_key(KEY_1)
		_key(KEY_ESCAPE)
		_check(_fingerprint() == before, "pending choice ignores background keyboard commands")
	viewport.size = original_size
	_shell.free()
	return _failures


func _battle() -> BattleScreen:
	return _shell.page as BattleScreen


func _card_index(definition_id: String) -> int:
	for index in _battle()._hand_cards.size():
		if str(_battle()._hand_cards[index].card_data.get("definition_id", "")) == definition_id:
			return index
	return -1


func _key(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	_shell.get_tree().root.push_input(event, true)


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
		_failures.append("battle polish: " + message)
