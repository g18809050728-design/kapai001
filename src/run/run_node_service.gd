class_name RunNodeService
extends RefCounted

var _catalog: ContentDB


func _init(content_db: ContentDB = null) -> void:
	_catalog = content_db


func enter_event(state: RunState, node: RunNodeState, rng: RandomSource) -> GameResult:
	var pool := _catalog.get_candidates({"kind": "event", "terms": state.term})
	pool = pool.filter(func(id): return not state.seen_event_ids.has(id))
	if pool.is_empty():
		return GameResult.success(null)
	var chosen := rng.draw_int("map", 0, pool.size() - 1)
	if not chosen.ok:
		return chosen
	var definition_result := _catalog.get_definition("event", pool[chosen.data])
	if not definition_result.ok:
		return definition_result
	var definition: Dictionary = definition_result.data
	var frozen := {}
	for option in definition.options:
		var option_candidates := {}
		for index in range(option.effects.size()):
			var effect: Dictionary = option.effects[index]
			if effect.op == "gain_card":
				var ids: Array[String] = []
				if effect.has("card_id"):
					ids.append(effect.card_id)
				elif effect.has("card_pool"):
					for id in effect.card_pool:
						if _catalog.get_definition("card", id).ok:
							ids.append(id)
				else:
					ids = _draw_candidates("card", effect.rarity, effect.candidate_count, [], rng)
				option_candidates[str(index)] = ids
			elif effect.op == "gain_relic":
				var held: Array[String] = []
				for relic in state.relics:
					held.append(relic.definition_id)
				var ids: Array[String] = []
				if effect.has("relic_id"):
					if not held.has(effect.relic_id):
						ids.append(effect.relic_id)
				else:
					ids = _draw_candidates("relic", effect.rarity, effect.count, held, rng)
				option_candidates[str(index)] = ids
		frozen[option.option_id] = option_candidates
	state.seen_event_ids.append(definition.id)
	return (
		GameResult
		. success(
			(
				EventState
				. create(
					{
						"event_instance_id": state.next_instance_id("event"),
						"node_id": node.node_id,
						"definition_id": definition.id,
						"frozen_candidates": frozen,
					}
				)
			)
		)
	)


func choose_event(state: RunState, payload: Dictionary) -> GameResult:
	var work := state.copy_for_write()
	var node := work.find_node(work.current_node_id)
	if node == null or node.kind != "event" or node.status != "active":
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.event.not_active")
	var event := _event(node)
	if event == null:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.event.state_missing")
	if not event.resolved_option_id.is_empty():
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.event.resolved")
	if payload.get("event_instance_id", "") != event.event_instance_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.instance_invalid")
	var definition_result := _catalog.get_definition("event", event.definition_id)
	if not definition_result.ok:
		return definition_result
	var selected_option: Dictionary = {}
	for option in definition_result.data.options:
		if option.option_id == payload.get("option_id", ""):
			selected_option = option
			break
	if selected_option.is_empty():
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.option_invalid")
	var cost: Dictionary = selected_option.cost
	if work.money < int(cost.get("money", 0)) or work.vitality - int(cost.get("vitality", 0)) < 1:
		return _error(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "run.event.cannot_pay")
	if typeof(payload.get("selection_ids", [])) != TYPE_ARRAY:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.event.selections_invalid")
	var targets: Array = payload.get("selection_ids", []).duplicate()
	var replace_id := str(payload.get("replace_relic_id", ""))
	work.money -= int(cost.get("money", 0))
	work.vitality -= int(cost.get("vitality", 0))
	for index in range(selected_option.effects.size()):
		var effect: Dictionary = selected_option.effects[index]
		var candidates: Array = event.frozen_candidates.get(selected_option.option_id, {}).get(
			str(index), []
		)
		var applied := _apply_event_effect(
			work, effect, candidates, targets, replace_id, event.event_instance_id
		)
		if not applied.ok:
			return applied
	if not targets.is_empty():
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.extra_selections")
	event.resolved_option_id = selected_option.option_id
	node.context.event = event
	return GameResult.success(work)


