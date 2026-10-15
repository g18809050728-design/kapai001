extends RefCounted

var _failures: Array[String] = []
var _catalog: ContentDB
var _service: RunService
var _state: RunState
var _rng: Dictionary
var _commands: Array[Dictionary] = []
var _route_evidence: Array[Dictionary] = []


func run() -> Array[String]:
	_catalog = ContentDB.new("res://tests/fixtures/run_flow", true)
	var loaded := _catalog.load("test_run_g4")
	_check(loaded.ok, "isolated test_run_g4 loads")
	if not loaded.ok:
		print("G4_FIXTURE_ERROR=", loaded.error.to_dictionary())
		return _failures
	_service = RunService.new(_catalog)
	for branch in [
		["event", "elite"], ["normal", "normal"], ["event", "normal"], ["normal", "elite"]
	]:
		_route(branch, "test_P01" if branch[1] == "elite" else "test_P04")
	_session_cases()
	print("G4_RUN_COMMANDS=", JSON.stringify(_commands))
	print("G4_ROUTE_EVIDENCE=", JSON.stringify(_route_evidence))
	print("G4_RUN_001=", "passed" if _failures.is_empty() else "failed")
	return _failures


func _route(branch: Array, character_id: String) -> void:
	var request := {
		"character_id": character_id,
		"manifest_id": "test_run_g4",
		"difficulty": "normal",
		"seed": "42"
	}
	var created := _service.create(request, {"unlocked_ids": []})
	_check(created.ok, "create complete semester fixture")
	if not created.ok:
		print("G4_CREATE_ERROR=", created.error.to_dictionary())
		return
	_state = created.data.state
	_rng = created.data.rng_states
	var evidence := {
		"request": request,
		"branch": branch,
		"initial_state": _state.to_dictionary(),
		"initial_rng": _rng.duplicate(true),
		"first_command": _commands.size()
	}
	_commands.append({"create": request, "branch": branch})
	_check(_state.nodes.size() == 8 and _state.cards.size() == 12, "frozen map and starter deck")
	var copy := _state.copy_for_write()
	copy.nodes[0].context["isolation"] = {"nested": [1]}
	copy.cards[0]["upgrade_level"] = 1
	_check(
		not _state.nodes[0].context.has("isolation") and _state.cards[0].upgrade_level == 0,
		"run deep-copy isolation"
	)
	var boss_id := _node_id(6, "boss")
	_rejected(&"enter_node", {"node_id": boss_id}, &"INVALID_TARGET")
	var route := ["normal", branch[0], "shop", branch[1], "rest", "boss"]
	for layer in range(1, 7):
		var kind: String = route[layer - 1]
		var node_id := _node_id(layer, kind)
		var entered := _apply(&"enter_node", {"node_id": node_id})
		if not entered.ok:
			return
		var node: RunNodeState = _state.find_node(node_id)
		if kind in ["normal", "elite", "boss"]:
			if not _fight(entered.data):
				return
			if _state.outcome != "":
				_check(layer == 6 and _state.outcome == "won", "only final boss completes MVP")
				_check(_state.pending_reward == null, "terminal boss has no post-terminal reward")
				_check(
					_state.settlement == null and _state.term == 1, "MVP has no next-term recovery"
				)
				_check(_service.make_view(_state).screen == "summary", "terminal screen is summary")
				_rejected(&"abandon_run", {"confirmed": true}, &"WRONG_PHASE")
				continue
			_rejected(&"leave_node", {"node_id": node_id}, &"CHOICE_PENDING")
			if not _collect_rewards():
				return
		elif kind == "event":
			var event: EventState = node.context.event
			var frozen: Dictionary = event.frozen_candidates.duplicate(true)
			var before := _state.to_dictionary()
			var preview := _service.preview(
				_state,
				ActionDraft.new(
					&"choose_event",
					{
						"event_instance_id": event.event_instance_id,
						"option_id": "leave",
						"selection_ids": []
					}
				)
			)
			_check(preview.ok and preview.data.can_submit, "event leave preview")
			_check(
				_state.to_dictionary() == before and node.context.event.frozen_candidates == frozen,
				"preview does not reroll frozen candidates"
			)
			var payload := {
				"event_instance_id": event.event_instance_id,
				"option_id": "leave",
				"selection_ids": []
			}
			if not _apply(&"choose_event", payload).ok:
				return
			_rejected(&"choose_event", payload, &"ALREADY_RESOLVED")
		elif kind == "shop":
			var shop: ShopState = node.context.shop
			var stock: Dictionary = shop.stocks[0]
			var payload := {"shop_id": shop.shop_id, "stock_id": stock.stock_id}
			var poor := _state.copy_for_write()
			poor.money = 0
			var poor_before := poor.to_dictionary()
			var poor_rng := _rng.duplicate(true)
			var cannot := _service.apply(poor, GameAction.new(&"buy_item", payload), _rng)
			_check(
				not cannot.ok and cannot.error.code == &"INSUFFICIENT_RESOURCE",
				"insufficient shopping money rejected"
			)
			_check(
				poor.to_dictionary() == poor_before and _rng == poor_rng,
				"rejected transaction leaves state and RNG intact"
			)
			if not _apply(&"buy_item", payload).ok:
				return
			_rejected(&"buy_item", payload, &"ALREADY_RESOLVED")
			var remove := {"shop_id": shop.shop_id, "card_instance_id": _state.cards[0].card_id}
			if not _apply(&"remove_card", remove).ok:
				return
			remove.card_instance_id = _state.cards[0].card_id
			_rejected(&"remove_card", remove, &"LIMIT_REACHED")
		elif kind == "rest":
			var preview := _service.preview(
				_state, ActionDraft.new(&"take_rest", {"node_id": node_id, "option_id": "upgrade"})
			)
			_check(
				(
					preview.ok
					and not preview.data.can_submit
					and preview.data.required_selections.size() == 1
				),
				"rest preview exposes missing card selection"
			)
			var payload := {
				"node_id": node_id,
				"option_id": "upgrade",
				"card_instance_id": _state.cards[0].card_id
			}
			if not _apply(&"take_rest", payload).ok:
				return
			_check(_state.cards[0].upgrade_level == 1, "rest upgrades permanent card")
			_rejected(&"take_rest", payload, &"ALREADY_RESOLVED")
		if not _apply(&"leave_node", {"node_id": node_id}).ok:
			return
		_rejected(&"enter_node", {"node_id": node_id}, &"ALREADY_RESOLVED")
	_check(_state.node_path.size() == 6, "RUN-001 completes six-node route")
	evidence.final_state = _state.to_dictionary()
	evidence.final_rng = _rng.duplicate(true)
	evidence.last_command = _commands.size() - 1
	_route_evidence.append(evidence)


