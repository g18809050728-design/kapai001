class_name BattleSession
extends RefCounted
##
## 战斗界面会话：把 BattleEngine 的「状态 + 随机快照」成对持有一份，供界面驱动。
##
## 职责边界（硬约束）：
##   · 只调用 engine.begin / preview / apply / make_view；
##   · 从不读写 BattleState 的字段（精力、牌堆、金币、触发次数一律不碰），
##     连日志翻译要用的名字与任务进度都从 make_view 的视图里取；
##   · 状态与 rng_state 永远共同提交：apply 失败整份丢弃，界面视图不变。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const BattleLabels := preload("res://src/ui/battle/battle_labels.gd")

const LOG_SYSTEM := "system"
const LOG_PLAY := "play"
const LOG_GAIN := "gain"
const LOG_LOSS := "loss"
const LOG_CHOICE := "choice"
const LOG_LIMIT := 400

## 引擎（BattleEngine 实例，catalog 由调用方载入）。
var engine = null
## BattleState；begin 成功后才非空。只透传给 engine，界面不读它的字段。
var state = null
## RandomSource.export_state() 的快照；与 state 同生共死。
var rng_state: Variant = null
var last_events: Array = []
var last_error: Dictionary = {}

var _log: Array = []
var _card_defs: Dictionary = {}
var _task_defs: Dictionary = {}
var _task_max: Dictionary = {}
var _unit_defs: Dictionary = {}
var _player_id := ""
var _round_index := 0
var _started := false
var _outcome: Variant = null


## Result：失败时 last_error 保留原因，界面视图不改变。
func start(engine_ref, battle_input: Dictionary) -> Dictionary:
    if engine_ref == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.no_engine", {})
    if engine_ref.catalog == null or not engine_ref.catalog.is_loaded():
        return Result.fail(GameConstants.ERROR_CONTENT_INVALID, "error.battle.catalog_missing", {})
    var step: Dictionary = engine_ref.begin(battle_input)
    if not Result.is_ok(step):
        last_error = step
        return step
    engine = engine_ref
    _commit(step["data"])
    return step


## Result：action 为空字典（例如待选期间被界面锁住）直接失败，不碰状态。
func submit(action: Dictionary) -> Dictionary:
    if not _started or engine == null or state == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.not_started", {})
    if action.is_empty():
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.empty_action", {})
    var step: Dictionary = engine.apply(state, action, rng_state)
    if not Result.is_ok(step):
        last_error = step
        return step
    _commit(step["data"])
    return step


func preview(draft: Dictionary) -> Dictionary:
    if engine == null or state == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.not_started", {})
    return engine.preview(state, draft)


func view() -> Dictionary:
    if engine == null or state == null:
        return {}
    return engine.make_view(state)


func started() -> bool:
    return _started


func finished() -> bool:
    return _outcome != null


func outcome() -> Variant:
    return _outcome


## 当前待选（无待选时为 null）。真相是引擎给出的同一份快照。
func pending_choice() -> Variant:
    var current: Dictionary = view()
    if current.is_empty():
        return null
    return current.get("pending_choice")


func log_entries() -> Array:
    return _log.duplicate()


func clear_log() -> void:
    _log.clear()


func catalog():
    if engine == null:
        return null
    return engine.catalog


## 卡面实例到卡牌定义 ID（界面见过的牌都记下来，供日志翻名字用）。
func card_definition_id(card_id: String) -> String:
    if _card_defs.has(card_id):
        return String(_card_defs[card_id])
    return card_id


func card_name(card_id: String) -> String:
    return BattleLabels.definition_name(catalog(), GameConstants.KIND_CARD, card_definition_id(card_id))


func task_label(task_id: String) -> String:
    return BattleLabels.definition_name(catalog(), GameConstants.KIND_TASK, String(_task_defs.get(task_id, task_id)))


func unit_label(definition_id: String) -> String:
    return BattleLabels.definition_name(catalog(), GameConstants.KIND_UNIT, definition_id)


func scene_label(definition_id: String) -> String:
    return BattleLabels.definition_name(catalog(), GameConstants.KIND_SCENE, definition_id)


## 给动画播报用：把一条事件翻成展示文案（只读，不改状态）。
func describe_event(event: Dictionary) -> Dictionary:
    return _describe_event(event)


# 内部：状态提交、视图索引与日志

