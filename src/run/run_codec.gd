class_name RunCodec
extends RefCounted

## Only this codec translates the run aggregate into persistence records.
const FIELDS := {
	"run_id": TYPE_STRING,
	"character_id": TYPE_STRING,
	"ruleset_id": TYPE_STRING,
	"difficulty": TYPE_STRING,
	"manifest_id": TYPE_STRING,
	"term": TYPE_INT,
	"money": TYPE_INT,
	"vitality": TYPE_INT,
	"max_vitality": TYPE_INT,
	"next_instance_seq": TYPE_INT,
	"cards": TYPE_ARRAY,
	"relics": TYPE_ARRAY,
	"career": TYPE_DICTIONARY,
	"nodes": TYPE_ARRAY,
	"current_node_id": TYPE_STRING,
	"node_path": TYPE_ARRAY,
	"pending_reward": -1,
	"settlement": -1,
	"seen_event_ids": TYPE_ARRAY,
	"settled_battle_ids": TYPE_ARRAY,
	"removals_used": TYPE_INT,
	"career_direction": TYPE_STRING,
	"active_battle_id": TYPE_STRING,
	"active_encounter_id": TYPE_STRING,
	"outcome": TYPE_STRING,
	"awaiting_ending": TYPE_BOOL,
	"ending_draft": TYPE_DICTIONARY,
}
const SUMMARY_FIELDS := {
	"run_id": TYPE_STRING,
	"result": TYPE_STRING,
	"reason": TYPE_STRING,
	"ending_id": TYPE_STRING,
	"character_id": TYPE_STRING,
	"difficulty": TYPE_STRING,
	"manifest_id": TYPE_STRING,
	"term": TYPE_INT,
	"statistics": TYPE_DICTIONARY,
	"unlocked_ids": TYPE_ARRAY,
	"seen_content_ids": TYPE_ARRAY,
}
const CARD_FIELDS := {
	"card_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"upgrade_level": TYPE_INT,
	"acquired_from": TYPE_STRING,
}
const RELIC_FIELDS := {
	"relic_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"slot": TYPE_INT,
	"acquired_order": TYPE_INT,
}
const NODE_FIELDS := {
	"node_id": TYPE_STRING,
	"term": TYPE_INT,
	"layer": TYPE_INT,
	"kind": TYPE_STRING,
	"status": TYPE_STRING,
	"next_ids": TYPE_ARRAY,
	"context": TYPE_DICTIONARY,
}
const EVENT_FIELDS := {
	"event_instance_id": TYPE_STRING,
	"node_id": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"resolved_option_id": TYPE_STRING,
	"frozen_candidates": TYPE_DICTIONARY,
}
const SHOP_FIELDS := {
	"shop_id": TYPE_STRING,
	"node_id": TYPE_STRING,
	"stocks": TYPE_ARRAY,
	"removal_count": TYPE_INT,
}
const STOCK_FIELDS := {
	"stock_id": TYPE_STRING,
	"kind": TYPE_STRING,
	"definition_id": TYPE_STRING,
	"base_price": TYPE_INT,
	"price": TYPE_INT,
	"sold": TYPE_BOOL,
}
const OFFER_FIELDS := {
	"offer_id": TYPE_STRING,
	"source_node_id": TYPE_STRING,
	"items": TYPE_ARRAY,
	"meta": TYPE_DICTIONARY,
}
const ITEM_FIELDS := {
	"item_id": TYPE_STRING,
	"kind": TYPE_STRING,
	"candidates": TYPE_ARRAY,
	"status": TYPE_STRING,
	"chosen_id": TYPE_STRING,
	"skippable": TYPE_BOOL,
}
const CAREER_FIELDS := {
	"research": TYPE_INT,
	"competition": TYPE_INT,
	"internship": TYPE_INT,
	"community": TYPE_INT,
}
const STEP_FIELDS := {
	"step_id": TYPE_STRING,
	"status": TYPE_STRING,
	"candidates": TYPE_ARRAY,
	"skippable": TYPE_BOOL,
	"chosen_id": TYPE_STRING,
}


static func encode(state: RunState) -> GameResult:
	if state == null:
		return corrupt(["run is required"])
	var data := state.to_dictionary()
	var issues := _validate_structure(data)
	if not issues.is_empty():
		return corrupt(issues)
	issues.append_array(state.validate())
	return GameResult.success(data) if issues.is_empty() else corrupt(issues)


