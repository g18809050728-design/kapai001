extends RefCounted

var _failures: Array[String] = []
var _root: String = ""
var _helpers = preload("res://tests/suites/test_ui_shell_pages.gd").new()


func run() -> Array[String]:
	_root = "user://g7-ui-battle-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var animated := _helpers.attach_shell(GameSession.new(SaveStore.new(_root))) as GameShell
	_check(
		animated.session.update_settings({"autosave": false}).ok,
		"disable autosave for isolated A/B"
	)
	animated.press("menu:new")
	var input := _find_input(animated.page)
	if input != null:
		input.text = "0"
		input.text_changed.emit("0")
	_check(animated.press("setup:start"), "production starts through real setup")
	var initial := animated.session.get_view()
	if initial.run_id == null:
		_check(false, "production session exists")
		animated.free()
		return _failures
	_check(
		animated.press("node:" + str(initial.run.reachable_node_ids[0])),
		"production enters battle through map"
	)
	_check(animated.press("battle:save"), "save common A/B starting boundary")
	var instant := _helpers.attach_shell(GameSession.new(SaveStore.new(_root))) as GameShell
	_check(instant.press("menu:continue"), "second shell restores same starting snapshot")
	_check(
		_fingerprint(animated) == _fingerprint(instant),
		"A/B starts with identical complete state and RNG"
	)
	_check(instant.press("battle:animation"), "animation can be disabled through real button")
	_check(not (instant.page as BattleScreen).animation_enabled, "instant branch animation is off")
	for candidate_shell in [animated, instant]:
		var shell: GameShell = candidate_shell
		_check_local_actions(shell)
		_check_pending_choice(shell)
		_check(shell.press("battle:end_turn"), "end turn completes through preview gate")
		_check(shell.last_error == null, "end turn accepted")
		var before := _fingerprint(shell)
		var battle := shell.page as BattleScreen
		var view := shell.session.get_view()
		var seen: int = battle.display_snapshot().seen_events.size()
		battle.consume_events(view.event_log, str(view.run_id), view.revision)
		var after_first: int = battle.display_snapshot().seen_events.size()
		battle.consume_events(view.event_log, str(view.run_id), view.revision)
		_check(
			battle.display_snapshot().seen_events.size() == after_first and after_first >= seen,
			"duplicate event batch is not replayed"
		)
		battle._animator.advance(100.0)
		_check(_fingerprint(shell) == before, "event playback never changes domain state or RNG")
	_check(
		_fingerprint(animated) == _fingerprint(instant),
		"animation on/off produces identical complete rule state and RNG"
	)
	print(
		"G7_UI_ANIMATION_AB=",
		SnapshotCodec.canonical_json(
			{
				"seed": "0",
				"revision": animated.session.get_view().revision,
				"identical_state_rng": _fingerprint(animated) == _fingerprint(instant),
				"pending_choice_test": "production K03 via real buttons"
			}
		)
	)
	animated.free()
	instant.free()
	_check_restart_pending()
	return _failures


func _check_restart_pending() -> void:
	var path := _root + "/restart"
	var shell := _helpers.attach_shell(GameSession.new(SaveStore.new(path))) as GameShell
	_check(shell.session.update_settings({"autosave": false}).ok, "isolate pending restart save")
	shell.press("menu:new")
	var input := _find_input(shell.page)
	input.text = "0"
	input.text_changed.emit("0")
	_check(shell.press("setup:start"), "start independent production run for pending restart")
	var initial := shell.session.get_view()
	if initial.run_id == null:
		_check(false, "pending restart production session exists")
		shell.free()
		return
	_check(
		shell.press("node:" + str(initial.run.reachable_node_ids[0])),
		"enter independent battle for pending restart"
	)
	var card_id := _card_id(shell, "K03")
	_check(
		not card_id.is_empty() and shell.press("card:" + card_id),
		"open genuine choice before restart"
	)
	if shell.session.get_view().pending_choice == null:
		_check(false, "pending restart begins with genuine choice")
		shell.free()
		return
	var old_id: String = shell.session.get_view().run_id
	var pending := _fingerprint(shell)
	_check(shell.press("choice:new_run"), "pending modal can open new-run setup")
	_check(shell.press("setup:start"), "pending restart requires confirmation")
	_check(_fingerprint(shell) == pending, "confirmation preserves pending workspace")
	_check(
		shell.press("setup:restart_cancel") and shell.press("setup:back"), "cancel pending restart"
	)
	_check(shell.press("menu:continue"), "return to original pending choice")
	_check(_fingerprint(shell) == pending, "return preserves complete pending state and RNG")
	_check(shell.press("choice:new_run") and shell.press("setup:start"), "reopen pending restart")
	_check(shell.press("setup:restart_confirm"), "confirm restart while choice is pending")
	var current := shell.session.get_view()
	_check(current.run_id != old_id and current.revision == 0, "pending restart creates fresh run")
	_check(current.pending_choice == null and current.battle == null, "old workspace is discarded")
	var saved := SaveStore.new(path).load("current_run")
	_check(saved.ok and str(saved.data.run_id) == str(current.run_id), "replacement is saved")
	shell.free()


