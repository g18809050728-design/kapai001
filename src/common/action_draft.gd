class_name ActionDraft
extends RefCounted

var type: StringName
var payload: Dictionary


func _init(p_type: StringName = &"", p_payload: Dictionary = {}) -> void:
	type = p_type
	payload = p_payload.duplicate(true)