func take_rest(state: RunState, payload: Dictionary) -> GameResult:
	var work := state.copy_for_write()
	var node := work.find_node(work.current_node_id)
	if node == null or node.kind != "rest" or node.status != "active":
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.rest.not_active")
	if payload.get("node_id", "") != node.node_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.rest.node_invalid")
	if node.context.get("used", false):
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.rest.used")
	var option := str(payload.get("option_id", ""))
	var rules := _rules(work)
	if option == "heal":
		work.vitality = mini(
			work.max_vitality,
			work.vitality + int(floor(work.max_vitality * int(rules.run.rest_heal_percent) / 100.0))
		)
	elif option in ["upgrade", "train", "remove_burden"]:
		var card_id := str(payload.get("card_instance_id", ""))
		var card := _card(work, card_id)
		if card.is_empty():
			return _error(GameConstants.ERROR_INVALID_TARGET, "run.rest.card_invalid")
		var definition_result := _catalog.get_definition("card", card.definition_id)
		if not definition_result.ok:
			return definition_result
		var definition: Dictionary = definition_result.data
		if option == "remove_burden":
			if not definition.get("tags", []).has("burden"):
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.rest.not_burden")
			if work.cards.size() <= int(rules.run.minimum_deck_size):
				return _error(GameConstants.ERROR_LIMIT_REACHED, "run.deck.minimum")
			work.cards.erase(card)
		else:
			if option == "train" and definition.type != "cooperation":
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.rest.not_cooperation")
			if int(card.get("upgrade_level", 0)) >= int(rules.run.max_card_upgrades):
				return _error(GameConstants.ERROR_LIMIT_REACHED, "run.card.upgrade_limit")
			if not definition.has("upgrade"):
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.card.no_upgrade")
			card.upgrade_level = int(card.get("upgrade_level", 0)) + 1
	else:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.rest.option_invalid")
	node.context.used = true
	node.context.option_id = option
	return GameResult.success(work)


func event_view(state: RunState, node: RunNodeState) -> Dictionary:
	var event := _event(node)
	if event == null:
		return {}
	var result := event.to_dictionary()
	var options: Array[Dictionary] = []
	var definition_result := _catalog.get_definition("event", event.definition_id)
	if not definition_result.ok:
		return result
	for option in definition_result.data.options:
		var blocking: Array[Dictionary] = []
		if not event.resolved_option_id.is_empty():
			blocking.append({"code": "ALREADY_RESOLVED", "message_key": "run.event.resolved"})
		elif (
			state.money < int(option.cost.get("money", 0))
			or state.vitality - int(option.cost.get("vitality", 0)) < 1
		):
			blocking.append(
				{"code": "INSUFFICIENT_RESOURCE", "message_key": "run.event.cannot_pay"}
			)
		for effect in option.effects:
			if (
				effect.op in ["upgrade_card", "remove_card"]
				and _eligible_cards(state, effect).is_empty()
			):
				blocking.append({"code": "INVALID_TARGET", "message_key": "run.event.no_target"})
		options.append(
			{
				"option_id": option.option_id,
				"label_key": option.label_key,
				"cost": option.cost.duplicate(true),
				"effects": option.effects.duplicate(true),
				"candidates": event.frozen_candidates.get(option.option_id, {}).duplicate(true),
				"enabled": blocking.is_empty(),
				"blocking": blocking
			}
		)
	result.options = options
	return result


func rest_view(state: RunState, node: RunNodeState) -> Dictionary:
	var rules := _rules(state)
	var options: Array[Dictionary] = []
	for option in ["heal", "upgrade", "remove_burden", "train"]:
		var blocking: Array[Dictionary] = []
		var eligible: Array[String] = []
		if node.context.get("used", false):
			blocking.append({"code": "ALREADY_RESOLVED", "message_key": "run.rest.used"})
		elif option != "heal":
			for card in state.cards:
				var preview := take_rest(
					state,
					{"node_id": node.node_id, "option_id": option, "card_instance_id": card.card_id}
				)
				if preview.ok:
					eligible.append(card.card_id)
			if eligible.is_empty():
				blocking.append({"code": "INVALID_TARGET", "message_key": "run.rest.no_target"})
		options.append(
			{
				"option_id": option,
				"enabled": blocking.is_empty(),
				"blocking": blocking,
				"needs_card": option != "heal",
				"eligible_card_ids": eligible
			}
		)
	return {
		"node_id": node.node_id,
		"used": node.context.get("used", false),
		"options": options,
		"heal_amount": int(floor(state.max_vitality * int(rules.run.rest_heal_percent) / 100.0))
	}


