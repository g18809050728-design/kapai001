extends RefCounted

const FIXTURE_FILES := [
	"characters",
	"cards",
	"relics",
	"tasks",
	"encounters",
	"units",
	"scenes",
	"events",
	"statuses",
	"rulesets"
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var fixture_root := _create_fixture()
	var content_db := ContentDB.new(fixture_root, true)
	var loaded := content_db.load("test_battle_g3")
	_check(loaded.ok, "isolated battle fixture loads", failures)
	if not loaded.ok:
		print(JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(fixture_root)
		return failures
	print("G3-02_TEST_FIXTURE_SHA256=", _fixture_hash(fixture_root))

	var input := _make_input()
	var original_random_state: Dictionary = input.rng_state.duplicate(true)
	var engine := BattleEngine.new(content_db)
	var first := engine.begin(input)
	_check(first.ok, "begin creates an isolated battle", failures)
	if not first.ok:
		print("G3-02_BEGIN_ERROR=", JSON.stringify(first.error.to_dictionary()))
	_check(
		input.rng_state == original_random_state,
		"begin leaves input RNG snapshot unchanged",
		failures
	)
	if first.ok:
		var step: BattleStep = first.data
		var state: BattleState = step.state
		_check(state.phase == "player_action", "begin reaches player action", failures)
		_check(
			state.round_index == 1 and state.ddl == 3,
			"begin sets first round and encounter DDL",
			failures
		)
		_check(
			state.player.vitality == 54 and state.player.max_vitality == 60,
			"begin carries vitality values",
			failures
		)
		_check(
			state.player.focus == 3 and state.player.relax == 0,
			"first prepare applies focus and zero relax",
			failures
		)
		_check(state.exam_flags.is_empty(), "begin carries encounter exam flags", failures)
		_check(state.tasks.size() == 1, "begin creates one encounter task", failures)
		if state.tasks.size() == 1:
			var task: Dictionary = state.tasks[0]
			_check(
				task.phase_key == "main" and task.work_remaining == 12,
				"begin creates the first task phase",
				failures
			)
			_check(
				task.intent_snapshot.index == 1 and task.shield == 2,
				"begin snapshots the first intent",
				failures
			)
			_check(task.eligible_round == 1, "initial task is eligible in round one", failures)
			_check(
				state.source_registry[task.task_id].creation_order == 2,
				"task source registers after character",
				failures
			)
		_check(
			state.source_registry[state.player.entity_id].creation_order == 1,
			"character source registers first",
			failures
		)
		_check(
			state.card_by_id.size() == 8,
			"permanent cards become distinct battle instances",
			failures
		)
		_check(
			state.zones.hand.size() == 5 and state.zones.draw.size() == 3,
			"begin draws up to the configured first hand",
			failures
		)
		_check(
			state.zones.discard.is_empty() and state.zones.exhaust.is_empty(),
			"begin clears non-draw zones",
			failures
		)
		_check(
			step.stable and step.pending_choice == null and step.outcome == null,
			"initial result is stable without a pending choice",
			failures
		)
		_check(
			step.rng_state.keys().size() == 2 and step.rng_state.streams.keys().size() == 4,
			"begin returns a full four-stream snapshot",
			failures
		)
		_check(
			step.rng_state.streams.map == original_random_state.streams.map,
			"begin leaves map RNG unchanged",
			failures
		)
		_check(
			step.rng_state.streams.reward == original_random_state.streams.reward,
			"begin leaves reward RNG unchanged",
			failures
		)
		_check(
			step.rng_state.streams.event == original_random_state.streams.event,
			"begin leaves event RNG unchanged",
			failures
		)
		_check(
			step.rng_state.streams.battle != original_random_state.streams.battle,
			"shuffle advances only battle RNG",
			failures
		)
		_check(
			_event_indexes_are_contiguous(step.events),
			"begin events have contiguous indexes",
			failures
		)
		_check(
			_count_events(step.events, "card_drawn") == 5,
			"begin emits one event per dealt card",
			failures
		)
		var first_deal := _deal_ids(state)
		var repeated := engine.begin(input)
		_check(repeated.ok, "same fixed input can be replayed", failures)
		if repeated.ok:
			var repeated_step: BattleStep = repeated.data
			_check(
				_deal_ids(repeated_step.state) == first_deal,
				"same seed reproduces the shuffled deck and opening hand",
				failures
			)
			_check(
				repeated_step.rng_state == step.rng_state,
				"same seed reproduces the resulting RNG snapshot",
				failures
			)
		_check(
			first_deal != _origin_ids(input.cards),
			"fixed-seed shuffle changes the input ordering",
			failures
		)
		_check(
			_all_cards_have_origins(state),
			"battle cards preserve permanent card references",
			failures
		)
		_run_preview_cases(engine, state, fixture_root, failures)
		_run_apply_cases(engine, state, step.rng_state, failures)
		_run_relic_cost_cases(engine, input, failures)
		var short_deck_input := _make_input()
		short_deck_input.cards.resize(4)
		var short_deck_result := engine.begin(short_deck_input)
		_check(short_deck_result.ok, "begin accepts a deck smaller than the base draw", failures)
		if short_deck_result.ok:
			var short_deck_step: BattleStep = short_deck_result.data
			_check(
				short_deck_step.state.zones.hand.size() == 4,
				"initial draw stops at remaining deck size",
				failures
			)
			_check(
				short_deck_step.state.zones.draw.is_empty(),
				"short initial deck leaves no phantom cards",
				failures
			)

	var missing_rng := _make_input()
	missing_rng.erase("rng_state")
	var missing_rng_result := engine.begin(missing_rng)
	_check(
		(
			not missing_rng_result.ok
			and missing_rng_result.error.code == GameConstants.ERROR_INVALID_ARGUMENT
		),
		"missing RNG snapshot is rejected",
		failures
	)
	var invalid_rng := _make_input()
	invalid_rng.rng_state = {
		"algorithm_version": GameConstants.RANDOM_ALGORITHM_VERSION, "streams": {}
	}
	var invalid_rng_snapshot: Dictionary = invalid_rng.rng_state.duplicate(true)
	var invalid_rng_result := engine.begin(invalid_rng)
	_check(
		(
			not invalid_rng_result.ok
			and invalid_rng_result.error.code == GameConstants.ERROR_INVALID_ARGUMENT
		),
		"incomplete RNG snapshots are rejected",
		failures
	)
	_check(
		invalid_rng.rng_state == invalid_rng_snapshot,
		"invalid RNG snapshots remain unchanged",
		failures
	)

	var missing_card := _make_input()
	missing_card.cards[0].definition_id = "test_missing_card"
	var missing_card_result := engine.begin(missing_card)
	_check(
		(
			not missing_card_result.ok
			and missing_card_result.error.code == GameConstants.ERROR_CONTENT_INVALID
		),
		"disabled card references fail with a content error",
		failures
	)
	if not missing_card_result.ok:
		print(
			"G3-02_MISSING_CARD_ERROR=", JSON.stringify(missing_card_result.error.to_dictionary())
		)
	_check(
		missing_card.rng_state == original_random_state,
		"reference rejection does not mutate RNG input",
		failures
	)
	if not missing_card_result.ok:
		_check(
			missing_card_result.error.details.path == "input.cards[0].definition_id",
			"content error identifies the missing card path",
			failures
		)

	var hooked_relic := _make_input()
	hooked_relic.relics = ["test_relic_001"]
	var hooked_relic_result := engine.begin(hooked_relic)
	_check(hooked_relic_result.ok, "supported relic hooks run during battle entry", failures)
	if hooked_relic_result.ok:
		var hooked_step: BattleStep = hooked_relic_result.data
		_check(
			hooked_step.state.player.focus == 4,
			"initial round_start relic hook grants focus after player preparation",
			failures
		)
		_check(
			hooked_step.state.zones.hand.size() == 6,
			"initial draw relic hook draws after the base opening hand",
			failures
		)
		var initial_hook_events: Array[String] = []
		for event: RuleEvent in hooked_step.events:
			if event.type == &"relic_triggered":
				initial_hook_events.append(str(event.data.at))
		_check(
			initial_hook_events == ["round_start", "draw"],
			"initial relic hooks emit events in prepare and draw order",
			failures
		)
		_check(
			_count_events(hooked_step.events, "card_drawn") == 6,
			"initial draw hook reports its additional card draw",
			failures
		)
		_check(
			hooked_step.rng_state == first.data.rng_state,
			"non-random initial hooks do not advance RNG beyond shuffle",
			failures
		)
	_check(
		hooked_relic.rng_state == original_random_state,
		"supported initial hooks do not mutate the input RNG snapshot",
		failures
	)

	var duplicate_origin := _make_input()
	duplicate_origin.cards[1].card_id = duplicate_origin.cards[0].card_id
	var duplicate_result := engine.begin(duplicate_origin)
	_check(
		(
			not duplicate_result.ok
			and duplicate_result.error.code == GameConstants.ERROR_INVALID_ARGUMENT
		),
		"duplicate permanent card ids are rejected",
		failures
	)

	var no_catalog := BattleEngine.new()
	var no_catalog_result := no_catalog.begin(_make_input())
	_check(
		(
			not no_catalog_result.ok
			and no_catalog_result.error.code == GameConstants.ERROR_ENGINE_NOT_READY
		),
		"begin requires a loaded catalog",
		failures
	)
	_remove_fixture(fixture_root)
	return failures


func _make_input() -> Dictionary:
	var cards: Array[Dictionary] = []
	for index in range(8):
		(
			cards
			. append(
				{
					"card_id": "origin_%03d" % (index + 1),
					"definition_id": "test_card_%03d" % ((index % 2) + 1),
					"upgrade_level": index % 2,
				}
			)
		)
	var random_source := RandomSource.new("g3-begin-fixed-seed")
	return {
		"battle_id": "battle_test_001",
		"node_id": "test_node_001",
		"encounter_id": "test_encounter_001",
		"character_id": "test_character_001",
		"difficulty": "normal",
		"vitality": 54,
		"max_vitality": 60,
		"cards": cards,
		"relics": [],
		"rng_state": random_source.export_state().to_dictionary(),
	}


func _create_fixture() -> String:
	var root := ProjectSettings.globalize_path(
		"res://.godot/g3_battle_fixture_%d" % Time.get_ticks_usec()
	)
	var absolute_root := ProjectSettings.globalize_path(root)
	for directory in ["definitions", "manifests"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [absolute_root, directory])
	for file_name in ContentDB.FILE_NAMES.values():
		_write_file(
			"%s/definitions/%s.json" % [root, file_name],
			FileAccess.get_file_as_string(
				"res://tests/fixtures/content_loader/definitions/%s.json" % file_name
			)
		)
	_write_file(
		"%s/manifests/test_content_loader.json" % root,
		FileAccess.get_file_as_string(
			"res://tests/fixtures/content_loader/manifests/test_content_loader.json"
		)
	)

	var manifest: Dictionary = _read_json("%s/manifests/test_content_loader.json" % root)
	manifest.id = "test_battle_g3"
	manifest.enabled.character = ["test_character_001"]
	manifest.enabled.card = ["test_card_001", "test_card_002"]
	manifest.enabled.relic = ["test_relic_001"]
	manifest.enabled.task = ["test_task_001"]
	manifest.enabled.encounter = ["test_encounter_001"]
	manifest.overrides = []
	_write_json("%s/manifests/test_battle_g3.json" % root, manifest)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path("%s/manifests/test_content_loader.json" % root)
	)
	var test_card: Dictionary = _read_json("%s/definitions/cards.json" % root)[0]
	var second_test_card: Dictionary = test_card.duplicate(true)
	second_test_card.id = "test_card_002"
	second_test_card.name_key = "card.test_content_loader.second_name"
	test_card.cost = 2
	test_card.vitality_cost = 4
	test_card.limit = {"per": "instance_round", "times": 1}
	test_card.upgrade.cost = 1
	test_card.upgrade.vitality_cost = 3
	second_test_card = test_card.duplicate(true)
	second_test_card.id = "test_card_002"
	second_test_card.name_key = "card.test_content_loader.second_name"
	var cooperation_card := {
		"id": "test_card_cooperation",
		"name_key": "card.test.cooperation",
		"type": "cooperation",
		"rarity": "white",
		"tags": ["test"],
		"cost": 2,
		"target": "unit",
		"exhaust": false,
		"pre_effects": [{"op": "relax", "amount": 1}],
		"effects": [{"op": "summon_unit", "unit": "test_unit_001"}],
		"upgrade":
		{
			"pre_effects": [{"op": "relax", "amount": 2}],
			"effects": [{"op": "summon_unit", "unit": "test_unit_001"}],
		},
	}
	var scene_card := {
		"id": "test_card_scene",
		"name_key": "card.test.scene",
		"type": "scene",
		"rarity": "white",
		"tags": ["test"],
		"cost": 2,
		"target": "self",
		"exhaust": false,
		"pre_effects": [{"op": "relax", "amount": 1}],
		"effects": [{"op": "establish_scene", "scene": "test_scene_001"}],
		"upgrade":
		{
			"pre_effects": [{"op": "relax", "amount": 2}],
			"effects": [{"op": "establish_scene", "scene": "test_scene_001"}],
		},
	}
	var unplayable_card := {
		"id": "test_card_unplayable",
		"name_key": "card.test.unplayable",
		"type": "strategy",
		"rarity": "white",
		"tags": ["test"],
		"cost": 0,
		"target": "self",
		"exhaust": false,
		"unplayable": true,
		"effects": [],
		"upgrade": {},
	}
	var complete_card := {
		"id": "test_card_complete",
		"name_key": "card.test.complete",
		"type": "work",
		"rarity": "white",
		"tags": ["test"],
		"cost": 0,
		"target": "task",
		"exhaust": false,
		"effects": [{"op": "complete", "amount": 14}],
		"upgrade": {},
	}
	var phase_segments_card := complete_card.duplicate(true)
	phase_segments_card.id = "test_card_phase_segments"
	phase_segments_card.name_key = "card.test.phase_segments"
	phase_segments_card.effects = [
		{"op": "complete", "amount": 14},
		{"op": "complete", "amount": 5},
	]
	var choice_card := {
		"id": "test_card_choice",
		"name_key": "card.test.choice",
		"type": "strategy",
		"rarity": "white",
		"tags": ["test"],
		"cost": 0,
		"target": "self",
		"exhaust": false,
		"effects": [{"op": "draw", "amount": 1}, {"op": "discard", "amount": 1}],
		"upgrade": {},
	}
	var k10_card := {
		"id": "test_card_k10",
		"name_key": "card.test.k10",
		"type": "strategy",
		"rarity": "blue",
		"tags": ["test"],
		"cost": 0,
		"vitality_cost": 4,
		"target": "self",
		"exhaust": true,
		"effects": [{"op": "gain_focus", "amount": 2}],
		"upgrade": {"vitality_cost": 3},
	}
	var retain_card := {
		"id": "test_card_retain",
		"name_key": "card.test.retain",
		"type": "strategy",
		"rarity": "white",
		"tags": ["test"],
		"cost": 0,
		"target": "self",
		"exhaust": false,
		"effects": [{"op": "retain_hand_card", "amount": 1}],
		"upgrade": {},
	}
	var lethal_combo_card := {
		"id": "test_card_lethal_combo",
		"name_key": "card.test.lethal_combo",
		"type": "strategy",
		"rarity": "white",
		"tags": ["test"],
		"cost": 0,
		"target": "task",
		"exhaust": false,
		"effects": [{"op": "lose_vitality", "amount": 1}, {"op": "complete", "amount": 5}],
		"upgrade": {},
	}
	_write_json(
		"%s/definitions/cards.json" % root,
		[
			test_card,
			second_test_card,
			cooperation_card,
			scene_card,
			unplayable_card,
			complete_card,
			phase_segments_card,
			choice_card,
			k10_card,
			retain_card,
			lethal_combo_card,
		]
	)
	var manifest_path := "%s/manifests/test_battle_g3.json" % root
	var updated_manifest: Dictionary = _read_json(manifest_path)
	updated_manifest.enabled.card = [
		"test_card_001",
		"test_card_002",
		"test_card_cooperation",
		"test_card_scene",
		"test_card_unplayable",
		"test_card_complete",
		"test_card_phase_segments",
		"test_card_choice",
		"test_card_k10",
		"test_card_retain",
		"test_card_lethal_combo",
	]
	updated_manifest.enabled.unit = ["test_unit_001"]
	updated_manifest.enabled.scene = ["test_scene_001"]
	updated_manifest.enabled.relic = ["test_relic_001", "test_relic_a08"]
	_write_json(manifest_path, updated_manifest)
	_write_json(
		"%s/definitions/units.json" % root,
		[
			{
				"id": "test_unit_001",
				"name_key": "unit.test.name",
				"vitality": 3,
				"cooperation": 1,
				"guard": true,
				"support": {"kind": "none"},
			}
		]
	)
	_write_json(
		"%s/definitions/scenes.json" % root,
		[
			{
				"id": "test_scene_001",
				"name_key": "scene.test.name",
				"battle_limit": 2,
				"prepare_random":
				{
					"options":
					[
						[{"op": "gain_focus", "amount": 1}],
						[{"op": "relax", "amount": 2}],
					],
				},
			}
		]
	)

	_write_json(
		"%s/definitions/characters.json" % root,
		[
			{
				"id": "test_character_001",
				"name_key": "character.test.name",
				"starter_cards": ["test_card_001", "test_card_002"],
				"starter_relic_id": "test_relic_001",
				"passive":
				{
					"id": "test_passive_001",
					"trigger": "work_card_resolved",
					"count": 1,
					"limit": {"per": "round", "times": 1},
					"effects": [{"op": "gain_focus", "amount": 1}],
				},
			}
		]
	)
	_write_json(
		"%s/definitions/relics.json" % root,
		[
			{
				"id": "test_relic_001",
				"name_key": "relic.test.name",
				"availability": "starter",
				"rarity": null,
				"tags": ["test"],
				"hooks":
				[
					{"at": "round_start", "effects": [{"op": "gain_focus", "amount": 1}]},
					{"at": "draw", "effects": [{"op": "draw", "amount": 1}]},
				],
			},
			{
				"id": "test_relic_a08",
				"name_key": "relic.test.a08",
				"availability": "starter",
				"rarity": null,
				"tags": ["test"],
				"hooks":
				[
					{
						"at": "cost_quote",
						"definition_id": "test_card_k10",
						"skip_vitality_cost": true,
						"limit": {"per": "battle", "times": 1},
					}
				],
			}
		]
	)
	_write_json(
		"%s/definitions/tasks.json" % root,
		[
			{
				"id": "test_task_001",
				"name_key": "task.test.name",
				"kind": "normal",
				"phases":
				[
					{
						"phase_key": "main",
						"work_max": 12,
						"intents": [{"index": 1, "text_key": "intent.test", "shield": 2}],
					},
					{
						"phase_key": "final",
						"work_max": 5,
						"intents": [{"index": 1, "text_key": "intent.test.final"}],
					}
				],
			}
		]
	)
	_write_json(
		"%s/definitions/encounters.json" % root,
		[
			{
				"id": "test_encounter_001",
				"name_key": "encounter.test.name",
				"kind": "normal",
				"members": ["test_task_001"],
				"base_ddl": 3,
				"terms": [1],
				"exam_flags": [],
			}
		]
	)
	return root


func _run_preview_cases(
	engine: BattleEngine, state: BattleState, fixture_root: String, failures: Array[String]
) -> void:
	print("G3-03_PREVIEW_FIXTURE_SHA256=", _fixture_hash(fixture_root))
	var original_state := state.to_dictionary()
	var random_source := RandomSource.new("g3-preview-no-random")
	var original_rng := random_source.export_state().to_dictionary()
	var upgraded_card_id := _card_in_hand(state, 1)
	var base_card_id := _card_in_hand(state, 0)
	_check(not upgraded_card_id.is_empty(), "preview fixture draws an upgraded card", failures)
	_check(not base_card_id.is_empty(), "preview fixture draws an unupgraded card", failures)
	if upgraded_card_id.is_empty() or base_card_id.is_empty():
		return

	var task_id: String = state.tasks[0].task_id
	var draft := ActionDraft.new(
		GameConstants.ACTION_PLAY_CARD,
		{"card_instance_id": upgraded_card_id, "target_ids": [task_id]}
	)
	var preview_result := engine.preview(state, draft)
	_check(preview_result.ok, "valid card preview returns an ActionPreview", failures)
	if preview_result.ok:
		var preview: ActionPreview = preview_result.data
		_check(preview.can_submit, "complete affordable target can be submitted", failures)
		_check(preview.revision == -1, "battle preview leaves revision for GameSession", failures)
		_check(
			preview.costs.focus == 1 and preview.costs.vitality == 3,
			"preview uses upgraded focus and vitality costs",
			failures
		)
		_check(
			(
				preview.costs.quote.base == 1
				and preview.costs.quote.vitality_base == 3
				and preview.costs.quote.sources.is_empty()
			),
			"cost quote preserves base, discount and source fields",
			failures
		)
		_check(
			preview.effective_card.effects[0].amount == 2,
			"preview resolves the upgraded effective card face",
			failures
		)

	var missing_target := engine.preview(
		state,
		ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": upgraded_card_id})
	)
	_check(missing_target.ok, "missing target is a normal preview result", failures)
	if missing_target.ok:
		var missing_preview: ActionPreview = missing_target.data
		_check(
			(
				not missing_preview.can_submit
				and missing_preview.required_selections.size() == 1
				and missing_preview.required_selections[0].field == "target_ids"
				and missing_preview.required_selections[0].candidates[0].id == task_id
				and _has_preview_error(missing_preview, GameConstants.ERROR_INVALID_TARGET)
			),
			"preview exposes legal target candidates and a blocking target error",
			failures
		)
	var invalid_target := engine.preview(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": upgraded_card_id, "target_ids": ["test_missing_task"]}
		)
	)
	_check(
		(
			invalid_target.ok
			and _has_preview_error(invalid_target.data, GameConstants.ERROR_INVALID_TARGET)
		),
		"disabled task instances are blocked during preview",
		failures
	)

	var poor_focus_state := state.copy()
	poor_focus_state.player.focus = 0
	var poor_focus := engine.preview(
		poor_focus_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": upgraded_card_id, "target_ids": [task_id]}
		)
	)
	_check(
		(
			poor_focus.ok
			and _has_preview_error(poor_focus.data, GameConstants.ERROR_INSUFFICIENT_RESOURCE)
		),
		"insufficient focus blocks submission without a failed Result",
		failures
	)
	var low_vitality_state := state.copy()
	low_vitality_state.player.vitality = 4
	var low_vitality := engine.preview(
		low_vitality_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": base_card_id, "target_ids": [task_id]}
		)
	)
	_check(
		(
			low_vitality.ok
			and _has_preview_error(low_vitality.data, GameConstants.ERROR_INSUFFICIENT_RESOURCE)
			and (
				(
					_preview_error_details(
						low_vitality.data, GameConstants.ERROR_INSUFFICIENT_RESOURCE
					)
					. must_keep
				)
				== 1
			)
		),
		"active vitality payment preserves the configured minimum",
		failures
	)

	var limited_state := state.copy()
	var origin_id: String = limited_state.card_by_id[upgraded_card_id].origin_card_id
	var limit_key := BattleState.counter_key(
		GameConstants.COUNTER_SCOPE_INSTANCE_ROUND, origin_id, &"play_card"
	)
	limited_state.counters[limit_key] = 1
	var limited := engine.preview(
		limited_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": upgraded_card_id, "target_ids": [task_id]}
		)
	)
	_check(
		limited.ok and _has_preview_error(limited.data, GameConstants.ERROR_LIMIT_REACHED),
		"per-instance play limit blocks a repeated card",
		failures
	)
	var wrong_phase_state := state.copy()
	wrong_phase_state.phase = "enemy_skill"
	var wrong_phase := engine.preview(
		wrong_phase_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": upgraded_card_id, "target_ids": [task_id]}
		)
	)
	_check(
		wrong_phase.ok and _has_preview_error(wrong_phase.data, GameConstants.ERROR_WRONG_PHASE),
		"wrong-phase preview is blocked",
		failures
	)
	var pending_state := state.copy()
	pending_state.phase = "awaiting_choice"
	pending_state.resolution = {"choice": {"choice_id": "test_choice"}}
	var pending := engine.preview(
		pending_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD,
			{"card_instance_id": upgraded_card_id, "target_ids": [task_id]}
		)
	)
	_check(
		pending.ok and _has_preview_error(pending.data, GameConstants.ERROR_CHOICE_PENDING),
		"effect choice blocks another card preview",
		failures
	)
	var no_task_state := state.copy()
	no_task_state.tasks.clear()
	var no_task := engine.preview(
		no_task_state,
		ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": upgraded_card_id})
	)
	_check(
		(
			no_task.ok
			and no_task.data.required_selections.is_empty()
			and _has_preview_error(no_task.data, GameConstants.ERROR_INVALID_TARGET)
		),
		"no legal task yields a blocking error without a selectable candidate",
		failures
	)
	var missing_card := engine.preview(
		state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD, {"card_instance_id": "battle_test_001|not_in_hand"}
		)
	)
	_check(
		(
			missing_card.ok
			and _has_preview_error(missing_card.data, GameConstants.ERROR_INVALID_TARGET)
		),
		"card not in hand is blocked during preview",
		failures
	)
	var unknown_action := engine.preview(state, ActionDraft.new(&"unknown_action", {}))
	_check(
		not unknown_action.ok and unknown_action.error.code == GameConstants.ERROR_INVALID_ARGUMENT,
		"unknown preview action type is a request error",
		failures
	)
	var temporary_modifier_state := state.copy()
	temporary_modifier_state.card_by_id[upgraded_card_id].temporary_modifiers = {"cost_added": 1}
	var unsupported_temporary_modifier := (
		engine
		. preview(
			temporary_modifier_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": upgraded_card_id, "target_ids": [task_id]},
				)
			)
		)
	)
	_check(
		(
			not unsupported_temporary_modifier.ok
			and unsupported_temporary_modifier.error.code == GameConstants.ERROR_ENGINE_NOT_READY
		),
		"unregistered temporary cost modifiers fail closed",
		failures
	)
	var unsupported_action := engine.preview(
		state, ActionDraft.new(GameConstants.ACTION_END_TURN, {})
	)
	_check(
		(
			not unsupported_action.ok
			and unsupported_action.error.code == GameConstants.ERROR_ENGINE_NOT_READY
		),
		"known but unimplemented battle action is reported as not ready",
		failures
	)

	var ordinary_cooperation_state := state.copy()
	var ordinary_cooperation_id := _attach_card(
		ordinary_cooperation_state, "test_card_cooperation", "origin_cooperation", 0
	)
	ordinary_cooperation_state.units.append(
		{"unit_id": "battle_test_001|u_test", "definition_id": "test_unit_001", "vitality": 3}
	)
	var summon_open_slot := engine.preview(
		ordinary_cooperation_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD, {"card_instance_id": ordinary_cooperation_id}
		)
	)
	_check(
		(
			summon_open_slot.ok
			and summon_open_slot.data.can_submit
			and summon_open_slot.data.known_effects.size() == 2
			and summon_open_slot.data.known_effects[0].op == "relax"
			and summon_open_slot.data.known_effects[0].amount == 1
			and summon_open_slot.data.known_effects[1].op == "summon_unit"
		),
		"summon preview keeps pre-effects before card effects when a slot is open",
		failures
	)
	var full_unit_state := ordinary_cooperation_state.copy()
	for index in range(2):
		(
			full_unit_state
			. units
			. append(
				{
					"unit_id": "battle_test_001|u_full_%d" % index,
					"definition_id": "test_unit_001",
					"vitality": 3,
				}
			)
		)
	var missing_replacement := engine.preview(
		full_unit_state,
		ActionDraft.new(
			GameConstants.ACTION_PLAY_CARD, {"card_instance_id": ordinary_cooperation_id}
		)
	)
	_check(
		(
			missing_replacement.ok
			and missing_replacement.data.required_selections.size() == 1
			and missing_replacement.data.required_selections[0].field == "replace_unit_id"
			and missing_replacement.data.required_selections[0].kind == "unit_replacement"
		),
		"full summon slots request a replacement unit selection",
		failures
	)
	var selected_replacement := (
		engine
		. preview(
			full_unit_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{
						"card_instance_id": ordinary_cooperation_id,
						"replace_unit_id": "battle_test_001|u_test",
					}
				)
			)
		)
	)
	_check(
		selected_replacement.ok and selected_replacement.data.can_submit,
		"valid replacement unit completes summon precheck",
		failures
	)
	var invalid_replacement := (
		engine
		. preview(
			full_unit_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{
						"card_instance_id": ordinary_cooperation_id,
						"replace_unit_id": "test_missing_unit",
					}
				)
			)
		)
	)
	_check(
		(
			invalid_replacement.ok
			and _has_preview_error(invalid_replacement.data, GameConstants.ERROR_INVALID_TARGET)
		),
		"unknown replacement unit is blocked",
		failures
	)
	var explicit_null_replacement := (
		engine
		. preview(
			ordinary_cooperation_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": ordinary_cooperation_id, "replace_unit_id": null},
				)
			)
		)
	)
	_check(
		explicit_null_replacement.ok and explicit_null_replacement.data.can_submit,
		"nullable replacement field is accepted when a unit slot is open",
		failures
	)
	var future_task_state := state.copy()
	future_task_state.tasks[0].eligible_round = future_task_state.round_index + 1
	var future_task := (
		engine
		. preview(
			future_task_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": upgraded_card_id},
				)
			)
		)
	)
	_check(
		(
			future_task.ok
			and future_task.data.required_selections.is_empty()
			and _has_preview_error(future_task.data, GameConstants.ERROR_INVALID_TARGET)
		),
		"task targets are unavailable before their eligible round",
		failures
	)
	var independent_exam_state := state.copy()
	independent_exam_state.exam_flags = ["independent_answer"]
	var exam_cooperation_id := _attach_card(
		independent_exam_state, "test_card_cooperation", "origin_exam_coop", 1
	)
	var exam_cooperation := engine.preview(
		independent_exam_state,
		ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": exam_cooperation_id})
	)
	_check(
		(
			exam_cooperation.ok
			and exam_cooperation.data.can_submit
			and exam_cooperation.data.required_selections.is_empty()
			and exam_cooperation.data.effective_card.target == "self"
			and exam_cooperation.data.effective_card.pre_effects.is_empty()
			and exam_cooperation.data.effective_card.effects[0].amount == 7
		),
		"independent-answer preview uses the upgraded relax replacement",
		failures
	)
	var fixed_exam_state := state.copy()
	fixed_exam_state.exam_flags = ["fixed_exam_room"]
	var exam_scene_id := _attach_card(fixed_exam_state, "test_card_scene", "origin_exam_scene", 0)
	var exam_scene := engine.preview(
		fixed_exam_state,
		ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": exam_scene_id})
	)
	_check(
		(
			exam_scene.ok
			and exam_scene.data.can_submit
			and exam_scene.data.effective_card.pre_effects.is_empty()
			and exam_scene.data.effective_card.effects.size() == 2
			and exam_scene.data.known_effects.size() == 2
			and exam_scene.data.effective_card.effects[0].op == "draw"
			and exam_scene.data.effective_card.effects[1].amount == 2
		),
		"fixed-exam preview uses the same draw-and-relax replacement face",
		failures
	)
	var unplayable_state := state.copy()
	var unplayable_id := _attach_card(
		unplayable_state, "test_card_unplayable", "origin_unplayable", 0
	)
	var unplayable := engine.preview(
		unplayable_state,
		ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": unplayable_id})
	)
	_check(
		unplayable.ok and _has_preview_error(unplayable.data, GameConstants.ERROR_UNPLAYABLE),
		"unplayable card face blocks submission",
		failures
	)
	_check(
		state.to_dictionary() == original_state, "preview leaves BattleState unchanged", failures
	)
	_check(
		random_source.export_state().to_dictionary() == original_rng,
		"preview does not advance an RNG stream",
		failures
	)


