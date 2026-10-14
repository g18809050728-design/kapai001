class_name RunService
extends RefCounted
##
## 局流程规则服务（《接口文档》§5；《统一设计文档》§10；《类与方法设计》§4）。
##
## 公开接口：create / preview / apply / settle_battle / make_view。
## 返回 RunStep = {state, events, battle_input, run_summary, rng_states}。
##
## 关键不变量：
##   · 只推进 map / reward / event 三条随机流，绝不推进 battle 流（战斗流归 BattleEngine）。
##   · 非法操作不改变状态：所有写操作都在 RunState.copy_for_write() 上做，
##     校验全部通过才由调用方发布；失败连随机快照都不提交。
##   · 内容抽取错误返回 CONTENT_INVALID，且在扣钱/发牌之前就返回。
##   · 战斗期间精力以 BattleState 为准，settle_battle 一次性写回 RunState。
##   · 幂等键：战斗结算 = battle_id（= 节点 ID）；奖励领取 = (offer_id,item_id)；
##     购买 = stock_id；事件 = event_instance_id；休息 = 节点 ID；学期步骤 = step_id。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const IdsScript := preload("res://src/common/ids.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const RunMapScript := preload("res://src/run/run_map.gd")
const RewardOfferScript := preload("res://src/run/run_reward_offer.gd")
const ShopStateScript := preload("res://src/run/run_shop_state.gd")
const EventStateScript := preload("res://src/run/run_event_state.gd")
const TermSettlementScript := preload("res://src/run/run_term_settlement.gd")
const RunSummaryScript := preload("res://src/run/run_summary.gd")
const RewardGenerator := preload("res://src/run/reward_generator.gd")
const TransactionResolver := preload("res://src/run/transaction_resolver.gd")

const DIFFICULTIES: Array[String] = [
	GameConstants.DIFFICULTY_RELAXED,
	GameConstants.DIFFICULTY_NORMAL,
	GameConstants.DIFFICULTY_HARD,
]

## 休息节点四选一（《统一设计文档》§10）：恢复 / 升级 / 删负担 / 训练合作牌。
const REST_HEAL := "heal"
const REST_UPGRADE := "upgrade"
const REST_REMOVE_BURDEN := "remove_burden"
const REST_TRAIN := "train"
const REST_OPTIONS: Array[String] = [REST_HEAL, REST_UPGRADE, REST_REMOVE_BURDEN, REST_TRAIN]
const TAG_BURDEN := "burden"

## 事件效果 op（事件作用域，与战斗 op 同名不同域）。未知 op 一律 CONTENT_INVALID。
const EV_OP_GAIN_MONEY := "gain_money"
const EV_OP_HEAL := "heal"
const EV_OP_LOSE_VITALITY := "lose_vitality"
const EV_OP_GAIN_CARD := "gain_card"
const EV_OP_GAIN_RELIC := "gain_relic"
const EV_OP_UPGRADE_CARD := "upgrade_card"
const EV_OP_REMOVE_CARD := "remove_card"
const EV_OP_CAREER := "career"
const EVENT_OPS: Array[String] = [
	EV_OP_GAIN_MONEY, EV_OP_HEAL, EV_OP_LOSE_VITALITY, EV_OP_GAIN_CARD, EV_OP_GAIN_RELIC,
	EV_OP_UPGRADE_CARD, EV_OP_REMOVE_CARD, EV_OP_CAREER,
]

## 结局 ID（《统一设计文档》§10.3）。条件不满足不能选；自由探索是保底。
const ENDING_GRAD_RECOMMEND := "grad_recommend"
const ENDING_GRAD_EXAM := "grad_exam"
const ENDING_ABROAD := "abroad"
const ENDING_EMPLOYMENT := "employment"
const ENDING_STARTUP := "startup"
const ENDING_FREE := "free_exploration"

# ── RuleEvent 类型（《接口文档》§8）────────────────────────
const EVENT_RUN_CREATED := "run_created"
const EVENT_NODE_ENTERED := "node_entered"
const EVENT_NODE_COMPLETED := "node_completed"
const EVENT_BATTLE_STARTED := "battle_started"
const EVENT_BATTLE_SETTLED := "battle_settled"
const EVENT_MONEY_GAINED := "money_gained"
const EVENT_REWARD_CREATED := "reward_created"
const EVENT_REWARD_CLAIMED := "reward_claimed"
const EVENT_REWARD_SKIPPED := "reward_skipped"
const EVENT_CARD_GAINED := "card_gained"
const EVENT_RELIC_GAINED := "relic_gained"
const EVENT_CARD_REMOVED := "card_removed"
const EVENT_CARD_UPGRADED := "card_upgraded"
const EVENT_SHOP_OPENED := "shop_opened"
const EVENT_SHOP_ITEM_BOUGHT := "shop_item_bought"
const EVENT_EVENT_OPENED := "event_opened"
const EVENT_EVENT_RESOLVED := "event_resolved"
const EVENT_EVENT_FALLBACK := "event_fallback"
const EVENT_REST_TAKEN := "rest_taken"
const EVENT_TERM_HEALED := "term_healed"
const EVENT_TERM_ENDED := "term_ended"
const EVENT_TERM_STARTED := "term_started"
const EVENT_RUN_FINISHED := "run_finished"
const EVENT_ENDING_CHOSEN := "ending_chosen"

## 需要在奖励界面完成的动作；奖励未处理完时其它写操作一律 CHOICE_PENDING。
const REWARD_ACTIONS: Array[String] = [
	GameConstants.ACTION_CLAIM_REWARD,
	GameConstants.ACTION_SKIP_REWARD,
]

const RUN_ACTIONS: Array[String] = [
	GameConstants.ACTION_ENTER_NODE,
	GameConstants.ACTION_CLAIM_REWARD,
	GameConstants.ACTION_SKIP_REWARD,
	GameConstants.ACTION_BUY_ITEM,
	GameConstants.ACTION_REMOVE_CARD,
	GameConstants.ACTION_CHOOSE_EVENT,
	GameConstants.ACTION_TAKE_REST,
	GameConstants.ACTION_LEAVE_NODE,
	GameConstants.ACTION_CHOOSE_TERM_OPTION,
	GameConstants.ACTION_CHOOSE_ENDING,
	GameConstants.ACTION_ABANDON_RUN,
]

var catalog: ContentDB = null
var _rewards: RewardGenerator = null
var _transactions: TransactionResolver = null


func _init(catalog_ref = null) -> void:
	_rewards = RewardGenerator.new()
	_transactions = TransactionResolver.new()
	set_catalog(catalog_ref)


func set_catalog(catalog_ref) -> void:
	catalog = catalog_ref
	if _rewards != null:
		_rewards.set_catalog(catalog_ref)
	if _transactions != null:
		_transactions.set_catalog(catalog_ref)


func rewards() -> RewardGenerator:
	return _rewards


func transactions() -> TransactionResolver:
	return _transactions
# ── create ────────────────────────────────────────────────

## Result<RunStep>：校验解锁与内容后初始化 RunState 与随机流（《接口文档》§5）。
func create(request: Dictionary, profile: Dictionary = {}) -> Dictionary:
	if not _catalog_ready():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.catalog_missing", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = {}
	var character_id := String(request.get("character_id", ""))
	if character_id.is_empty():
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.missing_character", {})
	var character: Dictionary = catalog.definition(GameConstants.KIND_CHARACTER, character_id)
	if character.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_character", {
			"character_id": character_id,
		})
	var locked_reason := _locked_reason(character_id, profile)
	if not locked_reason.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.character_locked", {
			"character_id": character_id,
			"reason": locked_reason,
		})
	var difficulty := String(request.get("difficulty", GameConstants.DIFFICULTY_NORMAL))
	if not DIFFICULTIES.has(difficulty):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_difficulty", {
			"difficulty": difficulty,
		})
	var requested_manifest := String(request.get("manifest_id", ""))
	if not requested_manifest.is_empty() and requested_manifest != catalog.manifest_id:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.manifest_mismatch", {
			"requested": requested_manifest,
			"loaded": catalog.manifest_id,
		})
	var seed_result := _parse_seed(request.get("seed"))
	if not Result.is_ok(seed_result):
		return seed_result
	var seed_value: int = seed_result["data"]
	var deck_plan := _starter_deck_plan(character)
	if not Result.is_ok(deck_plan):
		return deck_plan
	var relic_plan := _starter_relic_plan(character)
	if not Result.is_ok(relic_plan):
		return relic_plan

	var term_count := _ruleset_term_count()
	if term_count < 1:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.bad_term_count", {
			"term_count": term_count,
		})
	var nodes_per_term := _ruleset_nodes_per_term()
	if nodes_per_term != RunMapScript.layer_count():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.nodes_per_term_mismatch", {
			"ruleset": nodes_per_term,
			"template": RunMapScript.layer_count(),
		})

	var run = RunStateScript.new()
	run.run_id = IdsScript.run_id_from_seed(seed_value)
	run.character_id = character_id
	run.ruleset_id = catalog.ruleset_id
	run.difficulty = difficulty
	run.manifest_id = catalog.manifest_id
	run.term = 1
	run.max_vitality = catalog.difficulty_int(difficulty, "starting_vitality", catalog.run_int("starting_vitality", 72))
	if run.max_vitality <= 0:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.bad_vitality", {
			"max_vitality": run.max_vitality,
		})
	run.vitality = run.max_vitality
	run.money = catalog.run_int("starting_money", 60)
	run.outcome = ""
	for track in TermSettlementScript.TRACKS:
		run.career_progress[track] = 0
	for raw_entry in (deck_plan["data"] as Array):
		var entry: Dictionary = raw_entry
		var count := int(entry["count"])
		for _index in range(count):
			run.add_card(String(entry["definition_id"]), 0, "starter")
	var starter_relic := String(relic_plan["data"])
	if not starter_relic.is_empty():
		if run.equip_relic(starter_relic, catalog.run_int("relic_slots", 6), 1) == null:
			return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.starter_relic_no_slot", {
				"definition_id": starter_relic,
			})
	run.nodes = RunMapScript.build(run.run_id, term_count)

	var rng := RandomSourceScript.new(seed_value)
	var events := []
	_emit(events, EVENT_RUN_CREATED, run.run_id, [], {
		"character_id": character_id,
		"difficulty": difficulty,
		"manifest_id": run.manifest_id,
		"seed": str(seed_value),
		"term_count": term_count,
	})
	return _make_step(run, events, null, null, rng)


# ── 开局校验辅助 ──────────────────────────────────────────

## 传承解锁校验：profile.unlocked_ids 为空或缺失表示不限制（MVP 关闭传承，
## 见《项目计划书》§3.1）；非空时人物必须在清单内。
func _locked_reason(character_id: String, profile: Dictionary) -> String:
	var raw: Variant = profile.get("unlocked_ids")
	if typeof(raw) != TYPE_ARRAY:
		return ""
	var unlocked: Array = raw
	if unlocked.is_empty():
		return ""
	if unlocked.has(character_id):
		return ""
	return "unlocked_ids 未包含该人物"


## Result<Array[{definition_id, count}]>：起始牌组 = common_starter_cards + 人物额外 2 张。
func _starter_deck_plan(character: Dictionary) -> Dictionary:
	var run_rules := catalog.section("run")
	var common: Dictionary = run_rules.get("common_starter_cards", {})
	var plan := []
	var total := 0
	var definition_ids: Array = common.keys()
	definition_ids.sort()
	for raw_id in definition_ids:
		var count := _int(common.get(raw_id), 0)
		if count <= 0:
			continue
		plan.append({"definition_id": String(raw_id), "count": count})
		total += count
	for raw_id in (character.get("starter_cards", []) as Array):
		plan.append({"definition_id": String(raw_id), "count": 1})
		total += 1
	var expected := catalog.run_int("starter_deck_size", 12)
	if total != expected:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.starter_deck_size", {
			"expected": expected,
			"actual": total,
		})
	for raw_entry in plan:
		var entry: Dictionary = raw_entry
		var definition_id := String(entry["definition_id"])
		if catalog.definition(GameConstants.KIND_CARD, definition_id).is_empty():
			return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_starter_card", {
				"definition_id": definition_id,
			})
	return Result.ok(plan)


