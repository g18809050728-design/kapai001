extends RefCounted
##
## 引擎增量二（t10）验收：人物被动 trigger / 饰品 hook / 事件 op。
##
## 覆盖《统一设计文档》§4（P04 被动）、§8（A04/A05/A07/A08/A11/A15/A18 七件饰品）与 §10.2
## （V03/V04 的目标过滤与显式卡池）。每个 hook 一条正向断言；限次类都配「第二次不再触发」反向断言；
## 事件 op 的失败路径断言「先校验、后提交」——非法选择不扣钱、不扣精力、不动牌组。
##
## 白盒说明（沿审查套件惯例）：为了让时序与目标可复现，本套件会改写自己持有的
## BattleState / RunState（挪牌、置换节点 kind、注入事件实例与冻结候选）——只动测试态。
##

const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const BattleCardRules := preload("res://src/battle/card_rules.gd")
const RunServiceScript := preload("res://src/run/run_service.gd")
const RunNodeStateScript := preload("res://src/run/run_node_state.gd")
const ShopStateScript := preload("res://src/run/run_shop_state.gd")
const EventStateScript := preload("res://src/run/run_event_state.gd")
const TransactionResolverScript := preload("res://src/run/transaction_resolver.gd")
const RandomSourceScript := preload("res://src/common/random_source.gd")
const Result := preload("res://src/common/result.gd")
const GameConstants := preload("res://src/common/game_constants.gd")

const SEED := 20260210


func run(h) -> void:
        var db := ContentDB.new()
        var loaded = db.load(GameConstants.MANIFEST_MVP)
        if not Result.is_ok(loaded):
                h.begin("t10 前置")
                h.check("MVP 清单加载成功", false, str(loaded))
                return
        h.begin("t10 · P04 被动（合作牌结算，备考面也触发）")
        _passive_p04(h, db)
        h.begin("t10 · P01 被动回归（第 3 张工作牌）")
        _passive_p01_regression(h, db)
        h.begin("t10 · A04 费用减免走数据驱动 hook")
        _relic_a04(h, db)
        h.begin("t10 · A05 / A18 回合开始恢复精力")
        _relic_round_start(h, db)
        h.begin("t10 · A07 第 1 回合额外抽 2（受手牌上限）")
        _relic_a07(h, db)
        h.begin("t10 · A08 免除本战首次 K10 精力支付")
        _relic_a08(h, db)
        h.begin("t10 · A11 每回合首张策略牌结算后 +2 放松")
        _relic_a11(h, db)
        h.begin("t10 · A15 商店报价 ×0.8 向上取整")
        _relic_a15(h, db)
        # 事件 op 用冻结夹具 test_events：出厂 mvp 的 event 组由 content 的 t11 与界面回归一起启用
        var event_db := ContentDB.new()
        var event_loaded = event_db.load("test_events")
        if not Result.is_ok(event_loaded):
                h.begin("t10 前置 · 事件夹具")
                h.check("test_events 清单加载成功", false, str(event_loaded))
        else:
                h.begin("t10 · 事件 gain_card 显式卡池三选一")
                _event_card_pool(h, event_db)
                h.begin("t10 · 事件 remove_card / upgrade_card 目标过滤")
                _event_filters(h, event_db)


# ── P04 / P01 被动 ────────────────────────────────────────

