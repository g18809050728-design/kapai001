class_name RunService
extends RefCounted

var _catalog: ContentDB
var _reward_generator: RewardGenerator
var _transaction_resolver: TransactionResolver
var _node_service: RunNodeService
var _card_rules: BattleCardRules

const ACTION_KEYS := {
	"enter_node": ["node_id"],
	"claim_reward": ["offer_id", "item_id", "candidate_id", "replace_relic_id"],
	"skip_reward": ["offer_id", "item_id"],
	"buy_item": ["shop_id", "stock_id", "replace_relic_id"],
	"remove_card": ["shop_id", "card_instance_id"],
	"choose_event": ["event_instance_id", "option_id", "selection_ids", "replace_relic_id"],
	"take_rest": ["node_id", "option_id", "card_instance_id"],
	"leave_node": ["node_id"],
	"choose_term_option": ["settlement_id", "step_id", "option_id", "candidate_id"],
	"choose_ending": ["ending_id"],
	"abandon_run": ["confirmed"],
}


func _init(catalog: ContentDB = null) -> void:
	set_catalog(catalog)


func set_catalog(catalog: ContentDB) -> void:
	_catalog = catalog
	_reward_generator = RewardGenerator.new(catalog)
	_transaction_resolver = TransactionResolver.new(catalog)
	_node_service = RunNodeService.new(catalog)
	_card_rules = BattleCardRules.new(catalog)


func rewards() -> RewardGenerator:
	return _reward_generator


func transactions() -> TransactionResolver:
	return _transaction_resolver


func create(request: Variant, profile: Variant = {}) -> GameResult:
	if _catalog == null or _catalog.get_info() == null:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.catalog.missing")
	var seed: Variant = _read(request, "seed", null)
	if not seed is String or not _decimal_seed(seed):
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.seed.invalid")
	var info := _catalog.get_info()
	if str(_read(request, "manifest_id", "")) != info.id:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.manifest.mismatch")
	var rules_result := _catalog.get_definition("ruleset", info.ruleset_id)
	if not rules_result.ok:
		return rules_result
	var rules: Dictionary = rules_result.data
	var difficulty := str(_read(request, "difficulty", "normal"))
	if not rules.difficulty_overrides.has(difficulty):
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.difficulty.invalid")
	var character_id := str(_read(request, "character_id", ""))
	var character_result := _catalog.get_definition("character", character_id)
	if not character_result.ok:
		return character_result
	var unlocked: Variant = _read(profile, "unlocked_ids", [])
	if unlocked is Array and not unlocked.is_empty() and not unlocked.has(character_id):
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.character.locked")
	var character: Dictionary = character_result.data
	var vitality := int(
		rules.difficulty_overrides[difficulty].get("starting_vitality", rules.run.starting_vitality)
	)
	var run := (
		RunState
		. new(
			{
				"run_id": "run_%s" % Crypto.new().generate_random_bytes(12).hex_encode(),
				"character_id": character_id,
				"ruleset_id": info.ruleset_id,
				"difficulty": difficulty,
				"manifest_id": info.id,
				"vitality": vitality,
				"max_vitality": vitality,
				"money": int(rules.run.starting_money),
				"career": {"research": 0, "competition": 0, "internship": 0, "community": 0},
			}
		)
	)
	var starter: Array = rules.run.common_starter_cards.duplicate()
	starter.append_array(character.starter_cards)
	if starter.size() != int(rules.run.starter_deck_size):
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.starter.size")
	for definition_id in starter:
		_transaction_resolver.add_card(run, str(definition_id), "starter")
	_transaction_resolver.add_relic(run, str(character.starter_relic_id), "", 0)
	run.nodes = RunMap.build(run.run_id, int(rules.run.term_count))
	var rng := RandomSource.new(seed)
	var events: Array[RuleEvent] = []
	return GameResult.success(
		RunStep.new(run, events, null, null, rng.export_state().to_dictionary())
	)