## Result<String>：初始饰品定义 ID；没有则返回空串。
func _starter_relic_plan(character: Dictionary) -> Dictionary:
	var raw: Variant = character.get("starter_relic_id")
	if raw == null:
		return Result.ok("")
	var definition_id := String(raw)
	if definition_id.is_empty():
		return Result.ok("")
	if catalog.definition(GameConstants.KIND_RELIC, definition_id).is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_starter_relic", {
			"definition_id": definition_id,
		})
	return Result.ok(definition_id)


## Result<int>：seed 为十进制整数字符串（《接口文档》§2），也接受整数。
func _parse_seed(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return Result.ok(value)
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return Result.ok(String(value).to_int())
	if typeof(value) == TYPE_STRING and String(value).is_empty():
		return Result.ok(0)
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.bad_seed", {"seed": str(value)})
# ── preview ───────────────────────────────────────────────

## Result<ActionPreview>：不改状态、不消费随机（《接口文档》§3.3）。
## revision 由会话层填；这里只回答「现在能不能提交、缺什么」。
func preview(state, draft: Dictionary) -> Dictionary:
	if not _catalog_ready():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.catalog_missing", {})
	if state == null:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.no_state", {})
	var action_type := String(draft.get("type", ""))
	if not RUN_ACTIONS.has(action_type):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_action", {"type": action_type})
	var payload: Variant = draft.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	var preview := _empty_preview()
	var gate := _gate_error(state, action_type)
	if not Result.is_ok(gate):
		_block(preview, gate)
		return Result.ok(preview)
	match action_type:
		GameConstants.ACTION_ENTER_NODE:
			_preview_enter_node(state, payload, preview)
		GameConstants.ACTION_CLAIM_REWARD:
			_preview_claim_reward(state, payload, preview)
		GameConstants.ACTION_SKIP_REWARD:
			_preview_skip_reward(state, payload, preview)
		GameConstants.ACTION_BUY_ITEM:
			_preview_transaction(state, draft, preview)
		GameConstants.ACTION_REMOVE_CARD:
			_preview_transaction(state, draft, preview)
		GameConstants.ACTION_CHOOSE_EVENT:
			_preview_choose_event(state, payload, preview)
		GameConstants.ACTION_TAKE_REST:
			_preview_take_rest(state, payload, preview)
		GameConstants.ACTION_LEAVE_NODE:
			_preview_leave_node(state, payload, preview)
		GameConstants.ACTION_CHOOSE_TERM_OPTION:
			_preview_term_option(state, payload, preview)
		GameConstants.ACTION_CHOOSE_ENDING:
			_preview_choose_ending(state, payload, preview)
		GameConstants.ACTION_ABANDON_RUN:
			_preview_abandon(state, payload, preview)
	return Result.ok(preview)


func _empty_preview() -> Dictionary:
	return {
		"revision": 0,
		"can_submit": true,
		"required_selections": [],
		"costs": {},
		"known_effects": [],
		"unknown_effects": [],
		"effective_card": null,
		"blocking_errors": [],
	}


func _block(preview: Dictionary, error_result: Dictionary) -> void:
	preview["can_submit"] = false
	var error: Variant = error_result.get("error")
	if typeof(error) != TYPE_DICTIONARY:
		return
	var error_dict: Dictionary = error
	var details: Variant = error_dict.get("details")
	preview["blocking_errors"].append({
		"code": String(error_dict.get("code", "")),
		"message_key": String(error_dict.get("message_key", "")),
		"details": details if typeof(details) == TYPE_DICTIONARY else {},
	})


# ── apply ─────────────────────────────────────────────────

## Result<RunStep>：在工作副本上执行局流程写操作（《接口文档》§5）。
func apply(state, action: Dictionary, rng_states) -> Dictionary:
	if not _catalog_ready():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.catalog_missing", {})
	if state == null:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.no_state", {})
	var action_type := String(action.get("type", ""))
	if not RUN_ACTIONS.has(action_type):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_action", {"type": action_type})
	var payload: Variant = action.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	var rng := RandomSourceScript.new(0)
	if rng_states != null:
		var restored := rng.restore_state(rng_states)
		if not Result.is_ok(restored):
			return restored
	var working = state.copy_for_write()
	var ctx := {"run": working, "rng": rng, "events": [], "battle_input": null, "run_summary": null}
	var outcome := _dispatch(ctx, action_type, payload)
	if not Result.is_ok(outcome):
		return outcome
	return _make_step(working, ctx["events"], ctx["battle_input"], ctx["run_summary"], rng)


## 稳定边界闸门：一次只处理一个待决界面（《类与方法设计》§2）。
## 战斗未结算时 RunService 不推进任何东西——战斗流只归 BattleEngine。
func _gate_error(run, action_type: String) -> Dictionary:
	if run.is_run_over():
		if action_type == GameConstants.ACTION_CHOOSE_ENDING:
			return Result.ok(null)
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.run_finished", {"outcome": run.outcome})
	if not run.active_battle_id.is_empty():
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.battle_pending", {
			"battle_id": run.active_battle_id,
		})
	if run.pending_reward != null and not run.pending_reward.is_complete():
		if REWARD_ACTIONS.has(action_type):
			return Result.ok(null)
		return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.run.reward_pending", {
			"offer_id": run.pending_reward.offer_id,
		})
	if run.settlement != null and not run.settlement.is_complete():
		if action_type == GameConstants.ACTION_CHOOSE_TERM_OPTION:
			return Result.ok(null)
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.term_settlement_pending", {
			"settlement_id": run.settlement.settlement_id,
		})
	return Result.ok(null)


func _dispatch(ctx: Dictionary, action_type: String, payload: Dictionary) -> Dictionary:
	var gate := _gate_error(ctx["run"], action_type)
	if not Result.is_ok(gate):
		return gate
	match action_type:
		GameConstants.ACTION_ENTER_NODE:
			return _enter_node(ctx, payload)
		GameConstants.ACTION_CLAIM_REWARD:
			return _claim_reward(ctx, payload)
		GameConstants.ACTION_SKIP_REWARD:
			return _skip_reward(ctx, payload)
		GameConstants.ACTION_BUY_ITEM:
			return _buy_item(ctx, payload)
		GameConstants.ACTION_REMOVE_CARD:
			return _remove_card(ctx, payload)
		GameConstants.ACTION_CHOOSE_EVENT:
			return _choose_event(ctx, payload)
		GameConstants.ACTION_TAKE_REST:
			return _take_rest(ctx, payload)
		GameConstants.ACTION_LEAVE_NODE:
			return _leave_node(ctx, payload)
		GameConstants.ACTION_CHOOSE_TERM_OPTION:
			return _choose_term_option(ctx, payload)
		GameConstants.ACTION_CHOOSE_ENDING:
			return _choose_ending(ctx, payload)
		GameConstants.ACTION_ABANDON_RUN:
			return _abandon_run(ctx, payload)
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_action", {"type": action_type})
# ── 节点推进 ──────────────────────────────────────────────

## 进入节点：校验可达性 → 标记 active → 按类型建立局外上下文或 BattleInput。
func _enter_node(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var node_id := String(payload.get("node_id", ""))
	var node = run.find_node(node_id)
	if node == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_node", {"node_id": node_id})
	if node.status == RunNodeState.STATUS_COMPLETED:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_completed", {"node_id": node_id})
	if node.status == RunNodeState.STATUS_ACTIVE:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_active", {"node_id": node_id})
	if node.term != run.term:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.node_other_term", {
			"node_id": node_id,
			"term": node.term,
			"current_term": run.term,
		})
	var reachable: Array = run.reachable_node_ids()
	if not reachable.has(node_id):
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.node_not_reachable", {
			"node_id": node_id,
			"reachable": reachable,
		})
	node.mark_active()
	run.current_node_id = node_id
	_emit(ctx["events"], EVENT_NODE_ENTERED, node_id, [], {
		"kind": node.kind,
		"term": node.term,
		"layer": node.layer,
	})
	if node.kind == RunNodeState.KIND_SHOP:
		return _open_shop(ctx, node)
	if node.kind == RunNodeState.KIND_EVENT:
		return _open_event(ctx, node)
	if node.is_battle():
		return _start_battle(ctx, node)
	return Result.ok(null)


func _start_battle(ctx: Dictionary, node) -> Dictionary:
	var run = ctx["run"]
	var pool := _resolve_encounter_pool(run, node)
	if pool.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.no_encounter", {
			"node_id": node.node_id,
			"kind": node.kind,
			"term": run.term,
		})
	var picked := _pick(pool, ctx["rng"])
	if not Result.is_ok(picked):
		return picked
	var encounter_id := String(picked["data"])
	node.context["encounter_id"] = encounter_id
	run.active_battle_id = node.battle_id()
	run.active_encounter_id = encounter_id
	ctx["battle_input"] = _battle_input(run, node, encounter_id)
	_emit(ctx["events"], EVENT_BATTLE_STARTED, node.node_id, [], {
		"battle_id": run.active_battle_id,
		"encounter_id": encounter_id,
		"node_kind": node.kind,
	})
	return Result.ok(null)


func _open_shop(ctx: Dictionary, node) -> Dictionary:
	var run = ctx["run"]
	var generated := _rewards.generate_shop(node, run, ctx["rng"])
	if not Result.is_ok(generated):
		return generated
	node.context["shop"] = generated["data"]
	_emit(ctx["events"], EVENT_SHOP_OPENED, node.node_id, [], {
		"shop_id": node.context["shop"].shop_id,
		"stocks": node.context["shop"].stocks.size(),
	})
	return Result.ok(null)


## 事件节点：候选抽取用 map 流；同局同 ID 至多出现一次（进入即记，离开也算见过）。
## 没有任何合法事件时按《统一设计文档》§10.2 替换为普通战斗。
func _open_event(ctx: Dictionary, node) -> Dictionary:
	var run = ctx["run"]
	var pool := _event_pool(run, run.term)
	if pool.is_empty():
		node.kind = RunNodeState.KIND_NORMAL
		node.context.erase("event")
		_emit(ctx["events"], EVENT_EVENT_FALLBACK, node.node_id, [], {
			"reason": "empty_event_pool",
			"term": run.term,
		})
		return _start_battle(ctx, node)
	var picked := _pick(pool, ctx["rng"])
	if not Result.is_ok(picked):
		return picked
	var definition_id := String(picked["data"])
	var definition: Dictionary = catalog.definition(GameConstants.KIND_EVENT, definition_id)
	if definition.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_event", {
			"definition_id": definition_id,
		})
	var instance = EventStateScript.create(run.allocate_instance_id(), node.node_id, definition_id)
	var frozen := _freeze_event_candidates(run, definition, ctx["rng"])
	if not Result.is_ok(frozen):
		return frozen
	instance.frozen_candidates = frozen["data"]
	node.context["event"] = instance
	run.seen_event_ids[definition_id] = true
	_emit(ctx["events"], EVENT_EVENT_OPENED, node.node_id, [], {
		"definition_id": definition_id,
		"event_instance_id": instance.event_instance_id,
	})
	return Result.ok(null)


