extends RefCounted
##
## t16 验收：多段工作牌跨阶段时，锁定旧阶段的剩余段必须跳过（战斗契约 §17 / [DDL-002]）。
##
## 现役牌面每张只有一段 complete，所以这里用**合成队列**（白盒：只动测试持有的 BattleState）
## 造出「两段 complete + 第 1 段把阶段打穿」的场景。不能等内容里真有多段牌才靠探针兜底：
## 那时剩余段已经被悄悄打进新阶段（等于替玩家白打一个阶段）。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")


func run(h) -> void:
        var db := ContentDB.new()
        var loaded = db.load(GameConstants.MANIFEST_MVP)
        if not Result.is_ok(loaded):
                h.begin("t16 前置")
                h.check("MVP 清单加载成功", false, str(loaded))
                return
        h.begin("t16 · 锁定目标消失时剩余段跳过（合成两段工作牌）")
        _skip_after_phase_transition(h, db)
        h.begin("t16 · 目标选择的两条分支不误伤既有行为")
        _target_branches(h, db)


func _skip_after_phase_transition(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K01", 12), "B01")
        if not _ok(h, "begin 成功（B01 三阶段）", step):
                return
        var state = _state(step)
        h.eq("B01 初始 1 个任务", state.tasks.size(), 1)
        state.tasks[0].work_remaining = 6
        state.tasks[0].work_max = 6
        var old_id := String(state.tasks[0].task_id)

        # 合成牌面：两段 complete（各 6），锁定目标是旧阶段的 task。
        var card_id := _hand_card(state, "K01")
        h.check("手上有用于结算的牌", not card_id.is_empty())
        state.move_card(card_id, GameConstants.ZONE_RESOLVING)
        var resolution = BattleState.create_resolution({
                "card_id": card_id,
                "definition_id": "K01",
                "target_ids": [old_id],
                "replace_unit_id": null,
                "face": {"type": "work", "exhaust": false},
        })
        resolution.queue = [{"op": "complete", "amount": 6}, {"op": "complete", "amount": 6}]
        resolution.effect_cursor = 0
        resolution.locked_target_ids = [old_id]
        state.resolution = resolution
        h.eq("多段队列就绪（2 段）", resolution.queue.size(), 2)

        var rng = RandomSourceScript.new(0)
        rng.restore_state(step["data"]["rng_state"])
        engine._execute_queue(engine._new_ctx(state, rng))

        h.eq("仍在同一场战斗、仍有 1 个任务（先生成下一阶段）", state.tasks.size(), 1)
        var new_id := String(state.tasks[0].task_id)
        h.check("新 task_id 与旧的不同", new_id != old_id)
        h.eq("新阶段拿到满工作量（没吃到被跳过的第 2 段）", int(state.tasks[0].work_remaining), int(state.tasks[0].work_max))
        h.eq("旧阶段的任务已不存在", state.find_task(old_id), null)
        h.check("锁定旧阶段查不到任务 → 跳过该段（返回 null）", engine._primary_task(state, [old_id]) == null)
        h.check("结算正常收尾（resolution 清空）", state.resolution == null)
        h.eq("牌正常进弃牌堆", state.zone_of(card_id), GameConstants.ZONE_DISCARD)
        h.check("没有提前判胜", state.outcome == null)


func _target_branches(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K01", 8), "N01")
        if not _ok(h, "begin 成功（N01）", step):
                return
        var state = _state(step)
        var task_id := String(state.tasks[0].task_id)
        h.eq("锁定目标存在且未归零 → 命中它", String(engine._primary_task(state, [task_id]).task_id), task_id)
        h.eq("没给目标（场景/单位/饰品效果）→ 回退首个合法任务", String(engine._primary_task(state, []).task_id), task_id)
        h.check("锁定目标不存在 → 跳过（返回 null）", engine._primary_task(state, ["no-such-task"]) == null)


func _begin(db, deck: Array, encounter_id: String) -> Dictionary:
        var source = RandomSourceScript.new(0)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "RtestSeg#1",
                "node_id": "n1",
                "encounter_id": encounter_id,
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": 72,
                "max_vitality": 72,
                "cards": deck,
                "relics": ["A01"],
                "rng_state": source.export_state(),
        })


func _deck(definition_id: String, count: int) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "RtestSeg#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "RtestSeg#R_%s_%d" % [definition_id, index],
                        "upgrade_level": 0,
                })
        return deck


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
