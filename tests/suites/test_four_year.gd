extends RefCounted

var _failures: Array[String] = []
var _catalog := ContentDB.new("res://data/four_year")
var _service: RunService
var _run: RunState
var _rng: Dictionary
var _checkpoints: Dictionary = {}

func run() -> Array[String]:
	var loaded := _catalog.load("campus_four_year")
	_check(loaded.ok, "four-year content loads: " + str(loaded.error.to_dictionary() if loaded.error != null else null))
	if not loaded.ok:
		return _failures
	_service = RunService.new(_catalog)
	_test_public_session()
	var created := _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(created.ok, "campaign starts")
	if not created.ok:
		return _failures
	_run = created.data.state
	_rng = created.data.rng_states
	var legacy := _run.copy_for_write()
	legacy.nodes = CampaignMap.build(legacy.run_id, true)
	_check(legacy.validate().is_empty(), "legacy frozen map remains valid without editing player saves")
	var legacy_roundtrip := RunCodec.decode(legacy.to_dictionary(), _catalog)
	_check(legacy_roundtrip.ok and legacy_roundtrip.data.to_dictionary() == legacy.to_dictionary(), "legacy map codec preserves its exact original topology")
	var damaged_legacy := legacy.copy_for_write()
	damaged_legacy.nodes[0].next_ids.clear()
	_check(not damaged_legacy.validate().is_empty(), "mixed or damaged topology is rejected by both map baselines")
	_check(_run.relics.is_empty(), "no legacy starter relic")
	_check(_run.nodes.size() == 124, "124 frozen candidate nodes")
	for year in range(1, 5):
		var count := 0
		for node in _run.nodes:
			if node.term == year:
				count += 1
		_check(count == [20, 28, 36, 40][year - 1], "year node count %d" % year)
		_check(_safe_route(year), "safe route reaches year boss %d" % year)
		var reached := {}
		for node in _run.nodes:
			if node.term != year: continue
			_check(node.next_ids.size() <= 2, "year %d node offers at most two next stops" % year)
			for next_id in node.next_ids:
				var destination := _run.find_node(str(next_id))
				_check(destination != null and destination.layer == node.layer + 1, "year %d route edge advances one layer" % year)
			if node.layer == 1: reached[node.node_id] = true
			if reached.has(node.node_id):
				for next_id in node.next_ids: reached[next_id] = true
		_check(reached.size() == count, "all candidate nodes are reachable in year %d" % year)
		for layer in range(1, CampaignMap.MAPS[year - 1].layers):
			var sources := _run.nodes.filter(func(node): return node.term == year and node.layer == layer)
			var destinations := _run.nodes.filter(func(node): return node.term == year and node.layer == layer + 1)
			if sources.size() > 1 and destinations.size() > 1:
				var distinct_routes := {}
				for source in sources:
					var ids: Array = source.next_ids.duplicate()
					ids.sort()
					distinct_routes["|".join(ids)] = true
				_check(distinct_routes.size() > 1, "year %d layer %d routes differ by current position" % [year, layer])
	for i in 500:
		if not _run.outcome.is_empty():
			break
		var pending: Dictionary = _run.campaign.pending
		if not pending.is_empty():
			if not _checkpoints.has(pending.kind):
				_checkpoints[pending.kind] = _run.copy_for_write()
			if pending.kind == "relic" and _run.relics.size() == 3 and not _checkpoints.has("relic_full"):
				_checkpoints["relic_full"] = _run.copy_for_write()
			var payload := {"offer_id": pending.offer_id}
			match str(pending.kind):
				"direction": payload.option_id = "theory"
				"destination": payload.option_id = "research"
				"grand": payload.option_id = "resources"
				"relic":
					payload.option_id = "claim"
					payload.candidate_id = pending.candidates[0]
					if _run.relics.size() >= 3:
						payload.replace_relic_id = _run.relics[0].relic_id
				"service":
					var sub: String = CampaignMap.metadata(pending.source_node_id).subtype
					payload.option_id = "money" if sub in ["C", "I"] else ("progress" if sub == "ST" else "skip")
				_: payload.option_id = "skip"
			var before := _run.to_dictionary().duplicate(true)
			var rng_before := _rng.duplicate(true)
			var action := GameAction.new(&"choose_campaign", payload)
			var preview := _service.preview(_run, action)
			_check(preview.ok and preview.data.can_submit, "campaign preview accepts chosen option")
			_check(before == _run.to_dictionary() and rng_before == _rng, "preview preserves state/RNG")
			var old_run := _run
			var old_rng := _rng.duplicate(true)
			if not _apply(action): break
			var duplicate := _service.apply(_run, action, _rng)
			_check(not duplicate.ok, "duplicate campaign reward rejected")
			_check(old_run.to_dictionary() == before and old_rng == rng_before, "command copies source state")
			continue
		if not _run.active_battle_id.is_empty():
			# Controlled outcomes isolate run logic; actual battle engine checked below.
			var boss := _run.find_node(_run.current_node_id).kind == "boss"
			var old_money := _run.money
			var result := _service.settle_battle(_run, {"battle_id": _run.active_battle_id, "result": "won", "remaining_vitality": 50}, _rng)
			if not _accept(result): break
			if boss:
				_check(_run.money == old_money and _run.pending_reward == null, "boss gives only annual grand reward without ordinary payout")
			continue
		if _run.pending_reward != null and not _run.pending_reward.is_complete():
			for item in _run.pending_reward.items:
				_check(item.kind == "card", "elites never drop extra relics")
				if item.status == "pending":
					if not _apply(GameAction.new(&"skip_reward", {"offer_id": _run.pending_reward.offer_id, "item_id": item.item_id})): break
			continue
		var current := _run.find_node(_run.current_node_id)
		if current != null and current.status == "active":
			if current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				if not _apply(GameAction.new(&"choose_event", {"event_instance_id": current.context.event.event_instance_id, "option_id": "leave"})): break
			elif current.kind == "rest" and not current.context.get("used", false):
				if not _apply(GameAction.new(&"take_rest", {"node_id": current.node_id, "option_id": "heal"})): break
			else:
				if not _apply(GameAction.new(&"leave_node", {"node_id": current.node_id})): break
			continue
		var reachable := _run.reachable_node_ids()
		_check(not reachable.is_empty(), "campaign always has a next step")
		if reachable.is_empty(): break
		var chosen: String = reachable[0]
		# Mix special services and risk routes; any single forced path is separately checked.
		for id in reachable:
			if CampaignMap.metadata(id).subtype in ["C", "I", "ST", "LAB", "T"]:
				chosen = id
		if not _apply(GameAction.new(&"enter_node", {"node_id": chosen})): break
	_check(_run.outcome == "won" and _run.term == 4, "full four-year run graduates")
	_check(_run.node_path.size() == 52, "route completes exactly 52 layers")
	var relic_count := 0
	var grand_count := 0
	for record in _run.campaign.history:
		if "|relic" in str(record.offer_id): relic_count += 1
		if str(record.offer_id).ends_with("|grand"): grand_count += 1
	_check(relic_count == 8 and grand_count == 4, "exactly eight relic and four grand rewards")
	_check(_run.relics.size() == 3, "relic capacity stays three")
	_checkpoints["summary"] = _run.copy_for_write()
	_test_reward_edges()
	_test_save_guards()
	return _failures

