class_name CommandContext
extends RefCounted

var run_id: String
var expected_revision: int


func _init(p_run_id: String = "", p_expected_revision: int = 0) -> void:
	run_id = p_run_id
	expected_revision = p_expected_revision
