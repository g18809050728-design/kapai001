class_name RewardOffer
extends RefCounted

var offer_id: String
var source_node_id: String
var items: Array[Dictionary] = []
var meta: Dictionary


func _init(values: Dictionary = {}) -> void:
	offer_id = str(values.get("offer_id", ""))
	source_node_id = str(values.get("source_node_id", ""))
	for item in values.get("items", []):
		items.append(item.duplicate(true))
	meta = values.get("meta", {}).duplicate(true)


static func create(values: Dictionary = {}) -> RewardOffer:
	return RewardOffer.new(values)


func copy() -> RewardOffer:
	return RewardOffer.new(to_dictionary())


func copy_for_write() -> RewardOffer:
	return copy()


func to_dictionary() -> Dictionary:
	return {
		"offer_id": offer_id,
		"source_node_id": source_node_id,
		"items": items.duplicate(true),
		"meta": meta.duplicate(true)
	}


func is_complete() -> bool:
	for item in items:
		if item.get("status", "pending") == "pending":
			return false
	return true


func get_item(item_id: String) -> Dictionary:
	for item in items:
		if str(item.get("item_id", "")) == item_id:
			return item
	return {}
