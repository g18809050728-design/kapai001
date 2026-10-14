extends RefCounted
##
## 战斗界面冒烟测试（src/ui/battle_screen.gd + src/ui/battle/battle_*.gd）。
##
## 覆盖：实例化场景、注入输入、断言视图与状态一致、N01 全流程打完、
## 待选期间的锁、牌堆不暴露抽牌顺序、日志来自事件、render 不改状态。
##
## 所有输入都从界面 API 进入（select_card / select_target / confirm_choice / end_turn），
## 不直接调用引擎结算，确保「能在界面里打完 N01」是真的。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const BattleScreenScript := preload("res://src/ui/battle_screen.gd")
const BattleScreenScene := preload("res://src/ui/battle_screen.tscn")

const MANIFEST := "battle_mvp"
const ENCOUNTER_ID := "N01"
const GUARD := 400

var _finished_outcome: Variant = null
var _finished_count := 0


func _on_finished(outcome: Dictionary) -> void:
    _finished_outcome = outcome
    _finished_count += 1


## N01 用 5 张牌：起手就会摸到全部，K03 必然在手，抽后弃牌一定会发生。
static func deck_plan() -> Dictionary:
    return {"K03": 1, "K01": 1, "K02": 1, "K04": 1, "K14": 1}


static func build_cards(plan: Dictionary) -> Array:
    var cards: Array = []
    var index := 0
    for definition_id in plan:
        for _i in range(int(plan[definition_id])):
            index += 1
            var card_id := "c%d" % index
            cards.append({
                "card_id": card_id,
                "definition_id": definition_id,
                "origin_card_id": card_id,
                "upgrade_level": 0,
            })
    return cards


static func battle_input() -> Dictionary:
    return {
        "battle_id": "battle#1",
        "node_id": "node#1",
        "encounter_id": ENCOUNTER_ID,
        "character_id": "P01",
        "difficulty": "normal",
        "vitality": 72,
        "max_vitality": 72,
        "cards": build_cards(deck_plan()),
        "relics": ["A01"],
        "rng_state": null,
    }


static func view_text(view: Dictionary) -> String:
    return str(view)


