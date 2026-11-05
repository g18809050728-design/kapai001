extends RefCounted

const FIXTURE := "res://tests/fixtures/cards_v3_p04"
const MANIFEST := "test_cards_v3_p04"
const TASK_A := "R3_TEST_TASK_A"
const TASK_B := "R3_TEST_TASK_B"
const P04_IDS := [
	"R3-P04-01",
	"R3-P04-02",
	"R3-P04-03",
	"R3-P04-04",
	"R3-P04-05",
	"R3-P04-06",
	"R3-P04-07",
	"R3-P04-08",
	"R3-P04-09",
	"R3-P04-10",
	"R3-P04-11",
	"R3-P04-12",
	"R3-P04-13",
	"R3-P04-14",
	"R3-P04-15",
	"R3-P04-16",
	"R3-P04-17",
	"R3-P04-18",
	"R3-P04-19",
	"R3-P04-20",
	"R3-P04-21",
	"R3-P04-22",
	"R3-P04-23",
	"R3-P04-24",
	"R3-P04-25",
	"R3-P04-26",
	"R3-P04-27",
	"R3-P04-28",
	"R3-P04-29",
	"R3-P04-30",
	"R3-P04-31",
	"R3-P04-32",
	"R3-P04-33",
	"R3-P04-34",
	"R3-P04-35",
	"R3-P04-36",
	"R3-P04-37",
	"R3-P04-38",
	"R3-P04-39",
	"R3-P04-40",
]

