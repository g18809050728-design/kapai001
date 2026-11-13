extends RefCounted

var _failures: Array[String] = []
var _catalog := ContentDB.new("res://data/four_year")
var _service: RunService
var _run: RunState
var _rng: Dictionary
var _checkpoints: Dictionary = {}
var _assertions := 0

func run() -> Array[String]:
	_check(_catalog.load("campus_four_year").ok, "content loads")
	_service = RunService.new(_catalog)
	var created := _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(created.ok, "new run starts")
	if not created.ok:
		return _failures
	_run = created.data.state
	_rng = created.data.rng_states
	_check(_run.campaign.version == 2, "new run uses annual-map version2")
	_check(_run.campaign.map_version == 2 and _run.campaign.years[0].version == 2, "new runs use the denser generation algorithm version2")
	_check(_run.nodes.all(func(node): return node.term == 1), "future years are not generated at setup")
	_check(_run.nodes.size() > 20, "year1 has sustained route choices")
	_check(_run.validate().is_empty(), "new map passes aggregate validation")
	_check(CampaignProgression.year_info(_run, 2).is_empty(), "unpublished future year has no fabricated preview")
	var other: RunState = _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "42")).data.state
	_check(other.run_id != _run.run_id and other.campaign.years == _run.campaign.years, "run identity does not influence seeded maps")
	other = _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "43")).data.state
	_check(other.campaign.years != _run.campaign.years, "different seeds produce different maps")
	var frozen := _run.to_dictionary()
	var random_before := _rng.duplicate(true)
	_check(CampaignProgression.ensure_year(_run).ok and frozen == _run.to_dictionary() and random_before == _rng, "generation is idempotent and preserves shared RNG")
	_checkpoints.start = _run.copy_for_write()
	_walk()
	_check(_run.outcome == "won", "controlled four-year route graduates")
	_check(_run.node_path.size() == 52, "exactly 52 visited stops")
	_check(_run.campaign.years.size() == 4 and _run.campaign.summaries.size() == 4, "all four maps and completed summaries are frozen at graduation")
	var relics := 0
	var grands := 0
	for record in _run.campaign.history:
		if "|relic" in str(record.offer_id): relics += 1
		if str(record.offer_id).ends_with("|grand"): grands += 1
	_check(relics == 8 and grands == 4, "exactly eight relic and four annual grand rewards")
	if _checkpoints.has("direction"):
		_test_decision_boundary(_checkpoints.direction, "theory")
	if _checkpoints.has("destination"):
		_test_decision_boundary(_checkpoints.destination, "research")
	_test_corruption()
	_test_completed_experiences()
	_test_previous_year_influence()
	_test_direction_change()
	_test_destinations()
	_test_snapshot_compatibility()
	_test_generator_version_compatibility()
	print("ADAPTIVE_MAP_ASSERTIONS=%d CONTROLLED_STOPS=%d RELICS=%d GRANDS=%d" % [_assertions, _run.node_path.size(), relics, grands])
	return _failures

