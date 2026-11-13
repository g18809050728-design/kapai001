extends SceneTree

const OUT := "res://artifacts/verification/ui-remake-20261113"
var failures: Array[String] = []
var records: Array = []
var accepted := 0
var resource_count := 0
var reasons := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ContentDB.new("res://data/four_year")
	_check(catalog.load("campus_four_year").ok, "production catalog loads")
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(OUT.path_join("battle_engine_before.txt")).replace("class_name BattleEngine", "")
	_check(reference.reload() == OK, "recorded original engine compiles")
	if not reference.can_instantiate():
		quit(1)
		return
	var previous = reference.new(catalog)
	var current := BattleEngine.new(catalog)
	for id in catalog.get_candidates({"kind": "card"}):
		var card: Dictionary = catalog.get_definition("card", id).data
		for level in [0, 1]:
			var encounters: Array = ["normal"]
			if card.has("exam"):
				encounters.append(str(card.exam.condition))
			for encounter in encounters:
				_case(previous, current, id, card, level, encounter)
	var report := {"scope": "controlled production card/upgrade/exam commands against the recorded original engine; exact rule state and RNG, intended presentation event differences excluded", "cases": records.size(), "accepted_plays": accepted, "resource_events": resource_count, "resource_reasons": reasons, "failures": failures, "records": records}
	var file := FileAccess.open(OUT.path_join("battle-parity.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BATTLE_PRESENTATION_PARITY=", JSON.stringify({"cases": records.size(), "accepted_plays": accepted, "resource_events": resource_count, "resource_reasons": reasons, "failures": failures}))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _case(previous: Variant, current: BattleEngine, id: String, card: Dictionary, level: int, encounter: String) -> void:
	var key := "%s/%d/%s" % [id, level, encounter]
	var deck: Array = []
	for index in 10:
		deck.append({"card_id": "card_%02d" % index, "definition_id": id, "upgrade_level": level})
	var input := {"battle_id": key, "encounter_id": "N01", "character_id": str(card.get("owner", "P01")) if str(card.get("owner", "C")) != "C" else "P01", "difficulty": "normal", "vitality": 72, "max_vitality": 72, "cards": deck, "relics": [], "rng_state": RandomSource.new("presentation-parity").export_state().to_dictionary()}
	if not input.character_id.begins_with("P"):
		input.character_id = "P02"
	input.battle_id = key.replace("/", "_")
	var initial: GameResult = current.begin(input)
	var original: GameResult = previous.begin(input)
	_check(initial.ok and original.ok, key + " begins")
	if not initial.ok or not original.ok:
		if failures.size() < 3:
			print("PARITY_BEGIN_ERROR=", JSON.stringify(initial.error.to_dictionary() if not initial.ok else original.error.to_dictionary()))
		return
	_compare(original, initial, key + "/begin")
	var state: BattleState = initial.data.state.copy()
	# These are isolated rule fixtures. No session or player save is edited.
	state.player.focus = 10
	state.player.vitality = 50
	if encounter != "normal":
		state.exam_flags.assign([encounter])
	state.v3.synergy = 4
	if state.v3.has("paper"):
		state.v3.paper.open = true
		state.v3.paper.progress = 8
		state.v3.paper.citations = 2
		state.v3.paper.modifier = 2
		state.v3.paper.amplify = 2
	var card_id := str(state.zones.hand[0])
	var face: Dictionary = current.resolve_face(state, card_id).data
	var targets: Array = []
	if face.get("target", "self") == "task":
		targets.append(str(state.tasks[0].task_id))
	var action := ActionDraft.new(&"play_card", {"card_instance_id": card_id, "target_ids": targets, "replace_unit_id": null})
	var rng: Dictionary = initial.data.rng_state
	var before := state.to_dictionary()
	var old_step: GameResult = previous.apply(state, action, rng)
	var new_step := current.apply(state, action, rng)
	var did_play := new_step.ok
	_check(state.to_dictionary() == before, key + " apply preserves input")
	_compare(old_step, new_step, key + "/play")
	var trace: Array = []
	if new_step.ok:
		accepted += 1
		_resources(new_step, trace, key)
	for index in 8:
		if not new_step.ok or new_step.data.pending_choice == null:
			break
		var choice: Dictionary = new_step.data.pending_choice
		var ids: Array = []
		for selected in mini(int(choice.get("min_count", 0)), choice.get("candidates", []).size()):
			ids.append(str(choice.candidates[selected].get("id", "")))
		var confirm := ActionDraft.new(&"confirm_choice", {"choice_id": str(choice.choice_id), "selected_ids": ids})
		old_step = previous.apply(old_step.data.state, confirm, old_step.data.rng_state)
		new_step = current.apply(new_step.data.state, confirm, new_step.data.rng_state)
		_compare(old_step, new_step, key + "/choice%d" % index)
		_resources(new_step, trace, key)
	if new_step.ok and new_step.data.state.phase == "player_action":
		var end := ActionDraft.new(&"end_turn", {"retained_card_ids": []})
		old_step = previous.apply(old_step.data.state, end, old_step.data.rng_state)
		new_step = current.apply(new_step.data.state, end, new_step.data.rng_state)
		_compare(old_step, new_step, key + "/end_turn")
		_resources(new_step, trace, key)
	records.append({"case": key, "play_accepted": did_play, "resource_trace": trace})


func _compare(old: GameResult, latest: GameResult, key: String) -> void:
	_check(old.ok == latest.ok, key + " acceptance parity")
	if old.ok and latest.ok:
		_check(old.data.state.to_dictionary() == latest.data.state.to_dictionary(), key + " exact state parity")
		_check(old.data.rng_state == latest.data.rng_state, key + " exact RNG parity")
		_check(old.data.pending_choice == latest.data.pending_choice, key + " choice parity")
		_check(_non_resource_events(old.data.events) == _non_resource_events(latest.data.events), key + " other events retain order and values")
	elif not old.ok and not latest.ok:
		_check(old.error.to_dictionary() == latest.error.to_dictionary(), key + " rejection parity")


func _non_resource_events(events: Array) -> Array:
	var result: Array = []
	for event: RuleEvent in events:
		if str(event.type) in ["relax_changed", "focus_changed", "synergy_changed", "paper_changed"]:
			continue
		var data := {"type": str(event.type), "source": event.source_id, "targets": event.target_ids, "data": event.data}
		if str(event.type) == "pressure_applied":
			data.erase("source") # The new source is intentionally more precise.
		result.append(data)
	return result


func _resources(step: GameResult, trace: Array, key: String) -> void:
	if not step.ok:
		return
	for event: RuleEvent in step.data.events:
		if not event.data.has("resource"):
			continue
		var data: Dictionary = event.data
		_check(int(data.delta) == int(data.after) - int(data.before) and int(data.delta) != 0, key + " true resource delta")
		_check(not event.target_ids.is_empty() and not str(event.target_ids[0]).is_empty(), key + " real resource target")
		if data.reason == "ability":
			_check(step.data.state.v3.get("abilities", []).any(func(ability): return ability.get("ability_id", "") == event.source_id), key + " resources name the actual ability")
		if data.reason == "pressure_absorbed":
			_check(step.data.state.source_registry.get(event.source_id, {}).get("kind", "") == "task", key + " absorbed pressure names its task")
		resource_count += 1
		reasons[data.reason] = int(reasons.get(data.reason, 0)) + 1
		trace.append({"index": event.index, "type": str(event.type), "source": event.source_id, "targets": event.target_ids, "data": data})


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
