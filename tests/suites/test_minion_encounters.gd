extends RefCounted

const MINION_EXPECTATIONS := {
	"N13": {"ddl": 8, "tasks": ["N13"]},
	"N14": {"ddl": 8, "tasks": ["N14"]},
	"N15": {"ddl": 8, "tasks": ["N15"]},
	"N16": {"ddl": 8, "tasks": ["N16"]},
	"N17": {"ddl": 8, "tasks": ["N17"]},
	"N18": {"ddl": 8, "tasks": ["N18"]},
	"N19": {"ddl": 9, "tasks": ["N19"]},
	"N20": {"ddl": 8, "tasks": ["N20"]},
	"N21": {"ddl": 8, "tasks": ["N21"]},
	"N22": {"ddl": 8, "tasks": ["N22"]},
	"N23": {"ddl": 8, "tasks": ["N23"]},
	"N24": {"ddl": 7, "tasks": ["N24"]},
	"N25": {"ddl": 8, "tasks": ["N25"]},
	"N26": {"ddl": 8, "tasks": ["N26"]},
	"N27": {"ddl": 9, "tasks": ["N27"]},
	"N28": {"ddl": 8, "tasks": ["N28"]},
	"N29": {"ddl": 8, "tasks": ["N29"]},
	"N30": {"ddl": 9, "tasks": ["N30"]},
	"N31": {"ddl": 9, "tasks": ["N31"]},
	"N32": {"ddl": 9, "tasks": ["N32"]},
	"N33": {"ddl": 10, "tasks": ["N33"]},
	"N34": {"ddl": 8, "tasks": ["N34"]},
	"N35": {"ddl": 9, "tasks": ["N35"]},
	"N36": {"ddl": 8, "tasks": ["N36"]},
	"N37": {"ddl": 9, "tasks": ["N37"]},
	"N38": {"ddl": 9, "tasks": ["N38"]},
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
	var rng_state := RandomSource.new("minion-suite-seed").export_state().to_dictionary()
	_check_opening(engine, rng_state, failures)
	_check_content_contract(catalog, failures)
	_check_on_complete(engine, catalog, rng_state, failures)
	_check_first_card_discard(engine, rng_state, failures)
	_check_soak(engine, rng_state, failures)
	_check_codec_roundtrip(engine, catalog, rng_state, failures)
	if failures.is_empty():
		print("MINION_ENCOUNTERS_SUITE=passed")
	return failures


func _check_opening(engine: BattleEngine, rng_state: Dictionary, failures: Array[String]) -> void:
	var deck := _deck("K01", 10)
	for encounter_id in MINION_EXPECTATIONS:
		var expected: Dictionary = MINION_EXPECTATIONS[encounter_id]
		var begun := _begin(engine, encounter_id, deck, rng_state)
		_check(begun.ok, encounter_id + " starts", failures)
		if not begun.ok:
			print("MINION_BEGIN_ERROR=", JSON.stringify(begun.error.to_dictionary()))
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


func _check_content_contract(catalog: ContentDB, failures: Array[String]) -> void:
	var n14 := _task(catalog, "N14")
	_check(
		_first_phase(n14).get("intents", [])[0].get("gain_status", {}).get("status", "") == "drowsiness",
		"N14 applies drowsiness in its first intent",
		failures
	)
	_check(
		not n14.get("on_complete_effects", []).is_empty(),
		"N14 declares a deathrattle",
		failures
	)
	var n23 := _task(catalog, "N23")
	_check(
		str(n23.get("on_complete_effects", [])[0].get("task", "")) == "N22",
		"N23 deathrattle summons N22",
		failures
	)
	var n22 := _task(catalog, "N22")
	_check(bool(n22.get("taunt", false)), "N22 is a taunt task", failures)
	var n20 := _task(catalog, "N20")
	_check(bool(n20.get("self_copy_every_round", false)), "N20 copies itself every round", failures)
	var n33 := _task(catalog, "N33")
	_check(bool(n33.get("shield_persistent", false)), "N33 keeps its shield", failures)
	var n26 := _task(catalog, "N26")
	_check(int(n26.get("draw_reduction", 0)) == 1, "N26 reduces the player draw", failures)
	var n34 := _task(catalog, "N34")
	_check(
		int(n34.get("discard_on_first_card", 0)) == 1,
		"N34 discards after the first card",
		failures
	)
	var n28 := _task(catalog, "N28")
	_check(int(n28.get("first_card_cost_bonus", 0)) == 1, "N28 taxes the first card", failures)
	var n21 := _task(catalog, "N21")
	_check(int(n21.get("max_vitality_reduction", 0)) == 1, "N21 shrinks max vitality", failures)
	var n31 := _task(catalog, "N31")
	_check(
		not n31.get("on_complete_effects", []).is_empty(),
		"N31 restores max vitality on completion",
		failures
	)
	var n24 := _task(catalog, "N24")
	_check(
		_first_phase(n24).get("intent_loop", "") == "clamp"
		and _first_phase(n24).get("intents", []).size() == 4,
		"N24 escalates pressure and clamps",
		failures
	)
	var n32 := _task(catalog, "N32")
	_check(
		int(_first_phase(n32).get("intents", [])[0].get("pressure_per_vitality", 0)) == 1,
		"N32 scales pressure by vitality",
		failures
	)
	var n27 := _task(catalog, "N27")
	_check(
		int(_first_phase(n27).get("intents", [])[0].get("pressure_no_unit_mult", 0)) == 200,
		"N27 doubles pressure without units",
		failures
	)
	var n38 := _task(catalog, "N38")
	_check(
		int(_first_phase(n38).get("intents", [])[0].get("pressure_per_card_type", {}).get("cooperation", 0)) == 1,
		"N38 scales pressure by cooperation cards",
		failures
	)
	var n16 := _task(catalog, "N16")
	_check(
		int(_first_phase(n16).get("intents", [])[0].get("player_gain_focus", 0)) == 2,
		"N16 grants the player focus in surprise mode",
		failures
	)
	var n37 := _task(catalog, "N37")
	var n37_final: Dictionary = _first_phase(n37).get("intents", [])[1]
	_check(
		bool(n37_final.get("self_destruct", false))
		and bool(n37_final.get("pressure_all", false)),
		"N37 explodes after its countdown",
		failures
	)
	var x03 := catalog.get_definition("card", "X03")
	_check(x03.ok and bool(x03.data.get("unplayable", false)), "X03 is an unplayable card", failures)
	for encounter_id in MINION_EXPECTATIONS:
		_check(
			UiStyle.label(encounter_id) != encounter_id,
			"%s has a display label" % encounter_id,
			failures
		)
	_check(UiStyle.label("X03") != "X03", "X03 has a display label", failures)
	_check(UiStyle.label("work_boost") != "work_boost", "work_boost has a display label", failures)
	_check(
		UiStyle.label("task.n20.intent.b") == "复制自身",
		"N20 intent labels describe the copy action",
		failures
	)


func _check_on_complete(
	engine: BattleEngine, catalog: ContentDB, rng_state: Dictionary, failures: Array[String]
) -> void:
	# N17: completing the task grants the player +2 focus.
	var begun := _begin(engine, "N17", _deck("K01", 10), rng_state)
	if not begun.ok:
		return
	var state: BattleState = begun.data.state
	var task_id := str(state.tasks[0].task_id)
	var card_id := str(state.zones.hand[0])
	var applied := engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": card_id, "target_ids": [task_id]}
		),
		begun.data.rng_state
	)
	_check(applied.ok, "N17 completion resolves", failures)


