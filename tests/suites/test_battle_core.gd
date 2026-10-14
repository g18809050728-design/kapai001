extends RefCounted
##
## 战斗引擎步骤 1 验收：相位机与核心结算（《游戏规则书》§3.3 / §4~§10）。
## 覆盖：begin/preview/apply/make_view、相位顺序、完成量先扣屏障、
## 压力先扣放松、费用 max(0, 基础+加费-减费)、DDL 超时判负、非法操作零副作用。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")


func run(h) -> void:
        var db = ContentDB.new()
        var loaded: Dictionary = db.load(GameConstants.MANIFEST_MVP)
        if not Result.is_ok(loaded):
                h.begin("BattleEngine · 前置")
                h.check("MVP 清单加载成功", false, str(loaded))
                return
        h.begin("BattleEngine · 相位与初始化")
        _setup(h, db)
        h.begin("BattleEngine · 胜利路径（K01 + N01）")
        _win_path(h, db)
        h.begin("BattleEngine · 压力与放松")
        _relax_absorbs_pressure(h, db)
        h.begin("BattleEngine · 失败路径")
        _loss_vitality(h, db)
        _loss_deadline(h, db)
        h.begin("BattleEngine · 非法操作零副作用")
        _illegal(h, db)
        h.begin("BattleEngine · BattleView")
        _view(h, db)


# ── 用例 ──────────────────────────────────────────────────

func _setup(h, db) -> void:
        var step = _begin(db, _deck("K01", 6))
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        h.eq("停在玩家行动阶段", state.phase, GameConstants.PHASE_PLAYER_ACTION)
        h.eq("回合从 1 开始", state.round_index, 1)
        h.eq("专注 3", state.player.focus, 3)
        h.eq("首回合抽 5 张", state.zones.hand.size(), 5)
        h.eq("N01 DDL=8", state.ddl, 8)
        h.eq("任务 1 个", state.tasks.size(), 1)
        h.eq("任务未完成量 24", state.tasks[0].work_remaining, 24)
        h.eq("首轮意图压力 5", int(state.tasks[0].intent_snapshot.get("pressure", -1)), 5)
        h.eq("稳定边界 stable=true", step["data"]["stable"], true)
        h.check("无待选", step["data"]["pending_choice"] == null)
        h.eq("牌区总数等于登记牌数", state.zones.total(), 6)


func _win_path(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K01", 10))
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)

        step = _play(engine, step, "K01")
        if not _ok(h, "打出第一张 K01", step):
                return
        state = _state(step)
        h.eq("A01 首张工作牌 +1：24-7=17", state.tasks[0].work_remaining, 17)
        h.eq("扣 1 专注", state.player.focus, 2)

        step = _play(engine, step, "K01")
        state = _state(step)
        h.eq("第二张无 A01：17-6=11", state.tasks[0].work_remaining, 11)
        step = _play(engine, step, "K01")
        state = _state(step)
        h.eq("第三张：11-6=5", state.tasks[0].work_remaining, 5)
        h.eq("专注用尽", state.player.focus, 0)

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        state = _state(step)
        h.eq("轮末扣 1 DDL", state.ddl, 7)
        h.eq("进入第 2 回合", state.round_index, 2)
        h.eq("第 2 轮意图压力 7", int(state.tasks[0].intent_snapshot.get("pressure", -1)), 7)
        h.eq("压力 5 未被放松吸收：72-5=67", state.player.vitality, 67)
        h.eq("第 2 回合重新抽 5", state.zones.hand.size(), 5)

        step = _play(engine, step, "K01")
        if not _ok(h, "第 2 回合完成最后任务", step):
                return
        var outcome: Variant = step["data"]["outcome"]
        h.check("产生结局", outcome != null)
        if outcome != null:
                h.eq("result=won", outcome.get("result", ""), GameConstants.OUTCOME_WON)
                h.eq("reason=tasks_completed", outcome.get("reason", ""), GameConstants.REASON_TASKS_COMPLETED)
        h.eq("phase=finished", _state(step).phase, GameConstants.PHASE_FINISHED)
        h.eq("任务清空", _state(step).tasks.size(), 0)
        h.eq("胜利后不再扣 DDL", _state(step).ddl, 7)


