class_name TestRoomService
extends RefCounted

## Isolated battle-sandbox service used by GameSession. It never writes formal
## saves, never mutates the base catalog, and never executes unregistered ops.

const ROOM_VALIDATOR = preload("res://src/test/test_room_validator.gd")
const MANIFEST_ID := RelicPilot.ROSTER
var _manifest_id := MANIFEST_ID
const MANIFEST_ROOT := "res://data/four_year"
const ZONES := ["hand", "draw", "discard", "exhaust"]
const PLAYER_FIELDS := ["vitality", "max_vitality", "max_vitality_base", "focus", "relax"]
const BATTLE_ACTIONS := [&"play_card", &"end_turn", &"confirm_choice", &"set_ally_target"]
const ROOM_ACTIONS := [
	&"enter_node", &"buy_item", &"remove_card", &"choose_event", &"take_rest", &"leave_node",
	&"choose_campaign", &"claim_reward", &"skip_reward", &"choose_term_option", &"choose_ending",
]
const CONFIG_KEYS := [
	"node_key",
	"start_year",
	"template_id",
	"character_id",
	"encounter_id",
	"difficulty",
	"seed",
	"cards",
	"relics",
	"overlay",
	"switches",
]
const PATCH_KEYS := [
	"schema_version",
	"test_id",
	"branch_id",
	"expected_revision",
	"resolution_policy",
	"ops",
]
const LIMITS := {
	"zone": 500,
	"cards": 1000,
	"tasks": 100,
	"units": 64,
	"statuses": 1000,
	"relics": 128,
	"chapters": 24,
	"value": 9999,
	"ddl": 99,
	"round": 999,
	"ops": 100,
	"definitions": 500,
	"overrides": 2000,
}
const SWITCHES := {
	"allow_zero_vitality": "允许主角精力为 0 并继续实验",
	"allow_empty_tasks": "允许没有敌方任务",
	"freeze_outcome": "不自动判胜/判负",
	"freeze_ddl": "DDL 不随回合递减",
	"freeze_enemy": "跳过敌方技能与压力",
	"infinite_focus": "费用支付不改专注",
	"no_cost": "出牌不检查/不支付费用",
	"ignore_limits": "忽略每回合/每实例限次",
	"ignore_relic_unique": "允许重复饰品",
	"ignore_relic_slots": "忽略饰品槽位上限",
	"ignore_unit_slots": "忽略伙伴/单位槽位上限",
	"ignore_chapter_slots": "忽略章节槽位上限",
	"manual_rule_steps": "敌方/回合结算只在手动单步时推进",
	"keep_hand": "回合结束不强制弃手牌",
}
# Historical defaults used only to interpret old map snapshots.
const FREE_SWITCHES := [
	"allow_zero_vitality",
	"allow_empty_tasks",
	"ignore_limits",
	"ignore_relic_unique",
	"ignore_relic_slots",
	"ignore_unit_slots",
	"ignore_chapter_slots",
	"keep_hand",
	"infinite_focus",
	"no_cost",
]
const OP_KEYS := {
	"enter_node": ["op", "node_key"],
	"set_money": ["op", "value"],
	"set_character": ["op", "character_id", "keep_deck", "keep_relics"],
	"set_switch": ["op", "key", "value"],
	"set_player_field": ["op", "field", "value"],
	"adjust_player_field": ["op", "field", "delta"],
	"set_player_lock": ["op", "field", "locked"],
	"add_card": ["op", "definition_id", "zone", "count", "position", "persistence_scope"],
	"remove_instance": ["op", "instance_id", "persistence_scope"],
	"duplicate_instance": ["op", "instance_id", "count", "zone", "persistence_scope"],
	"move_instance": ["op", "instance_id", "zone", "position"],
	"set_zone_order": ["op", "zone", "instance_ids"],
	"shuffle_zone": ["op", "zone"],
	"clear_zone": ["op", "zone", "persistence_scope"],
	"set_card_field": ["op", "scope", "target", "field", "value", "persistence_scope"],
	"add_relic": ["op", "relic_id", "position", "persistence_scope"],
	"remove_relic": ["op", "relic_id", "position", "persistence_scope"],
	"add_status": ["op", "status_id", "target_id", "stacks", "expiry"],
	"remove_status": ["op", "instance_id", "status_id", "target_id"],
	"set_status_field": ["op", "instance_id", "field", "value"],
	"clear_statuses": ["op", "target_id"],
	"add_task": ["op", "definition_id", "position"],
	"remove_task": ["op", "task_id"],
	"set_task_field": ["op", "task_id", "field", "value"],
	"set_task_intent": ["op", "task_id", "intent", "intent_cursor"],
	"set_task_phase": ["op", "task_id", "phase_key"],
	"add_unit": ["op", "definition_id", "position"],
	"remove_unit": ["op", "unit_id"],
	"set_unit_field": ["op", "unit_id", "field", "value"],
	"replace_encounter": ["op", "encounter_id"],
	"set_round": ["op", "round_index"],
	"set_ddl": ["op", "ddl"],
	"set_phase": ["op", "phase"],
	"set_counter": ["op", "key", "value"],
	"remove_counter": ["op", "key"],
	"set_rng": ["op", "stream", "seed", "state"],
	"reset_rng": ["op", "mode", "seed"],
	"set_rule_field": ["op", "path", "value"],
	"set_status_cap": ["op", "status_id", "cap"],
	"upsert_definition": ["op", "kind", "id", "definition"],
	"remove_definition": ["op", "kind", "id"],
	"set_definition_field": ["op", "kind", "id", "path", "value"],
	"set_v3_field": ["op", "path", "value"],
	"set_outcome": ["op", "result"],
	"clear_outcome": ["op"],
	"run_rule_op": ["op", "rule", "args"],
	"clear_scene": ["op"],
	"add_scene": ["op", "scene_id"],
}

var state: TestRoomState
var base_catalog: ContentDB
var catalog: TestContent
var engine: BattleEngine
var store: TestStore
var view_builder: Callable
var notice: String = ""
# File-management binding stays outside rule snapshots and undo/checkpoint state.
var _snapshot_id: String = ""
var _snapshot_name: String = ""
var _node_cache_seed := ""
var _node_cache: Array[Dictionary] = []
var _projected_map_key := ""
var _projected_nodes: Array[Dictionary] = []


func _init(p_store: TestStore = null, p_view_builder: Callable = Callable(), manifest_id: String = MANIFEST_ID) -> void:
	_manifest_id = manifest_id
	store = p_store if p_store != null else TestStore.new()
	view_builder = p_view_builder


func active() -> bool:
	return state != null


func get_error() -> ApiError:
	return null


func start(config_value: Variant, pilot_events: Array[RuleEvent] = []) -> GameResult:
	if state != null:
		return _failure(
			GameConstants.ERROR_TEST_CONTEXT_MISMATCH,
			"test.room.active",
			{"test_id": state.test_id}
		)
	if typeof(config_value) != TYPE_DICTIONARY:
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.invalid")
	var config: Dictionary = config_value
	for key in config:
		if not CONFIG_KEYS.has(key):
			return _failure(
				GameConstants.ERROR_INVALID_ARGUMENT, "test.config.unknown", {"key": str(key)}
			)
	if config.has("start_year"):
		var year_value: Variant = config.start_year
		# JSON decodes integer-valued config numbers as floats.
		if not (year_value is int or year_value is float) or float(year_value) < 1.0 or float(year_value) > 4.0 or floor(float(year_value)) != float(year_value):
			return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.start_year")
	var character_id := str(config.get("character_id", "P01"))
	var loaded := ContentDB.new(MANIFEST_ROOT)
	var loaded_result := loaded.load(_manifest_id)
	if not loaded_result.ok:
		return loaded_result
	var overlay_issues := ROOM_VALIDATOR.validate_overlay_value(config.get("overlay", {}), loaded)
	if not overlay_issues.is_empty():
		return _failure(GameConstants.ERROR_CONTENT_INVALID, "test.config.overlay", {"issues": overlay_issues})
	var overlay := TestOverlay.from_dictionary(config.get("overlay", {}))
	var wrapped := TestContent.new(loaded, overlay)
	var character := _definition(wrapped, "character", character_id)
	if character.is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"test.config.character",
			{"character_id": character_id}
		)
	var encounter_id := str(config.get("encounter_id", ""))
	if encounter_id.is_empty():
		encounter_id = _default_encounter(loaded)
	if _definition(wrapped, "encounter", encounter_id).is_empty():
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"test.config.encounter",
			{"encounter_id": encounter_id}
		)
	var cards := _starter_cards(wrapped, character, config.get("cards", []))
	if not cards.ok:
		return cards
	var relics := _starting_relics(wrapped, config.get("relics", []), character_id)
	if not relics.ok:
		return relics
	var seed := str(config.get("seed", "42"))
	if seed.is_empty():
		seed = "42"
	var test_id := _new_test_id()
	var rng := RandomSource.new(seed)
	var begin_input := {
		"battle_id": "%s-b1" % test_id,
		"node_id": "",
		"encounter_id": encounter_id,
		"character_id": character_id,
		"difficulty": "normal",
		"cards": cards.data,
		"relics": relics.data,
		"rng_state": rng.export_state().to_dictionary(),
	}
	var node_key := str(config.get("node_key", ""))
	var switches := _default_switches(config.get("switches", {}))
	wrapped.battle_switches = switches
	var local_engine := BattleEngine.new(wrapped)
	var begun := local_engine.begin(begin_input)
	if not begun.ok:
		return begun
	var step: BattleStep = begun.data
	var new_state := TestRoomState.new()
	new_state.test_id = test_id
	new_state.branch_id = 0
	new_state.revision = 0
	new_state.attempt = 1
	new_state.seed = seed
	new_state.config = {
		"template_id": str(config.get("template_id", "character.%s" % character_id)),
		"character_id": character_id,
		"encounter_id": encounter_id,
		"difficulty": "normal",
		"seed": seed,
		"cards": cards.data.duplicate(true),
		"relics": relics.data.duplicate(true),
	}
	if config.has("start_year"):
		new_state.config["start_year"] = int(config.start_year)
	new_state.battle = step.state
	for _id in new_state.battle.relics:
		new_state.relic_origins.append("")
	new_state.rng = step.rng_state.duplicate(true)
	new_state.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
	new_state.overlay = overlay
	new_state.switches = switches
	new_state.config["switches"] = _explicit_switches(config.get("switches", {}))
	new_state.result = {"source": "none", "outcome": "", "editable": true}
	new_state.checkpoints = []
	base_catalog = loaded
	catalog = wrapped
	engine = local_engine
	if not node_key.is_empty():
		var moved := _enter_test_node(new_state, node_key)
		if not moved.ok:
			return moved
	elif config.has("start_year"):
		var opened := _start_test_map(new_state, int(config.start_year))
		if not opened.ok:
			return opened
	new_state.make_checkpoint("起点", "initial")
	_adopt_state(new_state)
	_snapshot_id = ""
	_snapshot_name = ""
	if RelicPilot.expanded(_manifest_id):
		for event in step.events:
			if event.type == &"relic_triggered" and RelicPilot.is_rx(event.source_id):
				pilot_events.append(event)
	notice = ""
	return GameResult.success(state.core_snapshot())


func view() -> Dictionary:
	if state == null:
		return {"screen": "closed"}
	var battle_view: Dictionary = {}
	if view_builder.is_valid() and state.battle != null:
		var built: Variant = view_builder.call(state.battle)
		if typeof(built) == TYPE_DICTIONARY:
			battle_view = built
	if state.battle != null:
		battle_view["draw_order"] = state.battle.zones.get("draw", []).duplicate()
		battle_view["source_count"] = state.battle.source_registry.size()
		battle_view["relics"] = state.battle.relics.duplicate()
		battle_view["relic_details"] = {}
		for id in state.battle.relics:
			var definition := catalog.get_definition("relic", str(id))
			if definition.ok:
				battle_view.relic_details[str(id)] = definition.data.duplicate(true)
		battle_view["counters"] = state.battle.counters.duplicate(true)
		battle_view["exam_flags"] = state.battle.exam_flags.duplicate()
		var chapter_cards: Array[Dictionary] = []
		if typeof(state.battle.v3) == TYPE_DICTIONARY and typeof(state.battle.v3.get("paper")) == TYPE_DICTIONARY:
			for entry in state.battle.v3.paper.get("chapters", []):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var card_id := str(entry.get("card_id", ""))
				var card: Dictionary = state.battle.card_by_id.get(card_id, {})
				chapter_cards.append(
					{
						"card_id": card_id,
						"definition_id": str(card.get("definition_id", entry.get("definition_id", ""))),
						"upgrade_level": int(card.get("upgrade_level", 0)),
					}
				)
		battle_view["chapter_cards"] = chapter_cards
		var counts: Dictionary = battle_view.get("zone_counts", {}).duplicate(true)
		counts["chapter"] = chapter_cards.size()
		battle_view["zone_counts"] = counts
	var checkpoints: Array[Dictionary] = []
	for checkpoint in state.checkpoints:
		checkpoints.append(
			{
				"id": str(checkpoint.get("id", "")),
				"label": str(checkpoint.get("label", "")),
				"kind": str(checkpoint.get("kind", "")),
				"revision": int(checkpoint.get("revision", 0)),
				"round_index": int(checkpoint.get("round_index", 0)),
			}
		)
	var run_view := RunService.new(catalog).make_view(state.run) if state.run != null else {}
	var screen := "test_room_battle"
	if state.run != null and not state.run.outcome.is_empty():
		run_view["terminal_summary"] = state.result.get("run_summary", {})
		screen = "test_room_campus"
	elif not str(state.result.get("outcome", "")).is_empty():
		screen = "test_room_result"
	elif _in_campus_room(state):
		screen = "test_room_campus"
	return {
		"run": run_view,
		"nodes": _jump_options(),
		"screen": screen,
		"test": {
			"test_id": state.test_id,
			"branch_id": state.branch_id,
			"revision": state.revision,
			"attempt": state.attempt,
			"paused": state.paused,
			"editing": state.editing,
			"interventions": state.interventions,
			"dirty": state.dirty,
			"player_locks": state.player_locks.duplicate(true),
			"pending_turn": state.pending_turn.duplicate(true),
		},
		"config": state.config.duplicate(true),
		"battle": battle_view,
		"pending_choice": TestRoomState.choice_to_dictionary(state.pending_choice),
		"rng": state.rng.duplicate(true),
		"overlay": state.overlay.summary(),
		"switches": state.switches.duplicate(true),
		"checkpoints": checkpoints,
		"history": {
			"can_undo": not state.undo_stack.is_empty(),
			"can_redo": not state.redo_stack.is_empty(),
			"undo_scope": state.undo_stack.size(),
		},
		"result": state.result.duplicate(true),
		"journal_size": state.journal.size(),
		"files": {
			"presets": store.list("preset"),
			"snapshots": store.list("snapshot"),
			"records": store.list("record"),
		},
		"notice": notice,
	}


func _generate_map(source: ContentDB, seed: String, character_id: String) -> GameResult:
	var created := RunService.new(source).create({"manifest_id": _manifest_id, "seed": seed, "character_id": character_id})
	if not created.ok:
		return created
	var step: RunStep = created.data
	var generated := _extend_maps(step.state, 4)
	return created if generated.ok else generated


func _extend_maps(run: RunState, last_year: int) -> GameResult:
	var saved_term := run.term
	var saved_pending: Dictionary = run.campaign.pending
	run.campaign.pending = {}
	for year in range(run.campaign.years.size() + 1, last_year + 1):
		run.term = year
		var generated := CampaignProgression.ensure_year(run)
		if not generated.ok:
			run.term = saved_term
			run.campaign.pending = saved_pending
			return generated
	run.term = saved_term
	run.campaign.pending = saved_pending
	return GameResult.success(true)


func node_options(seed: String) -> Array[Dictionary]:
	if seed == _node_cache_seed and not _node_cache.is_empty():
		return _node_cache.duplicate(true)
	var source := base_catalog
	if source == null:
		source = ContentDB.new(MANIFEST_ROOT)
		if not source.load(_manifest_id).ok:
			return []
	var generated := _generate_map(source, seed, "P01")
	if not generated.ok:
		return []
	_node_cache_seed = seed
	_node_cache = _map_nodes(generated.data.state)
	return _node_cache.duplicate(true)