func preview(state: RunState, draft: Variant) -> GameResult:
	var result := ActionPreview.new()
	result.revision = 0
	var type := str(_read(draft, "type", ""))
	var payload: Variant = _read(draft, "payload", null)
	var format_result := _validate_action(type, payload)
	if not format_result.ok:
		return format_result
	payload = _clean_payload(payload)
	var gate := _gate(state, type)
	if not gate.ok:
		result.blocking_errors.append(gate.error)
		return GameResult.success(result)
	_preview_details(state, type, payload, result)
	var checked: GameResult
	match type:
		"buy_item", "remove_card":
			checked = _transaction_resolver.prepare(
				state, ActionDraft.new(StringName(type), payload)
			)
			if checked.ok:
				result.costs = {"money": int(checked.data.price)}
		"choose_event":
			checked = _node_service.choose_event(state, payload)
		"take_rest":
			checked = _node_service.take_rest(state, payload)
		"claim_reward", "skip_reward":
			checked = _claim_reward(state.copy_for_write(), type, payload)
		"leave_node":
			checked = _can_leave(state, payload)
		"enter_node":
			checked = _can_enter(state, payload)
		"abandon_run":
			checked = (
				GameResult.success(true)
				if payload.get("confirmed") == true
				else _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.abandon.confirmation")
			)
		"choose_term_option":
			checked = _choose_term(state.copy_for_write(), payload)
		"choose_ending":
			checked = _choose_ending(state.copy_for_write(), payload)
		_:
			checked = _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.action.unknown")
	if not checked.ok:
		result.blocking_errors.append(checked.error)
	result.can_submit = result.blocking_errors.is_empty()
	return GameResult.success(result)


func apply(state: RunState, action: Variant, rng_states: Dictionary) -> GameResult:
	var type := str(_read(action, "type", ""))
	var payload: Variant = _read(action, "payload", null)
	var format_result := _validate_action(type, payload)
	if not format_result.ok:
		return format_result
	payload = _clean_payload(payload)
	var gate := _gate(state, type)
	if not gate.ok:
		return gate
	var rng := RandomSource.new()
	var restored := _restore_rng(rng, rng_states)
	if not restored.ok:
		return restored
	var work := state.copy_for_write()
	var events: Array[RuleEvent] = []
	var input: Variant = null
	var summary: RunSummary = null
	var applied: GameResult
	match type:
		"enter_node":
			applied = _enter_node(work, payload, rng, events)
			if applied.ok:
				input = applied.data
		"claim_reward", "skip_reward":
			applied = _claim_reward(work, type, payload)
		"buy_item", "remove_card":
			var prepared := _transaction_resolver.prepare(
				work, GameAction.new(StringName(type), payload)
			)
			if not prepared.ok:
				return prepared
			applied = _transaction_resolver.apply(work, prepared.data)
			if applied.ok:
				work = applied.data
		"choose_event":
			applied = _node_service.choose_event(work, payload)
			if applied.ok:
				work = applied.data
		"take_rest":
			applied = _node_service.take_rest(work, payload)
			if applied.ok:
				work = applied.data
		"leave_node":
			applied = _leave_node(work, payload, rng)
		"choose_term_option":
			applied = _choose_term(work, payload)
		"choose_ending":
			applied = _choose_ending(work, payload)
			if applied.ok:
				summary = _finalize(work, "won", "graduated", str(payload.get("ending_id", "")))
		"abandon_run":
			if payload.get("confirmed") != true:
				return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.abandon.confirmation")
			applied = GameResult.success(true)
			summary = _finalize(work, "abandoned", "player_abandoned")
		_:
			return _error(
				GameConstants.ERROR_INVALID_ARGUMENT, "run.action.unknown", {"type": type}
			)
	if not applied.ok:
		return applied
	if work.vitality <= 0 and work.outcome.is_empty():
		summary = _finalize(work, "lost", "vitality_depleted")
	_action_events(state, work, type, payload, events)
	if summary != null:
		_event(
			events,
			"run_finished",
			work.run_id,
			{"result": work.outcome, "reason": summary.reason, "ending_id": summary.ending_id}
		)
	var snapshot := rng.export_state().to_dictionary()
	if input is Dictionary:
		input.rng_state = snapshot.duplicate(true)
	return GameResult.success(RunStep.new(work, events, input, summary, snapshot))


