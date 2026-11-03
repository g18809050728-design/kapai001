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
	if bool(face.get("v3", false)):
		for requirement: Variant in face.get("requirements", []):
			if not _v3_condition(state, requirement):
				_add_preview_error(
					result,
					GameConstants.ERROR_INVALID_TARGET,
					"error.play.requirement_invalid",
					{"card_instance_id": card_id}
				)
		var per_turn := int(face.get("limits", {}).get("per_instance_per_turn", 0))
		if per_turn > 0:
			var limit_key := BattleState.counter_key(
				GameConstants.COUNTER_SCOPE_INSTANCE_ROUND, card_id, &"v3_play"
			)
			if int(state.counters.get(limit_key, 0)) >= per_turn:
				_add_preview_error(
					result,
					GameConstants.ERROR_LIMIT_REACHED,
					"error.battle.v3_card_limit",
					{"card_instance_id": card_id}
				)
		if state.character_id == "P02":
			var preview_name := str(face.get("name_key", face.get("id", "")))
			if _v3_paper(state).turn_names.has(preview_name):
				var preview_origin := str(
					state.card_by_id.get(card_id, {}).get("origin_card_id", "")
				)
				var preview_reuse := false
				for entry: Variant in _v3_paper(state).chapters:
					if (
						typeof(entry) == TYPE_DICTIONARY
						and str(entry.get("card_id", "")) == preview_origin
					):
						preview_reuse = true
						break
				if not preview_reuse:
					_add_preview_error(
						result,
						GameConstants.ERROR_INVALID_TARGET,
						"error.play.paper_name_used_turn",
						{"name": preview_name}
					)
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
		var has_taunt := _has_taunting_task(state)
		for task: Dictionary in state.tasks:
			if int(task.get("work_remaining", 0)) <= 0:
				continue
			if int(task.get("eligible_round", 1)) > state.round_index:
				continue
			if has_taunt and not _task_has_taunt(state, str(task.get("task_id", ""))):
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
		var started := _start_card_resolution(working, action.payload, rng, events)
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
	state: BattleState, payload: Dictionary, rng: RandomSource, events: Array[RuleEvent]
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
	if bool(face.get("v3", false)) and state.character_id == "P02":
		var paper_turn_name := str(face.get("name_key", face.get("id", "")))
		if _v3_paper(state).turn_names.has(paper_turn_name):
			var reuse_origin := str(card.get("origin_card_id", ""))
			var is_chapter_reuse := false
			for entry: Variant in _v3_paper(state).chapters:
				if (
					typeof(entry) == TYPE_DICTIONARY
					and str(entry.get("card_id", "")) == reuse_origin
				):
					is_chapter_reuse = true
					break
			if not is_chapter_reuse:
				return GameResult.failure(
					ApiError.new(
						GameConstants.ERROR_INVALID_TARGET,
						"error.play.paper_name_used_turn",
						{"name": paper_turn_name}
					)
				)
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
	var any_played_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_ROUND, "played:any", &"played"
	)
	state.counters[any_played_key] = int(state.counters.get(any_played_key, 0)) + 1
	if int(state.counters[any_played_key]) == 1:
		var discard_result := _random_discard(state, _task_first_card_discard(state), rng, events)
		if not discard_result.ok:
			return discard_result
	var played_type := str(face.get("type", ""))
	if not played_type.is_empty():
		var type_key := BattleState.counter_key(
			GameConstants.COUNTER_SCOPE_BATTLE, "card_type:" + played_type, &"played"
		)
		state.counters[type_key] = int(state.counters.get(type_key, 0)) + 1
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
	var v3_enabled := bool(face.get("v3", false))
	var v3_turn: Dictionary = _v3_turn(state) if v3_enabled else {}
	var v3_battle: Dictionary = _v3_battle(state) if v3_enabled else {}
	var v3_discount := _v3_cost_discount_applies(state, face) if v3_enabled else 0
	var v3_paper_name := ""
	var v3_paper_name_was_used := false
	if v3_enabled and state.character_id == "P02":
		var paper_snapshot := _v3_paper(state)
		var face_definition := _catalog.get_definition("card", str(face.get("id", "")))
		if face_definition.ok:
			v3_paper_name = str(face_definition.data.get("name_key", face.get("id", "")))
			v3_paper_name_was_used = paper_snapshot.used_names.has(v3_paper_name)
	var induced_snapshot: Array = []
	var target_induced: Dictionary = {}
	if v3_enabled:
		for task: Dictionary in state.tasks:
			var task_id := str(task.get("task_id", ""))
			var induced := _status_stacks(state, "induced", task_id)
			if induced > 0:
				induced_snapshot.append({"task_id": task_id, "stacks": induced})
			if target_ids.has(task_id):
				target_induced[task_id] = induced > 0
	state.resolution = {
		"card_instance_id": card_id,
		"definition_id": str(face.get("id", "")),
		"card_type": str(face.get("type", "")),
		"v3": v3_enabled,
		"v3_compound_candidates": [],
		"v3_induced_snapshot": induced_snapshot,
		"v3_target_induced_snapshot": target_induced,
		"v3_link":
		(
			str(face.get("type", "")) == "work"
			and str(v3_turn.get("previous_card_type", "")) == "strategy"
		),
		"v3_previous_card_type": str(v3_turn.get("previous_card_type", "")),
		"v3_previous_card_instance_id": str(v3_turn.get("previous_card_instance_id", "")),
		"v3_previous_card_definition_id": str(v3_turn.get("previous_card_definition_id", "")),
		"v3_instance_was_played_before":
		int(v3_battle.get("instance_plays", {}).get(card_id, 0)) > 0,
		"v3_played_type_counts":
		v3_turn.get("played_types", {}).duplicate(true) if v3_enabled else {},
		"v3_link_work_count": int(v3_turn.get("link_work_count", 0)),
		"v3_base_cost": int(face.get("cost", 0)),
		"v3_cost_discount_applied": v3_discount,
		"v3_paper_name_was_used": v3_paper_name_was_used,
		"v3_paper_name": v3_paper_name,
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
	if bool(face.get("v3", false)) and face.has("ability"):
		var ability_result := _register_v3_ability(state, face, events)
		if not ability_result.ok:
			return ability_result
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
					var advanced := _advance_or_remove_task(state, task_index, events, rng)
					if not advanced.ok:
						return advanced
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
		var shield_def := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if shield_def.ok and bool(shield_def.data.get("shield_persistent", false)):
			continue
		task.shield = 0
	var erosion_window := _v3_erosion_window(state, rng, events)
	if not erosion_window.ok:
		return erosion_window
	if state.phase == "finished":
		return GameResult.success(null)
	phase_result = _set_phase(state, events, "enemy_skill")
	if not phase_result.ok:
		return phase_result
	var pending_summons: Array[Dictionary] = []
	var pending_transforms: Array[Dictionary] = []
	for task_index in state.tasks.size():
		var task: Dictionary = state.tasks[task_index]
		if int(task.get("eligible_round", 1)) > state.round_index:
			continue
		var intent: Dictionary = task.get("intent_snapshot", {})
		var skill_result := _execute_intent_skill(
			state, task_index, intent, rng, events, pending_summons, pending_transforms
		)
		if not skill_result.ok:
			return skill_result
		if state.phase == "finished":
			return GameResult.success(null)
	phase_result = _set_phase(state, events, "enemy_pressure")
	if not phase_result.ok:
		return phase_result
	var pressure_rules: Dictionary = ruleset_result.data.statuses.get("extra_requirements", {})
	var brainstorm_rules: Dictionary = ruleset_result.data.statuses.get("brainstorm", {})
	var pressure_index := 0
	while pressure_index < state.tasks.size():
		var task: Dictionary = state.tasks[pressure_index]
		if int(task.get("eligible_round", 1)) <= state.round_index:
			var task_id := str(task.get("task_id", ""))
			var intent: Dictionary = task.get("intent_snapshot", {})
			var pressure := int(intent.get("pressure", 0))
			var extra := _status_stacks(state, "extra_requirements", task_id)
			pressure += extra * int(pressure_rules.get("pressure_per_stack", 0))
			var brainstorm := _status_stacks(state, "brainstorm", task_id)
			pressure += brainstorm * int(brainstorm_rules.get("pressure_per_stack", 0))
			var per_unit := int(intent.get("pressure_per_unit", 0))
			if per_unit > 0:
				var scaled := per_unit * state.units.size()
				var scaled_cap := int(intent.get("pressure_per_unit_cap", scaled))
				pressure += mini(scaled, maxi(0, scaled_cap))
			var per_vitality := int(intent.get("pressure_per_vitality", 0))
			if per_vitality > 0:
				var step := int(intent.get("pressure_vitality_step", 10))
				pressure += per_vitality * int(int(state.player.get("vitality", 0)) / maxi(1, step))
			if int(task.get("shield", 0)) > 0:
				pressure += int(intent.get("pressure_when_shield", 0))
			var per_card_type: Variant = intent.get("pressure_per_card_type", {})
			if per_card_type is Dictionary:
				for card_type in per_card_type:
					var played_key := BattleState.counter_key(
						GameConstants.COUNTER_SCOPE_BATTLE, "card_type:" + str(card_type), &"played"
					)
					pressure += (
						int(per_card_type[card_type]) * int(state.counters.get(played_key, 0))
					)
			if state.units.is_empty():
				var no_unit_mult := int(intent.get("pressure_no_unit_mult", 100))
				if no_unit_mult != 100:
					pressure = int(ceil(pressure * no_unit_mult / 100.0))
			else:
				var has_unit_mult := int(intent.get("pressure_has_unit_mult", 100))
				if has_unit_mult != 100:
					pressure = int(ceil(pressure * has_unit_mult / 100.0))
			var feeble := _status_stacks(state, "feebleness", task_id)
			if feeble > 0:
				var flat := int(
					ruleset_result.data.statuses.get("feebleness", {}).get("pressure_flat", 1)
				)
				pressure = maxi(0, pressure - feeble * flat)
			if _status_stacks(state, "weakness", task_id) > 0:
				var weakness_percent := int(
					ruleset_result.data.statuses.get("weakness", {}).get("pressure_percent", 75)
				)
				pressure = int(floor(pressure * weakness_percent / 100.0))
			var times := maxi(1, int(intent.get("pressure_times", 1)))
			for segment_index in times:
				if pressure > 0:
					_apply_pressure(
						state,
						pressure,
						bool(intent.get("pressure_all", false)),
						events,
						segment_index
					)
					if state.phase == "finished":
						return GameResult.success(null)
			if bool(intent.get("self_destruct", false)):
				_self_destruct_task(state, pressure_index, events)
				if state.phase == "finished":
					return GameResult.success(null)
				continue
		pressure_index += 1
	_tick_pressure_window_statuses(state, events)
	for pending: Dictionary in pending_transforms:
		var transform_result := _transform_task(
			state, str(pending.get("task_id", "")), pending.get("spec", {}), events
		)
		if not transform_result.ok:
			return transform_result
	for pending: Dictionary in pending_summons:
		var summon_result := _summon_tasks(
			state, str(pending.get("source_id", "")), pending.get("spec", {}), events
		)
		if not summon_result.ok:
			return summon_result
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
		if int(task.get("eligible_round", 1)) >= state.round_index:
			continue
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if definition.ok:
			var phase := _phase_definition(definition.data, str(task.get("phase_key", "")))
			var intents: Array = phase.get("intents", [])
			if not intents.is_empty():
				var cursor := int(task.get("intent_cursor", 0)) + 1
				if str(phase.get("intent_loop", "cycle")) == "clamp":
					cursor = mini(cursor, intents.size() - 1)
				else:
					cursor = cursor % intents.size()
				task.intent_cursor = cursor
				task.intent_snapshot = intents[cursor].duplicate(true)
				task.shield = (_scaled_shield(
					state,
					ruleset_result.data,
					str(task.get("task_id", "")),
					int(task.intent_snapshot.get("shield", 0))
				))
	var self_copy_pending: Array[Dictionary] = []
	for task: Dictionary in state.tasks.duplicate(true):
		var self_copy_def := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if self_copy_def.ok and bool(self_copy_def.data.get("self_copy_every_round", false)):
			self_copy_pending.append(
				{
					"source_id": str(task.get("task_id", "")),
					"spec": {"task": str(task.get("definition_id", "")), "count": 1}
				}
			)
	for pending: Dictionary in self_copy_pending:
		var copy_result := _summon_tasks(state, pending.source_id, pending.spec, events, false)
		if not copy_result.ok:
			return copy_result
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
	pending_summons: Array[Dictionary],
	pending_transforms: Array[Dictionary],
) -> GameResult:
	var task_id := str(state.tasks[task_index].get("task_id", ""))
	var task := state.tasks[task_index]
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	if intent.has("shield"):
		task.shield = (
			int(task.get("shield", 0))
			+ _scaled_shield(state, ruleset.data, task_id, int(intent.shield))
		)
	if intent.has("player_gain_focus"):
		var cap := int(ruleset.data.battle.focus_cap)
		var focus_before := int(state.player.get("focus", 0))
		state.player.focus = mini(cap, focus_before + int(intent.player_gain_focus))
		if state.player.focus != focus_before:
			_add_event(
				events,
				"focus_changed",
				task_id,
				[str(state.player.get("entity_id", ""))],
				{
					"before": focus_before,
					"after": state.player.focus,
					"delta": state.player.focus - focus_before,
					"reason": "intent",
				}
			)
	if intent.has("player_reduce_focus"):
		var reduce_before := int(state.player.get("focus", 0))
		state.player.focus = maxi(0, reduce_before - int(intent.player_reduce_focus))
		if state.player.focus != reduce_before:
			_add_event(
				events,
				"focus_changed",
				task_id,
				[str(state.player.get("entity_id", ""))],
				{
					"before": reduce_before,
					"after": state.player.focus,
					"delta": state.player.focus - reduce_before,
					"reason": "intent",
				}
			)
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
	if intent.has("summon_tasks"):
		var summon_key := BattleState.counter_key(
			GameConstants.COUNTER_SCOPE_BATTLE, task_id, &"summon"
		)
		if int(state.counters.get(summon_key, 0)) == 0:
			state.counters[summon_key] = 1
			for spec: Variant in intent.summon_tasks:
				if typeof(spec) != TYPE_DICTIONARY:
					continue
				pending_summons.append({"source_id": task_id, "spec": spec})
	if intent.has("ddl_bonus"):
		var ddl_before := state.ddl
		state.ddl += int(intent.ddl_bonus)
		_add_event(
			events,
			"ddl_adjusted",
			task_id,
			[task_id],
			{"before": ddl_before, "after": state.ddl, "reason": "intent"},
		)
	if intent.has("transform_task"):
		pending_transforms.append({"task_id": task_id, "spec": intent.transform_task})
	_add_event(
		events,
		"enemy_skill",
		task_id,
		[task_id],
		{"intent_index": int(intent.get("index", 0)), "text_key": str(intent.get("text_key", ""))},
	)
	return GameResult.success(null)


