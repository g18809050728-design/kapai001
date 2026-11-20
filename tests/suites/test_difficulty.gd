extends RefCounted

var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	var catalog := ContentDB.new("res://data/four_year")
	_check(catalog.load("campus_four_year").ok, "production catalog loads")
	_check(catalog.accepts_previous_four_year_hash(ContentDB.PREVIOUS_FOUR_YEAR_HASH), "strict reconstruction proves the previous content hash")
	var rules: Dictionary = catalog.get_definition("ruleset", catalog.get_info().ruleset_id).data
	var maps: Array = []
	var streams: Array = []
	var ddls: Array[int] = []
	for difficulty in ["relaxed", "normal", "hard"]:
		var store := SaveStore.new("user://difficulty-%s-%d" % [difficulty, Time.get_ticks_usec()])
		var session := GameSession.new(store)
		session.update_settings({"autosave": false})
		_check(session.start_run(StartRunRequest.new("P01", StringName(difficulty), "campus_four_year", "42")).accepted, "real session starts " + difficulty)
		var settings: Dictionary = rules.difficulty_overrides[difficulty]
		_check(session._state.run.vitality == settings.starting_vitality and session._state.run.max_vitality == settings.starting_vitality, "starting vitality is applied " + difficulty)
		maps.append(session._state.run.campaign.years.duplicate(true))
		streams.append(session._state.random_snapshot.duplicate(true))
		var view := session.get_view()
		var entered := session.submit(CommandContext.new(str(view.run_id), view.revision), GameAction.new(&"enter_node", {"node_id": view.run.reachable_node_ids[0]}))
		_check(entered.accepted and session._state.battle != null, "real battle starts " + difficulty)
		if session._state.battle == null:
			session.free()
			continue
		var battle: BattleState = session._state.battle
		var encounter: Dictionary = catalog.get_definition("encounter", battle.encounter_id).data
		var scaling: Dictionary = encounter.get("scaling", {})
		_check(
			battle.ddl
			== maxi(
				int(rules.battle.minimum_ddl),
				int(encounter.base_ddl) + int(scaling.get("ddl_bonus", 0)) + int(settings.ddl_offset)
			),
			"DDL applies the selected difficulty " + difficulty
		)
		ddls.append(battle.ddl)
		var expected_pressure := 0
		for task in battle.tasks:
			var normal := battle.copy()
			normal.difficulty = "normal"
			var base := BattleEngine.new(catalog).intent_pressure(normal, task)
			var expected := ceili(base * int(settings.get("pressure_percent", 100)) / 100.0)
			_check(session._battle_engine.intent_pressure(battle, task) == expected, "intent pressure is scaled once " + difficulty)
			expected_pressure += expected * maxi(1, int(task.intent_snapshot.get("pressure_times", 1)))
			var public_task: Dictionary = session.get_view().battle.tasks.filter(func(item): return item.task_id == task.task_id)[0]
			_check(public_task.effective_pressure == expected, "UI and engine share actual intent pressure " + difficulty)
		var vitality_before := int(battle.player.vitality)
		var turn_view := session.get_view()
		var ended := session.submit(CommandContext.new(str(turn_view.run_id), turn_view.revision), GameAction.new(&"end_turn", {"retained_card_ids": []}))
		_check(ended.accepted, "real end turn resolves " + difficulty)
		if session._state.battle != null:
			_check(int(session._state.battle.player.vitality) == vitality_before - expected_pressure, "real vitality loss matches displayed pressure " + difficulty)
		var before := SnapshotCodec.encode_session(session._state, session._catalog.get_info())
		var saved := session.save_current()
		_check(before.ok and saved.ok, "difficulty battle saves " + difficulty)
		var restored := GameSession.new(store)
		_check(restored.continue_run().ok, "difficulty battle resumes " + difficulty)
		if restored._state != null:
			var after := SnapshotCodec.encode_session(restored._state, restored._catalog.get_info())
			_check(after.ok and after.data == before.data and restored._state.run.difficulty == difficulty, "save restores exact state, difficulty, revision and all RNG " + difficulty)
		if before.ok:
			var old: Dictionary = before.data.duplicate(true)
			old.manifest_id = RelicPilot.BASE
			old.content_version = catalog.get_info().content_version
			old.payload.run.manifest_id = RelicPilot.BASE
			old.payload.run.campaign.erase("rx_uses")
			old.payload.run.campaign.erase("rx_state")
			old.content_hash = ContentDB.PREVIOUS_FOUR_YEAR_HASH
			old.checksum = SnapshotCodec.compute_checksum(old)
			_check(SnapshotCodec.decode_session(old, catalog).ok == (difficulty == "normal"), "previous content hash accepts only historical normal difficulty")
			old.content_hash = "f".repeat(64)
			old.checksum = SnapshotCodec.compute_checksum(old)
			_check(not SnapshotCodec.decode_session(old, catalog).ok, "unknown content hashes remain rejected")
		restored.free()
		session.free()
	_check(maps.size() == 3 and maps[0] == maps[1] and maps[1] == maps[2], "difficulty never changes same-seed topology or content opportunities")
	_check(streams.size() == 3 and streams[0] == streams[1] and streams[1] == streams[2], "difficulty never advances an extra RNG stream")
	_check(ddls.size() == 3 and ddls[0] == ddls[1] + 2 and ddls[2] == ddls[1] - 1, "three live battles have distinct actual deadlines")
	_test_dynamic_pressure(catalog, rules)
	_test_altered_content(catalog)
	print("DIFFICULTY_CHECKS=%d FAILURES=%d" % [_checks, _failures.size()])
	return _failures


