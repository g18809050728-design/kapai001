extends RefCounted
##
## 战斗引擎步骤 2 验收：效果内选择与六张牌（《统一设计文档》§3.6 / §5.1）。
## 覆盖：K03 抽2弃1（先抽后选 / 待选期间禁操作）、K04 灵感、K13 每实例每回合限 1 次、
## K14 编译加值、P01 第 3 张工作牌被动、状态到期时点。
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
                h.begin("BattleEngine · 前置")
                h.check("MVP 清单加载成功", false, str(loaded))
                return
        h.begin("BattleEngine · K03 抽2弃1")
        _k03(h, db)
        h.begin("BattleEngine · K04 灵感")
        _k04(h, db)
        h.begin("BattleEngine · K13 每实例每回合限 1 次")
        _k13(h, db)
        h.begin("BattleEngine · K14 编译加值")
        _k14(h, db)
        h.begin("BattleEngine · P01 被动")
        _p01(h, db)
        h.begin("BattleEngine · 状态到期时点")
        _expiry(h, db)


# ── K03 ───────────────────────────────────────────────────

func _k03(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, _deck("K03", 8), ["K03"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        var card_id = _hand_card(state, "K03")
        var play = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card_id},
        }, step["data"]["rng_state"])
        if not _ok(h, "打出 K03", play):
                return
        var after = _state(play)
        h.eq("费用 1 已扣", after.player.focus, 2)
        h.eq("牌进入结算区", after.zone_of(card_id), GameConstants.ZONE_RESOLVING)
        h.check("返回待选", play["data"]["pending_choice"] != null)
        h.eq("stable=false", play["data"]["stable"], false)
        h.eq("阶段 awaiting_choice", after.phase, GameConstants.PHASE_AWAITING_CHOICE)
        var choice = play["data"]["pending_choice"]
        if choice == null:
                return
        h.eq("choice.kind=discard", choice["kind"], "discard")
        h.eq("min_count=1", int(choice["min_count"]), 1)
        h.eq("max_count=1", int(choice["max_count"]), 1)
        h.eq("先抽到再选：5-1+2=6", after.zones.hand.size(), 6)
        h.eq("候选等于抽完后的手牌", (choice["candidates"] as Array).size(), after.zones.hand.size())

        var other = _hand_card(after, "K03")
        var play_while = engine.apply(after, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": other},
        }, play["data"]["rng_state"])
        h.eq("待选期间不能出牌", Result.error_code(play_while), GameConstants.ERROR_CHOICE_PENDING)
        var end_while = engine.apply(after, {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, play["data"]["rng_state"])
        h.eq("待选期间不能结束回合", Result.error_code(end_while), GameConstants.ERROR_CHOICE_PENDING)

        var bad = engine.apply(after, {
                "type": GameConstants.ACTION_CONFIRM_CHOICE,
                "payload": {"choice_id": choice["choice_id"], "selected_ids": []},
        }, play["data"]["rng_state"])
        h.check("选择数量不足被拒", not Result.is_ok(bad))
        h.check("非法确认不清除待选", play["data"]["state"].resolution != null)

        var pick = String((choice["candidates"][0] as Dictionary)["id"])
        var confirmed = engine.apply(after, {
                "type": GameConstants.ACTION_CONFIRM_CHOICE,
                "payload": {"choice_id": choice["choice_id"], "selected_ids": [pick]},
        }, play["data"]["rng_state"])
        if not _ok(h, "确认弃 1 张", confirmed):
                return
        var done = _state(confirmed)
        h.check("结算完成清空 resolution", done.resolution == null)
        h.check("待选清空", confirmed["data"]["pending_choice"] == null)
        h.eq("弃牌堆 = 结算的 K03 + 弃置的 1 张 = 2", done.zones.discard.size(), 2)
        h.eq("手牌 6-1=5", done.zones.hand.size(), 5)
        h.eq("K03 结算后进弃牌堆", done.zone_of(card_id), GameConstants.ZONE_DISCARD)
        h.eq("阶段回到玩家行动", done.phase, GameConstants.PHASE_PLAYER_ACTION)
        h.eq("费用只扣一次", done.player.focus, 2)

        # 升级：抽 3
        var step2 = _begin_with(db, _deck("K03", 8, 1), ["K03"])
        var state2 = _state(step2)
        var card2 = _hand_card(state2, "K03")
        var play2 = engine.apply(state2, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card2},
        }, step2["data"]["rng_state"])
        h.check("升级 K03 成功", Result.is_ok(play2))
        if Result.is_ok(play2):
                h.eq("升级抓 3：4+3=7", _state(play2).zones.hand.size(), 7)


# ── K04 ───────────────────────────────────────────────────

