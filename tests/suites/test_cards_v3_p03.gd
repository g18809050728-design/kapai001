extends RefCounted

const FIXTURE := "res://tests/fixtures/cards_v3_p03"
const MANIFEST := "test_cards_v3_p03"
const TASK_A := "R3_TEST_TASK_A"
const TASK_B := "R3_TEST_TASK_B"
const P03_IDS := [
	"R3-P03-01",
	"R3-P03-02",
	"R3-P03-03",
	"R3-P03-04",
	"R3-P03-05",
	"R3-P03-06",
	"R3-P03-07",
	"R3-P03-08",
	"R3-P03-09",
	"R3-P03-10",
	"R3-P03-11",
	"R3-P03-12",
	"R3-P03-13",
	"R3-P03-14",
	"R3-P03-15",
	"R3-P03-16",
	"R3-P03-17",
	"R3-P03-18",
	"R3-P03-19",
	"R3-P03-20",
	"R3-P03-21",
	"R3-P03-22",
	"R3-P03-23",
	"R3-P03-24",
	"R3-P03-25",
	"R3-P03-26",
	"R3-P03-27",
	"R3-P03-28",
	"R3-P03-29",
	"R3-P03-30",
	"R3-P03-31",
	"R3-P03-32",
	"R3-P03-33",
	"R3-P03-34",
	"R3-P03-35",
	"R3-P03-36",
	"R3-P03-37",
	"R3-P03-38",
	"R3-P03-39",
	"R3-P03-40",
]