func _test_dynamic_pressure(catalog: ContentDB, rules: Dictionary) -> void:
	var task := {"task_id": "intent-test", "shield": 3, "intent_snapshot": {"pressure": 7, "pressure_per_unit": 2, "pressure_per_unit_cap": 5, "pressure_when_shield": 2, "pressure_has_unit_mult": 150}}
	for difficulty in ["relaxed", "normal", "hard"]:
		var state := BattleState.new({"difficulty": difficulty, "units": [{"unit_id": "one"}], "statuses": [{"status_id": "feebleness", "target_id": "intent-test", "stacks": 2}, {"status_id": "weakness", "target_id": "intent-test", "stacks": 1}]})
		var full := ceili((7 + 2 + 2) * 1.5)
		var scaled := DifficultyRules.scale_pressure(full, difficulty, rules)
		_check(BattleEngine.new(catalog).intent_pressure(state, task) == floori(maxi(0, scaled - 2 * int(rules.statuses.feebleness.pressure_flat)) * int(rules.statuses.weakness.pressure_percent) / 100.0), "dynamic intent uses final pressure, then feebleness and weakness " + difficulty)


func _test_altered_content(catalog: ContentDB) -> void:
	var root := "user://difficulty-altered-%d" % Time.get_ticks_usec()
	for folder in ["definitions", "manifests"]:
		DirAccess.make_dir_recursive_absolute(root + "/" + folder)
		for file in DirAccess.get_files_at("res://data/four_year/" + folder):
			if file.ends_with(".json"):
				var output := FileAccess.open(root + "/" + folder + "/" + file, FileAccess.WRITE)
				output.store_string(FileAccess.get_file_as_string("res://data/four_year/" + folder + "/" + file))
	var path := root + "/definitions/rulesets.json"
	var rows: Array = SnapshotCodec.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path)))
	rows[0].difficulty_overrides.normal.starting_vitality += 1
	var changed := FileAccess.open(path, FileAccess.WRITE)
	changed.store_string(JSON.stringify(rows))
	changed.close()
	var modified := ContentDB.new(root)
	var loaded := modified.load("campus_four_year")
	_check(loaded.ok, "unrelated modified content is otherwise valid")
	if not loaded.ok:
		print("ALTERED_CONTENT_ERROR=", loaded.error.to_dictionary())
		return
	_check(not modified.accepts_previous_four_year_hash(ContentDB.PREVIOUS_FOUR_YEAR_HASH) and not modified.accepts_legacy_four_year_hash(ContentDB.LEGACY_FOUR_YEAR_HASH), "any changed historical rule prevents both compatibility proofs")
	_check(catalog.get_info().content_hash != modified.get_info().content_hash, "production catalog remains untouched by isolated fixture")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("difficulty: " + message)