func _k04(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K04", 3) + _deck("K01", 5)
        var step = _begin_with(db, deck, ["K04", "K01"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        var k04 = _hand_card(state, "K04")
        var play = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k04},
        }, step["data"]["rng_state"])
        if not _ok(h, "打出 K04", play):
                return
        h.eq("获得 2 层灵感", _status(_state(play), "inspiration"), 2)
        var work_before = _state(play).tasks[0].work_remaining
        var work = _play(engine, play, "K01")
        if not _ok(h, "打出 K01", work):
                return
        h.eq("灵感 2 层 +4：6+4+A01 1=11", work_before - _state(work).tasks[0].work_remaining, 11)
        h.eq("打出工作牌后灵感清空", _status(_state(work), "inspiration"), 0)

        var step2 = _begin_with(db, deck, ["K04"])
        var state2 = _state(step2)
        var k04b = _hand_card(state2, "K04")
        var play2 = engine.apply(state2, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k04b},
        }, step2["data"]["rng_state"])
        h.eq("未用灵感 2 层", _status(_state(play2), "inspiration"), 2)
        var turned = engine.apply(_state(play2), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, play2["data"]["rng_state"])
        h.eq("未用灵感轮末清除", _status(_state(turned), "inspiration"), 0)


# ── K13 ───────────────────────────────────────────────────

func _k13(h, db) -> void:
        var engine = BattleEngine.new(db)
        var origin = "Rtest#RSpecK13"
        var step = _begin(db, _deck_same_origin("K13", 5, origin))
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        h.eq("5 张同实例 K13 全在手", state.zones.hand.size(), 5)
        var first = _hand_card(state, "K13")
        var play1 = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": first},
        }, step["data"]["rng_state"])
        if not _ok(h, "第一张 K13 打出", play1):
                return
        h.eq("获得 1 编译", _compile(_state(play1)), 1)

        var second = _hand_card(_state(play1), "K13")
        var play2 = engine.apply(_state(play1), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": second},
        }, play1["data"]["rng_state"])
        h.eq("同一原始实例本回合第二次被拒", Result.error_code(play2), GameConstants.ERROR_LIMIT_REACHED)
        h.eq("被拒不获得编译", _compile(_state(play1)), 1)
        h.eq("被拒不移牌", _state(play1).zone_of(second), GameConstants.ZONE_HAND)

        var turned = engine.apply(_state(play1), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, play1["data"]["rng_state"])
        if not _ok(h, "结束回合", turned):
                return
        h.eq("进入第 2 回合", _state(turned).round_index, 2)
        h.eq("第 2 回合重新抽 5 张", _state(turned).zones.hand.size(), 5)
        var third = _hand_card(_state(turned), "K13")
        var play3 = engine.apply(_state(turned), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": third},
        }, turned["data"]["rng_state"])
        h.check("下回合同实例可再次打出", Result.is_ok(play3))
        if Result.is_ok(play3):
                h.eq("编译累加到 2", _compile(_state(play3)), 2)


# ── K14 ───────────────────────────────────────────────────

func _k14(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K13", 2) + _deck("K14", 3)
        var step = _begin_with(db, deck, ["K13", "K14"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        var k13 = _hand_card(state, "K13")
        var s1 = engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k13},
        }, step["data"]["rng_state"])
        h.eq("先获得 1 编译", _compile(_state(s1)), 1)
        var work_before = _state(s1).tasks[0].work_remaining
        var k14 = _hand_card(_state(s1), "K14")
        var s2 = engine.apply(_state(s1), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k14, "target_ids": [_state(s1).tasks[0].task_id]},
        }, s1["data"]["rng_state"])
        if not _ok(h, "打出 K14", s2):
                return
        h.eq("编译>=1 同段 +3：5+3+A01 1=9", work_before - _state(s2).tasks[0].work_remaining, 9)
        h.eq("K14 不消耗编译", _compile(_state(s2)), 1)

        var deck_u = _deck("K13", 2) + _deck("K14", 3, 1)
        var step_u = _begin_with(db, deck_u, ["K13", "K14"])
        var state_u = _state(step_u)
        var k13u = _hand_card(state_u, "K13")
        var su1 = engine.apply(state_u, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k13u},
        }, step_u["data"]["rng_state"])
        var before_u = _state(su1).tasks[0].work_remaining
        var k14u = _hand_card(_state(su1), "K14")
        var su2 = engine.apply(_state(su1), {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k14u, "target_ids": [_state(su1).tasks[0].task_id]},
        }, su1["data"]["rng_state"])
        if _ok(h, "升级 K14 打出", su2):
                h.eq("升级基础 7：7+3+1=11", before_u - _state(su2).tasks[0].work_remaining, 11)


# ── P01 ───────────────────────────────────────────────────