func settle_battle(state: RunState, outcome: Dictionary, rng_states: Dictionary) -> GameResult:
	var battle_id := str(outcome.get("battle_id", ""))
	if state.settled_battle_ids.has(battle_id):
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.battle.settled")
	if not state.outcome.is_empty() or state.active_battle_id.is_empty():
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.battle.inactive")
	if battle_id != state.active_battle_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.battle.invalid")
	if (
		outcome.get("result", "") not in ["won", "lost"]
		or not outcome.get("remaining_vitality") is int
	):
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.battle.outcome.invalid")
	var vitality := int(outcome.remaining_vitality)
	if vitality < 0 or vitality > state.max_vitality:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.battle.vitality.invalid")
	var rng := RandomSource.new()
	var restored := _restore_rng(rng, rng_states)
	if not restored.ok:
		return restored
	var work := state.copy_for_write()
	var node := work.find_node(work.current_node_id)
	if node == null or node.node_id != battle_id or node.status != "active":
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.battle.node.invalid")
	work.vitality = vitality
	work.settled_battle_ids.append(battle_id)
	work.active_battle_id = ""
	work.active_encounter_id = ""
	node.context.settled = true
	var events: Array[RuleEvent] = []
	var summary: RunSummary = null
	if outcome.result == "lost" or vitality == 0:
		summary = _finalize(work, "lost", str(outcome.get("reason", "battle_lost")))
	elif node.kind == "boss" and work.term == int(_rules(work).run.term_count):
		_complete_node(work, node)
		_event(events, "node_completed", node.node_id, {"node_id": node.node_id, "kind": node.kind})
		if int(_rules(work).run.term_count) == 1:
			summary = _finalize(work, "won", "first_term_completed")
		else:
			work.awaiting_ending = true
			work.ending_draft = {"eligible_endings": eligible_endings(work)}
			_event(events, "ending_requested", work.run_id, work.ending_draft.duplicate(true))
	else:
		var generated := _reward_generator.generate(node, work, rng)
		if not generated.ok:
			return generated
		work.pending_reward = generated.data
		work.money += int(work.pending_reward.meta.get("money", 0))
		_event(
			events,
			"reward_created",
			node.node_id,
			{
				"offer_id": work.pending_reward.offer_id,
				"money": int(work.pending_reward.meta.get("money", 0))
			}
		)
	if summary != null:
		_event(
			events,
			"run_finished",
			work.run_id,
			{"result": work.outcome, "reason": summary.reason, "ending_id": summary.ending_id}
		)
	return GameResult.success(
		RunStep.new(work, events, null, summary, rng.export_state().to_dictionary())
	)


func _gate(state: RunState, type: String) -> GameResult:
	if state == null:
		return _error(GameConstants.ERROR_RUN_NOT_FOUND, "run.missing")
	if not state.outcome.is_empty():
		return _error(
			(
				GameConstants.ERROR_ALREADY_RESOLVED
				if type == "choose_ending"
				else GameConstants.ERROR_WRONG_PHASE
			),
			"run.finished"
		)
	if state.awaiting_ending and type != "choose_ending":
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.ending.pending")
	if not state.active_battle_id.is_empty():
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.battle.active")
	if (
		state.pending_reward != null
		and not state.pending_reward.is_complete()
		and type not in ["claim_reward", "skip_reward"]
	):
		return _error(GameConstants.ERROR_CHOICE_PENDING, "run.reward.pending")
	if (
		state.settlement != null
		and not state.settlement.is_complete()
		and type != "choose_term_option"
	):
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.term.pending")
	return GameResult.success(true)


func _can_enter(state: RunState, payload: Dictionary) -> GameResult:
	var id := str(payload.get("node_id", ""))
	var node := state.find_node(id)
	if node == null:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.node.unknown")
	if node.status != "pending":
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.node.entered")
	if not state.reachable_node_ids().has(id):
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.node.unreachable")
	return GameResult.success(true)


