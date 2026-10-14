extends RefCounted
##
## 战斗引擎步骤 3 验收：单位 · 场景 · 考试 · 阶段。
## 覆盖：召入/换班/暂离/合作阶段、护卫改向不溢出、多护卫取最早入场、
## 独立作答备考面 / 固定考场回忆面、场景建立替换与准备触发、
## B01 三阶段转阶段（新 task_id、旧目标不误指、清旧屏障）。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const MANIFEST := "battle_mvp"


func run(h) -> void:
        var db := ContentDB.new()
        var loaded = db.load(MANIFEST)
        if not Result.is_ok(loaded):
                h.begin("BattleEngine · 前置")
                h.check("battle_mvp 清单加载成功", false, str(loaded))
                return
        h.begin("BattleEngine · 单位召入 / 合作阶段 / 护卫")
        _summon_and_ally(h, db)
        h.begin("BattleEngine · 多护卫取最早入场")
        _earliest_guard(h, db)
        h.begin("BattleEngine · 单位支援自身放松")
        _unit_self_relax(h, db)
        h.begin("BattleEngine · 护卫改向不溢出")
        _guard_no_overflow(h, db)
        h.begin("BattleEngine · 换班（满槽替换）")
        _switch_unit(h, db)
        h.begin("BattleEngine · 考试替代面")
        _exam_faces(h, db)
        h.begin("BattleEngine · 场景建立 / 替换 / 准备触发")
        _scene_flow(h, db)
        h.begin("BattleEngine · 场景本战次数上限")
        _scene_limit(h, db)
        h.begin("BattleEngine · 场景轮末效果")
        _scene_round_end(h, db)
        h.begin("BattleEngine · B01 三阶段")
        _b01_phases(h, db)


# ── 单位 ──────────────────────────────────────────────────