var _fixture_root := ""


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := _copy_fixture()
	var catalog := ContentDB.new(root, true)
	var loaded := catalog.load(MANIFEST)
	_check(loaded.ok, "P04 fixture loads", failures)
	if not loaded.ok:
		print("V3_P04_LOAD_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(root)
		return failures
	var engine := BattleEngine.new(catalog)
	_check_synergy(engine, failures)
	_check_partners(engine, failures)
	_check_exam(engine, failures)
	_check_conditions(engine, failures)
	_check_all_cards_resolve(engine, catalog, failures)
	_remove_fixture(root)
	if failures.is_empty():
		print("V3_P04_CARDS=", JSON.stringify({"total": P04_IDS.size(), "smoke": P04_IDS.size()}))
		print("V3_CARDS_V3_P04_SUITE=passed")
	return failures


func _check_synergy(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P04-02", 10]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-02", 1)
	var gained := _play(engine, begun, "R3-P04-02", [])
	_check(gained.ok and _synergy(gained) == 1, "P04 gains one synergy", failures)

	begun = _begin(engine, _deck([["R3-P04-30", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.v3["synergy"] = 3
	_move_to_hand(state, "R3-P04-30", 1)
	var all_in := _play(engine, begun, "R3-P04-30", [_target_a(begun)])
	_check(
		all_in.ok and _task(all_in, TASK_A).work_remaining == 29,
		"P04-30 spends all synergy for completion",
		failures
	)
	_check(all_in.ok and _synergy(all_in) == 0, "P04-30 empties synergy", failures)

	begun = _begin(engine, _deck([["R3-P04-40", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.v3["synergy"] = 2
	_move_to_hand(state, "R3-P04-40", 1)
	var group := _play(engine, begun, "R3-P04-40", [])
	_check(
		group.ok and _task(group, TASK_A).work_remaining == 40,
		"P04-40 spends synergy on group completion",
		failures
	)
	_check(
		group.ok and _task(group, TASK_B).work_remaining == 40, "P04-40 hits both tasks", failures
	)


func _check_partners(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P04-01", 10]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	var summoned := _play(engine, begun, "R3-P04-01", [])
	_check(summoned.ok and summoned.data.state.units.size() == 1, "P04 summons a partner", failures)
	if summoned.ok:
		var unit: Dictionary = summoned.data.state.units[0]
		_check(
			(
				str(unit.definition_id) == "R3-U01"
				and int(unit.vitality) == 3
				and int(unit.cooperation) == 2
			),
			"P04 summons U01 with its base stats",
			failures
		)
		_check(
			bool(summoned.data.state.v3.get("turn", {}).get("summoned_partner", false)),
			"P04 records the partner summon",
			failures
		)

	begun = _begin(engine, _deck([["R3-P04-01", 2], ["R3-P04-06", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.v3["synergy"] = 1
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-06", 1)
	var lead := _play(engine, begun, "R3-P04-01", [])
	var unit_id := str(lead.data.state.units[0].unit_id)
	var command := _play(engine, lead, "R3-P04-06", [unit_id])
	_check(
		command.ok and _task(command, TASK_A).work_remaining == 48,
		"P04-06 gives a partner an extra action",
		failures
	)
	_check(command.ok and _synergy(command) == 1, "P04-06 spends synergy", failures)

	begun = _begin(engine, _deck([["R3-P04-01", 2], ["R3-P04-10", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-10", 1)
	lead = _play(engine, begun, "R3-P04-01", [])
	var group := _play(engine, lead, "R3-P04-10", [])
	_check(
		group.ok and _task(group, TASK_A).work_remaining == 46,
		"P04-10 gives all partners extra actions",
		failures
	)
	_check(group.ok and group.data.state.units.size() == 2, "P04-10 summons another U01", failures)

	begun = _begin(engine, _deck([["R3-P04-01", 1], ["R3-P04-12", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-12", 1)
	lead = _play(engine, begun, "R3-P04-01", [])
	lead.data.state.units[0].vitality = 1
	unit_id = str(lead.data.state.units[0].unit_id)
	var healed := _play(engine, lead, "R3-P04-12", [unit_id])
	_check(
		healed.ok and int(healed.data.state.units[0].vitality) == 3,
		"P04-12 heals a partner",
		failures
	)
	_check(
		healed.ok and bool(healed.data.state.v3.get("turn", {}).get("healed_partner", false)),
		"P04 records partner healing",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-01", 1], ["R3-P04-15", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-15", 1)
	lead = _play(engine, begun, "R3-P04-01", [])
	unit_id = str(lead.data.state.units[0].unit_id)
	var retreated := _play(engine, lead, "R3-P04-15", [unit_id])
	_check(
		retreated.ok and retreated.data.state.units.is_empty(),
		"P04-15 retreats a partner",
		failures
	)
	_check(retreated.ok and _synergy(retreated) == 2, "P04-15 gains synergy", failures)


func _check_exam(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P04-01", 10]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	state.exam_flags = ["independent_answer"]
	_move_to_hand(state, "R3-P04-01", 1)
	var exam := _play(engine, begun, "R3-P04-01", [_target_a(begun)])
	_check(exam.ok and exam.data.state.units.is_empty(), "P04 exam face does not summon", failures)
	_check(
		exam.ok and _task(exam, TASK_A).work_remaining == 45, "P04 exam face completes 5", failures
	)

	begun = _begin(engine, _deck([["R3-P04-10", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.exam_flags = ["independent_answer"]
	_move_to_hand(state, "R3-P04-10", 1)
	var exam_group := _play(engine, begun, "R3-P04-10", [])
	_check(
		(
			exam_group.ok
			and _task(exam_group, TASK_A).work_remaining == 43
			and _task(exam_group, TASK_B).work_remaining == 43
		),
		"P04 exam face completes all tasks for 7",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-06", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.exam_flags = ["independent_answer"]
	state.v3["synergy"] = 1
	_move_to_hand(state, "R3-P04-06", 1)
	var exam_command := _play(engine, begun, "R3-P04-06", [_target_a(begun)])
	_check(
		(
			exam_command.ok
			and _task(exam_command, TASK_A).work_remaining == 41
			and _synergy(exam_command) == 0
		),
		"P04-06 exam face spends synergy without a partner",
		failures
	)


func _check_conditions(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P04-01", 2], ["R3-P04-13", 1]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-13", 1)
	var lead := _play(engine, begun, "R3-P04-01", [])
	var support := _play(engine, lead, "R3-P04-13", [_target_a(lead)])
	_check(
		support.ok and _task(support, TASK_A).work_remaining == 40,
		"P04-13 counts partners",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-01", 2], ["R3-P04-27", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-27", 1)
	lead = _play(engine, begun, "R3-P04-01", [])
	var collaboration := _play(engine, lead, "R3-P04-27", [_target_a(lead)])
	_check(
		collaboration.ok and _task(collaboration, TASK_A).work_remaining == 38,
		"P04-27 counts cooperation cards",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-01", 1], ["R3-P04-12", 1], ["R3-P04-19", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-12", 1)
	_move_to_hand(state, "R3-P04-19", 1)
	lead = _play(engine, begun, "R3-P04-01", [])
	var unit_id := str(lead.data.state.units[0].unit_id)
	var heal := _play(engine, lead, "R3-P04-12", [unit_id])
	var handoff := _play(engine, heal, "R3-P04-19", [_target_a(heal)])
	_check(
		handoff.ok and handoff.data.state.player.relax == 7,
		"P04-19 reads partner healing",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-17", 1], ["R3-P04-01", 1], ["R3-P04-12", 8]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P04-17", 1)
	var ability := _play(engine, begun, "R3-P04-17", [])
	var ended := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	if ended.ok:
		ended.data.state.player.focus = 10
		_move_to_hand(ended.data.state, "R3-P04-01", 1)
	var hand_before: int = ended.data.state.zones.hand.size()
	var cooperation := _play(engine, ended, "R3-P04-01", [])
	var ability_used := false
	if cooperation.ok and not cooperation.data.state.v3.get("abilities", []).is_empty():
		ability_used = int(cooperation.data.state.v3.abilities[0].get("uses_this_round", 0)) == 1
	_check(
		cooperation.ok and cooperation.data.state.zones.hand.size() == hand_before and ability_used,
		"P04-17 draws after the first cooperation",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-20", 1], ["R3-P04-01", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P04-20", 1)
	var p20 := _play(engine, begun, "R3-P04-20", [])
	var p20_end := engine.apply(
		p20.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p20.data.rng_state
	)
	if p20_end.ok:
		p20_end.data.state.player.focus = 10
		_move_to_hand(p20_end.data.state, "R3-P04-01", 1)
	var p20_coop := _play(engine, p20_end, "R3-P04-01", [])
	_check(
		p20_coop.ok and _synergy(p20_coop) == 2 and p20_coop.data.state.player.relax == 6,
		"P04-20 grants synergy and relax on the first cooperation",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-01", 2], ["R3-P04-03", 1]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P04-01", 1)
	_move_to_hand(state, "R3-P04-03", 1)
	var lead03 := _play(engine, begun, "R3-P04-01", [])
	var per_partner := _play(engine, lead03, "R3-P04-03", [_target_a(lead03)])
	_check(
		per_partner.ok and _task(per_partner, TASK_A).work_remaining == 42,
		"P04-03 completes once per partner",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-25", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.v3["synergy"] = 2
	_add_anxiety(state)
	_move_to_hand(state, "R3-P04-25", 1)
	var p25 := _play(engine, begun, "R3-P04-25", [])
	_check(
		(
			p25.ok
			and _synergy(p25) == 0
			and p25.data.state.player.relax == 11
			and not _has_player_status(p25.data.state, "anxiety")
		),
		"P04-25 spends up to two synergy",
		failures
	)

	begun = _begin(engine, _deck([["R3-P04-22", 1]]), rng)
	state = begun.data.state
	_move_to_hand(state, "R3-P04-22", 1)
	var p22 := _play(engine, begun, "R3-P04-22", [])
	var p22_end := engine.apply(
		p22.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p22.data.rng_state
	)
	_check(
		p22_end.ok and _synergy(p22_end) == 1, "P04-22 grants synergy without partners", failures
	)

	begun = _begin(engine, _deck([["R3-P04-39", 10]]), rng)
	state = begun.data.state
	state.player.focus = 10
	state.v3["synergy"] = 0
	_move_to_hand(state, "R3-P04-39", 1)
	var p39 := _play(engine, begun, "R3-P04-39", [])
	_check(p39.ok and _synergy(p39) == 1, "P04-39 grants synergy at zero", failures)


func _check_all_cards_resolve(
	engine: BattleEngine, catalog: ContentDB, failures: Array[String]
) -> void:
	for card_id in P04_IDS:
		var rng := _rng()
		var deck := _deck(
			[
				[card_id, 5],
				["R3-P04-01", 2],
				["R3-P04-12", 1],
				["R3-P04-27", 1],
				["R3-P04-03", 1],
			]
		)
		var begun := _begin(engine, deck, rng)
		_check(begun.ok, card_id + " smoke battle starts", failures)
		if not begun.ok:
			continue
		var state: BattleState = begun.data.state
		state.player.focus = 10
		state.v3["synergy"] = 3
		_add_anxiety(state)
		_move_to_hand(state, "R3-P04-01", 1)
		_move_to_hand(state, card_id, 1)
		_move_to_hand(state, "R3-P04-12", 1)
		var lead := _play(engine, begun, "R3-P04-01", [])
		var target_ids := []
		var definition = catalog.get_definition("card", card_id).data
		if str(definition.get("target", "")) == "task":
			target_ids = [_target_a(lead)]
		elif str(definition.get("target", "")) == "unit":
			if not lead.data.state.units.is_empty():
				target_ids = [str(lead.data.state.units[0].unit_id)]
		var step := _play(engine, lead, card_id, target_ids)
		_check(step.ok, card_id + " resolves through the v3 engine", failures)
		if step.ok:
			_check(
				step.data.state.phase in ["player_action", "finished"],
				card_id + " reaches a stable phase",
				failures
			)


func _copy_fixture() -> String:
	_fixture_root = ProjectSettings.globalize_path(
		"res://.godot/v3_p04_fixture_%d" % Time.get_ticks_usec()
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
	return RandomSource.new("cards-v3-p04").export_state().to_dictionary()


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
				"battle_id": "r3_p04_%d" % Time.get_ticks_usec(),
				"encounter_id": "R3_TEST",
				"character_id": "P04",
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


func _synergy(step: GameResult) -> int:
	if not step.ok:
		return 0
	return int(step.data.state.v3.get("synergy", 0))


func _has_player_status(state: BattleState, status_id: String) -> bool:
	for status: Dictionary in state.statuses:
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == str(state.player.get("entity_id", ""))
		):
			return true
	return false


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
		failures.append("cards v3 P04: " + label)