func _commit(step: Dictionary) -> void:
    state = step.get("state")
    rng_state = step.get("rng_state")
    _started = state != null
    _outcome = step.get("outcome")
    last_events = step.get("events", [])
    _absorb_view()
    _append_events(last_events)
    _append_closing_entry()


## 只从 make_view 的视图取展示需要的索引；不碰 BattleState 的字段。
func _absorb_view() -> void:
    if engine == null or state == null:
        return
    var current: Dictionary = engine.make_view(state)
    _round_index = int(current.get("round_index", 0))
    var player: Variant = current.get("player")
    if typeof(player) == TYPE_DICTIONARY:
        _player_id = String((player as Dictionary).get("entity_id", ""))
    for raw in (current.get("hand", []) as Array):
        _remember_card(raw)
    var public_zones: Variant = current.get("zones_public")
    if typeof(public_zones) == TYPE_DICTIONARY:
        for pile in (public_zones as Dictionary):
            for raw in (((public_zones as Dictionary)[pile]) as Array):
                _remember_card(raw)
    for raw in (current.get("tasks", []) as Array):
        var task: Dictionary = raw
        var task_id := String(task.get("task_id", ""))
        _task_defs[task_id] = String(task.get("definition_id", ""))
        _task_max[task_id] = int(task.get("work_max", 0))
    _unit_defs = {}
    for raw in (current.get("units", []) as Array):
        var unit: Dictionary = raw
        _unit_defs[String(unit.get("unit_id", ""))] = String(unit.get("definition_id", ""))


func _remember_card(raw: Variant) -> void:
    if typeof(raw) != TYPE_DICTIONARY:
        return
    var entry: Dictionary = raw
    var card_id := String(entry.get("card_id", ""))
    if card_id.is_empty():
        return
    _card_defs[card_id] = String(entry.get("definition_id", ""))


func _append_events(events: Array) -> void:
    for raw in events:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        if String((raw as Dictionary).get("type", "")) == "card_played":
            var played: Dictionary = raw
            _card_defs[String(played.get("card_id", ""))] = String(played.get("definition_id", ""))
        var entry: Dictionary = _describe_event(raw)
        if entry.is_empty():
            continue
        _log.append(entry)
    if _log.size() > LOG_LIMIT:
        _log = _log.slice(_log.size() - LOG_LIMIT)


## 收尾：BattleStep.outcome 是权威结果，日志必须记下结局。
## 引擎只在自动推进路径上发 battle_finished 事件，出牌结算获胜时可能没有该事件，
## 所以这里以 outcome 兜底，保证日志一定有结尾。
func _append_closing_entry() -> void:
    if _outcome == null:
        return
    if not _log.is_empty():
        var tail := String((_log[_log.size() - 1] as Dictionary).get("text", ""))
        if tail.contains("战斗结束"):
            return
    var outcome_dict: Dictionary = _outcome
    _log.append(_entry("战斗结束：%s（%s）" % [
        BattleLabels.outcome_name(String(outcome_dict.get("result", ""))),
        BattleLabels.reason_name(String(outcome_dict.get("reason", ""))),
    ], LOG_SYSTEM, _round_index))