static func decode(data: Dictionary, catalog: ContentDB) -> GameResult:
	var record: Dictionary = normalize_numbers(data)
	var issues := _validate_structure(record)
	if not issues.is_empty():
		return corrupt(issues)
	if catalog == null or catalog.get_info() == null:
		return missing(["catalog is not loaded"])
	var info := catalog.get_info()
	if record.manifest_id != info.id or record.ruleset_id != info.ruleset_id:
		return GameResult.failure(
			ApiError.new(GameConstants.ERROR_VERSION_MISMATCH, "save.run.content_mismatch")
		)
	var references: Array[String] = []
	_reference(catalog, "character", record.character_id, "run.character_id", references)
	_reference(catalog, "ruleset", record.ruleset_id, "run.ruleset_id", references)
	for card in record.cards:
		_reference(catalog, "card", card.definition_id, "run.cards", references)
	for relic in record.relics:
		_reference(catalog, "relic", relic.definition_id, "run.relics", references)
	for id in record.seen_event_ids:
		_reference(catalog, "event", id, "run.seen_event_ids", references)
	if not record.active_encounter_id.is_empty():
		_reference(
			catalog, "encounter", record.active_encounter_id, "run.active_encounter_id", references
		)
	for node in record.nodes:
		_validate_context_content(node, catalog, issues, references)
	if record.pending_reward != null:
		_validate_offer_content(record.pending_reward, catalog, references)
	if not references.is_empty():
		return missing(references)
	var rules: Dictionary = catalog.get_definition("ruleset", info.ruleset_id).data
	if not rules.difficulty_overrides.has(record.difficulty):
		issues.append("run.difficulty is unknown")
	if record.term < 1 or record.term > int(rules.run.term_count):
		issues.append("run.term is outside the ruleset")
	for card in record.cards:
		if card.upgrade_level < 0 or card.upgrade_level > int(rules.run.max_card_upgrades):
			issues.append("run.cards upgrade_level exceeds the limit")
	for value in record.career.values():
		if value < 0 or value > int(rules.run.get("career_cap", 3)):
			issues.append("run.career exceeds the limit")
	if not issues.is_empty():
		return corrupt(issues)
	var state := RunState.new(record)
	for node in state.nodes:
		if node.context.has("event"):
			node.context.event = EventState.create(node.context.event)
		if node.context.has("shop"):
			node.context.shop = ShopState.create(node.context.shop)
	if record.pending_reward != null:
		state.pending_reward = RewardOffer.create(record.pending_reward)
	if record.settlement != null:
		state.settlement = TermSettlement.create(record.settlement)
	issues.append_array(state.validate(int(rules.run.relic_slots)))
	return GameResult.success(state) if issues.is_empty() else corrupt(issues)


static func encode_summary(summary: RunSummary) -> Dictionary:
	return {} if summary == null else summary.to_dictionary()


static func decode_summary(data: Dictionary) -> GameResult:
	var record: Dictionary = normalize_numbers(data)
	var issues: Array[String] = []
	shape(record, SUMMARY_FIELDS, "summary", issues)
	if not issues.is_empty():
		return corrupt(issues)
	strings(record.unlocked_ids, "summary.unlocked_ids", issues)
	strings(record.seen_content_ids, "summary.seen_content_ids", issues)
	if record.run_id.is_empty() or record.character_id.is_empty() or record.manifest_id.is_empty():
		issues.append("summary identity is missing")
	if (
		record.result not in ["won", "lost", "abandoned"]
		or record.reason.is_empty()
		or record.term < 1
	):
		issues.append("summary is not finalized")
	for value in record.statistics.values():
		if typeof(value) != TYPE_INT or value < 0:
			issues.append("summary.statistics must contain non-negative integers")
	return GameResult.success(RunSummary.create(record)) if issues.is_empty() else corrupt(issues)


