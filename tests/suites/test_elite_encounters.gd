extends RefCounted

const ELITE_EXPECTATIONS := {
	"E01": {"ddl": 9, "tasks": ["E01"], "exam_flags": ["independent_answer"]},
	"E02": {"ddl": 8, "tasks": ["E02"], "exam_flags": ["independent_answer"]},
	"E03": {"ddl": 9, "tasks": ["E03"], "exam_flags": []},
	"E04": {"ddl": 7, "tasks": ["E04_1", "E04_2", "E04_3"], "exam_flags": ["independent_answer"]},
	"E05":
	{
		"ddl": 10,
		"tasks": ["E05"],
		"exam_flags": ["independent_answer", "fixed_exam_room"]
	},
	"E06": {"ddl": 8, "tasks": ["E06"], "exam_flags": ["independent_answer"]},
	"E07": {"ddl": 6, "tasks": ["E07"], "exam_flags": ["independent_answer"]},
	"Q0A": {"ddl": 8, "tasks": ["Q0A_1", "Q0A_2", "Q0A_3"], "exam_flags": []},
	"Q0B": {"ddl": 8, "tasks": ["Q0B_2"], "exam_flags": []},
	"Q0C": {"ddl": 10, "tasks": ["Q0C"], "exam_flags": ["independent_answer"]},
	"Q0D": {"ddl": 8, "tasks": ["Q0D"], "exam_flags": ["independent_answer"]},
	"Q0E": {"ddl": 10, "tasks": ["Q0E_1"], "exam_flags": []}
}

const PRODUCTION_MANIFEST := "campus_mvp"
const TEST_VITALITY := 200


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new()
	_check(catalog.load(PRODUCTION_MANIFEST).ok, "production content loads", failures)
	if catalog.get_info() == null:
		return failures
	var engine := BattleEngine.new(catalog)
	var rng_state := RandomSource.new("elite-suite-seed").export_state().to_dictionary()
	_check_opening(engine, rng_state, failures)
	_check_content_contract(catalog, failures)
	_check_pool_membership(catalog, failures)
	_check_attention_elite(engine, rng_state, failures)
	_check_deadline_pressure(engine, rng_state, failures)
	_check_unit_scaling(engine, rng_state, failures)
	_check_transformation(engine, rng_state, failures)
	_check_summons(engine, rng_state, failures)
	_check_cooperation_absorb(engine, catalog, rng_state, failures)
	_check_burden_injection(engine, rng_state, failures)
	_check_shield_window(engine, rng_state, failures)
	_check_six_level_elite(engine, rng_state, failures)
	_check_codec_roundtrip(engine, catalog, rng_state, failures)
	_check_soak(engine, rng_state, failures)
	if failures.is_empty():
		print("ELITE_ENCOUNTERS_SUITE=passed")
	return failures