func _describe_event(event: Dictionary) -> Dictionary:
    var type := String(event.get("type", ""))
    var round_index := _round_index
    match type:
        "round_started":
            return _entry("== 第 %d 轮 ==" % int(event.get("round_index", 0)), LOG_SYSTEM, round_index)
        "phase_changed":
            return _phase_event(event, round_index)
        "focus_changed":
            return _focus_event(event, round_index)
        "card_played":
            return _card_played_event(event, round_index)
        "card_resolved":
            return _entry("「%s」结算完成，移动到%s" % [card_name(String(event.get("card_id", ""))), _zone_name(String(event.get("destination", "")))], LOG_SYSTEM, round_index)
        "card_drawn":
            return _entry("抽到「%s」" % card_name(String(event.get("card_id", ""))), LOG_GAIN, round_index)
        "card_discarded":
            return _entry("弃掉「%s」" % card_name(String(event.get("card_id", ""))), LOG_LOSS, round_index)
        "choice_requested":
            return _entry("需要选择：%s" % _choice_kind_name(String(event.get("kind", ""))), LOG_CHOICE, round_index)
        "choice_confirmed":
            return _entry("已确认选择：%s" % _choice_kind_name(String(event.get("kind", ""))), LOG_CHOICE, round_index)
        "status_gained":
            return _entry("%s 获得 %d 层%s，共 %d 层" % [_holder_name(String(event.get("holder_id", ""))), int(event.get("gained", 0)), BattleLabels.status_name(String(event.get("status_id", ""))), int(event.get("stacks", 0))], LOG_GAIN, round_index)
        "status_removed":
            return _entry("%s 移除 %d 层%s" % [_holder_name(String(event.get("holder_id", ""))), int(event.get("removed", 0)), BattleLabels.status_name(String(event.get("status_id", "")))], LOG_SYSTEM, round_index)
        "completion_applied":
            return _entry(_completion_text(event), LOG_GAIN, round_index)
        "pressure_applied":
            return _entry("压力 %d 到 %s：放松吸收 %d，精力 -%d，剩余 %d" % [int(event.get("amount", 0)), _holder_name(String(event.get("target_id", ""))), int(event.get("absorbed", 0)), int(event.get("damage", 0)), int(event.get("vitality", 0))], LOG_LOSS, round_index)
        "vitality_changed":
            return _entry(_vitality_text(event), LOG_GAIN, round_index) if _vitality_is_gain(event) else _entry(_vitality_text(event), LOG_LOSS, round_index)
        "unit_summoned":
            return _entry("召入「%s」，精力 %d 协作 %d" % [unit_label(String(event.get("definition_id", ""))), int(event.get("vitality", 0)), int(event.get("cooperation", 0))], LOG_PLAY, round_index)
        "unit_departed":
            return _entry("「%s」离场：%s" % [unit_label(String(event.get("definition_id", ""))), _depart_reason_name(String(event.get("reason", "")))], LOG_LOSS, round_index)
        "scene_established":
            return _entry("建立场景「%s」" % scene_label(String(event.get("definition_id", ""))), LOG_PLAY, round_index)
        "scene_replaced":
            return _entry("替换场景：旧「%s」退场" % scene_label(String(event.get("old_definition_id", ""))), LOG_SYSTEM, round_index)
        "task_advanced":
            return _entry("「%s」进入下一阶段 %s" % [task_label(String(event.get("new_task_id", ""))), String(event.get("phase_key", ""))], LOG_SYSTEM, round_index)
        "task_completed":
            return _entry("任务「%s」阶段 %s 完成" % [BattleLabels.definition_name(catalog(), GameConstants.KIND_TASK, String(event.get("definition_id", ""))), String(event.get("phase_key", ""))], LOG_GAIN, round_index)
        "intent_revealed":
            return _entry("「%s」公开意图 #%d" % [task_label(String(event.get("task_id", ""))), int(event.get("index", 0))], LOG_SYSTEM, round_index)
        "enemy_skill":
            return _entry("「%s」执行意图 #%d" % [task_label(String(event.get("task_id", ""))), int(event.get("index", 0))], LOG_LOSS, round_index)
        "ddl_ticked":
            return _entry("DDL -1 到 %d，第 %d 轮结束" % [int(event.get("ddl", 0)), int(event.get("round_index", 0))], LOG_LOSS, round_index)
        "battle_finished":
            return _closing_entry("战斗结束：%s，%s" % [BattleLabels.outcome_name(String(event.get("result", ""))), BattleLabels.reason_name(String(event.get("reason", "")))], round_index)
        "coop_target_set":
            return _entry("「%s」的协作目标指向 %s" % [_holder_name(String(event.get("unit_id", ""))), task_label(String(event.get("task_id", "")))], LOG_SYSTEM, round_index)
    return {}


func _closing_entry(text: String, round_index: int) -> Dictionary:
    return _entry(text, LOG_SYSTEM, round_index)


func _phase_event(event: Dictionary, round_index: int) -> Dictionary:
    var phase := String(event.get("phase", ""))
    if phase == "ally_action" or phase == "enemy_prepare" or phase == "enemy_skill" or phase == "enemy_pressure" or phase == "round_end":
        return _entry("进入%s阶段" % BattleLabels.phase_name(phase), LOG_SYSTEM, round_index)
    return {}


