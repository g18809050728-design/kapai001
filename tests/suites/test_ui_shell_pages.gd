extends RefCounted


class FixtureSession:
	extends GameSession

	func _is_manifest_allowed(id: String) -> bool:
		return id == "test_run_g4"

	func get_setup_options() -> GameResult:
		var options := SetupOptions.new()
		options.characters = [
			{"id": "test_P01", "locked": false, "starter_cards": []},
			{"id": "test_P04", "locked": false, "starter_cards": []},
		]
		options.difficulties = [&"normal"]
		options.manifests = [{"id": "test_run_g4"}]
		options.default_seed = "42"
		return GameResult.success(options)


var _failures: Array[String] = []
var _commands: Array[Dictionary] = []
var _root := ""


func run() -> Array[String]:
	_root = "user://g7-ui-shell-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	_check_production_start()
	_check_save_continue()
	_check_restart()
	var shell := start_fixture_shell(_root + "/semester")
	if shell.session.get_view().run_id != null:
		drive_semester(shell, true)
		var view := shell.session.get_view()
		_check(view.screen == &"summary", "six-node route reaches summary through buttons")
		_check(view.run.outcome == "won", "real BattleEngine boss win finishes semester")
		_check(view.run.node_path.size() == 6, "six route nodes finish exactly once")
		_check_terminal_restart(shell.session)
		_check(shell.press("summary:menu"), "summary returns to menu")
		_check(shell.press("menu:settings"), "terminal settings are reachable")
		_check(shell.press("settings:save"), "terminal save is a button operation")
		var profile := shell.session.get_profile()
		_check(profile.completed_run_ids == [str(view.run_id)], "terminal save merges one summary")
		_check(shell.press("settings:save"), "terminal repeated save is available")
		_check(
			shell.session.get_profile().completed_run_ids == profile.completed_run_ids,
			"repeated terminal save is idempotent"
		)
		_check(shell.press("settings:back"), "settings returns to menu")
		_check(shell.press("menu:continue"), "terminal session remains resumable")
		_check(shell.press("summary:retry"), "retry opens setup without releasing old session")
		_check(
			shell.session.get_view().run_id == view.run_id,
			"retry configuration retains completed session until confirmation"
		)
		_check(shell.page.button_uids().has("setup:start"), "retry opens real setup page")
		_check(shell.press("setup:start"), "retry asks for replacement confirmation")
		_check(shell.press("setup:restart_confirm"), "retry replaces completed session")
		_check(shell.session.get_view().run_id != view.run_id, "confirmed retry creates new run")
		_check(
			shell.session.get_profile().completed_run_ids == profile.completed_run_ids,
			"restart preserves permanent progress"
		)
	shell.free()
	print(
		"G7_UI_ROUTE_EVIDENCE=",
		SnapshotCodec.canonical_json(
			{
				"seed": "42",
				"route": ["normal", "event", "shop", "elite", "rest", "boss"],
				"button_commands": _commands,
				"failures": _failures
			}
		)
	)
	return _failures


func fixture_session(path: String) -> GameSession:
	return FixtureSession.new(SaveStore.new(path), Callable(self, "_factory"))


func attach_shell(session: GameSession) -> GameShell:
	var shell := GameShell.new()
	shell.session = session
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	return shell


func start_fixture_shell(path: String) -> GameShell:
	var shell := attach_shell(fixture_session(path))
	_check(not shell.press("menu:continue"), "new menu disables continue without saves")
	_check(shell.press("menu:settings"), "menu opens settings")
	_check(not shell.press("settings:save"), "no-session save is disabled")
	_check(not shell.press("settings:restore_backup"), "missing backup restore is disabled")
	_check(shell.press("settings:autosave:false"), "autosave uses local setting selection")
	_check(shell.press("settings:apply"), "settings save uses public session operation")
	_check(not shell.session.get_profile().autosave, "autosave false persists")
	_check(shell.session.get_view().revision == 0, "settings do not change domain revision")
	_check(shell.press("settings:back"), "settings returns to menu")
	_check(shell.press("menu:new"), "new-run button opens setup")
	_check(shell.press("setup:character:test_P01"), "setup character uses stable uid")
	_check(shell.press("setup:difficulty:normal"), "setup difficulty uses stable uid")
	_check(shell.press("setup:start"), "setup start emits real Button.pressed")
	_check(shell.session.get_view().screen == &"map", "UI start reaches map")
	return shell