func _enter_node(
	work: RunState, payload: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var checked := _can_enter(work, payload)
	if not checked.ok:
		return checked
	var node := work.find_node(str(payload.node_id))
	work.current_node_id = node.node_id
	work.pending_reward = null
	node.status = "active"
	var fallback := false
	if node.kind == "event":
		var entered := _node_service.enter_event(work, node, rng)
		if not entered.ok:
			return entered
		if entered.data != null:
			node.context = {"event": entered.data}
			return GameResult.success(null)
		node.kind = "normal"
		fallback = true
	if node.kind == "shop":
		var shop := _reward_generator.generate_shop(node, work, rng)
		if not shop.ok:
			return shop
		node.context = {"shop": shop.data}
		return GameResult.success(null)
	if node.kind == "rest":
		node.context = {"used": false, "option_id": ""}
		return GameResult.success(null)
	var pool: Array[String] = []
	for id in _catalog.get_candidates({"kind": "encounter", "terms": work.term}):
		var definition: Dictionary = _catalog.get_definition("encounter", id).data
		if definition.kind == node.kind:
			pool.append(id)
	if pool.is_empty():
		return _error(
			GameConstants.ERROR_CONTENT_INVALID,
			"run.encounter.pool.empty",
			{"kind": node.kind, "term": work.term}
		)
	var chosen := rng.draw_int("map", 0, pool.size() - 1)
	var encounter_id: String = pool[int(chosen.data)]
	if fallback:
		_event(
			events,
			"event_fallback",
			node.node_id,
			{"node_id": node.node_id, "encounter_id": encounter_id}
		)
	work.active_battle_id = node.node_id
	work.active_encounter_id = encounter_id
	node.context = {"encounter_id": encounter_id, "settled": false}
	var relics := work.relics.duplicate(true)
	relics.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	var relic_ids: Array[String] = []
	for relic in relics:
		relic_ids.append(str(relic.definition_id))
	var cards: Array[Dictionary] = []
	for card in work.cards:
		cards.append(
			{
				"card_id": card.card_id,
				"definition_id": card.definition_id,
				"upgrade_level": card.upgrade_level
			}
		)
	return (
		GameResult
		. success(
			{
				"battle_id": node.node_id,
				"node_id": node.node_id,
				"encounter_id": encounter_id,
				"character_id": work.character_id,
				"difficulty": work.difficulty,
				"vitality": work.vitality,
				"max_vitality": work.max_vitality,
				"cards": cards,
				"relics": relic_ids,
				"rng_state": rng.export_state().to_dictionary(),
			}
		)
	)


func _can_leave(state: RunState, payload: Dictionary) -> GameResult:
	var node := state.find_node(str(payload.get("node_id", "")))
	if node == null or node.node_id != state.current_node_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.node.invalid")
	if node.status == "completed":
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.node.completed")
	if node.status != "active":
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.node.inactive")
	match node.kind:
		"normal", "elite", "boss":
			if not node.context.get("settled", false):
				return _error(GameConstants.ERROR_WRONG_PHASE, "run.battle.unsettled")
			if state.pending_reward == null or not state.pending_reward.is_complete():
				return _error(GameConstants.ERROR_CHOICE_PENDING, "run.reward.pending")
		"event":
			if (
				node.context.get("event") == null
				or str(_read(node.context.event, "resolved_option_id", "")).is_empty()
			):
				return _error(GameConstants.ERROR_CHOICE_PENDING, "run.event.unresolved")
		"rest":
			if not node.context.get("used", false):
				return _error(GameConstants.ERROR_CHOICE_PENDING, "run.rest.unused")
	return GameResult.success(true)


func _leave_node(work: RunState, payload: Dictionary, rng: RandomSource) -> GameResult:
	var checked := _can_leave(work, payload)
	if not checked.ok:
		return checked
	var node := work.find_node(work.current_node_id)
	_complete_node(work, node)
	if node.kind == "boss":
		var rules := _rules(work)
		work.vitality = mini(
			work.max_vitality,
			work.vitality + int(floor(work.max_vitality * int(rules.run.term_heal_percent) / 100.0))
		)
		var generated := _reward_generator.generate(
			{"kind": "term", "node_id": node.node_id}, work, rng
		)
		if not generated.ok:
			return generated
		var offer: RewardOffer = generated.data
		var candidates: Array = offer.items[0].candidates if not offer.items.is_empty() else []
		work.settlement = TermSettlement.create(
			{
				"settlement_id": "%s|term" % node.node_id,
				"term": work.term,
				"steps":
				[
					{
						"step_id": "direction_reward",
						"status": "pending",
						"candidates": candidates,
						"skippable": true
					}
				]
			}
		)
	return GameResult.success(true)


func _complete_node(work: RunState, node: RunNodeState) -> void:
	node.status = "completed"
	if not work.node_path.has(node.node_id):
		work.node_path.append(node.node_id)


func _claim_reward(work: RunState, type: String, payload: Dictionary) -> GameResult:
	var offer: Variant = work.pending_reward
	if offer == null or str(payload.get("offer_id", "")) != offer.offer_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.reward.invalid")
	var item: Dictionary = offer.get_item(str(payload.get("item_id", "")))
	if item.is_empty():
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.reward.item.invalid")
	if item.get("status", "pending") != "pending":
		return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.reward.resolved")
	if type == "skip_reward":
		if not item.get("skippable", false):
			return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.reward.skip.forbidden")
		item.status = "skipped"
		return GameResult.success(true)
	var candidates: Array = item.get("candidates", [])
	var chosen := str(payload.get("candidate_id", ""))
	if chosen.is_empty() and candidates.size() == 1:
		chosen = str(candidates[0])
	if not candidates.has(chosen):
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.reward.candidate.invalid")
	if item.kind == "card":
		_transaction_resolver.add_card(work, chosen, "reward")
	elif item.kind == "relic":
		var replacement := str(payload.get("replace_relic_id", ""))
		var validated := _transaction_resolver.validate_relic(
			work, chosen, replacement, int(_rules(work).run.relic_slots)
		)
		if not validated.ok:
			return validated
		_transaction_resolver.add_relic(work, chosen, replacement, int(validated.data))
	else:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "run.reward.kind.unknown")
	item.status = "claimed"
	item.chosen_id = chosen
	return GameResult.success(true)