static func _validate_structure(data: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	shape(data, FIELDS, "run", issues)
	if not issues.is_empty():
		return issues
	for key in ["node_path", "seen_event_ids", "settled_battle_ids"]:
		strings(data[key], "run." + key, issues)
	for card in data.cards:
		shape(card, CARD_FIELDS, "run.cards[]", issues)
	for relic in data.relics:
		shape(relic, RELIC_FIELDS, "run.relics[]", issues)
	shape(data.career, CAREER_FIELDS, "run.career", issues)
	for node in data.nodes:
		var before := issues.size()
		shape(node, NODE_FIELDS, "run.nodes[]", issues)
		if issues.size() != before:
			continue
		strings(node.next_ids, "node.next_ids", issues)
		_validate_context(node, issues)
	if data.pending_reward != null:
		_validate_offer(data.pending_reward, issues)
	if data.settlement != null:
		var before := issues.size()
		shape(
			data.settlement,
			{"settlement_id": TYPE_STRING, "term": TYPE_INT, "steps": TYPE_ARRAY},
			"settlement",
			issues
		)
		if before == issues.size():
			var step_ids := {}
			if data.settlement.settlement_id.is_empty() or data.settlement.term != data.term:
				issues.append("settlement identity/term is invalid")
			for step in data.settlement.steps:
				before = issues.size()
				shape(step, STEP_FIELDS, "settlement.steps[]", issues, ["chosen_id"])
				if before != issues.size():
					continue
				strings(step.candidates, "settlement.candidates", issues)
				unique(step.step_id, step_ids, "settlement.step_id", issues)
				if step.status not in ["pending", "claimed", "skipped"]:
					issues.append("settlement step status is invalid")
				if step.status == "claimed" and not step.candidates.has(step.get("chosen_id", "")):
					issues.append("claimed settlement step requires a frozen candidate")
				if step.status != "claimed" and not str(step.get("chosen_id", "")).is_empty():
					issues.append("unclaimed settlement step cannot contain chosen_id")
				if step.status == "skipped" and not step.skippable:
					issues.append("settlement step cannot be skipped")
	shape(
		data.ending_draft,
		{"eligible_endings": TYPE_ARRAY},
		"run.ending_draft",
		issues,
		["eligible_endings"]
	)
	if data.ending_draft.has("eligible_endings"):
		strings(data.ending_draft.eligible_endings, "run.ending_draft.eligible_endings", issues)
	return issues


static func _validate_context(node: Dictionary, issues: Array[String]) -> void:
	var context: Dictionary = node.context
	if context.is_empty():
		if node.status != "pending":
			issues.append("visited node requires context")
		return
	match node.kind:
		"event":
			shape(context, {"event": TYPE_DICTIONARY}, "node.context", issues)
			if typeof(context.get("event")) == TYPE_DICTIONARY:
				var before := issues.size()
				shape(context.event, EVENT_FIELDS, "event", issues)
				if before == issues.size():
					for options in context.event.frozen_candidates.values():
						if options is not Dictionary:
							issues.append("event frozen option must be an object")
							continue
						for candidates in options.values():
							strings(candidates, "event.frozen_candidates", issues)
		"shop":
			shape(context, {"shop": TYPE_DICTIONARY}, "node.context", issues)
			if typeof(context.get("shop")) == TYPE_DICTIONARY:
				var before := issues.size()
				shape(context.shop, SHOP_FIELDS, "shop", issues)
				if before == issues.size():
					for stock in context.shop.stocks:
						shape(stock, STOCK_FIELDS, "shop.stocks[]", issues)
		"rest":
			shape(context, {"used": TYPE_BOOL, "option_id": TYPE_STRING}, "node.context", issues)
		"normal", "elite", "boss":
			shape(
				context, {"encounter_id": TYPE_STRING, "settled": TYPE_BOOL}, "node.context", issues
			)
		_:
			issues.append("node kind is unknown")


static func _validate_offer(offer: Variant, issues: Array[String]) -> void:
	var before := issues.size()
	shape(offer, OFFER_FIELDS, "reward", issues)
	if before != issues.size():
		return
	shape(offer.meta, {"money": TYPE_INT, "kind": TYPE_STRING}, "reward.meta", issues)
	var item_ids := {}
	for item in offer.items:
		before = issues.size()
		shape(item, ITEM_FIELDS, "reward.items[]", issues)
		if before != issues.size():
			continue
		strings(item.candidates, "reward.candidates", issues)
		unique(item.item_id, item_ids, "reward.item_id", issues)
		if (
			item.kind not in ["card", "relic"]
			or item.status not in ["pending", "claimed", "skipped"]
		):
			issues.append("reward kind/status invalid")
		if item.status == "claimed" and not item.candidates.has(item.chosen_id):
			issues.append("claimed reward requires a frozen candidate")
		if item.status != "claimed" and not item.chosen_id.is_empty():
			issues.append("unclaimed reward cannot contain chosen_id")
		if item.status == "skipped" and not item.skippable:
			issues.append("reward item cannot be skipped")


static func _validate_context_content(
	node: Dictionary, catalog: ContentDB, issues: Array[String], refs: Array[String]
) -> void:
	var context: Dictionary = node.context
	if context.is_empty():
		return
	if context.has("encounter_id"):
		_reference(catalog, "encounter", context.encounter_id, "node.encounter_id", refs)
	if context.has("shop"):
		var shop: Dictionary = context.shop
		if shop.node_id != node.node_id or shop.shop_id.is_empty() or shop.removal_count < 0:
			issues.append("shop identity/removal_count invalid")
		var stocks := {}
		for stock in shop.stocks:
			unique(stock.stock_id, stocks, "stock.stock_id", issues)
			if (
				stock.price < 0
				or stock.base_price < 0
				or stock.kind not in ["card", "relic", "meal"]
			):
				issues.append("stock price/kind invalid")
			elif stock.kind != "meal":
				_reference(catalog, stock.kind, stock.definition_id, "shop.stock", refs)
	if not context.has("event"):
		return
	var event: Dictionary = context.event
	_reference(catalog, "event", event.definition_id, "event.definition_id", refs)
	if event.node_id != node.node_id or event.event_instance_id.is_empty():
		issues.append("event identity invalid")
	var found := catalog.get_definition("event", event.definition_id)
	if not found.ok:
		return
	var options := {}
	for option in found.data.options:
		options[option.option_id] = option
	if not event.resolved_option_id.is_empty() and not options.has(event.resolved_option_id):
		issues.append("event resolved option is unknown")
	if event.frozen_candidates.size() != options.size():
		issues.append("event frozen options are incomplete")
	for option_id in event.frozen_candidates:
		if not options.has(option_id):
			issues.append("event frozen option is unknown")
			continue
		var effects: Array = options[option_id].effects
		for index in range(effects.size()):
			if (
				effects[index].op in ["gain_card", "gain_relic"]
				and not event.frozen_candidates[option_id].has(str(index))
			):
				issues.append("event frozen effect candidates are missing")
		for index_key in event.frozen_candidates[option_id]:
			if (
				not str(index_key).is_valid_int()
				or int(index_key) < 0
				or int(index_key) >= effects.size()
			):
				issues.append("event frozen effect index invalid")
				continue
			var effect: Dictionary = effects[int(index_key)]
			var kind := "card" if effect.op == "gain_card" else "relic"
			if effect.op not in ["gain_card", "gain_relic"]:
				issues.append("event frozen candidates do not match effect")
			for id in event.frozen_candidates[option_id][index_key]:
				_reference(catalog, kind, id, "event.frozen_candidates", refs)


static func _validate_offer_content(
	offer: Dictionary, catalog: ContentDB, refs: Array[String]
) -> void:
	for item in offer.items:
		for id in item.candidates:
			_reference(catalog, item.kind, id, "reward.candidates", refs)


## Shared JSON guards run before any typed entity constructor.
static func shape(
	value: Variant, fields: Dictionary, path: String, issues: Array[String], optional: Array = []
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		issues.append(path + " must be an object")
		return
	for key in value:
		if not fields.has(key):
			issues.append("%s.%s is unknown" % [path, key])
	for key in fields:
		if not value.has(key):
			if not optional.has(key):
				issues.append("%s.%s is missing" % [path, key])
		elif fields[key] == -1:
			if value[key] != null and typeof(value[key]) != TYPE_DICTIONARY:
				issues.append("%s.%s must be object or null" % [path, key])
		elif typeof(value[key]) != fields[key]:
			issues.append("%s.%s has wrong type" % [path, key])


static func strings(value: Variant, path: String, issues: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		issues.append(path + " must be an array")
		return
	var seen := {}
	for id in value:
		if typeof(id) != TYPE_STRING:
			issues.append(path + " must contain strings")
		else:
			unique(id, seen, path, issues)


static func unique(id: String, seen: Dictionary, path: String, issues: Array[String]) -> void:
	if id.is_empty() or seen.has(id):
		issues.append(path + " must be nonempty and unique: " + id)
	seen[id] = true


static func json_tree(value: Variant, path: String, issues: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if typeof(key) != TYPE_STRING:
				issues.append(path + " keys must be strings")
			json_tree(value[key], path + "." + str(key), issues)
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			json_tree(item, path + "[]", issues)
	elif typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]:
		issues.append(path + " must contain JSON primitive values with integer numbers")


static func normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = normalize_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize_numbers(item))
		return result
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(value)
		and value == floor(value)
		and absf(value) <= 9007199254740991.0
	):
		return int(value)
	return value


static func _reference(
	catalog: ContentDB, kind: String, id: String, path: String, issues: Array[String]
) -> void:
	if not catalog.get_definition(kind, id).ok:
		issues.append("%s references disabled/missing %s/%s" % [path, kind, id])


static func corrupt(issues: Array) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_SAVE_CORRUPT, "save.domain.invalid", {"issues": issues})
	)


static func missing(issues: Array) -> GameResult:
	return GameResult.failure(
		ApiError.new(
			GameConstants.ERROR_CONTENT_INVALID, "save.domain.content_missing", {"issues": issues}
		)
	)