func _focus_event(event: Dictionary, round_index: int) -> Dictionary:
    if event.has("spent"):
        return _entry("消耗 %d 专注，剩余 %d" % [int(event.get("spent", 0)), int(event.get("focus", 0))], LOG_SYSTEM, round_index)
    if event.has("gained"):
        return _entry("获得 %d 专注，当前 %d" % [int(event.get("gained", 0)), int(event.get("focus", 0))], LOG_GAIN, round_index)
    return _entry("专注 %d" % int(event.get("focus", 0)), LOG_SYSTEM, round_index)


func _card_played_event(event: Dictionary, round_index: int) -> Dictionary:
    var played := "打出「%s」，费用 %d" % [card_name(String(event.get("card_id", ""))), int(event.get("cost", 0))]
    if not String(event.get("exam_face", "")).is_empty():
        played += "（考试替代面）"
    return _entry(played, LOG_PLAY, round_index)


func _completion_text(event: Dictionary) -> String:
    var kind := String(event.get("kind", ""))
    var task_id := String(event.get("task_id", ""))
    var remaining := int(event.get("work_remaining", 0))
    var work_max := int(_task_max.get(task_id, 0))
    var suffix := "%d" % remaining
    if work_max > 0:
        suffix = "%d/%d" % [remaining, work_max]
    if kind == "restore":
        return "任务「%s」恢复完成量，剩余 %s" % [task_label(task_id), suffix]
    return "任务「%s」完成 %d：屏障吸收 %d，实际 -%d，剩余 %s" % [task_label(task_id), int(event.get("amount", 0)), int(event.get("absorbed", 0)), int(event.get("applied", 0)), suffix]


func _vitality_text(event: Dictionary) -> String:
    if event.has("relax_gained"):
        return "%s 获得 %d 放松" % [_holder_name(_relax_holder(event)), int(event.get("relax_gained", 0))]
    if event.has("healed"):
        return "%s 恢复 %d 精力，当前 %d" % [_holder_name(String(event.get("holder_id", ""))), int(event.get("healed", 0)), int(event.get("vitality", 0))]
    if event.has("lost"):
        return "%s 失去 %d 精力，当前 %d" % [_holder_name(String(event.get("holder_id", ""))), int(event.get("lost", 0)), int(event.get("vitality", 0))]
    return "%s 精力 %d" % [_holder_name(String(event.get("holder_id", ""))), int(event.get("vitality", 0))]


func _vitality_is_gain(event: Dictionary) -> bool:
    return event.has("relax_gained") or event.has("healed")


func _relax_holder(event: Dictionary) -> String:
    if event.has("unit_id"):
        return _holder_name(String(event.get("unit_id", "")))
    return _holder_name(String(event.get("target", "")))


func _entry(text: String, kind: String, round_index: int) -> Dictionary:
    return {"text": text, "kind": kind, "round": round_index}


func _holder_name(holder_id: String) -> String:
    if holder_id.is_empty() or holder_id == _player_id:
        return "主角"
    if _unit_defs.has(holder_id):
        return unit_label(String(_unit_defs[holder_id]))
    return holder_id


func _zone_name(zone: String) -> String:
    match zone:
        GameConstants.ZONE_DRAW:
            return "抽牌堆"
        GameConstants.ZONE_HAND:
            return "手牌"
        GameConstants.ZONE_DISCARD:
            return "弃牌堆"
        GameConstants.ZONE_EXHAUST:
            return "消耗堆"
    return zone


func _choice_kind_name(kind: String) -> String:
    if kind == "discard":
        return "弃牌"
    return kind


func _depart_reason_name(reason: String) -> String:
    if reason == "exhausted":
        return "精力先耗完了"
    if reason == "switch":
        return "换班"
    return reason


## 读档续战：直接接管一份已存在的 BattleState（不重新 begin、不消费随机）。
## rng_ref 应为该战斗的随机流快照，否则后续抽牌会用零种子，导致读档后结果不一致。
func adopt(engine_ref, battle_state, rng_ref = null) -> Dictionary:
    if engine_ref == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.no_engine", {})
    if battle_state == null:
        return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.ui.battle.no_state", {})
    engine = engine_ref
    state = battle_state
    rng_state = rng_ref
    _started = true
    last_events = []
    _absorb_view()
    var current: Dictionary = view()
    _outcome = current.get("outcome")
    _append_closing_entry()
    return Result.ok({"state": state, "outcome": _outcome, "rng_state": rng_state})