class_name TransactionResolver
extends RefCounted

var _catalog: ContentDB
var _rewards: RewardGenerator


func _init(catalog: ContentDB = null) -> void:
	_catalog = catalog
	_rewards = RewardGenerator.new(catalog)


func set_catalog(catalog: ContentDB) -> void:
	_catalog = catalog
	_rewards.set_catalog(catalog)


func prepare(run: RunState, action: Variant) -> GameResult:
	var type := str(_read(action, "type", ""))
	var payload: Dictionary = _read(action, "payload", {})
	if type not in ["buy_item", "remove_card"]:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "transaction.action.invalid")
	if _catalog == null:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "content.catalog.missing")
	var rules_result := _catalog.get_definition("ruleset", run.ruleset_id)
	if not rules_result.ok:
		return rules_result
	var node: Variant = run.find_node(run.current_node_id)
	if node == null or _read(node, "kind") != "shop" or _read(node, "status") != "active":
		return _error(GameConstants.ERROR_WRONG_PHASE, "transaction.shop.inactive")
	var shop: Variant = _read(_read(node, "context", {}), "shop")
	if shop == null or str(_read(shop, "shop_id", "")) != str(payload.get("shop_id", "")):
		return _error(GameConstants.ERROR_INVALID_TARGET, "transaction.shop.invalid")
	var plan := {
		"type": type,
		"payload": payload.duplicate(true),
		"price": 0,
		"before": run.to_dictionary(),
		"shop_id": str(_read(shop, "shop_id")),
	}
	var rules: Dictionary = rules_result.data
	if type == "remove_card":
		if int(_read(shop, "removal_count", 0)) >= int(rules.shop.removals_per_shop):
			return _error(GameConstants.ERROR_LIMIT_REACHED, "transaction.removal.limit")
		var card_id := str(payload.get("card_instance_id", ""))
		if _card_index(run, card_id) < 0:
			return _error(GameConstants.ERROR_INVALID_TARGET, "transaction.card.invalid")
		if run.cards.size() <= int(rules.run.minimum_deck_size):
			return _error(GameConstants.ERROR_LIMIT_REACHED, "transaction.deck.minimum")
		plan.price = (
			int(rules.shop.first_removal_price)
			+ (int(rules.shop.removal_price_increment) * run.removals_used)
		)
		plan.card_id = card_id
	else:
		var stock: Dictionary = {}
		for entry in _read(shop, "stocks", []):
			if str(entry.get("stock_id", "")) == str(payload.get("stock_id", "")):
				stock = entry
				break
		if stock.is_empty():
			return _error(GameConstants.ERROR_INVALID_TARGET, "transaction.stock.invalid")
		if stock.get("sold", false):
			return _error(GameConstants.ERROR_ALREADY_RESOLVED, "transaction.stock.sold")
		var kind := str(stock.get("kind", ""))
		if kind not in ["card", "relic", "meal"]:
			return _error(GameConstants.ERROR_CONTENT_INVALID, "transaction.stock.kind")
		plan.stock = stock.duplicate(true)
		plan.price = _rewards.price_for(run, kind, int(stock.get("base_price", stock.price)))
		if kind in ["card", "relic"]:
			var definition := _catalog.get_definition(kind, str(stock.get("definition_id", "")))
			if not definition.ok:
				return definition
		if kind == "relic":
			var validated := validate_relic(
				run,
				str(stock.definition_id),
				str(payload.get("replace_relic_id", "")),
				int(rules.run.relic_slots)
			)
			if not validated.ok:
				return validated
			plan.relic_slot = validated.data
		if kind == "meal":
			plan.heal = int(rules.shop.meal_heal)
	if run.money < int(plan.price):
		return _error(
			GameConstants.ERROR_INSUFFICIENT_RESOURCE,
			"transaction.money.insufficient",
			{"price": plan.price, "money": run.money}
		)
	return GameResult.success(plan)