## 离开节点：商店随时可走；事件必须先选一项（离开无变化也是选项）；休息必须先行动；
## 战斗节点必须已结算且奖励已处理完。完成后按层推进：首领节点走学期结算。
func _leave_node(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var node_id := String(payload.get("node_id", ""))
	var node = run.current_node()
	if node == null or node.node_id != node_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.not_current_node", {"node_id": node_id})
	if node.status != RunNodeState.STATUS_ACTIVE:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_not_active", {"node_id": node_id})
	if node.is_battle():
		if not run.active_battle_id.is_empty():
			return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.battle_pending", {
				"battle_id": run.active_battle_id,
			})
		if run.pending_reward != null and not run.pending_reward.is_complete():
			return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.run.reward_pending", {
				"offer_id": run.pending_reward.offer_id,
			})
	elif node.kind == RunNodeState.KIND_EVENT:
		var instance = node.context.get("event")
		if instance == null or not instance.is_resolved():
			return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.event_unresolved", {
				"node_id": node_id,
			})
	elif node.kind == RunNodeState.KIND_REST:
		if not bool(node.context.get("used", false)):
			return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.rest_not_taken", {"node_id": node_id})
	run.pending_reward = null
	node.mark_completed()
	run.node_path.append(node.node_id)
	_emit(ctx["events"], EVENT_NODE_COMPLETED, node.node_id, [], {
		"kind": node.kind,
		"term": node.term,
		"layer": node.layer,
	})
	if node.layer >= _ruleset_nodes_per_term():
		return _complete_term(ctx)
	return Result.ok(null)


## 学期结束：恢复最大精力的 term_heal_percent（向下取整，直接写回），
## 然后建立学期结算步骤（方向奖励；第 5 学期开始前追加履历方向）。
func _complete_term(ctx: Dictionary) -> Dictionary:
	var run = ctx["run"]
	if run.term >= _ruleset_term_count():
		return Result.ok(null)
	var percent := catalog.run_int("term_heal_percent", 20)
	var before: int = run.vitality
	run.vitality = mini(run.max_vitality, run.vitality + catalog.scaled_by_percent(run.max_vitality, percent))
	if run.vitality != before:
		_emit(ctx["events"], EVENT_TERM_HEALED, run.current_node_id, [], {
			"before": before,
			"after": run.vitality,
			"percent": percent,
		})
	var settlement = TermSettlementScript.create(run.allocate_instance_id(), run.term)
	var tags := []
	if not run.career_direction.is_empty() and _rewards.has_card_pool("term", run, [run.career_direction]):
		tags = [run.career_direction]
	var candidates := _rewards.card_candidates_by_weights(
		"term", _int(catalog.section("rewards").get("candidate_count"), 3), run, ctx["rng"], tags
	)
	if not Result.is_ok(candidates):
		return candidates
	settlement.add_step("step_direction", TermSettlementScript.STEP_DIRECTION_REWARD, candidates["data"], true)
	if run.term + 1 == 5 and run.career_direction.is_empty() and catalog.run_int("career_track_cap", 3) > 0:
		settlement.add_step("step_career", TermSettlementScript.STEP_CAREER_TRACK, TermSettlementScript.TRACK_CHOICES, false)
	run.settlement = settlement
	_emit(ctx["events"], EVENT_TERM_ENDED, run.current_node_id, [], {
		"term": run.term,
		"settlement_id": settlement.settlement_id,
		"steps": settlement.steps.size(),
	})
	return Result.ok(null)


# ── 内容池 ────────────────────────────────────────────────

## 开战遭遇池：elite 空池回退普通池（品质/内容缺项走重归一化，见《常量与规则配置》§3）。
func _resolve_encounter_pool(run, node, kind_override: String = "") -> Array:
	var kind: String = kind_override if not kind_override.is_empty() else String(node.kind)
	var pool := _encounter_pool(run.term, kind)
	if pool.is_empty() and kind == RunNodeState.KIND_ELITE:
		pool = _encounter_pool(run.term, RunNodeState.KIND_NORMAL)
	return pool


func _encounter_pool(term_value: int, kind: String) -> Array:
	var pool := []
	for raw_id in catalog.get_candidates({"kind": GameConstants.KIND_ENCOUNTER}):
		var definition_id := String(raw_id)
		var definition: Dictionary = catalog.definition(GameConstants.KIND_ENCOUNTER, definition_id)
		if String(definition.get("kind", "")) != kind:
			continue
		if not _encounter_legal(definition, term_value):
			continue
		pool.append(definition_id)
	return pool


## 遭遇合法 = 自身 terms/allowed_terms 合法，且所有成员任务的 terms 合法
## （任务 terms 是唯一来源，见 data/definitions/tasks.json）。
func _encounter_legal(definition: Dictionary, term_value: int) -> bool:
	if not _term_legal(definition, term_value):
		return false
	for raw_task_id in (definition.get("tasks", []) as Array):
		var task_definition: Dictionary = catalog.definition(GameConstants.KIND_TASK, String(raw_task_id))
		if task_definition.is_empty():
			return false
		if not _term_legal(task_definition, term_value):
			return false
	return true


func _event_pool(run, term_value: int) -> Array:
	var pool := []
	for raw_id in catalog.get_candidates({"kind": GameConstants.KIND_EVENT}):
		var definition_id := String(raw_id)
		if run.seen_event_ids.has(definition_id):
			continue
		var definition: Dictionary = catalog.definition(GameConstants.KIND_EVENT, definition_id)
		if definition.is_empty():
			continue
		if not _term_legal(definition, term_value):
			continue
		pool.append(definition_id)
	return pool


## terms/allowed_terms 写成 [lo, hi] 或 [n]；没有该字段表示不限学期。
func _term_legal(definition: Dictionary, term_value: int) -> bool:
	for key in ["terms", "allowed_terms"]:
		var raw: Variant = definition.get(key)
		if typeof(raw) != TYPE_ARRAY:
			continue
		var ranges: Array = raw
		if ranges.size() >= 2:
			if term_value < _int(ranges[0], 1) or term_value > _int(ranges[1], 1):
				return false
		elif ranges.size() == 1 and term_value != _int(ranges[0], 1):
			return false
	return true
# ── 奖励领取 ──────────────────────────────────────────────

## 领取奖励项：候选在生成时已冻结，这里只校验「项还在 pending」与候选归属（幂等键 = item_id）。
func _claim_reward(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var offer = run.pending_reward
	if offer == null:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_reward", {})
	var offer_id := String(payload.get("offer_id", ""))
	if offer_id != offer.offer_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_offer", {"offer_id": offer_id})
	var item_id := String(payload.get("item_id", ""))
	var item = offer.find_item(item_id)
	if item == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_reward_item", {"item_id": item_id})
	if item.status != RewardOfferScript.STATUS_PENDING:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.reward_item_resolved", {
			"item_id": item_id,
			"status": item.status,
		})
	var candidate_id := String(payload.get("candidate_id", ""))
	if candidate_id.is_empty() and item.candidates.size() == 1:
		candidate_id = String(item.candidates[0])
	if item.kind == RewardOfferScript.ITEM_CARD:
		if candidate_id.is_empty() or not item.candidates.has(candidate_id):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.bad_reward_candidate", {
				"item_id": item_id,
				"candidates": item.candidates,
			})
		if catalog.definition(GameConstants.KIND_CARD, candidate_id).is_empty():
			return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_card", {
				"definition_id": candidate_id,
			})
		var card = run.add_card(candidate_id, 0, "reward")
		item.status = RewardOfferScript.STATUS_CLAIMED
		item.chosen_id = candidate_id
		_emit(ctx["events"], EVENT_CARD_GAINED, run.current_node_id, [card.card_id], {
			"definition_id": candidate_id,
			"source": "reward",
		})
		return Result.ok(null)
	if item.kind == RewardOfferScript.ITEM_RELIC:
		return _claim_reward_relic(ctx, run, offer, item, candidate_id, payload, item_id)
	return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_reward_kind", {"kind": item.kind})


func _claim_reward_relic(ctx: Dictionary, run, offer, item, candidate_id: String, payload: Dictionary, item_id: String) -> Dictionary:
	if candidate_id.is_empty() or not item.candidates.has(candidate_id):
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.bad_reward_candidate", {
			"item_id": item_id,
			"candidates": item.candidates,
		})
	if catalog.definition(GameConstants.KIND_RELIC, candidate_id).is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_relic", {
			"definition_id": candidate_id,
		})
	if run.has_relic_definition(candidate_id):
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.relic_owned", {
			"definition_id": candidate_id,
		})
	var relic_slots: int = catalog.run_int("relic_slots", 6)
	var replace_id := String(payload.get("replace_relic_id", ""))
	var acquired_order: int = run.relics.size() + 1
	var relic = null
	if run.relics.size() >= relic_slots or not replace_id.is_empty():
		if replace_id.is_empty():
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {
				"relic_slots": relic_slots,
			})
		relic = run.replace_relic(replace_id, candidate_id, acquired_order)
		if relic == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {
				"relic_id": replace_id,
			})
	else:
		relic = run.equip_relic(candidate_id, relic_slots, acquired_order)
		if relic == null:
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {})
	item.status = RewardOfferScript.STATUS_CLAIMED
	item.chosen_id = candidate_id
	_emit(ctx["events"], EVENT_RELIC_GAINED, run.current_node_id, [relic.relic_id], {
		"definition_id": candidate_id,
		"slot": relic.slot,
		"source": offer.source_kind,
	})
	return Result.ok(null)


## 跳过奖励项：只有允许跳过的项可以 skip；已处理项返回 ALREADY_RESOLVED。
func _skip_reward(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var offer = run.pending_reward
	if offer == null:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_reward", {})
	var offer_id := String(payload.get("offer_id", ""))
	if offer_id != offer.offer_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_offer", {"offer_id": offer_id})
	var item_id := String(payload.get("item_id", ""))
	var item = offer.find_item(item_id)
	if item == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_reward_item", {"item_id": item_id})
	if item.status != RewardOfferScript.STATUS_PENDING:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.reward_item_resolved", {
			"item_id": item_id,
			"status": item.status,
		})
	if not item.skippable:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.run.reward_item_mandatory", {"item_id": item_id})
	item.status = RewardOfferScript.STATUS_SKIPPED
	_emit(ctx["events"], EVENT_REWARD_SKIPPED, run.current_node_id, [], {"item_id": item_id, "kind": item.kind})
	return Result.ok(null)


# ── 商店交易 ──────────────────────────────────────────────

## 购买：价格现算、库存冻结，全部校验通过才整体应用（TransactionResolver）。
func _buy_item(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var plan := _transactions.prepare(run, {"type": GameConstants.ACTION_BUY_ITEM, "payload": payload})
	if not Result.is_ok(plan):
		return plan
	var applied := _transactions.apply(run, plan["data"])
	if not Result.is_ok(applied):
		return applied
	var stock_id := String(plan["data"].get("stock_id", ""))
	_emit(ctx["events"], EVENT_SHOP_ITEM_BOUGHT, run.current_node_id, [], {
		"stock_id": stock_id,
		"price": int(plan["data"].get("price", 0)),
		"money": run.money,
		"money_after": run.money,
		"definition_id": String(plan["data"].get("card_definition_id", plan["data"].get("relic_definition_id", ""))),
	})
	return Result.ok(null)


## 商店删牌：每店 1 次、牌组下限 5、价格随全局删牌次数递增。
func _remove_card(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var plan := _transactions.prepare(run, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": payload})
	if not Result.is_ok(plan):
		return plan
	var card_instance_id := String(plan["data"].get("card_instance_id", ""))
	var applied := _transactions.apply(run, plan["data"])
	if not Result.is_ok(applied):
		return applied
	_emit(ctx["events"], EVENT_CARD_REMOVED, run.current_node_id, [card_instance_id], {
		"price": int(plan["data"].get("price", 0)),
		"money": run.money,
		"reason": "shop",
		"removals_used": run.removals_used,
	})
	return Result.ok(null)
# ── 休息 ──────────────────────────────────────────────────

## 休息四选一（《统一设计文档》§10）：恢复 25% / 升级 1 张 / 删 1 张负担牌 / 训练合作牌。
func _take_rest(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var node = run.current_node()
	if node == null or node.kind != RunNodeState.KIND_REST:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_rest_node", {})
	if node.status != RunNodeState.STATUS_ACTIVE:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_not_active", {})
	if bool(node.context.get("used", false)):
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.rest_already_taken", {
			"node_id": node.node_id,
		})
	var node_id := String(payload.get("node_id", ""))
	if not node_id.is_empty() and node_id != node.node_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.not_current_node", {"node_id": node_id})
	var option_id := String(payload.get("option_id", ""))
	if not REST_OPTIONS.has(option_id):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_rest_option", {
			"option_id": option_id,
		})
	var card_instance_id := String(payload.get("card_instance_id", ""))
	var check := _rest_validate(run, option_id, card_instance_id)
	if not Result.is_ok(check):
		return check
	if option_id == REST_HEAL:
		var percent := catalog.run_int("rest_heal_percent", 25)
		var before: int = run.vitality
		run.vitality = mini(run.max_vitality, run.vitality + catalog.scaled_by_percent(run.max_vitality, percent))
		_emit(ctx["events"], EVENT_REST_TAKEN, node.node_id, [], {
			"option_id": option_id,
			"before": before,
			"after": run.vitality,
			"percent": percent,
		})
	elif option_id == REST_REMOVE_BURDEN:
		run.remove_card(card_instance_id)
		_emit(ctx["events"], EVENT_CARD_REMOVED, node.node_id, [card_instance_id], {"reason": "rest"})
	else:
		var card = run.find_card(card_instance_id)
		card.upgrade_level += 1
		_emit(ctx["events"], EVENT_CARD_UPGRADED, node.node_id, [card_instance_id], {
			"definition_id": card.definition_id,
			"upgrade_level": card.upgrade_level,
			"option_id": option_id,
		})
	node.context["used"] = true
	return Result.ok(null)


