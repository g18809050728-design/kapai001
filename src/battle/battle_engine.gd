class_name BattleEngine
extends RefCounted
##
## 战斗聚合服务（《类与方法设计》§3；《接口文档》§4）。
##
## 公开接口：
##   begin(input: BattleInput) -> Result<BattleStep>
##   preview(state, draft) -> Result<ActionPreview>
##   apply(state, action, rng_state) -> Result<BattleStep>
##   make_view(state) -> BattleView
##
## 相位顺序显式写死（《游戏规则书》§3.3 / 《统一设计文档》§3.3），不靠字典遍历。
## apply / preview 都只改工作副本：非法操作不扣费、不移牌、不消费随机、不加触发计数。
## BattleStep = {state, events, pending_choice, outcome, stable, rng_state}。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const BattleCardRules := preload("res://src/battle/card_rules.gd")

## 一个完整回合的显式相位顺序（步骤 1 硬要求）。
const PHASE_ORDER: Array[String] = [
        GameConstants.PHASE_PLAYER_PREPARE,
        GameConstants.PHASE_DRAW,
        GameConstants.PHASE_PLAYER_ACTION,
        GameConstants.PHASE_ALLY_ACTION,
        GameConstants.PHASE_DISCARD,
        GameConstants.PHASE_ENEMY_PREPARE,
        GameConstants.PHASE_ENEMY_SKILL,
        GameConstants.PHASE_ENEMY_PRESSURE,
        GameConstants.PHASE_ROUND_END,
]

const PLAYER_SIDE_PHASES: Array[String] = [
        GameConstants.PHASE_INITIALIZING,
        GameConstants.PHASE_PLAYER_PREPARE,
        GameConstants.PHASE_DRAW,
        GameConstants.PHASE_PLAYER_ACTION,
        GameConstants.PHASE_ALLY_ACTION,
        GameConstants.PHASE_DISCARD,
]

const ROUND_END_CLEAR_STATUSES: Array[String] = [
        GameConstants.STATUS_INSPIRATION,
]

const DEFAULT_RETENTION := 0

# ── RuleEvent 类型（写入 BattleStep.events，UI 只读）────────
const EVENT_PHASE_CHANGED := "phase_changed"
const EVENT_ROUND_STARTED := "round_started"
const EVENT_FOCUS_CHANGED := "focus_changed"
const EVENT_CARD_PLAYED := "card_played"
const EVENT_CARD_RESOLVED := "card_resolved"
const EVENT_CARD_DRAWN := "card_drawn"
const EVENT_CARD_DISCARDED := "card_discarded"
const EVENT_CHOICE_REQUESTED := "choice_requested"
const EVENT_CHOICE_CONFIRMED := "choice_confirmed"
const EVENT_STATUS_GAINED := "status_gained"
const EVENT_STATUS_REMOVED := "status_removed"
const EVENT_COMPLETION_APPLIED := "completion_applied"
const EVENT_PRESSURE_APPLIED := "pressure_applied"
const EVENT_VITALITY_CHANGED := "vitality_changed"
const EVENT_UNIT_SUMMONED := "unit_summoned"
const EVENT_UNIT_DEPARTED := "unit_departed"
const EVENT_SCENE_ESTABLISHED := "scene_established"
const EVENT_SCENE_REPLACED := "scene_replaced"
const EVENT_TASK_ADVANCED := "task_advanced"
const EVENT_TASK_COMPLETED := "task_completed"
const EVENT_INTENT_REVEALED := "intent_revealed"
const EVENT_ENEMY_SKILL := "enemy_skill"
const EVENT_DDL_TICKED := "ddl_ticked"
const EVENT_BATTLE_FINISHED := "battle_finished"
const EVENT_COOP_TARGET_SET := "coop_target_set"
const EVENT_CARD_RECALLED := "card_recalled"
const EVENT_RETENTION_GRANTED := "retention_granted"
const EVENT_RELIC_TRIGGERED := "relic_triggered"

## 只读内容库；由 GameSession 注入（测试可直接 new ContentDB 并 load）。
var catalog = null


func _init(catalog_ref = null) -> void:
        catalog = catalog_ref


func set_catalog(catalog_ref) -> void:
        catalog = catalog_ref


# ── 公开接口 ──────────────────────────────────────────────

## Result<BattleStep>。BattleInput = {battle_id, node_id, encounter_id, character_id,
## difficulty, vitality, max_vitality, cards, relics, rng_state}。
func begin(input: Dictionary) -> Dictionary:
        if catalog == null or not catalog.is_loaded():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.catalog_missing", {})

        var encounter_id = String(input.get("encounter_id", ""))
        var encounter: Dictionary = catalog.definition(GameConstants.KIND_ENCOUNTER, encounter_id)
        if encounter.is_empty():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.unknown_encounter", {
                        "encounter_id": encounter_id,
                })

        var working = BattleState.new()
        working.battle_id = String(input.get("battle_id", ""))
        if working.battle_id.is_empty():
                working.battle_id = "battle#1"
        working.node_id = String(input.get("node_id", ""))
        working.encounter_id = encounter_id
        working.character_id = String(input.get("character_id", ""))
        working.difficulty = String(input.get("difficulty", GameConstants.DIFFICULTY_NORMAL))
        working.relics = (input.get("relics", []) as Array).duplicate()
        working.exam_limits = (encounter.get("exam_limits", []) as Array).duplicate()
        working.phase = GameConstants.PHASE_INITIALIZING
        working.round_index = 1
        working.ddl = 0

        var default_vitality: int = catalog.run_int("starting_vitality", 72)
        var max_vitality = int(input.get("max_vitality", default_vitality))
        var vitality = int(input.get("vitality", max_vitality))
        if max_vitality <= 0:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.battle.bad_vitality", {
                        "max_vitality": max_vitality,
                })
        working.player = BattleState.create_player(
                working.allocate_entity_id("p"),
                clampi(vitality, 0, max_vitality),
                max_vitality
        )
        working.player.relax = 0
        working.player.focus = 0

        for raw in (input.get("cards", []) as Array):
                if typeof(raw) != TYPE_DICTIONARY:
                        continue
                var card_input: Dictionary = raw
                var card_id = String(card_input.get("card_id", ""))
                var definition_id = String(card_input.get("definition_id", ""))
                if card_id.is_empty() or definition_id.is_empty():
                        continue
                if catalog.definition(GameConstants.KIND_CARD, definition_id).is_empty():
                        return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.unknown_card", {
                                "definition_id": definition_id,
                        })
                working.add_card(
                        card_id,
                        definition_id,
                        GameConstants.ZONE_DRAW,
                        card_input.get("origin_card_id"),
                        int(card_input.get("upgrade_level", 0))
                )

        var rng = RandomSource.new(0)
        var raw_rng: Variant = input.get("rng_state")
        if raw_rng != null:
                var restored = rng.restore_state(raw_rng)
                if not Result.is_ok(restored):
                        return restored
        var shuffled = rng.shuffle(GameConstants.RNG_BATTLE, working.zones.draw)
        if Result.is_ok(shuffled):
                working.zones.draw = shuffled["data"]

        var task_ids: Array = (encounter.get("tasks", []) as Array)
        var max_ddl = 0
        for raw_task_id in task_ids:
                var task_def: Dictionary = catalog.definition(GameConstants.KIND_TASK, String(raw_task_id))
                if task_def.is_empty():
                        return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.unknown_task", {
                                "task_id": raw_task_id,
                        })
                max_ddl = maxi(max_ddl, int(task_def.get("ddl", 0)))
        if task_ids.size() > 1:
                max_ddl += int(catalog.section("encounters").get("dual_task_ddl_bonus", 0))
        var ddl_offset: int = catalog.difficulty_int(working.difficulty, "ddl_offset", 0)
        working.ddl = maxi(catalog.battle_int("minimum_ddl", 1), max_ddl + ddl_offset)

        for raw_task_id in task_ids:
                working.tasks.append(_create_task(working, String(raw_task_id), "", working.round_index))

        var ctx = _new_ctx(working, rng)
        _advance_until_input(ctx)

        var problems: PackedStringArray = working.validate(catalog.battle_int("unit_slots", 3))
        if not problems.is_empty():
                return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.battle.invalid_state", {
                        "problems": problems,
                })
        return _step_from(ctx)


## Result<ActionPreview>。不改变状态、不消费随机。
func preview(state, draft: Dictionary) -> Dictionary:
        if catalog == null or not catalog.is_loaded():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.catalog_missing", {})
        if state == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.battle.no_state", {})
        var action_type = String(draft.get("type", ""))
        var payload: Dictionary = draft.get("payload", {})
        if action_type == GameConstants.ACTION_PLAY_CARD:
                return _preview_play(state, payload)
        if action_type == GameConstants.ACTION_END_TURN:
                return _preview_end_turn(state, payload)
        if action_type == GameConstants.ACTION_CONFIRM_CHOICE:
                return _preview_choice(state, payload)
        if action_type == GameConstants.ACTION_SET_ALLY_TARGET:
                return _preview_ally_target(state, payload)
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.battle.unknown_action", {
                "type": action_type,
        })


## Result<BattleStep>。state 不被修改；rng_state 为当前战斗随机快照。
func apply(state, action: Dictionary, rng_state: Variant = null) -> Dictionary:
        if catalog == null or not catalog.is_loaded():
                return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.catalog_missing", {})
        if state == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.battle.no_state", {})
        var working = state.copy_for_write()
        var rng = RandomSource.new(0)
        if rng_state != null:
                var restored = rng.restore_state(rng_state)
                if not Result.is_ok(restored):
                        return restored
        var ctx = _new_ctx(working, rng)
        var action_type = String(action.get("type", ""))
        var payload: Dictionary = action.get("payload", {})
        var action_result = Result.ok(null)
        if action_type == GameConstants.ACTION_PLAY_CARD:
                action_result = _play_card(ctx, payload)
        elif action_type == GameConstants.ACTION_CONFIRM_CHOICE:
                action_result = _confirm_choice(ctx, payload)
        elif action_type == GameConstants.ACTION_SET_ALLY_TARGET:
                action_result = _set_ally_target(ctx, payload)
        elif action_type == GameConstants.ACTION_END_TURN:
                action_result = _end_turn(ctx, payload)
        else:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.battle.unknown_action", {
                        "type": action_type,
                })
        if not Result.is_ok(action_result):
                return action_result
        return _step_from(ctx)


## Result<EffectiveCard>：与 apply 使用同一解析函数。
func resolve_face(state, card_id: String) -> Dictionary:
        return BattleCardRules.resolve_face(catalog, state, card_id)


## Result<CostQuote>：与 apply 使用同一费用函数。
func calculate_cost(state, card_id: String) -> Dictionary:
        var face_result = BattleCardRules.resolve_face(catalog, state, card_id)
        if not Result.is_ok(face_result):
                return face_result
        return Result.ok(BattleCardRules.cost_quote(catalog, state, face_result["data"]))

# ── 内部上下文与相位机 ────────────────────────────────────

