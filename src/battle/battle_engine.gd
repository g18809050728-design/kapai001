class_name BattleEngine
extends RefCounted

var _catalog: ContentDB
var _card_rules: BattleCardRules


func _init(catalog: ContentDB = null) -> void:
	_catalog = catalog
	_card_rules = BattleCardRules.new(catalog)


func set_catalog(catalog: ContentDB) -> void:
	_catalog = catalog
	_card_rules.set_catalog(catalog)


func resolve_face(state: BattleState, card_id: String) -> GameResult:
	return _card_rules.resolve_face(state, card_id)


func calculate_cost(state: BattleState, card_id: String) -> GameResult:
	return _card_rules.calculate_cost(state, card_id)


func preview(state: BattleState, draft: ActionDraft) -> GameResult:
	if _catalog == null or _catalog.get_info() == null:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.catalog.not_ready",
			{"operation": "preview"}
		)
	if state == null or draft == null:
		return _invalid_input("preview requires state and draft", {"path": "preview"})
	if not _is_known_battle_action(draft.type):
		return _invalid_input(
			"draft.type is unknown", {"path": "draft.type", "type": String(draft.type)}
		)
	if draft.type != GameConstants.ACTION_PLAY_CARD:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.action.preview_not_ready",
			{"type": String(draft.type)}
		)

	var payload: Dictionary = draft.payload
	for key in payload:
		if key not in ["card_instance_id", "target_ids", "replace_unit_id"]:
			return _invalid_input(
				"draft.payload.%s is unknown" % key, {"path": "draft.payload.%s" % key}
			)
	if (
		not payload.has("card_instance_id")
		or typeof(payload.card_instance_id) != TYPE_STRING
		or payload.card_instance_id.is_empty()
	):
		return _invalid_input(
			"draft.payload.card_instance_id is required", {"path": "draft.payload.card_instance_id"}
		)
	var target_ids: Array[String] = []
	if payload.has("target_ids"):
		if typeof(payload.target_ids) != TYPE_ARRAY:
			return _invalid_input(
				"draft.payload.target_ids must be an array", {"path": "draft.payload.target_ids"}
			)
		for index in payload.target_ids.size():
			if typeof(payload.target_ids[index]) != TYPE_STRING:
				return _invalid_input(
					"draft.payload.target_ids items must be strings",
					{"path": "draft.payload.target_ids[%d]" % index}
				)
			target_ids.append(payload.target_ids[index])
	if (
		payload.has("replace_unit_id")
		and payload.replace_unit_id != null
		and typeof(payload.replace_unit_id) != TYPE_STRING
	):
		return _invalid_input(
			"draft.payload.replace_unit_id must be a string or null",
			{"path": "draft.payload.replace_unit_id"}
		)
	var replace_unit_id := ""
	if payload.has("replace_unit_id") and payload.replace_unit_id != null:
		replace_unit_id = payload.replace_unit_id

	var result := ActionPreview.new()
	var card_id: String = payload.card_instance_id
	var hand: Array = state.zones.get("hand", [])
	if not hand.has(card_id) or not state.card_by_id.has(card_id):
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.card_not_in_hand",
			{"card_instance_id": card_id}
		)
		return _finish_preview(result)

	var face_result := _card_rules.resolve_face(state, card_id)
	if not face_result.ok:
		return face_result
	var face: Dictionary = face_result.data
	result.effective_card = face.duplicate(true)
	result.known_effects = _visible_effects(face)
	result.costs = _preview_costs(state, card_id)
	if result.costs.is_empty():
		return _failure(
			GameConstants.ERROR_RESOLUTION_ERROR,
			"battle.cost.quote_failed",
			{"card_instance_id": card_id}
		)

	if state.phase == "awaiting_choice" or state.resolution != null:
		_add_preview_error(
			result, GameConstants.ERROR_CHOICE_PENDING, "error.battle.choice_pending", {}
		)
	elif state.phase != "player_action":
		_add_preview_error(
			result,
			GameConstants.ERROR_WRONG_PHASE,
			"error.battle.wrong_phase",
			{"phase": state.phase}
		)

	if bool(face.get("unplayable", false)):
		_add_preview_error(
			result,
			GameConstants.ERROR_UNPLAYABLE,
			"error.play.unplayable",
			{"card_instance_id": card_id, "definition_id": face.id}
		)

	_validate_preview_limit(result, state, face)
	_validate_preview_targets(result, state, face, target_ids, replace_unit_id)
	_validate_preview_resources(result, state, card_id)
	return _finish_preview(result)


func _is_known_battle_action(action_type: StringName) -> bool:
	return (
		action_type
		in [
			GameConstants.ACTION_PLAY_CARD,
			GameConstants.ACTION_END_TURN,
			GameConstants.ACTION_CONFIRM_CHOICE,
			GameConstants.ACTION_SET_ALLY_TARGET,
		]
	)


func _visible_effects(face: Dictionary) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for effect: Dictionary in face.get("pre_effects", []):
		effects.append(effect.duplicate(true))
	for effect: Dictionary in face.get("effects", []):
		effects.append(effect.duplicate(true))
	return effects


func _preview_costs(state: BattleState, card_id: String) -> Dictionary:
	var quote_result := _card_rules.calculate_cost(state, card_id)
	if not quote_result.ok:
		return {}
	var quote: Dictionary = quote_result.data
	return {
		"focus": quote.cost,
		"vitality": quote.vitality_cost,
		"quote": quote.duplicate(true),
	}


func _validate_preview_resources(
	result: ActionPreview, state: BattleState, card_id: String
) -> void:
	var quote_result := _card_rules.calculate_cost(state, card_id)
	if not quote_result.ok:
		return
	var quote: Dictionary = quote_result.data
	var available_focus: int = int(state.player.get("focus", 0))
	if available_focus < int(quote.cost):
		_add_preview_error(
			result,
			GameConstants.ERROR_INSUFFICIENT_RESOURCE,
			"error.play.not_enough_focus",
			{"required": quote.cost, "available": available_focus}
		)
	var available_vitality: int = int(state.player.get("vitality", 0))
	var minimum_vitality := 1
	var info: ContentInfo = _catalog.get_info()
	var ruleset_result := _catalog.get_definition("ruleset", info.ruleset_id)
	if ruleset_result.ok:
		minimum_vitality = int(ruleset_result.data.battle.get("minimum_vitality_after_payment", 1))
	var payment: int = int(quote.vitality_cost)
	if available_vitality - payment < minimum_vitality:
		_add_preview_error(
			result,
			GameConstants.ERROR_INSUFFICIENT_RESOURCE,
			"error.play.not_enough_vitality",
			{
				"required": payment,
				"available": available_vitality,
				"must_keep": minimum_vitality,
			}
		)


func _validate_preview_limit(result: ActionPreview, state: BattleState, face: Dictionary) -> void:
	var limit: Variant = face.get("limit")
	if typeof(limit) != TYPE_DICTIONARY:
		return
	var origin_card_id := str(face.get("origin_card_id", ""))
	var owner_key := origin_card_id if not origin_card_id.is_empty() else str(face.card_instance_id)
	var scope := StringName(str(limit.get("per", "")))
	var key := BattleState.counter_key(scope, owner_key, &"play_card")
	var used: int = int(state.counters.get(key, 0))
	if used >= int(limit.get("times", 0)):
		_add_preview_error(
			result,
			GameConstants.ERROR_LIMIT_REACHED,
			"error.play.limit_reached",
			{"card_instance_id": face.card_instance_id, "limit": limit.duplicate(true)}
		)


func _validate_preview_targets(
	result: ActionPreview,
	state: BattleState,
	face: Dictionary,
	target_ids: Array[String],
	replace_unit_id: String
) -> void:
	var target := str(face.get("target", ""))
	if target in ["self", "all_tasks"]:
		if not target_ids.is_empty() or not replace_unit_id.is_empty():
			_add_preview_error(
				result,
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.unexpected_target",
				{"target": target, "target_ids": target_ids, "replace_unit_id": replace_unit_id}
			)
		return
	if target not in ["task", "unit"]:
		_add_preview_error(
			result,
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.card.target_invalid",
			{"definition_id": face.get("id", ""), "target": target}
		)
		return

	if target == "unit" and _has_effect(face, "summon_unit"):
		_validate_summon_replacement(result, state, face, target_ids, replace_unit_id)
		return
	if not replace_unit_id.is_empty():
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.unexpected_replacement",
			{"replace_unit_id": replace_unit_id}
		)
	var candidates := _target_candidates(state, target)
	if target_ids.is_empty():
		if candidates.is_empty():
			_add_preview_error(
				result,
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.no_target",
				{"target": target}
			)
		else:
			(
				result
				. required_selections
				. append(
					{
						"field": "target_ids",
						"kind": target,
						"candidates": candidates.duplicate(true),
						"min_count": 1,
						"max_count": 1,
					}
				)
			)
			_add_preview_error(
				result,
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.target_required",
				{"field": "target_ids", "target": target}
			)
		return
	if target_ids.size() != 1 or not _candidate_ids(candidates).has(target_ids[0]):
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.invalid_target",
			{"target": target, "target_ids": target_ids}
		)


func _validate_summon_replacement(
	result: ActionPreview,
	state: BattleState,
	face: Dictionary,
	target_ids: Array[String],
	replace_unit_id: String
) -> void:
	if not target_ids.is_empty():
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.unexpected_target",
			{"target_ids": target_ids}
		)
		return
	var slot_limit := 0
	var info: ContentInfo = _catalog.get_info()
	var ruleset_result := _catalog.get_definition("ruleset", info.ruleset_id)
	if ruleset_result.ok:
		slot_limit = int(ruleset_result.data.battle.get("unit_slots", 0))
	var candidates := _target_candidates(state, "unit")
	if candidates.size() < slot_limit:
		if not replace_unit_id.is_empty():
			_add_preview_error(
				result,
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.unexpected_replacement",
				{"replace_unit_id": replace_unit_id}
			)
		return
	if replace_unit_id.is_empty():
		(
			result
			. required_selections
			. append(
				{
					"field": "replace_unit_id",
					"kind": "unit_replacement",
					"candidates": candidates.duplicate(true),
					"min_count": 1,
					"max_count": 1,
				}
			)
		)
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.replacement_required",
			{"field": "replace_unit_id", "card_instance_id": face.card_instance_id}
		)
	elif not _candidate_ids(candidates).has(replace_unit_id):
		_add_preview_error(
			result,
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.invalid_replacement",
			{"replace_unit_id": replace_unit_id}
		)


func _has_effect(face: Dictionary, op: String) -> bool:
	for effect: Dictionary in _visible_effects(face):
		if effect.get("op") == op:
			return true
	return false


