extends RefCounted

var _failures: Array[String] = []
var _catalog := ContentDB.new("res://data/four_year")


func run() -> Array[String]:
	var loaded := _catalog.load("campus_four_year")
	_check(loaded.ok, "four-year catalog loads")
	if not loaded.ok:
		return _failures
	_check_session_composition()
	_check_spawn_scaling()
	_check_death_effects()
	if _failures.is_empty():
		print("COMPOSED_ENCOUNTERS_SUITE=passed")
	return _failures


func _check_session_composition() -> void:
	var store := SaveStore.new("user://composed-session-%d" % Time.get_ticks_usec())
	var session := GameSession.new(store)
	session.update_settings({"autosave": false})
	var started := session.start_run(
		StartRunRequest.new("P01", &"normal", "campus_four_year", "42")
	)
	_check(started.accepted, "composed run starts")
	if not started.accepted:
		return
	var view := session.get_view()
	var normal_id := ""
	for node in view.run.nodes:
		if node.kind == "normal" and view.run.reachable_node_ids.has(node.node_id):
			normal_id = node.node_id
			break
	_check(not normal_id.is_empty(), "term opens a reachable normal node")
	if normal_id.is_empty():
		return
	var entered := session.submit(
		CommandContext.new(str(view.run_id), view.revision),
		GameAction.new(&"enter_node", {"node_id": normal_id})
	)
	_check(entered.accepted, "composed normal node enters")
	if not entered.accepted or session._state.battle == null:
		return
	var battle: BattleState = session._state.battle
	_check(battle.encounter_id in ["NR2", "NR3"], "normal node picks a composed encounter")
	_check(battle.tasks.size() in [2, 3], "composed battle spawns two or three tasks")
	var priority := 0
	var other := 0
	for task: Dictionary in battle.tasks:
		var definition := _task_definition(str(task.definition_id))
		if str(definition.get("spawn_group", "other")) == "priority":
			priority += 1
		else:
			other += 1
	_check(priority == 1, "composed battle includes exactly one priority task")
	_check(other == battle.tasks.size() - 1, "composed battle fills the rest from the other group")
	if battle.encounter_id == "NR2":
		_check(other == 1, "NR2 is a 1:1 composition")
	elif battle.encounter_id == "NR3":
		_check(other == 2, "NR3 is a 1:2 composition")
		if battle.tasks.size() == 3:
			var middle := _task_definition(str(battle.tasks[1].definition_id))
			_check(
				str(middle.get("spawn_group", "")) == "priority",
				"NR3 places the priority task between the two others"
			)


func _check_spawn_scaling() -> void:
	for pair in [["NR2", 2, 75, 1], ["NR3", 3, 67, 2]]:
		var encounter_id := str(pair[0])
		var count := int(pair[1])
		var percent := int(pair[2])
		var ddl_bonus := int(pair[3])
		var members := _member_pool()
		var picked: Array[String] = []
		for index in count:
			picked.append(str(members[index]))
		var begun := _begin(encounter_id, picked)
		_check(begun.ok, encounter_id + " begins with explicit members")
		if not begun.ok:
			continue
		var state: BattleState = begun.data.state
		_check(state.tasks.size() == count, encounter_id + " spawns the requested count")
		_check(
			state.ddl == int(_encounter(encounter_id).base_ddl) + ddl_bonus,
			encounter_id + " applies its DDL bonus"
		)
		for task: Dictionary in state.tasks:
			var definition := _task_definition(str(task.definition_id))
			var base_work := int(definition.phases[0].work_max)
			var expected := maxi(1, int(ceil(base_work * percent / 100.0)))
			_check(int(task.work_max) == expected, encounter_id + " scales task work")
			_check(int(task.power_percent) == percent, encounter_id + " scales task pressure")


