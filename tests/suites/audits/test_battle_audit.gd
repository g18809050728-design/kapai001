extends RefCounted
##
## 独立审查套件（verifier）：把《游戏规则书》§3.3、§4～§10 与《统一设计文档》§3.6/§5.1
## 的条文逐条映射成可复现断言。独立入口：res://tests/suites/audits/audit_battle_rules.gd
## （刻意不登记进 tests/run_tests.gd，避免审查探针污染实现者的验收基线）。
##
## 标 [偏差探针] 的断言断言的是「规则本应成立」。它们变红 = 实现层缺该规则落点，
## 是审查结论而不是回归；其余分节核对的是已实现行为是否与条文一致。
##
## 说明：为了让时序/计数归属可复现，本套件会白盒改写自己持有的 BattleState
## （挪牌到手牌、注入 intent_snapshot、注入单位/场景/状态）——只改测试态，不触碰实现。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const BattleCardRules := preload("res://src/battle/card_rules.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const MANIFEST := "battle_mvp"

var _db = null
var _engine = null


func run(h) -> void:
    var db := ContentDB.new()
    var loaded = db.load(MANIFEST)
    if not Result.is_ok(loaded):
        h.begin("审查 · 前置")
        h.check("battle_mvp 清单加载成功", false, str(loaded))
        return
    _db = db
    _engine = BattleEngine.new(db)
    h.begin("审查 §3.3/§4 · 相位顺序与首回合")
    _phases(h)
    h.begin("审查 §10.1/§10.2 · 完成/屏障/放松分层")
    _layers(h)
    h.begin("审查 §5.3/§3.2 · 费用与支付")
    _payment(h)
    h.begin("审查 §5.3 偏差探针 · 主动支付精力")
    _payment_gap(h)
    h.begin("审查 §17.1 · DDL 超时")
    _ddl(h)
    h.begin("审查 §9.2/§7.3 · 效果内选择与随机不刷新")
    _choice(h)
    h.begin("审查 §9.1/§9.2/§15 · 触发计数归属")
    _counters(h)
    h.begin("审查 §11.4/§11.5 · 状态到期时点")
    _statuses(h)
    h.begin("审查 §10.4 · 护卫改向与多护卫")
    _guard(h)
    h.begin("审查 §18 · 考试替代面")
    _exam(h)


# ── 工具 ──────────────────────────────────────────────────

## catalog_override：个别子用例需要换清单跑（例如 A04 是数据驱动 hook，battle_mvp 只启用 A01）。
func _begin(encounter_id: String, deck: Array, relics: Array = [], seed_value: int = 0, vitality: int = 72, catalog_override = null) -> Dictionary:
    var source = RandomSourceScript.new(seed_value)
    var runner = _engine if catalog_override == null else BattleEngine.new(catalog_override)
    return runner.begin({
        "battle_id": "Rtest#1",
        "node_id": "n1",
        "encounter_id": encounter_id,
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "vitality": vitality,
        "max_vitality": vitality,
        "cards": deck,
        "relics": relics,
        "rng_state": source.export_state(),
    })


func _deck(definition_id: String, count: int, upgrade_level: int = 0) -> Array:
    var deck := []
    for index in range(count):
        deck.append({
            "card_id": "Rtest#B_%s_%d" % [definition_id, index],
            "definition_id": definition_id,
            "origin_card_id": "Rtest#R_%s_%d" % [definition_id, index],
            "upgrade_level": upgrade_level,
        })
    return deck


func _state(step: Dictionary):
    return step["data"]["state"]


func _rng(step: Dictionary):
    return step["data"]["rng_state"]


func _ok(h, label: String, step: Dictionary) -> bool:
    if Result.is_ok(step):
        h.check(label, true)
        return true
    h.check(label, false, str(step.get("error")))
    return false


func _card_ids(state, definition_id: String) -> Array:
    var matches := []
    for card_id in state.card_by_id:
        var card = state.card_by_id[card_id]
        if card.definition_id == definition_id:
            matches.append(String(card_id))
    matches.sort()
    return matches


## 白盒把某张牌挪到手牌（审查时序时避开洗牌顺序，只关心规则本身）。
func _to_hand(state, definition_id: String, occurrence: int = 0) -> String:
    var matches := _card_ids(state, definition_id)
    if occurrence >= matches.size():
        return ""
    var card_id: String = matches[occurrence]
    state.move_card(card_id, GameConstants.ZONE_HAND)
    return card_id


func _ensure_hand(state, card_id: String) -> void:
    if state.zone_of(card_id) != GameConstants.ZONE_HAND:
        state.move_card(card_id, GameConstants.ZONE_HAND)


func _hand_card(state, definition_id: String, occurrence: int = 0) -> String:
    var matches := []
    for card_id in state.card_ids_in(GameConstants.ZONE_HAND):
        var card = state.get_card(String(card_id))
        if card != null and card.definition_id == definition_id:
            matches.append(String(card_id))
    if occurrence >= matches.size():
        return ""
    return matches[occurrence]


## 按定义出牌（工作牌自动带主目标）。
func _play(engine, step: Dictionary, definition_id: String, work: bool = false) -> Dictionary:
    var state = _state(step)
    var card_id := _hand_card(state, definition_id)
    if card_id.is_empty():
        card_id = _to_hand(state, definition_id)
    var payload := {"card_id": card_id}
    if work and not state.tasks.is_empty():
        payload["target_ids"] = [state.tasks[0].task_id]
    return engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}, _rng(step))


## 按卡实例出牌（需要精确控制是哪个实例时用）。
func _play_id(engine, step: Dictionary, card_id: String, target_ids: Array = []) -> Dictionary:
    var payload := {"card_id": card_id}
    if not target_ids.is_empty():
        payload["target_ids"] = target_ids
    return engine.apply(_state(step), {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}, _rng(step))


func _end_turn(engine, step: Dictionary) -> Dictionary:
    return engine.apply(_state(step), {"type": GameConstants.ACTION_END_TURN, "payload": {}}, _rng(step))


func _stacks(state, holder_id: String, status_id: String) -> int:
    var status = state.find_status(holder_id, status_id)
    return 0 if status == null else int(status.stacks)


func _has_event(step: Dictionary, event_type: String) -> bool:
    for raw in step["data"]["events"]:
        var event: Dictionary = raw
        if String(event.get("type", "")) == event_type:
            return true
    return false