func _choose_term(work: RunState, payload: Dictionary) -> GameResult:
	var settlement: Variant = work.settlement
	if settlement == null or str(payload.get("settlement_id", "")) != settlement.settlement_id:
		return _error(GameConstants.ERROR_INVALID_TARGET, "run.term.invalid")
	for step in settlement.steps:
		if str(step.step_id) != str(payload.get("step_id", "")):
			continue
		if str(step.status) != "pending":
			return _error(GameConstants.ERROR_ALREADY_RESOLVED, "run.term.step.resolved")
		var option := str(payload.get("option_id", ""))
		if option == "skip" and step.get("skippable", false):
			step.status = "skipped"
		elif option in ["claim", "take", "direction_reward"]:
			var id := str(payload.get("candidate_id", ""))
			if not step.get("candidates", []).has(id):
				return _error(GameConstants.ERROR_INVALID_TARGET, "run.term.candidate.invalid")
			_transaction_resolver.add_card(work, id, "term")
			step.status = "claimed"
			step.chosen_id = id
		else:
			return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.term.option.invalid")
		if settlement.is_complete():
			work.term += 1
			work.node_path.clear()
			work.current_node_id = ""
			work.pending_reward = null
			work.settlement = null
		return GameResult.success(true)
	return _error(GameConstants.ERROR_INVALID_TARGET, "run.term.step.invalid")


func _choose_ending(work: RunState, payload: Dictionary) -> GameResult:
	if not work.awaiting_ending:
		return _error(GameConstants.ERROR_WRONG_PHASE, "run.ending.inactive")
	if not work.ending_draft.get("eligible_endings", []).has(str(payload.get("ending_id", ""))):
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.ending.invalid")
	return GameResult.success(true)


func eligible_endings(state: RunState) -> Array[String]:
	var result: Array[String] = []
	if state.ending_draft.has("eligible_endings"):
		for id in state.ending_draft.eligible_endings:
			result.append(str(id))
	return result


func _finalize(work: RunState, result: String, reason: String, ending: String = "") -> RunSummary:
	work.outcome = result
	work.awaiting_ending = false
	work.ending_draft = {}
	return RunSummary.create(
		{
			"run_id": work.run_id,
			"result": result,
			"reason": reason,
			"ending_id": ending,
			"character_id": work.character_id,
			"difficulty": work.difficulty,
			"manifest_id": work.manifest_id,
			"term": work.term,
			"statistics":
			{
				"money": work.money,
				"vitality": work.vitality,
				"deck_size": work.cards.size(),
				"settled_battles": work.settled_battle_ids.size(),
				"completed_nodes": work.node_path.size()
			},
			"seen_content_ids": work.seen_event_ids
		}
	)