func _jump_options() -> Array[Dictionary]:
	if state.run == null:
		return node_options(state.seed)
	var rows := _map_nodes(state.run)
	var campaign := state.run.campaign
	var generated_years: int = campaign.years.size()
	if generated_years == 4:
		return rows
	# The picker can preview future years without committing them to the run.
	var key := JSON.stringify([campaign.root_seed, campaign.map_version, generated_years,
		campaign.summaries, campaign.history])
	if _projected_map_key != key:
		var probe := state.run.copy_for_write()
		var projected := _extend_maps(probe, 4)
		if not projected.ok:
			return rows
		_projected_nodes = _map_nodes(probe).filter(func(node): return node.year > generated_years)
		_projected_map_key = key
	rows.append_array(_projected_nodes.duplicate(true))
	return rows


func _map_nodes(run: RunState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for node in run.nodes:
		var meta := CampaignProgression.metadata(run, node.node_id)
		var key := node.node_id.get_slice("|", 1)
		rows.append({
			"key": key, "node_id": key, "year": node.term, "term": node.term,
			"layer": node.layer, "kind": node.kind,
			"column": int(meta.get("column", 3)), "status": node.status,
			"next_ids": node.next_ids.map(func(id): return str(id).get_slice("|", 1)),
			"title": str(meta.get("title", node.kind)),
			"subtype": str(meta.get("subtype", "")),
		})
	return rows


func _in_campus_room(working: TestRoomState) -> bool:
	return working.run != null and working.run.active_battle_id.is_empty()


func _ensure_test_run(working: TestRoomState, wrapped: TestContent) -> GameResult:
	if working.run == null:
		var generated := _generate_map(wrapped, working.seed, working.battle.character_id)
		if not generated.ok:
			return generated
		var initial: RunStep = generated.data
		working.run = initial.state
		working.run_rng = initial.rng_states
		working.run.cards.clear()
		var service := RunService.new(wrapped)
		for card in working.config.cards:
			var added := service.transactions().add_card(working.run, str(card.definition_id), "starter")
			added.upgrade_level = int(card.get("upgrade_level", 0))
		for index in working.battle.relics.size():
			var added := service.transactions().add_relic(working.run, working.battle.relics[index], "", working.run.relics.size())
			working.relic_origins[index] = str(added.relic_id)
		working.run.vitality = int(working.battle.player.vitality)
		working.run.max_vitality = int(working.battle.player.max_vitality)
	return GameResult.success(true)


func _start_test_map(working: TestRoomState, year: int) -> GameResult:
	var wrapped := TestContent.new(base_catalog, working.overlay)
	wrapped.battle_switches = working.switches
	var initialized := _ensure_test_run(working, wrapped)
	if not initialized.ok:
		return initialized
	working.run.term = year
	working.config["node_key"] = ""
	working.pending_choice = null
	return GameResult.success(true)


func _enter_test_node(working: TestRoomState, node_key: String) -> GameResult:
	var wrapped := TestContent.new(base_catalog, working.overlay)
	if working.run == null:
		working.switches = _default_switches(working.config.get("switches", {}))
	wrapped.battle_switches = working.switches
	if working.run != null and not _in_campus_room(working):
		working.run.vitality = int(working.battle.player.vitality)
		working.run_rng = working.rng.duplicate(true)
	var initialized := _ensure_test_run(working, wrapped)
	if not initialized.ok:
		return initialized
	var service := RunService.new(wrapped)
	var generated := _extend_maps(working.run, 4)
	if not generated.ok:
		return generated
	var entered := service.enter_test_node(working.run, working.run.run_id + "|" + node_key, working.run_rng)
	if not entered.ok:
		return entered
	working.config["node_key"] = node_key
	return _apply_run_step(working, entered.data, BattleEngine.new(wrapped))


func _apply_run_step(working: TestRoomState, step: RunStep, battle_engine: BattleEngine) -> GameResult:
	var events := step.events.duplicate()
	working.run = step.state
	working.run_rng = step.rng_states.duplicate(true)
	working.pending_choice = null
	working.pending_turn.clear()
	working.result = {"source": "none", "outcome": "", "editable": true}
	if step.battle_input is Dictionary:
		var begun := battle_engine.begin(step.battle_input)
		if not begun.ok:
			return begun
		var battle_step: BattleStep = begun.data
		working.battle = battle_step.state
		working.relic_origins.clear()
		var equipped := working.run.relics.duplicate(true)
		equipped.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
		for relic in equipped:
			working.relic_origins.append(str(relic.relic_id))
		working.rng = battle_step.rng_state.duplicate(true)
		working.pending_choice = TestRoomState.choice_from_dictionary(battle_step.pending_choice)
		events.append_array(battle_step.events)
	else:
		working.battle.player["vitality"] = step.state.vitality
		working.battle.player["max_vitality"] = step.state.max_vitality
		working.battle.player["max_vitality_base"] = step.state.max_vitality
		# Campus rewards/services may replace permanent relics while the previous
		# battle remains as the editor's historical placeholder.
		for index in working.relic_origins.size():
			var origin := working.relic_origins[index]
			if not origin.is_empty() and not working.run.relics.any(func(relic): return str(relic.relic_id) == origin):
				working.relic_origins[index] = ""
	if step.run_summary != null:
		working.result = {"source": "normal", "outcome": step.run_summary.result,
			"editable": true, "run_summary": step.run_summary.to_dictionary()}
	return GameResult.success(events)


func _settle_map_battle(working: TestRoomState, outcome: Dictionary) -> GameResult:
	var settled := RunService.new(TestContent.new(base_catalog, working.overlay)).settle_battle(
		working.run, outcome, working.rng
	)
	if not settled.ok:
		return settled
	return _apply_run_step(working, settled.data, engine)


func _preview_room_action(draft: Dictionary) -> GameResult:
	if state.editing or state.paused:
		return _failure(GameConstants.ERROR_TEST_CHOICE_CONFLICT, "test.action.editing")
	return RunService.new(catalog).preview(state.run, draft)


func _submit_room_action(draft: Dictionary) -> ActionResult:
	if state.paused:
		return _reject(ApiError.new(GameConstants.ERROR_TEST_CHOICE_CONFLICT, "test.action.paused"))
	var working := state.copy()
	if draft.type == "choose_campaign" and working.run.campaign.pending.get("kind") == "grand":
		# Maps prepared for jumping used a projection. At a real year boundary,
		# generate the next year from the completed route and actual choices.
		var year := working.run.term
		working.run.campaign.years.resize(year)
		working.run.nodes = working.run.nodes.filter(func(node): return node.term <= year)
	var applied := RunService.new(catalog).apply(working.run, draft, working.run_rng)
	if not applied.ok:
		return _reject(applied.error)
	var published := _apply_run_step(working, applied.data, engine)
	if not published.ok:
		return _reject(published.error)
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack.clear()
	working.revision += 1
	working.dirty = true
	var before_hash := state.state_hash()
	_adopt_state(working)
	state.make_checkpoint("房间命令 %s" % str(draft.type), "command")
	state.append_journal("command", {"type": str(draft.type)}, before_hash, state.state_hash())
	return _accepted_result(published.data, state.pending_choice == null)


func options() -> Dictionary:
	var loaded := ContentDB.new(MANIFEST_ROOT)
	if not loaded.load(_manifest_id).ok:
		return {"error": "content.load"}
	var info := loaded.get_info()
	var characters: Array[Dictionary] = []
	for id in info.enabled.get("character", []):
		var definition := _definition(loaded, "character", str(id))
		characters.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"starter_cards": definition.get("starter_cards", []).duplicate(),
				"passive_id": str(definition.get("passive", {}).get("id", "")),
			}
		)
	var encounters: Array[Dictionary] = []
	for id in info.enabled.get("encounter", []):
		var definition := _definition(loaded, "encounter", str(id))
		encounters.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"kind": str(definition.get("kind", "")),
				"base_ddl": int(definition.get("base_ddl", 0)),
				"members": definition.get("members", []).duplicate(),
			}
		)
	var cards: Array[Dictionary] = []
	for id in info.enabled.get("card", []):
		var definition := _definition(loaded, "card", str(id))
		cards.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"type": str(definition.get("type", "")),
				"cost": int(definition.get("cost", 0)),
				"rarity": str(definition.get("rarity", "")),
				"owner": str(definition.get("owner", "")),
			}
		)
	var statuses: Array[Dictionary] = []
	for id in info.enabled.get("status", []):
		var definition := _definition(loaded, "status", str(id))
		statuses.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"target": str(definition.get("target", "")),
			}
		)
	var tasks: Array[Dictionary] = []
	for id in info.enabled.get("task", []):
		var definition := _definition(loaded, "task", str(id))
		var phases: Array = definition.get("phases", [])
		var work_max := int((phases[0] as Dictionary).get("work_max", 0)) if not phases.is_empty() else 0
		var phase_list: Array[Dictionary] = []
		for phase in phases:
			phase_list.append(
				{
					"phase_key": str(phase.get("phase_key", "")),
					"work_max": int(phase.get("work_max", 0)),
					"intent_count": (phase.get("intents", []) as Array).size(),
				}
			)
		tasks.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"kind": str(definition.get("kind", "")),
				"work_max": work_max,
				"phases": phase_list,
			}
		)
	var units: Array[Dictionary] = []
	for id in info.enabled.get("unit", []):
		var definition := _definition(loaded, "unit", str(id))
		units.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"vitality": int(definition.get("vitality", 0)),
				"cooperation": int(definition.get("cooperation", 0)),
			}
		)
	var ruleset := _definition(loaded, "ruleset", info.ruleset_id)
	var relics: Array[Dictionary] = []
	for id in info.enabled.get("relic", []):
		var definition := _definition(loaded, "relic", str(id))
		relics.append(
			{
				"id": str(id),
				"name_key": str(definition.get("name_key", id)),
				"rarity": str(definition.get("rarity", "")),
			}
		)
	var switches: Array[Dictionary] = []
	for key in SWITCHES:
		switches.append(
			{"key": key, "description": SWITCHES[key], "default": false}
		)
	var scenes: Array[Dictionary] = []
	for id in info.enabled.get("scene", []):
		var definition := _definition(loaded, "scene", str(id))
		scenes.append({"id": str(id), "name_key": str(definition.get("name_key", id))})
	if state != null and state.overlay != null:
		for id in state.overlay.definitions.get("card", {}):
			if not _has_option(cards, str(id)):
				var definition: Dictionary = state.overlay.definitions.card[id]
				cards.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"type": str(definition.get("type", "")),
						"cost": int(definition.get("cost", 0)),
						"rarity": str(definition.get("rarity", "")),
						"owner": str(definition.get("owner", "")),
					}
				)
		for id in state.overlay.definitions.get("task", {}):
			if not _has_option(tasks, str(id)):
				var definition: Dictionary = state.overlay.definitions.task[id]
				var phases: Array = definition.get("phases", [])
				var phase_list: Array[Dictionary] = []
				for phase in phases:
					phase_list.append(
						{
							"phase_key": str(phase.get("phase_key", "")),
							"work_max": int(phase.get("work_max", 0)),
							"intent_count": (phase.get("intents", []) as Array).size(),
						}
					)
				tasks.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"kind": str(definition.get("kind", "")),
						"work_max": int((phases[0] as Dictionary).get("work_max", 0)) if not phases.is_empty() else 0,
						"phases": phase_list,
					}
				)
		for id in state.overlay.definitions.get("unit", {}):
			if not _has_option(units, str(id)):
				var definition: Dictionary = state.overlay.definitions.unit[id]
				units.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"vitality": int(definition.get("vitality", 0)),
						"cooperation": int(definition.get("cooperation", 0)),
					}
				)
		for id in state.overlay.definitions.get("relic", {}):
			if not _has_option(relics, str(id)):
				var definition: Dictionary = state.overlay.definitions.relic[id]
				relics.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"rarity": str(definition.get("rarity", "")),
					}
				)
		for id in state.overlay.definitions.get("status", {}):
			if not _has_option(statuses, str(id)):
				var definition: Dictionary = state.overlay.definitions.status[id]
				statuses.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"target": str(definition.get("target", "")),
					}
				)
		for id in state.overlay.definitions.get("encounter", {}):
			if not _has_option(encounters, str(id)):
				var definition: Dictionary = state.overlay.definitions.encounter[id]
				encounters.append(
					{
						"id": str(id),
						"name_key": str(definition.get("name_key", id)),
						"kind": str(definition.get("kind", "")),
						"base_ddl": int(definition.get("base_ddl", 0)),
						"members": definition.get("members", []).duplicate(),
					}
				)
		for id in state.overlay.definitions.get("scene", {}):
			if not _has_option(scenes, str(id)):
				var definition: Dictionary = state.overlay.definitions.scene[id]
				scenes.append({"id": str(id), "name_key": str(definition.get("name_key", id))})
	return {
		"manifest_id": info.id,
		"content_version": info.content_version,
		"content_hash": info.content_hash,
		"ruleset_id": info.ruleset_id,
		"characters": characters,
		"encounters": encounters,
		"cards": cards,
		"tasks": tasks,
		"units": units,
		"relics": relics,
		"statuses": statuses,
		"scenes": scenes,
		"ruleset": ruleset,
		"switches": switches,
		"limits": LIMITS.duplicate(true),
	}


func _has_option(entries: Array, id: String) -> bool:
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == id:
			return true
	return false


func begin_edit(context: Variant) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	state.editing = true
	return _accepted_result([], true)


func cancel_edit(context: Variant) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	state.editing = false
	return _accepted_result([], true)


func pause(value: bool) -> bool:
	if state == null:
		return false
	state.paused = value
	return true


func _truncate_resolution(working: TestRoomState) -> void:
	var resolution: Dictionary = working.battle.resolution if working.battle.resolution is Dictionary else {}
	var destination := "exhaust" if bool(resolution.get("exhaust", false)) else "discard"
	for id in working.battle.zones.get("resolving", []).duplicate():
		if working.battle.card_by_id.has(id) and not working.battle.zones[destination].has(id):
			working.battle.zones[destination].append(id)
	working.battle.zones["resolving"] = []
	working.battle.resolution = null
	working.pending_choice = null
	if working.battle.phase == "awaiting_choice":
		working.battle.phase = "player_action"


func _prepare_patch(patch: Dictionary) -> GameResult:
	var policy := str(patch.get("resolution_policy", "rollback"))
	var changes_node: bool = patch.ops.any(func(entry): return entry.op == "enter_node")
	var working := state.copy()
	if state.pending_choice != null:
		if policy not in ["rollback", "truncate"]:
			return GameResult.failure(ApiError.new(GameConstants.ERROR_TEST_CHOICE_CONFLICT, "test.choice.policy", {"policy": policy}))
		if not changes_node and policy == "rollback":
			if state.undo_stack.is_empty():
				return GameResult.failure(ApiError.new(GameConstants.ERROR_TEST_CHECKPOINT_INVALID, "test.choice.no_checkpoint"))
			var entry: Dictionary = state.undo_stack.back()
			working = TestRoomState.from_core(entry.core)
			working.journal.assign(entry.get("journal", state.journal.slice(0, int(entry.journal_size))))
			working.switches = state.switches.duplicate(true)
			working.overlay = state.overlay.copy()
			working.checkpoints.assign(state.checkpoints.duplicate(true))
		if not changes_node:
			_truncate_resolution(working)
			if policy == "truncate":
				working.result = {"source": "truncated", "outcome": "", "editable": true}
	var summary: Array[Dictionary] = []
	for index in patch.ops.size():
		var op_error := _apply_op(working, patch.ops[index], summary)
		if op_error != null:
			op_error.details["path"] = "ops[%d]" % index
			return GameResult.failure(op_error)
	var issues := _validate_structure(working)
	issues.append_array(ROOM_VALIDATOR.validate_state(working, base_catalog))
	if not issues.is_empty():
		return GameResult.failure(ApiError.new(GameConstants.ERROR_TEST_STRUCTURE_INVALID, "test.patch.structure", {"issues": issues}))
	if bool(state.switches.get("freeze_outcome", false)) and not bool(working.switches.get("freeze_outcome", false)):
		var judge_error := _judge_now(working, working.emitted_events)
		if judge_error != null:
			return GameResult.failure(judge_error)
	var only_switches: bool = patch.ops.all(func(entry): return str(entry.get("op", "")) == "set_switch")
	if not only_switches:
		var switch_error := _enforce_switches(working)
		if switch_error != null:
			return GameResult.failure(switch_error)
	return GameResult.success({"working": working, "summary": summary})