func _passive_p04(h, db) -> void:
        var deck = _deck("K43", 4) + _deck("K01", 8)
        var step = _begin_with(db, deck, ["K43"], "P04", "N01", ["A04"])
        if not _ok(h, "begin 成功（P04）", step):
                return
        _stretch(_state(step))
        var played = _play(engine_of(db), step, "K43")
        if not _ok(h, "打出合作牌 K43", played):
                return
        h.eq("每回合首张合作牌结算后 +2 放松", _state(played).player.relax, 2)
        h.eq("计数键走 TriggerCounter", _passive_count(_state(played), "p04_first_cooperation_relax", "cooperation_resolved"), 1)

        var second = _play(engine_of(db), played, "K43")
        if _ok(h, "同回合第二张合作牌", second):
                h.eq("同回合第二张不再触发（回合限 1 次）", _state(second).player.relax, 2)

        # 跨回合重置
        var turned = _end_turn(engine_of(db), played)
        if not _ok(h, "结束回合", turned):
                return
        h.eq("第 2 回合放松清零", _state(turned).player.relax, 0)
        var again = _play(engine_of(db), turned, "K43")
        if _ok(h, "第 2 回合再打合作牌", again):
                h.eq("新回合重新触发 +2", _state(again).player.relax, 2)

        # 备考面：B01 的独立作答把合作牌正文换成 relax 5，类型仍是 cooperation → 被动照样触发
        var exam = _begin_with(db, _deck("K44", 4) + _deck("K01", 8), ["K44"], "P04", "B01", ["A04"])
        if not _ok(h, "begin 成功（B01 备考面）", exam):
                return
        var exam_played = _play(engine_of(db), exam, "K44")
        if not _ok(h, "备考面打出 K44", exam_played):
                return
        h.eq("备考面正文 5 放松 + 被动 2 = 7", _state(exam_played).player.relax, 7)
        h.eq("备考面按 1 费结算（A04 减免 1）", _state(exam_played).player.focus, 2)
        h.check("备考面不召入单位", _state(exam_played).units.is_empty())


func _passive_p01_regression(h, db) -> void:
        var step = _begin_with(db, _deck("K01", 12), ["K01"], "P01", "N01", ["A01"])
        if not _ok(h, "begin 成功（P01）", step):
                return
        _stretch(_state(step))
        step = _play(engine_of(db), step, "K01")
        step = _play(engine_of(db), step, "K01")
        step = _play(engine_of(db), step, "K01")
        h.eq("P01 第 3 张工作牌仍 +1 编译", _status(_state(step), GameConstants.STATUS_COMPILE), 1)
        h.eq("P01 计数键不变", _passive_count(_state(step), "p01_third_work_compile", "work_resolved"), 3)


# ── 饰品 hook ─────────────────────────────────────────────

func _relic_a04(h, db) -> void:
        var step = _begin_with(db, _deck("K44", 4) + _deck("K01", 8), ["K44"], "P01", "N01", ["A04"])
        if not _ok(h, "begin 成功（A04）", step):
                return
        var state = _state(step)
        var k44 = _hand_card(state, "K44")
        var face = engine_of(db).resolve_face(state, k44)
        var quote = BattleCardRules.cost_quote(db, state, face["data"])
        h.eq("首张合作牌费用 2-1=1", int(quote["cost"]), 1)
        h.check("减免来源记在 sources", (quote["sources"] as Array).has("relic_hook:A04:0"))
        quote = BattleCardRules.cost_quote(db, state, face["data"])
        h.eq("报价不消费限次（可重复调用）", int(quote["cost"]), 1)

        var first = _play_id(engine_of(db), step, k44)
        if not _ok(h, "打出首张合作牌", first):
                return
        h.eq("首张实际支付 1：专注 3-1=2", _state(first).player.focus, 2)
        h.eq("限次计数已消费", _hook_count(_state(first), "A04", 0), 1)
        var second = _play(engine_of(db), first, "K44")
        if _ok(h, "打出第二张合作牌", second):
                h.eq("第二张按原价：专注 2-2=0", _state(second).player.focus, 0)
                h.eq("第二张不再消费限次", _hook_count(_state(second), "A04", 0), 1)