func drive_semester(shell: GameShell, claim_first: bool = false) -> void:
	for layer in range(1, 7):
		var kind: String = ["normal", "event", "shop", "elite", "rest", "boss"][layer - 1]
		var node_id := ""
		for node in shell.session.get_view().run.nodes:
			if int(node.layer) == layer and str(node.kind) == kind:
				node_id = str(node.node_id)
		_check(not node_id.is_empty(), "route contains " + kind)
		assert_previews_unchanged(shell)
		if layer == 1:
			for node in shell.session.get_view().run.nodes:
				if int(node.layer) == 6:
					assert_disabled_unchanged(shell, "node:" + str(node.node_id))
		_check(shell.session.get_view().screen == &"map", "every next layer waits for a map click")
		if not press_rule(shell, "node:" + node_id):
			return
		_check(shell.session.get_view().run.current_node_id == node_id, "enters expected layer")
		if kind in ["normal", "elite", "boss"]:
			if not finish_battle(shell):
				return
			if kind == "boss":
				return
			_check(
				not shell.page.button_uids().has("reward:leave"), "reward has no continue button"
			)
			for index in range(8):
				if shell.session.get_view().screen != &"reward":
					break
				var offer: Dictionary = shell.session.get_view().run.pending_reward
				var item: Dictionary = {}
				for candidate in offer.items:
					if str(candidate.status) == "pending":
						item = candidate
						break
				if item.is_empty():
					_check(false, "reward screen contains a pending item")
					return
				var uid := "reward:" + str(item.item_id)
				var pending_count := 0
				for reward_item in offer.items:
					if str(reward_item.status) == "pending":
						pending_count += 1
				var automatic := 1 if pending_count == 1 else 0
				if claim_first and layer == 1 and index == 0:
					assert_disabled_unchanged(shell, uid + ":claim")
					var candidate: Variant = item.candidates[0]
					var id := (
						str(candidate.get("id", candidate.get("definition_id", "")))
						if candidate is Dictionary
						else str(candidate)
					)
					var before := fingerprint(shell.session)
					_check(
						shell.press(uid + ":pick:" + id), "reward candidate button is selectable"
					)
					_check(fingerprint(shell.session) == before, "reward selection is local only")
					if not press_rule(shell, uid + ":claim", automatic):
						return
				else:
					if not press_rule(shell, uid + ":skip", automatic):
						return
			_check(
				(
					str(
						(
							shell
							. session
							. get_view()
							. run
							. nodes
							. filter(func(node): return str(node.node_id) == node_id)[0]
							. status
						)
					)
					== "completed"
				),
				"rewards automatically complete the battle node"
			)
		elif kind == "event":
			_check(not shell.page.button_uids().has("event:leave"), "event has no continue button")
			if not press_rule(shell, "event:option:leave", 1):
				return
			_check(
				shell.session.get_view().screen == &"map",
				"event returns to map before the sole shop"
			)
		elif kind == "shop":
			var stocks: Array = shell.session.get_view().run.shop.stocks
			_check(not stocks.is_empty(), "shop exposes real stock")
			if stocks.is_empty():
				return
			var uid := "shop:buy:" + str(stocks[0].stock_id)
			if not press_rule(shell, uid):
				return
			_check(shell.session.get_view().screen == &"shop", "purchase keeps shop open")
			assert_disabled_unchanged(shell, uid)
			if not press_rule(shell, "shop:leave"):
				return
		elif kind == "rest":
			_check(not shell.page.button_uids().has("rest:leave"), "rest has no continue button")
			_check(shell.press("rest:option:upgrade"), "rest opens upgrade comparison")
			var card_id: String = shell.session.get_view().run.cards[0].card_id
			var uid := "rest:take:upgrade:" + card_id
			if not press_rule(shell, uid, 1):
				return
			_check(
				shell.session.get_view().screen == &"map",
				"rest returns to map before the sole boss"
			)
	_check(false, "route must terminate at boss summary")


func finish_battle(shell: GameShell) -> bool:
	for step in range(24):
		var view := shell.session.get_view()
		if view.screen != &"battle":
			return true
		assert_previews_unchanged(shell)
		var card_id := ""
		for card in view.battle.hand:
			if str(card.definition_id) == "test_K01":
				card_id = str(card.card_id)
				break
		if card_id.is_empty():
			if not press_rule(shell, "battle:end_turn"):
				return false
			continue
		var before := fingerprint(shell.session)
		_check(shell.press("card:" + card_id), "battle hand card button is enabled")
		_check(
			fingerprint(shell.session) == before, "targeted card preselection does not change rules"
		)
		if not press_rule(shell, "task:" + str(view.battle.tasks[0].task_id)):
			return false
	_check(false, "battle did not complete within fixture command bound")
	return false