func _check_local_actions(shell: GameShell) -> void:
	var battle := shell.page as BattleScreen
	_check(battle != null, "real shell routes to BattleScreen")
	if battle == null:
		return
	var before := _fingerprint(shell)
	_check(battle.draw_pile_card_ids().is_empty(), "draw pile reveals no hidden card identities")
	for uid in [
		"battle:draw",
		"battle:discard",
		"battle:exhaust",
		"battle:rules",
		"battle:close_panel",
		"battle:speed"
	]:
		_check(shell.press(uid), "local control is reachable: " + uid)
		_check(
			_fingerprint(shell) == before, "local control preserves complete state and RNG: " + uid
		)
	var card_id := _card_id(shell, "K14")
	_check(
		not card_id.is_empty() and shell.press("card:" + card_id),
		"targeted card can be preselected"
	)
	_check(_fingerprint(shell) == before, "preselection preserves complete state and RNG")
	_check(shell.press("battle:cancel"), "cancel clears actual preselection")
	_check(
		(shell.page as BattleScreen).selection_snapshot().card_id == "",
		"cancel clears local card selection"
	)
	_check(_fingerprint(shell) == before, "cancel preserves complete state and RNG")
	for draft in [
		{"type": "end_turn", "payload": {"retained_card_ids": []}},
		{
			"type": "set_ally_target",
			"payload": {"unit_instance_id": "missing", "task_instance_id": "missing"}
		}
	]:
		shell.session.preview_action(ActionDraft.new(StringName(draft.type), draft.payload))
		_check(
			_fingerprint(shell) == before,
			"non-card preview preserves state/RNG/revision: " + str(draft.type)
		)


func _check_pending_choice(shell: GameShell) -> void:
	var card_id := _card_id(shell, "K03")
	var revision := shell.session.get_view().revision
	_check(
		not card_id.is_empty() and shell.press("card:" + card_id),
		"production K03 submitted through button"
	)
	var pending := shell.session.get_view()
	_check(
		pending.revision == revision + 1 and pending.pending_choice != null,
		"K03 publishes genuine pending choice"
	)
	if pending.pending_choice == null:
		return
	var battle := shell.page as BattleScreen
	_check(battle.is_locked(), "pending choice reports locked")
	var before := _fingerprint(shell)
	for uid in battle.button_uids():
		if str(uid).begins_with("choice:") and uid != "choice:confirm":
			continue
		_check(battle.button_disabled(uid), "pending locks actual button: " + str(uid))
		_check(not shell.press(uid), "locked button emits no action: " + str(uid))
	_check(_fingerprint(shell) == before, "locked controls preserve state/RNG/revision")
	var saved := shell.session.save_current()
	_check(
		not saved.ok and saved.error.code == &"CHOICE_PENDING",
		"public save rejects pending half-effect"
	)
	var candidate_id := pending.pending_choice.candidates[0].id
	_check(shell.press("choice:" + candidate_id), "choice candidate selectable through button")
	_check(_fingerprint(shell) == before, "choice candidate selection remains local")
	_check(shell.press("choice:confirm"), "choice confirms through shell and session")
	_check(
		shell.session.get_view().pending_choice == null, "choice queue resolves to stable boundary"
	)
	_check(
		shell.session.get_view().revision == revision + 2,
		"choice confirmation increments revision exactly once"
	)
	_check(
		not (shell.page as BattleScreen).is_locked(), "controls unlock after accepted confirmation"
	)
	_check(shell.press("battle:save"), "save control unlocks at stable boundary")


func _fingerprint(shell: GameShell) -> String:
	return _helpers.fingerprint(shell.session)


func _card_id(shell: GameShell, definition_id: String) -> String:
	for card in shell.session.get_view().battle.hand:
		if str(card.definition_id) == definition_id:
			return str(card.card_id)
	return ""


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
		_failures.append(message)
