class_name ActionResult
extends RefCounted

var accepted: bool = false
var revision: int = 0
var view: SessionView
var events: Array[RuleEvent] = []
var pending_choice: ChoiceRequest
var stable: bool = true
var error: ApiError
var persistence: StringName = GameConstants.PERSISTENCE_NOT_ATTEMPTED
var save_error: ApiError
var profile_merge: StringName = &"not_pending"
var profile_error: ApiError
var profile_cleanup: StringName = &"not_needed"
var cleanup_error: ApiError


func _init(p_view: SessionView = null) -> void:
	view = p_view.copy() if p_view != null else SessionView.new()
	revision = view.revision
	pending_choice = view.pending_choice.copy() if view.pending_choice != null else null


static func rejected(api_error: ApiError, current_view: SessionView) -> ActionResult:
	var result := ActionResult.new(current_view)
	result.error = api_error
	return result