func _check_opening(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var deck := _deck("K01", 10)
	for encounter_id in ELITE_EXPECTATIONS:
		var expected: Dictionary = ELITE_EXPECTATIONS[encounter_id]
		var begun := _begin(engine, encounter_id, deck, rng_state)
		_check(begun.ok, encounter_id + " starts", failures)
		if not begun.ok:
			print("ELITE_BEGIN_ERROR=", JSON.stringify(begun.error.to_dictionary()))
			continue
		var state: BattleState = begun.data.state
		_check(state.phase == "player_action", encounter_id + " reaches player action", failures)
		_check(
			state.ddl == int(expected.ddl),
			"%s opens on DDL %s" % [encounter_id, expected.ddl],
			failures
		)
		_check(
			_task_definitions(state) == expected.tasks,
			"%s opens with %s" % [encounter_id, expected.tasks],
			failures
		)
		_check(
			state.exam_flags == expected.exam_flags,
			encounter_id + " carries the draft exam flags",
			failures
		)
		_check(
			state.tasks.all(func(task): return int(task.work_remaining) > 0),
			encounter_id + " opens with positive task work",
			failures
		)


func _check_content_contract(catalog: ContentDB, failures: Array[String]) -> void:
	var e01 := _task(catalog, "E01")
	_check(
		e01.phases.size() == 3
		and e01.phases[0].work_max == 16
		and e01.phases[1].work_max == 22
		and e01.phases[2].work_max == 28,
		"E01 keeps the 16/22/28 phase totals",
		failures
	)
	if e01.phases.size() == 3:
		var anxiety: Dictionary = e01.phases[0].intents[1]
		_check(
			int(anxiety.get("shield", 0)) == 6
			and str(anxiety.get("gain_status", {}).get("status", "")) == "anxiety",
			"E01 phase 1 B shields and applies anxiety",
			failures
		)
		var essay: Dictionary = e01.phases[2].intents[1]
		_check(
			int(essay.get("shield", 0)) == 6 and int(essay.get("pressure", 0)) == 4,
			"E01 phase 3 B combines shield and pressure",
			failures
		)
	var e02 := _task(catalog, "E02")
	if e02.phases.size() == 2:
		var interrogation: Dictionary = e02.phases[1].intents[1]
		_check(
			str(interrogation.get("add_card", {}).get("card", "")) == "X01"
			and str(interrogation.get("add_card", {}).get("zone", "")) == "discard",
			"E02 interrogation B injects X01 into the discard pile",
			failures
		)
	var e03 := _task(catalog, "E03")
	if e03.phases.size() == 2:
		var scaled := 0
		for phase: Dictionary in e03.phases:
			for intent: Dictionary in phase.intents:
				if int(intent.get("pressure", 0)) > 0:
					if (
						int(intent.get("pressure_per_unit", 0)) == 1
						and int(intent.get("pressure_per_unit_cap", 0)) == 3
					):
						scaled += 1
		_check(scaled == 4, "E03 scales every pressure segment by surviving units", failures)
	var e05 := _task(catalog, "E05")
	if e05.phases.size() == 3:
		var interview: Dictionary = e05.phases[2].intents[1]
		_check(
			int(interview.get("pressure", 0)) == 7
			and int(interview.get("pressure_times", 1)) == 2,
			"E05 interview B is a two-segment pressure",
			failures
		)
	var e06 := _task(catalog, "E06")
	if e06.phases.size() == 2:
		var intro: Dictionary = e06.phases[0].intents[0]
		_check(
			str(intro.get("add_card", {}).get("card", "")) == "X02"
			and str(intro.get("add_card", {}).get("zone", "")) == "hand",
			"E06 puts an interview question into the hand",
			failures
		)
	var e04 := _encounter(catalog, "E04")
	_check(e04.members.size() == 3, "E04 starts three parallel tasks", failures)
	_check(
		not e04.has("initial_members"), "E04 places every member at battle start", failures
	)
	var q0c := _task(catalog, "Q0C")
	var q0d := _task(catalog, "Q0D")
	_check(
		_first_phase(q0c).get("intent_loop", "") == "clamp"
		and _first_phase(q0d).get("intent_loop", "") == "clamp",
		"Q0C/Q0D repeat the buff intent after the opening burst",
		failures
	)
	var q0a_3_1 := _task(catalog, "Q0A_3_1")
	_check(
		not bool(q0a_3_1.get("victory_required", true)),
		"Q0A_3_1 is an optional summoned task",
		failures
	)
	var q0e_1 := _task(catalog, "Q0E_1")
	var opening: Dictionary = _first_phase(q0e_1).intents[0]
	_check(
		opening.get("summon_tasks", []).size() == 2,
		"Q0E_1 summons two extra requirements",
		failures
	)
	_check(
		not bool(_task(catalog, "Q0E_2").get("victory_required", true))
		and not bool(_task(catalog, "Q0E_3").get("victory_required", true)),
		"Q0E extra requirements are optional for victory",
		failures
	)
	var q0b_2 := _task(catalog, "Q0B_2")
	var q0b_intents: Array = _first_phase(q0b_2).get("intents", [])
	if q0b_intents.size() >= 3:
		var transform: Dictionary = q0b_intents[2]
		_check(
			str(transform.get("transform_task", {}).get("task", "")) == "Q0B_1"
			and int(transform.get("ddl_bonus", 0)) == 1,
			"Q0B_2 converts into the defense form and extends the deadline",
			failures
		)
	else:
		_check(false, "Q0B_2 keeps three intents", failures)
	var confusion := catalog.get_definition("status", "confusion")
	var brainstorm := catalog.get_definition("status", "brainstorm")
	_check(
		confusion.ok and confusion.data.target == "task",
		"confusion is a task buff",
		failures
	)
	_check(
		brainstorm.ok and brainstorm.data.numeric_rule_key == "brainstorm",
		"brainstorm is a numeric task buff",
		failures
	)
	var burden := catalog.get_definition("card", "X02")
	_check(
		burden.ok and bool(burden.data.get("unplayable", false)),
		"X02 is an unplayable temporary burden",
		failures
	)


func _check_pool_membership(catalog: ContentDB, failures: Array[String]) -> void:
	var required := {
		1: ["Q01", "E01", "E02", "E03", "Q0B", "Q0C"],
		2: ["E01", "E02", "E03", "E04", "E06", "Q0A", "Q0B", "Q0C", "Q0D", "Q0E"],
		6: ["E07", "Q0C", "Q0D"]
	}
	for term in required:
		var pool := catalog.get_candidates({"kind": "encounter", "terms": term})
		for encounter_id: String in required[term]:
			_check(
				pool.has(encounter_id),
				"%s is selectable as an elite in term %s" % [encounter_id, term],
				failures
			)
			var definition := catalog.get_definition("encounter", encounter_id)
			_check(
				definition.ok and str(definition.data.kind) == "elite",
				encounter_id + " is an elite encounter",
				failures
			)
	var reachable := {}
	for term in range(1, 9):
		for encounter_id in catalog.get_candidates({"kind": "encounter", "terms": term}):
			reachable[encounter_id] = true
	for encounter_id in ELITE_EXPECTATIONS:
		_check(
			reachable.has(encounter_id),
			encounter_id + " is reachable in at least one term",
			failures
		)


func _check_attention_elite(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "E01", _deck("K01", 10), rng_state)
	_check(begun.ok, "E01 starts for the attention check", failures)
	if not begun.ok:
		return
	var first := _end_turn(engine, begun)
	_check(first.ok, "E01 first round ends", failures)
	if not first.ok:
		return
	var state: BattleState = first.data.state
	_check(state.player.vitality == TEST_VITALITY - 5, "E01 phase 1 A pressures for 5", failures)
	_check(state.round_index == 2, "E01 advances to round 2", failures)
	_check(
		int(state.tasks[0].intent_snapshot.get("shield", 0)) == 6
		and str(state.tasks[0].intent_snapshot.get("gain_status", {}).get("status", "")) == "anxiety",
		"E01 announces the anxiety turn before it resolves",
		failures
	)
	var second := _end_turn(engine, first)
	_check(second.ok, "E01 second round ends", failures)
	if not second.ok:
		return
	state = second.data.state
	_check(
		state.player.vitality == TEST_VITALITY - 5 and state.player.focus == 2,
		"E01 anxiety costs one focus on the following preparation",
		failures
	)
	_check(
		not _has_status(state, "anxiety"),
		"E01 anxiety expires after the punished preparation",
		failures
	)


func _check_deadline_pressure(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "Q0C", _deck("K01", 10), rng_state)
	_check(begun.ok, "Q0C starts for the deadline check", failures)
	if not begun.ok:
		return
	var step := begun
	var allowed := true
	for index in 3:
		step = _end_turn(engine, step)
		allowed = allowed and step.ok
		if not step.ok:
			break
	_check(allowed, "Q0C survives three quarters", failures)
	if not allowed:
		return
	var state: BattleState = step.data.state
	_check(
		state.player.vitality == TEST_VITALITY - 9 - 5 - 6,
		"Q0C stacks brainstorm onto the repeated pressure intent",
		failures
	)
	_check(
		_has_status(state, "brainstorm") and _status_stacks(state, "brainstorm") == 2,
		"Q0C accumulates two brainstorm stacks",
		failures
	)
	_check(state.ddl == 7, "Q0C spends one deadline per round", failures)


func _check_unit_scaling(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var deck := _deck("K43", 6)
	var begun := _begin(engine, "E03", deck, rng_state)
	_check(begun.ok, "E03 starts for the unit-scaling check", failures)
	if not begun.ok:
		return
	var state: BattleState = begun.data.state
	var cooperation_card := ""
	for card_id in state.zones.hand:
		if str(state.card_by_id[card_id].definition_id) == "K43":
			cooperation_card = str(card_id)
			break
	_check(not cooperation_card.is_empty(), "E03 draws a cooperation card", failures)
	if cooperation_card.is_empty():
		return
	var played := engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": cooperation_card, "target_ids": []}
		),
		begun.data.rng_state
	)
	_check(played.ok, "E03 accepts the cooperation card", failures)
	if not played.ok:
		return
	var with_unit: BattleState = played.data.state
	_check(with_unit.units.size() == 1, "E03 summons one allied unit", failures)
	var ended := _end_turn(engine, played)
	_check(ended.ok, "E03 first round ends with a unit", failures)
	if not ended.ok:
		return
	var after: BattleState = ended.data.state
	_check(
		after.units.size() == 1 and int(after.units[0].vitality) == 4,
		"E03 guard unit absorbed five pressure instead of the player",
		failures
	)
	_check(
		after.player.vitality == TEST_VITALITY,
		"E03 pressure never reaches the player while a guard is alive",
		failures
	)
	var cooperation_segments: Array = []
	for event: RuleEvent in ended.data.events:
		if event.type == &"completion_applied":
			cooperation_segments.append(event.data)
	_check(
		cooperation_segments.size() == 1,
		"E03 unit applies one cooperation segment",
		failures
	)
	if cooperation_segments.size() == 1:
		_check(
			int(cooperation_segments[0].get("shield_before", -1)) == 6
			and int(cooperation_segments[0].get("shield_after", -1)) == 4,
			"E03 cooperation strips two shield points from the task",
			failures
		)
	var control := _begin(engine, "E03", _deck("K01", 10), rng_state)
	_check(control.ok, "E03 control battle starts", failures)
	if not control.ok:
		return
	var control_end := _end_turn(engine, control)
	_check(control_end.ok, "E03 control round ends", failures)
	if not control_end.ok:
		return
	_check(
		control_end.data.state.player.vitality == TEST_VITALITY - 4,
		"E03 base pressure without units is 4",
		failures
	)


