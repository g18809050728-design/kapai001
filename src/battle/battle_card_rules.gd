class_name BattleCardRules
extends RefCounted

var _catalog: ContentDB


func _init(catalog: ContentDB = null) -> void:
	_catalog = catalog


func set_catalog(catalog: ContentDB) -> void:
	_catalog = catalog


func resolve_face(state: BattleState, card_id: String) -> GameResult:
	if state == null or not state.card_by_id.has(card_id):
		return _failure(
			GameConstants.ERROR_INVALID_TARGET,
			"error.play.card_not_found",
			{"card_instance_id": card_id}
		)
	if _catalog == null or _catalog.get_info() == null:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.catalog.not_ready",
			{"operation": "resolve_face"}
		)

	var instance: Dictionary = state.card_by_id[card_id]
	var temporary_modifiers: Variant = instance.get("temporary_modifiers", {})
	if typeof(temporary_modifiers) != TYPE_DICTIONARY or not temporary_modifiers.is_empty():
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.card.temporary_modifiers_not_supported",
			{"card_instance_id": card_id}
		)
	var definition_id := str(instance.get("definition_id", ""))
	var definition_result := _catalog.get_definition("card", definition_id)
	if not definition_result.ok:
		return definition_result
	var definition: Dictionary = definition_result.data
	var upgrade_level: Variant = instance.get("upgrade_level", 0)
	if typeof(upgrade_level) != TYPE_INT or upgrade_level not in [0, 1]:
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.card.instance_invalid",
			{"card_instance_id": card_id, "path": "upgrade_level"}
		)

	var face: Dictionary = definition.duplicate(true)
	var upgrade: Variant = face.get("upgrade", {})
	face.erase("upgrade")
	if upgrade_level == 1:
		if typeof(upgrade) != TYPE_DICTIONARY or upgrade.is_empty():
			return _failure(
				GameConstants.ERROR_CONTENT_INVALID,
				"battle.card.upgrade_missing",
				{"card_instance_id": card_id, "definition_id": definition_id}
			)
		face = _merge_patch(face, upgrade)
	face["card_instance_id"] = card_id
	face["origin_card_id"] = str(instance.get("origin_card_id", ""))
	face["upgrade_level"] = upgrade_level

	var exam_result := _apply_exam_substitution(state, face)
	if not exam_result.ok:
		return exam_result
	return GameResult.success(face)


func calculate_cost(state: BattleState, card_id: String) -> GameResult:
	var face_result := resolve_face(state, card_id)
	if not face_result.ok:
		return face_result
	var face: Dictionary = face_result.data
	var focus_base := int(face.get("cost", 0))
	var vitality_base := int(face.get("vitality_cost", 0))
	var focus_added := 0
	var focus_discount := 0
	var vitality_discount := 0
	var sources: Array[Dictionary] = []
	var work_played_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_ROUND, "played:work", &"played"
	)
	var first_work_card := (
		str(face.get("type", "")) == "work" and int(state.counters.get(work_played_key, 0)) == 0
	)
	if first_work_card and state.scene is Dictionary:
		var scene_result := _catalog.get_definition(
			"scene", str(state.scene.get("definition_id", ""))
		)
		if not scene_result.ok:
			return scene_result
		focus_discount += int(
			scene_result.data.get("modifiers", {}).get("first_work_cost_discount", 0)
		)
	for relic_id in state.relics:
		var relic_result := _catalog.get_definition("relic", relic_id)
		if not relic_result.ok:
			return relic_result
		var hooks: Array = relic_result.data.get("hooks", [])
		for hook_index in hooks.size():
			var hook: Dictionary = hooks[hook_index]
			if str(hook.get("at", "")) != "cost_quote":
				continue
			if hook.has("definition_id") and str(hook.definition_id) != str(face.get("id", "")):
				continue
			if hook.has("card_type") and str(hook.card_type) != str(face.get("type", "")):
				continue
			var limit: Dictionary = hook.get("limit", {})
			var owner_key := "relic_hook:%s:%d" % [relic_id, hook_index]
			var counter_key := BattleState.counter_key(
				StringName(str(limit.get("per", "battle"))), owner_key, &"hook"
			)
			if int(state.counters.get(counter_key, 0)) >= int(limit.get("times", 1)):
				continue
			var source := {
				"relic_id": relic_id,
				"hook_index": hook_index,
				"counter_key": counter_key,
				"discount": int(hook.get("discount", 0)),
				"skip_vitality_cost": bool(hook.get("skip_vitality_cost", false)),
			}
			sources.append(source)
			focus_discount += int(source.discount)
			if bool(source.skip_vitality_cost):
				vitality_discount = vitality_base
	return (
		GameResult
		. success(
			{
				"base": focus_base,
				"added": focus_added,
				"discount": focus_discount,
				"cost": maxi(0, focus_base + focus_added - focus_discount),
				"sources": sources,
				"vitality_base": vitality_base,
				"vitality_discount": vitality_discount,
				"vitality_cost": maxi(0, vitality_base - vitality_discount),
			}
		)
	)


func _apply_exam_substitution(state: BattleState, face: Dictionary) -> GameResult:
	var flags: Array[String] = state.exam_flags
	var exam_key := ""
	if "independent_answer" in flags and face.get("type") == "cooperation":
		exam_key = "cooperation_exam_relax"
	elif "fixed_exam_room" in flags and face.get("type") == "scene":
		exam_key = "scene_exam_relax"
	if exam_key.is_empty():
		return GameResult.success(null)

	var ruleset_result := _get_ruleset()
	if not ruleset_result.ok:
		return ruleset_result
	var battle_rules: Dictionary = ruleset_result.data.battle
	var values: Array = battle_rules.get(exam_key, [])
	var upgrade_level := int(face.get("upgrade_level", 0))
	if values.size() <= upgrade_level:
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"battle.ruleset.exam_values_invalid",
			{"path": "ruleset.battle.%s" % exam_key}
		)
	face["target"] = "self"
	face["pre_effects"] = []
	if exam_key == "cooperation_exam_relax":
		face["effects"] = [{"op": "relax", "amount": values[upgrade_level]}]
	else:
		face["effects"] = [
			{"op": "draw", "amount": int(battle_rules.get("scene_exam_draw", 0))},
			{"op": "relax", "amount": values[upgrade_level]},
		]
	return GameResult.success(null)


func _get_ruleset() -> GameResult:
	if _catalog == null or _catalog.get_info() == null:
		return _failure(
			GameConstants.ERROR_ENGINE_NOT_READY,
			"battle.catalog.not_ready",
			{"operation": "resolve_face"}
		)
	var info: ContentInfo = _catalog.get_info()
	return _catalog.get_definition("ruleset", info.ruleset_id)


func _merge_patch(base: Dictionary, patch: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in patch:
		if typeof(result.get(key)) == TYPE_DICTIONARY and typeof(patch[key]) == TYPE_DICTIONARY:
			result[key] = _merge_patch(result[key], patch[key])
		elif typeof(patch[key]) == TYPE_ARRAY or typeof(patch[key]) == TYPE_DICTIONARY:
			result[key] = patch[key].duplicate(true)
		else:
			result[key] = patch[key]
	return result


func _failure(code: StringName, message_key: String, details: Dictionary) -> GameResult:
	return GameResult.failure(ApiError.new(code, message_key, details))
