class_name RunStep
extends RefCounted

var state: RunState
var events: Array[RuleEvent] = []
var battle_input: Variant
var run_summary: RunSummary
var rng_states: Dictionary


func _init(
	p_state: RunState = null,
	p_events: Array[RuleEvent] = [],
	p_battle_input: Variant = null,
	p_run_summary: RunSummary = null,
	p_rng_states: Dictionary = {}
) -> void:
	state = p_state
	events = p_events.duplicate()
	battle_input = (
		p_battle_input.duplicate(true) if p_battle_input is Dictionary else p_battle_input
	)
	run_summary = p_run_summary
	rng_states = p_rng_states.duplicate(true)