## 休息选项校验（apply 与 preview 共用一套条件）。
func _rest_validate(run, option_id: String, card_instance_id: String) -> Dictionary:
	if option_id == REST_HEAL:
		return Result.ok(null)
	var minimum: int = catalog.run_int("minimum_deck_size", 5)
	var max_upgrades: int = catalog.run_int("max_card_upgrades", 1)
	if option_id == REST_UPGRADE or option_id == REST_TRAIN:
		if card_instance_id.is_empty():
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.need_card", {"option_id": option_id})
		var card = run.find_card(card_instance_id)
		if card == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.unknown_card", {
				"card_instance_id": card_instance_id,
			})
		if option_id == REST_TRAIN:
			var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
			if String(definition.get("type", "")) != GameConstants.CARD_COOPERATION:
				return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.not_cooperation", {
					"definition_id": card.definition_id,
				})
		if card.upgrade_level >= max_upgrades:
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.rest.upgrade_max", {
				"card_instance_id": card_instance_id,
				"max": max_upgrades,
			})
		return Result.ok(null)
	if option_id == REST_REMOVE_BURDEN:
		if card_instance_id.is_empty():
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.need_card", {"option_id": option_id})
		var card = run.find_card(card_instance_id)
		if card == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.unknown_card", {
				"card_instance_id": card_instance_id,
			})
		var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
		if not (definition.get("tags", []) as Array).has(TAG_BURDEN):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.not_burden", {
				"definition_id": card.definition_id,
			})
		if run.cards.size() <= minimum:
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.rest.deck_minimum", {"minimum": minimum})
		return Result.ok(null)
	return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_rest_option", {"option_id": option_id})


## 休息选项的可用性与禁用原因（视图用；不改状态）。
func _rest_option_blocking(run, option_id: String) -> Array:
	if option_id == REST_HEAL:
		return []
	var candidates := _rest_target_candidates(run, option_id)
	if not candidates.is_empty():
		return []
	return ["error.rest.no_target"]


func _rest_target_candidates(run, option_id: String) -> Array:
	var matched := []
	if option_id == REST_REMOVE_BURDEN and run.cards.size() <= catalog.run_int("minimum_deck_size", 5):
		return matched
	var max_upgrades: int = catalog.run_int("max_card_upgrades", 1)
	for card in run.cards:
		var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
		if option_id == REST_UPGRADE:
			if card.upgrade_level < max_upgrades:
				matched.append(card)
		elif option_id == REST_TRAIN:
			if String(definition.get("type", "")) == GameConstants.CARD_COOPERATION and card.upgrade_level < max_upgrades:
				matched.append(card)
		elif option_id == REST_REMOVE_BURDEN:
			if (definition.get("tags", []) as Array).has(TAG_BURDEN):
				matched.append(card)
	return matched


# ── 事件 ──────────────────────────────────────────────────

## 事件选项一次性结算：先整体校验（成本 + 全部收益），再应用。
func _choose_event(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var node = run.current_node()
	if node == null or node.kind != RunNodeState.KIND_EVENT:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_event_node", {})
	var instance = node.context.get("event")
	if instance == null:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_event_instance", {})
	if instance.is_resolved():
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.event_resolved", {
			"event_instance_id": instance.event_instance_id,
		})
	var event_instance_id := String(payload.get("event_instance_id", ""))
	if not event_instance_id.is_empty() and event_instance_id != instance.event_instance_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_event_instance", {
			"event_instance_id": event_instance_id,
		})
	var definition: Dictionary = catalog.definition(GameConstants.KIND_EVENT, instance.definition_id)
	if definition.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_event", {
			"definition_id": instance.definition_id,
		})
	var option := _find_event_option(definition, String(payload.get("option_id", "")))
	if option.is_empty():
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_event_option", {
			"option_id": payload.get("option_id", ""),
		})
	var raw_selection: Variant = payload.get("selection_ids")
	var selection_ids: Array = raw_selection if typeof(raw_selection) == TYPE_ARRAY else []
	var replace_relic_id := String(payload.get("replace_relic_id", ""))
	var check := _event_option_error(ctx, run, option, instance, selection_ids, replace_relic_id)
	if not Result.is_ok(check):
		return check
	var cost: Dictionary = option.get("cost", {})
	var money_cost := _int(cost.get("money"), 0)
	var vitality_cost := _int(cost.get("vitality"), 0)
	if money_cost > 0:
		run.money -= money_cost
		_emit(ctx["events"], EVENT_MONEY_GAINED, node.node_id, [], {"amount": -money_cost, "money": run.money})
	if vitality_cost > 0:
		run.vitality -= vitality_cost
		_emit(ctx["events"], EVENT_NODE_ENTERED, node.node_id, [], {"vitality": run.vitality})
	var applied := _apply_event_effects(ctx, run, option, instance, selection_ids, replace_relic_id, false)
	if not Result.is_ok(applied):
		return applied
	instance.resolved_option_id = String(option.get("option_id", ""))
	_emit(ctx["events"], EVENT_EVENT_RESOLVED, node.node_id, [], {
		"event_instance_id": instance.event_instance_id,
		"definition_id": instance.definition_id,
		"option_id": instance.resolved_option_id,
	})
	return Result.ok(null)


func _find_event_option(definition: Dictionary, option_id: String) -> Dictionary:
	for raw_option in (definition.get("options", []) as Array):
		var option: Dictionary = raw_option
		if String(option.get("option_id", "")) == option_id:
			return option
	return {}


## 事件选项校验：成本 + 每个收益 op（复用 dry_run 版的收益应用，保证与执行同一套条件）。
func _event_option_error(ctx, run, option: Dictionary, instance, selection_ids: Array, replace_relic_id: String) -> Dictionary:
	var cost: Dictionary = option.get("cost", {})
	var money_cost := _int(cost.get("money"), 0)
	if money_cost > 0 and run.money < money_cost:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.event.not_enough_money", {
			"needed": money_cost,
			"have": run.money,
		})
	var vitality_cost := _int(cost.get("vitality"), 0)
	if vitality_cost > 0 and run.vitality - vitality_cost < 1:
		return Result.fail(GameConstants.ERROR_INSUFFICIENT_RESOURCE, "error.event.not_enough_vitality", {
			"needed": vitality_cost,
			"have": run.vitality,
		})
	var effects: Array = option.get("effects", [])
	for raw_effect in effects:
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if not EVENT_OPS.has(op):
			return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.unknown_op", {"op": op})
		var checked := Result.ok(null)
		if op == EV_OP_GAIN_CARD:
			checked = _gain_event_card(ctx, run, effect, instance, option, selection_ids, true)
		elif op == EV_OP_GAIN_RELIC:
			checked = _gain_event_relic(ctx, run, effect, instance, option, selection_ids, replace_relic_id, true)
		elif op == EV_OP_UPGRADE_CARD:
			checked = _upgrade_event_card(ctx, run, effect, selection_ids, true)
		elif op == EV_OP_REMOVE_CARD:
			checked = _remove_event_card(ctx, run, effect, selection_ids, true)
		elif op == EV_OP_CAREER:
			checked = _gain_event_career(ctx, run, effect, true)
		if not Result.is_ok(checked):
			return checked
	return Result.ok(null)


func _apply_event_effects(ctx: Dictionary, run, option: Dictionary, instance, selection_ids: Array, replace_relic_id: String, dry_run: bool) -> Dictionary:
	var effects: Array = option.get("effects", [])
	for raw_effect in effects:
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		var applied := Result.ok(null)
		if op == EV_OP_GAIN_MONEY:
			var amount := _int(effect.get("amount"), 0)
			if not dry_run:
				run.money += amount
				_emit(ctx["events"], EVENT_MONEY_GAINED, run.current_node_id, [], {"amount": amount, "money": run.money})
		elif op == EV_OP_HEAL:
			var amount := _int(effect.get("amount"), 0)
			if not dry_run:
				var before: int = run.vitality
				run.vitality = mini(run.max_vitality, run.vitality + amount)
				_emit(ctx["events"], EVENT_TERM_HEALED, run.current_node_id, [], {"before": before, "after": run.vitality})
		elif op == EV_OP_LOSE_VITALITY:
			var amount := _int(effect.get("amount"), 0)
			if not dry_run:
				run.vitality = maxi(0, run.vitality - amount)
				_emit(ctx["events"], EVENT_NODE_ENTERED, run.current_node_id, [], {"vitality": run.vitality})
		elif op == EV_OP_GAIN_CARD:
			applied = _gain_event_card(ctx, run, effect, instance, option, selection_ids, dry_run)
		elif op == EV_OP_GAIN_RELIC:
			applied = _gain_event_relic(ctx, run, effect, instance, option, selection_ids, replace_relic_id, dry_run)
		elif op == EV_OP_UPGRADE_CARD:
			applied = _upgrade_event_card(ctx, run, effect, selection_ids, dry_run)
		elif op == EV_OP_REMOVE_CARD:
			applied = _remove_event_card(ctx, run, effect, selection_ids, dry_run)
		elif op == EV_OP_CAREER:
			applied = _gain_event_career(ctx, run, effect, dry_run)
		if not Result.is_ok(applied):
			return applied
	return Result.ok(null)
# ── 事件收益（dry_run=true 时只校验，用于选项预览与执行前的整体校验）──

## 获得卡：显式 card_id 直接发放；带 rarity 的走进入时冻结的候选。
## 池为空时按内容声明的 fallback_money 折算，否则 CONTENT_INVALID（不发明数值）。
func _gain_event_card(ctx, run, effect: Dictionary, instance, option: Dictionary, selection_ids: Array, dry_run: bool) -> Dictionary:
	var option_id := String(option.get("option_id", ""))
	var candidates: Array = instance.candidates_for(option_id)
	var definition_id := ""
	if effect.has("card_id"):
		definition_id = String(effect.get("card_id"))
	else:
		if candidates.is_empty():
			return _event_pool_fallback(ctx, run, effect, option_id, "card", dry_run)
		if not selection_ids.is_empty():
			definition_id = String(selection_ids[0])
		elif candidates.size() == 1:
			definition_id = String(candidates[0])
		else:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.need_card_selection", {
				"option_id": option_id,
				"candidates": candidates,
			})
		if not candidates.has(definition_id):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.bad_candidate", {
				"candidate_id": definition_id,
				"candidates": candidates,
			})
	if definition_id.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.missing_card_id", {
			"option_id": option_id,
		})
	if catalog.definition(GameConstants.KIND_CARD, definition_id).is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_card", {
			"definition_id": definition_id,
		})
	if dry_run:
		return Result.ok(null)
	var card = run.add_card(definition_id, _int(effect.get("upgrade_level"), 0), "event")
	_emit_event(ctx, EVENT_CARD_GAINED, run.current_node_id, [card.card_id], {
		"definition_id": definition_id,
		"source": "event",
	})
	return Result.ok(null)


