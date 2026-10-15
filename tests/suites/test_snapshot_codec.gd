extends RefCounted

var _failures: Array[String] = []
var _checks := 0
var _catalog: ContentDB


func run() -> Array[String]:
	_catalog = ContentDB.new("res://tests/fixtures/run_flow", true)
	_check(_catalog.load("test_run_g4").ok, "fixture loads")
	var service := RunService.new(_catalog)
	var created := service.create(
		{
			"character_id": "test_P01",
			"difficulty": "normal",
			"manifest_id": "test_run_g4",
			"seed": "42"
		}
	)
	_check(created.ok, "initial run")
	if not created.ok:
		return _failures
	var session := SessionState.new()
	session.run = created.data.state
	session.random_snapshot = created.data.rng_states.duplicate(true)
	session.random_snapshot.streams.battle.seed = "9223372036854775807"
	session.random_snapshot.streams.battle.state = "-9223372036854775808"
	var encoded := SnapshotCodec.encode_session(session, _catalog.get_info())
	_check(encoded.ok, "encode exact int64 RNG strings")
	if not encoded.ok:
		return _failures
	var base: Dictionary = encoded.data
	var parsed: Dictionary = JSON.parse_string(SnapshotCodec.canonical_json(base))
	var decoded := SnapshotCodec.decode_session(parsed, _catalog)
	_check(decoded.ok, "decode raw JSON with integer-valued floats")
	if decoded.ok:
		var again := SnapshotCodec.encode_session(decoded.data, _catalog.get_info())
		_check(again.ok and again.data == base, "complete checksum and 64-bit RNG roundtrip")
	_check(
		SnapshotCodec.canonical_json({"z": 1.0, "a": [2, 1]}) == '{"a":[2,1],"z":1}',
		"canonical keys and array order"
	)
	_check(SnapshotCodec.checksum_matches(parsed), "checksum survives raw JSON parse")
	for field in ["content_version", "content_hash", "manifest_id"]:
		var bad := base.duplicate(true)
		bad[field] = "incompatible"
		_reject(bad, &"VERSION_MISMATCH", field)
	var bad := base.duplicate(true)
	bad.schema_version = 99
	_reject(bad, &"VERSION_MISMATCH", "schema version")
	bad = base.duplicate(true)
	bad.random_state.algorithm_version = 99
	_reject(bad, &"VERSION_MISMATCH", "RNG algorithm")
	bad = base.duplicate(true)
	bad.random_state.streams.erase("event")
	_reject(bad, &"SAVE_CORRUPT", "missing random stream")
	bad = base.duplicate(true)
	bad.random_state.streams.battle.state = 42
	_reject(bad, &"SAVE_CORRUPT", "RNG state must be decimal string")
	bad = base.duplicate(true)
	bad.payload.run.money += 1
	var checksum_error := SnapshotCodec.decode_session(bad, _catalog)
	_check(
		not checksum_error.ok and checksum_error.error.code == &"SAVE_CORRUPT",
		"checksum catches corruption"
	)
	bad = base.duplicate(true)
	bad.erase("revision")
	_reject(bad, &"SAVE_CORRUPT", "missing outer key")
	bad = base.duplicate(true)
	bad["unexpected"] = true
	_reject(bad, &"SAVE_CORRUPT", "unknown outer key")
	bad = base.duplicate(true)
	bad.payload["unexpected"] = true
	_reject(bad, &"SAVE_CORRUPT", "unknown session key")
	bad = base.duplicate(true)
	bad.run_id = "other-run"
	_reject(bad, &"SAVE_CORRUPT", "inner outer identity mismatch")
	bad = base.duplicate(true)
	bad.payload.profile_merge_pending = true
	_reject(bad, &"SAVE_CORRUPT", "merge requires finalized summary")
	bad = base.duplicate(true)
	bad.payload.event_log = [
		{
			"run_id": session.run.run_id,
			"revision": 1,
			"index": 0,
			"type": "test",
			"source_id": "",
			"target_ids": [],
			"data": {},
			"source_label": "",
			"target_labels": []
		}
	]
	_reject(bad, &"SAVE_CORRUPT", "future log revision")
	bad = base.duplicate(true)
	bad.payload.event_log = [
		{
			"run_id": session.run.run_id,
			"revision": 0,
			"index": 0,
			"type": "test",
			"source_id": "",
			"target_ids": ["x"],
			"data": {},
			"source_label": "",
			"target_labels": []
		}
	]
	_reject(bad, &"SAVE_CORRUPT", "log target label mismatch")
	session.pending_choice = ChoiceRequest.new("choice", &"discard")
	var pending := SnapshotCodec.encode_session(session, _catalog.get_info())
	_check(
		not pending.ok and pending.error.code == &"CHOICE_PENDING", "pending session cannot encode"
	)
	session.pending_choice = null
	_migrations(base)
	_documents()
	_battle_and_summary(service, session)
	print("G5_SNAPSHOT_EVIDENCE=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures


func _migrations(base: Dictionary) -> void:
	var old := base.duplicate(true)
	old.schema_version = 0
	old["checksum"] = SnapshotCodec.compute_checksum(old)
	var original := old.duplicate(true)
	var no_path := SnapshotCodec.migrate(old)
	_check(not no_path.ok and no_path.error.code == &"VERSION_MISMATCH", "no implicit migration")
	var result := SnapshotCodec.migrate(JSON.parse_string(JSON.stringify(old)), {0: _schema_one})
	_check(result.ok and result.data == base, "migration on parsed JSON recalculates checksum")
	_check(old == original, "migration leaves source intact")
	var cycle := SnapshotCodec.migrate(old, {0: _schema_two, 2: _schema_zero})
	_check(
		not cycle.ok and cycle.error.code == &"VERSION_MISMATCH", "migration cycle refuses safely"
	)
	var invalid := SnapshotCodec.migrate(old, {0: func(_value): return null})
	_check(not invalid.ok and invalid.error.code == &"SAVE_CORRUPT", "invalid migration output")


func _schema_one(value: Dictionary) -> Dictionary:
	value.schema_version = 1
	return value


func _schema_two(value: Dictionary) -> Dictionary:
	value.schema_version = 2
	return value


func _schema_zero(value: Dictionary) -> Dictionary:
	value.schema_version = 0
	return value


func _documents() -> void:
	var profile := ProfileMerge.default_profile()
	var document := SnapshotCodec.encode_document("profile", profile)
	_check(document.ok, "profile document")
	var decoded := SnapshotCodec.decode_document(
		JSON.parse_string(JSON.stringify(document.data)), "profile"
	)
	_check(decoded.ok and decoded.data.payload == profile, "document raw JSON roundtrip")
	var wrong := SnapshotCodec.decode_document(document.data, "settings")
	_check(not wrong.ok and wrong.error.code == &"VERSION_MISMATCH", "document kind distinct")
	var unknown := SnapshotCodec.encode_document("unknown", {})
	_check(not unknown.ok and unknown.error.code == &"INVALID_ARGUMENT", "document kind allowlist")
	var unsafe := SnapshotCodec.encode_document("settings", {"unsafe": 9007199254740992})
	_check(not unsafe.ok and unsafe.error.code == &"SAVE_CORRUPT", "unsafe JSON integer refused")
	unsafe = SnapshotCodec.encode_document("settings", {"unsafe": NAN})
	_check(not unsafe.ok and unsafe.error.code == &"SAVE_CORRUPT", "non-finite JSON number refused")


func _battle_and_summary(service: RunService, initial: SessionState) -> void:
	var node_id: String = initial.run.reachable_node_ids()[0]
	var entered := service.apply(
		initial.run, GameAction.new(&"enter_node", {"node_id": node_id}), initial.random_snapshot
	)
	_check(entered.ok, "battle entry")
	if not entered.ok:
		return
	var begun := BattleEngine.new(_catalog).begin(entered.data.battle_input)
	_check(begun.ok, "battle starts")
	if not begun.ok:
		return
	var active := initial.copy_for_write()
	active.run = entered.data.state
	active.battle = begun.data.state
	active.random_snapshot = begun.data.rng_state
	var encoded := SnapshotCodec.encode_session(active, _catalog.get_info())
	_check(encoded.ok, "active battle snapshot")
	if encoded.ok:
		var bad: Dictionary = encoded.data.duplicate(true)
		var card_id: String = bad.payload.battle.zones.hand[0]
		bad.payload.battle.card_by_id[card_id].origin_card_id = "missing-permanent-card"
		_reject(bad, &"SAVE_CORRUPT", "battle permanent origin")
		bad = encoded.data.duplicate(true)
		bad.payload.battle.battle_id = "unrelated-battle"
		_reject(bad, &"SAVE_CORRUPT", "battle/run identity")
	var temporary := active.copy_for_write()
	temporary.battle.card_by_id[temporary.battle.zones.hand[0]].origin_card_id = ""
	var temporary_snapshot := SnapshotCodec.encode_session(temporary, _catalog.get_info())
	_check(temporary_snapshot.ok, "temporary card without permanent origin is valid")
	if temporary_snapshot.ok:
		_check(
			SnapshotCodec.decode_session(temporary_snapshot.data, _catalog).ok,
			"temporary card snapshot restores"
		)
	_task_status_lifecycle(active)
	var abandoned := service.apply(
		initial.run, GameAction.new(&"abandon_run", {"confirmed": true}), initial.random_snapshot
	)
	_check(abandoned.ok, "finalize summary")
	if not abandoned.ok:
		return
	var terminal := initial.copy_for_write()
	terminal.run = abandoned.data.state
	terminal.random_snapshot = abandoned.data.rng_states
	terminal.terminal_summary = abandoned.data.run_summary
	terminal.profile_merge_pending = true
	encoded = SnapshotCodec.encode_session(terminal, _catalog.get_info())
	_check(encoded.ok, "terminal snapshot")
	if encoded.ok:
		var bad: Dictionary = encoded.data.duplicate(true)
		bad.payload.terminal_summary.run_id = "other-run"
		_reject(bad, &"SAVE_CORRUPT", "terminal summary identity")
		bad = encoded.data.duplicate(true)
		bad.payload.terminal_summary.result = "won"
		_reject(bad, &"SAVE_CORRUPT", "terminal summary outcome")


func _task_status_lifecycle(active: SessionState) -> void:
	var engine := BattleEngine.new(_catalog)
	var task_definition: Dictionary = _catalog._definitions.task[
		active.battle.tasks[0].definition_id
	]
	var original_phases: Array = task_definition.phases.duplicate(true)
	var next_phase: Dictionary = original_phases[0].duplicate(true)
	next_phase.phase_key = "second"
	task_definition.phases.append(next_phase)
	var state := active.battle.copy()
	var rng := active.random_snapshot.duplicate(true)
	for label in ["phase advance", "final departure"]:
		if state.tasks.is_empty():
			break
		var events: Array[RuleEvent] = []
		var old_id: String = state.tasks[0].task_id
		_check(
			(
				engine
				. _gain_status_on_target(
					state, {"status": "extra_requirements", "stacks": 1}, old_id, events
				)
				. ok
			),
			"attach task status before " + label
		)
		var draft := ActionDraft.new(
			&"play_card", {"card_instance_id": state.zones.hand[0], "target_ids": [old_id]}
		)
		var result := engine.apply(state, draft, rng)
		_check(result.ok, "complete task with status at " + label)
		if not result.ok:
			break
		state = result.data.state
		rng = result.data.rng_state
		var stale := false
		for status in state.statuses:
			stale = stale or status.target_id == old_id
		_check(not stale, "departed task no longer holds status at " + label)
		var encoded := BattleCodec.encode(state)
		_check(encoded.ok, "stable battle encodes after " + label)
		if encoded.ok:
			_check(
				BattleCodec.decode(encoded.data, _catalog).ok,
				"stable battle persists after " + label
			)
		if label == "phase advance":
			_check(
				not state.tasks.is_empty() and state.tasks[0].task_id != old_id,
				"new phase has fresh task identity"
			)
	_check(state.phase == "finished" and state.tasks.is_empty(), "status lifecycle reaches victory")
	task_definition.phases = original_phases


func _reject(snapshot: Dictionary, code: StringName, label: String) -> void:
	snapshot["checksum"] = SnapshotCodec.compute_checksum(snapshot)
	var before := snapshot.duplicate(true)
	var result := SnapshotCodec.decode_session(snapshot, _catalog)
	_check(not result.ok and result.error.code == code, "reject " + label)
	_check(snapshot == before, "failed decode leaves caller intact " + label)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("G5 snapshot: " + label)