func _walk(stop_at: String = "", last_route: bool = false) -> void:
	for iteration in 600:
		if not _run.outcome.is_empty(): return
		var pending: Dictionary = _run.campaign.pending
		if not pending.is_empty():
			var kind: String = pending.kind
			if not _checkpoints.has(kind): _checkpoints[kind] = _run.copy_for_write()
			if kind == stop_at: return
			if kind == "service" and _run.term == 2 and CampaignProgression.metadata(_run, pending.source_node_id).layer >= 7:
				_checkpoints.change = _run.copy_for_write()
			var payload := {"offer_id": pending.offer_id, "option_id": "skip"}
			match kind:
				"direction": payload.option_id = "theory"
				"destination": payload.option_id = "research"
				"grand": payload.option_id = "resources"
				"service":
					var subtype: String = CampaignProgression.metadata(_run, pending.source_node_id).subtype
					if subtype in ["I", "C"]: payload.option_id = "money"
					elif subtype == "ST": payload.option_id = "progress"
					elif subtype in ["LAB", "T", "L"]:
						for card in _run.cards:
							var definition: Dictionary = _catalog.get_definition("card", card.definition_id).data
							if card.upgrade_level == 0 and not definition.get("upgrade", {}).is_empty():
								payload.option_id = "upgrade"
								payload.candidate_id = card.card_id
								break
						if not _service.preview(_run, GameAction.new(&"choose_campaign", payload)).data.can_submit:
							payload = {"offer_id": pending.offer_id, "option_id": "skip"}
			if kind == "service" and last_route:
				payload = {"offer_id": pending.offer_id, "option_id": "skip"}
			if not _apply(GameAction.new(&"choose_campaign", payload)): return
			continue
		if not _run.active_battle_id.is_empty():
			# These injected outcomes verify progression, not gameplay balance.
			if not _accept(_service.settle_battle(_run, {"battle_id": _run.active_battle_id, "result": "won", "remaining_vitality": _run.max_vitality}, _rng)): return
			continue
		if _run.pending_reward != null and not _run.pending_reward.is_complete():
			for item in _run.pending_reward.items:
				if item.status == "pending":
					if not _apply(GameAction.new(&"skip_reward", {"offer_id": _run.pending_reward.offer_id, "item_id": item.item_id})): return
			continue
		var current := _run.find_node(_run.current_node_id)
		if current != null and current.status == "active":
			if current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				if not _apply(GameAction.new(&"choose_event", {"event_instance_id": current.context.event.event_instance_id, "option_id": "leave"})): return
			elif current.kind == "rest" and not current.context.get("used", false):
				if not _apply(GameAction.new(&"take_rest", {"node_id": current.node_id, "option_id": "heal"})): return
			else:
				if not _apply(GameAction.new(&"leave_node", {"node_id": current.node_id})): return
			continue
		var reachable := _run.reachable_node_ids()
		_check(not reachable.is_empty(), "a reachable successor exists throughout the run")
		if reachable.is_empty(): return
		var chosen: String = reachable[-1] if last_route else reachable[0]
		if not last_route:
			for id in reachable:
				if CampaignProgression.metadata(_run, id).subtype in ["LAB", "T", "ST", "I"]: chosen = id
		if not _checkpoints.has("year%d" % _run.term): _checkpoints["year%d" % _run.term] = _run.copy_for_write()
		if not _apply(GameAction.new(&"enter_node", {"node_id": chosen})): return
	_check(false, "controlled route did not exceed action budget")

func _apply(action: GameAction) -> bool:
	var before := _run.to_dictionary()
	var rng_before := _rng.duplicate(true)
	var preview := _service.preview(_run, action)
	_check(preview.ok and preview.data.can_submit, "preview accepts controlled action")
	_check(before == _run.to_dictionary() and rng_before == _rng, "preview is read-only")
	var result := _service.apply(_run, action, _rng)
	_check(before == _run.to_dictionary() and rng_before == _rng, "apply preserves source state and RNG")
	if not _accept(result): return false
	if action.type == &"choose_campaign":
		var settled := _run.to_dictionary()
		var rejected := _service.apply(_run, action, _rng)
		_check(not rejected.ok and settled == _run.to_dictionary(), "duplicate campaign choice rejects atomically")
	return true

func _accept(result: GameResult) -> bool:
	_check(result.ok, "run action succeeds: " + str(result.error.to_dictionary() if result.error != null else null))
	if not result.ok: return false
	_run = result.data.state
	_rng = result.data.rng_states
	if result.data.battle_input != null and _run.find_node(_run.current_node_id).kind == "boss":
		var battle := BattleEngine.new(_catalog).begin(result.data.battle_input)
		_check(battle.ok, "generated annual boss enters real BattleEngine")
		if battle.ok: _check(BattleCodec.decode(battle.data.state.to_dictionary(), _catalog).ok, "annual boss BattleCodec roundtrip")
	var encoded := RunCodec.encode(_run)
	_check(encoded.ok, "every stable action encodes: " + str(encoded.error.to_dictionary() if encoded.error != null else null))
	if not encoded.ok: return false
	var decoded := RunCodec.decode(encoded.data, _catalog)
	_check(decoded.ok, "every stable action decodes: " + str(decoded.error.to_dictionary() if decoded.error != null else null))
	if not decoded.ok: return false
	_check(decoded.data.to_dictionary() == _run.to_dictionary(), "frozen maps and history survive exact roundtrip")
	_run = decoded.data
	return true