func _run_apply_cases(
	engine: BattleEngine, state: BattleState, rng_state: Dictionary, failures: Array[String]
) -> void:
	var card_id := _card_in_hand(state, 1)
	var task_id: String = state.tasks[0].task_id
	var original := state.to_dictionary()
	var failed := (
		engine
		. apply(
			state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": card_id, "target_ids": ["missing_task"]},
				)
			),
			rng_state,
		)
	)
	_check(
		not failed.ok and failed.error.code == GameConstants.ERROR_INVALID_TARGET,
		"invalid apply is rejected before publishing",
		failures,
	)
	_check(
		state.to_dictionary() == original, "failed apply leaves published state unchanged", failures
	)
	var applied := (
		engine
		. apply(
			state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": card_id, "target_ids": [task_id]},
				)
			),
			rng_state,
		)
	)
	_check(applied.ok, "valid play_card resolves on a working copy", failures)
	if not applied.ok:
		return
	var step: BattleStep = applied.data
	_check(
		step.stable and step.pending_choice == null,
		"effect queue reaches a stable boundary",
		failures
	)
	_check(step.state.zones.hand.find(card_id) < 0, "resolved card leaves the hand", failures)
	_check(step.state.zones.discard.has(card_id), "ordinary card enters discard", failures)
	var quote_result := engine.calculate_cost(state, card_id)
	var committed_focus_cost := -1
	for event: RuleEvent in step.events:
		if event.type == &"card_played":
			committed_focus_cost = int(event.data.get("focus_cost", -1))
	_check(
		(
			quote_result.ok
			and committed_focus_cost == quote_result.data.cost
			and step.state.player.focus == state.player.focus - committed_focus_cost + 1
		),
		"play payment is committed once before the character passive gain",
		failures
	)
	_check(
		step.state.tasks[0].shield == 0 and step.state.tasks[0].work_remaining == 12,
		"completion consumes the task shield before work",
		failures,
	)
	_check(
		(
			_count_events(step.events, "card_played") == 1
			and _count_events(step.events, "completion_applied") == 1
			and _count_events(step.events, "card_resolved") == 1
		),
		"apply emits ordered card and effect events",
		failures,
	)

	var atomic_turn_state := state.copy()
	var atomic_turn_before := atomic_turn_state.to_dictionary()
	var atomic_turn_rng := rng_state.duplicate(true)
	var atomic_turn := (
		engine
		. apply(
			atomic_turn_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_END_TURN,
					{"retained_card_ids": ["missing_retained_card"]},
				)
			),
			atomic_turn_rng,
		)
	)
	_check(not atomic_turn.ok, "invalid retention is rejected", failures)
	_check(
		atomic_turn_state.to_dictionary() == atomic_turn_before and atomic_turn_rng == rng_state,
		"failed end_turn preserves state and RNG",
		failures,
	)

	var completion_state := state.copy()
	var completion_id := _attach_card(completion_state, "test_card_complete", "origin_complete", 0)
	var completion := (
		engine
		. apply(
			completion_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{
						"card_instance_id": completion_id,
						"target_ids": [completion_state.tasks[0].task_id],
					},
				)
			),
			rng_state,
		)
	)
	_check(completion.ok, "complete effect resolves against the task", failures)
	if completion.ok:
		var completion_step: BattleStep = completion.data
		_check(
			(
				completion_step.state.tasks.size() == 1
				and completion_step.state.tasks[0].phase_key == "final"
				and completion_step.state.tasks[0].work_remaining == 5
			),
			"zero work advances to a fresh phase without carrying overflow",
			failures,
		)
		_check(
			_count_events(completion_step.events, "task_advanced") == 1,
			"phase transition emits task_advanced",
			failures,
		)

	var segmented_state := state.copy()
	var segmented_id := _attach_card(
		segmented_state, "test_card_phase_segments", "origin_segmented", 0
	)
	var segmented := (
		engine
		. apply(
			segmented_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{
						"card_instance_id": segmented_id,
						"target_ids": [segmented_state.tasks[0].task_id]
					},
				)
			),
			rng_state,
		)
	)
	_check(segmented.ok, "multi-segment completion resolves", failures)
	if segmented.ok:
		_check(
			(
				segmented.data.state.tasks.size() == 1
				and segmented.data.state.tasks[0].phase_key == "final"
				and segmented.data.state.tasks[0].work_remaining == 5
			),
			"old locked target is skipped after phase transition",
			failures,
		)
	var summon_state := state.copy()
	var summon_id := _attach_card(summon_state, "test_card_cooperation", "origin_summon_apply", 0)
	var summon := (
		engine
		. apply(
			summon_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": summon_id}),
			rng_state,
		)
	)
	_check(summon.ok, "summon effect resolves with an open unit slot", failures)
	if summon.ok:
		var summon_step: BattleStep = summon.data
		_check(summon_step.state.units.size() == 1, "summon creates a unit instance", failures)
		_check(
			_count_events(summon_step.events, "unit_summoned") == 1,
			"summon emits unit_summoned",
			failures,
		)
		_check(
			_summoned_guard_exists(summon_step.state),
			"guard unit has one runtime guard status",
			failures,
		)
		var pressure_state := summon_step.state.copy()
		pressure_state.player.relax = 0
		pressure_state.tasks[0].intent_snapshot.pressure = 5
		pressure_state.tasks[0].intent_snapshot.pressure_times = 2
		var pressure_result := (
			engine
			. apply(
				pressure_state,
				ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
				summon_step.rng_state,
			)
		)
		_check(pressure_result.ok, "guard pressure sequence resolves", failures)
		if pressure_result.ok:
			_check(
				(
					pressure_result.data.state.units.is_empty()
					and pressure_result.data.state.player.vitality == 49
				),
				"guard absorbs only the first pressure segment and does not overflow",
				failures,
			)

	var full_slots_state := state.copy()
	for index in 3:
		(
			full_slots_state
			. units
			. append(
				{
					"unit_id": "%s|u_full_%d" % [state.battle_id, index],
					"definition_id": "test_unit_001",
					"vitality": 3,
					"max_vitality": 3,
					"cooperation": 1,
					"guard": true,
					"entered_order": index + 3,
					"actions_taken": 0,
					"target_id": "",
				}
			)
		)
	var full_slots_card := _attach_card(
		full_slots_state, "test_card_cooperation", "origin_full_slots", 0
	)
	var full_slots_before := full_slots_state.to_dictionary()
	var full_slots_rng := rng_state.duplicate(true)
	var canceled_switch := (
		engine
		. apply(
			full_slots_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": full_slots_card}),
			full_slots_rng,
		)
	)
	_check(
		(
			(
				not canceled_switch.ok
				and canceled_switch.error.code == GameConstants.ERROR_INVALID_TARGET
			)
			and full_slots_state.to_dictionary() == full_slots_before
			and full_slots_rng == rng_state
		),
		"full unit slots require a replacement and canceled switch is atomic",
		failures,
	)

	var scene_state := state.copy()
	var scene_card_id := _attach_card(scene_state, "test_card_scene", "origin_scene_apply", 0)
	var scene_result := (
		engine
		. apply(
			scene_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": scene_card_id}),
			rng_state,
		)
	)
	_check(scene_result.ok, "scene effect resolves", failures)
	if scene_result.ok:
		var scene_step: BattleStep = scene_result.data
		_check(
			(
				typeof(scene_step.state.scene) == TYPE_DICTIONARY
				and scene_step.state.scene.definition_id == "test_scene_001"
			),
			"scene establishes a battle scene instance",
			failures,
		)
		var initial_pending: Array = scene_step.state.scene.pending_random_result
		_check(
			(
				initial_pending.size() == 1
				and scene_step.state.player.focus == state.player.focus - 2
				and scene_step.state.player.relax == 1
			),
			"scene random result is stored at establishment and waits for next prepare",
			failures,
		)
		var scene_turn := (
			engine
			. apply(
				scene_step.state,
				ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
				scene_step.rng_state,
			)
		)
		_check(scene_turn.ok, "scene prepare phase resumes from stored result", failures)
		if scene_turn.ok:
			var expected_focus := 3
			var expected_relax := 0
			if initial_pending[0].op == "gain_focus":
				expected_focus += 1
			else:
				expected_relax += 2
			_check(
				(
					scene_turn.data.state.player.focus == expected_focus
					and scene_turn.data.state.player.relax == expected_relax
					and scene_turn.data.state.scene.pending_random_result is Array
					and scene_turn.data.rng_state != scene_step.rng_state
				),
				"next prepare applies the saved scene result and pre-rolls the following one",
				failures,
			)

	var independent_apply_state := state.copy()
	independent_apply_state.exam_flags = ["independent_answer"]
	var independent_apply_card := _attach_card(
		independent_apply_state, "test_card_cooperation", "origin_independent_apply", 1
	)
	var independent_apply := (
		engine
		. apply(
			independent_apply_state,
			ActionDraft.new(
				GameConstants.ACTION_PLAY_CARD, {"card_instance_id": independent_apply_card}
			),
			rng_state,
		)
	)
	_check(
		(
			independent_apply.ok
			and independent_apply.data.state.units.is_empty()
			and independent_apply.data.state.player.relax == 7
			and independent_apply.data.state.outcome == null
		),
		"independent-answer execution grants upgraded relax without summoning",
		failures,
	)
	var fixed_room_state := state.copy()
	fixed_room_state.exam_flags = ["fixed_exam_room"]
	var fixed_room_card := _attach_card(
		fixed_room_state, "test_card_scene", "origin_fixed_room_apply", 1
	)
	var fixed_room := (
		engine
		. apply(
			fixed_room_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": fixed_room_card}),
			rng_state,
		)
	)
	_check(
		(
			fixed_room.ok
			and fixed_room.data.state.scene == null
			and fixed_room.data.state.player.relax == 4
			and _count_events(fixed_room.data.events, "scene_established") == 0
		),
		"fixed-exam execution draws and grants upgraded relax without establishing a scene",
		failures,
	)

	var choice_state := state.copy()
	var choice_card_id := _attach_card(choice_state, "test_card_choice", "origin_choice_apply", 0)
	var choice_start := (
		engine
		. apply(
			choice_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": choice_card_id}),
			rng_state,
		)
	)
	_check(
		choice_start.ok and choice_start.data.pending_choice != null,
		"draw then discard pauses for a choice",
		failures,
	)
	if choice_start.ok and choice_start.data.pending_choice != null:
		var choice_step: BattleStep = choice_start.data
		var choice_state_before := choice_step.state.to_dictionary()
		var choice_rng_before: Dictionary = choice_step.rng_state.duplicate(true)
		var bad_choice := (
			engine
			. apply(
				choice_step.state,
				(
					ActionDraft
					. new(
						GameConstants.ACTION_CONFIRM_CHOICE,
						{"choice_id": "wrong", "selected_ids": []},
					)
				),
				choice_step.rng_state,
			)
		)
		_check(not bad_choice.ok, "wrong choice id is rejected", failures)
		_check(
			(
				choice_step.state.to_dictionary() == choice_state_before
				and choice_step.rng_state == choice_rng_before
				and choice_step.state.phase == "awaiting_choice"
			),
			"rejected choice preserves the pending workspace and RNG",
			failures,
		)
		var selected_id: String = str(choice_step.pending_choice.candidates[0].id)
		var confirmed_choice := (
			engine
			. apply(
				choice_step.state,
				(
					ActionDraft
					. new(
						GameConstants.ACTION_CONFIRM_CHOICE,
						{
							"choice_id": choice_step.pending_choice.choice_id,
							"selected_ids": [selected_id],
						},
					)
				),
				choice_step.rng_state,
			)
		)
		_check(
			(
				confirmed_choice.ok
				and confirmed_choice.data.pending_choice == null
				and confirmed_choice.data.stable
			),
			"valid choice confirmation resumes and finishes the queue",
			failures,
		)

	var empty_retain_state := state.copy()
	for held_id in empty_retain_state.zones.hand.duplicate():
		empty_retain_state.zones.hand.erase(held_id)
		empty_retain_state.zones.discard.append(held_id)
	var empty_retain_id := _attach_card(
		empty_retain_state, "test_card_retain", "origin_empty_retain", 0
	)
	var empty_retain := (
		engine
		. apply(
			empty_retain_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": empty_retain_id}),
			rng_state,
		)
	)
	_check(
		empty_retain.ok and empty_retain.data.pending_choice == null and empty_retain.data.stable,
		"retain effect with no other hand cards does not create an empty choice",
		failures,
	)

	var retain_state := state.copy()
	var retain_id := _attach_card(retain_state, "test_card_retain", "origin_retain", 0)
	var retain_start := (
		engine
		. apply(
			retain_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": retain_id}),
			rng_state,
		)
	)
	_check(
		(
			retain_start.ok
			and retain_start.data.pending_choice != null
			and retain_start.data.pending_choice.kind == "retain"
			and retain_start.data.pending_choice.max_count == 1
		),
		"retain effect offers one other card when candidates exist",
		failures,
	)
	if retain_start.ok and retain_start.data.pending_choice != null:
		var retain_step: BattleStep = retain_start.data
		var selected_retain_id := str(retain_step.pending_choice.candidates[0].id)
		var confirmed_retain := (
			engine
			. apply(
				retain_step.state,
				(
					ActionDraft
					. new(
						GameConstants.ACTION_CONFIRM_CHOICE,
						{
							"choice_id": retain_step.pending_choice.choice_id,
							"selected_ids": [selected_retain_id],
						}
					)
				),
				retain_step.rng_state,
			)
		)
		_check(
			(
				confirmed_retain.ok
				and confirmed_retain.data.state.retained_card_ids == [selected_retain_id]
			),
			"confirmed retain choice is attached to the stable work state",
			failures,
		)
		if confirmed_retain.ok:
			var retained_turn := (
				engine
				. apply(
					confirmed_retain.data.state,
					ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
					confirmed_retain.data.rng_state,
				)
			)
			_check(
				(
					retained_turn.ok
					and retained_turn.data.state.zones.hand.has(selected_retain_id)
					and not retained_turn.data.state.zones.discard.has(selected_retain_id)
					and retained_turn.data.state.retained_card_ids.is_empty()
				),
				"retained card skips discard once and its marker is consumed",
				failures,
			)
			var left_hand_state: BattleState = confirmed_retain.data.state.copy()
			left_hand_state.zones.hand.clear()
			left_hand_state.zones.draw.clear()
			left_hand_state.zones.discard.clear()
			left_hand_state.zones.exhaust.clear()
			left_hand_state.zones.resolving.clear()
			for candidate_id in left_hand_state.card_by_id:
				if str(candidate_id) != selected_retain_id:
					left_hand_state.zones.draw.append(str(candidate_id))
			left_hand_state.zones.discard.append(selected_retain_id)
			var left_hand_turn := (
				engine
				. apply(
					left_hand_state,
					ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
					confirmed_retain.data.rng_state,
				)
			)
			_check(
				(
					left_hand_turn.ok
					and left_hand_turn.data.state.zones.discard.has(selected_retain_id)
					and left_hand_turn.data.state.retained_card_ids.is_empty()
				),
				"card leaving hand invalidates its outstanding retain marker",
				failures,
			)

	var expiry_state := state.copy()
	var expiry_player_id: String = expiry_state.player.entity_id
	expiry_state.statuses = [
		{
			"status_id": "anxiety",
			"stacks": 1,
			"target_id": expiry_player_id,
			"expiry": "next_prepare"
		},
		{
			"status_id": "procrastination",
			"stacks": 1,
			"target_id": expiry_player_id,
			"expiry": "next_draw"
		},
	]
	var expiry_step := (
		engine
		. apply(
			expiry_state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
			rng_state,
		)
	)
	_check(
		(
			expiry_step.ok
			and expiry_step.data.state.player.focus == 2
			and expiry_step.data.state.zones.hand.size() == 4
			and expiry_step.data.state.statuses.is_empty()
			and _count_events(expiry_step.data.events, "status_removed") == 2
		),
		"anxiety and procrastination affect their expiry phases before clearing",
		failures,
	)
	var restore_state := state.copy()
	restore_state.tasks[0].work_remaining = 5
	restore_state.tasks[0].intent_snapshot = {
		"index": 1, "text_key": "intent.test.restore", "work_restore": 2
	}
	var restored_work := (
		engine
		. apply(
			restore_state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
			rng_state,
		)
	)
	var work_restored_event_found := false
	if restored_work.ok:
		for event: RuleEvent in restored_work.data.events:
			if (
				event.type == &"work_restored"
				and int(event.data.get("before", -1)) == 5
				and int(event.data.get("after", -1)) == 7
			):
				work_restored_event_found = true
	_check(
		(
			restored_work.ok
			and restored_work.data.state.tasks[0].work_remaining == 7
			and work_restored_event_found
		),
		"enemy work restoration reports its before and after values",
		failures,
	)

	var drowsy_state := state.copy()
	drowsy_state.tasks[0].shield = 0
	drowsy_state.tasks[0].work_remaining = 30
	drowsy_state.tasks[0].work_max = 30
	(
		drowsy_state
		. statuses
		. append(
			{
				"status_id": "drowsiness",
				"stacks": 2,
				"target_id": drowsy_state.player.entity_id,
				"expiry": "next_player_action_end",
			}
		)
	)
	var drowsy_results: Array[BattleStep] = []
	var drowsy_rng: Dictionary = rng_state.duplicate(true)
	for index in 2:
		var work_id := _attach_card(
			drowsy_state, "test_card_complete", "origin_drowsy_%d" % index, 0
		)
		var work_result := (
			engine
			. apply(
				drowsy_state,
				(
					ActionDraft
					. new(
						GameConstants.ACTION_PLAY_CARD,
						{
							"card_instance_id": work_id,
							"target_ids": [drowsy_state.tasks[0].task_id]
						},
					)
				),
				drowsy_rng,
			)
		)
		if work_result.ok:
			drowsy_results.append(work_result.data)
			drowsy_state = work_result.data.state
			drowsy_rng = work_result.data.rng_state
	_check(
		(
			drowsy_results.size() == 2
			and drowsy_results[0].events.any(
				func(event): return event.type == &"completion_applied" and event.data.amount == 12
			)
			and drowsy_results[1].events.any(
				func(event): return event.type == &"completion_applied" and event.data.amount == 12
			)
			and not drowsy_state.statuses.is_empty()
		),
		"drowsiness reduces the first segment of both cards in the action window",
		failures,
	)
	if drowsy_results.size() == 2:
		var drowsy_end := (
			engine
			. apply(
				drowsy_state,
				ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
				drowsy_rng,
			)
		)
		_check(
			(
				drowsy_end.ok
				and drowsy_end.data.state.statuses.is_empty()
				and _count_events(drowsy_end.data.events, "status_removed") == 1
			),
			"drowsiness expires at player-action end before ally action",
			failures,
		)

	var turn_state := state.copy()
	var turn_before_hand: int = turn_state.zones.hand.size()
	var turn_result := (
		engine
		. apply(
			turn_state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
			rng_state,
		)
	)
	_check(turn_result.ok, "end_turn runs the complete round pipeline", failures)
	if turn_result.ok:
		var turn_step: BattleStep = turn_result.data
		_check(
			turn_step.state.phase == "player_action" and turn_step.state.round_index == 2,
			"end_turn returns to player action in the next round",
			failures,
		)
		_check(
			_count_events(turn_step.events, "card_discarded") == turn_before_hand,
			"discard phase emits each hand discard exactly once",
			failures,
		)
		_check(
			(
				_count_events(turn_step.events, "ddl_ticked") == 1
				and turn_step.state.ddl == state.ddl - 1
			),
			"round end decrements DDL once",
			failures,
		)

	var deadline_state := state.copy()
	deadline_state.ddl = 1
	var deadline_result := (
		engine
		. apply(
			deadline_state,
			ActionDraft.new(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}),
			rng_state,
		)
	)
	_check(
		(
			deadline_result.ok
			and deadline_result.data.outcome != null
			and deadline_result.data.outcome.reason == "deadline_expired"
		),
		"DDL one with remaining work fails at round end",
		failures,
	)
	var final_deadline_state := state.copy()
	final_deadline_state.ddl = 1
	final_deadline_state.tasks[0].phase_key = "final"
	final_deadline_state.tasks[0].work_remaining = 5
	final_deadline_state.tasks[0].work_max = 5
	var final_deadline_card := _attach_card(
		final_deadline_state, "test_card_complete", "origin_final_deadline", 0
	)
	var final_deadline_win := (
		engine
		. apply(
			final_deadline_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{
						"card_instance_id": final_deadline_card,
						"target_ids": [final_deadline_state.tasks[0].task_id],
					}
				)
			),
			rng_state,
		)
	)
	_check(
		(
			final_deadline_win.ok
			and final_deadline_win.data.outcome.result == "won"
			and _count_events(final_deadline_win.data.events, "ddl_ticked") == 0
		),
		"last task completion at DDL one wins before the deadline tick",
		failures,
	)

	var win_state := state.copy()
	win_state.tasks[0].phase_key = "final"
	win_state.tasks[0].work_remaining = 5
	win_state.tasks[0].work_max = 5
	var win_card_id := _attach_card(win_state, "test_card_complete", "origin_last_task", 0)
	var win_result := (
		engine
		. apply(
			win_state,
			(
				ActionDraft
				. new(
					GameConstants.ACTION_PLAY_CARD,
					{"card_instance_id": win_card_id, "target_ids": [win_state.tasks[0].task_id]},
				)
			),
			rng_state,
		)
	)
	_check(
		(
			win_result.ok
			and win_result.data.outcome != null
			and win_result.data.outcome.result == "won"
		),
		"last task completion finishes immediately",
		failures,
	)

	var lethal_state := state.copy()
	lethal_state.player.vitality = 1
	lethal_state.tasks[0].phase_key = "final"
	lethal_state.tasks[0].work_remaining = 5
	lethal_state.tasks[0].work_max = 5
	var lethal_id := _attach_card(lethal_state, "test_card_lethal_combo", "origin_lethal_combo", 0)
	var lethal_result := (
		engine
		. apply(
			lethal_state,
			ActionDraft.new(
				GameConstants.ACTION_PLAY_CARD,
				{"card_instance_id": lethal_id, "target_ids": [lethal_state.tasks[0].task_id]}
			),
			rng_state,
		)
	)
	_check(
		(
			lethal_result.ok
			and lethal_result.data.outcome.result == "lost"
			and lethal_result.data.outcome.reason == "vitality_depleted"
			and lethal_result.data.state.tasks[0].work_remaining == 5
			and _count_events(lethal_result.data.events, "task_completed") == 0
		),
		"vitality loss is terminal before a later final-task completion effect",
		failures,
	)