func _target_candidates(state: BattleState, target: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if target == "task":
		for task: Dictionary in state.tasks:
			if int(task.get("work_remaining", 0)) <= 0:
				continue
			if int(task.get("eligible_round", 1)) > state.round_index:
				continue
			var definition_result := _catalog.get_definition(
				"task", str(task.get("definition_id", ""))
			)
			var label_key := str(task.get("definition_id", ""))
			if definition_result.ok:
				label_key = str(definition_result.data.get("name_key", label_key))
			(
				candidates
				. append(
					{
						"id": str(task.get("task_id", "")),
						"label_key": label_key,
						"preview":
						{
							"work_remaining": int(task.get("work_remaining", 0)),
							"shield": int(task.get("shield", 0)),
						},
					}
				)
			)
	elif target == "unit":
		for unit: Dictionary in state.units:
			if int(unit.get("vitality", 1)) <= 0:
				continue
			var definition_result := _catalog.get_definition(
				"unit", str(unit.get("definition_id", ""))
			)
			var label_key := str(unit.get("definition_id", ""))
			if definition_result.ok:
				label_key = str(definition_result.data.get("name_key", label_key))
			(
				candidates
				. append(
					{
						"id": str(unit.get("unit_id", "")),
						"label_key": label_key,
						"preview": {"vitality": int(unit.get("vitality", 0))},
					}
				)
			)
	return candidates


func _candidate_ids(candidates: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for candidate: Dictionary in candidates:
		ids.append(str(candidate.get("id", "")))
	return ids


func _add_preview_error(
	result: ActionPreview, code: StringName, message_key: String, details: Dictionary
) -> void:
	result.blocking_errors.append(ApiError.new(code, message_key, details))


func _finish_preview(result: ActionPreview) -> GameResult:
	result.can_submit = result.required_selections.is_empty() and result.blocking_errors.is_empty()
	return GameResult.success(result)


func apply(state: BattleState, action: ActionDraft, rng_state: Dictionary) -> GameResult:
	if state == null or action == null:
		return _invalid_input("apply requires state and action", {"path": "apply"})
	if typeof(rng_state) != TYPE_DICTIONARY:
		return _invalid_input("rng_state must be a complete snapshot", {"path": "rng_state"})
	if (
		action.type
		not in [
			GameConstants.ACTION_PLAY_CARD,
			GameConstants.ACTION_CONFIRM_CHOICE,
			GameConstants.ACTION_END_TURN,
			GameConstants.ACTION_SET_ALLY_TARGET,
		]
	):
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.action.apply_not_ready",
			{"type": String(action.type)}
		)
	if action.type == GameConstants.ACTION_PLAY_CARD:
		var preview_result := preview(state, action)
		if not preview_result.ok:
			return preview_result
		var preview_value: ActionPreview = preview_result.data
		if not preview_value.can_submit:
			var error: ApiError = preview_value.blocking_errors[0]
			return GameResult.failure(error)
	elif action.type == GameConstants.ACTION_CONFIRM_CHOICE:
		if state.phase != "awaiting_choice" or typeof(state.resolution) != TYPE_DICTIONARY:
			return _failure(
				GameConstants.ERROR_WRONG_PHASE,
				"error.battle.no_pending_choice",
				{"phase": state.phase}
			)

	var rng := RandomSource.new("battle_apply")
	var restored := rng.restore_state(rng_state)
	if not restored.ok:
		return restored
	var working := state.copy()
	var events: Array[RuleEvent] = []
	var pending_choice: Variant = null
	if action.type == GameConstants.ACTION_PLAY_CARD:
		var started := _start_card_resolution(working, action.payload, events)
		if not started.ok:
			return started
	elif action.type == GameConstants.ACTION_CONFIRM_CHOICE:
		var confirmed := _confirm_effect_choice(working, action.payload, events)
		if not confirmed.ok:
			return confirmed
	var continued: GameResult
	if action.type == GameConstants.ACTION_END_TURN:
		continued = _end_turn(working, action.payload, rng, events)
	elif action.type == GameConstants.ACTION_SET_ALLY_TARGET:
		continued = _set_ally_target(working, action.payload, events)
	else:
		continued = _continue_resolution(working, rng, events)
	if not continued.ok:
		return continued
	pending_choice = continued.data
	var result_snapshot: RandomSnapshot = rng.export_state()
	return GameResult.success(
		BattleStep.new(
			working,
			events,
			pending_choice,
			working.outcome,
			pending_choice == null,
			result_snapshot.to_dictionary()
		)
	)


func _start_card_resolution(
	state: BattleState, payload: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var card_id: String = payload.card_instance_id
	var preview_result := preview(state, ActionDraft.new(GameConstants.ACTION_PLAY_CARD, payload))
	if not preview_result.ok or not preview_result.data.can_submit:
		return preview_result
	var quote_result := _card_rules.calculate_cost(state, card_id)
	if not quote_result.ok:
		return quote_result
	var quote: Dictionary = quote_result.data
	var face_result := _card_rules.resolve_face(state, card_id)
	if not face_result.ok:
		return face_result
	var face: Dictionary = face_result.data
	var card: Dictionary = state.card_by_id[card_id]
	var focus_before: int = int(state.player.get("focus", 0))
	var vitality_before: int = int(state.player.get("vitality", 0))
	state.player.focus = focus_before - int(quote.cost)
	state.player.vitality = vitality_before - int(quote.vitality_cost)
	if int(quote.cost) > 0:
		_add_event(
			events,
			"focus_changed",
			str(state.player.get("entity_id", "")),
			[str(state.player.get("entity_id", ""))],
			{
				"before": focus_before,
				"after": state.player.focus,
				"delta": state.player.focus - focus_before,
				"reason": "card_payment",
			}
		)
	if int(quote.vitality_cost) > 0:
		_add_event(
			events,
			"vitality_changed",
			str(state.player.get("entity_id", "")),
			[str(state.player.get("entity_id", ""))],
			{
				"before": vitality_before,
				"after": state.player.vitality,
				"delta": state.player.vitality - vitality_before,
				"reason": "payment",
			}
		)
	state.zones.hand.erase(card_id)
	state.zones.resolving.append(card_id)
	var owner_key := str(card.get("origin_card_id", ""))
	if owner_key.is_empty():
		owner_key = card_id
	var limit: Variant = face.get("limit")
	if typeof(limit) == TYPE_DICTIONARY:
		var counter_key := BattleState.counter_key(
			StringName(str(limit.get("per", ""))), owner_key, &"play_card"
		)
		state.counters[counter_key] = int(state.counters.get(counter_key, 0)) + 1
	var played_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_ROUND, "played:" + str(face.get("id", "")), &"played"
	)
	state.counters[played_key] = int(state.counters.get(played_key, 0)) + 1
	if str(face.get("type", "")) == "work":
		var work_played_key := BattleState.counter_key(
			GameConstants.COUNTER_SCOPE_ROUND, "played:work", &"played"
		)
		state.counters[work_played_key] = int(state.counters.get(work_played_key, 0)) + 1
	for source: Dictionary in quote.get("sources", []):
		var counter_key := str(source.get("counter_key", ""))
		state.counters[counter_key] = int(state.counters.get(counter_key, 0)) + 1
		_add_event(
			events,
			"relic_triggered",
			str(source.get("relic_id", "")),
			[card_id],
			{
				"relic_id": str(source.get("relic_id", "")),
				"hook_index": int(source.get("hook_index", 0)),
				"at": "cost_quote",
			},
		)
	var target_ids: Array[String] = []
	for target_id in payload.get("target_ids", []):
		target_ids.append(str(target_id))
	if face.get("target") == "all_tasks":
		for task: Dictionary in state.tasks:
			var task_id := str(task.get("task_id", ""))
			if (
				int(task.get("eligible_round", 1)) <= state.round_index
				and not target_ids.has(task_id)
			):
				target_ids.append(task_id)
	var effects := _visible_effects(face)
	state.resolution = {
		"card_instance_id": card_id,
		"definition_id": str(face.get("id", "")),
		"card_type": str(face.get("type", "")),
		"first_work_card":
		(
			str(face.get("type", "")) == "work"
			and (
				int(
					state.counters.get(
						BattleState.counter_key(
							GameConstants.COUNTER_SCOPE_ROUND, "played:work", &"played"
						),
						0
					)
				)
				== 1
			)
		),
		"effects": effects,
		"cursor": 0,
		"target_ids": target_ids,
		"choice": null,
		"choice_counts": {},
		"exhaust": bool(face.get("exhaust", false)) or face.get("type") == "ability",
		"discarded_in_resolution": [],
		"replace_unit_id": str(payload.get("replace_unit_id", "")),
		"all_tasks": face.get("target") == "all_tasks",
		"locked_target_ids": target_ids.duplicate(),
	}
	_add_event(
		events,
		"card_played",
		card_id,
		[card_id],
		{
			"definition_id": str(face.get("id", "")),
			"focus_cost": int(quote.cost),
			"vitality_cost": int(quote.vitality_cost),
		}
	)
	return GameResult.success(true)


func _end_turn(
	state: BattleState, payload: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if state.phase != "player_action":
		return _failure(
			GameConstants.ERROR_WRONG_PHASE,
			"error.battle.end_turn_wrong_phase",
			{"phase": state.phase},
		)
	for key in payload:
		if key != "retained_card_ids":
			return _invalid_input(
				"end_turn payload has an unknown field", {"path": "payload.%s" % key}
			)
	if payload.get("retained_card_ids", []) is not Array:
		return _invalid_input(
			"retained_card_ids must be an array", {"path": "payload.retained_card_ids"}
		)
	var retained: Array = []
	for card_id in state.retained_card_ids:
		if state.zones.hand.has(card_id):
			retained.append(card_id)
	var selected_retained: Array = []
	for card_id in payload.get("retained_card_ids", []):
		if (
			typeof(card_id) != TYPE_STRING
			or not state.zones.hand.has(card_id)
			or retained.has(card_id)
			or selected_retained.has(card_id)
		):
			return _failure(
				GameConstants.ERROR_INVALID_TARGET,
				"error.battle.retained_card_invalid",
				{"card_id": str(card_id)},
			)
		selected_retained.append(card_id)
	var ruleset_result := _loaded_ruleset()
	if not ruleset_result.ok:
		return ruleset_result
	if selected_retained.size() > int(ruleset_result.data.battle.get("base_retention_count", 0)):
		return _failure(GameConstants.ERROR_INVALID_TARGET, "error.battle.retention_limit", {})
	retained.append_array(selected_retained)
	var phase_result := _set_phase(state, events, "ally_action")
	if not phase_result.ok:
		return phase_result
	_clear_expiring_statuses(state, "player_action_end", events)
	var acting_unit_ids := _ordered_unit_ids(state)
	for unit_id in acting_unit_ids:
		var unit_index := _unit_index(state, unit_id)
		if unit_index < 0:
			continue
		var unit: Dictionary = state.units[unit_index]
		var support_result := _apply_unit_support(state, unit, events)
		if not support_result.ok:
			return support_result
		if not bool(unit.get("support_replaces_cooperation", false)):
			var task_id := str(unit.get("target_id", ""))
			var task_index := _task_index(state, task_id)
			if (
				task_index < 0
				or int(state.tasks[task_index].get("eligible_round", 1)) > state.round_index
			):
				task_id = _first_eligible_task(state)
				task_index = _task_index(state, task_id)
			if task_index >= 0:
				var task: Dictionary = state.tasks[task_index]
				var before := int(task.work_remaining)
				var shield_before := int(task.get("shield", 0))
				var cooperation := int(unit.get("cooperation", 0))
				var shield_loss := mini(shield_before, cooperation)
				task.shield = shield_before - shield_loss
				task.work_remaining = maxi(0, before - (cooperation - shield_loss))
				_add_event(
					events,
					"completion_applied",
					unit_id,
					[task_id],
					{
						"amount": cooperation,
						"shield_before": shield_before,
						"shield_after": int(task.get("shield", 0)),
						"work_before": before,
						"work_after": int(task.work_remaining),
						"segment_index": 0,
					}
				)
				if int(task.work_remaining) == 0:
					_advance_or_remove_task(state, task_index, events)
				_check_battle_outcome(state, events)
				if state.phase == "finished":
					return GameResult.success(null)
		unit_index = _unit_index(state, unit_id)
		if unit_index < 0:
			continue
		unit = state.units[unit_index]
		unit.actions_taken = int(unit.get("actions_taken", 0)) + 1
		var vitality_before := int(unit.get("vitality", 0))
		var unit_vitality_cost := int(
			ruleset_result.data.battle.get("unit_action_vitality_cost", 1)
		)
		unit.vitality = maxi(0, vitality_before - unit_vitality_cost)
		if unit.vitality == 0:
			state.units.remove_at(unit_index)
			_remove_holder_statuses(state, unit_id)
			_add_event(
				events,
				"unit_departed",
				unit_id,
				[unit_id],
				{"definition_id": str(unit.definition_id), "reason": "exhausted"}
			)
		_check_battle_outcome(state, events)
		if state.phase == "finished":
			return GameResult.success(null)
	phase_result = _set_phase(state, events, "discard")
	if not phase_result.ok:
		return phase_result
	for card_id in state.zones.hand.duplicate():
		if retained.has(card_id):
			continue
		state.zones.hand.erase(card_id)
		state.zones.discard.append(card_id)
		_add_event(
			events,
			"card_discarded",
			"",
			[card_id],
			{
				"definition_id": str(state.card_by_id[card_id].definition_id),
				"from_zone": "hand",
				"to_zone": "discard"
			}
		)
	state.retained_card_ids.clear()
	phase_result = _set_phase(state, events, "enemy_prepare")
	if not phase_result.ok:
		return phase_result
	for task: Dictionary in state.tasks:
		task.shield = 0
	phase_result = _set_phase(state, events, "enemy_skill")
	if not phase_result.ok:
		return phase_result
	for task_index in state.tasks.size():
		var task: Dictionary = state.tasks[task_index]
		if int(task.get("eligible_round", 1)) > state.round_index:
			continue
		var intent: Dictionary = task.get("intent_snapshot", {})
		var skill_result := _execute_intent_skill(state, task_index, intent, rng, events)
		if not skill_result.ok:
			return skill_result
		if state.phase == "finished":
			return GameResult.success(null)
	phase_result = _set_phase(state, events, "enemy_pressure")
	if not phase_result.ok:
		return phase_result
	for task: Dictionary in state.tasks:
		if int(task.get("eligible_round", 1)) > state.round_index:
			continue
		var intent: Dictionary = task.get("intent_snapshot", {})
		var pressure := int(intent.get("pressure", 0))
		var extra := _status_stacks(state, "extra_requirements", str(task.get("task_id", "")))
		var pressure_rules: Dictionary = ruleset_result.data.statuses.get("extra_requirements", {})
		pressure += extra * int(pressure_rules.get("pressure_per_stack", 0))
		var times := maxi(1, int(intent.get("pressure_times", 1)))
		for segment_index in times:
			if pressure > 0:
				_apply_pressure(
					state, pressure, bool(intent.get("pressure_all", false)), events, segment_index
				)
				if state.phase == "finished":
					return GameResult.success(null)
	phase_result = _set_phase(state, events, "round_end")
	if not phase_result.ok:
		return phase_result
	if state.scene is Dictionary:
		var scene_definition := _catalog.get_definition(
			"scene", str(state.scene.get("definition_id", ""))
		)
		if scene_definition.ok:
			var scene_effects: Array = scene_definition.data.get("round_end_effects", [])
			var scene_result := _execute_effect_list(
				state, scene_effects, str(state.scene.get("scene_id", "")), [], rng, events
			)
			if not scene_result.ok:
				return scene_result
		_clear_expiring_statuses(state, "round_end", events)
		_check_battle_outcome(state, events)
		if state.phase == "finished":
			return GameResult.success(null)
	var ddl_before := state.ddl
	state.ddl = maxi(0, state.ddl - 1)
	_add_event(events, "ddl_ticked", "", [], {"before": ddl_before, "after": state.ddl})
	if state.ddl == 0 and not state.tasks.is_empty():
		_finish_battle(state, "lost", "deadline_expired", events)
		return GameResult.success(null)
	var previous_round := state.round_index
	state.round_index += 1
	for unit: Dictionary in state.units:
		unit.relax = 0
	for task: Dictionary in state.tasks:
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if definition.ok:
			var phase := _phase_definition(definition.data, str(task.get("phase_key", "")))
			var intents: Array = phase.get("intents", [])
			if not intents.is_empty():
				var cursor := (int(task.get("intent_cursor", 0)) + 1) % intents.size()
				task.intent_cursor = cursor
				task.intent_snapshot = intents[cursor].duplicate(true)
				task.shield = int(task.intent_snapshot.get("shield", 0))
	_add_event(events, "round_started", "", [], {"round_index": state.round_index})
	return _run_player_prepare(state, ruleset_result.data, previous_round, rng, events)


func _execute_effect_list(
	state: BattleState,
	effects: Array,
	source_id: String,
	target_ids: Array,
	rng: RandomSource,
	events: Array[RuleEvent],
) -> GameResult:
	var previous_resolution: Variant = state.resolution
	var stable_targets: Array[String] = []
	for target_id in target_ids:
		stable_targets.append(str(target_id))
	state.resolution = {
		"card_instance_id": source_id,
		"definition_id": "",
		"effects": [],
		"cursor": 0,
		"target_ids": stable_targets,
		"choice": null,
		"choice_counts": {},
		"discarded_in_resolution": [],
		"all_tasks": false,
		"context_target_id": str(target_ids.front()) if not target_ids.is_empty() else "",
	}
	for effect: Dictionary in effects:
		var result := _execute_card_effect(state, effect, rng, events)
		if not result.ok:
			state.resolution = previous_resolution
			return result
		if typeof(result.data) == TYPE_DICTIONARY:
			state.resolution = previous_resolution
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY,
				"battle.effect.choice_context_not_ready",
				{"source_id": source_id, "op": str(effect.get("op", ""))},
			)
		if state.phase == "finished":
			break
	state.resolution = previous_resolution
	return GameResult.success(null)


func _execute_intent_skill(
	state: BattleState,
	task_index: int,
	intent: Dictionary,
	rng: RandomSource,
	events: Array[RuleEvent],
) -> GameResult:
	var task_id := str(state.tasks[task_index].get("task_id", ""))
	var task := state.tasks[task_index]
	if intent.has("shield"):
		task.shield = int(task.get("shield", 0)) + int(intent.shield)
	if intent.has("extra_requirements"):
		var extra := _gain_status_on_target(
			state,
			{
				"status": "extra_requirements",
				"stacks": int(intent.extra_requirements),
				"target": "task"
			},
			task_id,
			events,
		)
		if not extra.ok:
			return extra
	if intent.has("work_restore"):
		var before := int(task.get("work_remaining", 0))
		task.work_remaining = mini(
			int(task.get("work_max", before)), before + int(intent.work_restore)
		)
		_add_event(
			events,
			"work_restored",
			task_id,
			[task_id],
			{"before": before, "after": int(task.work_remaining)},
		)
	if intent.has("gain_status"):
		var status: Dictionary = intent.gain_status
		var target_id := str(state.player.get("entity_id", ""))
		match str(status.get("target", "")):
			"task":
				target_id = task_id
			"unit":
				return _failure(
					GameConstants.ERROR_ENGINE_NOT_READY,
					"battle.intent.unit_target_not_ready",
					{"task_id": task_id}
				)
		var gained := _gain_status_on_target(
			state,
			{
				"status": str(status.get("status", "")),
				"stacks": int(status.get("stacks", 1)),
				"target": str(status.target)
			},
			target_id,
			events,
		)
		if not gained.ok:
			return gained
	if intent.has("add_card"):
		var add_result := _add_intent_cards(state, task_id, intent.add_card, events)
		if not add_result.ok:
			return add_result
	_add_event(
		events,
		"enemy_skill",
		task_id,
		[task_id],
		{"intent_index": int(intent.get("index", 0)), "text_key": str(intent.get("text_key", ""))},
	)
	return GameResult.success(null)


func _add_intent_cards(
	state: BattleState, source_id: String, spec: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var definition_id := str(spec.get("card", ""))
	var definition_result := _catalog.get_definition("card", definition_id)
	if not definition_result.ok:
		return _content_reference_error("card", definition_id, "intent.add_card.card")
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	var zone := str(spec.get("zone", "discard"))
	for _index in int(spec.get("count", 0)):
		var card_id := _new_instance_id(state, "c")
		var card := {
			"card_id": card_id,
			"definition_id": definition_id,
			"origin_card_id": "",
			"upgrade_level": 0,
			"temporary_modifiers": {},
		}
		state.card_by_id[card_id] = card
		var destination := zone
		if zone == "hand" and state.zones.hand.size() >= int(ruleset.data.battle.hand_limit):
			destination = "discard"
		state.zones[destination].append(card_id)
		_add_event(
			events,
			"card_drawn" if destination == "hand" else "card_discarded",
			source_id,
			[card_id],
			{"definition_id": definition_id, "from_zone": "generated", "to_zone": destination},
		)
	return GameResult.success(null)


func _run_player_prepare(
	state: BattleState,
	ruleset: Dictionary,
	previous_round: int,
	rng: RandomSource,
	events: Array[RuleEvent]
) -> GameResult:
	var phase_result := _set_phase(state, events, "player_prepare")
	if not phase_result.ok:
		return phase_result
	if state.round_index != previous_round:
		_reset_round_counters(state)
	state.player.relax = 0
	var anxiety := _status_stacks(state, "anxiety", "player")
	var focus_before := int(state.player.get("focus", 0))
	var focus_amount := maxi(0, int(ruleset.battle.focus_per_round) - anxiety)
	state.player.focus = mini(int(ruleset.battle.focus_cap), focus_amount)
	_add_event(
		events,
		"focus_changed",
		str(state.player.get("entity_id", "")),
		[str(state.player.get("entity_id", ""))],
		{
			"before": focus_before,
			"after": state.player.focus,
			"delta": state.player.focus - focus_before,
			"reason": "player_prepare"
		},
	)
	_clear_expiring_statuses(state, "prepare", events)
	var relic_result := _run_relic_hooks(state, "round_start", {}, rng, events)
	if not relic_result.ok:
		return relic_result
	for unit: Dictionary in state.units:
		unit.relax = 0
	if (
		state.scene is Dictionary
		and int(state.scene.get("established_round", previous_round)) < state.round_index
	):
		var scene_result := _run_scene_prepare(state, rng, events)
		if not scene_result.ok:
			return scene_result
	var phase_to_draw := _set_phase(state, events, "draw")
	if not phase_to_draw.ok:
		return phase_to_draw
	var draw_amount := maxi(
		0, int(ruleset.battle.draw_per_round) - _status_stacks(state, "procrastination", "player")
	)
	_clear_expiring_statuses(state, "draw", events)
	_draw_cards(state, draw_amount, rng, events)
	relic_result = _run_relic_hooks(state, "draw", {}, rng, events)
	if not relic_result.ok:
		return relic_result
	return _set_phase(state, events, "player_action")


func _run_scene_prepare(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var scene_id := str(state.scene.get("scene_id", ""))
	var definition_id := str(state.scene.get("definition_id", ""))
	var definition_result := _catalog.get_definition("scene", definition_id)
	if not definition_result.ok:
		return _content_reference_error("scene", definition_id, "battle.scene.definition_id")
	var definition: Dictionary = definition_result.data
	var counter_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_BATTLE, definition_id, &"prepare"
	)
	var trigger_count := int(state.counters.get(counter_key, 0))
	var limit := int(definition.get("battle_limit", 2147483647))
	if trigger_count >= limit:
		return GameResult.success(null)
	state.counters[counter_key] = trigger_count + 1
	var effects: Array = definition.get("prepare_effects", [])
	if definition.has("prepare_random"):
		var pending: Variant = state.scene.get("pending_random_result")
		if typeof(pending) != TYPE_ARRAY:
			return _failure(
				GameConstants.ERROR_RESOLUTION_ERROR,
				"battle.scene.random_preview_missing",
				{"scene_id": scene_id}
			)
		effects = pending
	var effect_result := _execute_effect_list(state, effects, scene_id, [], rng, events)
	if not effect_result.ok:
		return effect_result
	if definition.has("prepare_random"):
		var next_result := _draw_scene_prepare_result(definition, rng)
		if not next_result.ok:
			return next_result
		state.scene.pending_random_result = next_result.data
	var anxiety_every := int(definition.get("anxiety_after_every", 0))
	if anxiety_every > 0 and (trigger_count + 1) % anxiety_every == 0:
		var status_result := _gain_status_on_target(
			state,
			{"status": "anxiety", "stacks": 1, "target": "player"},
			str(state.player.get("entity_id", "")),
			events,
		)
		if not status_result.ok:
			return status_result
	return GameResult.success(null)


func _draw_scene_prepare_result(definition: Dictionary, rng: RandomSource) -> GameResult:
	var options: Array = definition.get("prepare_random", {}).get("options", [])
	if options.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID, "battle.scene.random_options_empty", {}
		)
	var result := rng.draw_int(GameConstants.RNG_STREAM_BATTLE, 0, options.size() - 1)
	if not result.ok:
		return result
	return GameResult.success(options[int(result.data)].duplicate(true))


func _ordered_unit_ids(state: BattleState) -> Array[String]:
	var units: Array = state.units.duplicate(true)
	units.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return int(a.get("entered_order", 0)) < int(b.get("entered_order", 0))
	)
	var result: Array[String] = []
	for unit: Dictionary in units:
		result.append(str(unit.get("unit_id", "")))
	return result


