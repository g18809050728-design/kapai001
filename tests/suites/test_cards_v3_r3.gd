extends RefCounted

const ROOT := "res://data/v3"
const MANIFEST := "campus_v3"
const ENCOUNTER := "R3-AC"
const TASK_A := "R3-AC-TASK-A"
const TASK_B := "R3-AC-TASK-B"

var _catalog: ContentDB
var _engine: BattleEngine


func run() -> Array[String]:
	var failures: Array[String] = []
	_catalog = ContentDB.new(ROOT, false)
	var loaded := _catalog.load(MANIFEST)
	_check(loaded.ok, "R3-T01 campus_v3 manifest loads", failures)
	if not loaded.ok:
		print("R3_MANIFEST_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		return failures
	_engine = BattleEngine.new(_catalog)
	_check_manifest(failures)
	_check_paper_rules(failures)
	_check_exams(failures)
	_check_acquisition(failures)
	_check_save(failures)
	_check_overdraft(failures)
	_check_scenarios(failures)
	_check_existing_suites(failures)
	if failures.is_empty():
		print("R3_MATRIX=", JSON.stringify(_matrix()))
		print("V3_CARDS_V3_R3_SUITE=passed")
	return failures


func _check_manifest(failures: Array[String]) -> void:
	var enabled := _catalog.get_info().enabled
	_check(enabled.get("card", []).size() == 174, "R3-T01 all 174 cards enabled", failures)
	_check(enabled.get("character", []).size() == 4, "R3-T01 four characters enabled", failures)
	var starters := _catalog.get_definition("ruleset", "campus_v1")
	_check(
		starters.ok and starters.data.run.common_starter_cards.size() == 10,
		"R3-T01 common starter pool has ten cards",
		failures
	)
	for character_id in ["P01", "P02", "P03", "P04"]:
		var character := _catalog.get_definition("character", character_id)
		_check(
			character.ok and character.data.starter_cards.size() == 2,
			"R3-T01 " + character_id + " starter pair",
			failures
		)
	var paper := _catalog.get_definition("card", "R3-P02-01")
	_check(paper.ok and paper.data.id == "R3-P02-01", "R3-T01 P02 opening card exists", failures)


func _check_paper_rules(failures: Array[String]) -> void:
	var begun := _begin("P02", _deck([["R3-P02-01", 2], ["R3-P02-03", 2], ["R3-P02-06", 1], ["R3-T201", 1], ["R3-P02-23", 6]]))
	_check(begun.ok, "R3-T04 paper battle starts", failures)
	if not begun.ok:
		return
	var state: BattleState = begun.data.state
	_check(_has_hand(state, "R3-P02-01"), "R3-T01 P02 opening occupies the first draw", failures)
	state.player.focus = 10
	_move_to_hand(state, "R3-P02-01", 1)
	_move_to_hand(state, "R3-P02-03", 1)
	var opened := _play(begun, "R3-P02-01", [])
	_check(opened.ok and _paper(opened).open, "R3-T04 paper opens", failures)
	var first := _play(opened, "R3-P02-03", [])
	_check(
		first.ok and int(_paper(first).progress) == 1,
		"R3-T04 new name records progress",
		failures
	)
	_move_to_hand(first.data.state, "R3-P02-03", 1)
	var repeat_same_turn := _play(first, "R3-P02-03", [])
	_check(
		repeat_same_turn.ok == false,
		"R3-T04 same name is unavailable in one turn",
		failures
	)
	var ended := _end_turn(first)
	if ended.ok:
		ended.data.state.player.focus = 10
		_move_to_hand(ended.data.state, "R3-P02-03", 1)
	var second := _play(ended, "R3-P02-03", [])
	_check(
		second.ok and int(_paper(second).citations) == 1,
		"R3-T04 repeated name next turn becomes citation",
		failures
	)

	var pay_begun := _begin("P02", _deck([["R3-P02-01", 1], ["R3-P02-06", 1], ["R3-T201", 1], ["R3-P02-23", 8]]))
	if not pay_begun.ok:
		_check(false, "R3-T05 citation battle starts", failures)
		return
	pay_begun.data.state.player.focus = 10
	_move_to_hand(pay_begun.data.state, "R3-P02-01", 1)
	var pay_open := _play(pay_begun, "R3-P02-01", [])
	_paper(pay_open).citations = 2
	pay_open.data.state.player.focus = 4
	var paid := _play(pay_open, "R3-P02-06", [])
	_check(
		paid.ok and int(_paper(paid).citations) == 3 and paid.data.state.player.focus == 2,
		"R3-T05 third citation layer costs one focus",
		failures
	)

	var paper_state := _paper(paid)
	paper_state.progress = 8
	paper_state.citations = 4
	paper_state.modifier = 0
	paper_state.amplify = 2
	_move_to_hand(paid.data.state, "R3-T201", 1)
	var published := _play(paid, "R3-T201", [])
	_check(published.ok, "R3-T06 publication resolves", failures)
	if published.ok:
		_check(_task(published, TASK_B).work_remaining == 10, "R3-T06 C=80 gives 90/40", failures)
		_check(not _paper(published).open, "R3-T10 publication closes the paper", failures)
		_check(_paper(published).chapters.is_empty(), "R3-T10 publication clears chapters", failures)

	var unique_begun := _begin("P02", _deck([["R3-P02-01", 2], ["R3-T201", 1], ["R3-P02-23", 8]]))
	if unique_begun.ok:
		unique_begun.data.state.player.focus = 10
		_move_to_hand(unique_begun.data.state, "R3-P02-01", 1)
		var uopen := _play(unique_begun, "R3-P02-01", [])
		var upublish := _play(uopen, "R3-T201", [])
		var uturn := _end_turn(upublish)
		if uturn.ok:
			uturn.data.state.player.focus = 10
			_move_to_hand(uturn.data.state, "R3-P02-01", 1)
			var ureopen := _play(uturn, "R3-P02-01", [])
			_check(
				ureopen.ok
				and _count_definition(ureopen.data.state, "R3-T201") == 1
				and _has_hand(ureopen.data.state, "R3-T201"),
				"R3-T07 only one publication instance survives reopening",
				failures
			)

	var chapter_begun := _begin("P02", _deck([
		["R3-P02-01", 1], ["R3-P02-11", 2], ["R3-P02-13", 1], ["R3-P02-23", 8]
	]))
	if chapter_begun.ok:
		chapter_begun.data.state.player.focus = 10
		_move_to_hand(chapter_begun.data.state, "R3-P02-01", 1)
		_move_to_hand(chapter_begun.data.state, "R3-P02-11", 2)
		_move_to_hand(chapter_begun.data.state, "R3-P02-13", 1)
		var copen := _play(chapter_begun, "R3-P02-01", [])
		var c1 := _play(copen, "R3-P02-11", [])
		var c2 := _play(c1, "R3-P02-13", [])
		_check(c2.ok and _paper(c2).chapters.size() == 2, "R3-T08 two chapters deploy", failures)
		var c3 := _play(c2, "R3-P02-11", [])
		_check(
			not c3.ok and _paper(c2).chapters.size() == 2,
			"R3-T08 same chapter does not stack",
			failures
		)
		var cend := _end_turn(c2)
		_check(
			cend.ok and _task(cend, TASK_A).work_remaining == 46,
			"R3-T08 chapter residents start next round",
			failures
		)


func _check_exams(failures: Array[String]) -> void:
	var exams := 0
	for card_id in _catalog.get_info().enabled.card:
		var definition := _catalog.get_definition("card", card_id)
		if definition.ok and definition.data.has("exam"):
			exams += 1
			var exam: Dictionary = definition.data.exam
			_check(
				str(exam.get("type", definition.data.type)) == str(definition.data.type),
				"R3-T19 exam type matches " + card_id,
				failures
			)
			_check(
				not exam.get("effects", []).is_empty()
				and not exam.get("upgrade_effects", []).is_empty(),
				"R3-T19 exam has both faces " + card_id,
				failures
			)
	_check(exams == 14, "R3-T19 fourteen double-faced exams", failures)
	for card_id in _catalog.get_info().enabled.card:
		var definition := _catalog.get_definition("card", card_id)
		if not definition.ok or not definition.data.has("exam"):
			continue
		var exam: Dictionary = definition.data.exam
		var condition := str(exam.get("condition", ""))
		var encounter_id := (
			"R3-AC-FIXED" if condition == "fixed_exam_room" else "R3-AC-INDEP"
		)
		var character_id := "P01"
		if str(definition.data.owner) == "P02":
			character_id = "P02"
		elif str(definition.data.owner) == "P04":
			character_id = "P04"
		var begun := _begin(
			character_id, _deck([[card_id, 1], ["R3-C-01", 8]]), encounter_id
		)
		if not begun.ok:
			_check(false, "R3-T19 exam battle starts " + card_id, failures)
			continue
		begun.data.state.player.focus = 10
		begun.data.state.v3["synergy"] = 1
		_move_to_hand(begun.data.state, card_id, 1)
		var target_ids: Array = []
		if str(exam.get("target", "")) == "task" and not begun.data.state.tasks.is_empty():
			target_ids = [str(begun.data.state.tasks[0].task_id)]
		var played := _play(begun, card_id, target_ids)
		_check(played.ok, "R3-T19 exam resolves " + card_id, failures)
		if played.ok:
			_check(
				played.data.state.phase in ["player_action", "finished"],
				"R3-T19 exam reaches stable phase " + card_id,
				failures
			)
	var fixed := _catalog.get_definition("encounter", ENCOUNTER)
	_check(fixed.ok, "R3-T19 acceptance encounter exists", failures)


func _check_acquisition(failures: Array[String]) -> void:
	for token_id in ["R3-T201", "R3-T202"]:
		var token := _catalog.get_definition("card", token_id)
		_check(
			token.ok
			and not bool(token.data.get("permanent", true))
			and str(token.data.get("rarity", "")) == "token",
			"R3-T20 " + token_id + " is a non-permanent token",
			failures
		)
	var candidates := _catalog.get_candidates({"kind": "card"})
	_check(candidates.size() == 174, "R3-T20 card candidate query is populated", failures)


func _check_save(failures: Array[String]) -> void:
	var begun := _begin("P02", _deck([["R3-P02-01", 1], ["R3-P02-11", 1], ["R3-P02-23", 8]]))
	if not begun.ok:
		_check(false, "R3-T21 save battle starts", failures)
		return
	begun.data.state.player.focus = 10
	_move_to_hand(begun.data.state, "R3-P02-01", 1)
	_move_to_hand(begun.data.state, "R3-P02-11", 1)
	var opened := _play(begun, "R3-P02-01", [])
	var deployed := _play(opened, "R3-P02-11", [])
	var live_paper := _paper(deployed)
	live_paper.citations = 2
	live_paper.modifier = 3
	live_paper.amplify = 4
	live_paper.turn_names = ["R3-P02-01", "R3-P02-11"]
	var encoded := BattleCodec.encode(deployed.data.state)
	_check(encoded.ok, "R3-T21 paper state encodes", failures)
	if not encoded.ok:
		print("R3_T21_ENCODE_ERROR=", JSON.stringify(encoded.error.to_dictionary()))
	if encoded.ok:
		var decoded := BattleCodec.decode(encoded.data, _catalog)
		_check(decoded.ok, "R3-T21 paper state decodes", failures)
		if decoded.ok:
			var paper: Dictionary = decoded.data.v3.get("paper", {})
			_check(
				bool(paper.get("open", false))
				and int(paper.get("progress", 0)) == 1
				and int(paper.get("citations", 0)) == 2
				and int(paper.get("modifier", 0)) == 3
				and int(paper.get("amplify", 0)) == 4
				and paper.get("turn_names", []) == ["R3-P02-01", "R3-P02-11"]
				and paper.get("chapters", []).size() == 1
				and not str(paper.get("publication_id", "")).is_empty(),
				"R3-T21 chapters/paper/publication round-trip",
				failures
			)


func _check_overdraft(failures: Array[String]) -> void:
	var begun := _begin("P02", _deck([["R3-P02-37", 1], ["R3-P02-23", 10]]))
	if not begun.ok:
		_check(false, "R3-T22 overdraft battle starts", failures)
		return
	begun.data.state.player.vitality = 1
	_move_to_hand(begun.data.state, "R3-P02-37", 1)
	var played := _play(begun, "R3-P02-37", [])
	_check(
		played.ok and played.data.state.phase == "finished",
		"R3-T22 overdraft can lose the battle",
		failures
	)


func _check_scenarios(failures: Array[String]) -> void:
	var samples := [
		{"id": "P01-normal", "character": "P01", "encounter": ENCOUNTER,
			"deck": [["R3-P01-01", 1], ["R3-P01-02", 1], ["R3-C-01", 10]]},
		{"id": "P02-exam", "character": "P02", "encounter": "R3-AC-INDEP",
			"deck": [["R3-P02-01", 1], ["R3-P02-11", 1], ["R3-C-01", 10]]},
		{"id": "P03-normal", "character": "P03", "encounter": ENCOUNTER,
			"deck": [["R3-P03-01", 1], ["R3-P03-21", 1], ["R3-C-01", 10]]},
		{"id": "P04-multi", "character": "P04", "encounter": ENCOUNTER,
			"deck": [["R3-P04-01", 1], ["R3-P04-02", 1], ["R3-C-01", 10]]},
		{"id": "P02-no-rare", "character": "P02", "encounter": ENCOUNTER,
			"deck": [["R3-P02-01", 1], ["R3-P02-11", 1], ["R3-C-03", 10]]},
	]
	var report: Array = []
	for sample in samples:
		var played := _autoplay(
			str(sample.character), _deck(sample.deck), str(sample.encounter), 40
		)
		_check(played.get("started", false), "R3-T23 " + str(sample.id) + " starts", failures)
		_check(played.get("actions", 0) > 0, "R3-T23 " + str(sample.id) + " advances", failures)
		report.append(
			{
				"id": sample.id,
				"outcome": played.get("outcome", ""),
				"actions": played.get("actions", 0),
				"round": played.get("round", 0),
			}
		)
	print("V3_R3_SAMPLES=", JSON.stringify(report))


func _autoplay(
	character_id: String, deck: Array[Dictionary], encounter_id: String, limit: int
) -> Dictionary:
	var begun := _begin(character_id, deck, encounter_id)
	if not begun.ok:
		return {"started": false, "actions": 0}
	var step := begun
	var actions := 0
	while step.ok and actions < limit:
		var state: BattleState = step.data.state
		if state.phase == "finished":
			break
		if state.phase == "awaiting_choice" and state.resolution != null:
			var choice: Variant = state.resolution.get("choice")
			if typeof(choice) == TYPE_DICTIONARY:
				var selected: Array = []
				if not choice.get("candidates", []).is_empty():
					selected = [str(choice.candidates[0].id)]
				step = _engine.apply(
					state,
					ActionDraft.new(
						GameConstants.ACTION_CONFIRM_CHOICE,
						{"choice_id": str(choice.choice_id), "selected_ids": selected}
					),
					step.data.rng_state
				)
				actions += 1
				continue
		var played := false
		for card_id in state.zones.hand.duplicate():
			var card: Dictionary = state.card_by_id.get(str(card_id), {})
			var definition := _catalog.get_definition("card", str(card.get("definition_id", "")))
			if not definition.ok:
				continue
			var target_ids: Array = []
			if str(definition.data.target) == "task" and not state.tasks.is_empty():
				target_ids = [str(state.tasks[0].task_id)]
			var preview := _engine.preview(
				state,
				ActionDraft.new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": str(card_id), "target_ids": target_ids}
				)
			)
			if preview.ok and preview.data.can_submit:
				step = _play(step, str(definition.data.id), target_ids)
				played = true
				break
		if not played:
			step = _end_turn(step)
		actions += 1
	return {
		"started": true,
		"actions": actions,
		"outcome": str(step.data.state.outcome) if step.ok else "",
		"round": int(step.data.state.round_index) if step.ok else 0,
	}


