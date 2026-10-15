class_name SessionSaveResult
extends RefCounted

var current_run_receipt: SaveReceipt
var profile_merge: StringName = &"not_pending"
var profile_error: ApiError
var profile_cleanup: StringName = &"not_needed"
var cleanup_error: ApiError
