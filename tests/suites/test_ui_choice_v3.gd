extends RefCounted

var _failures: Array[String] = []
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	var root := "user://g7-choice-v3-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(root))) as GameShell
	_check(shell.session.update_settings({"autosave": false}).ok, "disable autosave")
	_check_discard_choice(shell)
	_check_retain_choice(root)
	_check_remove_status_choice(root)
	_check_passive_retrieve_choice(root)
	_check_end_turn_while_editing(root)
	if shell.is_inside_tree():
		shell.queue_free()
	return _failures


func _check_discard_choice(shell: GameShell) -> void:
	var started := shell.session.start_test_room(
		{
			"character_id": "P01",
			"cards":
			[
				"R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01",
				"R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02",
				"R3-P01-01", "R3-P01-01",
			],
			"seed": "42",
		}
	)
	_check(started.accepted, "discard test room starts")
	shell.refresh()
	var card_id := _hand_card(shell, "R3-P01-01")
	_check(not card_id.is_empty(), "快速定位 is in hand")
	if card_id.is_empty():
		return
	_check(shell.press("card:" + card_id), "快速定位 plays through button")
	var pending: Variant = shell.session.get_test_view().get("pending_choice")
	_check(pending is Dictionary, "快速定位 publishes a discard choice")
	if not (pending is Dictionary):
		return
	var battle := shell.page as BattleScreen
	_check(battle.is_locked(), "discard choice locks the battle")
	var candidates: Array = pending.get("candidates", [])
	_check(candidates.size() > 0, "discard choice has candidates")
	if candidates.is_empty():
		return
	var candidate_id := str(candidates[0].get("id", ""))
	_check(battle._buttons.has("choice:" + candidate_id), "discard candidate button is registered")
	_check(shell.press("choice:" + candidate_id), "discard candidate is clickable")
	_check(battle._choice_selected_ids.has(candidate_id), "discard candidate becomes selected")
	_check(shell.press("choice:confirm"), "discard choice confirms")
	_check(
		shell.session.get_test_view().get("pending_choice") == null,
		"discard choice resolves to a stable boundary"
	)
	_check(shell.last_error == null, "discard flow reports no error")


func _check_retain_choice(root: String) -> void:
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(root + "-retain"))) as GameShell
	var started := shell.session.start_test_room(
		{
			"character_id": "P04",
			"cards":
			[
				"R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01",
				"R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02",
				"R3-P04-34", "R3-P04-34",
			],
			"seed": "42",
		}
	)
	_check(started.accepted, "retain test room starts")
	shell.refresh()
	var card_id := _hand_card(shell, "R3-P04-34")
	_check(not card_id.is_empty(), "保留意见 is in hand")
	if card_id.is_empty():
		shell.queue_free()
		return
	_check(shell.press("card:" + card_id), "保留意见 plays through button")
	var pending: Variant = shell.session.get_test_view().get("pending_choice")
	_check(pending is Dictionary, "保留意见 publishes a retain choice")
	if pending is Dictionary:
		var battle := shell.page as BattleScreen
		var candidates: Array = pending.get("candidates", [])
		_check(candidates.size() > 0, "retain choice has candidates")
		if not candidates.is_empty():
			var candidate_id := str(candidates[0].get("id", ""))
			_check(battle._buttons.has("choice:" + candidate_id), "retain candidate button is registered")
			_check(shell.press("choice:" + candidate_id), "retain candidate is clickable")
			_check(battle._choice_selected_ids.has(candidate_id), "retain candidate becomes selected")
			_check(shell.press("choice:confirm"), "retain choice confirms")
			_check(
				shell.session.get_test_view().get("pending_choice") == null,
				"retain choice resolves to a stable boundary"
			)
	shell.queue_free()


func _check_remove_status_choice(root: String) -> void:
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(root + "-status"))) as GameShell
	var started := shell.session.start_test_room(
		{
			"character_id": "P04",
			"cards":
			[
				"R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01", "R3-C-01",
				"R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02", "R3-C-02",
				"R3-P04-37", "R3-P04-37",
			],
			"seed": "42",
		}
	)
	_check(started.accepted, "remove-status test room starts")
	var view := shell.session.get_test_view()
	var ctx := _context(view)
	var player_id := str(view.get("battle", {}).get("player", {}).get("entity_id", ""))
	var patch := _ok_patch(
		shell.session.apply_test_patch(
			ctx, {"schema_version": 1, "resolution_policy": "rollback", "ops": [{"op": "add_status", "status_id": "anxiety", "target_id": player_id, "stacks": 1, "expiry": "next_prepare"}]}
		),
		"add anxiety for 及时沟通"
	)
	if not patch:
		shell.queue_free()
		return
	shell.refresh()
	var card_id := _hand_card(shell, "R3-P04-37")
	_check(not card_id.is_empty(), "及时沟通 is in hand")
	if card_id.is_empty():
		shell.queue_free()
		return
	_check(shell.press("card:" + card_id), "及时沟通 plays through button")
	var pending: Variant = shell.session.get_test_view().get("pending_choice")
	_check(pending is Dictionary, "及时沟通 publishes a status choice")
	if pending is Dictionary:
		var battle := shell.page as BattleScreen
		var candidates: Array = pending.get("candidates", [])
		_check(candidates.size() > 0, "status choice has candidates")
		if not candidates.is_empty():
			var candidate_id := str(candidates[0].get("id", ""))
			_check(battle._buttons.has("choice:" + candidate_id), "status candidate button is registered")
			_check(shell.press("choice:" + candidate_id), "status candidate is clickable")
			_check(battle._choice_selected_ids.has(candidate_id), "status candidate becomes selected")
			_check(shell.press("choice:confirm"), "status choice confirms")
			_check(
				shell.session.get_test_view().get("pending_choice") == null,
				"status choice resolves to a stable boundary"
			)
	shell.queue_free()