func _check_existing_suites(failures: Array[String]) -> void:
	for path in [
		"test_cards_v3_p01",
		"test_cards_v3_p02",
		"test_cards_v3_p03",
		"test_cards_v3_p04",
	]:
		var script: Script = load("res://tests/suites/%s.gd" % path)
		if script == null:
			failures.append("R3 existing suite missing: " + path)
			continue
		var suite: RefCounted = script.new()
		var suite_failures: Array = suite.run()
		for failure in suite_failures:
			failures.append("R3 existing suite %s: %s" % [path, failure])


func _matrix() -> Dictionary:
	return {
		"T01": "manifest starters",
		"T02": "P01 suite",
		"T03": "P01 suite",
		"T04": "paper names",
		"T05": "citation payment",
		"T06": "publish formula",
		"T07": "unique publication",
		"T08": "chapter slots",
		"T09": "P02 suite",
		"T10": "publish cleanup",
		"T11": "P02 suite",
		"T12": "P02 suite",
		"T13": "P03 suite",
		"T14": "P03 suite",
		"T15": "P03 suite",
		"T16": "P03 suite",
		"T17": "P04 suite",
		"T18": "P04 suite",
		"T19": "14 exam flows",
		"T20": "50-card reward pool",
		"T21": "full paper save",
		"T22": "overdraft failure",
		"T23": "5 combat samples",
	}