func _run_relic_cost_cases(
	engine: BattleEngine, input: Dictionary, failures: Array[String]
) -> void:
	var relic_input := input.duplicate(true)
	relic_input.relics = ["test_relic_a08"]
	var begun := engine.begin(relic_input)
	_check(begun.ok, "supported cost-quote relic initializes in battle state", failures)
	if not begun.ok:
		return
	var begin_step: BattleStep = begun.data
	var state: BattleState = begin_step.state.copy()
	var player_order: int = state.source_registry[state.player.entity_id].creation_order
	var relic_instance_id := ""
	for source_id in state.source_registry:
		if state.source_registry[source_id].kind == "relic":
			relic_instance_id = str(source_id)
	_check(
		(
			state.relics == ["test_relic_a08"]
			and not relic_instance_id.is_empty()
			and state.source_registry[relic_instance_id].creation_order == player_order + 1
			and state.source_registry[state.tasks[0].task_id].creation_order == player_order + 2
		),
		"initial source order is character, relic, then encounter task",
		failures,
	)
	state.player.vitality = 4
	var card_id := _attach_card(state, "test_card_k10", "origin_k10_a08", 0)
	var before_counters: Dictionary = state.counters.duplicate(true)
	var quote_result := engine.calculate_cost(state, card_id)
	_check(
		(
			quote_result.ok
			and quote_result.data.vitality_cost == 0
			and quote_result.data.sources.size() == 1
			and state.counters == before_counters
		),
		"A08 preview exempts K10 without consuming its once-per-battle source",
		failures,
	)
	var preview_result := (
		engine
		. preview(
			state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": card_id}),
		)
	)
	_check(
		preview_result.ok and preview_result.data.can_submit,
		"A08 permits K10 at the minimum vitality boundary",
		failures,
	)
	var first_use := (
		engine
		. apply(
			state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": card_id}),
			begin_step.rng_state,
		)
	)
	_check(
		(
			first_use.ok
			and first_use.data.state.player.vitality == 4
			and first_use.data.state.player.focus == 5
			and first_use.data.state.zones.exhaust.has(card_id)
			and _count_events(first_use.data.events, "relic_triggered") == 1
		),
		"A08 first K10 use keeps vitality, grants focus and consumes the card",
		failures,
	)
	if not first_use.ok:
		return
	var second_state: BattleState = first_use.data.state.copy()
	second_state.player.vitality = 6
	var second_id := _attach_card(second_state, "test_card_k10", "origin_k10_second", 0)
	var second_quote := engine.calculate_cost(second_state, second_id)
	var second_use := (
		engine
		. apply(
			second_state,
			ActionDraft.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": second_id}),
			first_use.data.rng_state,
		)
	)
	_check(
		(
			second_quote.ok
			and second_quote.data.vitality_cost == 4
			and second_quote.data.sources.is_empty()
			and second_use.ok
			and second_use.data.state.player.vitality == 2
			and _count_events(second_use.data.events, "relic_triggered") == 0
		),
		"A08 exemption is consumed only by the committed first K10",
		failures,
	)


