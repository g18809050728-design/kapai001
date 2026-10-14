extends RefCounted
##
## 受控修复 t12 验收：消除静默失败（《游戏规则书》[ENG-003] + 内容加载期纪律）。
##
## F1 主动支付精力是一等公民：K10「支付4精力」走费用层（vitality_cost），预检按
##    battle.minimum_vitality_after_payment 判定「支付后 ≥ 下限」，不足则拒绝且零副作用；
##    支付绕过放松（与压力伤害不同）。
## F2 未接线的状态在加载期被拒：plagiarism_shield 缺「屏障吸收」接线，写进内容报 CONTENT_INVALID。
## F3 未知 intent 字段在加载期报错（以前静默忽略）。
## F4「至多/可选 0」由 t9 的 discard.up_to 覆盖（见 test_battle_ops.gd），本套件只做回归确认。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const TASKS_PATH := "res://data/definitions/tasks.json"


func run(h) -> void:
        var db := ContentDB.new()
        var loaded = db.load(GameConstants.MANIFEST_MVP)
        if not Result.is_ok(loaded):
                h.begin("引擎修复 · 前置")
                h.check("mvp 清单加载成功", false, str(loaded))
                return
        h.begin("引擎修复 · F1 精力代价是费用（K10 熬夜）")
        _vitality_cost(h, db)
        h.begin("引擎修复 · F1 非法用法零副作用")
        _vitality_denied(h, db)
        h.begin("引擎修复 · F2 未接线状态在加载期被拒")
        _unwired_status(h, db)
        h.begin("引擎修复 · F3 未知 intent 字段在加载期报错")
        _intent_fields(h, db)
        h.begin("引擎修复 · F4 至多选择回归确认")
        _up_to_regression(h, db)


# ── F1 正向 ───────────────────────────────────────────────

func _vitality_cost(h, db) -> void:
        var k10: Dictionary = db.definition(GameConstants.KIND_CARD, "K10")
        h.eq("K10 的支付写在费用层", int(k10["vitality_cost"]), 4)
        h.eq("K10 升级支付 3", int(k10["upgrade"]["vitality_cost"]), 3)
        h.eq("K10 不再用 lose_vitality 近似", (k10["effects"] as Array).size(), 1)
        h.eq("K10 剩下的是获得 2 专注", [String((k10["effects"][0] as Dictionary)["op"]), int((k10["effects"][0] as Dictionary)["amount"])], ["gain_focus", 2])
        h.eq("K10 仍耗尽", bool(k10["exhaust"]), true)
        h.eq("规则参数 minimum_vitality_after_payment 已接线", db.battle_int("minimum_vitality_after_payment", -1), 1)
        h.eq("带精力代价的启用牌只有 K10", _cards_with_vitality_cost(db), ["K10"])

        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K10", 4), 72)
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        var k10_id = _hand_card(state, "K10")
        var quote = engine.calculate_cost(state, k10_id)
        h.eq("CostQuote 报告真实精力代价", int(quote["data"]["vitality_cost"]), 4)
        h.eq("CostQuote 专注费用 0", int(quote["data"]["cost"]), 0)
        var preview = engine.preview(state, {"type": GameConstants.ACTION_PLAY_CARD, "payload": {"card_id": k10_id}})
        h.eq("预览给出真实精力代价", int(preview["data"]["costs"]["vitality"]), 4)
        h.eq("精力够时预览可提交", bool(preview["data"]["can_submit"]), true)
        h.eq("视图也带精力代价", _view_vitality_cost(engine.make_view(state), k10_id), 4)

        state.player.relax = 5
        var focus_before = state.player.focus
        var played = _play_id(engine, step, k10_id)
        if not _ok(h, "精力 72 打出 K10", played):
                return
        var after = _state(played)
        h.eq("支付 4 精力：72-4=68", after.player.vitality, 68)
        h.eq("支付绕过放松：放松仍在", after.player.relax, 5)
        h.eq("费用 0 + 获得 2 专注：3+2=5", after.player.focus, focus_before + 2)
        h.eq("耗尽进消耗堆", after.zone_of(k10_id), GameConstants.ZONE_EXHAUST)
        h.eq("结算后没有归零判负", after.outcome, null)

        # 升级面：支付 3
        var step_u = _begin(db, _deck("K10", 4, 1), 72)
        var state_u = _state(step_u)
        var k10_u = _hand_card(state_u, "K10")
        var quote_u = engine.calculate_cost(state_u, k10_u)
        h.eq("升级 CostQuote 支付 3", int(quote_u["data"]["vitality_cost"]), 3)
        var played_u = _play_id(engine, step_u, k10_u)
        if _ok(h, "升级 K10 打出", played_u):
                h.eq("升级支付 3：72-3=69", _state(played_u).player.vitality, 69)

        # 边界：支付后恰好剩 1 是允许的
        var step_edge = _begin(db, _deck("K10", 4), 5)
        var edge = _play_id(engine, step_edge, _hand_card(_state(step_edge), "K10"))
        if _ok(h, "精力 5 打 K10（支付后剩 1）", edge):
                h.eq("支付后剩 1", _state(edge).player.vitality, 1)
                h.eq("没有判负", _state(edge).outcome, null)


