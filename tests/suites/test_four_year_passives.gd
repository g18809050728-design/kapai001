extends RefCounted

var _failures: Array[String] = []
var _catalog := ContentDB.new("res://data/four_year")
var _engine: BattleEngine

func run() -> Array[String]:
	var loaded := _catalog.load("campus_four_year")
	_check(loaded.ok, "production catalog loads")
	if not loaded.ok:
		return _failures
	_engine = BattleEngine.new(_catalog)
	_test_p01()
	_test_p02()
	_test_p03()
	_test_p04("N01")
	_test_p04("Q01")
	if _failures.is_empty():
		print("FOUR_YEAR_PASSIVES=passed (P01 automatic retrieve; optional decline remains missing)")
	return _failures

func _test_p01() -> void:
	var step := _begin("P01", ["R3-P01-04", "R3-P01-11", "R3-P01-02", "R3-P01-02"])
	step = _play(step, 0)
	step = _play(step, 2, true)
	if not step.ok: return
	_check(step.data.state.zones.hand.has(_instance(step.data.state, 0)), "P01 retrieves the preceding permanent strategy")
	var repeated := _play(step, 0, false, false)
	_check(not repeated.ok, "P01 retrieval preserves the strategy instance's round limit")
	step = _play(step, 1)
	step = _play(step, 3, true)
	if step.ok:
		_check(step.data.state.zones.discard.has(_instance(step.data.state, 1)), "P01 cannot retrieve twice in the same round")

func _test_p02() -> void:
	var step := _begin("P02", ["R3-P02-01", "R3-C-02", "R3-C-02", "R3-P02-03"])
	step = _play(step, 0)
	if not step.ok: return
	_check(int(step.data.state.v3.paper.progress) == 0, "P02 opening does not record itself")
	step = _play(step, 1)
	if not step.ok: return
	_check(int(step.data.state.v3.paper.progress) == 1, "P02 first paper name gains progress")
	var repeated := _play(step, 2, false, false)
	_check(not repeated.ok, "P02 same name is unavailable twice in one round")
	step = _engine.apply(step.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), step.data.rng_state)
	_check(step.ok, "P02 advances to the next round")
	step = _play(step, 2)
	if not step.ok: return
	_check(int(step.data.state.v3.paper.progress) == 1 and int(step.data.state.v3.paper.citations) == 1, "P02 repeated paper name gains citation instead of progress")
	step = _play(step, 3)
	if step.ok:
		_check(int(step.data.state.v3.paper.progress) == 2, "P02 another new name records in the same round")

func _test_p03() -> void:
	var step := _begin("P03", ["R3-P03-17", "R3-P03-21"])
	step = _play(step, 0, true)
	if not step.ok: return
	_check(_stacks(step.data.state, "induced") == 1 and _stacks(step.data.state, "vulnerability") == 2, "P03 compound reaction adds one to the new different negative")
	step = _play(step, 1, true)
	if step.ok:
		_check(_stacks(step.data.state, "weakness") == 1 and _stacks(step.data.state, "feebleness") == 1, "P03 compound reaction triggers only once per round")

func _test_p04(encounter_id: String) -> void:
	var step := _begin("P04", ["R3-P04-01", "R3-P04-01"], encounter_id)
	step = _play(step, 0, encounter_id == "Q01")
	if not step.ok: return
	var state: BattleState = step.data.state
	_check(int(state.v3.synergy) == 1, "P04 first cooperation grants one synergy: " + encounter_id)
	_check(int(state.player.relax) == (5 if encounter_id == "Q01" else 2), "P04 first cooperation grants two passive relax after the card body: " + encounter_id)
	step = _play(step, 1, encounter_id == "Q01")
	if step.ok:
		_check(int(step.data.state.v3.synergy) == 1, "P04 second cooperation gives no additional passive synergy: " + encounter_id)
		_check(int(step.data.state.player.relax) == (8 if encounter_id == "Q01" else 2), "P04 second cooperation gives no additional passive relax: " + encounter_id)

# Controlled hands use the unchanged four-year production definitions and encounters.
func _begin(character_id: String, definitions: Array, encounter_id: String = "N01") -> GameResult:
	var cards: Array[Dictionary] = []
	for index in 12:
		cards.append({"card_id": "passive_%d" % index, "definition_id": definitions[index] if index < definitions.size() else "R3-C-02", "upgrade_level": 0})
	var step := _engine.begin({
		"battle_id": "passive-" + character_id + encounter_id,
		"encounter_id": encounter_id, "character_id": character_id,
		"difficulty": "normal", "vitality": 72, "max_vitality": 72,
		"cards": cards, "relics": [],
		"rng_state": RandomSource.new("four-year-passives").export_state().to_dictionary(),
	})
	_check(step.ok, "battle begins: " + character_id + encounter_id)
	return step

func _play(step: GameResult, index: int, targets_task: bool = false, expect_accepted: bool = true) -> GameResult:
	if not step.ok: return step
	var state: BattleState = step.data.state
	var card_id := _instance(state, index)
	if not state.zones.hand.has(card_id):
		for zone in ["draw", "discard"]: state.zones[zone].erase(card_id)
		state.zones.hand.append(card_id)
	state.player.focus = 10
	var result := _engine.apply(state, ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {
		"card_instance_id": card_id,
		"target_ids": [str(state.tasks[0].task_id)] if targets_task else [],
	}), step.data.rng_state)
	if expect_accepted:
		_check(result.ok, "card resolves: %s / %s" % [state.character_id, str(result.error.to_dictionary() if result.error != null else index)])
	return result

func _instance(state: BattleState, index: int) -> String:
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("origin_card_id", "")) == "passive_%d" % index:
			return str(card_id)
	return ""

func _stacks(state: BattleState, status_id: String) -> int:
	for status in state.statuses:
		if status.status_id == status_id and status.target_id == state.tasks[0].task_id:
			return int(status.stacks)
	return 0

func _check(value: bool, message: String) -> void:
	if not value: _failures.append("four-year passive: " + message)
