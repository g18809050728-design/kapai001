class_name EventState
extends RefCounted

var event_instance_id: String
var node_id: String
var definition_id: String
var resolved_option_id: String
var frozen_candidates: Dictionary


func _init(values: Dictionary = {}) -> void:
	event_instance_id = values.get("event_instance_id", "")
	node_id = values.get("node_id", "")
	definition_id = values.get("definition_id", "")
	resolved_option_id = values.get("resolved_option_id", "")
	frozen_candidates = values.get("frozen_candidates", {}).duplicate(true)


static func create(values: Dictionary = {}) -> EventState:
	return EventState.new(values)


func copy() -> EventState:
	return EventState.new(to_dictionary())


func copy_for_write() -> EventState:
	return copy()


func to_dictionary() -> Dictionary:
	return {
		"event_instance_id": event_instance_id,
		"node_id": node_id,
		"definition_id": definition_id,
		"resolved_option_id": resolved_option_id,
		"frozen_candidates": frozen_candidates.duplicate(true)
	}