func apply(run: RunState, plan: Dictionary) -> GameResult:
	if not plan.has("before") or run.to_dictionary() != plan.before:
		return _error(GameConstants.ERROR_STALE_STATE, "transaction.plan.stale")
	# Rebuild from authoritative state; callers cannot alter a prepared price or target.
	var prepared := prepare(run, {"type": plan.get("type"), "payload": plan.get("payload", {})})
	if not prepared.ok:
		return prepared
	var verified: Dictionary = prepared.data
	var work := run.copy_for_write()
	var node: Variant = work.find_node(work.current_node_id)
	var shop: Variant = _read(_read(node, "context", {}), "shop")
	work.money -= int(verified.price)
	if verified.type == "remove_card":
		work.cards.remove_at(_card_index(work, str(verified.card_id)))
		work.removals_used += 1
		_write(shop, "removal_count", int(_read(shop, "removal_count", 0)) + 1)
	else:
		var stock: Dictionary = verified.stock
		match str(stock.kind):
			"card":
				add_card(work, str(stock.definition_id), "shop")
			"relic":
				add_relic(
					work,
					str(stock.definition_id),
					str(verified.payload.get("replace_relic_id", "")),
					int(verified.relic_slot)
				)
			"meal":
				work.vitality = mini(work.max_vitality, work.vitality + int(verified.heal))
		for entry in _read(shop, "stocks", []):
			if str(entry.stock_id) == str(stock.stock_id):
				entry.sold = true
	return GameResult.success(work)


func validate_relic(
	run: RunState, definition_id: String, replace_relic_id: String, slots: int
) -> GameResult:
	var occupied: Array[int] = []
	var replacement_slot := -1
	for relic in run.relics:
		if str(relic.definition_id) == definition_id:
			return _error(GameConstants.ERROR_ALREADY_RESOLVED, "transaction.relic.duplicate")
		occupied.append(int(relic.slot))
		if str(relic.relic_id) == replace_relic_id:
			replacement_slot = int(relic.slot)
	if not replace_relic_id.is_empty():
		if replacement_slot < 0:
			return _error(GameConstants.ERROR_INVALID_TARGET, "transaction.relic.replace_invalid")
		return GameResult.success(replacement_slot)
	for slot in range(slots):
		if not occupied.has(slot):
			return GameResult.success(slot)
	return _error(GameConstants.ERROR_LIMIT_REACHED, "transaction.relic.slots_full")


func add_card(run: RunState, definition_id: String, source: String) -> Dictionary:
	var card := {
		"card_id": run.next_instance_id("card"),
		"definition_id": definition_id,
		"upgrade_level": 0,
		"acquired_from": source
	}
	run.cards.append(card)
	return card


func add_relic(
	run: RunState, definition_id: String, replace_relic_id: String, slot: int
) -> Dictionary:
	for index in range(run.relics.size() - 1, -1, -1):
		if str(run.relics[index].relic_id) == replace_relic_id:
			run.relics.remove_at(index)
	var relic := {
		"relic_id": run.next_instance_id("relic"),
		"definition_id": definition_id,
		"slot": slot,
		"acquired_order": run.next_instance_seq - 1
	}
	run.relics.append(relic)
	run.relics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.slot < b.slot)
	return relic


func price_for(run: RunState, kind: String, base_price: int) -> int:
	return _rewards.price_for(run, kind, base_price)


func _card_index(run: RunState, card_id: String) -> int:
	for index in range(run.cards.size()):
		if str(run.cards[index].get("card_id", "")) == card_id:
			return index
	return -1


func _read(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if value is Dictionary:
		return value.get(key, fallback)
	if value is Object:
		var found: Variant = value.get(key)
		return fallback if found == null else found
	return fallback


func _write(value: Variant, key: String, field: Variant) -> void:
	if value is Dictionary:
		value[key] = field
	else:
		value.set(key, field)


func _error(code: StringName, key: String, details: Dictionary = {}) -> GameResult:
	return GameResult.failure(ApiError.new(code, key, details))
