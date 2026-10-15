class_name BattleStep
extends RefCounted

var state: BattleState
var events: Array[RuleEvent]
var pending_choice: Variant
var outcome: Variant
var stable: bool
var rng_state: Dictionary


func _init(
	p_state: BattleState = null,
	p_events: Array[RuleEvent] = [],
	p_pending_choice: Variant = null,
	p_outcome: Variant = null,
	p_stable: bool = false,
	p_rng_state: Dictionary = {}
) -> void:
	state = p_state
	events = p_events.duplicate()
	pending_choice = (
		p_pending_choice.duplicate(true)
		if typeof(p_pending_choice) == TYPE_DICTIONARY
		else p_pending_choice
	)
	outcome = p_outcome.duplicate(true) if typeof(p_outcome) == TYPE_DICTIONARY else p_outcome
	stable = p_stable
	rng_state = p_rng_state.duplicate(true)