func _fight(entered: RunStep) -> bool:
	var before_rng := _rng.duplicate(true)
	var denied := _service.apply(_state, GameAction.new(&"abandon_run", {"confirmed": true}), _rng)
	_check(
		not denied.ok and denied.error.code == &"WRONG_PHASE",
		"run writes blocked while battle is active"
	)
	var engine := BattleEngine.new(_catalog)
	var begun := engine.begin(entered.battle_input)
	_check(begun.ok, "real BattleEngine begins from RunStep input")
	if not begun.ok:
		print("G4_BATTLE_BEGIN_ERROR=", begun.error.to_dictionary())
		return false
	var battle: BattleState = begun.data.state
	var action := ActionDraft.new(
		&"play_card",
		{"card_instance_id": battle.zones.hand[0], "target_ids": [battle.tasks[0].task_id]}
	)
	var played := engine.apply(battle, action, begun.data.rng_state)
	_check(played.ok and played.data.outcome != null, "real battle command reaches fixture victory")
	if not played.ok or played.data.outcome == null:
		return false
	var snapshot: Dictionary = played.data.rng_state
	var money := _state.money
	var settled := _service.settle_battle(_state, played.data.outcome, snapshot)
	_check(settled.ok, "battle outcome settles once")
	if not settled.ok:
		print("G4_SETTLE_ERROR=", settled.error.to_dictionary())
		return false
	var prior := _state.to_dictionary()
	_state = settled.data.state
	_rng = settled.data.rng_states
	_check(
		_rng.streams.battle == snapshot.streams.battle, "RunService never advances battle stream"
	)
	_check(
		prior.active_battle_id != "" and _state.active_battle_id == "",
		"settlement consumes active battle"
	)
	_check(before_rng.streams.map == snapshot.streams.map, "BattleEngine leaves map stream intact")
	var duplicate := _service.settle_battle(_state, played.data.outcome, _rng)
	_check(
		not duplicate.ok and duplicate.error.code == &"ALREADY_RESOLVED",
		"duplicate battle settlement rejected"
	)
	if _state.outcome != "":
		_check(
			settled.data.run_summary != null and settled.data.run_summary.result == "won",
			"final settlement creates immutable summary"
		)
		_check(_state.money == money, "terminal boss grants no living allowance")
	_commands.append(
		{
			"battle_id": played.data.outcome.battle_id,
			"type": String(action.type),
			"payload": action.payload.duplicate(true),
			"result": played.data.outcome.result
		}
	)
	return true