func _check_transformation(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "Q0B", _deck("K01", 10), rng_state)
	_check(begun.ok, "Q0B starts for the transformation check", failures)
	if not begun.ok:
		return
	var step := begun
	for index in 3:
		step = _end_turn(engine, step)
		if not step.ok:
			_check(false, "Q0B round %s ends" % (index + 1), failures)
			return
	var state: BattleState = step.data.state
	_check(
		state.tasks.size() == 1 and str(state.tasks[0].definition_id) == "Q0B_1",
		"Q0B converts the paper into the defense form",
		failures
	)
	if state.tasks.size() != 1:
		return
	_check(int(state.tasks[0].work_max) == 15, "Q0B defense form starts a 15 work bar", failures)
	_check(
		int(state.tasks[0].intent_snapshot.get("shield", 0)) == 5
		and int(state.tasks[0].intent_snapshot.get("work_restore", 0)) == 5,
		"Q0B defense form opens on the shield/restore intent",
		failures
	)
	_check(state.ddl == 6, "Q0B conversion grants one extra deadline", failures)
	_check(
		state.player.vitality == TEST_VITALITY - 6 - 2,
		"Q0B pressure before conversion matches the draft",
		failures
	)


func _check_summons(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "Q0E", _deck("K01", 10), rng_state)
	_check(begun.ok, "Q0E starts for the summon check", failures)
	if not begun.ok:
		return
	var first := _end_turn(engine, begun)
	_check(first.ok, "Q0E first round ends", failures)
	if not first.ok:
		return
	var state: BattleState = first.data.state
	_check(
		state.tasks.size() == 3 and _task_definitions(state) == ["Q0E_1", "Q0E_2", "Q0E_3"],
		"Q0E summons both extra requirements",
		failures
	)
	_check(
		state.player.vitality == TEST_VITALITY - 4,
		"Q0E big project only pressures for 4 before the extras act",
		failures
	)
	for task: Dictionary in state.tasks:
		if str(task.definition_id) == "Q0E_2":
			_check(
				int(task.work_remaining) == 15
				and int(task.intent_snapshot.get("shield", 0)) == 8,
				"Q0E extra requirement 1 opens on its shield intent",
				failures
			)
	var step := first
	for index in 4:
		step = _end_turn(engine, step)
		if not step.ok:
			_check(false, "Q0E follow-up round %s ends" % (index + 2), failures)
			return
	_check(
		_task_definitions(step.data.state).size() == 3,
		"Q0E never repeats the one-shot summon",
		failures
	)
	var q0a := _begin(engine, "Q0A", _deck("K01", 10), rng_state)
	_check(q0a.ok, "Q0A starts for the summon check", failures)
	if not q0a.ok:
		return
	var q0a_step := q0a
	var summoned := 0
	for index in 6:
		q0a_step = _end_turn(engine, q0a_step)
		if not q0a_step.ok:
			_check(false, "Q0A round %s ends" % (index + 1), failures)
			return
		for event: RuleEvent in q0a_step.data.events:
			if (
				event.type == &"task_summoned"
				and str(event.data.get("definition_id", "")) == "Q0A_3_1"
			):
				summoned += 1
	_check(summoned == 1, "Q0A summons the test run exactly once", failures)
	_check(
		not _task_definitions(q0a_step.data.state).has("Q0A_3_1"),
		"Q0A test run self-destructs after its attack",
		failures
	)


