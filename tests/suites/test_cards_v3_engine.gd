extends RefCounted

const FIXTURE := "res://tests/fixtures/cards_v3_engine"
const MANIFEST := "test_cards_v3_engine"
const TASK_A := "R3_TEST_TASK_A"
const TASK_B := "R3_TEST_TASK_B"


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := _copy_fixture()
	var catalog := ContentDB.new(root, true)
	var loaded := catalog.load(MANIFEST)
	_check(loaded.ok, "v3 engine fixture loads", failures)
	if not loaded.ok:
		print("V3_ENGINE_LOAD_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(root)
		return failures
	var engine := BattleEngine.new(catalog)
	_check_direct(engine, failures)
	_check_ability(engine, failures)
	_check_scene(engine, failures)
	_check_codec(engine, failures)
	_remove_fixture(root)
	if failures.is_empty():
		print("V3_ENGINE_CASES=", JSON.stringify({"passed": 12}))
		print("V3_CARDS_V3_ENGINE_SUITE=passed")
	return failures


func _check_direct(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck("R3-C-01", 10), rng)
	_check(begun.ok, "C-01 battle starts", failures)
	if begun.ok:
		var step := _play(engine, begun, "R3-C-01", [_task_id(begun.data.state, TASK_A)])
		_check(step.ok, "C-01 resolves", failures)
		_check(_task(step, TASK_A).work_remaining == 44, "C-01 completes 6", failures)
		_check_state_valid(engine, step, "C-01", failures)

	begun = _begin(engine, _deck("R3-C-02", 10), rng)
	var step := _play(engine, begun, "R3-C-02", [])
	_check(step.ok and step.data.state.player.relax == 5, "C-02 gains 5 relax", failures)

	begun = _begin(engine, _deck("R3-C-03", 10), rng)
	step = _play(engine, begun, "R3-C-03", [])
	_check(step.ok, "C-03 resolves with discard choice", failures)
	if step.ok:
		_check(
			step.data.state.zones.discard.size() == 2,
			"C-03 discards one card after drawing two",
			failures
		)

	begun = _begin(engine, _deck("R3-C-04", 10), rng)
	step = _play(engine, begun, "R3-C-04", [])
	_check(step.ok and step.data.state.player.relax == 3, "C-04 gains 3 relax", failures)
	_check(step.ok and step.data.state.zones.exhaust.size() == 1, "C-04 exhausts itself", failures)

	begun = _begin(engine, _deck("R3-C-05", 10), rng)
	begun.data.state.player.vitality = 50
	step = _play(engine, begun, "R3-C-05", [])
	_check(
		step.ok and step.data.state.player.vitality == 53 and step.data.state.player.relax == 3,
		"C-05 heals 3 and gains 3 relax",
		failures
	)

	begun = _begin(engine, _deck("R3-C-07", 10), rng)
	begun.data.state.ddl = 3
	step = _play(engine, begun, "R3-C-07", [_task_id(begun.data.state, TASK_A)])
	_check(
		step.ok and _task(step, TASK_A).work_remaining == 38, "C-07 adds the DDL bonus", failures
	)

	begun = _begin(engine, _deck("R3-C-09", 10), rng)
	step = _play(engine, begun, "R3-C-09", [_task_id(begun.data.state, TASK_A)])
	_check(
		step.ok and _task(step, TASK_A).work_remaining == 45,
		"C-09 vulnerability boosts completion",
		failures
	)
	_check(_has_status(step, TASK_A, "vulnerability"), "C-09 applies vulnerability", failures)

	begun = _begin(engine, _deck("R3-C-10", 10), rng)
	step = _play(engine, begun, "R3-C-10", [_task_id(begun.data.state, TASK_A)])
	_check(step.ok and _has_status(step, TASK_A, "weakness"), "C-10 applies weakness", failures)
	if step.ok:
		var state: BattleState = step.data.state
		state.player.relax = 0
		state.tasks[0].intent_snapshot.pressure = 1
		var ended := engine.apply(
			state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), step.data.rng_state
		)
		_check(ended.ok, "C-10 end turn resolves", failures)
		if ended.ok:
			_check(
				ended.data.state.player.vitality == 72,
				"C-10 weakness reduces pressure to zero",
				failures
			)
			_check(
				not _has_status(ended, TASK_A, "weakness"),
				"C-10 weakness expires after the pressure window",
				failures
			)

	begun = _begin(engine, _deck("R3-C-11", 10), rng)
	begun.data.state.tasks[0].shield = 6
	step = _play(engine, begun, "R3-C-11", [_task_id(begun.data.state, TASK_A)])
	_check(step.ok and _task(step, TASK_A).shield == 0, "C-11 removes the shield", failures)
	_check(
		step.ok and _task(step, TASK_A).work_remaining == 45,
		"C-11 completes after removing shield",
		failures
	)

	begun = _begin(engine, _deck("R3-C-12", 10), rng)
	step = _play(engine, begun, "R3-C-12", [])
	_check(step.ok and _task(step, TASK_A).work_remaining == 46, "C-12 completes task A", failures)
	_check(step.ok and _task(step, TASK_B).work_remaining == 46, "C-12 completes task B", failures)