func _test_decision_boundary(before: RunState, option: String) -> void:
	_check(before.campaign.years.size() == before.term - 1, "next map waits for explicit direction/destination")
	_check(before.campaign.summaries.size() == before.term - 1, "previous summary freezes before the decision")
	var waiting := before.to_dictionary()
	var held_rng := _rng.duplicate(true)
	var invalid := _service.apply(before, GameAction.new(&"choose_campaign", {"offer_id": before.campaign.pending.offer_id, "option_id": "invalid"}), held_rng)
	_check(not invalid.ok and waiting == before.to_dictionary() and held_rng == _rng, "invalid decision cannot generate a map or consume RNG")
	var restored := RunCodec.decode(waiting, _catalog)
	_check(restored.ok, "decision boundary can be saved and restored")
	if not restored.ok: return
	var action := GameAction.new(&"choose_campaign", {"offer_id": before.campaign.pending.offer_id, "option_id": option})
	var first := _service.apply(before, action, held_rng)
	var second := _service.apply(restored.data, action, held_rng)
	_check(first.ok and second.ok, "explicit decision publishes next map")
	if first.ok and second.ok:
		_check(first.data.state.campaign.years == second.data.state.campaign.years, "continue then generate matches uninterrupted play")
		_check(first.data.rng_states == held_rng and second.data.rng_states == held_rng, "annual generation leaves all shared random streams unchanged")
		_check(first.data.state.campaign.years.slice(0, before.term - 1) == before.campaign.years, "generating next year preserves all published maps")
		var alternate := "practice" if before.term == 2 else "job"
		var other := _service.apply(before, GameAction.new(&"choose_campaign", {"offer_id": before.campaign.pending.offer_id, "option_id": alternate}), held_rng)
		_check(other.ok and other.data.state.campaign.years[-1] != first.data.state.campaign.years[-1], "explicit choices can change later maps for the same seed")

func _test_corruption() -> void:
	var base: RunState = _checkpoints.start
	for field in ["years", "summaries", "root_seed", "map_version"]:
		var record := base.to_dictionary()
		record.campaign.erase(field)
		_check(not RunCodec.decode(record, _catalog).ok, "missing annual field rejects: " + field)
	var record := base.to_dictionary()
	record.campaign.years[0].nodes[0].next.clear()
	_check(not RunCodec.decode(record, _catalog).ok, "damaged frozen graph rejects")
	record = base.to_dictionary()
	record.campaign.years[0].nodes[2].title += "篡改"
	_check(not RunCodec.decode(record, _catalog).ok, "altered generated content rejects")
	record = base.to_dictionary()
	record.campaign.years[0].profile.direction = "practice"
	_check(not RunCodec.decode(record, _catalog).ok, "forged historical choice rejects")
	record = base.to_dictionary()
	record.nodes.append(CampaignMap.build(base.run_id)[0].to_dictionary())
	_check(not RunCodec.decode(record, _catalog).ok, "mixed fixed and generated nodes reject")
	if _checkpoints.has("year2"):
		record = _checkpoints.year2.to_dictionary()
		record.campaign.summaries[0].research = 6
		_check(not RunCodec.decode(record, _catalog).ok, "forged completed experience rejects")
		record = _checkpoints.year2.to_dictionary()
		record.campaign.direction = "practice"
		_check(not RunCodec.decode(record, _catalog).ok, "current direction must agree with explicit decision history")
		record = _checkpoints.year2.to_dictionary()
		record.campaign.direction_changed = true
		_check(not RunCodec.decode(record, _catalog).ok, "direction-change flag requires a completed change")
		record = _checkpoints.year2.to_dictionary()
		record.campaign.history = record.campaign.history.filter(func(item): return not str(item.offer_id).ends_with("|grand"))
		_check(not RunCodec.decode(record, _catalog).ok, "published next year requires previous grand reward completion")

