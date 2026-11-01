extends SceneTree

const ELITES := [
	"Q01", "E01", "E02", "E03", "E04", "E05", "E06", "E07",
	"Q0A", "Q0B", "Q0C", "Q0D", "Q0E"
]
const CHARACTERS := ["P01", "P04"]
const SEEDS := [
	"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
	"13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24"
]
const MAX_STEPS := 80


func _initialize() -> void:
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	if not loaded.ok:
		print("PLAYTEST_ERROR=", JSON.stringify(loaded.error.to_dictionary()))
		quit(1)
		return
	var engine := BattleEngine.new(catalog)
	var runs: Array[Dictionary] = []
	for character in CHARACTERS:
		for encounter_id in ELITES:
			for seed in SEEDS:
				runs.append(_play(engine, catalog, character, encounter_id, seed))
	print("PLAYTEST_RESULT=", JSON.stringify(_summarize(runs)))
	quit(0)


func _play(
	engine: BattleEngine, catalog: ContentDB, character: String, encounter_id: String, seed: String
) -> Dictionary:
	var service := RunService.new(catalog)
	var created := service.create(StartRunRequest.new(StringName(character), &"normal", "campus_mvp", seed))
	if not created.ok:
		return {"character": character, "encounter": encounter_id, "seed": seed, "error": "run create failed"}
	var run: RunState = created.data.state
	var cards: Array[Dictionary] = []
	for card in run.cards:
		cards.append(
			{
				"card_id": card.card_id,
				"definition_id": card.definition_id,
				"upgrade_level": card.upgrade_level,
			}
		)
	var relic_ids: Array[String] = []
	for relic in run.relics:
		relic_ids.append(str(relic.definition_id))
	var begun := engine.begin(
		{
			"battle_id": "play_%s_%s_%s" % [character, encounter_id, seed],
			"node_id": "play_node",
			"encounter_id": encounter_id,
			"character_id": character,
			"difficulty": "normal",
			"vitality": run.vitality,
			"max_vitality": run.max_vitality,
			"cards": cards,
			"relics": relic_ids,
			"rng_state": created.data.rng_states.duplicate(true),
		}
	)
	if not begun.ok:
		return {
			"character": character,
			"encounter": encounter_id,
			"seed": seed,
			"error": "begin failed: " + str(begun.error.message_key),
		}
	var state: BattleState = begun.data.state
	var rng_state: Dictionary = begun.data.rng_state
	var rounds := 0
	for step_index in MAX_STEPS:
		if state.phase == "finished" or state.outcome != null:
			break
		var action := _choose_action(engine, state)
		var step := engine.apply(state, action, rng_state)
		if not step.ok:
			return {
				"character": character,
				"encounter": encounter_id,
				"seed": seed,
				"error": "apply failed: " + str(step.error.message_key),
				"round": state.round_index,
				"ddl": state.ddl,
				"vitality": int(state.player.vitality),
			}
		state = step.data.state
		rng_state = step.data.rng_state
		var guards := 0
		while step.data.pending_choice != null and guards < 8:
			guards += 1
			var choice: Dictionary = step.data.pending_choice
			var selected: Array[String] = []
			for candidate in choice.get("candidates", []):
				if selected.size() >= int(choice.get("min_count", 0)):
					break
				selected.append(str(candidate.get("id", "")))
			var confirmed := engine.apply(
				state,
				ActionDraft.new(
					GameConstants.ACTION_CONFIRM_CHOICE,
					{"choice_id": str(choice.get("choice_id", "")), "selected_ids": selected}
				),
				rng_state
			)
			if not confirmed.ok:
				return {
					"character": character,
					"encounter": encounter_id,
					"seed": seed,
					"error": "choice failed: " + str(confirmed.error.message_key),
				}
			state = confirmed.data.state
			rng_state = confirmed.data.rng_state
			step = confirmed
		if action.type == GameConstants.ACTION_END_TURN:
			rounds += 1
	if state.outcome == null:
		return {
			"character": character,
			"encounter": encounter_id,
			"seed": seed,
			"error": "unfinished",
			"round": state.round_index,
			"ddl": state.ddl,
			"vitality": int(state.player.vitality),
			"tasks": _task_snapshot(state),
		}
	return {
		"character": character,
		"encounter": encounter_id,
		"seed": seed,
		"result": str(state.outcome.result),
		"reason": str(state.outcome.reason),
		"rounds": rounds,
		"ddl_left": state.ddl,
		"vitality": int(state.player.vitality),
		"max_vitality": int(state.player.max_vitality),
	}


func _choose_action(engine: BattleEngine, state: BattleState) -> ActionDraft:
	var incoming := _incoming_pressure(state)
	var relax := int(state.player.get("relax", 0))
	var focus := int(state.player.get("focus", 0))
	var units := state.units
	var best: Dictionary = {}
	var best_score := -1
	for card_id in state.zones.hand:
		var card: Dictionary = state.card_by_id.get(card_id, {})
		var face_result := engine.resolve_face(state, str(card_id))
		if not face_result.ok:
			continue
		var face: Dictionary = face_result.data
		if bool(face.get("unplayable", false)):
			continue
		var quote := engine.calculate_cost(state, str(card_id))
		if not quote.ok or int(quote.data.cost) > focus:
			continue
		var vitality := int(state.player.get("vitality", 0))
		if int(quote.data.vitality_cost) > 0 and vitality - int(quote.data.vitality_cost) < 1:
			continue
		var score := _score(face, incoming, relax)
		if score <= 0:
			continue
		if score > best_score:
			best_score = score
			best = _payload_for(state, str(card_id), face, units)
	if not best.is_empty():
		return ActionDraft.new(GameConstants.ACTION_PLAY_CARD, best)
	return ActionDraft.new(GameConstants.ACTION_END_TURN, {})