func _safe_route(year: int) -> bool:
	var reachable: Array[String] = []
	for node in _run.nodes:
		if node.term == year and node.layer == 1:
			reachable.append(node.node_id)
	var visited := {}
	while not reachable.is_empty():
		var node := _run.find_node(reachable.pop_front())
		if visited.has(node.node_id) or node.kind == "elite": continue
		visited[node.node_id] = true
		if node.kind == "boss": return true
		reachable.append_array(node.next_ids)
	return false

func _apply(action: GameAction) -> bool:
	return _accept(_service.apply(_run, action, _rng))

func _accept(result: GameResult) -> bool:
	_check(result.ok, "run action succeeds: " + str(result.error.to_dictionary() if result.error != null else null))
	if not result.ok: return false
	_run = result.data.state
	_rng = result.data.rng_states
	var encoded := RunCodec.encode(_run)
	_check(encoded.ok, "run encodes at every stable action: " + str(encoded.error))
	if not encoded.ok: return false
	var decoded := RunCodec.decode(encoded.data, _catalog)
	_check(decoded.ok, "run decodes at every stable action: " + str(decoded.error))
	if not decoded.ok: return false
	_check(decoded.data.to_dictionary() == _run.to_dictionary(), "save roundtrip preserves frozen offers/path/history")
	_run = decoded.data
	return true