func _scaled_shield(state: BattleState, ruleset: Dictionary, task_id: String, amount: int) -> int:
	var per_stack := int(
		ruleset.get("statuses", {}).get("confusion", {}).get("shield_per_stack", 0)
	)
	if per_stack > 0:
		amount += _status_stacks(state, "confusion", task_id) * per_stack
	if _status_stacks(state, "brittle", task_id) > 0:
		var percent := int(ruleset.get("statuses", {}).get("brittle", {}).get("shield_percent", 50))
		amount = int(floor(amount * percent / 100.0))
	return amount


func _summon_tasks(
	state: BattleState,
	source_id: String,
	spec: Dictionary,
	events: Array[RuleEvent],
	starts_next_round: bool = true,
) -> GameResult:
	var definition_id := str(spec.get("task", ""))
	var definition_result := _catalog.get_definition("task", definition_id)
	if not definition_result.ok:
		return _content_reference_error("task", definition_id, "intent.summon_tasks[].task")
	var phases: Array = definition_result.data.get("phases", [])
	if phases.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.task.phase_missing",
			{"definition_id": definition_id}
		)
	var phase: Dictionary = phases[0]
	var intents: Array = phase.get("intents", [])
	if intents.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.task.intent_missing",
			{"definition_id": definition_id}
		)
	for _index in maxi(1, int(spec.get("count", 1))):
		var cursor := 0
		var intent: Dictionary = intents[cursor].duplicate(true)
		var task_id := _new_instance_id(state, "t")
		var summoned := {
			"task_id": task_id,
			"definition_id": definition_id,
			"phase_key": str(phase.get("phase_key", "")),
			"work_remaining": int(phase.get("work_max", 1)),
			"work_max": int(phase.get("work_max", 1)),
			"shield": int(intent.get("shield", 0)),
			"intent_cursor": cursor,
			"intent_snapshot": intent,
			"entered_order": state.next_creation_order,
			"eligible_round": state.round_index + (1 if starts_next_round else 0),
		}
		_register_source(state, task_id, "task", definition_id)
		state.tasks.append(summoned)
		_add_event(
			events,
			"task_summoned",
			source_id,
			[task_id],
			{
				"definition_id": definition_id,
				"phase_key": str(phase.get("phase_key", "")),
				"work_remaining": int(summoned.work_remaining),
			},
		)
	return GameResult.success(null)


func _transform_task(
	state: BattleState, task_id: String, spec: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var task_index := _task_index(state, task_id)
	if task_index < 0:
		return GameResult.success(null)
	var definition_id := str(spec.get("task", ""))
	var definition_result := _catalog.get_definition("task", definition_id)
	if not definition_result.ok:
		return _content_reference_error("task", definition_id, "intent.transform_task.task")
	var phases: Array = definition_result.data.get("phases", [])
	if phases.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.task.phase_missing",
			{"definition_id": definition_id}
		)
	var phase: Dictionary = phases[0]
	var intents: Array = phase.get("intents", [])
	if intents.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.task.intent_missing",
			{"definition_id": definition_id}
		)
	var task: Dictionary = state.tasks[task_index]
	var previous_definition := str(task.get("definition_id", ""))
	var previous_phase := str(task.get("phase_key", ""))
	var work_max := int(phase.get("work_max", 1))
	var work_remaining := clampi(int(task.get("work_remaining", work_max)), 1, work_max)
	var cursor := 0
	var intent: Dictionary = intents[cursor].duplicate(true)
	_remove_holder_statuses(state, task_id)
	task.definition_id = definition_id
	task.phase_key = str(phase.get("phase_key", ""))
	task.work_max = work_max
	task.work_remaining = work_remaining
	task.intent_cursor = cursor
	task.intent_snapshot = intent
	task.shield = int(intent.get("shield", 0))
	task.eligible_round = state.round_index + 1
	if state.source_registry.has(task_id):
		state.source_registry[task_id]["definition_id"] = definition_id
	_add_event(
		events,
		"task_transformed",
		task_id,
		[task_id],
		{
			"from_definition_id": previous_definition,
			"to_definition_id": definition_id,
			"from_phase_key": previous_phase,
			"to_phase_key": str(phase.get("phase_key", "")),
			"work_remaining": work_remaining,
		},
	)
	return GameResult.success(null)