func _set_ally_target(
	state: BattleState, payload: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	for key in payload:
		if key not in ["unit_instance_id", "task_instance_id"]:
			return _invalid_input(
				"set_ally_target has an unknown field", {"path": "payload.%s" % key}
			)
	if not payload.has_all(["unit_instance_id", "task_instance_id"]):
		return _invalid_input("set_ally_target requires unit and task", {"path": "payload"})
	if state.phase != "player_action" or state.resolution != null:
		return _failure(
			GameConstants.ERROR_WRONG_PHASE,
			"error.battle.target_wrong_phase",
			{"phase": state.phase}
		)
	var unit_index := _unit_index(state, str(payload.unit_instance_id))
	var task_index := _task_index(state, str(payload.task_instance_id))
	if unit_index < 0 or task_index < 0:
		return _failure(GameConstants.ERROR_INVALID_TARGET, "error.battle.ally_target_invalid", {})
	state.units[unit_index].target_id = str(payload.task_instance_id)
	_add_event(
		events,
		"coop_target_set",
		str(payload.unit_instance_id),
		[str(payload.task_instance_id)],
		{"task_id": str(payload.task_instance_id)}
	)
	return GameResult.success(null)


func _apply_unit_support(
	state: BattleState, unit: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var support: Dictionary = unit.get("support", {"kind": "none"})
	var kind := str(support.get("kind", "none"))
	var amount := int(support.get("amount", 0))
	match kind:
		"none":
			return GameResult.success(null)
		"relax":
			state.player.relax = int(state.player.get("relax", 0)) + amount
		"self_relax":
			unit.relax = int(unit.get("relax", 0)) + amount
		"heal":
			var before := int(state.player.get("vitality", 0))
			state.player.vitality = mini(int(state.player.get("max_vitality", 0)), before + amount)
			_add_event(
				events,
				"vitality_changed",
				str(unit.unit_id),
				[str(state.player.get("entity_id", ""))],
				{
					"before": before,
					"after": state.player.vitality,
					"delta": state.player.vitality - before,
					"reason": "heal"
				}
			)
		"cleanse_or_relax":
			var player_id := str(state.player.get("entity_id", ""))
			var status_id := str(support.get("status", ""))
			var status_index := _status_index(state, status_id, player_id)
			if status_index >= 0:
				state.statuses.remove_at(status_index)
			else:
				state.player.relax = (
					int(state.player.get("relax", 0)) + int(support.get("fallback_relax", 0))
				)
		"gain_status_on_actions":
			var every := maxi(1, int(support.get("every", 1)))
			if (int(unit.get("actions_taken", 0)) + 1) % every == 0:
				var status := _gain_status_on_target(
					state,
					{"status": support.status, "stacks": support.stacks},
					str(unit.unit_id),
					events
				)
				if not status.ok:
					return status
		_:
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY,
				"battle.unit.support_not_ready",
				{"kind": kind}
			)
	return GameResult.success(null)


func _clear_expiring_statuses(state: BattleState, timing: String, events: Array[RuleEvent]) -> void:
	var ids: Array = (
		{
			"player_action_end": ["drowsiness"],
			"round_end": ["inspiration"],
			"prepare": ["anxiety"],
			"draw": ["procrastination"],
		}
		. get(timing, [])
	)
	for index in range(state.statuses.size() - 1, -1, -1):
		var status: Dictionary = state.statuses[index]
		if ids.has(str(status.get("status_id", ""))):
			_add_event(
				events,
				"status_removed",
				"",
				[str(status.get("target_id", ""))],
				{
					"status_definition_id": str(status.status_id),
					"before": int(status.get("stacks", 0)),
					"after": 0,
					"amount": int(status.get("stacks", 0)),
					"reason": timing
				}
			)
			state.statuses.remove_at(index)


func _phase_definition(task_definition: Dictionary, phase_key: String) -> Dictionary:
	for phase: Dictionary in task_definition.get("phases", []):
		if str(phase.get("phase_key", "")) == phase_key:
			return phase
	return {}


func _apply_pressure(
	state: BattleState, amount: int, all_targets: bool, events: Array[RuleEvent], segment_index: int
) -> void:
	if all_targets:
		_apply_pressure_to_player(state, amount, events, segment_index)
		for unit: Dictionary in state.units.duplicate(true):
			var index := _unit_index(state, str(unit.unit_id))
			if index >= 0:
				var before := int(state.units[index].vitality)
				state.units[index].vitality = maxi(0, before - amount)
				if int(state.units[index].vitality) == 0:
					var unit_id := str(state.units[index].unit_id)
					var definition_id := str(state.units[index].definition_id)
					state.units.remove_at(index)
					_remove_holder_statuses(state, unit_id)
					_add_event(
						events,
						"unit_departed",
						unit_id,
						[unit_id],
						{"definition_id": definition_id, "reason": "exhausted"}
					)
		_check_battle_outcome(state, events)
		return
	var target := _first_guard(state)
	if not target.is_empty():
		var index := _unit_index(state, target)
		var before := int(state.units[index].vitality)
		state.units[index].vitality = maxi(0, before - amount)
		_add_event(
			events,
			"pressure_applied",
			"",
			[target],
			{
				"amount": amount,
				"vitality_before": before,
				"vitality_after": int(state.units[index].vitality),
				"segment_index": segment_index
			}
		)
		if state.units[index].vitality == 0:
			_remove_holder_statuses(state, target)
			state.units.remove_at(index)
			_add_event(
				events,
				"unit_departed",
				target,
				[target],
				{"definition_id": "", "reason": "exhausted"}
			)
	else:
		_apply_pressure_to_player(state, amount, events, segment_index)


func _apply_pressure_to_player(
	state: BattleState, amount: int, events: Array[RuleEvent], segment_index: int
) -> void:
	var relax_before := int(state.player.get("relax", 0))
	var absorbed := mini(relax_before, amount)
	state.player.relax = relax_before - absorbed
	var vitality_before := int(state.player.get("vitality", 0))
	state.player.vitality = maxi(0, vitality_before - (amount - absorbed))
	_add_event(
		events,
		"pressure_applied",
		"",
		[str(state.player.get("entity_id", ""))],
		{
			"amount": amount,
			"relax_before": relax_before,
			"relax_after": state.player.relax,
			"vitality_before": vitality_before,
			"vitality_after": state.player.vitality,
			"segment_index": segment_index
		}
	)
	_check_battle_outcome(state, events)


func _first_guard(state: BattleState) -> String:
	var guards: Array[String] = []
	for status: Dictionary in state.statuses:
		var unit_id := str(status.get("target_id", ""))
		if status.get("status_id") == "guard" and _unit_index(state, unit_id) >= 0:
			guards.append(unit_id)
	guards.sort_custom(
		func(a: String, b: String):
			return (
				int(state.units[_unit_index(state, a)].get("entered_order", 0))
				< int(state.units[_unit_index(state, b)].get("entered_order", 0))
			)
	)
	return guards.front() if not guards.is_empty() else ""


func _continue_resolution(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	while typeof(state.resolution) == TYPE_DICTIONARY:
		if state.phase == "finished":
			return _finalize_card_resolution(state, rng, events)
		var resolution: Dictionary = state.resolution
		var effects: Array = resolution.get("effects", [])
		var cursor: int = int(resolution.get("cursor", 0))
		if cursor >= effects.size():
			var finalized := _finalize_card_resolution(state, rng, events)
			if not finalized.ok:
				return finalized
			continue
		var effect: Variant = effects[cursor]
		if typeof(effect) != TYPE_DICTIONARY:
			return _resolution_error("effect must be an object", {"effect_index": cursor})
		resolution.cursor = cursor + 1
		var outcome := _execute_card_effect(state, effect, rng, events)
		if not outcome.ok:
			return outcome
		if typeof(outcome.data) == TYPE_DICTIONARY:
			var choice: Dictionary = outcome.data
			resolution.choice = choice
			state.phase = "awaiting_choice"
			_add_event(
				events,
				"choice_requested",
				str(resolution.get("card_instance_id", "")),
				[],
				{
					"choice_id": choice.choice_id,
					"kind": choice.kind,
					"min_count": choice.min_count,
					"max_count": choice.max_count,
				}
			)
			return GameResult.success(choice.duplicate(true))
	return GameResult.success(null)


func _execute_card_effect(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var op := str(effect.get("op", ""))
	var amount := int(effect.get("amount", effect.get("stacks", 0)))
	match op:
		"complete":
			_apply_completion(state, effect, rng, events)
			return GameResult.success(null)
		"relax":
			var before: int = int(state.player.get("relax", 0))
			state.player.relax = before + maxi(0, amount)
			return GameResult.success(null)
		"gain_focus":
			var ruleset := _loaded_ruleset()
			if not ruleset.ok:
				return ruleset
			var cap: int = int(ruleset.data.battle.focus_cap)
			var focus_before: int = int(state.player.get("focus", 0))
			state.player.focus = mini(cap, focus_before + maxi(0, amount))
			if state.player.focus != focus_before:
				_add_event(
					events,
					"focus_changed",
					str(state.resolution.get("card_instance_id", "")),
					[str(state.player.get("entity_id", ""))],
					{
						"before": focus_before,
						"after": state.player.focus,
						"delta": state.player.focus - focus_before,
						"reason": "effect",
					}
				)
			return GameResult.success(null)
		"heal":
			var maximum: int = int(state.player.get("max_vitality", 0))
			var vitality_before: int = int(state.player.get("vitality", 0))
			state.player.vitality = mini(maximum, vitality_before + maxi(0, amount))
			if state.player.vitality != vitality_before:
				_add_event(
					events,
					"vitality_changed",
					str(state.resolution.get("card_instance_id", "")),
					[str(state.player.get("entity_id", ""))],
					{
						"before": vitality_before,
						"after": state.player.vitality,
						"delta": state.player.vitality - vitality_before,
						"reason": "heal",
					}
				)
			return GameResult.success(null)
		"lose_vitality":
			var before: int = int(state.player.get("vitality", 0))
			state.player.vitality = maxi(0, before - maxi(0, amount))
			_add_event(
				events,
				"vitality_changed",
				str(state.resolution.get("card_instance_id", "")),
				[str(state.player.get("entity_id", ""))],
				{
					"before": before,
					"after": state.player.vitality,
					"delta": state.player.vitality - before,
					"reason": "loss",
				}
			)
			_check_battle_outcome(state, events)
			return GameResult.success(null)
		"draw":
			var extra_draw := (
				int(effect.get("per_discarded", 0))
				* int(state.resolution.get("choice_counts", {}).get("discard", 0))
			)
			_draw_cards(state, maxi(0, amount + extra_draw), rng, events)
			return GameResult.success(null)
		"discard", "recall_from_discard", "retain_hand_card":
			return _start_card_choice(state, effect, op)
		"remove_status":
			if effect.get("category") == "negative":
				return _start_card_choice(state, effect, op)
			return _remove_status(state, effect, events)
		"summon_unit":
			return _summon_unit(state, effect, rng, events)
		"establish_scene":
			return _establish_scene(state, effect, rng, events)
		"gain_status":
			return _gain_status(state, effect, events)
		_:
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY, "battle.effect.not_ready", {"op": op}
			)


func _apply_completion(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> void:
	var resolution: Dictionary = state.resolution
	var targets: Array = resolution.get("target_ids", [])
	if bool(resolution.get("all_tasks", false)):
		targets = resolution.get("locked_target_ids", []).duplicate()
	elif targets.is_empty():
		var fallback := _first_eligible_task(state)
		if not fallback.is_empty():
			targets = [fallback]
	var requested: int = maxi(0, int(effect.get("amount", 0)))
	var segment_index := int(resolution.get("completion_segment_index", 0))
	resolution.completion_segment_index = segment_index + 1
	var applies_work_statuses := (
		str(resolution.get("card_type", "")) == "work" and segment_index == 0
	)
	var ruleset := _loaded_ruleset()
	if ruleset.ok and applies_work_statuses:
		requested += (
			_status_stacks(state, "inspiration", "player")
			* int(ruleset.data.statuses.get("inspiration", {}).get("completion_per_stack", 0))
		)
		requested -= (
			_status_stacks(state, "drowsiness", "player")
			* int(
				ruleset.data.statuses.get("drowsiness", {}).get("completion_penalty_per_stack", 0)
			)
		)
		if bool(resolution.get("first_work_card", false)):
			for relic_id in state.relics:
				var relic_result := _catalog.get_definition("relic", relic_id)
				if not relic_result.ok:
					continue
				var relic: Dictionary = relic_result.data
				if not relic.has("modifiers") or not relic.modifiers.has("work_flat_bonus"):
					continue
				var limit: Dictionary = relic.get("limit", {})
				var counter_key := BattleState.counter_key(
					StringName(str(limit.get("per", "round"))),
					"relic_modifier:%s:work_flat_bonus" % relic_id,
					&"modifier"
				)
				if int(state.counters.get(counter_key, 0)) >= int(limit.get("times", 1)):
					continue
				state.counters[counter_key] = int(state.counters.get(counter_key, 0)) + 1
				requested += int(relic.modifiers.work_flat_bonus)
				_add_event(
					events,
					"relic_triggered",
					relic_id,
					[str(resolution.get("card_instance_id", ""))],
					{"relic_id": relic_id, "at": "work_flat_bonus"}
				)
		if state.scene is Dictionary:
			var scene_result := _catalog.get_definition(
				"scene", str(state.scene.get("definition_id", ""))
			)
			if scene_result.ok:
				requested += int(
					scene_result.data.get("modifiers", {}).get("work_first_segment_bonus", 0)
				)
		var inspiration_index := _status_index(
			state, "inspiration", str(state.player.get("entity_id", ""))
		)
		if inspiration_index >= 0:
			var inspiration_before := int(state.statuses[inspiration_index].get("stacks", 0))
			state.statuses.remove_at(inspiration_index)
			_add_event(
				events,
				"status_removed",
				str(resolution.get("card_instance_id", "")),
				[str(state.player.get("entity_id", ""))],
				{
					"status_definition_id": "inspiration",
					"before": inspiration_before,
					"after": 0,
					"amount": inspiration_before,
					"reason": "work_card_resolved",
				},
			)
	requested = maxi(0, requested)
	var bonus_if: Variant = effect.get("bonus_if")
	if typeof(bonus_if) == TYPE_DICTIONARY and _completion_bonus_matches(state, bonus_if):
		requested += maxi(0, int(bonus_if.get("amount", 0)))
	for task_id in targets:
		var task_index := _task_index(state, str(task_id))
		if task_index < 0:
			continue
		var task: Dictionary = state.tasks[task_index]
		var before_shield: int = int(task.get("shield", 0))
		var before_work: int = int(task.get("work_remaining", 0))
		var shield_loss: int = mini(before_shield, requested)
		var applied: int = requested - shield_loss
		task.shield = before_shield - shield_loss
		task.work_remaining = maxi(0, before_work - applied)
		_add_event(
			events,
			"completion_applied",
			str(resolution.get("card_instance_id", "")),
			[str(task_id)],
			{
				"amount": requested,
				"shield_before": before_shield,
				"shield_after": task.shield,
				"work_before": before_work,
				"work_after": task.work_remaining,
				"segment_index": 0,
			}
		)
		if int(task.work_remaining) == 0:
			_advance_or_remove_task(state, task_index, events)
			_check_battle_outcome(state, events)
			if state.phase == "finished":
				return
		_check_battle_outcome(state, events)


func _completion_bonus_matches(state: BattleState, condition: Dictionary) -> bool:
	for key in condition:
		match key:
			"amount":
				continue
			"ddl_lte":
				if state.ddl > int(condition.ddl_lte):
					return false
			"status":
				var required: String = str(condition.status)
				var minimum: int = int(condition.get("min_stacks", 1))
				if _status_stacks(state, required, "player") < minimum:
					return false
			"played_definition":
				var played_key := BattleState.counter_key(
					GameConstants.COUNTER_SCOPE_ROUND,
					"played:" + str(condition.played_definition),
					&"played"
				)
				if int(state.counters.get(played_key, 0)) < 1:
					return false
			"scope", "min_stacks":
				continue
			_:
				return false
	return true


func _advance_or_remove_task(state: BattleState, task_index: int, events: Array[RuleEvent]) -> void:
	var previous: Dictionary = state.tasks[task_index]
	var definition_result := _catalog.get_definition("task", str(previous.get("definition_id", "")))
	if not definition_result.ok:
		return
	var phases: Array = definition_result.data.get("phases", [])
	_remove_holder_statuses(state, str(previous.task_id))
	var current_index := -1
	for index in phases.size():
		if str(phases[index].get("phase_key", "")) == str(previous.get("phase_key", "")):
			current_index = index
			break
	if current_index >= 0 and current_index + 1 < phases.size():
		var next_phase: Dictionary = phases[current_index + 1]
		var next_id := _new_instance_id(state, "t")
		var intent: Dictionary = {}
		var intents: Array = next_phase.get("intents", [])
		if not intents.is_empty():
			intent = intents[0].duplicate(true)
		var next_task := {
			"task_id": next_id,
			"definition_id": previous.definition_id,
			"phase_key": next_phase.phase_key,
			"work_remaining": int(next_phase.work_max),
			"work_max": int(next_phase.work_max),
			"shield": int(intent.get("shield", 0)),
			"intent_cursor": 0,
			"intent_snapshot": intent,
			"entered_order": state.next_creation_order,
			"eligible_round": state.round_index,
		}
		state.tasks.remove_at(task_index)
		_register_source(state, next_id, "task", str(previous.definition_id))
		state.tasks.insert(task_index, next_task)
		_add_event(
			events,
			"task_advanced",
			str(previous.task_id),
			[str(previous.task_id), next_id],
			{
				"old_task_id": str(previous.task_id),
				"new_task_id": next_id,
				"phase_key": next_phase.phase_key
			}
		)
		return
	state.tasks.remove_at(task_index)
	_add_event(
		events,
		"task_completed",
		str(previous.task_id),
		[str(previous.task_id)],
		{"definition_id": str(previous.definition_id), "phase_key": str(previous.phase_key)}
	)


func _check_battle_outcome(state: BattleState, events: Array[RuleEvent]) -> void:
	if state.phase == "finished":
		return
	if int(state.player.get("vitality", 0)) <= 0:
		_finish_battle(state, "lost", "vitality_depleted", events)
	elif state.tasks.is_empty():
		_finish_battle(state, "won", "tasks_completed", events)


func _summon_unit(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var definition_id := str(effect.get("unit", ""))
	var definition_result := _catalog.get_definition("unit", definition_id)
	if not definition_result.ok:
		return _content_reference_error("unit", definition_id, "effect.unit")
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	var limit := int(ruleset.data.battle.get("unit_slots", 0))
	if state.units.size() >= limit:
		var replacement := str(state.resolution.get("replace_unit_id", ""))
		if replacement.is_empty():
			return _failure(
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.replacement_required",
				{"field": "replace_unit_id"},
			)
		var old_index := _unit_index(state, replacement)
		if old_index < 0:
			return _failure(
				GameConstants.ERROR_INVALID_TARGET,
				"error.play.invalid_replacement",
				{"replace_unit_id": replacement},
			)
		var old_unit: Dictionary = state.units[old_index]
		state.units.remove_at(old_index)
		_remove_holder_statuses(state, replacement)
		_add_event(
			events,
			"unit_departed",
			replacement,
			[replacement],
			{"definition_id": str(old_unit.get("definition_id", "")), "reason": "switch"},
		)
	var unit_id := _new_instance_id(state, "u")
	var unit: Dictionary = definition_result.data.duplicate(true)
	unit["unit_id"] = unit_id
	unit["definition_id"] = definition_id
	unit["vitality"] = int(unit.get("vitality", 1)) + int(effect.get("vitality_bonus", 0))
	unit["max_vitality"] = unit["vitality"]
	unit["cooperation"] = int(unit.get("cooperation", 0)) + int(effect.get("cooperation_bonus", 0))
	unit["entered_order"] = state.next_creation_order
	unit["actions_taken"] = 0
	unit["target_id"] = ""
	state.units.append(unit)
	_register_source(state, unit_id, "unit", definition_id)
	_add_event(
		events,
		"unit_summoned",
		unit_id,
		[unit_id],
		{"definition_id": definition_id, "entered_order": unit.entered_order},
	)
	if bool(unit.get("guard", false)):
		var guard_result := _gain_status_on_target(
			state, {"status": "guard", "stacks": 1, "target": "unit"}, unit_id, events
		)
		if not guard_result.ok:
			return guard_result
	var entry_result := _execute_effect_list(
		state, unit.get("entry_effects", []), unit_id, [unit_id], rng, events
	)
	if not entry_result.ok:
		return entry_result
	return GameResult.success(null)


func _establish_scene(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var definition_id := str(effect.get("scene", ""))
	var definition_result := _catalog.get_definition("scene", definition_id)
	if not definition_result.ok:
		return _content_reference_error("scene", definition_id, "effect.scene")
	var definition: Dictionary = definition_result.data
	var scene_id := _new_instance_id(state, "s")
	var pending: Variant = null
	if definition.has("prepare_random"):
		var initial_result := _draw_scene_prepare_result(definition, rng)
		if not initial_result.ok:
			return initial_result
		pending = initial_result.data
	if state.scene != null:
		_add_event(
			events,
			"scene_replaced",
			str(state.scene.get("scene_id", "")),
			[str(state.scene.get("scene_id", "")), scene_id],
			{
				"old_definition_id": str(state.scene.get("definition_id", "")),
				"new_definition_id": definition_id,
			},
		)
	state.scene = {
		"scene_id": scene_id,
		"definition_id": definition_id,
		"established_round": state.round_index,
		"pending_random_result": pending,
	}
	_register_source(state, scene_id, "scene", definition_id)
	_add_event(
		events,
		"scene_established",
		scene_id,
		[scene_id],
		{"definition_id": definition_id, "pending_random_result": pending},
	)
	return GameResult.success(null)


func _unit_index(state: BattleState, unit_id: String) -> int:
	for index in state.units.size():
		if str(state.units[index].get("unit_id", "")) == unit_id:
			return index
	return -1


func _remove_holder_statuses(state: BattleState, holder_id: String) -> void:
	for index in range(state.statuses.size() - 1, -1, -1):
		if str(state.statuses[index].get("target_id", "")) == holder_id:
			state.statuses.remove_at(index)


func _finish_battle(
	state: BattleState, result: String, reason: String, events: Array[RuleEvent]
) -> void:
	var outcome := {
		"battle_id": state.battle_id,
		"result": result,
		"reason": reason,
		"remaining_vitality": int(state.player.get("vitality", 0)),
		"summary": {},
	}
	state.outcome = outcome
	state.phase = "finished"
	_add_event(
		events,
		"battle_finished",
		"",
		[],
		{"result": result, "reason": reason, "remaining_vitality": outcome.remaining_vitality}
	)


func _draw_cards(
	state: BattleState, amount: int, rng: RandomSource, events: Array[RuleEvent]
) -> void:
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return
	var hand_limit: int = int(ruleset.data.battle.hand_limit)
	while amount > 0 and state.zones.hand.size() < hand_limit:
		if state.zones.draw.is_empty():
			if state.zones.discard.is_empty():
				return
			var discarded: Array[String] = []
			for card_id in state.zones.discard:
				discarded.append(str(card_id))
			var shuffled := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, discarded)
			if not shuffled.ok:
				return
			state.zones.draw = shuffled.data
			state.zones.discard.clear()
		var card_id: String = state.zones.draw.pop_front()
		state.zones.hand.append(card_id)
		var card: Dictionary = state.card_by_id[card_id]
		_add_event(
			events,
			"card_drawn",
			"",
			[card_id],
			{"definition_id": str(card.definition_id), "from_zone": "draw", "to_zone": "hand"}
		)
		amount -= 1


func _start_card_choice(state: BattleState, effect: Dictionary, op: String) -> GameResult:
	var resolution: Dictionary = state.resolution
	var candidates: Array = []
	var kind := op
	match op:
		"discard":
			kind = "discard"
			for card_id in state.zones.hand:
				if str(card_id) != str(resolution.get("card_instance_id", "")):
					candidates.append(_card_candidate(state, str(card_id)))
		"recall_from_discard":
			kind = "recall"
			for card_id in state.zones.discard:
				candidates.append(_card_candidate(state, str(card_id)))
		"retain_hand_card":
			kind = "retain"
			for card_id in state.zones.hand:
				if str(card_id) != str(resolution.get("card_instance_id", "")):
					candidates.append(_card_candidate(state, str(card_id)))
		"remove_status":
			kind = "remove_status"
			for status: Dictionary in state.statuses:
				if (
					str(status.get("target_id", "")) == str(state.player.get("entity_id", ""))
					and (
						str(status.get("expiry", ""))
						in ["next_prepare", "next_draw", "next_player_action_end"]
					)
					and not candidates.any(
						func(candidate: Dictionary): return candidate.id == status.status_id
					)
				):
					candidates.append(
						{
							"id": str(status.status_id),
							"label_key": "status.%s.name" % status.status_id
						}
					)
	var maximum := mini(int(effect.get("amount", 1)), candidates.size())
	if op == "remove_status":
		maximum = mini(1, candidates.size())
	if op == "discard" and bool(effect.get("up_to", false)):
		if candidates.is_empty():
			return GameResult.success(null)
	else:
		maximum = mini(maximum, int(effect.get("amount", 1)))
		if maximum <= 0:
			return GameResult.success(null)
	if op == "recall_from_discard" and maximum < int(effect.get("amount", 1)):
		return _failure(
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.no_recall_target",
			{"required": int(effect.get("amount", 1)), "available": candidates.size()}
		)
	var minimum := 0 if op == "discard" and bool(effect.get("up_to", false)) else maximum
	var choice_id := _new_instance_id(state, "ch")
	return (
		GameResult
		. success(
			{
				"choice_id": choice_id,
				"kind": kind,
				"prompt_key": "choice.battle.%s" % kind,
				"candidates": candidates,
				"min_count": minimum,
				"max_count": maximum,
				"source_card_id": str(resolution.get("card_instance_id", "")),
				"effect_amount": int(effect.get("amount", 1)),
			}
		)
	)


func _confirm_effect_choice(
	state: BattleState, payload: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	for key in payload:
		if key not in ["choice_id", "selected_ids"]:
			return _invalid_input(
				"confirm_choice payload has an unknown field", {"path": "payload.%s" % key}
			)
	if not payload.has_all(["choice_id", "selected_ids"]):
		return _invalid_input(
			"confirm_choice requires choice_id and selected_ids", {"path": "payload"}
		)
	if typeof(payload.choice_id) != TYPE_STRING or typeof(payload.selected_ids) != TYPE_ARRAY:
		return _invalid_input("confirm_choice field types are invalid", {"path": "payload"})
	var resolution: Dictionary = state.resolution
	var choice: Variant = resolution.get("choice")
	if typeof(choice) != TYPE_DICTIONARY or str(choice.get("choice_id", "")) != payload.choice_id:
		return _failure(
			GameConstants.ERROR_INVALID_TARGET,
			"error.battle.choice_id_invalid",
			{"choice_id": payload.choice_id}
		)
	var selected: Array = payload.selected_ids
	if selected.size() < int(choice.min_count) or selected.size() > int(choice.max_count):
		return _invalid_input(
			"selected_ids count is outside choice bounds", {"path": "payload.selected_ids"}
		)
	var candidate_ids: Array[String] = []
	for candidate in choice.candidates:
		candidate_ids.append(str(candidate.get("id", "")))
	var unique := {}
	for card_id in selected:
		if typeof(card_id) != TYPE_STRING or not candidate_ids.has(card_id) or unique.has(card_id):
			return _failure(
				GameConstants.ERROR_INVALID_TARGET,
				"error.battle.choice_candidate_invalid",
				{"selected_id": str(card_id)}
			)
		unique[card_id] = true
	var kind := str(choice.kind)
	match kind:
		"discard":
			for card_id in selected:
				state.zones.hand.erase(card_id)
				state.zones.discard.append(card_id)
				resolution.discarded_in_resolution.append(card_id)
				_add_event(
					events,
					"card_discarded",
					str(choice.source_card_id),
					[card_id],
					{
						"definition_id": str(state.card_by_id[card_id].definition_id),
						"from_zone": "hand",
						"to_zone": "discard",
					}
				)
			resolution.choice_counts[kind] = selected.size()
		"recall":
			for card_id in selected:
				state.zones.discard.erase(card_id)
				if state.zones.hand.size() < int(_loaded_ruleset().data.battle.hand_limit):
					state.zones.hand.append(card_id)
				else:
					state.zones.discard.append(card_id)
		"retain":
			var retained: Array = resolution.get("retained_card_ids", [])
			retained.append_array(selected)
			resolution.retained_card_ids = retained
		"remove_status":
			if not selected.is_empty():
				var status_index := _status_index(
					state, str(selected[0]), str(state.player.get("entity_id", ""))
				)
				if status_index >= 0:
					var status: Dictionary = state.statuses[status_index]
					var before := int(status.get("stacks", 0))
					var after := maxi(0, before - int(choice.get("effect_amount", 1)))
					if after == 0:
						state.statuses.remove_at(status_index)
					else:
						status.stacks = after
					_add_event(
						events,
						"status_removed",
						str(choice.get("source_card_id", "")),
						[str(state.player.get("entity_id", ""))],
						{
							"status_definition_id": str(selected[0]),
							"before": before,
							"after": after,
							"amount": before - after,
							"reason": "effect",
						}
					)
	resolution.choice = null
	state.phase = "player_action"
	_add_event(
		events,
		"choice_confirmed",
		str(choice.source_card_id),
		selected,
		{"choice_id": str(choice.choice_id), "kind": kind, "selected_ids": selected.duplicate()}
	)
	return GameResult.success(true)


func _card_candidate(state: BattleState, card_id: String) -> Dictionary:
	var card: Dictionary = state.card_by_id.get(card_id, {})
	var definition_id := str(card.get("definition_id", ""))
	var label := definition_id
	var definition := _catalog.get_definition("card", definition_id)
	if definition.ok:
		label = str(definition.data.get("name_key", label))
	return {"id": card_id, "label_key": label, "preview": {"definition_id": definition_id}}


func _gain_status(state: BattleState, effect: Dictionary, events: Array[RuleEvent]) -> GameResult:
	var target := str(effect.get("target", "player"))
	var target_id := str(state.player.get("entity_id", ""))
	if target in ["self", "unit", "task"] and typeof(state.resolution) == TYPE_DICTIONARY:
		target_id = str(state.resolution.get("context_target_id", ""))
		if target_id.is_empty():
			target_id = str(state.resolution.get("target_ids", [""]).front())
		if target_id.is_empty() and target == "self":
			target_id = str(state.player.get("entity_id", ""))
	elif target == "task":
		target_id = ""
	return _gain_status_on_target(state, effect, target_id, events)


func _gain_status_on_target(
	state: BattleState, effect: Dictionary, target_id: String, events: Array[RuleEvent]
) -> GameResult:
	var status_id := str(effect.get("status", ""))
	var target := str(effect.get("target", "player"))
	var stacks := maxi(1, int(effect.get("stacks", 1)))
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	if status_id != "guard" and not ruleset.data.statuses.has(status_id):
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.status.definition_missing",
			{"status": status_id, "target": target}
		)
	var status_rule: Dictionary = ruleset.data.statuses.get(status_id, {"cap": 1})
	var index := _status_index(state, status_id, target_id)
	var before := 0
	if index >= 0:
		before = int(state.statuses[index].get("stacks", 0))
	var after := mini(int(status_rule.get("cap", before + stacks)), before + stacks)
	if status_id == "guard":
		after = 1
	if index >= 0:
		state.statuses[index].stacks = after
	else:
		var instance_id := _new_instance_id(state, "st")
		(
			state
			. statuses
			. append(
				{
					"status_id": status_id,
					"instance_id": instance_id,
					"source_id":
					(
						str(state.resolution.get("card_instance_id", ""))
						if typeof(state.resolution) == TYPE_DICTIONARY
						else ""
					),
					"target_id": target_id,
					"stacks": after,
					"expiry": str(status_rule.get("duration_policy", "battle")),
				}
			)
		)
		_register_source(state, instance_id, "status", status_id)
	_add_event(
		events,
		"status_gained",
		(
			str(state.resolution.get("card_instance_id", ""))
			if typeof(state.resolution) == TYPE_DICTIONARY
			else ""
		),
		[target_id],
		{
			"status_definition_id": status_id,
			"before": before,
			"after": after,
			"amount": after - before,
			"reason": "effect",
		}
	)
	return GameResult.success(true)


func _task_index(state: BattleState, task_id: String) -> int:
	for index in state.tasks.size():
		if str(state.tasks[index].get("task_id", "")) == task_id:
			return index
	return -1


func _remove_status(state: BattleState, effect: Dictionary, events: Array[RuleEvent]) -> GameResult:
	if effect.get("category") == "negative":
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.effect.status_choice_not_ready",
			{"op": "remove_status", "category": "negative"}
		)
	var status_id := str(effect.get("status", ""))
	var target := str(effect.get("target", "player"))
	var target_id := (
		str(state.player.get("entity_id", ""))
		if target in ["player", "self"]
		else str(state.resolution.get("target_ids", [""]).front())
	)
	var index := _status_index(state, status_id, target_id)
	if index < 0:
		return GameResult.success(true)
	var before: int = int(state.statuses[index].get("stacks", 0))
	var after: int = maxi(0, before - maxi(0, int(effect.get("amount", 0))))
	state.statuses[index].stacks = after
	if after == 0:
		state.statuses.remove_at(index)
	_add_event(
		events,
		"status_removed",
		str(state.resolution.get("card_instance_id", "")),
		[target_id],
		{
			"status_definition_id": status_id,
			"before": before,
			"after": after,
			"amount": before - after,
			"reason": "effect",
		}
	)
	return GameResult.success(true)


func _status_index(state: BattleState, status_id: String, target_id: String) -> int:
	for index in state.statuses.size():
		var status: Dictionary = state.statuses[index]
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == target_id
		):
			return index
	return -1


func _status_stacks(state: BattleState, status_id: String, target: String) -> int:
	var target_id := str(state.player.get("entity_id", "")) if target == "player" else target
	var index := _status_index(state, status_id, target_id)
	return int(state.statuses[index].get("stacks", 0)) if index >= 0 else 0


func _first_eligible_task(state: BattleState) -> String:
	for task: Dictionary in state.tasks:
		if (
			int(task.get("work_remaining", 0)) > 0
			and int(task.get("eligible_round", 1)) <= state.round_index
		):
			return str(task.get("task_id", ""))
	return ""


func _loaded_ruleset() -> GameResult:
	if _catalog == null or _catalog.get_info() == null:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.catalog.not_ready",
			{"operation": "ruleset"}
		)
	var info: ContentInfo = _catalog.get_info()
	return _catalog.get_definition("ruleset", info.ruleset_id)


func _finalize_card_resolution(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var resolution: Dictionary = state.resolution
	var card_id := str(resolution.get("card_instance_id", ""))
	var definition_id := str(resolution.get("definition_id", ""))
	var face := {"id": definition_id, "type": str(resolution.get("card_type", ""))}
	state.zones.resolving.erase(card_id)
	var destination := "exhaust" if bool(resolution.get("exhaust", false)) else "discard"
	state.zones[destination].append(card_id)
	for retained_id in resolution.get("retained_card_ids", []):
		if state.zones.hand.has(retained_id) and not state.retained_card_ids.has(retained_id):
			state.retained_card_ids.append(str(retained_id))
	_add_event(
		events,
		"card_resolved",
		card_id,
		[card_id],
		{"definition_id": definition_id, "destination": destination}
	)
	state.resolution = null
	if state.phase != "finished":
		state.phase = "player_action"
	var relic_result := _run_relic_hooks(state, "card_resolved", face, rng, events)
	if not relic_result.ok:
		return relic_result
	var passive_result := _run_character_passive(state, face, rng, events)
	if not passive_result.ok:
		return passive_result
	return GameResult.success(null)


func _run_relic_hooks(
	state: BattleState, at: String, face: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	for relic_id in state.relics:
		var relic_result := _catalog.get_definition("relic", relic_id)
		if not relic_result.ok:
			return relic_result
		var hooks: Array = relic_result.data.get("hooks", [])
		for hook_index in hooks.size():
			var hook: Dictionary = hooks[hook_index]
			if str(hook.get("at", "")) != at:
				continue
			if hook.has("card_type") and str(hook.card_type) != str(face.get("type", "")):
				continue
			if hook.has("definition_id") and str(hook.definition_id) != str(face.get("id", "")):
				continue
			if hook.has("rounds") and not hook.rounds.has(state.round_index):
				continue
			var limit: Variant = hook.get("limit")
			if typeof(limit) == TYPE_DICTIONARY:
				var key := BattleState.counter_key(
					StringName(str(limit.get("per", "battle"))),
					"relic_hook:%s:%d" % [relic_id, hook_index],
					&"hook"
				)
				if int(state.counters.get(key, 0)) >= int(limit.get("times", 1)):
					continue
				state.counters[key] = int(state.counters.get(key, 0)) + 1
			_add_event(
				events,
				"relic_triggered",
				relic_id,
				[],
				{"relic_id": relic_id, "hook_index": hook_index, "at": at}
			)
			var result := _execute_effect_list(
				state,
				hook.get("effects", []),
				"relic:%s:%d" % [relic_id, hook_index],
				[],
				rng,
				events
			)
			if not result.ok:
				return result
	return GameResult.success(null)


func _run_character_passive(
	state: BattleState, face: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var character_result := _catalog.get_definition("character", state.character_id)
	if not character_result.ok:
		return character_result
	var passive: Dictionary = character_result.data.get("passive", {})
	var trigger := str(passive.get("trigger", ""))
	var card_type := str(face.get("type", ""))
	if (
		(trigger == "work_card_resolved" and card_type != "work")
		or (trigger == "cooperation_card_resolved" and card_type != "cooperation")
	):
		return GameResult.success(null)
	var trigger_key := (
		"work_resolved" if trigger == "work_card_resolved" else "cooperation_resolved"
	)
	var count_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_ROUND, str(passive.get("id", "")), StringName(trigger_key)
	)
	var trigger_count := int(state.counters.get(count_key, 0)) + 1
	state.counters[count_key] = trigger_count
	if trigger_count % int(passive.get("count", 1)) != 0:
		return GameResult.success(null)
	var limit: Dictionary = passive.get("limit", {})
	var use_key := BattleState.counter_key(
		StringName(str(limit.get("per", "round"))),
		"passive:%s" % str(passive.get("id", "")),
		&"passive"
	)
	if int(state.counters.get(use_key, 0)) >= int(limit.get("times", 1)):
		return GameResult.success(null)
	state.counters[use_key] = int(state.counters.get(use_key, 0)) + 1
	_add_event(
		events,
		"passive_triggered",
		state.character_id,
		[str(state.player.get("entity_id", ""))],
		{"passive_id": str(passive.get("id", "")), "trigger": trigger}
	)
	return _execute_effect_list(
		state, passive.get("effects", []), "passive:%s" % passive.get("id", ""), [], rng, events
	)


func _reset_round_counters(state: BattleState) -> void:
	for key in state.counters.keys():
		var scope := str(key).split("|", false, 1)[0]
		if (
			scope == String(GameConstants.COUNTER_SCOPE_ROUND)
			or scope == String(GameConstants.COUNTER_SCOPE_INSTANCE_ROUND)
		):
			state.counters.erase(key)


func _resolution_error(message: String, details: Dictionary) -> GameResult:
	return _failure(
		GameConstants.ERROR_RESOLUTION_ERROR,
		"battle.resolution.invalid",
		{"message": message}.merged(details)
	)


func begin(input: Dictionary) -> GameResult:
	if _catalog == null or _catalog.get_info() == null:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY, "battle.catalog.not_ready", {"operation": "begin"}
		)
	var validation := _validate_input(input)
	if not validation.ok:
		return validation
	var context: Dictionary = validation.data
	var rng := RandomSource.new("battle_begin")
	var restored: GameResult = rng.restore_state(input.rng_state)
	if not restored.ok:
		return restored

	var encounter: Dictionary = context.encounter
	var ruleset: Dictionary = context.ruleset
	var battle_rules: Dictionary = ruleset.battle
	var difficulty_rules: Dictionary = ruleset.difficulty_overrides[input.get(
		"difficulty", "normal"
	)]
	var state := (
		BattleState
		. new(
			{
				"battle_id": input.battle_id,
				"node_id": input.get("node_id", ""),
				"encounter_id": input.encounter_id,
				"character_id": input.character_id,
				"difficulty": input.get("difficulty", "normal"),
				"exam_flags": encounter.exam_flags,
				"phase": "player_prepare",
				"round_index": 1,
				"ddl":
				maxi(
					int(battle_rules.minimum_ddl),
					int(encounter.base_ddl) + int(difficulty_rules.ddl_offset)
				),
				"player":
				{
					"entity_id": "",
					"vitality":
					input.get("vitality", input.get("max_vitality", ruleset.run.starting_vitality)),
					"max_vitality": input.get("max_vitality", ruleset.run.starting_vitality),
					"relax": 0,
					"focus": 0,
				},
				"relics": context.relics,
				"zones": {"draw": [], "hand": [], "discard": [], "exhaust": [], "resolving": []},
				"units": [],
				"tasks": [],
				"statuses": [],
				"scene": null,
				"counters": {},
				"resolution": null,
				"next_creation_order": 1,
				"next_instance_seq": 1,
				"source_registry": {},
			}
		)
	)
	var player_id := _new_instance_id(state, "p")
	state.player.entity_id = player_id
	_register_source(state, player_id, "character", input.character_id)
	for relic_id in context.relics:
		var relic_instance_id := _new_instance_id(state, "r")
		_register_source(state, relic_instance_id, "relic", relic_id)

	var card_ids: Array[String] = []
	for index in context.cards.size():
		var permanent: Dictionary = context.cards[index]
		var card_id := _new_instance_id(state, "c")
		var card := {
			"card_id": card_id,
			"definition_id": permanent.definition_id,
			"origin_card_id": permanent.card_id,
			"upgrade_level": permanent.upgrade_level,
			"temporary_modifiers": {},
		}
		state.card_by_id[card_id] = card
		card_ids.append(card_id)

	for member_id in encounter.members:
		var task_definition: Dictionary = context.tasks[member_id]
		var initial_phase: Dictionary = task_definition.phases[0]
		var intent: Dictionary = initial_phase.intents[0].duplicate(true)
		var task_id := _new_instance_id(state, "t")
		var task_state := {
			"task_id": task_id,
			"definition_id": member_id,
			"phase_key": initial_phase.phase_key,
			"work_remaining": initial_phase.work_max,
			"work_max": initial_phase.work_max,
			"shield": intent.get("shield", 0),
			"intent_cursor": 0,
			"intent_snapshot": intent,
			"entered_order": state.next_creation_order,
			"eligible_round": 1,
		}
		_register_source(state, task_id, "task", member_id)
		state.tasks.append(task_state)

	var shuffled := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, card_ids)
	if not shuffled.ok:
		return shuffled
	state.zones.draw = shuffled.data
	var events: Array[RuleEvent] = []
	var prepare_result := _run_player_prepare(state, ruleset, 0, rng, events)
	if not prepare_result.ok:
		return prepare_result
	var result_snapshot: RandomSnapshot = rng.export_state()
	return GameResult.success(
		BattleStep.new(state, events, null, null, true, result_snapshot.to_dictionary())
	)


func _validate_input(input: Dictionary) -> GameResult:
	var allowed := [
		"battle_id",
		"node_id",
		"encounter_id",
		"character_id",
		"difficulty",
		"vitality",
		"max_vitality",
		"cards",
		"relics",
		"rng_state",
	]
	for key in input:
		if not allowed.has(key):
			return _invalid_input("input.%s is unknown" % key, {"path": "input.%s" % key})
	for key in ["battle_id", "encounter_id", "character_id", "cards", "relics", "rng_state"]:
		if not input.has(key):
			return _invalid_input("input.%s is required" % key, {"path": "input.%s" % key})
	for key in ["battle_id", "encounter_id", "character_id"]:
		if typeof(input[key]) != TYPE_STRING or not _is_safe_id(input[key]):
			return _invalid_input(
				"input.%s must be a non-empty safe id" % key, {"path": "input.%s" % key}
			)
	if input.has("node_id") and typeof(input.node_id) != TYPE_STRING:
		return _invalid_input("input.node_id must be a string", {"path": "input.node_id"})
	var difficulty: Variant = input.get("difficulty", "normal")
	if typeof(difficulty) != TYPE_STRING or not ["relaxed", "normal", "hard"].has(difficulty):
		return _invalid_input("input.difficulty is invalid", {"path": "input.difficulty"})
	if typeof(input.rng_state) != TYPE_DICTIONARY:
		return _invalid_input(
			"input.rng_state must be a complete snapshot object", {"path": "input.rng_state"}
		)
	if typeof(input.cards) != TYPE_ARRAY or input.cards.is_empty():
		return _invalid_input("input.cards must be a non-empty array", {"path": "input.cards"})
	if typeof(input.relics) != TYPE_ARRAY:
		return _invalid_input("input.relics must be an array", {"path": "input.relics"})

	var info: ContentInfo = _catalog.get_info()
	var ruleset_result := _catalog.get_definition("ruleset", info.ruleset_id)
	if not ruleset_result.ok:
		return _content_reference_error("ruleset", info.ruleset_id, "manifest.ruleset_id")
	var ruleset: Dictionary = ruleset_result.data
	if not ruleset.difficulty_overrides.has(difficulty):
		return _invalid_input(
			"difficulty is not configured by the loaded Ruleset",
			{"path": "input.difficulty", "difficulty": difficulty}
		)
	var maximum: Variant = input.get("max_vitality", ruleset.run.starting_vitality)
	var vitality: Variant = input.get("vitality", maximum)
	if typeof(maximum) != TYPE_INT or maximum < 1:
		return _invalid_input(
			"input.max_vitality must be a positive integer", {"path": "input.max_vitality"}
		)
	if typeof(vitality) != TYPE_INT or vitality < 1 or vitality > maximum:
		return _invalid_input(
			"input.vitality must be an integer from 1 through max_vitality",
			{"path": "input.vitality", "max_vitality": maximum}
		)

	var character_result := _catalog.get_definition("character", input.character_id)
	if not character_result.ok:
		return _content_reference_error("character", input.character_id, "input.character_id")
	var encounter_result := _catalog.get_definition("encounter", input.encounter_id)
	if not encounter_result.ok:
		return _content_reference_error("encounter", input.encounter_id, "input.encounter_id")
	var encounter: Dictionary = encounter_result.data
	if encounter.has("scaling"):
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.encounter.scaling_not_supported",
			{"path": "encounter.%s.scaling" % input.encounter_id}
		)
	if encounter.members.is_empty():
		return _content_reference_error("task", "", "encounter.%s.members" % input.encounter_id)
	var tasks := {}
	for index in encounter.members.size():
		var task_id: String = encounter.members[index]
		var task_result := _catalog.get_definition("task", task_id)
		if not task_result.ok:
			return _content_reference_error(
				"task", task_id, "encounter.%s.members[%d]" % [input.encounter_id, index]
			)
		var task_definition: Dictionary = task_result.data
		if task_definition.kind != encounter.kind:
			return _content_reference_error(
				"task", task_id, "encounter.%s.kind" % input.encounter_id
			)
		tasks[task_id] = task_definition

	var permanent_ids := {}
	var cards: Array[Dictionary] = []
	for index in input.cards.size():
		var permanent: Variant = input.cards[index]
		var location := "input.cards[%d]" % index
		if typeof(permanent) != TYPE_DICTIONARY:
			return _invalid_input("%s must be an object" % location, {"path": location})
		if (
			permanent.size() != 3
			or not permanent.has_all(["card_id", "definition_id", "upgrade_level"])
		):
			return _invalid_input(
				"%s must contain only card_id, definition_id and upgrade_level" % location,
				{"path": location}
			)
		if (
			typeof(permanent.card_id) != TYPE_STRING
			or not _is_safe_id(permanent.card_id)
			or permanent_ids.has(permanent.card_id)
		):
			return _invalid_input(
				"%s.card_id must be unique and safe" % location, {"path": location + ".card_id"}
			)
		if (
			typeof(permanent.definition_id) != TYPE_STRING
			or not _is_safe_id(permanent.definition_id)
		):
			return _invalid_input(
				"%s.definition_id must be a safe id" % location,
				{"path": location + ".definition_id"}
			)
		if (
			typeof(permanent.upgrade_level) != TYPE_INT
			or permanent.upgrade_level < 0
			or permanent.upgrade_level > 1
		):
			return _invalid_input(
				"%s.upgrade_level must be 0 or 1" % location, {"path": location + ".upgrade_level"}
			)
		permanent_ids[permanent.card_id] = true
		var card_result := _catalog.get_definition("card", permanent.definition_id)
		if not card_result.ok:
			return _content_reference_error(
				"card", permanent.definition_id, location + ".definition_id"
			)
		if permanent.upgrade_level == 1 and card_result.data.get("upgrade", {}).is_empty():
			return _content_reference_error(
				"card", permanent.definition_id, location + ".upgrade_level"
			)
		cards.append(permanent.duplicate(true))

	var relic_ids: Array[String] = []
	for index in input.relics.size():
		var relic_id: Variant = input.relics[index]
		if typeof(relic_id) != TYPE_STRING or not _is_safe_id(relic_id):
			return _invalid_input(
				"input.relics[%d] must be a safe definition id" % index,
				{"path": "input.relics[%d]" % index}
			)
		if relic_ids.has(relic_id):
			return _invalid_input(
				"input.relics contains a duplicate id", {"path": "input.relics[%d]" % index}
			)
		var relic_result := _catalog.get_definition("relic", relic_id)
		if not relic_result.ok:
			return _content_reference_error("relic", relic_id, "input.relics[%d]" % index)
		relic_ids.append(relic_id)
	for relic_id in relic_ids:
		var relic_result := _catalog.get_definition("relic", relic_id)
		if not relic_result.ok:
			return relic_result
		for hook: Dictionary in relic_result.data.get("hooks", []):
			# Shop hooks are handled by the run layer, not executed in combat.
			if str(hook.get("at", "")) == "shop_price":
				continue
			if (
				str(hook.get("at", ""))
				not in ["round_start", "draw", "card_resolved", "cost_quote"]
			):
				return _failure(
					GameConstants.ERROR_ENGINE_NOT_READY,
					"battle.relic.hook_not_supported",
					{"relic_id": relic_id, "at": str(hook.get("at", ""))},
				)

	return (
		GameResult
		. success(
			{
				"encounter": encounter,
				"ruleset": ruleset,
				"cards": cards,
				"tasks": tasks,
				"relics": relic_ids,
			}
		)
	)