func _check_ability(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck("R3-C-06", 5)
	deck.append_array(_deck("R3-C-01", 5))
	var begun := _begin(engine, deck, rng)
	var ability := _play(engine, begun, "R3-C-06", [])
	_check(ability.ok, "C-06 ability resolves", failures)
	_check(
		ability.ok and ability.data.state.v3.get("abilities", []).size() == 1,
		"C-06 registers one ability",
		failures
	)
	if not ability.ok:
		return
	var ended := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	_check(ended.ok, "C-06 end turn resolves", failures)
	if not ended.ok:
		return
	var work := _play(engine, ended, "R3-C-01", [_task_id(ended.data.state, TASK_A)])
	_check(
		work.ok and _task(work, TASK_A).work_remaining == 42,
		"C-06 adds 2 to the first work card",
		failures
	)


func _check_scene(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck("R3-C-08", 10), rng)
	var scene := _play(engine, begun, "R3-C-08", [])
	_check(scene.ok, "C-08 establishes a scene", failures)
	if not scene.ok:
		return
	_check(
		str(scene.data.state.scene.get("definition_id", "")) == "R3-S01",
		"C-08 establishes R3-S01",
		failures
	)
	var ended := engine.apply(
		scene.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), scene.data.rng_state
	)
	_check(ended.ok and ended.data.state.player.relax == 3, "C-08 scene grants 3 relax", failures)


