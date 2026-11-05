extends RefCounted

const FIXTURE := "res://tests/fixtures/cards_v3_p02"
const MANIFEST := "test_cards_v3_p02"
const TASK_A := "R3_TEST_TASK_A"
const TASK_B := "R3_TEST_TASK_B"
const P02_IDS := [
	"R3-P02-01",
	"R3-P02-02",
	"R3-P02-03",
	"R3-P02-04",
	"R3-P02-05",
	"R3-P02-06",
	"R3-P02-07",
	"R3-P02-08",
	"R3-P02-09",
	"R3-P02-10",
	"R3-P02-11",
	"R3-P02-12",
	"R3-P02-13",
	"R3-P02-14",
	"R3-P02-15",
	"R3-P02-16",
	"R3-P02-17",
	"R3-P02-18",
	"R3-P02-19",
	"R3-P02-20",
	"R3-P02-21",
	"R3-P02-22",
	"R3-P02-23",
	"R3-P02-24",
	"R3-P02-25",
	"R3-P02-26",
	"R3-P02-27",
	"R3-P02-28",
	"R3-P02-29",
	"R3-P02-30",
	"R3-P02-31",
	"R3-P02-32",
	"R3-P02-33",
	"R3-P02-34",
	"R3-P02-35",
	"R3-P02-36",
	"R3-P02-37",
	"R3-P02-38",
	"R3-P02-39",
	"R3-P02-40",
]

var _fixture_root := ""


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := _copy_fixture()
	var catalog := ContentDB.new(root, true)
	var loaded := catalog.load(MANIFEST)
	_check(loaded.ok, "P02 fixture loads", failures)
	if not loaded.ok:
		print("V3_P02_LOAD_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(root)
		return failures
	var engine := BattleEngine.new(catalog)
	_check_paper_record(engine, failures)
	_check_citation(engine, failures)
	_check_publish(engine, failures)
	_check_unique_publication(engine, failures)
	_check_publication_discount(engine, failures)
	_check_chapters(engine, failures)
	_check_chapter_replace(engine, failures)
	_check_chapter_reuse(engine, failures)
	_check_amplify_and_topic(engine, failures)
	_check_abilities(engine, failures)
	_check_all_cards_resolve(engine, catalog, failures)
	_remove_fixture(root)
	if failures.is_empty():
		print("V3_P02_CARDS=", JSON.stringify({"total": P02_IDS.size(), "smoke": P02_IDS.size()}))
		print("V3_CARDS_V3_P02_SUITE=passed")
	return failures


func _check_paper_record(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-01", 1], ["R3-P02-03", 3], ["R3-P02-23", 6]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-03", 2)
	var opened := _play(engine, begun, "R3-P02-01", [])
	_check(opened.ok and _paper(opened).open, "P02 opens a paper", failures)
	_check(_has_card(opened.data.state, "R3-T201"), "P02 creates the unique publication", failures)
	var first := _play(engine, opened, "R3-P02-03", [])
	_check(
		first.ok and int(_paper(first).progress) == 1,
		"P02 records a new card name for progress",
		failures
	)
	var ended_first := engine.apply(
		first.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), first.data.rng_state
	)
	if ended_first.ok:
		ended_first.data.state.player.focus = 10
		_move_to_hand(ended_first.data.state, "R3-P02-03", 1)
	var second := _play(engine, ended_first, "R3-P02-03", [])
	_check(
		second.ok and int(_paper(second).progress) == 1 and int(_paper(second).citations) == 1,
		"P02 records a repeated name as citation",
		failures
	)


