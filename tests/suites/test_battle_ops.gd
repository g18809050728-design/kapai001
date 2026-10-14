extends RefCounted
##
## 引擎增量一（t9）验收：卡牌 op 与条件系统。
##
## 覆盖《统一设计文档》§5.1（K05/K07/K12）、§5.2（K16/K19）、§5.7（K59）、§5.8（X01）的卡面原文：
## 每张牌一条正向行为 + 一条非法用法（资源不足 / 无合法目标 / 超限次），非法用法零副作用
## （不扣费、不移牌、不推进任务、不消费随机、不留下待选）。
## 另钉：三个选择 kind（discard / recall / purify）共用同一套 pending_choice，一次只允许一个待选，
## K03 的「抽后弃」与 K07/K12 的新选择互不干扰。
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
                h.begin("BattleEngine ops · 前置")
                h.check("MVP 清单加载成功", false, str(loaded))
                return
        h.begin("BattleEngine ops · K05 细心写（条件加值同段合并）")
        _k05(h, db)
        h.begin("BattleEngine ops · K59 临时抱佛脚（DDL 阈值）")
        _k59(h, db)
        h.begin("BattleEngine ops · K07 复盘（弃牌堆选择）")
        _k07(h, db)
        h.begin("BattleEngine ops · K12 转换思路（至多 N + 按实际弃置数抽牌）")
        _k12(h, db)
        h.begin("BattleEngine ops · K16 调试（按类净化 2 层负面）")
        _k16(h, db)
        h.begin("BattleEngine ops · K19 版本控制（保留手牌）")
        _k19(h, db)
        h.begin("BattleEngine ops · X01 分心消息（不可打出）")
        _x01(h, db)
        h.begin("BattleEngine ops · 选择互不干扰（一次只允许一个待选）")
        _choice_isolation(h, db)


# ── K05 细心写 ────────────────────────────────────────────