func _find_event(step: Dictionary, event_type: String, key: String, value: String) -> Dictionary:
    for raw in step["data"]["events"]:
        var event: Dictionary = raw
        if String(event.get("type", "")) != event_type:
            continue
        if String(event.get(key, "")) == value:
            return event
    return {}


func _battle_count(state, definition_id: String) -> int:
    var key = BattleState.counter_key(GameConstants.COUNTER_SCOPE_BATTLE, definition_id, "prepare")
    if not state.counters.has(key):
        return 0
    return int(state.counters[key].count)

# ── §3.3 / §4 相位顺序 ────────────────────────────────────

func _phases(h) -> void:
    var step = _begin("N01", _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    h.eq("begin 停在玩家出牌阶段", state.phase, GameConstants.PHASE_PLAYER_ACTION)
    h.eq("round_index 从 1 开始", state.round_index, 1)
    h.eq("首轮专注 3 [ENG-001]", state.player.focus, 3)
    h.eq("首轮抽 5 且不重复抽起手 [DRW-001]", state.zones.hand.size(), 5)
    h.eq("N01 DDL=8 [DDL-001]", state.ddl, 8)
    var expected := ["player_prepare", "draw", "player_action", "ally_action", "discard",
        "enemy_prepare", "enemy_skill", "enemy_pressure", "round_end"]
    h.check("PHASE_ORDER 与 §3.3 同序（不走字典遍历）", str(BattleEngine.PHASE_ORDER) == str(expected), "got=%s" % str(BattleEngine.PHASE_ORDER))

    step = _play(_engine, step, "K01", true)
    if not _ok(h, "打出 K01", step):
        return
    h.eq("出牌后专注 2（旧剩余留到准备阶段清零）", _state(step).player.focus, 2)

    var turn = _end_turn(_engine, step)
    if not _ok(h, "结束回合", turn):
        return
    var phases := []
    for raw in turn["data"]["events"]:
        var event: Dictionary = raw
        if String(event.get("type", "")) == BattleEngine.EVENT_PHASE_CHANGED:
            phases.append(String(event.get("phase", "")))
    var tail := expected.slice(3) + expected.slice(0, 3)
    h.check("end_turn 严格按相位机推进 [PLR-006]/[ENM-004]", str(phases) == str(tail), "got=%s" % str(phases))
    var after = _state(turn)
    h.eq("进入第 2 轮", after.round_index, 2)
    h.eq("第 2 轮专注 3（2 旧剩余先清零再加 3）", after.player.focus, 3)
    h.eq("轮末扣 DDL：8→7", after.ddl, 7)
    h.eq("首轮意图压力 5 已施加：72-5=67", after.player.vitality, 67)


# ── §10.1/§10.2 完成 / 屏障 / 放松分层 ────────────────────

func _layers(h) -> void:
    # 完成：先扣任务屏障，再减未完成量；超额不结转。
    var step = _begin("B01", _deck("K01", 14))
    if not _ok(h, "B01 begin 成功", step):
        return
    var state = _state(step)
    state.tasks[0].shield = 5
    step = _play(_engine, step, "K01", true)
    if not _ok(h, "打 K01（任务屏障 5）", step):
        return
    state = _state(step)
    h.eq("屏障先吸收 5：未完成量只减 1（20-1=19）", state.tasks[0].work_remaining, 19)
    h.eq("屏障被扣空", state.tasks[0].shield, 0)

    state.tasks[0].work_remaining = 2
    step = _play(_engine, step, "K01", true)
    if not _ok(h, "打 K01 完成第一阶段", step):
        return
    state = _state(step)
    h.eq("先建下一阶段而不是判胜 [DDL-002]", state.tasks.size(), 1)
    h.eq("新阶段满工作量 25（不承接旧阶段超额 4）", state.tasks[0].work_remaining, 25)
    h.eq("新阶段清旧屏障", state.tasks[0].shield, 0)
    h.eq("新阶段 phase_key=integral", state.tasks[0].phase_key, "integral")

    # 屏障在敌方准备清零，随后本次技能获得的新屏障保留。
    step = _end_turn(_engine, step)
    if not _ok(h, "推进到第 2 轮", step):
        return
    state = _state(step)
    h.eq("B01 第 1 轮意图压力 7：72-7=65", state.player.vitality, 65)
    state.tasks[0].shield = 9
    step = _end_turn(_engine, step)
    if not _ok(h, "推进到第 3 轮", step):
        return
    state = _state(step)
    h.eq("[ENM-001] 准备清旧屏障后，技能新屏障 5 保留", state.tasks[0].shield, 5)
    h.eq("第 2 轮意图只有屏障没有压力：精力不变", state.player.vitality, 65)

    # 压力：先扣放松，再减精力；放松在下一次准备阶段清零。
    var step2 = _begin("N01", _deck("K02", 6) + _deck("K01", 4))
    if not _ok(h, "N01 begin（放松用例）", step2):
        return
    step2 = _play(_engine, step2, "K02")
    step2 = _play(_engine, step2, "K02")
    if not _ok(h, "连打两张 K02", step2):
        return
    h.eq("放松叠到 10", _state(step2).player.relax, 10)
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "结束第 1 回合", step2):
        return
    var st2 = _state(step2)
    h.eq("压力 5 全被放松吸收：精力不变", st2.player.vitality, 72)
    h.eq("准备阶段清零旧放松（剩 5 不带过来）", st2.player.relax, 0)
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "结束第 2 回合", step2):
        return
    h.eq("第 2 轮压力 7 无放松可挡：72-7=65", _state(step2).player.vitality, 65)

    # 单位放松同样在下一次准备清零。
    var step3 = _begin("N01", _deck("K46", 4) + _deck("K01", 4))
    if not _ok(h, "N01 begin（单位放松）", step3):
        return
    step3 = _play(_engine, step3, "K46")
    if not _ok(h, "召入 F04", step3):
        return
    step3 = _end_turn(_engine, step3)
    if not _ok(h, "结束回合", step3):
        return
    var st3 = _state(step3)
    h.eq("F04 自身放松 2 吸收后再挨打：12-1-(5-2)=8", st3.units[0].vitality, 8)
    h.eq("单位旧放松在下一次准备清零", st3.units[0].relax, 0)


# ── §5.3 / §3.2 费用与支付 ────────────────────────────────

