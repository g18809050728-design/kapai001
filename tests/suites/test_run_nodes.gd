extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	_check(loaded.ok, "node test production content loads", failures)
	if not loaded.ok:
		return failures
	var service := RunNodeService.new(catalog)
	var state := RunState.new(
		{
			"run_id": "node_test",
			"ruleset_id": "campus_v1",
			"vitality": 40,
			"max_vitality": 72,
			"money": 60,
			"cards": _cards()
		}
	)
	state.nodes = RunMap.build(state.run_id, 1)
	_check(state.nodes.size() == 8, "map has 8 frozen nodes", failures)
	_check(
		state.reachable_node_ids() == ["node_test|t1l1_normal"],
		"only first layer reachable",
		failures
	)
	state.nodes[0].status = "active"
	state.current_node_id = state.nodes[0].node_id
	_check(state.reachable_node_ids().is_empty(), "active node blocks progress", failures)
	state.nodes[0].status = "completed"
	_check(
		state.reachable_node_ids() == ["node_test|t1l2_event", "node_test|t1l2_normal"],
		"completed node exposes adjacent branch",
		failures
	)
	var event_node := state.find_node("node_test|t1l2_event")
	state.current_node_id = event_node.node_id
	event_node.status = "active"
	state.seen_event_ids.assign(["V01", "V04", "V10"])
	var rng := RandomSource.new("42")
	var initial := rng.export_state().to_dictionary()
	var entered := service.enter_event(state, event_node, rng)
	_check(entered.ok and entered.data is EventState, "event created", failures)
	if not entered.ok or entered.data == null:
		return failures
	event_node.context.event = entered.data
	var event: EventState = entered.data
	_check(event.definition_id == "V03", "seen event filtering", failures)
	_check(
		event.frozen_candidates.consult["0"] == ["K14", "K05", "K60"],
		"approved V03 override frozen",
		failures
	)
	_check(
		initial == rng.export_state().to_dictionary(),
		"single event and explicit candidates consume no RNG",
		failures
	)
	var before := state.to_dictionary()
	var rejected := service.choose_event(
		state,
		{
			"event_instance_id": event.event_instance_id,
			"option_id": "drop",
			"selection_ids": ["missing"]
		}
	)
	_check(
		not rejected.ok and before == state.to_dictionary(),
		"invalid event target preserves vitality and deck",
		failures
	)
	var resolved := service.choose_event(
		state,
		{"event_instance_id": event.event_instance_id, "option_id": "drop", "selection_ids": ["c0"]}
	)
	_check(resolved.ok, "valid event applies", failures)
	if resolved.ok:
		var after: RunState = resolved.data
		_check(
			after.vitality == 35 and after.cards.size() == 5,
			"event payment and deletion atomic",
			failures
		)
		_check(
			state.vitality == 40 and state.cards.size() == 6,
			"successful event returns independent state",
			failures
		)
		var repeated := service.choose_event(
			after,
			{
				"event_instance_id": event.event_instance_id,
				"option_id": "drop",
				"selection_ids": ["c1"]
			}
		)
		_check(
			not repeated.ok and repeated.error.code == &"ALREADY_RESOLVED",
			"event repeat rejected",
			failures
		)
	var copied := state.copy_for_write()
	var copied_event: EventState = copied.find_node(event_node.node_id).context.event
	copied_event.frozen_candidates.consult["0"].clear()
	_check(
		event.frozen_candidates.consult["0"].size() == 3,
		"event candidate copies isolated",
		failures
	)
	var rest_node := state.find_node("node_test|t1l5_rest")
	state.current_node_id = rest_node.node_id
	rest_node.status = "active"
	var rested := service.take_rest(state, {"node_id": rest_node.node_id, "option_id": "heal"})
	_check(
		rested.ok and rested.data.vitality == 58, "rest heals floor of quarter maximum", failures
	)
	if rested.ok:
		var repeated := service.take_rest(
			rested.data, {"node_id": rest_node.node_id, "option_id": "heal"}
		)
		_check(
			not repeated.ok and repeated.error.code == &"ALREADY_RESOLVED",
			"rest repeat rejected",
			failures
		)
	var upgraded := service.take_rest(
		state, {"node_id": rest_node.node_id, "option_id": "upgrade", "card_instance_id": "c0"}
	)
	_check(
		(
			upgraded.ok
			and upgraded.data.cards[0].upgrade_level == 1
			and state.cards[0].upgrade_level == 0
		),
		"rest upgrades only chosen permanent instance",
		failures
	)
	var invalid_train := service.take_rest(
		state, {"node_id": rest_node.node_id, "option_id": "train", "card_instance_id": "c0"}
	)
	_check(not invalid_train.ok, "training rejects non cooperation", failures)
	_test_event_variants(service, failures)
	return failures


