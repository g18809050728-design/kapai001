extends RefCounted

const NEW_RELICS := {
	"white": ["A25", "A26", "A27", "A28", "A29", "A30", "A31", "A32"],
	"blue": ["A33", "A34", "A35", "A36", "A37", "A38", "A39", "A40"],
	"purple": ["A41", "A42", "A43", "A44", "A45", "A46"],
	"gold": ["A47", "A48"],
}


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	_check(loaded.ok, "production manifest loads", failures)
	if not loaded.ok:
		return failures
	_check_offers(catalog, failures)
	_check_continuation(failures)
	if failures.is_empty():
		print("RELIC_INTEGRATION_SUITE=passed")
	return failures


func _check_offers(catalog: ContentDB, failures: Array[String]) -> void:
	var service := RunService.new(catalog)
	var created := service.create({
		"character_id": "P01", "difficulty": "normal",
		"manifest_id": "campus_mvp", "seed": "42"
	})
	_check(created.ok, "production run is created", failures)
	if not created.ok:
		return
	var run_state: RunState = created.data.state
	var generator := service.rewards()
	var original: Dictionary = run_state.to_dictionary()
	for rarity in NEW_RELICS:
		var full_pool := generator.relic_candidates(
			run_state, 100, RandomSource.new("pool-" + rarity), {}, rarity
		)
		_check(full_pool.ok, "%s reward pool can be sampled" % rarity, failures)
		if full_pool.ok:
			for relic_id in NEW_RELICS[rarity]:
				_check(full_pool.data.has(relic_id), "%s reaches the reward sampler" % relic_id, failures)
	var rng := RandomSource.new("42")
	var before: Dictionary = rng.export_state().to_dictionary()
	var first := _generate_offers(generator, run_state, rng, failures)
	if first.is_empty():
		return
	var after: Dictionary = rng.export_state().to_dictionary()
	_check(after.streams.reward != before.streams.reward, "offers advance reward RNG", failures)
	for stream in ["map", "event", "battle"]:
		_check(after.streams[stream] == before.streams[stream], "%s RNG is isolated" % stream, failures)
	_check(run_state.to_dictionary() == original, "offer generation does not mutate run", failures)
	var replay_rng := RandomSource.new("42")
	var replay := _generate_offers(generator, run_state, replay_rng, failures)
	_check(
		replay == first and replay_rng.export_state().to_dictionary() == after,
		"same seed repeats elite, boss, shop and all RNG states", failures
	)
	for kind in ["elite", "boss"]:
		var relic_item: Dictionary = _relic_item(first[kind].items)
		_check(not relic_item.is_empty(), "%s offers a relic" % kind, failures)
		for relic_id in relic_item.get("candidates", []):
			var definition := catalog.get_definition("relic", str(relic_id))
			_check(definition.ok, "%s reward relic resolves" % kind, failures)
			if definition.ok:
				_check(
					definition.data.rarity in NEW_RELICS.keys()
					and definition.data.availability == "drop",
					"%s reward relic has eligible rarity and availability" % kind, failures
				)
	var shop_rarities: Array[String] = []
	for stock in first.shop.stocks:
		if stock.kind != "relic":
			continue
		var definition := catalog.get_definition("relic", str(stock.definition_id))
		_check(definition.ok, "shop relic resolves", failures)
		if definition.ok:
			shop_rarities.append(str(definition.data.rarity))
			_check(
				definition.data.rarity in ["white", "blue"]
				and definition.data.availability == "drop",
				"shop excludes purple, gold and starter relics", failures
			)
	_check(shop_rarities.has("white") and shop_rarities.has("blue"), "shop fills white and blue relic slots", failures)
	print("RELIC_OFFER_EVIDENCE=", SnapshotCodec.canonical_json({
		"seed": "42", "elite": _relic_item(first.elite.items).get("candidates", []),
		"boss": _relic_item(first.boss.items).get("candidates", []),
		"shop": first.shop.stocks.filter(func(stock): return stock.kind == "relic"),
		"rng": after
	}))


func _generate_offers(
	generator: RewardGenerator, run_state: RunState, rng: RandomSource,
	failures: Array[String]
) -> Dictionary:
	var elite := generator.generate({"node_id": "relic_elite", "kind": "elite"}, run_state, rng)
	var boss := generator.generate({"node_id": "relic_boss", "kind": "boss"}, run_state, rng)
	var shop := generator.generate_shop({"node_id": "relic_shop"}, run_state, rng)
	_check(elite.ok and boss.ok and shop.ok, "production elite, boss and shop generate", failures)
	if not elite.ok or not boss.ok or not shop.ok:
		return {}
	return {
		"elite": elite.data.to_dictionary(),
		"boss": boss.data.to_dictionary(),
		"shop": shop.data.to_dictionary(),
	}


func _relic_item(items: Array) -> Dictionary:
	for item: Dictionary in items:
		if item.kind == "relic":
			return item
	return {}


