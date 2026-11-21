extends RefCounted

const PRODUCTION_MANIFEST := "campus_four_year"
const TEST_VITALITY := 200
const BOSS_IDS := [
	"FY_B1_TASK",
	"FY_B2_TASK",
	"FY_B3_TASK",
	"FY_B4_TASK",
	"FY_ROUTE_job_TASK",
	"FY_ROUTE_exam_TASK",
	"FY_ROUTE_research_TASK",
	"FY_ROUTE_abroad_TASK",
]

var _failures: Array[String] = []
var _catalog := ContentDB.new("res://data/four_year")
var _engine: BattleEngine


func run() -> Array[String]:
	var loaded := _catalog.load(PRODUCTION_MANIFEST)
	_check(bool(loaded.ok), "boss mechanics catalog loads")
	if bool(loaded.ok):
		_check_n26_injection()
		_check_boss_summon_taunt()
		_check_boss_junk_and_max_vitality()
		_check_content_invariants()
	if _failures.is_empty():
		print("BOSS_MECHANICS_SUITE=passed")
	return _failures


func _check_n26_injection() -> void:
	var n26 := _catalog.get_definition("task", "N26")
	_check(bool(n26.ok), "N26 讲座考勤 is defined")
	if not bool(n26.ok):
		return
	var injected := ""
	for intent: Dictionary in n26.data.phases[0].intents:
		if intent.has("add_card"):
			injected = str(intent.add_card.get("card", ""))
	_check(injected == "X03", "N26 injects the X03 签到表 card (got %s)" % injected)
	_check(bool(_catalog.get_definition("card", "X03").ok), "X03 签到表 is enabled")

	var begun := _begin("N26")
	_check(bool(begun.ok), "N26 battle begins")
	if not bool(begun.ok):
		return
	var ended := _end_turn(begun)
	_check(bool(ended.ok), "N26 first enemy turn resolves")
	if bool(ended.ok):
		var state: BattleState = ended.data.state
		_check(_zone_has(state, "hand", "X03"), "N26 deals 签到表 into the player's hand")


func _check_boss_summon_taunt() -> void:
	var begun := _begin("FY_B1")
	_check(bool(begun.ok), "FY_B1 boss battle begins")
	if not bool(begun.ok):
		return
	var ended := _end_turn(begun)
	_check(bool(ended.ok), "FY_B1 first enemy turn resolves")
	if not bool(ended.ok):
		return
	var state: BattleState = ended.data.state
	var summon: Dictionary = {}
	var boss_id := ""
	for task: Dictionary in state.tasks:
		if str(task.definition_id) == "N14":
			summon = task
		elif str(task.definition_id) == "FY_B1_TASK":
			boss_id = str(task.task_id)
	_check(not summon.is_empty(), "FY_B1 summons a priority-group minion (N14)")
	if summon.is_empty():
		return
	_check(bool(summon.get("taunt", false)), "the summoned minion is taunting")
	_check(int(summon.work_max) == 16, "the summon is scaled to 60%% work (got %d)" % int(summon.work_max))

	var candidates := _engine._target_candidates(state, "task")
	var ids: Array[String] = []
	for candidate: Dictionary in candidates:
		ids.append(str(candidate.get("id", "")))
	_check(ids.size() == 1 and ids.has(str(summon.task_id)), "taunt makes the summoned minion the only task target")
	_check(not ids.has(boss_id), "taunt keeps the boss out of single-target selection")


func _check_boss_junk_and_max_vitality() -> void:
	var begun := _begin("FY_B1")
	_check(bool(begun.ok), "FY_B1 junk battle begins")
	if not bool(begun.ok):
		return
	var step := begun
	for _index in 3:
		step = _end_turn(step)
		if not bool(step.ok):
			break
	_check(bool(step.ok), "FY_B1 three enemy turns resolve")
	if not bool(step.ok):
		return
	var state: BattleState = step.data.state
	_check(
		int(state.player.max_vitality) == TEST_VITALITY - 1,
		"the boss lowers max vitality by 1 (got %d)" % int(state.player.max_vitality)
	)
	var has_junk := false
	for card: Dictionary in state.card_by_id.values():
		if str(card.get("definition_id", "")) == "X04":
			has_junk = true
	_check(has_junk, "the boss injects the X04 修改意见 junk card")


