class_name RunState
extends RefCounted

var run_id: String
var character_id: String
var ruleset_id: String
var difficulty: String
var manifest_id: String
var term: int
var money: int
var vitality: int
var max_vitality: int
var next_instance_seq: int
var cards: Array[Dictionary]
var relics: Array[Dictionary]
var career: Dictionary
var nodes: Array[RunNodeState] = []
var current_node_id: String
var node_path: Array[String] = []
var pending_reward: Variant
var settlement: Variant
var seen_event_ids: Array[String] = []
var settled_battle_ids: Array[String] = []
var removals_used: int
var career_direction: String
var active_battle_id: String
var active_encounter_id: String
var outcome: String
var awaiting_ending: bool
var ending_draft: Dictionary


func _init(values: Dictionary = {}) -> void:
	run_id = values.get("run_id", "")
	character_id = values.get("character_id", "")
	ruleset_id = values.get("ruleset_id", "")
	difficulty = values.get("difficulty", "normal")
	manifest_id = values.get("manifest_id", "")
	term = values.get("term", 1)
	money = values.get("money", 0)
	vitality = values.get("vitality", 0)
	max_vitality = values.get("max_vitality", 0)
	next_instance_seq = values.get("next_instance_seq", 1)
	cards = _dictionary_array(values.get("cards", []))
	relics = _dictionary_array(values.get("relics", []))
	career = values.get("career", {}).duplicate(true)
	for value in values.get("nodes", []):
		nodes.append(
			value.copy_for_write() if value is RunNodeState else RunNodeState.create(value)
		)
	current_node_id = values.get("current_node_id", "")
	for id in values.get("node_path", []):
		node_path.append(str(id))
	pending_reward = values.get("pending_reward")
	if pending_reward != null:
		pending_reward = (
			pending_reward.copy_for_write()
			if pending_reward is Object
			else pending_reward.duplicate(true)
		)
	settlement = values.get("settlement")
	if settlement != null:
		settlement = (
			settlement.copy_for_write() if settlement is Object else settlement.duplicate(true)
		)
	for id in values.get("seen_event_ids", []):
		seen_event_ids.append(str(id))
	for id in values.get("settled_battle_ids", []):
		settled_battle_ids.append(str(id))
	removals_used = values.get("removals_used", 0)
	career_direction = values.get("career_direction", "")
	active_battle_id = values.get("active_battle_id", "")
	active_encounter_id = values.get("active_encounter_id", "")
	outcome = values.get("outcome", "")
	awaiting_ending = values.get("awaiting_ending", false)
	ending_draft = values.get("ending_draft", {}).duplicate(true)


func copy() -> RunState:
	return copy_for_write()


func copy_for_write() -> RunState:
	var result := RunState.new(to_dictionary())
	result.nodes.clear()
	for node in nodes:
		result.nodes.append(node.copy_for_write())
	result.pending_reward = (
		pending_reward.copy_for_write() if pending_reward is Object else result.pending_reward
	)
	result.settlement = settlement.copy_for_write() if settlement is Object else result.settlement
	return result


func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"character_id": character_id,
		"ruleset_id": ruleset_id,
		"difficulty": difficulty,
		"manifest_id": manifest_id,
		"term": term,
		"money": money,
		"vitality": vitality,
		"max_vitality": max_vitality,
		"next_instance_seq": next_instance_seq,
		"cards": cards.duplicate(true),
		"relics": relics.duplicate(true),
		"career": career.duplicate(true),
		"nodes": nodes.map(func(node): return node.to_dictionary()),
		"current_node_id": current_node_id,
		"node_path": node_path.duplicate(),
		"pending_reward":
		pending_reward.to_dictionary() if pending_reward is Object else pending_reward,
		"settlement": settlement.to_dictionary() if settlement is Object else settlement,
		"seen_event_ids": seen_event_ids.duplicate(),
		"settled_battle_ids": settled_battle_ids.duplicate(),
		"removals_used": removals_used,
		"career_direction": career_direction,
		"active_battle_id": active_battle_id,
		"active_encounter_id": active_encounter_id,
		"outcome": outcome,
		"awaiting_ending": awaiting_ending,
		"ending_draft": ending_draft.duplicate(true),
	}


