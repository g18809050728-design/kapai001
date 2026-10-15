extends RefCounted

var _failures: Array[String] = []
var _phases: Array[String] = []
var _restores: Array[String] = []


func run() -> Array[String]:
	var root := "user://g7-production-boss-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var store := SaveStore.new(root)
	var session := GameSession.new(store)
	_check(session.update_settings({"autosave": false}).ok, "isolated boss save settings")
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	_check(started.accepted, "production session starts")
	if not started.accepted:
		session.free()
		return _failures
	# A valid controlled pre-boss fixture isolates phase progression from route balance.
	# All content, costs, intents, transitions and subsequent commands remain production code.
	var run := session._state.run
	for card in run.cards:
		card.definition_id = "K01"
	for layer in range(1, 6):
		for node in run.nodes:
			if node.layer != layer or node.kind not in ["normal", "shop", "rest"]:
				continue
			node.status = "completed"
			if node.kind == "normal":
				node.context = {"encounter_id": "N01", "settled": true}
				run.settled_battle_ids.append(node.node_id)
			elif node.kind == "shop":
				node.context = {
					"shop":
					ShopState.create({"shop_id": node.node_id + "|shop", "node_id": node.node_id})
				}
			elif node.kind == "rest":
				node.context = {"used": true, "option_id": "heal"}
			run.node_path.append(node.node_id)
			run.current_node_id = node.node_id
			break
	_check(run.validate(6).is_empty(), "controlled pre-boss run is valid")
	var boss_id: String = run.reachable_node_ids()[0]
	_check(
		_submit(session, &"enter_node", {"node_id": boss_id}).accepted,
		"public enter production boss"
	)
	var commands := 0
	while session.get_view().battle != null and commands < 60:
		var view := session.get_view()
		var task: Dictionary = view.battle.tasks[0]
		var phase := str(task.phase_key)
		if _phases.is_empty() or _phases.back() != phase:
			_phases.append(phase)
			_check(int(task.phase_index) == _phases.size(), "phase ordinal matches real definition")
			_check(int(task.phase_count) == 3, "view exposes all three boss phases")
			var page := BattleScreen.new()
			(Engine.get_main_loop() as SceneTree).root.add_child(page)
			page.render(view.battle)
			_check(
				_contains_text(page, "第 %s / 3 阶段" % task.phase_index),
				"battlefield visibly shows phase count"
			)
			_check(
				_contains_text(page, "最终阶段" if int(task.phase_index) == 3 else "完成后进入下一阶段"),
				"battlefield explains phase transition"
			)
			page.free()
			var before := SnapshotCodec.encode_session(session._state, session._catalog.get_info())
			_check(before.ok, "phase " + phase + " snapshot encodes")
			if not before.ok:
				print("G7_BOSS_SNAPSHOT_ERROR=", before.error.to_dictionary())
			var saved := session.save_and_exit()
			_check(saved.ok, "phase " + phase + " saves")
			if not saved.ok:
				print("G7_BOSS_SAVE_ERROR=", saved.error.to_dictionary())
				break
			session.free()
			session = GameSession.new(store)
			var restored := session.continue_run()
			_check(restored.ok, "phase " + phase + " restores")
			if not restored.ok:
				print("G7_BOSS_RESTORE_ERROR=", restored.error.to_dictionary())
				break
			var after := SnapshotCodec.encode_session(session._state, session._catalog.get_info())
			_check(after.ok and before.data == after.data, "phase save preserves all state and RNG")
			_restores.append(phase)
			view = session.get_view()
			task = view.battle.tasks[0]
			_check(str(task.phase_key) == phase, "restoring never resets boss phase")
		var action: ActionResult
		if int(view.battle.player.focus) >= 1 and not view.battle.hand.is_empty():
			action = _submit(
				session,
				&"play_card",
				{"card_instance_id": view.battle.hand[0].card_id, "target_ids": [task.task_id]}
			)
		else:
			action = _submit(session, &"end_turn", {})
		_check(action.accepted, "production boss command is accepted")
		if not action.accepted:
			print("G7_BOSS_ACTION_ERROR=", action.error.to_dictionary())
			break
		commands += 1
	var final := session.get_view()
	_check(_phases == ["limits", "integrals", "proofs"], "boss visits each phase exactly once")
	_check(_restores == _phases, "every phase survives real disk restoration")
	_check(
		final.battle == null and final.screen == &"summary",
		"final phase ends battle and opens summary"
	)
	_check(final.run.outcome == "won", "production B01 can be defeated")
	var finished := final.event_log.filter(func(event): return event.type == "run_finished")
	_check(finished.size() == 1, "boss emits exactly one terminal run event")
	_check(session.save_current().ok and session.save_current().ok, "terminal save retries succeed")
	_check(
		session.get_profile().completed_run_ids == [str(final.run_id)],
		"terminal retries merge one summary"
	)
	var repeated := _submit(session, &"enter_node", {"node_id": boss_id})
	_check(not repeated.accepted, "completed boss cannot restart")
	print(
		"G7_PRODUCTION_BOSS_EVIDENCE=",
		SnapshotCodec.canonical_json(
			{
				"seed": "42",
				"manifest": "campus_mvp",
				"fixture": "valid pre-boss run; twelve production K01 cards",
				"phases": _phases,
				"restored_phases": _restores,
				"commands": commands,
				"outcome": final.run.outcome,
				"terminal_events": finished.size(),
				"failures": _failures
			}
		)
	)
	session.free()
	return _failures


func _submit(session: GameSession, type: StringName, payload: Dictionary) -> ActionResult:
	var view := session.get_view()
	return session.submit(
		CommandContext.new(str(view.run_id), view.revision), GameAction.new(type, payload)
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append("production boss: " + label)


func _contains_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text:
		return true
	for child in node.get_children():
		if _contains_text(child, fragment):
			return true
	return false