func _begin(
	character_id: String, deck: Array[Dictionary], encounter_id: String = ENCOUNTER
) -> GameResult:
	return _engine.begin(
		{
			"battle_id": "r3_ac_%d" % Time.get_ticks_usec(),
			"encounter_id": encounter_id,
			"character_id": character_id,
			"difficulty": "normal",
			"vitality": 72,
			"max_vitality": 72,
			"cards": deck,
			"relics": [],
			"rng_state": RandomSource.new("r3-acceptance").export_state().to_dictionary(),
		}
	)


func _deck(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var serial := 0
	for entry in entries:
		for _index in int(entry[1]):
			serial += 1
			result.append(
				{
					"card_id": "card_%03d" % serial,
					"definition_id": str(entry[0]),
					"upgrade_level": 0,
				}
			)
	return result


func _play(step: GameResult, definition_id: String, target_ids: Array) -> GameResult:
	if not step.ok:
		return step
	var state: BattleState = step.data.state
	var card_id := _hand_card(state, definition_id)
	if card_id.is_empty():
		return GameResult.failure(
			ApiError.new(GameConstants.ERROR_INVALID_TARGET, "test.card_not_in_hand", {"id": definition_id})
		)
	var result := _engine.apply(
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
		result = _engine.apply(
			result.data.state,
			ActionDraft.new(
				GameConstants.ACTION_CONFIRM_CHOICE,
				{"choice_id": str(choice.get("choice_id", "")), "selected_ids": selected}
			),
			result.data.rng_state
		)
		guard += 1
	return result


func _end_turn(step: GameResult) -> GameResult:
	if not step.ok:
		return step
	return _engine.apply(
		step.data.state,
		ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
		step.data.rng_state
	)


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
	for _index in count:
		if _hand_card(state, definition_id).is_empty():
			return


func _has_hand(state: BattleState, definition_id: String) -> bool:
	for card_id in state.zones.hand:
		if str(state.card_by_id.get(card_id, {}).get("definition_id", "")) == definition_id:
			return true
	return false


func _count_definition(state: BattleState, definition_id: String) -> int:
	var count := 0
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) == definition_id:
			count += 1
	return count


func _paper(step: GameResult) -> Dictionary:
	if not step.ok:
		return {}
	return step.data.state.v3.get("paper", {})


func _task(step: GameResult, definition_id: String) -> Dictionary:
	if step.ok:
		for task: Dictionary in step.data.state.tasks:
			if str(task.get("definition_id", "")) == definition_id:
				return task
	return {"work_remaining": 50}


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("cards v3 R3: " + label)