func _card_in_hand(state: BattleState, upgrade_level: int) -> String:
	for card_id in state.zones.hand:
		if int(state.card_by_id[card_id].upgrade_level) == upgrade_level:
			return str(card_id)
	return ""


func _summoned_guard_exists(state: BattleState) -> bool:
	if state.units.is_empty():
		return false
	var unit_id: String = state.units[0].unit_id
	for status: Dictionary in state.statuses:
		if status.get("status_id") == "guard" and status.get("target_id") == unit_id:
			return true
	return false


func _attach_card(
	state: BattleState, definition_id: String, origin_card_id: String, upgrade_level: int
) -> String:
	var card_id := "%s|preview_%s" % [state.battle_id, origin_card_id]
	state.card_by_id[card_id] = {
		"card_id": card_id,
		"definition_id": definition_id,
		"origin_card_id": origin_card_id,
		"upgrade_level": upgrade_level,
		"temporary_modifiers": {},
	}
	state.zones.hand.append(card_id)
	return card_id


func _has_preview_error(preview: ActionPreview, code: StringName) -> bool:
	for error: ApiError in preview.blocking_errors:
		if error.code == code:
			return true
	return false


func _preview_error_details(preview: ActionPreview, code: StringName) -> Dictionary:
	for error: ApiError in preview.blocking_errors:
		if error.code == code:
			return error.details
	return {}


