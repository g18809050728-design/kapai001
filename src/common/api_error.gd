class_name ApiError
extends RefCounted

var code: StringName
var message_key: String
var details: Dictionary


func _init(
	p_code: StringName = &"", p_message_key: String = "", p_details: Dictionary = {}
) -> void:
	code = p_code
	message_key = p_message_key
	details = p_details.duplicate(true)


func to_dictionary() -> Dictionary:
	return {
		"code": String(code),
		"message_key": message_key,
		"details": details.duplicate(true),
	}