# ── F1 反向：不足即拒绝且零副作用 ─────────────────────────

func _vitality_denied(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K10", 4) + _deck("K01", 6), 4)
        if not _ok(h, "begin 成功（精力 4）", step):
                return
        var state = _state(step)
        var k10_id = _hand_card(state, "K10")
        h.eq("精力 4 时预览不可提交", bool(engine.preview(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k10_id},
        })["data"]["can_submit"]), false)

        var focus_before = state.player.focus
        var vitality_before = state.player.vitality
        var draw_before = state.card_ids_in(GameConstants.ZONE_DRAW)
        var hand_before = state.card_ids_in(GameConstants.ZONE_HAND)
        var work_before = state.tasks[0].work_remaining
        var counters_before = _counter_fingerprint(state)
        var denied = _play_id(engine, step, k10_id)
        h.eq("[RB-03/T03] 精力 4 打 K10 被拒（支付后不足 1）", Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒不扣精力", state.player.vitality, vitality_before)
        h.eq("被拒不扣专注", state.player.focus, focus_before)
        h.eq("被拒不移动牌", [state.card_ids_in(GameConstants.ZONE_HAND), state.card_ids_in(GameConstants.ZONE_DRAW)], [hand_before, draw_before])
        h.eq("被拒不动任务", state.tasks[0].work_remaining, work_before)
        h.eq("被拒不加触发计数", _counter_fingerprint(state), counters_before)
        h.eq("被拒后牌仍在手", state.zone_of(k10_id), GameConstants.ZONE_HAND)
        h.eq("被拒后没有归零判负", state.outcome, null)

        # 升级面同样：精力 3 打升级 K10（支付 3 后为 0）被拒
        var step_u = _begin(db, _deck("K10", 4, 1), 3)
        var denied_u = _play_id(engine, step_u, _hand_card(_state(step_u), "K10"))
        h.eq("精力 3 打升级 K10 被拒", Result.error_code(denied_u), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒后精力仍 3", _state(step_u).player.vitality, 3)

        # 伤害语义的 lose_vitality 仍是合法 op（场景/事件用它，可以归零致死）——
        # 与主动支付分开表达，K10 不再借用它。
        h.check("lose_vitality 仍是合法 op（留给真正的伤害）", ContentDB.KNOWN_OPS.has(GameConstants.OP_LOSE_VITALITY))


# ── F2 未接线状态 ─────────────────────────────────────────

func _unwired_status(h, db) -> void:
        h.check("plagiarism_shield 不在已接线清单里", not GameConstants.WIRED_STATUS_IDS.has(GameConstants.STATUS_PLAGIARISM_SHIELD))
        h.check("guard 在已接线清单里（改向已实现）", GameConstants.WIRED_STATUS_IDS.has(GameConstants.STATUS_GUARD))
        h.check("焦虑/拖延/困倦/额外要求已接线", [
                GameConstants.STATUS_ANXIETY,
                GameConstants.STATUS_PROCRASTINATION,
                GameConstants.STATUS_DROWSINESS,
                GameConstants.STATUS_EXTRA_REQUIREMENTS,
        ].all(func(status_id): return GameConstants.WIRED_STATUS_IDS.has(status_id)), "四个状态未全部接线")
        h.eq("查重护盾本来就没有 rulesets 条目", db.has_status_definition(GameConstants.STATUS_PLAGIARISM_SHIELD), false)

        var problems := PackedStringArray()
        db._validate_effect_list([{"op": GameConstants.OP_GAIN_STATUS, "status": GameConstants.STATUS_PLAGIARISM_SHIELD, "stacks": 2}], "card K99.effects", problems)
        h.eq("卡效果里 grant 查重护盾被拒", problems.size(), 1)
        h.check("错误信息指出缺什么接线", _joined(problems).contains("尚未接线") and _joined(problems).contains("屏障吸收"), _joined(problems))

        var probs_intent := PackedStringArray()
        db._validate_task("N99", _task_with_intent({"index": 1, "gain_status": {"status": GameConstants.STATUS_PLAGIARISM_SHIELD, "stacks": 2, "target": "task"}, "text_key": "task.n99"}), probs_intent)
        h.check("意图里 grant 查重护盾被拒", not probs_intent.is_empty(), _joined(probs_intent))
        h.check("意图错误同样指出接线缺口", _joined(probs_intent).contains("屏障吸收"), _joined(probs_intent))

        var probs_remove := PackedStringArray()
        db._validate_effect_list([{"op": GameConstants.OP_REMOVE_STATUS, "status": GameConstants.STATUS_PLAGIARISM_SHIELD, "amount": 1}], "card K99.effects", probs_remove)
        h.check("remove_status 查重护盾同样被拒", _joined(probs_remove).contains("尚未接线"), _joined(probs_remove))

        var probs_bonus := PackedStringArray()
        db._validate_effect_list([{"op": GameConstants.OP_COMPLETE, "amount": 6, "bonus_if": {"status": GameConstants.STATUS_PLAGIARISM_SHIELD, "amount": 3}}], "card K99.effects", probs_bonus)
        h.check("bonus_if 查重护盾同样被拒", _joined(probs_bonus).contains("尚未接线"), _joined(probs_bonus))

        var ok_problems := PackedStringArray()
        db._validate_effect_list([{"op": GameConstants.OP_GAIN_STATUS, "status": GameConstants.STATUS_ANXIETY, "stacks": 1}], "card K99.effects", ok_problems)
        h.eq("已接线状态不被误伤", ok_problems.size(), 0)

        var unknown := PackedStringArray()
        db._validate_effect_list([{"op": GameConstants.OP_GAIN_STATUS, "status": "no_such_status", "stacks": 1}], "card K99.effects", unknown)
        h.check("完全未定义的状态同样被拒", _joined(unknown).contains("尚未接线") or _joined(unknown).contains("未定义"), _joined(unknown))


# ── F3 intent 字段 ────────────────────────────────────────

func _intent_fields(h, db) -> void:
        h.eq("已知 intent 字段清单被固定", ContentDB.INTENT_KNOWN_FIELDS, [
                "index", "text_key", "pressure", "pressure_times", "pressure_all",
                "shield", "work_restore", "extra_requirements", "gain_status", "add_card",
        ])

        var unknown := PackedStringArray()
        db._validate_intent({"index": 1, "pressure": 5, "pressure_target": "unit", "text_key": "x"}, "task N99 的 intent 1", unknown)
        h.check("未知字段报错（显式点名压力尚未实现）", _joined(unknown).contains("未知字段") and _joined(unknown).contains("pressure_target"), _joined(unknown))

        var sub_unknown := PackedStringArray()
        db._validate_intent({"index": 1, "gain_status": {"status": "anxiety", "stacks": 1, "duration": 2}, "text_key": "x"}, "task N99 的 intent 1", sub_unknown)
        h.check("gain_status 子字段未知也报错", _joined(sub_unknown).contains("duration"), _joined(sub_unknown))

        var bad_target := PackedStringArray()
        db._validate_intent({"index": 1, "gain_status": {"status": "anxiety", "stacks": 1, "target": "everyone"}, "text_key": "x"}, "task N99 的 intent 1", bad_target)
        h.check("gain_status.target 非法被拒", _joined(bad_target).contains("target 非法"), _joined(bad_target))

        var bad_zone := PackedStringArray()
        db._validate_intent({"index": 1, "add_card": {"card": "X01", "count": 1, "zone": "resolving"}, "text_key": "x"}, "task N99 的 intent 1", bad_zone)
        h.check("add_card.zone 非法被拒", _joined(bad_zone).contains("zone 非法"), _joined(bad_zone))

        var bad_number := PackedStringArray()
        db._validate_intent({"index": 1, "pressure": 0, "text_key": "x"}, "task N99 的 intent 1", bad_number)
        h.check("压力 0 被拒", _joined(bad_number).contains("pressure"), _joined(bad_number))

        # 现有 6 个任务定义逐条过校验：不许误伤
        var tasks := _read_json(TASKS_PATH)
        var checked := 0
        for raw in (tasks.get("definitions", []) as Array):
                var definition: Dictionary = raw
                var problems := PackedStringArray()
                db._validate_task(String(definition.get("id", "")), definition, problems)
                checked += 1
                h.check("现有任务 %s 通过 intent 校验" % String(definition.get("id", "")), problems.is_empty(), _joined(problems))
        h.eq("现役任务定义全部被检查", checked, 6)


# ── F4 回归确认 ───────────────────────────────────────────

func _up_to_regression(h, db) -> void:
        var k12: Dictionary = db.definition(GameConstants.KIND_CARD, "K12")
        h.eq("K12「弃至多2张」= discard.up_to", [String((k12["effects"][0] as Dictionary)["op"]), bool((k12["effects"][0] as Dictionary)["up_to"])], ["discard", true])
        h.eq("按实际弃置数抽牌 = draw.per_discarded", int((k12["effects"][1] as Dictionary)["per_discarded"]), 1)
        var engine = BattleEngine.new(db)
        var step = _begin(db, _deck("K12", 5), 72)
        var played = _play_id(engine, step, _hand_card(_state(step), "K12"))
        var choice = played.get("data", {}).get("pending_choice")
        h.check("至多选择真的允许 0 张", choice != null and int(choice["min_count"]) == 0, str(choice))


# ── 工具 ──────────────────────────────────────────────────

func _cards_with_vitality_cost(db) -> Array:
        var out = []
        for raw_id in db.enabled_ids(GameConstants.KIND_CARD):
                var definition: Dictionary = db.definition(GameConstants.KIND_CARD, String(raw_id))
                if int(definition.get("vitality_cost", 0)) > 0:
                        out.append(String(raw_id))
        out.sort()
        return out


func _view_vitality_cost(view: Dictionary, card_id: String) -> int:
        for raw in (view.get("hand", []) as Array):
                var entry: Dictionary = raw
                if String(entry.get("card_id", "")) == card_id:
                        return int(entry.get("effective_vitality_cost", -1))
        return -1


func _counter_fingerprint(state) -> String:
        var keys = state.counters.keys()
        keys.sort()
        var parts = []
        for key in keys:
                var counter = state.counters[key]
                parts.append("%s=%d@%s" % [key, int(counter.count), str(counter.round)])
        return "|".join(parts)


func _task_with_intent(intent: Dictionary) -> Dictionary:
        return {
                "id": "N99",
                "name_key": "task.n99.name",
                "ddl": 8,
                "terms": [1, 2],
                "phases": [{"phase_key": "A", "work": 10, "intents": [intent]}],
        }


func _read_json(path: String) -> Dictionary:
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(parsed) != TYPE_DICTIONARY:
                return {}
        return parsed


func _joined(problems: PackedStringArray) -> String:
        return " / ".join(problems)


func _begin(db, deck: Array, vitality: int, relics: Array = ["A01"]) -> Dictionary:
        var source = RandomSourceScript.new(0)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "RtestFix#1",
                "node_id": "n1",
                "encounter_id": "N01",
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": vitality,
                "max_vitality": 72,
                "cards": deck,
                "relics": relics,
                "rng_state": source.export_state(),
        })


func _deck(definition_id: String, count: int, upgrade_level: int = 0) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "RtestFix#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "RtestFix#R_%s_%d" % [definition_id, index],
                        "upgrade_level": upgrade_level,
                })
        return deck


func _play_id(engine, step: Dictionary, card_id: String) -> Dictionary:
        var state = _state(step)
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_card", {})
        var payload = {"card_id": card_id}
        if not state.tasks.is_empty():
                payload["target_ids"] = [state.tasks[0].task_id]
        return engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": payload,
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
