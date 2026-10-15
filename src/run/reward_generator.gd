class_name RewardGenerator
extends RefCounted

const RARITIES := ["white", "blue", "purple", "gold"]

var _catalog: ContentDB


func _init(catalog: ContentDB = null) -> void:
	_catalog = catalog


func set_catalog(catalog: ContentDB) -> void:
	_catalog = catalog


func generate(source: Variant, run: RunState, rng: RandomSource) -> GameResult:
	var rules_result := _rules(run)
	if not rules_result.ok:
		return rules_result
	var rules: Dictionary = rules_result.data
	var kind := str(_read(source, "kind", source if source is String else "normal"))
	var node_id := str(_read(source, "node_id", run.current_node_id))
	if kind not in ["normal", "elite", "boss", "term"]:
		return _error(GameConstants.ERROR_INVALID_ARGUMENT, "reward.source.invalid")
	var weights: Dictionary = rules.rewards.card_rarity_weights[kind]
	var cards := card_candidates(run, int(rules.rewards.candidate_count), rng, weights)
	if not cards.ok:
		return cards
	var items: Array[Dictionary] = []
	if not cards.data.is_empty():
		items.append(_item("card", cards.data))
	var money := 0
	if kind in ["normal", "elite"]:
		var allowances: Array = rules.rewards.normal_money_by_term
		money = int(allowances[mini(run.term - 1, allowances.size() - 1)])
		if kind == "elite":
			money += int(rules.rewards.elite_money_bonus)
	elif kind == "boss":
		money = int(rules.rewards.nonfinal_boss_money)
	if kind in ["elite", "boss"]:
		var relic_count := 1 if kind == "elite" else int(rules.rewards.candidate_count)
		var relic_weights: Dictionary = rules.rewards.relic_rarity_weights[
			"general" if kind == "elite" else "boss"
		]
		var relics := relic_candidates(run, relic_count, rng, relic_weights)
		if not relics.ok:
			return relics
		if relics.data.is_empty():
			money += int(rules.rewards.empty_relic_pool_money)
		else:
			items.append(_item("relic", relics.data))
	return (
		GameResult
		. success(
			(
				RewardOffer
				. create(
					{
						"offer_id": "%s|reward" % node_id,
						"source_node_id": node_id,
						"items": items,
						"meta": {"money": money, "kind": kind},
					}
				)
			)
		)
	)


func generate_shop(node: Variant, run: RunState, rng: RandomSource) -> GameResult:
	var rules_result := _rules(run)
	if not rules_result.ok:
		return rules_result
	var shop_rules: Dictionary = rules_result.data.shop
	var node_id := str(_read(node, "node_id", run.current_node_id))
	var stocks: Array[Dictionary] = []
	for rarity in ["white", "blue", "purple"]:
		var pool := _catalog.get_candidates({"kind": "card", "rarity": rarity})
		var chosen := _sample(pool, int(shop_rules.card_stock.get(rarity, 0)), rng)
		if not chosen.ok:
			return chosen
		for definition_id in chosen.data:
			stocks.append(
				_stock(
					run,
					node_id,
					stocks.size(),
					"card",
					definition_id,
					int(shop_rules.card_prices[rarity])
				)
			)
	for rarity in ["white", "blue"]:
		var pool := _catalog.get_candidates(
			{
				"kind": "relic",
				"rarity": rarity,
				"availability": "drop",
				"exclude_ids": _owned_relic_ids(run)
			}
		)
		var chosen := _sample(pool, int(shop_rules.relic_stock.get(rarity, 0)), rng)
		if not chosen.ok:
			return chosen
		for definition_id in chosen.data:
			stocks.append(
				_stock(
					run,
					node_id,
					stocks.size(),
					"relic",
					definition_id,
					int(shop_rules.relic_prices[rarity])
				)
			)
	for _index in range(int(shop_rules.meal_stock)):
		stocks.append(_stock(run, node_id, stocks.size(), "meal", "", int(shop_rules.meal_price)))
	return GameResult.success(
		ShopState.create(
			{
				"shop_id": "%s|shop" % node_id,
				"node_id": node_id,
				"stocks": stocks,
				"removal_count": 0
			}
		)
	)