func _check_content_invariants() -> void:
	for id: String in BOSS_IDS:
		var definition := _catalog.get_definition("task", id)
		_check(bool(definition.ok), "boss task is defined: " + id)
		if not bool(definition.ok):
			continue
		var statuses := {}
		var has_summon := false
		var has_max_reduce := false
		var has_junk := false
		for phase: Dictionary in definition.data.phases:
			for intent: Dictionary in phase.get("intents", []):
				if intent.has("gain_status"):
					var status_target := str(intent.gain_status.get("target", ""))
					if status_target == "player":
						statuses[str(intent.gain_status.get("status", ""))] = true
				if intent.has("summon_tasks"):
					has_summon = true
					for spec: Dictionary in intent.summon_tasks:
						_check(
							bool(spec.get("taunt", false)),
							id + " summons a taunting minion"
						)
						var add_id := str(spec.get("task", ""))
						var add_definition := _catalog.get_definition("task", add_id)
						_check(
							bool(add_definition.ok)
							and str(add_definition.data.get("spawn_group", "")) == "priority",
							id + " summons a first-group (priority) minion"
						)
						if bool(add_definition.ok):
							_check(
								not add_definition.data.get("on_complete_effects", []).is_empty(),
								id + " summoned minion carries a kill reward"
							)
							for add_phase: Dictionary in add_definition.data.phases:
								for add_intent: Dictionary in add_phase.get("intents", []):
									if add_intent.has("gain_status"):
										if str(add_intent.gain_status.get("target", "")) == "player":
											statuses[str(add_intent.gain_status.get("status", ""))] = true
				if intent.has("player_reduce_max_vitality"):
					has_max_reduce = true
				if intent.has("add_card"):
					has_junk = true
					_check(
						str(intent.add_card.get("card", "")) == "X04",
						id + " injects the X04 junk card"
					)
		_check(has_summon, id + " has a taunt summon")
		_check(has_max_reduce, id + " trims the player's max vitality")
		_check(has_junk, id + " injects a junk card")
		_check(
			statuses.size() <= 2,
			id + " applies at most two negative statuses (got %d)" % statuses.size()
		)


func _zone_has(state: BattleState, zone: String, definition_id: String) -> bool:
	for card_id: String in state.zones.get(zone, []):
		var card: Dictionary = state.card_by_id.get(card_id, {})
		if str(card.get("definition_id", "")) == definition_id:
			return true
	return false


func _begin(encounter_id: String) -> GameResult:
	var rng := RandomSource.new("boss-mechanics-" + encounter_id)
	var cards: Array[Dictionary] = []
	for index in 10:
		cards.append(
			{"card_id": "origin_%02d" % index, "definition_id": "R3-C-01", "upgrade_level": 0}
		)
	_engine = BattleEngine.new(_catalog)
	return (
		_engine
		. begin(
			{
				"battle_id": "boss_mechanics_" + encounter_id,
				"node_id": "",
				"encounter_id": encounter_id,
				"character_id": "P01",
				"difficulty": "normal",
				"vitality": TEST_VITALITY,
				"max_vitality": TEST_VITALITY,
				"cards": cards,
				"relics": [],
				"rng_state": rng.export_state().to_dictionary(),
			}
		)
	)


func _end_turn(step: GameResult) -> GameResult:
	return _engine.apply(
		step.data.state, ActionDraft.new(GameConstants.ACTION_END_TURN, {}), step.data.rng_state
	)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append("boss mechanics: " + message)