func preview_patch(context: Variant, patch_value: Variant) -> GameResult:
	var error := _check_context(context)
	if error == null:
		error = _validate_patch(patch_value)
	if error != null:
		return GameResult.failure(error)
	var preview := ActionPreview.new()
	preview.revision = state.revision
	var prepared := _prepare_patch(patch_value)
	if prepared.ok:
		preview.can_submit = true
		preview.known_effects = prepared.data.summary
	else:
		preview.blocking_errors.append(prepared.error)
	return GameResult.success(preview)


func apply_patch(context: Variant, patch_value: Variant) -> ActionResult:
	var error := _check_context(context)
	if error == null:
		error = _validate_patch(patch_value)
	if error != null:
		return _reject(error)
	var patch: Dictionary = patch_value
	var prepared := _prepare_patch(patch)
	if not prepared.ok:
		return _reject(prepared.error)
	return _commit_patch(patch, prepared.data)


func _commit_patch(patch: Dictionary, prepared: Dictionary) -> ActionResult:
	var working: TestRoomState = prepared.working
	var events := working.emitted_events.duplicate()
	working.emitted_events.clear()
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack = []
	if state.pending_choice != null:
		working.branch_id = state.branch_id + 1
		working.revision = 0
	else:
		working.branch_id = state.branch_id
		working.revision = state.revision + 1
	working.editing = state.editing
	working.dirty = true
	working.interventions = state.interventions + patch.ops.size()
	var before_hash := state.state_hash()
	_adopt_state(working)
	state.make_checkpoint("编辑 %d 项" % patch.ops.size(), "edit")
	state.append_journal("edit", {"ops": patch.ops.duplicate(true), "policy": str(patch.get("resolution_policy", "rollback"))}, before_hash, state.state_hash())
	notice = "已应用 %d 项" % patch.ops.size()
	return _accepted_result(events, state.pending_choice == null)


func preview_action(context: Variant, draft_value: Variant) -> GameResult:
	var error := _check_context(context)
	if error != null:
		return GameResult.failure(error)
	if typeof(draft_value) != TYPE_DICTIONARY:
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.action.invalid")
	var draft: Dictionary = draft_value
	var action_type := StringName(draft.get("type", ""))
	if _in_campus_room(state) and ROOM_ACTIONS.has(action_type):
		return _preview_room_action(draft)
	if _in_campus_room(state) or not BATTLE_ACTIONS.has(action_type):
		return _failure(
			GameConstants.ERROR_INVALID_ARGUMENT,
			"test.action.unsupported",
			{"type": String(action_type)}
		)
	if state.editing:
		return _failure(GameConstants.ERROR_TEST_CHOICE_CONFLICT, "test.action.editing")
	if state.pending_choice != null and action_type != &"confirm_choice":
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending")
	if action_type in BATTLE_ACTIONS and action_type != &"play_card":
		# Mirror the live session: non-play actions are validated by applying to a copy.
		var checked := engine.apply(
			state.battle, ActionDraft.new(action_type, draft.get("payload", {})), state.rng
		)
		var preview := ActionPreview.new()
		preview.can_submit = checked.ok
		if not checked.ok:
			preview.blocking_errors.append(checked.error)
		return GameResult.success(preview)
	return engine.preview(state.battle, ActionDraft.new(action_type, draft.get("payload", {})))


func submit_action(context: Variant, draft_value: Variant) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	if state.editing:
		return _reject(
			ApiError.new(
				GameConstants.ERROR_TEST_CHOICE_CONFLICT,
				"test.action.editing",
				{"test_id": state.test_id}
			)
		)
	if typeof(draft_value) != TYPE_DICTIONARY:
		return _reject(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "test.action.invalid"))
	var draft: Dictionary = draft_value
	var action_type := StringName(draft.get("type", ""))
	if _in_campus_room(state) and ROOM_ACTIONS.has(action_type):
		return _submit_room_action(draft)
	if _in_campus_room(state) or not BATTLE_ACTIONS.has(action_type):
		return _reject(
			ApiError.new(
				GameConstants.ERROR_INVALID_ARGUMENT,
				"test.action.unsupported",
				{"type": String(action_type)}
			)
		)
	if state.pending_choice != null and action_type != &"confirm_choice":
		return _reject(ApiError.new(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending"))
	var payload: Variant = draft.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return _reject(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "test.action.payload"))
	var working := state.copy()
	if action_type == &"end_turn" and bool(working.switches.get("manual_rule_steps", false)):
		var checked := engine.apply(working.battle, ActionDraft.new(action_type, payload), working.rng)
		if not checked.ok:
			return _reject(checked.error)
		working.pending_turn = payload.duplicate(true)
		working.battle.phase = "enemy_turn"
		working.revision += 1
		working.dirty = true
		_push_undo(state)
		working.undo_stack.assign(state.undo_stack.duplicate(true))
		working.redo_stack.clear()
		var before := state.state_hash()
		_adopt_state(working)
		state.append_journal("deferred_turn", {"payload": payload.duplicate(true)}, before, state.state_hash())
		notice = "回合已暂停，请在时间随机页执行一次真实规则步骤"
		return _accepted_result([], true)
	var applied := _execute_rule(working, "", {}, ActionDraft.new(action_type, payload))
	if not applied.ok:
		return _reject(applied.error)
	var step: BattleStep = applied.data
	var events := step.events.duplicate()
	working.battle = step.state
	working.rng = step.rng_state.duplicate(true)
	working.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
	working.revision += 1
	working.dirty = true
	if step.outcome != null:
		if working.run != null:
			var settled := _settle_map_battle(working, step.outcome)
			if not settled.ok:
				return _reject(settled.error)
			events.append_array(settled.data)
		else:
			working.result = {"source": "normal", "outcome": str(step.outcome.result), "editable": true}
	if step.outcome == null and working.player_locks.has("vitality"):
		var judge_error := _judge_now(working, events)
		if judge_error != null:
			return _reject(judge_error)
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack.clear()
	var before_hash := state.state_hash()
	_adopt_state(working)
	state.make_checkpoint("命令 %s" % String(action_type), "command")
	state.append_journal(
		"command",
		{"type": String(action_type), "payload": payload.duplicate(true), "events": events.size()},
		before_hash,
		state.state_hash()
	)
	return _accepted_result(events, state.pending_choice == null)


func restore_checkpoint(context: Variant, checkpoint_id: String) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	var found: Variant = null
	for checkpoint in state.checkpoints:
		if str(checkpoint.get("id", "")) == checkpoint_id:
			found = checkpoint
			break
	if found == null:
		return _reject(
			ApiError.new(
				GameConstants.ERROR_TEST_CHECKPOINT_INVALID,
				"test.checkpoint.missing",
				{"checkpoint_id": checkpoint_id}
			)
		)
	var core: Dictionary = found.state
	var restored := TestRoomState.from_core(core)
	restored.journal.assign(state.journal.duplicate(true))
	restored.checkpoints.assign(state.checkpoints.duplicate(true))
	restored.undo_stack.assign(state.undo_stack.duplicate(true))
	restored.redo_stack.assign(state.redo_stack.duplicate(true))
	restored.branch_id = state.branch_id + 1
	restored.revision = 0
	restored.editing = state.editing
	restored.dirty = true
	var before_hash := state.state_hash()
	_adopt_state(restored)
	state.append_journal(
		"restore", {"checkpoint_id": checkpoint_id}, before_hash, state.state_hash()
	)
	return _accepted_result([], true)


func step_history(context: Variant, direction: String) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	if direction == "undo":
		if state.undo_stack.is_empty():
			return _reject(
				ApiError.new(GameConstants.ERROR_TEST_CHECKPOINT_INVALID, "test.history.empty")
			)
		var entry: Dictionary = state.undo_stack.pop_back()
		state.redo_stack.append(
			{"core": state.core_snapshot(), "journal_size": state.journal.size(), "journal": state.journal.duplicate(true)}
		)
		var restored := TestRoomState.from_core(entry.core)
		restored.journal.assign(entry.get("journal", state.journal.slice(0, int(entry.journal_size))))
		restored.checkpoints.assign(state.checkpoints.duplicate(true))
		restored.undo_stack.assign(state.undo_stack.duplicate(true))
		restored.redo_stack.assign(state.redo_stack.duplicate(true))
		restored.branch_id = state.branch_id + 1
		restored.revision = 0
		restored.editing = state.editing
		restored.dirty = true
		_adopt_state(restored)
		return _accepted_result([], true)
	if direction == "redo":
		if state.redo_stack.is_empty():
			return _reject(
				ApiError.new(GameConstants.ERROR_TEST_CHECKPOINT_INVALID, "test.history.empty")
			)
		var entry: Dictionary = state.redo_stack.pop_back()
		state.undo_stack.append(
			{"core": state.core_snapshot(), "journal_size": state.journal.size(), "journal": state.journal.duplicate(true)}
		)
		var restored := TestRoomState.from_core(entry.core)
		restored.journal.assign(entry.get("journal", state.journal.slice(0, int(entry.journal_size))))
		restored.checkpoints.assign(state.checkpoints.duplicate(true))
		restored.undo_stack.assign(state.undo_stack.duplicate(true))
		restored.redo_stack.assign(state.redo_stack.duplicate(true))
		restored.branch_id = state.branch_id + 1
		restored.revision = 0
		restored.editing = state.editing
		restored.dirty = true
		_adopt_state(restored)
		return _accepted_result([], true)
	return _reject(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "test.history.direction"))


func set_outcome(context: Variant, value: String) -> ActionResult:
	var patch := {
		"schema_version": 1,
		"test_id": str(context.get("test_id", "")) if typeof(context) == TYPE_DICTIONARY else "",
		"branch_id": int(context.get("branch_id", 0)) if typeof(context) == TYPE_DICTIONARY else 0,
		"expected_revision": (
			int(context.get("expected_revision", 0)) if typeof(context) == TYPE_DICTIONARY else 0
		),
		"ops": [{"op": "set_outcome", "result": value}],
	}
	return apply_patch(context, patch)


func restart(context: Variant, origin: String, seed_mode: String, seed: String = "") -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	if origin not in ["initial", "current"]:
		return _reject(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "test.restart.origin"))
	if seed_mode not in ["same", "new"] or (seed_mode == "new" and seed.is_empty()):
		return _reject(ApiError.new(GameConstants.ERROR_INVALID_ARGUMENT, "test.restart.seed"))
	if origin == "initial" or (state.run != null and not state.run.outcome.is_empty()):
		var config := state.config.duplicate(true)
		if seed_mode == "new" and not seed.is_empty():
			config["seed"] = seed
		var overlay := state.overlay.to_dictionary()
		config["overlay"] = overlay
		config["switches"] = state.switches.duplicate(true)
		var original := state
		var original_catalog := catalog
		var original_base := base_catalog
		var original_engine := engine
		var original_snapshot_id := _snapshot_id
		var original_snapshot_name := _snapshot_name
		state = null
		var started := start(config)
		if not started.ok:
			state = original
			catalog = original_catalog
			base_catalog = original_base
			engine = original_engine
			return _reject(started.error)
		_snapshot_id = original_snapshot_id
		_snapshot_name = original_snapshot_name
		return _accepted_result([], true)
	var working := state.copy()
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack = []
	working.branch_id = state.branch_id + 1
	working.revision = 0
	working.attempt = state.attempt + 1
	working.pending_choice = null
	working.pending_turn.clear()
	_truncate_resolution(working)
	working.battle.outcome = null
	working.battle.phase = "player_action"
	working.result = {"source": "none", "outcome": "", "editable": true}
	working.paused = false
	working.editing = false
	working.dirty = true
	if seed_mode == "new" and not seed.is_empty():
		var rng := RandomSource.new(seed)
		working.rng = rng.export_state().to_dictionary()
		working.seed = seed
	_adopt_state(working)
	return _accepted_result([], true)


func close() -> void:
	state = null
	catalog = null
	base_catalog = null
	engine = null
	notice = ""
	_snapshot_id = ""
	_snapshot_name = ""


func save_preset(name: String) -> GameResult:
	if state == null:
		return _failure(GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE, "test.room.inactive")
	if state.pending_choice != null:
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "test.save.pending")
	var id := "preset-%s" % _stamp()
	return store.save(
		"preset",
		id,
		name,
		{
			"config": state.config.duplicate(true),
			"overlay": state.overlay.to_dictionary(),
			"switches": state.switches.duplicate(true),
			"seed": state.seed,
		}
	)


func save_snapshot(name: String) -> GameResult:
	if state == null:
		return _failure(GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE, "test.room.inactive")
	if state.pending_choice != null:
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "test.save.pending")
	var id := _snapshot_id if not _snapshot_id.is_empty() else "snapshot-%s" % _stamp()
	var snapshot_name := _snapshot_name if not _snapshot_id.is_empty() else name
	var saved := store.save(
		"snapshot",
		id,
		snapshot_name,
		{
			"core": state.core_snapshot(),
			"journal": state.journal.duplicate(true),
			"attempt": state.attempt,
			"compatibility": _compatibility_metadata(),
		}
	)
	if saved.ok:
		_snapshot_id = id
		_snapshot_name = snapshot_name
		state.dirty = false
	return saved


func save_record(name: String) -> GameResult:
	if state == null:
		return _failure(GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE, "test.room.inactive")
	if state.pending_choice != null:
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "test.save.pending")
	var id := "record-%s" % _stamp()
	return store.save(
		"record",
		id,
		name,
		{
			"core": state.core_snapshot(),
			"journal": state.journal.duplicate(true),
			"state_hash": state.state_hash(),
			"hash_version": 3,
			"journal_hash": SnapshotCodec.canonical_json(state.journal).sha256_text(),
			"compatibility": _compatibility_metadata(),
			"engine_version": GameConstants.GODOT_VERSION,
			"overlay_hash": state.overlay.hash,
		}
	)


func list_files(kind: String) -> Array[Dictionary]:
	return store.list(kind)


func delete_snapshot(snapshot_id: String) -> GameResult:
	return store.remove("snapshot", snapshot_id)


func load_preset(preset_id: String) -> ActionResult:
	if state != null:
		return _reject(
			ApiError.new(GameConstants.ERROR_TEST_CONTEXT_MISMATCH, "test.room.active")
		)
	var loaded := store.load_file("preset", preset_id)
	if not loaded.ok:
		return _reject(loaded.error)
	var payload: Dictionary = loaded.data.payload
	var config: Variant = payload.get("config", {})
	if typeof(config) != TYPE_DICTIONARY:
		return _reject(
			ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload")
		)
	var merged := (config as Dictionary).duplicate(true)
	merged["overlay"] = payload.get("overlay", {})
	merged["switches"] = payload.get("switches", {})
	var started := start(merged)
	if not started.ok:
		return _reject(started.error)
	return _accepted_result([], true)


func save_snapshot_with_patch(context: Variant, patch_value: Variant, name: String) -> GameResult:
	var error := _check_context(context)
	if error == null:
		error = _validate_patch(patch_value, true)
	if error != null:
		return GameResult.failure(error)
	var patch: Dictionary = patch_value
	var original := state.copy()
	var original_id := _snapshot_id
	var original_name := _snapshot_name
	var original_notice := notice
	if not patch.ops.is_empty() or state.pending_choice != null:
		var prepared := _prepare_patch(patch)
		if not prepared.ok:
			return prepared
		_commit_patch(patch, prepared.data)
	var saved := save_snapshot(name)
	if not saved.ok:
		_adopt_state(original)
		_snapshot_id = original_id
		_snapshot_name = original_name
		notice = original_notice
	return saved