## 获得饰品：显式 relic_id 直接发放；带 rarity 的走冻结候选；同名已持有按 fallback_money 折算。
func _gain_event_relic(ctx, run, effect: Dictionary, instance, option: Dictionary, selection_ids: Array, replace_relic_id: String, dry_run: bool) -> Dictionary:
	var option_id := String(option.get("option_id", ""))
	var candidates: Array = instance.candidates_for(option_id)
	var definition_id := ""
	if effect.has("relic_id"):
		definition_id = String(effect.get("relic_id"))
	else:
		if candidates.is_empty():
			return _event_pool_fallback(ctx, run, effect, option_id, "relic", dry_run)
		if not selection_ids.is_empty():
			definition_id = String(selection_ids[0])
		elif candidates.size() == 1:
			definition_id = String(candidates[0])
		else:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.need_relic_selection", {
				"option_id": option_id,
				"candidates": candidates,
			})
		if not candidates.has(definition_id):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.bad_candidate", {
				"candidate_id": definition_id,
				"candidates": candidates,
			})
	if definition_id.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.missing_relic_id", {
			"option_id": option_id,
		})
	if catalog.definition(GameConstants.KIND_RELIC, definition_id).is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_relic", {
			"definition_id": definition_id,
		})
	if run.has_relic_definition(definition_id):
		return _event_pool_fallback(ctx, run, effect, option_id, "relic_owned", dry_run)
	var relic_slots: int = catalog.run_int("relic_slots", 6)
	var slot_full: bool = run.relics.size() >= relic_slots
	if dry_run:
		if slot_full and replace_relic_id.is_empty():
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {
				"relic_slots": relic_slots,
			})
		if not replace_relic_id.is_empty() and run.find_relic(replace_relic_id) == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {
				"relic_id": replace_relic_id,
			})
		return Result.ok(null)
	var acquired_order: int = run.relics.size() + 1
	var relic = null
	if not replace_relic_id.is_empty():
		relic = run.replace_relic(replace_relic_id, definition_id, acquired_order)
		if relic == null:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.shop.unknown_replace_target", {
				"relic_id": replace_relic_id,
			})
	else:
		if slot_full:
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {
				"relic_slots": relic_slots,
			})
		relic = run.equip_relic(definition_id, relic_slots, acquired_order)
		if relic == null:
			return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.shop.relic_slots_full", {
				"relic_slots": relic_slots,
			})
	_emit_event(ctx, EVENT_RELIC_GAINED, run.current_node_id, [relic.relic_id], {
		"definition_id": definition_id,
		"slot": relic.slot,
		"source": "event",
	})
	return Result.ok(null)


## 奖池耗尽 / 同名重复的替代规则：内容必须显式给出 fallback_money，否则 CONTENT_INVALID。
func _event_pool_fallback(ctx, run, effect: Dictionary, option_id: String, reason: String, dry_run: bool) -> Dictionary:
	var fallback := _int(effect.get("fallback_money"), -1)
	if fallback < 0:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.no_pool_fallback", {
			"option_id": option_id,
			"reason": reason,
		})
	if dry_run:
		return Result.ok(null)
	run.money += fallback
	_emit_event(ctx, EVENT_MONEY_GAINED, run.current_node_id, [], {"amount": fallback, "money": run.money})
	return Result.ok(null)


func _upgrade_event_card(ctx, run, effect: Dictionary, selection_ids: Array, dry_run: bool) -> Dictionary:
	if selection_ids.is_empty():
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.need_card_selection", {})
	var card = run.find_card(String(selection_ids[0]))
	if card == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.unknown_card", {
			"card_instance_id": selection_ids[0],
		})
	var type_filter := String(effect.get("type_filter", ""))
	if not type_filter.is_empty():
		var card_definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
		if String(card_definition.get("type", "")) != type_filter:
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.card_type_mismatch", {
				"card_instance_id": card.card_id,
				"type_filter": type_filter,
				"type": String(card_definition.get("type", "")),
			})
	var max_upgrades: int = catalog.run_int("max_card_upgrades", 1)
	if card.upgrade_level >= max_upgrades:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.rest.upgrade_max", {"max": max_upgrades})
	if dry_run:
		return Result.ok(null)
	card.upgrade_level += 1
	_emit_event(ctx, EVENT_CARD_UPGRADED, run.current_node_id, [card.card_id], {
		"definition_id": card.definition_id,
		"upgrade_level": card.upgrade_level,
		"source": "event",
	})
	return Result.ok(null)


## 事件删卡：不增加商店删牌费用（《统一设计文档》§10.1），但仍受牌组下限约束。
func _remove_event_card(ctx, run, effect: Dictionary, selection_ids: Array, dry_run: bool) -> Dictionary:
	if selection_ids.is_empty():
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.need_card_selection", {})
	var card_instance_id := String(selection_ids[0])
	var card = run.find_card(card_instance_id)
	if card == null:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.rest.unknown_card", {
			"card_instance_id": card_instance_id,
		})
	var tag_filter := String(effect.get("tag_filter", ""))
	if not tag_filter.is_empty():
		var card_definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
		if not (card_definition.get("tags", []) as Array).has(tag_filter):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.event.card_tag_mismatch", {
				"card_instance_id": card.card_id,
				"tag_filter": tag_filter,
				"tags": (card_definition.get("tags", []) as Array).duplicate(),
			})
	var minimum: int = catalog.run_int("minimum_deck_size", 5)
	if run.cards.size() <= minimum:
		return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.rest.deck_minimum", {"minimum": minimum})
	if dry_run:
		return Result.ok(null)
	run.remove_card(card_instance_id)
	_emit_event(ctx, EVENT_CARD_REMOVED, run.current_node_id, [card_instance_id], {
		"definition_id": card.definition_id,
		"reason": "event",
	})
	return Result.ok(null)


## 履历加值，封顶 career_track_cap。
func _gain_event_career(ctx, run, effect: Dictionary, dry_run: bool) -> Dictionary:
	var track := String(effect.get("track", ""))
	if not TermSettlementScript.TRACKS.has(track):
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.unknown_track", {"track": track})
	var amount := _int(effect.get("amount"), 1)
	if amount < 0:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.event.negative_amount", {"amount": amount})
	if dry_run:
		return Result.ok(null)
	var added: int = run.add_career(track, amount, catalog.run_int("career_track_cap", 3))
	_emit_event(ctx, EVENT_CARD_UPGRADED, run.current_node_id, [], {
		"kind": "career",
		"track": track,
		"added": added,
		"value": run.career_of(track),
	})
	return Result.ok(null)


## ctx 为空（preview/dry-run）时不发事件。
func _emit_event(ctx, event_type: String, source_id: String, target_ids: Array, data: Dictionary) -> void:
	if ctx == null:
		return
	_emit(ctx["events"], event_type, source_id, target_ids, data)
# ── 学期结算与结局 ────────────────────────────────────────

## 学期结算步骤：direction_reward（白/蓝卡三选一或跳过）、career_track（第 5 学期前的方向）。
func _choose_term_option(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	var settlement = run.settlement
	if settlement == null:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_settlement", {})
	var settlement_id := String(payload.get("settlement_id", ""))
	if settlement_id != settlement.settlement_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_settlement", {
			"settlement_id": settlement_id,
		})
	var step: Dictionary = settlement.find_step(String(payload.get("step_id", "")))
	if step.is_empty():
		step = settlement.current_step()
	if step.is_empty():
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.settlement_complete", {})
	if String(step.get("status", "")) != TermSettlementScript.STEP_PENDING:
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.step_done", {
			"step_id": step.get("step_id", ""),
		})
	var option_id := String(payload.get("option_id", ""))
	var candidate_id := String(payload.get("candidate_id", ""))
	var kind := String(step.get("kind", ""))
	var candidates: Array = step.get("candidates", [])
	if kind == TermSettlementScript.STEP_DIRECTION_REWARD:
		if option_id == "skip":
			if not bool(step.get("skippable", false)):
				return Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.run.step_mandatory", {"step_id": step.get("step_id", "")})
		elif option_id == "choose":
			if candidate_id.is_empty() and candidates.size() == 1:
				candidate_id = String(candidates[0])
			if candidate_id.is_empty() or not candidates.has(candidate_id):
				return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.bad_term_candidate", {
					"candidate_id": candidate_id,
					"candidates": candidates,
				})
			if catalog.definition(GameConstants.KIND_CARD, candidate_id).is_empty():
				return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_card", {
					"definition_id": candidate_id,
				})
		else:
			return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_term_option", {
				"option_id": option_id,
			})
	elif kind == TermSettlementScript.STEP_CAREER_TRACK:
		if not TermSettlementScript.TRACK_CHOICES.has(option_id):
			return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_track", {"option_id": option_id})
	else:
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_step_kind", {"kind": kind})

	if kind == TermSettlementScript.STEP_DIRECTION_REWARD and option_id == "choose":
		var card = run.add_card(candidate_id, 0, "term")
		_emit(ctx["events"], EVENT_CARD_GAINED, run.current_node_id, [card.card_id], {
			"definition_id": candidate_id,
			"source": "term",
		})
	elif kind == TermSettlementScript.STEP_CAREER_TRACK:
		var added: int = run.add_career(option_id, 1, catalog.run_int("career_track_cap", 3))
		run.career_direction = option_id
		_emit(ctx["events"], EVENT_CARD_UPGRADED, run.current_node_id, [], {
			"kind": "career",
			"track": option_id,
			"added": added,
			"value": run.career_of(option_id),
		})
	step["status"] = TermSettlementScript.STEP_DONE
	step["chosen_id"] = candidate_id if option_id == "choose" else option_id
	if settlement.is_complete():
		run.settlement = null
		run.term += 1
		run.current_node_id = ""
		run.node_path = []
		_emit(ctx["events"], EVENT_TERM_STARTED, "", [], {"term": run.term})
	return Result.ok(null)


## 结局条件（《统一设计文档》§10.3）；自由探索是保底可选。
func eligible_endings(run) -> Array:
	var research: int = run.career_of(TermSettlementScript.TRACK_RESEARCH)
	var competition: int = run.career_of(TermSettlementScript.TRACK_COMPETITION)
	var internship: int = run.career_of(TermSettlementScript.TRACK_INTERNSHIP)
	var endings := []
	if research >= 3:
		endings.append(ENDING_GRAD_RECOMMEND)
	if run.career_of(TermSettlementScript.TRACK_GRADUATE) >= 3:
		endings.append(ENDING_GRAD_EXAM)
	if research >= 2 and internship >= 1:
		endings.append(ENDING_ABROAD)
	if internship >= 2:
		endings.append(ENDING_EMPLOYMENT)
	if competition >= 2 and internship >= 1:
		endings.append(ENDING_STARTUP)
	endings.append(ENDING_FREE)
	return endings


## 结局选择：只在通关后一次生效（幂等键 = run_summary.ending_id）。
func _choose_ending(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	if run.outcome != GameConstants.OUTCOME_WON:
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.not_won", {"outcome": run.outcome})
	if run.run_summary == null:
		return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.run.missing_summary", {})
	if not run.run_summary.ending_id.is_empty():
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.ending_chosen", {
			"ending_id": run.run_summary.ending_id,
		})
	var ending_id := String(payload.get("ending_id", ""))
	if not eligible_endings(run).has(ending_id):
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.ending_not_eligible", {
			"ending_id": ending_id,
			"eligible": eligible_endings(run),
		})
	run.run_summary.ending_id = ending_id
	if run.pending_profile_summary != null:
		run.pending_profile_summary.ending_id = ending_id
	_emit(ctx["events"], EVENT_ENDING_CHOSEN, run.run_id, [], {"ending_id": ending_id})
	return Result.ok(null)