func _check_citation(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-01", 1], ["R3-P02-06", 2], ["R3-P02-23", 6]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-06", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	_paper(opened).citations = 2
	opened.data.state.player.focus = 4
	var citation := _play(engine, opened, "R3-P02-06", [])
	_check(
		(
			citation.ok
			and int(_paper(citation).citations) == 3
			and citation.data.state.player.focus == 2
		),
		"P02 pays one focus for the third citation layer",
		failures
	)


func _check_publish(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-01", 1], ["R3-T201", 1], ["R3-P02-23", 8]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var paper := _paper(opened)
	paper.progress = 8
	paper.citations = 4
	_move_to_hand(opened.data.state, "R3-T201", 1)
	var published := _play(engine, opened, "R3-T201", [])
	_check(published.ok, "P02 publishes the paper", failures)
	if published.ok:
		_check(_task(published, TASK_B).work_remaining == 10, "P02 publish uses C=80", failures)
		_check(not _paper(published).open, "P02 publish closes the paper", failures)

	begun = _begin(engine, _deck([["R3-P02-01", 1], ["R3-T201", 1], ["R3-P02-23", 8]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	opened = _play(engine, begun, "R3-P02-01", [])
	paper = _paper(opened)
	paper.progress = 10
	paper.citations = 5
	_move_to_hand(opened.data.state, "R3-T201", 1)
	published = _play(engine, opened, "R3-T201", [])
	_check(
		published.ok and published.data.state.outcome != null,
		"P02 C=100 publication wins through the bonus",
		failures
	)


func _check_unique_publication(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-01", 2], ["R3-T201", 1], ["R3-P02-23", 8]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 2)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var published := _play(engine, opened, "R3-T201", [])
	if not published.ok:
		_check(false, "P02 publication opens before reuse", failures)
		return
	var ended_publish := engine.apply(
		published.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		published.data.rng_state
	)
	if ended_publish.ok:
		ended_publish.data.state.player.focus = 10
		_move_to_hand(ended_publish.data.state, "R3-P02-01", 1)
	var reopened := _play(engine, ended_publish, "R3-P02-01", [])
	_check(
		(
			reopened.ok
			and _paper(reopened).open
			and _count_definition(reopened.data.state, "R3-T201") == 1
			and _has_card(reopened.data.state, "R3-T201")
		),
		"P02 reuses the same unique publication instance",
		failures
	)


func _check_publication_discount(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(
		engine, _deck([["R3-P02-01", 1], ["R3-P02-28", 1], ["R3-T201", 1], ["R3-P02-23", 8]]), rng
	)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-28", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var discounted := _play(engine, opened, "R3-P02-28", [])
	var published := _play(engine, discounted, "R3-T201", [])
	_check(
		published.ok and published.data.state.player.focus == 9,
		"P02-28 discounts the next publication by one focus",
		failures
	)


func _count_definition(state: BattleState, definition_id: String) -> int:
	var count := 0
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) == definition_id:
			count += 1
	return count


func _check_chapters(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(
		engine, _deck([["R3-P02-01", 1], ["R3-P02-11", 1], ["R3-P02-13", 1], ["R3-P02-23", 8]]), rng
	)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-11", 1)
	_move_to_hand(state, "R3-P02-13", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var intro := _play(engine, opened, "R3-P02-11", [])
	var results := _play(engine, intro, "R3-P02-13", [])
	_check(
		results.ok and _paper(results).chapters.size() == 2, "P02 deploys two chapters", failures
	)
	var ended := engine.apply(
		results.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		results.data.rng_state
	)
	_check(
		ended.ok and _task(ended, TASK_A).work_remaining == 46,
		"P02 chapter residents run at prepare",
		failures
	)


func _check_chapter_replace(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(
		engine,
		_deck(
			[
				["R3-P02-01", 1],
				["R3-P02-11", 1],
				["R3-P02-12", 1],
				["R3-P02-13", 1],
				["R3-P02-14", 1],
				["R3-P02-23", 8],
			]
		),
		rng
	)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	for id in ["R3-P02-01", "R3-P02-11", "R3-P02-12", "R3-P02-13", "R3-P02-14"]:
		_move_to_hand(state, id, 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var step := _play(engine, opened, "R3-P02-11", [])
	step = _play(engine, step, "R3-P02-12", [])
	step = _play(engine, step, "R3-P02-13", [])
	var pending := _play_pending(engine, step, "R3-P02-14", [])
	_check(
		(
			pending.ok
			and pending.data.pending_choice != null
			and str(pending.data.pending_choice.kind) == "chapter_replace"
			and pending.data.pending_choice.candidates.size() == 3
		),
		"P02 full chapter slots request a replacement choice",
		failures
	)
	if pending.ok and pending.data.pending_choice != null:
		var choice: Dictionary = pending.data.pending_choice
		var replaced := str(choice.candidates[0].id)
		var confirmed := engine.apply(
			pending.data.state,
			ActionDraft.new(
				GameConstants.ACTION_CONFIRM_CHOICE,
				{"choice_id": str(choice.choice_id), "selected_ids": [replaced]}
			),
			pending.data.rng_state
		)
		_check(
			(
				confirmed.ok
				and _paper(confirmed).chapters.size() == 3
				and confirmed.data.state.zones.discard.has(replaced)
			),
			"P02 replacement discards the preselected chapter",
			failures
		)


func _check_chapter_reuse(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(
		engine, _deck([["R3-P02-01", 1], ["R3-P02-11", 1], ["R3-P02-27", 1], ["R3-P02-23", 8]]), rng
	)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-11", 1)
	_move_to_hand(state, "R3-P02-27", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	var deployed := _play(engine, opened, "R3-P02-11", [])
	var copied := _play(engine, deployed, "R3-P02-27", [])
	var reused := _play(engine, copied, "R3-P02-11", [])
	_check(
		reused.ok and _paper(reused).chapters.size() == 1,
		"P02 chapter copy performs manual reuse without redeploying",
		failures
	)


func _check_amplify_and_topic(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-01", 1], ["R3-P02-03", 2], ["R3-P02-23", 8]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-03", 1)
	var opened := _play(engine, begun, "R3-P02-01", [])
	_paper(opened).amplify = 2
	var amplified := _play(engine, opened, "R3-P02-03", [])
	_check(
		(
			amplified.ok
			and amplified.data.state.player.relax == 7
			and int(_paper(amplified).amplify) == 0
		),
		"P02 amplification boosts the first white-list effect",
		failures
	)

	begun = _begin(engine, _deck([["R3-P02-01", 1], ["R3-P02-21", 1], ["R3-P02-23", 8]]), rng)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-21", 1)
	opened = _play(engine, begun, "R3-P02-01", [])
	_paper(opened).used_names = ["R3-P02-03"]
	var topic := _play(engine, opened, "R3-P02-21", [])
	_check(
		(
			topic.ok
			and not _paper(topic).used_names.has("R3-P02-03")
			and int(_paper(topic).modifier) == -1
		),
		"P02 change-topic resets a name and lowers the modifier",
		failures
	)


func _check_abilities(engine: BattleEngine, failures: Array[String]) -> void:
	var rng := _rng()
	var begun := _begin(engine, _deck([["R3-P02-10", 1], ["R3-P02-01", 1], ["R3-P02-03", 8]]), rng)
	var state: BattleState = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-10", 1)
	var ability := _play(engine, begun, "R3-P02-10", [])
	var ended := engine.apply(
		ability.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		ability.data.rng_state
	)
	if ended.ok:
		ended.data.state.player.focus = 10
		_move_to_hand(ended.data.state, "R3-P02-01", 1)
		_move_to_hand(ended.data.state, "R3-P02-03", 1)
	var opened := _play(engine, ended, "R3-P02-01", [])
	var progress := _play(engine, opened, "R3-P02-03", [])
	_check(
		progress.ok and progress.data.state.player.relax >= 2,
		"P02-10 triggers on paper progress",
		failures
	)

	begun = _begin(
		engine,
		_deck(
			[
				["R3-P02-19", 1],
				["R3-P02-01", 1],
				["R3-P02-11", 2],
				["R3-P02-13", 1],
				["R3-P02-23", 6]
			]
		),
		rng
	)
	state = begun.data.state
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-19", 1)
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-11", 2)
	_move_to_hand(state, "R3-P02-13", 1)
	var p19 := _play(engine, begun, "R3-P02-19", [])
	var p19_end := engine.apply(
		p19.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p19.data.rng_state
	)
	if p19_end.ok:
		p19_end.data.state.player.focus = 10
		_move_to_hand(p19_end.data.state, "R3-P02-01", 1)
		_move_to_hand(p19_end.data.state, "R3-P02-11", 1)
		_move_to_hand(p19_end.data.state, "R3-P02-13", 1)
	var p19_open := _play(engine, p19_end, "R3-P02-01", [])
	var p19_a := _play(engine, p19_open, "R3-P02-11", [])
	var p19_b := _play(engine, p19_a, "R3-P02-13", [])
	var p19_ready := engine.apply(
		p19_b.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), p19_b.data.rng_state
	)
	_check(
		p19_ready.ok and p19_ready.data.state.player.relax == 4,
		"P02-19 triggers after a two-chapter window",
		failures
	)


func _check_all_cards_resolve(
	engine: BattleEngine, catalog: ContentDB, failures: Array[String]
) -> void:
	for card_id in P02_IDS:
		var rng := _rng()
		var deck := _deck(
			[
				[card_id, 5],
				["R3-P02-01", 2],
				["R3-P02-11", 2],
				["R3-P02-13", 1],
				["R3-P02-23", 6],
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
		var step := begun
		var paper_open: bool = card_id != "R3-P02-01" and card_id != "R3-P02-39"
		if card_id == "R3-P02-39":
			var insert := _any_card(state, "R3-P02-01")
			if not insert.is_empty():
				state.zones.hand.erase(insert)
				state.zones.draw.erase(insert)
				state.zones.discard.append(insert)
		if paper_open:
			_move_to_hand(state, "R3-P02-01", 1)
			step = _play(engine, begun, "R3-P02-01", [])
			if step.ok:
				step.data.state.player.focus = 10
				if card_id in ["R3-P02-17", "R3-P02-30"]:
					_move_to_hand(step.data.state, "R3-P02-11", 1)
					_move_to_hand(step.data.state, "R3-P02-13", 1)
					step = _play(engine, step, "R3-P02-11", [])
					step = _play(engine, step, "R3-P02-13", [])
				elif card_id in ["R3-P02-20", "R3-P02-27"]:
					_move_to_hand(step.data.state, "R3-P02-11", 1)
					step = _play(engine, step, "R3-P02-11", [])
				elif card_id == "R3-P02-09":
					_paper(step).progress = 7
				elif card_id == "R3-P02-26":
					_paper(step).citations = 1
		var target_ids := []
		var definition = catalog.get_definition("card", card_id).data
		if str(definition.get("target", "")) == "task":
			target_ids = [_target_a(step)]
		var result := _play(engine, step, card_id, target_ids)
		_check(result.ok, card_id + " resolves through the v3 engine", failures)
		if result.ok:
			_check(
				result.data.state.phase in ["player_action", "finished"],
				card_id + " reaches a stable phase",
				failures
			)


func _copy_fixture() -> String:
	_fixture_root = ProjectSettings.globalize_path(
		"res://.godot/v3_p02_fixture_%d" % Time.get_ticks_usec()
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
	return RandomSource.new("cards-v3-p02").export_state().to_dictionary()


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
				"battle_id": "r3_p02_%d" % Time.get_ticks_usec(),
				"encounter_id": "R3_TEST",
				"character_id": "P02",
				"difficulty": "normal",
				"vitality": 72,
				"max_vitality": 72,
				"cards": deck,
				"relics": [],
				"rng_state": rng.duplicate(true),
			}
		)
	)


func _play_pending(
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
	return engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD, {"card_instance_id": card_id, "target_ids": target_ids}
		),
		step.data.rng_state
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


func _any_card(state: BattleState, definition_id: String) -> String:
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) == definition_id:
			return str(card_id)
	return ""


func _move_to_hand(state: BattleState, definition_id: String, count: int) -> void:
	for index in count:
		var card_id := _hand_card(state, definition_id)
		if card_id.is_empty():
			return


func _has_card(state: BattleState, definition_id: String) -> bool:
	for card_id in state.zones.hand:
		if str(state.card_by_id.get(card_id, {}).get("definition_id", "")) == definition_id:
			return true
	return false


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


func _paper(step: GameResult) -> Dictionary:
	if not step.ok:
		return {}
	return step.data.state.v3.get("paper", {})


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
		failures.append("cards v3 P02: " + label)
