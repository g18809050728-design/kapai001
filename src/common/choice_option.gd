class_name ChoiceOption
extends RefCounted

var id: String
var label_key: String
var preview: Dictionary


func _init(p_id: String = "", p_label_key: String = "", p_preview: Dictionary = {}) -> void:
	id = p_id
	label_key = p_label_key
	preview = p_preview.duplicate(true)
