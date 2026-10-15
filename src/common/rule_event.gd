class_name RuleEvent
extends RefCounted

var index: int = 0
var type: StringName
var source_id: String
var target_ids: Array[String] = []
var data: Dictionary = {}


func _init(
	p_index: int = 0,
	p_type: StringName = &"",
	p_source_id: String = "",
	p_target_ids: Array[String] = [],
	p_data: Dictionary = {}
) -> void:
	index = p_index
	type = p_type
	source_id = p_source_id
	target_ids = p_target_ids.duplicate()
	data = p_data.duplicate(true)
