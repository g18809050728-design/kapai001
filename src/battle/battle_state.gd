class_name BattleState
extends RefCounted

var battle_id: String
var node_id: String
var encounter_id: String
var character_id: String
var difficulty: String
var exam_flags: Array[String]
var phase: String
var round_index: int
var ddl: int
var player: Dictionary
var card_by_id: Dictionary
var relics: Array[String]
var zones: Dictionary
var units: Array[Dictionary]
var tasks: Array[Dictionary]
var statuses: Array[Dictionary]
var retained_card_ids: Array[String]
var scene: Variant
var counters: Dictionary
var resolution: Variant
var outcome: Variant
var next_creation_order: int
var next_instance_seq: int
var source_registry: Dictionary


func _init(values: Dictionary = {}) -> void:
	battle_id = values.get("battle_id", "")
	node_id = values.get("node_id", "")
	encounter_id = values.get("encounter_id", "")
	character_id = values.get("character_id", "")
	difficulty = values.get("difficulty", "normal")
	exam_flags = _string_array(values.get("exam_flags", []))
	phase = values.get("phase", "player_prepare")
	round_index = values.get("round_index", 1)
	ddl = values.get("ddl", 1)
	player = values.get("player", {}).duplicate(true)
	card_by_id = values.get("card_by_id", {}).duplicate(true)
	relics = _string_array(values.get("relics", []))
	zones = values.get("zones", {}).duplicate(true)
	units = _dictionary_array(values.get("units", []))
	tasks = _dictionary_array(values.get("tasks", []))
	statuses = _dictionary_array(values.get("statuses", []))
	retained_card_ids = _string_array(values.get("retained_card_ids", []))
	scene = values.get("scene")
	if typeof(scene) == TYPE_DICTIONARY:
		scene = scene.duplicate(true)
	counters = values.get("counters", {}).duplicate(true)
	resolution = values.get("resolution")
	if typeof(resolution) == TYPE_DICTIONARY:
		resolution = resolution.duplicate(true)
	outcome = values.get("outcome")
	if typeof(outcome) == TYPE_DICTIONARY:
		outcome = outcome.duplicate(true)
	next_creation_order = values.get("next_creation_order", 1)
	next_instance_seq = values.get("next_instance_seq", 1)
	source_registry = values.get("source_registry", {}).duplicate(true)


func copy() -> BattleState:
	return BattleState.new(to_dictionary())


func validate(unit_slots: int = 2147483647) -> Array[String]:
	var issues: Array[String] = []
	if battle_id.is_empty() or encounter_id.is_empty() or character_id.is_empty():
		issues.append("battle identity is missing")
	if phase not in ["player_action", "finished"] or resolution != null:
		issues.append("battle is not at a stable boundary")
	if round_index < 1 or ddl < 0 or next_instance_seq < 1 or next_creation_order < 1:
		issues.append("battle round/DDL/sequence is invalid")
	if phase == "player_action" and (ddl < 1 or tasks.is_empty() or outcome != null):
		issues.append("active battle requires tasks/DDL and no outcome")
	if phase == "finished" and outcome == null:
		issues.append("finished battle requires outcome")
	if (
		int(player.get("vitality", -1)) < 0
		or int(player.get("max_vitality", 0)) < 1
		or int(player.get("vitality", 0)) > int(player.get("max_vitality", 0))
	):
		issues.append("battle player vitality is invalid")
	if int(player.get("focus", -1)) < 0 or int(player.get("relax", -1)) < 0:
		issues.append("battle player resources are negative")
	var instances := {}
	var holders := {}
	var player_id := str(player.get("entity_id", ""))
	_validate_instance(player_id, instances, issues)
	holders[player_id] = true
	var origins := {}
	for id in card_by_id:
		var card: Dictionary = card_by_id[id]
		_validate_instance(str(id), instances, issues)
		if str(card.get("card_id", "")) != id:
			issues.append("battle card key disagrees with instance ID")
		var origin := str(card.get("origin_card_id", ""))
		if not origin.is_empty():
			RunCodec.unique(origin, origins, "battle.card.origin_card_id", issues)
		if not card.get("temporary_modifiers", {}).is_empty():
			issues.append("battle temporary modifiers are unsupported")
	var zoned := {}
	for zone in zones:
		for id in zones[zone]:
			RunCodec.unique(str(id), zoned, "battle zone card", issues)
			if not card_by_id.has(id):
				issues.append("battle zone references a missing card")
	if zoned.size() != card_by_id.size():
		issues.append("battle card is omitted from zones")
	if not zones.get("resolving", []).is_empty():
		issues.append("stable battle has resolving cards")
	for id in retained_card_ids:
		if not zones.get("hand", []).has(id):
			issues.append("battle retained card must be in hand")
	if units.size() > unit_slots:
		issues.append("battle unit capacity exceeded")
	for unit in units:
		var id := str(unit.get("unit_id", ""))
		_validate_instance(id, instances, issues)
		holders[id] = true
		if (
			int(unit.get("vitality", 0)) < 1
			or int(unit.get("max_vitality", 0)) < int(unit.get("vitality", 0))
		):
			issues.append("battle live unit vitality invalid")
		if (
			int(unit.get("cooperation", -1)) < 0
			or int(unit.get("relax", 0)) < 0
			or int(unit.get("actions_taken", -1)) < 0
		):
			issues.append("battle unit resources/counters invalid")
		_validate_source_order(id, int(unit.get("entered_order", 0)), issues)
	for task in tasks:
		var id := str(task.get("task_id", ""))
		_validate_instance(id, instances, issues)
		holders[id] = true
		if (
			int(task.get("work_remaining", 0)) < 1
			or int(task.get("work_remaining", 0)) > int(task.get("work_max", 0))
			or int(task.get("shield", -1)) < 0
		):
			issues.append("battle task resources invalid")
		if (
			int(task.get("eligible_round", 0)) < 1
			or int(task.get("eligible_round", 0)) > round_index
		):
			issues.append("battle task eligible round invalid")
		_validate_source_order(id, int(task.get("entered_order", 0)), issues)
	var status_pairs := {}
	for status in statuses:
		_validate_instance(str(status.get("instance_id", "")), instances, issues)
		if not holders.has(str(status.get("target_id", ""))):
			issues.append("battle status holder is unknown or departed")
		if int(status.get("stacks", 0)) < 1:
			issues.append("battle status stacks must be positive")
		RunCodec.unique(
			"%s|%s" % [status.get("status_id", ""), status.get("target_id", "")],
			status_pairs,
			"battle status/holder",
			issues
		)
	if scene != null:
		_validate_instance(str(scene.get("scene_id", "")), instances, issues)
		if (
			int(scene.get("established_round", 0)) < 1
			or int(scene.get("established_round", 0)) > round_index
		):
			issues.append("battle scene established round invalid")
	var creation_orders := {}
	for id in source_registry:
		var source: Dictionary = source_registry[id]
		var order := int(source.get("creation_order", 0))
		if order < 1 or order >= next_creation_order or creation_orders.has(order):
			issues.append("battle source creation order is invalid or repeated")
		creation_orders[order] = true
		_validate_instance_sequence(str(id), issues)
	for id in instances:
		if not card_by_id.has(id) and not source_registry.has(id):
			issues.append("battle entity has no source registry entry")
	if outcome != null:
		if (
			outcome.get("battle_id", "") != battle_id
			or outcome.get("result", "") not in ["won", "lost"]
			or int(outcome.get("remaining_vitality", -1)) != int(player.get("vitality", 0))
		):
			issues.append("battle outcome disagrees with state")
	return issues