func _check_cooperation_absorb(
	engine: BattleEngine, catalog: ContentDB, rng_state: Dictionary, failures: Array[String]
) -> void:
	var deck := _deck("K43", 2)
	deck.append_array(_deck("K01", 4))
	var begun := _begin(engine, "Q0A", deck, rng_state)
	_check(begun.ok, "Q0A starts for the absorb check", failures)
	if not begun.ok:
		return
	var state: BattleState = begun.data.state
	_check(
		state.zones.exhaust.size() == 2,
		"Q0A absorbs every cooperation card into the exhaust pile",
		failures
	)
	for card_id in state.zones.exhaust:
		var card: Dictionary = state.card_by_id.get(card_id, {})
		var definition := catalog.get_definition("card", str(card.get("definition_id", "")))
		_check(
			definition.ok and str(definition.data.get("type", "")) == "cooperation",
			"absorbed card is a cooperation card",
			failures
		)
	_check(
		state.player.focus == 5,
		"Q0A converts each absorbed cooperation card into one focus",
		failures
	)
	var control := _begin(engine, "E01", deck, rng_state)
	_check(control.ok, "E01 control battle starts with cooperation cards", failures)
	if control.ok:
		_check(
			control.data.state.zones.exhaust.is_empty(),
			"only Q0A absorbs cooperation cards",
			failures
		)


