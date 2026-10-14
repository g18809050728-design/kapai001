class_name Result
extends RefCounted
##
## 统一返回结构（《接口文档》§1.2）：
##   Result<T> = {ok: bool, data: T 或 null, error: ApiError 或 null}
##   ApiError  = {code: String, message_key: String, details: Dictionary}
##
## GDScript 没有泛型，所以 Result 就是普通 Dictionary；这里只提供构造与读取工具，
## 不包一层自定义类型——否则每次调用都要多一次解包。
##

const GameConstants := preload("res://src/common/game_constants.gd")


static func ok(data: Variant = null) -> Dictionary:
	return {"ok": true, "data": data, "error": null}


static func fail(code: String, message_key: String = "", details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"error": {
			"code": code,
			"message_key": message_key,
			"details": details,
		},
	}


static func is_ok(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


static func data_of(result: Dictionary, fallback: Variant = null) -> Variant:
	return result.get("data", fallback)


static func error_code(result: Dictionary) -> String:
	var error: Variant = result.get("error")
	if typeof(error) != TYPE_DICTIONARY:
		return ""
	return String((error as Dictionary).get("code", ""))


static func error_detail(result: Dictionary, key: String, fallback: Variant = null) -> Variant:
	var error: Variant = result.get("error")
	if typeof(error) != TYPE_DICTIONARY:
		return fallback
	var details: Variant = (error as Dictionary).get("details")
	if typeof(details) != TYPE_DICTIONARY:
		return fallback
	return (details as Dictionary).get(key, fallback)