func _draw_initial_hand(
	state: BattleState, amount: int, hand_limit: int, events: Array[RuleEvent]
) -> void:
	while amount > 0 and state.zones.hand.size() < hand_limit and not state.zones.draw.is_empty():
		var card_id: String = state.zones.draw.pop_front()
		state.zones.hand.append(card_id)
		var card: Dictionary = state.card_by_id[card_id]
		_add_event(
			events,
			"card_drawn",
			"",
			[card_id],
			{"definition_id": card.definition_id, "from_zone": "draw", "to_zone": "hand"}
		)
		amount -= 1

	if state.phase != "finished":
		state.phase = "player_action"


func _set_phase(state: BattleState, events: Array[RuleEvent], next_phase: String) -> GameResult:
	if next_phase not in BattlePhaseFlow.PHASE_ORDER:
		return _failure(
			GameConstants.ERROR_RESOLUTION_ERROR,
			"battle.phase.unknown",
			{"phase": next_phase},
		)
	var previous := state.phase
	state.phase = next_phase
	_add_event(events, "phase_changed", "", [], {"before": previous, "after": next_phase})
	return GameResult.success(null)


func _add_event(
	events: Array[RuleEvent], type: String, source_id: String, target_ids: Array, data: Dictionary
) -> void:
	var stable_targets: Array[String] = []
	for target_id in target_ids:
		stable_targets.append(str(target_id))
	events.append(RuleEvent.new(events.size(), StringName(type), source_id, stable_targets, data))


