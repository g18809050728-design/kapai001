extends RefCounted


class UnknownHookCatalog:
	extends ContentDB

	func get_definition(kind: String, id: String) -> GameResult:
		var result := super.get_definition(kind, id)
		if result.ok and kind == "relic" and id == "A15":
			result.data.hooks[0].at = "test_unknown_hook"
		return result


var _failures: Array[String] = []
var _matrix: Array[Dictionary] = []


func run() -> Array[String]:
	var catalog := ContentDB.new()
	_check(catalog.load("campus_mvp").ok, "production content loads")
	var engine := BattleEngine.new(catalog)
	var created := RunService.new(catalog).create(
		StartRunRequest.new("P01", &"normal", "campus_mvp", "42")
	)
	_check(created.ok, "production starter run exists")
	if not created.ok:
		return _failures
	var run: RunState = created.data.state
	var cards: Array[Dictionary] = []
	for card in run.cards:
		cards.append(
			{
				"card_id": card.card_id,
				"definition_id": card.definition_id,
				"upgrade_level": card.upgrade_level
			}
		)
	var input := {
		"battle_id": "test_production_relic_entry",
		"node_id": "test_entry_node",
		"encounter_id": "B01",
		"character_id": "P01",
		"difficulty": "normal",
		"vitality": 60,
		"max_vitality": 72,
		"cards": cards,
		"relics": [],
		"rng_state": created.data.rng_states.duplicate(true)
	}
	for encounter in catalog.get_info().enabled.encounter:
		input.encounter_id = encounter
		input.relics = []
		var control := engine.begin(input)
		_check(control.ok, encounter + " control battle starts")
		for relic in catalog.get_info().enabled.relic:
			input.relics = [relic]
			var before := input.duplicate(true)
			var begun := engine.begin(input)
			_check(begun.ok, "%s with %s enters combat" % [encounter, relic])
			_check(input == before, "battle entry preserves caller state and RNG")
			_matrix.append({"encounter": encounter, "relic": relic, "accepted": begun.ok})
			if not begun.ok:
				print("RELIC_ENTRY_ERROR=", JSON.stringify(begun.error.to_dictionary()))
				continue
			_check(begun.data.state.phase == "player_action", "entry reaches playable phase")
			_check(begun.data.state.relics == [relic], "entry retains the owned relic")
			if relic == "A15" and control.ok:
				_check(
					begun.data.rng_state == control.data.rng_state,
					"shop hook does not consume gameplay RNG"
				)
				_check(
					begun.data.state.player == control.data.state.player,
					"shop hook does not change player resources"
				)
				_check_no_shop_trigger(begun.data.events)
				var next := engine.apply(
					begun.data.state, ActionDraft.new(&"end_turn", {}), begun.data.rng_state
				)
				var next_control := engine.apply(
					control.data.state, ActionDraft.new(&"end_turn", {}), control.data.rng_state
				)
				_check(next.ok and next_control.ok, "A15 also permits end turn")
				if next.ok and next_control.ok:
					_check(
						next.data.rng_state == next_control.data.rng_state,
						"A15 leaves subsequent RNG unchanged"
					)
					_check(
						next.data.state.player == next_control.data.state.player,
						"A15 leaves subsequent player resources unchanged"
					)
					_check_no_shop_trigger(next.data.events)
	TransactionResolver.new(catalog).add_relic(run, "A15", "", 1)
	var rewards := RewardGenerator.new(catalog)
	_check(rewards.price_for(run, "card", 36) == 29, "A15 card discount still rounds up")
	_check(rewards.price_for(run, "relic", 80) == 64, "A15 relic discount still applies")
	_check(rewards.price_for(run, "meal", 25) == 25, "A15 does not discount meals")
	var unknown := UnknownHookCatalog.new()
	_check(unknown.load("campus_mvp").ok, "unknown-hook probe loads valid base content")
	input.relics = ["A15"]
	var before_unknown := input.duplicate(true)
	var rejected := BattleEngine.new(unknown).begin(input)
	_check(
		not rejected.ok and rejected.error.message_key == "battle.relic.hook_not_supported",
		"unknown hooks remain rejected"
	)
	_check(input == before_unknown, "unknown-hook rejection preserves input and RNG")
	print(
		"PRODUCTION_RELIC_ENTRY_EVIDENCE=",
		SnapshotCodec.canonical_json(
			{
				"seed": "42",
				"manifest": "campus_mvp",
				"matrix": _matrix,
				"shop_prices":
				{
					"card36": rewards.price_for(run, "card", 36),
					"relic80": rewards.price_for(run, "relic", 80)
				},
				"unknown_hook_rejected": not rejected.ok,
				"failures": _failures
			}
		)
	)
	return _failures


func _check_no_shop_trigger(events: Array[RuleEvent]) -> void:
	for event in events:
		_check(
			event.type != &"relic_triggered" or event.data.get("relic_id") != "A15",
			"shop hook never fires in combat"
		)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append("relic battle entry: " + label)