func press_rule(shell: GameShell, uid: String, automatic_commands: int = 0) -> bool:
	var revision := shell.session.get_view().revision
	var draft := shell.page.action_draft(uid)
	var pressed := shell.press(uid)
	var accepted := (
		pressed and shell.session.get_view().revision == revision + 1 + automatic_commands
	)
	_check(accepted, "button and automatic commands each increment revision once: " + uid)
	if not accepted:
		print(
			"G7_UI_COMMAND_ERROR=",
			uid,
			" ",
			(
				shell.last_error.to_dictionary()
				if shell.last_error != null
				else shell.page.button_reason(uid)
			)
		)
	_commands.append(
		{
			"uid": uid,
			"draft": draft,
			"automatic_commands": automatic_commands,
			"revision": shell.session.get_view().revision
		}
	)
	return accepted


func assert_previews_unchanged(shell: GameShell) -> void:
	var before := fingerprint(shell.session)
	for uid in shell.page.action_uids():
		var draft := shell.page.action_draft(uid)
		var preview := shell.session.preview_action(
			ActionDraft.new(StringName(str(draft.type)), draft.get("payload", {}))
		)
		if preview.ok:
			_check(
				preview.data.revision == shell.session.get_view().revision,
				"preview quotes current revision: " + str(uid)
			)
		_check(
			fingerprint(shell.session) == before,
			"preview preserves complete state and RNG: " + str(uid)
		)


func assert_disabled_unchanged(shell: GameShell, uid: String) -> void:
	var before := fingerprint(shell.session)
	_check(shell.page.button_uids().has(uid), "disabled control exists: " + uid)
	_check(shell.page.button_disabled(uid), "control disabled: " + uid)
	_check(not shell.page.button_reason(uid).is_empty(), "disabled control has reason: " + uid)
	_check(not shell.press(uid), "disabled button emits no action: " + uid)
	_check(
		fingerprint(shell.session) == before, "disabled button preserves state/RNG/revision: " + uid
	)


func fingerprint(session: GameSession) -> String:
	if session._state == null:
		return "no-session"
	var state: SessionState = session._state
	var choice: Variant = null
	if state.pending_choice != null:
		var options: Array = []
		for candidate in state.pending_choice.candidates:
			options.append(
				{"id": candidate.id, "label_key": candidate.label_key, "preview": candidate.preview}
			)
		choice = {
			"choice_id": state.pending_choice.choice_id,
			"kind": str(state.pending_choice.kind),
			"candidates": options,
			"min_count": state.pending_choice.min_count,
			"max_count": state.pending_choice.max_count
		}
	return SnapshotCodec.canonical_json(
		{
			"revision": state.revision,
			"run": state.run.to_dictionary(),
			"battle": state.battle.to_dictionary() if state.battle != null else null,
			"random": state.random_snapshot,
			"pending_choice": choice,
			"terminal_summary":
			state.terminal_summary.to_dictionary() if state.terminal_summary != null else null,
			"profile_merge_pending": state.profile_merge_pending,
			"event_log": state.event_log
		}
	)


func _check_production_start() -> void:
	var session := GameSession.new(SaveStore.new(_root + "/production"))
	var shell := attach_shell(session)
	_check(shell.press("menu:new"), "production menu opens setup")
	_check(shell.page.button_uids().has("setup:character:P01"), "production setup exposes P01")
	_check(
		not shell.page.button_uids().has("setup:character:test_P01"),
		"production setup excludes fixtures"
	)
	_check(shell.press("setup:character:P01"), "production character button works")
	var input := _line_edit(shell.page)
	_check(input != null, "setup exposes editable seed")
	if input != null:
		input.text = "42"
		input.text_changed.emit("42")
	_check(shell.press("setup:start"), "production setup starts through shell")
	var view := session.get_view()
	_check(view.screen == &"map", "production start reaches map")
	if view.run is Dictionary:
		_check(
			view.run.manifest_id == "campus_mvp" and view.run.character_id == "P01",
			"production start uses approved manifest and character"
		)
		for card in view.run.cards:
			_check(
				not str(card.definition_id).begins_with("test_"),
				"production deck excludes fixture definitions"
			)
	shell.free()


func _check_save_continue() -> void:
	var path := _root + "/continue"
	var shell := start_fixture_shell(path)
	if shell.session.get_view().run_id == null:
		shell.free()
		return
	var before := fingerprint(shell.session)
	_check(shell.press("map:save"), "map save button writes stable snapshot")
	var stored := SaveStore.new(path).load("current_run")
	_check(stored.ok, "manual UI save writes current_run")
	_check(fingerprint(shell.session) == before, "manual save preserves rule state and RNG")
	var id: String = shell.session.get_view().run.reachable_node_ids[0]
	press_rule(shell, "node:" + id)
	var live := fingerprint(shell.session)
	_check(shell.press("battle:menu"), "battle menu keeps in-memory session")
	_check(shell.press("menu:new"), "active session can configure a new run")
	_check(fingerprint(shell.session) == live, "opening setup preserves old battle")
	_check(shell.press("setup:back"), "setup can return without starting a run")
	_check(shell.press("menu:continue"), "continue prefers active in-memory session")
	_check(fingerprint(shell.session) == live, "menu continue preserves unsaved current battle")
	shell.free()
	var restored := attach_shell(fixture_session(path))
	_check(restored.press("menu:continue"), "fresh shell continues through real menu button")
	_check(
		fingerprint(restored.session) == before,
		"disk continue restores complete saved state and RNG"
	)
	_check(
		restored.session.get_view().screen == &"map",
		"autosave-off continue restores last explicit boundary"
	)
	restored.free()


