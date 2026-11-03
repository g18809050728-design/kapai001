extends RefCounted

const FIXTURE := "res://tests/fixtures/cards_v3_p01"
const MANIFEST := "test_cards_v3_p01"
const TASK_A := "R3_TEST_TASK_A"
const TASK_B := "R3_TEST_TASK_B"
const P01_IDS := [
	"R3-P01-01", "R3-P01-02", "R3-P01-03", "R3-P01-04", "R3-P01-05",
	"R3-P01-06", "R3-P01-07", "R3-P01-08", "R3-P01-09", "R3-P01-10",
	"R3-P01-11", "R3-P01-12", "R3-P01-13", "R3-P01-14", "R3-P01-15",
	"R3-P01-16", "R3-P01-17", "R3-P01-18", "R3-P01-19", "R3-P01-20",
	"R3-P01-21", "R3-P01-22", "R3-P01-23", "R3-P01-24", "R3-P01-25",
	"R3-P01-26", "R3-P01-27", "R3-P01-28", "R3-P01-29", "R3-P01-30",
	"R3-P01-31", "R3-P01-32", "R3-P01-33", "R3-P01-34", "R3-P01-35",
	"R3-P01-36", "R3-P01-37", "R3-P01-38", "R3-P01-39", "R3-P01-40",
]