func _check_first_card_discard(
	engine: BattleEngine, rng_state: Dictionary, failures: Array[String]
) -> void:
	var begun := _begin(engine, "N34", _deck("K01", 10), rng_state)
	if not begun.ok:
		return
	var state: BattleState = begun.data.state
	var task_id := str(state.tasks[0].task_id)
	var first_card := str(state.zones.hand[0])
	var first := engine.apply(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": first_card, "target_ids": [task_id]}
		),
		begun.data.rng_state
	)
	_check(first.ok, "N34 first card resolves", failures)
	_check(_has_event(first, "card_discarded"), "N34 discards after the first card", failures)
	if not first.ok or not first.data.stable or first.data.state.zones.hand.is_empty():
		return
	var second_card := str(first.data.state.zones.hand[0])
	var second := engine.apply(
		first.data.state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": second_card, "target_ids": [task_id]}
		),
		first.data.rng_state
	)
	_check(second.ok, "N34 second card resolves", failures)
	_check(
		not _has_event(second, "card_discarded"),
		"N34 discards only after the first card",
		failures
	)


func _check_soak(engine: BattleEngine, rng_state: Dictionary, failures: Array[String]) -> void:
	var deck := _deck("K01", 10)
	for encounter_id in MINION_EXPECTATIONS:
		var begun := _begin(engine, encounter_id, deck, rng_state)
		if not begun.ok:
			continue
		var step := begun
		var rounds := 0
		while rounds < 60:
			if step.data.state.phase == "finished":
				break
			step = _end_turn(engine, step)
			rounds += 1
			if not step.ok or step.data.state.phase == "finished":
				break
		_check(step.ok, encounter_id + " soak turns never fail", failures)
		if not step.ok:
			print("MINION_SOAK_ERROR=", encounter_id, "=", JSON.stringify(step.error.to_dictionary()))
			continue
		_check(
			step.data.state.phase == "finished" and step.data.state.outcome != null,
			encounter_id + " soak reaches a terminal state",
			failures
		)


func _check_codec_roundtrip(
	engine: BattleEngine, catalog: ContentDB, rng_state: Dictionary, failures: Array[String]
) -> void:
	var deck := _deck("K01", 10)
	for encounter_id in MINION_EXPECTATIONS:
		var begun := _begin(engine, encounter_id, deck, rng_state)
		if not begun.ok:
			continue
		var encoded := BattleCodec.encode(begun.data.state)
		if not encoded.ok:
			_check(false, encounter_id + " encodes at open", failures)
			continue
		var decoded := BattleCodec.decode(encoded.data, catalog)
		_check(decoded.ok, encounter_id + " decodes at open", failures)


func _begin(
	engine: BattleEngine, encounter_id: String, cards: Array[Dictionary], rng_state: Dictionary
) -> GameResult:
	return (
		engine
		. begin(
			{
				"battle_id": "minion_test_%s" % encounter_id,
				"node_id": "minion_test_node",
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
		cards.append(
			{
				"card_id": "origin_%s_%02d" % [definition_id, index + 1],
				"definition_id": definition_id,
				"upgrade_level": 0,
			}
		)
	return cards


func _task_definitions(state: BattleState) -> Array[String]:
	var definitions: Array[String] = []
	for task: Dictionary in state.tasks:
		definitions.append(str(task.definition_id))
	return definitions


func _task(catalog: ContentDB, task_id: String) -> Dictionary:
	var result := catalog.get_definition("task", task_id)
	return result.data if result.ok else {}


func _first_phase(task_definition: Dictionary) -> Dictionary:
	var phases: Array = task_definition.get("phases", [])
	return phases[0] if not phases.is_empty() else {}


func _has_event(step: GameResult, event_type: StringName) -> bool:
	if not step.ok:
		return false
	for event: RuleEvent in step.data.events:
		if event.type == event_type:
			return true
	return false


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("minion encounters: " + label)