func card_candidates(
	run: RunState, count: int, rng: RandomSource, weights: Dictionary = {}, rarity: String = ""
) -> GameResult:
	var pools := {}
	for quality in RARITIES:
		if not rarity.is_empty() and quality != rarity:
			continue
		var pool: Array[String] = []
		for id in _catalog.get_candidates({"kind": "card", "rarity": quality}):
			var definition: Dictionary = _catalog.get_definition("card", id).data
			var tags: Array = definition.get("tags", [])
			if not tags.has("basic") and not tags.has("special"):
				pool.append(id)
		pools[quality] = pool
	return _weighted_sample(pools, count, rng, weights)


func relic_candidates(
	run: RunState, count: int, rng: RandomSource, weights: Dictionary = {}, rarity: String = ""
) -> GameResult:
	var pools := {}
	for quality in RARITIES:
		if not rarity.is_empty() and quality != rarity:
			continue
		pools[quality] = _catalog.get_candidates(
			{
				"kind": "relic",
				"rarity": quality,
				"availability": "drop",
				"exclude_ids": _owned_relic_ids(run)
			}
		)
	return _weighted_sample(pools, count, rng, weights)


func price_for(run: RunState, kind: String, base_price: int) -> int:
	var price := base_price
	for owned in run.relics:
		var found := _catalog.get_definition("relic", str(owned.definition_id))
		if not found.ok:
			continue
		for hook in found.data.get("hooks", []):
			if hook.get("at") != "shop_price" or not hook.get("kinds", []).has(kind):
				continue
			var scaled := price * int(hook.get("multiplier_percent", 100))
			price = ceili(float(scaled) / 100.0)
	return price


func _weighted_sample(
	pools: Dictionary, count: int, rng: RandomSource, weights: Dictionary
) -> GameResult:
	var candidates: Array[String] = []
	for _index in range(count):
		var available: Array[String] = []
		var total := 0
		for rarity in RARITIES:
			var weight := int(weights.get(rarity, 1 if weights.is_empty() else 0))
			if pools.has(rarity) and not pools[rarity].is_empty() and weight > 0:
				available.append(rarity)
				total += weight
		if available.is_empty():
			break
		var quality: String = available[0]
		if available.size() > 1:
			var roll := rng.draw_int("reward", 1, total)
			if not roll.ok:
				return roll
			var cursor := int(roll.data)
			for rarity in available:
				cursor -= int(weights.get(rarity, 1))
				if cursor <= 0:
					quality = rarity
					break
		var draw := rng.draw_int("reward", 0, pools[quality].size() - 1)
		if not draw.ok:
			return draw
		candidates.append(pools[quality].pop_at(int(draw.data)))
	return GameResult.success(candidates)


func _sample(pool: Array[String], count: int, rng: RandomSource) -> GameResult:
	var remaining := pool.duplicate()
	var chosen: Array[String] = []
	for _index in range(mini(count, remaining.size())):
		var draw := rng.draw_int("reward", 0, remaining.size() - 1)
		if not draw.ok:
			return draw
		chosen.append(remaining.pop_at(int(draw.data)))
	return GameResult.success(chosen)


func _stock(
	run: RunState, node_id: String, index: int, kind: String, definition_id: String, base: int
) -> Dictionary:
	return {
		"stock_id": "%s|stock_%02d" % [node_id, index],
		"kind": kind,
		"definition_id": definition_id,
		"base_price": base,
		"price": price_for(run, kind, base),
		"sold": false,
	}


func _item(kind: String, candidates: Array) -> Dictionary:
	return {
		"item_id": kind,
		"kind": kind,
		"candidates": candidates.duplicate(),
		"status": "pending",
		"chosen_id": "",
		"skippable": true,
	}


func _owned_relic_ids(run: RunState) -> Array[String]:
	var ids: Array[String] = []
	for relic in run.relics:
		ids.append(str(relic.definition_id))
	return ids


func _rules(run: RunState) -> GameResult:
	if _catalog == null:
		return _error(GameConstants.ERROR_CONTENT_INVALID, "content.catalog.missing")
	return _catalog.get_definition("ruleset", run.ruleset_id)


func _read(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if value is Dictionary:
		return value.get(key, fallback)
	if value is Object:
		var found: Variant = value.get(key)
		return fallback if found == null else found
	return fallback


func _error(code: StringName, key: String, details: Dictionary = {}) -> GameResult:
	return GameResult.failure(ApiError.new(code, key, details))
