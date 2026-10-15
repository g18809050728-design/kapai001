extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var expected_order := [
		"player_prepare",
		"draw",
		"player_action",
		"ally_action",
		"discard",
		"enemy_prepare",
		"enemy_skill",
		"enemy_pressure",
		"round_end",
	]
	_check(BattlePhaseFlow.PHASE_ORDER == expected_order, "phase order matches contract", failures)
	for index in range(expected_order.size()):
		var phase: String = expected_order[index]
		var expected_next: String = expected_order[(index + 1) % expected_order.size()]
		_check(BattlePhaseFlow.is_valid_phase(phase), "phase is recognized: " + phase, failures)
		_check(
			BattlePhaseFlow.next_phase(phase) == expected_next,
			"phase advances to " + expected_next,
			failures
		)

	var state := BattleState.new({"phase": "round_end", "round_index": 3})
	var next_state := BattlePhaseFlow.advance(state)
	_check(next_state != null, "round end advances to a new state", failures)
	if next_state != null:
		_check(next_state.phase == "player_prepare", "round wraps to player preparation", failures)
		_check(next_state.round_index == 4, "round index advances at wrap", failures)
		_check(state.phase == "round_end", "advance leaves source phase unchanged", failures)
		_check(state.round_index == 3, "advance leaves source round unchanged", failures)

	var paused := BattleState.new({"phase": "awaiting_choice", "round_index": 1})
	_check(
		not BattlePhaseFlow.is_valid_phase(paused.phase),
		"choice pause is outside phase schedule",
		failures
	)
	_check(BattlePhaseFlow.advance(paused) == null, "invalid phase cannot advance", failures)
	_check(BattlePhaseFlow.next_phase("unknown") == "", "unknown phase has no successor", failures)
	return failures


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