func _check_passive_retrieve_choice(root: String) -> void:
	# Decline with an empty confirmation.
	var decline_shell := _open_p01_retrieve_room(root + "-p01-decline")
	if decline_shell == null:
		return
	var decline_pending: Variant = decline_shell.session.get_test_view().get("pending_choice")
	_check(
		decline_pending is Dictionary
		and str(decline_pending.get("kind", "")) == "retrieve_strategy",
		"P01 offers a retrieve choice after a link work"
	)
	if decline_pending is Dictionary:
		var battle := decline_shell.page as BattleScreen
		var candidate_id := str(decline_pending.get("candidates", [])[0].get("id", ""))
		_check(battle._buttons.has("choice:" + candidate_id), "P01 retrieve candidate is registered")
		_check(decline_shell.press("choice:confirm"), "P01 decline confirms with no selection")
		_check(
			decline_shell.session.get_test_view().get("pending_choice") == null,
			"P01 decline closes the choice"
		)
		_check(
			_zone_has(decline_shell, "discard", candidate_id),
			"P01 decline leaves the strategy in discard"
		)
	decline_shell.queue_free()

	# Accept by selecting the strategy.
	var accept_shell := _open_p01_retrieve_room(root + "-p01-accept")
	if accept_shell == null:
		return
	var accept_pending: Variant = accept_shell.session.get_test_view().get("pending_choice")
	if accept_pending is Dictionary:
		var battle := accept_shell.page as BattleScreen
		var candidate_id := str(accept_pending.get("candidates", [])[0].get("id", ""))
		_check(accept_shell.press("choice:" + candidate_id), "P01 retrieve candidate is clickable")
		_check(battle._choice_selected_ids.has(candidate_id), "P01 retrieve candidate is selected")
		_check(accept_shell.press("choice:confirm"), "P01 retrieve confirms")
		_check(
			accept_shell.session.get_test_view().get("pending_choice") == null,
			"P01 retrieve closes the choice"
		)
		_check(_zone_has(accept_shell, "hand", candidate_id), "P01 retrieve returns the strategy")
	accept_shell.queue_free()


func _open_p01_retrieve_room(root: String) -> GameShell:
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(root))) as GameShell
	var started := shell.session.start_test_room(
		{
			"character_id": "P01",
			"cards": ["R3-P01-11", "R3-P01-11", "R3-P01-02", "R3-P01-02", "R3-P01-02"],
			"seed": "42",
		}
	)
	_check(started.accepted, "P01 retrieve test room starts")
	if not started.accepted:
		shell.queue_free()
		return null
	shell.refresh()
	var strategy_id := _hand_card(shell, "R3-P01-11")
	var work_id := _hand_card(shell, "R3-P01-02")
	_check(not strategy_id.is_empty() and not work_id.is_empty(), "P01 retrieve deck is in hand")
	if strategy_id.is_empty() or work_id.is_empty():
		shell.queue_free()
		return null
	_check(shell.press("card:" + strategy_id), "P01 strategy plays through button")
	_check(shell.press("card:" + work_id), "P01 work selects through button")
	var tasks: Array = shell.session.get_test_view().get("battle", {}).get("tasks", [])
	if tasks.is_empty():
		_check(false, "P01 retrieve battle has a task")
		shell.queue_free()
		return null
	var task_id := str(tasks[0].get("task_id", ""))
	_check(shell.press("task:" + task_id), "P01 work targets the task")
	return shell


func _zone_has(shell: GameShell, zone: String, card_id: String) -> bool:
	var battle: Dictionary = shell.session.get_test_view().get("battle", {})
	var cards: Array = (
		battle.get("hand", []) if zone == "hand" else battle.get("zones_public", {}).get(zone, [])
	)
	for card in cards:
		if str(card.get("card_id", "")) == card_id:
			return true
	return false


func _check_end_turn_while_editing(root: String) -> void:
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(root + "-edit"))) as GameShell
	var started := shell.session.start_test_room({"character_id": "P01", "seed": "42"})
	_check(started.accepted, "edit test room starts")
	shell.refresh()
	shell._test_hud.open_editor()
	_check(bool(shell.session.get_test_view().get("test", {}).get("editing", false)), "editor enters edit mode")
	var editor := shell._test_hud.editor
	_check(editor.press("test:editor:tab:time"), "editor time tab is reachable")
	var pressed := editor.press("test:editor:time:end_turn")
	_check(pressed, "editor end-turn button is pressable")
	_check(shell.last_error == null, "editor end-turn reports no error")
	var after := shell.session.get_test_view()
	_check(
		editor.is_open() and bool(after.get("test", {}).get("editing", false)),
		"editor end-turn preserves the visible editor input gate"
	)
	_check(
		int(after.get("test", {}).get("revision", 0)) > 0,
		"editor end-turn advances the battle revision"
	)
	shell.queue_free()


func _context(view: Dictionary) -> Dictionary:
	var test_state: Dictionary = view.get("test", {})
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _ok_patch(result: ActionResult, label: String) -> bool:
	_check(result.accepted, label)
	return result.accepted


func _hand_card(shell: GameShell, definition_id: String) -> String:
	for card in shell.session.get_test_view().get("battle", {}).get("hand", []):
		if str(card.get("definition_id", "")) == definition_id:
			return str(card.get("card_id", ""))
	return ""


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append("ui choice v3: " + label)