func _relax_absorbs_pressure(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K02", 6))
        if not _ok(h, "begin 成功", step):
                return
        step = _play(engine, step, "K02")
        if not _ok(h, "打出 K02", step):
                return
        h.eq("获得 5 放松", _state(step).player.relax, 5)
        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        h.eq("放松吸收 5 点压力，精力不变", _state(step).player.vitality, 72)
        h.eq("放松已用完", _state(step).player.relax, 0)


func _loss_vitality(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K02", 6), 5, 72)
        if not _ok(h, "低精力开局", step):
                return
        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        var outcome: Variant = step["data"]["outcome"]
        h.check("精力归零判负", outcome != null)
        if outcome != null:
                h.eq("result=lost", outcome.get("result", ""), GameConstants.OUTCOME_LOST)
                h.eq("reason=vitality_depleted", outcome.get("reason", ""), GameConstants.REASON_VITALITY_DEPLETED)
        h.eq("精力被夹到 0", _state(step).player.vitality, 0)


func _loss_deadline(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K02", 6), 72, 72)
        if not _ok(h, "begin 成功", step):
                return
        var rounds = 0
        while step["data"]["outcome"] == null and rounds < 20:
                step = _end_turn(engine, step)
                if not Result.is_ok(step):
                        h.check("结束回合成功", false, str(step))
                        return
                rounds += 1
        var outcome: Variant = step["data"]["outcome"]
        h.check("DDL 耗尽判负", outcome != null)
        if outcome != null:
                h.eq("reason=deadline_expired", outcome.get("reason", ""), GameConstants.REASON_DEADLINE_EXPIRED)
        h.eq("第 8 轮末超时", rounds, 8)
        h.eq("DDL 归零", _state(step).ddl, 0)
        h.check("精力仍有剩余（不是精力失败）", _state(step).player.vitality > 0)


func _illegal(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K01", 4))
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        var rng_state: Variant = step["data"]["rng_state"]
        var target = state.tasks[0].task_id
        var card_id = _hand_card(state, "K01")
        var focus_before = state.player.focus
        var hand_before = state.card_ids_in(GameConstants.ZONE_HAND).duplicate()
        var work_before = state.tasks[0].work_remaining

        var no_target = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card_id},
        }, rng_state)
        h.check("缺少任务目标被拒", not Result.is_ok(no_target))
        h.eq("错误码 INVALID_TARGET", Result.error_code(no_target), GameConstants.ERROR_INVALID_TARGET)

        var ghost = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": "no_such_card", "target_ids": [target]},
        }, rng_state)
        h.check("不在手中的牌被拒", not Result.is_ok(ghost))

        h.eq("失败后专注不变", state.player.focus, focus_before)
        h.eq("失败后手牌不变", state.card_ids_in(GameConstants.ZONE_HAND), hand_before)
        h.eq("失败后任务不变", state.tasks[0].work_remaining, work_before)

        var preview: Dictionary = engine.preview(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card_id, "target_ids": [target]},
        })
        h.check("预览成功", Result.is_ok(preview))
        if Result.is_ok(preview):
                h.eq("预览 can_submit", preview["data"]["can_submit"], true)
                h.eq("预览费用 1", int(preview["data"]["costs"]["focus"]), 1)
        h.eq("预览不改专注", state.player.focus, focus_before)
        h.eq("预览不改任务", state.tasks[0].work_remaining, work_before)
        h.eq("预览不改手牌", state.card_ids_in(GameConstants.ZONE_HAND), hand_before)

        # 专注用尽后再出牌：费用不足，状态不变
        for _i in range(3):
                step = _play(engine, step, "K01")
                if not Result.is_ok(step):
                        h.check("前三张 K01 成功", false, str(step))
                        return
        state = _state(step)
        rng_state = step["data"]["rng_state"]
        h.eq("专注归零", state.player.focus, 0)
        var broke_card = _hand_card(state, "K01")
        var broke_work = state.tasks[0].work_remaining
        var broke = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": broke_card, "target_ids": [state.tasks[0].task_id]},
        }, rng_state)
        h.check("专注不足被拒", not Result.is_ok(broke))
        h.eq("错误码 INSUFFICIENT_RESOURCE", Result.error_code(broke), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("失败不扣专注", state.player.focus, 0)
        h.eq("失败不移牌", state.zone_of(broke_card), GameConstants.ZONE_HAND)
        h.eq("失败不结算任务", state.tasks[0].work_remaining, broke_work)


func _view(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K01", 6))
        var state = _state(step)
        var view: Dictionary = engine.make_view(state)
        h.eq("view 阶段", view["phase"], GameConstants.PHASE_PLAYER_ACTION)
        h.eq("view 回合", view["round_index"], 1)
        h.eq("view DDL", view["ddl"], 8)
        h.eq("view 手牌 5", (view["hand"] as Array).size(), 5)
        h.eq("view 专注 3", int(view["player"]["focus"]), 3)
        h.eq("view 牌堆计数", int(view["zones"]["hand"]), 5)
        var moved: Array = state.card_ids_in(GameConstants.ZONE_HAND)
        state.move_card(String(moved[0]), GameConstants.ZONE_DISCARD)
        var view2: Dictionary = engine.make_view(state)
        var public_zones: Dictionary = view2["zones_public"]
        h.check("zones_public 不含抽牌堆", not public_zones.has("draw"))
        h.check("zones_public 不含结算区", not public_zones.has("resolving"))
        h.eq("弃牌堆公开 1 张", (public_zones["discard"] as Array).size(), 1)
        var discard_card: Dictionary = public_zones["discard"][0]
        h.eq("弃牌堆卡面含 card_id", discard_card.has("card_id"), true)
        h.eq("弃牌堆卡面 definition_id", String(discard_card["definition_id"]), "K01")
        h.eq("弃牌堆卡面与手牌同构（字段数一致）", discard_card.size(), (view2["hand"][0] as Dictionary).size())
        h.eq("弃牌堆的牌不可出牌", bool(discard_card["playable"]), false)
        h.eq("手牌里的牌仍可出牌", bool((view2["hand"][0] as Dictionary)["playable"]), true)
        h.eq("view 任务意图压力 5", int((view["tasks"][0] as Dictionary)["intent"]["pressure"]), 5)
        var order: Array = view["phase_order"]
        h.eq("相位顺序首项", String(order[0]), GameConstants.PHASE_PLAYER_PREPARE)
        h.eq("相位顺序 2", String(order[1]), GameConstants.PHASE_DRAW)
        h.eq("相位顺序 3", String(order[2]), GameConstants.PHASE_PLAYER_ACTION)
        h.eq("相位顺序末项", String(order[8]), GameConstants.PHASE_ROUND_END)
        h.check("view 稳定", bool(view["stable"]))


# ── 工具 ──────────────────────────────────────────────────

func _begin(db, deck: Array, vitality: int = -1, max_vitality: int = 72, seed_value: int = 20261013, relics: Array = ["A01"]) -> Dictionary:
        var source = RandomSourceScript.new(seed_value)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "Rtest#1",
                "node_id": "n1",
                "encounter_id": "N01",
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": (vitality if vitality >= 0 else max_vitality),
                "max_vitality": max_vitality,
                "cards": deck,
                "relics": relics,
                "rng_state": source.export_state(),
        })


func _deck(definition_id: String, count: int, upgrade_level: int = 0) -> Array:
        var deck = []
        for index in range(count):
                var origin = "Rtest#RC%s%d" % [definition_id, index]
                deck.append({
                        "card_id": "Rtest#BC%s%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": origin,
                        "upgrade_level": upgrade_level,
                })
        return deck


func _play(engine, step: Dictionary, definition_id: String) -> Dictionary:
        var state = _state(step)
        var card_id = _hand_card(state, definition_id)
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_card_in_hand", {"definition_id": definition_id})
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
                "payload": {"retained_card_ids": []},
        }, step["data"]["rng_state"])


func _hand_card(state, definition_id: String) -> String:
        for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        return card.card_id
        return ""


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, step: Dictionary) -> bool:
        if Result.is_ok(step):
                h.check(label, true)
                return true
        h.check(label, false, str(step.get("error")))
        return false