func _new_ctx(state, rng) -> Dictionary:
        return {
                "state": state,
                "rng": rng,
                "events": [],
                "pending_choice": null,
                "outcome": null,
        }


func _emit(ctx: Dictionary, event_type: String, payload: Dictionary = {}) -> void:
        var event: Dictionary = payload.duplicate(true)
        event["type"] = event_type
        var events: Array = ctx["events"]
        events.append(event)


func _set_phase(ctx: Dictionary, phase: String) -> void:
        var state: BattleState = ctx["state"]
        if state.phase == phase:
                return
        state.phase = phase
        _emit(ctx, EVENT_PHASE_CHANGED, {"phase": phase})


func _step_from(ctx: Dictionary) -> Dictionary:
        var state: BattleState = ctx["state"]
        var pending: Variant = ctx.get("pending_choice")
        var outcome: Variant = ctx.get("outcome")
        if outcome != null:
                state.phase = GameConstants.PHASE_FINISHED
                state.outcome = outcome
        elif pending != null:
                state.phase = GameConstants.PHASE_AWAITING_CHOICE
        var rng: RandomSource = ctx["rng"]
        return Result.ok({
                "state": state,
                "events": ctx["events"],
                "pending_choice": pending,
                "outcome": outcome,
                "stable": pending == null and outcome == null,
                "rng_state": rng.export_state(),
        })


func _make_outcome(state, result: String, reason: String) -> Dictionary:
        var summary = ""
        if result == GameConstants.OUTCOME_WON:
                summary = "任务全部完成"
        elif reason == GameConstants.REASON_DEADLINE_EXPIRED:
                summary = "DDL 超时"
        else:
                summary = "精力归零"
        return {
                "battle_id": state.battle_id,
                "result": result,
                "reason": reason,
                "remaining_vitality": 0 if state.player == null else state.player.vitality,
                "summary": summary,
        }


## 顺序显式：prepare → draw →（停在玩家行动）→ ally → discard → enemy×3 → round_end → 下一轮。
func _advance_until_input(ctx: Dictionary) -> void:
        var guard = 0
        while ctx.get("outcome") == null and guard < 100000:
                guard += 1
                var state: BattleState = ctx["state"]
                var phase = String(state.phase)
                if phase == GameConstants.PHASE_INITIALIZING or phase == GameConstants.PHASE_PLAYER_PREPARE:
                        _run_player_prepare(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_DRAW)
                elif phase == GameConstants.PHASE_DRAW:
                        _run_draw_phase(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_PLAYER_ACTION)
                        break
                elif phase == GameConstants.PHASE_PLAYER_ACTION:
                        break
                elif phase == GameConstants.PHASE_AWAITING_CHOICE:
                        break
                elif phase == GameConstants.PHASE_ALLY_ACTION:
                        _run_ally_phase(ctx)
                        _check_outcome(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_DISCARD)
                elif phase == GameConstants.PHASE_DISCARD:
                        _run_discard_phase(ctx)
                        _check_outcome(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_ENEMY_PREPARE)
                elif phase == GameConstants.PHASE_ENEMY_PREPARE:
                        _run_enemy_prepare(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_ENEMY_SKILL)
                elif phase == GameConstants.PHASE_ENEMY_SKILL:
                        _run_enemy_skill(ctx)
                        _check_outcome(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_ENEMY_PRESSURE)
                elif phase == GameConstants.PHASE_ENEMY_PRESSURE:
                        _run_enemy_pressure(ctx)
                        _check_outcome(ctx)
                        if ctx.get("outcome") != null:
                                break
                        _set_phase(ctx, GameConstants.PHASE_ROUND_END)
                elif phase == GameConstants.PHASE_ROUND_END:
                        _run_round_end(ctx)
                        if ctx.get("outcome") != null:
                                break
                        state.round_index += 1
                        _advance_intents(ctx)
                        _reset_round_counters(state)
                        _set_phase(ctx, GameConstants.PHASE_PLAYER_PREPARE)
                elif phase == GameConstants.PHASE_FINISHED:
                        break
                else:
                        break
        if ctx.get("outcome") != null:
                _finish(ctx)