func _apply_event_effect(
	state: RunState,
	effect: Dictionary,
	candidates: Array,
	targets: Array,
	replace_id: String,
	source: String
) -> GameResult:
	match str(effect.op):
		"gain_money":
			state.money += int(effect.amount)
		"heal":
			state.vitality = mini(state.max_vitality, state.vitality + int(effect.amount))
		"lose_vitality":
			state.vitality = maxi(0, state.vitality - int(effect.amount))
		"gain_card":
			if candidates.is_empty():
				state.money += int(effect.get("fallback_money", 0))
				return GameResult.success(true)
			var selected := str(candidates[0])
			if (
				not effect.has("card_id")
				and (
					candidates.size() > 1 or (not targets.is_empty() and candidates.has(targets[0]))
				)
			):
				if targets.is_empty():
					return _error(
						GameConstants.ERROR_INVALID_TARGET, "run.event.selection_required"
					)
				selected = str(targets.pop_front())
			if not candidates.has(selected):
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.candidate_invalid")
			if not _catalog.get_definition("card", selected).ok:
				return _error(GameConstants.ERROR_CONTENT_INVALID, "run.event.card_unknown")
			state.cards.append(
				{
					"card_id": state.next_instance_id("card"),
					"definition_id": selected,
					"upgrade_level": 0,
					"acquired_from": source
				}
			)
		"gain_relic":
			state.money += (
				maxi(0, int(effect.get("count", 1)) - candidates.size())
				* int(effect.fallback_money)
			)
			for id in candidates:
				var grant := _grant_relic(
					state, str(id), replace_id, source, int(effect.fallback_money)
				)
				if not grant.ok:
					return grant
		"upgrade_card", "remove_card":
			if targets.is_empty():
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.selection_required")
			var id := str(targets.pop_front())
			if not _eligible_cards(state, effect).has(id):
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.event.card_target_invalid")
			var card := _card(state, id)
			if effect.op == "upgrade_card":
				card.upgrade_level = int(card.get("upgrade_level", 0)) + 1
			else:
				state.cards.erase(card)
		"career":
			var rules := _rules(state)
			if int(rules.run.term_count) == 1:
				return _error(GameConstants.ERROR_CONTENT_INVALID, "run.event.career_outside_mvp")
			state.career[effect.track] = mini(
				int(rules.run.get("career_cap", 3)),
				int(state.career.get(effect.track, 0)) + int(effect.amount)
			)
		_:
			return _error(GameConstants.ERROR_CONTENT_INVALID, "run.event.unknown_op")
	return GameResult.success(true)


func _draw_candidates(
	kind: String, rarity: String, count: int, excluded: Array[String], rng: RandomSource
) -> Array[String]:
	var pool := _catalog.get_candidates({"kind": kind, "rarity": rarity, "exclude_ids": excluded})
	pool = pool.filter(
		func(id):
			var definition: Dictionary = _catalog.get_definition(kind, id).data
			if kind == "card":
				return (
					not definition.get("tags", []).has("basic")
					and not definition.get("tags", []).has("special")
				)
			return definition.get("availability") != "starter"
	)
	var result: Array[String] = []
	for _index in range(mini(count, pool.size())):
		var draw := rng.draw_int("reward", 0, pool.size() - 1)
		if not draw.ok:
			break
		result.append(pool[draw.data])
		pool.remove_at(draw.data)
	return result


func _grant_relic(
	state: RunState, definition_id: String, replace_id: String, source: String, fallback_money: int
) -> GameResult:
	if not _catalog.get_definition("relic", definition_id).ok:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.event.relic_unknown")
	for relic in state.relics:
		if relic.definition_id == definition_id:
			state.money += fallback_money
			return GameResult.success(true)
	var slots := int(_rules(state).run.relic_slots)
	var slot := -1
	if state.relics.size() >= slots:
		for relic in state.relics:
			if relic.relic_id == replace_id:
				slot = int(relic.slot)
				state.relics.erase(relic)
				break
		if slot == -1:
			return _error(GameConstants.ERROR_LIMIT_REACHED, "run.relic.replacement_required")
	else:
		var occupied: Array = state.relics.map(func(relic): return int(relic.slot))
		for index in range(slots):
			if not occupied.has(index):
				slot = index
				break
	var order := state.next_instance_seq
	state.relics.append(
		{
			"relic_id": state.next_instance_id("relic"),
			"definition_id": definition_id,
			"slot": slot,
			"acquired_order": order,
			"acquired_from": source
		}
	)
	return GameResult.success(true)


func _eligible_cards(state: RunState, effect: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var rules := _rules(state)
	if effect.op == "remove_card" and state.cards.size() <= int(rules.run.minimum_deck_size):
		return result
	for card in state.cards:
		var definition_result := _catalog.get_definition("card", card.definition_id)
		if not definition_result.ok:
			continue
		var definition: Dictionary = definition_result.data
		if effect.op == "upgrade_card":
			if (
				int(card.get("upgrade_level", 0)) >= int(rules.run.max_card_upgrades)
				or not definition.has("upgrade")
			):
				continue
			if effect.has("type_filter") and definition.type != effect.type_filter:
				continue
		elif effect.has("tag_filter") and not definition.get("tags", []).has(effect.tag_filter):
			continue
		result.append(card.card_id)
	return result


func _event(node: RunNodeState) -> EventState:
	var value: Variant = node.context.get("event")
	if value is EventState:
		return value
	if value is Dictionary:
		return EventState.create(value)
	return null


func _card(state: RunState, id: String) -> Dictionary:
	for card in state.cards:
		if card.card_id == id:
			return card
	return {}


func _rules(state: RunState) -> Dictionary:
	var result := _catalog.get_definition("ruleset", state.ruleset_id)
	return result.data if result.ok else {}


func _error(code: StringName, key: String) -> GameResult:
	return GameResult.failure(ApiError.new(code, key))