func _test_event_variants(service: RunNodeService, failures: Array[String]) -> void:
	for definition_id in ["V01", "V04", "V10"]:
		var state := RunState.new(
			{
				"run_id": "event_" + definition_id,
				"ruleset_id": "campus_v1",
				"vitality": 40,
				"max_vitality": 72,
				"money": 60,
				"cards": _cards()
			}
		)
		state.nodes = RunMap.build(state.run_id, 1)
		var node := state.nodes[1]
		node.status = "active"
		state.current_node_id = node.node_id
		for id in ["V01", "V03", "V04", "V10"]:
			if id != definition_id:
				state.seen_event_ids.append(id)
		var rng := RandomSource.new("42")
		var before := rng.export_state().to_dictionary()
		var entered := service.enter_event(state, node, rng)
		_check(entered.ok and entered.data != null, "event enters " + definition_id, failures)
		if not entered.ok or entered.data == null:
			continue
		var event: EventState = entered.data
		node.context.event = event
		var after := rng.export_state().to_dictionary()
		_check(
			(
				before.streams.battle == after.streams.battle
				and before.streams.event == after.streams.event
			),
			"event freezes only assigned streams " + definition_id,
			failures
		)
		if definition_id == "V01":
			var travel_candidates: Array = event.frozen_candidates.travel["0"]
			_check(not travel_candidates.is_empty(), "V01 blue candidates available", failures)
			if not travel_candidates.is_empty():
				var travel := service.choose_event(
					state,
					{
						"event_instance_id": event.event_instance_id,
						"option_id": "travel",
						"selection_ids": [travel_candidates[0]]
					}
				)
				_check(
					travel.ok and travel.data.cards.size() == 7, "V01 grants frozen card", failures
				)
			var return_home := service.choose_event(
				state,
				{
					"event_instance_id": event.event_instance_id,
					"option_id": "return_home",
					"selection_ids": []
				}
			)
			_check(
				return_home.ok and return_home.data.relics.size() == 1,
				"V01 grants random relic",
				failures
			)
		elif definition_id == "V04":
			var upgrade := service.choose_event(
				state,
				{
					"event_instance_id": event.event_instance_id,
					"option_id": "upgrade_work",
					"selection_ids": ["c0"]
				}
			)
			_check(
				(
					upgrade.ok
					and upgrade.data.vitality == 34
					and upgrade.data.cards[0].upgrade_level == 1
				),
				"V04 pays and upgrades permanent work card",
				failures
			)
		else:
			var grant := service.choose_event(
				state,
				{
					"event_instance_id": event.event_instance_id,
					"option_id": "return_card",
					"selection_ids": []
				}
			)
			_check(
				grant.ok and grant.data.relics[0].definition_id == "A15",
				"V10 grants campus card",
				failures
			)
			state.relics.append({"relic_id": "owned_a15", "definition_id": "A15", "slot": 0})
			var duplicate := service.choose_event(
				state,
				{
					"event_instance_id": event.event_instance_id,
					"option_id": "return_card",
					"selection_ids": []
				}
			)
			_check(
				duplicate.ok and duplicate.data.money == 80 and duplicate.data.relics.size() == 1,
				"V10 duplicate converts to declared money",
				failures
			)
		_check(
			after == rng.export_state().to_dictionary(),
			"event resolution consumes no RNG " + definition_id,
			failures
		)


func _cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for index in range(6):
		cards.append({"card_id": "c%d" % index, "definition_id": "K01", "upgrade_level": 0})
	return cards


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
