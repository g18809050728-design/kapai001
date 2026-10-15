class_name BattlePhaseFlow
extends RefCounted

const PHASE_ORDER: Array[String] = [
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


static func is_valid_phase(phase: String) -> bool:
	return PHASE_ORDER.has(phase)


static func next_phase(phase: String) -> String:
	var phase_index := PHASE_ORDER.find(phase)
	if phase_index < 0:
		return ""
	return PHASE_ORDER[(phase_index + 1) % PHASE_ORDER.size()]


static func advance(state: BattleState) -> BattleState:
	if state == null or not is_valid_phase(state.phase):
		return null
	var next_state := state.copy()
	if state.phase == "round_end":
		next_state.round_index += 1
	next_state.phase = next_phase(state.phase)
	return next_state