var _fixture_root := ""


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := _copy_fixture()
	var catalog := ContentDB.new(root, true)
	var loaded := catalog.load(MANIFEST)
	_check(loaded.ok, "P03 fixture loads", failures)
	if not loaded.ok:
		print("V3_P03_LOAD_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(root)
		return failures
	var engine := BattleEngine.new(catalog)
	_check_erosion(engine, failures)
	_check_induced(engine, failures)
	_check_compound(engine, failures)
	_check_poison_count(engine, failures)
	_check_burst_activation_and_limit(engine, failures)
	_check_abilities(engine, failures)
	_check_pressure_and_shield(engine, failures)
	_check_all_cards_resolve(engine, catalog, failures)
	_remove_fixture(root)
	if failures.is_empty():
		print("V3_P03_CARDS=", JSON.stringify({"total": P03_IDS.size(), "smoke": P03_IDS.size()}))
		print("V3_CARDS_V3_P03_SUITE=passed")
	return failures


func _check_erosion(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P03-02", 2]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-02", 1)
	var applied := _play(engine, begun, "R3-P03-02", [_target_a(begun)])
	_check(applied.ok, "P03 erosion card resolves", failures)
	var ended := engine.apply(
		applied.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		applied.data.rng_state
	)
	_check(ended.ok, "P03 erosion window resolves", failures)
	if ended.ok:
		_check(
			_task(ended, TASK_A).work_remaining == 47, "P03 erosion deals 3 at prepare", failures
		)
		_check(_task_status(ended, TASK_A, "erosion") == 2, "P03 erosion decays by one", failures)

	begun = _begin(engine, _deck([["R3-P03-10", 1], ["R3-P03-02", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P03-10", 1)
	var ability := _play(engine, begun, "R3-P03-10", [])
	var ability_end := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	if ability_end.ok:
		ability_end.data.state.player.focus = 10
		_move_to_hand(ability_end.data.state, "R3-P03-02", 1)
	var second := _play(engine, ability_end, "R3-P03-02", [_target_a(ability_end)])
	var second_end := engine.apply(
		second.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), second.data.rng_state
	)
	_check(second_end.ok, "P03 erosion acceleration resolves", failures)
	if second_end.ok:
		_check(
			_task(second_end, TASK_A).work_remaining == 45,
			"P03 erosion window runs twice",
			failures
		)
		_check(
			_task_status(second_end, TASK_A, "erosion") == 1,
			"P03 accelerated erosion decays twice",
			failures
		)


func _check_induced(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P03-11", 1], ["R3-P03-12", 1]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-11", 1)
	_move_to_hand(state, "R3-P03-12", 1)
	var induced := _play(engine, begun, "R3-P03-11", [_target_a(begun)])
	var triggered := _play(engine, induced, "R3-P03-12", [_target_a(induced)])
	_check(triggered.ok, "P03 induced window resolves", failures)
	if triggered.ok:
		_check(
			_task(triggered, TASK_A).work_remaining == 46,
			"P03 induced adds one status completion",
			failures
		)
		_check(
			_task_status(triggered, TASK_A, "induced") == 1,
			"P03 induced is not consumed by the trigger",
			failures
		)
		var ended := engine.apply(
			triggered.data.state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
			triggered.data.rng_state
		)
		_check(
			ended.ok and _task_status(ended, TASK_A, "induced") == 0,
			"P03 induced clears at action end",
			failures
		)

	begun = _begin(engine, _deck([["R3-P03-11", 1], ["R3-P03-18", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-11", 1)
	_move_to_hand(state, "R3-P03-18", 1)
	var i1 := _play(engine, begun, "R3-P03-11", [_target_a(begun)])
	var extra := _play(engine, i1, "R3-P03-18", [_target_a(i1)])
	_check(
		extra.ok and _task(extra, TASK_A).work_remaining == 42,
		"P03 extra induced trigger shares the window",
		failures
	)


func _check_compound(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P03-17", 1], ["R3-P03-21", 1]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-17", 1)
	_move_to_hand(state, "R3-P03-21", 1)
	var first := _play(engine, begun, "R3-P03-17", [_target_a(begun)])
	_check(first.ok, "P03 compound starter resolves", failures)
	if first.ok:
		_check(
			_task_status(first, TASK_A, "vulnerability") == 2,
			"P03 compound adds one vulnerability",
			failures
		)
		_check(
			_task_status(first, TASK_A, "induced") == 1,
			"P03 compound keeps the first status",
			failures
		)
		_check(
			bool(first.data.state.v3.get("turn", {}).get("compound_used", false)),
			"P03 compound is consumed",
			failures
		)
	var second := _play(engine, first, "R3-P03-21", [_target_a(first)])
	_check(second.ok, "P03 second compound card resolves", failures)
	if second.ok:
		_check(
			_task_status(second, TASK_A, "weakness") == 1,
			"P03 compound does not fire twice",
			failures
		)
		_check(
			_task_status(second, TASK_A, "feebleness") == 1,
			"P03 second new debuff remains one",
			failures
		)


func _check_poison_count(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(
		engine, _deck([["R3-P03-19", 1], ["R3-P03-02", 1], ["R3-P03-03", 1], ["R3-P03-08", 1]]), rng
	)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-19", 1)
	var ability := _play(engine, begun, "R3-P03-19", [])
	var ended := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	if ended.ok:
		ended.data.state.player.focus = 10
		_move_to_hand(ended.data.state, "R3-P03-02", 1)
		_move_to_hand(ended.data.state, "R3-P03-03", 1)
		_move_to_hand(ended.data.state, "R3-P03-08", 1)
	var one := _play(engine, ended, "R3-P03-02", [_target_a(ended)])
	var two := _play(engine, one, "R3-P03-03", [_target_a(one)])
	var three := _play(engine, two, "R3-P03-08", [_target_a(two)])
	_check(three.ok, "P03 poison count sequence resolves", failures)
	if three.ok:
		_check(
			_task(three, TASK_A).work_remaining == 46,
			"P03 third erosion event completes task A",
			failures
		)
		_check(
			_task(three, TASK_B).work_remaining == 46,
			"P03 third erosion event completes task B",
			failures
		)


func _check_burst_activation_and_limit(engine: BattleEngine, failures: Array[String]) -> void:
	for level in [0, 1]:
		var deck := _deck([["R3-P03-19", 1], ["R3-P03-02", 6]])
		deck[0].upgrade_level = level
		var step := _begin(engine, deck, _rng())
		step.data.state.player.focus = 30
		step = _play(engine, step, "R3-P03-19", [])
		for i in 3:
			step = _play(engine, step, "R3-P03-02", [_target_a(step)])
		_check(step.ok and _task(step, TASK_B).work_remaining == 50, "burst stays dormant during its deployment turn", failures)
		if not step.ok:
			continue
		step = engine.apply(step.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), step.data.rng_state)
		step.data.state.player.focus = 30
		for i in 4:
			step = _play(engine, step, "R3-P03-02", [_target_a(step)])
			_check(step.ok, "burst erosion sequence resolves", failures)
			if not step.ok:
				break
			var expected := 50 if i < 2 else (44 if level > 0 else 46)
			_check(_task(step, TASK_B).work_remaining == expected, "burst triggers at third event exactly once with correct upgrade amount", failures)
	print("BURST_CARD_RULES=base4 upgrade6 next_round third_event once_per_turn")


func _check_abilities(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P03-04", 1]]), rng)
	var state: BattleState = begun.data.state
	_move_to_hand(state, "R3-P03-04", 1)
	var auto := _play(engine, begun, "R3-P03-04", [])
	var auto_end := engine.apply(
		auto.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), auto.data.rng_state
	)
	_check(auto_end.ok, "P03 auto-erosion ability resolves", failures)
	if auto_end.ok:
		_check(
			_task_status(auto_end, TASK_A, "erosion") == 1, "P03 auto-erosion hits task A", failures
		)
		_check(
			_task_status(auto_end, TASK_B, "erosion") == 1, "P03 auto-erosion hits task B", failures
		)

	begun = _begin(engine, _deck([["R3-P03-20", 1], ["R3-P03-11", 1], ["R3-P03-12", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P03-20", 1)
	var p20 := _play(engine, begun, "R3-P03-20", [])
	var p20_end := engine.apply(
		p20.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p20.data.rng_state
	)
	if p20_end.ok:
		p20_end.data.state.player.focus = 10
		_move_to_hand(p20_end.data.state, "R3-P03-11", 1)
		_move_to_hand(p20_end.data.state, "R3-P03-12", 1)
	var p20_i := _play(engine, p20_end, "R3-P03-11", [_target_a(p20_end)])
	var p20_w := _play(engine, p20_i, "R3-P03-12", [_target_a(p20_i)])
	_check(
		p20_w.ok and _task(p20_w, TASK_A).work_remaining == 43,
		"P03-20 adds 3 on the first induced trigger",
		failures
	)

	begun = _begin(engine, _deck([["R3-P03-40", 1], ["R3-P03-17", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P03-40", 1)
	var p40 := _play(engine, begun, "R3-P03-40", [])
	var p40_end := engine.apply(
		p40.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p40.data.rng_state
	)
	if p40_end.ok:
		p40_end.data.state.player.focus = 10
		_move_to_hand(p40_end.data.state, "R3-P03-17", 1)
	var p40_card := _play(engine, p40_end, "R3-P03-17", [_target_a(p40_end)])
	_check(
		p40_card.ok and p40_card.data.state.player.relax == 3,
		"P03-40 triggers on compound reaction",
		failures
	)

	begun = _begin(engine, _deck([["R3-P03-16", 1], ["R3-P03-03", 1], ["R3-P03-12", 8]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P03-16", 1)
	_move_to_hand(state, "R3-P03-03", 1)
	var chain := _play(engine, begun, "R3-P03-16", [])
	var chain_work := _play(engine, chain, "R3-P03-03", [_target_a(chain)])
	_check(chain_work.ok, "P03 chain resolves", failures)
	if chain_work.ok:
		_check(
			_task_status(chain_work, TASK_A, "erosion") == 3,
			"P03 chain adds erosion to the target",
			failures
		)
		_check(
			_task_status(chain_work, TASK_B, "erosion") == 1,
			"P03 chain adds erosion to all tasks",
			failures
		)

	begun = _begin(engine, _deck([["R3-P03-30", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P03-30", 1)
	var p30 := _play(engine, begun, "R3-P03-30", [])
	var p30_end := engine.apply(
		p30.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p30.data.rng_state
	)
	if p30_end.ok:
		p30_end.data.state.player.focus = 10
		var id30 := _target_a(p30_end)
		_add_task_status(p30_end.data.state, id30, "feebleness", 1, "battle")
		_add_task_status(p30_end.data.state, id30, "weakness", 2, "pressure_window")
		_add_task_status(p30_end.data.state, id30, "brittle", 2, "pressure_window")
	var p30_prepare := engine.apply(
		p30_end.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		p30_end.data.rng_state
	)
	_check(p30_prepare.ok, "P03-30 prepare trigger resolves", failures)
	if p30_prepare.ok:
		_check(p30_prepare.data.state.player.relax == 5, "P03-30 grants relax at prepare", failures)
		_check(
			_task(p30_prepare, TASK_A).work_remaining == 45,
			"P03-30 adds status completion",
			failures
		)


func _check_pressure_and_shield(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P03-14", 20]]), rng)
	var state: BattleState = begun.data.state
	state.player.relax = 0
	_add_task_status(state, _target_a(begun), "feebleness", 2, "battle")
	_add_task_status(state, _target_a(begun), "weakness", 1, "pressure_window")
	state.tasks[0].intent_snapshot.pressure = 8
	var ended := engine.apply(
		state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), begun.data.rng_state
	)
	_check(
		ended.ok and ended.data.state.player.vitality == 68,
		"P03 feebleness applies before weakness",
		failures
	)

	begun = _begin(engine, _deck([["R3-P03-14", 20]]), rng)
	state = begun.data.state
	var shield_task_id := _task_id(state, "R3_TEST_SHIELD")
	_add_task_status(state, shield_task_id, "brittle", 1, "pressure_window")
	var ruleset := ContentDB.new(_fixture_root, true)
	ruleset.load(MANIFEST)
	var rules := ruleset.get_definition("ruleset", "campus_v1")
	_check(
		rules.ok and engine._scaled_shield(state, rules.data, shield_task_id, 8) == 4,
		"P03 brittle halves new shields",
		failures
	)

	begun = _begin(engine, _deck([["R3-C-09", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_add_task_status(state, _target_a(begun), "vulnerability", 1, "pressure_window")
	_move_to_hand(state, "R3-C-09", 1)
	var vulnerable := _play(engine, begun, "R3-C-09", [_target_a(begun)])
	_check(
		vulnerable.ok and _task(vulnerable, TASK_A).work_remaining == 45,
		"P03 vulnerability boosts direct work",
		failures
	)


func _check_all_cards_resolve(
	engine: BattleEngine, catalog: ContentDB, failures: Array[String]
) -> void:
	for card_id in P03_IDS:
		var rng := _rng()
		var deck := _deck(
			[
				[card_id, 5],
				["R3-P03-11", 1],
				["R3-P03-17", 1],
				["R3-P03-12", 1],
				["R3-P03-23", 1],
				["R3-P03-02", 1],
			]
		)
		var begun := _begin(engine, deck, rng)
		_check(begun.ok, card_id + " smoke battle starts", failures)
		if not begun.ok:
			continue
		var state: BattleState = begun.data.state
		state.player.focus = 10
		_add_anxiety(state)
		_move_to_hand(state, card_id, 1)
		_move_to_hand(state, "R3-P03-12", 1)
		_put_in_discard(state, "R3-P03-23", 1)
		for task_id in _task_ids(state):
			for status_id in [
				"erosion", "induced", "brittle", "feebleness", "weakness", "vulnerability"
			]:
				_add_task_status(state, task_id, status_id, 1, "pressure_window")
		var target_ids := []
		if str(catalog.get_definition("card", card_id).data.get("target", "")) == "task":
			target_ids = [_target_a(begun)]
		var step := _play(engine, begun, card_id, target_ids)
		_check(step.ok, card_id + " resolves through the v3 engine", failures)
		if step.ok:
			_check(
				step.data.state.phase in ["player_action", "finished"],
				card_id + " reaches a stable phase",
				failures
			)


func _copy_fixture() -> String:
	_fixture_root = ProjectSettings.globalize_path(
		"res://.godot/v3_p03_fixture_%d" % Time.get_ticks_usec()
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
	var file := FileAccess.open(to_path, FileAccess.WRITE)
	if file != null:
		file.store_string(FileAccess.get_file_as_string(from_path))


func _remove_fixture(root: String) -> void:
	for directory in ["definitions", "manifests"]:
		for file_name in DirAccess.get_files_at("%s/%s" % [root, directory]):
			DirAccess.remove_absolute("%s/%s/%s" % [root, directory, file_name])
		DirAccess.remove_absolute("%s/%s" % [root, directory])
	DirAccess.remove_absolute(root)


func _rng() -> Dictionary:
	return RandomSource.new("cards-v3-p03").export_state().to_dictionary()


func _deck(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var serial := 0
	for entry in entries:
		var definition_id := str(entry[0])
		for index in int(entry[1]):
			serial += 1
			(
				result
				. append(
					{
						"card_id": "card_%03d" % serial,
						"definition_id": definition_id,
						"upgrade_level": 0,
					}
				)
			)
	return result


func _begin(engine: BattleEngine, deck: Array[Dictionary], rng: Dictionary) -> GameResult:
	return (
		engine
		. begin(
			{
				"battle_id": "r3_p03_%d" % Time.get_ticks_usec(),
				"encounter_id": "R3_TEST",
				"character_id": "P03",
				"difficulty": "normal",
				"vitality": 72,
				"max_vitality": 72,
				"cards": deck,
				"relics": [],
				"rng_state": rng.duplicate(true),
			}
		)
	)


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
		if str(state.card_by_id.get(card_id, {}).get("definition_id", "")) == definition_id:
			return str(card_id)
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) != definition_id:
			continue
		for zone in ["draw", "discard"]:
			state.zones[zone].erase(card_id)
		state.zones.hand.append(card_id)
		return str(card_id)
	return ""


func _move_to_hand(state: BattleState, definition_id: String, count: int) -> void:
	for index in count:
		var card_id := _hand_card(state, definition_id)
		if card_id.is_empty():
			return


func _put_in_discard(state: BattleState, definition_id: String, count: int) -> void:
	for index in count:
		var card_id := _any_card(state, definition_id)
		if card_id.is_empty():
			return
		state.zones.hand.erase(card_id)
		state.zones.draw.erase(card_id)
		state.zones.discard.erase(card_id)
		state.zones.discard.append(card_id)


func _any_card(state: BattleState, definition_id: String) -> String:
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) == definition_id:
			return str(card_id)
	return ""


func _task_ids(state: BattleState) -> Array[String]:
	var result: Array[String] = []
	for task: Dictionary in state.tasks:
		result.append(str(task.get("task_id", "")))
	return result


func _target_a(step: GameResult) -> String:
	return _task_id(step.data.state, TASK_A)


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


func _task_status(step: GameResult, task_definition: String, status_id: String) -> int:
	if not step.ok:
		return 0
	var state: BattleState = step.data.state
	var task_id := _task_id(state, task_definition)
	for status: Dictionary in state.statuses:
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == task_id
		):
			return int(status.get("stacks", 0))
	return 0


func _add_task_status(
	state: BattleState, task_id: String, status_id: String, stacks: int, expiry: String
) -> void:
	(
		state
		. statuses
		. append(
			{
				"status_id": status_id,
				"instance_id": "test_%s_%s" % [status_id, task_id],
				"source_id": "",
				"target_id": task_id,
				"stacks": stacks,
				"expiry": expiry,
			}
		)
	)


func _add_anxiety(state: BattleState) -> void:
	(
		state
		. statuses
		. append(
			{
				"status_id": "anxiety",
				"instance_id": "anxiety_test_1",
				"source_id": "",
				"target_id": str(state.player.get("entity_id", "")),
				"stacks": 1,
				"expiry": "next_prepare",
			}
		)
	)


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("cards v3 P03: " + label)
