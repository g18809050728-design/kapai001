class_name SessionView
extends RefCounted

var run_id: Variant = null
var revision: int = 0
var screen: StringName = GameConstants.SCREEN_MENU
var run: Variant = null
var battle: Variant = null
var node: Variant = null
var pending_choice: ChoiceRequest
var can_save: bool = false
var terminal_summary: Variant = null
var event_log: Array[Dictionary] = []
var profile_commit_status: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"revision": revision,
		"screen": String(screen),
		"run": run,
		"battle": battle,
		"node": node,
		"pending_choice": pending_choice,
		"can_save": can_save,
		"terminal_summary": terminal_summary,
		"event_log": event_log.duplicate(true),
		"profile_commit_status": profile_commit_status.duplicate(true),
	}


func copy() -> SessionView:
	var result := SessionView.new()
	result.run_id = run_id
	result.revision = revision
	result.screen = screen
	result.run = _copy_value(run)
	result.battle = _copy_value(battle)
	result.node = _copy_value(node)
	result.pending_choice = pending_choice.copy() if pending_choice != null else null
	result.can_save = can_save
	result.terminal_summary = _copy_value(terminal_summary)
	result.event_log = event_log.duplicate(true)
	result.profile_commit_status = profile_commit_status.duplicate(true)
	return result


func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
