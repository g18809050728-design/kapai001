extends RefCounted

## End-to-end UI smoke: real shell, real buttons, all editor tabs, draft apply,
## pending-choice rollback, result page, snapshot round-trip and isolation.

var _failures: Array[String] = []
var _root := ""


func run() -> Array[String]:
	_root = "user://test-room-e2e-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var session := GameSession.new(SaveStore.new(_root + "/saves"))
	session.test_service().store = TestStore.new(_root + "/room")
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	await _frame()
	_check(shell.press("menu:test"), "menu entry")
	await _frame()
	_check(shell.press("test:start"), "start test room")
	await _frame()
	_check(session.has_test_room(), "test context active")
	var hud: TestHud = shell._test_hud
	var panel: TestEditorPanel = hud.editor
	_check(hud.press("test:open_editor"), "open editor")
	await _frame()
	_check(panel.is_open(), "editor open")

	# Resources: draft, preview, apply.
	_check(panel.press("test:editor:tab:resources"), "resources tab")
	var focus_before := int(session.get_test_view().battle.player.focus)
	_check(panel.press("test:editor:field:player.focus:plus"), "draft focus")
	_check(panel.draft_count() == 1, "one draft")
	_check(panel.press("test:editor:preview"), "preview draft")
	_check(panel.status_text().contains("可应用"), "preview reports applicability")
	_check(panel.press("test:editor:apply"), "apply focus")
	await _frame()
	_check(int(session.get_test_view().battle.player.focus) == focus_before + 1, "focus applied")

	# Cards: search, add, apply.
	_check(panel.press("test:editor:tab:cards"), "cards tab")
	await _frame()
	_check(panel.set_search("R3-P01-01"), "card search input")
	await _frame()
	var add_uid := _find(panel, "test:editor:add:R3-P01-01:")
	_check(not add_uid.is_empty(), "card search result exists")
	var hand_before := int(session.get_test_view().battle.hand.size())
	if not add_uid.is_empty():
		_check(panel.press(add_uid), "add searched card")
		await _frame()
		_check(panel.draft_count() == 1, "card draft")
		_check(panel.press("test:editor:apply"), "apply card")
		await _frame()
		_check(int(session.get_test_view().battle.hand.size()) == hand_before + 1, "card added to hand")

	# Enemies: add a task.
	_check(panel.press("test:editor:tab:enemies"), "enemies tab")
	await _frame()
	var tasks_before := int(session.get_test_view().battle.tasks.size())
	var add_task := _find(panel, "test:editor:addtask:")
	_check(not add_task.is_empty(), "task result exists")
	if not add_task.is_empty():
		_check(panel.press(add_task), "add task draft")
		await _frame()
		_check(panel.press("test:editor:apply"), "apply task")
		await _frame()
		_check(int(session.get_test_view().battle.tasks.size()) == tasks_before + 1, "task added")

	# Statuses: inspiration on player.
	_check(panel.press("test:editor:tab:statuses"), "statuses tab")
	await _frame()
	_check(panel.set_search("inspiration"), "status search")
	await _frame()
	var add_status := _find(panel, "test:editor:addstatus:inspiration:")
	_check(not add_status.is_empty(), "status result exists")
	var statuses_before := int(session.get_test_view().battle.statuses.size())
	if not add_status.is_empty():
		_check(panel.press(add_status), "add status draft")
		await _frame()
		_check(panel.press("test:editor:apply"), "apply status")
		await _frame()
		_check(int(session.get_test_view().battle.statuses.size()) == statuses_before + 1, "status added")

	# Rules: toggle a checkbox through the real control.
	_check(panel.press("test:editor:tab:rules"), "rules tab")
	await _frame()
	var switch_uid := "test:editor:switch:allow_empty_tasks"
	_check(panel.button_uids().has(switch_uid), "switch exists")
	_check(panel.press(switch_uid), "toggle switch")
	await _frame()
	_check(panel.draft_count() == 1, "switch draft queued")
	_check(panel.press("test:editor:apply"), "apply switch")
	await _frame()
	_check(bool(session.get_test_view().switches.get("allow_empty_tasks", false)), "switch applied")

	# History: save snapshot from the editor button.
	_check(panel.press("test:editor:tab:history"), "history tab")
	await _frame()
	_check(panel.press("test:editor:save_snapshot"), "save snapshot from history")
	await _frame()
	var snapshots := session.list_test_files("snapshot")
	_check(not snapshots.is_empty(), "snapshot listed")

	# Close confirmation and discard confirmation.
	_check(panel.press("test:editor:tab:resources"), "back to resources")
	await _frame()
	_check(panel.press("test:editor:field:player.focus:plus"), "draft before close")
	_check(panel.press("test:editor:close"), "close asks confirmation")
	_check(panel.is_open(), "editor remains open")
	_check(panel.press("test:editor:close:cancel"), "cancel close")
	_check(panel.press("test:editor:discard"), "discard asks confirmation")
	_check(panel.press("test:editor:discard:confirm"), "confirm discard")
	await _frame()
	_check(panel.draft_count() == 0, "draft discarded")
	_check(panel.press("test:editor:close"), "close without draft")
	await _frame()
	_check(not panel.is_open(), "editor closed")

	# Real battle command and undo.
	var rounds_before := int(session.get_test_view().battle.round_index)
	shell.submit_action({"type": "end_turn", "payload": {}})
	await _frame()
	_check(int(session.get_test_view().battle.round_index) == rounds_before + 1, "end turn advances")
	shell.submit_action({"type": "test.undo", "payload": {}})
	await _frame()
	_check(int(session.get_test_view().battle.round_index) == rounds_before, "undo restores round")

	# Pending choice: apply a draft with rollback policy.
	var pending_setup := session.apply_test_patch(
		_context(session),
		{
			"ops": [
				{"op": "set_player_field", "field": "focus", "value": 5},
				{"op": "add_card", "definition_id": "R3-P01-16", "zone": "hand", "count": 1},
				{"op": "add_card", "definition_id": "R3-P01-01", "zone": "discard", "count": 1},
			]
		}
	)
	_check(pending_setup.accepted, "pending fixture applies: " + _error(pending_setup.error))
	var view := session.get_test_view()
	var choice_card := ""
	for card in view.battle.hand:
		if str(card.get("definition_id", "")) == "R3-P01-16":
			choice_card = str(card.get("card_id", ""))
	var played := session.submit_test_action(
		_context(session), {"type": "play_card", "payload": {"card_instance_id": choice_card}}
	)
	_check(played.accepted, "choice card plays: " + _error(played.error))
	_check(session.get_test_view().pending_choice is Dictionary, "pending choice exists")
	_check(hud.press("test:open_editor"), "reopen editor during choice")
	await _frame()
	_check(panel.press("test:editor:tab:resources"), "resources tab during choice")
	await _frame()
	_check(panel.press("test:editor:field:player.focus:plus"), "draft during choice")
	_check(panel.press("test:editor:apply"), "apply shows policy row")
	_check(panel.button_uids().has("test:editor:apply:rollback"), "policy row exists")
	_check(panel.press("test:editor:apply:rollback"), "rollback edit")
	await _frame()
	view = session.get_test_view()
	_check(view.pending_choice == null, "pending cleared by rollback")
	_check(panel.press("test:editor:close"), "close after rollback")
	await _frame()

	# Result page and continue.
	view = session.get_test_view()
	var won := session.set_test_outcome(_context(session), "won")
	_check(won.accepted, "manual outcome")
	shell.refresh()
	await _frame()
	_check(shell.page is TestRoomPage, "result page")
	if shell.page is TestRoomPage:
		_check(shell.press("test:result:continue"), "continue from result")
	await _frame()
	_check(shell.page is BattleScreen, "back to battle")

	# Snapshot round-trip.
	var snapshot := session.save_test_snapshot("e2e")
	_check(snapshot.ok, "snapshot saved")
	var snapshot_id := str(snapshot.data.id)
	session.close_test_room()
	shell.refresh()
	await _frame()
	var loaded := session.load_test_snapshot(snapshot_id)
	_check(loaded.accepted, "snapshot loaded: " + _error(loaded.error))
	shell.refresh()
	await _frame()
	_check(shell.page is BattleScreen, "snapshot opens the battle")
	session.close_test_room()
	shell.refresh()
	await _frame()
	_check(shell.press("menu:new"), "formal setup still reachable")
	_check(not FileAccess.file_exists(_root + "/saves/current_run.json"), "no formal current_run")
	shell.queue_free()
	return _failures


func _find(panel: TestEditorPanel, prefix: String) -> String:
	for uid in panel.button_uids():
		if str(uid).begins_with(prefix):
			return str(uid)
	return ""


func _context(session: GameSession) -> Dictionary:
	var view := session.get_test_view()
	var test_state: Dictionary = view.get("test", {})
	return {
		"test_id": str(test_state.get("test_id", "")),
		"branch_id": int(test_state.get("branch_id", 0)),
		"expected_revision": int(test_state.get("revision", 0)),
	}


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _error(error: ApiError) -> String:
	return "" if error == null else "%s/%s" % [error.code, error.message_key]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)