func run(h) -> void:
    var early_tree := Engine.get_main_loop() as SceneTree
    if early_tree != null:
        _mvp_content_section(h, early_tree)
    h.begin("界面：战斗画面（N01 全流程 / K03 抽后弃牌）")
    var db := ContentDB.new()
    var info: Dictionary = db.load(MANIFEST)
    h.check("battle_mvp 清单可载入", bool(info.get("ok", false)), db.last_error_code)
    if not bool(info.get("ok", false)):
        return
    h.problems("内容校验无问题", db.validate())
    var engine := BattleEngineScript.new(db)
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        h.check("能拿到 SceneTree（可实例化场景）", false, "Engine.get_main_loop 不是 SceneTree")
        return
    var screen = BattleScreenScene.instantiate()
    h.check("battle_screen.tscn 可实例化", screen != null)
    tree.root.add_child(screen)
    screen.battle_finished.connect(_on_finished)
    var start: Dictionary = screen.start_battle(battle_input())
    h.check("start_battle 成功", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        return
    h.check("开局不处于锁定态", not screen.is_locked())
    h.check("开局未结束", not screen.is_finished())
    # ── 视图与状态一致 ─────────────────────────────
    var view: Dictionary = screen.current_view()
    h.check("current_view 等于 engine.make_view(state)", view_text(view) == view_text(engine.make_view(screen.current_state())))
    var hand_ids: PackedStringArray = screen.hand_card_ids()
    var view_hand: Array = view.get("hand", [])
    h.eq("手牌张数一致", hand_ids.size(), view_hand.size())
    var hand_ok := true
    for index in range(view_hand.size()):
        if hand_ids[index] != String((view_hand[index] as Dictionary).get("card_id", "")):
            hand_ok = false
    h.check("手牌 widget 顺序与视图一致", hand_ok)
    var costs_ok := true
    var widgets: Array = screen.hand_widgets()
    for index in range(widgets.size()):
        var widget = widgets[index]
        if widget.cost_text() != str(int((view_hand[index] as Dictionary).get("effective_cost", -1))):
            costs_ok = false
        if String((view_hand[index] as Dictionary).get("definition_id", "")) != widget.definition_id:
            costs_ok = false
    h.check("卡面费用读数 = 视图 effective_cost", costs_ok)
    var task_widgets: Array = screen.task_widgets()
    var view_tasks: Array = view.get("tasks", [])
    h.eq("任务卡数量一致", task_widgets.size(), view_tasks.size())
    var tasks_ok := true
    for index in range(task_widgets.size()):
        if int(task_widgets[index].work_remaining) != int((view_tasks[index] as Dictionary).get("work_remaining", -1)):
            tasks_ok = false
        if int(task_widgets[index].work_max) != int((view_tasks[index] as Dictionary).get("work_max", -1)):
            tasks_ok = false
    h.check("任务卡进度 = 视图 work_remaining/work_max", tasks_ok)



    # ── render 只读：重复 render 不改变状态与视图 ─────────────
    var before_state_text := str(engine.make_view(screen.current_state()))
    screen.render(screen.current_view())
    h.check("render 不改变规则状态", before_state_text == str(engine.make_view(screen.current_state())))


    # ── 牌堆查看：不暴露抽牌顺序 ─────────────
    screen.open_deck_viewer()
    var deck = screen.deck_viewer()
    h.check("牌堆弹窗可打开", deck.is_open())
    h.eq("抽牌堆计数 = 视图 zones.draw", deck.zone_count("draw"), int((view.get("zones", {}) as Dictionary).get("draw", -1)))
    h.check("抽牌堆不暴露内容（无抽牌顺序）", deck.draw_pile_card_ids().is_empty())
    h.check("抽牌堆只显示数量说明", deck.section_titles().size() >= 3)
    screen.close_deck_viewer()
    h.check("牌堆弹窗可关闭", not deck.is_open())


    # ── 规则说明弹窗 ─────────────
    screen.open_rules()
    var rules = screen.rules_dialog()
    h.check("规则说明可打开", rules.is_open())
    h.check("规则说明分节不少于 5", rules.section_count() >= 5)
    h.check("规则说明含回合流程", rules.text_content().contains("回合流程"))
    h.check("规则说明含效果内选择", rules.text_content().contains("效果内选择"))
    screen.close_rules()


    # ── 界面驱动打完 N01 ─────────────
    var stats := _drive(screen, h)
    h.check("N01 在界面里打完（is_finished）", screen.is_finished())
    h.check("全过程是真实 UI 输入驱动", screen.submitted_actions().size() > 3, "动作数=%d" % screen.submitted_actions().size())
    h.check("覆盖 K03 的抽后弃牌待选", int(stats["choice"]) > 0, "待选次数=%d" % int(stats["choice"]))
    h.check("待选候选 = 抽牌之后的手牌", bool(stats["candidates_match"]))
    h.check("待选期间其它动作被锁死", not bool(stats["lock_broken"]))
    var outcome: Variant = screen.outcome()
    if typeof(outcome) != TYPE_DICTIONARY:
        h.check("产出 BattleOutcome", false, str(outcome))
        return
    var outcome_dict: Dictionary = outcome
    h.eq("结局为胜利", String(outcome_dict.get("result", "")), GameConstants.OUTCOME_WON)
    h.eq("胜利原因为任务完成", String(outcome_dict.get("reason", "")), GameConstants.REASON_TASKS_COMPLETED)
    h.check("battle_finished 信号已发出一次", _finished_count == 1, "次数=%d" % _finished_count)
    h.eq("信号载荷与 outcome 一致", str(_finished_outcome), str(outcome_dict))
    h.check("结束后处于锁定态", screen.is_locked())


    # ── 结算日志来自引擎事件 ─────────────
    var lines: PackedStringArray = screen.log_lines()
    h.check("日志非空", lines.size() > 0, "行数=%d" % lines.size())
    var joined := "\n".join(lines)
    h.check("日志含出牌记录", joined.contains("打出"))
    h.check("日志含弃牌待选", joined.contains("需要选择"))
    h.check("日志含战斗结束", joined.contains("战斗结束"))
    h.check("日志含 DDL 结算", joined.contains("DDL"))
    h.check("日志行数不比引擎事件多到离谱", lines.size() <= 400)


    # ── 结束后所有输入都被拒绝 ─────────────
    var before_actions: int = screen.submitted_actions().size()
    screen.select_card("c1")
    screen.end_turn()
    h.eq("结束后 select_card 不产生动作", screen.submitted_actions().size(), before_actions)
    h.check("结束后 build_action(play_card) 为空", screen.build_action(GameConstants.ACTION_PLAY_CARD, {"card_id": "c1", "target_ids": []}).is_empty())
    h.check("结束后 build_action(end_turn) 为空", screen.build_action(GameConstants.ACTION_END_TURN, {"retained_card_ids": []}).is_empty())
    tree.root.remove_child(screen)
    screen.queue_free()


# ── 界面驱动：全部经界面 API，直接调引擎的地方只有断言用的 make_view ─────

func _drive(screen, h) -> Dictionary:
    var stats := {"choice": 0, "candidates_match": true, "lock_broken": false, "turns": 0}
    var guard := 0
    while not screen.is_finished() and guard < GUARD:
        guard += 1
        if screen.is_locked():
            stats["choice"] = int(stats["choice"]) + 1
            _resolve_choice(screen, stats)
            continue
        if _play_one(screen):
            continue
        stats["turns"] = int(stats["turns"]) + 1
        screen.end_turn()
    h.check("界面驱动未触发保护上限", guard < GUARD, "循环 %d 次" % guard)
    return stats


## 待选期间：只允许确认选择，其它动作必须拿不到动作。
func _resolve_choice(screen, stats: Dictionary) -> void:
    var view: Dictionary = screen.current_view()
    var pending: Variant = view.get("pending_choice")
    if typeof(pending) != TYPE_DICTIONARY:
        return
    var candidates: Array = (pending as Dictionary).get("candidates", [])
    if candidates.is_empty():
        stats["candidates_match"] = false
        return
    var hand_ids := PackedStringArray()
    for raw in (view.get("hand", []) as Array):
        hand_ids.append(String((raw as Dictionary).get("card_id", "")))
    var candidate_ids := PackedStringArray()
    for raw in candidates:
        candidate_ids.append(String((raw as Dictionary).get("id", "")))
    if candidate_ids != hand_ids:
        stats["candidates_match"] = false
    if not screen.build_action(GameConstants.ACTION_PLAY_CARD, {"card_id": candidate_ids[0], "target_ids": []}).is_empty():
        stats["lock_broken"] = true
    if not screen.build_action(GameConstants.ACTION_END_TURN, {}).is_empty():
        stats["lock_broken"] = true
    screen.confirm_choice([candidate_ids[0]])


## 尝试出一张牌：返回 true 表示确实提交了一个动作（状态已前进）。
func _play_one(screen) -> bool:
    var before: int = screen.submitted_actions().size()
    var view: Dictionary = screen.current_view()
    for raw in (view.get("hand", []) as Array):
        var entry: Dictionary = raw
        if not bool(entry.get("playable", false)):
            continue
        screen.select_card(String(entry.get("card_id", "")))
        if screen.submitted_actions().size() > before or screen.is_locked():
            return true
        if screen.selection_mode() == BattleScreenScript.MODE_CARD_TARGET:
            var tasks: Array = screen.current_view().get("tasks", [])
            for raw_task in tasks:
                var task_id := String((raw_task as Dictionary).get("task_id", ""))
                screen.select_target(task_id)
                if screen.submitted_actions().size() > before or screen.is_locked():
                    return true
        screen.cancel_selection()
    return false



# ── 出厂 mvp 清单（真实局流程用的那份）也要能开战 ─────

static func _input_with_plan(plan: Dictionary, vitality: int, max_vitality: int) -> Dictionary:
    var input := battle_input()
    input["cards"] = build_cards(plan)
    input["vitality"] = vitality
    input["max_vitality"] = max_vitality
    return input


static func _find_hand(screen, definition_id: String) -> String:
    for raw in (screen.current_view().get("hand", []) as Array):
        var entry: Dictionary = raw
        if String(entry.get("definition_id", "")) == definition_id:
            return String(entry.get("card_id", ""))
    return ""


static func _widget_of(screen, card_id: String):
    for raw in screen.hand_widgets():
        if String(raw.card_id) == card_id:
            return raw
    return null


func _mvp_content_section(h, tree) -> void:
    h.begin("界面：出厂 mvp 清单下的牌堆（精力代价 / 新牌）")
    var db := ContentDB.new()
    var info: Dictionary = db.load(GameConstants.MANIFEST_MVP)
    h.check("mvp 清单可载入", bool(info.get("ok", false)), db.last_error_code)
    if not bool(info.get("ok", false)):
        return
    h.check("mvp 清单启用 K10（精力代价牌）", db.is_enabled(GameConstants.KIND_CARD, "K10"))
    var plan := {"K10": 1, "K01": 1, "K02": 1, "K05": 1, "K07": 1}
    # 故意不 set_engine：让界面自己挑清单，验证默认清单与出厂局流程一致
    var screen = BattleScreenScene.instantiate()
    tree.root.add_child(screen)
    var start: Dictionary = screen.start_battle(_input_with_plan(plan, 72, 72))
    h.check("含 K10/K05/K07 的牌堆能开战", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        tree.root.remove_child(screen)
        screen.queue_free()
        return
    h.eq("界面默认清单就是出厂 mvp", screen.manifest_id, GameConstants.MANIFEST_MVP)
    var k10_id := _find_hand(screen, "K10")
    h.check("K10 在起手", not k10_id.is_empty())
    var widget = _widget_of(screen, k10_id)
    if widget == null:
        h.check("能拿到 K10 卡面", false)
    else:
        h.check("K10 卡面单列精力代价", widget.vitality_cost_text().contains("4"), widget.vitality_cost_text())
        h.check("K10 提示词含精力说明", widget.tooltip_text.contains("精力"), widget.tooltip_text)
    var vitality_before := int((screen.current_view().get("player", {}) as Dictionary).get("vitality", 0))
    var focus_before := int((screen.current_view().get("player", {}) as Dictionary).get("focus", 0))
    screen.select_card(k10_id)
    h.eq("K10 成功提交", screen.submitted_actions().size(), 1)
    var after: Dictionary = screen.current_view()
    h.eq("K10 支付 4 精力", int((after.get("player", {}) as Dictionary).get("vitality", 0)), vitality_before - 4)
    h.eq("K10 获得 2 专注", int((after.get("player", {}) as Dictionary).get("focus", 0)), focus_before + 2)
    _mvp_low_vitality_part(h, tree, plan)
    tree.root.remove_child(screen)
    screen.queue_free()


func _mvp_low_vitality_part(h, tree, plan: Dictionary) -> void:
    var low = BattleScreenScene.instantiate()
    tree.root.add_child(low)
    var low_start: Dictionary = low.start_battle(_input_with_plan(plan, 4, 72))
    h.check("低精力开局成功", Result.is_ok(low_start), str(low_start.get("error")))
    if not Result.is_ok(low_start):
        tree.root.remove_child(low)
        low.queue_free()
        return
    var low_k10 := _find_hand(low, "K10")
    var view_before := view_text(low.current_view())
    low.select_card(low_k10)
    h.eq("精力不足时不出牌", low.submitted_actions().size(), 0)
    h.check("精力不足时界面没被锁死", not low.is_locked())
    h.check("提示说明是精力不足", low.hint_text().contains("精力不足"), low.hint_text())
    h.check("被拒绝后视图不变", view_before == view_text(low.current_view()))
    tree.root.remove_child(low)
    low.queue_free()