func _check_burden_injection(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "E06", _deck("K01", 10), rng_state)
	_check(begun.ok, "E06 starts for the burden check", failures)
	if not begun.ok:
		return
	var ended := _end_turn(engine, begun)
	_check(ended.ok, "E06 first round ends", failures)
	if not ended.ok:
		return
	var state: BattleState = ended.data.state
	var questions := 0
	for card_id in state.zones.hand:
		if str(state.card_by_id[card_id].definition_id) == "X02":
			questions += 1
	_check(questions == 1, "E06 adds one interview question to the hand", failures)
	_check(
		state.player.vitality == TEST_VITALITY - 6,
		"E06 opening intent pressures for 6",
		failures
	)


func _check_shield_window(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "E02", _deck("K01", 10), rng_state)
	_check(begun.ok, "E02 starts for the shield-window check", failures)
	if not begun.ok:
		return
	var first := _end_turn(engine, begun)
	_check(first.ok, "E02 shield round ends", failures)
	if not first.ok:
		return
	_check(
		first.data.state.player.vitality == TEST_VITALITY,
		"E02 opening round only shields, so the player is untouched",
		failures
	)
	_check(
		int(first.data.state.tasks[0].shield) == 0
		and int(first.data.state.tasks[0].intent_snapshot.get("pressure", 0)) == 5,
		"E02 announces the empty pressure round after the shield",
		failures
	)
	var second := _end_turn(engine, first)
	_check(second.ok, "E02 pressure round ends", failures)
	if not second.ok:
		return
	_check(
		second.data.state.player.vitality == TEST_VITALITY - 5,
		"E02 pressure round hits for 5",
		failures
	)