func _finish(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        state.phase = GameConstants.PHASE_FINISHED
        state.outcome = ctx["outcome"]
        _emit(ctx, EVENT_BATTLE_FINISHED, {
                "result": state.outcome.get("result", ""),
                "reason": state.outcome.get("reason", ""),
        })


# ── 玩家准备 / 抽牌 / 弃牌 ────────────────────────────────

func _run_player_prepare(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var player = state.player
        player.relax = 0
        for unit in state.units:
                unit.relax = 0

        var anxiety_stacks = _status_stacks(state, player.entity_id, GameConstants.STATUS_ANXIETY)
        var penalty = anxiety_stacks * catalog.status_int(GameConstants.STATUS_ANXIETY, "focus_penalty_per_stack", 1)
        _remove_statuses_by_expiry(ctx, "prepare")
        _reset_round_counters(state)

        var focus: int = catalog.battle_int("base_focus_per_turn", 3)
        if _status_stacks(state, player.entity_id, GameConstants.STATUS_FLOW) > 0:
                focus += catalog.status_int(GameConstants.STATUS_FLOW, "focus_bonus_when_present", 1)
        focus -= penalty
        player.focus = clampi(focus, 0, catalog.battle_int("focus_cap", 10))
        _emit(ctx, EVENT_FOCUS_CHANGED, {"focus": player.focus})

        _run_relic_hooks(ctx, GameConstants.HOOK_ROUND_START, {})
        if state.scene != null:
                _run_scene_prepare(ctx)
        _emit(ctx, EVENT_ROUND_STARTED, {"round_index": state.round_index})


func _run_draw_phase(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var count: int = catalog.battle_int("base_draw_per_turn", 5)
        var procrastination = _status_stacks(state, state.player.entity_id, GameConstants.STATUS_PROCRASTINATION)
        if procrastination > 0:
                var per_stack: int = catalog.status_int(GameConstants.STATUS_PROCRASTINATION, "draw_penalty_per_stack", 1)
                count = maxi(0, count - procrastination * per_stack)
        _draw_cards(ctx, count)
        _run_relic_hooks(ctx, GameConstants.HOOK_DRAW, {})
        _remove_statuses_by_expiry(ctx, "draw")


func _run_ally_phase(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var order = state.units.duplicate()
        order.sort_custom(func(a, b): return a.entered_order < b.entered_order)
        for unit in order:
                if ctx.get("outcome") != null:
                        return
                if state.find_unit(unit.unit_id) == null:
                        continue
                if unit.last_acted_round == state.round_index or unit.vitality <= 0:
                        continue
                _run_unit_support(ctx, unit)
                if ctx.get("outcome") != null:
                        return
                var task = _coop_target(state, unit)
                if task != null:
                        _apply_completion(ctx, task.task_id, maxi(0, unit.cooperation), "cooperation")
                        _check_outcome(ctx)
                        if ctx.get("outcome") != null:
                                return
                unit.vitality -= catalog.battle_int("unit_action_vitality_cost", 1)
                unit.last_acted_round = state.round_index
                unit.actions_taken += 1
                _emit(ctx, EVENT_VITALITY_CHANGED, {
                        "holder_id": unit.unit_id,
                        "vitality": maxi(0, unit.vitality),
                })
                if unit.vitality <= 0:
                        _depart_unit(ctx, unit, "exhausted")
                _check_outcome(ctx)


func _run_discard_phase(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        # end_turn 声明的保留牌留在手牌（K19 等放宽保留上限）；读完即清空，不跨回合残留。
        var kept: Array = state.retained_card_ids.duplicate()
        state.retained_card_ids = []
        var hand = state.card_ids_in(GameConstants.ZONE_HAND)
        for card_id in hand:
                if kept.has(card_id):
                        continue
                _discard_card(ctx, String(card_id))


# ── 任务准备 / 技能 / 压力 / 轮末 ─────────────────────────

func _run_enemy_prepare(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        for task in state.tasks:
                task.shield = 0
        _remove_statuses_by_expiry(ctx, "enemy_prepare")


func _run_enemy_skill(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var snapshot = state.tasks.duplicate()
        for task in snapshot:
                if ctx.get("outcome") != null:
                        return
                if state.find_task(task.task_id) == null:
                        continue
                if not _task_actionable(state, task):
                        continue
                var intent = _current_intent(state, task)
                if intent.is_empty():
                        continue
                if intent.has("shield"):
                        task.shield += maxi(0, int(intent["shield"]))
                if intent.has("work_restore"):
                        task.work_remaining = mini(task.work_max, task.work_remaining + maxi(0, int(intent["work_restore"])))
                if intent.has("extra_requirements"):
                        _gain_status(ctx, task.task_id, GameConstants.STATUS_EXTRA_REQUIREMENTS, maxi(1, int(intent["extra_requirements"])))
                if intent.has("gain_status"):
                        var spec: Dictionary = intent["gain_status"]
                        var holder = _intent_holder(state, task, spec)
                        if not holder.is_empty():
                                _gain_status(ctx, holder, String(spec.get("status", "")), maxi(1, int(spec.get("stacks", 1))))
                if intent.has("add_card"):
                        _add_temporary_card(ctx, intent["add_card"])
                _emit(ctx, EVENT_ENEMY_SKILL, {
                        "task_id": task.task_id,
                        "index": int(intent.get("index", 0)),
                })


func _run_enemy_pressure(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var snapshot = state.tasks.duplicate()
        for task in snapshot:
                if ctx.get("outcome") != null:
                        return
                if state.find_task(task.task_id) == null:
                        continue
                if not _task_actionable(state, task):
                        continue
                var intent = _current_intent(state, task)
                if intent.is_empty():
                        continue
                if intent.has("pressure"):
                        var segments = int(intent.get("pressure_times", 1))
                        var base = int(intent["pressure"])
                        for _segment in range(maxi(1, segments)):
                                if ctx.get("outcome") != null:
                                        return
                                _apply_pressure_single(ctx, base, task.task_id)
                                _check_outcome(ctx)
                if intent.has("pressure_all"):
                        _apply_pressure_all(ctx, int(intent["pressure_all"]))
                        _check_outcome(ctx)


func _run_round_end(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        if state.scene != null:
                var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
                _run_effects_now(ctx, scene_def.get("round_end_effects", []), [])
        if ctx.get("outcome") != null:
                return
        _remove_statuses_by_expiry(ctx, "round_end")
        for status_id in ROUND_END_CLEAR_STATUSES:
                _remove_status_all(ctx, state.player.entity_id, status_id)
                for unit in state.units:
                        _remove_status_all(ctx, unit.unit_id, status_id)
        _check_outcome(ctx)
        if ctx.get("outcome") != null:
                return
        state.ddl -= 1
        _emit(ctx, EVENT_DDL_TICKED, {"ddl": state.ddl, "round_index": state.round_index})
        if state.ddl <= 0:
                ctx["outcome"] = _make_outcome(state, GameConstants.OUTCOME_LOST, GameConstants.REASON_DEADLINE_EXPIRED)


func _advance_intents(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        for task in state.tasks:
                var definition: Dictionary = catalog.definition(GameConstants.KIND_TASK, task.definition_id)
                task.intent_cursor = int(task.intent_cursor) + 1
                task.intent_snapshot = _intent_snapshot(definition, task.phase_key, task.intent_cursor)
                _emit(ctx, EVENT_INTENT_REVEALED, {
                        "task_id": task.task_id,
                        "index": int(task.intent_snapshot.get("index", 0)),
                })


func _check_outcome(ctx: Dictionary) -> void:
        if ctx.get("outcome") != null:
                return
        var state: BattleState = ctx["state"]
        if state.player == null:
                return
        if state.player.vitality <= 0:
                ctx["outcome"] = _make_outcome(state, GameConstants.OUTCOME_LOST, GameConstants.REASON_VITALITY_DEPLETED)
                return
        if state.tasks.is_empty():
                ctx["outcome"] = _make_outcome(state, GameConstants.OUTCOME_WON, GameConstants.REASON_TASKS_COMPLETED)

# ── 战斗操作 ──────────────────────────────────────────────

func _play_card(ctx: Dictionary, payload: Dictionary) -> Dictionary:
        var state: BattleState = ctx["state"]
        var plan_result = BattleCardRules.validate_play(catalog, state, payload)
        if not Result.is_ok(plan_result):
                return plan_result
        var plan: Dictionary = plan_result["data"]
        var face: Dictionary = plan["face"]
        var quote: Dictionary = plan["quote"]
        var card = plan["card"]

        state.player.focus -= int(quote.get("cost", 0))
        _emit(ctx, EVENT_FOCUS_CHANGED, {"focus": state.player.focus, "spent": int(quote.get("cost", 0))})
        # 主动支付的精力代价：绕过放松，直接扣精力（[ENG-003]；预检已保证支付后 ≥ 下限）。
        var vitality_cost = maxi(0, int(quote.get("vitality_cost", 0)))
        if vitality_cost > 0:
                state.player.vitality = state.player.vitality - vitality_cost
                _emit(ctx, EVENT_VITALITY_CHANGED, {
                        "holder_id": state.player.entity_id,
                        "vitality": state.player.vitality,
                        "paid": vitality_cost,
                })
        _consume_cost_sources(ctx, face)

        state.move_card(card.card_id, GameConstants.ZONE_RESOLVING)
        _emit(ctx, EVENT_CARD_PLAYED, {
                "card_id": card.card_id,
                "definition_id": card.definition_id,
                "exam_face": String(face.get("exam_face", "")),
                "cost": int(quote.get("cost", 0)),
        })

        # 「本回合打过某定义」条件的唯一数据来源；回合计数。
        _bump_counter(
                ctx,
                GameConstants.COUNTER_SCOPE_ROUND,
                GameConstants.COUNTER_OWNER_PLAYED_PREFIX + card.definition_id,
                GameConstants.COUNTER_TRIGGER_PLAYED
        )

        var limit: Variant = face.get("limit")
        if typeof(limit) == TYPE_DICTIONARY:
                _bump_counter(
                        ctx,
                        String((limit as Dictionary).get("per", "")),
                        BattleCardRules.instance_owner(state, card.card_id),
                        BattleCardRules.limit_trigger(face)
                )

        var resolution = BattleState.create_resolution({
                "card_id": card.card_id,
                "definition_id": card.definition_id,
                "target_ids": plan["target_ids"],
                "replace_unit_id": plan["replace_unit_id"],
                "face": face,
        })
        resolution.queue = (face.get("effects", []) as Array).duplicate(true)
        resolution.effect_cursor = 0
        resolution.locked_target_ids = (plan["target_ids"] as Array).duplicate()
        state.resolution = resolution
        # 卡面 pre_effects（K52/K53 的「建立前」，K12 升级的「获得2放松后再执行」）：
        # 整张牌结算前执行一次；考试替代面会清空 pre_effects，不叠加。
        var pre_effects: Variant = face.get("pre_effects")
        if typeof(pre_effects) == TYPE_ARRAY and not (pre_effects as Array).is_empty():
                _run_effects_now(ctx, pre_effects, resolution.locked_target_ids)

        state.phase = GameConstants.PHASE_PLAYER_ACTION

        _execute_queue(ctx)
        return Result.ok(null)


func _confirm_choice(ctx: Dictionary, payload: Dictionary) -> Dictionary:
        var state: BattleState = ctx["state"]
        # 待选是跨调用的：真相存在 state.resolution.choice，而不是本次 ctx。
        var choice: Variant = null
        if state.resolution != null:
                choice = state.resolution.choice
        if choice == null or state.resolution == null:
                return Result.fail(GameConstants.ERROR_ALREADY_RESOLVED, "error.choice.none_pending", {})
        var request: Dictionary = choice
        var choice_id = String(payload.get("choice_id", ""))
        if choice_id != String(request.get("choice_id", "")):
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.choice.id_mismatch", {
                        "expected": request.get("choice_id"),
                        "got": choice_id,
                })
        var selected: Array = (payload.get("selected_ids", []) as Array)
        var min_count = int(request.get("min_count", 0))
        var max_count = int(request.get("max_count", 0))
        if selected.size() < min_count or selected.size() > max_count:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.choice.bad_count", {
                        "min": min_count,
                        "max": max_count,
                        "got": selected.size(),
                })
        var candidates = {}
        for option in (request.get("candidates", []) as Array):
                candidates[String((option as Dictionary).get("id", ""))] = true
        var unique = {}
        for raw_id in selected:
                var selected_id = String(raw_id)
                if not candidates.has(selected_id):
                        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.choice.not_a_candidate", {
                                "id": selected_id,
                        })
                if unique.has(selected_id):
                        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.choice.duplicate_selection", {
                                "id": selected_id,
                        })
                unique[selected_id] = true

        var kind = String(request.get("kind", ""))
        var applied_count = 0
        if kind == GameConstants.CHOICE_DISCARD:
                for raw_id in selected:
                        _discard_card(ctx, String(raw_id))
                applied_count = selected.size()
        elif kind == GameConstants.CHOICE_RECALL:
                for raw_id in selected:
                        if _recall_card(ctx, String(raw_id)):
                                applied_count += 1
        elif kind == GameConstants.CHOICE_PURIFY:
                applied_count = _purify_status(ctx, String(selected[0]), int(request.get("effect_amount", 1)))
        _emit(ctx, EVENT_CHOICE_CONFIRMED, {"choice_id": choice_id, "kind": kind})

        var resolution = state.resolution
        resolution.choice_counts[kind] = applied_count
        resolution.choice = null
        ctx["pending_choice"] = null
        state.phase = GameConstants.PHASE_PLAYER_ACTION
        resolution.effect_cursor += 1
        _execute_queue(ctx)
        return Result.ok(null)


func _set_ally_target(ctx: Dictionary, payload: Dictionary) -> Dictionary:
        var state: BattleState = ctx["state"]
        if String(state.phase) != GameConstants.PHASE_PLAYER_ACTION:
                return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.ally.not_player_action", {"phase": state.phase})
        if state.resolution != null:
                return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.play.choice_pending", {})
        var unit = state.find_unit(String(payload.get("unit_id", "")))
        var task = state.find_task(String(payload.get("task_id", "")))
        if unit == null or task == null or task.work_remaining <= 0:
                return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.ally.invalid_target", {
                        "unit_id": payload.get("unit_id"),
                        "task_id": payload.get("task_id"),
                })
        unit.target_id = task.task_id
        _emit(ctx, EVENT_COOP_TARGET_SET, {"unit_id": unit.unit_id, "task_id": task.task_id})
        return Result.ok(null)


func _end_turn(ctx: Dictionary, payload: Dictionary) -> Dictionary:
        var state: BattleState = ctx["state"]
        if state.resolution != null or ctx.get("pending_choice") != null:
                return Result.fail(GameConstants.ERROR_CHOICE_PENDING, "error.turn.choice_pending", {})
        if String(state.phase) != GameConstants.PHASE_PLAYER_ACTION:
                return Result.fail(GameConstants.ERROR_WRONG_PHASE, "error.turn.not_player_action", {"phase": state.phase})

        var allowed = catalog.battle_int("base_retention_count", DEFAULT_RETENTION)
        # K19「保留另一张手牌」：本回合获得的保留额度（回合计数，轮末自动失效）。
        allowed += _counter_count(
                state,
                GameConstants.COUNTER_SCOPE_ROUND,
                GameConstants.COUNTER_OWNER_RETAIN,
                GameConstants.COUNTER_TRIGGER_RETAIN
        )
        var retained: Array = (payload.get("retained_card_ids", []) as Array)
        var unique = {}
        for raw_id in retained:
                var card_id = String(raw_id)
                if unique.has(card_id):
                        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.turn.duplicate_retention", {"card_id": card_id})
                unique[card_id] = true
                if state.zone_of(card_id) != GameConstants.ZONE_HAND:
                        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.turn.retention_not_in_hand", {"card_id": card_id})
        if retained.size() > allowed:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.turn.too_many_retained", {
                        "allowed": allowed,
                        "got": retained.size(),
                })

        state.retained_card_ids = retained.duplicate()
        state.phase = GameConstants.PHASE_ALLY_ACTION
        _emit(ctx, EVENT_PHASE_CHANGED, {"phase": state.phase})
        _advance_until_input(ctx)
        return Result.ok(null)


# ── 出牌结算队列 ──────────────────────────────────────────