func _payment(h) -> void:
    # 专注不足不能出牌：牌、专注、未完成量全不变。
    var step = _begin("N01", _deck("K01", 10))
    if not _ok(h, "N01 begin 成功", step):
        return
    for index in range(3):
        step = _play(_engine, step, "K01", true)
        if not _ok(h, "打出第 %d 张 K01" % (index + 1), step):
            return
    var state = _state(step)
    h.eq("三张 K01 花光专注", state.player.focus, 0)
    var card_id := _to_hand(state, "K01")
    var before_work = state.tasks[0].work_remaining
    var denied = _engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": card_id, "target_ids": [state.tasks[0].task_id]}}, _rng(step))
    h.eq("[ENG-003] 专注 0 不能出牌", Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.eq("拒绝后牌仍在手", state.zone_of(card_id), GameConstants.ZONE_HAND)
    h.eq("拒绝后专注不变", state.player.focus, 0)
    h.eq("拒绝后未完成量不变", state.tasks[0].work_remaining, before_work)

    # 费用减免先计入实际支付校验，且只在合法出牌成功后消费。
    var step2 = _begin("N01", _deck("K53", 2) + _deck("K01", 10))
    step2 = _play(_engine, step2, "K53")
    if not _ok(h, "建立 L03（费用 2）", step2):
        return
    h.eq("建立场景后专注 1", _state(step2).player.focus, 1)
    var st2 = _state(step2)
    var invalid = _engine.apply(st2, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": _to_hand(st2, "K01"), "target_ids": ["no-such-task"]}}, _rng(step2))
    h.eq("非法目标被拒", Result.error_code(invalid), GameConstants.ERROR_INVALID_TARGET)
    step2 = _play(_engine, step2, "K01", true)
    if not _ok(h, "失败后第一张工作牌仍享 L03 减免", step2):
        return
    st2 = _state(step2)
    h.eq("减免后费用 0：专注仍 1", st2.player.focus, 1)
    h.eq("完成量照常结算 24-6=18", st2.tasks[0].work_remaining, 18)
    step2 = _play(_engine, step2, "K01", true)
    if not _ok(h, "本回合第二张工作牌按原价", step2):
        return
    st2 = _state(step2)
    h.eq("第二张费用 1：专注 0", st2.player.focus, 0)
    h.eq("完成量 18-6=12", st2.tasks[0].work_remaining, 12)


# ── §5.3 偏差探针：主动支付精力 ───────────────────────────

func _payment_gap(h) -> void:
    # [偏差探针] RB-03/RB-04、T03/T04：主动支付精力绕过放松，支付后必须至少剩 1 精力。
    var payable := []
    for raw_id in _db.enabled_ids(GameConstants.KIND_CARD):
        var definition: Dictionary = _db.definition(GameConstants.KIND_CARD, String(raw_id))
        if definition.has("vitality_cost") or definition.has("pay_vitality"):
            payable.append(String(raw_id))
    var enabled_count: int = _db.enabled_ids(GameConstants.KIND_CARD).size()
    h.check("[记录] battle_mvp 12 张启用牌都没有精力代价字段", payable.is_empty(), "带精力代价字段的牌：%s" % str(payable))

    # [记录] CostQuote.vitality_cost 对全部启用牌恒为 0（没有来源可读）。
    var step = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin 成功", step):
        return
    var state = _state(step)
    var all_zero := true
    var checked := 0
    for raw_card_id in state.card_ids_in(GameConstants.ZONE_HAND):
        var face = _engine.resolve_face(state, String(raw_card_id))
        if not Result.is_ok(face):
            all_zero = false
            continue
        var quote = BattleCardRules.cost_quote(_db, state, face["data"])
        checked += 1
        if int(quote.get("vitality_cost", 0)) != 0:
            all_zero = false
    h.check("[记录] CostQuote.vitality_cost 对全部启用牌恒为 0", all_zero and checked > 0, "checked=%d" % checked)
    h.eq("[记录] 规则参数 minimum_vitality_after_payment 已配置", _db.battle_int("minimum_vitality_after_payment", -1), 1)
    _vitality_payment_probe(h)


# ── §17.1 DDL 超时 ────────────────────────────────────────

func _ddl(h) -> void:
    # T10：玩家行动内完成最后任务 → 立即胜利，不再扣本轮 DDL。
    var step = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin 成功", step):
        return
    var state = _state(step)
    state.tasks[0].work_remaining = 2
    step = _play(_engine, step, "K01", true)
    if not _ok(h, "完成最终任务", step):
        return
    var outcome: Variant = step["data"]["outcome"]
    h.check("立即产生结局", outcome != null)
    if outcome != null:
        h.eq("结果=won [END-001]", outcome["result"], GameConstants.OUTCOME_WON)
        h.eq("原因=tasks_completed", outcome["reason"], GameConstants.REASON_TASKS_COMPLETED)
    h.eq("不再扣 DDL（仍为 8）", _state(step).ddl, 8)
    h.check("没有 ddl_ticked 事件", not _has_event(step, BattleEngine.EVENT_DDL_TICKED))

    # T11：DDL=1 且轮末仍有任务 → 超时失败。
    var step2 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin 2 成功", step2):
        return
    var st2 = _state(step2)
    st2.ddl = 1
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "结束回合", step2):
        return
    var outcome2: Variant = step2["data"]["outcome"]
    h.check("产生结局", outcome2 != null)
    if outcome2 != null:
        h.eq("结果=lost", outcome2["result"], GameConstants.OUTCOME_LOST)
        h.eq("原因=deadline_expired [DDL-001]", outcome2["reason"], GameConstants.REASON_DEADLINE_EXPIRED)
    h.eq("DDL 归零", _state(step2).ddl, 0)
    h.eq("不是精力失败：72-5=67", _state(step2).player.vitality, 67)


# ── §9.2 / §7.3 效果内选择与随机不刷新 ────────────────────

func _choice(h) -> void:
    var step = _begin("N01", _deck("K03", 3) + _deck("K01", 6))
    if not _ok(h, "N01 begin 成功", step):
        return
    step = _play(_engine, step, "K03")
    if not _ok(h, "打出 K03（抽 2 弃 1）", step):
        return
    var pending: Variant = step["data"]["pending_choice"]
    h.check("出现效果内选择", pending != null)
    h.eq("待选时 stable=false", bool(step["data"]["stable"]), false)
    if pending == null:
        return
    var state = _state(step)
    h.eq("待选暂停态", state.phase, GameConstants.PHASE_AWAITING_CHOICE)
    var request: Dictionary = pending
    h.eq("选择种类=discard", String(request.get("kind", "")), "discard")
    h.eq("必须选 1 张", int(request.get("min_count", -1)), 1)
    h.eq("最多选 1 张", int(request.get("max_count", -1)), 1)
    var candidates: Array = request.get("candidates", [])
    h.eq("候选=抽牌之后的手牌（含新抽到的 2 张）", candidates.size(), 6)
    h.eq("候选与手牌区一致", candidates.size(), state.zones.hand.size())
    var choice_id := String(request.get("choice_id", ""))

    # 待选期间不能另出牌或结束回合 [PLY-002]。
    var other = _engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": _hand_card(state, "K01"), "target_ids": [state.tasks[0].task_id]}}, _rng(step))
    h.eq("待选期间禁止出牌", Result.error_code(other), GameConstants.ERROR_CHOICE_PENDING)
    var turn = _engine.apply(state, {"type": GameConstants.ACTION_END_TURN, "payload": {}}, _rng(step))
    h.eq("待选期间禁止结束回合", Result.error_code(turn), GameConstants.ERROR_CHOICE_PENDING)

    # 非法选择不清除原待选：等于没有取消整张牌、回看牌序的途径。
    var bad_count = _engine.apply(state, {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {"choice_id": choice_id, "selected_ids": []}}, _rng(step))
    h.eq("少选被拒", Result.error_code(bad_count), GameConstants.ERROR_INVALID_ARGUMENT)
    var bad_id = _engine.apply(state, {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {"choice_id": choice_id, "selected_ids": ["ghost"]}}, _rng(step))
    h.eq("非候选被拒", Result.error_code(bad_id), GameConstants.ERROR_INVALID_TARGET)
    h.check("原待选仍在（不能取消整张牌）", state.resolution != null and state.resolution.choice != null)
    h.eq("手牌数不变", state.zones.hand.size(), 6)

    var chosen := String((candidates[0] as Dictionary).get("id", ""))
    var confirmed = _engine.apply(state, {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {"choice_id": choice_id, "selected_ids": [chosen]}}, _rng(step))
    if not _ok(h, "确认弃牌", confirmed):
        return
    var after = _state(confirmed)
    h.eq("手牌 6-1=5", after.zones.hand.size(), 5)
    h.eq("被弃的牌进弃牌堆", after.zone_of(chosen), GameConstants.ZONE_DISCARD)
    h.check("结算结束", after.resolution == null)
    h.eq("回到玩家出牌阶段", after.phase, GameConstants.PHASE_PLAYER_ACTION)
    h.eq("待选不重复扣费：专注仍 2", after.player.focus, 2)
    h.check("确认后又回到稳定点", bool(confirmed["data"]["stable"]))

    # [记录] 待选张数是定值（min=max），引擎没有「至多/可选（允许选 0）」的表达。
    h.eq("[记录] 待选张数为定值而非区间", int(request.get("min_count", -1)) == int(request.get("max_count", -1)), true)

    # 随机不刷新：同种子同序列结果一致；被拒操作与 preview 不推进随机。
    var digest_a := _k03_digest(3, false)
    var digest_b := _k03_digest(3, false)
    h.check("摘要探针有实际内容", digest_a.length() > 10, digest_a)
    h.eq("[PLY-002] 同种子同序列结果一致（随机结果不刷新）", digest_a, digest_b)
    var digest_c := _k03_digest(3, true)
    h.eq("一次被拒出牌不影响后续随机序列", digest_c, digest_a)


## 同一 rng_state 下「预览 + 出牌 + 确认」的完整摘要，用来证明随机不刷新。
func _k03_digest(seed_value: int, with_failure: bool) -> String:
    var step = _begin("N01", _deck("K03", 3) + _deck("K01", 6), [], seed_value)
    if not Result.is_ok(step):
        return "begin-failed"
    var state = _state(step)
    var k03 := _hand_card(state, "K03")
    if k03.is_empty():
        k03 = _to_hand(state, "K03")
    var k01 := _hand_card(state, "K01")
    if k01.is_empty():
        k01 = _to_hand(state, "K01")
    _engine.preview(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": k03}})
    if with_failure:
        var refused = _engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": k01, "target_ids": ["no-such-task"]}}, _rng(step))
        if Result.is_ok(refused):
            return "unexpected-success"
    var played = _engine.apply(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": k03}}, _rng(step))
    if not Result.is_ok(played):
        return "play-failed"
    var pending: Variant = played["data"]["pending_choice"]
    if pending == null:
        return "no-choice"
    var request: Dictionary = pending
    var chosen := String((request.get("candidates", []) as Array)[0].get("id", ""))
    var confirmed = _engine.apply(_state(played), {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {"choice_id": String(request.get("choice_id", "")), "selected_ids": [chosen]}}, _rng(played))
    if not Result.is_ok(confirmed):
        return "confirm-failed"
    var after = _state(confirmed)
    var ids := []
    for card_id in after.zones.hand:
        ids.append(String(card_id))
    ids.sort()
    return "%s|%s|%s" % [str(ids), str(after.player.focus), str(confirmed["data"]["rng_state"])]


# ── §9.1 / §15 触发计数归属 ───────────────────────────────

func _counters(h) -> void:
    # K13 每实例每回合 1 次：回收入手/换场不刷新，回合推进才重置。
    var step = _begin("N01", _deck("K13", 2) + _deck("K01", 8))
    if not _ok(h, "N01 begin 成功", step):
        return
    var state = _state(step)
    var k13a := _to_hand(state, "K13", 0)
    var k13b := _to_hand(state, "K13", 1)
    step = _play_id(_engine, step, k13a)
    if not _ok(h, "打出 K13#1", step):
        return
    state = _state(step)
    h.eq("获得 1 编译", _stacks(state, state.player.entity_id, GameConstants.STATUS_COMPILE), 1)
    h.eq("K13 费用 0：专注仍 3", state.player.focus, 3)
    var key = BattleState.counter_key(GameConstants.COUNTER_SCOPE_INSTANCE_ROUND, "Rtest#R_K13_0", "limit:K13:")
    h.check("计数键按原始卡实例归属 [§9]", state.counters.has(key), str(key))
    if state.counters.has(key):
        h.eq("本回合已记 1 次", int(state.counters[key].count), 1)

    # 回收入手后重打同一实例：同回合限次仍然生效。
    _ensure_hand(state, k13a)
    var again = _play_id(_engine, step, k13a)
    h.eq("回收后重打被限次拒绝 [K13/T20]", Result.error_code(again), GameConstants.ERROR_LIMIT_REACHED)
    h.eq("拒绝后编译仍 1", _stacks(state, state.player.entity_id, GameConstants.STATUS_COMPILE), 1)
    h.eq("拒绝后牌仍在手", state.zone_of(k13a), GameConstants.ZONE_HAND)

    # 另一张实体（不同 origin）同回合可照常打：限次是每实例而不是每定义。
    step = _play_id(_engine, step, k13b)
    if not _ok(h, "另一实例 K13#2 可打", step):
        return
    h.eq("编译 2", _stacks(_state(step), _state(step).player.entity_id, GameConstants.STATUS_COMPILE), 2)

    # 回合推进后同一实例重置。
    step = _end_turn(_engine, step)
    if not _ok(h, "结束回合", step):
        return
    state = _state(step)
    _ensure_hand(state, k13a)
    step = _play_id(_engine, step, k13a)
    if not _ok(h, "第 2 回合同一实例可再打", step):
        return
    h.eq("编译 3", _stacks(_state(step), _state(step).player.entity_id, GameConstants.STATUS_COMPILE), 3)

    # 场景本战次数：换场再换回不刷新 [SCN-001]/T09。
    var step2 = _begin("N01", _deck("K51", 2) + _deck("K53", 1) + _deck("K01", 8))
    if not _ok(h, "N01 begin（场景次数）", step2):
        return
    var st2 = _state(step2)
    var l01a := _to_hand(st2, "K51", 0)
    var l01b := _to_hand(st2, "K51", 1)
    var l03 := _to_hand(st2, "K53", 0)
    step2 = _play_id(_engine, step2, l01a)
    if not _ok(h, "建立 L01", step2):
        return
    st2 = _state(step2)
    h.check("L01 已建立", st2.scene != null and st2.scene.definition_id == "L01")
    for index in range(3):
        step2 = _end_turn(_engine, step2)
        if not _ok(h, "轮末 #%d" % (index + 1), step2):
            return
    st2 = _state(step2)
    h.eq("三轮准备各恢复 2：72-5-7-5+6=61", st2.player.vitality, 61)
    h.eq("L01 本战计数 3", _battle_count(st2, "L01"), 3)

    # 换场再换回：本战次数不重置。
    _ensure_hand(st2, l03)
    step2 = _play_id(_engine, step2, l03)
    if not _ok(h, "替换为 L03", step2):
        return
    st2 = _state(step2)
    h.check("当前场景 L03", st2.scene != null and st2.scene.definition_id == "L03")
    _ensure_hand(st2, l01b)
    step2 = _play_id(_engine, step2, l01b)
    if not _ok(h, "换回 L01", step2):
        return
    st2 = _state(step2)
    h.check("当前场景又变回 L01", st2.scene != null and st2.scene.definition_id == "L01")
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "第 4 个轮末", step2):
        return
    st2 = _state(step2)
    h.eq("第 4 次准备不再恢复（61-7=54）", st2.player.vitality, 54)
    h.eq("L01 本战计数 4（超上限但不清零）", _battle_count(st2, "L01"), 4)


# ── §11.4 / §11.5 状态到期时点 ────────────────────────────

func _statuses(h) -> void:
    # 灵感：工作牌第一段每层 +2，打出工作牌后清空；未用轮末清除。
    var step = _begin("N01", _deck("K04", 3) + _deck("K01", 8))
    if not _ok(h, "N01 begin 成功", step):
        return
    step = _play(_engine, step, "K04")
    if not _ok(h, "打 K04 获得灵感", step):
        return
    var state = _state(step)
    h.eq("灵感 2 层", _stacks(state, state.player.entity_id, GameConstants.STATUS_INSPIRATION), 2)
    var before = state.tasks[0].work_remaining
    step = _play(_engine, step, "K01", true)
    if not _ok(h, "打 K01", step):
        return
    state = _state(step)
    h.eq("第一段 6+2×2=10", before - state.tasks[0].work_remaining, 10)
    h.eq("打出工作牌后灵感清空", _stacks(state, state.player.entity_id, GameConstants.STATUS_INSPIRATION), 0)
    step = _play(_engine, step, "K04")
    if not _ok(h, "第二次 K04", step):
        return
    step = _end_turn(_engine, step)
    if not _ok(h, "轮末", step):
        return
    h.eq("未用灵感在轮末清除", _stacks(_state(step), _state(step).player.entity_id, GameConstants.STATUS_INSPIRATION), 0)

    # 焦虑：下次准备每层 -1 专注，生效后清除；层数按上限 2 截断。
    var step2 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（焦虑）", step2):
        return
    _state(step2).tasks[0].intent_snapshot = {"index": 1, "gain_status": {"status": "anxiety", "stacks": 5, "target": "player"}}
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "敌方施加焦虑", step2):
        return
    var st2 = _state(step2)
    var gained := _find_event(step2, BattleEngine.EVENT_STATUS_GAINED, "status_id", "anxiety")
    h.eq("获得量按上限 2 截断", int(gained.get("stacks", -1)), 2)
    h.eq("T13：原焦虑扣回能 3-2=1", st2.player.focus, 1)
    h.eq("T13：生效后清除", _stacks(st2, st2.player.entity_id, GameConstants.STATUS_ANXIETY), 0)
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "下一轮准备", step2):
        return
    h.eq("清除后不影响更后面的准备（回到 3）", _state(step2).player.focus, 3)

    # T13 精确形态：L04 第 2 次准备施加 1 焦虑，影响下一次准备而不是倒流影响本次。
    var step3 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（L04）", step3):
        return
    var st3 = _state(step3)
    st3.scene = BattleState.create_scene("Rtest#1|s_audit", "L04", st3.round_index)
    step3 = _end_turn(_engine, step3)
    if not _ok(h, "L04 第 1 次准备", step3):
        return
    st3 = _state(step3)
    h.eq("第 1 次准备不加焦虑", _stacks(st3, st3.player.entity_id, GameConstants.STATUS_ANXIETY), 0)
    step3 = _end_turn(_engine, step3)
    if not _ok(h, "L04 第 2 次准备", step3):
        return
    st3 = _state(step3)
    h.eq("第 2 次准备施加 1 焦虑", _stacks(st3, st3.player.entity_id, GameConstants.STATUS_ANXIETY), 1)
    h.eq("本次准备按无焦虑计算（专注 3）", st3.player.focus, 3)
    step3 = _end_turn(_engine, step3)
    if not _ok(h, "L04 第 3 次准备", step3):
        return
    st3 = _state(step3)
    h.eq("T13：新焦虑在下一次准备扣回能 3-1=2", st3.player.focus, 2)
    h.eq("T13：扣完清除", _stacks(st3, st3.player.entity_id, GameConstants.STATUS_ANXIETY), 0)

    # 拖延：下次基础抽牌每层 -1（上限 3），生效后清除。
    var step4 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（拖延）", step4):
        return
    _state(step4).tasks[0].intent_snapshot = {"index": 1, "gain_status": {"status": "procrastination", "stacks": 9, "target": "player"}}
    step4 = _end_turn(_engine, step4)
    if not _ok(h, "敌方施加拖延", step4):
        return
    var st4 = _state(step4)
    var gained4 := _find_event(step4, BattleEngine.EVENT_STATUS_GAINED, "status_id", "procrastination")
    h.eq("获得量按上限 3 截断", int(gained4.get("stacks", -1)), 3)
    h.eq("下次抽牌 5-3=2", st4.zones.hand.size(), 2)
    h.eq("生效后清除", _stacks(st4, st4.player.entity_id, GameConstants.STATUS_PROCRASTINATION), 0)
    step4 = _end_turn(_engine, step4)
    if not _ok(h, "再下一轮", step4):
        return
    h.eq("之后恢复抽 5", _state(step4).zones.hand.size(), 5)

    # 困倦：下次玩家行动工作牌第一段每层 -1（上限 2），行动结束清除。
    var step5 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（困倦）", step5):
        return
    _state(step5).tasks[0].intent_snapshot = {"index": 1, "gain_status": {"status": "drowsiness", "stacks": 2, "target": "player"}}
    step5 = _end_turn(_engine, step5)
    if not _ok(h, "敌方施加困倦", step5):
        return
    var st5 = _state(step5)
    h.eq("困倦 2 层", _stacks(st5, st5.player.entity_id, GameConstants.STATUS_DROWSINESS), 2)
    var before5 = st5.tasks[0].work_remaining
    step5 = _play(_engine, step5, "K01", true)
    if not _ok(h, "带困倦打工作牌", step5):
        return
    st5 = _state(step5)
    h.eq("第一段 6-2=4", before5 - st5.tasks[0].work_remaining, 4)
    h.eq("行动结束清除", _stacks(st5, st5.player.entity_id, GameConstants.STATUS_DROWSINESS), 0)

    # 额外要求：任务每层压力 +2（上限 3），本战有效。
    var step6 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（额外要求）", step6):
        return
    _state(step6).tasks[0].intent_snapshot = {"index": 1, "extra_requirements": 9, "pressure": 5}
    step6 = _end_turn(_engine, step6)
    if not _ok(h, "加额外要求后挨打", step6):
        return
    var st6 = _state(step6)
    h.eq("层数按上限 3 截断", _stacks(st6, st6.tasks[0].task_id, GameConstants.STATUS_EXTRA_REQUIREMENTS), 3)
    h.eq("压力 5+3×2=11：72-11=61", st6.player.vitality, 61)
    step6 = _end_turn(_engine, step6)
    if not _ok(h, "第 3 轮", step6):
        return
    h.eq("本战有效：第 2 轮 7+6=13 → 61-13=48", _state(step6).player.vitality, 48)

    # [偏差探针] 查重护盾（§3.6/§11.5）：应是任务屏障值，参与「先扣屏障再减未完成量」。
    var step7 = _begin("N01", _deck("K01", 8))
    if not _ok(h, "N01 begin（查重护盾）", step7):
        return
    _state(step7).tasks[0].intent_snapshot = {"index": 1, "gain_status": {"status": "plagiarism_shield", "stacks": 2, "target": "task"}}
    step7 = _end_turn(_engine, step7)
    if not _ok(h, "任务获得查重护盾", step7):
        return
    var st7 = _state(step7)
    h.eq("状态存在且 2 层", _stacks(st7, st7.tasks[0].task_id, GameConstants.STATUS_PLAGIARISM_SHIELD), 2)
    var before7 = st7.tasks[0].work_remaining
    var played7 = _play(_engine, step7, "K01", true)
    if not _ok(h, "打 K01", played7):
        return
    var st7b = _state(played7)
    h.eq("[偏差探针] 2 层查重护盾应先吸收 2 点完成量（24-6+2=20）", before7 - st7b.tasks[0].work_remaining, 4)
    h.eq("[记录] 实际按无屏障结算（24-6=18）", before7 - st7b.tasks[0].work_remaining, 6)
    step7 = _end_turn(_engine, played7)
    if not _ok(h, "推进一轮", step7):
        return
    var st7c = _state(step7)
    h.eq("状态按 expiry=enemy_prepare 清除", _stacks(st7c, st7c.tasks[0].task_id, GameConstants.STATUS_PLAGIARISM_SHIELD), 0)