func _score(face: Dictionary, incoming: int, relax: int) -> int:
	var score := 0
	var needs_defense := incoming - relax
	for effect: Dictionary in _effects(face):
		match str(effect.get("op", "")):
			"relax":
				score = maxi(score, 80 if needs_defense > 0 else 6)
			"complete":
				score = maxi(score, 50)
			"draw", "gain_focus":
				score = maxi(score, 20)
			"heal":
				score = maxi(score, 30)
			"summon_unit":
				score = maxi(score, 40)
			_:
				score = maxi(score, 4)
	return score


func _payload_for(
	state: BattleState, card_id: String, face: Dictionary, units: Array[Dictionary]
) -> Dictionary:
	var payload := {"card_instance_id": card_id, "target_ids": []}
	var target := str(face.get("target", "self"))
	if target == "task":
		var task_id := _first_task(state)
		payload.target_ids = [task_id] if not task_id.is_empty() else []
	elif target == "unit" and _has_op(face, "summon_unit"):
		if units.size() >= 3 and not units.is_empty():
			var weakest := ""
			var lowest := 2147483647
			for unit: Dictionary in units:
				if int(unit.get("vitality", 0)) < lowest:
					lowest = int(unit.get("vitality", 0))
					weakest = str(unit.get("unit_id", ""))
			payload.replace_unit_id = weakest
	return payload


func _effects(face: Dictionary) -> Array:
	var effects: Array = []
	effects.append_array(face.get("pre_effects", []))
	effects.append_array(face.get("effects", []))
	return effects


func _has_op(face: Dictionary, op: String) -> bool:
	for effect: Dictionary in _effects(face):
		if str(effect.get("op", "")) == op:
			return true
	return false


func _incoming_pressure(state: BattleState) -> int:
	var total := 0
	for task: Dictionary in state.tasks:
		if int(task.get("eligible_round", 1)) > state.round_index:
			continue
		var intent: Dictionary = task.get("intent_snapshot", {})
		var pressure := int(intent.get("pressure", 0)) * int(intent.get("pressure_times", 1))
		total += pressure
	return total


func _first_task(state: BattleState) -> String:
	for task: Dictionary in state.tasks:
		if int(task.get("eligible_round", 1)) <= state.round_index:
			return str(task.get("task_id", ""))
	return ""


func _task_snapshot(state: BattleState) -> Array:
	var snapshot: Array = []
	for task: Dictionary in state.tasks:
		snapshot.append(
			{
				"definition_id": str(task.get("definition_id", "")),
				"work": int(task.get("work_remaining", 0)),
				"max": int(task.get("work_max", 0)),
			}
		)
	return snapshot


func _summarize(runs: Array[Dictionary]) -> Dictionary:
	var by_encounter := {}
	for row in runs:
		var key := "%s/%s" % [row.character, row.encounter]
		if not by_encounter.has(key):
			by_encounter[key] = {
				"character": row.character,
				"encounter": row.encounter,
				"runs": 0,
				"wins": 0,
				"errors": 0,
				"rounds": [],
				"ddl_left": [],
				"vitality": [],
			}
		var bucket: Dictionary = by_encounter[key]
		bucket.runs = int(bucket.runs) + 1
		if row.has("error"):
			bucket.errors = int(bucket.errors) + 1
			continue
		if str(row.get("result", "")) == "won":
			bucket.wins = int(bucket.wins) + 1
		bucket.rounds.append(int(row.get("rounds", 0)))
		bucket.ddl_left.append(int(row.get("ddl_left", 0)))
		bucket.vitality.append(int(row.get("vitality", 0)))
	var summary: Array = []
	for key in by_encounter:
		var bucket: Dictionary = by_encounter[key]
		summary.append(
			{
				"character": bucket.character,
				"encounter": bucket.encounter,
				"runs": bucket.runs,
				"wins": bucket.wins,
				"errors": bucket.errors,
				"win_rate": (
					float(bucket.wins) / float(maxi(1, bucket.runs - int(bucket.errors)))
				),
				"avg_rounds": _average(bucket.rounds),
				"avg_ddl_left": _average(bucket.ddl_left),
				"avg_vitality": _average(bucket.vitality),
			}
		)
	summary.sort_custom(
		func(a, b): return str(a.character) + str(a.encounter) < str(b.character) + str(b.encounter)
	)
	var errors: Array = []
	for row in runs:
		if row.has("error"):
			errors.append(row)
	return {"elites": ELITES, "characters": CHARACTERS, "seeds": SEEDS.size(), "summary": summary, "errors": errors}


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += int(value)
	return float(total) / float(values.size())