func _test_generator_version_compatibility() -> void:
	var saved_run := _run
	var saved_rng := _rng.duplicate(true)
	var created := _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
	_check(created.ok, "legacy annual fixture starts")
	if not created.ok: return
	_run = created.data.state
	_rng = created.data.rng_states
	_run.campaign.map_version = 1
	_run.campaign.years.clear()
	_run.nodes.clear()
	_check(CampaignProgression.ensure_year(_run).ok, "algorithm1 can still publish its original first year")
	_check(_run.campaign.years.size() == 1 and _run.campaign.years[0].version == 1, "algorithm1 stays frozen rather than silently upgrading")
	var expected_seed := ("annual-map-v1|42|1|" + SnapshotCodec.canonical_json(_run.campaign.years[0].profile)).sha256_text()
	_check(_run.campaign.years[0].seed == expected_seed, "legacy seed derivation retains original version1 domain")
	var old_graph: Array = _run.campaign.years.duplicate(true)
	var session := SessionState.new()
	session.run = _run
	session.random_snapshot = _rng.duplicate(true)
	var snapshot := SnapshotCodec.encode_session(session, _catalog.get_info())
	_check(snapshot.ok, "legacy annual graph encodes through public snapshot")
	if snapshot.ok:
		var decoded := SnapshotCodec.decode_session(snapshot.data, _catalog)
		_check(decoded.ok, "legacy annual graph restores through public snapshot")
		if decoded.ok:
			_run = decoded.data.run
			_check(_run.campaign.years == old_graph, "restoring legacy snapshot preserves every frozen node")
	_walk()
	_check(_run.outcome == "won" and _run.campaign.years.size() == 4, "legacy annual save can continue through all four years")
	_check(_run.campaign.years.all(func(map): return map.version == 1), "future legacy years use original generation algorithm")
	_check(_run.campaign.years[0] == old_graph[0], "legacy progression does not rewrite already published map")
	var mixed := saved_run.to_dictionary()
	mixed.campaign.map_version = 1
	_check(not RunCodec.decode(mixed, _catalog).ok, "algorithm2 maps cannot masquerade as algorithm1")
	mixed = _run.to_dictionary()
	mixed.campaign.map_version = 2
	_check(not RunCodec.decode(mixed, _catalog).ok, "algorithm1 maps cannot masquerade as algorithm2")
	mixed = saved_run.to_dictionary()
	mixed.campaign.map_version = 999
	_check(not RunCodec.decode(mixed, _catalog).ok, "unknown generator versions still reject")
	_run = saved_run
	_rng = saved_rng


func _test_completed_experiences() -> void:
	var fixture: RunState = _checkpoints.start.copy_for_write()
	var service_node: RunNodeState = null
	for node in fixture.nodes:
		if CampaignProgression.metadata(fixture, node.node_id).subtype in ["LAB", "T", "I", "C"]:
			service_node = node
			break
	_check(service_node != null, "fixture exposes experience service")
	if service_node == null: return
	service_node.status = "completed"
	fixture.campaign.history.append({"offer_id": service_node.node_id + "|service", "option_id": "skip", "candidate_id": ""})
	CampaignProgression.complete_year(fixture)
	var skipped: Dictionary = fixture.campaign.summaries[0]
	_check(skipped.research + skipped.competition + skipped.internship + skipped.community == 0, "skipped services do not count as experiences")
	fixture.campaign.summaries.clear()
	fixture.campaign.history[-1].option_id = "direction_theory"
	CampaignProgression.complete_year(fixture)
	var changed: Dictionary = fixture.campaign.summaries[0]
	_check(changed.research + changed.competition + changed.internship + changed.community == 0, "changing direction does not count as using a service")
	fixture.campaign.summaries.clear()
	var subtype: String = CampaignProgression.metadata(fixture, service_node.node_id).subtype
	fixture.campaign.history[-1].option_id = "money" if subtype in ["I", "C"] else "upgrade"
	CampaignProgression.complete_year(fixture)
	var used: Dictionary = fixture.campaign.summaries[0]
	_check(used.research + used.competition + used.internship + used.community == 1, "completed used service counts once")
	CampaignProgression.complete_year(fixture)
	_check(fixture.campaign.summaries.size() == 1, "summary freezing is idempotent")