# ── §10.4 护卫改向与多护卫 ────────────────────────────────

func _guard(h) -> void:
    # 多护卫取最早入场者。
    var step = _begin("N01", _deck("K43", 3) + _deck("K46", 3))
    if not _ok(h, "N01 begin 成功", step):
        return
    step = _play(_engine, step, "K43")
    step = _play(_engine, step, "K46")
    if not _ok(h, "召入 F01 与 F04", step):
        return
    var state = _state(step)
    h.eq("两个护卫单位", state.units.size(), 2)
    if state.units.size() < 2:
        return
    h.check("F01 入场更早", state.units[0].entered_order < state.units[1].entered_order)
    var first_id = state.units[0].unit_id
    var second_id = state.units[1].unit_id
    step = _end_turn(_engine, step)
    if not _ok(h, "结束回合", step):
        return
    state = _state(step)
    var u1 = state.find_unit(first_id)
    var u2 = state.find_unit(second_id)
    h.check("两名护卫都还活着", u1 != null and u2 != null)
    if u1 != null and u2 != null:
        h.eq("最早入场护卫承受压力：10-1-5=4", u1.vitality, 4)
        h.eq("后入场护卫不被改向：12-1=11", u2.vitality, 11)
    h.eq("两名单位各协作 2：24-4=20", state.tasks[0].work_remaining, 20)

    # 护卫 3 精力无放松承受 5×2：首段暂离、不溢出；次段重新找目标（T06）。
    var step2 = _begin("N01", _deck("K43", 3) + _deck("K01", 4))
    if not _ok(h, "N01 begin 2", step2):
        return
    step2 = _play(_engine, step2, "K43")
    if not _ok(h, "召入 F01", step2):
        return
    var st2 = _state(step2)
    st2.units[0].vitality = 3
    var guard_id = st2.units[0].unit_id
    st2.tasks[0].intent_snapshot = {"index": 1, "pressure": 5, "pressure_times": 2}
    step2 = _end_turn(_engine, step2)
    if not _ok(h, "结束回合", step2):
        return
    st2 = _state(step2)
    h.check("首段后护卫暂离", st2.find_unit(guard_id) == null)
    h.eq("次段无护卫则打主角：72-5=67", st2.player.vitality, 67)
    h.eq("协作仍已结算：24-2=22", st2.tasks[0].work_remaining, 22)

    # 两个护卫按入场顺序依次承接。
    var step3 = _begin("N01", _deck("K43", 3) + _deck("K46", 3))
    if not _ok(h, "N01 begin 3", step3):
        return
    step3 = _play(_engine, step3, "K43")
    step3 = _play(_engine, step3, "K46")
    if not _ok(h, "召入两名护卫", step3):
        return
    var st3 = _state(step3)
    st3.units[0].vitality = 3
    var g1 = st3.units[0].unit_id
    var g2 = st3.units[1].unit_id
    st3.tasks[0].intent_snapshot = {"index": 1, "pressure": 5, "pressure_times": 2}
    step3 = _end_turn(_engine, step3)
    if not _ok(h, "结束回合", step3):
        return
    st3 = _state(step3)
    h.check("最早入场的护卫第一段暂离", st3.find_unit(g1) == null)
    var u3 = st3.find_unit(g2)
    h.check("次早护卫仍在场", u3 != null)
    if u3 != null:
        h.eq("第二段改由次早护卫承接：12-1-(5-2)=8", u3.vitality, 8)
    h.eq("主角未被穿透", st3.player.vitality, 72)

    # 全体压力不被护卫改向。
    var step4 = _begin("N01", _deck("K43", 3) + _deck("K01", 4))
    if not _ok(h, "N01 begin 4", step4):
        return
    step4 = _play(_engine, step4, "K43")
    if not _ok(h, "召入 F01", step4):
        return
    var st4 = _state(step4)
    var gid = st4.units[0].unit_id
    st4.tasks[0].intent_snapshot = {"index": 1, "pressure_all": 5}
    step4 = _end_turn(_engine, step4)
    if not _ok(h, "结束回合", step4):
        return
    st4 = _state(step4)
    h.eq("全体压力打到主角：72-5=67", st4.player.vitality, 67)
    var u4 = st4.find_unit(gid)
    h.check("护卫仍在场", u4 != null)
    if u4 != null:
        h.eq("护卫照样承受：10-1-5=4", u4.vitality, 4)