func _relic_round_start(h, db) -> void:
        var start := 40
        var a05 := _round_deltas(db, ["A05"], 7, start)
        var a18 := _round_deltas(db, ["A18"], 7, start)
        var none := _round_deltas(db, [], 7, start)
        if none.is_empty() or a05.is_empty() or a18.is_empty():
                h.check("回合轨迹可读", false, "begin/end_turn 失败")
                return
        h.eq("A05：第 3 回合开始多恢复 3 精力", int(a05[2]) - int(none[2]), 3)
        h.eq("A05：第 2 回合不触发", int(a05[1]) - int(none[1]), 0)
        h.eq("A05：第 4 回合不触发", int(a05[3]) - int(none[3]), 0)
        h.eq("A05：第 6 回合开始再恢复 3", int(a05[5]) - int(none[5]), 3)
        h.eq("A18：第 1 回合开始多恢复 1 精力", int(a18[0]) - int(none[0]), 1)
        h.eq("A18：第 2 回合仍 +1", int(a18[1]) - int(none[1]), 1)
        h.eq("A18：第 3 回合仍 +1", int(a18[2]) - int(none[2]), 1)
        h.eq("A18：第 4 回合不触发", int(a18[3]) - int(none[3]), 0)


func _relic_a07(h, db) -> void:
        var with_a07 := _hand_sizes(db, ["A07"], 2)
        var control := _hand_sizes(db, [], 2)
        if control.is_empty():
                return
        h.eq("第 1 回合额外抽 2：5+2=7", int(with_a07[0]), 7)
        h.eq("对照：无 A07 时第 1 回合抽 5", int(control[0]), 5)
        h.eq("第 2 回合不再多抽", int(with_a07[1]), int(control[1]))