func _summon_and_ally(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, "N01", _deck("K43", 5), ["K43"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K43")
        if not _ok(h, "打出 K43 召入 F01", step):
                return
        var state = _state(step)
        h.eq("召入 1 个单位", state.units.size(), 1)
        if state.units.is_empty():
                return
        var unit = state.units[0]
        h.eq("单位定义 F01", unit.definition_id, "F01")
        h.eq("上限精力 10", unit.max_vitality, 10)
        h.eq("协作 2", unit.cooperation, 2)
        h.check("入场获得护卫", state.find_status(unit.unit_id, GameConstants.STATUS_GUARD) != null)
        var unit_id = unit.unit_id

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        state = _state(step)
        var still = state.find_unit(unit_id)
        h.check("单位仍存活", still != null)
        if still != null:
                h.eq("合作阶段协作 2：24-2=22", state.tasks[0].work_remaining, 22)
                h.eq("每回合行动一次", still.actions_taken, 1)
                h.eq("行动后失去 1 精力", still.vitality, 4)
        h.eq("护卫承接压力，主角精力不变 72", state.player.vitality, 72)


func _earliest_guard(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K43", 4) + _deck("K46", 4)
        var step = _begin_with(db, "N01", deck, ["K43", "K46"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K43")
        step = _play(engine, step, "K46")
        if not _ok(h, "召入两个护卫", step):
                return
        var state = _state(step)
        h.eq("场上 2 个单位", state.units.size(), 2)
        if state.units.size() < 2:
                return
        var first_id = state.units[0].unit_id
        var second_id = state.units[1].unit_id
        h.check("F01 入场更早", state.units[0].entered_order < state.units[1].entered_order)

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        state = _state(step)
        var first = state.find_unit(first_id)
        var second = state.find_unit(second_id)
        h.check("两个护卫都存活", first != null and second != null)
        if first != null and second != null:
                h.eq("最早入场者承受压力：10-1-5=4", first.vitality, 4)
                h.eq("后入场者未被改向：12-1=11", second.vitality, 11)
                h.eq("后入场者已行动一次", second.actions_taken, 1)


func _guard_no_overflow(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, "N01", _deck("K43", 5), ["K43"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K43")
        var state = _state(step)
        if state.units.is_empty():
                h.check("召入护卫", false)
                return
        state.units[0].vitality = 3
        state.tasks[0].intent_snapshot = {"index": 1, "pressure": 5, "pressure_times": 2}
        var unit_id = state.units[0].unit_id

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        state = _state(step)
        h.check("护卫第一段后暂离", state.find_unit(unit_id) == null)
        h.eq("第二段无护卫则打主角：72-5=67", state.player.vitality, 67)
        h.check("伤害不溢出到主角之外", state.units.is_empty())


func _switch_unit(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K43", 3) + _deck("K44", 2) + _deck("K46", 3)
        var step = _find_switch_state(db, engine, deck)
        if step.is_empty():
                h.check("找到换班测试种子", false)
                return
        h.check("找到换班测试种子", true)
        var state = _state(step)
        h.eq("第 2 回合开始有 2 个单位", state.units.size(), 2)
        h.check("手牌同时有 K46 与 K43", _has_in_hand(state, "K46") and _has_in_hand(state, "K43"))

        step = _play(engine, step, "K46")
        if not _ok(h, "召入第 3 个单位", step):
                return
        state = _state(step)
        h.eq("满 3 槽", state.units.size(), 3)
        h.eq("费用 2 后剩余专注 1", state.player.focus, 1)
        var oldest_id = state.units[0].unit_id
        var k43_card = _hand_card(state, "K43")
        var focus_before = state.player.focus

        var cancel = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k43_card},
        }, step["data"]["rng_state"])
        h.eq("满槽取消换班被拒", Result.error_code(cancel), GameConstants.ERROR_INVALID_TARGET)
        h.eq("取消不扣专注", state.player.focus, focus_before)
        h.eq("取消仍保持 3 槽", state.units.size(), 3)
        h.eq("取消不移牌", state.zone_of(k43_card), GameConstants.ZONE_HAND)

        step = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k43_card, "replace_unit_id": oldest_id},
        }, step["data"]["rng_state"])
        if not _ok(h, "指定换班后召入", step):
                return
        state = _state(step)
        h.eq("换班后仍是 3 槽", state.units.size(), 3)
        h.check("被换下的单位已离场", state.find_unit(oldest_id) == null)


func _unit_self_relax(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K46", 5) + _deck("K01", 5)
        var step = _begin_with(db, "N01", deck, ["K46"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K46")
        if not _ok(h, "召入 F04", step):
                return
        h.eq("F04 上限精力 12", _state(step).units[0].max_vitality, 12)
        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        var state = _state(step)
        h.check("F04 仍在场", state.units.size() == 1)
        if state.units.size() == 1:
                h.eq("支援自身 2 放松吸收：12-1-(5-2)=8", state.units[0].vitality, 8)

# ── 考试 ──────────────────────────────────────────────────

func _exam_faces(h, db) -> void:
        var engine = BattleEngine.new(db)

        var deck_prepare = _deck("K43", 5, 1)
        var step = _begin_with(db, "B01", deck_prepare, ["K43"])
        if not _ok(h, "独立作答 begin", step):
                return
        var card = _hand_card(_state(step), "K43")
        var play = engine.apply(_state(step), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card},
        }, step["data"]["rng_state"])
        if not _ok(h, "独立作答打出升级 K43", play):
                return
        var after = _state(play)
        h.eq("备考面：获得 7 放松", after.player.relax, 7)
        h.eq("不召入单位", after.units.size(), 0)
        h.eq("保留耗尽标记", after.zone_of(card), GameConstants.ZONE_EXHAUST)
        h.eq("同费用 1", after.player.focus, 2)

        var deck_recall = _deck("K53", 5, 1) + _deck("K01", 5)
        var step2 = _begin_with(db, "B01", deck_recall, ["K53"])
        if not _ok(h, "固定考场 begin", step2):
                return
        var card2 = _hand_card(_state(step2), "K53")
        var hand_before = _state(step2).zones.hand.size()
        var play2 = engine.apply(_state(step2), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card2},
        }, step2["data"]["rng_state"])
        if not _ok(h, "固定考场打出升级 K53", play2):
                return
        var after2 = _state(play2)
        h.eq("回忆面：获得 4 放松", after2.player.relax, 4)
        h.check("回忆面：抽 1（5-1+1=5）", after2.zones.hand.size() == hand_before)
        h.check("不建立场景", after2.scene == null)
        h.eq("保留耗尽标记", after2.zone_of(card2), GameConstants.ZONE_EXHAUST)
        h.eq("基础费用 2", after2.player.focus, 1)


# ── 场景 ──────────────────────────────────────────────────

func _scene_flow(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K53", 3) + _deck("K51", 3) + _deck("K01", 4)
        var step = _begin_with(db, "N01", deck, ["K53", "K51", "K01"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K53")
        if not _ok(h, "建立 L03", step):
                return
        var state = _state(step)
        h.check("场景已建立", state.scene != null)
        if state.scene != null:
                h.eq("场景定义 L03", state.scene.definition_id, "L03")
        h.eq("费用 2 后专注 1", state.player.focus, 1)

        var work_before = _state(step).tasks[0].work_remaining
        step = _play(engine, step, "K01")
        if not _ok(h, "L03 下打出第一张工作牌", step):
                return
        state = _state(step)
        h.eq("每回合第一张工作牌费用 -1（仍剩 1）", state.player.focus, 1)
        h.eq("A01 首张工作牌：24-7=17", work_before - state.tasks[0].work_remaining, 7)

        step = _play(engine, step, "K51")
        if not _ok(h, "替换为 L01", step):
                return
        state = _state(step)
        h.check("场景被替换", state.scene != null)
        if state.scene != null:
                h.eq("新场景定义 L01", state.scene.definition_id, "L01")
        h.eq("替换花费 1 专注", state.player.focus, 0)

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        state = _state(step)
        h.eq("L01 下个准备恢复 2：72-5+2=69", state.player.vitality, 69)


func _scene_limit(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, "N01", _deck("K51", 5), ["K51"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K51")
        if not _ok(h, "建立 L01", step):
                return
        for _i in range(5):
                step = _end_turn(engine, step)
                if not Result.is_ok(step):
                        h.check("连续结束回合", false, str(step))
                        return
        h.eq("L01 本战只恢复 3 次：49", _state(step).player.vitality, 49)
        h.check("战斗仍在进行", step["data"]["outcome"] == null)


func _scene_round_end(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, "N01", _deck("K56", 5) + _deck("K01", 3), ["K56"])
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K56")
        if not _ok(h, "建立 L06", step):
                return
        h.check("L06 已建立", _state(step).scene != null)
        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        h.eq("L06 轮末失去 2 + 意图压力 5：72-2-5=65", _state(step).player.vitality, 65)


# ── B01 三阶段 ────────────────────────────────────────────

func _b01_phases(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, "B01", _deck("K01", 10), ["K01"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        h.eq("B01 DDL 10", state.ddl, 10)
        h.eq("首阶段 phase_key", state.tasks[0].phase_key, "limit")
        h.eq("首阶段未完成量 20", state.tasks[0].work_max, 20)
        h.eq("首轮意图压力 7", int(state.tasks[0].intent_snapshot.get("pressure", -1)), 7)
        var old_id = state.tasks[0].task_id
        state.tasks[0].work_remaining = 2
        state.tasks[0].shield = 5

        step = _play(engine, step, "K01")
        if not _ok(h, "完成第一阶段", step):
                return
        state = _state(step)
        h.eq("先生成下一阶段，不提前胜利", state.tasks.size(), 1)
        h.check("尚无结局", step["data"]["outcome"] == null)
        if state.tasks.is_empty():
                return
        var next = state.tasks[0]
        h.check("新阶段使用新 task_id", next.task_id != old_id)
        h.eq("新阶段 phase_key", next.phase_key, "integral")
        h.eq("新阶段独立上限 25", next.work_max, 25)
        h.eq("新阶段清旧屏障", next.shield, 0)
        h.eq("新阶段公开下一意图压力 7", int(next.intent_snapshot.get("pressure", -1)), 7)
        h.check("旧 task_id 已不存在", state.find_task(old_id) == null)

        var stale_target = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": _hand_card(state, "K01"), "target_ids": [old_id]},
        }, step["data"]["rng_state"])
        h.eq("旧目标不误指新阶段", Result.error_code(stale_target), GameConstants.ERROR_INVALID_TARGET)

        var new_id = next.task_id
        next.work_remaining = 2
        step = _play(engine, step, "K01")
        if not _ok(h, "完成第二阶段", step):
                return
        state = _state(step)
        h.eq("第二阶段后进入 proof", state.tasks[0].phase_key, "proof")
        h.check("仍无结局", step["data"]["outcome"] == null)

        state.tasks[0].work_remaining = 2
        step = _play(engine, step, "K01")
        if not _ok(h, "完成第三阶段", step):
                return
        state = _state(step)
        h.eq("三阶段全清", state.tasks.size(), 0)
        h.check("产生胜利结局", step["data"]["outcome"] != null)
        if step["data"]["outcome"] != null:
                h.eq("result=won", step["data"]["outcome"].get("result", ""), GameConstants.OUTCOME_WON)
        h.check("新阶段任务也已移除", state.find_task(new_id) == null)


# ── 工具 ──────────────────────────────────────────────────

func _begin(db, encounter_id: String, deck: Array, vitality: int = 72, max_vitality: int = 72, seed_value: int = 0) -> Dictionary:
        var source = RandomSourceScript.new(seed_value)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "Rtest#1",
                "node_id": "n1",
                "encounter_id": encounter_id,
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": vitality,
                "max_vitality": max_vitality,
                "cards": deck,
                "relics": ["A01"],
                "rng_state": source.export_state(),
        })


func _begin_with(db, encounter_id: String, deck: Array, needed: Array) -> Dictionary:
        for seed_value in range(0, 120):
                var step = _begin(db, encounter_id, deck, 72, 72, seed_value)
                if not Result.is_ok(step):
                        continue
                var state = _state(step)
                var ok = true
                for definition_id in needed:
                        if not _has_in_hand(state, String(definition_id)):
                                ok = false
                                break
                if ok:
                        return step
        return _begin(db, encounter_id, deck, 72, 72, 0)


## 换班场景需要「第 1 回合手牌有 K43+K44，且第 2 回合手牌有 K46+K43」的种子。
func _find_switch_state(db, engine, deck: Array) -> Dictionary:
        for seed_value in range(0, 200):
                var step = _begin(db, "N01", deck, 72, 72, seed_value)
                if not Result.is_ok(step):
                        continue
                var state = _state(step)
                if not (_has_in_hand(state, "K43") and _has_in_hand(state, "K44")):
                        continue
                step = _play(engine, step, "K43")
                step = _play(engine, step, "K44")
                if not Result.is_ok(step):
                        continue
                step = _end_turn(engine, step)
                if not Result.is_ok(step):
                        continue
                state = _state(step)
                if state.units.size() == 2 and _has_in_hand(state, "K46") and _has_in_hand(state, "K43"):
                        return step
        return {}


func _deck(definition_id: String, count: int, upgrade_level: int = 0) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "Rtest#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "Rtest#R_%s_%d" % [definition_id, index],
                        "upgrade_level": upgrade_level,
                })
        return deck


func _play(engine, step: Dictionary, definition_id: String) -> Dictionary:
        var state = _state(step)
        var card_id = _hand_card(state, definition_id)
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_card", {"definition_id": definition_id})
        var payload = {"card_id": card_id}
        if not state.tasks.is_empty():
                payload["target_ids"] = [state.tasks[0].task_id]
        return engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": payload,
        }, step["data"]["rng_state"])


func _end_turn(engine, step: Dictionary) -> Dictionary:
        return engine.apply(_state(step), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, step["data"]["rng_state"])


func _hand_card(state, definition_id: String) -> String:
        for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        return card.card_id
        return ""


func _has_in_hand(state, definition_id: String) -> bool:
        return not _hand_card(state, definition_id).is_empty()


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, step: Dictionary) -> bool:
        if Result.is_ok(step):
                h.check(label, true)
                return true
        h.check(label, false, str(step.get("error")))
        return false