# ── §18 考试替代面 ────────────────────────────────────────

func _exam(h) -> void:
    var step = _begin("B01", _deck("K44", 2) + _deck("K53", 1) + _deck("K01", 8))
    if not _ok(h, "B01 begin 成功", step):
        return
    var state = _state(step)
    h.check("B01 带独立作答 [EXM-001]", state.has_exam_limit(GameConstants.EXAM_INDEPENDENT_ANSWER))
    h.check("B01 带固定考场 [EXM-001]", state.has_exam_limit(GameConstants.EXAM_FIXED_ROOM))
    var k44a := _to_hand(state, "K44", 0)
    var face = _engine.resolve_face(state, k44a)
    h.check("K44 解析成功", Result.is_ok(face))
    if Result.is_ok(face):
        h.eq("备考面标记", String(face["data"].get("exam_face", "")), GameConstants.EXAM_FACE_PREPARE)
        h.eq("保留原卡类型 cooperation [EXM-002]", String(face["data"].get("type", "")), GameConstants.CARD_COOPERATION)
        h.eq("同费用 2", int(face["data"].get("cost", -1)), 2)
    step = _play_id(_engine, step, k44a)
    if not _ok(h, "独立作答打 K44", step):
        return
    var after = _state(step)
    h.eq("获得 5 放松（基础面）", after.player.relax, 5)
    h.eq("不召入单位", after.units.size(), 0)
    h.eq("保留耗尽标记", after.zone_of(k44a), GameConstants.ZONE_EXHAUST)
    h.eq("费用 2：专注 3-2=1", after.player.focus, 1)
    h.check("没有 unit_summoned 事件", not _has_event(step, BattleEngine.EVENT_UNIT_SUMMONED))

    # 升级备考面 7 放松；升级的 unit_bonus 不得漏到替代面。
    var step_u = _begin("B01", _deck("K44", 1, 1) + _deck("K01", 8))
    if not _ok(h, "B01 begin（升级 K44）", step_u):
        return
    var su = _state(step_u)
    var k44u := _to_hand(su, "K44", 0)
    step_u = _play_id(_engine, step_u, k44u)
    if not _ok(h, "打升级 K44", step_u):
        return
    h.eq("升级备考面 7 放松 [EXM-002]", _state(step_u).player.relax, 7)
    h.eq("升级面也不召入", _state(step_u).units.size(), 0)

    # 替代先于槽位校验：满 3 单位也能在独立作答下出合作牌（无需 replace_unit_id）。
    var step_s = _begin("B01", _deck("K44", 1) + _deck("K01", 8))
    if not _ok(h, "B01 begin（满槽）", step_s):
        return
    var ss = _state(step_s)
    for index in range(3):
        var unit = BattleState.create_unit("Rtest#1|u_audit%d" % index, "F02", 4, 4)
        unit.entered_order = 100 + index
        ss.units.append(unit)
    var k44s := _to_hand(ss, "K44", 0)
    step_s = _play_id(_engine, step_s, k44s)
    if not _ok(h, "满槽下仍可出备考面", step_s):
        return
    h.eq("单位数不变", _state(step_s).units.size(), 3)
    h.eq("放松照给 5", _state(step_s).player.relax, 5)

    # 固定考场：场景牌 → 回忆面（抽 1、2 放松，不建立场景）。
    var step_r = _begin("B01", _deck("K53", 1) + _deck("K01", 8))
    if not _ok(h, "B01 begin（K53）", step_r):
        return
    var sr = _state(step_r)
    var k53 := _to_hand(sr, "K53", 0)
    var hand_before = sr.zones.hand.size()
    var face_r = _engine.resolve_face(sr, k53)
    if Result.is_ok(face_r):
        h.eq("回忆面标记", String(face_r["data"].get("exam_face", "")), GameConstants.EXAM_FACE_RECALL)
        h.eq("保留原卡类型 scene", String(face_r["data"].get("type", "")), GameConstants.CARD_SCENE)
    step_r = _play_id(_engine, step_r, k53)
    if not _ok(h, "固定考场打 K53", step_r):
        return
    sr = _state(step_r)
    h.eq("抽 1（打 1 张 + 抽 1 张，手牌数不变）", sr.zones.hand.size(), hand_before)
    h.eq("获得 2 放松（基础面）", sr.player.relax, 2)
    h.check("不建立场景", sr.scene == null)
    h.eq("保留耗尽标记", sr.zone_of(k53), GameConstants.ZONE_EXHAUST)
    h.eq("费用 2：专注 1", sr.player.focus, 1)
    h.check("没有 scene_established 事件", not _has_event(step_r, BattleEngine.EVENT_SCENE_ESTABLISHED))

    # 升级回忆面 4 放松、仍不建立场景。
    var step_ru = _begin("B01", _deck("K53", 1, 1) + _deck("K01", 8))
    if not _ok(h, "B01 begin（升级 K53）", step_ru):
        return
    var sru = _state(step_ru)
    var k53u := _to_hand(sru, "K53", 0)
    step_ru = _play_id(_engine, step_ru, k53u)
    if not _ok(h, "打升级 K53（固定考场）", step_ru):
        return
    sru = _state(step_ru)
    h.eq("升级回忆面 4 放松 [EXM-002]", sru.player.relax, 4)
    h.check("升级面也不建立场景", sru.scene == null)

    # 类型适用的费用优惠仍触发：A04 每战首张合作牌 -1，备考面同样适用。
    # 注意：A04 自 2026-10（t10 饰品 hook）起是**数据驱动**的，必须在该清单里启用才会命中；
    # 本套件主清单 battle_mvp 只启用 A01，因此这条子用例单独换 mvp 清单（A04+A01 都启用）。
    var a04_db := ContentDB.new()
    var a04_loaded = a04_db.load("mvp")
    if not Result.is_ok(a04_loaded):
        h.check("A04 子用例：mvp 清单可加载", false, str(a04_loaded))
        return
    h.check("A04 子用例：对照 battle_mvp 未启用 A04（这就是不能共用清单的原因）", _db.definition(GameConstants.KIND_RELIC, "A04").is_empty())
    var a04_engine := BattleEngine.new(a04_db)
    var step_a = _begin("B01", _deck("K44", 2) + _deck("K01", 8), ["A04"], 0, 72, a04_db)
    if not _ok(h, "B01 begin（A04）", step_a):
        return
    var sa = _state(step_a)
    var a1 := _to_hand(sa, "K44", 0)
    var a2 := _to_hand(sa, "K44", 1)
    step_a = _play_id(a04_engine, step_a, a1)
    if not _ok(h, "A04 下打首张合作牌", step_a):
        return
    h.eq("首张合作牌减 1：专注 3-1=2", _state(step_a).player.focus, 2)
    step_a = _play_id(a04_engine, step_a, a2)
    if not _ok(h, "打第二张合作牌", step_a):
        return
    h.eq("第二张按原价 2：专注 0", _state(step_a).player.focus, 0)
    h.eq("两次备考面叠放松 10", _state(step_a).player.relax, 10)