func _execute_queue(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var guard = 0
        while state.resolution != null and ctx.get("outcome") == null and guard < 100000:
                guard += 1
                var resolution = state.resolution
                if resolution.effect_cursor >= resolution.queue.size():
                        _finalize_play(ctx)
                        return
                var effect: Dictionary = resolution.queue[resolution.effect_cursor]
                if _start_effect_choice(ctx, effect):
                        return
                var face: Dictionary = resolution.action.get("face", {})
                _apply_effect(
                        ctx,
                        effect,
                        resolution.locked_target_ids,
                        _is_first_complete_segment(resolution),
                        String(face.get("type", ""))
                )
                resolution.effect_cursor += 1
        if state.resolution != null and (ctx.get("outcome") != null or state.resolution.effect_cursor >= state.resolution.queue.size()):
                _finalize_play(ctx)


func _is_first_complete_segment(resolution) -> bool:
        for index in range(resolution.effect_cursor):
                if String((resolution.queue[index] as Dictionary).get("op", "")) == GameConstants.OP_COMPLETE:
                        return false
        return true


## 效果内选择分派：返回 true 表示已挂起待选，调用方必须立刻返回。
## 三个 kind 共用同一套 pending_choice / candidates / ResolutionState.choice 机制。
func _start_effect_choice(ctx: Dictionary, effect: Dictionary) -> bool:
        var op = String(effect.get("op", ""))
        if op == GameConstants.OP_DISCARD:
                return _start_discard_choice(ctx, effect)
        if op == GameConstants.OP_RECALL_FROM_DISCARD:
                return _start_recall_choice(ctx, effect)
        if op == GameConstants.OP_REMOVE_STATUS and String(effect.get("category", "")) == GameConstants.STATUS_CATEGORY_NEGATIVE:
                return _start_purify_choice(ctx, effect)
        return false


## 本次结算里最近一次指定种类选择的实际生效数量（未发生过该种类选择时为 0）。
func _last_choice_count(state, kind: String) -> int:
        if state == null or state.resolution == null:
                return 0
        return maxi(0, int(state.resolution.choice_counts.get(kind, 0)))


## K07 复盘：从弃牌堆选 amount 张加入手牌。候选 = 弃牌堆（公开信息）。
func _start_recall_choice(ctx: Dictionary, effect: Dictionary) -> bool:
        var state: BattleState = ctx["state"]
        var amount = maxi(1, int(effect.get("amount", 1)))
        var candidates = []
        for card_id in state.card_ids_in(GameConstants.ZONE_DISCARD):
                var card = state.get_card(String(card_id))
                if card == null:
                        continue
                var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
                candidates.append({
                        "id": card.card_id,
                        "label_key": String(definition.get("name_key", "")),
                        "preview": {"definition_id": card.definition_id, "upgrade_level": card.upgrade_level},
                })
        if candidates.size() < amount:
                return false
        var request = {
                "choice_id": state.allocate_entity_id("ch"),
                "kind": GameConstants.CHOICE_RECALL,
                "prompt_key": "choice.recall",
                "candidates": candidates,
                "min_count": amount,
                "max_count": amount,
                "effect_amount": amount,
                "source_card_id": state.resolution.action.get("card_id", ""),
        }
        state.resolution.choice = request
        ctx["pending_choice"] = request
        _emit(ctx, EVENT_CHOICE_REQUESTED, {"choice_id": request["choice_id"], "kind": request["kind"]})
        return true


## K16 调试：净化 2 层负面（《统一设计文档》§3.6「由玩家选焦虑/拖延/困倦之一」）。
## 候选 = 玩家身上层数 > 0 的可净化状态；一个都没有时不挂起待选，卡牌其余部分照常结算。
func _start_purify_choice(ctx: Dictionary, effect: Dictionary) -> bool:
        var state: BattleState = ctx["state"]
        var amount = maxi(1, int(effect.get("amount", 1)))
        var candidates = []
        for status_id in GameConstants.NEGATIVE_STATUS_IDS:
                var status = state.find_status(state.player.entity_id, String(status_id))
                if status == null or int(status.stacks) <= 0:
                        continue
                candidates.append({
                        "id": String(status_id),
                        "label_key": "status." + String(status_id),
                        "preview": {"status_id": String(status_id), "stacks": int(status.stacks)},
                })
        if candidates.is_empty():
                return false
        var request = {
                "choice_id": state.allocate_entity_id("ch"),
                "kind": GameConstants.CHOICE_PURIFY,
                "prompt_key": "choice.purify",
                "candidates": candidates,
                "min_count": 1,
                "max_count": 1,
                "effect_amount": amount,
                "source_card_id": state.resolution.action.get("card_id", ""),
        }
        state.resolution.choice = request
        ctx["pending_choice"] = request
        _emit(ctx, EVENT_CHOICE_REQUESTED, {"choice_id": request["choice_id"], "kind": request["kind"]})
        return true


## 取回：只在弃牌堆时才移动，其余情况不动（返回 false，不产生副作用）。
func _recall_card(ctx: Dictionary, card_id: String) -> bool:
        var state: BattleState = ctx["state"]
        if state.zone_of(card_id) != GameConstants.ZONE_DISCARD:
                return false
        if not state.move_card(card_id, GameConstants.ZONE_HAND):
                return false
        _emit(ctx, EVENT_CARD_RECALLED, {"card_id": card_id})
        return true


## 净化：只作用于可净化负面状态，返回实际移除层数。
func _purify_status(ctx: Dictionary, status_id: String, stacks: int) -> int:
        var state: BattleState = ctx["state"]
        if not GameConstants.NEGATIVE_STATUS_IDS.has(status_id):
                return 0
        return _remove_status(ctx, state.player.entity_id, status_id, maxi(1, stacks))


func _start_discard_choice(ctx: Dictionary, effect: Dictionary) -> bool:
        var state: BattleState = ctx["state"]
        var amount = maxi(1, int(effect.get("amount", 1)))
        # up_to=true = 「至多 amount 张」（可选 0，K12）；否则为恰好 count 张（K03）。
        var up_to = bool(effect.get("up_to", false))
        var candidates = []
        for card_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(card_id))
                if card == null:
                        continue
                var definition: Dictionary = catalog.definition(GameConstants.KIND_CARD, card.definition_id)
                candidates.append({
                        "id": card.card_id,
                        "label_key": String(definition.get("name_key", "")),
                        "preview": {"definition_id": card.definition_id, "upgrade_level": card.upgrade_level},
                })
        if candidates.is_empty():
                return false
        var count = mini(amount, candidates.size())
        var request = {
                "choice_id": state.allocate_entity_id("ch"),
                "kind": GameConstants.CHOICE_DISCARD,
                "prompt_key": "choice.discard",
                "candidates": candidates,
                "min_count": 0 if up_to else count,
                "max_count": count,
                "effect_amount": amount,
                "source_card_id": state.resolution.action.get("card_id", ""),
        }
        state.resolution.choice = request
        ctx["pending_choice"] = request
        _emit(ctx, EVENT_CHOICE_REQUESTED, {"choice_id": request["choice_id"], "kind": request["kind"]})
        return true