func _check_death_effects() -> void:
	var n14 := _begin("NR3", ["N13", "N14", "N15"])
	_check(n14.ok, "N14 deathrattle battle begins")
	if n14.ok:
		var state: BattleState = n14.data.state
		var target_ids := _task_ids(state)
		for task: Dictionary in state.tasks:
			task.shield = 0
		var before := _work_snapshot(state)
		var applied := _apply_death(
			state, target_ids["N14"], _task_definition("N14").on_complete_effects, n14.data.rng_state
		)
		_check(applied.ok, "N14 deathrattle resolves")
		if applied.ok:
			for task: Dictionary in state.tasks:
				var task_id := str(task.task_id)
				if task_id == target_ids["N14"]:
					continue
				_check(
					int(task.work_remaining) == int(before[task_id]) - 4,
					"N14 damages every other task"
				)
		for task: Dictionary in state.tasks:
			task.shield = 10
		var shielded := _apply_death(
			state, target_ids["N14"], _task_definition("N14").on_complete_effects, n14.data.rng_state
		)
		_check(shielded.ok, "N14 shielded deathrattle resolves")
		if shielded.ok:
			for task: Dictionary in state.tasks:
				var task_id := str(task.task_id)
				if task_id == target_ids["N14"]:
					continue
				_check(int(task.shield) == 2, "N14 lowers other shields by 8 across both effects")

	var n20 := _begin("NR3", ["N13", "N20", "N15", "N16"])
	_check(n20.ok, "N20 deathrattle battle begins")
	if n20.ok:
		var state: BattleState = n20.data.state
		var target_ids := _task_ids(state)
		for task: Dictionary in state.tasks:
			task.shield = 0
		var before := _work_snapshot(state)
		var applied := _apply_death(
			state, target_ids["N20"], _task_definition("N20").on_complete_effects, n20.data.rng_state
		)
		_check(applied.ok, "N20 deathrattle resolves")
		if applied.ok:
			for task: Dictionary in state.tasks:
				var task_id := str(task.task_id)
				if task_id == target_ids["N20"]:
					continue
				_check(
					int(task.work_remaining) == int(before[task_id]) - 4,
					"N20 damages every other task"
				)
		for task: Dictionary in state.tasks:
			task.shield = 10
		var shielded := _apply_death(
			state, target_ids["N20"], _task_definition("N20").on_complete_effects, n20.data.rng_state
		)
		_check(shielded.ok, "N20 shielded deathrattle resolves")
		if shielded.ok:
			for task: Dictionary in state.tasks:
				var task_id := str(task.task_id)
				if task_id == target_ids["N20"]:
					continue
				_check(int(task.shield) == 2, "N20 lowers every other shield by 8 across both effects")


func _apply_death(
	state: BattleState, task_id: String, effects: Array, rng_state: Dictionary
) -> GameResult:
	var events: Array[RuleEvent] = []
	return _engine._run_on_complete_effects(state, task_id, effects, _rng(rng_state), events)


func _work_snapshot(state: BattleState) -> Dictionary:
	var result := {}
	for task: Dictionary in state.tasks:
		result[str(task.task_id)] = int(task.work_remaining)
	return result


func _begin(encounter_id: String, member_ids: Array) -> GameResult:
	var rng := RandomSource.new("composed-" + encounter_id)
	var cards: Array[Dictionary] = []
	for index in 10:
		cards.append(
			{
				"card_id": "origin_%02d" % index,
				"definition_id": "R3-C-01",
				"upgrade_level": 0,
			}
		)
	_engine = BattleEngine.new(_catalog)
	return (
		_engine
		. begin(
			{
				"battle_id": "composed_" + encounter_id,
				"node_id": "",
				"encounter_id": encounter_id,
				"character_id": "P01",
				"difficulty": "normal",
				"vitality": 72,
				"max_vitality": 72,
				"cards": cards,
				"relics": [],
				"rng_state": rng.export_state().to_dictionary(),
				"member_ids": member_ids,
			}
		)
	)


var _engine: BattleEngine


func _rng(rng_state: Dictionary) -> RandomSource:
	var rng := RandomSource.new("composed-apply")
	rng.restore_state(rng_state)
	return rng


func _member_pool() -> Array[String]:
	return ["N13", "N14", "N15", "N16", "N17", "N20"]


func _task_ids(state: BattleState) -> Dictionary:
	var result := {}
	for task: Dictionary in state.tasks:
		result[str(task.definition_id)] = str(task.task_id)
	return result


func _task_definition(task_id: String) -> Dictionary:
	return _catalog.get_definition("task", task_id).data


func _encounter(encounter_id: String) -> Dictionary:
	return _catalog.get_definition("encounter", encounter_id).data


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append("composed encounters: " + label)
