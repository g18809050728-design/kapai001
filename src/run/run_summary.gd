class_name RunSummary
extends RefCounted

var run_id: String
var result: String
var reason: String
var ending_id: String
var character_id: String
var difficulty: String
var manifest_id: String
var term: int
var statistics: Dictionary
var unlocked_ids: Array[String] = []
var seen_content_ids: Array[String] = []


func _init(values: Dictionary = {}) -> void:
	run_id = values.get("run_id", "")
	result = values.get("result", "")
	reason = values.get("reason", "")
	ending_id = values.get("ending_id", "")
	character_id = values.get("character_id", "")
	difficulty = values.get("difficulty", "normal")
	manifest_id = values.get("manifest_id", "")
	term = values.get("term", 1)
	statistics = values.get("statistics", {}).duplicate(true)
	for id in values.get("unlocked_ids", []):
		unlocked_ids.append(str(id))
	for id in values.get("seen_content_ids", []):
		seen_content_ids.append(str(id))


static func create(values: Dictionary = {}) -> RunSummary:
	return RunSummary.new(values)


func copy() -> RunSummary:
	return RunSummary.new(to_dictionary())


func copy_for_write() -> RunSummary:
	return copy()


func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"result": result,
		"reason": reason,
		"ending_id": ending_id,
		"character_id": character_id,
		"difficulty": difficulty,
		"manifest_id": manifest_id,
		"term": term,
		"statistics": statistics.duplicate(true),
		"unlocked_ids": unlocked_ids.duplicate(),
		"seen_content_ids": seen_content_ids.duplicate()
	}