func _finalize_play(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var resolution = state.resolution
        if resolution == null:
                return
        var face: Dictionary = resolution.action.get("face", {})
        var card_id = String(resolution.action.get("card_id", ""))
        var card = state.get_card(card_id)
        if card != null:
                var destination = GameConstants.ZONE_EXHAUST if bool(face.get("exhaust", false)) else GameConstants.ZONE_DISCARD
                state.move_card(card_id, destination)
                _emit(ctx, EVENT_CARD_RESOLVED, {"card_id": card_id, "destination": destination})

        if String(face.get("type", "")) == GameConstants.CARD_WORK:
                _remove_status_all(ctx, state.player.entity_id, GameConstants.STATUS_INSPIRATION)
                _remove_status_all(ctx, state.player.entity_id, GameConstants.STATUS_DROWSINESS)
        _handle_work_card_resolved(ctx, face)
        _run_relic_hooks(ctx, GameConstants.HOOK_CARD_RESOLVED, face)

        state.resolution = null
        ctx["pending_choice"] = null
        state.phase = GameConstants.PHASE_PLAYER_ACTION
        _check_outcome(ctx)


func _consume_cost_sources(ctx: Dictionary, face: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        if String(face.get("type", "")) == GameConstants.CARD_WORK and state.scene != null:
                var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
                var modifiers: Variant = scene_def.get("modifiers")
                if typeof(modifiers) == TYPE_DICTIONARY and int((modifiers as Dictionary).get("first_work_cost_discount", 0)) > 0:
                        _bump_counter(ctx, GameConstants.COUNTER_SCOPE_ROUND, "scene:" + String(state.scene.definition_id), "first_work_cost")
        # 消费本张牌实际用到的饰品费用 hook（与 cost_quote 同一套匹配）：出牌成功后只消费一次。
        var relic_quote := BattleCardRules.relic_cost_hooks(catalog, state, face)
        for entry in (relic_quote["matches"] as Array):
                _bump_counter(ctx, String((entry as Dictionary)["per"]), String((entry as Dictionary)["owner_key"]), String((entry as Dictionary)["trigger"]))


## 人物被动：按 trigger 认牌型计数，达到 count 后按 limit 触发一次。
##   work_card_resolved          P01「每回合第 3 张工作牌」（计数键 work_resolved，行为与键名都不变）
##   cooperation_card_resolved   P04「每回合首张合作牌」（计数键 cooperation_resolved）
## 考试替代面只换正文、不换 type（§3.4），所以备考面照样算一次「合作牌结算」。
func _handle_work_card_resolved(ctx: Dictionary, face: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        if state.character_id.is_empty():
                return
        var character: Dictionary = catalog.definition(GameConstants.KIND_CHARACTER, state.character_id)
        var passive: Variant = character.get("passive")
        if typeof(passive) != TYPE_DICTIONARY:
                return
        var passive_dict: Dictionary = passive
        var trigger := String(passive_dict.get("trigger", ""))
        var card_type := String(face.get("type", ""))
        if trigger == GameConstants.PASSIVE_TRIGGER_WORK_RESOLVED:
                if card_type != GameConstants.CARD_WORK:
                        return
        elif trigger == GameConstants.PASSIVE_TRIGGER_COOPERATION_RESOLVED:
                if card_type != GameConstants.CARD_COOPERATION:
                        return
        else:
                return
        var passive_id = String(passive_dict.get("id", "passive"))
        var counter_trigger := trigger.replace("_card_resolved", "_resolved")
        var resolved_count = _bump_counter(ctx, GameConstants.COUNTER_SCOPE_ROUND, passive_id, counter_trigger)
        var limit: Variant = passive_dict.get("limit")
        var times = 1
        if typeof(limit) == TYPE_DICTIONARY:
                times = maxi(1, int((limit as Dictionary).get("times", 1)))
        var fired = _counter_count(state, GameConstants.COUNTER_SCOPE_ROUND, passive_id, "fired")
        if resolved_count >= maxi(1, int(passive_dict.get("count", 3))) and fired < times:
                _bump_counter(ctx, GameConstants.COUNTER_SCOPE_ROUND, passive_id, "fired")
                _run_effects_now(ctx, passive_dict.get("effects", []), [])


# ── 预览 ──────────────────────────────────────────────────

func _preview_play(state, payload: Dictionary) -> Dictionary:
        var errors = []
        var face = {}
        var quote = {}
        var required = []
        var card_id = String(payload.get("card_id", ""))
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.play.card_id_required", {})
        var face_result = BattleCardRules.resolve_face(catalog, state, card_id)
        if Result.is_ok(face_result):
                face = face_result["data"]
                quote = BattleCardRules.cost_quote(catalog, state, face)
        var plan_result = BattleCardRules.validate_play(catalog, state, payload)
        if Result.is_ok(plan_result):
                face = plan_result["data"]["face"]
                quote = plan_result["data"]["quote"]
        else:
                errors.append(plan_result["error"])
        if String(face.get("target", "")) == GameConstants.TARGET_TASK:
                var target_ids: Array = (payload.get("target_ids", []) as Array)
                if target_ids.size() != 1:
                        required.append("target_ids")
        if not face.is_empty() and String(face.get("type", "")) == GameConstants.CARD_COOPERATION:
                if String(face.get("exam_face", "")).is_empty() and state.units.size() >= catalog.battle_int("unit_slots", 3):
                        if payload.get("replace_unit_id") == null:
                                required.append("replace_unit_id")
        return Result.ok({
                "can_submit": errors.is_empty() and required.is_empty(),
                "required_selections": required,
                "costs": {
                        "focus": int(quote.get("cost", 0)),
                        "vitality": int(quote.get("vitality_cost", 0)),
                },
                "known_effects": face.get("effects", []),
                "unknown_effects": [],
                "effective_card": face,
                "blocking_errors": errors,
        })


func _preview_end_turn(state, _payload: Dictionary) -> Dictionary:
        var errors = []
        if String(state.phase) != GameConstants.PHASE_PLAYER_ACTION:
                errors.append({
                        "code": GameConstants.ERROR_WRONG_PHASE,
                        "message_key": "error.turn.not_player_action",
                        "details": {"phase": state.phase},
                })
        if state.resolution != null:
                errors.append({
                        "code": GameConstants.ERROR_CHOICE_PENDING,
                        "message_key": "error.turn.choice_pending",
                        "details": {},
                })
        return Result.ok({
                "can_submit": errors.is_empty(),
                "required_selections": [],
                "costs": {"focus": 0, "vitality": 0},
                "known_effects": [{"op": "end_turn"}],
                "unknown_effects": [],
                "effective_card": null,
                "blocking_errors": errors,
        })


func _preview_choice(state, payload: Dictionary) -> Dictionary:
        var errors = []
        if state.resolution == null or state.resolution.choice == null:
                errors.append({
                        "code": GameConstants.ERROR_ALREADY_RESOLVED,
                        "message_key": "error.choice.none_pending",
                        "details": {},
                })
        return Result.ok({
                "can_submit": errors.is_empty(),
                "required_selections": ["selected_ids"],
                "costs": {"focus": 0, "vitality": 0},
                "known_effects": [],
                "unknown_effects": [],
                "effective_card": null,
                "blocking_errors": errors,
        })


func _preview_ally_target(state, payload: Dictionary) -> Dictionary:
        var errors = []
        if state.find_unit(String(payload.get("unit_id", ""))) == null or state.find_task(String(payload.get("task_id", ""))) == null:
                errors.append({
                        "code": GameConstants.ERROR_INVALID_TARGET,
                        "message_key": "error.ally.invalid_target",
                        "details": {},
                })
        return Result.ok({
                "can_submit": errors.is_empty(),
                "required_selections": [],
                "costs": {"focus": 0, "vitality": 0},
                "known_effects": [{"op": "set_ally_target"}],
                "unknown_effects": [],
                "effective_card": null,
                "blocking_errors": errors,
        })

# ── 效果执行（卡牌 / 场景 / 支援 / 意图共用）──────────────

func _run_effects_now(ctx: Dictionary, raw_effects: Variant, target_ids: Array) -> void:
        if typeof(raw_effects) != TYPE_ARRAY:
                return
        for raw in (raw_effects as Array):
                if ctx.get("outcome") != null:
                        return
                if typeof(raw) != TYPE_DICTIONARY:
                        continue
                _apply_effect(ctx, raw, target_ids, false, "")


## 返回 true 表示该 op 已被处理（未知 op 在内容层就应被拒绝）。
## 饰品 hook 执行器：找当前生效的 hook → 先消费限次计数 → 再跑 effects。
## 限次走 TriggerCounter 组合键（per=battle/round/instance_round），不另立计数器。
func _run_relic_hooks(ctx: Dictionary, at: String, face: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        if state.relics.is_empty():
                return
        for entry in BattleCardRules.matched_relic_hooks(catalog, state, at, face):
                var hook: Dictionary = entry["hook"]
                var effects: Variant = hook.get("effects")
                if typeof(effects) != TYPE_ARRAY or (effects as Array).is_empty():
                        continue
                _bump_counter(ctx, String(entry["per"]), String(entry["owner_key"]), String(entry["trigger"]))
                _emit(ctx, EVENT_RELIC_TRIGGERED, {
                        "relic_id": String(entry["relic_id"]),
                        "hook_index": int(entry["hook_index"]),
                        "at": at,
                })
                _run_effects_now(ctx, effects, [])
                if ctx.get("outcome") != null:
                        return


func _apply_effect(ctx: Dictionary, effect: Dictionary, target_ids: Array, is_first_segment: bool, card_type: String) -> bool:
        var state: BattleState = ctx["state"]
        var op = String(effect.get("op", ""))
        if op == GameConstants.OP_COMPLETE:
                _effect_complete(ctx, effect, target_ids, is_first_segment, card_type == GameConstants.CARD_WORK)
                return true
        if op == GameConstants.OP_RELAX:
                var amount = maxi(0, int(effect.get("amount", 0)))
                var relax_target = String(effect.get("target", "player"))
                if relax_target == "task":
                        var task = _primary_task(state, target_ids)
                        if task != null:
                                task.shield += amount
                elif relax_target == "unit":
                        var unit = _first_unit(state)
                        if unit != null:
                                unit.relax += amount
                else:
                        state.player.relax += amount
                _emit(ctx, EVENT_VITALITY_CHANGED, {"relax_gained": amount, "target": relax_target})
                return true
        if op == GameConstants.OP_DRAW:
                var draw_amount = maxi(0, int(effect.get("amount", 0)))
                var per_discarded = maxi(0, int(effect.get("per_discarded", 0)))
                if per_discarded > 0:
                        draw_amount += per_discarded * _last_choice_count(state, GameConstants.CHOICE_DISCARD)
                _draw_cards(ctx, draw_amount)
                return true
        if op == GameConstants.OP_GAIN_STATUS:
                var holder_id = _status_holder_id(state, effect, target_ids)
                if not holder_id.is_empty():
                        _gain_status(ctx, holder_id, String(effect.get("status", "")), maxi(1, int(effect.get("stacks", 1))))
                return true
        if op == GameConstants.OP_SUMMON_UNIT:
                _effect_summon(ctx, effect)
                return true
        if op == GameConstants.OP_ESTABLISH_SCENE:
                _effect_establish_scene(ctx, effect)
                return true
        if op == GameConstants.OP_HEAL:
                _effect_heal(ctx, maxi(0, int(effect.get("amount", 0))))
                return true
        if op == GameConstants.OP_GAIN_FOCUS:
                _effect_gain_focus(ctx, maxi(0, int(effect.get("amount", 0))))
                return true
        if op == GameConstants.OP_LOSE_VITALITY:
                _effect_lose_vitality(ctx, maxi(0, int(effect.get("amount", 0))))
                return true
        if op == GameConstants.OP_PRESSURE:
                _apply_pressure_single(ctx, maxi(0, int(effect.get("amount", 0))))
                return true
        if op == GameConstants.OP_RESTORE_WORK:
                _effect_restore_work(ctx, effect, target_ids)
                return true
        if op == GameConstants.OP_REMOVE_STATUS:
                _effect_remove_status(ctx, effect, target_ids)
                return true
        if op == GameConstants.OP_RETAIN_HAND_CARD:
                var retain_amount = maxi(1, int(effect.get("amount", 1)))
                var granted = _add_counter(
                        ctx,
                        GameConstants.COUNTER_SCOPE_ROUND,
                        GameConstants.COUNTER_OWNER_RETAIN,
                        GameConstants.COUNTER_TRIGGER_RETAIN,
                        retain_amount
                )
                _emit(ctx, EVENT_RETENTION_GRANTED, {"amount": retain_amount, "total": granted})
                return true
        if op == GameConstants.OP_WORK_FLAT_BONUS:
                return true
        return false

func _effect_complete(ctx: Dictionary, effect: Dictionary, target_ids: Array, is_first_segment: bool, is_work_card: bool) -> void:
        var state: BattleState = ctx["state"]
        var task = _primary_task(state, target_ids)
        if task == null:
                return
        var amount = _completion_amount(ctx, effect, is_first_segment, is_work_card)
        _apply_completion(ctx, task.task_id, amount, "complete")


func _completion_amount(ctx: Dictionary, effect: Dictionary, is_first_segment: bool, is_work_card: bool) -> int:
        var state: BattleState = ctx["state"]
        var amount = maxi(0, int(effect.get("amount", 0)))
        var bonus_if: Variant = effect.get("bonus_if")
        if typeof(bonus_if) == TYPE_DICTIONARY and _bonus_condition_met(state, bonus_if):
                amount += maxi(0, int((bonus_if as Dictionary).get("amount", 0)))
        if not (is_first_segment and is_work_card):
                return maxi(0, amount)
        var player_id = state.player.entity_id
        var inspiration = _status_stacks(state, player_id, GameConstants.STATUS_INSPIRATION)
        if inspiration > 0:
                amount += inspiration * catalog.status_int(GameConstants.STATUS_INSPIRATION, "completion_per_stack", 2)
        var flow = _status_stacks(state, player_id, GameConstants.STATUS_FLOW)
        if flow > 0:
                amount += flow * catalog.status_int(GameConstants.STATUS_FLOW, "completion_per_stack", 1)
        var drowsiness = _status_stacks(state, player_id, GameConstants.STATUS_DROWSINESS)
        if drowsiness > 0:
                amount -= drowsiness * catalog.status_int(GameConstants.STATUS_DROWSINESS, "completion_penalty_per_stack", 1)
        if state.scene != null:
                var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
                var modifiers: Variant = scene_def.get("modifiers")
                if typeof(modifiers) == TYPE_DICTIONARY:
                        amount += int((modifiers as Dictionary).get("work_first_segment_bonus", 0))
        amount += _relic_first_segment_bonus(ctx, amount)
        return maxi(0, amount)

## 每回合首张工作牌第一段加值（A01 等饰品）。加值只作用于第一段，读 limit 控制周期。
## bonus_if 条件（K14 状态层数 / K05 本回合打过指定定义 / K59 当前 DDL 阈值）。
## 同一条 bonus_if 同时写多个条件时全部满足才加值；一个条件都没写视为不成立（内容层已拦）。
func _bonus_condition_met(state, bonus: Dictionary) -> bool:
        var matched = false
        if bonus.has("status"):
                matched = true
                var status_id = String(bonus.get("status", ""))
                var min_stacks = maxi(1, int(bonus.get("min_stacks", 1)))
                if _status_stacks(state, state.player.entity_id, status_id) < min_stacks:
                        return false
        if bonus.has("played_definition"):
                matched = true
                var played_id = String(bonus.get("played_definition", ""))
                var played = _counter_count(
                        state,
                        GameConstants.COUNTER_SCOPE_ROUND,
                        GameConstants.COUNTER_OWNER_PLAYED_PREFIX + played_id,
                        GameConstants.COUNTER_TRIGGER_PLAYED
                )
                if played < 1:
                        return false
        if bonus.has("ddl_lte"):
                matched = true
                if state.ddl > int(bonus.get("ddl_lte")):
                        return false
        return matched


func _relic_first_segment_bonus(ctx: Dictionary, _amount: int) -> int:
        var state: BattleState = ctx["state"]
        var bonus = 0
        for relic_id in state.relics:
                var relic_def: Dictionary = catalog.definition(GameConstants.KIND_RELIC, String(relic_id))
                var relic_effects: Variant = relic_def.get("effects")
                if typeof(relic_effects) != TYPE_ARRAY:
                        continue
                for raw_effect in (relic_effects as Array):
                        if typeof(raw_effect) != TYPE_DICTIONARY:
                                continue
                        var relic_effect: Dictionary = raw_effect
                        if String(relic_effect.get("op", "")) != GameConstants.OP_WORK_FLAT_BONUS:
                                continue
                        if String(relic_effect.get("segment", "first")) != "first":
                                continue
                        var limit: Variant = relic_def.get("limit")
                        var per = GameConstants.COUNTER_SCOPE_BATTLE
                        var times = 1
                        if typeof(limit) == TYPE_DICTIONARY:
                                per = String((limit as Dictionary).get("per", GameConstants.COUNTER_SCOPE_BATTLE))
                                times = maxi(1, int((limit as Dictionary).get("times", 1)))
                        var owner_key = "relic:" + String(relic_id)
                        if _counter_count(state, per, owner_key, "work_first") < times:
                                _bump_counter(ctx, per, owner_key, "work_first")
                                bonus += maxi(0, int(relic_effect.get("amount", 0)))
        return bonus


func _apply_completion(ctx: Dictionary, task_id: String, amount: int, kind: String) -> void:
        var state: BattleState = ctx["state"]
        var task = state.find_task(task_id)
        if task == null:
                return
        var absorbed = mini(task.shield, maxi(0, amount))
        task.shield -= absorbed
        var remaining = maxi(0, amount) - absorbed
        var applied = mini(remaining, task.work_remaining)
        task.work_remaining -= applied
        _emit(ctx, EVENT_COMPLETION_APPLIED, {
                "task_id": task.task_id,
                "kind": kind,
                "amount": maxi(0, amount),
                "absorbed": absorbed,
                "applied": applied,
                "work_remaining": task.work_remaining,
        })
        if task.work_remaining <= 0:
                _advance_task_phase(ctx, task.task_id)


## 阶段归零：有下一阶段则生成新 task_id（清旧屏障与状态），否则完成任务。
func _advance_task_phase(ctx: Dictionary, task_id: String) -> void:
        var state: BattleState = ctx["state"]
        var task = state.find_task(task_id)
        if task == null:
                return
        var definition: Dictionary = catalog.definition(GameConstants.KIND_TASK, task.definition_id)
        var phases: Array = definition.get("phases", [])
        var index = -1
        for i in range(phases.size()):
                if String((phases[i] as Dictionary).get("phase_key", "")) == String(task.phase_key):
                        index = i
                        break
        _remove_statuses_of_holder(ctx, task.task_id)
        var definition_id = task.definition_id
        var old_task_id = task.task_id
        var old_phase = String(task.phase_key)
        state.tasks.erase(task)
        if index >= 0 and index + 1 < phases.size():
                var next_key = String((phases[index + 1] as Dictionary).get("phase_key", ""))
                var eligible = state.round_index if _is_player_side_phase(String(state.phase)) else state.round_index + 1
                var next_task = _create_task(state, definition_id, next_key, eligible)
                state.tasks.append(next_task)
                _emit(ctx, EVENT_TASK_ADVANCED, {
                        "old_task_id": old_task_id,
                        "new_task_id": next_task.task_id,
                        "phase_key": next_key,
                })
        else:
                _emit(ctx, EVENT_TASK_COMPLETED, {
                        "task_id": old_task_id,
                        "definition_id": definition_id,
                        "phase_key": old_phase,
                })

func _effect_heal(ctx: Dictionary, base_amount: int) -> void:
        var state: BattleState = ctx["state"]
        var amount = base_amount
        if state.scene != null:
                var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
                var modifiers: Variant = scene_def.get("modifiers")
                if typeof(modifiers) == TYPE_DICTIONARY:
                        var percent = int((modifiers as Dictionary).get("heal_percent", 100))
                        if percent != 100:
                                amount = catalog.scaled_by_percent(amount, percent)
        if amount <= 0:
                return
        state.player.vitality = mini(state.player.max_vitality, state.player.vitality + amount)
        _emit(ctx, EVENT_VITALITY_CHANGED, {"holder_id": state.player.entity_id, "vitality": state.player.vitality, "healed": amount})


func _effect_gain_focus(ctx: Dictionary, amount: int) -> void:
        var state: BattleState = ctx["state"]
        if amount <= 0:
                return
        state.player.focus = mini(catalog.battle_int("focus_cap", 10), state.player.focus + amount)
        _emit(ctx, EVENT_FOCUS_CHANGED, {"focus": state.player.focus, "gained": amount})


func _effect_lose_vitality(ctx: Dictionary, amount: int) -> void:
        var state: BattleState = ctx["state"]
        if amount <= 0:
                return
        state.player.vitality = maxi(0, state.player.vitality - amount)
        _emit(ctx, EVENT_VITALITY_CHANGED, {"holder_id": state.player.entity_id, "vitality": state.player.vitality, "lost": amount})


func _effect_restore_work(ctx: Dictionary, effect: Dictionary, target_ids: Array) -> void:
        var state: BattleState = ctx["state"]
        var task = _primary_task(state, target_ids)
        if task == null:
                return
        task.work_remaining = mini(task.work_max, task.work_remaining + maxi(0, int(effect.get("amount", 0))))
        _emit(ctx, EVENT_COMPLETION_APPLIED, {"task_id": task.task_id, "kind": "restore", "work_remaining": task.work_remaining})


func _effect_remove_status(ctx: Dictionary, effect: Dictionary, target_ids: Array) -> void:
        var state: BattleState = ctx["state"]
        var holder_id = _status_holder_id(state, effect, target_ids)
        if holder_id.is_empty():
                return
        var status_id = String(effect.get("status", ""))
        var amount = maxi(1, int(effect.get("amount", 1)))
        var removed = _remove_status(ctx, holder_id, status_id, amount)
        var fallback: Variant = effect.get("fallback")
        if removed == 0 and typeof(fallback) == TYPE_ARRAY:
                _run_effects_now(ctx, fallback, target_ids)


func _effect_summon(ctx: Dictionary, effect: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var unit_definition_id = String(effect.get("unit", ""))
        var unit_def: Dictionary = catalog.definition(GameConstants.KIND_UNIT, unit_definition_id)
        if unit_def.is_empty():
                return
        var slots: int = catalog.battle_int("unit_slots", 3)
        var replace_id: Variant = null
        if state.resolution != null:
                replace_id = state.resolution.action.get("replace_unit_id")
        if state.units.size() >= slots:
                var outgoing = state.find_unit(String(replace_id)) if replace_id != null else null
                if outgoing == null:
                        return
                _depart_unit(ctx, outgoing, "switch")
        var max_vitality = maxi(1, int(unit_def.get("vitality", 1)))
        var cooperation = maxi(0, int(unit_def.get("cooperation", 0)))
        var unit_bonus = {}
        if state.resolution != null:
                var face: Dictionary = state.resolution.action.get("face", {})
                if typeof(face.get("unit_bonus")) == TYPE_DICTIONARY:
                        unit_bonus = face.get("unit_bonus")
        max_vitality += maxi(0, int(unit_bonus.get("max_vitality", 0)))
        cooperation += maxi(0, int(unit_bonus.get("cooperation", 0)))
        var unit = BattleState.create_unit(state.allocate_entity_id("u"), unit_definition_id, max_vitality, max_vitality)
        unit.cooperation = cooperation
        unit.entered_order = state.next_order()
        unit.last_acted_round = 0
        state.units.append(unit)
        if bool(unit_def.get("guard", false)) or bool(unit_def.get("entry_guard", false)):
                _gain_status(ctx, unit.unit_id, GameConstants.STATUS_GUARD, 1)
        _emit(ctx, EVENT_UNIT_SUMMONED, {
                "unit_id": unit.unit_id,
                "definition_id": unit_definition_id,
                "vitality": unit.vitality,
                "cooperation": unit.cooperation,
        })
        var entry_effects: Variant = unit_def.get("entry_effects")
        if typeof(entry_effects) == TYPE_ARRAY:
                _run_effects_now(ctx, entry_effects, [unit.unit_id])

func _effect_establish_scene(ctx: Dictionary, effect: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var scene_definition_id = String(effect.get("scene", ""))
        var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, scene_definition_id)
        if scene_def.is_empty():
                return
        # pre_effects 已由 _play_card 在整张牌结算前统一执行（建立前时序不变）。
        if state.scene != null:
                _emit(ctx, EVENT_SCENE_REPLACED, {
                        "old_scene_id": state.scene.scene_id,
                        "old_definition_id": state.scene.definition_id,
                })
                state.scene = null
        var scene = BattleState.create_scene(state.allocate_entity_id("s"), scene_definition_id, state.round_index)
        state.scene = scene
        _preroll_scene_random(ctx)
        _emit(ctx, EVENT_SCENE_ESTABLISHED, {
                "scene_id": scene.scene_id,
                "definition_id": scene_definition_id,
        })


func _preroll_scene_random(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        if state.scene == null:
                return
        var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, state.scene.definition_id)
        var random_spec: Variant = scene_def.get("prepare_random")
        if typeof(random_spec) != TYPE_DICTIONARY:
                return
        var options: Array = (random_spec as Dictionary).get("options", [])
        if options.is_empty():
                state.scene.pending_random_result = null
                return
        var rng: RandomSource = ctx["rng"]
        var drawn = rng.draw_int(GameConstants.RNG_BATTLE, 0, options.size() - 1)
        if Result.is_ok(drawn):
                state.scene.pending_random_result = int(drawn["data"])


func _run_scene_prepare(ctx: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var scene = state.scene
        if scene == null:
                return
        var scene_def: Dictionary = catalog.definition(GameConstants.KIND_SCENE, scene.definition_id)
        if scene_def.is_empty():
                return
        var used = _bump_counter(ctx, GameConstants.COUNTER_SCOPE_BATTLE, scene.definition_id, "prepare")
        var battle_limit = int(scene_def.get("battle_limit", 0))
        if battle_limit > 0 and used > battle_limit:
                return
        var random_spec: Variant = scene_def.get("prepare_random")
        if typeof(random_spec) == TYPE_DICTIONARY:
                var options: Array = (random_spec as Dictionary).get("options", [])
                if not options.is_empty():
                        var index = int(scene.pending_random_result) if scene.pending_random_result != null else 0
                        index = clampi(index, 0, options.size() - 1)
                        _run_effects_now(ctx, (options[index] as Dictionary).get("effects", []), [])
                        if ctx.get("outcome") != null:
                                return
                        _preroll_scene_random(ctx)
        else:
                _run_effects_now(ctx, scene_def.get("prepare_effects", []), [])
                if ctx.get("outcome") != null:
                        return
        var after_every = int(scene_def.get("anxiety_after_every", 0))
        if after_every > 0 and used % after_every == 0:
                _gain_status(ctx, state.player.entity_id, GameConstants.STATUS_ANXIETY, 1)


func _run_unit_support(ctx: Dictionary, unit) -> void:
        var unit_def: Dictionary = catalog.definition(GameConstants.KIND_UNIT, unit.definition_id)
        var support: Variant = unit_def.get("support")
        if typeof(support) != TYPE_DICTIONARY:
                return
        var spec: Dictionary = support
        var kind = String(spec.get("kind", ""))
        var state: BattleState = ctx["state"]
        var player_id = state.player.entity_id
        if kind == "relax":
                var amount = maxi(0, int(spec.get("amount", 0)))
                state.player.relax += amount
                _emit(ctx, EVENT_VITALITY_CHANGED, {"relax_gained": amount, "unit_id": unit.unit_id})
        elif kind == "self_relax":
                unit.relax += maxi(0, int(spec.get("amount", 0)))
        elif kind == "cleanse_or_relax":
                var status_id = String(spec.get("status", ""))
                var removed = _remove_status(ctx, player_id, status_id, maxi(1, int(spec.get("amount", 1))))
                if removed == 0:
                        var fallback = maxi(0, int(spec.get("fallback_relax", 0)))
                        state.player.relax += fallback
                        _emit(ctx, EVENT_VITALITY_CHANGED, {"relax_gained": fallback, "unit_id": unit.unit_id})
        elif kind == "gain_status_on_actions":
                var actions: Array = spec.get("actions", [1, 3])
                var action_index = int(unit.actions_taken) + 1
                if actions.has(action_index):
                        _gain_status(ctx, player_id, String(spec.get("status", "")), maxi(1, int(spec.get("stacks", 1))))
        elif kind == "heal":
                _effect_heal(ctx, maxi(0, int(spec.get("amount", 0))))


func _depart_unit(ctx: Dictionary, unit, reason: String) -> void:
        var state: BattleState = ctx["state"]
        state.units.erase(unit)
        _remove_statuses_of_holder(ctx, unit.unit_id)
        _emit(ctx, EVENT_UNIT_DEPARTED, {
                "unit_id": unit.unit_id,
                "definition_id": unit.definition_id,
                "reason": reason,
        })


# ── 触发计数器与状态 ──────────────────────────────────────

func _bump_counter(ctx: Dictionary, scope: String, owner_key: String, trigger_key: String) -> int:
        return _add_counter(ctx, scope, owner_key, trigger_key, 1)


## 触发计数累加（delta 可 > 1）。回合/实例类计数跨回合自动归零，战斗类保留。
func _add_counter(ctx: Dictionary, scope: String, owner_key: String, trigger_key: String, delta: int) -> int:
        var state: BattleState = ctx["state"]
        var key = BattleState.counter_key(scope, owner_key, trigger_key)
        var counter = state.counters.get(key)
        if counter == null:
                counter = BattleState.create_counter(scope, owner_key, trigger_key)
                state.counters[key] = counter
        if scope != GameConstants.COUNTER_SCOPE_BATTLE and counter.round != state.round_index:
                counter.count = 0
                counter.round = state.round_index
        counter.count = int(counter.count) + maxi(0, delta)
        return int(counter.count)


func _counter_count(state, scope: String, owner_key: String, trigger_key: String) -> int:
        if state == null:
                return 0
        var key = BattleState.counter_key(scope, owner_key, trigger_key)
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        if scope != GameConstants.COUNTER_SCOPE_BATTLE and counter.round != state.round_index:
                return 0
        return int(counter.count)


func _reset_round_counters(state) -> void:
        for key in state.counters:
                var counter = state.counters[key]
                if String(counter.scope) != GameConstants.COUNTER_SCOPE_BATTLE:
                        counter.count = 0
                        counter.round = state.round_index


func _status_stacks(state, holder_id: String, status_id: String) -> int:
        if status_id.is_empty() or holder_id.is_empty():
                return 0
        var status = state.find_status(holder_id, status_id)
        if status == null:
                return 0
        return int(status.stacks)


func _gain_status(ctx: Dictionary, holder_id: String, status_id: String, stacks: int) -> void:
        if status_id.is_empty() or holder_id.is_empty() or stacks <= 0:
                return
        var state: BattleState = ctx["state"]
        var cap: int = catalog.status_int(status_id, "cap", 0)
        var existing = state.find_status(holder_id, status_id)
        if existing != null:
                var before = int(existing.stacks)
                var after = before + stacks
                if cap > 0:
                        after = mini(after, cap)
                existing.stacks = after
                if after > before:
                        _emit(ctx, EVENT_STATUS_GAINED, {"holder_id": holder_id, "status_id": status_id, "stacks": after, "gained": after - before})
                return
        var initial = stacks
        if cap > 0:
                initial = mini(initial, cap)
        var status = BattleState.create_status(state.allocate_entity_id("st"), status_id, holder_id, initial)
        status.expiry = _default_status_expiry(status_id)
        status.source = {"source": "battle"}
        state.statuses[status.status_id] = status
        _emit(ctx, EVENT_STATUS_GAINED, {"holder_id": holder_id, "status_id": status_id, "stacks": initial, "gained": initial})


func _default_status_expiry(status_id: String) -> String:
        if status_id == GameConstants.STATUS_ANXIETY:
                return "prepare"
        if status_id == GameConstants.STATUS_PROCRASTINATION:
                return "draw"
        if status_id == GameConstants.STATUS_DROWSINESS:
                return "player_action_end"
        if status_id == GameConstants.STATUS_INSPIRATION:
                return "round_end"
        if status_id == GameConstants.STATUS_PLAGIARISM_SHIELD:
                return "enemy_prepare"
        if status_id == GameConstants.STATUS_GUARD:
                return "unit_depart"
        return ""

func _remove_status(ctx: Dictionary, holder_id: String, status_id: String, amount: int) -> int:
        var state: BattleState = ctx["state"]
        var status = state.find_status(holder_id, status_id)
        if status == null or amount <= 0:
                return 0
        var removed = mini(int(status.stacks), amount)
        status.stacks = int(status.stacks) - removed
        if int(status.stacks) <= 0:
                state.statuses.erase(status.status_id)
        _emit(ctx, EVENT_STATUS_REMOVED, {"holder_id": holder_id, "status_id": status_id, "removed": removed})
        return removed


func _remove_status_all(ctx: Dictionary, holder_id: String, status_id: String) -> void:
        _remove_status(ctx, holder_id, status_id, 999999)


func _remove_statuses_by_expiry(ctx: Dictionary, expiry: String) -> void:
        var state: BattleState = ctx["state"]
        for status_id in state.statuses.keys():
                var status = state.statuses[status_id]
                if String(status.expiry) == expiry:
                        state.statuses.erase(status_id)
                        _emit(ctx, EVENT_STATUS_REMOVED, {
                                "holder_id": status.holder_id,
                                "status_id": status.definition_id,
                                "removed": int(status.stacks),
                        })


func _remove_statuses_of_holder(ctx: Dictionary, holder_id: String) -> void:
        var state: BattleState = ctx["state"]
        for status_id in state.statuses.keys():
                var status = state.statuses[status_id]
                if String(status.holder_id) == holder_id:
                        state.statuses.erase(status_id)


# ── 牌区操作 ──────────────────────────────────────────────

func _draw_cards(ctx: Dictionary, count: int) -> void:
        var state: BattleState = ctx["state"]
        var hand_limit: int = catalog.battle_int("hand_limit", 10)
        var rng: RandomSource = ctx["rng"]
        for _index in range(maxi(0, count)):
                if state.zones.hand.size() >= hand_limit:
                        break
                if state.zones.draw.is_empty():
                        if state.zones.discard.is_empty():
                                break
                        var reshuffled = rng.shuffle(GameConstants.RNG_BATTLE, state.zones.discard)
                        if not Result.is_ok(reshuffled):
                                break
                        state.zones.draw = reshuffled["data"]
                        state.zones.discard = []
                var card_id = String(state.zones.draw[0])
                state.zones.draw.remove_at(0)
                state.zones.hand.append(card_id)
                _emit(ctx, EVENT_CARD_DRAWN, {"card_id": card_id})


func _discard_card(ctx: Dictionary, card_id: String) -> void:
        var state: BattleState = ctx["state"]
        if state.zone_of(card_id) != GameConstants.ZONE_HAND:
                return
        if state.move_card(card_id, GameConstants.ZONE_DISCARD):
                _emit(ctx, EVENT_CARD_DISCARDED, {"card_id": card_id})


## 敌方意图加入特殊牌（如 X01 至弃牌堆）；手牌满时非抽牌入牌改入弃牌堆。
func _add_temporary_card(ctx: Dictionary, spec: Dictionary) -> void:
        var state: BattleState = ctx["state"]
        var definition_id = String(spec.get("card", ""))
        if definition_id.is_empty() or catalog.definition(GameConstants.KIND_CARD, definition_id).is_empty():
                return
        var count = maxi(1, int(spec.get("count", 1)))
        var zone = String(spec.get("zone", GameConstants.ZONE_DISCARD))
        if zone == GameConstants.ZONE_HAND and state.zones.hand.size() >= catalog.battle_int("hand_limit", 10):
                zone = GameConstants.ZONE_DISCARD
        for _index in range(count):
                var card_id = state.allocate_entity_id("c")
                if state.add_card(card_id, definition_id, zone) != null:
                        _emit(ctx, EVENT_CARD_DRAWN, {"card_id": card_id, "temporary": true})


# ── 压力 ──────────────────────────────────────────────────

func _scaled_pressure(ctx: Dictionary, amount: int) -> int:
        var state: BattleState = ctx["state"]
        var percent: int = catalog.difficulty_int(state.difficulty, "pressure_percent", 100)
        if percent == 100:
                return maxi(0, amount)
        return int(ceil(float(maxi(0, amount)) * float(percent) / 100.0))


func _apply_pressure_single(ctx: Dictionary, base_amount: int, source_task_id: String = "") -> void:
        var state: BattleState = ctx["state"]
        var amount = base_amount
        if not source_task_id.is_empty():
                var extra = _status_stacks(state, source_task_id, GameConstants.STATUS_EXTRA_REQUIREMENTS)
                if extra > 0:
                        amount += extra * catalog.status_int(GameConstants.STATUS_EXTRA_REQUIREMENTS, "pressure_per_stack", 2)
        var scaled = _scaled_pressure(ctx, amount)
        var guard = _guard_unit(state)
        if guard != null:
                _apply_pressure_to_unit(ctx, guard, scaled)
        else:
                _apply_pressure_to_player(ctx, scaled)


func _apply_pressure_all(ctx: Dictionary, base_amount: int) -> void:
        var state: BattleState = ctx["state"]
        var scaled = _scaled_pressure(ctx, base_amount)
        _apply_pressure_to_player(ctx, scaled)
        for unit in state.units.duplicate():
                if ctx.get("outcome") != null:
                        return
                if state.find_unit(unit.unit_id) == null:
                        continue
                _apply_pressure_to_unit(ctx, unit, scaled)


func _apply_pressure_to_player(ctx: Dictionary, amount: int) -> void:
        var state: BattleState = ctx["state"]
        if amount <= 0:
                return
        var absorbed = mini(state.player.relax, amount)
        state.player.relax -= absorbed
        var hurt = amount - absorbed
        state.player.vitality = maxi(0, state.player.vitality - hurt)
        _emit(ctx, EVENT_PRESSURE_APPLIED, {
                "target_id": state.player.entity_id,
                "amount": amount,
                "absorbed": absorbed,
                "damage": hurt,
                "vitality": state.player.vitality,
        })


func _apply_pressure_to_unit(ctx: Dictionary, unit, amount: int) -> void:
        var state: BattleState = ctx["state"]
        if amount <= 0 or state.find_unit(unit.unit_id) == null:
                return
        var absorbed = mini(unit.relax, amount)
        unit.relax -= absorbed
        var hurt = amount - absorbed
        unit.vitality = maxi(0, unit.vitality - hurt)
        _emit(ctx, EVENT_PRESSURE_APPLIED, {
                "target_id": unit.unit_id,
                "amount": amount,
                "absorbed": absorbed,
                "damage": hurt,
                "vitality": unit.vitality,
        })
        if unit.vitality <= 0:
                _depart_unit(ctx, unit, "exhausted")


## 护卫改向：默认单体压力由最早入场的护卫单位承接；点名与全体压力不走这里。
func _guard_unit(state):
        var earliest = null
        for unit in state.units:
                if unit.vitality <= 0:
                        continue
                var is_guard = _status_stacks(state, unit.unit_id, GameConstants.STATUS_GUARD) > 0
                if not is_guard:
                        var unit_def: Dictionary = catalog.definition(GameConstants.KIND_UNIT, unit.definition_id)
                        is_guard = bool(unit_def.get("guard", false))
                if not is_guard:
                        continue
                if earliest == null or unit.entered_order < earliest.entered_order:
                        earliest = unit
        return earliest

# ── 任务与意图 ────────────────────────────────────────────

## 由定义创建任务实例；多任务遭遇按 encounters.dual_task_work_percent 缩放工作量向上取整。
func _create_task(state, definition_id: String, phase_key: String, eligible_round: int):
        var definition: Dictionary = catalog.definition(GameConstants.KIND_TASK, definition_id)
        var phases: Array = definition.get("phases", [])
        var phase = {}
        if phase_key.is_empty() and not phases.is_empty():
                phase = phases[0]
                phase_key = String(phase.get("phase_key", ""))
        else:
                for raw in phases:
                        if String((raw as Dictionary).get("phase_key", "")) == phase_key:
                                phase = raw
                                break
        var work = maxi(1, int(phase.get("work", 1)))
        var encounter: Dictionary = catalog.definition(GameConstants.KIND_ENCOUNTER, state.encounter_id)
        var task_count: int = (encounter.get("tasks", []) as Array).size()
        if task_count > 1:
                var percent = int(catalog.section("encounters").get("dual_task_work_percent", 100))
                work = int(ceil(float(work) * float(percent) / 100.0))
        var task = BattleState.create_task(state.allocate_entity_id("t"), definition_id, phase_key, work)
        task.entered_order = state.next_order()
        task.eligible_round = eligible_round
        task.intent_cursor = 0
        task.intent_snapshot = _intent_snapshot(definition, phase_key, 0)
        return task


func _intent_snapshot(definition: Dictionary, phase_key: String, cursor: int) -> Dictionary:
        var phases: Array = definition.get("phases", [])
        for raw in phases:
                var phase: Dictionary = raw
                if String(phase.get("phase_key", "")) != phase_key:
                        continue
                var intents: Array = phase.get("intents", [])
                if intents.is_empty():
                        return {}
                var index = int(cursor) % intents.size()
                return (intents[index] as Dictionary).duplicate(true)
        return {}


func _current_intent(state, task) -> Dictionary:
        if task.intent_snapshot != null and not task.intent_snapshot.is_empty():
                return task.intent_snapshot
        var definition: Dictionary = catalog.definition(GameConstants.KIND_TASK, task.definition_id)
        return _intent_snapshot(definition, task.phase_key, int(task.intent_cursor))


## 入场延迟：敌方行动中生成的新任务本轮不行动，eligible_round 置为下一轮。
func _task_actionable(state, task) -> bool:
        return int(task.eligible_round) <= state.round_index


func _first_task(state):
        var earliest = null
        for task in state.tasks:
                if task.work_remaining <= 0:
                        continue
                if earliest == null or task.entered_order < earliest.entered_order:
                        earliest = task
        return earliest


## 效果的目标任务。两种情形必须分开（战斗契约 §17 / [DDL-002]）：
##   · 给了锁定目标（resolution.locked_target_ids），但该目标已不存在或已归零
##     → 返回 null，调用方跳过这一段完成量（不回退到新阶段，否则等于白打一个阶段）；
##   · 本来就没给目标（场景/单位/饰品效果传空数组）→ 回退到首个合法任务（既有行为）。
func _primary_task(state, target_ids: Array):
        if target_ids != null and not target_ids.is_empty():
                var locked = state.find_task(String(target_ids[0]))
                if locked == null or locked.work_remaining <= 0:
                        return null
                return locked
        return _first_task(state)


## 协作目标：玩家指定且仍合法者优先，失效时回退行动顺序最前任务。
func _coop_target(state, unit):
        if unit.target_id != null:
                var chosen = state.find_task(String(unit.target_id))
                if chosen != null and chosen.work_remaining > 0:
                        return chosen
        return _first_task(state)


func _first_unit(state):
        for unit in state.units:
                if unit.vitality > 0:
                        return unit
        return null


func _status_holder_id(state, effect: Dictionary, target_ids: Array) -> String:
        var target = String(effect.get("target", "player"))
        if target == "task":
                var task = _primary_task(state, target_ids)
                return "" if task == null else task.task_id
        if target == "unit":
                if target_ids != null and not target_ids.is_empty():
                        var unit = state.find_unit(String(target_ids[0]))
                        if unit != null:
                                return unit.unit_id
                var first = _first_unit(state)
                return "" if first == null else first.unit_id
        return state.player.entity_id


func _intent_holder(state, task, spec: Dictionary) -> String:
        var target = String(spec.get("target", "player"))
        if target == "task":
                return task.task_id
        if target == "unit":
                var first = _first_unit(state)
                return "" if first == null else first.unit_id
        return state.player.entity_id


func _is_player_side_phase(phase: String) -> bool:
        return PLAYER_SIDE_PHASES.has(phase)


# ── BattleView ────────────────────────────────────────────

func make_view(state) -> Dictionary:
        if state == null:
                return {}
        var hand = []
        for card_id in state.card_ids_in(GameConstants.ZONE_HAND):
                hand.append(_card_view(state, String(card_id)))
        var units = []
        for unit in state.units:
                units.append({
                        "unit_id": unit.unit_id,
                        "definition_id": unit.definition_id,
                        "vitality": unit.vitality,
                        "max_vitality": unit.max_vitality,
                        "relax": unit.relax,
                        "cooperation": unit.cooperation,
                        "entered_order": unit.entered_order,
                        "actions_taken": unit.actions_taken,
                        "last_acted_round": unit.last_acted_round,
                        "target_id": unit.target_id,
                        "guard": _status_stacks(state, unit.unit_id, GameConstants.STATUS_GUARD) > 0,
                })
        var tasks = []
        for task in state.tasks:
                tasks.append({
                        "task_id": task.task_id,
                        "definition_id": task.definition_id,
                        "phase_key": task.phase_key,
                        "work_remaining": task.work_remaining,
                        "work_max": task.work_max,
                        "shield": task.shield,
                        "entered_order": task.entered_order,
                        "eligible_round": task.eligible_round,
                        "intent": _current_intent(state, task),
                })
        var statuses = []
        for status_id in state.statuses:
                var status = state.statuses[status_id]
                statuses.append({
                        "status_id": status.status_id,
                        "definition_id": status.definition_id,
                        "holder_id": status.holder_id,
                        "stacks": status.stacks,
                        "expiry": status.expiry,
                })
        var scene_view: Variant = null
        if state.scene != null:
                scene_view = {
                        "scene_id": state.scene.scene_id,
                        "definition_id": state.scene.definition_id,
                        "established_round": state.scene.established_round,
                        "pending_random_result": state.scene.pending_random_result,
                }
        var pending_choice: Variant = null
        if state.resolution != null and state.resolution.choice != null:
                pending_choice = state.resolution.choice
        return {
                "battle_id": state.battle_id,
                "node_id": state.node_id,
                "encounter_id": state.encounter_id,
                "phase": state.phase,
                "round_index": state.round_index,
                "ddl": state.ddl,
                "character_id": state.character_id,
                "difficulty": state.difficulty,
                "relics": state.relics.duplicate(),
                "exam_limits": state.exam_limits.duplicate(),
                "player": {
                        "entity_id": state.player.entity_id,
                        "vitality": state.player.vitality,
                        "max_vitality": state.player.max_vitality,
                        "relax": state.player.relax,
                        "focus": state.player.focus,
                },
                "hand": hand,
                "zones": state.zones.counts(),
                "zones_public": _public_zone_contents(state),
                "units": units,
                "tasks": tasks,
                "statuses": statuses,
                "scene": scene_view,
                "pending_choice": pending_choice,
                "outcome": state.outcome,
                "stable": state.resolution == null and state.outcome == null,
                "phase_order": PHASE_ORDER.duplicate(),
        }


## 公开牌区内容：弃牌堆与耗尽堆是公开信息，抽牌堆顺序必须保密（《接口文档》§2、《游戏规则书》§7.3）。
func _public_zone_contents(state) -> Dictionary:
        var public_discard := []
        for card_id in state.card_ids_in(GameConstants.ZONE_DISCARD):
                public_discard.append(_card_view(state, String(card_id), false))
        var public_exhaust := []
        for card_id in state.card_ids_in(GameConstants.ZONE_EXHAUST):
                public_exhaust.append(_card_view(state, String(card_id), false))
        return {"discard": public_discard, "exhaust": public_exhaust}

func _card_view(state, card_id: String, from_hand: bool = true) -> Dictionary:
        var card = state.get_card(card_id)
        if card == null:
                return {}
        var face = {}
        var quote = {}
        var face_result = BattleCardRules.resolve_face(catalog, state, card_id)
        if Result.is_ok(face_result):
                face = face_result["data"]
                quote = BattleCardRules.cost_quote(catalog, state, face)
        var playable = false
        if from_hand and String(state.phase) == GameConstants.PHASE_PLAYER_ACTION and state.resolution == null and not face.is_empty():
                playable = state.player.focus >= int(quote.get("cost", 0)) and not bool(face.get("unplayable", false))
        return {
                "card_id": card.card_id,
                "definition_id": card.definition_id,
                "origin_card_id": card.origin_card_id,
                "upgrade_level": card.upgrade_level,
                "effective_cost": int(quote.get("cost", 0)),
                "effective_vitality_cost": maxi(0, int(quote.get("vitality_cost", 0))),
                "playable": playable,
                "face": face,
        }