func _self_destruct_task(state: BattleState, task_index: int, events: Array[RuleEvent]) -> void:
	if task_index < 0 or task_index >= state.tasks.size():
		return
	var task: Dictionary = state.tasks[task_index]
	var task_id := str(task.get("task_id", ""))
	_remove_holder_statuses(state, task_id)
	state.tasks.remove_at(task_index)
	_add_event(
		events,
		"task_self_destructed",
		task_id,
		[task_id],
		{"definition_id": str(task.get("definition_id", ""))},
	)
	_check_battle_outcome(state, events)


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
		if not state.v3.is_empty():
			_reset_v3_turn(state)
	state.player.relax = 0
	var max_reduction := _task_max_vitality_reduction(state)
	if max_reduction > 0:
		var max_before := int(state.player.get("max_vitality", 0))
		state.player.max_vitality = maxi(1, max_before - max_reduction)
		state.player.vitality = mini(
			int(state.player.get("vitality", 0)), state.player.max_vitality
		)
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
	var chapter_window := _v3_run_chapter_window(state, rng, events)
	if not chapter_window.ok:
		return chapter_window
	if state.phase == "finished":
		return GameResult.success(null)
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
	var prepare_trigger := _v3_run_ability_trigger(
		state, "prepare", {"prepare_window": true}, rng, events
	)
	if not prepare_trigger.ok:
		return prepare_trigger
	if state.phase == "finished":
		return GameResult.success(null)
	var phase_to_draw := _set_phase(state, events, "draw")
	if not phase_to_draw.ok:
		return phase_to_draw
	var draw_amount := maxi(
		0,
		(
			int(ruleset.battle.draw_per_round)
			- _status_stacks(state, "procrastination", "player")
			- _task_draw_reduction(state)
		)
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


func _absorb_cooperation(
	state: BattleState,
	encounter: Dictionary,
	ruleset: Dictionary,
	rng: RandomSource,
	events: Array[RuleEvent],
) -> GameResult:
	if not encounter.has("absorb_cooperation"):
		return GameResult.success(null)
	var spec: Dictionary = encounter.absorb_cooperation
	var absorbed: Array[String] = []
	for zone in ["draw", "hand", "discard"]:
		for card_id in state.zones.get(zone, []).duplicate():
			var card: Dictionary = state.card_by_id.get(card_id, {})
			var definition := _catalog.get_definition("card", str(card.get("definition_id", "")))
			if not definition.ok or str(definition.data.get("type", "")) != "cooperation":
				continue
			state.zones[zone].erase(card_id)
			state.zones.exhaust.append(card_id)
			absorbed.append(str(card_id))
			_add_event(
				events,
				"card_absorbed",
				"",
				[card_id],
				{
					"definition_id": str(definition.data.get("id", "")),
					"from_zone": zone,
					"to_zone": "exhaust",
				},
			)
	if absorbed.is_empty():
		return GameResult.success(null)
	var focus_per_card := int(spec.get("focus_per_card", 0))
	var draw_per_card := int(spec.get("draw_per_card", 0))
	var focus_before := int(state.player.get("focus", 0))
	var focus_cap := int(ruleset.battle.get("focus_cap", focus_before))
	state.player.focus = mini(focus_cap, focus_before + absorbed.size() * focus_per_card)
	if state.player.focus != focus_before:
		_add_event(
			events,
			"focus_changed",
			str(state.player.get("entity_id", "")),
			[str(state.player.get("entity_id", ""))],
			{
				"before": focus_before,
				"after": state.player.focus,
				"delta": state.player.focus - focus_before,
				"reason": "absorbed_cooperation",
			},
		)
	_draw_cards(state, absorbed.size() * draw_per_card, rng, events)
	return GameResult.success(null)


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
			"player_action_end": ["drowsiness", "induced"],
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


func _execute_v3_card_effect(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if effect.has("condition") and not _v3_condition(state, effect.condition):
		return GameResult.success(null)
	var op := str(effect.get("op", ""))
	match op:
		"complete":
			var completion := {"op": "complete", "amount": int(effect.get("amount", 0))}
			var per_link := int(effect.get("per_link_work", 0))
			if per_link > 0 and typeof(state.resolution) == TYPE_DICTIONARY:
				var link_count := mini(
					int(effect.get("cap", 3)), int(state.resolution.get("v3_link_work_count", 0))
				)
				completion["amount"] = int(completion.amount) + per_link * link_count
			var bonus: Variant = effect.get("bonus")
			if (
				typeof(bonus) == TYPE_DICTIONARY
				and _v3_condition(state, bonus.get("condition", {}))
			):
				completion["amount"] = int(completion.amount) + int(bonus.get("amount", 0))
			var per_partner := int(effect.get("per_partner", 0))
			if per_partner > 0:
				var partner_count := mini(int(effect.get("cap", 3)), state.units.size())
				completion["amount"] = int(completion.amount) + per_partner * partner_count
			var per_spent := int(effect.get("per_spent", 0))
			if per_spent > 0 and typeof(state.resolution) == TYPE_DICTIONARY:
				completion["amount"] = (
					int(completion.amount)
					+ per_spent * int(state.resolution.get("v3_last_synergy_spent", 0))
				)
			var per_other_chapter := int(effect.get("per_other_chapter", 0))
			if per_other_chapter > 0 and typeof(state.resolution) == TYPE_DICTIONARY:
				completion["amount"] = (
					int(completion.amount)
					+ (
						per_other_chapter
						* mini(
							int(effect.get("cap", 2)),
							int(state.resolution.get("v3_other_chapter_count", 0))
						)
					)
				)
			var per_kind := int(effect.get("per_debuff_kind", 0))
			if per_kind > 0:
				var kind_cap := int(effect.get("cap", 6))
				if bool(effect.get("per_target", false)):
					completion["per_debuff_kind"] = per_kind
					completion["per_debuff_cap"] = kind_cap
					completion["per_target"] = true
				else:
					var ids := _v3_effect_target_ids(state, effect)
					if not ids.is_empty():
						var kinds := mini(kind_cap, _v3_debuff_kinds(state, ids.front()).size())
						completion["amount"] = int(completion.amount) + per_kind * kinds
			return _apply_completion(state, completion, rng, events)
		"relax":
			var relax_amount := maxi(0, int(effect.get("amount", 0)))
			var relax_bonus: Variant = effect.get("bonus")
			if (
				typeof(relax_bonus) == TYPE_DICTIONARY
				and _v3_condition(state, relax_bonus.get("condition", {}))
			):
				relax_amount += int(relax_bonus.get("amount", 0))
			var relax_per_spent := int(effect.get("per_spent", 0))
			if relax_per_spent > 0 and typeof(state.resolution) == TYPE_DICTIONARY:
				relax_amount += (
					relax_per_spent * int(state.resolution.get("v3_last_synergy_spent", 0))
				)
			relax_amount += _v3_card_amplify(state)
			state.player.relax = int(state.player.get("relax", 0)) + relax_amount
			return GameResult.success(null)
		"heal":
			var maximum := int(state.player.get("max_vitality", 0))
			var vitality_before := int(state.player.get("vitality", 0))
			var heal_amount := maxi(0, int(effect.get("amount", 0))) + _v3_card_amplify(state)
			state.player.vitality = mini(maximum, vitality_before + heal_amount)
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
						"reason": "v3_effect",
					}
				)
			return GameResult.success(null)
		"draw":
			var draw_amount: Variant = effect.get("amount", 0)
			if typeof(draw_amount) == TYPE_DICTIONARY:
				draw_amount = int(state.resolution.get("v3_discarded_count", 0))
			var draw_total := maxi(0, int(draw_amount)) + _v3_card_amplify(state)
			_draw_cards(state, draw_total, rng, events)
			return GameResult.success(null)
		"discard":
			return _start_card_choice(state, effect, "discard")
		"retain":
			return _start_card_choice(state, effect, "retain_hand_card")
		"retrieve":
			return _start_card_choice(state, effect, "recall_from_discard")
		"exhaust_other":
			return _start_card_choice(state, effect, "exhaust_other")
		"remove_status":
			return _start_card_choice(state, effect, "remove_status")
		"work_bonus_next":
			_v3_add_work_bonus(state, int(effect.get("amount", 0)))
			return GameResult.success(null)
		"cost_discount_next":
			_v3_add_cost_discount(
				state, int(effect.get("amount", 0)), int(effect.get("min_base_cost", 2))
			)
			return GameResult.success(null)
		"gain_focus":
			var ruleset := _loaded_ruleset()
			if not ruleset.ok:
				return ruleset
			var focus_cap := int(ruleset.data.battle.focus_cap)
			var focus_before := int(state.player.get("focus", 0))
			var focus_amount := maxi(0, int(effect.get("amount", 0))) + _v3_card_amplify(state)
			state.player.focus = mini(focus_cap, focus_before + focus_amount)
			return GameResult.success(null)
		"apply_status":
			var stacks_value: Variant = effect.get("stacks", 1)
			if (
				typeof(stacks_value) == TYPE_DICTIONARY
				and str(stacks_value.get("op", "")) == "source_stacks"
			):
				stacks_value = _v3_source_stacks(state, stacks_value)
			return _v3_apply_status_batch(
				state,
				str(effect.get("status", "")),
				int(stacks_value),
				_v3_effect_target_ids(state, effect),
				true,
				true,
				events
			)
		"trigger_erosion":
			for target_id in _v3_effect_target_ids(state, effect):
				var erosion_stacks := _status_stacks(state, "erosion", target_id)
				if erosion_stacks <= 0:
					continue
				var deferred := _v3_status_complete_task(
					state, target_id, erosion_stacks, rng, events
				)
				if not deferred.ok:
					return deferred
				if not bool(effect.get("decay", true)):
					continue
				var erosion_index := _status_index(state, "erosion", target_id)
				if erosion_index >= 0:
					var status: Dictionary = state.statuses[erosion_index]
					var before := int(status.get("stacks", 0))
					if before <= 1:
						state.statuses.remove_at(erosion_index)
					else:
						status.stacks = before - 1
			return GameResult.success(null)
		"trigger_induced":
			for target_id in _v3_effect_target_ids(state, effect):
				var induced_stacks := _status_stacks(state, "induced", target_id)
				if induced_stacks <= 0:
					continue
				var triggered := _v3_induced_trigger_target(
					state, target_id, induced_stacks, rng, events
				)
				if not triggered.ok:
					return triggered
			return GameResult.success(null)
		"status_complete":
			for target_id in _v3_effect_target_ids(state, effect):
				var completed := _v3_status_complete_task(
					state, target_id, int(effect.get("amount", 0)), rng, events
				)
				if not completed.ok:
					return completed
				if state.phase == "finished":
					break
			return GameResult.success(null)
		"extend_timed_debuffs":
			for target_id in _v3_effect_target_ids(state, effect):
				for status_id in ["vulnerability", "weakness", "brittle"]:
					var status_index := _status_index(state, status_id, target_id)
					if status_index < 0:
						continue
					var status: Dictionary = state.statuses[status_index]
					var before := int(status.get("stacks", 0))
					status.stacks = mini(3, before + int(effect.get("amount", 1)))
					_add_event(
						events,
						"status_changed",
						str(state.resolution.get("card_instance_id", "")),
						[target_id],
						{
							"status_definition_id": status_id,
							"before": before,
							"after": status.stacks,
							"amount": status.stacks - before,
							"reason": "extend_timed_debuff",
						}
					)
			return GameResult.success(null)
		"arm_erosion_on_next_draws":
			_v3_turn(state).erosion_draws = maxi(
				int(_v3_turn(state).erosion_draws), int(effect.get("amount", 0))
			)
			return GameResult.success(null)
		"modify_erosion_window":
			return GameResult.success(null)
		"remove_shield":
			var shield_targets := _v3_effect_target_ids(state, effect)
			var remaining := maxi(0, int(effect.get("amount", 0)))
			for target_id in shield_targets:
				var task_index := _task_index(state, target_id)
				if task_index < 0:
					continue
				var task: Dictionary = state.tasks[task_index]
				var before := int(task.get("shield", 0))
				var removed := mini(before, remaining)
				task.shield = before - removed
				remaining -= removed
				_add_event(
					events,
					"shield_changed",
					str(state.resolution.get("card_instance_id", "")),
					[target_id],
					{"before": before, "after": task.shield, "reason": "v3_effect"}
				)
			return GameResult.success(null)
		"paper_open":
			_v3_open_paper(state, events)
			return GameResult.success(null)
		"paper_progress":
			var progress_amount := maxi(0, int(effect.get("amount", 0)))
			if not bool((state.resolution as Dictionary).get("v3_auto", false)):
				progress_amount += _v3_consume_amplify(state)
			var paper := _v3_paper(state)
			paper.progress = mini(10, int(paper.progress) + progress_amount)
			return GameResult.success(null)
		"paper_citation":
			var citation_amount := maxi(0, int(effect.get("amount", 0)))
			if not bool((state.resolution as Dictionary).get("v3_auto", false)):
				citation_amount += _v3_consume_amplify(state)
			_v3_gain_citation(state, citation_amount, rng, events)
			return GameResult.success(null)
		"paper_modifier":
			_v3_paper(state).modifier = (
				int(_v3_paper(state).modifier) + int(effect.get("amount", 0))
			)
			return GameResult.success(null)
		"paper_amplify":
			var paper_state := _v3_paper(state)
			paper_state.amplify = mini(
				5, int(paper_state.amplify) + maxi(0, int(effect.get("amount", 0)))
			)
			return GameResult.success(null)
		"paper_publish":
			return _v3_paper_publish(state, state.resolution, rng, events)
		"spend_citation":
			var paper_spend := _v3_paper(state)
			if int(paper_spend.citations) < int(effect.get("amount", 1)):
				return _failure(
					GameConstants.ERROR_INSUFFICIENT_RESOURCE,
					"error.play.citation_insufficient",
					{"required": int(effect.get("amount", 1))}
				)
			paper_spend.citations = int(paper_spend.citations) - int(effect.get("amount", 1))
			return GameResult.success(null)
		"change_topic":
			var paper_change := _v3_paper(state)
			if not paper_change.used_names.is_empty():
				paper_change.used_names.pop_front()
				paper_change.modifier = int(paper_change.modifier) + int(effect.get("modifier", -1))
			return GameResult.success(null)
		"chapter_deploy":
			var deployed := _v3_chapter_deploy(
				state, str(state.resolution.get("card_instance_id", "")), events
			)
			if not deployed.ok:
				return deployed
			if typeof(deployed.data) == TYPE_DICTIONARY:
				return deployed
			if (
				deployed.data is bool
				and deployed.data
				and typeof(state.resolution) == TYPE_DICTIONARY
			):
				state.resolution["v3_chapter_deploy"] = true
			return GameResult.success(null)
		"chapter_run":
			return _v3_chapter_run(state, int(effect.get("amount", 1)), rng, events)
		"chapter_return":
			var returned := _v3_chapter_return(state, int(effect.get("amount", 1)), events)
			if effect.has("modifier_per_chapter"):
				_v3_paper(state).modifier = (
					int(_v3_paper(state).modifier) + returned * int(effect.modifier_per_chapter)
				)
			return GameResult.success(null)
		"swap_chapter_slots":
			_v3_swap_chapter_slots(state, events)
			return GameResult.success(null)
		"search_draw_for_type":
			return _v3_search_draw_chapter(state, rng, events)
		"copy_chapter_to_hand":
			var paper_copy := _v3_paper(state)
			if not paper_copy.chapters.is_empty():
				var source_id := str(paper_copy.chapters[0].get("card_id", ""))
				var source_card: Dictionary = state.card_by_id.get(source_id, {})
				var copy_id := _new_instance_id(state, "c")
				state.card_by_id[copy_id] = {
					"card_id": copy_id,
					"definition_id": str(source_card.get("definition_id", "")),
					"origin_card_id": source_id,
					"upgrade_level": int(source_card.get("upgrade_level", 0)),
					"temporary_modifiers": {},
				}
				if state.zones.hand.size() < 10:
					state.zones.hand.append(copy_id)
				else:
					state.zones.discard.append(copy_id)
			return GameResult.success(null)
		"generate_card":
			var generated_id := str(effect.get("card", ""))
			var generated_count := maxi(1, int(effect.get("amount", 1)))
			for _index in generated_count:
				var new_card_id := _new_instance_id(state, "c")
				state.card_by_id[new_card_id] = {
					"card_id": new_card_id,
					"definition_id": generated_id,
					"origin_card_id": "",
					"upgrade_level": 0,
					"temporary_modifiers": {},
				}
				if str(effect.get("zone", "hand")) == "hand" and state.zones.hand.size() < 10:
					state.zones.hand.append(new_card_id)
				else:
					state.zones.discard.append(new_card_id)
			return GameResult.success(null)
		"shuffle_draw":
			var shuffled_draw := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, state.zones.draw)
			if not shuffled_draw.ok:
				return shuffled_draw
			state.zones.draw = shuffled_draw.data
			return GameResult.success(null)
		"lose_vitality":
			var vitality_loss := maxi(0, int(effect.get("amount", 0)))
			var lost_before := int(state.player.get("vitality", 0))
			state.player.vitality = maxi(0, lost_before - vitality_loss)
			_add_event(
				events,
				"vitality_changed",
				str(state.resolution.get("card_instance_id", "")),
				[str(state.player.get("entity_id", ""))],
				{
					"before": lost_before,
					"after": state.player.vitality,
					"delta": state.player.vitality - lost_before,
					"reason": "effect",
				}
			)
			_check_battle_outcome(state, events)
			return GameResult.success(null)
		"publication_cost_discount":
			state.v3["publication_discount"] = maxi(0, int(effect.get("amount", 1)))
			return GameResult.success(null)
		"establish_scene":
			return _establish_scene(state, effect, rng, events)
		"summon_partner":
			return _v3_summon_partner(state, effect, rng, events)
		"gain_synergy":
			_v3_gain_synergy(state, int(effect.get("amount", 0)))
			return GameResult.success(null)
		"spend_synergy":
			var optional := bool(effect.get("optional", false))
			var spent := _v3_spend_synergy(state, int(effect.get("amount", 0)), optional)
			if spent < 0:
				return _failure(
					GameConstants.ERROR_INSUFFICIENT_RESOURCE,
					"error.play.synergy_insufficient",
					{"required": int(effect.get("amount", 0))}
				)
			if spent == 0 and optional:
				return GameResult.success(null)
			if typeof(state.resolution) == TYPE_DICTIONARY:
				state.resolution["v3_last_synergy_spent"] = spent
			if effect.has("then"):
				var then_result := _v3_execute_effects(state, effect.then, rng, events)
				if not then_result.ok or typeof(then_result.data) == TYPE_DICTIONARY:
					return then_result
			if effect.has("if_spent"):
				return _v3_execute_effects(state, effect.if_spent, rng, events)
			return GameResult.success(null)
		"spend_synergy_up_to":
			var available := _v3_synergy(state)
			var spend_up_to := mini(maxi(0, int(effect.get("amount", 0))), available)
			_v3_spend_synergy(state, spend_up_to, false)
			if typeof(state.resolution) == TYPE_DICTIONARY:
				state.resolution["v3_last_synergy_spent"] = spend_up_to
			if effect.has("then"):
				var up_result := _v3_execute_effects(state, effect.then, rng, events)
				if not up_result.ok or typeof(up_result.data) == TYPE_DICTIONARY:
					return up_result
			if effect.has("after"):
				return _v3_execute_effects(state, effect.after, rng, events)
			return GameResult.success(null)
		"spend_all_synergy":
			var all_spent := _v3_synergy(state)
			_v3_spend_synergy(state, all_spent, false)
			if typeof(state.resolution) == TYPE_DICTIONARY:
				state.resolution["v3_last_synergy_spent"] = all_spent
			if effect.has("then"):
				return _v3_execute_effects(state, effect.then, rng, events)
			return GameResult.success(null)
		"partner_heal":
			return _v3_partner_heal(state, effect, events)
		"partner_retreat":
			return _v3_partner_retreat(state, effect, events)
		"partner_extra_action":
			return _v3_partner_extra_action(state, effect, rng, events)
		"add_work_bonus":
			_v3_add_work_bonus(state, int(effect.get("amount", 0)))
			return GameResult.success(null)
		_:
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY, "battle.v3.effect_not_ready", {"op": op}
			)