func load_snapshot(snapshot_id: String) -> ActionResult:
	if state != null:
		return _reject(
			ApiError.new(GameConstants.ERROR_TEST_CONTEXT_MISMATCH, "test.room.active")
		)
	var loaded := store.load_file("snapshot", snapshot_id)
	if not loaded.ok:
		return _reject(loaded.error)
	var payload: Dictionary = loaded.data.payload
	var core: Variant = payload.get("core", {})
	if typeof(core) != TYPE_DICTIONARY:
		return _reject(ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload"))
	var loaded_catalog := ContentDB.new(MANIFEST_ROOT)
	var loaded_ok := loaded_catalog.load(_manifest_id)
	if not loaded_ok.ok:
		return _reject(loaded_ok.error)
	var core_issues := ROOM_VALIDATOR.validate_core(core, loaded_catalog)
	if not core_issues.is_empty():
		return _reject(ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload", {"issues": core_issues}))
	var file_error := _payload_error(payload, loaded_catalog, false)
	if file_error != null:
		return _reject(file_error)
	var restored := TestRoomState.from_core(core)
	restored.editing = false
	var relic_error := _restored_relic_error(restored)
	if relic_error != null:
		return _reject(relic_error)
	restored.branch_id = int(core.get("branch_id", 0)) + 1
	restored.revision = 0
	restored.journal.assign(payload.get("journal", []).duplicate(true))
	restored.checkpoints = []
	var upgraded := _recover_old_map_battle(restored, loaded_catalog)
	if not upgraded.ok:
		return _reject(upgraded.error)
	restored.checkpoints.append(
		{
			"id": "cp-1",
			"label": "载入快照",
			"kind": "initial",
			"revision": 0,
			"branch_id": restored.branch_id,
			"round_index": restored.battle.round_index if restored.battle != null else 0,
			"state": restored.core_snapshot(),
		}
	)
	base_catalog = loaded_catalog
	catalog = TestContent.new(loaded_catalog, restored.overlay)
	engine = BattleEngine.new(catalog)
	_adopt_state(restored)
	_snapshot_id = snapshot_id
	_snapshot_name = str(loaded.data.name)
	return _accepted_result([], true)


func _compatibility_metadata(source: ContentDB = null) -> Dictionary:
	var info := (base_catalog if source == null else source).get_info()
	return {"manifest_id": info.id, "content_version": info.content_version,
		"content_hash": info.content_hash, "ruleset_id": info.ruleset_id,
		"rng_version": GameConstants.RANDOM_ALGORITHM_VERSION}


func _payload_error(payload: Dictionary, source: ContentDB, record: bool) -> ApiError:
	if payload.has("compatibility"):
		if not payload.compatibility is Dictionary or SnapshotCodec.canonical_json(payload.compatibility) != SnapshotCodec.canonical_json(_compatibility_metadata(source)):
			return ApiError.new(GameConstants.ERROR_VERSION_MISMATCH, "test.file.content_version")
	var journal: Variant = payload.get("journal", [])
	if not journal is Array:
		return ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.journal")
	for entry in journal:
		if not entry is Dictionary or not entry.get("summary") is Dictionary or not entry.get("kind") is String:
			return ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.journal")
	if not record:
		return null
	if str(payload.get("engine_version", "")) != GameConstants.GODOT_VERSION:
		return ApiError.new(GameConstants.ERROR_VERSION_MISMATCH, "test.record.engine_version")
	var hash_version: Variant = payload.get("hash_version", 1)
	if not (hash_version is int or hash_version is float) or floor(float(hash_version)) != float(hash_version) or int(hash_version) not in [1, 2, 3]:
		return ApiError.new(GameConstants.ERROR_VERSION_MISMATCH, "test.record.hash_version")
	var restored := TestRoomState.from_core(payload.core)
	if str(payload.get("state_hash", "")) != restored.state_hash(int(hash_version)) or str(payload.get("overlay_hash", "")) != restored.overlay.hash:
		return ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.record.hash")
	if int(hash_version) >= 2 and str(payload.get("journal_hash", "")) != SnapshotCodec.canonical_json(journal).sha256_text():
		return ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.record.journal_hash")
	return null


func load_record(record_id: String) -> ActionResult:
	if state != null:
		return _reject(
			ApiError.new(GameConstants.ERROR_TEST_CONTEXT_MISMATCH, "test.room.active")
		)
	var loaded := store.load_file("record", record_id)
	if not loaded.ok:
		return _reject(loaded.error)
	var payload: Dictionary = loaded.data.payload
	var core: Variant = payload.get("core", {})
	if typeof(core) != TYPE_DICTIONARY:
		return _reject(ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload"))
	var loaded_catalog := ContentDB.new(MANIFEST_ROOT)
	var loaded_ok := loaded_catalog.load(_manifest_id)
	if not loaded_ok.ok:
		return _reject(loaded_ok.error)
	var core_issues := ROOM_VALIDATOR.validate_core(core, loaded_catalog)
	if not core_issues.is_empty():
		return _reject(ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.payload", {"issues": core_issues}))
	var file_error := _payload_error(payload, loaded_catalog, true)
	if file_error != null:
		return _reject(file_error)
	var restored := TestRoomState.from_core(core)
	restored.editing = false
	var relic_error := _restored_relic_error(restored)
	if relic_error != null:
		return _reject(relic_error)
	restored.branch_id = 0
	restored.revision = 0
	restored.journal.assign(payload.get("journal", []).duplicate(true))
	restored.checkpoints = []
	var upgraded := _recover_old_map_battle(restored, loaded_catalog)
	if not upgraded.ok:
		return _reject(upgraded.error)
	restored.checkpoints.append(
		{
			"id": "cp-1",
			"label": "载入记录",
			"kind": "initial",
			"revision": 0,
			"branch_id": 0,
			"round_index": restored.battle.round_index if restored.battle != null else 0,
			"state": restored.core_snapshot(),
		}
	)
	base_catalog = loaded_catalog
	catalog = TestContent.new(loaded_catalog, restored.overlay)
	engine = BattleEngine.new(catalog)
	_adopt_state(restored)
	_snapshot_id = ""
	_snapshot_name = ""
	return _accepted_result([], true)


func _recover_old_map_battle(restored: TestRoomState, source: ContentDB) -> GameResult:
	if restored.run == null or restored.battle == null or restored.config.has("switches"):
		return GameResult.success(true)
	var overrides := {}
	for key in SWITCHES:
		if restored.switches.get(key, FREE_SWITCHES.has(key)) != FREE_SWITCHES.has(key):
			overrides[key] = restored.switches[key]
	restored.config["switches"] = overrides
	restored.switches = _default_switches(overrides)
	if restored.run.active_battle_id.is_empty() or not restored.battle.outcome is Dictionary:
		return GameResult.success(true)
	var wrapped := TestContent.new(source, restored.overlay)
	var outcome: Dictionary = RunCodec.normalize_numbers(restored.battle.outcome)
	var settled := RunService.new(wrapped).settle_battle(restored.run, outcome, restored.rng)
	return _apply_run_step(restored, settled.data, null) if settled.ok else settled


func _restored_relic_error(restored: TestRoomState) -> ApiError:
	if not RelicPilot.expanded(_manifest_id):
		return null
	var ids: Array = restored.overlay.definitions.get("relic", {}).keys()
	if restored.config.get("relics") is Array:
		ids.append_array(restored.config.relics)
	if restored.battle != null:
		ids.append_array(restored.battle.relics)
		for source in restored.battle.source_registry.values():
			if source is Dictionary and source.get("kind") == "relic":
				ids.append(source.get("definition_id"))
	for id in ids:
		if RelicPilot.is_retired(str(id)):
			return ApiError.new(GameConstants.ERROR_TEST_FILE_INVALID, "test.file.retired_relic")
	return null


func _adopt_state(value: TestRoomState) -> void:
	state = value
	if catalog is TestContent:
		(catalog as TestContent).overlay = state.overlay
		(catalog as TestContent).battle_switches = state.switches.duplicate(true)


func _check_context(context: Variant) -> ApiError:
	if state == null:
		return ApiError.new(GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE, "test.room.inactive")
	if typeof(context) != TYPE_DICTIONARY:
		return ApiError.new(GameConstants.ERROR_TEST_CONTEXT_MISMATCH, "test.context.invalid")
	var test_id := str(context.get("test_id", ""))
	var branch_id := int(context.get("branch_id", -1))
	var expected_revision := int(context.get("expected_revision", -1))
	if test_id != state.test_id or branch_id != state.branch_id:
		return ApiError.new(
			GameConstants.ERROR_TEST_CONTEXT_MISMATCH,
			"test.context.mismatch",
			{"test_id": state.test_id, "branch_id": state.branch_id}
		)
	if expected_revision != state.revision:
		return ApiError.new(
			GameConstants.ERROR_STALE_STATE,
			"test.context.stale",
			{"expected_revision": state.revision}
		)
	return null


func _validate_patch(value: Variant, allow_empty: bool = false) -> ApiError:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid_patch("test.patch.invalid")
	var patch: Dictionary = value
	for key in patch:
		if not PATCH_KEYS.has(key):
			return _invalid_patch("test.patch.unknown_key", {"key": str(key)})
	if int(patch.get("schema_version", 1)) != 1:
		return _invalid_patch("test.patch.schema", {"schema_version": patch.get("schema_version")})
	var ops: Variant = patch.get("ops", [])
	if typeof(ops) != TYPE_ARRAY or (ops.is_empty() and not allow_empty) or ops.size() > LIMITS.ops:
		return _invalid_patch("test.patch.ops", {"size": 0 if typeof(ops) != TYPE_ARRAY else ops.size()})
	for index in ops.size():
		var op: Variant = ops[index]
		if typeof(op) != TYPE_DICTIONARY:
			return _invalid_patch("test.patch.op_invalid", {"path": "ops[%d]" % index})
		var name := str(op.get("op", ""))
		if not OP_KEYS.has(name):
			return _invalid_patch("test.patch.unknown_op", {"op": name, "path": "ops[%d]" % index})
		for key in op:
			if not OP_KEYS[name].has(str(key)):
				return _invalid_patch(
					"test.patch.unknown_field",
					{"op": name, "field": str(key), "path": "ops[%d]" % index}
				)
	var policy := str(patch.get("resolution_policy", "rollback"))
	if not (policy in ["rollback", "truncate", "cancel", "stable"]):
		return _invalid_patch("test.patch.policy", {"policy": policy})
	return null


func _apply_op(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var scope := str(op.get("persistence_scope", "battle"))
	if scope not in ["battle", "run"]:
		return _invalid_patch("test.patch.persistence_scope", {"scope": scope})
	if scope == "battle":
		return _apply_op_unscoped(working, op, summary)
	if working.run == null:
		return _invalid_patch("test.patch.run_required")
	var before_cards := working.battle.card_by_id.duplicate(true)
	var before_relics := working.battle.relics.duplicate()
	var before_origins := working.relic_origins.duplicate()
	var error := _apply_op_unscoped(working, op, summary)
	if error != null:
		return error
	var transaction := TransactionResolver.new(TestContent.new(base_catalog, working.overlay))
	for id in before_cards:
		if working.battle.card_by_id.has(id):
			continue
		var origin := str(before_cards[id].get("origin_card_id", ""))
		var found := false
		for index in range(working.run.cards.size() - 1, -1, -1):
			if not origin.is_empty() and str(working.run.cards[index].card_id) == origin:
				working.run.cards.remove_at(index)
				found = true
				break
		if not found:
			return _invalid_patch("test.patch.run_card_unlinked", {"instance_id": str(id)})
	for id in working.battle.card_by_id:
		var card: Dictionary = working.battle.card_by_id[id]
		if not before_cards.has(id):
			var added := transaction.add_card(working.run, str(card.definition_id), "test_room")
			added.upgrade_level = int(card.get("upgrade_level", 0))
			card.origin_card_id = str(added.card_id)
	if str(op.op) == "set_card_field" and str(op.get("scope", "definition")) == "instance":
		var card: Dictionary = working.battle.card_by_id[str(op.target)]
		var origin := str(card.get("origin_card_id", ""))
		var found := false
		for permanent in working.run.cards:
			if not origin.is_empty() and str(permanent.card_id) == origin:
				permanent.upgrade_level = int(card.get("upgrade_level", 0))
				found = true
				break
		if not found:
			return _invalid_patch("test.patch.run_card_unlinked", {"instance_id": str(op.target)})
	if str(op.op) == "add_relic":
		var slot := 0
		var occupied := {}
		for relic in working.run.relics:
			occupied[int(relic.slot)] = true
		while occupied.has(slot):
			slot += 1
		var added := transaction.add_relic(working.run, str(op.relic_id), "", slot)
		var position := int(op.get("position", -1))
		if position < 0 or position >= working.battle.relics.size():
			position = working.battle.relics.size() - 1
		working.relic_origins[position] = str(added.relic_id)
	elif str(op.op) == "remove_relic":
		var position := before_relics.find(str(op.get("relic_id", "")))
		if position < 0:
			position = int(op.get("position", -1))
		var origin := str(before_origins[position])
		var found := false
		for index in working.run.relics.size():
			if not origin.is_empty() and str(working.run.relics[index].relic_id) == origin:
				working.run.relics.remove_at(index)
				found = true
				break
		if not found:
			return _invalid_patch("test.patch.run_relic_unlinked", {"relic_id": str(before_relics[position])})
	return null


func _apply_op_unscoped(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var name := str(op.get("op", ""))
	match name:
		"enter_node":
			var moved := _enter_test_node(working, str(op.get("node_key", "")))
			if not moved.ok:
				return moved.error
			summary.append({"op": name, "node_key": working.config.node_key})
			return null
		"set_money":
			var amount: Variant = op.get("value")
			if working.run == null or not amount is int or amount < 0 or amount > LIMITS.value:
				return _invalid_patch("test.patch.range", {"field": "money"})
			working.run.money = amount
			summary.append({"op": name, "value": amount})
			return null
		"set_character":
			return _op_set_character(working, op, summary)
		"set_switch":
			return _op_set_switch(working, op)
		"set_player_field":
			return _op_set_player_field(working, op)
		"adjust_player_field":
			return _op_adjust_player_field(working, op)
		"set_player_lock":
			var field := str(op.get("field", ""))
			if not PLAYER_FIELDS.has(field) or typeof(op.get("locked")) != TYPE_BOOL:
				return _invalid_patch("test.patch.lock", {"field": field})
			if op.locked:
				working.player_locks[field] = true
			else:
				working.player_locks.erase(field)
			summary.append({"op": name, "field": field, "locked": op.locked})
			return null
		"add_card":
			return _op_add_card(working, op, summary)
		"remove_instance":
			return _op_remove_instance(working, op, summary)
		"duplicate_instance":
			return _op_duplicate_instance(working, op, summary)
		"move_instance":
			return _op_move_instance(working, op, summary)
		"set_zone_order":
			return _op_set_zone_order(working, op, summary)
		"shuffle_zone":
			return _op_shuffle_zone(working, op, summary)
		"clear_zone":
			return _op_clear_zone(working, op, summary)
		"set_card_field":
			return _op_set_card_field(working, op, summary)
		"add_relic":
			return _op_add_relic(working, op, summary)
		"remove_relic":
			return _op_remove_relic(working, op, summary)
		"add_status":
			return _op_add_status(working, op, summary)
		"remove_status":
			return _op_remove_status(working, op, summary)
		"set_status_field":
			return _op_set_status_field(working, op, summary)
		"clear_statuses":
			return _op_clear_statuses(working, op, summary)
		"add_task":
			return _op_add_task(working, op, summary)
		"remove_task":
			return _op_remove_task(working, op, summary)
		"set_task_field":
			return _op_set_task_field(working, op, summary)
		"set_task_intent":
			return _op_set_task_intent(working, op, summary)
		"set_task_phase":
			return _op_set_task_phase(working, op, summary)
		"add_unit":
			return _op_add_unit(working, op, summary)
		"remove_unit":
			return _op_remove_unit(working, op, summary)
		"set_unit_field":
			return _op_set_unit_field(working, op, summary)
		"replace_encounter":
			return _op_replace_encounter(working, op, summary)
		"set_round":
			return _op_set_round(working, op)
		"set_ddl":
			return _op_set_ddl(working, op)
		"set_phase":
			return _op_set_phase(working, op)
		"set_counter":
			return _op_set_counter(working, op)
		"remove_counter":
			return _op_remove_counter(working, op)
		"set_rng":
			return _op_set_rng(working, op)
		"reset_rng":
			return _op_reset_rng(working, op)
		"set_rule_field":
			return _op_set_rule_field(working, op, summary)
		"set_status_cap":
			return _op_set_status_cap(working, op, summary)
		"upsert_definition":
			return _op_upsert_definition(working, op, summary)
		"remove_definition":
			return _op_remove_definition(working, op, summary)
		"set_definition_field":
			return _op_set_definition_field(working, op, summary)
		"set_v3_field":
			return _op_set_v3_field(working, op, summary)
		"set_outcome":
			return _op_set_outcome(working, op)
		"clear_outcome":
			return _op_set_outcome(working, op)
		"run_rule_op":
			return _op_run_rule_op(working, op, summary)
		"clear_scene":
			return _op_clear_scene(working, summary)
		"add_scene":
			return _op_add_scene(working, op, summary)
	return _invalid_patch("test.patch.unknown_op", {"op": name})


func _op_set_character(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var character_id := str(op.get("character_id", ""))
	var wrapped := TestContent.new(base_catalog, working.overlay)
	var character := _definition(wrapped, "character", character_id)
	if character.is_empty():
		return _invalid_patch("test.config.character", {"character_id": character_id})
	for field in ["keep_deck", "keep_relics"]:
		if typeof(op.get(field, true)) != TYPE_BOOL:
			return _invalid_patch("test.patch.type", {"field": field})
	working.config["character_id"] = character_id
	working.config["template_id"] = "character.%s" % character_id
	working.battle.character_id = character_id
	var player_id := str(working.battle.player.get("entity_id", ""))
	if working.battle.source_registry.has(player_id):
		working.battle.source_registry[player_id]["definition_id"] = character_id
	if working.run != null:
		working.run.character_id = character_id
		working.run.relics = working.run.relics.filter(func(relic): return bool(op.get("keep_relics", true)) and RelicPilot.owns_definition(str(relic.definition_id), character_id))
	if not bool(op.get("keep_deck", false)):
		var deck_error := _replace_character_deck(working, wrapped, character)
		if deck_error != null:
			return deck_error
	var relics: Array[String] = []
	var origins: Array[String] = []
	if bool(op.get("keep_relics", true)):
		for index in working.battle.relics.size():
			var relic_id := working.battle.relics[index]
			if RelicPilot.owns_definition(relic_id, character_id):
				relics.append(relic_id)
				origins.append(working.relic_origins[index])
	working.battle.relics.assign(relics)
	working.relic_origins.assign(origins)
	for source_id in working.battle.source_registry.keys():
		var source: Dictionary = working.battle.source_registry[source_id]
		if source.get("kind") == "relic" and not relics.has(str(source.get("definition_id", ""))):
			working.battle.source_registry.erase(source_id)
	for key in working.battle.counters.keys():
		var owner := str(key).get_slice("|", 1)
		if owner.begins_with("relic_hook:"):
			owner = owner.get_slice(":", 1)
		if owner.begins_with("RX-") and not relics.has(owner):
			working.battle.counters.erase(key)
	working.config["relics"] = relics.duplicate()
	summary.append({"op": "set_character", "character_id": character_id, "keep_deck": bool(op.get("keep_deck", false))})
	return null


func _replace_character_deck(working: TestRoomState, wrapped: TestContent, character: Dictionary) -> ApiError:
	var starter := _starter_cards(wrapped, character, [])
	if not starter.ok:
		return starter.error
	var battle := working.battle
	var hand_count: int = battle.zones.get("hand", []).size()
	var removed := {}
	for card in battle.card_by_id.values():
		removed[str(card.card_id)] = true
		removed[str(card.definition_id)] = true
		var origin := str(card.get("origin_card_id", ""))
		if not origin.is_empty():
			removed[origin] = true
	for id in wrapped.get_info().enabled.get("character", []):
		var definition := _definition(wrapped, "character", str(id))
		var passive_id := str(definition.get("passive", {}).get("id", ""))
		if not passive_id.is_empty():
			removed[passive_id] = true
			removed["passive:" + passive_id] = true
	for ability in battle.v3.get("abilities", []):
		removed[str(ability.get("ability_id", ""))] = true
		removed["ability:" + str(ability.get("definition_id", ""))] = true
	for unit in battle.units:
		removed[str(unit.unit_id)] = true
	if battle.scene is Dictionary:
		removed[str(battle.scene.scene_id)] = true
	for id in battle.card_by_id.keys():
		_remove_card(working, str(id))
	# A truncated pending choice can also leave cards in the resolving zone.
	for zone in battle.zones:
		battle.zones[zone].clear()
	battle.retained_card_ids.clear()
	battle.units.clear()
	battle.scene = null
	battle.v3.clear()
	battle.resolution = null
	for status in battle.statuses.duplicate():
		if removed.has(str(status.get("target_id", ""))) or removed.has(str(status.get("source_id", ""))):
			removed[str(status.instance_id)] = true
			battle.statuses.erase(status)
	for id in removed:
		battle.source_registry.erase(id)
	for key in battle.counters.keys():
		for id in removed:
			if not str(id).is_empty() and str(key).contains("|" + str(id) + "|"):
				battle.counters.erase(key)
				break
	# Keep the normal P02 opening card available immediately, without advancing
	# RNG, rerunning prepare hooks or restarting the current enemy encounter.
	var cards: Array = starter.data.duplicate(true)
	if battle.character_id == "P02":
		for index in cards.size():
			if cards[index].definition_id == "R3-P02-01":
				cards.push_front(cards.pop_at(index))
				break
	if working.run != null:
		working.run.cards.clear()
		var transactions := RunService.new(wrapped).transactions()
		for card in cards:
			transactions.add_card(working.run, str(card.definition_id), "starter")
		cards = working.run.cards.duplicate(true)
	for index in cards.size():
		var card: Dictionary = cards[index]
		var id := _new_instance_id(working, "c")
		battle.card_by_id[id] = {
			"card_id": id, "definition_id": str(card.definition_id),
			"origin_card_id": str(card.card_id), "upgrade_level": int(card.get("upgrade_level", 0)),
			"temporary_modifiers": {},
		}
		_register_source(working, id, "card", str(card.definition_id))
		var zone := "hand" if index < hand_count else "draw"
		battle.zones[zone].append(id)
	working.config["cards"] = cards.duplicate(true)
	return null


func _op_set_switch(working: TestRoomState, op: Dictionary) -> ApiError:
	var key := str(op.get("key", ""))
	if not SWITCHES.has(key):
		return _invalid_patch("test.patch.unknown_switch", {"key": key})
	if typeof(op.get("value")) != TYPE_BOOL:
		return _invalid_patch("test.patch.type", {"field": "value"})
	working.switches[key] = op.value
	if not working.config.has("switches"):
		working.config["switches"] = {}
	working.config.switches[key] = op.value
	return null


func _op_set_player_field(working: TestRoomState, op: Dictionary) -> ApiError:
	var field := str(op.get("field", ""))
	if not PLAYER_FIELDS.has(field):
		return _invalid_patch("test.patch.unknown_field", {"field": field})
	var value: Variant = op.get("value")
	if typeof(value) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": field})
	if absi(int(value)) > LIMITS.value:
		return _limit("value")
	if field == "max_vitality" and int(value) < 1:
		return _invalid_patch("test.patch.range", {"field": field})
	if field in ["vitality", "focus", "relax"] and int(value) < 0:
		return _invalid_patch("test.patch.range", {"field": field})
	if field == "vitality" and int(value) > int(working.battle.player.get("max_vitality", LIMITS.value)):
		return _invalid_patch("test.patch.range", {"field": field})
	working.battle.player[field] = int(value)
	if working.run != null:
		if field == "max_vitality":
			working.run.max_vitality = int(value)
			working.run.vitality = mini(working.run.vitality, int(value))
		elif field == "vitality":
			working.run.vitality = int(value)
	if field == "max_vitality":
		working.battle.player["max_vitality_base"] = int(value)
	return null


func _op_adjust_player_field(working: TestRoomState, op: Dictionary) -> ApiError:
	var field := str(op.get("field", ""))
	if not PLAYER_FIELDS.has(field):
		return _invalid_patch("test.patch.unknown_field", {"field": field})
	var delta: Variant = op.get("delta")
	if typeof(delta) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": "delta"})
	return _op_set_player_field(
		working, {"op": "set_player_field", "field": field, "value": int(working.battle.player.get(field, 0)) + int(delta)}
	)


func _op_add_card(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var definition_id := str(op.get("definition_id", ""))
	var zone := str(op.get("zone", "hand"))
	if zone == "chapter":
		return _add_chapter_cards(working, definition_id, op, summary)
	if not ZONES.has(zone):
		return ApiError.new(
			GameConstants.ERROR_TEST_UNSUPPORTED, "test.patch.zone_unsupported", {"zone": zone}
		)
	var definition := _definition(TestContent.new(base_catalog, working.overlay), "card", definition_id)
	if definition.is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
	if typeof(op.get("count", 1)) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": "count"})
	var count := int(op.get("count", 1))
	if count < 1 or count > 50:
		return _invalid_patch("test.patch.count", {"count": count})
	var zone_cards: Array = working.battle.zones.get(zone, [])
	if zone_cards.size() + count > LIMITS.zone:
		return _limit("zone")
	if working.battle.card_by_id.size() + count > LIMITS.cards:
		return _limit("cards")
	var position := int(op.get("position", -1))
	for _index in count:
		var instance_id := _new_instance_id(working, "c")
		working.battle.card_by_id[instance_id] = {
			"card_id": instance_id,
			"definition_id": definition_id,
			"origin_card_id": "",
			"upgrade_level": 0,
			"temporary_modifiers": {},
		}
		_register_source(working, instance_id, "card", definition_id)
		if position >= 0 and position <= zone_cards.size():
			zone_cards.insert(position, instance_id)
			position += 1
		else:
			zone_cards.append(instance_id)
	working.battle.zones[zone] = zone_cards
	summary.append({"op": "add_card", "definition_id": definition_id, "zone": zone, "count": count})
	return null


func _add_chapter_cards(
	working: TestRoomState, definition_id: String, op: Dictionary, summary: Array[Dictionary]
) -> ApiError:
	if _definition(TestContent.new(base_catalog, working.overlay), "card", definition_id).is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
	if typeof(op.get("count", 1)) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": "count"})
	var count := int(op.get("count", 1))
	if count < 1 or count > 50:
		return _invalid_patch("test.patch.count", {"count": count})
	var paper := _paper(working)
	var chapters: Array = paper.get("chapters", [])
	if chapters.size() + count > LIMITS.chapters:
		return _limit("chapters")
	if working.battle.card_by_id.size() + count > LIMITS.cards:
		return _limit("cards")
	paper["open"] = true
	for _index in count:
		var instance_id := _new_instance_id(working, "c")
		working.battle.card_by_id[instance_id] = {
			"card_id": instance_id,
			"definition_id": definition_id,
			"origin_card_id": "",
			"upgrade_level": 0,
			"temporary_modifiers": {},
		}
		_register_source(working, instance_id, "card", definition_id)
		chapters.append(
			{
				"card_id": instance_id,
				"definition_id": definition_id,
				"deployed_round": working.battle.round_index,
			}
		)
	paper["chapters"] = chapters
	working.battle.v3["paper"] = paper
	summary.append({"op": "add_card", "definition_id": definition_id, "zone": "chapter", "count": count})
	return null


func _paper(working: TestRoomState) -> Dictionary:
	if typeof(working.battle.v3) != TYPE_DICTIONARY:
		working.battle.v3 = {}
	if typeof(working.battle.v3.get("paper")) != TYPE_DICTIONARY:
		working.battle.v3["paper"] = {
			"open": true,
			"progress": 0,
			"citations": 0,
			"modifier": 0,
			"amplify": 0,
			"used_names": [],
			"publication_id": "",
			"chapters": [],
			"turn_names": [],
		}
	return working.battle.v3.paper


func _chapter_index(working: TestRoomState, instance_id: String) -> int:
	if (
		typeof(working.battle.v3) != TYPE_DICTIONARY
		or typeof(working.battle.v3.get("paper")) != TYPE_DICTIONARY
	):
		return -1
	var chapters: Array = working.battle.v3.paper.get("chapters", [])
	for index in chapters.size():
		if str((chapters[index] as Dictionary).get("card_id", "")) == instance_id:
			return index
	return -1


func _op_remove_instance(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var instance_id := str(op.get("instance_id", ""))
	if not working.battle.card_by_id.has(instance_id):
		return _invalid_patch("test.patch.instance_missing", {"instance_id": instance_id})
	_remove_card(working, instance_id)
	summary.append({"op": "remove_instance", "instance_id": instance_id})
	return null


func _op_duplicate_instance(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var instance_id := str(op.get("instance_id", ""))
	if not working.battle.card_by_id.has(instance_id):
		return _invalid_patch("test.patch.instance_missing", {"instance_id": instance_id})
	var source: Dictionary = working.battle.card_by_id[instance_id]
	var zone := str(op.get("zone", ""))
	if zone.is_empty():
		zone = _zone_of(working, instance_id)
	if not ZONES.has(zone):
		return ApiError.new(
			GameConstants.ERROR_TEST_UNSUPPORTED, "test.patch.zone_unsupported", {"zone": zone}
		)
	if typeof(op.get("count", 1)) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": "count"})
	var count := int(op.get("count", 1))
	if count < 1 or count > 50:
		return _invalid_patch("test.patch.count", {"count": count})
	var zone_cards: Array = working.battle.zones.get(zone, [])
	if zone_cards.size() + count > LIMITS.zone:
		return _limit("zone")
	for _index in count:
		var new_id := _new_instance_id(working, "c")
		working.battle.card_by_id[new_id] = {
			"card_id": new_id,
			"definition_id": str(source.definition_id),
			"origin_card_id": "",
			"upgrade_level": int(source.get("upgrade_level", 0)),
			"temporary_modifiers": {},
		}
		_register_source(working, new_id, "card", str(source.definition_id))
		zone_cards.append(new_id)
	working.battle.zones[zone] = zone_cards
	summary.append({"op": "duplicate_instance", "source": instance_id, "count": count})
	return null


func _op_move_instance(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var instance_id := str(op.get("instance_id", ""))
	var zone := str(op.get("zone", ""))
	if not working.battle.card_by_id.has(instance_id):
		return _invalid_patch("test.patch.instance_missing", {"instance_id": instance_id})
	if not ZONES.has(zone) and zone != "chapter":
		return ApiError.new(
			GameConstants.ERROR_TEST_UNSUPPORTED, "test.patch.zone_unsupported", {"zone": zone}
		)
	var source_zone := _zone_of(working, instance_id)
	if source_zone == zone:
		var position := int(op.get("position", -1))
		if position >= 0 and ZONES.has(zone):
			var cards: Array = working.battle.zones[zone]
			cards.erase(instance_id)
			cards.insert(mini(position, cards.size()), instance_id)
			summary.append({"op": "move_instance", "instance_id": instance_id, "to": zone, "position": position})
		return null
	if source_zone.is_empty():
		return _invalid_patch("test.patch.instance_unzoned", {"instance_id": instance_id})
	if source_zone == "chapter":
		var chapters: Array = _paper(working).get("chapters", [])
		var chapter_index := _chapter_index(working, instance_id)
		if chapter_index >= 0:
			chapters.remove_at(chapter_index)
			working.battle.v3.paper["chapters"] = chapters
		if zone == "chapter":
			return null
		var target_cards: Array = working.battle.zones.get(zone, [])
		if target_cards.size() >= LIMITS.zone:
			return _limit("zone")
		var position := int(op.get("position", -1))
		if position >= 0 and position <= target_cards.size():
			target_cards.insert(position, instance_id)
		else:
			target_cards.append(instance_id)
		working.battle.zones[zone] = target_cards
		working.battle.retained_card_ids.erase(instance_id)
		summary.append({"op": "move_instance", "instance_id": instance_id, "to": zone})
		return null
	var source_cards: Array = working.battle.zones.get(source_zone, [])
	source_cards.erase(instance_id)
	working.battle.zones[source_zone] = source_cards
	working.battle.retained_card_ids.erase(instance_id)
	if zone == "chapter":
		return _append_chapter(working, instance_id, summary)
	var target_cards: Array = working.battle.zones.get(zone, [])
	if target_cards.size() >= LIMITS.zone:
		return _limit("zone")
	var position := int(op.get("position", -1))
	if position >= 0 and position <= target_cards.size():
		target_cards.insert(position, instance_id)
	else:
		target_cards.append(instance_id)
	working.battle.zones[zone] = target_cards
	summary.append({"op": "move_instance", "instance_id": instance_id, "to": zone})
	return null


func _append_chapter(working: TestRoomState, instance_id: String, summary: Array[Dictionary]) -> ApiError:
	var paper := _paper(working)
	var chapters: Array = paper.get("chapters", [])
	if chapters.size() >= LIMITS.chapters:
		return _limit("chapters")
	var card: Dictionary = working.battle.card_by_id.get(instance_id, {})
	paper["open"] = true
	chapters.append(
		{
			"card_id": instance_id,
			"definition_id": str(card.get("definition_id", "")),
			"deployed_round": working.battle.round_index,
		}
	)
	paper["chapters"] = chapters
	summary.append({"op": "move_instance", "instance_id": instance_id, "to": "chapter"})
	return null


func _op_set_zone_order(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var zone := str(op.get("zone", ""))
	if not ZONES.has(zone):
		return _invalid_patch("test.patch.zone", {"zone": zone})
	var order: Variant = op.get("instance_ids")
	if typeof(order) != TYPE_ARRAY:
		return _invalid_patch("test.patch.type", {"field": "instance_ids"})
	var current: Array = working.battle.zones.get(zone, [])
	var expected := {}
	for id in current:
		expected[str(id)] = int(expected.get(str(id), 0)) + 1
	for id in order:
		var key := str(id)
		if not expected.has(key):
			return _invalid_patch("test.patch.zone_mismatch", {"id": key})
		expected[key] = int(expected[key]) - 1
		if int(expected[key]) < 0:
			return _invalid_patch("test.patch.zone_mismatch", {"id": key})
	for key in expected:
		if int(expected[key]) != 0:
			return _invalid_patch("test.patch.zone_mismatch", {"id": key})
	working.battle.zones[zone] = order.duplicate()
	summary.append({"op": "set_zone_order", "zone": zone, "count": order.size()})
	return null


func _op_shuffle_zone(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var zone := str(op.get("zone", "draw"))
	if not ZONES.has(zone):
		return _invalid_patch("test.patch.zone", {"zone": zone})
	var rng := RandomSource.new()
	var restored := rng.restore_state(working.rng)
	if not restored.ok:
		return ApiError.new(GameConstants.ERROR_TEST_STRUCTURE_INVALID, "test.rng.invalid")
	var ids: Array[String] = []
	for id in working.battle.zones.get(zone, []):
		ids.append(str(id))
	var shuffled := rng.shuffle(GameConstants.RNG_STREAM_BATTLE, ids)
	if not shuffled.ok:
		return shuffled.error
	working.battle.zones[zone] = shuffled.data
	working.rng = rng.export_state().to_dictionary()
	summary.append({"op": "shuffle_zone", "zone": zone, "count": ids.size()})
	return null


func _op_clear_zone(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var zone := str(op.get("zone", ""))
	if zone == "chapter":
		var chapters: Array = _paper(working).get("chapters", []).duplicate()
		for entry in chapters:
			_remove_card(working, str((entry as Dictionary).get("card_id", "")))
		working.battle.v3.paper["chapters"] = []
		summary.append({"op": "clear_zone", "zone": "chapter"})
		return null
	if not ZONES.has(zone):
		return _invalid_patch("test.patch.zone", {"zone": zone})
	for id in working.battle.zones.get(zone, []).duplicate():
		_remove_card(working, str(id))
	working.battle.zones[zone] = []
	working.battle.retained_card_ids.clear()
	summary.append({"op": "clear_zone", "zone": zone})
	return null


func _op_set_card_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var scope := str(op.get("scope", "definition"))
	var target := str(op.get("target", ""))
	var field := str(op.get("field", ""))
	var value: Variant = op.get("value")
	if scope == "instance":
		if not working.battle.card_by_id.has(target):
			return _invalid_patch("test.patch.instance_missing", {"instance_id": target})
		if field != "upgrade_level":
			return ApiError.new(
				GameConstants.ERROR_TEST_UNSUPPORTED,
				"test.patch.instance_field",
				{"field": field}
			)
		if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 1:
			return _invalid_patch("test.patch.range", {"field": field})
		working.battle.card_by_id[target]["upgrade_level"] = int(value)
		summary.append({"op": "set_card_field", "scope": scope, "target": target, "field": field})
		return null
	if scope != "definition":
		return _invalid_patch("test.patch.scope", {"scope": scope})
	if _definition(TestContent.new(base_catalog, working.overlay), "card", target).is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": target})
	var overlay_error := working.overlay.set_field("card", target, field, value)
	if overlay_error != null:
		return overlay_error
	summary.append({"op": "set_card_field", "scope": scope, "target": target, "field": field})
	return null


func _op_add_relic(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var relic_id := str(op.get("relic_id", ""))
	if _definition(TestContent.new(base_catalog, working.overlay), "relic", relic_id).is_empty() or not RelicPilot.owns_definition(relic_id, working.battle.character_id):
		return _invalid_patch("test.patch.definition_missing", {"relic_id": relic_id})
	if RelicPilot.expanded(_manifest_id) and relic_id in working.battle.relics and not bool(working.switches.get("ignore_relic_unique", false)):
		return _switch_required("ignore_relic_unique")
	if working.battle.relics.size() >= LIMITS.relics:
		return _limit("relics")
	var position := int(op.get("position", -1))
	if position >= 0 and position <= working.battle.relics.size():
		working.battle.relics.insert(position, relic_id)
		working.relic_origins.insert(position, "")
	else:
		working.battle.relics.append(relic_id)
		working.relic_origins.append("")
	summary.append({"op": "add_relic", "relic_id": relic_id})
	return null


func _op_remove_relic(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var relic_id := str(op.get("relic_id", ""))
	var position := int(op.get("position", -1))
	var removed := ""
	if not relic_id.is_empty() and working.battle.relics.has(relic_id):
		position = working.battle.relics.find(relic_id)
	if position >= 0 and position < working.battle.relics.size():
		removed = working.battle.relics[position]
		working.battle.relics.remove_at(position)
		working.relic_origins.remove_at(position)
	else:
		return _invalid_patch("test.patch.relic_missing", {"relic_id": relic_id, "position": position})
	summary.append({"op": "remove_relic", "relic_id": removed})
	return null


func _op_add_status(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var status_id := str(op.get("status_id", ""))
	var target_id := str(op.get("target_id", ""))
	if _definition(TestContent.new(base_catalog, working.overlay), "status", status_id).is_empty():
		return _invalid_patch("test.patch.definition_missing", {"status_id": status_id})
	if not _holder_exists(working, target_id):
		return _invalid_patch("test.patch.target_missing", {"target_id": target_id})
	var stacks := int(op.get("stacks", 1))
	if stacks < 1 or stacks > 999:
		return _invalid_patch("test.patch.range", {"field": "stacks"})
	if working.battle.statuses.size() >= LIMITS.statuses:
		return _limit("statuses")
	var existing := _status_index(working, status_id, target_id)
	if existing >= 0:
		working.battle.statuses[existing]["stacks"] = mini(
			999, int(working.battle.statuses[existing].get("stacks", 0)) + stacks
		)
	else:
		var definition := _definition(TestContent.new(base_catalog, working.overlay), "status", status_id)
		var instance_id := _new_instance_id(working, "st")
		working.battle.statuses.append(
			{
				"status_id": status_id,
				"instance_id": instance_id,
				"source_id": "",
				"target_id": target_id,
				"stacks": stacks,
				"expiry": str(op.get("expiry", definition.get("duration_policy", "battle"))),
			}
		)
		_register_source(working, instance_id, "status", status_id)
	summary.append({"op": "add_status", "status_id": status_id, "target_id": target_id, "stacks": stacks})
	return null


func _op_remove_status(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var instance_id := str(op.get("instance_id", ""))
	var status_id := str(op.get("status_id", ""))
	var target_id := str(op.get("target_id", ""))
	var index := -1
	if not instance_id.is_empty():
		for i in working.battle.statuses.size():
			if str(working.battle.statuses[i].get("instance_id", "")) == instance_id:
				index = i
				break
	else:
		index = _status_index(working, status_id, target_id)
	if index < 0:
		return _invalid_patch("test.patch.status_missing", {"status_id": status_id})
	var removed: Dictionary = working.battle.statuses[index]
	working.battle.statuses.remove_at(index)
	working.battle.source_registry.erase(str(removed.get("instance_id", "")))
	summary.append({"op": "remove_status", "status_id": str(removed.get("status_id", ""))})
	return null


func _op_set_status_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var instance_id := str(op.get("instance_id", ""))
	var field := str(op.get("field", ""))
	var value: Variant = op.get("value")
	var index := -1
	for i in working.battle.statuses.size():
		if str(working.battle.statuses[i].get("instance_id", "")) == instance_id:
			index = i
			break
	if index < 0:
		return _invalid_patch("test.patch.status_missing", {"instance_id": instance_id})
	if field == "stacks":
		if typeof(value) != TYPE_INT or int(value) < 1 or int(value) > 999:
			return _invalid_patch("test.patch.range", {"field": field})
		working.battle.statuses[index]["stacks"] = int(value)
	elif field == "expiry":
		if typeof(value) != TYPE_STRING:
			return _invalid_patch("test.patch.type", {"field": field})
		working.battle.statuses[index]["expiry"] = str(value)
	elif field == "source_id":
		working.battle.statuses[index]["source_id"] = str(value)
	else:
		return _invalid_patch("test.patch.field_not_supported", {"field": field})
	summary.append({"op": "set_status_field", "instance_id": instance_id, "field": field})
	return null


func _op_clear_statuses(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var target_id := str(op.get("target_id", ""))
	var kept: Array[Dictionary] = []
	for status in working.battle.statuses:
		if target_id.is_empty() or str(status.get("target_id", "")) == target_id:
			working.battle.source_registry.erase(str(status.get("instance_id", "")))
		else:
			kept.append(status)
	working.battle.statuses = kept
	summary.append({"op": "clear_statuses", "target_id": target_id})
	return null


func _op_add_task(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var definition_id := str(op.get("definition_id", ""))
	var definition := _definition(TestContent.new(base_catalog, working.overlay), "task", definition_id)
	if definition.is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
	if working.battle.tasks.size() >= LIMITS.tasks:
		return _limit("tasks")
	var phases: Array = definition.get("phases", [])
	if phases.is_empty():
		return _invalid_patch("test.patch.task_phases", {"definition_id": definition_id})
	var phase: Dictionary = phases[0]
	var intents: Array = phase.get("intents", [])
	if intents.is_empty():
		return _invalid_patch("test.patch.task_intents", {"definition_id": definition_id})
	var task_id := _new_instance_id(working, "t")
	var task := {
		"task_id": task_id,
		"definition_id": definition_id,
		"phase_key": str(phase.get("phase_key", "main")),
		"work_remaining": int(phase.get("work_max", 1)),
		"work_max": int(phase.get("work_max", 1)),
		"shield": int((intents[0] as Dictionary).get("shield", 0)),
		"intent_cursor": 0,
		"intent_snapshot": (intents[0] as Dictionary).duplicate(true),
		"entered_order": working.battle.next_creation_order,
		"eligible_round": 1,
	}
	_register_source(working, task_id, "task", definition_id)
	var position := int(op.get("position", -1))
	if position >= 0 and position <= working.battle.tasks.size():
		working.battle.tasks.insert(position, task)
	else:
		working.battle.tasks.append(task)
	summary.append({"op": "add_task", "definition_id": definition_id})
	return null


func _op_remove_task(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var task_id := str(op.get("task_id", ""))
	var index := -1
	for i in working.battle.tasks.size():
		if str(working.battle.tasks[i].get("task_id", "")) == task_id:
			index = i
			break
	if index < 0:
		return _invalid_patch("test.patch.task_missing", {"task_id": task_id})
	working.battle.tasks.remove_at(index)
	working.battle.source_registry.erase(task_id)
	var kept: Array[Dictionary] = []
	for status in working.battle.statuses:
		if str(status.get("target_id", "")) == task_id:
			working.battle.source_registry.erase(str(status.get("instance_id", "")))
		else:
			kept.append(status)
	working.battle.statuses = kept
	summary.append({"op": "remove_task", "task_id": task_id})
	return null


func _op_set_task_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var task_id := str(op.get("task_id", ""))
	var field := str(op.get("field", ""))
	var value: Variant = op.get("value")
	var index := -1
	for i in working.battle.tasks.size():
		if str(working.battle.tasks[i].get("task_id", "")) == task_id:
			index = i
			break
	if index < 0:
		return _invalid_patch("test.patch.task_missing", {"task_id": task_id})
	if field in ["work_remaining", "work_max", "shield"]:
		if typeof(value) != TYPE_INT:
			return _invalid_patch("test.patch.type", {"field": field})
		if int(value) < 0 or int(value) > 99999:
			return _invalid_patch("test.patch.range", {"field": field})
		if field == "work_remaining" and int(value) > int(working.battle.tasks[index].get("work_max", 0)):
			return _invalid_patch("test.patch.range", {"field": field})
		if field == "work_max" and int(value) < 1:
			return _invalid_patch("test.patch.range", {"field": field})
		if field == "work_max" and int(working.battle.tasks[index].get("work_remaining", 0)) > int(value):
			working.battle.tasks[index]["work_remaining"] = int(value)
		working.battle.tasks[index][field] = int(value)
	elif field == "eligible_round":
		if typeof(value) != TYPE_INT or int(value) < 1 or int(value) > working.battle.round_index:
			return _invalid_patch("test.patch.range", {"field": field})
		working.battle.tasks[index][field] = int(value)
	elif field == "phase_key":
		return _op_set_task_phase(working, {"task_id": task_id, "phase_key": str(value)}, summary)
	else:
		return _invalid_patch("test.patch.field_not_supported", {"field": field})
	summary.append({"op": "set_task_field", "task_id": task_id, "field": field})
	return null


func _op_set_task_intent(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var task_id := str(op.get("task_id", ""))
	var intent: Variant = op.get("intent")
	if typeof(intent) != TYPE_DICTIONARY:
		return _invalid_patch("test.patch.type", {"field": "intent"})
	for task in working.battle.tasks:
		if str(task.get("task_id", "")) == task_id:
			task["intent_snapshot"] = (intent as Dictionary).duplicate(true)
			if op.has("intent_cursor") and typeof(op.intent_cursor) == TYPE_INT:
				task["intent_cursor"] = maxi(0, int(op.intent_cursor))
			summary.append({"op": "set_task_intent", "task_id": task_id})
			return null
	return _invalid_patch("test.patch.task_missing", {"task_id": task_id})


func _op_set_task_phase(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var task_id := str(op.get("task_id", ""))
	var phase_key := str(op.get("phase_key", ""))
	for task in working.battle.tasks:
		if str(task.get("task_id", "")) != task_id:
			continue
		var definition := _definition(TestContent.new(base_catalog, working.overlay), "task", str(task.get("definition_id", "")))
		var phases: Array = definition.get("phases", [])
		for phase in phases:
			if str(phase.get("phase_key", "")) != phase_key:
				continue
			var intents: Array = phase.get("intents", [])
			task["phase_key"] = phase_key
			task["work_max"] = int(phase.get("work_max", 1))
			task["work_remaining"] = int(phase.get("work_max", 1))
			task["shield"] = int((intents[0] as Dictionary).get("shield", 0)) if not intents.is_empty() else 0
			task["intent_cursor"] = 0
			task["intent_snapshot"] = (intents[0] as Dictionary).duplicate(true) if not intents.is_empty() else {}
			summary.append({"op": "set_task_phase", "task_id": task_id, "phase_key": phase_key})
			return null
		return _invalid_patch("test.patch.phase_missing", {"task_id": task_id, "phase_key": phase_key})
	return _invalid_patch("test.patch.task_missing", {"task_id": task_id})


func _op_add_unit(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var definition_id := str(op.get("definition_id", ""))
	var definition := _definition(TestContent.new(base_catalog, working.overlay), "unit", definition_id)
	if definition.is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
	if working.battle.units.size() >= LIMITS.units:
		return _limit("units")
	var unit_id := _new_instance_id(working, "u")
	var unit: Dictionary = definition.duplicate(true)
	unit["unit_id"] = unit_id
	unit["definition_id"] = definition_id
	unit["vitality"] = int(unit.get("vitality", 1))
	unit["max_vitality"] = int(unit.get("max_vitality", unit["vitality"]))
	unit["cooperation"] = int(unit.get("cooperation", 0))
	unit["relax"] = int(unit.get("relax", 0))
	unit["entered_order"] = working.battle.next_creation_order
	unit["actions_taken"] = 0
	unit["target_id"] = ""
	_register_source(working, unit_id, "unit", definition_id)
	var position := int(op.get("position", -1))
	if position >= 0 and position <= working.battle.units.size():
		working.battle.units.insert(position, unit)
	else:
		working.battle.units.append(unit)
	summary.append({"op": "add_unit", "definition_id": definition_id})
	return null


func _op_remove_unit(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var unit_id := str(op.get("unit_id", ""))
	var index := -1
	for i in working.battle.units.size():
		if str(working.battle.units[i].get("unit_id", "")) == unit_id:
			index = i
			break
	if index < 0:
		return _invalid_patch("test.patch.unit_missing", {"unit_id": unit_id})
	working.battle.units.remove_at(index)
	working.battle.source_registry.erase(unit_id)
	var kept: Array[Dictionary] = []
	for status in working.battle.statuses:
		if str(status.get("target_id", "")) == unit_id:
			working.battle.source_registry.erase(str(status.get("instance_id", "")))
		else:
			kept.append(status)
	working.battle.statuses = kept
	summary.append({"op": "remove_unit", "unit_id": unit_id})
	return null


func _op_set_unit_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var unit_id := str(op.get("unit_id", ""))
	var field := str(op.get("field", ""))
	var value: Variant = op.get("value")
	var index := -1
	for i in working.battle.units.size():
		if str(working.battle.units[i].get("unit_id", "")) == unit_id:
			index = i
			break
	if index < 0:
		return _invalid_patch("test.patch.unit_missing", {"unit_id": unit_id})
	if field not in ["vitality", "max_vitality", "cooperation", "relax", "actions_taken"]:
		return _invalid_patch("test.patch.field_not_supported", {"field": field})
	if typeof(value) != TYPE_INT:
		return _invalid_patch("test.patch.type", {"field": field})
	if int(value) < 0 or int(value) > LIMITS.value:
		return _invalid_patch("test.patch.range", {"field": field})
	working.battle.units[index][field] = int(value)
	summary.append({"op": "set_unit_field", "unit_id": unit_id, "field": field})
	return null


func _op_replace_encounter(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var encounter_id := str(op.get("encounter_id", ""))
	var encounter := _definition(TestContent.new(base_catalog, working.overlay), "encounter", encounter_id)
	if encounter.is_empty():
		return _invalid_patch("test.patch.definition_missing", {"encounter_id": encounter_id})
	var members: Array = encounter.get("members", []).duplicate()
	if encounter.has("spawn"):
		var pool := members.duplicate()
		members.clear()
		for group in encounter.spawn.get("groups", []):
			var used := 0
			for id in pool:
				var definition := _definition(TestContent.new(base_catalog, working.overlay), "task", str(id))
				if str(definition.get("spawn_group", "other")) == str(group.get("group", "")):
					members.append(id)
					used += 1
					if used >= int(group.get("count", 1)):
						break
			if used < int(group.get("count", 1)):
				return _invalid_patch("test.patch.dynamic_encounter", {"encounter_id": encounter_id})
	for member_id in members:
		if _definition(TestContent.new(base_catalog, working.overlay), "task", str(member_id)).is_empty():
			return _invalid_patch("test.patch.task_missing", {"definition_id": str(member_id)})
	var kept_statuses: Array[Dictionary] = []
	for status in working.battle.statuses:
		if _holder_kind(working, str(status.get("target_id", ""))) != "task":
			kept_statuses.append(status)
	for task in working.battle.tasks:
		working.battle.source_registry.erase(str(task.get("task_id", "")))
	working.battle.statuses = kept_statuses
	working.battle.tasks.clear()
	for member_id in members:
		var task_op := {"op": "add_task", "definition_id": str(member_id)}
		var task_error := _op_add_task(working, task_op, summary)
		if task_error != null:
			return task_error
	working.battle.encounter_id = encounter_id
	working.config["encounter_id"] = encounter_id
	working.battle.exam_flags.clear()
	for flag in encounter.get("exam_flags", []):
		working.battle.exam_flags.append(str(flag))
	working.battle.ddl = maxi(1, int(encounter.get("base_ddl", working.battle.ddl)))
	summary.append({"op": "replace_encounter", "encounter_id": encounter_id, "tasks": working.battle.tasks.size()})
	return null


func _op_set_round(working: TestRoomState, op: Dictionary) -> ApiError:
	var value: Variant = op.get("round_index")
	if typeof(value) != TYPE_INT or int(value) < 1 or int(value) > LIMITS.round:
		return _invalid_patch("test.patch.range", {"field": "round_index"})
	for task in working.battle.tasks:
		if int(task.get("eligible_round", 1)) > int(value):
			task["eligible_round"] = int(value)
	working.battle.round_index = int(value)
	return null


func _op_set_ddl(working: TestRoomState, op: Dictionary) -> ApiError:
	var value: Variant = op.get("ddl")
	if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > LIMITS.ddl:
		return _invalid_patch("test.patch.range", {"field": "ddl"})
	working.battle.ddl = int(value)
	return null


func _op_set_phase(working: TestRoomState, op: Dictionary) -> ApiError:
	var phase := str(op.get("phase", ""))
	if not (phase in ["player_prepare", "player_action", "enemy_turn", "finished"]):
		return _invalid_patch("test.patch.phase", {"phase": phase})
	if phase == "finished" and working.battle.outcome == null:
		return _invalid_patch("test.patch.phase_outcome", {"phase": phase})
	working.battle.phase = phase
	if phase != "enemy_turn":
		working.pending_turn.clear()
	return null


func _op_set_counter(working: TestRoomState, op: Dictionary) -> ApiError:
	var key := str(op.get("key", ""))
	if key.is_empty() or key.length() > 128:
		return _invalid_patch("test.patch.counter_key", {"key": key})
	var value: Variant = op.get("value")
	if typeof(value) != TYPE_INT or absi(int(value)) > LIMITS.value:
		return _invalid_patch("test.patch.range", {"field": "value"})
	working.battle.counters[key] = int(value)
	return null


func _op_remove_counter(working: TestRoomState, op: Dictionary) -> ApiError:
	working.battle.counters.erase(str(op.get("key", "")))
	return null


func _op_set_rng(working: TestRoomState, op: Dictionary) -> ApiError:
	var stream := str(op.get("stream", ""))
	if not RandomSource.STREAMS.has(stream):
		return _invalid_patch("test.patch.rng_stream", {"stream": stream})
	var snapshot: Dictionary = working.rng.duplicate(true)
	if not snapshot.has("streams"):
		return ApiError.new(GameConstants.ERROR_TEST_STRUCTURE_INVALID, "test.rng.invalid")
	var entry: Dictionary = snapshot.streams.get(stream, {}).duplicate(true)
	if op.has("seed"):
		if not str(op.seed).is_valid_int():
			return _invalid_patch("test.patch.rng_seed", {"seed": op.seed})
		entry["seed"] = str(op.seed)
	if op.has("state"):
		if not str(op.state).is_valid_int():
			return _invalid_patch("test.patch.rng_state", {"state": op.state})
		entry["state"] = str(op.state)
	snapshot.streams[stream] = entry
	var check := RandomSource.new()
	var restored := check.restore_state(snapshot)
	if not restored.ok:
		return restored.error
	working.rng = snapshot
	return null


func _op_reset_rng(working: TestRoomState, op: Dictionary) -> ApiError:
	var mode := str(op.get("mode", "battle"))
	var seed := str(op.get("seed", working.seed))
	if seed.is_empty():
		seed = "42"
	var fresh := RandomSource.new(seed).export_state().to_dictionary()
	if mode == "all":
		working.rng = fresh
	elif mode == "battle":
		var snapshot: Dictionary = working.rng.duplicate(true)
		if not snapshot.has("streams"):
			return ApiError.new(GameConstants.ERROR_TEST_STRUCTURE_INVALID, "test.rng.invalid")
		snapshot.streams["battle"] = fresh.streams["battle"]
		working.rng = snapshot
	else:
		return _invalid_patch("test.patch.rng_mode", {"mode": mode})
	return null


func _op_set_rule_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var path := str(op.get("path", ""))
	var ruleset_id := "" if catalog == null else str(catalog.get_info().ruleset_id)
	var error := working.overlay.set_field("ruleset", ruleset_id, path, op.get("value"))
	if error != null:
		return error
	summary.append({"op": "set_rule_field", "path": path})
	return null


func _op_set_status_cap(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var status_id := str(op.get("status_id", ""))
	var cap := int(op.get("cap", 0))
	if cap < 1 or cap > 99:
		return _invalid_patch("test.patch.range", {"field": "cap"})
	var ruleset_id := "" if catalog == null else str(catalog.get_info().ruleset_id)
	var error := working.overlay.set_field("ruleset", ruleset_id, "statuses.%s.cap" % status_id, cap)
	if error != null:
		return error
	summary.append({"op": "set_status_cap", "status_id": status_id, "cap": cap})
	return null


func _op_upsert_definition(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var kind := str(op.get("kind", ""))
	var id := str(op.get("id", ""))
	var definition: Variant = op.get("definition", {})
	if typeof(definition) != TYPE_DICTIONARY:
		return _invalid_patch("test.patch.definition_invalid", {"id": id})
	if working.overlay.definition_count() >= LIMITS.definitions:
		return _limit("definitions")
	var error := working.overlay.upsert(kind, id, definition)
	if error != null:
		return error
	summary.append({"op": "upsert_definition", "kind": kind, "id": id})
	return null


func _op_remove_definition(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var kind := str(op.get("kind", ""))
	var id := str(op.get("id", ""))
	if _referenced(working, kind, id):
		return _invalid_patch("test.patch.definition_in_use", {"kind": kind, "id": id})
	var error := working.overlay.remove(kind, id)
	if error != null:
		return error
	summary.append({"op": "remove_definition", "kind": kind, "id": id})
	return null


func _op_set_definition_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var kind := str(op.get("kind", ""))
	var id := str(op.get("id", ""))
	if _definition(TestContent.new(base_catalog, working.overlay), kind, id).is_empty():
		return _invalid_patch("test.patch.definition_missing", {"kind": kind, "id": id})
	var error := working.overlay.set_field(kind, id, str(op.get("path", "")), op.get("value"))
	if error != null:
		return error
	summary.append({"op": "set_definition_field", "kind": kind, "id": id})
	return null


func _op_set_v3_field(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var path := str(op.get("path", ""))
	var value: Variant = op.get("value")
	if not (path in [
		"paper.open",
		"paper.progress",
		"paper.citations",
		"paper.modifier",
		"paper.amplify",
		"synergy",
	]):
		return _invalid_patch("test.patch.v3_path", {"path": path})
	if typeof(working.battle.v3) != TYPE_DICTIONARY:
		working.battle.v3 = {}
	if path == "synergy":
		if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 999:
			return _invalid_patch("test.patch.range", {"path": path})
		working.battle.v3["synergy"] = int(value)
	else:
		var paper: Variant = working.battle.v3.get("paper")
		if typeof(paper) != TYPE_DICTIONARY:
			paper = {
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
			working.battle.v3["paper"] = paper
		var field := path.get_slice(".", 1)
		if field == "open":
			if typeof(value) != TYPE_BOOL:
				return _invalid_patch("test.patch.type", {"path": path})
			paper["open"] = bool(value)
		else:
			if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 999:
				return _invalid_patch("test.patch.range", {"path": path})
			paper[field] = int(value)
	summary.append({"op": "set_v3_field", "path": path})
	return null


func _op_set_outcome(working: TestRoomState, op: Dictionary) -> ApiError:
	var value := str(op.get("result", op.get("outcome", "")))
	if value.is_empty() or value == "clear":
		working.battle.outcome = null
		working.battle.phase = "player_action"
		working.result = {"source": "none", "outcome": "", "editable": true}
		return null
	if not (value in ["won", "lost"]):
		return _invalid_patch("test.patch.outcome", {"result": value})
	working.battle.outcome = {
		"battle_id": working.battle.battle_id,
		"result": value,
		"remaining_vitality": int(working.battle.player.get("vitality", 0)),
	}
	working.battle.phase = "finished"
	if working.run != null and not _in_campus_room(working):
		var settled := _settle_map_battle(working, working.battle.outcome)
		if not settled.ok:
			return settled.error
		if working.result.source == "normal":
			working.result.source = "manual"
		return null
	working.result = {"source": "manual", "outcome": value, "editable": true}
	return null


func _judge_now(working: TestRoomState, events: Array[RuleEvent]) -> ApiError:
	if working.battle.phase == "finished" or bool(working.switches.get("freeze_outcome", false)) or _in_campus_room(working):
		return null
	var wrapped := TestContent.new(base_catalog, working.overlay)
	wrapped.battle_switches = working.switches.duplicate(true)
	var judge := BattleEngine.new(wrapped)
	judge._check_battle_outcome(working.battle, events)
	if working.battle.outcome == null and working.battle.ddl <= 0 and not bool(working.switches.get("freeze_ddl", false)):
		judge._finish_battle(working.battle, "lost", "ddl_expired", events)
	if working.battle.outcome != null:
		working.pending_turn.clear()
		if working.run != null:
			var settled := _settle_map_battle(working, working.battle.outcome)
			if not settled.ok:
				return settled.error
			events.append_array(settled.data)
		else:
			working.result = {"source": "normal", "outcome": str(working.battle.outcome.result), "editable": true}
	return null


func _execute_rule(working: TestRoomState, rule: String, args: Dictionary, action: ActionDraft = null) -> GameResult:
	var wrapped := TestContent.new(base_catalog, working.overlay)
	wrapped.battle_switches = working.switches.duplicate(true)
	# Locked vitality must not cause a transient defeat within an atomic command.
	if working.player_locks.has("vitality"):
		wrapped.battle_switches["freeze_outcome"] = true
	var rule_engine := BattleEngine.new(wrapped)
	var before_player := working.battle.player.duplicate(true)
	var applied := rule_engine.apply(working.battle, action, working.rng) if action != null else rule_engine.test_apply_rule_op(working.battle.copy(), rule, args, working.rng)
	if not applied.ok:
		return applied
	var step: BattleStep = applied.data
	working.battle = step.state
	working.rng = step.rng_state.duplicate(true)
	working.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
	var restored_fields := {}
	for field in working.player_locks:
		if working.battle.player.get(field) != before_player.get(field, 0):
			restored_fields[field] = {"before": working.battle.player.get(field), "after": before_player.get(field, 0)}
		working.battle.player[field] = before_player.get(field, 0)
	if int(working.battle.player.vitality) > int(working.battle.player.max_vitality):
		return _failure(GameConstants.ERROR_TEST_LIMIT_REACHED, "test.lock.conflict", {
			"locks": working.player_locks.keys(), "vitality": working.battle.player.vitality,
			"max_vitality": working.battle.player.max_vitality,
		})
	if not restored_fields.is_empty():
		var event_index: int = step.events.back().index + 1 if not step.events.is_empty() else 0
		step.events.append(RuleEvent.new(event_index, &"test_resource_restored", working.test_id, [str(working.battle.player.entity_id)], {"fields": restored_fields}))
	if working.run != null:
		working.run.vitality = int(working.battle.player.vitality)
		working.run.max_vitality = int(working.battle.player.max_vitality)
	return GameResult.success(step)


func _op_run_rule_op(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var rule := str(op.get("rule", ""))
	if rule not in ["end_turn", "draw", "gain_status", "pressure"] or not op.get("args", {}) is Dictionary:
		return _invalid_patch("test.patch.rule", {"rule": rule})
	var action: ActionDraft = null
	if rule == "end_turn":
		if working.battle.phase == "enemy_turn":
			working.battle.phase = "player_action"
		var payload: Dictionary = working.pending_turn.duplicate(true)
		working.pending_turn.clear()
		action = ActionDraft.new(&"end_turn", payload)
	var applied := _execute_rule(working, rule, op.get("args", {}), action)
	if not applied.ok:
		return applied.error
	var step: BattleStep = applied.data
	working.emitted_events.append_array(step.events)
	if step.outcome != null and working.run != null:
		var settled := _settle_map_battle(working, step.outcome)
		if not settled.ok:
			return settled.error
		working.emitted_events.append_array(settled.data)
	elif step.outcome != null:
		working.result = {"source": "normal", "outcome": str(step.outcome.result), "editable": true}
	if step.outcome == null and working.player_locks.has("vitality"):
		var judge_error := _judge_now(working, working.emitted_events)
		if judge_error != null:
			return judge_error
	summary.append({"op": "run_rule_op", "rule": rule})
	return null


func _enforce_switches(working: TestRoomState) -> ApiError:
	var battle := working.battle
	if battle.phase != "finished":
		if (
			not bool(working.switches.get("allow_zero_vitality", false))
			and int(battle.player.get("vitality", 0)) < 1
		):
			return _switch_required("allow_zero_vitality")
		if not bool(working.switches.get("allow_empty_tasks", false)) and battle.tasks.is_empty():
			return _switch_required("allow_empty_tasks")
	var ruleset_id := "" if catalog == null else str(catalog.get_info().ruleset_id)
	var ruleset := _definition(TestContent.new(base_catalog, working.overlay), "ruleset", ruleset_id)
	var battle_rules: Dictionary = ruleset.get("battle", {})
	if (
		not bool(working.switches.get("ignore_unit_slots", false))
		and battle.units.size() > int(battle_rules.get("unit_slots", 3))
	):
		return _switch_required("ignore_unit_slots")
	if (
		not bool(working.switches.get("ignore_relic_slots", false))
		and battle.relics.size() > int(ruleset.get("run", {}).get("relic_slots", 3))
	):
		return _switch_required("ignore_relic_slots")
	if battle.v3.has("paper") and typeof(battle.v3.paper) == TYPE_DICTIONARY:
		var chapters: Array = battle.v3.paper.get("chapters", [])
		if not bool(working.switches.get("ignore_chapter_slots", false)) and chapters.size() > 3:
			return _switch_required("ignore_chapter_slots")
	return null


func _switch_required(key: String) -> ApiError:
	return ApiError.new(
		GameConstants.ERROR_TEST_LIMIT_REACHED,
		"test.switch.required",
		{"switch": key, "reason": "当前状态违反正式玩法限制；先启用对应测试开关。"}
	)


func _op_add_scene(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var definition_id := str(op.get("scene_id", ""))
	if _definition(TestContent.new(base_catalog, working.overlay), "scene", definition_id).is_empty():
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
	var scene_id := _new_instance_id(working, "s")
	working.battle.scene = {
		"scene_id": scene_id,
		"definition_id": definition_id,
		"established_round": working.battle.round_index,
		"pending_random_result": null,
	}
	_register_source(working, scene_id, "scene", definition_id)
	summary.append({"op": "add_scene", "scene_id": definition_id})
	return null


func _op_clear_scene(working: TestRoomState, summary: Array[Dictionary]) -> ApiError:
	if working.battle.scene is Dictionary:
		working.battle.source_registry.erase(str(working.battle.scene.get("scene_id", "")))
	working.battle.scene = null
	summary.append({"op": "clear_scene"})
	return null


func _validate_structure(working: TestRoomState) -> Array[String]:
	var issues: Array[String] = []
	if working.battle == null:
		issues.append("battle is missing")
		return issues
	var battle := working.battle
	if battle.battle_id.is_empty() or battle.encounter_id.is_empty() or battle.character_id.is_empty():
		issues.append("battle identity is missing")
	if battle.phase.is_empty():
		issues.append("battle phase is missing")
	if battle.round_index < 1 or battle.next_instance_seq < 1 or battle.next_creation_order < 1:
		issues.append("battle sequence is invalid")
	if int(battle.player.get("max_vitality", 0)) < 1:
		issues.append("player max vitality is invalid")
	var rng_check := RandomSource.new()
	if not rng_check.restore_state(working.rng).ok:
		issues.append("battle rng is invalid")
	var seen := {}
	var zoned := {}
	for zone in battle.zones:
		for id in battle.zones[zone]:
			var key := str(id)
			if zoned.has(key):
				issues.append("card is in multiple zones: " + key)
				continue
			zoned[key] = true
			if not battle.card_by_id.has(key):
				issues.append("zone references a missing card: " + key)
	if typeof(battle.v3) == TYPE_DICTIONARY and typeof(battle.v3.get("paper")) == TYPE_DICTIONARY:
		for entry in battle.v3.paper.get("chapters", []):
			if typeof(entry) != TYPE_DICTIONARY:
				issues.append("chapter entry is invalid")
				continue
			var key := str(entry.get("card_id", ""))
			if zoned.has(key):
				issues.append("chapter card is also in a zone: " + key)
				continue
			zoned[key] = true
			if not battle.card_by_id.has(key):
				issues.append("chapter references a missing card: " + key)
	for id in battle.card_by_id:
		var card: Dictionary = battle.card_by_id[id]
		if str(card.get("card_id", "")) != str(id):
			issues.append("card key mismatch: " + str(id))
		if not zoned.has(str(id)):
			issues.append("card is not in any zone: " + str(id))
		if str(card.get("definition_id", "")).is_empty():
			issues.append("card definition is missing: " + str(id))
	for id in battle.source_registry:
		var source: Dictionary = battle.source_registry[id]
		var order := int(source.get("creation_order", 0))
		if order < 1 or seen.has(order):
			issues.append("creation order is invalid: " + str(id))
		seen[order] = true
	for id in battle.zones.get("hand", []):
		pass
	for id in battle.retained_card_ids:
		if not battle.zones.get("hand", []).has(id):
			issues.append("retained card is not in hand: " + str(id))
	var holder_ids := {str(battle.player.get("entity_id", "")): true}
	for unit in battle.units:
		var unit_id := str(unit.get("unit_id", ""))
		if unit_id.is_empty() or holder_ids.has(unit_id):
			issues.append("unit id is missing or duplicated: " + unit_id)
		holder_ids[unit_id] = true
		if int(unit.get("vitality", -1)) < 0 or int(unit.get("max_vitality", 0)) < int(unit.get("vitality", 0)):
			issues.append("unit vitality is invalid: " + unit_id)
		if int(unit.get("cooperation", 0)) < 0 or int(unit.get("relax", 0)) < 0:
			issues.append("unit resources are invalid: " + unit_id)
	for task in battle.tasks:
		var task_id := str(task.get("task_id", ""))
		if task_id.is_empty() or holder_ids.has(task_id):
			issues.append("task id is missing or duplicated: " + task_id)
		holder_ids[task_id] = true
		if int(task.get("work_remaining", -1)) < 0 or int(task.get("work_max", 0)) < 1:
			issues.append("task work is invalid: " + task_id)
		if int(task.get("work_remaining", 0)) > int(task.get("work_max", 0)):
			issues.append("task work exceeds max: " + task_id)
		if int(task.get("shield", 0)) < 0:
			issues.append("task shield is invalid: " + task_id)
		if int(task.get("eligible_round", 0)) < 1:
			issues.append("task eligible round is invalid: " + task_id)
	var status_pairs := {}
	for status in battle.statuses:
		var target_id := str(status.get("target_id", ""))
		if not holder_ids.has(target_id):
			issues.append("status holder is missing: " + target_id)
		var pair := "%s|%s" % [status.get("status_id", ""), target_id]
		if status_pairs.has(pair):
			issues.append("status/holder is duplicated: " + pair)
		status_pairs[pair] = true
		if int(status.get("stacks", 0)) < 1:
			issues.append("status stacks must be positive")
		if not battle.source_registry.has(str(status.get("instance_id", ""))):
			issues.append("status source is missing: " + str(status.get("instance_id", "")))
	if battle.scene != null and typeof(battle.scene) != TYPE_DICTIONARY:
		issues.append("scene is invalid")
	if battle.outcome != null:
		if (
			str(battle.outcome.get("battle_id", "")) != battle.battle_id
			or not (str(battle.outcome.get("result", "")) in ["won", "lost"])
		):
			issues.append("battle outcome is invalid")
	if not working.overlay.is_empty() and working.overlay.hash.is_empty():
		issues.append("overlay hash is missing")
	return issues


func _starter_cards(wrapped: TestContent, character: Dictionary, raw: Variant) -> GameResult:
	var cards: Array[Dictionary] = []
	if typeof(raw) == TYPE_ARRAY and not raw.is_empty():
		for item in raw:
			var definition_id := ""
			var upgrade_level := 0
			if typeof(item) == TYPE_STRING:
				definition_id = str(item)
			elif typeof(item) == TYPE_DICTIONARY:
				definition_id = str(item.get("definition_id", ""))
				upgrade_level = int(item.get("upgrade_level", 0))
			if definition_id.is_empty() or _definition(wrapped, "card", definition_id).is_empty():
				return _failure(
					GameConstants.ERROR_CONTENT_INVALID,
					"test.config.card",
					{"definition_id": definition_id}
				)
			cards.append(
				{
					"definition_id": definition_id,
					"card_id": "cap-%d" % cards.size(),
					"upgrade_level": upgrade_level,
				}
			)
	else:
		var ruleset_id := str(wrapped.get_info().ruleset_id)
		var ruleset := _definition(wrapped, "ruleset", ruleset_id)
		var common: Array = ruleset.get("run", {}).get("common_starter_cards", [])
		var starter: Array = common.duplicate()
		starter.append_array(character.get("starter_cards", []))
		for definition_id in starter:
			if _definition(wrapped, "card", str(definition_id)).is_empty():
				return _failure(
					GameConstants.ERROR_CONTENT_INVALID,
					"test.config.starter_card",
					{"definition_id": str(definition_id)}
				)
			cards.append(
				{
					"definition_id": str(definition_id),
					"card_id": "cap-%d" % cards.size(),
					"upgrade_level": 0,
				}
			)
	if cards.is_empty():
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.empty_deck")
	if cards.size() > LIMITS.cards:
		return _failure(GameConstants.ERROR_TEST_LIMIT_REACHED, "test.limit.cards")
	return GameResult.success(cards)


func _starting_relics(wrapped: TestContent, raw: Variant, character_id: String) -> GameResult:
	var relics: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return GameResult.success(relics)
	for item in raw:
		if typeof(item) != TYPE_STRING:
			return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.relic")
		if not RelicPilot.owns_definition(str(item), character_id) or (RelicPilot.expanded(_manifest_id) and (relics.has(str(item)) or relics.size() >= 3)):
			return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.relic", {"relic_id": str(item)})
		if _definition(wrapped, "relic", str(item)).is_empty():
			return _failure(
				GameConstants.ERROR_CONTENT_INVALID, "test.config.relic", {"relic_id": str(item)}
			)
		relics.append(str(item))
	return GameResult.success(relics)


func _default_encounter(catalog_db: ContentDB) -> String:
	var info := catalog_db.get_info()
	var encounters: Array = info.enabled.get("encounter", [])
	if encounters.has("N01"):
		return "N01"
	return str(encounters[0]) if not encounters.is_empty() else ""


func _default_switches(raw: Variant) -> Dictionary:
	var switches := {}
	for key in SWITCHES:
		switches[key] = false
	switches.merge(_explicit_switches(raw), true)
	return switches


func _explicit_switches(raw: Variant) -> Dictionary:
	var switches := {}
	if raw is Dictionary:
		for key in raw:
			if SWITCHES.has(str(key)) and raw[key] is bool:
				switches[str(key)] = raw[key]
	return switches


func _definition(source: Variant, kind: String, id: String) -> Dictionary:
	if source == null:
		return {}
	var result: GameResult = source.get_definition(kind, id)
	return result.data if result.ok and typeof(result.data) == TYPE_DICTIONARY else {}


func _holder_exists(working: TestRoomState, target_id: String) -> bool:
	if target_id == str(working.battle.player.get("entity_id", "")):
		return true
	for unit in working.battle.units:
		if str(unit.get("unit_id", "")) == target_id:
			return true
	for task in working.battle.tasks:
		if str(task.get("task_id", "")) == target_id:
			return true
	return false


func _holder_kind(working: TestRoomState, target_id: String) -> String:
	if target_id == str(working.battle.player.get("entity_id", "")):
		return "player"
	for unit in working.battle.units:
		if str(unit.get("unit_id", "")) == target_id:
			return "unit"
	for task in working.battle.tasks:
		if str(task.get("task_id", "")) == target_id:
			return "task"
	return ""


func _status_index(working: TestRoomState, status_id: String, target_id: String) -> int:
	for index in working.battle.statuses.size():
		var status: Dictionary = working.battle.statuses[index]
		if (
			str(status.get("status_id", "")) == status_id
			and str(status.get("target_id", "")) == target_id
		):
			return index
	return -1


func _zone_of(working: TestRoomState, instance_id: String) -> String:
	for zone in ZONES:
		if working.battle.zones.get(zone, []).has(instance_id):
			return zone
	if _chapter_index(working, instance_id) >= 0:
		return "chapter"
	return ""


func _remove_card(working: TestRoomState, instance_id: String) -> void:
	for zone in ZONES:
		var cards: Array = working.battle.zones.get(zone, [])
		cards.erase(instance_id)
		working.battle.zones[zone] = cards
	var chapter_index := _chapter_index(working, instance_id)
	if chapter_index >= 0:
		var chapters: Array = working.battle.v3.paper.get("chapters", [])
		chapters.remove_at(chapter_index)
		working.battle.v3.paper["chapters"] = chapters
	working.battle.card_by_id.erase(instance_id)
	working.battle.source_registry.erase(instance_id)
	working.battle.retained_card_ids.erase(instance_id)


func _new_instance_id(working: TestRoomState, prefix: String) -> String:
	var instance_id := "%s|%s%d" % [working.battle.battle_id, prefix, working.battle.next_instance_seq]
	working.battle.next_instance_seq += 1
	return instance_id


func _register_source(working: TestRoomState, instance_id: String, kind: String, definition_id: String) -> void:
	working.battle.source_registry[instance_id] = {
		"kind": kind,
		"definition_id": definition_id,
		"creation_order": working.battle.next_creation_order,
	}
	working.battle.next_creation_order += 1


func _referenced(working: TestRoomState, kind: String, id: String) -> bool:
	match kind:
		"card":
			return working.battle.card_by_id.values().any(func(card): return str(card.get("definition_id", "")) == id)
		"status":
			return working.battle.statuses.any(func(status): return str(status.get("status_id", "")) == id)
		"task":
			return working.battle.tasks.any(func(task): return str(task.get("definition_id", "")) == id)
		"unit":
			return working.battle.units.any(func(unit): return str(unit.get("definition_id", "")) == id)
		"relic":
			return working.battle.relics.has(id)
		"encounter":
			return working.battle.encounter_id == id
	return false


func _push_undo(current: TestRoomState) -> void:
	current.undo_stack.append(
		{"core": current.core_snapshot(), "journal_size": current.journal.size(), "journal": current.journal.duplicate(true)}
	)
	while current.undo_stack.size() > TestRoomState.CHECKPOINT_LIMIT:
		current.undo_stack.pop_front()
	current.redo_stack.clear()


func _accepted_result(events: Array, stable: bool) -> ActionResult:
	var session_view := SessionView.new()
	session_view.revision = state.revision if state != null else 0
	session_view.screen = GameConstants.SCREEN_BATTLE
	var snapshot := view()
	session_view.battle = snapshot.get("battle", {})
	session_view.pending_choice = state.pending_choice.copy() if state != null and state.pending_choice != null else null
	var result := ActionResult.new(session_view)
	result.accepted = true
	result.stable = stable
	result.view = session_view
	result.events.assign(events)
	return result


func _reject(error: ApiError) -> ActionResult:
	var view_value := view()
	var session_view := SessionView.new()
	session_view.revision = state.revision if state != null else 0
	session_view.battle = view_value.get("battle", {})
	var result := ActionResult.rejected(error, session_view)
	return result


func _invalid_patch(key: String, details: Dictionary = {}) -> ApiError:
	return ApiError.new(GameConstants.ERROR_TEST_PATCH_INVALID, key, details)


func _limit(field: String) -> ApiError:
	return ApiError.new(
		GameConstants.ERROR_TEST_LIMIT_REACHED, "test.limit." + field, {"limit": LIMITS.get(field, 0)}
	)


func _failure(code: StringName, key: String, details: Dictionary = {}) -> GameResult:
	return GameResult.failure(ApiError.new(code, key, details))


func _new_test_id() -> String:
	var date := Time.get_date_string_from_system().replace("-", "")
	var time := Time.get_time_string_from_system().replace(":", "")
	var suffix := "%06x" % (randi() & 0xFFFFFF)
	return "test-%s-%s-%s" % [date, time, suffix]


func _stamp() -> String:
	var date := Time.get_date_string_from_system().replace("-", "")
	var time := Time.get_time_string_from_system().replace(":", "")
	return "%s-%s-%04d" % [date, time, Time.get_ticks_usec() % 10000]


