## [偏差探针] RB-03/RB-04、T03/T04：主动支付精力必须「支付后≥1」。
## K10《熬夜》在 mvp 清单里被写成 lose_vitality 4 的普通效果，而不是费用。
func _vitality_payment_probe(h) -> void:
    var db := ContentDB.new()
    var loaded = db.load("mvp")
    if not Result.is_ok(loaded):
        h.check("mvp 清单加载成功", false, str(loaded))
        return
    h.check("K10 在 mvp 清单内启用", db.is_enabled(GameConstants.KIND_CARD, "K10"))
    h.check("[偏差探针] A08 定义存在（RB-04 需要它免除首次支付）", not db.definition(GameConstants.KIND_RELIC, "A08").is_empty(), "relics.json 只有 A01/A04")
    var engine = BattleEngine.new(db)
    var source = RandomSourceScript.new(0)
    var step = engine.begin({
        "battle_id": "Rtest#2",
        "node_id": "n1",
        "encounter_id": "N01",
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "vitality": 4,
        "max_vitality": 72,
        "cards": _deck("K10", 4) + _deck("K01", 6),
        "relics": [],
        "rng_state": source.export_state(),
    })
    if not _ok(h, "mvp 战斗 begin 成功（精力 4）", step):
        return
    var state = _state(step)
    var k10 := _to_hand(state, "K10")
    var face = engine.resolve_face(state, k10)
    if Result.is_ok(face):
        var effects: Array = face["data"].get("effects", [])
        if effects.size() > 0:
            h.eq("K10 第一段是 gain_focus：精力代价改走费用层", String(effects[0].get("op", "")), "gain_focus")
        h.eq("K10 的 CostQuote 带 4 点精力代价（升级 3）", int(BattleCardRules.cost_quote(db, state, face["data"]).get("vitality_cost", 0)), 4)
    var played = _play_id(engine, step, k10)
    h.check("[偏差探针] 精力 4 打 K10 应被拒（支付后不足 1）[RB-03/T03]", not Result.is_ok(played), "实际可打出，error=%s" % Result.error_code(played))
    if Result.is_ok(played):
        var after = _state(played)
        h.eq("[记录] K10 被当作普通失血：精力 4-4=0", after.player.vitality, 0)
        var outcome: Variant = played["data"]["outcome"]
        if outcome != null:
            h.eq("[记录] 主角精力归零直接判负", String(outcome["reason"]), GameConstants.REASON_VITALITY_DEPLETED)