## 放弃本局：只在稳定边界（没有进行中战斗）生效，给 abandoned 结局、不发战胜奖励。
func _abandon_run(ctx: Dictionary, payload: Dictionary) -> Dictionary:
	var run = ctx["run"]
	if not bool(payload.get("confirmed", false)):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.abandon_unconfirmed", {})
	if run.is_run_over():
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.run_finished", {
			"outcome": run.outcome,
		})
	if not run.active_battle_id.is_empty():
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.battle_pending", {
			"battle_id": run.active_battle_id,
		})
	run.outcome = GameConstants.OUTCOME_ABANDONED
	ctx["run_summary"] = _finish_summary(run, GameConstants.OUTCOME_ABANDONED, "abandoned", null)
	run.run_summary = ctx["run_summary"]
	run.pending_profile_summary = ctx["run_summary"]
	_emit(ctx["events"], EVENT_RUN_FINISHED, run.run_id, [], {"outcome": run.outcome})
	return Result.ok(null)


# ── 战斗结算 ──────────────────────────────────────────────

## Result<RunStep>：匹配当前 battle_id 且只结算一次；写回精力、发奖励、推进节点。
func settle_battle(state, outcome: Dictionary, rng_states) -> Dictionary:
	if not _catalog_ready():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.catalog_missing", {})
	if state == null:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.no_state", {})
	if typeof(outcome) != TYPE_DICTIONARY:
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.bad_outcome", {})
	var battle_id := String(outcome.get("battle_id", ""))
	if battle_id.is_empty():
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.missing_battle_id", {})
	if state.active_battle_id.is_empty() and not state.settled_battle_ids.has(battle_id):
		return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_active_battle", {})
	if state.settled_battle_ids.has(battle_id):
		return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.battle_settled", {
			"battle_id": battle_id,
		})
	if battle_id != state.active_battle_id:
		return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.battle_mismatch", {
			"expected": state.active_battle_id,
			"got": battle_id,
		})
	var result := String(outcome.get("result", ""))
	if not [GameConstants.OUTCOME_WON, GameConstants.OUTCOME_LOST, GameConstants.OUTCOME_ABANDONED].has(result):
		return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.bad_outcome_result", {"result": result})
	var rng := RandomSourceScript.new(0)
	if rng_states != null:
		var restored := rng.restore_state(rng_states)
		if not Result.is_ok(restored):
			return restored
	var working = state.copy_for_write()
	var ctx := {"run": working, "rng": rng, "events": [], "battle_input": null, "run_summary": null}
	var node = working.find_node(working.current_node_id)
	if node == null or not node.is_battle():
		return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.run.no_battle_node", {
			"current_node_id": working.current_node_id,
		})
	# 战斗期间精力以 BattleState 为准，这里一次性写回（钳制到 [0, max_vitality]）
	working.vitality = clampi(_int(outcome.get("remaining_vitality"), working.vitality), 0, working.max_vitality)
	working.settled_battle_ids[battle_id] = true
	working.active_battle_id = ""
	working.active_encounter_id = ""
	_emit(ctx["events"], EVENT_BATTLE_SETTLED, node.node_id, [], {
		"battle_id": battle_id,
		"result": result,
		"reason": String(outcome.get("reason", "")),
		"vitality": working.vitality,
		"node_kind": node.kind,
	})
	if result == GameConstants.OUTCOME_WON:
		var awarded := _award_victory(ctx, node)
		if not Result.is_ok(awarded):
			return awarded
	else:
		node.mark_completed()
		working.node_path.append(node.node_id)
		working.outcome = result
		ctx["run_summary"] = _finish_summary(working, result, String(outcome.get("reason", "")), node)
		working.run_summary = ctx["run_summary"]
		working.pending_profile_summary = ctx["run_summary"]
		_emit(ctx["events"], EVENT_RUN_FINISHED, node.node_id, [], {"outcome": result, "reason": ctx["run_summary"].reason})
	return _make_step(working, ctx["events"], null, ctx["run_summary"], rng)


## 胜利：发生活费、生成奖励（冻结候选）、必要时直接结算学期/结局。
func _award_victory(ctx: Dictionary, node) -> Dictionary:
	var run = ctx["run"]
	var is_boss: bool = node.kind == RunNodeState.KIND_BOSS
	if is_boss and run.term >= _ruleset_term_count():
		# 最终首领：直接进入结局，不发影响已结束局的奖励
		node.mark_completed()
		run.node_path.append(node.node_id)
		run.outcome = GameConstants.OUTCOME_WON
		ctx["run_summary"] = _finish_summary(run, GameConstants.OUTCOME_WON, GameConstants.REASON_TASKS_COMPLETED, node)
		run.run_summary = ctx["run_summary"]
		run.pending_profile_summary = ctx["run_summary"]
		_emit(ctx["events"], EVENT_RUN_FINISHED, node.node_id, [], {"outcome": run.outcome, "term": run.term})
		return Result.ok(null)
	var generated := _rewards.generate_battle_reward(node, run, ctx["rng"])
	if not Result.is_ok(generated):
		return generated
	var offer = generated["data"]
	var money := _battle_payout(run, node) + _int(offer.meta.get("relic_fallback_money"), 0)
	if money > 0:
		run.money += money
		_emit(ctx["events"], EVENT_MONEY_GAINED, node.node_id, [], {
			"amount": money,
			"money": run.money,
			"source": node.kind,
		})
	offer.meta["money"] = money
	run.pending_reward = offer
	_emit(ctx["events"], EVENT_REWARD_CREATED, node.node_id, [], {
		"offer_id": offer.offer_id,
		"source": offer.source_kind,
		"items": offer.items.size(),
		"money": money,
	})
	return Result.ok(null)


## 生活费（《统一设计文档》§10.1）：正常学期 1~2/3~4/5~6/7~8 = 15/20/25/30；
## 精英 +20；非最终首领 50。
func _battle_payout(run, node) -> int:
	var rewards := catalog.section("rewards")
	if node.kind == RunNodeState.KIND_BOSS:
		return _int(rewards.get("nonfinal_boss_money"), 50)
	if node.kind == RunNodeState.KIND_ELITE:
		return _normal_money(run, rewards) + _int(rewards.get("elite_money_bonus"), 20)
	return _normal_money(run, rewards)


func _normal_money(run, rewards: Dictionary) -> int:
	var table: Array = rewards.get("normal_money_by_term", [])
	if table.is_empty():
		return 0
	return _int(table[clampi(run.term - 1, 0, table.size() - 1)], 0)


func _finish_summary(run, result: String, reason: String, node) -> RunSummaryScript:
	var summary = RunSummaryScript.create(run.run_id, result, reason, run.character_id, run.difficulty, run.term)
	summary.stats = {
		"term": run.term,
		"money": run.money,
		"vitality": run.vitality,
		"max_vitality": run.max_vitality,
		"deck_size": run.cards.size(),
		"relics": run.relics.size(),
		"settled_battles": run.settled_battle_ids.size(),
		"node_id": node.node_id if node != null else run.current_node_id,
	}
	return summary
# ── 视图 ──────────────────────────────────────────────────

## RunView + 当前节点视图（《接口文档》§2 SessionView 的 run / node 部分）。
## 只读；不暴露抽取顺序、未公开随机状态或内容定义全表。
func make_view(state) -> Dictionary:
	if state == null:
		return {}
	var relic_slots: int = catalog.run_int("relic_slots", 6) if _catalog_ready() else 0
	var view := {
		"run_id": state.run_id,
		"character_id": state.character_id,
		"ruleset_id": state.ruleset_id,
		"difficulty": state.difficulty,
		"manifest_id": state.manifest_id,
		"term": state.term,
		"term_count": _ruleset_term_count(),
		"nodes_per_term": _ruleset_nodes_per_term(),
		"money": state.money,
		"vitality": state.vitality,
		"max_vitality": state.max_vitality,
		"career": state.career_progress.duplicate(),
		"career_direction": state.career_direction,
		"relic_slots": relic_slots,
		"cards": _cards_view(state),
		"relics": _relics_view(state),
		"deck_size": state.cards.size(),
		"removals_used": state.removals_used,
		"current_node_id": state.current_node_id,
		"node_path": state.node_path.duplicate(),
		"reachable_node_ids": state.reachable_node_ids(),
		"nodes": _nodes_view(state),
		"node": null,
		"battle": null,
		"pending_reward": null,
		"shop": null,
		"event": null,
		"rest": null,
		"settlement": null,
		"outcome": state.outcome,
		"run_summary": null,
		"eligible_endings": [],
		"screen": GameConstants.SCREEN_MAP,
	}
	if state.run_summary != null:
		view["run_summary"] = _summary_view(state.run_summary)
	if state.outcome == GameConstants.OUTCOME_WON:
		view["eligible_endings"] = eligible_endings(state)
	if state.settlement != null:
		view["settlement"] = _settlement_view(state.settlement)
	if state.pending_reward != null:
		view["pending_reward"] = _offer_view(state.pending_reward)
	var node = state.current_node()
	if node != null:
		view["node"] = _node_view(state, node)
		if node.is_battle():
			view["battle"] = {
				"battle_id": node.battle_id(),
				"encounter_id": String(node.context.get("encounter_id", "")),
				"settled": state.settled_battle_ids.has(node.battle_id()),
			}
		elif node.kind == RunNodeState.KIND_SHOP and node.context.has("shop"):
			view["shop"] = _shop_view(state, node.context["shop"])
		elif node.kind == RunNodeState.KIND_EVENT and node.context.has("event"):
			view["event"] = _event_view(state, node)
		elif node.kind == RunNodeState.KIND_REST:
			view["rest"] = _rest_view(state)
	view["screen"] = _screen_of(state)
	return view


## 页面路由（GameSession 直接用它决定显示哪个页面）。
func _screen_of(state) -> String:
	if state.outcome == GameConstants.OUTCOME_WON and state.run_summary != null and state.run_summary.ending_id.is_empty():
		return GameConstants.SCREEN_ENDING
	if not state.outcome.is_empty():
		return GameConstants.SCREEN_SUMMARY
	if state.settlement != null and not state.settlement.is_complete():
		return GameConstants.SCREEN_TERM
	if state.pending_reward != null:
		return GameConstants.SCREEN_REWARD
	var node = state.current_node()
	if node != null and node.status == RunNodeState.STATUS_ACTIVE:
		if node.is_battle():
			return GameConstants.SCREEN_BATTLE
		if node.kind == RunNodeState.KIND_SHOP:
			return GameConstants.SCREEN_SHOP
		if node.kind == RunNodeState.KIND_EVENT:
			return GameConstants.SCREEN_EVENT
		if node.kind == RunNodeState.KIND_REST:
			return GameConstants.SCREEN_REST
	return GameConstants.SCREEN_MAP


func _cards_view(state) -> Array:
	var cards := []
	for card in state.cards:
		cards.append({
			"card_id": card.card_id,
			"definition_id": card.definition_id,
			"upgrade_level": card.upgrade_level,
			"acquired_from": card.acquired_from,
		})
	return cards


func _relics_view(state) -> Array:
	var relics := []
	for relic in state.relics:
		relics.append({
			"relic_id": relic.relic_id,
			"definition_id": relic.definition_id,
			"slot": relic.slot,
			"acquired_order": relic.acquired_order,
		})
	relics.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return relics


## 只给当前学期的节点，避免把整局地图一次性推给界面。
func _nodes_view(state) -> Array:
	var nodes := []
	for raw_node in state.nodes_of_term(state.term):
		var node: RunNodeState = raw_node
		nodes.append(_node_view(state, node))
	return nodes


func _node_view(state, node) -> Dictionary:
	var view := {
		"node_id": node.node_id,
		"term": node.term,
		"layer": node.layer,
		"kind": node.kind,
		"status": node.status,
		"next_ids": node.next_ids.duplicate(),
		"encounter_id": String(node.context.get("encounter_id", "")),
		"event_definition_id": "",
	}
	if node.context.has("event") and node.context["event"] != null:
		view["event_definition_id"] = node.context["event"].definition_id
	return view