var _fixture_root := ""


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := _copy_fixture()
	var catalog := ContentDB.new(root, true)
	var loaded := catalog.load(MANIFEST)
	_check(loaded.ok, "P01 fixture loads", failures)
	if not loaded.ok:
		print("V3_P01_LOAD_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(root)
		return failures
	var engine := BattleEngine.new(catalog)
	_check_link_retrieve(engine, failures)
	_check_work_bonus(engine, failures)
	_check_cost_discount(engine, failures)
	_check_link_sequence(engine, failures)
	_check_retrieve_choice(engine, failures)
	_check_exhaust_retain_remove(engine, failures)
	_check_abilities(engine, failures)
	_check_condition_matrix(engine, failures)
	_check_all_cards_resolve(engine, catalog, failures)
	_remove_fixture(root)
	if failures.is_empty():
		print("V3_P01_CARDS=", JSON.stringify({"total": P01_IDS.size(), "smoke": P01_IDS.size()}))
		print("V3_CARDS_V3_P01_SUITE=passed")
	return failures


func _check_link_retrieve(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-11", 1], ["R3-P01-02", 9]])
	var begun := _begin(engine, deck, rng)
	if not begun.ok:
		_check(false, "P01 link battle starts", failures)
		return
	var state: BattleState = begun.data.state
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-02", 1)
	var strategy := _play(engine, begun, "R3-P01-11", [])
	if not strategy.ok:
		_check(false, "P01 strategy resolves", failures)
		return
	var work := _play(engine, strategy, "R3-P01-02", [_target_a(strategy)])
	_check(work.ok, "P01 link work resolves", failures)
	if work.ok:
		_check(_task(work, TASK_A).work_remaining == 41, "P01 link adds 3 completion", failures)
		_check(
			bool(work.data.state.v3.get("turn", {}).get("retrieved_strategy", false)),
			"P01 passive retrieve marks the turn opportunity",
			failures
		)
		_check(
			_has_card(work.data.state, "R3-P01-11"),
			"P01 passive retrieve returns the previous strategy",
			failures
		)


func _check_work_bonus(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-21", 3], ["R3-P01-23", 1]])
	var begun := _begin(engine, deck, rng)
	if not begun.ok:
		_check(false, "P01 work bonus battle starts", failures)
		return
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-21", 3)
	_move_to_hand(state, "R3-P01-23", 1)
	var step := begun
	for index in 3:
		step = _play(engine, step, "R3-P01-21", [])
		if not step.ok:
			break
	_check(step.ok, "P01 preparation cards resolve", failures)
	if not step.ok:
		return
	_check(
		int(step.data.state.v3.get("pending_work_bonus", 0)) == 12,
		"P01 work bonus caps at 12",
		failures
	)
	var work := _play(engine, step, "R3-P01-23", [_target_a(step)])
	_check(work.ok and _task(work, TASK_A).work_remaining == 24, "P01 work bonus applies to the next work", failures)
	_check(
		work.ok and int(work.data.state.v3.get("pending_work_bonus", 0)) == 0,
		"P01 work bonus is consumed",
		failures
	)


func _check_cost_discount(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-25", 1], ["R3-P01-23", 1]])
	var begun := _begin(engine, deck, rng)
	if not begun.ok:
		_check(false, "P01 discount battle starts", failures)
		return
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-25", 1)
	_move_to_hand(state, "R3-P01-23", 1)
	var discount := _play(engine, begun, "R3-P01-25", [])
	var work := _play(engine, discount, "R3-P01-23", [_target_a(discount)])
	_check(work.ok, "P01 discounted work resolves", failures)
	if work.ok:
		_check(work.data.state.player.focus == 9, "P01 cost discount reduces a 2-cost work to 1", failures)
		_check(
			int(work.data.state.v3.get("pending_cost_discount", {}).get("amount", -1)) == 0,
			"P01 cost discount is consumed",
			failures
		)
		_check(_task(work, TASK_A).work_remaining == 36, "P01 discounted work still completes 14", failures)


func _check_link_sequence(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-11", 2], ["R3-P01-02", 1], ["R3-P01-09", 1]])
	var begun := _begin(engine, deck, rng)
	if not begun.ok:
		_check(false, "P01 link sequence starts", failures)
		return
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 2)
	_move_to_hand(state, "R3-P01-02", 1)
	_move_to_hand(state, "R3-P01-09", 1)
	var step := _play(engine, begun, "R3-P01-11", [])
	step = _play(engine, step, "R3-P01-02", [_target_a(step)])
	step = _play(engine, step, "R3-P01-11", [])
	step = _play(engine, step, "R3-P01-09", [_target_a(step)])
	_check(step.ok, "P01 link sequence resolves", failures)
	if step.ok:
		_check(_task(step, TASK_A).work_remaining == 28, "P01 per-link-work count adds 3", failures)


func _check_retrieve_choice(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-11", 1], ["R3-P01-16", 1]])
	var begun := _begin(engine, deck, rng)
	if not begun.ok:
		_check(false, "P01 retrieve battle starts", failures)
		return
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-16", 1)
	var strategy := _play(engine, begun, "R3-P01-11", [])
	var retrieve := _play(engine, strategy, "R3-P01-16", [])
	_check(retrieve.ok, "P01 retrieve choice resolves", failures)
	if retrieve.ok:
		_check(_has_card(retrieve.data.state, "R3-P01-11"), "P01 retrieve returns a strategy", failures)


func _check_exhaust_retain_remove(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-38", 1], ["R3-P01-12", 1]])
	var begun := _begin(engine, deck, rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-38", 1)
	_move_to_hand(state, "R3-P01-12", 1)
	var exhausted := _play(engine, begun, "R3-P01-38", [])
	_check(exhausted.ok and not exhausted.data.state.zones.exhaust.is_empty(), "P01 exhausts another hand card", failures)

	begun = _begin(engine, _deck([["R3-P01-15", 1], ["R3-P01-12", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-15", 1)
	_move_to_hand(state, "R3-P01-12", 1)
	var retained := _play(engine, begun, "R3-P01-15", [])
	_check(retained.ok and not retained.data.state.retained_card_ids.is_empty(), "P01 retains another hand card", failures)

	begun = _begin(engine, _deck([["R3-P01-13", 1], ["R3-P01-12", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_add_anxiety(state)
	_move_to_hand(state, "R3-P01-13", 1)
	_move_to_hand(state, "R3-P01-12", 1)
	var cleansed := _play(engine, begun, "R3-P01-13", [])
	_check(cleansed.ok, "P01 anxiety removal resolves", failures)
	if cleansed.ok:
		_check(
			not _has_player_status(cleansed.data.state, "anxiety"),
			"P01 removes anxiety",
			failures
		)
		_check(cleansed.data.state.player.relax == 4, "P01 anxiety card gains 4 relax", failures)


func _check_abilities(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var deck := _deck([["R3-P01-28", 1], ["R3-P01-23", 9]])
	var begun := _begin(engine, deck, rng)
	var state: BattleState = begun.data.state
	_move_to_hand(state, "R3-P01-28", 1)
	var ability := _play(engine, begun, "R3-P01-28", [])
	var ended := engine.apply(ability.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), ability.data.rng_state)
	if ended.ok:
		ended.data.state.player.focus = 10
		_move_to_hand(ended.data.state, "R3-P01-23", 1)
	var work := _play(engine, ended, "R3-P01-23", [_target_a(ended)])
	_check(work.ok and work.data.state.player.relax == 6, "P01-28 triggers on a 2-cost work", failures)

	begun = _begin(engine, _deck([["R3-P01-10", 1], ["R3-P01-11", 1], ["R3-P01-02", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P01-10", 1)
	var first := _play(engine, begun, "R3-P01-10", [])
	var first_end := engine.apply(first.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), first.data.rng_state)
	if first_end.ok:
		first_end.data.state.player.focus = 10
		_move_to_hand(first_end.data.state, "R3-P01-11", 1)
		_move_to_hand(first_end.data.state, "R3-P01-02", 1)
	var strategy := _play(engine, first_end, "R3-P01-11", [])
	var relax_before: int = strategy.data.state.player.relax if strategy.ok else 0
	var linked := _play(engine, strategy, "R3-P01-02", [_target_a(strategy)])
	_check(
		linked.ok and linked.data.state.player.relax == relax_before + 3,
		"P01-10 triggers after a link work",
		failures
	)

	begun = _begin(engine, _deck([["R3-P01-20", 1], ["R3-P01-01", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P01-20", 1)
	var p20 := _play(engine, begun, "R3-P01-20", [])
	var p20_end := engine.apply(p20.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p20.data.rng_state)
	if p20_end.ok:
		p20_end.data.state.player.focus = 10
		_move_to_hand(p20_end.data.state, "R3-P01-01", 1)
		var card_id := _hand_card(p20_end.data.state, "R3-P01-01")
		p20_end.data.state.v3["battle"] = {"instance_plays": {card_id: 1}}
		var p01 := _play(engine, p20_end, "R3-P01-01", [])
		_check(p01.ok and p01.data.state.player.relax == 5, "P01-20 triggers on a reused strategy", failures)

	begun = _begin(engine, _deck([["R3-P01-18", 1], ["R3-P01-11", 1], ["R3-P01-02", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P01-18", 1)
	var p18 := _play(engine, begun, "R3-P01-18", [])
	var p18_end := engine.apply(p18.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p18.data.rng_state)
	if p18_end.ok:
		p18_end.data.state.player.focus = 10
		_move_to_hand(p18_end.data.state, "R3-P01-11", 1)
		_move_to_hand(p18_end.data.state, "R3-P01-02", 1)
	var hand_before: int = p18_end.data.state.zones.hand.size()
	var p18_strategy := _play(engine, p18_end, "R3-P01-11", [])
	var p18_work := _play(engine, p18_strategy, "R3-P01-02", [_target_a(p18_strategy)])
	_check(p18_work.ok, "P01-18 passive retrieve resolves", failures)
	if p18_work.ok:
		_check(
			p18_work.data.state.zones.hand.size() >= hand_before,
			"P01-18 draws after passive retrieve",
			failures
		)
		_check(
			_has_card(p18_work.data.state, "R3-P01-11"),
			"P01-18 battle keeps the retrieved strategy",
			failures
		)


func _check_condition_matrix(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()

	var begun := _begin(engine, _deck([["R3-P01-17", 2]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-17", 1)
	var card_id := _hand_card(state, "R3-P01-17")
	_set_instance_plays(state, card_id, 1)
	var repeat := _play(engine, begun, "R3-P01-17", [])
	_check(repeat.ok and repeat.data.state.player.relax == 9, "P01-17 uses instance battle count", failures)

	begun = _begin(engine, _deck([["R3-P01-11", 1], ["R3-P01-19", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-19", 1)
	var previous_id := _hand_card(state, "R3-P01-11")
	_set_instance_plays(state, previous_id, 2)
	var strategy := _play(engine, begun, "R3-P01-11", [])
	var result19 := _play(engine, strategy, "R3-P01-19", [_target_a(strategy)])
	_check(
		result19.ok and _task(result19, TASK_A).work_remaining == 37,
		"P01-19 reads the previous strategy battle count",
		failures
	)

	begun = _begin(engine, _deck([["R3-P01-11", 1], ["R3-P01-24", 1], ["R3-P01-23", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-24", 1)
	_move_to_hand(state, "R3-P01-23", 1)
	var prep_strategy := _play(engine, begun, "R3-P01-11", [])
	var prep := _play(engine, prep_strategy, "R3-P01-24", [])
	var result23 := _play(engine, prep, "R3-P01-23", [_target_a(prep)])
	_check(
		result23.ok and _task(result23, TASK_A).work_remaining == 33,
		"P01-24 checks prior strategies and grants the next work bonus",
		failures
	)

	begun = _begin(engine, _deck([["R3-P01-11", 1], ["R3-P01-02", 1], ["R3-P01-33", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-02", 1)
	_move_to_hand(state, "R3-P01-33", 1)
	var retrieve_strategy := _play(engine, begun, "R3-P01-11", [])
	var retrieve_work := _play(engine, retrieve_strategy, "R3-P01-02", [_target_a(retrieve_strategy)])
	var relax_before33: int = retrieve_work.data.state.player.relax if retrieve_work.ok else 0
	var result33 := _play(engine, retrieve_work, "R3-P01-33", [_target_a(retrieve_work)])
	_check(
		result33.ok and result33.data.state.player.relax == relax_before33 + 6,
		"P01-33 reads the passive-retrieve flag",
		failures
	)

	begun = _begin(engine, _deck([["R3-P01-11", 1], ["R3-P01-08", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P01-11", 1)
	_move_to_hand(state, "R3-P01-08", 1)
	var link_strategy := _play(engine, begun, "R3-P01-11", [])
	var result08 := _play(engine, link_strategy, "R3-P01-08", [])
	_check(result08.ok, "P01-08 group link resolves", failures)
	if result08.ok:
		_check(_task(result08, TASK_A).work_remaining == 44, "P01-08 applies the link bonus to task A", failures)
		_check(_task(result08, TASK_B).work_remaining == 44, "P01-08 applies the link bonus to task B", failures)


func _check_all_cards_resolve(
	engine: BattleEngine, catalog: ContentDB, failures: Array[String]
) -> void:
	for card_id in P01_IDS:
		var rng := _rng()
		var deck := _deck([
			[card_id, 6], ["R3-P01-11", 1], ["R3-P01-23", 1],
			["R3-P01-12", 1], ["R3-P01-13", 1], ["R3-P01-17", 1],
		])
		var begun := _begin(engine, deck, rng)
		_check(begun.ok, card_id + " smoke battle starts", failures)
		if not begun.ok:
			continue
		var state: BattleState = begun.data.state
		state.player.focus = 10
		_add_anxiety(state)
		_move_to_hand(state, card_id, 1)
		_move_to_hand(state, "R3-P01-12", 1)
		_put_in_discard(state, "R3-P01-11", 1)
		_put_in_discard(state, "R3-P01-23", 1)
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
		"res://.godot/v3_p01_fixture_%d" % Time.get_ticks_usec()
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
	return RandomSource.new("cards-v3-p01").export_state().to_dictionary()


func _deck(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var serial := 0
	for entry in entries:
		var definition_id := str(entry[0])
		for index in int(entry[1]):
			serial += 1
			result.append(
				{
					"card_id": "card_%03d" % serial,
					"definition_id": definition_id,
					"upgrade_level": 0,
				}
			)
	return result


func _begin(engine: BattleEngine, deck: Array[Dictionary], rng: Dictionary) -> GameResult:
	return engine.begin(
		{
			"battle_id": "r3_p01_%d" % Time.get_ticks_usec(),
			"encounter_id": "R3_TEST",
			"character_id": "P01",
			"difficulty": "normal",
			"vitality": 72,
			"max_vitality": 72,
			"cards": deck,
			"relics": [],
			"rng_state": rng.duplicate(true),
		}
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
			ApiError.new(GameConstants.ERROR_INVALID_TARGET, "test.card_not_in_hand", {"id": definition_id})
		)
	var result := engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": card_id, "target_ids": target_ids}
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


func _has_card(state: BattleState, definition_id: String) -> bool:
	for card_id in state.zones.hand:
		if str(state.card_by_id.get(card_id, {}).get("definition_id", "")) == definition_id:
			return true
	return false


func _task_id(state: BattleState, definition_id: String) -> String:
	for task: Dictionary in state.tasks:
		if str(task.get("definition_id", "")) == definition_id:
			return str(task.get("task_id", ""))
	return ""


func _target_a(step: GameResult) -> String:
	return _task_id(step.data.state, TASK_A)


func _task(step: GameResult, definition_id: String) -> Dictionary:
	if not step.ok:
		return {}
	for task: Dictionary in step.data.state.tasks:
		if str(task.get("definition_id", "")) == definition_id:
			return task
	return {}


func _set_instance_plays(state: BattleState, card_id: String, count: int) -> void:
	state.v3["battle"] = {"instance_plays": {card_id: count}}


func _add_anxiety(state: BattleState) -> void:
	state.statuses.append(
		{
			"status_id": "anxiety",
			"instance_id": "anxiety_test_1",
			"source_id": "",
			"target_id": str(state.player.get("entity_id", "")),
			"stacks": 1,
			"expiry": "next_prepare",
		}
	)


func _has_player_status(state: BattleState, status_id: String) -> bool:
	for status: Dictionary in state.statuses:
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == str(state.player.get("entity_id", ""))
		):
			return true
	return false


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("cards v3 P01: " + label)