func _test_previous_year_influence() -> void:
	var saved := _run
	var saved_rng := _rng.duplicate(true)
	var outcomes: Array[Dictionary] = []
	for last_route in [false, true]:
		var created := _service.create(StartRunRequest.new("P02", &"normal", "campus_four_year", "42"))
		_run = created.data.state
		_rng = created.data.rng_states
		_walk("direction", last_route)
		_check(_run.term == 2 and _run.campaign.pending.get("kind", "") == "direction", "different actual year-one routes reach the decision boundary")
		outcomes.append({"run": _run.copy_for_write(), "rng": _rng.duplicate(true)})
	var first: RunState = outcomes[0].run
	var second: RunState = outcomes[1].run
	print("HISTORY_INFLUENCE_INPUTS=" + JSON.stringify([first.campaign.summaries, second.campaign.summaries]))
	_check(first.campaign.summaries != second.campaign.summaries, "different completed experiences produce different annual summaries")
	var maps: Array = []
	for outcome in outcomes:
		var source: RunState = outcome.run
		var result := _service.apply(source, GameAction.new(&"choose_campaign", {"offer_id": source.campaign.pending.offer_id, "option_id": "theory"}), outcome.rng)
		_check(result.ok, "same explicit direction is valid after each different history")
		if result.ok: maps.append(result.data.state.campaign.years[-1])
	_check(maps.size() == 2 and maps[0] != maps[1], "same seed and direction with different experiences can change the following map")
	_run = saved
	_rng = saved_rng

func _test_direction_change() -> void:
	_check(_checkpoints.has("change"), "year-two route exposes a late direction-change service")
	if not _checkpoints.has("change"): return
	var saved := _run
	var saved_rng := _rng.duplicate(true)
	var source: RunState = _checkpoints.change.copy_for_write()
	var frozen: Array = source.campaign.years.duplicate(true)
	var result := _service.apply(source, GameAction.new(&"choose_campaign", {"offer_id": source.campaign.pending.offer_id, "option_id": "direction_practice"}), _rng)
	_check(result.ok, "late direction change succeeds through the public run command")
	if result.ok:
		_check(result.data.state.campaign.years == frozen, "changing direction cannot rewrite published year-two map")
		if _accept(result):
			_walk("destination")
			_check(_run.campaign.years.size() == 3 and _run.campaign.years[1].profile.direction == "theory" and _run.campaign.years[2].profile.direction == "practice", "changed direction influences year three while preserving year-two generation input")
	_run = saved
	_rng = saved_rng

func _test_snapshot_compatibility() -> void:
	var session := SessionState.new()
	session.run = _checkpoints.start.copy_for_write()
	session.random_snapshot = _rng.duplicate(true)
	var snapshot := SnapshotCodec.encode_session(session, _catalog.get_info())
	_check(snapshot.ok and SnapshotCodec.decode_session(snapshot.data, _catalog).ok, "version-two public snapshot roundtrip")
	if not snapshot.ok: return
	var damaged: Dictionary = snapshot.data.duplicate(true)
	damaged.content_hash = "0".repeat(64)
	damaged.checksum = SnapshotCodec.compute_checksum(damaged)
	_check(not SnapshotCodec.decode_session(damaged, _catalog).ok, "unknown content hash still rejects")
	damaged = snapshot.data.duplicate(true)
	damaged.content_hash = ContentDB.LEGACY_FOUR_YEAR_HASH
	damaged.checksum = SnapshotCodec.compute_checksum(damaged)
	_check(not SnapshotCodec.decode_session(damaged, _catalog).ok, "legacy content exception cannot be applied to version-two maps")
	for legacy_layout in [false, true]:
		session.run.campaign = CampaignService.initial()
		session.run.nodes = CampaignMap.build(session.run.run_id, legacy_layout)
		var legacy := SnapshotCodec.encode_session(session, _catalog.get_info())
		_check(legacy.ok, "legacy fixed map still encodes")
		if legacy.ok:
			legacy.data.content_hash = "0936881b5f4eedc6cb63fb51676b1dfaa46000966d04a34aa2382f6ae7d9bbd2"
			legacy.data.checksum = SnapshotCodec.compute_checksum(legacy.data)
			_check(SnapshotCodec.decode_session(legacy.data, _catalog).ok, "known unchanged legacy content remains loadable")
	_test_changed_legacy_definition(session)