func _check_restart() -> void:
	var path := _root + "/restart"
	var shell := start_fixture_shell(path)
	var session := shell.session
	var request := StartRunRequest.new("test_P01", &"normal", "test_run_g4", "43")
	_check(shell.press("map:save"), "save old run before replacement failure tests")
	var saved := SaveStore.new(path).load("current_run")
	var old_id: String = session.get_view().run_id
	var node_id: String = session.get_view().run.reachable_node_ids[0]
	press_rule(shell, "node:" + node_id)
	var before := fingerprint(session)
	_check(not session.restart_run(request).accepted, "restart requires explicit confirmation")
	_check(
		not (
			session
			. restart_run(
				StartRunRequest.new("test_P01", &"normal", "test_run_g4", "invalid"), true
			)
			. accepted
		),
		"invalid replacement seed is rejected"
	)
	session._store.debug_hooks = {"current_run": {"fail_write": true}}
	_check(not session.restart_run(request, true).accepted, "replacement write failure is rejected")
	_check(fingerprint(session) == before, "failed replacements preserve old battle and RNG")
	_check(
		SaveStore.new(path).load("current_run").data == saved.data,
		"failed replacements preserve old disk snapshot"
	)
	session._store.debug_hooks = {}
	_check(shell.press("battle:menu") and shell.press("menu:new"), "battle can open new setup")
	_check(shell.press("setup:start"), "active run asks for confirmation")
	_check(fingerprint(session) == before, "requesting confirmation preserves old run")
	_check(shell.press("setup:restart_cancel"), "replacement can be cancelled")
	_check(fingerprint(session) == before, "cancel preserves old battle and RNG")
	_check(shell.press("setup:start") and shell.press("setup:restart_confirm"), "restart midbattle")
	_check(session.get_view().run_id != old_id, "restart creates a distinct run id")
	_check(
		session.get_view().revision == 0 and session.get_view().screen == &"map", "restart is fresh"
	)
	var replacement := fingerprint(session)
	shell.free()
	var fresh := attach_shell(fixture_session(path))
	_check(fresh.press("menu:continue"), "restart is durable even with autosave disabled")
	_check(
		fingerprint(fresh.session) == replacement, "relaunch restores replacement, not old battle"
	)
	fresh.free()
	var disk := attach_shell(fixture_session(path))
	_check(
		disk.press("menu:new") and disk.press("setup:start"), "disk run permits new configuration"
	)
	_check(
		disk.press("setup:restart_confirm"), "disk active save can be replaced without restoring"
	)
	_check(disk.session.get_view().run_id != old_id, "disk replacement starts a new run")
	disk.free()


func _check_terminal_restart(source: GameSession) -> void:
	var path := _root + "/terminal_restart"
	var snapshot := SnapshotCodec.encode_session(source._state, source._catalog.get_info())
	_check(
		snapshot.ok and SaveStore.new(path).save("current_run", snapshot.data).ok,
		"persist terminal marker before a simulated relaunch"
	)
	var session := fixture_session(path)
	var request := StartRunRequest.new("test_P01", &"normal", "test_run_g4", "44")
	session._store.debug_hooks = {"profile": {"fail_write": true}}
	_check(
		not session.restart_run(request, true).accepted,
		"profile merge failure prevents losing terminal summary on restart"
	)
	_check(
		SaveStore.new(path).load("current_run").data == snapshot.data,
		"failed terminal restart retains pending summary on disk"
	)
	session._store.debug_hooks = {}
	_check(
		session.restart_run(request, true).accepted, "restart retries pending disk summary merge"
	)
	_check(
		session.get_profile().completed_run_ids == [str(source.get_view().run_id)],
		"replacement merges exactly one old terminal summary"
	)
	session.free()


func _line_edit(node: Node) -> LineEdit:
	if node is LineEdit:
		return node
	for child in node.get_children():
		var found := _line_edit(child)
		if found != null:
			return found
	return null


func _factory() -> ContentDB:
	return ContentDB.new("res://tests/fixtures/run_flow", true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("G7 shell: " + message)
