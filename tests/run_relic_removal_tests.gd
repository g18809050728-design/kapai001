extends SceneTree
## Exercise the public continued-game path with checksum-valid old snapshots.

const ROOT := "res://data/four_year"
const ROSTER_V1_HASH := "ac9279d7d204bc2b59fdf0502db1a4cfbb8604dd72865cb8023a6d96a359fd21"
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var legacy := ContentDB.new(ROOT)
	var pilot := ContentDB.new(ROOT)
	var base := ContentDB.new(ROOT)
	if _ok(legacy.load_legacy_relic_catalog(RelicPilot.ROSTER), "decode-only mixed catalog") and _ok(pilot.load_legacy_relic_catalog(RelicPilot.MANIFEST), "decode-only pilot catalog") and _ok(base.load(RelicPilot.BASE), "decode-only base catalog"):
		_check(legacy.get_info().content_hash == ROSTER_V1_HASH, "original v1 catalog hash matches the preceding release")
		_test_mixed_offer(legacy)
		_test_active_battle(legacy)
		_test_active_battle(pilot, true)
		_test_base_frozen_map(base)
		_test_test_room()
	print("RX_REMOVAL_CHECKS=%d FAILURES=%d" % [_checks, _failures.size()])
	for message in _failures:
		push_error(message)
	quit(0 if _failures.is_empty() else 1)


func _test_mixed_offer(legacy: ContentDB) -> void:
	var fixture := _new_session(legacy)
	if fixture == null:
		return
	var run := fixture.run
	var service := RunService.new(legacy)
	service.transactions().add_relic(run, "RX-C01", "", 0)
	service.transactions().add_relic(run, "FY_Y1_2", "", 1)
	service.transactions().add_relic(run, "RX-C04", "", 2)
	# Stage a legal route to the first reward. Battle wins are controlled.
	for _step in 32:
		run = fixture.run
		var current := run.find_node(run.current_node_id)
		var pending: Dictionary = run.campaign.pending
		var next: GameResult
		if pending.get("kind") == "relic":
			break
		if not pending.is_empty():
			next = _apply(service, fixture, &"choose_campaign", {"offer_id":pending.offer_id,"option_id":"skip"})
		elif not run.active_battle_id.is_empty():
			next = service.settle_battle(run, {"battle_id":run.active_battle_id,"result":"won","remaining_vitality":50}, fixture.random_snapshot)
		elif current != null and current.status == "active":
			if run.pending_reward != null and not run.pending_reward.is_complete():
				next = _apply(service, fixture, &"skip_reward", {"offer_id":run.pending_reward.offer_id,"item_id":run.pending_reward.items[0].item_id})
			elif current.kind == "event" and str(current.context.event.resolved_option_id).is_empty():
				next = _apply(service, fixture, &"choose_event", {"event_instance_id":current.context.event.event_instance_id,"option_id":"leave"})
			elif current.kind == "rest" and not current.context.get("used", false):
				next = _apply(service, fixture, &"take_rest", {"node_id":current.node_id,"option_id":"heal"})
			else:
				next = _apply(service, fixture, &"leave_node", {"node_id":current.node_id})
		else:
			next = _apply(service, fixture, &"enter_node", {"node_id":run.reachable_node_ids().front()})
		if not _ok(next, "stage reward checkpoint"):
			return
		fixture.run = next.data.state
		fixture.random_snapshot = next.data.rng_states
	run = fixture.run
	if not _check(run.campaign.pending.get("kind") == "relic", "normal milestone reached"):
		return
	# Reproduce a v1 mixed offer with a year-one FY gold in the middle.
	run.campaign.pending.candidates = ["RX-C02", "FY_Y1_4", "RX-P01-01"]
	var encoded := SnapshotCodec.encode_session(fixture, legacy.get_info())
	if not _ok(encoded, "old mixed snapshot encodes"):
		return
	var store := _store("mixed")
	if not _ok(store.save("current_run", encoded.data), "old mixed snapshot on disk"):
		return
	var session := GameSession.new(store)
	session._autosave = false
	_check(session.inspect_saves().data.can_continue, "old mixed file is offered in main menu")
	if _ok(session.continue_run(), "continue old mixed file"):
		var now := session._state
		_check(now.run.campaign.pending.candidates == ["RX-C02", "RX-P01-01"] and now.run.campaign.pending.offer_id == run.campaign.pending.offer_id, "same offer ID with original RX in original order")
		_check(now.run.relics == [run.relics[0], run.relics[2]], "remove only FY, retain exact RX slot and instance IDs")
		_check(now.run.campaign.years == run.campaign.years and now.run.node_path == run.node_path and now.run.cards == run.cards and now.run.money == run.money and now.random_snapshot == fixture.random_snapshot and now.revision == fixture.revision, "conversion preserves map, progress, cards, money, revision and all RNG")
		_check(store.load("current_run").data == encoded.data, "continuing does not rewrite current file")
		var forged := GameAction.new(&"choose_campaign", {"offer_id":now.run.campaign.pending.offer_id,"option_id":"claim","candidate_id":"FY_Y1_4"})
		_check(not session.submit(CommandContext.new(now.run.run_id, now.revision), forged).accepted, "retired candidate cannot be claimed")
		if _ok(session.save_current(), "save migrated mixed snapshot"):
			_check(store.load("current_run").data.content_version == RelicPilot.ROSTER_VERSION, "next save writes RX-only version")
			_check(store.load_backup("current_run").data == encoded.data, "old bytes retained by ordinary backup")
			var backup := GameSession.new(store)
			if _ok(backup.restore_backup(), "explicit old backup also migrates"):
				_check(backup._state.run.campaign.pending.candidates == ["RX-C02", "RX-P01-01"], "backup preserves RX order")
			backup.free()
			var reread := GameSession.new(store)
			if _ok(reread.continue_run(), "new snapshot resumes"):
				_check(reread._state.run.to_dictionary() == now.run.to_dictionary(), "migration is not repeated on new snapshot")
			reread.free()
	session.free()