func _check_continuation(failures: Array[String]) -> void:
	var root := "user://relic-integration-%s-%s" % [Time.get_ticks_usec(), OS.get_process_id()]
	var control := GameSession.new(SaveStore.new(root + "/control"))
	_check(control.update_settings({"autosave": false}).ok, "control uses isolated saves", failures)
	var started := control.start_run(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	_check(started.accepted, "production control session starts", failures)
	if not started.accepted:
		control.free()
		return
	TransactionResolver.new(control._catalog).add_relic(control._state.run, "A31", "", 1)
	for card in control._state.run.cards:
		card.definition_id = "K02"
	var initial := SnapshotCodec.encode_session(control._state, control._catalog.get_info())
	_check(initial.ok, "A31 initial session snapshot encodes", failures)
	if not initial.ok:
		control.free()
		return
	var resume_store := SaveStore.new(root + "/resumed")
	var copied := resume_store.save("current_run", initial.data)
	_check(copied.ok, "A31 initial snapshot copies to isolated resume store", failures)
	if not copied.ok:
		control.free()
		return
	var resumed := GameSession.new(resume_store)
	_check(resumed.update_settings({"autosave": false}).ok, "resume uses isolated saves", failures)
	var continued := resumed.continue_run()
	_check(continued.ok, "A31 initial session continues", failures)
	if not continued.ok:
		control.free()
		resumed.free()
		return
	_compare_sessions(control, resumed, "initial restore", failures)
	var node_id: String = control.get_view().run.reachable_node_ids[0]
	if not _pair(control, resumed, &"enter_node", {"node_id": node_id}, failures):
		control.free()
		resumed.free()
		return
	_check(control._state.battle != null, "production battle opens with A31", failures)
	if control._state.battle == null:
		control.free()
		resumed.free()
		return
	var first_card: String = control._state.battle.zones.hand[0]
	if not _pair(control, resumed, &"play_card", {
		"card_instance_id": first_card, "target_ids": []
	}, failures):
		control.free()
		resumed.free()
		return
	var counter_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_BATTLE, "relic_hook:A31:0", &"hook"
	)
	_check(
		int(control._state.battle.counters.get(counter_key, 0)) == 1,
		"A31 discount is spent before save", failures
	)
	var before_save := SnapshotCodec.encode_session(resumed._state, resumed._catalog.get_info())
	var saved := resumed.save_and_exit()
	_check(before_save.ok and saved.ok, "A31 battle saves at a stable boundary", failures)
	resumed.free()
	if not before_save.ok or not saved.ok:
		control.free()
		return
	resumed = GameSession.new(resume_store)
	continued = resumed.continue_run()
	_check(continued.ok, "A31 battle resumes from disk", failures)
	if not continued.ok:
		control.free()
		resumed.free()
		return
	var after_save := SnapshotCodec.encode_session(resumed._state, resumed._catalog.get_info())
	_check(
		after_save.ok and after_save.data == before_save.data,
		"A31 state and RNG survive disk roundtrip", failures
	)
	_compare_sessions(control, resumed, "battle restore", failures)
	var next_card: String = control._state.battle.zones.hand[0]
	if _pair(control, resumed, &"play_card", {
		"card_instance_id": next_card, "target_ids": []
	}, failures):
		_check(
			int(control._state.battle.counters.get(counter_key, 0)) == 1
			and int(resumed._state.battle.counters.get(counter_key, 0)) == 1,
			"A31 does not refresh after save and continue", failures
		)
	control.free()
	resumed.free()


func _pair(
	control: GameSession, resumed: GameSession, type: StringName,
	payload: Dictionary, failures: Array[String]
) -> bool:
	var first := _submit(control, type, payload)
	var second := _submit(resumed, type, payload)
	_check(first.accepted and second.accepted, "paired %s succeeds" % type, failures)
	if not first.accepted or not second.accepted:
		return false
	_compare_sessions(control, resumed, "after " + String(type), failures)
	return true


func _submit(session: GameSession, type: StringName, payload: Dictionary) -> ActionResult:
	var view := session.get_view()
	return session.submit(
		CommandContext.new(view.run_id, view.revision), GameAction.new(type, payload)
	)


func _compare_sessions(
	control: GameSession, resumed: GameSession, label: String,
	failures: Array[String]
) -> void:
	var control_snapshot := SnapshotCodec.encode_session(control._state, control._catalog.get_info())
	var resumed_snapshot := SnapshotCodec.encode_session(resumed._state, resumed._catalog.get_info())
	_check(control_snapshot.ok and resumed_snapshot.ok, label + " snapshots encode", failures)
	if not control_snapshot.ok or not resumed_snapshot.ok:
		return
	_check(
		SnapshotCodec.canonical_json(control_snapshot.data)
		== SnapshotCodec.canonical_json(resumed_snapshot.data),
		label + " complete state matches uninterrupted control", failures
	)
	for stream in RandomSource.STREAMS:
		_check(
			control_snapshot.data.random_state.streams[stream]
			== resumed_snapshot.data.random_state.streams[stream],
			label + " %s RNG stream matches" % stream, failures
		)


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("relic integration: " + label)
