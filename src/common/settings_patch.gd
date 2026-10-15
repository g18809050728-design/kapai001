class_name SettingsPatch
extends RefCounted

var has_autosave: bool = false
var autosave: bool = false


func _init(p_has_autosave: bool = false, p_autosave: bool = false) -> void:
	has_autosave = p_has_autosave
	autosave = p_autosave


func to_dictionary() -> Dictionary:
	var values: Dictionary = {}
	if has_autosave:
		values["autosave"] = autosave
	return values