func _test_reward_edges() -> void:
	var created := _service.create(StartRunRequest.new("P01", &"normal", "campus_four_year", "7"))
	var run: RunState = created.data.state
	var rewards := CampaignService.new(_catalog)
	var node: RunNodeState = run.nodes[0]
	node.status = "active"
	run.current_node_id = node.node_id
	run.active_battle_id = node.node_id
	run.active_encounter_id = "N01"
	node.context = {"encounter_id": "N01", "settled": false}
	for encounter in ["FY_B1", "FY_B2", "FY_B3", "FY_B4", "FY_FINAL_job", "FY_FINAL_exam", "FY_FINAL_research", "FY_FINAL_abroad", "FY_FINAL_deferred"]:
		var input := {"battle_id": "probe" + encounter, "node_id": "probe" + encounter, "encounter_id": encounter, "character_id": "P01", "difficulty": "normal", "vitality": 72, "max_vitality": 72, "cards": run.cards.map(func(card): return {"card_id": card.card_id, "definition_id": card.definition_id, "upgrade_level": card.upgrade_level}), "relics": [], "rng_state": created.data.rng_states}
		var engine := BattleEngine.new(_catalog)
		var battle := engine.begin(input)
		_check(battle.ok, "annual boss enters existing battle engine: %s %s" % [encounter, str(battle.error)])
	var tx := TransactionResolver.new(_catalog)
	for i in 3: tx.add_relic(run, "FY_Y1_%d" % (i+1), "", i)
	run.active_battle_id = ""
	run.active_encounter_id = ""
	var pending := {"offer_id": "edge", "kind": "relic", "source_node_id": node.node_id, "candidates": ["FY_Y1_1", "FY_Y1_4"]}
	run.campaign.pending = pending.duplicate(true)
	run.campaign.triggered.append("edge")
	var before := run.to_dictionary()
	var money := run.money
	var invalid := _service.apply(run, GameAction.new(&"choose_campaign", {"offer_id": "edge", "option_id": "claim", "candidate_id": "FY_Y1_4"}), created.data.rng_states)
	_check(not invalid.ok and before == run.to_dictionary(), "full slots require valid replacement, reject atomically")
	var duplicate := rewards.choose(run, {"offer_id": "edge", "option_id": "claim", "candidate_id": "FY_Y1_1"})
	_check(duplicate.ok and run.money == money + 25 and run.relics.size() == 3, "duplicate converts exactly 25")
	run.campaign.pending = pending.duplicate(true)
	money = run.money
	var converted := rewards.choose(run, {"offer_id": "edge", "option_id": "convert", "candidate_id": "FY_Y1_4"})
	_check(converted.ok and run.money == money + 30, "full-slot conversion is 30")
	for year in [3, 4]:
		run.term = year
		var service_node := run.find_node(run.run_id + ("|y3l2s2" if year == 3 else "|y4l2s0"))
		run.current_node_id = service_node.node_id
		service_node.status = "active"
		service_node.context = {"used": false, "option_id": ""}
		rewards.enter(run, service_node)
		var offer_id: String = run.campaign.pending.offer_id
		_check(rewards.choose(run, {"offer_id": offer_id, "option_id": "skip"}).ok, "special service can be skipped")
		rewards.completed(run, service_node, RandomSource.new())
		_check(run.campaign.resume == 0 and run.campaign.thesis == 0, "skipped service cannot grant resume/thesis")

func _test_save_guards() -> void:
	var record: Dictionary = _checkpoints.relic.to_dictionary()
	record.campaign.pending.candidates[0] = "FY_Y4_1"
	_check(not RunCodec.decode(record, _catalog).ok, "save rejects wrong-year relic candidate")
	record = _checkpoints.grand.to_dictionary()
	record.campaign.pending.candidates[0] = "R3-C-01"
	_check(not RunCodec.decode(record, _catalog).ok, "save rejects basic annual reward")
	record = _checkpoints.grand.to_dictionary()
	record.campaign.history.append({"offer_id": record.campaign.pending.offer_id, "option_id": "skip", "candidate_id": ""})
	_check(not RunCodec.decode(record, _catalog).ok, "save rejects an offer both resolved and pending")

func _test_public_session() -> void:
	var store := SaveStore.new("user://four-year-public-%s" % Time.get_ticks_usec())
	var session := GameSession.new(store)
	var started := session.start_run(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(started.accepted, "public session starts four-year run")
	var saved := session.save_current()
	_check(saved.ok, "public campaign saves: " + str(saved.error.to_dictionary() if saved.error != null else null))
	session.free()
	var restored := GameSession.new(store)
	var continued := restored.continue_run()
	_check(continued.ok, "public campaign resumes: " + str(continued.error.to_dictionary() if continued.error != null else null))
	restored.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