func _offer_view(offer) -> Dictionary:
	var items := []
	for raw_item in offer.items:
		items.append({
			"item_id": raw_item.item_id,
			"kind": raw_item.kind,
			"candidates": raw_item.candidates.duplicate(),
			"status": raw_item.status,
			"chosen_id": raw_item.chosen_id,
			"skippable": raw_item.skippable,
		})
	return {
		"offer_id": offer.offer_id,
		"source_node_id": offer.source_node_id,
		"source_kind": offer.source_kind,
		"money": _int(offer.meta.get("money"), 0),
		"relic_fallback_money": _int(offer.meta.get("relic_fallback_money"), 0),
		"complete": offer.is_complete(),
		"items": items,
	}


func _shop_view(state, shop) -> Dictionary:
	var stocks := []
	for raw_stock in shop.stocks:
		stocks.append({
			"stock_id": raw_stock.stock_id,
			"kind": raw_stock.kind,
			"definition_id": raw_stock.definition_id,
			"price": _transactions.quote_price(state, raw_stock),
		"base_price": int(raw_stock.price),
			"sold": raw_stock.sold,
			"meta": raw_stock.meta.duplicate(),
		})
	var shop_rules := catalog.section("shop")
	var max_per_shop := _int(shop_rules.get("removals_per_shop"), 1)
	var minimum := catalog.run_int("minimum_deck_size", 5)
	return {
		"shop_id": shop.shop_id,
		"node_id": shop.node_id,
		"stocks": stocks,
		"removal": {
			"available": shop.removal_count < max_per_shop and state.cards.size() > minimum,
			"used": shop.removal_count,
			"max": max_per_shop,
			"price": _transactions.removal_price(state),
			"money": state.money,
			"minimum_deck_size": minimum,
			"deck_size": state.cards.size(),
		},
	}


func _event_view(state, node) -> Dictionary:
	var instance = node.context["event"]
	var definition: Dictionary = catalog.definition(GameConstants.KIND_EVENT, instance.definition_id)
	var options := []
	for raw_option in (definition.get("options", []) as Array):
		var option: Dictionary = raw_option
		var option_id := String(option.get("option_id", ""))
		options.append({
			"option_id": option_id,
			"label_key": String(option.get("label_key", "")),
			"cost": (option.get("cost", {}) as Dictionary).duplicate(),
			"effects": (option.get("effects", []) as Array).duplicate(),
			"candidates": instance.candidates_for(option_id).duplicate(),
			"selection_candidates": _event_selection_candidates(state, option, instance),
			"enabled": _event_option_blocking(state, option, instance).is_empty(),
			"blocking": _event_option_blocking(state, option, instance),
		})
	return {
		"event_instance_id": instance.event_instance_id,
		"definition_id": instance.definition_id,
		"name_key": String(definition.get("name_key", "")),
		"resolved_option_id": instance.resolved_option_id,
		"frozen_candidates": instance.frozen_candidates.duplicate(true),
		"relic_slots_full": state.relics.size() >= catalog.run_int("relic_slots", 6),
		"options": options,
	}


## 选项的合法选择目标（卡实例 ID）：升级 = 未满级且类型匹配；删卡 = 牌组高于下限且 tag 匹配。
## gain_card 的候选是「卡定义 ID」，沿用 options[].candidates，不混进这个数组。
func _event_selection_candidates(state, option: Dictionary, instance) -> Array:
	var out := []
	for raw_effect in (option.get("effects", []) as Array):
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if op == EV_OP_UPGRADE_CARD:
			for card in _upgrade_targets(state, String(effect.get("type_filter", ""))):
				out.append(card.card_id)
		elif op == EV_OP_REMOVE_CARD:
			if state.cards.size() <= catalog.run_int("minimum_deck_size", 5):
				continue
			for card in _remove_targets(state, String(effect.get("tag_filter", ""))):
				out.append(card.card_id)
	return out


## 选项「现在是否可能成功」的静态检查（带目标的选项由提交时全量校验）。
func _event_option_blocking(state, option: Dictionary, instance) -> Array:
	var blocking := []
	var cost: Dictionary = option.get("cost", {})
	var money_cost := _int(cost.get("money"), 0)
	if money_cost > 0 and state.money < money_cost:
		blocking.append("error.event.not_enough_money")
	var vitality_cost := _int(cost.get("vitality"), 0)
	if vitality_cost > 0 and state.vitality - vitality_cost < 1:
		blocking.append("error.event.not_enough_vitality")
	var option_id := String(option.get("option_id", ""))
	var candidates: Array = instance.candidates_for(option_id)
	for raw_effect in (option.get("effects", []) as Array):
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if not EVENT_OPS.has(op):
			blocking.append("error.event.unknown_op")
			continue
		if op == EV_OP_GAIN_CARD and not effect.has("card_id"):
			if candidates.is_empty() and _int(effect.get("fallback_money"), -1) < 0:
				blocking.append("error.event.empty_card_pool")
		elif op == EV_OP_GAIN_RELIC and not effect.has("relic_id"):
			if candidates.is_empty() and _int(effect.get("fallback_money"), -1) < 0:
				blocking.append("error.event.empty_relic_pool")
		elif op == EV_OP_UPGRADE_CARD:
			if _upgrade_targets(state, String(effect.get("type_filter", ""))).is_empty():
				blocking.append("error.event.no_upgrade_target")
		elif op == EV_OP_REMOVE_CARD:
			if state.cards.size() <= catalog.run_int("minimum_deck_size", 5):
				blocking.append("error.rest.deck_minimum")
			elif _remove_targets(state, String(effect.get("tag_filter", ""))).is_empty():
				blocking.append("error.event.no_remove_target")
		elif op == EV_OP_CAREER:
			if not TermSettlementScript.TRACKS.has(String(effect.get("track", ""))):
				blocking.append("error.event.unknown_track")
	return blocking


## 可升级目标：默认全部未满级牌；给 type_filter 时只留该类型的牌（V04「升级1张工作牌」）。
func _upgrade_targets(state, type_filter: String = "") -> Array:
	var max_upgrades: int = catalog.run_int("max_card_upgrades", 1)
	var matched := []
	for card in state.cards:
		if card.upgrade_level >= max_upgrades:
			continue
		if not _card_matches_type(card, type_filter):
			continue
		matched.append(card)
	return matched


## 可删目标：默认全部牌；给 tag_filter 时只留带该 tag 的牌（V03「删1张基础牌」）。
func _remove_targets(state, tag_filter: String = "") -> Array:
	var matched := []
	for card in state.cards:
		if tag_filter.is_empty():
			matched.append(card)
			continue
		var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
		if (definition.get("tags", []) as Array).has(tag_filter):
			matched.append(card)
	return matched


func _card_matches_type(card, type_filter: String) -> bool:
	if type_filter.is_empty():
		return true
	var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
	return String(definition.get("type", "")) == type_filter


func _rest_view(state) -> Dictionary:
	var options := []
	for option_id in REST_OPTIONS:
		var blocking := _rest_option_blocking(state, option_id)
		options.append({
			"option_id": option_id,
			"enabled": blocking.is_empty(),
			"blocking": blocking,
			"needs_card": option_id != REST_HEAL,
		})
	return {
		"node_id": state.current_node_id,
		"heal_percent": catalog.run_int("rest_heal_percent", 25),
		"heal_amount": catalog.scaled_by_percent(state.max_vitality, catalog.run_int("rest_heal_percent", 25)),
		"options": options,
	}


func _settlement_view(settlement) -> Dictionary:
	var steps := []
	for raw_step in settlement.steps:
		var step: Dictionary = raw_step
		steps.append({
			"step_id": String(step.get("step_id", "")),
			"kind": String(step.get("kind", "")),
			"status": String(step.get("status", "")),
			"candidates": (step.get("candidates", []) as Array).duplicate(),
			"skippable": bool(step.get("skippable", false)),
			"chosen_id": String(step.get("chosen_id", "")),
		})
	var current: Dictionary = settlement.current_step()
	return {
		"settlement_id": settlement.settlement_id,
		"term": settlement.term,
		"complete": settlement.is_complete(),
		"current_step_id": String(current.get("step_id", "")),
		"steps": steps,
	}


func _summary_view(summary) -> Dictionary:
	return {
		"run_id": summary.run_id,
		"result": summary.result,
		"reason": summary.reason,
		"ending_id": summary.ending_id,
		"character_id": summary.character_id,
		"difficulty": summary.difficulty,
		"term": summary.term,
		"stats": summary.stats.duplicate(true),
		"unlocked_ids": summary.unlocked_ids.duplicate(),
	}
# ── preview 实现（不改状态、不消费随机）───────────────────

func _preview_enter_node(run, payload: Dictionary, preview: Dictionary) -> void:
	var node_id := String(payload.get("node_id", ""))
	var node = run.find_node(node_id)
	if node == null:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_node", {"node_id": node_id}))
		return
	if node.status != RunNodeState.STATUS_PENDING:
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_not_pending", {"node_id": node_id}))
		return
	if not run.reachable_node_ids().has(node_id):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.node_not_reachable", {"node_id": node_id}))
		return
	if node.is_battle():
		if _resolve_encounter_pool(run, node).is_empty():
			_block(preview, Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.no_encounter", {
				"kind": node.kind,
				"term": run.term,
			}))
	elif node.kind == RunNodeState.KIND_EVENT and _event_pool(run, run.term).is_empty():
		if _resolve_encounter_pool(run, node, RunNodeState.KIND_NORMAL).is_empty():
			_block(preview, Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.no_encounter", {
				"kind": RunNodeState.KIND_NORMAL,
				"term": run.term,
			}))


func _preview_claim_reward(run, payload: Dictionary, preview: Dictionary) -> void:
	var offer = run.pending_reward
	if offer == null:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_reward", {}))
		return
	if String(payload.get("offer_id", "")) != offer.offer_id:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_offer", {}))
		return
	var item = offer.find_item(String(payload.get("item_id", "")))
	if item == null:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_reward_item", {}))
		return
	if item.status != RewardOfferScript.STATUS_PENDING:
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.reward_item_resolved", {
			"status": item.status,
		}))
		return
	preview["known_effects"] = [{"kind": item.kind, "candidates": item.candidates.duplicate()}]
	var candidate_id := String(payload.get("candidate_id", ""))
	if candidate_id.is_empty() and item.candidates.size() > 1:
		_require(preview, "candidate_id")
	elif not candidate_id.is_empty() and not item.candidates.has(candidate_id):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.bad_reward_candidate", {}))
		return
	if item.kind == RewardOfferScript.ITEM_RELIC:
		var relic_slots: int = catalog.run_int("relic_slots", 6)
		if run.relics.size() >= relic_slots and String(payload.get("replace_relic_id", "")).is_empty():
			_require(preview, "replace_relic_id")


func _preview_skip_reward(run, payload: Dictionary, preview: Dictionary) -> void:
	var offer = run.pending_reward
	if offer == null:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_reward", {}))
		return
	if String(payload.get("offer_id", "")) != offer.offer_id:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_offer", {}))
		return
	var item = offer.find_item(String(payload.get("item_id", "")))
	if item == null:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_reward_item", {}))
		return
	if item.status != RewardOfferScript.STATUS_PENDING:
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.reward_item_resolved", {}))
	elif not item.skippable:
		_block(preview, Result.fail(GameConstants.ERROR_LIMIT_REACHED, "error.run.reward_item_mandatory", {}))


func _preview_transaction(run, draft: Dictionary, preview: Dictionary) -> void:
	var plan := _transactions.prepare(run, draft)
	if not Result.is_ok(plan):
		_block(preview, plan)
		return
	preview["costs"] = {"money": int(plan["data"].get("price", 0))}
	preview["known_effects"] = [{"kind": String(plan["data"].get("kind", ""))}]


