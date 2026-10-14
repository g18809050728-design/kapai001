extends RefCounted
##
## 战斗界面：效果内选择（K03 抽后弃牌）、目标选择与取消、换班、动画不变性。
##
## 关心三件事：
##   1. 待选期间除「确认选择」外的一切入口都被锁死，且非法确认不改状态；
##   2. 目标选择可选可取消，取消不提交任何动作；
##   3. 关闭 / 加速动画不改变任何结算结果（视图、日志、结局逐项相等）。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")
const ContentDB := preload("res://src/content/content_db.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const BattleScreenScript := preload("res://src/ui/battle_screen.gd")
const BattleScreenScene := preload("res://src/ui/battle_screen.tscn")
const AnimatorScript := preload("res://src/ui/battle/battle_event_animator.gd")

const MANIFEST := "battle_mvp"
const GUARD := 400

var _finished_outcome: Variant = null


func _on_finished(outcome: Dictionary) -> void:
    _finished_outcome = outcome


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


static func battle_input(plan: Dictionary, relics: Array = ["A01"]) -> Dictionary:
    return {
        "battle_id": "battle#1",
        "node_id": "node#1",
        "encounter_id": "N01",
        "character_id": "P01",
        "difficulty": "normal",
        "vitality": 200,
        "max_vitality": 200,
        "cards": build_cards(plan),
        "relics": relics,
        "rng_state": null,
    }


static func view_text(view: Dictionary) -> String:
    return str(view)


func run(h) -> void:
    h.begin("界面：效果内选择 / 目标取消 / 换班 / 动画不变性")
    var db := ContentDB.new()
    var info: Dictionary = db.load(MANIFEST)
    h.check("battle_mvp 清单可载入", bool(info.get("ok", false)), db.last_error_code)
    if not bool(info.get("ok", false)):
        return
    h.problems("内容校验无问题", db.validate())
    var engine := BattleEngineScript.new(db)
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        h.check("能拿到 SceneTree", false)
        return
    _animator_section(h, tree)
    _k03_section(h, tree, engine)
    _target_section(h, tree, engine)
    _replace_section(h, tree, engine)
    _invariance_section(h, tree, engine)
    _resume_section(h, tree, engine)


func _new_screen(tree, engine):
    var screen = BattleScreenScene.instantiate()
    tree.root.add_child(screen)
    screen.set_engine(engine)
    screen.prepare()
    return screen


func _drop_screen(tree, screen) -> void:
    tree.root.remove_child(screen)
    screen.queue_free()


static func _hand_ids(screen) -> PackedStringArray:
    var out := PackedStringArray()
    for raw in (screen.current_view().get("hand", []) as Array):
        out.append(String((raw as Dictionary).get("card_id", "")))
    return out


# ── 动画器本体：只做播放节奏，不碰任何状态 ─────

func _animator_section(h, tree) -> void:
    h.begin("界面：事件动画队列（异步播放，不参与结算）")
    var animator = AnimatorScript.new()
    tree.root.add_child(animator)
    animator.base_delay = 0.2
    animator.speed_scale = 1.0
    animator.enqueue([{"type": "a"}, {"type": "b"}, {"type": "c"}])
    h.eq("入队后待播 3 条", animator.pending_count(), 3)
    h.eq("尚未推进时一条都没播", animator.played_count(), 0)
    animator.advance(0.01)
    h.eq("一帧只播 1 条（异步，不一次性播完）", animator.played_count(), 1)
    h.eq("播放数 + 待播数守恒", animator.played_count() + animator.pending_count(), 3)
    animator.advance(0.01)
    h.eq("未到播放间隔则不播", animator.played_count(), 1)
    animator.speed_scale = 100.0
    animator.advance(0.01)
    h.eq("加速后一帧播完剩余", animator.pending_count(), 0)
    h.eq("加速后总播放数不变", animator.played_count(), 3)
    animator.enqueue([{"type": "d"}])
    animator.set_animation_enabled(false)
    h.eq("关闭动画后立即播完", animator.pending_count(), 0)
    h.eq("关闭动画不影响播放计数", animator.played_count(), 4)
    animator.enqueue([{"type": "e"}, {"type": "f"}])
    h.eq("关闭动画时入队即播", animator.pending_count(), 0)
    animator.set_animation_enabled(true)
    animator.clear()
    h.eq("clear 清空待播队列", animator.pending_count(), 0)
    tree.root.remove_child(animator)
    animator.queue_free()


# ── K03：抽 2 弃 1 的效果内选择 ─────

func _k03_section(h, tree, engine) -> void:
    h.begin("界面：K03 抽后弃牌待选（锁定 / 候选 / 非法确认）")
    var plan := {"K03": 1, "K01": 4, "K02": 4, "K04": 2, "K14": 1}
    var screen = _new_screen(tree, engine)
    var start: Dictionary = screen.start_battle(battle_input(plan))
    h.check("开局成功", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        _drop_screen(tree, screen)
        return
    var ready := false
    var guard := 0
    while not screen.is_finished() and not ready and guard < 40:
        guard += 1
        ready = _k03_ready(screen)
        if not ready:
            screen.end_turn()
    h.check("等到「K03 在手且抽牌堆至少 2 张」", ready, "转发轮数=%d" % guard)
    if not ready:
        _drop_screen(tree, screen)
        return
    var hand_before := _hand_ids(screen)
    var draw_before := int((screen.current_view().get("zones", {}) as Dictionary).get("draw", 0))
    var k03_id := _find_card(screen, "K03")
    screen.select_card(k03_id)
    h.check("打出 K03 后进入锁定态", screen.is_locked())
    var pending: Variant = screen.current_view().get("pending_choice")
    h.check("产生 pending_choice", typeof(pending) == TYPE_DICTIONARY)
    if typeof(pending) != TYPE_DICTIONARY:
        _drop_screen(tree, screen)
        return
    var pending_dict: Dictionary = pending
    var choice_id := String(pending_dict.get("choice_id", ""))
    h.eq("待选类型是弃牌", String(pending_dict.get("kind", "")), "discard")
    h.eq("min_count = 1", int(pending_dict.get("min_count", -1)), 1)
    h.eq("max_count = 1", int(pending_dict.get("max_count", -1)), 1)
    var candidates: Array = pending_dict.get("candidates", [])
    var candidate_ids := PackedStringArray()
    for raw in candidates:
        candidate_ids.append(String((raw as Dictionary).get("id", "")))
    var hand_now := _hand_ids(screen)
    h.eq("候选 = 抽牌之后的手牌（含新抽到的牌）", str(candidate_ids), str(hand_now))
    var new_cards := 0
    for candidate_id in candidate_ids:
        if not hand_before.has(candidate_id):
            new_cards += 1
    h.check("候选里确实有新抽到的牌", new_cards > 0, "新牌 %d 张" % new_cards)
    h.check("待选期间视图仍与引擎一致", view_text(screen.current_view()) == view_text(engine.make_view(screen.current_state())))
    var locks: Dictionary = screen.lock_snapshot()
    h.check("待选期间结束回合禁用", bool(locks["end_turn"]))
    h.check("待选期间牌堆按钮禁用", bool(locks["deck"]))
    h.check("待选期间规则按钮禁用", bool(locks["rules"]))
    h.check("待选期间动画开关禁用", bool(locks["anim"]))
    h.check("待选期间取消选择禁用", bool(locks["cancel"]))
    h.check("待选期间手牌全部禁用", bool(locks["cards_disabled"]))

    screen.open_deck_viewer()
    h.check("待选期间不能打开牌堆", not screen.deck_viewer().is_open())
    screen.open_rules()
    h.check("待选期间不能打开规则说明", not screen.rules_dialog().is_open())
    screen.select_card(k03_id)
    h.check("待选期间点手牌无效（仍锁定）", screen.is_locked())
    screen.end_turn()
    h.check("待选期间点结束回合无效（仍锁定）", screen.is_locked())
    h.check("待选期间 build_action(play_card) 为空", screen.build_action(GameConstants.ACTION_PLAY_CARD, {"card_id": k03_id, "target_ids": []}).is_empty())
    h.check("待选期间 build_action(end_turn) 为空", screen.build_action(GameConstants.ACTION_END_TURN, {}).is_empty())
    h.check("待选期间 build_action(set_ally_target) 为空", screen.build_action(GameConstants.ACTION_SET_ALLY_TARGET, {"unit_id": "u", "task_id": "t"}).is_empty())
    var confirm_draft: Dictionary = screen.build_action(GameConstants.ACTION_CONFIRM_CHOICE, {"choice_id": choice_id, "selected_ids": [candidate_ids[0]]})
    h.check("待选期间 confirm_choice 仍可构造", not confirm_draft.is_empty())
    h.eq("confirm_choice 动作类型", String(confirm_draft.get("type", "")), GameConstants.ACTION_CONFIRM_CHOICE)
    var submitted: int = screen.submitted_actions().size()
    var state_text := view_text(engine.make_view(screen.current_state()))
    screen.confirm_choice([])
    h.check("数量不足的确认被拒绝，待选保留", screen.is_locked())
    h.eq("被拒绝的确认不产生提交动作", screen.submitted_actions().size(), submitted)
    h.check("被拒绝的确认不改变状态", state_text == view_text(engine.make_view(screen.current_state())))
    screen.confirm_choice(["card-not-a-candidate"])
    h.check("非候选的确认被拒绝，待选保留", screen.is_locked())
    h.eq("非候选确认不产生提交动作", screen.submitted_actions().size(), submitted)
    screen.confirm_choice([candidate_ids[0], candidate_ids[1]])
    h.check("超过上限的确认被拒绝，待选保留", screen.is_locked())
    h.eq("超额确认不产生提交动作", screen.submitted_actions().size(), submitted)
    var discard_before := int((screen.current_view().get("zones", {}) as Dictionary).get("discard", 0))
    var log_before: int = screen.log_lines().size()
    screen.confirm_choice([candidate_ids[0]])
    h.check("合法确认后解除锁定", not screen.is_locked())
    h.check("合法确认后待选消失", screen.current_view().get("pending_choice") == null)
    h.eq("合法确认只提交一个动作", screen.submitted_actions().size(), submitted + 1)
    h.eq("提交的动作是 confirm_choice", String((screen.submitted_actions()[submitted] as Dictionary).get("type", "")), GameConstants.ACTION_CONFIRM_CHOICE)
    h.check("被弃的牌离开手牌", not _hand_ids(screen).has(candidate_ids[0]))
    h.check("弃牌堆增加了牌", int((screen.current_view().get("zones", {}) as Dictionary).get("discard", 0)) > discard_before)
    h.check("日志增加了行", screen.log_lines().size() > log_before)
    h.check("日志含「需要选择」", "\n".join(screen.log_lines()).contains("需要选择"))
    h.check("日志含「已确认选择」", "\n".join(screen.log_lines()).contains("已确认选择"))
    _drop_screen(tree, screen)


# ── 目标选择与取消 ─────

func _target_section(h, tree, engine) -> void:
    h.begin("界面：目标选择与取消（工作牌打任务）")
    var plan := {"K01": 2, "K02": 2, "K03": 1, "K04": 1, "K14": 1}
    var screen = _new_screen(tree, engine)
    var start: Dictionary = screen.start_battle(battle_input(plan))
    h.check("开局成功", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        _drop_screen(tree, screen)
        return
    var k01_id := _find_card(screen, "K01")
    h.check("手牌里有工作牌 K01（5 张牌必全在起手）", not k01_id.is_empty())
    var submitted: int = screen.submitted_actions().size()
    screen.select_card(k01_id)
    h.eq("工作牌进入目标选择模式", screen.selection_mode(), BattleScreenScript.MODE_CARD_TARGET)
    h.eq("仅选牌（还没点目标）时不提交动作", screen.submitted_actions().size(), submitted)
    h.check("提示要求选任务", screen.hint_text().contains("任务"))
    h.check("取消按钮可用", not bool(screen.lock_snapshot()["cancel"]))
    screen.cancel_selection()
    h.eq("取消后回到空闲模式", screen.selection_mode(), BattleScreenScript.MODE_NONE)
    h.eq("取消不提交任何动作", screen.submitted_actions().size(), submitted)
    h.check("取消后取消按钮禁用", bool(screen.lock_snapshot()["cancel"]))
    screen.select_card(k01_id)
    h.eq("再次选牌仍进入目标模式", screen.selection_mode(), BattleScreenScript.MODE_CARD_TARGET)
    var task_id := String(screen.task_ids()[0])
    screen.select_target(task_id)
    h.eq("点任务后提交了一个动作", screen.submitted_actions().size(), submitted + 1)
    var action: Dictionary = screen.submitted_actions()[submitted]
    h.eq("动作类型是 play_card", String(action.get("type", "")), GameConstants.ACTION_PLAY_CARD)
    h.eq("动作目标就是被点的任务", str((action.get("payload", {}) as Dictionary).get("target_ids", [])), str([task_id]))
    h.eq("提交后回到空闲模式", screen.selection_mode(), BattleScreenScript.MODE_NONE)
    h.check("提交后任务进度下降", int(screen.task_widgets()[0].work_remaining) < int(screen.current_view().get("tasks", [])[0].get("work_max", 0)))
    _drop_screen(tree, screen)


# ── 换班：单位槽满了必须选一个换下 ─────

func _replace_section(h, tree, engine) -> void:
    h.begin("界面：单位槽满时的换班选择")
    var plan := {"K43": 2, "K44": 1, "K46": 1}
    var screen = _new_screen(tree, engine)
    var start: Dictionary = screen.start_battle(battle_input(plan))
    h.check("开局成功", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        _drop_screen(tree, screen)
        return
    _play_definition(screen, "K43")
    _play_definition(screen, "K44")
    h.eq("两张合作牌后有两个单位", _unit_ids(screen).size(), 2)
    screen.end_turn()
    _play_definition(screen, "K46")
    h.eq("三张合作牌后单位槽已满", _unit_ids(screen).size(), 3)
    var duplicate_id := _find_card(screen, "K43")
    h.check("手里还有一张合作牌可打", not duplicate_id.is_empty(), "手牌=%s" % str(_hand_ids(screen)))
    if duplicate_id.is_empty():
        _drop_screen(tree, screen)
        return
    var submitted: int = screen.submitted_actions().size()
    screen.select_card(duplicate_id)
    h.eq("槽满时合作牌进入换班模式", screen.selection_mode(), BattleScreenScript.MODE_REPLACE_UNIT)
    h.eq("未选换下单位时不提交动作", screen.submitted_actions().size(), submitted)
    h.check("提示要求选换下的单位", screen.hint_text().contains("换下"))
    var units := _unit_ids(screen)
    var replace_target := units[0]
    screen.select_unit(replace_target)
    h.eq("换班后仍占满三个单位槽", _unit_ids(screen).size(), 3)
    h.check("被换下的单位已离场", not _unit_ids(screen).has(replace_target))
    h.eq("换班只提交了一个动作", screen.submitted_actions().size(), submitted + 1)
    var action: Dictionary = screen.submitted_actions()[submitted]
    h.eq("换班动作带 replace_unit_id", String((action.get("payload", {}) as Dictionary).get("replace_unit_id", "")), replace_target)
    h.eq("换班后回到空闲模式", screen.selection_mode(), BattleScreenScript.MODE_NONE)
    _drop_screen(tree, screen)


# ── 动画开关 / 加速不改变结算 ─────

func _invariance_section(h, tree, engine) -> void:
    h.begin("界面：关闭或加速动画不改变任何结算结果")
    var plan := {"K03": 1, "K01": 4, "K02": 4, "K04": 2, "K14": 1}
    var input := battle_input(plan)
    var screen_a = _new_screen(tree, engine)
    screen_a.animator.set_animation_enabled(false)
    var start_a: Dictionary = screen_a.start_battle(input.duplicate(true))
    h.check("关闭动画组开局成功", Result.is_ok(start_a), str(start_a.get("error")))
    _drive_script(screen_a, 0.0)
    var screen_b = _new_screen(tree, engine)
    screen_b.animator.set_animation_enabled(true)
    screen_b.animator.speed_scale = 50.0
    var start_b: Dictionary = screen_b.start_battle(input.duplicate(true))
    h.check("加速动画组开局成功", Result.is_ok(start_b), str(start_b.get("error")))
    _drive_script(screen_b, 0.016)
    h.check("两组都打完了", screen_a.is_finished() and screen_b.is_finished())
    h.eq("两组的输入动作序列完全一致", str(screen_a.submitted_actions()), str(screen_b.submitted_actions()))
    h.eq("两组的最终视图一致", view_text(screen_a.current_view()), view_text(screen_b.current_view()))
    h.eq("两组的结局一致", str(screen_a.outcome()), str(screen_b.outcome()))
    h.eq("两组的结算日志一致", str(screen_a.log_lines()), str(screen_b.log_lines()))
    h.eq("关闭动画时队列始终为空", screen_a.animator.pending_count(), 0)
    h.check("关闭动画时事件也已全部播放", screen_a.animator.played_count() > 0)
    screen_b.animator.drain_now()
    h.eq("加速组补播后队列清空", screen_b.animator.pending_count(), 0)
    h.eq("两组播放的事件总数一致（动画只是观看节奏）", screen_b.animator.played_count(), screen_a.animator.played_count())
    _drop_screen(tree, screen_a)
    _drop_screen(tree, screen_b)


# ── 测试用小工具 ─────

static func _find_card(screen, definition_id: String) -> String:
    for raw in (screen.current_view().get("hand", []) as Array):
        var entry: Dictionary = raw
        if String(entry.get("definition_id", "")) == definition_id and bool(entry.get("playable", false)):
            return String(entry.get("card_id", ""))
    return ""


static func _unit_ids(screen) -> PackedStringArray:
    var out := PackedStringArray()
    for raw in (screen.current_view().get("units", []) as Array):
        out.append(String((raw as Dictionary).get("unit_id", "")))
    return out


static func _k03_ready(screen) -> bool:
    var view: Dictionary = screen.current_view()
    var draw := int((view.get("zones", {}) as Dictionary).get("draw", 0))
    if draw < 2:
        return false
    return not _find_card(screen, "K03").is_empty()


func _play_definition(screen, definition_id: String) -> bool:
    var before: int = screen.submitted_actions().size()
    var card_id := _find_card(screen, definition_id)
    if card_id.is_empty():
        return false
    screen.select_card(card_id)
    if screen.submitted_actions().size() > before:
        return true
    if screen.selection_mode() == BattleScreenScript.MODE_CARD_TARGET and screen.task_ids().size() > 0:
        screen.select_target(String(screen.task_ids()[0]))
    return screen.submitted_actions().size() > before


## 确定性的界面策略：K03 优先 → 第一张可出的牌 → 结束回合。
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
            for raw_task in (screen.current_view().get("tasks", []) as Array):
                screen.select_target(String((raw_task as Dictionary).get("task_id", "")))
                if screen.submitted_actions().size() > before or screen.is_locked():
                    return true
        if screen.selection_mode() == BattleScreenScript.MODE_REPLACE_UNIT:
            var unit_ids := _unit_ids(screen)
            if unit_ids.size() > 0:
                screen.select_unit(unit_ids[0])
                if screen.submitted_actions().size() > before:
                    return true
        screen.cancel_selection()
    return false


func _drive_script(screen, tick: float) -> void:
    var guard := 0
    while not screen.is_finished() and guard < GUARD:
        guard += 1
        if tick > 0.0 and screen.animator != null:
            screen.animator.advance(tick)
        if screen.is_locked():
            var pending: Variant = screen.current_view().get("pending_choice")
            if typeof(pending) != TYPE_DICTIONARY:
                break
            var candidates: Array = (pending as Dictionary).get("candidates", [])
            if candidates.is_empty():
                break
            screen.confirm_choice([String((candidates[0] as Dictionary).get("id", ""))])
            continue
        if not _play_one(screen):
            screen.end_turn()


# ── 读档续战：同一份状态 + 同一份随机快照 → 结果一致 ─────

func _resume_section(h, tree, engine) -> void:
    h.begin("界面：读档续战（状态与随机快照一致）")
    var plan := {"K03": 1, "K01": 4, "K02": 4, "K04": 2, "K14": 1}
    var input := battle_input(plan)
    var original = _new_screen(tree, engine)
    var start: Dictionary = original.start_battle(input.duplicate(true))
    h.check("原局开局成功", Result.is_ok(start), str(start.get("error")))
    if not Result.is_ok(start):
        _drop_screen(tree, original)
        return
    _drive_rounds(original, 2)
    var saved_state = original.current_state()
    var saved_rng = original.current_rng_state()
    h.check("存档点未结束", not original.is_finished())
    var resumed = _new_screen(tree, engine)
    var resumed_result: Dictionary = resumed.resume_battle(saved_state, saved_rng)
    h.check("resume_battle 成功", Result.is_ok(resumed_result), str(resumed_result.get("error")))
    h.eq("续战视图与原局一致", view_text(resumed.current_view()), view_text(original.current_view()))
    h.eq("续战后不处于空手牌", resumed.hand_card_ids().size(), original.hand_card_ids().size())
    _drive_script(original, 0.0)
    _drive_script(resumed, 0.0)
    h.check("两边都打完了", original.is_finished() and resumed.is_finished())
    h.eq("续战结局与原局一致", str(resumed.outcome()), str(original.outcome()))
    h.eq("续战视图与原局一致（终局）", view_text(resumed.current_view()), view_text(original.current_view()))
    _drop_screen(tree, original)
    _drop_screen(tree, resumed)


## 只推进若干轮（每次「出完手上的牌再结束回合」算一轮）
func _drive_rounds(screen, rounds: int) -> void:
    for _i in range(rounds):
        if screen.is_finished():
            return
        var guard := 0
        while not screen.is_finished() and guard < 50:
            guard += 1
            if screen.is_locked():
                var pending: Variant = screen.current_view().get("pending_choice")
                if typeof(pending) != TYPE_DICTIONARY:
                    break
                var candidates: Array = (pending as Dictionary).get("candidates", [])
                if candidates.is_empty():
                    break
                screen.confirm_choice([String((candidates[0] as Dictionary).get("id", ""))])
                continue
            if not _play_one(screen):
                break
        if not screen.is_finished():
            screen.end_turn()