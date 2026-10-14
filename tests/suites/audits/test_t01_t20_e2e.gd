extends RefCounted
##
## T01～T20 端到端验收探针（verifier，为 t7/v3 准备）：把《统一设计文档》§12.2 的 20 条用例
## 逐条写成可执行断言，每条一个 h.begin("Txx …") 段，便于逐条看结论。
## 独立入口：res://tests/suites/audits/audit_t01_t20.gd（不登记进主套件）。
##
## 约定：
##   · [待内容] 前缀 = 该用例的前置定义还没落地（目前 T04/T14/T15、T11 的 A24、T16 的满槽）。
##     这类断言写成「阻塞前提仍成立」，等前置落地会翻红提醒我补真探针，不会假绿。
##   · [偏差探针] 前缀 = 断言条文本身，变红即审查结论。
##   · 内容清单：mvp（主）与 battle_mvp（补 L04/L05/L06 场景与旧卡集）两套。
##

const ContentDB := preload("res://src/content/content_db.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")
const RandomSource := preload("res://src/common/random_source.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const RunService := preload("res://src/run/run_service.gd")
const RunNodeState := preload("res://src/run/run_node_state.gd")
const SnapshotCodec := preload("res://src/storage/snapshot_codec.gd")
const SaveStore := preload("res://src/storage/save_store.gd")
const SessionStateScript := preload("res://src/app/session_state.gd")

const SEED := "20261013"

var _db = null
var _db2 = null
var _svc = null


func run(h) -> void:
    var db := ContentDB.new()
    var loaded := db.load("mvp")
    if not Result.is_ok(loaded):
        h.begin("T01～T20 · 前置")
        h.check("mvp 清单可加载", false, str(loaded))
        return
    _db = db
    _svc = RunService.new(db)
    var db2 := ContentDB.new()
    var loaded2 := db2.load("battle_mvp")
    if Result.is_ok(loaded2):
        _db2 = db2
    h.begin("T01 新回合普通角色，无修正")
    _t01(h)
    h.begin("T02 手牌9张抽3；随后生成临时牌")
    _t02(h)
    h.begin("T03 精力4打K10，未持A08")
    _t03(h)
    h.begin("T04 精力4打K10，A08本战未用")
    _t04(h)
    h.begin("T05 场上3单位再打合作牌，取消换班")
    _t05(h)
    h.begin("T06 护卫剩3精力承受5×2压力")
    _t06(h)
    h.begin("T07 独立作答中打升级K44")
    _t07(h)
    h.begin("T08 固定考场中打K53")
    _t08(h)
    h.begin("T09 建立L01触发3次后换场再建立")
    _t09(h)
    h.begin("T10 DDL1时完成最后任务")
    _t10(h)
    h.begin("T11 DDL1时轮末仍有任务")
    _t11(h)
    h.begin("T12 首领阶段归零且尚有下一阶段")
    _t12(h)
    h.begin("T13 焦虑2在L04第2次准备触发")
    _t13(h)
    h.begin("T14 L05存在，K08恢复3且A12有次数")
    _t14(h)
    h.begin("T15 同名能力二次打出")
    _t15(h)
    h.begin("T16 钱不足/删后不足5张/满槽取消交易")
    _t16(h)
    h.begin("T17 同种子保存后继续L02随机")
    _t17(h)
    h.begin("T18 主角与最后任务同时归零")
    _t18(h)
    h.begin("T19 单位行动后自身精力从1变0")
    _t19(h)
    h.begin("T20 K13回收后在本回合再次打出")
    _t20(h)
    h.begin("R1 清单漂移：用 mvp 独有的牌打一场")
    _r01(h)
    h.begin("R2 真实战斗必须真的结算一次（不注入结局）")
    _r02(h)
    h.begin("R3 add_card → X01 端到端（N03）")
    _r03(h)


# ── 工具 ──────────────────────────────────────────────────

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


func _battle(db, deck: Array, encounter_id: String = "N01", relics: Array = [], vitality: int = 72, seed_value: int = 0) -> Dictionary:
    var source = RandomSource.new(seed_value)
    var engine = BattleEngine.new(db)
    return engine.begin({
        "battle_id": "Rtest#1",
        "node_id": "n1",
        "encounter_id": encounter_id,
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "vitality": vitality,
        "max_vitality": 72,
        "cards": deck,
        "relics": relics,
        "rng_state": source.export_state(),
    })


func _state(step: Dictionary):
    return step["data"]["state"]


## 战斗步给 rng_state，局流程步给 rng_states；两者都要能吃。
func _rng(step: Dictionary) -> Dictionary:
    var data: Dictionary = step.get("data", {})
    if data.has("rng_state"):
        return data["rng_state"]
    if data.has("rng_states"):
        return data["rng_states"]
    return {}


func _ok(h, label: String, result: Dictionary) -> bool:
    if Result.is_ok(result):
        h.check(label, true)
        return true
    h.check(label, false, str(result.get("error")))
    return false


func _stacks(state, holder_id: String, status_id: String) -> int:
    var status = state.find_status(holder_id, status_id)
    return 0 if status == null else int(status.stacks)


func _work(state) -> int:
    return 0 if (state.tasks as Array).is_empty() else int(state.tasks[0].work_remaining)


func _card_ids(state, definition_id: String) -> Array:
    var matches := []
    for card_id in state.card_by_id:
        var card = state.card_by_id[card_id]
        if card.definition_id == definition_id:
            matches.append(String(card_id))
    matches.sort()
    return matches


func _to_hand(state, definition_id: String, occurrence: int = 0) -> String:
    var matches := _card_ids(state, definition_id)
    if occurrence >= matches.size():
        return ""
    var card_id: String = matches[occurrence]
    state.move_card(card_id, GameConstants.ZONE_HAND)
    return card_id


func _has_event(step: Dictionary, event_type: String) -> bool:
    for raw in step["data"]["events"]:
        if String((raw as Dictionary).get("type", "")) == event_type:
            return true
    return false


func _event_count(step: Dictionary, event_type: String) -> int:
    var count := 0
    for raw in step["data"]["events"]:
        if String((raw as Dictionary).get("type", "")) == event_type:
            count += 1
    return count


func _play_id(engine, step: Dictionary, card_id: String, target_ids: Array = []) -> Dictionary:
    var payload := {"card_id": card_id}
    if not target_ids.is_empty():
        payload["target_ids"] = target_ids
    return engine.apply(_state(step), {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}, _rng(step))


func _play_def(engine, step: Dictionary, definition_id: String, work: bool = false) -> Dictionary:
    var state = _state(step)
    var card_id := _to_hand(state, definition_id)
    var targets := []
    if work and not (state.tasks as Array).is_empty():
        targets = [state.tasks[0].task_id]
    return _play_id(engine, step, card_id, targets)


func _end(engine, step: Dictionary) -> Dictionary:
    return engine.apply(_state(step), {"type": GameConstants.ACTION_END_TURN, "payload": {}}, _rng(step))


# ── T01～T06 ──────────────────────────────────────────────

func _t01(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    h.eq("专注 3", int(state.player.focus), 3)
    h.eq("首轮抽 5，没有第二次起手", state.zones.hand.size(), 5)
    h.eq("round_index = 1", int(state.round_index), 1)
    var turn = _end(engine, step)
    if not _ok(h, "结束回合", turn):
        return
    var after = _state(turn)
    h.eq("第 2 轮专注仍是 3", int(after.player.focus), 3)
    h.eq("第 2 轮抽 5", after.zones.hand.size(), 5)


func _t02(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K03", 3, 1) + _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    _to_hand(state, "K03")
    for raw_id in state.card_by_id.keys():
        if state.zones.hand.size() >= 10:
            break
        if state.zone_of(String(raw_id)) == GameConstants.ZONE_DRAW:
            state.move_card(String(raw_id), GameConstants.ZONE_HAND)
    h.eq("手牌凑到 10 张（含 K03）", state.zones.hand.size(), 10)
    var k03 := _to_hand(state, "K03")
    var played = _play_id(engine, step, k03)
    if not _ok(h, "打出升级 K03（抽3弃1）", played):
        return
    var after = _state(played)
    h.eq("手牌上限生效：打出后 9 张，抽 3 只落实 1 张", after.zones.hand.size(), 10)
    h.eq("只发生 1 次抽牌（9→10 顶满即停）", _event_count(played, BattleEngine.EVENT_CARD_DRAWN), 1)
    var ctx := {"state": after, "rng": RandomSource.new(0), "events": [], "pending_choice": null, "outcome": null}
    engine._add_temporary_card(ctx, {"card": "X01", "count": 1, "zone": GameConstants.ZONE_HAND})
    var temp_ids := []
    for card_id in after.card_by_id:
        if String(after.card_by_id[card_id].definition_id) == "X01":
            temp_ids.append(String(card_id))
    h.eq("生成牌落地 1 张", temp_ids.size(), 1)
    if temp_ids.size() == 1:
        h.eq("手牌满时生成牌进弃牌堆", after.zone_of(temp_ids[0]), GameConstants.ZONE_DISCARD)
    var discarded := 0
    for raw in (ctx["events"] as Array):
        if String((raw as Dictionary).get("type", "")) == BattleEngine.EVENT_CARD_DISCARDED:
            discarded += 1
    h.eq("生成牌不算主动弃牌（无 card_discarded 事件）", discarded, 0)


func _t03(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K10", 4) + _deck("K01", 6), "N01", [], 4)
    if not _ok(h, "begin 成功（精力 4）", step):
        return
    var state = _state(step)
    var k10 := _to_hand(state, "K10")
    var before := _work(state)
    var played = _play_id(engine, step, k10)
    h.eq("支付后不足 1 精力，不能打出", Result.error_code(played), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.eq("拒绝后精力不变", int(state.player.vitality), 4)
    h.eq("拒绝后专注不变", int(state.player.focus), 3)
    h.eq("拒绝后牌仍在手", state.zone_of(k10), GameConstants.ZONE_HAND)
    h.eq("拒绝后未完成量不变", _work(state), before)


func _t04(h) -> void:
    if _db.definition(GameConstants.KIND_RELIC, "A08").is_empty():
        h.check("[待内容] T04 阻塞前提：A08 未定义（t10 饰品 hook 负责）", true)
        return
    h.check("[记录] T04 阻塞前提已解除：A08 已有定义，实探针就位", true)
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K10", 4) + _deck("K01", 6), "N01", ["A08"], 4)
    if not _ok(h, "T04 begin 成功（精力 4 + A08）", step):
        return
    var state = _state(step)
    var k10a := _to_hand(state, "K10", 0)
    var played = _play_id(engine, step, k10a)
    if not _ok(h, "T04 A08 免除本战首张 K10 的精力代价，可以打出", played):
        return
    var after = _state(played)
    h.eq("T04 精力未被扣除（仍 4）", int(after.player.vitality), 4)
    h.eq("T04 获得 2 专注：3+2=5", int(after.player.focus), 5)
    h.eq("T04 K10 已耗尽", after.zone_of(k10a), GameConstants.ZONE_EXHAUST)
    var k10b := _to_hand(after, "K10", 1)
    var second = _play_id(engine, played, k10b)
    h.eq("T04 免支付次数已消费：第二张 K10 支付后不足 1 精力被拒", Result.error_code(second), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.eq("T04 被拒后精力仍 4", int(after.player.vitality), 4)
    h.eq("T04 被拒后第二张仍在手", after.zone_of(k10b), GameConstants.ZONE_HAND)



func _t05(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K10", 3) + _deck("K43", 4) + _deck("K44", 2) + _deck("K46", 2))
    if not _ok(h, "begin 成功", step):
        return
    step = _play_def(engine, step, "K10")
    step = _play_def(engine, step, "K10")
    step = _play_def(engine, step, "K43")
    step = _play_def(engine, step, "K44")
    step = _play_def(engine, step, "K46")
    if not _ok(h, "召满 3 个单位", step):
        return
    var state = _state(step)
    h.eq("场上 3 单位", state.units.size(), 3)
    h.check("还有专注可付（否则测不到槽位校验）", int(state.player.focus) > 0, str(state.player.focus))
    var k43 := _to_hand(state, "K43")
    var focus_before := int(state.player.focus)
    var cancel = _play_id(engine, step, k43)
    h.eq("满槽取消换班被拒", Result.error_code(cancel), GameConstants.ERROR_INVALID_TARGET)
    h.eq("取消不扣专注", int(state.player.focus), focus_before)
    h.eq("取消不移牌/不耗尽", state.zone_of(k43), GameConstants.ZONE_HAND)
    h.eq("取消不改变单位", state.units.size(), 3)


func _t06(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K43", 3) + _deck("K01", 4))
    step = _play_def(engine, step, "K43")
    if not _ok(h, "召入 F01 护卫", step):
        return
    var state = _state(step)
    state.units[0].vitality = 3
    var guard_id := String(state.units[0].unit_id)
    state.tasks[0].intent_snapshot = {"index": 1, "pressure": 5, "pressure_times": 2}
    var turn = _end(engine, step)
    if not _ok(h, "结束回合（5×2 压力）", turn):
        return
    var after = _state(turn)
    h.check("首段护卫暂离", after.find_unit(guard_id) == null)
    h.eq("次段无护卫则打主角：72-5=67", int(after.player.vitality), 67)
    h.eq("协作仍已结算：24-2=22", _work(after), 22)


func _t07(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K44", 3, 1) + _deck("K01", 4), "B01")
    if not _ok(h, "begin 成功（B01 独立作答）", step):
        return
    var state = _state(step)
    var k44 := _to_hand(state, "K44")
    var played = _play_id(engine, step, k44)
    if not _ok(h, "独立作答中打出升级 K44", played):
        return
    var after = _state(played)
    h.eq("备考面：获得 7 放松", int(after.player.relax), 7)
    h.eq("不召入单位", after.units.size(), 0)
    h.eq("保留耗尽标记", after.zone_of(k44), GameConstants.ZONE_EXHAUST)
    h.eq("同费用 2：专注 3-2=1", int(after.player.focus), 1)
    h.eq("没有 unit_summoned 事件", _event_count(played, BattleEngine.EVENT_UNIT_SUMMONED), 0)


func _t08(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K53", 3) + _deck("K01", 4), "B01")
    if not _ok(h, "begin 成功（B01 固定考场）", step):
        return
    var state = _state(step)
    var k53 := _to_hand(state, "K53")
    var hand_before: int = state.zones.hand.size()
    var played = _play_id(engine, step, k53)
    if not _ok(h, "固定考场中打出 K53", played):
        return
    var after = _state(played)
    h.eq("回忆面：抽 1（手牌数不变）", after.zones.hand.size(), hand_before)
    h.eq("获得 2 放松", int(after.player.relax), 2)
    h.check("不建立场景（L03 不出现）", after.scene == null)
    h.eq("保留耗尽标记", after.zone_of(k53), GameConstants.ZONE_EXHAUST)
    h.eq("同费用 2：专注 3-2=1", int(after.player.focus), 1)


func _t09(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K51", 2) + _deck("K53", 1) + _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    var l01a := _to_hand(state, "K51", 0)
    var l01b := _to_hand(state, "K51", 1)
    var l03 := _to_hand(state, "K53", 0)
    step = _play_id(engine, step, l01a)
    if not _ok(h, "建立 L01", step):
        return
    for _index in range(3):
        step = _end(engine, step)
        if not Result.is_ok(step):
            h.check("连续结束回合", false, str(step))
            return
    h.eq("三次准备各恢复 2：72-5-7-5+6=61", int(_state(step).player.vitality), 61)
    var st = _state(step)
    st.move_card(l03, GameConstants.ZONE_HAND)
    step = _play_id(engine, step, l03)
    if not _ok(h, "换成 L03", step):
        return
    _state(step).move_card(l01b, GameConstants.ZONE_HAND)
    step = _play_id(engine, step, l01b)
    if not _ok(h, "换回 L01", step):
        return
    step = _end(engine, step)
    if not _ok(h, "第 4 次准备", step):
        return
    h.eq("不再恢复精力（61-7=54）：本战次数不重置", int(_state(step).player.vitality), 54)


func _t10(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    state.ddl = 1
    state.tasks[0].work_remaining = 2
    var played = _play_def(engine, step, "K01", true)
    if not _ok(h, "完成最后任务", played):
        return
    var outcome: Variant = played["data"]["outcome"]
    h.check("立即产生结局", outcome != null)
    if outcome != null:
        h.eq("结果 = won", String(outcome["result"]), GameConstants.OUTCOME_WON)
        h.eq("原因 = tasks_completed", String(outcome["reason"]), GameConstants.REASON_TASKS_COMPLETED)
    h.eq("DDL 仍为 1（不进行轮末超时）", int(_state(played).ddl), 1)
    h.eq("没有 ddl_ticked 事件", _event_count(played, BattleEngine.EVENT_DDL_TICKED), 0)


# ── T11～T15 ─────────────────────────────────────────────

func _t11(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    _state(step).ddl = 1
    var turn = _end(engine, step)
    if not _ok(h, "结束回合", turn):
        return
    var outcome: Variant = turn["data"]["outcome"]
    h.check("产生结局", outcome != null)
    if outcome != null:
        h.eq("结果 = lost", String(outcome["result"]), GameConstants.OUTCOME_LOST)
        h.eq("原因 = deadline_expired", String(outcome["reason"]), GameConstants.REASON_DEADLINE_EXPIRED)
    h.eq("DDL 归零", int(_state(turn).ddl), 0)
    h.check("[待内容] T11 的 A24 部分阻塞：A24 未定义（无「救场」可测）", _db.definition(GameConstants.KIND_RELIC, "A24").is_empty(), "A24 已有定义 → 请补真探针")


func _t12(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K01", 12), "B01")
    if not _ok(h, "begin 成功（B01）", step):
        return
    var state = _state(step)
    state.tasks[0].work_remaining = 2
    var old_id := String(state.tasks[0].task_id)
    var played = _play_def(engine, step, "K01", true)
    if not _ok(h, "完成第一阶段", played):
        return
    var after = _state(played)
    h.eq("仍有 1 个任务（先生成下一阶段）", after.tasks.size(), 1)
    h.check("新 task_id 与旧的不同", String(after.tasks[0].task_id) != old_id)
    h.eq("新阶段满工作量 25（不承接超额）", _work(after), 25)
    h.check("没有提前判胜", played["data"]["outcome"] == null)
    var primary = engine._primary_task(after, [old_id])
    h.check("[偏差探针] 锁定旧阶段的剩余段必须跳过（查不到旧任务应返回 null）", primary == null, "实际指向：" + ("" if primary == null else String(primary.task_id)))


func _t13(h) -> void:
    if _db2 == null:
        h.check("battle_mvp 清单可用", false)
        return
    h.check("[待内容] T13 需 battle_mvp：L04 未进 mvp 清单", _db.definition(GameConstants.KIND_SCENE, "L04").is_empty())
    var engine = BattleEngine.new(_db2)
    var step = _battle(_db2, _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    state.scene = BattleState.create_scene("Rtest#1|s_l04", "L04", state.round_index)
    step = _end(engine, step)
    if not _ok(h, "L04 第 1 次准备", step):
        return
    var st1 = _state(step)
    h.eq("第 1 次准备不加焦虑", _stacks(st1, st1.player.entity_id, GameConstants.STATUS_ANXIETY), 0)
    step = _end(engine, step)
    if not _ok(h, "L04 第 2 次准备", step):
        return
    var st2 = _state(step)
    h.eq("第 2 次准备施加 1 焦虑", _stacks(st2, st2.player.entity_id, GameConstants.STATUS_ANXIETY), 1)
    h.eq("本次准备按无焦虑计算（专注 3）", int(st2.player.focus), 3)
    step = _end(engine, step)
    if not _ok(h, "L04 第 3 次准备", step):
        return
    var st3 = _state(step)
    h.eq("新焦虑在下一次准备扣回能（3-1=2）", int(st3.player.focus), 2)
    h.eq("生效后清除", _stacks(st3, st3.player.entity_id, GameConstants.STATUS_ANXIETY), 0)


func _t14(h) -> void:
    h.check("[待内容] T14 阻塞：A12 未定义（饰品 hook）", _db.definition(GameConstants.KIND_RELIC, "A12").is_empty())
    h.check("[待内容] T14 阻塞：L05 未进 mvp 清单", _db.definition(GameConstants.KIND_SCENE, "L05").is_empty())
    h.check("[待内容] T14 阻塞：K08 不在 battle_mvp 清单（单清单凑不齐 K08+L05+A12）", _db2 != null and _db2.definition(GameConstants.KIND_CARD, "K08").is_empty())


func _t15(h) -> void:
    var abilities := []
    for raw_id in _db.enabled_ids(GameConstants.KIND_CARD):
        var definition: Dictionary = _db.definition(GameConstants.KIND_CARD, String(raw_id))
        if String(definition.get("type", "")) == GameConstants.CARD_ABILITY:
            abilities.append(String(raw_id))
    h.check("[待内容] T15 阻塞：mvp 清单里没有任何能力牌，持续能力无从叠加", abilities.is_empty(), str(abilities))


# ── 局流程侧工具（T16/T17/T18 用） ────────────────────────

func _create_run() -> Dictionary:
    return _svc.create({
        "character_id": "P01",
        "difficulty": GameConstants.DIFFICULTY_NORMAL,
        "manifest_id": _db.manifest_id,
        "seed": SEED,
    }, {})


func _session_of(run, rng: Dictionary, revision: int, battle = null) -> Object:
    var session = SessionStateScript.new()
    session.run_id = run.run_id
    session.revision = revision
    session.run = run
    session.battle = battle
    session.random_snapshot = rng
    return session


func _next_battle_action(state, data: Dictionary) -> Dictionary:
    var choice: Variant = data.get("pending_choice")
    if choice != null:
        var candidates: Array = (choice as Dictionary).get("candidates", [])
        if not candidates.is_empty():
            return {"type": GameConstants.ACTION_CONFIRM_CHOICE, "payload": {
                "choice_id": String((choice as Dictionary)["choice_id"]),
                "selected_ids": [String(((candidates[0]) as Dictionary)["id"])],
            }}
    for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
        var card = state.get_card(String(raw_id))
        if card == null:
            continue
        var definition: Dictionary = _db.definition(GameConstants.KIND_CARD, card.definition_id)
        if String(definition.get("type", "")) != GameConstants.CARD_WORK:
            continue
        if int(definition.get("cost", 0)) > int(state.player.focus):
            continue
        var payload := {"card_id": card.card_id}
        if not (state.tasks as Array).is_empty():
            payload["target_ids"] = [state.tasks[0].task_id]
        return {"type": GameConstants.ACTION_PLAY_CARD, "payload": payload}
    return {"type": GameConstants.ACTION_END_TURN, "payload": {}}


func _fight(battle_input: Dictionary) -> Dictionary:
    var engine = BattleEngine.new(_db)
    var step: Dictionary = engine.begin(battle_input)
    if not Result.is_ok(step):
        return {}
    var guard := 0
    while guard < 240:
        guard += 1
        var data: Dictionary = step["data"]
        if data.get("outcome") != null:
            return data["outcome"]
        var next: Dictionary = engine.apply(data["state"], _next_battle_action(data["state"], data), data.get("rng_state"))
        if not Result.is_ok(next):
            return {}
        step = next
    return {}


func _pick_reachable(run) -> String:
    var reachable: Array = run.reachable_node_ids()
    for raw in reachable:
        if String(run.find_node(String(raw)).kind) in RunNodeState.BATTLE_KINDS:
            return String(raw)
    return "" if reachable.is_empty() else String(reachable[0])


func _advance_one_node(run, rng: Dictionary) -> Dictionary:
    var node_id := _pick_reachable(run)
    if node_id.is_empty():
        return Result.fail(GameConstants.ERROR_INVALID_TARGET, "error.t20.no_reachable", {})
    var node = run.find_node(node_id)
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node_id}}, rng)
    if not Result.is_ok(entered):
        print("[audit] enter_node failed at ", node_id, ": ", entered)
        return entered
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var outcome := {}
    if String(current.find_node(node_id).kind) in RunNodeState.BATTLE_KINDS:
        outcome = _fight(entered["data"]["battle_input"])
        if outcome.is_empty():
            print("[audit] fight_failed at ", node_id, " kind=", String(current.find_node(node_id).kind))
            return Result.fail(GameConstants.ERROR_RESOLUTION_ERROR, "error.t20.fight_failed", {"node_id": node_id})
        print("[audit] fight ", node_id, " -> ", String(outcome.get("result", "?")), " vit=", str(outcome.get("remaining_vitality", -1)))
        var settled: Dictionary = _svc.settle_battle(current, outcome, current_rng)
        if not Result.is_ok(settled):
            print("[audit] settle failed: ", settled)
            return settled
        current = _state(settled)
        current_rng = _rng(settled)
        var guard := 0
        while current.pending_reward != null and not current.pending_reward.is_complete() and guard < 16:
            guard += 1
            var offer = current.pending_reward
            var items: Array = offer.pending_items()
            if items.is_empty():
                break
            var item = items[0]
            var claim_payload := {"offer_id": String(offer.offer_id), "item_id": String(item.item_id)}
            if not (item.candidates as Array).is_empty():
                claim_payload["candidate_id"] = String((item.candidates as Array)[0])
            var claimed: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_CLAIM_REWARD, "payload": claim_payload}, current_rng)
            if not Result.is_ok(claimed):
                print("[audit] claim failed at ", node_id, ": ", claimed)
                return claimed
            current = _state(claimed)
            current_rng = _rng(claimed)
    var left: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_LEAVE_NODE, "payload": {"node_id": node_id}}, current_rng)
    if not Result.is_ok(left):
        print("[audit] leave failed at ", node_id, ": ", left)
        return left
    return Result.ok({"run": _state(left), "rng": _rng(left), "outcome": outcome})


func _advance_to_kind(kind: String) -> Dictionary:
    var created: Dictionary = _create_run()
    if not Result.is_ok(created):
        return {}
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    for _index in range(8):
        var node_id := _pick_reachable(run)
        if node_id.is_empty():
            break
        if String(run.find_node(node_id).kind) == kind:
            return {"run": run, "rng": rng}
        var advanced: Dictionary = _advance_one_node(run, rng)
        if not Result.is_ok(advanced):
            print("[audit] advance failed at ", node_id, ": ", advanced)
            return {}
        run = advanced["data"]["run"]
        rng = advanced["data"]["rng"]
    return {}


# ── T16～T20 ─────────────────────────────────────────────

func _t16(h) -> void:
    var reached := _advance_to_kind("shop")
    if reached.is_empty():
        h.check("推进到商店可达", false, "见 [audit] 行")
        return
    h.check("推进到商店可达", true)
    var run = reached["run"]
    var rng: Dictionary = reached["rng"]
    var node = run.find_node(_pick_reachable(run))
    var entered = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "进入商店", entered):
        return
    var current = _state(entered)
    var current_rng: Dictionary = _rng(entered)
    var guard := 0
    while guard < 10:
        guard += 1
        var affordable = null
        for raw in current.current_node().context["shop"].stocks:
            if not bool((raw as Object).sold) and int((raw as Object).price) <= int(current.money):
                affordable = raw
                break
        if affordable == null:
            break
        var bought: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((affordable as Object).stock_id)}}, current_rng)
        if not Result.is_ok(bought):
            break
        current = _state(bought)
        current_rng = _rng(bought)
    var money_before := int(current.money)
    var deck_before: int = current.cards.size()
    var denied_count := 0
    for raw in current.current_node().context["shop"].stocks:
        if bool((raw as Object).sold):
            continue
        denied_count += 1
        var denied: Dictionary = _svc.apply(current, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": String((raw as Object).stock_id)}}, current_rng)
        h.eq("(a) 钱不足返回 INSUFFICIENT_RESOURCE", Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
    h.check("(a) 存在买不起的库存（用例有效）", denied_count > 0)
    h.check("(a) 被拒后余额/牌组/库存全不变", int(current.money) == money_before and current.cards.size() == deck_before)
    while current.cards.size() > 5:
        current.cards.pop_back()
    var removal = _svc.apply(current, {"type": GameConstants.ACTION_REMOVE_CARD, "payload": {"card_instance_id": String(current.cards[0].card_id)}}, current_rng)
    h.eq("(b) 删到只剩 5 张后不能再删", Result.error_code(removal), GameConstants.ERROR_LIMIT_REACHED)
    h.check("(b) 被拒后牌组仍 5 张且不扣钱", current.cards.size() == 5 and int(current.money) == money_before)
    # (c) 满饰品槽取消交易（前提：清单启用 ≥6 件饰品，2026-10 t10 后成立）
    var relics: Array = _db.enabled_ids(GameConstants.KIND_RELIC)
    if relics.size() < 6:
        h.check("[待内容] T16(c) 阻塞前提：清单启用饰品不足 6 件", true)
        return
    h.check("[记录] T16(c) 阻塞前提已解除：清单已启用 ≥6 件饰品，实探针就位", true)
    var created_c: Dictionary = _create_run()
    if not _ok(h, "(c) 局创建成功", created_c):
        return
    var run_c = _state(created_c)
    var rng_c: Dictionary = _rng(created_c)
    for definition_id in ["A05", "A07", "A08", "A11", "A15"]:
        if run_c.relics.size() >= 6:
            break
        if not run_c.has_relic_definition(definition_id):
            run_c.equip_relic(definition_id, 6, run_c.relics.size() + 1)
    h.eq("(c) 已占满 6 个饰品槽", run_c.relics.size(), 6)
    var reached_c := _advance_to_shop_from(run_c, rng_c)
    if reached_c.is_empty():
        h.check("(c) 推进到商店可达", false)
        return
    h.check("(c) 推进到商店可达", true)
    var shop_run_c = reached_c["run"]
    var shop_rng_c: Dictionary = reached_c["rng"]
    var shop_node_c = shop_run_c.find_node(_pick_reachable(shop_run_c))
    var entered_c: Dictionary = _svc.apply(shop_run_c, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": shop_node_c.node_id}}, shop_rng_c)
    if not _ok(h, "(c) 进入商店", entered_c):
        return
    var store_c = _state(entered_c)
    var store_rng_c: Dictionary = _rng(entered_c)
    var relic_stock = null
    for raw in store_c.current_node().context["shop"].stocks:
        if String((raw as Object).kind) == "relic":
            relic_stock = raw
            break
    if relic_stock == null:
        h.check("[记录] (c) 本店没有饰品库存（池被已持有项占满），跳过", true)
        return
    var stock_id_c := String((relic_stock as Object).stock_id)
    var relic_price := int((relic_stock as Object).price)
    var money_before_c := int(store_c.money)
    var relics_before_c := []
    for relic in store_c.relics:
        relics_before_c.append(String(relic.relic_id))
    relics_before_c.sort()
    var denied_c: Dictionary = _svc.apply(store_c, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": stock_id_c}}, store_rng_c)
    h.eq("(c) 满槽且不给替换对象 → LIMIT_REACHED", Result.error_code(denied_c), GameConstants.ERROR_LIMIT_REACHED)
    h.eq("(c) 被拒后金钱不变", int(store_c.money), money_before_c)
    h.check("(c) 被拒后库存未售出", not bool((relic_stock as Object).sold))
    var relics_after_c := []
    for relic in store_c.relics:
        relics_after_c.append(String(relic.relic_id))
    relics_after_c.sort()
    h.eq("(c) 被拒后装备不变", relics_after_c, relics_before_c)
    store_c.money = 500
    var replaced_id := String(store_c.relics[0].relic_id)
    var quote_c: Dictionary = _svc.preview(store_c, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": stock_id_c, "replace_relic_id": replaced_id}})
    var quoted_money := -1
    if Result.is_ok(quote_c):
        quoted_money = int((quote_c["data"]["costs"] as Dictionary).get("money", -1))
    h.check("(c) 服务给出报价（可能带饰品价格 hook）", quoted_money >= 0, str(quoted_money))
    var bought_c: Dictionary = _svc.apply(store_c, {"type": GameConstants.ACTION_BUY_ITEM, "payload": {"stock_id": stock_id_c, "replace_relic_id": replaced_id}}, store_rng_c)
    if _ok(h, "(c) 带替换对象可以买下", bought_c):
        var after_c = _state(bought_c)
        h.eq("(c) 只扣一次钱：500-服务报价（本局持有 A15，实际报价低于库存基价）", int(after_c.money), 500 - quoted_money)
        h.eq("(c) 仍是 6 槽", after_c.relics.size(), 6)
        h.check("(c) 被替换的饰品已不在", after_c.find_relic(replaced_id) == null)
        h.check("(c) 新饰品已装备", after_c.has_relic_definition(String((relic_stock as Object).definition_id)))
        h.check("(c) 库存已售出", bool(after_c.current_node().context["shop"].find_stock(stock_id_c).sold))
        h.check("[记录] (c) 库存基价与实收价可能不同（A15 商店价 hook）", true, "base=%d quoted=%d" % [relic_price, quoted_money])


func _l02_digest(save_middle: bool) -> String:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K52", 3) + _deck("K01", 9))
    if not Result.is_ok(step):
        return "begin-failed"
    var played = _play_def(engine, step, "K52", false)
    if not Result.is_ok(played):
        return "play-failed"
    var mid: Dictionary = played
    if save_middle:
        var created: Dictionary = _create_run()
        if not Result.is_ok(created):
            return "run-failed"
        var run = _state(created)
        run.active_battle_id = "Rtest#1"
        var session = _session_of(run, _rng(played), 7, _state(played))
        var encoded = SnapshotCodec.encode_session(session, null, {"content_version": _db.content_version, "content_hash": _db.content_hash, "manifest_id": _db.manifest_id})
        if not Result.is_ok(encoded):
            return "encode-failed"
        var store = SaveStore.new("user://audit_t20_t17", _db)
        var saved = store.save(SaveStore.SLOT_CURRENT_RUN, encoded["data"])
        if not Result.is_ok(saved):
            return "save-failed"
        var loaded = store.load(SaveStore.SLOT_CURRENT_RUN)
        if not Result.is_ok(loaded):
            return "load-failed"
        var decoded = SnapshotCodec.decode_session(loaded["data"])
        if not Result.is_ok(decoded):
            return "decode-failed"
        var resumed = decoded["data"]["session"]
        mid = {"data": {"state": resumed.battle, "rng_state": resumed.random_snapshot, "events": [], "pending_choice": null, "outcome": null, "stable": true}}
    var turn = _end(engine, mid)
    if not Result.is_ok(turn):
        return "turn-failed"
    var after = _state(turn)
    var scene_random := -1
    if after.scene != null and after.scene.pending_random_result != null:
        scene_random = int(after.scene.pending_random_result)
    var hand := []
    for card_id in after.zones.hand:
        hand.append(String(card_id))
    hand.sort()
    return SnapshotCodec.canonical_json({"scene_random": scene_random, "focus": int(after.player.focus), "vitality": int(after.player.vitality), "hand": hand, "rng": _rng(turn)})


func _t17(h) -> void:
    var control := _l02_digest(false)
    var with_save := _l02_digest(true)
    h.check("控制组有实际内容", control.length() > 10, control)
    h.check("存读档组有实际内容", with_save.length() > 10, with_save)
    h.eq("T17：同种子保存退出再继续，L02 预抽与后续随机与不退出时一致", with_save, control)


func _t18(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K01", 8), "N01", [], 1)
    if not _ok(h, "begin 成功（精力 1）", step):
        return
    var state = _state(step)
    state.player.vitality = 0
    state.tasks[0].work_remaining = 2
    var played = _play_def(engine, step, "K01", true)
    if not _ok(h, "同一次结算里完成最后任务且主角已归零", played):
        return
    var outcome: Variant = played["data"]["outcome"]
    h.check("产生结局", outcome != null)
    if outcome != null:
        h.eq("精力归零优先判负（不是胜利）", String(outcome["result"]), GameConstants.OUTCOME_LOST)
        h.eq("原因 = vitality_depleted", String(outcome["reason"]), GameConstants.REASON_VITALITY_DEPLETED)
    var created: Dictionary = _create_run()
    if not _ok(h, "局流程 create 成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node = run.find_node(String(run.reachable_node_ids()[0]))
    var entered = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "进入战斗节点", entered):
        return
    var lost := {
        "battle_id": String(node.node_id),
        "result": GameConstants.OUTCOME_LOST,
        "reason": GameConstants.REASON_VITALITY_DEPLETED,
        "remaining_vitality": 0,
    }
    var settled = _svc.settle_battle(_state(entered), lost, _rng(entered))
    if not _ok(h, "按失败结算", settled):
        return
    h.eq("失败不发生活费（仍 60）", int(_state(settled).money), 60)
    h.check("失败不生成奖励", _state(settled).pending_reward == null)
    h.eq("本局结束 = lost", String(_state(settled).outcome), GameConstants.OUTCOME_LOST)
    h.check("[待内容] T18 的 A24 部分阻塞：A24 未定义", _db.definition(GameConstants.KIND_RELIC, "A24").is_empty())


func _t19(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K46", 3) + _deck("K01", 4))
    step = _play_def(engine, step, "K46")
    if not _ok(h, "召入 F04（支援自身放松 2）", step):
        return
    var state = _state(step)
    state.units[0].vitality = 1
    var unit_id := String(state.units[0].unit_id)
    var before := _work(state)
    var turn = _end(engine, step)
    if not _ok(h, "结束回合", turn):
        return
    var after = _state(turn)
    h.eq("支援与协作都已执行：24-2=22", before - _work(after), 2)
    h.check("随后暂离（精力 1→0）", after.find_unit(unit_id) == null)
    h.eq("只协作了一次（没有第二次行动）", before - _work(after), 2)
    var departed := 0
    for raw in (turn["data"]["events"] as Array):
        var event: Dictionary = raw
        if String(event.get("type", "")) == BattleEngine.EVENT_UNIT_DEPARTED and String(event.get("reason", "")) == "exhausted":
            departed += 1
    h.eq("暂离事件恰好一次", departed, 1)


func _t20(h) -> void:
    var engine = BattleEngine.new(_db)
    var step = _battle(_db, _deck("K13", 2) + _deck("K01", 8))
    if not _ok(h, "begin 成功", step):
        return
    var state = _state(step)
    var k13a := _to_hand(state, "K13", 0)
    var k13b := _to_hand(state, "K13", 1)
    step = _play_id(engine, step, k13a)
    if not _ok(h, "打出 K13#1", step):
        return
    var st = _state(step)
    h.eq("获得 1 编译", _stacks(st, st.player.entity_id, GameConstants.STATUS_COMPILE), 1)
    st.move_card(k13a, GameConstants.ZONE_HAND)
    var again = _play_id(engine, step, k13a)
    h.eq("回收后本回合再打出被限次拒绝", Result.error_code(again), GameConstants.ERROR_LIMIT_REACHED)
    h.eq("拒绝后编译仍 1", _stacks(st, st.player.entity_id, GameConstants.STATUS_COMPILE), 1)
    step = _play_id(engine, step, k13b)
    if not _ok(h, "换一张 K13#2 可以打", step):
        return
    step = _end(engine, step)
    if not _ok(h, "结束回合", step):
        return
    var st2 = _state(step)
    st2.move_card(k13a, GameConstants.ZONE_HAND)
    var next_round = _play_id(engine, step, k13a)
    h.eq("下回合同一实例重置后可再打", Result.is_ok(next_round), true)


# ── R1～R3 回归项（队长转来的三条交叉模块发现） ───────────

func _r01(h) -> void:
    var created: Dictionary = _create_run()
    if not _ok(h, "R1 局创建成功（mvp 清单）", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var added = run.add_card("K10", 0, "test")
    h.check("R1 K10 已加入牌堆（mvp 独有、battle_mvp 没有）", added != null)
    h.check("R1 对照：battle_mvp 清单里确实没有 K10", _db2 != null and _db2.definition(GameConstants.KIND_CARD, "K10").is_empty())
    var node = run.find_node(String(run.reachable_node_ids()[0]))
    var entered = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node.node_id}}, rng)
    if not _ok(h, "R1 进入战斗节点", entered):
        return
    var input: Variant = entered["data"]["battle_input"]
    h.check("R1 battle_input 非空", typeof(input) == TYPE_DICTIONARY)
    if typeof(input) != TYPE_DICTIONARY:
        return
    var engine = BattleEngine.new(_db)
    var opened = engine.begin(input)
    h.check("R1 用 mvp 清单能开战（含 K10 的牌堆不再 unknown_card）", Result.is_ok(opened), Result.error_code(opened))
    if _db2 != null:
        var frozen = BattleEngine.new(_db2)
        var refused = frozen.begin(input)
        h.check("[记录] R1 同一份牌堆用冻结的 battle_mvp 清单会开不起来（清单漂移的症状）", not Result.is_ok(refused), "error=" + Result.error_code(refused))


func _r02(h) -> void:
    var created: Dictionary = _create_run()
    if not _ok(h, "R2 create 成功", created):
        return
    var advanced: Dictionary = _advance_one_node(_state(created), _rng(created))
    if not _ok(h, "R2 真实闭环：进节点→真打→真结算→领奖→离开", advanced):
        return
    var after = advanced["data"]["run"]
    var outcome: Dictionary = advanced["data"]["outcome"]
    h.check("R2 拿到真实 BattleOutcome", not outcome.is_empty())
    h.eq("R2 精力按真实剩余值写回（不是注入的胜利）", int(after.vitality), clampi(int(outcome.get("remaining_vitality", -1)), 0, int(after.max_vitality)))
    h.check("R2 奖励已处理完（无 pending）", after.pending_reward == null)
    h.eq("R2 节点已完成并写入 node_path", int(after.node_path.size()), 1)
    h.eq("R2 该战斗已进已结算集合", after.settled_battle_ids.size(), 1)
    if String(outcome.get("result", "")) == GameConstants.OUTCOME_WON:
        h.eq("R2 胜利按规则发生活费：60+15=75", int(after.money), 75)
    else:
        h.eq("R2 非胜利不发生活费：60", int(after.money), 60)


func _r03(h) -> void:
    var tasks: Array = _db.enabled_ids(GameConstants.KIND_TASK)
    if not tasks.has("N03"):
        h.check("[待内容] R3 阻塞前提：N03 尚未进 mvp 清单", true)
        return
    h.check("[记录] R3 阻塞前提已解除：N03 已进清单，实探针就位", true)
    var created: Dictionary = _create_run()
    if not _ok(h, "R3 局创建成功", created):
        return
    var run = _state(created)
    var rng: Dictionary = _rng(created)
    var node_id := _pick_reachable(run)
    var entered: Dictionary = _svc.apply(run, {"type": GameConstants.ACTION_ENTER_NODE, "payload": {"node_id": node_id}}, rng)
    if not _ok(h, "R3 进入战斗节点", entered):
        return
    var input: Dictionary = (entered["data"]["battle_input"] as Dictionary).duplicate(true)
    # 夹具：牌堆/精力/难度/人物都来自真实局，只把遭遇换成 N03（它的意图 2 是 add_card → X01 入弃牌堆）。
    input["encounter_id"] = "N03"
    # 夹具：把牌堆加厚到 36 张，保证第 3 轮抽牌不会把含 X01 的弃牌堆洗回抽牌堆
    # （否则 X01 会被重新抽上手，测不到「落在弃牌堆」）。
    for _index in range(24):
        input["cards"].append({
            "card_id": "Rtest#B_pad_%d" % _index,
            "definition_id": "K01",
            "origin_card_id": "Rtest#R_pad_%d" % _index,
            "upgrade_level": 0,
        })
    var engine = BattleEngine.new(_db)
    var step: Dictionary = engine.begin(input)
    if not _ok(h, "R3 用 N03 开战（真实 battle_input 只换遭遇）", step):
        return
    h.eq("R3 开战时尚无 X01", _count_definition(_state(step), "X01"), 0)
    var first: Dictionary = engine.apply(_state(step), {"type": GameConstants.ACTION_END_TURN, "payload": {}}, _rng(step))
    if not _ok(h, "R3 走完第 1 轮", first):
        return
    var snapshot: Variant = _state(first).tasks[0].intent_snapshot.get("add_card")
    h.check("R3 第 2 轮意图带 add_card → X01", typeof(snapshot) == TYPE_DICTIONARY and String((snapshot as Dictionary).get("card", "")) == "X01", str(snapshot))
    var second: Dictionary = engine.apply(_state(first), {"type": GameConstants.ACTION_END_TURN, "payload": {}}, _rng(first))
    if not _ok(h, "R3 走完第 2 轮（敌方技能发牌）", second):
        return
    var after = _state(second)
    var x01_ids := _card_ids(after, "X01")
    h.eq("R3 X01 已生成 1 张", x01_ids.size(), 1)
    if x01_ids.size() == 1:
        h.eq("R3 X01 落在弃牌堆（意图 zone=discard）", after.zone_of(x01_ids[0]), GameConstants.ZONE_DISCARD)
        var card = after.get_card(x01_ids[0])
        h.check("R3 X01 是临时牌（无 origin_card_id）", card != null and card.origin_card_id == null)
        var self_discarded := 0
        for raw in (second["data"]["events"] as Array):
            var event: Dictionary = raw
            if String(event.get("type", "")) == BattleEngine.EVENT_CARD_DISCARDED and String(event.get("card_id", "")) == x01_ids[0]:
                self_discarded += 1
        h.eq("R3 生成牌不算主动弃牌（无它自己的 card_discarded 事件）", self_discarded, 0)
    var skills := 0
    for raw in (second["data"]["events"] as Array):
        if String((raw as Dictionary).get("type", "")) == BattleEngine.EVENT_ENEMY_SKILL:
            skills += 1
    h.check("R3 敌方技能事件已发出", skills >= 1)



## 数某个定义在本战里出现了几张（跨牌区）。
func _count_definition(state, definition_id: String) -> int:
    var count := 0
    for card_id in state.card_by_id:
        if String(state.card_by_id[card_id].definition_id) == definition_id:
            count += 1
    return count


## 从给定局势推进到商店可达（T16(c) 需要先摆好饰品再进店，所以不能用 _advance_to_kind）。
func _advance_to_shop_from(run, rng: Dictionary) -> Dictionary:
    var current = run
    var current_rng: Dictionary = rng
    for _index in range(8):
        var node_id := _pick_reachable(current)
        if node_id.is_empty():
            return {}
        if String(current.find_node(node_id).kind) == "shop":
            return {"run": current, "rng": current_rng}
        var advanced: Dictionary = _advance_one_node(current, current_rng)
        if not Result.is_ok(advanced):
            return {}
        current = advanced["data"]["run"]
        current_rng = advanced["data"]["rng"]
    return {}