func _check_six_level_elite(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "Q0D", _deck("K01", 10), rng_state)
	_check(begun.ok, "Q0D starts for the six-level check", failures)
	if not begun.ok:
		return
	var step := begun
	for index in 3:
		step = _end_turn(engine, step)
		if not step.ok:
			_check(false, "Q0D round %s ends" % (index + 1), failures)
			return
	var state: BattleState = step.data.state
	_check(
		state.player.vitality == TEST_VITALITY - 13 - 8 - 9,
		"Q0D stacks two brainstorm per buff round and caps at three stacks",
		failures
	)
	_check(
		_status_stacks(state, "brainstorm") == 3,
		"Q0D brainstorm is capped at three stacks",
		failures
	)
	_check(state.ddl == 5, "Q0D burns one deadline per round", failures)


func _check_codec_roundtrip(
	engine: BattleEngine, catalog: ContentDB, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "Q0E", _deck("K01", 10), rng_state)
	_check(begun.ok, "Q0E starts for the codec check", failures)
	if not begun.ok:
		return
	var summoned := _end_turn(engine, begun)
	_check(summoned.ok, "Q0E summon round ends", failures)
	if not summoned.ok:
		return
	var encoded := BattleCodec.encode(summoned.data.state)
	_check(encoded.ok, "summoned battle encodes at a stable boundary", failures)
	if encoded.ok:
		var decoded := BattleCodec.decode(encoded.data, catalog)
		_check(decoded.ok, "summoned battle decodes", failures)
		if decoded.ok:
			_check(
				_task_definitions(decoded.data) == ["Q0E_1", "Q0E_2", "Q0E_3"],
				"codec roundtrip keeps every summoned task",
				failures
			)
			var resumed := GameResult.success(
				BattleStep.new(decoded.data, [], null, null, true, summoned.data.rng_state)
			)
			var resumed_next := _end_turn(engine, resumed)
			var control_next := _end_turn(engine, summoned)
			_check(
				resumed_next.ok and control_next.ok,
				"resumed summoned battle keeps playing",
				failures
			)
			if resumed_next.ok and control_next.ok:
				_check(
					(
						SnapshotCodec.canonical_json(resumed_next.data.state.to_dictionary())
						== SnapshotCodec.canonical_json(
							control_next.data.state.to_dictionary()
						)
					),
					"resumed summoned battle matches the uninterrupted control",
					failures
				)
	var transformed := _begin(engine, "Q0B", _deck("K01", 10), rng_state)
	_check(transformed.ok, "Q0B starts for the codec check", failures)
	if not transformed.ok:
		return
	var step := transformed
	for index in 3:
		step = _end_turn(engine, step)
		if not step.ok:
			_check(false, "Q0B codec round %s ends" % (index + 1), failures)
			return
	var encoded_transform := BattleCodec.encode(step.data.state)
	_check(encoded_transform.ok, "transformed battle encodes", failures)
	if encoded_transform.ok:
		var decoded_transform := BattleCodec.decode(encoded_transform.data, catalog)
		_check(decoded_transform.ok, "transformed battle decodes", failures)
		if decoded_transform.ok:
			_check(
				_task_definitions(decoded_transform.data) == ["Q0B_1"],
				"codec roundtrip keeps the converted defense form",
				failures
			)
			_check(
				int(decoded_transform.data.tasks[0].work_max) == 15,
				"codec roundtrip keeps the converted work bar",
				failures
			)