func _test_active_battle(legacy: ContentDB, pilot: bool = false) -> void:
	var fixture := _new_session(legacy)
	if fixture == null:
		return
	var service := RunService.new(legacy)
	service.transactions().add_relic(fixture.run, "FY_Y1_1", "", 0)
	service.transactions().add_relic(fixture.run, "RX-C01", "", 1)
	var node_id := str(fixture.run.reachable_node_ids().front())
	var entered := _apply(service, fixture, &"enter_node", {"node_id":node_id})
	if not _ok(entered, "prepare old stable battle") or not _check(entered.data.battle_input != null, "opening node is a battle"):
		return
	var begun := BattleEngine.new(legacy).begin(entered.data.battle_input)
	if not _ok(begun, "build battle with FY and RX"):
		return
	fixture.run = entered.data.state
	fixture.battle = begun.data.state
	fixture.random_snapshot = begun.data.rng_state
	var encoded := SnapshotCodec.encode_session(fixture, legacy.get_info())
	var store := _store("battle-pilot" if pilot else "battle")
	if not _ok(encoded,"encode old active battle") or not _ok(store.save("current_run", encoded.data), "store old active battle"):
		return
	var session := GameSession.new(store, Callable(), pilot)
	session._autosave = false
	if _ok(session.continue_run(), "continue old active battle"):
		var state := session._state
		var before := fixture.battle.to_dictionary()
		before.relics = ["RX-C01"]
		for key in before.source_registry.keys():
			if before.source_registry[key].definition_id == "FY_Y1_1":
				before.source_registry.erase(key)
		_check(state.battle.to_dictionary() == before and state.random_snapshot == fixture.random_snapshot, "battle preserves everything except retired equipment and source")
		_check(state.run.relics.size() == 1 and state.run.relics[0].slot == 1 and session._catalog.get_candidates({"kind":"relic"}).all(RelicPilot.is_rx), "remaining RX slot stays fixed and no FY definitions are installed")
		_check(session.submit(CommandContext.new(state.run.run_id,state.revision), GameAction.new(&"end_turn")).accepted, "restored battle can actually advance")
	session.free()


func _test_base_frozen_map(base: ContentDB) -> void:
	var runner = preload("res://tests/suites/test_four_year.gd").new()
	if not _check(runner.run().is_empty(), "historical fixed-map fixture runs"):
		return
	var fixture := SessionState.new()
	fixture.run = runner._checkpoints.relic_full
	fixture.random_snapshot = runner._rng
	var before := fixture.run.to_dictionary()
	var offer_id: String = fixture.run.campaign.pending.offer_id
	var encoded := SnapshotCodec.encode_session(fixture, base.get_info())
	var store := _store("base")
	if not _ok(encoded,"encode base FY-only offer") or not _ok(store.save("current_run", encoded.data), "store base FY-only offer"):
		return
	var session := GameSession.new(store)
	if _ok(session.continue_run(), "continue original fixed-map campaign"):
		var run := session._state.run
		_check(run.manifest_id == RelicPilot.ROSTER and run.relics.is_empty(), "old equipped FY are gone, run uses RX version")
		_check(run.campaign.pending.is_empty() and run.campaign.history.back() == {"offer_id":offer_id,"option_id":"skip","candidate_id":""}, "FY-only frozen offer closes without a redraw")
		_check(run.to_dictionary().nodes == before.nodes and run.cards == before.cards and run.money == before.money and session._state.random_snapshot == fixture.random_snapshot, "legacy nodes, deck, money and RNG unchanged")
		_check(run.campaign.version == 1 and CampaignService.relic_layers(run) == CampaignService.relic_layers(fixture.run), "legacy map generator and reward layers stay fixed")
		_check(not run.reachable_node_ids().is_empty() and session.get_view().screen == &"map", "no empty reward page or progression block")
	session.free()


func _test_test_room() -> void:
	var store := TestStore.new("user://remove-test-room-%d" % Time.get_ticks_usec())
	var room := TestRoomService.new(store)
	for kind in ["snapshot", "record"]:
		var file := store.save(kind, "old-" + kind, "old relic fixture", {"core":{"config":{"relics":["FY_Y1_1"]}}})
		if _ok(file, "store old test-room " + kind):
			var result := room.load_snapshot("old-" + kind) if kind == "snapshot" else room.load_record("old-" + kind)
			_check(not result.accepted and result.error.message_key == &"test.file.retired_relic" and room.state == null, "old test data cannot re-enable FY: " + kind)


func _new_session(catalog: ContentDB) -> SessionState:
	var result := RunService.new(catalog).create(StartRunRequest.new("P01", &"normal", catalog.get_info().id, "42"))
	if not _ok(result, "create legacy fixture"):
		return null
	var out := SessionState.new()
	out.run = result.data.state
	out.random_snapshot = result.data.rng_states
	return out


func _apply(service: RunService, fixture: SessionState, command: StringName, payload: Dictionary) -> GameResult:
	return service.apply(fixture.run, GameAction.new(command, payload), fixture.random_snapshot)


func _store(suffix: String) -> SaveStore:
	return SaveStore.new("user://rx-removal-%s-%d" % [suffix, Time.get_ticks_usec()])


func _ok(result: GameResult, message: String) -> bool:
	return _check(result != null and result.ok, message + (": " + str(result.error.to_dictionary()) if result != null and not result.ok else ""))


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition
