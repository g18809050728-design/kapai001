extends RefCounted

var _failures: Array[String] = []
var _catalog: ContentDB
var _checks := 0
var _boundaries: Array[String] = []


func run() -> Array[String]:
	_catalog = ContentDB.new("res://tests/fixtures/run_flow", true)
	var loaded := _catalog.load("test_run_g4")
	_check(loaded.ok, "codec fixture loads")
	if not loaded.ok:
		return _failures
	var service := RunService.new(_catalog)
	var created := service.create(
		{
			"character_id": "test_P01",
			"manifest_id": "test_run_g4",
			"difficulty": "normal",
			"seed": "42"
		}
	)
	_check(created.ok, "codec fixture starts")
	if not created.ok:
		return _failures
	var state: RunState = created.data.state
	var rng: Dictionary = created.data.rng_states
	_roundtrip_run(state, "initial map")
	_malformed_runs(state)
	for kind in ["normal", "event", "shop", "elite", "rest", "boss"]:
		var node_id := ""
		for node in state.nodes:
			if node.kind == kind and state.reachable_node_ids().has(node.node_id):
				node_id = node.node_id
				break
		var entered := service.apply(
			state, GameAction.new(&"enter_node", {"node_id": node_id}), rng
		)
		_check(entered.ok, "enter " + kind)
		if not entered.ok:
			print("G5_CODEC_ENTER_ERROR=", entered.error.to_dictionary())
			break
		state = entered.data.state
		rng = entered.data.rng_states
		_roundtrip_run(state, kind + " entry")
		if kind == "normal":
			var inactive := state.to_dictionary()
			inactive.active_battle_id = ""
			inactive.active_encounter_id = ""
			_reject_run(inactive, &"SAVE_CORRUPT", "battle node without active battle")
		if entered.data.battle_input != null:
			var engine := BattleEngine.new(_catalog)
			var begun := engine.begin(entered.data.battle_input)
			_check(begun.ok, "codec battle begins")
			if not begun.ok:
				break
			var battle: BattleState = begun.data.state
			_roundtrip_battle(battle, kind + " battle")
			if kind == "normal":
				_malformed_battles(battle)
				_rich_battle(battle)
			var played := engine.apply(
				battle,
				ActionDraft.new(
					&"play_card",
					{
						"card_instance_id": battle.zones.hand[0],
						"target_ids": [battle.tasks[0].task_id]
					}
				),
				begun.data.rng_state
			)
			_check(played.ok and played.data.outcome != null, "codec battle fixture wins")
			if not played.ok or played.data.outcome == null:
				break
			_roundtrip_battle(played.data.state, kind + " finished battle")
			var settled := service.settle_battle(state, played.data.outcome, played.data.rng_state)
			_check(settled.ok, "codec battle settles")
			if not settled.ok:
				break
			state = settled.data.state
			rng = settled.data.rng_states
			_roundtrip_run(state, kind + " rewards/terminal")
			if settled.data.run_summary != null:
				_summary(settled.data.run_summary)
			if state.pending_reward != null:
				for item in state.pending_reward.items.duplicate(true):
					var skipped := service.apply(
						state,
						GameAction.new(
							&"skip_reward",
							{"offer_id": state.pending_reward.offer_id, "item_id": item.item_id}
						),
						rng
					)
					_check(skipped.ok, "codec skip reward")
					if not skipped.ok:
						return _failures
					state = skipped.data.state
					rng = skipped.data.rng_states
					_roundtrip_run(state, "partially/fully resolved reward")
		elif kind == "event":
			var event: EventState = state.find_node(node_id).context.event
			var resolved := service.apply(
				state,
				GameAction.new(
					&"choose_event",
					{
						"event_instance_id": event.event_instance_id,
						"option_id": "leave",
						"selection_ids": []
					}
				),
				rng
			)
			_check(resolved.ok, "codec event resolves")
			if not resolved.ok:
				break
			state = resolved.data.state
			rng = resolved.data.rng_states
			_roundtrip_run(state, "resolved event")
		elif kind == "shop":
			var shop: ShopState = state.find_node(node_id).context.shop
			var bought := service.apply(
				state,
				GameAction.new(
					&"buy_item", {"shop_id": shop.shop_id, "stock_id": shop.stocks[0].stock_id}
				),
				rng
			)
			_check(bought.ok, "codec shop purchase")
			if not bought.ok:
				break
			state = bought.data.state
			rng = bought.data.rng_states
			_roundtrip_run(state, "shop sold marker")
		elif kind == "rest":
			var rested := service.apply(
				state,
				GameAction.new(
					&"take_rest",
					{
						"node_id": node_id,
						"option_id": "upgrade",
						"card_instance_id": state.cards[0].card_id
					}
				),
				rng
			)
			_check(rested.ok, "codec rest upgrade")
			if not rested.ok:
				break
			state = rested.data.state
			rng = rested.data.rng_states
			_roundtrip_run(state, "used rest")
		if not state.outcome.is_empty():
			break
		var left := service.apply(state, GameAction.new(&"leave_node", {"node_id": node_id}), rng)
		_check(left.ok, "codec leave " + kind)
		if not left.ok:
			break
		state = left.data.state
		rng = left.data.rng_states
		_roundtrip_run(state, kind + " completed")
		if kind == "event":
			var unresolved := state.to_dictionary()
			for node in unresolved.nodes:
				if node.node_id == node_id:
					node.context.event.resolved_option_id = ""
			_reject_run(unresolved, &"SAVE_CORRUPT", "completed event without resolution")
		elif kind == "rest":
			var unused := state.to_dictionary()
			for node in unused.nodes:
				if node.node_id == node_id:
					node.context.used = false
					node.context.option_id = ""
			_reject_run(unused, &"SAVE_CORRUPT", "completed rest without usage")
	_check(state.outcome == "won" and state.node_path.size() == 6, "codec covers whole semester")
	print(
		"G5_CODEC_EVIDENCE=",
		JSON.stringify({"checks": _checks, "boundaries": _boundaries, "failures": _failures})
	)
	return _failures


func _roundtrip_run(state: RunState, label: String) -> void:
	var before := state.to_dictionary()
	var encoded := RunCodec.encode(state)
	_check(encoded.ok, "encode run " + label)
	if not encoded.ok:
		print("G5_CODEC_ENCODE_ERROR=", label, encoded.error.to_dictionary())
		return
	var decoded := RunCodec.decode(JSON.parse_string(JSON.stringify(encoded.data)), _catalog)
	_check(decoded.ok, "decode run " + label)
	if not decoded.ok:
		print("G5_CODEC_DECODE_ERROR=", label, decoded.error.to_dictionary())
		return
	_check(decoded.data.to_dictionary() == before, "run JSON roundtrip " + label)
	_check(state.to_dictionary() == before, "run encode/decode leaves input intact")
	if decoded.data.pending_reward != null:
		_check(decoded.data.pending_reward is RewardOffer, "reward restores typed object")
	for node in decoded.data.nodes:
		if node.context.has("shop"):
			_check(node.context.shop is ShopState, "shop restores typed object")
		if node.context.has("event"):
			_check(node.context.event is EventState, "event restores typed object")
	decoded.data.cards[0].upgrade_level = 99
	_check(state.to_dictionary() == before, "decoded run is detached")
	_boundaries.append(label)


func _roundtrip_battle(state: BattleState, label: String) -> void:
	var before := state.to_dictionary()
	var encoded := BattleCodec.encode(state)
	_check(encoded.ok, "encode " + label)
	if not encoded.ok:
		print("G5_CODEC_BATTLE_ENCODE_ERROR=", label, encoded.error.to_dictionary())
		return
	var decoded := BattleCodec.decode(JSON.parse_string(JSON.stringify(encoded.data)), _catalog)
	_check(decoded.ok, "decode " + label)
	if not decoded.ok:
		print("G5_CODEC_BATTLE_DECODE_ERROR=", label, decoded.error.to_dictionary())
		return
	_check(decoded.data.to_dictionary() == before, "battle JSON roundtrip " + label)
	decoded.data.player.focus = 99
	_check(state.to_dictionary() == before, "decoded battle is detached")
	_boundaries.append(label)


func _malformed_runs(state: RunState) -> void:
	var base := state.to_dictionary()
	var bad := base.duplicate(true)
	bad.erase("money")
	_reject_run(bad, &"SAVE_CORRUPT", "missing required field")
	bad = base.duplicate(true)
	bad["unexpected"] = 1
	_reject_run(bad, &"SAVE_CORRUPT", "unknown field")
	bad = base.duplicate(true)
	bad.cards[0].upgrade_level = 0.5
	_reject_run(bad, &"SAVE_CORRUPT", "fractional integer")
	bad = base.duplicate(true)
	bad.cards.append(bad.cards[0].duplicate(true))
	_reject_run(bad, &"SAVE_CORRUPT", "duplicate card")
	bad = base.duplicate(true)
	bad.cards[0].definition_id = "test_unknown_card"
	_reject_run(bad, &"CONTENT_INVALID", "missing definition")
	bad = base.duplicate(true)
	bad.money = -1
	_reject_run(bad, &"SAVE_CORRUPT", "negative wallet")
	bad = base.duplicate(true)
	bad.cards[0].upgrade_level = 2
	_reject_run(bad, &"SAVE_CORRUPT", "upgrade limit")
	bad = base.duplicate(true)
	bad.nodes[0].next_ids.append(bad.nodes[-1].node_id)
	_reject_run(bad, &"SAVE_CORRUPT", "illegal map edge")
	bad = base.duplicate(true)
	bad.nodes[0].status = "completed"
	_reject_run(bad, &"SAVE_CORRUPT", "missing completion marker")
	bad = base.duplicate(true)
	bad.next_instance_seq = 1
	_reject_run(bad, &"SAVE_CORRUPT", "instance sequence reuse")
	bad = base.duplicate(true)
	bad.relics.append(bad.relics[0].duplicate(true))
	bad.relics[-1].relic_id = "relic_000000"
	_reject_run(bad, &"SAVE_CORRUPT", "duplicate relic definition and slot")
	bad = base.duplicate(true)
	bad.manifest_id = "other"
	_reject_run(bad, &"VERSION_MISMATCH", "manifest mismatch")
	bad = base.duplicate(true)
	bad.pending_reward = []
	_reject_run(bad, &"SAVE_CORRUPT", "wrong optional object type")
	bad = base.duplicate(true)
	bad.career["unknown"] = 1
	_reject_run(bad, &"SAVE_CORRUPT", "unknown career track")
	bad = base.duplicate(true)
	bad.career.research = 4
	_reject_run(bad, &"SAVE_CORRUPT", "career cap")
	bad = base.duplicate(true)
	bad.ending_draft["unknown"] = true
	_reject_run(bad, &"SAVE_CORRUPT", "unknown ending draft field")
	bad = base.duplicate(true)
	bad.settlement = {
		"settlement_id": "term_1",
		"term": 1,
		"steps":
		[
			{
				"step_id": "reward",
				"status": "claimed",
				"candidates": ["test_K01"],
				"skippable": true,
				"chosen_id": "unknown"
			}
		]
	}
	_reject_run(bad, &"SAVE_CORRUPT", "settlement chosen value outside candidates")


func _malformed_battles(state: BattleState) -> void:
	var base := state.to_dictionary()
	var bad := base.duplicate(true)
	bad.zones.hand.append(bad.zones.hand[0])
	_reject_battle(bad, &"SAVE_CORRUPT", "duplicate zone card")
	bad = base.duplicate(true)
	bad.zones.hand.pop_back()
	_reject_battle(bad, &"SAVE_CORRUPT", "omitted zone card")
	bad = base.duplicate(true)
	bad.tasks[0].intent_cursor = 99
	_reject_battle(bad, &"SAVE_CORRUPT", "intent cursor out of bounds")
	bad = base.duplicate(true)
	bad.tasks[0].intent_snapshot = {}
	_reject_battle(bad, &"SAVE_CORRUPT", "intent snapshot mismatch")
	bad = base.duplicate(true)
	bad.resolution = {}
	_reject_battle(bad, &"SAVE_CORRUPT", "pending resolution cannot load as stable")
	var pending := state.copy()
	pending.resolution = {}
	var refused := BattleCodec.encode(pending)
	_check(
		not refused.ok and refused.error.code == &"CHOICE_PENDING", "pending resolution cannot save"
	)
	bad = base.duplicate(true)
	bad.next_creation_order = 1
	_reject_battle(bad, &"SAVE_CORRUPT", "creation order reuse")
	bad = base.duplicate(true)
	bad.player.focus = -1
	_reject_battle(bad, &"SAVE_CORRUPT", "negative focus")
	bad = base.duplicate(true)
	bad.card_by_id[bad.zones.hand[0]].definition_id = "test_unknown_card"
	_reject_battle(bad, &"CONTENT_INVALID", "battle missing definition")
	bad = base.duplicate(true)
	bad.zones["unknown"] = []
	_reject_battle(bad, &"SAVE_CORRUPT", "unknown zone")
	bad = base.duplicate(true)
	bad.units = [1]
	_reject_battle(bad, &"SAVE_CORRUPT", "malformed nested object")
	bad = base.duplicate(true)
	bad.source_registry.erase(bad.tasks[0].task_id)
	_reject_battle(bad, &"SAVE_CORRUPT", "live task without registry entry")


func _rich_battle(state: BattleState) -> void:
	var rich := state.copy()
	var definition: Dictionary = _catalog.get_definition("unit", "test_F01").data
	var unit := definition.duplicate(true)
	unit.merge(
		{
			"unit_id": _id(rich, "u"),
			"definition_id": definition.id,
			"max_vitality": definition.vitality,
			"entered_order": rich.next_creation_order,
			"actions_taken": 2,
			"target_id": rich.tasks[0].task_id,
			"relax": 2
		}
	)
	_register(rich, unit.unit_id, "unit", definition.id)
	rich.units.append(unit)
	for spec in [
		["anxiety", rich.player.entity_id],
		["guard", unit.unit_id],
		["extra_requirements", rich.tasks[0].task_id]
	]:
		var id := _id(rich, "st")
		rich.statuses.append(
			{
				"status_id": spec[0],
				"instance_id": id,
				"source_id": rich.zones.hand[0],
				"target_id": spec[1],
				"stacks": 1,
				"expiry": "battle"
			}
		)
		_register(rich, id, "status", spec[0])
	var scene_id := _id(rich, "s")
	rich.scene = {
		"scene_id": scene_id,
		"definition_id": "test_L02",
		"established_round": 1,
		"pending_random_result": [{"op": "gain_focus", "amount": 1}]
	}
	_register(rich, scene_id, "scene", "test_L02")
	rich.counters[BattleState.counter_key(&"battle", "test_L02", &"prepare")] = 2
	rich.retained_card_ids.append(rich.zones.hand[0])
	_roundtrip_battle(rich, "units/status holders/scene frozen result/counters")
	var bad := rich.to_dictionary()
	bad.statuses[0].target_id = "departed_entity"
	_reject_battle(bad, &"SAVE_CORRUPT", "unknown status holder")
	bad = rich.to_dictionary()
	bad.statuses[0].target_id = unit.unit_id
	_reject_battle(bad, &"SAVE_CORRUPT", "player status attached to unit")
	bad = rich.to_dictionary()
	bad.scene.pending_random_result = [{"op": "unknown"}]
	_reject_battle(bad, &"SAVE_CORRUPT", "invalid frozen scene result")
	bad = rich.to_dictionary()
	bad.units.append(bad.units[0].duplicate(true))
	_reject_battle(bad, &"SAVE_CORRUPT", "duplicate unit")


func _summary(summary: RunSummary) -> void:
	var data := RunCodec.encode_summary(summary)
	var decoded := RunCodec.decode_summary(JSON.parse_string(JSON.stringify(data)))
	_check(decoded.ok and decoded.data.to_dictionary() == data, "summary JSON roundtrip")
	data.result = "in_progress"
	var denied := RunCodec.decode_summary(data)
	_check(not denied.ok and denied.error.code == &"SAVE_CORRUPT", "summary must be finalized")


func _id(state: BattleState, prefix: String) -> String:
	var id := "%s|%s%d" % [state.battle_id, prefix, state.next_instance_seq]
	state.next_instance_seq += 1
	return id


func _register(state: BattleState, id: String, kind: String, definition_id: String) -> void:
	state.source_registry[id] = {
		"kind": kind, "definition_id": definition_id, "creation_order": state.next_creation_order
	}
	state.next_creation_order += 1


func _reject_run(data: Dictionary, code: StringName, label: String) -> void:
	var before := data.duplicate(true)
	var result := RunCodec.decode(data, _catalog)
	_check(not result.ok and result.error.code == code, "reject run " + label)
	_check(data == before, "run rejection leaves input intact")


func _reject_battle(data: Dictionary, code: StringName, label: String) -> void:
	var before := data.duplicate(true)
	var result := BattleCodec.decode(data, _catalog)
	_check(not result.ok and result.error.code == code, "reject battle " + label)
	_check(data == before, "battle rejection leaves input intact")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("G5 codec: " + label)