func make_view(state: RunState) -> Dictionary:
	var rules := _rules(state)
	var view := state.to_dictionary()
	view.term_count = int(rules.run.term_count)
	view.nodes_per_term = 8
	view.relic_slots = int(rules.run.relic_slots)
	view.deck_size = state.cards.size()
	view.reachable_node_ids = state.reachable_node_ids()
	for card in view.cards:
		var level := int(card.get("upgrade_level", 0))
		card.detail = _reward_candidate_view(
			"card", str(card.definition_id), rules, level, str(card.card_id)
		)
		card.upgrade_detail = null
		var definition := _catalog.get_definition("card", str(card.definition_id))
		if (
			level < int(rules.run.max_card_upgrades)
			and definition.ok
			and not definition.data.get("upgrade", {}).is_empty()
		):
			card.upgrade_detail = _reward_candidate_view(
				"card", str(card.definition_id), rules, level + 1, str(card.card_id)
			)
	for relic in view.relics:
		relic.detail = _reward_candidate_view("relic", str(relic.definition_id), rules)
	if view.pending_reward is Dictionary:
		for item in view.pending_reward.items:
			item.candidate_details = {}
			for id in item.candidates:
				item.candidate_details[str(id)] = _reward_candidate_view(
					str(item.kind), str(id), rules
				)
	view.eligible_endings = eligible_endings(state)
	view.nodes = []
	for node in state.nodes:
		if node.term == state.term:
			view.nodes.append(_node_view(node))
	var node := state.find_node(state.current_node_id)
	view.node = _node_view(node) if node != null else null
	view.battle = null
	view.shop = null
	view.event = null
	view.rest = null
	view.screen = "map"
	if node != null and node.status == "active":
		if node.kind in ["normal", "elite", "boss"]:
			view.battle = {
				"battle_id": node.node_id,
				"encounter_id": node.context.get("encounter_id", ""),
				"settled": node.context.get("settled", false)
			}
			view.screen = "battle" if not node.context.get("settled", false) else "map"
		elif node.kind == "shop":
			var shop: Variant = node.context.get("shop")
			view.shop = shop.to_dictionary() if shop is Object else shop.duplicate(true)
			for stock in view.shop.stocks:
				stock.price = _reward_generator.price_for(
					state, str(stock.kind), int(stock.get("base_price", stock.price))
				)
				if stock.kind in ["card", "relic"]:
					stock.detail = _reward_candidate_view(
						str(stock.kind), str(stock.definition_id), rules
					)
				elif stock.kind == "meal":
					var base_heal := int(rules.shop.meal_heal)
					var heal := mini(base_heal, maxi(0, state.max_vitality - state.vitality))
					stock.detail = {
						"kind": "meal",
						"base_heal_amount": base_heal,
						"heal_amount": heal,
						"effects": [{"op": "heal", "amount": heal, "target": "player"}]
					}
			view.shop.removal = {
				"available":
				(
					int(view.shop.removal_count) < int(rules.shop.removals_per_shop)
					and state.cards.size() > int(rules.run.minimum_deck_size)
				),
				"used": int(view.shop.removal_count),
				"max": int(rules.shop.removals_per_shop),
				"price":
				(
					int(rules.shop.first_removal_price)
					+ state.removals_used * int(rules.shop.removal_price_increment)
				),
				"money": state.money,
				"minimum_deck_size": int(rules.run.minimum_deck_size),
				"deck_size": state.cards.size()
			}
			view.screen = "shop"
		elif node.kind == "event":
			view.event = _node_service.event_view(state, node)
			view.screen = "event"
		elif node.kind == "rest":
			view.rest = _node_service.rest_view(state, node)
			view.rest.effective_heal_amount = mini(
				int(view.rest.heal_amount), maxi(0, state.max_vitality - state.vitality)
			)
			view.screen = "rest"
	if state.pending_reward != null and not state.pending_reward.is_complete():
		view.screen = "reward"
	if state.settlement != null and not state.settlement.is_complete():
		view.screen = "term"
	if not state.outcome.is_empty():
		view.screen = "summary"
	if state.awaiting_ending:
		view.screen = "ending"
	return view


func _reward_candidate_view(
	kind: String,
	id: String,
	rules: Dictionary,
	upgrade_level: int = 0,
	card_instance_id: String = ""
) -> Dictionary:
	var result := _catalog.get_definition(kind, id)
	if not result.ok:
		return {}
	var detail: Dictionary = result.data.duplicate(true)
	if kind == "card":
		var instance_id := card_instance_id if not card_instance_id.is_empty() else id
		var face_state := BattleState.new(
			{
				"card_by_id":
				{
					instance_id:
					{
						"definition_id": id,
						"upgrade_level": upgrade_level,
						"origin_card_id": card_instance_id
					}
				}
			}
		)
		var resolved := _card_rules.resolve_face(face_state, instance_id)
		if not resolved.ok:
			return {}
		detail = resolved.data.duplicate(true)
	detail.related_units = {}
	detail.related_scenes = {}
	for effect in detail.get("pre_effects", []) + detail.get("effects", []):
		for pair in [["unit", "related_units"], ["scene", "related_scenes"]]:
			var related_id := str(effect.get(pair[0], ""))
			if related_id.is_empty():
				continue
			var related := _catalog.get_definition(pair[0], related_id)
			if related.ok:
				detail[pair[1]][related_id] = related.data.duplicate(true)
	if kind == "card" and detail.get("type") in ["cooperation", "scene"]:
		var battle_rules: Dictionary = rules.get("battle", {})
		var values: Array = battle_rules.get(
			"cooperation_exam_relax" if detail.type == "cooperation" else "scene_exam_relax", []
		)
		if values.size() > upgrade_level:
			detail.exam_effects = [{"op": "relax", "amount": values[upgrade_level]}]
			if detail.type == "scene":
				detail.exam_effects.push_front(
					{"op": "draw", "amount": int(battle_rules.get("scene_exam_draw", 0))}
				)
	return detail


