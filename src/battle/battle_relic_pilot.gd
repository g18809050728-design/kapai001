class_name BattleRelicPilot
extends RefCounted
## Counters live in the battle snapshot; no state or random stream of its own.


static func has_any(state: BattleState) -> bool:
	return state.relics.any(func(id): return id.begins_with("RX-") and RelicPilot.owns_definition(id, state.character_id))


static func eligible(state: BattleState, id: String, battle_limit: int, round_limit: int = 0) -> bool:
	return (
		state.phase != "finished"
		and state.relics.has(id)
		and RelicPilot.owns_definition(id, state.character_id)
		and used(state, id) < battle_limit
		and (round_limit == 0 or used(state, id, &"round") < round_limit)
	)


static func used(state: BattleState, id: String, scope: StringName = &"battle") -> int:
	return int(state.counters.get(BattleState.counter_key(scope, id, &"rx"), 0))


static func consume(state: BattleState, id: String) -> void:
	for scope: StringName in [&"battle", &"round"]:
		var key := BattleState.counter_key(scope, id, &"rx")
		state.counters[key] = int(state.counters.get(key, 0)) + 1


static func card_context(state: BattleState) -> Dictionary:
	return state.resolution.get("rx", {}) if state.resolution is Dictionary else {}


static func work_bonus_for_slot(state: BattleState, id: String, rx: Dictionary, types: Dictionary, linked: bool) -> Dictionary:
	var paid_work := int(rx.base_cost) >= 2 and int(rx.paid) >= 1
	var amount := 0
	var limit := 1
	var per_round := 0
	match id:
		"RX-C09":
			amount = 4 if paid_work else 0
			limit = 2
			per_round = 1
		"RX-P01-01":
			amount = 3 if linked else 0
			limit = 3
			per_round = 1
		"RX-P01-09":
			amount = 5 if paid_work and int(types.get("strategy", 0)) > 0 else 0
		"RX-P03-09":
			amount = 4 if int(rx.main_debuff_kinds) >= 3 else 0
		"RX-P04-11":
			amount = 3 if state.units.is_empty() else 0
			limit = 3
			per_round = 1
	return {"amount": amount, "limit": limit} if amount > 0 and eligible(state, id, limit, per_round) else {}