func _relic_a08(h, db) -> void:
        var step = _begin_with(db, _deck("K10", 4) + _deck("K01", 6), ["K10"], "P01", "N01", ["A08"], 4)
        if not _ok(h, "begin 成功（精力 4 + A08）", step):
                return
        var state = _state(step)
        var k10 = _hand_card(state, "K10")
        var face = engine_of(db).resolve_face(state, k10)
        var quote = BattleCardRules.cost_quote(db, state, face["data"])
        h.eq("首张 K10 精力代价被免除", int(quote["vitality_cost"]), 0)
        var played = _play_id(engine_of(db), step, k10)
        if not _ok(h, "[RB-04/T04] 精力 4 打 K10 应可打出（免除支付）", played):
                return
        h.eq("免支付：精力仍是 4", _state(played).player.vitality, 4)
        h.eq("获得 2 专注：3+2=5", _state(played).player.focus, 5)
        h.eq("A08 本战次数已消费", _hook_count(_state(played), "A08", 0), 1)

        var second = _ensure_hand(_state(played), "K10")
        var denied = _play_id(engine_of(db), played, second)
        h.eq("第二张 K10 不再免支付：支付后不足 1 → 被拒", Result.error_code(denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)
        h.eq("被拒后精力仍 4", _state(played).player.vitality, 4)
        h.eq("被拒后牌仍在手", _state(played).zone_of(second), GameConstants.ZONE_HAND)

        var control = _begin_with(db, _deck("K10", 4) + _deck("K01", 6), ["K10"], "P01", "N01", [], 4)
        var control_denied = _play_id(engine_of(db), control, _hand_card(_state(control), "K10"))
        h.eq("对照：无 A08 时被拒", Result.error_code(control_denied), GameConstants.ERROR_INSUFFICIENT_RESOURCE)


func _relic_a11(h, db) -> void:
        var step = _begin_with(db, _deck("K02", 4) + _deck("K01", 8), ["K02"], "P01", "N01", ["A11"])
        if not _ok(h, "begin 成功（A11）", step):
                return
        var first = _play(engine_of(db), step, "K02")
        if not _ok(h, "打出首张策略牌 K02", first):
                return
        h.eq("首张策略牌结算后 +2 放松：5+2=7", _state(first).player.relax, 7)
        var second = _play(engine_of(db), first, "K02")
        if _ok(h, "打出第二张策略牌", second):
                h.eq("同回合第二张不再 +2：7+5=12", _state(second).player.relax, 12)
        var turned = _end_turn(engine_of(db), first)
        if not _ok(h, "结束回合", turned):
                return
        h.eq("新回合放松清零（场景/单位不干扰）", _state(turned).player.relax, 0)
        var again = _play(engine_of(db), turned, "K02")
        if _ok(h, "第 2 回合再打策略牌", again):
                h.eq("新回合重新 +2：5+2=7", _state(again).player.relax, 7)


func _relic_a15(h, db) -> void:
        var card_price: int = int((db.section("shop").get("card_prices", {}) as Dictionary).get("white", 0))
        var relic_price: int = int((db.section("shop").get("relic_prices", {}) as Dictionary).get("white", 0))
        var meal_price: int = int(db.section("shop").get("meal_price", 0))

        var control := _shop_run(db, [])
        if control.is_empty():
                h.check("对照商店就绪", false, "create/enter 失败")
                return
        h.eq("对照：白卡原价", _stock_price(control, ShopStateScript.STOCK_CARD), card_price)
        h.eq("对照：白饰品原价", _stock_price(control, ShopStateScript.STOCK_RELIC), relic_price)
        h.eq("对照：餐食原价", _stock_price(control, ShopStateScript.STOCK_MEAL), meal_price)

        var discounted := _shop_run(db, ["A15"])
        if discounted.is_empty():
                h.check("A15 商店就绪", false, "create/enter 失败")
                return
        h.eq("卡牌 35 ×0.8 = 28", _stock_price(discounted, ShopStateScript.STOCK_CARD), int(ceil(float(card_price) * 0.8)))
        h.eq("饰品 80 ×0.8 = 64", _stock_price(discounted, ShopStateScript.STOCK_RELIC), int(ceil(float(relic_price) * 0.8)))
        h.eq("餐食不受影响", _stock_price(discounted, ShopStateScript.STOCK_MEAL), meal_price)
        h.eq("删牌费不受影响", int((_shop_view(discounted)["removal"] as Dictionary)["price"]), 60)

        # 向上取整：用合成库存验非整数场景（真商店价格 ×0.8 恰好都是整数）
        var tx := TransactionResolverScript.new(db)
        var run = discounted["run"]
        var odd_stock = ShopStateScript.create("shoptodd#1", "n1")
        odd_stock.add_stock("shoptodd#1|relic0", ShopStateScript.STOCK_RELIC, "A05", 33)
        h.eq("33 ×0.8 = 26.4 → ceil 27（不是 floor 26）", tx.quote_price(run, odd_stock.find_stock("shoptodd#1|relic0")), 27)

        # 成交价 = 界面标价（同一套报价函数）
        run.money = 300
        var stock_id := _first_stock_id(discounted, ShopStateScript.STOCK_CARD)
        var displayed := _stock_price(discounted, ShopStateScript.STOCK_CARD)
        var bought = (discounted["svc"] as Object).apply(run, {
                "type": GameConstants.ACTION_BUY_ITEM,
                "payload": {"stock_id": stock_id},
        }, discounted["rng"])
        if not _ok(h, "买入卡牌", bought):
                return
        h.eq("扣钱 = 界面标价：300-28=272", _state(bought).money, 300 - displayed)


# ── 事件 op ───────────────────────────────────────────────

func _event_card_pool(h, db) -> void:
        var ctx := _event_run(db, "V03", [])
        if ctx.is_empty():
                h.check("V03 事件节点就绪", false, "create/enter 失败")
                return
        var instance = ctx["instance"]
        h.eq("显式卡池被冻结成 3 个候选", instance.candidates_for("consult"), ["K14", "K05", "K60"])
        var consult := _option_view(_shop_or_event_view(ctx), "consult")
        h.eq("视图暴露候选 = 显式卡池", consult["candidates"], ["K14", "K05", "K60"])
        h.eq("consult 不需要卡实例选择", (consult["selection_candidates"] as Array).size(), 0)
        h.eq("consult 现在可用", consult["enabled"], true)

        var before_cards: int = (ctx["run"] as Object).cards.size()
        var before_money: int = int((ctx["run"] as Object).money)
        var bad = _choose(ctx, "consult", ["K01"])
        h.eq("选池外的牌被拒", Result.error_code(bad), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒后牌组不变", (ctx["run"] as Object).cards.size(), before_cards)
        h.eq("被拒后生活费不变", int((ctx["run"] as Object).money), before_money)
        h.eq("被拒后事件未结算", String(instance.resolved_option_id), "")

        # rarity 路径的冻结必须真的发生且非空（verifier E04：候选数量 ≥1 才算非平凡通过）
        var v01 := _event_run(db, "V01", [])
        if v01.is_empty():
                h.check("V01 事件节点就绪", false, "create/enter 失败")
        else:
                var play_candidates: Array = (v01["instance"] as Object).candidates_for("play")
                h.check("V01 蓝卡池冻结出 ≥1 个候选（E04）", play_candidates.size() >= 1, str(play_candidates))
                var real_cards := 0
                for candidate_id in play_candidates:
                        if not (db.definition(GameConstants.KIND_CARD, String(candidate_id)) as Dictionary).is_empty():
                                real_cards += 1
                h.eq("候选都是清单里的真卡", real_cards, play_candidates.size())
                var again_view: Dictionary = (v01["svc"] as Object).make_view(v01["run"])
                h.eq("重开界面不重抽（同一份冻结）", _option_view(again_view.get("event", {}), "play")["candidates"], play_candidates)

        var chosen = _choose(ctx, "consult", ["K05"])
        if not _ok(h, "选 K05", chosen):
                return
        var after = _state(chosen)
        h.eq("牌组 +1", after.cards.size(), before_cards + 1)
        h.check("拿到的是 K05", _has_definition(after, "K05"))
        h.eq("事件已结算", String(after.current_node().context["event"].resolved_option_id), "consult")


func _event_filters(h, db) -> void:
        # V03「删 1 张基础牌并支付 5 精力」
        var ctx := _event_run(db, "V03", [])
        if ctx.is_empty():
                h.check("V03 事件节点就绪", false, "create/enter 失败")
                return
        var run = ctx["run"]
        var strategy_id := _card_id_of_definition(run, "K13")
        var basic_id := _card_id_of_definition(run, "K01")
        h.check("牌组里有基础牌与非基础牌", not strategy_id.is_empty() and not basic_id.is_empty())
        var drop := _option_view(_shop_or_event_view(ctx), "drop")
        h.check("drop 只给基础牌候选", (drop["selection_candidates"] as Array).has(basic_id))
        h.check("drop 不给非基础牌候选", not (drop["selection_candidates"] as Array).has(strategy_id))
        h.eq("drop 可用（有基础牌）", drop["enabled"], true)

        run.vitality = 72
        var before_cards: int = run.cards.size()
        var illegal = _choose(ctx, "drop", [strategy_id])
        h.eq("删非基础牌被拒", Result.error_code(illegal), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒不扣精力（先校验后提交）", int(run.vitality), 72)
        h.eq("被拒不删牌", run.cards.size(), before_cards)
        h.eq("被拒后事件仍未结算", String(ctx["instance"].resolved_option_id), "")

        var removed = _choose(ctx, "drop", [basic_id])
        if not _ok(h, "删基础牌", removed):
                return
        var after = _state(removed)
        h.eq("删掉 1 张", after.cards.size(), before_cards - 1)
        h.eq("支付 5 精力：72-5=67", int(after.vitality), 67)

        # 牌组全非基础牌时：drop 在视图层就被判不可用（无合法候选）
        var blocked := _event_run(db, "V03", [])
        if blocked.is_empty():
                return
        var blocked_run = blocked["run"]
        # 换成 6 张非基础牌（高于牌组下限 5，否则先被 deck_minimum 拦住）
        blocked_run.cards = []
        for definition_id in ["K13", "K14", "K05", "K12", "K19", "K16"]:
                blocked_run.add_card(String(definition_id), 0, "test")
        blocked_run.vitality = 72
        var blocked_view: Dictionary = (blocked["svc"] as Object).make_view(blocked_run)
        var blocked_drop := _option_view(blocked_view.get("event", {}), "drop")
        h.eq("没有基础牌时 drop 不可用", blocked_drop["enabled"], false)
        h.check("阻断原因写明没有合法目标", (blocked_drop["blocking"] as Array).has("error.event.no_remove_target"))
        var blocked_choice = _choose(blocked, "drop", [_card_id_of_definition(blocked_run, "K13")])
        h.eq("没有合法目标时提交也被拒", Result.error_code(blocked_choice), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒后精力不变", int(blocked_run.vitality), 72)

        # V04「支付 6 精力，升级 1 张工作牌」
        var pay := _event_run(db, "V04", [])
        if pay.is_empty():
                return
        var pay_run = pay["run"]
        var work_id := _card_id_of_definition(pay_run, "K01")
        var strategy_id_v4 := _card_id_of_definition(pay_run, "K13")
        var pay_option := _option_view(_shop_or_event_view(pay), "pay")
        h.check("pay 只给工作牌候选", (pay_option["selection_candidates"] as Array).has(work_id))
        h.check("pay 不给策略牌候选", not (pay_option["selection_candidates"] as Array).has(strategy_id_v4))
        pay_run.vitality = 72
        var bad_upgrade = _choose(pay, "pay", [strategy_id_v4])
        h.eq("升级非工作牌被拒", Result.error_code(bad_upgrade), GameConstants.ERROR_INVALID_TARGET)
        h.eq("被拒不扣精力", int(pay_run.vitality), 72)
        h.eq("被拒不改升级等级", _card_upgrade(pay_run, strategy_id_v4), 0)
        var upgraded = _choose(pay, "pay", [work_id])
        if not _ok(h, "升级工作牌", upgraded):
                return
        var upgraded_state = _state(upgraded)
        h.eq("工作牌升级 +1", _card_upgrade(upgraded_state, work_id), 1)
        h.eq("支付 6 精力：72-6=66", int(upgraded_state.vitality), 66)


# ── 工具：战斗侧 ──────────────────────────────────────────

func engine_of(db):
        return BattleEngine.new(db)


func _begin(db, deck: Array, relics: Array, character_id: String, encounter_id: String, vitality: int, seed_value: int) -> Dictionary:
        var source = RandomSourceScript.new(seed_value)
        var engine = BattleEngine.new(db)
        return engine.begin({
                "battle_id": "RtestHooks#1",
                "node_id": "n1",
                "encounter_id": encounter_id,
                "character_id": character_id,
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "vitality": vitality,
                "max_vitality": 72,
                "cards": deck,
                "relics": relics,
                "rng_state": source.export_state(),
        })


func _begin_with(db, deck: Array, needed: Array, character_id: String, encounter_id: String, relics: Array, vitality: int = 72) -> Dictionary:
        for seed_value in range(0, 80):
                var step = _begin(db, deck, relics, character_id, encounter_id, vitality, seed_value)
                if not Result.is_ok(step):
                        continue
                var ok = true
                for definition_id in needed:
                        if _hand_card(_state(step), String(definition_id)).is_empty():
                                ok = false
                                break
                if ok:
                        return step
        return _begin(db, deck, relics, character_id, encounter_id, vitality, 0)


func _deck(definition_id: String, count: int, upgrade_level: int = 0) -> Array:
        var deck = []
        for index in range(count):
                deck.append({
                        "card_id": "RtestHooks#B_%s_%d" % [definition_id, index],
                        "definition_id": definition_id,
                        "origin_card_id": "RtestHooks#R_%s_%d" % [definition_id, index],
                        "upgrade_level": upgrade_level,
                })
        return deck


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


func _end_turn(engine, step: Dictionary) -> Dictionary:
        return engine.apply(_state(step), {
                "type": GameConstants.ACTION_END_TURN,
                "payload": {},
        }, step["data"]["rng_state"])


## 逐回合记录每回合「玩家准备之后」的精力，返回相对上一回合的增量。
## 不主动出牌，只结束回合；起手 40（低于上限 72，避免满血裁切掩盖恢复量）。
func _round_deltas(db, relics: Array, rounds: int, start: int) -> Array:
        var step = _begin(db, _deck("K01", 30), relics, "P01", "N01", start, 7)
        if not Result.is_ok(step):
                return []
        var track := [int(_state(step).player.vitality)]
        for _index in range(rounds - 1):
                step = _end_turn(engine_of(db), step)
                if not Result.is_ok(step):
                        break
                track.append(int(_state(step).player.vitality))
        var deltas := []
        var previous := start
        for value in track:
                deltas.append(int(value) - previous)
                previous = int(value)
        return deltas


func _hand_sizes(db, relics: Array, rounds: int) -> Array:
        var step = _begin(db, _deck("K01", 30), relics, "P01", "N01", 72, 7)
        if not Result.is_ok(step):
                return []
        var sizes := [_state(step).zones.hand.size()]
        for _index in range(rounds - 1):
                step = _end_turn(engine_of(db), step)
                if not Result.is_ok(step):
                        break
                sizes.append(_state(step).zones.hand.size())
        return sizes


func _hand_card(state, definition_id: String) -> String:
        for raw_id in state.card_ids_in(GameConstants.ZONE_HAND):
                var card = state.get_card(String(raw_id))
                if card != null and card.definition_id == definition_id:
                        return card.card_id
        return ""


func _status(state, status_id: String) -> int:
        var status = state.find_status(state.player.entity_id, status_id)
        if status == null:
                return 0
        return int(status.stacks)


func _passive_count(state, passive_id: String, trigger_key: String) -> int:
        var key = BattleState.counter_key(GameConstants.COUNTER_SCOPE_ROUND, passive_id, trigger_key)
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        return int(counter.count)


func _hook_count(state, relic_id: String, hook_index: int) -> int:
        var key = BattleState.counter_key(
                GameConstants.COUNTER_SCOPE_BATTLE,
                "%s%s:%d" % [GameConstants.COUNTER_OWNER_RELIC_HOOK_PREFIX, relic_id, hook_index],
                GameConstants.COUNTER_TRIGGER_HOOK
        )
        var counter = state.counters.get(key)
        if counter == null:
                return 0
        return int(counter.count)


func _state(step: Dictionary):
        return step["data"]["state"]


func _ok(h, label: String, step: Dictionary) -> bool:
        if Result.is_ok(step):
                h.check(label, true)
                return true
        h.check(label, false, str(step.get("error")))
        return false


# ── 工具：局流程侧 ────────────────────────────────────────

func _create_run(svc) -> Dictionary:
        return svc.create({
                "character_id": "P01",
                "difficulty": GameConstants.DIFFICULTY_NORMAL,
                "manifest_id": "" if svc.catalog == null else svc.catalog.manifest_id,
                "seed": SEED,
        }, {})


func _rng(step: Dictionary) -> Dictionary:
        return step["data"]["rng_states"]


func _event_rng(step: Dictionary):
        var rng = RandomSourceScript.new(0)
        rng.restore_state(_rng(step))
        return rng


## 就地把入口节点改成商店并真的走一次 enter_node：库存、报价、扣钱全走真实流程。
func _shop_run(db, relics: Array) -> Dictionary:
        var svc = RunServiceScript.new(db)
        var created = _create_run(svc)
        if not Result.is_ok(created):
                return {}
        var run = _state(created)
        for raw_relic_id in relics:
                run.equip_relic(String(raw_relic_id), db.run_int("relic_slots", 6), run.relics.size() + 1)
        var entry_id := String(run.reachable_node_ids()[0])
        var node = run.find_node(entry_id)
        node.kind = RunNodeStateScript.KIND_SHOP
        var entered = svc.apply(run, {
                "type": GameConstants.ACTION_ENTER_NODE,
                "payload": {"node_id": entry_id},
        }, _rng(created))
        if not Result.is_ok(entered):
                return {}
        var state = _state(entered)
        return {"svc": svc, "run": state, "rng": _rng(entered), "view": svc.make_view(state)}


## 就地把入口节点改成事件节点、只留 event_id 可抽，再真的走一次 enter_node（候选冻结走真实代码）。
func _event_run(db, event_id: String, extra_cards: Array) -> Dictionary:
        var svc = RunServiceScript.new(db)
        var created = _create_run(svc)
        if not Result.is_ok(created):
                return {}
        var run = _state(created)
        for raw_card_id in extra_cards:
                run.add_card(String(raw_card_id), 0, "test")
        for raw_id in db.enabled_ids(GameConstants.KIND_EVENT):
                var other := String(raw_id)
                if other != event_id:
                        run.seen_event_ids[other] = true
        var entry_id := String(run.reachable_node_ids()[0])
        var node = run.find_node(entry_id)
        node.kind = RunNodeStateScript.KIND_EVENT
        var entered = svc.apply(run, {
                "type": GameConstants.ACTION_ENTER_NODE,
                "payload": {"node_id": entry_id},
        }, _rng(created))
        if not Result.is_ok(entered):
                return {}
        var state = _state(entered)
        var instance = state.current_node().context.get("event")
        if instance == null:
                return {}
        return {"svc": svc, "run": state, "rng": _rng(entered), "instance": instance, "view": svc.make_view(state)}


## 提交事件选项（走真实的 choose_event：先整体校验，再扣成本与发收益）。
func _choose(ctx: Dictionary, option_id: String, selection_ids: Array) -> Dictionary:
        var payload := {
                "event_instance_id": String((ctx["instance"] as Object).event_instance_id),
                "option_id": option_id,
        }
        if not selection_ids.is_empty():
                payload["selection_ids"] = selection_ids
        return (ctx["svc"] as Object).apply(ctx["run"], {
                "type": GameConstants.ACTION_CHOOSE_EVENT,
                "payload": payload,
        }, ctx["rng"])


func _shop_or_event_view(ctx: Dictionary) -> Dictionary:
        return ctx["view"].get("event", {})


func _shop_view(ctx: Dictionary) -> Dictionary:
        return ctx["view"].get("shop", {})


func _stock_of_kind(ctx: Dictionary, kind: String) -> Dictionary:
        for raw_stock in (_shop_view(ctx).get("stocks", []) as Array):
                var stock: Dictionary = raw_stock
                if String(stock.get("kind", "")) == kind:
                        return stock
        return {}


func _stock_price(ctx: Dictionary, kind: String) -> int:
        return int(_stock_of_kind(ctx, kind).get("price", -1))


func _first_stock_id(ctx: Dictionary, kind: String) -> String:
        return String(_stock_of_kind(ctx, kind).get("stock_id", ""))


func _card_id_of_definition(run, definition_id: String) -> String:
        for card in run.cards:
                if String(card.definition_id) == definition_id:
                        return String(card.card_id)
        return ""


## 确保手上有某定义的牌（不够就从抽牌堆白盒挪一张）。
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


func _option_view(view: Dictionary, option_id: String) -> Dictionary:
        for raw_option in (view.get("options", []) as Array):
                var option: Dictionary = raw_option
                if String(option.get("option_id", "")) == option_id:
                        return option
        return {}


func _has_definition(run, definition_id: String) -> bool:
        for card in run.cards:
                if String(card.definition_id) == definition_id:
                        return true
        return false


func _card_upgrade(run, card_id: String) -> int:
        var card = run.find_card(card_id)
        if card == null:
                return -1
        return int(card.upgrade_level)