func _new_instance_id(state: BattleState, prefix: String) -> String:
	var instance_id := "%s|%s%d" % [state.battle_id, prefix, state.next_instance_seq]
	state.next_instance_seq += 1
	return instance_id


func _register_source(
	state: BattleState, instance_id: String, kind: String, definition_id: String
) -> void:
	state.source_registry[instance_id] = {
		"kind": kind,
		"definition_id": definition_id,
		"creation_order": state.next_creation_order,
	}
	state.next_creation_order += 1


func _content_reference_error(kind: String, id: String, path: String) -> GameResult:
	return _failure(
		GameConstants.ERROR_CONTENT_INVALID,
		"battle.content.reference_invalid",
		{"kind": kind, "id": id, "path": path}
	)


func _invalid_input(message: String, details: Dictionary) -> GameResult:
	return _failure(
		GameConstants.ERROR_INVALID_ARGUMENT,
		"battle.input.invalid",
		{"message": message}.merged(details)
	)


func _failure(code: StringName, message_key: String, details: Dictionary) -> GameResult:
	return GameResult.failure(ApiError.new(code, message_key, details))


func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 100:
		return false
	for index in value.length():
		var codepoint := value.unicode_at(index)
		var is_letter := (
			(codepoint >= 65 and codepoint <= 90) or (codepoint >= 97 and codepoint <= 122)
		)
		var is_digit := codepoint >= 48 and codepoint <= 57
		var is_separator := codepoint == 95 or codepoint == 124
		if not (is_letter or is_digit or is_separator):
			return false
	var first := value.unicode_at(0)
	return (first >= 65 and first <= 90) or (first >= 97 and first <= 122) or first == 95