func _test_changed_legacy_definition(session: SessionState) -> void:
	var fixture_root := "user://adaptive-map-altered-content"
	DirAccess.make_dir_recursive_absolute(fixture_root + "/definitions")
	DirAccess.make_dir_recursive_absolute(fixture_root + "/manifests")
	for relative in ["manifests/campus_four_year.json", "definitions/characters.json", "definitions/cards.json", "definitions/relics.json", "definitions/tasks.json", "definitions/encounters.json", "definitions/units.json", "definitions/scenes.json", "definitions/events.json", "definitions/statuses.json", "definitions/rulesets.json"]:
		var file := FileAccess.open(fixture_root + "/" + relative, FileAccess.WRITE)
		_check(file != null, "isolated altered-content fixture can be written")
		if file == null: return
		file.store_string(FileAccess.get_file_as_string("res://data/four_year/" + relative))
		file.close()
	var tasks: Array = SnapshotCodec.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(fixture_root + "/definitions/tasks.json")))
	for task in tasks:
		if task.id == "FY_B4_TASK": task.phases[0].work_max += 1
	var altered := FileAccess.open(fixture_root + "/definitions/tasks.json", FileAccess.WRITE)
	altered.store_string(JSON.stringify(tasks))
	altered.close()
	var changed := ContentDB.new(fixture_root)
	var loaded := changed.load("campus_four_year")
	_check(loaded.ok, "altered legacy definition is otherwise valid content")
	if not loaded.ok: return
	var snapshot := SnapshotCodec.encode_session(session, _catalog.get_info())
	_check(snapshot.ok, "legacy fixture snapshot encodes")
	if not snapshot.ok: return
	snapshot.data.content_hash = ContentDB.LEGACY_FOUR_YEAR_HASH
	snapshot.data.checksum = SnapshotCodec.compute_checksum(snapshot.data)
	_check(not SnapshotCodec.decode_session(snapshot.data, changed).ok, "known old hash cannot bypass an altered historical definition")

func _test_destinations() -> void:
	var signatures := {}
	for destination in ["job", "exam", "research", "abroad"]:
		var encounter_id: String = "FY_ROUTE_" + destination
		var definition := _catalog.get_definition("encounter", encounter_id)
		_check(definition.ok, "distinct destination encounter enabled: " + destination)
		if not definition.ok: continue
		var task: Dictionary = _catalog.get_definition("task", definition.data.members[0]).data
		var work := 0
		for phase in task.phases:
			work += int(phase.work_max)
			var pressure := 0
			var shield := 0
			for intent in phase.intents:
				pressure += int(intent.get("pressure", 0))
				shield += int(intent.get("shield", 0))
			_check(pressure == 22 and shield == 8, "destination keeps common annual pressure/shield budget")
		_check(work == 115 and definition.data.base_ddl == 10, "destination keeps common workload and DDL budget")
		signatures[SnapshotCodec.canonical_json(task.phases.map(func(phase): return phase.intents))] = true
		var fixture: RunState = _checkpoints.start
		var battle := BattleEngine.new(_catalog).begin({"battle_id": encounter_id, "node_id": encounter_id, "encounter_id": encounter_id, "character_id": fixture.character_id, "difficulty": "normal", "vitality": fixture.max_vitality, "max_vitality": fixture.max_vitality, "cards": fixture.cards.map(func(card): return {"card_id": card.card_id, "definition_id": card.definition_id, "upgrade_level": card.upgrade_level}), "relics": [], "rng_state": _rng})
		_check(battle.ok, "destination enters real BattleEngine: " + destination)
		if battle.ok:
			_check(BattleCodec.decode(battle.data.state.to_dictionary(), _catalog).ok, "destination battle can be saved: " + destination)
	_check(signatures.size() == 4, "four destinations have different real intent timing")

func _check(ok: bool, message: String) -> void:
	_assertions += 1
	if not ok:
		_failures.append("adaptive maps: " + message)