func _validate_instance(instance_id: String, instances: Dictionary, issues: Array[String]) -> void:
	RunCodec.unique(instance_id, instances, "battle.instance_id", issues)
	_validate_instance_sequence(instance_id, issues)


func _validate_instance_sequence(instance_id: String, issues: Array[String]) -> void:
	var prefix := battle_id + "|"
	var local_id := instance_id.substr(prefix.length())
	var digit_start := 0
	while digit_start < local_id.length() and not local_id[digit_start].is_valid_int():
		digit_start += 1
	var suffix := local_id.substr(digit_start)
	if (
		not instance_id.begins_with(prefix)
		or not suffix.is_valid_int()
		or int(suffix) < 1
		or int(suffix) >= next_instance_seq
	):
		issues.append("battle next_instance_seq would reuse an instance ID")


func _validate_source_order(instance_id: String, order: int, issues: Array[String]) -> void:
	if (
		not source_registry.has(instance_id)
		or int(source_registry[instance_id].get("creation_order", 0)) != order
	):
		issues.append("battle entered_order disagrees with source registry")


static func counter_key(scope: StringName, owner_key: String, trigger_key: StringName) -> String:
	return "%s|%s|%s" % [scope, owner_key, trigger_key]


func to_dictionary() -> Dictionary:
	return {
		"battle_id": battle_id,
		"node_id": node_id,
		"encounter_id": encounter_id,
		"character_id": character_id,
		"difficulty": difficulty,
		"exam_flags": exam_flags.duplicate(),
		"phase": phase,
		"round_index": round_index,
		"ddl": ddl,
		"player": player.duplicate(true),
		"card_by_id": card_by_id.duplicate(true),
		"relics": relics.duplicate(),
		"zones": zones.duplicate(true),
		"units": units.duplicate(true),
		"tasks": tasks.duplicate(true),
		"statuses": statuses.duplicate(true),
		"retained_card_ids": retained_card_ids.duplicate(),
		"scene": scene.duplicate(true) if typeof(scene) == TYPE_DICTIONARY else scene,
		"counters": counters.duplicate(true),
		"resolution":
		resolution.duplicate(true) if typeof(resolution) == TYPE_DICTIONARY else resolution,
		"outcome": outcome.duplicate(true) if typeof(outcome) == TYPE_DICTIONARY else outcome,
		"next_creation_order": next_creation_order,
		"next_instance_seq": next_instance_seq,
		"source_registry": source_registry.duplicate(true),
	}


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) == TYPE_DICTIONARY:
				result.append(item.duplicate(true))
	return result


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) == TYPE_STRING:
				result.append(item)
	return result