func _v3_effect_target_ids(state: BattleState, effect: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if str(effect.get("target", "")) == "all_tasks":
		for task: Dictionary in state.tasks:
			result.append(str(task.get("task_id", "")))
		return result
	if str(effect.get("target", "")) == "earliest_task":
		var earliest := _first_eligible_task(state)
		if not earliest.is_empty():
			result.append(earliest)
		return result
	if typeof(state.resolution) != TYPE_DICTIONARY:
		return result
	if str(effect.get("target", "")) == "other_task":
		var selected: Array = state.resolution.get("target_ids", [])
		for task: Dictionary in state.tasks:
			var task_id := str(task.get("task_id", ""))
			if not selected.has(task_id):
				result.append(task_id)
				break
		return result
	for target_id in state.resolution.get("target_ids", []):
		result.append(str(target_id))
	if result.is_empty():
		var fallback := _first_eligible_task(state)
		if not fallback.is_empty():
			result.append(fallback)
	return result


func _v3_condition(state: BattleState, condition: Variant, context: Dictionary = {}) -> bool:
	if typeof(condition) != TYPE_DICTIONARY:
		return false
	if condition.has("all"):
		for child: Variant in condition.all:
			if not _v3_condition(state, child, context):
				return false
		return true
	if condition.has("any"):
		for child: Variant in condition.any:
			if _v3_condition(state, child, context):
				return true
		return false
	var kind := str(condition.get("kind", ""))
	match kind:
		"ddl_lte":
			return state.ddl <= int(condition.get("value", 0))
		"link":
			return (
				typeof(state.resolution) == TYPE_DICTIONARY
				and bool(state.resolution.get("v3_link", false))
			)
		"prev_card_type_is":
			return (
				typeof(state.resolution) == TYPE_DICTIONARY
				and (
					str(state.resolution.get("v3_previous_card_type", ""))
					== str(condition.get("value", ""))
				)
			)
		"played_type_count_turn":
			var played_types: Dictionary = _v3_turn(state).played_types
			if typeof(state.resolution) == TYPE_DICTIONARY:
				var snapshot: Variant = state.resolution.get("v3_played_type_counts", null)
				if typeof(snapshot) == TYPE_DICTIONARY:
					played_types = snapshot
			return (
				int(played_types.get(str(condition.get("value", "")), 0))
				>= int(condition.get("min", 1))
			)
		"no_strategy_played_turn":
			return int(_v3_turn(state).played_types.get("strategy", 0)) == 0
		"instance_plays_battle":
			var before := bool(context.get("instance_was_played_before", false))
			if typeof(state.resolution) == TYPE_DICTIONARY:
				before = bool(state.resolution.get("v3_instance_was_played_before", before))
			return (
				before
				or (
					typeof(state.resolution) == TYPE_DICTIONARY
					and (
						int(
							_v3_battle(state).instance_plays.get(
								str(state.resolution.get("card_instance_id", "")), 0
							)
						)
						>= int(condition.get("min", 1))
					)
				)
			)
		"instance_played_before":
			if context.has("instance_was_played_before"):
				return bool(context.instance_was_played_before)
			return (
				typeof(state.resolution) == TYPE_DICTIONARY
				and bool(state.resolution.get("v3_instance_was_played_before", false))
			)
		"previous_strategy_plays_min":
			if typeof(state.resolution) != TYPE_DICTIONARY:
				return false
			var previous_id := str(state.resolution.get("v3_previous_card_instance_id", ""))
			return (
				int(_v3_battle(state).instance_plays.get(previous_id, 0))
				>= int(condition.get("value", 1))
			)
		"retrieved_strategy_this_turn":
			return bool(_v3_turn(state).retrieved_strategy)
		"synergy_min":
			return _v3_synergy(state) >= int(condition.get("value", 0))
		"synergy_is_zero":
			return _v3_synergy(state) == 0
		"partner_count_min":
			return state.units.size() >= int(condition.get("value", 1))
		"no_partner":
			return state.units.is_empty()
		"independent_exam":
			return state.exam_flags.has("independent_answer")
		"summoned_partner_turn":
			return bool(_v3_turn(state).summoned_partner)
		"healed_partner_turn":
			return bool(_v3_turn(state).healed_partner)
		"first_cooperation_resolved":
			return bool(_v3_turn(state).first_cooperation)
		"paper_open":
			return bool(_v3_paper(state).open)
		"paper_closed":
			return not bool(_v3_paper(state).open)
		"paper_progress_min":
			return int(_v3_paper(state).progress) >= int(condition.get("value", 0))
		"paper_name_unused":
			if (
				typeof(state.resolution) == TYPE_DICTIONARY
				and state.resolution.has("v3_paper_name_was_used")
			):
				return not bool(state.resolution.v3_paper_name_was_used)
			return false
		"paper_name_used":
			if (
				typeof(state.resolution) == TYPE_DICTIONARY
				and state.resolution.has("v3_paper_name_was_used")
			):
				return bool(state.resolution.v3_paper_name_was_used)
			return false
		"paper_name_turn_unused":
			if typeof(state.resolution) == TYPE_DICTIONARY:
				return not _v3_paper(state).turn_names.has(
					str(state.resolution.get("v3_paper_name", ""))
				)
			return true
		"paper_progress_gained":
			return bool(context.get("paper_progress_gained", false))
		"chapter_count_min":
			return _v3_chapter_count(state) >= int(condition.get("value", 1))
		"other_chapter_ran_window":
			if typeof(state.resolution) == TYPE_DICTIONARY:
				return int(state.resolution.get("v3_other_chapter_count", 0)) > 0
			return false
		"citation_min":
			return int(_v3_paper(state).citations) >= int(condition.get("value", 1))
		"paid_citation_focus_this_turn":
			return bool(_v3_turn(state).paid_citation)
		"fixed_exam_room":
			return state.exam_flags.has("fixed_exam_room")
		"base_cost_min":
			var base_cost := int(context.get("base_cost", 0))
			if typeof(state.resolution) == TYPE_DICTIONARY:
				base_cost = int(state.resolution.get("v3_base_cost", base_cost))
			return base_cost >= int(condition.get("value", 0))
		"card_discarded_this_effect":
			return (
				typeof(state.resolution) == TYPE_DICTIONARY
				and not state.resolution.get("discarded_in_resolution", []).is_empty()
			)
		"passive_retrieve_success":
			return bool(context.get("passive_retrieve_success", false))
		"link_work_resolved":
			return bool(context.get("link_work", false))
		"target_has_status":
			var status_id := str(condition.get("status", ""))
			for target_id in _v3_effect_target_ids(state, {}):
				if _status_stacks(state, status_id, target_id) > 0:
					return true
			return false
		"target_still_alive":
			for target_id in _v3_effect_target_ids(state, {}):
				if _task_index(state, target_id) >= 0:
					return true
			return false
		"target_status_kinds":
			for target_id in _v3_effect_target_ids(state, {}):
				var kinds := _v3_debuff_kinds(state, target_id).size()
				if condition.has("min") and kinds < int(condition.min):
					continue
				if condition.has("max") and kinds > int(condition.max):
					continue
				return true
			return false
		"target_has_any_timed_debuff":
			for target_id in _v3_effect_target_ids(state, {}):
				for status_id in ["vulnerability", "weakness", "brittle"]:
					if _status_stacks(state, status_id, target_id) > 0:
						return true
			return false
		"target_has_induced":
			for target_id in _v3_effect_target_ids(state, {}):
				if _status_stacks(state, "induced", target_id) > 0:
					return true
			return false
		"target_had_induced_at_play_start":
			if typeof(state.resolution) != TYPE_DICTIONARY:
				return false
			var snapshot: Dictionary = state.resolution.get("v3_target_induced_snapshot", {})
			for target_id in _v3_effect_target_ids(state, {}):
				if bool(snapshot.get(target_id, false)):
					return true
			return false
		"any_task_has_induced":
			for task: Dictionary in state.tasks:
				if _status_stacks(state, "induced", str(task.get("task_id", ""))) > 0:
					return true
			return false
		"any_task_debuff_kinds_min":
			for task: Dictionary in state.tasks:
				if (
					_v3_debuff_kinds(state, str(task.get("task_id", ""))).size()
					>= int(condition.get("value", 0))
				):
					return true
			return false
		"two_tasks":
			return state.tasks.size() >= 2
		"erosion_applied_events_min":
			return int(_v3_turn(state).get("erosion_events", 0)) >= int(condition.get("value", 0))
		"first_induced_trigger":
			return bool(context.get("first_induced_trigger", false))
		"compound_reaction_success":
			return bool(context.get("compound_reaction_success", false))
		"prepare_window":
			return bool(context.get("prepare_window", false))
		_:
			return false


func _consume_v3_first_work_bonus(state: BattleState) -> int:
	if not state.v3.has("abilities"):
		return 0
	var total := 0
	var abilities: Array = state.v3.abilities
	for ability: Variant in abilities:
		if typeof(ability) != TYPE_DICTIONARY:
			continue
		if str(ability.get("trigger", "")) != "first_work_card_resolving":
			continue
		if state.round_index < int(ability.get("activate_round", 0)):
			continue
		if int(ability.get("last_round", 0)) == state.round_index:
			continue
		for effect: Variant in ability.get("effects", []):
			if typeof(effect) != TYPE_DICTIONARY or str(effect.get("op", "")) != "add_work_bonus":
				continue
			if effect.has("condition") and not _v3_condition(state, effect.condition):
				continue
			total += maxi(0, int(effect.get("amount", 0)))
			ability.last_round = state.round_index
	return total


func _tick_pressure_window_statuses(state: BattleState, events: Array[RuleEvent]) -> void:
	for index in range(state.statuses.size() - 1, -1, -1):
		var status: Dictionary = state.statuses[index]
		if not ["vulnerability", "weakness", "brittle"].has(str(status.get("status_id", ""))):
			continue
		var before := int(status.get("stacks", 0))
		var after := before - 1
		if after > 0:
			status.stacks = after
			_add_event(
				events,
				"status_changed",
				"",
				[str(status.get("target_id", ""))],
				{
					"status_definition_id": str(status.status_id),
					"before": before,
					"after": after,
					"amount": -1,
					"reason": "pressure_window",
				}
			)
		else:
			_add_event(
				events,
				"status_removed",
				"",
				[str(status.get("target_id", ""))],
				{
					"status_definition_id": str(status.status_id),
					"before": before,
					"after": 0,
					"amount": before,
					"reason": "pressure_window",
				}
			)
			state.statuses.remove_at(index)


func _execute_card_effect(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if typeof(state.resolution) == TYPE_DICTIONARY and bool(state.resolution.get("v3", false)):
		return _execute_v3_card_effect(state, effect, rng, events)
	var op := str(effect.get("op", ""))
	var amount := int(effect.get("amount", effect.get("stacks", 0)))
	match op:
		"complete":
			return _apply_completion(state, effect, rng, events)
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
		"pressure":
			_apply_pressure(state, amount, str(effect.get("target", "player")) == "all", events, 0)
			return GameResult.success(null)
		"reduce_relax":
			var relax_before: int = int(state.player.get("relax", 0))
			state.player.relax = maxi(0, relax_before - maxi(0, amount))
			_add_event(
				events,
				"relax_changed",
				str(state.resolution.get("card_instance_id", "")),
				[str(state.player.get("entity_id", ""))],
				{
					"before": relax_before,
					"after": state.player.relax,
					"delta": state.player.relax - relax_before,
					"reason": "effect",
				}
			)
			return GameResult.success(null)
		"reduce_max_vitality":
			var max_before: int = int(state.player.get("max_vitality", 0))
			state.player.max_vitality = maxi(1, max_before - maxi(0, amount))
			state.player.vitality = mini(
				int(state.player.get("vitality", 0)), state.player.max_vitality
			)
			return GameResult.success(null)
		"restore_max_vitality":
			var max_base: int = int(
				state.player.get("max_vitality_base", state.player.get("max_vitality", 0))
			)
			state.player.max_vitality = mini(
				max_base, int(state.player.get("max_vitality", 0)) + maxi(0, amount)
			)
			return GameResult.success(null)
		"reduce_focus":
			var focus_before: int = int(state.player.get("focus", 0))
			state.player.focus = maxi(0, focus_before - maxi(0, amount))
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
		"random_discard":
			return _random_discard(state, maxi(0, amount), rng, events)
		"summon_task":
			return _summon_tasks(
				state,
				str(state.resolution.get("card_instance_id", "")),
				{
					"task": str(effect.get("task", "")),
					"count": maxi(1, int(effect.get("count", 1)))
				},
				events
			)
		_:
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY, "battle.effect.not_ready", {"op": op}
			)


func _random_discard(
	state: BattleState, amount: int, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var hand: Array[String] = []
	for card_id in state.zones.get("hand", []):
		hand.append(str(card_id))
	var resolving := ""
	if typeof(state.resolution) == TYPE_DICTIONARY:
		resolving = str(state.resolution.get("card_instance_id", ""))
	hand.erase(resolving)
	if amount <= 0 or hand.is_empty():
		return GameResult.success(null)
	var shuffled := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, hand)
	if not shuffled.ok:
		return shuffled
	var discarded_count := mini(amount, shuffled.data.size())
	for index in discarded_count:
		var card_id: String = str(shuffled.data[index])
		state.zones.hand.erase(card_id)
		state.zones.discard.append(card_id)
		_add_event(
			events,
			"card_discarded",
			resolving,
			[card_id],
			{
				"definition_id": str(state.card_by_id[card_id].definition_id),
				"from_zone": "hand",
				"to_zone": "discard",
			}
		)
	return GameResult.success(null)


func _task_draw_reduction(state: BattleState) -> int:
	var total := 0
	for task: Dictionary in state.tasks:
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if definition.ok:
			total += int(definition.data.get("draw_reduction", 0))
	return total


func _task_first_card_discard(state: BattleState) -> int:
	var total := 0
	for task: Dictionary in state.tasks:
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if definition.ok:
			total += int(definition.data.get("discard_on_first_card", 0))
	return total


func _task_max_vitality_reduction(state: BattleState) -> int:
	var total := 0
	for task: Dictionary in state.tasks:
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if definition.ok:
			total += int(definition.data.get("max_vitality_reduction", 0))
	return total


func _has_taunting_task(state: BattleState) -> bool:
	for task: Dictionary in state.tasks:
		if int(task.get("work_remaining", 0)) <= 0:
			continue
		if int(task.get("eligible_round", 1)) > state.round_index:
			continue
		if _task_has_taunt(state, str(task.get("task_id", ""))):
			return true
	return false


func _task_has_taunt(state: BattleState, task_id: String) -> bool:
	var task_index := _task_index(state, task_id)
	if task_index < 0:
		return false
	var definition := _catalog.get_definition(
		"task", str(state.tasks[task_index].get("definition_id", ""))
	)
	return definition.ok and bool(definition.data.get("taunt", false))


func _apply_completion(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
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
		requested += (
			_status_stacks(state, "work_boost", "player")
			* int(ruleset.data.statuses.get("work_boost", {}).get("completion_per_stack", 0))
		)
		if bool(resolution.get("v3", false)) and applies_work_statuses:
			var main_target_bonus := _v3_take_work_bonus(state)
			if bool(resolution.get("first_work_card", false)):
				main_target_bonus += _consume_v3_first_work_bonus(state)
			resolution["v3_main_target_bonus"] = main_target_bonus
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
		var requested_for_target := requested
		if (
			bool(resolution.get("v3", false))
			and int(effect.get("per_debuff_kind", 0)) > 0
			and bool(effect.get("per_target", false))
		):
			var kinds := mini(
				int(effect.get("per_debuff_cap", 6)), _v3_debuff_kinds(state, str(task_id)).size()
			)
			requested_for_target += int(effect.per_debuff_kind) * kinds
		if (
			bool(resolution.get("v3", false))
			and not targets.is_empty()
			and str(task_id) == str(targets.front())
		):
			requested_for_target += int(resolution.get("v3_main_target_bonus", 0))
		if (
			bool(resolution.get("v3", false))
			and ruleset.ok
			and _status_stacks(state, "vulnerability", str(task_id)) > 0
		):
			var percent := int(
				ruleset.data.statuses.get("vulnerability", {}).get("completion_percent", 125)
			)
			requested_for_target = int(floor(requested_for_target * percent / 100.0))
		var shield_loss: int = mini(before_shield, requested_for_target)
		var applied: int = requested_for_target - shield_loss
		task.shield = before_shield - shield_loss
		task.work_remaining = maxi(0, before_work - applied)
		_add_event(
			events,
			"completion_applied",
			str(resolution.get("card_instance_id", "")),
			[str(task_id)],
			{
				"amount": requested_for_target,
				"shield_before": before_shield,
				"shield_after": task.shield,
				"work_before": before_work,
				"work_after": task.work_remaining,
				"segment_index": 0,
			}
		)
		if int(task.work_remaining) == 0:
			var advanced := _advance_or_remove_task(state, task_index, events, rng)
			if not advanced.ok:
				return advanced
			_check_battle_outcome(state, events)
			if state.phase == "finished":
				return GameResult.success(null)
		_check_battle_outcome(state, events)
	return GameResult.success(null)


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


func _run_on_complete_effects(
	state: BattleState, task_id: String, effects: Array, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if effects.is_empty():
		return GameResult.success(null)
	var previous: Variant = state.resolution
	state.resolution = {
		"card_instance_id": task_id,
		"definition_id": "",
		"effects": [],
		"cursor": 0,
		"target_ids": [],
		"choice": null,
		"choice_counts": {},
		"discarded_in_resolution": [],
		"all_tasks": false,
		"context_target_id": "",
	}
	for effect: Dictionary in effects:
		var result := _execute_card_effect(state, effect, rng, events)
		if not result.ok:
			state.resolution = previous
			return result
		if typeof(result.data) == TYPE_DICTIONARY:
			state.resolution = previous
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY,
				"battle.on_complete.choice_not_ready",
				{"task_id": task_id, "op": str(effect.get("op", ""))},
			)
		if state.phase == "finished":
			break
	state.resolution = previous
	return GameResult.success(null)


func _advance_or_remove_task(
	state: BattleState, task_index: int, events: Array[RuleEvent], rng: RandomSource = null
) -> GameResult:
	var previous: Dictionary = state.tasks[task_index]
	var definition_result := _catalog.get_definition("task", str(previous.get("definition_id", "")))
	if not definition_result.ok:
		return GameResult.success(null)
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
		return GameResult.success(null)
	var on_complete: Array = definition_result.data.get("on_complete_effects", [])
	if not on_complete.is_empty() and rng != null:
		var completed := _run_on_complete_effects(
			state, str(previous.task_id), on_complete, rng, events
		)
		if not completed.ok:
			return completed
	state.tasks.remove_at(task_index)
	_add_event(
		events,
		"task_completed",
		str(previous.task_id),
		[str(previous.task_id)],
		{"definition_id": str(previous.definition_id), "phase_key": str(previous.phase_key)}
	)
	return GameResult.success(null)


func _check_battle_outcome(state: BattleState, events: Array[RuleEvent]) -> void:
	if state.phase == "finished":
		return
	if int(state.player.get("vitality", 0)) <= 0:
		_finish_battle(state, "lost", "vitality_depleted", events)
	elif not _has_required_task(state):
		_finish_battle(state, "won", "tasks_completed", events)


func _has_required_task(state: BattleState) -> bool:
	for task: Dictionary in state.tasks:
		var definition := _catalog.get_definition("task", str(task.get("definition_id", "")))
		if not definition.ok:
			return true
		if bool(definition.data.get("victory_required", true)):
			return true
	return false


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
	if effect.has("vitality_override"):
		unit["vitality"] = int(effect.vitality_override)
	unit["max_vitality"] = (
		int(effect.max_vitality_override)
		if effect.has("max_vitality_override")
		else int(unit["vitality"])
	)
	unit["cooperation"] = int(unit.get("cooperation", 0)) + int(effect.get("cooperation_bonus", 0))
	if effect.has("cooperation_override"):
		unit["cooperation"] = int(effect.cooperation_override)
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
		if not state.v3.is_empty():
			var turn := _v3_turn(state)
			if int(turn.get("erosion_draws", 0)) > 0:
				var chain_targets: Array[String] = []
				for task: Dictionary in state.tasks:
					chain_targets.append(str(task.get("task_id", "")))
				var chain := _v3_apply_status_batch(
					state, "erosion", 1, chain_targets, true, false, events
				)
				if not chain.ok:
					return
				turn.erosion_draws = int(turn.erosion_draws) - 1
				var settled := _v3_settle_erosion_events(state, rng, events)
				if not settled.ok or state.phase == "finished":
					return
		amount -= 1


func _v3_retrieve_allowed(state: BattleState, card_id: String, effect: Dictionary) -> bool:
	var card: Dictionary = state.card_by_id.get(card_id, {})
	var definition := _catalog.get_definition("card", str(card.get("definition_id", "")))
	if not definition.ok:
		return false
	if (
		bool(effect.get("permanent_only", false))
		and not bool(definition.data.get("permanent", true))
	):
		return false
	var card_kind := str(effect.get("card_kind", ""))
	if not card_kind.is_empty() and str(definition.data.get("type", "")) != card_kind:
		return false
	var required_id := str(effect.get("card_id", ""))
	if not required_id.is_empty() and str(definition.data.get("id", "")) != required_id:
		return false
	if int(definition.data.get("cost", 0)) < int(effect.get("base_cost_min", 0)):
		return false
	var owner := str(effect.get("owner", ""))
	if owner.is_empty():
		owner = state.character_id
	if not owner.is_empty() and str(definition.data.get("owner", "")) != owner:
		return false
	return true


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
				if (
					bool(resolution.get("v3", false))
					and not _v3_retrieve_allowed(state, str(card_id), effect)
				):
					continue
				candidates.append(_card_candidate(state, str(card_id)))
		"exhaust_other":
			kind = "exhaust"
			for card_id in state.zones.hand:
				if str(card_id) != str(resolution.get("card_instance_id", "")):
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
	if op == "exhaust_other" and candidates.is_empty():
		return _failure(
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.no_exhaust_target",
			{"required": int(effect.get("amount", 1))}
		)
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
		"exhaust":
			for card_id in selected:
				state.zones.hand.erase(card_id)
				state.zones.exhaust.append(card_id)
				_add_event(
					events,
					"card_exhausted",
					str(choice.source_card_id),
					[card_id],
					{
						"definition_id": str(state.card_by_id[card_id].definition_id),
						"from_zone": "hand",
						"to_zone": "exhaust",
					}
				)
			resolution.choice_counts[kind] = selected.size()
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
		"chapter_replace":
			if selected.is_empty():
				return _failure(
					GameConstants.ERROR_INVALID_TARGET, "error.play.no_chapter_replace", {}
				)
			var removed_id := str(selected[0])
			var paper_replace := _v3_paper(state)
			var removed := false
			for index in paper_replace.chapters.size():
				var entry: Variant = paper_replace.chapters[index]
				if typeof(entry) == TYPE_DICTIONARY and str(entry.get("card_id", "")) == removed_id:
					paper_replace.chapters.remove_at(index)
					removed = true
					break
			if not removed:
				return _failure(
					GameConstants.ERROR_INVALID_TARGET,
					"error.play.no_chapter_replace",
					{"selected_id": removed_id}
				)
			state.zones.discard.append(removed_id)
			var current_id := str(choice.get("source_card_id", ""))
			var current_card: Dictionary = state.card_by_id.get(current_id, {})
			(
				paper_replace
				. chapters
				. append(
					{
						"card_id": current_id,
						"definition_id": str(current_card.get("definition_id", "")),
						"deployed_round": state.round_index,
					}
				)
			)
			resolution.v3_chapter_deploy = true
			resolution.choice_counts[kind] = 1
			_add_event(
				events,
				"chapter_deployed",
				current_id,
				[current_id],
				{
					"definition_id": str(current_card.get("definition_id", "")),
					"replaced": removed_id,
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
	if bool(resolution.get("v3_chapter_deploy", false)):
		destination = "chapters"
	else:
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
	if bool(resolution.get("v3", false)):
		var compound := _v3_apply_compound_reaction(state, rng, events)
		if not compound.ok:
			return compound
		var recorded := _v3_record_card_played(state, resolution, rng, events)
		if not recorded.ok:
			return recorded
		var erosion_settled := _v3_settle_erosion_events(state, rng, events)
		if not erosion_settled.ok:
			return erosion_settled
		var induced := _v3_induced_window(state, rng, events)
		if not induced.ok:
			return induced
		if int(resolution.get("v3_cost_discount_applied", 0)) > 0:
			state.v3["pending_cost_discount"] = {"amount": 0, "min_base_cost": 0}
		if definition_id == "R3-T201":
			state.v3["publication_discount"] = 0
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


func _v3_turn(state: BattleState) -> Dictionary:
	if not state.v3.has("turn") or typeof(state.v3.turn) != TYPE_DICTIONARY:
		state.v3["turn"] = {
			"previous_card_type": "",
			"previous_card_definition_id": "",
			"previous_card_instance_id": "",
			"played_types": {},
			"link_work_count": 0,
			"retrieved_strategy": false,
			"erosion_events": 0,
			"compound_used": false,
			"induced_triggers": {},
			"induced_first": {},
			"erosion_draws": 0,
			"summoned_partner": false,
			"healed_partner": false,
			"first_cooperation": false,
			"partner_extra": {},
			"chapter_window_ran": [],
			"chapter_extra_used": {},
			"paid_citation": false,
			"p04_passive_used": false,
		}
	return state.v3.turn


func _v3_battle(state: BattleState) -> Dictionary:
	if not state.v3.has("battle") or typeof(state.v3.battle) != TYPE_DICTIONARY:
		state.v3["battle"] = {"instance_plays": {}}
	if not state.v3.battle.has("instance_plays"):
		state.v3.battle["instance_plays"] = {}
	return state.v3.battle


func _reset_v3_turn(state: BattleState) -> void:
	state.v3["turn"] = {
		"previous_card_type": "",
		"previous_card_definition_id": "",
		"previous_card_instance_id": "",
		"played_types": {},
		"link_work_count": 0,
		"retrieved_strategy": false,
		"erosion_events": 0,
		"compound_used": false,
		"induced_triggers": {},
		"induced_first": {},
		"erosion_draws": 0,
		"summoned_partner": false,
		"healed_partner": false,
		"first_cooperation": false,
		"partner_extra": {},
		"chapter_window_ran": [],
		"chapter_extra_used": {},
		"paid_citation": false,
		"p04_passive_used": false,
	}
	if state.v3.has("paper") and typeof(state.v3.paper) == TYPE_DICTIONARY:
		state.v3.paper["turn_names"] = []
	state.v3["pending_work_bonus"] = 0
	state.v3["pending_cost_discount"] = {"amount": 0, "min_base_cost": 0}


func _v3_add_work_bonus(state: BattleState, amount: int) -> void:
	var current := int(state.v3.get("pending_work_bonus", 0))
	state.v3["pending_work_bonus"] = mini(12, current + maxi(0, amount))


func _v3_take_work_bonus(state: BattleState) -> int:
	var amount := maxi(0, int(state.v3.get("pending_work_bonus", 0)))
	state.v3["pending_work_bonus"] = 0
	return amount


func _v3_add_cost_discount(state: BattleState, amount: int, min_base_cost: int) -> void:
	var pending: Variant = state.v3.get("pending_cost_discount", {})
	var current := 0
	var current_min := 0
	if typeof(pending) == TYPE_DICTIONARY:
		current = int(pending.get("amount", 0))
		current_min = int(pending.get("min_base_cost", 0))
	var merged_min := min_base_cost
	if current > 0 and current_min > 0:
		merged_min = maxi(current_min, min_base_cost)
	state.v3["pending_cost_discount"] = {
		"amount": mini(1, current + maxi(0, amount)),
		"min_base_cost": merged_min,
	}


func _v3_cost_discount_applies(state: BattleState, face: Dictionary) -> int:
	var pending: Variant = state.v3.get("pending_cost_discount", {})
	if typeof(pending) != TYPE_DICTIONARY:
		return 0
	var amount := int(pending.get("amount", 0))
	if amount <= 0 or str(face.get("type", "")) != "work":
		return 0
	if int(face.get("cost", 0)) < int(pending.get("min_base_cost", 0)):
		return 0
	return amount


func _v3_record_card_played(
	state: BattleState, resolution: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if not bool(resolution.get("v3", false)):
		return GameResult.success(null)
	var card_id := str(resolution.get("card_instance_id", ""))
	var card_type := str(resolution.get("card_type", ""))
	var definition_id := str(resolution.get("definition_id", ""))
	var turn := _v3_turn(state)
	var battle := _v3_battle(state)
	var plays: Dictionary = battle.instance_plays
	plays[card_id] = int(plays.get(card_id, 0)) + 1
	var definition := _catalog.get_definition("card", definition_id)
	if definition.ok:
		var per_turn := int(definition.data.get("limits", {}).get("per_instance_per_turn", 0))
		if per_turn > 0:
			var limit_key := BattleState.counter_key(
				GameConstants.COUNTER_SCOPE_INSTANCE_ROUND, card_id, &"v3_play"
			)
			state.counters[limit_key] = int(state.counters.get(limit_key, 0)) + 1
	var paper_recorded := _v3_paper_record(state, resolution, rng, events)
	if not paper_recorded.ok:
		return paper_recorded
	if state.character_id == "P02":
		var played_name := str(resolution.get("v3_paper_name", ""))
		if not played_name.is_empty():
			var paper_turn := _v3_paper(state)
			if not paper_turn.turn_names.has(played_name):
				paper_turn.turn_names.append(played_name)
	var played_types: Dictionary = turn.played_types
	played_types[card_type] = int(played_types.get(card_type, 0)) + 1
	var link_work := card_type == "work" and bool(resolution.get("v3_link", false))
	if link_work:
		turn.link_work_count = int(turn.link_work_count) + 1
	turn.previous_card_type = card_type
	turn.previous_card_definition_id = definition_id
	turn.previous_card_instance_id = card_id
	if card_type == "cooperation" and not bool(turn.first_cooperation):
		turn.first_cooperation = true
		var coop_trigger := _v3_run_ability_trigger(
			state, "first_cooperation_resolved", {"first_cooperation": true}, rng, events
		)
		if not coop_trigger.ok:
			return coop_trigger
	if (
		state.character_id == "P01"
		and card_type == "work"
		and link_work
		and not bool(turn.retrieved_strategy)
	):
		var retrieved := _v3_try_passive_retrieve(state, resolution, events)
		if retrieved:
			var passive_trigger := _v3_run_ability_trigger(
				state, "passive_retrieve_success", {"passive_retrieve_success": true}, rng, events
			)
			if not passive_trigger.ok:
				return passive_trigger
	if link_work:
		var link_trigger := _v3_run_ability_trigger(
			state, "link_work_resolved", {"link_work": true}, rng, events
		)
		if not link_trigger.ok:
			return link_trigger
	if card_type == "work":
		var work_trigger := _v3_run_ability_trigger(
			state,
			"work_resolved",
			{"base_cost": int(resolution.get("v3_base_cost", 0)), "link_work": link_work},
			rng,
			events
		)
		if not work_trigger.ok:
			return work_trigger
	elif card_type == "strategy":
		var strategy_trigger := _v3_run_ability_trigger(
			state,
			"strategy_resolved",
			{
				"instance_was_played_before":
				bool(resolution.get("v3_instance_was_played_before", false))
			},
			rng,
			events
		)
		if not strategy_trigger.ok:
			return strategy_trigger
	return GameResult.success(null)


func _v3_try_passive_retrieve(
	state: BattleState, resolution: Dictionary, events: Array[RuleEvent]
) -> bool:
	var turn := _v3_turn(state)
	var previous_id := str(resolution.get("v3_previous_card_instance_id", ""))
	var previous_definition := str(resolution.get("v3_previous_card_definition_id", ""))
	if previous_id.is_empty() or previous_definition.is_empty():
		return false
	if not state.zones.discard.has(previous_id):
		return false
	var definition := _catalog.get_definition("card", previous_definition)
	if not definition.ok:
		return false
	if str(definition.data.get("type", "")) != "strategy":
		return false
	if not bool(definition.data.get("permanent", true)):
		return false
	turn.retrieved_strategy = true
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return false
	if state.zones.hand.size() >= int(ruleset.data.battle.hand_limit):
		return false
	state.zones.discard.erase(previous_id)
	state.zones.hand.append(previous_id)
	_add_event(
		events,
		"card_retrieved",
		str(resolution.get("card_instance_id", "")),
		[previous_id],
		{"definition_id": previous_definition, "reason": "P01_passive"}
	)
	return true


func _v3_ability_limit(ability: Dictionary) -> int:
	var limit := str(ability.get("limit", ""))
	for effect: Variant in ability.get("effects", []):
		if typeof(effect) == TYPE_DICTIONARY:
			var effect_limit := str(effect.get("limit", ""))
			if effect_limit == "twice_per_turn":
				return 2
			if not effect_limit.is_empty() and limit.is_empty():
				limit = effect_limit
	if limit == "twice_per_turn":
		return 2
	return 1


func _v3_run_ability_trigger(
	state: BattleState,
	trigger: String,
	context: Dictionary,
	rng: RandomSource,
	events: Array[RuleEvent],
) -> GameResult:
	if not state.v3.has("abilities"):
		return GameResult.success(null)
	for ability: Variant in state.v3.abilities:
		if typeof(ability) != TYPE_DICTIONARY:
			continue
		if str(ability.get("trigger", "")) != trigger:
			continue
		if state.round_index < int(ability.get("activate_round", 0)):
			continue
		if (
			typeof(ability.get("condition", {})) == TYPE_DICTIONARY
			and not ability.get("condition", {}).is_empty()
			and not _v3_condition(state, ability.condition, context)
		):
			continue
		if int(ability.get("uses_round", 0)) != state.round_index:
			ability.uses_round = state.round_index
			ability.uses_this_round = 0
		if int(ability.get("uses_this_round", 0)) >= _v3_ability_limit(ability):
			continue
		var applied := false
		for effect: Variant in ability.get("effects", []):
			if typeof(effect) != TYPE_DICTIONARY:
				continue
			if effect.has("condition") and not _v3_condition(state, effect.condition, context):
				continue
			var executed := _v3_execute_ability_effect(state, effect, context, rng, events)
			if not executed.ok:
				return executed
			applied = true
		if applied:
			for effect: Variant in ability.get("extra_effects", []):
				if typeof(effect) != TYPE_DICTIONARY:
					continue
				if effect.has("condition") and not _v3_condition(state, effect.condition, context):
					continue
				var extra := _v3_execute_ability_effect(state, effect, context, rng, events)
				if not extra.ok:
					return extra
			ability.uses_this_round = int(ability.get("uses_this_round", 0)) + 1
			_add_event(
				events,
				"v3_ability_triggered",
				str(ability.get("ability_id", "")),
				[],
				{"definition_id": str(ability.get("definition_id", "")), "trigger": trigger}
			)
	return GameResult.success(null)


func _v3_execute_ability_effect(
	state: BattleState,
	effect: Dictionary,
	context: Dictionary,
	rng: RandomSource,
	events: Array[RuleEvent],
) -> GameResult:
	match str(effect.get("op", "")):
		"relax":
			state.player.relax = (
				int(state.player.get("relax", 0)) + maxi(0, int(effect.get("amount", 0)))
			)
			return GameResult.success(null)
		"draw":
			_draw_cards(state, maxi(0, int(effect.get("amount", 0))), rng, events)
			return GameResult.success(null)
		"gain_focus":
			var ruleset := _loaded_ruleset()
			if not ruleset.ok:
				return ruleset
			state.player.focus = mini(
				int(ruleset.data.battle.focus_cap),
				int(state.player.get("focus", 0)) + maxi(0, int(effect.get("amount", 0)))
			)
			return GameResult.success(null)
		"add_work_bonus":
			_v3_add_work_bonus(state, int(effect.get("amount", 0)))
			return GameResult.success(null)
		"gain_synergy":
			_v3_gain_synergy(state, int(effect.get("amount", 0)))
			return GameResult.success(null)
		"apply_status":
			var targets := _v3_ability_targets(state, effect, context)
			return _v3_apply_status_batch(
				state,
				str(effect.get("status", "")),
				int(effect.get("stacks", 1)),
				targets,
				false,
				false,
				events
			)
		"status_complete":
			for target_id in _v3_ability_targets(state, effect, context):
				var completed := _v3_status_complete_task(
					state, target_id, int(effect.get("amount", 0)), rng, events
				)
				if not completed.ok:
					return completed
			return GameResult.success(null)
		"modify_erosion_window":
			return GameResult.success(null)
		_:
			return _failure(
				GameConstants.ERROR_ENGINE_NOT_READY,
				"battle.v3.ability_effect_not_ready",
				{"op": str(effect.get("op", ""))}
			)


func _v3_ability_targets(
	state: BattleState, effect: Dictionary, context: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	var target := str(effect.get("target", ""))
	if target == "all_tasks":
		for task: Dictionary in state.tasks:
			result.append(str(task.get("task_id", "")))
		return result
	if target == "earliest_task":
		var earliest := _first_eligible_task(state)
		if not earliest.is_empty():
			result.append(earliest)
		return result
	var context_target := str(context.get("target_id", ""))
	if not context_target.is_empty():
		result.append(context_target)
		return result
	var fallback := _first_eligible_task(state)
	if not fallback.is_empty():
		result.append(fallback)
	return result


func _v3_execute_effects(
	state: BattleState, effects: Array, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var result := _execute_v3_card_effect(state, effect, rng, events)
		if not result.ok:
			return result
		if typeof(result.data) == TYPE_DICTIONARY:
			return result
		if state.phase == "finished":
			break
	return GameResult.success(null)


func _v3_card_amplify(state: BattleState) -> int:
	if typeof(state.resolution) == TYPE_DICTIONARY and bool(state.resolution.get("v3_auto", false)):
		return 0
	return _v3_consume_amplify(state)


func _v3_paper(state: BattleState) -> Dictionary:
	if not state.v3.has("paper") or typeof(state.v3.paper) != TYPE_DICTIONARY:
		state.v3["paper"] = {
			"open": false,
			"progress": 0,
			"citations": 0,
			"modifier": 0,
			"amplify": 0,
			"used_names": [],
			"publication_id": "",
			"chapters": [],
			"turn_names": [],
		}
	return state.v3.paper


func _v3_chapter_count(state: BattleState) -> int:
	return _v3_paper(state).chapters.size()


func _v3_gain_citation(
	state: BattleState, amount: int, rng: RandomSource, events: Array[RuleEvent]
) -> int:
	var paper := _v3_paper(state)
	var gained := 0
	for _index in maxi(0, amount):
		if int(paper.citations) >= 5:
			break
		var layer := int(paper.citations) + 1
		var cost := maxi(0, layer - 2)
		if int(state.player.get("focus", 0)) < cost:
			_draw_cards(state, 1, rng, events)
			break
		state.player.focus = int(state.player.get("focus", 0)) - cost
		if cost > 0:
			_v3_turn(state).paid_citation = true
		paper.citations = layer
		gained += 1
	return gained


func _v3_consume_amplify(state: BattleState) -> int:
	var paper := _v3_paper(state)
	var amount := int(paper.get("amplify", 0))
	paper.amplify = 0
	return maxi(0, amount)


func _v3_paper_record(
	state: BattleState, resolution: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if state.character_id != "P02" or not bool(_v3_paper(state).open):
		return GameResult.success(null)
	var definition_id := str(resolution.get("definition_id", ""))
	var definition := _catalog.get_definition("card", definition_id)
	if not definition.ok:
		return GameResult.success(null)
	if not bool(definition.data.get("flags", {}).get("paper_record", true)):
		return GameResult.success(null)
	var paper := _v3_paper(state)
	var name_key := str(definition.data.get("name_key", definition_id))
	var used: Array = paper.used_names
	var was_used := used.has(name_key)
	if not was_used:
		used.append(name_key)
		if int(paper.progress) < 10:
			paper.progress = int(paper.progress) + 1
			var trigger := _v3_run_ability_trigger(
				state, "paper_progress_gained", {"paper_progress_gained": true}, rng, events
			)
			if not trigger.ok:
				return trigger
			if (
				bool(definition.data.get("permanent", true))
				and not bool(definition.data.get("flags", {}).get("unique", false))
			):
				var unused_trigger := _v3_run_ability_trigger(
					state,
					"first_unused_permanent_card_resolved",
					{"first_unused_permanent_card_resolved": true},
					rng,
					events
				)
				if not unused_trigger.ok:
					return unused_trigger
	else:
		_v3_gain_citation(state, 1, rng, events)
	return GameResult.success(null)


func _v3_open_paper(state: BattleState, events: Array[RuleEvent]) -> void:
	var paper := _v3_paper(state)
	paper.open = true
	paper.progress = 0
	paper.citations = 0
	paper.modifier = 0
	paper.amplify = 0
	paper.used_names = []
	var publication := ""
	for card_id in state.card_by_id:
		if str(state.card_by_id[card_id].get("definition_id", "")) == "R3-T201":
			publication = str(card_id)
			break
	if publication.is_empty():
		publication = _new_instance_id(state, "c")
		state.card_by_id[publication] = {
			"card_id": publication,
			"definition_id": "R3-T201",
			"origin_card_id": "",
			"upgrade_level": 0,
			"temporary_modifiers": {},
		}
	paper.publication_id = publication
	if state.zones.hand.has(publication):
		return
	for zone in ["draw", "discard"]:
		if state.zones[zone].has(publication):
			state.zones[zone].erase(publication)
			break
	if state.zones.hand.size() < 10:
		state.zones.hand.append(publication)
	else:
		state.zones.discard.append(publication)


func _v3_paper_publish(
	state: BattleState, resolution: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var paper := _v3_paper(state)
	var progress := int(paper.progress) * 7 + int(paper.citations) * 6 + int(paper.modifier)
	var completion := clampi(progress, 0, 100)
	var targets: Array = resolution.get("locked_target_ids", [])
	if targets.is_empty():
		targets = resolution.get("target_ids", [])
	var main_bonus := 0
	if bool(resolution.get("v3", false)) and bool(resolution.get("first_work_card", false)):
		main_bonus += _consume_v3_first_work_bonus(state)
	main_bonus += _v3_take_work_bonus(state)
	var ruleset := _loaded_ruleset()
	for index in targets.size():
		var task_id := str(targets[index])
		var amount := completion + 10 if index == 0 else int(floor(completion / 2.0))
		if completion >= 100:
			amount += 20
		if index == 0:
			amount += main_bonus
		if (
			bool(resolution.get("v3", false))
			and ruleset.ok
			and _status_stacks(state, "vulnerability", task_id) > 0
		):
			var percent := int(
				ruleset.data.statuses.get("vulnerability", {}).get("completion_percent", 125)
			)
			amount = int(floor(amount * percent / 100.0))
		var completed := _v3_status_complete_task(state, task_id, amount, rng, events)
		if not completed.ok:
			return completed
		if state.phase == "finished":
			break
	paper.open = false
	paper.progress = 0
	paper.citations = 0
	paper.modifier = 0
	paper.amplify = 0
	paper.used_names = []
	for entry: Variant in paper.chapters:
		if typeof(entry) == TYPE_DICTIONARY:
			var chapter_id := str(entry.get("card_id", ""))
			if state.card_by_id.has(chapter_id):
				state.zones.discard.append(chapter_id)
				_add_event(
					events,
					"chapter_returned",
					str(resolution.get("card_instance_id", "")),
					[chapter_id],
					{"reason": "publication"}
				)
	paper.chapters = []
	_add_event(events, "paper_published", "", [], {"completion": completion})
	return GameResult.success(null)


func _v3_chapter_deploy(
	state: BattleState, card_id: String, events: Array[RuleEvent]
) -> GameResult:
	var paper := _v3_paper(state)
	if not bool(paper.open):
		return GameResult.success(null)
	var card: Dictionary = state.card_by_id.get(card_id, {})
	var definition_id := str(card.get("definition_id", ""))
	var origin := str(card.get("origin_card_id", ""))
	for entry: Variant in paper.chapters:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("definition_id", "")) == definition_id:
			return GameResult.success(null)
		if not origin.is_empty() and str(entry.get("card_id", "")) == origin:
			return GameResult.success(null)
	if paper.chapters.size() >= 3:
		var candidates: Array = []
		for entry: Variant in paper.chapters:
			if typeof(entry) == TYPE_DICTIONARY:
				candidates.append(_card_candidate(state, str(entry.get("card_id", ""))))
		var choice_id := _new_instance_id(state, "ch")
		return (
			GameResult
			. success(
				{
					"choice_id": choice_id,
					"kind": "chapter_replace",
					"prompt_key": "choice.battle.chapter_replace",
					"candidates": candidates,
					"min_count": 1,
					"max_count": 1,
					"source_card_id": card_id,
					"effect_amount": 1,
				}
			)
		)
	(
		paper
		. chapters
		. append(
			{
				"card_id": card_id,
				"definition_id": definition_id,
				"deployed_round": state.round_index,
			}
		)
	)
	_add_event(events, "chapter_deployed", card_id, [card_id], {"definition_id": definition_id})
	return GameResult.success(true)


func _v3_run_chapter_entry(
	state: BattleState, entry: Dictionary, extra: bool, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var card_id := str(entry.get("card_id", ""))
	var card: Dictionary = state.card_by_id.get(card_id, {})
	var definition := _catalog.get_definition("card", str(card.get("definition_id", "")))
	if not definition.ok:
		return GameResult.success(null)
	var chapter: Dictionary = definition.data.get("chapter", {})
	var resident: Dictionary = chapter.get("resident", {})
	if int(card.get("upgrade_level", 0)) > 0 and chapter.has("upgraded_resident"):
		resident = chapter.get("upgraded_resident", resident)
	var effects: Array = resident.get("effects", [])
	if effects.is_empty():
		return GameResult.success(null)
	var turn := _v3_turn(state)
	var previous: Variant = state.resolution
	var ran: Array = turn.get("chapter_window_ran", [])
	state.resolution = {
		"card_instance_id": card_id,
		"definition_id": str(card.get("definition_id", "")),
		"card_type": "strategy",
		"v3": true,
		"v3_auto": not extra,
		"v3_other_chapter_count": ran.size(),
		"v3_compound_candidates": [],
		"v3_induced_snapshot": [],
		"v3_target_induced_snapshot": {},
		"effects": effects,
		"cursor": 0,
		"target_ids": [],
		"choice": null,
		"choice_counts": {},
		"discarded_in_resolution": [],
		"all_tasks": false,
		"locked_target_ids": [],
	}
	var result := _v3_execute_effects(state, effects, rng, events)
	state.resolution = previous
	if result.ok and state.phase != "finished":
		ran.append(str(card.get("definition_id", "")))
		turn["chapter_window_ran"] = ran
		_add_event(
			events,
			"chapter_ran",
			card_id,
			[card_id],
			{"definition_id": str(card.get("definition_id", "")), "extra": extra}
		)
	return result


func _v3_run_chapter_window(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var paper := _v3_paper(state)
	if paper.chapters.is_empty():
		return GameResult.success(null)
	var turn := _v3_turn(state)
	turn["chapter_window_ran"] = []
	for entry: Variant in paper.chapters:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("deployed_round", 0)) >= state.round_index:
			continue
		var ran := _v3_run_chapter_entry(state, entry, false, rng, events)
		if not ran.ok:
			return ran
		if state.phase == "finished":
			return GameResult.success(null)
	var end_trigger := _v3_run_ability_trigger(
		state, "chapter_window_end", {"chapter_count": paper.chapters.size()}, rng, events
	)
	if not end_trigger.ok:
		return end_trigger
	return GameResult.success(null)


func _v3_chapter_run(
	state: BattleState, amount: int, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var paper := _v3_paper(state)
	var turn := _v3_turn(state)
	var used: Dictionary = turn.get("chapter_extra_used", {})
	var count := 0
	for entry: Variant in paper.chapters:
		if count >= maxi(0, amount):
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var card_id := str(entry.get("card_id", ""))
		if bool(used.get(card_id, false)):
			continue
		var ran := _v3_run_chapter_entry(state, entry, true, rng, events)
		if not ran.ok:
			return ran
		used[card_id] = true
		count += 1
		if state.phase == "finished":
			break
	turn["chapter_extra_used"] = used
	return GameResult.success(null)


func _v3_chapter_return(state: BattleState, amount: int, events: Array[RuleEvent]) -> int:
	var paper := _v3_paper(state)
	var removed := 0
	for index in mini(maxi(0, amount), paper.chapters.size()):
		var entry: Variant = paper.chapters.pop_front()
		if typeof(entry) == TYPE_DICTIONARY:
			state.zones.discard.append(str(entry.get("card_id", "")))
			removed += 1
	return removed


func _v3_swap_chapter_slots(state: BattleState, events: Array[RuleEvent]) -> void:
	var paper := _v3_paper(state)
	if paper.chapters.size() < 2:
		return
	var first: Variant = paper.chapters[0]
	paper.chapters[0] = paper.chapters[1]
	paper.chapters[1] = first
	_add_event(events, "chapter_slots_swapped", "", [], {"count": paper.chapters.size()})


func _v3_search_draw_chapter(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	for card_id in state.zones.draw.duplicate():
		var card: Dictionary = state.card_by_id.get(card_id, {})
		var definition := _catalog.get_definition("card", str(card.get("definition_id", "")))
		if definition.ok and definition.data.has("chapter"):
			state.zones.draw.erase(card_id)
			if state.zones.hand.size() < 10:
				state.zones.hand.append(card_id)
				_add_event(
					events,
					"card_drawn",
					"",
					[card_id],
					{
						"definition_id": str(card.get("definition_id", "")),
						"from_zone": "draw",
						"to_zone": "hand"
					}
				)
			else:
				state.zones.discard.append(card_id)
			var shuffled := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, state.zones.draw)
			if shuffled.ok:
				state.zones.draw = shuffled.data
			return GameResult.success(null)
	_draw_cards(state, 1, rng, events)
	return GameResult.success(null)


func _v3_synergy(state: BattleState) -> int:
	return maxi(0, int(state.v3.get("synergy", 0)))


func _v3_gain_synergy(state: BattleState, amount: int) -> void:
	state.v3["synergy"] = mini(6, _v3_synergy(state) + maxi(0, amount))


func _v3_spend_synergy(state: BattleState, amount: int, optional: bool = false) -> int:
	var available := _v3_synergy(state)
	var spend := maxi(0, amount)
	if spend > available:
		if optional:
			return 0
		return -1
	state.v3["synergy"] = available - spend
	return spend


func _v3_partner_extra_action(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var turn := _v3_turn(state)
	var used: Dictionary = turn.partner_extra
	var targets: Array[String] = []
	if str(effect.get("target", "one")) == "all_eligible":
		for unit_id in _ordered_unit_ids(state):
			targets.append(unit_id)
	else:
		if typeof(state.resolution) == TYPE_DICTIONARY:
			for unit_id in state.resolution.get("target_ids", []):
				targets.append(str(unit_id))
		if targets.is_empty():
			for unit_id in _ordered_unit_ids(state):
				targets.append(unit_id)
	var acted := false
	for unit_id in targets:
		if bool(used.get(unit_id, false)):
			continue
		if _unit_index(state, unit_id) < 0:
			continue
		var action := _v3_unit_action(state, unit_id, rng, events)
		if not action.ok:
			return action
		used[unit_id] = true
		acted = true
		if state.phase == "finished":
			return GameResult.success(null)
		if str(effect.get("target", "one")) != "all_eligible":
			break
	if not acted:
		return _failure(
			GameConstants.ERROR_INVALID_TARGET, "error.play.no_partner_extra_action", {}
		)
	return GameResult.success(null)


func _v3_unit_action(
	state: BattleState, unit_id: String, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var unit_index := _unit_index(state, unit_id)
	if unit_index < 0:
		return GameResult.success(null)
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
			var before := int(task.get("work_remaining", 0))
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
				var advanced := _advance_or_remove_task(state, task_index, events, rng)
				if not advanced.ok:
					return advanced
			_check_battle_outcome(state, events)
			if state.phase == "finished":
				return GameResult.success(null)
	unit.actions_taken = int(unit.get("actions_taken", 0)) + 1
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	var vitality_before := int(unit.get("vitality", 0))
	unit.vitality = maxi(
		0, vitality_before - int(ruleset.data.battle.get("unit_action_vitality_cost", 1))
	)
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
	return GameResult.success(null)


func _v3_summon_partner(
	state: BattleState, effect: Dictionary, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var summon_effect := {
		"unit": str(effect.get("unit", "")),
		"vitality_bonus": int(effect.get("vitality_bonus", 0)),
		"cooperation_bonus": int(effect.get("cooperation_bonus", 0)),
	}
	if effect.has("vitality"):
		summon_effect["vitality_override"] = int(effect.vitality)
	if effect.has("max_vitality"):
		summon_effect["max_vitality_override"] = int(effect.max_vitality)
	if effect.has("cooperation"):
		summon_effect["cooperation_override"] = int(effect.cooperation)
	var summoned := _summon_unit(state, summon_effect, rng, events)
	if summoned.ok:
		_v3_turn(state).summoned_partner = true
	return summoned


func _v3_partner_heal(
	state: BattleState, effect: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var targets: Array[String] = []
	if str(effect.get("target", "one")) == "all":
		for unit_id in _ordered_unit_ids(state):
			targets.append(unit_id)
	else:
		if typeof(state.resolution) == TYPE_DICTIONARY:
			for unit_id in state.resolution.get("target_ids", []):
				targets.append(str(unit_id))
		if targets.is_empty():
			for unit_id in _ordered_unit_ids(state):
				targets.append(unit_id)
	var healed := false
	for unit_id in targets:
		var index := _unit_index(state, unit_id)
		if index < 0:
			continue
		var unit: Dictionary = state.units[index]
		var before := int(unit.get("vitality", 0))
		var maximum := int(unit.get("max_vitality", before))
		unit.vitality = mini(maximum, before + maxi(0, int(effect.get("amount", 0))))
		if unit.vitality != before:
			healed = true
			_add_event(
				events,
				"unit_healed",
				str(state.resolution.get("card_instance_id", "")),
				[unit_id],
				{"before": before, "after": unit.vitality}
			)
	if healed:
		_v3_turn(state).healed_partner = true
	return GameResult.success(null)


func _v3_partner_retreat(
	state: BattleState, effect: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var target := ""
	if typeof(state.resolution) == TYPE_DICTIONARY:
		var targets: Array = state.resolution.get("target_ids", [])
		if not targets.is_empty():
			target = str(targets.front())
	if target.is_empty():
		var ordered := _ordered_unit_ids(state)
		if not ordered.is_empty():
			target = ordered.front()
	var index := _unit_index(state, target)
	if index < 0:
		return _failure(GameConstants.ERROR_INVALID_TARGET, "error.play.no_partner_to_retreat", {})
	var unit: Dictionary = state.units[index]
	state.units.remove_at(index)
	_remove_holder_statuses(state, target)
	_add_event(
		events,
		"unit_departed",
		str(state.resolution.get("card_instance_id", "")),
		[target],
		{"definition_id": str(unit.get("definition_id", "")), "reason": "retreat"}
	)
	return GameResult.success(null)


func _v3_debuff_kinds(state: BattleState, task_id: String) -> Array[String]:
	var result: Array[String] = []
	for status_id in ["erosion", "induced", "brittle", "feebleness", "weakness", "vulnerability"]:
		if _status_stacks(state, status_id, task_id) > 0:
			result.append(status_id)
	return result


func _v3_apply_status_batch(
	state: BattleState,
	status_id: String,
	stacks: int,
	target_ids: Array[String],
	count_event: bool,
	allow_compound: bool,
	events: Array[RuleEvent],
) -> GameResult:
	var gained_any := false
	for target_id in target_ids:
		var before := _status_stacks(state, status_id, target_id)
		var other_kinds := _v3_debuff_kinds(state, target_id)
		other_kinds.erase(status_id)
		var applied := _gain_status_on_target(
			state,
			{"status": status_id, "stacks": maxi(1, stacks), "target": "task"},
			target_id,
			events
		)
		if not applied.ok:
			return applied
		var after := _status_stacks(state, status_id, target_id)
		if after <= before:
			continue
		gained_any = true
		if allow_compound and before == 0 and not other_kinds.is_empty():
			var task_index := _task_index(state, target_id)
			if task_index >= 0 and typeof(state.resolution) == TYPE_DICTIONARY:
				var candidates: Array = state.resolution.get("v3_compound_candidates", [])
				(
					candidates
					. append(
						{
							"task_id": target_id,
							"status_id": status_id,
							"order": candidates.size(),
							"entered_order": int(state.tasks[task_index].get("entered_order", 0)),
						}
					)
				)
				state.resolution.v3_compound_candidates = candidates
	if count_event and status_id == "erosion" and gained_any:
		var turn := _v3_turn(state)
		turn.erosion_events = int(turn.erosion_events) + 1
	return GameResult.success(null)


func _v3_source_stacks(state: BattleState, spec: Dictionary) -> int:
	if typeof(state.resolution) != TYPE_DICTIONARY:
		return 0
	var targets: Array = state.resolution.get("target_ids", [])
	if targets.is_empty():
		return 0
	var stacks := _status_stacks(state, str(spec.get("status", "")), str(targets.front()))
	stacks = mini(stacks, int(spec.get("cap", stacks)))
	stacks += int(spec.get("bonus", 0))
	return maxi(0, stacks)


func _v3_apply_compound_reaction(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if state.character_id != "P03":
		return GameResult.success(null)
	if typeof(state.resolution) != TYPE_DICTIONARY:
		return GameResult.success(null)
	var turn := _v3_turn(state)
	if bool(turn.compound_used):
		return GameResult.success(null)
	var candidates: Array = state.resolution.get("v3_compound_candidates", [])
	if candidates.is_empty():
		return GameResult.success(null)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary):
			if int(a.entered_order) != int(b.entered_order):
				return int(a.entered_order) < int(b.entered_order)
			return int(a.order) < int(b.order)
	)
	var ruleset := _loaded_ruleset()
	if not ruleset.ok:
		return ruleset
	for candidate: Dictionary in candidates:
		var task_id := str(candidate.get("task_id", ""))
		var status_id := str(candidate.get("status_id", ""))
		if _task_index(state, task_id) < 0:
			continue
		var status_index := _status_index(state, status_id, task_id)
		if status_index < 0:
			continue
		var status: Dictionary = state.statuses[status_index]
		var before := int(status.get("stacks", 0))
		var cap := int(ruleset.data.statuses.get(status_id, {}).get("cap", before + 1))
		var after := mini(cap, before + 1)
		if after <= before:
			continue
		status.stacks = after
		turn.compound_used = true
		_add_event(
			events,
			"v3_compound_reaction",
			str(state.resolution.get("card_instance_id", "")),
			[task_id],
			{"status_id": status_id, "before": before, "after": after}
		)
		return _v3_run_ability_trigger(
			state, "compound_reaction_success", {"compound_reaction_success": true}, rng, events
		)
	return GameResult.success(null)


func _v3_settle_erosion_events(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var turn := _v3_turn(state)
	var count := int(turn.get("erosion_events", 0))
	if count <= 0:
		return GameResult.success(null)
	return _v3_run_ability_trigger(
		state, "erosion_applied_event", {"erosion_events": count}, rng, events
	)


func _v3_status_complete_task(
	state: BattleState, task_id: String, amount: int, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var task_index := _task_index(state, task_id)
	if task_index < 0:
		return GameResult.success(null)
	var task: Dictionary = state.tasks[task_index]
	var before_shield := int(task.get("shield", 0))
	var before_work := int(task.get("work_remaining", 0))
	var shield_loss := mini(before_shield, maxi(0, amount))
	var applied := maxi(0, amount) - shield_loss
	task.shield = before_shield - shield_loss
	task.work_remaining = maxi(0, before_work - applied)
	_add_event(
		events,
		"completion_applied",
		"",
		[task_id],
		{
			"amount": amount,
			"shield_before": before_shield,
			"shield_after": task.shield,
			"work_before": before_work,
			"work_after": task.work_remaining,
			"segment_index": 0,
		}
	)
	if int(task.work_remaining) == 0:
		var advanced := _advance_or_remove_task(state, task_index, events, rng)
		if not advanced.ok:
			return advanced
		_check_battle_outcome(state, events)
	return GameResult.success(null)


func _v3_induced_trigger_target(
	state: BattleState, task_id: String, stacks: int, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var turn := _v3_turn(state)
	var triggers: Dictionary = turn.induced_triggers
	var used := int(triggers.get(task_id, 0))
	if used >= 4:
		return GameResult.success(null)
	triggers[task_id] = used + 1
	var completed := _v3_status_complete_task(state, task_id, maxi(0, stacks), rng, events)
	if not completed.ok:
		return completed
	if state.phase == "finished":
		return GameResult.success(null)
	var first: Dictionary = turn.induced_first
	if not bool(first.get(task_id, false)):
		first[task_id] = true
		return _v3_run_ability_trigger(
			state,
			"induced_trigger",
			{"first_induced_trigger": true, "target_id": task_id},
			rng,
			events
		)
	return GameResult.success(null)


func _v3_induced_window(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	if typeof(state.resolution) != TYPE_DICTIONARY:
		return GameResult.success(null)
	var snapshot: Array = state.resolution.get("v3_induced_snapshot", [])
	for entry: Variant in snapshot:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var task_id := str(entry.get("task_id", ""))
		if _task_index(state, task_id) >= 0:
			var triggered := _v3_induced_trigger_target(
				state, task_id, int(entry.get("stacks", 0)), rng, events
			)
			if not triggered.ok:
				return triggered
		if state.phase == "finished":
			return GameResult.success(null)
	return GameResult.success(null)


func _v3_erosion_window(
	state: BattleState, rng: RandomSource, events: Array[RuleEvent]
) -> GameResult:
	var times := 1
	if state.v3.has("abilities"):
		for ability: Variant in state.v3.abilities:
			if typeof(ability) != TYPE_DICTIONARY:
				continue
			if state.round_index < int(ability.get("activate_round", 0)):
				continue
			for effect: Variant in ability.get("effects", []):
				if (
					typeof(effect) == TYPE_DICTIONARY
					and str(effect.get("op", "")) == "modify_erosion_window"
				):
					times = maxi(times, int(effect.get("times", 1)))
	var snapshot: Array[String] = []
	for task: Dictionary in state.tasks:
		if _status_stacks(state, "erosion", str(task.get("task_id", ""))) > 0:
			snapshot.append(str(task.get("task_id", "")))
	for task_id in snapshot:
		for _index in times:
			var task_index := _task_index(state, task_id)
			if task_index < 0:
				break
			var stacks := _status_stacks(state, "erosion", task_id)
			if stacks <= 0:
				break
			var completed := _v3_status_complete_task(state, task_id, stacks, rng, events)
			if not completed.ok:
				return completed
			if state.phase == "finished":
				return GameResult.success(null)
			task_index = _task_index(state, task_id)
			if task_index < 0:
				break
			var status_index := _status_index(state, "erosion", task_id)
			if status_index < 0:
				break
			var status: Dictionary = state.statuses[status_index]
			var before := int(status.get("stacks", 0))
			var after := before - 1
			if after <= 0:
				state.statuses.remove_at(status_index)
				_add_event(
					events,
					"status_removed",
					"",
					[task_id],
					{
						"status_definition_id": "erosion",
						"before": before,
						"after": 0,
						"amount": before,
						"reason": "erosion_window",
					}
				)
			else:
				status.stacks = after
				_add_event(
					events,
					"status_changed",
					"",
					[task_id],
					{
						"status_definition_id": "erosion",
						"before": before,
						"after": after,
						"amount": -1,
						"reason": "erosion_window",
					}
				)
	return GameResult.success(null)


func _register_v3_ability(
	state: BattleState, face: Dictionary, events: Array[RuleEvent]
) -> GameResult:
	var ability: Dictionary = face.get("ability", {})
	var triggers: Array = ability.get("triggers", [])
	if triggers.is_empty():
		return GameResult.success(null)
	var definition_id := str(face.get("id", ""))
	if not state.v3.has("abilities"):
		state.v3["abilities"] = []
	var abilities: Array = state.v3.abilities
	if str(ability.get("stack", "unique_name")) == "unique_name":
		for existing: Variant in abilities:
			if (
				typeof(existing) == TYPE_DICTIONARY
				and str(existing.get("definition_id", "")) == definition_id
			):
				return GameResult.success(null)
	var upgrade_level := int(face.get("upgrade_level", 0))
	for index in triggers.size():
		var trigger: Variant = triggers[index]
		if typeof(trigger) != TYPE_DICTIONARY:
			continue
		var effects: Array = trigger.get("effects", [])
		if upgrade_level > 0 and typeof(trigger.get("upgrade_effects")) == TYPE_ARRAY:
			effects = trigger.upgrade_effects
		var ability_id := _new_instance_id(state, "ab")
		(
			abilities
			. append(
				{
					"ability_id": ability_id,
					"definition_id": definition_id,
					"name_key": str(face.get("name_key", definition_id)),
					"trigger": str(trigger.get("on", "")),
					"effects": effects.duplicate(true),
					"activate_round":
					(
						state.round_index
						+ (1 if str(ability.get("activate", "next_round")) == "next_round" else 0)
					),
					"limit": str(trigger.get("limit", "")),
					"condition": ability.get("condition", {}).duplicate(true),
					"last_round": 0,
					"uses_round": 0,
					"uses_this_round": 0,
					"extra_effects": ability.get("extra_effects", []).duplicate(true),
					"stack": str(ability.get("stack", "unique_name")),
				}
			)
		)
	_add_event(
		events,
		"v3_ability_registered",
		str(state.resolution.get("card_instance_id", "")),
		[],
		{"definition_id": definition_id, "triggers": triggers.size()}
	)
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
	if state.character_id in ["P01", "P02", "P03"]:
		# These passives are implemented by their v3 engine rules already.
		return GameResult.success(null)
	if state.character_id == "P04":
		if trigger != "cooperation_card_resolved" or card_type != "cooperation":
			return GameResult.success(null)
		var p04_turn := _v3_turn(state)
		if bool(p04_turn.get("p04_passive_used", false)):
			return GameResult.success(null)
		p04_turn["p04_passive_used"] = true
		_v3_gain_synergy(state, 1)
		state.player.relax = int(state.player.get("relax", 0)) + 2
		_add_event(
			events,
			"passive_triggered",
			state.character_id,
			[str(state.player.get("entity_id", ""))],
			{"passive_id": str(passive.get("id", "")), "trigger": trigger, "synergy": 1, "relax": 2}
		)
		return GameResult.success(null)
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
					"max_vitality_base": input.get("max_vitality", ruleset.run.starting_vitality),
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

	for member_id in encounter.get("initial_members", encounter.members):
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
	if input.character_id == "P02":
		for card_id in state.zones.draw:
			if str(state.card_by_id[card_id].get("definition_id", "")) == "R3-P02-01":
				state.zones.draw.erase(card_id)
				state.zones.draw.push_front(card_id)
				break
	var events: Array[RuleEvent] = []
	var prepare_result := _run_player_prepare(state, ruleset, 0, rng, events)
	if not prepare_result.ok:
		return prepare_result
	var absorb_result := _absorb_cooperation(state, encounter, ruleset, rng, events)
	if not absorb_result.ok:
		return absorb_result
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
		var is_separator := (
			codepoint == 95 or codepoint == 124 or codepoint == 45 or codepoint == 43
		)
		if not (is_letter or is_digit or is_separator):
			return false
	var first := value.unicode_at(0)
	return (first >= 65 and first <= 90) or (first >= 97 and first <= 122) or first == 95