func _check_codec(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck("R3-C-06", 5)
	deck.append_array(_deck("R3-C-01", 5))
	var begun := _begin(engine, deck, rng)
	var ability := _play(engine, begun, "R3-C-06", [])
	if not ability.ok:
		_check(false, "C-06 codec setup resolves", failures)
		return
	var ended := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	if not ended.ok:
		_check(false, "C-06 codec end turn resolves", failures)
		return
	var encoded := BattleCodec.encode(ended.data.state)
	_check(encoded.ok, "v3 state encodes", failures)
	if not encoded.ok:
		return
	var catalog := ContentDB.new(_last_fixture_root(), true)
	if not catalog.load(MANIFEST).ok:
		_check(false, "v3 codec fixture reloads", failures)
		return
	var decoded := BattleCodec.decode(encoded.data, catalog)
	_check(decoded.ok, "v3 state decodes", failures)
	if decoded.ok:
		_check(decoded.data.v3 == ended.data.state.v3, "v3 ability state round-trips", failures)


var _fixture_root := ""


func _copy_fixture() -> String:
	_fixture_root = ProjectSettings.globalize_path(
		"res://.godot/r3_engine_fixture_%d" % Time.get_ticks_usec()
	)
	for directory in ["definitions", "manifests"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [_fixture_root, directory])
	for file_name in ContentDB.FILE_NAMES.values():
		_copy(
			"%s/definitions/%s.json" % [FIXTURE, file_name],
			"%s/definitions/%s.json" % [_fixture_root, file_name]
		)
	_copy(
		"%s/manifests/%s.json" % [FIXTURE, MANIFEST],
		"%s/manifests/%s.json" % [_fixture_root, MANIFEST]
	)
	return _fixture_root


func _copy(from_path: String, to_path: String) -> void:
	var contents := FileAccess.get_file_as_string(from_path)
	var file := FileAccess.open(to_path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)


func _remove_fixture(root: String) -> void:
	for directory in ["definitions", "manifests"]:
		for file_name in DirAccess.get_files_at("%s/%s" % [root, directory]):
			DirAccess.remove_absolute("%s/%s/%s" % [root, directory, file_name])
		DirAccess.remove_absolute("%s/%s" % [root, directory])
	DirAccess.remove_absolute(root)


func _last_fixture_root() -> String:
	return _fixture_root


func _rng() -> Dictionary:
	return RandomSource.new("cards-v3-engine").export_state().to_dictionary()


func _deck(definition_id: String, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in count:
		(
			result
			. append(
				{
					"card_id": "%s_%02d" % [definition_id, index + 1],
					"definition_id": definition_id,
					"upgrade_level": 0,
				}
			)
		)
	return result


func _begin(engine: BattleEngine, deck: Array[Dictionary], rng: Dictionary) -> GameResult:
	var result := (
		engine
		. begin(
			{
				"battle_id": "r3_engine_%d" % Time.get_ticks_usec(),
				"encounter_id": "R3_TEST",
				"character_id": "R3_TEST_CHAR",
				"difficulty": "normal",
				"vitality": 72,
				"max_vitality": 72,
				"cards": deck,
				"relics": [],
				"rng_state": rng.duplicate(true),
			}
		)
	)
	if not result.ok:
		print("V3_BEGIN_ERROR=", JSON.stringify(result.error.to_dictionary()))
	return result


func _play(
	engine: BattleEngine, step: GameResult, definition_id: String, target_ids: Array
) -> GameResult:
	if not step.ok:
		return step
	var state: BattleState = step.data.state
	var card_id := _hand_card(state, definition_id)
	if card_id.is_empty():
		return GameResult.failure(
			ApiError.new(
				GameConstants.ERROR_INVALID_TARGET, "test.card_not_in_hand", {"id": definition_id}
			)
		)
	var result := engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD, {"card_instance_id": card_id, "target_ids": target_ids}
		),
		step.data.rng_state
	)
	var guard := 0
	while result.ok and result.data.pending_choice != null and guard < 4:
		var choice: Dictionary = result.data.pending_choice
		var candidates: Array = choice.get("candidates", [])
		var selected: Array = []
		if not candidates.is_empty():
			selected = [str(candidates[0].get("id", ""))]
		result = engine.apply(
			result.data.state,
			ActionDraft.new(
				GameConstants.ACTION_CONFIRM_CHOICE,
				{"choice_id": str(choice.get("choice_id", "")), "selected_ids": selected}
			),
			result.data.rng_state
		)
		guard += 1
	return result


func _hand_card(state: BattleState, definition_id: String) -> String:
	for card_id in state.zones.hand:
		var card: Dictionary = state.card_by_id.get(card_id, {})
		if str(card.get("definition_id", "")) == definition_id:
			return str(card_id)
	for card_id in state.card_by_id:
		var card: Dictionary = state.card_by_id[card_id]
		if str(card.get("definition_id", "")) != definition_id:
			continue
		for zone in ["draw", "discard"]:
			state.zones[zone].erase(card_id)
		state.zones.hand.append(card_id)
		return str(card_id)
	return ""


func _task_id(state: BattleState, definition_id: String) -> String:
	for task: Dictionary in state.tasks:
		if str(task.get("definition_id", "")) == definition_id:
			return str(task.get("task_id", ""))
	return ""


func _task(step: GameResult, definition_id: String) -> Dictionary:
	if not step.ok:
		return {}
	for task: Dictionary in step.data.state.tasks:
		if str(task.get("definition_id", "")) == definition_id:
			return task
	return {}


func _has_status(step: GameResult, task_definition: String, status_id: String) -> bool:
	if not step.ok:
		return false
	var state: BattleState = step.data.state
	var task_id := _task_id(state, task_definition)
	for status: Dictionary in state.statuses:
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == task_id
		):
			return true
	return false


func _check_state_valid(
	engine: BattleEngine, step: GameResult, label: String, failures: Array[String]
) -> void:
	if not step.ok:
		return
	var ruleset := ContentDB.new(_fixture_root, true)
	var loaded := ruleset.load(MANIFEST)
	if not loaded.ok:
		return
	var rules := ruleset.get_definition("ruleset", "campus_v1")
	if rules.ok:
		var issues: Array = step.data.state.validate(int(rules.data.battle.unit_slots))
		_check(issues.is_empty(), label + " state validates", failures)


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("cards v3 engine: " + label)