func _node_view(node: RunNodeState) -> Dictionary:
	return {
		"node_id": node.node_id,
		"term": node.term,
		"layer": node.layer,
		"kind": node.kind,
		"status": node.status,
		"next_ids": node.next_ids.duplicate(),
		"encounter_id": node.context.get("encounter_id", ""),
		"event_definition_id": str(_read(node.context.get("event"), "definition_id", ""))
	}


func _rules(state: RunState) -> Dictionary:
	return _catalog.get_definition("ruleset", state.ruleset_id).data


func _restore_rng(rng: RandomSource, snapshot: Dictionary) -> GameResult:
	if snapshot.get("algorithm_version") != GameConstants.RANDOM_ALGORITHM_VERSION:
		return _error(GameConstants.ERROR_VERSION_MISMATCH, "run.random.version")
	return rng.restore_state(snapshot)


func _decimal_seed(seed: String) -> bool:
	if seed.is_empty():
		return false
	var start := 1 if seed.begins_with("-") or seed.begins_with("+") else 0
	if start == seed.length():
		return false
	for index in range(start, seed.length()):
		if seed.unicode_at(index) < 48 or seed.unicode_at(index) > 57:
			return false
	return true


func _clean_payload(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	for key in ["candidate_id", "replace_relic_id", "card_instance_id"]:
		if result.has(key) and result[key] == null:
			result.erase(key)
	return result


func _validate_action(type: String, payload: Variant) -> GameResult:
	if not ACTION_KEYS.has(type) or not payload is Dictionary:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "run.action.invalid")
	for key in payload:
		if not ACTION_KEYS[type].has(key):
			return _error(
				GameConstants.ERROR_INVALID_ARGUMENT, "run.payload.unknown_key", {"field": key}
			)
	return GameResult.success(true)


func _action_events(
	before: RunState, after: RunState, type: String, payload: Dictionary, events: Array[RuleEvent]
) -> void:
	var node := after.find_node(after.current_node_id)
	match type:
		"enter_node", "leave_node":
			_event(
				events,
				"node_entered" if type == "enter_node" else "node_completed",
				node.node_id,
				{"node_id": node.node_id, "kind": node.kind}
			)
		"claim_reward", "skip_reward":
			var item: Dictionary = after.pending_reward.get_item(str(payload.item_id))
			_event(
				events,
				"reward_claimed" if type == "claim_reward" else "reward_skipped",
				node.node_id,
				{
					"offer_id": payload.offer_id,
					"item_id": payload.item_id,
					"candidate_id": item.get("chosen_id")
				}
			)
		"buy_item":
			_event(
				events,
				"item_purchased",
				node.node_id,
				{
					"shop_id": payload.shop_id,
					"stock_id": payload.stock_id,
					"price": before.money - after.money
				}
			)
		"choose_event":
			_event(
				events,
				"event_resolved",
				str(payload.event_instance_id),
				{"event_instance_id": payload.event_instance_id, "option_id": payload.option_id}
			)
		"take_rest":
			_event(
				events,
				"rest_taken",
				node.node_id,
				{
					"node_id": node.node_id,
					"option_id": payload.option_id,
					"card_id": payload.get("card_instance_id")
				}
			)
		"choose_term_option":
			if after.term != before.term:
				_event(
					events,
					"term_settled",
					before.current_node_id,
					{"term": before.term, "next_term": after.term}
				)
	for card in before.cards:
		var updated: Dictionary = {}
		for candidate in after.cards:
			if candidate.card_id == card.card_id:
				updated = candidate
		if updated.is_empty():
			_event(
				events,
				"card_removed",
				card.card_id,
				{
					"card_id": card.card_id,
					"definition_id": card.definition_id,
					"upgrade_level": card.upgrade_level
				}
			)
		elif updated.upgrade_level != card.upgrade_level:
			_event(
				events,
				"card_upgraded",
				card.card_id,
				{
					"card_id": card.card_id,
					"definition_id": card.definition_id,
					"upgrade_level": updated.upgrade_level
				}
			)


