extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := ContentDB.new()
	var loaded := catalog.load("campus_mvp")
	_check(loaded.ok, "G4 rewards: production definitions load", failures)
	if not loaded.ok:
		return failures
	var generator := RewardGenerator.new(catalog)
	var resolver := TransactionResolver.new(catalog)
	var state := _run_fixture()
	var rng := RandomSource.new("42")
	var original := state.to_dictionary()
	var initial_rng := rng.export_state().to_dictionary()
	var offer := generator.generate({"node_id": "test_normal", "kind": "normal"}, state, rng)
	_check(offer.ok, "G4 rewards: normal offer generated", failures)
	if offer.ok:
		_check(
			offer.data.meta.money == 15, "G4 rewards: normal allowance is direct money", failures
		)
		_check(offer.data.items.size() == 1, "G4 rewards: money is not a pending item", failures)
		var candidates: Array = offer.data.items[0].candidates
		_check(candidates.size() == 3, "G4 rewards: three frozen card candidates", failures)
		for id in candidates:
			var definition: Dictionary = catalog.get_definition("card", id).data
			_check(
				not definition.tags.has("basic") and not definition.tags.has("special"),
				"G4 rewards: random card excludes basic and special",
				failures
			)
	var replay_rng := RandomSource.new("42")
	var replay := generator.generate(
		{"node_id": "test_normal", "kind": "normal"}, state, replay_rng
	)
	_check(
		replay.ok and offer.ok and replay.data.to_dictionary() == offer.data.to_dictionary(),
		"G4 rewards: same seed freezes same offer",
		failures
	)
	_check(state.to_dictionary() == original, "G4 rewards: generator does not mutate run", failures)
	var generated_rng := rng.export_state().to_dictionary()
	for stream in ["map", "event", "battle"]:
		_check(
			generated_rng.streams[stream] == initial_rng.streams[stream],
			"G4 rewards: generator only advances reward stream",
			failures
		)
	var shop_result := generator.generate_shop({"node_id": state.current_node_id}, state, rng)
	_check(shop_result.ok, "G4 shop: stock generated", failures)
	if not shop_result.ok:
		return failures
	var stock_ids: Array[String] = []
	for stock in shop_result.data.stocks:
		if stock.kind != "meal":
			_check(
				not stock_ids.has(stock.definition_id),
				"G4 shop: no duplicate definitions",
				failures
			)
			stock_ids.append(stock.definition_id)
			var definition: Dictionary = (
				catalog.get_definition(stock.kind, stock.definition_id).data
			)
			_check(definition.rarity != "gold", "G4 shop: no gold stock", failures)
			if stock.kind == "relic":
				_check(definition.availability != "starter", "G4 shop: no starter relic", failures)
	_check(generator.price_for(state, "card", 35) == 28, "G4 shop: A15 card discount", failures)
	_check(generator.price_for(state, "relic", 81) == 65, "G4 shop: A15 rounds up", failures)
	_check(
		generator.price_for(state, "meal", 25) == 25,
		"G4 shop: A15 leaves meals unchanged",
		failures
	)
	var shop := ShopState.create(
		{
			"shop_id": "test_shop",
			"node_id": state.current_node_id,
			"stocks":
			[
				{
					"stock_id": "stock_card",
					"kind": "card",
					"definition_id": "K05",
					"price": 999,
					"base_price": 35,
					"sold": false
				}
			],
			"removal_count": 0
		}
	)
	state.find_node(state.current_node_id).context.shop = shop
	var action := GameAction.new(
		&"buy_item", {"shop_id": "test_shop", "stock_id": "stock_card", "price": 1}
	)
	var before := state.to_dictionary()
	var prepared := resolver.prepare(state, action)
	_check(
		prepared.ok and prepared.data.price == 28, "G4 transaction: server computes price", failures
	)
	if not prepared.ok:
		return failures
	prepared.data.price = 1
	var bought := resolver.apply(state, prepared.data)
	_check(bought.ok, "G4 transaction: purchase commits", failures)
	if bought.ok:
		_check(
			(
				bought.data.money == state.money - 28
				and bought.data.cards.size() == state.cards.size() + 1
			),
			"G4 transaction: money and card commit together using verified price",
			failures
		)
		var repeated := resolver.prepare(bought.data, action)
		_check(
			not repeated.ok and repeated.error.code == GameConstants.ERROR_ALREADY_RESOLVED,
			"G4 transaction: sold stock cannot be purchased twice",
			failures
		)
	_check(
		state.to_dictionary() == before,
		"G4 transaction: original aggregate remains unchanged",
		failures
	)
	var stale := state.copy_for_write()
	stale.money -= 1
	var stale_result := resolver.apply(stale, prepared.data)
	_check(
		not stale_result.ok and stale_result.error.code == GameConstants.ERROR_STALE_STATE,
		"G4 transaction: stale plan rejected",
		failures
	)
	var poor := state.copy_for_write()
	poor.money = 27
	var poor_before := poor.to_dictionary()
	var rejected := resolver.prepare(poor, action)
	_check(
		not rejected.ok and rejected.error.code == GameConstants.ERROR_INSUFFICIENT_RESOURCE,
		"G4 transaction: insufficient money rejected",
		failures
	)
	_check(poor.to_dictionary() == poor_before, "G4 transaction: rejection is atomic", failures)
	var remove_action := GameAction.new(
		&"remove_card", {"shop_id": "test_shop", "card_instance_id": state.cards[0].card_id}
	)
	var remove_plan := resolver.prepare(state, remove_action)
	_check(
		remove_plan.ok and remove_plan.data.price == 60,
		"G4 transaction: removal uses global count without A15 discount",
		failures
	)
	if remove_plan.ok:
		var removed := resolver.apply(state, remove_plan.data)
		_check(
			removed.ok and removed.data.removals_used == 1,
			"G4 transaction: removal increments global count",
			failures
		)
		if removed.ok:
			remove_action.payload.card_instance_id = removed.data.cards[0].card_id
			var repeat_remove := resolver.prepare(removed.data, remove_action)
			_check(
				(
					not repeat_remove.ok
					and repeat_remove.error.code == GameConstants.ERROR_LIMIT_REACHED
				),
				"G4 transaction: one removal per shop",
				failures
			)
	var full := state.copy_for_write()
	full.relics.clear()
	for index in range(6):
		full.relics.append(
			{
				"relic_id": "owned_%d" % index,
				"definition_id": "A%02d" % index,
				"slot": index,
				"acquired_order": index
			}
		)
	var full_result := resolver.validate_relic(full, "A18", "", 6)
	_check(
		not full_result.ok and full_result.error.code == GameConstants.ERROR_LIMIT_REACHED,
		"G4 transaction: full relic slots require replacement",
		failures
	)
	var replacement := resolver.validate_relic(full, "A18", "owned_3", 6)
	_check(
		replacement.ok and replacement.data == 3, "G4 transaction: replacement keeps slot", failures
	)
	var empty_relics := state.copy_for_write()
	for id in catalog.get_candidates({"kind": "relic", "availability": "drop"}):
		if id == "A15":
			continue
		empty_relics.relics.append(
			{
				"relic_id": "all_%s" % id,
				"definition_id": id,
				"slot": empty_relics.relics.size(),
				"acquired_order": empty_relics.relics.size()
			}
		)
	var elite := generator.generate(
		{"node_id": "test_elite", "kind": "elite"}, empty_relics, RandomSource.new("42")
	)
	_check(
		elite.ok and elite.data.meta.money == 65 and elite.data.items.size() == 1,
		"G4 rewards: exhausted relic pool converts to direct money",
		failures
	)
	print("G4 reward/transaction checks: ", "passed" if failures.is_empty() else "failed")
	return failures


func _run_fixture() -> RunState:
	var cards: Array[Dictionary] = []
	for index in range(8):
		cards.append(
			{
				"card_id": "existing_%d" % index,
				"definition_id": "K01",
				"upgrade_level": 0,
				"acquired_from": "fixture"
			}
		)
	return RunState.new(
		{
			"run_id": "test_transactions",
			"character_id": "P01",
			"ruleset_id": "campus_v1",
			"manifest_id": "campus_mvp",
			"money": 200,
			"vitality": 50,
			"max_vitality": 72,
			"cards": cards,
			"next_instance_seq": 100,
			"relics":
			[{"relic_id": "owned_a15", "definition_id": "A15", "slot": 0, "acquired_order": 1}],
			"current_node_id": "test_shop_node",
			"nodes":
			[
				{
					"node_id": "test_shop_node",
					"term": 1,
					"layer": 3,
					"kind": "shop",
					"status": "active",
					"context": {}
				}
			]
		}
	)


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