func find_node(node_id: String) -> RunNodeState:
	for node in nodes:
		if node.node_id == node_id:
			return node
	return null


func reachable_node_ids() -> Array[String]:
	var result: Array[String] = []
	if not outcome.is_empty() or awaiting_ending or settlement != null:
		return result
	if current_node_id.is_empty():
		for node in nodes:
			if node.term == term and node.layer == 1 and node.status == "pending":
				result.append(node.node_id)
		return result
	var node := find_node(current_node_id)
	if node != null and node.status == "completed":
		return node.next_ids.duplicate()
	return result


func next_instance_id(prefix: String) -> String:
	var instance_id := "%s_%06d" % [prefix, next_instance_seq]
	next_instance_seq += 1
	return instance_id


func validate(relic_slots: int = 2147483647) -> Array[String]:
	var issues: Array[String] = []
	if (
		run_id.is_empty()
		or character_id.is_empty()
		or manifest_id.is_empty()
		or ruleset_id.is_empty()
	):
		issues.append("run identity is missing")
	if term < 1 or money < 0 or vitality < 0 or max_vitality < 1 or vitality > max_vitality:
		issues.append("run resources are outside bounds")
	if next_instance_seq < 1 or removals_used < 0:
		issues.append("run sequence/removal counter is invalid")
	if outcome not in ["", "won", "lost", "abandoned"]:
		issues.append("run outcome is unknown")
	if awaiting_ending and (not outcome.is_empty() or ending_draft.is_empty()):
		issues.append("run awaiting ending state is invalid")
	var instance_ids := {}
	var relic_definitions := {}
	var occupied_slots := {}
	for card in cards:
		RunCodec.unique(str(card.get("card_id", "")), instance_ids, "run.card_id", issues)
		_validate_instance_sequence(str(card.get("card_id", "")), issues)
	for relic in relics:
		RunCodec.unique(str(relic.get("relic_id", "")), instance_ids, "run.relic_id", issues)
		RunCodec.unique(
			str(relic.get("definition_id", "")), relic_definitions, "run.relic.definition", issues
		)
		_validate_instance_sequence(str(relic.get("relic_id", "")), issues)
		var slot := int(relic.get("slot", -1))
		if slot < 0 or slot >= relic_slots or occupied_slots.has(slot):
			issues.append("run relic slot is invalid or repeated")
		occupied_slots[slot] = true
		if (
			int(relic.get("acquired_order", 0)) < 1
			or int(relic.get("acquired_order", 0)) >= next_instance_seq
		):
			issues.append("run relic acquired_order is invalid")
	if relics.size() > relic_slots:
		issues.append("run relic capacity exceeded")
	var node_ids := {}
	var max_term := 1
	for node in nodes:
		RunCodec.unique(node.node_id, node_ids, "run.node_id", issues)
		max_term = maxi(max_term, node.term)
	if max_term > 8 or nodes.is_empty():
		issues.append("run map term count is invalid")
		return issues
	var expected := RunMap.build(run_id, max_term)
	if nodes.size() != expected.size():
		issues.append("run map is incomplete")
	for template in expected:
		var node := find_node(template.node_id)
		if node == null:
			issues.append("run map is missing a frozen node")
			continue
		if (
			node.term != template.term
			or node.layer != template.layer
			or node.next_ids != template.next_ids
		):
			issues.append("run node topology is invalid")
		if node.kind != template.kind and not (template.kind == "event" and node.kind == "normal"):
			issues.append("run node kind is invalid")
		if node.status not in ["pending", "active", "completed"]:
			issues.append("run node status is invalid")
		if node.status == "active" and node.node_id != current_node_id:
			issues.append("run has an unexpected active node")
		if (node.status == "completed") != node_path.has(node.node_id):
			issues.append("run completed-node marker disagrees with path")
		if node.status == "pending" and not node.context.is_empty():
			issues.append("pending node cannot contain visited context")
		if node.context.has("event"):
			var event: Variant = node.context.event
			var event_id := str(event.get("event_instance_id"))
			RunCodec.unique(event_id, instance_ids, "event.instance_id", issues)
			_validate_instance_sequence(event_id, issues)
			if not seen_event_ids.has(str(event.get("definition_id"))):
				issues.append("visited event has no seen marker")
			if node.status == "completed" and str(event.get("resolved_option_id")).is_empty():
				issues.append("completed event has no resolved option")
		if node.kind == "rest" and not node.context.is_empty():
			var used := bool(node.context.get("used", false))
			var option := str(node.context.get("option_id", ""))
			if (
				(used and option not in ["heal", "upgrade", "train", "remove_burden"])
				or (not used and not option.is_empty())
			):
				issues.append("rest usage and selected option disagree")
			if node.status == "completed" and not used:
				issues.append("completed rest has no usage marker")
		if node.context.get("settled", false) != settled_battle_ids.has(node.node_id):
			issues.append("run settled battle marker disagrees with node")
		if (
			node.status == "completed"
			and node.kind in ["normal", "elite", "boss"]
			and not node.context.get("settled", false)
		):
			issues.append("completed battle node is unsettled")
	var previous: RunNodeState = null
	for id in node_path:
		var node := find_node(id)
		if node == null:
			issues.append("run path references missing node")
			continue
		if previous == null and (node.term != 1 or node.layer != 1):
			issues.append("run path must start at the first layer")
		elif previous != null and not previous.next_ids.has(id):
			if not (previous.kind == "boss" and node.term == previous.term + 1 and node.layer == 1):
				issues.append("run path contains an illegal edge")
		previous = node
	var current := find_node(current_node_id)
	if current_node_id.is_empty():
		if not node_path.is_empty():
			issues.append("run path requires a current node")
	elif current == null or current.status == "pending":
		issues.append("run current node is missing or unvisited")
	elif current.status == "active":
		if previous != null and not previous.next_ids.has(current.node_id):
			if not (
				previous.kind == "boss" and current.term == previous.term + 1 and current.layer == 1
			):
				issues.append("run active node is unreachable from path")
		elif previous == null and current.layer != 1:
			issues.append("run active node skips the first layer")
	elif previous == null or previous.node_id != current.node_id:
		issues.append("run current node disagrees with path tail")
	if active_battle_id.is_empty() != active_encounter_id.is_empty():
		issues.append("run active battle/encounter must be paired")
	if not active_battle_id.is_empty():
		if (
			current == null
			or active_battle_id != current_node_id
			or settled_battle_ids.has(active_battle_id)
		):
			issues.append("run active battle is invalid or already settled")
		elif (
			current.status != "active"
			or current.kind not in ["normal", "elite", "boss"]
			or str(current.context.get("encounter_id", "")) != active_encounter_id
		):
			issues.append("run active battle disagrees with current node")
	elif (
		current != null
		and current.status == "active"
		and current.kind in ["normal", "elite", "boss"]
		and not current.context.get("settled", false)
	):
		issues.append("unsettled battle node requires an active battle")
	for id in settled_battle_ids:
		if find_node(id) == null:
			issues.append("settled battle references missing node")
	if pending_reward != null:
		var source_id := str(pending_reward.get("source_node_id"))
		if source_id != current_node_id or not settled_battle_ids.has(source_id):
			issues.append("run reward has no matching settled battle")
	return issues


func _validate_instance_sequence(instance_id: String, issues: Array[String]) -> void:
	var suffix := instance_id.get_slice("_", instance_id.get_slice_count("_") - 1)
	if not suffix.is_valid_int() or int(suffix) < 1 or int(suffix) >= next_instance_seq:
		issues.append("run next_instance_seq would reuse an instance ID")


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) == TYPE_DICTIONARY:
				result.append(item.duplicate(true))
	return result