func _check_soak(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	for encounter_id in ELITE_EXPECTATIONS:
		var begun := _begin(engine, encounter_id, _deck("K01", 10), rng_state)
		if not begun.ok:
			_check(false, encounter_id + " starts the soak", failures)
			continue
		var step := begun
		var rounds := 0
		while step.ok and step.data.state.phase != "finished" and rounds < 14:
			step = _end_turn(engine, step)
			rounds += 1
			if not step.ok or step.data.state.phase == "finished":
				break
			var encoded := BattleCodec.encode(step.data.state)
			if not encoded.ok:
				_check(
					false,
					"%s stays saveable after round %s" % [encounter_id, rounds],
					failures
				)
				break
		_check(step.ok, encounter_id + " soak turns never fail", failures)
		if not step.ok:
			continue
		var state: BattleState = step.data.state
		_check(
			state.phase == "finished" and state.outcome != null,
			encounter_id + " soak reaches a terminal state",
			failures
		)
		if state.outcome == null:
			continue
		_check(
			str(state.outcome.result) == "lost"
			and str(state.outcome.reason) == "deadline_expired"
			and state.ddl == 0,
			encounter_id + " ends on deadline expiry without player damage",
			failures
		)
		_check(
			not state.tasks.is_empty(),
			encounter_id + " still holds its task when the deadline expires",
			failures
		)


func _begin(
	engine: BattleEngine, encounter_id: String, cards: Array[Dictionary], rng_state: Dictionary
) -> GameResult:
	return (
		engine
		. begin(
			{
				"battle_id": "elite_test_%s" % encounter_id,
				"node_id": "elite_test_node",
				"encounter_id": encounter_id,
				"character_id": "P01",
				"difficulty": "normal",
				"vitality": TEST_VITALITY,
				"max_vitality": TEST_VITALITY,
				"cards": cards,
				"relics": [],
				"rng_state": rng_state.duplicate(true),
			}
		)
	)


func _end_turn(engine: BattleEngine, step: GameResult) -> GameResult:
	return (
		engine
		. apply(
			step.data.state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {}),
			step.data.rng_state
		)
	)


func _deck(definition_id: String, count: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for index in count:
		(
			cards
			. append(
				{
					"card_id": "origin_%s_%02d" % [definition_id, index + 1],
					"definition_id": definition_id,
					"upgrade_level": 0,
				}
			)
		)
	return cards


func _task_definitions(state: BattleState) -> Array[String]:
	var definitions: Array[String] = []
	for task: Dictionary in state.tasks:
		definitions.append(str(task.definition_id))
	return definitions


func _has_status(state: BattleState, status_id: String) -> bool:
	for status: Dictionary in state.statuses:
		if str(status.status_id) == status_id:
			return true
	return false


func _status_stacks(state: BattleState, status_id: String) -> int:
	var player_id := str(state.player.get("entity_id", ""))
	for status: Dictionary in state.statuses:
		if str(status.status_id) == status_id and str(status.target_id) == player_id:
			return int(status.get("stacks", 0))
	for status: Dictionary in state.statuses:
		if str(status.status_id) == status_id:
			return int(status.get("stacks", 0))
	return 0


func _task(catalog: ContentDB, task_id: String) -> Dictionary:
	var result := catalog.get_definition("task", task_id)
	return result.data if result.ok else {}


func _encounter(catalog: ContentDB, encounter_id: String) -> Dictionary:
	var result := catalog.get_definition("encounter", encounter_id)
	return result.data if result.ok else {}


func _first_phase(task_definition: Dictionary) -> Dictionary:
	var phases: Array = task_definition.get("phases", [])
	return phases[0] if not phases.is_empty() else {}


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("elite encounters: " + label)