func _collect_rewards() -> bool:
	var offer: RewardOffer = _state.pending_reward
	if offer == null:
		_check(false, "nonterminal victory freezes reward offer")
		return false
	var items: Array[Dictionary] = offer.items.duplicate(true)
	for index in items.size():
		var item: Dictionary = items[index]
		var payload := {"offer_id": offer.offer_id, "item_id": item.item_id}
		var type: StringName = &"claim_reward" if index == 0 else &"skip_reward"
		if type == &"claim_reward":
			var candidate: Variant = item.candidates[0]
			payload["candidate_id"] = (
				candidate.get(
					"candidate_id", candidate.get("id", candidate.get("definition_id", ""))
				)
				if candidate is Dictionary
				else candidate
			)
		if not _apply(type, payload).ok:
			return false
		_rejected(type, payload, &"ALREADY_RESOLVED")
	return true


func _session_cases() -> void:
	var session := GameSession.new(
		SaveStore.new("user://g4-session-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()])
	)
	var setup := session.get_setup_options()
	_check(setup.ok and setup.data.characters.size() == 2, "session exposes production setup")
	var forbidden := session.start_run(
		StartRunRequest.new("test_P01", &"normal", "test_run_g4", "42")
	)
	_check(not forbidden.accepted, "player entry excludes test manifests")
	var started := session.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	_check(started.accepted and started.revision == 0, "session creates run at revision zero")
	if not started.accepted:
		print("G4_SESSION_START_ERROR=", started.error.to_dictionary())
		session.free()
		return
	var view := session.get_view()
	var original_run: Dictionary = view.run.duplicate(true)
	view.run.cards.clear()
	_check(session.get_view().run == original_run, "session run view cannot mutate internal state")
	var context := CommandContext.new(view.run_id, 0)
	var node_id: String = original_run.reachable_node_ids[0]
	var draft := ActionDraft.new(&"enter_node", {"node_id": node_id})
	var malformed := session.preview_action(
		ActionDraft.new(&"enter_node", {"node_id": node_id, "price": 0})
	)
	_check(
		not malformed.ok and malformed.error.code == &"INVALID_ARGUMENT",
		"unknown preview payload key rejected"
	)
	var preview := session.preview_action(draft)
	_check(preview.ok and preview.data.revision == 0, "session binds preview revision")
	var entered := session.submit(context, GameAction.new(&"enter_node", {"node_id": node_id}))
	_check(
		entered.accepted and entered.revision == 1 and entered.view.battle != null,
		"session atomically starts real production battle"
	)
	var stale := session.submit(context, GameAction.new(&"enter_node", {"node_id": node_id}))
	_check(
		not stale.accepted and stale.error.code == &"STALE_STATE" and stale.revision == 1,
		"stale command cannot replay accepted action"
	)
	if entered.accepted:
		var before := session.get_view().to_dictionary()
		var invalid := session.submit(
			CommandContext.new(view.run_id, 1),
			GameAction.new(&"play_card", {"card_instance_id": "missing", "target_ids": []})
		)
		_check(
			not invalid.accepted and session.get_view().to_dictionary() == before,
			"invalid battle command leaves entire published session unchanged"
		)
		_check(
			not entered.view.battle.has("card_by_id") and not entered.view.battle.has("draw"),
			"public battle view hides draw order"
		)
	session.free()


func _node_id(layer: int, kind: String) -> String:
	for node in _state.nodes:
		if node.layer == layer and node.kind == kind:
			return node.node_id
	return "missing"


func _apply(type: StringName, payload: Dictionary) -> GameResult:
	var result := _service.apply(_state, GameAction.new(type, payload), _rng)
	_check(result.ok, "accept %s" % type)
	if result.ok:
		_state = result.data.state
		_rng = result.data.rng_states
		_commands.append({"type": String(type), "payload": payload.duplicate(true)})
	else:
		print("G4_ACTION_ERROR=", type, " ", result.error.to_dictionary())
	return result


func _rejected(type: StringName, payload: Dictionary, code: StringName) -> void:
	var before := _state.to_dictionary()
	var rng_before := _rng.duplicate(true)
	var result := _service.apply(_state, GameAction.new(type, payload), _rng)
	_check(not result.ok and result.error.code == code, "reject %s as %s" % [type, code])
	_check(_state.to_dictionary() == before and _rng == rng_before, "rejected %s is atomic" % type)
	if result.ok or result.error.code != code:
		print(
			"G4_REJECTION_MISMATCH=",
			type,
			" expected ",
			code,
			" actual ",
			result.error.to_dictionary() if not result.ok else "accepted"
		)


func _check(value: bool, label: String) -> void:
	if not value:
		_failures.append("G4: " + label)
