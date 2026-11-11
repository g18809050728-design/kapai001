class_name TestRoomService
extends RefCounted

## Isolated battle-sandbox service used by GameSession. It never writes formal
## saves, never mutates the base catalog, and never executes unregistered ops.

const MANIFEST_ID := "campus_four_year"
const MANIFEST_ROOT := "res://data/four_year"
const ZONES := ["hand", "draw", "discard", "exhaust"]
const PLAYER_FIELDS := ["vitality", "max_vitality", "max_vitality_base", "focus", "relax"]
const BATTLE_ACTIONS := [&"play_card", &"end_turn", &"confirm_choice", &"set_ally_target"]
const CONFIG_KEYS := [
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
	"zone": 300,
	"cards": 500,
	"tasks": 40,
	"units": 32,
	"statuses": 500,
	"relics": 64,
	"value": 9999,
	"ddl": 99,
	"round": 999,
	"ops": 100,
	"definitions": 200,
	"overrides": 1000,
}
const SWITCHES := {
	"allow_zero_vitality": "允许主角精力为 0 并继续实验",
	"allow_empty_tasks": "允许没有敌方任务",
	"freeze_outcome": "不自动判胜/判负",
	"freeze_ddl": "DDL 不随回合递减",
	"freeze_enemy": "跳过敌方自动行动（仍需手动单步）",
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
const OP_KEYS := {
	"set_switch": ["op", "key", "value"],
	"set_player_field": ["op", "field", "value"],
	"adjust_player_field": ["op", "field", "delta"],
	"set_player_lock": ["op", "field", "locked"],
	"add_card": ["op", "definition_id", "zone", "count", "position"],
	"remove_instance": ["op", "instance_id"],
	"duplicate_instance": ["op", "instance_id", "count", "zone"],
	"move_instance": ["op", "instance_id", "zone", "position"],
	"set_zone_order": ["op", "zone", "instance_ids"],
	"shuffle_zone": ["op", "zone"],
	"clear_zone": ["op", "zone"],
	"set_card_field": ["op", "scope", "target", "field", "value"],
	"add_relic": ["op", "relic_id", "position"],
	"remove_relic": ["op", "relic_id", "position"],
	"add_status": ["op", "status_id", "target_id", "stacks", "expiry"],
	"remove_status": ["op", "instance_id", "status_id", "target_id"],
	"set_status_field": ["op", "instance_id", "field", "value"],
	"clear_statuses": ["op", "target_id"],
	"add_task": ["op", "definition_id", "position"],
	"remove_task": ["op", "task_id"],
	"set_task_field": ["op", "task_id", "field", "value"],
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
	"set_outcome": ["op", "result"],
	"clear_outcome": ["op"],
	"run_rule_op": ["op", "rule", "args"],
}

var state: TestRoomState
var base_catalog: ContentDB
var catalog: TestContent
var engine: BattleEngine
var store: TestStore
var view_builder: Callable
var notice: String = ""


func _init(p_store: TestStore = null, p_view_builder: Callable = Callable()) -> void:
	store = p_store if p_store != null else TestStore.new()
	view_builder = p_view_builder


func active() -> bool:
	return state != null


func get_error() -> ApiError:
	return null


func start(config_value: Variant) -> GameResult:
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
	var character_id := str(config.get("character_id", "P01"))
	var loaded := ContentDB.new(MANIFEST_ROOT)
	var loaded_result := loaded.load(MANIFEST_ID)
	if not loaded_result.ok:
		return loaded_result
	var overlay := TestOverlay.from_dictionary(config.get("overlay", {}))
	var wrapped := TestContent.new(loaded, overlay)
	var character := _definition(wrapped, "character", character_id)
	if character == null:
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"test.config.character",
			{"character_id": character_id}
		)
	var encounter_id := str(config.get("encounter_id", ""))
	if encounter_id.is_empty():
		encounter_id = _default_encounter(loaded)
	if _definition(wrapped, "encounter", encounter_id) == null:
		return _failure(
			GameConstants.ERROR_CONTENT_INVALID,
			"test.config.encounter",
			{"encounter_id": encounter_id}
		)
	var cards := _starter_cards(wrapped, character, config.get("cards", []))
	if not cards.ok:
		return cards
	var relics := _starting_relics(wrapped, config.get("relics", []))
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
	new_state.battle = step.state
	new_state.rng = step.rng_state.duplicate(true)
	new_state.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
	new_state.overlay = overlay
	new_state.switches = _default_switches(config.get("switches", {}))
	new_state.result = {"source": "none", "outcome": "", "editable": true}
	new_state.checkpoints = []
	new_state.make_checkpoint("起点", "initial")
	base_catalog = loaded
	catalog = wrapped
	engine = local_engine
	state = new_state
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
	return {
		"screen": "test_room_result" if not str(state.result.get("outcome", "")).is_empty() else "test_room_battle",
		"test": {
			"test_id": state.test_id,
			"branch_id": state.branch_id,
			"revision": state.revision,
			"attempt": state.attempt,
			"paused": state.paused,
			"editing": state.editing,
			"interventions": state.interventions,
			"dirty": state.dirty,
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


func options() -> Dictionary:
	var loaded := ContentDB.new(MANIFEST_ROOT)
	if not loaded.load(MANIFEST_ID).ok:
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
		statuses.append({"id": str(id), "name_key": str(definition.get("name_key", id))})
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
		switches.append({"key": key, "description": SWITCHES[key], "default": false})
	return {
		"manifest_id": info.id,
		"content_version": info.content_version,
		"content_hash": info.content_hash,
		"ruleset_id": info.ruleset_id,
		"characters": characters,
		"encounters": encounters,
		"cards": cards,
		"relics": relics,
		"statuses": statuses,
		"switches": switches,
		"limits": LIMITS.duplicate(true),
	}


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


func preview_patch(context: Variant, patch_value: Variant) -> GameResult:
	var error := _check_context(context)
	if error != null:
		return GameResult.failure(error)
	error = _validate_patch(patch_value)
	if error != null:
		return GameResult.failure(error)
	var patch: Dictionary = patch_value
	var preview := ActionPreview.new()
	preview.revision = state.revision
	var working := state.copy()
	var summary: Array[Dictionary] = []
	for index in patch.ops.size():
		var op_error := _apply_op(working, patch.ops[index], summary)
		if op_error != null:
			op_error.details["path"] = "ops[%d]" % index
			preview.blocking_errors.append(op_error)
			break
	if preview.blocking_errors.is_empty():
		var issues := _validate_structure(working)
		if not issues.is_empty():
			preview.blocking_errors.append(
				ApiError.new(
					GameConstants.ERROR_TEST_STRUCTURE_INVALID,
					"test.patch.structure",
					{"issues": issues}
				)
			)
		else:
			preview.can_submit = true
	preview.known_effects = summary
	return GameResult.success(preview)


func apply_patch(context: Variant, patch_value: Variant) -> ActionResult:
	var error := _check_context(context)
	if error != null:
		return _reject(error)
	error = _validate_patch(patch_value)
	if error != null:
		return _reject(error)
	var patch: Dictionary = patch_value
	var policy := str(patch.get("resolution_policy", "rollback"))
	if state.pending_choice != null:
		if policy == "cancel" or not (policy in ["rollback", "truncate"]):
			return _reject(
				ApiError.new(
					GameConstants.ERROR_TEST_CHOICE_CONFLICT,
					"test.choice.policy",
					{"policy": policy}
				)
			)
	var base_core: Dictionary = state.core_snapshot()
	var journal_size := state.journal.size()
	if state.pending_choice != null and policy == "rollback":
		if state.undo_stack.is_empty():
			return _reject(
				ApiError.new(
					GameConstants.ERROR_TEST_CHECKPOINT_INVALID,
					"test.choice.no_checkpoint",
					{"test_id": state.test_id}
				)
			)
		var entry: Dictionary = state.undo_stack[state.undo_stack.size() - 1]
		base_core = entry.core
		journal_size = int(entry.journal_size)
	var working := TestRoomState.from_core(base_core)
	working.journal.assign(state.journal.slice(0, journal_size))
	working.switches = state.switches.duplicate(true)
	working.overlay = state.overlay.copy()
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack.assign(state.redo_stack.duplicate(true))
	working.checkpoints.assign(state.checkpoints.duplicate(true))
	var summary: Array[Dictionary] = []
	for index in patch.ops.size():
		var op_error := _apply_op(working, patch.ops[index], summary)
		if op_error != null:
			op_error.details["path"] = "ops[%d]" % index
			return _reject(op_error)
	var issues := _validate_structure(working)
	if not issues.is_empty():
		return _reject(
			ApiError.new(
				GameConstants.ERROR_TEST_STRUCTURE_INVALID,
				"test.patch.structure",
				{"issues": issues}
			)
		)
	var only_switches: bool = patch.ops.all(func(entry): return str(entry.get("op", "")) == "set_switch")
	if not only_switches:
		var switch_error := _enforce_switches(working)
		if switch_error != null:
			return _reject(switch_error)
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack = []
	if state.pending_choice != null:
		working.branch_id = state.branch_id + 1
		working.revision = 0
		working.pending_choice = null
		if policy == "truncate":
			working.result = {"source": "truncated", "outcome": "", "editable": true}
	else:
		working.branch_id = state.branch_id
		working.revision = state.revision + 1
	working.editing = false
	working.dirty = true
	working.interventions = state.interventions + patch.ops.size()
	var before_hash := state.state_hash()
	state = working
	state.make_checkpoint("编辑 %d 项" % patch.ops.size(), "edit")
	state.append_journal("edit", {"ops": patch.ops.size(), "policy": policy}, before_hash, state.state_hash())
	notice = "已应用 %d 项" % patch.ops.size()
	return _accepted_result([], state.pending_choice == null)


func preview_action(context: Variant, draft_value: Variant) -> GameResult:
	var error := _check_context(context)
	if error != null:
		return GameResult.failure(error)
	if typeof(draft_value) != TYPE_DICTIONARY:
		return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.action.invalid")
	var draft: Dictionary = draft_value
	var action_type := StringName(draft.get("type", ""))
	if not BATTLE_ACTIONS.has(action_type):
		return _failure(
			GameConstants.ERROR_INVALID_ARGUMENT,
			"test.action.unsupported",
			{"type": String(action_type)}
		)
	if state.editing:
		return _failure(GameConstants.ERROR_TEST_CHOICE_CONFLICT, "test.action.editing")
	if state.pending_choice != null and action_type != &"confirm_choice":
		return _failure(GameConstants.ERROR_CHOICE_PENDING, "error.choice.pending")
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
	if not BATTLE_ACTIONS.has(action_type):
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
	var ddl_before := int(working.battle.ddl)
	var applied := engine.apply(
		working.battle, ActionDraft.new(action_type, payload), working.rng
	)
	if not applied.ok:
		return _reject(applied.error)
	var step: BattleStep = applied.data
	if bool(state.switches.get("freeze_ddl", false)):
		step.state.ddl = ddl_before
	if step.outcome != null and bool(state.switches.get("freeze_outcome", false)):
		step.state.outcome = null
		step.state.phase = "player_action"
		step.outcome = null
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack = []
	working.battle = step.state
	working.rng = step.rng_state.duplicate(true)
	working.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
	working.revision += 1
	working.dirty = true
	if step.outcome != null:
		working.result = {
			"source": "normal",
			"outcome": str(step.outcome.get("result", "")),
			"editable": true,
		}
	var before_hash := state.state_hash()
	state = working
	state.make_checkpoint("命令 %s" % String(action_type), "command")
	state.append_journal(
		"command",
		{"type": String(action_type), "events": step.events.size()},
		before_hash,
		state.state_hash()
	)
	return _accepted_result(step.events, state.pending_choice == null)


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
	restored.editing = false
	restored.dirty = true
	var before_hash := state.state_hash()
	state = restored
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
			{"core": state.core_snapshot(), "journal_size": state.journal.size()}
		)
		var restored := TestRoomState.from_core(entry.core)
		restored.journal.assign(state.journal.slice(0, int(entry.journal_size)))
		restored.checkpoints.assign(state.checkpoints.duplicate(true))
		restored.undo_stack.assign(state.undo_stack.duplicate(true))
		restored.redo_stack.assign(state.redo_stack.duplicate(true))
		restored.branch_id = state.branch_id + 1
		restored.revision = 0
		restored.editing = false
		restored.dirty = true
		state = restored
		return _accepted_result([], true)
	if direction == "redo":
		if state.redo_stack.is_empty():
			return _reject(
				ApiError.new(GameConstants.ERROR_TEST_CHECKPOINT_INVALID, "test.history.empty")
			)
		var entry: Dictionary = state.redo_stack.pop_back()
		state.undo_stack.append(
			{"core": state.core_snapshot(), "journal_size": state.journal.size()}
		)
		var restored := TestRoomState.from_core(entry.core)
		restored.journal.assign(state.journal.slice(0, int(entry.journal_size)))
		restored.checkpoints.assign(state.checkpoints.duplicate(true))
		restored.undo_stack.assign(state.undo_stack.duplicate(true))
		restored.redo_stack.assign(state.redo_stack.duplicate(true))
		restored.branch_id = state.branch_id + 1
		restored.revision = 0
		restored.editing = false
		restored.dirty = true
		state = restored
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
	if origin == "initial":
		var config := state.config.duplicate(true)
		if seed_mode == "new" and not seed.is_empty():
			config["seed"] = seed
		var overlay := state.overlay.to_dictionary()
		config["overlay"] = overlay
		config["switches"] = state.switches.duplicate(true)
		state = null
		var started := start(config)
		if not started.ok:
			return _reject(started.error)
		return _accepted_result([], true)
	var working := state.copy()
	_push_undo(state)
	working.undo_stack.assign(state.undo_stack.duplicate(true))
	working.redo_stack = []
	working.branch_id = 0
	working.revision = 0
	working.attempt = state.attempt + 1
	working.pending_choice = null
	working.result = {"source": "none", "outcome": "", "editable": true}
	working.paused = false
	working.editing = false
	working.dirty = true
	if seed_mode == "new" and not seed.is_empty():
		var rng := RandomSource.new(seed)
		working.rng = rng.export_state().to_dictionary()
		working.seed = seed
	state = working
	return _accepted_result([], true)


func close() -> void:
	state = null
	catalog = null
	base_catalog = null
	engine = null
	notice = ""


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
	var id := "snapshot-%s" % _stamp()
	return store.save(
		"snapshot",
		id,
		name,
		{
			"core": state.core_snapshot(),
			"journal": state.journal.duplicate(true),
			"attempt": state.attempt,
		}
	)


func save_record(name: String) -> GameResult:
	if state == null:
		return _failure(GameConstants.ERROR_TEST_ROOM_NOT_ACTIVE, "test.room.inactive")
	var id := "record-%s" % _stamp()
	return store.save(
		"record",
		id,
		name,
		{
			"core": state.core_snapshot(),
			"journal": state.journal.duplicate(true),
			"state_hash": state.state_hash(),
			"engine_version": GameConstants.GODOT_VERSION,
			"overlay_hash": state.overlay.hash,
		}
	)


func list_files(kind: String) -> Array[Dictionary]:
	return store.list(kind)


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
	var loaded_ok := loaded_catalog.load(MANIFEST_ID)
	if not loaded_ok.ok:
		return _reject(loaded_ok.error)
	var restored := TestRoomState.from_core(core)
	restored.branch_id = int(core.get("branch_id", 0)) + 1
	restored.revision = 0
	restored.journal = []
	restored.checkpoints = []
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
	state = restored
	return _accepted_result([], true)


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
	var loaded_ok := loaded_catalog.load(MANIFEST_ID)
	if not loaded_ok.ok:
		return _reject(loaded_ok.error)
	var restored := TestRoomState.from_core(core)
	restored.branch_id = 0
	restored.revision = 0
	restored.journal = []
	restored.checkpoints = []
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
	state = restored
	return _accepted_result([], true)


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


func _validate_patch(value: Variant) -> ApiError:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid_patch("test.patch.invalid")
	var patch: Dictionary = value
	for key in patch:
		if not PATCH_KEYS.has(key):
			return _invalid_patch("test.patch.unknown_key", {"key": str(key)})
	if int(patch.get("schema_version", 1)) != 1:
		return _invalid_patch("test.patch.schema", {"schema_version": patch.get("schema_version")})
	var ops: Variant = patch.get("ops", [])
	if typeof(ops) != TYPE_ARRAY or ops.is_empty() or ops.size() > LIMITS.ops:
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
	var name := str(op.get("op", ""))
	match name:
		"set_switch":
			return _op_set_switch(working, op)
		"set_player_field":
			return _op_set_player_field(working, op)
		"adjust_player_field":
			return _op_adjust_player_field(working, op)
		"set_player_lock":
			summary.append({"op": name, "field": str(op.get("field", ""))})
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
		"set_outcome":
			return _op_set_outcome(working, op)
		"clear_outcome":
			return _op_set_outcome(working, op)
		"run_rule_op":
			return _op_run_rule_op(working, op, summary)
	return _invalid_patch("test.patch.unknown_op", {"op": name})


func _op_set_switch(working: TestRoomState, op: Dictionary) -> ApiError:
	var key := str(op.get("key", ""))
	if not SWITCHES.has(key):
		return _invalid_patch("test.patch.unknown_switch", {"key": key})
	if typeof(op.get("value")) != TYPE_BOOL:
		return _invalid_patch("test.patch.type", {"field": "value"})
	working.switches[key] = op.value
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
	if not ZONES.has(zone):
		return ApiError.new(
			GameConstants.ERROR_TEST_UNSUPPORTED, "test.patch.zone_unsupported", {"zone": zone}
		)
	var definition := _definition(catalog, "card", definition_id)
	if definition == null:
		return _invalid_patch("test.patch.definition_missing", {"definition_id": definition_id})
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
	if not ZONES.has(zone):
		return ApiError.new(
			GameConstants.ERROR_TEST_UNSUPPORTED, "test.patch.zone_unsupported", {"zone": zone}
		)
	var source_zone := _zone_of(working, instance_id)
	if source_zone == zone:
		return null
	if source_zone.is_empty():
		return _invalid_patch("test.patch.instance_unzoned", {"instance_id": instance_id})
	var source_cards: Array = working.battle.zones.get(source_zone, [])
	source_cards.erase(instance_id)
	var target_cards: Array = working.battle.zones.get(zone, [])
	if target_cards.size() >= LIMITS.zone:
		return _limit("zone")
	var position := int(op.get("position", -1))
	if position >= 0 and position <= target_cards.size():
		target_cards.insert(position, instance_id)
	else:
		target_cards.append(instance_id)
	working.battle.zones[source_zone] = source_cards
	working.battle.zones[zone] = target_cards
	working.battle.retained_card_ids.erase(instance_id)
	summary.append({"op": "move_instance", "instance_id": instance_id, "to": zone})
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
	if _definition(catalog, "card", target) == null:
		return _invalid_patch("test.patch.definition_missing", {"definition_id": target})
	var overlay_error := working.overlay.set_field("card", target, field, value)
	if overlay_error != null:
		return overlay_error
	summary.append({"op": "set_card_field", "scope": scope, "target": target, "field": field})
	return null


func _op_add_relic(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var relic_id := str(op.get("relic_id", ""))
	if _definition(catalog, "relic", relic_id) == null:
		return _invalid_patch("test.patch.definition_missing", {"relic_id": relic_id})
	if working.battle.relics.size() >= LIMITS.relics:
		return _limit("relics")
	var position := int(op.get("position", -1))
	if position >= 0 and position <= working.battle.relics.size():
		working.battle.relics.insert(position, relic_id)
	else:
		working.battle.relics.append(relic_id)
	summary.append({"op": "add_relic", "relic_id": relic_id})
	return null


func _op_remove_relic(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var relic_id := str(op.get("relic_id", ""))
	var position := int(op.get("position", -1))
	var removed := ""
	if not relic_id.is_empty() and working.battle.relics.has(relic_id):
		working.battle.relics.erase(relic_id)
		removed = relic_id
	elif position >= 0 and position < working.battle.relics.size():
		removed = working.battle.relics[position]
		working.battle.relics.remove_at(position)
	else:
		return _invalid_patch("test.patch.relic_missing", {"relic_id": relic_id, "position": position})
	summary.append({"op": "remove_relic", "relic_id": removed})
	return null


func _op_add_status(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var status_id := str(op.get("status_id", ""))
	var target_id := str(op.get("target_id", ""))
	if _definition(catalog, "status", status_id) == null:
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
		var definition := _definition(catalog, "status", status_id)
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
	var definition := _definition(catalog, "task", definition_id)
	if definition == null:
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
		working.battle.tasks[index][field] = str(value)
	else:
		return _invalid_patch("test.patch.field_not_supported", {"field": field})
	summary.append({"op": "set_task_field", "task_id": task_id, "field": field})
	return null


func _op_add_unit(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var definition_id := str(op.get("definition_id", ""))
	var definition := _definition(catalog, "unit", definition_id)
	if definition == null:
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
	var encounter := _definition(catalog, "encounter", encounter_id)
	if encounter == null:
		return _invalid_patch("test.patch.definition_missing", {"encounter_id": encounter_id})
	var members: Array = encounter.get("members", [])
	for member_id in members:
		if _definition(catalog, "task", str(member_id)) == null:
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
			return _invalid_patch(
				"test.patch.range", {"field": "round_index", "task_id": str(task.get("task_id", ""))}
			)
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
	if _definition(catalog, kind, id) == null:
		return _invalid_patch("test.patch.definition_missing", {"kind": kind, "id": id})
	var error := working.overlay.set_field(kind, id, str(op.get("path", "")), op.get("value"))
	if error != null:
		return error
	summary.append({"op": "set_definition_field", "kind": kind, "id": id})
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
	working.result = {"source": "manual", "outcome": value, "editable": true}
	return null


func _op_run_rule_op(working: TestRoomState, op: Dictionary, summary: Array[Dictionary]) -> ApiError:
	var rule := str(op.get("rule", ""))
	match rule:
		"end_turn":
			var applied := engine.apply(working.battle, ActionDraft.new(&"end_turn", {}), working.rng)
			if not applied.ok:
				return applied.error
			var step: BattleStep = applied.data
			working.battle = step.state
			working.rng = step.rng_state.duplicate(true)
			working.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
			summary.append({"op": "run_rule_op", "rule": rule})
			return null
		"draw", "gain_status", "pressure":
			var applied := engine.test_apply_rule_op(
				working.battle, rule, op.get("args", {}), working.rng
			)
			if not applied.ok:
				return applied.error
			var step: BattleStep = applied.data
			working.battle = step.state
			working.rng = step.rng_state.duplicate(true)
			working.pending_choice = TestRoomState.choice_from_dictionary(step.pending_choice)
			summary.append({"op": "run_rule_op", "rule": rule})
			return null
	return _invalid_patch("test.patch.rule", {"rule": rule})


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
	var ruleset := _definition(catalog, "ruleset", ruleset_id)
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
			if definition_id.is_empty() or _definition(wrapped, "card", definition_id) == null:
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
			if _definition(wrapped, "card", str(definition_id)) == null:
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


func _starting_relics(wrapped: TestContent, raw: Variant) -> GameResult:
	var relics: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return GameResult.success(relics)
	for item in raw:
		if typeof(item) != TYPE_STRING:
			return _failure(GameConstants.ERROR_INVALID_ARGUMENT, "test.config.relic")
		if _definition(wrapped, "relic", str(item)) == null:
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
	if typeof(raw) == TYPE_DICTIONARY:
		for key in raw:
			if SWITCHES.has(str(key)) and typeof(raw[key]) == TYPE_BOOL:
				switches[str(key)] = bool(raw[key])
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
	return ""


func _remove_card(working: TestRoomState, instance_id: String) -> void:
	for zone in ZONES:
		var cards: Array = working.battle.zones.get(zone, [])
		cards.erase(instance_id)
		working.battle.zones[zone] = cards
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
		{"core": current.core_snapshot(), "journal_size": current.journal.size()}
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












