class_name ChoiceRequest
extends RefCounted

var choice_id: String
var kind: StringName
var candidates: Array[ChoiceOption] = []
var min_count: int = 0
var max_count: int = 0
var prompt_key: String = ""
var source_card_id: Variant = null
var effect_amount: Variant = null


func _init(
	p_choice_id: String = "",
	p_kind: StringName = &"",
	p_candidates: Array[ChoiceOption] = [],
	p_min_count: int = 0,
	p_max_count: int = 0,
	p_prompt_key: String = "",
	p_source_card_id: Variant = null,
	p_effect_amount: Variant = null
) -> void:
	choice_id = p_choice_id
	kind = p_kind
	candidates = p_candidates.duplicate()
	min_count = p_min_count
	max_count = p_max_count
	prompt_key = p_prompt_key
	source_card_id = p_source_card_id
	effect_amount = p_effect_amount


func copy() -> ChoiceRequest:
	var copied_options: Array[ChoiceOption] = []
	for option in candidates:
		copied_options.append(ChoiceOption.new(option.id, option.label_key, option.preview))
	return ChoiceRequest.new(
		choice_id,
		kind,
		copied_options,
		min_count,
		max_count,
		prompt_key,
		source_card_id,
		effect_amount
	)