func _k05(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K04", 1) + _deck("K05", 6)
        var step = _begin_with(db, deck, ["K04", "K05"])
        if not _ok(h, "begin 成功", step):
                return
        _stretch(_state(step))
        var before = _state(step).tasks[0].work_remaining
        step = _play(engine, step, "K04")
        if not _ok(h, "打出 K04", step):
                return
        h.eq("K04 只留打出记录，不产生完成量", _state(step).tasks[0].work_remaining, before)
        # 白盒清掉 K04 顺带给的 2 层灵感，单独量 K05 的条件加值（灵感机制由 test_battle_effects 钉）。
        _clear_status(_state(step), "inspiration")
        var played = _play(engine, step, "K05")
        if not _ok(h, "打出 K05", played):
                return
        h.eq("本回合打过 K04：14+4+A01 首张工作牌 1 = 19", before - _state(played).tasks[0].work_remaining, 19)
        h.eq("加值合进同一段：只结算一次完成", _count_events(played, "completion_applied"), 1)
        h.eq("同一段的完成量就是 19", _event_amount(played, "completion_applied"), 19)

        var solo = _begin_with(db, _deck("K05", 6), ["K05"])
        if not _ok(h, "begin（没打 K04）成功", solo):
                return
        _stretch(_state(solo))
        var before_solo = _state(solo).tasks[0].work_remaining
        var solo_play = _play(engine, solo, "K05")
        h.eq("本回合没打过 K04：14+A01 1 = 15", before_solo - _state(solo_play).tasks[0].work_remaining, 15)

        # 回合作用域：上回合打过的 K04 不算
        var deck_r = _deck("K04", 1) + _deck("K05", 8)
        var step_r = _begin_with(db, deck_r, ["K04", "K05"])
        _stretch(_state(step_r))
        var before_r = _state(step_r).tasks[0].work_remaining
        step_r = _play(engine, step_r, "K04")
        _clear_status(_state(step_r), "inspiration")
        step_r = _play(engine, step_r, "K05")
        h.eq("第 1 回合：19", before_r - _state(step_r).tasks[0].work_remaining, 19)
        step_r = _end_turn(engine, step_r)
        if not _ok(h, "结束第 1 回合", step_r):
                return
        h.eq("进入第 2 回合", _state(step_r).round_index, 2)
        _stretch(_state(step_r))
        var k05_next = _ensure_hand(_state(step_r), "K05")
        h.check("第 2 回合手上有 K05", not k05_next.is_empty())
        var before_r2 = _state(step_r).tasks[0].work_remaining
        var played_r2 = _play_id(engine, step_r, k05_next)
        h.eq("上回合的 K04 不再算：14+A01 1 = 15", before_r2 - _state(played_r2).tasks[0].work_remaining, 15)

        var deck_u = _deck("K04", 1) + _deck("K05", 4, 1)
        var step_u = _begin_with(db, deck_u, ["K04", "K05"])
        _stretch(_state(step_u))
        var before_u = _state(step_u).tasks[0].work_remaining
        step_u = _play(engine, step_u, "K04")
        _clear_status(_state(step_u), "inspiration")
        var played_u = _play(engine, step_u, "K05")
        if _ok(h, "升级 K05 打出", played_u):
                h.eq("升级基础 18 仍保留条件加值：18+4+1 = 23", before_u - _state(played_u).tasks[0].work_remaining, 23)

        var step_bad = _begin_with(db, _deck("K05", 4), ["K05"])
        var state_bad = _state(step_bad)
        _stretch(state_bad)
        state_bad.player.focus = 1
        var card_bad = _hand_card(state_bad, "K05")
        var focus_before = state_bad.player.focus
        var work_before = state_bad.tasks[0].work_remaining
        var illegal = _play_id(engine, step_bad, card_bad)
        h.eq("专注不足被拒", Result.error_code(illegal), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒不扣专注", state_bad.player.focus, focus_before)
        h.eq("被拒不移牌", state_bad.zone_of(card_bad), GameConstants.ZONE_HAND)
        h.eq("被拒不推进任务", state_bad.tasks[0].work_remaining, work_before)


# ── K59 临时抱佛脚 ────────────────────────────────────────

func _k59(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, _deck("K59", 6), ["K59"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        _stretch(state)
        h.eq("N01 基础 DDL 8", state.ddl, 8)
        state.ddl = 3
        var before = state.tasks[0].work_remaining
        var at3 = _play(engine, step, "K59")
        if not _ok(h, "DDL=3 打出 K59", at3):
                return
        h.eq("DDL≤3：12+10+A01 1 = 23", before - _state(at3).tasks[0].work_remaining, 23)
        h.eq("阈值加值同段合并：只结算一次", _count_events(at3, "completion_applied"), 1)
        h.eq("同段完成量就是 23", _event_amount(at3, "completion_applied"), 23)

        var step2 = _begin_with(db, _deck("K59", 6), ["K59"])
        var state2 = _state(step2)
        _stretch(state2)
        state2.ddl = 4
        var before2 = state2.tasks[0].work_remaining
        var at4 = _play(engine, step2, "K59")
        h.eq("DDL=4（高于阈值）：12+A01 1 = 13", before2 - _state(at4).tasks[0].work_remaining, 13)

        var step_u = _begin_with(db, _deck("K59", 4, 1), ["K59"])
        var state_u = _state(step_u)
        _stretch(state_u)
        state_u.ddl = 1
        var before_u = state_u.tasks[0].work_remaining
        var up = _play(engine, step_u, "K59")
        if _ok(h, "升级 K59 打出", up):
                h.eq("升级基础 16+10+1 = 27", before_u - _state(up).tasks[0].work_remaining, 27)

        var step_bad = _begin_with(db, _deck("K59", 4), ["K59"])
        var state_bad = _state(step_bad)
        _stretch(state_bad)
        var card_bad = _hand_card(state_bad, "K59")
        var work_before = state_bad.tasks[0].work_remaining
        var no_target = engine.apply(state_bad, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": card_bad},
        }, step_bad["data"]["rng_state"])
        h.eq("工作牌没有目标被拒", Result.error_code(no_target), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒不移牌", state_bad.zone_of(card_bad), GameConstants.ZONE_HAND)
        h.eq("被拒不推进任务", state_bad.tasks[0].work_remaining, work_before)
        state_bad.player.focus = 1
        var poor = _play_id(engine, step_bad, card_bad)
        h.eq("专注不足被拒", Result.error_code(poor), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒不扣专注", state_bad.player.focus, 1)


# ── K07 复盘 ──────────────────────────────────────────────

func _k07(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K01", 4) + _deck("K07", 4)
        var step = _begin_with(db, deck, ["K01", "K07"])
        if not _ok(h, "begin 成功", step):
                return
        _stretch(_state(step))
        step = _play(engine, step, "K01")
        if not _ok(h, "先打出 K01 造出弃牌堆", step):
                return
        h.eq("弃牌堆 1 张", _state(step).zones.discard.size(), 1)
        var k07 = _hand_card(_state(step), "K07")
        var played = _play(engine, step, "K07")
        if not _ok(h, "打出 K07", played):
                return
        h.eq("费用 1 已扣", _state(played).player.focus, 1)
        var choice = played["data"]["pending_choice"]
        if choice == null:
                h.check("K07 挂起待选", false, "无待选")
                return
        h.eq("choice.kind=recall", String(choice["kind"]), "recall")
        h.eq("prompt_key", String(choice["prompt_key"]), "choice.recall")
        h.eq("恰好选 1 张", [int(choice["min_count"]), int(choice["max_count"])], [1, 1])
        h.eq("候选 = 弃牌堆", _candidate_ids(choice), _state(played).card_ids_in(GameConstants.ZONE_DISCARD))
        h.eq("卡面在待选期间停在结算区", _state(played).zone_of(k07), GameConstants.ZONE_RESOLVING)

        var over = _confirm(engine, played, choice, _candidate_ids(choice) + [_hand_card(_state(played), "K07")])
        h.check("选超 1 张被拒", not Result.is_ok(over))
        h.check("被拒后待选仍在", _state(played).resolution != null)
        var outsider = _confirm(engine, played, choice, [_hand_card(_state(played), "K01")])
        h.eq("选中不在弃牌堆的牌被拒", Result.error_code(outsider), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒后弃牌堆不动", _state(played).zones.discard.size(), 1)
        var blocked = _play_id(engine, played, _hand_card(_state(played), "K07"))
        h.eq("待选期间不能再出牌", Result.error_code(blocked), GameConstants.ERROR_CHOICE_PENDING)
        var end_blocked = _end_turn(engine, played)
        h.eq("待选期间不能结束回合", Result.error_code(end_blocked), GameConstants.ERROR_CHOICE_PENDING)

        var target_id = String(_candidate_ids(choice)[0])
        var done = _confirm(engine, played, choice, [target_id])
        if not _ok(h, "确认取回 1 张", done):
                return
        h.eq("取回的牌回到手牌", _state(done).zone_of(target_id), GameConstants.ZONE_HAND)
        h.eq("K07 耗尽进消耗堆", _state(done).zone_of(k07), GameConstants.ZONE_EXHAUST)
        h.eq("弃牌堆清空", _state(done).zones.discard.size(), 0)

        var second = _hand_card(_state(done), "K07")
        h.check("手上还有第二张 K07", not second.is_empty())
        var focus_before = _state(done).player.focus
        var no_target = _play_id(engine, done, second)
        h.eq("弃牌堆为空时不可用（无目标）", Result.error_code(no_target), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒不扣专注", _state(done).player.focus, focus_before)
        h.eq("被拒不移牌", _state(done).zone_of(second), GameConstants.ZONE_HAND)

        # 升级：费用 0
        var deck_u = _deck("K01", 4) + _deck("K07", 4, 1)
        var step_u = _begin_with(db, deck_u, ["K01", "K07"])
        _stretch(_state(step_u))
        step_u = _play(engine, step_u, "K01")
        var upgraded = _hand_card(_state(step_u), "K07")
        var quote = engine.calculate_cost(_state(step_u), upgraded)
        h.eq("升级费用 0", int(quote["data"]["cost"]), 0)
        var focus_u = _state(step_u).player.focus
        var played_u = _play_id(engine, step_u, upgraded)
        h.check("升级 K07 打出", Result.is_ok(played_u))
        if Result.is_ok(played_u):
                h.eq("费用 0：专注不变", _state(played_u).player.focus, focus_u)
                h.check("升级卡同样挂起 recall 待选", String(played_u["data"]["pending_choice"]["kind"]) == "recall")


# ── K12 转换思路 ──────────────────────────────────────────

func _k12(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K12", 5) + _deck("K01", 8)
        var step = _begin_with(db, deck, ["K12"])
        if not _ok(h, "begin 成功", step):
                return
        _stretch(_state(step))
        var hand_before = _state(step).zones.hand.size()
        var played = _play(engine, step, "K12")
        if not _ok(h, "打出 K12", played):
                return
        var choice = played["data"]["pending_choice"]
        if choice == null:
                h.check("K12 挂起待选", false, "无待选")
                return
        h.eq("choice.kind=discard", String(choice["kind"]), "discard")
        h.eq("至多 2 张：min 0 / max 2", [int(choice["min_count"]), int(choice["max_count"])], [0, 2])
        h.eq("候选 = 手牌", (choice["candidates"] as Array).size(), hand_before - 1)

        var ids = _candidate_ids(choice)
        var too_many = _confirm(engine, played, choice, [ids[0], ids[1], ids[2]])
        h.eq("超过上限被拒", Result.error_code(too_many), GameConstants.ERROR_INVALID_ARGUMENT)
        var dupe = _confirm(engine, played, choice, [ids[0], ids[0]])
        h.eq("重复选择被拒", Result.error_code(dupe), GameConstants.ERROR_INVALID_ARGUMENT)
        var outsider = _confirm(engine, played, choice, [_state(played).tasks[0].task_id])
        h.eq("非候选被拒", Result.error_code(outsider), GameConstants.ERROR_INVALID_TARGET)
        h.eq("非法确认不动手牌", _state(played).zones.hand.size(), hand_before - 1)
        h.eq("非法确认不动弃牌堆", _state(played).zones.discard.size(), 0)

        var done = _confirm(engine, played, choice, [ids[0], ids[1]])
        if not _ok(h, "确认弃 2 张", done):
                return
        var after = _state(done)
        h.eq("弃 2 张 + K12 自身 = 弃牌堆 3", after.zones.discard.size(), 3)
        h.eq("抽实际弃置数+1：手牌 4-2+3 = 5", after.zones.hand.size(), 5)
        h.eq("结算完成无残留", after.resolution == null, true)

        # 至多语义：可以选 0 张
        var state2 = _state(done)
        var k12b = _ensure_hand(state2, "K12")
        h.check("手上还有第二张 K12", not k12b.is_empty())
        var hand2 = state2.zones.hand.size()
        var step2 = _step_like(state2, done)
        var played2 = _play_id(engine, step2, k12b)
        if not _ok(h, "打出第二张 K12", played2):
                return
        var choice2 = played2["data"]["pending_choice"]
        h.eq("可选 0 张仍然挂起待选", int(choice2["min_count"]), 0)
        var zero = _confirm(engine, played2, choice2, [])
        if not _ok(h, "确认弃 0 张", zero):
                return
        h.eq("弃 0 张：抽 0+1，手牌不变", _state(zero).zones.hand.size(), hand2)

        # 升级：获得 2 放松后再执行
        var deck_u = _deck("K12", 3, 1) + _deck("K01", 8)
        var step_u = _begin_with(db, deck_u, ["K12"])
        var played_u = _play(engine, step_u, "K12")
        if not _ok(h, "升级 K12 打出", played_u):
                return
        h.eq("升级：建立待选前已获得 2 放松", _state(played_u).player.relax, 2)
        h.check("升级卡同样挂起待选", played_u["data"]["pending_choice"] != null)

        var step_bad = _begin_with(db, _deck("K12", 4), ["K12"])
        var state_bad = _state(step_bad)
        state_bad.player.focus = 0
        var card_bad = _hand_card(state_bad, "K12")
        var illegal = _play_id(engine, step_bad, card_bad)
        h.eq("专注不足被拒", Result.error_code(illegal), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒不扣专注", state_bad.player.focus, 0)
        h.eq("被拒不移牌", state_bad.zone_of(card_bad), GameConstants.ZONE_HAND)
        h.eq("被拒不产生待选", state_bad.resolution, null)


# ── K16 调试 ──────────────────────────────────────────────

func _k16(h, db) -> void:
        var engine = BattleEngine.new(db)
        var step = _begin_with(db, _deck("K16", 4) + _deck("K01", 8), ["K16"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        _inject_status(state, "anxiety", 2, "prepare")
        _inject_status(state, "drowsiness", 1, "player_action_end")
        var played = _play(engine, step, "K16")
        if not _ok(h, "打出 K16", played):
                return
        var choice = played["data"]["pending_choice"]
        if choice == null:
                h.check("K16 挂起净化待选", false, "无待选")
                return
        h.eq("choice.kind=purify", String(choice["kind"]), "purify")
        h.eq("净化未指定状态时由玩家选其一", [int(choice["min_count"]), int(choice["max_count"])], [1, 1])
        h.eq("候选 = 身上有的可净化负面", _candidate_ids(choice), ["anxiety", "drowsiness"])
        var two = _confirm(engine, played, choice, ["anxiety", "drowsiness"])
        h.eq("一次选两个状态被拒", Result.error_code(two), GameConstants.ERROR_INVALID_ARGUMENT)
        var outsider = _confirm(engine, played, choice, ["compile"])
        h.eq("非可净化状态被拒", Result.error_code(outsider), GameConstants.ERROR_INVALID_TARGET)
        h.eq("非法确认不改状态", _status(_state(played), "anxiety"), 2)
        h.eq("非法确认不加编译", _status(_state(played), "compile"), 0)

        var done = _confirm(engine, played, choice, ["anxiety"])
        if not _ok(h, "确认净化焦虑", done):
                return
        h.eq("焦虑 2 层清空", _status(_state(done), "anxiety"), 0)
        h.eq("不跨状态累计：困倦 1 层保留", _status(_state(done), "drowsiness"), 1)
        h.eq("同段获得 1 编译", _status(_state(done), "compile"), 1)

        # 层数不足：只移除实际有的层数
        var step2 = _begin_with(db, _deck("K16", 4) + _deck("K01", 8), ["K16"])
        var state2 = _state(step2)
        _inject_status(state2, "procrastination", 1, "draw")
        var played2 = _play(engine, step2, "K16")
        var choice2 = played2["data"]["pending_choice"]
        h.eq("只有一个可净化状态时候选 1 个", _candidate_ids(choice2), ["procrastination"])
        var done2 = _confirm(engine, played2, choice2, ["procrastination"])
        h.eq("要求 2 层但只有 1 层：清空该状态", _status(_state(done2), "procrastination"), 0)

        # 无负面状态：仍可打出，卡牌其余部分照常结算
        var step3 = _begin_with(db, _deck("K16", 4) + _deck("K01", 8), ["K16"])
        var played3 = _play(engine, step3, "K16")
        if not _ok(h, "无负面时打出 K16", played3):
                return
        h.eq("无状态不挂起待选", played3["data"]["pending_choice"], null)
        h.eq("无状态仍结算其余部分（+1 编译）", _status(_state(played3), "compile"), 1)
        h.eq("无状态时回合稳定", played3["data"]["stable"], true)

        # 升级：编译 2
        var step_u = _begin_with(db, _deck("K16", 4, 1) + _deck("K01", 8), ["K16"])
        var played_u = _play(engine, step_u, "K16")
        if _ok(h, "升级 K16 打出", played_u):
                h.eq("升级编译 2", _status(_state(played_u), "compile"), 2)


# ── K19 版本控制 ──────────────────────────────────────────

func _k19(h, db) -> void:
        var engine = BattleEngine.new(db)
        # 控制组：规则基线保留上限 0
        var step0 = _begin_with(db, _deck("K01", 20), ["K01"])
        _stretch(_state(step0))
        var keep0 = _hand_card(_state(step0), "K01")
        var denied = _end_turn(engine, step0, [keep0])
        h.eq("规则基线保留上限 0：保留 1 张被拒", Result.error_code(denied), GameConstants.ERROR_INVALID_ARGUMENT)
        h.eq("被拒不推进阶段", String(_state(step0).phase), GameConstants.PHASE_PLAYER_ACTION)

        var step = _begin_with(db, _deck("K19", 4) + _deck("K01", 10), ["K19"])
        if not _ok(h, "begin 成功", step):
                return
        _stretch(_state(step))
        var played = _play(engine, step, "K19")
        if not _ok(h, "打出 K19", played):
                return
        h.eq("获得 5 放松", _state(played).player.relax, 5)
        h.eq("本回合保留额度 +1", _retain_counter(_state(played)), 1)

        var hand_ids = _state(played).card_ids_in(GameConstants.ZONE_HAND)
        h.eq("K19 结算后手牌 4 张", hand_ids.size(), 4)
        var over = _end_turn(engine, played, [String(hand_ids[0]), String(hand_ids[1])])
        h.eq("保留 2 张超限被拒", Result.error_code(over), GameConstants.ERROR_INVALID_ARGUMENT)
        h.eq("被拒后仍在玩家行动", String(_state(played).phase), GameConstants.PHASE_PLAYER_ACTION)
        h.eq("被拒后回合不变", _state(played).round_index, 1)
        h.eq("被拒后手牌不变", _state(played).zones.hand.size(), 4)
        var outsider = _end_turn(engine, played, ["Rtest#not_in_hand"])
        h.eq("保留不在手牌的牌被拒", Result.error_code(outsider), GameConstants.ERROR_INVALID_TARGET)
        var dupe = _end_turn(engine, played, [String(hand_ids[0]), String(hand_ids[0])])
        h.eq("重复保留被拒", Result.error_code(dupe), GameConstants.ERROR_INVALID_ARGUMENT)

        var kept_id = String(hand_ids[0])
        var turned = _end_turn(engine, played, [kept_id])
        if not _ok(h, "保留 1 张结束回合", turned):
                return
        var next = _state(turned)
        h.eq("进入第 2 回合", next.round_index, 2)
        h.eq("保留牌留在手牌", next.zone_of(kept_id), GameConstants.ZONE_HAND)
        h.eq("其余 3 张正常弃置 +1 张 K19", next.zones.discard.size(), 4)
        h.eq("保留 1 + 新抽 5 = 手牌 6", next.zones.hand.size(), 6)

        var keep2 = String(next.card_ids_in(GameConstants.ZONE_HAND)[0])
        var expired = _end_turn(engine, turned, [keep2])
        h.eq("保留额度不跨回合（一次性标记）", Result.error_code(expired), GameConstants.ERROR_INVALID_ARGUMENT)

        var step_u = _begin_with(db, _deck("K19", 4, 1) + _deck("K01", 10), ["K19"])
        _stretch(_state(step_u))
        var played_u = _play(engine, step_u, "K19")
        if _ok(h, "升级 K19 打出", played_u):
                h.eq("升级放松 8", _state(played_u).player.relax, 8)
                h.eq("升级同样给保留额度", _retain_counter(_state(played_u)), 1)


# ── X01 分心消息 ──────────────────────────────────────────

func _x01(h, db) -> void:
        var definition: Dictionary = db.definition(GameConstants.KIND_CARD, "X01")
        h.check("X01 已在清单里启用（N03 add_card 的前置）", db.is_enabled(GameConstants.KIND_CARD, "X01"))
        h.eq("X01 不可打出", bool(definition.get("unplayable", false)), true)
        h.eq("X01 无效果（不是半张牌）", (definition.get("effects", []) as Array).size(), 0)
        h.eq("X01 不进随机品质池：rarity=null", definition.get("rarity"), null)
        h.eq("X01 标签 special/temporary", definition.get("tags"), ["special", "temporary"])
        h.eq("X01 非耗尽（回合末正常弃置）", bool(definition.get("exhaust", false)), false)
        h.eq("X01 没有限次（无被动扣费）", definition.get("limit"), null)

        var engine = BattleEngine.new(db)
        var step = _begin_with(db, _deck("X01", 3) + _deck("K01", 8), ["X01", "K01"])
        if not _ok(h, "begin 成功", step):
                return
        var state = _state(step)
        _stretch(state)
        var x01 = _hand_card(state, "X01")
        h.check("X01 作为战斗牌进入手牌", not x01.is_empty())
        var preview = engine.preview(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": {"card_id": x01},
        })
        h.eq("预览不可提交", bool(preview["data"]["can_submit"]), false)
        h.eq("预览给出 UNPLAYABLE", String((preview["data"]["blocking_errors"][0] as Dictionary)["code"]), GameConstants.ERROR_UNPLAYABLE)
        h.eq("视图标记不可打出", _view_playable(engine.make_view(state), x01), false)

        var focus_before = state.player.focus
        var illegal = _play_id(engine, step, x01)
        h.eq("打出 X01 被拒", Result.error_code(illegal), GameConstants.ERROR_UNPLAYABLE)
        h.eq("被拒不扣专注", state.player.focus, focus_before)
        h.eq("被拒不移牌", state.zone_of(x01), GameConstants.ZONE_HAND)

        var turned = _end_turn(engine, step)
        if not _ok(h, "结束回合", turned):
                return
        var next = _state(turned)
        h.eq("回合末正常弃置", next.zone_of(x01), GameConstants.ZONE_DISCARD)
        h.check("战斗未因 X01 结束", next.outcome == null)
        h.check("X01 没有留下状态副作用", next.find_status(next.player.entity_id, "anxiety") == null)


# ── 选择互不干扰 ──────────────────────────────────────────

func _choice_isolation(h, db) -> void:
        var engine = BattleEngine.new(db)
        var deck = _deck("K03", 3) + _deck("K07", 3)
        var step = _begin_with(db, deck, ["K03", "K07"])
        if not _ok(h, "begin 成功", step):
                return
        _stretch(_state(step))
        var played = _play(engine, step, "K03")
        if not _ok(h, "打出 K03", played):
                return
        var k03_choice = played["data"]["pending_choice"]
        h.eq("K03 待选 kind=discard", String(k03_choice["kind"]), "discard")
        var k07_id = _hand_card(_state(played), "K07")
        h.check("手上同时握着 K07", not k07_id.is_empty())
        var blocked = _play_id(engine, played, k07_id)
        h.eq("待选期间不能再出牌（K07 也不能插队）", Result.error_code(blocked), GameConstants.ERROR_CHOICE_PENDING)
        var end_blocked = _end_turn(engine, played)
        h.eq("待选期间不能结束回合", Result.error_code(end_blocked), GameConstants.ERROR_CHOICE_PENDING)

        var pick = ""
        for candidate_id in _candidate_ids(k03_choice):
                if String(candidate_id) != k07_id:
                        pick = String(candidate_id)
                        break
        h.check("K03 候选里有一张不是 K07 的牌", not pick.is_empty())
        var done = _confirm(engine, played, k03_choice, [pick])
        if not _ok(h, "确认 K03 弃牌", done):
                return
        h.check("K03 结算后没有残留待选", _state(done).resolution == null and done["data"]["pending_choice"] == null)
        h.check("K03 的弃牌进了弃牌堆", _state(done).zones.discard.size() >= 2)

        var played2 = _play_id(engine, done, k07_id)
        if not _ok(h, "接着打出 K07", played2):
                return
        var k07_choice = played2["data"]["pending_choice"]
        h.check("K07 待选登场", k07_choice != null)
        if k07_choice != null:
                h.eq("一次只有一个新的 kind", String(k07_choice["kind"]), "recall")
                h.eq("state.resolution.choice 是同一份真相", String(_state(played2).resolution.choice["kind"]), "recall")
                h.eq("choice_id 与 pending_choice 一致", String(_state(played2).resolution.choice["choice_id"]), String(k07_choice["choice_id"]))


# ── 工具 ──────────────────────────────────────────────────

func _begin(db, deck: Array, vitality: int = 72, max_vitality: int = 72, seed_value: int = 0, relics: Array = ["A01"]) -> Dictionary:
        var source = RandomSourceScript.new(seed_value)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "RtestOps#1",
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
                        "card_id": "RtestOps#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "RtestOps#R_%s_%d" % [definition_id, index],
                        "upgrade_level": upgrade_level,
                })
        return deck


## 把任务工作量放宽到打不死，测试只关心单张牌的结算量。
func _stretch(state) -> void:
        for task in state.tasks:
                task.work_remaining = 400
                task.work_max = 400


func _play(engine, step: Dictionary, definition_id: String) -> Dictionary:
        var card_id = _hand_card(_state(step), definition_id)
        if card_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_card", {"definition_id": definition_id})
        return _play_id(engine, step, card_id)


func _play_id(engine, step: Dictionary, card_id: String) -> Dictionary:
        var state = _state(step)
        var payload = {"card_id": card_id}
        if not state.tasks.is_empty():
                payload["target_ids"] = [state.tasks[0].task_id]
        return engine.apply(state, {
                "type": GameConstants.ACTION_PLAY_CARD,
                "payload": payload,
        }, step["data"]["rng_state"])


func _confirm(engine, step: Dictionary, choice, selected_ids: Array) -> Dictionary:
        if choice == null:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.test.no_choice", {})
        return engine.apply(_state(step), {
                "type": GameConstants.ACTION_CONFIRM_CHOICE,
                "payload": {"choice_id": String(choice["choice_id"]), "selected_ids": selected_ids},
        }, step["data"]["rng_state"])


func _end_turn(engine, step: Dictionary, retained: Array = []) -> Dictionary:
        return engine.apply(_state(step), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {"retained_card_ids": retained},
        }, step["data"]["rng_state"])


## 用某个已结算 step 的 state/rng 造一个等价的 step 外壳（继续在同一个战斗里操作）。
func _step_like(state, step: Dictionary) -> Dictionary:
        return {"data": {"state": state, "rng_state": step["data"]["rng_state"]}}


func _candidate_ids(choice) -> Array:
        var ids = []
        for raw in ((choice as Dictionary).get("candidates", []) as Array):
                ids.append(String((raw as Dictionary).get("id", "")))
        return ids


func _hand_card(state, definition_id: String) -> String:
        for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        return card.card_id
        return ""


func _has_in_hand(state, definition_id: String) -> bool:
        return not _hand_card(state, definition_id).is_empty()


## 确保手上有某定义的牌（不够就从抽牌堆白盒挪一张），返回 card_id。
func _ensure_hand(state, definition_id: String) -> String:
        var existing = _hand_card(state, definition_id)
        if not existing.is_empty():
                return existing
        for raw_id in state.card_ids_in(GameConstants.ZONE_DRAW):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        state.move_card(card.card_id, GameConstants.ZONE_HAND)
                        return card.card_id
        return ""


func _status(state, status_id: String) -> int:
        var status = state.find_status(state.player.entity_id, status_id)
        if status == null:
                return 0
        return int(status.stacks)


func _clear_status(state, status_id: String) -> void:
        var status = state.find_status(state.player.entity_id, status_id)
        if status != null:
                state.statuses.erase(status.status_id)


func _inject_status(state, status_id: String, stacks: int, expiry: String) -> void:
        var status = BattleState.create_status("RtestOps#st_%s" % status_id, status_id, state.player.entity_id, stacks)
        status.expiry = expiry
        state.statuses[status.status_id] = status


func _retain_counter(state) -> int:
        var key = BattleState.counter_key(
                GameConstants.COUNTER_SCOPE_ROUND,
                GameConstants.COUNTER_OWNER_RETAIN,
                GameConstants.COUNTER_TRIGGER_RETAIN
        )
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        return int(counter.count)


func _view_playable(view: Dictionary, card_id: String) -> bool:
        for raw in (view.get("hand", []) as Array):
                var entry: Dictionary = raw
                if String(entry.get("card_id", "")) == card_id:
                        return bool(entry.get("playable", false))
        return false


func _events_of(step: Dictionary, event_type: String) -> Array:
        var out = []
        for raw in (step["data"]["events"] as Array):
                var event: Dictionary = raw
                if String(event.get("type", "")) == event_type:
                        out.append(event)
        return out


func _count_events(step: Dictionary, event_type: String) -> int:
        return _events_of(step, event_type).size()


func _event_amount(step: Dictionary, event_type: String) -> int:
        var events = _events_of(step, event_type)
        if events.is_empty():
                return -1
        return int((events[events.size() - 1] as Dictionary).get("amount", -1))


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, step: Dictionary) -> bool:
        if Result.is_ok(step):
                h.check(label, true)
                return true
        h.check(label, false, str(step.get("error")))
        return false
