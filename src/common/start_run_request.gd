class_name StartRunRequest
extends RefCounted

var character_id: String
var difficulty: StringName
var manifest_id: String
var seed: String


func _init(
	p_character_id: String = "",
	p_difficulty: StringName = &"normal",
	p_manifest_id: String = "",
	p_seed: String = "0"
) -> void:
	character_id = p_character_id
	difficulty = p_difficulty
	manifest_id = p_manifest_id
	seed = p_seed
