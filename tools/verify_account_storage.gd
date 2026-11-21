extends SceneTree

const ACCOUNT_A := "9f662bc1-98c5-42ff-b18c-733c738f2e1c"
const ACCOUNT_B := "f3bb2ee1-6d6f-464e-b46b-f831a1499e5b"
const ACCOUNT_LEGACY := "bb9ee809-fad0-41ef-9a9d-928944f41017"

var failures: Array[String] = []
var records: Array[String] = []
var checkpoints: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)


func _command(session: GameSession, kind: StringName, data: Dictionary = {}) -> ActionResult:
	var view := session.get_view()
	return session.submit(CommandContext.new(str(view.run_id), view.revision), GameAction.new(kind, data))


func _run() -> void:
	var base := SaveStore.new("user://account-test-guest")
	var session := GameSession.new(base)
	session.run_recorded.connect(func(kind: String, _run: Dictionary, _detail: Dictionary): records.append(kind))
	session.checkpoint_saved.connect(func(slot: String, snapshot: Dictionary):
		checkpoints.append("%s:%s" % [slot, snapshot.checksum]))
	_require(session.use_account_storage(ACCOUNT_A), "select first account")
	var created := session.start_run(StartRunRequest.new("P01", &"normal", GameSession.NEW_RUN_MANIFEST, "42"))
	if not created.accepted:
		printerr("Unable to start production fixture: ", created.error.to_dictionary())
		session.free()
		quit(1)
		return
	_require(records.count("start") == 1, "accepted real start reported once")
	_require(not session.use_account_storage(ACCOUNT_B), "live session prevents account switching")
	var node := str(created.view.run.reachable_node_ids[0])
	_require(_command(session, &"enter_node", {"node_id": node}).accepted, "enter actual first battle")
	_require(_command(session, &"end_turn").accepted, "advance actual first battle")
	var checked := session.cloud_snapshot("current_run")
	if not checked.ok:
		printerr("Missing actual stable checkpoint")
		session.free()
		quit(1)
		return
	var canonical := SnapshotCodec.canonical_json(checked.data)
	var parsed: Dictionary = SnapshotCodec.normalize_numbers(JSON.parse_string(canonical))
	_require(SnapshotCodec.checksum_matches(parsed), "canonical UTF-8 round trip")
	var restored := GameSession.new(base)
	_require(restored.use_account_storage(ACCOUNT_B), "select second account cache")
	_require(not restored.cloud_snapshot("current_run").ok, "second account has no first account file")
	_require(restored.restore_cloud_snapshot("current_run", parsed).ok, "validate and install incoming snapshot")
	_require(restored.continue_run().ok, "continue through existing public boundary")
	var restored_view := restored.get_view()
	var original_view := session.get_view()
	_require(restored_view.run == original_view.run and restored_view.battle == original_view.battle, "run and battle views identical")
	_require(restored_view.revision == original_view.revision, "same visible revision")
	_require(restored._state.random_snapshot == session._state.random_snapshot, "random streams identical")
	_require(_command(restored, &"end_turn").accepted and _command(session, &"end_turn").accepted, "same next command accepted")
	_require(restored.cloud_snapshot("current_run").data.checksum == session.cloud_snapshot("current_run").data.checksum, "same next command preserves deterministic snapshot")
	var unoptimized := SaveStore.new("user://account-test-baseline")
	var optimized := SaveStore.new("user://account-test-optimized", true)
	var earlier: Dictionary = session.cloud_snapshot("current_run").data
	_require(_command(session, &"end_turn").accepted, "advance before benchmarking writes")
	var latest: Dictionary = session.cloud_snapshot("current_run").data
	for store in [unoptimized, optimized]:
		_require(store.save("current_run", earlier).ok and store.save("current_run", latest).ok, "seed save and backup")
	var baseline_times: Array[float] = []
	var optimized_times: Array[float] = []
	for index in 8:
		for pair in [[unoptimized, baseline_times], [optimized, optimized_times]]:
			var before := Time.get_ticks_usec()
			_require(pair[0].save("current_run", latest).ok, "repeat verified snapshot")
			pair[1].append((Time.get_ticks_usec() - before) / 1000.0)
	baseline_times.sort()
	optimized_times.sort()
	_require(unoptimized.load_backup("current_run").data.checksum == latest.checksum, "baseline rotates duplicate over backup")
	_require(optimized.load_backup("current_run").data.checksum == earlier.checksum, "identical save keeps older valid backup")
	var finished := session.get_view()
	for index in 24:
		if finished.terminal_summary != null:
			break
		var next := _command(session, &"end_turn")
		if not next.accepted:
			break
		finished = next.view
	_require(records.count("first_battle") == 1, "first battle result reported once")
	_require(records.count("finish") == 1, "terminal summary reported once")
	_require(session.cloud_snapshot("profile").ok, "terminal profile saved")
	_require(not base.load("current_run").ok, "guest cache remains isolated")
	_check_legacy_cloud(base)
	print("ACCOUNT_STORAGE_CHECKS=", JSON.stringify({
		"failures": failures,
		"snapshot_bytes": canonical.to_utf8_buffer().size(),
		"baseline_repeat_ms_p50": baseline_times[4],
		"baseline_repeat_ms_p95": baseline_times.back(),
		"optimized_repeat_ms_p50": optimized_times[4],
		"optimized_repeat_ms_p95": optimized_times.back(),
		"observed_checkpoints": checkpoints.size(),
		"events": records,
		"battle_round": parsed.payload.battle.round_index
	}))
	restored.free()
	session.free()
	quit(1 if not failures.is_empty() else 0)


func _check_legacy_cloud(base: SaveStore) -> void:
	var catalog := ContentDB.new("res://data/four_year")
	if not catalog.load_legacy_relic_catalog(RelicPilot.ROSTER).ok:
		_require(false, "load previous FY catalog")
		return
	var content := catalog.get_info()
	var service := RunService.new(catalog)
	var made := service.create(StartRunRequest.new("P01", &"normal", content.id, "42"))
	if not made.ok:
		_require(false, "build a legal previous FY run")
		return
	var fixture := SessionState.new()
	fixture.run = made.data.state
	fixture.random_snapshot = made.data.rng_states
	service.transactions().add_relic(fixture.run, "FY_Y1_1", "", 0)
	service.transactions().add_relic(fixture.run, "RX-C01", "", 1)
	var old := SnapshotCodec.encode_session(fixture, content)
	if not old.ok:
		_require(false, "encode previous FY snapshot")
		return
	var legacy := GameSession.new(base)
	_require(legacy.use_account_storage(ACCOUNT_LEGACY), "select isolated legacy cache")
	_require(legacy.restore_cloud_snapshot("current_run", old.data).ok, "accept legacy FY cloud snapshot")
	var corrupted: Dictionary = old.data.duplicate(true)
	corrupted.content_hash = "a".repeat(64)
	corrupted.checksum = SnapshotCodec.compute_checksum(corrupted)
	_require(not legacy.restore_cloud_snapshot("current_run", corrupted).ok, "unknown content cannot replace a good save")
	_require(legacy.continue_run().ok, "continue and migrate legacy cloud snapshot")
	if legacy._state != null:
		_require(legacy._state.random_snapshot == fixture.random_snapshot, "FY migration preserves the four random streams")
		_require(legacy._state.run.relics.size() == 1 and legacy._state.run.relics[0].slot == 1, "retain the selected RX at the original slot")
		_require(legacy.cloud_snapshot("current_run").data.checksum == old.data.checksum, "read preserves original FY snapshot")
	legacy.free()