func _remove_fixture(root: String) -> void:
	for file_name in ContentDB.FILE_NAMES.values():
		DirAccess.remove_absolute("%s/definitions/%s.json" % [root, file_name])
	DirAccess.remove_absolute("%s/manifests/test_battle_g3.json" % root)
	DirAccess.remove_absolute("%s/definitions" % root)
	DirAccess.remove_absolute("%s/manifests" % root)
	DirAccess.remove_absolute(root)


func _read_json(path: String) -> Variant:
	var parser := JSON.new()
	var source := FileAccess.get_file_as_string(path)
	assert(parser.parse(source) == OK, "could not parse fixture JSON %s" % path)
	return parser.data


func _write_json(path: String, value: Variant) -> void:
	_write_file(path, JSON.stringify(_normalize_numbers(value)))


func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, round(value)):
		return int(value)
	if typeof(value) == TYPE_DICTIONARY:
		var normalized := {}
		for key in value:
			normalized[key] = _normalize_numbers(value[key])
		return normalized
	if typeof(value) == TYPE_ARRAY:
		var normalized: Array = []
		for item in value:
			normalized.append(_normalize_numbers(item))
		return normalized
	return value


func _write_file(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "could not write battle fixture %s" % path)
	file.store_string(value)


func _fixture_hash(root: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var files: Array[String] = ["manifests/test_battle_g3.json"]
	for file_name in FIXTURE_FILES:
		files.append("definitions/%s.json" % file_name)
	files.sort()
	for relative_path in files:
		context.update(relative_path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(FileAccess.get_file_as_bytes("%s/%s" % [root, relative_path]))
	return context.finish().hex_encode()


func _deal_ids(state: BattleState) -> Array[String]:
	var result: Array[String] = []
	for card_id in state.zones.hand:
		result.append(state.card_by_id[card_id].origin_card_id)
	for card_id in state.zones.draw:
		result.append(state.card_by_id[card_id].origin_card_id)
	return result


func _origin_ids(cards: Array) -> Array[String]:
	var result: Array[String] = []
	for card in cards:
		result.append(card.card_id)
	return result


func _all_cards_have_origins(state: BattleState) -> bool:
	for card in state.card_by_id.values():
		if not card.has("origin_card_id") or card.origin_card_id.is_empty():
			return false
	return true


func _event_indexes_are_contiguous(events: Array[RuleEvent]) -> bool:
	for index in events.size():
		if events[index].index != index:
			return false
	return true


func _count_events(events: Array[RuleEvent], type: String) -> int:
	var count := 0
	for event in events:
		if event.type == StringName(type):
			count += 1
	return count


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
