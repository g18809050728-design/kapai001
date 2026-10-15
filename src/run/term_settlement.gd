class_name TermSettlement
extends RefCounted

var settlement_id: String
var term: int
var steps: Array[Dictionary] = []


func _init(values: Dictionary = {}) -> void:
	settlement_id = values.get("settlement_id", "")
	term = values.get("term", 1)
	for step in values.get("steps", []):
		steps.append(step.duplicate(true))


static func create(values: Dictionary = {}) -> TermSettlement:
	return TermSettlement.new(values)


func copy() -> TermSettlement:
	return TermSettlement.new(to_dictionary())


func copy_for_write() -> TermSettlement:
	return copy()


func is_complete() -> bool:
	for step in steps:
		if step.get("status", "pending") == "pending":
			return false
	return true


func to_dictionary() -> Dictionary:
	return {"settlement_id": settlement_id, "term": term, "steps": steps.duplicate(true)}