func _preview_details(
	state: RunState, type: String, payload: Dictionary, result: ActionPreview
) -> void:
	var node := state.find_node(state.current_node_id)
	if type == "take_rest" and node != null and node.kind == "rest":
		var view := _node_service.rest_view(state, node)
		for option in view.options:
			if option.option_id != payload.get("option_id"):
				continue
			if option.needs_card and str(payload.get("card_instance_id", "")).is_empty():
				_selection(result, "card_instance_id", "card", option.eligible_card_ids)
			result.known_effects.append(
				{
					"op": option.option_id,
					"amount": view.heal_amount if option.option_id == "heal" else 1
				}
			)
	elif type == "choose_event" and node != null and node.kind == "event":
		var event: EventState = node.context.get("event")
		if event == null:
			return
		var definition := _catalog.get_definition("event", event.definition_id)
		if not definition.ok:
			return
		var selected: Array = (
			payload.get("selection_ids", []) if payload.get("selection_ids", []) is Array else []
		)
		var selection_index := 0
		for option in definition.data.options:
			if option.option_id != payload.get("option_id"):
				continue
			result.costs = option.cost.duplicate(true)
			result.known_effects.assign(option.effects.duplicate(true))
			for index in option.effects.size():
				var effect: Dictionary = option.effects[index]
				var ids: Array = []
				if effect.op in ["upgrade_card", "remove_card"]:
					ids = _node_service._eligible_cards(state, effect)
				elif effect.op == "gain_card" and not effect.has("card_id"):
					ids = event.frozen_candidates.get(option.option_id, {}).get(str(index), [])
					if ids.size() <= 1:
						continue
				else:
					continue
				if selection_index >= selected.size():
					_selection(result, "selection_ids", "event_target", ids, selection_index)
				selection_index += 1
	elif type == "remove_card" and str(payload.get("card_instance_id", "")).is_empty():
		_selection(
			result, "card_instance_id", "card", state.cards.map(func(card): return card.card_id)
		)
	elif type == "claim_reward" and state.pending_reward != null:
		var item: Dictionary = state.pending_reward.get_item(str(payload.get("item_id", "")))
		if (
			item.get("candidates", []).size() > 1
			and str(payload.get("candidate_id", "")).is_empty()
		):
			_selection(result, "candidate_id", str(item.get("kind", "")), item.candidates)
	if (
		type in ["claim_reward", "buy_item", "choose_event"]
		and state.relics.size() >= int(_rules(state).run.relic_slots)
	):
		if str(payload.get("replace_relic_id", "")).is_empty():
			var needs_replacement := false
			if type == "claim_reward" and state.pending_reward != null:
				needs_replacement = (
					state.pending_reward.get_item(str(payload.get("item_id", ""))).get("kind")
					== "relic"
				)
			elif type == "buy_item" and node != null and node.kind == "shop":
				for stock in node.context.shop.stocks:
					if stock.stock_id == payload.get("stock_id"):
						needs_replacement = stock.kind == "relic"
			elif type == "choose_event":
				needs_replacement = result.known_effects.any(
					func(effect): return effect.op == "gain_relic"
				)
			if needs_replacement:
				_selection(
					result,
					"replace_relic_id",
					"relic_replacement",
					state.relics.map(func(relic): return relic.relic_id)
				)


func _selection(
	result: ActionPreview, field: String, kind: String, ids: Array, index: int = -1
) -> void:
	var candidates: Array[Dictionary] = []
	for id in ids:
		candidates.append({"id": str(id), "label_key": str(id), "preview": {}})
	result.required_selections.append(
		{
			"field": field,
			"kind": kind,
			"candidates": candidates,
			"min_count": 1,
			"max_count": 1,
			"index": index
		}
	)


func _event(events: Array[RuleEvent], type: String, source: String, data: Dictionary) -> void:
	events.append(RuleEvent.new(events.size(), StringName(type), source, [], data))


func _read(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if value is Dictionary:
		return value.get(key, fallback)
	if value is Object:
		for property in value.get_property_list():
			if property.name == key:
				return value.get(key)
	return fallback


func _error(code: StringName, key: String, details: Dictionary = {}) -> GameResult:
	return GameResult.failure(ApiError.new(code, key, details))
