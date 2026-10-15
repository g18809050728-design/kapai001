extends RefCounted

var _failures: Array[String] = []
var _catalog: ContentDB
var _service: RunService


func run() -> Array[String]:
	_catalog = ContentDB.new()
	var loaded := _catalog.load("campus_mvp")
	_check(loaded.ok, "production catalog loads")
	if not loaded.ok:
		return _failures
	_service = RunService.new(_catalog)
	var created := _service.create(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	_check(created.ok, "production run starts")
	if not created.ok:
		return _failures
	var state: RunState = created.data.state
	_card_and_relic_details(state, created.data.rng_states)
	_shop_details(state.copy_for_write())
	_rest_healing(state.copy_for_write())
	return _failures


func _card_and_relic_details(state: RunState, rng_states: Dictionary) -> void:
	var upgraded := _service.transactions().add_card(state, "K01", "view_fixture")
	upgraded.upgrade_level = 1
	var recall := _service.transactions().add_card(state, "K07", "view_fixture")
	var cooperation := _service.transactions().add_card(state, "K43", "view_fixture")
	var scene := _service.transactions().add_card(state, "K51", "view_fixture")
	var before := state.to_dictionary()
	var rng_before := rng_states.duplicate(true)
	var view := _service.make_view(state)
	var basic := _card(view, str(state.cards[0].card_id))
	_check(
		basic.detail.cost == 1 and basic.detail.effects[0].amount == 6,
		"base card shows its actual cost and completion amount"
	)
	_check(
		basic.upgrade_detail.effects[0].amount == 8,
		"upgrade preview shows the next level's actual effect"
	)
	var upgraded_view := _card(view, str(upgraded.card_id))
	_check(
		upgraded_view.detail.effects[0].amount == 8 and upgraded_view.upgrade_detail == null,
		"owned upgraded card shows its effective effect and no further upgrade"
	)
	var recall_view := _card(view, str(recall.card_id))
	_check(
		recall_view.detail.cost == 1 and recall_view.upgrade_detail.cost == 0,
		"cost-only upgrade previews the real discount"
	)
	_check(
		(
			recall_view.upgrade_detail.effects == recall_view.detail.effects
			and recall_view.upgrade_detail.exhaust
		),
		"cost-only patch retains effects and exhaust"
	)
	var cooperation_view := _card(view, str(cooperation.card_id))
	_check(
		(
			cooperation_view.detail.related_units.has("F01")
			and cooperation_view.upgrade_detail.effects[0].vitality_bonus == 3
			and cooperation_view.detail.exam_effects[0].amount == 5
			and cooperation_view.upgrade_detail.exam_effects[0].amount == 7
		),
		"cooperation details include the unit, upgraded bonus and matching exam substitution"
	)
	var scene_view := _card(view, str(scene.card_id))
	_check(
		(
			scene_view.detail.related_scenes.has("L01")
			and scene_view.upgrade_detail.cost == 0
			and scene_view.upgrade_detail.exam_effects[0] == {"op": "draw", "amount": 1}
			and scene_view.upgrade_detail.exam_effects[1].amount == 4
		),
		"scene details retain the scene and the upgraded exam substitution"
	)
	_check(view.relics[0].detail.modifiers.work_flat_bonus == 1, "owned relic exposes its effect")
	basic.detail.effects[0].amount = 999
	basic.upgrade_detail.effects[0].amount = 999
	cooperation_view.detail.related_units.F01.name_key = "modified"
	view.relics[0].detail.modifiers.work_flat_bonus = 999
	var fresh := _service.make_view(state)
	_check(
		(
			_card(fresh, str(state.cards[0].card_id)).detail.effects[0].amount == 6
			and _card(fresh, str(state.cards[0].card_id)).upgrade_detail.effects[0].amount == 8
			and fresh.relics[0].detail.modifiers.work_flat_bonus == 1
			and _catalog.get_definition("unit", "F01").data.name_key != "modified"
		),
		"detail and upgrade preview are independent deep copies"
	)
	_check(state.to_dictionary() == before, "detail generation never enters persisted state")
	_check(rng_states == rng_before, "detail generation keeps every random stream unchanged")
	var action := GameAction.new(&"enter_node", {"node_id": state.reachable_node_ids()[0]})
	var after_view := _service.apply(state, action, rng_states)
	var control := _service.apply(RunState.new(before), action, rng_before)
	_check(after_view.ok and control.ok, "view control branches enter the next production battle")
	if after_view.ok and control.ok:
		_check(
			(
				after_view.data.state.to_dictionary() == control.data.state.to_dictionary()
				and after_view.data.rng_states == control.data.rng_states
				and after_view.data.battle_input == control.data.battle_input
			),
			"reading and editing details cannot alter subsequent encounter or random results"
		)


func _shop_details(state: RunState) -> void:
	var node: RunNodeState
	for candidate in state.nodes:
		if candidate.kind == "shop":
			node = candidate
			break
	_check(node != null, "production map has a shop")
	if node == null:
		return
	state.current_node_id = node.node_id
	state.vitality = state.max_vitality - 3
	node.status = "active"
	node.context = {
		"shop":
		ShopState.new(
			{
				"shop_id": "content_view_shop",
				"node_id": node.node_id,
				"stocks":
				[
					_stock("cooperation", "card", "K43", 35),
					_stock("scene", "card", "K51", 55),
					_stock("relic", "relic", "A05", 80),
					_stock("meal", "meal", "", 25)
				]
			}
		)
	}
	var before := state.to_dictionary()
	var view := _service.make_view(state)
	_check(view.screen == "shop", "active shop view is generated")
	_check(
		view.shop.stocks[0].detail.related_units.has("F01"),
		"shop cooperation card includes its unit"
	)
	_check(
		view.shop.stocks[1].detail.related_scenes.has("L01"), "shop scene card includes its scene"
	)
	_check(
		view.shop.stocks[2].detail.hooks[0].at == "round_start",
		"shop relic includes its real trigger"
	)
	_check(
		(
			view.shop.stocks[3].detail.base_heal_amount == 12
			and view.shop.stocks[3].detail.heal_amount == 3
			and view.shop.stocks[3].detail.effects[0].amount == 3
		),
		"meal shows both configured healing and actual healing capped at missing vitality"
	)
	view.shop.stocks[0].detail.related_units.F01.name_key = "modified"
	view.shop.stocks[1].detail.effects.clear()
	view.shop.stocks[2].detail.hooks.clear()
	var fresh := _service.make_view(state)
	_check(
		(
			fresh.shop.stocks[0].detail.related_units.F01.name_key != "modified"
			and fresh.shop.stocks[1].detail.effects.size() == 1
			and not fresh.shop.stocks[2].detail.hooks.is_empty()
			and state.to_dictionary() == before
		),
		"shop detail mutations cannot change catalog, stock or persisted state"
	)
	state.vitality = state.max_vitality
	_check(
		_service.make_view(state).shop.stocks[3].detail.heal_amount == 0,
		"meal at full vitality shows zero actual healing"
	)


func _rest_healing(state: RunState) -> void:
	var node: RunNodeState
	for candidate in state.nodes:
		if candidate.kind == "rest":
			node = candidate
			break
	_check(node != null, "production map has a rest node")
	if node == null:
		return
	state.current_node_id = node.node_id
	state.vitality = state.max_vitality - 2
	node.status = "active"
	node.context = {"used": false, "option_id": ""}
	var before := state.to_dictionary()
	var base_rest := RunNodeService.new(_catalog).rest_view(state, node)
	var view := _service.make_view(state)
	_check(
		(
			view.rest.heal_amount == base_rest.heal_amount
			and view.rest.heal_amount > 2
			and view.rest.effective_heal_amount == 2
		),
		"rest preserves configured healing while showing actual healing capped at the deficit"
	)
	var rested := _service.apply(
		state,
		GameAction.new(&"take_rest", {"node_id": node.node_id, "option_id": "heal"}),
		RandomSource.new("42").export_state().to_dictionary()
	)
	_check(
		(
			rested.ok
			and rested.data.state.vitality - state.vitality == view.rest.effective_heal_amount
		),
		"rest preview matches the actual healing granted by the existing rules"
	)
	_check(state.to_dictionary() == before, "rest healing preview never changes persisted state")
	state.vitality = state.max_vitality
	_check(
		_service.make_view(state).rest.effective_heal_amount == 0,
		"rest at full vitality previews zero actual healing"
	)


func _stock(stock_id: String, kind: String, definition_id: String, price: int) -> Dictionary:
	return {
		"stock_id": stock_id,
		"kind": kind,
		"definition_id": definition_id,
		"price": price,
		"base_price": price,
		"sold": false
	}


func _card(view: Dictionary, id: String) -> Dictionary:
	for card in view.cards:
		if str(card.card_id) == id:
			return card
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("Run content views: " + message)