func _preview_choose_event(run, payload: Dictionary, preview: Dictionary) -> void:
	var node = run.current_node()
	if node == null or node.kind != RunNodeState.KIND_EVENT:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_event_node", {}))
		return
	var instance = node.context.get("event")
	if instance == null:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_event_instance", {}))
		return
	if instance.is_resolved():
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.event_resolved", {}))
		return
	var definition: Dictionary = catalog.definition(GameConstants.KIND_EVENT, instance.definition_id)
	if definition.is_empty():
		_block(preview, Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_event", {}))
		return
	var option := _find_event_option(definition, String(payload.get("option_id", "")))
	if option.is_empty():
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_event_option", {}))
		return
	preview["known_effects"] = (option.get("effects", []) as Array).duplicate()
	var raw_selection: Variant = payload.get("selection_ids")
	var selection_ids: Array = raw_selection if typeof(raw_selection) == TYPE_ARRAY else []
	var replace_relic_id := String(payload.get("replace_relic_id", ""))
	var check := _event_option_error(null, run, option, instance, selection_ids, replace_relic_id)
	if Result.is_ok(check):
		return
	var code := Result.error_code(check)
	var needs: Array = _event_needs_selection(run, option, instance)
	if code == GameConstants.ERROR_INVALID_TARGET and not needs.is_empty():
		for key in needs:
			var still_missing := _selection_missing(key, selection_ids, replace_relic_id)
			if still_missing:
				_require(preview, String(key))
		return
	_block(preview, check)


func _selection_missing(key: String, selection_ids: Array, replace_relic_id: String) -> bool:
	if key == "replace_relic_id":
		return replace_relic_id.is_empty()
	return selection_ids.is_empty()


## 该选项需要哪些玩家选择（带目标的选项不能直接提交）。
func _event_needs_selection(run, option: Dictionary, instance) -> Array:
	var needs := []
	var option_id := String(option.get("option_id", ""))
	var candidates: Array = instance.candidates_for(option_id)
	var relic_slots: int = catalog.run_int("relic_slots", 6)
	for raw_effect in (option.get("effects", []) as Array):
		var effect: Dictionary = raw_effect
		var op := String(effect.get("op", ""))
		if (op == EV_OP_UPGRADE_CARD or op == EV_OP_REMOVE_CARD) and not needs.has("selection_ids"):
			needs.append("selection_ids")
		elif op == EV_OP_GAIN_CARD and not effect.has("card_id") and candidates.size() > 1 and not needs.has("selection_ids"):
			needs.append("selection_ids")
		elif op == EV_OP_GAIN_RELIC:
			if not effect.has("relic_id") and candidates.size() > 1 and not needs.has("selection_ids"):
				needs.append("selection_ids")
			if run.relics.size() >= relic_slots and not needs.has("replace_relic_id"):
				needs.append("replace_relic_id")
	return needs


func _preview_take_rest(run, payload: Dictionary, preview: Dictionary) -> void:
	var node = run.current_node()
	if node == null or node.kind != RunNodeState.KIND_REST:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_rest_node", {}))
		return
	if node.status != RunNodeState.STATUS_ACTIVE:
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_not_active", {}))
		return
	if bool(node.context.get("used", false)):
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.rest_already_taken", {}))
		return
	var option_id := String(payload.get("option_id", ""))
	if not REST_OPTIONS.has(option_id):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_rest_option", {}))
		return
	var card_instance_id := String(payload.get("card_instance_id", ""))
	preview["known_effects"] = [{"option_id": option_id}]
	if card_instance_id.is_empty() and option_id != REST_HEAL:
		_require(preview, "card_instance_id")
		return
	var check := _rest_validate(run, option_id, card_instance_id)
	if not Result.is_ok(check):
		_block(preview, check)


func _preview_leave_node(run, payload: Dictionary, preview: Dictionary) -> void:
	var node = run.current_node()
	if node == null or node.node_id != String(payload.get("node_id", "")):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.not_current_node", {}))
		return
	if node.status != RunNodeState.STATUS_ACTIVE:
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.node_not_active", {}))
		return
	if node.is_battle():
		if not run.active_battle_id.is_empty():
			_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.battle_pending", {}))
			return
		if run.pending_reward != null and not run.pending_reward.is_complete():
			_block(preview, Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.run.reward_pending", {}))
	elif node.kind == RunNodeState.KIND_EVENT:
		var instance = node.context.get("event")
		if instance == null or not instance.is_resolved():
			_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.event_unresolved", {}))
	elif node.kind == RunNodeState.KIND_REST:
		if not bool(node.context.get("used", false)):
			_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.rest_not_taken", {}))


func _preview_term_option(run, payload: Dictionary, preview: Dictionary) -> void:
	var settlement = run.settlement
	if settlement == null:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.no_settlement", {}))
		return
	if String(payload.get("settlement_id", "")) != settlement.settlement_id:
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_settlement", {}))
		return
	var step: Dictionary = settlement.find_step(String(payload.get("step_id", "")))
	if step.is_empty():
		step = settlement.current_step()
	if step.is_empty():
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.settlement_complete", {}))
		return
	var option_id := String(payload.get("option_id", ""))
	var candidate_id := String(payload.get("candidate_id", ""))
	var kind := String(step.get("kind", ""))
	var candidates: Array = step.get("candidates", [])
	if kind == TermSettlementScript.STEP_DIRECTION_REWARD:
		if option_id == "skip":
			return
		if option_id != "choose":
			_block(preview, Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.unknown_term_option", {}))
			return
		if candidate_id.is_empty() and candidates.size() > 1:
			_require(preview, "candidate_id")
			return
		if candidate_id.is_empty() and candidates.is_empty():
			_block(preview, Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.empty_term_pool", {}))
			return
		if not candidates.has(candidate_id if not candidate_id.is_empty() else String(candidates[0])):
			_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.bad_term_candidate", {}))
	elif kind == TermSettlementScript.STEP_CAREER_TRACK:
		if not TermSettlementScript.TRACK_CHOICES.has(option_id):
			_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.unknown_track", {}))
	else:
		_block(preview, Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.unknown_step_kind", {}))


func _preview_choose_ending(run, payload: Dictionary, preview: Dictionary) -> void:
	if run.outcome != GameConstants.OUTCOME_WON:
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.not_won", {}))
		return
	var ending_id := String(payload.get("ending_id", ""))
	if not eligible_endings(run).has(ending_id):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.run.ending_not_eligible", {
			"eligible": eligible_endings(run),
		}))


func _preview_abandon(run, payload: Dictionary, preview: Dictionary) -> void:
	if not bool(payload.get("confirmed", false)):
		_block(preview, Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.run.abandon_unconfirmed", {}))
	elif run.is_run_over():
		_block(preview, Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.run.run_finished", {}))
	elif not run.active_battle_id.is_empty():
		_block(preview, Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.run.battle_pending", {}))


# ── 工具 ──────────────────────────────────────────────────

func _require(preview: Dictionary, key: String) -> void:
	var required: Array = preview["required_selections"]
	if not required.has(key):
		required.append(key)


func _catalog_ready() -> bool:
	return catalog != null and catalog.is_loaded()


func _ruleset_term_count() -> int:
	if not _catalog_ready():
		return 0
	return catalog.run_int("term_count", 8)


func _ruleset_nodes_per_term() -> int:
	if not _catalog_ready():
		return 0
	return catalog.run_int("nodes_per_term", RunMapScript.layer_count())


## Result<String>：在已按 ID 稳定排序的池里等概率取一个（推进 map 流）。
func _pick(pool: Array, rng) -> Dictionary:
	if pool.is_empty():
		return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.run.empty_pool", {})
	# 候选唯一时不消费 map 流（契约 §5）：显式短路，不再依赖 randi_range(0, 0) 不推进随机的实现细节。
	if pool.size() == 1:
		return Result.ok(String(pool[0]))
	var roll: Dictionary = rng.draw_int(GameConstants.RNG_MAP, 0, pool.size() - 1)
	if not Result.is_ok(roll):
		return roll
	return Result.ok(String(pool[int(roll["data"])]))


## RuleEvent = {index, type, source_id, target_ids, data}（《接口文档》§8）。
func _emit(events: Array, event_type: String, source_id: String, target_ids: Array, data: Dictionary) -> void:
	events.append({
		"index": events.size(),
		"type": event_type,
		"source_id": source_id,
		"target_ids": target_ids,
		"data": data,
	})


## RunStep = {state, events, battle_input, run_summary, rng_states}。
## battle_input.rng_state 取「本次命令提交后」的完整随机快照（含刚推进的 map/reward/event），
## 交给 BattleEngine 后只有 battle 流会前进。
func _make_step(run, events: Array, battle_input, run_summary, rng) -> Dictionary:
	var published = battle_input
	if typeof(published) == TYPE_DICTIONARY:
		var published_dict: Dictionary = published
		published_dict["rng_state"] = rng.export_state()
	return Result.ok({
		"state": run,
		"events": events,
		"battle_input": published,
		"run_summary": run_summary,
		"rng_states": rng.export_state(),
	})


## 战斗入场输入（《战斗模块契约》§2）：永久牌实例直接作为战斗牌实例，
## origin_card_id 指向同一永久实例（本局一张永久牌同时只在一场战斗里）。
func _battle_input(run, node, encounter_id: String) -> Dictionary:
	var cards := []
	for card in run.cards:
		cards.append({
			"card_id": card.card_id,
			"definition_id": card.definition_id,
			"origin_card_id": card.card_id,
			"upgrade_level": card.upgrade_level,
		})
	var ordered: Array = run.relics.duplicate()
	ordered.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	var relics := []
	for relic in ordered:
		relics.append(relic.definition_id)
	return {
		"battle_id": node.battle_id(),
		"node_id": node.node_id,
		"encounter_id": encounter_id,
		"character_id": run.character_id,
		"difficulty": run.difficulty,
		"vitality": run.vitality,
		"max_vitality": run.max_vitality,
		"cards": cards,
		"relics": relics,
		"rng_state": null,
	}


## 统一读整数：JSON 里所有数字都是 float，十进制字符串也接受。
func _int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)):
		return int(value)
	if typeof(value) == TYPE_STRING and String(value).is_valid_int():
		return String(value).to_int()
	return fallback
# ── 事件候选冻结 ──────────────────────────────────────────

## 进入事件节点时，把「带 rarity 的随机收益」候选一次性抽好并冻结（reward 流）；
## 重新打开界面不重抽、不换候选。显式 card_id / relic_id 的收益不需要冻结。
func _freeze_event_candidates(run, definition: Dictionary, rng) -> Dictionary:
	var frozen := {}
	for raw_option in (definition.get("options", []) as Array):
		var option: Dictionary = raw_option
		var option_id := String(option.get("option_id", ""))
		for raw_effect in (option.get("effects", []) as Array):
			var effect: Dictionary = raw_effect
			var op := String(effect.get("op", ""))
			if op == EV_OP_GAIN_CARD and effect.has("card_pool"):
				# 显式卡池（V03「从 K14/K05/K60 里选 1」）：候选由内容直接给出，不抽随机。
				frozen[option_id] = (effect.get("card_pool", []) as Array).duplicate()
			elif op == EV_OP_GAIN_CARD and effect.has("rarity") and not effect.has("card_id"):
				var card_count := _int(effect.get("candidate_count"), 3)
				var card_picked := _rewards.card_candidates_of_rarity(String(effect.get("rarity")), card_count, run, rng)
				if not Result.is_ok(card_picked):
					return card_picked
				frozen[option_id] = card_picked["data"]
			elif op == EV_OP_GAIN_RELIC and effect.has("rarity") and not effect.has("relic_id"):
				var relic_count := _int(effect.get("count"), 1)
				var relic_picked := _rewards.relic_candidates_of_rarity(String(effect.get("rarity")), relic_count, run, rng)
				if not Result.is_ok(relic_picked):
					return relic_picked
				frozen[option_id] = relic_picked["data"]
	return Result.ok(frozen)