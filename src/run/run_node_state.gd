class_name RunNodeState
extends RefCounted

var node_id: String
var term: int
var layer: int
var kind: String
var status: String
var next_ids: Array[String] = []
var context: Dictionary


func _init(values: Dictionary = {}) -> void:
	node_id = values.get("node_id", "")
	term = values.get("term", 1)
	layer = values.get("layer", 1)
	kind = values.get("kind", "normal")
	status = values.get("status", "pending")
	for id in values.get("next_ids", []):
		next_ids.append(str(id))
	context = duplicate_value(values.get("context", {}))


static func create(values: Dictionary = {}) -> RunNodeState:
	return RunNodeState.new(values)


func copy() -> RunNodeState:
	var result := RunNodeState.new(to_dictionary())
	result.context = duplicate_value(context)
	return result


func copy_for_write() -> RunNodeState:
	return copy()


func to_dictionary() -> Dictionary:
	return {
		"node_id": node_id,
		"term": term,
		"layer": layer,
		"kind": kind,
		"status": status,
		"next_ids": next_ids.duplicate(),
		"context": encode_value(context),
	}


static func duplicate_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = duplicate_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(duplicate_value(item))
		return result
	if value is Object and value.has_method("copy"):
		return value.copy()
	return value


static func encode_value(value: Variant) -> Variant:
	if value is Object and value.has_method("to_dictionary"):
		return value.to_dictionary()
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = encode_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(encode_value(item))
		return result
	return value
