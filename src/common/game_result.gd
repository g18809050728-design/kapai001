class_name GameResult
extends RefCounted

var ok: bool
var data: Variant
var error: ApiError


func _init(p_ok: bool = false, p_data: Variant = null, p_error: ApiError = null) -> void:
	ok = p_ok
	data = p_data
	error = p_error


static func success(value: Variant) -> GameResult:
	return GameResult.new(true, value)


static func failure(api_error: ApiError) -> GameResult:
	return GameResult.new(false, null, api_error)