func _p01(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, _deck("K01", 10), ["K01"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        state.tasks[0].work_remaining = 200
        state.tasks[0].work_max = 200

        step = _play(engine, step, "K01")
        step = _play(engine, step, "K01")
        step = _play(engine, step, "K01")
        h.eq("第 3 张工作牌结算后获得 1 编译", _compile(_state(step)), 1)
        h.eq("同回合被动只触发一次", _passive_fired(_state(step)), 1)

        step = _end_turn(engine, step)
        if not _ok(h, "结束回合", step):
                return
        step = _play(engine, step, "K01")
        step = _play(engine, step, "K01")
        step = _play(engine, step, "K01")
        h.eq("第 2 回合再次触发：编译 2", _compile(_state(step)), 2)
        h.eq("第 2 回合被动计数重置为 1", _passive_fired(_state(step)), 1)


# ── 状态到期 ──────────────────────────────────────────────

func _expiry(h, db) -> void:
        var engine = BattleEngine.new(db)

        var step = _begin(db, _deck("K01", 6))
        var state = _state(step)
        _inject_status(state, state.player.entity_id, "anxiety", 2, "prepare")
        var turned = engine.apply(state, {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, step["data"]["rng_state"])
        h.eq("焦虑 2：回合专注 3-2=1", _state(turned).player.focus, 1)
        h.eq("焦虑生效后清除", _status(_state(turned), "anxiety"), 0)

        var step2 = _begin(db, _deck("K01", 12))
        var state2 = _state(step2)
        _inject_status(state2, state2.player.entity_id, "procrastination", 2, "draw")
        var turned2 = engine.apply(state2, {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, step2["data"]["rng_state"])
        h.eq("拖延 2：下回合抽 5-2=3", _state(turned2).zones.hand.size(), 3)
        h.eq("拖延生效后清除", _status(_state(turned2), "procrastination"), 0)

        var step3 = _begin_with(db, _deck("K01", 6), ["K01"])
        var state3 = _state(step3)
        _inject_status(state3, state3.player.entity_id, "drowsiness", 2, "player_action_end")
        var played = _play(engine, step3, "K01")
        h.eq("困倦 2：6+A01 1-2=5", 24 - _state(played).tasks[0].work_remaining, 5)
        h.eq("困倦在行动结束清除", _status(_state(played), "drowsiness"), 0)

        var step4 = _begin_with(db, _deck("K04", 2) + _deck("K01", 4), ["K04"])
        var state4 = _state(step4)
        var k04 = _hand_card(state4, "K04")
        var played4 = engine.apply(state4, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": k04},
        }, step4["data"]["rng_state"])
        h.eq("灵感 2 层", _status(_state(played4), "inspiration"), 2)
        var turned4 = engine.apply(_state(played4), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, played4["data"]["rng_state"])
        h.eq("未用灵感在轮末清除", _status(_state(turned4), "inspiration"), 0)


# ── 工具 ──────────────────────────────────────────────────

func _begin(db, deck: Array, vitality: int = 72, max_vitality: int = 72, seed_value: int = 0, relics: Array = ["A01"]) -> Dictionary:
        var source = RandomSourceScript.new(seed_value)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "Rtest#1",
                "node_id": "n1",
                "encounter_id": "N01",
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": vitality,
                "max_vitality": max_vitality,
                "cards": deck,
                "relics": relics,
                "rng_state": source.export_state(),
        })


## 找一个能把手牌凑齐 needed 的种子，避免测试依赖洗牌顺序。
func _begin_with(db, deck: Array, needed: Array) -> Dictionary:
        for seed_value in range(0, 80):
                var step = _begin(db, deck, 72, 72, seed_value)
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
        return _begin(db, deck, 72, 72, 0)


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


## 同原始卡实例的多张战斗牌，用于验证「按原始卡实例限次」。
func _deck_same_origin(definition_id: String, count: int, origin: String) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "Rtest#SameOrigin_%d" % index,
                        "definition_id": definition_id,
                        "origin_card_id": origin,
                        "upgrade_level": 0,
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


func _status(state, status_id: String) -> int:
        var status = state.find_status(state.player.entity_id, status_id)
        if status == null:
                return 0
        return int(status.stacks)


func _compile(state) -> int:
        return _status(state, GameConstants.STATUS_COMPILE)


func _passive_fired(state) -> int:
        var key = BattleState.counter_key("round", "p01_third_work_compile", "fired")
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        return int(counter.count)


func _inject_status(state, holder_id: String, status_id: String, stacks: int, expiry: String) -> void:
        var status = BattleState.create_status("Rtest#st_" + status_id, status_id, holder_id, stacks)
        status.expiry = expiry
        state.statuses[status.status_id] = status


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, step: Dictionary) -> bool:
        if Result.is_ok(step):
                h.check(label, true)
                return true
        h.check(label, false, str(step.get("error")))
        return false